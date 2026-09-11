# 1. Luanti/QGIS

A comprehensive system for tracking and storing player positions from a Luanti (formerly Minetest) game server using **PostgreSQL**, with real-time map rendering and HTTP hosting capabilities.

> [!NOTE]
> This project uses **PostgreSQL** with PostGIS for advanced GIS capabilities and efficient spatial tracking.

## 1.1. Features

- **Real-time Position Tracking**: Captures player positions every second via Luanti mod
- **Auto Map Rendering**: Generates map images every 15 seconds
- **HTTP Map Server**: Serves rendered maps via HTTP for QGIS integration
- **PostgreSQL Database**: Robust data storage with spatial extensions
- **One-Command Deployment**: Unified deployment script for production
- **Auto-Archiving**: Intelligent data management with live/archive tables

## 1.2. Quick Start

### 1.2.1. Prerequisites

- Ubuntu 20.04+ or Debian 11+
- 2GB RAM minimum (4GB recommended)
- Root or sudo access

### 1.2.2. Installation

```bash
# Clone the repository
sudo bash
cd /root 

git clone https://github.com/Eph777/EduTerra.git
cd EduTerra

# Run unified deployment (interactive)
./bin/deploy.sh

# Or for production (non-interactive)
./bin/deploy.sh --auto --world myworld
```

That's it! The deployment script will:
1. Install PostgreSQL and all dependencies
2. Set up Python Flask server
3. Install Luanti game server
4. Compile map renderer
5. Configure systemd services
6. Set up firewall rules

### 1.2.3. Start Playing

```bash
# Start Luanti server
~/start-luanti.sh myworld 30000

# Connect from your Luanti client
# Server: <your-server-ip>
# Port: 30000
```

## 1.3. Repository Structure

```
luanti-position-tracker/
├── bin/
│   └── deploy.sh              # Unified deployment script
├── src/
│   ├── server.py              # Flask position tracker
│   ├── range_server.py        # HTTP map server
│   └── lib/
│       └── common.sh          # Shared bash utilities
├── scripts/
│   ├── setup/
│   │   ├── postgresql.sh      # Database setup
│   │   ├── mapper.sh          # Map renderer setup
│   ├── server/
│   │   ├── start-luanti.sh    # Start game server
│   │   ├── migrate-backend.sh # Backend migration
│   │   └── reset-env.sh       # Environment reset
│   └── map/
│       ├── render.sh          # Render map once  
│       ├── auto-render.sh     # Auto-render loop
│       └── setup-hosting.sh   # Setup map hosting
├── config/
│   └── .env.example           # Configuration template
├── mod/
│   ├── init.lua               # Luanti/QGIS mod
│   └── mod.conf               # Mod configuration
├── schema.sql                 # PostgreSQL schema
├── requirements.txt           # Python dependencies
├── README.md                  # This file
└── DEPLOYMENT.md              # Detailed deployment guide
```

## 1.4. System architecture
![system architecture](public/assets/system_architecture.png)

## 1.5. Deployment Options

### 1.5.1. Interactive Setup
```bash
./bin/deploy.sh
```
Prompts for confirmation at each step. Best for first-time setup.

### 1.5.2. Automated Setup (Production)
```bash
./bin/deploy.sh --auto --world production
```
Non-interactive deployment. Perfect for CI/CD or remote servers.

### 1.5.3. Update Existing Deployment
```bash
./bin/deploy.sh --update
```
Pulls latest code, updates dependencies, and restarts services.

### 1.5.4. Check Status
```bash
./bin/deploy.sh --status
```
Shows status of all services and components.

## 1.6. Manual Setup

If you prefer granular control:

```bash
# 1. Setup PostgreSQL
./scripts/setup/postgresql.sh

# 2. Migrate world backend
./scripts/server/migrate-backend.sh myworld

# 3. Setup map renderer
./scripts/setup/mapper.sh myworld

# 4. Setup map hosting
./scripts/map/setup-hosting.sh myworld
```

## 1.7. Configuration

Edit `.env` in the project root:

```bash
# Database
DB_HOST=localhost
DB_NAME=luanti_db
DB_USER=luanti
DB_PASS=postgres123
DB_PORT=5432

# Servers
FLASK_PORT=5000
LUANTI_PORT=30000
MAP_SERVER_PORT=8080

# Map rendering
MAP_RENDER_INTERVAL=15
```

> [!WARNING]
> Change default passwords before deploying to production!

## 1.8. Service Management

### 1.8.1. Starting Luanti Server

