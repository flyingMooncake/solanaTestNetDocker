# Deployment Guide - Solana Private Test Network

This guide explains how to deploy your Solana test network to a remote server and make it accessible externally.

## Prerequisites on Remote Server

- Docker and Docker Compose installed
- Root or sudo access
- Open network ports (firewall configuration)

## Step 1: Transfer Files to Server

### Option A: Using SCP
```bash
scp -r /home/water/solanaTestNetDocker user@your-server-ip:/home/user/
```

### Option B: Using rsync (recommended)
```bash
rsync -avz --progress /home/water/solanaTestNetDocker user@your-server-ip:/home/user/
```

### Option C: Using Git
```bash
# On local machine
cd /home/water/solanaTestNetDocker
git init
git add .
git commit -m "Initial commit"
git remote add origin <your-git-repo-url>
git push -u origin main

# On remote server
git clone <your-git-repo-url>
cd solanaTestNetDocker
chmod +x manager.sh
```

## Step 2: Configure Firewall on Server

### For Ubuntu/Debian (using UFW)
```bash
# Enable UFW if not already enabled
sudo ufw enable

# Allow SSH (important - don't lock yourself out!)
sudo ufw allow 22/tcp

# Allow Solana ports
sudo ufw allow 8001/tcp comment 'Solana Gossip'
sudo ufw allow 8899/tcp comment 'Solana RPC'
sudo ufw allow 8900/tcp comment 'Solana WebSocket'
sudo ufw allow 8003/tcp comment 'Solana TVU'
sudo ufw allow 8004/tcp comment 'Solana TPU'

# Check status
sudo ufw status numbered
```

### For CentOS/RHEL (using firewalld)
```bash
# Allow Solana ports
sudo firewall-cmd --permanent --add-port=8001/tcp
sudo firewall-cmd --permanent --add-port=8899/tcp
sudo firewall-cmd --permanent --add-port=8900/tcp
sudo firewall-cmd --permanent --add-port=8003/tcp
sudo firewall-cmd --permanent --add-port=8004/tcp

# Reload firewall
sudo firewall-cmd --reload

# Check status
sudo firewall-cmd --list-all
```

### For Cloud Providers (AWS, GCP, Azure, etc.)

You'll also need to configure security groups/firewall rules in your cloud provider's console:

**AWS Security Group Rules:**
- Type: Custom TCP, Port: 8001, Source: 0.0.0.0/0 (Gossip)
- Type: Custom TCP, Port: 8899, Source: 0.0.0.0/0 (RPC)
- Type: Custom TCP, Port: 8900, Source: 0.0.0.0/0 (WebSocket)
- Type: Custom TCP, Port: 8003, Source: 0.0.0.0/0 (TVU)
- Type: Custom TCP, Port: 8004, Source: 0.0.0.0/0 (TPU)

**GCP Firewall Rules:**
```bash
gcloud compute firewall-rules create solana-testnet \
    --allow tcp:8001,tcp:8899,tcp:8900,tcp:8003,tcp:8004 \
    --source-ranges 0.0.0.0/0 \
    --description "Solana test network ports"
```

## Step 3: Deploy on Server

```bash
# SSH into your server
ssh user@your-server-ip

# Navigate to the project directory
cd solanaTestNetDocker

# Make manager script executable (if not already)
chmod +x manager.sh

# Initialize the network
./manager.sh --init

# Start the validator
./manager.sh --validate

# Check status
./manager.sh --status
```

## Step 4: Verify External Access

From your local machine or another computer, test the connection:

```bash
# Test RPC endpoint
curl http://your-server-ip:8899 -X POST -H "Content-Type: application/json" -d '
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "getHealth"
}'

# Expected response: {"jsonrpc":"2.0","result":"ok","id":1}
```

### Using Solana CLI from Remote Machine

```bash
# Configure Solana CLI to use your remote network
solana config set --url http://your-server-ip:8899

# Test connection
solana cluster-version

# Check balance (should show test tokens)
solana balance
```

## Step 5: Connect Multiple Nodes

### Bootstrap Node (First Server)
```bash
# Server 1 (e.g., 192.168.1.100)
./manager.sh --init
./manager.sh --validate
```

### Additional Nodes (Other Servers)
```bash
# Server 2, 3, etc.
./manager.sh --init
./manager.sh --connect 192.168.1.100:8001
```

## Security Considerations

### 1. Restrict RPC Access (Production)
For production environments, restrict RPC access to specific IPs:

```bash
# UFW example - only allow specific IP
sudo ufw delete allow 8899/tcp
sudo ufw allow from 203.0.113.0/24 to any port 8899 proto tcp
```

### 2. Use Reverse Proxy (Recommended)
Set up Nginx as a reverse proxy with SSL:

```nginx
# /etc/nginx/sites-available/solana-rpc
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8899;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 3. Rate Limiting
Implement rate limiting to prevent abuse:

```nginx
limit_req_zone $binary_remote_addr zone=solana_rpc:10m rate=10r/s;

server {
    location / {
        limit_req zone=solana_rpc burst=20;
        proxy_pass http://localhost:8899;
    }
}
```

## Monitoring

### Check Validator Logs
```bash
docker exec solana-testnet tail -f /solana/validator.log
```

### Monitor Container Resources
```bash
docker stats solana-testnet
```

### Check Network Status
```bash
./manager.sh --status
```

## Maintenance

### Update Solana Version
Edit the Dockerfile and change the version:
```dockerfile
RUN sh -c "$(curl -sSfL https://release.solana.com/v1.18.18/install)"
```

Then rebuild:
```bash
./manager.sh --stops
docker-compose build --no-cache
./manager.sh --validate
```

### Backup Data
```bash
# Backup ledger and config
tar -czf solana-backup-$(date +%Y%m%d).tar.gz data/
```

### Restore Data
```bash
# Stop services
./manager.sh --stops

# Extract backup
tar -xzf solana-backup-YYYYMMDD.tar.gz

# Restart
./manager.sh --validate
```

## Troubleshooting

### Port Already in Use
```bash
# Check what's using the port
sudo lsof -i :8899
sudo netstat -tulpn | grep 8899

# Kill the process if needed
sudo kill -9 <PID>
```

### Cannot Connect Externally
```bash
# Verify ports are listening on all interfaces
sudo netstat -tulpn | grep -E '8899|8001'

# Should show 0.0.0.0:8899 not 127.0.0.1:8899
```

### Firewall Issues
```bash
# Test if port is open from external machine
telnet your-server-ip 8899

# Or use nmap
nmap -p 8899 your-server-ip
```

## Performance Tuning

### Increase Docker Resources
Edit `/etc/docker/daemon.json`:
```json
{
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
```

Restart Docker:
```bash
sudo systemctl restart docker
```

### System Limits
```bash
# Increase file descriptors
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
```

## Useful Commands

```bash
# View all Docker logs
docker-compose logs -f

# Restart validator without losing data
./manager.sh --validate -s
./manager.sh --validate

# Complete reset
./manager.sh --purge
./manager.sh --init
./manager.sh --validate

# Check Docker container IP
docker inspect solana-testnet | grep IPAddress
```

## Support

For issues specific to Solana, refer to:
- [Solana Documentation](https://docs.solana.com/)
- [Solana Discord](https://discord.gg/solana)
- [Solana Stack Exchange](https://solana.stackexchange.com/)
