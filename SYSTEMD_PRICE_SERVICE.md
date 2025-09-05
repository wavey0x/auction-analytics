# Systemd Service Configuration for Auction Analytics Price Service

This document describes how to set up and manage the auction analytics price service using systemd.

## Available Service Files

1. **`auction-price-service.service`** - Runs all price services (YPM, Odos, ENSO) in parallel
2. **`auction-price-service-ypm.service`** - Runs only the YPM (Brownie-based) price service
3. **`auction-price-service-external.service`** - Runs only external API services (Odos + ENSO)

## Installation

### 1. Copy Service Files

```bash
# Copy to systemd directory (requires sudo)
sudo cp auction-price-service*.service /etc/systemd/system/

# Or create symlinks to keep files in project directory
sudo ln -s /Users/wavey/yearn/auction-analytics/auction-price-service.service /etc/systemd/system/
sudo ln -s /Users/wavey/yearn/auction-analytics/auction-price-service-ypm.service /etc/systemd/system/
sudo ln -s /Users/wavey/yearn/auction-analytics/auction-price-service-external.service /etc/systemd/system/
```

### 2. Set Permissions

```bash
# Set correct ownership and permissions
sudo chown root:root /etc/systemd/system/auction-price-service*.service
sudo chmod 644 /etc/systemd/system/auction-price-service*.service
```

### 3. Reload Systemd

```bash
sudo systemctl daemon-reload
```

## Usage

### Start Services

```bash
# Start all price services (recommended for production)
sudo systemctl start auction-price-service

# Or start only YPM service
sudo systemctl start auction-price-service-ymp

# Or start only external API services
sudo systemctl start auction-price-service-external
```

### Enable Auto-Start on Boot

```bash
# Enable the main service to start automatically
sudo systemctl enable auction-price-service

# Or enable individual services
sudo systemctl enable auction-price-service-ymp
sudo systemctl enable auction-price-service-external
```

### Monitor Services

```bash
# Check service status
sudo systemctl status auction-price-service

# Follow logs in real-time
sudo journalctl -u auction-price-service -f

# View recent logs
sudo journalctl -u auction-price-service -n 100

# View logs for specific pricer
sudo journalctl -u auction-price-service-ymp -f
```

### Control Services

```bash
# Stop service
sudo systemctl stop auction-price-service

# Restart service
sudo systemctl restart auction-price-service

# Disable auto-start
sudo systemctl disable auction-price-service
```

## Configuration

### Environment Variables

The service loads environment variables from `/Users/wavey/yearn/auction-analytics/.env`. Ensure this file exists and contains all required variables:

```bash
# Required environment variables
DATABASE_URL=postgresql://user:password@host:port/database
ETHEREUM_RPC_URL=https://your-ethereum-rpc-url
# ... other required variables
```

### Logging

- **Service logs**: Use `journalctl -u <service-name>` to view systemd logs
- **Application logs**: Written to `/Users/wavey/yearn/auction-analytics/logs/`
- **Log rotation**: Handled automatically by systemd/journald

### Resource Limits

The service files include resource limits:
- Memory: 1-1.5GB limit with high-water mark
- File descriptors: 512-1024 limit
- Security: Sandboxed with limited system access

## Troubleshooting

### Common Issues

1. **Permission errors**: Ensure the `wavey` user has read/write access to the project directory and logs folder
2. **Environment not loaded**: Check that `.env` file exists and is readable
3. **Network connectivity**: Ensure the server has internet access for external APIs
4. **Brownie network issues**: Check that the specified Brownie network is configured correctly

### Debug Commands

```bash
# Test the run script manually
cd /Users/wavey/yearn/auction-analytics
./scripts/run_price_service.sh --pricer ymp --once

# Check service configuration
sudo systemctl show auction-price-service

# Check if port is in use
netstat -tulpn | grep :8000

# View full service logs
sudo journalctl -u auction-price-service --since "1 hour ago"
```

### Performance Monitoring

```bash
# Monitor resource usage
sudo systemctl status auction-price-service
top -p $(pgrep -f price_service)

# Check memory usage
sudo systemctl show auction-price-service | grep Memory
```

## Security Considerations

The service files include several security hardening measures:
- `NoNewPrivileges=true` - Prevents privilege escalation
- `PrivateTmp=true` - Provides private /tmp directory  
- `ProtectSystem=strict` - Read-only access to system directories
- `ProtectHome=read-only` - Read-only access to home directories
- `ReadWritePaths=` - Explicitly allows write access only to logs directory

## Service Dependencies

The price service depends on:
- Network connectivity (`network-online.target`)
- PostgreSQL database (should be running)
- Python virtual environment and dependencies
- Brownie configuration (for YPM service)

Make sure these are properly configured before starting the service.