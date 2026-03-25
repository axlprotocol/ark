# ArkNet — Community GPU Grid

ArkNet is a mesh network of Ark nodes that share models and inference capacity. Instead of every household downloading every model, neighbors can share what they have. Instead of one GPU handling everything, a request can be routed to whichever node has the right model loaded.

---

## What is ArkNet?

ArkNet turns isolated Ark servers into a cooperative grid. Each node remains fully sovereign -- you control what you share, who you share with, and what you accept from others. There is no central authority and no mandatory participation.

**What ArkNet does:**
- Discovers other Ark nodes on your local network automatically
- Lets you approve trusted peers for model and inference sharing
- Routes inference requests to a neighbor's GPU if they have a model you do not
- Encrypts all inter-node traffic

**What ArkNet does not do:**
- Share your conversation history or user data
- Allow anonymous access to your GPU
- Require internet connectivity (local mesh works offline)
- Cost anything

---

## Three Discovery Layers

ArkNet uses three methods to find peers, from simplest to broadest:

### Layer 1: mDNS (Local Network, Zero Config)

Any Ark node on your LAN is discovered automatically via multicast DNS. No setup required.

```
┌──────────┐   mDNS broadcast   ┌──────────┐
│  Ark #1  │◄──────────────────▶│  Ark #2  │
│ 192.168  │    _arknet._tcp    │ 192.168  │
│  .1.100  │                    │  .1.101  │
└──────────┘                    └──────────┘
```

How it works:
- Each Ark node advertises `_arknet._tcp` on the local network
- Other Ark nodes see the advertisement and add it to their peer list
- No ports need to be opened beyond the local network
- Works with zero configuration out of the box

Verify mDNS discovery:

```bash
avahi-browse -t _arknet._tcp
```

### Layer 2: WireGuard (Trusted Tunnel)

For peers outside your LAN -- a friend across town, a family member in another state -- ArkNet uses WireGuard tunnels. See `VPN.md` for WireGuard setup.

```
┌──────────┐   WireGuard tunnel  ┌──────────┐
│  Ark #1  │◄───────────────────▶│  Ark #3  │
│ 10.0.0.1 │   (encrypted UDP)  │ 10.0.0.5 │
│  Home    │                     │  Friend  │
└──────────┘                     └──────────┘
```

Once a WireGuard peer is connected, ArkNet discovers them the same way it discovers LAN peers -- the VPN makes them appear local.

### Layer 3: Public Registry (Opt-In)

For broader discovery, nodes can optionally register with the ArkNet public registry at `registry.projectark.dev`.

```
┌──────────┐                    ┌──────────────────┐
│  Ark #1  │───register────────▶│  registry.       │
│          │◀──peer list────────│  projectark.dev  │
└──────────┘                    └──────────────────┘
```

- Registration is opt-in. Your node is not visible unless you explicitly register.
- The registry only stores: node ID, public key, endpoint (IP:port), and available models
- No conversation data, no user data, no usage metrics
- You still must approve each peer before they can access your node

---

## Peer Approval

ArkNet never grants access automatically. Every peer must be explicitly approved.

### The approved_peers.json file

Located at `/opt/ark/data/arknet/approved_peers.json`:

```json
{
  "peers": [
    {
      "node_id": "ark-neighbor-001",
      "public_key": "WG_PUBLIC_KEY_HERE",
      "name": "Dave's Ark",
      "approved_at": "2026-03-15T10:30:00Z",
      "permissions": {
        "can_request_inference": true,
        "can_pull_models": true,
        "models_shared": ["qwen3.5:35b", "llama3.1:8b"],
        "max_concurrent_requests": 2
      }
    },
    {
      "node_id": "ark-family-002",
      "public_key": "WG_PUBLIC_KEY_HERE",
      "name": "Mom's Ark",
      "approved_at": "2026-03-20T14:00:00Z",
      "permissions": {
        "can_request_inference": true,
        "can_pull_models": false,
        "models_shared": ["llama3.1:8b"],
        "max_concurrent_requests": 1
      }
    }
  ]
}
```

### Permission levels

| Permission | Description |
|-----------|-------------|
| `can_request_inference` | Peer can send prompts to your models |
| `can_pull_models` | Peer can download model weights from your node |
| `models_shared` | Which specific models this peer can access |
| `max_concurrent_requests` | Rate limiting per peer |

### Approving a new peer

When a new node is discovered (via mDNS, WireGuard, or registry), it appears as a pending request. Approve it via the ArkNet API:

```bash
curl -X POST http://localhost:8910/peers/approve \
  -H "Content-Type: application/json" \
  -d '{
    "node_id": "ark-new-peer-003",
    "public_key": "PEER_PUBLIC_KEY",
    "permissions": {
      "can_request_inference": true,
      "can_pull_models": false,
      "models_shared": ["llama3.1:8b"],
      "max_concurrent_requests": 1
    }
  }'
```

---

## How Inference Proxying Works

When you send a chat request and your node does not have the requested model loaded (or does not have it at all), ArkNet can route the request to a peer that does.

### Request flow

