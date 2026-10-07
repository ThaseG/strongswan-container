#!/bin/bash
# reload-generator.sh - generator container entrypoint

set -euo pipefail
cd "$(dirname "$0")"

./generate_ca_and_certs.sh
./generate_server_config.sh
./generate_client_config.sh

echo "Test configuration generated successfully"
