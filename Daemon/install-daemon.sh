#!/bin/bash
set -e

IP="IP"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/4] Compiling daemon..."
make -C "$DIR" clean
make -C "$DIR" all

echo "[2/4] Stopping old daemon on device..."
ssh "root@$IP" "launchctl unload /Library/LaunchDaemons/com.beerus.daemon.plist 2>/dev/null; killall beerusd 2>/dev/null; true"

echo "[3/4] Uploading files..."
scp "$DIR/beerusd" "root@$IP:/usr/local/bin/beerusd"
scp "$DIR/com.beerus.daemon.plist" "root@$IP:/Library/LaunchDaemons/com.beerus.daemon.plist"

echo "[4/4] Setting permissions and starting daemon..."
ssh "root@$IP" "\
    chmod 755 /usr/local/bin/beerusd && \
    chown root:wheel /usr/local/bin/beerusd && \
    chown root:wheel /Library/LaunchDaemons/com.beerus.daemon.plist && \
    launchctl load /Library/LaunchDaemons/com.beerus.daemon.plist"

echo "Done — daemon installed and running"
