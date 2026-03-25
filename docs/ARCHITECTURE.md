# ARK Architecture — Complete System Design

## Overview

ARK is a single-machine AI operations platform. One box runs everything: LLM inference, API proxy, chat interface, image generation, experiment orchestration, 3D visualization, monitoring, and secure multi-tenant access.

No Kubernetes. No microservices mesh. No cloud dependency. One machine, one docker-compose, full sovereignty.

## Hardware Baseline

| Component | Minimum | Recommended (Ark Spec) |
|-----------|---------|-------------------------------|
| CPU | 8-core x86_64 | AMD Ryzen 9 9950X (16C/32T) |
| RAM | 32 GB DDR4 | 96 GB DDR5 |
| GPU | RTX 3060 12GB | RTX 4090/5090 (24-32GB VRAM) |
| Storage | 500 GB NVMe | 2 TB NVMe |
| Network | 100 Mbps | 1 Gbps symmetric |
| OS | Ubuntu 22.04+ | Ubuntu 24.04 LTS |

## Network Architecture

```
                    INTERNET
                       │
                       ▼
            ┌──────────────────┐
            │   Nginx (443)    │  ← Let's Encrypt TLS
            │  Reverse Proxy   │
            └────────┬─────────┘
                     │
        ┌────────────┼────────────────────────┐
        │            │                        │
   ┌────▼────┐  ┌────▼────┐  ┌────▼────┐  ┌──▼──────┐
   │Open     │  │LiteLLM  │  │Grafana  │  │ Other   │
   │WebUI    │  │  :4000   │  │ :3001   │  │Services │
   │ :3000   │  │         │  │         │  │         │
   └────┬────┘  └────┬────┘  └─────────┘  └─────────┘
        │            │
        └──────┬─────┘
               ▼
        ┌─────────────┐     ┌─────────────┐
        │   Ollama     │────▶│   RTX 5090  │
        │  :11434      │     │   32GB VRAM │
        └──────────────┘     └─────────────┘
```

### Port Map

| Port | Service | Binding | Access |
|------|---------|---------|--------|
| 22 | SSH | 0.0.0.0 | Key auth only |
| 80 | Nginx HTTP | 0.0.0.0 | Redirect to 443 |
| 443 | Nginx HTTPS | 0.0.0.0 | TLS termination |
| 3000 | Open WebUI | 127.0.0.1 | Via Nginx |
| 3001 | Grafana | 127.0.0.1 | Via Nginx |
| 4000 | LiteLLM | 0.0.0.0 | API key required |
| 5678 | n8n | 127.0.0.1 | Via Nginx |
| 8000 | ChromaDB | 127.0.0.1 | Via Nginx |
| 8188 | ComfyUI | 127.0.0.1 | Via Nginx |
| 9090 | Prometheus | 127.0.0.1 | Via Nginx + basic auth |
| 9100 | node_exporter | 0.0.0.0 | Metrics only |
| 9835 | nvidia_gpu_exporter | 0.0.0.0 | Metrics only |
| 11434 | Ollama | 0.0.0.0 | Via WireGuard + LiteLLM |
| 51820 | WireGuard | 0.0.0.0 | UDP, VPN mesh |

### Domain Routing (Nginx)

```
chat.domain.io        → 127.0.0.1:3000  (Open WebUI)
llm.domain.io         → 127.0.0.1:4000  (LiteLLM API)
art.domain.io         → 127.0.0.1:8188  (ComfyUI)
grafana.domain.io     → 127.0.0.1:3001  (Grafana)
n8n.domain.io         → 127.0.0.1:5678  (n8n)
prometheus.domain.io  → 127.0.0.1:9090  (Prometheus)
chromadb.domain.io    → 127.0.0.1:8000  (ChromaDB)
```

## Service Architecture

### Layer 1: GPU Inference
- **Ollama** (systemd) — Loads/unloads LLM models on demand. VRAM management is critical: only one large model at a time on consumer GPUs.
- **ComfyUI** (Docker + GPU passthrough) — Image generation via Flux, SD, etc. Holds ~750MB VRAM when idle.

### Layer 2: API Proxy
- **LiteLLM** (Docker) — OpenAI-compatible API that routes to Ollama. Supports model aliasing (`gpt-4` → local model), API key auth, request logging to Prometheus.

### Layer 3: User Interfaces
- **Open WebUI** (Docker) — Full-featured chat UI with model selection, document upload, RAG via ChromaDB. Auto-login via proxy auth headers.
- **ComfyUI** — Drag-and-drop image generation workflows.

### Layer 4: Data & Storage
- **ChromaDB** (Docker) — Vector database for RAG embeddings.
- **NVMe** at `/opt/ark/data/` — All persistent data, models, experiments, recordings.

### Layer 5: Monitoring
- **Prometheus** (Docker) — Scrapes node_exporter (CPU/RAM/disk), nvidia_gpu_exporter (GPU temp/VRAM/power), Ollama, LiteLLM.
- **Grafana** (Docker) — Dashboards for GPU health, system metrics, API usage.

### Layer 6: Automation
- **n8n** (Docker) — Workflow automation. Connects to LiteLLM, webhooks, email, etc.

### Layer 7: Networking
- **Nginx** (systemd) — Reverse proxy with Let's Encrypt TLS. All subdomains terminate here.
- **WireGuard** (systemd) — VPN mesh connecting remote nodes (Battlegrounds server, mobile devices).

