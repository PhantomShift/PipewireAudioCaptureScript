# Pipewire Audio Capture Script

A super scuffed script that attempts to make capturing specific application audio easier. By all practicality just a bunch of automated pw-cli calls, I am unfortunately not well-versed with C++ at the moment and do not have time (woohoo finals season) to work on a full-blown plugin. Note that currently all output nodes with a shared name will be captured (i.e. all audio outputs with the name 'Firefox'). This is intentional since my personal use-case is capturing game audio, which will often have multiple outputs created for some reason. I may add it as an option at some point but right now cannot be bothered

As the name implies, you need to be using pipewire as your audio backend for this script to function.

> Note: "OBS Pipewire Audio Capture Monitor" must be added as a global audio device under the audio settings for sound to be properly captured

## Script Properties
### `Auto Reconnection Time (ms)`
How often the script should poll for new nodes for automatically connecting new nodes with a given name. Default value of `500`. Note that setting this to a low value may introduce some stutter.

### `Restart Timer`
For whatever reason, `obslua.timer_add` does not run properly when reloading scripts, requiring that you re-open OBS or edit `Auto Reconnection Time (ms)` in order for auto reconnection to start functioning again.

## Source Properties
> Note: Currently, to my knowledge, `obslua.obs_properties_set_flags` does not function properly. Preferrably I would set the `OBS_PROPERTIES_DEFER_UPDATE` flag so that audio is not captured until the user has actually closed the settings window, but that is currently not the case, so keep that in mind when changing these properties.
### `Application Audio to Capture`
Node names to connect. Currently filters out any pipewire nodes that are not of `media.class`
 
 - `Stream/Output/Audio`
 - `Audio/Source`

 Currently this whitelist can be edited by editing `pwinterface.lua`, though I will likely decouple this hard-coded whitelist from the script in the future.
 ### `Automatically Connect New Sources with Same Name`
When a new audio source with the same name is created automatically connect the new node to the capture. Useful for when re-opening applications or in browsers.