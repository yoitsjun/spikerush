-- A small UI kit for the menus: one visual language everywhere.
--   * glass panels (dark, translucent, hairline border) over the 3D scenes
--   * gold primary buttons, white secondary buttons, flat tabs
--   * display titles in FredokaOne with a gold gradient and an ink outline, UI text in
--     Builder Sans
--   * icons drawn from GUI shapes (no uploaded images): home, recruit, players, locker, shop,
--     settings, help, back, the V Point volleyball and the Gold coin

--
-- The broadcast kit (Home first; the other screens move over one by one): slanted plates in
-- court navy, signal yellow and ball blue, a solid edge tab instead of borders, heavy italic
-- condensed type (Assets.Fonts), filled white icons and a halftone texture from the Toolbox
-- (Assets.image). No rounded corners, no glass, no soft gradients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"))

local Gui = {}

-- broadcast palette (from the volleyball: yellow, blue, white panels)
Gui.NAVY = Color3.fromRGB(13, 27, 62)
Gui.NAVY_LIGHT = Color3.fromRGB(26, 44, 92)
Gui.SIGNAL = Color3.fromRGB(255, 210, 31)
Gui.SIGNAL_HOT = Color3.fromRGB(255, 228, 110)
Gui.BLUE = Color3.fromRGB(31, 87, 214)
Gui.BLUE_HOT = Color3.fromRGB(62, 118, 240)
Gui.CHALK = Color3.fromRGB(242, 245, 250)
Gui.LINE = Color3.fromRGB(7, 13, 34)
Gui.ALERT = Color3.fromRGB(232, 56, 79)
Gui.DIM = Color3.fromRGB(150, 164, 196)
Gui.HAIRLINE = Color3.fromRGB(222, 184, 96) -- the thin gold edge on every card
Gui.CARD = Color3.fromRGB(12, 14, 22)

Gui.INK = Color3.fromRGB(16, 18, 30)
Gui.WHITE = Color3.fromRGB(246, 247, 250)
Gui.MUTED = Color3.fromRGB(176, 182, 200)
Gui.GOLD = Color3.fromRGB(255, 196, 40)
Gui.GOLD_LIGHT = Color3.fromRGB(255, 226, 120)
Gui.GOLD_DARK = Color3.fromRGB(214, 142, 10)
Gui.FONT = Enum.Font.BuilderSansBold
Gui.FONT_HEAVY = Enum.Font.BuilderSansExtraBold
Gui.FONT_TITLE = Enum.Font.FredokaOne
Gui.FONT_NUM = Enum.Font.GothamBlack

function Gui.make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local make = Gui.make

function Gui.corner(parent, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, parent)
end

function Gui.round(parent)
	return make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, parent)
end

