# AGENTS.md — Crimsonland macOS port

<!-- Context for coding agents. Read this first when resuming work. -->

## Goal

Native macOS (Apple Silicon) port of Crimsonland 2014 (GOG build 2.2.0.4, game
version 1.2.3.0 per `prog.xml`) by running the **original Lua scripts + assets**
on a **reimplemented engine runtime**. Not a decompilation of x86 machine code —
the game logic is plaintext Lua, so we reimplement the engine's Lua API.

## Environment

- macOS, Apple Silicon (M4 Pro). Tool versions via `mise` — run project commands
  as `mise exec -- <cmd>`, never bare cargo/trunk/etc.
- `innoextract` installed via Homebrew (used once for the GOG installer).
- Original data lives under `vendor/` (gitignored, reproducible via
  `make extract`): rar, installer, `extracted/`, `assets*/`.

## Key facts discovered (do not rediscover)

### Binaries
- `vendor/extracted/app/Crimsonland.exe` — 2.9 MB PE32 (x86) launcher/engine shell
- `vendor/extracted/app/prog.dll` — 1.3 MB PE32, the actual engine + embedded **Lua 5.1**
- `vendor/extracted/app/prog.xml` — app config: `reference_resolution="960x640"`,
  `fps_limit="152"`, features `ACHIEVEMENTS,LEADERBOARDS`,
  control interfaces GAMEPAD,MOUSE,TOUCH,KEYBOARD

### PAK V11 archive format (spec in `tools/extract_pak.py` docstring)
`"PAK\0V11\0"` + u32 dir_offset + u32 total_size, then raw concatenated file data;
directory at dir_offset: u16 count, entries of `name\0 + u32 offset + u32 size +
8 bytes extra` (constant `ff26e25020000000` everywhere — likely hash + flags).
Files inside are verbatim PNG / Ogg / XML / Lua — no per-file compression.

### Extracted assets
- `vendor/assets/` — 4157 files from data.pak: 123 plaintext **Lua 5.1** scripts
  (~11,310 lines), XML configs (`creatures/`, `weapons/`, `perks/`, `chapters.xml`,
  `game-modes/`, `fxs/`, `ui/` with most Lua), PNG art, shaders
— `vendor/assets-1080p/` — 3119 hi-res variants
- `vendor/assets-music/` — 8 OGG 44.1kHz, `vendor/assets-sfx/` — 105 OGG
- Scripts use custom include: `LuaInclude("ui/common-ui-funcs.lua")`

### MEG_Font_v6 (.mft) bitmap fonts — decoded (full spec in `src/engine/mft.lua`)
Header + 256 fixed 271-byte glyph records in codepoint order, each followed by
its inline RGBA8 pixels (white, coverage in alpha). The record carries y-offset,
advance and a 256-entry int8 kerning row (A/V = -4). Parsing all three fonts
consumes each file to its exact last byte — that is the proof the layout is right.
- Encoding is **LATIN-1**, so UTF-8 source strings must be folded back
  (`·` would otherwise print as `Â·`); the fonts have no middle dot at all.
- `fonts/ammo.mft` is a 7-segment display: `0`-`9` are lit digits that already
  include their dark unlit plate, `a`-`j` a second inverted set, and there is
  **no `/`** — the magazine size has to be drawn in another font.

### Resolution / retina (measured, LÖVE 11.5)
- The 1080p pak is the *same* art at exactly **1080/640 = 1.6875x** (verified
  across the set: 90px -> 151px, 13x23 -> 21x38). Drop-in via per-image dpiscale.
- LÖVE 11.5 semantics that make the whole port resolution-independent for free:
  - `newImage(f, {dpiscale=d})` — `getWidth()` and plain `draw()` stay in
    reference units (±1px rounding), only the texture is denser.
  - `newCanvas(w, h, {dpiscale=d})` — allocates `w*d x h*d` pixels but still
    accepts reference coordinates. This is why nothing above `compute_viewport`
    knows about resolution.
  - `newFont(size, hinting, d)` — identical metrics, glyphs rasterized at `d`.
  - **Quads are the exception**: they address raw texels and are drawn at their
    literal pixel size, ignoring dpiscale. Every quad site must go through
    `assets.quad()` (or divide by `seq.density` as `bms.draw` does).
- `t.window.highdpi = true` is required or macOS renders 1x and upscales the
  window itself; `love.graphics.getDimensions()` stays in *window units* either
  way (`getPixelDimensions()` is the pixel one), so mouse math is unaffected.

