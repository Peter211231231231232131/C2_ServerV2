param($args)

$taskName = "WindowsUpdaterTask"

try {
    schtasks /delete /tn $taskName /f | Out-Null
    Write-Output "✅ Scheduled task '$taskName' deleted."
} catch {
    Write-Output "❌ Failed to delete task (maybe it doesn't exist?)."
}