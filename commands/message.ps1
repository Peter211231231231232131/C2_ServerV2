param(
    [string]$Text
)

$ProgressPreference    = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$VerbosePreference     = 'SilentlyContinue'
$DebugPreference       = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

if (-not $Text) {
    Write-Output "Usage: message <text>"
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Form ────────────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Message"
$form.Size            = New-Object System.Drawing.Size(420, 220)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.BackColor       = [System.Drawing.Color]::FromArgb(245, 245, 245)
$form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

# ── Coloured header strip ────────────────────────────────────────────────────
$header = New-Object System.Windows.Forms.Panel
$header.Size      = New-Object System.Drawing.Size(420, 6)
$header.Location  = New-Object System.Drawing.Point(0, 0)
$header.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)   # Windows blue
$form.Controls.Add($header)

# ── Icon ────────────────────────────────────────────────────────────────────
$icon = New-Object System.Windows.Forms.PictureBox
$icon.Size     = New-Object System.Drawing.Size(32, 32)
$icon.Location = New-Object System.Drawing.Point(20, 28)
$icon.Image    = [System.Drawing.SystemIcons]::Information.ToBitmap()
$icon.SizeMode = "StretchImage"
$form.Controls.Add($icon)

# ── Title label ─────────────────────────────────────────────────────────────
$title = New-Object System.Windows.Forms.Label
$title.Text      = "Message from remote operator"
$title.Location  = New-Object System.Drawing.Point(62, 28)
$title.Size      = New-Object System.Drawing.Size(330, 18)
$title.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.Controls.Add($title)

# ── Message label ───────────────────────────────────────────────────────────
$msg = New-Object System.Windows.Forms.Label
$msg.Text      = $Text
$msg.Location  = New-Object System.Drawing.Point(62, 52)
$msg.Size      = New-Object System.Drawing.Size(330, 70)
$msg.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$msg.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$form.Controls.Add($msg)

# ── Separator ───────────────────────────────────────────────────────────────
$sep = New-Object System.Windows.Forms.Panel
$sep.Size      = New-Object System.Drawing.Size(420, 1)
$sep.Location  = New-Object System.Drawing.Point(0, 136)
$sep.BackColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$form.Controls.Add($sep)

# ── OK button ───────────────────────────────────────────────────────────────
$btn = New-Object System.Windows.Forms.Button
$btn.Text          = "OK"
$btn.Size          = New-Object System.Drawing.Size(88, 30)
$btn.Location      = New-Object System.Drawing.Point(314, 150)
$btn.FlatStyle     = "Flat"
$btn.BackColor     = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btn.ForeColor     = [System.Drawing.Color]::White
$btn.Font          = New-Object System.Drawing.Font("Segoe UI", 9)
$btn.FlatAppearance.BorderSize = 0
$btn.DialogResult  = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $btn
$form.Controls.Add($btn)

# ── Show ────────────────────────────────────────────────────────────────────
[void]$form.ShowDialog()

Write-Output "✅ Message displayed on target."
