-- The AFK Lounge's screen (Config.Lounge, LoungeService; the owner: "add an afk chamber", after
-- another game's AFK Lounge): opened from AFK at the top right of the main screens, it covers the
-- menus in a dark room with an ember glow:
--   * the title and "rewards keep coming while you rest";
--   * the big card: the countdown to the next payout, its bar, what each payout pays and how often,
--     and the chips that make it (the base, VIP's x2, Premium's x1.5, lit when yours);
--   * three cards: earned this visit, today against the daily cap, and your balance;
--   * the payout's lucky find, Get VIP (when you haven't got it) and Return to game;
--   * a line on the refresh that keeps you past Roblox's idle limit.
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

	-- the title
	label(root, { Text = "AFK LOUNGE", display = true, weight = Enum.FontWeight.Heavy, TextSize = 64, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(700, 70), TextXAlignment = Enum.TextXAlignment.Center })
	local underline = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 106), Size = UDim2.fromOffset(64, 5), BackgroundColor3 = EMBER, BorderSizePixel = 0, ZIndex = Z + 2 }, root)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, underline)
	pill(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 122), Size = UDim2.fromOffset(470, 38) }, '<font color="#E8283A">Zz</font>  REWARDS KEEP COMING WHILE YOU REST', 19)

	-- the big card: the countdown
	local big = card(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 172), Size = UDim2.fromOffset(860, 360), ClipsDescendants = true }, Color3.fromRGB(90, 60, 66))
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
	rewardL.Position = UDim2.fromOffset(18, 0)
	Gui.icon.gold(rewardPill, 26).Position = UDim2.new(0, 22, 0.5, -13)
	ui.reward, ui.rewardPill = rewardL, rewardPill
	ui.rewardScale = make("UIScale", { Scale = 1 }, rewardPill)
	local chips = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 304), Size = UDim2.fromOffset(640, 36), BackgroundTransparency = 1, ZIndex = Z + 2 }, big)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	ui.chipBase = { pill(chips, { Size = UDim2.fromOffset(140, 36), LayoutOrder = 1 }, "", 19) }
	ui.chipVip = { pill(chips, { Size = UDim2.fromOffset(140, 36), LayoutOrder = 2 }, "", 19) }
	ui.chipPremium = { pill(chips, { Size = UDim2.fromOffset(190, 36), LayoutOrder = 3 }, "", 19) }

	-- the three cards
	local function stat(i, title)
		local c = card(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, (i - 2) * 292, 0, 548), Size = UDim2.fromOffset(276, 118) })
		label(c, { Text = title, display = true, weight = Enum.FontWeight.Heavy, TextSize = 19, TextColor3 = Gui.MUTED, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
		local value = label(c, { Text = "0", display = true, weight = Enum.FontWeight.Heavy, TextSize = 38, RichText = true, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
		local sub = label(c, { Text = "", TextSize = 19, weight = Enum.FontWeight.Medium, TextColor3 = Gui.MUTED, RichText = true, Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
		return c, value, sub
	end
	local earnedCard, earned, earnedSub = stat(1, "EARNED HERE")
	Gui.icon.gold(earnedCard, 28).Position = UDim2.new(0, 24, 0, 44)
	local todayCard, today, todaySub = stat(2, "TODAY")
	ui.todayFill = bar(todayCard, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 102), Size = UDim2.new(1, -60, 0, 6) })
	local balCard, balance, balSub = stat(3, "BALANCE")
	Gui.icon.gold(balCard, 28).Position = UDim2.new(0, 24, 0, 44)
	ui.earned, ui.earnedSub, ui.today, ui.todaySub, ui.balance, ui.balSub = earned, earnedSub, today, todaySub, balance, balSub

	ui.luck = label(root, { Text = "", TextSize = 22, weight = Enum.FontWeight.Medium, TextColor3 = Gui.MUTED, RichText = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 682), Size = UDim2.fromOffset(860, 24), TextXAlignment = Enum.TextXAlignment.Center })

	-- Get VIP and Return to game
	local buttons = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 722), Size = UDim2.fromOffset(700, 70), BackgroundTransparency = 1, ZIndex = Z + 2 }, root)
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

	ui.foot = label(root, { Text = "", TextSize = 19, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, TextWrapped = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 812), Size = UDim2.fromOffset(820, 48), TextXAlignment = Enum.TextXAlignment.Center })

	ui.root = root
	if mods.PadNav then
		mods.PadNav.root(root, { prio = 30, back = function()
			LoungeMenu.close()
		end })
	end
