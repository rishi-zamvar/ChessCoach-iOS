# Knightlight 0.9 — "Coach, not quiz" UX update

Goal: every screen has a next step, every wrong move gets a reason, every position can be explored,
and we can finally see how people use the app.

Inputs: 2 TestFlight feedback submissions (build 43, 2026-10-28, anonymous UK tester, iPhone 17 Pro Max),
a code walk of HEAD `b0965f0` (build 61), and a competitor review (Chess.com, Lichess, Chessable,
Aimchess, Noctie, Dr. Wolf, ChessKid, ChessBase/ChessTempo, Duolingo streaks).

## Tester feedback (verbatim)
1. *Puzzle, 07:02:* "These puzzles are good, but you must explain why any move is a mistake. You must have
   an 'Analyze' function, where players can try out different moves against the engine. Also puzzles should
   not have an immediate right or wrong move function. If they make a wrong move … continue letting them play,
   and then at the end, tell them that one of their moves was wrong, and then let them figure out where they
   went wrong. Only then can players improve. That is what a coach does."
2. *Today tab, 14:51:* "Cannot progress beyond this page." (screenshot: all 5 plan items ticked, "Done for today")

The tester is 18 builds behind (43 vs 61). Build 57+ already removed the PC status card they saw and
339f1ea added mistake explanations in Review. Neither complaint is fixed by those builds.

## Decisions (locked 2026-10-28, user: "go with whatever is most optimal on our setup")
- **Two puzzle modes.** *Coach* (deferred feedback, the tester's ask) is the default for plan blocks,
  lessons and reviews. *Drill* (instant right/wrong) stays for Speed set and Puzzle Rush. The research on
  delayed feedback is mixed, so Coach-as-default ships behind a feature flag and is A/B tested.
- **Refutation first, words second.** A wrong move is always shown being punished on the board (engine
  reply), then explained with the existing `FactExtractor` → `Explainer` template; LLM/on-device rewrite only
  after the existing grounding check. Works offline with no key.
- **One analysis board** (`AnalysisBoard`) reused everywhere; no per-screen variants.
- **Analytics = PostHog Cloud (EU region), free tier**, fed by a new `TelemetrySink`. Not self-hosted:
  PostHog self-host needs a 4-core/16 GB Docker stack the PC shouldn't carry, and a home-built dashboard is
  weeks of work. Free tier: 1M events + 5k session replays a month, iOS SDK with replay, funnels,
  retention, person profiles, feature flags. Upgrade path: pay-as-you-go, same SDK.
- **Two consent tiers**: Basic usage (anonymous, on by default, opt-out) and Rich profile (identified,
  opt-in at onboarding). Details in W7.

## Pain map (what's wrong today)
| # | Problem | Evidence | Sev |
|---|---|---|---|
| P1 | Plan block that can never complete → user loops on Today | "Reviews" consumes due mistake reviews, so "Your mistakes" recomputes to 0 tasks; runner shows "Nothing to do here right now." + X only, `onComplete` never fires (`TrainingService.swift:148-166`, `TrainingRunnerView.swift:21-24`) | Critical |
| P2 | "Done for today" is a dead end | `PlanCard.swift:21,37` hides Start, nothing replaces it; block end = "Block complete" + Done only (`TrainingRunnerView.swift:113`) | High |
| P3 | Cards look tappable but aren't | Play a game, Recent games, Top mistake, Week stats, Recurring mistakes | High |
| P4 | Wrong move gets no reason | "`Nf3` isn't it. Try again." (`PuzzleView.swift:150`); Rush has no miss review | High |
| P5 | No way to explore a position vs engine | Board non-interactive after solve (`PuzzleView.swift:68`); Review only interactive in retry; no FEN/PGN paste | High |
| P6 | Instant right/wrong only | Tester; ChessTempo "continue on failed problem", Chess.com Learning mode show demand | Medium |
| P7 | Valid alternative wins rejected | Top Lichess complaint; our session matches exact solution moves only | Medium |
| P8 | Inconsistent board settings | Coordinates toggle read only by GameScreen; vision drill always White-side, doesn't show the correct square on a miss | Low |
| P9 | Jargon and naming | "Speed set", "Mixed puzzles", "Reviews", two ratings; app display name still "ChessCoach"; learner brief hard-coded "chess.com rapid ~300" (`TrainingService.swift:99`) | Low |
| P10 | No offline indicator | `ConnectionBanner.swift` exists, unused | Low |
| P11 | Duplicate plan card on Train with separate state | `TrainView` + `TodayView` | Low |
| P12 | Zero cross-user data | Telemetry writes `step_event` on device only; no KPIs exist | High |

## Workstreams

### W1 Never a dead end (fixes P1, P2, P3, P11)
1. **Plan tasks are reserved at plan time.** `DailyPlanner` snapshots each block's task IDs into the frozen
   plan; `tasks(for:)` reads the snapshot, so blocks can't steal each other's items.
2. **Empty block auto-completes.** If a block still resolves to 0 tasks, mark it done with reason `empty`
   and show "Nothing due here, moved on" — never the X-only screen. Telemetry event `plan.block_empty`.
3. **Block end has a forward button**: "Next: Mixed puzzles (5 min)" primary, "Back to Today" secondary.
4. **Completion card** replaces the plan when done: today's summary (puzzles, accuracy, lesson, reviews,
   streak) + 3 optional CTAs ranked by weakness: *Bonus 5 on <weakest theme>*, *Review your last game*,
   *Play the coach*. Then "Tomorrow: <first block> · <first focus skill>". Never generate an endless plan.
