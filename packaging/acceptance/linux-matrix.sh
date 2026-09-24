#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/dist/official/zellij-v0.45.1-full-x86_64-unknown-linux-musl-flat-bin.tar.gz}"
HOST="${ZELLIJ_SSH_HOST:-surfer}"
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
RECORD="$ROOT/packaging/acceptance/linux-matrix.md"

[[ -f "$ARCHIVE" ]] || {
	echo "linux-matrix: archive not found: $ARCHIVE" >&2
	exit 1
}

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
inventory="$(ssh "${ssh_opts[@]}" "$HOST" '
set -eu
printf "architecture="; uname -m
printf "kernel="; uname -srm
printf "long_bit="; getconf LONG_BIT
printf "os="; sed -n "s/^PRETTY_NAME=//p" /etc/os-release
')"

architecture="$(printf '%s\n' "$inventory" | sed -n 's/^architecture=//p')"
[[ "$architecture" == x86_64 ]] || {
	echo "linux-matrix: unsupported remote architecture: $architecture" >&2
	exit 1
}

baseline_path="$(ssh "${ssh_opts[@]}" "$HOST" 'command -v zellij || true')"
baseline_version="$(ssh "${ssh_opts[@]}" "$HOST" 'zellij --version 2>/dev/null || true')"
remote_tmp="$(ssh "${ssh_opts[@]}" "$HOST" 'mktemp -d "${TMPDIR:-/tmp}/zellij-package.XXXXXX"')"
case "$remote_tmp" in
	/tmp/zellij-package.*|/var/tmp/zellij-package.*) ;;
	*) echo "linux-matrix: unsafe temporary path: $remote_tmp" >&2; exit 1 ;;
esac

cleanup() {
	ssh "${ssh_opts[@]}" "$HOST" "rm -rf -- '$remote_tmp'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ssh "${ssh_opts[@]}" "$HOST" "tar -xzf - -C '$remote_tmp'" < "$ARCHIVE"
if ssh "${ssh_opts[@]}" "$HOST" "test -x '$remote_tmp/zellij_bin/zellij'"; then
	package_dir="$remote_tmp/zellij_bin"
elif ssh "${ssh_opts[@]}" "$HOST" "test -x '$remote_tmp/zellij'"; then
	package_dir="$remote_tmp"
else
	package_dir="$remote_tmp/zellij-x86_64-unknown-linux-musl"
fi
remote_result="$(ssh "${ssh_opts[@]}" "$HOST" "
set -eu
test -x '$package_dir/zellij'
test -f '$package_dir/BUILD-INFO.txt'
test -f '$package_dir/README.md'
grep -Fq '## Prerequisites' '$package_dir/README.md'
grep -Fq '## Add to PATH' '$package_dir/README.md'
grep -Fq '## Boundary' '$package_dir/README.md'
grep -Fq '## Links' '$package_dir/README.md'
mkdir -p '$remote_tmp/home' '$remote_tmp/config' '$remote_tmp/cache'
file '$package_dir/zellij'
if readelf -lW '$package_dir/zellij' | grep -q ' INTERP '; then exit 1; fi
HOME='$remote_tmp/home' XDG_CONFIG_HOME='$remote_tmp/config' XDG_CACHE_HOME='$remote_tmp/cache' '$package_dir/zellij' --version
HOME='$remote_tmp/home' XDG_CONFIG_HOME='$remote_tmp/config' XDG_CACHE_HOME='$remote_tmp/cache' '$package_dir/zellij' setup --check
HOME='$remote_tmp/home' XDG_CONFIG_HOME='$remote_tmp/config' XDG_CACHE_HOME='$remote_tmp/cache' '$package_dir/zellij' setup --dump-layout default > '$remote_tmp/default.kdl'
test -s '$remote_tmp/default.kdl'
HOME='$remote_tmp/home' XDG_CONFIG_HOME='$remote_tmp/config' XDG_CACHE_HOME='$remote_tmp/cache' '$package_dir/zellij' setup --dump-plugins '$remote_tmp/plugins'
count=\$(find '$remote_tmp/plugins' -type f -name '*.wasm' | wc -l | tr -d ' ')
test \"\$count\" -ge 12
printf 'plugin_count=%s\\n' \"\$count\"
if grep -Fxq 'Variant: full' '$package_dir/README.txt'; then
	HOME='$remote_tmp/home' XDG_CONFIG_HOME='$remote_tmp/config' XDG_CACHE_HOME='$remote_tmp/cache' '$package_dir/zellij' web --help > '$remote_tmp/web-help'
	grep -Eq '(^|[[:space:]])status([[:space:]]|$)' '$remote_tmp/web-help'
	printf 'web_variant=full\\n'
else
	printf 'web_variant=disabled\\n'
fi
")"

after_path="$(ssh "${ssh_opts[@]}" "$HOST" 'command -v zellij || true')"
after_version="$(ssh "${ssh_opts[@]}" "$HOST" 'zellij --version 2>/dev/null || true')"
[[ "$after_path" == "$baseline_path" && "$after_version" == "$baseline_version" ]] \
	|| {
		echo "linux-matrix: existing Zellij baseline changed" >&2
		echo "before: $baseline_path / $baseline_version" >&2
		echo "after: $after_path / $after_version" >&2
		exit 1
	}

mkdir -p "$(dirname "$RECORD")"
{
	echo "# Linux x86_64 Zellij acceptance"
	echo
	echo "- Test time: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	echo "- SSH host alias: \`$HOST\`"
	echo "- Artifact: \`$(basename "$ARCHIVE")\`"
	echo "- Mapping: \`$HOST $architecture → x86_64-unknown-linux-musl\`"
	echo "- Existing Zellij path before test: \`${baseline_path:-absent}\`"
	echo "- Existing Zellij version before test: \`${baseline_version:-absent}\`"
	echo
	echo '```text'
printf '%s\n' "$inventory"
printf '%s\n' "$remote_result"
echo '```'
} > "$RECORD"

echo "linux-matrix: passed; evidence written to $RECORD"
