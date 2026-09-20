[CmdletBinding()]
param(
    [string]$Target = "x86_64-pc-windows-msvc"
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\")).Path
$Toolchain = if ($env:ZELLIJ_RUST_TOOLCHAIN) { $env:ZELLIJ_RUST_TOOLCHAIN } else { "1.95.0" }
$ExpectedVersion = "0.46.0"
$ExpectedCommit = "474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb"
$ExpectedDescribe = "v0.44.1-122-g474ea0cef"
$FeatureProfile = "terminal-only"

if ($Target -ne "x86_64-pc-windows-msvc") { throw "unsupported Windows target: $Target" }
Set-Location $Root

$commit = (git rev-parse HEAD).Trim()
$describe = (git describe --tags --always).Trim()
$version = (Select-String -Path (Join-Path $Root "Cargo.toml") -Pattern '^version = "([^"]+)"' | Select-Object -First 1).Matches.Groups[1].Value
if ($commit -ne $ExpectedCommit) { throw "source commit is not $ExpectedCommit" }
if ($describe -ne $ExpectedDescribe) { throw "source describe is not $ExpectedDescribe" }
if ($version -ne $ExpectedVersion) { throw "source version is $version, expected $ExpectedVersion" }

foreach ($tool in @("git", "cargo", "rustc", "rustup", "protoc", "nasm", "cl", "link")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "missing build tool: $tool" }
}

rustup run $Toolchain rustc --version | Out-Null
if (-not ((rustup target list --installed --toolchain $Toolchain) -contains "wasm32-wasip1")) { throw "wasm32-wasip1 is not installed" }
if (-not ((rustup target list --installed --toolchain $Toolchain) -contains $Target)) { throw "$Target is not installed" }

$env:CARGO_BUILD_JOBS = if ($env:ZELLIJ_WINDOWS_BUILD_JOBS) { $env:ZELLIJ_WINDOWS_BUILD_JOBS } else { "1" }
$env:CARGO_INCREMENTAL = "0"
$env:RUSTFLAGS = "-C target-feature=+crt-static"
$env:CL_FLAGS = if ($env:CL_FLAGS) { "$env:CL_FLAGS /MT" } else { "/MT" }
$env:CFLAGS = if ($env:CFLAGS) { "$env:CFLAGS /MT" } else { "/MT" }
$env:CXXFLAGS = if ($env:CXXFLAGS) { "$env:CXXFLAGS /MT" } else { "/MT" }

Write-Host "[build-windows] source=$ExpectedDescribe commit=$ExpectedCommit target=$Target"
Write-Host "[build-windows] rust=$Toolchain jobs=$env:CARGO_BUILD_JOBS profile=$FeatureProfile,crt-static"

cargo "+$Toolchain" xtask build --release --plugins-only
cargo "+$Toolchain" build --locked --release --no-default-features --features plugins_from_target

$Binary = Join-Path $Root "target\release\zellij.exe"
if (-not (Test-Path -Path $Binary -PathType Leaf)) { throw "missing Windows release binary: $Binary" }
& $Binary --version
Write-Host "[build-windows] binary=$Binary"
