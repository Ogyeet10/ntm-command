--[[
    NTM Command Framework - Artillery Module
    Controls and coordinates artillery batteries (rocket and cannon)
    
    Supports:
    - Individual battery control
    - Coordinated volleys across multiple batteries
    - Target queue management
    - Range validation (cannon only)
]]

local component = require("component")
local event = require("event")
local core = require("lib.core")

local artillery = {}

-- ============================================================================
-- BATTERY REGISTRY
-- ============================================================================

-- Stores all known artillery batteries
-- Format: batteries[name] = {proxy, type, position, status}
artillery.batteries = {}

--- Scans for and registers all artillery components
function artillery.scanBatteries()
    artillery.batteries = {}
    
    -- Find all artillery components
    local found = core.findComponents("ntm_artillery")
    
    for i, comp in ipairs(found) do
        local name = "battery_" .. i
        local proxy = comp.proxy
        
        -- Determine type by checking if addCoords returns boolean (cannon) or nil (rocket)
        -- We'll default to "unknown" and let the user configure
        artillery.batteries[name] = {
            proxy = proxy,
            address = comp.address,
            type = "unknown", -- "rocket" or "cannon"
            enabled = true,
            lastTarget = nil
        }
        
        core.info("Registered artillery: %s @ %s", name, comp.address:sub(1,8))
    end
    
    return #found
end

--- Manually registers a battery with a custom name
function artillery.registerBattery(name, address, batteryType)
    local proxy = component.proxy(address)
    if not proxy then
        core.error("Cannot find component: %s", address)
        return false
    end
    
    artillery.batteries[name] = {
        proxy = proxy,
        address = address,
        type = batteryType or "unknown",
        enabled = true,
        lastTarget = nil
    }
    
    core.info("Registered battery '%s' as %s", name, batteryType or "unknown")
    return true
end

--- Sets battery type (rocket/cannon)
function artillery.setBatteryType(name, batteryType)
    if not artillery.batteries[name] then
        core.error("Unknown battery: %s", name)
        return false
    end
    artillery.batteries[name].type = batteryType
    return true
end

--- Enables/disables a battery
function artillery.setBatteryEnabled(name, enabled)
    if not artillery.batteries[name] then
        core.error("Unknown battery: %s", name)
        return false
    end
    artillery.batteries[name].enabled = enabled
    return true
end

-- ============================================================================
-- TARGETING
-- ============================================================================

--- Gets current target of a battery
function artillery.getCurrentTarget(name)
    local battery = artillery.batteries[name]
    if not battery then return nil end
    
    local target = {battery.proxy.getCurrentTarget()}
    if #target >= 3 then
        return {x = target[1], y = target[2], z = target[3]}
    end
    return nil
end

