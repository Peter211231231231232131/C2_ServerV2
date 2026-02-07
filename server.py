#!/usr/bin/env python3
"""
🚀 ENHANCED MANAGEMENT SERVER
Working version for Render.com
Educational purposes only
"""

from flask import Flask, request, jsonify, render_template_string
import time
import uuid
from datetime import datetime, timedelta
import json

app = Flask(__name__)

# ============================================
# GLOBAL VARIABLES (in-memory storage)
# ============================================
SAFE_COMMANDS = [
    "get_system_info", "get_disk_usage", "list_processes_safe",
    "echo", "get_network_info", "get_time", "get_status",
    "ping", "get_geo_info", "execute_safe"
]

clients = {}  # client_id -> {data}
command_queues = {}  # client_id -> [commands]
command_history = []  # list of executed commands
server_start_time = datetime.now()

# ============================================
# HTML TEMPLATE
# ============================================
HTML_TEMPLATE = '''<!DOCTYPE html>
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
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header { 
            background: white; 
            padding: 30px; 
            border-radius: 15px; 
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            text-align: center;
        }
        .header h1 { color: #2d3748; font-size: 2.5rem; margin-bottom: 10px; }
        .header .subtitle { color: #718096; font-size: 1.1rem; }
        .server-url {
            background: #edf2f7; 
            padding: 10px 20px; 
            border-radius: 8px; 
            margin-top: 15px; 
            display: inline-block; 
            font-family: monospace;
            color: #2d3748;
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
        .stat-card:hover { transform: translateY(-5px); }
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
            display: flex;
            justify-content: space-between;
            align-items: center;
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
        td { padding: 15px; border-bottom: 1px solid #e2e8f0; }
        tr:hover { background: #f7fafc; }
        
        .badge {
            display: inline-block;
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85rem;
            font-weight: 600;
        }
        .badge.success { background: #c6f6d5; color: #22543d; }
        .badge.error { background: #fed7d7; color: #742a2a; }
        .badge.info { background: #bee3f8; color: #2a4365; }
        .badge.primary { background: #ebf4ff; color: #2c5282; }
        
        .command-form { background: #f7fafc; padding: 20px; border-radius: 10px; margin-top: 20px; }
        .form-group { margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; font-weight: 600; color: #4a5568; }
        input, select, textarea {
            width: 100%;
            padding: 12px;
            border: 2px solid #e2e8f0;
            border-radius: 8px;
            font-size: 1rem;
            transition: border-color 0.3s ease;
        }
        input:focus, select:focus, textarea:focus { outline: none; border-color: #667eea; }
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
        button:hover { transform: scale(1.05); }
        
        .footer {
            text-align: center;
            padding: 20px;
            color: white;
            font-size: 0.9rem;
            margin-top: 30px;
        }
        
        @media (max-width: 768px) {
            .stats-grid { grid-template-columns: 1fr; }
            table { display: block; overflow-x: auto; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Enhanced Management Server</h1>
            <div class="subtitle">Safe Command & Control for Educational Purposes</div>
            <div class="server-url">https://c2-serverv2.onrender.com</div>
            <div style="margin-top: 15px; font-size: 0.9rem; color: #718096;">
                🔐 Authentication: Disabled | 📡 Real-time monitoring | 🎯 Safe commands only
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
                <h3>Server Version</h3>
                <div class="value">2.0</div>
            </div>
        </div>
        
        <div class="section">
            <h2>📱 Connected Clients <span class="badge primary">{{ active_clients }} active</span></h2>
            {% if clients_list %}
            <table>
                <tr>
                    <th>Client ID</th>
                    <th>OS/Arch</th>
                    <th>IP Address</th>
                    <th>Last Seen</th>
                    <th>Status</th>
                    <th>Quick Actions</th>
                </tr>
                {% for client in clients_list %}
                <tr>
                    <td><strong>{{ client.id }}</strong></td>
                    <td>{{ client.os }}/{{ client.arch }}</td>
                    <td><code>{{ client.ip }}</code></td>
                    <td>{{ client.last_seen }}</td>
                    <td><span class="badge success">Active</span></td>
                    <td>
                        <form action="/command" method="POST" style="display: inline;">
                            <input type="hidden" name="client_id" value="{{ client.id }}">
                            <input type="hidden" name="action" value="echo">
                            <button type="submit" style="padding: 8px 15px; font-size: 0.9rem;">👋 Echo</button>
                        </form>
                        <form action="/command" method="POST" style="display: inline;">
                            <input type="hidden" name="client_id" value="{{ client.id }}">
                            <input type="hidden" name="action" value="get_system_info">
                            <button type="submit" style="padding: 8px 15px; font-size: 0.9rem;">💻 System</button>
                        </form>
                    </td>
                </tr>
                {% endfor %}
            </table>
            {% else %}
            <div style="text-align: center; padding: 40px; color: #718096; background: #f7fafc; border-radius: 10px;">
                <div style="font-size: 3rem; margin-bottom: 20px;">📡</div>
                <h3 style="color: #4a5568; margin-bottom: 10px;">No clients connected yet</h3>
                <p>Start your Go client to see it appear here!</p>
            </div>
            {% endif %}
        </div>
        
        <div class="section">
            <h2>🎯 Send Command</h2>
            <div class="command-form">
                <form action="/command" method="POST">
                    <div class="form-group">
                        <label for="client_id">Client ID</label>
                        <input type="text" id="client_id" name="client_id" 
                               placeholder="Enter client ID or 'broadcast' for all clients" 
                               list="client-list" required>
                        <datalist id="client-list">
                            {% for client in clients_list %}
                            <option value="{{ client.id }}">
                            {% endfor %}
                        </datalist>
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
                                  placeholder='{"message": "Hello from the server!"}'></textarea>
                    </div>
                    <button type="submit">🚀 Send Command</button>
                </form>
            </div>
        </div>
        
        <div class="section">
            <h2>📝 Recent Command History</h2>
            {% if command_history %}
            <table>
                <tr>
                    <th>Time</th>
                    <th>Client</th>
                    <th>Command</th>
                    <th>Status</th>
                </tr>
                {% for cmd in command_history %}
                <tr>
                    <td>{{ cmd.time }}</td>
                    <td><code>{{ cmd.client_id }}</code></td>
                    <td><strong>{{ cmd.action }}</strong></td>
                    <td>
                        <span class="badge {{ 'success' if cmd.status == 'success' else 'error' }}">
                            {{ cmd.status }}
                        </span>
                    </td>
                </tr>
                {% endfor %}
            </table>
            {% else %}
            <div style="text-align: center; padding: 30px; color: #718096;">
                No commands executed yet. Send your first command above!
            </div>
            {% endif %}
        </div>
        
        <div class="section">
            <h2>📋 Available Commands</h2>
            <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 15px;">
                {% for cmd in safe_commands %}
                <div style="background: #edf2f7; padding: 20px; border-radius: 10px; border-left: 4px solid #4299e1;">
                    <strong style="color: #2d3748;">{{ cmd }}</strong>
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
        <p>Server: https://c2-serverv2.onrender.com | Active Clients: {{ active_clients }} | Commands: {{ total_commands }}</p>
        <p style="margin-top: 10px; font-size: 0.8rem; opacity: 0.8;">
            🔄 Auto-refreshes every 30 seconds | Last updated: {{ current_time }}
        </p>
    </div>
    
    <script>
        // Auto-refresh every 30 seconds
        setTimeout(() => location.reload(), 30000);
        
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
        
        // Auto-focus on client ID field
        document.getElementById('client_id')?.focus();
    </script>
</body>
</html>
'''

