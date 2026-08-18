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

-- Same conversions the rest of the mod uses (and vanilla before it).
local BULLET_SPEED_SCALE = 16
local RANGE_SCALE = 4

-- Flame weapons are short-ranged sprays, not rifles: the XML range is the
-- number every weapon carries and it makes a flamethrower reach across the
-- map. Vanilla cuts it to 0.18 for the same reason.
local FLAME_RANGE_MUL = 0.18

function shooter.clip_size(owner)
	return owner.weapon and owner.weapon.clip_size or 0
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
	owner.cooldown = w.shoot_interval
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
	for _ = 1, w.num_projectiles do
		local a = owner.angle + (love.math.random() - 0.5) * 2 * w.spread
		field.bullets[#field.bullets + 1] = {
			x = owner.x + math.cos(owner.angle) * 20,
			y = owner.y + math.sin(owner.angle) * 20,
			dx = math.cos(a), dy = math.sin(a),
			speed = w.projectile_speed * BULLET_SPEED_SCALE,
			dist_left = range,
			damage = w.damage_effective,
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
	owner.cooldown = math.max(0, owner.cooldown - dt)
	owner.muzzle = math.max(0, owner.muzzle - dt)

	if owner.reloading > 0 then
		owner.reloading = owner.reloading - dt
		if owner.reloading <= 0 then owner.ammo = shooter.clip_size(owner) end
		return
	end
	if wants_reload and owner.ammo < shooter.clip_size(owner) then
		owner.reloading = w.reload_time
		owner.reload_total = owner.reloading
		audio.play_sound(w.snd_reload)
		return
	end
	if wants_fire and owner.cooldown <= 0 then
		if owner.ammo <= 0 then
			owner.reloading = w.reload_time
			owner.reload_total = owner.reloading
			audio.play_sound(w.snd_reload)
		else
			shooter.fire(field, owner)
		end
	end
end

return shooter
