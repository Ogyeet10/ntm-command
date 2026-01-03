--[[
    NTM Command Center
    Main interface for the artillery command system
    
    Usage:
        ntm-command          - Interactive mode
        ntm-command fire X Z - Quick fire at coordinates
        ntm-command volley X Z N - Fire N volleys at coordinates
        ntm-command status   - Show system status
        ntm-command scan     - Scan radar
]]

-- Add lib to package path
package.path = package.path .. ";/home/lib/?.lua;/usr/lib/?.lua"

local component = require("component")
local term = require("term")
local event = require("event")

-- Load framework modules
local core = require("lib.core")
local artillery = require("lib.artillery")
local radar = require("lib.radar")
local network = require("lib.network")

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function init()
    core.info("NTM Command Center initializing...")
    
    -- Scan for components
    local artilleryCount = artillery.scanBatteries()
    local radarCount = radar.scanRadars()
    
    -- Initialize network
    network.init("command_center", "command")
    
    -- Setup network message handlers
    network.onMessage("fire_command", function(msg)
        if msg.target then
            core.info("Received fire command from %s", msg.senderId)
            artillery.fireVolley(msg.target)
        end
    end)
    
    network.onMessage("status_request", function(msg)
        network.send(msg.senderId, "status_response", {
            artillery = artillery.getStatus(),
            radar = radar.getStatus()
        })
    end)
    
    -- Setup radar alerts
    radar.onAlert("new_contact", function(alertType, data)
        -- Broadcast alert to network
        network.sendAlert("incoming_threat", data)
    end)
    
    core.info("Initialization complete")
    core.info("Artillery batteries: %d", artilleryCount)
    core.info("Radars: %d", radarCount)
    
    return true
end

-- ============================================================================
-- COMMAND HANDLERS
-- ============================================================================

local commands = {}

function commands.help()
    print([[
NTM Command Center - Available Commands:

ARTILLERY:
  fire X Y Z        - Fire all batteries at coordinates
  fire X Z          - Fire at X, ground level, Z  
  volley X Z N      - Fire N volleys at coordinates
  volley X Z N D    - Fire N volleys with D second delay
  walk              - Walking fire mode (enter targets one by one)
  batteries         - List all artillery batteries
  enable NAME       - Enable a battery
  disable NAME      - Disable a battery
  
RADAR:
  scan              - Perform radar scan
  threats           - Show current threats
  monitor           - Start continuous monitoring
  stopmonitor       - Stop monitoring
  
NETWORK:
  nodes             - Show known network nodes
  broadcast X Z     - Broadcast fire command to all nodes
  
SYSTEM:
  status            - Show full system status
  reload            - Rescan all components
  config            - Configuration menu
  exit              - Exit command center
]])
end

function commands.fire(args)
    local x, y, z
    
    if #args == 2 then
        x, z = tonumber(args[1]), tonumber(args[2])
        y = 64 -- Default ground level, adjust as needed
    elseif #args >= 3 then
        x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    else
        print("Usage: fire X Z  or  fire X Y Z")
        return
    end
    
    if not x or not z then
        print("Invalid coordinates")
        return
    end
    
    print(string.format("Firing at %d, %d, %d...", x, y, z))
    local results = artillery.fireVolley({x = x, y = y, z = z})
    
    local success, fail = 0, 0
    for name, result in pairs(results) do
        if result then
            success = success + 1
        else
            fail = fail + 1
            print(string.format("  %s: FAILED", name))
        end
    end
    
    print(string.format("Complete: %d success, %d failed", success, fail))
end

function commands.volley(args)
    if #args < 3 then
        print("Usage: volley X Z COUNT [DELAY]")
        return
    end
    
    local x = tonumber(args[1])
    local z = tonumber(args[2])
    local count = tonumber(args[3])
    local delay = tonumber(args[4]) or 2
    
    if not x or not z or not count then
        print("Invalid arguments")
        return
    end
    
    print(string.format("Firing %d volleys at %d, 64, %d (delay: %ds)", count, x, z, delay))
    artillery.fireVolleyBurst({x = x, y = 64, z = z}, count, delay)
end

