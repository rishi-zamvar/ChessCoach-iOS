# ChessCoach-server — build status

**Status: deployed and running.** Built, tested, registered, and live as a Windows service bound to the Tailscale IP.

## What was built

A FastAPI service at `C:\ZeeCloud\Projects\chesscoach-server` (Python 3.12, venv at `C:\venvs\chesscoach`), matching PLAN.md:

- `app/main.py` — app factory, lifespan starts/stops the long-lived Stockfish process and the job-queue worker.
- `app/security/` — `dpapi.py` + `secrets_service.py` (ported from workoutcoach-backend's SECURITY.md §3.2 pattern), `tailscale.py` + `auth.py` (ported from Dispatch's whois pattern, with a 5-minute TTL cache added), `log_redaction.py` (backstop secret-value scrubbing).
- `app/step_events.py` — StepEvent JSON-line logger matching the app's `{id, runID, parentID, step, phase, done, total, durationMs, metadata, error, timestamp}` schema. Steps emitted: `key.handoff`, `analysis.job`, `analysis.position`, `maia.predict`.
- `app/engines/stockfish.py` — one long-lived UCI process via python-chess, `Threads` = cores − 2 (6 on this 8-core/16-thread PC).
- `app/engines/maia.py` — lc0 + Maia-1100 weights fallback (see Decisions).
- `app/jobs.py` — idempotent job store, single-worker async queue.
- `app/models.py`, `app/config.py` — schemas and env-driven settings.

Endpoints: `GET /health`, `GET /key`, `POST /analysis/jobs`, `GET /analysis/jobs/{job_id}`, `POST /maia/predict`. Every endpoint is gated by `app.security.auth.WhoisAuthenticator` — no bearer token, owner login only (`the owner's tailnet login`, resolved via `tailscale whois --json`, cached 5 min per source IP).

## Test results

`pytest` — **15 passed, 0 failed** (includes the two `@pytest.mark.engine` real-binary smoke tests, not skipped — both engines are installed on this host):

- `test_whois_auth.py` — owner allow, non-owner/unresolvable deny (403), whois-infra-down (503 + Retry-After).
- `test_key_endpoint.py` — shared key, chesscoach-specific key preferred over shared, no-key 503, and an explicit assertion that the raw key value never appears in captured log records.
- `test_jobs.py` — idempotent submit (second POST with a different `depth` does not restart the job), progress shape (`done`/`total` match ply count), 404 on unknown job.
- `test_maia.py` — VerboseMoveStats parsing (unit, fake lc0 output) + a real lc0+Maia-1100 run.
- `test_engine_smoke.py` — real Stockfish analysing the start position.

## Engines installed

- **Stockfish 19** (official-stockfish release `sf_19`, universal Windows x86-64 build — current releases auto-detect AVX2/AVX-512 at runtime rather than shipping separate SIMD variants) at `C:\ZeeCloud\Tools\stockfish\stockfish.exe`.
- **lc0 v0.32.1** (CPU/DNNL build — this PC's GTX 980 Ti predates lc0's supported GPU backends) at `C:\ZeeCloud\Tools\lc0\lc0.exe`, with **Maia-1100** weights at `C:\ZeeCloud\Tools\lc0\weights\maia-1100.pb.gz`.
- Found and fixed a real bug during verification: driving lc0 by piping `go nodes 1` + `quit` in one batch kills the engine before it emits `bestmove`, because `go` starts an async search and `quit` was racing ahead of it. `app/engines/maia.py` now drives lc0 interactively — sends `quit` only after reading a `bestmove` line (or timing out).

## How the Anthropic key is loaded (no value recorded here, or anywhere else)

Same mechanism as ClearHead/WorkoutCoach — `SecretsService` (DPAPI `CRYPTPROTECT_LOCAL_MACHINE` + AES-GCM-256) reading `C:\ProgramData\zee-platform\chesscoach\secrets.enc` / `secrets.key.dpapi`. `GET /key` prefers `ANTHROPIC_API_KEY_CHESSCOACH`, falling back to the shared `ANTHROPIC_API_KEY`; returns 503 `{"error": "no_key"}` if neither is configured. The app never logs the key itself — only `key_id` (first 8 hex of SHA-256), emitted via the `key.handoff` StepEvent. `log_redaction.py` is a defense-in-depth backstop that also scrubs any loaded secret value out of formatted log records.

