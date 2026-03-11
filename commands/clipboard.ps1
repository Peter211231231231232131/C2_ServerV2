$ProgressPreference = 'SilentlyContinue'
param(
    [string]$Action,
    [string]$Text = ""
)

# Load required assembly
Add-Type -AssemblyName System.Windows.Forms

if ($Action -eq "get") {
    try {
        $clip = [System.Windows.Forms.Clipboard]::GetText()
        if ($clip) {
            Write-Output $clip
        } else {
            Write-Output "Clipboard is empty."
        }
    } catch {
        Write-Output "❌ Failed to read clipboard: $_"
    }
}
elseif ($Action -eq "set") {
    if ($Text -eq "") {
        Write-Output "❌ Usage: clipboard set <text>"
        exit
    }
    try {
        [System.Windows.Forms.Clipboard]::SetText($Text)
        Write-Output "✅ Clipboard set."
    } catch {
        Write-Output "❌ Failed to set clipboard: $_"
    }
}
else {
    Write-Output "❌ Usage: clipboard [get|set <text>]"
}