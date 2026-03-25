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
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root."
    exit 1
fi

COMPOSE_DIR="/opt/ark/data/docker-compose"

echo -e "${BOLD}${CYAN}Starting Ark services...${NC}"

# ── Docker Compose ──────────────────────────────────────────────────────────
info "Starting Docker Compose stack..."
if [[ -d "$COMPOSE_DIR" ]]; then
    cd "$COMPOSE_DIR"
    if docker compose up -d; then
        ok "Docker Compose stack started."
    else
        fail "Docker Compose failed to start."
        exit 1
    fi
else
    fail "Compose directory not found: ${COMPOSE_DIR}"
    exit 1
fi

# ── Ollama ──────────────────────────────────────────────────────────────────
info "Starting Ollama service..."
if systemctl start ollama 2>/dev/null; then
    ok "Ollama started."
else
    fail "Failed to start Ollama. Check: systemctl status ollama"
    exit 1
fi

echo ""
ok "All Ark services started."