# ============================================
# HELPER FUNCTIONS
# ============================================
def cleanup_old_clients():
    """Remove clients inactive for more than 5 minutes"""
    cutoff = time.time() - 300  # 5 minutes in seconds
    to_delete = []
    for client_id, client_data in clients.items():
        if client_data.get('last_seen', 0) < cutoff:
            to_delete.append(client_id)
    
    for client_id in to_delete:
        del clients[client_id]
        if client_id in command_queues:
            del command_queues[client_id]

def format_uptime():
    """Format server uptime as HH:MM:SS"""
    uptime = datetime.now() - server_start_time
    hours, remainder = divmod(int(uptime.total_seconds()), 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"

# ============================================
# ROUTES
# ============================================
@app.route('/')
def index():
    """Main dashboard"""
    cleanup_old_clients()
    
    # Prepare client list
    clients_list = []
    for client_id, client_data in clients.items():
        last_seen = datetime.fromtimestamp(client_data.get('last_seen', time.time()))
        clients_list.append({
            'id': client_id,
            'os': client_data.get('os', 'unknown'),
            'arch': client_data.get('arch', 'unknown'),
            'ip': client_data.get('ip', 'unknown'),
            'last_seen': last_seen.strftime('%H:%M:%S')
        })
    
    # Command descriptions
    command_descriptions = {
        "get_system_info": "Get system information (OS, hostname, etc.)",
        "get_disk_usage": "Check disk space usage",
        "list_processes_safe": "List running processes",
        "echo": "Echo a message back",
        "get_network_info": "Get network configuration",
        "get_time": "Get current time from client",
        "get_status": "Check client status",
        "ping": "Simple ping response",
        "get_geo_info": "Get simulated geolocation",
        "execute_safe": "Execute safe command"
    }
    
    return render_template_string(
        HTML_TEMPLATE,
        active_clients=len(clients),
        total_commands=len(command_history),
        uptime=format_uptime(),
        clients_list=clients_list,
        safe_commands=SAFE_COMMANDS,
        command_descriptions=command_descriptions,
        command_history=command_history[-20:],  # Last 20 commands
        current_time=datetime.now().strftime('%H:%M:%S')
    )

@app.route('/heartbeat', methods=['POST'])
def heartbeat():
    """Client heartbeat endpoint"""
    try:
        # Get data
        if request.is_json:
            data = request.get_json()
        else:
            data = request.form.to_dict()
        
        client_id = data.get('client_id', f'client-{uuid.uuid4().hex[:8]}')
        
        # Update client info
        clients[client_id] = {
            'os': data.get('os', 'unknown'),
            'arch': data.get('arch', 'unknown'),
            'hostname': data.get('hostname', 'unknown'),
            'last_seen': time.time(),
            'ip': request.remote_addr,
            'version': data.get('version', '1.0')
        }
        
        # Get pending commands
        commands = command_queues.get(client_id, [])
        if client_id in command_queues:
            command_queues[client_id] = []  # Clear after sending
        
        print(f"💓 Heartbeat from {client_id} ({request.remote_addr})")
        
        return jsonify({
            'status': 'success',
            'message': 'Heartbeat received',
            'commands': commands,
            'timestamp': time.time(),
            'server_time': datetime.now().isoformat(),
            'client_count': len(clients),
            'server_version': '2.0'
        })
        
    except Exception as e:
        print(f"❌ Heartbeat error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/result', methods=['POST'])
def command_result():
    """Receive command execution results"""
    try:
        if not request.is_json:
            return jsonify({'error': 'JSON required'}), 400
        
        data = request.get_json()
        client_id = data.get('client_id', 'unknown')
        command_id = data.get('command_id', 'unknown')
        status = data.get('status', 'unknown')
        action = data.get('command', 'unknown')
        
        # Log to history
        command_history.append({
            'time': datetime.now().strftime('%H:%M:%S'),
            'client_id': client_id,
            'action': action,
            'status': status
        })
        
        # Keep only last 100 commands
        while len(command_history) > 100:
            command_history.pop(0)
        
        print(f"📤 Result from {client_id}: {action} - {status}")
        
        return jsonify({
            'status': 'success',
            'message': 'Result received',
            'received_at': datetime.now().isoformat()
        })
        
    except Exception as e:
        print(f"❌ Result error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/command', methods=['POST'])
def send_command():
    """Send command to client(s)"""
    try:
        client_id = request.form.get('client_id')
        action = request.form.get('action')
        params_str = request.form.get('params', '{}')
        
        if not client_id or not action:
            return "Missing client_id or action", 400
        
        if action not in SAFE_COMMANDS:
            return f"Command '{action}' is not in safe whitelist", 400
        
        # Parse parameters
        try:
            params = json.loads(params_str) if params_str.strip() else {}
        except:
            params = {'message': params_str}
        
        command_id = f'cmd-{uuid.uuid4().hex[:8]}'
        command = {
            'command_id': command_id,
            'action': action,
            'params': params,
            'timestamp': time.time()
        }
        
        # Broadcast to all clients
        if client_id.lower() == 'broadcast':
            sent_count = 0
            for cid in clients.keys():
                if cid not in command_queues:
                    command_queues[cid] = []
                command_copy = command.copy()
                command_copy['command_id'] = f'{command_id}-{sent_count}'
                command_queues[cid].append(command_copy)
                sent_count += 1
            
            print(f"📨 Broadcast command '{action}' to {sent_count} clients")
            return f'''
            <script>
                alert("✅ Command broadcast to {sent_count} clients!\\nCommand: {action}");
                window.location.href = "/";
            </script>
            '''
        
        # Send to specific client
        if client_id not in command_queues:
            command_queues[client_id] = []
        
        command_queues[client_id].append(command)
        
        print(f"📨 Command queued for {client_id}: {action} (ID: {command_id})")
        
        return f'''
        <script>
            alert("✅ Command queued successfully!\\nClient: {client_id}\\nCommand: {action}\\nID: {command_id}");
            window.location.href = "/";
        </script>
        '''
    
    except Exception as e:
        return f'''
        <script>
            alert("❌ Error: {str(e)}");
            window.location.href = "/";
        </script>
        ''', 400

@app.route('/api/clients', methods=['GET'])
def api_clients():
    """API endpoint to get connected clients"""
    client_list = []
    for client_id, client_data in clients.items():
        client_list.append({
            'client_id': client_id,
            'os': client_data.get('os', 'unknown'),
            'arch': client_data.get('arch', 'unknown'),
            'last_seen': datetime.fromtimestamp(
                client_data.get('last_seen', time.time())
            ).isoformat(),
            'ip_address': client_data.get('ip', 'unknown'),
            'status': 'active'
        })
    
    return jsonify({
        'clients': client_list,
        'count': len(client_list),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/stats', methods=['GET'])
def api_stats():
    """API endpoint to get server statistics"""
    return jsonify({
        'server_stats': {
            'active_clients': len(clients),
            'total_commands': len(command_history),
            'uptime': format_uptime(),
            'start_time': server_start_time.isoformat(),
            'server_version': '2.0'
        },
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint for Render"""
    return jsonify({
        'status': 'healthy',
        'server': 'running',
        'timestamp': datetime.now().isoformat(),
        'clients': len(clients)
    })

# ============================================
# START SERVER
# ============================================
if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    print(f"🚀 Starting Enhanced Management Server on port {port}")
    print(f"🌐 Dashboard: http://localhost:{port}")
    print(f"💓 Heartbeat endpoint: /heartbeat (POST)")
    print(f"📤 Result endpoint: /result (POST)")
    print(f"📊 API: /api/clients (GET), /api/stats (GET)")
    print("=" * 50)
    print("⚠️  EDUCATIONAL PURPOSES ONLY - SAFE COMMANDS ONLY")
    print("=" * 50)
    app.run(host='0.0.0.0', port=port, debug=False)
