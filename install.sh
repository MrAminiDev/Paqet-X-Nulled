#!/bin/bash
#=================================================
# Paqet-X Client Manager v1.0
#=================================================

# Colors
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m' BLUE='\033[0;34m' MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m' NC='\033[0m'

# Config
readonly SCRIPT_VERSION="1.0"
readonly BIN_DIR="/usr/local/bin"
readonly BIN_NAME="Paqet-X"
readonly INSTALL_DIR="/opt/paqet-x"
readonly CONFIG_DIR="/etc/paqet-x"
readonly SERVICE_DIR="/etc/systemd/system"
readonly DOWNLOAD_URL=""
readonly DEFAULT_LISTEN_PORT="8888"
readonly DEFAULT_KCP_MODE="fast"
readonly DEFAULT_ENCRYPTION="aes-128-gcm"
readonly DEFAULT_CONNECTIONS="6"
readonly DEFAULT_MTU="1150"
readonly DEFAULT_SOCKS5_PORT="1080"
readonly DEFAULT_V2RAY_PORTS="443,8443"

# KCP modes
declare -A KCP_MODES=(
    ["0"]="normal:Conservative / Reliable / Higher latency"
    ["1"]="fast:Balanced speed / Recommended"
    ["2"]="fast2:Aggressive / Lower latency"
    ["3"]="fast3:Most aggressive / Lowest latency"
)

# Encryption options
declare -A ENCRYPTION_OPTIONS=(
    ["1"]="aes-128-gcm:Best balance of speed and security"
    ["2"]="aes-128:Good security / Moderate speed"
    ["3"]="aes:Standard AES / Good security"
    ["4"]="salsa20:Fast stream cipher"
    ["5"]="aes-256:Maximum security / Slower"
    ["6"]="none:No encryption / Max speed"
    ["7"]="null:No encryption / Max speed"
)

# ═══════════════════════════════════════
#  Utility Functions
# ═══════════════════════════════════════
print_step()    { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error()   { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info()    { echo -e "${CYAN}[i]${NC} $1"; }

pause() { echo ""; read -p "${1:-Press Enter to continue...}" </dev/tty; }

check_root() { [[ $EUID -ne 0 ]] && { print_error "Run as root"; exit 1; }; }

show_banner() {
    clear
    echo -e "${MAGENTA}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║   ██████╗  █████╗  ██████╗ ███████╗████████╗ ██╗  ██╗       ║"
    echo "║   ██╔══██╗██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝ ╚██╗██╔╝       ║"
    echo "║   ██████╔╝███████║██║   ██║█████╗     ██║     ╚███╔╝        ║"
    echo "║   ██╔═══╝ ██╔══██║██║▄▄ ██║██╔══╝     ██║     ██╔██╗        ║"
    echo "║   ██║     ██║  ██║╚██████╔╝███████╗   ██║    ██╔╝ ██╗       ║"
    echo "║   ╚═╝     ╚═╝  ╚═╝ ╚══▀▀═╝ ╚══════╝   ╚═╝    ╚═╝  ╚═╝       ║"
    echo "║                                                              ║"
    echo "║              PAQET-X Manager v${SCRIPT_VERSION}                            ║"
    echo "║                            Nulled                            ║"
    echo "║   GitHub  : https://github.com/MrAminiDev/Paqet-X-Nulled/                     ║"
    echo "║   Telegram: t.me/AminiDev                                    ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

detect_os() {
    if [ -f /etc/os-release ]; then . /etc/os-release; echo "$ID"
    else echo "$(uname -s | tr '[:upper:]' '[:lower:]')"; fi
}

detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64|x86-64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "armv7" ;;
        *) print_error "Unsupported: $arch"; return 1 ;;
    esac
}

get_public_ip() {
    for svc in ifconfig.me icanhazip.com api.ipify.org; do
        local ip=$(curl -4 -s --max-time 2 "$svc" 2>/dev/null)
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { echo "$ip"; return; }
    done
    echo "N/A"
}

get_network_info() {
    NETWORK_INTERFACE=""
    LOCAL_IP=""
    GATEWAY_IP=""
    GATEWAY_MAC=""

    if command -v ip &>/dev/null; then
        NETWORK_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
        LOCAL_IP=$(ip -4 addr show "$NETWORK_INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -1)

        if [ -n "$GATEWAY_IP" ]; then
            ping -c 1 -W 1 "$GATEWAY_IP" >/dev/null 2>&1 || true
            GATEWAY_MAC=$(ip neigh show "$GATEWAY_IP" 2>/dev/null | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -1)

            if [ -z "$GATEWAY_MAC" ] && command -v arp &>/dev/null; then
                GATEWAY_MAC=$(arp -n "$GATEWAY_IP" 2>/dev/null | awk "/^$GATEWAY_IP/ {print \$3}" | head -1)
            fi
        fi
    fi

    NETWORK_INTERFACE="${NETWORK_INTERFACE:-eth0}"
}

validate_ip() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
validate_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

clean_config_name() {
    echo "$1" | tr -cd '[:alnum:]-_' | tr '[:upper:]' '[:lower:]'
}

clean_port_list() {
    echo "$1" | tr ',' '\n' | while read -r p; do
        p=$(echo "$p" | tr -d '[:space:]')
        validate_port "$p" && echo "$p"
    done | paste -sd ',' -
}

generate_secret_key() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 24 | head -n 1
}

# ═══════════════════════════════════════
#  Iptables
# ═══════════════════════════════════════
save_iptables() {
    command -v netfilter-persistent &>/dev/null && netfilter-persistent save >/dev/null 2>&1
    command -v iptables-save &>/dev/null && [ -d "/etc/iptables" ] && iptables-save > /etc/iptables/rules.v4 2>/dev/null
}

configure_iptables() {
    local port="$1" proto="${2:-tcp}"
    if [ "$proto" = "both" ]; then
        configure_iptables "$port" "tcp"
        configure_iptables "$port" "udp"
        return
    fi
    iptables -t raw -C PREROUTING -p "$proto" --dport "$port" -j NOTRACK >/dev/null 2>&1 || \
        iptables -t raw -A PREROUTING -p "$proto" --dport "$port" -j NOTRACK >/dev/null 2>&1
    iptables -t raw -C OUTPUT -p "$proto" --sport "$port" -j NOTRACK >/dev/null 2>&1 || \
        iptables -t raw -A OUTPUT -p "$proto" --sport "$port" -j NOTRACK >/dev/null 2>&1
    iptables -t mangle -C OUTPUT -p tcp --sport "$port" --tcp-flags RST RST -j DROP >/dev/null 2>&1 || \
        iptables -t mangle -A OUTPUT -p tcp --sport "$port" --tcp-flags RST RST -j DROP >/dev/null 2>&1
    save_iptables
}

install_iptables_persistent() {
    local os=$(detect_os)
    case $os in
        ubuntu|debian)
            if ! dpkg -l | grep -q "iptables-persistent"; then
                export DEBIAN_FRONTEND=noninteractive
                apt-get update -qq >/dev/null 2>&1
                apt-get install -y iptables-persistent >/dev/null 2>&1
            fi ;;
        centos|rhel|fedora|rocky|almalinux)
            rpm -q iptables-services >/dev/null 2>&1 || {
                yum install -y iptables-services >/dev/null 2>&1 || dnf install -y iptables-services >/dev/null 2>&1
                systemctl enable iptables >/dev/null 2>&1
            } ;;
    esac
    save_iptables
}

