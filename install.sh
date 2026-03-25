#!/bin/bash
set -e

echo "═══ ARK INSTALLER ═══"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then echo "Run as root: sudo ./install.sh"; exit 1; fi

# Check Ubuntu
source /etc/os-release
if [ "$ID" != "ubuntu" ]; then echo "Ubuntu required"; exit 1; fi
echo "  OS: $PRETTY_NAME ✓"

# Check GPU
if ! command -v nvidia-smi &>/dev/null; then
    echo "  GPU: NVIDIA driver not found. Install first:"
    echo "    sudo apt install nvidia-driver-570-open"
    exit 1
fi
GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader)
echo "  GPU: $GPU ✓"

# Check Docker
if ! command -v docker &>/dev/null; then
    echo "  Docker: Installing..."
    curl -fsSL https://get.docker.com | sh
    # NVIDIA Container Toolkit
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update && apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
fi
echo "  Docker: $(docker --version) ✓"

# Check Ollama
if ! command -v ollama &>/dev/null; then
    echo "  Ollama: Installing..."
    curl -fsSL https://ollama.com/install.sh | sh
fi
echo "  Ollama: $(ollama --version) ✓"

# Create data directory
DATA_DIR="/opt/ark/data"
mkdir -p $DATA_DIR/{docker-compose,litellm,prometheus/data,grafana,chromadb,open-webui,n8n,comfyui,recordings,experiments}

# Copy configs
cp configs/litellm.yaml $DATA_DIR/litellm/config.yaml
cp configs/prometheus.yml $DATA_DIR/prometheus/prometheus.yml
cp docker/docker-compose.yml $DATA_DIR/docker-compose/docker-compose.yml

# Generate .env if not exists
if [ ! -f $DATA_DIR/docker-compose/.env ]; then
    cp configs/.env.example $DATA_DIR/docker-compose/.env
    MASTER_KEY="sk-ark-$(openssl rand -hex 24)"
    sed -i "s/LITELLM_MASTER_KEY=.*/LITELLM_MASTER_KEY=$MASTER_KEY/" $DATA_DIR/docker-compose/.env
    sed -i "s/WEBUI_SECRET_KEY=.*/WEBUI_SECRET_KEY=$(openssl rand -hex 16)/" $DATA_DIR/docker-compose/.env
    sed -i "s/N8N_PASSWORD=.*/N8N_PASSWORD=$(openssl rand -hex 12)/" $DATA_DIR/docker-compose/.env
    sed -i "s/GRAFANA_PASSWORD=.*/GRAFANA_PASSWORD=$(openssl rand -hex 12)/" $DATA_DIR/docker-compose/.env
    echo "  Generated .env with random secrets"
    echo "  LiteLLM master key: $MASTER_KEY"
fi

# Start services
cd $DATA_DIR/docker-compose
docker compose up -d
echo ""
echo "  Services started ✓"

# Install exporters
echo "  Installing Prometheus exporters..."
# node_exporter
if ! systemctl is-active --quiet node_exporter; then
    useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
    wget -q https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-*.linux-amd64.tar.gz -O /tmp/ne.tar.gz 2>/dev/null
    # (actual install steps here)
    echo "    node_exporter: install manually — see docs/DEPLOYMENT.md"
fi

# Pull default model
echo "  Pulling default LLM model..."
ollama pull qwen3.5:35b &
echo "    Model pull started in background"

echo ""
echo "═══ ARK INSTALLED ═══"
echo ""
echo "  Chat:       http://localhost:3000"
echo "  API:        http://localhost:4000/v1/chat/completions"
echo "  Grafana:    http://localhost:3001"
echo "  Prometheus: http://localhost:9090"
echo ""
echo "  Next steps:"
echo "    1. Edit /opt/ark/data/docker-compose/.env"
echo "    2. Set up Nginx + TLS: see docs/DEPLOYMENT.md"
echo "    3. Configure WireGuard: see docs/VPN.md"
echo "    4. Import Grafana dashboards: see monitoring/"
echo ""
