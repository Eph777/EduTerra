#!/bin/bash
# Copyright (C) 2026 Ephraim BOURIAHI
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Setup HTTPS hosting for the EduTerra whiteboard page
# Usage: ./setup-whiteboard.sh [port] [cert_file] [key_file]
#   Without cert/key, a self-signed certificate is generated.

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh

PORT="$1"
CERT_FILE="$2"
KEY_FILE="$3"

if [ -z "$PORT" ]; then
    read -p "Port for the whiteboard page [8443]: " PORT
    PORT="${PORT:-8443}"
fi

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    print_error "Invalid port: $PORT"
    exit 1
fi

if [ -n "$CERT_FILE" ] && [ -z "$KEY_FILE" ]; then
    print_error "Usage: $0 [port] [cert_file] [key_file]"
    echo "  Pass both cert and key, or neither to generate a self-signed certificate"
    exit 1
fi

# Configuration
SERVICE_USER=$(get_current_user)
PROJECT_ROOT=$(get_project_root)
PAGE_FILE="$PROJECT_ROOT/public/assets/EduTerraWhiteboard.html"
CERT_DIR="$PROJECT_ROOT/certs/whiteboard"
SERVICE_NAME="eduterra-whiteboard"

if [ ! -f "$PAGE_FILE" ]; then
    print_error "Page not found: $PAGE_FILE"
    exit 1
fi

if ! check_port "$PORT" --kill; then
    exit 1
fi

# Generate a self-signed certificate if none was provided
if [ -z "$CERT_FILE" ]; then
    CERT_FILE="$CERT_DIR/cert.pem"
    KEY_FILE="$CERT_DIR/key.pem"

    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        SERVER_IP=$(hostname -I | awk '{print $1}')
        print_info "Generating self-signed certificate for $(hostname) / $SERVER_IP..."
        mkdir -p "$CERT_DIR"
        openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
            -keyout "$KEY_FILE" -out "$CERT_FILE" \
            -subj "/CN=$(hostname)" \
            -addext "subjectAltName=DNS:$(hostname),DNS:localhost,IP:$SERVER_IP,IP:127.0.0.1" \
            2>/dev/null || { print_error "Certificate generation failed"; exit 1; }
        sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$CERT_DIR"
        chmod 600 "$KEY_FILE"
    else
        print_info "Reusing existing certificate in $CERT_DIR"
    fi
fi

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    print_error "Certificate or key not found: $CERT_FILE / $KEY_FILE"
    exit 1
fi

# Create HTTPS Server Service
print_info "Creating ${SERVICE_NAME}.service..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=EduTerra Whiteboard HTTPS Server (Port ${PORT})
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
ExecStart=/usr/bin/python3 $PROJECT_ROOT/src/whiteboard_server.py ${PORT} --cert ${CERT_FILE} --key ${KEY_FILE} --file ${PAGE_FILE}
Restart=always
# Allows ports below 1024 (e.g. 443) without running as root
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
# Keep it from competing with the game server
Nice=10
MemoryMax=64M

[Install]
WantedBy=multi-user.target
EOF

# Open Firewall Port
print_info "Opening port ${PORT}..."
sudo ufw allow ${PORT}/tcp

# Start Service
print_info "Starting service..."
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}
sudo systemctl restart ${SERVICE_NAME}

print_info "Whiteboard service started successfully!"
echo "Whiteboard is now hosted at: https://$(hostname -I | awk '{print $1}'):${PORT}/"
echo ""
print_info "Service Management Commands:"
echo "  Status:  sudo systemctl status ${SERVICE_NAME}"
echo "  Logs:    sudo journalctl -u ${SERVICE_NAME} -f"
