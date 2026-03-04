param(
    [string]$Url
)

if (-not $Url) {
    Write-Output "Usage: wallpaper <image-url>"
    exit
}

# Function to set wallpaper using P/Invoke
function Set-Wallpaper {
    param([string]$ImagePath)
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    [Wallpaper]::SystemParametersInfo(20, 0, $ImagePath, 0x01 -bor 0x02) | Out-Null
}

# Download the image to a temporary file
$tempFile = [System.IO.Path]::GetTempFileName() + ".jpg"
try {
    Invoke-WebRequest -Uri $Url -OutFile $tempFile -ErrorAction Stop
} catch {
    Write-Output "❌ Failed to download image: $_"
    exit
}

# Set as wallpaper
Set-Wallpaper -ImagePath $tempFile

# Confirm success
Write-Output "✅ Wallpaper changed to: $Url"