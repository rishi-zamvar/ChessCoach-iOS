"""Job idempotency and the progress shape, with a fake engine (PLAN.md Tests)."""
from __future__ import annotations

import time

SIMPLE_PGN = "1. e4 e5 2. Nf3 Nc6 *"


def _wait_until_done(client, job_id: str, *, timeout_s: float = 5.0) -> dict:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        resp = client.get(f"/analysis/jobs/{job_id}")
        assert resp.status_code == 200
        body = resp.json()
        if body["status"] in ("done", "failed"):
            return body
        time.sleep(0.05)
    raise AssertionError(f"job {job_id} did not finish within {timeout_s}s")


def test_given_new_job_when_submitted_twice_with_same_id_then_idempotent(owner_client):
    payload = {
        "job_id": "job-idempotent-1",
        "game_id": "g1",
        "pgn": SIMPLE_PGN,
        "user_color": "white",
        "depth": 10,
        "multipv": 1,
    }
    first = owner_client.post("/analysis/jobs", json=payload)
    assert first.status_code == 200
    assert first.json()["job_id"] == "job-idempotent-1"

    different_depth_payload = {**payload, "depth": 30}
    second = owner_client.post("/analysis/jobs", json=different_depth_payload)
    assert second.status_code == 200
    assert second.json()["job_id"] == "job-idempotent-1"

    done = _wait_until_done(owner_client, "job-idempotent-1")
    # The second submit must NOT have restarted the job at depth=30;
    # the original depth=10 request owns this job_id.
    assert done["status"] == "done"
    assert done["result"]["positions"][0]["lines"][0]["depth"] == 10


def test_given_job_when_running_then_progress_shape_matches_moves(owner_client):
    payload = {
        "job_id": "job-progress-1",
        "game_id": "g2",
        "pgn": SIMPLE_PGN,
        "user_color": "white",
        "depth": 8,
        "multipv": 1,
    }
    resp = owner_client.post("/analysis/jobs", json=payload)
    assert resp.status_code == 200

    done = _wait_until_done(owner_client, "job-progress-1")
    assert done["progress"]["done"] == done["progress"]["total"]
    # 4 plies (e4 e5 Nf3 Nc6) + the starting position = 5 positions.
    assert done["progress"]["total"] == 5
    assert len(done["result"]["positions"]) == 5
    for position in done["result"]["positions"]:
        assert "fen" in position
        assert position["lines"][0]["pv"]


def test_given_unknown_job_id_when_queried_then_404(owner_client):
    resp = owner_client.get("/analysis/jobs/does-not-exist")
    assert resp.status_code == 404
