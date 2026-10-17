#!/bin/bash
# Records every coach line in Aman's voice (English, India) into the app bundle,
# so every phone hears Aman without downloading a voice. Re-run after changing CoachVoice lines.
# For the best quality, first download Aman (Enhanced/Premium) on this Mac:
# System Settings → Accessibility → Spoken Content → System voice → Manage Voices → English (India).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/ChessCoach/Resources/Voice"
LINES="$(mktemp)"
(cd "$ROOT/Packages/ChessCoachKit" && COACH_LINES_OUT="$LINES" swift test --filter test_dumpSpokenLines >/dev/null)
rm -rf "$OUT" && mkdir -p "$OUT"
export OUT
tr '\n' '\0' <"$LINES" | xargs -0 -P 8 -n 1 sh -c '
  name="${0%%	*}"; text="${0#*	}"
  say -v Aman -r 185 -o "$OUT/$name.aiff" "$text"
  afconvert -f m4af -d aac -b 32000 "$OUT/$name.aiff" "$OUT/coach-$name.m4a" && rm "$OUT/$name.aiff"'
echo "$(ls "$OUT" | wc -l | tr -d " ") clips, $(du -sh "$OUT" | cut -f1)"