# ═══════════════════════════════════════
#  Systemd Service
# ═══════════════════════════════════════
create_systemd_service() {
    local name="$1"
    cat > "$SERVICE_DIR/paqet-x-${name}.service" <<EOF
[Unit]
Description=Paqet-X Tunnel (${name})
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/$BIN_NAME run -c $CONFIG_DIR/${name}.yaml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

# ═══════════════════════════════════════
#  Install Dependencies
# ═══════════════════════════════════════
install_dependencies() {
    show_banner
    print_step "Installing dependencies...\n"
    local os=$(detect_os)
    case $os in
        ubuntu|debian)
            apt update -qq >/dev/null 2>&1 || true
            apt install -y curl wget libpcap-dev iptables lsof iproute2 cron dnsutils >/dev/null 2>&1
            install_iptables_persistent ;;
        centos|rhel|fedora|rocky|almalinux)
            yum install -y curl wget libpcap-devel iptables lsof iproute cronie bind-utils >/dev/null 2>&1
            install_iptables_persistent ;;
        *) print_warning "Unknown OS. Install manually: libpcap iptables curl cron dnsutils" ;;
    esac
    print_success "Dependencies installed"
    pause
}

# ═══════════════════════════════════════
#  Install Paqet-X Core
# ═══════════════════════════════════════
install_paqet() {
    show_banner
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Install / Update Paqet-X Core                                ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

    local arch=$(detect_arch) || return 1
    local current="Not installed"
    [ -f "$BIN_DIR/$BIN_NAME" ] && current=$("$BIN_DIR/$BIN_NAME" version 2>/dev/null | head -1)

    echo -e " Arch:      ${CYAN}$arch${NC}"
    echo -e " Installed: ${CYAN}$current${NC}\n"

    local download_url="$DOWNLOAD_URL"
    print_info "Downloading from $download_url ..."

    mkdir -p "$INSTALL_DIR"
    if ! curl -fsSL "$download_url" -o "/tmp/paqet.tar.gz" 2>/dev/null; then
        print_error "Download failed"; pause; return 1
    fi

    print_success "Downloaded"
    rm -rf "$INSTALL_DIR"/*
    tar -xzf "/tmp/paqet.tar.gz" -C "$INSTALL_DIR" 2>/dev/null || { print_error "Extract failed"; pause; return 1; }

    local binary=""
    for pattern in "Paqet-X" "paqet-x" "paqet" "Paqet"; do
        binary=$(find "$INSTALL_DIR" -type f -iname "*${pattern}*" 2>/dev/null | head -1)
        [ -n "$binary" ] && break
    done
    [ -z "$binary" ] && binary=$(find "$INSTALL_DIR" -type f -executable 2>/dev/null | head -1)

    if [ -n "$binary" ]; then
        cp "$binary" "$BIN_DIR/$BIN_NAME" && chmod +x "$BIN_DIR/$BIN_NAME"
        print_success "Installed to $BIN_DIR/$BIN_NAME"
    else
        print_error "Binary not found in archive"
        ls -la "$INSTALL_DIR"
    fi
    rm -f "/tmp/paqet.tar.gz"
    pause
}

# ═══════════════════════════════════════
#  Configure Server (Kharej)
# ═══════════════════════════════════════
configure_server() {
    while true; do
        show_banner
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║ Configure as Server (Kharej)                                 ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

        get_network_info
        local public_ip=$(get_public_ip)

        echo -e "${YELLOW}Detected Network Information${NC}"
        echo -e "┌──────────────────────────────────────────────────────────────┐"
        printf "│ %-12s : %-44s │\n" "Interface" "${NETWORK_INTERFACE:-Not found}"
        printf "│ %-12s : %-44s │\n" "Local IP" "${LOCAL_IP:-Not found}"
        printf "│ %-12s : %-44s │\n" "Public IP" "$public_ip"
        printf "│ %-12s : %-44s │\n" "Gateway MAC" "${GATEWAY_MAC:-Not found}"
        echo -e "└──────────────────────────────────────────────────────────────┘\n"

        echo -e "${CYAN}Server Configuration${NC}"
        echo -e "────────────────────────────────────────────────────────────────"

        # [1/7] Service Name
        echo -en "${YELLOW}[1/7] Service Name (e.g: myserver) : ${NC}"
        read -r config_name
        config_name=$(clean_config_name "${config_name:-server}")
        echo -e "[1/7] Service Name : ${CYAN}$config_name${NC}"

        if [ -f "$CONFIG_DIR/${config_name}.yaml" ]; then
            print_warning "Config '$config_name' already exists!"
            read -p "Overwrite? (y/N): " ow
            [[ ! "$ow" =~ ^[Yy]$ ]] && continue
        fi

        # [2/7] Listen Port
        echo -en "${YELLOW}[2/7] Listen Port (default: $DEFAULT_LISTEN_PORT) : ${NC}"
        read -r port
        port="${port:-$DEFAULT_LISTEN_PORT}"
        validate_port "$port" || { print_error "Invalid port"; sleep 1.5; continue; }
        echo -e "[2/7] Listen Port : ${CYAN}$port${NC}"

        # [3/7] Secret Key
        local secret_key=$(generate_secret_key)
        echo -e "${YELLOW}[3/7] Secret Key : ${GREEN}$secret_key${NC} (press Enter for auto-generate)"
        read -p "Custom key? (Enter=use above): " custom_key
        if [ -n "$custom_key" ]; then
            [ ${#custom_key} -lt 8 ] && { print_error "Min 8 chars"; continue; }
            secret_key="$custom_key"
        fi
        echo -e "[3/7] Secret Key : ${GREEN}$secret_key${NC}"

        # [4/7] KCP Mode
        echo -e "\n${CYAN}KCP Mode Selection${NC}"
        echo -e "────────────────────────────────────────────────────────────────"
        for k in 0 1 2 3; do
            IFS=':' read -r name desc <<< "${KCP_MODES[$k]}"
            echo " [$k] $name - $desc"
        done
        echo ""
        read -p "[4/7] Choose KCP mode [0-3] (default 1): " mode_choice
        mode_choice="${mode_choice:-1}"
        local mode_name
        case $mode_choice in
            0) mode_name="normal" ;; 1) mode_name="fast" ;;
            2) mode_name="fast2" ;; 3) mode_name="fast3" ;; *) mode_name="fast" ;;
        esac
        echo -e "[4/7] KCP Mode : ${CYAN}$mode_name${NC}"

        # [5/7] Connections
        echo -en "${YELLOW}[5/7] Connections [1-32] (default $DEFAULT_CONNECTIONS): ${NC}"
        read -r conn; conn="${conn:-$DEFAULT_CONNECTIONS}"
        echo -e "[5/7] Connections : ${CYAN}$conn${NC}"

        # [6/7] MTU
        echo -en "${YELLOW}[6/7] MTU (default $DEFAULT_MTU): ${NC}"
        read -r mtu; mtu="${mtu:-$DEFAULT_MTU}"
        echo -e "[6/7] MTU : ${CYAN}$mtu${NC}"

        # [7/7] Encryption
        echo -e "\n${CYAN}Encryption Selection${NC}"
        echo -e "────────────────────────────────────────────────────────────────"
        for k in 1 2 3 4 5 6 7; do
            IFS=':' read -r enc_name enc_desc <<< "${ENCRYPTION_OPTIONS[$k]}"
            echo " [$k] $enc_name - $enc_desc"
        done
        echo ""
        read -p "[7/7] Choose encryption [1-7] (default 1): " enc_choice
        enc_choice="${enc_choice:-1}"
        local block
        IFS=':' read -r block _ <<< "${ENCRYPTION_OPTIONS[$enc_choice]}"
        block="${block:-aes-128-gcm}"
        echo -e "[7/7] Encryption : ${CYAN}$block${NC}"

        # Apply
        echo -e "\n${CYAN}Applying Configuration${NC}"
        echo -e "────────────────────────────────────────────────────────────────"

        [ ! -f "$BIN_DIR/$BIN_NAME" ] && { install_paqet || continue; }

        configure_iptables "$port" "tcp"
        mkdir -p "$CONFIG_DIR"

        {
            echo "# Paqet-X Server Configuration"
            echo "role: \"server\""
            echo "log:"
            echo "  level: \"info\""
            echo "listen:"
            echo "  addr: \":$port\""
            echo "network:"
            echo "  interface: \"$NETWORK_INTERFACE\""
            echo "  ipv4:"
            echo "    addr: \"$LOCAL_IP:$port\""
            echo "    router_mac: \"$GATEWAY_MAC\""
            echo "  tcp:"
            echo "    local_flag: [\"PA\"]"
            # echo "  pcap:"
            # echo "    sockbuf: 8388608"
            echo "transport:"
            echo "  protocol: \"kcp\""
            echo "  conn: $conn"
            echo "  kcp:"
            echo "    key: \"$secret_key\""
            echo "    mode: \"$mode_name\""
            echo "    block: \"$block\""
            echo "    mtu: $mtu"
            # echo "    rcvwnd: 1024"
            # echo "    sndwnd: 1024"
            # echo "    smuxbuf: 4194304"
            # echo "    streambuf: 2097152"
        } > "$CONFIG_DIR/${config_name}.yaml"

        print_success "Config saved: $CONFIG_DIR/${config_name}.yaml"

        create_systemd_service "$config_name"
        local svc="paqet-x-${config_name}"
        systemctl enable "$svc" --now >/dev/null 2>&1

        if systemctl is-active --quiet "$svc"; then
            print_success "Server started successfully"

            echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║ Server Ready                                                  ║${NC}"
            echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

            echo -e "${YELLOW}Server Information${NC}"
            echo -e "┌──────────────────────────────────────────────────────────────┐"
            printf "│ %-14s : %-44s │\n" "Public IP" "$public_ip"
            printf "│ %-14s : %-44s │\n" "Listen Port" "$port"
            printf "│ %-14s : %-44s │\n" "KCP Mode" "$mode_name"
            printf "│ %-14s : %-44s │\n" "Encryption" "$block"
            printf "│ %-14s : %-44s │\n" "Connections" "$conn"
            echo -e "└──────────────────────────────────────────────────────────────┘\n"

            echo -e "${YELLOW}Secret Key (give this to Client)${NC}"
            echo -e "┌──────────────────────────────────────────────────────────────┐"
            printf "│ %-60s │\n" "$secret_key"
            echo -e "└──────────────────────────────────────────────────────────────┘\n"

            echo -e "${GREEN}✅ Server setup completed!${NC}"

            # Auto-enable 1hr restart
            setup_auto_restart "$svc" "$DEFAULT_RESTART_INTERVAL"
        else
            print_error "Service failed to start"
            systemctl status "$svc" --no-pager -l
        fi
        pause
        return 0
    done
}

# ═══════════════════════════════════════
#  Configure Client (Iran)
# ═══════════════════════════════════════
configure_client() {
    while true; do
        show_banner
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║ Configure as Client (Iran)                                   ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

        get_network_info
        local public_ip=$(get_public_ip)

        echo -e "${YELLOW}Detected Network Information${NC}"
        echo -e "┌──────────────────────────────────────────────────────────────┐"
        printf "│ %-12s : %-44s │\n" "Interface" "${NETWORK_INTERFACE:-Not found}"
        printf "│ %-12s : %-44s │\n" "Local IP" "${LOCAL_IP:-Not found}"
        printf "│ %-12s : %-44s │\n" "Public IP" "$public_ip"
        printf "│ %-12s : %-44s │\n" "Gateway MAC" "${GATEWAY_MAC:-Not found}"
        echo -e "└──────────────────────────────────────────────────────────────┘\n"

        echo -e "${CYAN}Client Configuration${NC}"
        echo -e "────────────────────────────────────────────────────────────────"

        # [1/10] Service Name
        echo -en "${YELLOW}[1/10] Service Name (e.g: myclient) : ${NC}"
        read -r config_name
        config_name=$(clean_config_name "${config_name:-client}")
        echo -e "[1/10] Service Name : ${CYAN}$config_name${NC}"

        if [ -f "$CONFIG_DIR/${config_name}.yaml" ]; then
            print_warning "Config already exists!"
            read -p "Overwrite? (y/N): " ow
            [[ ! "$ow" =~ ^[Yy]$ ]] && continue
        fi

        # [2/10] Server IP
        echo -en "${YELLOW}[2/10] Server IP (Kharej e.g: 45.76.123.89) : ${NC}"
        read -r server_ip
        [ -z "$server_ip" ] && { print_error "Server IP required"; continue; }
        validate_ip "$server_ip" || { print_error "Invalid IP"; continue; }
        echo -e "[2/10] Server IP : ${CYAN}$server_ip${NC}"

        # [3/10] Server Port
        echo -en "${YELLOW}[3/10] Server Port (default: $DEFAULT_LISTEN_PORT) : ${NC}"
        read -r server_port
        server_port="${server_port:-$DEFAULT_LISTEN_PORT}"
        validate_port "$server_port" || { print_error "Invalid port"; continue; }
        echo -e "[3/10] Server Port : ${CYAN}$server_port${NC}"

        # [4/10] Secret Key
        echo -en "${YELLOW}[4/10] Secret Key (from server) : ${NC}"
        read -r secret_key
        [ -z "$secret_key" ] && { print_error "Secret key required"; continue; }
        echo -e "[4/10] Secret Key : ${GREEN}$secret_key${NC}"

        # [5/10] KCP Mode
        echo -e "\n${CYAN}KCP Mode Selection${NC}"
        echo -e "────────────────────────────────────────────────────────────────"
        for k in 0 1 2 3; do
            IFS=':' read -r name desc <<< "${KCP_MODES[$k]}"
            echo " [$k] $name - $desc"
        done
        echo ""
        read -p "[5/10] Choose KCP mode [0-3] (default 1): " mode_choice
        mode_choice="${mode_choice:-1}"
        local mode_name
        case $mode_choice in
            0) mode_name="normal" ;; 1) mode_name="fast" ;;
            2) mode_name="fast2" ;; 3) mode_name="fast3" ;; *) mode_name="fast" ;;
        esac
        echo -e "[5/10] KCP Mode : ${CYAN}$mode_name${NC}"

        # [6/10] Connections
        echo -en "${YELLOW}[6/10] Connections [1-32] (default $DEFAULT_CONNECTIONS): ${NC}"
        read -r conn; conn="${conn:-$DEFAULT_CONNECTIONS}"
        echo -e "[6/10] Connections : ${CYAN}$conn${NC}"

        # [7/10] MTU
        echo -en "${YELLOW}[7/10] MTU (default $DEFAULT_MTU): ${NC}"
        read -r mtu; mtu="${mtu:-$DEFAULT_MTU}"
        echo -e "[7/10] MTU : ${CYAN}$mtu${NC}"

        # [8/10] Encryption
        echo -e "\n${CYAN}Encryption Selection${NC}"
        echo -e "────────────────────────────────────────────────────────────────"
        for k in 1 2 3 4 5 6 7; do
            IFS=':' read -r enc_name enc_desc <<< "${ENCRYPTION_OPTIONS[$k]}"
            echo " [$k] $enc_name - $enc_desc"
        done
        echo ""
        read -p "[8/10] Choose encryption [1-7] (default 1): " enc_choice
        enc_choice="${enc_choice:-1}"
        local block
        IFS=':' read -r block _ <<< "${ENCRYPTION_OPTIONS[$enc_choice]}"
        block="${block:-aes-128-gcm}"
        echo -e "[8/10] Encryption : ${CYAN}$block${NC}"

        # [9/10] Traffic Type
        echo -e "\n${CYAN}Traffic Type Selection${NC}"
        echo -e "────────────────────────────────────────────────────────────────"
        echo -e " ${GREEN}[1]${NC} Port Forwarding - Forward specific ports"
        echo -e " ${GREEN}[2]${NC} SOCKS5 Proxy - Create a SOCKS5 proxy"
        echo ""
        read -p "[9/10] Choose traffic type [1-2] (default 1): " traffic_type
        traffic_type="${traffic_type:-1}"

        local forward_entries=()
        local socks5_entries=()
        local display_ports=""

        case $traffic_type in
            1)
                echo -e "\n${CYAN}Port Forwarding Configuration${NC}"
                echo -e "────────────────────────────────────────────────────────────────"
                echo -en "${YELLOW}[10/10] Forward Ports (comma separated) [default $DEFAULT_V2RAY_PORTS]: ${NC}"
                read -r forward_ports
                forward_ports=$(clean_port_list "${forward_ports:-$DEFAULT_V2RAY_PORTS}")
                [ -z "$forward_ports" ] && { print_error "No valid ports"; continue; }

                echo -e "\n${CYAN}Protocol Selection${NC}"
                echo " [1] tcp   [2] udp   [3] tcp+udp"
                echo ""

                IFS=',' read -ra PORTS <<< "$forward_ports"
                for p in "${PORTS[@]}"; do
                    p=$(echo "$p" | tr -d '[:space:]')
                    echo -en "${YELLOW}Port $p → protocol [1-3] (default 1): ${NC}"
                    read -r proto_choice
                    proto_choice="${proto_choice:-1}"
                    case $proto_choice in
                        1) forward_entries+=("  - listen: \"0.0.0.0:$p\"\n    target: \"127.0.0.1:$p\"\n    protocol: \"tcp\"")
                           display_ports+=" $p(TCP)" ;;
                        2) forward_entries+=("  - listen: \"0.0.0.0:$p\"\n    target: \"127.0.0.1:$p\"\n    protocol: \"udp\"")
                           display_ports+=" $p(UDP)" ;;
                        3) forward_entries+=("  - listen: \"0.0.0.0:$p\"\n    target: \"127.0.0.1:$p\"\n    protocol: \"tcp\"")
                           forward_entries+=("  - listen: \"0.0.0.0:$p\"\n    target: \"127.0.0.1:$p\"\n    protocol: \"udp\"")
                           display_ports+=" $p(TCP+UDP)" ;;
                        *) forward_entries+=("  - listen: \"0.0.0.0:$p\"\n    target: \"127.0.0.1:$p\"\n    protocol: \"tcp\"")
                           display_ports+=" $p(TCP)" ;;
                    esac
                done
                ;;
            2)
                echo -e "\n${CYAN}SOCKS5 Proxy Configuration${NC}"
                echo -e "────────────────────────────────────────────────────────────────"
                echo -en "${YELLOW}[10/10] SOCKS5 Port (default $DEFAULT_SOCKS5_PORT): ${NC}"
                read -r socks_port
                socks_port="${socks_port:-$DEFAULT_SOCKS5_PORT}"

                echo -en "${YELLOW}SOCKS5 Username (Enter=none): ${NC}"
                read -r socks_user
                if [ -n "$socks_user" ]; then
                    echo -en "${YELLOW}SOCKS5 Password: ${NC}"
                    read -r socks_pass
                    socks5_entries+=("  - listen: \"127.0.0.1:$socks_port\"\n    username: \"$socks_user\"\n    password: \"$socks_pass\"")
                else
                    socks5_entries+=("  - listen: \"127.0.0.1:$socks_port\"")
                fi
                display_ports="SOCKS5:$socks_port"
                ;;
        esac

        # Apply
        echo -e "\n${CYAN}Applying Configuration${NC}"
        echo -e "────────────────────────────────────────────────────────────────"

        [ ! -f "$BIN_DIR/$BIN_NAME" ] && { install_paqet || continue; }
        mkdir -p "$CONFIG_DIR"

        {
            echo "# Paqet-X Client Configuration"
            echo "role: \"client\""
            echo "log:"
            echo "  level: \"info\""

            if [ ${#forward_entries[@]} -gt 0 ]; then
                echo "forward:"
                for entry in "${forward_entries[@]}"; do echo -e "$entry"; done
            fi
            if [ ${#socks5_entries[@]} -gt 0 ]; then
                echo "socks5:"
                for entry in "${socks5_entries[@]}"; do echo -e "$entry"; done
            fi

            echo "network:"
            echo "  interface: \"$NETWORK_INTERFACE\""
            echo "  ipv4:"
            echo "    addr: \"$LOCAL_IP:0\""
            echo "    router_mac: \"$GATEWAY_MAC\""
            echo "  tcp:"
            echo "    local_flag: [\"PA\"]"
            echo "    remote_flag: [\"PA\"]"
            # echo "  pcap:"
            # echo "    sockbuf: 4194304"
            echo "server:"
            echo "  addr: \"$server_ip:$server_port\""
            echo "transport:"
            echo "  protocol: \"kcp\""
            echo "  conn: $conn"
            echo "  kcp:"
            echo "    key: \"$secret_key\""
            echo "    mode: \"$mode_name\""
            echo "    block: \"$block\""
            echo "    mtu: $mtu"
            # echo "    rcvwnd: 1024"
            # echo "    sndwnd: 1024"
            # echo "    smuxbuf: 4194304"
            # echo "    streambuf: 2097152"
        } > "$CONFIG_DIR/${config_name}.yaml"

        print_success "Config saved: $CONFIG_DIR/${config_name}.yaml"

        create_systemd_service "$config_name"
        local svc="paqet-x-${config_name}"
        systemctl enable "$svc" --now >/dev/null 2>&1

        if systemctl is-active --quiet "$svc"; then
            print_success "Client started successfully"

            echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║ Client Ready                                                   ║${NC}"
            echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

            echo -e "${YELLOW}Client Information${NC}"
            echo -e "┌──────────────────────────────────────────────────────────────┐"
            printf "│ %-16s : %-42s │\n" "This Server" "$public_ip"
            printf "│ %-16s : %-42s │\n" "Remote Server" "$server_ip:$server_port"
            printf "│ %-16s : %-42s │\n" "Traffic" "${display_ports# }"
            printf "│ %-16s : %-42s │\n" "KCP Mode" "$mode_name"
            printf "│ %-16s : %-42s │\n" "Encryption" "$block"
            printf "│ %-16s : %-42s │\n" "Connections" "$conn"
            echo -e "└──────────────────────────────────────────────────────────────┘\n"

            echo -e "${GREEN}✅ Client setup completed!${NC}"

            # Auto-enable 1hr restart
            setup_auto_restart "$svc" "$DEFAULT_RESTART_INTERVAL"
        else
            print_error "Client failed to start"
            systemctl status "$svc" --no-pager -l
        fi
        pause
        return 0
    done
}

# ═══════════════════════════════════════
#  Auto-Restart (Cronjob)
# ═══════════════════════════════════════
readonly DEFAULT_RESTART_INTERVAL=60

setup_auto_restart() {
    local service_name="$1"
    local interval="${2:-$DEFAULT_RESTART_INTERVAL}"

    # Remove existing cronjob for this service
    remove_auto_restart "$service_name" 2>/dev/null

    # Add new cronjob
    local cron_cmd="systemctl restart $service_name"
    (crontab -l 2>/dev/null; echo "*/$interval * * * * $cron_cmd") | crontab - 2>/dev/null
    print_success "Auto-restart enabled: every $interval minutes"
}

