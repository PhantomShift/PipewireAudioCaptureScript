-- Replacement of pwinterface that uses WirePlumber scripts instead of pipewire cli tools
-- Must be initialized with script directory in order to use wpexec
local wpinterface = {}
local wpScriptDir

-- Wrapper for io.popen that returns the output of the given command
local function getOSExecuteResult(command)
    local fs = io.popen(command)
    assert(fs, ("getOSExecuteResult given malformed command '%s'"):format(command))
    local result = fs:read("*all")
    fs:close()
    return result
end

local LINE_CAPTURE = "[^\r\n]+"
local function parseWireplumberObjectOutput(output)
    local objects = {}
    for line in output:gmatch(LINE_CAPTURE) do
        local object = {}
        for prop, val in line:gmatch("([^%s]-) = (%b\"\")") do
            object[prop] = val:sub(2, -2)
        end
        table.insert(objects, object)
    end
    return objects
end

-- Filters should be a list separated by commas, no spaces
function wpinterface.listNodes(nameFilter, classFilter)
    local cmd = "wpexec " .. wpScriptDir .. "/getNodes.lua"
    if nameFilter then
        cmd = cmd .. " filterName=" .. nameFilter
    end
    if classFilter then
        cmd = cmd .. " filterClass=" .. classFilter
    end

    return parseWireplumberObjectOutput(getOSExecuteResult(cmd))
end

function wpinterface.doesNodeWithNameExist(name)
    return (#wpinterface.listNodes(name)) > 0
end

function wpinterface.createMonitor(name, mediaClass)
    assert(name and mediaClass, "Both args required for wpinterface.createMonitor")
    local cmd = ("wpexec %s/createMonitor.lua name=\"%s\" mediaClass=\"%s\""):format(wpScriptDir, name, mediaClass)
    return getOSExecuteResult(cmd)
end

function wpinterface.init(dir)
    wpScriptDir = dir .. "/WirePlumberScripts"
end

return wpinterface