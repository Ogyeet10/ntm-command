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
        local result = arty.addCoords(x, y, z)
        
        -- Cannon returns boolean (in range check), rocket returns nil
        if result == false then
            print(string.format("  Battery %d: OUT OF RANGE", i))
        else
            print(string.format("  Battery %d: FIRING", i))
        end
    end
    
    -- Delay between volleys
    if v < volleys and delay > 0 then
        print(string.format("  (waiting %ds...)", delay))
        os.sleep(delay)
    end
end

print("")
print("=== FIRE MISSION COMPLETE ===")
