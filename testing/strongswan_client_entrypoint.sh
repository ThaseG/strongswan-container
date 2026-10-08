#!/bin/bash
# strongswan_client_entrypoint.sh
#
# Starts charon, loads the client configuration from SWANCTL_DIR and stays in
# the foreground. The tunnel itself is initiated by the e2e tests.

set -euo pipefail

export SWANCTL_DIR="${SWANCTL_DIR:?SWANCTL_DIR must point at the client config directory}"
VICI_SOCKET="/var/run/charon.vici"

rm -f /var/run/charon.pid "$VICI_SOCKET"

# Log to stdout line by line; the default --debug-* logger is block-buffered
# and loses its tail when the container stops.
cat > /etc/strongswan.d/charon-logging-container.conf << 'EOF'
charon {
    filelog {
        stdout {
            default = 1
            ike_name = yes
            flush_line = yes
        }
    }
}
EOF

/usr/lib/ipsec/charon &
CHARON_PID=$!
trap 'kill -TERM "$CHARON_PID" 2>/dev/null || true' TERM INT

for _ in $(seq 1 30); do
    [ -S "$VICI_SOCKET" ] && break
    kill -0 "$CHARON_PID" 2>/dev/null || { echo "FATAL: charon exited"; exit 1; }
    sleep 1
done
[ -S "$VICI_SOCKET" ] || { echo "FATAL: VICI socket not available"; exit 1; }

swanctl --load-all --noprompt

echo "=== Client ready ==="

set +e
wait "$CHARON_PID"
rc=$?
while kill -0 "$CHARON_PID" 2>/dev/null; do
    wait "$CHARON_PID"
    rc=$?
done
exit "$rc"
