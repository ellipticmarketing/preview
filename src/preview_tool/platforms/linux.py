from __future__ import annotations

import shutil
import sys
import zlib
from argparse import Namespace
from pathlib import Path

from preview_tool.core import PreviewError, Project, run


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


def nginx_backend(site_name: str) -> str:
    port = 20000 + zlib.crc32(site_name.encode()) % 20000
    return f"http://127.0.0.1:{port}"


def prepare(project: Project, public_host: str, args: Namespace) -> Project:
    result = run(
        [stage_path(), "--site", project.site_name],
        check=False,
        capture=False,
        cwd=project.root,
    )
    if result.returncode == 20:
        print(f"Using APP_URL directly: {project.backend_url}")
        return project
    if result.returncode != 0:
        raise PreviewError("Linux staging failed. See the stage output above.")

    if args.backend is not None:
        return project
    return Project(
        project.root,
        project.site_host,
        project.site_name,
        nginx_backend(project.site_name),
    )
