-- The match HUD, in the menus' broadcast kit (Gui): dark hairline cards, heavy italic
-- condensed type for names and numbers, slanted plates, signal yellow for the one thing that
-- matters. Team, stamina and ability colours carry the energy.
--
-- In play (laid out like The Spike's): a slanted scoreboard across the top (each team's name over
-- its stamina bar and timeout ticks, a signal-yellow VS plate with the points played to over it
-- and a white score box under each side); the attack readout under it (the km/h with small
-- decimals, and the hitting height); a point banner with gold edges and the reason; name tags
-- with tier badges and a marker over the player you control; the ability card top left; round
-- Timeout, Forfeit and Settings buttons top right; the control pills bottom left, each with its
-- key.
-- Out of a match the menus (MenuController) take over; this controller only lends them the
-- settings panel. The matchup intro and the showcase after a match are LineupController's.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Characters = require(Shared.Characters)
local Court = require(Shared.Court)
local Util = require(Shared.Util)
local Tutorial = require(Shared.Tutorial)
local HitLogic = require(Shared.HitLogic)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local UIController = {}
local mods

local player = Players.LocalPlayer
local UI = Config.UI
local ST = Config.Stamina
local THUNDER = Color3.fromRGB(255, 226, 60)
local AZURE = Color3.fromRGB(70, 210, 255)
local HOT = Color3.fromRGB(255, 50, 90)
local gui
local ui = {}
local tags = {}

------------------------------------------------------------------------------------------
-- builders
------------------------------------------------------------------------------------------

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function corner(parent, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, parent)
end

local function stroke(parent, thickness, color, transparency)
	return make("UIStroke", {
		Thickness = thickness or 2,
		Color = color or UI.Ink,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

-- A dark hairline card (edge() adds the hairline, or a coloured one).
local function panel(parent, props)
	local f = make("Frame", {
		BackgroundColor3 = Gui.CARD,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	corner(f, 6)
	return f
end

local function edge(f, color, transparency)
	return make("UIStroke", { Color = color or Gui.HAIRLINE, Thickness = 1, Transparency = transparency or 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
end

-- The old Gotham and Bangers faces map onto the kit's: Gotham Black and Bangers to the display
-- face (heavy italic condensed), Gotham Bold to the body face.
local function faceFor(font)
	if font == Enum.Font.GothamBlack or font == Enum.Font.Bangers then
		return Gui.display(Enum.FontWeight.Heavy)
	elseif font == Enum.Font.GothamBold then
		return Gui.body(Enum.FontWeight.Medium)
	end
	return nil
end

local function label(parent, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = UI.Chalk,
		FontFace = Gui.body(Enum.FontWeight.Medium),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props or {}) do
		if k == "Font" then
			l.FontFace = faceFor(v) or l.FontFace
		else
			l[k] = v
		end
	end
	return l
end

local function button(parent, text, props)
	local b = make("TextButton", {
		BackgroundColor3 = Color3.fromRGB(38, 42, 58),
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = text,
		TextColor3 = UI.Chalk,
		FontFace = Gui.display(),
		TextSize = 18,
	}, parent)
	for k, v in pairs(props or {}) do
		if k == "Font" then
			b.FontFace = faceFor(v) or b.FontFace
		else
			b[k] = v
		end
	end
	corner(b, 6)
	return b
end

-- The press sound (none when the button already sounded as it went down: Gui.pressSound).
local function click()
	Gui.click("UIClick")
end

local function teamColor(team)
	local t = Config.Teams[team or ""]
	return t and t.Color or UI.Chalk
end

local function teamName(team)
	local t = Config.Teams[team or ""]
	return t and t.Name or "?"
end

local function fmt2(x)
	return string.format("%.2f", x or 0)
end

------------------------------------------------------------------------------------------
-- top bar: team names, stamina, score, sets, timeouts
------------------------------------------------------------------------------------------

-- A team's wing of the scoreboard: a slanted dark plate, the name toward the VS plate, the stamina
-- bar under it and a tick per timeout left.
local function buildTeamBlock(parent, team, align)
	local right = align == "Right"
	local f = Gui.plate(parent, { Name = team, AnchorPoint = Vector2.new(right and 1 or 0, 0), Position = right and UDim2.fromScale(1, 0) or UDim2.new(), Size = UDim2.fromOffset(330, 60) }, Gui.CARD)
	Gui.fade(f, 0.16)
	local name = label(f, {
		Text = teamName(team),
		Font = Enum.Font.GothamBlack,
		TextSize = 21,
		TextColor3 = teamColor(team),
		Size = UDim2.new(1, -64, 0, 24),
		Position = UDim2.fromOffset(right and 26 or 38, 4),
		TextXAlignment = right and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
		ZIndex = 2,
	})
	stroke(name, 1.5, UI.Ink)
	local barX, barY = right and 22 or 34, 32
	local bar = make("Frame", {
		Size = UDim2.new(1, -56, 0, 10),
		Position = UDim2.fromOffset(barX, barY),
		BackgroundColor3 = Color3.fromRGB(10, 12, 26),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, f)
	local barStroke = make("UIStroke", { Thickness = 1, Color = UI.Fog, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bar)
	local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.Chalk, BorderSizePixel = 0, ZIndex = 2 }, bar)
	if right then
		fill.AnchorPoint = Vector2.new(1, 0)
		fill.Position = UDim2.fromScale(1, 0)
	end
	local broken = label(bar, {
		Text = "Broken",
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		TextColor3 = HOT,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 3,
	})
	local pips = make("Frame", { Size = UDim2.new(1, -56, 0, 5), Position = UDim2.fromOffset(barX, 48), BackgroundTransparency = 1, ZIndex = 2 }, f)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = right and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 5),
	}, pips)
	local pipList = {}
	for i = 1, math.max(Config.Timeout.PerSet, Config.Match.Custom.TimeoutsMax) do
		table.insert(pipList, make("Frame", { Size = UDim2.fromOffset(18, 5), BackgroundColor3 = Gui.SIGNAL, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 2 }, pips))
	end
	return { name = name, bar = bar, fill = fill, barStroke = barStroke, broken = broken, pips = pipList, barX = barX, barY = barY }
end

local function buildTopBar()
	local bar = make("Frame", { Name = "TopBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(820, 84), BackgroundTransparency = 1 }, gui)
	local home = buildTeamBlock(bar, "Home", "Left")
	local away = buildTeamBlock(bar, "Away", "Right")
	-- the centre: a signal-yellow VS plate with the points played to on a dark tag over it (it
	-- rises in a deuce), and a white score box under each side
	local mid = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(170, 84), BackgroundTransparency = 1, ZIndex = 3 }, bar)
	local vs = Gui.plate(mid, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(122, 42), ZIndex = 3 }, Gui.SIGNAL)
	label(vs, { Text = "VS", Font = Enum.Font.GothamBlack, TextSize = 30, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	local tag = Gui.plate(mid, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(58, 20), ZIndex = 4 }, Gui.LINE)
	local target = label(tag, { Text = "15", Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = Gui.SIGNAL, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	local function scoreBox(x)
		local box = Gui.plate(mid, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, 54), Size = UDim2.fromOffset(64, 30), ZIndex = 3 }, Gui.CHALK)
		return label(box, { Text = "0", Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	end
	local sHome = scoreBox(-36)
	local sAway = scoreBox(36)
	local setLine = label(bar, { Text = "", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = UI.Fog, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 88), TextXAlignment = Enum.TextXAlignment.Center })
	stroke(setLine, 1, UI.Ink, 0.4)
	-- who serves: a small ball beside that team's score box
	local serveDot = Gui.icon.vp(bar, 20)
	serveDot.ZIndex = 5
	-- the attack readout under the scoreboard: "129.75 km/h   3.85 m"
	local readout = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.fromOffset(440, 42), BackgroundTransparency = 1 }, gui)
	local kmh = label(readout, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 36, RichText = true, Size = UDim2.new(0.6, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	stroke(kmh, 2, UI.Ink)
	local height = label(readout, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 32, RichText = true, TextColor3 = UI.Fog, Size = UDim2.new(0.38, 0, 1, 0), Position = UDim2.fromScale(0.62, 0) })
	stroke(height, 2, UI.Ink)
	ui.top = { bar = bar, Home = home, Away = away, sHome = sHome, sAway = sAway, setLine = setLine, serveDot = serveDot, readout = readout, kmh = kmh, height = height, shownAt = -10, target = target, diamond = vs, tag = tag }
end

local function refreshTopBar()
	local m = State.match
	local t = ui.top
	local scores = m.scores or { Home = 0, Away = 0 }
	local sets = m.sets or { Home = 0, Away = 0 }
	t.sHome.Text = tostring(scores.Home or 0)
	t.sAway.Text = tostring(scores.Away or 0)
	t.sHome.TextColor3 = teamColor("Home")
	t.sAway.TextColor3 = teamColor("Away")
	local playTo, deuce = Court.playTo(scores.Home or 0, scores.Away or 0, m.target or Config.Match.PointsPerSet, m.winBy)
	t.target.Text = tostring(playTo)
	if deuce then
		t.setLine.Text = string.format("DEUCE, win by %d   set %d", m.winBy or Config.Match.WinBy, m.setNumber or 1)
		t.setLine.TextColor3 = UI.Whistle
		Gui.tint(t.diamond, UI.Whistle)
	else
		t.setLine.Text = string.format("Set %d   sets %d-%d", m.setNumber or 1, sets.Home or 0, sets.Away or 0)
		t.setLine.TextColor3 = UI.Fog
		Gui.tint(t.diamond, Gui.SIGNAL)
	end
	if m.servingTeam == "Away" then
		t.serveDot.Position = UDim2.fromOffset(410 + 36 + 38, 59)
	else
		t.serveDot.Position = UDim2.fromOffset(410 - 36 - 38 - 20, 59)
	end
	-- someone else's match on this court stays out of the menus
	local mine = m.inMatch == true and State.isPlaying
	t.serveDot.Visible = mine
	t.bar.Visible = mine
	t.readout.Visible = mine -- the last attack stays off the menus (benched, or someone else's match)
end

local function updateStamina()
	local now = os.clock()
	for _, team in ipairs(Config.TeamOrder) do
		local block = ui.top[team]
		local s = State.stamina(team)
		local pct = s.max > 0 and math.clamp(s.value / s.max, 0, 1) or 0
		block.fill.Size = UDim2.fromScale(pct, 1)
		-- a guard hit shakes the bar for a moment
		local hit = block.hitAt and now - block.hitAt < 0.4
		if hit then
			local k = 1 - (now - block.hitAt) / 0.4
			block.bar.Position = UDim2.fromOffset(block.barX + math.sin(now * 90) * 4 * k * block.hitSize, block.barY)
		else
			block.bar.Position = UDim2.fromOffset(block.barX, block.barY)
		end
		local broken = s.value <= 0
		block.broken.Visible = broken
		if broken then
			block.barStroke.Color = HOT
			block.barStroke.Transparency = 0.5 + 0.5 * math.sin(now * 10)
		elseif pct < ST.RedAt then
			block.fill.BackgroundColor3 = HOT
			block.barStroke.Color = HOT
			block.barStroke.Transparency = 0.3
		else
			block.fill.BackgroundColor3 = UI.Chalk
			block.barStroke.Color = UI.Fog
			block.barStroke.Transparency = 0.4
		end
		local left = State.timeouts(team)
		local allowed = State.match.timeouts or Config.Timeout.PerSet
		for i, p in ipairs(block.pips) do
			p.Visible = i <= allowed
			p.BackgroundTransparency = i <= left and 0 or 0.8
		end
	end
end

local function showReadout(meta)
	local t = ui.top
	local color = UI.Chalk
	if meta.thunder then
		color = THUNDER
	elseif meta.energy then
		color = AZURE
	elseif (meta.kmh or 0) >= 120 then
		color = HOT
	end
	local function split(x, unit, small)
		local whole, dec = string.match(fmt2(x), "^(%d+)%.(%d+)$")
		return string.format('%s<font size="%d">.%s %s</font>', whole or "0", small, dec or "00", unit)
	end
	t.kmh.Text = split(meta.kmh, "km/h", 22)
	t.kmh.TextColor3 = color
	t.kmh.TextTransparency = 0
	t.height.Text = meta.height and split(meta.height, "m", 20) or ""
	t.height.TextColor3 = meta.thunder and THUNDER or UI.Fog
	t.height.TextTransparency = 0
	t.shownAt = os.clock()
	local s = make("UIScale", { Scale = 1.35 }, t.kmh)
	TweenService:Create(s, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.25, function()
		s:Destroy()
	end)
end

local function updateReadout()
	local t = ui.top
	local age = os.clock() - t.shownAt
	-- stays readable for a few seconds, then settles to a dim "last attack"
	local a = math.clamp((age - 3) / 0.6, 0, 1) * 0.55
	t.kmh.TextTransparency = a
	t.height.TextTransparency = a
end

------------------------------------------------------------------------------------------
-- banner, callouts, hints
------------------------------------------------------------------------------------------

local REASON = {
	Spike = "Spike",
	Feint = "Feint",
	Ace = "Service ace",
	Stuff = "Stuff block",
	Block = "Block",
	Tooled = "Block out",
	["Free ball"] = "Free ball",
	Break = "Guard break",
	Out = "Out",
	Net = "Net",
	Drop = "Drop",
	ServiceFault = "Service fault",
	ServeClock = "Serve clock",
	Fault = "Fault",
	Point = "Point",
}

-- "Home (Riku) scored" on a dark bar with a gold edge, and the reason on a tag in the scorer's
-- colour, like a broadcast lower third.
local function buildBanner()
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 156),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Gui.CARD,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	edge(f, Gui.HAIRLINE, 0.1)
	make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 8) }, f)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, f)
	local text = make("TextLabel", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 46),
		RichText = true,
		FontFace = Gui.display(Enum.FontWeight.Heavy),
		TextSize = 24,
		TextColor3 = UI.Chalk,
		LayoutOrder = 1,
	}, f)
	local tag = make("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundColor3 = UI.Chalk,
		BorderSizePixel = 0,
		TextColor3 = UI.Ink,
		FontFace = Gui.display(Enum.FontWeight.Heavy),
		TextSize = 18,
		LayoutOrder = 2,
	}, f)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, tag)
	ui.banner = { frame = f, text = text, tag = tag, token = 0 }
