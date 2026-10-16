# 02 — Open-Source Stack for an iOS Chess-Coaching App

Researched 2026-10-15. GitHub stats came from the GitHub REST API on that date. "Last push" is `pushed_at`. Licenses are the SPDX ids GitHub reports, and I checked them against LICENSE/COPYING files where it mattered.

Context: Swift/SwiftUI app for iOS 17+. It works offline first and can optionally reach a home PC (Windows, GTX 980 Ti) over Tailscale. The play UI should look and feel like chess.com. The user wants to reuse as many OSS libraries as possible.

---

## 0. License primer for this project (read first)

- **GPL-3 / AGPL-3 obligations trigger on *distribution*** (and for AGPL, also on *network use by others*). A purely personal build sideloaded onto your own phone and never given to anyone has no compliance problem with any license below.
- **If the app is later distributed** (TestFlight to friends counts, and so does the App Store), every GPL-3 component **statically linked into the binary** forces the *whole app* to be GPL-3 compatible. That means you publish the full source under GPL-3. The FSF also argues that App Store terms add restrictions that GPL-3 §10 forbids (the VLC precedent from 2011). Many App Store chess apps do ship Stockfish with published source, and the Stockfish team enforces source availability (they sued ChessBase in 2021 and settled).
- **Running a GPL program on your own server and talking to it over the network is *not* distribution.** Plain GPL has no network clause. So Stockfish, Lc0 and python-chess on the home PC are clean for a closed-source client. AGPL code on that server would only matter if *other people* used the server.
- **CC BY-NC-SA assets** (many Lichess piece sets, the Lichess "lisp" sounds, WintrCat/freechess code) cannot be used in anything sold or monetized, and ShareAlike propagates to derivatives.
- **CC0** data (Lichess puzzles, games, evals, chess-openings) can be used anywhere.
- **MIT/BSD/Apache** can be used anywhere with attribution.

**Strategy that keeps every door open:** use permissive libraries in the iOS binary (MIT logic and UI, BSD/CC0 assets). Keep Stockfish in its own module, so the choice later is either (a) publish the app as GPL-3 open source, or (b) swap the on-device engine for server-only analysis. Do not copy any code from GPL/AGPL review repos. Re-implement from the published *formulas*, since formulas and thresholds are facts and not copyrightable expression.

---

## 1. Swift chess logic

