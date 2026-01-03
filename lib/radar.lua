--[[
    NTM Command Framework - Radar Module
    Provides radar integration for threat detection and target acquisition
    
    Features:
    - Automatic threat detection
    - Target tracking
    - Alert system
    - Integration with artillery for automatic response
]]

local component = require("component")
local event = require("event")
local core = require("lib.core")

local radar = {}

-- ============================================================================
-- RADAR MANAGEMENT
-- ============================================================================

radar.radars = {}
radar.trackedEntities = {}
radar.alertCallbacks = {}

-- Threat classification thresholds
radar.THREAT_LEVELS = {
    LOW = 1,      -- Tier 0-1 missiles, players
    MEDIUM = 2,   -- Tier 2-3 missiles
    HIGH = 3,     -- Tier 4+ missiles, large customs
    CRITICAL = 4  -- Nuclear/Doomsday
}

--- Scans for and registers all radar components
function radar.scanRadars()
    radar.radars = {}
    
    local found = core.findComponents("ntm_radar")
    
    for i, comp in ipairs(found) do
        local proxy = comp.proxy
        local range = proxy.getRange()
        local pos = {proxy.getPos()}
        
        radar.radars[i] = {
            proxy = proxy,
            address = comp.address,
            range = range,
            position = {x = pos[1], y = pos[2], z = pos[3]},
            isLarge = range > 1500 -- Large radar has 3000 range
        }
        
        core.info("Registered radar @ %s (range: %d)", comp.address:sub(1,8), range)
    end
    
    return #found
end

--- Gets a radar by index
function radar.getRadar(index)
    return radar.radars[index or 1]
end

-- ============================================================================
-- RADAR SETTINGS
-- ============================================================================

--- Configures radar scanning settings
function radar.configure(index, missiles, shells, players, smart)
    local r = radar.radars[index or 1]
    if not r then return false end
    
    r.proxy.setSettings(missiles, shells, players, smart)
    core.info("Radar configured: missiles=%s shells=%s players=%s smart=%s",
              tostring(missiles), tostring(shells), tostring(players), tostring(smart))
    return true
end

--- Gets current radar settings
function radar.getSettings(index)
    local r = radar.radars[index or 1]
    if not r then return nil end
    
    local settings = {r.proxy.getSettings()}
    return {
        missiles = settings[1],
        shells = settings[2],
        players = settings[3],
        smart = settings[4]
    }
end

--- Checks if radar is jammed
function radar.isJammed(index)
    local r = radar.radars[index or 1]
    if not r then return nil end
    return r.proxy.isJammed()
end

--- Gets radar energy info
function radar.getEnergy(index)
    local r = radar.radars[index or 1]
    if not r then return nil end
    
    local info = {r.proxy.getEnergyInfo()}
    return {current = info[1], max = info[2]}
end

-- ============================================================================
-- ENTITY DETECTION
-- ============================================================================

--- Classifies threat level based on blip type
local function classifyThreat(blipLevel)
    -- Blip levels from the API docs
    if blipLevel >= 4 and blipLevel <= 9 then
        return radar.THREAT_LEVELS.CRITICAL -- Nuclear/large missiles
    elseif blipLevel == 3 then
        return radar.THREAT_LEVELS.HIGH -- Tier 3
    elseif blipLevel == 2 then
        return radar.THREAT_LEVELS.MEDIUM -- Tier 2
    else
        return radar.THREAT_LEVELS.LOW -- Tier 0-1, players, shells
    end
end

--- Gets blip type name
local function getBlipTypeName(blipLevel)
    local names = {
        [0] = "Micro Missile",
        [1] = "Tier 1 Missile",
        [2] = "Tier 2 Missile",
        [3] = "Tier 3 Missile",
        [4] = "Tier 4 (Nuclear)",
        [5] = "Custom Missile (10)",
        [6] = "Custom Missile (10-15)",
        [7] = "Custom Missile (15)",
        [8] = "Custom Missile (15-20)",
        [9] = "Custom Missile (20)",
        [10] = "Anti-Ballistic",
        [11] = "Player",
        [12] = "Artillery Shell"
    }
    return names[blipLevel] or "Unknown"
