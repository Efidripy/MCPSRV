import os
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException, Request
from fastmcp import FastMCP

WORKSPACES_DIR = Path(os.environ.get("MCP_WORKSPACES_DIR", "/opt/mcp-workspaces"))
GITHUB_USER = os.environ.get("MCP_GITHUB_USER", "").strip()
TOKEN = os.environ.get("MCP_BEARER_TOKEN", "").strip()


def require_bearer(request: Request):
    auth = request.headers.get("authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing Bearer token")
    if not TOKEN:
        raise HTTPException(status_code=500, detail="Server token not configured")
    got = auth.removeprefix("Bearer ").strip()
    if got != TOKEN:
        raise HTTPException(status_code=403, detail="Invalid token")


def validate_repo_url(repo_url: str):
    if not GITHUB_USER:
        raise HTTPException(status_code=500, detail="MCP_GITHUB_USER not configured")
    pattern = rf"^https://github\.com/{re.escape(GITHUB_USER)}/[A-Za-z0-9_.-]+(\.git)?$"
    if not re.match(pattern, repo_url):
        raise HTTPException(status_code=400, detail=f"repo_url must be https://github.com/{GITHUB_USER}/<repo>")


def run(cmd: List[str], cwd: Optional[Path] = None, timeout_s: int = 3600) -> str:
    p = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout_s,
    )
    return p.stdout


mcp = FastMCP("mcp-runner")
app = FastAPI()


@app.middleware("http")
async def auth_mw(request: Request, call_next):
    if request.url.path.startswith("/mcp"):
        require_bearer(request)
    return await call_next(request)


@app.get("/health")
def health():
    return {"ok": True}


app.mount("/mcp", mcp.streamable_http_app())


@mcp.tool()
def run_in_docker(
    repo_url: str,
    ref: str = "main",
    script: str = "uname -a",
    image: str = "mcp-runner-base:latest",
    workdir: str = "/work",
    timeout_s: int = 3600,
) -> Dict[str, str]:
    validate_repo_url(repo_url)

    WORKSPACES_DIR.mkdir(parents=True, exist_ok=True)

    safe_ref = "".join(c for c in ref if c.isalnum() or c in "-_./")
    if not safe_ref:
        raise HTTPException(status_code=400, detail="ref contains no valid characters after sanitization")
    key = abs(hash(repo_url + safe_ref))
    target = WORKSPACES_DIR / f"repo-{key}"

    if not (target / ".git").exists():
        run(["git", "clone", repo_url, str(target)], timeout_s=timeout_s)

    run(["git", "fetch", "--all", "--tags"], cwd=target, timeout_s=timeout_s)
    run(["git", "checkout", safe_ref], cwd=target, timeout_s=timeout_s)
    run(["git", "reset", "--hard"], cwd=target, timeout_s=timeout_s)

    docker_cmd = [
        "docker", "run", "--rm",
        "--cpus=2",
        "--memory=2g",
        "--pids-limit=512",
        "--network=bridge",
        "--security-opt=no-new-privileges",
        "-v", f"{target}:{workdir}",
        "-w", workdir,
        image,
        "bash", "-lc", script,
    ]

    out = run(docker_cmd, timeout_s=timeout_s)
    return {"output": out, "repo_path": str(target), "image": image, "ref": safe_ref}
