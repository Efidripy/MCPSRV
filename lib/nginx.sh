#!/usr/bin/env bash
set -euo pipefail
ensure_nginx(){
  command -v nginx >/dev/null 2>&1 && return 0
  apt-get update
  apt-get install -y nginx
}
