#!/usr/bin/env bash
set -euo pipefail
issue_cert_or_fallback() {
  local domain="$1" email="$2"
  mkdir -p /var/www/letsencrypt /etc/ssl/localcerts
  if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" && -f "/etc/letsencrypt/live/$domain/privkey.pem" ]]; then
    echo "le"
    return 0
  fi
  if certbot certonly --webroot -w /var/www/letsencrypt -d "$domain" --agree-tos -m "$email" --non-interactive; then
    echo "le"
    return 0
  fi
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "/etc/ssl/localcerts/$domain.key" \
    -out "/etc/ssl/localcerts/$domain.crt" \
    -subj "/CN=$domain" >/dev/null 2>&1
  echo "selfsigned"
}
