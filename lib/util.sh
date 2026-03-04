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
    python3 - "$dst" "$k" "$v" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
text = path.read_text()
text = text.replace("{{" + key + "}}", value)
path.write_text(text)
PY
    shift 2
  done
}
