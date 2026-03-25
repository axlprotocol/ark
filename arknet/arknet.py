"""
ArkNet — Discovery and peer communication service for Ark nodes.
Layers: mDNS discovery, REST API (aiohttp :8910), optional registry client.
"""

import asyncio
import json
import logging
import os
import platform
import socket
import subprocess
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import aiohttp
import aiohttp_cors
from aiohttp import web
from zeroconf import IPVersion, ServiceBrowser, ServiceInfo, ServiceStateChange, Zeroconf

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NODE_ID_PATH = Path(os.getenv("ARKNET_NODE_ID_PATH", "/opt/ark/arknet/node_id"))
APPROVED_PEERS_PATH = Path(os.getenv("ARKNET_PEERS_PATH", "/opt/ark/arknet/approved_peers.json"))
SERVICE_TYPE = "_ark._tcp.local."
SERVICE_PORT = 8910
ARK_VERSION = "0.3.0"

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
LITELLM_HOST = os.getenv("LITELLM_HOST", "http://localhost:4000")
LITELLM_API_KEY = os.getenv("LITELLM_API_KEY", os.getenv("LITELLM_MASTER_KEY", ""))
REGISTRY_URL = os.getenv("ARKNET_REGISTRY_URL", "https://registry.projectark.dev/api/v1/announce")
REGISTRY_ENABLED = os.getenv("ARKNET_REGISTRY_ENABLED", "false").lower() == "true"
NODE_NAME = os.getenv("ARKNET_NODE_NAME", platform.node())

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger("arknet")

# ---------------------------------------------------------------------------
# Globals populated at startup
# ---------------------------------------------------------------------------

BOOT_TIME = time.time()
PEERS: dict[str, dict] = {}  # node_id -> {name, ip, port, gpu, models, seen, ...}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


def generate_node_id() -> str:
    """Load or create a persistent node UUID."""
    if NODE_ID_PATH.exists():
        nid = NODE_ID_PATH.read_text().strip()
        if nid:
            return nid
    nid = str(uuid.uuid4())
    try:
        NODE_ID_PATH.parent.mkdir(parents=True, exist_ok=True)
        NODE_ID_PATH.write_text(nid + "\n")
    except OSError as exc:
        log.warning("Could not persist node_id: %s", exc)
    return nid


def probe_gpu() -> dict:
    """Query nvidia-smi for GPU name and VRAM."""
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"],
            text=True,
            timeout=5,
        ).strip()
        parts = [p.strip() for p in out.split(",")]
        name = parts[0]
        vram_str = parts[1] if len(parts) > 1 else "0 MiB"
        vram_mb = int("".join(c for c in vram_str.split()[0] if c.isdigit()) or 0)
        vram_gb = round(vram_mb / 1024, 1)
        return {"gpu_model": name, "gpu_vram_gb": vram_gb}
    except FileNotFoundError:
        log.warning("nvidia-smi not found — no GPU detected")
        return {"gpu_model": "none", "gpu_vram_gb": 0}
    except Exception as exc:
        log.warning("GPU probe failed: %s", exc)
        return {"gpu_model": "unknown", "gpu_vram_gb": 0}


async def probe_models() -> list[dict]:
    """Query Ollama for available models."""
    try:
        async with aiohttp.ClientSession() as s:
            async with s.get(f"{OLLAMA_HOST}/api/tags", timeout=aiohttp.ClientTimeout(total=5)) as r:
                if r.status != 200:
                    return []
                data = await r.json()
                return [
                    {"name": m["name"], "size": m.get("size", 0)}
                    for m in data.get("models", [])
                ]
    except Exception as exc:
        log.debug("Ollama probe failed: %s", exc)
        return []


def probe_system() -> dict:
    """Gather basic system info from /proc."""
    info: dict = {"cpu": "unknown", "ram_gb": 0}
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    info["cpu"] = line.split(":", 1)[1].strip()
                    break
    except OSError:
        pass
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal"):
                    kb = int(line.split()[1])
                    info["ram_gb"] = round(kb / 1024 / 1024, 1)
                    break
    except OSError:
        pass
    return info


