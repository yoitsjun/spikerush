-- HUD and menus. Visual language: stadium "ink" navy panels, team colours and the stamina and
-- ability colours carry the energy, one loud element at a time (manga callouts in Bangers),
-- numbers in Gotham Black, sentence case everywhere.
--
-- In play (modelled on The Spike's layout): a top bar with team names, stamina bars, score and
-- sets; the attack readout (km/h and hitting height) right below it; a "Team (Player) scored"
-- banner with the reason; name tags with tier badges and a marker over the player you control;
-- the ability panel; charge bars over your head; a timeout button.
-- Out of a match the menus (MenuController) take over; this controller only lends them the
-- settings panel.

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

local function panel(parent, props)
	local f = make("Frame", {
		BackgroundColor3 = UI.Ink,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	corner(f, 10)
	return f
end

local function label(parent, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = UI.Chalk,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function button(parent, text, props)
	local b = make("TextButton", {
		BackgroundColor3 = UI.InkSoft,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = text,
		TextColor3 = UI.Chalk,
		Font = Enum.Font.GothamBlack,
		TextSize = 15,
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 8)
	return b
end

local function click()
	if mods.AudioController then
		mods.AudioController.play("UIClick")
	end
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

local function buildTeamBlock(parent, team, align)
	local right = align == "Right"
	local f = make("Frame", {
		Size = UDim2.new(0, 250, 1, 0),
		BackgroundTransparency = 1,
	}, parent)
	if right then
		f.Position = UDim2.new(1, -250, 0, 0)
	end
	local xAlign = right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	local name = label(f, {
		Text = teamName(team),
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
		TextColor3 = teamColor(team),
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 6),
		TextXAlignment = xAlign,
	})
	stroke(name, 1.5, UI.Ink)
	local bar = make("Frame", {
		Size = UDim2.new(1, -16, 0, 12),
		Position = UDim2.fromOffset(8, 32),
		BackgroundColor3 = Color3.fromRGB(10, 12, 26),
		BorderSizePixel = 0,
	}, f)
	corner(bar, 6)
	local barStroke = stroke(bar, 1.5, UI.Fog, 0.4)
	local fill = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Chalk,
		BorderSizePixel = 0,
	}, bar)
	if right then
		fill.AnchorPoint = Vector2.new(1, 0)
		fill.Position = UDim2.fromScale(1, 0)
	end
	corner(fill, 6)
	local broken = label(bar, {
		Text = "Broken",
		Font = Enum.Font.GothamBlack,
		TextSize = 11,
		TextColor3 = HOT,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})
	local pips = make("Frame", {
		Size = UDim2.new(1, -16, 0, 10),
		Position = UDim2.fromOffset(8, 50),
		BackgroundTransparency = 1,
	}, f)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = right and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 5),
	}, pips)
	local pipList = {}
	for i = 1, Config.Timeout.PerSet do
		local p = make("Frame", { Size = UDim2.fromOffset(10, 10), BackgroundColor3 = UI.Chalk, BorderSizePixel = 0, LayoutOrder = i }, pips)
		corner(p, 5)
		table.insert(pipList, p)
	end
	return { name = name, bar = bar, fill = fill, barStroke = barStroke, broken = broken, pips = pipList }
end

