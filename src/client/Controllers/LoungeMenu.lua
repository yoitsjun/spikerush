-- The AFK Lounge's screen (Config.Lounge, LoungeService; the owner: "add an afk chamber", after
-- another game's AFK Lounge): opened from AFK at the top right of the main screens, it covers the
-- menus in a dark room with an ember glow:
--   * the title and "rewards keep coming while you rest";
--   * the big card: the countdown to the next payout, its bar, how often a reward is rolled, and
--     the chips (how many rewards there are, VIP's x2 and Premium's x1.5, lit when yours);
--   * three cards: the last reward rolled, today's rewards against the daily limit, your balance;
--   * the odds' two ends (the top reward and the bottom line), Get VIP (when you haven't got it)
--     and Return to game;
--   * a line on the refresh that keeps you past Roblox's idle limit;
--   * on the left, the odds (the owner: "show a probability table on the left"): every reward,
--     the top one first, at your multiplier, with its chance;
--   * on the right, the side panel (the owner: "in the sidebar, let it show how much you've
--     made"): this stay's Gold, V Points, lucky spins and boosts, and its latest rolls.
-- The countdown runs here between the server's updates (LoungeService.send).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Economy = require(Shared.Economy)
local Lounge = require(Shared.Lounge)
local Gui = require(script.Parent.Gui)

local LoungeMenu = {}
local L = Config.Lounge
local player = Players.LocalPlayer
local mods, kit
local ui = {}
local state = nil -- the server's last word (LoungeService.send), and when it came
local stateAt = 0
local EMBER = Color3.fromRGB(232, 40, 52)
local EMBER_DEEP = Color3.fromRGB(70, 6, 12)
local BLUE = Color3.fromRGB(90, 200, 255)
local Z = 40
-- a reward's colour by its Tier (Config.Lounge.Rewards)
local TIER = { Color3.fromRGB(200, 204, 216), Color3.fromRGB(110, 220, 120), Color3.fromRGB(90, 170, 255), Color3.fromRGB(190, 110, 255), Color3.fromRGB(255, 200, 60) }
local MAIN_W = 860 -- the main column's width
local SIDE_W = 290 -- the side panels' (the odds on the left, this stay on the right)
local GAP = 16

local function make(...)
	return kit.make(...)
end

local function label(parent, props)
	props.ZIndex = props.ZIndex or Z + 2
	return Gui.label(parent, props)
end

-- a dark rounded card with a faint edge
local function card(parent, props, edge)
	local f = make("Frame", { BackgroundColor3 = Color3.fromRGB(14, 14, 18), BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = Z + 1 }, parent)
	for k, v in pairs(props) do
		f[k] = v
	end
	make("UICorner", { CornerRadius = UDim.new(0, 18) }, f)
	make("UIStroke", { Color = edge or Color3.fromRGB(70, 70, 82), Thickness = 1.5, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	return f
end

-- a pill with a label (chips and the reward line)
local function pill(parent, props, text, size)
	local f = make("Frame", { BackgroundColor3 = Color3.fromRGB(26, 26, 32), BorderSizePixel = 0, ZIndex = Z + 2 }, parent)
	for k, v in pairs(props) do
		f[k] = v
	end
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	local stroke = make("UIStroke", { Color = Color3.fromRGB(70, 70, 82), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	local l = label(f, { Text = text, display = true, weight = Enum.FontWeight.Heavy, TextSize = size or 16, RichText = true, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z + 3 })
	return f, l, stroke
end

local function bar(parent, props)
	local back = make("Frame", { BackgroundColor3 = Color3.fromRGB(40, 40, 48), BorderSizePixel = 0, ZIndex = Z + 2 }, parent)
	for k, v in pairs(props) do
		back[k] = v
	end
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, back)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = EMBER, BorderSizePixel = 0, ZIndex = Z + 3 }, back)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)
	return fill
end

local function clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function build()
	local root = make("Frame", { Name = "Lounge", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = Z }, kit.canvas)
	-- the room: near black past the canvas's edges, an ember glow rising from the floor
	local shade = make("TextButton", { Name = "Shade", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(3, 3), BackgroundColor3 = Color3.fromRGB(4, 3, 5), BackgroundTransparency = 0.04, Text = "", AutoButtonColor = false, ZIndex = Z }, root)
	shade:SetAttribute("NoNav", true)
	local glow = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1.6, 0, 0.75, 0), BackgroundColor3 = EMBER_DEEP, BorderSizePixel = 0, ZIndex = Z }, root)
	make("UIGradient", { Rotation = -90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.6, 0.85), NumberSequenceKeypoint.new(1, 1) }) }, glow)

	-- the main column, between the side panels
	local main = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, MAIN_W, 1, 0), BackgroundTransparency = 1, ZIndex = Z }, root)

	-- the title
	label(main, { Text = "AFK LOUNGE", display = true, weight = Enum.FontWeight.Heavy, TextSize = 64, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(700, 70), TextXAlignment = Enum.TextXAlignment.Center })
	local underline = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 106), Size = UDim2.fromOffset(64, 5), BackgroundColor3 = EMBER, BorderSizePixel = 0, ZIndex = Z + 2 }, main)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, underline)
	pill(main, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 122), Size = UDim2.fromOffset(470, 38) }, '<font color="#E8283A">Zz</font>  REWARDS KEEP COMING WHILE YOU REST', 19)

	-- the big card: the countdown
	local big = card(main, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 172), Size = UDim2.fromOffset(860, 360), ClipsDescendants = true }, Color3.fromRGB(90, 60, 66))
	local ember = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 0.6), BackgroundColor3 = EMBER, BorderSizePixel = 0, ZIndex = Z + 1 }, big)
	make("UIGradient", { Rotation = -90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }) }, ember)
	make("UICorner", { CornerRadius = UDim.new(0, 18) }, ember)
	Gui.halftone(big, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 0, 200), ImageColor3 = Gui.CHALK, ImageTransparency = 0.92, ZIndex = Z + 1 })
	ui.head = label(big, { Text = "NEXT REWARD IN", display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextColor3 = Gui.MUTED, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26), Size = UDim2.fromOffset(500, 24), TextXAlignment = Enum.TextXAlignment.Center })
	ui.timer = label(big, { Text = "10:00", display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, -- (TextSize stops at 100)
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 50), Size = UDim2.fromOffset(700, 150), TextXAlignment = Enum.TextXAlignment.Center })
	make("UIStroke", { Color = Color3.fromRGB(110, 14, 24), Thickness = 4 }, ui.timer)
	ui.fill = bar(big, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 214), Size = UDim2.fromOffset(640, 10) })
	local rewardPill, rewardL, rewardStroke = pill(big, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 244), Size = UDim2.fromOffset(420, 50), BackgroundColor3 = Color3.fromRGB(40, 8, 14) }, "", 25)
	rewardStroke.Color = EMBER
	ui.reward, ui.rewardPill = rewardL, rewardPill
	ui.rewardScale = make("UIScale", { Scale = 1 }, rewardPill)
	local chips = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 304), Size = UDim2.fromOffset(640, 36), BackgroundTransparency = 1, ZIndex = Z + 2 }, big)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	ui.chipBase = { pill(chips, { Size = UDim2.fromOffset(170, 36), LayoutOrder = 1 }, "", 19) }
	ui.chipVip = { pill(chips, { Size = UDim2.fromOffset(140, 36), LayoutOrder = 2 }, "", 19) }
	ui.chipPremium = { pill(chips, { Size = UDim2.fromOffset(190, 36), LayoutOrder = 3 }, "", 19) }

	-- the three cards
	local function stat(i, title)
		local c = card(main, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, (i - 2) * 292, 0, 548), Size = UDim2.fromOffset(276, 118) })
		label(c, { Text = title, display = true, weight = Enum.FontWeight.Heavy, TextSize = 19, TextColor3 = Gui.MUTED, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
		local value = label(c, { Text = "0", display = true, weight = Enum.FontWeight.Heavy, TextSize = 38, RichText = true, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
		local sub = label(c, { Text = "", TextSize = 19, weight = Enum.FontWeight.Medium, TextColor3 = Gui.MUTED, RichText = true, Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
		return c, value, sub
	end
	local _, earned, earnedSub = stat(1, "LAST REWARD")
	earned.TextScaled = true -- (a long name fits the card)
	earned.Position = UDim2.fromOffset(14, 38)
	earned.Size = UDim2.new(1, -28, 0, 36)
	local todayCard, today, todaySub = stat(2, "TODAY")
	ui.todayFill = bar(todayCard, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 102), Size = UDim2.new(1, -60, 0, 6) })
	local balCard, balance, balSub = stat(3, "BALANCE")
	Gui.icon.gold(balCard, 28).Position = UDim2.new(0, 24, 0, 44)
	ui.earned, ui.earnedSub, ui.today, ui.todaySub, ui.balance, ui.balSub = earned, earnedSub, today, todaySub, balance, balSub

	ui.luck = label(main, { Text = "", TextSize = 22, weight = Enum.FontWeight.Medium, TextColor3 = Gui.MUTED, RichText = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 682), Size = UDim2.fromOffset(860, 24), TextXAlignment = Enum.TextXAlignment.Center })

	-- the odds: every reward, the top one first
	local odds = card(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -MAIN_W / 2 - GAP, 0, 172), Size = UDim2.fromOffset(SIDE_W, 494), ClipsDescendants = true }, Color3.fromRGB(90, 60, 66))
	label(odds, { Text = "REWARD ODDS", display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	ui.oddsRows = {}
	local n = #L.Rewards
	local rowH = math.min(26, math.floor((494 - 58) / n))
	for k = 1, n do
		local i = n - k + 1
		local c = TIER[L.Rewards[i].Tier] or Gui.CHALK
		local r = make("Frame", { Position = UDim2.fromOffset(12, 50 + (k - 1) * rowH), Size = UDim2.new(1, -24, 0, rowH - 2), BackgroundColor3 = Color3.fromRGB(24, 22, 28), BackgroundTransparency = k % 2 == 1 and 0 or 1, BorderSizePixel = 0, ZIndex = Z + 2 }, odds)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, r)
		local name = label(r, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 16, TextColor3 = c, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.7, -10, 1, 0), ZIndex = Z + 3 })
		label(r, { Text = tostring(math.floor(Lounge.chance(i) * 1000 + 0.5) / 10) .. "%", display = true, weight = Enum.FontWeight.Heavy, TextSize = 16, TextColor3 = Gui.MUTED, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0.3, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = Z + 3 })
		ui.oddsRows[i] = name
	end

	-- the side panel: this stay's totals and its latest rolls
	local side = card(root, { Position = UDim2.new(0.5, MAIN_W / 2 + GAP, 0, 172), Size = UDim2.fromOffset(SIDE_W, 494), ClipsDescendants = true }, Color3.fromRGB(90, 60, 66))
	label(side, { Text = "MADE THIS STAY", display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	ui.sideCount = label(side, { Text = "", TextSize = 17, weight = Enum.FontWeight.Medium, TextColor3 = Gui.MUTED, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	local function row(y, name, color, icon)
		local r = make("Frame", { Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 34), BackgroundColor3 = Color3.fromRGB(24, 22, 28), BorderSizePixel = 0, ZIndex = Z + 2 }, side)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, r)
		if icon then
			icon(r, 22).Position = UDim2.new(0, 8, 0.5, -11)
		else
			local dot = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 13, 0.5, 0), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = Z + 3 }, r)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
		end
		label(r, { Text = name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 17, TextColor3 = Gui.MUTED, Position = UDim2.fromOffset(38, 0), Size = UDim2.new(0.6, -38, 1, 0), ZIndex = Z + 3 })
		local v = label(r, { Text = "0", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = color, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0.45, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = Z + 3 })
		return { value = v, color = color }
	end
	ui.rows = {
		Gold = row(72, "GOLD", Gui.GOLD, Gui.icon.gold),
		VP = row(110, "V POINTS", BLUE, Gui.icon.vp),
		Lucky = row(148, "LUCKY SPINS", TIER[5]),
		BoostVP = row(186, "2x VP", TIER[3]),
		BoostLuck = row(224, "2x LUCK", TIER[4]),
	}
	local rule = make("Frame", { Position = UDim2.fromOffset(24, 272), Size = UDim2.new(1, -48, 0, 2), BackgroundColor3 = Color3.fromRGB(60, 50, 58), BorderSizePixel = 0, ZIndex = Z + 2 }, side)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, rule)
	label(side, { Text = "LATEST ROLLS", display = true, weight = Enum.FontWeight.Heavy, TextSize = 17, TextColor3 = Gui.MUTED, Position = UDim2.fromOffset(0, 284), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	ui.logRows = {}
	for k = 1, L.LogSize do
		ui.logRows[k] = label(side, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 17, RichText = true, Position = UDim2.fromOffset(18, 286 + k * 23), Size = UDim2.new(1, -36, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	end
	ui.logEmpty = label(side, { Text = "Your first reward comes when the timer runs out.", TextSize = 17, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(24, 316), Size = UDim2.new(1, -48, 0, 48), TextXAlignment = Enum.TextXAlignment.Center })

	-- Get VIP and Return to game
	local buttons = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 722), Size = UDim2.fromOffset(700, 70), BackgroundTransparency = 1, ZIndex = Z + 2 }, main)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }, buttons)
	local vip = Gui.plateButton(buttons, { Size = UDim2.fromOffset(300, 68), LayoutOrder = 1, ZIndex = Z + 2 }, Gui.GOLD, Gui.GOLD_LIGHT)
	vip:SetAttribute("Sound", "UIConfirm")
	ui.vipL = label(vip, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z + 4 })
	ui.vip = vip
	kit.onClick(vip, function()
		local def = Config.Passes.VIP
		if def and def.PassId then
			MarketplaceService:PromptGamePassPurchase(player, def.PassId)
		end
	end)
	local back = Gui.plateButton(buttons, { Size = UDim2.fromOffset(330, 68), LayoutOrder = 2, ZIndex = Z + 2 }, Color3.fromRGB(200, 22, 38), Color3.fromRGB(240, 50, 64))
	label(back, { Text = "RETURN TO GAME", display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z + 4 })
	kit.onClick(back, function()
		LoungeMenu.close()
	end)

	ui.foot = label(main, { Text = "", TextSize = 19, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, TextWrapped = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 812), Size = UDim2.fromOffset(820, 48), TextXAlignment = Enum.TextXAlignment.Center })

	ui.root = root
	if mods.PadNav then
		mods.PadNav.root(root, { prio = 30, back = function()
			LoungeMenu.close()
		end })
	end