--- Sets target for a specific battery
-- @param name string: Battery name
-- @param x number: Target X coordinate
-- @param y number: Target Y coordinate  
-- @param z number: Target Z coordinate
-- @return boolean: Success status (for cannon, indicates if in range)
function artillery.setTarget(name, x, y, z)
    local battery = artillery.batteries[name]
    if not battery then
        core.error("Unknown battery: %s", name)
        return false
    end
    
    if not battery.enabled then
        core.warn("Battery '%s' is disabled", name)
        return false
    end
    
    -- Ensure turret is active before targeting
    local wasActive = battery.proxy.isActive()
    core.debug("Battery '%s' active state before targeting: %s", name, tostring(wasActive))
    
    if not wasActive then
        core.info("Activating battery '%s'...", name)
        battery.proxy.setActive(true)
        os.sleep(0.1) -- Brief delay for activation
        
        -- Verify activation
        local nowActive = battery.proxy.isActive()
        if not nowActive then
            core.error("Failed to activate battery '%s'!", name)
            return false
        end
        core.debug("Battery '%s' successfully activated", name)
    end
    
    -- Check energy before firing
    local energy = {battery.proxy.getEnergyInfo()}
    core.debug("Battery '%s' energy: %d / %d", name, energy[1] or 0, energy[2] or 0)
    if energy[1] and energy[1] <= 0 then
        core.warn("Battery '%s' has no energy!", name)
    end
    
    -- Log current angle before targeting
    local angleBefore = {battery.proxy.getAngle()}
    core.debug("Battery '%s' angle before targeting - pitch: %.2f, yaw: %.2f", 
               name, angleBefore[1] or 0, angleBefore[2] or 0)
    
    -- Add target coordinates
    core.info("Setting target for '%s': %d, %d, %d", name, x, y, z)
    local result = battery.proxy.addCoords(x, y, z)
    battery.lastTarget = {x = x, y = y, z = z}
    
    core.debug("addCoords returned: %s (type: %s)", tostring(result), type(result))
    
    -- Cannon returns boolean for range check, rocket returns nil
    if battery.type == "cannon" then
        if result == false then
            core.warn("Target out of range for cannon '%s'", name)
            return false
        end
    end
    
    -- Check targeting settings
    local targeting = {battery.proxy.getTargeting()}
    core.debug("Battery '%s' targeting settings - players: %s, animals: %s, mobs: %s, machines: %s",
               name, tostring(targeting[1]), tostring(targeting[2]), 
               tostring(targeting[3]), tostring(targeting[4]))
    
    -- Warn if all targeting is disabled
    if not targeting[1] and not targeting[2] and not targeting[3] and not targeting[4] then
        core.warn("Battery '%s' has ALL targeting disabled! Enabling players targeting...", name)
        battery.proxy.setTargeting(true, false, false, false)
        
        -- Verify it was set
        local newTargeting = {battery.proxy.getTargeting()}
        core.debug("Battery '%s' new targeting settings - players: %s, animals: %s, mobs: %s, machines: %s",
                   name, tostring(newTargeting[1]), tostring(newTargeting[2]), 
                   tostring(newTargeting[3]), tostring(newTargeting[4]))
    end
    
    -- Check target distance (may be nil if no target)
    -- NOTE: getTargetDistance requires coordinates as args, not stored target
    local turretPos = {battery.proxy.getPos and battery.proxy.getPos() or nil}
    if turretPos[1] then
        local dx = x - turretPos[1]
        local dy = y - turretPos[2]
        local dz = z - turretPos[3]
        local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
        core.debug("Battery '%s' at position: %d, %d, %d", name, turretPos[1], turretPos[2], turretPos[3])
        core.debug("Battery '%s' distance to target: %.2f blocks", name, distance)
        
        -- Artillery mode has 250 block MINIMUM range and 3000 max range
        -- Cannon mode has 32 block minimum and 250 max range
        if distance < 32 then
            core.warn("Battery '%s' target may be TOO CLOSE! Distance %.0f < 32 block minimum (cannon mode)", name, distance)
        elseif distance < 250 then
            core.warn("Battery '%s' target may be TOO CLOSE for artillery mode! Distance %.0f < 250 block minimum", name, distance)
            core.info("  Consider using cannon mode or moving target further away")
        elseif distance > 3000 then
            core.warn("Battery '%s' target is TOO FAR! Distance %.0f > 3000 block maximum", name, distance)
        end
    end
    
    -- Verify target was accepted
    -- NOTE: hasTarget() checks for entity targets, NOT manual coordinate targets!
    -- In manual mode (which addCoords forces), hasTarget() will always be false.
    -- We use getCurrentTarget() instead to verify the coordinates were queued.
    local hasTarget = battery.proxy.hasTarget()
    core.debug("Battery '%s' hasTarget after addCoords: %s (NOTE: always false in manual mode)", name, tostring(hasTarget))
    
    -- Even if hasTarget is false, let's check getCurrentTarget anyway
    local currentTarget = {battery.proxy.getCurrentTarget()}
    local targetAccepted = false
    if #currentTarget >= 3 then
        core.debug("Battery '%s' getCurrentTarget: %d, %d, %d", 
                   name, currentTarget[1], currentTarget[2], currentTarget[3])
        -- Verify the target matches what we sent
        if math.abs(currentTarget[1] - x) < 1 and 
           math.abs(currentTarget[2] - y) < 1 and 
           math.abs(currentTarget[3] - z) < 1 then
            targetAccepted = true
            core.debug("Battery '%s' target coordinates confirmed in queue", name)
        else
            core.warn("Battery '%s' target mismatch! Expected %d,%d,%d but got %d,%d,%d",
                     name, x, y, z, currentTarget[1], currentTarget[2], currentTarget[3])
        end
    else
        core.warn("Battery '%s' getCurrentTarget returned no data - target not accepted!", name)
        core.warn("  Possible causes: No ammo, out of range, turret obstructed")
    end
    
    -- Wait briefly and check alignment
    os.sleep(0.2)
    local aligned = battery.proxy.isAligned()
    local angleAfter = {battery.proxy.getAngle()}
    core.debug("Battery '%s' after targeting - aligned: %s, pitch: %.2f, yaw: %.2f", 
               name, tostring(aligned), angleAfter[1] or 0, angleAfter[2] or 0)
    
    if not aligned and targetAccepted then
        core.info("Battery '%s' is aligning to target...", name)
    end
    
    core.info("Target set for '%s': %d, %d, %d (aligned: %s, accepted: %s)", 
              name, x, y, z, tostring(aligned), tostring(targetAccepted))
    return targetAccepted
