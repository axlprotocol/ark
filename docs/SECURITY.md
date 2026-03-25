# ARK Security Hardening Guide

Ark runs on your own hardware, but that does not make it secure by default. This guide covers every layer: network, OS, containers, authentication, and monitoring.

---

## Firewall: setup-firewall.sh

Ark ships with an iptables-based firewall script. The policy is **default DROP** on INPUT with explicit allows.

```bash
sudo /opt/ark/network/setup-firewall.sh
```

If the script does not yet exist, configure iptables manually:

```bash
# Flush existing rules
sudo iptables -F
sudo iptables -X

# Default policies
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# Allow loopback
sudo iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# HTTP / HTTPS
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# WireGuard
sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT

# Docker bridge (internal container communication)
sudo iptables -A INPUT -s 172.16.0.0/12 -j ACCEPT

# Prometheus exporters (Docker only)
sudo iptables -A INPUT -s 172.16.0.0/12 -p tcp --dport 9100 -j ACCEPT
sudo iptables -A INPUT -s 172.16.0.0/12 -p tcp --dport 9835 -j ACCEPT

# Ollama (WireGuard peers only)
sudo iptables -A INPUT -s 10.0.0.0/24 -p tcp --dport 11434 -j ACCEPT

# Save rules
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
```

### What is NOT exposed

- Open WebUI (:3000) -- localhost only, accessed via Nginx
- Grafana (:3001) -- localhost only, accessed via Nginx
- LiteLLM (:4000) -- API key required, geo-blocked
- n8n (:5678) -- localhost only, accessed via Nginx
- ChromaDB (:8000) -- localhost only
- ComfyUI (:8188) -- localhost only
- Prometheus (:9090) -- localhost only, basic auth via Nginx

---

## SSH: Key-Only Authentication

Disable password authentication entirely. This eliminates brute-force SSH attacks.

### Generate a key pair (on your local machine)

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
ssh-copy-id -i ~/.ssh/id_ed25519.pub cdev@your-ark-server
```

### Disable password auth (on the Ark server)

```bash
sudo nano /etc/ssh/sshd_config
```

Set these values:

```
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
MaxAuthTries 3
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

**Warning:** Make sure your key works before disabling password auth. Test in a second terminal before closing your current session.

---

## fail2ban

fail2ban watches log files and bans IPs that show malicious activity (brute-force attempts, repeated 401s).

```bash
sudo apt install -y fail2ban
```

Create `/etc/fail2ban/jail.local`:

```ini
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 86400

[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-http-auth
logpath  = /var/log/nginx/error.log
maxretry = 5

[nginx-botsearch]
enabled  = true
port     = http,https
filter   = nginx-botsearch
logpath  = /var/log/nginx/access.log
maxretry = 3
bantime  = 86400
```

Start and enable:

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check status
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

---

## Changing Default Passwords in .env

The installer generates random secrets, but you should review them:

```bash
sudo nano /opt/ark/data/docker-compose/.env
```

Critical values to verify:

| Variable | Purpose | Notes |
|----------|---------|-------|
| `LITELLM_MASTER_KEY` | API authentication | Format: `sk-ark-...`. Share only with trusted clients |
| `WEBUI_SECRET_KEY` | Open WebUI session signing | Random hex string |
| `N8N_PASSWORD` | n8n admin login | Change from default |
| `GRAFANA_PASSWORD` | Grafana admin login | Change from default |

After changing any value:

```bash
cd /opt/ark/data/docker-compose
docker compose down
docker compose up -d
```

---

## Nginx SSL with Certbot

See `DEPLOYMENT.md` Step 11 for initial setup. Additional hardening:

### Enable HSTS

Add to your Nginx server block (inside the `listen 443 ssl` section):

```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

### Disable weak TLS versions

In `/etc/letsencrypt/options-ssl-nginx.conf` or your server block:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
```

### Auto-renewal

Certbot sets up a systemd timer automatically. Verify:

```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
```

---

## WireGuard for Remote Access

**Do not expose Ark services directly to the internet.** Use WireGuard instead. See `VPN.md` for full setup.

The principle: all Ark services bind to `127.0.0.1`. Only Nginx (80/443), SSH (22), and WireGuard (51820) face the internet. Remote clients connect via WireGuard and access services through the VPN tunnel at `10.0.0.1`.

This means even if you skip TLS, traffic is encrypted end-to-end through the WireGuard tunnel.

---

## Container Isolation

### Principles

1. **No `--privileged` containers.** Only GPU passthrough is granted via `--gpus all`.
2. **Read-only root filesystems** where possible. Data volumes are mounted explicitly.
3. **No host networking.** All containers use Docker bridge networks.
4. **Bind to localhost.** Container ports are published as `127.0.0.1:PORT:PORT`, not `0.0.0.0`.
5. **Separate networks.** Frontend services (Open WebUI, Grafana) cannot directly reach backend services (ChromaDB, Prometheus) unless explicitly linked.

### Verify container port bindings

```bash
docker ps --format "table {{.Names}}\t{{.Ports}}" | sort
```

Every port should show `127.0.0.1:` prefix, except Ollama (which needs LAN/VPN access) and exporters.

---

## The cdev (Compute Device) User Pattern

**Do not run Ark as root. Do not log in as root daily.**

Create a dedicated non-root user:

```bash
sudo adduser cdev
sudo usermod -aG docker cdev
sudo usermod -aG sudo cdev
```

### Use cdev for daily operations

