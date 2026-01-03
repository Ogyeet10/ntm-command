--[[
    NTM Command Framework - Bootstrap Installer
    
    One-liner to run in OpenComputers:
    wget -f https://raw.githubusercontent.com/Ogyeet10/ntm-command/main/bootstrap.lua /tmp/bs.lua && /tmp/bs.lua
]]

local shell = require("shell")
local fs = require("filesystem")

local BASE_URL = "https://raw.githubusercontent.com/Ogyeet10/ntm-command/main/"

-- Files to download
local files = {
    -- Libraries
    {"lib/core.lua", "/usr/lib/lib/core.lua"},
    {"lib/artillery.lua", "/usr/lib/lib/artillery.lua"},
    {"lib/radar.lua", "/usr/lib/lib/radar.lua"},
    {"lib/network.lua", "/usr/lib/lib/network.lua"},
    
    -- Binaries
    {"bin/ntm-command.lua", "/usr/bin/ntm-command"},
    {"bin/ntm-battery.lua", "/usr/bin/ntm-battery"},
    {"bin/quickfire.lua", "/usr/bin/quickfire"},
}

-- Directories to create
local dirs = {
    "/usr/lib/lib",
    "/usr/bin",
    "/etc/ntm",
    "/var/log"
}

print("╔═══════════════════════════════════════╗")
print("║   NTM Command Framework Installer     ║")
print("╚═══════════════════════════════════════╝")
print("")

-- Create directories
print("Creating directories...")
for _, dir in ipairs(dirs) do
    if not fs.exists(dir) then
        fs.makeDirectory(dir)
        print("  + " .. dir)
    end
end

-- Download files
print("")
print("Downloading from GitHub...")

local success = 0
local failed = 0

for _, file in ipairs(files) do
    local src = BASE_URL .. file[1]
    local dst = file[2]
    
    print("  " .. file[1] .. " -> " .. dst)
    
    -- Use wget with -f to force overwrite
    local result = shell.execute("wget -f -q " .. src .. " " .. dst)
    
    if fs.exists(dst) then
        success = success + 1
    else
        failed = failed + 1
        print("    FAILED!")
    end
end

print("")
print(string.format("Downloaded: %d success, %d failed", success, failed))

if failed > 0 then
    print("")
    print("Some files failed to download!")
    print("Make sure you have an Internet Card installed.")
    os.exit(1)
end

-- Create default config
print("")
print("Creating default config...")

local configContent = [[
return {
    nodeName = nil,
    nodeType = "command",
    artillery = { defaultY = 64 },
    radar = { monitorInterval = 1 },
    network = { heartbeatInterval = 10 }
}
]]

local cfg = io.open("/etc/ntm/config.lua", "w")
cfg:write(configContent)
cfg:close()
print("  + /etc/ntm/config.lua")

-- Done
print("")
print("════════════════════════════════════════")
print("  Installation complete!")
print("════════════════════════════════════════")
print("")
print("Commands available:")
print("  ntm-command    - Full command center")
print("  ntm-battery    - Remote battery daemon")
print("  quickfire      - Simple fire script")
print("")
print("Run 'ntm-command' to start!")

-- Cleanup
fs.remove("/tmp/bs.lua")
