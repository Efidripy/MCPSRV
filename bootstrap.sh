#!/usr/bin/env bash
set -euo pipefail

REPO_TARBALL_URL="${MCPSRV_REPO_TARBALL_URL:-https://codeload.github.com/Efidripy/MCPSRV/tar.gz/refs/heads/main}"
WORKDIR="$(mktemp -d /tmp/mcpsrv-bootstrap-XXXXXX)"
ARCHIVE="$WORKDIR/repo.tar.gz"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if command -v curl >/dev/null 2>&1; then
  curl --retry 3 --retry-delay 1 -fsSL "$REPO_TARBALL_URL" -o "$ARCHIVE"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$ARCHIVE" "$REPO_TARBALL_URL"
else
  echo "[error] Neither curl nor wget is available." >&2
  exit 1
fi

tar -xzf "$ARCHIVE" -C "$WORKDIR"
ROOT="$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d | head -n1)"

if [[ -z "$ROOT" || ! -f "$ROOT/install.sh" ]]; then
  echo "[error] Cannot find install.sh in extracted archive." >&2
  exit 1
fi

chmod +x "$ROOT/install.sh"
exec "$ROOT/install.sh" "$@"
