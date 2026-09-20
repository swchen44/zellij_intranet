#!/usr/bin/env bash
set -euo pipefail

TARGET="x86_64-pc-windows-msvc"
TOOLCHAIN="${ZELLIJ_RUST_TOOLCHAIN:-1.95.0}"
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING="$ROOT/packaging"
EXPECTED_VERSION="0.46.0"
EXPECTED_COMMIT="474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb"
EXPECTED_DESCRIBE="v0.44.1-122-g474ea0cef"
FEATURE_PROFILE="terminal-only"

if [[ -f "${HOME:-}/.cargo/env" ]]; then
	# shellcheck disable=SC1090
	source "${HOME}/.cargo/env"
fi

# Keep the build aligned with the preflight check on macOS, where Homebrew's
# LLVM is keg-only and Apple's clang is otherwise found first.
for llvm_bin in /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
	if [[ -d "$llvm_bin" ]]; then
		export PATH="$llvm_bin:$PATH"
		break
	fi
done

die() {
	echo "build-windows-local: $*" >&2
	exit 1
}

cd "$ROOT"
[[ "$(git rev-parse HEAD)" == "$EXPECTED_COMMIT" ]] \
	|| die "source commit is not $EXPECTED_COMMIT"
[[ "$(git describe --tags --always)" == "$EXPECTED_DESCRIBE" ]] \
	|| die "source describe is not $EXPECTED_DESCRIBE"
version="$(sed -n 's/^version = "\([^"]*\)"/\1/p' Cargo.toml | head -n 1)"
[[ "$version" == "$EXPECTED_VERSION" ]] || die "source version is $version, expected $EXPECTED_VERSION"

"$PACKAGING/check-windows-local-tools.sh"

export CARGO_BUILD_JOBS="${ZELLIJ_WINDOWS_BUILD_JOBS:-1}"
export CARGO_INCREMENTAL=0
export RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=+crt-static"
export XWIN_CROSS_COMPILER="${XWIN_CROSS_COMPILER:-clang-cl}"

echo "[build-windows-local] source=$EXPECTED_DESCRIBE commit=$EXPECTED_COMMIT target=$TARGET"
echo "[build-windows-local] rust=$TOOLCHAIN jobs=$CARGO_BUILD_JOBS compiler=$XWIN_CROSS_COMPILER features=$FEATURE_PROFILE"
echo "[build-windows-local] candidate only: runtime verification must run on Windows"

# Generate protobufs and bundled WASM plugins with the fixed Rust toolchain.
cargo "+$TOOLCHAIN" xtask build --release --plugins-only
plugin_count="$(find zellij-utils/assets/plugins -type f -name '*.wasm' | wc -l | tr -d ' ')"
((plugin_count >= 12)) || die "expected at least 12 bundled plugin assets, found $plugin_count"

# cargo-xwin supplies the MSVC-compatible Windows SDK/CRT sysroot on macOS.
# cargo-xwin appends the sysroot library directory to CFLAGS. With newer
# Homebrew LLVM, aws-lc-sys's -Werror feature probes treat that compile-only
# `-L` as an error; preserve the flag but downgrade only that diagnostic. `/MT`
# is also required for C/C++ crates; Rust `+crt-static` alone does not change
# their default CRT selection.
export CL_FLAGS="${CL_FLAGS:-} /MT"
export CFLAGS="${CFLAGS:-} -Wno-error=unused-command-line-argument /MT"
export CXXFLAGS="${CXXFLAGS:-} /MT"
cargo "+$TOOLCHAIN" xwin build --locked --release --target "$TARGET" \
	--no-default-features --features plugins_from_target

binary="target/$TARGET/release/zellij.exe"
[[ -f "$binary" ]] || die "missing Windows release binary: $binary"
file_output="$(file "$binary")"
echo "$file_output"
echo "$file_output" | grep -Eiq 'PE32\+.*x86-64' \
	|| die "binary is not a Windows x86-64 PE32+ executable according to file"
imports="$(llvm-objdump -p "$binary")"
if echo "$imports" | grep -Eiq 'DLL Name: (VCRUNTIME|MSVCP|api-ms-win-crt)'; then
	die "binary still imports Visual C++ runtime DLLs; /MT/static CRT was not applied"
fi
echo "[build-windows-local] binary=$ROOT/$binary plugins=$plugin_count"
