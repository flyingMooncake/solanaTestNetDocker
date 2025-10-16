FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    bzip2 \
    build-essential \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Update CA certificates
RUN update-ca-certificates

# Install Solana CLI tools - download tarball directly
RUN cd /tmp && \
    wget https://github.com/solana-labs/solana/releases/download/v1.18.18/solana-release-x86_64-unknown-linux-gnu.tar.bz2 && \
    tar jxf solana-release-x86_64-unknown-linux-gnu.tar.bz2 && \
    mkdir -p /root/.local/share/solana/install && \
    mv solana-release /root/.local/share/solana/install/active_release && \
    rm solana-release-x86_64-unknown-linux-gnu.tar.bz2

# Add Solana to PATH
ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"

# Create directories for ledger and configuration
RUN mkdir -p /solana/ledger /solana/config /solana/accounts

# Set working directory
WORKDIR /solana

# Expose Solana ports
# 8001: gossip
# 8899: RPC
# 8900: RPC pubsub
# 8003: TVU (Transaction Verification Unit)
# 8004: TPU (Transaction Processing Unit)
EXPOSE 8001 8899 8900 8003 8004

# Keep container running
CMD ["tail", "-f", "/dev/null"]