remove_auto_restart() {
    local service_name="$1"
    crontab -l 2>/dev/null | grep -v "systemctl restart $service_name" | crontab - 2>/dev/null
}

manage_auto_restart() {
    local service_name="$1"
    local display_name="$2"

    show_banner
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ⏰ Auto-Restart Management                                       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

    local svc_name="${service_name%.service}"
    local has_cron="No"
    local current_interval="-"
    local cron_line
    cron_line=$(crontab -l 2>/dev/null | grep "systemctl restart $svc_name")
    if [ -n "$cron_line" ]; then
        has_cron="Yes"
        current_interval=$(echo "$cron_line" | grep -oP '\*/\K[0-9]+' || echo "-")
    fi

    echo -e "${CYAN}Service:${NC} $display_name"
    echo -e "${CYAN}Auto-Restart:${NC} $has_cron"
    [ "$has_cron" = "Yes" ] && echo -e "${CYAN}Interval:${NC} Every ${current_interval} minutes"

    echo -e "\n${CYAN}Options${NC}"
    echo " 1. ✅ Enable Auto-Restart"
    echo " 2. ❌ Disable Auto-Restart"
    echo " 0. ↩️  Back"
    echo ""
    read -p "Choose [0-2]: " choice

    case $choice in
        0) return ;;
        1)
            echo -e "\n${CYAN}Restart Intervals${NC}"
            echo -e "────────────────────────────────────────────────────────────────"
            echo " [1] 30 minutes"
            echo " [2] 1 hour (default)"
            echo " [3] 2 hours"
            echo " [4] 4 hours"
            echo " [5] 6 hours"
            echo " [6] 12 hours"
            echo " [7] Custom interval"
            echo ""
            read -p "Choose [1-7] (default 2): " int_choice
            int_choice="${int_choice:-2}"

            local mins=60
            case $int_choice in
                1) mins=30 ;;
                2) mins=60 ;;
                3) mins=120 ;;
                4) mins=240 ;;
                5) mins=360 ;;
                6) mins=720 ;;
                7) echo -en "${YELLOW}Enter interval in minutes: ${NC}"
                   read -r mins
                   [[ ! "$mins" =~ ^[0-9]+$ ]] || [ "$mins" -lt 1 ] && { print_error "Invalid"; pause; return; }
                   ;;
                *) mins=60 ;;
            esac
            setup_auto_restart "$svc_name" "$mins"
            ;;
        2)
            remove_auto_restart "$svc_name"
            print_success "Auto-restart disabled"
            ;;
    esac
    pause
}

