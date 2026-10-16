# ChessCoach

A personal iOS chess coach. Plays, reviews and trains fully offline; calls Claude when online; uses a home PC over Tailscale as an accelerator.

- **Today · Analyze · Train · Play** — WorkoutCoach-style app shell, chess.com-style game screen.
- **Engines on device:** Stockfish 17 and Lc0 running Maia-1 (human-like play) via [chesskit-engine](https://github.com/chesskit-app/chesskit-engine).
- **Rule:** the engine and deterministic code decide what is true; AI only explains.

Design: [`docs/superpowers/specs/2026-10-15-chess-coach-design.md`](docs/superpowers/specs/2026-10-15-chess-coach-design.md) · Research: [`docs/research/`](docs/research/) · Plans: [`docs/superpowers/plans/`](docs/superpowers/plans/)

## Build

```sh
scripts/fetch-engine-assets.sh   # Stockfish NNUE nets + Maia weights (not committed)
xcodegen generate
open ChessCoach.xcodeproj
```

Logic lives in `Packages/ChessCoachKit` (`swift test` runs on macOS).

## Licensing

Personal project. Bundles GPL-3 engines (Stockfish, Lc0, Maia weights) at build time and CC BY-NC-SA piece sets — see [`ChessCoach/Resources/LICENSES.md`](ChessCoach/Resources/LICENSES.md). Not affiliated with chess.com; no chess.com assets are used.