5. **Everything that looks like a button is one**: Play a game → Play tab; Recent game → Review;
   Top mistake → practice that pattern; Reviews due → review run; Week stats → Progress sheet.
6. Train shows a link to Today's plan instead of a second PlanCard. Today bottom padding = Train (80 pt).
7. Closing a run mid-block asks "Leave? Progress so far is saved" and saves partial progress.

### W2 Every wrong move gets a "why" (P4)
1. On a wrong move (both modes): the move is played, the engine's best reply animates (max 2 plies, 0.6 s
   each), a red arrow marks the refuting move, then the caption: one sentence built from engine facts
   ("Bxf7+ loses the bishop: after Kxf7 nothing wins it back.", "Allows Qh7#.", "Drops the e5 knight.").
2. Board then rewinds to the puzzle position (Drill: try again; Coach: see W3).
3. Puzzle Rush end screen lists every miss with your move, the answer, the reason, and "Analyze".
4. Copy rules: name pieces and squares, no eval numbers by default, no "Blunder" label when the position was
   already lost (say "best try was …").

### W3 Coach mode puzzles (P6)
1. User's move is accepted whatever it is. Opponent replies with engine best. Play continues until the
   solution line length + 2 plies, a decisive result, or eval settles.
2. If every move was good: "Solved." If any move dropped eval past the mistake threshold (same thresholds as
   GameAnalyzer labels): "One of your moves was a mistake. Can you find which?" Move list becomes tappable.
3. User taps the move. Right → board rewinds there, "Now find the better move" with the existing hint
   ladder (theme → piece → arrow). Wrong pick → "Not that one — the position was still fine after it" (max 2
   picks, then the mistake is highlighted).
4. Outcome grades feed the scheduler and rating: `clean` (=solved), `selfFound` (found mistake + fixed),
   `assisted` (needed highlight/hints), `revealed`. First-move correctness still drives puzzle rating so
   ratings stay comparable across modes.
5. Mode toggle in puzzle header and Settings ("Feedback: Coach / Instant"). Default from feature flag
   `coach_mode_default`.

### W4 Analysis board (P5)
1. `AnalysisBoard(fen:history:)` view: any legal move for either side, eval bar, top 3 lines (tap to
   preview), "Explain this move" (Explainer, offline), undo/redo, flip, reset to start, copy FEN/PGN.
2. "Play from here" toggle: engine answers your moves (Stockfish level or Maia 1100, like Play).
3. Entry points: an **Analyze** button on every board — puzzle (after solve/reveal and during W3 reveal),
   Rush misses, Review (any move), lessons, game result card, coach game. Analyze tab gets an
   "Analysis board" row with paste FEN/PGN.
4. On-device Stockfish only; deep analysis server path unchanged.

### W5 Accept alternative wins (P7)
Move not in the solution but eval stays winning (mate found, or ≥ +3.0 and within 1.0 of the solution
eval at depth 14): "Good move — that wins too." Counts as solved; show the intended line as "Also good".

### W6 Clarity and consistency (P8, P9, P10)
- Rename: Speed set → **Quick warm-up**, Mixed puzzles → **Mixed practice**, Reviews → **Spaced review**,
  Puzzle rating labelled "Knightlight puzzle rating" with chess.com rating shown separately.
