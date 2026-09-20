[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath
)

$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "verify-windows.ps1") -InputPath $InputPath
