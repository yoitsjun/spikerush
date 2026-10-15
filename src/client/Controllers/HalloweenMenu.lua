-- The Halloween event's screens (Config.Halloween, the shared Halloween module), drawn with the
-- menus' kit (MenuController.kit) on the menus' canvas:
--   * a Halloween button down Home's right edge, with the time left
--   * the event window: Match (Easy / Normal / Hard: what each pays, today's first clears),
--     Banner (what's on it, the odds, scout points, recruits for VP or Candy), Shop (Candy
--     prices) and Reaper (your copies, and the characters they're on, switched on or off)
--   * the card picks before each stage (LobbyService's mine.event.draft): the roulette spins
--     through the deck and stops on 3 cards; you pick 1; your hand, your teammates' and the AI's
--     underneath, and the time left
--   * a Halloween recruit's results (the profile's hwReveal)
--   * in a Halloween Match, your cards and the AI's at the side of the screen
-- The looks are first passes: the PC Claude lays them out in Studio (HANDOFF.md).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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

local function cardFace(parent, props)
	local b = make("TextButton", { BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 22 }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Gui.corner(b, 10)
	local stroke = make("UIStroke", { Thickness = 3, Transparency = 0.05, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local band = make("Frame", { Size = UDim2.new(1, 0, 0, 40), BorderSizePixel = 0, ZIndex = 23 }, b)
	Gui.corner(band, 10)
	local kind = Gui.label(band, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 18, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
	local name = Gui.label(b, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextWrapped = true, Size = UDim2.new(1, -24, 0, 76), Position = UDim2.fromOffset(12, 50), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	local rarity = Gui.label(b, { Text = "", display = true, TextSize = 17, Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 128), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	local blurb = Gui.label(b, { Text = "", TextSize = 17, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -28, 1, -170), Position = UDim2.fromOffset(14, 160), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	return { button = b, stroke = stroke, band = band, kind = kind, name = name, rarity = rarity, blurb = blurb }
end

local function setFace(face, key, dim)
	local card = Halloween.card(key)
	if not card then
		face.name.Text = "?"
		face.kind.Text = ""
		face.rarity.Text = ""
		face.blurb.Text = ""
		return
	end
	local color = kindColor(card)
	face.band.BackgroundColor3 = color
	face.stroke.Color = Spins.rarityColor(card.Rarity)
	face.kind.Text = string.upper(HW.Kinds[card.Kind].Name)
	face.name.Text = card.Name
	face.rarity.Text = card.Rarity
	face.rarity.TextColor3 = Spins.rarityColor(card.Rarity)
	face.blurb.Text = Halloween.blurb(card)
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
	Gui.label(f, { Text = string.format("Two stages of %d points against the AI. Before each, the roulette deals 3 cards: pick 1, twice. Win both stages to clear it. The first clear of each difficulty every day pays the most Candy.", HW.Points), TextSize = 17, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 44), ZIndex = 22 })
	local cards = {}
	local W, GAP = 352, 22
	for i, d in ipairs(HW.Difficulties) do
		local card = make("Frame", { Position = UDim2.fromOffset((i - 1) * (W + GAP), 56), Size = UDim2.fromOffset(W, 440), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, ZIndex = 22 }, f)
		Gui.corner(card, 10)
		make("UIStroke", { Color = d.Color, Thickness = 2, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		local head = make("Frame", { Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = d.Color, BorderSizePixel = 0, ZIndex = 23 }, card)
		Gui.corner(head, 10)
		Gui.label(head, { Text = string.upper(d.Name), display = true, weight = Enum.FontWeight.Heavy, TextSize = 34, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
		Gui.label(card, { Text = string.format("%s bots  ·  %d stages  ·  %dv%d", d.Bots, HW.Stages, HW.Mode, HW.Mode), display = true, TextSize = 19, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 80), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(card, { Text = d.AiCards == 0 and "The AI takes no cards." or string.format("The AI takes %d card%s a stage.", d.AiCards, d.AiCards == 1 and "" or "s"), TextSize = 16, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 108), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(card, { Text = "FIRST CLEAR TODAY", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 146), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(card, { Text = string.format("%d Candy", d.Candy), display = true, weight = Enum.FontWeight.Heavy, TextSize = 40, TextColor3 = ORANGE, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 172), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		Gui.label(card, { Text = string.format("Later clears: %d Candy\nOut in stage 2: %d Candy", d.Repeat, d.StageOne), TextSize = 16, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 226), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
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
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 52), Size = UDim2.fromOffset(700, 444), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, f)
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
	Gui.label(f, { Text = "Candy from Halloween Matches buys these until the event ends. Your Candy stays after it.", TextSize = 17, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 28), ZIndex = 22 })
	local rows = {}
	for i, row in ipairs(HW.Shop) do
		local r = make("Frame", { Position = UDim2.fromOffset(0, 40 + (i - 1) * 64), Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, ZIndex = 22 }, f)
		Gui.corner(r, 6)
		Gui.label(r, { Text = row.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(480, 56), ZIndex = 23 })
		local left = Gui.label(r, { Text = "", TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(520, 0), Size = UDim2.fromOffset(240, 56), ZIndex = 23 })
		local buy, buyL = kit.actionPlate(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(240, 44) }, string.format("Buy  ·  %d Candy", row.Price), 19)
		kit.onClick(buy, function()
			Net.get("Profile"):FireServer("hwShop", row.Key)
		end)
		rows[i] = { row = row, left = left, buy = buy, buyL = buyL }
	end
	return { frame = f, rows = rows }
end

local function buildReaperTab(body)
	local key = HW.SkinOrder[1]
	local skin = HW.Skins[key]
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	Gui.label(f, { Text = skin.Name:upper(), display = true, weight = Enum.FontWeight.Heavy, TextSize = 40, TextColor3 = skin.Color, Size = UDim2.new(1, 0, 0, 44), ZIndex = 22 })
	Gui.label(f, { Text = skin.Blurb, TextSize = 17, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 46), ZIndex = 22 })
	local copies = Gui.label(f, { Text = "", display = true, TextSize = 22, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 96), ZIndex = 22 })
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 132), Size = UDim2.new(1, 0, 0, 364), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, f)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(360, 56), CellPadding = UDim2.fromOffset(10, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rows = {}
	for i, c in ipairs(Roster) do
		local r = make("Frame", { BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, LayoutOrder = i, Visible = false, ZIndex = 22 }, list)
		Gui.corner(r, 6)
		Gui.label(r, { Text = c.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(12, 2), Size = UDim2.fromOffset(170, 30), ZIndex = 23 })
		local state = Gui.label(r, { Text = "", TextSize = 14, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(12, 30), Size = UDim2.fromOffset(170, 20), ZIndex = 23 })
		local act, actL = kit.hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(160, 40), ZIndex = 23 }, "", 17)
		local entry = { frame = r, state = state, act = act, actL = actL, char = c }
		kit.onClick(act, function()
			local p = prof()
			local row = p.skins and p.skins[key]
			local on = row and row.on and row.on[c.Id]
			local op = on == nil and "apply" or (on and "off" or "on")
			Net.get("Profile"):FireServer("skin", op, c.Id, key)
		end)
		rows[i] = entry
	end
	return { frame = f, rows = rows, copies = copies, key = key }
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
	local items = { { key = "Match", text = "Match" }, { key = "Banner", text = "Banner" }, { key = "Shop", text = "Candy shop" }, { key = "Reaper", text = "Reaper" } }
	local _, set = kit.segmented(m.panel, items, { Position = UDim2.fromOffset(28, 86), Size = UDim2.fromOffset(640, 46), ZIndex = 22 }, setTab)
	ui.setSeg = set
	local body = make("Frame", { Position = UDim2.fromOffset(28, 148), Size = UDim2.new(1, -56, 1, -170), BackgroundTransparency = 1, ZIndex = 21 }, m.panel)
	ui.tabs = { Match = buildMatchTab(body), Banner = buildBannerTab(body), Shop = buildShopTab(body), Reaper = buildReaperTab(body) }
	set(tab)
end

function HalloweenMenu.open(which)
	if which then
		setTab(which)
	end
	ui.window.root.Visible = true
	HalloweenMenu.refresh()
end

------------------------------------------------------------------------------------------
-- the picks
------------------------------------------------------------------------------------------

local spin = nil -- { id, t0, slots = { { stopAt, nextAt, key } } } while the roulette runs

local function buildPick()
	local m = kit.modal("HalloweenPick", "Pick a card", 1100, 700, true)
	hideClose(m)
	mods.PadNav.set(m.root, "prio", 30) -- (over the lobby's window)
	ui.pick = m
	ui.pickTimer = Gui.label(m.panel, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextColor3 = ORANGE, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, 22), Size = UDim2.fromOffset(300, 36), ZIndex = 22 })
	ui.pickLine = Gui.label(m.panel, { Text = "", TextSize = 18, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(28, 84), Size = UDim2.new(1, -56, 0, 24), ZIndex = 22 })
	ui.faces = {}
	local W, GAP = 300, 30
	local x0 = (1100 - (3 * W + 2 * GAP)) / 2
	for i = 1, HW.Offers do
		local face = cardFace(m.panel, { Position = UDim2.fromOffset(x0 + (i - 1) * (W + GAP), 120), Size = UDim2.fromOffset(W, 380) })
		kit.onClick(face.button, function()
			if not spin and ui.pickReady then
				Net.get("Lobby"):FireServer("pick", i)
				ui.pickReady = false
			end
		end)
		ui.faces[i] = face
	end
	ui.handRow = chipRow(m.panel, 520, "Your cards:")
	ui.mateRow = chipRow(m.panel, 560, "Teammates:")
	ui.aiRow = chipRow(m.panel, 600, "The AI:")
	ui.pickWait = Gui.label(m.panel, { Text = "", display = true, TextSize = 26, TextColor3 = Gui.SIGNAL_HOT, Position = UDim2.fromOffset(0, 290), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 25 })
end

-- The roulette: each slot flicks through the deck, slowing, and stops on its offer in turn.
local function startSpin(id, offers)
	local now = os.clock()
	local slots = {}
	for i = 1, HW.Offers do
		slots[i] = { stopAt = now + HW.SpinTime * (0.55 + 0.45 * i / HW.Offers), nextAt = now, key = offers[i] }
	end
	spin = { id = id, t0 = now, slots = slots }
	ui.pickReady = false
end

local deck = Halloween.cards()
local function spinStep()
	if not spin then
		return
	end
	local now = os.clock()
	local running = false
	for i, s in ipairs(spin.slots) do
		local face = ui.faces[i]
		if now < s.stopAt then
			running = true
			if now >= s.nextAt then
				setFace(face, deck[math.random(#deck)].Key, true)
				local k = math.clamp((now - spin.t0) / HW.SpinTime, 0, 1)
				s.nextAt = now + 0.045 + 0.22 * k * k
				if mods.AudioController then
					mods.AudioController.play("UISelect", { volume = 0.3, minGap = 0.04 })
				end
			end
		elseif not s.done then
			s.done = true
			setFace(face, s.key, false)
			if mods.AudioController then
				mods.AudioController.play("UIConfirm", { volume = 0.6, minGap = 0.05 })
			end
		end
	end
	if not running then
		spin = nil
		ui.pickReady = true
	end
end

local function refreshPick()
	local mn = mine()
	local ev = mn and mn.event
	local picking = ev ~= nil and ev.picking == true
	if not picking then
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
	local d = ev.draft
	if d and d.offers then
		ui.pick.title.Text = string.format("Stage %d of %d: card %d of %d", ev.stage, ev.stages, d.pick, d.picks)
		ui.pickLine.Text = "Pick one. A new ability card replaces the one you have."
		ui.pickWait.Visible = false
		local id = ev.stage .. ":" .. d.pick .. ":" .. table.concat(d.offers, ",")
		if ui.pickId ~= id then
			ui.pickId = id
			startSpin(id, d.offers)
		end
		for _, face in ipairs(ui.faces) do
			face.button.Visible = true
		end
	else
		ui.pick.title.Text = string.format("Stage %d of %d", ev.stage, ev.stages)
		ui.pickLine.Text = ""
		ui.pickWait.Visible = true
		ui.pickWait.Text = (ev.waiting or 0) > 0 and string.format("Waiting for %d teammate%s to pick...", ev.waiting, ev.waiting == 1 and "" or "s") or "Starting..."
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
	-- the banner tab's last pulls line
	local parts = {}
	for _, it in ipairs(r.items or {}) do
		local item = Halloween.bannerItem(it.kind, it.key)
		local c = Spins.rarityColor(it.rarity)
		table.insert(parts, string.format('<font color="rgb(%d,%d,%d)">%s</font>', math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255), item and item.name or it.key))
	end
	ui.tabs.Banner.last.Text = "Last recruit: " .. table.concat(parts, ", ")
end

------------------------------------------------------------------------------------------
-- in a match: your cards and the AI's
------------------------------------------------------------------------------------------

local function buildHud()
	local sg = make("ScreenGui", { Name = "SpikeRushHalloween", ResetOnSpawn = false, DisplayOrder = 6, Enabled = false }, player:WaitForChild("PlayerGui"))
	local f = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.32, 0), Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, sg)
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
	local lines = { string.format('<b><font color="%s">HALLOWEEN · STAGE %d/%d</font></b>', colorTag(ORANGE), ev.stage, ev.stages) }
	local function add(title, keys)
		if keys and #keys > 0 then
			table.insert(lines, "<b>" .. title .. "</b>")
			for _, k in ipairs(keys) do
				local card = Halloween.card(k)
				if card then
					table.insert(lines, string.format('<font color="%s">%s</font>', colorTag(kindColor(card)), card.Name))
				end
			end
		end
	end
	add("Your cards", ev.hand)
	add("The AI's", ev.ai)
	ui.hud.text.Text = table.concat(lines, "\n")
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
	if ui.homeBtn then
		ui.homeBtn.Visible = active
		ui.homeLeft.Text = active and leftText(Halloween.secondsLeft(now)) or ""
	end
	ui.info.Text = string.format("%s left  ·  %s Candy  ·  %d scout", active and leftText(Halloween.secondsLeft(now)) or "Ended", Gui.num(ev.candy or 0), ev.scout or 0)
	if ui.window.root.Visible then
		local T = ui.tabs
		if tab == "Match" then
			for key, c in pairs(T.Match.cards) do
				c.done.Text = (ev.cleared and ev.cleared[key]) and "Cleared today: later clears pay less" or ""
			end
		elseif tab == "Banner" then
			T.Banner.scout.Text = string.format("%d scout points", ev.scout or 0)
			local skins = p.skins or {}
			for _, r in ipairs(T.Banner.rows) do
				local it = r.item
				if it.kind == "Skin" then
					local row = skins[it.key]
					r.have.Text = row and row.copies > 0 and string.format("%d cop%s", row.copies, row.copies == 1 and "y" or "ies") or ""
					r.pick.Visible = true
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
		elseif tab == "Reaper" then
			local R = T.Reaper
			local row = p.skins and p.skins[R.key]
			R.copies.Text = string.format("%d cop%s  ·  %d free to apply", row and row.copies or 0, (row and row.copies or 0) == 1 and "y" or "ies", row and row.free or 0)
			for _, e in ipairs(R.rows) do
				local owned = p.owned and p.owned.Char and p.owned.Char[e.char.Id] == true
				e.frame.Visible = owned == true
				if owned then
					local on = row and row.on and row.on[e.char.Id]
					if on == nil then
						e.state.Text = "Not applied"
						e.actL.Text = "Apply a copy"
						e.act.Visible = (row and row.free or 0) > 0
					else
						e.state.Text = on and "On" or "Off"
						e.state.TextColor3 = on and HW.Skins[R.key].Color or Gui.DIM
						e.actL.Text = on and "Switch off" or "Switch on"
						e.act.Visible = true
					end
				end
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
	-- Home's button, down the right edge (first in the list)
	if kit.extras then
		local b = kit.navItem(kit.extras, kit.iconKey("IconHalloween", "IconStar"), "Halloween", { LayoutOrder = -1 })
		local left = Gui.label(b, { Text = "", display = true, TextSize = 13, TextColor3 = ORANGE, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 60), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		kit.extras.Size = UDim2.fromOffset(kit.extras.Size.X.Offset, kit.extras.Size.Y.Offset + 84)
		kit.onClick(b, function()
			HalloweenMenu.open()
		end)
		ui.homeBtn, ui.homeLeft = b, left
	end
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
			if ui.pick.root.Visible or ui.window.root.Visible or (ui.homeBtn and kit.shown()) then
				HalloweenMenu.refresh()
			end
		end
	end)
	HalloweenMenu.refresh()
end

return HalloweenMenu
