-- HUD and menus. Visual language: stadium "ink" navy panels, team colours and the stamina and
-- ability colours carry the energy, one loud element at a time (manga callouts in Bangers),
-- numbers in Gotham Black, sentence case everywhere.
--
-- In play (modelled on The Spike's layout): a top bar with team names, stamina bars, score and
-- sets; the attack readout (km/h and hitting height) right below it; a "Team (Player) scored"
-- banner with the reason; name tags with tier badges and a marker over the player you control;
-- the ability panel; charge bars over your head; a timeout button.
-- In the lobby (tabs): Play - pick a tier and ability, spread that character's points over its
-- stats (up to its rolled caps), vote on the mode and the bot level; Shop - spend V Points on
-- x1 / x10 spins (stat caps, height, spike styles, colours, trails, score effects) and buy VP;
-- Locker - equip what you've unlocked.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Characters = require(Shared.Characters)
local Court = require(Shared.Court)
local Spins = require(Shared.Spins)
local Util = require(Shared.Util)
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
local selectedTier = nil
local myPick = nil -- the mode I picked this lobby

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
	t.serveDot.Visible = m.inMatch == true
	t.bar.Visible = m.inMatch == true
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
			if h then
				t.sub.Text = string.format("%d cm   %s", h, abilityName)
			else
				t.sub.Text = abilityName
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
	-- optional Toolbox icon (Assets.Images.Ability<Name>) to the left of the text
	local icon = make("ImageLabel", {
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(8, 6),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
	}, f)
	ui.ability = { frame = f, name = name, line = line, bar = bar, gauge = gauge, energy = energy, icon = icon, e = 0, g = 1, st = "idle" }

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

local function updateAbility()
	local a = ui.ability
	local playing = State.isPlaying and State.match.inMatch
	a.frame.Visible = playing == true
	local ability = State.myAbility()
	local def = Config.Abilities[ability]
	local stats = State.myStats()
	a.name.Text = def.Name
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
	if ability == "Thunder" then
		a.bar.Visible = false
		a.frame.Size = UDim2.fromOffset(250, 48)
		if stats.ContactMaxM >= Config.Hits.ThunderHeight then
			a.line.Text = "Hitting point " .. fmt2(stats.ContactMaxM) .. " m, thunder in reach"
			a.line.TextColor3 = THUNDER
		else
			a.line.Text = "Hitting point " .. fmt2(stats.ContactMaxM) .. " m, needs 4.00 m"
			a.line.TextColor3 = UI.Fog
		end
	else
		a.bar.Visible = true
		a.frame.Size = UDim2.fromOffset(250, 66)
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
}

