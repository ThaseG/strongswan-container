# Use the official Debian base image
FROM debian:12.12

# Set environment variables to avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    net-tools \
    tcpdump \
    ethtool \
    openssl \
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

# Copy supporting scripts to the container
COPY --chown=strongswan:strongswan versions.sh /home/strongswan/versions.sh
COPY --chown=strongswan:strongswan testing/generate_ca_and_certs.sh /home/strongswan/generate_ca_and_certs.sh
COPY --chown=strongswan:strongswan testing/generate_server_config.sh /home/strongswan/generate_server_config.sh
COPY --chown=strongswan:strongswan testing/generate_client_config.sh /home/strongswan/generate_client_config.sh

# Copy the reload entrypoint script to the container
COPY --chown=strongswan:strongswan testing/reload-generator.sh /home/strongswan/reload-generator.sh

# Ensure the script is executable
RUN chmod +x /home/strongswan/reload-generator.sh

# Set the entrypoint to the script
ENTRYPOINT ["/home/strongswan/reload-generator.sh"]
