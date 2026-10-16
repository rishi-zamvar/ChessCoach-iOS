# ChessCoach — Design Spec

**Date:** 2026-10-15 · **Owner:** Rishi (chess.com `Zammy009`, rapid ~305) · **Status:** approved in brainstorming, pending spec review

ChessCoach is a personal iOS chess coach. It plays, reviews and trains fully offline, calls Claude directly from the phone when there is internet, and uses a home PC over Tailscale as an accelerator. It has four tabs: **Today · Analyze · Train · Play**.

**Guiding rule:** deterministic code (rules, Stockfish, Maia, classifier, fact extractor) decides what is true. Claude only explains and chooses among engine-vetted options. AI is always optional; nothing breaks without it.

Research backing every decision lives in `docs/research/`:
- `01-drills-pedagogy.md` covers curriculum, the Lichess puzzle DB, learning science and the adaptive plan.
- `02-open-source-stack.md` covers libraries, engines, assets, licenses, the chess.com API and formulas.
- `03-chesscom-coach-teardown.md` covers chess.com Game Review and Coach, user complaints, competitors and explanation grounding.
- `04-claude-code-api-wrappers.md` covers the subscription vs API-key policy and the reasons for choosing an API key.

---

## 0. Locked decisions

| Topic | Decision |
|---|---|
| Distribution | **Personal only** (Xcode sideload, like WorkoutCoach). GPL Stockfish/Lc0/Maia-1 bundled; NC-licensed piece sets allowed. Never App Store without a license re-review. |
| Tabs | Today · Analyze · Train · Play |
| UI | WorkoutCoach "Apothecary" design system everywhere **except** board screens, which replicate chess.com's dark game chrome and green board |
| Board default | Green `#EEEED2` / `#769656`; all themes are data |
| Bot | Human-like. Teaching bot (Claude choosing among Maia/Stockfish candidates) first; weakest Maia directly once the user consistently beats the teaching bot |
| LLM | Anthropic API key funded by Max 5x monthly API credit ($100/mo). App-side spend cap **$80/mo** |
| Key provisioning | Automatic: phone discovers PC over Tailscale → PC authenticates the phone by Tailscale `whois` (no secret on phone) → PC returns the key → Keychain. **No manual key entry anywhere.** |
| AI tools | Executed **on the phone** (Anthropic cannot reach the tailnet). Same tool schemas later re-exposed as an MCP server on the PC for Claude Code/Desktop. |
| Openings | Small coach-picked starter repertoire driven by onboarding style, plus "left the repertoire" flags from the user's games |
| Persistence | GRDB (SQLite) |
| Tailscale | iOS Tailscale app for v1 (TailscaleKit embedding deferred) |
| Logging | Comprehensive structured step logging everywhere (§9) |
| Tests | Test-first, BDD names `test_givenX_whenY_thenZ()` |

## 1. Architecture

```
┌──────────────── iPhone (everything works offline) ──────────────────┐
│ SwiftUI · tabs Today · Analyze · Train · Play                        │
│ ChessCore     chesskit-swift (rules, FEN/PGN/SAN, MoveTree)          │
│ Engines       chesskit-engine → Stockfish 17 (+NNUE nets shipped)    │
│                              → Lc0 + Maia-1 1100 weights (1.2 MB)    │
│ Board         custom SwiftUI board + annotation layer, sound, haptic │
│ Analysis      win%/accuracy · classifier · fact extractor · templates│
│ Training      puzzle bundle (Lichess CC0) · FSRS · planner           │
│ Store         GRDB                                                    │
│ Coach         Anthropic client + on-phone tool loop + validator      │
│ Telemetry     StepEvent logging (§9)                                 │
│ Sync          Tailscale → PC (optional)                              │
└─────┬─────────────────────────────────────────┬──────────────────────┘
      │ HTTPS                                    │ Tailscale (whois-authenticated)
      ▼                                          ▼
 api.anthropic.com                   ┌── Home PC `zee-cloud` (accelerator) ──┐
 api.chess.com (imports from phone)  │ chesscoach-server · FastAPI · NSSM     │
                                     │ bound to the Tailscale IP only         │
                                     │ /health · /key · /analysis jobs ·      │
                                     │ /maia · /sync · (later) MCP            │
                                     │ Stockfish 19 big net · Maia-2/3 (CPU)  │
                                     └────────────────────────────────────────┘
```

