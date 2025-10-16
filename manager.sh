#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Solana Test Network Manager Script
# Usage: ./manager.sh [OPTIONS]

CONTAINER_NAME="solana-testnet"
LEDGER_DIR="./data/ledger"
CONFIG_DIR="./data/config"
ACCOUNTS_DIR="./data/accounts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 3
    fi
}

# Detect docker-compose command
get_docker_compose_cmd() {
    local cmd=""
    if docker compose version &> /dev/null; then
        cmd="docker compose"
    elif command -v docker-compose &> /dev/null; then
        cmd="docker-compose"
    else
        print_error "Docker Compose is not installed. Please run: ./manager.sh --install"
        exit 3
    fi
    
    # Validate the command works
    if ! $cmd version &> /dev/null; then
        print_error "Docker Compose command validation failed"
        exit 3
    fi
    
    echo "$cmd"
}

# Install prerequisites
install_prerequisites() {
    print_info "Checking and installing prerequisites..."
    echo ""
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS="${ID:-unknown}"
        VERSION="${VERSION_ID:-unknown}"
    else
        print_error "Cannot detect OS. Please install Docker and Docker Compose manually."
        exit 1
    fi
    
    print_info "Detected OS: $OS $VERSION"
    echo ""
    
    # Check if running as root or with sudo
    if [[ "$EUID" -ne 0 ]]; then
        print_warning "This script needs sudo privileges to install packages."
        SUDO="sudo"
    else
        SUDO=""
    fi
    
    # Check Docker
    print_info "Checking Docker..."
    if command -v docker &> /dev/null; then
        local docker_version
        docker_version=$(docker --version || echo "Unknown version")
        print_info "Docker is already installed: $docker_version"
    else
        print_warning "Docker is not installed. Installing Docker..."
        
        case "$OS" in
            ubuntu|debian)
                $SUDO apt-get update
                $SUDO apt-get install -y ca-certificates curl gnupg lsb-release
                $SUDO install -m 0755 -d /etc/apt/keyrings
                curl -fsSL "https://download.docker.com/linux/$OS/gpg" | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
                $SUDO apt-get update
                $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                print_info "Docker installed successfully!"
                ;;
            centos|rhel|fedora)
                $SUDO yum install -y yum-utils
                $SUDO yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                $SUDO yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                $SUDO systemctl start docker
                $SUDO systemctl enable docker
                print_info "Docker installed successfully!"
                ;;
            *)
                print_error "Unsupported OS: $OS"
                print_info "Please install Docker manually from: https://docs.docker.com/engine/install/"
                exit 1
                ;;
        esac
    fi
    
    # Check if Docker daemon is running
    print_info "Checking Docker daemon..."
    if ! docker info > /dev/null 2>&1; then
        print_warning "Docker daemon is not running. Starting Docker..."
        $SUDO systemctl start docker
        $SUDO systemctl enable docker
        sleep 3
        
        if docker info > /dev/null 2>&1; then
            print_info "Docker daemon started successfully!"
        else
            print_error "Failed to start Docker daemon. Please start it manually."
            exit 1
        fi
    else
        print_info "Docker daemon is running."
    fi
    
    # Check Docker Compose
    print_info "Checking Docker Compose..."
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        print_info "Docker Compose is already installed: $COMPOSE_VERSION"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version)
        print_info "Docker Compose is already installed: $COMPOSE_VERSION"
    else
        print_warning "Docker Compose is not installed. Installing Docker Compose..."
        
        case $OS in
            ubuntu|debian)
                $SUDO apt-get update
                $SUDO apt-get install -y docker-compose-plugin
                print_info "Docker Compose installed successfully!"
                ;;
            centos|rhel|fedora)
                $SUDO yum install -y docker-compose-plugin
                print_info "Docker Compose installed successfully!"
                ;;
            *)
                # Install standalone docker-compose
                print_info "Installing standalone Docker Compose..."
                COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
                $SUDO curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                $SUDO chmod +x /usr/local/bin/docker-compose
                print_info "Docker Compose installed successfully!"
                ;;
        esac
    fi
    
    # Add current user to docker group
    if [[ "$EUID" -ne 0 ]]; then
        print_info "Adding current user to docker group..."
        if groups "$USER" | grep -q '\bdocker\b'; then
            print_info "User $USER is already in docker group."
        else
            $SUDO usermod -aG docker "$USER"
            print_warning "User $USER added to docker group."
            print_warning "You need to log out and log back in for this to take effect."
            print_warning "Or run: newgrp docker"
        fi
    fi
    
    # Check other useful tools
    print_info "Checking additional tools..."
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        print_warning "curl is not installed. Installing..."
        case "$OS" in
            ubuntu|debian)
                $SUDO apt-get install -y curl
                ;;
            centos|rhel|fedora)
                $SUDO yum install -y curl
                ;;
        esac
    else
        print_info "curl is installed."
    fi
    
    # Check git
    if ! command -v git &> /dev/null; then
        print_warning "git is not installed. Installing..."
        case "$OS" in
            ubuntu|debian)
                $SUDO apt-get install -y git
                ;;
            centos|rhel|fedora)
                $SUDO yum install -y git
                ;;
        esac
    else
        print_info "git is installed."
    fi
    
    echo ""
    print_info "Prerequisites check completed!"
    echo ""
    print_info "Summary:"
    echo "  ✓ Docker: $(docker --version 2>/dev/null || echo 'Installed')"
    echo "  ✓ Docker Compose: $(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo 'Installed')"
    echo "  ✓ curl: $(curl --version 2>/dev/null | head -n1 || echo 'Installed')"
    echo "  ✓ git: $(git --version 2>/dev/null || echo 'Installed')"
    echo ""
    print_info "You can now run: ./manager.sh --init"
}

