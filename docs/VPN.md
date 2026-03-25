# ARK WireGuard VPN Setup

WireGuard provides encrypted tunnel access to all Ark services without exposing ports to the internet. This is the recommended way to access your Ark from outside your home network.

---

## Overview

```
┌─────────────┐      UDP 51820       ┌─────────────────────┐
│   Laptop    │─────────────────────▶│    Ark Server       │
│  10.0.0.2   │    WireGuard tunnel  │    10.0.0.1         │
│             │◀─────────────────────│                     │
│  Access:    │                      │  Open WebUI :3000   │
│  10.0.0.1   │                      │  Grafana    :3001   │
└─────────────┘                      │  LiteLLM    :4000   │
                                     │  Ollama     :11434  │
┌─────────────┐      UDP 51820       │  ComfyUI    :8188   │
│   Phone     │─────────────────────▶│  n8n        :5678   │
│  10.0.0.3   │    WireGuard tunnel  │                     │
└─────────────┘                      └─────────────────────┘
```

All Ark services are accessible at `10.0.0.1` through the VPN. No ports need to be exposed beyond 51820/UDP.

---

## Step 1: Install WireGuard

### On the Ark server (Ubuntu 24.04)

```bash
sudo apt install -y wireguard wireguard-tools
```

### On clients

| Platform | Install |
|----------|---------|
| Ubuntu/Debian | `sudo apt install -y wireguard` |
| macOS | `brew install wireguard-tools` or download from App Store |
| Windows | Download from https://www.wireguard.com/install/ |
| iOS | App Store: "WireGuard" |
| Android | Play Store: "WireGuard" |

---

## Step 2: Generate Server Keys

```bash
# Generate server private and public keys
wg genkey | sudo tee /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key

# Secure the private key
sudo chmod 600 /etc/wireguard/server_private.key
```

Note the public key -- clients will need it:

```bash
cat /etc/wireguard/server_public.key
```

---

## Step 3: Generate Client Keys

Generate a key pair for each client device:

```bash
# Laptop
wg genkey | tee /tmp/laptop_private.key | wg pubkey > /tmp/laptop_public.key

# Phone
wg genkey | tee /tmp/phone_private.key | wg pubkey > /tmp/phone_public.key
```

---

## Step 4: Server Configuration

Create `/etc/wireguard/wg0.conf`:

```ini
[Interface]
# Server private key (from Step 2)
PrivateKey = SERVER_PRIVATE_KEY_HERE
Address = 10.0.0.1/24
ListenPort = 51820

# Enable IP forwarding for this interface
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# ── Laptop ──────────────────────────────────────────────────
[Peer]
PublicKey = LAPTOP_PUBLIC_KEY_HERE
AllowedIPs = 10.0.0.2/32

# ── Phone ───────────────────────────────────────────────────
[Peer]
PublicKey = PHONE_PUBLIC_KEY_HERE
AllowedIPs = 10.0.0.3/32
```

Replace:
- `SERVER_PRIVATE_KEY_HERE` with contents of `/etc/wireguard/server_private.key`
- `LAPTOP_PUBLIC_KEY_HERE` with contents of `/tmp/laptop_public.key`
- `PHONE_PUBLIC_KEY_HERE` with contents of `/tmp/phone_public.key`
- `eth0` with your actual network interface name (check with `ip route | grep default`)

Set permissions:

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
```

---

## Step 5: Client Configurations

### Laptop config

Create `laptop.conf`:

```ini
[Interface]
PrivateKey = LAPTOP_PRIVATE_KEY_HERE
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = SERVER_PUBLIC_KEY_HERE
Endpoint = YOUR_SERVER_PUBLIC_IP:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

Replace:
- `LAPTOP_PRIVATE_KEY_HERE` with contents of `/tmp/laptop_private.key`
- `SERVER_PUBLIC_KEY_HERE` with contents of `/etc/wireguard/server_public.key`
- `YOUR_SERVER_PUBLIC_IP` with your server's public IP address

### Phone config

Create `phone.conf`:

```ini
[Interface]
PrivateKey = PHONE_PRIVATE_KEY_HERE
Address = 10.0.0.3/24
DNS = 1.1.1.1

[Peer]
PublicKey = SERVER_PUBLIC_KEY_HERE
Endpoint = YOUR_SERVER_PUBLIC_IP:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

### Generate QR Code for Mobile

Install qrencode and generate a scannable QR code for the phone:

```bash
sudo apt install -y qrencode

# Display QR code in terminal
qrencode -t ansiutf8 < phone.conf

# Save as PNG
qrencode -o phone-wireguard.png < phone.conf
```

Open the WireGuard app on your phone, tap **+**, select **Create from QR code**, and scan.

---

## Step 6: Enable IP Forwarding

Required for traffic to flow through the VPN:

```bash
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/99-wireguard.conf
sudo sysctl -p /etc/sysctl.d/99-wireguard.conf
```

---

## Step 7: Start the Tunnel

### On the server

```bash
# Start WireGuard
sudo wg-quick up wg0

