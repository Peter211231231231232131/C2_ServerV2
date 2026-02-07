from flask import Flask, request, jsonify
import time
import uuid

app = Flask(__name__)

# Simple in-memory storage
clients = {}
command_queues = {}

@app.route('/')
def index():
    return '''
    <!DOCTYPE html>
    <html>
    <head><title>Simple Server</title></head>
    <body>
        <h1>🚀 Simple Management Server</h1>
        <p>Active Clients: {}</p>
        <p>Server is running!</p>
    </body>
    </html>
    '''.format(len(clients))

@app.route('/heartbeat', methods=['POST'])
def heartbeat():
    try:
        data = request.get_json() or {}
        client_id = data.get('client_id', f'client-{uuid.uuid4().hex[:8]}')
        
        # Update client
        clients[client_id] = {
            'last_seen': time.time(),
            'os': data.get('os', 'unknown'),
            'arch': data.get('arch', 'unknown'),
            'ip': request.remote_addr
        }
        
        # Get pending commands
        commands = command_queues.get(client_id, [])
        if client_id in command_queues:
            command_queues[client_id] = []
        
        return jsonify({
            'status': 'success',
            'commands': commands,
            'timestamp': time.time()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/result', methods=['POST'])
def result():
    try:
        data = request.get_json()
        print(f"Result from {data.get('client_id')}: {data.get('status')}")
        return jsonify({'status': 'received'})
    except:
        return jsonify({'status': 'error'}), 400

@app.route('/command', methods=['POST'])
def command():
    client_id = request.form.get('client_id')
    action = request.form.get('action', 'echo')
    
    if not client_id:
        return "Missing client_id", 400
    
    command = {
        'command_id': f'cmd-{uuid.uuid4().hex[:8]}',
        'action': action,
        'params': {'message': 'Hello from server!'},
        'timestamp': time.time()
    }
    
    if client_id not in command_queues:
        command_queues[client_id] = []
    
    command_queues[client_id].append(command)
    
    return f'Command queued for {client_id}'

if __name__ == '__main__':
    print("🚀 Server starting on port 8080")
    app.run(host='0.0.0.0', port=8080)
