#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/dist/zellij-x86_64-unknown-linux-musl.tar.gz}"
HOST="${ZELLIJ_SSH_HOST:-surfer}"

[[ -f "$ARCHIVE" ]] || {
	echo "ssh-linux: archive not found: $ARCHIVE" >&2
	exit 1
}

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
remote_tmp="$(ssh "${ssh_opts[@]}" "$HOST" 'mktemp -d "${TMPDIR:-/tmp}/zellij-ssh.XXXXXX"')"
case "$remote_tmp" in
	/tmp/zellij-ssh.*|/var/tmp/zellij-ssh.*) ;;
	*) echo "ssh-linux: unsafe temporary path: $remote_tmp" >&2; exit 1 ;;
esac

cleanup() {
	ssh "${ssh_opts[@]}" "$HOST" "rm -rf -- '$remote_tmp'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ssh "${ssh_opts[@]}" "$HOST" "tar -xzf - -C '$remote_tmp'" < "$ARCHIVE"
if ssh "${ssh_opts[@]}" "$HOST" "test -x '$remote_tmp/zellij'"; then
	package_dir="$remote_tmp"
else
	package_dir="$remote_tmp/zellij-x86_64-unknown-linux-musl"
fi
runtime_home="$remote_tmp/home"
runtime_config="$remote_tmp/config"
runtime_cache="$remote_tmp/cache"

ssh "${ssh_opts[@]}" "$HOST" \
	"mkdir -p '$runtime_home' '$runtime_config' '$runtime_cache'"

echo "Starting sandbox Zellij on $HOST. Detach or exit normally to finish."
ssh -tt "${ssh_opts[@]}" "$HOST" \
	"cd '$package_dir' && HOME='$runtime_home' XDG_CONFIG_HOME='$runtime_config' XDG_CACHE_HOME='$runtime_cache' exec ./zellij --session zellij-intranet-smoke"
