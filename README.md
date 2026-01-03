# NTM Command Framework

A centralized artillery command system for HBM's Nuclear Tech Mod with OpenComputers integration.

## Features

- **Artillery Control**: Manage multiple artillery batteries from a central command
- **Volley Fire**: Coordinate simultaneous fire from all batteries
- **Walking Fire**: Sequential targeting across multiple coordinates
- **Radar Integration**: Track incoming threats and missiles
- **Distributed Network**: Control remote artillery installations over the network
- **Alert System**: Get notified of incoming threats automatically

## Installation

1. Copy all files to an OpenComputers computer
2. Run: `install.lua`
3. Connect your NTM artillery/radar with OC cables

## Quick Start

### Basic Fire Command
```
ntm-command fire 1000 500      # Fire at X=1000, Z=500
ntm-command fire 1000 64 500   # Fire at X=1000, Y=64, Z=500
```

### Volley Fire
```
ntm-command volley 1000 500 5     # Fire 5 volleys
ntm-command volley 1000 500 5 3   # Fire 5 volleys, 3 second delay
```

### Interactive Mode
```
ntm-command
```

## Architecture

### Command Center (ntm-command)
The main control interface. Run this on your primary computer.

Commands:
- `fire X [Y] Z` - Fire at coordinates
- `volley X Z COUNT [DELAY]` - Multiple volleys
- `walk` - Interactive walking fire mode
- `batteries` - List artillery batteries
- `scan` - Radar scan
- `threats` - Show tracked threats
- `monitor` - Start continuous radar monitoring
- `nodes` - Show network nodes
- `broadcast X Z` - Send fire command to all remote batteries
- `status` - Full system status

### Battery Node (ntm-battery)
Run this on computers at remote artillery positions. It receives fire commands from the command center over the network.

```
ntm-battery              # Auto-generated node name
ntm-battery north_base   # Custom node name
```

## Network Setup

### Local Network (Wired)
Connect computers with OpenComputers cables. Use `modem` components (wired or wireless).

### Remote Bases (Linked Cards)
For bases beyond network range, use Linked Cards for infinite-range point-to-point communication.

## File Structure

```
/usr/lib/lib/
  core.lua      - Core utilities
  artillery.lua - Artillery control
  radar.lua     - Radar integration
  network.lua   - Network communication

/usr/bin/
  ntm-command   - Command center
  ntm-battery   - Remote battery node

/etc/ntm/
  config.lua    - Configuration file
  artillery.cfg - Saved battery config
```

## API Reference

### Artillery Module
```lua
local artillery = require("lib.artillery")

-- Scan for batteries
artillery.scanBatteries()

-- Fire at target
artillery.fireVolley({x=1000, y=64, z=500})

-- Multiple volleys
artillery.fireVolleyBurst({x=1000, y=64, z=500}, 5, 2)  -- 5 volleys, 2s delay

-- Walking fire
artillery.walkingFire({
    {x=1000, y=64, z=500},
    {x=1010, y=64, z=510},
    {x=1020, y=64, z=520}
}, 1)  -- 1 second between targets
```

### Radar Module
```lua
local radar = require("lib.radar")

-- Scan for contacts
local entities = radar.scan()

-- Get threats only
local threats = radar.getTrackedThreats()

-- Start monitoring
radar.startMonitoring(1)  -- 1 second interval

-- Register alert callback
radar.onAlert("new_contact", function(alertType, entity)
    print("Incoming: " .. entity.typeName)
end)
```

### Network Module
```lua
local network = require("lib.network")

-- Initialize
network.init("my_base", "command")

-- Send fire command to specific node
network.sendFireCommand("north_battery", {x=1000, y=64, z=500})

-- Broadcast to all nodes
network.broadcastFireCommand({x=1000, y=64, z=500})

-- Handle incoming messages
network.onMessage("fire_command", function(msg)
    -- Execute fire
end)
```

## Extending the Framework

The framework is designed to be extended. You can add support for:
- Nuclear reactors (RBMK, PWR, etc.)
- Turrets (automatic defense)
- Missile silos
- Storage systems (if APIs available)

Each NTM component type has its own OC component name and API. See the HBM Wiki for full documentation.

## Tips

1. **Configure battery types**: After scanning, use `config` to set each battery as "rocket" or "cannon". Cannons report if targets are out of range.

2. **Use radar monitoring**: Run `monitor` to get automatic alerts when threats are detected.

3. **Save your config**: After setting up batteries, run `config` → Save to persist settings.

4. **Network heartbeats**: The system automatically discovers other nodes via heartbeat broadcasts.

## Troubleshooting

**No batteries found**
- Ensure OC cables connect directly to artillery blocks
- Check that artillery has power

**Network not working**
- Verify modem components are installed
- Check that ports aren't blocked

**Commands fail silently**
- Check `/var/log/ntm-battery.log` on battery nodes
- Run in interactive mode for more verbose output

---

*"With great artillery comes great responsibility"*
