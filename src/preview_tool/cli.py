from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any, Sequence

from preview_tool import __version__
from preview_tool.core import PreviewError, Project, detect_project, run, service_slug
from preview_tool.platforms import prepare


def tailscale_path() -> str:
    path = shutil.which("tailscale")
    if not path:
        raise PreviewError("Tailscale is not installed or is not in PATH.")
    return path


def tailscale_status(tailscale: str) -> dict[str, Any]:
    result = run([tailscale, "status", "--json"])
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise PreviewError("Tailscale returned invalid status data.") from error


def ensure_tailscale_online(tailscale: str) -> dict[str, Any]:
    status = tailscale_status(tailscale)
    if status.get("BackendState") == "Running" and status.get("Self", {}).get("Online"):
        return status

    print("Tailscale is offline. Starting sign-in...")
    run([tailscale, "up"], capture=False)
    status = tailscale_status(tailscale)
    if status.get("BackendState") != "Running" or not status.get("Self", {}).get("Online"):
        raise PreviewError("Tailscale sign-in did not finish.")
    return status


def is_service_host(status: dict[str, Any]) -> bool:
    return bool(status.get("Self", {}).get("Tags"))


def tailnet_suffix(status: dict[str, Any]) -> str:
    suffix = str(status.get("MagicDNSSuffix", "")).strip().strip(".")
    if not suffix:
        suffix = str(status.get("CurrentTailnet", {}).get("MagicDNSSuffix", "")).strip().strip(".")
    if not suffix:
        raise PreviewError("Tailscale did not return the tailnet DNS name.")
    return suffix


def device_dns_name(status: dict[str, Any]) -> str:
    value = str(status.get("Self", {}).get("DNSName", "")).rstrip(".")
    if not value:
        raise PreviewError("Tailscale did not return a DNS name for this computer.")
    return value


def service_identity(project: Project, status: dict[str, Any]) -> tuple[str, str]:
    slug = service_slug(project.site_name)
    return f"svc:{slug}", f"{slug}.{tailnet_suffix(status)}"


