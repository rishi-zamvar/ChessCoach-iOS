#!/bin/bash
# Archive Release and upload to App Store Connect → TestFlight. Uses Xcode's signed-in Apple ID.
# Build number = git commit count, so every upload is unique and increasing.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=$(git rev-list --count HEAD)
OUT=build/testflight
rm -rf "$OUT" && mkdir -p "$OUT"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>373D7DZ9NM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
scripts/lint-design.sh
xcodegen generate -q
xcodebuild -project ChessCoach.xcodeproj -scheme ChessCoach -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$OUT/ChessCoach.xcarchive" -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" -quiet archive
xcodebuild -exportArchive -archivePath "$OUT/ChessCoach.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates
echo "Uploaded build $BUILD. It appears in TestFlight after Apple's processing (~10-15 min)."
