#!/usr/bin/env bash
set -euo pipefail

TARGET="x86_64-pc-windows-msvc"
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING="$ROOT/packaging"
VERSION="0.46.0"
SOURCE_COMMIT="474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb"
SOURCE_DESCRIBE="v0.44.1-122-g474ea0cef"
RUST_TOOLCHAIN="1.95.0"
FEATURE_PROFILE="terminal-only"
NAME="zellij-$TARGET"
ARCHIVE="$ROOT/dist/$NAME.zip"
MANIFEST="$ROOT/dist/$NAME.manifest.json"
CHECKSUM="$ARCHIVE.sha256"
BINARY="$ROOT/target/$TARGET/release/zellij.exe"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zellij-windows-package.XXXXXX")"
STAGE="$STAGE_ROOT/$NAME"

cleanup() { rm -rf "$STAGE_ROOT"; }
trap cleanup EXIT

die() {
	echo "package-windows-local: $*" >&2
	exit 1
}

cd "$ROOT"
[[ "$(git rev-parse HEAD)" == "$SOURCE_COMMIT" ]] || die "source commit mismatch"
[[ -f "$BINARY" ]] || die "missing binary: $BINARY; run packaging/build-windows-local.sh"
command -v zip >/dev/null 2>&1 || die "zip is required"
command -v file >/dev/null 2>&1 || die "file is required"
file_output="$(file "$BINARY")"
echo "$file_output" | grep -Eiq 'PE32\+.*x86-64' \
	|| die "binary is not a Windows x86-64 PE32+ executable"

mkdir -p "$STAGE" "$ROOT/dist"
install -m 0644 "$BINARY" "$STAGE/zellij.exe"
install -m 0644 "$ROOT/LICENSE.md" "$STAGE/LICENSE.md"
install -m 0644 "$ROOT/docs/ZELLIJ-USER-GUIDE.md" "$STAGE/ZELLIJ-USER-GUIDE.md"

cat > "$STAGE/README.txt" <<EOF
Zellij $VERSION portable Windows candidate package

Target: $TARGET
Source: $SOURCE_DESCRIBE ($SOURCE_COMMIT)
Build method: cargo-xwin on macOS
Runtime verification: pending Windows host
Feature profile: $FEATURE_PROFILE (no default features; plugins_from_target)

Run .\\zellij.exe --version or .\\zellij.exe setup --check in Windows Terminal.
Read ZELLIJ-USER-GUIDE.md for pane, tab, session and Windows Terminal workflows.
This package does not include Rust, Cargo, Yazi, Claude Code, Codex, SSH, or a shell.
Builtin WASM plugins are embedded in the zellij binary and do not require network access.
The web/share capability is excluded from this terminal-only package; it is not needed for
Windows Terminal + Zellij + Yazi usage.
EOF

cat > "$STAGE/README.md" <<EOF
# Zellij offline portable package

- Version: $VERSION
- Variant: source-fallback
- Target: $TARGET

## Prerequisites

Use on a matching x86_64 Windows host with Windows Terminal and a shell. Rust, Cargo,
OpenSSL, Visual Studio, Yazi, SSH, and network access are not runtime prerequisites.

## Usage

\`\`\`powershell
.\\zellij.exe --version
.\\zellij.exe setup --check
.\\zellij.exe
\`\`\`

## Add to PATH

\`\`\`powershell
\$env:Path = "\$PWD;\$env:Path"
zellij.exe
\`\`\`

## User guide

Read `ZELLIJ-USER-GUIDE.md` for common pane, tab, session, SSH, Windows Terminal and
Yazi workflows. It is included for offline use.

## Boundary

This source-fallback package contains Zellij only. It does not contain Yazi, SSH,
Windows Terminal, a shell, Claude Code, Codex, or preview helpers. Windows runtime
verification is pending on a real Windows host.

## Links

- Project: https://github.com/swchen44/zellij_intranet
- Upstream documentation: https://zellij.dev/documentation/
EOF

cat > "$STAGE/BUILD-INFO.txt" <<EOF
product=zellij
version=$VERSION
source_commit=$SOURCE_COMMIT
source_describe=$SOURCE_DESCRIBE
rust_toolchain=$RUST_TOOLCHAIN
target=$TARGET
feature_profile=$FEATURE_PROFILE
bundled_plugins=true
build_method=cargo-xwin-macos
runtime_verification=pending-windows-host
build_jobs=${ZELLIJ_WINDOWS_BUILD_JOBS:-1}
EOF

rm -f "$ARCHIVE" "$MANIFEST" "$CHECKSUM"
(cd "$STAGE_ROOT" && zip -q -X "$ARCHIVE" "$NAME/zellij.exe" "$NAME/README.md" "$NAME/README.txt" "$NAME/ZELLIJ-USER-GUIDE.md" "$NAME/LICENSE.md" "$NAME/BUILD-INFO.txt")
archive_sha256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha256" "$(basename "$ARCHIVE")" > "$CHECKSUM"

ZELLIJ_PACKAGE_VERSION="$VERSION" \
ZELLIJ_SOURCE_COMMIT="$SOURCE_COMMIT" \
ZELLIJ_SOURCE_DESCRIBE="$SOURCE_DESCRIBE" \
ZELLIJ_RUST_TOOLCHAIN="$RUST_TOOLCHAIN" \
ZELLIJ_FEATURE_PROFILE="$FEATURE_PROFILE" \
ZELLIJ_RUNTIME_VERIFICATION="pending-windows-host" \
	"$PACKAGING/manifest-windows.sh" "$MANIFEST" "$ARCHIVE" "$archive_sha256" "cargo-xwin-macos"

echo "$ARCHIVE"
echo "$MANIFEST"
echo "$CHECKSUM"
