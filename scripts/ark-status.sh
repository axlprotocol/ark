#!/bin/bash

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

status_ok()   { echo -e "  ${GREEN}●${NC} $*"; }
status_fail() { echo -e "  ${RED}●${NC} $*"; }
status_warn() { echo -e "  ${YELLOW}●${NC} $*"; }
header()      { echo -e "\n${BOLD}${CYAN}━━ $* ━━${NC}"; }
divider()     { echo -e "${DIM}──────────────────────────────────────────────${NC}"; }

echo -e "${BOLD}${CYAN}"
echo "    ╔═══════════════════════════════╗"
echo "    ║       ARK STATUS REPORT       ║"
echo "    ╚═══════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${NC}"

# ── Docker Containers ──────────────────────────────────────────────────────
header "Docker Containers"
if command -v docker &>/dev/null; then
    RUNNING=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)
    if [[ $RUNNING -gt 0 ]]; then
        status_ok "${RUNNING} container(s) running"
        echo ""
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | \
            while IFS= read -r line; do echo "    $line"; done
    else
        status_warn "No containers running"
    fi
else
    status_fail "Docker not installed"
fi

# ── Listening Ports ─────────────────────────────────────────────────────────
header "Listening Ports"
if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | while IFS= read -r line; do echo "    $line"; done
else
    netstat -tlnp 2>/dev/null | while IFS= read -r line; do echo "    $line"; done
fi

# ── GPU Utilization ─────────────────────────────────────────────────────────
header "GPU"
if command -v nvidia-smi &>/dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
    if [[ -n "$GPU_INFO" ]]; then
        IFS=',' read -r GPU_NAME GPU_UTIL MEM_USED MEM_TOTAL GPU_TEMP <<< "$GPU_INFO"
        GPU_NAME=$(echo "$GPU_NAME" | xargs)
        GPU_UTIL=$(echo "$GPU_UTIL" | xargs)
        MEM_USED=$(echo "$MEM_USED" | xargs)
        MEM_TOTAL=$(echo "$MEM_TOTAL" | xargs)
        GPU_TEMP=$(echo "$GPU_TEMP" | xargs)

        status_ok "${GPU_NAME}"
        echo -e "    Utilization: ${BOLD}${GPU_UTIL}%${NC}"
        echo -e "    VRAM:        ${BOLD}${MEM_USED} MiB / ${MEM_TOTAL} MiB${NC}"
        echo -e "    Temperature: ${BOLD}${GPU_TEMP}°C${NC}"
    else
        status_fail "nvidia-smi returned no data"
    fi
else
    status_fail "nvidia-smi not found"
fi

# ── RAM Usage ───────────────────────────────────────────────────────────────
header "RAM"
if command -v free &>/dev/null; then
    read -r TOTAL USED AVAIL <<< $(free -m | awk '/^Mem:/{print $2, $3, $7}')
    PCT=$((USED * 100 / TOTAL))
    if [[ $PCT -lt 80 ]]; then
        status_ok "RAM: ${USED}M / ${TOTAL}M (${PCT}%) — ${AVAIL}M available"
    elif [[ $PCT -lt 95 ]]; then
        status_warn "RAM: ${USED}M / ${TOTAL}M (${PCT}%) — ${AVAIL}M available"
    else
        status_fail "RAM: ${USED}M / ${TOTAL}M (${PCT}%) — ${AVAIL}M available"
    fi
fi

# ── Disk Usage (/opt/ark/data) ──────────────────────────────────────────────
header "Disk (/opt/ark/data)"
if mountpoint -q /opt/ark/data 2>/dev/null || [[ -d /opt/ark/data ]]; then
    read -r SIZE USED AVAIL PCT MOUNT <<< $(df -h /opt/ark/data 2>/dev/null | awk 'NR==2{print $2, $3, $4, $5, $6}')
    PCT_NUM=${PCT//%/}
    if [[ $PCT_NUM -lt 80 ]]; then
        status_ok "Disk: ${USED} / ${SIZE} (${PCT}) — ${AVAIL} free"
    elif [[ $PCT_NUM -lt 95 ]]; then
        status_warn "Disk: ${USED} / ${SIZE} (${PCT}) — ${AVAIL} free"
    else
        status_fail "Disk: ${USED} / ${SIZE} (${PCT}) — ${AVAIL} free"
    fi
else
    status_fail "/opt/ark/data not found"
fi

# ── Ollama Models ───────────────────────────────────────────────────────────
header "Ollama Models"
OLLAMA_RESP=$(curl -s --connect-timeout 3 --max-time 5 http://localhost:11434/api/tags 2>/dev/null)
if [[ $? -eq 0 && -n "$OLLAMA_RESP" ]]; then
    MODEL_COUNT=$(echo "$OLLAMA_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('models',[])))" 2>/dev/null || echo "0")
    if [[ "$MODEL_COUNT" -gt 0 ]]; then
        status_ok "${MODEL_COUNT} model(s) available"
        echo "$OLLAMA_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('models', []):
    name = m.get('name', 'unknown')
    size_gb = m.get('size', 0) / (1024**3)
    print(f'    {name:40s} {size_gb:6.1f} GB')
" 2>/dev/null
    else
        status_warn "Ollama running but no models loaded"
    fi
else
    status_fail "Ollama API not responding (localhost:11434)"
fi

# ── LiteLLM Health ──────────────────────────────────────────────────────────
header "LiteLLM"
LITELLM_RESP=$(curl -s --connect-timeout 3 --max-time 5 http://localhost:4000/health 2>/dev/null)
if [[ $? -eq 0 && -n "$LITELLM_RESP" ]]; then
    status_ok "LiteLLM healthy"
    echo -e "    ${DIM}${LITELLM_RESP}${NC}"
else
    status_fail "LiteLLM not responding (localhost:4000)"
fi

echo ""
divider
echo -e "  ${DIM}Report generated at $(date '+%H:%M:%S')${NC}"
echo ""
