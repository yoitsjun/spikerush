-- The Colosseum's screens (2026-11-14: the Halloween event's, repurposed; Config.Halloween, the
-- shared Halloween module), drawn with the
-- menus' kit (MenuController.kit) on the menus' canvas:
--   * a Halloween button down Home's right edge, with the time left
--   * the event window: Match (Easy / Normal / Hard: what each pays, today's first clears),
--     Banner (what's on it, the odds, scout points, recruits for VP or Candy), Shop (Candy
--     prices) and Reaper (your copies, and the characters they're on, switched on or off)
--   * the card picks before each stage (LobbyService's mine.event.draft): a strip of cards scrolls
--     past, slows and lands the 3 offers in their slots (the owner: "a scrolling cards motion for
--     rolls"); you pick 1; your hand, your teammates' and the AI's underneath, and the time left.
--     Each card wears an icon (the owner: "the cards are bland, so put the character icons on"):
--     an ability card its character's badge icon and name, the others their stat's, the team's, a
--     skull for a curse
--   * a Halloween recruit: the recruit sequence in orange (MenuController's, through the kit)
--   * in a Halloween Match, your cards and the AI's at the side of the screen
-- The looks are first passes: the PC Claude lays them out in Studio (HANDOFF.md).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Halloween = require(Shared.Halloween)
local Spins = require(Shared.Spins)
local Roster = require(Shared.Roster)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local HalloweenMenu = {}
local HW = Config.Halloween
local player = Players.LocalPlayer
local mods, kit
local ui = {}
local tab = "Match"
local ORANGE = HW.Candy.Color
local PURPLE = Color3.fromRGB(120, 60, 200)
local refreshMap, mapHint -- (the chain map, further down)

local function make(...)
	return kit.make(...)
end

local function prof()
	return kit.profile()
end

local function eventOf(p)
	return (p and p.halloween) or { candy = 0, scout = 0, cleared = {}, bought = {} }
end

local function mine()
	local l = kit.lobbies()
	return l and l.mine
end

-- "18d 6h", "5h 12m", "3m"
local function leftText(seconds)
	seconds = math.max(0, math.floor(seconds))
	local d = math.floor(seconds / 86400)
	local h = math.floor(seconds % 86400 / 3600)
	local m = math.floor(seconds % 3600 / 60)
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", math.max(1, m))
end

local function kindColor(card)
	local k = card and HW.Kinds[card.Kind]
	return k and k.Color or Gui.CHALK
end

local function itemKindName(kind)
	if kind == "Skin" then
		return "Skin"
	elseif kind == "Room" then
		return "Home room"
	elseif kind == "Card" then
		return "Player card"
	end
	local b = Config.Spins.Banners[kind]
	return b and b.Name or kind
end

local function hideClose(m)
	for _, d in ipairs(m.panel:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text == "Close" and d.Parent and d.Parent:IsA("GuiButton") then
			d.Parent.Visible = false
		end
	end
end

------------------------------------------------------------------------------------------
-- a card's face
------------------------------------------------------------------------------------------

-- The character an ability card comes from (the roster's best with that ability), or nil.
local abilityChar = {}
for _, c in ipairs(Roster) do
	if c.Ability and (not abilityChar[c.Ability] or (c.Tier == "S+" and abilityChar[c.Ability].Tier ~= "S+")) then
		abilityChar[c.Ability] = c
	end
end

local STATS = Config.Stats.Order
-- A card's icon (an Assets image key, or an Fx sprite id) and who it hits, for its face.
local function cardArt(card)
	if card.Kind == "Ability" then
		local c = abilityChar[card.Ability]
		local def = Config.Abilities[card.Ability]
		return { image = Assets.image("Ability" .. card.Ability) or Assets.image("IconStar"), ring = def and def.Color or kindColor(card), who = c and string.format("%s  ·  %s", c.Name, c.Tier) or "", whoColor = c and Gui.CHALK or Gui.DIM, tier = c and c.Tier }
	end
	local who = card.Target == "Team" and "Your whole team" or (card.Target == "Foes" and "The other team" or "You")
	local key = "IconStar"
	if card.Kind == "Curse" then
		return { image = Assets.id(Assets.Fx.Skull), ring = kindColor(card), who = who, whoColor = Gui.DIM }
	elseif card.Kind == "Team" then
		key = "IconPlayers"
	elseif card.SpikeReach then
		key = "AbilityFeral" -- (claws)
	elseif card.Block or card.Stuff or card.DrainTake then
		key = "IconDefense"
	elseif card.DrainDeal then
		key = "AbilityChainReaction"
	elseif card.PerPoint then
		key = "AbilityRisingSun"
	elseif card.SpikeMul or card.ServeMul then
		key = "IconAttack"
	elseif card.Height then
		key = "IconJump"
	end
	if card.Add and card.Kind ~= "Team" then
		local best, bv = nil, 0
		for _, k in ipairs(STATS) do
			local v = math.abs(card.Add[k] or 0)
			if v > bv then
				best, bv = k, v
			end
		end
		if best then
			key = "Icon" .. best
		end
	end
	return { image = Assets.image(key) or "", ring = kindColor(card), who = who, whoColor = Gui.DIM }
end

-- A faint Halloween picture behind each kind's art.
local WATERMARK = { Ability = "SoulWisp", Stat = "Bat", Team = "GhostSheet", Curse = "InkSplat", Rule = "Skull" }

-- A trading card (300 x 380 at full size; everything scales with it): the kind's band and the
-- rarity, the icon in a ring over a glow in the kind's colour with a Halloween watermark, who it's
-- from or hits, the name and what it does.
local CARD_W, CARD_H = 300, 380
local function cardFace(parent, props)
	local b = make("TextButton", { Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = Color3.fromRGB(14, 12, 24), BorderSizePixel = 0, Text = "", AutoButtonColor = false, ClipsDescendants = true, ZIndex = 22 }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Gui.corner(b, 12)
	local stroke = make("UIStroke", { Thickness = 3, Transparency = 0.05, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local shade = make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 170)) }, b)
	local glow = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.33), Size = UDim2.fromScale(1.15, 0.9), BackgroundTransparency = 1, Image = Assets.id(Assets.Fx.Glow) or "", ImageTransparency = 0.5, ZIndex = 22 }, b)
	local mark = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.8, 0.72), Size = UDim2.fromScale(0.75, 0.59), Rotation = -14, BackgroundTransparency = 1, ImageTransparency = 0.9, ZIndex = 22 }, b)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, mark)
	local band = make("Frame", { Size = UDim2.new(1, 0, 0.1, 0), BorderSizePixel = 0, ZIndex = 23 }, b)
	make("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(160, 160, 160)), Rotation = 0 }, band)
	local kind = Gui.label(band, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextColor3 = Gui.LINE, Position = UDim2.fromScale(0.05, 0.16), Size = UDim2.fromScale(0.5, 0.68), ZIndex = 24 })
	local rarity = Gui.label(band, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextColor3 = Gui.LINE, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.45, 0.2), Size = UDim2.fromScale(0.5, 0.6), ZIndex = 24 })
	local ring = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromScale(0.39, 0.31), BackgroundColor3 = Color3.fromRGB(10, 8, 18), BorderSizePixel = 0, ZIndex = 24 }, b)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, ring)
	Gui.round(ring)
	local ringStroke = make("UIStroke", { Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
	local icon = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.64, 0.64), BackgroundTransparency = 1, ZIndex = 25 }, ring)
	local who = Gui.label(b, { Text = "", display = true, TextScaled = true, Position = UDim2.fromScale(0.06, 0.505), Size = UDim2.fromScale(0.88, 0.06), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	local name = Gui.label(b, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextWrapped = true, Position = UDim2.fromScale(0.06, 0.575), Size = UDim2.fromScale(0.88, 0.13), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	make("UITextSizeConstraint", { MaxTextSize = 30 }, name)
	local blurb = Gui.label(b, { Text = "", TextScaled = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromScale(0.07, 0.72), Size = UDim2.fromScale(0.86, 0.25), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	make("UITextSizeConstraint", { MaxTextSize = 17 }, blurb)
	local scale = make("UIScale", { Scale = 1 }, b)
	return { button = b, stroke = stroke, shade = shade, glow = glow, mark = mark, band = band, kind = kind, rarity = rarity, ring = ring, ringStroke = ringStroke, icon = icon, who = who, name = name, blurb = blurb, scale = scale }
end

-- Whether an ability is already yours: your character's own, or an ability card's in your hand
-- (a card for it adds only its stats then: the ability isn't played twice).
local function holdsAbility(name)
	if name == State.myAbility() then
		return true
	end
	local mn = mine()
	for _, a in ipairs(Halloween.abilitiesOf(mn and mn.event and mn.event.hand)) do
		if a == name then
			return true
		end
	end
	return false
end

local function setFace(face, key, dim)
	local card = Halloween.card(key)
	if not card then
		face.name.Text = "?"
		face.kind.Text = ""
		face.rarity.Text = ""
		face.blurb.Text = ""
		face.who.Text = ""
		face.icon.Image = ""
		return
	end
	local color = kindColor(card)
	local rc = Spins.rarityColor(card.Rarity)
	local art = cardArt(card)
	face.band.BackgroundColor3 = color
	face.stroke.Color = rc
	face.stroke.Thickness = Spins.rarityRank(card.Rarity) >= 4 and 4 or 3
	face.kind.Text = string.upper(HW.Kinds[card.Kind].Name)
	face.rarity.Text = string.upper(card.Rarity)
	face.glow.ImageColor3 = color
	face.mark.Image = Assets.id(Assets.Fx[WATERMARK[card.Kind] or "Bat"]) or ""
	face.mark.ImageColor3 = color
	face.ringStroke.Color = art.ring
	face.icon.Image = art.image or ""
	face.icon.ImageColor3 = card.Kind == "Curse" and Color3.fromRGB(220, 190, 255) or Color3.new(1, 1, 1)
	face.who.Text = art.who
	face.who.TextColor3 = art.tier and Config.TierColors[art.tier] or art.whoColor
	face.name.Text = card.Name
	face.name.TextColor3 = card.Kind == "Ability" and art.ring:Lerp(Color3.new(1, 1, 1), 0.35) or Gui.CHALK
	face.blurb.Text = Halloween.blurb(card)
	local passives = Halloween.passiveLine(card)
	if passives then
		face.blurb.Text = face.blurb.Text .. "\n" .. passives
	end
	if card.Kind == "Ability" and holdsAbility(card.Ability) then
		face.blurb.Text = face.blurb.Text .. "\nYou have it already: its stats only"
	end
	face.button.BackgroundTransparency = dim and 0.5 or 0
end

-- A row of small chips, one per card (a hand).
local function chipRow(parent, y, caption)
	local row = make("Frame", { Position = UDim2.fromOffset(28, y), Size = UDim2.new(1, -56, 0, 30), BackgroundTransparency = 1, ZIndex = 22 }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	Gui.label(row, { Text = caption, display = true, TextSize = 18, TextColor3 = Gui.DIM, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), LayoutOrder = 0, ZIndex = 22 })
	return { frame = row, chips = {} }
end

local function setChips(row, keys)
	for _, c in ipairs(row.chips) do
		c:Destroy()
	end
	row.chips = {}
	for i, key in ipairs(keys or {}) do
		local card = Halloween.card(key)
		if card then
			local chip = Gui.plate(row.frame, { Size = UDim2.fromOffset(math.max(70, #card.Name * 10 + 28), 28), LayoutOrder = i, ZIndex = 22 }, kindColor(card))
			Gui.label(chip, { Text = card.Name, display = true, TextSize = 16, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
			table.insert(row.chips, chip)
		end
	end
	if #(keys or {}) == 0 then
		table.insert(row.chips, Gui.label(row.frame, { Text = "none yet", TextSize = 16, TextColor3 = Gui.DIM, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), LayoutOrder = 1, ZIndex = 22 }))
	end
end

------------------------------------------------------------------------------------------
-- the event window
------------------------------------------------------------------------------------------

local function buildMatchTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 21 }, body)
	Gui.label(f, { Text = string.format("%d stages of %d points against the AI, %d Life for the whole run: every point they score costs one. Pick %d cards to start and more after every win; before each stage pick a path (a Match, a tougher Elite, or a Rest); the All-Star waits at the end. Each stage and card grows the Final Reward: the first %d runs a day pay all of it.", HW.Stages, HW.Points, HW.Life, HW.StartPicks, HW.RewardedRuns), TextSize = 16, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 44), ZIndex = 22 })
	local cards = {}
	local W, GAP = 352, 22
	for i, d in ipairs(HW.Difficulties) do
		local card = make("Frame", { Position = UDim2.fromOffset((i - 1) * (W + GAP), 56), Size = UDim2.fromOffset(W, 440), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, ZIndex = 22 }, f)
		Gui.corner(card, 10)
		make("UIStroke", { Color = d.Color, Thickness = 2, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		local head = make("Frame", { Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = d.Color, BorderSizePixel = 0, ZIndex = 23 }, card)
		Gui.corner(head, 10)
		Gui.label(head, { Text = string.upper(d.Name), display = true, weight = Enum.FontWeight.Heavy, TextSize = 34, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
		Gui.label(card, { Text = string.format("%s bots  ·  Elite %s  ·  All-Star %s", d.Bots, d.Elite, d.Boss), display = true, TextSize = 19, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 80), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(card, { Text = d.AiCards == 0 and "The AI takes cards only at Elites and the All-Star." or string.format("The AI takes %d card%s a stage, more at Elites.", d.AiCards, d.AiCards == 1 and "" or "s"), TextSize = 16, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 108), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(card, { Text = "A STAGE CLEARED", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 146), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(card, { Text = string.format("+%d %s", d.StageReward, HW.Candy.Name), display = true, weight = Enum.FontWeight.Heavy, TextSize = 40, TextColor3 = ORANGE, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 172), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(card, { Text = string.format("Elite +%d  ·  All-Star +%d\nplus every card you pick", Halloween.stageReward(d, "Elite"), Halloween.stageReward(d, "AllStar")), TextSize = 16, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 226), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		local done = Gui.label(card, { Text = "", display = true, TextSize = 18, TextColor3 = Gui.SIGNAL_HOT, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 290), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		local enter = kit.actionPlate(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, -36, 0, 64) }, "Play", 24)
		kit.onClick(enter, function()
			Net.get("Lobby"):FireServer("halloween", d.Key)
			ui.window.hide()
		end)
		cards[d.Key] = { done = done }
	end
	return { frame = f, cards = cards }
end

local function buildBannerTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	Gui.label(f, { Text = HW.Banner.Blurb, TextSize = 17, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(0, 700, 0, 44), ZIndex = 22 })
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 52), Size = UDim2.fromOffset(700, 444), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.DIM, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, f)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rows = {}
	for i, row in ipairs(Halloween.bannerTable()) do
		local it = row.item
		local r = make("Frame", { Size = UDim2.new(1, -10, 0, 50), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 22 }, list)
		Gui.corner(r, 6)
		make("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = Spins.rarityColor(it.rarity), BorderSizePixel = 0, ZIndex = 23 }, r)
		Gui.label(r, { Text = it.name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 21, Position = UDim2.fromOffset(18, 2), Size = UDim2.fromOffset(260, 26), ZIndex = 23 })
		Gui.label(r, { Text = itemKindName(it.kind) .. "  ·  " .. it.rarity, TextSize = 14, TextColor3 = Spins.rarityColor(it.rarity), Position = UDim2.fromOffset(18, 27), Size = UDim2.fromOffset(260, 18), ZIndex = 23 })
		Gui.label(r, { Text = string.format("%.2f%%", row.chance * 100), display = true, TextSize = 20, Position = UDim2.fromOffset(290, 0), Size = UDim2.fromOffset(90, 50), ZIndex = 23 })
		local have = Gui.label(r, { Text = "", TextSize = 15, TextColor3 = Gui.SIGNAL_HOT, Position = UDim2.fromOffset(384, 0), Size = UDim2.fromOffset(120, 50), ZIndex = 23 })
		local pick, pickL = kit.hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(170, 38), ZIndex = 23 }, string.format("Scout  ·  %d", it.scout), 17)
		kit.onClick(pick, function()
			Net.get("Profile"):FireServer("hwScout", it.kind, it.key)
		end)
		rows[i] = { item = it, have = have, pick = pick, pickL = pickL }
	end
	-- right: recruits and your scout points
	local side = make("Frame", { Position = UDim2.fromOffset(722, 52), Size = UDim2.fromOffset(392, 444), BackgroundTransparency = 1, ZIndex = 21 }, f)
	local scout = Gui.label(side, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, Size = UDim2.new(1, 0, 0, 34), ZIndex = 22 })
	Gui.label(side, { Text = "Scout points: one a recruit. Spend them on any item above.", TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 36), ZIndex = 22 })
	local buttons = {}
	local defs = { { "Candy", 1 }, { "Candy", 10 }, { "VP", 1 }, { "VP", 10 } }
	for i, def in ipairs(defs) do
		local cur, n = def[1], def[2]
		local x = ((i - 1) % 2) * 200
		local y = 96 + math.floor((i - 1) / 2) * 84
		local b, l = kit.actionPlate(side, { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(190, 72) }, "", 20)
		l.Text = string.format("Recruit x%d\n%s %s", n, Gui.num(Halloween.cost(cur, n)), cur)
		kit.onClick(b, function()
			Net.get("Profile"):FireServer("hwSpin", n, cur)
		end)
		buttons[i] = b
	end
	local last = Gui.label(side, { Text = "", RichText = true, TextSize = 15, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 160), Position = UDim2.fromOffset(0, 272), ZIndex = 22 })
	return { frame = f, rows = rows, scout = scout, last = last }
end

local function buildShopTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	Gui.label(f, { Text = HW.Candy.Name .. " from Colosseum runs buy these.", TextSize = 17, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 28), ZIndex = 22 })
	local rows = {}
	for i, row in ipairs(HW.Shop) do
		local r = make("Frame", { Position = UDim2.fromOffset(0, 40 + (i - 1) * 64), Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, ZIndex = 22 }, f)
		Gui.corner(r, 6)
		Gui.label(r, { Text = row.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(480, 56), ZIndex = 23 })
		local left = Gui.label(r, { Text = "", TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(520, 0), Size = UDim2.fromOffset(240, 56), ZIndex = 23 })
		local buy, buyL = kit.actionPlate(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(240, 44) }, string.format("Buy  ·  %d %s", row.Price, HW.Candy.Name), 19)
		kit.onClick(buy, function()
			Net.get("Profile"):FireServer("hwShop", row.Key)
		end)
		rows[i] = { row = row, left = left, buy = buy, buyL = buyL }
	end
	return { frame = f, rows = rows }
end

local function setTab(key)
	tab = key
	for k, t in pairs(ui.tabs) do
		t.frame.Visible = k == key
	end
	if ui.setSeg then
		ui.setSeg(key)
	end
	HalloweenMenu.refresh()
end

local function buildWindow()
	local m = kit.modal("Halloween", HW.Name, 1180, 680, true)
	ui.window = m
	ui.info = Gui.label(m.panel, { Text = "", display = true, TextSize = 21, TextColor3 = ORANGE, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 26), Size = UDim2.fromOffset(560, 26), ZIndex = 22 })
	-- (no Skins tab: the owner, 2026-10-16, "remove this"; a skin swaps on and off on its player's page)
	local items = { { key = "Match", text = "Colosseum" }, { key = "Shop", text = "Shop" } }
	if Halloween.active(Util.now()) then
		table.insert(items, 2, { key = "Banner", text = "Banner" })
	end
	local _, set = kit.segmented(m.panel, items, { Position = UDim2.fromOffset(28, 86), Size = UDim2.fromOffset(480, 46), ZIndex = 22 }, setTab)
	ui.setSeg = set
	local body = make("Frame", { Position = UDim2.fromOffset(28, 148), Size = UDim2.new(1, -56, 1, -170), BackgroundTransparency = 1, ZIndex = 21 }, m.panel)
	ui.tabs = { Match = buildMatchTab(body), Banner = buildBannerTab(body), Shop = buildShopTab(body) }
	set(tab)
end

-- The event window out of the way (a recruit's sequence takes the screen).
function HalloweenMenu.hideWindow()
	if ui.window then
		ui.window.root.Visible = false
	end
end

function HalloweenMenu.open(which)
	if which == "Banner" and not Halloween.active(Util.now()) then
		which = "Match" -- (the Halloween banner has closed; the Colosseum and its shop stay)
	end
	if which then
		setTab(which)
	end
	ui.window.root.Visible = true
	HalloweenMenu.refresh()
end

------------------------------------------------------------------------------------------
-- the picks
------------------------------------------------------------------------------------------

local spin = nil -- { id, t0, x0, x1, keys } while the strip scrolls
local STRIP_N = 22 -- cards in the strip; the offers are the last three but two
local STEP = CARD_W + 30
local WINDOW_W = 1044

local function buildPick()
	local m = kit.modal("HalloweenPick", "Pick a card", 1100, 700, true)
	hideClose(m)
	mods.PadNav.set(m.root, "prio", 30) -- (over the lobby's window)
	ui.pick = m
	ui.pickTimer = Gui.label(m.panel, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextColor3 = ORANGE, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, 22), Size = UDim2.fromOffset(300, 36), ZIndex = 22 })
	ui.pickLine = Gui.label(m.panel, { Text = "", TextSize = 18, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(28, 84), Size = UDim2.new(1, -56, 0, 24), ZIndex = 22 })
	-- the window the strip scrolls through, and the three slots the offers land in
	local win = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 116), Size = UDim2.fromOffset(WINDOW_W, CARD_H + 12), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 22 }, m.panel)
	local x0 = (WINDOW_W - (3 * CARD_W + 2 * 30)) / 2
	ui.slotX = x0
	-- the edges fade the strip in and out
	for _, right in ipairs({ false, true }) do
		local fade = make("Frame", { AnchorPoint = Vector2.new(right and 1 or 0, 0), Position = UDim2.fromScale(right and 1 or 0, 0), Size = UDim2.new(0, 90, 1, 0), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, ZIndex = 27 }, win)
		make("UIGradient", { Transparency = NumberSequence.new(right and 1 or 0, right and 0 or 1) }, fade)
	end
	local strip = make("Frame", { Size = UDim2.fromOffset(STRIP_N * STEP, CARD_H), Position = UDim2.fromOffset(0, 6), BackgroundTransparency = 1, ZIndex = 22 }, win)
	ui.strip = strip
	ui.stripFaces = {}
	for i = 1, STRIP_N do
		local f = cardFace(strip, { Position = UDim2.fromOffset((i - 1) * STEP, 0), Active = false, Selectable = false })
		-- (only for show: a controller skips them for the three offers; it used to land in the
		-- strip and couldn't pick, the owner, 2026-10-21: "Halloween cards are unselectable on
		-- controller")
		f.button:SetAttribute("NoNav", true)
		ui.stripFaces[i] = f
	end
	-- the three you pick from (in the slots, over the strip once it stops)
	ui.faces = {}
	for i = 1, HW.Offers do
		local face = cardFace(win, { Position = UDim2.fromOffset(x0 + (i - 1) * STEP, 6), Visible = false, ZIndex = 28 })
		for _, d in ipairs(face.button:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = d.ZIndex + 6
			end
		end
		face.button.ZIndex = 28
		face.button.Selectable = true
		if i == 1 then
			face.button:SetAttribute("NavFirst", true) -- (a controller starts on the first offer)
		end
		kit.onClick(face.button, function()
			if not spin and ui.pickReady then
				Net.get("Lobby"):FireServer("pick", i)
				ui.pickReady = false
				face.stroke.Color = ORANGE
				face.scale.Scale = 0.94
				TweenService:Create(face.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end)
		face.button.MouseEnter:Connect(function()
			if not spin and ui.pickReady then
				TweenService:Create(face.scale, TweenInfo.new(0.12), { Scale = 1.04 }):Play()
			end
		end)
		face.button.MouseLeave:Connect(function()
			TweenService:Create(face.scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end)
		ui.faces[i] = face
	end
	ui.pickWin = win
	ui.handRow = chipRow(m.panel, 520, "Your cards:")
	ui.mateRow = chipRow(m.panel, 560, "Teammates:")
	ui.aiRow = chipRow(m.panel, 600, "The AI:")
	ui.pickWait = Gui.label(m.panel, { Text = "", display = true, TextSize = 26, TextColor3 = Gui.SIGNAL_HOT, Position = UDim2.fromOffset(0, 290), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 30 })
	-- the run: Life and the Final Reward
	ui.runLine = Gui.label(m.panel, { Text = "", RichText = true, display = true, TextSize = 22, Position = UDim2.fromOffset(28, 52), Size = UDim2.fromOffset(700, 28), ZIndex = 22 })
	-- the path between stages: two nodes, the host picks
	local path = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 130), Size = UDim2.fromOffset(760, 330), BackgroundTransparency = 1, Visible = false, ZIndex = 30 }, m.panel)
	ui.path = { frame = path, buttons = {} }
	for i = 1, 2 do
		local b = make("TextButton", { Position = UDim2.fromOffset((i - 1) * 390, 0), Size = UDim2.fromOffset(370, 300), BackgroundColor3 = Gui.NAVY, AutoButtonColor = true, Text = "", BorderSizePixel = 0, ZIndex = 31 }, path)
		Gui.corner(b, 12)
		local stroke = make("UIStroke", { Color = ORANGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local name = Gui.label(b, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 44, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 50), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 32 })
		local blurb = Gui.label(b, { Text = "", TextSize = 19, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, -40, 0, 120), Position = UDim2.fromOffset(20, 130), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 32 })
		kit.onClick(b, function()
			Net.get("Lobby"):FireServer("colosseumPath", i)
		end)
		ui.path.buttons[i] = { button = b, name = name, blurb = blurb, stroke = stroke }
	end
end

-- The roll: the strip is dealt random cards with the offers in the three slots near its end, then
-- scrolls right to left, fast and slowing (ease-out), a tick for every card that passes the middle,
-- overshoots a touch and settles; the offers pop in their slots one by one.
local deck = Halloween.cards()
local LAND = STRIP_N - 4 -- the strip card that lands in the first slot
local function startSpin(id, offers)
	for i, f in ipairs(ui.stripFaces) do
		local key = nil
		if i >= LAND and i < LAND + HW.Offers then
			key = offers[i - LAND + 1]
		else
			key = deck[math.random(#deck)].Key
		end
		setFace(f, key, false)
		f.button.Visible = true
		f.button.BackgroundTransparency = 0
	end
	for i, face in ipairs(ui.faces) do
		face.button.Visible = false
		setFace(face, offers[i], false)
	end
	local xEnd = ui.slotX - (LAND - 1) * STEP
	local xStart = ui.slotX + 2 * STEP -- (the first cards come in from the right)
	ui.strip.Position = UDim2.fromOffset(xStart, 6)
	spin = { id = id, t0 = os.clock(), x0 = xStart, x1 = xEnd, keys = offers, passed = 0 }
	ui.pickReady = false
end

local function spinStep()
	if not spin then
		return
	end
	local T = HW.SpinTime
	local t = os.clock() - spin.t0
	local x
	if t < T then
		local k = t / T
		local e = 1 - (1 - k) ^ 4
		x = spin.x0 + (spin.x1 - 14 - spin.x0) * e -- (14 px past the slots, then back)
	elseif t < T + 0.22 then
		local k = (t - T) / 0.22
		x = spin.x1 - 14 + 14 * (1 - (1 - k) ^ 2)
	else
		x = spin.x1
	end
	ui.strip.Position = UDim2.fromOffset(math.floor(x + 0.5), 6)
	-- a tick for each card crossing the middle
	local passed = math.floor((spin.x0 - x) / STEP)
	if passed > spin.passed then
		spin.passed = passed
		if mods.AudioController then
			mods.AudioController.play("UISelect", { volume = 0.28, minGap = 0.035, speed = 1 + math.min(0.3, (spin.x0 - x) / 30000) })
		end
	end
	if t >= T + 0.22 then
		-- landed: the offers take their slots and pop, left to right
		local keys = spin.keys
		spin = nil
		for i, f in ipairs(ui.stripFaces) do
			f.button.Visible = not (i >= LAND and i < LAND + HW.Offers)
			if f.button.Visible then
				TweenService:Create(f.button, TweenInfo.new(0.25), { BackgroundTransparency = 0.6 }):Play()
			end
		end
		for i, face in ipairs(ui.faces) do
			face.button.Visible = keys[i] ~= nil
			task.delay((i - 1) * 0.09, function()
				face.scale.Scale = 1.1
				TweenService:Create(face.scale, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				if mods.AudioController then
					mods.AudioController.play("UIConfirm", { volume = 0.55, minGap = 0.05, speed = 0.95 + 0.07 * i })
				end
			end)
		end
		task.delay(0.12 * HW.Offers, function()
			ui.pickReady = true
		end)
	end
end

local function refreshPick()
	local mn = mine()
	local ev = mn and mn.event
	local picking = ev ~= nil and ev.picking == true
	if not picking then
		refreshMap(nil)
		ui.pick.root.Visible = false
		spin = nil
		ui.pickId = nil
		return
	end
	if kit.shown() then
		ui.pick.root.Visible = true
	end
	setChips(ui.handRow, ev.hand)
	local mateCards = {}
	for _, mt in ipairs(ev.mates or {}) do
		for _, k in ipairs(mt.cards or {}) do
			table.insert(mateCards, k)
		end
	end
	setChips(ui.mateRow, mateCards)
	setChips(ui.aiRow, ev.ai)
	ui.runLine.Text = string.format('Life <font color="%s"><b>%d / %d</b></font>   ·   Final Reward <font color="%s"><b>%d %s</b></font>',
		(ev.life or 0) <= 5 and "#FF5050" or "#7CFF6A", ev.life or 0, ev.lifeMax or HW.Life, "#FFC446", ev.reward or 0, HW.Candy.Name)
	-- the path between stages: the chain map (refreshMap) instead of this window
	ui.path.frame.Visible = false
	refreshMap(ev)
	if ev.path then
		ui.pick.root.Visible = false
		return
	end
	local d = ev.draft
	if d and d.offers then
		ui.pick.title.Text = string.format("Stage %d of %d: card %d of %d", ev.stage, ev.stages, d.pick, d.picks)
		local held = Halloween.abilityCount(ev.hand)
		ui.pickLine.Text = (held >= HW.MaxAbilityCards and string.format("Pick one. Your ability stays, with %d ability cards stacked on it: the most you can hold.", held)
			or string.format("Pick one. Your ability stays; ability cards stack on it (%d of %d so far).", held, HW.MaxAbilityCards)) .. " Out of time: one is picked at random."
		ui.pickWait.Visible = false
		local id = ev.stage .. ":" .. d.pick .. ":" .. table.concat(d.offers, ",")
		if ui.pickId ~= id then
			ui.pickId = id
			startSpin(id, d.offers)
		end
		ui.strip.Visible = true
	else
		ui.pick.title.Text = string.format("Stage %d of %d", ev.stage, ev.stages)
		ui.pickLine.Text = ""
		ui.pickWait.Visible = true
		ui.pickWait.Text = (ev.waiting or 0) > 0 and string.format("Waiting for %d teammate%s to pick...", ev.waiting, ev.waiting == 1 and "" or "s") or "Starting..."
		ui.strip.Visible = false
		for _, face in ipairs(ui.faces) do
			face.button.Visible = false
		end
	end
end

local function tickPick()
	local mn = mine()
	local d = mn and mn.event and mn.event.draft
	if d and d.endsAt then
		ui.pickTimer.Text = string.format("%d s", math.max(0, math.ceil(d.endsAt - Util.now())))
	else
		ui.pickTimer.Text = ""
	end
end

------------------------------------------------------------------------------------------
-- a recruit's results
------------------------------------------------------------------------------------------

local function buildReveal()
	local m = kit.modal("HalloweenReveal", "Halloween recruit", 1000, 560, true)
	ui.reveal = m
	local grid = make("Frame", { Position = UDim2.fromOffset(28, 100), Size = UDim2.new(1, -56, 1, -130), BackgroundTransparency = 1, ZIndex = 21 }, m.panel)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(176, 196), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	ui.revealGrid = grid
end

local function showReveal(r)
	-- the banner tab's last pulls line
	local parts = {}
	for _, it in ipairs(r.items or {}) do
		local item = Halloween.bannerItem(it.kind, it.key)
		local c = Spins.rarityColor(it.rarity)
		table.insert(parts, string.format('<font color="rgb(%d,%d,%d)">%s</font>', math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255), item and item.name or it.key))
	end
	ui.tabs.Banner.last.Text = "Last recruit: " .. table.concat(parts, ", ")
	if kit.playRecruit and kit.shown() then
		local items = {}
		for i, it in ipairs(r.items or {}) do
			local item = Halloween.bannerItem(it.kind, it.key)
			items[i] = { hw = true, kind = it.kind, key = it.key, name = item and item.name or it.key, rarity = it.rarity, dup = it.dup, candy = it.candy }
		end
		kit.playRecruit({ banner = "Halloween", theme = "Halloween", items = items, candy = r.candy })
		return
	end
	for _, c in ipairs(ui.revealGrid:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, it in ipairs(r.items or {}) do
		local item = Halloween.bannerItem(it.kind, it.key)
		local color = Spins.rarityColor(it.rarity)
		local f = make("Frame", { BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 22 }, ui.revealGrid)
		Gui.corner(f, 8)
		make("UIStroke", { Color = color, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
		Gui.label(f, { Text = it.rarity, display = true, TextSize = 16, TextColor3 = color, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 10), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(f, { Text = item and item.name or it.key, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextWrapped = true, Size = UDim2.new(1, -16, 0, 70), Position = UDim2.fromOffset(8, 40), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(f, { Text = itemKindName(it.kind), TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 112), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		local note = it.kind == "Skin" and "+1 copy" or (it.dup and string.format("Duplicate: +%d Candy", it.candy or 0) or "New!")
		Gui.label(f, { Text = note, display = true, TextSize = 17, TextColor3 = it.dup and Gui.DIM or Gui.SIGNAL_HOT, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 150), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	end
	ui.reveal.title.Text = string.format("Halloween recruit x%d", r.count or #(r.items or {}))
	ui.reveal.root.Visible = true
end

------------------------------------------------------------------------------------------
-- in a match: your cards and the AI's
------------------------------------------------------------------------------------------

local function buildHud()
	local sg = make("ScreenGui", { Name = "SpikeRushHalloween", ResetOnSpawn = false, DisplayOrder = 6, Enabled = false }, player:WaitForChild("PlayerGui"))
	local f = make("Frame", { AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 12, 0, 120), Size = UDim2.fromOffset(240, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, sg)
	Gui.corner(f, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, f)
	local text = Gui.label(f, { Text = "", RichText = true, TextSize = 14, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), TextYAlignment = Enum.TextYAlignment.Top })
	ui.hud = { gui = sg, text = text }
end

local function colorTag(c)
	return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function refreshHud()
	local mn = mine()
	local ev = mn and mn.event
	local on = State.isPlaying and State.match and State.match.event ~= nil and ev ~= nil
	ui.hud.gui.Enabled = on == true
	if not on then
		return
	end
	local node = Halloween.node(ev.node)
	local lines = { string.format('<b><font color="%s">COLOSSEUM · STAGE %d/%d%s</font></b>', colorTag(ORANGE), ev.stage, ev.stages, node and node.Kind == "Match" and node.Name ~= "Match" and (" · " .. string.upper(node.Name)) or ""),
		string.format("Life %d/%d  ·  Reward %d %s", ev.life or 0, ev.lifeMax or HW.Life, ev.reward or 0, HW.Candy.Name) }
	-- (the cards on one line each list, so the box stays clear of the ability buttons below it)
	local function add(title, keys)
		if keys and #keys > 0 then
			local names = {}
			for _, k in ipairs(keys) do
				local card = Halloween.card(k)
				if card then
					table.insert(names, string.format('<font color="%s">%s</font>', colorTag(kindColor(card)), card.Name))
				end
			end
			table.insert(lines, "<b>" .. title .. ":</b> " .. table.concat(names, ", "))
		end
	end
	-- what stacked: your character's own ability and every ability card's, in the order they play
	local names = {}
	for _, a in ipairs(State.myAbilities()) do
		local def = Config.Abilities[a]
		table.insert(names, string.format('<font color="%s">%s</font>', colorTag(def.Color), def.Name))
	end
	if #names > 0 then
		table.insert(lines, "<b>Abilities:</b> " .. table.concat(names, " + "))
	end
	add("Your cards", ev.hand)
	add("The AI's", ev.ai)
	ui.hud.text.Text = table.concat(lines, "\n")
end

------------------------------------------------------------------------------------------
-- the chain map (the owner, 2026-11-14: "i wanted this kind of progressing chain for coloseum",
-- with The Spike Cross's Volleyball Colosseum as the reference): the run as a chain of hexagon
-- nodes up the Colosseum, one row a stage, dotted lines between them. The stages behind you
-- show the node each one took (mine.event.trail); the stage to pick shows the path's two choices,
-- glowing; the stages ahead are unknown, the All-Star at the top. Final Reward, Remaining Life and
-- your cards in panels at the top right. Pick a node: its name and stage show at the top, and the
-- host's button at the bottom right takes it (Prepare for Match, or Take the Rest).
------------------------------------------------------------------------------------------

local SQ3 = math.sqrt(3)
local MAP_W, MAP_H = 1600, 900
local HEX_R = 56
local NODE_ICONS = { Match = "IconPlayers", Elite = "IconAttack", Rest = "IconHome", AllStar = "IconStar" }
local REST_GREEN = Color3.fromRGB(120, 220, 140)
local ELITE_RED = Color3.fromRGB(235, 80, 80)

-- A pointy-top hexagon of circumradius r: three rectangles turned 0, 60 and 120 degrees.
local function hexShape(parent, r, color, z)
	local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(SQ3 * r, 2 * r), BackgroundTransparency = 1, ZIndex = z }, parent)
	local parts = {}
	for i = 0, 2 do
		parts[i + 1] = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(math.floor(SQ3 * r + 0.5), r), Rotation = i * 60, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z }, holder)
	end
	return { holder = holder, parts = parts }
end

local function hexColor(h, color)
	for _, p in ipairs(h.parts) do
		p.BackgroundColor3 = color
	end
end

-- One node: a glow (when picked), a rim, a dark face, an inner line, the icon (or "?") and the
-- name under it.
local function mapNode(parent, x, y, onClick)
	local b = make("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(HEX_R * 2, HEX_R * 2), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 40 }, parent)
	local glow = make("CanvasGroup", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(HEX_R * 3, HEX_R * 3), BackgroundTransparency = 1, GroupTransparency = 0.55, Visible = false, ZIndex = 41 }, b)
	local glowHex = hexShape(glow, HEX_R + 16, Gui.GOLD, 41)
	local rim = hexShape(b, HEX_R, Gui.CHALK, 42)
	local face = hexShape(b, HEX_R - 5, Gui.NAVY, 43)
	local line = hexShape(b, HEX_R - 11, Gui.CHALK, 44)
	local inner = hexShape(b, HEX_R - 14, Gui.NAVY, 45)
	local icon = Gui.iconImage(b, "IconStar", 50, Gui.CHALK, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 46 })
	local q = Gui.label(b, { Text = "?", display = true, weight = Enum.FontWeight.Heavy, TextSize = 46, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(60, 60), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 46 })
	local name = Gui.label(b, { Text = "", display = true, TextSize = 18, TextStrokeTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(200, 22), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 46 })
	local scale = make("UIScale", { Scale = 1 }, b)
	if onClick then
		kit.onClick(b, onClick)
		b.MouseEnter:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.08 }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		end)
	end
	return { button = b, glow = glow, glowHex = glowHex, rim = rim, face = face, line = line, inner = inner, icon = icon, q = q, name = name }
end

-- How a node looks: "done" (a stage behind you), "choice" (one of the path's two), "picked" (the
-- choice you picked), "ahead" (unknown yet), "boss" (the All-Star at the top).
local function styleNode(n, key, look)
	local node = key and Halloween.node(key)
	local tint = Gui.CHALK
	if node and node.Kind == "Rest" then
		tint = REST_GREEN
	elseif node and node.Elite then
		tint = ELITE_RED
	elseif node and node.Boss then
		tint = Gui.GOLD
	end
	local rimC, lineC, iconC = tint, tint, tint
	if look == "done" then
		rimC, lineC, iconC = Color3.fromRGB(120, 124, 140), Color3.fromRGB(90, 94, 110), Color3.fromRGB(150, 154, 170)
	elseif look == "ahead" then
		rimC, lineC, iconC = Color3.fromRGB(80, 84, 100), Color3.fromRGB(60, 64, 80), Color3.fromRGB(110, 114, 130)
	elseif look == "picked" then
		rimC = Gui.GOLD
	end
	hexColor(n.rim, rimC)
	hexColor(n.line, lineC)
	hexColor(n.glowHex, look == "picked" and Gui.GOLD or tint)
	n.glow.Visible = look == "picked" or look == "choice"
	n.glow.GroupTransparency = look == "picked" and 0.35 or 0.75
	n.icon.Visible = node ~= nil and look ~= "ahead"
	n.icon.Image = Assets.image(NODE_ICONS[key or ""] or "IconStar") or ""
	n.icon.ImageColor3 = iconC
	n.q.Visible = not n.icon.Visible
	n.q.TextColor3 = iconC
	n.name.Text = (node and look ~= "ahead") and string.upper(node.Name) or ""
	n.name.TextColor3 = look == "done" and Gui.DIM or Gui.CHALK
	n.button.Active = look == "choice" or look == "picked"
end

-- A dotted line between two points on the map.
local function dots(parent, a, b)
	local d = b - a
	local n = math.max(1, math.floor(d.Magnitude / 15))
	for i = 1, n - 1 do
		local p = a + d * (i / n)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p.X, p.Y), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Gui.CHALK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 39 }, parent)
	end
end

local function mapPanel(parent, x, w, title)
	local f = make("Frame", { Position = UDim2.fromOffset(x, 24), Size = UDim2.fromOffset(w, 92), BackgroundColor3 = Gui.NAVY, BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 50 }, parent)
	Gui.corner(f, 6)
	make("UIStroke", { Color = Gui.GOLD_LIGHT, Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	Gui.label(f, { Text = title, TextSize = 15, weight = Enum.FontWeight.Bold, TextColor3 = Gui.GOLD_LIGHT, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 51 })
	return f
end

local function buildMap()
	local sg = make("ScreenGui", { Name = "ColosseumMap", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 25, Enabled = false }, player:WaitForChild("PlayerGui"))
	make("ImageLabel", { Name = "Court", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Assets.image("MatchColosseum") or "", ScaleType = Enum.ScaleType.Crop, ZIndex = 1 }, sg)
	local shade = make("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 2 }, sg)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.35, 0.45), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 0) }) }, shade)
	local canvas = make("Frame", { Name = "Canvas", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(MAP_W, MAP_H), BackgroundTransparency = 1, ZIndex = 3 }, sg)
	local uiScale = make("UIScale", { Scale = 1 }, canvas)
	local function fit()
		local cam = workspace.CurrentCamera
		local v = cam and cam.ViewportSize or Vector2.new(MAP_W, MAP_H)
		uiScale.Scale = math.min(v.X / MAP_W, v.Y / MAP_H)
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	local chain = make("Frame", { Name = "Chain", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 39 }, canvas)
	-- the panels, top right: Final Reward, Remaining Life, your cards
	local cardsW, lifeW, rewardW = 260, 130, 150
	local xCards = MAP_W - 24 - cardsW
	local xLife = xCards - 10 - lifeW
	local xReward = xLife - 10 - rewardW
	local reward = mapPanel(canvas, xReward, rewardW, "Final Reward")
	local rewardText = Gui.label(reward, { Text = "0", RichText = true, display = true, weight = Enum.FontWeight.Heavy, TextSize = 36, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 52), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 51 })
	local life = mapPanel(canvas, xLife, lifeW, "Remaining Life")
	local lifeText = Gui.label(life, { Text = "0", display = true, weight = Enum.FontWeight.Heavy, TextSize = 44, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 51 })
	local cards = mapPanel(canvas, xCards, cardsW, "Selected Cards")
	local dotRow = make("Frame", { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, ZIndex = 51 }, cards)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12) }, dotRow)
	local cardDots = {}
	for i = 1, HW.MaxHand do
		local d = make("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Gui.CHALK, BackgroundTransparency = 0.6, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 52 }, dotRow) -- (8 of them fit the panel)
		Gui.corner(d, 7)
		cardDots[i] = d
	end
	local cardsLine = Gui.label(cards, { Text = "", TextSize = 13, TextColor3 = Gui.DIM, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(10, 62), Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 51 })
	-- the banner, top centre: the picked node's name and stage
	local banner = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(MAP_W / 2, 10), Size = UDim2.fromOffset(420, 150), BackgroundTransparency = 1, Visible = false, ZIndex = 50 }, canvas)
	local bIcon = Gui.iconImage(banner, "IconStar", 34, Gui.CHALK, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), ZIndex = 51 })
	local bName = Gui.label(banner, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 44, TextColor3 = Gui.GOLD_LIGHT, TextStrokeTransparency = 0.5, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 50), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 51 })
	local bar = make("Frame", { Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 50 }, banner)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }) }, bar)
	local bStage = Gui.label(bar, { Text = "", TextSize = 16, weight = Enum.FontWeight.Bold, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 51 })
	local bBlurb = Gui.label(banner, { Text = "", TextSize = 16, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(20, 122), Size = UDim2.new(1, -40, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 51 })
	-- the button, bottom right (the host's)
	local go = make("TextButton", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromOffset(MAP_W - 24, MAP_H - 24), Size = UDim2.fromOffset(250, 120), BackgroundColor3 = Gui.NAVY, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = true, BorderSizePixel = 0, Visible = false, ZIndex = 50 }, canvas)
	Gui.corner(go, 6)
	make("UIStroke", { Color = Gui.GOLD_LIGHT, Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, go)
	local goIcon = Gui.iconImage(go, "IconAttack", 50, Gui.CHALK, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), ZIndex = 51 })
	local goStrip = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 51 }, go)
	local goText = Gui.label(goStrip, { Text = "Prepare for Match", display = true, TextSize = 20, TextColor3 = Gui.GOLD_LIGHT, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 52 })
	-- the line along the bottom: who picks, and the time left
	local hint = Gui.label(canvas, { Text = "", display = true, TextSize = 22, TextStrokeTransparency = 0.5, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(MAP_W / 2, MAP_H - 6), Size = UDim2.fromOffset(800, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 50 })
	ui.map = { gui = sg, chain = chain, rewardText = rewardText, lifeText = lifeText, cardDots = cardDots, cardsLine = cardsLine, banner = banner, bIcon = bIcon, bName = bName, bStage = bStage, bBlurb = bBlurb, go = go, goIcon = goIcon, goText = goText, hint = hint, sel = nil, id = nil, nodes = {} }
	kit.onClick(go, function()
		local mp = ui.map
		if mp.sel and mp.host then
			Net.get("Lobby"):FireServer("colosseumPath", mp.sel)
			go.Visible = false
		end
	end)
end

-- Where stage s's row stands (stage 1 at the bottom, the All-Star at the top).
local function rowY(s)
	return MAP_H - 135 - (s - 1) * ((MAP_H - 360) / math.max(1, HW.Stages - 1))
end

function mapHint()
	local mp = ui.map
	local ev = mp and mp.ev
	if not ev or not ev.path or not mp.gui.Enabled then
		return
	end
	local left = math.max(0, math.ceil((ev.path.endsAt or 0) - Util.now()))
	local what
	if not ev.path.host then
		what = "The host picks the path."
	elseif mp.sel then
		what = "Ready? Take it at the bottom right."
	else
		what = "Pick the next node on the chain."
	end
	mp.hint.Text = string.format("%s  ·  %ds", what, left)
end

function refreshMap(ev)
	local mp = ui.map
	if not mp then
		return
	end
	local on = ev ~= nil and ev.path ~= nil and kit.shown()
	mp.gui.Enabled = on == true
	mp.ev = ev
	if not on then
		mp.sel, mp.id = nil, nil
		return
	end
	local path = ev.path
	local id = ev.stage .. ":" .. table.concat(path.choices, ",")
	if mp.id ~= id then
		-- a new path: the chain again, nothing picked
		mp.id, mp.sel = id, nil
		mp.chain:ClearAllChildren()
		mp.nodes = {}
		local trail = ev.trail or {}
		local rows = {}
		for s = 1, ev.stages do
			local keys
			if s < ev.stage then
				keys = { trail[s] or "Match" }
			elseif s == ev.stage then
				keys = path.choices
			elseif s == ev.stages then
				keys = { "AllStar" }
			else
				keys = { false }
			end
			local row = {}
			for i, key in ipairs(keys) do
				local x = MAP_W / 2 + (i - (#keys + 1) / 2) * 290
				row[i] = { key = key or nil, pos = Vector2.new(x, rowY(s)) }
			end
			rows[s] = row
		end
		for s = 1, ev.stages - 1 do
			for _, a in ipairs(rows[s]) do
				for _, b in ipairs(rows[s + 1]) do
					dots(mp.chain, a.pos, b.pos)
				end
			end
		end
		for s, row in ipairs(rows) do
			for i, r in ipairs(row) do
				local onClick = nil
				if s == ev.stage then
					onClick = function()
						if not mp.host then
							return
						end
						mp.sel = i
						if mods.AudioController then
							mods.AudioController.play("UISelect", { volume = 0.5 })
						end
						refreshMap(mp.ev)
					end
				end
				local n = mapNode(mp.chain, r.pos.X, r.pos.Y, onClick)
				n.stage, n.index, n.key = s, i, r.key
				table.insert(mp.nodes, n)
			end
		end
	end
	mp.host = path.host == true
	for _, n in ipairs(mp.nodes) do
		local look
		if n.stage < ev.stage then
			look = "done"
		elseif n.stage == ev.stage then
			look = mp.sel == n.index and "picked" or "choice"
		elseif n.key == "AllStar" then
			look = "boss"
		else
			look = "ahead"
		end
		styleNode(n, n.key, look)
	end
	-- the panels
	mp.rewardText.Text = string.format('<font color="#FFC446">%d</font> <font size="18">%s</font>', ev.reward or 0, HW.Candy.Name)
	mp.lifeText.Text = tostring(ev.life or 0)
	mp.lifeText.TextColor3 = (ev.life or 0) <= 5 and Color3.fromRGB(255, 90, 90) or Gui.CHALK
	local hand = ev.hand or {}
	local names = {}
	for i, d in ipairs(mp.cardDots) do
		local card = hand[i] and Halloween.card(hand[i])
		d.BackgroundColor3 = card and kindColor(card) or Gui.CHALK
		d.BackgroundTransparency = card and 0 or 0.6
		if card then
			table.insert(names, card.Name)
		end
	end
	mp.cardsLine.Text = #names > 0 and table.concat(names, ", ") or "No cards yet"
	-- the picked node: the banner and the button
	local key = mp.sel and path.choices[mp.sel]
	local node = key and Halloween.node(key)
	mp.banner.Visible = node ~= nil
	mp.go.Visible = node ~= nil and mp.host
	if node then
		mp.bIcon.Image = Assets.image(NODE_ICONS[key] or "IconStar") or ""
		mp.bName.Text = node.Name
		mp.bStage.Text = string.format("STAGE %d OF %d", ev.stage, ev.stages)
		mp.bBlurb.Text = node.Blurb or ""
		local rest = node.Kind == "Rest"
		mp.goText.Text = rest and string.format("Take the Rest (+%d)", HW.RestHeal) or "Prepare for Match"
		mp.goIcon.Image = Assets.image(rest and "IconHome" or "IconAttack") or ""
	end
	mapHint()
end

------------------------------------------------------------------------------------------
-- refresh
------------------------------------------------------------------------------------------

function HalloweenMenu.refresh()
	if not ui.window then
		return
	end
	local p = prof()
	local ev = eventOf(p)
	local now = Util.now()
	local active = Halloween.active(now)
	-- today's rewarded runs (a copy: the profile's isn't touched here)
	local runsLeft = math.max(0, HW.RewardedRuns - Halloween.runsToday({ runDay = ev.runDay, runs = ev.runs }, Halloween.day(now)))
	if ui.homeBtn then
		ui.homeBtn.Visible = true -- (the Colosseum is there for good)
		ui.homeLeft.Text = string.format("%d/%d runs", runsLeft, HW.RewardedRuns)
	end
	-- a match started with the window open: it goes (the menus hide their own modals then)
	if State.isPlaying and ui.window.root.Visible then
		ui.window.root.Visible = false
	end
	ui.info.Text = string.format("%s %s  ·  rewarded runs today %d/%d%s", Gui.num(ev.candy or 0), HW.Candy.Name, runsLeft, HW.RewardedRuns, active and string.format("  ·  banner %s left", leftText(Halloween.secondsLeft(now))) or "")
	if ui.window.root.Visible then
		local T = ui.tabs
		if tab == "Match" then
			for key, c in pairs(T.Match.cards) do
				c.done.Text = runsLeft == 0 and "Today's rewarded runs are used: runs pay a share" or ""
			end
		elseif tab == "Banner" then
			T.Banner.scout.Text = string.format("%d scout points", ev.scout or 0)
			local skins = p.skins or {}
			for _, r in ipairs(T.Banner.rows) do
				local it = r.item
				if it.kind == "Skin" then
					local row = skins[it.key]
					local have = row ~= nil and row.copies > 0
					r.have.Text = have and "Owned" or ""
					r.pick.Visible = not have -- (a second copy would only be a duplicate: Jaeil wears one)
				elseif it.kind == "Room" then
					local have = p.rooms and p.rooms.owned and p.rooms.owned[it.key] == true
					r.have.Text = have and "Owned" or ""
					r.pick.Visible = not have
				elseif it.kind == "Card" then
					local have = p.cards and p.cards.unlocked and p.cards.unlocked[it.key] == true
					r.have.Text = have and "Owned" or ""
					r.pick.Visible = not have
				else
					local owned = p.owned and p.owned[it.kind] and p.owned[it.kind][it.key] == true
					r.have.Text = owned and "Owned" or ""
					r.pick.Visible = not owned
				end
				r.pickL.TextColor3 = (ev.scout or 0) >= it.scout and Gui.SIGNAL or Gui.DIM
			end
		elseif tab == "Shop" then
			for _, r in ipairs(T.Shop.rows) do
				local row = r.row
				local n = (ev.bought and ev.bought[row.Key]) or 0
				local owned = row.Item and p.owned and p.owned[row.Item.Kind] and p.owned[row.Item.Kind][row.Item.Key] == true
				if owned then
					r.left.Text = "Owned"
				elseif row.Limit then
					r.left.Text = string.format("%d of %d left", math.max(0, row.Limit - n), row.Limit)
				else
					r.left.Text = ""
				end
				r.buy.Visible = not owned and not (row.Limit and n >= row.Limit)
			end
		end
	end
	refreshPick()
	refreshHud()
end

------------------------------------------------------------------------------------------

function HalloweenMenu.init(m)
	mods = m
	kit = mods.MenuController.kit()
	buildWindow()
	buildPick()
	buildReveal()
	buildHud()
	buildMap()
	-- (no button down Home's right edge any more: the owner, 2026-11-15, "take colloseum off this
	-- sidebar". The Colosseum is a card in the Match row.)
	local lastReveal = nil
	State.signals.Profile:Connect(function(p)
		if type(p) == "table" and p.hwReveal and p.hwReveal ~= lastReveal then
			lastReveal = p.hwReveal
			showReveal(p.hwReveal)
		end
		HalloweenMenu.refresh()
	end)
	Net.get("Lobbies").OnClientEvent:Connect(function()
		task.defer(HalloweenMenu.refresh) -- (after MenuController has taken the payload)
	end)
	State.signals.Match:Connect(function()
		task.defer(HalloweenMenu.refresh)
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		spinStep()
		acc = acc + dt
		if acc >= 0.5 then
			acc = 0
			tickPick()
			mapHint()
			if ui.pick.root.Visible or ui.window.root.Visible or ui.map.gui.Enabled or (ui.homeBtn and kit.shown()) then
				HalloweenMenu.refresh()
			end
		end
	end)
	HalloweenMenu.refresh()
end

return HalloweenMenu
