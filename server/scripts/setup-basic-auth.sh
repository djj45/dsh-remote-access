#!/usr/bin/env bash
#
# Generate the Nginx Basic Auth password file used to protect DSH.
# DSH has no login of its own, so this layer is mandatory.
#
# Usage:
#   sudo bash setup-basic-auth.sh
#
# Environment variables:
#   BASIC_AUTH_USER      username                        (default: dsh)
#   BASIC_AUTH_PASSWORD  password                        (default: generated 24 hex chars)
#   BASIC_AUTH_FILE      destination file               (default: /etc/nginx/.htpasswd_dsh)
set -euo pipefail

USERNAME="${BASIC_AUTH_USER:-dsh}"
PASSWORD="${BASIC_AUTH_PASSWORD:-}"
FILE="${BASIC_AUTH_FILE:-/etc/nginx/.htpasswd_dsh}"

if [ -z "$PASSWORD" ]; then
  PASSWORD="$(openssl rand -hex 12)"
fi

HASH="$(openssl passwd -apr1 "$PASSWORD")"
printf '%s:%s\n' "$USERNAME" "$HASH" | sudo tee "$FILE" >/dev/null
sudo chown root:www-data "$FILE"
sudo chmod 640 "$FILE"

echo "BASIC_AUTH_USER=${USERNAME}"
echo "BASIC_AUTH_PASSWORD=${PASSWORD}"
echo "BASIC_AUTH_FILE=${FILE}"
