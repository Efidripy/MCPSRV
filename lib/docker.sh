#!/usr/bin/env bash
set -euo pipefail
ensure_docker() {
  command -v docker >/dev/null 2>&1 && return 0
  apt-get update
  apt-get install -y docker.io
  systemctl enable --now docker
}
