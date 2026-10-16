"""StepEvent structured JSON-line logging.

Matches the schema the iOS app already uses for its own run telemetry:
{id, runID, parentID, step, phase, done, total, durationMs, metadata,
error, timestamp} - one event per step. Steps used by this service:
`key.handoff`, `analysis.job`, `analysis.position`, `maia.predict`.
"""
from __future__ import annotations

import datetime
import json
import logging
import uuid
from dataclasses import dataclass, field
from typing import Any

_log = logging.getLogger("app.stepevent")


def new_id() -> str:
    return uuid.uuid4().hex


def _utcnow_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


@dataclass
class StepEvent:
    step: str
    phase: str
    run_id: str
    parent_id: str | None = None
    done: int | None = None
    total: int | None = None
    duration_ms: float | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
    error: str | None = None
    id: str = field(default_factory=new_id)
    timestamp: str = field(default_factory=_utcnow_iso)

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "runID": self.run_id,
            "parentID": self.parent_id,
            "step": self.step,
            "phase": self.phase,
            "done": self.done,
            "total": self.total,
            "durationMs": self.duration_ms,
            "metadata": self.metadata,
            "error": self.error,
            "timestamp": self.timestamp,
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), separators=(",", ":"))

    def emit(self) -> None:
        _log.info(self.to_json())
