import discord
from discord import app_commands
from discord.ext import commands, tasks
import os
import asyncio
from aiohttp import web
from datetime import datetime, timezone, timedelta
import re
import time
import logging

# ------------------- CONFIGURATION -------------------
BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
GUILD_ID = int(os.getenv("DISCORD_GUILD_ID", 0))
CONTROL_CHANNEL_NAME = os.getenv("CONTROL_CHANNEL", "control")
AGENT_CHANNEL_PREFIX = os.getenv("AGENT_PREFIX", "agent-")
STALE_THRESHOLD_MINUTES = int(os.getenv("STALE_THRESHOLD_MINUTES", 5))
PORT = int(os.getenv("PORT", 10000))

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

# ------------------- BOT SETUP -------------------
intents = discord.Intents.default()
intents.message_content = True
intents.guilds = True
intents.messages = True

class MyBot(commands.Bot):
    def __init__(self):
        super().__init__(command_prefix="!", intents=intents)
        # self.tree is already created by the base class – do NOT reassign it

    async def setup_hook(self):
        # Sync commands to the specific guild (instant)
        guild = discord.Object(id=GUILD_ID)
        self.tree.copy_global_to(guild=guild)
        await self.tree.sync(guild=guild)
        logger.info("Slash commands synced")

bot = MyBot()

# ------------------- HTTP HEALTH SERVER -------------------
async def handle_health(request):
    return web.Response(text="OK")

app = web.Application()
app.router.add_get("/", handle_health)
app.router.add_get("/health", handle_health)

async def start_http_server():
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()
    logger.info(f"Health check server running on port {PORT}")

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

# ------------------- SLASH COMMANDS -------------------
async def send_command_to_agent(interaction: discord.Interaction, command_text: str):
    """Send a command message to the agent's channel."""
    channel = interaction.channel
    if not channel.name.startswith(AGENT_CHANNEL_PREFIX):
        await interaction.response.send_message(
            "This command can only be used in an agent channel.",
            ephemeral=True
        )
        return False
    # Send a message that the agent will recognize
    await channel.send(f"[CMD] {command_text}")
    await interaction.response.send_message(
        f"✅ Command `{command_text}` sent to agent.",
        ephemeral=True
    )
    return True

@bot.tree.command(name="run", description="Execute a shell command on the agent")
async def run_command(interaction: discord.Interaction, command: str):
    await send_command_to_agent(interaction, f"run {command}")

@bot.tree.command(name="screenshot", description="Capture a screenshot from the agent")
async def screenshot_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "screenshot")

@bot.tree.command(name="kill", description="Terminate the agent")
async def kill_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "kill")

# ------------------- CONTROL CHANNEL COMMANDS (optional, keep for backward compat) -------------------
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