end

-- the screen a refresh's teleport shows while it travels
local function teleportScreen(line)
	local g = Instance.new("ScreenGui")
	g.Name = "LoungeTeleport"
	g.IgnoreGuiInset = true
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(4, 3, 5)
	f.BorderSizePixel = 0
	f.Parent = g
	Gui.label(f, { Text = "AFK LOUNGE", display = true, weight = Enum.FontWeight.Heavy, TextSize = 56, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -24), Size = UDim2.fromOffset(700, 64), TextXAlignment = Enum.TextXAlignment.Center })
	Gui.label(f, { Text = line or "Refreshing your connection. Your rewards keep coming.", TextSize = 20, weight = Enum.FontWeight.Medium, TextColor3 = Gui.MUTED, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 30), Size = UDim2.fromOffset(700, 26), TextXAlignment = Enum.TextXAlignment.Center })
	return g
end

local function nextIn()
	if not state or state.nextIn == nil then
		return nil
	end
	if state.moving then
		return state.nextIn -- (on the way to a lounge server the clock waits)
	end
	return math.max(0, state.nextIn - (os.clock() - stateAt))
end

local function tickTimer()
	if not (ui.root and ui.root.Visible) then
		return
	end
	local left = nextIn()
	if left == nil then
		ui.head.Text = "TODAY'S REWARDS"
		ui.timer.Text = "DONE"
		ui.fill.Size = UDim2.fromScale(1, 1)
	else
		ui.head.Text = "NEXT REWARD IN"
		ui.timer.Text = clock(left)
		ui.fill.Size = UDim2.fromScale(math.clamp(1 - left / L.Interval, 0.01, 1), 1)
	end