- SSH in as `cdev`
- Run `ollama` commands as `cdev`
- Use `docker` commands as `cdev` (via docker group)
- Use `sudo` only for system-level changes (firewall, Nginx, systemd)

### Root access pattern

```bash
# Only when needed:
sudo systemctl restart nginx
sudo iptables -L -n
sudo certbot renew

# Never:
ssh root@ark-server    # Root login is disabled
```

---

## API Key Management for LiteLLM

### Master key

The master key (`sk-ark-...`) has full access. Treat it like a root password.

- Stored in `/opt/ark/data/docker-compose/.env` as `LITELLM_MASTER_KEY`
- Used for admin operations: creating virtual keys, viewing usage

### Virtual keys (per-user or per-application)

Create scoped keys with budgets:

```bash
# Create a key with a monthly budget
curl -s http://localhost:4000/key/generate \
  -H "Authorization: Bearer sk-ark-YOUR_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "family-laptop",
    "max_budget": 0,
    "models": ["qwen3.5:35b", "llama3.1:8b"],
    "duration": "30d"
  }' | python3 -m json.tool
```

### List active keys

```bash
curl -s http://localhost:4000/key/info \
  -H "Authorization: Bearer sk-ark-YOUR_MASTER_KEY" \
  | python3 -m json.tool
```

### Revoke a key

```bash
curl -s http://localhost:4000/key/delete \
  -H "Authorization: Bearer sk-ark-YOUR_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"keys": ["sk-revoked-key-here"]}'
```

---

## Geo-Blocking (CN/RU IP Ranges)

Block known scanner-heavy regions on sensitive ports. This reduces noise significantly.

### Using iptables with ipset

```bash
sudo apt install -y ipset

# Create IP sets
sudo ipset create geoblock-cn hash:net
sudo ipset create geoblock-ru hash:net

# Download and load country IP ranges
# Using ipdeny.com aggregated zones
wget -q https://www.ipdeny.com/ipblocks/data/aggregated/cn-aggregated.zone -O /tmp/cn.zone
wget -q https://www.ipdeny.com/ipblocks/data/aggregated/ru-aggregated.zone -O /tmp/ru.zone

while read cidr; do
  sudo ipset add geoblock-cn "$cidr" 2>/dev/null
done < /tmp/cn.zone

while read cidr; do
  sudo ipset add geoblock-ru "$cidr" 2>/dev/null
done < /tmp/ru.zone

# Block on LiteLLM port
sudo iptables -I INPUT -p tcp --dport 4000 -m set --match-set geoblock-cn src -j DROP
sudo iptables -I INPUT -p tcp --dport 4000 -m set --match-set geoblock-ru src -j DROP

# Block on HTTP/HTTPS too (optional, stricter)
sudo iptables -I INPUT -p tcp --dport 443 -m set --match-set geoblock-cn src -j DROP
sudo iptables -I INPUT -p tcp --dport 443 -m set --match-set geoblock-ru src -j DROP

# Save
sudo ipset save > /etc/ipset.conf
sudo netfilter-persistent save
```

### Restore on boot

Create `/etc/systemd/system/ipset-restore.service`:

```ini
[Unit]
Description=Restore ipset rules
Before=netfilter-persistent.service

[Service]
Type=oneshot
ExecStart=/sbin/ipset restore -f /etc/ipset.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable ipset-restore
```

---

## Monitoring for Intrusion via Grafana Alerts

### What to monitor

| Metric | Alert Threshold | Meaning |
|--------|----------------|---------|
| SSH failed logins | > 10 in 5 min | Brute force attempt |
| Nginx 401/403 rate | > 50 in 5 min | API probing |
| New Docker containers | Any unexpected | Container escape attempt |
| CPU > 95% sustained | > 10 min | Cryptominer or abuse |
| Outbound traffic spike | > 1 GB/hr unexpected | Data exfiltration |
| fail2ban bans | Any | Active attack blocked |

### Setting up Grafana alerts

1. Open Grafana at http://localhost:3001
2. Go to **Alerting > Alert Rules > New Alert Rule**
3. Set the data source to Prometheus
4. Example query for high CPU:
   ```promql
   100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 95
   ```
5. Set evaluation interval to 1 minute
6. Add a notification channel (email, webhook, or Slack via n8n)

### Useful Prometheus queries for security

```promql
# Failed SSH attempts (requires node_exporter textfile collector)
node_textfile_scrape_error

# Nginx error rate
rate(nginx_http_requests_total{status=~"4.."}[5m])

# GPU temperature (overheating = possible abuse)
nvidia_gpu_temperature_celsius > 85

# Ollama request rate (unusual spikes)
rate(ollama_requests_total[5m])
```

---

## Security Checklist

- [ ] Firewall configured with default DROP policy
- [ ] SSH is key-only, root login disabled
- [ ] fail2ban installed and running
- [ ] All passwords in `.env` changed from defaults
- [ ] Nginx with TLS enabled (or WireGuard-only access)
- [ ] WireGuard configured for remote access
- [ ] No containers running as `--privileged`
- [ ] All service ports bound to 127.0.0.1 (except SSH, Nginx, WireGuard)
- [ ] cdev user created, daily operations run as non-root
- [ ] LiteLLM master key secured, virtual keys issued for clients
- [ ] Geo-blocking enabled for CN/RU ranges
- [ ] Grafana alerts configured for intrusion indicators
- [ ] Automatic security updates enabled (`sudo apt install unattended-upgrades`)
