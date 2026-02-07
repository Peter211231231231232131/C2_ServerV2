#!/usr/bin/env python3
"""
ENHANCED SAFE MANAGEMENT SERVER
Educational purpose only - Now with more features!
"""

from flask import Flask, request, jsonify, render_template_string, send_file
import hashlib
import hmac
import json
import time
import os
import sqlite3
import threading
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import secrets
import uuid
from collections import defaultdict
import qrcode
import io
import base64

# ============================================
# ENHANCED CONFIGURATION
# ============================================
SAFE_COMMANDS = [
    "get_system_info",      # Get basic system info
    "get_disk_usage",       # Get disk usage (limited)
    "list_processes_safe",  # List processes (limited)
    "echo",                 # Echo a message
    "get_network_info",     # Get network info
    "get_time",             # Get current time
    "get_status",           # Get client status
    "ping",                 # Simple ping response
    "get_geo_info",         # Get geolocation info (simulated)
]

# Enhanced client database
class ClientManager:
    def __init__(self):
        self.conn = sqlite3.connect(':memory:', check_same_thread=False)
        self.setup_database()
        self.client_stats = defaultdict(lambda: {'command_count': 0, 'last_active': None})
    
    def setup_database(self):
        cursor = self.conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS clients (
                client_id TEXT PRIMARY KEY,
                hostname TEXT,
                os TEXT,
                arch TEXT,
                ip_address TEXT,
                first_seen TIMESTAMP,
                last_seen TIMESTAMP,
                status TEXT,
                version TEXT,
                tags TEXT
            )
        ''')
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS command_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                client_id TEXT,
                command_id TEXT,
                command TEXT,
                params TEXT,
                output TEXT,
                timestamp TIMESTAMP,
                status TEXT,
                execution_time REAL
            )
        ''')
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS server_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                level TEXT,
                message TEXT,
                timestamp TIMESTAMP,
                source TEXT
            )
        ''')
        self.conn.commit()
    
    def log_message(self, level: str, message: str, source: str = "server"):
        cursor = self.conn.cursor()
        cursor.execute('''
            INSERT INTO server_logs (level, message, timestamp, source)
            VALUES (?, ?, ?, ?)
        ''', (level, message, datetime.now(), source))
        self.conn.commit()

# ============================================
# ENHANCED SERVER IMPLEMENTATION
# ============================================

class EnhancedManagementServer:
    def __init__(self, host='127.0.0.1', port=8080, secret_key=None):
        """
        Initialize ENHANCED management server
        """
        self.host = host
        self.port = port
        self.secret_key = secret_key or secrets.token_hex(32)
        self.app = Flask(__name__)
        self.client_manager = ClientManager()
        self.command_queues = {}
        self.server_stats = {
            'start_time': datetime.now(),
            'total_requests': 0,
            'total_clients': 0,
            'total_commands': 0
        }
        
        self.setup_routes()
        self.start_background_tasks()
        
        print(f"\n{'='*60}")
        print(f"🚀 ENHANCED SAFE MANAGEMENT SERVER")
        print(f"{'='*60}")
        print(f"🌐 URL: https://c2-serverv2.onrender.com")
        print(f"📊 Dashboard: Real-time monitoring enabled")
        print(f"🔐 Auth: DISABLED (for testing)")
        print(f"📈 Features: Analytics, QR Codes, Logging")
        print(f"{'='*60}")
        print("⚠️  EDUCATIONAL PURPOSES ONLY - SAFE COMMANDS")
        print(f"{'='*60}\n")
    
    def start_background_tasks(self):
        """Start background cleanup and monitoring"""
        def cleanup_old_clients():
            while True:
                time.sleep(300)  # Every 5 minutes
                self.cleanup_inactive_clients()
        
        def update_stats():
            while True:
                time.sleep(60)  # Every minute
                self.update_server_stats()
        
        threading.Thread(target=cleanup_old_clients, daemon=True).start()
        threading.Thread(target=update_stats, daemon=True).start()
    
    def cleanup_inactive_clients(self):
        """Remove clients inactive for more than 30 minutes"""
        cutoff = datetime.now() - timedelta(minutes=30)
        cursor = self.client_manager.conn.cursor()
        cursor.execute('DELETE FROM clients WHERE last_seen < ?', (cutoff,))
        deleted = cursor.rowcount
        if deleted > 0:
            self.client_manager.log_message("INFO", f"Cleaned up {deleted} inactive clients")
        self.client_manager.conn.commit()
    
    def update_server_stats(self):
        """Update server statistics"""
        cursor = self.client_manager.conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM clients WHERE status = "active"')
        active_clients = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM command_history')
        total_commands = cursor.fetchone()[0]
        
        self.server_stats['active_clients'] = active_clients
        self.server_stats['total_commands'] = total_commands
        self.server_stats['uptime'] = str(datetime.now() - self.server_stats['start_time'])
    
    def verify_signature(self, client_id: str, data: str, signature: str) -> bool:
        """Verify HMAC signature - DISABLED FOR NOW"""
        # ⚠️ Temporarily disabled for testing
        return True  # Always return True to skip authentication
        
        # To re-enable authentication later, uncomment:
        # expected_signature = hmac.new(
        #     self.secret_key.encode(),
        #     data.encode(),
        #     hashlib.sha256
        # ).hexdigest()
        # return hmac.compare_digest(signature, expected_signature)
    
    def register_client(self, client_data: Dict) -> Tuple[bool, str]:
        """Register or update client with enhanced info"""
        client_id = client_data.get('client_id', 'unknown')
        if client_id == 'unknown':
            client_id = f"auto-{uuid.uuid4().hex[:8]}"
        
        cursor = self.client_manager.conn.cursor()
        
        # Check if client exists
        cursor.execute('SELECT * FROM clients WHERE client_id = ?', (client_id,))
        existing = cursor.fetchone()
        
        if existing:
            # Update existing client
            cursor.execute('''
                UPDATE clients SET 
                last_seen = ?, os = ?, arch = ?, ip_address = ?, status = ?
                WHERE client_id = ?
            ''', (
                datetime.now(),
                client_data.get('os', 'unknown'),
                client_data.get('arch', 'unknown'),
                request.remote_addr,
                'active',
                client_id
            ))
        else:
            # Insert new client
            cursor.execute('''
                INSERT INTO clients 
                (client_id, hostname, os, arch, ip_address, first_seen, last_seen, status, version, tags)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                client_id,
                client_data.get('hostname', 'unknown'),
                client_data.get('os', 'unknown'),
                client_data.get('arch', 'unknown'),
                request.remote_addr,
                datetime.now(),
                datetime.now(),
                'active',
                client_data.get('version', '1.0'),
                json.dumps(client_data.get('tags', []))
            ))
            self.server_stats['total_clients'] += 1
        
        self.client_manager.conn.commit()
        
        # Log the connection
        self.client_manager.log_message("INFO", 
            f"Client {client_id} connected from {request.remote_addr}")
        
        return True, "Client registered/updated"
    
    def get_pending_commands(self, client_id: str) -> List[Dict]:
        """Get pending commands for a client"""
        if client_id not in self.command_queues:
            return []
        
        commands = self.command_queues[client_id].copy()
        self.command_queues[client_id] = []  # Clear after sending
        
        # Log command delivery
        for cmd in commands:
            self.log_command(client_id, cmd['command_id'], cmd['action'], 'SENT')
        
        return commands
    
    def queue_command(self, client_id: str, action: str, params: Dict = None) -> Optional[str]:
        """Queue a command for a client"""
        if action not in SAFE_COMMANDS:
            return f"Command '{action}' is not in safe whitelist"
        
        if client_id not in self.command_queues:
            self.command_queues[client_id] = []
        
        command_id = f"cmd-{uuid.uuid4().hex[:8]}"
        command = {
            'command_id': command_id,
            'action': action,
            'params': params or {},
            'timestamp': int(time.time())
        }
        
        self.command_queues[client_id].append(command)
        
        # Log
        self.client_manager.log_message("INFO", 
            f"Command '{action}' queued for {client_id} (ID: {command_id})")
        
        return command_id
    
    def log_command(self, client_id: str, command_id: str, command: str, status: str):
        """Log command execution"""
        cursor = self.client_manager.conn.cursor()
        cursor.execute('''
            INSERT INTO command_history 
            (client_id, command_id, command, timestamp, status)
            VALUES (?, ?, ?, ?, ?)
        ''', (client_id, command_id, command, datetime.now(), status))
        self.client_manager.conn.commit()
    
    def log_command_result(self, client_id: str, command_id: str, command: str, 
                          output: str, status: str, execution_time: float = 0.0):
        """Log command execution result"""
        cursor = self.client_manager.conn.cursor()
        cursor.execute('''
            INSERT INTO command_history 
            (client_id, command_id, command, params, output, timestamp, status, execution_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            client_id, command_id, command.get('action', 'unknown'),
            json.dumps(command.get('params', {})), 
            output[:1000],  # Limit output size
            datetime.now(), 
            status, 
            execution_time
        ))
        self.client_manager.conn.commit()
        self.server_stats['total_commands'] += 1
    
    def generate_qr_code(self, data: str):
        """Generate QR code for client connection"""
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(data)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to base64 for HTML embedding
        buffered = io.BytesIO()
        img.save(buffered, format="PNG")
        img_str = base64.b64encode(buffered.getvalue()).decode()
        
        return f"data:image/png;base64,{img_str}"
    
    # ============================================
    # ENHANCED FLASK ROUTES
    # ============================================
    
    def setup_routes(self):
        """Setup all HTTP routes"""
        
        @self.app.route('/')
        def index():
            """Enhanced Dashboard"""
            cursor = self.client_manager.conn.cursor()
            
            # Get active clients
            cursor.execute('''
                SELECT client_id, hostname, os, arch, ip_address, 
                       first_seen, last_seen, status, tags
                FROM clients 
                WHERE status = "active"
                ORDER BY last_seen DESC
            ''')
            clients = cursor.fetchall()
            
            # Get recent commands
            cursor.execute('''
                SELECT client_id, command, status, timestamp, execution_time
                FROM command_history 
                ORDER BY timestamp DESC 
                LIMIT 20
            ''')
            history = cursor.fetchall()
            
            # Get server stats
            cursor.execute('SELECT COUNT(*) FROM clients WHERE status = "active"')
            active_clients = cursor.fetchone()[0]
            
            cursor.execute('SELECT COUNT(*) FROM command_history')
            total_commands = cursor.fetchone()[0]
            
            cursor.execute('''
                SELECT command, COUNT(*) as count 
                FROM command_history 
                GROUP BY command 
                ORDER BY count DESC 
                LIMIT 10
            ''')
            popular_commands = cursor.fetchall()
            
            # Generate QR code for easy mobile access
            qr_code = self.generate_qr_code(f"https://c2-serverv2.onrender.com")
            
            html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>🚀 Enhanced Management Server</title>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    body { 
                        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
                        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                        color: #333;
                        line-height: 1.6;
                    }
                    .container { 
                        max-width: 1400px; 
                        margin: 0 auto; 
                        padding: 20px;
                    }
                    .header {
                        background: white;
                        padding: 30px;
                        border-radius: 15px;
                        margin-bottom: 30px;
                        box-shadow: 0 10px 30px rgba(0,0,0,0.1);
                        display: flex;
                        justify-content: space-between;
                        align-items: center;
                    }
                    .header h1 { 
                        color: #2d3748;
                        font-size: 2.5rem;
                    }
                    .header .subtitle {
                        color: #718096;
                        font-size: 1.1rem;
                        margin-top: 5px;
                    }
                    .stats-grid {
                        display: grid;
                        grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                        gap: 20px;
                        margin-bottom: 30px;
                    }
                    .stat-card {
                        background: white;
                        padding: 25px;
                        border-radius: 12px;
                        box-shadow: 0 5px 15px rgba(0,0,0,0.08);
                        transition: transform 0.3s ease;
                    }
                    .stat-card:hover {
                        transform: translateY(-5px);
                    }
                    .stat-card h3 {
                        color: #4a5568;
                        font-size: 0.9rem;
                        text-transform: uppercase;
                        letter-spacing: 1px;
                        margin-bottom: 10px;
                    }
                    .stat-card .value {
                        font-size: 2.5rem;
                        font-weight: bold;
                        color: #2d3748;
                    }
                    .stat-card.green { border-left: 5px solid #48bb78; }
                    .stat-card.blue { border-left: 5px solid #4299e1; }
                    .stat-card.purple { border-left: 5px solid #9f7aea; }
                    .stat-card.orange { border-left: 5px solid #ed8936; }
                    
                    .section {
                        background: white;
                        padding: 30px;
                        border-radius: 15px;
                        margin-bottom: 30px;
                        box-shadow: 0 10px 30px rgba(0,0,0,0.1);
                    }
                    .section h2 {
                        color: #2d3748;
                        margin-bottom: 20px;
                        padding-bottom: 10px;
                        border-bottom: 2px solid #e2e8f0;
                    }
                    
                    table {
                        width: 100%;
                        border-collapse: collapse;
                        margin: 20px 0;
                    }
                    th {
                        background: #f7fafc;
                        padding: 15px;
                        text-align: left;
                        font-weight: 600;
                        color: #4a5568;
                        border-bottom: 2px solid #e2e8f0;
                    }
                    td {
                        padding: 15px;
                        border-bottom: 1px solid #e2e8f0;
                    }
                    tr:hover {
                        background: #f7fafc;
                    }
                    
                    .badge {
                        display: inline-block;
                        padding: 5px 12px;
                        border-radius: 20px;
                        font-size: 0.85rem;
                        font-weight: 600;
                    }
                    .badge.success { background: #c6f6d5; color: #22543d; }
                    .badge.warning { background: #feebc8; color: #744210; }
                    .badge.error { background: #fed7d7; color: #742a2a; }
                    .badge.info { background: #bee3f8; color: #2a4365; }
                    
                    .command-form {
                        background: #f7fafc;
                        padding: 20px;
                        border-radius: 10px;
                        margin-top: 20px;
                    }
                    .form-group {
                        margin-bottom: 15px;
                    }
                    label {
                        display: block;
                        margin-bottom: 5px;
                        font-weight: 600;
                        color: #4a5568;
                    }
                    input, select, textarea {
                        width: 100%;
                        padding: 12px;
                        border: 2px solid #e2e8f0;
                        border-radius: 8px;
                        font-size: 1rem;
                        transition: border-color 0.3s ease;
                    }
                    input:focus, select:focus, textarea:focus {
                        outline: none;
                        border-color: #667eea;
                    }
                    button {
                        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                        color: white;
                        border: none;
                        padding: 15px 30px;
                        border-radius: 8px;
                        font-size: 1rem;
                        font-weight: 600;
                        cursor: pointer;
                        transition: transform 0.3s ease;
                    }
                    button:hover {
                        transform: scale(1.05);
                    }
                    
                    .qr-container {
                        text-align: center;
                        padding: 20px;
                    }
                    .qr-container img {
                        max-width: 200px;
                        border: 10px solid white;
                        border-radius: 10px;
                        box-shadow: 0 5px 15px rgba(0,0,0,0.1);
                    }
                    
                    .footer {
                        text-align: center;
                        padding: 20px;
                        color: white;
                        font-size: 0.9rem;
                    }
                    .footer a {
                        color: white;
                        text-decoration: underline;
                    }
                    
                    @media (max-width: 768px) {
                        .header { flex-direction: column; text-align: center; }
                        .stats-grid { grid-template-columns: 1fr; }
                        table { display: block; overflow-x: auto; }
                    }
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="header">
                        <div>
                            <h1>🚀 Enhanced Management Server</h1>
                            <div class="subtitle">Safe Command & Control for Educational Purposes</div>
                        </div>
                        <div class="qr-container">
                            <div>Scan to access on mobile</div>
                            <img src="QR_CODE_PLACEHOLDER" alt="QR Code">
                        </div>
                    </div>
                    
                    <div class="stats-grid">
                        <div class="stat-card green">
                            <h3>Active Clients</h3>
                            <div class="value">{{ active_clients }}</div>
                        </div>
                        <div class="stat-card blue">
                            <h3>Total Commands</h3>
                            <div class="value">{{ total_commands }}</div>
                        </div>
                        <div class="stat-card purple">
                            <h3>Server Uptime</h3>
                            <div class="value">{{ uptime }}</div>
                        </div>
                        <div class="stat-card orange">
                            <h3>Popular Command</h3>
                            <div class="value">{{ popular_command }}</div>
                        </div>
                    </div>
                    
                    <div class="section">
                        <h2>📱 Connected Clients</h2>
                        {% if clients %}
                        <table>
                            <tr>
                                <th>Client ID</th>
                                <th>Hostname</th>
                                <th>OS/Arch</th>
                                <th>IP Address</th>
                                <th>First Seen</th>
                                <th>Last Seen</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                            {% for client in clients %}
                            <tr>
                                <td><strong>{{ client[0] }}</strong></td>
                                <td>{{ client[1] }}</td>
                                <td>{{ client[2] }}/{{ client[3] }}</td>
                                <td>{{ client[4] }}</td>
                                <td>{{ client[5][:19] }}</td>
                                <td>{{ client[6][:19] }}</td>
                                <td>
                                    <span class="badge success">{{ client[7] }}</span>
                                </td>
                                <td>
                                    <form class="command-form-inline" action="/command" method="POST" style="display: inline;">
                                        <input type="hidden" name="client_id" value="{{ client[0] }}">
                                        <select name="action" style="width: auto; margin-right: 5px;">
                                            {% for cmd in safe_commands %}
                                            <option value="{{ cmd }}">{{ cmd }}</option>
                                            {% endfor %}
                                        </select>
                                        <button type="submit" style="padding: 8px 15px;">Send</button>
                                    </form>
                                </td>
                            </tr>
                            {% endfor %}
                        </table>
                        {% else %}
                        <p style="text-align: center; padding: 40px; color: #718096;">
                            No clients connected yet. Start your Go client to see it here!
                        </p>
                        {% endif %}
                    </div>
                    
                    <div class="section">
                        <h2>📝 Recent Command History</h2>
                        {% if history %}
                        <table>
                            <tr>
                                <th>Time</th>
                                <th>Client</th>
                                <th>Command</th>
                                <th>Status</th>
                                <th>Duration</th>
                            </tr>
                            {% for record in history %}
                            <tr>
                                <td>{{ record[3][:19] }}</td>
                                <td>{{ record[0] }}</td>
                                <td>{{ record[1] }}</td>
                                <td>
                                    {% if record[2] == 'success' %}
                                    <span class="badge success">{{ record[2] }}</span>
                                    {% elif record[2] == 'error' %}
                                    <span class="badge error">{{ record[2] }}</span>
                                    {% else %}
                                    <span class="badge info">{{ record[2] }}</span>
                                    {% endif %}
                                </td>
                                <td>{{ record[4]|round(3) }}s</td>
                            </tr>
                            {% endfor %}
                        </table>
                        {% else %}
                        <p style="text-align: center; padding: 40px; color: #718096;">
                            No commands executed yet.
                        </p>
                        {% endif %}
                    </div>
                    
                    <div class="section">
                        <h2>🎯 Send Command</h2>
                        <div class="command-form">
                            <form action="/command" method="POST">
                                <div class="form-group">
                                    <label for="client_id">Client ID</label>
                                    <input type="text" id="client_id" name="client_id" 
                                           placeholder="Enter client ID or 'broadcast' for all" required>
                                </div>
                                <div class="form-group">
                                    <label for="action">Command</label>
                                    <select id="action" name="action" required>
                                        {% for cmd in safe_commands %}
                                        <option value="{{ cmd }}">{{ cmd }}</option>
                                        {% endfor %}
                                    </select>
                                </div>
                                <div class="form-group">
                                    <label for="params">Parameters (JSON)</label>
                                    <textarea id="params" name="params" rows="3" 
                                              placeholder='{"message": "Hello!"}'></textarea>
                                </div>
                                <button type="submit">🚀 Send Command</button>
                            </form>
                        </div>
                    </div>
                    
                    <div class="section">
                        <h2>📋 Available Commands</h2>
                        <div style="display: flex; flex-wrap: wrap; gap: 10px;">
                            {% for cmd in safe_commands %}
                            <div style="background: #edf2f7; padding: 15px; border-radius: 8px; flex: 1; min-width: 200px;">
                                <strong>{{ cmd }}</strong>
                                <div style="color: #718096; font-size: 0.9rem; margin-top: 5px;">
                                    {{ command_descriptions[cmd] }}
                                </div>
                            </div>
                            {% endfor %}
                        </div>
                    </div>
                </div>
                
                <div class="footer">
                    <p>⚠️ Educational Purposes Only | Safe Command Whitelist | No Malicious Actions</p>
                    <p>Server: https://c2-serverv2.onrender.com | Clients connected: {{ active_clients }}</p>
                </div>
                
                <script>
                    // Auto-refresh every 30 seconds
                    setTimeout(function() {
                        window.location.reload();
                    }, 30000);
                    
                    // Form submission feedback
                    document.querySelectorAll('form').forEach(form => {
                        form.addEventListener('submit', function(e) {
                            const button = this.querySelector('button[type="submit"]');
                            if (button) {
                                button.innerHTML = '⏳ Sending...';
                                button.disabled = true;
                            }
                        });
                    });
                    
                    // Time formatting
                    document.querySelectorAll('td').forEach(td => {
                        if (td.textContent.includes('T') && td.textContent.includes(':')) {
                            const date = new Date(td.textContent);
                            td.textContent = date.toLocaleString();
                        }
                    });
                </script>
            </body>
            </html>
            """
            
            # Command descriptions
            command_descriptions = {
                "get_system_info": "Get basic system information",
                "get_disk_usage": "Check disk space usage",
                "list_processes_safe": "List running processes (limited)",
                "echo": "Echo back a message",
                "get_network_info": "Get network configuration",
                "get_time": "Get current server time",
                "get_status": "Check client status",
                "ping": "Simple ping response",
                "get_geo_info": "Get simulated geolocation info"
            }
            
            popular_command = popular_commands[0][0] if popular_commands else "echo"
            
            return render_template_string(html.replace("QR_CODE_PLACEHOLDER", qr_code),
                clients=clients,
                history=history,
                active_clients=active_clients,
                total_commands=total_commands,
                popular_command=popular_command,
                uptime=self.server_stats['uptime'],
                safe_commands=SAFE_COMMANDS,
                command_descriptions=command_descriptions
            )
        
        @self.app.route('/heartbeat', methods=['POST'])
        def heartbeat():
            """Client heartbeat endpoint - NO AUTHENTICATION REQUIRED"""
            try:
                self.server_stats['total_requests'] += 1
                
                # Get request data
                if request.is_json:
                    data = request.get_json()
                else:
                    data = request.form.to_dict()
                
                # DEBUG logging
                client_id = data.get('client_id', 'unknown')
                print(f"\n💓 Heartbeat from: {client_id}")
                print(f"   IP: {request.remote_addr}")
                print(f"   Data: {data}")
                
                # Register/update client (NO AUTH CHECK)
                success, message = self.register_client(data)
                if not success:
                    return jsonify({'error': message}), 400
                
                # Get pending commands
                commands = self.get_pending_commands(client_id)
                
                # If no commands, send a welcome command for new clients
                if not commands and "new_client" in data.get('tags', []):
                    welcome_cmd = {
                        'command_id': f"welcome-{int(time.time())}",
                        'action': 'echo',
                        'params': {'message': 'Welcome to the enhanced server!'},
                        'timestamp': int(time.time())
                    }
                    commands = [welcome_cmd]
                
                response = {
                    'status': 'success',
                    'message': 'Heartbeat received',
                    'commands': commands,
                    'timestamp': int(time.time()),
                    'server_time': datetime.now().isoformat(),
                    'server_version': '2.0-enhanced'
                }
                
                return jsonify(response)
                
            except Exception as e:
                print(f"❌ Heartbeat error: {str(e)}")
                self.client_manager.log_message("ERROR", f"Heartbeat error: {str(e)}")
                return jsonify({'error': str(e)}), 500
        
        @self.app.route('/result', methods=['POST'])
        def command_result():
            """Receive command execution results"""
            try:
                if not request.is_json:
                    return jsonify({'error': 'JSON required'}), 400
                
                data = request.get_json()
                client_id = data.get('client_id', 'unknown')
                command_id = data.get('command_id', 'unknown')
                status = data.get('status', 'unknown')
                
                print(f"📤 Result from {client_id}: {command_id} - {status}")
                
                # Log the result
                self.log_command_result(
                    client_id, command_id, 
                    {'action': data.get('command', 'unknown'), 'params': {}},
                    data.get('output', ''),
                    status,
                    data.get('execution_time', 0.0)
                )
                
                return jsonify({
                    'status': 'success', 
                    'message': 'Result received',
                    'received_at': datetime.now().isoformat()
                })
                
            except Exception as e:
                print(f"❌ Result error: {str(e)}")
                return jsonify({'error': str(e)}), 500
        
        @self.app.route('/command', methods=['POST'])
        def send_command():
            """Send command to client(s)"""
            client_id = request.form.get('client_id')
            action = request.form.get('action')
            params_str = request.form.get('params', '{}')
            
            if not client_id or not action:
                return "Missing client_id or action", 400
            
            try:
                params = json.loads(params_str) if params_str.strip() else {}
            except:
                params = {'message': params_str}
            
            # Broadcast to all clients if client_id is 'broadcast'
            if client_id.lower() == 'broadcast':
                cursor = self.client_manager.conn.cursor()
                cursor.execute('SELECT client_id FROM clients WHERE status = "active"')
                active_clients = [row[0] for row in cursor.fetchall()]
                
                sent_count = 0
                for cid in active_clients:
                    cmd_id = self.queue_command(cid, action, params)
                    if cmd_id and not cmd_id.startswith('Command'):
                        sent_count += 1
                
                return f"""
                <script>
                    alert('Command broadcast to {sent_count} clients!');
                    window.location.href = '/';
                </script>
                """
            else:
                # Send to specific client
                command_id = self.queue_command(client_id, action, params)
                
                if command_id and not command_id.startswith('Command'):
                    return f"""
                    <script>
                        alert('Command queued successfully! ID: {command_id}');
                        window.location.href = '/';
                    </script>
                    """
                else:
                    return f"""
                    <script>
                        alert('Error: {command_id}');
                        window.location.href = '/';
                    </script>
                    """
        
        @self.app.route('/api/clients', methods=['GET'])
        def api_clients():
            """API endpoint to get connected clients"""
            cursor = self.client_manager.conn.cursor()
            cursor.execute('''
                SELECT client_id, hostname, os, arch, ip_address, 
                       first_seen, last_seen, status
                FROM clients 
                WHERE status = "active"
                ORDER BY last_seen DESC
            ''')
            clients = cursor.fetchall()
            
            return jsonify({
                'clients': [
                    {
                        'client_id': c[0],
                        'hostname': c[1],
                        'os': c[2],
                        'arch': c[3],
                        'ip_address': c[4],
                        'first_seen': c[5],
                        'last_seen': c[6],
                        'status': c[7]
                    }
                    for c in clients
                ],
                'count': len(clients),
                'timestamp': datetime.now().isoformat()
            })
        
        @self.app.route('/api/stats', methods=['GET'])
        def api_stats():
            """API endpoint to get server statistics"""
            cursor = self.client_manager.conn.cursor()
            cursor.execute('SELECT COUNT(*) FROM clients WHERE status = "active"')
            active_clients = cursor.fetchone()[0]
            
            cursor.execute('SELECT COUNT(*) FROM command_history')
            total_commands = cursor.fetchone()[0]
            
            return jsonify({
                'server_stats': {
                    'active_clients': active_clients,
                    'total_commands': total_commands,
                    'uptime': str(datetime.now() - self.server_stats['start_time']),
                    'start_time': self.server_stats['start_time'].isoformat(),
                    'total_requests': self.server_stats['total_requests']
                },
                'timestamp': datetime.now().isoformat()
            })
        
        @self.app.route('/api/logs', methods=['GET'])
        def api_logs():
            """API endpoint to get server logs"""
            limit = request.args.get('limit', 100, type=int)
            cursor = self.client_manager.conn.cursor()
            cursor.execute('''
                SELECT level, message, timestamp, source
                FROM server_logs 
                ORDER BY timestamp DESC 
                LIMIT ?
            ''', (limit,))
            logs = cursor.fetchall()
            
            return jsonify({
                'logs': [
                    {
                        'level': l[0],
                        'message': l[1],
                        'timestamp': l[2],
                        'source': l[3]
                    }
                    for l in logs
                ],
                'count': len(logs)
            })
    
    def run(self, debug=False):
        """Start the server"""
        self.app.run(host=self.host, port=self.port, debug=debug, use_reloader=False)

# ============================================
# START THE SERVER
# ============================================
server = EnhancedManagementServer(
    host="0.0.0.0",
    port=int(os.environ.get("PORT", 8080)),
    secret_key="educational-demo-key-change-in-production"
)

app = server.app  # For Gunicorn

if __name__ == "__main__":
    try:
        server.run(debug=True)
    except KeyboardInterrupt:
        print("\n\n🛑 Server stopped by user")
    except Exception as e:
        print(f"\n❌ Server error: {e}")
