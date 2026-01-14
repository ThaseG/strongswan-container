#!/bin/bash

# Define the paths
CLIENT_CONF="/home/strongswan/config/client-bookworm.conf"
CLIENT_SCRIPT="/home/strongswan/config/client-bookworm.sh"

# Change ownership of all files in config folder
sudo chown -R strongswan:strongswan /home/strongswan/config/

# Check if script for client config exist
if [ -f "$CLIENT_SCRIPT" ]; then
    # Just for sure add execution parameter
    sudo chmod +x /home/strongswan/config/client.sh
    # Now execute it
    sudo /home/strongswan/config/client.sh

# If there is no client script, then executing client config
else
    # Start client with generated configuration
    echo "Starting client with generated configuration ..."
    # We run with sudo, because without this strongswan won't have rights to utilize /dev/net/tun
    sudo strongswan --config "$CLIENT_CONF" &
    # We also check curl to see exporter statistics
    sleep 30
    curl -vvv http://192.168.200.100:9234/metrics
fi

# Wait for all background processes to finish
wait
