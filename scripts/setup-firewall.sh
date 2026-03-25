#!/bin/bash
set -e

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
header(){ echo -e "\n${BOLD}── $* ──${NC}"; }

# ── Root check ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root."
    exit 1
fi

# ── Confirm ─────────────────────────────────────────────────────────────────
header "Firewall Hardening"
warn "This will flush existing iptables rules and apply new ones."
echo -e "${YELLOW}Press Ctrl+C within 5 seconds to abort...${NC}"
sleep 5

# ── Flush existing rules ────────────────────────────────────────────────────
header "Flushing existing rules"
iptables -F
iptables -X
iptables -t nat -F
iptables -t mangle -F
ok "Existing rules flushed."

# ── Default policies ────────────────────────────────────────────────────────
header "Setting default policies"
iptables -P INPUT DROP
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
ok "INPUT=DROP, FORWARD=ACCEPT, OUTPUT=ACCEPT"

# ── Loopback ────────────────────────────────────────────────────────────────
header "Loopback"
iptables -A INPUT -i lo -j ACCEPT
ok "Loopback traffic allowed."

# ── Established / Related ──────────────────────────────────────────────────
header "Stateful connections"
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ok "Established and related connections allowed."

# ── ICMP (ping) ─────────────────────────────────────────────────────────────
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
ok "ICMP echo-request allowed."

# ── CN/RU block on port 4000 (LiteLLM) ─────────────────────────────────────
header "Geo-blocking CN/RU on port 4000 (LiteLLM)"

# Major CN IP ranges (APNIC allocated)
CN_RANGES=(
    "1.0.1.0/24" "1.0.2.0/23" "1.0.8.0/21" "1.1.0.0/24" "1.1.2.0/23"
    "36.0.0.0/8" "39.0.0.0/8" "42.0.0.0/8" "49.0.0.0/8"
    "58.0.0.0/8" "59.0.0.0/8" "60.0.0.0/8" "61.0.0.0/8"
    "101.0.0.0/8" "103.0.0.0/8" "106.0.0.0/8"
    "110.0.0.0/8" "111.0.0.0/8" "112.0.0.0/8" "113.0.0.0/8"
    "114.0.0.0/8" "115.0.0.0/8" "116.0.0.0/8" "117.0.0.0/8"
    "118.0.0.0/8" "119.0.0.0/8" "120.0.0.0/8" "121.0.0.0/8"
    "122.0.0.0/8" "123.0.0.0/8" "124.0.0.0/8" "125.0.0.0/8"
    "139.0.0.0/8" "140.0.0.0/8"
    "159.226.0.0/16" "163.0.0.0/8"
    "171.0.0.0/8" "175.0.0.0/8"
    "180.0.0.0/8" "182.0.0.0/8" "183.0.0.0/8"
    "202.0.0.0/8" "203.0.0.0/8" "210.0.0.0/8" "211.0.0.0/8"
    "218.0.0.0/8" "219.0.0.0/8" "220.0.0.0/8" "221.0.0.0/8"
    "222.0.0.0/8" "223.0.0.0/8"
)

