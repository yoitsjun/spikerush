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
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Assets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Gui = {}

-- broadcast palette (Volleyball Rush: a deep orange on navy with magenta edges; the owner,
-- 2026-10-28: "keep the core color orange on the menus... i just cant have it identical" to the old
-- golden yellow)
Gui.NAVY = Color3.fromRGB(11, 16, 46)
Gui.NAVY_LIGHT = Color3.fromRGB(26, 34, 88)
Gui.SIGNAL = Color3.fromRGB(255, 124, 28)
Gui.SIGNAL_HOT = Color3.fromRGB(255, 178, 108)
Gui.CYAN = Color3.fromRGB(0, 229, 255)
Gui.MAGENTA = Color3.fromRGB(255, 46, 170)
Gui.MAGENTA_HOT = Color3.fromRGB(255, 122, 206)
Gui.BLUE = Color3.fromRGB(40, 92, 232)
Gui.BLUE_HOT = Color3.fromRGB(72, 126, 248)
Gui.CHALK = Color3.fromRGB(242, 245, 250)
Gui.LINE = Color3.fromRGB(6, 10, 30)
Gui.ALERT = Color3.fromRGB(232, 56, 79)
Gui.DIM = Color3.fromRGB(150, 164, 204)
-- the edge on every card and button: black (the owner, 2026-10-29: "the outlines dont have to be
-- pink. black or a more clean color would work"), or your spike trail's colour (Gui.setEdge, below);
-- magenta stays an accent (a card's small headings, the Party and Recruit icons), and thin dividers
-- and scrollbars are DIM
Gui.HAIRLINE = Color3.fromRGB(0, 0, 0)
Gui.CARD = Color3.fromRGB(10, 12, 28)

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

-- The edges follow your spike trail (the owner, 2026-10-29: "make the menu outlines the same as
-- your spike trail"): Classic keeps them black, a one-colour trail paints them its colour, and a
-- banded one (Rainbow, Candy Corn...) runs its bands along every edge. Gui.HAIRLINE is always the
-- current edge colour, nudged a hair off the colour itself so an edge can be told from any other
-- stroke (white under a banded trail's gradient); a stroke set back to it (a tab losing the orange
-- selection) wears the trail again. MenuController calls this with your SpikeColor.
local EDGE_BLACK = Gui.HAIRLINE
local function edgeOf(c)
	return Color3.new(c.R, c.G, c.B + (c.B > 0.5 and -1 or 1) / 2048) -- (invisible)
end
Gui.HAIRLINE = edgeOf(EDGE_BLACK)
local edgeBands = nil -- a banded trail's ColorSequence
local edgeHooked = false

-- A banded trail's gradient on a stroke, shown only while the stroke wears the edge colour.
local function bandStroke(stroke)
	local g = stroke:FindFirstChild("TrailEdge")
	if not g then
		if not edgeBands then
			return
		end
		g = Instance.new("UIGradient")
		g.Name = "TrailEdge"
		g.Rotation = 30
		g.Parent = stroke
		stroke:GetPropertyChangedSignal("Color"):Connect(function()
			g.Enabled = edgeBands ~= nil and stroke.Color == Gui.HAIRLINE
		end)
	end
	if edgeBands then
		g.Color = edgeBands
	end
	g.Enabled = edgeBands ~= nil and stroke.Color == Gui.HAIRLINE
end

function Gui.setEdge(colorKey, root)
	local item = nil
	for _, it in ipairs(Config.Cosmetics.Color or {}) do
		if it.Key == colorKey then
			item = it
			break
		end
	end
	local bands = item and type(item.Trail) == "table" and #item.Trail >= 2 and item.Trail or nil
	local old = Gui.HAIRLINE
	if bands then
		local kps = {}
		for i, c in ipairs(bands) do
			table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#bands - 1), c))
		end
		edgeBands = ColorSequence.new(kps)
		Gui.HAIRLINE = edgeOf(Color3.new(1, 1, 1))
	else
		edgeBands = nil
		Gui.HAIRLINE = edgeOf(item and item.Color or EDGE_BLACK)
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("UIStroke") then
			if d.Color == old then
				d.Color = Gui.HAIRLINE
			end
			bandStroke(d)
		end
	end
	if not edgeHooked then
		-- (strokes made later: a list filling, a card opening)
		edgeHooked = true
		root.DescendantAdded:Connect(function(d)
			if edgeBands and d:IsA("UIStroke") then
				task.defer(bandStroke, d)
			end
		end)
	end
end

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

-- Big display title: white-to-orange gradient fill with an ink outline.
function Gui.title(parent, props)
	local l = Gui.text(parent, { Font = Gui.FONT_TITLE, TextSize = 44 })
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	Gui.gradient(l, Color3.fromRGB(255, 242, 228), Gui.SIGNAL)
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
	Gui.gradient(b, Color3.fromRGB(255, 170, 92), Color3.fromRGB(255, 102, 18))
	Gui.stroke(b, 1.5, Color3.fromRGB(168, 58, 6), 0.1, true)
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
Gui.play = nil -- AudioController.play

-- Press sounds. A click only fires as the finger or the mouse comes back up, which sounds late,
-- so a button sounds as it goes down (Gui.pressSound) and the click that follows stays quiet:
-- Gui.click, which click handlers call, skips once after a press has sounded. The skip lapses
-- just after the release, so a press that slid off its button can't silence a later click.
local lastClick = 0
local pressed = false
local pressGen = 0

local function playPress(key)
	if Gui.play then
		Gui.play(key or "UIClick", { minGap = 0.05 })
	end
end

function Gui.click(key)
	local now = os.clock()
	if pressed or now - lastClick < 0.08 then
		pressed = false
		lastClick = now
		return
	end
	lastClick = now
	playPress(key)
end

function Gui.press(key)
	playPress(key)
	pressed = true
	pressGen = pressGen + 1
	lastClick = os.clock()
end

-- Sound `button` as it goes down: `key`, else its Sound attribute, else UIClick. `canAct`, when
-- given, says whether the press will do anything (a dimmed + stays quiet).
function Gui.pressSound(button, key, canAct)
	button.MouseButton1Down:Connect(function()
		if canAct == nil or canAct() then
			Gui.press(key or button:GetAttribute("Sound"))
		end
	end)
end

UserInputService.InputEnded:Connect(function(input)
	local t = input.UserInputType
	if pressed and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
		local gen = pressGen
		task.delay(0.1, function()
			if pressGen == gen then
				pressed = false
			end
		end)
	end
end)

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
-- Every row of tabs (tabs, chips, segmented controls, plate tabs) by its frame, so a controller's
-- shoulder buttons can step through them (PadNav): { keys, pick(key), current }.
Gui.tabGroups = setmetatable({}, { __mode = "k" })

-- Register a row of tabs; returns mark(activeKey) for its set() to call.
function Gui.navTabs(frame, items, onPick)
	local g = { keys = {}, pick = onPick, current = nil }
	for i, it in ipairs(items) do
		g.keys[i] = it.key
	end
	Gui.tabGroups[frame] = g
	return function(active)
		g.current = active
	end
end

function Gui.tabs(parent, items, props, onPick)
	local f = make("Frame", { BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Gui.DIM,
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
		Gui.pressSound(b, "UISelect")
		b.MouseButton1Click:Connect(function()
			onPick(it.key)
		end)
		tabs[it.key] = { label = l, bar = bar }
	end
	local mark = Gui.navTabs(f, items, onPick)
	local function set(active)
		mark(active)
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
		Gui.pressSound(b, "UISelect")
		b.MouseButton1Click:Connect(function()
			onPick(it.key)
		end)
		chips[it.key] = { button = b, label = l }
	end
	local mark = Gui.navTabs(f, items, onPick)
	local function set(active)
		mark(active)
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

-- A player card (the scorer's card after a point, the Locker's cards), w x h (480 x 104 by
-- default) in `props` (Position, AnchorPoint, Visible, ZIndex...). A slanted plate: a border
-- (optional), the base, the colour sweeping in from the left, a pattern (halftone, stripes, rays or
-- stars), the headshot, the card's title on a small tag, the name, tier and a line, a number in big
-- type at the right with its label (else speed chevrons), and the point's word on a tag.
-- card.set(look, data): look = { Base, Sweep, Accent, Edge (or nil), Pattern, Big, Avatar };
-- data = { userId, name, tier, tierColor, line, value, label, word, title }. Big: words in big
-- type where the number goes; Avatar: card.viewport (left, over the headshot's place) shows and
-- the caller fills it with the player's avatar (AnimationController.portrait).
function Gui.playerCard(parent, props)
	props = props or {}
	local W = props.W or 480
	local H = props.H or 104
	local z = props.ZIndex or 1
	local root = make("Frame", { Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1 }, parent)
	-- NoWings: a card in a list, where wings would cover the text beside it (the crown stays)
	local noWings = props.NoWings == true
	for k, v in pairs(props) do
		if k ~= "W" and k ~= "H" and k ~= "NoWings" then
			root[k] = v
		end
	end
	-- Special cards (Look.Fx; all of it on the Almighty card; the owner: "make it really special", after a game's
	-- winged title banners): gold wings out of both sides and a crown over the top, a breathing glow
	-- round the edge, a halo of turning rays behind the avatar, a shine sweeping across, sparkles
	-- twinkling and gold light running through the big word. Hidden on every other card.
	local wingH = math.floor(H * 1.3)
	local wingW = math.floor(wingH * 1.6)
	local glow = Gui.plate(root, { Position = UDim2.fromOffset(-12, -12), Size = UDim2.fromOffset(W + 24, H + 24), Visible = false, ZIndex = z }, Color3.fromRGB(255, 214, 100))
	-- (Aura, the True Almighty card: the owner, 2026-10-21, "put some more special stuff on it") a
	-- band of every colour turning round the card's edge
	local aura = Gui.plate(root, { Position = UDim2.fromOffset(-9, -9), Size = UDim2.fromOffset(W + 18, H + 18), Visible = false, ZIndex = z }, Color3.new(1, 1, 1))
	local auraGrads = {}
	for _, d in ipairs(aura:GetDescendants()) do
		if d:IsA("GuiObject") then
			table.insert(auraGrads, make("UIGradient", { Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
				ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 40)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 200, 255)),
				ColorSequenceKeypoint.new(0.8, Color3.fromRGB(190, 90, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 60)),
			}) }, d))
		end
	end
	-- (each wing's root, the gold boss, sits at 92% / 72% of its image: tucked in behind the card's
	-- side, so the wings grow from behind it; the owner: "it would look better if the wings were more
	-- inward")
	local tuck = math.floor(H * 0.55)
	local wingL = make("ImageLabel", { Image = Assets.image("CardWingL") or "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.92, 0.72), Position = UDim2.new(0, tuck, 0.5, 0), Size = UDim2.fromOffset(wingW, wingH), Visible = false, ZIndex = z }, root)
	local wingR = make("ImageLabel", { Image = Assets.image("CardWingR") or "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.08, 0.72), Position = UDim2.new(1, -tuck, 0.5, 0), Size = UDim2.fromOffset(wingW, wingH), Visible = false, ZIndex = z }, root)
	local crestH = math.floor(H * 0.78)
	local crest = make("ImageLabel", { Image = Assets.image("CardCrest") or "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.8), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(math.floor(crestH * 1.28), crestH), Visible = false, ZIndex = z + 7 }, root)
	local edge = Gui.plate(root, { Position = UDim2.fromOffset(-5, -5), Size = UDim2.fromOffset(W + 10, H + 10), ZIndex = z }, Gui.CHALK)
	local base = Gui.plate(root, { Size = UDim2.fromOffset(W, H), ZIndex = z + 1 }, Gui.CARD)
	local sweep = Gui.plate(root, { Size = UDim2.fromOffset(W, H), ZIndex = z + 2 }, Gui.CHALK)
	local body = sweep:FindFirstChild("Body")
	if body then
		make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.45, 0.6), NumberSequenceKeypoint.new(1, 1) }) }, body)
	end
	local capR = sweep:FindFirstChild("CapR")
	if capR then
		capR.ImageTransparency = 1
	end
	-- the patterns, over the right of the card; one shows at a time
	local patterns = {}
	patterns.halftone = Gui.halftone(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.55, 0, 1, 0), ImageColor3 = Gui.CHALK, ImageTransparency = 0.9, ZIndex = z + 3 })
	local function clipBox()
		return make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -math.floor(H * 0.22), 0, 0), Size = UDim2.new(0.62, 0, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z + 3 }, root)
	end
	local tinted = {}
	patterns.stripes = clipBox()
	for i = 1, 8 do
		table.insert(tinted, make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new((i - 1) / 7, 0, 0.5, 0), Size = UDim2.new(0, 12, 2.4, 0), Rotation = 24, BackgroundColor3 = Gui.CHALK, BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = z + 3 }, patterns.stripes))
	end
	patterns.rays = clipBox()
	for i = 1, 12 do
		table.insert(tinted, make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.72, 0.5), Size = UDim2.new(0, 6, 0, W), Rotation = (i - 1) * 15, BackgroundColor3 = Gui.CHALK, BackgroundTransparency = 0.84, BorderSizePixel = 0, ZIndex = z + 3 }, patterns.rays))
	end
	patterns.stars = clipBox()
	for _, spot in ipairs({ { 0.2, 0.3, 26 }, { 0.42, 0.72, 18 }, { 0.6, 0.22, 22 }, { 0.8, 0.62, 30 }, { 0.95, 0.25, 16 } }) do
		local sp = Gui.sparkle(patterns.stars, spot[3], Gui.CHALK)
		sp.Position = UDim2.fromScale(spot[1], spot[2])
		sp.ZIndex = z + 3
		-- its arms take the accent (the white dot in the middle stays)
		for _, d in ipairs(sp:GetChildren()) do
			if d:IsA("Frame") and d.BackgroundColor3 == Gui.CHALK then
				table.insert(tinted, d)
			end
		end
	end
	-- (Divine) the halo behind the avatar and the sweeping shine, kept inside the card
	local divineClip = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false, ZIndex = z + 3 }, root)
	local rays = {}
	local haloX = 28 + math.floor((H - 20) / 2) + 10
	for i = 1, 14 do
		local ray = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(haloX, math.floor(H / 2)), Size = UDim2.fromOffset(7, math.floor(W * 0.9)), BackgroundColor3 = Color3.fromRGB(255, 226, 130), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = z + 3 }, divineClip)
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, ray)
		rays[i] = ray
	end
	local gloss = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.3, 0.5), Size = UDim2.new(0, math.floor(H * 0.7), 2.4, 0), Rotation = 22, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = z + 4 }, divineClip)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) }) }, gloss)
	local sparks = {}
	for i, spot in ipairs({ { 0.3, 0.12, 22 }, { 0.47, 0.86, 16 }, { 0.62, 0.18, 18 }, { 0.84, 0.9, 20 }, { 0.97, 0.3, 14 }, { 0.05, 0.92, 16 } }) do
		local sp = Gui.sparkle(root, spot[3], Color3.fromRGB(255, 244, 200))
		sp.Position = UDim2.fromScale(spot[1], spot[2])
		sp.Visible = false
		sp.ZIndex = z + 7
		for _, d in ipairs(sp:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = z + 7
			end
		end
		sparks[i] = { frame = sp, scale = make("UIScale", { Scale = 1 }, sp) }
	end
	-- (Embers, the True Almighty card) sparks of gold and red rising up through the card
	local emberClip = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false, ZIndex = z + 6 }, root)
	local embers = {}
	for i = 1, 14 do
		local e = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4 + (i % 3) * 2, 4 + (i % 3) * 2), BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(255, 210, 80) or Color3.fromRGB(255, 90, 50), BorderSizePixel = 0, ZIndex = z + 6 }, emberClip)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, e)
		embers[i] = { frame = e, x = ((i * 0.618) % 1), speed = 0.18 + (i % 5) * 0.05, phase = (i * 0.37) % 1 }
	end
	local chevrons = {}
	for i = 1, 3 do
		local chevron = Gui.plate(root, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -30 - (3 - i) * 26, 0.5, 8), Size = UDim2.fromOffset(16, H - 44), ZIndex = z + 3 }, Gui.SIGNAL)
		Gui.fade(chevron, 0.2 + (3 - i) * 0.25)
		chevrons[i] = chevron
	end
	local shotSize = H - 20
	local shot = make("ImageLabel", {
		Position = UDim2.fromOffset(28, 10),
		Size = UDim2.fromOffset(shotSize, shotSize),
		BackgroundColor3 = Gui.LINE,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = z + 4,
	}, root)
	local shotEdge = make("UIStroke", { Color = Gui.CHALK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, shot)
	local x = 28 + shotSize + 16
	local name = Gui.label(root, { display = true, weight = Enum.FontWeight.Heavy, TextSize = 32, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(x, 12), Size = UDim2.new(1, -x - 120, 0, 38), ZIndex = z + 5 })
	local _, setBadge = Gui.tierBadge(root, 30, { Position = UDim2.fromOffset(x, 58), ZIndex = z + 5 })
	local line = Gui.label(root, { TextSize = 18, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(x + 38, 58), Size = UDim2.new(1, -x - 60, 0, 30), ZIndex = z + 5 })
	-- the number the card shows, big at the right, and its label
	-- (the Ranked card: the wearer's rank badge standing off the right edge)
	local rankBadge = make("ImageLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, math.floor(H * 0.18), 0.5, 0), Size = UDim2.fromOffset(math.floor(H * 1.25), math.floor(H * 1.25)), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Visible = false, ZIndex = z + 7 }, root)
	local value = Gui.label(root, { display = true, weight = Enum.FontWeight.Heavy, TextSize = 44, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -26, 0, 10), Size = UDim2.fromOffset(170, 48), ZIndex = z + 5 })
	local valueLabel = Gui.label(root, { display = true, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, 58), Size = UDim2.fromOffset(170, 18), ZIndex = z + 5 })
	-- the card's title, on a small tag over the top left
	local title = Gui.plate(root, { Position = UDim2.fromOffset(18, -14), Size = UDim2.fromOffset(150, 26), ZIndex = z + 6 }, Gui.SIGNAL)
	local titleText = Gui.label(title, { display = true, weight = Enum.FontWeight.Heavy, TextSize = 16, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 7 })
	-- the Content Creator card's words, in big type where the number goes, and its avatar viewport
	-- (the caller poses the player's avatar in it, mid-spike, rising over the card's top edge)
	local bigW = math.floor(W * 0.34)
	local big = Gui.label(root, { display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 2), Size = UDim2.fromOffset(bigW, H - 26), Visible = false, ZIndex = z + 5 })
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.35 }, big)
	-- (Divine) gold light running through the big word
	local GOLD = Color3.fromRGB(255, 205, 70)
	local bigShine = make("UIGradient", { Enabled = false, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, GOLD), ColorSequenceKeypoint.new(0.42, GOLD), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.58, GOLD), ColorSequenceKeypoint.new(1, GOLD) }) }, big)
	local viewport = make("ViewportFrame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 4),
		Size = UDim2.fromOffset(shotSize + 44, H + 40),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 180, 210),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.6, -1, -0.4),
		Visible = false,
		ZIndex = z + 6,
	}, root)
	-- the point's word ("KILL!"), on a tag over the top right
	local tag = Gui.plate(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, -16), Size = UDim2.fromOffset(150, 34), ZIndex = z + 6 }, Gui.SIGNAL)
	local word = Gui.label(tag, { display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 7 })
	-- (Net, the Bug Catcher card; the owner sent a bug net to go by, mirrored so the net's on the
	-- right) the net hooked over the card's top right by its cuff: the sack hangs out past the side,
	-- the handle curls down over the card's corner. `net` is a square centred on the cuff, so turning
	-- it swings the net about it. In a list (NoWings) it's smaller, clear of the text beside it.
	local NR = 160
	local netH = noWings and math.floor(H * 1.05) or math.floor(H * 1.5)
	local net = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W + (noWings and 4 or 20), -4), Size = UDim2.fromOffset(NR * 2, NR * 2), BackgroundTransparency = 1, Visible = false, ZIndex = z + 7 }, root)
	make("ImageLabel", { Image = Assets.image("CardBugNet") or "", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.66, 0.05), Position = UDim2.fromOffset(NR, NR), Size = UDim2.fromOffset(math.floor(netH * 0.95), netH), ZIndex = z + 7 }, net)

	-- (Pumpkin, the Halloween 2026 card; the owner, 2026-10-17: "put a jackolantern on the halloween
	-- 2026 card its too bland right now", then of the one built from shapes: "looks way too ai") a
	-- carved jack-o'-lantern image (Assets.Images.CardPumpkin) sat on the card's bottom right corner,
	-- glowing, its candle flickering, rocking a little
	local PS = noWings and math.floor(H * 0.95) or math.floor(H * 1.3)
	local pumpkin = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W - math.floor(PS * 0.2), H - math.floor(PS * 0.3)), Size = UDim2.fromOffset(PS, PS), BackgroundTransparency = 1, Visible = false, ZIndex = z + 7 }, root)
	local pumpkinGlow = make("ImageLabel", { Image = Assets.id(Assets.Fx.Glow) or "", BackgroundTransparency = 1, ImageColor3 = Color3.fromRGB(255, 140, 30), ImageTransparency = 0.45, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(1.9, 1.9), ZIndex = z + 6 }, pumpkin)
	local pumpkinImg = make("ImageLabel", { Image = Assets.image("CardPumpkin") or "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z + 7 }, pumpkin)


	-- (built only on a card that shows one: a list of cards would carry hundreds of hidden
	-- pieces otherwise)
	local winterFx = nil
	local function buildWinterFx()
		-- The Winter Pass's cards (the owner, 2026-11-16: "these are all nearly identical give them some
		-- flair"): each its own thing on the card, moving (Look.Fx). All hidden on every other card.
		local SNOWW = Color3.fromRGB(246, 251, 255)
		local function blob(parent, props)
			local f = make("Frame", props, parent)
			f.BorderSizePixel = 0
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
			return f
		end
		-- (Snowfall: Snow Day) snow piled along the top edge, flakes drifting down the card
		local snowCap = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = z + 6 }, root)
		-- (between the card's slanted ends: x from about H * 0.3 to W - H * 0.05)
		-- (clear of the title tag on the left, sitting on the edge: mostly on the card, bumps above)
		local x0, x1 = 18 + 150 + 16, W - math.floor(H * 0.12)
		for i = 0, 8 do
			local w = math.floor((x1 - x0) / 5) + (i % 3) * 10
			local h = math.floor(H * 0.24) + (i % 2) * 6
			blob(snowCap, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x0 + math.floor(i / 8 * (x1 - x0)), math.floor(h * 0.32) + (i % 3)), Size = UDim2.fromOffset(w, h), BackgroundColor3 = SNOWW, ZIndex = z + 6 })
		end
		local snowClip = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false, ZIndex = z + 6 }, root)
		local flakes = {}
		for i = 1, 14 do
			local d = 3 + (i % 3) * 2
			local f = blob(snowClip, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(d, d), BackgroundColor3 = SNOWW, BackgroundTransparency = 0.1, ZIndex = z + 6 })
			flakes[i] = { frame = f, x = (i * 0.618) % 1, speed = 0.16 + (i % 4) * 0.05, phase = (i * 0.41) % 1 }
		end
		-- (Lights: Winter 2026) a string of Christmas lights sagging along the top edge, twinkling
		local lights = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = z + 6 }, root)
		local BULB = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(90, 230, 120), Color3.fromRGB(255, 206, 80), Color3.fromRGB(90, 170, 255) }
		local bulbs = {}
		for i = 0, 10 do
			local u = i / 10
			local y = 2 + math.sin((u * 2 % 1) * math.pi) * 9
			local b = blob(lights, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(math.floor(u * W), math.floor(y)), Size = UDim2.fromOffset(9, 13), BackgroundColor3 = BULB[i % #BULB + 1], ZIndex = z + 6 })
			bulbs[i + 1] = { frame = b, color = BULB[i % #BULB + 1] }
			if i < 10 then
				local u2 = (i + 1) / 10
				local y2 = 2 + math.sin((u2 * 2 % 1) * math.pi) * 9
				local x1, x2 = u * W, u2 * W
				local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y) ^ 2)
				make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(math.floor((x1 + x2) / 2), math.floor((y + y2) / 2) + 1), Size = UDim2.fromOffset(math.floor(len), 2), Rotation = math.deg(math.atan2(y2 - y, x2 - x1)), BackgroundColor3 = Color3.fromRGB(20, 50, 30), BorderSizePixel = 0, ZIndex = z + 6 }, lights)
			end
		end
		local bigFlake = make("ImageLabel", { Image = Assets.image("IconSnowflake") or "", BackgroundTransparency = 1, ImageColor3 = SNOWW, ImageTransparency = 0.72, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -math.floor(W * 0.17), 0.5, 0), Size = UDim2.fromOffset(math.floor(H * 1.25), math.floor(H * 1.25)), Visible = false, ZIndex = z + 3 }, root)
		-- (Icicles: Frostbitten) icicles hanging off the bottom edge, frost creeping in at the sides
		local icicles = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = z + 6 }, root)
		local icicleImg = Assets.id(Assets.Fx.Icicle) or ""
		local iceBits = {}
		for i = 0, 8 do
			local len = math.floor(H * (0.4 + ((i * 37) % 5) * 0.09))
			local ic = make("ImageLabel", { Image = icicleImg, BackgroundTransparency = 1, ImageColor3 = Color3.fromRGB(210, 246, 255), Rotation = 180, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(math.floor((0.1 + i * 0.1) * W), H - 6), Size = UDim2.fromOffset(math.floor(len * 0.55), len), ZIndex = z + 6 }, icicles)
			iceBits[i + 1] = ic
		end
		for _, spot in ipairs({ { 0.36, 0.2, 0.34 }, { 0.6, 0.78, 0.26 }, { 0.93, 0.22, 0.4 } }) do
			make("ImageLabel", { Image = Assets.image("IconSnowflake") or "", BackgroundTransparency = 1, ImageColor3 = Color3.fromRGB(220, 248, 255), ImageTransparency = 0.35, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spot[1], spot[2]), Size = UDim2.fromOffset(math.floor(H * spot[3]), math.floor(H * spot[3])), ZIndex = z + 5 }, icicles)
		end
		-- (Bells: Jingle Spiker) two gold bells on a holly sprig, swinging off the top right corner
		local bellSize = math.floor(H * 0.42)
		local bells = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(1, -math.floor(H * 0.1), 0, -math.floor(H * 0.24)), Size = UDim2.fromOffset(bellSize * 3, bellSize * 2), BackgroundTransparency = 1, Visible = false, ZIndex = z + 7 }, root)
		local bellArms = {}
		for k, dx in ipairs({ -0.6, 0.6 }) do
			local arm = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, math.floor(dx * bellSize), 0, math.floor(bellSize * 0.25)), Size = UDim2.fromOffset(bellSize, math.floor(bellSize * 1.5)), BackgroundTransparency = 1, ZIndex = z + 7 }, bells)
			make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(3, math.floor(bellSize * 0.3)), BackgroundColor3 = Color3.fromRGB(200, 30, 40), BorderSizePixel = 0, ZIndex = z + 7 }, arm)
			local body = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromScale(0.7, 0.62), BackgroundColor3 = Color3.fromRGB(255, 206, 60), BorderSizePixel = 0, ZIndex = z + 7 }, arm)
			make("UICorner", { CornerRadius = UDim.new(0.45, 0) }, body)
			make("UIGradient", { Rotation = 0, Color = ColorSequence.new(Color3.fromRGB(255, 236, 140), Color3.fromRGB(210, 140, 20)) }, body)
			make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(0.95, 0.12), BackgroundColor3 = Color3.fromRGB(220, 160, 30), BorderSizePixel = 0, ZIndex = z + 8 }, arm)
			blob(arm, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.9), Size = UDim2.fromOffset(math.floor(bellSize * 0.24), math.floor(bellSize * 0.24)), BackgroundColor3 = Color3.fromRGB(150, 100, 20), ZIndex = z + 7 })
			bellArms[k] = arm
		end
		for k, dx in ipairs({ -0.35, 0.35 }) do
			blob(bells, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.floor(dx * bellSize), 0, math.floor(bellSize * 0.2)), Size = UDim2.fromOffset(math.floor(bellSize * 0.75), math.floor(bellSize * 0.35)), Rotation = dx * 60, BackgroundColor3 = Color3.fromRGB(30, 130, 60), ZIndex = z + 9 })
		end
		for k, dx in ipairs({ -0.08, 0.1, 0 }) do
			blob(bells, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.floor(dx * bellSize), 0, math.floor(bellSize * (k == 3 and 0.1 or 0.22))), Size = UDim2.fromOffset(math.floor(bellSize * 0.2), math.floor(bellSize * 0.2)), BackgroundColor3 = Color3.fromRGB(220, 20, 30), ZIndex = z + 10 })
		end
		-- (Coal: Naughty) a lump pile of coal smouldering in the bottom right corner, smoke curling up
		local CS = noWings and math.floor(H * 0.8) or math.floor(H * 1.05)
		local coal = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W - math.floor(CS * 0.3), H - math.floor(CS * 0.3)), Size = UDim2.fromOffset(CS, CS), BackgroundTransparency = 1, Visible = false, ZIndex = z + 7 }, root)
		local coalGlow = make("ImageLabel", { Image = Assets.id(Assets.Fx.Glow) or "", BackgroundTransparency = 1, ImageColor3 = Color3.fromRGB(255, 90, 20), ImageTransparency = 0.5, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromScale(1.6, 1.1), ZIndex = z + 6 }, coal)
		local embersC = {}
		for i, l in ipairs({ { 0.3, 0.72, 0.42 }, { 0.65, 0.74, 0.46 }, { 0.48, 0.52, 0.4 }, { 0.82, 0.6, 0.3 }, { 0.16, 0.6, 0.28 } }) do
			local lump = blob(coal, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(l[1], l[2]), Size = UDim2.fromScale(l[3], l[3] * 0.8), Rotation = i * 23, BackgroundColor3 = Color3.fromRGB(46 + i * 4, 42 + i * 3, 46), ZIndex = z + 7 })
			make("UIStroke", { Color = Color3.fromRGB(255, 110, 30), Thickness = 1.5, Transparency = 0.35 }, lump)
			embersC[i] = blob(coal, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(l[1] + 0.04, l[2] - 0.02), Size = UDim2.fromOffset(5, 3), BackgroundColor3 = Color3.fromRGB(255, 120, 30), ZIndex = z + 8 })
		end
		local smoke = {}
		for i = 1, 4 do
			smoke[i] = blob(coal, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.3, 0.3), BackgroundColor3 = Color3.fromRGB(110, 110, 120), ZIndex = z + 6 })
		end
		-- (Gift: Nice) a wrapped present in the bottom right corner, its lid hopping
		local GS = noWings and math.floor(H * 0.78) or math.floor(H * 1.0)
		local gift = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(W - math.floor(GS * 0.35), H + math.floor(GS * 0.18)), Size = UDim2.fromOffset(GS, GS), BackgroundTransparency = 1, Visible = false, ZIndex = z + 7 }, root)
		local box = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.8, 0.62), BackgroundColor3 = Color3.fromRGB(214, 36, 52), BorderSizePixel = 0, ZIndex = z + 7 }, gift)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.18, 1), BackgroundColor3 = Color3.fromRGB(255, 214, 90), BorderSizePixel = 0, ZIndex = z + 8 }, box)
		local lid = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.92, 0.17), BackgroundColor3 = Color3.fromRGB(236, 50, 66), BorderSizePixel = 0, ZIndex = z + 9 }, gift)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, lid)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.17, 1), BackgroundColor3 = Color3.fromRGB(255, 214, 90), BorderSizePixel = 0, ZIndex = z + 10 }, lid)
		for _, dx in ipairs({ -1, 1 }) do
			blob(lid, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, dx * math.floor(GS * 0.12), 0, 2), Size = UDim2.fromOffset(math.floor(GS * 0.26), math.floor(GS * 0.2)), Rotation = dx * 25, BackgroundColor3 = Color3.fromRGB(255, 214, 90), ZIndex = z + 10 })
		end
		-- (Aurora: Northern Lights) green and violet light rippling across the card
		local auroraClip = make("Frame", { Position = UDim2.fromOffset(math.floor(H * 0.3), 3), Size = UDim2.new(1, -math.floor(H * 0.55), 1, -6), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false, ZIndex = z + 3 }, root)
		local auroraBands = {}
		for i = 1, 3 do
			local band = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3 + i * 0.12), Size = UDim2.new(1.6, 0, 0, math.floor(H * 0.42)), Rotation = -8 + i * 5, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = z + 3 }, auroraClip)
			local g = make("UIGradient", {
				Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 255, 170)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 110, 255)) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(0.7, 0.55), NumberSequenceKeypoint.new(1, 1) }),
			}, band)
			auroraBands[i] = { frame = band, grad = g }
		end
		-- (SantaHat: Santa's Ace) a Santa hat on the player's picture
		-- (on the picture's top right corner, clear of the title tag)
		local hatS = math.floor(H * 0.8)
		local hat = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(28 + (H - 20) - 20, math.floor(H * 0.42)), Size = UDim2.fromOffset(hatS, hatS), Rotation = 14, BackgroundTransparency = 1, Visible = false, ZIndex = z + 8 }, root)
		local BANDS = 8
		for i = 0, BANDS - 1 do
			local u = i / BANDS
			local bw = 0.78 * (1 - u) + 0.1
			local droop = u * u * 0.32
			local band = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5 + droop, 0.84 - u * 0.62), Size = UDim2.fromScale(bw, 0.62 / BANDS + 0.02), BackgroundColor3 = Color3.fromRGB(214, 30, 44):Lerp(Color3.fromRGB(160, 16, 28), u * 0.5), BorderSizePixel = 0, ZIndex = z + 8 }, hat)
			make("UICorner", { CornerRadius = UDim.new(0.4, 0) }, band)
		end
		local fur = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.fromScale(0.96, 0.2), BackgroundColor3 = SNOWW, BorderSizePixel = 0, ZIndex = z + 9 }, hat)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fur)
		local pom = blob(hat, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.82, 0.22), Size = UDim2.fromScale(0.24, 0.24), BackgroundColor3 = SNOWW, ZIndex = z + 9 })
		return { snowCap = snowCap, snowClip = snowClip, flakes = flakes, lights = lights, bulbs = bulbs, bigFlake = bigFlake, icicles = icicles, iceBits = iceBits, bells = bells, bellArms = bellArms, coal = coal, coalGlow = coalGlow, embersC = embersC, smoke = smoke, gift = gift, lid = lid, auroraClip = auroraClip, auroraBands = auroraBands, hat = hat, pom = pom }
	end

	local card = { root = root, viewport = viewport }
	-- (Divine) one frame of its motion
	local divineConn = nil
	local function divineStep()
		local t = os.clock()
		for i, ray in ipairs(rays) do
			ray.Rotation = (i - 1) * (180 / #rays) + t * 14
		end
		-- the shine crosses in the first 40% of every 3.2 s, then rests off the card
		local cyc = (t % 3.2) / 3.2
		gloss.Position = UDim2.fromScale(cyc < 0.4 and (cyc / 0.4) * 1.6 - 0.3 or 1.4, 0.5)
		Gui.fade(glow, 0.35 + 0.45 * (0.5 + 0.5 * math.sin(t * 2.4)))
		for i, s in ipairs(sparks) do
			local k = 0.5 + 0.5 * math.sin(t * 3.1 + i * 1.9)
			s.scale.Scale = 0.2 + 0.9 * k * k
		end
		bigShine.Offset = Vector2.new(((t * 0.55) % 1.8) - 0.9, 0)
		local flap = math.sin(t * 1.7) * 3
		wingL.Rotation = flap
		wingR.Rotation = -flap
		-- (Aura) the colours turn round the edge; (Embers) the sparks rise and fade
		for _, g in ipairs(auraGrads) do
			g.Rotation = (t * 90) % 360
			g.Offset = Vector2.new(math.sin(t * 0.8) * 0.3, 0)
		end
		for _, e in ipairs(embers) do
			local k = (t * e.speed + e.phase) % 1
			e.frame.Position = UDim2.fromScale(e.x + math.sin(t * 2 + e.phase * 6) * 0.02, 1.05 - k * 1.15)
			e.frame.BackgroundTransparency = 0.1 + 0.9 * k * k
		end
		-- (Net) a lazy swing on its peg, with a little extra wobble now and then
		net.Rotation = math.sin(t * 1.3) * 3 + math.sin(t * 3.7) * 0.8
		-- (Pumpkin) a slow rock, and the candle inside flickering
		pumpkin.Rotation = math.sin(t * 1.1) * 4
		local flicker = 0.75 + 0.15 * math.sin(t * 13) + 0.1 * math.sin(t * 29 + 1.3)
		pumpkinImg.ImageColor3 = Color3.fromRGB(215, 175, 150):Lerp(Color3.new(1, 1, 1), flicker)
		pumpkinGlow.ImageTransparency = 0.75 - 0.4 * flicker
		-- the winter cards
		local wx = winterFx
		if wx then
			if wx.snowClip.Visible then
				for _, f in ipairs(wx.flakes) do
					local k = (t * f.speed + f.phase) % 1
					f.frame.Position = UDim2.fromScale(f.x + math.sin(t * 1.6 + f.phase * 6) * 0.03, -0.05 + k * 1.1)
				end
			end
			if wx.lights.Visible then
				for i, b in ipairs(wx.bulbs) do
					local on = math.sin(t * 3 + i * 1.7) > -0.2
					b.frame.BackgroundColor3 = on and b.color or b.color:Lerp(Color3.new(0, 0, 0), 0.6)
				end
			end
			wx.bigFlake.Rotation = (t * 12) % 360
			if wx.icicles.Visible then
				for i, ic in ipairs(wx.iceBits) do
					ic.ImageTransparency = 0.1 + 0.15 * (0.5 + 0.5 * math.sin(t * 2 + i))
				end
			end
			if wx.bells.Visible then
				for k, arm in ipairs(wx.bellArms) do
					arm.Rotation = math.sin(t * 3.2 + k * 1.3) * 16
				end
			end
			if wx.coal.Visible then
				wx.coalGlow.ImageTransparency = 0.45 + 0.25 * math.sin(t * 4)
				for i, e in ipairs(wx.embersC) do
					e.BackgroundTransparency = 0.5 + 0.5 * math.sin(t * 5 + i * 2)
				end
				for i, sm in ipairs(wx.smoke) do
					local k = (t * 0.35 + i / #wx.smoke) % 1
					sm.Position = UDim2.fromScale(0.5 + math.sin(t * 1.5 + i) * 0.12, 0.45 - k * 0.9)
					sm.Size = UDim2.fromScale(0.2 + k * 0.35, 0.2 + k * 0.35)
					sm.BackgroundTransparency = 0.55 + 0.45 * k
				end
			end
			if wx.gift.Visible then
				local hop = math.max(0, math.sin(t * 2.6)) ^ 6
				wx.lid.Position = UDim2.fromScale(0.5, 0.4 - 0.12 * hop)
				wx.lid.Rotation = math.sin(t * 2.6) * 6 * hop
			end
			if wx.auroraClip.Visible then
				for i, b in ipairs(wx.auroraBands) do
					b.grad.Offset = Vector2.new(math.sin(t * 0.5 + i * 1.2) * 0.25, 0)
					b.frame.Position = UDim2.fromScale(0.5 + math.sin(t * 0.3 + i) * 0.08, 0.3 + i * 0.12 + math.sin(t * 0.9 + i * 2) * 0.05)
				end
			end
			if wx.hat.Visible then
				wx.pom.Position = UDim2.fromScale(0.82 + math.sin(t * 2.2) * 0.04, 0.22 + math.abs(math.sin(t * 2.2)) * 0.03)
			end
		end
	end
	root.Destroying:Connect(function()
		if divineConn then
			divineConn:Disconnect()
			divineConn = nil
		end
	end)
	function card.set(look, data)
		data = data or {}
		local accent = look.Accent or Gui.SIGNAL
		edge.Visible = look.Edge ~= nil
		if look.Edge then
			Gui.tint(edge, look.Edge)
		end
		Gui.tint(base, look.Base or Gui.CARD)
		Gui.tint(sweep, look.Sweep or Gui.CHALK)
		for key, f in pairs(patterns) do
			f.Visible = key == (look.Pattern or "halftone")
		end
		for _, f in ipairs(tinted) do
			f.BackgroundColor3 = accent
		end
		local hasValue = type(data.value) == "string" and data.value ~= ""
		local bigOn = type(look.Big) == "string" and look.Big ~= ""
		local fx = look.Fx or {}
		-- (Net) the big word steps left, out from under the net
		local bigShift = (fx.Pumpkin == true and 96) or ((fx.Coal == true or fx.Gift == true or fx.Bells == true) and 80) or (fx.Net == true and 46) or 0 -- (clear of the jack-o'-lantern, the coal, the present, the bells)
		big.Visible = bigOn
		big.Text = bigOn and look.Big or ""
		big.Position = UDim2.new(1, -16 - bigShift, 0.5, 2)
		viewport.Visible = look.Avatar == true
		for _, c in ipairs(chevrons) do
			c.Visible = not hasValue and not bigOn
			Gui.tint(c, accent)
		end
		value.Visible, valueLabel.Visible = hasValue, hasValue
		local badgeImage = look.Badge and Assets.image(look.Badge) or nil
		rankBadge.Visible = badgeImage ~= nil
		rankBadge.Image = badgeImage or ""
		local badgeShift = badgeImage and math.floor(H * 0.95) or 0
		value.Position = UDim2.new(1, -26 - badgeShift, 0, 10)
		valueLabel.Position = UDim2.new(1, -28 - badgeShift, 0, 58)
		valueLabel.Size = UDim2.fromOffset(badgeImage and 230 or 170, 18)
		value.Text = hasValue and data.value or ""
		valueLabel.Text = data.label or ""
		valueLabel.TextColor3 = accent
		name.Size = UDim2.new(1, -x - badgeShift - ((hasValue or bigOn) and (bigOn and bigW + 24 + bigShift or 200) or 120), 0, 38)
		line.Size = UDim2.new(1, -x - badgeShift - ((hasValue or bigOn) and (bigOn and bigW + 24 + bigShift or 230) or 60), 0, 30)
		shot.Image = (data.userId or 0) > 0 and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", data.userId) or ""
		shot.Visible = look.Avatar ~= true -- the avatar takes the headshot's place
		shotEdge.Color = accent
		name.Text = data.name or ""
		setBadge(data.tier or "", data.tierColor or Gui.CHALK, false)
		line.Text = data.line or ""
		title.Visible = data.title ~= nil
		titleText.Text = data.title or ""
		Gui.tint(title, accent)
		tag.Visible = data.word ~= nil and data.word ~= ""
		word.Text = data.word or ""
		Gui.tint(tag, accent)
		-- the special cards' effects (Look.Fx: Wings, Crest, Glow, Halo, Shine, Sparkles, WordShine),
		-- the glow and the halo in the card's edge colour (a rank card's gold, silver or bronze)
		local shine = look.Edge or Color3.fromRGB(255, 214, 100)
		glow.Visible = fx.Glow == true
		Gui.tint(glow, shine)
		wingL.Visible, wingR.Visible, crest.Visible = fx.Wings == true and not noWings, fx.Wings == true and not noWings, fx.Crest == true
		divineClip.Visible = fx.Halo == true or fx.Shine == true
		for _, ray in ipairs(rays) do
			ray.Visible = fx.Halo == true
			ray.BackgroundColor3 = shine:Lerp(Color3.new(1, 1, 1), 0.3)
		end
		gloss.Visible = fx.Shine == true
		for _, s in ipairs(sparks) do
			s.frame.Visible = fx.Sparkles == true
		end
		bigShine.Enabled = fx.WordShine == true
		net.Visible = fx.Net == true
		pumpkin.Visible = fx.Pumpkin == true
		if not winterFx and (fx.Snowfall or fx.Lights or fx.Flake or fx.Icicles or fx.Bells or fx.Coal or fx.Gift or fx.Aurora or fx.SantaHat) then
			winterFx = buildWinterFx()
		end
		local wx = winterFx
		if wx then
			wx.snowCap.Visible, wx.snowClip.Visible = fx.Snowfall == true, fx.Snowfall == true
			wx.lights.Visible = fx.Lights == true
			wx.bigFlake.Visible = fx.Flake == true
			wx.icicles.Visible = fx.Icicles == true
			wx.bells.Visible = fx.Bells == true
			wx.coal.Visible = fx.Coal == true
			wx.gift.Visible = fx.Gift == true
			wx.auroraClip.Visible = fx.Aurora == true
			wx.hat.Visible = fx.SantaHat == true
		end
		aura.Visible = fx.Aura == true
		emberClip.Visible = fx.Embers == true
		local divine = next(fx) ~= nil
		if divine and not divineConn then
			divineConn = RunService.Heartbeat:Connect(divineStep)
			divineStep()
		elseif not divine and divineConn then
			divineConn:Disconnect()
			divineConn = nil
		end
	end
	return card
end

return Gui
