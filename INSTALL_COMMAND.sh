#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║         A.I SLOWDNS TZ - Quick Install Command               ║
# ║              Run this on your Ubuntu VPS                      ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---- CONFIGURE THIS ----
GITHUB_USER="Iddy29"
REPO_NAME="slowdns-tz"
BRANCH="main"
# -------------------------

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH"
INSTALL_DIR="/opt/ai-slowdns-tz"

echo -e "${CYAN}[*] A.I SLOWDNS TZ - Quick Installer${NC}"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Install dependencies
echo -e "${CYAN}[*] Installing dependencies...${NC}"
apt update -qq > /dev/null 2>&1
apt install -y wget curl > /dev/null 2>&1

# Create install directory
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/scripts"

# Download files
echo -e "${CYAN}[*] Downloading files from GitHub...${NC}"

wget -q "$BASE_URL/SLOWDNS-TZ.sh" -O "$INSTALL_DIR/SLOWDNS-TZ.sh"
wget -q "$BASE_URL/scripts/ai-monitor.sh" -O "$INSTALL_DIR/scripts/ai-monitor.sh"
wget -q "$BASE_URL/scripts/ai-optimizer.py" -O "$INSTALL_DIR/scripts/ai-optimizer.py"

# Set permissions
chmod +x "$INSTALL_DIR/SLOWDNS-TZ.sh"
chmod +x "$INSTALL_DIR/scripts/ai-monitor.sh"
chmod +x "$INSTALL_DIR/scripts/ai-optimizer.py"

echo -e "${GREEN}[+] Download complete!${NC}"
echo ""

# Launch main script
echo -e "${CYAN}[*] Launching A.I SLOWDNS TZ...${NC}"
echo ""
bash "$INSTALL_DIR/SLOWDNS-TZ.sh"
