#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║         A.I SLOWDNS TZ - One Click Installer                 ║
# ║              For Ubuntu/Debian VPS Systems                   ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# ---- CONFIGURE THIS ----
GITHUB_USER="Iddy29"
REPO_NAME="slowdns-tz"
BRANCH="main"
# -------------------------

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH"
INSTALL_DIR="/opt/ai-slowdns-tz"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] This script must be run as root${NC}"
    echo -e "${YELLOW}    Run: sudo bash one-click-install.sh${NC}"
    exit 1
fi

# Detect OS
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            echo -e "${YELLOW}[!] Warning: This script is optimized for Ubuntu/Debian. Detected: $PRETTY_NAME${NC}"
            read -p "    Continue anyway? (y/n): " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
        fi
    fi
}

# Banner
clear
echo -e "${PURPLE}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║         A.I SLOWDNS TZ INSTALLER              ║"
echo "  ║     SlowDNS + DNSTT SSH Tunnel Setup          ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

check_os

# Install dependencies
echo -e "${CYAN}[1/4] Installing dependencies...${NC}"
apt update -qq > /dev/null 2>&1
apt install -y wget curl git > /dev/null 2>&1
echo -e "${GREEN}  [+] Dependencies installed${NC}"

# Create directories
echo -e "${CYAN}[2/4] Creating directories...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$INSTALL_DIR/config"
mkdir -p "$INSTALL_DIR/logs"
echo -e "${GREEN}  [+] Directories created${NC}"

# Download all files
echo -e "${CYAN}[3/4] Downloading files from GitHub...${NC}"

download_file() {
    local file=$1
    local dest=$2
    if wget -q "$BASE_URL/$file" -O "$dest" 2>/dev/null; then
        echo -e "  ${GREEN}[+]${NC} $file"
    else
        echo -e "  ${RED}[-]${NC} Failed: $file"
        return 1
    fi
}

download_file "SLOWDNS-TZ.sh" "$INSTALL_DIR/SLOWDNS-TZ.sh"
download_file "scripts/ai-monitor.sh" "$INSTALL_DIR/scripts/ai-monitor.sh"
download_file "scripts/ai-optimizer.py" "$INSTALL_DIR/scripts/ai-optimizer.py"

# Set permissions
chmod +x "$INSTALL_DIR/SLOWDNS-TZ.sh"
chmod +x "$INSTALL_DIR/scripts/ai-monitor.sh"
chmod +x "$INSTALL_DIR/scripts/ai-optimizer.py"

echo -e "${GREEN}  [+] All files downloaded${NC}"

# Create symlink for easy access
echo -e "${CYAN}[4/4] Setting up...${NC}"
ln -sf "$INSTALL_DIR/SLOWDNS-TZ.sh" /usr/local/bin/slowdns-tz
echo -e "${GREEN}  [+] Command 'slowdns-tz' created${NC}"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Installation Complete!                 ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Starting A.I SLOWDNS TZ...${NC}"
echo ""

# Launch
bash "$INSTALL_DIR/SLOWDNS-TZ.sh"
