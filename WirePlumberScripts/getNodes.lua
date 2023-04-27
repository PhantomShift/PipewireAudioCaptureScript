#!/usr/bin/wpexec
-- Get nodes, optional filter options
local arg = ...
local nameConstraint
local classConstraint

local function splitString(str, sep)
    if not sep then sep = "," end
    local result = {}
    for item in str:gmatch("[^"..sep.."]+") do
        table.insert(result, item)
    end

    return result
end

if arg["filterName"] then
    nameConstraint = Constraint { "node.name", "in-list", table.unpack(splitString(arg["filterName"])) }
end

if arg["filterClass"] then
    classConstraint = Constraint { "media.class", "in-list", table.unpack(splitString(arg["filterClass"])) }
end

AppManager = ObjectManager {
    Interest {
        type = "node",
        nameConstraint,
        classConstraint
    },
}

AppManager:activate()

-- Minimum timeout seems to be about 3 milliseconds, but set to 10 just to make sure
Core.timeout_add(10, function()
    for node in AppManager:iterate() do
        local string = ""
        for property, value in pairs(node.properties) do
            if tostring(value) ~= "" then
                string = string .. property .. " = \"" .. tostring(value) .. "\" "
            end
        end
    end
    Core.quit()
end)