local function buildRail()
	local rail = make("Frame", {
		Name = "ControlRail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.56, 0),
		Size = UDim2.fromOffset(124, 6 * 34),
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
	}
	for action, sl in pairs(r.slots) do
		local def = sl.def
		sl.slot.Visible = action ~= "Serve" or ctx.serving == true
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
-- timeout and settings buttons
------------------------------------------------------------------------------------------

local SETTINGS = {
	{ key = "landingMarker", text = "Landing marker" },
	{ key = "dramatic", text = "Impact frames and speed lines" },
	{ key = "assist", text = "Receive assist" },
	{ key = "closeCam", text = "Closer camera" },
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
	end)
	ui.timeout = timeout
end

local function updateTimeout()
	local b = ui.timeout
	local show = State.isPlaying and State.match.inMatch == true
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
-- lobby: Play (character + mode), Shop (V Points spins and packs), Locker (unlockables)
------------------------------------------------------------------------------------------

local SPINS = Config.Spins
local COS = Config.Cosmetics
local STAT_SHORT = { Attack = "ATK", Defense = "DEF", Speed = "SPD", Jump = "JMP" }
local tab = "Play"
local banner = "Caps"
local pendingPick = nil -- index of the pending result I've selected
local revealed = nil -- the snapshot whose reveal already played
local packPrices = {}

local function profile()
	return State.profile or { vp = 0, builds = {}, owned = {}, equip = {} }
end

local function activeTier()
	local t = player:GetAttribute("Tier")
	if Characters.isTier(t) then
		return t
	end
	return Config.DefaultTier
end

local function send(...)
	click()
	Net.get("Profile"):FireServer(...)
end

local function rarityStroke(parent, rarity, thickness)
	return stroke(parent, thickness or 2, Spins.rarityColor(rarity))
end

local function capsLine(caps)
	local parts = {}
	for _, k in ipairs(Config.Stats.Order) do
		table.insert(parts, tostring(caps[k] or "-"))
	end
	return table.concat(parts, " / ")
end

local function buildPlay(page)
	-- left column: tier and ability
	local left = make("Frame", { Size = UDim2.fromOffset(410, 420), BackgroundTransparency = 1 }, page)
	label(left, { Text = "Tier (sets the point total and how high caps can roll)", Font = Enum.Font.GothamBlack, TextSize = 13, Size = UDim2.new(1, 0, 0, 20) })
	local grid = make("Frame", { Size = UDim2.fromOffset(410, 120), Position = UDim2.fromOffset(0, 24), BackgroundTransparency = 1 }, left)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(74, 34), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local chips = {}
	for i = #Config.Tiers, 1, -1 do
		local tier = Config.Tiers[i]
		local caps = Characters.caps(tier)
		local b = button(grid, tier, { LayoutOrder = #Config.Tiers - i, TextSize = 16 })
		local capLabel = label(b, {
			Text = tostring(caps.Cap),
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextColor3 = UI.Fog,
			Size = UDim2.new(1, -6, 0, 10),
			Position = UDim2.new(0, 0, 1, -12),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		b.MouseButton1Click:Connect(function()
			click()
			selectedTier = tier
			Net.get("SetCharacter"):FireServer(tier, State.myAbility())
			UIController.refreshLobby()
		end)
		chips[tier] = { button = b, cap = capLabel }
	end

	label(left, { Text = "Ability", Font = Enum.Font.GothamBlack, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 152) })
	local cards = {}
	for i, key in ipairs(Config.AbilityOrder) do
		local def = Config.Abilities[key]
		local c = button(left, "", {
			Size = UDim2.fromOffset(200, 96),
			Position = UDim2.fromOffset((i - 1) * 210, 176),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		label(c, { Text = def.Name, Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = def.Color, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 6) })
		label(c, {
			Text = def.Blurb,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = UI.Fog,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -16, 0, 64),
			Position = UDim2.fromOffset(8, 28),
		})
		local iconId = Assets.id(Assets.Images["Ability" .. key])
		if iconId then
			make("ImageLabel", {
				Size = UDim2.fromOffset(30, 30),
				Position = UDim2.new(1, -36, 0, 4),
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
				Image = iconId,
			}, c)
		end
		c.MouseButton1Click:Connect(function()
			click()
			Net.get("SetCharacter"):FireServer(selectedTier or activeTier(), key)
		end)
		cards[key] = c
	end

	-- votes
	label(left, { Text = "Pick a mode to start", Font = Enum.Font.GothamBlack, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 284) })
	local votes = {}
	for i, n in ipairs({ 1, 2, 3 }) do
		local b = button(left, n .. "v" .. n, { Size = UDim2.fromOffset(94, 34), Position = UDim2.fromOffset((i - 1) * 102, 308) })
		b.MouseButton1Click:Connect(function()
			click()
			myPick = n
			Net.get("Vote"):FireServer("mode", n)
			UIController.refreshLobby()
		end)
		votes[n] = b
	end
	label(left, { Text = "Bot level", Font = Enum.Font.GothamBlack, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 350) })
	local botDown = button(left, "<", { Size = UDim2.fromOffset(40, 34), Position = UDim2.fromOffset(0, 374) })
	local botTier = label(left, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		Size = UDim2.fromOffset(100, 34),
		Position = UDim2.fromOffset(46, 374),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local botUp = button(left, ">", { Size = UDim2.fromOffset(40, 34), Position = UDim2.fromOffset(152, 374) })
	local function stepBot(d)
		click()
		local cur = Characters.tierIndex(State.match.botTier or Config.Match.DefaultBotTier) or 11
		local nextI = math.clamp(cur + d, 1, #Config.Tiers)
		Net.get("Vote"):FireServer("botTier", Config.Tiers[nextI])
	end
	botDown.MouseButton1Click:Connect(function()
		stepBot(-1)
	end)
	botUp.MouseButton1Click:Connect(function()
		stepBot(1)
	end)

	-- right column: the build. Points move freely between the stats, up to each rolled cap.
	local right = panel(page, {
		Size = UDim2.fromOffset(390, 420),
		Position = UDim2.fromOffset(430, 0),
		BackgroundColor3 = UI.InkSoft,
		BackgroundTransparency = 0.35,
	})
	local head = label(right, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 18, Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 10) })
	local capsGrade = label(right, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.fromOffset(12, 10),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local heightText = label(right, { Text = "", Font = Enum.Font.GothamBold, TextSize = 14, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 38) })
	local rows = {}
	local steps = { -10, -5, -1 }
	for i, stat in ipairs(Config.Stats.Order) do
		local y = 68 + (i - 1) * 44
		label(right, { Text = stat, Font = Enum.Font.GothamBlack, TextSize = 13, Size = UDim2.fromOffset(60, 30), Position = UDim2.fromOffset(10, y) })
		local row = { buttons = {} }
		for j, d in ipairs(steps) do
			local b = button(right, tostring(d), { Size = UDim2.fromOffset(34, 30), Position = UDim2.fromOffset(70 + (j - 1) * 36, y), TextSize = 12 })
			b.MouseButton1Click:Connect(function()
				send("alloc", selectedTier or activeTier(), stat, d)
			end)
			row.buttons[d] = b
		end
		row.value = label(right, {
			Text = "",
			Font = Enum.Font.GothamBlack,
			TextSize = 13,
			Size = UDim2.fromOffset(72, 26),
			Position = UDim2.fromOffset(180, y),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local track = make("Frame", {
			Size = UDim2.fromOffset(64, 4),
			Position = UDim2.fromOffset(184, y + 26),
			BackgroundColor3 = Color3.fromRGB(10, 12, 26),
			BorderSizePixel = 0,
		}, right)
		row.fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = UI.Chalk, BorderSizePixel = 0 }, track)
		for j, d in ipairs({ 1, 5, 10 }) do
			local b = button(right, "+" .. d, { Size = UDim2.fromOffset(34, 30), Position = UDim2.fromOffset(254 + (j - 1) * 36, y), TextSize = 12 })
			b.MouseButton1Click:Connect(function()
				send("alloc", selectedTier or activeTier(), stat, d)
			end)
			row.buttons[d] = b
		end
		rows[stat] = row
	end
	local free = label(right, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = UI.Spark, Size = UDim2.fromOffset(250, 26), Position = UDim2.fromOffset(12, 244) })
	local auto = button(right, "Auto", { Size = UDim2.fromOffset(70, 26), Position = UDim2.new(1, -82, 0, 244), TextSize = 12 })
	auto.MouseButton1Click:Connect(function()
		send("auto", selectedTier or activeTier())
	end)
	local derived = label(right, {
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -24, 0, 90),
		Position = UDim2.fromOffset(12, 278),
	})
	local notice = label(right, {
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = UI.Spark,
		TextWrapped = true,
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.new(0, 12, 1, -40),
	})
	return {
		chips = chips,
		cards = cards,
		votes = votes,
		botTier = botTier,
		head = head,
		capsGrade = capsGrade,
		heightText = heightText,
		rows = rows,
		free = free,
		derived = derived,
		notice = notice,
	}
