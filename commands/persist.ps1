param($args)

$agentPath = $env:AgentPath
if (-not $agentPath) {
    Write-Output "❌ AgentPath environment variable not set."
    exit
}

$taskName = "WindowsUpdaterTask"

try {
    # Connect to Task Scheduler
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    $rootFolder = $taskService.GetFolder("\")

    # Create a new task definition
    $taskDefinition = $taskService.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = "Windows Updater Task"
    $taskDefinition.Principal.UserId = $env:USERNAME
    $taskDefinition.Principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN

    # Create a logon trigger
    $trigger = $taskDefinition.Triggers.Create(9) # TASK_TRIGGER_LOGON
    $trigger.UserId = $env:USERNAME

    # Create an action to run the agent
    $action = $taskDefinition.Actions.Create(0) # TASK_ACTION_EXEC
    $action.Path = $agentPath

    # Register the task (6 = UpdateOrCreate, 3 = InteractiveToken)
    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, 3) | Out-Null

    Write-Output "✅ Scheduled task '$taskName' created via COM. Agent will run at next logon."
} catch {
    Write-Output "❌ Failed to create task: $_"
}