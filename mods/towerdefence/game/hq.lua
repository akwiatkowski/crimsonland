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

--- Price under every plate, in the colour of what it means: owned, affordable,
-- out of reach. A shop where you cannot see what you cannot afford is a shop
-- that makes the decision for you.
local function draw_armoury(screen)
	if not field then return end
	for _, comp in ipairs(screen.comps) do
		local i = gallery.slot_index(comp, "Weapon")
		local entry = i and gallery.entry_at("weapon", i)
		local price = entry and prices.weapon(entry)
		if price then
			local x, y, w, h = comps.screen_rect(comp)
			local held = field.player.weapon and field.player.weapon.id == entry.id
			local owned = field.owned[entry.id]
			local label, colour
			if mount_target and not plots.accepts(mount_target, entry) then
				-- a light mount cannot take a cannon, and finding that out
				-- after paying for it would be the shop lying
				label, colour = "TOO HEAVY", BLOOD
			elseif held then
				label, colour = "IN HAND", TOXIC
			elseif owned then
				label, colour = "OWNED", BONE
			else
				label = ("$%d"):format(price)
				colour = (field.money >= price) and BRASS or DIM
			end
			-- inside the plate, not under it: the grid's bottom row sits on the
			-- Back button, and a price drawn in that gap lands on top of it
			font.draw(F_SMALL, label, x + 6, y + h - 20, colour)
		end
	end

	-- what there is to spend, beside the title. The grid says the rest: a price
	-- you can pay is brass, one you cannot is grey, and what you already have
	-- says so instead of costing anything.
	local panel = screen.compmap.panel
	if panel then
		local px, py, pw = comps.screen_rect(panel)
		local money = ("$%d"):format(field.money)
		font.draw(F_MEDIUM, money, px + pw - font.measure(F_MEDIUM, money) - 40,
			py + 44, BRASS)
	end
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
		if title then comps.set(title, "textbox.text", { "Armoury" }) end
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
