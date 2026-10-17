from __future__ import annotations

import chess
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.jobs import JobStore
from app.main import create_app
from app.security.auth import WhoisAuthenticator
from app.security.secrets_service import SecretsService

OWNER_LOGIN = "owner@example.com"
OWNER_IP = "100.120.95.17"
NON_OWNER_IP = "100.100.100.1"


class FakeAnalysisEngine:
    """Deterministic stand-in for StockfishEngine - no real process."""

    def analyse_position(self, board: chess.Board, *, depth: int, multipv: int) -> list[dict]:
        return [
            {
                "multipv": 1,
                "depth": depth,
                "cp": 25,
                "mate": None,
                "pv": ["e2e4"] if board.turn == chess.WHITE else ["e7e5"],
            }
        ]


def make_whois_runner(*, owner_ip: str = OWNER_IP, owner_login: str = OWNER_LOGIN):
    """Fake `tailscale whois --json <ip>` runner. Only `owner_ip` resolves
    to the owner login; everything else resolves to a different user."""

    def _runner(cmd: list[str]) -> str:
        ip = cmd[-1]
        if ip == owner_ip:
            login, node = owner_login, "iphone-14-pro-max"
        else:
            login, node = "someone-else@example.com", "unknown-device"
        return (
            '{"Node": {"ComputedName": "%s"}, "UserProfile": {"LoginName": "%s"}}'
            % (node, login)
        )

    return _runner


@pytest.fixture
def no_engine_settings(tmp_path) -> Settings:
    """Points stockfish/lc0 paths somewhere that doesn't exist so the
    lifespan never tries to spawn a real process during tests."""
    return Settings(
        host="127.0.0.1",
        port=0,
        stockfish_path=str(tmp_path / "no-stockfish.exe"),
        lc0_path=str(tmp_path / "no-lc0.exe"),
        maia_1100_weights_path=str(tmp_path / "no-weights.pb.gz"),
    )


@pytest.fixture
def app(no_engine_settings):
    """A fresh app with whois wired to a fake runner and a fake analysis
    engine, so no real subprocess/tailscale/stockfish is touched."""
    SecretsService.reset_for_tests(None)
    application = create_app(settings=no_engine_settings)
    application.state.whois_auth = WhoisAuthenticator(
        owner_login=OWNER_LOGIN, whois_runner=make_whois_runner()
    )
    application.state.job_store = JobStore(FakeAnalysisEngine())
    yield application
    SecretsService.reset_for_tests(None)


def make_client(application, ip: str) -> TestClient:
    """A TestClient whose ASGI scope reports `ip` as request.client.host."""
    return TestClient(application, client=(ip, 51111))


@pytest.fixture
def owner_client(app):
    with make_client(app, OWNER_IP) as c:
        yield c


@pytest.fixture
def stranger_client(app):
    with make_client(app, NON_OWNER_IP) as c:
        yield c