| Library | Stars | Last push | License | Notes |
|---|---|---|---|---|
| [chesskit-app/chesskit-swift](https://github.com/chesskit-app/chesskit-swift) | 48 | 2026-08-07 (release 0.17.0, 2025-11-12) | **MIT** | Pieces, squares, moves, positions, `UInt64` **bitboard** legal-move validation, castling/en passant, check/mate/stalemate/draw detection, promotion. Parses **FEN, PGN, SAN, UCI LAN**. Has a **variation tree** (`MoveTree`) with PGN tags. Includes a CLI. Codecov-tracked tests. Actively maintained, with releases every ~3 months. |
| [chesskit-app/chesskit-engine](https://github.com/chesskit-app/chesskit-engine) | 39 | 2025-09-16 (0.7.0) | MIT wrapper, **bundles GPL-3 engines** | See §2. |
| [rohanrhu/ChessboardKit](https://github.com/rohanrhu/ChessboardKit) | 75 | 2025-12-13 | MIT | A SwiftUI *board* (see §3). It depends on **aperechnev/ChessKit**, not chesskit-swift. |
| [aperechnev/ChessKit](https://github.com/aperechnev/ChessKit) | 24 | 2025-10-01 | MIT | "Lightweight and fast" Swift chess framework, less featureful (weaker PGN/variation support). **Its module name `ChessKit` collides with chesskit-swift's `ChessKit` module.** You cannot easily import both in one target, which is a practical problem if you adopt ChessboardKit unmodified. |
| [SteveBarnegren/SwiftChess](https://github.com/SteveBarnegren/SwiftChess) | 149 | **2020-12-22 (abandoned)** | MIT | Logic plus a toy AI. Not maintained, so avoid it. |
| "sweet-chess" | — | — | — | No such maintained repo exists (`nicklockwood/sweet-chess` returns 404). Treat it as non-existent. |

**Performance:** chesskit-swift uses bitboards, so legal move generation is in the microsecond range per position. That is ample for UI, PGN replay and puzzle validation. Perft-grade speed is only needed inside the engine, and Stockfish does that itself.

**Verdict:** **chesskit-swift is the best-maintained Swift chess logic library and is MIT.** Use it as the single source of truth for rules, FEN, SAN and PGN, including variation trees for analysis.

---

## 2. On-device engines for iOS

### Stockfish
- Upstream: [official-stockfish/Stockfish](https://github.com/official-stockfish/Stockfish), 16.9k stars, **GPL-3**. **Latest release is `sf_19` (2026-09-05).**
- **chesskit-engine** (MIT wrapper) compiles **Stockfish 17** and **Lc0 0.31.1** into an SPM C++ target (`ChessKitEngineCore`). It supports iOS 16+/macOS 13+ and builds with `NNUE_EMBEDDING_OFF` and `NO_PEXT`. The API is async: `Engine(type: .stockfish)`, then `start()`, `.position()` and `.go()`, with an async stream of UCI info and bestmove. **NNUE nets are NOT bundled.** You ship them in the app bundle or download them, then set `setoption EvalFile/EvalFileSmall` ([README](https://github.com/chesskit-app/chesskit-engine)). It is one SF version behind (17 vs 19). That is fine for coaching, or you can bump the vendored source.
- **App-size impact (measured by downloading from tests.stockfishchess.org):**
  - SF17 big net `nn-1111cefa1111.nnue` = **74.9 MB**
  - SF17 small net `nn-37f18f62d772.nnue` = **3.5 MB**
  - Current master/SF19 default big net `nn-c9e480e92425.nnue` = **113.2 MB**
  - Option: ship only the small net, which keeps the app under 10 MB of engine data and is still around 3000+ Elo. Download the big net on demand via On-Demand Resources or a first-run download from the home PC.
- **GPL note:** linking Stockfish into the app binary means the app must be GPL-3 if it is ever distributed. This is the single largest contamination risk in the stack.

### Weak / human-like opponents
| Option | How | Range | Notes |
|---|---|---|---|
| Stockfish `UCI_LimitStrength` + `UCI_Elo` | UCI options | **1320 → 3190**, calibrated at 60s+0.6s against CCRL 40/4 ([ref](https://cdn.jsdelivr.net/npm/capacitor-stockfish-variants@2.0.0/stockfish/Readme.md)) | Overrides `Skill Level`. Too strong for beginners. Its errors are random blunders, not human-like ones. Below 1320 you need `Skill Level 0–20` plus a short movetime, or custom random-move injection. |
| **Maia-1** ([CSSLab/maia-chess](https://github.com/CSSLab/maia-chess), 1.3k stars, **GPL-3**) | lc0 weights `maia-1100.pb.gz` … `maia-1900.pb.gz` (~1.2 MB each) run by **lc0** with `nodes=1` | 1100–1900 in 100 steps | Tiny nets, so on-device is easy *if* lc0 runs. chesskit-engine already bundles **Lc0 0.31.1** (CPU/Eigen backend), so Maia-1 on iPhone works by passing a weights file. One-node policy inference is cheap on CPU. Weights are GPL-3. |
| **Maia-2** ([CSSLab/maia2](https://github.com/CSSLab/maia2), 158 stars, **MIT**) | PyTorch. One unified model conditioned on `active_elo` and `opponent_elo` | Continuous Elo | **MIT is the cleanest license of all human-like models.** No lc0 needed. ONNX exports of ~<100 MB circulate ([maia2-rapid on HF](https://huggingface.co/shermansiu/maia2-rapid), [Lichess blog on ONNX integration](https://lichess.org/@/HollowLeaf/blog/integrating-maia2-the-human-like-chess-engine-into-my-chess-application/zi3EhDn5)). Convert with **coremltools** (PyTorch to CoreML) for on-device use. The README now says "for new projects, see Maia-3". |
| **Maia-3** ([CSSLab/maia3](https://github.com/CSSLab/maia3), 195 stars, **AGPL-3**) | "Chessformer" transformer with 3M/5M/23M/79M params and UCI options `Elo/SelfElo/OppoElo` | Continuous | Most accurate. [bqrio/maia3-onnx](https://huggingface.co/bqrio/maia3-onnx): 5M fp16 = **10.8 MB**, 23M fp16 = 45.8 MB. Inputs are `[B,64,12]` board tokens plus 2 ratings. Outputs are 4352 move logits plus WDL. **AGPL weights**, so this is the worst license for a distributed closed app. Fine for personal use or on the home PC. |

**Recommendation:** for the bot, use **Maia-2 via CoreML** (MIT, continuous Elo, human mistakes) when on device. Use **Stockfish UCI_Elo** for the "strong" bot levels. Maia-1 through chesskit-engine's lc0 is the zero-conversion fallback, but it is GPL.

**Lc0 + Metal on iOS:** upstream lc0 has a Metal backend for macOS (Apple Silicon). The chesskit-engine iOS build is CPU/Eigen only. A Flutter `lc0` plugin (v0.32.1, CPU-only) also exists. Do not count on GPU lc0 on iPhone. Full-strength Lc0 analysis belongs on the PC.

---

## 3. Board UI options

| Option | License | Pros | Cons |
|---|---|---|---|
| **Custom SwiftUI board** on chesskit-swift (ZStack of squares + `matchedGeometryEffect` / `withAnimation` for slides + a `Canvas` overlay for arrows/circles) | yours | Full control for a chess.com-identical feel: drag with ghost piece, click-click, premove queue, right-drag arrows, highlight colors, haptics. No GPL. | You build it (~1–2k LOC). |
| [rohanrhu/ChessboardKit](https://github.com/rohanrhu/ChessboardKit) (75★, MIT, iOS 17+) | MIT | Drag/drop and tap, slide animations, legal-move highlights, promotion picker, FEN, flip, `ChessboardColorScheme` protocol | No arrows and no premoves documented. Depends on aperechnev/ChessKit (module-name clash with chesskit-swift). Best used as **reference code or a fork**, not a dependency. |
| [lichess-org/chessground](https://github.com/lichess-org/chessground) in WKWebView | **GPL-3** (1.4k★, pushed 2026-10-14) | Battle-tested arrows (`drawable.autoShapes`), premoves, drag, animations, and a `brushes` API | **GPL-3**, so bundling the JS in a distributed app makes the app GPL. The WKWebView bridge adds latency and gesture conflicts and does not feel native. Its *design* is a good spec to imitate. |
| SpriteKit board | — | Particle effects | Overkill. SwiftUI + Canvas handles 60/120 fps animations for 32 sprites. |

**Arrows/highlights API to design (modeled on chessground's concepts, implemented natively):**
- `Shape { orig: Square; dest: Square?; brush: .green/.red/.blue/.yellow }`. Right-drag draws an arrow and right-tap draws a circle. Modifiers pick the color: chess.com uses Shift/Ctrl/Alt variants, and on iOS use a long-press palette.
- `autoShapes` for engine best move and coach hints, separate from user shapes.
- `lastMove`, `check`, `selected`, `premoveDests` square overlays.

---

## 4. Assets resembling chess.com (legally)

**Legal line:** chess.com's piece art ("Neo", "Neo-Wood"…), board textures and sounds are proprietary. Do **not** hot-link or bundle `chess.com/chess-themes/...` PNG/MP3s. Board *colors* (facts), layout, and interaction design (trade dress is a risk only if you also copy branding/logos) can be imitated with your own or openly licensed assets.

### Board colors
- Commonly cited "chess.com green": light **#EEEED2**, dark **#769656**. One recent design-spec scrape gives **#EBECD0 / #779556** ([webdesignhot design-md](https://www.webdesignhot.com/api/design-md/chess-com/claude.md)). Use either. They differ by about 1 RGB step.
- Last-move highlight: yellow overlay at ~50% alpha (`rgba(255,255,0,0.5)`). On green this produces the familiar **~#F6F669 (light) / ~#BACA2B (dark)** squares. Verify with the eyedropper and treat it as a tunable token.
- Arrows: chess.com uses semi-opaque orange-yellow (#FFAA00 at ~80%). Lichess brushes are green #15781B, red #882020, blue #003088, yellow #E68F00.

### Piece sets (from [lila COPYING.md](https://github.com/lichess-org/lila/blob/master/COPYING.md))
| Set | Author | License | Usable in a distributed closed app? |
|---|---|---|---|
| **cburnett** | Colin M.L. Burnett | Lichess lists GPLv2+, but the **Wikimedia originals are quad-licensed GFDL / CC BY-SA 3.0 / BSD / GPLv2+** ([File:Chess_klt45.svg](https://commons.wikimedia.org/wiki/File:Chess_klt45.svg)) | **Yes, under the BSD option** (take the SVGs from Commons and keep the notice) |
| **chessnut** | Alexis Luengas | Apache-2.0 | Yes |
| **fantasy / spatial / celtic** | Maurizio Monge | MIT | Yes |
| **rhosgfx** | RhosGFX | CC0 | Yes |
| kiwen-suwi, firi, totoy, papercut | various | CC BY 4.0 | Yes (attribution) |
| shapes | flugsio | CC BY-SA 4.0 | Yes, but SA applies to the art |
| merida, mono, mpchess | — | GPL v2+/v3+ | GPL |
| letter, pirouetti, pixel | — | AGPLv3+ | AGPL |
| **cardinal, staunty, maestro, california, horsey, tatiana, gioco, fresca, icpieces, dubrovny, caliente, anarcandy, monarchy, cooke…** | sadsnake1 et al. | **CC BY-NC-SA 4.0** | **No** (non-commercial). Personal use only. |
| alpha, chess7, companion, leipzig, riohacha, reillycraig, shahi-ivory-brown | — | non-free | No |

"Neo-like" look: none of the open sets is a Neo clone. The closest feel (chunky, soft-shaded, modern) comes from **staunty / cardinal / maestro (NC-only)**. Among permissive sets, **chessnut (Apache)** and **cburnett (BSD)** are the safe defaults. A long-term option is commissioning or AI-assisting your own Neo-*inspired* set (not traced).

### Sounds
Lichess sound sets ([lila COPYING.md](https://github.com/lichess-org/lila/blob/master/COPYING.md)):
- **standard, robot, woodland, instrument, other**: **non-free** (unlisted means all rights reserved). The default "standard" set is the one people recognize, and it is not reusable.
- **sfx, nes, piano, futuristic** by Enigmahack: **AGPLv3+**. Shipping AGPL audio in a distributed app is the same as GPL contamination for the asset files.
- **lisp** by EdinburghCollective: **CC BY-NC-SA 4.0** (non-commercial).
- Files per set (e.g. `public/sound/sfx/`): `Move, Capture, Check, Checkmate, Confirmation, CountDown0–10, Defeat, Draw, Victory, Error, Explosion, GenericNotify, LowTime, NewChallenge, NewPM, OutOfBound, Berserk, Tournament1st/2nd/3rd/Other` (mp3 + ogg). **Lichess has no separate castle, promote, premove or illegal sounds** (castle uses Move).

chess.com's event set, which is the target UX to replicate: `move-self`, `move-opponent`, `capture`, `castle`, `move-check`, `promote`, `premove`, `illegal`, `notify`, `tenseconds` (low time), `game-start`, `game-end`, plus puzzle correct/wrong. (These names come from chess.com's public asset paths. Do not ship their files.)

**Permissive sources to fill all events:** Freesound CC0 chess clips, e.g. el_boss "Piece Placement / Piece Slide / Piece Capture" and "Chess Puzzle Blitz SFX" (CC0, [soundspool listing](https://soundspool.com/tags/chess)). Also **Kenney.nl "Interface Sounds" / "Impact Sounds"** (CC0) for notify, illegal and low-time. Alternatively, record two wood blocks with an iPhone and process them yourself. You own those, and it is the closest route to the chess.com "wooden thock". Recommended: record or own `move`, `capture`, `castle` (two quick clicks), `check`, and `promote`. Use Kenney CC0 for the UI chimes.

---

## 5. Data

| Dataset | License | Size / shape | Use |
|---|---|---|---|
| **Lichess puzzles** [database.lichess.org](https://database.lichess.org/#puzzles) | **CC0** | **6,157,341 puzzles** (Oct 2026). `lichess_db_puzzle.csv.zst`, roughly 250–300 MB compressed and ~1 GB CSV. Columns: `PuzzleId, FEN, Moves, Rating, RatingDeviation, Popularity, NbPlays, Themes, GameUrl, OpeningTags, DailyDate`. `Moves[0]` is the opponent's move and the puzzle starts after it. Theme names and descriptions are in lila's `translation/source/puzzleTheme.xml`. | Ship a curated subset on device (e.g. 50–100k puzzles across rating bands and themes, ~10–20 MB in SQLite). Keep the full set on the PC. |
| **Lichess eval DB** | CC0 | **416M positions** with SF multi-PV (JSONL) | PC-side lookup cache, which avoids re-analysing common positions. |
| **lichess-org/chess-openings** [repo](https://github.com/lichess-org/chess-openings) (568★, pushed 2026-10-06) | **CC0** | `a.tsv`…`e.tsv` (ECO volumes) with columns `eco, name, pgn`. `make` (python-chess) builds the `uci` and `epd` columns. ~3.5k named lines. | On-device opening naming and "Book" move detection: look up EPD after each move. This also supplies **ECO codes**. |
| **Lichess Opening Explorer API** (`explorer.lichess.ovh/{masters,lichess,player}`) | data free, service ToS | **Since 2026 it requires a (free, scope-less) Personal API Token** ([forum](https://lichess.org/forum/lichess-feedback/why-this-change-using-the-opening-explorer-now-requires-being-logged-in)). Server: [lila-openingexplorer](https://github.com/lichess-org/lila-openingexplorer) (AGPL). | Use online when connected, with cache. Rate rule for all Lichess APIs: **one request at a time; on 429 wait 60 s** ([lichess.org/api](https://lichess.org/api)). |
| **Lichess tablebase API** `tablebase.lichess.ovh/standard?fen=` | free service | Up to 7-man (Syzygy + op1) | Online endgame truth. |
| **Syzygy on device** | data (free) | **3-4-5-man = 939 MiB** (WDL 378 MiB + DTZ 562 MiB). **6-man = 149 GiB** ([chessprogramming](https://www.chessprogramming.org/Syzygy_Bases)) | A 3-4-5 **WDL-only** set (378 MiB) is possible as an optional download but probably not worth it. Use the API and the PC instead. Probing code: Fathom (MIT) or Stockfish's built-in `SyzygyPath`. |
| **Polyglot books** (`.bin`) | varies by book | e.g. `gm2001.bin`, `Perfect2023.bin`, Cerebellum (large). python-chess `chess.polyglot` reads them. | A bot opening book for variety (Maia already plays human openings). Prefer generating your own book from Lichess CC0 games with python-chess to avoid license ambiguity. |

---

## 6. Chess.com Published-Data API ([docs](https://www.chess.com/news/view/published-data-api))

- **No auth.** It is read-only public data.
- Endpoints:
  - `GET https://api.chess.com/pub/player/{username}` returns the profile
  - `GET …/player/{username}/stats` returns ratings per `chess_rapid|blitz|bullet|daily`, plus tactics and puzzle-rush stats
  - `GET …/player/{username}/games/archives` returns a list of monthly archive URLs
  - `GET …/player/{username}/games/{YYYY}/{MM}` returns JSON `games[]`
  - `GET …/player/{username}/games/{YYYY}/{MM}/pgn` returns multi-game PGN
- Game object fields: `url, pgn, time_control, end_time, rated, tcn, uuid, initial_setup, fen, time_class, rules, white{rating,result,username,@id,uuid}, black{…}, eco` (an opening URL), and **`accuracies{white,black}` only when the game has been reviewed on chess.com**. **Clocks:** the PGN carries `{[%clk 0:02:59.9]}` per move, and you parse them for time-use coaching.
- **Rate limits:** "serial access rate is unlimited". Wait for each response before sending the next and you will not be limited. **Parallel requests may get `429`.**
- **Etiquette:** send a **descriptive `User-Agent` with contact info** (e.g. `ChessCoachApp/0.1 (contact: you@example.com)`) so they can contact you rather than block you.
- **Caching:** responses carry `ETag`/`Last-Modified`, so use `If-None-Match`. Data refreshes **at most every 12 h**. The current month's archive changes and past months are immutable, so cache them permanently.
- Note: the `accuracies` field uses chess.com's proprietary CAPS2 metric. Show it when present, but compute your own Lichess-style accuracy for every game for consistency.

---

## 7. Game-review / move-classification implementations

| Repo | Stars | Last push | License | What to take |
|---|---|---|---|---|
| [WintrCat/freechess](https://github.com/WintrCat/freechess) | 841 | 2025-08-02 | **CC BY-NC-SA 4.0** (LICENSE file; GitHub shows NOASSERTION) | The original "chess.com Game Review clone" (TypeScript): Brilliant/Great/Best/Excellent/Good/Inaccuracy/Mistake/Blunder/Book/Forced. **NC license, so read for ideas only.** |
| [WintrCat/wintrchess](https://github.com/wintrcat/wintrchess) | 262 | 2026-04-24 | **GPL-3** | Successor. Has Brilliant/Critical/Best/Excellent/Okay/Inaccuracy/Mistake/Blunder/Miss/Theory. On a benchmark it caught 45/100 chess.com brilliants with 73% precision ([chessigma](https://www.chessigma.com/benchmarks/brilliant)). |
| [WintrCat/wintrchess-lib](https://github.com/WintrCat/wintrchess-lib) | 32 | 2026-04-25 | **AGPL-3** | Library form. |
| [GuillaumeSD/Chesskit](https://github.com/GuillaumeSD/Chesskit) (web, unrelated to chesskit-app) | 428 | 2026-05-08 | **AGPL-3** | Clean win%-based classifier (Splendid/Perfect/Best/Excellent/Okay/Inaccuracy/Mistake/Blunder/Opening/Forced). |
| [franciscoBSalgueiro/en-croissant](https://github.com/franciscoBSalgueiro/en-croissant) | 1.9k | 2026-10-15 | GPL-3 | Desktop toolkit (Tauri) with annotations. |
| [T-Julsgaard/Chess-Review](https://github.com/T-Julsgaard/Chess-Review) | 17 | 2026-10-14 | GPL-3 | Small and active. |

All are GPL/AGPL/NC. **Re-implement in Swift from the formulas below** and do not port the code.

### Exact Lichess formulas (from lila source, [accuracy page](https://lichess.org/page/accuracy))
```
// cp from side-to-move's POV is converted to White POV; cp clamped to [-1000, 1000]
WinPercent(cp) = 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1)
// mate: lichess converts mate to a large cp before clamping (effectively 0% / 100%)

// per-move accuracy, from mover's POV (winBefore, winAfter in 0..100)
if winAfter >= winBefore: acc = 100
else:
  acc = 103.1668100711649 * exp(-0.04354415386753951 * (winBefore - winAfter))
        - 3.166924740191411
  acc = clamp(acc + 1, 0, 100)        // "+1 uncertainty bonus"

// game accuracy per colour (AccuracyPercent.scala)
windowSize = clamp(numPositions / 10, 2, 8)
windows    = sliding windows of WinPercent over the game (padded at start)
weight_i   = clamp(stddev(window_i WinPercents), 0.5, 12)
weighted   = Σ(acc_i * weight_i) / Σ(weight_i)
harmonic   = n / Σ(1 / acc_i)
gameAcc    = (weighted + harmonic) / 2
```
Lichess's own judgments use the drop in win chances (on the ±1 scale, `2/(1+e^{-0.00368208·cp})−1`): **Inaccuracy ≥ 0.1, Mistake ≥ 0.2, Blunder ≥ 0.3**. That equals 5 / 10 / 15 points of Win%.

### chess.com classification thresholds (publicly described, Expected-Points model)
Expected points: 1.0 = winning, 0.5 = equal, 0 = losing. Points lost per move:
**Best = engine top move · Excellent 0.00–0.02 · Good 0.02–0.05 · Inaccuracy 0.05–0.10 · Mistake 0.10–0.20 · Blunder 0.20–1.00** ([support article](https://support.chess.com/en/articles/8584089-how-does-game-review-work), [summary](https://chessgrader.com/blog/chess-move-classifications/)).
Using WinPercent/100 as expected points gives a faithful clone.
- **Book**: the position's EPD is in chess-openings or masters explorer.
- **Forced**: only one legal move.
- **Miss**: the opponent's previous move was a mistake or blunder, and your move failed to punish it. That is, best-move win% after their error minus your-move win% is ≥ the Mistake threshold, while you did not lose much relative to the pre-error position.
- **Great**: the only move that keeps the result. Best-move expected points minus second-best is ≥ ~0.10–0.15 (MultiPV 2 required), or it is the only move after an opponent's error that wins.
- **Brilliant**: a Best/Great move that **sacrifices material** (a piece left en prise, or a capture into a losing exchange, that SEE says is hanging, excluding pawns, recaptures and promotions). The position afterward must be ≥ ~50% for you and must not be already completely winning without it. WintrChess and freechess use: `winningAnyways = secondBest ≥ +700cp`. GuillaumeSD uses: not losing and the alternative ≤ 97%.

Reference: freechess's cp-loss thresholds are quadratic in |prevEval|, e.g. `Excellent ≤ 0.0002·e² + 0.1231·e + 27.55` cp. They are readable in `src/lib/classification.ts`, but the license is NC, and the win%-based approach above is cleaner anyway.

---

## 8. LLM chess-coach projects and chess MCP servers

### Coach pipelines (Stockfish → features → LLM)
| Repo | Stars | Last push | License | Idea |
|---|---|---|---|---|
| [armandlance/gambit](https://github.com/armandlance/gambit) | 0 | 2026-10-05 | MIT | LLM explains, **Stockfish verifies**, python-chess fact-checks every claimed move. Includes LoRA fine-tune and a FastAPI demo. **Best architectural match.** |
| [andrewnakas/ChessGpt](https://github.com/andrewnakas/ChessGpt) | 0 | 2026-10-05 | AGPL-3 | Rating-aware explanations via MCP. Every move mentioned is engine-checked. |
| [Iamsdt/chess](https://github.com/Iamsdt/chess) | 30 | 2026-10-12 | none (all rights reserved) | SF18 + LLM browser trainer. Look only. |
| [ai-chess-training/LLM-ChessCoach](https://github.com/ai-chess-training/LLM-ChessCoach) | 6 | 2026-03-27 | MIT | Imports games, coaches move by move. |
| [akmenon1996/LLM-ChessCoach](https://github.com/akmenon1996/LLM-ChessCoach) | 4 | 2025-07-19 | MIT | Fetches site games and gives LLM advice. |
| Canvas-open/ai-chess-coach | — | — | — | Modular engine/feature-parser/LLM design (repo now 404/private). |

Common lessons from these:
1. **Never let the LLM compute chess.** Feed it a structured fact sheet: eval before and after, best line in SAN, threats (python-chess `attackers`, hanging pieces via SEE), material, pawn-structure flags, king safety, the motif tags (fork/pin/skewer/discovered attack, which can be computed the way Lichess puzzle themes are), and the opening name.
2. **Post-validate:** parse every SAN in the LLM output and check it is legal and appears in the engine PV. Regenerate otherwise.
3. Condition on the player's rating.

**Stockfish `eval` command caveat:** since **SF16 (June 2023) the classical hand-crafted evaluation was removed**. The `eval` trace no longer lists Material/Mobility/King-safety/Threats/Passed terms. It prints the **NNUE per-piece contribution board** (the value of removing each piece) and the bucketed NNUE output. Per-piece contributions are still useful ("your knight on f5 is worth +1.8"). For human concept terms, compute them yourself in python-chess, or use an older SF15.1 binary on the PC purely as a "concept annotator" (`eval` there prints the classical term table). SF15.1 is GPL, server-side only, so this is fine.

### Chess MCP servers (useful as a server-side tool layer for the PC LLM)
| Repo | Stars | Last push | License | Features |
|---|---|---|---|---|
| [karayaman/lichess-mcp](https://github.com/karayaman/lichess-mcp) | 18 | 2026-10-12 | MIT | Lichess account, play, analyze |
| [turlockmike/chess-mcp](https://github.com/turlockmike/chess-mcp) | 19 | 2025-02-04 | MIT | General chess tools |
| [parkseokjune/chess-coach-mcp](https://github.com/parkseokjune/chess-coach-mcp) | 4 | 2026-10-15 | MIT | **Local Stockfish + Lichess/Chess.com import, weakness diagnosis, drills.** Closest to this app's goals. |
| [alegerber/stockfish-lc0-mcp](https://github.com/alegerber/stockfish-lc0-mcp) | 2 | 2026-09-23 | MIT | TS: Stockfish + Lc0 analysis, opening DB, puzzle generation, Docker |
| [realsidg/chess_mcp](https://github.com/realsidg/chess_mcp) | 2 | 2026-07-21 | MIT | Stockfish, Chess.com + Lichess APIs, board render |
| [wilson-urdaneta/chesspal-mcp-engine](https://github.com/wilson-urdaneta/chesspal-mcp-engine) | 5 | 2025-04-24 | GPL-3 | Stockfish MCP |
| [cigizeta/aio64](https://github.com/cigizeta/aio64) | 0 | 2026-10-12 | AGPL-3 | Lichess + Claude + Stockfish with board widget |
| [shelajev/mcp-lichess](https://github.com/shelajev/mcp-lichess) | 0 | 2025-07-01 | Apache-2.0 | Spring Boot, builds SF + lc0 |

All are young and low-star. Treat them as reference implementations. A ~200-line FastMCP server over python-chess + Stockfish on the PC is easier to own than any of these.

---

## 9. On-device LLMs on iOS

| Option | License | Feasibility for chess explanations |
|---|---|---|
| **Apple Foundation Models** (iOS 26+) | system API | ~3B on-device model, **4096-token context per session** ([TN3193](https://developer.apple.com/tutorials/data/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window.md)). iOS 26.4 adds `contextSize` and `tokenCount(for:)`. Has `@Generable` guided generation (typed Swift structs) and **Tool calling**. Needs an A17 Pro/M1 or newer with Apple Intelligence enabled. **Good fit** for "turn this fact sheet into 2–3 sentences at a 1200 level", since the facts come from the engine and the model only phrases them. A tool can expose `evaluate(fen)`/`bestLine(fen)`. Weak at chess reasoning on its own, so never ask it to find moves. **The app targets iOS 17**, so gate this behind `if #available(iOS 26, *)` and fall back to templates or the PC. |
| [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) (2.1k★, MIT, pushed 2026-10-15) + [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) (2.7k★, MIT) `MLXLLM` | MIT | Runs 4-bit Qwen/Llama/Gemma 1–4B from HF on Metal. A 3–4B 4-bit model needs ~2–2.5 GB of RAM, which needs the `increased-memory-limit` entitlement on 6–8 GB iPhones. Model download is 1–2.5 GB. Works, but heavy. |
| [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) (131k★, MIT) via [LLM.swift](https://github.com/eastriverlee/LLM.swift) (882★, MIT) / [SpeziLLM](https://github.com/StanfordSpezi/SpeziLLM) (291★, MIT) / [SwiftLlama](https://github.com/ShenghaiWang/SwiftLlama) (99★, MIT) | MIT | GGUF + Metal, with similar sizes and speed. Grammar-constrained JSON is available. |
| [mlc-ai/mlc-llm](https://github.com/mlc-ai/mlc-llm) (23k★, Apache-2.0) | Apache | Compiled models with an iOS SDK. More build friction. |

**Verdict:** for offline mode use **templated explanations** (deterministic from motif tags) as the floor, **Foundation Models** on iOS 26 devices as the first upgrade, and the **home-PC LLM** for deep "why" questions. Bundling MLX or llama.cpp models is only worth it if FM quality proves insufficient.

---

## 10. Server side (home PC, Windows, Python)

- **[python-chess](https://github.com/niklasf/python-chess)** (2.9k★, pushed 2026-08-22, **GPL-3**): rules, PGN/FEN/SAN, async UCI engine control (`chess.engine.popen_uci`, `analyse(multipv=…)`), Polyglot reading, Syzygy/Gaviota probing, SVG rendering. GPL is fine because it is a server process and not distributed. It is the backbone for the analysis service.
- **Stockfish 19** native Windows build (`sf_19`, 2026-09-05). Choose the `x86-64-avx2` or `bmi2` build to match the CPU. Use Hash 1–4 GB, Threads = cores−1, MultiPV 3 for classification.
- **Lc0 v0.32.1** (2025-11-23, GPL-3) on the **GTX 980 Ti (Maxwell, compute capability 5.2)**. Lc0 0.32 ships CUDA 12 builds. CUDA 12.x still supports sm_52 (deprecated, and removed in CUDA 13). If the prebuilt `cudnn`/`cuda` backend refuses the card, use the **`onnx-dml` (DirectML) build** on Windows or rebuild with `-arch=sm_52`. Expect low thousands of nps with large nets. That is plenty for **Maia (nodes=1)**, which is the main reason to run lc0 there.
- **Maia-2 (MIT) / Maia-3 (AGPL, server-only is fine)** in PyTorch. Maxwell supports CUDA in recent PyTorch only via older wheels, because current PyTorch CUDA 12.x wheels dropped sm_5x in 2.5+. Practical options: **run Maia-2/3 on CPU** (5M-param Maia-3 is designed for CPU), or use ONNX Runtime with the DirectML EP on the 980 Ti.
- Optional: the **fishnet** pattern ([lichess-org/fishnet](https://github.com/lichess-org/fishnet), GPL-3) is a good queue design reference for batch-analysing imported game archives.
- LLM: local via Ollama/llama.cpp on CPU+980 Ti (6 GB VRAM fits a 7–8B Q4), or Claude API, behind the same fact-sheet-plus-verify pipeline.

---

## Recommended stack

| Component | Library / asset | License | Why |
|---|---|---|---|
| Rules, FEN/PGN/SAN, variations | **chesskit-swift** | MIT | Best-maintained Swift chess lib, bitboards, MoveTree |
| Board UI | **Custom SwiftUI board** (ChessboardKit as MIT reference) | own / MIT | Exact chess.com feel (premoves, arrows, ghost drag). Avoids chessground GPL and the module clash. |
| Arrow/highlight model | own, modeled on chessground concepts | own | Concepts are not copyrighted |
| On-device engine | **Stockfish 17 via chesskit-engine** (small net 3.5 MB bundled, big net 75 MB on demand) | **GPL-3** (wrapper MIT) | Only practical strong iOS engine. Isolate it behind an `EngineProvider` protocol. |
| Human-like bot | **Maia-2 → CoreML** (on device); Stockfish UCI_Elo for 1320+ | **MIT** / GPL-3 | Maia-2 has the cleanest license and continuous Elo |
| Bot fallback | Maia-1 nets via chesskit-engine lc0 | GPL-3 | Zero conversion work |
| Pieces | **cburnett (BSD option, from Commons)** + **chessnut (Apache)**, with staunty/cardinal for personal-only builds | BSD / Apache / (NC) | Permissive. The NC sets are the closest to Neo. |
| Board colors | #EEEED2 / #769656, yellow 50% last-move overlay | facts | chess.com look |
| Sounds | Self-recorded wood + Freesound CC0 (el_boss) + Kenney CC0 | own / CC0 | Lichess "standard" is non-free and its others are AGPL/NC |
| Puzzles | Lichess puzzle CSV subset in SQLite | CC0 | 6.16M puzzles with themes |
| Openings / ECO / Book | lichess-org/chess-openings | CC0 | Opening names + Book detection |
| Explorer / tablebase | Lichess APIs (token for explorer; serial, 429 means 60 s) | service | Online enrichment |
| Game import | chess.com PubAPI (serial, UA w/ contact, ETag) + Lichess export API | public | Monthly archives with `%clk` |
| Review / accuracy | **own Swift implementation** of Lichess win%/accuracy + chess.com EP thresholds | own | All reference impls are GPL/AGPL/NC |
| On-device LLM | Apple Foundation Models (iOS 26 gated) → template fallback | system | 4k ctx is enough for fact-sheet phrasing |
| PC analysis | python-chess + Stockfish 19 + Lc0/Maia (CPU or DirectML on the 980 Ti) | GPL-3 / MIT / AGPL (server-only) | Not distributed, so no contamination |
| PC tool layer | Own FastMCP server (ref: chess-coach-mcp, stockfish-lc0-mcp) | own | Easier to own than young repos |
| Coach pipeline | Fact sheet → LLM → SAN legality + PV verification (gambit pattern) | own / MIT ref | Prevents hallucinated moves |

## GPL / license risk list

1. **Stockfish (GPL-3) linked into the iOS app.** This is the big one. It is fine for personal use. To distribute, either open-source the whole app under GPL-3 (and accept the App Store GPL debate) or drop on-device SF and analyse on the PC or a server.
2. **Lc0 (GPL-3) inside chesskit-engine**: same issue. Maia-1 weights are also GPL-3.
3. **Maia-3 weights and code (AGPL-3)**: do not bundle them in a distributed app. They are fine on the private PC.
4. **chessground (GPL-3)**: do not embed it in a WKWebView in a distributable build.
5. **Lichess sounds**: "standard/robot/woodland" are **non-free**, sfx/nes/piano/futuristic are **AGPL**, and lisp is **NC**. Do not ship any of them.
6. **Lichess piece sets**: most of the attractive modern ones are **CC BY-NC-SA** (cardinal, staunty, maestro…). Use them in personal builds only. merida/mono/mpchess are GPL and letter/pixel/pirouetti are AGPL.
7. **Review clones**: freechess is **CC BY-NC-SA**, wintrchess is GPL-3, wintrchess-lib and GuillaumeSD/Chesskit are AGPL-3, en-croissant is GPL-3. Re-implement from formulas and never port code.
8. **python-chess (GPL-3)**: server-only, so OK. Do not port it into the iOS app.
9. **chess.com assets** (Neo pieces, sounds, board textures, logos): proprietary. Imitate the look and do not copy files.
10. **Iamsdt/chess has no license** (all rights reserved). Read only.
11. **The MIT wrapper does not launder GPL**: chesskit-engine's MIT label covers only the Swift wrapper, while the compiled engine inside it is GPL-3.