# Initialize new network
init_network() {
    print_info "Initializing new Solana test network..."
    
    # Get docker-compose command
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    
    # Create necessary directories
    mkdir -p "$LEDGER_DIR" "$CONFIG_DIR" "$ACCOUNTS_DIR"
    
    # Build and start the container
    print_info "Building Docker image..."
    $compose_cmd build
    
    print_info "Starting container..."
    $compose_cmd up -d
    
    # Wait for container to be ready
    sleep 3
    
    # Solana binary path
    local solana_bin="/root/.local/share/solana/install/active_release/bin"
    
    # Generate validator identity
    print_info "Generating validator identity..."
    docker exec "$CONTAINER_NAME" "$solana_bin/solana-keygen" new --no-bip39-passphrase -o /solana/config/validator-keypair.json --force
    
    # Generate vote account
    print_info "Generating vote account..."
    docker exec "$CONTAINER_NAME" "$solana_bin/solana-keygen" new --no-bip39-passphrase -o /solana/config/vote-account-keypair.json --force
    
    # Generate stake account
    print_info "Generating stake account..."
    docker exec "$CONTAINER_NAME" "$solana_bin/solana-keygen" new --no-bip39-passphrase -o /solana/accounts/stake-account.json --force
    
    # Create genesis config
    print_info "Creating genesis configuration..."
    docker exec "$CONTAINER_NAME" bash -c "cd /solana/ledger && $solana_bin/solana-genesis \
        --ledger /solana/ledger \
        --faucet-lamports 500000000000000000 \
        --bootstrap-validator \
        /solana/config/validator-keypair.json \
        /solana/config/vote-account-keypair.json \
        /solana/accounts/stake-account.json"
    
    print_info "Network initialized successfully!"
    local validator_pubkey
    validator_pubkey=$(docker exec "$CONTAINER_NAME" "$solana_bin/solana-keygen" pubkey /solana/config/validator-keypair.json 2>/dev/null || echo "Unknown")
    print_info "Validator identity: $validator_pubkey"
}

# Start validator
start_validator() {
    print_info "Starting Solana validator..."
    
    # Get docker-compose command
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    
    # Check if container is running
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        print_error "Container is not running. Starting container first..."
        $compose_cmd up -d
        sleep 3
    fi
    
    # Check if validator is already running
    if docker exec "$CONTAINER_NAME" pgrep -f solana-test-validator > /dev/null 2>&1; then
        print_warning "Validator is already running!"
        return
    fi
    
    # Start the validator
    print_info "Launching validator process..."
    docker exec -d "$CONTAINER_NAME" bash -c "solana-test-validator \
        --ledger /solana/ledger \
        --rpc-port 8899 \
        --bind-address 0.0.0.0 \
        --gossip-port 8001 \
        --dynamic-port-range 8002-8020 \
        > /solana/validator.log 2>&1"
    
    sleep 5
    
    # Verify validator is running
    if docker exec "$CONTAINER_NAME" pgrep -f solana-test-validator > /dev/null 2>&1; then
        print_info "Validator started successfully!"
        print_info "RPC endpoint: http://localhost:8899"
        print_info "Check logs: docker exec $CONTAINER_NAME tail -f /solana/validator.log"
    else
        print_error "Failed to start validator. Check logs for details."
        exit 1
    fi
}

