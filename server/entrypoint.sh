#!/bin/bash
set -e

echo "=== Starting StrongSwan Charon Daemon ==="

mkdir -p /var/run/strongswan
chmod 755 /var/run/strongswan

/usr/lib/ipsec/charon --debug-dmn 1 --debug-knl 1 --debug-cfg 1 &
CHARON_PID=$!

echo "Waiting for VICI socket..."
SOCKET=""
for i in {1..30}; do
    if [ -S "/var/run/charon.vici" ]; then
        SOCKET="/var/run/charon.vici"
    elif [ -S "/var/run/strongswan/charon-vici.sock" ]; then
        SOCKET="/var/run/strongswan/charon-vici.sock"
    fi

    if [ -n "$SOCKET" ]; then
        echo "VICI socket found at $SOCKET!"
        export STRONGSWAN_VICI_SOCKET="unix://$SOCKET"

        if [ -f /usr/local/bin/strongswan-exporter ]; then
            echo "Starting StrongSwan Exporter..."
            /usr/local/bin/strongswan-exporter --config.file=/home/strongswan/exporter.yml &
            EXPORTER_PID=$!
            echo "StrongSwan exporter started with PID $EXPORTER_PID"
        else
            echo "WARNING: Exporter binary not found"
        fi

        # Socket found, exporter started — exit the loop
        break
    fi

    if [ $((i % 5)) -eq 0 ]; then
        if kill -0 $CHARON_PID 2>/dev/null; then
            echo "Attempt $i: Charon is running, but socket is not ready yet..."
        else
            echo "Attempt $i: FATAL - Charon process has died!"
            exit 1
        fi
    fi

    sleep 1
done

if [ -z "$SOCKET" ]; then
    echo "ERROR: VICI socket timeout."
    exit 1
fi

echo "=== All services started, waiting... ==="
# Wait for charon — if it dies, container exits
wait $CHARON_PID