-- The Winter collab's menu (Config.Winter, the Winter module; the owner, 2026-11-15: a Christmas
-- event with Jaja's Volleyball Evolved: "event snowflakes, quests, and a new event
-- gamemode... an exclusive character that can only be recruited from the event currencies"),
-- laid out after The Spike Cross's collab event (event matches, missions, an attendance pass, a
-- banner only the event's coins recruit on, an exchange shop):
--   * a card on Home, under your record (where the tutorial's card sits until it's done): the
--     event's name, its time left, your Snowflakes, and a dot while something waits to be claimed;
--   * the Winter window, four tabs:
--       Match    the Winter Match (Christmas Cards): today's rival, the three difficulties;
--       Quests   attendance along the top, today's three quests, the event's missions;
--       Recruit  the Wild Card banner: Jaja, the gauge that guarantees him, the odds, the last
--                recruit's results;
--       Advent   the advent calendar: 25 doors, today's free, the rest opened with Robux;
--       Shop     what Snowflakes buy;
--       Pass     the Winter Pass: its tiers in a row, a free and a premium reward under each,
--                claimed by clicking them; premium unlocked with Robux (Config.Winter.Pass).
-- Nothing shows unless the event runs (Winter.active: off in a published game until it's switched
-- on; always on in Studio, Config.Winter.StudioPreview). Everything is asked through the Profile
-- remote ("winLogin", "winQuest", "winMission", "winSpin", "winShop") and the Lobby remote
-- ("winter", a difficulty).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Winter = require(Shared.Winter)
local Roster = require(Shared.Roster)
local Spins = require(Shared.Spins)
local Story = require(Shared.Story)
local Bios = require(Shared.Bios)
local Net = require(Shared.Net)
local Assets = require(Shared.Assets)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local WinterMenu = {}
local W = Config.Winter
local SNOW = W.Snow.Name
local ICE = W.Snow.Color
local GREEN = Color3.fromRGB(91, 227, 138)
-- the window's own look (the owner, 2026-11-15: "make this menu more blue and white, christmassy
-- theme, with some stringlights at the top bar menu"): deep winter blue under frost white, no
-- orange anywhere in it
local FROST = Color3.fromRGB(238, 247, 255) -- the white: plates, the lit tab, titles
local FROST_HOT = Color3.fromRGB(190, 228, 255) -- a plate under the pointer
local DEEP_TOP = Color3.fromRGB(30, 72, 150) -- the panel, top
local DEEP = Color3.fromRGB(10, 26, 70) -- the panel, bottom
local ROW = Color3.fromRGB(22, 52, 116) -- cards and rows
local WELL = Color3.fromRGB(8, 22, 60) -- sunk things: a track, a quiet button
local INK = Color3.fromRGB(8, 24, 62) -- text on white
local MIST = Color3.fromRGB(178, 206, 242) -- quiet text on blue
local GOLD_T = Color3.fromRGB(255, 214, 90) -- prices, premium, stars
-- the string lights' bulbs, in turn
local LIGHTS = { Color3.fromRGB(255, 92, 92), Color3.fromRGB(255, 216, 112), Color3.fromRGB(104, 228, 136), Color3.fromRGB(120, 196, 255), Color3.fromRGB(255, 255, 255) }
local mods, kit
local ui = { tabs = {} }
local tab = "Match"
local seenAt, seen = 0, nil -- when the profile last arrived, and its winter view

local function make(...)
	return kit.make(...)
end

local function label(parent, props)
	props.ZIndex = props.ZIndex or 23
	return Gui.label(parent, props)
end

-- The event as the server last sent it: { endsIn, day, dayLeft, ev }, or nil when it isn't running.
local function view()
	local p = kit.profile()
	local w = p and p.winter
	return type(w) == "table" and w or nil
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

-- A grant in a line, Snowflakes first: "+150 Snowflakes, +1 Lucky Spin".
local function grantLine(g)
	local parts = {}
	if (g.Snow or 0) > 0 then
		table.insert(parts, string.format("+%d %s", g.Snow, SNOW))
	end
	local rest = Story.grantText(g)
	if rest ~= "" then
		table.insert(parts, rest)
	end
	if g.Skin then
		table.insert(parts, Winter.rewardText({ Skin = g.Skin }))
	end
	return table.concat(parts, ", ")
end

-- The event's snowflake: our own icon (Assets.Images.IconSnowflake) once its id is in, drawn from
-- three bars until then.
local function snowIcon(parent, size, props)
	local f = make("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	local image = Assets.image("IconSnowflake")
	if image then
		make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = image, ImageColor3 = ICE, ZIndex = f.ZIndex }, f)
		return f
	end
	for i = 0, 2 do
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, math.max(2, math.floor(size * 0.12))), Rotation = i * 60, BackgroundColor3 = ICE, BorderSizePixel = 0, ZIndex = f.ZIndex }, f)
	end
	return f
end

-- A frost-white plate button with dark blue words (the menus' orange plate, in the window's colours).
local function icePlate(parent, props, caption, textSize)
	local b = Gui.plateButton(parent, props, FROST, FROST_HOT)
	b:SetAttribute("Sound", "UIConfirm")
	local l = Gui.label(b, { Text = caption, display = true, weight = Enum.FontWeight.Heavy, TextSize = textSize or 22, TextColor3 = INK, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = b.ZIndex + 3 })
	return b, l
end

-- A card in the window's blue with an icy hairline.
local function iceCard(parent, props)
	local f = make("Frame", { BackgroundColor3 = ROW, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	Gui.corner(f, 8)
	make("UIStroke", { Color = ICE, Thickness = 1, Transparency = 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	return f
end

-- A quiet button (Claim) in the window's colours: the menus' hairline button, blue.
local function iceButton(parent, props, caption, textSize)
	local b, l = kit.hairButton(parent, props, caption, textSize)
	b.BackgroundColor3 = WELL
	b.UIStroke.Color = ICE
	return b, l
end

-- String lights along the top of the window: a wire hung in swags from hook to hook, a bulb
-- every few studs of it in the Christmas colours, each with a soft glow. Returns the bulbs
-- ({ bulb, glow, phase }), which twinkle while the window is up (WinterMenu.init).
local function stringLights(panel, width)
	local f = make("Frame", { Name = "Lights", Position = UDim2.fromOffset(0, -8), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, ZIndex = 30 }, panel)
	local SWAGS, PER, SAG = 10, 4, 9
	local step = width / SWAGS
	local pts = {}
	for sw = 0, SWAGS - 1 do
		table.insert(pts, { x = sw * step, y = 0, hook = true })
		for i = 1, PER do
			local t = i / (PER + 1)
			table.insert(pts, { x = (sw + t) * step, y = SAG * 4 * t * (1 - t) })
		end
	end
	table.insert(pts, { x = width, y = 0, hook = true })
	-- the wire, a short straight piece between each two points
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dy = b.x - a.x, b.y - a.y
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((a.x + b.x) / 2, (a.y + b.y) / 2 + 6), Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 1, 2), Rotation = math.deg(math.atan(dy / dx)), BackgroundColor3 = Color3.fromRGB(4, 12, 34), BorderSizePixel = 0, ZIndex = 30 }, f)
	end
	local glowImage = Assets.id(Assets.Fx.Glow) or ""
	local bulbs = {}
	for _, pt in ipairs(pts) do
		if pt.hook then
			-- a small hook holding the wire up
			local hook = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(pt.x, 6), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = FROST, BorderSizePixel = 0, ZIndex = 31 }, f)
			Gui.round(hook)
		else
			local color = LIGHTS[#bulbs % #LIGHTS + 1]
			local y = pt.y + 6
			make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(pt.x, y), Size = UDim2.fromOffset(6, 4), BackgroundColor3 = Color3.fromRGB(4, 12, 34), BorderSizePixel = 0, ZIndex = 31 }, f)
			local glow = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(pt.x, y + 10), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, Image = glowImage, ImageColor3 = color, ImageTransparency = 0.45, ZIndex = 30 }, f)
			local bulb = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(pt.x, y + 3), Size = UDim2.fromOffset(10, 14), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 32 }, f)
			Gui.round(bulb)
			table.insert(bulbs, { bulb = bulb, glow = glow, phase = #bulbs * 1.7 })
		end
	end
	return bulbs
end

local function sectionTitle(parent, text, x, y, w)
	label(parent, { Text = text, display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = FROST, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 24), ZIndex = 22 })
end

------------------------------------------------------------------------------------------
-- Match
------------------------------------------------------------------------------------------

local function foeText(d)
	local level = d.FoeLevel or 1
	if d.Rivals == false then
		return string.format("Jaja %s, with %s-tier players", level <= 0 and "fresh" or "half trained", d.Bots)
	elseif level <= 0 then
		return "Today's rivals as fresh recruits"
	elseif level < 1 then
		return "Today's rivals half trained"
	end
	return "Today's rivals at full strength"
end

local function buildMatchTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 21 }, body)
	-- today's rival (WinterMenu.refresh fills it in) and how the cards work
	local rival = label(f, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = FROST, RichText = true, Size = UDim2.new(1, 0, 0, 22), ZIndex = 22 })
	label(f, { Text = string.format("Christmas Cards: before every rally a card flips and changes that rally's rules. First to %d; each day's first win on a difficulty pays the most %s.", W.Match.Points, SNOW), TextSize = 15, TextColor3 = MIST, TextWrapped = true, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 22), ZIndex = 22 })
	local cards = {}
	local CW, GAP = 352, 22
	for i, d in ipairs(W.Difficulties) do
		local card = make("Frame", { Position = UDim2.fromOffset((i - 1) * (CW + GAP), 56), Size = UDim2.fromOffset(CW, 440), BackgroundColor3 = ROW, BorderSizePixel = 0, ZIndex = 22 }, f)
		Gui.corner(card, 10)
		make("UIStroke", { Color = d.Color, Thickness = 2, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		local head = make("Frame", { Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = d.Color, BorderSizePixel = 0, ZIndex = 23 }, card)
		Gui.corner(head, 10)
		label(head, { Text = string.upper(d.Name), display = true, weight = Enum.FontWeight.Heavy, TextSize = 34, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
		label(card, { Text = string.format("%s bots", d.Bots), display = true, TextSize = 22, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 82), TextXAlignment = Enum.TextXAlignment.Center })
		label(card, { Text = foeText(d), TextSize = 16, TextColor3 = MIST, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 110), TextXAlignment = Enum.TextXAlignment.Center })
		label(card, { Text = "TODAY'S FIRST WIN", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 152), TextXAlignment = Enum.TextXAlignment.Center })
		label(card, { Text = string.format("+%d %s", d.First, SNOW), display = true, weight = Enum.FontWeight.Heavy, TextSize = 40, TextColor3 = ICE, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 178), TextXAlignment = Enum.TextXAlignment.Center })
		label(card, { Text = string.format("then +%d a win  ·  +%d a loss", d.Repeat, d.Loss), TextSize = 16, TextColor3 = MIST, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 230), TextXAlignment = Enum.TextXAlignment.Center })
		local done = label(card, { Text = "", display = true, TextSize = 18, TextColor3 = GREEN, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 292), TextXAlignment = Enum.TextXAlignment.Center })
		local play, playL = icePlate(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, -36, 0, 64), ZIndex = 23 }, "Play", 24)
		if i == 1 then
			play:SetAttribute("NavFirst", true)
		end
		kit.onClick(play, function()
			Net.get("Lobby"):FireServer("winter", d.Key)
			ui.window.hide()
		end)
		cards[d.Key] = { done = done }
	end
	return { frame = f, cards = cards, rival = rival }
end

