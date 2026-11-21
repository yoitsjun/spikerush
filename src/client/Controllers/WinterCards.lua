-- A Winter Match's Christmas cards on screen (Config.Winter.Cards; MatchService.dealWinterCard):
-- before every rally the drawn card flips in big in the middle (its name, what it does, its band
-- colour), holds for Config.Winter.CardShow, then shrinks away into a chip under the score that
-- stays for the rally. A Candy Cane point pops a "+2" off the chip. The server's WinterCard
-- attribute ("key:n") says which card; n changes with every draw, so each one shows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Winter = require(Shared.Winter)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local WinterCards = {}
local make = Gui.make
local W = Config.Winter

-- the Winter window's colours (WinterMenu)
local FROST = Color3.fromRGB(238, 247, 255)
local INK = Color3.fromRGB(8, 24, 62)
local DEEP = Color3.fromRGB(10, 26, 70)
local ICE = W.Snow.Color

local CHIP_Y = 206 -- px from the top: the chip sits under the score and the speed readout

local mods = nil
local ui = {}
local shownN = nil -- the draw on screen ("key:n"'s n)

local function sound(key, opts)
	if mods and mods.AudioController then
		pcall(mods.AudioController.play, key, opts)
	end
end

local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- A snowflake drawn from bars (six arms, each with a pair of twigs).
local function flake(parent, size, color, props)
	local f = make("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	local thick = math.max(2, math.floor(size * 0.07))
	for i = 0, 2 do
		local arm = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, thick), Rotation = i * 60, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = f.ZIndex }, f)
		Gui.round(arm)
		for _, side in ipairs({ 0.2, 0.8 }) do
			for _, tilt in ipairs({ 45, -45 }) do
				local tw = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(side, 0, 0.5, 0), Size = UDim2.fromOffset(math.floor(size * 0.2), thick), Rotation = tilt, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = f.ZIndex }, arm)
				Gui.round(tw)
			end
		end
	end
	return f
end

