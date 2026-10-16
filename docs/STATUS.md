# ChessCoach: overnight build status (2026-10-16)

Built autonomously overnight from the approved spec (`docs/superpowers/specs/2026-10-15-chess-coach-design.md`).
Repo: https://github.com/rishi-zamvar/ChessCoach-iOS. `main` holds tagged releases (latest tag below); `m1-base-app` is the working branch.

Releases: v0.4.0 (offline MVP: Play, Analysis, Drills, Openings) → v0.5.0 (Play Coach) → v0.6.0 (AI layer) → v0.7.0 (fast review, Settings, on-device model) → **v0.8.0** (Puzzle Rush, background analysis, streak, review fixes).

## What works (simulator-tested, much of it on your real chess.com games)

| Area | What you can do |
|---|---|
| **Play** | <ul><li>**Game screen**, chess.com style: green board, last-move tint, legal-move dots and capture rings, drag or tap moves, premoves (including recaptures and castling), promotion picker, arrows you draw, sliding pieces, clocks with a low-time warning, captured pieces, resign and draw, move browsing, result card leading to Game Review.</li><li>**Opponents:** Coach bot (AI teaching moves; plays like Maia when offline or in timed games), Maia 1100, Stockfish levels 1–8.</li><li>**Sounds and haptics.**</li></ul> |
| **Analyze** | <ul><li>**Import:** your chess.com games (Zammy009) come in, and the latest 10 are **analyzed automatically in the background**. This pauses whenever you play or open a review.</li><li>**Game Review:** about 30 s per game on the phone, with eval graph, Lichess accuracy, labels from Brilliant to Blunder, opening name, key moments, coach bubble, Retry with hints, follow-up line, a note on where you left your repertoire, and **Ask the coach**.</li><li>**Explanations:** built from engine facts. The AI (or Apple's on-device model on iOS 26) rewrites them only when every move and square it names is real.</li><li>**Recurring mistakes** across games.</li></ul> |
| **Today** | <ul><li>**Daily plan:** 15 minutes, built from your games and ratings. Every block says why it's there, and the plan stays fixed for the day.</li><li>**Also on Today:** your top mistake, this week's stats with a practice streak, and AI / home-PC status with monthly spend. Settings is behind the gear icon.</li></ul> |
| **Train** | <ul><li>**Puzzles:** 59,457 Lichess puzzles, offline, with a puzzle rating for each skill.</li><li>**Puzzle Rush.**</li><li>**Hints:** a hint ladder, with Solution available after the third hint.</li><li>**Spaced-repetition reviews** of failed puzzles, your own game mistakes and missed opening moves.</li><li>**18 lessons:** each goes idea, worked example, your turn, then practice. Practice can be puzzles, board-vision drills, or **play-it-out** against Stockfish's best defence for the queen mate, rook mate and king-and-pawn lessons.</li><li>**Play Coach:** pauses after your mistakes (take back / show me / continue), nudges you about threats, and gives hints.</li></ul> |
| **Openings** | <ul><li>**Repertoires:** one for your style (White, Black vs 1.e4, Black vs 1.d4). There are 12 validated repertoires across the 4 styles, with ideas, arrows, deviations and traps.</li><li>**Modes:** Learn and Drill. Moves you miss become review cards.</li><li>**Ask the coach.**</li></ul> |
| **Onboarding / Settings** | <ul><li>**Onboarding:** username, style, a 7-position instinct quiz, a 10-puzzle placement, then the result (with a warning if your style pick and your quiz answers disagree).</li><li>**Settings:** retake onboarding, username, board theme and pieces, coordinates, sound, AI status.</li></ul> |
| **AI** | <ul><li>**Direct calls:** the phone calls Claude directly. Haiku 4.5 writes explanations; Sonnet 5.5 drives the coach bot and Ask the coach, using on-phone board tools: position, legal moves, Stockfish lines, Maia human moves, tactic facts, your profile, and drawing arrows.</li><li>**Spending:** the $80/month cap is enforced, and every call's cost is logged.</li><li>**Key:** arrives automatically from your PC over Tailscale (whois-checked). It is never typed, and stays on this device only.</li></ul> |
| **Logging** | Every step is a structured event in SQLite (kept 30 days), Console.app and a live stream. Progress bars and ETAs read from it. |

Tests: 273 package tests plus app unit tests and 5 UI flows, all green. One more UI test, a tour on your real chess.com games, runs on demand with `TEST_RUNNER_TOUR=1` and passes.
Screenshots: `docs/screenshots/{m1,m2,m3,real}/`.

## Needs you (morning)

1. **Install on your phone.** Run `xcodegen generate`, open `ChessCoach.xcodeproj`, and run it on your iPhone. The engine nets are already in place locally; on a fresh clone, run `scripts/fetch-engine-assets.sh` first.
2. **Check feel on real hardware:**
   - drag smoothness at 120 Hz;
   - how long a review takes (the simulator does about 30 s for the longest game);
   - how warm the phone gets;
   - whether you like the synthesized sounds (swap in your own under `ChessCoach/Resources/Sounds/`);
   - which piece set you prefer.
3. **AI key:** create a dedicated Anthropic API key with an $80/month limit, paid from your Max 5x API credit. Put it in the PC's central `.env` as `ANTHROPIC_API_KEY_CHESSCOACH`.
4. **Home PC server (M5) has not been built yet.** It was dispatched to the PC at 00:44 (`docs/superpowers/plans/2026-10-16-m5-pc-server.md`). The PC marked the message read, but no repo existed as of about 01:35, so there's probably no active Claude session on the PC. Start one there and point it at the plan. The phone side is done and waits for `100.91.236.115:8810` (`/health`, `/key`, `/analysis/jobs`).
5. **Verify the PC connection over plain HTTP on the device.** I removed the app-wide insecure-HTTP setting. iOS should allow plain HTTP to a raw IP address, but I couldn't test that without the server. If the phone can't reach the PC, add an App Transport Security exception for it.

## Not done / next

- M5 server (on the PC). The coach bot's tuning (how often it gives away material on purpose, and its caps on how much it can lose) needs real games.
- "What if I skip this move" refutations in Openings Learn (Ask the coach covers this informally).
- AI weekly summary. Embedding Tailscale in the app (it uses the Tailscale app for now). An MCP server on the PC exposing the same tools.
- On-device model verification on an iOS 26 Apple Intelligence device.
