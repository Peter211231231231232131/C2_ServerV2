param(
    [string]$Path
)

if (-not $Path) {
    Write-Output "❌ No path received. Raw args: $args"
    exit
}

Write-Output "📁 Path received: $Path"

if (Test-Path $Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $filename = Split-Path $Path -Leaf
    Write-Output "FILE:$filename"
    Write-Output $base64
} else {
    Write-Output "❌ File not found: $Path"
}