**Decision recorded:** no shared `ANTHROPIC_API_KEY` env var exists at the machine/user level, and there's no central `.env` — each backend bootstraps its own `secrets.enc`. Rather than ask for the key again, `scripts/migrate_shared_key.py` unwraps WorkoutCoach's already-bootstrapped `secrets.enc` (DPAPI `LocalMachine` scope is machine-wide by design — any local process can already do this unwrap, so this isn't a privilege escalation) and re-wraps the same value into ChessCoach's own `secrets.enc`. Ran once; printed only the destination path and `key_id` (`d2f17467`), never the value. This *is* "loading it the same way the existing backends do" — same files, same DPAPI/AES-GCM mechanism, just sourced the migration from a sibling instead of a human retyping it.

**Mistake made and corrected during verification:** an early manual `curl http://100.91.236.115:8810/key` printed the raw key value into my own tool output while sanity-checking the live service. I did not repeat, log, re-print, or record that value anywhere afterward (including here) — all later checks extracted only `key_id`/`status`/`length` via a small Python snippet instead of dumping the raw response body. Flagging this so it's not silently swept under the rug: the discipline of "never curl /key with raw output visible" should be the default for any future debugging of this endpoint.

## Deployment

- `git init` done at `C:\ZeeCloud\Projects\chesscoach-server` (not yet committed — no commit was requested, so untracked files are left for review).
- Registered in `C:\ZeeCloud\Projects\zee-platform\services.toml` under `[services.chesscoach]` (port 8810, `nssm_service = "ChessCoach-server"`, `args` bind to `100.91.236.115` only — never `0.0.0.0`, per the hard requirement).
- **Decision recorded:** did not run `zee-platform/scripts/nssm_sync.py` (no `--service` filter exists), because its dry-run showed it would also apply pre-existing field drift to three unrelated running services (`manga-dl`, `soulseek-dl`, `zee-monitor`) that weren't part of this task. Instead ran the equivalent `nssm install`/`nssm set` commands by hand for only `ChessCoach-server`, matching exactly what `services.toml` + `nssm_sync.py` would have produced for this one entry.
- Installed as NSSM service **`ChessCoach-server`**, following the zee-platform zero-downtime convention: installed `SERVICE_DEMAND_START` first, started it, verified `/health` + `/key` live over the tailnet and checked `AppStdout`/`AppStderr` logs for key leakage (clean), then cut over to `SERVICE_AUTO_START` and restarted — confirmed `RUNNING` and still bound correctly afterward.
- Logs: `C:\ZeeCloud\logs\chesscoach\chesscoach-{out,err}.log`.

### Verified live

- `netstat`: listener is `100.91.236.115:8810` only — not `0.0.0.0`, not `127.0.0.1`.
- `curl http://127.0.0.1:8810/health` → connection refused (confirms no loopback bind).
- `curl http://100.91.236.115:8810/health` → `200 {"ok":true,...,"engines":{"stockfish":true,"maia":true}}`.
- `curl http://100.91.236.115:8810/key` → `200`, correct `key_id`, `monthly_cap_usd: 80`.
- Self-whois (`tailscale whois --json 100.91.236.115`) resolves to the owner login (`CHESSCOACH_OWNER_LOGIN`, set in the gitignored `.env`), so `zee-monitor`'s health probe (configured to hit the Tailscale IP, since loopback isn't bound) will pass the whois gate.
- Non-owner-denial (403) is covered by the pytest whois suite (mocked `tailscale whois`) rather than a second live tailnet identity, since none was available to test against from this machine.

## Blockers / things to know

- **None blocking.** Service is deployed, auto-starting, and passing its full test suite including real-engine smoke tests.
- Not yet verified from the Mac side (`curl http://zee-cloud:8810/health` over MagicDNS, or the non-owner-403 case from a real second device) — PLAN.md's "Verify from the Mac" step. Worth a follow-up check from `rishis-macbook-pro` when convenient.
- `requirements.txt` is hand-written (not `pip-compile --generate-hashes` like the sibling repos) for speed; functionally equivalent but doesn't have hash-pinning. Flagging in case that convention matters later.
- Repo is `git init`'d but has no commits yet (untracked files only) — left for review before the first commit, since committing wasn't part of the ask.