# ═══════════════════════════════════════
#  Service Management
# ═══════════════════════════════════════
get_service_details() {
    local service_name="$1"
    local config_name="${service_name#paqet-x-}"
    local config_file="$CONFIG_DIR/$config_name.yaml"

    local type="unknown" mode="fast" mtu="-" conn="-" cron="No"

    if [ -f "$config_file" ]; then
        local role_line=$(grep "^role:" "$config_file" 2>/dev/null | head -1)
        [ -n "$role_line" ] && type=$(echo "$role_line" | awk '{print $2}' | tr -d '"')
        local mode_line=$(grep "mode:" "$config_file" 2>/dev/null | head -1)
        [ -n "$mode_line" ] && mode=$(echo "$mode_line" | awk '{print $2}' | tr -d '"')
        grep -q "mtu:" "$config_file" 2>/dev/null && mtu=$(grep "mtu:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"')
        grep -q "conn:" "$config_file" 2>/dev/null && conn=$(grep "conn:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"')
    fi

    crontab -l 2>/dev/null | grep -q "systemctl restart $service_name" && cron="Yes"
    echo "$type $mode $mtu $conn $cron"
}

manage_services() {
    while true; do
        show_banner
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  Paqet-X Service Management                                                                       ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}\n"

        local services=()
        mapfile -t services < <(systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null |
                              grep -E '^paqet-x-.*\.service' | awk '{print $1}' || true)

        if [ ${#services[@]} -eq 0 ]; then
            echo -e "${YELLOW}No Paqet-X services found.${NC}\n"
            pause
            return
        fi

        echo -e "${CYAN}┌─────┬──────────────────────────┬─────────────┬───────────┬────────────┬──────────┬────────┬────────────────┐${NC}"
        echo -e "${CYAN}│  #  │ Service Name             │ Status      │ Type      │ Mode       │ MTU      │ Conn   │ Auto-Restart   │${NC}"
        echo -e "${CYAN}├─────┼──────────────────────────┼─────────────┼───────────┼────────────┼──────────┼────────┼────────────────┤${NC}"

        local i=1
        for svc in "${services[@]}"; do
            local service_name="${svc%.service}"
            local display_name="${service_name#paqet-}"
            local status
            status=$(systemctl is-active "$svc" 2>/dev/null) || true
            status="${status:-unknown}"
            status=$(echo "$status" | head -1 | awk '{print $1}')
            local details=$(get_service_details "$service_name")
            local type=$(echo "$details" | awk '{print $1}')
            local mode=$(echo "$details" | awk '{print $2}')
            local mtu=$(echo "$details" | awk '{print $3}')
            local conn=$(echo "$details" | awk '{print $4}')
            local cron=$(echo "$details" | awk '{print $5}')

            local status_color=""
            case "$status" in
                active) status_color="${GREEN}" ;;
                failed) status_color="${RED}" ;;
                inactive) status_color="${YELLOW}" ;;
                activating) status_color="${YELLOW}"; status="restarting" ;;
                deactivating) status_color="${YELLOW}"; status="stopping" ;;
                *) status_color="${WHITE}" ;;
            esac

            local mode_color=""
            case "$mode" in
                normal) mode_color="${CYAN}" ;;
                fast) mode_color="${GREEN}" ;;
                fast2) mode_color="${YELLOW}" ;;
                fast3) mode_color="${RED}" ;;
                *) mode_color="${WHITE}" ;;
            esac

            printf "${CYAN}│${NC} %3d ${CYAN}│${NC} %-24s ${CYAN}│${NC} ${status_color}%-11s${NC} ${CYAN}│${NC} %-9s ${CYAN}│${NC} ${mode_color}%-10s${NC} ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-6s ${CYAN}│${NC} %-14s ${CYAN}│${NC}\n" \
                "$i" "${display_name:0:24}" "$status" "${type:-unknown}" "${mode:-fast}" "${mtu:--}" "${conn:--}" "${cron:-No}"
            ((i++))
        done

        echo -e "${CYAN}└─────┴──────────────────────────┴─────────────┴───────────┴────────────┴──────────┴────────┴────────────────┘${NC}\n"

        echo -e "${YELLOW}Options:${NC}"
        echo -e " 1-${#services[@]}. Select a service to manage"
        echo -e " 0. ↩️  Back to Main Menu"
        echo ""

        read -p "Enter choice: " choice

        [ "$choice" = "0" ] && return

        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#services[@]} )); then
            print_error "Invalid selection"
            sleep 1.5
            continue
        fi

        local selected_service="${services[$((choice-1))]}"
        local sel_name="${selected_service%.service}"
        local sel_display="${sel_name#paqet-x-}"
        manage_single_service "$selected_service" "$sel_display"
    done
}

