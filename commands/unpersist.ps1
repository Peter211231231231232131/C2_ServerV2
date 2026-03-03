param($args)

$carrierFile = "C:\Users\Public\Desktop\desktop.ini"
$streamName = "thumbs.db"
$taskName = "WindowsUpdaterTask"

Write-Output "[+] Removing persistence..."

# 1. Remove the hidden stream (the agent inside desktop.ini)
if (Test-Path $carrierFile) {
    try {
        Remove-Item -Path $carrierFile -Stream $streamName -Force -ErrorAction Stop
        Write-Output "[+] Hidden stream '$streamName' removed from $carrierFile"
    } catch {
        Write-Output "[-] Failed to remove hidden stream (maybe it doesn't exist?)"
    }
} else {
    Write-Output "[-] Carrier file not found."
}

# 2. Delete the scheduled task
try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    $rootFolder.DeleteTask($taskName, 0)
    Write-Output "[+] Scheduled task '$taskName' deleted."
} catch {
    Write-Output "[-] Failed to delete scheduled task (maybe it doesn't exist?)"
}

# 3. Optionally delete any leftover temp agent (if running, it may be locked)
$tempAgent = "$env:TEMP\agent.exe"
if (Test-Path $tempAgent) {
    try {
        Remove-Item $tempAgent -Force -ErrorAction Stop
        Write-Output "[+] Removed leftover temporary agent from $tempAgent"
    } catch {
        Write-Output "[-] Could not remove $tempAgent (may be in use)."
    }
}

Write-Output ""
Write-Output "✅ UNPERSIST COMPLETE"
Write-Output "Reboot to verify the agent no longer starts automatically."