- Coordinates setting applies to every board; "You play Black" chip on flipped puzzles; vision drill
  flips with the user's colour and shows the correct square in green on a miss; drill count matches plan.
- Wire `ConnectionBanner` (only when the user taps something that needs the network).
- Display name "Knightlight" (`project.yml`). Learner brief built from profile, not hard-coded.
- Streaks: one free weekly freeze, streak = any finished block, gentle copy on a break.

### W7 Analytics and KPIs (P12)
**Architecture.** `PostHogSink: TelemetrySink` in the app target (package stays SDK-free) maps
`StepEvent`s to PostHog events, plus `screen` events from a `.trackScreen("today")` modifier. Events queue
offline in the SDK and flush on network. The existing `step_event` table is kept (on-device debug).

**Consent tiers.**
| | Basic usage | Rich profile |
|---|---|---|
| Default | On; toggle in Settings → Privacy | Off; asked once at end of onboarding ("Help us coach you better") |
| Identity | Random install ID, no person profile | `identify(sha256(appleUserID) or install ID)` + person props: chess.com username, ratings, style, skill ratings, plan length, AI provider (not key), device, locale |
| Data | Screen views, feature use, durations, errors, block/plan outcomes | Everything in Basic + per-puzzle detail (id, theme, rating, moves, mode, grade, hints, time), game summaries, coach interactions, session replay (text inputs and API key fields masked) |
| Privacy label | Usage Data, Diagnostics — Not Linked to You | Usage Data, Identifiers, User Content (gameplay) — Linked to You |

No ATT prompt: we don't track across other companies' apps. Required alongside: `PrivacyInfo.xcprivacy`
collected-data entries, App Store privacy label update, privacy policy page (host on chess.zamvar.io),
Settings → "Delete my data" (PostHog person delete via a server endpoint holding the personal API key),
retention 12 months, EU data region. UK/EU users: rich tier only after explicit opt-in.

**Event taxonomy** (snake_case, `area.action`):
`app.open`, `screen.view{name}`, `onboarding.step{step}`, `onboarding.done{placement_rating}`,
`plan.built{blocks,minutes}`, `plan.block_start{kind,skill}`, `plan.block_done{kind,tasks,accuracy,secs}`,
`plan.block_empty{kind}`, `plan.block_abandon{kind,done,total}`, `plan.done`, `plan.cta{which}`,
`puzzle.done{id,theme,rating,mode,grade,hints,secs,first_move_ok}`, `puzzle.wrong_move{reason_kind}`,
`analysis.open{from}`, `analysis.move`, `analysis.explain`, `review.open{source}`, `review.retry{label}`,
`game.start{opponent,tc,color}`, `game.end{result,moves,holdups}`, `coach.holdup{kind,choice}`,
`coach.ask`, `ai.call{provider,model,ms,cost_usd}`, `lesson.done{id,passed}`, `rush.done{score}`,
`settings.change{key}`, `error{where}`.

**KPIs** (PostHog dashboard "Knightlight core"):
| Area | KPI | Definition |
|---|---|---|
| Activation | Onboarding completion | `onboarding.done` / `app.open` first-session |
| Activation | First block within D0 | users with `plan.block_done` on install day |
| Engagement | DAU, WAU, DAU/WAU | distinct users with `app.open` |
| Engagement | Plan completion rate | `plan.done` / `plan.built` per day |
| Engagement | Post-plan continuation | `plan.cta` / `plan.done` |
| Retention | D1, D7, D30 | PostHog retention on `plan.block_done` |
| Learning | First-try rate by theme, trend | `puzzle.done.first_move_ok` over 4 weeks |
| Learning | Self-found mistakes | share of `grade=selfFound` among Coach-mode misses |
| Learning | Repeat-mistake rate | recurring pattern count per 10 games |
| Coach value | Analyze adoption | users with `analysis.open` / WAU |
| Coach value | AI cost per active user | sum `ai.call.cost_usd` / WAU |
| Friction | Dead ends | `plan.block_empty`, `plan.block_abandon`, sessions ending on Today with no tap |
| Quality | Crash-free sessions | App Store Connect Analytics + MetricKit |

