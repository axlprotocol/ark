# ARK Deployment Guide

From bare metal Ubuntu 24.04 to a running Ark instance. This guide assumes a clean install.

---

## Prerequisites

### Hardware

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 8-core x86_64 | AMD Ryzen 9 9950X (16C/32T) |
| RAM | 32 GB DDR4 | 96 GB DDR5 |
| GPU | RTX 3060 12GB | RTX 4090/5090 (24-32GB VRAM) |
| Storage | 500 GB NVMe | 2 TB NVMe |
| Network | 100 Mbps | 1 Gbps symmetric |

### Operating System

- Ubuntu 24.04 LTS (server or desktop, server preferred)
- UEFI boot, GPT partition table
- Separate NVMe partition for `/opt/ark/data` (recommended: dedicate the entire drive)

### Network

- Static IP on your LAN (set via Netplan or router DHCP reservation)
- Port forwarding on your router for: 22 (SSH), 80/443 (HTTP/HTTPS), 51820/UDP (WireGuard)
- A domain name pointed at your public IP (optional but recommended for TLS)

---

## Step 1: Prepare the Storage Volume

Format and mount the NVMe drive that will hold all Ark data:

```bash
# Identify the drive (e.g., /dev/nvme1n1)
lsblk

# Create partition and filesystem
sudo mkfs.ext4 /dev/nvme1n1p1

# Create mount point and mount
sudo mkdir -p /opt/ark/data
sudo mount /dev/nvme1n1p1 /opt/ark/data

# Add to fstab for persistence
echo "/dev/nvme1n1p1  /opt/ark/data  ext4  defaults  0  2" | sudo tee -a /etc/fstab
```

---

## Step 2: Install NVIDIA Driver

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y nvidia-driver-570-open
sudo reboot
```

After reboot, verify:

```bash
nvidia-smi
```

You should see your GPU model, driver version, and CUDA version.

Alternatively, use the Ark GPU setup script:

```bash
sudo /opt/ark/scripts/setup-gpu.sh
```

This script installs the driver, NVIDIA Container Toolkit, and configures the Docker runtime.

---

## Step 3: Clone Ark

```bash
sudo git clone https://github.com/your-org/ark.git /opt/ark
cd /opt/ark
```

---

## Step 4: Run the Installer

```bash
sudo ./install.sh
```

The installer will:

1. Verify Ubuntu, NVIDIA driver, and Docker are present (installs Docker and Ollama if missing)
2. Install the NVIDIA Container Toolkit for GPU passthrough to Docker containers
3. Create all directories under `/opt/ark/data/`
4. Copy configuration files (LiteLLM, Prometheus, docker-compose)
5. Generate `/opt/ark/data/docker-compose/.env` with random secrets (master API key, session keys, passwords)
6. Start all Docker services via `docker compose up -d`
7. Install Prometheus exporters (node_exporter, nvidia_gpu_exporter)
8. Begin pulling the default LLM model in the background

**Save the LiteLLM master key** printed during installation. You will need it for API access.

---

## Step 5: Post-Install Checklist

Run these checks immediately after install:

```bash
# All containers running?
docker ps

# Expected: open-webui, litellm, grafana, prometheus, chromadb, n8n, comfyui

# Ollama responding?
curl -s http://localhost:11434/api/tags | python3 -m json.tool

# LiteLLM responding?
curl -s http://localhost:4000/health

# GPU accessible from Docker?
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
```

---

## Step 6: Pull Your First Model

Ollama manages model downloads. Pull the primary reasoning model:

```bash
ollama pull qwen3.5:35b
```

This downloads approximately 20 GB. Monitor progress with:

```bash
ollama list
```

Other useful models:

```bash
ollama pull devstral-small-2         # Code generation (~15 GB)
ollama pull nomic-embed-text         # Embeddings for RAG (~0.3 GB)
ollama pull llama3.1:8b              # Lighter general model (~4.7 GB)
```

---

## Step 7: Test the API

### Direct Ollama test

```bash
curl -s http://localhost:11434/api/generate \
  -d '{"model": "qwen3.5:35b", "prompt": "Hello, who are you?", "stream": false}' \
  | python3 -m json.tool
```

### LiteLLM (OpenAI-compatible) test

```bash
# Replace sk-ark-... with your actual master key from install
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-ark-YOUR_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5:35b",
    "messages": [{"role": "user", "content": "What is Ark?"}],
    "stream": false
  }' | python3 -m json.tool
```

### Streaming test

```bash
curl -N http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-ark-YOUR_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5:35b",
    "messages": [{"role": "user", "content": "Explain recursion in 3 sentences."}],
    "stream": true
  }'
