# mcp-runner-installer

Idempotent installer for Ubuntu 24.04 that deploys a shared MCP runner (FastMCP Streamable HTTP) behind nginx stream SNI routing.

## Quickstart

```bash
sudo ./install.sh \
  --domain example.com \
  --path /abc123xyz/ \
  --email admin@example.com \
  --github-user your-org-or-user
```

> If `--install-dir` and `--workspaces-dir` are omitted, installer uses default `/opt/MCPSRV` and `/opt/MCPSRV/workspaces`, and prints this in logs.

## Install via sudo + curl/wget

### 1) Рекомендуемый способ (всегда полный репозиторий)

```bash
sudo bash -c 'set -e; tmpdir=$(mktemp -d /tmp/mcpsrv-XXXXXX); curl -fsSL https://codeload.github.com/Efidripy/MCPSRV/tar.gz/refs/heads/main -o "$tmpdir/repo.tar.gz"; tar -xzf "$tmpdir/repo.tar.gz" -C "$tmpdir"; "$tmpdir"/MCPSRV-main/install.sh'
```

```bash
sudo bash -c 'set -e; tmpdir=$(mktemp -d /tmp/mcpsrv-XXXXXX); wget -qO "$tmpdir/repo.tar.gz" https://codeload.github.com/Efidripy/MCPSRV/tar.gz/refs/heads/main; tar -xzf "$tmpdir/repo.tar.gz" -C "$tmpdir"; "$tmpdir"/MCPSRV-main/install.sh'
```

### 2) С флагами (неинтерактивно)

```bash
sudo bash -c 'set -e; tmpdir=$(mktemp -d /tmp/mcpsrv-XXXXXX); curl -fsSL https://codeload.github.com/Efidripy/MCPSRV/tar.gz/refs/heads/main -o "$tmpdir/repo.tar.gz"; tar -xzf "$tmpdir/repo.tar.gz" -C "$tmpdir"; "$tmpdir"/MCPSRV-main/install.sh --domain example.com --path /abc123xyz/ --email admin@example.com --github-user your-org-or-user --assume-yes'
```

```bash
sudo bash -c 'set -e; tmpdir=$(mktemp -d /tmp/mcpsrv-XXXXXX); wget -qO "$tmpdir/repo.tar.gz" https://codeload.github.com/Efidripy/MCPSRV/tar.gz/refs/heads/main; tar -xzf "$tmpdir/repo.tar.gz" -C "$tmpdir"; "$tmpdir"/MCPSRV-main/install.sh --domain example.com --path /abc123xyz/ --email admin@example.com --github-user your-org-or-user --assume-yes'
```

> Почему так: `install.sh` использует `lib/`, `templates/`, `app/`. Запуск только одного файла из `/tmp` возможен лишь в версиях с bootstrap-логикой, а запуск из tarball всегда гарантирует наличие всех файлов.

## Troubleshooting

- Если у вас `80.conf` лежит в `/etc/nginx/sites-available/`, это теперь дефолтный путь для инсталлятора.
- Если путь другой, передайте явно:

```bash
--http80-conf /your/path/to/80.conf --stream-conf /your/path/to/stream.conf
```

- Инсталлятор автоматически ищет stream конфиг в:
  - `/etc/nginx/stream/stream.conf`
  - `/etc/nginx/stream-enabled/stream.conf`
- Инсталлятор автоматически ищет HTTP:80 конфиг в:
  - `/etc/nginx/sites-available/80.conf`
  - `/etc/nginx/conf.d/80.conf`
- Если HTTP:80 конфиг отсутствует, создается базовый `server { listen 80 ... }` и в него добавляется ACME location.

## Re-run / update

```bash
sudo ./install.sh \
  --domain example.com \
  --path /abc123xyz/ \
  --email admin@example.com \
  --github-user your-org-or-user \
  --mode update \
  --update-image yes
```

## Verify

```bash
curl -fsS "https://example.com/abc123xyz/health"

curl -fsS "https://example.com/abc123xyz/mcp" \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## Codex config

Copy from `<install_dir>/codex_config.toml` or use:

```toml
[mcp_servers.runner]
url = "https://example.com/abc123xyz/mcp"
bearer_token_env_var = "MCP_RUNNER_TOKEN"
```

```bash
export MCP_RUNNER_TOKEN='<token>'
```

## Security notes

- Keep `token.txt` secret; it grants MCP access.
- MCP can run scripts in Docker; only trusted users should access the token.
- Repo URL is strictly limited to `https://github.com/<github_user>/<repo>(.git)?`.

## Installer decision tree (схема дерева вопросов)

```text
Старт
 ├─ Переданы обязательные флаги?
 │   ├─ Нет → начать задавать вопросы по недостающим флагам (domain/email/github-user)
 │   └─ Да
 ├─ path в формате /.../ ?
 │   ├─ Нет → предложить ввести корректный путь; если пусто/некорректно — сгенерировать random /<8-12>/
 │   └─ Да
 ├─ install_dir/workspaces_dir заданы?
 │   ├─ Нет → использовать дефолт /opt/MCPSRV и /opt/MCPSRV/workspaces + вывести в лог
 │   └─ Да → использовать значения оператора
 ├─ nginx установлен?
 │   ├─ Нет → установка nginx
 │   └─ Да
 ├─ docker установлен?
 │   ├─ Нет → установка docker.io
 │   └─ Да
 ├─ Домен уже есть в stream map?
 │   ├─ Да → оставить текущий upstream/port
 │   └─ Нет → выбрать свободный порт из [7443..13443], добавить map+upstream
 ├─ LE сертификат существует?
 │   ├─ Да → использовать LE
 │   └─ Нет → certbot webroot; при ошибке self-signed fallback
 ├─ Vhost уже существует?
 │   ├─ Нет → создать из шаблона
 │   └─ Да → обработать location по mode=keep|update|add
 ├─ token.txt существует?
 │   ├─ Нет → сгенерировать
 │   └─ Да → использовать существующий
 └─ Установить/перезапустить systemd, проверить nginx -t, вывести URL/token/TOML и записать report
```
