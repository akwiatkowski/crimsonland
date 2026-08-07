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
- [x] First playable gameplay: quest mode on the original XML data
      (terrain baking, creature spawning/AI, weapons, `.bms` animations, HUD)

Next:

- [ ] Perk picking on level-up (currently a small heal)
- [ ] Powerups, particle FX (`fxs/` DSL is parsed but not drawn)
- [ ] Survival mode; real quest definitions (kill-count table is an approximation —
      original quest setups were compiled into `prog.dll`, only `custom-quests/` ships as XML)
- [ ] Persistence: profiles, unlocks, high scores (`DM_*` database API)

## Rebuilding from scratch

```sh
brew install innoextract
# put Crimsonland.2014.rar in vendor/
make extract   # unpacks rar -> GOG installer -> paks -> vendor/assets*
make run       # launches with LÖVE (expects ~/Applications/love.app)
```

## Layout

| Path                    | Contents                                           |
|-------------------------|----------------------------------------------------|
| `main.lua`, `conf.lua`  | LÖVE entry point (+ headless ASCII debug harness)  |
| `src/engine/`           | Reimplemented 10tons engine runtime (screens, comps, NX_* API) |
| `src/game/`             | Gameplay reimplementation (quests, creatures, weapons) |
| `tools/`                | `extract_pak.py` — PAK V11 extractor               |
| `vendor/`               | Original rar, installer, `extracted/`, `assets*/` (gitignored) |

## Legal note

Assets/scripts are copyrighted by 10tons. This project is a personal interoperability
port for a legitimately owned GOG copy — do not redistribute the `assets*/` or
`extracted/` directories (they are gitignored).
