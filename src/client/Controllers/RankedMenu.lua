-- Ranked (Config.Ranked, the Ranked module): the Ranked window from the Match screen's card, and
-- the bans before a ranked match.
--   * the window: your Career on the left (the highest rank you've reached, your rank's badge and
--     name, its progress bar, this season's wins and losses, when the season ends), the queues on
--     the right (1v1, 2v2, 3v3: real players only; your party queues with you), and a card for
--     each season along the bottom (its number, your rank in it, your wins and losses; the owner's
--     reference, without the lock);
--   * the bans (MatchService's "Bans" announcement): every character in a grid, your team picks
--     one to ban, both bans showing, then the match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Ranked = require(Shared.Ranked)
local Roster = require(Shared.Roster)
local Characters = require(Shared.Characters)
local Assets = require(Shared.Assets)
local Util = require(Shared.Util)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local RankedMenu = {}
local RC = Config.Ranked
local mods, kit
local ui = {}

local function make(...)
	return kit.make(...)
end

local function label(parent, props)
	props.ZIndex = props.ZIndex or 23
	return Gui.label(parent, props)
end

local function record()
	local p = kit.profile()
	return Ranked.clean(p and p.ranked, Ranked.season(Util.now()))
end

-- A rank's badge: its picture (Assets.Images Rank<Key>) when there is one, else a gem in its
-- colour with the division's pips. Returns a setter(rp) and the frame.
function RankedMenu.badge(parent, size, props)
	local f = make("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ZIndex = 23 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	local glow = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.5, 1.5), BackgroundTransparency = 1, Image = Assets.id(Assets.Fx.Glow) or "", ImageTransparency = 0.55, ZIndex = f.ZIndex }, f)
	local img = make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = f.ZIndex + 2 }, f)
	local gem = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62), Rotation = 45, BorderSizePixel = 0, ZIndex = f.ZIndex + 1 }, f)
	make("UICorner", { CornerRadius = UDim.new(0.18, 0) }, gem)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 120, 130)) }, gem)
	local stroke = make("UIStroke", { Thickness = math.max(2, size * 0.04), Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, gem)
	local pips = label(f, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.3), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = f.ZIndex + 3 })
	make("UIStroke", { Thickness = 2, Color = Color3.fromRGB(10, 10, 16) }, pips)
	local ROMAN = { "I", "II", "III" }
	local function set(rp)
		local _, rank, div = Ranked.rankOf(rp)
		-- (each division has its own picture; the rank's own is the fallback)
		local own = Assets.image(Ranked.badgeKey(rp))
		local pic = own or Assets.image("Rank" .. rank.Key)
		img.Image = pic or ""
		img.Visible = pic ~= nil
		gem.Visible = pic == nil
		gem.BackgroundColor3 = rank.Color
		stroke.Color = rank.Color:Lerp(Color3.new(1, 1, 1), 0.55)
		glow.ImageColor3 = rank.Color
		pips.Text = div and ROMAN[div] or (rank.Key == "Almighty" and "A" or "M")
		pips.Visible = pic == nil or (div ~= nil and own == nil) -- (a division's own picture shows its pips)
	end
	return set, f
end

------------------------------------------------------------------------------------------
-- the window
------------------------------------------------------------------------------------------

local function seasonCard(parent, order)
	local c = make("Frame", { Size = UDim2.fromOffset(350, 92), BackgroundColor3 = Color3.fromRGB(10, 12, 20), BorderSizePixel = 0, LayoutOrder = order, ZIndex = 22 }, parent)
	Gui.corner(c, 12)
	local stroke = make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, c)
	local grad = make("UIGradient", { Rotation = 0, Transparency = NumberSequence.new(0.2, 0.75) }, c)
	label(c, { Text = "★ RANKED", display = true, TextSize = 13, TextColor3 = Gui.GOLD, Position = UDim2.fromOffset(18, 8), Size = UDim2.fromOffset(120, 16) })
	local title = label(c, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 32, Position = UDim2.fromOffset(16, 22), Size = UDim2.fromOffset(220, 38) })
	local titleGrad = make("UIGradient", { Rotation = 0 }, title)
	local wl = label(c, { Text = "", RichText = true, display = true, TextSize = 17, Position = UDim2.fromOffset(18, 62), Size = UDim2.fromOffset(220, 22) })
	local setBadge = RankedMenu.badge(c, 76, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), ZIndex = 23 })
	return { frame = c, stroke = stroke, grad = grad, title = title, titleGrad = titleGrad, wl = wl, setBadge = setBadge }
