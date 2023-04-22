local obs = obslua
local pwi = require "pwinterface"

local UNLOADING = false

-- [nodeName] = true/nil
local MANAGED_NODE_NAMES = {}

-- [data] = nodeName/nil
local AUTORECONNECT_NODES = {}

local CENTRAL_VIRTUAL_MONITOR = "OBS Pipewire Audio Capture Monitor"
local CENTRAL_VIRTUAL_MONITOR_PRIORITY = 700 + 150 * #pwi.getNodesWithName(CENTRAL_VIRTUAL_MONITOR, true) -- This is pretty arbitrary and often doesn't help in my experience?
local _CENTRAL_VIRTUAL_MONITOR_STRING = ([[
{
    factory.name     = support.null-audio-sink
    node.name        = "%s"
    media.class      = Audio/Sink
    object.linger    = true
    audio.position   = [ FL FR ]
    priority.session = %d
    priority.driver  = %d
}
]]):format(CENTRAL_VIRTUAL_MONITOR, CENTRAL_VIRTUAL_MONITOR_PRIORITY, CENTRAL_VIRTUAL_MONITOR_PRIORITY)
pwi.recreateNode(CENTRAL_VIRTUAL_MONITOR, _CENTRAL_VIRTUAL_MONITOR_STRING)

function script_description()
    return [[
A super scuffed script that attempts to make capturing specific application audio easier
By all practicality just a bunch of automated pw-cli calls, I am unfortunately not well-versed with C++ at the moment
Note that currently all output nodes with a shared name will be captured (i.e. all audio outputs with the name 'Firefox')
This is intentional since my personal use-case is capturing game audio, which will often have multiple outputs created for some reason
I may add it as an option at some point but right now cannot be bothered
Note that "OBS Pipewire Audio Capture Monitor" must be added as a global audio device under the audio settings for sound to be recorded
]]
end

local AUTO_RECONNECT_TIME_MS = 500
function autoReconnectCallback()
    if UNLOADING then return end
    for data, node_name in pairs(AUTORECONNECT_NODES) do
        if MANAGED_NODE_NAMES[node_name] then
            print "AUTO CONNECTING NODES"
            pwi.connectAllNamed(node_name, CENTRAL_VIRTUAL_MONITOR)
        end
    end
end

obs.timer_add(autoReconnectCallback, AUTO_RECONNECT_TIME_MS)

function script_unload()
    UNLOADING = true
    -- For some reason when autoreconnecting is active, pipewire crashes due to some unresolved reference
    -- if the node is destroyed; cannot be bothered to diagnose the issue at the moment.
    -- If you often close OBS and then open it again in less than 5 seconds, more power to you.
    -- Yes this is a hack, this entire script is a hack.
    os.execute(("(sleep 5; pgrep -x obs >/dev/null && echo 'obs is still running' || pw-cli destroy '%s') &"):format(CENTRAL_VIRTUAL_MONITOR))
end

local pipewireAudioCaptureSource = {
    id = "pipewireAudioCaptureSource",
--     icon_type = obs.OBS_ICON_TYPE_AUDIO_OUTPUT, -- Doesn't seem to work with obslua?
    type = obs.OBS_SOURCE_TYPE_OUTPUT,
    output_flags = obs.OBS_SOURCE_DO_NOT_DUPLICATE,
}

function pipewireAudioCaptureSource.get_name()
    return "Pipewire Audio Capture"
end

function pipewireAudioCaptureSource.create(settings, source)
    local data = {
        source_name = obs.obs_source_get_name(source),
        managed_node = obs.obs_data_get_string(settings, "Audio Source"),
        auto_reconnect = obs.obs_data_get_bool(settings, "autoreconnect")
    }

    if data.managed_node and data.auto_reconnect then
        AUTORECONNECT_NODES[data] = data.managed_node
    end
    if data.managed_node and obs.obs_source_active(source) then
        MANAGED_NODE_NAMES[data.managed_node] = true
        pwi.connectAllNamed(data.managed_node, CENTRAL_VIRTUAL_MONITOR)
    end

    return data
end

function pipewireAudioCaptureSource.destroy(data)
    pwi.disconnectAllNamed(data.managed_node, CENTRAL_VIRTUAL_MONITOR)
    MANAGED_NODE_NAMES[data.managed_node] = nil
end
function pipewireAudioCaptureSource.deactivate(data)
    pwi.disconnectAllNamed(data.managed_node, CENTRAL_VIRTUAL_MONITOR)
    MANAGED_NODE_NAMES[data.managed_node] = nil
end
function pipewireAudioCaptureSource.activate(data)
    local source = obs.obs_get_source_by_name(data.source_name)
    local settings = obs.obs_source_get_settings(source)
    local audioSource = obs.obs_data_get_string(settings, "Audio Source")
    if audioSource ~= "None" then
        pwi.connectAllNamed(audioSource, CENTRAL_VIRTUAL_MONITOR)
        MANAGED_NODE_NAMES[data.managed_node] = true
    end
    obs.obs_data_release(settings)
    obs.obs_source_release(source)
end

function pipewireAudioCaptureSource.get_properties(data)
    local properties = obs.obs_properties_create()
    local audioSourceProp = obs.obs_properties_add_list(properties, "Audio Source", "Application Audio to Capture", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)

    local audioSources = pwi.listNodesByName()
    obs.obs_property_list_insert_string(audioSourceProp, 0, "None", "None")

    local index = 1
    for _, audioSource in pairs(audioSources) do
        if not MANAGED_NODE_NAMES[audioSource["node.name"]] or data.managed_node == audioSource["node.name"] then
            obs.obs_property_list_insert_string(audioSourceProp, index, audioSource["node.name"], audioSource["node.name"])
            index = index + 1
        end
    end

    obs.obs_property_set_modified_callback(audioSourceProp, function(props, prop, settings)
        print "Source property updated"
        local newAudioSource = obs.obs_data_get_string(settings, "Audio Source")
        print("Current audio source:")
        print(data.managed_node)
        MANAGED_NODE_NAMES[data.managed_node] = nil

        pwi.disconnectAllNamed(data.managed_node, CENTRAL_VIRTUAL_MONITOR)
        print("New audio source:")
        print(newAudioSource)
        data.managed_node = newAudioSource
        if newAudioSource ~= "None" then
            MANAGED_NODE_NAMES[newAudioSource] = true
            pwi.connectAllNamed(newAudioSource, CENTRAL_VIRTUAL_MONITOR)
            AUTORECONNECT_NODES[data] = data.auto_reconnect and data.managed_node or nil
        else
            AUTORECONNECT_NODES[data] = nil
        end
    end)

    local autoreconnectProp = obs.obs_properties_add_bool(properties, "autoreconnect", "Automatically Connect Audio Sources with Same Name")

    obs.obs_property_set_modified_callback(autoreconnectProp, function(props, prop, settings)
        data.auto_reconnect = obs.obs_data_get_bool(settings, "autoreconnect")
        if data.managed_node ~= "None" then
            AUTORECONNECT_NODES[data] = data.auto_reconnect and data.managed_node or nil
        end
    end)

    return properties
end

obs.obs_register_source(pipewireAudioCaptureSource)