#### 1.8.1.1. Foreground Mode (Interactive)
```bash
# Start server in foreground (Ctrl+C to stop)
~/start-luanti.sh myworld 30000

# Or using the script directly
./scripts/server/start-luanti.sh myworld 30000
```

#### 1.8.1.2. Service Mode (Background)
```bash
# Start as systemd service (runs in background)
~/start-luanti.sh myworld 30000 --service

# Or using the script directly
./scripts/server/start-luanti.sh myworld 30000 --service
```

#### 1.8.1.3. With Map Hosting
```bash
# Start server with automatic map rendering and hosting
~/start-luanti.sh myworld 30000 --service --map 8080

# This will:
# - Start the Luanti game server
# - Setup and start map renderer (auto-render every 15s)
# - Setup and start map HTTP server on port 8080
# - Open firewall ports automatically
```

When started as a service, you get:
- Automatic restart on failure
- Persistent logs via journalctl
- Starts automatically on boot
- Runs in background

**Service Management:**
```bash
# Check service status
sudo systemctl status luanti-server@myworld

# Stop service
sudo systemctl stop luanti-server@myworld

# Restart service
sudo systemctl restart luanti-server@myworld

# View logs
sudo journalctl -u luanti-server@myworld -f

# Disable auto-start
sudo systemctl disable luanti-server@myworld
```

### 1.8.2. View Logs

```bash
# Flask server logs
sudo journalctl -u luanti-tracker-postgresql -f

# Map render logs
sudo journalctl -u luanti-map-render -f

# Map server logs
sudo journalctl -u luanti-map-server -f

# Luanti game server logs
sudo journalctl -u luanti-server@myworld -f
```

### 1.8.3. Automated Background Services

Three additional services are created automatically by the deployment:

```bash
# Position tracker (Flask server - Port 5000)
sudo systemctl status luanti-tracker-postgresql
sudo systemctl restart luanti-tracker-postgresql

# Map renderer (auto-render every 15s)
sudo systemctl status luanti-map-render
sudo systemctl restart luanti-map-render

# Map HTTP server (serves map.png - Port 8080)
sudo systemctl status luanti-map-server
sudo systemctl restart luanti-map-server
```

## 1.9. API Endpoints

### 1.9.1. Health Check
```bash
GET /
```
Returns: `{"status": "running"}`

### 1.9.2. Log Position
```bash
POST /position
Content-Type: application/json

{
  "player": "player_name",
  "world": "world_name",
  "pos": {
    "x": 10.5,
    "y": 20.0,
    "z": -5.3
  }
}
```
Returns: `{"status": "success"}`

**Note**: The `world` parameter is automatically sent by the mod. It detects the world name from the minetest world path.

### 1.9.3. Get Traces
```bash
GET /traces?player=player_name&world=world_name&limit=100
```
Returns list of player position traces.

**Query Parameters:**
- `player` (optional): Filter by player name
- `world` (optional): Filter by world name
- `limit` (optional, default: 100): Number of records to return

### 1.9.4. Create World View
```bash
POST /create_world_view/<world_name>
```
Creates a QGIS-ready view for a specific world.

**Example:**
```bash
curl -X POST http://localhost:5000/create_world_view/production
```

Returns: `{"status": "success", "message": "Created view: view_live_positions_production"}`

**Note**: This is automatically called when the mod loads, so manual creation is typically not needed.

### 1.9.5. Player Logout
```bash
POST /logout
Content-Type: application/json

{"player": "player_name"}
```
Archives player traces.

## 1.10. Querying Data

### 1.10.1. PostgreSQL

```bash
# Connect to database
psql -U luanti -d luanti_db

# View live positions
SELECT * FROM player_traces ORDER BY timestamp DESC LIMIT 10;

# Count traces by player
SELECT player_name, COUNT(*) as trace_count 
FROM player_traces 
GROUP BY player_name;

# View archived data
SELECT * FROM player_traces_archive 
WHERE player_name = 'username' 
ORDER BY timestamp DESC;
```

### 1.10.2. QGIS Integration

#### 1.10.2.1. World-Specific Views

Each world automatically gets its own QGIS view when the mod loads:
- `view_live_positions` - All worlds combined
- `view_live_positions_production` - Production world only
- `view_live_positions_testing` - Testing world only
- `view_live_positions_<worldname>` - Specific world

**Adding to QGIS:**

1. **Install QGIS**

2. **Add Raster Layer (Map Background)**:
   - Layer → Add Layer → Add Raster Layer
   - Source: `http://<server-ip>:8080/map.png`
   - Configure georeferencing with `map.pgw` world file