# Stop validator
stop_validator() {
    print_info "Stopping Solana validator..."
    
    if docker exec "$CONTAINER_NAME" pgrep -f solana-test-validator > /dev/null 2>&1; then
        docker exec "$CONTAINER_NAME" pkill -f solana-test-validator
        sleep 2
        print_info "Validator stopped successfully!"
    else
        print_warning "Validator is not running."
    fi
}

# Pause validator
pause_validator() {
    print_info "Pausing Solana validator..."
    
    # Get the PID of the validator process
    local pid
    pid=$(docker exec "$CONTAINER_NAME" pgrep -f "solana-test-validator\|solana-validator" 2>/dev/null || echo "")
    
    if [[ -z "$pid" ]]; then
        print_warning "Validator is not running."
        return
    fi
    
    # Validate PID is numeric
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        print_error "Invalid PID retrieved: $pid"
        return
    fi
    
    # Send SIGSTOP to pause the process
    if docker exec "$CONTAINER_NAME" kill -STOP "$pid"; then
        print_info "Validator paused successfully (PID: $pid)"
        print_info "Process is suspended but still in memory"
        print_info "To resume: ./manager.sh --validate -r"
    else
        print_error "Failed to pause validator"
        exit 1
    fi
}

# Resume validator
resume_validator() {
    print_info "Resuming Solana validator..."
    
    # Get the PID of the validator process
    local pid
    pid=$(docker exec "$CONTAINER_NAME" pgrep -f "solana-test-validator\|solana-validator" 2>/dev/null || echo "")
    
    if [[ -z "$pid" ]]; then
        print_warning "Validator is not running."
        return
    fi
    
    # Validate PID is numeric
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        print_error "Invalid PID retrieved: $pid"
        return
    fi
    
    # Send SIGCONT to resume the process
    if docker exec "$CONTAINER_NAME" kill -CONT "$pid"; then
        print_info "Validator resumed successfully (PID: $pid)"
        print_info "Process is now active again"
    else
        print_error "Failed to resume validator"
        exit 1
    fi
}

# Stop Docker container
stop_docker() {
    print_info "Stopping Docker container..."
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    $compose_cmd down
    print_info "Container stopped successfully!"
}

# Purge all data
purge_data() {
    print_warning "This will delete all ledger data and configurations!"
    local confirm
    read -t 30 -p "Are you sure? (yes/no): " confirm || confirm="no"
    
    if [[ "$confirm" != "yes" ]]; then
        print_info "Purge cancelled."
        return
    fi
    
    print_info "Stopping validator and container..."
    stop_validator || true
    stop_docker || true
    
    print_info "Removing data directories..."
    rm -rf "$LEDGER_DIR" "$CONFIG_DIR" "$ACCOUNTS_DIR"
    
    print_info "Purge completed successfully!"
}

