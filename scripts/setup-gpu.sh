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

# ── GPU Detection ───────────────────────────────────────────────────────────
header "Detecting NVIDIA GPU"
if ! lspci 2>/dev/null | grep -qi nvidia; then
    fail "No NVIDIA GPU detected via lspci."
    exit 1
fi

GPU_NAME=$(lspci | grep -i nvidia | head -1 | sed 's/.*: //')
ok "Found GPU: ${GPU_NAME}"

# ── NVIDIA Driver ───────────────────────────────────────────────────────────
header "NVIDIA Driver (nvidia-driver-570-open)"

if command -v nvidia-smi &>/dev/null; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)
    if [[ "$DRIVER_VER" == 570.* ]]; then
        ok "nvidia-driver-570-open already installed (version ${DRIVER_VER})"
    else
        warn "Different driver version detected: ${DRIVER_VER}"
        info "Installing nvidia-driver-570-open..."
        apt-get update -qq
        apt-get install -y nvidia-driver-570-open
    fi
else
    info "Installing nvidia-driver-570-open..."
    apt-get update -qq
    apt-get install -y nvidia-driver-570-open
    ok "Driver installed. A reboot may be required."
fi

# ── NVIDIA Container Toolkit ───────────────────────────────────────────────
header "NVIDIA Container Toolkit"

if dpkg -l nvidia-container-toolkit &>/dev/null; then
    ok "nvidia-container-toolkit already installed."
else
    info "Adding NVIDIA container toolkit repository..."
    if [[ ! -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg ]]; then
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
            | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    fi

    DIST=$(. /etc/os-release && echo "$ID$VERSION_ID" | sed 's/\.//g')
    curl -fsSL "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
        | sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#" \
        | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    apt-get update -qq
    apt-get install -y nvidia-container-toolkit
    ok "nvidia-container-toolkit installed."
fi

# ── Docker Runtime Configuration ───────────────────────────────────────────
header "Docker Runtime Configuration"

if command -v docker &>/dev/null; then
    DAEMON_JSON="/etc/docker/daemon.json"
    if [[ -f "$DAEMON_JSON" ]] && grep -q "nvidia" "$DAEMON_JSON" 2>/dev/null; then
        ok "Docker already configured with NVIDIA runtime."
    else
        info "Configuring NVIDIA runtime for Docker..."
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
        ok "Docker runtime configured and restarted."
    fi
else
    warn "Docker is not installed. Skipping Docker runtime configuration."
fi

# ── Verification ────────────────────────────────────────────────────────────
header "Verification"

if command -v nvidia-smi &>/dev/null; then
    echo ""
    nvidia-smi
    echo ""
    ok "nvidia-smi works. GPU is ready."
else
    warn "nvidia-smi not found. A reboot may be required after driver install."
fi

echo ""
ok "GPU setup complete."
