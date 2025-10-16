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
    && rm -rf /var/lib/apt/lists/*

# Install Solana CLI tools
RUN sh -c "$(curl -sSfL https://release.solana.com/v1.18.18/install)" && \
    /root/.local/share/solana/install/active_release/bin/solana --version

# Add Solana to PATH for all shells
ENV PATH="/root/.local/share/solana/install/active_release/bin:${PATH}"
RUN echo 'export PATH="/root/.local/share/solana/install/active_release/bin:$PATH"' >> /root/.bashrc

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
