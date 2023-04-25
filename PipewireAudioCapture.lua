local obs = obslua
local pwi = require "pwinterface"

local _SCRIPT_DEBUG_MODE = false
if not _SCRIPT_DEBUG_MODE then
    print("Pipewire Audio Capture script debugging is off.")
    local print = _G.print
    _G.print = function(...)
        return nil
    end
end

local UNLOADING = false
local AUTO_RECONNECT_TIME_MS = 500
local DEFAULT_AUTO_RECONNECT_TIME_MS = 500
local _SCRIPT_SETTINGS

-- [nodeName] = true/nil
local MANAGED_NODE_NAMES = {}

-- [data] = nodeName/nil
local AUTORECONNECT_NODES = {}

-- `session.suspend-timeout-seconds` is set to 0 to prevent wireplumber from attempting to suspend destroyed nodes
local BASE_MONITOR_STRING = [[
{
    factory.name     = support.null-audio-sink
    node.name        = "%s"
    node.virtual     = true
    media.class      = %s
    object.linger    = true
    audio.position   = [ FL FR ]
    priority.session = %d
    priority.driver  = %d

    monitor.channel-volumes         = true
    session.suspend-timeout-seconds = 0
}
]]

local CENTRAL_VIRTUAL_MONITOR = "OBS Pipewire Audio Capture Monitor"
local CENTRAL_VIRTUAL_MONITOR_PRIORITY = 700 + 150 * #pwi.getNodesWithName(CENTRAL_VIRTUAL_MONITOR, true) -- This is pretty arbitrary and often doesn't help in my experience?
local CENTRAL_VIRTUAL_MONITOR_MEDIA_CLASS = "Audio/Sink" -- Cannot be virtual as it will not be detected by OBS
local _CENTRAL_VIRTUAL_MONITOR_STRING = (BASE_MONITOR_STRING):format(
    CENTRAL_VIRTUAL_MONITOR,
    CENTRAL_VIRTUAL_MONITOR_MEDIA_CLASS,
    CENTRAL_VIRTUAL_MONITOR_PRIORITY,
    CENTRAL_VIRTUAL_MONITOR_PRIORITY
)
pwi.recreateNode(CENTRAL_VIRTUAL_MONITOR, _CENTRAL_VIRTUAL_MONITOR_STRING)

local function createSubMonitorNode(nodeName)
    return pwi.createAndGetUniqueNode(BASE_MONITOR_STRING:format(
        "OBS Source " .. nodeName,
        "Audio/Sink/Virtual",
        500,
        500
    ))
end

function autoReconnectCallback()
    if UNLOADING then return end
    -- print(("%d ms"):format(AUTO_RECONNECT_TIME_MS))
    for data, node_name in pairs(AUTORECONNECT_NODES) do
        if MANAGED_NODE_NAMES[node_name] then
            print "AUTO CONNECTING NODES"
            pwi.connectAllNamed(node_name, data.capture_node)
        end
    end
end
obs.timer_add(autoReconnectCallback, AUTO_RECONNECT_TIME_MS)

local VolumeManager = {volumes = {}}
function VolumeManager:update()
    for id, vol in pairs(self.volumes) do
        self.volumes[id] = nil
        pwi.setMonitorVolume(id, vol)
    end
end
function VolumeManager:set(id, vol)
    self.volumes[id] = vol
end

function script_tick()
    VolumeManager:update()
end

function script_description()
    return [[
<center><h2>Pipewire Audio Capture</h2></center>
<p>A super scuffed script that attempts to make capturing specific application audio easier.</p>
<p>A new source called "Pipewire Audio Capture" should be available as a source if everything is working as intended.</p>
<p><a href="https://github.com/PhantomShift/PipewireAudioCaptureScript">Source code</a></p>
<p><strong>Note that "OBS Pipewire Audio Capture Monitor" must be added as a global audio device under the audio settings for sound to be recorded</strong></p>
]]
end

function script_properties()
    local properties = obs.obs_properties_create()

    local reconnectTime = obs.obs_properties_add_int_slider(properties, "reconnectTime", "Auto Reconnection Time (ms)", 50, 2000, 1)
    obs.obs_property_set_long_description(reconnectTime, "Time in milliseconds to poll for new nodes for sources where auto reconnect is active. Note that setting this too low may cause performance issues.")
    obs.obs_property_set_modified_callback(reconnectTime, function(_, _, settings)
        AUTO_RECONNECT_TIME_MS = obs.obs_data_get_int(settings, "reconnectTime")
        obs.timer_remove(autoReconnectCallback)
        obs.timer_add(autoReconnectCallback, AUTO_RECONNECT_TIME_MS)
    end)
    -- Stop-gap measure until timer_add works properly on script reload
    local forceRestartTimer = obs.obs_properties_add_button(properties, "forceRestartTimer", "Restart Timer", function()
        AUTO_RECONNECT_TIME_MS = obs.obs_data_get_int(_SCRIPT_SETTINGS, "reconnectTime")
        obs.timer_remove(autoReconnectCallback)
        obs.timer_add(autoReconnectCallback, AUTO_RECONNECT_TIME_MS)
    end)
    obs.obs_property_set_long_description(forceRestartTimer, "A stop-gap measure until timer_add works properly on script reload. Must be pressed to re-enable auto reconnecting when reloading script, otherwise OBS must be closed and opened again.")

    return properties