end

--- Gets distance to current target
function artillery.getTargetDistance(name)
    local battery = artillery.batteries[name]
    if not battery then return nil end
    return battery.proxy.getTargetDistance()
end

-- ============================================================================
-- TURRET CONTROLS (inherited from base turret API)
-- ============================================================================

--- Activates/deactivates a battery's turret
function artillery.setActive(name, active)
    local battery = artillery.batteries[name]
    if not battery then return false end
    battery.proxy.setActive(active)
    return true
end

--- Checks if battery is active
function artillery.isActive(name)
    local battery = artillery.batteries[name]
    if not battery then return nil end
    return battery.proxy.isActive()
end

--- Gets battery energy info
function artillery.getEnergy(name)
    local battery = artillery.batteries[name]
    if not battery then return nil end
    local info = {battery.proxy.getEnergyInfo()}
    return {current = info[1], max = info[2]}
end

--- Gets battery angle (pitch/yaw)
function artillery.getAngle(name)
    local battery = artillery.batteries[name]
    if not battery then return nil end
    local angle = {battery.proxy.getAngle()}
    return {pitch = angle[1], yaw = angle[2]}
end

--- Checks if battery is aligned with target
function artillery.isAligned(name)
    local battery = artillery.batteries[name]
    if not battery then return nil end
    return battery.proxy.isAligned()
end

--- Checks if battery has a target
function artillery.hasTarget(name)
    local battery = artillery.batteries[name]
    if not battery then return nil end
    return battery.proxy.hasTarget()
end

--- Gets/modifies whitelist
function artillery.getWhitelist(name)
    local battery = artillery.batteries[name]
    if not battery then return nil end
    return battery.proxy.getWhitelist()
end

function artillery.removeFromWhitelist(name, player)
    local battery = artillery.batteries[name]
    if not battery then return false end
    return battery.proxy.removeWhiteList(player)
end

--- Sets targeting preferences
function artillery.setTargeting(name, players, animals, mobs, machines)
    local battery = artillery.batteries[name]
    if not battery then return false end
    battery.proxy.setTargeting(players, animals, mobs, machines)
    return true
end

-- ============================================================================
-- VOLLEY FIRE SYSTEM
-- ============================================================================

