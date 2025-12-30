#!/bin/bash
#
# OpenTune Deployment Script
# For: Ubuntu 24.04 LTS on Proxmox + Cloudflare Tunnel
#
# Usage:
#   curl -fsSL https://opentune.robertonovara.dev/static/deploy.sh | sudo bash
#   # oppure
#   sudo bash deploy.sh
#
# Prerequisites:
#   - Ubuntu 24.04 LTS (VM or LXC container)
#   - Root access
#   - Internet connection
#   - Cloudflare account with domain configured
#

set -e

# =============================================================================
# Configuration
# =============================================================================

INSTALL_DIR="/opt/opentune"
REPO_URL="https://github.com/Pl1n10/opentune"  # Se disponibile
ZIP_URL=""  # Lascia vuoto se usi upload manuale
DOMAIN="opentune.robertonovara.dev"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║              OpenTune Deployment Script v1.0                  ║"
    echo "║          Proxmox + Cloudflare Tunnel Edition                  ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        log_warn "This script is designed for Ubuntu. Proceeding anyway..."
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -p "$prompt" response
    response=${response:-$default}
    
    [[ "$response" =~ ^[Yy]$ ]]
}

generate_api_key() {
    python3 -c "import secrets; print(secrets.token_urlsafe(32))"
}

# =============================================================================
# Installation Steps
# =============================================================================

install_dependencies() {
    log_info "Installing system dependencies..."
    
    apt-get update -qq
    apt-get install -y -qq \
        curl \
        wget \
        unzip \
        git \
        python3 \
        ca-certificates \
        gnupg \
        lsb-release
    
    log_success "System dependencies installed"
}

install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker already installed: $(docker --version)"
        return
    fi
    
    log_info "Installing Docker..."
    
    curl -fsSL https://get.docker.com | sh
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    log_success "Docker installed: $(docker --version)"
}

install_cloudflared() {
    if command -v cloudflared &> /dev/null; then
        log_success "cloudflared already installed: $(cloudflared --version)"
        return
    fi
    
    log_info "Installing cloudflared..."
    
    # Add Cloudflare GPG key
    mkdir -p /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    
    # Add repository
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
    
    apt-get update -qq
    apt-get install -y -qq cloudflared
    
    log_success "cloudflared installed: $(cloudflared --version)"
}

setup_cloudflare_tunnel() {
    echo ""
    log_info "Cloudflare Tunnel Setup"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    echo "To create a tunnel:"
    echo "  1. Go to https://one.dash.cloudflare.com/"
    echo "  2. Networks → Tunnels → Create a tunnel"
    echo "  3. Select 'Cloudflared' connector"
    echo "  4. Name it: opentune"
    echo "  5. Copy the token"
    echo ""
    
    read -p "Paste your Cloudflare Tunnel token (or press Enter to skip): " CF_TOKEN
    
    if [[ -n "$CF_TOKEN" ]]; then
        log_info "Installing cloudflared service..."
        
        # Stop existing service if any
        systemctl stop cloudflared 2>/dev/null || true
        
        # Install with token
        cloudflared service install "$CF_TOKEN"
        
        systemctl enable cloudflared
        systemctl start cloudflared
        
        log_success "Cloudflare Tunnel configured and running"
        
        echo ""
        log_warn "IMPORTANT: Configure the tunnel route in Cloudflare Dashboard:"
        echo "  - Public hostname: ${DOMAIN}"
        echo "  - Service: http://localhost:8000"
        echo ""
        read -p "Press Enter when you've configured the route..."
    else
        log_warn "Skipping Cloudflare Tunnel setup"
        log_warn "You'll need to configure it manually later"
    fi
}

download_opentune() {
    log_info "Setting up OpenTune directory..."
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Check if already exists
    if [[ -d "$INSTALL_DIR/dsc-cp" ]]; then
        if prompt_yes_no "OpenTune already exists. Overwrite?" "n"; then
            rm -rf "$INSTALL_DIR/dsc-cp"
        else
            log_info "Using existing installation"
            return
        fi
    fi
    
    echo ""
    echo "How do you want to install OpenTune?"
    echo "  [1] Upload ZIP manually (I'll wait)"
    echo "  [2] Clone from GitHub"
    echo "  [3] Download from URL"
    echo ""
    read -p "Choice [1]: " install_method
    install_method=${install_method:-1}
    
    case $install_method in
        1)
            echo ""
            log_info "Please upload opentune-v1.0-secure.zip to: $INSTALL_DIR/"
            echo ""
            echo "From your local machine, run:"
            echo "  scp opentune-v1.0-secure.zip root@$(hostname -I | awk '{print $1}'):$INSTALL_DIR/"
            echo ""
            read -p "Press Enter when the file is uploaded..."
            
            if [[ -f "$INSTALL_DIR/opentune-v1.0-secure.zip" ]]; then
                unzip -q opentune-v1.0-secure.zip
                rm opentune-v1.0-secure.zip
                log_success "OpenTune extracted"
            else
                log_error "ZIP file not found!"
                exit 1
            fi
            ;;
        2)
            log_info "Cloning from GitHub..."
            git clone "$REPO_URL" dsc-cp
            log_success "OpenTune cloned"
            ;;
        3)
            read -p "Enter ZIP URL: " ZIP_URL
            wget -q "$ZIP_URL" -O opentune.zip
            unzip -q opentune.zip
            rm opentune.zip
            log_success "OpenTune downloaded and extracted"
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

