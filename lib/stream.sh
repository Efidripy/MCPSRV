#!/usr/bin/env bash
set -euo pipefail
choose_port() {
  local conf="$1"
  for p in 7443 8443 9443 10443 11443 12443 13443; do
    if ! grep -q ":$p;" "$conf" 2>/dev/null; then echo "$p"; return; fi
  done
  return 1
}
