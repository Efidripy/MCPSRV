#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Bootstrap mode: if only install.sh is downloaded, fetch full repository archive and re-exec.
if [[ ! -f "$ROOT_DIR/lib/util.sh" ]]; then
  echo "[info] Local lib/ not found next to install.sh. Bootstrapping full repository..."
  BOOTSTRAP_URL="${MCPSRV_REPO_TARBALL_URL:-https://codeload.github.com/Efidripy/MCPSRV/tar.gz/refs/heads/main}"
  BOOTSTRAP_DIR="$(mktemp -d /tmp/mcpsrv-bootstrap-XXXXXX)"
  BOOTSTRAP_ARCHIVE="$BOOTSTRAP_DIR/repo.tar.gz"

  download_bootstrap() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
      curl --retry 3 --retry-delay 1 -fsSL "$url" -o "$BOOTSTRAP_ARCHIVE"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$BOOTSTRAP_ARCHIVE" "$url"
    else
      echo "[error] Neither curl nor wget is available for bootstrap download." >&2
      return 1
    fi
  }

  if ! download_bootstrap "$BOOTSTRAP_URL"; then
    echo "[error] Failed to download bootstrap archive: $BOOTSTRAP_URL" >&2
    exit 1
  fi

  if ! tar -xzf "$BOOTSTRAP_ARCHIVE" -C "$BOOTSTRAP_DIR"; then
    echo "[error] Failed to extract bootstrap archive (not a valid tar.gz?)." >&2
    exit 1
  fi

  BOOTSTRAP_ROOT="$(find "$BOOTSTRAP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$BOOTSTRAP_ROOT" && -f "$BOOTSTRAP_ROOT/install.sh" && -f "$BOOTSTRAP_ROOT/lib/util.sh" ]] || {
    echo "[error] Downloaded archive does not contain expected repository structure." >&2
    exit 1
  }

  echo "[info] Re-running installer from: $BOOTSTRAP_ROOT"
  chmod +x "$BOOTSTRAP_ROOT/install.sh"
  exec "$BOOTSTRAP_ROOT/install.sh" "$@"
fi

source "$ROOT_DIR/lib/util.sh"
source "$ROOT_DIR/lib/docker.sh"
source "$ROOT_DIR/lib/systemd.sh"
source "$ROOT_DIR/lib/nginx.sh"
source "$ROOT_DIR/lib/stream.sh"
source "$ROOT_DIR/lib/letsencrypt.sh"

DOMAIN=""; PATH_PREFIX=""; EMAIL=""; GITHUB_USER=""
BACKEND_PORT="21582"; STREAM_CONF="/etc/nginx/stream/stream.conf"; HTTP80_CONF="/etc/nginx/sites-available/80.conf"
WORKSPACES_DIR=""; INSTALL_DIR=""; MODE="update"; UPDATE_IMAGE=""; ASSUME_YES="no"
STREAM_CONF_SET="no"; HTTP80_CONF_SET="no"

ask_value() {
  local var_name="$1" prompt="$2"
  local cur="${!var_name:-}"
  [[ -n "$cur" ]] && return 0

  if [[ "$ASSUME_YES" == "yes" ]]; then
    echo "[error] Missing required argument: $var_name" >&2
    exit 1
  fi

  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "$prompt: " value
  done
  printf -v "$var_name" '%s' "$value"
}

normalize_path_prefix() {
  [[ "$PATH_PREFIX" =~ ^/.+/$ ]] && return 0

  local generated="/$(rand_name $((RANDOM % 5 + 8)))/"
  if [[ "$ASSUME_YES" == "yes" ]]; then
    PATH_PREFIX="$generated"
    echo "[warn] Invalid or missing --path; generated random path: $PATH_PREFIX"
    return 0
  fi

  echo "[warn] Path must match /.../."
  read -r -p "Enter path in format /.../ (leave empty for random $generated): " entered
  if [[ -n "$entered" && "$entered" =~ ^/.+/$ ]]; then
    PATH_PREFIX="$entered"
  else
    [[ -n "$entered" ]] && echo "[warn] Invalid entered path; using random: $generated"
    PATH_PREFIX="$generated"
  fi
}

resolve_stream_conf() {
  [[ "$STREAM_CONF_SET" == "yes" ]] && return 0
  local candidates=(
    "/etc/nginx/stream/stream.conf"
    "/etc/nginx/stream-enabled/stream.conf"
  )
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      STREAM_CONF="$c"
      return 0
    fi
  done
  STREAM_CONF="${candidates[0]}"
}

