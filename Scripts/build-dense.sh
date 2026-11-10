#!/bin/bash
set -euo pipefail

DENSE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DENSE_BUILD="${1:-$DENSE_ROOT/.build/derived-data}"
DENSE_OUTPUT="${2:-$DENSE_ROOT/dist}"
mkdir -p "$DENSE_BUILD" "$DENSE_OUTPUT"
DENSE_BUILD="$(cd "$DENSE_BUILD" && pwd)"
DENSE_OUTPUT="$(cd "$DENSE_OUTPUT" && pwd)"
if [[ -e "$DENSE_OUTPUT/Stats Dense.app" ]]; then
    echo "Output already exists. Select a clean output directory; no app was overwritten." >&2
    exit 1
fi
DENSE_STAGE="$(mktemp -d "$DENSE_OUTPUT/.dense.XXXXXX")"
trap 'rm -rf -- "$DENSE_STAGE"' EXIT

cd "$DENSE_ROOT"
# Keep local source paths out of debug metadata and #file/__FILE__ strings.
printf -v DENSE_SWIFT_FLAGS '%s -file-prefix-map "%s" -debug-prefix-map "%s"' '$(inherited)' "$DENSE_ROOT=/Stats-Dense" "$DENSE_ROOT=/Stats-Dense"
printf -v DENSE_C_FLAGS '%s -ffile-prefix-map="%s"' '$(inherited)' "$DENSE_ROOT=/Stats-Dense"
xcodebuild -project Stats.xcodeproj -scheme Stats \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DENSE_BUILD" CODE_SIGNING_ALLOWED=NO \
    "OTHER_SWIFT_FLAGS=$DENSE_SWIFT_FLAGS" \
    "OTHER_CFLAGS=$DENSE_C_FLAGS" "OTHER_CPLUSPLUSFLAGS=$DENSE_C_FLAGS" \
    SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO build

DENSE_APP="$DENSE_STAGE/Stats Dense.app"
ditto "$DENSE_BUILD/Build/Products/Release/Stats.app" "$DENSE_APP"
# This local ad-hoc preview does not distribute the optional WidgetKit extension.
rm -rf -- "$DENSE_APP/Contents/PlugIns/WidgetsExtension.appex"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier eu.exelban.Stats.Dense' "$DENSE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleDisplayName' "$DENSE_APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Stats Dense' "$DENSE_APP/Contents/Info.plist"
codesign --force --deep --sign - "$DENSE_APP"
codesign --verify --deep --strict "$DENSE_APP"
mv "$DENSE_APP" "$DENSE_OUTPUT/Stats Dense.app"
cp LICENSE "$DENSE_OUTPUT/LICENSE"
cp Kit/lldb/LICENSE.txt "$DENSE_OUTPUT/LICENSE-LevelDB.txt"
cp NOTICE.md "$DENSE_OUTPUT/NOTICE.md"
echo "Built: $DENSE_OUTPUT/Stats Dense.app"
