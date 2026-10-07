#!/bin/bash
# generate_ca_and_certs.sh
#
# Creates an Ed25519 test PKI in ${CONFIG_DIR}/pki: one CA, one server
# certificate and one certificate per test client. strongSwan matches IKE
# identities against subjectAltName (not the CN), so every leaf gets a SAN.

set -euo pipefail
cd "$(dirname "$0")"
source ./versions.sh

CONFIG_DIR="${CONFIG_DIR:-/config}"
PKI="${CONFIG_DIR}/pki"
SUBJECT_BASE="/C=SK/L=Kosice/O=Test/OU=Test"

# Start from an empty volume so stale material never leaks into a test run
rm -rf "${CONFIG_DIR:?}"/*
mkdir -p "$PKI"

echo "Generating CA (Ed25519)"
openssl genpkey -algorithm ED25519 -out "$PKI/ca.key"
openssl req -x509 -new -key "$PKI/ca.key" -days "$CA_VALIDITY_DAYS" \
    -subj "${SUBJECT_BASE}/CN=StrongSwan Test CA" \
    -out "$PKI/ca.crt"

# issue_cert <name> <common name> <subjectAltName>
issue_cert() {
    local name="$1" cn="$2" san="$3"

    openssl genpkey -algorithm ED25519 -out "$PKI/${name}.key"
    openssl req -new -key "$PKI/${name}.key" \
        -subj "${SUBJECT_BASE}/CN=${cn}" -out "$PKI/${name}.csr"
    printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\nsubjectAltName=%s\n' \
        "$san" > "$PKI/${name}.ext"
    openssl x509 -req -in "$PKI/${name}.csr" \
        -CA "$PKI/ca.crt" -CAkey "$PKI/ca.key" -CAcreateserial \
        -days "$CERT_VALIDITY_DAYS" -extfile "$PKI/${name}.ext" \
        -out "$PKI/${name}.crt"
    openssl verify -CAfile "$PKI/ca.crt" "$PKI/${name}.crt"
    echo "✓ Issued certificate for ${name} (${san})"
}

issue_cert server "$SERVER_ID" "DNS:${SERVER_ID},IP:${SERVER_EXTERNAL_IP}"

for client in "${CLIENT_IMAGE_VERSIONS[@]}"; do
    issue_cert "$client" "${client}.strongswan.com" "DNS:${client}.strongswan.com"
done

echo "Certificate generation complete"
