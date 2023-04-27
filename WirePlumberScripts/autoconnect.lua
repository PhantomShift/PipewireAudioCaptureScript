#!/usr/bin/wpexec
-- Automatically connect nodes with name `inputNode` to given `outputNode`
-- Only handles left, right and mono channels
-- If you're working with more channels, you probably know a lot more about
-- audio than I do anyways
local arg = ...
if not (arg["inputNode"] and arg["outputNode"])then
    print("Node names required")
    Core.quit()
    return
end

local INPUT_LIST = {
    left = {
        input_FL    = true,
        playback_FL = true,
        input_MONO  = true
    },
    right = {
        input_FR    = true,
        playback_FR = true,
        input_MONO  = true
    }
}
local OUTPUT_LIST = {
    left = {
        output_FL       = true,
        monitor_FL      = true,
        capture_MONO    = true
    },
    right = {
        output_FR       = true,
        monitor_FR      = true,
        capture_MONO    = true
    }
}

local function outputSide(portName)
    return OUTPUT_LIST.left[portName] and "left" or OUTPUT_LIST.right[portName] and "right" or nil
end

local inputNode

inputManager = ObjectManager {
    Interest {
        type = "node",
        Constraint { "node.name", "matches", arg["inputNode"], type = "pw-global" }
    }
}
outputManager = ObjectManager {
    Interest {
        type = "node",
        Constraint { "node.name", "matches", arg["outputNode"], type = "pw-global" }
    }
}

inputManager:connect("object-added", function(inMgr, node)
    local portManagers = {}
    local managedLinks = {}
    inputNode = node
    local inputPorts = {}
    for port in inputNode:iterate_ports(Interest { type = "port", Constraint { "port.direction", "=", "in" } }) do
        inputPorts[port.properties["port.name"]] = port
    end

    outputManager:connect("object-added", function(outMgr, outputNode)
        local portManager = ObjectManager {
            Interest {
                type = "port",
                Constraint { "node.id", "=", outputNode.properties["object.id"] },
                Constraint { "port.direction", "=", "out" }
            }
        }
        portManager:connect("object-added", function(portMgr, port)
            local portName = port.properties["port.name"]
            local side = outputSide(portName)
            if side then
                for name, inputPort in pairs(inputPorts) do
                    if INPUT_LIST[side][name] then
                        local link = Link("link-factory", {
                            ["link.input.port"] = inputPort.properties["object.id"],
                            ["link.output.port"] = port.properties["object.id"],
                            ["link.input.node"] = inputNode.properties["object.id"],
                            ["link.output.node"] = outputNode.properties["object.id"],
                            ["object.linger"] = true -- Keeps the link alive after autoreconnect option is turned off; link will get destroyed regardless when the node is destroyed
                        })
                        link:activate(1)
                        table.insert(managedLinks, link)
                    end
                end
            end
        end)
        portManager:activate()
        table.insert(portManagers, portManager)
    end)
end)

outputManager:activate()
inputManager:activate()

-- Exit process if output node never ends up being found
Core.timeout_add(1000, function()
    if not inputNode then
        Log.warning(inputManager, ("Error finding output node '%s', does it exist?"):format(tostring(arg["inputNode"])))
        Core.quit()
    end
end)