manage_single_service() {
    local selected_service="$1"
    local display_name="$2"

    while true; do
        show_banner

        local short_name="${display_name:0:32}"
        [ ${#display_name} -gt 32 ] && short_name="${short_name}..."

        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        printf "${GREEN}║ Managing: %-50s ║${NC}\n" "$short_name"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

        local status
        status=$(systemctl is-active "$selected_service" 2>/dev/null) || true
        status="${status:-unknown}"
        status=$(echo "$status" | head -1 | awk '{print $1}')

        echo -en "${CYAN}Status:${NC} "
        case "$status" in
            active)       echo -e "${GREEN}🟢 Active${NC}" ;;
            failed)       echo -e "${RED}🔴 Failed${NC}" ;;
            inactive)     echo -e "${YELLOW}🟡 Inactive${NC}" ;;
            activating)   echo -e "${YELLOW}🟡 Restarting${NC}" ;;
            deactivating) echo -e "${YELLOW}🟡 Stopping${NC}" ;;
            *)            echo -e "${WHITE}⚪ $status${NC}" ;;
        esac

        local details=$(get_service_details "${selected_service%.service}")
        local type=$(echo "$details" | awk '{print $1}')
        local mode=$(echo "$details" | awk '{print $2}')
        local mtu=$(echo "$details" | awk '{print $3}')
        local conn=$(echo "$details" | awk '{print $4}')
        local cron=$(echo "$details" | awk '{print $5}')

        echo -e "\n${CYAN}Details:${NC}"
        echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
        printf "${CYAN}│${NC} %-16s ${CYAN}:${NC} %-25s ${CYAN}│${NC}\n" "Type" "${type:-unknown}"
        printf "${CYAN}│${NC} %-16s ${CYAN}:${NC} %-25s ${CYAN}│${NC}\n" "KCP Mode" "${mode:-fast}"
        printf "${CYAN}│${NC} %-16s ${CYAN}:${NC} %-25s ${CYAN}│${NC}\n" "MTU" "${mtu:--}"
        printf "${CYAN}│${NC} %-16s ${CYAN}:${NC} %-25s ${CYAN}│${NC}\n" "Connections" "${conn:--}"
        printf "${CYAN}│${NC} %-16s ${CYAN}:${NC} %-25s ${CYAN}│${NC}\n" "Auto-Restart" "${cron:-No}"
        echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}"

        echo -e "\n${CYAN}Actions${NC}"
        echo " 1. 🟢 Start"
        echo " 2. 🔴 Stop"
        echo " 3. 🔄 Restart"
        echo " 4. 📊 Show Status"
        echo " 5. 📝 View Recent Logs"
        echo " 6. 📺 Live Logs"
        echo " 7. 📄 View Configuration"
        echo " 8. ✏️  Edit Configuration"
        echo " 9. ⏰ Auto-Restart"
        echo " 10. 🗑️  Delete Service"
        echo " 0. ↩️  Back"
        echo ""

        read -p "Choose action [0-10]: " action

        case "$action" in
            0) return ;;
            1) systemctl start "$selected_service" >/dev/null 2>&1
               print_success "Service started"
               sleep 1.5 ;;
            2) systemctl stop "$selected_service" >/dev/null 2>&1
               print_success "Service stopped"
               sleep 1.5 ;;
            3) systemctl restart "$selected_service" >/dev/null 2>&1
               print_success "Service restarted"
               sleep 1.5 ;;
            4) echo ""
               systemctl status "$selected_service" --no-pager -l
               pause ;;
            5) echo ""
               journalctl -u "$selected_service" -n 30 --no-pager
               pause ;;
            6) echo -e "\n${CYAN}Ctrl+C to return to menu...${NC}\n"
               journalctl -u "$selected_service" -f --no-pager &
               local log_pid=$!
               trap "kill $log_pid 2>/dev/null; wait $log_pid 2>/dev/null" INT
               wait $log_pid 2>/dev/null
               trap - INT
               echo ""
               ;;
            7) local cfg="$CONFIG_DIR/$display_name.yaml"
               if [ -f "$cfg" ]; then
                   echo -e "\n${CYAN}$cfg${NC}\n"
                   cat "$cfg"
               else
                   print_error "Config file not found"
               fi
               pause ;;
            8) local cfg="$CONFIG_DIR/$display_name.yaml"
               if [ -f "$cfg" ]; then
                   echo -e "\n${YELLOW}Editing: $cfg${NC}"
                   local editor="nano"
                   command -v nano &>/dev/null || editor="vi"
                   $editor "$cfg"
                   read -p "Restart service to apply changes? (y/N): " restart_choice
                   if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
                       systemctl restart "$selected_service" >/dev/null 2>&1
                       if systemctl is-active --quiet "$selected_service"; then
                           print_success "Service restarted successfully"
                       else
                           print_error "Service failed to start"
                           systemctl status "$selected_service" --no-pager -l
                       fi
                   fi
               else
                   print_error "Config file not found"
               fi
               pause ;;
            9) manage_auto_restart "$selected_service" "$display_name" ;;
            10) read -p "Delete this service? (y/N): " confirm
               if [[ "$confirm" =~ ^[Yy]$ ]]; then
                   # Safety check: only delete services with paqet- prefix
                   local svc_file="$SERVICE_DIR/$selected_service"
                   if [[ "$selected_service" != paqet-x-* ]]; then
                       print_error "Safety check failed: '$selected_service' is not a paqet-x- service"
                       pause; continue
                   fi
                   systemctl stop "$selected_service" 2>/dev/null || true
                   systemctl disable "$selected_service" 2>/dev/null || true
                   rm -f "$svc_file" 2>/dev/null || true
                   [ -n "$display_name" ] && rm -f "$CONFIG_DIR/$display_name.yaml" 2>/dev/null || true
                   systemctl daemon-reload 2>/dev/null || true
                   remove_auto_restart "${selected_service%.service}"
                   print_success "Service removed"
                   pause
                   return
               fi ;;
            *) print_error "Invalid choice"
               sleep 1 ;;
        esac
    done
}