end

function LoungeMenu.refresh()
	if not ui.root then
		return
	end
	local s = state or { mult = 1, paidToday = 0, daily = L.DailyPayouts }
	local prof = kit.profile()
	local made = s.made or Lounge.newMade()
	local log = s.log or {}
	local function pct(i)
		return tostring(math.floor(Lounge.chance(i) * 1000 + 0.5) / 10) .. "%"
	end
	ui.reward.Text = string.format("A RANDOM REWARD  •  EVERY %d MIN", math.floor(L.Interval / 60))
	local function chip(c, text, on, color)
		c[2].Text = text
		c[2].TextColor3 = on and color or Gui.DIM
		c[3].Color = on and color or Color3.fromRGB(70, 70, 82)
		c[1].BackgroundColor3 = on and Color3.fromRGB(16, 30, 44) or Color3.fromRGB(26, 26, 32)
	end
	chip(ui.chipBase, #L.Rewards .. " REWARDS", false, Gui.CHALK)
	ui.chipBase[2].TextColor3 = Gui.MUTED
	chip(ui.chipVip, (s.vip and "" or "🔒 ") .. "VIP x" .. L.VipMult, s.vip, Gui.GOLD)
	chip(ui.chipPremium, "PREMIUM x" .. L.PremiumMult, s.premium, BLUE)
	local last = log[1]
	if last and L.Rewards[last.i] then
		ui.earned.Text = Lounge.label(Lounge.grant(last.i, last.m))
		ui.earned.TextColor3 = TIER[L.Rewards[last.i].Tier] or Gui.CHALK
		ui.earnedSub.Text = "a " .. pct(last.i) .. " roll"
	else
		ui.earned.Text = "-"
		ui.earned.TextColor3 = Gui.DIM
		ui.earnedSub.Text = "none yet"
	end
	local daily = s.daily or L.DailyPayouts
	if daily then
		ui.today.Text = string.format('%d <font size="24" color="#B0B6C8">/ %d</font>', s.paidToday or 0, daily)
		ui.todaySub.Text = "rewards today"
		ui.todayFill.Size = UDim2.fromScale(math.clamp((s.paidToday or 0) / math.max(daily, 1), 0, 1), 1)
	else
		-- no daily limit: just the count
		ui.today.Text = tostring(s.paidToday or 0)
		ui.todaySub.Text = "rewards today  •  no limit"
		ui.todayFill.Size = UDim2.fromScale(1, 1)
	end
	ui.balance.Text = Economy.commas(prof.gold or 0)
	ui.balSub.Text = string.format('gold  •  <font color="#5AC8FF">%s VP</font>', Economy.commas(prof.vp or 0))
	local top = #L.Rewards
	ui.luck.Text = string.format('Top reward: <font color="#FFC83C">%s</font> (%s)  •  every roll at least %s or %s', Lounge.label(Lounge.grant(top, 1)), pct(top), Lounge.label(Lounge.grant(1, s.mult or 1)), Lounge.label(Lounge.grant(2, s.mult or 1)))
	-- the odds, at your multiplier
	for i, l in pairs(ui.oddsRows) do
		l.Text = Lounge.label(Lounge.grant(i, s.mult or 1))
	end
	-- the side panel
	ui.sideCount.Text = (made.n or 0) == 1 and "1 reward rolled" or ((made.n or 0) .. " rewards rolled")
	for _, k in ipairs(Lounge.Kinds) do
		local r = ui.rows[k]
		local n = made[k] or 0
		if k == "BoostVP" or k == "BoostLuck" then
			r.value.Text = n > 0 and (math.floor(n / 60 + 0.5) .. " MIN") or "0"
		else
			r.value.Text = Economy.commas(n)
		end
		r.value.TextColor3 = n > 0 and r.color or Gui.DIM
	end
	for k, l in ipairs(ui.logRows) do
		local e = log[k]
		if e and L.Rewards[e.i] then
			local c = TIER[L.Rewards[e.i].Tier] or Gui.CHALK
			l.Text = string.format('<font color="#%s">%s</font>', c:ToHex(), Lounge.label(Lounge.grant(e.i, e.m)))
			l.TextTransparency = (k - 1) * 0.07
		else
			l.Text = ""
		end
	end
	ui.logEmpty.Visible = #log == 0
	ui.vip.Visible = not s.vip
	ui.vipL.Text = string.format("GET VIP  •  %dx GOLD & VP", L.VipMult)
	if s.moving == "game" then
		ui.foot.Text = "Taking you back to the game..."
	elseif s.moving == "lounge" then
		ui.foot.Text = s.own and "Refreshing your connection..." or "Taking you to your own lounge server..."
	else
		ui.foot.Text = (s.own and "Your own server. " or "") .. "Stay as long as you want: the lounge refreshes your connection automatically, past Roblox's 20 minute AFK limit."
	end
	tickTimer()
end

function LoungeMenu.open()
	if not ui.root then
		return
	end
	ui.root.Visible = true
	LoungeMenu.refresh()
	Net.get("Lounge"):FireServer("enter")
end

function LoungeMenu.close()
	if ui.root and not (state and state.own) then
		ui.root.Visible = false -- (in your own server it stays up until the teleport back)
	end
	Net.get("Lounge"):FireServer("leave")
end

function LoungeMenu.isOpen()
	return ui.root ~= nil and ui.root.Visible
end

local function onState(s)
	if type(s) ~= "table" then
		return
	end
	if s.refused then
		if ui.root then
			ui.root.Visible = false
		end
		kit.toast(s.refused)
		return
	end
	state = s
	stateAt = os.clock()
	if s.moving and ui.teleportSet ~= s.moving then
		-- (only for the lounge's own teleports: a ranked match's keeps Roblox's own screen)
		ui.teleportSet = s.moving
		pcall(function()
			TeleportService:SetTeleportGui(teleportScreen(s.moving == "game" and "Back to the game..." or (s.own and "Refreshing your connection. Your rewards keep coming." or "To your own lounge server...")))
		end)
	end
	if ui.root then
		-- (put back in after a refresh, or let out: a party pulled you into a lobby)
		if s.inside and not ui.root.Visible then
			ui.root.Visible = true
		elseif s.inside == false and ui.root.Visible then
			ui.root.Visible = false
		end
	end
	if s.paid and ui.rewardScale then
		ui.rewardScale.Scale = 1.15
		task.delay(0.18, function()
			ui.rewardScale.Scale = 1
		end)
		if mods.AudioController then
			mods.AudioController.play("UIConfirm")
		end
	end
	LoungeMenu.refresh()
end

function LoungeMenu.init(m)
	mods = m
	kit = mods.MenuController.kit()
	build()
	Net.get("Lounge").OnClientEvent:Connect(onState)
	mods.State.signals.Profile:Connect(function()
		if LoungeMenu.isOpen() then
			LoungeMenu.refresh()
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc >= 0.25 then
			acc = 0
			tickTimer()
		end
	end)
	Net.get("Lounge"):FireServer("get")
end

return LoungeMenu