end

local function fillSeasonCard(card, season, rp, peak, wins, losses, current)
	local _, rank = Ranked.rankOf(peak)
	card.title.Text = "SEASON " .. season
	card.titleGrad.Color = ColorSequence.new(rank.Color:Lerp(Color3.new(1, 1, 1), 0.5), rank.Color)
	card.wl.Text = string.format('<font color="#5BE38A">W: %d</font>   <font color="#FF6B6B">L: %d</font>   %s', wins, losses, Ranked.name(peak))
	card.setBadge(peak)
	card.grad.Color = ColorSequence.new(rank.Color:Lerp(Color3.new(0, 0, 0), 0.55), Color3.fromRGB(10, 12, 20))
	card.stroke.Color = current and Gui.SIGNAL or Gui.HAIRLINE
	card.stroke.Transparency = current and 0 or 0.4
end

local function buildWindow()
	local m = kit.modal("Ranked", "Ranked", 1180, 680, true)
	ui.window = m
	-- Career (left)
	local career = Gui.card(m.panel, { Position = UDim2.fromOffset(28, 86), Size = UDim2.fromOffset(420, 360), ZIndex = 22 })
	local best = label(career, { Text = "", display = true, TextSize = 18, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	local setBadge = RankedMenu.badge(career, 150, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44) })
	local rankName = label(career, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 38, Position = UDim2.fromOffset(0, 202), Size = UDim2.new(1, 0, 0, 42), TextXAlignment = Enum.TextXAlignment.Center })
	local track = make("Frame", { Position = UDim2.fromOffset(30, 254), Size = UDim2.new(1, -60, 0, 16), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, ZIndex = 23 }, career)
	Gui.corner(track, 8)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Gui.SIGNAL, BorderSizePixel = 0, ZIndex = 24 }, track)
	Gui.corner(fill, 8)
	local prog = label(career, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(0, 274), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	local wl = label(career, { Text = "", RichText = true, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, Position = UDim2.fromOffset(0, 300), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center })
	local ends = label(career, { Text = "", TextSize = 14, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(0, 332), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	ui.career = { best = best, setBadge = setBadge, rankName = rankName, fill = fill, prog = prog, wl = wl, ends = ends }
	-- the queues (right)
	local q = Gui.card(m.panel, { Position = UDim2.fromOffset(468, 86), Size = UDim2.new(1, -496, 0, 360), ZIndex = 22 })
	label(q, { Text = "Play ranked", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, Position = UDim2.fromOffset(22, 14), Size = UDim2.new(1, -44, 0, 36) })
	label(q, { Text = "Real players only: it waits until both teams are full. Win to climb, lose and you drop. Before the match each team bans two characters. Your party queues with you, on your side.", TextSize = 16, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(22, 54), Size = UDim2.new(1, -44, 0, 64) })
	ui.queues = {}
	for i, mode in ipairs(RC.Modes) do
		local b, l = kit.actionPlate(q, { Position = UDim2.fromOffset(22 + (i - 1) * 200, 132), Size = UDim2.fromOffset(186, 80) }, string.format("%dv%d", mode, mode), 30)
		kit.onClick(b, function()
			local lock = Ranked.banLeft(record(), Util.now())
			if lock > 0 then
				kit.toast(string.format("You left a ranked match: you can queue again in %d:%02d.", math.floor(lock / 60), math.floor(lock % 60)))
				return
			end
			local mine = kit.lobbies() and kit.lobbies().mine
			if mine and not (mine.ranked and mine.mode == mode) then
				kit.toast("You're in a lobby: leave it first.")
				return
			end
			if not mine then
				Net.get("Lobby"):FireServer("ranked", mode)
			end
		end)
		ui.queues[mode] = l
	end
	ui.queueLine = label(q, { Text = "", display = true, TextSize = 20, TextColor3 = Gui.SIGNAL, Position = UDim2.fromOffset(22, 226), Size = UDim2.new(1, -44, 0, 26) })
	local leave, leaveL = kit.hairButton(q, { Position = UDim2.fromOffset(22, 262), Size = UDim2.fromOffset(200, 44) }, "Leave the queue", 17)
	kit.onClick(leave, function()
		Net.get("Lobby"):FireServer("leave")
	end)
	ui.leave = leave
	local party = kit.hairButton(q, { Position = UDim2.fromOffset(236, 262), Size = UDim2.fromOffset(200, 44) }, "Party", 17)
	kit.onClick(party, function()
		if mods.PartyMenu then
			mods.PartyMenu.open()
		end
	end)
	ui.partyLine = label(q, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(22, 314), Size = UDim2.new(1, -44, 0, 20) })
	-- the seasons (bottom)
	label(m.panel, { Text = "Seasons", display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, Position = UDim2.fromOffset(28, 456), Size = UDim2.fromOffset(300, 28) })
	local row = make("ScrollingFrame", { Position = UDim2.fromOffset(28, 488), Size = UDim2.new(1, -56, 0, 108), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 5, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ZIndex = 22 }, m.panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	ui.seasonRow = row
	ui.seasonCards = {}
end

-- Left a ranked match early: a pop-up at the top offers the way back while it's still on
-- (Config.Ranked.Leave.RejoinSeconds); rejoining lifts the penalty. Dismiss keeps the penalty.
local function buildRejoin()
	local gui = make("ScreenGui", { Name = "SpikeRushRankedRejoin", ResetOnSpawn = false, DisplayOrder = 46 }, Players.LocalPlayer:WaitForChild("PlayerGui"))
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(500, 104), BackgroundColor3 = Color3.fromRGB(14, 16, 28), BorderSizePixel = 0, Visible = false }, gui)
	Gui.corner(f, 10)
	make("UIStroke", { Color = Color3.fromRGB(255, 107, 107), Thickness = 2 }, f)
	local text = Gui.label(f, { Text = "", display = true, TextSize = 17, TextWrapped = true, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 50) })
	local yes = kit.actionPlate(f, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -130, 1, -10), Size = UDim2.fromOffset(150, 34) }, "Rejoin match", 17)
	local no = kit.hairButton(f, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -10), Size = UDim2.fromOffset(106, 34) }, "Dismiss", 16)
	kit.onClick(yes, function()
		Net.get("Lobby"):FireServer("rejoinRanked")
		f.Visible = false
	end)
	kit.onClick(no, function()
		ui.rejoinDismissed = ui.rejoinKey
		Net.get("Lobby"):FireServer("forgetRanked")
		f.Visible = false
	end)
	ui.rejoin = { frame = f, text = text }