# ═══════════════════════════════════════
#  Status
# ═══════════════════════════════════════
show_status() {
    show_banner
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Paqet-X Status                                               ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

    local ver="Not installed"
    [ -f "$BIN_DIR/$BIN_NAME" ] && ver=$("$BIN_DIR/$BIN_NAME" version 2>/dev/null | head -1)

    echo -e "┌──────────────────────────────────────────────────────────────┐"
    printf "│ %-18s : %-39s │\n" "OS" "$(detect_os)"
    printf "│ %-18s : %-39s │\n" "Architecture" "$(detect_arch 2>/dev/null)"
    printf "│ %-18s : %-39s │\n" "Public IP" "$(get_public_ip)"
    printf "│ %-18s : %-39s │\n" "Paqet-X" "$ver"
    echo -e "└──────────────────────────────────────────────────────────────┘"

    local services=()
    mapfile -t services < <(systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null |
                          grep -E '^paqet-x-.*\.service' | awk '{print $1}')
    if [ ${#services[@]} -gt 0 ]; then
        echo -e "\n${CYAN}Tunnels:${NC}\n"
        for svc in "${services[@]}"; do
            local st=$(systemctl is-active "$svc" 2>/dev/null)
            local icon; case "$st" in active) icon="${GREEN}🟢${NC}" ;; failed) icon="${RED}🔴${NC}" ;; *) icon="${YELLOW}🟡${NC}" ;; esac
            echo -e " $icon ${svc%.service} ($st)"
        done
    else
        echo -e "\n${YELLOW}No tunnels configured${NC}"
    fi
    pause
}

