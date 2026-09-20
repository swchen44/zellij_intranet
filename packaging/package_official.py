#!/usr/bin/env python3
"""Package official Zellij release binaries for offline use."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import shutil
import ssl
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


GITHUB_RELEASE_BASE = "https://github.com/zellij-org/zellij/releases/download"
VERSION_PATTERN = re.compile(r"^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")


@dataclass(frozen=True)
class TargetSpec:
    upstream_target: str
    archive_format: str
    binary_name: str


TARGETS = {
    "linux-x86_64": TargetSpec(
        upstream_target="x86_64-unknown-linux-musl",
        archive_format="tar.gz",
        binary_name="zellij",
    ),
    "windows-x86_64": TargetSpec(
        upstream_target="x86_64-pc-windows-msvc",
        archive_format="zip",
        binary_name="zellij.exe",
    ),
}


def normalize_version(value: str) -> str:
    value = value.strip()
    if not VERSION_PATTERN.fullmatch(value):
        raise ValueError(f"invalid release version: {value!r}")
    return value if value.startswith("v") else f"v{value}"


def official_asset_name(variant: str, target: str) -> str:
    if variant not in {"full", "no-web"}:
        raise ValueError(f"unsupported variant: {variant}")
    try:
        spec = TARGETS[target]
    except KeyError as error:
        raise ValueError(f"unsupported target: {target}") from error
    prefix = "zellij" if variant == "full" else "zellij-no-web"
    return f"{prefix}-{spec.upstream_target}.{spec.archive_format}"


def official_checksum_name(variant: str, target: str) -> str:
    asset_name = official_asset_name(variant, target)
    archive_suffix = f".{TARGETS[target].archive_format}"
    return f"{asset_name.removesuffix(archive_suffix)}.sha256sum"


def release_url(version: str, asset_name: str) -> str:
    return f"{GITHUB_RELEASE_BASE}/{normalize_version(version)}/{asset_name}"


def parse_sha256sum(contents: str, expected_filename: str) -> str:
    for line in contents.splitlines():
        fields = line.strip().split()
        if len(fields) < 2:
            continue
        digest, filename = fields[0].lower(), fields[-1].lstrip("*")
        if Path(filename).name != expected_filename:
            continue
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError(f"invalid SHA-256 in checksum file for {expected_filename}")
        return digest
    raise ValueError(f"checksum file does not contain {expected_filename}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _ssl_context(ca_bundle: Path | None) -> ssl.SSLContext:
    if ca_bundle is not None:
        return ssl.create_default_context(cafile=str(ca_bundle))
    if sys.platform == "darwin":
        macos_bundle = Path("/etc/ssl/cert.pem")
        if macos_bundle.is_file():
            return ssl.create_default_context(cafile=str(macos_bundle))
    return ssl.create_default_context()


def download(url: str, destination: Path, ca_bundle: Path | None = None) -> None:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "zellij-intranet-packager/1"},
    )
    with urllib.request.urlopen(
        request,
        context=_ssl_context(ca_bundle),
        timeout=120,
    ) as response:
        with destination.open("wb") as output:
            shutil.copyfileobj(response, output)


def _validate_archive_member(name: str) -> None:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe archive member: {name!r}")


def extract_upstream_archive(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    if archive.name.endswith(".tar.gz"):
        with tarfile.open(archive, "r:gz") as source:
            members = source.getmembers()
            for member in members:
                _validate_archive_member(member.name)
            try:
                source.extractall(destination, filter="data")
            except TypeError:
                source.extractall(destination)
        return
    if archive.name.endswith(".zip"):
        with zipfile.ZipFile(archive) as source:
            for name in source.namelist():
                _validate_archive_member(name)
            source.extractall(destination)
        return
    raise ValueError(f"unsupported upstream archive: {archive.name}")


def _package_stem(version: str, variant: str, target: str) -> str:
    spec = TARGETS[target]
    return f"zellij-{normalize_version(version)}-{variant}-{spec.upstream_target}"


def _runtime_readme_markdown(version: str, variant: str, target: str) -> str:
    binary = TARGETS[target].binary_name
    if target == "linux-x86_64":
        platform_name = "Linux x86_64"
        run_command = f"./{binary}"
        version_command = f"./{binary} --version"
        path_command = 'export PATH="$PWD:$PATH"'
        path_run_command = "zellij"
    else:
        platform_name = "Windows x86_64 (PowerShell)"
        run_command = f".\\{binary}"
        version_command = f".\\{binary} --version"
        path_command = '$env:Path = "$PWD;$env:Path"'
        path_run_command = "zellij.exe"

    if variant == "full":
        web_boundary = (
            "This `full` variant includes the upstream Zellij Web Server/Web Client capability. "
            "It does not start a web server automatically. Before exposing a web endpoint, "
            "configure authentication, HTTPS, listen address, and port for the company policy."
        )
    else:
        web_boundary = (
            "This `no-web` variant excludes the upstream Web Server/Web Client capability. "
            "Use the `full` variant only when the web capability is explicitly required and "
            "has passed a separate security review."
        )

    return "\n".join(
        [
            "# Zellij offline portable package",
            "",
            f"- Version: `{normalize_version(version)}`",
            f"- Variant: `{variant}`",
            f"- Target: `{target}`",
            "",
            "This archive is prepared for the `zellij_intranet` project. Extract the complete "
            "archive and run the platform binary from the extracted directory. The package "
            "does not download anything at runtime.",
            "",
            "## Prerequisites",
            "",
            f"- A matching {platform_name} host.",
            "- A terminal and shell supplied by the host. Windows native use is intended for "
            "Windows Terminal; the SSH scenario uses the remote Linux shell.",
            "- No Rust, Cargo, OpenSSL, `protoc`, musl toolchain, Visual Studio, Git, or "
            "package manager is required at runtime.",
            "- Yazi, SSH, Windows Terminal, shells, Claude Code, and Codex are external "
            "commands and are not included in this archive.",
            "",
            "## Usage",
            "",
            f"### {platform_name}",
            "",
            "Run Zellij directly:",
            "",
            "```text",
            run_command,
            version_command,
            f"{run_command} setup --check",
            "```",
            "",
            "The first command starts Zellij. The other commands are useful smoke checks "
            "before starting an interactive session.",
            "",
            "## Add to PATH",
            "",
            "For the current shell only, add this package directory to `PATH`:",
            "",
            "```sh" if target == "linux-x86_64" else "```powershell",
            path_command,
            path_run_command,
            "```",
            "",
            "Do not copy only the binary to another directory if you also need the release "
            "metadata; keep the complete extracted package together for traceability.",
            "",
            "## Built-in plugins",
            "",
            "The official release binary contains Zellij's bundled WASM plugins. They are "
            "embedded in the binary; a separate plugin directory, Rust toolchain, or network "
            "download is not required for the built-in plugin set.",
            "",
            "```text",
            f"{run_command} setup --dump-plugins <temporary-plugin-directory>",
            "```",
            "",
            "## Boundary",
            "",
            "- This is a Zellij binary package, not a complete terminal workstation bundle.",
            "- It does not include Yazi, SSH, Windows Terminal, a shell, Claude Code, Codex, "
            "or company authentication/configuration.",
            "- This release package targets x86_64 only. ARM64 is not included or runtime "
            "verified in this project version.",
            "- Runtime network access is not required for the terminal workflow.",
            f"- {web_boundary}",
            "- Image, video, PDF, and archive preview helpers belong to the separate Yazi "
            "bundle and are outside this package's scope.",
            "",
            "## Release and checksums",
            "",
            "Keep this archive together with its matching `.sha256` and `.manifest.json` "
            "files. Verify the archive checksum before extracting it. The manifest records "
            "both the package SHA-256 and the upstream binary SHA-256.",
            "",
            "## Links",
            "",
            "- Project: https://github.com/swchen44/zellij_intranet",
            f"- Upstream release: https://github.com/zellij-org/zellij/releases/tag/{normalize_version(version)}",
            "- Upstream documentation: https://zellij.dev/documentation/",
            "",
        ]
    )


def _write_runtime_readme(path: Path, version: str, variant: str, target: str) -> None:
    path.write_text(
        _runtime_readme_markdown(version, variant, target),
        encoding="utf-8",
    )


def _write_runtime_readme_compatibility(
    path: Path, version: str, variant: str, target: str
) -> None:
    binary = TARGETS[target].binary_name
    path.write_text(
        "\n".join(
            [
                "Zellij offline portable package",
                "",
                f"Version: {normalize_version(version)}",
                f"Variant: {variant}",
                f"Target: {target}",
                "",
                f"Run ./{binary} from this directory.",
                "Read README.md for prerequisites, PATH instructions, boundaries, and links.",
                "This package is self-contained and does not download anything at runtime.",
                "Yazi, shells, SSH and Windows Terminal are packaged separately.",
                "",
            ]
        ),
        encoding="utf-8",
    )


def _write_build_info(
    path: Path,
    version: str,
    variant: str,
    target: str,
    upstream_asset: str,
    upstream_binary_sha256: str,
) -> None:
    path.write_text(
        "\n".join(
            [
                f"version={normalize_version(version)}",
                "source=official-zellij-release",
                f"variant={variant}",
                f"target={target}",
                f"upstream_asset={upstream_asset}",
                f"upstream_binary_sha256={upstream_binary_sha256}",
                "runtime_network_required=false",
                "arm64_runtime_verification=not-run",
                "",
            ]
        ),
        encoding="utf-8",
    )


def create_package(
    *,
    stage_dir: Path,
    target: str,
    version: str,
    variant: str,
    upstream_asset: str,
    upstream_binary_sha256: str,
    downloaded_archive_sha256: str,
    output_dir: Path,
    license_source: Path,
) -> Path:
    spec = TARGETS[target]
    output_dir.mkdir(parents=True, exist_ok=True)
    package_name = f"{_package_stem(version, variant, target)}.{spec.archive_format}"
    output = output_dir / package_name

    with tempfile.TemporaryDirectory(prefix="zellij-package-") as temporary:
        package_root = Path(temporary)
        binary_source = stage_dir / spec.binary_name
        if not binary_source.is_file():
            raise FileNotFoundError(f"missing upstream binary: {binary_source}")
        if not license_source.is_file():
            raise FileNotFoundError(f"missing license source: {license_source}")

        binary = package_root / spec.binary_name
        shutil.copy2(binary_source, binary)
        if target == "linux-x86_64":
            binary.chmod(0o755)
        shutil.copy2(license_source, package_root / "LICENSE.md")
        _write_runtime_readme(package_root / "README.md", version, variant, target)
        _write_runtime_readme_compatibility(
            package_root / "README.txt", version, variant, target
        )
        _write_build_info(
            package_root / "BUILD-INFO.txt",
            version,
            variant,
            target,
            upstream_asset,
            upstream_binary_sha256,
        )

        members = [
            package_root / spec.binary_name,
            package_root / "BUILD-INFO.txt",
            package_root / "README.md",
            package_root / "README.txt",
            package_root / "LICENSE.md",
        ]
        if spec.archive_format == "tar.gz":
            with output.open("wb") as raw_output:
                with gzip.GzipFile(
                    filename="",
                    mode="wb",
                    fileobj=raw_output,
                    mtime=0,
                ) as compressed_output:
                    with tarfile.open(fileobj=compressed_output, mode="w") as archive:
                        for member in members:
                            info = tarfile.TarInfo(member.name)
                            info.size = member.stat().st_size
                            info.mode = member.stat().st_mode & 0o777
                            info.mtime = 0
                            info.uid = 0
                            info.gid = 0
                            info.uname = ""
                            info.gname = ""
                            with member.open("rb") as source:
                                archive.addfile(info, source)
        else:
            with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for member in members:
                    info = zipfile.ZipInfo(member.name, date_time=(1980, 1, 1, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.create_system = 3
                    info.external_attr = (member.stat().st_mode & 0o777) << 16
                    archive.writestr(info, member.read_bytes())

    package_sha256 = sha256_file(output)
    checksum_path = output.with_name(output.name + ".sha256")
    checksum_path.write_text(f"{package_sha256}  {output.name}\n", encoding="utf-8")
    manifest_path = output.with_name(
        output.name.removesuffix(".tar.gz").removesuffix(".zip") + ".manifest.json"
    )
    manifest_path.write_text(
        json.dumps(
            {
                "package": output.name,
                "package_sha256": package_sha256,
                "version": normalize_version(version),
                "source": "official-zellij-release",
                "variant": variant,
                "target": target,
                "upstream_asset": upstream_asset,
                "upstream_binary_sha256": upstream_binary_sha256,
                "downloaded_archive_sha256": downloaded_archive_sha256,
                "runtime_network_required": False,
                "arm64_runtime_verification": "not-run",
                "package_readme": "README.md",
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return output


def package_release(
    *,
    version: str,
    variant: str,
    targets: list[str],
    output_dir: Path,
    license_source: Path,
    ca_bundle: Path | None,
) -> list[Path]:
    version = normalize_version(version)
    with tempfile.TemporaryDirectory(prefix="zellij-download-") as temporary:
        download_dir = Path(temporary)
        packages = []
        for target in targets:
            asset_name = official_asset_name(variant, target)
            checksum_name = official_checksum_name(variant, target)
            archive_path = download_dir / asset_name
            checksum_path = download_dir / checksum_name
            print(f"[download] {release_url(version, asset_name)}")
            download(release_url(version, asset_name), archive_path, ca_bundle)
            print(f"[download] {release_url(version, checksum_name)}")
            download(release_url(version, checksum_name), checksum_path, ca_bundle)
            archive_sha256 = sha256_file(archive_path)
            extracted = download_dir / f"extracted-{target}"
            extract_upstream_archive(archive_path, extracted)
            binary = extracted / TARGETS[target].binary_name
            if not binary.is_file():
                raise FileNotFoundError(
                    f"official archive does not contain root binary {TARGETS[target].binary_name}: {asset_name}"
                )
            expected = parse_sha256sum(
                checksum_path.read_text(encoding="utf-8"),
                TARGETS[target].binary_name,
            )
            actual = sha256_file(binary)
            if actual != expected:
                raise RuntimeError(
                    f"upstream binary SHA-256 mismatch for {asset_name}: expected {expected}, got {actual}"
                )
            print(f"[verify] upstream binary SHA-256 {asset_name}: {actual}")
            print(f"[info] downloaded archive SHA-256 {asset_name}: {archive_sha256}")
            packages.append(
                create_package(
                    stage_dir=extracted,
                    target=target,
                    version=version,
                    variant=variant,
                    upstream_asset=asset_name,
                    upstream_binary_sha256=expected,
                    downloaded_archive_sha256=archive_sha256,
                    output_dir=output_dir,
                    license_source=license_source,
                )
            )
        return packages


def _package_manifest_path(package: Path) -> Path:
    return package.with_name(
        package.name.removesuffix(".tar.gz").removesuffix(".zip") + ".manifest.json"
    )


def _package_checksum_path(package: Path) -> Path:
    return package.with_name(package.name + ".sha256")


def verify_package(package: Path) -> None:
    if not package.is_file():
        raise FileNotFoundError(package)
    checksum_path = _package_checksum_path(package)
    manifest_path = _package_manifest_path(package)
    expected = parse_sha256sum(checksum_path.read_text(encoding="utf-8"), package.name)
    actual = sha256_file(package)
    if actual != expected:
        raise RuntimeError(f"package SHA-256 mismatch: expected {expected}, got {actual}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("package") != package.name:
        raise ValueError("manifest package name does not match archive")
    if manifest.get("package_sha256") != actual:
        raise ValueError("manifest package SHA-256 does not match archive")
    target = manifest.get("target")
    if target not in TARGETS:
        raise ValueError(f"manifest contains unsupported target: {target!r}")
    variant = manifest.get("variant")
    if variant not in {"full", "no-web"}:
        raise ValueError(f"manifest contains unsupported variant: {variant!r}")
    if manifest.get("package_readme") != "README.md":
        raise ValueError("manifest must identify README.md as the package README")
    binary = TARGETS[target].binary_name
    with tempfile.TemporaryDirectory(prefix="zellij-verify-") as temporary:
        extracted = Path(temporary)
        extract_upstream_archive(package, extracted)
        binary_path = extracted / binary
        if not binary_path.is_file():
            raise ValueError(f"package is missing {binary}")
        if target == "linux-x86_64" and binary_path.stat().st_mode & 0o111 == 0:
            raise ValueError("Linux zellij binary is not executable")
        readme_path = extracted / "README.md"
        if not readme_path.is_file():
            raise ValueError("package is missing README.md")
        readme = readme_path.read_text(encoding="utf-8")
        for section in ("## Prerequisites", "## Add to PATH", "## Boundary", "## Links"):
            if section not in readme:
                raise ValueError(f"package README.md is missing section: {section}")
        if "https://github.com/swchen44/zellij_intranet" not in readme:
            raise ValueError("package README.md is missing the project GitHub link")
        if "https://github.com/zellij-org/zellij/releases/tag/" not in readme:
            raise ValueError("package README.md is missing the upstream release link")
    print(f"[verify] package SHA-256 {package.name}: {actual}")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    package = commands.add_parser("package", help="download and package an official release")
    package.add_argument("--version", required=True, help="release version, for example v0.45.1")
    package.add_argument("--variant", choices=("no-web", "full"), default="full")
    package.add_argument(
        "--target",
        action="append",
        choices=tuple(TARGETS),
        dest="targets",
        help="target to package; repeat to select a subset",
    )
    package.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "dist" / "official",
    )
    package.add_argument("--ca-bundle", type=Path, help="custom CA bundle for HTTPS downloads")

    verify = commands.add_parser("verify", help="verify a local package without network access")
    verify.add_argument("package", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "package":
            targets = args.targets or list(TARGETS)
            license_source = Path(__file__).resolve().parent / "LICENSE.md"
            packages = package_release(
                version=args.version,
                variant=args.variant,
                targets=targets,
                output_dir=args.output_dir,
                license_source=license_source,
                ca_bundle=args.ca_bundle,
            )
            for package in packages:
                verify_package(package)
                print(f"[done] {package}")
            return 0
        verify_package(args.package)
        return 0
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"package-official: error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
