# OpenTune Manual Deployment Guide

Complete guide for deploying OpenTune on a Linux VM without Docker.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Systemd Service](#systemd-service)
- [Nginx & HTTPS](#nginx--https)
- [Post-Installation](#post-installation)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| OS | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| CPU | 1 core | 2 cores |
| RAM | 1 GB | 2 GB |
| Disk | 10 GB | 20 GB |
| Network | Outbound HTTPS | Inbound 80/443 |

### Required Software

- Python 3.10+
- Node.js 18+ (for building frontend)
- Git
- (Optional) Nginx for reverse proxy

---

## Installation

### Step 1: System Preparation

```bash
# Connect to your VM
ssh user@your-server-ip

# Update system
sudo apt update && sudo apt upgrade -y

# Install system dependencies
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    build-essential

# Install Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Verify installations
python3 --version   # Should be 3.10+
node --version      # Should be 20.x
npm --version       # Should be 10.x
git --version       # Should be 2.x+
```

### Step 2: Create Application Directory

```bash
# Create directory
sudo mkdir -p /opt/opentune
sudo chown $USER:$USER /opt/opentune

# Clone repository (or upload your files)
git clone https://github.com/YOUR_USERNAME/opentune.git /opt/opentune
cd /opt/opentune
```

### Step 3: Backend Setup

```bash
cd /opt/opentune

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install dependencies
pip install -r backend/requirements.txt

# Create data directories
mkdir -p backend/data/repos
```

### Step 4: Configuration

```bash
# Copy example configuration
cp backend/.env.example backend/.env

# Generate secure API key
python3 -c "import secrets; print('ADMIN_API_KEY=' + secrets.token_urlsafe(32))"

# Edit configuration
nano backend/.env
```

**Example `.env` file:**

```env
# Required
ADMIN_API_KEY=your-generated-api-key-here

# Database (SQLite default)
DATABASE_URL=sqlite:///./data/opentune.db

# Server URL (for bootstrap scripts)
SERVER_URL=https://opentune.company.com

# Git repos cache directory
REPOS_DIR=./data/repos

# Optional
PROJECT_NAME=opentune
DEBUG=false
```

### Step 5: Build Frontend

```bash
cd /opt/opentune/frontend

# Install Node dependencies
npm ci --no-audit

# Build for production
npm run build

# Verify build
ls -la dist/
```

### Step 6: Test Installation

```bash
cd /opt/opentune/backend
source ../venv/bin/activate

# Start server manually
uvicorn app.main:app --host 0.0.0.0 --port 8000

# Test in another terminal or browser
curl http://localhost:8000/health
# Should return: {"status":"healthy"}
```

Press `Ctrl+C` to stop the test server.

---

## Systemd Service

### Step 1: Create Service User

```bash
# Create system user (no login shell)
sudo useradd --system --no-create-home --shell /bin/false opentune

# Set ownership
sudo chown -R opentune:opentune /opt/opentune
```

### Step 2: Install Service File

```bash
# Copy service file
sudo cp /opt/opentune/deploy/opentune.service /etc/systemd/system/

# Or create manually:
sudo nano /etc/systemd/system/opentune.service
```

**Service file content:**

```ini
[Unit]
Description=OpenTune DSC Control Plane
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=opentune
Group=opentune
WorkingDirectory=/opt/opentune/backend
Environment="PATH=/opt/opentune/venv/bin"
EnvironmentFile=/opt/opentune/backend/.env
ExecStart=/opt/opentune/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/opentune/backend/data

[Install]
WantedBy=multi-user.target
```

### Step 3: Enable and Start

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable on boot
sudo systemctl enable opentune

# Start service
sudo systemctl start opentune

# Check status
sudo systemctl status opentune
```

### Service Commands

| Action | Command |
|--------|---------|
| Start | `sudo systemctl start opentune` |
| Stop | `sudo systemctl stop opentune` |
| Restart | `sudo systemctl restart opentune` |
| Status | `sudo systemctl status opentune` |
| Logs | `sudo journalctl -u opentune -f` |
| Last 100 logs | `sudo journalctl -u opentune -n 100` |

---

## Nginx & HTTPS

### Step 1: Install Nginx

```bash
sudo apt install -y nginx
```

### Step 2: Configure Virtual Host

```bash
# Copy configuration
sudo cp /opt/opentune/deploy/opentune.nginx /etc/nginx/sites-available/opentune

# Or create manually:
sudo nano /etc/nginx/sites-available/opentune
```

**Nginx configuration:**

```nginx
server {
    listen 80;
    server_name opentune.company.com;
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name opentune.company.com;

    # SSL certificates (configured by certbot)
    ssl_certificate /etc/letsencrypt/live/opentune.company.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/opentune.company.com/privkey.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000" always;

    # Logging
    access_log /var/log/nginx/opentune_access.log;
    error_log /var/log/nginx/opentune_error.log;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

### Step 3: Enable Site

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/opentune /etc/nginx/sites-enabled/

# Remove default site (optional)
sudo rm /etc/nginx/sites-enabled/default

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

### Step 4: SSL Certificate (Let's Encrypt)

```bash
# Install certbot
sudo apt install -y certbot python3-certbot-nginx

# Get certificate (follow prompts)
sudo certbot --nginx -d opentune.company.com

# Verify auto-renewal
sudo certbot renew --dry-run
```

### Step 5: Firewall

```bash
# Allow HTTP and HTTPS
sudo ufw allow 'Nginx Full'

# Remove direct port 8000 if previously opened
sudo ufw delete allow 8000

# Check status
sudo ufw status
```

---

## Post-Installation

### Verification Checklist

```bash
# 1. Service is running
sudo systemctl status opentune
# Should show: active (running)

# 2. Health check
curl http://localhost:8000/health
# Should return: {"status":"healthy"}

# 3. Nginx is running
sudo systemctl status nginx
# Should show: active (running)

# 4. HTTPS works
curl -I https://opentune.company.com
# Should return: HTTP/2 200

# 5. API responds
curl https://opentune.company.com/api/docs
# Should return Swagger UI HTML
```

### Directory Structure

After installation:

```
/opt/opentune/
├── backend/
│   ├── app/                    # Application code
│   ├── data/
│   │   ├── opentune.db        # SQLite database
│   │   └── repos/             # Cached Git repositories
│   ├── static/
│   │   └── agent/             # Agent files
│   ├── .env                   # Configuration
│   └── requirements.txt
├── frontend/
│   ├── dist/                  # Built frontend
│   └── src/
├── venv/                      # Python virtual environment
└── deploy/                    # Deployment files
```

### First Login

1. Open `https://opentune.company.com` in browser
2. Enter your `ADMIN_API_KEY` from `.env`
3. You're in! 🎉

---

## Maintenance

### Backup

```bash
# Backup database
sudo -u opentune cp /opt/opentune/backend/data/opentune.db \
    /opt/opentune/backend/data/backup-$(date +%Y%m%d).db

# Backup entire data directory
sudo tar czf /backup/opentune-$(date +%Y%m%d).tar.gz \
    /opt/opentune/backend/data \
    /opt/opentune/backend/.env
```

### Restore

```bash
# Stop service
sudo systemctl stop opentune

# Restore database
sudo -u opentune cp /backup/backup-20240115.db \
    /opt/opentune/backend/data/opentune.db

# Start service
sudo systemctl start opentune
```

### Update

```bash
cd /opt/opentune

# Stop service
sudo systemctl stop opentune

# Pull updates
git pull origin main

# Update Python dependencies
source venv/bin/activate
pip install -r backend/requirements.txt

# Rebuild frontend
cd frontend
npm ci --no-audit
npm run build

# Fix permissions
sudo chown -R opentune:opentune /opt/opentune

# Start service
sudo systemctl start opentune
```

### Log Rotation

Systemd journal handles log rotation automatically. To configure:

```bash
# Edit journald config
sudo nano /etc/systemd/journald.conf

# Set max size
SystemMaxUse=500M

# Restart journald
sudo systemctl restart systemd-journald
```

---

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u opentune -n 100 --no-pager

# Common issues:
# - Missing .env file
# - Wrong permissions
# - Port already in use
# - Python module not found

# Fix permissions
sudo chown -R opentune:opentune /opt/opentune

# Check port
sudo lsof -i :8000
```

### Frontend Not Loading

```bash
# Check if dist exists
ls -la /opt/opentune/frontend/dist/

# Rebuild if missing
cd /opt/opentune/frontend
npm run build

# Restart
sudo systemctl restart opentune
```

### Database Issues

```bash
# Check database file
ls -la /opt/opentune/backend/data/opentune.db

# Reset database (WARNING: deletes all data!)
sudo systemctl stop opentune
rm /opt/opentune/backend/data/opentune.db
sudo systemctl start opentune
```

### Git Clone Fails

```bash
# Test git manually
sudo -u opentune git clone https://github.com/test/repo.git /tmp/test

# Check network
curl -I https://github.com

# Check DNS
nslookup github.com
```

### Nginx 502 Bad Gateway

```bash
# Check if backend is running
curl http://localhost:8000/health

# Check nginx error log
sudo tail -f /var/log/nginx/opentune_error.log

# Restart both services
sudo systemctl restart opentune
sudo systemctl restart nginx
```

### SSL Certificate Issues

```bash
# Check certificate status
sudo certbot certificates

# Force renewal
sudo certbot renew --force-renewal

# Check nginx config
sudo nginx -t
```

---

## Security Hardening

### Firewall Rules

```bash
# Only allow SSH, HTTP, HTTPS
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

### Fail2ban (Optional)

```bash
# Install
sudo apt install -y fail2ban

# Create jail for nginx
sudo nano /etc/fail2ban/jail.local
```

```ini
[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
```

```bash
# Restart
sudo systemctl restart fail2ban
```

### File Permissions

```bash
# Secure .env file
sudo chmod 600 /opt/opentune/backend/.env
sudo chown opentune:opentune /opt/opentune/backend/.env

# Secure data directory
sudo chmod 750 /opt/opentune/backend/data
```

---

## Commands Reference

| Action | Command |
|--------|---------|
| Start service | `sudo systemctl start opentune` |
| Stop service | `sudo systemctl stop opentune` |
| Restart service | `sudo systemctl restart opentune` |
| View logs | `sudo journalctl -u opentune -f` |
| Check status | `sudo systemctl status opentune` |
| Health check | `curl http://localhost:8000/health` |
| Nginx reload | `sudo systemctl reload nginx` |
| SSL renew | `sudo certbot renew` |

---

## Quick Reference Card

```
┌────────────────────────────────────────────────────────┐
│                   OpenTune Quick Reference             │
├────────────────────────────────────────────────────────┤
│ Installation Path:  /opt/opentune                      │
│ Config File:        /opt/opentune/backend/.env         │
│ Database:           /opt/opentune/backend/data/        │
│ Service:            opentune.service                   │
│ Service User:       opentune                           │
│ Default Port:       8000 (behind nginx)                │
├────────────────────────────────────────────────────────┤
│ Start:    sudo systemctl start opentune                │
│ Stop:     sudo systemctl stop opentune                 │
│ Logs:     sudo journalctl -u opentune -f               │
│ Health:   curl http://localhost:8000/health            │
└────────────────────────────────────────────────────────┘
```
