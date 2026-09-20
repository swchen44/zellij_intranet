#!/usr/bin/env bash
set -euo pipefail

TARGET="x86_64-pc-windows-msvc"
TOOLCHAIN="${ZELLIJ_RUST_TOOLCHAIN:-1.95.0}"
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${HOME:-}/.cargo/env" ]]; then
	# Non-interactive shells do not load rustup's environment automatically.
	# shellcheck disable=SC1090
	source "${HOME}/.cargo/env"
fi

# Homebrew's LLVM is keg-only on macOS. Prefer it over Apple's clang so
# cargo-xwin uses the compiler that understands the Windows SDK/CRT sysroot.
for llvm_bin in /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
	if [[ -d "$llvm_bin" ]]; then
		export PATH="$llvm_bin:$PATH"
		break
	fi
done

die() {
	echo "check-windows-local-tools: $*" >&2
	exit 1
}

required=(git rustc cargo rustup zip file llvm-objdump clang-cl protoc)
missing=()
for tool in "${required[@]}"; do
	command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
((${#missing[@]} == 0)) || die "missing tools: ${missing[*]}"

rustup run "$TOOLCHAIN" rustc --version >/dev/null 2>&1 \
	|| die "Rust toolchain $TOOLCHAIN is not installed"
rustup target list --installed --toolchain "$TOOLCHAIN" | grep -Fxq wasm32-wasip1 \
	|| die "Rust target wasm32-wasip1 is not installed for $TOOLCHAIN"
rustup target list --installed --toolchain "$TOOLCHAIN" | grep -Fxq "$TARGET" \
	|| die "Rust target $TARGET is not installed for $TOOLCHAIN"
rustup component list --installed --toolchain "$TOOLCHAIN" | grep -Eq '^llvm-tools(-[^ ]+)?$' \
	|| die "Rust component llvm-tools-preview (reported as llvm-tools-<host>) is not installed for $TOOLCHAIN"

cargo "+$TOOLCHAIN" xwin --version >/dev/null 2>&1 \
	|| die "cargo-xwin is not installed for $TOOLCHAIN; run cargo +$TOOLCHAIN install --locked cargo-xwin"

printf 'root=%s\n' "$ROOT"
printf 'target=%s\n' "$TARGET"
printf 'rust_toolchain=%s\n' "$TOOLCHAIN"
printf 'rustc=%s\n' "$(rustup run "$TOOLCHAIN" rustc --version)"
printf 'cargo=%s\n' "$(rustup run "$TOOLCHAIN" cargo --version)"
printf 'cargo_xwin=%s\n' "$(cargo "+$TOOLCHAIN" xwin --version 2>&1 | head -n 1)"
printf 'clang_cl=%s\n' "$(clang-cl --version | head -n 1)"
printf 'llvm_objdump=%s\n' "$(llvm-objdump --version | head -n 1)"
printf 'nasm=%s\n' "$(nasm -v 2>&1 | head -n 1)"