local function buildTopBar()
	local bar = panel(gui, {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(760, 66),
	})
	stroke(bar, 2, UI.InkSoft)
	local home = buildTeamBlock(bar, "Home", "Left")
	local away = buildTeamBlock(bar, "Away", "Right")
	local mid = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 240, 1, 0),
		BackgroundTransparency = 1,
	}, bar)
	local function score(x, align)
		return label(mid, {
			Text = "0",
			Font = Enum.Font.GothamBlack,
			TextSize = 38,
			Size = UDim2.new(0, 90, 0, 44),
			Position = UDim2.fromOffset(x, 4),
			TextXAlignment = align,
		})
	end
	local sHome = score(0, Enum.TextXAlignment.Right)
	local sAway = score(150, Enum.TextXAlignment.Left)
	-- the points this set is played to (rises in a deuce), in a yellow diamond between the scores
	local diamond = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(120, 27),
		Size = UDim2.fromOffset(32, 32),
		Rotation = 45,
		BackgroundColor3 = UI.Spark,
		BorderSizePixel = 0,
	}, mid)
	corner(diamond, 4)
	stroke(diamond, 2, UI.Ink)
	local target = label(mid, {
		Text = "15",
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextColor3 = UI.Ink,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(120, 27),
		Size = UDim2.fromOffset(40, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
	label(mid, {
		Text = "PLAY TO",
		Font = Enum.Font.GothamBlack,
		TextSize = 8,
		TextColor3 = UI.Fog,
		Size = UDim2.fromOffset(60, 10),
		Position = UDim2.fromOffset(90, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local setLine = label(mid, {
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = UI.Fog,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 48),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local serveDot = make("Frame", { Size = UDim2.fromOffset(10, 10), BackgroundColor3 = UI.Spark, BorderSizePixel = 0 }, mid)
	corner(serveDot, 5)

	-- attack readout under the bar: "129.75 km/h   3.85 m"
	local readout = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(300, 30),
		BackgroundTransparency = 1,
	}, gui)
	local kmh = label(readout, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 24,
		Size = UDim2.new(0.62, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	stroke(kmh, 2, UI.Ink)
	local height = label(readout, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = UI.Fog,
		Size = UDim2.new(0.36, 0, 1, 0),
		Position = UDim2.fromScale(0.64, 0),
	})
	stroke(height, 2, UI.Ink)
	ui.top = { bar = bar, Home = home, Away = away, sHome = sHome, sAway = sAway, setLine = setLine, serveDot = serveDot, kmh = kmh, height = height, shownAt = -10, target = target, diamond = diamond }
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
	local playTo, deuce = Court.playTo(scores.Home or 0, scores.Away or 0, m.target or Config.Match.PointsPerSet)
	t.target.Text = tostring(playTo)
	if deuce then
		t.setLine.Text = string.format("DEUCE, win by %d   set %d", Config.Match.WinBy, m.setNumber or 1)
		t.setLine.TextColor3 = UI.Whistle
		t.diamond.BackgroundColor3 = UI.Whistle
	else
		t.setLine.Text = string.format("Set %d   sets %d-%d", m.setNumber or 1, sets.Home or 0, sets.Away or 0)
		t.setLine.TextColor3 = UI.Fog
		t.diamond.BackgroundColor3 = UI.Spark
	end
	if m.servingTeam == "Away" then
		t.serveDot.Position = UDim2.fromOffset(232, 24)
	else
		t.serveDot.Position = UDim2.fromOffset(-2, 24)
	end
	-- someone else's match on this court stays out of the menus
	local mine = m.inMatch == true and State.isPlaying
	t.serveDot.Visible = mine
	t.bar.Visible = mine
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
			block.bar.Position = UDim2.fromOffset(8 + math.sin(now * 90) * 4 * k * block.hitSize, 32)
		else
			block.bar.Position = UDim2.fromOffset(8, 32)
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
		for i, p in ipairs(block.pips) do
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
	t.kmh.Text = fmt2(meta.kmh) .. " km/h"
	t.kmh.TextColor3 = color
	t.kmh.TextTransparency = 0
	t.height.Text = meta.height and (fmt2(meta.height) .. " m") or ""
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

local function buildBanner()
	local f = panel(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 8) }, f)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, f)
	local text = make("TextLabel", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		RichText = true,
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextColor3 = UI.Chalk,
		LayoutOrder = 1,
	}, f)
	local tag = make("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundColor3 = UI.Chalk,
		TextColor3 = UI.Ink,
		Font = Enum.Font.GothamBlack,
		TextSize = 13,
		LayoutOrder = 2,
	}, f)
	corner(tag, 13)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, tag)
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
	b.frame.Position = UDim2.new(0.5, 0, 0, 108)
	TweenService:Create(b.frame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 120) }):Play()
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
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = UI.Ink,
		BackgroundTransparency = 0.15,
		TextColor3 = UI.Chalk,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Visible = false,
	}, gui)
	corner(ui.hint, 15)
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
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		LayoutOrder = 1,
	}, row)
	corner(badge, 5)
	local name = make("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		BackgroundTransparency = 1,
		TextColor3 = UI.Chalk,
		Font = Enum.Font.GothamBlack,
		TextSize = 13,
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
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(250, 66),
		Visible = false,
	})
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
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.56, 0),
		Size = UDim2.fromOffset(124, #RAIL * 34),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	ui.railScale = make("UIScale", {}, rail)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, rail)
	local slots = {}
	for i, def in ipairs(RAIL) do
		-- a compact pill: key badge + action name
		local b = make("TextButton", {
			Size = UDim2.fromOffset(124, 30),
			BackgroundColor3 = UI.Ink,
			BackgroundTransparency = 0.25,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
		}, rail)
		corner(b, 8)
		local ring = make("UIStroke", { Thickness = 1.5, Color = UI.Chalk, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local badge = make("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.fromOffset(34, 22),
			BackgroundColor3 = UI.Chalk,
			TextColor3 = UI.Ink,
			Font = Enum.Font.GothamBlack,
			TextSize = 11,
			Text = def.key,
		}, b)
		corner(badge, 5)
		local name = label(b, {
			Text = def.action,
			Font = Enum.Font.GothamBlack,
			TextSize = 13,
			Size = UDim2.new(1, -46, 1, 0),
			Position = UDim2.fromOffset(44, 0),
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
		Spike = ctx.inZone == true or (ctx.serving == true and ctx.spikeLabel ~= nil),
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
			sl.ring.Thickness = 2.5
			sl.ring.Transparency = 0
			sl.button.BackgroundColor3 = def.color:Lerp(UI.Ink, 0.55)
			sl.badge.BackgroundColor3 = def.color
		else
			sl.ring.Color = UI.Chalk
			sl.ring.Thickness = 1.5
			sl.ring.Transparency = 0.6
			sl.button.BackgroundColor3 = UI.Ink
			sl.badge.BackgroundColor3 = UI.Chalk
		end
	end
end

------------------------------------------------------------------------------------------
-- after a set: keep playing for the extra set rewards, or end the match
------------------------------------------------------------------------------------------

local function buildContinue()
	local f = panel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromOffset(520, 190), Visible = false })
	stroke(f, 2, UI.Spark)
	ui.againScale = make("UIScale", {}, f)
	local title = label(f, { Text = "Keep playing?", Font = Enum.Font.GothamBlack, TextSize = 24, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 10), TextXAlignment = Enum.TextXAlignment.Center })
	local offer = label(f, { Text = "", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = UI.Fog, TextWrapped = true, RichText = true, Size = UDim2.new(1, -32, 0, 40), Position = UDim2.fromOffset(16, 44), TextXAlignment = Enum.TextXAlignment.Center })
	local keep = button(f, "Keep playing", { Size = UDim2.fromOffset(230, 46), Position = UDim2.new(0.5, -238, 0, 94), BackgroundColor3 = UI.Spark, TextColor3 = UI.Ink, TextSize = 17 })
	local stop = button(f, "End match", { Size = UDim2.fromOffset(230, 46), Position = UDim2.new(0.5, 8, 0, 94), TextSize = 17 })
	local status = label(f, { Text = "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = UI.Fog, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 1, -28), TextXAlignment = Enum.TextXAlignment.Center })
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

local function buildCoach()
	local f = panel(gui, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 60), Size = UDim2.fromOffset(360, 196), Visible = false })
	stroke(f, 2, UI.Spark)
	ui.coachScale = make("UIScale", {}, f)
	local head = label(f, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = UI.Spark, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 10) })
	local title = label(f, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 22, Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 28) })
	local body = label(f, { Text = "", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = UI.Fog, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -24, 0, 54), Position = UDim2.fromOffset(12, 60) })
	local list = make("Frame", { Size = UDim2.new(1, -24, 0, 50), Position = UDim2.fromOffset(12, 118), BackgroundTransparency = 1 }, f)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(110, 22), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local chips = {}
	for i, s in ipairs(Tutorial.Steps) do
		local c = label(list, { Text = s.title, Font = Enum.Font.GothamBold, TextSize = 12, LayoutOrder = i, BackgroundTransparency = 0, BackgroundColor3 = UI.InkSoft, TextXAlignment = Enum.TextXAlignment.Center })
		corner(c, 5)
		chips[s.id] = c
	end
	local leave = button(f, "Back to the menu", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 1, -44), BackgroundColor3 = UI.Spark, TextColor3 = UI.Ink, TextSize = 15, Visible = false })
	leave.MouseButton1Click:Connect(function()
		click()
		Net.get("Forfeit"):FireServer()
	end)
	ui.coach = { frame = f, head = head, title = title, body = body, chips = chips, leave = leave, done = -1 }
