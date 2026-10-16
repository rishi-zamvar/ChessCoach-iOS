"""Long-lived Stockfish process wrapper (python-chess UCI engine)."""
from __future__ import annotations

from typing import Protocol

import chess
import chess.engine


class AnalysisEngine(Protocol):
    def analyse_position(
        self, board: chess.Board, *, depth: int, multipv: int
    ) -> list[dict]: ...


class StockfishEngine:
    """One long-lived UCI process, `Threads` = cores - 2 (PLAN.md notes)."""

    def __init__(self, path: str, *, threads: int) -> None:
        self._path = path
        self._threads = threads
        self._engine: chess.engine.SimpleEngine | None = None

    def start(self) -> None:
        self._engine = chess.engine.SimpleEngine.popen_uci(self._path)
        self._engine.configure({"Threads": self._threads})

    def stop(self) -> None:
        if self._engine is not None:
            self._engine.quit()
            self._engine = None

    @property
    def is_running(self) -> bool:
        return self._engine is not None

    def analyse_position(
        self, board: chess.Board, *, depth: int, multipv: int
    ) -> list[dict]:
        if self._engine is None:
            raise RuntimeError("stockfish engine not started")
        infos = self._engine.analyse(
            board, chess.engine.Limit(depth=depth), multipv=multipv
        )
        if isinstance(infos, dict):
            infos = [infos]
        lines: list[dict] = []
        for info in infos:
            pv = info.get("pv", [])
            score = info["score"].pov(board.turn)
            cp = None if score.is_mate() else score.score()
            mate = score.mate() if score.is_mate() else None
            lines.append(
                {
                    "multipv": info.get("multipv", 1),
                    "depth": info.get("depth", depth),
                    "cp": cp,
                    "mate": mate,
                    "pv": [m.uci() for m in pv],
                }
            )
        return lines
