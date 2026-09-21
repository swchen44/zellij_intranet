[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath
)

$ErrorActionPreference = "Stop"
$TempRoot = $null
$RuntimeRoot = $null
try {
    if (Test-Path $InputPath -PathType Leaf) {
        if (-not $InputPath.EndsWith(".zip", [StringComparison]::OrdinalIgnoreCase)) { throw "input must be a ZIP or package directory" }
        $TempRoot = Join-Path $env:TEMP ("zellij-verify-{0}" -f ([guid]::NewGuid().ToString("N")))
        New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
        Expand-Archive -LiteralPath $InputPath -DestinationPath $TempRoot -Force
        $NestedPackageRoot = Join-Path $TempRoot "zellij-x86_64-pc-windows-msvc"
        if (Test-Path (Join-Path $NestedPackageRoot "zellij.exe") -PathType Leaf) {
            $PackageRoot = $NestedPackageRoot
        } else {
            $PackageRoot = $TempRoot
        }
    } elseif (Test-Path $InputPath -PathType Container) {
        $PackageRoot = (Resolve-Path $InputPath).Path
    } else {
        throw "package not found: $InputPath"
    }

    foreach ($required in @("zellij.exe", "README.md", "ZELLIJ-USER-GUIDE.md", "README.txt", "LICENSE.md", "BUILD-INFO.txt")) {
        if (-not (Test-Path (Join-Path $PackageRoot $required) -PathType Leaf)) { throw "missing package file: $required" }
    }

    $Readme = Get-Content (Join-Path $PackageRoot "README.md") -Raw
    foreach ($section in @("## Prerequisites", "## Add to PATH", "## Boundary", "## Links")) {
        if ($Readme -notmatch [regex]::Escape($section)) { throw "README.md missing section: $section" }
    }
    if ($Readme -notmatch "https://github.com/swchen44/zellij_intranet") {
        throw "README.md missing project GitHub link"
    }
    $Guide = Get-Content (Join-Path $PackageRoot "ZELLIJ-USER-GUIDE.md") -Raw
    foreach ($section in @("## 1. Help、版本與設定檢查", "## 3. 情境一：", "## 4. 情境二：", "## 官方資料來源")) {
        if ($Guide -notmatch [regex]::Escape($section)) { throw "ZELLIJ-USER-GUIDE.md missing section: $section" }
    }

    $BuildInfo = Get-Content (Join-Path $PackageRoot "BUILD-INFO.txt") -Raw
    $IsOfficial = $BuildInfo -match "source=official-zellij-release"
    if ($IsOfficial) {
        foreach ($required in @("version=", "source=", "variant=", "target=", "upstream_asset=", "upstream_binary_sha256=", "runtime_network_required=")) {
            if ($BuildInfo -notmatch [regex]::Escape($required)) { throw "BUILD-INFO.txt missing $required" }
        }
        if ($BuildInfo -notmatch "target=windows-x86_64") { throw "wrong official target in BUILD-INFO.txt" }
        if ($BuildInfo -notmatch "runtime_network_required=false") { throw "official package requires runtime network" }
    } else {
        foreach ($required in @("version=", "source_commit=", "source_describe=", "rust_toolchain=", "target=", "feature_profile=", "bundled_plugins=")) {
            if ($BuildInfo -notmatch [regex]::Escape($required)) { throw "BUILD-INFO.txt missing $required" }
        }
        if ($BuildInfo -notmatch "target=x86_64-pc-windows-msvc") { throw "wrong target in BUILD-INFO.txt" }
    }
    if ($BuildInfo -notmatch "bundled_plugins=true") { throw "builtin plugins are not declared bundled" }

    $Forbidden = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object {
        $_.FullName -match "\\target\\|\\.cargo\\|\\registry\\"
    }
    if ($Forbidden) { throw "build-only content found in package: $($Forbidden[0].FullName)" }

    $Binary = Join-Path $PackageRoot "zellij.exe"
    & $Binary --version
    if ($LASTEXITCODE -ne 0) { throw "zellij.exe --version failed" }
    & $Binary setup --check
    if ($LASTEXITCODE -ne 0) { throw "zellij.exe setup --check failed" }

    $RuntimeRoot = Join-Path $env:TEMP ("zellij-runtime-{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
    & $Binary setup --dump-layout default | Set-Content -Encoding utf8 (Join-Path $RuntimeRoot "default.kdl")
    if ((Get-Item (Join-Path $RuntimeRoot "default.kdl")).Length -eq 0) { throw "default layout dump is empty" }
    $PluginRoot = Join-Path $RuntimeRoot "plugins"
    & $Binary setup --dump-plugins $PluginRoot
    $PluginCount = @(Get-ChildItem -Path $PluginRoot -Recurse -Filter "*.wasm" -File).Count
    if ($PluginCount -lt 12) { throw "expected at least 12 bundled plugins, found $PluginCount" }

    if (Test-Path $InputPath -PathType Leaf) {
        $Checksum = "$InputPath.sha256"
        if (Test-Path $Checksum) {
            $Expected = ((Get-Content $Checksum -Raw) -split "\s+")[0].ToLowerInvariant()
            $Actual = (Get-FileHash -Algorithm SHA256 $InputPath).Hash.ToLowerInvariant()
            if ($Expected -ne $Actual) { throw "archive SHA-256 does not match companion checksum" }
        }

        $ManifestPath = [IO.Path]::ChangeExtension($InputPath, ".manifest.json")
        if (Test-Path $ManifestPath -PathType Leaf) {
            $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
            $Actual = (Get-FileHash -Algorithm SHA256 $InputPath).Hash.ToLowerInvariant()
            if ($IsOfficial) {
                if ($Manifest.target -ne "windows-x86_64") { throw "official manifest target is incorrect" }
                if ($Manifest.variant -ne "full" -and $Manifest.variant -ne "no-web") { throw "official manifest variant is invalid" }
                if ($Manifest.package_sha256.ToLowerInvariant() -ne $Actual) {
                    throw "official manifest package SHA-256 does not match archive"
                }
                if ($Manifest.package_readme -ne "README.md") { throw "official manifest README is incorrect" }
            } else {
                if ($Manifest.target -ne "x86_64-pc-windows-msvc") { throw "manifest target is incorrect" }
                if ($Manifest.feature_profile -ne "terminal-only") { throw "manifest feature profile is incorrect" }
                if ($Manifest.sha256.ToLowerInvariant() -ne $Actual) {
                    throw "manifest SHA-256 does not match archive"
                }
            }
        }
    }

    Write-Output "verification passed: target=x86_64-pc-windows-msvc plugins=$PluginCount"
} finally {
    if ($RuntimeRoot -and (Test-Path $RuntimeRoot)) { Remove-Item -Recurse -Force $RuntimeRoot }
    if ($TempRoot -and (Test-Path $TempRoot)) { Remove-Item -Recurse -Force $TempRoot }
}
