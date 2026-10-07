# strongswan_generator.dockerfile
#
# One-shot container that writes the test PKI and swanctl configurations into
# the volume mounted at /config, then exits (non-zero on any failure).
FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /generator

COPY versions.sh \
     testing/generate_ca_and_certs.sh \
     testing/generate_server_config.sh \
     testing/generate_client_config.sh \
     testing/reload-generator.sh \
     ./

RUN chmod +x ./*.sh

ENTRYPOINT ["/generator/reload-generator.sh"]
