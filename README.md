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

Scenarios: `quest-smoke`, `quest-fast`, `combat-smoke` (an AI plays, so
weapons/hits/drops are exercised), `survival-smoke`, `rush-smoke`,
`menus-smoke` (galleries + statistics), `options-smoke`, `fx-smoke`,
`emitter-smoke`, `editbox-smoke`, `perks-smoke`, `custom-smoke`.

Scenarios run on a fixed 1/60 clock as fast as the machine manages, not on
real time — a minimized LÖVE window is App-Nap throttled on macOS, which used
to make a 65-second scenario take minutes and look like a hang. They are also
reproducible: `love.math` is seeded, so two runs agree exactly.

In-game controls: WASD/arrows move, mouse aims, LMB fires, R reloads,
Escape aborts the quest back to the menu.

## Layout

| Path                    | Contents                                           |
|-------------------------|----------------------------------------------------|
| `main.lua`, `conf.lua`  | LÖVE entry point (game only)                       |
| `src/engine/`           | Reimplemented 10tons engine runtime (screens, comps, NX_* API) |
| `mods/vanilla/`         | The game as a mod: descriptor, `game/` (quests, creatures, weapons, UI screens) and `fxs/` (the port's own particle effects) |
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
