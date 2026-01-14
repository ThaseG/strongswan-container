# Use the official Debian base image
FROM debian:bullseye

# Set environment variables to avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install required packages
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

# Create a non-root user for running StrongSwan
RUN groupadd strongswan
RUN useradd -m -s /bin/bash strongswan -g strongswan

# Ensure /dev/net/tun exists
RUN mkdir -p /dev/net && \
    mknod /dev/net/tun c 10 200 && \
    chmod 666 /dev/net/tun

# Allow the strongswan user to execute sudo commands without password
RUN echo 'strongswan ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Switch to the strongswan user
USER strongswan

# Create directory for StrongSwan configuration & logs
RUN mkdir -p /home/strongswan/config
RUN mkdir -p /home/strongswan/logs

# Set the working directory
WORKDIR /home/strongswan

# Send logs from strongswan to stdout
RUN ln -sf /dev/stdout /home/strongswan/logs/strongswan-client.log

# Copy the reload script to the container
COPY --chown=strongswan:strongswan testing/reload-client-bullseye.sh /home/strongswan/reload-client-bullseye.sh

# Ensure the script is executable
RUN chmod +x /home/strongswan/reload-client-bullseye.sh

# Set the entrypoint to the script
ENTRYPOINT ["/home/strongswan/reload-client-bullseye.sh"]