function Gui.stroke(parent, thickness, color, transparency, border)
	return make("UIStroke", {
		Thickness = thickness or 1,
		Color = color or Gui.WHITE,
		Transparency = transparency or 0,
		ApplyStrokeMode = border and Enum.ApplyStrokeMode.Border or Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

function Gui.gradient(parent, top, bottom, rotation)
	return make("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 }, parent)
end

-- A dark, translucent panel with a hairline border.
function Gui.glass(parent, props, transparency)
	local f = make("Frame", {
		BackgroundColor3 = Color3.fromRGB(10, 12, 22),
		BackgroundTransparency = transparency or 0.3,
		BorderSizePixel = 0,
	}, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	Gui.corner(f, 10)
	Gui.stroke(f, 1, Gui.WHITE, 0.82, true)
	return f
end

function Gui.text(parent, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = Gui.WHITE,
		Font = Gui.FONT,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

-- Big display title: gold gradient fill with an ink outline.
function Gui.title(parent, props)
	local l = Gui.text(parent, { Font = Gui.FONT_TITLE, TextSize = 44 })
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	Gui.gradient(l, Color3.fromRGB(255, 244, 190), Gui.GOLD)
	Gui.stroke(l, 3, Gui.INK, 0)
	return l
end

local function baseButton(parent, text, props)
	local b = make("TextButton", {
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = text or "",
		Font = Gui.FONT_HEAVY,
		TextSize = 20,
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	local scale = make("UIScale", { Scale = 1 }, b)
	-- press feedback
	b.MouseButton1Down:Connect(function()
		scale.Scale = 0.96
	end)
	b.MouseButton1Up:Connect(function()
		scale.Scale = 1
	end)
	b.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	return b
end

function Gui.primary(parent, text, props)
	local b = baseButton(parent, text, { BackgroundColor3 = Color3.new(1, 1, 1), TextColor3 = Gui.INK })
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Gui.corner(b, 6)
	Gui.gradient(b, Color3.fromRGB(255, 214, 80), Color3.fromRGB(255, 170, 24))
	Gui.stroke(b, 1.5, Gui.GOLD_DARK, 0.1, true)
	return b
end

function Gui.secondary(parent, text, props)
	local b = baseButton(parent, text, { BackgroundColor3 = Color3.new(1, 1, 1), TextColor3 = Gui.INK })
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Gui.corner(b, 6)
	Gui.gradient(b, Color3.fromRGB(252, 252, 252), Color3.fromRGB(214, 218, 226))
	Gui.stroke(b, 1, Color3.fromRGB(150, 156, 170), 0.3, true)
	return b
end

-- A flat dark button (lists, small actions).
function Gui.flat(parent, text, props)
	local b = baseButton(parent, text, {
		BackgroundColor3 = Color3.fromRGB(26, 30, 48),
		BackgroundTransparency = 0.15,
		TextColor3 = Gui.WHITE,
		Font = Gui.FONT,
		TextSize = 16,
	})
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Gui.corner(b, 6)
	Gui.stroke(b, 1, Gui.WHITE, 0.85, true)
	return b
end

------------------------------------------------------------------------------------------
-- icons (drawn in a square frame; `color` for the line work)
------------------------------------------------------------------------------------------

local function box(parent, size)
	return make("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, parent)
end

local function rect(parent, x, y, w, h, color, rot, radius)
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = rot or 0,
	}, parent)
	if radius then
		Gui.corner(f, radius)
	end
	return f
end

local function ring(parent, x, y, d, color, thickness)
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(d, d),
		BackgroundTransparency = 1,
	}, parent)
	Gui.round(f)
	Gui.stroke(f, thickness or 2, color, 0, true)
	return f
end

local function dot(parent, x, y, d, color)
	local f = rect(parent, x, y, d, d, color)
	Gui.round(f)
	return f
end

Gui.icon = {}

function Gui.icon.home(parent, size, color)
	local b = box(parent, size)
	rect(b, 0.5, 0.36, 0.5, 0.5, color, 45, 2) -- roof
	rect(b, 0.5, 0.66, 0.6, 0.46, color, 0, 2) -- walls
	rect(b, 0.5, 0.76, 0.18, 0.26, Color3.fromRGB(10, 12, 22)) -- door
	return b
end

function Gui.icon.recruit(parent, size, color)
	local b = box(parent, size)
	local card = rect(b, 0.44, 0.56, 0.54, 0.7, Color3.new(0, 0, 0), -8, 3)
	card.BackgroundTransparency = 1
	Gui.stroke(card, 2, color, 0, true)
	rect(b, 0.76, 0.26, 0.1, 0.42, color, 0, 2) -- sparkle
	rect(b, 0.76, 0.26, 0.42, 0.1, color, 0, 2)
	return b
end

function Gui.icon.players(parent, size, color)
	local b = box(parent, size)
	dot(b, 0.36, 0.34, 0.3, color)
	rect(b, 0.36, 0.76, 0.52, 0.36, color, 0, 6)
	dot(b, 0.7, 0.3, 0.24, color).BackgroundTransparency = 0.35
	rect(b, 0.72, 0.68, 0.4, 0.3, color, 0, 5).BackgroundTransparency = 0.35
	return b
end

function Gui.icon.locker(parent, size, color)
	local b = box(parent, size)
	local door = rect(b, 0.5, 0.52, 0.56, 0.86, Color3.new(0, 0, 0), 0, 3)
	door.BackgroundTransparency = 1
	Gui.stroke(door, 2, color, 0, true)
	for i = 0, 2 do
		rect(b, 0.5, 0.2 + i * 0.09, 0.3, 0.04, color)
	end
	rect(b, 0.66, 0.6, 0.06, 0.14, color)
	return b
end

function Gui.icon.shop(parent, size, color)
	local b = box(parent, size)
	rect(b, 0.5, 0.64, 0.66, 0.54, color, 0, 3)
	ring(b, 0.5, 0.34, 0.36, color, 2.5)
	rect(b, 0.5, 0.5, 0.66, 0.08, Color3.fromRGB(10, 12, 22))
	return b
end

function Gui.icon.settings(parent, size, color)
	local b = box(parent, size)
	for i = 0, 3 do
		rect(b, 0.5, 0.5, 0.18, 0.86, color, i * 45, 2)
	end
	dot(b, 0.5, 0.5, 0.62, color)
	dot(b, 0.5, 0.5, 0.26, Color3.fromRGB(10, 12, 22))
	return b
end

function Gui.icon.help(parent, size, color)
	local b = box(parent, size)
	ring(b, 0.5, 0.5, 0.86, color, 2.5)
	Gui.text(b, { Text = "?", Font = Gui.FONT_HEAVY, TextColor3 = color, TextScaled = true, Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), TextXAlignment = Enum.TextXAlignment.Center })
	return b
end

function Gui.icon.back(parent, size, color)
	local b = box(parent, size)
	rect(b, 0.42, 0.34, 0.5, 0.12, color, -45, 3)
	rect(b, 0.42, 0.66, 0.5, 0.12, color, 45, 3)
	return b
end

function Gui.icon.match(parent, size, color)
	local b = Gui.icon.vp(parent, size)
	return b
end

function Gui.icon.trophy(parent, size, color)
	local b = box(parent, size)
	local cup = rect(b, 0.5, 0.36, 0.52, 0.44, color, 0, 4) -- bowl
	cup.BackgroundTransparency = 0
	ring(b, 0.24, 0.34, 0.24, color, 2.5) -- handles
	ring(b, 0.76, 0.34, 0.24, color, 2.5)
	rect(b, 0.5, 0.66, 0.12, 0.2, color) -- stem
	rect(b, 0.5, 0.82, 0.46, 0.1, color, 0, 2) -- base
	return b
end

-- The V Point: a small volleyball (yellow, white and blue bands).
function Gui.icon.vp(parent, size)
	local b = box(parent, size)
	local ball = dot(b, 0.5, 0.5, 0.94, Color3.new(1, 1, 1))
	make("UIGradient", {
		Rotation = 25,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 205, 40)),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 205, 40)),
			ColorSequenceKeypoint.new(0.31, Color3.fromRGB(250, 250, 250)),
			ColorSequenceKeypoint.new(0.62, Color3.fromRGB(250, 250, 250)),
			ColorSequenceKeypoint.new(0.63, Color3.fromRGB(34, 86, 196)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 86, 196)),
		}),
	}, ball)
	Gui.stroke(ball, 1.5, Gui.INK, 0.2, true)
	return b
