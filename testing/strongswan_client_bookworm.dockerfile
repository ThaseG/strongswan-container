FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    strongswan \
    net-tools \
    tcpdump \
    ethtool \
    iputils-ping \
    iproute2 \
    curl \
    wget \
    vim \
    nano \
    ssh \
    sudo \
    iptables \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Ensure /dev/net/tun exists
RUN mkdir -p /dev/net && \
    mknod /dev/net/tun c 10 200 && \
    chmod 666 /dev/net/tun

# Create home directory and necessary subdirectories for strongswan user (BEFORE switching users)
RUN mkdir -p /home/strongswan/config && \
    mkdir -p /home/strongswan/logs && \
    chown -R strongswan:strongswan /home/strongswan

# Allow the strongswan user to execute sudo commands without password
RUN echo 'strongswan ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set the working directory
WORKDIR /home/strongswan

# Send logs from strongswan to stdout (do this as root before switching users)
RUN ln -sf /dev/stdout /home/strongswan/logs/strongswan-client.log

# Copy the reload script to the container
COPY --chown=strongswan:strongswan testing/reload-client-bookworm.sh /home/strongswan/reload-client-bookworm.sh

# Ensure the script is executable
RUN chmod +x /home/strongswan/reload-client-bookworm.sh

# Switch to the strongswan user (do this LAST)
USER strongswan

# Set the entrypoint to the script
ENTRYPOINT ["/home/strongswan/reload-client-bookworm.sh"]