#!/usr/bin/env bash
#
# Install frps on the CVM and run it as a systemd service.
# Usage:
#   FRP_TOKEN="$(openssl rand -hex 32)" sudo -E bash install-frps.sh
#
# Environment variables:
#   FRP_VERSION         frp release to install          (default: 0.71.0)
#   FRP_DOWNLOAD_PROXY  GitHub proxy base URL           (default: https://gh.djj45.com)
#   FRP_TOKEN           frps/frpc auth token            (default: generated with openssl)
#   INSTALL_DIR         install directory              (default: /usr/local/frp)
#   ALLOW_PORTS_START   first allowed remote port      (default: 18080)
#   ALLOW_PORTS_END     last allowed remote port       (default: 18081)
set -euo pipefail

FRP_VERSION="${FRP_VERSION:-0.71.0}"
FRP_DOWNLOAD_PROXY="${FRP_DOWNLOAD_PROXY:-https://gh.djj45.com}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/frp}"
ALLOW_PORTS_START="${ALLOW_PORTS_START:-18080}"
ALLOW_PORTS_END="${ALLOW_PORTS_END:-18081}"
FRP_TOKEN="${FRP_TOKEN:-}"

if [ -z "$FRP_TOKEN" ]; then
  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required to generate a token" >&2
    exit 1
  fi
  FRP_TOKEN="$(openssl rand -hex 32)"
fi

TARBALL="frp_${FRP_VERSION}_linux_amd64.tar.gz"
URL="${FRP_DOWNLOAD_PROXY}/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${TARBALL}"

echo "==> Downloading frp v${FRP_VERSION} via ${FRP_DOWNLOAD_PROXY}"
cd /tmp
curl -fsSL --retry 3 -m 300 -o "$TARBALL" "$URL"
tar xzf "$TARBALL"

echo "==> Installing binaries to ${INSTALL_DIR}"
sudo mkdir -p "$INSTALL_DIR"
sudo cp -f "frp_${FRP_VERSION}_linux_amd64/frps" "$INSTALL_DIR/frps"
sudo cp -f "frp_${FRP_VERSION}_linux_amd64/frpc" "$INSTALL_DIR/frpc"
sudo chmod 755 "$INSTALL_DIR/frps" "$INSTALL_DIR/frpc"

echo "==> Writing frps.toml"
sudo tee "$INSTALL_DIR/frps.toml" >/dev/null <<EOF
bindAddr = "0.0.0.0"
bindPort = 7000
proxyBindAddr = "127.0.0.1"
auth.method = "token"
auth.token = "$FRP_TOKEN"
transport.tls.force = true
allowPorts = [{ start = $ALLOW_PORTS_START, end = $ALLOW_PORTS_END }]
EOF
sudo chmod 600 "$INSTALL_DIR/frps.toml"

echo "==> Installing systemd service"
sudo tee /etc/systemd/system/frps.service >/dev/null <<EOF
[Unit]
Description=frps
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/frps -c ${INSTALL_DIR}/frps.toml
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now frps
sleep 2

echo "==> Status"
sudo systemctl status frps --no-pager | head -15 || true
sudo ss -lntp | grep ':7000' || true

echo
echo "==> Done. frps config: ${INSTALL_DIR}/frps.toml"
echo "FRP_TOKEN=${FRP_TOKEN}"
echo "Keep this token secret; it must match every frpc client."
