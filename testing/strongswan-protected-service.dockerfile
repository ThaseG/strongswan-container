FROM debian:trixie-slim

# Host on the internal network that VPN clients must reach through the tunnel.
# Its default route points at the server, so replies to the VPN pool go back
# through IPsec.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        iputils-ping \
        iproute2 \
    && rm -rf /var/lib/apt/lists/*

ENV GATEWAY_IP=10.10.10.100

ENTRYPOINT ["/bin/sh", "-c", "set -e; ip route replace default via \"$GATEWAY_IP\"; ip route show; echo 'Protected service ready'; exec sleep infinity"]