end

local function updateCoach()
	local c = ui.coach
	local prof = State.profile
	local tut = prof and prof.tutorial
	local show = State.isPlaying and State.match.tutorial == true and tut ~= nil
	c.frame.Visible = show
	if not show then
		return
	end
	local cam = workspace.CurrentCamera
	if cam then
		ui.coachScale.Scale = math.clamp(cam.ViewportSize.Y / 760, 0.62, 1.1)
	end
	local nextStep, n, total = Tutorial.progress(tut.steps)
	if n ~= c.done then
		if c.done >= 0 and n > c.done and mods.AudioController then
			mods.AudioController.play("Point", { volume = 0.8 })
		end
		c.done = n
	end
	for id, chip in pairs(c.chips) do
		local ok = tut.steps[id] == true
		chip.BackgroundColor3 = ok and UI.Mint or (nextStep and nextStep.id == id and UI.Spark or UI.InkSoft)
		chip.TextColor3 = (ok or (nextStep and nextStep.id == id)) and UI.Ink or UI.Fog
	end
	if tut.done or not nextStep then
		local vp, gold, spins = Tutorial.reward()
		c.head.Text = "TUTORIAL COMPLETE"
		c.title.Text = "You're ready!"
		c.body.Text = string.format("+%d VP, +%d Gold and %d free recruits. Finish the match or head back to the menu.", vp, gold, spins)
		c.leave.Visible = true
		return
	end
	c.leave.Visible = false
	c.head.Text = string.format("TUTORIAL  %d / %d", n + 1, total)
	c.title.Text = nextStep.title
	local how = nextStep.key
	if State.isMobile then
		how = nextStep.touch
	elseif mods.InputController.lastDevice() == "Gamepad" then
		how = nextStep.pad
	end
	c.body.Text = how
