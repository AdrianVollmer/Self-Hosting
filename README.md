anchorage
=========

A lightweight framework for self-hosting containerized applications using
podman, caddy, and systemd.

- Per-service lifecycle management via a systemd template unit
- Automatic TLS via Caddy's internal CA (`local_certs`)
- Caddyfile generated automatically from labels in `docker-compose.yml`
- Dynamic DNS registration for local network hostnames
- Rootless container execution under a dedicated `anchorage` system user

# Installation

Build and install the Debian package (requires `dpkg-deb`, `gzip`):

```console
./build-deb.sh
apt install ./anchorage_*.deb
```

This installs all scripts, systemd units, and creates the `anchorage` system
user with rootless podman configured.

Alternatively, install manually:

```console
apt install podman podman-compose caddy python3 python3-yaml bind9-dnsutils
cp gen-caddyfile.py run.sh dns-update.sh /usr/lib/anchorage/
cp container@.service anchorage-gen-caddyfile.service dns-update.service \
   /etc/systemd/system/
systemctl daemon-reload
```

# Set up a new service

A service consists of:

- A directory under `/var/lib/anchorage/<name>/`
- A `docker-compose.yml` with `caddy.host` and `caddy.port` labels
- Optional: `env.app` for service-specific environment variables
- `/var/lib/anchorage/env.shared` for variables shared by all services (including
  `DOMAIN_SUFFIX`)

Always prefer SQLite over a separate database process where possible -- it
gives you a single file you can copy, back up, or move. If you need
Postgres, run one shared instance and reference it from `env.shared`.

[LinuxServer.io](https://docs.linuxserver.io/images/) has many suitable images.

## Caddyfile generation

When caddy starts or restarts, `anchorage-gen-caddyfile.service` runs first
and scans all `/var/lib/anchorage/*/docker-compose.yml` files for services with
these two labels:

| Label | Meaning |
|---|---|
| `caddy.host` | Subdomain (without the domain suffix) |
| `caddy.port` | Host port mapped in the `ports` section |

The Caddyfile is written to `/etc/caddy/Caddyfile` automatically. Do not
edit it by hand.

## Example: Vaultwarden

```console
mkdir -p /var/lib/anchorage/vaultwarden/data
```

```yaml
# /var/lib/anchorage/vaultwarden/docker-compose.yml
services:
  vaultwarden:
    image: docker.io/vaultwarden/server:latest
    restart: unless-stopped
    labels:
      caddy.host: vault        # resolves to vault.<DOMAIN_SUFFIX>
      caddy.port: "10002"
    environment:
      - ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}
      - DOMAIN=https://vault.${DOMAIN_SUFFIX}
      - SIGNUPS_ALLOWED=false
      - WEBSOCKET_ENABLED=true
      - ROCKET_PORT=80
    volumes:
      - ./data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "10002:80"
```

`VAULTWARDEN_ADMIN_TOKEN` goes in `/var/lib/anchorage/vaultwarden/env.app`.
`DOMAIN_SUFFIX` is set in `/etc/anchorage/anchorage.conf`.

Enable and start:

```console
systemctl enable --now container@vaultwarden.service
systemctl start anchorage-gen-caddyfile.service   # regenerates config and reloads caddy
systemctl start dns-update.service                # register DNS (if enabled)
```

# Managing services

```console
systemctl status container@vaultwarden.service
systemctl restart container@vaultwarden.service
journalctl -f -u container@vaultwarden.service
```

# Reverse proxy and TLS

Caddy issues TLS certificates using its internal CA. The root certificate is at:

```
/home/caddy/.local/share/caddy/pki/authorities/local/root.crt
```

Distribute this to all devices that need to reach your services.

# Configuration

All system-wide settings live in `/etc/anchorage/anchorage.conf`:

```ini
DOMAIN_SUFFIX=local     # DNS suffix for all service hostnames
IP=192.168.1.42         # This host's IP address
DNS_SERVER=192.168.1.1  # DNS server for dynamic updates (nsupdate)
TTL=3600                # DNS record TTL in seconds
```

`DOMAIN_SUFFIX` is the only required field. `IP` and `DNS_SERVER` are only
needed if you enable `dns-update.service`.

After editing the config, apply changes without downtime:

```console
systemctl start anchorage-gen-caddyfile.service
```

A full `systemctl restart caddy` is still needed if you change Caddy's global
options block or want to trigger DNS registration.

# DNS automation

Enable `dns-update.service` so it runs whenever caddy starts or restarts.
It reads `IP`, `DNS_SERVER`, and `DOMAIN_SUFFIX` from
`/etc/anchorage/anchorage.conf`.

```console
systemctl enable dns-update.service
systemctl restart caddy
```

# Access

For private access, enable the WireGuard VPN on your router and connect with
[WG Tunnel](https://github.com/wgtunnel/wgtunnel) (Android) or the official
WireGuard client.

For shared access with friends, consider
[Tailscale](https://tailscale.com/) or its self-hosted alternative
[Headscale](https://headscale.net/).