def read_json_command(command: Sequence[str]) -> dict[str, Any]:
    result = run(command, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise PreviewError(detail or f"Command failed: {' '.join(command)}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}


def print_status(tailscale: str) -> None:
    found = False
    node_status = read_json_command([tailscale, "serve", "status", "--json"])
    for host, config in node_status.get("Web", {}).items():
        handlers = config.get("Handlers", {})
        proxy = handlers.get("/", {}).get("Proxy", "unknown backend")
        print(f"https://{host.removesuffix(':443')} -> {proxy}")
        found = True

    service_config = read_json_command([tailscale, "serve", "get-config", "--all"])
    for service, config in service_config.get("services", {}).items():
        endpoints = config.get("endpoints", {})
        for endpoint, target in endpoints.items():
            print(f"{service} {endpoint} -> {target}")
            found = True

    if not found:
        print("No preview is active.")


def stop_preview(tailscale: str, args: argparse.Namespace) -> None:
    status = ensure_tailscale_online(tailscale)
    if is_service_host(status):
        project = detect_project(Path.cwd(), site=args.site, backend=args.backend)
        service, _ = service_identity(project, status)
        result = run(
            [tailscale, "serve", f"--service={service}", "--https=443", "off"],
            check=False,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            raise PreviewError(detail or f"Tailscale could not stop {service}.")
        print(f"Stopped the preview for {project.site_name}.")
        return

    run([tailscale, "serve", "reset"], capture=False)
    print("Private preview stopped.")


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def state_directory() -> Path:
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return base / "Elliptic" / "preview"
    return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "elliptic-preview"


def update_preview() -> None:
    root = repository_root()
    if not (root / ".git").exists():
        raise PreviewError("This installation is not a Git clone. Reinstall preview to update it.")

    dirty = run(["git", "status", "--porcelain"], cwd=root).stdout.strip()
    if dirty:
        raise PreviewError(f"The preview repository has local changes: {root}")

    previous = run(["git", "rev-parse", "HEAD"], cwd=root).stdout.strip()
    run(["git", "pull", "--ff-only"], cwd=root, capture=False)
    current = run(["git", "rev-parse", "HEAD"], cwd=root).stdout.strip()

    tests = run(
        [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"],
        cwd=root,
        check=False,
        capture=False,
    )
    if tests.returncode != 0:
        raise PreviewError(
            "The update failed its tests. "
            f"The previous commit was {previous}. The current commit is {current}."
        )

    state = state_directory()
    state.mkdir(parents=True, exist_ok=True)
    (state / "previous-version").write_text(f"{previous}\n", encoding="utf-8")
    if previous == current:
        print(f"preview {__version__} is current.")
    else:
        print(f"Updated preview from {previous[:8]} to {current[:8]}.")


def rollback_preview() -> None:
    root = repository_root()
    if not (root / ".git").exists():
        raise PreviewError("This installation is not a Git clone. Reinstall preview to change versions.")

    dirty = run(["git", "status", "--porcelain"], cwd=root).stdout.strip()
    if dirty:
        raise PreviewError(f"The preview repository has local changes: {root}")

    state_file = state_directory() / "previous-version"
    if not state_file.is_file():
        raise PreviewError("No previous preview version was recorded.")

    previous = state_file.read_text(encoding="utf-8").strip()
    current = run(["git", "rev-parse", "HEAD"], cwd=root).stdout.strip()
    run(["git", "cat-file", "-e", f"{previous}^{{commit}}"], cwd=root)
    run(["git", "reset", "--hard", previous], cwd=root, capture=False)
    state_file.write_text(f"{current}\n", encoding="utf-8")
    print(f"Changed preview from {current[:8]} to {previous[:8]}.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="preview",
        description="Share the current Git project through private Tailscale HTTPS.",
    )
    parser.add_argument(
        "command",
        nargs="?",
        choices=("start", "stop", "status", "update", "rollback", "version"),
    )
    legacy = parser.add_mutually_exclusive_group()
    legacy.add_argument("--stop", action="store_true", help=argparse.SUPPRESS)
    legacy.add_argument("--status", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--site", help="Override the site host or local site name.")
    parser.add_argument("--backend", help="Override the local HTTP backend URL.")
    parser.add_argument("--no-stage", action="store_true", help="Skip Laragon staging on Windows.")
    parser.add_argument(
        "--laragon-root",
        type=Path,
        default=Path(os.environ.get("LARAGON_ROOT", r"F:\laragon")),
        help="Laragon directory on Windows. The default is F:\\laragon.",
    )
    return parser


def selected_command(args: argparse.Namespace) -> str:
    if args.stop:
        return "stop"
    if args.status:
        return "status"
    return args.command or "start"


def start_preview(tailscale: str, args: argparse.Namespace) -> None:
    project = detect_project(Path.cwd(), site=args.site, backend=args.backend)
    status = ensure_tailscale_online(tailscale)

    if is_service_host(status):
        service, public_host = service_identity(project, status)
    else:
        service = None
        public_host = device_dns_name(status)

    args.multi_url = service is not None
    project = prepare(project, public_host, args)
    print(f"Creating a private preview for {project.site_host}...")

    command = [tailscale, "serve"]
    if service:
        command.extend([f"--service={service}", "--https=443", project.backend_url])
    else:
        command.extend(["--bg", project.backend_url])

    result = run(command, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        if service and ("not found" in detail.lower() or "unknown" in detail.lower()):
            raise PreviewError(
                f"Create {service} on the Tailscale Services page, then run preview again.\n{detail}"
            )
        raise PreviewError(f"Tailscale Serve failed.\n{detail}")

    print(f"Private preview: https://{public_host}")
    print(f"Backend: {project.backend_url}")
    if service:
        print(f"Service: {service}")
    else:
        print("This computer uses one URL. The last project wins.")
    print("Only devices allowed by this Tailscale network can open it.")


def execute(args: argparse.Namespace) -> int:
    command = selected_command(args)
    if command == "version":
        print(f"preview {__version__}")
        return 0
    if command == "update":
        update_preview()
        return 0
    if command == "rollback":
        rollback_preview()
        return 0

    tailscale = tailscale_path()
    if command == "stop":
        stop_preview(tailscale, args)
    elif command == "status":
        print_status(tailscale)
    else:
        start_preview(tailscale, args)
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    try:
        return execute(build_parser().parse_args(argv))
    except PreviewError as error:
        print(f"preview: {error}", file=sys.stderr)
        return 1
