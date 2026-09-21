#!/usr/bin/env python3
"""Create diagnostic Zellij Windows ZIPs for corporate download testing.

These archives are deliberately diagnostic variants, not replacement release
packages. Each variant keeps the same zellij.exe bytes and changes only the
archive payload/layout/compression dimension described in its manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path


VARIANTS = {
    "minimal-flat-deflate": {
        "description": "Only zellij.exe at the ZIP root, deflate compression.",
        "prefix": "",
        "move_binary_to_bin": False,
        "include": {"zellij.exe"},
        "compression": zipfile.ZIP_DEFLATED,
    },
    "flat-store": {
        "description": "The normal package files at the ZIP root, stored without compression.",
        "prefix": "",
        "move_binary_to_bin": False,
        "include": None,
        "compression": zipfile.ZIP_STORED,
    },
    "nested-deflate": {
        "description": "The normal package files under one top-level directory, deflate compression.",
        "prefix": "zellij-v0.45.1-full-x86_64-pc-windows-msvc/",
        "move_binary_to_bin": False,
        "include": None,
        "compression": zipfile.ZIP_DEFLATED,
    },
    "nested-bin-deflate": {
        "description": "Top-level directory with zellij.exe moved to bin/, matching Yazi's executable layout.",
        "prefix": "zellij-v0.45.1-full-x86_64-pc-windows-msvc/",
        "move_binary_to_bin": True,
        "include": None,
        "compression": zipfile.ZIP_DEFLATED,
    },
    "nested-bin-store": {
        "description": "Top-level directory with zellij.exe in bin/, stored without compression.",
        "prefix": "zellij-v0.45.1-full-x86_64-pc-windows-msvc/",
        "move_binary_to_bin": True,
        "include": None,
        "compression": zipfile.ZIP_STORED,
    },
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def zip_member_name(name: str, variant: dict[str, object]) -> str:
    if bool(variant["move_binary_to_bin"]) and name == "zellij.exe":
        name = "bin/zellij.exe"
    return f'{variant["prefix"]}{name}'


def write_variant(source: Path, output_dir: Path, variant_name: str) -> Path:
    variant = VARIANTS[variant_name]
    with zipfile.ZipFile(source) as archive:
        payload = {
            info.filename: archive.read(info.filename)
            for info in archive.infolist()
            if not info.is_dir()
        }

    selected = variant["include"]
    if selected is not None:
        payload = {name: data for name, data in payload.items() if name in selected}

    output_name = (
        f"zellij-v0.45.1-full-x86_64-pc-windows-msvc-diag-{variant_name}.zip"
    )
    output = output_dir / output_name
    output_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(
        output,
        "w",
        compression=int(variant["compression"]),
        compresslevel=9 if variant["compression"] == zipfile.ZIP_DEFLATED else None,
    ) as archive:
        for name in sorted(payload):
            info = zipfile.ZipInfo(
                zip_member_name(name, variant),
                date_time=(2000, 1, 1, 0, 0, 0),
            )
            info.compress_type = int(variant["compression"])
            info.create_system = 3
            info.external_attr = 0x81A40000
            archive.writestr(info, payload[name])

    binary = payload["zellij.exe"]
    manifest = {
        "diagnostic": True,
        "production_package": False,
        "archive_name": output.name,
        "source_package": source.name,
        "variant": variant_name,
        "description": variant["description"],
        "compression": "deflate" if variant["compression"] == zipfile.ZIP_DEFLATED else "stored",
        "top_level_directory": bool(variant["prefix"]),
        "binary_path_after_extract": (
            "bin/zellij.exe" if variant["move_binary_to_bin"] else "zellij.exe"
        ),
        "zellij_sha256": sha256_bytes(binary),
        "package_sha256": sha256_file(output),
        "test_command": (
            "bin\\zellij.exe --version"
            if variant["move_binary_to_bin"]
            else "zellij.exe --version"
        ),
    }
    manifest_path = output.with_suffix(".manifest.json")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    checksum_path = output.with_name(output.name + ".sha256")
    checksum_path.write_text(f"{manifest['package_sha256']}  {output.name}\n", encoding="utf-8")
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="canonical Windows Zellij ZIP")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("dist/diagnostic"),
        help="directory for diagnostic ZIPs and metadata",
    )
    parser.add_argument("--variant", choices=tuple(VARIANTS), action="append")
    args = parser.parse_args()
    if not args.source.is_file():
        parser.error(f"source ZIP not found: {args.source}")
    for name in args.variant or VARIANTS:
        output = write_variant(args.source, args.output_dir, name)
        print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
