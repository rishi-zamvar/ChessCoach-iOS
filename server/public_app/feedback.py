"""In-app feedback reports: one SQLite table plus a JPEG per screenshot, keyed by the sending device."""
from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path

STATUSES = ("received", "fixed", "wontfix")


class FeedbackStore:
    def __init__(self, data_dir: Path) -> None:
        self.images = data_dir / "feedback"
        self.images.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(data_dir / "feedback.db", check_same_thread=False)
        self._db.execute(
            "CREATE TABLE IF NOT EXISTS feedback (id TEXT PRIMARY KEY, device TEXT, created REAL, category TEXT,"
            " text TEXT, screen TEXT, build TEXT, app_version TEXT, context TEXT, breadcrumbs TEXT,"
            " has_screenshot INTEGER, status TEXT DEFAULT 'received', fixed_in_build TEXT, notified INTEGER DEFAULT 0)")
        self._db.execute("CREATE TABLE IF NOT EXISTS deletion (distinct_id TEXT PRIMARY KEY, device TEXT, requested REAL, done INTEGER DEFAULT 0)")
        self._db.commit()
        self._lock = threading.Lock()

    def delete_device(self, device: str, distinct_id: str | None) -> int:
        """Removes a device's reports and screenshots; queues its analytics profile for deletion."""
        with self._lock:
            ids = [r[0] for r in self._db.execute("SELECT id FROM feedback WHERE device = ?", (device,)).fetchall()]
            self._db.execute("DELETE FROM feedback WHERE device = ?", (device,))
            if distinct_id:
                self._db.execute("INSERT OR REPLACE INTO deletion VALUES (?, ?, ?, 0)", (distinct_id, device, time.time()))
            self._db.commit()
        for report_id in ids:
            (self.images / f"{report_id}.jpg").unlink(missing_ok=True)
        return len(ids)

    def pending_deletions(self) -> list[dict]:
        with self._lock:
            rows = self._db.execute("SELECT distinct_id, requested FROM deletion WHERE done = 0").fetchall()
        return [{"distinct_id": d, "requested": t} for d, t in rows]

    def mark_deleted(self, distinct_id: str) -> None:
        with self._lock:
            self._db.execute("UPDATE deletion SET done = 1 WHERE distinct_id = ?", (distinct_id,))
            self._db.commit()

    def add(self, device: str, report: dict, screenshot: bytes | None) -> None:
        """Idempotent on the client's id: a retried send stores nothing new."""
        with self._lock:
            cur = self._db.execute(
                "INSERT OR IGNORE INTO feedback (id, device, created, category, text, screen, build, app_version,"
                " context, breadcrumbs, has_screenshot) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (report["id"], device, time.time(), report["category"], report["text"], report["screen"],
                 report["build"], report["app_version"], json.dumps(report["context"]),
                 json.dumps(report["breadcrumbs"]), int(screenshot is not None)))
            self._db.commit()
        if cur.rowcount == 1 and screenshot is not None:
            (self.images / f"{report['id']}.jpg").write_bytes(screenshot)

    def for_device(self, device: str, limit: int = 50) -> list[dict]:
        with self._lock:
            rows = self._db.execute(
                "SELECT id, created, category, text, screen, status, fixed_in_build FROM feedback"
                " WHERE device = ? ORDER BY created DESC LIMIT ?", (device, limit)).fetchall()
        keys = ("id", "created", "category", "text", "screen", "status", "fixed_in_build")
        return [dict(zip(keys, r)) for r in rows]

    # Owner-side (run on the PC by scripts/feedback.py, never over the network).

    def all(self, status: str | None = None) -> list[dict]:
        with self._lock:
            cur = self._db.execute(
                "SELECT * FROM feedback" + (" WHERE status = ?" if status else "") + " ORDER BY created DESC",
                (status,) if status else ())
            names = [d[0] for d in cur.description]
            return [dict(zip(names, r)) for r in cur.fetchall()]

    def set_status(self, report_id: str, status: str, fixed_in_build: str | None = None) -> None:
        if status not in STATUSES:
            raise ValueError(f"status must be one of {STATUSES}")
        with self._lock:
            self._db.execute("UPDATE feedback SET status = ?, fixed_in_build = ? WHERE id = ?", (status, fixed_in_build, report_id))
            self._db.commit()

    def unnotified(self) -> list[dict]:
        return [r for r in self.all() if not r["notified"]]

    def mark_notified(self, report_id: str) -> None:
        with self._lock:
            self._db.execute("UPDATE feedback SET notified = 1 WHERE id = ?", (report_id,))
            self._db.commit()