end

local function hex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function showBanner(a)
	local b = ui.banner
	b.token = b.token + 1
	local token = b.token
	local who = ""
	if a.scorerName then
		who = " (" .. a.scorerName .. ")"
	end
	b.text.Text = string.format('<font color="%s">%s</font>%s scored', hex(teamColor(a.winner)), teamName(a.winner), who)
	b.tag.Text = REASON[a.reason] or tostring(a.reason or "Point")
	b.tag.BackgroundColor3 = a.error and UI.Fog or teamColor(a.winner)
	b.tag.TextColor3 = a.error and UI.Ink or UI.Chalk
	b.frame.Visible = true
	b.frame.Position = UDim2.new(0.5, 0, 0, 144)
	TweenService:Create(b.frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 156) }):Play()
	task.delay(Config.Match.PointPauseTime - 0.3, function()
		if token == b.token then
			b.frame.Visible = false
		end
	end)
end

local calloutToken = 0

function UIController.callout(text, color, sub, duration)
	calloutToken = calloutToken + 1
	local token = calloutToken
	local c = ui.callout
	c.main.Text = text
	c.main.TextColor3 = color or UI.Chalk
	c.main.TextTransparency = 0
	c.mainStroke.Transparency = 0
	c.sub.Text = sub or ""
	c.sub.TextTransparency = 0
	c.scale.Scale = 1.7
	c.frame.Rotation = -4
	c.frame.Visible = true
	TweenService:Create(c.scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(c.frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Rotation = -2 }):Play()
	task.delay(duration or 1.35, function()
		if token ~= calloutToken then
			return
		end
		local fade = TweenInfo.new(0.25)
		TweenService:Create(c.main, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(c.mainStroke, fade, { Transparency = 1 }):Play()
		TweenService:Create(c.sub, fade, { TextTransparency = 1 }):Play()
		task.delay(0.26, function()
			if token == calloutToken then
				c.frame.Visible = false
			end
		end)
	end)
end

local function buildCallout()
	local frame = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(700, 130),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local scale = make("UIScale", {}, frame)
	local main = label(frame, {
		Text = "",
		Font = Enum.Font.Bangers,
		TextSize = 80,
		Size = UDim2.new(1, 0, 0, 90),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local mainStroke = stroke(main, 5, UI.Ink)
	local sub = label(frame, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 90),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	stroke(sub, 2.5, UI.Ink)
	ui.callout = { frame = frame, scale = scale, main = main, mainStroke = mainStroke, sub = sub }
end

local hintToken = 0
local function showHint(text)
	hintToken = hintToken + 1
	local token = hintToken
	ui.hint.Text = "  " .. text .. "  "
	ui.hint.Visible = true
	ui.hint.TextTransparency = 0
	ui.hint.BackgroundTransparency = 0.15
	task.delay(1.8, function()
		if token ~= hintToken then
			return
		end
		TweenService:Create(ui.hint, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	end)
end

local function buildHint()
	ui.hint = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Gui.CARD,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		TextColor3 = UI.Chalk,
		FontFace = Gui.display(),
		TextSize = 19,
		Visible = false,
	}, gui)
	corner(ui.hint, 6)
end

------------------------------------------------------------------------------------------
-- name tags: tier badge, height, and a marker over the player you control
------------------------------------------------------------------------------------------

local function tagFor(model)
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not head then
		return nil
	end
	local bb = make("BillboardGui", {
		Name = "SpikeRushTag",
		Size = UDim2.fromOffset(150, 58),
		StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 220,
		Adornee = head,
	}, head)
	local mark = label(bb, {
		Text = "▼",
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		TextColor3 = Color3.fromRGB(70, 150, 255),
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 38),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})
	stroke(mark, 2, UI.Ink)
	local row = make("Frame", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 16), BackgroundTransparency = 1 }, bb)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local badge = make("TextLabel", {
		Size = UDim2.fromOffset(28, 18),
		BackgroundColor3 = UI.Chalk,
		TextColor3 = UI.Ink,
		FontFace = Gui.display(Enum.FontWeight.Heavy),
		TextSize = 14,
		LayoutOrder = 1,
	}, row)
	corner(badge, 4)
	local name = make("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		BackgroundTransparency = 1,
		TextColor3 = UI.Chalk,
		FontFace = Gui.display(Enum.FontWeight.Heavy),
		TextSize = 16,
		LayoutOrder = 2,
	}, row)
	stroke(name, 1.5, UI.Ink)
	local sub = label(bb, {
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = UI.Fog,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	stroke(sub, 1, UI.Ink)
	return { bb = bb, mark = mark, badge = badge, name = name, sub = sub, model = model }
end

local function allModels()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			table.insert(list, { model = plr.Character, name = plr.DisplayName, me = plr == player })
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, m in ipairs(bots:GetChildren()) do
			local hum = m:FindFirstChildOfClass("Humanoid")
			table.insert(list, { model = m, name = hum and hum.DisplayName or m.Name, bot = true })
		end
	end
	return list
end

local function refreshTags()
	local seen = {}
	for _, info in ipairs(allModels()) do
		local m = info.model
		seen[m] = true
		local t = tags[m]
		if not t or not t.bb.Parent then
			t = tagFor(m)
			tags[m] = t
		end
		if t then
			local tier = m:GetAttribute("Tier")
			local team = m:GetAttribute("Team")
			t.badge.Text = tier or "?"
			t.badge.BackgroundColor3 = Characters.color(tier)
			t.name.Text = info.name
			t.name.TextColor3 = team and teamColor(team) or UI.Chalk
			local h = m:GetAttribute("Height")
			local ability = m:GetAttribute("Ability")
			local abilityName = ability and Config.Abilities[ability] and Config.Abilities[ability].Name or ""
			local charName = m:GetAttribute("CharName")
			local who = (charName and charName ~= info.name) and (charName .. "   ") or ""
			if h then
				t.sub.Text = string.format("%s%d cm   %s", who, h, abilityName)
			else
				t.sub.Text = who .. abilityName
			end
			t.mark.Visible = info.me == true and State.isPlaying
		end
	end
	for m, t in pairs(tags) do
		if not seen[m] then
			if t and t.bb then
				t.bb:Destroy()
			end
			tags[m] = nil
		end
	end
end

------------------------------------------------------------------------------------------
-- ability panel and charge bars
------------------------------------------------------------------------------------------

local function buildAbility()
	local f = panel(gui, {
		Name = "Ability",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(250, 66),
		Visible = false,
	})
	edge(f)
	local name = label(f, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 15,
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 6),
	})
	local line = label(f, {
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = UI.Fog,
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.fromOffset(10, 26),
	})
	local bar = make("Frame", {
		Size = UDim2.new(1, -20, 0, 10),
		Position = UDim2.fromOffset(10, 46),
		BackgroundColor3 = Color3.fromRGB(10, 12, 26),
		BorderSizePixel = 0,
	}, f)
	corner(bar, 5)
	local gauge = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(40, 110, 255), BorderSizePixel = 0 }, bar)
	corner(gauge, 5)
	local energy = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = AZURE, BorderSizePixel = 0 }, bar)
	corner(energy, 5)
	-- level notches (Rising Sun's Sunrise levels)
	local ticks = {}
	for i = 1, 3 do
		table.insert(ticks, make("Frame", {
			Size = UDim2.new(0, 2, 1, 0),
			Position = UDim2.fromScale(i / 4, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = UI.Ink,
			BorderSizePixel = 0,
			ZIndex = 3,
			Visible = false,
		}, bar))
	end
	-- optional Toolbox icon (Assets.Images.Ability<Name>) to the left of the text
	local icon = make("ImageLabel", {
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(8, 6),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
	}, f)
	-- a teammate's (or your own) Rally Cry: a gold tag under the panel while it lasts
	local rally = label(f, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 13,
		TextColor3 = Config.Abilities.RallyCry.Color,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 4, 1, 4),
		Visible = false,
	})
	stroke(rally, 1.5, UI.Ink)
	ui.ability = { frame = f, name = name, line = line, bar = bar, gauge = gauge, energy = energy, icon = icon, ticks = ticks, rally = rally, e = 0, g = 1, st = "idle" }

	-- overhead bar for toss height, block charge and Azure energy
	-- a BillboardGui only renders straight under PlayerGui (or in the world), never inside a ScreenGui
	ui.overhead = make("BillboardGui", {
		Name = "SpikeRushCharge",
		Size = UDim2.fromOffset(110, 26),
		StudsOffsetWorldSpace = Vector3.new(0, 5.6, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	local ob = make("Frame", {
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.fromOffset(0, 14),
		BackgroundColor3 = UI.Ink,
		BorderSizePixel = 0,
	}, ui.overhead)
	corner(ob, 5)
	stroke(ob, 1.5, UI.Chalk, 0.3)
	ui.overFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.Chalk, BorderSizePixel = 0 }, ob)
	corner(ui.overFill, 5)
	ui.overText = label(ui.overhead, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	stroke(ui.overText, 1.5, UI.Ink)
end

local ACTIVE_TEXT = {
	IronWall = "Wall up: everything at your hands is stuffed",
	Turnabout = "Armed: jump for your next set, it spins over",
	RallyCry = "Rally Cry: your whole team is fired up",
}
local READY_TEXT = {
	IronWall = "Ready: press Q (L2) before you block",
	Turnabout = "Ready: press Q (L2) before your set",
	RallyCry = "Ready: press Q (L2) to fire up your team",
}

local function updateAbility()
	local a = ui.ability
	local playing = State.isPlaying and State.match.inMatch
	local ability = State.myAbility()
	local def = ability and Config.Abilities[ability]
	a.frame.Visible = playing == true
	local stats = State.myStats()
	local charName = player:GetAttribute("CharName") or ""
	for _, tick in ipairs(a.ticks) do
		tick.Visible = false
	end
	local rallyLeft = (ReplicatedStorage:GetAttribute("RallyUntil_" .. tostring(State.myTeam)) or -1) - Util.now()
	a.rally.Visible = playing == true and rallyLeft > 0
	if a.rally.Visible then
		a.rally.Text = string.format("RALLY CRY  +%d%% all stats  %d s", Config.Abilities.RallyCry.Boost * 100, math.ceil(rallyLeft))
	end
	if not def then
		-- no ability (below S tier): just who you're playing and your hitting point
		a.name.Text = charName
		a.name.TextColor3 = Characters.color(player:GetAttribute("Tier"))
		a.line.Text = string.format("%s, hitting point %s m", tostring(player:GetAttribute("Tier") or ""), fmt2(stats.ContactMaxM))
		a.line.TextColor3 = UI.Fog
		a.icon.Visible = false
		a.bar.Visible = false
		a.frame.Size = UDim2.fromOffset(250, 48)
		a.name.Position = UDim2.fromOffset(10, 6)
		a.line.Position = UDim2.fromOffset(10, 26)
		return
	end
	a.name.Text = def.Name .. "  " .. charName
	a.name.TextColor3 = def.Color
	local iconId = Assets.id(Assets.Images["Ability" .. ability])
	a.icon.Visible = iconId ~= nil
	if iconId then
		a.icon.Image = iconId
	end
	local textX = iconId and 52 or 10
	a.name.Position = UDim2.fromOffset(textX, 6)
	a.name.Size = UDim2.new(1, -textX - 10, 0, 20)
	a.line.Position = UDim2.fromOffset(textX, 26)
	a.line.Size = UDim2.new(1, -textX - 10, 0, 16)
	a.bar.Visible = false
	a.frame.Size = UDim2.fromOffset(250, 48)
	if ability == "Thunder" then
		if stats.ContactMaxM >= Config.Hits.ThunderHeight then
			a.line.Text = "Hitting point " .. fmt2(stats.ContactMaxM) .. " m, thunder in reach"
			a.line.TextColor3 = THUNDER
		else
			a.line.Text = "Hitting point " .. fmt2(stats.ContactMaxM) .. " m, needs 4.00 m"
			a.line.TextColor3 = UI.Fog
		end
	elseif ability == "Adrenaline" then
		local on = player.Character and player.Character:GetAttribute("Adrenaline")
		if on then
			a.line.Text = "Active: more Attack and Jump"
			a.line.TextColor3 = def.Color
		else
			a.line.Text = string.format("Wakes up below %d%% stamina", def.StaminaBelow * 100)
			a.line.TextColor3 = UI.Fog
		end
	elseif def.Active then
		-- Iron Wall, Turnabout, Rally Cry: a key press, a window, a cooldown
		local AC = mods.ActionController
		a.bar.Visible = true
		a.frame.Size = UDim2.fromOffset(250, 66)
		a.gauge.BackgroundColor3 = def.Color:Lerp(UI.Ink, 0.75)
		a.energy.BackgroundColor3 = def.Color
		local left = AC.abilityCooldown()
		if AC.abilityActive() then
			a.line.Text = ACTIVE_TEXT[ability] or (def.Name .. " is on")
			a.line.TextColor3 = def.Color
			a.energy.Size = UDim2.fromScale(1, 1)
		elseif left > 0 then
			a.line.Text = string.format("Ready in %d s", math.ceil(left))
			a.line.TextColor3 = UI.Fog
			a.energy.Size = UDim2.fromScale(1 - left / def.Cooldown, 1)
		else
			a.line.Text = READY_TEXT[ability] or "Ready: press Q (L2)"
			a.line.TextColor3 = def.Color
			a.energy.Size = UDim2.fromScale(1, 1)
		end
		a.gauge.Size = UDim2.fromScale(1, 1)
	elseif ability == "ChainReaction" then
		a.line.Text = "Your sets are charged: the next spike explodes"
		a.line.TextColor3 = def.Color
	elseif ability == "Vector" then
		a.line.Text = string.format("Your sets pulse: steep spikes off them, up to +%d%%", def.MaxBoost * 100)
		a.line.TextColor3 = def.Color
	elseif ability == "RisingSun" then
		-- the Sunrise meter: every Every points the other team scores is a level
		local pts = State.enemyPoints(State.myTeam)
		local lvl = HitLogic.sunLevel(pts)
		local cap = def.Every * def.MaxLevel
		a.bar.Visible = true
		a.frame.Size = UDim2.fromOffset(250, 66)
		a.gauge.BackgroundColor3 = def.Color:Lerp(UI.Ink, 0.55)
		a.gauge.Size = UDim2.fromScale(math.min(pts, cap) / cap, 1)
		a.energy.BackgroundColor3 = def.Color
		a.energy.Size = UDim2.fromScale(lvl / def.MaxLevel, 1)
		for _, tick in ipairs(a.ticks) do
			tick.Visible = true
		end
		if lvl >= def.MaxLevel then
			a.line.Text = string.format("Sunrise Lv %d/%d: full blaze", lvl, def.MaxLevel)
		else
			local need = (lvl + 1) * def.Every - pts
			a.line.Text = string.format("Sunrise Lv %d/%d, next in %d point%s", lvl, def.MaxLevel, need, need == 1 and "" or "s")
		end
		a.line.TextColor3 = lvl > 0 and def.Color or UI.Fog
	elseif ability == "Counter" then
		local c = player:GetAttribute("Counter") or 0
		a.bar.Visible = true
		a.frame.Size = UDim2.fromOffset(250, 66)
		a.gauge.BackgroundColor3 = def.Color:Lerp(UI.Ink, 0.8)
		a.gauge.Size = UDim2.fromScale(1, 1)
		a.energy.BackgroundColor3 = def.Color
		a.energy.Size = UDim2.fromScale(math.clamp(c / 100, 0, 1), 1)
		if c > 0 then
			local k = math.clamp(c, 0, 100) / 100
			a.line.Text = string.format("Counter %d%%: spike +%d%%, +%d ATK", c, math.floor(def.ReleaseBoost * 100 * k + 0.5), math.floor(def.PerFull.Attack * k + 0.5))
			a.line.TextColor3 = def.Color
		else
			a.line.Text = "Dig their balls to fill it (spikes cost no stamina)"
			a.line.TextColor3 = UI.Fog
		end
	else
		a.bar.Visible = true
		a.frame.Size = UDim2.fromOffset(250, 66)
		a.gauge.BackgroundColor3 = Color3.fromRGB(40, 110, 255)
		a.gauge.Size = UDim2.fromScale(math.clamp(a.g, 0, 1), 1)
		a.energy.Size = UDim2.fromScale(math.clamp(a.e, 0, 1), 1)
		if a.st == "over" then
			a.line.Text = "Overcharged, release!"
			a.line.TextColor3 = HOT
			a.energy.BackgroundColor3 = HOT
		elseif a.st == "full" then
			a.line.Text = "Full energy"
			a.line.TextColor3 = AZURE
			a.energy.BackgroundColor3 = Color3.fromRGB(190, 250, 255)
		elseif a.st == "charging" then
			a.line.Text = "Gathering energy " .. math.floor(a.e * 100 + 0.5) .. "%"
			a.line.TextColor3 = AZURE
			a.energy.BackgroundColor3 = AZURE
		else
			a.line.Text = "Hold Spike in the air to charge"
			a.line.TextColor3 = UI.Fog
			a.energy.BackgroundColor3 = AZURE
		end
	end
end

local function updateOverhead()
	local c = player.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local AC = mods.ActionController
	local toss = AC.tossCharge()
	local blockC = AC.blockCharge()
	local a = ui.ability
	local value, text, color = nil, "", UI.Chalk
	if toss then
		value, text, color = toss, toss <= 0 and "Overhand" or "Toss height", UI.Spark
	elseif blockC then
		value, text, color = blockC, "Block", UI.Chalk
	elseif a.st ~= "idle" then
		value = a.e
		text = a.st == "over" and "Over!" or (a.st == "full" and "Full" or "Energy")
		color = a.st == "over" and HOT or AZURE
	end
	if value and hrp then
		ui.overhead.Adornee = hrp
		ui.overhead.Enabled = true
		ui.overFill.Size = UDim2.fromScale(math.clamp(value, 0.02, 1), 1)
		ui.overFill.BackgroundColor3 = color
		ui.overText.Text = text
		ui.overText.TextColor3 = color
	else
		ui.overhead.Enabled = false
	end
end

------------------------------------------------------------------------------------------
-- control rail (left edge): every action as a round button with its key, lit when it's live
------------------------------------------------------------------------------------------

local RAIL = {
	{ action = "Spike", key = "Z", pad = "A", color = Color3.fromRGB(235, 70, 60) },
	{ action = "Receive", key = "S", pad = "B", color = Color3.fromRGB(50, 130, 235) },
	{ action = "SlideFeint", key = "C", pad = "RB", color = Color3.fromRGB(70, 180, 140) },
	{ action = "Block", key = "W", pad = "Y", color = Color3.fromRGB(120, 110, 220) },
	{ action = "Set", key = "E", pad = "LB", color = Color3.fromRGB(240, 170, 60) },
	{ action = "Serve", key = "X", pad = "X", color = Color3.fromRGB(245, 200, 40) },
	{ action = "EasyServe", key = "F", pad = "Up", color = Color3.fromRGB(255, 232, 150) },
	{ action = "Ability", key = "Q", pad = "L2", color = Color3.fromRGB(150, 205, 255) },
}

local function buildRail()
	local rail = make("Frame", {
		Name = "ControlRail",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(150, #RAIL * 38),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	ui.railScale = make("UIScale", {}, rail)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, rail)
	local slots = {}
	for i, def in ipairs(RAIL) do
		-- a compact pill: key badge + action name
		local b = make("TextButton", {
			Name = def.action,
			Size = UDim2.fromOffset(150, 33),
			BackgroundColor3 = UI.Ink,
			BackgroundTransparency = 0.3,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
		}, rail)
		corner(b, 6)
		local ring = make("UIStroke", { Thickness = 1, Color = UI.Chalk, Transparency = 0.7, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local badge = make("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -5, 0.5, 0),
			Size = UDim2.fromOffset(36, 23),
			BackgroundColor3 = UI.Chalk,
			TextColor3 = UI.Ink,
			FontFace = Gui.display(Enum.FontWeight.Heavy),
			TextSize = 14,
			Text = def.key,
		}, b)
		corner(badge, 4)
		local name = label(b, {
			Text = def.action,
			Font = Enum.Font.GothamBlack,
			TextSize = 17,
			Size = UDim2.new(1, -52, 1, 0),
			Position = UDim2.fromOffset(12, 0),
		})
		-- mouse users can click the rail too
		b.MouseButton1Down:Connect(function()
			mods.ActionController.press(def.action)
		end)
		local function up()
			mods.ActionController.release(def.action)
		end
		b.MouseButton1Up:Connect(up)
		b.MouseLeave:Connect(up)
		slots[def.action] = { slot = b, button = b, ring = ring, badge = badge, name = name, def = def }
	end
	ui.rail = { frame = rail, slots = slots }
end

local RAIL_NAMES = {
	SlideFeint = function(ctx)
		return ctx.grounded == false and "Feint" or "Slide"
	end,
	Spike = function(ctx)
		return ctx.spikeLabel or "Spike"
	end,
	EasyServe = function()
		return "Easy serve"
	end,
}

local function updateRail()
	local r = ui.rail
	local show = not State.isMobile and State.isPlaying and State.match.inMatch == true
	r.frame.Visible = show
	if not show then
		return
	end
	local cam = workspace.CurrentCamera
	if cam then
		ui.railScale.Scale = math.clamp(cam.ViewportSize.Y / 760, 0.62, 1.1)
	end
	local ctx = State.context or {}
	local pad = mods.InputController.lastDevice() == "Gamepad"
	local live = {
		Spike = ctx.inZone == true or ctx.running == true or (ctx.serving == true and ctx.spikeLabel ~= nil),
		Receive = ctx.incoming == true and ctx.grounded == true,
		SlideFeint = (ctx.incoming == true and ctx.grounded == true) or (ctx.grounded == false and ctx.inZone == true),
		Block = ctx.nearNet == true and ctx.grounded == true and not ctx.serving,
		Set = ctx.canSet == true,
		Serve = ctx.serving == true,
		EasyServe = ctx.serving == true and ctx.spikeLabel == "Toss",
		Ability = mods.ActionController.abilityCooldown() <= 0 and not mods.ActionController.abilityActive(),
	}
	local abilityDef = Config.Abilities[State.myAbility() or ""]
	for action, sl in pairs(r.slots) do
		local def = sl.def
		sl.slot.Visible = ((action ~= "Serve" and action ~= "EasyServe") or ctx.serving == true) and (action ~= "Ability" or (abilityDef ~= nil and abilityDef.Active == true))
		sl.badge.Text = pad and def.pad or def.key
		local namer = RAIL_NAMES[action]
		sl.name.Text = namer and namer(ctx) or (action == "SlideFeint" and "Slide" or action)
		if live[action] then
			sl.ring.Color = def.color
			sl.ring.Thickness = 2
			sl.ring.Transparency = 0
			sl.button.BackgroundColor3 = def.color:Lerp(UI.Ink, 0.6)
			sl.badge.BackgroundColor3 = def.color
			sl.name.TextColor3 = UI.Chalk
		else
			sl.ring.Color = UI.Chalk
			sl.ring.Thickness = 1
			sl.ring.Transparency = 0.7
			sl.button.BackgroundColor3 = UI.Ink
			sl.badge.BackgroundColor3 = UI.Chalk
			sl.name.TextColor3 = UI.Fog
		end
	end
end

------------------------------------------------------------------------------------------
-- after a set: keep playing for the extra set rewards, or end the match
------------------------------------------------------------------------------------------

local function buildContinue()
	local f = panel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromOffset(540, 200), Visible = false })
	edge(f, Gui.SIGNAL, 0.1)
	ui.againScale = make("UIScale", {}, f)
	local title = label(f, { Text = "Keep playing?", Font = Enum.Font.GothamBlack, TextSize = 24, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 10), TextXAlignment = Enum.TextXAlignment.Center })
	local offer = label(f, { Text = "", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = UI.Fog, TextWrapped = true, RichText = true, Size = UDim2.new(1, -32, 0, 40), Position = UDim2.fromOffset(16, 44), TextXAlignment = Enum.TextXAlignment.Center })
	local keep = button(f, "Keep playing", { Size = UDim2.fromOffset(230, 46), Position = UDim2.new(0.5, -238, 0, 94), BackgroundColor3 = UI.Spark, TextColor3 = UI.Ink, TextSize = 17 })
	local stop = button(f, "End match", { Size = UDim2.fromOffset(230, 46), Position = UDim2.new(0.5, 8, 0, 94), TextSize = 17 })
	local status = label(f, { Text = "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = UI.Fog, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 1, -28), TextXAlignment = Enum.TextXAlignment.Center })
	Gui.pressSound(keep)
	Gui.pressSound(stop)
	keep.MouseButton1Click:Connect(function()
		click()
		ui.again.voted = true
		Net.get("Continue"):FireServer(true)
	end)
	stop.MouseButton1Click:Connect(function()
		click()
		ui.again.voted = false
		Net.get("Continue"):FireServer(false)
	end)
	ui.again = { frame = f, title = title, offer = nil, offerLabel = offer, keep = keep, stop = stop, status = status }
end

local function updateContinue()
	local c = ui.again
	local show = State.isPlaying and State.phase() == "Continue"
	c.frame.Visible = show
	if not show then
		return
	end
	local cam = workspace.CurrentCamera
	if cam then
		ui.againScale.Scale = math.clamp(cam.ViewportSize.Y / 760, 0.62, 1.1)
	end
	local o = c.offer or {}
	c.offerLabel.Text = string.format("Another set pays <b>+%d VP, +%d Gold</b> if you win it (+%d VP, +%d Gold if you lose), on top of the match reward.", o.winVP or 0, o.winGold or 0, o.lossVP or 0, o.lossGold or 0)
	local left = math.max(0, math.ceil((State.match.phaseEnd or 0) - Util.now()))
	local v = State.match.continueVote
	local tally = v and string.format("   Keep playing %d, end %d (of %d)", v[1] or 0, v[2] or 0, v[3] or 0) or ""
	c.status.Text = string.format("%ds%s", left, tally)
	c.keep.BackgroundColor3 = c.voted == true and UI.Mint or UI.Spark
	c.stop.BackgroundColor3 = c.voted == false and UI.Whistle or UI.InkSoft
end

------------------------------------------------------------------------------------------
-- the tutorial coach: the current step, how to do it, and the checklist
------------------------------------------------------------------------------------------

-- The coach, top right while you practise (a drill, or the tutorial's four): what the drill is,
-- how to do it on your device, and a dot per rep of the goal (for an in-a-row drill a miss
-- empties them). "Back to the menu" ends practice (the forfeit request).
local function buildCoach()
	local f = panel(gui, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 104), Size = UDim2.fromOffset(360, 214), Visible = false })
	edge(f, Gui.SIGNAL, 0.1)
	ui.coachScale = make("UIScale", {}, f)
	local head = label(f, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = UI.Spark, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 10) })
	local title = label(f, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 24, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 28) })
	local body = label(f, { Text = "", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = UI.Fog, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -24, 0, 60), Position = UDim2.fromOffset(12, 60) })
	local row = make("Frame", { Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 128), BackgroundTransparency = 1 }, f)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local dots = {}
	for i = 1, 5 do
		local d = make("Frame", { Size = UDim2.fromOffset(20, 20), BackgroundColor3 = UI.InkSoft, BorderSizePixel = 0, LayoutOrder = i }, row)
		corner(d, 10)
		dots[i] = d
	end
	local streak = label(row, { Text = "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = UI.Fog, Size = UDim2.fromOffset(120, 20), LayoutOrder = 10 })
	local leave = button(f, "Back to the menu", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 1, -44), BackgroundColor3 = UI.InkSoft, TextColor3 = UI.Chalk, TextSize = 15 })
	Gui.pressSound(leave)
	leave.MouseButton1Click:Connect(function()
		click()
		Net.get("Forfeit"):FireServer()
	end)
	ui.coach = { frame = f, head = head, title = title, body = body, dots = dots, streak = streak, leave = leave }
