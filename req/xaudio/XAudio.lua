_G.XAudio = {}

-- Constants
XAudio.PLAYER = "xa_player_1"

-- Variables
XAudio._sources = {}
XAudio._next_source_id = 1
-- Vanilla's default value for Music and Sound is 20%
-- If the loaded value is higher or lower than 20%, it is updated in the callback down below
-- The value is updated in menu/mission load (if not 20% on first game load, everytime else)
-- or user changes the value themselves (always regardless of value)
XAudio._base_gains = {
	sfx = 0.2,
	music = 0.2
}

BLT:Require("req/xaudio/XAudioBuffer")
BLT:Require("req/xaudio/XAudioSource")
BLT:Require("req/xaudio/XAudioUnitSource")

BLT:Require("req/xaudio/VoicelineManager")

-- This is our wu-to-meters conversion
-- You can get it using blt.xaudio.getworldscale() if you need to use it
-- This means we can use positions from the game without worrying about
-- unit conversion or anything.
blt.xaudio.setworldscale(100)

-- Delete any existing sources from the last heist/menu
blt.xaudio.reset()

local _device_check_t = 0
local function check_device(dt)
	if not blt.xaudio.checkdevice then
		return
	end
	_device_check_t = _device_check_t + dt
	if _device_check_t < 1 then
		return
	end
	_device_check_t = 0
	blt.xaudio.checkdevice()
end

local function update(t, dt, paused)
	for _, src in pairs(XAudio._sources) do
		src:update(t, dt, paused)
	end
	check_device(dt)
end

Hooks:Add("MenuUpdate", "Base_XAudio_MenuSetupUpdate", function(t, dt)
	update(t, dt, false)
end)

Hooks:Add("GameSetupUpdate", "Base_XAudio_GameSetupUpdate", function(t, dt)
	update(t, dt, false)
end)

Hooks:Add("GameSetupPausedUpdate", "Base_XAudio_GameSetupPausedUpdate", function(t, dt)
	update(t, dt, true)
end)

Hooks:Add("MenuManagerInitialize", "Base_XAudio_SetUpdateCallbacks", function(menu_manager)
	managers.user:add_setting_changed_callback("music_volume", function(setting_name, default_value, value)
		XAudio._base_gains.music = value / 100
	end, true)
	managers.user:add_setting_changed_callback("sfx_volume", function(setting_name, default_value, value)
		XAudio._base_gains.sfx = value / 100
	end, true)
end)