------------------------------------------------------------------------------------------
-- Quests: attendance, today's quests, the event's missions
------------------------------------------------------------------------------------------

local DAYS = 7 -- attendance chips in view

local function buildQuestTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local T = { frame = f, days = {}, quests = {}, missions = {} }

	-- attendance: a strip across the top
	local strip = iceCard(f, { Size = UDim2.new(1, 0, 0, 104), ZIndex = 22 })
	label(strip, { Text = "ATTENDANCE", display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, TextColor3 = ICE, Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(180, 26) })
	T.dayLine = label(strip, { Text = "", TextSize = 15, TextColor3 = MIST, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(18, 46), Size = UDim2.fromOffset(176, 44) })
	for i = 1, DAYS do
		local chip = make("Frame", { Position = UDim2.fromOffset(200 + (i - 1) * 100, 14), Size = UDim2.fromOffset(92, 76), BackgroundColor3 = ROW, BorderSizePixel = 0, ZIndex = 23 }, strip)
		Gui.corner(chip, 6)
		local stroke = make("UIStroke", { Color = ICE, Thickness = 2, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
		local day = label(chip, { Text = "", display = true, TextSize = 14, TextColor3 = MIST, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
		local snow = label(chip, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, TextColor3 = ICE, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 32), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
		local state = label(chip, { Text = "", display = true, TextSize = 13, TextColor3 = GREEN, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
		T.days[i] = { chip = chip, stroke = stroke, day = day, snow = snow, state = state }
	end
	local check, checkL = icePlate(strip, { Name = "CheckIn", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(190, 64), ZIndex = 23 }, "Check in", 24)
	check:SetAttribute("NavFirst", true)
	T.check, T.checkL = check, checkL
	-- (once today's is taken the plate goes and this stands in its place)
	T.checked = label(strip, { Text = "Checked in", display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextColor3 = GREEN, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(190, 64), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	kit.onClick(check, function()
		kit.sendProfile("winLogin")
	end)

	-- today's quests, down the left
	sectionTitle(f, "DAILY QUESTS", 0, 118, 260)
	T.reset = label(f, { Text = "", TextSize = 15, TextColor3 = MIST, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(280, 120), Size = UDim2.fromOffset(260, 20), ZIndex = 22 })
	for i = 1, W.Quests.Count do
		local c = iceCard(f, { Position = UDim2.fromOffset(0, 148 + (i - 1) * 88), Size = UDim2.fromOffset(540, 80), ZIndex = 22 })
		local text = label(c, { Text = "", TextSize = 19, TextWrapped = true, Position = UDim2.fromOffset(18, 6), Size = UDim2.fromOffset(280, 68) })
		local pay = label(c, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextColor3 = ICE, Position = UDim2.fromOffset(300, 0), Size = UDim2.fromOffset(100, 80), TextXAlignment = Enum.TextXAlignment.Center })
		local b, bl = iceButton(c, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(112, 46), ZIndex = 23 }, "Claim", 20)
		bl.ZIndex = 24
		local row = { text = text, pay = pay, claim = b, claimL = bl, key = nil }
		kit.onClick(b, function()
			if row.key then
				kit.sendProfile("winQuest", row.key)
			end
		end)
		T.quests[i] = row
	end

	-- the event's missions, down the right
	sectionTitle(f, "EVENT MISSIONS", 562, 118, 300)
	for i, def in ipairs(W.Missions) do
		local c = iceCard(f, { Position = UDim2.fromOffset(562, 148 + (i - 1) * 60), Size = UDim2.fromOffset(562, 54), ZIndex = 22 })
		local text = label(c, { Text = "", TextSize = 17, TextWrapped = true, Position = UDim2.fromOffset(16, 2), Size = UDim2.fromOffset(266, 50) })
		label(c, { Text = grantLine(def.Grant), display = true, TextSize = 15, TextColor3 = ICE, TextWrapped = true, Position = UDim2.fromOffset(288, 2), Size = UDim2.fromOffset(160, 50), TextXAlignment = Enum.TextXAlignment.Center })
		local b, bl = iceButton(c, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(96, 38), ZIndex = 23 }, "Claim", 18)
		bl.ZIndex = 24
		kit.onClick(b, function()
			kit.sendProfile("winMission", def.Key)
		end)
		T.missions[i] = { def = def, text = text, claim = b, claimL = bl }
	end
	return T
end

------------------------------------------------------------------------------------------
-- Recruit: the Wild Card banner
------------------------------------------------------------------------------------------

local RESULTS = 10

local function buildRecruitTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local T = { frame = f, results = {} }
	local B = W.Banner
	local star = Roster.get("jaja")

	-- the featured card: the tier as a huge faint watermark (no portrait yet), who he is, the gauge
	local card = iceCard(f, { Size = UDim2.fromOffset(520, 510), ClipsDescendants = true, ZIndex = 22 })
	card.UIStroke.Color = ICE
	card.UIStroke.Transparency = 0.35
	Gui.halftone(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.6, 0.6), ImageColor3 = ICE, ImageTransparency = 0.92, ZIndex = 22 })
	label(card, { Text = star and star.Tier or "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 250, TextTransparency = 0.9, TextColor3 = ICE, TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Top, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -30), Size = UDim2.fromOffset(340, 250), ZIndex = 22 })
	label(card, { Text = string.upper(B.Name) .. " BANNER", display = true, TextSize = 16, TextColor3 = ICE, Position = UDim2.fromOffset(20, 16), Size = UDim2.fromOffset(300, 18) })
	label(card, { Text = star and star.Name or "?", display = true, weight = Enum.FontWeight.Heavy, TextSize = 66, Position = UDim2.fromOffset(18, 34), Size = UDim2.fromOffset(330, 70) })
	local tierPlate = Gui.plate(card, { Position = UDim2.fromOffset(20, 110), Size = UDim2.fromOffset(78, 32), ZIndex = 23 }, star and Config.TierColors[star.Tier] or ICE)
	label(tierPlate, { Text = star and star.Tier or "", display = true, TextSize = 22, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
	local ability = star and star.Ability and Config.Abilities[star.Ability]
	label(card, { Text = string.format("Wing Spiker  ·  %s  ·  from %s", ability and ability.Name or "Joker", W.Partner), TextSize = 16, weight = Enum.FontWeight.Medium, Position = UDim2.fromOffset(110, 114), Size = UDim2.fromOffset(396, 22) })
	label(card, { Text = (star and Bios[star.Id]) or "",TextSize = 15, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTransparency = 0.1, Position = UDim2.fromOffset(20, 156), Size = UDim2.fromOffset(480, 96) })
	label(card, { Text = string.format("Only %s recruit here. Jaja stays yours after the event.", SNOW), TextSize = 14, TextColor3 = MIST, Position = UDim2.fromOffset(20, 256), Size = UDim2.fromOffset(480, 18) })
	-- the gauge: recruits without him, filling toward the guarantee
	T.gauge = label(card, { Text = "", display = true, TextSize = 20, Position = UDim2.fromOffset(20, 296), Size = UDim2.fromOffset(480, 24) })
	local track = make("Frame", { Position = UDim2.fromOffset(20, 326), Size = UDim2.fromOffset(480, 14), BackgroundColor3 = WELL, BorderSizePixel = 0, ZIndex = 23 }, card)
	T.fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = FROST, BorderSizePixel = 0, ZIndex = 24 }, track)
	T.owned = label(card, { Text = "", display = true, TextSize = 16, TextColor3 = GREEN, Position = UDim2.fromOffset(20, 346), Size = UDim2.fromOffset(480, 20) })
	T.buttons = {}
	for i, n in ipairs({ 1, 10 }) do
		local b, l = icePlate(card, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20 + (i - 1) * 246, 1, -20), Size = UDim2.fromOffset(234, 80), ZIndex = 23 }, "", 21)
		l.Text = string.format("Recruit x%d\n%s %s", n, Gui.num(Winter.cost(n)), SNOW)
		if i == 1 then
			b:SetAttribute("NavFirst", true)
		end
		kit.onClick(b, function()
			kit.sendProfile("winSpin", n)
		end)
		T.buttons[i] = { button = b, label = l, cost = Winter.cost(n) }
	end

	-- the odds, and under them what the last recruit gave
	sectionTitle(f, "ODDS", 544, 0, 200)
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(544, 30), Size = UDim2.fromOffset(580, 236), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.DIM, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, f)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i, row in ipairs(Winter.bannerTable()) do
		local it = row.item
		local r = make("Frame", { Size = UDim2.new(1, -10, 0, 34), BackgroundColor3 = ROW, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 22 }, list)
		Gui.corner(r, 6)
		make("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = Spins.rarityColor(it.rarity), BorderSizePixel = 0, ZIndex = 23 }, r)
		label(r, { Text = it.name, display = true, TextSize = 19, Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(300, 34) })
		label(r, { Text = it.rarity, TextSize = 14, TextColor3 = Spins.rarityColor(it.rarity), Position = UDim2.fromOffset(320, 0), Size = UDim2.fromOffset(120, 34) })
		label(r, { Text = string.format("%.1f%%", row.chance * 100), display = true, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.fromOffset(90, 34) })
	end
	sectionTitle(f, "LAST RECRUIT", 544, 282, 300)
	T.none = label(f, { Text = "Nothing yet: your recruits show here.", TextSize = 15, TextColor3 = MIST, Position = UDim2.fromOffset(544, 312), Size = UDim2.fromOffset(560, 22), ZIndex = 22 })
	for i = 1, RESULTS do
		local col, rowI = (i - 1) % 2, math.floor((i - 1) / 2)
		local r = make("Frame", { Position = UDim2.fromOffset(544 + col * 292, 312 + rowI * 38), Size = UDim2.fromOffset(284, 32), BackgroundColor3 = ROW, BorderSizePixel = 0, Visible = false, ZIndex = 22 }, f)
		Gui.corner(r, 6)
		local bar = make("Frame", { Size = UDim2.new(0, 6, 1, 0), BorderSizePixel = 0, ZIndex = 23 }, r)
		local name = label(r, { Text = "", display = true, TextSize = 17, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(170, 32) })
		local note = label(r, { Text = "", TextSize = 13, TextColor3 = MIST, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(96, 32) })
		T.results[i] = { frame = r, bar = bar, name = name, note = note }
	end
	return T
end

-- A recruit's results into the Recruit tab, and the recruit sequence over the top of it.
local function showReveal(r)
	local T = ui.tabs.Recruit
	local items = type(r.items) == "table" and r.items or {}
	-- (the banner's last recruit, only for the banner's own: an advent door or a skin from a mission
	-- or the shop plays the sequence but leaves it)
	if not r.tab then
		T.none.Visible = #items == 0
	end
	for i, row in ipairs(r.tab and {} or T.results) do
		local it = items[i]
		row.frame.Visible = it ~= nil
		if it then
			local color = Spins.rarityColor(it.rarity or "Rare")
			row.bar.BackgroundColor3 = color
			row.name.Text = it.name or it.key or "?"
			row.name.TextColor3 = it.kind == "Char" and color or Gui.CHALK
			row.note.Text = (it.frag and string.format("+1 %s Fragment", it.frag)) or (it.snow and string.format("+%d %s", it.snow, SNOW)) or (it.kind == "Char" and "NEW" or "")
		end
	end
	-- the recruit itself: the usual sequence in the winter's look (blue, snow falling; Jaja keeps the
	-- Mythic red), then back to the banner
	if #items > 0 and kit.playRecruit and kit.shown() then
		local list = {}
		for i, it in ipairs(items) do
			list[i] = { win = true, kind = it.kind, key = it.key, name = it.name, rarity = it.rarity, dup = it.dup, frag = it.frag, snow = it.snow }
		end
		ui.window.root.Visible = false
		kit.playRecruit({
			banner = "Winter",
			theme = "Winter",
			count = #list,
			items = list,
			snow = r.snow or 0,
			after = function()
				WinterMenu.open(r.tab or "Recruit") -- back to where it came from (the banner, Advent...)
			end,
		})
	end
end

------------------------------------------------------------------------------------------
-- Shop
------------------------------------------------------------------------------------------

local function buildShopTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	-- Snowflakes for Robux (Config.Winter.SnowPacks), across the top
	label(f, { Text = "GET " .. string.upper(SNOW), display = true, weight = Enum.FontWeight.Heavy, TextSize = 18, TextColor3 = ICE, Size = UDim2.fromOffset(200, 22), ZIndex = 22 })
	local packs = W.SnowPacks or {}
	local PW = 200
	for i, pack in ipairs(packs) do
		local b = make("TextButton", { Position = UDim2.fromOffset((i - 1) * (PW + 12), 26), Size = UDim2.fromOffset(PW, 62), BackgroundColor3 = ROW, BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 22 }, f)
		Gui.corner(b, 8)
		make("UIStroke", { Color = ICE, Thickness = 2, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		snowIcon(b, 28, { Position = UDim2.fromOffset(10, 17) })
		label(b, { Text = pack.Label or pack.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextColor3 = FROST, Position = UDim2.fromOffset(44, 6), Size = UDim2.fromOffset(PW - 50, 28) })
		label(b, { Text = (pack.Id ~= 0) and string.format("R$ %d", pack.Price) or "free in Studio", TextSize = 16, TextColor3 = GOLD_T, Position = UDim2.fromOffset(44, 34), Size = UDim2.fromOffset(PW - 50, 20) })
		-- and for someone else
		if pack.Gift then
			local g = iceButton(b, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(58, 30), ZIndex = 24 }, "Gift", 14)
			kit.onClick(g, function()
				kit.openGift("Snow", i)
			end)
		end
		kit.onClick(b, function()
			local p = kit.profile()
			if pack.Id ~= 0 then
				pcall(function()
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, pack.Id)
				end)
			elseif p and p.studio then
				Net.get("Profile"):FireServer("buy", i, "Snow")
			end
		end)
	end
	label(f, { Text = string.format("%s buy these while the event runs.", SNOW), TextSize = 17, TextColor3 = MIST, TextWrapped = true, Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 24), ZIndex = 22 })
	local rows = {}
	local scroll = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 128), Size = UDim2.new(1, 0, 1, -128), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = ICE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, f)
	for i, row in ipairs(Winter.shop()) do
		local r = make("Frame", { Position = UDim2.fromOffset(0, (i - 1) * 64), Size = UDim2.new(1, -10, 0, 56), BackgroundColor3 = ROW, BorderSizePixel = 0, ZIndex = 22 }, scroll)
		Gui.corner(r, 6)
		label(r, { Text = row.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(480, 56) })
		local left = label(r, { Text = "", TextSize = 16, TextColor3 = MIST, Position = UDim2.fromOffset(520, 0), Size = UDim2.fromOffset(240, 56) })
		local buy, buyL = icePlate(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(260, 44), ZIndex = 23 }, string.format("Buy  ·  %d %s", row.Price, SNOW), 19)
		kit.onClick(buy, function()
			kit.sendProfile("winShop", row.Key)
		end)
		rows[i] = { row = row, left = left, buy = buy, buyL = buyL }
	end
	return { frame = f, rows = rows }