end

-- A result card: stat caps, a height or an unlocked item.
local function resultCard(parent, i)
	local c = button(parent, "", {
		Size = UDim2.fromOffset(78, 92),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(28, 32, 60),
		LayoutOrder = i,
		Visible = false,
	})
	local s = stroke(c, 2, UI.Fog)
	local top = label(c, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 11, Size = UDim2.new(1, -6, 0, 14), Position = UDim2.fromOffset(3, 4), TextXAlignment = Enum.TextXAlignment.Center })
	local body = label(c, {
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -6, 1, -22),
		Position = UDim2.fromOffset(3, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local scale = make("UIScale", { Scale = 1 }, c)
	return { button = c, stroke = s, top = top, body = body, scale = scale }
end

local function buildShop(page)
	-- banners
	local list = make("Frame", { Size = UDim2.fromOffset(180, 420), BackgroundTransparency = 1 }, page)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local banners = {}
	for i, key in ipairs(SPINS.Order) do
		local def = SPINS.Banners[key]
		local b = button(list, "", { Size = UDim2.fromOffset(180, 50), LayoutOrder = i })
		label(b, { Text = def.Name, Font = Enum.Font.GothamBlack, TextSize = 14, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 6) })
		label(b, {
			Text = def.PerCharacter and "per character" or "unlocks for all",
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = UI.Fog,
			Size = UDim2.new(1, -16, 0, 14),
			Position = UDim2.fromOffset(8, 28),
		})
		b.MouseButton1Click:Connect(function()
			click()
			banner = key
			UIController.refreshLobby()
		end)
		banners[key] = b
	end

	-- the selected banner
	local mid = panel(page, { Size = UDim2.fromOffset(420, 420), Position = UDim2.fromOffset(190, 0), BackgroundColor3 = UI.InkSoft, BackgroundTransparency = 0.35 })
	local title = label(mid, { Text = "", Font = Enum.Font.Bangers, TextSize = 30, TextColor3 = UI.Spark, Size = UDim2.new(1, -24, 0, 32), Position = UDim2.fromOffset(12, 6) })
	stroke(title, 2, UI.Ink)
	local blurb = label(mid, { Text = "", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = UI.Fog, TextWrapped = true, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 38), TextYAlignment = Enum.TextYAlignment.Top })
	local current = label(mid, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 12, TextWrapped = true, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 68), TextYAlignment = Enum.TextYAlignment.Top })
	local odds = label(mid, { Text = "", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = UI.Fog, RichText = true, TextWrapped = true, Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 98) })
	local spin1 = button(mid, "", { Size = UDim2.fromOffset(190, 40), Position = UDim2.fromOffset(12, 120), BackgroundColor3 = UI.Spark, TextColor3 = UI.Ink })
	local spin10 = button(mid, "", { Size = UDim2.fromOffset(190, 40), Position = UDim2.new(1, -202, 0, 120), BackgroundColor3 = Color3.fromRGB(255, 120, 60), TextColor3 = UI.Ink })
	spin1.MouseButton1Click:Connect(function()
		send("spin", banner, 1, selectedTier or activeTier())
	end)
	spin10.MouseButton1Click:Connect(function()
		send("spin", banner, 10, selectedTier or activeTier())
	end)
	local grid = make("Frame", { Size = UDim2.fromOffset(410, 196), Position = UDim2.fromOffset(8, 168), BackgroundTransparency = 1 }, mid)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(78, 92), CellPadding = UDim2.fromOffset(3, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local results = {}
	for i = 1, 10 do
		local card = resultCard(grid, i)
		card.button.MouseButton1Click:Connect(function()
			click()
			pendingPick = i
			UIController.refreshLobby()
		end)
		results[i] = card
	end
	local keep = button(mid, "Keep", { Size = UDim2.fromOffset(120, 34), Position = UDim2.new(0, 12, 1, -44), BackgroundColor3 = UI.Mint, TextColor3 = UI.Ink, Visible = false })
	local discard = button(mid, "Discard", { Size = UDim2.fromOffset(120, 34), Position = UDim2.new(0, 140, 1, -44), Visible = false })
	local status = label(mid, { Text = "", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = UI.Spark, TextWrapped = true, Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 1, -44) })
	keep.MouseButton1Click:Connect(function()
		if pendingPick then
			send("keep", pendingPick)
		end
	end)
	discard.MouseButton1Click:Connect(function()
		send("discard")
	end)

	-- VP packs
	local right = make("Frame", { Size = UDim2.fromOffset(200, 420), Position = UDim2.fromOffset(620, 0), BackgroundTransparency = 1 }, page)
	label(right, { Text = "Get V Points", Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = UI.Spark, Size = UDim2.new(1, 0, 0, 22) })
	local packs = {}
	for i, pack in ipairs(Config.Shop.Packs) do
		local b = button(right, "", { Size = UDim2.fromOffset(200, 64), Position = UDim2.fromOffset(0, 28 + (i - 1) * 72) })
		label(b, { Text = pack.Name, Font = Enum.Font.GothamBlack, TextSize = 14, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(10, 8) })
		label(b, { Text = pack.VP .. " VP", Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = UI.Spark, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(10, 30) })
		local price = label(b, { Text = "", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = UI.Fog, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(10, 8), TextXAlignment = Enum.TextXAlignment.Right })
		b.MouseButton1Click:Connect(function()
			click()
			if pack.Id ~= 0 then
				pcall(function()
					MarketplaceService:PromptProductPurchase(player, pack.Id)
				end)
			elseif profile().studio then
				Net.get("Profile"):FireServer("buy", i)
			end
		end)
		packs[i] = { button = b, price = price }
		if pack.Id ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(pack.Id, Enum.InfoType.Product)
				end)
				if ok and info and info.PriceInRobux then
					packPrices[i] = info.PriceInRobux
					UIController.refreshLobby()
				end
			end)
		end
	end
	label(right, {
		Text = "Or earn them: " .. Config.Progression.WinVP .. " a win, " .. Config.Progression.LossVP .. " a loss, +" .. Config.Progression.PlayVP .. " per kill, ace or block.",
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = UI.Fog,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 320),
	})
	return {
		banners = banners,
		title = title,
		blurb = blurb,
		current = current,
		odds = odds,
		spin1 = spin1,
		spin10 = spin10,
		results = results,
		keep = keep,
		discard = discard,
		status = status,
		packs = packs,
	}
