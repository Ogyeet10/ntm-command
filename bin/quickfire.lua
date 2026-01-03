--[[
    Quick Fire - Simple artillery script
    
    This is the "three inputs and a for loop" version for when you
    just need to rain hell on someone's base without all the framework.
    
    Usage:
        quickfire           - Interactive prompts
        quickfire X Z       - Fire at coords
        quickfire X Z 5     - Fire 5 volleys
        quickfire X Z 5 2   - Fire 5 volleys with 2s delay
]]

local component = require("component")

-- ============================================================================
-- GET ALL ARTILLERY
-- ============================================================================

local artillery = {}

print("Scanning for artillery...")
for addr, ctype in component.list("ntm_artillery") do
    local proxy = component.proxy(addr)
    table.insert(artillery, proxy)
    print("  Found: " .. addr:sub(1, 8))
end

if #artillery == 0 then
    print("No artillery found!")
    os.exit(1)
end

print(string.format("Ready: %d batteries", #artillery))
print("")

-- ============================================================================
-- PARSE ARGS OR PROMPT
-- ============================================================================

local args = {...}
local x, z, volleys, delay

if #args >= 2 then
    -- Command line args
    x = tonumber(args[1])
    z = tonumber(args[2])
    volleys = tonumber(args[3]) or 1
    delay = tonumber(args[4]) or 2
else
    -- Interactive
    io.write("Target X: ")
    x = tonumber(io.read())
    
    io.write("Target Z: ")
    z = tonumber(io.read())
    
    io.write("Volleys (1): ")
    local v = io.read()
    volleys = tonumber(v) or 1
    
    if volleys > 1 then
        io.write("Delay between volleys (2): ")
        local d = io.read()
        delay = tonumber(d) or 2
    else
        delay = 0
    end
end

-- Validate
if not x or not z then
    print("Invalid coordinates!")
    os.exit(1)
end

local y = 64  -- Default ground level

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function log(msg, ...)
    print(string.format("[DEBUG] " .. msg, ...))
end

local function checkAndActivate(arty, index)
    -- Check if turret is active
    local isActive = arty.isActive()
    log("Battery %d: isActive = %s", index, tostring(isActive))
    
    if not isActive then
        log("Battery %d: Activating turret...", index)
        arty.setActive(true)
        os.sleep(0.1)
        
        -- Verify activation
        isActive = arty.isActive()
        log("Battery %d: isActive after activation = %s", index, tostring(isActive))
        
        if not isActive then
            print(string.format("  Battery %d: FAILED TO ACTIVATE!", index))
            return false
        end
    end
    return true
end

local function logTurretState(arty, index, label)
    local angle = {arty.getAngle()}
    local hasTarget = arty.hasTarget()
    local aligned = arty.isAligned()
    local energy = {arty.getEnergyInfo()}
    
    log("Battery %d [%s]:", index, label)
    log("  - Pitch: %.2f, Yaw: %.2f", angle[1] or 0, angle[2] or 0)
    log("  - hasTarget: %s, isAligned: %s", tostring(hasTarget), tostring(aligned))
    log("  - Energy: %d / %d", energy[1] or 0, energy[2] or 0)
end

-- ============================================================================
-- FIRE
-- ============================================================================

print("")
print(string.format("=== FIRING %d VOLLEY(S) AT %d, %d, %d ===", volleys, x, y, z))
print("")

for v = 1, volleys do
    if volleys > 1 then
        print(string.format("--- Volley %d/%d ---", v, volleys))
    end
    
    -- Fire all batteries
    for i, arty in ipairs(artillery) do
        print(string.format("  Battery %d:", i))
        
        -- Log state before
        logTurretState(arty, i, "BEFORE")
        
        -- Ensure turret is active
        if not checkAndActivate(arty, i) then
            goto continue
        end
        
        -- Add target coordinates
        log("Battery %d: Calling addCoords(%d, %d, %d)", i, x, y, z)
        local result = arty.addCoords(x, y, z)
        log("Battery %d: addCoords returned: %s (type: %s)", i, tostring(result), type(result))
        
        -- Cannon returns boolean (in range check), rocket returns nil
        if result == false then
            print(string.format("    -> OUT OF RANGE"))
            goto continue
        end
        
        -- Verify target was accepted
        local hasTarget = arty.hasTarget()
        log("Battery %d: hasTarget after addCoords = %s", i, tostring(hasTarget))
        
        if not hasTarget then
            print(string.format("    -> TARGET NOT ACCEPTED!"))
            goto continue
        end
        
        -- Check current target
        local currentTarget = {arty.getCurrentTarget()}
        if #currentTarget >= 3 then
            log("Battery %d: getCurrentTarget = %d, %d, %d", i, currentTarget[1], currentTarget[2], currentTarget[3])
        else
            log("Battery %d: getCurrentTarget returned incomplete data", i)
        end
        
        -- Wait and check alignment
        os.sleep(0.3)
        logTurretState(arty, i, "AFTER")
        
        local aligned = arty.isAligned()
        if aligned then
            print(string.format("    -> FIRING (aligned)"))
        else
            print(string.format("    -> FIRING (aligning...)"))
        end
        
        ::continue::
    end
    
    -- Delay between volleys
    if v < volleys and delay > 0 then
        print(string.format("  (waiting %ds...)", delay))
        os.sleep(delay)
    end
end

print("")
print("=== FIRE MISSION COMPLETE ===")
