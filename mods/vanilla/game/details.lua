-- The weapon detail screen (ui/weapon-details.lua).
--
-- It ships fully laid out and nothing in the pak or this port could push it:
-- the gallery answered a click with nothing and put what it had to say in a
-- hover tooltip instead. A tooltip is 380 pixels wide and holds one line;
-- weapon-details holds the name, the ammo cell's own icon, the clip size and
-- four bars.
--
-- The tooltip stays. It is the thing you read while sweeping the grid, and this
-- is the thing you open when one of them interests you.
--
-- What fills what, by layout line:
--
--   weapon-details.lua:21  WeaponName          w.name
--   weapon-details.lua:73  ClipSize            w.clip_size
--   weapon-details.lua:81  ammo_type           w.ammo_icon (the family's cell)
--   weapon-details.lua:87  slider_accuracy     stat_accuracy, authored, all 31
--   weapon-details.lua:93  slider_damage       stat_damage, authored, all 31
--   weapon-details.lua:99  slider_fire_rate    stat_fire_rate where authored
--   weapon-details.lua:105 slider_reload_time  derived, see RATE below
--
-- Nothing else on the layout carries data: text_ptype ("Ammo"),
-- text_accuracy, text_damage, text_fire_rate, text_fire_rate2 ("Reload TIme",
-- the original's own typo) and text_clip_size are static labels, and fader,
-- panel and grid are furniture.
--
-- Not filled, because the data cannot: weapons.xml's `projectile_type` is on
-- two weapons (PLASMA_OVERLOAD and MEGALASER, both creature guns) and this
-- screen has no comp for it -- text_ptype is the label, not the value.

local comps = require("src.engine.comps")
local data = require("mods.vanilla.game.data")
local gallery = require("mods.vanilla.game.gallery")

local details = {}

-- ---------------------------------------------------------------- the bars
--
-- Two of the four bars are authored ratings and go straight on: stat_damage and
-- stat_accuracy are on all 31 player weapons. The other two are not that
-- simple, and this is the port's own reading rather than the data's:
--
--   fire rate    stat_fire_rate exists, and is authored on exactly one weapon
--                (SPLITTER_GUN). One of 31 is not a dataset -- it is an
--                override, for the gun whose nominal rate lies about it. So
--                the bar is the weapon's own rate, with that override winning
--                where it is present.
--   reload       no rating is authored for it at all, only reload_time in
--                seconds. Nothing to defer to, so it is derived too.
--
-- Both are normalised across the roster, so a bar means "compared with every
-- other gun you can hold" -- and both point the same way as the two authored
-- bars, more bar being better. A slower reload is therefore a shorter bar.
--
-- Rate is compared on a log scale because the arsenal is not linear: 1.4 shots
-- a second for the pistol against 164 for the blow torch. Linear would put
-- twenty-nine guns in the bottom tenth of the bar and tell the player nothing.

local range = nil

local function roster_range()
	if range then return range end
	data.load_weapons()
	local r = { rate_lo = math.huge, rate_hi = 0, rel_lo = math.huge, rel_hi = 0 }
	for i = 1, data.last_player_weapon do
		local w = data.weapon_order[i]
		if w then
			local rate = math.log(1 / math.max(0.0001, w.shoot_interval))
			r.rate_lo, r.rate_hi = math.min(r.rate_lo, rate), math.max(r.rate_hi, rate)
			r.rel_lo = math.min(r.rel_lo, w.reload_time)
			r.rel_hi = math.max(r.rel_hi, w.reload_time)
		end
	end
	range = r
	return r
end

local function span(v, lo, hi)
	if hi <= lo then return 0 end
	return math.max(0, math.min(1, (v - lo) / (hi - lo)))
end

--- 0..1 for each of the four bars.
function details.bars(w)
	local r = roster_range()
	return {
		slider_accuracy = w.stat_accuracy,
		slider_damage = w.stat_damage,
		slider_fire_rate = w.stat_fire_rate
			or span(math.log(1 / math.max(0.0001, w.shoot_interval)), r.rate_lo, r.rate_hi),
		-- inverted: the fastest reload in the arsenal is the longest bar
		slider_reload_time = 1 - span(w.reload_time, r.rel_lo, r.rel_hi),
	}
end

-- ---------------------------------------------------------------- filling

local function put(screen, name, prop, value)
	local comp = screen.compmap[name]
	if comp and value ~= nil then comps.set(comp, prop, { value }) end
end

--- The screen carries its subject on the screen's own parm, which is what the
-- engine's push() takes it for -- the same way the unlock celebrations carry
-- which plate to point at.
function details.prepare(screen_name, screen)
	if screen_name ~= "WeaponDetails" then return end
	local index = tonumber(screen.parm)
	local w = index and gallery.entry_at("weapon", index)
	if not w then return end
	put(screen, "WeaponName", "textbox.text", w.name)
	put(screen, "ClipSize", "textbox.text", tostring(w.clip_size))
	put(screen, "ammo_type", "image.bitmap", w.ammo_icon)
	for comp_name, value in pairs(details.bars(w)) do
		put(screen, comp_name, "slider.value", value)
	end
end

return details
