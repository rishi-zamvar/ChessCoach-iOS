from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    ok: bool
    service: str = "chesscoach-server"
    version: str = "0.1.0"
    engines: dict[str, bool]


class KeyResponse(BaseModel):
    key: str
    key_id: str
    monthly_cap_usd: int


class KeyErrorResponse(BaseModel):
    error: Literal["no_key"] = "no_key"


class AnalysisJobRequest(BaseModel):
    job_id: str
    game_id: str
    pgn: str
    user_color: Literal["white", "black"]
    depth: int = Field(default=22, ge=1, le=60)
    multipv: int = Field(default=3, ge=1, le=10)


class AnalysisJobAccepted(BaseModel):
    job_id: str
    status: Literal["queued", "running", "done", "failed"]


class EngineLine(BaseModel):
    multipv: int
    depth: int
    cp: int | None = None
    mate: int | None = None
    pv: list[str]


class PositionResult(BaseModel):
    fen: str
    lines: list[EngineLine]


class AnalysisResult(BaseModel):
    positions: list[PositionResult]


class JobProgress(BaseModel):
    done: int
    total: int


class AnalysisJobStatus(BaseModel):
    status: Literal["queued", "running", "done", "failed"]
    progress: JobProgress
    result: AnalysisResult | None = None
    error: str | None = None


class MaiaPredictRequest(BaseModel):
    fen: str
    rating: int = Field(default=1100)


class MaiaPredictResponse(BaseModel):
    policy: dict[str, float]
