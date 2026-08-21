-- The HQ: the only place money turns into anything.
--
-- Two screens, and neither of them ships in the pak:
--
--   TDHeadquarters  built from real comps through the engine's own
--                   register_internal seam — the same door GamePause uses, so
--                   hit-testing, hover sounds and transitions are the
--                   framework's rather than something drawn by hand.
--   Weapons         the pak's Extras weapon gallery, reused as the armoury.
--                   Thirty plates already carrying the right icons, already
--                   laid out; the shop only has to write prices under them.
--                   Building a second grid that looked worse was the only
--                   alternative (mods/allweapons does the same for its picker).
--
-- Why the HQ is a place and not a menu key: it sits at the centre of the map,
-- so re-arming means leaving the perimeter, and the lull between waves is the
-- window that makes that affordable. Spending is a decision about position as
-- much as money.

local comps = require("src.engine.comps")
local font = require("src.engine.font")
local gallery = require("mods.vanilla.game.gallery")
local save = require("mods.vanilla.game.save")
local screens = require("src.engine.screens")
local cards = require("mods.towerdefence.game.cards")
local plots = require("mods.towerdefence.game.plots")
local prices = require("mods.towerdefence.game.prices")

local hq = {}

local HQ_SCREEN = "TDHeadquarters"
local MOUNT_SCREEN = "TDMount"
local ARMOURY = "Weapons"
-- the original's own card screen, six plates and a pair of textboxes that
-- follow the pointer. Bought here rather than earned on a level-up.
local CARDS = "PickAPerk"

-- The plot the armoury was opened for, if it was opened from one. With it set,
-- clicking a weapon bolts it on (buying it first if you do not own it yet);
-- without it, the armoury is the shop it was in slice two. One screen, because
-- the question it answers — "which weapon?" — is the same question.
local mount_target = nil

local BONE = { 0.91, 0.89, 0.84 }
local BRASS = { 0.79, 0.64, 0.29 }
local BLOOD = { 0.70, 0.13, 0.16 }
local TOXIC = { 0.50, 0.73, 0.31 }
local DIM = { 0.45, 0.44, 0.42 }

local F_SMALL = "fonts/small.mft"
local F_MEDIUM = "fonts/medium.mft"

-- the field, injected on open so this module never requires the game back
local field

-- ------------------------------------------------------------ the HQ screen

local function add(screen, ctype, name, template, x, y)
	local c = comps.new(ctype, name, screen)
	c._order = #screen.comps + 1
	table.insert(screen.comps, c)
	screen.compmap[name] = c
	if template then comps.set(c, "inherit", { template }) end
	comps.set(c, "position", { x, y })
	comps.set(c, "align", { "CENTER" })
	return c
end

--- Label for the repair button, which has to say the whole decision: what it
-- buys and what it costs, because the alternative is a weapon.
local function repair_label()
	local missing = field.base.max_hp - field.base.hp
	if missing <= 0 then return "Base at full strength" end
	return ("Repair %d  -  $%d"):format(math.floor(missing), prices.repair(missing))
end

screens.register_internal(HQ_SCREEN, function(screen)
	add(screen, "Image", "panel", "PanelMedium", 0.5, 0.5)
	-- 0.20 leaves the band under the title for the three lines draw_hq writes
	-- there; the panel is 858x571 centred, so it runs y=34..605 and the
	-- buttons below start at 0.44
	local title = add(screen, "Textbox", "Title", "LargeTextbox", 0.5, 0.20)
	comps.set(title, "textbox.text", { "HEADQUARTERS" })
	comps.set(title, "align", { "HCENTER" })

	local repair = add(screen, "Button", "Repair", "WideButton", 0.5, 0.44)
	comps.set(repair, "button.text", { repair_label() })
	local armoury = add(screen, "Button", "Armoury", "WideButton", 0.5, 0.55)
	comps.set(armoury, "button.text", { "Armoury" })
	local training = add(screen, "Button", "Cards", "WideButton", 0.5, 0.66)
	comps.set(training, "button.text",
		{ ("Training  -  $%d"):format(cards.cost(field and field.cards_taken or 0)) })
	local close = add(screen, "Button", "Close", "WideButton", 0.5, 0.77)
	comps.set(close, "button.text", { "Back to the field" })

	screen.env.OnKeyDown = function(key)
		if key == "ESCAPE" or key == "E" then hq.close() end
	end
	screen.env.OnDraw = function() end
end)