end

local function updateCoach()
	local c = ui.coach
	local pr = State.isPlaying and State.match.practice
	c.frame.Visible = type(pr) == "table"
	if type(pr) ~= "table" then
		return
	end
	local cam = workspace.CurrentCamera
	if cam then
		ui.coachScale.Scale = math.clamp(cam.ViewportSize.Y / 760, 0.62, 1.1)
	end
	local d = Tutorial.drill(pr.drill)
	if pr.finished or not d then
		c.head.Text = pr.tutorial and "TUTORIAL COMPLETE" or "DRILL COMPLETE"
		c.title.Text = "Nice work!"
		if pr.tutorial then
			local vp, gold, spins = Tutorial.reward()
			c.body.Text = string.format("The first time you finish it: +%d VP, +%d Gold and %d free recruits. Head back when you're ready.", vp, gold, spins)
		else
			c.body.Text = "Pick another drill from Practice, or run this one again."
		end
		for _, dot in ipairs(c.dots) do
			dot.Visible = false
		end
		c.streak.Text = ""
		c.leave.BackgroundColor3 = UI.Spark
		c.leave.TextColor3 = UI.Ink
		return
	end
	c.leave.BackgroundColor3 = UI.InkSoft
	c.leave.TextColor3 = UI.Chalk
	c.head.Text = pr.tutorial and string.format("TUTORIAL  %d / %d", pr.index or 1, pr.total or #Tutorial.Drills) or "PRACTICE"
	c.title.Text = d.title
	local how = d.key
	if State.isMobile then
		how = d.touch
	elseif mods.InputController.lastDevice() == "Gamepad" then
		how = d.pad
	end
	c.body.Text = d.blurb .. " " .. how
	for i, dot in ipairs(c.dots) do
		dot.Visible = i <= (pr.goal or d.goal)
		dot.BackgroundColor3 = i <= (pr.count or 0) and UI.Mint or UI.InkSoft
	end
	c.streak.Text = d.inARow and "in a row" or ""
end

------------------------------------------------------------------------------------------
-- timeout and settings buttons
------------------------------------------------------------------------------------------

-- One row per setting: a switch (key), or a button (press) that opens something. `sub` is a
-- line under the name; `touch` rows show on touch devices only.
local SETTINGS = {
	{ key = "doubleApproach", text = "Double approach", sub = "Spike once to run in, again to jump" },
	{ key = "setterAim", text = "Setter aim", sub = "As the setter, aim your sets (your team sees it)" },
	{ key = "landingMarker", text = "Landing marker" },
	{ key = "dramatic", text = "Impact frames and speed lines" },
	{ key = "assist", text = "Receive assist" },
	{ key = "followCam", text = "Follow camera (zoomed in)" },
	{ key = "shake", text = "Camera shake" },
	{
		key = "touchLayout",
		text = "Touch controls",
		sub = "Move and resize your buttons",
		touch = true,
		button = "Edit",
		press = function()
			UIController.closeSettings()
			mods.MobileControls.editLayout()
		end,
	},
}

-- A round button with a Toolbox icon and a caption under it, top right (The Spike's corner).
local function roundButton(name, iconKey, x)
	local b = make("TextButton", { Name = name, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, x, 0, 6), Size = UDim2.fromOffset(70, 80), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, gui)
	local disc = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(54, 54), BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, b)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disc)
	local ring = make("UIStroke", { Color = UI.Chalk, Thickness = 2, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, disc)
	Gui.iconImage(disc, iconKey, 28, UI.Chalk, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	local cap = label(b, { Text = name, Font = Enum.Font.GothamBlack, TextSize = 15, Size = UDim2.new(1, 30, 0, 18), Position = UDim2.new(0, -15, 0, 58), TextXAlignment = Enum.TextXAlignment.Center })
	stroke(cap, 1.5, UI.Ink)
	b.MouseEnter:Connect(function()
		ring.Color = Gui.SIGNAL
		if Gui.onHover then
			Gui.onHover()
		end
	end)
	b.MouseLeave:Connect(function()
		ring.Color = UI.Chalk
	end)
	return b, cap
end

-- The settings panel shrinks to fit below wherever it opened (a phone held sideways is short).
local function fitSettings()
	local sp = ui.settings
	if not sp or not ui.settingsScale then
		return
	end
	local room = gui.AbsoluteSize.Y - sp.Position.Y.Offset - 8
	ui.settingsScale.Scale = math.clamp(room / sp.Size.Y.Offset, 0.45, 1)
end

local function buildCorner()
	local timeout, timeoutCap = roundButton("Timeout", "IconTimeout", -84)
	timeout.Visible = false
	Gui.pressSound(timeout)
	timeout.MouseButton1Click:Connect(function()
		click()
		mods.ActionController.press("Timeout")
	end)
	-- forfeit: tap once to arm, again within 3 seconds to give up the match
	local forfeit, forfeitCap = roundButton("Forfeit", "IconForfeit", -156)
	forfeit.Visible = false
	Gui.pressSound(forfeit)
	forfeit.MouseButton1Click:Connect(function()
		click()
		if ui.forfeitArmed and os.clock() - ui.forfeitArmed < 3 then
			ui.forfeitArmed = nil
			Net.get("Forfeit"):FireServer()
		else
			ui.forfeitArmed = os.clock()
		end
	end)
	ui.forfeit = forfeit
	ui.forfeitCap = forfeitCap
	local gear = roundButton("Settings", "IconSettings", -12)

	-- the settings panel: a dark hairline card, one row per setting
	local rows, tops = {}, {}
	local y = 60
	for _, s in ipairs(SETTINGS) do
		if not s.touch or State.isMobile then
			table.insert(rows, s)
			table.insert(tops, y)
			y = y + (s.sub and 58 or 44) + 6
		end
	end
	local sp = panel(gui, {
		Name = "Settings",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 92),
		Size = UDim2.fromOffset(360, y + 6),
		Visible = false,
		ZIndex = 5,
	})
	sp.BackgroundTransparency = 0.05
	edge(sp, Gui.HAIRLINE, 0.3)
	ui.settingsScale = make("UIScale", {}, sp)
	label(sp, { Text = "Settings", Font = Enum.Font.GothamBlack, TextSize = 26, Size = UDim2.new(1, -32, 0, 30), Position = UDim2.fromOffset(16, 10), ZIndex = 5 })
	Gui.plate(sp, { Size = UDim2.fromOffset(56, 5), Position = UDim2.fromOffset(18, 44), ZIndex = 5 }, Gui.SIGNAL)
	local toggles = {}
	for i, s in ipairs(rows) do
		local h = s.sub and 58 or 44
		local b = make("TextButton", {
			Name = s.key,
			Size = UDim2.new(1, -24, 0, h),
			Position = UDim2.fromOffset(12, tops[i]),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.95,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 5,
		}, sp)
		corner(b, 6)
		label(b, { Text = s.text, Font = Enum.Font.GothamBlack, TextSize = 18, Size = UDim2.new(1, -96, 0, s.sub and 30 or h), Position = UDim2.fromOffset(12, s.sub and 4 or 0), ZIndex = 5 })
		if s.sub then
			label(b, { Text = s.sub, TextSize = 14, TextColor3 = UI.Fog, TextWrapped = true, Size = UDim2.new(1, -96, 0, 20), Position = UDim2.fromOffset(12, 32), ZIndex = 5 })
		end
		if s.press then
			-- a button row: a signal-yellow plate on the right
			local plate = Gui.plate(b, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(78, 34), ZIndex = 5 }, Gui.SIGNAL)
			label(plate, { Text = s.button, Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
			Gui.pressSound(b)
			b.MouseButton1Click:Connect(function()
				click()
				s.press()
			end)
		else
			-- a switch: signal yellow with the knob right when on
			local track = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(54, 28), BorderSizePixel = 0, ZIndex = 5 }, b)
			corner(track, 14)
			local knob = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 6 }, track)
			corner(knob, 11)
			local function refresh()
				local v = State.settings[s.key]
				local on = v == true or (type(v) == "number" and v > 0)
				track.BackgroundColor3 = on and Gui.SIGNAL or Color3.fromRGB(64, 68, 86)
				knob.Position = on and UDim2.new(1, -25, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
			end
			Gui.pressSound(b)
			b.MouseButton1Click:Connect(function()
				click()
				local v = State.settings[s.key]
				if type(v) == "number" then
					State.setSetting(s.key, v > 0 and 0 or 1)
				else
					State.setSetting(s.key, not v)
				end
			end)
			refresh()
			table.insert(toggles, refresh)
		end
	end
	-- a change from anywhere (a click here, or the saved settings arriving with the profile)
	State.signals.Settings:Connect(function()
		for _, refresh in ipairs(toggles) do
			refresh()
		end
	end)
	Gui.pressSound(gear)
	gear.MouseButton1Click:Connect(function()
		click()
		sp.Visible = not sp.Visible
		sp.Position = UDim2.new(1, -12, 0, 92)
		gui.DisplayOrder = 10
		fitSettings()
	end)
	ui.timeout = timeout
	ui.timeoutCap = timeoutCap
	ui.gear = gear
	ui.settings = sp
end

function UIController.closeSettings()
	if ui.settings then
		ui.settings.Visible = false
		gui.DisplayOrder = 10
	end
end

-- The settings panel, opened from the menus' own Settings button: it shows just under that
-- button (belowY, a screen position from the very top) and above the menus.
function UIController.toggleSettings(belowY)
	local sp = ui.settings
	if not sp then
		return
	end
	sp.Visible = not sp.Visible
	gui.DisplayOrder = sp.Visible and 25 or 10
	if belowY then
		local inset = GuiService:GetGuiInset()
		sp.Position = UDim2.new(1, -12, 0, math.max(8, belowY - inset.Y))
	end
	fitSettings()
end

local function updateTimeout()
	local b = ui.timeout
	local show = State.isPlaying and State.match.inMatch == true
	ui.gear.Visible = State.isPlaying
	b.Visible = show
	local f = ui.forfeit
	f.Visible = show and State.phase() ~= "MatchEnd"
	if ui.forfeitArmed and os.clock() - ui.forfeitArmed < 3 then
		ui.forfeitCap.Text = "Sure?"
		ui.forfeitCap.TextColor3 = UI.Whistle
	else
		ui.forfeitArmed = nil
		ui.forfeitCap.Text = "Forfeit"
		ui.forfeitCap.TextColor3 = UI.Chalk
	end
	if show then
		local left = State.timeouts(State.myTeam)
		if State.match.timeoutPending then
			ui.timeoutCap.Text = "Called"
			ui.timeoutCap.TextColor3 = Gui.SIGNAL
		else
			ui.timeoutCap.Text = "Timeout " .. left
			ui.timeoutCap.TextColor3 = left > 0 and UI.Chalk or UI.Fog
		end
	end
end

------------------------------------------------------------------------------------------
-- wiring
------------------------------------------------------------------------------------------

-- The scorer's card: a slanted plate, ink with the scorer's team colour sweeping in from the
-- left, print grain and speed chevrons; their Roblox headshot, their name and the character they
-- play (tier, role, ability), with the point's word on a tag. It slides in while the camera holds
-- on them after a point they earned (Config.Match.Celebrate). Card designs to pick come later.
local CARD_W, CARD_H = 480, 104
local CARD_Y = 0.6
local ROLE_NAME = {}
for key, r in pairs(Config.Roles) do
	ROLE_NAME[key] = r.Name
end

local function buildScoreCard()
	local root = make("Frame", {
		Name = "ScoreCard",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -CARD_W - 60, CARD_Y, 0),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, gui)
	Gui.plate(root, { Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = 1 }, Gui.CARD)
	-- the team colour, solid at the left and gone by the middle
	local sweep = Gui.plate(root, { Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = 2 }, UI.Chalk)
	local body = sweep:FindFirstChild("Body")
	if body then
		make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.45, 0.6), NumberSequenceKeypoint.new(1, 1) }) }, body)
	end
	local capR = sweep:FindFirstChild("CapR")
	if capR then
		capR.ImageTransparency = 1
	end
	Gui.halftone(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.55, 0, 1, 0), ImageColor3 = UI.Chalk, ImageTransparency = 0.9, ZIndex = 3 })
	for i = 1, 3 do
		local chevron = Gui.plate(root, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -30 - (3 - i) * 26, 0.5, 8), Size = UDim2.fromOffset(16, CARD_H - 44), ZIndex = 3 }, Gui.SIGNAL)
		Gui.fade(chevron, 0.2 + (3 - i) * 0.25)
	end
	local shotSize = CARD_H - 20
	local shot = make("ImageLabel", {
		Position = UDim2.fromOffset(28, 10),
		Size = UDim2.fromOffset(shotSize, shotSize),
		BackgroundColor3 = Gui.LINE,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 4,
	}, root)
	make("UIStroke", { Color = UI.Chalk, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, shot)
	local x = 28 + shotSize + 16
	local name = Gui.label(root, { display = true, weight = Enum.FontWeight.Heavy, TextSize = 32, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(x, 12), Size = UDim2.new(1, -x - 120, 0, 38), ZIndex = 5 })
	local _, setBadge = Gui.tierBadge(root, 30, { Position = UDim2.fromOffset(x, 58), ZIndex = 5 })
	local line = Gui.label(root, { TextSize = 18, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(x + 38, 58), Size = UDim2.new(1, -x - 60, 0, 30), ZIndex = 5 })
	local tag = Gui.plate(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, -16), Size = UDim2.fromOffset(150, 34), ZIndex = 6 }, Gui.SIGNAL)
	local word = Gui.label(tag, { display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
	ui.scoreCard = { root = root, sweep = sweep, shot = shot, name = name, setBadge = setBadge, line = line, word = word, token = 0 }
end

local function showScoreCard(a)
	local word = Config.Match.Celebrate[a.reason or ""]
	local C = ui.scoreCard
	if not word or a.error or not a.scorerId or not C then
		return
	end
	C.token = C.token + 1
	local token = C.token
	local m = Util.modelOf(a.scorerId)
	local userId = m and tonumber(m:GetAttribute("AvatarUserId")) or 0
	C.shot.Image = userId > 0 and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId) or ""
	C.name.Text = a.scorerName or ""
	local tier = m and m:GetAttribute("Tier") or ""
	C.setBadge(tier, Characters.color(tier), false)
	local parts = {}
	local charName = m and m:GetAttribute("CharName")
	if charName and charName ~= "" then
		table.insert(parts, charName)
	end
	local role = m and ROLE_NAME[m:GetAttribute("Role") or ""]
	if role then
		table.insert(parts, role)
	end
	local ability = m and Config.Abilities[m:GetAttribute("Ability") or ""]
	if ability then
		table.insert(parts, ability.Name)
	end
	C.line.Text = table.concat(parts, "  /  ")
	C.word.Text = word
	Gui.tint(C.sweep, teamColor(a.winner))
	local away = UDim2.new(0, -CARD_W - 60, CARD_Y, 0)
	C.root.Visible = true
	C.root.Position = away
	TweenService:Create(C.root, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 28, CARD_Y, 0) }):Play()
	task.delay(Config.Match.PointPauseTime - 0.55, function()
		if token ~= C.token then
			return
		end
		local out = TweenService:Create(C.root, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = away })
		out.Completed:Connect(function()
			if token == C.token then
				C.root.Visible = false
			end
		end)
		out:Play()
	end)
