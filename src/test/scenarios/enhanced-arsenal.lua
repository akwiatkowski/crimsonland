-- The enhanced cartridge's sixteen weapons reach the game, and the pak's own
-- thirty-one come out of it unchanged.
--
--   make test MOD=enhanced SCENARIO=enhanced-arsenal
--
-- This is the structural half of the cartridge: no fight, no AI, nothing that
-- can be flaky. `data.weapon_overlay` is a seam that either lands or silently
-- does nothing -- a typo in an id leaves a weapon with no verbs and no error,
-- an index colliding with the pak's would overwrite one of the original's
-- entries in `weapon_order`, and a missing icon file draws as an empty pickup
-- that nothing complains about. Each of those is invisible from inside a run
-- and obvious from here.
--
-- The last three expectations are the ones that matter most: the point of a
-- cartridge is that vanilla is untouched, so the pistol's damage, the blade
-- gun's verbs and the size of the pak's own run of weapons are all asserted
-- against the numbers they had before any of this existed.

local data = require("mods.vanilla.game.data")

local PAK_WEAPONS = 31 -- the leading run in weapons.xml that carries an icon
local ADDED = 16

local function overlay()
	data.load_all()
	local list = {}
	for i = data.last_player_weapon + 1, #data.player_weapons do
		list[#list + 1] = data.player_weapons[i]
	end
	return list
end

local function report()
	for _, w in ipairs(overlay()) do
		local verbs = {}
		for verb in pairs(w.traits or {}) do verbs[#verbs + 1] = verb end
		table.sort(verbs)
		print(("[arsenal] %-17s idx=%-3d %-7s dmg=%-5.1f spread=%.2fdeg  %s"):format(
			w.id, w.index, w.proj_art, w.damage_effective,
			math.deg(w.spread), table.concat(verbs, ",")))
	end
end

local function merged()
	local list = overlay()
	if #list ~= ADDED then
		return false, ("overlay merged %d weapons, expected %d"):format(#list, ADDED)
	end
	for _, w in ipairs(list) do
		if not w.traits then
			return false, ("%s carries no verbs (bad id in traits.lua?)"):format(w.id)
		end
		if not w.icon then
			return false, ("%s has no icon path"):format(w.id)
		end
		if not love.filesystem.getInfo("mods/enhanced/assets/" .. w.icon) then
			return false, ("%s icon is missing: %s"):format(w.id, w.icon)
		end
		-- authored, not derived: `damage_effective` falls back to a heuristic
		-- off stat_damage whenever projectile_damage is 1 or less, and a new
		-- weapon accidentally taking that path is a weapon nobody chose the
		-- strength of
		if w.damage_effective ~= w.projectile_damage then
			return false, ("%s damage is derived (%.2f) not authored (%.2f)"):format(
				w.id, w.damage_effective, w.projectile_damage)
		end
	end
	return true, ("all %d weapons merged, with verbs, art and authored damage"):format(#list)
end

--- Nothing the cartridge added may have landed on top of anything the pak
-- numbered. `weapon_order` is keyed by weapons.xml's own index and the gallery
-- plates are addressed through it, so a collision would silently replace one
-- of the original's weapons with one of ours.
local function no_collisions()
	data.load_all()
	local ours = {}
	for _, w in ipairs(overlay()) do ours[w.index] = w.id end
	for idx, id in pairs(ours) do
		if idx <= 63 then
			return false, ("%s sits at index %d, inside the pak's own numbering"):format(id, idx)
		end
	end
	for idx, w in pairs(data.weapon_order) do
		if ours[idx] and ours[idx] ~= w.id then
			return false, ("index %d is both %s and %s"):format(idx, ours[idx], w.id)
		end
	end
	return true, "every added index is clear of the pak's"
end

local function pool_intact()
	data.load_all()
	if data.last_player_weapon ~= PAK_WEAPONS then
		return false, ("the pak's own run is %d weapons, expected %d"):format(
			data.last_player_weapon, PAK_WEAPONS)
	end
	if #data.player_weapons ~= PAK_WEAPONS + ADDED then
		return false, ("pool is %d, expected %d"):format(
			#data.player_weapons, PAK_WEAPONS + ADDED)
	end
	-- the pool has to stay dense, or a drop roll lands on a hole
	for i = 1, #data.player_weapons do
		if not data.player_weapons[i] then
			return false, ("pool slot %d is empty"):format(i)
		end
	end
	return true, ("pool is %d weapons, dense, pak's %d first"):format(
		#data.player_weapons, PAK_WEAPONS)
end

local function vanilla_unmoved()
	data.load_all()
	local pistol = data.weapons.PISTOL
	if not pistol or pistol.damage_effective ~= 4.1 then
		return false, ("the pistol's damage moved: %s"):format(
			pistol and tostring(pistol.damage_effective) or "no pistol")
	end
	local blade = data.weapons.BLADE_GUN
	if not (blade and blade.traits and blade.traits.ricochet == 3) then
		return false, "vanilla's own trait overlay stopped merging"
	end
	return true, "the pak's weapons come out as they always did"
end

return {
	{ t = 1.5, run = report },
	{ t = 1.6, expect = merged },
	{ t = 1.7, expect = no_collisions },
	{ t = 1.8, expect = pool_intact },
	{ t = 1.9, expect = vanilla_unmoved },
}
