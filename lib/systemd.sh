#!/usr/bin/env bash
set -euo pipefail
install_unit() {
  local src="$1" dst="$2"
  cp "$src" "$dst"
  systemctl daemon-reload
}
