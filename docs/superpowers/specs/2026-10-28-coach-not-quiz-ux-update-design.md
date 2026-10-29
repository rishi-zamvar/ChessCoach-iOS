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
  weeks of work. Free tier: 1M events + 2.5k mobile session replays a month, iOS SDK with replay, funnels,
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
Build, don't buy: Sentry/PostHog Surveys/Shake/Instabug can't show "Fixed in build N" back to the user,
Shake's free tier is 30 reports/month, Instabug has no free plan, PostHog Surveys has no screenshot or
markup and no iOS feedback-button support. Our sheet is ≈300 lines + one endpoint.
1. **Entry points:** a feedback icon (speech bubble) in every tab's top bar next to the Settings gear
   (visible beats hidden: NN/g measured 20–50% lower discoverability for hidden menus); "Send feedback" in
   the ⋯ menu of every full-screen board (puzzle runner, game, review, lesson, analysis). No floating button.
2. **Screenshot trigger:** on `userDidTakeScreenshotNotification` show a small toast "Report a problem with
   this screen?" (once per session).
3. **Shake is opt-in:** on by default in TestFlight builds only, Settings toggle otherwise; ignored while a
   board/clock is active or a text field is focused (Apple HIG reserves shake for undo).
4. **Sheet:** screenshot captured *before* the sheet appears, shown as a thumbnail with an include toggle and
   PencilKit highlight/blackout; optional category chips (Bug · Confusing · Idea · Praise) that never block
   Send; one text field focused on open; draft autosaved; "Include diagnostic details" toggle (on) with a
   "What's included?" expander.
5. **Context attached automatically:** screen name + view state (puzzle id/FEN/mode, plan block, game id,
   review ply), last 50 telemetry events as breadcrumbs (scrubbed: no email, no free-text inputs),
   build/version, device, OS, locale, network state, AI provider (never the key), consent tier, PostHog
   distinct/session id. Sensitive views (API key fields) carry `.postHogMask()`.
6. **Transport:** client UUID as idempotency key; payload + image written to disk first, retried on launch and
   on `NWPathMonitor` reconnect. `POST /v1/feedback` on the public server (chess.zamvar.io, App Attest, 64 KB body cap
   for JSON + separate image upload ≤ 1 MB JPEG) → SQLite row + image on the PC. Queued on device and
   retried when offline. Also emits PostHog `feedback.submit{category, screen, feedback_id}` so each report
   links to the session replay (rich tier) and shows on the dashboard.
7. **Triage:** a new report sends a ZeeChat ping with category + first line; a `scripts/feedback.sh`
   lists/exports reports (and pulls TestFlight feedback through the ASC API into the same table).
8. **Reply loop:** confirmation "Sent. Track it in Settings → Your feedback." Server status Received · Fixed in
   build N · Won't fix; the app shows a badge on first launch of a build ≥ N. Push only if notifications are
   already allowed. KPI: feedback per 100 WAU, by screen and category.
9. **Micro-prompts:** inline 👍/👎 under coach explanations, puzzle explanations and game reviews (👎 opens an
   optional "What was off?" line) → `feedback.thumb{surface,value}`. Budget: one prompt per session, none
   during timed play, 30-day pause after two dismissals. No NPS until there's volume.
10. **App Store review prompt:** `requestReview` only after a success moment (puzzle streak, won game, 👍),
    once per version, 7+ days after install, never after 👎 or a bug report.

### W9 One design system on every screen
**Audit (HEAD).** Two complete visual languages. *Apothecary* (`Palette`/`Typography`/`Spacing`/`Card`/
`BackgroundAtmosphere`; cream paper, serif italic display, sage + rose) covers the 4 tab hubs and onboarding.
*ChessChrome* (13 colour tokens copied from chess.com: charcoal `#302E2B`, green `#81B64C`, hard-coded
`.system(.rounded)` fonts, ~115 literals, 0 Typography use) covers every board screen: GameScreen, PuzzleView,
TrainingRunner, PuzzleRush, Lesson, VisionDrill, Openings session, Review. `ReviewScreen` forces
`.preferredColorScheme(.dark)` (line 51) so it flips theme when opened from light Analyze. The same green
radius-10 button exists 4 times (`PuzzleButton`, Review, GameScreen, ResultCard). Onboarding switches to
ChessChrome for placement. Settings/board-options are untinted stock Forms. No Dynamic Type (every font is
`system(size:)`), no Reduce Motion handling, 6 accessibility labels vs 108 identifiers, the board is one
"Chess board" element. Leftovers from WorkoutCoach: felt colours, `StepperButton`, `TimeMinSecField`,
unattached toasts, unused animations, an opaque tab-bar appearance iOS 26 ignores.

**Decision: evolve Apothecary into "Knightlight Paper", delete ChessChrome.** Apothecary is the only layer with
type/spacing/components and already matches the research recommendation for a coach app: follow the system
appearance, but design light as the hero (positive polarity reads better for text-heavy coach chat, lessons
and reviews), warm charcoal in dark, serif display, and clearly not chess.com green-on-charcoal.