def load_approved_peers() -> dict:
    """Load approved peers from disk."""
    try:
        if APPROVED_PEERS_PATH.exists():
            return json.loads(APPROVED_PEERS_PATH.read_text())
    except Exception as exc:
        log.warning("Failed to load approved peers: %s", exc)
    return {}


def save_approved_peers(data: dict) -> None:
    """Persist approved peers to disk."""
    try:
        APPROVED_PEERS_PATH.parent.mkdir(parents=True, exist_ok=True)
        APPROVED_PEERS_PATH.write_text(json.dumps(data, indent=2) + "\n")
    except OSError as exc:
        log.warning("Failed to save approved peers: %s", exc)


def get_local_ip() -> str:
    """Best-effort LAN IP."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"


# ---------------------------------------------------------------------------
# Layer 1 — mDNS Discovery (zeroconf)
# ---------------------------------------------------------------------------


class ArkServiceListener:
    """Handles mDNS service state changes for _ark._tcp.local."""

    def __init__(self, zc: Zeroconf, own_node_id: str):
        self.zc = zc
        self.own_node_id = own_node_id

    def on_state_change(
        self, zeroconf: Zeroconf, service_type: str, name: str, state_change: ServiceStateChange
    ) -> None:
        if state_change in (ServiceStateChange.Added, ServiceStateChange.Updated):
            info = zeroconf.get_service_info(service_type, name)
            if info is None:
                return
            props = {k.decode(): v.decode() if isinstance(v, bytes) else v for k, v in info.properties.items()}
            node_id = props.get("node_id", "")
            if node_id == self.own_node_id:
                return  # skip self
            addresses = [socket.inet_ntoa(a) for a in info.addresses if len(a) == 4]
            ip = addresses[0] if addresses else "unknown"
            PEERS[node_id] = {
                "node_id": node_id,
                "name": props.get("node_name", "unknown"),
                "ip": ip,
                "port": info.port,
                "gpu_model": props.get("gpu_model", "unknown"),
                "gpu_vram_gb": props.get("gpu_vram_gb", "0"),
                "available_models": props.get("available_models", ""),
                "ark_version": props.get("ark_version", ""),
                "last_seen": datetime.now(timezone.utc).isoformat(),
            }
            log.info("Discovered peer %s (%s) at %s", props.get("node_name"), node_id[:8], ip)

        elif state_change is ServiceStateChange.Removed:
            # Try to find the peer by name and remove
            info = zeroconf.get_service_info(service_type, name)
            if info:
                props = {k.decode(): v.decode() if isinstance(v, bytes) else v for k, v in info.properties.items()}
                nid = props.get("node_id", "")
                PEERS.pop(nid, None)
                log.info("Peer removed: %s", nid[:8])


def register_mdns(node_id: str, gpu: dict, model_names: list[str]) -> tuple[Zeroconf, ServiceInfo]:
    """Register this node via mDNS and start browsing."""
    local_ip = get_local_ip()
    txt_records = {
        "node_id": node_id,
        "node_name": NODE_NAME,
        "gpu_model": gpu.get("gpu_model", "none"),
        "gpu_vram_gb": str(gpu.get("gpu_vram_gb", 0)),
        "available_models": ",".join(model_names)[:255],  # TXT record length cap
        "ark_version": ARK_VERSION,
    }

    service_info = ServiceInfo(
        SERVICE_TYPE,
        name=f"{NODE_NAME}.{SERVICE_TYPE}",
        addresses=[socket.inet_aton(local_ip)],
        port=SERVICE_PORT,
        properties=txt_records,
        server=f"{NODE_NAME}.local.",
    )

    zc = Zeroconf(ip_version=IPVersion.V4Only)
    zc.register_service(service_info)
    log.info("mDNS service registered: %s at %s:%d", NODE_NAME, local_ip, SERVICE_PORT)

    listener = ArkServiceListener(zc, node_id)
    ServiceBrowser(zc, SERVICE_TYPE, handlers=[listener.on_state_change])
    return zc, service_info


# ---------------------------------------------------------------------------
# Layer 2 — REST API
# ---------------------------------------------------------------------------


def build_app(node_id: str, gpu: dict, system_info: dict) -> web.Application:
    app = web.Application()
    app["node_id"] = node_id
    app["gpu"] = gpu
    app["system_info"] = system_info

    app.router.add_get("/ark/v1/status", handle_status)
    app.router.add_get("/ark/v1/peers", handle_peers)
    app.router.add_post("/ark/v1/peers/approve", handle_approve)
    app.router.add_post("/ark/v1/peers/revoke", handle_revoke)
    app.router.add_get("/ark/v1/models", handle_models)
    app.router.add_post("/ark/v1/inference", handle_inference)
    app.router.add_get("/ark/v1/knowledge/search", handle_knowledge_search)

    # CORS — allow all origins for LAN convenience
    cors = aiohttp_cors.setup(app, defaults={
        "*": aiohttp_cors.ResourceOptions(
            allow_credentials=True,
            expose_headers="*",
            allow_headers="*",
        )
    })
    for route in list(app.router.routes()):
        cors.add(route)

    return app


async def handle_status(request: web.Request) -> web.Response:
    models = await probe_models()
    return web.json_response({
        "node_id": request.app["node_id"],
        "node_name": NODE_NAME,
        "gpu": request.app["gpu"],
        "system": request.app["system_info"],
        "models": [m["name"] for m in models],
        "model_count": len(models),
        "uptime_seconds": round(time.time() - BOOT_TIME, 1),
        "ark_version": ARK_VERSION,
    })


async def handle_peers(request: web.Request) -> web.Response:
    approved = load_approved_peers()
    peers_out = []
    for nid, p in PEERS.items():
        entry = dict(p)
        entry["approved"] = nid in approved
        peers_out.append(entry)
    return web.json_response({"peers": peers_out, "count": len(peers_out)})


async def handle_approve(request: web.Request) -> web.Response:
    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": "Invalid JSON"}, status=400)

    node_id = body.get("node_id", "").strip()
    if not node_id:
        return web.json_response({"error": "node_id required"}, status=400)

    peer = PEERS.get(node_id)
    approved = load_approved_peers()
    approved[node_id] = {
        "name": peer["name"] if peer else body.get("name", "unknown"),
        "ip": peer["ip"] if peer else body.get("ip", "unknown"),
        "approved_at": datetime.now(timezone.utc).isoformat(),
    }
    save_approved_peers(approved)
    log.info("Peer approved: %s", node_id[:8])
    return web.json_response({"status": "approved", "node_id": node_id})


async def handle_revoke(request: web.Request) -> web.Response:
    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": "Invalid JSON"}, status=400)

    node_id = body.get("node_id", "").strip()
    if not node_id:
        return web.json_response({"error": "node_id required"}, status=400)

    approved = load_approved_peers()
    if node_id in approved:
        del approved[node_id]
        save_approved_peers(approved)
        log.info("Peer revoked: %s", node_id[:8])
        return web.json_response({"status": "revoked", "node_id": node_id})
    return web.json_response({"error": "Peer not found in approved list"}, status=404)


async def handle_models(request: web.Request) -> web.Response:
    models = await probe_models()
    return web.json_response({"models": models, "count": len(models)})


async def handle_inference(request: web.Request) -> web.Response:
    """Proxy inference to local LiteLLM — only for approved peers."""
    caller_id = request.headers.get("X-Ark-Node-Id", "").strip()
    if not caller_id:
        return web.json_response(
            {"error": "X-Ark-Node-Id header required"}, status=401
        )

    approved = load_approved_peers()
    if caller_id not in approved:
        return web.json_response(
            {"error": "Peer not approved. Request approval first."}, status=403
        )

    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": "Invalid JSON body"}, status=400)

    # Forward to LiteLLM's OpenAI-compatible endpoint
    headers = {"Content-Type": "application/json"}
    if LITELLM_API_KEY:
        headers["Authorization"] = f"Bearer {LITELLM_API_KEY}"

    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{LITELLM_HOST}/v1/chat/completions",
                json=body,
                headers=headers,
                timeout=aiohttp.ClientTimeout(total=300),
            ) as resp:
                result = await resp.json()
                return web.json_response(result, status=resp.status)
    except aiohttp.ClientError as exc:
        return web.json_response(
            {"error": f"LiteLLM proxy error: {exc}"}, status=502
        )


async def handle_knowledge_search(request: web.Request) -> web.Response:
    """Placeholder for distributed RAG search."""
    return web.json_response({
        "status": "not_implemented",
        "message": "Distributed knowledge search is planned for a future release.",
    }, status=501)


# ---------------------------------------------------------------------------
# Layer 3 — Registry Client (opt-in)
# ---------------------------------------------------------------------------


async def registry_announce(node_id: str, gpu: dict, model_count: int) -> None:
    """Periodically announce to the central registry if enabled."""
    if not REGISTRY_ENABLED:
        log.info("Registry client disabled (ARKNET_REGISTRY_ENABLED=false)")
        return

    log.info("Registry client enabled — announcing to %s", REGISTRY_URL)
    while True:
        payload = {
            "node_id": node_id,
            "public_ip": get_local_ip(),
            "gpu_model": gpu.get("gpu_model", "none"),
            "model_count": model_count,
            "ark_version": ARK_VERSION,
        }
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    REGISTRY_URL,
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=10),
                ) as resp:
                    log.info("Registry announce: HTTP %d", resp.status)
        except Exception as exc:
            log.warning("Registry announce failed: %s", exc)
        await asyncio.sleep(300)  # every 5 minutes


# ---------------------------------------------------------------------------
# Background: refresh mDNS TXT records with current model list
# ---------------------------------------------------------------------------


async def mdns_refresh_loop(zc: Zeroconf, service_info: ServiceInfo, node_id: str, gpu: dict) -> None:
    """Periodically update the mDNS TXT record with fresh model list."""
    while True:
        await asyncio.sleep(120)
        try:
            models = await probe_models()
            model_names = [m["name"] for m in models]
            new_props = {
                "node_id": node_id,
                "node_name": NODE_NAME,
                "gpu_model": gpu.get("gpu_model", "none"),
                "gpu_vram_gb": str(gpu.get("gpu_vram_gb", 0)),
                "available_models": ",".join(model_names)[:255],
                "ark_version": ARK_VERSION,
            }
            service_info.properties = {k.encode(): v.encode() for k, v in new_props.items()}
            zc.update_service(service_info)
            log.debug("mDNS TXT records refreshed (%d models)", len(model_names))
        except Exception as exc:
            log.warning("mDNS refresh failed: %s", exc)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


async def main() -> None:
    node_id = generate_node_id()
    log.info("ArkNet starting — node %s (%s)", NODE_NAME, node_id[:8])

    gpu = probe_gpu()
    system_info = probe_system()
    log.info("GPU: %s (%s GB)  CPU: %s  RAM: %s GB",
             gpu["gpu_model"], gpu["gpu_vram_gb"],
             system_info["cpu"][:40], system_info["ram_gb"])

    # Probe models (best-effort)
    models = await probe_models()
    model_names = [m["name"] for m in models]
    log.info("Ollama models: %s", model_names if model_names else "(none / offline)")

    # Layer 1 — mDNS
    zc, svc_info = register_mdns(node_id, gpu, model_names)

    # Layer 3 — Registry (background, if enabled)
    asyncio.create_task(registry_announce(node_id, gpu, len(models)))

    # Background mDNS refresh
    asyncio.create_task(mdns_refresh_loop(zc, svc_info, node_id, gpu))

    # Layer 2 — REST API
    app = build_app(node_id, gpu, system_info)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", SERVICE_PORT)
    await site.start()
    log.info("REST API listening on 0.0.0.0:%d", SERVICE_PORT)

    # Block forever
    try:
        await asyncio.Event().wait()
    finally:
        log.info("Shutting down…")
        zc.unregister_service(svc_info)
        zc.close()
        await runner.cleanup()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("ArkNet stopped.")