--- Fires a coordinated volley at a single target from multiple batteries
-- @param target table: {x, y, z} coordinates
-- @param batteryNames table|nil: Specific batteries to use (nil = all enabled)
-- @param delay number: Delay between shots in seconds (default 0)
-- @return table: Results for each battery
function artillery.fireVolley(target, batteryNames, delay)
    delay = delay or 0
    local results = {}
    
    -- Get list of batteries to use
    local batteries = {}
    if batteryNames then
        for _, name in ipairs(batteryNames) do
            if artillery.batteries[name] then
                table.insert(batteries, name)
            end
        end
    else
        for name, battery in pairs(artillery.batteries) do
            if battery.enabled then
                table.insert(batteries, name)
            end
        end
    end
    
    core.info("Firing volley at %d, %d, %d with %d batteries", 
              target.x, target.y, target.z, #batteries)
    
    for i, name in ipairs(batteries) do
        local success = artillery.setTarget(name, target.x, target.y, target.z)
        results[name] = success
        
        if success then
            core.debug("Battery '%s' targeted", name)
        else
            core.warn("Battery '%s' failed to target", name)
        end
        
        -- Delay between shots if specified
        if delay > 0 and i < #batteries then
            os.sleep(delay)
        end
    end
    
    return results
end

--- Fires multiple volleys at the same target
-- @param target table: {x, y, z} coordinates
-- @param volleys number: Number of volleys to fire
-- @param volleyDelay number: Delay between volleys in seconds
-- @param shotDelay number: Delay between shots within a volley
function artillery.fireVolleyBurst(target, volleys, volleyDelay, shotDelay)
    volleyDelay = volleyDelay or 2
    shotDelay = shotDelay or 0
    
    core.info("Firing %d volleys at target", volleys)
    
    for v = 1, volleys do
        core.info("Volley %d/%d", v, volleys)
        artillery.fireVolley(target, nil, shotDelay)
        
        if v < volleys then
            os.sleep(volleyDelay)
        end
    end
    
    core.info("Volley burst complete")
end

--- Fire at multiple targets in sequence (walking fire)
-- @param targets table: Array of {x, y, z} coordinates
-- @param delay number: Delay between targets
function artillery.walkingFire(targets, delay)
    delay = delay or 1
    
    core.info("Walking fire across %d targets", #targets)
    
    for i, target in ipairs(targets) do
        core.info("Target %d/%d: %d, %d, %d", i, #targets, target.x, target.y, target.z)
        artillery.fireVolley(target)
        
        if i < #targets then
            os.sleep(delay)
        end
    end
    
    core.info("Walking fire complete")
end

-- ============================================================================
-- STATUS & REPORTING
-- ============================================================================

--- Gets comprehensive status of all batteries
function artillery.getStatus()
    local status = {
        total = 0,
        enabled = 0,
        active = 0,
        batteries = {}
    }
    
    for name, battery in pairs(artillery.batteries) do
        status.total = status.total + 1
        
        local batteryStatus = {
            name = name,
            address = battery.address:sub(1, 8),
            type = battery.type,
            enabled = battery.enabled,
            active = battery.proxy.isActive(),
            hasTarget = battery.proxy.hasTarget(),
            aligned = battery.proxy.isAligned(),
            energy = artillery.getEnergy(name),
            lastTarget = battery.lastTarget
        }
        
        if battery.enabled then status.enabled = status.enabled + 1 end
        if batteryStatus.active then status.active = status.active + 1 end
        
        status.batteries[name] = batteryStatus
    end
    
    return status
end

--- Prints a formatted status report
function artillery.printStatus()
    local status = artillery.getStatus()
    
    print("=== Artillery Status ===")
    print(string.format("Batteries: %d total, %d enabled, %d active",
          status.total, status.enabled, status.active))
    print("")
    
    for name, info in pairs(status.batteries) do
        local state = info.enabled and "ON" or "OFF"
        local targetStr = info.hasTarget and "TARGETED" or "NO TARGET"
        local energyPct = info.energy and math.floor(info.energy.current / info.energy.max * 100) or 0
        
        print(string.format("[%s] %s (%s) - %s - Energy: %d%%",
              state, name, info.type, targetStr, energyPct))
    end
end

-- ============================================================================
-- PERSISTENCE
-- ============================================================================

--- Saves battery configuration to file
function artillery.saveConfig(path)
    local config = {}
    
    for name, battery in pairs(artillery.batteries) do
        config[name] = {
            address = battery.address,
            type = battery.type,
            enabled = battery.enabled
        }
    end
    
    return core.saveConfig(path or "/etc/ntm/artillery.cfg", config)
end

--- Loads battery configuration from file
function artillery.loadConfig(path)
    local config = core.loadConfig(path or "/etc/ntm/artillery.cfg")
    
    for name, data in pairs(config) do
        artillery.registerBattery(name, data.address, data.type)
        artillery.setBatteryEnabled(name, data.enabled)
    end
    
    return true
end

return artillery
