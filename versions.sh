#!/bin/bash
#
# versions.sh - StrongSwan Container Version Configuration
#
# This file defines version information for the StrongSwan container
# and the distributions used for testing. It is the single source of truth
# for CI: the image build and the e2e tests both read it.
#

# Container image version
IMAGE_VERSION='v0.0.7'

# StrongSwan version (CI passes both values to server/strongswan.dockerfile;
# keep the ARG defaults there in sync for local builds)
STRONGSWAN_VERSION='6.1.0'
STRONGSWAN_SHA256='d9484eea319481bda86f992fa69cbdbdd9c0d6f8b9a4bd793a7df45c0760d963'

# strongswan-exporter release tag (https://github.com/ThaseG/strongswan-exporter)
EXPORTER_VERSION='v1.0.0'

# Go release used to build the exporter (major.minor; patch releases are
# picked up automatically by the golang:<version> image)
GO_VERSION='1.27'

# Client image versions for testing (built from testing/strongswan_client.dockerfile)
# Covers every supported Debian release and Ubuntu LTS. Debian 11 (bullseye)
# was dropped after its end of life (2026-08), when its security archive left
# the mirrors and apt could no longer install packages.
CLIENT_IMAGE_VERSIONS=("bookworm" "trixie" "jammy" "noble" "resolute")

# Distribution details
declare -gA DISTRO_INFO=(
    ["bookworm"]="Debian 12 (Bookworm)"
    ["trixie"]="Debian 13 (Trixie)"
    ["jammy"]="Ubuntu 22.04 LTS (Jammy)"
    ["noble"]="Ubuntu 24.04 LTS (Noble)"
    ["resolute"]="Ubuntu 26.04 LTS (Resolute)"
)

# Base image of each test client
declare -gA CLIENT_BASE_IMAGES=(
    ["bookworm"]="debian:bookworm"
    ["trixie"]="debian:trixie"
    ["jammy"]="ubuntu:jammy"
    ["noble"]="ubuntu:noble"
    ["resolute"]="ubuntu:resolute"
)

# Certificate configuration (all keys are Ed25519)
CA_VALIDITY_DAYS=3650    # 10 years
CERT_VALIDITY_DAYS=1825  # 5 years

# IPsec configuration defaults (swanctl.conf proposal syntax)
IKE_PROPOSALS="aes256gcm16-prfsha256-x25519-ecp256"
ESP_PROPOSALS="aes256gcm16"

# Network configuration
VPN_POOL="10.0.70.0/24"
EXTERNAL_NETWORK="192.168.200.0/24"
INTERNAL_NETWORK="10.10.10.0/24"

# Test topology
SERVER_ID="cicd.strongswan.com"
SERVER_EXTERNAL_IP="192.168.200.100"
SERVER_INTERNAL_IP="10.10.10.100"
PROTECTED_SERVICE_IP="10.10.10.10"
EXPORTER_PORT=9234
declare -gA CLIENT_IPS=(
    ["bookworm"]="192.168.200.10"
    ["trixie"]="192.168.200.20"
    ["jammy"]="192.168.200.40"
    ["noble"]="192.168.200.50"
    ["resolute"]="192.168.200.60"
)

# Export variables for use in scripts
export IMAGE_VERSION
export STRONGSWAN_VERSION
export STRONGSWAN_SHA256
export EXPORTER_VERSION
export GO_VERSION
export CLIENT_IMAGE_VERSIONS
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
    echo "Exporter Version:    ${EXPORTER_VERSION}"
    echo "Go Version:          ${GO_VERSION}"
    echo ""
    echo "Supported Test Distributions:"
    for dist in "${CLIENT_IMAGE_VERSIONS[@]}"; do
        echo "  - ${dist}: ${DISTRO_INFO[$dist]} (${CLIENT_IPS[$dist]})"
    done
    echo ""
    echo "Certificate Configuration:"
    echo "  Key Algorithm:       Ed25519"
    echo "  CA Validity:         ${CA_VALIDITY_DAYS} days"
    echo "  Cert Validity:       ${CERT_VALIDITY_DAYS} days"
    echo ""
    echo "IPsec Configuration:"
    echo "  IKE Proposals:       ${IKE_PROPOSALS}"
    echo "  ESP Proposals:       ${ESP_PROPOSALS}"
    echo ""
    echo "Network Configuration:"
    echo "  VPN Pool:            ${VPN_POOL}"
    echo "  External Network:    ${EXTERNAL_NETWORK}"
    echo "  Internal Network:    ${INTERNAL_NETWORK}"
    echo "  Server:              ${SERVER_EXTERNAL_IP} / ${SERVER_INTERNAL_IP}"
    echo "  Protected Service:   ${PROTECTED_SERVICE_IP}"
    echo ""
}

# If script is executed directly, print versions
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    print_versions
fi