end

local function onAnnounce(a)
	if not State.isPlaying and a.kind ~= "StandIn" then
		return -- a match you're not in (you're in the menus)
	end
	if a.kind == "Point" then
		showBanner(a)
		showScoreCard(a)
		if a.deuce then
			UIController.callout("Deuce!", UI.Whistle, "Play to " .. tostring(a.playTo), 1.2)
		elseif a.matchPoint then
			UIController.callout("Match point", teamColor(a.setPoint), teamName(a.setPoint), 1.2)
		elseif a.setPoint then
			UIController.callout("Set point", teamColor(a.setPoint), teamName(a.setPoint), 1.2)
		end
	elseif a.kind == "Drill" then
		local d = Tutorial.drill(a.drill)
		if a.finished then
			UIController.callout("Done!", UI.Spark, a.tutorial and "Tutorial complete" or "Drill complete", 2)
		elseif a.start and d then
			UIController.callout(d.title, UI.Spark, d.inARow and string.format("%d in a row", d.goal) or string.format("%d to finish", d.goal), 1.4)
		elseif a.success == true then
			UIController.callout("Nice!", UI.Mint, string.format("%d / %d", a.count or 0, a.goal or 3), 0.9)
		elseif a.success == false then
			UIController.callout("Miss", UI.Fog, (d and d.inARow) and "Back to 0" or "Go again", 0.9)
		end
	elseif a.kind == "SetStart" then
		if (a.setNumber or 1) > 1 then
			UIController.callout("Set " .. tostring(a.setNumber), UI.Chalk, "First to " .. tostring(a.target), 1.4)
		end
	elseif a.kind == "SetEnd" then
		UIController.callout("Set to " .. teamName(a.winner), teamColor(a.winner), string.format("Sets %d-%d", a.sets.Home or 0, a.sets.Away or 0), 2.4)
		if a.offer then
			ui.again.offer = a.offer
			ui.again.voted = nil
		end
	elseif a.kind == "Serve" then
		if a.id == State.myId then
			showHint("Your serve: F for an easy underhand serve, tap X for an overhand serve, hold X to toss for a jump serve (hold toward the net to toss it forward)")
		end
	elseif a.kind == "Forfeit" then
		UIController.callout("Forfeit", teamColor(a.team), teamName(a.team) .. " gave up the match", 1.6)
	elseif a.kind == "TimeoutCalled" then
		showHint(teamName(a.team) .. " called a timeout (next dead ball)")
	elseif a.kind == "Timeout" then
		UIController.callout("Timeout", teamColor(a.team), "Stamina refilled. Rearrange your rotation", 1.6)
	elseif a.kind == "Break" then
		if a.team == State.myTeam then
			showHint("Guard broken! Slide to receive (C) or call a timeout (T)")
		end
	elseif a.kind == "StandIn" then
		local why = a.reason == "afk" and "is away" or "left"
		showHint(string.format("%s %s. Their AI plays %s for now", a.name or "A player", why, a.char or "their character"))
	end
