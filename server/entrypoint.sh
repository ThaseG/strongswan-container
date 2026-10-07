#!/bin/bash
set -euo pipefail

# Tunables (override with `docker run -e ...`)
#   CHARON_DEBUG     - charon --debug-* arguments
#   SWANCTL_DIR      - swanctl config root (read natively by swanctl)
#   VICI_TIMEOUT     - seconds to wait for the VICI socket
#   EXPORTER_ENABLED - set to "false" to skip the Prometheus exporter
CHARON_DEBUG="${CHARON_DEBUG:---debug-dmn 1 --debug-knl 1 --debug-cfg 1}"
export SWANCTL_DIR="${SWANCTL_DIR:-/etc/swanctl}"
VICI_TIMEOUT="${VICI_TIMEOUT:-30}"
EXPORTER_ENABLED="${EXPORTER_ENABLED:-true}"

# Default socket; the exporter (govici) connects to this path unconditionally.
VICI_SOCKET="/var/run/charon.vici"
CHARON_PID=""
EXPORTER_PID=""

shutdown() {
    echo "=== Shutting down ==="
    [ -n "$EXPORTER_PID" ] && kill -TERM "$EXPORTER_PID" 2>/dev/null || true
    [ -n "$CHARON_PID" ] && kill -TERM "$CHARON_PID" 2>/dev/null || true
}
trap shutdown TERM INT

echo "=== Starting StrongSwan Charon Daemon ==="

# A restarted container keeps its filesystem: a stale PID file makes charon
# refuse to start, and a stale socket would pass the readiness check below.
rm -f /var/run/charon.pid "$VICI_SOCKET"

# shellcheck disable=SC2086  # CHARON_DEBUG is intentionally word-split
/usr/lib/ipsec/charon $CHARON_DEBUG &
CHARON_PID=$!

echo "Waiting for VICI socket at $VICI_SOCKET..."
for ((i = 1; i <= VICI_TIMEOUT; i++)); do
    [ -S "$VICI_SOCKET" ] && break
    if ! kill -0 "$CHARON_PID" 2>/dev/null; then
        echo "FATAL: charon exited during startup"
        exit 1
    fi
    sleep 1
done

if [ ! -S "$VICI_SOCKET" ]; then
    echo "FATAL: VICI socket not available after ${VICI_TIMEOUT}s"
    shutdown
    exit 1
fi
echo "VICI socket is ready"

echo "Loading swanctl configuration from $SWANCTL_DIR..."
if ! swanctl --load-all --noprompt; then
    echo "FATAL: failed to load swanctl configuration"
    shutdown
    exit 1
fi

if [ "$EXPORTER_ENABLED" = "true" ]; then
    echo "Starting StrongSwan Exporter..."
    /usr/local/bin/strongswan-exporter \
        --config.file=/etc/strongswan-exporter/exporter.yml &
    EXPORTER_PID=$!
    echo "StrongSwan exporter started with PID $EXPORTER_PID"
fi

echo "=== All services started ==="

# `wait` returns early when a trapped signal arrives; keep waiting until
# charon has actually exited so its exit code is propagated.
set +e
wait "$CHARON_PID"
rc=$?
while kill -0 "$CHARON_PID" 2>/dev/null; do
    wait "$CHARON_PID"
    rc=$?
done
set -e

echo "charon exited with code $rc"
[ -n "$EXPORTER_PID" ] && kill -TERM "$EXPORTER_PID" 2>/dev/null || true
exit "$rc"