end

------------------------------------------------------------------------------------------
-- Pass: the Winter Pass's tiers
------------------------------------------------------------------------------------------

local PASS = W.Pass
local COL_W, CELL_H = 150, 150

-- What a reward is, in a word for its tag, and the colour it's shown in.
local function rewardKind(r)
	if r.Snow then
		return "SNOWFLAKES", ICE
	elseif r.Gold then
		return "GOLD", Color3.fromRGB(255, 206, 70)
	elseif r.VP then
		return "VP", Color3.fromRGB(120, 230, 160)
	elseif r.Lucky then
		return "LUCKY SPINS", Color3.fromRGB(255, 150, 220)
	elseif r.Card then
		return "CARD  ·  TITLE", Color3.fromRGB(255, 120, 120)
	elseif r.Skin then
		return "MYTHIC SKIN", Config.Rarity.Colors.Mythic or Color3.fromRGB(255, 60, 60)
	elseif r.Room then
		return "HOME ROOM", Color3.fromRGB(255, 196, 60)
	elseif r.Item then
		local it = Spins.item(r.Item.Kind, r.Item.Key)
		local word = ({ Pose = "EMOTE", Ball = "BALL" })[r.Item.Kind] or string.upper(r.Item.Kind)
		return word, it and Spins.rarityColor(it.Rarity) or FROST
	end
	return "", FROST
end

-- The premium track's product (Config.Winter.Pass.Packs[1]).
local function buyPremium()
	local pack = PASS.Packs[1]
	local p = kit.profile()
	if pack and pack.Id ~= 0 then
		pcall(function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, pack.Id)
		end)
	elseif pack and p and p.studio then
		Net.get("Profile"):FireServer("buy", 1, "WinterPass") -- (free in Studio while there's no product)
	else
		kit.toast("The " .. PASS.Name .. " goes on sale soon.")
	end
end

-- A tier skip (Config.Winter.Pass.Packs[i], PassTiers): its product, or free in Studio while it
-- has none.
local function buySkip(i)
	local pack = PASS.Packs[i]
	local p = kit.profile()
	if pack and pack.Id ~= 0 then
		pcall(function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, pack.Id)
		end)
	elseif pack and p and p.studio then
		Net.get("Profile"):FireServer("buy", i, "WinterPass")
	end
end