3. **Add PostGIS Layer (Player Positions)**:
   - Layer → Add Layer → Add PostGIS Layers
   - Create new connection to your PostgreSQL database
   - Select world-specific view (e.g., `view_live_positions_production`)
   - Set as point layer

4. **Style the Layer**:
   - Right-click layer → Properties → Symbology
   - Add labels with player names
   - Style points as needed

**Example Multi-World Setup:**

```bash
# QGIS shows different colors for each world:
# - view_live_positions_production (red points)
# - view_live_positions_testing (blue points)
# - view_live_positions_creative (green points)
```

**Querying Specific Worlds:**

```sql
# View all active players in production world
SELECT * FROM view_live_positions_production;

# Query historical data for a specific world
SELECT player_name, x, y, z, timestamp 
FROM player_traces_archive 
WHERE world_name = 'production' 
ORDER BY timestamp DESC 
LIMIT 100;
```

## 1.11. Troubleshooting

### 1.11.1. Service Won't Start

```bash
# Check logs
sudo journalctl -u luanti-tracker-postgresql -n 100

# Verify Python environment
source venv/bin/activate
python -c "import psycopg2; print('OK')"
```

### 1.11.2. Port Conflicts

```bash
# Check what's using port 5000
sudo lsof -i :5000

# Kill process
sudo kill -9 <PID>

# Or let deploy script handle it
./bin/deploy.sh --auto
```

### 1.11.3. Database Connection Issues

```bash
# Test connection
PGPASSWORD=postgres123 psql -U luanti -d luanti_db -c "SELECT 1;"

# Check PostgreSQL service
sudo systemctl status postgresql

# Review authentication
sudo cat /etc/postgresql/*/main/pg_hba.conf
```

### 1.11.4. Map Not Rendering

```bash
# Check mapper executable
ls -la ~/minetest-mapper/minetestmapper

# Test manual render
./scripts/map/render.sh myworld

# Check render service
sudo systemctl status luanti-map-render
sudo journalctl -u luanti-map-render -f
```

## 1.12. Backup & Restore

### 1.12.1. Database Backup

```bash
# Backup
pg_dump -U luanti -d luanti_db > backup_$(date +%Y%m%d).sql

# Restore
psql -U luanti -d luanti_db < backup_20260125.sql
```

### 1.12.2. World Backup

```bash
# Backup
tar -czf world_backup.tar.gz ~/snap/luanti/common/.minetest/worlds/myworld

# Restore
tar -xzf world_backup.tar.gz -C ~/snap/luanti/common/.minetest/worlds/
```

## 1.13. Security

1. **Change Default Passwords**: Edit `.env` and update database passwords
2. **Restrict PostgreSQL Access**: Edit `pg_hba.conf` to limit IP ranges
3. **Enable HTTPS**: Use Nginx reverse proxy with Let's Encrypt
4. **Regular Updates**: Run `./bin/deploy.sh --update` regularly
5. **Firewall Rules**: Only open required ports

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed security hardening.

## 1.14. Development

### 1.14.1. Running Locally

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export $(cat .env | xargs)

# Run Flask server
python src/server.py
```

### 1.14.2. Testing Changes

```bash
# Test position logging
curl -X POST http://localhost:5000/position \
  -H "Content-Type: application/json" \
  -d '{"player":"test","pos":{"x":1,"y":2,"z":3}}'

# Verify in database
PGPASSWORD=postgres123 psql -U luanti -d luanti_db \
  -c "SELECT * FROM player_traces;"
```

## 1.15. Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 1.16. Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)**: Comprehensive production deployment guide
- **[schema.sql](schema.sql)**: Database schema documentation
- **[config/.env.example](config/.env.example)**: Configuration options

## 1.17. License

This project is open source and available for educational and personal use.

## 1.18. Acknowledgments

- Built for [Luanti](https://www.luanti.org/) (formerly Minetest)
- Uses [Flask](https://flask.palletsprojects.com/) web framework
- [PostgreSQL](https://www.postgresql.org/) with [PostGIS](https://postgis.net/)
- Map rendering by [minetestmapper](https://github.com/luanti-org/minetestmapper)

## 1.19. Support

For detailed deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

For issues:
1. Check logs: `sudo journalctl -u luanti-tracker-postgresql`
2. Run status check: `./bin/deploy.sh --status`
3. Review troubleshooting section above
4. Open an issue on GitHub

## 1.20. Contact

Ephraim BOURIAHI - amar-ephraim.bouriahi@etu.u-pec.fr
Project Link: [https://github.com/Eph777/Position](https://github.com/Eph777/Position)
