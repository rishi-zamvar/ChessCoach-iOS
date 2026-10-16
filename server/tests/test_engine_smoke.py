"""A real-engine smoke test marked @pytest.mark.engine (PLAN.md Tests)."""
from __future__ import annotations

import chess
import pytest

from app.config import engine_available, get_settings
from app.engines.stockfish import StockfishEngine


@pytest.mark.engine
def test_given_real_stockfish_when_analysing_startpos_then_returns_lines():
    settings = get_settings()
    if not engine_available(settings.stockfish_path):
        pytest.skip("stockfish not installed on this host")

    engine = StockfishEngine(settings.stockfish_path, threads=settings.stockfish_threads)
    engine.start()
    try:
        lines = engine.analyse_position(chess.Board(), depth=8, multipv=2)
    finally:
        engine.stop()

    assert len(lines) == 2
    for line in lines:
        assert line["pv"]
        assert line["cp"] is not None or line["mate"] is not None