end

-- the screen a refresh's teleport shows while it travels
local function teleportScreen()
	local g = Instance.new("ScreenGui")
	g.Name = "LoungeTeleport"
	g.IgnoreGuiInset = true
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(4, 3, 5)
	f.BorderSizePixel = 0
	f.Parent = g
	Gui.label(f, { Text = "AFK LOUNGE", display = true, weight = Enum.FontWeight.Heavy, TextSize = 56, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -24), Size = UDim2.fromOffset(700, 64), TextXAlignment = Enum.TextXAlignment.Center })
	Gui.label(f, { Text = "Refreshing your connection. Your rewards keep coming.", TextSize = 20, weight = Enum.FontWeight.Medium, TextColor3 = Gui.MUTED, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 30), Size = UDim2.fromOffset(700, 26), TextXAlignment = Enum.TextXAlignment.Center })
	return g
end

local function nextIn()
	if not state or state.nextIn == nil then
		return nil
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
	local s = state or { rate = L.BaseGold, base = L.BaseGold, cap = L.BaseGold * L.DailyPayouts, today = 0, earned = 0, earnedVP = 0 }
	local prof = kit.profile()
	ui.reward.Text = string.format("+%s GOLD  •  EVERY %d MIN", Economy.commas(s.rate or 0), math.floor(L.Interval / 60))
	local function chip(c, text, on, color)
		c[2].Text = text
		c[2].TextColor3 = on and color or Gui.DIM
		c[3].Color = on and color or Color3.fromRGB(70, 70, 82)
		c[1].BackgroundColor3 = on and Color3.fromRGB(16, 30, 44) or Color3.fromRGB(26, 26, 32)
	end
	chip(ui.chipBase, "BASE " .. Economy.commas(s.base or L.BaseGold), false, Gui.CHALK)
	ui.chipBase[2].TextColor3 = Gui.MUTED
	chip(ui.chipVip, (s.vip and "" or "🔒 ") .. "VIP x" .. L.VipMult, s.vip, Gui.GOLD)
	chip(ui.chipPremium, "PREMIUM x" .. L.PremiumMult, s.premium, BLUE)
	ui.earned.Text = Economy.commas(s.earned or 0)
	ui.earnedSub.Text = (s.earnedVP or 0) > 0 and string.format('gold  •  <font color="#5AC8FF">%s VP</font>', Economy.commas(s.earnedVP)) or "gold"
	ui.today.Text = string.format('%s <font size="24" color="#B0B6C8">/ %s</font>', Economy.commas(s.today or 0), Economy.commas(s.cap or 0))
	ui.todaySub.Text = "gold today"
	ui.todayFill.Size = UDim2.fromScale(math.clamp((s.today or 0) / math.max(s.cap or 1, 1), 0, 1), 1)
	ui.balance.Text = Economy.commas(prof.gold or 0)
	ui.balSub.Text = string.format('gold  •  <font color="#5AC8FF">%s VP</font>', Economy.commas(prof.vp or 0))
	ui.luck.Text = string.format('Every payout: <font color="#5AC8FF">%s%% chance</font> to find <font color="#5AC8FF">+%d V POINTS</font>', tostring(L.GemChance * 100), L.GemVP)
	ui.vip.Visible = not s.vip
	ui.vipL.Text = string.format("GET VIP  •  %dx GOLD", L.VipMult)
	ui.foot.Text = s.refreshing and "Refreshing your connection..." or "Stay as long as you want: the lounge refreshes your connection automatically, past Roblox's 20 minute AFK limit."
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
	if ui.root then
		ui.root.Visible = false
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
	if s.refreshing and not ui.teleportSet then
		-- (only for the refresh: a ranked match's teleport keeps Roblox's own screen)
		ui.teleportSet = true
		pcall(function()
			TeleportService:SetTeleportGui(teleportScreen())
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