# Connect to another node
connect_node() {
    local node_address="$1"
    
    if [[ -z "$node_address" ]]; then
        print_error "Node address is required. Usage: --connect <ip:port>"
        exit 2
    fi
    
    # Validate node address format (basic IP:port validation)
    if ! [[ "$node_address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{1,5}$ ]]; then
        print_error "Invalid node address format. Expected: IP:PORT (e.g., 192.168.1.100:8001)"
        exit 2
    fi
    
    print_info "Connecting to node at $node_address as RPC-only (non-validating)..."
    
    # Stop current validator if running
    if docker exec "$CONTAINER_NAME" pgrep -f "solana-validator\|solana-test-validator" > /dev/null 2>&1; then
        print_info "Stopping current validator..."
        docker exec "$CONTAINER_NAME" pkill -f "solana-validator\|solana-test-validator"
        sleep 2
    fi
    
    # Ensure validator identity exists
    if [[ ! -f "$CONFIG_DIR/validator-keypair.json" ]]; then
        print_info "Validator identity not found. Generating one..."
        mkdir -p "$CONFIG_DIR"
        local solana_bin="/root/.local/share/solana/install/active_release/bin"
        docker exec "$CONTAINER_NAME" "$solana_bin/solana-keygen" new \
            --no-bip39-passphrase -o /solana/config/validator-keypair.json --force
    fi
    
    # Start as RPC node (non-validating) with entrypoint
    print_info "Starting RPC node connected to $node_address..."
    local solana_bin="/root/.local/share/solana/install/active_release/bin"
    docker exec -d "$CONTAINER_NAME" bash -c "$solana_bin/solana-validator \
        --identity /solana/config/validator-keypair.json \
        --ledger /solana/ledger \
        --rpc-port 8899 \
        --rpc-bind-address 0.0.0.0 \
        --gossip-port 8001 \
        --dynamic-port-range 8002-8020 \
        --entrypoint $node_address \
        --no-voting \
        --no-os-network-limits-test \
        --enable-rpc-transaction-history \
        --enable-cpi-and-log-storage \
        > /solana/validator.log 2>&1"
    
    sleep 5
    
    if docker exec "$CONTAINER_NAME" pgrep -f solana-validator > /dev/null 2>&1; then
        print_info "RPC node connected to $node_address successfully!"
        print_info "Node is syncing blocks (non-validating mode)"
        print_info "RPC endpoint: http://localhost:8899"
        print_info "Check logs: docker exec $CONTAINER_NAME tail -f /solana/validator.log"
    else
        print_error "Failed to connect. Check logs for details."
        docker exec "$CONTAINER_NAME" tail -20 /solana/validator.log || true
        exit 1
    fi
}

# Set validator key
set_validator_key() {
    local key_file="$1"
    local key_type="${2:-validator}"  # validator, vote, or stake
    
    # Validate key type
    if ! [[ "$key_type" =~ ^(validator|vote|stake)$ ]]; then
        print_error "Invalid key type. Use: validator, vote, or stake"
        exit 2
    fi
    
    print_info "Setting $key_type keypair..."
    echo ""
    
    # Check if container is running
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        print_error "Container is not running. Please start it first with: ./manager.sh --init"
        exit 3
    fi
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    if [[ -z "$key_file" ]]; then
        # Generate new key
        print_info "No key file provided. Generating new $key_type keypair..."
        
        case "$key_type" in
            validator)
                docker exec "$CONTAINER_NAME" solana-keygen new --no-bip39-passphrase -o /solana/config/validator-keypair.json --force
                print_info "New validator keypair generated!"
                local pubkey
                pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/config/validator-keypair.json 2>/dev/null || echo "Unknown")
                print_info "Public key: $pubkey"
                ;;
            vote)
                docker exec "$CONTAINER_NAME" solana-keygen new --no-bip39-passphrase -o /solana/config/vote-account-keypair.json --force
                print_info "New vote account keypair generated!"
                local pubkey
                pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/config/vote-account-keypair.json 2>/dev/null || echo "Unknown")
                print_info "Public key: $pubkey"
                ;;
            stake)
                docker exec "$CONTAINER_NAME" solana-keygen new --no-bip39-passphrase -o /solana/accounts/stake-account.json --force
                print_info "New stake account keypair generated!"
                local pubkey
                pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/accounts/stake-account.json 2>/dev/null || echo "Unknown")
                print_info "Public key: $pubkey"
                ;;
        esac
    else
        # Import existing key - sanitize filename
        local safe_key_file
        safe_key_file=$(realpath "$key_file" 2>/dev/null || echo "$key_file")
        
        if [[ ! -f "$safe_key_file" ]]; then
            print_error "Key file not found: $key_file"
            exit 1
        fi
        
        print_info "Importing $key_type keypair from: $(basename "$safe_key_file")"
        
        case "$key_type" in
            validator)
                cp "$safe_key_file" "$CONFIG_DIR/validator-keypair.json"
                docker exec "$CONTAINER_NAME" bash -c "cat > /solana/config/validator-keypair.json" < "$safe_key_file"
                print_info "Validator keypair imported successfully!"
                local pubkey
                pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/config/validator-keypair.json 2>/dev/null || echo "Unknown")
                print_info "Public key: $pubkey"
                ;;
            vote)
                cp "$safe_key_file" "$CONFIG_DIR/vote-account-keypair.json"
                docker exec "$CONTAINER_NAME" bash -c "cat > /solana/config/vote-account-keypair.json" < "$safe_key_file"
                print_info "Vote account keypair imported successfully!"
                local pubkey
                pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/config/vote-account-keypair.json 2>/dev/null || echo "Unknown")
                print_info "Public key: $pubkey"
                ;;
            stake)
                mkdir -p "$ACCOUNTS_DIR"
                cp "$safe_key_file" "$ACCOUNTS_DIR/stake-account.json"
                docker exec "$CONTAINER_NAME" bash -c "cat > /solana/accounts/stake-account.json" < "$safe_key_file"
                print_info "Stake account keypair imported successfully!"
                local pubkey
                pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/accounts/stake-account.json 2>/dev/null || echo "Unknown")
                print_info "Public key: $pubkey"
                ;;
        esac
    fi
    
    echo ""
    print_warning "Note: If you've already initialized the network, you may need to run:"
    print_warning "  ./manager.sh --purge"
    print_warning "  ./manager.sh --init"
    print_warning "  ./manager.sh --validate"
}

