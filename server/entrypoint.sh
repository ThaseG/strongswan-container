#!/bin/bash
set -e

echo "=== Starting StrongSwan Charon Daemon ==="

# Vytvorenie adresára pre socket, ak neexistuje
mkdir -p /var/run/strongswan

# Spustíme priamo charon (nie charon-systemd)
# --debug-all 1 nám vypíše základné info o načítaní pluginov
/usr/lib/ipsec/charon --debug-all 1 &

echo "Waiting for VICI socket..."
# StrongSwan (non-systemd) zvyčajne vytvára socket tu:
# Ak by ho nevytvoril, skontrolujeme aj /var/run/charon.vici
for i in {1..20}; do
    # Skúsime obe bežné cesty
    if [ -S "/var/run/charon.vici" ]; then
        SOCKET="/var/run/charon.vici"
    elif [ -S "/var/run/strongswan/charon-vici.sock" ]; then
        SOCKET="/var/run/strongswan/charon-vici.sock"
    fi

    if [ ! -z "$SOCKET" ]; then
        echo "VICI socket found at $SOCKET!"
        export STRONGSWAN_VICI_SOCKET="unix://$SOCKET"
        echo "Starting exporter..."
        exec /usr/local/bin/strongswan-exporter
    fi

    echo "Attempt $i: Socket not found yet..."
    sleep 1
done

echo "ERROR: VICI socket timeout."
echo "--- Process list ---"
ps aux
echo "--- Content of /var/run ---"
ls -R /var/run
exit 1