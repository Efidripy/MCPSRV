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

### 1) Рекомендуемый способ: standalone bootstrap

```bash
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/Efidripy/MCPSRV/main/bootstrap.sh -o /tmp/mcpsrv-bootstrap.sh && chmod +x /tmp/mcpsrv-bootstrap.sh && /tmp/mcpsrv-bootstrap.sh'
```

```bash
sudo bash -c 'wget -qO /tmp/mcpsrv-bootstrap.sh https://raw.githubusercontent.com/Efidripy/MCPSRV/main/bootstrap.sh && chmod +x /tmp/mcpsrv-bootstrap.sh && /tmp/mcpsrv-bootstrap.sh'
```

### 2) С флагами (неинтерактивно)

```bash
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/Efidripy/MCPSRV/main/bootstrap.sh -o /tmp/mcpsrv-bootstrap.sh && chmod +x /tmp/mcpsrv-bootstrap.sh && /tmp/mcpsrv-bootstrap.sh --domain example.com --path /abc123xyz/ --email admin@example.com --github-user your-org-or-user --assume-yes'
```

### 3) Альтернатива: raw install.sh (с внутренним bootstrap)

```bash
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/Efidripy/MCPSRV/main/install.sh -o /tmp/mcp-install.sh && chmod +x /tmp/mcp-install.sh && /tmp/mcp-install.sh'
```

> `bootstrap.sh` всегда тянет полный архив репозитория перед запуском `install.sh`, поэтому это самый стабильный способ для copy/paste.

## Troubleshooting

- **Не используйте URL вида `https://github.com/.../blob/...` для запуска скриптов** — это HTML-страница, а не shell-файл (`<!DOCTYPE html>`).
- Правильные URL для скриптов должны быть из `raw.githubusercontent.com`.
- Быстрая проверка, что файл действительно shell-скрипт:

```bash
head -n 1 /tmp/mcp-install.sh
# ожидается: #!/usr/bin/env bash
```

- Если первая строка не shebang, удалите файл и скачайте заново из raw-ссылки.

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
- Если на сервере нет `python3-venv` (ошибка про `ensurepip is not available`), инсталлятор теперь автоматически доустанавливает `python3-venv` и повторяет создание `.venv`.
- Если `pip` сообщает конфликт версий между `fastapi`/`fastmcp`, используйте обновлённые зависимости из репозитория (`fastmcp` + `uvicorn`, без жёсткого pin на `fastapi`) и перезапустите установщик.
<<<<<<< codex/generate-mcp-runner-installer-repo-wkqvg2
- Инсталлятор дополнительно сам удаляет legacy-pin `fastapi==0.115.0` из `requirements.txt` (если встретит) и повторяет установку зависимостей автоматически.
=======
>>>>>>> main
- Инсталлятор также автоматически доустанавливает системные зависимости при отсутствии: `python3`, `python3-pip`, `python3-venv`, `git`, `openssl`, `certbot`, `tar` и `curl` (если нет `curl/wget`).

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
