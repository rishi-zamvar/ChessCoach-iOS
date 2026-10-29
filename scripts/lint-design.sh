#!/bin/bash
# Design-system guard (spec W9): screens use Palette / Typography / Spacing tokens, never literals.
# Fails on raw colours, fixed font sizes, and numeric corner radii / paddings outside
# DesignSystem/ and Board/ (the board scales its own glyphs and squares).
set -uo pipefail
cd "$(dirname "$0")/.."
SRC=ChessCoach
errors=$(grep -rnE 'Color\((red|hex|white):|Color\(\.sRGB|UIColor\(red:|\.system\(size:|Font\.custom\(|cornerRadius: *[0-9]|\.padding\([0-9]' "$SRC" \
  --include='*.swift' | grep -vE "^$SRC/(DesignSystem|Board)/" || true)
if [ -n "$errors" ]; then
  echo "Design lint: use Palette / Typography / Spacing tokens instead of:"
  echo "$errors"
  exit 1
fi
echo "Design lint passed."
