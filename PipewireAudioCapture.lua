local obs = obslua
local pwi = require "pwinterface"
local wpi = require "wpinterface"
local processManager = require "processManager"

wpi.init(script_path())

local _SCRIPT_DEBUG_MODE = false
if not _SCRIPT_DEBUG_MODE then
    print("Pipewire Audio Capture script debugging is off.")
    local print = _G.print
    _G.print = function(...)
        return nil
    end
end

-- [nodeName] = true/nil
local MANAGED_NODE_NAMES = {}

-- [data] = pid/nil
local AUTORECONNECT_PROCESSES = {}
local function startAutoConnecting(outputNode, inputNode)
    local pid = processManager:spawn(("wpexec %s/WirePlumberScripts/autoconnect.lua inputNode=\"%s\" outputNode=\"%s\""):format(
        script_path(),
        inputNode,
        outputNode
    ))

    return pid
end

local CENTRAL_VIRTUAL_MONITOR = "OBS Pipewire Audio Capture Monitor"
local CENTRAL_VIRTUAL_MONITOR_MEDIA_CLASS = "Audio/Sink" -- Cannot be virtual as it will not be detected by OBS

wpi.createMonitor(CENTRAL_VIRTUAL_MONITOR, CENTRAL_VIRTUAL_MONITOR_MEDIA_CLASS)

local function createSubMonitorNode(nodeName)
    return wpi.createMonitor("OBS Source " .. nodeName, "Audio/Sink/Virtual")
end

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

    return properties
end

local function shutdownCallback(event, _)
    print(event)
    if event == obs.OBS_FRONTEND_EVENT_SCRIPTING_SHUTDOWN then
        pwi.destroyNode(CENTRAL_VIRTUAL_MONITOR)
    end
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(shutdownCallback)
    print "Loaded successfully"
end

function script_unload()
    for p in pairs(processManager) do
        processManager:kill(p)
    end
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
    data.capture_name = "OBS Source " .. data.source_name
    VolumeManager:set(data.capture_node, obs.obs_data_get_int(settings, "volume") / 100)
    if data.managed_node and data.auto_reconnect then
        AUTORECONNECT_PROCESSES[data] = startAutoConnecting(data.managed_node, data.capture_name)
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
    processManager:kill(AUTORECONNECT_PROCESSES[data])
    AUTORECONNECT_PROCESSES[data] = nil
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

    -- local audioSources = pwi.listNodesByName()
    local audioSources = wpi.listNodes(nil, "Stream/Output/Audio,Audio/Source")
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
        if AUTORECONNECT_PROCESSES[data] then
            processManager:kill(AUTORECONNECT_PROCESSES[data])
            AUTORECONNECT_PROCESSES[data] = nil
        end

        print("New audio source:")
        print(newAudioSource)
        data.managed_node = newAudioSource
        if newAudioSource ~= "None" then
            if not data.capture_node then
                data.capture_node = createSubMonitorNode(data.source_name)
                data.capture_name = "OBS Source " .. data.source_name
                pwi.connectNodes(data.capture_node, CENTRAL_VIRTUAL_MONITOR)
            end
            local captureID = data.capture_node

            MANAGED_NODE_NAMES[data.managed_node] = true
            pwi.connectAllNamed(data.managed_node, captureID)

            if data.auto_reconnect then
                AUTORECONNECT_PROCESSES[data] = startAutoConnecting(data.managed_node, data.capture_name)
            end
        else
            processManager:kill(AUTORECONNECT_PROCESSES[data])
            AUTORECONNECT_PROCESSES[data] = nil
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
            if data.auto_reconnect and data.managed_node then
                AUTORECONNECT_PROCESSES[data] = startAutoConnecting(data.managed_node, data.capture_name)
            else
                processManager:kill(AUTORECONNECT_PROCESSES[data])
                AUTORECONNECT_PROCESSES[data] = nil
            end
        end
    end)

    return properties
end

obs.obs_register_source(pipewireAudioCaptureSource)
