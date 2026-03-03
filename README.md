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

> If `--install-dir` and `--workspaces-dir` are omitted, installer generates random `/opt/<8-12 chars>` paths and prints them.

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
 │   ├─ Нет → ошибка и выход
 │   └─ Да
 ├─ path в формате /.../ ?
 │   ├─ Нет → ошибка и выход
 │   └─ Да
 ├─ install_dir/workspaces_dir заданы?
 │   ├─ Нет → генерируются случайные /opt/<8-12 символов> и печатаются в лог
 │   └─ Да → используются значения оператора
 ├─ nginx установлен?
 │   ├─ Нет → установка nginx
 │   └─ Да
 ├─ docker установлен?
 │   ├─ Нет → установка docker.io
 │   └─ Да
 ├─ Пользователь mcp существует?
 │   ├─ Нет → создать системного mcp (без shell)
 │   └─ Да
 ├─ Домен уже есть в stream map?
 │   ├─ Да → оставить текущий upstream/port без изменений
 │   └─ Нет → выбрать свободный порт из [7443..13443], добавить map+upstream
 ├─ В 80.conf есть ACME location до redirect?
 │   ├─ Нет → сделать backup и вставить snippet
 │   └─ Да
 ├─ LE сертификат уже существует?
 │   ├─ Да → использовать его
 │   └─ Нет → certbot webroot
 │       ├─ Успех → использовать LE
 │       └─ Ошибка → self-signed fallback + warning в report
 ├─ /etc/nginx/sites-available/<domain>.conf существует?
 │   ├─ Нет → создать из шаблона + location для PATH
 │   └─ Да
 │       ├─ mode=keep → оставить существующий MCP location
 │       ├─ mode=update → обновить существующий/добавить отсутствующий
 │       └─ mode=add → добавить новый MCP location
 ├─ token.txt существует?
 │   ├─ Нет → сгенерировать openssl rand -hex 32
 │   └─ Да → переиспользовать
 ├─ update-image?
 │   ├─ yes (по умолчанию) → docker build base image
 │   └─ no → пропустить
 └─ Установить/включить systemd сервисы, nginx -t, reload nginx,
    вывести MCP URL, health URL, токен, TOML и сохранить install-report.md
```
