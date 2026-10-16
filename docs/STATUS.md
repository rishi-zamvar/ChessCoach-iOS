# ChessCoach — overnight build status (2026-10-16)

Built autonomously overnight from the approved spec (`docs/superpowers/specs/2026-10-15-chess-coach-design.md`).
Repo: https://github.com/rishi-zamvar/ChessCoach-iOS (`main` = tagged releases, `m1-base-app` = working branch).

## What works (tested on the iPhone 17 simulator)

| Area | What you can do |
|---|---|
| **Play** | chess.com-style game screen (green board, last-move tint, legal dots/rings, drag or tap, premoves incl. recaptures, promotion picker, arrows, sliding pieces, clocks + low-time warning, captured pieces, resign/draw, move browsing, result card). Opponents: **Coach bot** (AI teaching moves, Maia-like offline), **Maia 1100** (human-like), **Stockfish 1–8**. Sounds + haptics. |
| **Analyze** | Imports your chess.com games (Zammy009). **Game Review** like chess.com: eval graph, accuracy (Lichess formula), Brilliant→Blunder labels, phase grades, opening name, key-moment walkthrough with a coach bubble, **Retry** with hints, follow-up line, **Ask the coach** (AI). Explanations are built from engine facts, and the AI rewrites them only if every move/square it names is real. **Recurring mistakes** across games. Calibrated on your real games. |
| **Today** | A 15-minute daily plan built from your games and ratings, with the reason for every block. Your top mistake. AI/home-PC status + monthly spend. |
| **Train** | 59,457 Lichess puzzles (offline), per-skill puzzle ratings (Glicko-2), hint ladder, spaced-repetition reviews (FSRS) of failed puzzles and your own game mistakes, 18 taught lessons (idea → worked example → your turn → practice → 7/10 mastery), board-vision drills (coordinates, checks & captures, "is this move safe?"), **Play Coach** (pauses after your mistakes: take back / show me / continue; threat nudges; hints). |
| **Openings** | Your style's repertoire (White, Black vs 1.e4, Black vs 1.d4) — 12 validated repertoires across 4 styles, with ideas, arrows, deviations and traps. Learn mode + Drill mode (misses become review cards) + Ask the coach. |
| **Onboarding** | Username → style (Attacker/Tactician/Positional/All-rounder) → 7-position instinct quiz → 10-puzzle placement → result (flags if your instincts disagree with your pick). |
| **AI (M6)** | Phone calls Claude directly (Haiku for explanations, Sonnet 5.5 for the coach bot / Ask the coach) with on-phone board tools; $80/month cap enforced in-app; every call logged with cost. **Key arrives automatically from your PC** — never typed. |
| **Logging** | Every step (engine, analysis, import, puzzles, AI calls, key handoff…) is a structured event in SQLite (30 days), Console.app and a live stream — progress bars/ETAs read from it. |

Tests: **270+ package tests + app unit + 4 UI flows**, all green.

## Needs you (morning checklist)

1. **Install on your phone.** Open `ChessCoach.xcodeproj` after `xcodegen generate`, then run on device. The engine files are already in `ChessCoach/Resources/Engines`. On a fresh clone, run `scripts/fetch-engine-assets.sh`.
2. **Check feel on real hardware**, which the simulator can't show:
   - board drag smoothness at 120 Hz
   - how fast Stockfish analyses a game
   - phone heat during a long review
   - whether the move/capture sounds feel right; they're synthesized, so swap them by recording your own into `ChessCoach/Resources/Sounds/`
3. **Pick a piece set** under Options during a game: staunty (default), cardinal, maestro or cburnett.
4. **AI key:** create a dedicated Anthropic API key with an $80/month limit, funded by the Max 5x API credit. Put it in the PC's central `.env` as `ANTHROPIC_API_KEY_CHESSCOACH`. The phone picks it up automatically from the PC server (M5). Until then the app runs fully offline with template explanations.
5. **Home PC server (M5):** dispatched to the PC (`docs/superpowers/plans/2026-10-16-m5-pc-server.md`). Status: see below.

## Not done / next

- M5 PC server: being built on the PC. The phone side is ready: discovery, key handoff, deep analysis client.
- Teaching-bot quality needs real games to tune (gift frequency, loss caps).
- Openings: "what if I skip this move" refutations; Socratic AI walkthrough is available via Ask the coach.
- Weekly plan summary (AI) and an on-device model (M7).
- TailscaleKit embedding (currently uses the Tailscale app).
