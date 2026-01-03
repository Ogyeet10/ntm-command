--[[
    NTM Command Framework - Network Module
    Handles communication between distributed bases and command centers
    
    Uses OpenComputers network cards/linked cards for communication.
    Supports both local (wired) and remote (linked card) networks.
]]

local component = require("component")
local event = require("event")
local serialization = require("serialization")
local core = require("lib.core")

local network = {}

-- ============================================================================
-- NETWORK SETUP
-- ============================================================================

network.nodeId = nil
network.nodeType = "unknown" -- "command", "battery", "radar", "relay"
network.knownNodes = {}
network.messageHandlers = {}
network.modem = nil
network.tunnel = nil -- Linked card

-- Standard ports
network.PORTS = {
    BROADCAST = 1000,
    COMMAND = 1001,
    ARTILLERY = 1002,
    RADAR = 1003,
    ALERT = 1004,
    HEARTBEAT = 1005
}

--- Initializes network components
function network.init(nodeId, nodeType)
    network.nodeId = nodeId or os.getenv("HOSTNAME") or "node_" .. math.random(1000, 9999)
    network.nodeType = nodeType or "unknown"
    
    -- Try to get modem (wireless or wired)
    if component.isAvailable("modem") then
        network.modem = component.modem
        
        -- Open standard ports
        for name, port in pairs(network.PORTS) do
            network.modem.open(port)
        end
        
        core.info("Network initialized with modem (node: %s)", network.nodeId)
    end
    
    -- Try to get linked card (tunnel)
    if component.isAvailable("tunnel") then
        network.tunnel = component.tunnel
        core.info("Linked card available")
    end
    
    if not network.modem and not network.tunnel then
        core.warn("No network hardware found!")
        return false
    end
    
    -- Register event listener
    event.listen("modem_message", network._handleMessage)
    
    -- Start heartbeat
    network.startHeartbeat()
    
    return true
end

--- Shuts down network cleanly
function network.shutdown()
    event.ignore("modem_message", network._handleMessage)
    network.stopHeartbeat()
    
    if network.modem then
        for _, port in pairs(network.PORTS) do
            network.modem.close(port)
        end
    end
end

-- ============================================================================
-- MESSAGE HANDLING
-- ============================================================================

--- Internal message handler
function network._handleMessage(_, localAddr, remoteAddr, port, distance, ...)
    local args = {...}
    
    -- First arg should be our serialized message
    if #args < 1 then return end
    
    local success, message = pcall(serialization.unserialize, args[1])
    if not success or not message then
        core.debug("Received malformed message")
        return
    end
    
    -- Add metadata
    message._remoteAddr = remoteAddr
    message._port = port
    message._distance = distance
    
    -- Update known nodes
    if message.senderId and message.senderType then
        network.knownNodes[message.senderId] = {
            address = remoteAddr,
            type = message.senderType,
            lastSeen = os.time(),
            distance = distance
        }
    end
    
    -- Call registered handlers
    local handlers = network.messageHandlers[message.type] or {}
    for _, handler in ipairs(handlers) do
        pcall(handler, message)
    end
    
    -- Also call wildcard handlers
    for _, handler in ipairs(network.messageHandlers["*"] or {}) do
        pcall(handler, message)
    end
end

--- Registers a message handler
function network.onMessage(messageType, handler)
    if not network.messageHandlers[messageType] then
        network.messageHandlers[messageType] = {}
    end
    table.insert(network.messageHandlers[messageType], handler)
end

-- ============================================================================
-- SENDING MESSAGES
-- ============================================================================

--- Builds a message with standard headers
function network.buildMessage(msgType, data)
    local msg = data or {}
    msg.type = msgType
    msg.senderId = network.nodeId
    msg.senderType = network.nodeType
    msg.timestamp = os.time()
    return msg
end

--- Broadcasts a message to all nodes on a port
function network.broadcast(msgType, data, port)
    port = port or network.PORTS.BROADCAST
    local msg = network.buildMessage(msgType, data)
    local serialized = serialization.serialize(msg)
    
    if network.modem then
        network.modem.broadcast(port, serialized)
    end
    
    core.debug("Broadcast [%s] on port %d", msgType, port)
    return true