# Major RU IP ranges (RIPE allocated)
RU_RANGES=(
    "2.60.0.0/15" "5.3.0.0/16" "5.8.0.0/16" "5.16.0.0/15"
    "5.34.0.0/16" "5.42.0.0/16" "5.44.0.0/16" "5.45.0.0/16"
    "5.53.0.0/16" "5.59.0.0/16" "5.61.0.0/16" "5.62.0.0/16"
    "31.13.0.0/16" "31.28.0.0/16" "31.40.0.0/16" "31.41.0.0/16"
    "31.44.0.0/16" "31.130.0.0/16" "31.148.0.0/16"
    "37.9.0.0/16" "37.18.0.0/16" "37.29.0.0/16"
    "46.0.0.0/8"
    "62.76.0.0/16" "62.105.0.0/16" "62.118.0.0/16"
    "77.34.0.0/16" "77.35.0.0/16" "77.37.0.0/16"
    "78.25.0.0/16" "78.36.0.0/16" "78.37.0.0/16"
    "79.104.0.0/16" "79.105.0.0/16"
    "80.64.0.0/16" "80.68.0.0/16" "80.73.0.0/16"
    "81.16.0.0/16" "81.17.0.0/16" "81.18.0.0/16"
    "82.138.0.0/16" "82.140.0.0/16" "82.142.0.0/16"
    "83.69.0.0/16" "83.102.0.0/16" "83.149.0.0/16"
    "85.21.0.0/16" "85.26.0.0/16"
    "86.62.0.0/16" "86.102.0.0/16" "86.110.0.0/16"
    "87.117.0.0/16" "87.226.0.0/16" "87.240.0.0/16" "87.250.0.0/16"
    "88.83.0.0/16" "88.147.0.0/16" "88.210.0.0/16"
    "89.108.0.0/16" "89.109.0.0/16" "89.110.0.0/16"
    "90.150.0.0/16" "90.188.0.0/16"
    "91.77.0.0/16" "91.103.0.0/16" "91.122.0.0/16"
    "92.38.0.0/16" "92.39.0.0/16" "92.50.0.0/16"
    "93.170.0.0/16" "93.171.0.0/16" "93.178.0.0/16"
    "94.19.0.0/16" "94.24.0.0/16" "94.25.0.0/16"
    "95.24.0.0/16" "95.25.0.0/16" "95.31.0.0/16"
    "176.59.0.0/16" "176.96.0.0/16"
    "178.34.0.0/16" "178.35.0.0/16" "178.44.0.0/16"
    "185.6.0.0/16"
    "188.32.0.0/16" "188.43.0.0/16"
    "193.19.0.0/16" "193.32.0.0/16" "193.33.0.0/16"
    "194.58.0.0/16" "194.67.0.0/16" "194.85.0.0/16"
    "195.2.0.0/16" "195.3.0.0/16" "195.16.0.0/16"
    "212.41.0.0/16" "212.42.0.0/16" "212.45.0.0/16"
    "213.5.0.0/16" "213.24.0.0/16" "213.33.0.0/16"
    "217.15.0.0/16" "217.16.0.0/16" "217.18.0.0/16"
)

for cidr in "${CN_RANGES[@]}"; do
    iptables -A INPUT -s "$cidr" -p tcp --dport 4000 -j DROP
done
ok "Blocked ${#CN_RANGES[@]} CN ranges on port 4000."

for cidr in "${RU_RANGES[@]}"; do
    iptables -A INPUT -s "$cidr" -p tcp --dport 4000 -j DROP
done
ok "Blocked ${#RU_RANGES[@]} RU ranges on port 4000."

# ── Docker bridge (172.16.0.0/12) ──────────────────────────────────────────
header "Docker bridge network"
DOCKER_CIDR="172.16.0.0/12"

INTERNAL_PORTS=(3000 3001 4000 5678 8910 11434)
for port in "${INTERNAL_PORTS[@]}"; do
    iptables -A INPUT -s "$DOCKER_CIDR" -p tcp --dport "$port" -j ACCEPT
done
ok "Docker bridge (${DOCKER_CIDR}) allowed to internal ports: ${INTERNAL_PORTS[*]}"

# ── Public ports ────────────────────────────────────────────────────────────
header "Allowed public ports"

declare -A PORT_MAP=(
    [22]="SSH"
    [80]="HTTP"
    [443]="HTTPS"
    [3000]="Open WebUI"
    [3001]="Grafana"
    [4000]="LiteLLM"
    [5678]="n8n"
    [8910]="ArkNet"
)

for port in "${!PORT_MAP[@]}"; do
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    ok "Port ${port}/tcp (${PORT_MAP[$port]}) — allowed"
done

# WireGuard (UDP)
iptables -A INPUT -p udp --dport 51820 -j ACCEPT
ok "Port 51820/udp (WireGuard) — allowed"

# ── Save rules ──────────────────────────────────────────────────────────────
header "Persisting rules"
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
ok "Rules saved to /etc/iptables/rules.v4"

# Install iptables-persistent if available
if ! dpkg -l iptables-persistent &>/dev/null; then
    info "Installing iptables-persistent for boot-time restore..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent 2>/dev/null || \
        warn "Could not install iptables-persistent. Ensure rules are loaded at boot manually."
fi

echo ""
ok "Firewall hardening complete."
info "Review rules with: iptables -L -n -v"
