#!/usr/bin/env bash
set -euo pipefail

TARGET="x86_64-unknown-linux-musl"
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING="$ROOT/packaging"
VERSION="0.46.0"
SOURCE_COMMIT="474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb"
SOURCE_DESCRIBE="v0.44.1-122-g474ea0cef"
RUST_TOOLCHAIN="1.95.0"
FEATURE_PROFILE="default"
NAME="zellij-$TARGET"
ARCHIVE="$ROOT/dist/$NAME.tar.gz"
MANIFEST="$ROOT/dist/$NAME.manifest.json"
CHECKSUM="$ARCHIVE.sha256"
BINARY="$ROOT/target/$TARGET/release/zellij"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zellij-package.XXXXXX")"
STAGE="$STAGE_ROOT/$NAME"

cleanup() { rm -rf "$STAGE_ROOT"; }
trap cleanup EXIT

die() {
	echo "package-linux: $*" >&2
	exit 1
}

cd "$ROOT"
[[ "$(git rev-parse HEAD)" == "$SOURCE_COMMIT" ]] || die "source commit mismatch"
[[ -x "$BINARY" ]] || die "missing binary: $BINARY; run packaging/build-linux.sh"
if readelf -lW "$BINARY" | grep -q ' INTERP '; then
	die "binary contains an ELF interpreter"
fi

mkdir -p "$STAGE" "$ROOT/dist"
install -m 0755 "$BINARY" "$STAGE/zellij"
install -m 0644 "$ROOT/LICENSE.md" "$STAGE/LICENSE.md"

cat > "$STAGE/README.txt" <<EOF
Zellij $VERSION portable Linux package

Target: $TARGET
Source: $SOURCE_DESCRIBE ($SOURCE_COMMIT)

Run ./zellij --version or ./zellij setup --check.
This package does not include Rust, Cargo, Yazi, Claude Code, Codex, SSH, or a shell.
Builtin WASM plugins are embedded in the zellij binary and do not require network access.
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
build_jobs=1
EOF

rm -f "$ARCHIVE" "$MANIFEST" "$CHECKSUM"
tar -C "$STAGE_ROOT" -czf "$ARCHIVE" "$NAME"
archive_sha256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha256" "$(basename "$ARCHIVE")" > "$CHECKSUM"

ZELLIJ_PACKAGE_VERSION="$VERSION" \
ZELLIJ_SOURCE_COMMIT="$SOURCE_COMMIT" \
ZELLIJ_SOURCE_DESCRIBE="$SOURCE_DESCRIBE" \
ZELLIJ_RUST_TOOLCHAIN="$RUST_TOOLCHAIN" \
ZELLIJ_FEATURE_PROFILE="$FEATURE_PROFILE" \
	"$PACKAGING/manifest.sh" "$MANIFEST" "$ARCHIVE" "$archive_sha256"

echo "$ARCHIVE"
echo "$MANIFEST"
echo "$CHECKSUM"
