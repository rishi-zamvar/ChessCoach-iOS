#!/bin/bash
# Build Release and install on the paired iPhone — over USB or Wi-Fi (same network, phone unlocked).
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${CHESSCOACH_DEVICE:-E1F3A99A-C5EA-5F4A-BEF2-E85E318BA62D}"   # CoreDevice id (xcrun devicectl list devices)
UDID="${CHESSCOACH_UDID:-00008120-001660E63EE2601E}"                    # xcodebuild destination id
xcodegen generate -q
xcodebuild -project ChessCoach.xcodeproj -scheme ChessCoach -configuration Release \
  -destination "id=$UDID" -derivedDataPath build/device -allowProvisioningUpdates -quiet build
xcrun devicectl device install app --device "$DEVICE" build/device/Build/Products/Release-iphoneos/ChessCoach.app
xcrun devicectl device process launch --device "$DEVICE" com.rishizamvar.chesscoach
