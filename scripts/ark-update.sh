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

if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root."
    exit 1
fi

COMPOSE_DIR="/opt/ark/data/docker-compose"

echo -e "${BOLD}${CYAN}Updating Ark services...${NC}"

if [[ ! -d "$COMPOSE_DIR" ]]; then
    fail "Compose directory not found: ${COMPOSE_DIR}"
    exit 1
fi

cd "$COMPOSE_DIR"

# ── Pull latest images ─────────────────────────────────────────────────────
info "Pulling latest images..."
if docker compose pull; then
    ok "All images pulled."
else
    warn "Some images may have failed to pull."
fi

# ── Recreate with new images ───────────────────────────────────────────────
info "Recreating containers with updated images..."
if docker compose up -d --remove-orphans; then
    ok "Containers recreated."
else
    fail "Failed to recreate containers."
    exit 1
fi

echo ""
ok "Ark update complete."
info "Run 'ark-status' to verify all services are healthy."
