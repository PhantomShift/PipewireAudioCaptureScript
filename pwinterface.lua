-- Just a layer of abstraction between lua and a shell that interacts with pipewire
local pwinterface = {}

-- Wrapper for io.popen that returns the output of the given command
local function getOSExecuteResult(command)
    local fs = io.popen(command)
    assert(fs, ("getOSExecuteResult given malformed command '%s'"):format(command))
    local result = fs:read("*all")
    fs:close()
    return result
end

local LINE_CAPTURE = "[^\r\n]+"
local ID_CAPTURE = "id %d+"
-- Convert the result of "pw-cli list-objects" into a simple to work with table
local function parsePipewireListObjectsOutput(output)
    local objects = {}
    local focusedObject
    for line in output:gmatch(LINE_CAPTURE) do
        local objectId = line:match(ID_CAPTURE)
        if objectId then
            focusedObject = {id = objectId:match("%d+")}
            table.insert(objects, focusedObject)
        else
            local prop, value = line:match("([%a%p]+)%s=%s\"(.-)\"")
            focusedObject[prop] = value
        end
    end

    return objects
end

local PIPEWIRE_LINK_CAPTURE = "%s+(%d+)%s([^\n]+)%s+(%d+)%s+(%S+)%s+(%d+)%s+([^\n]+)"
local function parsePipewireLinkOutput(output)
    local result = {}

    for portID1, port1, linkID, direction, portID2, port2 in output:gmatch(PIPEWIRE_LINK_CAPTURE) do
        print(portID1, port1, linkID, direction, portID2, port2)
        table.insert(result, {
            portName1 = port1,
            portID1 = portID1,
            portName2 = port2,
            portID2 = portID2,

            id = linkID,
            direction = direction == "|->" and "out" or "in"
        })
    end

    return result
end

pwinterface.parsePipewireLinkOutput = parsePipewireLinkOutput

local PIPEWIRE_OBJECT_PROPERTIES_CAPTURE = "([%S]+) = \"([^\n]+)\""
function pwinterface.getDetailedObjectInformation(objectID)
    local infoString = getOSExecuteResult(("pw-cli info %s"):format(tostring(objectID)))

    local infoTable = {id = tostring(objectID)}
    for prop, val in infoString:gmatch(PIPEWIRE_OBJECT_PROPERTIES_CAPTURE) do
        infoTable[prop] = val
    end

    return infoTable
end

local INPUT_CONNECTION_ID_CAPTURE = "(%d+)%s+|<-"
function pwinterface.getNodeInputConnectionIDs(nodeName)
    local cmd = ("pw-link -l -I any '%s'"):format(nodeName)
    local output = getOSExecuteResult(cmd)

    local result = {}

    for line in output:gmatch(LINE_CAPTURE) do
        local connectionID = line:match(INPUT_CONNECTION_ID_CAPTURE)
        if connectionID then table.insert(result, connectionID) end
    end

    return result
end

local NODE_NAME_CAPTURE = "\"(.-)\""
local WHITELISTED_MEDIA_CLASSES = {
    ["Stream/Output/Audio"] = true,
    ["Audio/Source"] = true
}
-- Note that currently, filters only by node/application name
function pwinterface.listNodesByName(filter, ignoreWhitelist)
    local cmd = "pw-cli list-objects Node"

    local audioOutputString = getOSExecuteResult(cmd)

    local objects = parsePipewireListObjectsOutput(audioOutputString)
    local result = {}
    for _, object in pairs(objects) do
        if (not filter or filter and (object["node.name"] == filter or object["application.name"] == filter)) and (ignoreWhitelist or WHITELISTED_MEDIA_CLASSES[object["media.class"]]) then
            table.insert(result, object)
        end
    end

    return result
end

function pwinterface.getNodesWithName(nodeName, ignoreWhitelist)
    return pwinterface.listNodesByName(nodeName, ignoreWhitelist)
end

function pwinterface.doesNodeWithNameExist(nodeName)
    return getOSExecuteResult(("pw-cli info '%s'"):format(nodeName)) ~= ""
end

function pwinterface.getLinks()
    local linksString = getOSExecuteResult("pw-cli ls Link")
    return parsePipewireListObjectsOutput(linksString)
