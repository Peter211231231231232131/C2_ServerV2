param($args)
$action = $args[0]
$text = $args[1..$args.Count] -join ' '
if ($action -eq 'get') {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::GetText()
} elseif ($action -eq 'set') {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::SetText($text)
    "Clipboard set."
} else {
    "Usage: clipboard [get|set <text>]"
}