# Export validator keys
export_keys() {
    local output_dir="${1:-.}"
    
    # Sanitize output directory
    output_dir=$(basename "$output_dir")
    
    print_info "Exporting validator keys to: $output_dir"
    echo ""
    
    # Check if container is running
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        print_error "Container is not running."
        exit 3
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Export keys
    if [[ -f "$CONFIG_DIR/validator-keypair.json" ]]; then
        cp "$CONFIG_DIR/validator-keypair.json" "$output_dir/validator-keypair.json"
        print_info "Validator keypair exported: $output_dir/validator-keypair.json"
        local pubkey
        pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/config/validator-keypair.json 2>/dev/null || echo 'N/A')
        print_info "  Public key: $pubkey"
    else
        print_warning "Validator keypair not found"
    fi
    
    if [[ -f "$CONFIG_DIR/vote-account-keypair.json" ]]; then
        cp "$CONFIG_DIR/vote-account-keypair.json" "$output_dir/vote-account-keypair.json"
        print_info "Vote account keypair exported: $output_dir/vote-account-keypair.json"
        local pubkey
        pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/config/vote-account-keypair.json 2>/dev/null || echo 'N/A')
        print_info "  Public key: $pubkey"
    else
        print_warning "Vote account keypair not found"
    fi
    
    if [[ -f "$ACCOUNTS_DIR/stake-account.json" ]]; then
        cp "$ACCOUNTS_DIR/stake-account.json" "$output_dir/stake-account.json"
        print_info "Stake account keypair exported: $output_dir/stake-account.json"
        local pubkey
        pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/accounts/stake-account.json 2>/dev/null || echo 'N/A')
        print_info "  Public key: $pubkey"
    else
        print_warning "Stake account keypair not found"
    fi
    
    echo ""
    print_info "Keys exported successfully!"
    print_warning "Keep these keys secure! Anyone with access to these files can control your validator."
}

# Show validator keys info
show_keys() {
    print_info "Validator Keys Information:"
    echo ""
    
    # Check if container is running
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        print_error "Container is not running."
        exit 3
    fi
    
    # Show validator key
    if [[ -f "$CONFIG_DIR/validator-keypair.json" ]]; then
        echo -e "${GREEN}Validator Identity:${NC}"
        echo "  Location: $CONFIG_DIR/validator-keypair.json"
        local validator_pubkey
        validator_pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/config/validator-keypair.json 2>/dev/null || echo "")
        if [[ -n "$validator_pubkey" ]]; then
            echo "  Public Key: $validator_pubkey"
        fi
        echo ""
    else
        echo -e "${RED}Validator Identity: Not found${NC}"
        echo ""
    fi
    
    # Show vote account key
    if [[ -f "$CONFIG_DIR/vote-account-keypair.json" ]]; then
        echo -e "${GREEN}Vote Account:${NC}"
        echo "  Location: $CONFIG_DIR/vote-account-keypair.json"
        local vote_pubkey
        vote_pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/config/vote-account-keypair.json 2>/dev/null || echo "")
        if [[ -n "$vote_pubkey" ]]; then
            echo "  Public Key: $vote_pubkey"
        fi
        echo ""
    else
        echo -e "${RED}Vote Account: Not found${NC}"
        echo ""
    fi
    
    # Show stake account key
    if [[ -f "$ACCOUNTS_DIR/stake-account.json" ]]; then
        echo -e "${GREEN}Stake Account:${NC}"
        echo "  Location: $ACCOUNTS_DIR/stake-account.json"
        local stake_pubkey
        stake_pubkey=$(docker exec "$CONTAINER_NAME" solana-keygen pubkey /solana/accounts/stake-account.json 2>/dev/null || echo "")
        if [[ -n "$stake_pubkey" ]]; then
            echo "  Public Key: $stake_pubkey"
        fi
        echo ""
    else
        echo -e "${RED}Stake Account: Not found${NC}"
        echo ""
    fi
}

