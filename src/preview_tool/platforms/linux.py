from __future__ import annotations

import shutil
import socket
import sys
from argparse import Namespace
from pathlib import Path
from urllib.parse import urlparse

from preview_tool.core import PreviewError, Project, run, service_slug


def stage_path() -> str:
    path = shutil.which("stage")
    if path:
        return path

    launcher = Path(sys.argv[0]).resolve()
    candidates = (
        launcher.with_name("stage"),
        Path(__file__).resolve().parents[3] / "bin" / "stage",
    )
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)

    raise PreviewError("The stage command was not found next to preview or in PATH.")


def machine_label(hostname: str | None = None) -> str:
    value = hostname or socket.gethostname()
    return service_slug(value.split(".", 1)[0])


def mdns_host(project: Project, hostname: str | None = None) -> str:
    return f"{service_slug(project.site_name)}-{machine_label(hostname)}.local"


def prepare(project: Project, public_host: str, args: Namespace) -> Project:
    if args.no_stage:
        raise PreviewError(
            "Linux mDNS previews need Nginx staging. Remove --no-stage and use "
            "--backend when the application already runs its own server."
        )

    local_host = mdns_host(project)
    command = [
        stage_path(),
        "--site",
        project.site_name,
        "--machine",
        machine_label(),
        "--quiet",
    ]
    backend_host = urlparse(project.backend_url).hostname
    if args.backend is not None or backend_host != project.site_host:
        command.extend(["--backend", project.backend_url])

    result = run(
        command,
        check=False,
        capture=False,
        cwd=project.root,
    )
    if result.returncode == 20:
        raise PreviewError("Linux mDNS staging was skipped.")
    if result.returncode != 0:
        raise PreviewError("Linux staging failed. See the stage output above.")

    return Project(
        project.root,
        local_host,
        project.site_name,
        f"http://{local_host}",
    )


def stop(project: Project) -> None:
    result = run(
        [stage_path(), "--stop", "--site", project.site_name, "--machine", machine_label()],
        check=False,
        capture=False,
        cwd=project.root,
    )
    if result.returncode != 0:
        raise PreviewError("Linux preview cleanup failed. See the stage output above.")


def status() -> None:
    result = run([stage_path(), "--status"], check=False, capture=False)
    if result.returncode != 0:
        raise PreviewError("Linux preview status failed.")
