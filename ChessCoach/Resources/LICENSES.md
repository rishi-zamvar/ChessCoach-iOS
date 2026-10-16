# Third-party assets

## Piece sets (`Assets.xcassets/<set>/<color><kind>`)
Fetched from lichess-org/lila `public/piece/<set>/`.

| Set | Author | License |
|---|---|---|
| staunty | sadsnake1 | CC BY-NC-SA 4.0 — personal / non-commercial use only |
| cardinal | sadsnake1 | CC BY-NC-SA 4.0 — personal / non-commercial use only |
| maestro | sadsnake1 | CC BY-NC-SA 4.0 — personal / non-commercial use only |
| cburnett | Colin M.L. Burnett | GPLv2+ / GFDL / BSD (tri-licensed via Wikimedia Commons; we use the BSD option) |

The NC sets mean this build must not be distributed commercially. cburnett is the
permissive fallback.

## Engines and networks (`Resources/Engines`, via ChessCoachKit)
- Stockfish and its NNUE nets — GPL-3.0
- Lc0 (Leela Chess Zero) — GPL-3.0
- Maia weights (maia-1100) — GPL-3.0

## Sounds (`Resources/Sounds`)
Generated in-house by `scripts/make_sounds.py` (synthesized). No third-party audio.

## Puzzles (`Resources/puzzles.sqlite`)
- Lichess puzzle database (built by `scripts/build_puzzles.py`) — CC0, attribution https://database.lichess.org