### Engine Lua API (61 NX_* functions, from `strings prog.dll`)
Rendering: `NX_LoadBitmap NX_GetBitmap NX_DrawBitmap NX_DrawBitmapS NX_DrawBitmapRS
NX_DrawBitmapMirroredRS NX_DrawBitmapAligned NX_DrawSubBitmap NX_CreateBitmap
NX_RefreshBitmap NX_ReleaseBitmap NX_IsBitmapReady NX_GetBitmapWidth/Height
NX_GetNumBitmapFrames NX_SetBitmapFrame NX_SetBitmapCacheMode NX_ClearScreen
NX_DrawLine NX_DrawRect NX_SetBlend NX_BLEND_ADDITIVE NX_SetAlpha NX_SetColor
NX_SetPixelFilter NX_Push/PopScissorRectangle NX_Push/PopTransform
NX_PushTransformRotation/Scale/Translation`
Text: `NX_GetFont NX_DrawText NX_GetTextWidth/Height NX_GetFontHeight
NX_SetTextAlign NX_SetTextboxWidth NX_SetTextTransform`
Audio: `NX_LoadSound NX_GetSound NX_PlaySound NX_ReleaseSound NX_SetSoundParm
NX_SetChannelFrequency/Looping/Paused NX_SlideChannelVolume NX_SlideMusicVolume
NX_StopChannel NX_AllowMusic`
Input/misc: `NX_GetKeyState NX_GetKeyStateFloat NX_SetKeyState NX_SetKeyStateFloat
NX_SetCursor NX_GetInterface NX_GetTime NX_FileExists NX_Popup NX_CallExtension`

### NOT yet mapped (next session's job)
- The API surface **beyond NX_***: game-object functions the scripts call
  (grep scripts for all global function calls and cross-reference with prog.dll
  strings) — creatures, weapons, player, UI framework, save DB (`DM_SaveDatabase`),
  achievements/leaderboards hooks
- Script bootstrap order / entry point (look at `vendor/assets/loader/`, `events.lua`
  references in prog.dll strings, `index.xml`, `timeline.xml`)

## Port plan

1. Inventory the full Lua API (NX_* + game objects) the scripts actually use.
2. Implement a runtime on **LÖVE 11.x** (LuaJIT = Lua 5.1 compatible) — love2d's
   image/audio/draw API maps closely onto NX_*. Add `LuaInclude` shim.
3. Milestones: main menu renders ✓ → menu navigation ✓ → gameplay loop ✓
   (first playable quest mode in `src/game/`) → polish (perks, powerups, FX,
   survival mode, persistence; achievements/leaderboards are stubbed/optional).

## Mod architecture (engine = console, mod = cartridge)

- The engine never requires game code directly: all coupling goes through
  `src/engine/mod.lua` — a mod descriptor (`mods/<name>/init.lua`) provides
  `game` hooks (update/draw/pause/unpause/to_main_menu/on_ui_click), `save`
  (load/flush), and optional `paths` overrides for total conversions.
- Selected with `--mod=<name>` (`make run MOD=<name>`), default `vanilla`.
- `mods/vanilla/` is the clean-room Crimsonland; its implementation still
  lives in `src/game/` (predates the architecture — physically moving it is
  fine in a quiet window, only the descriptor's requires change).
- ORDERING: `mod.select()` runs before `src.engine` loads, because engine
  modules capture asset roots from `src.engine.paths` at require time and
  path overrides mutate that table in place.

## Gameplay layer (src/game/)

- `data.lua` — loads original XML datasets (weapons, creatures, variants,
  terrains, chapters) into Lua tables
- `bms.lua` — parser for the 10tons `NX_Bm_Seq_v1` animation format
  (frame table + packed PNG atlas). Uses `love.data.unpack` (NOT string.unpack —
  LuaJIT is Lua 5.1)
- `play.lua` — quest + survival modes: terrain baking from terrains.xml ops,
  creature spawn/AI/contact damage, weapon firing from weapons.xml stats
  (damage derived from stat_damage — see data.lua), drops, XP/levels/perks,
  outcome → original end screens. Hooked into the engine via the
  GameCrimsonland internal screen (update/draw) and unhandled UI clicks
  (screens.lua routes them to `game.on_ui_click`). Gameplay pauses whenever
  any UI screen overlays GameCrimsonland
- `perks.lua` — clean-room classic perk set as game.mods multipliers;
  PickAPerk comps are filled from the game layer (C++ did this originally)
- `particles.lua` — hand-rolled FX layer (NOT the fxs/ DSL — still open)
- `hud.lua` — in-game HUD from the original 2014 art (game/health_pie_*,
  aim_circle/dot crosshair with reload sweep, progress-bar XP strip,
  levelup-ring, white-vignette low-hp breathing); bone/blood/brass/toxic
  palette; fonts via engine font module (small/medium/ammo.mft)
- `save.lua` — platform state + progress to LÖVE save dir (identity
  crimsonland-mac), sandboxed load, flushed on quit/outcomes
- Quest kill-count/spawn tables are approximations — original quest defs were
  compiled into prog.dll; only `custom-quests/` ships as XML

## Test harness (src/test/)

- Loaded ONLY via `love . --autotest[=scenario]` (`make test SCENARIO=...`);
  `make run` never touches test code — main.lua's arg check is the sole gate
- `harness.lua` drives the game like a player (synthesized screens.mousepressed/
  keypressed, read-only state captures) — do not mutate game internals from it
- `scenarios/*.lua` are pure data: timed `{t, click=|key=}` steps + `captures`
  time list. New test = new scenario file, no harness/game edits
- Output: screen stack, game state line, clickable rects, ASCII canvas render —
  all teed to /tmp/crimsonland_port.log

## Conventions

- Large binaries stay out of git: everything under `vendor/` is ignored and
  reproducible via `make extract` (see README).
- Conventional commits; minimal diffs; keep this file and README status sections
  current when facts change.
- Do NOT redistribute copyrighted assets; treat this as a personal interop port.
