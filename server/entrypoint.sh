#!/bin/bash
set -euo pipefail

# Tunables (override with `docker run -e ...`)
#   SWANCTL_DIR         - swanctl config root (read natively by swanctl)
#   VICI_TIMEOUT        - seconds to wait for the VICI socket
#   EXPORTER_ENABLED    - set to "false" to skip the Prometheus exporter
#   CHARON_STOP_TIMEOUT - seconds charon gets to shut down before it is killed
#                         (keep below the `docker stop` timeout, default 10s)
# Log levels are set in /etc/strongswan.d/charon-logging-container.conf.
export SWANCTL_DIR="${SWANCTL_DIR:-/etc/swanctl}"
VICI_TIMEOUT="${VICI_TIMEOUT:-30}"
EXPORTER_ENABLED="${EXPORTER_ENABLED:-true}"
CHARON_STOP_TIMEOUT="${CHARON_STOP_TIMEOUT:-8}"

# Default socket; the exporter (govici) connects to this path unconditionally.
VICI_SOCKET="/var/run/charon.vici"
CHARON_PID=""
EXPORTER_PID=""

# Print state, kernel wait channel and current syscall of every charon thread,
# to show where a stuck shutdown is blocked.
dump_charon_threads() {
    local task
    for task in /proc/"$CHARON_PID"/task/*; do
        echo "  thread ${task##*/}:" \
             "state=$(awk '/^State:/ {print $2}' "$task/status" 2>/dev/null)" \
             "wchan=$(cat "$task/wchan" 2>/dev/null)" \
             "syscall=$(cut -d' ' -f1 "$task/syscall" 2>/dev/null)"
    done
}

shutdown() {
    echo "=== Shutting down ==="
    [ -n "$EXPORTER_PID" ] && kill -TERM "$EXPORTER_PID" 2>/dev/null || true
    [ -n "$CHARON_PID" ] && kill -TERM "$CHARON_PID" 2>/dev/null || true

    # Watchdog: never let a hung charon run into Docker's SIGKILL of the
    # whole container. A killed charon still exits non-zero, so it stays visible.
    if [ -n "$CHARON_PID" ]; then
        (
            sleep "$CHARON_STOP_TIMEOUT"
            if kill -0 "$CHARON_PID" 2>/dev/null; then
                echo "WARNING: charon did not stop within ${CHARON_STOP_TIMEOUT}s, killing it. Thread state:"
                dump_charon_threads
                kill -KILL "$CHARON_PID" 2>/dev/null || true
            fi
        ) &
    fi
}
trap shutdown TERM INT

echo "=== Starting StrongSwan Charon Daemon ==="

# A restarted container keeps its filesystem: a stale PID file makes charon
# refuse to start, and a stale socket would pass the readiness check below.
rm -f /var/run/charon.pid "$VICI_SOCKET"

/usr/lib/ipsec/charon &
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
