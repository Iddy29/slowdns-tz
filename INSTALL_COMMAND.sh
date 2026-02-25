#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║         A.I SLOWDNS TZ - Quick Install Command               ║
# ║              Run this on your Ubuntu VPS                      ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# ---- CONFIGURE THIS ----
GITHUB_USER="Iddy29"
REPO_NAME="slowdns-tz"
BRANCH="main"
# -------------------------

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH"
INSTALL_DIR="/opt/ai-slowdns-tz"

echo ""
echo "  [*] A.I SLOWDNS TZ - Quick Installer"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "  [!] This script must be run as root"
    echo "  [!] Run: sudo bash INSTALL_COMMAND.sh"
    exit 1
fi

# Pre-install essential tools (bc, wget, curl needed before main script)
echo "  [*] Installing essential tools..."
apt-get update -qq > /dev/null 2>&1
apt-get install -y bc wget curl > /dev/null 2>&1
echo "  [+] Essential tools ready"

# Create install directory
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/scripts"

# Download files
echo "  [*] Downloading files from GitHub..."

download_ok=true

if wget -q "$BASE_URL/SLOWDNS-TZ.sh" -O "$INSTALL_DIR/SLOWDNS-TZ.sh"; then
    echo "  [+] SLOWDNS-TZ.sh"
else
    echo "  [-] FAILED: SLOWDNS-TZ.sh"
    download_ok=false
fi

if wget -q "$BASE_URL/scripts/ai-monitor.sh" -O "$INSTALL_DIR/scripts/ai-monitor.sh"; then
    echo "  [+] scripts/ai-monitor.sh"
else
    echo "  [-] FAILED: scripts/ai-monitor.sh"
fi

if wget -q "$BASE_URL/scripts/ai-optimizer.py" -O "$INSTALL_DIR/scripts/ai-optimizer.py"; then
    echo "  [+] scripts/ai-optimizer.py"
else
    echo "  [-] FAILED: scripts/ai-optimizer.py"
fi

if [ "$download_ok" = false ]; then
    echo ""
    echo "  [!] Main script download failed. Check your internet connection."
    exit 1
fi

# Set permissions
chmod +x "$INSTALL_DIR/SLOWDNS-TZ.sh"
chmod +x "$INSTALL_DIR/scripts/ai-monitor.sh" 2>/dev/null
chmod +x "$INSTALL_DIR/scripts/ai-optimizer.py" 2>/dev/null

# Create symlink
ln -sf "$INSTALL_DIR/SLOWDNS-TZ.sh" /usr/local/bin/slowdns-tz

echo ""
echo "  [+] Download complete!"
echo "  [*] Launching A.I SLOWDNS TZ..."
echo ""

# Run the script directly (NOT piped) so interactive input works
exec bash "$INSTALL_DIR/SLOWDNS-TZ.sh"