end

local function refreshRejoin()
	if not ui.rejoin then
		return
	end
	local rec = record()
	local left = Ranked.rejoinable(rec, Util.now())
	local show = left ~= nil and not State.isPlaying and ui.rejoinDismissed ~= left.key
	ui.rejoinKey = left and left.key
	ui.rejoin.frame.Visible = show
	if show then
		local lock = Ranked.banLeft(rec, Util.now())
		ui.rejoin.text.Text = string.format("You left a ranked match: %d RP and the queue locked for %d:%02d. Rejoin it while it's on and you get them back.", left.d or 0, math.floor(lock / 60), math.floor(lock % 60))
	end
end

function RankedMenu.refresh()
	refreshRejoin()
	if not ui.window or not ui.window.root.Visible then
		return
	end
	local rec = record()
	local C = ui.career
	local bestIdx = math.max(rec.best or 0, (Ranked.rankOf(rec.peak)))
	C.best.Text = "Highest rank: " .. ((rec.best or 0) > 0 and RC.Ranks[bestIdx].Name or "unranked")
	C.setBadge(rec.rp)
	C.rankName.Text = Ranked.name(rec.rp)
	local _, rank, _, from, to = Ranked.rankOf(rec.rp)
	C.rankName.TextColor3 = rank.Color:Lerp(Color3.new(1, 1, 1), 0.25)
	C.fill.Size = UDim2.fromScale(Ranked.progress(rec.rp), 1)
	C.fill.BackgroundColor3 = rank.Color
	C.prog.Text = to and string.format("%d / %d RP to %s", rec.rp - from, to - from, Ranked.name(to)) or string.format("%d RP: the top", rec.rp)
	C.wl.Text = string.format('<font color="#5BE38A">Wins: %d</font>   <font color="#FF6B6B">Losses: %d</font>', rec.wins, rec.losses)
	local left = Ranked.seasonEnds(rec.season) - Util.now()
	C.ends.Text = string.format("Season %d ends in %s", rec.season, kit.clockText and left < 86400 and kit.clockText(left) or string.format("%d days", math.max(0, math.floor(left / 86400))))
	-- the queue you're in
	local mine = kit.lobbies() and kit.lobbies().mine
	local inRanked = mine and mine.ranked
	ui.queueLine.Text = inRanked and string.format("Ranked %dv%d: %d / %d players. Waiting for real players...", mine.mode, mine.mode, mine.count or 0, mine.capacity or 0) or ""
	ui.leave.Visible = inRanked == true
	local lock = Ranked.banLeft(rec, Util.now())
	for mode, l in pairs(ui.queues) do
		l.Text = (inRanked and mine.mode == mode) and "Queued" or (lock > 0 and string.format("%d:%02d", math.floor(lock / 60), math.floor(lock % 60))) or string.format("%dv%d", mode, mode)
	end
	if lock > 0 and not inRanked then
		ui.queueLine.Text = "Locked: you left a ranked match early."
	end
	local party = mods.PartyMenu and mods.PartyMenu.current()
	ui.partyLine.Text = party and string.format("Party of %d%s", #party.members, party.leader == Players.LocalPlayer.UserId and " (you lead)" or ": your leader queues") or "Solo. Make a party to queue with friends."
	-- the season cards: this one first, then the past ones
	local list = { { season = rec.season, rp = rec.rp, peak = rec.peak, wins = rec.wins, losses = rec.losses, current = true } }
	for _, h in ipairs(rec.history or {}) do
		table.insert(list, h)
	end
	for i, s in ipairs(list) do
		local card = ui.seasonCards[i]
		if not card then
			card = seasonCard(ui.seasonRow, i)
			ui.seasonCards[i] = card
		end
		card.frame.Visible = true
		fillSeasonCard(card, s.season, s.rp, math.max(s.peak or 0, s.rp or 0), s.wins or 0, s.losses or 0, s.current)
	end
	for i = #list + 1, #ui.seasonCards do
		ui.seasonCards[i].frame.Visible = false
	end
end

function RankedMenu.open()
	ui.window.root.Visible = true
	RankedMenu.refresh()
end

------------------------------------------------------------------------------------------
-- the bans
------------------------------------------------------------------------------------------

local function buildBans()
	-- (its own screen: the menus hide while you're on court) a 1600 x 900 canvas scaled to fit
	local gui = make("ScreenGui", { Name = "SpikeRushBans", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, Players.LocalPlayer:WaitForChild("PlayerGui"))
	local shade = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 4, 12), BackgroundTransparency = 0.12, BorderSizePixel = 0, Visible = false, ZIndex = 59 }, gui)
	local root = make("Frame", { Name = "RankedBans", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), BackgroundTransparency = 1, ZIndex = 60 }, shade)
	local scale = make("UIScale", { Scale = 1 }, root)
	local function fit()
		local cam = workspace.CurrentCamera
		local v = cam and cam.ViewportSize or Vector2.new(1600, 900)
		scale.Scale = math.min(v.X / 1600, v.Y / 900)
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	local title = label(root, { Text = "BAN A CHARACTER", display = true, weight = Enum.FontWeight.Heavy, TextSize = 52, TextColor3 = Color3.fromRGB(255, 70, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(900, 60), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 61 })
	local sub = label(root, { Text = "", TextSize = 19, TextColor3 = Gui.DIM, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(1100, 24), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 61 })
	local timer = label(root, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 40, TextColor3 = Gui.SIGNAL, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 34), Size = UDim2.fromOffset(160, 50), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 61 })
	local grid = make("ScrollingFrame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 130), Size = UDim2.fromOffset(1240, 560), BackgroundColor3 = Color3.fromRGB(20, 8, 12), BackgroundTransparency = 0.2, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 61 }, root)
	Gui.corner(grid, 12)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingTop = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }, grid)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(226, 110), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	-- best first
	local order = {}
	for _, c in ipairs(Roster) do
		table.insert(order, c)
	end
	table.sort(order, function(a, b)
		local ra, rb = Characters.tierIndex(a.Tier) or 0, Characters.tierIndex(b.Tier) or 0
		if ra ~= rb then
			return ra > rb
		end
		return a.Name < b.Name
	end)
	local cells = {}
	for i, c in ipairs(order) do
		local color = Characters.color(c.Tier)
		local b = make("TextButton", { BackgroundColor3 = Color3.fromRGB(30, 20, 60), AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 62 }, grid)
		Gui.corner(b, 10)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(Color3.fromRGB(30, 20, 60), 0.6), Color3.fromRGB(20, 14, 40)) }, b)
		local stroke = make("UIStroke", { Color = color, Thickness = 2, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		label(b, { Text = c.Tier, display = true, weight = Enum.FontWeight.Heavy, TextSize = 18, TextColor3 = color, Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(60, 20), ZIndex = 63 })
		local name = label(b, { Text = c.Name, display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, Position = UDim2.fromOffset(8, 30), Size = UDim2.new(1, -16, 0, 44), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 63 })
		make("UITextSizeConstraint", { MaxTextSize = 34 }, name)
		make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, name)
		local tag = label(b, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 18, TextColor3 = Color3.fromRGB(255, 80, 80), Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 63 })
		kit.onClick(b, function()
			Net.get("Lobby"):FireServer("ban", c.Id)
		end)
		cells[c.Id] = { button = b, stroke = stroke, tag = tag, name = name }
	end
	ui.bans = { root = shade, title = title, sub = sub, timer = timer, cells = cells }