# Enable on boot
sudo systemctl enable wg-quick@wg0
```

Verify:

```bash
sudo wg show
```

You should see the interface with the listening port and peer entries (handshake will show after a client connects).

### On the laptop

```bash
# Linux
sudo wg-quick up ./laptop.conf

# macOS (if using CLI)
sudo wg-quick up laptop
```

On Windows/macOS/mobile, import the `.conf` file into the WireGuard GUI and activate.

---

## Step 8: Access Ark Services Over VPN

Once connected, all services are available at `10.0.0.1`:

| Service | VPN URL |
|---------|---------|
| Open WebUI | http://10.0.0.1:3000 |
| Grafana | http://10.0.0.1:3001 |
| LiteLLM API | http://10.0.0.1:4000 |
| n8n | http://10.0.0.1:5678 |
| ChromaDB | http://10.0.0.1:8000 |
| ComfyUI | http://10.0.0.1:8188 |
| Prometheus | http://10.0.0.1:9090 |
| Ollama | http://10.0.0.1:11434 |

Test connectivity:

```bash
# Ping the server through the tunnel
ping 10.0.0.1

# Test Ollama
curl -s http://10.0.0.1:11434/api/tags | python3 -m json.tool

# Test Open WebUI
curl -s -o /dev/null -w "%{http_code}" http://10.0.0.1:3000
```

---

## Adding Multiple Peers

### IP allocation scheme

| IP | Device |
|----|--------|
| 10.0.0.1 | Ark server |
| 10.0.0.2 | Laptop |
| 10.0.0.3 | Phone |
| 10.0.0.4 | Tablet |
| 10.0.0.5 | Second Ark node |
| 10.0.0.10-50 | Family devices |
| 10.0.0.100+ | ArkNet peers |

### Adding a new peer without restarting

```bash
# Generate keys for the new device
wg genkey | tee /tmp/newdevice_private.key | wg pubkey > /tmp/newdevice_public.key

# Add peer to running interface (no restart needed)
sudo wg set wg0 peer $(cat /tmp/newdevice_public.key) allowed-ips 10.0.0.4/32

# Also add to wg0.conf for persistence across reboots
sudo bash -c 'cat >> /etc/wireguard/wg0.conf << EOF

# ── New Device ──────────────────────────────────────────────
[Peer]
PublicKey = $(cat /tmp/newdevice_public.key)
AllowedIPs = 10.0.0.4/32
EOF'
```

Create the client config:

```ini
[Interface]
PrivateKey = NEWDEVICE_PRIVATE_KEY
Address = 10.0.0.4/24
DNS = 1.1.1.1

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = YOUR_SERVER_PUBLIC_IP:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

---

## Troubleshooting

### No handshake happening

```bash
# Check WireGuard is running
sudo wg show

# If "latest handshake" is missing, the client has not connected
```

Common causes:
- **Port not open:** Ensure UDP 51820 is allowed in iptables and forwarded on your router
- **Wrong endpoint:** The client config must have the server's public IP, not LAN IP
- **Key mismatch:** Verify the client's peer public key matches what the server expects

### Can ping 10.0.0.1 but can't reach services

- Check that Ark services are listening on `0.0.0.0` or `10.0.0.1`, not just `127.0.0.1`
- For services bound to `127.0.0.1`, access them through Nginx at `10.0.0.1:80` or `10.0.0.1:443`
- Alternatively, use SSH port forwarding as a fallback:
  ```bash
  ssh -L 3000:127.0.0.1:3000 cdev@10.0.0.1
  ```

### DNS resolution fails over VPN

- The `DNS = 1.1.1.1` line in the client config sets DNS for the tunnel
- If you want to resolve local hostnames, run a DNS server (e.g., dnsmasq) on the Ark server and set `DNS = 10.0.0.1`

### Connection drops after a few minutes

- Ensure `PersistentKeepalive = 25` is set in the client config (keeps NAT mappings alive)
- Check if your ISP or router is blocking sustained UDP connections

### Check WireGuard logs

```bash
sudo journalctl -u wg-quick@wg0 -f
```

### Verify firewall allows WireGuard

```bash
sudo iptables -L INPUT -n | grep 51820
# Should show: ACCEPT udp -- 0.0.0.0/0 0.0.0.0/0 udp dpt:51820
```

### Remove a peer

```bash
# Remove from running interface
sudo wg set wg0 peer PEER_PUBLIC_KEY_HERE remove

# Also remove from wg0.conf manually
sudo nano /etc/wireguard/wg0.conf
```

---

## Security Notes

- **Never share private keys.** Each device gets its own key pair.
- **Rotate keys periodically.** Generate new keys and update configs every 6-12 months.
- **Use AllowedIPs carefully.** Setting `AllowedIPs = 0.0.0.0/0` routes ALL traffic through the VPN (full tunnel). Use `10.0.0.0/24` for split tunnel (only Ark traffic goes through VPN).
- **Clean up temp key files** after distributing configs:
  ```bash
  rm -f /tmp/*_private.key /tmp/*_public.key
  ```
