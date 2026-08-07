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

Next:

- [ ] Find the game entry point / script bootstrap order (`events.lua`, `loader/`)
- [ ] Enumerate the full Lua API surface beyond `NX_*` (game objects: creatures,
      weapons, players — check what globals/scripts expect)
- [ ] Build a minimal LÖVE runtime implementing `NX_*` + `LuaInclude`
- [ ] Get the main menu rendering, then gameplay

## Rebuilding from scratch

```sh
brew install innoextract
bsdtar -xf Crimsonland.2014.rar
mkdir extracted && innoextract -d extracted setup_crimsonland_2.2.0.4.exe
python3 tools/extract_pak.py extracted/app/data.pak assets
python3 tools/extract_pak.py extracted/app/data-1080p.pak assets-1080p
python3 tools/extract_pak.py extracted/app/data-music-OGG_44100.pak assets-music
python3 tools/extract_pak.py extracted/app/data-sfx-OGG_44100.pak assets-sfx
```

## Layout

| Path              | Contents                                            |
|-------------------|-----------------------------------------------------|
| `extracted/app/`  | Raw GOG installer payload (Windows exe/dll + paks)  |
| `assets*/`        | Extracted game data (Lua, XML, PNG, OGG)            |
| `tools/`          | `extract_pak.py` — PAK V11 extractor                |

## Legal note

Assets/scripts are copyrighted by 10tons. This project is a personal interoperability
port for a legitimately owned GOG copy — do not redistribute the `assets*/` or
`extracted/` directories (they are gitignored).
