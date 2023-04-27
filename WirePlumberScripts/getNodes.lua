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

nodeManager = ObjectManager {
    Interest {
        type = "node",
        nameConstraint,
        classConstraint
    },
}

nodeManager:connect("installed", function(self)
    for node in self:iterate() do
        local string = ""
        for property, value in pairs(node.properties) do
            if tostring(value) ~= "" then
                string = string .. property .. " = \"" .. tostring(value) .. "\" "
            end
        end
        print(string)
    end
    Core.quit()
end)

nodeManager:activate()

Core.timeout_add(50, function()
    Log.warning("Error occurred in trying to get nodes")
    Core.quit()
end)