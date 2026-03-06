param($args)

$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$fontFile = "$fontDir\seguibl.ttf"
$launcherPath = "$fontDir\run.ps1"
$shortcutPath = "$([Environment]::GetFolderPath('Startup'))\WindowsUpdate.lnk"

Write-Output "[+] Removing persistence..."

# Remove startup shortcut
if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-Output "[+] Removed shortcut"
}

# Remove hidden stream from font file
if (Test-Path $fontFile) {
    Remove-Item -Path $fontFile -Stream "Zone.Identifier" -Force -ErrorAction SilentlyContinue
    Write-Output "[+] Removed hidden stream from font file"
    
    # Optional: delete the font file entirely
    Remove-Item $fontFile -Force -ErrorAction SilentlyContinue
    Write-Output "[+] Deleted font file"
}

# Remove launcher script
if (Test-Path $launcherPath) {
    Remove-Item $launcherPath -Force
    Write-Output "[+] Removed launcher script"
}

Write-Output ""
Write-Output "✅ UNPERSIST COMPLETE"