resolve_http80_conf() {
  [[ "$HTTP80_CONF_SET" == "yes" ]] && return 0
  local candidates=(
    "/etc/nginx/sites-available/80.conf"
    "/etc/nginx/conf.d/80.conf"
  )
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      HTTP80_CONF="$c"
      return 0
    fi
  done
  HTTP80_CONF="${candidates[0]}"
}

ensure_http80_conf_exists() {
  [[ -f "$HTTP80_CONF" ]] && return 0
  mkdir -p "$(dirname "$HTTP80_CONF")"
  cat > "$HTTP80_CONF" <<'HC'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    return 301 https://$host$request_uri;
}
HC
}

insert_acme_location() {
  grep -q '/.well-known/acme-challenge/' "$HTTP80_CONF" && return 0

  local snippet tmp snip_oneline
  snippet="$(cat "$ROOT_DIR/templates/nginx_http80_acme_snippet.conf")"
  snip_oneline="$(printf '%s' "$snippet" | sed ':a;N;$!ba;s/\n/\\n/g')"
  tmp="$(mktemp)"

  awk -v snip="$snip_oneline" '
    /return 301 https/ && !done {
      gsub(/\\n/,"\n",snip)
      print snip
      done=1
    }
    {print}
    END {
      if (!done) {
        gsub(/\\n/,"\n",snip)
        print snip
      }
    }
  ' "$HTTP80_CONF" > "$tmp"
  mv "$tmp" "$HTTP80_CONF"
}


ensure_system_tools() {
  local missing=()
  command -v python3 >/dev/null 2>&1 || missing+=(python3)
  command -v pip3 >/dev/null 2>&1 || missing+=(python3-pip)
  command -v git >/dev/null 2>&1 || missing+=(git)
  command -v openssl >/dev/null 2>&1 || missing+=(openssl)
  command -v certbot >/dev/null 2>&1 || missing+=(certbot)
  command -v tar >/dev/null 2>&1 || missing+=(tar)
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || missing+=(curl)

  if (( ${#missing[@]} > 0 )); then
    echo "[info] Installing missing system packages: ${missing[*]}"
    apt-get update
    apt-get install -y "${missing[@]}"
  fi

  if ! python3 -m venv --help >/dev/null 2>&1; then
    echo "[info] Installing python3-venv (required for virtualenv setup)"
    apt-get update
    apt-get install -y python3-venv
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2;;
    --path) PATH_PREFIX="$2"; shift 2;;
    --email) EMAIL="$2"; shift 2;;
    --github-user) GITHUB_USER="$2"; shift 2;;
    --backend-port) BACKEND_PORT="$2"; shift 2;;
    --stream-conf) STREAM_CONF="$2"; STREAM_CONF_SET="yes"; shift 2;;
    --http80-conf) HTTP80_CONF="$2"; HTTP80_CONF_SET="yes"; shift 2;;
    --workspaces-dir) WORKSPACES_DIR="$2"; shift 2;;
    --install-dir) INSTALL_DIR="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --update-image) UPDATE_IMAGE="$2"; shift 2;;
    --assume-yes) ASSUME_YES="yes"; shift;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$DOMAIN" || -z "$EMAIL" || -z "$GITHUB_USER" ]]; then
  echo "[info] Starting interactive input for missing required flags"
fi
ask_value DOMAIN "domain"
ask_value EMAIL "email"
ask_value GITHUB_USER "github-user"
normalize_path_prefix
[[ "$MODE" =~ ^(keep|update|add)$ ]] || { echo "--mode must be keep|update|add"; exit 1; }

if [[ -z "$INSTALL_DIR" ]]; then
  INSTALL_DIR="/opt/MCPSRV"
  echo "[info] Default install dir: $INSTALL_DIR"
fi
if [[ -z "$WORKSPACES_DIR" ]]; then
  WORKSPACES_DIR="/opt/MCPSRV/workspaces"
  echo "[info] Default workspaces dir: $WORKSPACES_DIR"
fi

ensure_nginx
ensure_docker
ensure_system_tools
resolve_stream_conf
resolve_http80_conf
ensure_http80_conf_exists
id -u mcp >/dev/null 2>&1 || useradd --system --home /nonexistent --shell /usr/sbin/nologin mcp
usermod -aG docker mcp || true

