# Crimsonland macOS Port

An attempt to port **Crimsonland (2014 remaster, GOG v2.2.0.4)** natively to macOS
by reusing the original game assets and Lua scripts with a new runtime.

## Why this is feasible

The 2014 remaster by 10tons is built on their in-house engine where:

- **Game logic lives in plaintext Lua 5.1 scripts** (123 files, ~11.3k lines) inside `data.pak`
- **Game data lives in XML** (creatures, weapons, perks, chapters, game modes...)
- **Assets are plain PNG / Ogg Vorbis** inside `.pak` archives (custom "PAK V11" format)
- The engine exposes a compact C API to Lua: 61 `NX_*` functions
  (bitmap loading/drawing, sound, input, transforms, text)

So instead of decompiling x86 machine code, we can **reimplement the engine API**
(on top of LÖVE/LuaJIT — which is Lua 5.1 compatible — or a custom SDL runtime)
and run the original scripts natively on Apple Silicon.

## Current status

Done:

- [x] Unpacked `Crimsonland.2014.rar` → GOG installer (`setup_crimsonland_2.2.0.4.exe`, Inno Setup 5.5.0)
- [x] Extracted installer with `innoextract` → `extracted/app/`
- [x] Reverse-engineered the PAK V11 archive format → `tools/extract_pak.py`
- [x] Extracted all assets: `assets/` (4157 files), `assets-1080p/` (3119),
      `assets-music/` (7 OGG), `assets-sfx/` (104 OGG)
- [x] Confirmed Lua scripts are plaintext (not bytecode)
- [x] Identified 61 `NX_*` engine API functions (strings in `prog.dll`)
- [x] LÖVE runtime running the original UI scripts — menus render and navigate
- [x] Playable quest mode on the original XML data (terrain baking, creature
      spawning/AI, weapons, `.bms` animations, HUD)
- [x] Weapon + medikit drops (rockets explode, flamethrowers spray), particle FX,
      persistent gore baked into the terrain
- [x] Perks on level-up via the original PickAPerk screen (12 classic perks)
- [x] Survival mode (ramping waves) with the original SurvivalOver stats screen;
      quest results use LevelCompleted/LevelFailed (Play Next / Retry)
- [x] Persistence: profiles, completed quests, survival high score

- [x] Pause menu (Esc), timed powerups (nuke/freeze/shield/points/speed/fire),
      authored quest definitions with chapter palettes and quest-10 bosses
- [x] XML-driven creature AI (shooters, dens), 25-perk roster with gambles
- [x] Endless-mode family: Rush, Blitz, Waves, Nukefism, Weapon Picker
- [x] Mod architecture (engine = console, `mods/` = cartridges, `--mod=<name>`)
- [x] In-game HUD rebuilt from the original 2014 art (crosshair, health pie,
      ammo, XP strip, powerup chips)
- [x] Retina-native rendering on the 1080p art set (canvas at true pixel
      density, glyphs rasterized at device size)
- [x] `.mft` bitmap font decoder — the game's own letterforms, with kerning
- [x] Original `fxs/` particle DSL interpreted (spent brass on the real
      emitter parameters; the pak ships no blood/explosion effect files)
- [x] Quest and chapter unlock gating fed from the save data
- [x] Attract mode: the menu sits on a live game played by an AI, as the
      original's timeline intends
- [x] High Scores + Statistics screens, lifetime stats and per-mode bests
- [x] Weapon and perk galleries with hover details
- [x] Options that apply and persist (volume sliders, windowed)

- [x] Achievements (22 from `achievements.xml`, awarded from save data)
- [x] "New weapon/perk unlocked" celebrations on the original screens
- [x] Resolution picker (`Listbox` comp) and `required_features` gating, so
      platform-specific buttons stop showing up
- [x] Mod architecture phase 2: the game lives entirely in `mods/vanilla/`

- [x] The full 55-perk roster, with the original's own names and descriptions
      read out of `prog.dll` (the pak ships only numbered icons)
- [x] Custom Quests — the authored-quest format from `custom-quests/`, with
      the play-menu button the pak has a handler for and no layout
- [x] Gameplay effects (blood, gore, explosions, pickups) authored in the
      original's `fxs/` DSL against `game/particles.tga`, replacing a second
      hand-rolled particle system
- [x] `Emitter` and `Editbox` comps — the last two comp types the pak uses
- [x] The whole shipped music set, per quest and per endless run
- [x] Galleries show only what you have met: locked plates until first sight,
      and a discovered count
