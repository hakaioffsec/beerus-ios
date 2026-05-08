#!/bin/bash
set -e

IP="192.168.0.205"
PORT="${SSH_PORT:-22}"
DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect rootless: check if /var/jb exists on device
ROOTLESS=$(ssh -p "$PORT" "root@$IP" '[ -d /var/jb ] && echo 1 || echo 0' 2>/dev/null)
if [ "$ROOTLESS" = "1" ]; then
    PREFIX="/var/jb"
    echo "[*] Detected ROOTLESS jailbreak (prefix: $PREFIX)"
else
    PREFIX=""
    echo "[*] Detected ROOTFUL jailbreak"
fi

BIN_PATH="$PREFIX/usr/local/bin/beerusd"
PLIST_PATH="$PREFIX/Library/LaunchDaemons/com.beerus.daemon.plist"

echo "[1/4] Compiling daemon..."
make -C "$DIR" clean
make -C "$DIR" all

echo "[2/4] Stopping old daemon on device..."
ssh -p "$PORT" "root@$IP" "launchctl bootout system '$PLIST_PATH' 2>/dev/null; killall beerusd 2>/dev/null; true"
# Also stop legacy daemon
ssh -p "$PORT" "root@$IP" "launchctl bootout system '$PREFIX/Library/LaunchDaemons/io.hakaisecurity.BEERUS-Framework.plist' 2>/dev/null; killall BEERUS-Framework 2>/dev/null; true"

echo "[3/4] Uploading files..."
scp -P "$PORT" "$DIR/beerusd" "root@$IP:$BIN_PATH"
scp -P "$PORT" "$DIR/com.beerus.daemon.plist" "root@$IP:$PLIST_PATH"

echo "[4/4] Setting permissions and starting daemon..."
ssh -p "$PORT" "root@$IP" "\
    chmod 755 '$BIN_PATH' && \
    chown root:wheel '$BIN_PATH' && \
    chown root:wheel '$PLIST_PATH' && \
    launchctl bootstrap system '$PLIST_PATH'"

echo "Done — daemon installed and running (rootless=$ROOTLESS)"
