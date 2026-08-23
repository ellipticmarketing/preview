import argparse
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from preview_tool.cli import is_service_host, service_identity, start_preview
from preview_tool.core import PreviewError, Project, read_app_url, safe_site_name, service_slug
from preview_tool.platforms.windows import apache_preview_config


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

    def test_windows_config_marks_forwarded_request_as_https(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = type("Project", (), {"site_name": "sample"})()
            config = apache_preview_config(project, "computer.tailnet.ts.net", root)

            self.assertIn("ServerName computer.tailnet.ts.net", config)
            self.assertIn("SetEnv HTTPS on", config)
            self.assertIn("/data/stage/sample/public", config)

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
