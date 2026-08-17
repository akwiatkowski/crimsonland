-- Music + sound effect playback, replicating the engine's logical-name API.

local assets = require("src.engine.assets")

local audio = {}

audio.music_volume = 1.0
audio.sound_volume = 1.0
audio.current_music = nil -- logical name
audio.music_source = nil

local delayed = {} -- { {name=..., time_left=...}, ... }

function audio.switch_music(name, fade_out, fade_in)
	-- fades are approximated: instant switch (fade support is polish)
	if audio.current_music == name then return end
	if audio.music_source then
		audio.music_source:stop()
		audio.music_source = nil
	end
	audio.current_music = name
	if name and name ~= "" and name ~= "!NONE" then
		local src = assets.sound(name, "music")
		if src then
			src:setLooping(true)
			src:setVolume(audio.music_volume)
			src:play()
			audio.music_source = src
		end
	end
end

function audio.stop_music()
	if audio.music_source then audio.music_source:stop() end
	audio.music_source = nil
	audio.current_music = nil
end

--- Temporary attenuation for sounds the player did not cause — attract mode's
-- gunfire under the menu. Deliberately separate from sound_volume, which is
-- the player's own setting and what the options screen reads back.
audio.duck = 1

--- UI sounds: button clicks and script-triggered cues, never ducked.
function audio.play_ui_sound(name, vol, pan, freq)
	local duck = audio.duck
	audio.duck = 1
	local s = audio.play_sound(name, vol, pan, freq)
	audio.duck = duck
	return s
end

function audio.play_sound(name, vol, pan, freq)
	local src = assets.sound(name, "sfx")
	if not src then return nil end
	-- static sources can't be reused while playing; clone for overlap
	local s = src:clone()
	s:setVolume((vol or 1) * audio.sound_volume * audio.duck)
	if freq and freq ~= 1 then s:setPitch(freq) end
	s:play()
	return s
end

function audio.play_sound_delayed(name, delay)
	table.insert(delayed, { name = name, time_left = delay or 0 })
end

function audio.set_music_volume(v)
	audio.music_volume = v
	if audio.music_source then audio.music_source:setVolume(v) end
end

function audio.update(dt)
	for i = #delayed, 1, -1 do
		local d = delayed[i]
		d.time_left = d.time_left - dt
		if d.time_left <= 0 then
			audio.play_sound(d.name)
			table.remove(delayed, i)
		end
	end
end

return audio
