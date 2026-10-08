#!/bin/bash
# e2e.sh - manage the end-to-end test environment
#
# Usage:
#   testing/e2e.sh up            build test images and start the topology
#   testing/e2e.sh logs <dir>    dump container logs and IPsec state into <dir>
#   testing/e2e.sh connect       (re)connect all clients to the server
#   testing/e2e.sh down          remove everything this script created
#
# The server image is not built here; CI builds it in a separate job.
# Override with SERVER_IMAGE=... for local runs.
#
# The server publishes IKE (500/udp, 4500/udp) and the exporter (9234/tcp) on
# all host interfaces so devices outside the runner can connect. Set
# PUBLISH_PORTS=false to keep it reachable only from the Docker networks.
#
#   clients (192.168.200.0/24) --IPsec--> server --> protected service (10.10.10.0/24)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/versions.sh"

SERVER_IMAGE="${SERVER_IMAGE:-strongswan-server:latest}"
PUBLISH_PORTS="${PUBLISH_PORTS:-true}"
NET_EXTERNAL="strongswan_external"
NET_INTERNAL="strongswan_internal"
CONFIG_VOLUME="strongswan_configs"

containers() {
    echo strongswan-server strongswan-protected-service
    for client in "${CLIENT_IMAGE_VERSIONS[@]}"; do
        echo "strongswan-client-${client}"
    done
}

up() {
    docker network create --subnet="$EXTERNAL_NETWORK" "$NET_EXTERNAL"
    docker network create --subnet="$INTERNAL_NETWORK" "$NET_INTERNAL"
    docker volume create "$CONFIG_VOLUME"

    echo "::group::Generate PKI and swanctl configuration"
    docker build -t strongswan-generator -f "$ROOT/testing/strongswan_generator.dockerfile" "$ROOT"
    docker run --rm -v "$CONFIG_VOLUME":/config strongswan-generator
    echo "::endgroup::"

    echo "::group::Start server"
    local publish=()
    if [ "$PUBLISH_PORTS" = "true" ]; then
        publish=(-p 500:500/udp -p 4500:4500/udp -p "${EXPORTER_PORT}:${EXPORTER_PORT}/tcp")
    fi
    docker run -d --name strongswan-server \
        --network "$NET_EXTERNAL" --ip "$SERVER_EXTERNAL_IP" \
        "${publish[@]}" \
        --cap-add NET_ADMIN \
        --sysctl net.ipv4.ip_forward=1 \
        -v "$CONFIG_VOLUME":/config:ro \
        -e SWANCTL_DIR=/config/server \
        "$SERVER_IMAGE"
    docker network connect --ip "$SERVER_INTERNAL_IP" "$NET_INTERNAL" strongswan-server
    echo "::endgroup::"

    echo "::group::Start protected service"
    docker build -t strongswan-protected-service \
        -f "$ROOT/testing/strongswan-protected-service.dockerfile" "$ROOT"
    docker run -d --init --name strongswan-protected-service \
        --network "$NET_INTERNAL" --ip "$PROTECTED_SERVICE_IP" \
        --cap-add NET_ADMIN \
        -e GATEWAY_IP="$SERVER_INTERNAL_IP" \
        strongswan-protected-service
    echo "::endgroup::"

    for client in "${CLIENT_IMAGE_VERSIONS[@]}"; do
        echo "::group::Start client ${client} (${CLIENT_BASE_IMAGES[$client]})"
        docker build -t "strongswan-client-${client}" \
            --build-arg BASE_IMAGE="${CLIENT_BASE_IMAGES[$client]}" \
            -f "$ROOT/testing/strongswan_client.dockerfile" "$ROOT"
        docker run -d --name "strongswan-client-${client}" \
            --network "$NET_EXTERNAL" --ip "${CLIENT_IPS[$client]}" \
            --cap-add NET_ADMIN \
            -v "$CONFIG_VOLUME":/config:ro \
            -e SWANCTL_DIR="/config/${client}" \
            "strongswan-client-${client}"
        echo "::endgroup::"
    done
}

logs() {
    local dir="${1:?usage: e2e.sh logs <dir>}"
    mkdir -p "$dir"
    for c in $(containers); do
        docker logs "$c" > "$dir/${c}.log" 2>&1 || echo "(no container $c)" > "$dir/${c}.log"
        if docker exec "$c" true 2>/dev/null; then
            {
                echo "### ip addr";      docker exec "$c" ip addr
                echo "### ip route";     docker exec "$c" ip route show table all
                echo "### xfrm state";   docker exec "$c" ip xfrm state
                echo "### xfrm policy";  docker exec "$c" ip xfrm policy
                echo "### swanctl --list-sas"
                docker exec "$c" swanctl --list-sas 2>&1 || true
            } > "$dir/${c}.state.txt" 2>&1 || true
        fi
    done
}

connect() {
    # (Re)establish every client tunnel, e.g. to leave a working environment
    # behind after the tests restarted the server. Stale SAs are dropped first.
    local client c rc=0
    for client in "${CLIENT_IMAGE_VERSIONS[@]}"; do
        c="strongswan-client-${client}"
        docker exec "$c" swanctl --terminate --ike home --force --timeout 5 >/dev/null 2>&1 || true
        if docker exec "$c" swanctl --initiate --child protected --timeout 30 >/dev/null; then
            echo "✓ ${client} connected"
        else
            echo "✗ ${client} failed to connect"
            rc=1
        fi
    done
    return "$rc"
}

down() {
    for c in $(containers); do
        docker rm -f "$c" >/dev/null 2>&1 || true
    done
    docker network rm "$NET_EXTERNAL" "$NET_INTERNAL" >/dev/null 2>&1 || true
    docker volume rm "$CONFIG_VOLUME" >/dev/null 2>&1 || true
}

case "${1:-}" in
    up)   up ;;
    logs) logs "${2:-}" ;;
    connect) connect ;;
    down) down ;;
    *)    echo "usage: $0 up|logs <dir>|connect|down" >&2; exit 2 ;;
esac
