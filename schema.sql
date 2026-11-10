-- Copyright (C) 2026 Ephraim BOURIAHI
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

-- PostgreSQL Schema for Luanti/QGIS
-- This schema stores player position traces with timestamps and world information

CREATE TABLE IF NOT EXISTS player_traces (
    id SERIAL PRIMARY KEY,
    player_name VARCHAR(100) NOT NULL,
    world_name VARCHAR(100),
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    z DOUBLE PRECISION NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS player_traces_archive (
    id SERIAL PRIMARY KEY,
    player_name VARCHAR(100) NOT NULL,
    world_name VARCHAR(100),
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL,
    z DOUBLE PRECISION NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for faster querying
CREATE INDEX IF NOT EXISTS idx_player_traces_archive_name_time ON player_traces_archive(player_name, timestamp);
CREATE INDEX IF NOT EXISTS idx_player_traces_world ON player_traces(world_name);
CREATE INDEX IF NOT EXISTS idx_player_traces_archive_world ON player_traces_archive(world_name);
CREATE INDEX IF NOT EXISTS idx_player_traces_world_name ON player_traces(world_name, player_name);

-- Create optimized view for QGIS live tracking (latest position per player, all worlds)
CREATE OR REPLACE VIEW view_live_positions AS
SELECT DISTINCT ON (player_name, world_name) 
    id, player_name, world_name, x, y, z, timestamp,
    ST_SetSRID(ST_MakePoint(x, z), 0) AS geom
FROM player_traces
WHERE timestamp > NOW() - INTERVAL '60 seconds'
ORDER BY player_name, world_name, timestamp DESC;

-- Function to create world-specific views dynamically
-- Usage: SELECT create_world_view('myworld');
CREATE OR REPLACE FUNCTION create_world_view(world_name_param TEXT) RETURNS TEXT AS $$
DECLARE
    view_name TEXT;
    safe_world_name TEXT;
BEGIN
    -- Sanitize world name for use in identifiers (replace special chars with underscore)
    safe_world_name := regexp_replace(world_name_param, '[^a-zA-Z0-9_]', '_', 'g');
    view_name := 'view_live_positions_' || safe_world_name;
    
    EXECUTE format('
        CREATE OR REPLACE VIEW %I AS
        SELECT DISTINCT ON (player_name) 
            id, player_name, world_name, x, y, z, timestamp,
            ST_SetSRID(ST_MakePoint(x, z), 0) AS geom
        FROM player_traces
        WHERE world_name = %L
          AND timestamp > NOW() - INTERVAL ''60 seconds''
        ORDER BY player_name, timestamp DESC
    ', view_name, world_name_param);
    
    RETURN 'Created view: ' || view_name;
END;
$$ LANGUAGE plpgsql;
---fqfqzfqizhfqzfq