function commands.walk()
    print("Walking Fire Mode - Enter coordinates, empty line to execute, 'cancel' to abort")
    
    local targets = {}
    
    while true do
        io.write(string.format("Target %d (X Z): ", #targets + 1))
        local input = io.read()
        
        if not input or input == "" then
            break
        elseif input:lower() == "cancel" then
            print("Cancelled")
            return
        end
        
        local x, z = input:match("(-?%d+)%s+(-?%d+)")
        if x and z then
            table.insert(targets, {x = tonumber(x), y = 64, z = tonumber(z)})
            print(string.format("  Added target: %d, 64, %d", x, z))
        else
            print("  Invalid format, use: X Z")
        end
    end
    
    if #targets == 0 then
        print("No targets entered")
        return
    end
    
    print(string.format("Executing walking fire on %d targets...", #targets))
    artillery.walkingFire(targets, 1)
end

function commands.batteries()
    artillery.printStatus()
end

function commands.enable(args)
    if #args < 1 then
        print("Usage: enable BATTERY_NAME")
        return
    end
    if artillery.setBatteryEnabled(args[1], true) then
        print("Battery enabled: " .. args[1])
    end
end

function commands.disable(args)
    if #args < 1 then
        print("Usage: disable BATTERY_NAME")
        return
    end
    if artillery.setBatteryEnabled(args[1], false) then
        print("Battery disabled: " .. args[1])
    end
end

function commands.scan()
    print("Scanning radar...")
    
    local entities = radar.scan()
    
    if #entities == 0 then
        print("No contacts detected")
        return
    end
    
    print(string.format("Detected %d contacts:", #entities))
    
    for _, e in ipairs(entities) do
        local threatStr = ({"LOW", "MEDIUM", "HIGH", "CRITICAL"})[e.threatLevel]
        print(string.format("  [%s] %s at %.0f, %.0f, %.0f (dist: %.0fm)",
              threatStr, e.typeName, e.position.x, e.position.y, e.position.z, e.distance))
    end
end

function commands.threats()
    local threats = radar.getTrackedThreats()
    
    if #threats == 0 then
        print("No active threats")
        return
    end
    
    print(string.format("Active threats (%d):", #threats))
    for _, t in ipairs(threats) do
        local threatStr = ({"LOW", "MEDIUM", "HIGH", "CRITICAL"})[t.threatLevel]
        print(string.format("  [%s] %s @ %.0f, %.0f, %.0f",
              threatStr, t.typeName, t.position.x, t.position.y, t.position.z))
    end
end

function commands.monitor()
    radar.startMonitoring(1)
    print("Radar monitoring started (1s interval)")
    print("Threats will be announced automatically")
end

function commands.stopmonitor()
    radar.stopMonitoring()
    print("Radar monitoring stopped")
end

function commands.nodes()
    network.printStatus()
end

function commands.broadcast(args)
    if #args < 2 then
        print("Usage: broadcast X Z")
        return
    end
    
    local x, z = tonumber(args[1]), tonumber(args[2])
    if not x or not z then
        print("Invalid coordinates")
        return
    end
    
    print(string.format("Broadcasting fire command: %d, 64, %d", x, z))
    network.broadcastFireCommand({x = x, y = 64, z = z})
end

function commands.status()
    print("")
    artillery.printStatus()
    print("")
    radar.printStatus()
    print("")
    network.printStatus()
end

function commands.reload()
    print("Rescanning components...")
    local artCount = artillery.scanBatteries()
    local radarCount = radar.scanRadars()
    print(string.format("Found: %d batteries, %d radars", artCount, radarCount))
end

function commands.config()
    print("Configuration options:")
    print("  1. Set battery types")
    print("  2. Configure radar settings")
    print("  3. Set network node ID")
    print("  4. Save configuration")
    print("  5. Load configuration")
    print("  0. Back")
    
    io.write("Select: ")
    local choice = io.read()
    
    if choice == "1" then
        for name, _ in pairs(artillery.batteries) do
            io.write(string.format("Type for %s (rocket/cannon): ", name))
            local t = io.read()
            if t == "rocket" or t == "cannon" then
                artillery.setBatteryType(name, t)
            end
        end
    elseif choice == "2" then
        io.write("Scan missiles (y/n): ")
        local missiles = io.read():lower() == "y"
        io.write("Scan shells (y/n): ")
        local shells = io.read():lower() == "y"
        io.write("Scan players (y/n): ")
        local players = io.read():lower() == "y"
        io.write("Smart mode (y/n): ")
        local smart = io.read():lower() == "y"
        radar.configure(1, missiles, shells, players, smart)
    elseif choice == "4" then
        artillery.saveConfig()
        print("Configuration saved")
    elseif choice == "5" then
        artillery.loadConfig()
        print("Configuration loaded")
    end
end

-- ============================================================================
-- MAIN LOOP
-- ============================================================================

local function parseCommand(input)
    local parts = {}
    for part in input:gmatch("%S+") do
        table.insert(parts, part)
    end
    
    local cmd = parts[1]
    local args = {}
    for i = 2, #parts do
        table.insert(args, parts[i])
    end
    
    return cmd, args
end

local function interactive()
    print([[
╔═══════════════════════════════════════════════════════════╗
║            NTM COMMAND CENTER v1.0                        ║
║         Artillery Fire Control System                     ║
╚═══════════════════════════════════════════════════════════╝
]])
    print("Type 'help' for commands, 'exit' to quit")
    print("")
    
    while true do
        io.write("NTM> ")
        local input = io.read()
        
        if not input then break end
        
        input = input:gsub("^%s*(.-)%s*$", "%1") -- trim
        
        if input == "" then
            -- Do nothing
        elseif input == "exit" or input == "quit" then
            break
        else
            local cmd, args = parseCommand(input)
            
            if commands[cmd] then
                local success, err = pcall(commands[cmd], args)
                if not success then
                    print("Error: " .. tostring(err))
                end
            else
                print("Unknown command: " .. cmd)
                print("Type 'help' for available commands")
            end
        end
    end
    
    print("Shutting down...")
    radar.stopMonitoring()
    network.shutdown()
end

local function main(args)
    if not init() then
        print("Initialization failed!")
        return 1
    end
    
    -- Handle command-line arguments for quick commands
    if #args > 0 then
        local cmd = args[1]
        local cmdArgs = {}
        for i = 2, #args do
            table.insert(cmdArgs, args[i])
        end
        
        if commands[cmd] then
            commands[cmd](cmdArgs)
        else
            print("Unknown command: " .. cmd)
        end
        
        network.shutdown()
        return 0
    end
    
    -- Interactive mode
    interactive()
    return 0
end

-- Run
local args = {...}
os.exit(main(args))
