-- Just a layer of abstraction between lua and a shell that interacts with pipewire
local pwinterface = {}

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
            local prop, value = line:match("([%a%p]+)%s=%s\"(.+)\"")
            focusedObject[prop] = value
        end
    end

    return objects
end

-- Wrapper for io.popen that returns the output of the given command
local function getOSExecuteResult(command)
    local fs = io.popen(command)
    assert(fs, ("getOSExecuteResult given malformed command '%s'"):format(command))
    local result = fs:read("*all")
    fs:close()
    return result
end

local INPUT_CONNECTION_ID_CAPTURE = "(%d+)%s+|<-"
function pwinterface.getNodeInputConnectionIDs(nodeName)
    local cmd = ("pw-link -l -I any '%s'"):format(nodeName)
    local outputGrab = io.popen(cmd)
    local output = outputGrab:read("*all")
    outputGrab:close()

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

function pwinterface.getLinkByNodeIDs(outputID, inputID)
    local linksString = getOSExecuteResult("pw-cli ls Link")

    local links = parsePipewireListObjectsOutput(linksString)
    for _, link in pairs(links) do
        if link["link.output.node"] == outputID and link["link.input.node"] == inputID then
            return link
        end
    end
end

function pwinterface.connectNodes(output, input)
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
function pwinterface.destroyNode(nodeID)
    os.execute(("pw-cli destroy %s"):format(nodeID))
end
function pwinterface.destroyNodeByName(nodeName)
    local nodes = pwinterface.getNodesWithName(nodeName, true)
    for _, node in pairs(nodes) do
        pwinterface.destroyNode(node.id)
    end
end

return pwinterface
