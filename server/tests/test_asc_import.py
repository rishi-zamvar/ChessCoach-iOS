"""TestFlight feedback lands in the same feedback table (spec W8.7)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import asc_client  # noqa: E402

from public_app.feedback import FeedbackStore

ITEM = {
    "id": "AbC123",
    "attributes": {
        "comment": "Cannot progress beyond this page. ", "deviceModel": "iPhone17_2", "osVersion": "26.6.2",
        "locale": "en-GB", "createdDate": "2026-10-28T14:51:01.706Z",
        "screenshots": [{"url": "https://tf-feedback.example/x.jpg"}],
    },
    "build_version": "43",
}


def test_given_testflight_item_when_mapped_then_feedback_row_with_build_and_device():
    row = asc_client.as_feedback_rows([ITEM])[0]
    assert row["id"] == "tf-AbC123"
    assert row["text"].startswith("Cannot progress")
    assert row["build"] == "43"
    assert row["context"]["device"] == "iPhone17_2" and row["context"]["source"] == "testflight"
    assert row["screenshot_url"].endswith("x.jpg")


def test_given_same_testflight_item_twice_when_imported_then_stored_once(tmp_path):
    store = FeedbackStore(tmp_path)
    row = asc_client.as_feedback_rows([ITEM])[0]
    for _ in range(2):
        store.add("testflight", {k: v for k, v in row.items() if k != "screenshot_url"}, None)
    assert [r["id"] for r in store.all()] == ["tf-AbC123"]
