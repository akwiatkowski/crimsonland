-- UI component model: property storage, layout/transform math, drawing,
-- hit testing. Replicates the 10tons Nexus UI semantics:
--
--  * SetProperty("prop", ...) targets the most recently created comp;
--    "Name:prop" targets a named comp; "/:prop" targets the screen itself.
--  * Comps form a tree via the "parent" property. Positions are normalized
--    to the PARENT's area (x * parent_width, y * parent_height).
--  * "align" picks the anchor point on both parent and comp
--    (LEFT/RIGHT/HCENTER x TOP/BOTTOM/VCENTER; CENTER = both).
--  * "inherit" copies properties from a template comp (ui/templates.lua).

local assets = require("src.engine.assets")
local font = require("src.engine.font")

local comps = {}

-- template registry: name -> props table (filled by ui/templates.lua)
comps.templates = {}

-- ------------------------------------------------------------------ props

local function shallow_copy(t)
	local n = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			local c = {}
			for i, x in ipairs(v) do c[i] = x end
			n[k] = c
		else
			n[k] = v
		end
	end
	return n
end

-- per-type hardcoded defaults (the engine's built-ins)
local function type_defaults(ctype)
	return {
		position = { 0, 0 },
		visible = true,
		active = true,
		scale = 1,
		angle = 0,
		["angle.x"] = 0,
		["angle.y"] = 0,
		["position.z"] = 0,
		["color.r"] = 1,
		["color.g"] = 1,
		["color.b"] = 1,
		["color.a"] = 1,
		blend_mode = "NORMAL",
		align = "TOPLEFT",
		inherit_scale = false,
		localize = true,
		expanded_hit_area = 0,
	}
end

function comps.new(ctype, name, screen)
	ctype = ctype:sub(1, 1):upper() .. ctype:sub(2):lower() -- "BUTTON" -> "Button"
	local comp = {
		type = ctype,
		name = name,
		screen = screen,
		props = type_defaults(ctype),
		children = {},
		parent = nil,
	}
	-- implicit Default<Type> template inheritance
	local def = comps.templates["Default" .. ctype]
	if def then
		for k, v in pairs(def) do
			if type(v) == "table" then
				local c = {}
				for i, x in ipairs(v) do c[i] = x end
				comp.props[k] = c
			else
				comp.props[k] = v
			end
		end
	end
	return comp
end

function comps.set(comp, key, values)
	if key == "inherit" then
		local tpl = comps.templates[values[1]]
		if tpl then
			for k, v in pairs(tpl) do
				if type(v) == "table" then
					local c = {}
					for i, x in ipairs(v) do c[i] = x end
					comp.props[k] = c
				else
					comp.props[k] = v
				end
			end
		else
			print(("[comps] unknown inherit template '%s'"):format(tostring(values[1])))
		end
		return
	end
	if key == "parent" then
		comp.parent_name = values[1] -- resolved by screen
	end
	if #values > 1 then
		local arr = {}
		for i, v in ipairs(values) do arr[i] = v end
		comp.props[key] = arr
	else
		comp.props[key] = values[1]
	end
end

function comps.get(comp, key)
	local v = comp.props[key]
	if key == "visible" or key == "active" then
		return v == true or v == 1
	end
	return v
end

-- numeric scalar prop with default
local function num(comp, key, default)
	local v = comp.props[key]
	if type(v) == "number" then return v end
	return default or 0
end
comps.num = num

-- position component (handles both {x,y} arrays and scalar .x/.y keys)
local function pos2(comp, key)
	local v = comp.props[key]
	if type(v) == "table" then return v[1] or 0, v[2] or 0 end
	return num(comp, key .. ".x", 0), num(comp, key .. ".y", 0)
end
comps.pos2 = pos2

local function color4(comp)
	local a = num(comp, "alpha", nil) -- events write "alpha" directly
	if comp.props["alpha"] == nil then a = num(comp, "color.a", 1) end
	return num(comp, "color.r", 1), num(comp, "color.g", 1), num(comp, "color.b", 1), a
end
comps.color4 = color4

-- ------------------------------------------------------------------- area

function comps.area(comp)
	local p = comp.props
	local t = comp.type
	if t == "Marker" then
		return num(comp, "marker.area_width", 0), num(comp, "marker.area_height", 0)
	elseif t == "Aligner" then
		return num(comp, "aligner.area_width", 0), num(comp, "aligner.area_height", 0)
	elseif t == "Image" then
		local img = assets.image(p["image.bitmap"])
		if img then return img:getWidth(), img:getHeight() end
		return 0, 0
	elseif t == "Button" then
		local img = assets.image(p["button.bm_idle"])
		if img then return img:getWidth(), img:getHeight() end
		local text = p["button.text"] or ""
		local fnt = p["button.font"]
		return font.measure(fnt, tostring(text))
	elseif t == "Textbox" then
		local text = p["textbox.text"] or ""
		return font.measure(p["textbox.font"], tostring(text))
	elseif t == "Rectangle" then
		return num(comp, "rectangle.rect_width", 0), num(comp, "rectangle.rect_height", 0)
	elseif t == "NinePatch" then
		local cs = p["ninepatch.client_size"]
		if type(cs) == "table" then return cs[1] or 0, cs[2] or 0 end
		return 0, 0
	elseif t == "TouchField" then
		return num(comp, "touchfield.area_width", 0), num(comp, "touchfield.area_height", 0)
	elseif t == "Checkbox" then
		local img = assets.image(p["checkbox.bm_idle"])
		if img then return img:getWidth(), img:getHeight() end
		return 0, 0
	elseif t == "Slider" then
		local img = assets.image(p["slider.bm_panel"])
		if img then return img:getWidth(), img:getHeight() end
		return 0, 0
	end
	return 0, 0
end

-- ------------------------------------------------------------------ align

local function align_axes(align)
	align = align or "TOPLEFT"
	local ax, ay = 0, 0
	if align:find("HCENTER") or align == "CENTER" then ax = 0.5
	elseif align:find("RIGHT") then ax = 1
	elseif align:find("LEFT") then ax = 0 end
	if align:find("VCENTER") or align == "CENTER" then ay = 0.5
	elseif align:find("BOTTOM") then ay = 1
	elseif align:find("TOP") then ay = 0 end
	return ax, ay
end

-- ------------------------------------------------------- transform/draw

-- Layout semantics (verified against logo/items/buttons geometry):
-- a comp's position is normalized to the parent's area and measured FROM
-- THE PARENT'S OWN ALIGN POINT (in parent space); the comp's own align
-- point is placed at the resulting location. The screen root's align point
-- is its top-left corner.
local function apply_transform(comp, parent_w, parent_h, parent_ax, parent_ay)
	local px, py = pos2(comp, "position")
	local ox, oy = pos2(comp, "position_offset")
	local ax, ay = align_axes(comp.props.align)
	local w, h = comps.area(comp)

	local x = parent_ax * parent_w + px * parent_w + ox * parent_w
	local y = parent_ay * parent_h + py * parent_h + oy * parent_h

	love.graphics.translate(x, y)
	local angle = num(comp, "angle", 0)
	if angle ~= 0 then love.graphics.rotate(angle) end
	local sx = num(comp, "scale", 1)
	local sy = sx
	local sv = comp.props.scale
	if type(sv) == "table" then sx, sy = sv[1] or 1, sv[2] or sv[1] or 1 end
	-- approximate 3D flips (angle.x/angle.y in radians) as axis scaling
	local angx = num(comp, "angle.x", 0)
	local angy = num(comp, "angle.y", 0)
	sx = sx * math.cos(angy)
	sy = sy * math.cos(angx)
	if sx ~= 1 or sy ~= 1 then love.graphics.scale(sx, sy) end
	-- move origin to comp anchor
	love.graphics.translate(-ax * w, -ay * h)
	return w, h, ax, ay
end

local function draw_self(comp, w, h)
	local p = comp.props
	local r, g, b, a = color4(comp)
	local blend = p.blend_mode
	if blend == "ADDITIVE" then love.graphics.setBlendMode("add") end
	love.graphics.setColor(r, g, b, a)

	local t = comp.type
	if t == "Image" then
		local img = assets.image(p["image.bitmap"])
		if img then love.graphics.draw(img, 0, 0) end
	elseif t == "Rectangle" then
		love.graphics.rectangle("fill", 0, 0, w, h)
	elseif t == "NinePatch" then
		comps.draw_ninepatch(comp, w, h)
	elseif t == "Textbox" then
		local text = tostring(p["textbox.text"] or "")
		if p.localize ~= false and p.localize ~= 0 then text = Localize(text) end
		font.draw(p["textbox.font"], text, 0, 0, { r, g, b, a })
	elseif t == "Button" then
		comps.draw_button(comp, w, h, r, g, b, a)
	elseif t == "Checkbox" then
		comps.draw_checkbox(comp, w, h)
	elseif t == "Slider" then
		comps.draw_slider(comp, w, h)
	end
	-- Marker/Aligner/Emitter/Path/Model/Scriptable/TouchGrid: nothing (yet)

	if blend == "ADDITIVE" then love.graphics.setBlendMode("alpha") end
end

function comps.draw_ninepatch(comp, w, h)
	local p = comp.props
	local img = assets.image(p["ninepatch.bitmap"])
	if not img then return end
	local rect = p["ninepatch.bitmap_client_rect"]
	if type(rect) ~= "table" then
		love.graphics.draw(img, 0, 0)
		return
	end
	local cl, ct, cr, cb = rect[1] or 0, rect[2] or 0, rect[3] or 0, rect[4] or 0
	local iw, ih = img:getWidth(), img:getHeight()
	-- corner/edge sizes in source pixels
	local lw, rw = cl, iw - cr
	local th, bh = ct, ih - cb
	local cw, ch = cr - cl, cb - ct
	-- destination sizes
	local dcw, dch = w - lw - rw, h - th - bh
	if dcw < 0 or dch < 0 then return end
	local function quad(sx, sy, sw, sh, dx, dy, dw, dh)
		if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0 then return end
		local q = love.graphics.newQuad(sx, sy, sw, sh, iw, ih)
		love.graphics.draw(img, q, dx, dy, 0, dw / sw, dh / sh)
	end
	quad(0, 0, lw, th, 0, 0, lw, th)
	quad(cl, 0, cw, th, lw, 0, dcw, th)
	quad(cr, 0, rw, th, lw + dcw, 0, rw, th)
	quad(0, ct, lw, ch, 0, th, lw, dch)
	quad(cl, ct, cw, ch, lw, th, dcw, dch)
	quad(cr, ct, rw, ch, lw + dcw, th, rw, dch)
	quad(0, cb, lw, bh, 0, th + dch, lw, bh)
	quad(cl, cb, cw, bh, lw, th + dch, dcw, bh)
	quad(cr, cb, rw, bh, lw + dcw, th + dch, rw, bh)
end

function comps.draw_button(comp, w, h, r, g, b, a)
	local p = comp.props
	local state = comp.hover and "over" or "idle"
	if comp.pressed then state = "pressed" end
	if p.active == false or p.active == 0 then state = "disabled" end

	local img = assets.image(p["button.bm_" .. state]) or assets.image(p["button.bm_idle"])
	local bscale = num(comp, "button.scale_" .. state, 1)
	local cx, cy = w / 2, h / 2
	if img then
		love.graphics.push()
		love.graphics.translate(cx, cy)
		love.graphics.scale(bscale, bscale)
		love.graphics.translate(-cx, -cy)
		local bc = p["button.bitmap_color_" .. state]
		if type(bc) == "table" then
			love.graphics.setColor(bc[1] or 1, bc[2] or 1, bc[3] or 1, (bc[4] or 1) * a)
		end
		love.graphics.draw(img, 0, 0)
		love.graphics.pop()
	end

	local text = p["button.text"]
	if text ~= nil and text ~= "" then
		text = tostring(text)
		if p.localize ~= false and p.localize ~= 0 then text = Localize(text) end
		local tc = p["button.text_color_" .. state]
		local tr, tg, tb, ta = r, g, b, a
		if type(tc) == "table" then
			tr, tg, tb, ta = tc[1] or 1, tc[2] or 1, tc[3] or 1, (tc[4] or 1) * a
		end
		local tscale = num(comp, "button.text_scale_" .. state, 1)
		local fnt = p["button.font"]
		local tw, th = font.measure(fnt, text)
		local off = p["button.text_offset"]
		local tox, toy = 0, 0
		if type(off) == "table" then tox, toy = off[1] or 0, off[2] or 0 end
		-- centered on the button area; text is drawn top-left of its bounds
		local tx = cx - (tw * tscale) / 2 + tox
		local ty = cy - (th * tscale) / 2 + toy
		love.graphics.push()
		love.graphics.translate(tx, ty)
		love.graphics.scale(tscale, tscale)
		font.draw(fnt, text, 0, 0, { tr, tg, tb, ta })
		love.graphics.pop()
	end
end

function comps.draw_checkbox(comp, w, h)
	local p = comp.props
	local state = comp.hover and "over" or "idle"
	local img = assets.image(p["checkbox.bm_" .. state]) or assets.image(p["checkbox.bm_idle"])
	if img then love.graphics.draw(img, 0, 0) end
	local val = p["checkbox.value"]
	if val == true or val == 1 then
		local marker = assets.image(p["checkbox.bm_marker"])
		if marker then love.graphics.draw(marker, 0, 0) end
	end
	-- optional label
	local text = p["checkbox.text"]
	if text ~= nil and text ~= "" then
		local fnt = p["checkbox.font"]
		font.draw(fnt, tostring(text), w + 8, h / 2 - select(2, font.measure(fnt, "X")) / 2, { 1, 1, 1, 1 })
	end
end

function comps.draw_slider(comp, w, h)
	local p = comp.props
	local panel = assets.image(p["slider.bm_panel"])
	if panel then love.graphics.draw(panel, 0, 0) end
	local value = num(comp, "slider.value", 0) -- 0..1
	local full = assets.image(p["slider.bm_full"])
	if full and value > 0 then
		local fw = full:getWidth() * math.max(0, math.min(1, value))
		local q = love.graphics.newQuad(0, 0, fw, full:getHeight(), full:getWidth(), full:getHeight())
		love.graphics.draw(full, q, 0, 0)
	end
	local marker = assets.image(p["slider.bm_marker"])
	if marker then
		love.graphics.draw(marker, (w - marker:getWidth()) * math.max(0, math.min(1, value)), 0)
	end
end

-- draw comp + children, inside parent space of size pw x ph
function comps.draw(comp, pw, ph, pax, pay)
	if not comps.get(comp, "visible") then return end
	pax = pax or 0
	pay = pay or 0
	love.graphics.push("all") -- isolate transform/color/blend/font per comp
	local w, h, ax, ay = apply_transform(comp, pw, ph, pax, pay)
	draw_self(comp, w, h)
	-- children: stable sort by position.z
	local kids = comp.children
	if #kids > 1 then
		local sorted = {}
		for i, c in ipairs(kids) do sorted[i] = c end
		table.sort(sorted, function(a, b)
			local za, zb = num(a, "position.z", 0), num(b, "position.z", 0)
			if za == zb then return (a._order or 0) < (b._order or 0) end
			return za < zb
		end)
		kids = sorted
	end
	for _, child in ipairs(kids) do
		comps.draw(child, w, h, ax, ay)
	end
	love.graphics.pop()
end

-- ---------------------------------------------------------------- hit test

-- compute the screen-space axis-aligned bounds of a comp (debug aid)
function comps.screen_rect(comp)
	-- walk up the tree accumulating translations (ignores rotation/scale
	-- of ancestors for simplicity; good enough for menu debugging)
	local x, y = 0, 0
	local c = comp
	local parent = comp.parent
	local pw, ph, pax, pay
	while parent do
		pw, ph = comps.area(parent)
		local pax2, pay2 = align_axes(parent.props.align)
		local px, py = pos2(c, "position")
		local ox, oy = pos2(c, "position_offset")
		local cax, cay = align_axes(c.props.align)
		local w, h = comps.area(c)
		x = x + pax2 * pw + (px + ox) * pw - cax * w
		y = y + pay2 * ph + (py + oy) * ph - cay * h
		c = parent
		parent = parent.parent
	end
	-- c is now a root comp; apply its own screen-space placement
	local ax, ay = align_axes(c.props.align)
	local px, py = pos2(c, "position")
	local ox, oy = pos2(c, "position_offset")
	local w, h = comps.area(c)
	x = x + (px + ox) * 960 - ax * w
	y = y + (py + oy) * 640 - ay * h
	local cw, ch = comps.area(comp)
	return x, y, cw, ch
end

local CLICKABLE = { Button = true, Checkbox = true, Slider = true, Editbox = true }

-- x,y in parent space; returns hit comp or nil
function comps.hit(comp, pw, ph, x, y, pax, pay)
	if not comps.get(comp, "visible") then return nil end
	pax = pax or 0
	pay = pay or 0
	-- reproduce apply_transform math manually to compute local point
	local px, py = pos2(comp, "position")
	local ox, oy = pos2(comp, "position_offset")
	local ax, ay = align_axes(comp.props.align)
	local w, h = comps.area(comp)
	local lx = x - (pax * pw + px * pw + ox * pw)
	local ly = y - (pay * ph + py * ph + oy * ph)
	local angle = num(comp, "angle", 0)
	if angle ~= 0 then
		local c, s = math.cos(-angle), math.sin(-angle)
		lx, ly = lx * c - ly * s, lx * s + ly * c
	end
	local sx = num(comp, "scale", 1)
	local sy = sx
	local sv = comp.props.scale
	if type(sv) == "table" then sx, sy = sv[1] or 1, sv[2] or sv[1] or 1 end
	sx = sx * math.cos(num(comp, "angle.y", 0))
	sy = sy * math.cos(num(comp, "angle.x", 0))
	if sx ~= 0 and sy ~= 0 then
		lx, ly = lx / sx, ly / sy
	end
	lx = lx + ax * w
	ly = ly + ay * h

	-- children get first dibs (topmost = later creation order)
	for i = #comp.children, 1, -1 do
		local hit = comps.hit(comp.children[i], w, h, lx, ly, ax, ay)
		if hit then return hit end
	end

	if CLICKABLE[comp.type] and comps.get(comp, "active") then
		local pad = num(comp, "expanded_hit_area", 0)
		if lx >= -pad and ly >= -pad and lx <= w + pad and ly <= h + pad then
			return comp
		end
	end
	return nil
end

return comps