end

function script_load(settings)
    obs.timer_remove(autoReconnectCallback)
    obs.timer_add(autoReconnectCallback, AUTO_RECONNECT_TIME_MS)
    _SCRIPT_SETTINGS = settings
end

function script_unload()
    UNLOADING = true
    pwi.destroyNode(CENTRAL_VIRTUAL_MONITOR)
end

local pipewireAudioCaptureSource = {
    id = "pipewireAudioCaptureSource",
    icon_type = obs.OBS_ICON_TYPE_AUDIO_PROCESS_OUTPUT, -- Doesn't seem to work with obslua?
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
    data.capture_node = createSubMonitorNode(data.source_name)
    VolumeManager:set(data.capture_node, obs.obs_data_get_int(settings, "volume") / 100)
    if data.managed_node and data.auto_reconnect then
        AUTORECONNECT_NODES[data] = data.managed_node
    end
    if obs.obs_source_active(source) then
        pwi.connectNodes(data.capture_node, CENTRAL_VIRTUAL_MONITOR)
    end
    if data.managed_node and data.managed_node ~= "None" and obs.obs_source_active(source) then
        MANAGED_NODE_NAMES[data.managed_node] = true
        pwi.connectAllNamed(data.managed_node, data.capture_node)
    end

    return data
end

function pipewireAudioCaptureSource.destroy(data)
    AUTORECONNECT_NODES[data] = nil
    MANAGED_NODE_NAMES[data.managed_node] = nil
    pwi.destroyNode(data.capture_node)
end
function pipewireAudioCaptureSource.deactivate(data)
    -- pwi.disconnectAllNamed(data.managed_node, CENTRAL_VIRTUAL_MONITOR)
    -- MANAGED_NODE_NAMES[data.managed_node] = nil

    pwi.disconnectNodes(data.capture_node, CENTRAL_VIRTUAL_MONITOR)
end
function pipewireAudioCaptureSource.activate(data)
    pwi.connectNodes(data.capture_node, CENTRAL_VIRTUAL_MONITOR)
    if data.managed_node ~= "None" then
        MANAGED_NODE_NAMES[data.managed_node] = true
        pwi.connectAllNamed(data.managed_node, data.capture_node)
    end
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
        pwi.disconnectAllNamed(data.managed_node, data.capture_node)
        MANAGED_NODE_NAMES[data.managed_node] = nil

        print("New audio source:")
        print(newAudioSource)
        data.managed_node = newAudioSource
        if newAudioSource ~= "None" then
            if not data.capture_node then
                data.capture_node = createSubMonitorNode(data.source_name)
                pwi.connectNodes(data.capture_node, CENTRAL_VIRTUAL_MONITOR)
            end
            local captureID = data.capture_node

            MANAGED_NODE_NAMES[data.managed_node] = true
            pwi.connectAllNamed(data.managed_node, captureID)
        else
            AUTORECONNECT_NODES[data] = nil
        end
    end)

    local volumeProp = obs.obs_properties_add_int_slider(properties, "volume", "Volume (%)", 0, 100, 1)
    obs.obs_property_set_modified_callback(volumeProp, function(_, _, settings)
        local newVolume = obs.obs_data_get_int(settings, "volume") / 100
        VolumeManager:set(data.capture_node, newVolume)
    end)

    local autoreconnectProp = obs.obs_properties_add_bool(properties, "autoreconnect", "Automatically Connect New Sources with Same Name")
    obs.obs_property_set_long_description(autoreconnectProp, [[When a new audio source with the same name is created
automatically connect the new node to the capture.
Useful for when re-opening applications or in browsers.]])

    obs.obs_property_set_modified_callback(autoreconnectProp, function(props, prop, settings)
        data.auto_reconnect = obs.obs_data_get_bool(settings, "autoreconnect")
        if data.managed_node ~= "None" then
            AUTORECONNECT_NODES[data] = data.auto_reconnect and data.managed_node or nil
        end
    end)

    return properties
end

obs.obs_register_source(pipewireAudioCaptureSource)