end

-- Gold: a coin with a rim.
function Gui.icon.gold(parent, size)
	local b = box(parent, size)
	local coin = dot(b, 0.5, 0.5, 0.94, Color3.new(1, 1, 1))
	Gui.gradient(coin, Color3.fromRGB(255, 232, 120), Color3.fromRGB(226, 150, 20), 45)
	Gui.stroke(coin, 1.5, Color3.fromRGB(140, 86, 10), 0, true)
	ring(b, 0.5, 0.5, 0.6, Color3.fromRGB(176, 110, 12), 1.5)
	return b
end

-- A four-point sparkle (the recruit animation's stars).
function Gui.sparkle(parent, size, color)
	local b = make("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5) }, parent)
	local v = rect(b, 0.5, 0.5, 0.1, 1, color, 0)
	local h = rect(b, 0.5, 0.5, 1, 0.1, color, 0)
	for _, f in ipairs({ v, h }) do
		make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = f == v and 90 or 0,
		}, f)
	end
	dot(b, 0.5, 0.5, 0.18, Color3.new(1, 1, 1))
	return b
end

-- A currency pill: icon, amount, and an optional "+" button.
function Gui.currency(parent, iconFn, props)
	local f = make("Frame", {
		Size = UDim2.fromOffset(170, 34),
		BackgroundColor3 = Color3.fromRGB(8, 10, 18),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	Gui.round(f)
	local icon = iconFn(f, 30)
	icon.Position = UDim2.fromOffset(2, 2)
	local amount = Gui.text(f, {
		Text = "0",
		Font = Gui.FONT_HEAVY,
		TextSize = 18,
		Size = UDim2.new(1, -72, 1, 0),
		Position = UDim2.fromOffset(38, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local plus = make("TextButton", {
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -30, 0, 4),
		BackgroundColor3 = Gui.GOLD,
		Text = "+",
		Font = Gui.FONT_HEAVY,
		TextSize = 20,
		TextColor3 = Gui.INK,
		AutoButtonColor = true,
		BorderSizePixel = 0,
	}, f)
	Gui.round(plus)
	return f, amount, plus
end

------------------------------------------------------------------------------------------
-- broadcast kit
------------------------------------------------------------------------------------------

-- Faces are built once: Font.new per label would allocate on every refresh.
local faces = {}
local function face(family, weight, style)
	local key = family .. weight.Name .. style.Name
	local f = faces[key]
	if not f then
		f = Font.new(family, weight, style)
		faces[key] = f
	end
	return f
end

-- Display: heavy italic condensed (names, numbers, big buttons). Body: upright condensed.
function Gui.display(weight)
	return face(Assets.Fonts.Display, weight or Enum.FontWeight.Bold, Enum.FontStyle.Italic)
end

function Gui.body(weight)
	return face(Assets.Fonts.Body, weight or Enum.FontWeight.Regular, Enum.FontStyle.Normal)
end

-- A label in the broadcast faces: `props.display` picks the display face, `props.weight` its
-- weight; everything else is a TextLabel property.
function Gui.label(parent, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = Gui.CHALK,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	local display, weight = false, nil
	for k, v in pairs(props or {}) do
		if k == "display" then
			display = v
		elseif k == "weight" then
			weight = v
		else
			l[k] = v
		end
	end
	l.FontFace = display and Gui.display(weight) or Gui.body(weight)
	return l
end

-- A card: dark and see-through with a one-pixel gold hairline and square corners. `tint`
-- (optional) warms the fill (the career card).
function Gui.card(parent, props, tint)
	local f = make("Frame", {
		BackgroundColor3 = tint or Gui.CARD,
		BackgroundTransparency = tint and 0.55 or 0.3,
		BorderSizePixel = 0,
	}, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	return f
end

-- A hairline button (the card look, pressable): the edge brightens under the pointer.
function Gui.cardButton(parent, props)
	local b = make("TextButton", {
		BackgroundColor3 = Gui.CARD,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	local edge = make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local scale = make("UIScale", { Scale = 1 }, b)
	-- a button switched off (Gui.enable) stays dim under the pointer
	b.MouseEnter:Connect(function()
		if not b.Active then
			return
		end
		edge.Thickness = 2
		edge.Transparency = 0
		b.BackgroundTransparency = 0.15
		if Gui.onHover then
			Gui.onHover()
		end
	end)
	b.MouseLeave:Connect(function()
		edge.Thickness = 1
		edge.Transparency = 0.15
		b.BackgroundTransparency = b.Active and 0.3 or 0.65
		scale.Scale = 1
	end)
	b.MouseButton1Down:Connect(function()
		if b.Active then
			scale.Scale = 0.97
		end
	end)
	b.MouseButton1Up:Connect(function()
		scale.Scale = 1
	end)
	return b
end

-- The slanted ends: a right triangle from the Toolbox, mirrored so every plate leans forward
-- (the top edge further right than the bottom). A cap as wide as SLANT x its height keeps the
-- same 12 degree angle at any size.
Gui.SLANT = 0.21
local FLIP = 1024 -- a mirror rect at least as big as the image (it clamps to the image)
local slantImage = nil
local function capImage()
	slantImage = slantImage or Assets.image("Slant") or ""
	return slantImage
end

-- A plate: a transparent frame (props: Size in offsets, Position, ...) holding a body and two
-- caps in `color`. `opts.flatLeft` / `opts.flatRight` square off an end (a plate that runs off
-- the screen). Children go straight into the returned frame; keep text `Gui.plateInset(plate)`
-- in from the left.
function Gui.plate(parent, props, color, opts)
	opts = opts or {}
	local f = make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	local h = f.Size.Y.Offset
	local s = math.floor(h * Gui.SLANT + 0.5)
	local left = opts.flatLeft and 0 or s
	local right = opts.flatRight and 0 or s
	-- the body overlaps each cap by a pixel so no seam shows between them
	make("Frame", {
		Name = "Body",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(math.max(0, left - 1), 0),
		Size = UDim2.new(1, -math.max(0, left - 1) - math.max(0, right - 1), 1, 0),
		ZIndex = f.ZIndex,
	}, f)
	if left > 0 then
		make("ImageLabel", {
			Name = "CapL",
			BackgroundTransparency = 1,
			Image = capImage(),
			ImageColor3 = color,
			ImageRectOffset = Vector2.new(FLIP, 0),
			ImageRectSize = Vector2.new(-FLIP, FLIP),
			Size = UDim2.new(0, left, 1, 0),
			ZIndex = f.ZIndex,
		}, f)
	end
	if right > 0 then
		make("ImageLabel", {
			Name = "CapR",
			BackgroundTransparency = 1,
			Image = capImage(),
			ImageColor3 = color,
			ImageRectOffset = Vector2.new(0, FLIP),
			ImageRectSize = Vector2.new(FLIP, -FLIP),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, right, 1, 0),
			ZIndex = f.ZIndex,
		}, f)
	end
	f:SetAttribute("Slant", s)
	return f
end

-- How far text should sit from a plate's left edge.
function Gui.plateInset(plate)
	return (plate:GetAttribute("Slant") or 0) + 12
end

function Gui.tint(plate, color)
	local body = plate:FindFirstChild("Body")
	if body then
		body.BackgroundColor3 = color
	end
	for _, name in ipairs({ "CapL", "CapR" }) do
		local cap = plate:FindFirstChild(name)
		if cap then
			cap.ImageColor3 = color
		end
	end
end

function Gui.fade(plate, transparency)
	local body = plate:FindFirstChild("Body")
	if body then
		body.BackgroundTransparency = transparency
	end
	for _, name in ipairs({ "CapL", "CapR" }) do
		local cap = plate:FindFirstChild(name)
		if cap then
			cap.ImageTransparency = transparency
		end
	end
end

-- Hooks the menus set for hover and press sounds (Gui has no audio of its own).
Gui.onHover = nil

-- A plate that is a button: `color` at rest, `hot` under the pointer, pressed a touch smaller.
function Gui.plateButton(parent, props, color, hot, opts)
	local b = make("TextButton", { BackgroundTransparency = 1, Text = "", AutoButtonColor = false, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	local plate = Gui.plate(b, { Size = UDim2.fromOffset(b.Size.X.Offset, b.Size.Y.Offset), ZIndex = b.ZIndex }, color, opts)
	plate.Size = UDim2.fromScale(1, 1)
	local scale = make("UIScale", { Scale = 1 }, b)
	b.MouseEnter:Connect(function()
		Gui.tint(plate, hot or color)
		if Gui.onHover then
			Gui.onHover()
		end
	end)
	b.MouseLeave:Connect(function()
		Gui.tint(plate, color)
		scale.Scale = 1
	end)
	b.MouseButton1Down:Connect(function()
		scale.Scale = 0.97
	end)
	b.MouseButton1Up:Connect(function()
		scale.Scale = 1
	end)
	return b, plate
end

-- A Toolbox icon (Assets.image key), tinted.
function Gui.iconImage(parent, key, size, color, props)
	local im = make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Assets.image(key) or "",
		ImageColor3 = color or Gui.CHALK,
		Size = UDim2.fromOffset(size, size),
		ScaleType = Enum.ScaleType.Fit,
	}, parent)
	for k, v in pairs(props or {}) do
		im[k] = v
	end
	return im
end

-- The halftone texture laid over a plate's right end (print grain, not a gradient).
function Gui.halftone(parent, props)
	local im = make("ImageLabel", {
		Name = "Halftone",
		BackgroundTransparency = 1,
		Image = Assets.image("Halftone") or "",
		ImageColor3 = Gui.LINE,
		ImageTransparency = 0.82,
		ScaleType = Enum.ScaleType.Crop,
		Rotation = 180,
	}, parent)
	for k, v in pairs(props or {}) do
		im[k] = v
	end
	return im
end

------------------------------------------------------------------------------------------
-- roster pieces: tier badges, square buttons, text tabs, filter chips
------------------------------------------------------------------------------------------

-- A tier badge: a dark disc ringed in the tier's colour with the tier in it, and "MAX" under it
-- once a character is fully upgraded. Returns the frame and set(tier, color, maxed).
function Gui.tierBadge(parent, size, props)
	local f = make("Frame", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	local ring = make("UIStroke", { Thickness = math.max(2, size * 0.065), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	local tier = Gui.label(f, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = math.floor(size * 0.46), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = f.ZIndex })
	local maxed = Gui.label(f, {
		Text = "MAX",
		display = true,
		weight = Enum.FontWeight.Heavy,
		TextSize = math.floor(size * 0.24),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -math.floor(size * 0.12)),
		Size = UDim2.new(1, 0, 0, math.floor(size * 0.28)),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Visible = false,
		ZIndex = f.ZIndex,
	})
	local function set(text, color, isMax)
		tier.Text = text
		tier.TextColor3 = color
		ring.Color = color
		maxed.TextColor3 = color
		maxed.Visible = isMax == true
		tier.Position = isMax and UDim2.fromOffset(0, -math.floor(size * 0.06)) or UDim2.new()
	end
	return f, set
end

-- A square hairline button with a big glyph ("+", "-"). Gui.enable dims it when it can't act.
function Gui.squareButton(parent, glyph, props)
	local b = Gui.cardButton(parent, props)
	local l = Gui.label(b, { Text = glyph, display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	return b, l
end

function Gui.enable(button, label, on)
	button.Active = on
	button.AutoButtonColor = false
	if label then
		label.TextTransparency = on and 0 or 0.7
	end
	button.BackgroundTransparency = on and 0.3 or 0.65
end

-- Text tabs over a hairline: the active tab in signal yellow with a slanted bar under it.
-- Returns the frame and set(activeKey); onPick(key) on a press.
function Gui.tabs(parent, items, props, onPick)
	local f = make("Frame", { BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Gui.HAIRLINE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
	}, f)
	local tabs = {}
	for i, it in ipairs(items) do
		local b = make("TextButton", {
			Name = tostring(it.key),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Position = UDim2.fromScale((i - 1) / #items, 0),
			Size = UDim2.new(1 / #items, 0, 1, 0),
		}, f)
		local l = Gui.label(b, { Text = it.text, display = true, TextSize = 24, Size = UDim2.new(1, 0, 1, -8), TextXAlignment = Enum.TextXAlignment.Center })
		local bar = Gui.plate(b, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0.62, 0, 0, 5) }, Gui.SIGNAL)
		b.MouseEnter:Connect(function()
			if not bar.Visible then
				l.TextColor3 = Gui.CHALK
				if Gui.onHover then
					Gui.onHover()
				end
			end
		end)
		b.MouseLeave:Connect(function()
			if not bar.Visible then
				l.TextColor3 = Gui.DIM
			end
		end)
		b.MouseButton1Click:Connect(function()
			onPick(it.key)
		end)
		tabs[it.key] = { label = l, bar = bar }
	end
	local function set(active)
		for key, t in pairs(tabs) do
			local on = key == active
			t.label.TextColor3 = on and Gui.SIGNAL or Gui.DIM
			t.bar.Visible = on
		end
	end
	return f, set
end

-- Filter chips in a row (widths per item, default 72): dark rounded pills, the active one
-- filled signal yellow. Returns the frame and set(activeKey); onPick(key) on a press.
function Gui.chips(parent, items, props, onPick)
	local f = make("Frame", { BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, f)
	local chips = {}
	for i, it in ipairs(items) do
		local b = make("TextButton", {
			Name = tostring(it.key),
			Size = UDim2.new(0, it.width or 72, 1, 0),
			BackgroundColor3 = Color3.fromRGB(38, 42, 58),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
		}, f)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		local l = Gui.label(b, { Text = it.text, display = true, TextSize = 21, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		b.MouseEnter:Connect(function()
			if Gui.onHover then
				Gui.onHover()
			end
		end)
		b.MouseButton1Click:Connect(function()
			onPick(it.key)
		end)
		chips[it.key] = { button = b, label = l }
	end
	local function set(active)
		for key, c in pairs(chips) do
			local on = key == active
			c.button.BackgroundColor3 = on and Gui.SIGNAL or Color3.fromRGB(38, 42, 58)
			c.label.TextColor3 = on and Gui.LINE or Gui.CHALK
		end
	end
	return f, set
end

-- Number with thousands separators: 18435 -> "18,435".
function Gui.num(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

return Gui
