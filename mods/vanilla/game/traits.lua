-- Projectile traits: what a round *does*, as opposed to how big its numbers are.
--
-- The diagnosis this exists to answer: all 38 weapons in weapons.xml collapse
-- to roughly four behaviours, because the port reads seven numbers per weapon
-- and spawns a straight line from them. Half the arsenal's names are promises
-- the code never kept -- SEEKER_ROCKETS did not seek, SPLITTER_GUN did not
-- split, BLADE_GUN did not ricochet, SHRINKIFIER_5K did not shrink. That is
-- false variety: 38 entries and one decision ("is the number bigger?").
--
-- So this is not a stat line. It is a small set of verbs a projectile can
-- have, and weapons are recombinations of them:
--
--   pierce   = N     passes through N bodies before stopping
--   ricochet = N     bounces off the playfield edge N times
--   homing   = deg/s steers toward the nearest creature at this turn rate
--   accel    = {from, rate}  leaves the barrel at `from` of the weapon's rated
--                            speed and gains `rate` px/s^2 up to it
--   blast    = {radius, damage}  detonates where it stops: everything within
--                            `radius` takes `damage` times the round's own,
--                            falling off with distance
--   split    = {n, spread}  breaks into n children when it stops
--   chain    = {jumps, range, decay}  arcs on to further creatures
--   slow     = {factor, seconds}      what it hits moves slower
--   shrink   = factor                 what it hits gets smaller (and weaker)
--
-- The pak is read-only and stays untouched, so this is a mod-side overlay:
-- data.load_weapons merges it onto the weapons it parsed, keyed by id. A mod
-- adding its own weapons adds them the same way.
--
-- Nothing here invents a weapon. Every entry is a name in the original's own
-- data finally doing what it says.

-- What every rocket in the arsenal shares, and what tells one from a bullet.
--
-- A rocket has a motor: it leaves the tube well below its rated speed and
-- builds up to it, which is why a launch is something you can watch and why
-- standing close to a rocket mount is different from standing close to a
-- rifle. `from` is a fraction of the weapon's own projectile_speed and `rate`
-- is picked so the round reaches that speed in about a third of a second --
-- long enough to read as a launch, short enough that the range in weapons.xml
-- is still the distance the round covers.
local ROCKET_ACCEL = { from = 0.35, rate = 1300 }

-- Ordnance goes off where it stops instead of punching one hole. Radius in
-- world pixels, damage as a multiple of the round's own, linear falloff to the
-- edge -- the numbers the port has always detonated with, now written where
-- both the weapon table and the code can see them.
local BLAST_MEDIUM = { radius = 80, damage = 2 }

return {
	-- The four whose names were already promises ------------------------

	-- "Seeker" rockets that fly straight are the clearest example of the
	-- problem. Slow turn: they should correct toward a target, not track it
	-- like a wire-guided missile, or dodging stops mattering. With the motor
	-- and the warhead they are finally the whole word: a rocket that lights,
	-- chases and goes off.
	SEEKER_ROCKETS = { homing = 150, accel = ROCKET_ACCEL, blast = BLAST_MEDIUM },
	MINI_ROCKET_SWARMERS = { homing = 110, accel = ROCKET_ACCEL, blast = BLAST_MEDIUM },

	-- The rockets that never claimed to steer still light and still detonate.
	ROCKET_LAUNCHER = { accel = ROCKET_ACCEL, blast = BLAST_MEDIUM },
	ROCKET_MINIGUN = { accel = ROCKET_ACCEL, blast = BLAST_MEDIUM },

	-- A splitter that does not split. Children carry the parent's family and
	-- a share of its damage, so splitting is reach rather than free damage.
	SPLITTER_GUN = { split = { count = 3, spread = 34, damage = 0.5 } },

	-- A thrown blade bounces off things. Three is enough for the ricochet to
	-- be a tactic in a corner without the blade living forever.
	BLADE_GUN = { ricochet = 3 },

	-- "Shrinkifier". Smaller creatures are worth less XP by variant scale, so
	-- this is a defensive weapon rather than a damage one -- which is exactly
	-- what its terrible damage rating already said.
	SHRINKIFIER_5K = { shrink = 0.72 },

	-- The gauss family is the game's railgun class and the XML gives it no
	-- identity at all (flags=1, shared with the plain shotgun). Piercing is
	-- what a railgun is: it goes through what it hits.
	GAUSS_GUN = { pierce = 3 },
	GAUSS_SHOTGUN = { pierce = 1 },
	GAUSS_MINIGUN = { pierce = 2 },

	-- Energy weapons ----------------------------------------------------

	-- The pulse gun fires a shockwave front (its own family in weapons.xml,
	-- and the sprite on projs.tga is a wave). A wave does not stop at the
	-- first body, and it breaks where it lands -- the port has always
	-- detonated this one alongside the rockets.
	PULSE_GUN = { pierce = 2, blast = BLAST_MEDIUM },

	-- Ion weapons arc. The original's ion chain was cut from the effects
	-- round for depicting a rule the game lacked -- this is that rule.
	ION_CANNON = { chain = { jumps = 3, range = 150, decay = 0.6 } },
	MULTI_ION = { chain = { jumps = 2, range = 130, decay = 0.55 } },

	-- Plasma runs cold enough to slow what it touches; it is the family with
	-- the worst rate of fire, so a control effect is what makes it worth it.
	PLASMA_RIFLE = { slow = { factor = 0.6, seconds = 1.5 } },
	PLASMA_CANNON = { slow = { factor = 0.45, seconds = 2.5 } },

	-- Kinetic -----------------------------------------------------------

	-- A jackhammer is a heavy slug thrower; one body does not stop it.
	JACKHAMMER = { pierce = 1 },
	-- Bubbles bounce. This one is a joke weapon in the original and bouncing
	-- is the funniest true thing about it.
	BUBBLEGUN = { ricochet = 4 },
}
