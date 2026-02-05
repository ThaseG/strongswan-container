# ============================================
# Stage 1: Build StrongSwan
# ============================================
# strongswan.dockerfile

FROM debian:12-slim AS strongswan-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV STRONGSWAN_VERSION=6.0.4

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
    libsystemd-dev \
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
        --with-systemdsystemunitdir=/lib/systemd/system \
        --enable-systemd \
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
        --enable-cmd && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /opt/strongswan

# Create a staging directory with all files we need
RUN mkdir -p /staging/usr/sbin /staging/usr/lib /staging/usr/share && \
    cp -a /usr/sbin/swanctl /usr/sbin/charon-systemd /staging/usr/sbin/ && \
    cp -a /usr/lib/ipsec /staging/usr/lib/ && \
    cp -a /usr/share/strongswan /staging/usr/share/ && \
    find /usr/lib -name "libcharon.so*" -exec cp -a {} /staging/usr/lib/ \; && \
    find /usr/lib -name "libstrongswan.so*" -exec cp -a {} /staging/usr/lib/ \; && \
    find /usr/lib -name "libvici.so*" -exec cp -a {} /staging/usr/lib/ \; && \
    ls -la /staging/usr/lib/

# ============================================
# Stage 2: Build Go Exporter
# ============================================

FROM golang:1.25-bookworm AS go-builder

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

LABEL maintainer="ThaseG"
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
    tini \
    && apt-get upgrade -y \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create strongswan user and group
RUN groupadd --system strongswan && \
    useradd --system --create-home --home-dir /home/strongswan --shell /bin/bash -g strongswan strongswan

# Create necessary directories with proper permissions
RUN mkdir -p \
    /etc/swanctl/conf.d \
    /etc/swanctl/x509 \
    /etc/swanctl/x509ca \
    /etc/swanctl/private \
    /etc/swanctl/rsa \
    /var/run/strongswan \
    /var/log/strongswan \
    /home/strongswan/exporter && \
    chown -R strongswan:strongswan \
        /etc/swanctl \
        /var/run/strongswan \
        /var/log/strongswan \
        /home/strongswan && \
    chmod 700 /etc/swanctl/private /etc/swanctl/rsa && \
    chmod 755 /etc/swanctl/x509 /etc/swanctl/x509ca

# Copy StrongSwan installation from staging directory
COPY --from=strongswan-builder /staging/usr/sbin/ /usr/sbin/
COPY --from=strongswan-builder /staging/usr/lib/ipsec/ /usr/lib/ipsec/
COPY --from=strongswan-builder /staging/usr/lib/libcharon.so* /usr/lib/
COPY --from=strongswan-builder /staging/usr/lib/libstrongswan.so* /usr/lib/
COPY --from=strongswan-builder /staging/usr/lib/libvici.so* /usr/lib/
COPY --from=strongswan-builder /staging/usr/share/strongswan/ /usr/share/strongswan/

# Copy Go exporter binary from builder
COPY --from=go-builder /build/strongswan-exporter /usr/local/bin/strongswan-exporter
RUN chmod +x /usr/local/bin/strongswan-exporter

# Copy entrypoint
COPY server/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create strongswan.conf
RUN echo 'charon-systemd { \n\
  load_modular = yes \n\
  plugins { \n\
    vici { \n\
      socket = unix:///var/run/strongswan/charon-vici.sock \n\
    } \n\
  } \n\
}' > /etc/strongswan.conf

# Run ldconfig to update library cache
RUN ldconfig

WORKDIR /home/strongswan

# Expose ports
EXPOSE 500/udp 4500/udp 9234/tcp

# Use volumes for configuration
VOLUME ["/etc/swanctl", "/var/log/strongswan"]

# Use tini as init system
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]