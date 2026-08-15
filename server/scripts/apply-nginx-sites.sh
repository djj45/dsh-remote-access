#!/usr/bin/env bash
#
# Install the two DSH Nginx vhosts from server/nginx into a Debian/Ubuntu
# style nginx layout (sites-available + sites-enabled) and reload nginx.
#
# Before running: edit server/nginx/*.conf when your domain or certificate
# paths differ from dsh.djj45.cn / dsh-mac.djj45.cn.
#
# Usage:
#   sudo bash apply-nginx-sites.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_DIR="${SCRIPT_DIR}/../nginx"

for site in dsh.djj45.cn dsh-mac.djj45.cn; do
  src="${NGINX_DIR}/${site}.conf"
  if [ ! -f "$src" ]; then
    echo "missing ${src}" >&2
    exit 1
  fi
  echo "==> installing ${site}"
  sudo cp -f "$src" "/etc/nginx/sites-available/${site}"
  sudo ln -sfn "/etc/nginx/sites-available/${site}" "/etc/nginx/sites-enabled/${site}"
done

echo "==> nginx config test"
sudo nginx -t

echo "==> reload nginx"
sudo systemctl reload nginx

echo "==> enabled sites"
ls -l /etc/nginx/sites-enabled/
