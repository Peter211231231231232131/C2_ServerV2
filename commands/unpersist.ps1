param($args)

$taskName = "WindowsUpdaterTask"

try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    $rootFolder.DeleteTask($taskName, 0)
    Write-Output "✅ Scheduled task '$taskName' deleted via COM."
} catch {
    Write-Output "❌ Failed to delete task (maybe it doesn't exist?)."
}