end

local function onBall(snap, isEcho)
	if isEcho or snap.state ~= "Flight" or not snap.meta then
		return
	end
	local meta = snap.meta
	local ht = meta.hitType
	if (ht == "Spike" or ht == "JumpServe" or ht == "Overhand") and meta.kmh then
		showReadout(meta)
	end
	if meta.drain and meta.team and ui.top[meta.team] then
		ui.top[meta.team].hitAt = os.clock()
		ui.top[meta.team].hitSize = math.clamp(meta.drain / 25, 0.4, 1.5)
	end
end

-- Every frame: only what animates smoothly. The panels below change a few times a second at
-- most, so they refresh at 20 Hz; the top bar only changes with the match state.
local function updateFast()
	updateReadout()
	updateOverhead()
	updateRail()
end

------------------------------------------------------------------------------------------
-- timeout: rearrange your rotation and pick the next server
------------------------------------------------------------------------------------------

local ROLE_NAME = { WS = "Wing spiker", MB = "Middle blocker", SE = "Setter", Solo = "Solo" }

local function buildRotation()
	local f = panel(gui, {
		Name = "Rotation",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 130),
		Size = UDim2.fromOffset(460, 64 + 3 * 46),
		Visible = false,
	})
	edge(f)
	local title = label(f, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 16, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 8) })
	label(f, {
		Text = "Rotation order. Serve picks who serves next; Up and Down change the order.",
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = UI.Fog,
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.fromOffset(12, 32),
	})
	local rows = {}
	for i = 1, 3 do
		local y = 56 + (i - 1) * 46
		local row = make("Frame", { Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, y), BackgroundColor3 = UI.InkSoft, BorderSizePixel = 0 }, f)
		corner(row, 8)
		local name = label(row, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 14, Size = UDim2.new(1, -200, 0, 20), Position = UDim2.fromOffset(10, 3) })
		local sub = label(row, { Text = "", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = UI.Fog, Size = UDim2.new(1, -200, 0, 14), Position = UDim2.fromOffset(10, 22) })
		local r = { frame = row, name = name, sub = sub }
		local function op(kind)
			return function()
				if r.id then
					click()
					Net.get("Rotation"):FireServer(kind, r.id)
				end
			end
		end
		r.serve = button(row, "Serve", { Size = UDim2.fromOffset(64, 30), Position = UDim2.new(1, -186, 0, 5), TextSize = 12 })
		r.up = button(row, "Up", { Size = UDim2.fromOffset(54, 30), Position = UDim2.new(1, -118, 0, 5), TextSize = 12 })
		r.down = button(row, "Down", { Size = UDim2.fromOffset(58, 30), Position = UDim2.new(1, -60, 0, 5), TextSize = 12 })
		local function hasId()
			return r.id ~= nil
		end
		Gui.pressSound(r.serve, nil, hasId)
		Gui.pressSound(r.up, nil, hasId)
		Gui.pressSound(r.down, nil, hasId)
		r.serve.MouseButton1Click:Connect(op("serve"))
		r.up.MouseButton1Click:Connect(op("up"))
		r.down.MouseButton1Click:Connect(op("down"))
		rows[i] = r
	end
	local ready = button(f, "Ready", { Size = UDim2.fromOffset(150, 34), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -10), BackgroundColor3 = UI.Spark, TextColor3 = UI.Ink, TextSize = 14 })
	Gui.pressSound(ready)
	ready.MouseButton1Click:Connect(function()
		click()
		ui.rotation.ready = true
		Net.get("Timeout"):FireServer("ready")
	end)
	local swap = button(f, "Character and look", { Size = UDim2.fromOffset(200, 34), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), TextSize = 13 })
	Gui.pressSound(swap)
	swap.MouseButton1Click:Connect(function()
		click()
		mods.MenuController.openSwap()
	end)
	ui.rotation = { frame = f, title = title, rows = rows, readyButton = ready, swap = swap }
