-- Live scoreboard: hold Tab during a match (playing or spectating) to see both teams' stats
-- for this match, best score first. One card per team: its emblem and name on a slanted plate,
-- a role badge, headshot and name per player, then spikes (kills), aces, blocks, assists, top
-- spike speed and a score (the match-MVP rating MatchService uses, minus the win bonus). The
-- leader of each column is yellow, the overall leader wears the MVP pill, and your own row has
-- your team's edge. The numbers ride on the roster of every MatchState broadcast
-- (TeamService.matchStats), which goes out on every point, so the board updates after each point.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Gui = require(script.Parent.Gui)
local State = require(script.Parent.State)

local ScoreboardController = {}

local player = Players.LocalPlayer
local make = Gui.make

local PANEL_W = 960
local CARD_PAD = 8
local HEAD_H = 64
local ROW_H = 52
local ROW_GAP = 3
local GAP = 10

local COLS = {
	{ key = "k", label = "SPIKES", icon = "IconAttack", w = 96 },
	{ key = "a", label = "ACES", icon = "AbilityZeroPoint", w = 88 },
	{ key = "bt", label = "BLOCKS", icon = "IconDefense", w = 96 },
	{ key = "s", label = "AST", icon = "IconJump", w = 80 },
	{ key = "t", label = "TOP KM/H", icon = "IconSpeed", w = 120 },
	{ key = "pts", label = "SCORE", icon = "IconStar", w = 100, score = true },
}
local COLS_W = 0
for _, c in ipairs(COLS) do
	COLS_W = COLS_W + c.w
end
local NAME_W = PANEL_W - CARD_PAD * 2 - COLS_W
local CARD_BASE = Color3.fromRGB(10, 14, 30)

local ZERO = { k = 0, a = 0, b = 0, bt = 0, d = 0, s = 0, e = 0, t = 0 }

local gui, root, scale
local visible = false
local naturalH = 200

local function lighten(c, a)
	return c:Lerp(Color3.new(1, 1, 1), a)
end

local function scoreOf(st)
	return (st.k or 0) + (st.a or 0) * 1.5 + (st.b or 0) * 1.5 + (st.d or 0) * 0.5 + (st.s or 0) * 0.4 - (st.e or 0) * 0.6
end

local function value(st, key)
	if key == "pts" then
		return scoreOf(st)
	end
	return st[key] or 0
end

local function fmt(key, v)
	if key == "t" then
		return v > 0 and string.format("%.0f", v) or "-"
	end
	if key == "pts" then
		return string.format("%.1f", v)
	end
	return tostring(v)
end

-- Both teams' rows sorted by score, the best value of every column, and the overall leader.
local function collect()
	local teams, best, mvp, mvpScore = {}, {}, nil, 0
	for _, c in ipairs(COLS) do
		best[c.key] = 0
	end
	for _, team in ipairs(Config.TeamOrder) do
		local list = {}
		for _, e in ipairs(State.roster(team)) do
			local st = e.st or ZERO
			local sc = scoreOf(st)
			table.insert(list, { e = e, st = st, score = sc })
			for _, c in ipairs(COLS) do
				local v = value(st, c.key)
				if v > best[c.key] then
					best[c.key] = v
				end
			end
			if sc > mvpScore then
				mvp, mvpScore = e.id, sc
			end
		end
		table.sort(list, function(x, y)
			if x.score ~= y.score then
				return x.score > y.score
			end
			return (x.e.rot or 0) < (y.e.rot or 0)
		end)
		teams[team] = list
	end
	return teams, best, mvp
end

local function avatar(parent, e, size, teamColor)
	local uid = type(e.id) == "string" and string.match(e.id, "^P_(%d+)$")
	local f = make("Frame", {
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromOffset(46, (ROW_H - size) / 2),
		BackgroundColor3 = Gui.NAVY_LIGHT,
		BorderSizePixel = 0,
	}, parent)
	Gui.corner(f, 6)
	Gui.stroke(f, 1.5, teamColor, 0.35, true)
	if uid then
		local im = make("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = string.format("rbxthumb://type=AvatarHeadShot&id=%s&w=60&h=60", uid),
		}, f)
		Gui.corner(im, 6)
	else
		Gui.label(f, {
			Text = "AI",
			display = true,
			weight = Enum.FontWeight.Heavy,
			TextSize = 16,
			TextColor3 = Gui.DIM,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
		}, f)
	end
end

