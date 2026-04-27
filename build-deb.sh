#!/bin/bash
# Build an anchorage Debian package.
# Run from the repository root. Requires dpkg-deb and gzip.

set -euo pipefail

PACKAGE=anchorage
ARCH=all
MAINTAINER="${MAINTAINER:-anchorage contributors}"
DESCRIPTION_SHORT="Container self-hosting framework using podman, caddy, and systemd"

# Derive version from git tag, fall back to 0.1.0
VERSION=$(git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo "0.1.0")
# dpkg versions must not contain hyphens except as epoch/revision separator
VERSION=${VERSION//-/.}

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR=$(mktemp -d)
PKG_DIR="$BUILD_DIR/${PACKAGE}_${VERSION}_${ARCH}"

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

echo "Building $PACKAGE $VERSION ..."

# ---------------------------------------------------------------------------
# Directory structure
# ---------------------------------------------------------------------------
mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/usr/lib/anchorage" \
  "$PKG_DIR/usr/share/man/man7" \
  "$PKG_DIR/usr/share/doc/anchorage" \
  "$PKG_DIR/etc/anchorage" \
  "$PKG_DIR/etc/caddy/anchorage" \
  "$PKG_DIR/etc/systemd/system" \
  "$PKG_DIR/var/lib/anchorage"

# ---------------------------------------------------------------------------
# Scripts and units
# ---------------------------------------------------------------------------
install -m 755 "$REPO_ROOT/gen-caddyfile.py"  "$PKG_DIR/usr/lib/anchorage/gen-caddyfile.py"
install -m 755 "$REPO_ROOT/run.sh"             "$PKG_DIR/usr/lib/anchorage/run.sh"
install -m 755 "$REPO_ROOT/dns-update.sh"      "$PKG_DIR/usr/lib/anchorage/dns-update.sh"

install -m 644 "$REPO_ROOT/anchorage.conf"                    "$PKG_DIR/etc/anchorage/anchorage.conf"
install -m 644 "$REPO_ROOT/container@.service"                "$PKG_DIR/etc/systemd/system/"
install -m 644 "$REPO_ROOT/anchorage-gen-caddyfile.service"   "$PKG_DIR/etc/systemd/system/"
install -m 644 "$REPO_ROOT/dns-update.service"                "$PKG_DIR/etc/systemd/system/"

# ---------------------------------------------------------------------------
# Man page
# ---------------------------------------------------------------------------
gzip -9 -c "$REPO_ROOT/man/anchorage.7" > "$PKG_DIR/usr/share/man/man7/anchorage.7.gz"

# ---------------------------------------------------------------------------
# conffiles -- dpkg will prompt before overwriting these on upgrade
# ---------------------------------------------------------------------------
cat > "$PKG_DIR/DEBIAN/conffiles" <<'EOF'
/etc/anchorage/anchorage.conf
EOF

# ---------------------------------------------------------------------------
# Copyright file
# ---------------------------------------------------------------------------
cat > "$PKG_DIR/usr/share/doc/anchorage/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/

Files: *
License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
EOF

# ---------------------------------------------------------------------------
# DEBIAN/control
# ---------------------------------------------------------------------------
cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Depends: podman, podman-compose, caddy, python3, python3-yaml, systemd, bind9-dnsutils
Recommends: wireguard-tools
Description: $DESCRIPTION_SHORT
 Anchorage ties together podman, caddy, and systemd to make self-hosting
 container applications straightforward and reproducible on a home server
 or private VPS.
 .
 Features:
  - Per-service podman-compose lifecycle via a systemd template unit
  - Automatic TLS via Caddy's internal CA with local_certs
  - Caddyfile generated automatically from docker-compose labels
  - Optional dynamic DNS registration for local network hostnames
  - Rootless container execution under a dedicated system user
EOF

# ---------------------------------------------------------------------------
# DEBIAN/postinst
# ---------------------------------------------------------------------------
cat > "$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e

ANCHORAGE_USER=anchorage
ANCHORAGE_HOME=/var/lib/anchorage
ANCHORAGE_DIR=/var/lib/anchorage
CADDYFILE=/etc/caddy/Caddyfile
IMPORT_MARKER="import /etc/caddy/anchorage/*"
IMPORT_LINE="${IMPORT_MARKER}  # inserted by anchorage"

# Create system user for rootless podman
if ! id -u "$ANCHORAGE_USER" >/dev/null 2>&1; then
  useradd \
    --system \
    --home-dir "$ANCHORAGE_HOME" \
    --create-home \
    --shell /bin/bash \
    --comment "Anchorage container runtime" \
    "$ANCHORAGE_USER"
fi

# Ensure home dir exists with correct ownership even if user pre-existed
install -d -m 750 -o "$ANCHORAGE_USER" -g "$ANCHORAGE_USER" "$ANCHORAGE_HOME"

# Configure subuid/subgid for rootless podman (65536 IDs starting at 100000)
if ! grep -q "^${ANCHORAGE_USER}:" /etc/subuid 2>/dev/null; then
  echo "${ANCHORAGE_USER}:100000:65536" >> /etc/subuid
fi
if ! grep -q "^${ANCHORAGE_USER}:" /etc/subgid 2>/dev/null; then
  echo "${ANCHORAGE_USER}:100000:65536" >> /etc/subgid
fi

# Linger: keep the user's systemd session alive across logins
loginctl enable-linger "$ANCHORAGE_USER" 2>/dev/null || true

# Create container root dir owned by anchorage
install -d -m 755 -o "$ANCHORAGE_USER" -g "$ANCHORAGE_USER" "$ANCHORAGE_DIR"

# Ensure Caddyfile imports anchorage snippets
install -d -m 755 /etc/caddy/anchorage
if [ -f "$CADDYFILE" ]; then
  if ! grep -qF "$IMPORT_MARKER" "$CADDYFILE"; then
    printf '\n%s\n' "$IMPORT_LINE" >> "$CADDYFILE"
  fi
else
  printf '%s\n' "$IMPORT_LINE" > "$CADDYFILE"
fi

# Reload systemd so new units are visible
systemctl daemon-reload

cat <<MSG

anchorage installed successfully.

Next steps:
  1. Edit /etc/anchorage/anchorage.conf -- set DOMAIN_SUFFIX, and optionally
     IP and DNS_SERVER if you want automatic DNS registration.
  2. Add services under /var/lib/anchorage/<name>/docker-compose.yml.
  3. Enable caddy:  systemctl enable --now caddy
  4. Add a service and apply:
       systemctl enable --now container@<name>.service
       systemctl start anchorage-gen-caddyfile.service

See man anchorage(7) for full documentation.
MSG

EOF
chmod 755 "$PKG_DIR/DEBIAN/postinst"

# ---------------------------------------------------------------------------
# DEBIAN/prerm
# ---------------------------------------------------------------------------
cat > "$PKG_DIR/DEBIAN/prerm" <<'EOF'
#!/bin/bash
set -e

# Stop all anchorage-managed services gracefully before removal.
# Data under /var/lib/anchorage is intentionally preserved.

systemctl stop 'container@*.service' 2>/dev/null || true
systemctl stop anchorage-gen-caddyfile.service dns-update.service 2>/dev/null || true
systemctl disable anchorage-gen-caddyfile.service dns-update.service 2>/dev/null || true

EOF
chmod 755 "$PKG_DIR/DEBIAN/prerm"

# ---------------------------------------------------------------------------
# DEBIAN/postrm
# ---------------------------------------------------------------------------
cat > "$PKG_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/bash
set -e

if [ "$1" = "purge" ]; then
  # Remove anchorage import line from Caddyfile (leave the rest intact)
  if [ -f /etc/caddy/Caddyfile ]; then
    sed -i '\|^import /etc/caddy/anchorage/|d' /etc/caddy/Caddyfile
  fi
  rm -rf /etc/caddy/anchorage

  # Disable linger and remove system user; preserve /var/lib/anchorage data
  loginctl disable-linger anchorage 2>/dev/null || true
  userdel anchorage 2>/dev/null || true

  systemctl daemon-reload
fi

EOF
chmod 755 "$PKG_DIR/DEBIAN/postrm"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
OUTPUT="${REPO_ROOT}/${PACKAGE}_${VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$PKG_DIR" "$OUTPUT"

echo "Package written to: $OUTPUT"
echo "Install with:  apt install ./$OUTPUT"