end

local function updateRotation()
	local R = ui.rotation
	local show = State.isPlaying and State.match.inMatch == true and State.phase() == "Timeout" and State.myTeam ~= nil
	R.frame.Visible = show
	if not show then
		R.ready = nil
		return
	end
	local tr = State.match.timeoutReady
	R.readyButton.Text = R.ready and string.format("Ready %d/%d", tr and tr[1] or 1, tr and tr[2] or 1) or "Ready"
	R.readyButton.BackgroundColor3 = R.ready and UI.Mint or UI.Spark
	local left = math.max(0, math.ceil((State.match.phaseEnd or 0) - Util.now()))
	R.title.Text = "Timeout " .. left .. "   " .. teamName(State.myTeam) .. " rotation"
	local roster = State.roster(State.myTeam)
	local serving = State.match.servingTeam == State.myTeam
	local nextServer = serving and 1 or math.min(2, #roster)
	for i, r in ipairs(R.rows) do
		local e = roster[i]
		r.frame.Visible = e ~= nil
		r.id = e and e.id
		if e then
			r.name.Text = i .. ".  " .. e.name .. (e.id == State.myId and "  (you)" or "")
			r.name.TextColor3 = e.id == State.myId and UI.Spark or UI.Chalk
			r.sub.Text = (ROLE_NAME[e.role] or e.role or "") .. (i == nextServer and "   serves next" or "")
			r.sub.TextColor3 = i == nextServer and UI.Mint or UI.Fog
			r.up.TextColor3 = i > 1 and UI.Chalk or UI.Fog
			r.down.TextColor3 = i < #roster and UI.Chalk or UI.Fog
			r.serve.Visible = #roster > 1
		end
	end
	R.frame.Size = UDim2.fromOffset(460, 64 + #roster * 46 + 48)
end

-- Your AI teammates' active abilities under your own: the key, the ability and whose it is, the
-- bar filling as it cools down (in the ability's colour once ready). Click or tap one to pop it.
local function buildTeamAbilities()
	local list = {}
	for i = 1, 2 do
		local b = make("TextButton", {
			Name = "TeamAbility" .. i,
			Position = UDim2.fromOffset(12, 84 + (i - 1) * 46),
			Size = UDim2.fromOffset(250, 40),
			BackgroundColor3 = Gui.CARD,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ClipsDescendants = true,
			Visible = false,
		}, gui)
		edge(b)
		local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.Chalk, BackgroundTransparency = 0.82, BorderSizePixel = 0 }, b)
		local cap = make("TextLabel", {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = UI.Chalk,
			BorderSizePixel = 0,
			Text = tostring(i),
			TextColor3 = UI.Ink,
			TextSize = 15,
			FontFace = Gui.display(Enum.FontWeight.Heavy),
		}, b)
		corner(cap, 4)
		local name = make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(42, 0),
			Size = UDim2.new(1, -50, 1, 0),
			RichText = true,
			Text = "",
			TextColor3 = UI.Chalk,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = Gui.display(Enum.FontWeight.Bold),
		}, b)
		b.MouseButton1Click:Connect(function()
			mods.ActionController.press("Team" .. i)
		end)
		list[i] = { button = b, fill = fill, name = name }
	end
	ui.teamAbilities = list
