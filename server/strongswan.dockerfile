# ============================================
# Stage 1: Build StrongSwan
# ============================================
FROM debian:12-slim AS strongswan-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV STRONGSWAN_VERSION=6.0.4

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential autoconf automake python3-docutils libtool \
    libssl-dev libgmp-dev libpam0g-dev libcap-ng-dev libnl-3-dev \
    libnl-genl-3-dev pkg-config ca-certificates git wget gperf \
    libiptc-dev bison flex libsystemd-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

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
    make install

# Priprava staging adresara pre cisty prenos do finalneho image
RUN mkdir -p /staging/usr/sbin /staging/usr/lib /staging/usr/share /staging/etc/strongswan.d && \
    cp -a /usr/sbin/swanctl /usr/sbin/charon-systemd /staging/usr/sbin/ && \
    cp -a /usr/lib/ipsec /staging/usr/lib/ && \
    cp -a /usr/share/strongswan /staging/usr/share/ && \
    cp -r /etc/strongswan.d/* /staging/etc/strongswan.d/ && \
    find /usr/lib -name "libcharon.so*" -exec cp -a {} /staging/usr/lib/ \; && \
    find /usr/lib -name "libstrongswan.so*" -exec cp -a {} /staging/usr/lib/ \; && \
    find /usr/lib -name "libvici.so*" -exec cp -a {} /staging/usr/lib/ \;

# ============================================
# Stage 2: Build Go Exporter
# ============================================
FROM golang:1.25-bookworm AS go-builder
WORKDIR /build
RUN git clone https://github.com/ThaseG/strongswan-exporter /build && \
    go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -a -installsuffix cgo -ldflags="-w -s" \
    -o strongswan-exporter .

# ============================================
# Stage 3: Final Runtime Image
# ============================================
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Instalacia runtime zavislosti
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates libssl3t64 libgmp10 libpam0g libcap-ng0 \
    libnl-3-200 libnl-genl-3-200 iproute2 iptables kmod curl tini && \
    apt-get upgrade -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Uzivatel a adresarova struktura
RUN groupadd --system strongswan && \
    useradd --system --create-home --home-dir /home/strongswan --shell /bin/bash -g strongswan strongswan && \
    mkdir -p /etc/swanctl/conf.d /etc/swanctl/x509 /etc/swanctl/x509ca /etc/swanctl/private /etc/swanctl/rsa \
             /var/run/strongswan /var/log/strongswan /etc/strongswan.d && \
    chown -R strongswan:strongswan /etc/swanctl /var/run/strongswan /var/log/strongswan /home/strongswan && \
    chmod 700 /etc/swanctl/private /etc/swanctl/rsa

# Kopirovanie vsetkych komponentov zo stagingu a builderov
COPY --from=strongswan-builder /staging/etc/strongswan.d/ /etc/strongswan.d/
COPY --from=strongswan-builder /staging/usr/sbin/ /usr/sbin/
COPY --from=strongswan-builder /staging/usr/lib/ /usr/lib/
COPY --from=strongswan-builder /staging/usr/share/strongswan/ /usr/share/strongswan/
COPY --from=go-builder /build/strongswan-exporter /usr/local/bin/strongswan-exporter
COPY server/entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/strongswan-exporter /entrypoint.sh

# Vytvorenie hlavnej konfiguracie s definiciou VICI socketu
RUN echo 'charon-systemd {\n\
  load_modular = yes\n\
  plugins {\n\
    vici {\n\
      socket = unix:///var/run/strongswan/charon-vici.sock\n\
    }\n\
  }\n\
}' > /etc/strongswan.conf

# Aktualizacia cache kniznic
RUN ldconfig

WORKDIR /home/strongswan
EXPOSE 500/udp 4500/udp 9234/tcp
VOLUME ["/etc/swanctl", "/var/log/strongswan"]

WORKDIR /root
RUN chown -R root:root /etc/swanctl /var/run/strongswan /var/log/strongswan
USER root

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]