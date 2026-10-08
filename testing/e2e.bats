#!/usr/bin/env bats
# e2e.bats - end-to-end tests for the strongSwan server image
#
# Expects the topology from `testing/e2e.sh up`. Tests run in file order and
# later tests build on earlier ones (tunnels are initiated before traffic is
# checked; the server is restarted and stopped last).
#
# Run: bats --report-formatter junit --output test-results testing/e2e.bats

bats_require_minimum_version 1.5.0
load test_helper

# --- Server -----------------------------------------------------------------

@test "server: container is running" {
    retry 30 container_running "$SERVER"
}

@test "server: charon answers on the VICI socket" {
    retry 30 docker exec "$SERVER" swanctl --stats
    run -0 docker exec "$SERVER" swanctl --stats
    assert_output_contains "uptime:"
}

@test "server: runs the strongSwan version from versions.sh" {
    run -0 docker exec "$SERVER" /usr/lib/ipsec/charon --version
    [ "$output" = "strongSwan ${STRONGSWAN_VERSION}" ] ||
        { echo "Expected 'strongSwan ${STRONGSWAN_VERSION}', got '$output'"; false; }
}

@test "server: connection 'rw' is loaded" {
    retry 30 conn_loaded "$SERVER" rw
    run -0 docker exec "$SERVER" swanctl --list-conns
    assert_output_contains "protected:"
}

@test "server: server and CA certificates are loaded" {
    run -0 docker exec "$SERVER" swanctl --list-certs
    assert_output_contains "CN=${SERVER_ID}"
    assert_output_contains "CN=StrongSwan Test CA"
    assert_output_contains "has private key"
}

@test "server: virtual IP pool is loaded" {
    run -0 docker exec "$SERVER" swanctl --list-pools
    assert_output_contains "rw_pool"
}

@test "server: IKE and exporter ports are published on the host" {
    [ "${PUBLISH_PORTS:-true}" = "true" ] || skip "PUBLISH_PORTS=false"
    run -0 docker port "$SERVER"
    assert_output_contains "500/udp ->"
    assert_output_contains "4500/udp ->"
    assert_output_contains "${EXPORTER_PORT}/tcp ->"
}

@test "server: IPv4 forwarding is enabled" {
    run -0 docker exec "$SERVER" cat /proc/sys/net/ipv4/ip_forward
    [ "$output" = "1" ]
}

@test "server: docker healthcheck reports healthy" {
    retry 90 bash -c "[ \"\$(docker inspect -f '{{.State.Health.Status}}' $SERVER)\" = healthy ]"
}

@test "exporter: /metrics reports strongSwan up" {
    retry 30 metrics
    run -0 metrics
    assert_output_matches '^probe_success\{.*\} 1$'
    assert_output_contains "strongswan_info{"
    assert_output_contains "version=\"${STRONGSWAN_VERSION}\""
}

# --- Clients (one set of tests per entry in CLIENT_IMAGE_VERSIONS) -------------

client_config_loaded() {
    local c="strongswan-client-$1"
    retry 60 conn_loaded "$c" home || { docker logs --tail 50 "$c"; false; }
}

client_establishes_tunnel() {
    run -0 docker exec "strongswan-client-$1" \
        swanctl --initiate --child protected --timeout 30
    run -0 docker exec "strongswan-client-$1" swanctl --list-sas --ike home
    assert_output_contains "ESTABLISHED"
    assert_output_contains "INSTALLED"
}

client_gets_virtual_ip() {
    run -0 docker exec "strongswan-client-$1" ip -4 -o addr show
    assert_output_contains "inet ${VPN_POOL_PREFIX}"
}

client_reaches_protected_service() {
    run -0 docker exec "strongswan-client-$1" \
        ping -c 3 -W 2 -s 1300 "$PROTECTED_SERVICE_IP"
}

client_traffic_uses_ipsec() {
    # Packet counters on the CHILD_SA prove the ping went through the tunnel
    run -0 docker exec "strongswan-client-$1" swanctl --list-sas --ike home
    assert_output_matches 'in .* [1-9][0-9]* packets'
    assert_output_matches 'out .* [1-9][0-9]* packets'
}

for client in "${CLIENT_IMAGE_VERSIONS[@]}"; do
    bats_test_function --description "client ${client}: configuration is loaded" \
        -- client_config_loaded "$client"
    bats_test_function --description "client ${client}: establishes IKE and CHILD SA" \
        -- client_establishes_tunnel "$client"
    bats_test_function --description "client ${client}: receives a virtual IP from ${VPN_POOL}" \
        -- client_gets_virtual_ip "$client"
    bats_test_function --description "client ${client}: reaches ${PROTECTED_SERVICE_IP} through the tunnel" \
        -- client_reaches_protected_service "$client"
    bats_test_function --description "client ${client}: traffic is carried by the CHILD SA" \
        -- client_traffic_uses_ipsec "$client"
done

# --- Server-side view of all clients -----------------------------------------

@test "server: one IKE SA per test client" {
    run -0 docker exec "$SERVER" swanctl --list-sas
    count=$(grep -c "ESTABLISHED" <<<"$output" || true)
    [ "$count" -eq "${#CLIENT_IMAGE_VERSIONS[@]}" ] ||
        { echo "Expected ${#CLIENT_IMAGE_VERSIONS[@]} IKE SAs, found $count"; echo "$output"; false; }
}

sessions_total_is() {
    metrics | grep -qx "strongswan_sessions_total $1"
}

@test "exporter: strongswan_sessions_total matches connected clients" {
    # The exporter serves a cache refreshed every 15s; wait for a refresh
    # that includes the most recently connected client.
    retry 40 sessions_total_is "${#CLIENT_IMAGE_VERSIONS[@]}" || true
    run -0 metrics
    assert_output_matches "^strongswan_sessions_total ${#CLIENT_IMAGE_VERSIONS[@]}$"
}

@test "exporter: /sessions_local responds" {
    run -0 curl -fsS --max-time 5 "${EXPORTER_URL}/sessions_local"
}

# --- Lifecycle (keep last: these disrupt running tunnels) ---------------------

@test "server: recovers after container restart" {
    run -0 docker restart "$SERVER"
    retry 30 conn_loaded "$SERVER" rw || { docker logs --tail 50 "$SERVER"; false; }
}

@test "server: stops cleanly within 10 seconds with exit code 0" {
    start=$SECONDS
    run -0 docker stop -t 30 "$SERVER"
    elapsed=$((SECONDS - start))
    exit_code=$(docker inspect -f '{{.State.ExitCode}}' "$SERVER")
    echo "stopped in ${elapsed}s with exit code ${exit_code}"
    if [ "$elapsed" -ge 10 ] || [ "$exit_code" -ne 0 ]; then
        echo "--- last server log lines ---"
        docker logs --tail 40 "$SERVER" 2>&1
        false
    fi
}

@test "server: starts again after a clean stop" {
    run -0 docker start "$SERVER"
    retry 30 conn_loaded "$SERVER" rw || { docker logs --tail 50 "$SERVER"; false; }
}
