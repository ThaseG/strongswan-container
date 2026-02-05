#!/bin/bash
set -e

echo "Starting StrongSwan charon daemon..."
# Spustíme charon na pozadí a presmerujeme logy do súboru
/usr/sbin/charon-systemd > /var/log/strongswan/charon.log 2>&1 &

echo "Waiting for VICI socket..."
for i in {1..30}; do
    # Vypíšeme, čo vidí systém v /var/run, aby sme videli progres
    if [ -S "/var/run/strongswan/charon-vici.sock" ]; then
        echo "VICI socket found!"
        break
    fi
    
    # Ak po 5 sekundách socket stále nie je, vypíš posledné riadky logu charonu
    if [ $i -eq 5 ]; then
        echo "--- Debug: Last logs from charon ---"
        tail -n 20 /var/log/strongswan/charon.log || echo "No logs available"
        echo "------------------------------------"
    fi
    
    sleep 1
    if [ $i -eq 30 ]; then
        echo "ERROR: VICI socket timeout"
        # Pred koncom vypíšeme úplne všetko, čo charon povedal
        cat /var/log/strongswan/charon.log
        exit 1
    fi
done

# Spustenie exportera...
exec /usr/local/bin/strongswan-exporter