--- The money line and what the base is worth repairing, drawn over the panel.
-- The layout has no textbox for either, and inventing comps for text that
-- changes every frame is more machinery than drawing it.
local function draw_hq(screen)
	local panel = screen.compmap.panel
	if not panel or not field then return end
	local px, py, pw = comps.screen_rect(panel)
	local function line(f, text, y, colour)
		font.draw(f, text, px + (pw - font.measure(f, text)) / 2, y, colour)
	end

	line(F_MEDIUM, ("$%d"):format(field.money), py + 120, BRASS)

	local k = field.base.hp / field.base.max_hp
	line(F_SMALL, ("Base %d / %d"):format(math.floor(field.base.hp), field.base.max_hp),
		py + 155, k < 0.5 and BLOOD or BONE)

	-- Whether the wave is still out there is the whole cost of standing here:
	-- the HQ is at the centre, so shopping mid-wave means nothing is holding
	-- the perimeter while you read prices.
	if field.lull > 0 then
		line(F_SMALL, ("Wave %d arrives in %ds"):format(field.wave, math.ceil(field.lull)),
			py + 180, TOXIC)
	else
		line(F_SMALL, "The wave is still out there", py + 180, BLOOD)
	end
end

-- ------------------------------------------------------------- the mount

--- What the plot the player is standing on can be asked, in the order the
-- money goes: build it, arm it, reinforce it, strip it.
local function mount_labels(plot)
	local out = {}
	if not plot.built then
		local cost, why = plots.build_cost(field, plot)
		out[#out + 1] = { name = "Build",
			text = cost and ("Build mount  -  $%d"):format(cost) or why }
		return out
	end
	out[#out + 1] = {
		name = "Arm",
		text = plot.weapon and ("Change weapon  (%s)"):format(plot.weapon.name or plot.weapon.id)
			or "Bolt a weapon on",
	}
	if plot.tier < 2 then
		out[#out + 1] = { name = "Upgrade",
			text = ("Reinforce mount  -  $%d"):format(plots.UPGRADE_COST) }
	end
	if plot.weapon then
		out[#out + 1] = { name = "Strip", text = "Take the weapon back" }
	end
	return out
end

screens.register_internal(MOUNT_SCREEN, function(screen)
	add(screen, "Image", "panel", "PanelSmall", 0.5, 0.5)
	local title = add(screen, "Textbox", "Title", "LargeTextbox", 0.5, 0.30)
	comps.set(title, "textbox.text", { "MOUNT" })
	comps.set(title, "align", { "HCENTER" })

	-- The buttons are built from the plot's own state at push time, which is
	-- why this screen is pushed fresh rather than kept: a mount that has just
	-- been built is a different set of choices from the plot it was.
	local y = 0.45
	for _, item in ipairs(mount_labels(hq.plot or {})) do
		local b = add(screen, "Button", item.name, "WideButton", 0.5, y)
		comps.set(b, "button.text", { item.text })
		y = y + 0.10
	end
	local back = add(screen, "Button", "Leave", "WideButton", 0.5, y + 0.02)
	comps.set(back, "button.text", { "Leave it" })

	screen.env.OnKeyDown = function(key)
		if key == "ESCAPE" or key == "E" then screens.pop(MOUNT_SCREEN) end
	end
	screen.env.OnDraw = function() end
end)

--- The mount's own state, under the title: what it holds and what it covers.
local function draw_mount_screen(screen)
	local panel = screen.compmap.panel
	local plot = hq.plot
	if not panel or not plot or not field then return end
	local px, py, pw = comps.screen_rect(panel)
	local function line(f, text, y, colour)
		font.draw(f, text, px + (pw - font.measure(f, text)) / 2, y, colour)
	end
	line(F_MEDIUM, ("$%d"):format(field.money), py + 74, BRASS)
	if not plot.built then
		line(F_SMALL, plot.outer and "Bare ground, on the outer ring"
			or "Bare ground on the perimeter", py + 108, DIM)
	elseif plot.weapon then
		line(F_SMALL, ("%s  -  reach %d"):format(plot.weapon.name or plot.weapon.id,
			math.floor(plots.range(plot))), py + 108, BONE)
		-- what it has actually done, which is the only honest answer to
		-- whether it was worth what it cost
		line(F_SMALL, ("%s  -  %d kills"):format(
			plot.tier >= 2 and "Reinforced mount" or "Light mount", plot.kills or 0),
			py + 130, plot.tier >= 2 and TOXIC or DIM)
	else
		line(F_SMALL, plot.tier >= 2 and "Reinforced mount, empty"
			or "Light mount, empty", py + 108, DIM)
	end
end

-- ---------------------------------------------------------------- the cards

--- The original's card screen, filled with the offer the field paid for. Its
-- six plates carry icons only; the name and description belong to the pair of
-- textboxes that follow the pointer, which is how the layout was drawn.
local function set_card_desc(screen, perk)
	if screen.compmap.PerkName then
		comps.set(screen.compmap.PerkName, "textbox.text", { perk.name })
	end
	if screen.compmap.PerkDesc then
		comps.set(screen.compmap.PerkDesc, "textbox.text", { perk.desc })
	end
end

local function fill_cards(screen)
	local offer = field and field.card_offer
	if not offer then return end
	if screen.compmap.Title then
		comps.set(screen.compmap.Title, "textbox.text",
			{ ("Training  -  $%d spent"):format(field.card_paid or 0) })
	end
	for i = 1, 6 do
		local b = screen.compmap["PerkButton_" .. i]
		if b then
			comps.set(b, "visible", { offer[i] ~= nil })
			if offer[i] then comps.set(b, "button.bm_icon", { offer[i].icon }) end
		end
	end
	if offer[1] then set_card_desc(screen, offer[1]) end
end

--- Hovering a plate previews what it does, which is the only way to choose.
local function update_card_hover(screen)
	local hover = screen._hover_comp
	local n = hover and hover.name:match("^PerkButton_(%d+)$")
	local perk = n and field and field.card_offer and field.card_offer[tonumber(n)]
	if perk then set_card_desc(screen, perk) end
end

-- -------------------------------------------------------------- the armoury

--- Every weapon shows its own art in a shop: the gallery's locked plates mean
-- "not found yet", which is a progression this mod does not have. Marking them
-- seen in this mod's own profile is cheaper than teaching the gallery a second
-- mode (mods/allweapons does the same).
local function mark_all_seen()
	local data = require("mods.vanilla.game.data")
	data.load_all()
	for _, w in pairs(data.weapon_order) do
		if w.id ~= nil then save.game.seen.weapons[w.id] = true end
	end
end

-- The shop's own ink, for the veil over what is out of reach and for the
-- payment bar's track. Darker than the panel, so a veiled plate reads as
-- switched off rather than merely tinted.
local INK = { 0.02, 0.02, 0.03 }

-- How hard each refusal reads. Both are set so the gun underneath is still
-- recognisable -- thirty pieces of weapon art are the best thing on this
-- screen and blacking most of them out was worse than the mess it replaced.
-- Not affording something is a maybe, and the money is coming; a mount that
-- cannot carry the weapon is a no for as long as that mount stands.
local VEIL_SHORT = 0.5
local VEIL_REFUSED = 0.72

--- Everything the shop has to say about one weapon, as a single state. The
-- plate draws it and the line under the title spells it out, so the two can
-- never disagree about what is on offer.
local function verdict(entry, price)
	-- a light mount cannot take a cannon, and finding that out after paying
	-- for it would be the shop lying
	if mount_target and not plots.accepts(mount_target, entry) then return "refused" end
	if field.player.weapon and field.player.weapon.id == entry.id then return "held" end
	if field.owned[entry.id] then return "owned" end
	if field.money >= price then return "afford" end
	return "short"
end

local function fill(x, y, w, h, c, a)
	love.graphics.setColor(c[1], c[2], c[3], a or 1)
	love.graphics.rectangle("fill", x, y, w, h)
end

local function outline(x, y, w, h, c)
	love.graphics.setColor(c[1], c[2], c[3], 1)
	love.graphics.setLineWidth(2)
	love.graphics.rectangle("line", x + 1, y + 1, w - 2, h - 2)
	love.graphics.setLineWidth(1)
end

-- The payment bar lives in the plate's bottom margin. The art is 77x38 inside
-- a 103x50 plate, so those few pixels are the only ones on it that are neither
-- border nor gun.
local BAR_INSET = 9
local BAR_HEIGHT = 3

--- A plate, saying what it costs without writing a number on the gun.
--
-- There is no room for one that would not sit on the art -- which is what this
-- shop did before, and why thirty pieces of weapon art read as vandalised. So
-- the plate answers in light instead: a veil over what is out of reach, and a
-- bar filled with the fraction of the price the money on hand covers. A full
-- bar means take it, a half-full one means one more wave. The exact number is
-- one hover away, under the title. Returns the state it drew.
local function draw_plate(comp, entry, price)
	local x, y, w, h = comps.screen_rect(comp)
	local state = verdict(entry, price)

	-- the pointer is a torch: whatever it rests on comes out from under the
	-- veil, so you are never reading the line under the title about a weapon
	-- you cannot see
	if not comp.hover then
		if state == "short" then
			fill(x, y, w, h, INK, VEIL_SHORT)
		elseif state == "refused" then
			fill(x, y, w, h, INK, VEIL_REFUSED)
		end
	end

	if state ~= "refused" then
		local bx, by, bw = x + BAR_INSET, y + h - BAR_HEIGHT - 3, w - BAR_INSET * 2
		if state == "held" or state == "owned" then
			-- nothing left to pay: a full bar, in the colour of what it is
			fill(bx, by, bw, BAR_HEIGHT, state == "held" and TOXIC or BONE, 0.9)
		else
			fill(bx, by, bw, BAR_HEIGHT, INK, 0.85)
			fill(bx, by, bw * math.min(1, field.money / price), BAR_HEIGHT,
				state == "afford" and BRASS or DIM)
		end
	end

	-- A refusal and a gun already in your hands are facts about the run and
	-- outrank the pointer, which is only ever passing through; hover marks the
	-- plates that have nothing else to say.
	local frame = (state == "refused" and BLOOD) or (state == "held" and TOXIC)
		or (comp.hover and BRASS)
	if frame then outline(x, y, w, h, frame) end
	return state
end

--- The engine's inline colour markup (src/engine/font.lua), so one measured
-- line can carry several colours.
local function tag(c)
	return ("|#%02x%02x%02x|"):format(
		math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

--- The line under the title: what the pointer is on. Sustained dps rather than
-- the damage number, because that is what the price was computed from
-- (game/prices) -- the shop quotes the same figure it charges for.
local function dossier(entry, price)
	if not entry then
		if mount_target then
			return tag(DIM) .. (mount_target.tier >= 2 and "Reinforced mount"
				or "Light mount") .. "  -  point at a weapon to bolt it on"
		end
		return tag(DIM) .. "Point at a weapon to read it"
	end
	local state = verdict(entry, price)
	local tail
	if state == "refused" then tail = tag(BLOOD) .. "too heavy for this mount"
	elseif state == "held" then tail = tag(TOXIC) .. "in hand"
	elseif state == "owned" then tail = tag(BONE) .. "owned"
	else tail = tag(state == "afford" and BRASS or DIM) .. ("$%d"):format(price)
	end
	return ("%s%s   %s%.0f dps  -  clip %d  -  %.1fs reload   %s"):format(
		tag(BONE), entry.name or entry.id, tag(DIM), prices.dps(entry),
		entry.clip_size or 0, entry.reload_time or 0, tail)
end

--- What taking it would leave, under the money itself -- the one question a
-- price tag cannot answer on its own.
local function balance(entry, price)
	if not entry then return nil end
	local state = verdict(entry, price)
	if state == "afford" then
		return ("leaves $%d"):format(field.money - price), BRASS
	elseif state == "short" then
		return ("short $%d"):format(price - field.money), BLOOD
	end
	return nil
end

--- The grid, and the three things the plates cannot say: what the pointer is
-- on, what the money reaches, and that the wave does not stop for a shop.
local function draw_armoury(screen)
	if not field then return end
	local hovered, hovered_price, reach, total = nil, nil, 0, 0

	for _, comp in ipairs(screen.comps) do
		local i = gallery.slot_index(comp, "Weapon")
		local entry = i and gallery.entry_at("weapon", i)
		local price = entry and prices.weapon(entry)
		if price then
			-- what the count says and what the veil shows are the same fact,
			-- so they are read off the same state
			local state = draw_plate(comp, entry, price)
			total = total + 1
			if state ~= "short" and state ~= "refused" then reach = reach + 1 end
			if comp.hover then hovered, hovered_price = entry, price end
		end
	end
	love.graphics.setColor(1, 1, 1, 1)

	local panel = screen.compmap.panel
	if not panel then return end
	local px, py, pw = comps.screen_rect(panel)
	local function right(f, text, y, colour)
		font.draw(f, text, px + pw - font.measure(f, text) - 46, y, colour)
	end

	local money = ("$%d"):format(field.money)
	right(F_MEDIUM, money, py + 44, BRASS)
	local left_over, left_colour = balance(hovered, hovered_price)
	if left_over then right(F_SMALL, left_over, py + 88, left_colour) end

	local line = dossier(hovered, hovered_price)
	font.draw(F_SMALL, line, px + (pw - font.measure(F_SMALL, line)) / 2, py + 96)

	-- Either side of the Back button, in the band the grid leaves free: what
	-- standing here costs, and how far the money goes. The HQ is at the centre
	-- of the map and the wave keeps coming while the shop is open, so the
	-- clock belongs on the counter (game/field).
	if field.lull > 0 then
		font.draw(F_SMALL, ("Wave %d arrives in %ds"):format(field.wave,
			math.ceil(field.lull)), px + 46, py + 485, TOXIC)
	else
		font.draw(F_SMALL, "The wave is still out there", px + 46, py + 485, BLOOD)
	end
	right(F_SMALL, ("%d of %d within reach"):format(reach, total), py + 485, DIM)
end

-- ------------------------------------------------------------------ opening

function hq.open(f)
	field = f
	mount_target = nil
	screens.push(HQ_SCREEN)
end

--- Open the mount screen for the plot the player is standing on. `hq.plot` is
-- read by the screen's builder, which runs inside this push.
function hq.open_mount(f, plot)
	field = f
	hq.plot = plot
	mount_target = nil
	screens.push(MOUNT_SCREEN)
end

--- Rebuild the mount screen after something changed what it can offer. Popping
-- and pushing is the cheap way to do it and the honest one: the choices really
-- are different now.
local function refresh_mount()
	local s = screens.find(MOUNT_SCREEN)
	if s then
		-- straight out of the stack, no transition: it is being replaced by
		-- itself and a fade would read as a flicker
		for i, scr in ipairs(screens.stack) do
			if scr == s then table.remove(screens.stack, i) break end
		end
	end
	screens.push(MOUNT_SCREEN)
end

function hq.close()
	screens.pop(HQ_SCREEN)
end

--- Shut every counter at once. Used when the field decides the player has
-- stopped being someone who can shop — being killed at the counter, mostly,
-- which is now possible because a shop no longer stops the wave.
function hq.close_all()
	for _, name in ipairs({ CARDS, ARMOURY, MOUNT_SCREEN, HQ_SCREEN }) do
		if screens.find(name) then screens.pop(name) end
	end
	mount_target = nil
end

function hq.is_open()
	return screens.find(HQ_SCREEN) ~= nil or screens.find(ARMOURY) ~= nil
		or screens.find(MOUNT_SCREEN) ~= nil
end

-- --------------------------------------------------------------- mod hooks

function hq.on_screen_enter(screen_name, screen)
	if screen_name == CARDS then
		fill_cards(screen)
	elseif screen_name == ARMOURY then
		mark_all_seen()
		gallery.fill(screen, "Weapon", "weapon")
		local title = screen.compmap.TimeTitle
		-- the same grid answers two questions, and the title says which one is
		-- being asked: what to buy, or what to bolt onto the mount out there
		if title then
			comps.set(title, "textbox.text",
				{ mount_target and "Arm the mount" or "Armoury" })
		end
	end
end

function hq.on_screen_draw(screen_name, screen)
	if screen_name == HQ_SCREEN then
		draw_hq(screen)
	elseif screen_name == MOUNT_SCREEN then
		draw_mount_screen(screen)
	elseif screen_name == ARMOURY then
		draw_armoury(screen)
	elseif screen_name == CARDS then
		update_card_hover(screen)
	end
end

--- Returns true when the click was the HQ's. `f` is the field, which owns the
-- money and is the only thing allowed to spend it.
function hq.on_ui_click(screen_name, comp_name, f)
	field = f
	if screen_name == HQ_SCREEN then
		if comp_name == "Repair" then
			field.repair()
			-- the button says the price, and the price just changed
			local screen = screens.find(HQ_SCREEN)
			local btn = screen and screen.compmap.Repair
			if btn then comps.set(btn, "button.text", { repair_label() }) end
		elseif comp_name == "Armoury" then
			screens.push(ARMOURY)
		elseif comp_name == "Cards" then
			-- paid for on opening, not on choosing: the offer is what the money
			-- buys, and walking away from three cards you dislike is a real
			-- (bad) outcome rather than a free look
			if field.buy_cards() then screens.push(CARDS) end
		elseif comp_name == "Close" then
			hq.close()
		end
		return true
	elseif screen_name == CARDS then
		local n = comp_name:match("^PerkButton_(%d+)$")
		local perk = n and field.card_offer and field.card_offer[tonumber(n)]
		if perk then
			field.take_card(perk)
			screens.pop(CARDS)
			-- the next card costs more, and the button says so
			local s = screens.find(HQ_SCREEN)
			local btn = s and s.compmap.Cards
			if btn then
				comps.set(btn, "button.text",
					{ ("Training  -  $%d"):format(cards.cost(field.cards_taken)) })
			end
		end
		return true
	elseif screen_name == ARMOURY then
		if comp_name == "Back" then
			screens.pop(ARMOURY)
			mount_target = nil
			return true
		end
		local slot = comp_name:match("^Weapon_(%d+)$")
		local entry = slot and gallery.entry_at("weapon", tonumber(slot))
		if entry then
			if mount_target then
				-- opened from a plot: buying and bolting on are one act, so a
				-- weapon never sits in an inventory the player has to think about
				if field.mount_weapon(mount_target, entry) then
					screens.pop(ARMOURY)
					mount_target = nil
					refresh_mount()
				end
			else
				field.buy_weapon(entry)
			end
			return true
		end
	elseif screen_name == MOUNT_SCREEN then
		local plot = hq.plot
		if comp_name == "Build" then
			if field.buy_plot(plot) then refresh_mount() end
		elseif comp_name == "Arm" then
			mount_target = plot
			screens.push(ARMOURY)
		elseif comp_name == "Upgrade" then
			if field.upgrade_plot(plot) then refresh_mount() end
		elseif comp_name == "Strip" then
			field.strip_plot(plot)
			refresh_mount()
		elseif comp_name == "Leave" then
			screens.pop(MOUNT_SCREEN)
		end
		return true
	end
	return false
end

return hq
