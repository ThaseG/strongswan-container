#!/bin/bash
# entrypoint.sh
set -e

echo "=== StrongSwan Container Initialization ==="

CONFIG_DIR="/etc/swanctl"
LOG_DIR="/var/log/strongswan"
VICI_SOCKET="/var/run/strongswan/charon-vici.sock"

# Setup permissions
echo "Setting up permissions..."
chown -R strongswan:strongswan "$CONFIG_DIR" "$LOG_DIR"
chmod 700 "$CONFIG_DIR/private" "$CONFIG_DIR/rsa"

# Apply iptables if exists
if [ -f "$CONFIG_DIR/iptables.sh" ]; then
    echo "Applying iptables rules..."
    chmod +x "$CONFIG_DIR/iptables.sh"
    "$CONFIG_DIR/iptables.sh"
fi

# Array to track background PIDs
pids=()

# Shutdown handler
shutdown() {
    echo "Shutting down gracefully..."
    if [ -S "$VICI_SOCKET" ]; then
        /usr/sbin/swanctl --terminate --ike all 2>/dev/null || true
    fi
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait
    exit 0
}

trap shutdown SIGTERM SIGINT

# Start charon daemon
echo "Starting StrongSwan charon daemon..."
/usr/sbin/charon-systemd &
pids+=($!)

# Wait for VICI socket
echo "Waiting for VICI socket..."
for i in {1..30}; do
    if [ -S "$VICI_SOCKET" ]; then
        echo "VICI socket ready"
        break
    fi
    [ $i -eq 30 ] && { echo "ERROR: VICI socket timeout"; exit 1; }
    sleep 1
done

# Load configuration
echo "Loading swanctl configuration..."
/usr/sbin/swanctl --load-all || echo "WARNING: Failed to load swanctl config"

# Fix VICI socket permissions
chown strongswan:strongswan "$VICI_SOCKET" 2>/dev/null || true
chmod 660 "$VICI_SOCKET" 2>/dev/null || true

# Start exporter
if [ -f /usr/local/bin/strongswan-exporter ]; then
    echo "Starting StrongSwan Exporter..."
    su -s /bin/bash strongswan -c "/usr/local/bin/strongswan-exporter" &
    pids+=($!)
else
    echo "WARNING: Exporter not found"
fi

echo "=== All services started ==="
wait