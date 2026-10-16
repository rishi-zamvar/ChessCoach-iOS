"""tailscale CLI wrapper - `whois`.

Copied from dispatch/dispatch/tailscale.py (the established pattern on
this PC for resolving a tailnet peer's identity). Mocking pattern:
`whois()` accepts `_runner=...`; tests inject a stub so no real
`tailscale` binary is required.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from typing import Callable

TS_TIMEOUT_SEC = 5.0

_TAILSCALE_FALLBACK_PATHS: tuple[str, ...] = (
    r"C:\Program Files\Tailscale\tailscale.exe",
    r"C:\Program Files (x86)\Tailscale\tailscale.exe",
    "/usr/local/bin/tailscale",
    "/usr/bin/tailscale",
    "/opt/homebrew/bin/tailscale",
)


def _resolve_tailscale_bin() -> str:
    env = os.environ.get("CHESSCOACH_TAILSCALE_BIN")
    if env and os.path.exists(env):
        return env
    on_path = shutil.which("tailscale")
    if on_path:
        return on_path
    for candidate in _TAILSCALE_FALLBACK_PATHS:
        if os.path.exists(candidate):
            return candidate
    return "tailscale"


@dataclass(frozen=True)
class WhoisInfo:
    """Subset of `tailscale whois --json` fields we use for identity check."""

    node: str  # MagicDNS short name (e.g. "iphone-14-pro-max")
    user: str  # the logged-in user (e.g. "rishizamvar@...")
    role_tag: str = ""


def _default_runner(cmd: list[str]) -> str:
    resolved = list(cmd)
    if resolved and resolved[0] == "tailscale":
        resolved[0] = _resolve_tailscale_bin()
    res = subprocess.run(
        resolved, capture_output=True, text=True, timeout=TS_TIMEOUT_SEC, check=False,
    )
    if res.returncode != 0:
        raise subprocess.SubprocessError(
            f"command failed ({res.returncode}): {' '.join(resolved)}\n{res.stderr}"
        )
    return res.stdout


def whois(
    ip: str,
    *,
    _runner: Callable[[list[str]], str] = _default_runner,
) -> WhoisInfo | None:
    """Resolve a tailnet IP -> WhoisInfo. None on non-tailnet IP or error."""
    try:
        out = _runner(["tailscale", "whois", "--json", ip])
    except (FileNotFoundError, subprocess.SubprocessError):
        return None
    if not out.strip():
        return None
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    node_section = data.get("Node") or {}
    node = node_section.get("ComputedName") or ""
    if not node:
        name = node_section.get("Name") or ""
        if name:
            node = name.rstrip(".").split(".", 1)[0]
    user = (data.get("UserProfile") or {}).get("LoginName", "")
    if not node or not user:
        return None
    role_tag = ""
    caps = data.get("Caps") or []
    if isinstance(caps, list):
        tags = [c for c in caps if isinstance(c, str) and c.startswith("tag:")]
        if tags:
            role_tag = tags[0]
    return WhoisInfo(node=node, user=user, role_tag=role_tag)


def is_installed() -> bool:
    return shutil.which("tailscale") is not None