### Layer 8: Security
- **iptables** — Default DROP policy. Explicit allows for each service.
- **API key auth** — LiteLLM master key. Virtual keys with budgets (requires DB).
- **Geo-blocking** — CN/RU IP ranges blocked on API ports.
- **Proxy auth** — Open WebUI auto-login via trusted headers from Nginx.

## Data Flow

### Chat Request
```
User → chat.domain.io → Nginx → Open WebUI → Ollama → GPU → Response
```

### API Request (External)
```
Client → llm.domain.io → Nginx → LiteLLM (key check) → Ollama → GPU → Response
```

### Experiment Pipeline
```
MiroFish (remote) → Sophon Receiver (8099) → /opt/ark/data/experiments/
                                                       │
                                                       ▼
                                              Blender (GPU EEVEE)
                                                       │
                                                       ▼
                                              /opt/ark/data/recordings/
                                                       │
                                                       ▼
                                              axl.domain.io/recordings/
```

### Monitoring
```
node_exporter (9100) ─┐
nvidia_gpu (9835)  ───┤
ollama (11434)     ───┼──→ Prometheus (9090) ──→ Grafana (3001)
litellm (4000)     ───┘
```

## VRAM Management

The GPU is the most constrained resource. VRAM allocation:

| Model | VRAM | Priority |
|-------|------|----------|
| qwen3.5:35b | ~23 GB | High (primary thinker) |
| devstral-small-2 | ~15 GB | Medium (coder) |
| Dolphin-Mistral-24B | ~13 GB | Low (uncensored) |
| nomic-embed-text | ~0.3 GB | Always loaded |
| ComfyUI (idle) | ~0.75 GB | Background |

**Rule:** Only one large model loaded at a time. Ollama auto-unloads after timeout. ComfyUI can be freed with `curl -X POST http://localhost:8188/free`.

If Ollama hangs after VRAM pressure:
```bash
curl -X POST http://localhost:8188/free \
  -H "Content-Type: application/json" \
  -d '{"unload_models":true,"free_memory":true}'
sudo systemctl restart ollama
```

## File System Layout

```
/opt/ark/data/                    # Primary data volume (NVMe)
├── docker-compose/               # docker-compose.yml
├── docker-data/                  # Docker data root
├── ollama/                       # Model weights (~50GB+)
├── open-webui/                   # Chat history, user data
├── litellm/                      # config.yaml
├── prometheus/                   # prometheus.yml + TSDB (30d retention)
├── grafana/                      # Dashboard data
├── chromadb/                     # Vector store
├── comfyui/                      # Models, outputs, workflows
├── n8n/                          # Workflow data
├── experiments/                  # Sophon experiment data
├── recordings/                   # Rendered videos
└── ark-dashboard/         # Landing page app

/opt/                             # Applications
├── ark/                          # THIS PROJECT
├── teams/                        # Agent team profiles (FORGE, LENS, PRISM)
├── sophon-blender/               # Blender scene pipeline
├── sophon-3d/                    # Three.js renderer (deprecated)
├── sophon-receiver/              # Experiment data receiver
└── sophon-prism/                 # Future interactive cockpit
```

## Security Hardening

### Firewall (iptables)
```
Default policy: INPUT DROP
Allowed:
  - SSH (22) from anywhere
  - HTTP/HTTPS (80/443) from anywhere
  - WireGuard (51820/UDP) from anywhere
  - Docker bridge (172.16.0.0/12) to internal ports
  - node_exporter (9100) from Docker only
  - nvidia_gpu_exporter (9835) from Docker only

Blocked:
  - CN/RU IP ranges on port 4000 (LiteLLM)
  - Known scanner IPs (full DROP)
```

### Authentication
- **Open WebUI:** Proxy auth via Nginx headers (X-Trusted-Email, X-Trusted-Name)
- **LiteLLM:** Master API key (`sk-ark-*`)
- **Grafana:** Proxy auth via Nginx (X-WEBAUTH-USER)
- **Prometheus:** Basic auth via Nginx
- **SSH:** Key-only, no password

### TLS
- Nginx with Let's Encrypt (certbot auto-renewal)
- All subdomains: `*.yourdomain.com`
- HSTS enabled

## Deployment Checklist

1. Install Ubuntu 24.04 LTS
2. Partition NVMe, mount at `/opt/ark/data`
3. Install NVIDIA driver (570+) and CUDA toolkit
4. Install Docker with NVIDIA Container Toolkit
5. Install Ollama, pull models
6. Deploy docker-compose (all services)
7. Install Nginx, configure subdomains, run certbot
8. Install WireGuard, configure peers
9. Install Prometheus exporters (node, gpu)
10. Import Grafana dashboards
11. Configure iptables firewall
12. Set up LiteLLM API keys
13. Test all endpoints
14. Set up monitoring alerts

## Extensions (Optional)

| Extension | Purpose | Files |
|-----------|---------|-------|
| Sophon | Experiment orchestration + 3D replay | `/opt/sophon-*` |
| Blender Pipeline | Cinema-quality data visualization | `/opt/sophon-blender/` |
| MiroFish | Remote agent swarm coordinator | External (DigitalOcean) |
| PRISM | Interactive Three.js cockpit | `/opt/sophon-prism/` (future) |