end
function pwinterface.getLinkByNodeIDs(outputID, inputID)
    local linksString = getOSExecuteResult("pw-cli ls Link")

    local links = parsePipewireListObjectsOutput(linksString)
    for _, link in pairs(links) do
        if link["link.output.node"] == outputID and link["link.input.node"] == inputID then
            return link
        end
    end
end
function pwinterface.getLinkObjectsByNodeID(nodeID)
    local links = pwinterface.getLinks()
--     local nodeInfo = pwinterface.getDetailedObjectInformation(nodeID)
    local result = {}
    for _, link in pairs(links) do
        if link["link.output.node"] == nodeID or link["link.input.node"] == nodeID then
            table.insert(result, link)
        end
    end

    return result
end

function pwinterface.connectNodes(output, input)
    -- May be necessary to prevent crashes
--     for _, link in pairs(pwinterface.getLinkObjectsByNodeID(output)) do
--         local inputObject = pwinterface.getDetailedObjectInformation(link["link.input.node"])
--         if inputObject["node.name"] == input then
--             print "Automatic connection prevented as nodes are already connected"
--             return
--         end
--     end

    os.execute(("pw-link '%s' '%s' "):format(output, input))
end
-- Specifically for connecting all outputs under a shared name (i.e. all audio sources under 'Firefox') to a single input node
function pwinterface.connectAllNamed(sharedOutputName, input)
    for _, output in pairs(pwinterface.getNodesWithName(sharedOutputName)) do
        pwinterface.connectNodes(output.id, input)
    end
end
function pwinterface.disconnectNodes(output, input)
    os.execute(("pw-link -d '%s' '%s' "):format(output, input))
end
function pwinterface.disconnectAllNamed(sharedOutputName, input)
    for _, output in pairs(pwinterface.getNodesWithName(sharedOutputName)) do
        pwinterface.disconnectNodes(output.id, input)
    end
end
function pwinterface.disconnectInputs(nodeName)
    for _, connection in pairs (pwinterface.getNodeInputConnectionIDs(nodeName)) do
        os.execute(("pw-link -d %s"):format(connection))
    end
end

function pwinterface.createNode(argString)
    os.execute(("pw-cli create-node adapter '%s'"):format(argString))
end
-- Creates the node if it node with name `nodeName` doesn't exist, else does nothing
function pwinterface.recreateNode(nodeName, argString)
    if not pwinterface.doesNodeWithNameExist(nodeName) then
        pwinterface.createNode(argString)
    end
end
-- Creates the node and returns its `object.id` and `node.name`
function pwinterface.createAndGetUniqueNode(argString)
    local originalName = argString:match("node.name%s+=%s+\"(.-)\"")
    local createdName = originalName
    local count = 0
    while pwinterface.doesNodeWithNameExist(createdName) do
        createdName = originalName .. (" %d"):format(count)
        count = count + 1
    end
    argString:gsub(originalName, createdName)
    pwinterface.createNode(argString)
    repeat
        print "lol"
    until pwinterface.doesNodeWithNameExist(createdName)
    -- return pwinterface.getNodesWithName(createdName, true)[1].id, createdName
    return pwinterface.getDetailedObjectInformation(createdName)["object.id"], createdName
end
function pwinterface.destroyNode(nodeID)
    os.execute(("pw-cli destroy %s"):format(nodeID))
end
function pwinterface.destroyNodeByName(nodeName)
    local nodes = pwinterface.getNodesWithName(nodeName, true)
    for _, node in pairs(nodes) do
        print("Destroying Node:")
        print(node["node.name"])
        if node["node.name"] == nodeName then -- sanity check
            -- Might need to do this first to prevent issues, not entirely sure, probably a good idea regardless
            pwinterface.disconnectInputs(nodeName)
            pwinterface.destroyNode(node.id)
        end
    end
end

-- Commands
function pwinterface.setMonitorVolume(nodeID, volume)
    os.execute(("pw-cli set-param %s Props '{monitorVolumes: [%f, %f]}'"):format(tostring(nodeID), volume, volume))
end

return pwinterface
