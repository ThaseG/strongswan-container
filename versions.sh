#!/bin/bash
#
# versions.sh - StrongSwan Container Version Configuration
#
# This file defines version information for the StrongSwan container
# and the distributions used for testing.
#

# Container image version
IMAGE_VERSION='v0.0.2'

# StrongSwan version
# For upgrade, please update also in server/strongswan.dockerfile
STRONGSWAN_VERSION='6.0.3'

# Client image versions for testing
# These correspond to the Dockerfiles in testing/ directory
CLIENT_IMAGE_VERSIONS=("bullseye" "bookworm" "jammy")

# Distribution details
declare -A DISTRO_INFO=(
    ["bullseye"]="Debian 11 (Bullseye)"
    ["bookworm"]="Debian 12 (Bookworm)"
    ["jammy"]="Ubuntu 22.04 LTS (Jammy)"
)

# Certificate configuration
CA_KEY_SIZE=4096
CERT_KEY_SIZE=2048
CA_VALIDITY_DAYS=3650    # 10 years
CERT_VALIDITY_DAYS=1825  # 5 years

# IPsec configuration defaults
DEFAULT_IKE_CIPHER="aes256-sha256-modp2048"
DEFAULT_ESP_CIPHER="aes256-sha256"
DEFAULT_KEY_EXCHANGE="ikev2"

# Network configuration
VPN_POOL="10.0.70.0/24"
EXTERNAL_NETWORK="192.168.200.0/24"
INTERNAL_NETWORK="10.10.10.0/24"

# Export variables for use in scripts
export IMAGE_VERSION
export STRONGSWAN_VERSION
export CLIENT_IMAGE_VERSIONS
export CA_KEY_SIZE
export CERT_KEY_SIZE
export CA_VALIDITY_DAYS
export CERT_VALIDITY_DAYS

# Function to print version information
print_versions() {
    echo "=========================================="
    echo "StrongSwan Container Version Information"
    echo "=========================================="
    echo ""
    echo "Container Image:     ${IMAGE_VERSION}"
    echo "StrongSwan Version:  ${STRONGSWAN_VERSION}"
    echo ""
    echo "Supported Test Distributions:"
    for dist in "${CLIENT_IMAGE_VERSIONS[@]}"; do
        echo "  - ${dist}: ${DISTRO_INFO[$dist]}"
    done
    echo ""
    echo "Certificate Configuration:"
    echo "  CA Key Size:         ${CA_KEY_SIZE} bits"
    echo "  Certificate Key Size: ${CERT_KEY_SIZE} bits"
    echo "  CA Validity:         ${CA_VALIDITY_DAYS} days"
    echo "  Cert Validity:       ${CERT_VALIDITY_DAYS} days"
    echo ""
    echo "IPsec Configuration:"
    echo "  IKE Cipher:          ${DEFAULT_IKE_CIPHER}"
    echo "  ESP Cipher:          ${DEFAULT_ESP_CIPHER}"
    echo "  Key Exchange:        ${DEFAULT_KEY_EXCHANGE}"
    echo ""
    echo "Network Configuration:"
    echo "  VPN Pool:            ${VPN_POOL}"
    echo "  External Network:    ${EXTERNAL_NETWORK}"
    echo "  Internal Network:    ${INTERNAL_NETWORK}"
    echo ""
}

# If script is executed directly, print versions
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    print_versions
fi