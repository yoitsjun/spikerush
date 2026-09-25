-- HUD and menus. Visual language: stadium "ink" navy panels, team colours and the stamina and
-- ability colours carry the energy, one loud element at a time (manga callouts in Bangers),
-- numbers in Gotham Black, sentence case everywhere.
--
-- In play (modelled on The Spike's layout): a top bar with team names, stamina bars, score and
-- sets; the attack readout (km/h and hitting height) right below it; a "Team (Player) scored"
-- banner with the reason; name tags with tier badges and a marker over the player you control;
-- the ability panel; charge bars over your head; a timeout button.
-- In the lobby: pick a tier and ability, upgrade that character's stats with your points,
-- re-roll its height, vote on the mode and the bot level.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Characters = require(Shared.Characters)
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
	label(mid, {
		Text = "VS",
		Font = Enum.Font.Bangers,
		TextSize = 24,
		TextColor3 = UI.Fog,
		Size = UDim2.fromOffset(60, 44),
		Position = UDim2.fromOffset(90, 4),
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
	ui.top = { bar = bar, Home = home, Away = away, sHome = sHome, sAway = sAway, setLine = setLine, serveDot = serveDot, kmh = kmh, height = height, shownAt = -10 }
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
	t.setLine.Text = string.format("Set %d   sets %d-%d", m.setNumber or 1, sets.Home or 0, sets.Away or 0)
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
	{ action = "Spike", glyph = "\u{1F4A5}", key = "Z", pad = "A", color = Color3.fromRGB(235, 70, 60) },
	{ action = "Receive", glyph = "\u{1F6E1}", key = "S", pad = "B", color = Color3.fromRGB(50, 130, 235) },
	{ action = "SlideFeint", glyph = "\u{1F4A8}", key = "C", pad = "RB", color = Color3.fromRGB(70, 180, 140) },
	{ action = "Block", glyph = "\u{270B}", key = "W", pad = "Y", color = Color3.fromRGB(120, 110, 220) },
	{ action = "Set", glyph = "\u{1F64C}", key = "E", pad = "LB", color = Color3.fromRGB(240, 170, 60) },
	{ action = "Serve", glyph = "\u{1F3D0}", key = "X", pad = "X", color = Color3.fromRGB(245, 200, 40) },
}

local function buildRail()
	local rail = make("Frame", {
		Name = "ControlRail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.56, 0),
		Size = UDim2.fromOffset(96, 6 * 82),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	ui.railScale = make("UIScale", {}, rail)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, rail)
	local slots = {}
	for i, def in ipairs(RAIL) do
		local slot = make("Frame", { Size = UDim2.fromOffset(96, 76), BackgroundTransparency = 1, LayoutOrder = i }, rail)
		local b = make("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(56, 56),
			BackgroundColor3 = UI.Ink,
			BackgroundTransparency = 0.25,
			AutoButtonColor = false,
			Text = def.glyph,
			TextSize = 26,
			Font = Enum.Font.GothamBlack,
			TextColor3 = UI.Chalk,
		}, slot)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		local ring = make("UIStroke", { Thickness = 2.5, Color = UI.Chalk, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local badge = make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -2, 0, 4),
			Size = UDim2.fromOffset(26, 18),
			BackgroundColor3 = UI.Chalk,
			TextColor3 = UI.Ink,
			Font = Enum.Font.GothamBlack,
			TextSize = 11,
			Text = def.key,
		}, b)
		make("UICorner", { CornerRadius = UDim.new(0, 5) }, badge)
		local name = label(slot, {
			Text = def.action,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 58),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		stroke(name, 1.5, UI.Ink)
		-- mouse users can click the rail too
		b.MouseButton1Down:Connect(function()
			mods.ActionController.press(def.action)
		end)
		local function up()
			mods.ActionController.release(def.action)
		end
		b.MouseButton1Up:Connect(up)
		b.MouseLeave:Connect(up)
		slots[def.action] = { slot = slot, button = b, ring = ring, badge = badge, name = name, def = def }
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
			sl.ring.Thickness = 4
			sl.ring.Transparency = 0
			sl.button.BackgroundColor3 = def.color:Lerp(UI.Ink, 0.55)
		else
			sl.ring.Color = UI.Chalk
			sl.ring.Thickness = 2.5
			sl.ring.Transparency = 0.45
			sl.button.BackgroundColor3 = UI.Ink
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
-- lobby: character builder
------------------------------------------------------------------------------------------

local function profile()
	return State.profile or { points = 0, builds = {} }
end

local function activeTier()
	local t = player:GetAttribute("Tier")
	if Characters.isTier(t) then
		return t
	end
	return Config.DefaultTier
end

local function buildLobby()
	local root = panel(gui, {
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(860, 520),
		Visible = false,
	})
	stroke(root, 2, UI.InkSoft)
	ui.lobbyScale = make("UIScale", {}, root)
	local title = label(root, {
		Text = "Spike Rush",
		Font = Enum.Font.Bangers,
		TextSize = 44,
		TextColor3 = UI.Spark,
		Size = UDim2.fromOffset(300, 50),
		Position = UDim2.fromOffset(20, 8),
	})
	stroke(title, 3, UI.Ink)
	local timer = label(root, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextColor3 = UI.Fog,
		Size = UDim2.fromOffset(460, 24),
		Position = UDim2.new(1, -480, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	-- left column: tier and ability
	local left = make("Frame", { Size = UDim2.fromOffset(410, 400), Position = UDim2.fromOffset(20, 64), BackgroundTransparency = 1 }, root)
	label(left, { Text = "Tier (sets your stat caps)", Font = Enum.Font.GothamBlack, TextSize = 14, Size = UDim2.new(1, 0, 0, 20) })
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

	-- right column: the build
	local right = panel(root, {
		Size = UDim2.fromOffset(390, 430),
		Position = UDim2.fromOffset(450, 64),
		BackgroundColor3 = UI.InkSoft,
		BackgroundTransparency = 0.35,
	})
	local head = label(right, { Text = "", Font = Enum.Font.GothamBlack, TextSize = 18, Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 10) })
	local points = label(right, {
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextColor3 = UI.Spark,
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 10),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local heightText = label(right, { Text = "", Font = Enum.Font.GothamBold, TextSize = 14, Size = UDim2.fromOffset(200, 30), Position = UDim2.fromOffset(12, 40) })
	local reroll = button(right, "Re-roll height (" .. Config.Progression.HeightRollCost .. ")", {
		Size = UDim2.fromOffset(170, 30),
		Position = UDim2.new(1, -182, 0, 40),
		TextSize = 12,
	})
	reroll.MouseButton1Click:Connect(function()
		click()
		Net.get("Profile"):FireServer("reroll", selectedTier or activeTier())
	end)
	local rows = {}
	for i, stat in ipairs(Config.Stats.Order) do
		local y = 82 + (i - 1) * 44
		label(right, { Text = stat, Font = Enum.Font.GothamBlack, TextSize = 14, Size = UDim2.fromOffset(70, 30), Position = UDim2.fromOffset(12, y) })
		local track = make("Frame", {
			Size = UDim2.fromOffset(120, 10),
			Position = UDim2.fromOffset(84, y + 10),
			BackgroundColor3 = Color3.fromRGB(10, 12, 26),
			BorderSizePixel = 0,
		}, right)
		corner(track, 5)
		local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = UI.Chalk, BorderSizePixel = 0 }, track)
		corner(fill, 5)
		local value = label(right, {
			Text = "",
			Font = Enum.Font.GothamBlack,
			TextSize = 13,
			Size = UDim2.fromOffset(70, 30),
			Position = UDim2.fromOffset(210, y),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local plus1 = button(right, "+1", { Size = UDim2.fromOffset(40, 30), Position = UDim2.fromOffset(284, y), TextSize = 13 })
		local plus5 = button(right, "+5", { Size = UDim2.fromOffset(40, 30), Position = UDim2.fromOffset(330, y), TextSize = 13 })
		plus1.MouseButton1Click:Connect(function()
			click()
			Net.get("Profile"):FireServer("upgrade", selectedTier or activeTier(), stat, 1)
		end)
		plus5.MouseButton1Click:Connect(function()
			click()
			Net.get("Profile"):FireServer("upgrade", selectedTier or activeTier(), stat, 5)
		end)
		rows[stat] = { fill = fill, value = value, plus1 = plus1, plus5 = plus5 }
	end
	local total = label(right, { Text = "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = UI.Fog, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 258) })
	local derived = label(right, {
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -24, 0, 110),
		Position = UDim2.fromOffset(12, 282),
	})
	local notice = label(right, {
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = UI.Spark,
		TextWrapped = true,
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.new(0, 12, 1, -36),
	})

	ui.lobby = {
		root = root,
		timer = timer,
		chips = chips,
		cards = cards,
		votes = votes,
		botTier = botTier,
		head = head,
		points = points,
		heightText = heightText,
		reroll = reroll,
		rows = rows,
		total = total,
		derived = derived,
		notice = notice,
	}
end

function UIController.refreshLobby()
	local L = ui.lobby
	if not L then
		return
	end
	local tier = selectedTier or activeTier()
	local prof = profile()
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
	L.points.Text = "Upgrade points " .. tostring(prof.points or 0)
	if not build then
		L.heightText.Text = "Height rolls when you pick it"
		for _, row in pairs(L.rows) do
			row.value.Text = "-"
			row.fill.Size = UDim2.fromScale(0, 1)
		end
		L.total.Text = ""
		L.derived.Text = ""
		return
	end
	L.heightText.Text = "Height " .. tostring(build.Height) .. " cm"
	local canAfford = (prof.points or 0) > 0
	for stat, row in pairs(L.rows) do
		local v = build[stat] or 0
		row.value.Text = v .. " / " .. caps.Cap
		row.fill.Size = UDim2.fromScale(math.clamp((v - Config.Stats.Min) / (caps.Cap - Config.Stats.Min), 0, 1), 1)
		local room = Characters.raisable(tier, build, stat, 5)
		row.plus1.TextColor3 = (room > 0 and canAfford) and UI.Chalk or UI.Fog
		row.plus5.TextColor3 = (room > 0 and canAfford) and UI.Chalk or UI.Fog
	end
	L.total.Text = string.format("Total %d of %d, %d still to spend on this character", Characters.total(build), caps.Total, Characters.remaining(tier, build))
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

local function updateLobby()
	local L = ui.lobby
	local phase = State.phase()
	local show = phase == "Intermission" or not State.isPlaying
	L.root.Visible = show
	if show then
		local left = math.max(0, math.ceil((State.match.phaseEnd or 0) - Util.now()))
		if phase == "Intermission" and State.match.waitingForPick then
			L.timer.Text = "Pick 1v1, 2v2 or 3v3 to start a match"
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
	{ "Points", 0.87, 0.12 },
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
		if a.matchPoint then
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
	elseif a.kind == "TimeoutCalled" then
		showHint(teamName(a.team) .. " called a timeout (next dead ball)")
	elseif a.kind == "Timeout" then
		UIController.callout("Timeout", teamColor(a.team), "Stamina refilled", 1.6)
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

local function updateSlow()
	updateStamina()
	updateAbility()
	updateTimeout()
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
