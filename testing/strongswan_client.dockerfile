# strongswan_client.dockerfile
#
# Test client using the distribution's own strongSwan packages, so the server
# is tested against the versions real users run. Build one image per distro:
#   docker build --build-arg BASE_IMAGE=debian:bookworm \
#       -f testing/strongswan_client.dockerfile -t strongswan-client-bookworm .
ARG BASE_IMAGE=debian:bookworm
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        strongswan-charon \
        strongswan-swanctl \
        libstrongswan-standard-plugins \
        libstrongswan-extra-plugins \
        libcharon-extra-plugins \
        iproute2 \
        iputils-ping \
        tini && \
    rm -rf /var/lib/apt/lists/*

COPY testing/strongswan_client_entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
