param(
    [string]$Text
)

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

# If no argument was passed, show usage
if (-not $Text) {
    Write-Output "Usage: message <text>"
    exit
}

# Load required assembly
Add-Type -AssemblyName System.Windows.Forms

# Show the message box
[System.Windows.Forms.MessageBox]::Show($Text, "Message from remote operator", "OK", [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

Write-Output "✅ Message displayed on target."
