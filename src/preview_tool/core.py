from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence
from urllib.parse import urlparse


class PreviewError(RuntimeError):
    pass


@dataclass(frozen=True)
class Project:
    root: Path
    site_host: str
    site_name: str
    backend_url: str


def run(
    command: Sequence[str],
    *,
    check: bool = True,
    capture: bool = True,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            list(command),
            check=check,
            capture_output=capture,
            cwd=cwd,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as error:
        raise PreviewError(f"Command not found: {command[0]}") from error
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "").strip()
        message = f"Command failed: {' '.join(command)}"
        if detail:
            message = f"{message}\n{detail}"
        raise PreviewError(message) from error


def git_root(cwd: Path) -> Path:
    result = run(["git", "rev-parse", "--show-toplevel"], cwd=cwd)
    value = result.stdout.strip()
    if not value:
        raise PreviewError("Run preview from a Git worktree.")
    return Path(value).resolve()


def read_app_url(root: Path) -> str | None:
    for name in (".env", ".env.example"):
        path = root / name
        if not path.is_file():
            continue
        for raw_line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
            match = re.match(r"^\s*APP_URL\s*=\s*(.*?)\s*$", raw_line)
            if not match:
                continue
            value = match.group(1).strip().strip('"\'')
            parsed = urlparse(value)
            if parsed.scheme in {"http", "https"} and parsed.hostname:
                return value.rstrip("/")
    return None


def safe_site_name(value: str) -> str:
    value = re.sub(r"(?i)\.test$", "", value.strip())
    value = re.sub(r"[^a-zA-Z0-9._-]+", "-", value).strip("-.").lower()
    if not value or value in {".", ".."}:
        raise PreviewError("The project did not produce a valid site name.")
    return value


def service_slug(value: str) -> str:
    value = re.sub(r"[^a-z0-9-]+", "-", value.lower()).strip("-")
    value = re.sub(r"-+", "-", value)[:63].rstrip("-")
    if not value:
        raise PreviewError("The project did not produce a valid Tailscale service name.")
    return value


def detect_project(
    cwd: Path,
    *,
    site: str | None = None,
    backend: str | None = None,
) -> Project:
    root = git_root(cwd)
    app_url = read_app_url(root)

    if site:
        raw_host = site.strip()
        site_host = raw_host if "." in raw_host else f"{raw_host}.test"
    elif app_url and (urlparse(app_url).hostname or "").endswith(".test"):
        site_host = urlparse(app_url).hostname or ""
    else:
        site_host = f"{root.name}.test"

    site_name = safe_site_name(site_host)
    backend_url = (backend or app_url or f"http://{site_host}").rstrip("/")
    parsed_backend = urlparse(backend_url)
    if parsed_backend.scheme not in {"http", "https"} or not parsed_backend.hostname:
        raise PreviewError(f"The backend URL is not valid: {backend_url}")

    return Project(root, site_host, site_name, backend_url)
