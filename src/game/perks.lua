-- Perk definitions. The original perk roster/effects were compiled into
-- prog.dll (only numbered icons ship in the pak), so this is a clean-room
-- set of the classic Crimsonland perks. Names/descriptions follow the
-- originals where they are known (Thick Skinned's text appears verbatim
-- in ui/pick-a-perk.lua).
--
-- Effects are expressed as multipliers/adders on game.mods, consumed by
-- play.lua:
--   dmg      weapon damage multiplier
--   fire     fire-rate multiplier (shoot_interval divided by this)
--   reload   reload-time multiplier
--   speed    player move-speed multiplier
--   clip     clip-size multiplier
--   xp       experience-gain multiplier
--   taken    incoming-damage multiplier
--   regen    hp per second
--   kill_heal  hp restored per kill
--   heal_mul   health-pack effectiveness multiplier

local perks = {}

perks.list = {
	{
		id = "FASTLOADER",
		name = "Fastloader",
		desc = "You reload your weapon 40% faster.",
		icon = "perks/perk_01.png",
		apply = function(mods) mods.reload = mods.reload * 0.6 end,
	},
	{
		id = "SHARPSHOOTER",
		name = "Sharpshooter",
		desc = "Your shots hit where it hurts: +30% damage.",
		icon = "perks/perk_02.png",
		apply = function(mods) mods.dmg = mods.dmg * 1.3 end,
	},
	{
		id = "FASTSHOT",
		name = "Fastshot",
		desc = "Your trigger finger is a blur: +25% rate of fire.",
		icon = "perks/perk_03.png",
		apply = function(mods) mods.fire = mods.fire * 1.25 end,
	},
	{
		id = "LONG_DISTANCE_RUNNER",
		name = "Long Distance Runner",
		desc = "You move 20% faster. Handy when everything wants a bite.",
		icon = "perks/perk_04.png",
		apply = function(mods) mods.speed = mods.speed * 1.2 end,
	},
	{
		id = "THICK_SKINNED",
		name = "Thick Skinned",
		desc = "Trade 1/3 of your health for only receiving 2/3rds damage on attacks.",
		icon = "perks/perk_05.png",
		apply = function(mods, game)
			mods.taken = mods.taken * (2 / 3)
			game.player.hp = math.max(1, game.player.hp * (2 / 3))
		end,
	},
	{
		id = "REGENERATION",
		name = "Regeneration",
		desc = "Your wounds slowly close on their own: +1.5 hp per second.",
		icon = "perks/perk_06.png",
		apply = function(mods) mods.regen = mods.regen + 1.5 end,
	},
	{
		id = "AMMO_MANIAC",
		name = "Ammo Maniac",
		desc = "You cram 50% more ammo into every clip.",
		icon = "perks/perk_07.png",
		apply = function(mods) mods.clip = mods.clip * 1.5 end,
	},
	{
		id = "LEAN_MEAN_EXP_MACHINE",
		name = "Lean Mean Exp. Machine",
		desc = "You gain experience 25% faster.",
		icon = "perks/perk_08.png",
		apply = function(mods) mods.xp = mods.xp * 1.25 end,
	},
	{
		id = "BLOODLUST",
		name = "Bloodlust",
		desc = "Every kill restores 2 health. Keep the streak going.",
		icon = "perks/perk_09.png",
		apply = function(mods) mods.kill_heal = mods.kill_heal + 2 end,
	},
	{
		id = "DOCTOR",
		name = "Doctor",
		desc = "You know how to use a medikit: health pickups heal double.",
		icon = "perks/perk_10.png",
		apply = function(mods) mods.heal_mul = mods.heal_mul * 2 end,
	},
	{
		id = "TOUGH_RELOADER",
		name = "Tough Reloader",
		desc = "While reloading you take 30% less damage. Panic responsibly.",
		icon = "perks/perk_11.png",
		apply = function(mods) mods.reload_guard = 0.7 end,
	},
	{
		id = "RADIOACTIVE",
		name = "Radioactive",
		desc = "Creatures touching you burn for 6 damage per second.",
		icon = "perks/perk_12.png",
		apply = function(mods) mods.touch_burn = (mods.touch_burn or 0) + 6 end,
	},
}

function perks.fresh_mods()
	return {
		dmg = 1, fire = 1, reload = 1, speed = 1, clip = 1, xp = 1,
		taken = 1, regen = 0, kill_heal = 0, heal_mul = 1,
		reload_guard = 1, touch_burn = 0,
	}
end

--- Pick `n` random perks the player does not own yet.
function perks.offer(n, owned)
	local pool = {}
	for _, p in ipairs(perks.list) do
		if not owned[p.id] then pool[#pool + 1] = p end
	end
	-- Fisher-Yates prefix shuffle
	for i = 1, math.min(n, #pool) do
		local j = love.math.random(i, #pool)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(n, #pool) do out[i] = pool[i] end
	return out
end

return perks