-- A reward's picture, `size` across, centred at (cx, cy) in `parent`: the game's own VP, Gold and
-- recruit icons, the Snowflake; a glossy ball in its colour; a star for an emote, card or skin.
local function passIcon(parent, r, color, cx, cy, size)
	local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ZIndex = 24 }, parent)
	local icon = nil
	if r.VP then
		icon = Gui.icon.vp(holder, size)
	elseif r.Gold then
		icon = Gui.icon.gold(holder, size)
	elseif r.Lucky then
		icon = Gui.icon.recruit(holder, size, color)
	elseif r.Snow then
		local img = Assets.image("IconSnowflake")
		if img then
			make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = img, ImageColor3 = Color3.fromRGB(238, 247, 255), ZIndex = 25 }, holder)
		end
	elseif r.Item and r.Item.Kind == "Ball" then
		local ball = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.86), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 25 }, holder)
		Gui.round(ball)
		make("UIGradient", { Rotation = 50, Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.6), color:Lerp(Color3.new(0, 0, 0), 0.35)) }, ball)
		local shine = make("Frame", { Position = UDim2.fromScale(0.22, 0.16), Size = UDim2.fromScale(0.26, 0.2), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.25, BorderSizePixel = 0, Rotation = -30, ZIndex = 26 }, ball)
		Gui.round(shine)
	elseif r.Item and (r.Item.Kind == "Color" or r.Item.Kind == "Trail") then
		-- a spike colour's bands on a swatch, a trail's colours as a streak
		local it = Spins.item(r.Item.Kind, r.Item.Key)
		local cols = it and (it.Trail or it.Solid) or { color }
		local keys = {}
		for i, c in ipairs(cols) do
			table.insert(keys, ColorSequenceKeypoint.new(#cols == 1 and 0 or (i - 1) / (#cols - 1), c))
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, cols[1]))
		end
		local trail = r.Item.Kind == "Trail"
		local sw = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = trail and UDim2.fromScale(1.3, 0.34) or UDim2.fromScale(0.86, 0.86), Rotation = trail and -24 or 0, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 25 }, holder)
		Gui.corner(sw, trail and 99 or 8)
		make("UIGradient", { Rotation = trail and 0 or 90, Color = ColorSequence.new(keys), Transparency = trail and NumberSequence.new(0.7, 0) or nil }, sw)
		make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = 0.5 }, sw)
	else
		local img = Assets.image("IconStar")
		if img then
			make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = img, ImageColor3 = color, ZIndex = 25 }, holder)
		end
	end
	if icon then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		for _, d in ipairs(icon:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = 25
			end
		end
	end
	return holder
end

local function passCell(parent, x, y, tier, track)
	local r = Winter.passReward(tier, track)
	local kindWord, color = rewardKind(r or {})
	local b = make("TextButton", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(COL_W - 12, CELL_H), BackgroundColor3 = track == "prem" and Color3.fromRGB(40, 30, 70) or ROW, BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 23 }, parent)
	Gui.corner(b, 8)
	local stroke = make("UIStroke", { Color = color, Thickness = 2, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local band = make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 24 }, b)
	Gui.corner(band, 8)
	label(band, { Text = kindWord, display = true, weight = Enum.FontWeight.Heavy, TextSize = 13, TextColor3 = INK, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
	if r then
		passIcon(b, r, color, (COL_W - 12) / 2, 54, 40)
	end
	local name = label(b, { Text = r and Winter.rewardText(r) or "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 16, TextWrapped = true, Position = UDim2.fromOffset(6, 76), Size = UDim2.new(1, -12, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 24 })
	local state = label(b, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 16, Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
	kit.onClick(b, function()
		local p = kit.profile()
		local ev = p and p.winter and p.winter.ev
		if track == "prem" and ev and not (ev.pass and ev.pass.premium) then
			buyPremium()
			return
		end
		kit.sendProfile("winPass", tier, track)
	end)
	return { button = b, stroke = stroke, name = name, state = state, tier = tier, track = track, color = color }
end

local function buildPassTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local T = { frame = f, cells = {}, chips = {} }
	-- the head: the tier, the XP bar, premium, claim all
	T.tier = label(f, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextColor3 = FROST, Size = UDim2.fromOffset(300, 34), ZIndex = 22 })
	local track = make("Frame", { Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(420, 14), BackgroundColor3 = WELL, BorderSizePixel = 0, ZIndex = 22 }, f)
	Gui.corner(track, 7)
	T.fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = ICE, BorderSizePixel = 0, ZIndex = 23 }, track)
	Gui.corner(T.fill, 7)
	-- (the head's row, left to right: the tier and its bar (0-420), Skip tiers, Gift, Unlock Premium,
	-- Claim all, each clear of the next: the Gift button once sat over Premium)
	T.xp = label(f, { Text = "", TextSize = 15, TextColor3 = MIST, Position = UDim2.fromOffset(0, 60), Size = UDim2.fromOffset(420, 20), ZIndex = 22 })
	T.premium, T.premiumL = icePlate(f, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -188, 0, 4), Size = UDim2.fromOffset(290, 56), ZIndex = 23 }, "Unlock Premium", 20)
	kit.onClick(T.premium, buyPremium)
	T.premiumTag = label(f, { Text = "PREMIUM UNLOCKED", display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, TextColor3 = GOLD_T, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -188, 0, 18), Size = UDim2.fromOffset(290, 28), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 23 })
	T.all, T.allL = iceButton(f, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(180, 56), ZIndex = 23 }, "Claim all", 20)
	-- tier skips: a button that opens the packs (Config.Winter.Pass.Packs with PassTiers)
	T.skip, T.skipL = iceButton(f, { Position = UDim2.fromOffset(430, 4), Size = UDim2.fromOffset(110, 56), ZIndex = 23 }, "Skip tiers", 18)
	T.skipMenu = make("Frame", { Position = UDim2.fromOffset(430, 66), Size = UDim2.fromOffset(300, 16), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(12, 26, 60), BorderSizePixel = 0, Visible = false, ZIndex = 40 }, f)
	Gui.corner(T.skipMenu, 10)
	make("UIStroke", { Color = ICE, Thickness = 2, Transparency = 0.2 }, T.skipMenu)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, T.skipMenu)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, T.skipMenu)
	T.skips = {}
	for i, pack in ipairs(PASS.Packs) do
		if tonumber(pack.PassTiers) then
			local b, l = icePlate(T.skipMenu, { Size = UDim2.new(1, 0, 0, 52), LayoutOrder = i, ZIndex = 41 }, "", 20)
			kit.onClick(b, function()
				T.skipMenu.Visible = false
				buySkip(i)
			end)
			table.insert(T.skips, { button = b, label = l, pack = pack })
		end
	end
	kit.onClick(T.skip, function()
		T.skipMenu.Visible = not T.skipMenu.Visible
		T.giftMenu.Visible = false
	end)
	-- gifting (the owner, 2026-11-18: "add gifting"): the Pass and its skips for someone else
	T.gift, T.giftL = iceButton(f, { Position = UDim2.fromOffset(548, 4), Size = UDim2.fromOffset(90, 56), ZIndex = 23 }, "Gift", 18)
	T.giftMenu = make("Frame", { Position = UDim2.fromOffset(548, 66), Size = UDim2.fromOffset(300, 16), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(12, 26, 60), BorderSizePixel = 0, Visible = false, ZIndex = 40 }, f)
	Gui.corner(T.giftMenu, 10)
	make("UIStroke", { Color = ICE, Thickness = 2, Transparency = 0.2 }, T.giftMenu)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, T.giftMenu)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, T.giftMenu)
	for i, pack in ipairs(PASS.Packs) do
		if pack.Gift then
			local b = icePlate(T.giftMenu, { Size = UDim2.new(1, 0, 0, 52), LayoutOrder = i, ZIndex = 41 }, string.format("%s  ·  R$ %d", pack.Name, tonumber(pack.Price) or PASS.Price), 19)
			kit.onClick(b, function()
				T.giftMenu.Visible = false
				kit.openGift("WinterPass", i)
			end)
		end
	end
	kit.onClick(T.gift, function()
		T.giftMenu.Visible = not T.giftMenu.Visible
		T.skipMenu.Visible = false
	end)
	kit.onClick(T.all, function()
		kit.sendProfile("winPass", "all")
	end)
	-- the rows' names
	label(f, { Text = "FREE", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = FROST, Position = UDim2.fromOffset(0, 168), Size = UDim2.fromOffset(90, 24), ZIndex = 22 })
	label(f, { Text = "PREMIUM", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = GOLD_T, Position = UDim2.fromOffset(0, 330), Size = UDim2.fromOffset(90, 24), ZIndex = 22 })
	-- the tiers, side by side, scrolling sideways
	local sc = make("ScrollingFrame", { Position = UDim2.fromOffset(96, 92), Size = UDim2.new(1, -96, 1, -92), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.fromOffset(PASS.Tiers * COL_W + 12, 0), ScrollBarThickness = 8, ScrollBarImageColor3 = ICE, ElasticBehavior = Enum.ElasticBehavior.Never, ZIndex = 22 }, f)
	T.scroll = sc
	-- the line through the tier numbers, filled to the tier reached
	local line = make("Frame", { Position = UDim2.fromOffset(COL_W / 2, 18), Size = UDim2.fromOffset((PASS.Tiers - 1) * COL_W, 4), BackgroundColor3 = WELL, BorderSizePixel = 0, ZIndex = 22 }, sc)
	T.lineFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = ICE, BorderSizePixel = 0, ZIndex = 23 }, line)
	for t = 1, PASS.Tiers do
		local x = (t - 1) * COL_W
		local chip = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x + COL_W / 2 - 6, 2), Size = UDim2.fromOffset(40, 36), BackgroundColor3 = WELL, BorderSizePixel = 0, ZIndex = 24 }, sc)
		Gui.corner(chip, 8)
		local n = label(chip, { Text = tostring(t), display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = MIST, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
		T.chips[t] = { chip = chip, n = n }
		T.cells[#T.cells + 1] = passCell(sc, x, 48, t, "free")
		T.cells[#T.cells + 1] = passCell(sc, x, 48 + CELL_H + 12, t, "prem")
	end
	return T
end

local function refreshPass(ev, p)
	local T = ui.tabs.Pass
	local tier, into, need = Winter.passTier(ev)
	local P = ev.pass or {}
	T.tier.Text = string.format("TIER %d / %d", tier, PASS.Tiers)
	T.fill.Size = UDim2.fromScale(need > 0 and into / need or 1, 1)
	T.xp.Text = need > 0 and string.format("%d / %d XP to tier %d  ·  play matches, Winter Matches and quests", into, need, tier + 1) or "Every tier reached!"
	T.premium.Visible = not P.premium
	T.premiumTag.Visible = P.premium == true
	local pack = PASS.Packs[1]
	T.premiumL.Text = (pack and pack.Id ~= 0) and string.format("Unlock Premium  ·  R$ %d", PASS.Price) or ((p and p.studio) and "Unlock Premium (free in Studio)" or "Premium: soon")
	-- the skips that still fit under the last tier (none at the top)
	local left = PASS.Tiers - tier
	T.skip.Visible = left > 0
	if left <= 0 then
		T.skipMenu.Visible = false
	end
	for _, sk in ipairs(T.skips) do
		local n = tonumber(sk.pack.PassTiers) or 0
		sk.button.Visible = n <= left
		local price = sk.pack.Id ~= 0 and string.format("R$ %d", tonumber(sk.pack.Price) or 0) or ((p and p.studio) and "free in Studio" or "soon")
		sk.label.Text = string.format("%s  ·  %s", sk.pack.Name, price)
	end
	local claimable = #Winter.passClaimable(ev)
	T.allL.Text = claimable > 0 and string.format("Claim all (%d)", claimable) or "Claim all"
	Gui.enable(T.all, T.allL, claimable > 0)
	T.lineFill.Size = UDim2.fromScale(math.clamp((tier - 1) / math.max(1, PASS.Tiers - 1), 0, 1), 1)
	for t, c in ipairs(T.chips) do
		local reached = t <= tier
		c.chip.BackgroundColor3 = reached and FROST or WELL
		c.n.TextColor3 = reached and INK or MIST
	end
	for _, c in ipairs(T.cells) do
		local ok, why = Winter.canClaimPass(ev, c.tier, c.track)
		local claimed = why == "claimed"
		c.stroke.Transparency = ok and 0 or 0.6
		c.stroke.Thickness = ok and 3 or 2
		c.button.BackgroundTransparency = (claimed or why == "tier") and 0.45 or 0
		c.name.TextTransparency = claimed and 0.5 or 0
		if ok then
			c.state.Text = "CLAIM"
			c.state.TextColor3 = FROST
		elseif claimed then
			c.state.Text = "CLAIMED"
			c.state.TextColor3 = GREEN
		elseif why == "locked" then
			c.state.Text = "PREMIUM"
			c.state.TextColor3 = GOLD_T
		else
			c.state.Text = "TIER " .. c.tier
			c.state.TextColor3 = MIST
		end
	end
	ui.passDot.Visible = claimable > 0
end

------------------------------------------------------------------------------------------
-- Advent: the calendar's doors (Config.Winter.Advent)
-- (the owner, 2026-11-18: "really work on this presentation its pretty ugly"): the doors are
-- wrapped presents of different sizes scattered like a real advent calendar's, each in its own
-- paper with a ribbon, a bow and a gift tag for its number; door 25 a big gold present whose prize
-- stays a mystery. An open door is the box open with its prize inside. The door picked shows on
-- the right with a live preview: the ball turning, the card itself, a colour's spike streak, a
-- trail's things drifting off a streak, a jump's bells.
------------------------------------------------------------------------------------------

local ADV = W.Advent
local BallSkins = require(script.Parent.BallSkins)
local UNIT_W, UNIT_H, GAP = 104, 84, 6
-- where each door sits: { door, column, row, columns wide, rows tall } (numbers scattered)
local LAYOUT = {
	{ 7, 0, 0, 1, 1 }, { 18, 1, 0, 1, 1 }, { 12, 2, 0, 2, 1 }, { 3, 4, 0, 1, 1 }, { 21, 5, 0, 1, 1 },
	{ 14, 0, 1, 1, 1 }, { 1, 1, 1, 1, 1 }, { 9, 2, 1, 1, 1 }, { 22, 3, 1, 1, 1 }, { 25, 4, 1, 2, 2 },
	{ 5, 0, 2, 1, 1 }, { 16, 1, 2, 1, 1 }, { 24, 2, 2, 2, 1 },
	{ 11, 0, 3, 1, 1 }, { 20, 1, 3, 1, 1 }, { 2, 2, 3, 1, 1 }, { 17, 3, 3, 1, 1 }, { 8, 4, 3, 1, 1 }, { 13, 5, 3, 1, 1 },
	{ 23, 0, 4, 1, 1 }, { 4, 1, 4, 1, 1 }, { 19, 2, 4, 1, 1 }, { 10, 3, 4, 1, 1 }, { 6, 4, 4, 1, 1 }, { 15, 5, 4, 1, 1 },
}
-- wrapping papers, each with its ribbon
local PAPERS = {
	{ Color3.fromRGB(196, 28, 44), Color3.fromRGB(255, 214, 90) }, -- red, gold ribbon
	{ Color3.fromRGB(22, 120, 62), Color3.fromRGB(226, 36, 52) }, -- green, red ribbon
	{ Color3.fromRGB(236, 240, 250), Color3.fromRGB(214, 30, 44) }, -- white, red ribbon
	{ Color3.fromRGB(42, 92, 196), Color3.fromRGB(240, 246, 255) }, -- blue, white ribbon
	{ Color3.fromRGB(232, 172, 42), Color3.fromRGB(150, 16, 32) }, -- gold, deep red ribbon
	{ Color3.fromRGB(122, 40, 150), Color3.fromRGB(255, 214, 90) }, -- plum, gold ribbon
}
local GOLD_PAPER = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(196, 20, 40) }
-- what each trail sheds (its preview), and a line on each kind
local TRAIL_SPRITE = { Starlight = "Sparkle", Holly = "HollyLeaf", CandyCanes = "CandyCane", Gingerbread = "GingerMan", SleighBells = "Bell", Snowfall = "Snowflake", Icicle = "Icicle" }
local KIND_LINE = {
	Color = "A spike colour: your spikes and their streak in these bands.",
	Trail = "A trail: these fly off the ball behind your spikes, in your own spike colour.",
	Ball = "A ball skin: the ball wears it whenever you serve.",
	Jump = "A jump effect: gold bells spring up round you and ring.",
	Card = "A player card: your title in the matchup intro and when you score.",
	Skin = "A Mythic skin, with its character.",
}

local function paperOf(d)
	if d == ADV.Doors then
		return GOLD_PAPER
	end
	return PAPERS[(d * 5) % #PAPERS + 1]
end

-- The door's prize as shown: the Item when it has one (a card alone otherwise), a skin first.
local function doorShown(r)
	if type(r) ~= "table" then
		return {}
	end
	return (r.Skin and { Skin = r.Skin }) or (r.Item and { Item = r.Item }) or r
end

-- Whether a door's prize is still hidden: shut and its day not come yet (the owner, 2026-11-18:
-- "dont reveal any gifts until the day comes i think thats smarter"); door 25 says it's a Mythic.
local function mystery(d, ev)
	return not Winter.adventOpen(ev, d) and Winter.adventToday(os.time()) < d
end

-- Opens door `door`: today's free, any other shut one with Robux (picked first, so the purchase
-- opens that one).
local function openDoor(door, state)
	if state == "today" then
		kit.sendProfile("winAdvent", door)
		return
	end
	if state ~= "missed" and state ~= "ahead" then
		return
	end
	kit.sendProfile("winAdventPick", door)
	local p = kit.profile()
	if ADV.Product.Id ~= 0 then
		pcall(function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, ADV.Product.Id)
		end)
	elseif p and p.studio then
		task.delay(0.3, function()
			Net.get("Profile"):FireServer("buy", 1, "Advent")
		end)
	else
		kit.toast("Advent doors go on sale soon.")
	end
end

-- A wrapped present filling `b`: its paper (with a faint print), the ribbon both ways, a bow where
-- they cross. Returns the pieces that hide when it's opened.
local function wrap(b, paper, big)
	local bits = {}
	local function add(o)
		table.insert(bits, o)
		return o
	end
	add(Gui.halftone(b, { Size = UDim2.fromScale(1, 1), ImageColor3 = Color3.new(1, 1, 1), ImageTransparency = 0.88, ZIndex = 24 }))
	add(make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 200)) }, b))
	local rw = big and 18 or 12
	local crossY = 0.34
	add(make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, rw, 1, 0), BackgroundColor3 = paper[2], BorderSizePixel = 0, ZIndex = 25 }, b))
	add(make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, crossY), Size = UDim2.new(1, 0, 0, rw), BackgroundColor3 = paper[2], BorderSizePixel = 0, ZIndex = 25 }, b))
	-- the bow: two loops and two tails round a knot
	local bow = add(make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, crossY), Size = UDim2.fromOffset(big and 64 or 40, big and 40 or 26), BackgroundTransparency = 1, ZIndex = 26 }, b))
	for _, side in ipairs({ -1, 1 }) do
		local loop = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * (big and 16 or 10), 0.42, 0), Size = UDim2.fromScale(0.46, 0.62), Rotation = side * 22, BackgroundColor3 = paper[2], BorderSizePixel = 0, ZIndex = 26 }, bow)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, loop)
		make("UIStroke", { Color = paper[2]:Lerp(Color3.new(0, 0, 0), 0.35), Thickness = 1.5 }, loop)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, side * (big and 8 or 5), 0.55, 0), Size = UDim2.new(0, big and 8 or 5, 0.7, 0), Rotation = side * -24, BackgroundColor3 = paper[2], BorderSizePixel = 0, ZIndex = 25 }, bow)
	end
	local knot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(big and 16 or 11, big and 16 or 11), BackgroundColor3 = paper[2]:Lerp(Color3.new(0, 0, 0), 0.2), BorderSizePixel = 0, ZIndex = 27 }, bow)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, knot)
	return bits
