#!/usr/bin/env bash
#
# macOS one-shot installer for the DSH frpc tunnel.
# Run as the normal user; sudo is used only for installing the binary.
#
# Usage:
#   FRP_SERVER_ADDR=111.230.57.237 FRP_TOKEN="FRP_TOKEN" bash install-frpc.sh
#
# Environment variables:
#   FRP_VERSION         frp release            (default: 0.71.0)
#   FRP_DOWNLOAD_PROXY  GitHub proxy base URL  (default: https://gh.djj45.com)
#   FRP_SERVER_ADDR     CVM public IP          (required)
#   FRP_TOKEN           frps auth token        (required)
#   FRP_SERVER_PORT     7000                   (default)
#   FRP_REMOTE_PORT     18081 (dsh-mac)        (default)
#   FRP_LOCAL_PORT      3080                   (default)
#   FRP_PROXY_NAME      dsh-mac                (default)
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this script as the normal macOS user (sudo will be used where needed)." >&2
  exit 1
fi

FRP_VERSION="${FRP_VERSION:-0.71.0}"
FRP_DOWNLOAD_PROXY="${FRP_DOWNLOAD_PROXY:-https://gh.djj45.com}"
FRP_SERVER_ADDR="${FRP_SERVER_ADDR:-}"
FRP_TOKEN="${FRP_TOKEN:-}"
FRP_SERVER_PORT="${FRP_SERVER_PORT:-7000}"
FRP_REMOTE_PORT="${FRP_REMOTE_PORT:-18081}"
FRP_LOCAL_PORT="${FRP_LOCAL_PORT:-3080}"
FRP_PROXY_NAME="${FRP_PROXY_NAME:-dsh-mac}"

if [ -z "$FRP_SERVER_ADDR" ] || [ -z "$FRP_TOKEN" ]; then
  echo "FRP_SERVER_ADDR and FRP_TOKEN are required." >&2
  exit 1
fi

case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=amd64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

TARBALL="frp_${FRP_VERSION}_darwin_${ARCH}.tar.gz"
URL="${FRP_DOWNLOAD_PROXY}/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${TARBALL}"

echo "==> Downloading $URL"
cd /tmp
curl -fsSL --retry 3 -m 300 -o "$TARBALL" "$URL"
tar xzf "$TARBALL"

echo "==> Installing frpc binary"
sudo mkdir -p /usr/local/bin
sudo cp -f "frp_${FRP_VERSION}_darwin_${ARCH}/frpc" /usr/local/bin/frpc
sudo chmod 755 /usr/local/bin/frpc

echo "==> Writing config"
CONFIG_DIR="$HOME/.dsh-frpc"
mkdir -p "$CONFIG_DIR"
CONFIG_PATH="$CONFIG_DIR/frpc.toml"
cat > "$CONFIG_PATH" <<EOF
serverAddr = "$FRP_SERVER_ADDR"
serverPort = $FRP_SERVER_PORT
auth.method = "token"
auth.token = "$FRP_TOKEN"
transport.tls.enable = true
log.to = "/tmp/frpc-mac.log"
log.level = "info"
log.maxDays = 7

[[proxies]]
name = "$FRP_PROXY_NAME"
type = "tcp"
localIP = "127.0.0.1"
localPort = $FRP_LOCAL_PORT
remotePort = $FRP_REMOTE_PORT
EOF
chmod 600 "$CONFIG_PATH"

echo "==> Installing LaunchAgent"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/com.dsh.frpc.plist"
mkdir -p "$PLIST_DIR"
sed "s|__CONFIG_PATH__|$CONFIG_PATH|g" "$SCRIPT_DIR/com.dsh.frpc.plist" > "$PLIST_PATH"
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo
echo "==> Done."
echo "    config : $CONFIG_PATH"
echo "    log    : /tmp/frpc-mac.log"
echo "    Check log for 'login to server success' and 'start proxy success'."
