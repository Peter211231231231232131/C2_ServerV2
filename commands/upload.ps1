$ProgressPreference = 'SilentlyContinue'
param(
    [string]$Path
)

# Remove surrounding double quotes if present
$Path = $Path -replace '^"|"$', ''

if (-not $Path) {
    Write-Output "Usage: upload <filepath>"
    exit
}

if (Test-Path $Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $filename = Split-Path $Path -Leaf
    Write-Output "FILE:$filename"
    Write-Output $base64
} else {
    Write-Output "File not found: $Path"
}