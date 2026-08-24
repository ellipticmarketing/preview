import argparse
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from preview_tool.cli import is_service_host, service_identity, start_preview, update_preview
from preview_tool.core import (
    PreviewError,
    Project,
    detect_project,
    read_app_url,
    safe_site_name,
    service_slug,
)
from preview_tool.platforms.linux import nginx_backend, prepare as prepare_linux, stage_path
from preview_tool.platforms.windows import apache_preview_config, running_laragon_root


class PreviewTests(unittest.TestCase):
    def test_read_app_url_prefers_env(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".env.example").write_text(
                "APP_URL=http://example.test\n", encoding="utf-8"
            )
            (root / ".env").write_text(
                'APP_URL="https://active.test"\n', encoding="utf-8"
            )

            self.assertEqual(read_app_url(root), "https://active.test")

    def test_safe_site_name_removes_test_suffix(self) -> None:
        self.assertEqual(safe_site_name("DG.EMForward.test"), "dg.emforward")

    def test_safe_site_name_rejects_empty_name(self) -> None:
        with self.assertRaises(PreviewError):
            safe_site_name("...")

    def test_ip_backend_uses_repository_name_for_site(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "my-project"
            root.mkdir()
            (root / ".env").write_text(
                "APP_URL=http://127.0.0.1:8000\n", encoding="utf-8"
            )

            with patch("preview_tool.core.git_root", return_value=root):
                project = detect_project(root)

        self.assertEqual(project.site_host, "my-project.test")
        self.assertEqual(project.backend_url, "http://127.0.0.1:8000")

    def test_windows_config_marks_forwarded_request_as_https(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = type("Project", (), {"site_name": "sample"})()
            config = apache_preview_config(project, "computer.tailnet.ts.net", root)

            self.assertIn("ServerName computer.tailnet.ts.net", config)
            self.assertIn("SetEnv HTTPS on", config)
            self.assertIn("/data/stage/sample/public", config)

    def test_windows_detects_running_laragon_directory(self) -> None:
        completed = subprocess.CompletedProcess([], 0, "C:\\laragon\n", "")

        with patch("preview_tool.platforms.windows.run", return_value=completed):
            self.assertEqual(running_laragon_root("powershell"), Path("C:\\laragon"))

    def test_linux_stage_backend_replaces_app_url(self) -> None:
        project = Project(Path("/project"), "demo.test", "demo", "http://demo.test")
        args = argparse.Namespace(backend=None)
        completed = subprocess.CompletedProcess([], 0, "", "")

        with (
            patch("preview_tool.platforms.linux.stage_path", return_value="/bin/stage"),
            patch("preview_tool.platforms.linux.run", return_value=completed) as run_command,
        ):
            prepared = prepare_linux(project, "demo.tailnet.ts.net", args)

        self.assertEqual(prepared.backend_url, nginx_backend("demo"))
        run_command.assert_called_once_with(
            ["/bin/stage", "--site", "demo"],
            check=False,
            capture=False,
            cwd=Path("/project"),
        )

    def test_linux_finds_stage_next_to_preview_launcher(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bin_directory = Path(directory) / "bin"
            bin_directory.mkdir()
            preview = bin_directory / "preview"
            stage = bin_directory / "stage"
            preview.touch()
            stage.touch()

            with (
                patch("preview_tool.platforms.linux.shutil.which", return_value=None),
                patch("preview_tool.platforms.linux.sys.argv", [str(preview)]),
            ):
                self.assertEqual(Path(stage_path()).resolve(), stage.resolve())

    def test_linux_stage_keeps_explicit_backend(self) -> None:
        project = Project(Path("/project"), "demo.test", "demo", "http://127.0.0.1:8000")
        args = argparse.Namespace(backend="http://127.0.0.1:8000")
        completed = subprocess.CompletedProcess([], 0, "", "")

        with (
            patch("preview_tool.platforms.linux.stage_path", return_value="/bin/stage"),
            patch("preview_tool.platforms.linux.run", return_value=completed),
        ):
            prepared = prepare_linux(project, "demo.tailnet.ts.net", args)

        self.assertEqual(prepared, project)

    def test_linux_stage_decline_uses_app_url(self) -> None:
        project = Project(Path("/project"), "demo.test", "demo", "http://demo.test")
        args = argparse.Namespace(backend=None)
        completed = subprocess.CompletedProcess([], 20, "", "")

        with (
            patch("preview_tool.platforms.linux.stage_path", return_value="/bin/stage"),
            patch("preview_tool.platforms.linux.run", return_value=completed),
        ):
            prepared = prepare_linux(project, "demo.tailnet.ts.net", args)

        self.assertEqual(prepared, project)

    def test_update_reinstalls_linux_command_links(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".git").mkdir()
            installer = root / "install-ubuntu.sh"
            installer.touch()
            state = root / "state"
            revisions = iter(("a" * 40, "b" * 40))

            def command_result(command, **kwargs):
                if command[:3] == ["git", "rev-parse", "HEAD"]:
                    return subprocess.CompletedProcess(command, 0, next(revisions) + "\n", "")
                return subprocess.CompletedProcess(command, 0, "", "")

            with (
                patch("preview_tool.cli.repository_root", return_value=root),
                patch("preview_tool.cli.state_directory", return_value=state),
                patch("preview_tool.cli.os.name", "posix"),
                patch("preview_tool.cli.run", side_effect=command_result) as run_command,
            ):
                update_preview()

            run_command.assert_any_call(
                ["sh", str(installer)], cwd=root, capture=False
            )

    def test_service_slug_is_dns_safe(self) -> None:
        self.assertEqual(service_slug("DG.EMForward_test"), "dg-emforward-test")

    def test_tagged_device_uses_project_service(self) -> None:
        project = Project(Path("/project"), "Demo.test", "demo", "http://demo.test")
        status = {
            "MagicDNSSuffix": "tail-example.ts.net",
            "Self": {"Tags": ["tag:preview"]},
        }

        self.assertTrue(is_service_host(status))
        self.assertEqual(
            service_identity(project, status),
            ("svc:demo", "demo.tail-example.ts.net"),
        )

    def test_personal_device_is_not_a_service_host(self) -> None:
        self.assertFalse(is_service_host({"Self": {"Tags": None}}))

    def test_tagged_device_starts_named_service(self) -> None:
        project = Project(Path("/project"), "demo.test", "demo", "http://demo.test")
        status = {
            "BackendState": "Running",
            "MagicDNSSuffix": "tail-example.ts.net",
            "Self": {"Online": True, "Tags": ["tag:preview"]},
        }
        args = argparse.Namespace(
            site=None,
            backend=None,
            no_stage=True,
            laragon_root=Path("/laragon"),
        )
        completed = subprocess.CompletedProcess([], 0, "", "")

        with (
            patch("preview_tool.cli.detect_project", return_value=project),
            patch("preview_tool.cli.ensure_tailscale_online", return_value=status),
            patch("preview_tool.cli.prepare", return_value=project),
            patch("preview_tool.cli.run", return_value=completed) as run_command,
        ):
            start_preview("tailscale", args)

        run_command.assert_called_once_with(
            [
                "tailscale",
                "serve",
                "--service=svc:demo",
                "--https=443",
                "http://demo.test",
            ],
            check=False,
        )


if __name__ == "__main__":
    unittest.main()
