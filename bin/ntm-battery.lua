#!/usr/bin/env lua
--[[
    NTM Artillery Battery Node
    Runs on remote artillery installations, receives commands from command center
    
    This is a headless daemon that listens for fire commands over the network.
    
    Usage:
        ntm-battery            - Run with auto-detected name
        ntm-battery NODENAME   - Run with specific name
]]

package.path = package.path .. ";/home/lib/?.lua;/usr/lib/?.lua"

local event = require("event")
local core = require("lib.core")
local artillery = require("lib.artillery")
local network = require("lib.network")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local config = {
    nodeName = nil,
    autoFire = true,     -- Automatically execute fire commands
    reportStatus = true, -- Respond to status requests
    logFile = "/var/log/ntm-battery.log"
}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function init(nodeName)
    config.nodeName = nodeName or "battery_" .. math.random(1000, 9999)
    
    core.openLogFile(config.logFile)
    core.info("Battery node '%s' starting...", config.nodeName)
    
    -- Scan for local artillery
    local count = artillery.scanBatteries()
    if count == 0 then
        core.error("No artillery found!")
        return false
    end
    core.info("Found %d artillery batteries", count)
    
    -- Initialize network as artillery node
    if not network.init(config.nodeName, "battery") then
        core.error("Network initialization failed!")
        return false
    end
    
    -- Register message handlers
    network.onMessage("fire_command", handleFireCommand)
    network.onMessage("status_request", handleStatusRequest)
    network.onMessage("configure", handleConfigure)
    
    core.info("Battery node ready")
    return true
end

-- ============================================================================
-- MESSAGE HANDLERS
-- ============================================================================

function handleFireCommand(msg)
    core.info("Fire command from %s", msg.senderId)
    
    if not config.autoFire then
        core.warn("Auto-fire disabled, ignoring command")
        return
    end
    
    local target = msg.target
    if not target or not target.x or not target.z then
        core.error("Invalid target in fire command")
        return
    end
    
    local y = target.y or 64
    
    -- Check if this command is targeted at us specifically
    if msg.targetId and msg.targetId ~= config.nodeName then
        core.debug("Command not for us, ignoring")
        return
    end
    
    local options = msg.options or {}
    
    -- Execute fire
    if options.volleys and options.volleys > 1 then
        core.info("Firing %d volleys at %d, %d, %d", options.volleys, target.x, y, target.z)
        artillery.fireVolleyBurst(
            {x = target.x, y = y, z = target.z},
            options.volleys,
            options.volleyDelay or 2,
            options.shotDelay or 0
        )
    else
        core.info("Firing at %d, %d, %d", target.x, y, target.z)
        artillery.fireVolley({x = target.x, y = y, z = target.z})
    end
    
    -- Send acknowledgment
    network.send(msg.senderId, "fire_ack", {
        success = true,
        target = target
    })
end

function handleStatusRequest(msg)
    if not config.reportStatus then return end
    
    core.debug("Status request from %s", msg.senderId)
    
    local status = artillery.getStatus()
    
    network.send(msg.senderId, "status_response", {
        nodeName = config.nodeName,
        nodeType = "battery",
        artillery = status,
        config = {
            autoFire = config.autoFire,
            reportStatus = config.reportStatus
        }
    })
end

function handleConfigure(msg)
    core.info("Configuration update from %s", msg.senderId)
    
    if msg.autoFire ~= nil then
        config.autoFire = msg.autoFire
        core.info("Auto-fire: %s", tostring(config.autoFire))
    end
    
    if msg.reportStatus ~= nil then
        config.reportStatus = msg.reportStatus
    end
    
    if msg.enableBattery then
        artillery.setBatteryEnabled(msg.enableBattery, true)
    end
    
    if msg.disableBattery then
        artillery.setBatteryEnabled(msg.disableBattery, false)
    end
end

-- ============================================================================
-- MAIN LOOP
-- ============================================================================

local running = true

local function mainLoop()
    core.info("Entering main loop, Ctrl+C to stop")
    
    while running do
        -- Pull events with timeout to allow for graceful shutdown
        local evt = {event.pull(5)}
        
        if evt[1] == "interrupted" then
            core.info("Interrupt received, shutting down...")
            running = false
        end
    end
end

local function shutdown()
    core.info("Shutting down battery node")
    network.shutdown()
end

-- ============================================================================
-- ENTRY POINT
-- ============================================================================

local function main(args)
    local nodeName = args[1]
    
    if not init(nodeName) then
        return 1
    end
    
    -- Run main loop
    local success, err = pcall(mainLoop)
    
    if not success then
        core.error("Error in main loop: %s", err)
    end
    
    shutdown()
    return 0
end

local args = {...}
os.exit(main(args))
