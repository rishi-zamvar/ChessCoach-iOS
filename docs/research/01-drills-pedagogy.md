# 01 — Drills & Pedagogy Research: Teaching Chess Fundamentals to an Improving Amateur

Target user: improving amateur, roughly **400–1600 chess.com rapid**. Product: iOS (Swift), offline-first chess coach.
Research date: 2026-10-15. Sources are linked inline; a consolidated list is at the end.

> Note on confidence: items marked **[verified]** were checked against primary sources or code during this research (e.g. the Lichess source code, the live Lichess puzzle CSV). Items marked **[secondary]** come from reviews, blogs or summaries. Items with no mark are well-established and widely documented.

---

## 0. TL;DR

1. **At this level, tactics and safety decide nearly every game.** Every curriculum we looked at (Steps Method, Heisman, de la Maza, Woodpecker, Silman's endgame course) agrees on the order: board vision, then mates and basic motifs, then a blunder-check habit, then basic endgames, with opening principles throughout. Pawn structures and strategy come later.
2. **The Lichess puzzle database is the obvious offline drill source.** It holds 6.16M puzzles under a CC0 license, each with a Glicko-2 rating and around 75 theme tags. The compressed file is 307 MB. Our streamed sample showed about 61% of puzzles rated under 1600, and a quality-filtered subset of 50k–150k puzzles would take a few MB to tens of MB.
3. **Drill formats with real evidence:** spaced retrieval of failed items (FSRS), interleaved mixed sets after blocked introduction, repeated solving of a fixed small set (Woodpecker-style, with caveats), and solving your own mistakes. Blindfold and visualization drills are plausible, but the evidence for them is mostly anecdotal.
4. **Adaptive engine:** per-theme Glicko-2 ratings (the same model Lichess uses for player vs puzzle), plus a Lichess-style "performance by theme" weakness detector, plus an FSRS review queue, plus a weakness boost from engine analysis of the user's own games. Target a success rate of about 75–85%.
5. **Teaching, not only testing:** hint ladders (idea → piece → square → move), a "why this works" explanation generated from the tag and the line, arrows and highlights, and retry-after-fail with the refutation shown.

---

## 1. Curriculum: what a 400–1600 player must learn, and in what order

### 1.1 Survey of established curricula

| Curriculum | Structure | What it says about our band |
|---|---|---|
| **Steps Method (Stappenmethode, Brunia & van Wijgerden, NL)** | 6 Steps. Each Step has a Manual (for trainers) and several workbooks: base, Plus, Extra, Thinking Ahead, Mix. Official targets are **Step 1 ≤800, Step 2 ≤1400, Step 3 ≤1600, Step 4 ≤1750, Step 5 ≤1900, Step 6 ≤2100** (OTB; Studer says to add about 200 for online). [verified: [nextlevelchess](https://nextlevelchess.com/steps-method-explained/), [stappenmethode.nl](https://www.stappenmethode.nl/en/step1.php)] | **Step 1** covers board, moves, attacking and capturing, defending, check, mate (1) and (2), castling, profitable exchange, double ("twofold") attack, draw, and mating with the queen. **Step 2** covers tactics and winning material, mating with the rook, eliminating the defender, stalemate, and first positional ideas. "All games are decided by tactics" at this level, and positional play is taught by analysing the student's own games. **Step 3** covers harder tactics, defence against tactics, trapping pieces, first pawn endings, and "thinking ahead" (calculation). **Step 4** covers preparatory moves (luring, eliminating the defence, chasing, aiming, clearance), material advantage, endgame strategy, and weak pawns. Didactic rules: tiny steps, mastery before moving on, and an aim of about **60–80% correct** on exercises. The Mix workbooks have no hints, which tests recognition under realistic conditions. ([step2](https://www.stappenmethode.nl/en/step2.php), [step3](https://www.stappenmethode.nl/en/step3.php), [step4](https://www.stappenmethode.nl/en/step4.php)) |
| **Lichess Learn** (lichess.org/learn) | Interactive stages: the pieces (rook, bishop, queen, king, knight, pawn) → fundamentals (capture, protection, combat, check in one, out of check, mate in one) → intermediate (setup, castling, en passant, stalemate) → advanced (piece value, check in two). | Rules and board fluency only. This covers our 400 floor. |
| **Lichess Practice** (lichess.org/practice) [verified] | **Checkmates**: Piece Checkmates I (basic), Checkmate Patterns I–IV, Piece Checkmates II, Knight & Bishop Mate. **Fundamental Tactics**: Pin, Skewer, Fork, Discovered Attacks, Double Check, Overloaded Pieces, Zwischenzug, X-Ray. **Advanced Tactics**: Zugzwang, Interference, Greek Gift, Deflection, Attraction, Underpromotion, Desperado, Counter Check, Undermining, Clearance. **Pawn Endgames**: Key Squares, Opposition, 7th-Rank Rook Pawn. **Rook Endgames**: 7th-rank rook pawn vs passive rook, Basic (Lucena, Philidor), Intermediate, Practical. | A good blueprint for structured "lessons". Each one is a short explanation followed by positions with a **goal** (mate in N, win, draw, promote), played against Stockfish. ([lichess.org/practice](https://lichess.org/practice)) |
| **ChessKid** | Levels go Pawn → Knight → Bishop → Rook → Queen → King → Super King. Pawn covers meeting the pieces; Knight covers check, checkmate and stalemate; and so on. Includes a board-vision training game. ([ChessKid levels](https://www.chesskid.com/article/view/new-chesskid-feature-release-levels), [lessons](https://www.chesskid.com/learn/lessons)) | Gamified levels and badges. Shows that a level ladder motivates beginners. |
| **Dan Heisman** (Novice Nook, *A Guide to Chess Improvement*, *The Improving Chess Thinker*) | Not a syllabus but a diagnosis. Below about 1600–1800, games are lost to **"Hope Chess"**: playing a move without checking whether the opponent's checks, captures and threats refute it. Fix it with **"Real Chess"**, a safety check on every candidate move, plus **board vision** ("seeing that a bishop on a1 is attacking h8"), **counting** (capture sequences), and a final **sanity check**. ([Definitions](https://www.danheisman.com/definitions.html), [Maximize Your Chess Potential PDF](https://www.newinchess.com/media/wysiwyg/product_pdf/81008.pdf)) | The **blunder-check habit** is a first-class skill to train, not a footnote. Heisman also advises **re-solving easy tactics many times**: speed and accuracy on simple patterns beat struggling with hard ones. |
| **Michael de la Maza, *Rapid Chess Improvement* (2002)** | "Seven Circles": about 1000 problems solved 7 times. Circle 1 takes 64 days, then each circle halves the time (32, 16, 8, 4, 2, 1 days). This was preceded by a "Concrete Chess" phase of basic board-vision drills (knight and bishop exercises, square naming). De la Maza went from about 1300 to 2000+ USCF in 2 years. | Criticism [secondary]: Silman's review was scathing. The evidence is anecdotal with selection bias. "Empirical Rabbit" found a **median gain of about 75 points among completers rated above 1600**, memory faded without revision, and de la Maza himself reported trouble transferring to games. ([Empirical Rabbit](http://empiricalrabbit.blogspot.com/2010/12/7-circles.html), [Kenilworthian](http://kenilworthian.blogspot.com/2005/08/de-la-mazas-rapid-chess-improvement.html)) Lesson: **build fundamentals first, use a revision schedule, and measure on fresh problems.** |
| **Woodpecker Method (Smith & Tikkanen, 2018)** | 1128 puzzles (222 easy, 762 intermediate, 144 advanced). Cycle 1 is slow and complete, solving the whole line. Each later cycle roughly **halves the time**, with short rests (2–3 days) between cycles, for about 7 cycles. The book targets 1500–2400. ([budapestchessnews](https://budapestchessnews.com/2018/08/29/the-woodpecker-method/), [chess.phd guide](https://chess.phd/blog/woodpecker-method-chess/)) | Community advice for club players [secondary]: use **200–400 puzzles**, rated at or up to 100 points below the user's rating, or **themed sets of 50**. Keep a **permanent "failed puzzles" set** and re-solve it monthly. **Below about 1200, learn the patterns first.** Failure modes: a set that is too big, a set that is too hard, rushing cycle 1, editing the set mid-cycle. |
| **Yusupov (Build Up / Boost / Evolution, 9 vols)** | Each series has Fundamentals (orange), Beyond the Basics (blue) and Mastery (green). Tactics, strategy, endgames, calculation and openings are interleaved in every volume. Each chapter has an explanation followed by a 12-exercise test with a points threshold to pass. The orange series targets roughly <1500 ([summary](https://www.goodreads.com/book/show/3680932)) | Good model for **lesson → mastery test with a pass mark**, and for interleaving topics across volumes rather than blocking them. |
| **Silman** (*Complete Endgame Course*; *How to Reassess Your Chess*) | The endgame course is **organised by rating class**, so the student learns only what pays off at their level. [verified TOC: [LOC](https://catdir.loc.gov/catdir/toc/ecip076/2006037884.html)] | See §4. For strategy, Silman's "imbalances" (minor pieces, pawn structure, space, material, files, development, initiative, king safety) give a vocabulary for later (1400+) strategy explanations. |

### 1.2 Synthesised skill taxonomy (proposed for our app)

Each leaf below should be a **skill node** with: an ID, prerequisite node IDs, a lesson (teaching content), a drill source (usually a set of Lichess theme tags or a hand-curated position set), and a mastery model (§7).

```
A. Board fluency (400–800)
   A1 square names / coordinates          A2 piece movement & what each piece attacks
   A3 "what's attacked / what's hanging"  A4 check / escape from check (move, block, capture)
   A5 counting attackers vs defenders     A6 piece values & profitable exchanges
   A7 stalemate awareness                 A8 special moves (castling, en passant, promotion)

B. Checkmate (400–1400)
   B1 mate in 1 (all pieces)              B2 basic mates: K+Q, K+R (box / ladder), K+2R ladder
   B3 essential named patterns (back rank, smothered, Anastasia, Arabian, Boden, hook,
      Greco, Damiano, Lolli, Opera, Morphy, Pillsbury, epaulette, dovetail, corner, Légal)
   B4 mate in 2  ->  B5 mate in 3+        B6 defending against mate (luft, back-rank safety)

C. Tactical motifs (600–1600)
   C1 hanging piece / free material       C2 fork (knight first, then pawn/queen/others)
   C3 pin (absolute / relative)           C4 skewer        C5 discovered attack & check, double check
   C6 removing/capturing the defender     C7 overloading / deflection     C8 attraction / decoy
   C9 trapped piece                       C10 intermezzo (zwischenzug)    C11 clearance, interference, x-ray (1400+)
   C12 quiet moves                        C13 promotion tactics / advanced pawn
   C14 defensive move (only-move defence) C15 sacrifice (combinations combining the above)

D. Safety habit / thought process (all levels; THE key 800–1600 skill)
   D1 blunder check: opponent's checks, captures, threats (CCT) after the candidate move
   D2 "why did they play that?" (threat detection after opponent move)
   D3 candidate moves: enumerate own CCT first     D4 counting in exchanges

E. Endgames (see §4, ordered by Silman class)
   E1 K+Q / K+R mates (shared w/ B2)      E2 square of the pawn    E3 opposition (direct)
   E4 K+P vs K & key squares              E5 rook-pawn draws        E6 Q vs pawn on 7th (incl. a/c/f/h exceptions)
   E7 R vs pawn / minor vs pawn           E8 Philidor               E9 Lucena
   E10 outside passed pawn, triangulation, distant opposition (1400+)
   E11 wrong-coloured bishop + rook pawn  E12 (nice-to-have) B+N mate

F. Opening principles (all levels; NOT memorised theory below ~1400)
   F1 centre, develop, castle, don't move a piece twice / bring queen early
   F2 opening traps to avoid & punish (Scholar's, Fried Liver f7 ideas, Légal, Fishing Pole...)
   F3 a small personal repertoire (1-2 white systems, 1 reply each to 1.e4 / 1.d4) drilled w/ SRS (1200+)

G. Calculation & visualisation (1000+)
   G1 hold position 2-3 plies ahead       G2 blindfold puzzle (move list only)
   G3 full-line solving (not just first move)

H. Strategy & pawn structures (1200–1600, intro only)
   H1 passed pawns, isolated/doubled/backward pawns    H2 open files, rook on 7th
   H3 good vs bad bishop, outposts       H4 king safety, pawn storms (opposite castling)
```

**Recommended order by rating band** (cross-checked against the Steps targets and Silman's classes):

| Band (chess.com rapid) | Primary focus | Secondary |
|---|---|---|
| 400–800 | A1–A8, B1, B2 (K+Q, K+R), C1, C2 (knight fork), D1 (hanging check) | F1 |
| 800–1100 | B3 essentials (back rank, smothered, Anastasia, Arabian, Boden, hook), B4, C2–C6, D1–D2 every day, E2–E4 | F1–F2 |
| 1100–1400 | C6–C10, B4–B6, D3–D4, E5–E8, G1 | F2, H1 |
| 1400–1600 | C11–C15, G1–G3, E9–E11, H1–H4 | F3 |

---

## 2. Checkmate patterns

A full list of named patterns is on Wikipedia's [Checkmate pattern](https://en.wikipedia.org/wiki/Checkmate_pattern) page (about 40). The **Lichess theme tag** is given where one exists, because that determines whether we get drill positions for free.

| Pattern | Pieces / geometry | Lichess tag | Priority |
|---|---|---|---|
| **Back-rank mate** | R/Q mates king on its home rank, boxed in by its own pawns | `backRankMate` (3.4% of puzzles) | **Essential** (the most common mate at our level) |
| **Smothered mate** | Knight mates a king surrounded by its own pieces (often after a Q sac on g8, e.g. Philidor's legacy) | `smotheredMate` | **Essential** |
| **Anastasia's mate** | N + R/Q trap the king on the edge between the board edge and its own piece | `anastasiaMate` | Essential |
| **Arabian mate** | N + R in the corner (N covers the rook and the escape square) | `arabianMate` | Essential |
| **Boden's mate** | Two bishops on criss-crossing diagonals (typically after O-O-O) | `bodenMate` | Essential |
| **Hook mate** | R + N + P; the rook is protected by the knight, the knight by a pawn | `hookMate` | Essential |
| **Opera mate** | R on the back rank protected by a bishop (Morphy's Opera Game) | `operaMate` (1.0%) | Essential |
| **Damiano's mate** | Q supported by a pawn (or bishop) on g7/h7 | none (falls under `mate`) | Essential |
| **Greco's mate** | B contains the king in the corner (after the h-pawn is gone); R/Q mates on the h-file | none | Recommended |
| **Lolli's mate** | Q infiltrates g7 supported by a pawn on f6 against a fianchetto | none | Recommended |
| **Légal's mate** | Opening trap: Q "sacrifice", then 2 knights + bishop mate | none (opening trap; teach as a lesson) | Recommended (classic trap) |
| **Morphy's mate** | B mates in the corner; R cuts off | `morphysMate` | Recommended |
| **Pillsbury's mate** | R mates, B cuts off the corner escape | `pillsburysMate` (1.1%) | Recommended |
| **Epaulette mate** | King's two side squares blocked by its own pieces (like epaulettes); Q mates from the front | `epauletteMate` | Recommended |
| **Dovetail (Cozio's) mate** | Q diagonally adjacent, protected; the king's two flanking escapes are blocked by its own pieces | `dovetailMate` | Recommended |
| **Swallow's tail (Guéridon)** | Q mates from directly in front, protected; the rear-diagonal escapes are blocked | `swallowstailMate` | Recommended |
| **Corner mate** | R/Q + N confine the king to the corner | `cornerMate` | Recommended |
| **Kill box** | R next to the king; Q supports diagonally to form a 3×3 box | `killBoxMate` | Nice |
| **Triangle mate** | Q and R one square apart on the same line, adjacent to the king | `triangleMate` | Nice |
| **Blind swine mate** | Doubled rooks on the 7th mate a king in the corner area | `blindSwineMate` | Nice |
| **Balestra** | B mates from a distance; Q covers escapes | `balestraMate` | Nice |
| **Vuković mate** | R mates supported by a third piece; N blocks escapes | `vukovicMate` | Nice |
| **Double bishop mate** | Two bishops on adjacent diagonals | `doubleBishopMate` | Nice |
| **Anderssen's mate** | R/Q on the back rank supported diagonally by a pawn or bishop | none | Nice |
| **Blackburne's mate** | 2 bishops + knight | none | Nice |
| **Mayet's mate** | R on the edge supported by a distant bishop | none | Nice |
| **Max Lange's mate** | Q + B | none | Nice |
| **Réti's mate** | B + R (Réti–Tartakower 1910) | none | Nice |
| **Ladder (lawnmower) mate** | Two major pieces alternate cutting ranks | none (basic mate) | **Essential** (basic mate) |
| **David & Goliath, pawn mate, rainbow, double-knight, suffocation, Stamma** | Curiosities | none | Skip / trivia |

**Basic (elementary) mates, essential vs nice-to-have:**
- **K+Q vs K**: essential (Steps 1, Silman Part 1 "The Box" / staircase). Drill against an engine; it must be done within the 50-move rule, with **stalemate traps** highlighted.
- **K+R vs K**: essential ("box" technique, or ladder with 2R/R+Q).
- **K+2R / K+Q+R ladder**: essential and easy. These are Silman's "overkill mates".
- **K+2B vs K**: nice-to-have (Silman puts "what can and cannot mate" at Class E, about 1000–1200. Know that it is possible; the technique is optional).
- **K+B+N vs K**: **not needed below about 2000**. Silman defers it well past our band, and it occurs in well under 1 in 1000 games. Ship it as an optional "challenge" lesson (Lichess Practice has one).
- **K+2N vs K cannot be forced**: worth one knowledge card ("don't trade into this expecting to win").

**Drill source:** the named-pattern tags give thousands of positions each for common patterns, but only hundreds for rare ones. In our 600k-row sample: `anastasiaMate` about 760, `bodenMate` about 400, `balestraMate` about 140; multiply by about 10 for the full DB. Patterns without a tag (Greco, Damiano, Lolli, Légal, Anderssen) need **hand-curated sets of about 10–20 positions each**. Alternatively, write our own geometric detector over `mate` puzzles: check the final-position geometry, as lichess-puzzler's `cook.py` does for its tags.

---

## 3. Tactical motifs and the Lichess puzzle database (our offline drill source)

### 3.1 The database [verified]

Source: [database.lichess.org/#puzzles](https://database.lichess.org/#puzzles) (checked 2026-10-15).

- **Size:** **6,157,341** puzzles (last updated 2026-10-05). The file `lichess_db_puzzle.csv.zst` is **307,234,795 bytes (about 293 MiB) compressed**. Uncompressed it is about 185 bytes per row, so about **1.1 GB**.
- **License:** **CC0** (public domain). Commercial use is allowed with no attribution required (attribution is still courteous).
- **Columns:** `PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags,DailyDate`
- **Sample row:**
  `00sHx,q3k1nr/1pp1nQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 b k - 0 17,e8d7 a2e6 d7d8 f7f8,1760,80,83,72,mate mateIn2 middlegame short,https://lichess.org/yyznGmXs/black#34,Italian_Game Italian_Game_Classical_Variation,`
- **Semantics (important for implementation):**
  - `Moves` are **UCI**. The **FEN is the position BEFORE the opponent's move**. Apply `Moves[0]` (the opponent's move, which should be **animated** so the user sees what just happened), then the user must find `Moves[1]`, the engine replies `Moves[2]`, and so on.
  - Every player move in the solution is an **"only move"**. **Exception: in mate-in-1, any checkmating move wins**, so the app must accept any mate on the last move. This is generally good practice for final mating moves too.
  - `Rating`/`RatingDeviation` are **Glicko-2**: "each attempt to solve is considered as a Glicko2 rated game between the player and the puzzle".
  - `Popularity` runs from −100 to 100, from weighted up/down votes. `NbPlays` is the number of attempts.
  - `OpeningTags` is set only for puzzles starting before move 20, using the lichess-org/chess-openings names.
  - `DailyDate` is a Unix timestamp in milliseconds, present if the puzzle was a daily puzzle.
  - Generation: 600M analysed games, re-analysed with Stockfish NNUE at 40 meganodes, then auto-tagged by [lichess-puzzler `tagger/cook.py`](https://github.com/ornicar/lichess-puzzler/blob/master/tagger/cook.py) and refined by votes.

### 3.2 All theme tags, exactly (from lila `PuzzleTheme.scala` and `puzzleTheme.xml`) [verified]

Grouped as Lichess groups them in the UI ([PuzzleTheme.scala](https://github.com/lichess-org/lila/blob/master/modules/puzzle/src/main/PuzzleTheme.scala), [descriptions xml](https://github.com/lichess-org/lila/blob/master/translation/source/puzzleTheme.xml)). The percentage is the **share of puzzles carrying the tag in our streamed sample of the first 599,999 rows** (about 10% of the DB; ordering in the file is roughly random by ID).

- **Phases:** `opening` 4.8%, `middlegame` 45.2%, `endgame` 50.1%, `rookEndgame` 5.4%, `bishopEndgame` 1.4%, `pawnEndgame` 3.7%, `knightEndgame` 0.85%, `queenEndgame` 1.2%, `queenRookEndgame` 0.74%
- **Motifs:** `advancedPawn` 6.2%, `attackingF2F7` 0.76%, `capturingDefender` 0.65%, `discoveredAttack` 5.1%, `doubleCheck` 0.52%, `exposedKing` 3.0%, `fork` 12.8%, `hangingPiece` 3.7%, `kingsideAttack` 8.7%, `pin` 6.0%, `queensideAttack` 1.5%, `sacrifice` 7.6%, `skewer` 2.2%, `trappedPiece` 1.1%
- **Advanced:** `attraction` 3.7%, `clearance` 1.3%, `collinearMove` 0.13%, `discoveredCheck` 1.8%, `defensiveMove` 6.0%, `deflection` 4.4%, `interference` 0.37%, `intermezzo` 1.2%, `quietMove` 4.2%, `xRayAttack` 0.35%, `zugzwang` 1.0%
- **Mates:** `mate` 31.9%, `mateIn1` 14.8%, `mateIn2` 13.4%, `mateIn3` 3.2%, `mateIn4` 0.48%, `mateIn5` 0.10%
- **Mate patterns:** `anastasiaMate`, `arabianMate`, `backRankMate` (3.4%), `balestraMate`, `blindSwineMate`, `bodenMate`, `cornerMate`, `doubleBishopMate`, `dovetailMate`, `epauletteMate`, `hookMate`, `killBoxMate`, `pillsburysMate`, `morphysMate`, `operaMate`, `swallowstailMate`, `triangleMate`, `vukovicMate`, `smotheredMate` (each between 0.02% and 1.1%)
- **Special moves:** `castling` 0.04%, `enPassant` 0.14%, `promotion` 2.4%, `underPromotion` 0.02%
- **Goals:** `equality` 0.21%, `advantage` 28.7% (200–600cp), `crushing` 38.3% (≥600cp), `mate`
- **Lengths:** `oneMove` 14.8%, `short` 50.2% (2 player moves), `long` 26.0% (3), `veryLong` 8.1% (4+)
- **Origin:** `master` 13.6%, `masterVsMaster` 1.3%, `superGM` 0.05%
- **UI-only (not in the CSV):** `mix` (healthy mix), `playerGames`, plus the hidden `checkFirst`. `cook.py` can also emit `overloading`, but it is not a visible theme in the current UI and did not appear in our sample.

Tagging caveats: tags are **automatic and imperfect**. One puzzle usually has several motifs (fork + sacrifice + attraction). `hangingPiece` is under-applied, and some "fork" puzzles are really "capture the hanging piece, then fork". For teaching, take the **primary motif** as the most specific tag. Suggested precedence: named mate > `mateInN` > advanced motif > basic motif > goal/phase.

**Rating distribution (sample):** percentiles p1=460, p10=801, p25=1040, **median 1412**, p75=1868, p90=2240, p99=2730. **22.7% are rated under 1000 and 38.3% are 1000–1599**, so about 61% sit in our target range. RD median is 79 (p90 105).

**Quality filter for offline bundling:** `RatingDeviation ≤ 80 AND Popularity ≥ 85 AND NbPlays ≥ 200 AND 400 ≤ Rating ≤ 2000` keeps about 35% of rows (about 2.15M across the full DB). Practical bundle options:
- Ship a **stratified sample of about 50k–150k puzzles**, stratified by (primary theme × 100-point rating bucket), with every rare mate-pattern and endgame puzzle kept up to a per-cell cap. That is about **9–28 MB raw CSV**. In SQLite, store FEN, moves, rating, RD, a theme bitmask (about 75 bits fits in two `INTEGER` columns) and opening tags; expect roughly a few MB to about 15 MB with zstd/LZFSE. Optionally offer a larger on-demand download pack.
- A dense 128-bit bitmask, or a `puzzle_theme(puzzle_id, theme_id)` join table, makes "puzzles with theme X near rating R not seen recently" a fast indexed query.

### 3.3 How the tagger detects motifs (useful for classifying the user's own game mistakes) [verified, summarised]

The [`cook.py`](https://github.com/ornicar/lichess-puzzler/blob/master/tagger/cook.py) heuristics are reproducible in Swift and can be **run on the engine's best line from the user's own blunders** (§7):
- **fork**: a non-king moved piece attacks ≥2 opponent pieces that are of higher value or undefended.
- **pin**: an opponent piece cannot capture or escape because it is aligned with a more valuable piece behind it.
- **skewer**: capturing a lower-value piece that stood behind a higher-value piece on a ray after the latter moved.
- **discoveredAttack**: the moved piece unveils a ray attack that leads to a capture.
- **hangingPiece**: capture of undefended material without compensation.
- **backRankMate / smotheredMate / …**: geometry checks on the final mating position.
- **deflection / attraction**: a sacrifice or forced move pulls a defender away from, or onto, a square.
- **quietMove**: no check, capture or direct threat, with many legal alternatives.
- **Length** by the number of solution plies; **goal** by eval thresholds (advantage 200–600cp, crushing ≥600cp, equality ≤200cp).

---

## 4. Endgame essentials and drilling them against an engine

### 4.1 What to learn, ordered by Silman's rating classes [verified TOC]

From [Silman's Complete Endgame Course](https://catdir.loc.gov/catdir/toc/ecip076/2006037884.html):
- **Part 1, Unrated–1000:** overkill mates (staircase with 2Q, Q+R, 2R), "the box" (K+Q, K+R), **stalemate alert**.
- **Part 2, Class E 1000–1199:** what can and cannot mate a lone king; minor piece vs queen; **understanding the king: opposition, rook pawns**.
- **Part 3, Class D 1200–1399:** beyond basic opposition; **K+P vs K** (key squares); minor piece vs lone pawn; **rook vs lone pawn**.
- **Part 4, Class C 1400–1599:** K+P endgames (doubled pawns, rook-pawn positions, **outside passed pawn**); minor-piece endgames (**bishop and wrong rook-pawn**); **rook endgames (Lucena, Philidor)**; **queen vs K+P** (the 7th-rank a/c/f/h-pawn draws).
- **Part 5, Class B 1600–1799:** more K+P (triangulation, etc.), rook endings, minor-piece endings.

### 4.2 Concept cards we need (each with 3–10 positions)

| Concept | Core rule to teach | Drill goal vs engine |
|---|---|---|
| **Square of the pawn** | Draw the square from the pawn to its promotion rank. If the defending king can step into it, it catches the pawn. (Count from the 2nd rank as if the pawn stood on the 3rd, because of the double step.) | "Win" / "Draw": can the king catch it? Also as a **quick yes/no quiz** (very fast pattern drill). |
| **Opposition** (direct, distant, diagonal) | Kings an odd number of squares apart on a line, *opponent to move*: you have the opposition. | Win/draw K+P vs K positions. |
| **Key squares** | Pawn not past the 5th rank: the 3 squares two ranks ahead are key. Pawn on the 5th/6th: the 3 squares one rank ahead (and two ahead). Rook pawn: g7/g8 (b7/b8) style. If your king reaches a key square, you win regardless of who is to move. | "Click all key squares" quiz, then play-out. |
| **Rook-pawn draws** | Defending king in front of the a/h pawn draws, even against an extra bishop of the wrong colour. | Draw positions. |
| **Triangulation** | Lose a tempo with a 3-move king triangle to hand over the move. | Win (1400+). |
| **Outside passed pawn** | It decoys the enemy king; your king eats the other side. | Win. |
| **Philidor** | Defending rook on the 3rd rank (6th from the attacker's view) until the pawn advances, then check from behind. | Draw. |
| **Lucena** | "Building a bridge": rook to the 4th rank to shield checks. | Win. |
| **Q vs pawn on 7th** | Approach with checks and pins; a/c/f/h pawns can draw by stalemate tricks. | Win, or recognise the draw. |
| **Wrong bishop + rook pawn** | Bishop not controlling the promotion corner: draw if the defending king reaches the corner. | Draw/win. |

### 4.3 How to drill endgames against an engine (design)

The Lichess Practice pattern: short explanation, then a position with a **goal** ("Win", "Draw", "Promote", "Mate in N"), then the user plays against an engine that defends perfectly.

- **Judge moves with a tablebase, not centipawns**, so feedback is instant and exact: "That move turns a win into a draw." Syzygy 3–5-piece is **939 MiB total (WDL 378 MiB + DTZ 562 MiB)** ([chessprogramming wiki](https://www.chessprogramming.org/Syzygy_Bases)). That is too big to bundle whole on iOS. **3–4-piece Syzygy is small (a few MB)** and covers KPvK, KQvK, KRvK, KQvKP and KRvKP. Lucena and Philidor (KRPvKR) need a 5-piece table. Options:
  - Bundle 3–4-piece WDL+DTZ, plus the **specific 5-piece files we need** (KRPvKR, KQvKP, KPPvKP if needed). Individual 5-piece files are a few MB to tens of MB each, so bundle only the needed tables.
  - Or use on-device Stockfish with a mate/score threshold and a hand-coded rule, e.g. "eval drops below +2 in a winning drill = fail".
  - Or precompute: for each curated drill position, store the WDL of every legal reply for the first N plies (tiny), and fall back to Stockfish afterwards.
- **Engine opponent behaviour:** in a "win" drill the engine should **defend maximally** (DTZ/DTM-longest resistance), so the user must show technique. In a "draw" drill the engine should **try the most testing winning attempts**.
- **Feedback:** on the first WDL-changing move, stop, show the **correct move with arrows** and the key concept ("Your king left the key square"), then offer **retry from that position** or restart.
- **Mastery:** pass = reach the goal (win within N moves / draw held for M moves) **twice on different days** (FSRS card per position).
- **License note:** Stockfish is GPLv3. A closed-source App Store binary embedding it raises a GPL/App Store compatibility question. (Lichess mobile is open source; many closed iOS apps ship it anyway.) Flag this for the architecture/legal track. Syzygy probing code (Fathom) is MIT.

---

## 5. Drill formats: what works and the evidence

| Format | Description | Evidence / rationale | Verdict for v1 |
|---|---|---|---|
| **Rated puzzle solving (untimed)** | Lichess/Chess.com standard. One Glicko-rated attempt. | Deliberate-practice research: **Charness et al. 2005** found accumulated **"serious study alone"** a far stronger predictor of rating than tournament play ([Wiley](https://onlinelibrary.wiley.com/doi/10.1002/acp.1106)). **Southwick et al. 2026 (*Psychological Science*), N=44,213 Chess.com users:** deliberate-practice-aligned activities (puzzles, lessons, game review) had a **3.61× learning-efficiency advantage per unit time over playing games**, even though players spent >90% of their time on games. Not all such activities were equally effective ([DOI](https://doi.org/10.1177/09567976261452568), [summary](https://www.citedrive.com/en/discovery/not-all-practice-is-created-equal-longitudinal-evidence-from-over-40000-chess-players/)). | **Core** |
| **Themed (blocked) sets** | 10–20 puzzles of one motif after a lesson. | Good for *acquiring* a pattern (worked-example → practice). But blocked practice lets the user know the answer type in advance, so recognition is not tested. | **Core**, immediately after a lesson |
| **Interleaved mixed sets** | Random themes ("healthy mix"). | Interleaving meta-analysis: **g = 0.42** overall, strongest for **visual/perceptual category learning** ([Brunmair & Richter 2019](https://www.psychologie.uni-wuerzburg.de/fileadmin/06020400/2019/Brunmair_Richter_in_press__2019_META-ANALYSIS_OF_INTERLEAVED_LEARNING.pdf)). Rohrer et al. 2020 RCT d≈0.83 (math). Chess motif recognition is exactly a discriminative "which pattern is this?" task. The Steps "Mix" workbooks exist for this reason. | **Core** (default daily mode after initial learning) |
| **Spaced repetition of failed / key positions** | Re-show a failed puzzle at expanding intervals. | Spacing and retrieval practice are among the most robust effects in learning science. Chessable's MoveTrainer (8 levels: 4h, 1d, 3d, 1w, 2w, 1mo, 3mo, 6mo; [Chessable support](https://support.chess.com/en/articles/10319322-how-does-the-spaced-repetition-scheduling-work)), Listudy (Leitner, per move; [Listudy](https://listudy.org/en/blog/spaced-repetition-for-chess)), Lichess "replay failed puzzles". | **Core** (FSRS) |
| **Woodpecker cycles** | Fixed set re-solved with halving time. | Strong testimonials, but **no controlled evidence**. The Seven-Circles critique: memorisation, poor transfer, decay without revision. Fine as an **opt-in program** using the user's own failed-puzzle set, which is more sensible than a random 1000. | v1.1 opt-in "Woodpecker mode" |
| **Timed / speed recognition** (Puzzle Storm/Rush style) | Many easy puzzles under a clock. | Builds **automaticity on easy patterns** (the chunking view: masters "see" instead of calculate). Heisman recommends speed on easy tactics. Risk: it trains guessing. Use only puzzles about 300–600 below the user's rating, with a mistake limit. | **Core** as a short warm-up mode (3 min) |
| **Board vision drills** | Coordinates ("tap e4"), "what does this piece attack?", "find all hanging pieces", "find all checks/captures", knight routes (knight from a1 to h8 in min moves, knight tours), "is this square safe for my queen?" | De la Maza's "Concrete Chess" phase; Heisman's "board vision"; ChessKid's board-vision game; Lichess Coordinates trainer. Evidence is mostly experiential, but **"find all checks/captures/threats" directly trains the blunder-check habit**, which is the #1 failure at 800–1400. | **Core**: coordinate + CCT-enumeration drills (very cheap to build) |
| **Blunder-check / safety drill** | Show a position and a *proposed move* (often a plausible blunder). User answers "safe?" and, if unsafe, shows the refutation. Or "your opponent just moved: what is the threat?" | Directly targets Hope Chess (Heisman). Positions are easy to generate from puzzle DB starting positions: the opponent's first move in each puzzle **is** a blunder, so "Is Moves[0] safe? Why not?" is a ready-made drill. | **Core** (distinctive, cheap, high value) |
| **"Guess the move" / play-through** | Replay a master game; guess each move; score by engine/eval loss. | Classic (Chess Life "Solitaire Chess"). Trains candidate-move generation and strategy. Requires annotated games, and scoring by eval loss needs an engine. | v2 |
| **Play-out vs engine from a position** | Endgames (§4) and "convert the winning position" (Aimchess "Advantage Capitalization"). | Fixes a common amateur failure: being winning and not converting. | **Core** for endgames; v1.1 for conversion drills |
| **Blindfold / visualisation** | Puzzle shown, then hidden; solve from the move list. Or "move N plies forward in your head, then answer: where is the knight?" | Chunking research shows expertise is memory for meaningful structure. Claims of visualisation training gains are **largely anecdotal** ([e.g.](https://darksquares.net/learn/blindfold-chess)). Low build cost. | v1.1 option ("hide board after 5 s") |
| **Retry own mistakes** | Positions from the user's own games where they blundered or missed a tactic. | Most personally relevant; used by Lichess ("Learn from your mistakes"), Aimchess ("Retry Mistakes"), Chess.com. Steps teaches positional play from the student's own games. | **Core** if game import is in v1 (§7) |

**Design implications from the Einstellung research:** experts who spot a familiar solution (smothered mate) stop looking for a faster one, and their eye movements stay on the familiar idea ([Bilalić, McLeod & Gobet 2008](https://cognition.aau.at/download/Publikationen/Bilalic/Bilalic_etal_2008b.pdf)). So themed sets should **sometimes include a "decoy"** (a position that looks like the theme but isn't, or has a better move), and mixed sets should dominate once a theme is learned.

---

## 6. Learning science

### 6.1 Chunking and pattern recognition (why puzzles work)
- **de Groot** (*Thought and Choice in Chess*, 1946/65): masters do not search more moves than weaker players; they consider *better* moves sooner. After 5 s exposure they reconstruct real positions far better.
- **Chase & Simon 1973** ("Perception in chess"): the master advantage in recall **vanishes for random positions**, so the skill is *chunks*: meaningful configurations of up to about 5–7 pieces, stored as patterns linked to moves. Estimates put masters' chunk stores at 10k–100k+ ([Matuschak notes](https://notes.andymatuschak.org/Chase_and_Simon_-_Perception_in_chess)).
- **Gobet & Simon 1996, template theory, CHREST:** experts also hold larger "templates" with slots; there is a small expert advantage even on random boards ([Gobet & Simon](https://www.researchgate.net/publication/13576754_Expert_Chess_Memory_Revisiting_the_Chunking_Hypothesis)).
- **Implication:** volume of **varied, real-game** pattern exposure plus **retrieval** is how amateurs build chunks. Puzzles from real games (the Lichess DB) beat composed problems for this. Seeing the *same motif across many surface configurations* (interleaving and variety) is what builds a generalisable chunk.

### 6.2 Deliberate practice
- Charness et al. 2005: serious solitary study is the strongest predictor; coaching and tournament play add independent prediction ([Wiley](https://onlinelibrary.wiley.com/doi/10.1002/acp.1106)).
- Southwick et al. 2026: 3.61× efficiency for deliberate-practice-aligned activity vs playing ([DOI](https://doi.org/10.1177/09567976261452568)).
- Deliberate practice means **targeted at weaknesses, at the edge of ability, with immediate feedback, and repeated**. That is the case for an adaptive engine (§7) rather than random puzzles.

### 6.3 Desirable difficulty and target success rate
- **Steps Method:** aim for **60–80% correct** ([nextlevelchess](https://nextlevelchess.com/steps-method-explained/)).
- **"Eighty-Five Percent Rule"** (Wilson, Shenhav et al., *Nature Communications* 2019): the optimal training error rate for gradient-based learners is about 15.9% ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC6831579)). This is a theoretical result for binary classification, but it is a useful anchor.
- Lichess difficulty presets offset the puzzle rating from the player's rating by **−600 / −300 / 0 / +300 / +600** (easiest to hardest) [verified, `PuzzleDifficulty.scala`]. Under Glicko, "0 offset" means about 50% expected success, which is **harder than optimal for learning**.
- **Recommendation:** for *learning* drills, target about **75–85% success**, i.e. puzzle rating ≈ theme rating − 150 to −250 (with the Glicko expectation formula, an Elo-style gap of about 190–300 gives 75–85%). For *rating/testing* mode, use 0 offset. For speed warm-ups, use −400 to −600.

### 6.4 Spaced repetition: SM-2 vs FSRS
- **SM-2** (SuperMemo/Anki legacy): ease factor and interval multiplication. Simple, but it ignores the actual forgetting curve.
- **FSRS** (Free Spaced Repetition Scheduler, open-spaced-repetition): DSR model with **Difficulty, Stability** (days until recall probability falls to 90%), and **Retrievability R = f(t, S)**. Users choose a target retention (e.g. 0.9). Benchmarks show fewer reviews for the same retention than SM-2 ([FSRS repo](https://github.com/open-spaced-repetition/free-spaced-repetition-scheduler)).
- **Swift:** [`open-spaced-repetition/swift-fsrs`](https://github.com/open-spaced-repetition/swift-fsrs) is **MIT** licensed, supports **FSRS-6** (FSRS-5 via a 19-length `w`), and is installed via SPM. API: `FSRS(parameters:)`, `createEmptyCard()`, `next(card:now:grade:)` [verified]. **Use this as the scheduler.**
- **Chess-specific mapping to FSRS grades** (FSRS has Again / Hard / Good / Easy):
  - Failed (wrong move) or used the full solution → **Again**
  - Solved after a hint, or after a wrong first try, or slower than 2× the median time → **Hard**
  - Solved cleanly → **Good**
  - Solved cleanly in under the median time for its rating → **Easy**
- **What becomes a card:** (a) every failed puzzle, (b) every lesson's key positions, (c) every endgame drill position, (d) each own-game mistake position, (e) opening repertoire moves *per position* (as Chessable/Listudy/Chessbook do), (f) mate-pattern exemplars. Puzzles solved first time cleanly at ≥ the user's rating **do not** need cards, which keeps the queue small.
- **Card granularity for openings:** per *position* (FEN → expected move), like MoveTrainer's "each move has its own timer".
- **Caveat about memorising answers:** repeated puzzles can be recalled by surface memory ("knight to f7 here") rather than pattern recognition. Mitigations: (1) on review, show a **sibling puzzle** with the same primary theme and similar rating instead of the identical one, at least sometimes (e.g. on 2 of every 3 reviews once Stability is over 7 days); (2) require the **full line**, not only the first move; (3) mirror or flip colours where legal (e.g. flip the board and colours of a mate pattern) to break surface memory.

---

## 7. Adaptive recommendation: from the user's games to the daily plan

### 7.1 How the existing products do it
- **Lichess Puzzle Dashboard** [verified, `PuzzleDashboard.scala`]: over the last N days (1–90), for each relevant theme, compute `nb`, `wins`, `fixed` (failed then solved on replay) and the average puzzle rating. **Performance = avgPuzzleRating − 500 + 1000 × firstWinRate**. A theme counts only if `nb > globalNb/40`. A **weak theme** has `failed ≥ 3 && performance < global performance`; a **strong theme** has `firstWins ≥ 3 && performance > global`; the top 8 of each are shown. Excluded as "irrelevant" for this view: length tags, mateInN, goal tags, origin tags. The dashboard also offers "replay failed puzzles by theme". That makes it a simple, transparent, already battle-tested weakness detector worth copying.
- **Lichess game analysis** [verified, `Advice.scala`]: a move is an **inaccuracy / mistake / blunder when winning chances drop by ≥0.1 / 0.2 / 0.3**, where winning chances are on a [−1, 1] scale (i.e. 5 / 10 / 15 Win% points). `WinPercent = 50 + 50 × (2/(1+exp(−0.00368208 × cp)) − 1)`; move accuracy = `103.1668 × exp(−0.04354 × ΔWin%) − 3.1669` ([lichess accuracy](https://lichess.org/page/accuracy)). Mate events are classed separately (MateCreated / MateLost / MateDelayed). "Learn from your mistakes" replays these positions.
- **Chess.com Game Review / Insights:** expected-points model, rating-aware. Classification by expected-points loss: Best 0, Excellent ≤0.02, Good 0.02–0.05, **Inaccuracy 0.05–0.10, Mistake 0.10–0.20, Blunder >0.20**, plus Great, Brilliant and Miss ([Chess.com support](https://support.chess.com/en/articles/8572705-how-are-moves-classified-what-is-a-blunder-or-brilliant-move)). Insights (Diamond tier) aggregates accuracy by phase, opening and time.
- **Aimchess** [secondary]: imports games, scores six areas (**openings, tactics, endgames, advantage capitalization, resourcefulness, time management**), turns missed opportunities from the user's games into puzzles, and runs trainers (Opening Improver, Advantage Capitalization, Endgames, Intuition, Retry Mistakes, Defender, Time Trainer) with personalised plans ([App Store](https://apps.apple.com/us/app/aimchess-learn-chess-online/id1524941307), [review](https://www.raindropchess.com/aimchess-review-does-personalized-chess-training-actually-work/)).
- **Chessbook**: opening repertoire with SRS, focused on lines **common at the user's level** (Lichess explorer frequencies) ([chessbook](https://beta.chessbook.com/)). **Listudy**: free and open source, Leitner per move. **Noctie**: a human-like bot (about 25 levels, 400–2800) for practising openings and positions against human-style errors ([noctie.ai](https://noctie.ai/)).
- **Educational-systems literature:** Elo for student vs item, treating each answer as a match, is "simple, robust and effective" for adaptive practice ([Pelánek 2016, *Computers & Education*](https://www.fi.muni.cz/~xpelanek/publications/CAE-elo.pdf)). **Bayesian Knowledge Tracing** (P(L0), P(T), slip, guess; mastery at P ≥ 0.95) is the classic per-skill mastery model.

### 7.2 Detecting weaknesses from the user's own games (offline, on-device)

Pipeline per imported game (PGN from chess.com or Lichess, including `%clk` comments):

1. **Engine pass:** on-device Stockfish at modest depth or node count (e.g. 1–2M nodes per position; on a modern iPhone this is seconds per game on a background task). Store `cp/mate` before and after each user move.
2. **Classify each user move** with Lichess winning-chance thresholds (0.1 / 0.2 / 0.3). Chess.com's expected-points thresholds are an alternative, but they need a rating-aware model.
3. **For each mistake or blunder, determine the type:**
   - **Missed tactic (offence):** the best move led to a gain of ≥ the threshold. Run the **motif tagger (a port of `cook.py`)** on the engine's best line, and label it e.g. `fork`, `mateIn2`, `backRankMate`.
   - **Allowed tactic (defence / blunder-check failure):** the user's move allowed an opponent tactic. Tag the *opponent's* best line with the motif tagger. Count it toward **D1 Safety** *and* the motif.
   - **Hung material:** the opponent's best reply simply captures an undefended piece → `hangingPiece` + D1.
   - **Missed mate / allowed mate:** use the mate-score transitions (MateLost, MateCreated).
   - **Endgame error:** material-based phase (e.g. no queens and ≤ 13 points of non-pawn material, or Lichess's phase rule). Map to an endgame family by material signature (KPvK, KRPvKR, rook endgame, etc.) and to the skill nodes in E.
   - **Conversion failure:** the user was ≥ +3 (Win% ≥ 80) and the game was not won → "advantage capitalization".
   - **Opening deviation:** the first move out of the user's repertoire, or out of the explorer's top-N, that loses ≥0.1 winning chances. Increment the opening node and propose an SRS card for that position.
   - **Time trouble:** from `%clk`, mistakes made with < 10% of the base time left, or a large clock deficit. Mark a time-management weakness. These are drilled with *timed* mixed sets rather than motif sets.
4. **Create a personal puzzle** from each missed-tactic position: the FEN before the user's move, solution = the engine PV truncated where the gain is secured (as lichess-puzzler does). It becomes an FSRS card immediately.

### 7.3 Skill model

Per skill node *k* (taxonomy §1.2; most map to one or more Lichess tags):

- **`rating_k` (Glicko-2: r, RD, σ)**, updated after every rated attempt on an item tagged *k*. The item's own Glicko rating comes from the Lichess `Rating`/`RD`. Treat the puzzle rating as fixed (do not update it locally). If a puzzle has several tags, update the **primary** tag fully and secondary tags with a lower weight. A simple way to do this is to scale the Glicko update by 0.5, or to update a secondary only on failure.
- **`perf_k`**: a Lichess-dashboard-style rolling 30-day performance (formula above), for display and the weak/strong lists.
- **`mastery_k`** (for curriculum gating, i.e. "lesson completed → unlock next"): BKT with P(L0)=0.1, P(T)=0.2, guess 0.15, slip 0.1. Mastery at **P ≥ 0.95, plus ≥ 2 sessions on different days**. Alternatively, simpler: a Yusupov-style test of 10 mixed-in puzzles at ≥ the node's target rating, scoring ≥ 7/10.
- **`gameWeakness_k`**: an exponentially decayed count of game-derived mistakes tagged *k* (half-life about 14 days), normalised by games played. Also track **missed-vs-allowed** split per motif.
- **Global:** `globalRating` (Glicko over all puzzles), `safetyScore` (D1: share of user moves in recent games that hung material or allowed a ≥0.2 tactic), `timeTroubleRate`.

### 7.4 Concrete daily-plan algorithm

Inputs: session length L (minutes; default 15), current time, all models above.
Rule of thumb for time per item: about 45 s per puzzle at learning difficulty, about 10 s for a warm-up item, about 3 min for an endgame play-out.

```
func buildDailyPlan(L):
  plan = []

  # 1. Warm-up (≈10%): board vision / speed
  plan += boardVisionDrill(level by globalRating)      # coordinates, "find all checks/captures", 60–90 s
  plan += speedSet(n≈8, rating = globalRating − 500, mixed easy themes incl. mateIn1, hangingPiece, fork)

  # 2. Reviews (≤35%): FSRS due queue
  due = fsrsCards.filter(R(now) ≤ targetRetention).sortBy(R ascending)
  # cap so reviews never crowd out new learning; overflow carries to tomorrow
  plan += due.prefix(maxReviews(L))                     # sibling-swap for puzzle cards w/ S>7d, 2 of 3 times

  # 3. Focus block (≈35%): the 1–2 weakest skills
  for k in candidateSkills (unlocked & curriculum-appropriate for band):
      gap_k      = max(0, globalRating − rating_k.r) / 200        # relative weakness
      game_k     = gameWeakness_k / max(gameWeakness)             # from own games (0..1)
      freq_k     = expected real-game frequency of motif k at user's band (prior table; from tag shares in §3.2,
                   e.g. hangingPiece/fork/mateIn1/backRank high; xRay/interference low)
      unc_k      = rating_k.RD / 350                              # explore uncertain skills
      stale_k    = days since k last practised / 14, capped 1
      priority_k = 0.30*game_k + 0.25*gap_k + 0.20*freq_k + 0.15*unc_k + 0.10*stale_k
      if safetyScore is bad: priority[D1] += 0.3                  # blunder-check is the #1 lever below ~1400
  focus = top 2 by priority (no repeat of yesterday's #1 unless game_k still top)
  for k in focus:
      if mastery_k < 0.5 and lesson_k not done: plan += lesson(k)  # teach first (§8)
      plan += themedSet(k, n≈6, rating = rating_k.r − 200 ± 100)   # blocked, ~80% target
      plan += 1–2 decoy puzzles (looks like k, isn't)              # anti-Einstellung

  # 4. Mixed interleaved set (≈15%): healthy mix weighted toward weak skills
  plan += mixedSet(n≈6, rating = globalRating − 150,
                   themeWeights ∝ softmax(priority) blended 50/50 with freq prior)

  # 5. Endgame / own-mistake slot (≈10%), alternate days
  plan += (dayIndex even) ? endgameDrill(next unmastered E-node in Silman order, or due card)
                          : ownGameMistake(most recent unsolved)

  # Adaptive difficulty inside a session:
  #   rolling success over last 8 items >90% → +100 offset; <65% → −100 offset (bounded ±300)
  return trimToLength(plan, L)
```

**Selection query** for a themed puzzle: `theme = k AND rating BETWEEN target−100 AND target+100 AND id NOT IN seen(last 90 days) ORDER BY popularity DESC, random()`. Fall back by widening the band in ±100 steps.

**Curriculum gating:** skills unlock by prerequisites (e.g. C3 pin ← A3, B1; E9 Lucena ← E3, E4), but **the user can always free-play any theme**. Band-appropriate skills are suggested; skills more than one band above are hidden from the "focus" pool unless `game_k` is high.

**Explainability:** every plan item shows *why it is there*: "Because you missed 3 forks in your last 5 games", "Review: due today", "New: Philidor position". Aimchess and Chess.com both lean on this, and it drives adherence.

---

## 8. How to TEACH, not just test

1. **Lesson → worked example → faded practice → independent practice.** This is cognitive-load-theory canon. For a motif:
   (a) 2–3 sentences on the idea plus one animated example with arrows;
   (b) a **worked example** where the app plays the moves and narrates why;
   (c) a **faded example**: the first move is shown and the user finds the follow-up;
   (d) 6–10 themed puzzles;
   (e) the motif later appears in mixed sets.
   Yusupov and the Steps Method both follow explanation → graded exercises → test.
2. **Hint ladder** (Koedinger & Aleven's "assistance dilemma": give the least help that unblocks):
   - **H1 Strategic:** "Look for a forcing move," or the theme name ("There's a fork"). Optionally "Check, capture or threat first."
   - **H2 Focus:** highlight the **target(s)**, e.g. the overloaded defender or the two forked pieces.
   - **H3 Piece:** highlight the **piece to move**.
   - **H4 Bottom-out:** show the move with an arrow and explain it.
   Every hint used downgrades the FSRS grade (H1 → Good possible; H2–H3 → Hard; H4 → Again) and gives a partial Glicko score. Lichess counts any hint as a loss; a gentler partial credit is better for learning mode, while rated mode stays strict.
3. **Feedback after failure** (the most important teaching moment):
   - Show the **refutation** of the wrong move: the engine reply plus a one-line reason, e.g. "Qxf7?? — Black's knight was defending f7… after Nxf7 you've lost the queen."
   - Then let the user **retry** from the same position before revealing the answer, which gives a second retrieval attempt.
   - After the solution: a **"why it works" card** generated from tags and the line (template + tag + squares), e.g. "**Fork**: the knight on e5 attacks the king (g6) and the rook (c6) at once; the king must move, so the rook falls." These templates are deterministic, offline, and safe.
   - Mark the puzzle as an FSRS card ("you'll see this pattern again in 1 day").
4. **Visual language:** arrows (green = solution, red = threat/refutation, blue = hint), square highlights for attacked and hanging pieces, an optional "show attacked squares" overlay in board-vision mode, and animate the opponent's setup move (`Moves[0]`) so the user sees *what just happened* (Lichess does this).
5. **Thinking-process prompts** (Heisman) for D-skills: before the user's move in a "slow mode" puzzle, prompt "What does your opponent's last move threaten?" Before confirming, prompt "Checks, captures, threats for your opponent after this move?" This is the blunder-check checklist built into the UI. Fade it out as `safetyScore` improves.
6. **Self-explanation:** occasionally (about 1 in 10) ask after a solve, "Which motif was this?" (multiple choice from 4 tags). This cheap retrieval reinforces the category label and builds the vocabulary used in hints.
7. **Progress visibility:** per-theme ratings and strengths/weaknesses (the Lichess dashboard), a mastery map of the taxonomy, and the streak. Avoid vanity metrics that encourage guessing, such as raw puzzle counts.

---

## 9. Recommendations for our app

### 9.1 Drill types to ship in v1
1. **Lessons** (taught units): about 40 units covering taxonomy A–F essentials. Each has an explanation, an animated worked example, a faded example, a 6–10 puzzle themed set, and a mastery check (≥7/10).
2. **Rated puzzles**: mixed and themed, from the bundled Lichess subset, with the hint ladder, refutation feedback and "why it works" card. Includes **mate patterns** as a first-class menu (the 9 essential and 9 recommended named mates from §2) and **mate-in-N** ladders.
3. **Review (FSRS)**: failed puzzles, lesson key positions, endgame positions, own-game mistakes. Uses sibling-swap to avoid memorising answers.
4. **Warm-up speed set** (3 min, easy puzzles, 3-strike).
5. **Board vision / safety drills**: (a) coordinates; (b) "find all checks and captures" (tap all; scored by set match, auto-generated from any FEN with move generation); (c) **"Is this move safe?"**, using each Lichess puzzle's `Moves[0]` (the blunder) as the example. All three are cheap to build and target the #1 amateur failure.
6. **Endgame trainer**: about 25 curated positions in Silman order (K+Q, K+R, square, opposition, key squares, rook pawn, Q vs 7th-rank pawn, R vs pawn, Philidor, Lucena, triangulation, outside passer, wrong bishop). Played vs an engine with **tablebase judging** (bundle 3–4-piece Syzygy plus selected 5-piece files: KRPvKR, KQvKP, KBPvK) and immediate WDL-change feedback.
7. **Own-game analysis → personal puzzles** (if game import is in v1 scope): PGN import, on-device Stockfish, Lichess thresholds, motif tagging via a `cook.py` port, personal puzzles into FSRS, and weakness signals.

Deferred: Woodpecker mode (v1.1, on the failed-puzzle set), blindfold mode (v1.1), conversion drills vs engine (v1.1), guess-the-move (v2), opening repertoire SRS (v1.1 for users over 1200), strategy and pawn structures (v2).

### 9.2 Skill taxonomy
Use §1.2 (A board fluency, B checkmate, C motifs, D safety/thought process, E endgames, F opening principles, G calculation, H strategy) as **skill nodes with prerequisites**. Map each node to Lichess theme tags where possible:
- C1 → `hangingPiece`
- C2 → `fork`
- C3 → `pin`
- C4 → `skewer`
- C5 → `discoveredAttack`, `discoveredCheck`, `doubleCheck`
- C6 → `capturingDefender`
- C7 → `deflection`
- C8 → `attraction`
- C9 → `trappedPiece`
- C10 → `intermezzo`
- C11 → `clearance`, `interference`, `xRayAttack`
- C12 → `quietMove`
- C13 → `promotion`, `advancedPawn`
- C14 → `defensiveMove`
- C15 → `sacrifice`
- B1/B4/B5 → `mateIn1` / `mateIn2` / `mateIn3`+
- B3 → the named mate tags
- E → `pawnEndgame`, `rookEndgame`, etc., plus curated positions

Use hand-curated sets for untagged nodes (Greco, Damiano, Lolli, Légal, opening traps, all of D).

### 9.3 Data sources
- **Lichess puzzle DB** (CC0, 6.16M puzzles, Glicko-2 ratings, ~75 tags). Build-time script: filter `RD ≤ 80, Popularity ≥ 85, NbPlays ≥ 200, 400 ≤ Rating ≤ 2000` (about 35% pass), then **stratified sample by primary theme × 100-point bucket → about 100k puzzles**. Keep all rare mate-pattern and endgame puzzles up to a cap. Store in SQLite with a theme bitmask; expect about 10–20 MB in-app. Optionally offer a larger downloadable pack. Attribute Lichess anyway.
- **Theme names and descriptions**: lila `translation/source/puzzleTheme.xml` (AGPL repo; write our own descriptions to be safe, since they are short).
- **Motif tagger logic**: port the ideas of `lichess-puzzler/tagger/cook.py` (AGPL code; **reimplement, don't copy**) to tag own-game mistakes.
- **Opening names**: `lichess-org/chess-openings` (CC0) for `OpeningTags` and own-game opening detection.
- **Endgames**: hand-curated positions (Silman/Lichess-Practice style, positions themselves are not copyrightable) plus Syzygy subsets (data freely distributed; Fathom probe code MIT).
- **Engine**: Stockfish (GPLv3). Flag the App Store/GPL question for the architecture track.
- **SRS**: `swift-fsrs` (MIT, FSRS-6, SPM).

### 9.4 Adaptive algorithm (summary)
- **Per-skill Glicko-2** (user vs Lichess puzzle rating, primary tag full weight, secondaries half), **plus a Lichess-dashboard performance** (`avgRating − 500 + 1000 × firstWinRate`; weak if `failed ≥ 3` and below global) for display, **plus BKT or a 7/10 test** for lesson mastery and unlocking.
- **Game-derived weakness**: decayed per-motif counts of missed and allowed tactics (Lichess 0.1/0.2/0.3 winning-chance thresholds, motif-tagged), plus a safety score, endgame-family errors, conversion failures, opening deviations, and time-trouble errors from `%clk`.
- **Daily plan** (default 15 min), split: warm-up 10% → FSRS reviews ≤35% → focus block 35% (top-2 skills by `0.30·game + 0.25·gap + 0.20·freq + 0.15·uncertainty + 0.10·staleness`; lesson first if not mastered; themed set at skill rating −200; decoys) → interleaved mix 15% weighted to weaknesses → endgame/own-mistake 10%.
- **Difficulty targeting**: about 75–85% success in learning mode (rating offset about −200), 0 offset in rated/test mode, −500 for speed. Adjust within the session by ±100 per 8 items.
- **FSRS grades**: wrong or bottom-out hint = Again; hint or slow = Hard; clean = Good; clean and fast = Easy. Target retention 0.9. Sibling-swap puzzle reviews once S > 7 days.
- **Always show the reason** for each plan item.

---

## Sources
- Lichess puzzle DB: https://database.lichess.org/#puzzles
- Lichess theme definitions: https://github.com/lichess-org/lila/blob/master/translation/source/puzzleTheme.xml ; https://github.com/lichess-org/lila/blob/master/modules/puzzle/src/main/PuzzleTheme.scala
- Lichess puzzle dashboard and difficulty code: https://github.com/lichess-org/lila/blob/master/modules/puzzle/src/main/PuzzleDashboard.scala ; .../PuzzleDifficulty.scala
- Lichess move judgement: https://github.com/lichess-org/lila/blob/master/modules/tree/src/main/Advice.scala ; accuracy: https://lichess.org/page/accuracy
- Lichess puzzle tagger: https://github.com/ornicar/lichess-puzzler/blob/master/tagger/cook.py
- Lichess Practice: https://lichess.org/practice
- Steps Method: https://www.stappenmethode.nl/en/step1.php , step2.php, step3.php, step4.php ; https://nextlevelchess.com/steps-method-explained/
- Heisman: https://www.danheisman.com/definitions.html ; https://www.newinchess.com/media/wysiwyg/product_pdf/81008.pdf
- de la Maza critique: http://empiricalrabbit.blogspot.com/2010/12/7-circles.html ; http://kenilworthian.blogspot.com/2005/08/de-la-mazas-rapid-chess-improvement.html
- Woodpecker: https://budapestchessnews.com/2018/08/29/the-woodpecker-method/ ; https://chess.phd/blog/woodpecker-method-chess/
- Yusupov series: https://www.goodreads.com/book/show/3680932
- ChessKid: https://www.chesskid.com/article/view/new-chesskid-feature-release-levels ; https://www.chesskid.com/learn/lessons
- Silman endgame TOC: https://catdir.loc.gov/catdir/toc/ecip076/2006037884.html
- Checkmate patterns: https://en.wikipedia.org/wiki/Checkmate_pattern
- Syzygy: https://www.chessprogramming.org/Syzygy_Bases
- Charness et al. 2005: https://onlinelibrary.wiley.com/doi/10.1002/acp.1106
- Southwick et al. 2026: https://doi.org/10.1177/09567976261452568
- Chase & Simon / Gobet: https://notes.andymatuschak.org/Chase_and_Simon_-_Perception_in_chess ; https://www.researchgate.net/publication/13576754_Expert_Chess_Memory_Revisiting_the_Chunking_Hypothesis
- Einstellung: https://cognition.aau.at/download/Publikationen/Bilalic/Bilalic_etal_2008b.pdf ; https://www.scientificamerican.com/article/einstellung-how-psychologists-study-einstellung-effect-chess
- Interleaving meta-analysis: https://www.psychologie.uni-wuerzburg.de/fileadmin/06020400/2019/Brunmair_Richter_in_press__2019_META-ANALYSIS_OF_INTERLEAVED_LEARNING.pdf
- 85% rule: https://pmc.ncbi.nlm.nih.gov/articles/PMC6831579
- FSRS: https://github.com/open-spaced-repetition/free-spaced-repetition-scheduler ; https://github.com/open-spaced-repetition/swift-fsrs
- Chessable MoveTrainer intervals: https://support.chess.com/en/articles/10319322-how-does-the-spaced-repetition-scheduling-work
- Listudy: https://listudy.org/en/blog/spaced-repetition-for-chess
- Chess.com classification: https://support.chess.com/en/articles/8572705-how-are-moves-classified-what-is-a-blunder-or-brilliant-move ; Insights: https://support.chess.com/en/articles/8708925-what-is-insights-on-chess-com
- Aimchess: https://apps.apple.com/us/app/aimchess-learn-chess-online/id1524941307 ; https://www.raindropchess.com/aimchess-review-does-personalized-chess-training-actually-work/
- Chessbook: https://beta.chessbook.com/ ; Noctie: https://noctie.ai/
- Pelánek Elo in education: https://www.fi.muni.cz/~xpelanek/publications/CAE-elo.pdf
- Assistance dilemma / hints: https://www.cmu.edu/dietrich/philosophy/docs/scheines/Shih_Koedinger_Scheines_2008_EDM.pdf
- Blindfold (anecdotal): https://darksquares.net/learn/blindfold-chess
