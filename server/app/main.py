"""FastAPI app factory for chesscoach-server.

Endpoints per PLAN.md: /health, /key, /analysis/jobs (POST),
/analysis/jobs/{job_id} (GET), /maia/predict (POST). Every endpoint is
whois-gated (owner login only, no bearer token).
"""
from __future__ import annotations

import hashlib
import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import Depends, FastAPI, HTTPException, Request

from app import models
from app.config import Settings, engine_available, get_settings
from app.engines.maia import MaiaEngine
from app.engines.stockfish import StockfishEngine
from app.jobs import JobStore
from app.security import log_redaction
from app.security.auth import WhoisAuthenticator
from app.security.secrets_service import SecretsService
from app.step_events import StepEvent, new_id

_log = logging.getLogger("app.main")


def key_id_for(key: str) -> str:
    """First 8 hex of sha256(key) - the ONLY form of the key allowed
    in logs (PLAN.md hard requirement #3)."""
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:8]


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings: Settings = app.state.settings
    if engine_available(settings.stockfish_path):
        app.state.stockfish_engine.start()
        _log.info("stockfish engine started: %s", settings.stockfish_path)
    else:
        _log.warning("stockfish not found at %s; /analysis/jobs will fail", settings.stockfish_path)
    app.state.job_store.start()
    try:
        yield
    finally:
        await app.state.job_store.stop()
        app.state.stockfish_engine.stop()


def create_app(*, settings: Settings | None = None) -> FastAPI:
    log_redaction.install()
    settings = settings or get_settings()

    app = FastAPI(title="chesscoach-server", version="0.1.0", lifespan=_lifespan)
    app.state.settings = settings
    app.state.whois_auth = WhoisAuthenticator()
    app.state.stockfish_engine = StockfishEngine(
        settings.stockfish_path, threads=settings.stockfish_threads
    )
    app.state.job_store = JobStore(app.state.stockfish_engine)
    app.state.maia_engine = MaiaEngine(settings.lc0_path, settings.maia_1100_weights_path)

    def require_owner(request: Request) -> None:
        request.app.state.whois_auth(request)

    @app.get("/health", response_model=models.HealthResponse)
    def health(request: Request, _: None = Depends(require_owner)) -> models.HealthResponse:
        s: Settings = request.app.state.settings
        return models.HealthResponse(
            ok=True,
            engines={
                "stockfish": engine_available(s.stockfish_path),
                "maia": engine_available(s.lc0_path) and engine_available(s.maia_1100_weights_path),
            },
        )

    @app.get("/key")
    def get_key(request: Request, _: None = Depends(require_owner)):
        s: Settings = request.app.state.settings
        anthropic_key = SecretsService.instance().get_anthropic_key()
        if not anthropic_key:
            raise HTTPException(status_code=503, detail={"error": "no_key"})
        kid = key_id_for(anthropic_key)
        StepEvent(
            step="key.handoff", phase="done", run_id=new_id(), metadata={"key_id": kid}
        ).emit()
        return models.KeyResponse(
            key=anthropic_key, key_id=kid, monthly_cap_usd=s.monthly_cap_usd
        )

    @app.post("/analysis/jobs", response_model=models.AnalysisJobAccepted)
    async def create_job(
        request: Request,
        body: models.AnalysisJobRequest,
        _: None = Depends(require_owner),
    ) -> models.AnalysisJobAccepted:
        store: JobStore = request.app.state.job_store
        job = await store.submit(
            job_id=body.job_id,
            game_id=body.game_id,
            pgn=body.pgn,
            user_color=body.user_color,
            depth=body.depth,
            multipv=body.multipv,
        )
        return models.AnalysisJobAccepted(job_id=job.job_id, status=job.status)

    @app.get("/analysis/jobs/{job_id}", response_model=models.AnalysisJobStatus)
    def get_job(
        request: Request, job_id: str, _: None = Depends(require_owner)
    ) -> models.AnalysisJobStatus:
        store: JobStore = request.app.state.job_store
        job = store.get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail="job not found")
        return models.AnalysisJobStatus(
            status=job.status,
            progress=models.JobProgress(done=job.done, total=job.total),
            result=job.result,
            error=job.error,
        )

    @app.post("/maia/predict", response_model=models.MaiaPredictResponse)
    def maia_predict(
        request: Request,
        body: models.MaiaPredictRequest,
        _: None = Depends(require_owner),
    ) -> models.MaiaPredictResponse:
        engine: MaiaEngine = request.app.state.maia_engine
        run_id = new_id()
        policy = engine.predict(body.fen)
        StepEvent(
            step="maia.predict", phase="done", run_id=run_id, metadata={"rating": body.rating}
        ).emit()
        return models.MaiaPredictResponse(policy=policy)

    return app


app = create_app()