end

local function buildLocker(page)
	local rows = {}
	for r, kind in ipairs(COS.Kinds) do
		local y = (r - 1) * 104
		label(page, { Text = SPINS.Banners[kind].Name, Font = Enum.Font.GothamBlack, TextSize = 14, Size = UDim2.fromOffset(300, 20), Position = UDim2.fromOffset(0, y) })
		local chips = {}
		for i, item in ipairs(COS[kind]) do
			local b = button(page, "", { Size = UDim2.fromOffset(86, 72), Position = UDim2.fromOffset((i - 1) * 91, y + 24), BackgroundColor3 = Color3.fromRGB(28, 32, 60) })
			local s = rarityStroke(b, item.Rarity, 2)
			local swatch = nil
			if item.Color then
				swatch = make("Frame", { Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -24, 0, 6), BackgroundColor3 = item.Color, BorderSizePixel = 0 }, b)
				corner(swatch, 9)
			end
			label(b, { Text = item.Name, Font = Enum.Font.GothamBlack, TextSize = 11, TextWrapped = true, Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(5, 24), TextXAlignment = Enum.TextXAlignment.Center })
			local tag = label(b, { Text = "", Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Spins.rarityColor(item.Rarity), Size = UDim2.new(1, -10, 0, 12), Position = UDim2.new(0, 5, 1, -16), TextXAlignment = Enum.TextXAlignment.Center })
			b.MouseButton1Click:Connect(function()
				local owned = profile().owned and profile().owned[kind]
				if owned and owned[item.Key] then
					send("equip", kind, item.Key)
				else
					click()
					tab = "Shop"
					banner = kind
					UIController.refreshLobby()
				end
			end)
			chips[item.Key] = { button = b, stroke = s, tag = tag, item = item }
		end
		rows[kind] = chips
	end
	return { rows = rows }
