#!/usr/bin/env bash
set -euo pipefail

INPUT="${1:-}"
[[ -n "$INPUT" ]] || {
	echo "Usage: packaging/verify-package.sh <package-dir|archive.tar.gz>" >&2
	exit 2
}

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/packaging/verify-linux.sh" "$INPUT"

if [[ -f "$INPUT" && "$INPUT" == *.tar.gz ]]; then
	manifest="${INPUT%.tar.gz}.manifest.json"
	checksum="$INPUT.sha256"
	[[ -f "$manifest" ]] || {
		echo "verify-package: missing companion manifest: $manifest" >&2
		exit 1
	}
	[[ -f "$checksum" ]] || {
		echo "verify-package: missing checksum: $checksum" >&2
		exit 1
	}
	(
		cd "$(dirname "$INPUT")"
		sha256sum -c "$(basename "$checksum")"
	)
	grep -Fq '"product": "zellij"' "$manifest"
	grep -Fq '"target": "x86_64-unknown-linux-musl"' "$manifest"
	grep -Fq '"bundled_plugins": true' "$manifest"
	archive_sha256="$(sha256sum "$INPUT" | awk '{print $1}')"
	grep -Fq "\"sha256\": \"$archive_sha256\"" "$manifest" \
		|| {
			echo "verify-package: manifest SHA-256 does not match archive" >&2
			exit 1
		}
fi

echo "package verification passed"
