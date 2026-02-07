#!/usr/bin/env python3
"""
SAFE MANAGEMENT SERVER - NOT A C2 SERVER
Educational purpose only - Demonstrates secure client-server architecture
"""

from flask import Flask, request, jsonify, render_template_string
import hashlib
import hmac
import json
import time
import os
import threading
import sqlite3
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import secrets

# ============================================
# SAFE CONFIGURATION - MODIFY AS NEEDED
# ============================================
SAFE_COMMANDS = [
    "get_system_info",      # Get basic system info
    "get_disk_usage",       # Get disk usage (limited)
    "list_processes_safe",  # List processes (limited)
    "echo",                 # Echo a message
    "get_network_info",     # Get network info
    "get_time",             # Get current time
    "get_status",           # Get client status
]

# Client database (in-memory for demo, use real DB for production)
client_db = {}

# ============================================
# SAFE SERVER IMPLEMENTATION
# ============================================

class SafeManagementServer:
    def __init__(self, host='127.0.0.1', port=8080, secret_key=None):
        """
        Initialize SAFE management server
        """
        self.host = host
        self.port = port
        self.secret_key = secret_key or secrets.token_hex(32)
        self.app = Flask(__name__)
        self.setup_routes()
        self.setup_database()
        
        # Command queue for clients
        self.command_queues = {}
        
        # Audit log
        self.audit_log = []
        
        print(f"🔐 Secret Key (for clients): {self.secret_key}")
        print(f"✅ SAFE Commands: {', '.join(SAFE_COMMANDS)}")
    
    def setup_database(self):
        """Initialize database for client management"""
        self.conn = sqlite3.connect(':memory:', check_same_thread=False)
        cursor = self.conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS clients (
                client_id TEXT PRIMARY KEY,
                last_seen TIMESTAMP,
                os TEXT,
                arch TEXT,
                ip_address TEXT,
                status TEXT
            )
        ''')
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS command_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                client_id TEXT,
                command_id TEXT,
                command TEXT,
                timestamp TIMESTAMP,
                status TEXT
            )
        ''')
        self.conn.commit()
    
    def verify_signature(self, client_id: str, data: str, signature: str) -> bool:
        """Verify HMAC signature for security"""
        expected_signature = hmac.new(
            self.secret_key.encode(),
            data.encode(),
            hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(signature, expected_signature)
    
    def register_client(self, client_data: Dict) -> Tuple[bool, str]:
        """Register or update client information"""
        client_id = client_data.get('client_id')
        if not client_id:
            return False, "Missing client_id"
        
        cursor = self.conn.cursor()
        cursor.execute('''
            INSERT OR REPLACE INTO clients 
            (client_id, last_seen, os, arch, ip_address, status)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (
            client_id,
            datetime.now(),
            client_data.get('os', 'unknown'),
            client_data.get('arch', 'unknown'),
            request.remote_addr,
            'active'
        ))
        self.conn.commit()
        
        # Log the connection
        self.log_audit('CLIENT_HEARTBEAT', client_id, 
                      f"Client heartbeat from {client_id} ({request.remote_addr})")
        
        return True, "Client registered/updated"
    
    def get_pending_commands(self, client_id: str) -> List[Dict]:
        """Get pending SAFE commands for a client"""
        if client_id not in self.command_queues:
            return []
        
        commands = self.command_queues[client_id].copy()
        self.command_queues[client_id] = []  # Clear after sending
        
        # Log command delivery
        for cmd in commands:
            self.log_command(client_id, cmd['command_id'], cmd['action'], 'SENT')
        
        return commands
    
    def queue_safe_command(self, client_id: str, action: str, params: Dict = None) -> Optional[str]:
        """Queue a SAFE command for a client"""
        if action not in SAFE_COMMANDS:
            return f"Command '{action}' is not in safe whitelist"
        
        if client_id not in self.command_queues:
            self.command_queues[client_id] = []
        
        command_id = secrets.token_hex(8)
        command = {
            'command_id': command_id,
            'action': action,
            'params': params or {},
            'timestamp': int(time.time())
        }
        
        self.command_queues[client_id].append(command)
        self.log_audit('COMMAND_QUEUED', client_id, 
                      f"Command '{action}' queued for {client_id}")
        
        return command_id
    
    def log_command(self, client_id: str, command_id: str, command: str, status: str):
        """Log command execution"""
        cursor = self.conn.cursor()
        cursor.execute('''
            INSERT INTO command_history 
            (client_id, command_id, command, timestamp, status)
            VALUES (?, ?, ?, ?, ?)
        ''', (client_id, command_id, command, datetime.now(), status))
        self.conn.commit()
    
    def log_audit(self, event_type: str, client_id: str, message: str):
        """Log audit event"""
        event = {
            'timestamp': datetime.now().isoformat(),
            'type': event_type,
            'client_id': client_id,
            'ip': request.remote_addr,
            'message': message
        }
        self.audit_log.append(event)
        print(f"[AUDIT] {event_type}: {message}")
    
    # ============================================
    # FLASK ROUTES
    # ============================================
    
    def setup_routes(self):
        """Setup all HTTP routes"""
        
        @self.app.route('/')
        def index():
            """Dashboard - Shows connected clients"""
            cursor = self.conn.cursor()
            cursor.execute('SELECT * FROM clients ORDER BY last_seen DESC')
            clients = cursor.fetchall()
            
            cursor.execute('SELECT * FROM command_history ORDER BY timestamp DESC LIMIT 50')
            history = cursor.fetchall()
            
            html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>🔒 Safe Management Server</title>
                <style>
                    body { font-family: Arial, sans-serif; margin: 20px; }
                    .container { max-width: 1200px; margin: 0 auto; }
                    .card { background: #f5f5f5; padding: 20px; margin: 10px 0; border-radius: 5px; }
                    .connected { color: green; }
                    .disconnected { color: #ccc; }
                    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
                    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
                    th { background-color: #4CAF50; color: white; }
                    .command-form { display: inline-block; margin: 5px; }
                    input, select { padding: 5px; margin: 2px; }
                    .warning { background: #fff3cd; border: 1px solid #ffeaa7; padding: 10px; }
                </style>
            </head>
            <body>
                <div class="container">
                    <h1>🔒 Safe Management Server</h1>
                    <div class="warning">
                        <strong>⚠️ EDUCATIONAL PURPOSES ONLY</strong><br>
                        This server only allows SAFE, whitelisted commands.
                    </div>
                    
                    <h2>📊 Connected Clients ({{ clients|length }})</h2>
                    {% if clients %}
                    <table>
                        <tr>
                            <th>Client ID</th>
                            <th>Last Seen</th>
                            <th>OS/Arch</th>
                            <th>IP Address</th>
                            <th>Status</th>
                            <th>Actions</th>
                        </tr>
                        {% for client in clients %}
                        <tr>
                            <td>{{ client[0] }}</td>
                            <td>{{ client[1] }}</td>
                            <td>{{ client[2] }}/{{ client[3] }}</td>
                            <td>{{ client[4] }}</td>
                            <td>{{ client[5] }}</td>
                            <td>
                                <form class="command-form" action="/command" method="POST">
                                    <input type="hidden" name="client_id" value="{{ client[0] }}">
                                    <select name="action">
                                        {% for cmd in safe_commands %}
                                        <option value="{{ cmd }}">{{ cmd }}</option>
                                        {% endfor %}
                                    </select>
                                    <input type="text" name="params" placeholder="JSON params" size="20">
                                    <button type="submit">Send Command</button>
                                </form>
                            </td>
                        </tr>
                        {% endfor %}
                    </table>
                    {% else %}
                    <p>No clients connected yet.</p>
                    {% endif %}
                    
                    <h2>📝 Command History</h2>
                    {% if history %}
                    <table>
                        <tr>
                            <th>Time</th>
                            <th>Client ID</th>
                            <th>Command</th>
                            <th>Status</th>
                        </tr>
                        {% for record in history %}
                        <tr>
                            <td>{{ record[4] }}</td>
                            <td>{{ record[1] }}</td>
                            <td>{{ record[3] }}</td>
                            <td>{{ record[5] }}</td>
                        </tr>
                        {% endfor %}
                    </table>
                    {% else %}
                    <p>No commands executed yet.</p>
                    {% endif %}
                    
                    <hr>
                    <h3>🔄 Manual Client Test</h3>
                    <form action="/heartbeat" method="POST">
                        <label>Client ID: <input type="text" name="client_id" value="test-client-01"></label><br>
                        <label>OS: <input type="text" name="os" value="linux"></label>
                        <label>Arch: <input type="text" name="arch" value="x64"></label><br>
                        <button type="submit">Send Test Heartbeat</button>
                    </form>
                    
                    <h3>📋 Safe Commands Whitelist</h3>
                    <ul>
                        {% for cmd in safe_commands %}
                        <li><code>{{ cmd }}</code></li>
                        {% endfor %}
                    </ul>
                </div>
            </body>
            </html>
            """
            
            return render_template_string(html, 
                                         clients=clients, 
                                         history=history,
                                         safe_commands=SAFE_COMMANDS)
        
        @self.app.route('/heartbeat', methods=['POST'])
        def heartbeat():
            """Client heartbeat endpoint - Returns pending commands"""
            try:
                # Get request data
                if request.is_json:
                    data = request.get_json()
                    signature = request.headers.get('X-Signature', '')
                    client_id = request.headers.get('X-Client-ID', '')
                else:
                    data = request.form.to_dict()
                    signature = request.headers.get('X-Signature', '')
                    client_id = data.get('client_id', '')
                
                # Verify signature (skip for demo if no signature)
                if signature and client_id:
                    if not self.verify_signature(client_id, json.dumps(data), signature):
                        self.log_audit('AUTH_FAILED', client_id, "Invalid signature")
                        return jsonify({'error': 'Authentication failed'}), 401
                
                # Register/update client
                success, message = self.register_client(data)
                if not success:
                    return jsonify({'error': message}), 400
                
                # Get pending commands for this client
                commands = self.get_pending_commands(client_id or data.get('client_id'))
                
                return jsonify({
                    'status': 'success',
                    'message': 'Heartbeat received',
                    'commands': commands,
                    'timestamp': int(time.time())
                })
                
            except Exception as e:
                self.log_audit('ERROR', 'unknown', f"Heartbeat error: {str(e)}")
                return jsonify({'error': str(e)}), 500
        
        @self.app.route('/result', methods=['POST'])
        def command_result():
            """Receive command execution results from clients"""
            try:
                if not request.is_json:
                    return jsonify({'error': 'JSON required'}), 400
                
                data = request.get_json()
                signature = request.headers.get('X-Signature', '')
                client_id = request.headers.get('X-Client-ID', '')
                
                # Verify signature
                if signature and client_id:
                    if not self.verify_signature(client_id, json.dumps(data), signature):
                        return jsonify({'error': 'Authentication failed'}), 401
                
                # Log the result
                self.log_command(
                    data.get('client_id', 'unknown'),
                    data.get('command_id', 'unknown'),
                    data.get('status', 'unknown'),
                    'COMPLETED'
                )
                
                # Log to audit
                self.log_audit('COMMAND_RESULT', 
                              data.get('client_id', 'unknown'),
                              f"Command {data.get('command_id')} completed with status: {data.get('status')}")
                
                return jsonify({'status': 'success', 'message': 'Result received'})
                
            except Exception as e:
                return jsonify({'error': str(e)}), 500
        
        @self.app.route('/command', methods=['POST'])
        def send_command():
            """Web interface to send commands to clients"""
            client_id = request.form.get('client_id')
            action = request.form.get('action')
            params_str = request.form.get('params', '{}')
            
            if not client_id or not action:
                return "Missing client_id or action", 400
            
            # Parse params (safe JSON only)
            try:
                params = json.loads(params_str) if params_str else {}
            except:
                params = {'raw': params_str}
            
            # Queue the command
            command_id = self.queue_safe_command(client_id, action, params)
            
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
            cursor = self.conn.cursor()
            cursor.execute('SELECT * FROM clients ORDER BY last_seen DESC')
            clients = cursor.fetchall()
            
            return jsonify({
                'clients': [
                    {
                        'client_id': c[0],
                        'last_seen': c[1],
                        'os': c[2],
                        'arch': c[3],
                        'ip_address': c[4],
                        'status': c[5]
                    }
                    for c in clients
                ]
            })
        
        @self.app.route('/api/audit', methods=['GET'])
        def api_audit():
            """API endpoint to get audit log"""
            return jsonify({'audit_log': self.audit_log[-100:]})  # Last 100 entries
        
        @self.app.route('/api/cleanup', methods=['POST'])
        def cleanup():
            """Cleanup old clients (more than 5 minutes inactive)"""
            cutoff = datetime.now() - timedelta(minutes=5)
            cursor = self.conn.cursor()
            cursor.execute('DELETE FROM clients WHERE last_seen < ?', (cutoff,))
            deleted = cursor.rowcount
            self.conn.commit()
            
            return jsonify({
                'status': 'success',
                'message': f'Cleaned up {deleted} inactive clients'
            })
    
    def run(self, debug=False):
        """Start the server"""
        print(f"\n{'='*60}")
        print(f"🔒 SAFE MANAGEMENT SERVER")
        print(f"{'='*60}")
        print(f"🌐 Host: {self.host}:{self.port}")
        print(f"📁 Dashboard: http://{self.host}:{self.port}")
        print(f"💓 Heartbeat endpoint: /heartbeat (POST)")
        print(f"📤 Result endpoint: /result (POST)")
        print(f"📋 API: /api/clients (GET)")
        print(f"{'='*60}")
        print("⚠️  EDUCATIONAL PURPOSES ONLY - NOT A REAL C2 SERVER")
        print(f"{'='*60}\n")
        
        self.app.run(host=self.host, port=self.port, debug=debug, use_reloader=False)

# ============================================
# START THE SERVER
# ============================================
server = SafeManagementServer(
    host="0.0.0.0",
    port=int(os.environ.get("PORT", 8080)),
    secret_key="educational-demo-key-change-in-production"
)

app = server.app  # Gunicorn looks for this


if __name__ == "__main__":
    try:
        server.run(debug=True)
    except KeyboardInterrupt:
        print("\n\n🛑 Server stopped by user")
    except Exception as e:
        print(f"\n❌ Server error: {e}")
