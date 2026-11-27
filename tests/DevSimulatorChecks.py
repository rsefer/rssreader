import io
import os
import runpy
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


watcher = runpy.run_path(str(Path(__file__).resolve().parent.parent / "scripts" / "dev_simulator.py"))


class DevSimulatorChecks(unittest.TestCase):
    def load_env(self, contents, overrides=None):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / ".env"
            config.write_text(contents)
            environment = os.environ.copy()
            environment.pop("DEVICE_ID", None)
            environment.pop("SIMULATOR_ID", None)
            environment.update(overrides or {})
            loader = Path(__file__).resolve().parent.parent / "scripts" / "load_env.sh"
            return subprocess.run(
                ["bash", "-e", "-c",
                 'source "$1"; load_device_env "$2"; printf "%s\\n%s\\n" "$DEVICE_ID" "$SIMULATOR_ID"',
                 "env-check", str(loader), str(config)],
                env=environment, capture_output=True, text=True,
            )

    def test_shared_env_loads_both_targets_and_empty_defaults(self):
        result = self.load_env("# Local targets\r\nDEVICE_ID=ABC-123\r\nSIMULATOR_ID=DEF-456\r\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["ABC-123", "DEF-456"])
        for device, simulator in [("", ""), ("ABC-123", ""), ("", "DEF-456")]:
            with self.subTest(device=device, simulator=simulator):
                blank = self.load_env(f"DEVICE_ID={device}\nSIMULATOR_ID={simulator}")
                self.assertEqual(blank.returncode, 0, blank.stderr)
                self.assertEqual(blank.stdout.splitlines(), [device, simulator])

    def test_command_line_targets_override_shared_env(self):
        result = self.load_env(
            "DEVICE_ID=ABC-123\nSIMULATOR_ID=DEF-456\n",
            {"DEVICE_ID": "123-ABC", "SIMULATOR_ID": "456-DEF"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["123-ABC", "456-DEF"])

    def test_shared_env_rejects_duplicates_unknown_keys_and_expansion(self):
        for contents in [
            "DEVICE_ID=ABC\nDEVICE_ID=DEF\n",
            "SIMULATOR_ID=ABC\nSIMULATOR_ID=DEF\n",
            "DEVICE_ID=\nDEVICE_ID=ABC\n",
            "UNKNOWN=ABC\n",
            "DEVICE_ID=$HOME\n",
            'SIMULATOR_ID="ABC"\n',
        ]:
            with self.subTest(contents=contents):
                result = self.load_env(contents)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid .env line", result.stderr)

    def test_detects_source_and_resource_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "rssreader" / "Feature.swift"
            source.parent.mkdir()
            source.write_text("original")
            original = watcher["snapshot"](root)
            source.write_text("modified feature")
            modified = watcher["snapshot"](root)
            self.assertNotEqual(original, modified)
            resource = source.parent / "Asset.json"
            resource.write_text("{}")
            added = watcher["snapshot"](root)
            self.assertNotEqual(modified, added)
            resource.unlink()
            self.assertEqual(modified, watcher["snapshot"](root))

    def test_ignores_build_output_and_xcode_user_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = watcher["snapshot"](root)
            for relative in ["build/dev-simulator.log", "rssreader.xcodeproj/xcuserdata/state"]:
                generated = root / relative
                generated.parent.mkdir(parents=True, exist_ok=True)
                generated.write_text("generated")
            self.assertEqual(original, watcher["snapshot"](root))
            (root / ".env").write_text("SIMULATOR_ID=changed")
            self.assertNotEqual(original, watcher["snapshot"](root))

    def test_failed_deployment_surfaces_log_without_retrying(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def failed_build(command, **kwargs):
                kwargs["stdout"].write("error: test compilation failed\n")
                return SimpleNamespace(returncode=1)

            output = io.StringIO()
            with patch("subprocess.run", side_effect=failed_build) as run, redirect_stdout(output):
                self.assertEqual(watcher["deploy"](root), 1)
            run.assert_called_once()
            self.assertIn("Deployment failed", output.getvalue())
            self.assertIn("error: test compilation failed", output.getvalue())


if __name__ == "__main__":
    unittest.main()
