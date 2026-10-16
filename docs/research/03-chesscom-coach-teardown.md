# 03 — Chess.com Coach Teardown (and how to beat it)

Research date: 2026-10-15. Scope: an offline-first iOS (Swift) chess-coaching app with an optional LLM on a home server.
Confidence tags: **[doc]** = chess.com's own help/news page; **[src]** = read open-source code; **[3p]** = third-party blog or review (several are competitors marketing themselves, so weigh them accordingly); **[inf]** = my inference.

Note on sources: Reddit blocks automated fetching, so the user complaints quoted below come from chess.com's own forums. Those forums are actually stronger evidence, because many of the posters are paying members. Chess.com support URLs redirect a lot. The URLs given below are the canonical ones.

---

## 1. Chess.com Game Review: how it works

### 1.1 User flow [doc]
1. When the game ends, a green **Game Review** button appears. Free users get 1 full review per day. Platinum and Diamond get unlimited reviews. ([support: How does Game Review work](https://support.chess.com/en/articles/8584089-how-does-game-review-work), [tiers](https://support.chess.com/en/articles/8562418-what-does-each-level-of-membership-get-me))
2. **Report card** screen: accuracy (0–100) for both players, a "Game Rating" estimate for each player, a count of each move classification, an eval graph, and **phase grades** for Opening, Middlegame and Endgame. Phase grades arrived with Game Review v2. ([Game Review v2 announcement](https://www.chess.com/news/view/chesscom-launches-game-review-v2))
3. **Start Review** walks you through the **Key Moments** in order. The coach avatar speaks one line per moment and the voice can be muted. Key moments include the last book move, brilliant or great moves, bad moves and missed tactics. ([chess.com/terms/game-review](https://www.chess.com/terms/game-review))
4. On a bad key move you can press **Retry** to replay the position and look for a better move. If you find it, you see "what your positional score would have been". ([terms page](https://www.chess.com/terms/game-review))
5. A follow-up button sits inside the coach's speech bubble: **Show Follow-Up**, **Show Fork**, **Show Lost Piece**, **Show Checkmate** or **Show Idea**. It animates the engine line on the board with arrows and highlighted squares. In v2 the coach also "draws arrows and highlights squares", and the threat explanations name the pieces involved and say whether a threat was prevented or allowed. ([v2](https://www.chess.com/news/view/chesscom-launches-game-review-v2))
6. You can move into a full **Analysis** board for free exploration with the engine.

The coach's speech bubble is the product's core. Chess.com's help pages and terms page don't name a published template grammar, but from user reports and the v2 notes the pattern is clearly:
`<classification praise/scold> + <one fact: material lost / threat allowed / piece left en prise / mate allowed> + <optional "Show X" button>`.
When no simple fact is available, the coach falls back to filler such as "That's an unfortunate error". A chess.com forum moderator explains why: *"when there's no clear way to explain a move, no explanation is given … the depth it gets to isn't enough to generate why it gives that evaluation."* ([forum, Dec 2024](https://www.chess.com/forum/view/game-analysis/why-does-the-coach-occasionally-just-not-explain-why-a-move-was-evaluated-the-way-it-was)) **[inf]** This strongly suggests a deterministic, template-and-feature system (hanging material, forks, mates, threats) with no LLM reasoning behind it. That design is the right one, but chess.com's feature set is shallow.

### 1.2 Coach avatars [doc]
- **Coach David** is the default for everyone. The help center lists "four unique coaches and twelve celebrity coaches, each with a distinct speaking voice". Celebrity coaches include Magnus, Hikaru, Levy Rozman, Danny Rensch, Anna Cramling and the Botez sisters. ([choose your coach](https://www.chess.com/news/view/choose-your-coach-on-chesscom), [manage coach](https://support.chess.com/en/articles/10812255-how-do-i-manage-the-coach))
- Voices are generated with ElevenLabs from celebrity voice samples, with a **dialogue tree** behind them. ([GamesBeat](https://gamesbeat.com/chess-com-will-let-you-choose-your-ai-coach-based-on-celebrity-voices/), [ElevenLabs case study](https://elevenlabs.io/blog/chess-dot-com)) A dialogue tree confirms the lines are template-driven rather than generated freely.
- Other coach settings: motivational messages, practice and review reminders, "show puzzle goals", "explain my mistakes" in puzzles, and "chat hints" in games.

### 1.3 Move classifications and criteria
Chess.com's **Expected Points model** turns the engine eval *and the player's rating* into a win expectancy from 0 to 1. Each move is graded by the expected points it loses. ([support: move classification](https://support.chess.com/en/articles/8572705-how-are-moves-classified-what-is-a-blunder-or-brilliant-etc)) [doc]

| Class | Expected points lost | Notes |
|---|---|---|
| Best | 0.00 | the engine's top move |
| Excellent | 0.00–0.02 | |
| Good | 0.02–0.05 | |
| Inaccuracy | 0.05–0.10 | |
| Mistake | 0.10–0.20 | |
| Blunder | 0.20–1.00 | |
| Book | — | the move is in the opening database (overhauled in v2) |
| **Brilliant (!!)** | — | "you find a good piece sacrifice". You must not be in a bad position afterwards and must not already be completely winning. **More generous for lower-rated players.** |
| **Great (!)** | — | "critical to the outcome": turns losing into equal or equal into winning, or is "the only good move". Also more generous for lower ratings. |
| **Miss** | — | you "fail to capitalize on your opponent's mistake". The threshold depends on rating. |

The exact sigmoid, the search depth and the rating adjustment are proprietary. Re-running a review can change borderline grades. ([ChessGrader critique](https://chessgrader.com/blog/is-chess-com-game-review-accurate/)) [3p]

**Best public reverse-engineering: WintrChess** (GPL-3.0, [github.com/WintrCat/wintrchess](https://github.com/WintrCat/wintrchess)). I read `shared/src/lib/reporter/` directly. [src]
- Expected points: `1/(1+exp(-0.0035*cp))`, with no rating term. Thresholds: Best < 0.01, Excellent < 0.045, Okay < 0.08, Inaccuracy < 0.12, Mistake < 0.22, otherwise Blunder. There are separate tables for mate→mate, mate→cp and cp→mate transitions.
- Classification order: **Forced** (only one legal move) → **Theory** (FEN found in the opening book) → checkmate = Best → top move = Best, otherwise point-loss class → upgrade to **Critical** (= Great) → upgrade to **Brilliant**.
- **Critical-candidate gate**: not already ≥ +7.00 even with the second-best move; not losing; not a queen promotion; not escaping check.
- **Critical (Great)**: the move is the top move, the second-best move loses ≥ 0.10 expected points, it isn't a capture of free material, and it isn't in a position where you already have mate.
- **Brilliant**: passes the critical-candidate gate, isn't a promotion, and *leaves at least one of your own pieces unsafe*, so material is really sacrificed. It is disqualified if it moves a piece *to* safety, if every unsafe piece is covered by an equal-or-bigger counter-threat ("danger levels"), or if the sacrificed pieces were trapped anyway. Piece safety is a static exchange heuristic: attacked by a lower-value piece = unsafe; attackers ≤ defenders = safe; defended by a pawn = safe; and so on.
- This roughly matches Chessigma's description: "no sacrifice, no brilliant"; looks bad at shallow depth and holds up at deep depth; not forced. ([Chessigma](https://www.chessigma.com/blog/brilliant-move-chess)) [3p]

**Lichess, for comparison** [doc/src]: `Win% = 50 + 50·(2/(1+e^(−0.00368208·cp)) − 1)`, fitted on real Lichess games. Per-move accuracy is `103.1668·e^(−0.04354·ΔWin%) − 3.1669`. Game accuracy averages a volatility-weighted mean and a harmonic mean. ([lichess.org/page/accuracy](https://lichess.org/page/accuracy)) The thresholds in `Advice.scala` are winning-chances deltas on a [−1, 1] scale: 0.1 = Inaccuracy, 0.2 = Mistake, 0.3 = Blunder, which is 5, 10 and 15 Win% points. ([lichess forum citing source](https://lichess.org/forum/general-chess-discussion/what-constitutes-an-inaccuracy))

**Research on what makes a move feel "brilliant"**: Zaidi & Guerzhoy (ICCC 2024, [arXiv 2406.11895](https://arxiv.org/abs/2406.11895)) predict human "brilliant" annotations with 79% accuracy. The key signal is that **weaker or shallower engines (Maia at 10 nodes, low-node Leela) rate the move as bad while stronger search rates it as good**. Brilliant moves "actually appear to be *losing* moves on average" at low node counts ([Balas summary](https://www.chess.com/blog/bjbalas/science-of-chess-what-makes-a-move-seem-brilliant)). → Our version can define Brilliant as **"Maia-at-your-rating assigns it low probability AND Stockfish says it's best or near-best"**. That is more principled than "you sacrificed something" and resists inflation.

### 1.4 Accuracy (CAPS → CAPS2) and Game Rating [doc]
- Accuracy measures how closely you matched the engine. CAPS2 changed the math so that "the majority of scores now fall mostly between 50 and 95", which reads like a school grade. The old CAPS gave single digits for 40% best moves and 99.9 for near-perfect games. ([support: accuracy](https://support.chess.com/en/articles/8708970-how-is-accuracy-in-analysis-determined), [original CAPS article](https://www.chess.com/article/view/better-than-ratings-chess-com-s-new-caps-system))
- **Game Rating** "estimates how well you played in a single game based on the quality of your moves". In practice it is anchored to the players' real ratings. A chess.com forum moderator: *"If you … put high ratings on one or both players, the estimated rating will be high … put low ratings on the players, on the exact same game, the estimated ratings will be lower."* ([forum, Sep 2025](https://www.chess.com/forum/view/general/game-review-estimated-game-rating-is-a-lie-and-deceit))

### 1.5 Cost (US, 2025–26) [doc/3p]
| Tier | ~Monthly / ~annual-per-month | Coaching-relevant features |
|---|---|---|
| Free | $0 | 1 Game Review/day, **1 game vs Coach/month**, 3 puzzles/day, 1 Puzzle Rush and 1 Battle/day, limited lessons, first 4 moves of the opening explorer |
| Gold | $9.99 / ~$4.17 | unlimited puzzles and lessons, **unlimited Play Coach**, all bots, full explorer, no ads |
| Platinum | $14.99 / ~$6.67 | + **unlimited Game Review** |
| Diamond | $19.99 / ~$12.50 | + **"coach explanations on all of your moves"**, **Insights**, Advanced Stats |

Sources: [support: tiers](https://support.chess.com/en/articles/8562418-what-does-each-level-of-membership-get-me), [pricing summary](https://www.chess.com/blog/speedyg2/is-a-premium-chess-com-membership-worth-it-2021). **The feature this app is reverse-engineering, explanations on every move plus cross-game Insights, is the $240/yr list-price tier.**

---

## 2. Play Coach, training and AI features

### 2.1 Play Coach ([announcement](https://www.chess.com/news/view/announcing-play-coach), [help](https://support.chess.com/en/articles/10877257-how-do-i-play-against-the-coach)) [doc]
- You play an adaptive engine opponent at chess.com/play/coach and choose your color and level.
- **Hint**: the first tap *highlights pieces* to nudge you, and the second tap shows the best move as an arrow. This two-stage hint is a good pattern to copy.
- **Threats** toggle: shows what the coach is threatening.
- **Undo / takeback** without limits.
- **Real-time commentary**: praise for good moves, explanations for mistakes, and "pointers at critical moments … like when a piece is attacked or when you need to make a key positional move".
- Toggles for move suggestions, threat display and the eval bar. You choose among 4 coach avatars.
- A narrated Game Review runs afterwards.
- **Limitation**: *"If you ask 'but what if I had played Nc6 instead' Play Coach goes quiet — there's no back-and-forth."* ([chessvia 2026](https://www.chessvia.ai/blog/chess-com-game-review-free)) [3p]

### 2.2 The rest of the training stack [doc]
- **Puzzles**: Rated (rating moves up or down with solve speed and difficulty), **Puzzle Rush** (timed streak), **Puzzle Battle** (3-minute head-to-head), Daily, and **Custom Puzzles** (formerly "Learning mode": pick themes, a rating range, and optionally only puzzles you failed before). ([support: puzzles](https://support.chess.com/en/articles/8608686-how-do-puzzles-work))
- **Practice** (formerly Drills): openings against a bot that plays your chosen line, themed drills, endgames (checkmates, pawn, minor-piece and rook endings, with timed challenges and leaderboards), master games, and custom positions. ([support: Practice](https://support.chess.com/en/articles/8724749-what-is-practice-on-chess-com), [endgames](https://www.chess.com/announcements/view/new-perfect-your-endgame-technique))
- **Lessons**: dozens of video and interactive courses. Reports say lesson suggestions are now personalized from your game history ([chessvia](https://www.chessvia.ai/blog/best-chess-software)) [3p]. In early 2025 a power user complained that "Suggested Lessons" had been removed from Game Review ([forum](https://www.chess.com/forum/view/site-feedback/detailed-critique-of-new-game-review-110227953)).
- **Vision**: a board-awareness drill introduced in 2025. [3p]
- **Insights** (Diamond only): accuracy over time and by move number, results against opponent rating bands, % of games ending in each phase, accuracy by phase, your top 10 openings per color with results, and "Opening Mastery" (how many moves before you leave theory). ([support: Insights](https://support.chess.com/en/articles/8708925-what-is-insights-on-chess-com), [Opening Insights](https://www.chess.com/news/view/announcing-opening-insights))
- **Advanced Stats**: lets you revisit your brilliant moves. ([announcement](https://www.chess.com/news/view/announcing-advanced-stats))
- The Openings Explorer and opening courses are covered by Gold and above.
- The **Chessable** (spaced-repetition courses) and **ChessKid** brands are both owned by chess.com.

**Takeaway**: chess.com has *every surface* (play, review, puzzles, drills, lessons, stats) but they are **siloed**. Insights shows stats but doesn't prescribe anything. Game Review doesn't feed your mistakes into puzzles, except that Custom Puzzles can replay puzzles you *failed*, not positions from *your games*. The coach doesn't remember anything between sessions.

---

## 3. User complaints about Game Review and the coach

| # | Complaint | Evidence |
|---|---|---|
| C1 | **Says *what*, not *why*.** Labels without reasons, or empty filler | *"That's an unfortunate error"… "hard to learn from your mistakes when you don't know what the mistakes are."* — Fr3nchToastCrunch, Dec 2024 ([forum](https://www.chess.com/forum/view/game-analysis/why-does-the-coach-occasionally-just-not-explain-why-a-move-was-evaluated-the-way-it-was)). A recurring thread title: "game review stopped giving explanations" ([forum](https://www.chess.com/forum/view/help-support/game-review-stopped-giving-explanations)). Summary line: the review "tells you if you blundered, not why you blundered" ([chessdrive](https://chessdrive.io/blog/chess-game-review-explained)) |
| C2 | **Wrong explanations, especially for sacrifices and combinations** | *"the coach says it was a blunder to use the knight as queen bait"* (the knight sac won a rook by fork), Jan 2023. *"the bot tell me I blundered … even though the move was necessary to enable checkmate in 2"*, Dec 2023 ([forum](https://www.chess.com/forum/view/site-feedback/bot-coach-usually-excellent-being-wrong)). *"They always call my checkmate setup a blunder"* ([forum, May 2025](https://www.chess.com/forum/view/general/game-reviews-terrible)) |
| C3 | **Doesn't understand the player's plan; assumes perfect replies** | *"The game review isn't able to 'see' your plan 9 times out of 10, and only considers its own plan."* *"The game review expects that the opponent plays the perfect moves. But on your level, 200-300, most players don't."* ([forum, May 2025](https://www.chess.com/forum/view/general/game-reviews-terrible)) → This is the argument for Maia: judge "risky but practical" moves by what humans at your level actually play |
| C4 | **Brilliant inflation and gamification** | *"Out of all of the above examples, only the last 2 really made me feel like I found something actually brilliant."* ([forum, Apr 2023](https://www.chess.com/forum/view/site-feedback/brilliant-moves-arent-all-that-brilliant)). People "farm Brilliancies with objectively unnecessary queen sacs in already-won positions" ([ChessGrader](https://chessgrader.com/blog/is-chess-com-game-review-accurate/)) |
| C5 | **Game Rating and accuracy are vanity numbers** | Game Rating follows the players' actual ratings, not the game ([forum](https://www.chess.com/forum/view/general/game-review-estimated-game-rating-is-a-lie-and-deceit)). *"96.5% accuracy … rating of 1500. Hikaru plays ~80% … 2700."* *"No one takes these enhancements seriously except the marketing department."* — Ziryab |
| C6 | **Same language for every level** | "The same coaching language is used whether you're 400 or 1900" ([improvemychess](https://www.improvemychess.co/learn/best-chess-com-game-review-alternatives-2026)) [3p, competitor] |
| C7 | **No memory across games, no curriculum** | It "cannot identify that 'you make the same blunder every third game'"; *"It evaluates; it does not prescribe a curriculum."*; no memory between sessions; ignores playing style ([MyChessPlan 2026](https://mychessplan.com/chess-com-play-coach-mode-honest-review-adult-improvers-2026/)) [3p] |
| C8 | **UX regressions in the v2 redesign** | Eval graph disappears, move list became a horizontal scroll ("you can never see all of them at once"), "Suggested Lessons has been removed" ([forum, Jan 2025](https://www.chess.com/forum/view/site-feedback/detailed-critique-of-new-game-review-110227953)). Removed the "change your moves and see what accuracy you get" feature. *"I cancelled my Diamond membership because of this"* ([forum, Oct 2024–Feb 2025](https://www.chess.com/forum/view/site-feedback/the-new-game-review-on-the-app-is-a-lot-worse-than-the-old-one)) |
| C9 | **Oversimplified reasons that are technically true but miss the point** | "This loses a pawn" when the real problem was the king never castling ([ChessGrader](https://chessgrader.com/blog/is-chess-com-game-review-accurate/)) |
| C10 | **Opaque and non-reproducible** | Depth, nodes, formula and the rating adjustment are all secret, and borderline grades change between runs ([ChessGrader](https://chessgrader.com/methodology/)) |
| C11 | **"More fun than serious learning"** | *Game Review is "more about fun than serious learning"; use the analysis board instead* — davidk67, Dec 2025 ([forum](https://www.chess.com/forum/view/game-analysis/why-does-the-coach-occasionally-just-not-explain-why-a-move-was-evaluated-the-way-it-was)) |
| C12 | **Paywall on the useful parts** | Per-move explanations and Insights need Diamond. *"Why would I pay $120 for a year of 'better' game reviews?"* ([forum](https://www.chess.com/forum/view/general/game-reviews-terrible)) |

---

## 4. Competitors: what each does best

| Product | What it does uniquely well | Weakness | Steal |
|---|---|---|---|
| **Lichess** (free, open) | Unlimited server analysis. **"Learn from your mistakes"** marks your bad move in red, asks you to "make another try", only reveals the answer on request, and checks against a masters DB so opening moves aren't flagged ([blog](https://lichess.org/blog/WFvLpiQAACMA8e9D/learn-from-your-mistakes)). **Puzzle Dashboard**: per-theme performance, a radar chart, a "Strengths" list and an **"Improvement areas" list with replay** ([forum](https://lichess.org/forum/general-chess-discussion/puzzle-dashboard-2)). **Practice** section, **Studies** with interactive lessons. Publishes its accuracy formula. | No natural-language explanations, no plan | Make-another-try retry, theme dashboard, transparent formulas. The **Lichess puzzle DB and opening names are CC0**, so they can ship offline |
| **Chessable** (chess.com-owned) | **MoveTrainer** spaced repetition. Commentary is interleaved with quizzes, one move at a time. Each *move* has its own interval: L1 4h → 1d → 3d → 1w → 2w → 1mo → 3mo → L8 6mo, and a mistake resets the interval ([support](https://support.chess.com/en/articles/10319322-how-does-the-spaced-repetition-scheduling-work), [Matuschak notes](https://notes.andymatuschak.org/zDr94hP6bG3jJYrdYy8B5hx)) | Book-shaped content, not drawn from your own games | Per-move SRS scheduling |
| **Chessbook** | Build **your own** repertoire. Per-move (not per-line) storage so transpositions work. Moves scored by Lichess data **for your rating**, plus master scores and precomputed evals ([review](https://64squares.substack.com/p/chessbook-review)) | Openings only | Per-move repertoire graph and "what your opponents at your rating actually play" |
| **Aimchess** (Play Magnus Group) | Imports from chess.com and Lichess and scores **6 skills**: Tactics, Endgame, Advantage Capitalization, Resourcefulness, Time Management, Opening. Compares you with peers of your rating. Builds a training plan with weekly targets and puzzles made from your mistakes ([App Store](https://apps.apple.com/us/app/aimchess-learn-chess-online/id1524941307), [stork](https://www.stork.ai/en/aimchess)) | Puzzles feel "disconnected from actual games" [3p] | Skill radar with peer percentiles, and a plan with targets |
| **Noctie.ai** | **Human-like bot** from 400 to 2800 across 25 levels, with human openings, mistakes and *move timings*. Instant grading during play, hints, retries. **Your mistakes become flashcard puzzles in SRS decks.** Repertoire drills where the AI plays "the most common human responses". €14/mo or €8/mo yearly ([noctie.ai](https://noctie.ai/)) | Thin on explanations | The closest product to our target. Beat it with grounded explanations, memory and offline use |
| **Maia Chess platform** (U Toronto / MSR) | Maia-2 is a single rating-conditioned model of human moves ([NeurIPS 2024, arXiv 2409.20553](https://arxiv.org/abs/2409.20553)). Platform v1 (Jul 2025) shows each move "through two lenses": engine eval plus **how players at different ratings would play it** ([blog](https://www.maiachess.com/blog/platform-v1)). They are researching a personalized Maia that predicts *your* recurring mistakes ([MSR](https://www.microsoft.com/en-us/research/?p=708031)) | Research-grade UX | The "what would a 1200 play here" lens, and a human-like opponent |
| **Allie** (CMU, ICLR 2025) | Human-aligned bot that also models **think time and resignation**. Adaptive search keeps it within about 49 Elo of its opponent across 1000–2600 ([arXiv 2410.03893](https://arxiv.org/abs/2410.03893)) | Research only | Human pacing for the in-game coach opponent |
| **DecodeChess** | Breaks engine analysis into tabs (Threats, Good Moves, Plans, Functionality, Concepts) and aims at players up to ~2000 ([decodechess about](https://decodechess.com/about/)) | Mechanical. Documented hallucinations, e.g. "queen on c7 to guard g3" when the queen was on d8 ([chess.com blog](https://www.chess.com/blog/sbernst8/state-of-chess-ai-for-move-interpretation)) | A tab structure for "Threats / Plans / Piece roles" |
| **Dr. Wolf** | A **spoken** coach that teaches *while you play*, explains its own moves as well as yours, and sometimes "gently suggest[s] you reconsider a move or ask[s] a question at a critical moment" ([App Store](https://apps.apple.com/us/app/id1353041020)) | Beginner ceiling | **Socratic interruption at critical moments** |
| **ChessKid** (chess.com) | Gamified lesson progression, a large puzzle library, Workouts and Vision drills ([guide](https://chesskid.com/learn/articles/complete-guide-to-chesskid)) | Kids only | Level and progression loop |
| **Chessigma / WintrChess / Chessiro** | Free, unlimited chess.com-style reports. Chessiro runs Stockfish *in the browser*, has an AI coach that takes follow-up questions, shows "themes you missed / handled well" with one-click practice, and supports 24 languages ([Chessiro](https://chessiro.com/blog/inside-chessiro-game-review)). WintrChess is GPL source for the classification logic | Clones with labels and little reasoning | Proof that on-device analysis is a parity feature, and that themes should link to practice |
| **Listudy** (FOSS) | Spaced repetition on any PGN: openings, endgames, tactics ([listudy.org](https://listudy.org/)) | Bare UI | SRS on arbitrary positions |
| **Woodpecker apps** (Disco Chess, ChessWoodie) | Repeat a **fixed small set** of puzzles in shrinking cycles until the patterns are automatic | Generic sets | Woodpecker cycles over *your own* mistake set |
| **Improve my Chess / Chessvia / MyChessPlan** (2026 GPT-coach crop) | Explanations tuned to rating (400–999). **Opponent scouting** before games [3p, self-reported] | Single-platform, new | Rating-appropriate vocabulary, pre-game scouting |

---

## 5. Generating explanations that are reliable

### 5.1 The evidence: raw LLMs are unreliable on chess facts
- **ACT-Eval / "Hallucinations on the Board"** ([arXiv 2608.04240](https://arxiv.org/abs/2608.04240)): commentary is broken into atomic claims and each claim is checked with deterministic tools. Without tools, **GPT-5.4 gets 22.0% of sub-claims wrong** and open-weight models exceed 40%. Error rates with tools vs without: GPT-5.4 22.0→9.2%, Claude Opus 4.7 20.8→13.4%, Gemini 3.1 Pro 10.8→7.5%, DeepSeek V4 Pro 36.7→14.4%. **Bad-move detection F1 jumps from 12.5 to 97.6** (GPT-5.4) with tools. Error taxonomy: board comprehension, legality, quality evaluation, tactical reasoning, other. Small open models fail on *board and legality*. Frontier models produce "plausible continuations that become inconsistent after several moves". With tools, the remaining errors are tactical (overlooked defences, invented forcing lines). The tool suite is a good spec for our feature extractor: piece locations, legal moves, material, check, attacked squares, attackers, pins, threat verification, ray alignment, open files, variation simulation, and engine top-N and compare.
- **Concept-guided Chess Commentary (CCC)**, NAACL 2025 ([arXiv 2410.20811](https://arxiv.org/abs/2410.20811)): uses **Stockfish 8 classical eval terms** as 20 concepts (material, imbalance, pawns, knights, bishops, rooks, queens, mobility, king safety, threats, space and passed pawns, per side). It **ranks the concepts whose score changed most between the pre-move and post-move positions** and feeds the top ones plus an **enumerated list of real attacks** to the LLM so it "prevent[s] mentioning … non-existing pieces or illegal moves". Human-rated correctness was 0.60, with fluency at 0.91. Remaining error rates: 20% illegal or non-existent references, 26% tactical, 28% positional. GPT-4o's mate-in-1 rate went from 57% to 73.6% with concept guidance. Stockfish's classical eval was **removed in SF16 (2023)**, so we have to write our own term extractor (an approximate port of the SF classical terms is fine).
- **Grounded Chess Reasoning via Master Distillation** (Anderson lab, [arXiv 2603.20510](https://arxiv.org/abs/2603.20510)): **C1, a 4B model**, is distilled from Stockfish d24 PVs turned into step-by-step explanations. It goes from near 0 to 48.1% and beats most frontier models while using about 100× fewer tokens. This shows a small model that could run on the home server.
- **Communicating Chess Strategies in Natural Language** ([arXiv 2607.11486](https://arxiv.org/abs/2607.11486), Jul 2026): defines "strategy verbalization". Finds that purely concept-based descriptions are weak and that strategies must be checked *beyond the main PV*. Our "plan" text should therefore be checked against several engine lines, not only line 1.
- **Do Chess Explanations Reflect Model Decisions?** ([arXiv 2609.22245](https://arxiv.org/pdf/2609.22245)): the explanations LLMs give for their own moves are often not faithful to how they chose them. So never let the LLM *decide*. It only gets to *phrase*.
- **ChessQA** ([arXiv 2510.23948](https://arxiv.org/abs/2510.23948)): benchmark showing that reasoning models do better but no model is reliable across all chess tasks.
- **Jhamtani et al., ACL 2018** ([P18-1154](https://aclanthology.org/P18-1154/)): 298K move–comment pairs from gameknot. Useful for the *style* human annotators use. Its categories (move description, quality, comparison, planning/rationale, context) make a good taxonomy for templates.
- **Lichess puzzle tagger** ([ornicar/lichess-puzzler `tagger/cook.py`](https://github.com/ornicar/lichess-puzzler)): about 60 deterministic motif detectors: fork, pin, skewer, discovered attack, double check, hanging piece, trapped piece, deflection, attraction, overloading, interference, clearance, x-ray, intermezzo, quiet move, defensive move, sacrifice, back-rank, smothered, Anastasia, Arabian and hook mates, exposed king, attacking f2/f7, advanced pawn, promotion and underpromotion, plus endgame-type tags. **It is AGPL**, so for a closed iOS app we must reimplement the *ideas* in Swift without copying code. Also check the licences of WintrChess (GPL-3) and Stockfish (GPL-3) for App Store distribution.

### 5.2 Recommended pipeline (deterministic first, LLM optional) [inf, built on the above]
```
Engine (Stockfish, MultiPV 3–5, on device)  ──┐
Maia-2 policy at user's rating (CoreML)     ──┤
Feature extractor (Swift, deterministic):    ─┤──► Fact sheet (typed JSON: claims[] each with evidence)
  material/SEE, hanging & unsafe pieces,       │      │
  attacks/defends, pins/skewers/x-rays,        │      ├─► Template renderer (offline, always works)
  forks/double attacks, mate threats,          │      └─► LLM (home server, optional): "rephrase ONLY these
  king-safety (shield, open files, attackers), │           facts for a {rating} player; cite claim ids"
  pawn structure (isolated/doubled/passed/     │                 │
  backward), mobility, space, outposts,        │                 ▼
  phase, opening name (CC0 book)             ──┘      Verifier: re-parse every square/piece/move mentioned,
                                                       check legality & presence vs fact sheet; drop or fall
                                                       back to template on any unverifiable token
```
Rules that follow from the papers:
1. **The engine decides and the LLM only phrases.** Classification, the best move and "why it's bad" come from the engine line plus the feature diff.
2. **Explain with the refutation line.** The "why" for a mistake is: *the opponent's best reply* (PV move 1), *what it attacks or wins* (feature diff after that move), and *what you should have played* (best move plus the feature it addresses). This fixes C1. If the PV is longer than about 3 plies and no simple feature explains it, **say so honestly** ("the engine sees a long-term problem: let's look at the position 5 moves later") rather than using filler. Better still, show the position where the material or mate actually happens.
3. **Rank concepts by delta**, as in CCC, so the text names the one or two biggest changes and not every term.
4. **Enumerate facts and whitelist entities.** The prompt gets the full list of real attacks, pins, hanging pieces and legal candidate moves. Then a post-hoc regex extracts every SAN or square from the output and checks it against the fact sheet, as in ACT-Eval.
5. **Check claims across lines.** "This wins a piece" must hold in the top 2–3 engine lines, not only the PV (2607.11486).
6. **Rate the "human" difficulty with Maia.** p(move | rating) tells you whether a mistake was natural ("most 1200s play this too: here is the hidden trick") or careless. It also gives a principled Brilliant/Great definition (low Maia probability plus engine-best) and fixes C3 and C4.
7. **Adapt vocabulary to rating, not content.** The fact sheet stays the same and only the register changes (fixes C6).
8. **Small grounded model** (C1-style 4B, or a 7–8B instruct model on the home server) is enough for phrasing. The iPhone ships with templates. With the server present, the text is richer, but correctness does not depend on the server.

---

## 6. Where we can beat chess.com

| Opportunity | Why chess.com loses here | Build notes |
|---|---|---|
| **Cross-game mistake memory** | Fixes C7. Insights is stats, not causes | Tag every mistake with motif tags (hung piece, missed fork, back rank, king left in centre, bad trade, time-trouble), the phase, the opening and the eval band. Keep the tag history locally (SQLite/GRDB) and report "Your #1 leak this month: you miss knight forks after your opponent castles queenside (7 of 23 games)" |
| **Retry your mistakes as SRS** | Retry is one-shot and Custom Puzzles only replays *failed puzzles* | Every Mistake, Blunder and Miss from your own games becomes a card with a per-position schedule like Chessable's L1–L8 (or FSRS). Add a Woodpecker mode that cycles your own set. Noctie proves people want this; do it offline and with explanations |
| **Personalized plan** | "It evaluates; it does not prescribe" | Weekly plan derived from leak frequency × fixability: e.g. 3 SRS sessions, 20 fork puzzles from the CC0 Lichess DB at your rating, 1 endgame drill, 5 coach games with the "threats" overlay on. Measure the leak rate before and after |
| **Repertoire built from your own games** | Insights only lists your top 10 openings | Build a per-move repertoire graph from your games, Chessbook-style. Flag where you leave book and lose eval. Fill gaps using what *your-rating* opponents actually play (Maia probabilities, or Lichess explorer counts when online). Drill it with SRS against a human-like bot |
| **Socratic walkthrough** | The coach monologues, and Play Coach "goes quiet" on what-ifs | Before revealing anything: "What does Black threaten after ...Nd4?" Tap a square or piece to answer, get a 2-stage hint (highlight the area, then the arrow), and you can always play any what-if move and get a grounded explanation for it |
| **Human-like coach opponent that talks** | Play Coach is an engine opponent with tips | Maia-2 (CoreML) at your rating ±100, with human-like think time as in Allie. The coach speaks only at *critical moments*: threat ignored, tactic available, or a large drop in Maia vs SF value. Interruption is Dr. Wolf-style and doesn't need to block ("Are you sure? Look at the e-file") |
| **Honest, transparent metrics** | Fixes C5 and C10 | Publish the formulas: Lichess-style Win% and accuracy, plus a *Maia-calibrated performance rating* (the rating at which Maia most likely plays your moves). That is an actual per-game estimate, not one anchored to your real rating |
| **Meaningful Brilliant** | Fixes C4 | Low Maia probability at your rating, engine best or within 0.02 EP, not already winning by more than +7, not forced. Add a separate "Sacrifice" badge if you want the dopamine |
| **"Why" for every flagged move** | Fixes C1, C2 and C9 | Refutation line plus feature diff, never filler. Detect sacrifices before calling something a blunder: if the PV regains the material or mates, grade it on EP loss, not material |
| **Full context UX** | Fixes C8 | Always-visible eval graph, a vertical two-column move list, and your move and the best move shown at the same time |
| **Offline, no paywall per review** | Fixes C12 | Stockfish on device gives unlimited reviews, and works on a plane. The LLM is an optional extra on top |

---

## 7. Prioritized feature list

### Parity (must match chess.com)
1. **On-device Stockfish game review with EP-based classifications** (Best/Excellent/Good/Inaccuracy/Mistake/Miss/Blunder/Book/Forced): table stakes. WintrChess logic and the Lichess formulas give us a known-good baseline.
2. **Accuracy score plus eval graph**: users expect a single number. Use the published Lichess formula for transparency.
3. **Key Moments walkthrough with a coach line per moment**: chess.com's main UX loop.
4. **Retry the position, with a 2-stage hint (highlight, then arrow)**: chess.com and Lichess both have it, and it's the most valued learning action.
5. **Show Follow-up / Show Threat animation** of the engine line on the board: turns text into something you can see.
6. **Phase grades (opening, middlegame, endgame)**: cheap to compute and part of the v2 report card users now expect.
7. **Brilliant / Great badges**: users love them. Keep them, but define them better (see D7).
8. **Play-vs-Coach with hints, undo, threat overlay and an adjustable level**: Gold-tier chess.com feature.
9. **Rated puzzles plus themed Custom Puzzles** from the CC0 Lichess puzzle DB, shipped offline: free-tier parity.
10. **Opening names and book detection** (CC0 opening list): stops opening moves being flagged.
11. **Game import from chess.com and Lichess (public APIs) plus PGN**: users already have years of games there.
12. **Voice narration** (AVSpeechSynthesizer, optionally a nicer server TTS): chess.com's spoken coach is a big part of its appeal.

### Differentiators (beat chess.com)
1. **Grounded "why" for every flagged move** (refutation line plus feature diff, verifier, honest fallback): fixes the #1 complaint.
2. **Cross-game leak memory with a ranked "top 3 leaks"**: chess.com analyses each game alone.
3. **Your-own-mistakes SRS deck plus Woodpecker cycles**: turns review into retention, which chess.com doesn't connect.
4. **Weekly personalized plan with before/after leak metrics**: answers "what do I study next", which chess.com doesn't prescribe.
5. **Maia-2 human-like coach opponent at your rating that speaks at critical moments**: practice that feels like a real opponent, with a coach interrupting at the right moment.
6. **Socratic mode with free what-ifs**: where Play Coach goes quiet, ours answers what-ifs and asks questions back.
7. **Maia-defined Brilliant and difficulty-aware grading** ("most 1200s miss this"): fixes brilliant inflation and the complaint that review "doesn't see my plan".
8. **Repertoire graph built from your games, drilled against human-likely replies**: Chessbook and Noctie features joined to your own games.
9. **Honest metrics: published formulas plus a Maia-calibrated per-game performance rating**: fixes the "Game Rating is a lie" complaint and builds trust.
10. **Rating-adaptive explanation register** (same facts, different vocabulary): fixes "same language for 400 and 1900".
11. **Optional home-server LLM for phrasing and chat, never for deciding**: richer text without hallucinations (ACT-Eval shows a 22%→9% claim error rate with tools).
12. **Fully offline and no per-review paywall**: removes chess.com's main frictions (1 review per day free, $240/yr for explanations).

---

### Licensing to verify before building
Stockfish, WintrChess and Maia are GPL-3. lichess-puzzler is AGPL. The Lichess puzzle DB, opening names and game DB are CC0. App Store distribution of GPL code is a known grey area. Either open-source the app, or keep GPL components clearly separated and get advice. Reimplement motif detectors and classification logic clean-room in Swift.
