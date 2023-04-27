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

node:activate(1)

Core.timeout_add(10, function()
    print(node.properties["object.id"])
    Core.quit()
end)