end

--- Scans radar and returns all detected entities
function radar.scan(radarIndex)
    local r = radar.radars[radarIndex or 1]
    if not r then return {} end
    
    local entities = {}
    local count = r.proxy.getAmount()
    
    for i = 1, count do
        local data = {r.proxy.getEntityAtIndex(i)}
        
        if data[1] ~= nil then -- Check if valid
            local entity = {
                index = i,
                isPlayer = data[1],
                position = {x = data[2], y = data[3], z = data[4]},
                blipLevel = data[5],
                name = data[6] or nil,
                typeName = getBlipTypeName(data[5]),
                threatLevel = classifyThreat(data[5]),
                distance = core.distance3D(
                    r.position.x, r.position.y, r.position.z,
                    data[2], data[3], data[4]
                )
            }
            table.insert(entities, entity)
        end
    end
    
    return entities
end

--- Filters entities by type
function radar.filterEntities(entities, filterType)
    local filtered = {}
    
    for _, entity in ipairs(entities) do
        local include = false
        
        if filterType == "missiles" then
            include = entity.blipLevel >= 0 and entity.blipLevel <= 9
        elseif filterType == "players" then
            include = entity.isPlayer
        elseif filterType == "shells" then
            include = entity.blipLevel == 12
        elseif filterType == "threats" then
            include = entity.threatLevel >= radar.THREAT_LEVELS.MEDIUM
        elseif filterType == "critical" then
            include = entity.threatLevel >= radar.THREAT_LEVELS.CRITICAL
        end
        
        if include then
            table.insert(filtered, entity)
        end
    end
    
    return filtered
end

--- Gets the highest threat from a scan
function radar.getHighestThreat(entities)
    local highest = nil
    local highestLevel = 0
    
    for _, entity in ipairs(entities) do
        if entity.threatLevel > highestLevel then
            highest = entity
            highestLevel = entity.threatLevel
        end
    end
    
    return highest
end

-- ============================================================================
-- TRACKING SYSTEM
-- ============================================================================

--- Updates tracked entities with new scan data
function radar.updateTracking()
    local newTracked = {}
    
    for i, r in ipairs(radar.radars) do
        local entities = radar.scan(i)
        
        for _, entity in ipairs(entities) do
            -- Create a unique-ish key based on position and type
            local key = string.format("%s_%.0f_%.0f_%.0f", 
                entity.typeName, entity.position.x, entity.position.y, entity.position.z)
            
            local existing = radar.trackedEntities[key]
            
            if existing then
                -- Update existing track with velocity estimation
                local dt = os.time() - (existing.lastSeen or os.time())
                if dt > 0 then
                    entity.velocity = {
                        x = (entity.position.x - existing.position.x) / dt,
                        y = (entity.position.y - existing.position.y) / dt,
                        z = (entity.position.z - existing.position.z) / dt
                    }
                end
                entity.firstSeen = existing.firstSeen
                entity.trackId = existing.trackId
            else
                -- New track
                entity.firstSeen = os.time()
                entity.trackId = key
                entity.velocity = {x = 0, y = 0, z = 0}
            end
            
            entity.lastSeen = os.time()
            entity.radarIndex = i
            newTracked[key] = entity
        end
    end
    
    -- Check for alerts on new threats
    for key, entity in pairs(newTracked) do
        if not radar.trackedEntities[key] then
            radar.triggerAlert("new_contact", entity)
        end
    end
    
    radar.trackedEntities = newTracked
    return newTracked
end

--- Gets all currently tracked entities
function radar.getTracked()
    return radar.trackedEntities
end

--- Gets tracked missiles/threats only
function radar.getTrackedThreats(minLevel)
    minLevel = minLevel or radar.THREAT_LEVELS.LOW
    local threats = {}
    
    for _, entity in pairs(radar.trackedEntities) do
        if not entity.isPlayer and entity.threatLevel >= minLevel then
            table.insert(threats, entity)
        end
    end
    
    -- Sort by threat level (highest first)
    table.sort(threats, function(a, b) return a.threatLevel > b.threatLevel end)
    
    return threats
