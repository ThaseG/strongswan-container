#!/bin/bash
IMAGE_VERSION='v0.0.1'
STRONGSWAN_VERSION='v6.0.3' # For upgrade, please update also in server/openvpn.dockerfile
CLIENT_IMAGE_VERSIONS=("bullseye" "bookworm" "focal" "jammy")