end

local function updateTeamAbilities()
	local mates = (State.isPlaying and State.match.inMatch) and mods.ActionController.teamAbilities() or {}
	for i, t in ipairs(ui.teamAbilities) do
		local mate = mates[i]
		t.button.Visible = mate ~= nil
		if mate then
			local def = Config.Abilities[mate.ability]
			local left = mods.ActionController.cooldownOf(mate.id)
			local ready = left <= 0
			t.name.Text = string.format('%s  <font color="#%s">%s</font>', def.Name, ready and def.Color:ToHex() or "8A93AD", ready and "READY" or (math.ceil(left) .. " s"))
			t.fill.Size = UDim2.fromScale(ready and 1 or math.clamp(1 - left / def.Cooldown, 0, 1), 1)
			t.fill.BackgroundColor3 = ready and def.Color or UI.Chalk
			t.fill.BackgroundTransparency = ready and 0.7 or 0.85
		end
	end
end

local function updateSlow()
	updateStamina()
	updateAbility()
	updateTeamAbilities()
	updateTimeout()
	updateRotation()
	updateCoach()
	updateContinue()
end

function UIController.init(m)
	mods = m
	gui = make("ScreenGui", {
		Name = "SpikeRushUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	}, player:WaitForChild("PlayerGui"))
	buildTopBar()
	buildBanner()
	buildScoreCard()
	buildCallout()
	buildHint()
	buildAbility()
	buildTeamAbilities()
	buildRail()
	buildCorner()
	buildRotation()
	buildCoach()
	buildContinue()

	State.signals.Announce:Connect(function(a)
		if a.kind == "Point" then
			refreshTopBar()
		end
		onAnnounce(a)
	end)
	State.signals.Ball:Connect(onBall)
	State.signals.Hint:Connect(showHint)
	State.signals.Match:Connect(function()
		refreshTopBar()
	end)
	State.signals.Charge:Connect(function(energy, gauge, st)
		ui.ability.e = energy
		ui.ability.g = gauge
		ui.ability.st = st
	end)
	refreshTopBar()
	pcall(updateSlow)

	local slowAcc, tagAcc = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(updateFast)
		slowAcc = slowAcc + dt
		if ok and slowAcc >= 0.05 then
			slowAcc = 0
			ok, err = pcall(updateSlow)
		end
		if not ok then
			warn("[SpikeRush] ui: " .. tostring(err))
		end
		tagAcc = tagAcc + dt
		if tagAcc > 0.5 then
			tagAcc = 0
			refreshTags()
		end
	end)
end

return UIController