end

-- ============================================================================
-- ALERT SYSTEM
-- ============================================================================

--- Registers an alert callback
function radar.onAlert(alertType, callback)
    if not radar.alertCallbacks[alertType] then
        radar.alertCallbacks[alertType] = {}
    end
    table.insert(radar.alertCallbacks[alertType], callback)
end

--- Triggers an alert
function radar.triggerAlert(alertType, data)
    local callbacks = radar.alertCallbacks[alertType] or {}
    
    -- Log the alert
    if alertType == "new_contact" then
        local threatNames = {"LOW", "MEDIUM", "HIGH", "CRITICAL"}
        core.warn("NEW CONTACT: %s at %.0f, %.0f, %.0f (Threat: %s)",
                  data.typeName, data.position.x, data.position.y, data.position.z,
                  threatNames[data.threatLevel])
    end
    
    -- Call registered handlers
    for _, callback in ipairs(callbacks) do
        pcall(callback, alertType, data)
    end
    
    -- Also call global handlers
    for _, callback in ipairs(radar.alertCallbacks["*"] or {}) do
        pcall(callback, alertType, data)
    end
end

-- ============================================================================
-- CONTINUOUS MONITORING
-- ============================================================================

local monitorTimer = nil

--- Starts continuous radar monitoring
function radar.startMonitoring(interval)
    interval = interval or 1 -- Default 1 second
    
    if monitorTimer then
        radar.stopMonitoring()
    end
    
    core.info("Starting radar monitoring (interval: %ds)", interval)
    
    monitorTimer = event.timer(interval, function()
        radar.updateTracking()
    end, math.huge)
    
    return true
end

--- Stops continuous monitoring
function radar.stopMonitoring()
    if monitorTimer then
        event.cancel(monitorTimer)
        monitorTimer = nil
        core.info("Radar monitoring stopped")
    end
end

--- Checks if monitoring is active
function radar.isMonitoring()
    return monitorTimer ~= nil
end

-- ============================================================================
-- STATUS & REPORTING
-- ============================================================================

--- Gets comprehensive radar status
function radar.getStatus()
    local status = {
        radarCount = #radar.radars,
        trackedCount = 0,
        threatCount = 0,
        highestThreat = nil,
        isMonitoring = radar.isMonitoring(),
        radars = {}
    }
    
    for i, r in ipairs(radar.radars) do
        status.radars[i] = {
            address = r.address:sub(1, 8),
            range = r.range,
            isLarge = r.isLarge,
            isJammed = r.proxy.isJammed(),
            energy = radar.getEnergy(i),
            settings = radar.getSettings(i)
        }
    end
    
    for _, entity in pairs(radar.trackedEntities) do
        status.trackedCount = status.trackedCount + 1
        if not entity.isPlayer then
            status.threatCount = status.threatCount + 1
        end
    end
    
    status.highestThreat = radar.getHighestThreat(radar.getTrackedThreats())
    
    return status
end

--- Prints formatted status
function radar.printStatus()
    local status = radar.getStatus()
    
    print("=== Radar Status ===")
    print(string.format("Radars: %d | Tracking: %d contacts | Threats: %d",
          status.radarCount, status.trackedCount, status.threatCount))
    print(string.format("Monitoring: %s", status.isMonitoring and "ACTIVE" or "INACTIVE"))
    
    if status.highestThreat then
        print(string.format("HIGHEST THREAT: %s @ %.0f, %.0f, %.0f",
              status.highestThreat.typeName,
              status.highestThreat.position.x,
              status.highestThreat.position.y,
              status.highestThreat.position.z))
    end
    
    print("")
    for i, r in ipairs(status.radars) do
        local energyPct = r.energy and math.floor(r.energy.current / r.energy.max * 100) or 0
        local jammed = r.isJammed and " [JAMMED]" or ""
        print(string.format("Radar %d: %s (range %d) - %d%% energy%s",
              i, r.address, r.range, energyPct, jammed))
    end
end

return radar
