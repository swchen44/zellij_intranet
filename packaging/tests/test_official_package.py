#!/usr/bin/env python3
import importlib.util
import json
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "packaging" / "package_official.py"
MODULE_SPEC = importlib.util.spec_from_file_location("package_official", MODULE_PATH)
assert MODULE_SPEC and MODULE_SPEC.loader
package_official = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = package_official
MODULE_SPEC.loader.exec_module(package_official)


class OfficialPackageUnitTests(unittest.TestCase):
    def test_official_asset_names_for_no_web_targets(self):
        self.assertEqual(
            package_official.official_asset_name("no-web", "linux-x86_64"),
            "zellij-no-web-x86_64-unknown-linux-musl.tar.gz",
        )
        self.assertEqual(
            package_official.official_checksum_name("no-web", "linux-x86_64"),
            "zellij-no-web-x86_64-unknown-linux-musl.sha256sum",
        )
        self.assertEqual(
            package_official.official_asset_name("no-web", "windows-x86_64"),
            "zellij-no-web-x86_64-pc-windows-msvc.zip",
        )

    def test_parse_sha256sum_requires_the_expected_filename(self):
        digest = "a" * 64
        self.assertEqual(
            package_official.parse_sha256sum(
                f"{digest}  target/x86_64-pc-windows-msvc/release/zellij.exe\n",
                "zellij.exe",
            ),
            digest,
        )
        with self.assertRaises(ValueError):
            package_official.parse_sha256sum(
                f"{digest}  target/x86_64-pc-windows-msvc/release/another.exe\n",
                "zellij.exe",
            )

    def test_normalize_version_adds_v_prefix(self):
        self.assertEqual(package_official.normalize_version("0.45.1"), "v0.45.1")
        self.assertEqual(package_official.normalize_version("v0.45.1"), "v0.45.1")

    def test_package_command_defaults_to_full_variant(self):
        args = package_official._parser().parse_args(["package", "--version", "v0.45.1"])
        self.assertEqual(args.variant, "full")

    def test_create_linux_package_preserves_executable_and_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stage = root / "stage"
            stage.mkdir()
            binary = stage / "zellij"
            binary.write_bytes(b"fake-linux-binary")
            binary.chmod(0o755)
            license_file = root / "LICENSE.md"
            license_file.write_text("license\n", encoding="utf-8")

            output = package_official.create_package(
                stage_dir=stage,
                target="linux-x86_64",
                version="v0.45.1",
                variant="no-web",
                upstream_asset="zellij-no-web-x86_64-unknown-linux-musl.tar.gz",
                upstream_binary_sha256="b" * 64,
                downloaded_archive_sha256="d" * 64,
                output_dir=root / "dist",
                license_source=license_file,
            )

            with tarfile.open(output, "r:gz") as archive:
                members = {member.name: member for member in archive.getmembers()}
                self.assertIn("zellij", members)
                self.assertEqual(members["zellij"].mode & 0o111, 0o111)
                self.assertIn("BUILD-INFO.txt", members)
                self.assertIn("README.md", members)
                self.assertIn("README.txt", members)
                self.assertIn("LICENSE.md", members)
                readme = archive.extractfile("README.md").read().decode("utf-8")
                for section in ("## Prerequisites", "## Add to PATH", "## Boundary", "## Links"):
                    self.assertIn(section, readme)
                self.assertIn("https://github.com/swchen44/zellij_intranet", readme)
            manifest = json.loads(
                output.with_name(output.name.removesuffix(".tar.gz") + ".manifest.json")
                .read_text(encoding="utf-8")
            )
            self.assertEqual(manifest["target"], "linux-x86_64")
            self.assertEqual(manifest["upstream_binary_sha256"], "b" * 64)

    def test_create_windows_package_contains_exe_and_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stage = root / "stage"
            stage.mkdir()
            (stage / "zellij.exe").write_bytes(b"fake-windows-binary")
            license_file = root / "LICENSE.md"
            license_file.write_text("license\n", encoding="utf-8")

            output = package_official.create_package(
                stage_dir=stage,
                target="windows-x86_64",
                version="v0.45.1",
                variant="no-web",
                upstream_asset="zellij-no-web-x86_64-pc-windows-msvc.zip",
                upstream_binary_sha256="c" * 64,
                downloaded_archive_sha256="e" * 64,
                output_dir=root / "dist",
                license_source=license_file,
            )

            with zipfile.ZipFile(output) as archive:
                self.assertEqual(
                    set(archive.namelist()),
                    {"zellij.exe", "BUILD-INFO.txt", "README.md", "README.txt", "LICENSE.md"},
                )
                readme = archive.read("README.md").decode("utf-8")
                self.assertIn("Windows Terminal", readme)
                self.assertIn("### Windows x86_64 (PowerShell)", readme)
                self.assertIn("$env:Path", readme)
                self.assertIn("## Boundary", readme)

    def test_create_package_is_reproducible_for_same_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stage = root / "stage"
            stage.mkdir()
            (stage / "zellij.exe").write_bytes(b"same-binary")
            license_file = root / "LICENSE.md"
            license_file.write_text("license\n", encoding="utf-8")

            first = package_official.create_package(
                stage_dir=stage,
                target="windows-x86_64",
                version="v0.45.1",
                variant="no-web",
                upstream_asset="zellij-no-web-x86_64-pc-windows-msvc.zip",
                upstream_binary_sha256="c" * 64,
                downloaded_archive_sha256="e" * 64,
                output_dir=root / "first",
                license_source=license_file,
            )
            second = package_official.create_package(
                stage_dir=stage,
                target="windows-x86_64",
                version="v0.45.1",
                variant="no-web",
                upstream_asset="zellij-no-web-x86_64-pc-windows-msvc.zip",
                upstream_binary_sha256="c" * 64,
                downloaded_archive_sha256="e" * 64,
                output_dir=root / "second",
                license_source=license_file,
            )

            self.assertEqual(first.read_bytes(), second.read_bytes())


if __name__ == "__main__":
    unittest.main()
