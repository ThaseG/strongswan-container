# Ubuntu release for the build and runtime stages. 26.04 is the current LTS and
# what ubuntu:latest points to; pinned so a new release is a deliberate bump.
ARG UBUNTU_VERSION=26.04
# Go release for the exporter build (golang:<version>-trixie). CI passes
# GO_VERSION from versions.sh; keep this default in sync for local builds.
ARG GO_VERSION=1.27.2

# ============================================
# Stage 1: Build StrongSwan
# --------------------------------------------
# Built from the release tarball (verified by SHA-256) and installed
# into /build so the runtime stage copies only the install tree. CI passes
# STRONGSWAN_VERSION/STRONGSWAN_SHA256 from versions.sh; the defaults below
# are for local builds and must be kept in sync.
# ============================================
FROM ubuntu:${UBUNTU_VERSION} AS strongswan-builder

ARG STRONGSWAN_VERSION=6.1.0
ARG STRONGSWAN_SHA256=d9484eea319481bda86f992fa69cbdbdd9c0d6f8b9a4bd793a7df45c0760d963

ENV DEBIAN_FRONTEND=noninteractive

# build-essential       - gcc, make, binutils (strip)
# libssl-dev            - openssl plugin (sole crypto provider)
# libcurl4-openssl-dev  - curl fetcher plugin (CRL/OCSP retrieval)
# file                  - ELF detection for the strip step
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential pkg-config ca-certificates curl file \
        libssl-dev libcurl4-openssl-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src

RUN set -eux; \
    curl -fsSL -o strongswan.tar.gz \
        "https://download.strongswan.org/strongswan-${STRONGSWAN_VERSION}.tar.gz"; \
    echo "${STRONGSWAN_SHA256}  strongswan.tar.gz" | sha256sum -c -; \
    tar -xzf strongswan.tar.gz; \
    rm strongswan.tar.gz

WORKDIR /usr/src/strongswan-${STRONGSWAN_VERSION}

# The full plugin set (every plugin explicitly enabled or disabled) lives in
# configure-strongswan.sh.
COPY server/configure-strongswan.sh /usr/local/bin/configure-strongswan.sh

RUN set -eux; \
    bash /usr/local/bin/configure-strongswan.sh; \
    make -j"$(nproc)"; \
    make install DESTDIR=/build

# Strip ELF files, drop libtool archives and man pages, and make sure nothing
# lands on /var/run (a symlink to /run in the runtime image).
RUN set -eux; \
    find /build -type f -exec sh -c \
        'file -b "$1" | grep -q "^ELF" && strip --strip-unneeded "$1" || true' _ {} \; ; \
    find /build -name '*.la' -delete; \
    rm -rf /build/usr/share/man /build/var/run /build/run; \
    test -x /build/usr/lib/ipsec/charon; \
    test -x /build/usr/sbin/swanctl; \
    test -f /build/etc/swanctl/swanctl.conf

# ============================================
# Stage 2: Build Go Exporter
# ============================================
FROM golang:${GO_VERSION}-trixie AS go-builder

# Exporter release tag. CI passes EXPORTER_VERSION from versions.sh; keep
# this default in sync for local builds.
ARG EXPORTER_VERSION=v1.0.0
ARG TARGETOS=linux
ARG TARGETARCH=amd64

WORKDIR /build
# The exporter repo has no go.sum yet, so `go mod tidy` is still needed to
# resolve dependencies.
RUN set -eux; \
    git clone -q --depth 1 --branch "${EXPORTER_VERSION}" \
        https://github.com/ThaseG/strongswan-exporter . && \
    go mod tidy && \
    CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
        go build -trimpath -ldflags="-w -s" -o strongswan-exporter .

# ============================================
# Stage 3: Final Runtime Image
# ============================================
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive

# libssl3t64            - openssl plugin
# libcurl4t64           - curl fetcher plugin
# ca-certificates       - TLS verification for curl
# iproute2, iptables    - network tooling for updown scripts and debugging
# tini                  - PID 1, reaps zombies and forwards signals
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends \
        ca-certificates libssl3t64 libcurl4t64 \
        iproute2 iptables tini && \
    rm -rf /var/lib/apt/lists/*

COPY --from=strongswan-builder /build/ /
COPY --from=go-builder /build/strongswan-exporter /usr/local/bin/strongswan-exporter
COPY server/exporter.yml /etc/strongswan-exporter/exporter.yml
COPY server/entrypoint.sh /entrypoint.sh
COPY server/charon-logging.conf /etc/strongswan.d/charon-logging-container.conf

# Secrets directories must not be world readable.
RUN set -eux; \
    chmod 0755 /entrypoint.sh /usr/local/bin/strongswan-exporter; \
    mkdir -p /etc/swanctl/conf.d /etc/swanctl/x509 /etc/swanctl/x509ca \
             /etc/swanctl/private /etc/swanctl/rsa /etc/swanctl/ecdsa \
             /etc/swanctl/pkcs8; \
    chmod 0700 /etc/swanctl/private /etc/swanctl/rsa /etc/swanctl/ecdsa \
               /etc/swanctl/pkcs8

# Fail the build if charon, swanctl or any plugin is missing a shared library
# (plugins are dlopen()ed at runtime, so `charon --version` alone won't catch it).
RUN set -eux; \
    ! ldd /usr/lib/ipsec/charon /usr/sbin/swanctl \
          /usr/lib/ipsec/*.so /usr/lib/ipsec/plugins/*.so | grep 'not found'; \
    /usr/lib/ipsec/charon --version

EXPOSE 500/udp 4500/udp 9234/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD swanctl --stats >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
