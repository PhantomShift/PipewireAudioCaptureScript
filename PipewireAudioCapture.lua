local obs = obslua
local pwi = require "pwinterface"

-- [nodeName] = true/nil
local MANAGED_NODE_NAMES = {}

local CENTRAL_VIRTUAL_MONITOR = "OBS Pipewire Audio Capture Monitor"
local _CENTRAL_VIRTUAL_MONITOR_STRING = [[
{
    factory.name     = support.null-audio-sink
    node.name        = "OBS Pipewire Audio Capture Monitor"
    media.class      = Audio/Sink
    object.linger    = true
    audio.position   = [ FL FR ]
}
]]
pwi.createNode(_CENTRAL_VIRTUAL_MONITOR_STRING)

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

function script_unload()
    pwi.destroyNodeByName(CENTRAL_VIRTUAL_MONITOR)
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
        managed_node = obs.obs_data_get_string(settings, "Audio Source")
    }

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
    end
    obs.obs_data_release(settings)
    obs.obs_source_release(source)
end

function pipewireAudioCaptureSource.get_properties(data)
    local properties = obs.obs_properties_create()
    local audioSourceProp = obs.obs_properties_add_list(properties, "Audio Source", "Audio to capture", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)

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
        end
    end)

    return properties
end

obs.obs_register_source(pipewireAudioCaptureSource)