end

local function buildAdventTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local T = { frame = f, doors = {}, pick = nil, sprites = {}, t = 0 }
	-- the head: the title, how many are open (a bar of 25 ticks), when the next free door opens
	label(f, { Text = "ADVENT CALENDAR", display = true, weight = Enum.FontWeight.Heavy, TextSize = 26, TextColor3 = FROST, Size = UDim2.fromOffset(300, 30), ZIndex = 22 })
	T.line = label(f, { Text = "", TextSize = 15, TextColor3 = MIST, Position = UDim2.fromOffset(0, 32), Size = UDim2.fromOffset(660, 18), ZIndex = 22 })
	T.ticks = {}
	for d = 1, ADV.Doors do
		local tick = make("Frame", { Position = UDim2.fromOffset(262 + (d - 1) * 12, 9), Size = UDim2.fromOffset(9, 14), BackgroundColor3 = WELL, BorderSizePixel = 0, ZIndex = 22 }, f)
		Gui.corner(tick, 3)
		T.ticks[d] = tick
	end
	T.count = label(f, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 18, TextColor3 = GOLD_T, Position = UDim2.fromOffset(262 + ADV.Doors * 12 + 8, 4), Size = UDim2.fromOffset(70, 24), ZIndex = 22 })
	-- the doors
	local grid = make("Frame", { Position = UDim2.fromOffset(0, 58), Size = UDim2.fromOffset(6 * UNIT_W + 5 * GAP, 5 * UNIT_H + 4 * GAP), BackgroundTransparency = 1, ZIndex = 22 }, f)
	for _, L in ipairs(LAYOUT) do
		local d, cx, cy, cw, ch = L[1], L[2], L[3], L[4], L[5]
		local big = cw > 1 and ch > 1
		local paper = paperOf(d)
		local r = Winter.adventReward(d)
		local kindWord, color = rewardKind(doorShown(r))
		local b = make("TextButton", { Name = "Door" .. d, Position = UDim2.fromOffset(cx * (UNIT_W + GAP), cy * (UNIT_H + GAP)), Size = UDim2.fromOffset(cw * UNIT_W + (cw - 1) * GAP, ch * UNIT_H + (ch - 1) * GAP), BackgroundColor3 = paper[1], BorderSizePixel = 0, AutoButtonColor = false, Text = "", ClipsDescendants = true, ZIndex = 23 }, grid)
		Gui.corner(b, 6)
		local stroke = make("UIStroke", { Color = Color3.fromRGB(8, 18, 44), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local wrapped = wrap(b, paper, big)
		-- the gift tag with the number, bottom left (paper white, the number in ink)
		local tag = make("Frame", { Position = UDim2.new(0, 6, 1, big and -64 or -40), Size = UDim2.fromOffset(big and 68 or 44, big and 56 or 34), BackgroundColor3 = Color3.fromRGB(252, 248, 236), BorderSizePixel = 0, Rotation = -6, ZIndex = 28 }, b)
		Gui.corner(tag, 5)
		make("UIStroke", { Color = Color3.fromRGB(60, 40, 20), Thickness = 1.5 }, tag)
		label(tag, { Text = tostring(d), display = true, weight = Enum.FontWeight.Heavy, TextSize = big and 44 or 26, TextColor3 = Color3.fromRGB(150, 14, 30), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 29 })
		table.insert(wrapped, tag)
		-- door 25's mystery mark: a big "?" glowing on the paper
		local q = nil
		if ADV.Mystery and ADV.Mystery[d] then
			q = label(b, { Text = "?", display = true, weight = Enum.FontWeight.Heavy, TextSize = 120, TextColor3 = Color3.fromRGB(255, 250, 230), TextStrokeTransparency = 0.3, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.62, 0), Size = UDim2.fromOffset(90, 130), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 28 })
			table.insert(wrapped, q)
		end
		-- a sash across the corner: TODAY, MISSED, or the day it opens
		local sash = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -22, 0, 18), Size = UDim2.fromOffset(110, 18), Rotation = 38, BackgroundColor3 = GOLD_T, BorderSizePixel = 0, Visible = false, ZIndex = 30 }, b)
		local sashL = label(sash, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 12, TextColor3 = INK, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 31 })
		-- shut but not for sale yet, or gone by: dimmed under a veil
		local veil = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 12, 32), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 29 }, b)
		-- once open: the box open, its prize inside
		local inside = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color:Lerp(Color3.fromRGB(8, 16, 40), 0.72), BorderSizePixel = 0, Visible = false, ZIndex = 32 }, b)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(140, 140, 160)) }, inside)
		make("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = paper[1], BorderSizePixel = 0, ZIndex = 33 }, inside) -- (the torn paper along the top)
		if r then
			passIcon(inside, doorShown(r), color, (cw * UNIT_W + (cw - 1) * GAP) / 2, big and 62 or 32, big and 70 or 34)
		end
		label(inside, { Text = Winter.adventText(r), display = true, weight = Enum.FontWeight.Heavy, TextSize = big and 18 or 12, TextWrapped = true, Position = UDim2.new(0, 4, 1, big and -70 or -32), Size = UDim2.new(1, -8, 0, big and 62 or 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 34 })
		label(inside, { Text = tostring(d), display = true, weight = Enum.FontWeight.Heavy, TextSize = 13, TextColor3 = color, Position = UDim2.fromOffset(5, 3), Size = UDim2.fromOffset(30, 14), ZIndex = 34 })
		kit.onClick(b, function()
			T.pick = d
			WinterMenu.refresh()
		end)
		T.doors[d] = { button = b, stroke = stroke, wrapped = wrapped, sash = sash, sashL = sashL, veil = veil, inside = inside, color = color, paper = paper, q = q }
	end
	-- the door picked, on the right
	local SIDE_X = 6 * UNIT_W + 5 * GAP + 16
	T.sideW = 1124 - SIDE_X
	local side = iceCard(f, { Position = UDim2.fromOffset(SIDE_X, 0), Size = UDim2.new(1, -SIDE_X, 1, 0), ZIndex = 22 })
	T.sideDay = label(side, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextColor3 = FROST, Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 34) })
	T.sideDoor = label(side, { Text = "", TextSize = 14, TextColor3 = MIST, Position = UDim2.fromOffset(21, 46), Size = UDim2.new(1, -40, 0, 16) })
	T.kindChip = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(110, 24), BackgroundColor3 = ICE, BorderSizePixel = 0, ZIndex = 23 }, side)
	Gui.corner(T.kindChip, 12)
	T.kindL = label(T.kindChip, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 13, TextColor3 = INK, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
	-- the preview: a dark well with a soft light behind, snow falling in it
	local well = make("Frame", { Position = UDim2.fromOffset(16, 72), Size = UDim2.new(1, -32, 0, 196), BackgroundColor3 = Color3.fromRGB(6, 14, 38), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 23 }, side)
	Gui.corner(well, 10)
	make("UIStroke", { Color = ICE, Thickness = 1, Transparency = 0.6 }, well)
	T.wellGlow = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1, Image = Assets.id(Assets.Fx.Glow) or "", ImageTransparency = 0.55, ZIndex = 23 }, well)
	T.well = well
	T.wellW = T.sideW - 32
	T.flakes = {}
	for i = 1, 14 do
		local s = make("Frame", { Size = UDim2.fromOffset(3, 3), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 24 }, well)
		Gui.round(s)
		T.flakes[i] = { f = s, x = math.random(), y = math.random(), v = 0.06 + math.random() * 0.08 }
	end
	T.stage = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 25 }, well)
	T.sideName = label(side, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, TextWrapped = true, Position = UDim2.fromOffset(20, 276), Size = UDim2.new(1, -40, 0, 64), TextXAlignment = Enum.TextXAlignment.Center })
	T.sideText = label(side, { Text = "", TextSize = 15, TextColor3 = MIST, TextWrapped = true, Position = UDim2.fromOffset(24, 340), Size = UDim2.new(1, -48, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })
	T.open, T.openL = icePlate(side, { Name = "OpenDoor", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -40, 0, 58), ZIndex = 23 }, "Open", 22)
	T.note = label(side, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = GREEN, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.new(1, -40, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	kit.onClick(T.open, function()
		local w = view()
		if not (w and T.pick) then
			return
		end
		local ev = Winter.clean(w.ev)
		openDoor(T.pick, Winter.adventState(ev, T.pick, os.time()))
	end)
	return T
end

-- The preview of the door's prize in the well (rebuilt when the door shown changes).
local function stagePreview(T, d, r, color, hidden)
	for _, c in ipairs(T.stage:GetChildren()) do
		c:Destroy()
	end
	T.sprites, T.spin, T.cardRoot = {}, nil, nil
	local W2, H2 = T.wellW, 196
	T.wellGlow.ImageColor3 = hidden and GOLD_T or color
	if hidden then
		-- the mystery: a gold "?" pulsing, sparkles round it
		local q = label(T.stage, { Text = "?", display = true, weight = Enum.FontWeight.Heavy, TextSize = 150, TextColor3 = GOLD_T, TextStrokeTransparency = 0.4, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 26 })
		T.pulse = q
		local spark = Assets.id(Assets.Fx.Sparkle) or ""
		for i = 1, 8 do
			local s = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Image = spark, ImageColor3 = Color3.fromRGB(255, 236, 160), ZIndex = 27 }, T.stage)
			table.insert(T.sprites, { img = s, orbit = true, a = i / 8 * math.pi * 2, r = 74 })
		end
		return
	end
	T.pulse = nil
	local shown = doorShown(r)
	if shown.Item and shown.Item.Kind == "Ball" then
		-- the ball itself, turning
		local vp = make("ViewportFrame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(190, 190), BackgroundTransparency = 1, Ambient = Color3.fromRGB(150, 160, 190), LightColor = Color3.fromRGB(255, 246, 230), LightDirection = Vector3.new(-0.4, -0.7, -0.6), ZIndex = 26 }, T.stage)
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 1, 7.2), Vector3.new(0, 0.25, 0))
		cam.Parent = vp
		vp.CurrentCamera = cam
		local model = BallSkins.build(shown.Item.Key, 1.4)
		if model then
			model:PivotTo(CFrame.new())
			model.Parent = vp
			T.spin = model
		end
	elseif r and r.Card and not shown.Item and not shown.Skin then
		-- the card itself, with your name on it
		local def = nil
		for _, c in ipairs(Config.Cards.List) do
			if c.Key == r.Card then
				def = c
			end
		end
		if def and Gui.playerCard then
			-- (in a holder of the card's own size, centred, so its scale shrinks it about the middle)
			local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(480, 104), BackgroundTransparency = 1, ZIndex = 26 }, T.stage)
			make("UIScale", { Scale = math.min(1, (W2 - 30) / 480) }, holder)
			local card = Gui.playerCard(holder, { Position = UDim2.fromOffset(0, 0), NoWings = true })
			card.root.ZIndex = 26
			card.set(def.Look, { name = Players.LocalPlayer.DisplayName, line = def.Goal, title = def.Name })
			T.cardRoot = card.root
		end
	elseif shown.Item and (shown.Item.Kind == "Color" or shown.Item.Kind == "Trail") then
		-- a spike's streak across the well: a colour's bands, or a trail's things flying off a plain one
		local it = Spins.item(shown.Item.Kind, shown.Item.Key)
		local cols = (shown.Item.Kind == "Color" and it and it.Trail) or { Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 220, 255) }
		local keys = {}
		for i, c in ipairs(cols) do
			table.insert(keys, ColorSequenceKeypoint.new(#cols == 1 and 0 or (i - 1) / (#cols - 1), c))
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, cols[1]))
		end
		local L = W2 * 0.86
		local streak = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(-20, H2 * 0.62), Size = UDim2.fromOffset(L, 22), Rotation = -18, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 26 }, T.stage)
		-- (a frame turns about its middle: the streak's tip, where the ball is)
		local tip = Vector2.new(-20 + L / 2 + L / 2 * math.cos(math.rad(18)), H2 * 0.62 - L / 2 * math.sin(math.rad(18)))
		Gui.corner(streak, 11)
		make("UIGradient", { Color = ColorSequence.new(keys), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.2), NumberSequenceKeypoint.new(1, 0) }) }, streak)
		local ball = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(tip.X, tip.Y), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = Color3.fromRGB(250, 250, 246), BorderSizePixel = 0, ZIndex = 27 }, T.stage)
		Gui.round(ball)
		make("UIStroke", { Color = cols[#cols], Thickness = 3 }, ball)
		T.ballAt = tip
		local spriteKey = shown.Item.Kind == "Trail" and TRAIL_SPRITE[shown.Item.Key] or nil
		local img = spriteKey and Assets.id(Assets.Fx[spriteKey]) or nil
		if img then
			for i = 1, 10 do
				local s = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1, Image = img, ImageColor3 = (spriteKey == "Sparkle" and Color3.fromRGB(255, 222, 110)) or Color3.new(1, 1, 1), ZIndex = 26 }, T.stage)
				table.insert(T.sprites, { img = s, shed = true, age = i / 10, life = 1 })
			end
		end
	elseif shown.Item and shown.Item.Kind == "Jump" then
		-- a ring of gold bells bobbing on a gold floor ring
		local ring = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.fromOffset(240, 46), BackgroundTransparency = 1, ZIndex = 25 }, T.stage)
		Gui.round(ring)
		make("UIStroke", { Color = GOLD_T, Thickness = 3, Transparency = 0.2 }, ring)
		local img = Assets.id(Assets.Fx.Bell) or ""
		for i = 1, 6 do
			local s = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(50, 50), BackgroundTransparency = 1, Image = img, ZIndex = 26 }, T.stage)
			table.insert(T.sprites, { img = s, bell = true, a = i / 6 * math.pi * 2 })
		end
	else
		-- a skin (or anything else): its big glowing star in its colour
		local star = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(130, 130), BackgroundTransparency = 1, Image = Assets.image("IconStar") or "", ImageColor3 = color, ZIndex = 26 }, T.stage)
		T.pulse = star
	end
