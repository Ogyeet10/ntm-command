--[[
    NTM Command Framework - Core Library
    Central utilities and component management for the framework
    
    This is the foundation that everything else builds on.
]]

local component = require("component")
local event = require("event")
local serialization = require("serialization")

local core = {}

-- ============================================================================
-- COMPONENT DISCOVERY & MANAGEMENT
-- ============================================================================

--- Finds all components of a given type
-- @param componentType string: The component type to search for (e.g., "ntm_artillery")
-- @return table: Array of {address, proxy} pairs
function core.findComponents(componentType)
    local found = {}
    for address, ctype in component.list(componentType) do
        table.insert(found, {
            address = address,
            proxy = component.proxy(address),
            type = ctype
        })
    end
    return found
end

--- Gets a component proxy by partial address match
-- @param partialAddr string: First few characters of the address
-- @return proxy or nil
function core.getByPartialAddress(partialAddr)
    for address, ctype in component.list() do
        if address:sub(1, #partialAddr) == partialAddr then
            return component.proxy(address), ctype
        end
    end
    return nil
end

-- ============================================================================
-- LOGGING SYSTEM
-- ============================================================================

core.LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    CRITICAL = 5
}

local currentLogLevel = core.LOG_LEVELS.INFO
local logFile = nil

--- Sets the minimum log level to display
function core.setLogLevel(level)
    currentLogLevel = level
end

--- Opens a log file for persistent logging
function core.openLogFile(path)
    logFile = io.open(path, "a")
end

--- Logs a message with timestamp and level
function core.log(level, message, ...)
    if level < currentLogLevel then return end
    
    local levelNames = {"DEBUG", "INFO", "WARN", "ERROR", "CRITICAL"}
    local timestamp = os.date("%H:%M:%S")
    local formatted = string.format("[%s][%s] " .. message, timestamp, levelNames[level], ...)
    
    print(formatted)
    
    if logFile then
        logFile:write(formatted .. "\n")
        logFile:flush()
    end
end

-- Convenience logging functions
function core.debug(msg, ...) core.log(core.LOG_LEVELS.DEBUG, msg, ...) end
function core.info(msg, ...) core.log(core.LOG_LEVELS.INFO, msg, ...) end
function core.warn(msg, ...) core.log(core.LOG_LEVELS.WARN, msg, ...) end
function core.error(msg, ...) core.log(core.LOG_LEVELS.ERROR, msg, ...) end
function core.critical(msg, ...) core.log(core.LOG_LEVELS.CRITICAL, msg, ...) end

-- ============================================================================
-- CONFIGURATION MANAGEMENT
-- ============================================================================

--- Loads a config file (Lua table format)
-- @param path string: Path to config file
-- @return table: Config data or empty table if not found
function core.loadConfig(path)
    local file = io.open(path, "r")
    if not file then
        core.warn("Config file not found: %s", path)
        return {}
    end
    
    local content = file:read("*all")
    file:close()
    
    -- Using serialization for safety instead of raw loadstring
    local success, data = pcall(serialization.unserialize, content)
    if success and data then
        return data
    else
        core.error("Failed to parse config: %s", path)
        return {}
    end
end

--- Saves a config table to file
-- @param path string: Path to save to
-- @param data table: Config data to save
function core.saveConfig(path, data)
    local file = io.open(path, "w")
    if not file then
        core.error("Cannot write config: %s", path)
        return false
    end
    
    file:write(serialization.serialize(data, true)) -- pretty print
    file:close()
    return true
end

-- ============================================================================
-- COORDINATE UTILITIES
-- ============================================================================

--- Calculates distance between two 3D points
function core.distance3D(x1, y1, z1, x2, y2, z2)
    return math.sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2)
end

--- Calculates horizontal distance (ignoring Y)
function core.distance2D(x1, z1, x2, z2)
    return math.sqrt((x2-x1)^2 + (z2-z1)^2)
end

--- Parses coordinate string "x,y,z" or "x z" formats
function core.parseCoords(str)
    -- Try comma-separated first
    local x, y, z = str:match("(-?%d+),(-?%d+),(-?%d+)")
    if x then return tonumber(x), tonumber(y), tonumber(z) end
    
    -- Try space-separated (2D, common for artillery)
    local x2, z2 = str:match("(-?%d+)%s+(-?%d+)")
    if x2 then return tonumber(x2), nil, tonumber(z2) end
    
    return nil
end

-- ============================================================================
-- EVENT HELPERS
-- ============================================================================

--- Creates a simple event-driven state machine
function core.createStateMachine(initialState)
    local sm = {
        state = initialState,
        handlers = {},
        onTransition = nil
    }
    
    function sm:on(state, handler)
        self.handlers[state] = handler
    end
    
    function sm:transition(newState, ...)
        local oldState = self.state
        self.state = newState
        
        if self.onTransition then
            self.onTransition(oldState, newState)
        end
        
        if self.handlers[newState] then
            return self.handlers[newState](...)
        end
    end
    
    return sm
end

-- ============================================================================
-- TABLE UTILITIES
-- ============================================================================

--- Deep copies a table
function core.deepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[core.deepCopy(k)] = core.deepCopy(v)
        end
        setmetatable(copy, core.deepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

--- Merges two tables (second overwrites first)
function core.merge(t1, t2)
    local result = core.deepCopy(t1)
    for k, v in pairs(t2) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = core.merge(result[k], v)
        else
            result[k] = v
        end
    end
    return result
end

return core
