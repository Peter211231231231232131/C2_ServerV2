param($args)

$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regName = "WindowsUpdater"

if (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $regPath -Name $regName
    Write-Output "✅ Persistence removed."
} else {
    Write-Output "ℹ️ No persistence key found."
}