**Rules (from HIG + WWDC25 "Get to know the new design system").**
- Liquid Glass only on the navigation layer: tab bar, nav/toolbars, the board control cluster
  (prev/next/flip/hint/analyze, in one `GlassEffectContainer`), the coach chat input. Never on cards,
  the board, move list or bubbles. One tinted (prominent) action per screen. Must still read with Reduce
  Transparency and the 26.1 Tinted look.
- Follow the system appearance; no app appearance setting; no forced schemes.
- Every font is a text style (Dynamic Type + Bold Text). Serif (New York) for display, titles and the coach's voice.
- Never colour alone: move quality always shows its glyph.

**Tokens** (asset-catalog colours with Any/Dark/High Contrast; views only use semantic names).
| Token | Light | Dark | Notes |
|---|---|---|---|
| `surface.base` | `#F6F4EF` | `#181715` | every screen, boards included |
| `surface.raised` | `#FDFBF6` | `#23211E` | cards, sheets |
| `surface.sunken` | `#EFEBE3` | `#100F0E` | inputs, wells, move list |
| `separator` | ink 12% | paper 12% | hairlines |
| `text.primary` | `#2B2523` | `#F2EDE6` | |
| `text.secondary` | `#6B625D` | `#B5ADA5` | |
| `text.tertiary` | `#8F867E` | `#857D76` | ≥ 4.5:1 checked on both surfaces |
| `action.primary` | `#2B2523` | `#F2EDE6` | ink capsule CTA, label = surface.base |
| `accent.sage` | `#4F7560` | `#8DB59C` | coach ring, progress, links (was primaryDeep) |
| `accent.rose` | `#B06F6F` | `#E6A8A8` | streak, warmth only |
| `status.success` / `danger` / `warning` | `#2F7D4F` / `#B23A1E` / `#A87F00` | `#5CC98A` / `#FF7A52` / `#F0D24A` | |

Move quality (Okabe-Ito based, glyph + colour, light/dark): Brilliant `!!` `#00897B`/`#3CC9B8` · Great `!`
`#0072B2`/`#56B4E9` · Best `★` `#2F7D4F`/`#5CC98A` · Good `✓` `#6B7F70`/`#93A898` · Book `#8C6E4E`/`#C2A07C`
· Inaccuracy `?!` `#A87F00`/`#F0D24A` · Mistake `?` `#D9730D`/`#F5A04A` · Blunder `??` `#C0392B`/`#FF6B5B`
· Miss `✕` `#CC79A7`/`#E7A3CC`. Replaces the hex literals in `ReviewScreen.swift:695-705`.

Board: themes unchanged and user-selectable via `@Environment(\.boardTheme)`; default becomes **Sage**
(`#E9EDDF`/`#7D9672`, sits with the brand) instead of chess.com green; board dimmed 6% in dark; radius 8.
Overlays: last move `#E9C46A` 45%, selected ink 25%, legal dots ink 20%, coach arrow sage 85%, best line
best-green 80%, threat blunder 80%. Eval bar `#F4F1EA`/`#2A2724` with hairline midline (was fixed `#403D39`).
Clock tokens move from ChessChrome into the palette.

