"""chesscoach-public: the only part of the home PC that faces the internet (via Cloudflare Tunnel).

Deliberately separate from app.main: it never imports the secrets service, has no /key, binds to
127.0.0.1 only and runs as a low-privilege Windows user that can't read the secrets folder.
Every call except health and attestation needs an App Attest assertion from a genuine install
of the app; every call is rate limited and every input is capped.

Run: uvicorn public_app.main:create_public_app --factory --host 127.0.0.1 --port 8811
"""
from __future__ import annotations

import base64
import collections
import io
import os
import secrets
import sqlite3
import threading
import time
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import AsyncIterator

import chess
import chess.pgn
from fastapi import Depends, FastAPI, HTTPException, Request
from pydantic import BaseModel, Field

from app import models
from app.config import engine_available, get_settings
from app.engines.maia import MaiaEngine
from app.engines.stockfish import StockfishEngine
from app.jobs import JobStore
from public_app.attest import AppAttestVerifier, AttestError, AttestedKey

APP_ID = "373D7DZ9NM.com.rishizamvar.chesscoach"
MAX_PGN_CHARS = 20_000
MAX_PLIES = 300
MAX_DEPTH = 18
MAX_MULTIPV = 3
MAX_QUEUED_JOBS = 4


@dataclass(frozen=True)
class PublicSettings:
    data_dir: str = os.environ.get("CHESSCOACH_PUBLIC_DATA", r"C:\ProgramData\chesscoach-public")
    stockfish_threads: int = int(os.environ.get("CHESSCOACH_PUBLIC_THREADS", "2"))


