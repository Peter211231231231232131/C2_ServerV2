param($args)

$carrierFile = "C:\Windows\Temp\~DF539A.tmp"
$streamName = "thumbs.db"
$taskName = "WindowsUpdaterTask"
$tempAgent = "$env:TEMP\agent.exe"

Write-Output "[+] Removing persistence..."

# 1. Remove the hidden stream from the carrier file
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

# 2. Delete the scheduled task using COM (no admin needed)
try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    $rootFolder.DeleteTask($taskName, 0)
    Write-Output "[+] Scheduled task '$taskName' deleted."
} catch {
    Write-Output "[-] Failed to delete scheduled task (maybe it doesn't exist?)"
}

# 3. Optionally delete the carrier file itself (comment out if you want to keep it)
if (Test-Path $carrierFile) {
    try {
        Remove-Item $carrierFile -Force -ErrorAction Stop
        Write-Output "[+] Carrier file deleted: $carrierFile"
    } catch {
        Write-Output "[-] Could not delete carrier file."
    }
}

# 4. Remove any leftover temporary agent
if (Test-Path $tempAgent) {
    try {
        Remove-Item $tempAgent -Force -ErrorAction Stop
        Write-Output "[+] Removed temporary agent: $tempAgent"
    } catch {
        Write-Output "[-] Could not remove $tempAgent (may be in use)."
    }
}

Write-Output ""
Write-Output "✅ UNPERSIST COMPLETE"
Write-Output "Reboot to verify the agent no longer starts automatically."