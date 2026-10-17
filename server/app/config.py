"""Runtime configuration. Env-var driven with sensible defaults so the
test suite doesn't need a real .env."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _env_path(name: str, default: str) -> str:
    return os.environ.get(name, default)


def _env_int(name: str, default: int) -> int:
    val = os.environ.get(name)
    if val is None:
        return default
    try:
        return int(val)
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    host: str = "100.91.236.115"
    port: int = 8810
    monthly_cap_usd: int = 80
    stockfish_path: str = r"C:\ZeeCloud\Tools\stockfish\stockfish.exe"
    lc0_path: str = r"C:\ZeeCloud\Tools\lc0\lc0.exe"
    maia_1100_weights_path: str = r"C:\ZeeCloud\Tools\lc0\weights\maia-1100.pb.gz"
    stockfish_threads: int = max(1, (os.cpu_count() or 4) - 2)


def get_settings() -> Settings:
    return Settings(
        host=_env_path("CHESSCOACH_HOST", "100.91.236.115"),
        port=_env_int("CHESSCOACH_PORT", 8810),
        monthly_cap_usd=_env_int("CHESSCOACH_MONTHLY_CAP_USD", 80),
        stockfish_path=_env_path(
            "CHESSCOACH_STOCKFISH_PATH", r"C:\ZeeCloud\Tools\stockfish\stockfish.exe"
        ),
        lc0_path=_env_path("CHESSCOACH_LC0_PATH", r"C:\ZeeCloud\Tools\lc0\lc0.exe"),
        maia_1100_weights_path=_env_path(
            "CHESSCOACH_MAIA_1100_WEIGHTS",
            r"C:\ZeeCloud\Tools\lc0\weights\maia-1100.pb.gz",
        ),
        stockfish_threads=max(1, (os.cpu_count() or 4) - 2),
    )


def engine_available(path: str) -> bool:
    return Path(path).exists()
