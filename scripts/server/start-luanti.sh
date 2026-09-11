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

# Start Luanti game server
# Usage: ./start-luanti.sh <world_name> [port] [--service] [--map MAP_PORT]
#   Without --service: Runs in foreground
#   With --service: Creates and starts systemd service
#   With --map PORT: Also starts map rendering and hosting services on specified port

# Load common functions
PROJECT_ROOT=$(cat /root/.proj_root)
source $PROJECT_ROOT/src/lib/common.sh
# Defaults
WORLD=""
PORT=30000
IS_SERVICE=false
MAP_PORT=""
INTERACTIVE=false
GAME_ID="minetest_game"
MAP_RENDER_INTERVAL=15

# Parse Positional Arguments
# Check if current First argument is existent and NOT a flag
if [[ -n "$1" && "$1" != -* ]]; then
    WORLD="$1"
    shift
fi

# Check if current First argument (was second) is a number (Port)
if [[ -n "$1" && "$1" =~ ^[0-9]+$ ]]; then
    PORT="$1"
    shift
fi

# Parse Flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            echo "Usage: $0 [-i|--interactive] <world_name> [port] [--service] [--map MAP_PORT] [--map-interval INTERVAL]"
            echo "  -i, --interactive        Run in interactive mode"
            echo "  <world_name>             Name of the world folder (Required unless interactive)"
            echo "  [port]                   UDP Port for game server (Default: 30000)"
            echo "  --service                Create and start as systemd service"
            echo "  --map PORT               Also start map hosting on TCP PORT"
            echo "  --map-interval INTERVAL  Map render interval in seconds (Default: 15)"
            exit 0
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        --service)
            IS_SERVICE=true
            shift
            ;;
        --game)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --game requires a game ID argument"
                exit 1
            fi
            GAME_ID="$2"
            shift 2
            ;;
        --map)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --map requires a port number argument"
                exit 1
            fi
            MAP_PORT="$2"
            shift 2
            ;;
        --map-interval)
            if [[ -z "$2" || "$2" == -* || ! "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --map-interval requires a positive integer argument (seconds)"
                exit 1
            fi
            MAP_RENDER_INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument '$1'"
            exit 1
            ;;
    esac
done

if [[ "$INTERACTIVE" == true ]]; then
    # interactive personalization
    echo "--- Server Configuration ---"


    GAMES_DIR="/root/snap/luanti/common/.minetest/games"
    existing_games=()
    if [ -d "$GAMES_DIR" ]; then
        for g in "$GAMES_DIR"/*; do
            if [ -d "$g" ]; then
                existing_games+=("$(basename "$g")")
            fi
        done
    fi
    
    


    while true; do
        echo "[0] download a new game"
        for i in "${!existing_games[@]}"; do
            echo "[$((i + 1))] ${existing_games[$i]}"
        done

        read -p "game choice : " -r G_CHOICE

        if [[ "$G_CHOICE" =~ ^[0-9]+$ ]]; then
            if [[ "$G_CHOICE" -eq 0 ]]; then
                # download a new game
                read -p "game download link : " -r G_LINK
                if [[ -n "$G_LINK" ]]; then
                    if install_game_from_zip "$G_LINK"; then
                        existing_games=()
                        if [ -d "$GAMES_DIR" ]; then
                            for g in "$GAMES_DIR"/*; do
                                if [ -d "$g" ]; then
                                    existing_games+=("$(basename "$g")")
                                fi
                            done
                        fi
                    fi
                else
                    print_error "Link cannot be empty."
                fi
            else

                G_INDEX=$((G_CHOICE - 1))
                if [[ "$G_INDEX" -lt 0 ]] || [[ "$G_INDEX" -ge "${#existing_games[@]}" ]]; then
                    print_error "Invalid selection."
                else
                    GAME_ID="${existing_games[$G_INDEX]}"
                    break
                fi
            fi
        else
            print_error "Invalid choice: please enter a number."
        fi
    done

    
    

    WORLDS_DIR="/root/snap/luanti/common/.minetest/worlds"
    existing_worlds=()
    if [ -d "$WORLDS_DIR" ]; then
        for w in "$WORLDS_DIR"/*; do
            if [ -d "$w" ]; then
                existing_worlds+=("$(basename "$w")")
            fi
        done
    fi

    echo "[0] create a new world"
    for i in "${!existing_worlds[@]}"; do
        echo "[$((i + 1))] ${existing_worlds[$i]}"
    done
    
    while true; do
        read -p "world choice : " -r W_CHOICE
        if [[ "$W_CHOICE" =~ ^[0-9]+$ ]]; then
            if [[ "$W_CHOICE" -eq 0 ]]; then
                read -p "new world name : " -r NEW_WORLD
                if [[ -n "$NEW_WORLD" ]]; then
                    WORLD="$NEW_WORLD"
                    break
                else
                    print_error "Name cannot be empty."
                fi
            else
                W_INDEX=$((W_CHOICE - 1))
                if [[ "$W_INDEX" -lt 0 ]] || [[ "$W_INDEX" -ge "${#existing_worlds[@]}" ]]; then
                    print_error "Invalid selection."
                else
                    WORLD="${existing_worlds[$W_INDEX]}"
                    break
                fi
            fi
        else
            print_error "Invalid choice: please enter a number."
        fi
    done

    read -p "game server port (default: $PORT) : " -r
    if [[ -n "$REPLY" ]]; then PORT="$REPLY"; fi

    read -p "map hosting port (default: ${MAP_PORT:-none}) : " -r
    if [[ -n "$REPLY" ]]; then MAP_PORT="$REPLY"; fi

    if [[ -n "$MAP_PORT" ]]; then
        read -p "map render interval in seconds (default: $MAP_RENDER_INTERVAL) : " -r
        if [[ -n "$REPLY" ]]; then MAP_RENDER_INTERVAL="$REPLY"; fi
    fi

    curr_svc="n"
    if [ "$IS_SERVICE" = true ]; then curr_svc="y"; fi
    read -p "run as systemd service? (y/n) (default: $curr_svc) : " -n 1 -r
    echo
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        IS_SERVICE=true
    elif [[ "$REPLY" =~ ^[Nn]$ ]]; then
        IS_SERVICE=false
    fi
    echo
fi

sudo ufw allow "$PORT/udp"

if [ -z "$WORLD" ]; then
    print_error "Usage: $0 [-i|--interactive] <world_name> [port] [--service] [--map MAP_PORT]"
    echo "  With -i, --interactive:  Prompts for configuration interactively"
    echo "  Without --service: Runs in foreground"
    echo "  With --service: Creates and starts systemd service"
    echo "  With --map PORT: Also starts Mapserver hosting on specified port"
    exit 1
fi

USER_HOME=$(get_user_home)
CURRENT_USER=$(get_current_user)
WORLD_PATH="$USER_HOME/snap/luanti/common/.minetest/worlds/$WORLD"
WORLD_MT="$WORLD_PATH/world.mt"

# Create world directory if it doesn't exist
if [ ! -d "$WORLD_PATH" ]; then
    print_info "Creating world directory: $WORLD"
    mkdir -p "$WORLD_PATH"
fi

# Create worldmods directory if it doesn't exist
MODS_DIR="$USER_HOME/snap/luanti/common/.minetest/mods"
if [ ! -d "$MODS_DIR" ]; then
    mkdir -p "$MODS_DIR"
fi

# Create mod_archives directory if it doesn't exist
MOD_ARCHIVES_DIR="$USER_HOME/snap/luanti/common/.minetest/mod_archives"
if [ ! -d "$MOD_ARCHIVES_DIR" ]; then
    mkdir -p "$MOD_ARCHIVES_DIR"
fi

# Create or verify world.mt file
if [ ! -f "$WORLD_MT" ]; then
    print_info "Creating world.mt configuration file..."
    cat > "$WORLD_MT" <<EOF
gameid = ${GAME_ID}
backend = sqlite3
player_backend = sqlite3
auth_backend = sqlite3
mod_storage_backend = sqlite3
EOF
    print_info "World configuration created."
else
    print_info "World $WORLD exists."
fi

# Interactive Mod Installation
if [[ "$INTERACTIVE" == true ]]; then
    echo
    echo "--- Mod Installation ---"
    while true; do
        read -p "Would you like to install a mod? (y/n) ==> " -n 1 -r
        echo
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            break
        fi
        
        local_zips=()
        for f in "$MOD_ARCHIVES_DIR"/*.zip; do
            [ -e "$f" ] && local_zips+=("$f")
        done
        
        installed_mods=()
        for d in "$MODS_DIR"/*; do
            [ -d "$d" ] && installed_mods+=("$(basename "$d")")
        done
        
        echo "[0] add mod by URL"
        zip_count=${#local_zips[@]}
        for i in "${!local_zips[@]}"; do
            echo "[$((i + 1))] [ZIP] $(basename "${local_zips[$i]}")"
        done
        for i in "${!installed_mods[@]}"; do
            mod_name="${installed_mods[$i]}"
            
            SCRIPT="$PROJECT_ROOT/scripts/server/install-mod.py"
            submods=()
            submod_statuses=()
            is_modpack=false
            mod_enabled=false
            
            while IFS=: read -r type name status; do
                if [ "$type" = "mod" ]; then
                    if [ "$status" = "enabled" ]; then
                        mod_enabled=true
                    fi
                elif [ "$type" = "modpack" ]; then
                    is_modpack=true
                    if [ "$status" = "enabled" ]; then
                        mod_enabled=true
                    fi
                elif [ "$type" = "submod" ]; then
                    submods+=("$name")
                    if [ "$status" = "enabled" ]; then
                        submod_statuses+=("[ENABLED]")
                    else
                        submod_statuses+=("[DISABLED]")
                    fi
                fi
            done < <(python3 "$SCRIPT" --check-status "$mod_name" --mods-dir "$MODS_DIR" --world-mt "$WORLD_MT")
            
            status_tag="[INSTALLED]"
            if [ "$mod_enabled" = true ]; then
                status_tag="[INSTALLED] [ENABLED]"
            fi
            
            echo "[$((i + 1 + zip_count))] $status_tag $mod_name"
            
            if [ "$is_modpack" = true ]; then
                submod_count=${#submods[@]}
                for ((j=0; j<submod_count; j++)); do
                    prefix="    ├──"
                    if [ "$j" -eq "$((submod_count - 1))" ]; then
                        prefix="    └──"
                    fi
                    echo "$prefix ${submod_statuses[$j]} ${submods[$j]}"
                done
            fi
        done
        
        read -p "your choice : " -r CHOICE
        
        if [[ ! "$CHOICE" =~ ^[0-9]+$ ]]; then
            print_error "Invalid choice: please enter a number."
            continue
        fi

        total_choices=$((zip_count + ${#installed_mods[@]}))
        if [[ "$CHOICE" -gt "$total_choices" ]]; then
            print_error "Invalid selection."
            continue
        fi

        DOWNLOAD_SUCCESS=false
        TEMP_ZIP=""

        if [[ "$CHOICE" -eq 0 ]]; then
            echo "Please provide a ContentDB package ID/URL or GitHub repository URL:"
            read -p "URL or ID ==> " -r MOD_INPUT
            
            if [[ -z "$MOD_INPUT" ]]; then
                print_error "No URL or ID provided."
                continue
            fi
            
            print_info "Running recursive dependency installer..."
            SCRIPT="$PROJECT_ROOT/scripts/server/install-mod.py"
            python3 "$SCRIPT" "$MOD_INPUT" --mods-dir "$MODS_DIR" --world-mt "$WORLD_MT"
            echo
            continue
        elif [[ "$CHOICE" -le "$zip_count" ]]; then
            FILE_INDEX=$((CHOICE - 1))
            LOCAL_FILE="${local_zips[$FILE_INDEX]}"
            print_info "Running local mod installer and dependency resolver..."
            SCRIPT="$PROJECT_ROOT/scripts/server/install-mod.py"
            python3 "$SCRIPT" "$LOCAL_FILE" --mods-dir "$MODS_DIR" --world-mt "$WORLD_MT"
            echo
            continue
        else
            MOD_INDEX=$((CHOICE - 1 - zip_count))
            SELECTED_MOD="${installed_mods[$MOD_INDEX]}"
            
            print_info "Toggling activation for installed mod '$SELECTED_MOD'..."
            SCRIPT="$PROJECT_ROOT/scripts/server/install-mod.py"
            python3 "$SCRIPT" --toggle "$SELECTED_MOD" --mods-dir "$MODS_DIR" --world-mt "$WORLD_MT"
            echo
            continue
        fi
        echo
    done
fi

# Check port availability
if [ "$IS_SERVICE" = true ]; then
    check_port "$PORT" --kill --force || exit 1
else
    check_port "$PORT" --kill || exit 1
fi

# Setup map services if --map is specified
if [ -n "$MAP_PORT" ]; then

    check_port "$MAP_PORT" --kill || exit 1

    print_info "Setting up Mapserver services on port $MAP_PORT..."
    
    # Run map hosting setup script
    print_info "Configuring Mapserver..."
    "$PROJECT_ROOT/scripts/map/setup-hosting.sh" "$WORLD" "$MAP_PORT" "$MAP_RENDER_INTERVAL"|| {
        print_error "Failed to setup map services"
        exit 1
    }
    
    # Ensure mapserver mod is enabled in world.mt
    if ! grep -q "^load_mod_mapserver[ =]*true" "$WORLD_MT"; then
        print_info "Activating mapserver mod in world.mt..."
        grep -v "^load_mod_mapserver[ =]" "$WORLD_MT" > "${WORLD_MT}.tmp" && mv "${WORLD_MT}.tmp" "$WORLD_MT"
        echo "load_mod_mapserver = true" >> "$WORLD_MT"
    fi
    
    # Verify services are running
    sleep 2
    if systemctl is-active --quiet "luanti-mapserver@${WORLD}"; then
        print_info "Map services started successfully!"
        print_info "Map will be available at: http://$(hostname -I | awk '{print $1}'):$MAP_PORT/"
        print_info "QGIS XYZ Tile URL: http://$(hostname -I | awk '{print $1}'):$MAP_PORT/api/map/tiles/{z}/{x}/{y}"
    else
        print_warning "Map services may not have started correctly. Check with:"
        echo "  sudo systemctl status luanti-mapserver@${WORLD}"
    fi
    echo ""
fi

# Service mode: Create and start systemd service
if [ "$IS_SERVICE" = true ]; then
    print_info "Setting up Luanti server as systemd service..."
    
    SERVICE_NAME="luanti-server@${WORLD}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    
    print_info "Creating systemd service: ${SERVICE_NAME}"
    
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Luanti Game Server - ${WORLD} (Port ${PORT})
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${USER_HOME}
ExecStart=/snap/bin/luanti --server --world ${WORLD_PATH} --gameid ${GAME_ID} --port ${PORT}
Restart=always
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=luanti-${WORLD}

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    print_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    # Enable service
    print_info "Enabling ${SERVICE_NAME}..."
    sudo systemctl enable "${SERVICE_NAME}"
    
    # Start service
    print_info "Starting ${SERVICE_NAME}..."
    sudo systemctl start "${SERVICE_NAME}"
    
    # Show status
    echo ""
    print_info "Service started successfully!"
    print_info "Status:"
    sudo systemctl status "${SERVICE_NAME}" --no-pager | head -n 10
    
    echo ""
    print_info "Service Management Commands:"
    echo "  Stop:    sudo systemctl stop ${SERVICE_NAME}"
    echo "  Restart: sudo systemctl restart ${SERVICE_NAME}"
    echo "  Status:  sudo systemctl status ${SERVICE_NAME}"
    echo "  Logs:    sudo journalctl -u ${SERVICE_NAME} -f"
    
else
    # Foreground mode: Run luanti directly
    print_info "Running Luanti server in foreground mode..."
    print_info "World: $WORLD"
    print_info "Port: $PORT"
    print_info "Press Ctrl+C to stop the server"
    echo ""
    
    /snap/bin/luanti --server --world "$WORLD_PATH" --gameid "$GAME_ID" --port "$PORT"
fi