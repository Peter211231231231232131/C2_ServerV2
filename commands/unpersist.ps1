$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
param($args)

$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$fontFile = "$fontDir\seguibl.ttf"
$launcherPath = "$fontDir\run.ps1"
$taskName = "WindowsUpdaterTask"

Write-Output "[+] Removing persistence..."

# 1. Delete the scheduled task (via COM, fallback to schtasks)
try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    $rootFolder.DeleteTask($taskName, 0)
    Write-Output "[+] Scheduled task '$taskName' deleted via COM."
} catch {
    schtasks /delete /tn $taskName /f *>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "[+] Scheduled task '$taskName' deleted via schtasks."
    } else {
        Write-Output "[-] Scheduled task not found or could not be deleted."
    }
}

# 2. Remove the hidden ADS from the font file
if (Test-Path $fontFile) {
    try {
        Remove-Item -Path $fontFile -Stream "Zone.Identifier" -Force -ErrorAction Stop
        Write-Output "[+] Hidden ADS removed from $fontFile"
    } catch {
        Write-Output "[-] No hidden ADS found on $fontFile"
    }
} else {
    Write-Output "[-] Font file not found: $fontFile"
}

# 3. Delete the launcher script
if (Test-Path $launcherPath) {
    Remove-Item $launcherPath -Force
    Write-Output "[+] Deleted launcher script: $launcherPath"
} else {
    Write-Output "[-] Launcher script not found: $launcherPath"
}

# 4. Optional: Delete any leftover temp agent.exe from previous runs
$tempAgent = "$env:TEMP\agent.exe"
if (Test-Path $tempAgent) {
    Remove-Item $tempAgent -Force -ErrorAction SilentlyContinue
    Write-Output "[+] Removed temporary agent: $tempAgent"
}

Write-Output ""
Write-Output "✅ UNPERSIST COMPLETE"
Write-Output "All known persistence traces have been removed."