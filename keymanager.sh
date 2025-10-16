#!/bin/bash

# Solana Key Manager Script
# Usage: ./keymanager.sh [OPTIONS]

CONTAINER_NAME="solana-testnet"
CONFIG_DIR="./data/config"
ACCOUNTS_DIR="./data/accounts"
CONTAINER_CONFIG_DIR="/solana/config"
CONTAINER_ACCOUNTS_DIR="/solana/accounts"
RPC_URL="http://localhost:8899"

# Helper function to print messages
print_info() {
    echo "[INFO] $1"
}

print_error() {
    echo "[ERROR] $1"
}

print_warning() {
    echo "[WARNING] $1"
}

print_key() {
    echo "[$1] $2"
}

# Check if container is running
check_container() {
    if ! docker ps | grep -q $CONTAINER_NAME; then
        print_error "Container is not running. Please start it first."
        exit 1
    fi
}

# Convert host path to container path
host_to_container_path() {
    local host_path="$1"
    echo "$host_path" | sed "s|$CONFIG_DIR|$CONTAINER_CONFIG_DIR|g; s|$ACCOUNTS_DIR|$CONTAINER_ACCOUNTS_DIR|g"
}

# Get all key files
get_key_files() {
    # Find all JSON files in both directories
    find "$CONFIG_DIR" "$ACCOUNTS_DIR" -type f -name "*.json" 2>/dev/null | sort
}

# Show all keys
show_keys() {
    print_info "Available Keys:"
    echo ""
    
    local index=1
    local found=0
    
    while IFS= read -r keyfile; do
        if [ -f "$keyfile" ]; then
            found=1
            local filename=$(basename "$keyfile")
            local container_path=$(host_to_container_path "$keyfile")
            local pubkey=$(docker exec $CONTAINER_NAME solana-keygen pubkey "$container_path" 2>/dev/null)
            
            print_key "$index" "$filename"
            echo "    Path: $keyfile"
            echo "    Public Key: $pubkey"
            echo ""
            ((index++))
        fi
    done < <(get_key_files)
    
    if [ $found -eq 0 ]; then
        print_warning "No keys found."
    fi
}