local function mvpPill(parent, x)
	local pill = make("Frame", {
		Size = UDim2.fromOffset(86, 26),
		Position = UDim2.fromOffset(x, (ROW_H - 26) / 2),
		BackgroundColor3 = Gui.NAVY,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, parent)
	Gui.round(pill)
	Gui.stroke(pill, 1.5, Gui.SIGNAL, 0.1, true)
	Gui.iconImage(pill, "AbilityTyrant", 18, Gui.SIGNAL, { Position = UDim2.fromOffset(10, 4) })
	Gui.label(pill, {
		Text = "MVP",
		display = true,
		weight = Enum.FontWeight.Heavy,
		TextSize = 17,
		TextColor3 = Gui.SIGNAL,
		Size = UDim2.new(1, -34, 1, 0),
		Position = UDim2.fromOffset(32, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
end

local function buildRow(parent, row, order, best, topScore, isMvp, team)
	local def = Config.Teams[team]
	local e = row.e
	local isMe = e.id == State.myId
	local f = make("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundColor3 = isMe and def.Dark or Color3.fromRGB(8, 12, 28),
		BackgroundTransparency = isMe and 0.3 or 0.5,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	if isMe then
		Gui.stroke(f, 2, def.Color, 0.05, true)
	else
		make("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.new(0, 0, 1, -1),
			BackgroundColor3 = Gui.CHALK,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
		}, f)
	end
	if isMvp then
		make("Frame", {
			Size = UDim2.new(0, 4, 1, 0),
			Position = UDim2.new(1, -4, 0, 0),
			BackgroundColor3 = def.Color,
			BorderSizePixel = 0,
		}, f)
	end

	-- the court role: a square badge, filled with the team's colour for you
	local role = Config.Roles[e.role or ""]
	local badge = make("Frame", {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(8, (ROW_H - 30) / 2),
		BackgroundColor3 = isMe and def.Color or Gui.NAVY_LIGHT,
		BorderSizePixel = 0,
	}, f)
	Gui.corner(badge, 6)
	Gui.label(badge, {
		Text = role and role.Short or "?",
		display = true,
		weight = Enum.FontWeight.Heavy,
		TextSize = 14,
		TextColor3 = isMe and Gui.INK or Gui.CHALK,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	avatar(f, e, 40, def.Color)
	Gui.label(f, {
		Text = e.name or "?",
		display = true,
		weight = Enum.FontWeight.Bold,
		TextSize = 24,
		TextColor3 = e.isBot and Gui.MUTED or Gui.CHALK,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(NAME_W - 96 - (isMvp and 100 or 8), ROW_H),
		Position = UDim2.fromOffset(96, 0),
	})
	if isMvp then
		mvpPill(f, NAME_W - 94)
	end

	local x = NAME_W
	for _, c in ipairs(COLS) do
		local v = value(row.st, c.key)
		local color = Gui.CHALK
		if c.score then
			if v > 0 and v == best[c.key] then
				color = Gui.SIGNAL
			elseif v > 0 and row.score == topScore then
				color = lighten(def.Color, 0.4)
			end
		elseif v > 0 and v == best[c.key] then
			color = Gui.SIGNAL
		end
		Gui.label(f, {
			Text = fmt(c.key, v),
			display = true,
			weight = Enum.FontWeight.Heavy,
			TextSize = c.score and 32 or 28,
			TextColor3 = color,
			TextTransparency = (v == 0 and not c.score) and 0.4 or 0,
			Size = UDim2.fromOffset(c.w, ROW_H),
			Position = UDim2.fromOffset(x, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
		}, f)
		x = x + c.w
	end
end

local function teamCardHeight(n)
	return CARD_PAD + HEAD_H + 6 + n * ROW_H + math.max(0, n - 1) * ROW_GAP + CARD_PAD
end

local function buildTeam(parent, team, list, best, mvp, order)
	local def = Config.Teams[team]
	local card = make("Frame", {
		Size = UDim2.fromOffset(PANEL_W, teamCardHeight(#list)),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Gui.corner(card, 8)
	Gui.stroke(card, 2, def.Color, 0.05, true)
	Gui.gradient(card, def.Dark:Lerp(CARD_BASE, 0.55), CARD_BASE, 90)

	-- the plate: emblem and team name, its right end slanted
	local plate = Gui.plate(card, {
		Size = UDim2.fromOffset(NAME_W + 70, HEAD_H),
		Position = UDim2.fromOffset(CARD_PAD, CARD_PAD),
		ZIndex = 2,
	}, def.Dark, { flatLeft = true })
	Gui.halftone(plate, { Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromScale(0.6, 0), ZIndex = 2 })
	Gui.iconImage(plate, def.Icon, 46, def.Color, { Position = UDim2.fromOffset(16, (HEAD_H - 46) / 2), ZIndex = 3 })
	local name = Gui.label(plate, {
		Text = string.upper(def.Name),
		display = true,
		weight = Enum.FontWeight.Heavy,
		TextSize = 40,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(NAME_W - 40, HEAD_H),
		Position = UDim2.fromOffset(76, 0),
		ZIndex = 3,
	})
	Gui.gradient(name, lighten(def.Color, 0.6), def.Color, 90)

	-- the column heads: an icon over its label, a hairline between them
	local x = CARD_PAD + NAME_W
	for i, c in ipairs(COLS) do
		if i > 1 then
			make("Frame", {
				Size = UDim2.fromOffset(1, 44),
				Position = UDim2.fromOffset(x, CARD_PAD + 10),
				BackgroundColor3 = Gui.CHALK,
				BackgroundTransparency = 0.86,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, card)
		end
		Gui.iconImage(card, c.icon, 24, c.score and Gui.SIGNAL or Gui.CHALK, {
			Position = UDim2.fromOffset(x + (c.w - 24) / 2, CARD_PAD + 8),
			ZIndex = 2,
		})
		Gui.label(card, {
			Text = c.label,
			weight = Enum.FontWeight.Bold,
			TextSize = 13,
			TextColor3 = Gui.CHALK,
			TextTransparency = 0.1,
			Size = UDim2.fromOffset(c.w, 16),
			Position = UDim2.fromOffset(x, CARD_PAD + 38),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 2,
		})
		x = x + c.w
	end

	local rows = make("Frame", {
		Size = UDim2.fromOffset(PANEL_W - CARD_PAD * 2, #list * ROW_H + math.max(0, #list - 1) * ROW_GAP),
		Position = UDim2.fromOffset(CARD_PAD, CARD_PAD + HEAD_H + 6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, card)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, ROW_GAP) }, rows)
	local topScore = list[1] and list[1].score or 0
	for i, row in ipairs(list) do
		buildRow(rows, row, i, best, topScore, row.e.id == mvp, team)
	end
end

local function render()
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local teams, best, mvp = collect()
	if #teams.Home + #teams.Away == 0 then
		naturalH = 80
		Gui.label(root, {
			Text = "No match in progress",
			display = true,
			weight = Enum.FontWeight.Bold,
			TextSize = 28,
			TextColor3 = Gui.DIM,
			Size = UDim2.fromOffset(PANEL_W, 56),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		return
	end

	local total, n = 0, 0
	for i, team in ipairs(Config.TeamOrder) do
		local list = teams[team]
		if #list > 0 then
			buildTeam(root, team, list, best, mvp, i)
			total = total + teamCardHeight(#list) + (n > 0 and GAP or 0)
			n = n + 1
		end
	end
	naturalH = total + 16
end

local function fit()
	local cam = workspace.CurrentCamera
	if cam and scale then
		local vp = cam.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / (PANEL_W + 56), vp.Y / (naturalH + 56)), 0.4, 1)
	end
end

local function show()
	if visible or not State.watching() then
		return
	end
	visible = true
	render()
	fit()
	root.GroupTransparency = 1
	gui.Enabled = true
	TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
end

local function hide()
	if not visible then
		return
	end
	visible = false
	gui.Enabled = false
end

-- also callable from elsewhere (a button, a test)
ScoreboardController.show = show
ScoreboardController.hide = hide

function ScoreboardController.init(mods)
	gui = make("ScreenGui", {
		Name = "SpikeRushScoreboard",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	root = make("CanvasGroup", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_W + 16, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, gui)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, root)
	make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, root)
	scale = make("UIScale", {}, root)

	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	-- Hold Tab. Ignored while typing (chat), so a Tab in a text box never opens it.
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Tab and not processed then
			show()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			hide()
		end
	end)
	UserInputService.WindowFocusReleased:Connect(hide)

	-- live while it is held: every MatchState broadcast (each point) redraws it
	State.signals.Match:Connect(function()
		if visible then
			if State.watching() then
				render()
				fit()
			else
				hide()
			end
		end
	end)
end

return ScoreboardController
