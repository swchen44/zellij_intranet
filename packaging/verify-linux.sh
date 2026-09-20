#!/usr/bin/env bash
set -euo pipefail

INPUT="${1:-}"
[[ -n "$INPUT" ]] || {
	echo "Usage: packaging/verify-linux.sh <package-dir|archive.tar.gz>" >&2
	exit 2
}

TEMP_ROOT=""
cleanup() {
	[[ -z "$TEMP_ROOT" ]] || rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

if [[ -f "$INPUT" && "$INPUT" == *.tar.gz ]]; then
	TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zellij-verify.XXXXXX")"
	tar -xzf "$INPUT" -C "$TEMP_ROOT"
	PACKAGE_DIR="$TEMP_ROOT/zellij-x86_64-unknown-linux-musl"
elif [[ -d "$INPUT" ]]; then
	PACKAGE_DIR="$INPUT"
else
	echo "verify-linux: input is not a package directory or tar.gz: $INPUT" >&2
	exit 1
fi

die() {
	echo "verify-linux: $*" >&2
	exit 1
}

[[ -d "$PACKAGE_DIR" ]] || die "missing package root"
[[ -x "$PACKAGE_DIR/zellij" ]] || die "missing executable zellij"
[[ -f "$PACKAGE_DIR/README.txt" ]] || die "missing README.txt"
[[ -f "$PACKAGE_DIR/LICENSE.md" ]] || die "missing LICENSE.md"
[[ -f "$PACKAGE_DIR/BUILD-INFO.txt" ]] || die "missing BUILD-INFO.txt"

for required in version source_commit source_describe rust_toolchain target feature_profile bundled_plugins; do
	grep -Eq "^${required}=" "$PACKAGE_DIR/BUILD-INFO.txt" \
		|| die "BUILD-INFO.txt missing $required"
done
grep -Fxq 'target=x86_64-unknown-linux-musl' "$PACKAGE_DIR/BUILD-INFO.txt" \
	|| die "wrong target in BUILD-INFO.txt"
grep -Fxq 'bundled_plugins=true' "$PACKAGE_DIR/BUILD-INFO.txt" \
	|| die "builtin plugins are not declared bundled"

while IFS= read -r -d '' path; do
	relative="${path#$PACKAGE_DIR/}"
	case "$relative" in
		target/*|.cargo/*|*'/registry/'*|*'/registry/src/'*)
			die "build-only content found in package: $relative"
			;;
	esac
done < <(find "$PACKAGE_DIR" -type f -print0)

command -v file >/dev/null 2>&1 || die "file is required for verification"
command -v readelf >/dev/null 2>&1 || die "readelf is required for verification"
file_output="$(file "$PACKAGE_DIR/zellij")"
echo "$file_output"
echo "$file_output" | grep -Eiq 'ELF.*(x86-64|x86_64)' \
	|| die "binary is not Linux x86-64 according to file"
if readelf -lW "$PACKAGE_DIR/zellij" | grep -q ' INTERP '; then
	die "ELF interpreter found; expected static musl binary"
fi

"$PACKAGE_DIR/zellij" --version | tee "$PACKAGE_DIR/.verify-version.txt"
grep -q '0\.46\.0' "$PACKAGE_DIR/.verify-version.txt" \
	|| die "unexpected Zellij version"

RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zellij-runtime.XXXXXX")"
mkdir -p "$RUN_ROOT/home" "$RUN_ROOT/config" "$RUN_ROOT/cache" "$RUN_ROOT/plugins"
RUNTIME_ENV=(
	"HOME=$RUN_ROOT/home"
	"XDG_CONFIG_HOME=$RUN_ROOT/config"
	"XDG_CACHE_HOME=$RUN_ROOT/cache"
	"PATH=/usr/bin:/bin"
)
env -i "${RUNTIME_ENV[@]}" "$PACKAGE_DIR/zellij" setup --check
env -i "${RUNTIME_ENV[@]}" "$PACKAGE_DIR/zellij" setup --dump-layout default > "$RUN_ROOT/default.kdl"
[[ -s "$RUN_ROOT/default.kdl" ]] || die "default layout dump is empty"
env -i "${RUNTIME_ENV[@]}" "$PACKAGE_DIR/zellij" setup --dump-plugins "$RUN_ROOT/plugins"
plugin_count="$(find "$RUN_ROOT/plugins" -type f -name '*.wasm' | wc -l | tr -d ' ')"
((plugin_count >= 12)) || die "expected at least 12 bundled plugins, found $plugin_count"

rm -f "$PACKAGE_DIR/.verify-version.txt"
rm -rf "$RUN_ROOT"
echo "verification passed: target=x86_64-unknown-linux-musl plugins=$plugin_count"