# ═══════════════════════════════════════
#  Uninstall
# ═══════════════════════════════════════
uninstall_paqet() {
    show_banner
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Uninstall Paqet-X                                            ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo " 1. Remove binary only"
    echo " 2. Remove everything (binary + configs + services)"
    echo " 0. Cancel"
    echo ""
    read -p "Choice [0-2]: " choice
    case $choice in
        0) return ;;
        1) rm -f "$BIN_DIR/$BIN_NAME"; rm -rf "$INSTALL_DIR"; print_success "Binary removed" ;;
        2)
            print_warning "This will remove ALL Paqet-X tunnels!"
            read -p "Type YES to confirm: " confirm
            if [ "$confirm" = "YES" ]; then
                local svcs=()
                mapfile -t svcs < <(systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null |
                                  grep -E '^paqet-x-.*\.service' | awk '{print $1}')
                for s in "${svcs[@]}"; do
                    systemctl stop "$s" 2>/dev/null; systemctl disable "$s" 2>/dev/null
                    rm -f "$SERVICE_DIR/$s"
                done
                systemctl daemon-reload
                rm -f "$BIN_DIR/$BIN_NAME"; rm -rf "$INSTALL_DIR" "$CONFIG_DIR"
                crontab -l 2>/dev/null | grep -v "paqet-x-" | crontab - 2>/dev/null
                print_success "Paqet-X completely removed"
            fi ;;
    esac
    pause
}

