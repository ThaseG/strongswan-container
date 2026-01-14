#!/bin/bash

# StrongSwan Certificate Generation Script with Curve25519 (Ed25519)
# Compliant with: AES-256-GCM, SHA256, Curve25519/X25519

# Change ownership of all files in config folder
sudo chown -R strongswan:strongswan /home/strongswan/config/

# Load centralized variables
source /home/strongswan/versions.sh

# Clean config and logs folders
sudo rm -rf /home/strongswan/config/*

# Create CA cert folder
mkdir -p /home/strongswan/config/ca

# Generate CA certificate files using Ed25519 (Curve25519)
echo "Generating CA certificate files with Ed25519 (Curve25519)"
openssl genpkey -algorithm ED25519 -out /home/strongswan/config/ca/ca.key
openssl req -x509 -new -key /home/strongswan/config/ca/ca.key -days 3650 \
    -out /home/strongswan/config/ca/ca.crt \
    -subj "/C=SK/L=Kosice/O=Test/OU=Test/CN=StrongSwan"

# Generate server certificate files using Ed25519 (Curve25519)
echo "Generating server certificate files with Ed25519 (Curve25519)"
openssl genpkey -algorithm ED25519 -out /home/strongswan/config/server.key
openssl req -new -key /home/strongswan/config/server.key \
    -out /home/strongswan/config/server.csr \
    -subj "/C=SK/L=Kosice/O=Test/OU=Test/CN=cicd.strongswan.com"
openssl x509 -req -in /home/strongswan/config/server.csr \
    -CA /home/strongswan/config/ca/ca.crt \
    -CAkey /home/strongswan/config/ca/ca.key \
    -CAcreateserial \
    -out /home/strongswan/config/server.crt \
    -days 365

# Generate client private keys using Ed25519 (Curve25519)
echo "Generating client private keys with Ed25519 (Curve25519)"
for client in "${CLIENT_IMAGE_VERSIONS[@]}"; do
    openssl genpkey -algorithm ED25519 -out /home/strongswan/config/${client}.key
    echo "✓ Generated private key for ${client}"
done

# Generate client CSRs
echo "Generating client CSRs"
for client in "${CLIENT_IMAGE_VERSIONS[@]}"; do
    openssl req -new -key /home/strongswan/config/${client}.key \
        -out /home/strongswan/config/${client}.csr \
        -subj "/C=SK/L=Kosice/O=Test/OU=Test/CN=${client}.strongswan.com"
    echo "✓ Generated CSR for ${client}"
done

# Sign client CSRs and generate certificates
echo "Signing client CSRs and generating certificates"
for client in "${CLIENT_IMAGE_VERSIONS[@]}"; do
    openssl x509 -req -in /home/strongswan/config/${client}.csr \
        -CA /home/strongswan/config/ca/ca.crt \
        -CAkey /home/strongswan/config/ca/ca.key \
        -CAcreateserial \
        -out /home/strongswan/config/${client}.crt \
        -days 365
    echo "✓ Generated certificate for ${client}"
done

# Note: DH parameters are NOT needed when using ECC/ECDH
echo "Skipping DH parameters generation (not needed with ECDH)"

# Show generated files
echo "####"
echo "ls -lah /home/strongswan/config/ca/"
ls -lah /home/strongswan/config/ca/
echo "####"
echo "ls -lah /home/strongswan/config/"
ls -lah /home/strongswan/config/

# Verify certificate details
echo "####"
echo "Verifying CA certificate uses Ed25519:"
openssl x509 -in /home/strongswan/config/ca/ca.crt -text -noout | grep "Public Key Algorithm"
openssl x509 -in /home/strongswan/config/ca/ca.crt -text -noout | grep "ED25519"
echo "####"
echo "Verifying server certificate uses Ed25519:"
openssl x509 -in /home/strongswan/config/server.crt -text -noout | grep "Public Key Algorithm"
openssl x509 -in /home/strongswan/config/server.crt -text -noout | grep "ED25519"

# Wait for all background processes to finish
wait

echo "####"
echo "Certificate generation complete!"
echo "All certificates are using Ed25519 (Curve25519)"
echo "Generated certificates for CLIENT_IMAGE_VERSIONS: ${CLIENT_IMAGE_VERSIONS[*]}"
echo "Use 'ecdh-curve X25519' in your StrongSwan config for key exchange"