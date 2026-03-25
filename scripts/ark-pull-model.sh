#!/bin/bash
set -e

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

# ── Arg check ───────────────────────────────────────────────────────────────
if [[ -z "$1" ]]; then
    fail "Usage: ark-pull-model <model-name>"
    echo -e "  ${DIM}Example: ark-pull-model llama3.1:70b${NC}"
    exit 1
fi

MODEL="$1"

echo -e "${BOLD}${CYAN}Pulling model: ${MODEL}${NC}"
echo ""

# ── Pull ────────────────────────────────────────────────────────────────────
if command -v ollama &>/dev/null; then
    if ollama pull "$MODEL"; then
        ok "Model '${MODEL}' pulled successfully."
    else
        fail "Failed to pull model '${MODEL}'."
        exit 1
    fi
else
    fail "Ollama CLI not found. Is Ollama installed?"
    exit 1
fi

# ── VRAM after pull ─────────────────────────────────────────────────────────
echo ""
info "Current VRAM usage:"
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name,memory.used,memory.total,memory.free --format=csv,noheader 2>/dev/null | \
        while IFS=',' read -r name used total free; do
            echo -e "  ${BOLD}$(echo "$name" | xargs)${NC}"
            echo -e "    Used: $(echo "$used" | xargs)  |  Total: $(echo "$total" | xargs)  |  Free: $(echo "$free" | xargs)"
        done
else
    echo -e "  ${YELLOW}nvidia-smi not available${NC}"
fi
echo ""
