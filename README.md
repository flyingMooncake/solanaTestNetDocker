# Solana Private Test Network Docker

A Docker-based Solana private test network for development and testing purposes.

## Prerequisites

- Docker
- Docker Compose

## Quick Start

1. Make the manager script executable:
```bash
chmod +x manager.sh
```

2. Install prerequisites (Docker, Docker Compose):
```bash
./manager.sh --install
```

3. Initialize the network:
```bash
./manager.sh --init
```

4. Start the validator:
```bash
./manager.sh --validate
```

## Manager Script Commands

### `--install`
Check and install all prerequisites including Docker and Docker Compose. This command will:
- Detect your operating system (Ubuntu/Debian/CentOS/RHEL/Fedora)
- Install Docker if not present
- Install Docker Compose if not present
- Start and enable Docker daemon
- Add current user to docker group
- Install additional tools (curl, git)

```bash
./manager.sh --install
```

**Note:** After installation, you may need to log out and log back in for docker group permissions to take effect, or run `newgrp docker`.

### `--init`
Initialize a new Solana test network. This will:
- Build the Docker image
- Start the container
- Generate validator identity and vote account keypairs
- Create genesis configuration

```bash
./manager.sh --init
```

### `--validate`
Start the Solana validator

```bash
./manager.sh --validate
```

### `--validate -s`
Stop the validator (keeps container running)

```bash
./manager.sh --validate -s
```

### `--stops`
Stop the Docker container completely

```bash
./manager.sh --stops
```

### `--purge`
Delete all ledger data and configurations. This will prompt for confirmation.

```bash
./manager.sh --purge
```

### `--connect <ip:port>`
Connect to another Solana node to share validation and ledger data

```bash
./manager.sh --connect 192.168.1.100:8001
```

### `--status`
Show current network status

```bash
./manager.sh --status
```

### `--help`
Display help information

```bash
./manager.sh --help
```

## Network Endpoints

Once the validator is running, you can access:

- **RPC Endpoint**: http://localhost:8899
- **WebSocket**: ws://localhost:8900
- **Gossip Port**: 8001

## Interacting with the Network

### Using Solana CLI from host machine

Configure Solana CLI to use your local test network:
```bash
solana config set --url http://localhost:8899
```

### Using Solana CLI from inside container

```bash
docker exec -it solana-testnet bash
solana --url http://localhost:8899 cluster-version
```

### Check validator logs

```bash
docker exec solana-testnet tail -f /solana/validator.log
```

## Data Persistence

All data is stored in the `./data` directory:
- `./data/ledger` - Blockchain ledger data
- `./data/config` - Validator keypairs and configuration
- `./data/accounts` - Account data

## Connecting Multiple Nodes

To create a multi-node test network:

1. On the first node (bootstrap node):
```bash
./manager.sh --init
./manager.sh --validate
```

2. Get the IP address of the first node

3. On additional nodes:
```bash
./manager.sh --init
./manager.sh --connect <first-node-ip>:8001
```

## Troubleshooting

### Check if validator is running
```bash
docker exec solana-testnet pgrep -f solana-test-validator
```

### View validator logs
```bash
docker exec solana-testnet cat /solana/validator.log
```

### Restart everything
```bash
./manager.sh --stops
./manager.sh --validate
```

### Complete reset
```bash
./manager.sh --purge
./manager.sh --init
./manager.sh --validate
```

## Port Configuration

The following ports are exposed:
- 8001: Gossip protocol
- 8899: JSON RPC
- 8900: PubSub WebSocket
- 8003: TVU (Transaction Verification Unit)
- 8004: TPU (Transaction Processing Unit)

Make sure these ports are available on your system.
