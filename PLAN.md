# M5 Home PC Server (`chesscoach-server`) Implementation Plan

> **For agentic workers:** built on the PC (zee-cloud) by the SWE node. REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. TDD, pytest, BDD test names `test_given_x_when_y_then_z`.

**Goal:** A small FastAPI service on the home PC that the ChessCoach iPhone app reaches over Tailscale. It does three things:
1. Hands over the Anthropic API key automatically, with nothing typed on the phone.
2. Runs deep Stockfish analysis jobs.
3. Answers Maia move-probability queries.

All three are optional accelerators: the phone works fully offline without the PC.

**Spec:** ChessCoach-iOS `docs/superpowers/specs/2026-10-15-chess-coach-design.md` §1 (key handoff) and §7.

**Repo:** new repo `chesscoach-server` at `C:\ZeeCloud\Projects\chesscoach-server` (Python 3.12, FastAPI, uvicorn, python-chess). Register it in zee-platform `services.toml` and run it as an NSSM service named `ChessCoach-server`.

## Hard requirements

1. **Bind to the Tailscale IP only** (100.91.236.115), port **8810**. Never bind to 0.0.0.0, and verify the bind address after cutover (zee-platform lesson).
2. **Auth on every request** uses Tailscale `whois`. Resolve the peer IP with `tailscale whois --json <ip>` (cache it for 5 minutes) and accept only the owner's login. This is the same pattern as Dispatch/ZeeChat. Reuse the existing helper if Dispatch's `api_chat.py` has one. **No bearer token, because the phone never stores a secret.**
3. **The key never appears in logs.** Log only `key_id` (the first 8 hex digits of SHA-256(key)).

## Endpoints

| Method | Path | Behaviour |
|---|---|---|
| GET | `/health` | `{"ok": true, "service": "chesscoach-server", "version": "0.1.0", "engines": {"stockfish": bool, "maia": bool}}`. Also whois-gated. |
| GET | `/key` | `{"key": "<sk-ant-…>", "key_id": "ab12cd34", "monthly_cap_usd": 80}`. The key comes from env `ANTHROPIC_API_KEY_CHESSCOACH`, falling back to `ANTHROPIC_API_KEY`, loaded from the central `.env` the way the WorkoutCoach backend loads it. If neither is set, return 503 `{"error": "no_key"}`. |
| POST | `/analysis/jobs` | Body: `{"job_id": "<uuid>", "game_id": "...", "pgn": "...", "user_color": "white", "depth": 22, "multipv": 3}`. It is idempotent: the same `job_id` returns the existing job. Returns `{"job_id", "status": "queued"}`. |
| GET | `/analysis/jobs/{job_id}` | `{"status": "queued|running|done|failed", "progress": {"done": n, "total": m}, "result": {...}}`. `result.positions` = one entry per position `{fen, lines: [{multipv, depth, cp|mate, pv: [uci...]}]}` from the start through the last ply, from the side-to-move perspective. Use the same JSON shape the phone's `PositionCache` stores. |
| POST | `/maia/predict` | Body: `{"fen": "...", "rating": 1100}`. Returns `{"policy": {"e2e4": 0.31, ...}}`. Run Maia-2 on CPU if it installs cleanly. The GTX 980 Ti is sm_52, which current PyTorch doesn't support, so use CPU or ONNX DirectML. Otherwise fall back to lc0 with the maia-1 weights (`go nodes 1`, `VerboseMoveStats`). |

## Notes

- **Engine:** Stockfish 17+ native Windows build with the big net, one long-lived process, `Threads` = cores − 2, and a job queue worker processing one job at a time.
- **Logging:** structured JSON lines with the same StepEvent schema as the app: `{id, runID, parentID, step, phase, done, total, durationMs, metadata, error, timestamp}`, one event per step (`key.handoff`, `analysis.job`, `analysis.position`, `maia.predict`).
- **Tests (pytest):**
  - whois allow/deny, using a mocked `tailscale whois`
  - `/key` with and without the env var, and the key absent from captured logs
  - job idempotency and the progress shape, with a fake engine
  - a real-engine smoke test marked `@pytest.mark.engine`
- **Verify from the Mac:** `curl http://zee-cloud:8810/health` over the tailnet returns 200, and from a non-owner (simulated) returns 403.

## Phone side (done on the Mac, M6)

The iOS app calls `/health` (1.5 s timeout) on launch and foreground, then `/key`, and stores the key in the Keychain. Deep analysis and Maia are used when reachable.