# Get key file by index
get_key_by_index() {
    local index=$1
    local keys=($(get_key_files))
    
    if [ $index -lt 1 ] || [ $index -gt ${#keys[@]} ]; then
        print_error "Invalid key index: $index. Valid range: 1-${#keys[@]}"
        exit 1
    fi
    
    echo "${keys[$((index-1))]}"
}

# Get balance by key index
get_balance_by_index() {
    local index=$1
    local keyfile=$(get_key_by_index $index)
    
    print_info "Getting balance for key #$index..."
    echo ""
    
    local pubkey=$(docker exec $CONTAINER_NAME solana-keygen pubkey "$keyfile" 2>/dev/null)
    local balance=$(docker exec $CONTAINER_NAME solana balance "$keyfile" --url $RPC_URL 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "Key #$index: $(basename "$keyfile")"
        echo "Public Key: $pubkey"
        echo "Balance: $balance"
    else
        print_error "Failed to get balance for key #$index"
    fi
}

# Get balance by public key
get_balance_by_pubkey() {
    local pubkey=$1
    
    print_info "Getting balance for public key: $pubkey"
    echo ""
    
    local balance=$(docker exec $CONTAINER_NAME solana balance "$pubkey" --url $RPC_URL 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "Public Key: $pubkey"
        echo "Balance: $balance"
    else
        print_error "Failed to get balance for public key: $pubkey"
    fi
}

# Send SOL
send_sol() {
    local sender_type=$1
    local sender_value=$2
    local receiver=$3
    local amount=$4
    
    local sender_keyfile=""
    
    # Determine sender keyfile
    if [ "$sender_type" == "-n" ]; then
        sender_keyfile=$(get_key_by_index $sender_value)
        print_info "Sending from key #$sender_value..."
    elif [ "$sender_type" == "-k" ]; then
        # Find keyfile by public key
        local keys=($(get_key_files))
        for keyfile in "${keys[@]}"; do
            local pubkey=$(docker exec $CONTAINER_NAME solana-keygen pubkey "$keyfile" 2>/dev/null)
            if [ "$pubkey" == "$sender_value" ]; then
                sender_keyfile=$keyfile
                break
            fi
        done
        
        if [ -z "$sender_keyfile" ]; then
            print_error "No keyfile found for public key: $sender_value"
            exit 1
        fi
        print_info "Sending from public key: $sender_value..."
    else
        print_error "Invalid sender type. Use -n for index or -k for public key."
        exit 1
    fi
    
    echo ""
    echo "Sender: $(basename "$sender_keyfile")"
    echo "Receiver: $receiver"
    echo "Amount: $amount SOL"
    echo ""
    
    # Execute transfer
    local result=$(docker exec $CONTAINER_NAME solana transfer \
        --from "$sender_keyfile" \
        "$receiver" \
        "$amount" \
        --url $RPC_URL \
        --allow-unfunded-recipient 2>&1)
    
    if [ $? -eq 0 ]; then
        print_info "Transfer successful!"
        echo "$result"
    else
        print_error "Transfer failed!"
        echo "$result"
    fi
}

# Show current block/slot
show_block() {
    print_info "Current Block Information:"
    echo ""
    
    # Get current slot
    local slot=$(docker exec $CONTAINER_NAME solana slot --url $RPC_URL 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "Current Slot: $slot"
    fi
    
    # Get block height
    local block_height=$(docker exec $CONTAINER_NAME solana block-height --url $RPC_URL 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "Block Height: $block_height"
    fi
    
    # Get epoch info
    echo ""
    echo "Epoch Information:"
    docker exec $CONTAINER_NAME solana epoch-info --url $RPC_URL 2>/dev/null
    
    # Get transaction count
    echo ""
    local tx_count=$(docker exec $CONTAINER_NAME solana transaction-count --url $RPC_URL 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "Total Transactions: $tx_count"
    fi
}

# Show specific block details
show_block_details() {
    local slot=$1
    
    print_info "Block Details for Slot: $slot"
    echo ""
    
    docker exec $CONTAINER_NAME solana block "$slot" --url $RPC_URL 2>/dev/null
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get block details for slot: $slot"
    fi
}

# Export private key
export_key() {
    local export_type=$1
    local export_value=$2
    local output_file=$3
    
    local keyfile=""
    
    # Determine which key to export
    if [ "$export_type" == "-n" ]; then
        keyfile=$(get_key_by_index $export_value)
        print_info "Exporting key #$export_value..."
    elif [ "$export_type" == "-pubkey" ]; then
        # Find keyfile by public key
        local keys=($(get_key_files))
        for kf in "${keys[@]}"; do
            local pubkey=$(docker exec $CONTAINER_NAME solana-keygen pubkey "$kf" 2>/dev/null)
            if [ "$pubkey" == "$export_value" ]; then
                keyfile=$kf
                break
            fi
        done
        
        if [ -z "$keyfile" ]; then
            print_error "No keyfile found for public key: $export_value"
            exit 1
        fi
        print_info "Exporting key with public key: $export_value..."
    else
        print_error "Invalid export type. Use -n for index or -pubkey for public key."
        exit 1
    fi
    
    # Determine output filename
    if [ -z "$output_file" ]; then
        local basename_key=$(basename "$keyfile" .json)
        output_file="exported-${basename_key}-$(date +%Y%m%d-%H%M%S).json"
    fi
    
    echo ""
    print_info "Exporting private key..."
    echo "Source: $(basename "$keyfile")"
    echo "Output: $output_file"
    echo ""
    
    # Copy the key file
    cp "$keyfile" "$output_file"
    
    if [ $? -eq 0 ]; then
        local pubkey=$(docker exec $CONTAINER_NAME solana-keygen pubkey "$keyfile" 2>/dev/null)
        
        print_info "Private key exported successfully!"
        echo ""
        echo "File: $output_file"
        echo "Public Key: $pubkey"
        echo ""
        print_warning "SECURITY WARNING"
        print_warning "This file contains your PRIVATE KEY!"
        print_warning "Keep it secure and never share it with anyone!"
        print_warning "Anyone with this file can control your funds!"
    else
        print_error "Failed to export private key."
    fi
}

# Import private key
import_key() {
    local import_file=$1
    local key_name=$2
    
    if [ -z "$import_file" ]; then
        print_error "Import file required. Usage: --import <file> [name]"
        exit 1
    fi
    
    if [ ! -f "$import_file" ]; then
        print_error "File not found: $import_file"
        exit 1
    fi
    
    print_info "Importing keypair from: $import_file"
    echo ""
    
    # Validate JSON format by copying to container first
    docker cp "$import_file" "$CONTAINER_NAME:/tmp/import-key.json" 2>/dev/null
    if ! docker exec $CONTAINER_NAME solana-keygen pubkey "/tmp/import-key.json" > /dev/null 2>&1; then
        print_error "Invalid keypair file format."
        docker exec $CONTAINER_NAME rm -f /tmp/import-key.json 2>/dev/null
        exit 1
    fi
    
    # Get public key
    local pubkey=$(docker exec $CONTAINER_NAME solana-keygen pubkey "/tmp/import-key.json" 2>/dev/null)
    
    # Determine key name
    if [ -z "$key_name" ]; then
        key_name="imported-$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Sanitize keyname
    key_name=$(echo "$key_name" | sed 's/[^a-zA-Z0-9_-]/_/g')
    
    local dest_file="$ACCOUNTS_DIR/${key_name}.json"
    
    # Check if destination exists
    if [ -f "$dest_file" ]; then
        print_warning "Key file already exists: $dest_file"
        read -p "Overwrite? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            print_info "Import cancelled."
            docker exec $CONTAINER_NAME rm -f /tmp/import-key.json 2>/dev/null
            return
        fi
    fi
    
    # Create accounts directory
    mkdir -p "$ACCOUNTS_DIR"
    
    # Copy the key from container to host
    docker cp "$CONTAINER_NAME:/tmp/import-key.json" "$dest_file"
    docker exec $CONTAINER_NAME rm -f /tmp/import-key.json 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_info "Keypair imported successfully!"
        echo ""
        echo "Name: $key_name"
        echo "File: $dest_file"
        echo "Public Key: $pubkey"
        echo ""
        
        # Check balance
        local balance=$(docker exec $CONTAINER_NAME solana balance "$dest_file" --url $RPC_URL 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "Current Balance: $balance"
        fi
    else
        print_error "Failed to import keypair."
    fi
}

# Airdrop SOL
airdrop_sol() {
    local target_type=$1
    local target_value=$2
    local amount=${3:-100}  # Default 100 SOL
    
    local keyfile=""
    local pubkey=""
    
    # Determine target
    if [ "$target_type" == "-n" ]; then
        keyfile=$(get_key_by_index $target_value)
        pubkey=$(docker exec $CONTAINER_NAME solana-keygen pubkey "$keyfile" 2>/dev/null)
        print_info "Airdropping to key #$target_value..."
    elif [ "$target_type" == "-k" ]; then
        pubkey="$target_value"
        print_info "Airdropping to public key: $pubkey..."
    else
        print_error "Invalid target type. Use -n for index or -k for public key."
        exit 1
    fi
    
    echo ""
    echo "Target: $pubkey"
    echo "Amount: $amount SOL"
    echo ""
    
    print_info "Requesting airdrop..."
    
    # Execute airdrop
    local result=$(docker exec $CONTAINER_NAME solana airdrop "$amount" "$pubkey" --url $RPC_URL 2>&1)
    
    if [ $? -eq 0 ]; then
        print_info "Airdrop successful!"
        echo "$result"
        
        # Show new balance
        echo ""
        local balance=$(docker exec $CONTAINER_NAME solana balance "$pubkey" --url $RPC_URL 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "New Balance: $balance"
        fi
    else
        print_error "Airdrop failed!"
        echo "$result"
    fi
}

# Generate new keypair
generate_key() {
    local keyname=$1
    
    if [ -z "$keyname" ]; then
        # Generate default name with timestamp
        keyname="wallet-$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Sanitize keyname (remove special characters)
    keyname=$(echo "$keyname" | sed 's/[^a-zA-Z0-9_-]/_/g')
    
    local keyfile="$ACCOUNTS_DIR/${keyname}.json"
    
    # Check if file already exists
    if [ -f "$keyfile" ]; then
        print_error "Key file already exists: $keyfile"
        read -p "Overwrite? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            print_info "Key generation cancelled."
            return
        fi
    fi
    
    print_info "Generating new keypair: $keyname"
    echo ""
    
    # Create accounts directory if it doesn't exist
    mkdir -p "$ACCOUNTS_DIR"
    
    # Generate keypair
    docker exec $CONTAINER_NAME solana-keygen new \
        --no-bip39-passphrase \
        --outfile "$keyfile" \
        --force 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local pubkey=$(docker exec $CONTAINER_NAME solana-keygen pubkey "$keyfile" 2>/dev/null)
        
        print_info "Keypair generated successfully!"
        echo ""
        echo "Name: $keyname"
        echo "File: $keyfile"
        echo "Public Key: $pubkey"
        echo ""
        print_warning "Save this information! The private key is stored in: $keyfile"
        
        # Optionally airdrop some SOL
        echo ""
        read -p "Airdrop test SOL to this address? (yes/no): " airdrop_confirm
        if [ "$airdrop_confirm" == "yes" ]; then
            read -p "Amount (SOL): " amount
            if [ ! -z "$amount" ]; then
                print_info "Requesting airdrop of $amount SOL..."
                docker exec $CONTAINER_NAME solana airdrop "$amount" "$keyfile" --url $RPC_URL 2>/dev/null
                if [ $? -eq 0 ]; then
                    print_info "Airdrop successful!"
                    local balance=$(docker exec $CONTAINER_NAME solana balance "$keyfile" --url $RPC_URL 2>/dev/null)
                    echo "New Balance: $balance"
                else
                    print_error "Airdrop failed. You can request it later."
                fi
            fi
        fi
    else
        print_error "Failed to generate keypair."
    fi
}

# Show help
show_help() {
    cat << EOF
Solana Key Manager

Usage: ./keymanager.sh [OPTION]

Key Management:
  --list                       List all available keys with indices
  --generate [name]            Generate new keypair (optional: specify name)
  --export -n <index> [file]   Export private key by index to JSON file
  --export -pubkey <key> [file]
                               Export private key by public key to JSON file
  --import <file> [name]       Import private key from JSON file

Balance Operations:
  --balance -n <index>         Show balance of key by index number
  --balance -k <pubkey>        Show balance of key by public key
  --airdrop -n <index> [amount]
                               Airdrop SOL to key by index (default: 100 SOL)
  --airdrop -k <pubkey> [amount]
                               Airdrop SOL to public key (default: 100 SOL)

Transfer Operations:
  --send -n <index> -r <receiver> -a <amount>
                               Send SOL from key index to receiver
  --send -k <pubkey> -r <receiver> -a <amount>
                               Send SOL from public key to receiver

Block Information:
  --block                      Show current block/slot information
  --block <slot>               Show specific block details by slot number

Examples:
  # List all keys
  ./keymanager.sh --list

  # Generate new keypair with auto-generated name
  ./keymanager.sh --generate

  # Generate new keypair with custom name
  ./keymanager.sh --generate my-wallet

  # Export key #1 to file
  ./keymanager.sh --export -n 1
  ./keymanager.sh --export -n 1 my-backup.json

  # Export key by public key
  ./keymanager.sh --export -pubkey 7xJ...abc backup.json

  # Import key from file
  ./keymanager.sh --import my-key.json
  ./keymanager.sh --import my-key.json my-wallet

  # Get balance of key #1
  ./keymanager.sh --balance -n 1

  # Get balance by public key
  ./keymanager.sh --balance -k 7xJ...abc

  # Airdrop 100 SOL to key #1 (default amount)
  ./keymanager.sh --airdrop -n 1

  # Airdrop 500 SOL to key #2
  ./keymanager.sh --airdrop -n 2 500

  # Airdrop to public key
  ./keymanager.sh --airdrop -k 7xJ...abc 1000

  # Send 10 SOL from key #1 to another address
  ./keymanager.sh --send -n 1 -r 7xJ...xyz -a 10

  # Send 5 SOL from public key to another address
  ./keymanager.sh --send -k 7xJ...abc -r 7xJ...xyz -a 5

  # Show current block info
  ./keymanager.sh --block

  # Show specific block details
  ./keymanager.sh --block 12345

EOF
}

# Main script logic
check_container

case "$1" in
    --list)
        show_keys
        ;;
    --balance)
        if [ "$2" == "-n" ]; then
            if [ -z "$3" ]; then
                print_error "Key index required. Usage: --balance -n <index>"
                exit 1
            fi
            get_balance_by_index "$3"
        elif [ "$2" == "-k" ]; then
            if [ -z "$3" ]; then
                print_error "Public key required. Usage: --balance -k <pubkey>"
                exit 1
            fi
            get_balance_by_pubkey "$3"
        else
            print_error "Invalid option. Use -n for index or -k for public key."
            show_help
            exit 1
        fi
        ;;
    --send)
        # Parse arguments
        sender_type=""
        sender_value=""
        receiver=""
        amount=""
        
        shift # skip --send
        while [ $# -gt 0 ]; do
            case "$1" in
                -n|-k)
                    sender_type="$1"
                    sender_value="$2"
                    shift 2
                    ;;
                -r)
                    receiver="$2"
                    shift 2
                    ;;
                -a)
                    amount="$2"
                    shift 2
                    ;;
                *)
                    print_error "Unknown option: $1"
                    exit 1
                    ;;
            esac
        done
        
        # Validate required parameters
        if [ -z "$sender_type" ] || [ -z "$sender_value" ] || [ -z "$receiver" ] || [ -z "$amount" ]; then
            print_error "Missing required parameters."
            echo "Usage: --send -n <index> -r <receiver> -a <amount>"
            echo "   or: --send -k <pubkey> -r <receiver> -a <amount>"
            exit 1
        fi
        
        send_sol "$sender_type" "$sender_value" "$receiver" "$amount"
        ;;
    --block)
        if [ -z "$2" ]; then
            show_block
        else
            show_block_details "$2"
        fi
        ;;
    --generate)
        generate_key "$2"
        ;;
    --export)
        if [ "$2" == "-n" ]; then
            if [ -z "$3" ]; then
                print_error "Key index required. Usage: --export -n <index> [output_file]"
                exit 1
            fi
            export_key "-n" "$3" "$4"
        elif [ "$2" == "-pubkey" ]; then
            if [ -z "$3" ]; then
                print_error "Public key required. Usage: --export -pubkey <pubkey> [output_file]"
                exit 1
            fi
            export_key "-pubkey" "$3" "$4"
        else
            print_error "Invalid option. Use -n for index or -pubkey for public key."
            echo "Usage: --export -n <index> [output_file]"
            echo "   or: --export -pubkey <pubkey> [output_file]"
            exit 1
        fi
        ;;
    --import)
        if [ -z "$2" ]; then
            print_error "Import file required. Usage: --import <file> [name]"
            exit 1
        fi
        import_key "$2" "$3"
        ;;
    --airdrop)
        if [ "$2" == "-n" ]; then
            if [ -z "$3" ]; then
                print_error "Key index required. Usage: --airdrop -n <index> [amount]"
                exit 1
            fi
            airdrop_sol "-n" "$3" "$4"
        elif [ "$2" == "-k" ]; then
            if [ -z "$3" ]; then
                print_error "Public key required. Usage: --airdrop -k <pubkey> [amount]"
                exit 1
            fi
            airdrop_sol "-k" "$3" "$4"
        else
            print_error "Invalid option. Use -n for index or -k for public key."
            echo "Usage: --airdrop -n <index> [amount]"
            echo "   or: --airdrop -k <pubkey> [amount]"
            exit 1
        fi
        ;;
    --help|*)
        show_help
        ;;
esac
