[CmdletBinding()]
param(
    [string]$Target = "x86_64-pc-windows-msvc"
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\")).Path
$Version = "0.46.0"
$SourceCommit = "474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb"
$SourceDescribe = "v0.44.1-122-g474ea0cef"
$RustToolchain = "1.95.0"
$FeatureProfile = "terminal-only"
$Name = "zellij-$Target"
$Dist = Join-Path $Root "dist"
$Stage = Join-Path $Dist $Name
$Archive = Join-Path $Dist "$Name.zip"
$Manifest = Join-Path $Dist "$Name.manifest.json"
$Checksum = Join-Path $Dist "$Name.zip.sha256"
$Binary = Join-Path $Root "target\release\zellij.exe"

if ($Target -ne "x86_64-pc-windows-msvc") { throw "unsupported Windows target: $Target" }
Set-Location $Root
if ((git rev-parse HEAD).Trim() -ne $SourceCommit) { throw "source commit mismatch" }
if (-not (Test-Path -Path $Binary -PathType Leaf)) { throw "missing binary: $Binary; run packaging/build-windows.ps1" }

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item $Binary (Join-Path $Stage "zellij.exe")
Copy-Item (Join-Path $Root "LICENSE.md") (Join-Path $Stage "LICENSE.md")

@"
Zellij $Version portable Windows package

Target: $Target
Source: $SourceDescribe ($SourceCommit)
Build method: native Windows MSVC
Feature profile: $FeatureProfile (no default features; plugins_from_target)

Run .\zellij.exe --version or .\zellij.exe setup --check in Windows Terminal.
This package does not include Rust, Cargo, Yazi, Claude Code, Codex, SSH, or a shell.
Builtin WASM plugins are embedded in the zellij binary and do not require network access.
The web/share capability is excluded from this terminal-only package; it is not needed for
Windows Terminal + Zellij + Yazi usage.
"@ | Set-Content -Encoding utf8 (Join-Path $Stage "README.txt")

@"
product=zellij
version=$Version
source_commit=$SourceCommit
source_describe=$SourceDescribe
rust_toolchain=$RustToolchain
target=$Target
feature_profile=$FeatureProfile
bundled_plugins=true
build_method=windows-native-msvc
runtime_verification=pending
build_jobs=$(if ($env:ZELLIJ_WINDOWS_BUILD_JOBS) { $env:ZELLIJ_WINDOWS_BUILD_JOBS } else { "1" })
"@ | Set-Content -Encoding ascii (Join-Path $Stage "BUILD-INFO.txt")

if (Test-Path $Archive) { Remove-Item -Force $Archive }
Compress-Archive -Path $Stage -DestinationPath $Archive -Force
$Hash = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
"$Hash  $([IO.Path]::GetFileName($Archive))" | Set-Content -Encoding ascii $Checksum

$ManifestObject = [ordered]@{
    product = "zellij"
    version = $Version
    source_commit = $SourceCommit
    source_describe = $SourceDescribe
    rust_toolchain = $RustToolchain
    target = $Target
    feature_profile = $FeatureProfile
    bundled_plugins = $true
    archive = [IO.Path]::GetFileName($Archive)
    sha256 = $Hash
    build_method = "windows-native-msvc"
    runtime_verification = "pending"
}
$ManifestObject | ConvertTo-Json | Set-Content -Encoding utf8 $Manifest

Write-Output $Archive
Write-Output $Manifest
Write-Output $Checksum
