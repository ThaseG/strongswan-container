#!/bin/bash
# generate_server_config.sh

set -e

# Define the paths
CONFIG_DIR="/home/strongswan/config"
IPSEC_CONF="${CONFIG_DIR}/ipsec.conf"
IPSEC_SECRETS="${CONFIG_DIR}/ipsec.secrets"
STRONGSWAN_CONF="${CONFIG_DIR}/strongswan.conf"

# Configuration variables (can be overridden by environment variables)
SERVER_IP="${SERVER_IP:-192.168.200.100}"
PROTECTED_SUBNET="${PROTECTED_SUBNET:-10.10.10.0/24}"
VPN_POOL="${VPN_POOL:-10.0.70.0/24}"
DNS_SERVERS="${DNS_SERVERS:-1.1.1.1,8.8.8.8}"
MAX_CLIENTS="${MAX_CLIENTS:-100}"

# IKE/ESP cipher configuration
IKE_PROPOSALS="${IKE_PROPOSALS:-aes256-sha256-modp2048!}"
ESP_PROPOSALS="${ESP_PROPOSALS:-aes256-sha256!}"

# Timeouts
IKE_LIFETIME="${IKE_LIFETIME:-60m}"
KEY_LIFETIME="${KEY_LIFETIME:-20m}"
REKEY_MARGIN="${REKEY_MARGIN:-3m}"

# Logging
LOG_LEVEL="${LOG_LEVEL:-2}"

echo "=========================================="
echo "StrongSwan Server Configuration Generator"
echo "=========================================="
echo ""

# Create config directory if it doesn't exist
mkdir -p "${CONFIG_DIR}"

echo "Generating ipsec.conf..."

# Generate ipsec.conf
cat > "${IPSEC_CONF}" << EOF
# StrongSwan IPsec Configuration
# Generated on: $(date)
# 
# This configuration provides IKEv2 road-warrior VPN setup
# Clients will be assigned IPs from ${VPN_POOL}
# and can access protected subnet ${PROTECTED_SUBNET}

config setup
    # Logging levels: ike, knl, cfg, net, esp, dmn, mgr
    charondebug="ike ${LOG_LEVEL}, knl ${LOG_LEVEL}, cfg ${LOG_LEVEL}, net ${LOG_LEVEL}, esp ${LOG_LEVEL}, dmn ${LOG_LEVEL}, mgr ${LOG_LEVEL}"
    
    # Allow multiple connections from same client
    uniqueids=never

# Default settings for all connections
conn %default
    # IKE SA lifetime
    ikelifetime=${IKE_LIFETIME}
    
    # Child SA (IPsec) lifetime
    keylife=${KEY_LIFETIME}
    
    # Rekey margin (start rekeying before expiry)
    rekeymargin=${REKEY_MARGIN}
    
    # Key exchange retries
    keyingtries=3
    
    # Use IKEv2
    keyexchange=ikev2
    
    # IKE cipher proposals
    ike=${IKE_PROPOSALS}
    
    # ESP cipher proposals
    esp=${ESP_PROPOSALS}
    
    # Dead peer detection
    dpdaction=clear
    dpddelay=300s
    dpdtimeout=600s

# Road-warrior connection (remote clients)
conn roadwarrior
    # Server side (left)
    left=%any
    leftid=${SERVER_IP}
    leftcert=server-cert.pem
    leftsubnet=${PROTECTED_SUBNET}
    
    # Client side (right)
    right=%any
    rightid=%any
    rightsourceip=${VPN_POOL}
    
    # DNS servers to push to clients
    rightdns=${DNS_SERVERS}
    
    # Auto start policy
    # add = load but don't start
    # start = load and start immediately
    auto=add
    
    # Send certificate requests
    leftsendcert=always
    
    # Request client certificate
    rightauth=pubkey
    rightauth2=eap-mschapv2

# Optional: PSK-based connection for legacy clients
# conn roadwarrior-psk
#     also=roadwarrior
#     leftauth=psk
#     rightauth=psk
#     rightauth2=%any
#     auto=add

EOF

chmod 644 "${IPSEC_CONF}"
echo "✓ ipsec.conf generated at: ${IPSEC_CONF}"

echo ""
echo "Generating ipsec.secrets..."

# Generate ipsec.secrets
cat > "${IPSEC_SECRETS}" << EOF
# StrongSwan IPsec Secrets
# Generated on: $(date)
#
# This file holds shared secrets or RSA private keys for authentication.

# RSA private key for server authentication
: RSA server-key.pem

# Optional: PSK for legacy clients (if using roadwarrior-psk connection)
# %any : PSK "your-secure-pre-shared-key-here"

# Optional: EAP credentials for username/password authentication
# username : EAP "password"

EOF

chmod 600 "${IPSEC_SECRETS}"
echo "✓ ipsec.secrets generated at: ${IPSEC_SECRETS}"

echo ""
echo "Generating strongswan.conf..."

# Generate strongswan.conf (daemon configuration)
cat > "${STRONGSWAN_CONF}" << EOF
# StrongSwan Daemon Configuration
# Generated on: $(date)

charon {
    # Number of worker threads
    threads = 16
    
    # Log to syslog
    syslog {
        daemon {
            ike = ${LOG_LEVEL}
            knl = ${LOG_LEVEL}
            cfg = ${LOG_LEVEL}
        }
    }
    
    # Load plugins
    load_modular = yes
    
    plugins {
        include strongswan.d/charon/*.conf
    }
    
    # DNS resolution
    dns1 = ${DNS_SERVERS%%,*}
    dns2 = ${DNS_SERVERS##*,}
    
    # Enable NAT traversal
    nat_traversal = yes
    
    # Maximum number of IKE SA half-open connections
    max_half_open_ike_sa = ${MAX_CLIENTS}
    
    # Keep alive interval
    keep_alive = 20s
}

# Logging to files
charon-systemd {
    journal {
        # Log to stdout for container
        default = 1
    }
}

EOF

chmod 644 "${STRONGSWAN_CONF}"
echo "✓ strongswan.conf generated at: ${STRONGSWAN_CONF}"

echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo ""
echo "Server Configuration:"
echo "  Server IP:         ${SERVER_IP}"
echo "  Protected Subnet:  ${PROTECTED_SUBNET}"
echo "  VPN Pool:          ${VPN_POOL}"
echo "  DNS Servers:       ${DNS_SERVERS}"
echo "  Max Clients:       ${MAX_CLIENTS}"
echo ""
echo "Security Configuration:"
echo "  IKE Proposals:     ${IKE_PROPOSALS}"
echo "  ESP Proposals:     ${ESP_PROPOSALS}"
echo "  IKE Lifetime:      ${IKE_LIFETIME}"
echo "  Key Lifetime:      ${KEY_LIFETIME}"
echo ""
echo "Log Level:           ${LOG_LEVEL}"
echo ""
echo "=========================================="
echo "Generated Files"
echo "=========================================="
echo ""

echo "### IPSEC.CONF ###"
cat "${IPSEC_CONF}"

echo ""
echo "### IPSEC.SECRETS ###"
echo "(Content hidden for security - contains private key references)"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Generate certificates if not already done:"
echo "   ./generate-certificates.sh"
echo ""
echo "2. Copy certificates to ${CONFIG_DIR}/ipsec.d/"
echo ""
echo "3. Start StrongSwan:"
echo "   ipsec start"
echo ""
echo "4. Verify configuration:"
echo "   ipsec statusall"
echo ""

# Wait for all background processes to finish (if any)
wait

echo "Configuration generation complete!"