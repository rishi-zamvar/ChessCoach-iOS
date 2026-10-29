"""In-app feedback: genuine installs send reports (with an optional screenshot) and read back their status."""
from __future__ import annotations

import base64
import json
import uuid

from public_app import feedback as feedback_mod
from public_app import main as public_main
from tests.test_public_app import FakeApple, apple, client, post, register  # noqa: F401 (fixtures)

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 2000 + b"\xff\xd9"


def report(**overrides) -> dict:
    body = {
        "id": str(uuid.uuid4()),
        "category": "bug",
        "text": "Cannot progress beyond this page.",
        "screen": "today",
        "context": {"plan_done": True, "block": "own", "fen": "8/8/8/8/8/8/8/K6k w - - 0 1"},
        "breadcrumbs": ["screen.view today", "plan.block_empty own"],
        "build": "62",
        "app_version": "0.9.0",
        "screenshot": base64.b64encode(JPEG).decode(),
    }
    body.update(overrides)
    return body


def get(client, apple, path: str):
    return client.get(path, headers=apple.headers("GET", path))


def test_given_genuine_install_when_sending_feedback_then_stored_and_listed_as_received(client, apple, tmp_path):
    register(client, apple)
    r = post(client, apple, "/v1/feedback", report())
    assert r.status_code == 200
    listed = get(client, apple, "/v1/feedback").json()["reports"]
    assert len(listed) == 1
    assert listed[0]["status"] == "received" and listed[0]["category"] == "bug"
    assert listed[0]["text"].startswith("Cannot progress")
    shots = list((tmp_path / "public" / "feedback").glob("*.jpg"))
    assert len(shots) == 1 and shots[0].read_bytes() == JPEG


def test_given_retry_with_same_id_when_sending_then_stored_once(client, apple):
    register(client, apple)
    body = report()
    assert post(client, apple, "/v1/feedback", body).status_code == 200
    assert post(client, apple, "/v1/feedback", body).status_code == 200
    assert len(get(client, apple, "/v1/feedback").json()["reports"]) == 1


def test_given_two_devices_when_listing_then_each_sees_only_its_own(client, apple):
    register(client, apple)
    post(client, apple, "/v1/feedback", report(text="mine"))
    other = FakeApple()
    other.root_key, other.root, other.inter_key, other.inter = apple.root_key, apple.root, apple.inter_key, apple.inter
    register(client, other)
    assert get(client, other, "/v1/feedback").json()["reports"] == []


def test_given_junk_when_sending_then_refused(client, apple):
    register(client, apple)
    assert post(client, apple, "/v1/feedback", report(category="spam")).status_code == 422
    assert post(client, apple, "/v1/feedback", report(text="x" * 5000)).status_code == 422
    assert post(client, apple, "/v1/feedback", report(id="../etc/passwd")).status_code == 422
    assert post(client, apple, "/v1/feedback", report(breadcrumbs=["x"] * 80)).status_code == 422
    not_jpeg = base64.b64encode(b"<svg>hi</svg>").decode()
    assert post(client, apple, "/v1/feedback", report(screenshot=not_jpeg)).status_code == 400


def test_given_oversized_screenshot_when_sending_then_413_but_normal_shot_fits(client, apple):
    register(client, apple)
    huge = base64.b64encode(b"\xff\xd8" + b"\x00" * (public_main.MAX_FEEDBACK_BYTES)).decode()
    assert post(client, apple, "/v1/feedback", report(screenshot=huge)).status_code == 413
    ok = base64.b64encode(b"\xff\xd8" + b"\x00" * 300_000 + b"\xff\xd9").decode()
    assert post(client, apple, "/v1/feedback", report(screenshot=ok)).status_code == 200


def test_given_no_attestation_when_sending_feedback_then_401(client):
    body = json.dumps(report()).encode()
    assert client.post("/v1/feedback", content=body, headers={"content-type": "application/json"}).status_code in (400, 401)


def test_given_owner_marks_fixed_when_listing_then_status_and_build_show(client, apple, tmp_path):
    register(client, apple)
    body = report()
    post(client, apple, "/v1/feedback", body)
    store = feedback_mod.FeedbackStore(tmp_path / "public")
    store.set_status(body["id"], "fixed", fixed_in_build="63")
    listed = get(client, apple, "/v1/feedback").json()["reports"][0]
    assert listed["status"] == "fixed" and listed["fixed_in_build"] == "63"
    assert [r["id"] for r in store.unnotified()] == [body["id"]]
    store.mark_notified(body["id"])
    assert store.unnotified() == []
