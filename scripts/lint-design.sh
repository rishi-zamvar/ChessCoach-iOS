#!/bin/bash
# Design-system guard (spec W9): screens use Palette / Typography / Spacing tokens, never literals.
# Errors: raw colours and fixed font sizes outside DesignSystem/ and Board/ (the board scales its own glyphs).
# Warnings: numeric corner radii and paddings (counted, not failed).
set -uo pipefail
cd "$(dirname "$0")/.."
SRC=ChessCoach
errors=$(grep -rnE 'Color\((red|hex|white):|Color\(\.sRGB|UIColor\(red:|\.system\(size:|Font\.custom\(' "$SRC" \
  --include='*.swift' | grep -vE "^$SRC/(DesignSystem|Board)/" || true)
warnings=$(grep -rnE 'cornerRadius: *[0-9]|\.padding\([0-9]' "$SRC" --include='*.swift' | grep -vE "^$SRC/(DesignSystem|Board)/" | wc -l | tr -d ' ')
if [ -n "$errors" ]; then
  echo "Design lint: use Palette / Typography tokens instead of:"
  echo "$errors"
  exit 1
fi
echo "Design lint passed (${warnings} numeric radius/padding literals left to tokenise)."
