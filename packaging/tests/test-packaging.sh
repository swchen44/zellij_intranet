#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGING="$ROOT/packaging"

fail() {
	echo "test-packaging: $*" >&2
	exit 1
}

require_file() {
	[[ -f "$1" ]] || fail "missing file: ${1#$ROOT/}"
}

require_executable() {
	[[ -x "$1" ]] || fail "missing executable: ${1#$ROOT/}"
}

require_file "$PACKAGING/targets.toml"
require_file "$ROOT/README.md"
require_file "$ROOT/docs/ZELLIJ-USER-GUIDE.md"
require_file "$PACKAGING/OFFICIAL-BINARY.md"
require_file "$PACKAGING/BUILDING-OFFLINE.md"
require_file "$PACKAGING/package_official.py"
require_file "$PACKAGING/make-download-test-zips.py"
require_file "$PACKAGING/tests/test_official_package.py"
require_file "$PACKAGING/tests/test_download_variants.py"
require_executable "$PACKAGING/check-build-tools.sh"
require_executable "$PACKAGING/build-linux.sh"
require_executable "$PACKAGING/package-linux.sh"
require_executable "$PACKAGING/verify-linux.sh"
require_executable "$PACKAGING/manifest.sh"
require_executable "$PACKAGING/verify-package.sh"
require_executable "$PACKAGING/acceptance/linux-matrix.sh"
require_executable "$PACKAGING/acceptance/ssh-linux.sh"
require_executable "$PACKAGING/check-windows-local-tools.sh"
require_executable "$PACKAGING/build-windows-local.sh"
require_executable "$PACKAGING/package-windows-local.sh"
require_executable "$PACKAGING/manifest-windows.sh"
require_file "$PACKAGING/build-windows.ps1"
require_file "$PACKAGING/package-windows.ps1"
require_file "$PACKAGING/verify-windows.ps1"
require_file "$PACKAGING/verify-package.ps1"
require_file "$ROOT/docs/superpowers/specs/2026-09-21-zellij-offline-bundle-design.md"
require_file "$ROOT/docs/superpowers/plans/2026-09-21-zellij-offline-bundle.md"
require_file "$ROOT/docs/superpowers/specs/2026-09-24-zellij-flat-bin-design.md"
require_file "$ROOT/docs/superpowers/plans/2026-09-24-zellij-flat-bin.md"
require_file "$ROOT/docs/plans/2026-09-21-zellij-windows-acceptance.md"
require_file "$ROOT/docs/plans/2026-09-22-zellij-download-block-test-plan.md"

grep -Fq 'linux_targets = ["x86_64-unknown-linux-musl"]' "$PACKAGING/targets.toml" \
	|| fail "Linux target is not fixed to x86_64-unknown-linux-musl"
grep -Fq 'official_release_version = "0.45.1"' "$PACKAGING/targets.toml" \
	|| fail "official release baseline is not recorded"
grep -Fq 'official_variant = "full"' "$PACKAGING/targets.toml" \
	|| fail "official default variant is not recorded"
grep -Fq 'bundled_plugins = true' "$PACKAGING/targets.toml" \
	|| fail "bundled plugin policy is not enabled"
grep -Fq 'CARGO_BUILD_JOBS=1' "$PACKAGING/build-linux.sh" \
	|| fail "low-memory build does not force one Cargo job"
grep -Fq 'x86_64-pc-windows-msvc' "$PACKAGING/targets.toml" \
	|| fail "Windows target is not fixed to x86_64-pc-windows-msvc"
grep -Fq 'xwin build' "$PACKAGING/build-windows-local.sh" \
	|| fail "local Mac Windows candidate does not use cargo-xwin"
grep -Fq '+crt-static' "$PACKAGING/build-windows-local.sh" \
	|| fail "Windows candidate does not request static CRT"
grep -Fq '/MT' "$PACKAGING/build-windows-local.sh" \
	|| fail "Windows candidate does not request static C/C++ CRT"
grep -Fq 'Compress-Archive' "$PACKAGING/package-windows.ps1" \
	|| fail "Windows package script does not create ZIP"
grep -Fq 'Get-FileHash' "$PACKAGING/verify-windows.ps1" \
	|| fail "Windows verifier does not validate SHA-256"
grep -Fq 'zellij_bin' "$PACKAGING/verify-windows.ps1" \
	|| fail "Windows verifier does not detect flat-bin root"
grep -Fq 'six-file contract' "$PACKAGING/verify-windows.ps1" \
	|| fail "Windows verifier does not enforce package file contract"
grep -Fq 'README.md' "$PACKAGING/package_official.py" \
	|| fail "official packager does not include README.md"
grep -Fq 'flat-bin' "$PACKAGING/package_official.py" \
	|| fail "official packager does not include flat-bin layout"
grep -Fq 'zellij_bin' "$PACKAGING/package_official.py" \
	|| fail "official packager does not include zellij_bin root"
grep -Fq 'ZELLIJ-USER-GUIDE.md' "$PACKAGING/package_official.py" \
	|| fail "official packager does not include the user guide"
grep -Fq 'README.md' "$PACKAGING/package-linux.sh" \
	|| fail "Linux source fallback does not include README.md"
grep -Fq 'ZELLIJ-USER-GUIDE.md' "$PACKAGING/package-linux.sh" \
	|| fail "Linux source fallback does not include the user guide"
grep -Fq 'README.md' "$PACKAGING/package-windows-local.sh" \
	|| fail "Windows local fallback does not include README.md"
grep -Fq 'ZELLIJ-USER-GUIDE.md' "$PACKAGING/package-windows-local.sh" \
	|| fail "Windows local fallback does not include the user guide"
python3 "$PACKAGING/make-download-test-zips.py" --help >/dev/null \
	|| fail "diagnostic ZIP packager does not run"
grep -Fq '/dist/official/*.tar.gz' "$ROOT/.gitignore" \
	|| fail "release tarballs are not protected from Git commits"
grep -Fq '/dist/official/*.zip' "$ROOT/.gitignore" \
	|| fail "release ZIPs are not protected from Git commits"

bash -n \
	"$PACKAGING/check-build-tools.sh" \
	"$PACKAGING/build-linux.sh" \
	"$PACKAGING/package-linux.sh" \
	"$PACKAGING/verify-linux.sh" \
	"$PACKAGING/manifest.sh" \
	"$PACKAGING/verify-package.sh" \
	"$PACKAGING/acceptance/linux-matrix.sh" \
	"$PACKAGING/acceptance/ssh-linux.sh" \
	"$PACKAGING/check-windows-local-tools.sh" \
	"$PACKAGING/build-windows-local.sh" \
	"$PACKAGING/package-windows-local.sh" \
	"$PACKAGING/manifest-windows.sh"

python3 "$PACKAGING/tests/test_official_package.py"
python3 "$PACKAGING/tests/test_download_variants.py"

echo "test-packaging: passed"