end

local function showBans(bans)
	local B = ui.bans
	local mine = State.myTeam
	local other = mine == "Home" and "Away" or "Home"
	bans = bans or {}
	local ourList, theirList = bans[mine] or {}, bans[other] or {}
	for id, c in pairs(B.cells) do
		local ours, theirs = table.find(ourList, id) ~= nil, table.find(theirList, id) ~= nil
		c.tag.Text = ours and "YOUR BAN" or (theirs and "THEIR BAN" or "")
		c.stroke.Transparency = (ours or theirs) and 0 or 0.5
		c.stroke.Color = (ours or theirs) and Color3.fromRGB(255, 60, 60) or Characters.color(Roster.get(id) and Roster.get(id).Tier)
		c.button.BackgroundTransparency = (ours or theirs) and 0.5 or 0
	end
	local per = RC.BansPerTeam
	local function names(list)
		local out = {}
		for i = 1, per do
			local c = list[i] and Roster.get(list[i])
			table.insert(out, c and c.Name or "...")
		end
		return table.concat(out, ", ")
	end
	B.sub.Text = string.format("Each team bans %d (your team's first %d picks count): nobody plays them this match.   Yours: %s   Theirs: %s", per, per, names(ourList), names(theirList))
end

local function onAnnounce(a)
	if type(a) ~= "table" or not ui.bans then
		return
	end
	if a.kind == "Bans" then
		ui.banEnds = a.endsAt
		ui.bans.root.Visible = State.isPlaying == true
		showBans(a.bans)
	elseif a.kind == "BanUpdate" then
		showBans(a.bans)
		if a.team ~= State.myTeam then
			local c = a.id and Roster.get(a.id)
			kit.toast(string.format("The other team banned %s.", c and c.Name or "someone"))
		end
	elseif a.kind == "BansDone" or a.kind == "MatchStart" or a.kind == "MatchAbort" then
		ui.bans.root.Visible = false
		ui.banEnds = nil
		if a.kind == "BansDone" and a.bans then
			local names = {}
			for _, list in pairs(a.bans) do
				for _, id in ipairs(list) do
					local c = Roster.get(id)
					table.insert(names, c and c.Name or id)
				end
			end
			if #names > 0 then
				kit.toast("Banned this match: " .. table.concat(names, ", "))
			end
		end
	end
end

function RankedMenu.init(m)
	mods = m
	kit = mods.MenuController.kit()
	buildWindow()
	buildBans()
	buildRejoin()
	State.signals.Announce:Connect(onAnnounce)
	State.signals.Profile:Connect(function()
		RankedMenu.refresh()
	end)
	Net.get("Lobbies").OnClientEvent:Connect(function()
		task.defer(RankedMenu.refresh)
	end)
	-- the ban timer
	local nextTick = 0
	game:GetService("RunService").Heartbeat:Connect(function()
		if ui.banEnds and ui.bans.root.Visible then
			ui.bans.timer.Text = string.format("%d s", math.max(0, math.ceil(ui.banEnds - Util.now())))
		end
		-- (the queue lock and the rejoin offer count down)
		if os.clock() >= nextTick then
			nextTick = os.clock() + 1
			RankedMenu.refresh()
		end
	end)
end

return RankedMenu
