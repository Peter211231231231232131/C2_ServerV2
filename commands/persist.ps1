# ---- 3. Scheduled task with logon + every 3 hours ----
$taskName = "WindowsUpdaterTask"
$taskCreated = $false

try {
    # Try COM first (more reliable for multiple triggers)
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")
    try { $rootFolder.DeleteTask($taskName, 0) *>$null } catch { }

    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3  # Run only when user is logged on
    $taskDefinition.Settings.StopIfGoingOnBatteries = $false
    $taskDefinition.Settings.DisallowStartIfOnBatteries = $false
    $taskDefinition.Settings.AllowDemandStart = $true

    # Trigger 1: At logon
    $logonTrigger = $taskDefinition.Triggers.Create(9)  # TASK_TRIGGER_LOGON = 9
    $logonTrigger.UserId = $env:USERNAME
    $logonTrigger.Enabled = $true

    # Trigger 2: Every 3 hours (repeat indefinitely)
    $timeTrigger = $taskDefinition.Triggers.Create(2)  # TASK_TRIGGER_DAILY = 2? No, actually 2 is TASK_TRIGGER_TIME (one-time). But we want a daily trigger with repetition.
    # Better: Use TASK_TRIGGER_DAILY = 2, then set repetition. Let's do it properly:
    # Actually trigger type 2 is TASK_TRIGGER_DAILY. We set StartBoundary to now, then repetition every 3 hours.
    $dailyTrigger = $taskDefinition.Triggers.Create(2)
    $dailyTrigger.Enabled = $true
    $dailyTrigger.Repetition.Interval = "PT3H"   # 3 hours
    $dailyTrigger.Repetition.Duration = "P0D"    # Indefinite
    $dailyTrigger.Repetition.StopAtDurationEnd = $false
    # Set start time to midnight today so it runs from now onward
    $startTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $dailyTrigger.StartBoundary = $startTime

    # Action: same as before
    $action = $taskDefinition.Actions.Create(0)
    $action.Path = "wscript.exe"
    $action.Arguments = "`"$vbsPath`""

    # Register task
    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null
    $taskCreated = $true
    Write-Output "✅ Task created with logon + every-3-hour triggers (COM method)."
} catch {
    # Fallback to schtasks.exe for old or locked systems
    Write-Output "COM failed, falling back to schtasks..."
    schtasks /delete /tn $taskName /f *>$null 2>&1
    # Create task with two triggers: at logon and every 3 hours (sc minute /mo 180)
    # schtasks doesn't easily support two triggers in one command, so we create first, then add second trigger via XML or separate command.
    # Simpler: create a task that runs at logon AND repeats every 3 hours using /sc onlogon /ri PT3H /du 9999:59
    # But /ri (repetition interval) only works with /sc minute, hourly, daily, etc., not with onlogon.
    # Workaround: create two separate tasks? No, user wants one task. Let's use XML.
    $xmlTemplate = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <UserId>$env:USERNAME</UserId>
      <Enabled>true</Enabled>
    </LogonTrigger>
    <CalendarTrigger>
      <Repetition>
        <Interval>PT3H</Interval>
        <Duration>P0D</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$(Get-Date -Format "yyyy-MM-ddTHH:mm:ss")</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$env:USERNAME</UserId>
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
      <Arguments>"$vbsPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $xmlFile = "$env:TEMP\task_$taskName.xml"
    $xmlTemplate | Out-File -FilePath $xmlFile -Encoding UTF16
    schtasks /create /tn $taskName /xml "$xmlFile" /f *>$null 2>&1
    if ($LASTEXITCODE -eq 0) { 
        $taskCreated = $true
        Write-Output "✅ Task created via XML (logon + every 3 hours)."
    } else {
        Write-Output "❌ schtasks XML failed."
    }
    Remove-Item $xmlFile -Force -ErrorAction SilentlyContinue
}