end

-- The well's motion, each frame while the tab is up (WinterMenu.init).
local function animateAdvent(dt)
	local T = ui.tabs.Advent
	if not T or not T.frame.Visible then
		return
	end
	T.t = T.t + dt
	local t = T.t
	for _, s in ipairs(T.flakes) do
		s.y = (s.y + s.v * dt) % 1
		s.f.Position = UDim2.new(s.x + math.sin(t * 0.8 + s.v * 40) * 0.02, 0, s.y, 0)
	end
	if T.spin and T.spin.Parent then
		T.spin:PivotTo(CFrame.Angles(math.rad(-12), t * 0.9, 0))
	end
	if T.pulse then
		local k = 1 + 0.06 * math.sin(t * 3)
		T.pulse.Size = UDim2.fromOffset(130 * k, 130 * k)
		if T.pulse:IsA("TextLabel") then
			T.pulse.Size = UDim2.fromScale(k, k)
			T.pulse.Position = UDim2.fromScale((1 - k) / 2, (1 - k) / 2)
		end
	end
	for _, s in ipairs(T.sprites) do
		if s.orbit then
			local a = s.a + t * 0.8
			s.img.Position = UDim2.new(0.5, math.cos(a) * s.r * 1.6, 0.5, math.sin(a) * s.r * 0.9)
			s.img.ImageTransparency = 0.2 + 0.5 * (0.5 + 0.5 * math.sin(t * 4 + s.a * 3))
		elseif s.shed and T.ballAt then
			s.age = s.age + dt / 1.1
			if s.age > 1 then
				s.age = s.age - 1
				s.dx, s.dy, s.rot = -40 - math.random() * 90, -10 + math.random() * 60, math.random() * 360
			end
			local a = s.age
			s.img.Position = UDim2.fromOffset(T.ballAt.X + (s.dx or -80) * a, T.ballAt.Y + (s.dy or 20) * a + 70 * a * a)
			s.img.Rotation = (s.rot or 0) + a * 200
			s.img.ImageTransparency = math.clamp((a - 0.6) / 0.4, 0, 1)
			local sz = 22 + 14 * math.min(1, a * 5)
			s.img.Size = UDim2.fromOffset(sz, sz)
		elseif s.bell then
			local a = s.a + t * 0.6
			local depth = math.sin(a)
			s.img.Position = UDim2.new(0.5, math.cos(a) * 110, 0.72, depth * 18 - 6 - math.abs(math.sin(t * 4 + s.a)) * 14)
			s.img.Rotation = math.sin(t * 6 + s.a * 2) * 18
			s.img.ZIndex = depth > 0 and 27 or 24
		end
	end
	-- today's door glows
	for _, c in pairs(T.doors) do
		if c.today then
			c.stroke.Transparency = 0.5 - 0.5 * math.sin(t * 4)
		end
	end
end

local function refreshAdvent(ev, p)
	local T = ui.tabs.Advent
	local now = os.time()
	local today = Winter.adventToday(now)
	local opened = Winter.adventCount(ev)
	local price = ADV.Product.Id ~= 0 and string.format("R$ %d", ADV.Product.Price) or ((p and p.studio) and "free in Studio" or "soon")
	local w = view()
	if today < 1 then
		T.line.Text = string.format("Door 1 opens on December 1. Can't wait? Open a door early for %s (all but the 25th).", price)
	elseif today <= ADV.Doors then
		local left = math.max(0, (w and w.dayLeft or 0) - (os.clock() - seenAt))
		T.line.Text = string.format("A free door every day to Christmas: the next opens in %s. Missed one? %s.", leftText(left), price)
	else
		T.line.Text = string.format("Every door's day has come. Missed doors still open for %s.", price)
	end
	T.count.Text = string.format("%d / %d", opened, ADV.Doors)
	for d, tick in ipairs(T.ticks) do
		tick.BackgroundColor3 = Winter.adventOpen(ev, d) and GOLD_T or (d == today and FROST or WELL)
	end
	if not T.pick then
		T.pick = (today >= 1 and today <= ADV.Doors) and today or (Winter.adventTarget(ev, nil, now) or 1)
	end
	for d, c in pairs(T.doors) do
		local st = Winter.adventState(ev, d, now)
		local open = st == "open"
		c.inside.Visible = open
		for _, o in ipairs(c.wrapped) do
			if o:IsA("GuiObject") then
				o.Visible = not open
			end
		end
		c.today = st == "today"
		c.veil.BackgroundTransparency = st == "missed" and 0.45 or 1
		c.stroke.Color = (d == T.pick) and FROST or (st == "today" and GOLD_T or (open and c.color or Color3.fromRGB(8, 18, 44)))
		c.stroke.Thickness = (d == T.pick) and 4 or (st == "today" and 4 or 2)
		if not c.today then
			c.stroke.Transparency = 0
		end
		c.sash.Visible = st == "today" or st == "missed" or st == "early"
		if st == "today" then
			c.sash.BackgroundColor3 = GOLD_T
			c.sashL.Text = "TODAY"
		elseif st == "missed" then
			c.sash.BackgroundColor3 = Color3.fromRGB(170, 180, 200)
			c.sashL.Text = "MISSED"
		elseif st == "early" then
			c.sash.BackgroundColor3 = FROST
			c.sashL.Text = "DEC " .. d
		end
	end
	local d = T.pick
	local r = Winter.adventReward(d)
	local st = Winter.adventState(ev, d, now)
	local hidden = mystery(d, ev)
	local shown = doorShown(r)
	local kindWord, color = rewardKind(shown)
	T.sideDay.Text = "DECEMBER " .. d
	T.sideDoor.Text = "Door " .. d .. ((d == ADV.Doors) and "  ·  Christmas morning" or "")
	T.kindChip.BackgroundColor3 = hidden and GOLD_T or color
	T.kindL.Text = hidden and "MYSTERY" or kindWord
	if T.shownFor ~= d or T.shownHidden ~= hidden then
		T.shownFor, T.shownHidden = d, hidden
		stagePreview(T, d, r, color, hidden)
	end
	if hidden then
		local big = ADV.Mystery and ADV.Mystery[d]
		T.sideName.Text = big and "A Mythic surprise" or "A surprise"
		T.sideText.Text = big and "Something huge is behind the last door. Open it on Christmas morning to find out." or string.format("What's behind it stays a secret until December %d. Open it early to find out.", d)
	else
		T.sideName.Text = Winter.adventText(r)
		local kindKey = (shown.Skin and "Skin") or (shown.Item and shown.Item.Kind) or (r and r.Card and "Card") or ""
		T.sideText.Text = KIND_LINE[kindKey] or ""
	end
	T.open.Visible = st ~= "open" and st ~= "early"
	T.note.Visible = st == "open" or st == "early"
	if st == "open" then
		T.note.Text = "Opened: it's in your Locker"
		T.note.TextColor3 = GREEN
	elseif st == "early" then
		T.note.Text = "Opens on Christmas morning"
		T.note.TextColor3 = GOLD_T
	elseif st == "today" then
		T.openL.Text = "Open today's door: free"
	elseif st == "missed" then
		T.openL.Text = "Open  ·  " .. price
	else
		T.openL.Text = "Open early  ·  " .. price
	end
	ui.adventDot.Visible = Winter.adventState(ev, today, now) == "today"
