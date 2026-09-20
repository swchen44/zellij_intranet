#!/usr/bin/env bash
set -euo pipefail

TARGET="x86_64-unknown-linux-musl"
TOOLCHAIN="${ZELLIJ_RUST_TOOLCHAIN:-1.95.0}"
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING="$ROOT/packaging"
EXPECTED_VERSION="0.46.0"
EXPECTED_COMMIT="474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb"
EXPECTED_DESCRIBE="v0.44.1-122-g474ea0cef"

if [[ -f "${HOME:-}/.cargo/env" ]]; then
	# Non-interactive SSH commands do not load rustup's environment automatically.
	# shellcheck disable=SC1090
	source "${HOME}/.cargo/env"
fi

die() {
	echo "build-linux: $*" >&2
	exit 1
}

cd "$ROOT"
[[ "$(git rev-parse HEAD)" == "$EXPECTED_COMMIT" ]] \
	|| die "source commit is not $EXPECTED_COMMIT"
[[ "$(git describe --tags --always)" == "$EXPECTED_DESCRIBE" ]] \
	|| die "source describe is not $EXPECTED_DESCRIBE"
version="$(sed -n 's/^version = "\([^"]*\)"/\1/p' Cargo.toml | head -n 1)"
[[ "$version" == "$EXPECTED_VERSION" ]] || die "source version is $version, expected $EXPECTED_VERSION"

"$PACKAGING/check-build-tools.sh" "$TARGET"

export CARGO_BUILD_JOBS=1
export CARGO_INCREMENTAL=0
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER="${CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER:-musl-gcc}"
export CC_x86_64_unknown_linux_musl="${CC_x86_64_unknown_linux_musl:-musl-gcc}"

# The one-CPU runner has limited RAM. Keep an optimized release binary while
# avoiding upstream LTO/codegen settings that create a large rustc peak.
export CARGO_PROFILE_RELEASE_LTO=false
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
export CARGO_PROFILE_RELEASE_OPT_LEVEL=2

echo "[build] source=$EXPECTED_DESCRIBE commit=$EXPECTED_COMMIT target=$TARGET"
echo "[build] rust=$TOOLCHAIN jobs=$CARGO_BUILD_JOBS profile=lto:false,codegen-units:16,opt-level:2"

# This is the air-gapped-safe equivalent of the upstream cross pipeline:
# generate protobufs and compile builtin plugins first, then compile the
# native musl binary with the preinstalled linker. It never installs cross.
cargo +"$TOOLCHAIN" xtask build --release --plugins-only

plugin_count="$(find zellij-utils/assets/plugins -type f -name '*.wasm' | wc -l | tr -d ' ')"
((plugin_count >= 12)) || die "expected at least 12 bundled plugin assets, found $plugin_count"

cargo +"$TOOLCHAIN" build --locked --release --target "$TARGET"

binary="target/$TARGET/release/zellij"
[[ -x "$binary" ]] || die "missing release binary: $binary"
file "$binary"
if readelf -lW "$binary" | grep -q ' INTERP '; then
	die "unexpected ELF interpreter; binary is not static"
fi
"$binary" --version
echo "[build] binary=$ROOT/$binary plugins=$plugin_count"