local function build()
	local player = Players.LocalPlayer
	ui.gui = make("ScreenGui", { Name = "SpikeRushWinterCard", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 38, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = true }, player:WaitForChild("PlayerGui"))

	-- the big card
	local card = make("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(270, 360), BackgroundColor3 = FROST, BorderSizePixel = 0, Visible = false, ZIndex = 10 }, ui.gui)
	Gui.corner(card, 16)
	ui.scale = make("UIScale", { Scale = 1 }, card)
	ui.stroke = make("UIStroke", { Color = ICE, Thickness = 6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	ui.band = make("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = ICE, BorderSizePixel = 0, ZIndex = 11 }, card)
	Gui.corner(ui.band, 16)
	-- (the band's square lower corners)
	ui.bandFoot = make("Frame", { Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = ICE, BorderSizePixel = 0, ZIndex = 11 }, ui.band)
	Gui.label(ui.band, { Text = "CHRISTMAS CARD", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = FROST, TextStrokeColor3 = DEEP, TextStrokeTransparency = 0.4, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
	ui.flake = flake(card, 96, ICE, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), ZIndex = 11 })
	ui.name = Gui.label(card, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 36, TextColor3 = INK, TextWrapped = true, Position = UDim2.fromOffset(12, 190), Size = UDim2.new(1, -24, 0, 44), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
	ui.text = Gui.label(card, { Text = "", TextSize = 21, TextColor3 = INK, TextWrapped = true, Position = UDim2.fromOffset(16, 240), Size = UDim2.new(1, -32, 0, 100), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 12 })
	ui.worth = Gui.label(card, { Text = "x2", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextColor3 = FROST, BackgroundColor3 = Color3.fromRGB(236, 40, 56), BackgroundTransparency = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(58, 58), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 14 })
	Gui.round(ui.worth)
	make("UIStroke", { Color = FROST, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ui.worth)
	ui.card = card

	-- the chip under the score
	local chip = make("Frame", { Name = "Chip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, CHIP_Y), Size = UDim2.fromOffset(500, 38), BackgroundColor3 = DEEP, BackgroundTransparency = 0.15, BorderSizePixel = 0, Visible = false, ZIndex = 10 }, ui.gui)
	Gui.corner(chip, 10)
	ui.chipStroke = make("UIStroke", { Color = ICE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
	ui.chipFlake = flake(chip, 24, ICE, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), ZIndex = 11 })
	ui.chipText = Gui.label(chip, { Text = "", TextSize = 16, TextColor3 = FROST, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -52, 1, 0), ZIndex = 11 })
	ui.chipScale = make("UIScale", { Scale = 1 }, chip)
	ui.chip = chip
end

local function paint(c)
	local color = c.Color or ICE
	ui.stroke.Color = color
	ui.band.BackgroundColor3 = color
	ui.bandFoot.BackgroundColor3 = color
	for _, f in ipairs({ ui.flake, ui.chipFlake }) do
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("Frame") then
				d.BackgroundColor3 = color
			end
		end
	end
	ui.chipStroke.Color = color
	ui.name.Text = c.Name
	ui.text.Text = c.Text
	local worth = Winter.cardPoints(c)
	ui.worth.Visible = worth > 1
	ui.worth.Text = "x" .. worth
	ui.chipText.Text = string.format("<b>%s</b>  %s", c.Name, c.Text)
end

-- Flip `c` in, hold it, then shrink it into the chip.
local function show(c, n)
	shownN = n
	paint(c)
	ui.chip.Visible = false
	local card = ui.card
	card.Visible = true
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Rotation = -14
	ui.scale.Scale = 0.1
	tween(ui.scale, 0.42, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(card, 0.42, { Rotation = 0 }, Enum.EasingStyle.Back)
	-- the card turning over under a jingle of bells; Gift Exchange chimes, Jackpot! laughs
	sound("WinterCardFlip")
	sound("WinterBells", { volume = 0.7 })
	if c.Gift then
		task.delay(0.25, sound, "WinterGift")
	end
	if c.Key == "Jackpot" then
		task.delay(0.35, sound, "WinterHoHo")
	end
	task.delay(W.CardShow, function()
		if shownN ~= n then
			return
		end
		tween(card, 0.3, { Position = UDim2.new(0.5, 0, 0, CHIP_Y + 19) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(ui.scale, 0.3, { Scale = 0.12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.3, function()
			if shownN ~= n then
				return
			end
			card.Visible = false
			ui.chip.Visible = true
			ui.chipScale.Scale = 0.8
			tween(ui.chipScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end)
end

local function hideAll()
	shownN = nil
	ui.card.Visible = false
	ui.chip.Visible = false
end

local function onCard()
	local raw = ReplicatedStorage:GetAttribute("WinterCard")
	local key, n = nil, nil
	if type(raw) == "string" then
		key, n = string.match(raw, "^(%w+):(%d+)$")
	end
	local c = Winter.card(key)
	if not c or not State.watching() then
		hideAll()
		return
	end
	if n ~= shownN then
		show(c, n)
	end
end

-- A point worth more than one (a Candy Cane): "+2" pops off the chip.
local function onPoint(a)
	if a.kind == "Point" and a.matchWon and shownN and a.winner == State.myTeam then
		-- a Winter Match won: Jingle Bells (its first bars)
		sound("WinterWin", { seconds = 4 })
	end
	if not (a.kind == "Point" and a.worth and ui.chip.Visible) then
		return
	end
	sound("WinterJingle")
	local pop = Gui.label(ui.gui, { Text = "+" .. tostring(a.worth), display = true, weight = Enum.FontWeight.Heavy, TextSize = 44, TextColor3 = FROST, TextStrokeColor3 = Color3.fromRGB(236, 40, 56), TextStrokeTransparency = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, CHIP_Y + 40), Size = UDim2.fromOffset(120, 50), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 15 })
	tween(pop, 0.9, { Position = UDim2.new(0.5, 0, 0, CHIP_Y + 90), TextTransparency = 1, TextStrokeTransparency = 1 })
	ui.chipScale.Scale = 1.15
	tween(ui.chipScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1, function()
		pop:Destroy()
	end)
end

function WinterCards.init(m)
	mods = m
	build()
	ReplicatedStorage:GetAttributeChangedSignal("WinterCard"):Connect(onCard)
	State.signals.Announce:Connect(onPoint)
	onCard()
end

return WinterCards
