# test_helper.bash - shared helpers for the bats e2e suite

ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
# shellcheck source=../versions.sh
source "$ROOT/versions.sh"

SERVER=strongswan-server
EXPORTER_URL="http://${SERVER_EXTERNAL_IP}:${EXPORTER_PORT}"
VPN_POOL_PREFIX="${VPN_POOL%.*}."

# retry <seconds> <command...> - run command every second until it succeeds
retry() {
    local timeout="$1"; shift
    local deadline=$((SECONDS + timeout))
    until "$@" >/dev/null 2>&1; do
        if ((SECONDS >= deadline)); then
            echo "Timed out after ${timeout}s waiting for: $*"
            return 1
        fi
        sleep 1
    done
}

# assert_output_contains <text> - check the $output of the last `run`
assert_output_contains() {
    if [[ "$output" != *"$1"* ]]; then
        echo "Expected output to contain: $1"
        echo "Actual output:"
        echo "$output"
        return 1
    fi
}

# assert_output_matches <extended regex> - check the $output of the last `run`
assert_output_matches() {
    if ! grep -Eq -- "$1" <<<"$output"; then
        echo "Expected output to match: $1"
        echo "Actual output:"
        echo "$output"
        return 1
    fi
}

container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

# conn_loaded <container> <connection name>
conn_loaded() {
    docker exec "$1" swanctl --list-conns 2>/dev/null | grep -q "^$2:"
}

metrics() {
    curl -fsS --max-time 5 "${EXPORTER_URL}/metrics"
}
