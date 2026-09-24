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

    def test_package_command_defaults_to_full_flat_bin_layout(self):
        args = package_official._parser().parse_args(["package", "--version", "v0.45.1"])
        self.assertEqual(args.variant, "full")
        self.assertEqual(args.layout, "flat-bin")

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
                self.assertIn("zellij_bin/zellij", members)
                self.assertEqual(members["zellij_bin/zellij"].mode & 0o111, 0o111)
                self.assertIn("zellij_bin/BUILD-INFO.txt", members)
                self.assertIn("zellij_bin/README.md", members)
                self.assertIn("zellij_bin/README.txt", members)
                self.assertIn("zellij_bin/LICENSE.md", members)
                readme = archive.extractfile("zellij_bin/README.md").read().decode("utf-8")
                for section in ("## Prerequisites", "## Add to PATH", "## User guide", "## Boundary", "## Links"):
                    self.assertIn(section, readme)
                self.assertIn("https://github.com/swchen44/zellij_intranet", readme)
                self.assertIn("zellij_bin/ZELLIJ-USER-GUIDE.md", members)
                self.assertIn("zellij_bin", readme)
                self.assertIn("~/local/bin/zellij_bin", readme)
            manifest = json.loads(
                output.with_name(output.name.removesuffix(".tar.gz") + ".manifest.json")
                .read_text(encoding="utf-8")
            )
            self.assertEqual(manifest["target"], "linux-x86_64")
            self.assertEqual(manifest["upstream_binary_sha256"], "b" * 64)
            self.assertEqual(manifest["layout"], "flat-bin")
            self.assertEqual(manifest["package_root"], "zellij_bin")
            self.assertEqual(output.name, "zellij-v0.45.1-no-web-x86_64-unknown-linux-musl-flat-bin.tar.gz")

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
                    {
                        "zellij_bin/zellij.exe",
                        "zellij_bin/BUILD-INFO.txt",
                        "zellij_bin/README.md",
                        "zellij_bin/README.txt",
                        "zellij_bin/ZELLIJ-USER-GUIDE.md",
                        "zellij_bin/LICENSE.md",
                    },
                )
                readme = archive.read("zellij_bin/README.md").decode("utf-8")
                self.assertIn("Windows Terminal", readme)
                self.assertIn("### Windows x86_64 (PowerShell)", readme)
                self.assertIn("$env:Path", readme)
                self.assertIn("ZELLIJ-USER-GUIDE.md", readme)
                self.assertIn("## Boundary", readme)
                self.assertIn("zellij_bin", readme)
            self.assertEqual(output.name, "zellij-v0.45.1-no-web-x86_64-pc-windows-msvc-flat-bin.zip")

    def test_create_standard_package_remains_supported_for_compatibility(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stage = root / "stage"
            stage.mkdir()
            (stage / "zellij.exe").write_bytes(b"legacy-windows-binary")
            license_file = root / "LICENSE.md"
            license_file.write_text("license\n", encoding="utf-8")

            output = package_official.create_package(
                stage_dir=stage,
                target="windows-x86_64",
                version="v0.45.1",
                variant="no-web",
                layout="standard",
                upstream_asset="zellij-no-web-x86_64-pc-windows-msvc.zip",
                upstream_binary_sha256="c" * 64,
                downloaded_archive_sha256="e" * 64,
                output_dir=root / "dist",
                license_source=license_file,
            )

            with zipfile.ZipFile(output) as archive:
                self.assertIn("zellij.exe", archive.namelist())
            manifest = json.loads(
                output.with_name(output.name.removesuffix(".zip") + ".manifest.json")
                .read_text(encoding="utf-8")
            )
            self.assertEqual(manifest["layout"], "standard")
            self.assertEqual(manifest["package_root"], ".")

    def test_verify_package_accepts_flat_bin_archive_without_network(self):
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
                variant="full",
                upstream_asset="zellij-x86_64-unknown-linux-musl.tar.gz",
                upstream_binary_sha256="f" * 64,
                downloaded_archive_sha256="a" * 64,
                output_dir=root / "dist",
                license_source=license_file,
                layout="flat-bin",
            )

            package_official.verify_package(output)

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
                layout="flat-bin",
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
                layout="flat-bin",
                upstream_asset="zellij-no-web-x86_64-pc-windows-msvc.zip",
                upstream_binary_sha256="c" * 64,
                downloaded_archive_sha256="e" * 64,
                output_dir=root / "second",
                license_source=license_file,
            )

            self.assertEqual(first.read_bytes(), second.read_bytes())


if __name__ == "__main__":
    unittest.main()
