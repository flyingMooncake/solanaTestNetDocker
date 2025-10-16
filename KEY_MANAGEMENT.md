# Validator Key Management Guide

This guide explains how to manage validator keys for your Solana test network.

## Understanding Solana Keys

Your Solana validator uses three types of keypairs:

1. **Validator Identity Key** - Uniquely identifies your validator node
2. **Vote Account Key** - Used for voting on blocks and earning rewards
3. **Stake Account Key** - Used for staking SOL to your validator

## Key Management Commands

### View Current Keys

Display information about all current validator keys:

```bash
./manager.sh --show-keys
```

This shows:
- File locations
- Public keys for each keypair
- Status of each key

### Generate New Keys

Generate a new keypair (without importing):

```bash
# Generate new validator identity
./manager.sh --set-key "" validator

# Generate new vote account
./manager.sh --set-key "" vote

# Generate new stake account
./manager.sh --set-key "" stake
```

Or simply:
```bash
./manager.sh --set-key
```

### Import Existing Keys

Import a keypair from a JSON file:

```bash
# Import validator identity
./manager.sh --set-key /path/to/validator-keypair.json validator

# Import vote account
./manager.sh --set-key /path/to/vote-keypair.json vote

# Import stake account
./manager.sh --set-key /path/to/stake-keypair.json stake
```

### Export Keys

Export all validator keys to a backup directory:

```bash
# Export to current directory
./manager.sh --export-keys

# Export to specific directory
./manager.sh --export-keys ./backup

# Export to absolute path
./manager.sh --export-keys /home/user/solana-keys-backup
```

**⚠️ Security Warning:** Keep exported keys secure! Anyone with access to these files can control your validator.

## Key File Format

Solana keypairs are stored as JSON arrays of 64 bytes (the private key):

```json
[123,45,67,89,...]
```

The public key is derived from the private key and can be displayed using:

```bash
docker exec solana-testnet solana-keygen pubkey /solana/config/validator-keypair.json
```

## Common Workflows

### 1. Fresh Start with New Keys

```bash
./manager.sh --init
./manager.sh --validate
```

The `--init` command automatically generates all required keys.

### 2. Use Existing Validator Identity

If you have an existing validator identity you want to reuse:

```bash
# Start the container
./manager.sh --init

# Import your existing validator key
./manager.sh --set-key /path/to/my-validator-keypair.json validator

# Reinitialize with the new key
./manager.sh --purge
./manager.sh --init
./manager.sh --validate
```

### 3. Backup Keys Before Purging

Always backup your keys before purging data:

```bash
# Export keys
./manager.sh --export-keys ./backup-$(date +%Y%m%d)

# Now safe to purge
./manager.sh --purge
```

### 4. Restore Keys After Purge

```bash
# Initialize new network
./manager.sh --init

# Import backed up keys
./manager.sh --set-key ./backup-20240101/validator-keypair.json validator
./manager.sh --set-key ./backup-20240101/vote-account-keypair.json vote
./manager.sh --set-key ./backup-20240101/stake-account.json stake

# Reinitialize with restored keys
./manager.sh --purge
./manager.sh --init
./manager.sh --validate
```

### 5. Transfer Validator to Another Server

On the original server:

```bash
# Export keys
./manager.sh --export-keys ./keys-export
```

Transfer the `keys-export` directory to the new server, then:

```bash
# On new server
./manager.sh --init

# Import keys
./manager.sh --set-key ./keys-export/validator-keypair.json validator
./manager.sh --set-key ./keys-export/vote-account-keypair.json vote
./manager.sh --set-key ./keys-export/stake-account.json stake

# Reinitialize
./manager.sh --purge
./manager.sh --init
./manager.sh --validate
```

## Key Storage Locations

Keys are stored in the following locations:

```
./data/
├── config/
│   ├── validator-keypair.json    # Validator identity
│   └── vote-account-keypair.json # Vote account
└── accounts/
    └── stake-account.json         # Stake account
```

These directories are mounted as Docker volumes, so keys persist even if the container is recreated.

## Security Best Practices

### 1. File Permissions

Ensure key files have restricted permissions:

```bash
chmod 600 ./data/config/validator-keypair.json
chmod 600 ./data/config/vote-account-keypair.json
chmod 600 ./data/accounts/stake-account.json
```

### 2. Backup Strategy

- **Regular Backups**: Export keys regularly
- **Secure Storage**: Store backups in encrypted storage
- **Multiple Locations**: Keep backups in multiple secure locations
- **Test Restores**: Periodically test that you can restore from backups

### 3. Access Control

- Limit SSH access to the server
- Use SSH keys instead of passwords
- Enable firewall rules
- Consider using a hardware security module (HSM) for production

### 4. Key Rotation

For test networks, you can rotate keys by:

```bash
# Backup old keys
./manager.sh --export-keys ./old-keys-$(date +%Y%m%d)

# Generate new keys
./manager.sh --purge
./manager.sh --init
./manager.sh --validate
```

## Generating Keys Manually

You can also generate keys manually using Solana CLI:

```bash
# Inside the container
docker exec -it solana-testnet bash

# Generate a new keypair
solana-keygen new --outfile /solana/config/my-keypair.json

# Display public key
solana-keygen pubkey /solana/config/my-keypair.json

# Verify keypair
solana-keygen verify <PUBKEY> /solana/config/my-keypair.json
```

## Troubleshooting

### Key File Not Found

If you get "key file not found" errors:

```bash
# Check if container is running
./manager.sh --status

# Check if keys exist
ls -la ./data/config/
ls -la ./data/accounts/

# Reinitialize if needed
./manager.sh --init
```

### Invalid Key Format

If importing a key fails:

```bash
# Verify the key file format
cat /path/to/keypair.json

# Should be a JSON array of 64 numbers
# Example: [123,45,67,...]

# Verify the key is valid
docker exec solana-testnet solana-keygen verify <PUBKEY> /path/to/keypair.json
```

### Permission Denied

If you get permission errors:

```bash
# Fix permissions
sudo chown -R $USER:$USER ./data
chmod -R 755 ./data
chmod 600 ./data/config/*.json
chmod 600 ./data/accounts/*.json
```

## Advanced: Using Hardware Wallets

For production validators, consider using hardware wallets:

1. **Ledger Nano S/X**: Supported by Solana CLI
2. **Remote Signing**: Use a separate signing service
3. **Multi-sig**: Require multiple signatures for validator operations

Example with Ledger:

```bash
# Inside container
docker exec -it solana-testnet bash

# Use Ledger for validator identity
solana-keygen pubkey usb://ledger

# Create vote account with Ledger
solana create-vote-account \
  --keypair usb://ledger \
  vote-account.json \
  validator-identity.json
```

## Key Recovery

If you lose your keys:

- **Test Network**: Simply generate new keys with `./manager.sh --init`
- **Production**: You MUST have backups. Lost keys = lost validator identity and stake

Always maintain secure, tested backups of your validator keys!

## Additional Resources

- [Solana Key Management](https://docs.solana.com/cli/conventions#keypair-conventions)
- [Validator Security Best Practices](https://docs.solana.com/running-validator/validator-start#security)
- [Solana CLI Reference](https://docs.solana.com/cli)
