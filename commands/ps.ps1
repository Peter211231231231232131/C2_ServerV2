$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
param($args)  # args are ignored for this command

# Get all processes, sort by PID, select relevant properties
Get-Process | Select-Object Id, ProcessName, CPU, WorkingSet | Sort-Object Id | Format-Table -AutoSize