class RateLimiter:
    """Sliding-window counts per key."""
    # ponytail: in memory, so limits reset when the service restarts; fine for a home PC.

    def __init__(self) -> None:
        self._hits: dict[str, collections.deque[float]] = collections.defaultdict(collections.deque)
        self._lock = threading.Lock()

    def allow(self, key: str, limit: int, per_seconds: float, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        with self._lock:
            q = self._hits[key]
            while q and q[0] <= now - per_seconds:
                q.popleft()
            if len(q) >= limit:
                return False
            q.append(now)
            return True


class KeyStore:
    """Attested public keys and their counters (no personal data: just a device key)."""

    def __init__(self, data_dir: Path) -> None:
        data_dir.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(data_dir / "attested_keys.db", check_same_thread=False)
        self._db.execute("CREATE TABLE IF NOT EXISTS keys (key_id BLOB PRIMARY KEY, pem BLOB, counter INTEGER, created REAL)")
        self._db.commit()
        self._lock = threading.Lock()

    def get(self, key_id: bytes) -> AttestedKey | None:
        with self._lock:
            row = self._db.execute("SELECT pem, counter FROM keys WHERE key_id = ?", (key_id,)).fetchone()
        return AttestedKey(key_id, row[0], row[1]) if row else None

    def add(self, key: AttestedKey) -> None:
        with self._lock:
            self._db.execute("INSERT OR REPLACE INTO keys VALUES (?, ?, ?, ?)", (key.key_id, key.public_key_pem, key.counter, time.time()))
            self._db.commit()

    def bump(self, key_id: bytes, counter: int) -> bool:
        """Stores the new counter only if it went up (atomic against concurrent requests)."""
        with self._lock:
            cur = self._db.execute("UPDATE keys SET counter = ? WHERE key_id = ? AND counter < ?", (counter, key_id, counter))
            self._db.commit()
            return cur.rowcount == 1


class RegisterRequest(BaseModel):
    key_id: str = Field(max_length=100)
    attestation: str = Field(max_length=20_000)
    challenge: str = Field(max_length=100)


class PublicJobRequest(BaseModel):
    job_id: str = Field(max_length=64, pattern=r"^[A-Za-z0-9-]+$")
    game_id: str = Field(max_length=128)
    pgn: str = Field(max_length=MAX_PGN_CHARS)
    user_color: str = Field(pattern=r"^(white|black)$")
    depth: int = Field(default=MAX_DEPTH, ge=1, le=60)
    multipv: int = Field(default=MAX_MULTIPV, ge=1, le=10)


class MaiaRequest(BaseModel):
    fen: str = Field(max_length=100)


def b64(s: str) -> bytes:
    try:
        return base64.b64decode(s, validate=True)
    except Exception as e:
        raise HTTPException(status_code=400, detail="bad base64") from e


def create_public_app(
    *, settings: PublicSettings | None = None, verifier: AppAttestVerifier | None = None,
    analysis_engine=None, maia_engine=None,
) -> FastAPI:
    settings = settings or PublicSettings()
    engine_settings = get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        sf = app.state.stockfish
        if sf is not None and engine_available(engine_settings.stockfish_path):
            sf.start()
        app.state.jobs.start()
        try:
            yield
        finally:
            await app.state.jobs.stop()
            if sf is not None:
                sf.stop()

    # No interactive docs or schema: nothing to browse.
    app = FastAPI(title="chesscoach-public", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
    app.state.stockfish = None if analysis_engine else StockfishEngine(engine_settings.stockfish_path, threads=settings.stockfish_threads)
    app.state.jobs = JobStore(analysis_engine or app.state.stockfish)
    app.state.maia = maia_engine or MaiaEngine(engine_settings.lc0_path, engine_settings.maia_1100_weights_path)
    app.state.keys = KeyStore(Path(settings.data_dir))
    app.state.verifier = verifier or AppAttestVerifier(APP_ID)
    app.state.limits = RateLimiter()
    app.state.challenges: dict[bytes, float] = {}

    def client_ip(request: Request) -> str:
        # Only cloudflared can reach 127.0.0.1, so its header is the real caller.
        return request.headers.get("cf-connecting-ip") or (request.client.host if request.client else "?")

    def limit(request: Request, key: str, n: int, per: float) -> None:
        if not request.app.state.limits.allow(key, n, per):
            raise HTTPException(status_code=429, detail="slow down", headers={"Retry-After": str(int(per))})

    async def attested(request: Request) -> bytes:
        """Verifies the App Attest assertion over method, path and body; returns the key id."""
        key_id = b64(request.headers.get("x-attest-key", ""))
        assertion = b64(request.headers.get("x-attest-assertion", ""))
        key = request.app.state.keys.get(key_id)
        if key is None:
            raise HTTPException(status_code=401, detail="unknown device")
        client_data = f"{request.method}\n{request.url.path}\n".encode() + await request.body()
        try:
            counter = request.app.state.verifier.verify_assertion(key, assertion, client_data)
        except AttestError as e:
            raise HTTPException(status_code=401, detail="invalid assertion") from e
        if not request.app.state.keys.bump(key_id, counter):
            raise HTTPException(status_code=401, detail="replayed request")
        limit(request, "key:" + key_id.hex(), 600, 3600)
        return key_id

    @app.get("/v1/health")
    def health() -> dict:
        return {"ok": True}

    @app.post("/v1/attest/challenge")
    def challenge(request: Request) -> dict:
        limit(request, "ip:" + client_ip(request), 20, 3600)
        now = time.time()
        ch = request.app.state.challenges
        for c, exp in list(ch.items()):
            if exp < now:
                del ch[c]
        if len(ch) > 10_000:
            raise HTTPException(status_code=503, detail="busy")
        value = secrets.token_bytes(32)
        ch[value] = now + 300
        return {"challenge": base64.b64encode(value).decode()}

    @app.post("/v1/attest/register")
    def register(request: Request, body: RegisterRequest) -> dict:
        limit(request, "ip:" + client_ip(request), 20, 3600)
        challenge_bytes = b64(body.challenge)
        expiry = request.app.state.challenges.pop(challenge_bytes, None)  # one use only
        if expiry is None or expiry < time.time():
            raise HTTPException(status_code=400, detail="unknown or expired challenge")
        try:
            key = request.app.state.verifier.verify_attestation(b64(body.key_id), b64(body.attestation), challenge_bytes)
        except AttestError as e:
            raise HTTPException(status_code=401, detail="attestation rejected") from e
        request.app.state.keys.add(key)
        return {"ok": True}

    def job_key(key_id: bytes, job_id: str) -> str:
        return f"{key_id.hex()[:16]}-{job_id}"  # each device only ever sees its own jobs

    @app.post("/v1/analysis/jobs", response_model=models.AnalysisJobAccepted)
    async def create_job(request: Request, body: PublicJobRequest, key_id: bytes = Depends(attested)) -> models.AnalysisJobAccepted:
        jobs: JobStore = request.app.state.jobs
        existing = jobs.get(job_key(key_id, body.job_id))
        if existing is None:
            limit(request, "jobs:" + key_id.hex(), 10, 3600)
            if jobs.active_count() >= MAX_QUEUED_JOBS:
                raise HTTPException(status_code=503, detail="busy", headers={"Retry-After": "60"})
            try:
                game = chess.pgn.read_game(io.StringIO(body.pgn))
            except Exception:
                game = None
            plies = len(list(game.mainline_moves())) if game else 0
            if not 1 <= plies <= MAX_PLIES:
                raise HTTPException(status_code=400, detail="game must have 1-300 moves")
        job = await jobs.submit(
            job_id=job_key(key_id, body.job_id), game_id=body.game_id, pgn=body.pgn, user_color=body.user_color,
            depth=min(body.depth, MAX_DEPTH), multipv=min(body.multipv, MAX_MULTIPV))
        return models.AnalysisJobAccepted(job_id=body.job_id, status=job.status)

    @app.get("/v1/analysis/jobs/{job_id}", response_model=models.AnalysisJobStatus)
    def get_job(request: Request, job_id: str, key_id: bytes = Depends(attested)) -> models.AnalysisJobStatus:
        job = request.app.state.jobs.get(job_key(key_id, job_id))
        if job is None:
            raise HTTPException(status_code=404, detail="job not found")
        return models.AnalysisJobStatus(
            status=job.status, progress=models.JobProgress(done=job.done, total=job.total), result=job.result,
            error="analysis failed" if job.error else None)

    @app.post("/v1/maia/predict", response_model=models.MaiaPredictResponse)
    def maia(request: Request, body: MaiaRequest, key_id: bytes = Depends(attested)) -> models.MaiaPredictResponse:
        limit(request, "maia:" + key_id.hex(), 300, 3600)
        try:
            board = chess.Board(body.fen)
        except ValueError as e:
            raise HTTPException(status_code=400, detail="bad position") from e
        if not board.is_valid():
            raise HTTPException(status_code=400, detail="bad position")
        return models.MaiaPredictResponse(policy=request.app.state.maia.predict(board.fen()))

    return app