mkdir -p "$INSTALL_DIR" "$WORKSPACES_DIR" /var/www/letsencrypt
chown root:mcp "$INSTALL_DIR" && chmod 750 "$INSTALL_DIR"
chown mcp:mcp "$WORKSPACES_DIR"

if [[ ! -f "$STREAM_CONF" ]]; then
  mkdir -p "$(dirname "$STREAM_CONF")"
  cat > "$STREAM_CONF" <<'SC'
map $ssl_preread_server_name $sni_name {
    default default_backend;
}
SC
fi
backup_file "$STREAM_CONF"

if grep -qE "^\s*${DOMAIN}\s+" "$STREAM_CONF"; then
  UPSTREAM_NAME="$(awk -v d="$DOMAIN" '$1==d{print $2}' "$STREAM_CONF" | tr -d ';' | head -n1)"
  HTTPS_PORT="$(awk -v u="$UPSTREAM_NAME" '$1=="upstream"&&$2==u{getline; gsub(/[^0-9]/, "", $0); print $0}' "$STREAM_CONF" | head -n1)"
else
  HTTPS_PORT="$(choose_port "$STREAM_CONF")"
  UPSTREAM_NAME="mcp_${DOMAIN//./_}"
  awk -v d="$DOMAIN" -v u="$UPSTREAM_NAME" '
    /map \$ssl_preread_server_name \$sni_name \{/ {print; inmap=1; next}
    inmap && /^}/ {print "    " d " " u ";"; inmap=0}
    {print}
  ' "$STREAM_CONF" > "$STREAM_CONF.new"
  mv "$STREAM_CONF.new" "$STREAM_CONF"
  echo -e "\nupstream $UPSTREAM_NAME {\n    server 127.0.0.1:$HTTPS_PORT;\n}" >> "$STREAM_CONF"
fi

backup_file "$HTTP80_CONF"
insert_acme_location

CERT_KIND="$(issue_cert_or_fallback "$DOMAIN" "$EMAIL")"
if [[ "$CERT_KIND" == "le" ]]; then
  CERT_FULLCHAIN="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  CERT_PRIVKEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
else
  CERT_FULLCHAIN="/etc/ssl/localcerts/$DOMAIN.crt"
  CERT_PRIVKEY="/etc/ssl/localcerts/$DOMAIN.key"
fi

DOMAIN_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
LOCATION_BLOCK="$(sed "s|{{PATH}}|$PATH_PREFIX|g; s|{{BACKEND_PORT}}|$BACKEND_PORT|g" "$ROOT_DIR/templates/nginx_location.conf.tmpl")"
if [[ ! -f "$DOMAIN_CONF" ]]; then
  tmp="$(mktemp)"
  render_template "$ROOT_DIR/templates/nginx_domain.conf.tmpl" "$tmp" \
    DOMAIN "$DOMAIN" HTTPS_PORT "$HTTPS_PORT" CERT_FULLCHAIN "$CERT_FULLCHAIN" CERT_PRIVKEY "$CERT_PRIVKEY" DOMAIN_REGEX "${DOMAIN//./\\.}" LOCATION_BLOCK "$LOCATION_BLOCK"
  mv "$tmp" "$DOMAIN_CONF"
else
  backup_file "$DOMAIN_CONF"
  if [[ "$MODE" == "keep" ]]; then
    :
  elif grep -q "location $PATH_PREFIX" "$DOMAIN_CONF"; then
    [[ "$MODE" == "add" ]] || perl -0777 -i -pe "s#location \Q$PATH_PREFIX\E \{.*?\n\}#$LOCATION_BLOCK#s" "$DOMAIN_CONF"
  else
    python3 - "$DOMAIN_CONF" "$LOCATION_BLOCK" <<'PYLOC'
import sys
from pathlib import Path

path = Path(sys.argv[1])
location_block = sys.argv[2]
text = path.read_text()
needle = "proxy_intercept_errors on;"
if needle in text:
    text = text.replace(needle, needle + "\n\n" + location_block + "\n", 1)
else:
    text = text.rstrip() + "\n\n" + location_block + "\n"
path.write_text(text)
PYLOC
  fi
  python3 - "$DOMAIN_CONF" "$CERT_FULLCHAIN" "$CERT_PRIVKEY" <<'PYCERT'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
