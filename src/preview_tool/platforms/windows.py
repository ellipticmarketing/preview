from __future__ import annotations

import shutil
from argparse import Namespace
from pathlib import Path

from preview_tool.core import PreviewError, Project, run


def powershell_path() -> str:
    for name in ("pwsh", "powershell"):
        path = shutil.which(name)
        if path:
            return path
    raise PreviewError("PowerShell is required for Laragon staging.")


def stage_script(shell: str) -> str:
    result = run(
        [
            shell,
            "-NoProfile",
            "-Command",
            "(Get-Command stage.ps1 -ErrorAction Stop).Source",
        ]
    )
    path = result.stdout.strip()
    if not path:
        raise PreviewError("The global stage.ps1 command was not found.")
    return path


def run_stage(project: Project, laragon_root: Path, *, reload: bool = False) -> None:
    shell = powershell_path()
    command = [
        shell,
        "-NoProfile",
        "-File",
        stage_script(shell),
        "-Site",
        project.site_name,
        "-LaragonRoot",
        str(laragon_root),
    ]
    if reload:
        command.append("-ForceReload")
    run(command, capture=False, cwd=project.root)


def apache_preview_config(project: Project, public_host: str, laragon_root: Path) -> str:
    preview_root = (laragon_root / "data" / "stage" / project.site_name / "public").as_posix()
    return (
        "<VirtualHost *:80>\n"
        f"    ServerName {public_host}\n"
        f'    DocumentRoot "{preview_root}"\n'
        "    SetEnv HTTPS on\n"
        f'    <Directory "{preview_root}">\n'
        "        AllowOverride All\n"
        "        Require all granted\n"
        "    </Directory>\n"
        "</VirtualHost>\n"
    )


def prepare(project: Project, public_host: str, args: Namespace) -> Project:
    laragon_root = args.laragon_root.resolve()
    if args.backend is None:
        project = Project(
            project.root,
            project.site_host,
            project.site_name,
            f"http://{project.site_host}",
        )

    run_stage(project, laragon_root)
    public_path = laragon_root / "data" / "stage" / project.site_name / "public"
    if not public_path.is_dir():
        raise PreviewError(f"The staged public directory was not found: {public_path}")

    sites_path = laragon_root / "etc" / "apache2" / "sites-enabled"
    if not sites_path.is_dir():
        raise PreviewError(f"The Apache site directory was not found: {sites_path}")

    config_name = (
        f"000-tailscale-preview-{public_host.split('.')[0]}.conf"
        if args.multi_url
        else "000-tailscale-preview.conf"
    )
    config_path = sites_path / config_name
    content = apache_preview_config(project, public_host, laragon_root)
    current = config_path.read_text(encoding="utf-8") if config_path.is_file() else None
    if current != content:
        config_path.write_text(content, encoding="utf-8", newline="\n")

    run_stage(project, laragon_root, reload=True)
    return project
