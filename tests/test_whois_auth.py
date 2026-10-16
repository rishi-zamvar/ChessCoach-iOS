"""whois allow/deny, using a mocked `tailscale whois` (PLAN.md Tests)."""
from __future__ import annotations

from tests.conftest import NON_OWNER_IP, OWNER_IP


def test_given_owner_ip_when_health_called_then_200(owner_client):
    resp = owner_client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True
    assert body["service"] == "chesscoach-server"


def test_given_non_owner_ip_when_health_called_then_403(stranger_client):
    resp = stranger_client.get("/health")
    assert resp.status_code == 403


def test_given_unresolvable_ip_when_health_called_then_403(app):
    from tests.conftest import make_client

    with make_client(app, "100.64.1.1") as client:
        # "100.64.1.1" isn't the configured owner_ip in the fake runner,
        # so it resolves to a different (non-owner) login - still 403.
        resp = client.get("/health")
        assert resp.status_code == 403


def test_given_whois_infra_failure_when_health_called_then_503(app):
    from tests.conftest import make_client

    def _raising_runner(cmd: list[str]) -> str:
        raise TimeoutError("tailscale whois timed out")

    from app.security.auth import WhoisAuthenticator

    app.state.whois_auth = WhoisAuthenticator(whois_runner=_raising_runner)
    with make_client(app, OWNER_IP) as client:
        resp = client.get("/health")
        assert resp.status_code == 503
        assert resp.headers.get("retry-after") == "2"
