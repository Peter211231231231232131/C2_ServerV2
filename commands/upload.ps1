$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
param($args)

$path = $args -join ' '
if (-not $path) {
    Write-Output "Usage: upload <filepath>"
    exit
}

if (Test-Path $path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $filename = Split-Path $path -Leaf
    Write-Output "FILE:$filename"
    Write-Output $base64
} else {
    Write-Output "File not found: $path"
}