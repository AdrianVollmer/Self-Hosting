Self-hosting with containers
============================

Leverage containers and systemd services to easily self-host apps.

Assumes podman, but works with docker as well.

# Prerequisites

Systemd and podman-compose. Install on Debian-like systems:

```console
apt install podman podman-compose
```

# Installation

```console
mkdir -p /opt/container
cp run.sh /opt/container
cp container@.service /etc/systemd/system
systemctl daemon-reload
```

# Set up a new service

A service now consist of:

- a directory in `/opt/container`
- a `docker-compose.yml` file
- Optional: a `env.app` in the container directory
- Optional: a `/opt/container/env.shared` for environment variables shared by
  all containers.

Always try to configure your services to use sqlite, if possible. This gives you
a single file which can be easily copied, backupped or moved.

The next best option is to set up a single postgres service on the host system.
Hostname and port can be defined in `env.shared`.

[https://docs.linuxserver.io/images/](LinuxServer.io) has lots of suitable
images.

# Example

We will use [Vaultwarden](https://www.vaultwarden.net/) as an example.

Create the directories:

```console
mkdir -p /opt/container/vaultwarden/data
```

```yaml
# /opt/container/vaultwarden/docker-compose.yml
version: '3.8'

services:
  vaultwarden:
    image: docker.io/vaultwarden/server:${VAULTWARDEN_VERSION}
    container_name: vaultwarden
    restart: unless-stopped
    environment:
      - ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}
      - DOMAIN=https://vault.${DOMAIN_SUFFIX}
      - SIGNUPS_ALLOWED=false  # change to `true` once so you can sign up
      - WEBSOCKET_ENABLED=true
      - ROCKET_PORT=80
    volumes:
      - ./data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "10002:80"
```

Here, `ADMIN_TOKEN=...` would be defined in `env.app`, and `DOMAIN_SUFFIX=...`
would be defined in `env.shared`.

Enable and start the service:

```console
systemctl enable --now container@vaultwarden.service
```

# Manage a service

Use `systemctl [status|start|stop|restart] <service name>` for status, start, stop, restart (duh).

Check logs:

```console
journalctl -f -u container@vaultwarden.service
```


# Reverse proxy

Caddy makes it very simple to endow your services with certificates.

In this example, we assume your local network suffix is `fritz.box`.

Install with `apt install caddy`, then edit your configuration:

```
{
    # Use internal CA for local domains
    local_certs
}

# Add one entry for each service with matching port number
vault.fritz.box {
    reverse_proxy 127.0.0.1:10002 {
        header_up Host {host}
        header_up X-Real-IP {remote}
    }
}
```

The root certificate will be in
`home/caddy/.local/share/caddy/pki/authorities/local/root.crt`, which you
should distribute to all your devices.

Finally, add a DNS entry for `vault.fritz.box` pointing at the host.

# Automating the DNS update

This can be automated as well. It's a bit dependent on your environment, but
this works for a FritxBox.

Drop a unit at `/etc/systemd/system/dns-update.service`:

```ini
[Unit]
Description=Update DNS entries for self-hosted services
After=caddy.service
BindsTo=caddy.service
PartOf=caddy.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for name in $(/opt/container/list-services.sh); do /opt/container/dns-update.sh "$name.fritz.box"; done'

[Install]
WantedBy=caddy.service
```

Then enable it so it runs whenever caddy starts or restarts:

```console
systemctl daemon-reload
systemctl enable --now dns-update.service
```

`PartOf=caddy.service` propagates stop/restart from caddy, and
`WantedBy=caddy.service` pulls the unit in whenever caddy is started.

Here, `dns-update.sh` is a script like this:

```bash
#!/bin/bash
hostname="$1"
ip="192.168.1.XXX"
TTL=3600
DNS_SERVER=192.168.178.1

nsupdate <<EOF
server "${DNS_SERVER}"
update delete "${hostname}" A
update add "${hostname}" "${TTL}" A "${ip}"
send
EOF

if [ $? -eq 0 ]; then
    echo "$(date): Updated $hostname to $ip"
else
    echo "$(date): Failed to update $hostname" >&2
    return 1
fi
```