end

------------------------------------------------------------------------------------------
-- timeout and settings buttons
------------------------------------------------------------------------------------------

local SETTINGS = {
	{ key = "landingMarker", text = "Landing marker" },
	{ key = "dramatic", text = "Impact frames and speed lines" },
	{ key = "assist", text = "Receive assist" },
	{ key = "followCam", text = "Follow camera (zoomed in)" },
	{ key = "shake", text = "Camera shake" },
}

local function buildCorner()
	local timeout = button(gui, "Timeout", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -60, 0, 12),
		Size = UDim2.fromOffset(120, 36),
		BackgroundColor3 = UI.Ink,
		Visible = false,
	})
	stroke(timeout, 2, UI.InkSoft)
	timeout.MouseButton1Click:Connect(function()
		click()
		mods.ActionController.press("Timeout")
	end)
	-- forfeit: tap once to arm, again within 3 seconds to give up the match
	local forfeit = button(gui, "Forfeit", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -188, 0, 12),
		Size = UDim2.fromOffset(100, 36),
		BackgroundColor3 = UI.Ink,
		TextSize = 14,
		Visible = false,
	})
	stroke(forfeit, 2, UI.InkSoft)
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
	local gear = button(gui, "⚙", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(40, 36),
		BackgroundColor3 = UI.Ink,
		TextSize = 20,
	})
	stroke(gear, 2, UI.InkSoft)

	local sp = panel(gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 56),
		Size = UDim2.fromOffset(300, 30 + #SETTINGS * 40),
		Visible = false,
		ZIndex = 5,
	})
	label(sp, { Text = "Settings", Font = Enum.Font.GothamBlack, TextSize = 16, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(12, 6), ZIndex = 5 })
	local toggles = {}
	for i, s in ipairs(SETTINGS) do
		local b = button(sp, "", {
			Size = UDim2.new(1, -20, 0, 34),
			Position = UDim2.fromOffset(10, 30 + (i - 1) * 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 14,
			Font = Enum.Font.GothamBold,
			ZIndex = 5,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, b)
		local function refresh()
			local v = State.settings[s.key]
			local on = v == true or (type(v) == "number" and v > 0)
			b.Text = s.text .. ": " .. (on and "on" or "off")
			b.BackgroundColor3 = on and UI.InkSoft or Color3.fromRGB(28, 30, 50)
		end
		b.MouseButton1Click:Connect(function()
			click()
			local v = State.settings[s.key]
			if type(v) == "number" then
				State.setSetting(s.key, v > 0 and 0 or 1)
			else
				State.setSetting(s.key, not v)
			end
			refresh()
		end)
		refresh()
		table.insert(toggles, refresh)
	end
	gear.MouseButton1Click:Connect(function()
		click()
		sp.Visible = not sp.Visible
		sp.Position = UDim2.new(1, -12, 0, 56)
		gui.DisplayOrder = 10
	end)
	ui.timeout = timeout
	ui.gear = gear
	ui.settings = sp
end

function UIController.closeSettings()
	if ui.settings then
		ui.settings.Visible = false
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
end

local function updateTimeout()
	local b = ui.timeout
	local show = State.isPlaying and State.match.inMatch == true
	ui.gear.Visible = State.isPlaying
	b.Visible = show
	local f = ui.forfeit
	f.Visible = show and State.phase() ~= "MatchEnd"
	if ui.forfeitArmed and os.clock() - ui.forfeitArmed < 3 then
		f.Text = "Sure?"
		f.TextColor3 = UI.Whistle
	else
		ui.forfeitArmed = nil
		f.Text = "Forfeit"
		f.TextColor3 = UI.Fog
	end
	if show then
		local left = State.timeouts(State.myTeam)
		if State.match.timeoutPending then
			b.Text = "Timeout called"
			b.TextColor3 = UI.Spark
		else
			b.Text = "Timeout (" .. left .. ")"
			b.TextColor3 = left > 0 and UI.Chalk or UI.Fog
		end
	end
end

------------------------------------------------------------------------------------------
-- results
------------------------------------------------------------------------------------------

local COLS = {
	{ "Player", 0, 0.3 },
	{ "Tier", 0.3, 0.08 },
	{ "Kills", 0.38, 0.09 },
	{ "Aces", 0.47, 0.09 },
	{ "Blocks", 0.56, 0.1 },
	{ "Digs", 0.66, 0.08 },
	{ "Top km/h", 0.74, 0.13 },
	{ "VP", 0.87, 0.12 },
}

local function buildResults()
	local f = panel(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(720, 400),
		Visible = false,
	})
	stroke(f, 2, UI.InkSoft)
	local title = label(f, {
		Text = "",
		Font = Enum.Font.Bangers,
		TextSize = 46,
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.fromOffset(0, 8),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	stroke(title, 3, UI.Ink)
	local mvp = label(f, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 15,
		TextColor3 = UI.Spark,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 62),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local mine = label(f, {
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = UI.Mint,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -28),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local list = make("Frame", { Size = UDim2.new(1, -40, 1, -136), Position = UDim2.fromOffset(20, 96), BackgroundTransparency = 1 }, f)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	ui.results = { frame = f, title = title, mvp = mvp, list = list, mine = mine }
end

local function resultRow(values, color, order, header)
	local row = make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = order }, ui.results.list)
	for i, c in ipairs(COLS) do
		label(row, {
			Text = tostring(values[i] or ""),
			Font = header and Enum.Font.GothamBold or Enum.Font.GothamBlack,
			TextSize = header and 12 or 14,
			TextColor3 = header and UI.Fog or (i == 1 and color or UI.Chalk),
			Size = UDim2.new(c[3], 0, 1, 0),
			Position = UDim2.new(c[2], 0, 0, 0),
			TextXAlignment = i == 1 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center,
		})
	end
end

local function showResults(a)
	local r = ui.results
	for _, c in ipairs(r.list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	r.title.Text = teamName(a.winner) .. " win"
	r.title.TextColor3 = teamColor(a.winner)
	r.mvp.Text = a.mvpName and ("MVP " .. a.mvpName) or ""
	for _, e in ipairs(a.results or {}) do
		if e.id == a.mvpId and e.mvpBonus then
			r.mvp.Text = r.mvp.Text .. string.format("  (+%d VP bonus)", e.mvpBonus)
		end
	end
	if a.forfeit then
		r.mvp.Text = teamName(a.forfeit) .. " forfeited"
	end
	-- your own line: gold, extra sets and the win streak
	r.mine.Text = ""
	for _, e in ipairs(a.results or {}) do
		if e.id == State.myId then
			local parts = {}
			if e.reward then
				table.insert(parts, string.format("+%d VP  +%d Gold", e.reward, e.gold or 0))
			end
			if e.extraVP then
				table.insert(parts, "extra sets included")
			end
			if e.streak and e.streak >= 2 then
				local bonus = e.streakVP and string.format(" (+%d VP, +%d Gold)", e.streakVP, e.streakGold or 0) or ""
				table.insert(parts, string.format("<b>Win streak %d</b>%s", e.streak, bonus))
			elseif e.streak == 0 then
				table.insert(parts, "win streak reset")
			end
			r.mine.Text = table.concat(parts, "     ")
		end
	end
	local header = {}
	for i, c in ipairs(COLS) do
		header[i] = c[1]
	end
	resultRow(header, UI.Fog, 0, true)
	for i, e in ipairs(a.results or {}) do
		local reward = e.reward and ("+" .. e.reward) or ""
		local top = (e.topKmh and e.topKmh > 0) and string.format("%.1f", e.topKmh) or "-"
		resultRow({ e.name, e.tier or "", e.kills, e.aces, e.blocks, e.digs, top, reward }, teamColor(e.team), i, false)
	end
	r.frame.Visible = true
	task.delay(Config.Match.MatchEndTime - 0.5, function()
		r.frame.Visible = false
	end)
end

------------------------------------------------------------------------------------------
-- wiring
------------------------------------------------------------------------------------------

local function onAnnounce(a)
	if not State.isPlaying and a.kind ~= "StandIn" then
		return -- a match you're not in (you're in the menus)
	end
	if a.kind == "Point" then
		showBanner(a)
		if a.deuce then
			UIController.callout("Deuce!", UI.Whistle, "Play to " .. tostring(a.playTo), 1.2)
		elseif a.matchPoint then
			UIController.callout("Match point", teamColor(a.setPoint), teamName(a.setPoint), 1.2)
		elseif a.setPoint then
			UIController.callout("Set point", teamColor(a.setPoint), teamName(a.setPoint), 1.2)
		end
	elseif a.kind == "MatchStart" then
		UIController.callout("Game on!", UI.Spark, string.format("%dv%d", a.mode or 3, a.mode or 3), 1.6)
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
	elseif a.kind == "MatchEnd" then
		showResults(a)
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
	stroke(f, 2, UI.InkSoft)
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
		r.serve.MouseButton1Click:Connect(op("serve"))
		r.up.MouseButton1Click:Connect(op("up"))
		r.down.MouseButton1Click:Connect(op("down"))
		rows[i] = r
	end
	local ready = button(f, "Ready", { Size = UDim2.fromOffset(150, 34), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -10), BackgroundColor3 = UI.Spark, TextColor3 = UI.Ink, TextSize = 14 })
	ready.MouseButton1Click:Connect(function()
		click()
		ui.rotation.ready = true
		Net.get("Timeout"):FireServer("ready")
	end)
	local swap = button(f, "Character and look", { Size = UDim2.fromOffset(200, 34), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), TextSize = 13 })
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

local function updateSlow()
	updateStamina()
	updateAbility()
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
	buildCallout()
	buildHint()
	buildAbility()
	buildRail()
	buildCorner()
	buildResults()
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
