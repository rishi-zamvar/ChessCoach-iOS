"""Maia move-probability predictions via lc0 + maia-1100 weights.

PLAN.md ("Notes"): GTX 980 Ti is sm_52, unsupported by current PyTorch,
so this falls back to lc0 with the maia-1 weights (`go nodes 1`,
`VerboseMoveStats`) rather than a GPU/ONNX Maia-2 path.

lc0 is spawned per-request (predictions are infrequent relative to
Stockfish's long-lived analysis process) with a short timeout.
`_runner` is the injectable seam so tests don't need a real lc0.exe.
"""
from __future__ import annotations

import re
import subprocess
import time
from typing import Callable

_MOVE_P_RE = re.compile(
    r"^info string\s+(?P<move>[a-h][1-8][a-h][1-8][qrbn]?)\b.*?\(P:\s*(?P<pct>[\d.]+)%\)"
)

LC0_TIMEOUT_SEC = 10.0


def _default_runner(cmd: list[str], stdin_text: str) -> str:
    """Drive lc0 interactively: `go` starts an async search, so `quit`
    must wait for `bestmove` on stdout - sending it eagerly (e.g. via
    `subprocess.run(input=...)`, which pipes everything at once) races
    ahead of the search and kills lc0 before it reports any moves."""
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    output_lines: list[str] = []
    try:
        assert proc.stdin is not None and proc.stdout is not None
        proc.stdin.write(stdin_text)
        proc.stdin.flush()
        deadline = time.monotonic() + LC0_TIMEOUT_SEC
        while time.monotonic() < deadline:
            line = proc.stdout.readline()
            if not line:
                break
            output_lines.append(line)
            if line.startswith("bestmove"):
                break
    finally:
        try:
            if proc.stdin is not None:
                proc.stdin.write("quit\n")
                proc.stdin.flush()
        except Exception:  # noqa: BLE001
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
    return "".join(output_lines)


class MaiaEngine:
    def __init__(
        self,
        lc0_path: str,
        weights_path: str,
        *,
        _runner: Callable[[list[str], str], str] = _default_runner,
    ) -> None:
        self._lc0_path = lc0_path
        self._weights_path = weights_path
        self._runner = _runner

    def predict(self, fen: str, *, nodes: int = 1) -> dict[str, float]:
        """Return a policy dict {uci_move: probability}, normalized to sum to 1.

        Returns {} if lc0 produced no parseable VerboseMoveStats lines
        (caller surfaces an empty policy rather than failing the request)."""
        cmd = [
            self._lc0_path,
            f"--weights={self._weights_path}",
            "--verbose-move-stats",
        ]
        stdin_text = (
            "uci\n"
            "isready\n"
            f"position fen {fen}\n"
            f"go nodes {nodes}\n"
        )
        out = self._runner(cmd, stdin_text)
        return self._parse_policy(out)

    @staticmethod
    def _parse_policy(output: str) -> dict[str, float]:
        raw: dict[str, float] = {}
        for line in output.splitlines():
            m = _MOVE_P_RE.match(line.strip())
            if not m:
                continue
            raw[m.group("move")] = float(m.group("pct")) / 100.0
        total = sum(raw.values())
        if total <= 0:
            return {}
        return {move: p / total for move, p in raw.items()}
