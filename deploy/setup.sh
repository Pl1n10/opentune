#!/bin/bash
#
# OpenTune Setup Script
# Run this on a fresh Ubuntu 22.04+ server
#
# Usage: sudo ./setup.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo_error "Please run as root (sudo ./setup.sh)"
    exit 1
fi

INSTALL_DIR="/opt/opentune"
SERVICE_USER="opentune"

echo "=============================================="
echo "  OpenTune Setup Script"
echo "=============================================="
echo ""

# Step 1: Install system dependencies
echo_info "Installing system dependencies..."
apt-get update
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    git \
    curl

# Check versions
echo_info "Checking versions..."
python3 --version
node --version
npm --version

# Step 2: Create service user
if ! id "$SERVICE_USER" &>/dev/null; then
    echo_info "Creating service user: $SERVICE_USER"
    useradd --system --no-create-home --shell /bin/false $SERVICE_USER
else
    echo_info "User $SERVICE_USER already exists"
fi

# Step 3: Create installation directory
echo_info "Creating installation directory: $INSTALL_DIR"
mkdir -p $INSTALL_DIR
chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR

# Step 4: Check if code exists (assumes you've cloned the repo)
if [ ! -f "$INSTALL_DIR/backend/requirements.txt" ]; then
    echo_warn "Code not found in $INSTALL_DIR"
    echo_warn "Please clone the repository first:"
    echo ""
    echo "  git clone https://github.com/YOUR_USERNAME/opentune.git $INSTALL_DIR"
    echo ""
    echo "Then run this script again."
    exit 1
fi

# Step 5: Create Python virtual environment
echo_info "Creating Python virtual environment..."
python3 -m venv $INSTALL_DIR/venv
source $INSTALL_DIR/venv/bin/activate

# Step 6: Install Python dependencies
echo_info "Installing Python dependencies..."
pip install --upgrade pip
pip install -r $INSTALL_DIR/backend/requirements.txt

# Step 7: Build frontend
echo_info "Building frontend..."
cd $INSTALL_DIR/frontend
npm install
npm run build

# Step 8: Create .env if it doesn't exist
if [ ! -f "$INSTALL_DIR/backend/.env" ]; then
    echo_info "Creating .env file..."
    
    # Generate secure API key
    API_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
    
    cat > $INSTALL_DIR/backend/.env << EOF
# OpenTune Configuration
PROJECT_NAME=opentune
DATABASE_URL=sqlite:///./opentune.db
ADMIN_API_KEY=$API_KEY
DEBUG=false
EOF
    
    echo_info "Generated new ADMIN_API_KEY: $API_KEY"
    echo_warn "SAVE THIS KEY! You'll need it to log in."
else
    echo_info ".env file already exists, skipping..."
fi

# Step 9: Set permissions
echo_info "Setting permissions..."
chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR

# Step 10: Install systemd service
echo_info "Installing systemd service..."
cp $INSTALL_DIR/deploy/opentune.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable opentune

# Step 11: Start the service
echo_info "Starting OpenTune service..."
systemctl start opentune

# Wait a moment for startup
sleep 3

# Check status
if systemctl is-active --quiet opentune; then
    echo ""
    echo "=============================================="
    echo -e "${GREEN}  OpenTune installed successfully!${NC}"
    echo "=============================================="
    echo ""
    echo "  URL: http://$(hostname -I | awk '{print $1}'):8000"
    echo ""
    echo "  Commands:"
    echo "    systemctl status opentune   - Check status"
    echo "    systemctl restart opentune  - Restart service"
    echo "    journalctl -u opentune -f   - View logs"
    echo ""
    echo "  API Key is in: $INSTALL_DIR/backend/.env"
    echo ""
else
    echo_error "Service failed to start. Check logs with:"
    echo "  journalctl -u opentune -n 50"
fi