end

------------------------------------------------------------------------------------------
-- the window, and Home's card
------------------------------------------------------------------------------------------

-- The Story tab (the owner, 2026-11-16: "where do you find the story in the event tab? make a
-- seperate tab"): the Winter side story (Config.Story's Side chapter, Snowed In), its five stages
-- and how far you are, a button into story mode at your next stage; a stage opens there too.
local STORY_KEY = "w1"

local function openStory(stageKey)
	local SM = mods and mods.StoryMenu
	if not SM or not SM.openChapter then
		return
	end
	if SM.openChapter(STORY_KEY, stageKey) then
		ui.window.root.Visible = false
	end
end

local function buildStoryTab(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local T = { frame = f, rows = {} }
	local ch = Story.chapter(STORY_KEY)
	T.chapter = ch
	-- the chapter, down the left
	label(f, { Text = "WINTER SPECIAL  ·  STORY MODE", display = true, weight = Enum.FontWeight.Heavy, TextSize = 18, TextColor3 = ICE, Size = UDim2.fromOffset(420, 22), ZIndex = 22 })
	label(f, { Text = ch and ch.Name or "Coming soon", display = true, weight = Enum.FontWeight.Heavy, TextSize = 46, TextColor3 = FROST, Position = UDim2.fromOffset(0, 24), Size = UDim2.fromOffset(420, 52), ZIndex = 22 })
	label(f, { Text = ch and ch.Blurb or "", TextSize = 18, TextColor3 = MIST, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(0, 86), Size = UDim2.fromOffset(410, 120), ZIndex = 22 })
	T.stars = label(f, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, TextColor3 = GOLD_T, Position = UDim2.fromOffset(0, 214), Size = UDim2.fromOffset(410, 26), ZIndex = 22 })
	T.play, T.playL = icePlate(f, { Position = UDim2.fromOffset(0, 254), Size = UDim2.fromOffset(410, 66), ZIndex = 23 }, "Play", 24)
	kit.onClick(T.play, function()
		openStory(nil)
	end)
	label(f, { Text = "Five stages on Snowfall Lodge, with Jaja. Clears pay VP and Gold, the finale a lucky spin.", TextSize = 15, TextColor3 = MIST, TextWrapped = true, Position = UDim2.fromOffset(0, 330), Size = UDim2.fromOffset(410, 40), ZIndex = 22 })
	-- the stages, down the right
	for i, st in ipairs(ch and ch.Stages or {}) do
		local y = (i - 1) * 84
		local b = make("TextButton", { Position = UDim2.new(0, 444, 0, y), Size = UDim2.new(1, -444, 0, 74), BackgroundColor3 = ROW, BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 22 }, f)
		Gui.corner(b, 10)
		local stroke = make("UIStroke", { Color = ICE, Thickness = 2, Transparency = 0.7, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local chip = make("Frame", { Position = UDim2.fromOffset(12, 15), Size = UDim2.fromOffset(64, 44), BackgroundColor3 = WELL, BorderSizePixel = 0, ZIndex = 23 }, b)
		Gui.corner(chip, 8)
		local num = label(chip, { Text = Story.label(st.Key):gsub(" ", ""), display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = FROST, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
		local name = label(b, { Text = st.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 26, TextColor3 = FROST, Position = UDim2.fromOffset(92, 10), Size = UDim2.new(1, -260, 0, 30), ZIndex = 23 })
		local kind = Story.isMatch(st) and ("Match vs " .. tostring(st.Versus)) or "Story: reading only"
		label(b, { Text = kind, TextSize = 16, TextColor3 = MIST, Position = UDim2.fromOffset(92, 42), Size = UDim2.new(1, -260, 0, 20), ZIndex = 23 })
		local state = label(b, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, TextColor3 = GOLD_T, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, 0), Size = UDim2.fromOffset(150, 28), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 23 })
		kit.onClick(b, function()
			local p = kit.profile()
			if Story.unlocked((p and p.story) or { stars = {} }, st.Key) then
				openStory(st.Key)
			else
				kit.toast("Clear the stage before it first.")
			end
		end)
		T.rows[i] = { button = b, stroke = stroke, num = num, name = name, state = state, stage = st }
	end
	return T
end

local function refreshStory()
	local T = ui.tabs.Story
	local ch = T.chapter
	if not ch then
		T.playL.Text = "Coming soon"
		return
	end
	local p = kit.profile()
	local prog = (p and p.story) or { stars = {} }
	local have, total = Story.chapterStars(prog, ch)
	T.stars.Text = string.format("★ %d / %d stars", have, total)
	local nextStage = nil
	for _, st in ipairs(ch.Stages) do
		if not Story.cleared(prog, st.Key) then
			nextStage = st
			break
		end
	end
	if nextStage then
		T.playL.Text = (nextStage == ch.Stages[1]) and "Start the story" or ("Continue: " .. nextStage.Name)
	else
		T.playL.Text = "Read it again"
	end
	for _, r in ipairs(T.rows) do
		local n = Story.stars(prog, r.stage.Key)
		local open = Story.unlocked(prog, r.stage.Key)
		local isNext = nextStage == r.stage
		if n > 0 then
			r.state.Text = string.rep("★", n) .. string.rep("☆", 3 - n)
			r.state.TextColor3 = GOLD_T
		elseif isNext then
			r.state.Text = "NEXT"
			r.state.TextColor3 = FROST
		else
			r.state.Text = open and "" or "LOCKED"
			r.state.TextColor3 = MIST
		end
		r.button.BackgroundTransparency = open and 0 or 0.45
		r.name.TextTransparency = open and 0 or 0.4
		r.stroke.Transparency = isNext and 0 or 0.7
	end
end

local function setTab(key)
	tab = key
	for k, t in pairs(ui.tabs) do
		t.frame.Visible = k == key
	end
	if ui.setSeg then
		ui.setSeg(key)
	end
	WinterMenu.refresh()
end

local function buildWindow()
	local m = kit.modal("Winter", W.Name, 1180, 680, true)
	ui.window = m
	-- its own colours: deep blue fading down, an icy edge, the title's bar in white, the grain white
	m.panel.BackgroundColor3 = Color3.new(1, 1, 1)
	m.panel.BackgroundTransparency = 0.03
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(DEEP_TOP, DEEP) }, m.panel)
	for _, d in ipairs(m.panel:GetChildren()) do
		if d:IsA("UIStroke") then
			d.Color = ICE
			d.Thickness = 2
			d.Transparency = 0.2
		elseif d.Name == "Halftone" then
			d.ImageColor3 = FROST
			d.ImageTransparency = 0.9
		elseif d:GetAttribute("Slant") and not d:IsA("GuiButton") then
			Gui.tint(d, FROST) -- (the slanted bar under the title)
		end
	end
	-- big faint snowflakes behind everything
	-- (in a frame of their own that clips them at the window's edge; unturned, since a turned image
	-- ignores the clip. The lights hang over the top edge, so the panel itself can't clip.)
	local flake = Assets.image("IconSnowflake")
	if flake then
		local back = make("Frame", { Name = "Snow", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 0 }, m.panel)
		for _, def in ipairs({ { 0.93, 0.22, 320, 0.9 }, { 0.04, 0.97, 260, 0.92 }, { 0.62, 1.03, 190, 0.94 } }) do
			make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(def[1], def[2]), Size = UDim2.fromOffset(def[3], def[3]), BackgroundTransparency = 1, Image = flake, ImageColor3 = FROST, ImageTransparency = def[4], ZIndex = 0 }, back)
		end
	end
	ui.bulbs = stringLights(m.panel, 1180)
	ui.info = label(m.panel, { Text = "", display = true, TextSize = 21, TextColor3 = FROST, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 26), Size = UDim2.fromOffset(560, 26), ZIndex = 22 })
	local items = { { key = "Match", text = "Match" }, { key = "Story", text = "Story" }, { key = "Quests", text = "Quests" }, { key = "Advent", text = "Advent" }, { key = "Recruit", text = "Recruit" }, { key = "Shop", text = "Shop" }, { key = "Pass", text = "Pass" } }
	local SEG_W = 910 -- (seven tabs, 130 each)
	local per = SEG_W / #items
	local seg, set = kit.segmented(m.panel, items, { Position = UDim2.fromOffset(28, 86), Size = UDim2.fromOffset(SEG_W, 46), ZIndex = 22 }, setTab)
	seg.Name = "Tabs"
	-- the lit tab is white, not the menus' orange
	seg.BackgroundColor3 = WELL
	for _, d in ipairs(seg:GetChildren()) do
		if d:IsA("TextButton") then
			d.BackgroundColor3 = FROST
		end
	end
	ui.setSeg = set
	-- a dot on Quests while something waits there
	ui.questDot = make("Frame", { Position = UDim2.fromOffset(28 + per * 3 - 22, 90), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Gui.ALERT, BorderSizePixel = 0, Visible = false, ZIndex = 25 }, m.panel)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ui.questDot)
	-- and on Pass while a tier's reward waits
	ui.adventDot = make("Frame", { Position = UDim2.fromOffset(28 + per * 4 - 22, 90), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Gui.ALERT, BorderSizePixel = 0, Visible = false, ZIndex = 25 }, m.panel)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ui.adventDot)
	ui.passDot = make("Frame", { Position = UDim2.fromOffset(28 + per * 7 - 22, 90), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Gui.ALERT, BorderSizePixel = 0, Visible = false, ZIndex = 25 }, m.panel)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ui.passDot)
	local body = make("Frame", { Position = UDim2.fromOffset(28, 148), Size = UDim2.new(1, -56, 1, -170), BackgroundTransparency = 1, ZIndex = 21 }, m.panel)
	ui.tabs = { Match = buildMatchTab(body), Story = buildStoryTab(body), Quests = buildQuestTab(body), Advent = buildAdventTab(body), Recruit = buildRecruitTab(body), Shop = buildShopTab(body), Pass = buildPassTab(body) }
	set(tab)
end

-- Home's card: under your record, where the tutorial's card sits until it's done.
local function buildHomeCard()
	local column = kit.homeColumn
	if not column then
		return
	end
	local b = Gui.cardButton(column, { Name = "Winter", Position = UDim2.fromOffset(0, 434), Size = UDim2.fromOffset(470, 112), Visible = false })
	b.BackgroundColor3 = ROW
	b.BackgroundTransparency = 0.18
	b.UIStroke.Color = ICE
	b.UIStroke.Transparency = 0.25
	Gui.halftone(b, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.5, 1), ImageColor3 = ICE, ImageTransparency = 0.9 })
	snowIcon(b, 34, { Position = UDim2.fromOffset(18, 16) })
	Gui.label(b, { Text = "Limited event", TextSize = 14, weight = Enum.FontWeight.Medium, TextColor3 = ICE, Position = UDim2.fromOffset(64, 10), Size = UDim2.fromOffset(200, 16) })
	Gui.label(b, { Text = W.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 34, Position = UDim2.fromOffset(62, 24), Size = UDim2.fromOffset(290, 38) })
	Gui.label(b, { Text = "with " .. W.Partner, TextSize = 14, TextColor3 = MIST, Position = UDim2.fromOffset(64, 62), Size = UDim2.fromOffset(300, 16) })
	local left = Gui.label(b, { Text = "", display = true, TextSize = 18, TextColor3 = ICE, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(130, 22) })
	local line = Gui.label(b, { Text = "", TextSize = 15, weight = Enum.FontWeight.Medium, Position = UDim2.fromOffset(18, 84), Size = UDim2.fromOffset(434, 20) })
	local dot = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Gui.ALERT, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, b)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
	kit.onClick(b, function()
		WinterMenu.open()
	end)
	ui.home = { button = b, left = left, line = line, dot = dot }