```
User → Open WebUI → LiteLLM → Ollama (local)
                                  │
                                  ├─ Model loaded locally? → GPU → Response
                                  │
                                  └─ Model not available? → ArkNet Proxy
                                                               │
                                                               ▼
                                                    Query approved peers
                                                               │
                                              ┌────────────────┼────────────────┐
                                              ▼                ▼                ▼
                                         Peer #1          Peer #2          Peer #3
                                      (has model,      (has model,       (doesn't
                                       busy)            available)        have it)
                                                            │
                                                            ▼
                                                     Run inference
                                                            │
                                                            ▼
                                                     Return response
                                                     to requesting node
```

### What gets sent to the peer

- The model name
- The prompt/messages
- Generation parameters (temperature, max tokens, etc.)

### What does NOT get sent

- Your user identity
- Conversation history beyond the current request
- System-level information about your node
- Any data from other users on your node

### Latency

- LAN peers (mDNS): 1-5ms overhead. Feels identical to local inference.
- WireGuard peers (remote): Depends on internet latency between nodes. Typically 20-100ms overhead.
- The actual inference time (GPU computation) dominates in all cases.

---

## The Density Grid Concept

As more Ark nodes come online in a geographic area, they form a "density grid" -- a neighborhood with collective GPU capacity.

### Example: A neighborhood with 5 Arks

| Node | GPU | Models | VRAM |
|------|-----|--------|------|
| Ark #1 | RTX 4090 | qwen3.5:35b, nomic-embed | 24 GB |
| Ark #2 | RTX 3090 | llama3.1:70b (quantized) | 24 GB |
| Ark #3 | RTX 5090 | devstral, flux-dev | 32 GB |
| Ark #4 | RTX 3060 | llama3.1:8b, phi-3 | 12 GB |
| Ark #5 | RTX 4090 | qwen3.5:35b, deepseek-r1 | 24 GB |

**Collective capacity:** 116 GB VRAM, 5 different large models available, redundancy on qwen3.5:35b.

Any user on any of these nodes can access any shared model across the grid. If Ark #1's GPU is busy, the request automatically routes to Ark #5 (which also has qwen3.5:35b).

### Benefits of density

- **Model diversity without duplication.** Not everyone needs to download every model. One neighbor has the code model, another has the creative writing model, another has the image model.
- **Redundancy.** If one node is offline, others pick up the slack.
- **Load balancing.** Peak usage spreads across multiple GPUs instead of bottlenecking one.
- **Lower barrier to entry.** A family with a budget RTX 3060 still gets access to 35B+ models through their neighbor's more powerful hardware.

---

## Security

### All traffic is encrypted

- LAN peers: ArkNet uses TLS for all inter-node API calls
- WireGuard peers: All traffic is encrypted at the tunnel level
- Registry communication: HTTPS only

### Peer approval is mandatory

- No node can access your GPU without explicit approval
- Approved peers can be revoked at any time
- Each peer has granular permissions (which models, how many concurrent requests)

### No anonymous access

- Every request carries a node identity (public key)
- Unapproved nodes are rejected immediately
- There is no "open relay" mode

### Rate limiting

- Per-peer request limits prevent any single neighbor from monopolizing your GPU
- Local requests always take priority over ArkNet proxy requests
- You can set VRAM reservation to ensure your own models stay loaded

### Audit logging

All ArkNet requests are logged:

```bash
# View recent ArkNet activity
cat /opt/ark/data/arknet/audit.log | tail -20
```

Log entries include: timestamp, peer node ID, model requested, tokens generated, latency.

---

## Future Roadmap

### Content Pack Sharing

Share Kiwix content packs (offline Wikipedia, Khan Academy, Stack Exchange) across the mesh. Instead of each node downloading 90 GB of Wikipedia, one node hosts it and serves pages to neighbors.

### Distributed RAG

Combine vector databases across nodes. Your documents stay on your node, but semantic search can query across the grid (with permission). A neighborhood could build a shared knowledge base without centralizing the data.

### Model Swarm

For very large models that exceed any single GPU's VRAM, ArkNet could split inference across multiple nodes. This is technically challenging but would allow a neighborhood of RTX 3060s to collectively run a 70B model.

### Reputation System

Track peer reliability (uptime, response latency, request success rate) to improve routing decisions. Nodes that are frequently offline or slow get deprioritized in the routing table.

---

## Getting Started with ArkNet

1. **Ensure ArkNet is running.** The service listens on port 8910 and is proxied via Nginx at `/arknet/`.

2. **Check for discovered peers:**
   ```bash
   curl -s http://localhost:8910/peers/discovered | python3 -m json.tool
   ```

3. **Approve a peer** (see the Peer Approval section above).

4. **Verify connectivity:**
   ```bash
   curl -s http://localhost:8910/peers/status | python3 -m json.tool
   ```

5. **Test cross-node inference:**
   ```bash
   # Request a model that only exists on a peer
   curl -s http://localhost:4000/v1/chat/completions \
     -H "Authorization: Bearer sk-ark-YOUR_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "deepseek-r1:70b",
       "messages": [{"role": "user", "content": "Hello from across the grid"}]
     }'
   ```
   If the model is not local but an approved peer has it, ArkNet routes the request transparently.
