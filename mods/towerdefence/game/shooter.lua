-- One weapon, being fired by something.
--
-- The player and a tower are the same object with different brains: position,
-- facing, weapon, cooldown, reload, ammo. This is the half they share — a
-- weapon's clip emptying and refilling, and what leaves the barrel when it
-- does — and it moved out of field.lua the moment it had a second caller,
-- which is the point the design predicted it would (plans/crimsonland.md).
--
-- `owner` is any table with x, y, angle, weapon, ammo, cooldown, reloading,
-- muzzle. `field` is the world the shot lands in: it owns the bullet list, and
-- it is the only thing that counts shots.
--
-- Nothing here knows *why* the trigger was pulled. A human holds a mouse
-- button, a tower has decided something is in range, and the weapon behaves
-- identically either way — which is the whole reason a weapon means the same
-- thing in your hands as on a mount.

local audio = require("src.engine.audio")
local fx = require("src.engine.fx")

local shooter = {}

-- A shooter with no modifier table is unmodified. That is how perks stay
-- player-only without a single conditional at the call sites: the player
-- carries `mods`, a mount does not (mods/towerdefence/game/cards.lua).
local NEUTRAL = {
	dmg = 1, fire = 1, reload = 1, clip = 1, clip_add = 0, bullet_speed = 1,
}

local function mods_of(owner)
	return owner.mods or NEUTRAL
end

-- Same conversions the rest of the mod uses (and vanilla before it).
local BULLET_SPEED_SCALE = 16
local RANGE_SCALE = 4

-- How far out from the shooter a round appears, in world pixels: the end of
-- the barrel rather than the middle of whoever is holding it. Public because a
-- mount solving for an intercept has to solve from the place the round really
-- starts (game/plots.lua) -- twenty pixels of head start arrives early enough
-- to miss a walking creature by half its own body.
shooter.MUZZLE_OFFSET = 20

-- Flame weapons are short-ranged sprays, not rifles: the XML range is the
-- number every weapon carries and it makes a flamethrower reach across the
-- map. Vanilla cuts it to 0.18 for the same reason.
local FLAME_RANGE_MUL = 0.18

function shooter.clip_size(owner)
	if not owner.weapon then return 0 end
	local m = mods_of(owner)
	return math.max(1, math.floor(owner.weapon.clip_size * m.clip + 0.5) + m.clip_add)
end

--- How fast this shooter's rounds fly, in world pixels per second.
--
-- Public because a mount has to know it to work out where a creature will be
-- when the round arrives (game/plots.lua). Reading it off the weapon at the
-- call site instead would be two copies of the same conversion, and the aim
-- would quietly stop matching the bullet the first time either changed.
function shooter.bullet_speed(owner)
	local w = owner.weapon
	if not w then return 0 end
	return w.projectile_speed * BULLET_SPEED_SCALE * mods_of(owner).bullet_speed
end

--- How far behind a constant-speed round this weapon's rounds run, in seconds.
--
-- A rocket spends its first third of a second below its rated speed, and the
-- distance it gives away doing so is fixed however far it flies:
-- (vmax - v0)^2 / 2a. Divided by the top speed that is a constant delay -- and
-- a constant delay is what lets a mount lead an accelerating round with the
-- same closed-form solve it uses for a bullet (game/plots.lua). Zero for
-- everything that leaves the barrel at speed.
function shooter.launch_lag(owner)
	local tr = owner.weapon and owner.weapon.traits
	if not (tr and tr.accel and tr.accel.rate > 0) then return 0 end
	local vmax = shooter.bullet_speed(owner)
	if vmax <= 0 then return 0 end
	local v0 = vmax * tr.accel.from
	return (vmax - v0) ^ 2 / (2 * tr.accel.rate) / vmax
end

--- How far this weapon's rounds actually travel, in world pixels.
function shooter.range(w)
	local range = w.projectile_range * RANGE_SCALE
	if w.proj_art == "flame" then range = range * FLAME_RANGE_MUL end
	return range
end

--- One trigger pull: a round (or a fan of them) into the world.
function shooter.fire(field, owner)
	local w = owner.weapon
	local m = mods_of(owner)
	owner.cooldown = w.shoot_interval / m.fire
	owner.ammo = math.max(0, owner.ammo - 1)
	owner.muzzle = 0.05
	field.shots = field.shots + 1
	audio.play_sound(w.snd_fire, 1, 0, 1 + (love.math.random() - 0.5) / 6)
	if w.brass then
		fx.spawn("fxs/shells1.lua", owner.x + math.cos(owner.angle) * 14,
			owner.y + math.sin(owner.angle) * 14, math.deg(owner.angle),
			{ layer = "world", fade = 0.25 })
	end
	local range = shooter.range(w)
	local speed = shooter.bullet_speed(owner)
	-- What this round *does*, as opposed to how big its numbers are: the same
	-- overlay vanilla reads (mods/vanilla/game/traits.lua), because a weapon
	-- has to mean the same thing on a mount as it does in your hands.
	local tr = w.traits
	for _ = 1, w.num_projectiles do
		local a = owner.angle + (love.math.random() - 0.5) * 2 * w.spread
		field.bullets[#field.bullets + 1] = {
			x = owner.x + math.cos(owner.angle) * shooter.MUZZLE_OFFSET,
			y = owner.y + math.sin(owner.angle) * shooter.MUZZLE_OFFSET,
			dx = math.cos(a), dy = math.sin(a),
			-- a rocket leaves the tube under power, not at speed
			speed = tr and tr.accel and speed * tr.accel.from or speed,
			accel = tr and tr.accel and tr.accel.rate or nil,
			max_speed = speed,
			traits = tr,
			blast = tr and tr.blast or nil,
			dist_left = range,
			damage = w.damage_effective * m.dmg,
			art = w.proj_art,
			bolt = w.proj_scale,
			weapon_id = w.id,
			-- who fired it, so a kill can be credited to the mount that made
			-- it. "Is that mount earning its money" is the question the whole
			-- economy asks, and it cannot be answered by a number nobody keeps.
			owner = owner,
		}
	end
end

--- Advance one shooter's weapon by dt. `wants_fire` and `wants_reload` are the
-- brain's answer; everything else is the weapon's own numbers.
function shooter.update(field, owner, dt, wants_fire, wants_reload)
	local w = owner.weapon
	if not w then return end
	local m = mods_of(owner)
	owner.cooldown = math.max(0, owner.cooldown - dt)
	owner.muzzle = math.max(0, owner.muzzle - dt)

	if owner.reloading > 0 then
		owner.reloading = owner.reloading - dt
		if owner.reloading <= 0 then owner.ammo = shooter.clip_size(owner) end
		return
	end
	if wants_reload and owner.ammo < shooter.clip_size(owner) then
		owner.reloading = w.reload_time * m.reload
		owner.reload_total = owner.reloading
		audio.play_sound(w.snd_reload)
		return
	end
	if wants_fire and owner.cooldown <= 0 then
		if owner.ammo <= 0 then
			owner.reloading = w.reload_time * m.reload
			owner.reload_total = owner.reloading
			audio.play_sound(w.snd_reload)
		else
			shooter.fire(field, owner)
		end
	end
end

return shooter