end

--- Sends a message to a specific node
function network.send(targetId, msgType, data, port)
    port = port or network.PORTS.COMMAND
    
    local node = network.knownNodes[targetId]
    if not node then
        core.warn("Unknown node: %s", targetId)
        return false
    end
    
    local msg = network.buildMessage(msgType, data)
    msg.targetId = targetId
    local serialized = serialization.serialize(msg)
    
    if network.modem then
        network.modem.send(node.address, port, serialized)
    end
    
    core.debug("Sent [%s] to %s", msgType, targetId)
    return true
end

--- Sends via linked card (point-to-point, infinite range)
function network.sendLinked(msgType, data)
    if not network.tunnel then
        core.warn("No linked card available")
        return false
    end
    
    local msg = network.buildMessage(msgType, data)
    local serialized = serialization.serialize(msg)
    
    network.tunnel.send(serialized)
    core.debug("Sent [%s] via linked card", msgType)
    return true
end

-- ============================================================================
-- HEARTBEAT SYSTEM
-- ============================================================================

local heartbeatTimer = nil

--- Starts periodic heartbeat broadcasts
function network.startHeartbeat(interval)
    interval = interval or 10
    
    if heartbeatTimer then
        network.stopHeartbeat()
    end
    
    heartbeatTimer = event.timer(interval, function()
        network.broadcast("heartbeat", {
            status = "online",
            uptime = os.clock()
        }, network.PORTS.HEARTBEAT)
    end, math.huge)
end

--- Stops heartbeat
function network.stopHeartbeat()
    if heartbeatTimer then
        event.cancel(heartbeatTimer)
        heartbeatTimer = nil
    end
end

--- Gets list of online nodes (seen within timeout)
function network.getOnlineNodes(timeout)
    timeout = timeout or 30
    local online = {}
    local now = os.time()
    
    for id, node in pairs(network.knownNodes) do
        if (now - node.lastSeen) < timeout then
            online[id] = node
        end
    end
    
    return online
end

-- ============================================================================
-- COMMAND MESSAGES
-- ============================================================================

--- Sends a fire command to a remote artillery node
function network.sendFireCommand(targetNodeId, coordinates, options)
    return network.send(targetNodeId, "fire_command", {
        target = coordinates,
        options = options or {}
    }, network.PORTS.ARTILLERY)
end

--- Broadcasts a fire command to all artillery nodes
function network.broadcastFireCommand(coordinates, options)
    return network.broadcast("fire_command", {
        target = coordinates,
        options = options or {}
    }, network.PORTS.ARTILLERY)
end

--- Sends an alert to all nodes
function network.sendAlert(alertType, alertData)
    return network.broadcast("alert", {
        alertType = alertType,
        alertData = alertData
    }, network.PORTS.ALERT)
end

--- Requests status from a specific node
function network.requestStatus(targetNodeId)
    return network.send(targetNodeId, "status_request", {}, network.PORTS.COMMAND)
end

--- Broadcasts status request to all nodes
function network.broadcastStatusRequest()
    return network.broadcast("status_request", {}, network.PORTS.COMMAND)
end

-- ============================================================================
-- STATUS & REPORTING
-- ============================================================================

function network.getStatus()
    return {
        nodeId = network.nodeId,
        nodeType = network.nodeType,
        hasModem = network.modem ~= nil,
        hasTunnel = network.tunnel ~= nil,
        knownNodes = network.getOnlineNodes(),
        openPorts = network.PORTS
    }
end

function network.printStatus()
    local status = network.getStatus()
    
    print("=== Network Status ===")
    print(string.format("Node: %s (%s)", status.nodeId, status.nodeType))
    print(string.format("Hardware: Modem=%s Linked=%s",
          status.hasModem and "YES" or "NO",
          status.hasTunnel and "YES" or "NO"))
    
    print("")
    print("Known Nodes:")
    
    local count = 0
    for id, node in pairs(status.knownNodes) do
        count = count + 1
        print(string.format("  %s (%s) - last seen %ds ago",
              id, node.type, os.time() - node.lastSeen))
    end
    
    if count == 0 then
        print("  (none)")
    end
end

return network
