$ProgressPreference    = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$VerbosePreference     = 'SilentlyContinue'
$DebugPreference       = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# ── Compute bounding box across ALL monitors ─────────────────────────────────
$allScreens  = [System.Windows.Forms.Screen]::AllScreens
$left        = ($allScreens | Measure-Object -Property { $_.Bounds.Left }   -Minimum).Minimum
$top         = ($allScreens | Measure-Object -Property { $_.Bounds.Top }    -Minimum).Minimum
$right       = ($allScreens | Measure-Object -Property { $_.Bounds.Right }  -Maximum).Maximum
$bottom      = ($allScreens | Measure-Object -Property { $_.Bounds.Bottom } -Maximum).Maximum

$totalWidth  = $right  - $left
$totalHeight = $bottom - $top

# ── Capture ──────────────────────────────────────────────────────────────────
$bitmap   = New-Object System.Drawing.Bitmap $totalWidth, $totalHeight
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($left, $top, 0, 0, (New-Object System.Drawing.Size($totalWidth, $totalHeight)))

# ── Encode ───────────────────────────────────────────────────────────────────
$ms     = New-Object System.IO.MemoryStream
$bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
$base64 = [System.Convert]::ToBase64String($ms.ToArray())

$graphics.Dispose()
$bitmap.Dispose()
$ms.Dispose()

Write-Output "FILE:screenshot.png"
Write-Output $base64
