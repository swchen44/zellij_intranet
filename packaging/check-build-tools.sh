#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-x86_64-unknown-linux-musl}"
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN="${ZELLIJ_RUST_TOOLCHAIN:-1.95.0}"

if [[ -f "${HOME:-}/.cargo/env" ]]; then
	# Non-interactive SSH commands do not load rustup's environment automatically.
	# shellcheck disable=SC1090
	source "${HOME}/.cargo/env"
fi

die() {
	echo "check-build-tools: $*" >&2
	exit 1
}

case "$TARGET" in
	x86_64-unknown-linux-musl) ;;
	*) die "unsupported Linux target: $TARGET" ;;
esac

required=(git rustc cargo rustup protoc tar gzip file readelf sha256sum)
missing=()
for tool in "${required[@]}"; do
	command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
command -v musl-gcc >/dev/null 2>&1 || missing+=(musl-gcc)

if ((${#missing[@]})); then
	die "missing build tools: ${missing[*]}"
fi

rustup run "$TOOLCHAIN" rustc --version >/dev/null 2>&1 \
	|| die "Rust toolchain $TOOLCHAIN is not installed; run rustup toolchain install $TOOLCHAIN"

rustup target list --installed --toolchain "$TOOLCHAIN" | grep -Fxq wasm32-wasip1 \
	|| die "Rust target wasm32-wasip1 is not installed for $TOOLCHAIN"
rustup target list --installed --toolchain "$TOOLCHAIN" | grep -Fxq "$TARGET" \
	|| die "Rust target $TARGET is not installed for $TOOLCHAIN"

printf 'root=%s\n' "$ROOT"
printf 'target=%s\n' "$TARGET"
printf 'rust_toolchain=%s\n' "$TOOLCHAIN"
printf 'rustc=%s\n' "$(rustup run "$TOOLCHAIN" rustc --version)"
printf 'cargo=%s\n' "$(rustup run "$TOOLCHAIN" cargo --version)"
printf 'protoc=%s\n' "$(protoc --version)"
printf 'musl_gcc=%s\n' "$(musl-gcc --version | head -n 1)"
