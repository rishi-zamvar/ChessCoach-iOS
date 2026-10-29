"""Delete my data + the privacy policy page (spec W7)."""
from __future__ import annotations

from public_app import feedback as feedback_mod
from tests.test_feedback import get, report
from tests.test_public_app import apple, client, post, register  # noqa: F401 (fixtures)


def test_given_reports_when_deleting_my_data_then_reports_and_screenshots_gone_and_analytics_queued(client, apple, tmp_path):
    register(client, apple)
    post(client, apple, "/v1/feedback", report())
    assert len(get(client, apple, "/v1/feedback").json()["reports"]) == 1
    r = post(client, apple, "/v1/privacy/delete", {"distinct_id": "a1b2c3d4e5f6"})
    assert r.status_code == 200 and r.json()["deleted_reports"] == 1
    assert get(client, apple, "/v1/feedback").json()["reports"] == []
    assert list((tmp_path / "public" / "feedback").glob("*.jpg")) == []
    store = feedback_mod.FeedbackStore(tmp_path / "public")
    assert [d["distinct_id"] for d in store.pending_deletions()] == ["a1b2c3d4e5f6"]


def test_given_bad_distinct_id_when_deleting_then_refused(client, apple):
    register(client, apple)
    assert post(client, apple, "/v1/privacy/delete", {"distinct_id": "../../x"}).status_code == 422


def test_given_anyone_when_opening_privacy_page_then_plain_html_policy(client):
    r = client.get("/privacy")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/html")
    assert "Knightlight" in r.text and "Delete my data" in r.text