Type (`KLFont`, all text styles): display = largeTitle serif semibold · title = title2 serif semibold ·
section = headline · body = body · coachSpeech = body serif · meta = subheadline · caption = caption ·
numeric = title3 monospacedDigit semibold · moveSAN = body monospaced. Left-aligned. Spacing keeps the 4pt
scale (4/8/12/16/24/32/48, gutter 16, card gap 12); radii chip = capsule, inner 12, card 20, board 8,
nested = `ConcentricRectangle`. Elevation: opaque raised surface + hairline; light-mode shadow y1 blur3 6%;
no shadows in dark. Background: one `AppBackground` (base + 5% grain; sage/rose mesh on hubs only, 50% of
today's strength).

**Components** (one each, everything else deleted): `KLCard`, `SectionHeader`, `PrimaryButton` (ink capsule
50 pt), `SecondaryButton`, `GlassIconButton`, `BoardControlCluster`, `StatTile`, `CoachBubble`, `UserBubble`,
`EvalBar`, `MoveListRow`, `QualityBadge`, `ArrowOverlay`, `PuzzleResultBanner`, `EmptyState`, `Toast`
(attached at root), `FeedbackButton` (W8).

**Motion and feedback** through one `Feedback` helper honouring Settings toggles and the silent switch:
move light impact · capture medium · check rigid · puzzle right `.success` · wrong `.warning` · scrubbing
`.selection` · nothing on opponent moves. Piece slide 180 ms ease-out, illegal snap-back 120 ms, eval 300 ms.
Reduce Motion: instant placement + 100 ms fade, no pulses or slides (`CoachLineBubble` pulse included).

**Accessibility.** Labels on every icon button; board exposes 64 squares ("e4, white knight") with VoiceOver
move entry by square; Dynamic Type up to AX5 with board-first layouts that scroll; contrast ≥ 4.5:1.

**Enforcement.** SwiftLint `custom_rules` outside `DesignSystem/`: ban `Color(red:`, `Color(hex:`,
`.font(.system(size:`, `Font.custom` without `relativeTo`, numeric `cornerRadius:`/`.padding(<n>)`.
Snapshot tests (swift-snapshot-testing) for every screen × light, dark, AX5 text, dark + Increase Contrast.

**Per-screen checklist:** base background, no literals, serif headers left-aligned, ≤1 prominent action,
glass only on nav/controls, board via environment theme, quality via `QualityBadge`, feedback via helper,
snapshots pass. Screens: Today, Train, Analyze, Play home, Onboarding (no chrome switch), GameScreen,
TrainingRunner + Puzzle/Lesson/Vision, Rush, Openings session, Review (drop forced dark), Analysis board (W4),
Settings + board options (tinted, grouped), AskCoach, Feedback sheet.

## Milestones
- **M1 — Foundation + unstuck + measure (≈3 days):** W9 tokens, `KLFont`, components, lint rules and
  snapshot harness; W1; W7 Basic tier + taxonomy; W8 feedback sheet + endpoint; privacy manifest; display
  name. Ship to TestFlight, ask testers to update.
- **M2 — Board screens + explain + explore (≈4 days):** re-skin every board screen onto W9 and delete
  ChessChrome; W2, W4, W5.
- **M3 — Coach mode (≈3 days):** W3 behind `coach_mode_default`, W7 Rich tier + consent + delete my data.
- **M4 — Polish + accessibility (≈2 days):** rest of W6, VoiceOver board, Reduce Motion, streak freeze, KPI
  dashboard + ASC report pull, remove WorkoutCoach leftovers.

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
- `test_givenBoardActive_whenShake_thenFeedbackSheetNotShown`
- `test_givenPromptShownThisSession_whenNextPromptDue_thenSuppressed`
- `test_givenEveryScreen_whenSnapshotInLightDarkAX5HighContrast_thenMatchesReference`
- `test_givenMoveClass_whenBadgeRendered_thenGlyphAndTokenColourBothPresent`
- `test_givenReduceMotion_whenPieceMoves_thenNoSlideAnimation`
- `test_givenBoard_whenVoiceOverReadsSquare_thenLabelNamesSquareAndPiece`

## Out of scope
Paywalls/subscriptions, social features, online multiplayer, Android, rewriting the planner algorithm.

## As built (branch feat/0.9-m1, 2026-10-29)
All four milestones are implemented. Where the build differs from the text above:
- **Enforcement**: `scripts/lint-design.sh` (grep) instead of SwiftLint, which isn't installed; it fails on raw
  colours, fixed font sizes and numeric radius/padding literals outside `DesignSystem/` and `Board/` (zero left).
  `scripts/testflight.sh` runs it.
- **Snapshots**: components and the feedback sheet are compared references (`ChessCoachTests/__Snapshots__`).
  Today and the completion card change with the date, so they render to `ChessCoachTests/ScreenRenders/`
  (git-ignored) for visual QA, and their logic is asserted instead.
- **Tokens** live in code (`Palette`, `Color(light:dark:lightHC:darkHC:)`) rather than the asset catalog.
- **ChessChrome** is deleted; its tokens map onto Palette. The 4 duplicate buttons are one `ActionButton`.
- **Coach mode** applies to plan puzzles, skill sets and failed-puzzle reviews. Own-game mistake reviews stay
  instant (they carry the "your move vs better" insight card). Quick warm-up and Rush are always instant.
- **Analyze** entry points: puzzles, Coach puzzles, Rush misses, Review, finished games, lessons, Analyze tab
  (paste FEN/PGN). Mode switch: the puzzle header chip (from the next puzzle) and Settings.
- **Rich tier**: session replay switches on at the next launch after opting in (PostHog config is per launch).
- **Analytics is off in this build**: `PostHogAPIKey` in project.yml is empty. Add the EU project key to turn
  on both tiers and the `coach_mode_default` flag; until then Coach mode is the default.
- **Server** (deployed, live at chess.zamvar.io): `POST/GET /v1/feedback`, `POST /v1/privacy/delete`,
  `GET /privacy`; `server/scripts/feedback.py list|show|status|notify|deletions|testflight` on the PC
  (`testflight` imports TestFlight feedback into the same table; needs the ASC key on the PC).
- **App Store Connect**: `uv run scripts/asc.py feedback | whattotest <build> <text> | analytics request|download`.
  Ongoing analytics reports were requested 2026-10-29 (Apple's first files arrive within ~48 h).
- **PostHog**: `uv run scripts/posthog-setup.py` creates both experiment flags and the "Knightlight core"
  dashboard (13 insights from the KPI table) once a project and personal key exist.
- "Blunder" in already-lost positions was already handled by `MoveClassifier` (decided positions cap at
  inaccuracy). The bot's replies no longer buzz (`SoundSink.play(_:byUser:)`). Board: 8 pt radius, dimmed 6% in dark.