- [x] The playfield art the pak ships and nothing was drawing: shadows under
      everything alive (`bm_shadow`), body parts thrown by a kill and baked
      where they land (`bm_gibs_unique`/`_common`), projectile sprites off
      `game/projs.tga` picked by each weapon's own `type`/`flags`, the ice
      block on a frozen creature and the fragments it sheds, and the shield
      ring while the powerup runs

- [x] The ground as it was authored: all ten `terrains.xml` operations
      (noise-scattered detail, Voronoi trail webs, roads and mech tracks,
      hand-placed landing pads), each chapter's own seed list so a quest
      always bakes its own layout, `quest_number_required` so a field gets
      visibly more fought-over as a chapter goes on, and the per-mode
      terrains — Rush's beach, Blitz's roads and landing pad — which every
      endless mode used to replace with chapter 1's grass

- [x] Feel and light: camera shake, a full-screen flash, blood that stays on
      the ground, and additive light pooling under muzzle flashes, blasts and
      energy bolts
- [x] A post pass on the finished frame (`src/engine/postfx.lua`): colour
      grading so a frozen field goes cold and Reflex Boost drains the world,
      bloom so the additive effects read as light, and a heat shimmer over
      explosions. The original engine shipped two shaders — a textured quad
      and an untextured one — so this is the one place the port deliberately
      goes past the 2014 build

- [x] Every shot reads as itself: spatter scaled to the damage that caused it,
      a per-family impact off each weapon's own `type`/`flags` (energy sparks
      in the colour of the bolt, the blade and the gauss family throwing a
      tight spray that carries), exit spatter streaked along the shot onto the
      ground behind the body, family-coloured ground marks, a hit flash, ice
      chips instead of blood on a frozen creature, and overkill that takes a
      creature apart instead of playing its death
- [x] The three powerups the original had and this port did not — Fireblast,
      Shock Chain, Fire Spinner — plus the announcement banner the pak ships
      the plate for, and brass only from the guns that have a case to eject

- [x] A second cartridge, `mods/allweapons/` — every chapter open and a weapon
      chosen off the gallery grid before each run, for testing a weapon in any
      map in seconds. It is a thin layer over `mods/vanilla/`, and the engine
      now gives every mod its own profile directory, so nothing it clears can
      touch the base game's progress or achievements

Next:

- [ ] Gamepad support (`joystick` is enabled but unused)
- [ ] `ai-player.xml` — shipped UI-navigation hints for the attract-mode and
      autotest AI, currently hand-written

## Rebuilding from scratch

```sh
brew install innoextract
# put Crimsonland.2014.rar in vendor/
make extract   # unpacks rar -> GOG installer -> paks -> vendor/assets*
make run       # launches with LÖVE (expects ~/Applications/love.app)
make test      # scripted autotest (SCENARIO=quest-smoke): ASCII captures to
               # the terminal plus PNG frames in LÖVE's save directory
```

Both take `MOD=<name>` to pick a cartridge from `mods/` (default `vanilla`):
`make run MOD=allweapons` opens every chapter and asks which weapon to start
with. Each mod keeps its own profile — progress, achievements, statistics and
settings — under `~/Library/Application Support/Crimsonland/mods/<name>/`, so
playing a debug cartridge cannot unlock anything in the base game.

Hand-written scenarios: `quest-smoke`, `quest-fast`, `quest-win` (an AI plays
chapter 1 quest 1 to the end, for the completed panel), `combat-smoke` (an AI
plays, so weapons/hits/drops are exercised), `survival-smoke`, `rush-smoke`,
`menus-smoke` (galleries + statistics), `options-smoke`, `fx-smoke`,
`emitter-smoke`, `editbox-smoke`, `perks-smoke`, `custom-smoke`,
`allweapons-smoke` and `allweapons-bolts` (need `MOD=allweapons`),
`terrain-smoke`, `gore-smoke`, `impact-smoke`, `traits-smoke`, plus the `td-*`
set (needs `MOD=towerdefence`).

