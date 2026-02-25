#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║            A.I SLOWDNS TZ - Ultra Speed Edition              ║
# ║        SlowDNS + DNSTT SSH Tunnel Optimizer v3.0             ║
# ║              Transform Slow DNS to Lightning Fast            ║
# ╚══════════════════════════════════════════════════════════════╝

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- Global Config ---
INSTALL_DIR="/opt/ai-slowdns-tz"
CONFIG_FILE="$INSTALL_DIR/config/slowdns.conf"
USERS_DB="$INSTALL_DIR/config/users.db"
LOG_DIR="$INSTALL_DIR/logs"
DNSTT_BIN="$INSTALL_DIR/dnstt-server"
PRIVKEY_FILE="$INSTALL_DIR/server.key"
PUBKEY_FILE="$INSTALL_DIR/server.pub"
DEFAULT_MTU=512
DNSTT_PORT=5300
SSH_PORT=22
GO_VERSION="1.22.5"

# --- Helper Functions ---
print_header() {
    clear
    echo -e "${PURPLE}"
    cat << "LOGO"
     ___    ___   ___ _    _____      ____  _  _ ___    _____ ____
    / _ |  |_ _| / __| |  / _ \ \    / /  \| \| / __|  |_   _|_  /
   / __ |   | |  \__ \ |_| (_) \ \/\/ /| .` |  \__ \    | |  / /
  /_/ |_|  |___| |___/____\___/ \_/\_/ |_|\_|_|\_|___/   |_| /___|

              SLOWDNS + DNSTT SSH TUNNEL OPTIMIZER v3.0
LOGO
    echo -e "${NC}"
}

progress_bar() {
    local duration=$1
    local width=50
    local progress=0
    # Calculate sleep interval without bc (use awk as fallback)
    local sleep_time
    if command -v bc &>/dev/null; then
        sleep_time=$(echo "scale=3; $duration / 50" | bc)
    elif command -v awk &>/dev/null; then
        sleep_time=$(awk "BEGIN {printf \"%.3f\", $duration / 50}")
    else
        sleep_time="0.04"
    fi
    while [ $progress -le 100 ]; do
        local filled=$((progress * width / 100))
        local empty=$((width - filled))
        printf "\r${CYAN}["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' '-'
        printf "] %d%%${NC}" $progress
        progress=$((progress + 2))
        sleep "$sleep_time"
    done
    printf "\n"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root. Use: sudo $0${NC}"
        exit 1
    fi
}

log_msg() {
    local level=$1
    local msg=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_DIR/install.log" 2>/dev/null
}

# Load config if exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
# A.I SLOWDNS TZ Configuration
# Generated: $(date)
DOMAIN=$DOMAIN
NAMESERVER=$NAMESERVER
MTU_SIZE=$MTU_SIZE
DNSTT_PORT=$DNSTT_PORT
SSH_PORT=$SSH_PORT
EOF
    chmod 600 "$CONFIG_FILE"
}

# ========================================================================
# USER MANAGEMENT SYSTEM
# ========================================================================

init_users_db() {
    mkdir -p "$(dirname "$USERS_DB")"
    if [[ ! -f "$USERS_DB" ]]; then
        echo "# A.I SLOWDNS TZ Users Database" > "$USERS_DB"
        echo "# Format: username|created_date|expiry_date|status" >> "$USERS_DB"
        chmod 600 "$USERS_DB"
    fi
}

create_user() {
    echo -e "\n${CYAN}=== Create New User ===${NC}"
    read -p "$(echo -e "${YELLOW}Enter username: ${NC}")" new_user

    # Validate username
    if [[ -z "$new_user" ]]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        return 1
    fi

    if id "$new_user" &>/dev/null; then
        echo -e "${RED}User '$new_user' already exists on this system.${NC}"
        return 1
    fi

    if grep -q "^${new_user}|" "$USERS_DB" 2>/dev/null; then
        echo -e "${RED}User '$new_user' already exists in database.${NC}"
        return 1
    fi

    # Get password
    read -s -p "$(echo -e "${YELLOW}Enter password: ${NC}")" new_pass
    echo
    read -s -p "$(echo -e "${YELLOW}Confirm password: ${NC}")" confirm_pass
    echo

    if [[ "$new_pass" != "$confirm_pass" ]]; then
        echo -e "${RED}Passwords do not match.${NC}"
        return 1
    fi

    if [[ ${#new_pass} -lt 6 ]]; then
        echo -e "${RED}Password must be at least 6 characters.${NC}"
        return 1
    fi

    # Get expiry
    echo -e "\n${YELLOW}Set account expiry:${NC}"
    echo -e "  ${CYAN}1)${NC} 7 days"
    echo -e "  ${CYAN}2)${NC} 14 days"
    echo -e "  ${CYAN}3)${NC} 30 days"
    echo -e "  ${CYAN}4)${NC} 60 days"
    echo -e "  ${CYAN}5)${NC} 90 days"
    echo -e "  ${CYAN}6)${NC} No expiry (permanent)"
    echo -e "  ${CYAN}7)${NC} Custom days"
    read -p "$(echo -e "${YELLOW}Select [1-7]: ${NC}")" expiry_choice

    local expiry_days=0
    local expiry_date="permanent"
    case $expiry_choice in
        1) expiry_days=7 ;;
        2) expiry_days=14 ;;
        3) expiry_days=30 ;;
        4) expiry_days=60 ;;
        5) expiry_days=90 ;;
        6) expiry_days=0 ;;
        7)
            read -p "$(echo -e "${YELLOW}Enter number of days: ${NC}")" expiry_days
            if ! [[ "$expiry_days" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Invalid number.${NC}"
                return 1
            fi
            ;;
        *) expiry_days=30 ;;
    esac

    # Create system user with SSH access
    useradd -m -s /bin/bash "$new_user"
    echo "$new_user:$new_pass" | chpasswd

    local created_date
    created_date=$(date '+%Y-%m-%d')

    if [[ $expiry_days -gt 0 ]]; then
        expiry_date=$(date -d "+${expiry_days} days" '+%Y-%m-%d')
        chage -E "$expiry_date" "$new_user"
    fi

    # Record in database
    echo "${new_user}|${created_date}|${expiry_date}|active" >> "$USERS_DB"

    echo -e "\n${GREEN}User created successfully!${NC}"
    echo -e "${CYAN}+--------------------------+${NC}"
    echo -e "${CYAN}| Username : ${WHITE}$new_user${NC}"
    echo -e "${CYAN}| Password : ${WHITE}$new_pass${NC}"
    echo -e "${CYAN}| Created  : ${WHITE}$created_date${NC}"
    echo -e "${CYAN}| Expires  : ${WHITE}$expiry_date${NC}"
    echo -e "${CYAN}+--------------------------+${NC}"
    log_msg "INFO" "User created: $new_user (expires: $expiry_date)"
}

list_users() {
    echo -e "\n${CYAN}=== SlowDNS Users ===${NC}"
    if [[ ! -f "$USERS_DB" ]] || [[ $(grep -c '^[^#]' "$USERS_DB") -eq 0 ]]; then
        echo -e "${YELLOW}No users found.${NC}"
        return
    fi

    echo -e "${WHITE}%-15s %-12s %-12s %-10s %-10s${NC}" "USERNAME" "CREATED" "EXPIRES" "STATUS" "LOGGED IN"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"

    while IFS='|' read -r username created expires status; do
        [[ "$username" =~ ^#.*$ ]] && continue
        [[ -z "$username" ]] && continue

        # Check if user is currently logged in
        local logged_in="No"
        if who | grep -q "^${username} "; then
            logged_in="${GREEN}Yes${NC}"
        fi

        # Check if expired
        if [[ "$expires" != "permanent" ]]; then
            local today_epoch
            local expiry_epoch
            today_epoch=$(date +%s)
            expiry_epoch=$(date -d "$expires" +%s 2>/dev/null || echo 0)
            if [[ $today_epoch -gt $expiry_epoch && $expiry_epoch -gt 0 ]]; then
                status="${RED}expired${NC}"
            fi
        fi

        printf "  %-15s %-12s %-12s %-10b %-10b\n" "$username" "$created" "$expires" "$status" "$logged_in"
    done < "$USERS_DB"
}

delete_user() {
    echo -e "\n${CYAN}=== Delete User ===${NC}"
    list_users
    echo
    read -p "$(echo -e "${YELLOW}Enter username to delete: ${NC}")" del_user

    if [[ -z "$del_user" ]]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        return 1
    fi

    if ! grep -q "^${del_user}|" "$USERS_DB" 2>/dev/null; then
        echo -e "${RED}User '$del_user' not found in database.${NC}"
        return 1
    fi

    read -p "$(echo -e "${RED}Are you sure you want to delete '$del_user'? (y/n): ${NC}")" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        return
    fi

    # Kill user sessions
    pkill -u "$del_user" 2>/dev/null

    # Remove system user
    userdel -r "$del_user" 2>/dev/null

    # Remove from database
    sed -i "/^${del_user}|/d" "$USERS_DB"

    echo -e "${GREEN}User '$del_user' deleted successfully.${NC}"
    log_msg "INFO" "User deleted: $del_user"
}

change_user_password() {
    echo -e "\n${CYAN}=== Change User Password ===${NC}"
    list_users
    echo
    read -p "$(echo -e "${YELLOW}Enter username: ${NC}")" chg_user

    if ! id "$chg_user" &>/dev/null; then
        echo -e "${RED}User '$chg_user' does not exist.${NC}"
        return 1
    fi

    read -s -p "$(echo -e "${YELLOW}Enter new password: ${NC}")" new_pass
    echo
    read -s -p "$(echo -e "${YELLOW}Confirm new password: ${NC}")" confirm_pass
    echo

    if [[ "$new_pass" != "$confirm_pass" ]]; then
        echo -e "${RED}Passwords do not match.${NC}"
        return 1
    fi

    echo "$chg_user:$new_pass" | chpasswd
    echo -e "${GREEN}Password changed for '$chg_user'.${NC}"
    log_msg "INFO" "Password changed for user: $chg_user"
}

renew_user() {
    echo -e "\n${CYAN}=== Renew User Expiry ===${NC}"
    list_users
    echo
    read -p "$(echo -e "${YELLOW}Enter username to renew: ${NC}")" ren_user

    if ! grep -q "^${ren_user}|" "$USERS_DB" 2>/dev/null; then
        echo -e "${RED}User '$ren_user' not found.${NC}"
        return 1
    fi

    echo -e "${YELLOW}Extend by how many days?${NC}"
    echo -e "  ${CYAN}1)${NC} 7 days"
    echo -e "  ${CYAN}2)${NC} 14 days"
    echo -e "  ${CYAN}3)${NC} 30 days"
    echo -e "  ${CYAN}4)${NC} 60 days"
    echo -e "  ${CYAN}5)${NC} 90 days"
    echo -e "  ${CYAN}6)${NC} Set permanent"
    echo -e "  ${CYAN}7)${NC} Custom days"
    read -p "$(echo -e "${YELLOW}Select [1-7]: ${NC}")" ext_choice

    local ext_days=0
    local new_expiry="permanent"
    case $ext_choice in
        1) ext_days=7 ;;
        2) ext_days=14 ;;
        3) ext_days=30 ;;
        4) ext_days=60 ;;
        5) ext_days=90 ;;
        6) ext_days=0 ;;
        7)
            read -p "$(echo -e "${YELLOW}Enter number of days: ${NC}")" ext_days
            ;;
        *) ext_days=30 ;;
    esac

    if [[ $ext_days -gt 0 ]]; then
        new_expiry=$(date -d "+${ext_days} days" '+%Y-%m-%d')
        chage -E "$new_expiry" "$ren_user"
    else
        chage -E -1 "$ren_user"
    fi

    # Update database
    local old_line
    old_line=$(grep "^${ren_user}|" "$USERS_DB")
    local created
    created=$(echo "$old_line" | cut -d'|' -f2)
    sed -i "/^${ren_user}|/c\\${ren_user}|${created}|${new_expiry}|active" "$USERS_DB"

    echo -e "${GREEN}User '$ren_user' renewed. New expiry: $new_expiry${NC}"
    log_msg "INFO" "User renewed: $ren_user (new expiry: $new_expiry)"
}

user_management_menu() {
    while true; do
        echo -e "\n${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║       USER MANAGEMENT SYSTEM         ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        echo -e "  ${CYAN}1)${NC} Create User"
        echo -e "  ${CYAN}2)${NC} List Users"
        echo -e "  ${CYAN}3)${NC} Delete User"
        echo -e "  ${CYAN}4)${NC} Change Password"
        echo -e "  ${CYAN}5)${NC} Renew / Extend Expiry"
        echo -e "  ${CYAN}6)${NC} Back to Main Menu"
        echo
        read -p "$(echo -e "${YELLOW}Select [1-6]: ${NC}")" user_choice
        case $user_choice in
            1) create_user ;;
            2) list_users ;;
            3) delete_user ;;
            4) change_user_password ;;
            5) renew_user ;;
            6) return ;;
            *) echo -e "${RED}Invalid option.${NC}" ;;
        esac
    done
}

# ========================================================================
# MTU SELECTION
# ========================================================================

select_mtu() {
    echo -e "\n${CYAN}=== MTU Size Selection ===${NC}"
    echo -e "${YELLOW}MTU controls the max DNS response payload size.${NC}"
    echo -e "${YELLOW}Lower MTU = more compatible but slower.${NC}"
    echo -e "${YELLOW}Higher MTU = faster but may be blocked by some networks.${NC}"
    echo
    echo -e "  ${CYAN}1)${NC} 512  (Default - most compatible, works on restrictive networks)"
    echo -e "  ${CYAN}2)${NC} 760  (Balanced - good speed and compatibility)"
    echo -e "  ${CYAN}3)${NC} 1024 (Fast - works on most networks)"
    echo -e "  ${CYAN}4)${NC} 1232 (Maximum - best speed, may not work everywhere)"
    echo -e "  ${CYAN}5)${NC} Custom MTU size"
    echo
    read -p "$(echo -e "${YELLOW}Select MTU [1-5] (default: 1 = 512): ${NC}")" mtu_choice

    case $mtu_choice in
        1|"") MTU_SIZE=512 ;;
        2) MTU_SIZE=760 ;;
        3) MTU_SIZE=1024 ;;
        4) MTU_SIZE=1232 ;;
        5)
            read -p "$(echo -e "${YELLOW}Enter custom MTU (128-1452): ${NC}")" custom_mtu
            if [[ "$custom_mtu" =~ ^[0-9]+$ ]] && [[ $custom_mtu -ge 128 ]] && [[ $custom_mtu -le 1452 ]]; then
                MTU_SIZE=$custom_mtu
            else
                echo -e "${RED}Invalid MTU. Using default 512.${NC}"
                MTU_SIZE=512
            fi
            ;;
        *) MTU_SIZE=512 ;;
    esac

    echo -e "${GREEN}MTU set to: $MTU_SIZE${NC}"
}

# ========================================================================
# INSTALLATION
# ========================================================================

install_dependencies() {
    echo -e "\n${YELLOW}[1/8] Installing System Dependencies...${NC}"

    # Install bc first (needed for progress_bar and version checks)
    apt-get update -qq > /dev/null 2>&1
    apt-get install -y bc > /dev/null 2>&1

    # Install all other dependencies
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        wget curl iptables iptables-persistent net-tools dnsutils \
        screen jq openssh-server golang-go git 2>/dev/null || {
        echo -e "${YELLOW}  Some packages may have failed, retrying...${NC}"
        apt-get install -y wget curl iptables net-tools dnsutils \
            screen jq openssh-server git > /dev/null 2>&1
    }

    # If golang from apt is too old or missing, install manually
    local go_ver
    go_ver=$(go version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
    local need_go=false
    if [[ -z "$go_ver" ]]; then
        need_go=true
    elif command -v bc &>/dev/null && (( $(echo "$go_ver < 1.21" | bc -l) )); then
        need_go=true
    fi

    if [[ "$need_go" == "true" ]]; then
        echo -e "${CYAN}Installing Go $GO_VERSION...${NC}"
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh
        rm -f /tmp/go.tar.gz
    fi

    progress_bar 2
    echo -e "${GREEN}Dependencies installed.${NC}"
}

configure_ssh() {
    echo -e "\n${YELLOW}[2/8] Configuring SSH Server...${NC}"

    # Enable password authentication for SSH (needed for SlowDNS users)
    # Use a drop-in config so we don't break existing sshd_config
    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/99-slowdns.conf << 'SSHCONF'
# A.I SLOWDNS TZ - SSH Configuration
PasswordAuthentication yes
PermitRootLogin yes
UsePAM yes
SSHCONF

    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
    progress_bar 1
    echo -e "${GREEN}SSH configured (password auth enabled).${NC}"
}

configure_network() {
    echo -e "\n${YELLOW}[3/8] Configuring Network (IPv4/IPv6 Forwarding)...${NC}"

    # Enable forwarding (idempotent - check before appending)
    grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    grep -q '^net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1

    progress_bar 1
    echo -e "${GREEN}Network forwarding enabled.${NC}"
}

build_dnstt() {
    echo -e "\n${YELLOW}[4/8] Building DNSTT Server from Source...${NC}"

    mkdir -p "$INSTALL_DIR"

    # Make sure Go is in PATH (if manually installed earlier)
    if [[ -d /usr/local/go/bin ]]; then
        export PATH=$PATH:/usr/local/go/bin
    fi

    local build_success=false

    # Try to build from source (preferred - always latest)
    if command -v go &>/dev/null; then
        echo -e "${CYAN}Go found: $(go version)${NC}"
        echo -e "${CYAN}Building dnstt-server from source...${NC}"
        rm -rf /tmp/dnstt-build
        mkdir -p /tmp/dnstt-build

        # Try multiple git sources
        if git clone https://www.bamsoftware.com/git/dnstt.git /tmp/dnstt-build/dnstt 2>/dev/null; then
            echo -e "${GREEN}  Cloned from bamsoftware.com${NC}"
        elif git clone https://github.com/refraction-networking/dnstt.git /tmp/dnstt-build/dnstt 2>/dev/null; then
            echo -e "${GREEN}  Cloned from github (refraction-networking)${NC}"
        elif git clone https://github.com/Mygod/dnstt.git /tmp/dnstt-build/dnstt 2>/dev/null; then
            echo -e "${GREEN}  Cloned from github (Mygod)${NC}"
        else
            echo -e "${RED}  Failed to clone dnstt source from all mirrors${NC}"
        fi

        if [[ -d "/tmp/dnstt-build/dnstt/dnstt-server" ]]; then
            cd /tmp/dnstt-build/dnstt/dnstt-server
            echo -e "${CYAN}  Compiling...${NC}"
            if go build -o "$DNSTT_BIN" 2>&1; then
                build_success=true
                echo -e "${GREEN}  Build successful!${NC}"
            else
                echo -e "${RED}  Go build failed${NC}"
            fi
            cd "$INSTALL_DIR"
        fi
        rm -rf /tmp/dnstt-build
    else
        echo -e "${YELLOW}Go not found, skipping build from source${NC}"
    fi

    # Fallback: download pre-built binary
    if [[ "$build_success" == "false" ]] || [[ ! -f "$DNSTT_BIN" ]]; then
        echo -e "${CYAN}Downloading pre-built dnstt-server binary...${NC}"
        # Try multiple sources
        wget -q "https://raw.githubusercontent.com/AvidalSharing/dnstt-server-binary/main/dnstt-server" -O "$DNSTT_BIN" 2>/dev/null || \
        wget -q "https://raw.githubusercontent.com/usfrfrjikrvj/DN/main/dnstt-server" -O "$DNSTT_BIN" 2>/dev/null || \
        echo -e "${RED}  Failed to download pre-built binary${NC}"
    fi

    if [[ ! -f "$DNSTT_BIN" ]]; then
        echo -e "${RED}FATAL: Could not build or download dnstt-server!${NC}"
        echo -e "${RED}Please install Go and retry, or provide the binary manually at: $DNSTT_BIN${NC}"
        log_msg "ERROR" "dnstt-server binary not available"
        exit 1
    fi

    chmod +x "$DNSTT_BIN"

    # Verify binary works (dnstt-server -help outputs usage to stderr)
    if "$DNSTT_BIN" -help 2>&1 | grep -qi "gen-key\|privkey\|udp\|DOMAIN" ; then
        echo -e "${GREEN}dnstt-server binary is functional.${NC}"
        log_msg "INFO" "dnstt-server binary verified OK"
    else
        echo -e "${YELLOW}WARNING: Could not verify dnstt-server binary. Will attempt to continue.${NC}"
        log_msg "WARN" "dnstt-server binary verification uncertain"
    fi

    progress_bar 2
}

generate_keys() {
    echo -e "\n${YELLOW}[5/8] Generating DNSTT Encryption Keys...${NC}"

    cd "$INSTALL_DIR"

    # DNSTT uses Noise protocol with Curve25519 keys (hex format)
    # Generated by: dnstt-server -gen-key -privkey-file FILE -pubkey-file FILE

    # Check if valid keys already exist (hex string, 64 chars)
    if [[ -f "$PRIVKEY_FILE" ]] && [[ -f "$PUBKEY_FILE" ]]; then
        local priv_content pub_content
        priv_content=$(head -1 "$PRIVKEY_FILE" 2>/dev/null | tr -d '[:space:]')
        pub_content=$(head -1 "$PUBKEY_FILE" 2>/dev/null | tr -d '[:space:]')
        if [[ ${#priv_content} -eq 64 ]] && [[ "$priv_content" =~ ^[0-9a-f]+$ ]] && \
           [[ ${#pub_content} -eq 64 ]] && [[ "$pub_content" =~ ^[0-9a-f]+$ ]]; then
            echo -e "${YELLOW}Existing valid keys found.${NC}"
            echo -e "${CYAN}Public key: ${pub_content}${NC}"
            echo
            read -p "$(echo -e "${YELLOW}Regenerate keys? (y/n, default: n): ${NC}")" regen
            if [[ "$regen" != "y" && "$regen" != "Y" ]]; then
                echo -e "${GREEN}Using existing keys.${NC}"
                return
            fi
        else
            echo -e "${YELLOW}Existing key files found but contain placeholder data. Generating new keys...${NC}"
        fi
    fi

    echo -e "${CYAN}Generating new Curve25519 keypair...${NC}"

    # Remove old placeholder/invalid key files
    rm -f "$PRIVKEY_FILE" "$PUBKEY_FILE"

    # Generate keys
    local keygen_output
    keygen_output=$("$DNSTT_BIN" -gen-key -privkey-file "$PRIVKEY_FILE" -pubkey-file "$PUBKEY_FILE" 2>&1)
    local keygen_rc=$?

    echo -e "${CYAN}  keygen output: ${keygen_output}${NC}"

    # Verify key files were created and contain valid hex keys
    if [[ ! -f "$PRIVKEY_FILE" ]] || [[ ! -f "$PUBKEY_FILE" ]]; then
        echo -e "${RED}Key files were not created!${NC}"

        # Fallback: try -gen-key without file flags (outputs to stdout)
        echo -e "${YELLOW}Trying fallback key generation...${NC}"
        keygen_output=$("$DNSTT_BIN" -gen-key 2>&1)
        local privkey pubkey
        privkey=$(echo "$keygen_output" | grep -i 'privkey' | grep -oE '[0-9a-f]{64}')
        pubkey=$(echo "$keygen_output" | grep -i 'pubkey' | grep -oE '[0-9a-f]{64}')

        if [[ -n "$privkey" ]] && [[ -n "$pubkey" ]]; then
            echo "$privkey" > "$PRIVKEY_FILE"
            echo "$pubkey" > "$PUBKEY_FILE"
            echo -e "${GREEN}Keys extracted from stdout output.${NC}"
        else
            echo -e "${RED}FATAL: Key generation failed completely!${NC}"
            echo -e "${RED}dnstt-server output: ${keygen_output}${NC}"
            echo -e "${RED}Make sure dnstt-server binary is working.${NC}"
            log_msg "ERROR" "Key generation failed"
            exit 1
        fi
    fi

    chmod 600 "$PRIVKEY_FILE"
    chmod 644 "$PUBKEY_FILE"

    local final_pubkey
    final_pubkey=$(head -1 "$PUBKEY_FILE" | tr -d '[:space:]')

    echo -e "\n${GREEN}Keys generated successfully!${NC}"
    echo -e "${CYAN}Private key: $PRIVKEY_FILE${NC}"
    echo -e "${CYAN}Public key:  $PUBKEY_FILE${NC}"
    echo -e "\n${WHITE}=========== PUBLIC KEY (give this to clients) ===========${NC}"
    echo -e "${GREEN}${final_pubkey}${NC}"
    echo -e "${WHITE}=========================================================${NC}"
    echo
    echo -e "${YELLOW}IMPORTANT: Clients need this public key to connect.${NC}"
    echo -e "${YELLOW}View later: cat $PUBKEY_FILE${NC}"
    read -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"

    log_msg "INFO" "New keypair generated"
    progress_bar 1
}

configure_domain() {
    echo -e "\n${YELLOW}[6/8] Domain & Nameserver Configuration...${NC}"

    echo -e "${CYAN}For DNSTT to work, you need:${NC}"
    echo -e "${CYAN}  1. A domain (e.g., example.com)${NC}"
    echo -e "${CYAN}  2. DNS records configured:${NC}"
    echo -e "${CYAN}     - A record:  tns.example.com -> YOUR_SERVER_IP${NC}"
    echo -e "${CYAN}     - NS record: t.example.com   -> tns.example.com${NC}"
    echo

    read -p "$(echo -e "${YELLOW}Enter your domain (e.g., example.com): ${NC}")" DOMAIN

    if [[ -z "$DOMAIN" ]]; then
        echo -e "${RED}Domain cannot be empty.${NC}"
        exit 1
    fi

    # Default nameserver subdomain
    local default_ns="t.${DOMAIN}"
    read -p "$(echo -e "${YELLOW}Enter DNS tunnel zone (default: ${default_ns}): ${NC}")" NAMESERVER
    NAMESERVER=${NAMESERVER:-$default_ns}

    echo -e "${GREEN}Domain:     $DOMAIN${NC}"
    echo -e "${GREEN}Tunnel zone: $NAMESERVER${NC}"

    # Verify DNS delegation
    echo -e "\n${CYAN}Testing DNS delegation...${NC}"
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "unknown")
    echo -e "${CYAN}Your server IP: $server_ip${NC}"

    local ns_result
    ns_result=$(dig +short NS "$NAMESERVER" 2>/dev/null)
    local a_result
    a_result=$(dig +short A "tns.${DOMAIN}" 2>/dev/null)

    if [[ -n "$ns_result" ]]; then
        echo -e "${GREEN}NS record found: $ns_result${NC}"
    else
        echo -e "${YELLOW}WARNING: NS record for '$NAMESERVER' not found yet.${NC}"
        echo -e "${YELLOW}Make sure you configure these DNS records:${NC}"
        echo -e "${WHITE}  A  record: tns.${DOMAIN} -> ${server_ip}${NC}"
        echo -e "${WHITE}  NS record: ${NAMESERVER} -> tns.${DOMAIN}${NC}"
    fi

    if [[ -n "$a_result" ]]; then
        echo -e "${GREEN}A record found: tns.${DOMAIN} -> $a_result${NC}"
        if [[ "$a_result" == "$server_ip" ]]; then
            echo -e "${GREEN}A record correctly points to this server!${NC}"
        else
            echo -e "${YELLOW}WARNING: A record points to $a_result, but this server is $server_ip${NC}"
        fi
    else
        echo -e "${YELLOW}WARNING: A record for 'tns.${DOMAIN}' not found yet.${NC}"
    fi

    read -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
    progress_bar 1
}

configure_iptables() {
    echo -e "\n${YELLOW}[7/8] Configuring Firewall (iptables)...${NC}"

    # Flush old DNS-related NAT rules
    iptables -t nat -F 2>/dev/null

    # Allow DNSTT port
    iptables -I INPUT -p udp --dport $DNSTT_PORT -j ACCEPT
    iptables -I INPUT -p tcp --dport $DNSTT_PORT -j ACCEPT

    # Allow SSH
    iptables -I INPUT -p tcp --dport $SSH_PORT -j ACCEPT

    # Redirect incoming DNS (port 53) to DNSTT server (port 5300)
    iptables -t nat -A PREROUTING -i "$(ip route show default | awk '{print $5}' | head -1)" -p udp --dport 53 -j REDIRECT --to-ports $DNSTT_PORT
    iptables -t nat -A PREROUTING -i "$(ip route show default | awk '{print $5}' | head -1)" -p tcp --dport 53 -j REDIRECT --to-ports $DNSTT_PORT

    # IPv6 if available
    ip6tables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports $DNSTT_PORT 2>/dev/null
    ip6tables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports $DNSTT_PORT 2>/dev/null

    # Save rules persistently
    netfilter-persistent save > /dev/null 2>&1 || {
        iptables-save > /etc/iptables/rules.v4 2>/dev/null
        ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
    }

    progress_bar 1
    echo -e "${GREEN}Firewall configured: port 53 -> $DNSTT_PORT (DNSTT)${NC}"
}

setup_dnstt_service() {
    echo -e "\n${YELLOW}[8/8] Creating DNSTT Service & Starting...${NC}"

    # Save configuration
    save_config

    # Create the systemd service for dnstt-server
    # Correct syntax: dnstt-server -udp :PORT -privkey-file KEYFILE DOMAIN UPSTREAM
    # DNSTT tunnels DNS traffic to SSH on 127.0.0.1:22
    #
    # Note: -mtu flag is only available in some dnstt forks.
    # We test if the binary supports it before adding it.

    local EXEC_CMD="$DNSTT_BIN -udp :$DNSTT_PORT -privkey-file $PRIVKEY_FILE $NAMESERVER 127.0.0.1:$SSH_PORT"

    # Check if this dnstt-server binary supports -mtu flag
    if "$DNSTT_BIN" -help 2>&1 | grep -qi '\-mtu'; then
        EXEC_CMD="$DNSTT_BIN -udp :$DNSTT_PORT -mtu $MTU_SIZE -privkey-file $PRIVKEY_FILE $NAMESERVER 127.0.0.1:$SSH_PORT"
        echo -e "${GREEN}  Using MTU: $MTU_SIZE${NC}"
    else
        echo -e "${YELLOW}  This dnstt-server build does not support -mtu flag, skipping.${NC}"
    fi

    echo -e "${CYAN}  Service command: $EXEC_CMD${NC}"

    cat > /etc/systemd/system/ai-slowdns-tz.service << EOF
[Unit]
Description=A.I SLOWDNS TZ - DNSTT SSH Tunnel Server
After=network.target sshd.service
Wants=sshd.service

[Service]
Type=simple
ExecStart=$EXEC_CMD
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # Create auto-expiry checker cron script
    cat > "$INSTALL_DIR/scripts/check-expiry.sh" << 'EXPIRY'
#!/bin/bash
# Auto-check and disable expired users
USERS_DB="/opt/ai-slowdns-tz/config/users.db"
LOG="/opt/ai-slowdns-tz/logs/expiry.log"
TODAY=$(date +%s)

while IFS='|' read -r username created expires status; do
    [[ "$username" =~ ^#.*$ ]] && continue
    [[ -z "$username" ]] && continue
    [[ "$expires" == "permanent" ]] && continue

    expiry_epoch=$(date -d "$expires" +%s 2>/dev/null || echo 0)
    if [[ $TODAY -gt $expiry_epoch && $expiry_epoch -gt 0 && "$status" == "active" ]]; then
        # Lock the user account
        usermod -L "$username" 2>/dev/null
        # Kill their sessions
        pkill -u "$username" 2>/dev/null
        # Update status in DB
        sed -i "/^${username}|/c\\${username}|${created}|${expires}|expired" "$USERS_DB"
        echo "[$(date)] User $username expired and locked." >> "$LOG"
    fi
done < "$USERS_DB"
EXPIRY
    chmod +x "$INSTALL_DIR/scripts/check-expiry.sh"

    # Add cron job for expiry check every hour
    (crontab -l 2>/dev/null | grep -v "check-expiry"; echo "0 * * * * $INSTALL_DIR/scripts/check-expiry.sh") | crontab -

    # Enable and start
    systemctl daemon-reload
    systemctl enable ai-slowdns-tz.service > /dev/null 2>&1
    systemctl start ai-slowdns-tz.service

    sleep 3

    # Verify it started
    if systemctl is-active --quiet ai-slowdns-tz.service; then
        echo -e "${GREEN}DNSTT server started successfully!${NC}"
        log_msg "INFO" "DNSTT service started OK"
    else
        echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  DNSTT server failed to start!                   ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Service status:${NC}"
        systemctl status ai-slowdns-tz.service --no-pager 2>&1 | head -20
        echo ""
        echo -e "${YELLOW}Recent logs:${NC}"
        journalctl -u ai-slowdns-tz.service --no-pager -n 30
        echo ""
        echo -e "${YELLOW}Debug info:${NC}"
        echo -e "  Binary:    $DNSTT_BIN ($(file "$DNSTT_BIN" 2>/dev/null | head -1))"
        echo -e "  Privkey:   $PRIVKEY_FILE ($(wc -c < "$PRIVKEY_FILE" 2>/dev/null || echo 'missing') bytes)"
        echo -e "  Pubkey:    $PUBKEY_FILE ($(wc -c < "$PUBKEY_FILE" 2>/dev/null || echo 'missing') bytes)"
        echo -e "  Domain:    $NAMESERVER"
        echo -e "  Port:      $DNSTT_PORT"
        echo -e "  SSH Port:  $SSH_PORT"
        echo -e "  Command:   $EXEC_CMD"
        echo ""
        echo -e "${CYAN}Try running manually to see the error:${NC}"
        echo -e "${WHITE}  $EXEC_CMD${NC}"
        log_msg "ERROR" "DNSTT service failed to start"
    fi

    progress_bar 2
}

# ========================================================================
# CONNECTION TEST
# ========================================================================

test_connection() {
    echo -e "\n${CYAN}=== Connection Test ===${NC}"

    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")

    echo -e "${CYAN}Checking services...${NC}"

    # Check DNSTT service
    if systemctl is-active --quiet ai-slowdns-tz.service; then
        echo -e "  ${GREEN}[OK]${NC} DNSTT server is running"
    else
        echo -e "  ${RED}[FAIL]${NC} DNSTT server is NOT running"
        echo -e "  ${YELLOW}Fix: systemctl restart ai-slowdns-tz.service${NC}"
    fi

    # Check SSH
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} SSH server is running"
    else
        echo -e "  ${RED}[FAIL]${NC} SSH server is NOT running"
    fi

    # Check port 5300 is listening
    if ss -ulnp | grep -q ":${DNSTT_PORT} "; then
        echo -e "  ${GREEN}[OK]${NC} DNSTT listening on UDP :$DNSTT_PORT"
    else
        echo -e "  ${RED}[FAIL]${NC} DNSTT NOT listening on UDP :$DNSTT_PORT"
    fi

    # Check iptables redirect
    if iptables -t nat -L PREROUTING -n 2>/dev/null | grep -q "redir ports $DNSTT_PORT"; then
        echo -e "  ${GREEN}[OK]${NC} iptables: port 53 -> $DNSTT_PORT redirect active"
    else
        echo -e "  ${YELLOW}[WARN]${NC} iptables redirect may not be configured"
    fi

    # Check DNS resolution via this server
    echo -e "\n${CYAN}Testing DNS tunnel path...${NC}"
    if command -v dig &>/dev/null; then
        local dig_result
        dig_result=$(dig +short +timeout=5 @127.0.0.1 -p $DNSTT_PORT test.example.com 2>/dev/null)
        if [[ -n "$dig_result" ]]; then
            echo -e "  ${GREEN}[OK]${NC} DNS queries reach DNSTT server"
        else
            echo -e "  ${YELLOW}[INFO]${NC} DNSTT responds only to tunnel protocol, not raw DNS queries (this is normal)"
        fi
    fi

    # Show config summary
    load_config
    echo -e "\n${WHITE}=== Configuration Summary ===${NC}"
    echo -e "  ${CYAN}Server IP:    ${WHITE}$server_ip${NC}"
    echo -e "  ${CYAN}Domain:       ${WHITE}${DOMAIN:-not set}${NC}"
    echo -e "  ${CYAN}Tunnel Zone:  ${WHITE}${NAMESERVER:-not set}${NC}"
    echo -e "  ${CYAN}MTU Size:     ${WHITE}${MTU_SIZE:-$DEFAULT_MTU}${NC}"
    echo -e "  ${CYAN}DNSTT Port:   ${WHITE}$DNSTT_PORT${NC}"
    echo -e "  ${CYAN}SSH Port:     ${WHITE}$SSH_PORT${NC}"

    if [[ -f "$PUBKEY_FILE" ]]; then
        echo -e "  ${CYAN}Public Key:   ${WHITE}$(cat "$PUBKEY_FILE")${NC}"
    fi

    echo -e "\n${WHITE}=== Client Connection Info ===${NC}"
    echo -e "${YELLOW}For DarkTunnel / HTTP Injector / SlowDNS client:${NC}"
    echo -e "  ${CYAN}DNS Server:    ${WHITE}${server_ip}${NC}"
    echo -e "  ${CYAN}Nameserver:    ${WHITE}${NAMESERVER:-t.yourdomain.com}${NC}"
    echo -e "  ${CYAN}Public Key:    ${WHITE}$(cat "$PUBKEY_FILE" 2>/dev/null || echo 'not generated')${NC}"
    echo -e "  ${CYAN}SSH Host:      ${WHITE}127.0.0.1${NC}"
    echo -e "  ${CYAN}SSH Port:      ${WHITE}$SSH_PORT${NC}"
}

# ========================================================================
# CHANGE MTU (POST-INSTALL)
# ========================================================================

change_mtu() {
    echo -e "\n${CYAN}=== Change MTU Size ===${NC}"
    load_config
    echo -e "${CYAN}Current MTU: ${WHITE}${MTU_SIZE:-$DEFAULT_MTU}${NC}"
    select_mtu
    save_config

    # Update the systemd service with new MTU
    if [[ -f /etc/systemd/system/ai-slowdns-tz.service ]]; then
        sed -i "s/-mtu [0-9]*/-mtu $MTU_SIZE/" /etc/systemd/system/ai-slowdns-tz.service
        systemctl daemon-reload
        systemctl restart ai-slowdns-tz.service
        echo -e "${GREEN}DNSTT restarted with MTU $MTU_SIZE${NC}"
    else
        echo -e "${YELLOW}Service not installed yet. MTU will be used during installation.${NC}"
    fi
}

# ========================================================================
# SHOW LOGS
# ========================================================================

show_logs() {
    echo -e "\n${CYAN}=== Recent DNSTT Logs ===${NC}"
    journalctl -u ai-slowdns-tz.service --no-pager -n 50
    echo
    echo -e "${CYAN}=== Expiry Logs ===${NC}"
    tail -20 "$LOG_DIR/expiry.log" 2>/dev/null || echo -e "${YELLOW}No expiry logs yet.${NC}"
}

# ========================================================================
# UNINSTALL
# ========================================================================

uninstall() {
    echo -e "\n${RED}=== Uninstall A.I SLOWDNS TZ ===${NC}"
    read -p "$(echo -e "${RED}This will remove all SLOWDNS services and config. Continue? (y/n): ${NC}")" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        return
    fi

    # Stop and disable services
    systemctl stop ai-slowdns-tz.service 2>/dev/null
    systemctl disable ai-slowdns-tz.service 2>/dev/null
    rm -f /etc/systemd/system/ai-slowdns-tz.service
    systemctl daemon-reload

    # Remove iptables rules
    iptables -t nat -F 2>/dev/null
    netfilter-persistent save 2>/dev/null

    # Remove SSH drop-in config
    rm -f /etc/ssh/sshd_config.d/99-slowdns.conf

    # Remove cron
    (crontab -l 2>/dev/null | grep -v "check-expiry") | crontab -

    # Remove install dir
    rm -rf "$INSTALL_DIR"

    echo -e "${GREEN}Uninstalled successfully.${NC}"
}

# ========================================================================
# FULL INSTALLATION FLOW
# ========================================================================

full_install() {
    print_header
    check_root

    echo -e "${CYAN}[$(date +%T)] Starting A.I SLOWDNS TZ Installation...${NC}"

    # Pre-create directories
    mkdir -p "$INSTALL_DIR"/{cache,logs,scripts,config}

    # Step 1: Dependencies
    install_dependencies

    # Step 2: SSH config
    configure_ssh

    # Step 3: Network
    configure_network

    # Step 4: Build/download DNSTT
    build_dnstt

    # Step 5: Generate keys
    generate_keys

    # Step 6: Domain & MTU
    configure_domain
    select_mtu

    # Step 7: Firewall
    configure_iptables

    # Step 8: Service & start
    setup_dnstt_service

    # Initialize user DB
    init_users_db

    # Done
    echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║       A.I SLOWDNS TZ v3.0 - Installation Complete!           ║${NC}"
    echo -e "${GREEN}║         SlowDNS + DNSTT SSH Tunnel Active                    ║${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"

    # Show connection info
    test_connection

    echo -e "\n${YELLOW}Next steps:${NC}"
    echo -e "${CYAN}  1. Create users with the User Management menu${NC}"
    echo -e "${CYAN}  2. Give clients: public key, nameserver, and SSH credentials${NC}"
    echo -e "${CYAN}  3. Run this script again for the management menu${NC}"
    echo -e "\n${GREEN}Run: bash $0 for management menu${NC}"
}

# ========================================================================
# MAIN MENU
# ========================================================================

main_menu() {
    check_root
    init_users_db

    while true; do
        print_header
        echo -e "${WHITE}  Server Status: $(systemctl is-active ai-slowdns-tz.service 2>/dev/null || echo 'not installed')${NC}"
        echo
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║         MAIN MENU                    ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        echo -e "  ${CYAN}1)${NC} Fresh Install / Reinstall"
        echo -e "  ${CYAN}2)${NC} User Management"
        echo -e "  ${CYAN}3)${NC} Change MTU Size"
        echo -e "  ${CYAN}4)${NC} Show Connection Info & Test"
        echo -e "  ${CYAN}5)${NC} View Logs"
        echo -e "  ${CYAN}6)${NC} Restart DNSTT Service"
        echo -e "  ${CYAN}7)${NC} Show Public Key"
        echo -e "  ${CYAN}8)${NC} Uninstall"
        echo -e "  ${CYAN}0)${NC} Exit"
        echo
        read -p "$(echo -e "${YELLOW}Select [0-8]: ${NC}")" main_choice

        case $main_choice in
            1)
                full_install
                read -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
                ;;
            2) user_management_menu ;;
            3) change_mtu ;;
            4) test_connection
               read -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
               ;;
            5) show_logs
               read -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
               ;;
            6)
                systemctl restart ai-slowdns-tz.service
                sleep 2
                if systemctl is-active --quiet ai-slowdns-tz.service; then
                    echo -e "${GREEN}DNSTT service restarted successfully.${NC}"
                else
                    echo -e "${RED}Failed to restart. Check: journalctl -u ai-slowdns-tz.service${NC}"
                fi
                read -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
                ;;
            7)
                if [[ -f "$PUBKEY_FILE" ]]; then
                    echo -e "\n${GREEN}Public Key:${NC}"
                    echo -e "${WHITE}$(cat "$PUBKEY_FILE")${NC}"
                else
                    echo -e "${RED}Public key not found. Run install first.${NC}"
                fi
                read -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
                ;;
            8) uninstall
               read -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
               ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option.${NC}"
                sleep 1
                ;;
        esac
    done
}

# ========================================================================
# ENTRY POINT
# ========================================================================

# If service is already installed, show management menu
# Otherwise, ask what to do
if [[ -f /etc/systemd/system/ai-slowdns-tz.service ]]; then
    main_menu
else
    print_header
    echo -e "${YELLOW}A.I SLOWDNS TZ is not installed yet.${NC}"
    echo -e "  ${CYAN}1)${NC} Install Now"
    echo -e "  ${CYAN}2)${NC} Exit"
    read -p "$(echo -e "${YELLOW}Select [1-2]: ${NC}")" init_choice
    case $init_choice in
        1) full_install
           echo
           read -p "$(echo -e "${CYAN}Press Enter for management menu...${NC}")"
           main_menu
           ;;
        *) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
    esac
fi