**Connectivity modes:**

| Mode | Behaviour |
|---|---|
| No internet | Everything except AI text. Templates explain, Maia-on-phone plays. |
| Internet, no PC | Everything including Claude (if the key was provisioned before). Phone-depth analysis. |
| PC reachable | Deep analysis replaces phone results, Maia-2/3, key refresh, backup sync. |

**Key handoff flow:**
1. On launch and on foreground, the phone calls `https://zee-cloud.<tailnet>/health` (≤1.5 s timeout).
2. If the PC is reachable, the phone calls `GET /key`.
3. The server resolves the caller with `tailscale whois <peer-ip>` and accepts only the owner's user login, the same pattern as Dispatch/ZeeChat. It returns `{key, key_id, monthly_cap_usd}`.
4. The phone stores the key in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`).
5. The phone re-checks on every successful reach. When `key_id` changes, it replaces the stored key, which handles rotation.
6. Before the first handoff, AI surfaces show "Connect to your home PC once to enable AI."

The key is never logged. Handoff events log only success/failure and `key_id`.

**Repos:** `ChessCoach-iOS` (XcodeGen, iOS 17 target, mirrors WorkoutCoach layout) and `chesscoach-server` (Python/FastAPI on the PC, NSSM service, registered in zee-platform `services.toml`).

## 2. Board & Play

**Visual zones:** all menus and lists use the ported WorkoutCoach DesignSystem (Palette, Typography, Spacing, Atmosphere, Components, Haptics, Toast, ConnectionBanner). Board screens use chess.com-style dark chrome (charcoal background) around the board.

**Game screen, top to bottom:**
1. Opponent bar: avatar, name, rating, captured pieces and +material, and a clock that turns red under 10% or under 20 s.
2. Horizontal move strip that auto-scrolls; classification icons appear in review.
3. Full-width board. An optional eval bar is off during play.
4. Player bar, same layout as the opponent bar.
5. Bottom toolbar: options (flip, resign, draw), ◀ ▶, and Hint in coach modes.

**Board component** (one reusable `BoardView` used by every screen):
- **Rendering:** a SwiftUI `Canvas` draws squares, highlights and arrows. Pieces are vector assets in a `ZStack` so they can animate. Target is 120 Hz on ProMotion.
- **Input:** tap-tap and drag (the piece lifts and scales under the finger). Legal moves show as dots, captures as rings. Premoves and a promotion picker are supported, and the board can be flipped.
- **Annotation layer (data-driven):** arrows (green/red/blue/yellow), circles, square highlights, last-move tint (yellow, ~50%), check glow, a classification badge on the moved piece, and user-drawn arrows by long-press-drag.
- **Coordinates:** drawn inside the edge squares. Move animation is ~150 ms.
- **Themes:** a `BoardTheme` (colors) and a `PieceSet` (asset folder) are both data. The default piece set is the most Neo-like NC set (staunty/cardinal/maestro, chosen in M0), with cburnett (BSD) as the fallback.

**Sound** (an `AVAudioPlayer` pool, preloaded):
- Events: move, capture, check, castle, promote, illegal, premove, game start, game end, low-time tick.
- Sources: self-recorded wood clicks for move/capture/castle/check/promote, and Freesound CC0 (el_boss) / Kenney CC0 for UI chimes. Lichess sound sets are not usable (see research 02 §5). No chess.com assets.
- Haptics: light impact on move, medium on capture.

**Play tab:**
- Opponents:
  - Teaching bot (Claude). This needs AI; the offline fallback is Maia.
  - Maia (weakest available: Maia-1 1100 on phone; Maia-2 low Elo on PC).
  - Stockfish fixed levels.
- Time controls: none / 10|0 / 15|10 / 30|0.
- The result card has a **Game Review** button that leads into Analyze.
- All games are saved as PGN with `%clk`.

## 3. Onboarding & style profile

The flow takes about 3 minutes and every step can be skipped:

1. **Chess.com username:** prefilled `Zammy009`. Import starts in the background.
2. **Style pick:** four cards.
   - Attacker (Tal)
   - Tactician (Kasparov)
   - Positional (Carlsen)
   - All-rounder
3. **Instinct quiz:** 7 positions, each with two sound moves (one sharp, one quiet). Each answer adds to an attacking↔positional score.
4. **Game-history signal:** computed deterministically from imported games.
   - Inputs: gambit/sacrifice frequency, open vs closed structures, and king-attack frequency.
   - The result is added to the same score.
5. **Reconcile:** if the picked style disagrees with the signals, the app shows the mismatch and the user chooses. Claude phrases the trade-off when available.
6. **Placement:** a 10-puzzle test across the fundamentals, combined with the chess.com rating. This sets the start position on the lesson ladder and seeds the skill ratings.

**The style controls:**
- starter repertoire (e.g. Attacker → Italian, Scotch Gambit; Positional → London, Caro-Kann)
- model games and themed lessons
- coach voice and plan suggestions
- puzzle-theme weighting once the fundamentals are mastered

**The style never controls** the fundamentals ladder below ~1000, or difficulty targeting.

Onboarding can be retaken from Settings. The app suggests a retake when 30+ games drift from the chosen style.

## 4. Game Analysis

**Import (from the phone):**
- `GET /pub/player/zammy009/games/archives`, then each month, **serially**, with a User-Agent that carries contact info.
- Past months are cached forever. The current month uses `If-None-Match`/`If-Modified-Since`.
- Back off on 429.
- Keep only games with `rules == "chess"` from the standard start FEN. Drop aborted games (≤2 plies) and daily games.
- Dedupe on game URL and compare usernames in lowercase.

**Engine passes:**
- **Phone:** Stockfish depth 14–16, MultiPV 3, cached by normalized FEN (no move counters). A pass pauses at `thermalState >= .serious` and resumes from the last completed ply.
- **PC (when reachable):** SF19 big net at depth 22+, MultiPV 3, plus Maia-2 probability of the played move at the user's rating. Results are tagged with engine, version and depth, and replace phone results. Results from different engines are never compared directly.
- Scores are normalized to the mover's perspective in **one** function. Mate scores take their own branch (±100% win).

**Formulas (from the Lichess source):**
- Win% = 50 + 50·(2/(1+e^(−0.00368208·cp)) − 1), with cp clamped to ±1000.
- Move accuracy = 103.1668100711649·e^(−0.04354415386753951·Δwin%) − 3.166924740191411 + 1, clamped to 0–100.
- Game accuracy = (volatility-weighted mean + harmonic mean)/2. The window is clamp(moves/10, 2, 8) and the weights are clamp(stddev, 0.5, 12).

**Classification** (expected points lost, EP = win%/100):

| Label | Rule |
|---|---|
| Book | Position is in the openings DB (Lichess chess-openings, CC0) |
| Forced | Only one legal move; not graded |
| Best / Excellent / Good / Inaccuracy / Mistake / Blunder | EP lost ≤0 / ≤.02 / ≤.05 / ≤.10 / ≤.20 / >.20 (tuned against a sample of the user's chess.com reviews) |
| Great | Best move, and the second-best loses ≥.10 EP, and the move changes the outcome bucket |
| Brilliant | Best or within .02 of best, gives up material (by static exchange evaluation (SEE) or the piece left unsafe), position not losing after, **and** Maia probability at the user's rating < 0.10 (phone pass uses Maia-1 1100 as the proxy; PC pass uses Maia-2 at the exact rating) |
| Miss | The opponent's previous move lost ≥.10 EP, a winning reply existed, and the played move failed to keep ≥ half that gain |

**Guards:**
- Positions already decided (EP ≤.05 or ≥.95 before the move) cannot be labelled Blunder or Mistake.
- Moves made with <10% of the starting clock get a `timeTrouble` tag.

**Fact extractor (deterministic Swift):**
- **What it runs on:** the position before the move, the played move, the best line and the punishing line.
- **Outputs:**
  - material delta
  - hanging and undefended pieces (by SEE)
  - threats created, allowed and missed
  - motif tags: fork, pin, skewer, discovered attack, back-rank, mate threat, trapped piece, overloaded defender, deflection, decoy
  - king-safety basics
  - game phase
- **Implementation:** ideas reimplemented from the Lichess tagger (AGPL; no code copied).

**Mistake taxonomy:**
- missed tactic
- allowed tactic (a failure of the checks/captures/threats (CCT) habit)
- hung material
- endgame error
- failure to convert
- opening deviation
- time trouble

**Explanations:**
- Templates always work offline.
- Claude rewrites them when online and passes the validator (§6).
- Cached by (FEN, move).

**Review screen (chess.com layout):**
- Top: eval graph, per-side accuracy, classification counts, and phase grades.
- **Start Review** walks through key moments only, with a coach bubble and arrows.
- Each mistake offers **Retry** (hint first, then the move) and **Show Follow-up**.
- A free analysis board sits below.
- Chess.com's "Game Rating" is deliberately omitted.

**Downstream:**
- Each critical moment becomes a `drill_item` plus an FSRS card.
- The weakness counters are incremented by motif × mistake type × phase.
- The **Recurring Mistakes** screen aggregates across games (e.g. "missed a knight fork 6× in 10 games").

## 5. Training

### Drills

**Ladder** (~40 lessons, Steps-Method order; the detailed list and pass rules are in research 01 §§1–5):
1. board vision
2. safety (hanging pieces, threat detection, is-this-move-safe)
3. mate in 1 → K+Q, K+R mates
4. forks/pins/skewers
5. the CCT habit
6. named mates
7. other tactics
8. basic endgames
9. calculation

**Lesson format:** explain → worked example → faded example → themed set → mastery test (7/10 correct unlocks the next lesson).

**Content:**
- **Puzzles:** a ~100k Lichess puzzle subset, filtered to RD ≤80, popularity ≥85, plays ≥200, rating 400–2000, stratified by theme. About 10–20 MB, bundled as SQLite.
  - Puzzle format: the FEN is *before* the opponent's move; apply `Moves[0]` first. Moves are UCI.
  - In mate-in-1 puzzles, any mating move is accepted.
- **Generated:** board-vision and safety drills.
- **Endgames:** ~25 curated positions played against the engine, judged by Syzygy WDL. The bundle is the 3–4-man set plus the specific 5-man files needed (e.g. KRPvKR).
- **Hand-curated FENs:** untagged mates (Greco, Légal, Damiano, Lolli, Anderssen).

**Ratings:**
- Per-theme Glicko-2.
- Puzzle selection targets ~200 below the theme rating, aiming for a 60–80% solve rate.
- Offsets: −500 for warm-up, 0 for rated play.

**Teaching mechanics:**
- **Hints:** idea → target → piece → move. Each hint lowers the FSRS grade.
- **On failure:** the board shows why the move fails, and the user gets one retry before the reveal.
- **Arrows:** green for solution, red for threat, blue for hint.
- **CCT prompt:** shown, then faded as the safety skill rises.
- **Motif check:** an occasional "which motif was this?" after a solve.

**Reviews:**
- FSRS-6 (`swift-fsrs`, MIT) schedules missed puzzles, own-game mistakes and opening lines.
- Some reviews substitute a *similar* puzzle (same theme, nearby rating) to block rote memorization.

**Speed warm-up:** 3 minutes.

**Deferred:** Woodpecker mode, blindfold, guess-the-move, strategy lessons.

### Openings

**Repertoire:**
- Annotated PGN in the bundle, parsed into a `repertoire_node` tree.
- Each node carries: idea text, arrows, highlights, a deviation flag and a trap flag.
- Style-specific starter sets.

**Learn mode:**
- Steps one move at a time, showing arrows for the move and its threat plus a 1–2 line reason.
- Branch points pause and show the realistic replies at the user's level (Maia/explorer stats, cached), along with traps and refutations.
- "What if I skip this move?" plays out the refutation.
- With AI, the walkthrough is Socratic: it asks before it tells and draws through tools.

**Drill mode:** the opponent picks branches weighted by popularity. A miss creates an FSRS card.

**From games:** the app flags the point where the user or the opponent left the repertoire and offers to add that branch.

### Play Coach

- **Opponent:** the teaching bot, or weakest Maia offline.
- **After a user Mistake/Blunder:** the game pauses and offers **Take back and try again** or **Show me**.
- **Before the user's move:** if the opponent just created a threat whose motif is in the user's weakness profile, show a subtle "check for threats" nudge. The nudge frequency fades as that weakness improves.
- **Hints:** the same hint ladder as drills.
- **After the game:** goes straight to Review.

### Daily plan (Today tab, default 15 min)

| Block | Share | Content |
|---|---|---|
| Warm-up | 10% | board vision + speed set |
| Reviews | ≤35% | due FSRS cards |
| Focus | 35% | top-2 skills; lesson first if not mastered; includes decoys |
| Mixed | 15% | weighted toward weak themes |
| Endgame / own mistake | 10% | one slot |

- **Skill priority:** 0.30·game-weakness + 0.25·rating-gap + 0.20·motif-frequency + 0.15·uncertainty + 0.10·staleness.
- Every item shows its reason, and every planner decision is logged with its inputs.
- **Weekly plan:** a Sunday summary with next week's focus. Claude writes it when online; otherwise a template is used.

## 6. AI layer

**Client:**
- Anthropic Messages API with tool use, called directly from the phone with streaming.
- Model: Claude Sonnet (latest) by default, Haiku for cheap phrasing. The model id is config.
- The cap is enforced client-side from `ai_call` cost sums ($80/mo). Above the cap, the app falls back to templates.

**Tools (executed on the phone; schemas shared with the later PC MCP server):**

| Tool | Returns |
|---|---|
| `get_position` | FEN, side to move, material, history, opening name |
| `legal_moves` | all legal moves (SAN) |
| `evaluate_moves(moves?)` | Stockfish win% per move + top lines |
| `human_moves(rating)` | Maia move probabilities at a rating |
| `position_facts` | fact-extractor output |
| `player_profile` | weakness profile, recent mistake types, style, skill ratings |
| `draw(arrows, highlights)` | renders on the user's board |
| `play_move(move)` | teaching bot only; must be legal and from the supplied candidate set |

**Validator:**
- Every SAN and square that Claude outputs must appear in the fact sheet or the tool results for the turn.
- On failure, the app makes one corrective retry. If that also fails, it shows the template.
- Failures are logged with the reason.

**Teaching bot:**
1. While the user thinks, the phone precomputes the top-k candidates with SF win%, Maia probability and facts.
2. Claude receives a teaching brief (focus skills, recent mistakes, game so far) and picks a move plus a one-line rationale. The rationale is logged.
3. Guardrails (enforced in code):
   - The move must be legal.
   - Its EP loss must be ≤ a level-scaled cap.
   - At most ~1 deliberate "teaching gift" per 8 moves; other moves come from low-Elo Maia's distribution.
4. The bot speaks only at coach triggers.
5. **Graduation:** after ~6 wins in the last 10 games vs the teaching bot, the app suggests Maia. The user can switch back freely.

Expected latency is 1–3 s per move thanks to precompute.

**Later:**
- M7: Apple Foundation Models (iOS 26, A17 Pro+) for short offline phrasing.
- PC MCP server reusing the tool schemas for Claude Code/Desktop.

## 7. Home PC server (`chesscoach-server`)

- **Platform:** FastAPI on Windows, run as an NSSM service, bound to the Tailscale IP only (check the bind address on cutover; see the zee-platform lesson).
- **Auth:** Tailscale `whois` on every request. Only the owner login is accepted.
- **Endpoints:**
  - `/health`
  - `/key` (key from the PC's central `.env`; see the keymgr reference)
  - `POST /analysis/jobs` (idempotent job UUID) and `GET /analysis/jobs/{id}`
  - `POST /maia/predict`
  - `POST /sync/push` and `GET /sync/pull`
- **Engines:** Stockfish 19 (big net); Maia-2 and Maia-3 on CPU or ONNX DirectML. The GTX 980 Ti is sm_52 and is unsupported by current PyTorch.
- **Libraries:** python-chess is used (GPL is fine server-side).
- **Logging:** emits the same StepEvent schema as JSON lines.
- **Tests:** pytest, BDD names.

## 8. Data model (GRDB)

| Table | Key fields |
|---|---|
| `game` | id = chess.com URL or local UUID, pgn, time_control, color, result, ratings, end_time, source |
| `position_cache` | fen_key → eval, pv (MultiPV), engine, version, depth, source |
| `move_analysis` | game_id, ply, win_before, win_after, classification, best_move, mistake_type, time_trouble, source |
| `motif` | analysis_id, tag, phase |
| `fact_sheet` | fen_key + move → facts JSON |
| `explanation` | fen_key + move → text, origin (template/claude), validated |
| `puzzle` | id, fen, moves, rating, rd, themes, popularity (bundled, read-only) |
| `drill_item` | id, fen, solution, theme, origin (puzzle/game/opening/generated), source_ref |
| `review_card` | drill_item_id, FSRS state (stability, difficulty, due, reps, lapses), history |
| `skill_rating` | theme → glicko rating, rd, volatility, attempts |
| `lesson_progress` | lesson_id, state, best_score |
| `repertoire_node` | id, parent_id, san, idea, arrows, highlights, deviation, trap, repertoire |
| `profile` | style, quiz_score, history_score, rating, placement |
| `weakness_snapshot` | computed_at, vectors (motif/mistake/phase) |
| `ai_call` | ts, model, input/output tokens, cost_usd, tools, latency_ms, validated |
| `step_event` | see §9 |
| `sync_job` | uuid, type, status, payload_hash |

**Ownership:**
- The phone is authoritative for user state.
- The PC is authoritative for deep analysis.
- Sync pushes phone deltas (backup) and pulls deep results.
- Idempotent job UUIDs prevent double counting.
- A new install restores from the PC.

## 9. Logging & telemetry (cross-cutting, mandatory)

- **One schema:** `StepEvent { id, runID, parentID?, step, phase: start|progress|finish|fail, done?, total?, durationMs?, metadata: [String: JSON], error? }`. Steps nest (import → month → game; analysis → ply → engine/classify/facts/explain).
- **One API:** `Telemetry.step("analysis.ply", parent:) { ctx in ... ctx.progress(done, total) }` emits start/finish/fail automatically, including the duration.
- **Sinks:**
  1. `os.Logger` (subsystem `com.rishi.chesscoach`, privacy-redacted, zero `print()`).
  2. GRDB `step_event` table (30-day rolling).
  3. `AsyncStream<StepEvent>` that the UI subscribes to for progress bars, timers and ETAs. ETAs come from the historical `durationMs` median per step.
  4. Shipped to the PC on sync.
- **Coverage:**
  - import, every analysis stage, every Claude call (tokens, cost, tools, latency), drill sessions, planner decisions with inputs, sync, and key handoff (outcome + key_id only)
  - engine lifecycle and thermal pauses
- **Enforcement:** a test asserts that every public pipeline entry point emits start + finish/fail. A new pipeline step cannot ship unlogged.
- **Server:** the same schema as JSON lines.

## 10. Error handling

| Failure | Behaviour |
|---|---|
| PC unreachable | ≤1.5 s timeout, "offline" chip (ConnectionBanner style), jobs queued |
| chess.com 429/down | backoff, keep cache, show last-import time |
| Claude error / no key / cap reached | templates; spend meter in Settings |
| Validator failure | 1 retry → template; logged |
| Engine crash / thermal | pause, resume from last completed ply; partial results kept |
| Bad PGN | skip game, log, continue |

## 11. Testing

- **Approach:** test-first (TDD), BDD naming.
- **Formulas:** win%/accuracy against Lichess reference values; classifier boundary cases on constructed positions.
- **Fact extractor:** a ~50-position golden suite (forks, pins, back-rank, …).
- **Golden games:** some of the user's real games are compared against chess.com's labels to tune thresholds.
- **Planner:** deterministic for fixed inputs; priority math unit-tested.
- **Validator:** rejects hallucinated SAN/squares. Teaching-bot EP cap is enforced.
- **Logging:** the logging enforcement test from §9.
- **UI:** XCUITest per main flow. Board drag and premove get a manual on-device checklist.
- **Server:** pytest.

## 12. Build order (milestones)

| # | Milestone | Deliverable | Built on |
|---|---|---|---|
| M0 | Spikes (2–3 days) | On-device: SF17 depth-16 time/heat, Lc0 + Maia-1 1100 move latency, Maia-2 CoreML conversion feasibility, 120 Hz drag prototype, piece set + sound set picked | Mac |
| M1 | **Base app** | XcodeGen project, DesignSystem port, 4-tab shell, GRDB, Telemetry, BoardView + game screen, sounds/haptics, Play vs Maia & Stockfish, clocks, PGN save | Mac |
| M2 | Analysis | import, phone pass, formulas, classifier, fact extractor, templates, review screen, Retry/Follow-up, Recurring Mistakes | Mac |
| M3 | Drills + Today | onboarding, puzzle bundle, lesson ladder, generated drills, FSRS, Glicko skills, planner, offline Play Coach | Mac |
| M4 | Openings | style repertoires, Learn/Drill modes, left-repertoire flags | Mac |
| M5 | Home PC | chesscoach-server, whois auth, key handoff, deep analysis, Maia-2/3, sync | PC via Dispatch |
| M6 | AI layer | Anthropic client, tool loop, validator, Claude explanations, Socratic openings, teaching bot, weekly plan, spend meter; later PC MCP | Mac + PC |
| M7 | On-device LLM | Foundation Models phrasing (iOS 26 gate) | Mac |

**Base version** = M0 + M1. M2–M4 complete the fully offline app. M5–M7 add networking and AI on top.

## 13. Licensing (personal build)

- **GPL-3:** Stockfish, Lc0 and Maia-1 weights are compiled or bundled. This is acceptable for a personal sideload only.
- **NC piece sets:** acceptable for personal use only.
- **CC0:** Lichess puzzles and openings.
- **AGPL:** the Lichess tagger and the Lichess app code. Ideas are reimplemented; no code is copied.
- **Not copied:** no WintrChess, freechess or Chesskit-web code is copied (GPL/AGPL/NC); formulas are reimplemented from public sources.
- **No chess.com assets:** no pieces, sounds, classification glyphs or code. The layout and interaction are replicated with original or open assets. The board colors are a personal-use choice.
- **Before any distribution:** re-review everything in this section.
