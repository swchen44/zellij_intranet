#!/usr/bin/env python3
import importlib.util
import json
import sys
import tempfile
import zipfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "packaging" / "make-download-test-zips.py"
MODULE_SPEC = importlib.util.spec_from_file_location("make_download_test_zips", MODULE_PATH)
assert MODULE_SPEC and MODULE_SPEC.loader
module = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = module
MODULE_SPEC.loader.exec_module(module)


class DownloadVariantTests(unittest.TestCase):
    def test_variants_keep_the_same_binary_and_change_documented_layout(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.zip"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("zellij.exe", b"same-binary")
                archive.writestr("README.md", b"readme")
                archive.writestr("LICENSE.md", b"license")

            binary_hashes = set()
            for variant_name, variant in module.VARIANTS.items():
                output = module.write_variant(source, root / variant_name, variant_name)
                manifest_path = output.with_suffix(".manifest.json")
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                with zipfile.ZipFile(output) as archive:
                    names = set(archive.namelist())
                expected_binary = manifest["binary_path_after_extract"]
                expected_binary = (
                    f'{variant["prefix"]}{expected_binary}'
                    if variant["prefix"]
                    else expected_binary
                )
                self.assertIn(expected_binary, names)
                binary_hashes.add(manifest["zellij_sha256"])
                self.assertEqual(manifest["archive_name"], output.name)

            self.assertEqual(binary_hashes, {module.sha256_bytes(b"same-binary")})


if __name__ == "__main__":
    unittest.main()