```

---

## Step 8: Access Services

After installation, all services are available on localhost:

| Service | URL | Purpose |
|---------|-----|---------|
| Open WebUI | http://localhost:3000 | Chat interface (ChatGPT-equivalent) |
| Grafana | http://localhost:3001 | System and GPU monitoring dashboards |
| LiteLLM | http://localhost:4000 | OpenAI-compatible API proxy |
| n8n | http://localhost:5678 | Workflow automation |
| ChromaDB | http://localhost:8000 | Vector database for RAG |
| ComfyUI | http://localhost:8188 | Image generation workflows |
| Prometheus | http://localhost:9090 | Metrics database |
| Ollama | http://localhost:11434 | Direct model inference |

---

## Step 9: Set Up User Accounts in Open WebUI

1. Open http://localhost:3000 in your browser
2. The first account you create becomes the **admin account** -- choose a strong password
3. As admin, go to **Admin Panel > Users** to create additional accounts
4. For each family member, create a separate account with a unique login
5. Under **Admin Panel > Settings > Models**, you can restrict which models are visible to non-admin users
6. Enable or disable features per-user: document upload, image generation, model selection

**Tip:** Keep uncensored models (e.g., Dolphin) visible only to admin accounts. See `FAMILY-GUIDE.md` for details.

---

## Step 10: Set Up Nginx Reverse Proxy

Install Nginx and link the Ark config:

```bash
sudo apt install -y nginx
sudo ln -s /opt/ark/configs/nginx/ark.conf /etc/nginx/sites-enabled/ark.conf
sudo rm -f /etc/nginx/sites-enabled/default
```

Edit the config to set your domain:

```bash
sudo nano /opt/ark/configs/nginx/ark.conf
# Replace "ark.local" with your actual domain
```

Test and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

---

## Step 11 (Optional): Domain + TLS with Certbot

If you have a domain pointed at your server:

```bash
# Install certbot
sudo apt install -y certbot python3-certbot-nginx

# Obtain certificate (replace with your domain)
sudo certbot --nginx -d yourdomain.com

# Auto-renewal is configured automatically. Test it:
sudo certbot renew --dry-run
```

Certbot will modify your Nginx config to add SSL listeners and redirect HTTP to HTTPS.

For subdomain routing (chat.domain.com, grafana.domain.com, etc.), set up DNS A records for each subdomain and run certbot for each:

```bash
sudo certbot --nginx -d chat.yourdomain.com -d grafana.yourdomain.com -d llm.yourdomain.com
```

---

## Verifying Everything Works

Run through this final checklist:

- [ ] `nvidia-smi` shows your GPU
- [ ] `docker ps` shows all containers running
- [ ] `ollama list` shows at least one model
- [ ] Open WebUI loads at :3000 and you can chat
- [ ] Grafana loads at :3001 with GPU metrics visible
- [ ] LiteLLM responds to API calls at :4000
- [ ] Nginx proxies correctly (if configured)
- [ ] TLS certificate is valid (if configured)

---

## Troubleshooting

### Containers won't start

```bash
cd /opt/ark/data/docker-compose
docker compose logs --tail=50
```

### Ollama out of VRAM

Only one large model fits in VRAM at a time. Free ComfyUI memory and restart:

```bash
curl -X POST http://localhost:8188/free \
  -H "Content-Type: application/json" \
  -d '{"unload_models":true,"free_memory":true}'
sudo systemctl restart ollama
```

### Model pull fails

```bash
# Check disk space
df -h /opt/ark/data

# Retry
ollama pull qwen3.5:35b
```

### Port conflicts

```bash
sudo ss -tlnp | grep -E '3000|3001|4000|8188|11434'
```

---

## File Locations Reference

| Path | Contents |
|------|----------|
| `/opt/ark/` | Ark source code, scripts, configs |
| `/opt/ark/install.sh` | Main installer |
| `/opt/ark/scripts/setup-gpu.sh` | GPU driver + container toolkit setup |
| `/opt/ark/configs/nginx/ark.conf` | Nginx reverse proxy config |
| `/opt/ark/configs/litellm.yaml` | LiteLLM model routing config |
| `/opt/ark/configs/prometheus.yml` | Prometheus scrape targets |
| `/opt/ark/data/` | All persistent data |
| `/opt/ark/data/docker-compose/.env` | Secrets and environment variables |
| `/opt/ark/data/docker-compose/docker-compose.yml` | Service definitions |
| `/opt/ark/data/ollama/` | Downloaded model weights |
| `/opt/ark/data/open-webui/` | Chat history, user data |
| `/opt/ark/data/grafana/` | Dashboard configs and data |
