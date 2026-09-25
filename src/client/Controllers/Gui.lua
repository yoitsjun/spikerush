-- A small UI kit for the menus: one visual language everywhere.
--   * glass panels (dark, translucent, hairline border) over the 3D scenes
--   * gold primary buttons, white secondary buttons, flat tabs
--   * display titles in FredokaOne with a gold gradient and an ink outline, UI text in
--     Builder Sans
--   * icons drawn from GUI shapes (no uploaded images): home, recruit, players, locker, shop,
--     settings, help, back, the V Point volleyball and the Gold coin

local Gui = {}

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