Data invariants, which assert rather than only avoid crashing: `drop-table`
(every index a weapon drop can reach is a weapon a player can hold),
`creature-data` (the art table against the variant table, both ways),
`variant-colour` (the authored per-variant alpha), `june-2015-content` (the
three comps one feature flag gates), `attract-demos` (the menu backdrop runs
the five authored scenes), `mode-info` (the survival menu's mode panel).

Parameterised scenarios, which the sweeps below drive rather than being run
alone: `matrix` (`CL_WEAPON`, `CL_CREATURE`), `bake` and `bake-variety`
(`CL_CHAPTER`, `CL_QUEST`), `mode` and `mode-menu` (`CL_MODE`), `lethality` and
`weapon-details` (`CL_WEAPON`), `perk-details` (`CL_PERK`), `keep-display`
(`CL_ANSWER`).

A scenario fails on a stated claim, not only on a crash: a step may carry
`expect = function() return ok, why end`, and the run's exit code is the answer.
A Lua error prints a traceback and exits 1 rather than sitting on LÖVE's error
screen for ever, which is what makes a few hundred unattended runs possible.

Scenarios run on a fixed 1/60 clock as fast as the machine manages, not on
real time — a minimized LÖVE window is App-Nap throttled on macOS, which used
to make a 65-second scenario take minutes and look like a hang. They are also
reproducible: `love.math` is seeded, so two runs agree exactly.

A test run never opens a window at all (`conf.lua` creates it hidden under
`--autotest`), never makes a sound, and keeps its progress in its own
`~/Library/Application Support/Crimsonland-Test/` — so it can be left running
while the machine is used for something else. Captures still come out: the
canvas dumps and backbuffer screenshots land in LÖVE's own save directory.

### Sweeps

`tools/sweep.sh <axis> [jobs]` runs one axis of the matrix to exhaustion and
tabulates. An axis is a parameterised scenario crossed with a list read out of
`vendor/assets`, so the lists cannot drift from the data:

| axis | what it crosses | runs | wall time |
|--------------|----------------------------------------------|-----:|-----------|
| `modes`      | six endless modes, each against its own rule  |    6 | 5–10 s    |
| `modemenu`   | the same six, reached by clicking             |    6 | 5–15 s    |
| `keepdisplay`| keep / revert / time out the resolution dialog|    3 | ~7 s      |
| `variety`    | each chapter's ten grounds, hashed            |    7 | ~8 s      |
| `details`    | every weapon's detail screen                  |   30 | 40–50 s   |
| `lethality`  | every weapon against the first enemy          |   30 | ~40 s     |
| `named`      | every hand-written scenario                   |   33 | ~100 s    |
| `perkdetails`| every perk's detail screen                    |   56 | ~96 s     |
| `bake`       | 7 chapters × 10 quests of ground              |   70 | ~60 s     |
| `variants`   | all 102 creature variants                     |  102 | 65–120 s  |
| `matrix`     | 30 weapons × 12 creature types                |  360 | 4–6.5 min |
| `all`        | every axis above                              | ~700 | 12–13 min |

Times are at the default of 4 jobs on an M4 Pro. **The job count is a RAM
ceiling, not a CPU one**: each job is a whole LÖVE process that bakes its own
3071×1728 terrain canvases, which is what makes a sweep felt on the machine
running it. `tools/sweep.sh <axis> 1` does the same work one process at a time —
roughly four times the wall clock, and the laptop stays usable. Four is for when
you have stepped away.

A single scenario is nearly free: `make test SCENARIO=weapon-details` is one
process for about three seconds.

In-game controls: WASD/arrows move, mouse aims, LMB fires, R reloads,
Escape aborts the quest back to the menu.

## Layout

| Path                    | Contents                                           |
|-------------------------|----------------------------------------------------|
| `main.lua`, `conf.lua`  | LÖVE entry point (game only)                       |
| `src/engine/`           | Reimplemented 10tons engine runtime (screens, comps, NX_* API) |
| `mods/vanilla/`         | The game as a mod: descriptor, `game/` (quests, creatures, weapons, UI screens) and `fxs/` (the port's own particle effects) |
| `mods/allweapons/`      | Debug cartridge: everything unlocked, weapon picked before each run |
| `src/test/`             | Autotest harness + scripted scenarios (loaded only with `--autotest`) |
| `tools/`                | `extract_pak.py` — PAK V11 extractor               |
| `vendor/`               | Original rar, installer, `extracted/`, `assets*/` (gitignored) |

## License

The code in this repository — the reimplemented engine (`src/engine/`), the game
as a mod (`mods/`), the autotest harness (`src/test/`), the PAK extractor
(`tools/`) and the LÖVE entry points — is **GPL-3.0-or-later**. See [LICENSE](LICENSE).

**Mod linking exception.** Mods under `mods/` that are not derived from this
program's source and that talk to the engine only through the contract in
`src/engine/mod.lua` may be licensed however their authors like. Changes to the
engine itself stay under the GPL. The exact wording is at the top of `LICENSE`.

## Legal note

The game is not mine and is not here. Every bitmap, sound, music track, font,
XML data file, original Lua script and executable string belongs to **10tons Ltd**;
this repo ships none of them (`vendor/` and `extracted/` are gitignored) and reads
them at runtime from your own installation. You need a legitimate copy of the 2014
remaster to run any of this — it is an interoperability port, not a redistribution.

"Crimsonland" is a trademark of 10tons Ltd. This project is unofficial and is not
affiliated with or endorsed by them.
