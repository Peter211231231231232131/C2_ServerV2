-- screenshot.lua
-- Captures a screenshot and sends it to the Discord channel

send_message("📸 Taking screenshot...")

local err = take_screenshot()
if err then
    send_message("❌ Screenshot failed: " .. err)
else
    send_message("✅ Screenshot taken and sent.")
end