end

-- Home's Pass button (the owner, 2026-11-16: "put a pass button right next to admin showing your
-- level and progress"): in the row with Decorate and Admin, bottom left; the tier you're on and the
-- way to the next, a dot while a reward waits; it opens the Pass tab.
local function buildPassButton()
	local row = kit.homeCorner
	if not row then
		return
	end
	local b = make("TextButton", { Name = "WinterPass", Size = UDim2.fromOffset(170, 74), BackgroundColor3 = ROW, BackgroundTransparency = 0.15, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = 3, Visible = false }, row)
	Gui.corner(b, 10)
	make("UIStroke", { Color = ICE, Thickness = 2, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	snowIcon(b, 26, { Position = UDim2.fromOffset(10, 9) })
	label(b, { Text = "WINTER PASS", display = true, weight = Enum.FontWeight.Heavy, TextSize = 13, TextColor3 = ICE, Position = UDim2.fromOffset(42, 6), Size = UDim2.fromOffset(122, 16) })
	local tier = label(b, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextColor3 = FROST, Position = UDim2.fromOffset(42, 20), Size = UDim2.fromOffset(122, 26) })
	local track = make("Frame", { Position = UDim2.fromOffset(10, 52), Size = UDim2.fromOffset(150, 8), BackgroundColor3 = WELL, BorderSizePixel = 0 }, b)
	Gui.corner(track, 4)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = ICE, BorderSizePixel = 0 }, track)
	Gui.corner(fill, 4)
	local xp = label(b, { Text = "", TextSize = 11, TextColor3 = MIST, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(10, 60), Size = UDim2.fromOffset(150, 12) })
	local dot = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Gui.ALERT, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, b)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
	kit.onClick(b, function()
		WinterMenu.open("Pass")
	end)
	ui.passButton = { button = b, tier = tier, fill = fill, xp = xp, dot = dot }
end

function WinterMenu.refresh()
	if not ui.window then
		return
	end
	local w = view()
	local hm = ui.home
	if not w then
		-- the event isn't running: nothing of it shows
		if hm then
			hm.button.Visible = false
		end
		if ui.passButton then
			ui.passButton.button.Visible = false
		end
		if ui.window.root.Visible then
			ui.window.root.Visible = false
		end
		return
	end
	local ev = Winter.clean(w.ev)
	local day = w.day
	local endsIn = math.max(0, (w.endsIn or 0) - (os.clock() - seenAt))
	local waiting = Winter.waiting(ev, day)
	if hm then
		-- (the tutorial's card has the spot until it's done)
		hm.button.Visible = not (kit.homeTut and kit.homeTut.Visible)
		hm.left.Text = leftText(endsIn) .. " left"
		hm.line.Text = string.format("%s %s%s", Gui.num(ev.snow), SNOW, waiting > 0 and string.format("  ·  %d reward%s waiting", waiting, waiting == 1 and "" or "s") or "")
		hm.dot.Visible = waiting > 0
	end
	local pb = ui.passButton
	if pb then
		local t, into, need = Winter.passTier(ev)
		pb.button.Visible = true
		pb.tier.Text = string.format("TIER %d", t)
		pb.fill.Size = UDim2.fromScale(need > 0 and into / need or 1, 1)
		pb.xp.Text = need > 0 and string.format("%d / %d XP", into, need) or "every tier reached"
		pb.dot.Visible = #Winter.passClaimable(ev) > 0
	end
	-- a match started with the window open: it goes
	if State.isPlaying and ui.window.root.Visible then
		ui.window.root.Visible = false
	end
	if not ui.window.root.Visible then
		return
	end
	ui.info.Text = string.format("%s %s  ·  %s left", Gui.num(ev.snow), SNOW, leftText(endsIn))
	ui.questDot.Visible = waiting > 0
	if tab == "Match" then
		local row = Winter.rival(Winter.rivalIndex(day))
		local names = {}
		for _, id in ipairs(Winter.picks(Winter.rivalIndex(day)).Away) do
			local c = Roster.get(id)
			table.insert(names, c and c.Name or id)
		end
		ui.tabs.Match.rival.Text = string.format("TODAY'S RIVAL (Blizzard): %s  <font size=\"16\" color=\"#B2CEF2\">%s  ·  a new team in %s</font>", string.upper(row.Name), table.concat(names, ", "), leftText(math.max(0, (w.dayLeft or 0) - (os.clock() - seenAt))))
		for key, c in pairs(ui.tabs.Match.cards) do
			c.done.Text = (ev.day == day and ev.cleared[key]) and "First win taken today" or ""
		end
	elseif tab == "Quests" then
		local T = ui.tabs.Quests
		local ready = Winter.loginReady(ev, day)
		T.check.Visible = ready
		T.checked.Visible = not ready
		T.dayLine.Text = string.format("%d day%s checked in. A new one every day.", ev.login.count, ev.login.count == 1 and "" or "s")
		for i, d in ipairs(Winter.loginRow(ev, DAYS)) do
			local chip = T.days[i]
			local nextUp = ready and d.day == ev.login.count + 1
			chip.day.Text = "DAY " .. d.day
			chip.snow.Text = "+" .. d.snow
			chip.snow.TextTransparency = d.taken and 0.6 or 0
			chip.state.Text = d.taken and "TAKEN" or (nextUp and "TODAY" or "")
			chip.state.TextColor3 = d.taken and GREEN or ICE
			chip.stroke.Transparency = nextUp and 0 or 1
		end
		T.reset.Text = "new quests in " .. leftText(math.max(0, (w.dayLeft or 0) - (os.clock() - seenAt)))
		local today = Winter.dailyQuests(day)
		for i, row in ipairs(T.quests) do
			local def = today[i]
			row.key = def and def.Key or nil
			if def then
				local have, need, done, claimed = Winter.questProgress(ev, def, day)
				row.text.Text = string.format("%s  (%d/%d)", Winter.text(def), have, need)
				row.text.TextColor3 = claimed and Gui.MUTED or Gui.CHALK
				row.pay.Text = "+" .. def.Snow
				row.pay.TextColor3 = claimed and GREEN or ICE
				row.claimL.Text = claimed and "Claimed" or "Claim"
				row.claimL.TextColor3 = (done and not claimed) and FROST or MIST
				Gui.enable(row.claim, row.claimL, done and not claimed)
			end
		end
		for _, row in ipairs(T.missions) do
			local have, need, done, claimed = Winter.missionProgress(ev, row.def)
			row.text.Text = string.format("%s  (%d/%d)", Winter.text(row.def), have, need)
			row.text.TextColor3 = claimed and Gui.MUTED or Gui.CHALK
			row.claimL.Text = claimed and "Claimed" or "Claim"
			row.claimL.TextColor3 = (done and not claimed) and FROST or MIST
			Gui.enable(row.claim, row.claimL, done and not claimed)
		end
	elseif tab == "Recruit" then
		local T = ui.tabs.Recruit
		local p = kit.profile()
		local left = Winter.pityLeft(ev)
		T.gauge.Text = left <= 1 and "The next recruit is Jaja" or string.format("Jaja is certain within %d recruits", left)
		T.fill.Size = UDim2.fromScale(math.clamp(ev.gauge / math.max(1, W.Banner.Pity - 1), 0, 1), 1)
		local mine = p and p.owned and p.owned.Char and p.owned.Char.jaja == true
		T.owned.Text = mine and "Jaja is on your roster: another is a Fragment for his breakthroughs" or ""
		for _, b in ipairs(T.buttons) do
			b.label.TextTransparency = (ev.snow >= b.cost or (p and p.dev)) and 0 or 0.45
		end
	elseif tab == "Shop" then
		local p = kit.profile()
		for _, r in ipairs(ui.tabs.Shop.rows) do
			local row = r.row
			local n = ev.bought[row.Key] or 0
			local owned = row.Item and p and p.owned and p.owned[row.Item.Kind] and p.owned[row.Item.Kind][row.Item.Key] == true
			if owned then
				r.left.Text = "Owned"
			elseif row.Limit then
				r.left.Text = string.format("%d of %d left", math.max(0, row.Limit - n), row.Limit)
			else
				r.left.Text = ""
			end
			r.buy.Visible = not owned and not (row.Limit and n >= row.Limit)
			r.buyL.TextTransparency = ev.snow >= row.Price and 0 or 0.45
		end
	elseif tab == "Pass" then
		refreshPass(ev, kit.profile())
	elseif tab == "Advent" then
		refreshAdvent(ev, kit.profile())
	elseif tab == "Story" then
		refreshStory()
	end
	if tab ~= "Pass" then
		ui.passDot.Visible = #Winter.passClaimable(ev) > 0
	end
	if tab ~= "Advent" then
		ui.adventDot.Visible = Winter.adventState(ev, Winter.adventToday(os.time()), os.time()) == "today"
	end
end

-- The Winter window, on `which` tab when given ("Match", "Story", "Quests", "Recruit", "Shop", "Pass").
function WinterMenu.open(which)
	if not ui.window then
		return
	end
	if not view() then
		kit.toast(W.Name .. " isn't running.")
		return
	end
	if which and ui.tabs[which] then
		setTab(which)
	end
	if not ui.window.root.Visible and mods and mods.AudioController then
		mods.AudioController.play("WinterBells") -- (the window opens on a jingle of bells)
	end
	ui.window.root.Visible = true
	WinterMenu.refresh()
end

function WinterMenu.init(m)
	mods = m
	kit = mods.MenuController.kit()
	buildWindow()
	buildHomeCard()
	buildPassButton()
	local lastReveal = nil
	local function took(p)
		if type(p) == "table" and type(p.winter) == "table" and p.winter ~= seen then
			seen, seenAt = p.winter, os.clock()
		end
	end
	took(kit.profile())
	State.signals.Profile:Connect(function(p)
		took(p)
		if type(p) == "table" and p.winReveal and p.winReveal ~= lastReveal then
			lastReveal = p.winReveal
			showReveal(p.winReveal)
		end
		WinterMenu.refresh()
	end)
	State.signals.Match:Connect(function()
		task.defer(WinterMenu.refresh)
	end)
	-- the countdowns, while something of the event is on screen
	local last, lastTwinkle = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		if ui.window.root.Visible and tab == "Advent" then
			animateAdvent(dt)
		end
		local now = os.clock()
		if ui.window.root.Visible and now - lastTwinkle > 0.06 then
			lastTwinkle = now
			for _, bl in ipairs(ui.bulbs or {}) do
				local k = 0.5 + 0.5 * math.sin(now * 2.4 + bl.phase)
				bl.glow.ImageTransparency = 0.3 + 0.5 * k
				bl.bulb.BackgroundTransparency = 0.3 * k
			end
		end
		if now - last < 1 then
			return
		end
		last = now
		if ui.window.root.Visible or (ui.home and kit.shown()) then
			WinterMenu.refresh()
		end
	end)
	WinterMenu.refresh()
end

return WinterMenu