# ═══════════════════════════════════════
#  Check Dependencies
# ═══════════════════════════════════════
check_dependencies() {
    local missing_deps=()
    local os=$(detect_os)

    local common_deps=("curl" "wget" "iptables" "lsof")

    case $os in
        ubuntu|debian)
            common_deps+=("libpcap-dev" "iproute2" "cron" "dig") ;;
        centos|rhel|fedora|rocky|almalinux)
            common_deps+=("libpcap-devel" "iproute" "cronie" "bind-utils") ;;
    esac

    for dep in "${common_deps[@]}"; do
        if ! command -v "$dep" &>/dev/null &&
           ! dpkg -l | grep -q "$dep" 2>/dev/null &&
           ! rpm -q "$dep" &>/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -eq 0 ]; then
        return 0
    else
        echo "${missing_deps[@]}"
        return 1
    fi
}

# ═══════════════════════════════════════
#  Main Menu
# ═══════════════════════════════════════
main_menu() {
    while true; do
        show_banner
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  Main Menu                                                     ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"

        # Show Paqet-X binary status
        if [ -f "$BIN_DIR/$BIN_NAME" ]; then
            echo -e "${GREEN}✅ Paqet-X is installed${NC}"
            local core_version
            core_version=$("$BIN_DIR/$BIN_NAME" version 2>/dev/null | grep "^Version:" | head -1 | cut -d':' -f2 | xargs)
            [ -z "$core_version" ] && core_version=$("$BIN_DIR/$BIN_NAME" version 2>/dev/null | head -1)
            if [ -n "$core_version" ]; then
                echo -e "   ${GREEN}└─ Version: ${CYAN}$core_version${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Paqet-X not installed${NC}"
        fi

        # Show dependency status
        local missing_deps
        missing_deps=$(check_dependencies)
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Dependencies are installed${NC}"
        else
            echo -e "${YELLOW}⚠️  Missing dependencies: $missing_deps${NC}"
        fi

        # Show active tunnels count
        local tunnel_count
        tunnel_count=$(systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null |
                      grep -cE '^paqet-x-.*\.service' || echo "0")
        local active_count
        active_count=$(systemctl list-units --type=service --state=active --no-legend --no-pager 2>/dev/null |
                      grep -cE 'paqet-x-' || echo "0")
        echo -e "${CYAN}📊 Tunnels: ${WHITE}$active_count${NC} active / ${WHITE}$tunnel_count${NC} total"

        echo -e "\n${CYAN}1.${NC} 📦 Install Dependencies"
        echo -e "${CYAN}2.${NC} 📥 Install / Update Paqet-X Core"
        echo -e "${CYAN}3.${NC} 🌍 Configure Server (Kharej)"
        echo -e "${CYAN}4.${NC} 🇮🇷 Configure Client (Iran)"
        echo -e "${CYAN}5.${NC} ⚙️  Service Management"
        echo -e "${CYAN}6.${NC} 📊 Status"
        echo -e "${CYAN}7.${NC} 🗑️  Uninstall"
        echo -e "${CYAN}0.${NC} 🚪 Exit"
        echo ""

        read -p "Choose [0-7]: " choice
        case $choice in
            0) echo -e "\n${GREEN}Goodbye! 👋${NC}\n"; exit 0 ;;
            1) install_dependencies ;;
            2) install_paqet ;;
            3) configure_server ;;
            4) configure_client ;;
            5) manage_services ;;
            6) show_status ;;
            7) uninstall_paqet ;;
            *) print_error "Invalid"; sleep 1 ;;
        esac
    done
}

check_root
main_menu
