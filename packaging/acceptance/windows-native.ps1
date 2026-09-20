[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Archive
)

$ErrorActionPreference = "Stop"
$Verifier = Join-Path $PSScriptRoot "..\verify-package.ps1"
& $Verifier -InputPath $Archive
Write-Output "Automated Windows package smoke passed. Continue the manual Windows Terminal/ConPTY checklist in windows-native.md."
