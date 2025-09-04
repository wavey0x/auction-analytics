#!/usr/bin/env bash
# One-shot deploy script for Ubuntu/Debian VPS
# - Installs system packages
# - Creates app user and directories
# - Clones/updates repo
# - Builds UI and sets up Python venv
# - Runs DB migrations
# - Installs and starts systemd services

set -euo pipefail

REPO_URL=${REPO_URL:-"https://github.com/your-org/auctions_charts.git"}
APP_DIR=${APP_DIR:-"/opt/auction-app"}
BRANCH=${BRANCH:-"main"}

# Required envs
PROD_DATABASE_URL=${PROD_DATABASE_URL:-}
REDIS_URL=${REDIS_URL:-}
API_PORT=${API_PORT:-8000}

if [[ -z "$PROD_DATABASE_URL" ]]; then
  echo "PROD_DATABASE_URL must be provided (e.g., export PROD_DATABASE_URL=postgres://...)" >&2
  exit 1
fi

echo "==> Installing packages"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  git curl ca-certificates build-essential \
  python3 python3-venv python3-dev \
  nodejs npm \
  nginx

echo "==> Creating app directory at $APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER":"$USER" "$APP_DIR"

if [[ ! -d "$APP_DIR/.git" ]]; then
  echo "==> Cloning repo"
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"
git fetch --all
git checkout "$BRANCH"
git pull --ff-only

echo "==> Writing .env"
cat > .env <<EOF
APP_MODE=prod
API_HOST=0.0.0.0
API_PORT=$API_PORT
PROD_DATABASE_URL=$PROD_DATABASE_URL
REDIS_URL=${REDIS_URL}
# Optional Telegram
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
# Redis ACLs (optional)
REDIS_PUBLISHER_USER=${REDIS_PUBLISHER_USER:-}
REDIS_PUBLISHER_PASS=${REDIS_PUBLISHER_PASS:-}
REDIS_CONSUMER_USER=${REDIS_CONSUMER_USER:-}
REDIS_CONSUMER_PASS=${REDIS_CONSUMER_PASS:-}
EOF

echo "==> Setting up Python venv"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
if [[ -f monitoring/api/requirements-working.txt ]]; then
  pip install -r monitoring/api/requirements-working.txt
else
  pip install -r monitoring/api/requirements.txt
fi

echo "==> Building UI"
pushd ui
npm ci
npm run build
popd

echo "==> Running database migrations"
export DATABASE_URL="$PROD_DATABASE_URL"
bash scripts/migrate.sh

echo "==> Installing systemd services"
SERVICE_DIR=/etc/systemd/system

sudo bash -s <<'SYS'
set -e
cat > /etc/systemd/system/auction-api.service <<EOF
[Unit]
Description=Auction API (FastAPI)
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/auction-app
EnvironmentFile=%h/auction-app/.env
ExecStart=%h/auction-app/venv/bin/python -m uvicorn monitoring.api.app:app --host 0.0.0.0 --port ${API_PORT}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/auction-relay.service <<EOF
[Unit]
Description=Outbox Relay -> Redis
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/auction-app
EnvironmentFile=%h/auction-app/.env
ExecStart=%h/auction-app/venv/bin/python scripts/relay_outbox_to_redis.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/auction-indexer.service <<EOF
[Unit]
Description=Auction Indexer
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/auction-app/indexer
EnvironmentFile=%h/auction-app/.env
ExecStart=%h/auction-app/venv/bin/python indexer.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/auction-telegram.service <<EOF
[Unit]
Description=Telegram Consumer
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/auction-app
EnvironmentFile=%h/auction-app/.env
ExecStart=%h/auction-app/venv/bin/python scripts/consumers/telegram_consumer.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
SYS

echo "==> Starting services"
sudo systemctl enable --now auction-api.service
sudo systemctl enable --now auction-relay.service
sudo systemctl enable --now auction-indexer.service || true
sudo systemctl enable --now auction-telegram.service || true

echo "==> Configuring Nginx"
SITE=/etc/nginx/sites-available/auction
sudo bash -s <<NG
cat > $SITE <<'EOF'
server {
  listen 80 default_server;
  server_name _;

  # Serve built UI
  root /opt/auction-app/ui/dist;
  index index.html;

  location /api/ {
    proxy_pass http://127.0.0.1:${API_PORT}/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
  }

  # SSE stream passthrough
  location /events/stream {
    proxy_pass http://127.0.0.1:${API_PORT}/events/stream;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_buffering off;
  }

  location / {
    try_files $uri /index.html;
  }
}
EOF

ln -sf $SITE /etc/nginx/sites-enabled/auction
nginx -t
systemctl restart nginx
NG

echo "==> Deployment complete"

