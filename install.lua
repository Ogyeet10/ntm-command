#!/usr/bin/env lua
--[[
    NTM Command Framework - Installer
    Installs the framework to the OpenOS filesystem
    
    Run: install.lua
]]

local fs = require("filesystem")
local shell = require("shell")

print("NTM Command Framework Installer")
print("================================")
print("")

-- Directories to create
local dirs = {
    "/usr/lib",
    "/usr/bin",
    "/etc/ntm",
    "/var/log"
}

-- Files to install
local files = {
    -- Libraries
    {"lib/core.lua", "/usr/lib/lib/core.lua"},
    {"lib/artillery.lua", "/usr/lib/lib/artillery.lua"},
    {"lib/radar.lua", "/usr/lib/lib/radar.lua"},
    {"lib/network.lua", "/usr/lib/lib/network.lua"},
    
    -- Binaries
    {"bin/ntm-command.lua", "/usr/bin/ntm-command"},
    {"bin/ntm-battery.lua", "/usr/bin/ntm-battery"},
}

-- Create directories
print("Creating directories...")
for _, dir in ipairs(dirs) do
    if not fs.exists(dir) then
        fs.makeDirectory(dir)
        print("  Created: " .. dir)
    end
end

-- Also create lib subdir in /usr/lib
if not fs.exists("/usr/lib/lib") then
    fs.makeDirectory("/usr/lib/lib")
end

-- Get source directory (where this script is)
local sourceDir = shell.resolve(".")

-- Copy files
print("")
print("Installing files...")

for _, file in ipairs(files) do
    local src = fs.concat(sourceDir, file[1])
    local dst = file[2]
    
    if fs.exists(src) then
        -- Read source
        local srcFile = io.open(src, "r")
        local content = srcFile:read("*all")
        srcFile:close()
        
        -- Write destination
        local dstFile = io.open(dst, "w")
        dstFile:write(content)
        dstFile:close()
        
        print("  Installed: " .. dst)
    else
        print("  WARNING: Source not found: " .. src)
    end
end

-- Create default config
print("")
print("Creating default configuration...")

local defaultConfig = [[
-- NTM Command Framework Configuration
-- Edit this file to customize behavior

return {
    -- Node identification
    nodeName = nil,  -- nil = auto-generate
    nodeType = "command",  -- "command", "battery", "radar"
    
    -- Artillery settings
    artillery = {
        defaultY = 64,  -- Default Y coordinate for 2D targeting
    },
    
    -- Radar settings
    radar = {
        monitorInterval = 1,  -- Seconds between scans
        alertOnMissiles = true,
        alertOnPlayers = false,
    },
    
    -- Network settings
    network = {
        heartbeatInterval = 10,
        nodeTimeout = 30,
    }
}
]]

local cfgFile = io.open("/etc/ntm/config.lua", "w")
cfgFile:write(defaultConfig)
cfgFile:close()
print("  Created: /etc/ntm/config.lua")

print("")
print("Installation complete!")
print("")
print("Usage:")
print("  ntm-command          - Run command center (interactive)")
print("  ntm-command status   - Quick status check")
print("  ntm-command fire X Z - Quick fire command")
print("  ntm-battery          - Run as remote battery node")
print("")
print("Connect your artillery/radar with OC cables and run ntm-command!")
