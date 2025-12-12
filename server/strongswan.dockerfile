# ============================================
# Stage 1: Build StrongSwan
# ============================================

FROM debian:12-slim AS strongswan-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV STRONGSWAN_VERSION=6.0.3

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    automake \
    python3-docutils \
    libtool \
    libssl-dev \
    libgmp-dev \
    libpam0g-dev \
    libcap-ng-dev \
    libnl-3-dev \
    libnl-genl-3-dev \
    pkg-config \
    ca-certificates \
    git \
    wget \
    gperf \
    libiptc-dev \
    bison \
    flex \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download and build StrongSwan
RUN cd /opt && \
    git clone --depth 1 --branch ${STRONGSWAN_VERSION} https://github.com/strongswan/strongswan.git && \
    cd strongswan && \
    ./autogen.sh && \
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --libexecdir=/usr/lib \
        --enable-vici \
        --enable-swanctl \
        --enable-openssl \
        --enable-eap-identity \
        --enable-eap-md5 \
        --enable-eap-mschapv2 \
        --enable-eap-tls \
        --enable-eap-ttls \
        --enable-eap-peap \
        --enable-eap-dynamic \
        --enable-kernel-netlink \
        --enable-agent \
        --enable-xauth-eap \
        --enable-xauth-pam \
        --enable-bypass-lan \
        --enable-farp \
        --enable-connmark \
        --enable-forecast \
        --enable-cmd \
        --disable-charon \
        --disable-stroke \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /opt/strongswan

# ============================================
# Stage 2: Build Go Exporter
# ============================================

FROM golang:1.23-bookworm AS go-builder

WORKDIR /build

# Clone and build exporter
RUN git clone https://github.com/ThaseG/strongswan-exporter /build && \
    go mod tidy && \
    go mod download && \
    go mod verify && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -a -installsuffix cgo \
    -ldflags="-w -s" \
    -o strongswan-exporter .

# ============================================
# Stage 3: Final Runtime Image
# ============================================

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

LABEL maintainer="Andrej"
LABEL description="StrongSwan IKEv2 VPN Server with Prometheus Exporter"

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3t64 \
    libgmp10 \
    libpam0g \
    libcap-ng0 \
    libnl-3-200 \
    libnl-genl-3-200 \
    iproute2 \
    iptables \
    kmod \
    curl \
    supervisor \
    && apt-get upgrade -y \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create strongswan user and group
RUN groupadd --system strongswan --gid 1000 && \
    useradd --system --create-home --home-dir /home/strongswan --shell /bin/bash --uid 1000 -g strongswan strongswan

# Create necessary directories
RUN mkdir -p \
    /etc/swanctl/conf.d \
    /etc/swanctl/x509 \
    /etc/swanctl/x509ca \
    /etc/swanctl/private \
    /etc/swanctl/rsa \
    /var/run/strongswan \
    /var/log/strongswan \
    /home/strongswan/exporter && \
    chown -R strongswan:strongswan /etc/swanctl /var/run/strongswan /var/log/strongswan /home/strongswan

# Copy StrongSwan installation from builder
COPY --from=strongswan-builder /usr/sbin/swanctl /usr/sbin/charon-systemd /usr/sbin/
COPY --from=strongswan-builder /usr/lib/ipsec/ /usr/lib/ipsec/
COPY --from=strongswan-builder /usr/lib/libcharon.so* /usr/lib/libstrongswan.so* /usr/lib/libvici.so* /usr/lib/
COPY --from=strongswan-builder /usr/share/strongswan/ /usr/share/strongswan/

# Copy Go exporter binary from builder
COPY --from=go-builder /build/strongswan-exporter /home/strongswan/exporter/strongswan-exporter

# Copy configuration files
COPY --chown=strongswan:strongswan config/swanctl.conf /etc/swanctl/swanctl.conf
COPY --chown=strongswan:strongswan config/strongswan.conf /etc/strongswan.conf
COPY --chown=strongswan:strongswan config/exporter.yml /home/strongswan/exporter/config.yml
COPY --chown=strongswan:strongswan scripts/entrypoint.sh /entrypoint.sh
COPY --chown=root:root config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod +x /entrypoint.sh /home/strongswan/exporter/strongswan-exporter

# Set proper permissions
RUN chmod 644 /etc/swanctl/swanctl.conf /etc/strongswan.conf && \
    chmod 700 /etc/swanctl/private /etc/swanctl/rsa && \
    chmod 755 /etc/swanctl/x509 /etc/swanctl/x509ca

# Run ldconfig to update library cache
RUN ldconfig

WORKDIR /home/strongswan

# Expose ports
# 500/udp  - IKE (Internet Key Exchange)
# 4500/udp - NAT-T (NAT Traversal)
# 9234/tcp - Prometheus Exporter
EXPOSE 500/udp 4500/udp 9234/tcp

VOLUME ["/etc/swanctl"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]