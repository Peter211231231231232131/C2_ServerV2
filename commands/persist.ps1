# ---- 3. Scheduled task using only schtasks (logon + every 3 hours) ----
$taskName = "WindowsUpdaterTask"
$xmlFile = "$env:TEMP\task_$taskName.xml"

# Delete existing task if present
schtasks /delete /tn $taskName /f *>$null 2>&1

# Build the XML with both triggers (Logon + Daily repeat every 3 hours)
$xmlContent = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <UserId>{0}</UserId>
      <Enabled>true</Enabled>
    </LogonTrigger>
    <CalendarTrigger>
      <Repetition>
        <Interval>PT3H</Interval>
        <Duration>P0D</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>{1}</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>{0}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>P3D</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"{2}"</Arguments>
    </Exec>
  </Actions>
</Task>
'@

# Fill placeholders: userId, start boundary (now), vbsPath
$startBoundary = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
$finalXml = $xmlContent -f $env:USERNAME, $startBoundary, $vbsPath

# Write XML file with correct UTF-16 LE encoding
# Use "unicode" (not "UTF16") – that's UTF-16 LE with BOM
[System.IO.File]::WriteAllText($xmlFile, $finalXml, [System.Text.UnicodeEncoding]::new($false, $true))

# Import task via schtasks
schtasks /create /tn $taskName /xml "$xmlFile" /f *>$null 2>&1

if ($LASTEXITCODE -eq 0) {
    $taskCreated = $true
    Write-Output "✅ Task '$taskName' created with logon + every-3-hour triggers."
} else {
    $taskCreated = $false
    Write-Output "❌ schtasks failed (exit code: $LASTEXITCODE)."
}

# Cleanup
Remove-Item $xmlFile -Force -ErrorAction SilentlyContinue
