#!/bin/bash
set -e # Exit on error

# Define the paths
SWANCTL_CONF="/etc/swanctl/swanctl.conf"
STRONGSWAN_CONF="/etc/strongswan.conf"
LOG_DIR="/var/log/strongswan"
CONFIG_DIR="/etc/swanctl"
VICI_SOCKET="/var/run/strongswan/charon-vici.sock"

# Change ownership of all files in config folder
sudo chown -R strongswan:strongswan "$CONFIG_DIR"

# Change ownership of logs directory
sudo chown -R strongswan:strongswan "$LOG_DIR"

# Backup old logfiles before starting StrongSwan
echo "Backing up old log files..."
if [ -f "$LOG_DIR/charon.log" ]; then
    cp "$LOG_DIR/charon.log" "$LOG_DIR/charon.log.backup"
fi

# Pre-create log file with correct ownership and permissions
echo "Pre-creating log files..."
touch "$LOG_DIR/charon.log"
chown strongswan:strongswan "$LOG_DIR/charon.log"
chmod 644 "$LOG_DIR/charon.log"

# Implement iptables rules if the config file exists
if [ -f "$CONFIG_DIR/iptables.sh" ]; then
    echo "Applying iptables rules..."
    sudo chmod +x "$CONFIG_DIR/iptables.sh"
    sudo "$CONFIG_DIR/iptables.sh"
fi

# Check if the configuration file exists
if [ ! -f "$SWANCTL_CONF" ]; then
    echo "ERROR: Swanctl configuration not found at $SWANCTL_CONF"
    exit 1
fi

if [ ! -f "$STRONGSWAN_CONF" ]; then
    echo "ERROR: StrongSwan configuration not found at $STRONGSWAN_CONF"
    exit 1
fi

# Array to track background PIDs
pids=()

# Start StrongSwan charon-systemd daemon
echo "Starting StrongSwan charon daemon..."
sudo /usr/sbin/charon-systemd &
pids+=($!)
echo "StrongSwan charon started with PID ${pids[-1]}"

# Wait for VICI socket to be ready
echo "Waiting for VICI socket to be ready..."
for i in {1..30}; do
    if [ -S "$VICI_SOCKET" ]; then
        echo "VICI socket is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: VICI socket not ready after 30 seconds"
        exit 1
    fi
    sleep 1
done

# Load swanctl configuration
echo "Loading swanctl configuration..."
sudo /usr/sbin/swanctl --load-all
if [ $? -eq 0 ]; then
    echo "Swanctl configuration loaded successfully"
else
    echo "WARNING: Failed to load swanctl configuration"
fi

# Give StrongSwan a moment to initialize
sleep 2

# Fix permissions on VICI socket
sudo chown strongswan:strongswan "$VICI_SOCKET" 2>/dev/null || true
sudo chmod 660 "$VICI_SOCKET" 2>/dev/null || true

# Start the strongswan-exporter
if [ -f /home/strongswan/exporter/strongswan-exporter ]; then
    echo "Starting StrongSwan Exporter..."
    /home/strongswan/exporter/strongswan-exporter --config.file=/home/strongswan/exporter.yml &
    pids+=($!)
    echo "StrongSwan exporter started with PID ${pids[-1]}"
else
    echo "WARNING: Exporter binary not found"
fi

# Function to handle shutdown gracefully
shutdown() {
    echo "Shutting down gracefully..."
    
    # Terminate connections gracefully
    if [ -S "$VICI_SOCKET" ]; then
        echo "Terminating active connections..."
        sudo /usr/sbin/swanctl --terminate --ike all 2>/dev/null || true
    fi
    
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping process $pid"
            sudo kill "$pid"
        fi
    done
    exit 0
}

# Trap SIGTERM and SIGINT for graceful shutdown
trap shutdown SIGTERM SIGINT

echo "All services started. Waiting for processes..."

# Wait for all background processes
wait