end

local function buildLobby()
	local root = panel(gui, {
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(860, 540),
		Visible = false,
	})
	stroke(root, 2, UI.InkSoft)
	ui.lobbyScale = make("UIScale", {}, root)
	local title = label(root, {
		Text = "Spike Rush",
		Font = Enum.Font.Bangers,
		TextSize = 44,
		TextColor3 = UI.Spark,
		Size = UDim2.fromOffset(220, 50),
		Position = UDim2.fromOffset(20, 6),
	})
	stroke(title, 3, UI.Ink)
	local tabs = {}
	for i, name in ipairs({ "Play", "Shop", "Locker" }) do
		local b = button(root, name, { Size = UDim2.fromOffset(100, 34), Position = UDim2.fromOffset(240 + (i - 1) * 108, 14) })
		b.MouseButton1Click:Connect(function()
			click()
			tab = name
			UIController.refreshLobby()
		end)
		tabs[name] = b
	end
	local vp = label(root, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = UI.Spark,
		Size = UDim2.fromOffset(200, 34),
		Position = UDim2.new(1, -220, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	stroke(vp, 2, UI.Ink)
	local timer = label(root, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 15,
		TextColor3 = UI.Fog,
		Size = UDim2.new(1, -40, 0, 22),
		Position = UDim2.new(0, 20, 1, -30),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local pages = {}
	for _, name in ipairs({ "Play", "Shop", "Locker" }) do
		pages[name] = make("Frame", { Size = UDim2.fromOffset(820, 420), Position = UDim2.fromOffset(20, 62), BackgroundTransparency = 1, Visible = false }, root)
	end
	ui.lobby = {
		root = root,
		timer = timer,
		vp = vp,
		tabs = tabs,
		pages = pages,
		play = buildPlay(pages.Play),
		shop = buildShop(pages.Shop),
		locker = buildLocker(pages.Locker),
	}
end

local function refreshPlay(L, prof, tier)
	local build = prof.builds and prof.builds[tier]
	for t, chip in pairs(L.chips) do
		local on = t == tier
		chip.button.BackgroundColor3 = on and Characters.color(t) or UI.InkSoft
		chip.button.TextColor3 = on and UI.Ink or UI.Chalk
		chip.cap.TextColor3 = on and UI.Ink or UI.Fog
	end
	local ability = State.myAbility()
	for key, card in pairs(L.cards) do
		local on = key == ability
		card.BackgroundColor3 = on and Color3.fromRGB(52, 60, 108) or UI.InkSoft
	end
	local counts = State.match.votes or {}
	if State.match.phase ~= "Intermission" then
		myPick = nil
	end
	for n, b in pairs(L.votes) do
		b.Text = string.format("%dv%d   %d", n, n, counts["v" .. n] or 0)
		if myPick == n then
			b.BackgroundColor3 = UI.Spark
			b.TextColor3 = UI.Ink
		else
			b.BackgroundColor3 = UI.InkSoft
			b.TextColor3 = UI.Chalk
		end
	end
	L.botTier.Text = State.match.botTier or Config.Match.DefaultBotTier
	L.botTier.TextColor3 = Characters.color(L.botTier.Text)

	local caps = Characters.caps(tier)
	L.head.Text = tier .. " character"
	L.head.TextColor3 = Characters.color(tier)
	if not build then
		L.heightText.Text = "Height and stat caps roll when you pick it"
		L.capsGrade.Text = ""
		for _, row in pairs(L.rows) do
			row.value.Text = "-"
			row.fill.Size = UDim2.fromScale(0, 1)
		end
		L.free.Text = ""
		L.derived.Text = ""
		L.notice.Text = ""
		return
	end
	local statCaps = Characters.statCaps(tier, build)
	local grade = Characters.capsGrade(tier, statCaps)
	L.capsGrade.Text = grade .. " caps"
	L.capsGrade.TextColor3 = Spins.rarityColor(grade)
	local hGrade = Characters.heightGrade(build.Height)
	L.heightText.Text = string.format("Height %d cm  (%s)", build.Height, hGrade)
	L.heightText.TextColor3 = Spins.rarityColor(hGrade)
	local freePts = Characters.remaining(tier, build)
	for stat, row in pairs(L.rows) do
		local v = build[stat] or 0
		local cap = statCaps[stat]
		row.value.Text = v .. " / " .. cap
		row.value.TextColor3 = v >= cap and UI.Spark or UI.Chalk
		row.fill.Size = UDim2.fromScale(math.clamp((v - Config.Stats.Min) / math.max(1, cap - Config.Stats.Min), 0, 1), 1)
		local up = Characters.raisable(tier, build, stat, 1) > 0
		local down = Characters.lowerable(build, stat, 1) > 0
		for d, b in pairs(row.buttons) do
			b.TextColor3 = ((d > 0 and up) or (d < 0 and down)) and UI.Chalk or UI.Fog
		end
	end
	L.free.Text = string.format("Free points %d  (total %d of %d)", freePts, Characters.total(build), caps.Total)
	L.free.TextColor3 = freePts > 0 and UI.Spark or UI.Fog
	local s = Characters.derive(tier, build)
	local H = Config.Hits
	local lo, hi = H.SpikeKmhMin * s.Power, H.SpikeKmhMax * s.Power
	local thunder
	if s.ContactMaxM >= H.ThunderHeight then
		thunder = string.format("Thunder spikes %.0f to %.0f km/h", H.ThunderKmhMin * s.Power, H.ThunderKmhMax * s.Power)
	else
		thunder = "Thunder needs a 4.00 m hitting point"
	end
	L.derived.Text = string.format(
		"Hitting point %s m\nSpike speed %.0f to %.0f km/h\n%s\nStamina %d, run speed %.1f",
		fmt2(s.ContactMaxM),
		lo,
		hi,
		thunder,
		math.floor(s.StaminaPool + 0.5),
		s.WalkSpeed
	)
	if State.isPlaying and State.match.inMatch then
		L.notice.Text = "Your character is locked until this match ends."
	elseif prof.notice then
		L.notice.Text = prof.notice
	elseif prof.saving == false then
		L.notice.Text = "Progress isn't being saved in this session."
	else
		L.notice.Text = ""
	end
end

local function showCard(card, kind, value, tier)
	card.button.Visible = true
	if kind == "Caps" then
		local grade = Characters.capsGrade(tier, value)
		card.top.Text = grade
		card.top.TextColor3 = Spins.rarityColor(grade)
		local lines = {}
		for _, k in ipairs(Config.Stats.Order) do
			table.insert(lines, STAT_SHORT[k] .. " " .. tostring(value[k]))
		end
		card.body.Text = table.concat(lines, "\n")
		card.stroke.Color = Spins.rarityColor(grade)
	elseif kind == "Height" then
		local grade = Characters.heightGrade(value)
		card.top.Text = grade
		card.top.TextColor3 = Spins.rarityColor(grade)
		card.body.Text = "\n" .. tostring(value) .. " cm"
		card.body.TextSize = 16
		card.stroke.Color = Spins.rarityColor(grade)
	else
		local item = Spins.item(kind, value.key)
		local rarity = item and item.Rarity or "Common"
		card.top.Text = rarity
		card.top.TextColor3 = Spins.rarityColor(rarity)
		card.body.Text = (item and item.Name or "?") .. "\n\n" .. (value.dup and ("+" .. SPINS.DuplicateRefund .. " VP") or "NEW")
		card.stroke.Color = Spins.rarityColor(rarity)
	end
	if kind ~= "Height" then
		card.body.TextSize = 11
	end
end

-- Pop the cards in one after another.
local function playReveal(cards, count, best)
	for i = 1, count do
		local card = cards[i]
		card.scale.Scale = 0.2
		task.delay(0.06 * (i - 1), function()
			TweenService:Create(card.scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			if i == best then
				TweenService:Create(card.scale, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true, 0.25), { Scale = 1.08 }):Play()
			end
			click()
		end)
	end
	if mods.AudioController then
		task.delay(0.06 * count, function()
			mods.AudioController.play("Point")
		end)
	end
end

local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

local function refreshShop(L, prof, tier)
	for key, b in pairs(L.banners) do
		local on = key == banner
		b.BackgroundColor3 = on and Color3.fromRGB(52, 60, 108) or UI.InkSoft
	end
	local def = SPINS.Banners[banner]
	L.title.Text = def.Name
	L.blurb.Text = def.Blurb
	L.spin1.Text = "Spin x1   " .. SPINS.Costs[1] .. " VP"
	L.spin10.Text = "Spin x10   " .. SPINS.Costs[10] .. " VP"
	local vp = prof.vp or 0
	L.spin1.AutoButtonColor = vp >= SPINS.Costs[1]
	L.spin1.BackgroundTransparency = vp >= SPINS.Costs[1] and 0 or 0.5
	L.spin10.BackgroundTransparency = vp >= SPINS.Costs[10] and 0 or 0.5

	local build = prof.builds and prof.builds[tier]
	if banner == "Caps" then
		local caps = build and Characters.statCaps(tier, build)
		L.current.Text = caps and string.format("%s character now: %s  (%s)   caps roll %d to %d", tier, capsLine(caps), Characters.capsGrade(tier, caps), Characters.capFloor(tier), Characters.caps(tier).Cap)
			or (tier .. " character: pick it once to create it")
		L.odds.Text = "Grades by how close the four caps are to the tier cap. Higher caps are rarer."
	elseif banner == "Height" then
		L.current.Text = build and string.format("%s character now: %d cm (%s)   rolls %d to %d cm", tier, build.Height, Characters.heightGrade(build.Height), Config.Height.Min, Config.Height.Max) or (tier .. " character: pick it once to create it")
		L.odds.Text = "Most rolls land near " .. Config.Height.Mean .. " cm. 200 cm and up is legendary."
	else
		local owned, total = 0, 0
		for _, item in ipairs(COS[banner]) do
			total = total + 1
			if prof.owned and prof.owned[banner] and prof.owned[banner][item.Key] then
				owned = owned + 1
			end
		end
		L.current.Text = string.format("Unlocked %d of %d", owned, total)
		local o = Spins.odds(banner)
		local parts = {}
		for _, r in ipairs(Config.Rarity.Order) do
			if o[r] > 0 then
				table.insert(parts, string.format('<font color="#%s">%s %.0f%%</font>', hex(Spins.rarityColor(r)), r, o[r] * 100))
			end
		end
		L.odds.Text = table.concat(parts, "   ")
	end
	L.current.TextColor3 = UI.Chalk

	-- results: a pending stat or height spin (keep one), or the last item spin
	local pending = prof.pending
	local reveal = prof.reveal
	for _, card in ipairs(L.results) do
		card.button.Visible = false
		card.button.BackgroundColor3 = Color3.fromRGB(28, 32, 60)
	end
	L.keep.Visible = false
	L.discard.Visible = false
	L.status.Text = ""
	if pending then
		local best, bestScore = 1, -1
		for i, r in ipairs(pending.results) do
			local score = pending.banner == "Caps" and Characters.capsScore(pending.tier, r) or r
			if score > bestScore then
				best, bestScore = i, score
			end
			showCard(L.results[i], pending.banner, r, pending.tier)
		end
		if not pendingPick or not pending.results[pendingPick] then
			pendingPick = best
		end
		L.results[pendingPick].button.BackgroundColor3 = Color3.fromRGB(70, 84, 150)
		L.keep.Visible = true
		L.discard.Visible = true
		L.keep.Text = "Keep #" .. pendingPick
		if pending.banner ~= banner or pending.tier ~= tier then
			L.status.Text = ""
		end
		if revealed ~= prof and reveal then
			revealed = prof
			playReveal(L.results, #pending.results, best)
		end
	elseif reveal and reveal.items then
		local best, bestRank = 1, 0
		for i, it in ipairs(reveal.items) do
			showCard(L.results[i], reveal.banner, it, tier)
			local item = Spins.item(reveal.banner, it.key)
			local rank = item and RARITY_RANK[item.Rarity] or 1
			if rank > bestRank then
				best, bestRank = i, rank
			end
		end
		if revealed ~= prof then
			revealed = prof
			playReveal(L.results, #reveal.items, best)
		end
		L.status.Text = prof.notice or "Equip them in the Locker."
	else
		pendingPick = nil
		L.status.Text = prof.notice or ""
	end
	if pending then
		L.status.Text = ""
	end

	for i, pack in ipairs(Config.Shop.Packs) do
		local p = L.packs[i]
		if pack.Id ~= 0 then
			p.price.Text = packPrices[i] and ("R$ " .. packPrices[i]) or "..."
		elseif prof.studio then
			p.price.Text = "Studio: free"
		else
			p.price.Text = "Soon"
		end
	end
end

local function refreshLocker(L, prof)
	for kind, chips in pairs(L.rows) do
		local owned = prof.owned and prof.owned[kind] or {}
		local equipped = prof.equip and prof.equip[kind] or Spins.default(kind)
		for key, chip in pairs(chips) do
			local have = owned[key] == true
			chip.button.BackgroundColor3 = key == equipped and Color3.fromRGB(70, 84, 150) or Color3.fromRGB(28, 32, 60)
			chip.button.BackgroundTransparency = have and 0 or 0.5
			chip.stroke.Thickness = key == equipped and 3 or 2
			if key == equipped then
				chip.tag.Text = "Equipped"
				chip.tag.TextColor3 = UI.Spark
			elseif have then
				chip.tag.Text = chip.item.Rarity
				chip.tag.TextColor3 = Spins.rarityColor(chip.item.Rarity)
			else
				chip.tag.Text = "Locked"
				chip.tag.TextColor3 = UI.Fog
			end
		end
	end
end

function UIController.refreshLobby()
	local L = ui.lobby
	if not L then
		return
	end
	local tier = selectedTier or activeTier()
	local prof = profile()
	-- a fresh spin result jumps to the shop
	if prof.reveal and revealed ~= prof then
		tab = "Shop"
		if prof.reveal.banner then
			banner = prof.reveal.banner
		end
	end
	L.vp.Text = tostring(prof.vp or 0) .. " VP"
	for name, b in pairs(L.tabs) do
		local on = name == tab
		b.BackgroundColor3 = on and UI.Spark or UI.InkSoft
		b.TextColor3 = on and UI.Ink or UI.Chalk
		L.pages[name].Visible = on
	end
	refreshPlay(L.play, prof, tier)
	refreshShop(L.shop, prof, tier)
	refreshLocker(L.locker, prof)
end

local function updateLobby()
	local L = ui.lobby
	local phase = State.phase()
	local show = phase == "Intermission" or not State.isPlaying
	L.root.Visible = show
	if show then
		local left = math.max(0, math.ceil((State.match.phaseEnd or 0) - Util.now()))
		if phase == "Intermission" and State.match.waitingForPick then
			L.timer.Text = "Pick 1v1, 2v2 or 3v3 on the Play tab to start a match"
			L.timer.TextColor3 = UI.Spark
		elseif phase == "Intermission" then
			L.timer.Text = "Match starts in " .. left
			L.timer.TextColor3 = UI.Fog
		else
			L.timer.Text = "Match in progress, you join at the next rally"
			L.timer.TextColor3 = UI.Fog
		end
		local cam = workspace.CurrentCamera
		if cam then
			ui.lobbyScale.Scale = math.clamp(cam.ViewportSize.Y / 640, 0.55, 1.1)
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
	local list = make("Frame", { Size = UDim2.new(1, -40, 1, -110), Position = UDim2.fromOffset(20, 96), BackgroundTransparency = 1 }, f)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	ui.results = { frame = f, title = title, mvp = mvp, list = list }
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
	if a.forfeit then
		r.mvp.Text = teamName(a.forfeit) .. " forfeited"
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
		UIController.callout("Set to " .. teamName(a.winner), teamColor(a.winner), string.format("%d-%d", a.sets.Home or 0, a.sets.Away or 0), 2.4)
	elseif a.kind == "MatchEnd" then
		showResults(a)
	elseif a.kind == "Serve" then
		if a.id == State.myId then
			showHint("Your serve: tap X for an overhand serve, hold X to toss for a jump serve")
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
	ui.rotation = { frame = f, title = title, rows = rows }
end

local function updateRotation()
	local R = ui.rotation
	local show = State.isPlaying and State.match.inMatch == true and State.phase() == "Timeout" and State.myTeam ~= nil
	R.frame.Visible = show
	if not show then
		return
	end
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
	R.frame.Size = UDim2.fromOffset(460, 64 + #roster * 46)
end

local function updateSlow()
	updateStamina()
	updateAbility()
	updateTimeout()
	updateRotation()
	updateLobby()
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
	buildLobby()
	buildResults()
	buildRotation()

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
		UIController.refreshLobby()
	end)
	State.signals.Profile:Connect(function()
		UIController.refreshLobby()
	end)
	State.signals.Charge:Connect(function(energy, gauge, st)
		ui.ability.e = energy
		ui.ability.g = gauge
		ui.ability.st = st
	end)
	player:GetAttributeChangedSignal("Tier"):Connect(function()
		selectedTier = nil
		UIController.refreshLobby()
	end)
	player:GetAttributeChangedSignal("Ability"):Connect(UIController.refreshLobby)
	UIController.refreshLobby()
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
