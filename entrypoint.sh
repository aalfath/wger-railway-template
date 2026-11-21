#!/bin/sh
# Runs as root: prepare the Railway volume (mounted at /data), then drop to the wger user.
set -eu
DATA=${WGER_DATA_DIR:-/data}
mkdir -p "$DATA/media" "$DATA/beat" "$DATA/secrets"
rm -r "$DATA/lost+found" 2>/dev/null || true
chown -R 1000:1000 "$DATA"
chmod 700 "$DATA/secrets"
exec setpriv --reuid=1000 --regid=1000 --init-groups /usr/local/bin/wger-railway-run
