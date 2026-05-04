param(
    [string]$Text
)

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

if (-not $Text) {
    Write-Output "Usage: message <text>"
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Message from remote operator"
$form.Size = New-Object System.Drawing.Size(400,200)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true   # 🔥 Always on top

# Label (text)
$label = New-Object System.Windows.Forms.Label
$label.Text = $Text
$label.AutoSize = $false
$label.Size = New-Object System.Drawing.Size(360,100)
$label.Location = New-Object System.Drawing.Point(20,20)
$label.TextAlign = "MiddleCenter"

# Button
$button = New-Object System.Windows.Forms.Button
$button.Text = "Ok bro"
$button.Size = New-Object System.Drawing.Size(80,30)
$button.Location = New-Object System.Drawing.Point(150,120)
$button.Add_Click({ $form.Close() })

# Add controls
$form.Controls.Add($label)
$form.Controls.Add($button)

# Show dialog (forces focus)
$form.ShowDialog() | Out-Null

Write-Output "✅ Message displayed on target."
