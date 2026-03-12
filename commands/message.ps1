$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
param(
    [string]$Text
)

# If no argument was passed, show usage
if (-not $Text) {
    Write-Output "Usage: message <text>"
    exit
}

# Load required assembly
Add-Type -AssemblyName System.Windows.Forms

# Show the message box (the pop‑up will appear on the target machine)
[System.Windows.Forms.MessageBox]::Show($Text, "Message from remote operator", "OK", [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

# Confirm to the operator that the message was displayed
Write-Output "✅ Message displayed on target."