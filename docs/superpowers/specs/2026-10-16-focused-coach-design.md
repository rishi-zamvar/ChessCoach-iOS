# Focused coach games (Coach bot v2)

Goal: a chess.com-style coach that steers each game toward what you need to practise,
talks instantly in fixed words, and stops you ("Hold up") before a mistake costs you.

## Decisions (locked with the user, 2026-10-16)
- Hold up fires **before the bot replies** (take back / show me / continue).
- Play Coach merges into the Coach bot: one coach opponent. Train's "Play Coach" entry starts a Coach bot game.
- All coach text and speech is deterministic templates. AI (Haiku) only picks among
  engine-vetted bot moves and may *request* a hold-up of a fixed kind; it never writes coach text.

## Units
1. **CoachFocus** (package, pure): `Focus = hangingOwn | freePieces | mates | tactics`.
   `WeaknessTally` (decayed counts: hung, missedFree, missedMate, missedTactic) →
   `pick(tally:puzzleSkills:)`. With no game data, falls back to the weakest of the puzzle
   skills (C1 free pieces, mate skills, fork/pin skills), else `freePieces`. Persisted by the app
   (UserDefaults JSON), updated after every coach game: `tally = tally * 0.7 + gameCounts`.
2. **FocusGifts** (package, pure, engine-free): bot moves that set up the focus —
   `freePieces`: leaves a piece hanging (SEE); `mates`: lets you mate in one; `tactics`: lets you
   fork/pin/skewer. TeachingBot adds these to its candidates and, when a gift is due
   (every 3 bot moves for freePieces/tactics, every 6 for mates), restricts the choice to gifts.
3. **No mercy**: if you leave a piece hanging and continue, the bot's allowed set is restricted to
   moves that win it (code rule, AI can't overrule).
4. **TeachingBot**: Haiku 4.5 (fast) chooses among the allowed set with the focus in its brief;
   deterministic fallback (Maia-weighted, gift-first) offline, timed, or without a key.
5. **Hold up** (GameController.coachCheck, untimed coach games): rules in order —
   hung piece (newly hanging, non-pawn, or any when focus = hangingOwn) → missed mate →
   missed free piece → blunder/mistake. If no rule fires and the move was an inaccuracy or skipped
   a fork/pin, Haiku may answer `none | missedTactic | allowsTactic` (2.5 s timeout → none).
   Each kind has a template line + board marks (red ring on your loose piece, green ring on the
   free target, arrow on Show me). The line is spoken immediately.
6. **Instant voice**: on your turn, prompts are computed engine-free from the board
   (mate in one, safe capture of a loose piece, fork, your piece attacked, their threats), so they
   speak the moment the bot's move lands. Spoken lines drop squares (the board shows them), so
   ~50 bundled Aman clips cover everything; rendered ~10 % faster.
7. **Game start chip**: "Focus: spotting free pieces" (+ spoken once).

## Testing
Package unit tests for CoachFocus.pick, FocusGifts (each focus on a fixed FEN), no-mercy
restriction, hold-up rules (hung piece, missed mate, missed free piece), engine-free prompts,
spoken-line coverage. Existing UI flows (PlayCoachUITests moved to the Coach bot).
