#!/bin/bash
set -e

IP="IP"
APP="BEERUS Framework"
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="ssh -o ControlMaster=auto -o ControlPath=/tmp/beerus-ssh -o ControlPersist=60"
DERIVED="$DIR/build/DerivedData"
OUT="$DERIVED/Build/Products/Release-iphoneos"

# Build (incremental — pass 'clean' as arg to force full rebuild)
if [ "${1:-}" = "clean" ]; then rm -rf "$DERIVED"; fi
xcodebuild build -project "$DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -arch arm64 -sdk iphoneos -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    2>&1 | tee /tmp/beerus-build.log | tail -5
if ! grep -q "BUILD SUCCEEDED" /tmp/beerus-build.log; then
    echo "BUILD FAILED"; exit 1
fi

FWDIR="$OUT/$APP.app/Frameworks"
if [ -d "$FWDIR" ]; then
    for f in "$FWDIR"/*.framework; do
        [ -d "$f" ] && rm -rf "$f"          # remove bundled .framework dirs
    done
fi

# Sign main binary + any embedded dylibs
if command -v ldid &>/dev/null; then
    ldid -S"$DIR/$APP/Entitlements.plist" "$OUT/$APP.app/$APP"
    if [ -d "$FWDIR" ]; then
        for dylib in "$FWDIR"/*.dylib; do
            [ -f "$dylib" ] && ldid -S "$dylib"
        done
    fi
fi

# Install
$SSH "root@$IP" "rm -rf '/Applications/$APP.app'"
scp -o ControlPath=/tmp/beerus-ssh -qr "$OUT/$APP.app" "root@$IP:/Applications/"
$SSH "root@$IP" "chown -R root:wheel '/Applications/$APP.app' && chmod -R 755 '/Applications/$APP.app' && uicache -p '/Applications/$APP.app' && killall -9 SpringBoard"

echo "Installed - device will respring"
