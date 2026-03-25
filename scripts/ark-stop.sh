#!/bin/bash
set -e

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
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

echo -e "${BOLD}${CYAN}Stopping Ark services...${NC}"

# ── Docker Compose ──────────────────────────────────────────────────────────
info "Stopping Docker Compose stack..."
if [[ -d "$COMPOSE_DIR" ]]; then
    cd "$COMPOSE_DIR"
    if docker compose down; then
        ok "Docker Compose stack stopped."
    else
        fail "Docker Compose failed to stop cleanly."
    fi
else
    fail "Compose directory not found: ${COMPOSE_DIR}"
fi

# ── Ollama ──────────────────────────────────────────────────────────────────
info "Stopping Ollama service..."
if systemctl stop ollama 2>/dev/null; then
    ok "Ollama stopped."
else
    fail "Failed to stop Ollama."
fi

echo ""
ok "All Ark services stopped."
