#!/usr/bin/env bash
set -euo pipefail
write_report() {
  local report="$1"
  cat > "$report"
}
