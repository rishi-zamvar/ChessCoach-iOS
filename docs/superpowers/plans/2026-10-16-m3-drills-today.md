# M3 Drills + Today Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Train tab and the Today tab become a real coach:
- an offline Lichess puzzle trainer, with a hint ladder and refutation feedback;
- about 15 taught lessons for the 300–1100 band;
- board-vision and safety drills;
- per-theme Glicko-2 skill ratings;
- FSRS reviews of failed puzzles and of the user's own game mistakes;
- an onboarding flow (style, quiz, placement);
- a daily 15-minute plan built from the user's own games, where every item says why it was picked.

**Architecture:**
- **Package (pure, tested):**
  - `Training/Glicko2.swift`
  - `Training/SkillModel.swift`: skill nodes → Lichess tags, ratings, mastery
  - `Training/ReviewScheduler.swift`: wraps swift-fsrs, cards as JSON
  - `Training/PuzzleSession.swift`: opponent's setup move, user moves, the "any mate in 1 is accepted" rule, hints, grading
  - `Training/PuzzleStore.swift`: read-only bundled SQLite
  - `Training/Curriculum.swift`: lesson JSON model
  - `Training/BoardVision.swift`: coordinates; find all checks and captures; is this move safe?
  - `Training/WeaknessProfile.swift`: mistakes → per-skill weakness
  - `Training/DailyPlanner.swift`: research 01 §7.4
  - `Training/TrainingStore.swift`: migration v3 (`skill_rating`, `review_card`, `attempt`, `lesson_progress`, `profile`)
- **App:**
  - `Features/Train/*`: hub, PuzzleScreen, LessonScreen, VisionDrillScreen
  - `Features/Today/TodayView`: the plan
  - `Features/Onboarding/*`

**Tech Stack:**
- swift-fsrs (MIT, pinned revision 4fbaf20), FSRS-6 with the default weights.
- Lichess puzzle DB (CC0), filtered and stratified to about 60k puzzles in `ChessCoach/Resources/puzzles.sqlite`, built by `scripts/build_puzzles.py`.

**Spec:** §3 onboarding, §5 drills, daily plan, §8 tables, §9 telemetry.

## Tasks

1. **Puzzle bundle** (agent):
   - Script: stream the `.zst`, apply the quality filter (RD ≤ 80, popularity ≥ 85, plays ≥ 200, rating 400–2000), then stratify by primary theme × 100-point bucket and cap. Output SQLite tables `puzzle(id, fen, moves, rating, rd, popularity, themes, opening)` and `puzzle_theme(puzzle_id, theme)`, indexed by `(theme, rating)`.
   - `PuzzleStore`: `puzzles(theme:, around:, excluding:, limit:)`, `puzzle(id:)`, `count(theme:)`.
   - Tests use a small fixture database built in the test.
2. **Curriculum content** (agent):
   - `Packages/ChessCoachKit/Sources/ChessCoachKit/Resources/curriculum.json`: about 15 lessons, each with skill, title, idea text, worked example (FEN, UCI moves, per-move narration, arrows), faded example, practice (themes, rating range, or a drill kind) and a mastery rule of 7/10.
   - Every position and move is validated with python-chess by `scripts/validate_curriculum.py`.
3. **Glicko2 + SkillModel:** the skill taxonomy for bands A–F as nodes with Lichess tags and prerequisites. Glicko-2 update against a fixed puzzle rating. A primary tag gets the full update; secondary tags get half.
4. **ReviewScheduler (FSRS):** grades come from the attempt (wrong / bottom-out hint = Again, hint = Hard, clean = Good, clean and fast = Easy). Due queue; sibling swap.
5. **PuzzleSession:** the state machine and grading.
6. **BoardVision generators:** coordinates, all checks and captures, is-this-move-safe.
7. **WeaknessProfile + DailyPlanner:** deterministic, with every item carrying a reason, plus tests.
8. **TrainingStore v3** (migration) + `TrainingService` (app).
9. **UI:**
   - Train hub (plan, skills map, themes)
   - PuzzleScreen (chess.com puzzle look)
   - LessonScreen (worked example with arrows → faded → practice → test)
   - VisionDrillScreen
   - Today plan
   - Onboarding (username, style cards, a 7-position quiz, a 10-puzzle placement)
10. **Verify:** tests, a UI test for one puzzle solved, screenshots, review, merge, tag v0.3.0.