fullchain = sys.argv[2]
privkey = sys.argv[3]
text = path.read_text()
text = re.sub(r"^\s*ssl_certificate\s+.*;$", f"    ssl_certificate {fullchain};", text, flags=re.M)
text = re.sub(r"^\s*ssl_certificate_key\s+.*;$", f"    ssl_certificate_key {privkey};", text, flags=re.M)
path.write_text(text)
PYCERT
fi
ln -sf "$DOMAIN_CONF" "/etc/nginx/sites-enabled/$DOMAIN.conf"

TOKEN_FILE="$INSTALL_DIR/token.txt"
if [[ ! -f "$TOKEN_FILE" ]]; then openssl rand -hex 32 > "$TOKEN_FILE"; fi
TOKEN="$(cat "$TOKEN_FILE")"
chmod 640 "$TOKEN_FILE"; chown root:mcp "$TOKEN_FILE"

cp -a app "$INSTALL_DIR/"
if ! python3 -m venv "$INSTALL_DIR/.venv"; then
  echo "[warn] python3-venv/ensurepip missing; installing python3-venv and retrying"
  apt-get update
  apt-get install -y python3-venv
  python3 -m venv "$INSTALL_DIR/.venv"
fi
"$INSTALL_DIR/.venv/bin/pip" install -r "$INSTALL_DIR/app/requirements.txt" >/dev/null

svc_tmp="$(mktemp)"
render_template "$ROOT_DIR/templates/mcp-runner.service.tmpl" "$svc_tmp" \
  INSTALL_DIR "$INSTALL_DIR" TOKEN "$TOKEN" GITHUB_USER "$GITHUB_USER" WORKSPACES_DIR "$WORKSPACES_DIR" BACKEND_PORT "$BACKEND_PORT"
install_unit "$svc_tmp" /etc/systemd/system/mcp-runner.service

cl_tmp="$(mktemp)"
render_template "$ROOT_DIR/templates/cleanup.service.tmpl" "$cl_tmp" WORKSPACES_DIR "$WORKSPACES_DIR"
install_unit "$cl_tmp" /etc/systemd/system/mcp-workspace-cleanup.service
cp "$ROOT_DIR/templates/cleanup.timer.tmpl" /etc/systemd/system/mcp-workspace-cleanup.timer
systemctl daemon-reload
systemctl enable --now mcp-runner mcp-workspace-cleanup.timer

if [[ -z "$UPDATE_IMAGE" ]]; then UPDATE_IMAGE="yes"; fi
if [[ "$UPDATE_IMAGE" == "yes" ]]; then docker build -t mcp-runner-base:latest -f "$ROOT_DIR/templates/Dockerfile.base" "$ROOT_DIR"; fi

COD="[mcp_servers.runner]
url = \"https://$DOMAIN${PATH_PREFIX}mcp\"
bearer_token_env_var = \"MCP_RUNNER_TOKEN\""
printf "%s\n" "$COD" > "$INSTALL_DIR/codex_config.toml"
chmod 640 "$INSTALL_DIR/codex_config.toml" && chown root:mcp "$INSTALL_DIR/codex_config.toml"

REPORT="$INSTALL_DIR/install-report.md"
cat > "$REPORT" <<R
# MCP Runner install report

- Domain: $DOMAIN
- Path: $PATH_PREFIX
- Stream route: $DOMAIN -> $UPSTREAM_NAME -> $HTTPS_PORT
- Cert mode: $CERT_KIND
- Backend: 127.0.0.1:$BACKEND_PORT
- Stream conf: $STREAM_CONF
- HTTP:80 conf: $HTTP80_CONF
- Install dir: $INSTALL_DIR
- Workspaces dir: $WORKSPACES_DIR
- Service: $(systemctl is-active mcp-runner || true)
- Cleanup timer: $(systemctl is-active mcp-workspace-cleanup.timer || true)

## URLs
- MCP: https://$DOMAIN${PATH_PREFIX}mcp
- Health: https://$DOMAIN${PATH_PREFIX}health

## Token
$TOKEN

## Codex config
\`\`\`toml
$COD
\`\`\`

## Verify
\`\`\`bash
curl -fsS "https://$DOMAIN${PATH_PREFIX}mcp" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
\`\`\`
R
chmod 640 "$REPORT" && chown root:mcp "$REPORT"

nginx -t
systemctl reload nginx

echo "Stream conf: $STREAM_CONF"
echo "HTTP:80 conf: $HTTP80_CONF"
echo "MCP URL: https://$DOMAIN${PATH_PREFIX}mcp"
echo "Health URL: https://$DOMAIN${PATH_PREFIX}health"
echo "Token: $TOKEN"
echo "$COD"
