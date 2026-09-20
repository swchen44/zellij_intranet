#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 ]] || {
	echo "Usage: packaging/manifest.sh <output> <archive> <sha256>" >&2
	exit 2
}

OUTPUT="$1"
ARCHIVE="$2"
ARCHIVE_SHA256="$3"
TARGET="x86_64-unknown-linux-musl"
VERSION="${ZELLIJ_PACKAGE_VERSION:-0.46.0}"
SOURCE_COMMIT="${ZELLIJ_SOURCE_COMMIT:-474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb}"
SOURCE_DESCRIBE="${ZELLIJ_SOURCE_DESCRIBE:-v0.44.1-122-g474ea0cef}"
RUST_TOOLCHAIN="${ZELLIJ_RUST_TOOLCHAIN:-1.95.0}"
FEATURE_PROFILE="${ZELLIJ_FEATURE_PROFILE:-default}"

[[ "$ARCHIVE_SHA256" =~ ^[[:xdigit:]]{64}$ ]] || {
	echo "manifest: invalid SHA-256: $ARCHIVE_SHA256" >&2
	exit 1
}

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
{
  "product": "zellij",
  "version": "$VERSION",
  "source_commit": "$SOURCE_COMMIT",
  "source_describe": "$SOURCE_DESCRIBE",
  "rust_toolchain": "$RUST_TOOLCHAIN",
  "target": "$TARGET",
  "feature_profile": "$FEATURE_PROFILE",
  "bundled_plugins": true,
  "package_readme": "README.md",
  "archive": "$(basename "$ARCHIVE")",
  "sha256": "$ARCHIVE_SHA256"
}
EOF
