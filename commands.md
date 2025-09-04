# Production Deployment Commands

This file contains copy-paste ready commands for deploying the auction system to production.

## Systemd Services

### API (FastAPI)
```bash
sudo tee /etc/systemd/system/auction-api.service >/dev/null << 'EOF'
[Unit]
Description=Auction API (FastAPI)
After=network.target

[Service]
Type=simple
User=auction
Group=auction
WorkingDirectory=/opt/auction-app
EnvironmentFile=/opt/auction-app/.env
Environment=PYTHONPATH=/opt/auction-app
ExecStart=/opt/auction-app/venv/bin/python -m uvicorn monitoring.api.app:app --host 0.0.0.0 --port ${API_PORT}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
```

### Outbox Relay
```bash
sudo tee /etc/systemd/system/auction-relay.service >/dev/null << 'EOF'
[Unit]
Description=Outbox Relay -> Redis
After=network.target

[Service]
Type=simple
User=auction
Group=auction
WorkingDirectory=/opt/auction-app
EnvironmentFile=/opt/auction-app/.env
ExecStart=/opt/auction-app/venv/bin/python scripts/relay_outbox_to_redis.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
```

### Indexer
```bash
sudo tee /etc/systemd/system/auction-indexer.service >/dev/null << 'EOF'
[Unit]
Description=Auction Indexer
After=network.target

[Service]
Type=simple
User=auction
Group=auction
WorkingDirectory=/opt/auction-app/indexer
EnvironmentFile=/opt/auction-app/.env
ExecStart=/opt/auction-app/venv/bin/python indexer.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Telegram Consumer (Optional)
```bash
sudo tee /etc/systemd/system/auction-telegram.service >/dev/null << 'EOF'
[Unit]
Description=Telegram Consumer
After=network.target

[Service]
Type=simple
User=auction
Group=auction
WorkingDirectory=/opt/auction-app
EnvironmentFile=/opt/auction-app/.env
ExecStart=/opt/auction-app/venv/bin/python scripts/consumers/telegram_consumer.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Enable and Start Services
```bash
# Reload systemd daemon
sudo systemctl daemon-reload

# Enable and start core services
sudo systemctl enable --now auction-api.service
sudo systemctl enable --now auction-relay.service
sudo systemctl enable --now auction-indexer.service

# Enable telegram service only if TELEGRAM_BOT_TOKEN is configured
sudo systemctl enable --now auction-telegram.service
```

### Check Service Status
```bash
# Check individual service status
systemctl status auction-api
systemctl status auction-relay
systemctl status auction-indexer
systemctl status auction-telegram

# Follow logs for specific services
journalctl -u auction-api -f
journalctl -u auction-relay -f
journalctl -u auction-indexer -f
journalctl -u auction-telegram -f
```

## Nginx Configuration

### Create Site Configuration
```bash
sudo tee /etc/nginx/sites-available/auction >/dev/null << 'EOF'
server {
    listen 80 default_server;
    server_name _;
    root /opt/auction-app/ui/dist;
    index index.html;

    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    # Server-Sent Events stream
    location /events/stream {
        proxy_pass http://127.0.0.1:8000/events/stream;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_buffering off;
    }

    # React app - serve static files and fallback to index.html
    location / {
        try_files $uri /index.html;
    }
}
EOF
```

### Enable Site and Reload Nginx
```bash
# Enable the site
sudo ln -sf /etc/nginx/sites-available/auction /etc/nginx/sites-enabled/auction

# Test nginx configuration
sudo nginx -t

# Restart nginx
sudo systemctl restart nginx
```

## All-in-One Deployment Script

### Deploy All Services
```bash
# Create all systemd services
sudo tee /etc/systemd/system/auction-api.service >/dev/null << 'EOF'
[Unit]
Description=Auction API (FastAPI)
After=network.target

[Service]
Type=simple
User=auction
Group=auction
WorkingDirectory=/opt/auction-app
EnvironmentFile=/opt/auction-app/.env
Environment=PYTHONPATH=/opt/auction-app
ExecStart=/opt/auction-app/venv/bin/python -m uvicorn monitoring.api.app:app --host 0.0.0.0 --port ${API_PORT}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/auction-relay.service >/dev/null << 'EOF'
[Unit]
Description=Outbox Relay -> Redis
After=network.target

[Service]
Type=simple
User=auction
Group=auction
WorkingDirectory=/opt/auction-app
EnvironmentFile=/opt/auction-app/.env
ExecStart=/opt/auction-app/venv/bin/python scripts/relay_outbox_to_redis.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/auction-indexer.service >/dev/null << 'EOF'
[Unit]
Description=Auction Indexer
After=network.target

[Service]
Type=simple
User=auction
Group=auction
WorkingDirectory=/opt/auction-app/indexer
EnvironmentFile=/opt/auction-app/.env
ExecStart=/opt/auction-app/venv/bin/python indexer.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/auction-telegram.service >/dev/null << 'EOF'
[Unit]
Description=Telegram Consumer
After=network.target

[Service]
Type=simple
User=auction
Group=auction
WorkingDirectory=/opt/auction-app
EnvironmentFile=/opt/auction-app/.env
ExecStart=/opt/auction-app/venv/bin/python scripts/consumers/telegram_consumer.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create nginx configuration
sudo tee /etc/nginx/sites-available/auction >/dev/null << 'EOF'
server {
    listen 80 default_server;
    server_name _;
    root /opt/auction-app/ui/dist;
    index index.html;

    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    # Server-Sent Events stream
    location /events/stream {
        proxy_pass http://127.0.0.1:8000/events/stream;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_buffering off;
    }

    # React app - serve static files and fallback to index.html
    location / {
        try_files $uri /index.html;
    }
}
EOF

# Enable and start all services
sudo systemctl daemon-reload
sudo systemctl enable --now auction-api.service
sudo systemctl enable --now auction-relay.service  
sudo systemctl enable --now auction-indexer.service
# sudo systemctl enable --now auction-telegram.service  # Uncomment if telegram is configured

# Enable nginx site
sudo ln -sf /etc/nginx/sites-available/auction /etc/nginx/sites-enabled/auction
sudo nginx -t && sudo systemctl restart nginx

echo "✅ Deployment complete! Check service status:"
systemctl status auction-api auction-relay auction-indexer
```

## Verification Commands

### Check All Services
```bash
# Check all service statuses at once
systemctl status auction-api auction-relay auction-indexer auction-telegram

# Check nginx status
systemctl status nginx

# Check if services are listening on expected ports
ss -tulpn | grep -E "(8000|80)"

# Check recent logs for all services
journalctl -u auction-api --since "5 minutes ago" --no-pager
journalctl -u auction-relay --since "5 minutes ago" --no-pager  
journalctl -u auction-indexer --since "5 minutes ago" --no-pager
```

### Test API Endpoints
```bash
# Test API health
curl http://localhost/api/health

# Test API directly (bypass nginx)
curl http://localhost:8000/health

# Test static file serving
curl -I http://localhost/

# Test that API routes work through nginx
curl http://localhost/api/auctions | jq
```