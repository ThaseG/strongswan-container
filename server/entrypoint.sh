#!/bin/bash
set -e

echo "=== Starting StrongSwan Charon Daemon ==="

# Vytvorenie adresára pre socket a nastavenie práv
mkdir -p /var/run/strongswan
chmod 755 /var/run/strongswan

# Spustenie charonu so správnym debugovaním (dmn = daemon, knl = kernel, cfg = config)
# Spúšťame na pozadí
/usr/lib/ipsec/charon --debug-dmn 1 --debug-knl 1 --debug-cfg 1 &

echo "Waiting for VICI socket..."
for i in {1..30}; do
    # Kontrolujeme obe možné cesty, kde by sa mohol socket objaviť
    if [ -S "/var/run/charon.vici" ]; then
        SOCKET="/var/run/charon.vici"
    elif [ -S "/var/run/strongswan/charon-vici.sock" ]; then
        SOCKET="/var/run/strongswan/charon-vici.sock"
    fi

    if [ ! -z "$SOCKET" ]; then
        echo "VICI socket found at $SOCKET!"
        export STRONGSWAN_VICI_SOCKET="unix://$SOCKET"

        # Start the strongswan-exporter
        if [ -f /usr/local/bin/strongswan-exporter ]; then
            echo "Starting StrongSwan Exporter..."
            /usr/local/bin/strongswan-exporter --config.file=/home/strongswan/exporter.yml &
            pids+=($!)
            echo "StrongSwan exporter started with PID ${pids[-1]}"
        else
            echo "WARNING: Exporter binary not found"
        fi
    fi

    # Každých 5 pokusov vypíšeme, či proces charon stále žije
    if [ $((i%5)) -eq 0 ]; then
        if ps aux | grep -v grep | grep -q "/usr/lib/ipsec/charon"; then
            echo "Attempt $i: Charon is running, but socket is not ready yet..."
        else
            echo "Attempt $i: FATAL - Charon process has died!"
            exit 1
        fi
    fi
    
    sleep 1
done

echo "ERROR: VICI socket timeout."
exit 1