configure_opentune() {
    log_info "Configuring OpenTune..."
    
    cd "$INSTALL_DIR/dsc-cp"
    
    # Create data directories
    mkdir -p data repos
    
    # Generate API key
    if [[ -f ".env" ]]; then
        log_warn "Existing .env found"
        if prompt_yes_no "Generate new API key?" "n"; then
            API_KEY=$(generate_api_key)
        else
            log_info "Keeping existing configuration"
            return
        fi
    else
        API_KEY=$(generate_api_key)
    fi
    
    # Create .env file
    cat > .env << EOF
# OpenTune Configuration
# Generated: $(date)

# Admin API Key - KEEP THIS SECRET!
ADMIN_API_KEY=${API_KEY}

# Database
DATABASE_URL=sqlite:///./data/opentune.db

# Server URL (used for bootstrap scripts)
SERVER_URL=https://${DOMAIN}

# Debug mode (set to True only for development)
DEBUG=False
EOF

    chmod 600 .env
    
    log_success "Configuration created"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${GREEN}  YOUR ADMIN API KEY (save this somewhere safe!):${NC}"
    echo ""
    echo -e "  ${YELLOW}${API_KEY}${NC}"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    read -p "Press Enter after you've saved the API key..."
}

build_and_start() {
    log_info "Building and starting OpenTune..."
    
    cd "$INSTALL_DIR/dsc-cp"
    
    # Build and start
    docker compose up -d --build
    
    # Wait for startup
    log_info "Waiting for OpenTune to start..."
    sleep 5
    
    # Check health
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if curl -s http://localhost:8000/health | grep -q "healthy"; then
            log_success "OpenTune is running!"
            return
        fi
        sleep 2
        ((retries--))
    done
    
    log_error "OpenTune failed to start. Check logs with: docker compose logs"
    exit 1
}

create_systemd_service() {
    log_info "Creating systemd service for auto-start..."
    
    cat > /etc/systemd/system/opentune.service << EOF
[Unit]
Description=OpenTune DSC Control Plane
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}/dsc-cp
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable opentune.service
    
    log_success "Systemd service created (auto-starts on boot)"
}

print_summary() {
    local IP=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║              OpenTune Deployment Complete! 🎉                 ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "URLs:"
    echo "  • Local:    http://${IP}:8000"
    echo "  • Public:   https://${DOMAIN}"
    echo "  • Health:   https://${DOMAIN}/health"
    echo ""
    echo "Test from Windows (PowerShell as Admin):"
    echo "  iwr https://${DOMAIN}/static/setup.ps1 | iex"
    echo ""
    echo "Useful commands:"
    echo "  cd ${INSTALL_DIR}/dsc-cp"
    echo "  docker compose logs -f      # View logs"
    echo "  docker compose restart      # Restart"
    echo "  docker compose down         # Stop"
    echo "  systemctl status cloudflared  # Tunnel status"
    echo ""
    echo "Configuration:"
    echo "  • Install dir: ${INSTALL_DIR}/dsc-cp"
    echo "  • Config file: ${INSTALL_DIR}/dsc-cp/.env"
    echo "  • Database:    ${INSTALL_DIR}/dsc-cp/data/opentune.db"
    echo ""
    
    if ! systemctl is-active --quiet cloudflared; then
        echo -e "${YELLOW}⚠ Cloudflare Tunnel is not running!${NC}"
        echo "  Run: cloudflared service install <YOUR_TOKEN>"
        echo ""
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    print_banner
    
    check_root
    check_ubuntu
    
    echo "This script will install:"
    echo "  • Docker"
    echo "  • Cloudflared (Cloudflare Tunnel)"
    echo "  • OpenTune (Docker container)"
    echo ""
    
    if ! prompt_yes_no "Continue with installation?" "y"; then
        echo "Aborted."
        exit 0
    fi
    
    echo ""
    
    install_dependencies
    install_docker
    install_cloudflared
    setup_cloudflare_tunnel
    download_opentune
    configure_opentune
    build_and_start
    create_systemd_service
    print_summary
}

# Run main function
main "$@"
