#!/usr/bin/env bash
set -euo pipefail

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  C_RESET="$(tput sgr0)"
  C_RED="$(tput setaf 1)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"
  C_BOLD="$(tput bold)"
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""
fi

log_info() { printf "%b\n" "${C_BLUE}ℹ️  [info]${C_RESET} $*"; }
log_warn() { printf "%b\n" "${C_YELLOW}⚠️  [warn]${C_RESET} $*"; }
log_error() { printf "%b\n" "${C_RED}❌ [error]${C_RESET} $*" >&2; }
log_ok()   { printf "%b\n" "${C_GREEN}✅ [ok]${C_RESET} $*"; }
log_step() { printf "\n%b\n" "${C_BOLD}${C_BLUE}▶ $*${C_RESET}"; }

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
