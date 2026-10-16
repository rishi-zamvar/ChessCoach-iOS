#!/bin/bash
# Fetches the engine network files (not committed: 75 MB+). Idempotent.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/ChessCoach/Resources/Engines"
mkdir -p "$DIR"
fetch() { [ -s "$DIR/$1" ] || curl -sSLf -o "$DIR/$1" "$2"; }
fetch nn-1111cefa1111.nnue https://tests.stockfishchess.org/api/nn/nn-1111cefa1111.nnue
fetch nn-37f18f62d772.nnue https://tests.stockfishchess.org/api/nn/nn-37f18f62d772.nnue
fetch maia-1100.pb.gz https://github.com/CSSLab/maia-chess/raw/master/maia_weights/maia-1100.pb.gz
ls -la "$DIR"
