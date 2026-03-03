#!/usr/bin/env bash
set -euo pipefail

rand_name() { tr -dc 'a-z0-9' </dev/urandom | head -c "${1:-10}"; }
backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
}
render_template() {
  local src="$1" dst="$2"
  shift 2
  cp "$src" "$dst"
  while (($#)); do
    local k="$1" v="$2"
    sed -i "s|{{$k}}|$v|g" "$dst"
    shift 2
  done
}