**App Store Connect side.** Request the ongoing Analytics Reports (`analyticsReportRequests`, access
type ONGOING) with the existing team API key for installs, sessions, retention, crashes by build; a
weekly script pulls them into the same dashboard. The current key gets 403 on beta testers: give it the
App Manager role so we can list testers and their builds.

**Experiments.** PostHog feature flags: `coach_mode_default` (50/50), `completion_cta_set` (A/B CTA order).
Primary metric D7 retention, guardrail plan completion rate.

### W8 In-app feedback, one tap from every screen
TestFlight's shake-to-feedback only exists in TestFlight builds, carries no app context, and can't be
answered. We own it instead.
1. **Entry points:** a feedback icon (speech bubble) in every tab's top bar next to the Settings gear;
   "Send feedback" in the ⋯ menu of every full-screen board (puzzle runner, game, review, lesson, analysis);
   shake gesture anywhere. No floating button over the board.
2. **Sheet:** category (Bug · Confusing · Idea · Praise), free text, screenshot of the screen it was opened
   from (auto-captured, can be removed or marked up with a pen), "Include diagnostic details" toggle (on,
   with a "what's included" disclosure).
3. **Context attached automatically:** screen name + view state (puzzle id/FEN/mode, plan block, game id,
   review ply), last 50 telemetry events as breadcrumbs, build/version, device, OS, locale, network state,
   AI provider (never the key), consent tier, PostHog distinct/session id.
4. **Transport:** `POST /v1/feedback` on the public server (chess.zamvar.io, App Attest, 64 KB body cap
   for JSON + separate image upload ≤ 1 MB JPEG) → SQLite row + image on the PC. Queued on device and
   retried when offline. Also emits PostHog `feedback.submit{category, screen, feedback_id}` so each report
   links to the session replay (rich tier) and shows on the dashboard.
5. **Triage:** a new report sends a ZeeChat ping with category + first line; a `scripts/feedback.sh`
   lists/exports reports (and pulls TestFlight feedback through the ASC API into the same table).
6. **Reply loop:** reports stay visible under Settings → Your feedback with status (Received · Fixed in build N).
   KPI: feedback per 100 WAU, by screen and category.

## Milestones
- **M1 — Unstuck + measure (≈2 days):** W1, W7 Basic tier + taxonomy for existing flows, W8 feedback
  sheet + server endpoint, privacy manifest, W6 display name. Ship to TestFlight, ask testers to update.
- **M2 — Explain + explore (≈3 days):** W2, W4, W5.
- **M3 — Coach mode (≈3 days):** W3 behind `coach_mode_default`, W7 Rich tier + consent screen + delete my data.
- **M4 — Polish (≈1 day):** rest of W6, streak freeze, KPI dashboard + ASC report pull.

## Tests (written before code, BDD names)
- `test_givenReviewsBlockConsumedMistakes_whenMistakesBlockStarts_thenItsReservedTasksStillRun`
- `test_givenBlockWithNoTasks_whenStarted_thenMarkedDoneEmptyAndPlanAdvances`
- `test_givenPlanDone_whenTodayRenders_thenCompletionCardWithThreeCTAs`
- `test_givenWrongMove_whenPlayed_thenRefutationPliesAndFactCaptionProduced`
- `test_givenCoachMode_whenMistakeThenGoodMoves_thenRevealAsksToFindMistake`
- `test_givenCoachMode_whenUserPicksMistakeMove_thenRewindsToThatPosition`
- `test_givenAltMoveStillWinning_whenPlayed_thenCountsAsSolved`
- `test_givenAnalysisBoard_whenAnyLegalMove_thenEvalUpdatesAndUndoRestores`
- `test_givenBasicTierOnly_whenEventsEmitted_thenNoIdentifyAndNoPersonProps`
- `test_givenRichTierOptOut_whenToggled_thenSDKResetAndReplayStops`
- `test_givenStepEvent_whenMapped_thenPostHogEventNameAndPropsMatchTaxonomy`
- `test_givenFeedbackFromPuzzle_whenSubmitted_thenPayloadHasScreenFenBreadcrumbsAndNoAPIKey`
- `test_givenOffline_whenFeedbackSubmitted_thenQueuedAndSentOnReconnect`
- `test_givenDiagnosticsOff_whenFeedbackSubmitted_thenOnlyTextCategoryAndScreenshotSent`

## Out of scope
Paywalls/subscriptions, social features, online multiplayer, Android, rewriting the planner algorithm.
