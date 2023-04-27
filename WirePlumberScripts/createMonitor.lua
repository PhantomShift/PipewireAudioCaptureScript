#!/usr/bin/wpexec
-- Script that creates a virtual monitor

local arg = ...
node = Node("adapter", {
    ["factory.name"]    = "support.null-audio-sink",
    ["node.name"]       = arg["name"],
    ["node.virtual"]    = true,
    ["media.class"]     = arg["mediaClass"],
    ["object.linger"]   = true,
    ["audio.position"]  = "[ FL FR ]",

    ["monitor.channel-volumes"]         = true,
-- `session.suspend-timeout-seconds` is set to 0 to prevent wireplumber from attempting to suspend destroyed nodes
    ["session.suspend-timeout-seconds"] = 0
})

node:connect("state-changed", function(self, oldState, newState)
    if oldState == "creating" then
        print(node.properties["object.id"])
        Core.idle_add(function() Core.quit() end)
    end
end)

node:activate(1)

Core.timeout_add(50, function()
    Log.warning("Error occurred in trying to create virtual monitor")
    Core.quit()
end)