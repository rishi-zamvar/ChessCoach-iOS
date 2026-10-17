"""In-memory analysis job store.

Idempotent by job_id (PLAN.md endpoint table: "the same job_id returns
the existing job"). A single background worker processes one job at a
time, matching the one-long-lived-engine-process model in PLAN.md
Notes.
"""
from __future__ import annotations

import asyncio
import io
import logging
from dataclasses import dataclass, field
from typing import Protocol

import chess
import chess.pgn

from app.step_events import StepEvent, new_id

_log = logging.getLogger("app.jobs")


class AnalysisEngine(Protocol):
    def analyse_position(
        self, board: chess.Board, *, depth: int, multipv: int
    ) -> list[dict]: ...


@dataclass
class Job:
    job_id: str
    game_id: str
    pgn: str
    user_color: str
    depth: int
    multipv: int
    status: str = "queued"
    done: int = 0
    total: int = 0
    result: dict | None = None
    error: str | None = None


class JobStore:
    def __init__(self, engine: AnalysisEngine) -> None:
        self._engine = engine
        self._jobs: dict[str, Job] = {}
        self._queue: asyncio.Queue[str] = asyncio.Queue()
        self._worker_task: asyncio.Task | None = None
        self._lock = asyncio.Lock()

    def start(self) -> None:
        if self._worker_task is None:
            self._worker_task = asyncio.create_task(self._worker_loop())

    async def stop(self) -> None:
        if self._worker_task is not None:
            self._worker_task.cancel()
            try:
                await self._worker_task
            except asyncio.CancelledError:
                pass
            self._worker_task = None

    def get(self, job_id: str) -> Job | None:
        return self._jobs.get(job_id)

    def prune_finished(self, keep: int) -> None:
        """Drops the oldest finished jobs once more than `keep` are stored (results live in memory only)."""
        finished = [jid for jid, j in self._jobs.items() if j.status in ("done", "failed")]
        for jid in finished[: max(0, len(self._jobs) - keep)]:
            del self._jobs[jid]

    def active_count(self) -> int:
        """Jobs waiting or running."""
        return sum(1 for j in self._jobs.values() if j.status in ("queued", "running"))

    async def submit(
        self,
        *,
        job_id: str,
        game_id: str,
        pgn: str,
        user_color: str,
        depth: int,
        multipv: int,
    ) -> Job:
        async with self._lock:
            existing = self._jobs.get(job_id)
            if existing is not None:
                return existing
            job = Job(
                job_id=job_id,
                game_id=game_id,
                pgn=pgn,
                user_color=user_color,
                depth=depth,
                multipv=multipv,
            )
            self._jobs[job_id] = job
            await self._queue.put(job_id)
            return job

    async def _worker_loop(self) -> None:
        while True:
            job_id = await self._queue.get()
            job = self._jobs.get(job_id)
            if job is None:
                continue
            await self._run_job(job)

    async def _run_job(self, job: Job) -> None:
        run_id = new_id()
        job.status = "running"
        StepEvent(
            step="analysis.job",
            phase="start",
            run_id=run_id,
            metadata={"job_id": job.job_id},
        ).emit()
        try:
            game = chess.pgn.read_game(io.StringIO(job.pgn))
            if game is None:
                raise ValueError("unparsable PGN")
            board = game.board()
            moves = list(game.mainline_moves())
            job.total = len(moves) + 1

            positions = [await self._analyse_and_record(board, job, run_id, 0)]
            job.done = 1
            for i, move in enumerate(moves, start=1):
                board.push(move)
                positions.append(await self._analyse_and_record(board, job, run_id, i))
                job.done = i + 1

            job.result = {"positions": positions}
            job.status = "done"
            StepEvent(
                step="analysis.job",
                phase="done",
                run_id=run_id,
                done=job.done,
                total=job.total,
                metadata={"job_id": job.job_id},
            ).emit()
        except Exception as exc:  # noqa: BLE001
            job.status = "failed"
            job.error = str(exc)
            StepEvent(
                step="analysis.job",
                phase="error",
                run_id=run_id,
                error=str(exc),
                metadata={"job_id": job.job_id},
            ).emit()

    async def _analyse_and_record(
        self, board: chess.Board, job: Job, run_id: str, ply_index: int
    ) -> dict:
        lines = await asyncio.to_thread(
            self._engine.analyse_position, board, depth=job.depth, multipv=job.multipv
        )
        StepEvent(
            step="analysis.position",
            phase="done",
            run_id=run_id,
            metadata={"job_id": job.job_id, "ply": ply_index},
        ).emit()
        return {"fen": board.fen(), "lines": lines}