# Show status
show_status() {
    print_info "Solana Test Network Status:"
    echo ""
    
    # Check container status
    if docker ps | grep -q "$CONTAINER_NAME"; then
        echo -e "Container: ${GREEN}Running${NC}"
    else
        echo -e "Container: ${RED}Stopped${NC}"
    fi
    
    # Check validator status
    if docker ps | grep -q "$CONTAINER_NAME" && docker exec "$CONTAINER_NAME" pgrep -f solana-test-validator > /dev/null 2>&1; then
        echo -e "Validator: ${GREEN}Running${NC}"
        
        # Try to get validator info
        if docker exec "$CONTAINER_NAME" solana --url http://localhost:8899 cluster-version > /dev/null 2>&1; then
            echo ""
            docker exec "$CONTAINER_NAME" solana --url http://localhost:8899 cluster-version || true
        fi
    else
        echo -e "Validator: ${RED}Stopped${NC}"
    fi
    
    echo ""
    echo "Data directories:"
    echo "  Ledger: $LEDGER_DIR"
    echo "  Config: $CONFIG_DIR"
    echo "  Accounts: $ACCOUNTS_DIR"
}

# Show help
show_help() {
    cat << EOF
Solana Test Network Manager

Usage: ./manager.sh [OPTION]

Options:
  --install                    Check and install prerequisites (Docker, Docker Compose)
  --init                       Initialize new network (creates genesis and keys)
  --validate                   Start validator
  --stop                       Stop Docker container
  --validate -s                Stop validator only
  --purge                      Delete all ledger data and configurations
  --connect <ip:port>          Connect to another node and share validation
  --set-key [file] [type]      Set/import validator key (types: validator, vote, stake)
  --export-keys [directory]    Export all validator keys to directory
  --show-keys                  Display validator keys information
  --status                     Show current network status
  --help                       Show this help message

Key Management Examples:
  ./manager.sh --set-key                              # Generate new validator key
  ./manager.sh --set-key my-key.json validator        # Import validator key
  ./manager.sh --set-key my-vote.json vote            # Import vote account key
  ./manager.sh --export-keys ./backup                 # Export all keys to backup folder
  ./manager.sh --show-keys                            # Show current keys info

General Examples:
  ./manager.sh --install
  ./manager.sh --init
  ./manager.sh --validate
  ./manager.sh --validate -s
  ./manager.sh --stop
  ./manager.sh --connect 192.168.1.100:8001
  ./manager.sh --purge

EOF
}

# Main script logic
case "$1" in
    --install)
        install_prerequisites
        ;;
    --init)
        check_docker
        init_network
        ;;
    --validate)
        check_docker
        if [[ "$2" == "-s" ]]; then
            stop_validator
        elif [[ "$2" == "-p" ]]; then
            pause_validator
        elif [[ "$2" == "-r" ]]; then
            resume_validator
        else
            start_validator
        fi
        ;;
    --stop)
        check_docker
        stop_docker
        ;;
    --purge)
        check_docker
        purge_data
        ;;
    --connect)
        check_docker
        connect_node "$2"
        ;;
    --set-key)
        check_docker
        set_validator_key "$2" "$3"
        ;;
    --export-keys)
        check_docker
        export_keys "$2"
        ;;
    --show-keys)
        check_docker
        show_keys
        ;;
    --status)
        check_docker
        show_status
        ;;
    --help|*)
        show_help
        ;;
esac
