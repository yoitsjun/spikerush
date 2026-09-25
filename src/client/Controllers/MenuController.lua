-- The menus, over the 3D scenes (SceneController): everything you do outside a match.
--   Home ......... your profile and currencies, the featured recruit, tips, Recruit Player and
--                  Match. When your AI is standing in for you, a Rejoin banner.
--   Recruit ...... Player and cosmetic banners, the probability table, auto-roll, auto-sell,
--                  Recruit x1 / x10 and the recruit sequence: sparkles on black (gold when an S
--                  is inside), volleyballs under the gym ceiling, the line-up ("Click to
--                  Continue"), a short cinematic of your avatar spiking before an S is unboxed,
--                  the reveal card and the results. Skip jumps straight to the next S.
--   Players ...... your characters: pick who you play, spend Gold on their four stats.
--   Locker ....... equip spike styles, colours, trails and score effects, with a live preview.
--   Shop ......... V Point packs.
--   Match ........ Quick Match, the lobby list, Create Lobby (public, friends only or private
--                  with a password, fill with bots, bot level) and your lobby.
-- Layout is drawn on a 900-unit-tall canvas scaled to the screen, so it keeps its proportions
-- on every device.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)
local Spins = require(Shared.Spins)
local Roster = require(Shared.Roster)
local Tutorial = require(Shared.Tutorial)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local MenuController = {}
local mods

local player = Players.LocalPlayer
local make, text = Gui.make, Gui.text
local SP, COS = Config.Spins, Config.Cosmetics
local M = 28 -- screen margin (canvas units)

local gui, canvas, canvasScale
local screen = "home"
local shown = false
local ui = {}
local lobbies = { list = {}, mine = nil, court = {} }
local seqActive = nil -- the recruit sequence while it plays
local lastReveal = nil -- the last reveal table handled
local selectedChar = nil -- the Players screen's character
local lockerKind = "Style"
local lockerPick = {} -- kind -> key being previewed
local recruitTab = "Player"
local banner = "Char"
local refreshQueued = false

local TIPS = {
	"Hold toward the net as you let go of a jump-serve toss to throw it forward, then run into it.",
	"Press receive a little early for a perfect dig: it barely costs your team's stamina.",
	"Boom jumps need a Jump stat of 170 or more. Spend Gold on Jump in Players.",
	"Setters: hold toward the net to set a quick for your middle, away for a back set.",
	"A timeout refills stamina and lets you change who serves next.",
	"Thunder Spiker turns any spike hit above 4.00 m into lightning.",
	"Friends lobbies only show up for the host's friends. Private lobbies need a password.",
	"The match MVP earns 15 extra V Points.",
}

------------------------------------------------------------------------------------------
-- small helpers
------------------------------------------------------------------------------------------

local function click()
	if mods and mods.AudioController then
		mods.AudioController.play("UIClick", { minGap = 0.05 })
	end
end

local function profile()
	return State.profile or { vp = 0, gold = 0, owned = {}, equip = {}, levels = {}, autoSell = {} }
end

local function sendProfile(...)
	click()
	Net.get("Profile"):FireServer(...)
end

local function sendLobby(...)
	click()
	Net.get("Lobby"):FireServer(...)
end

local function tween(obj, time, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function roleName(role)
	local r = Config.Roles[role or ""]
	return r and r.Name or tostring(role)
end

local function tierColor(tier)
	if tier == "S+" then
		return Config.Rarity.Colors.Mythic
	end
	return Characters.color(tier)
end

local function owns(prof, kind, key)
	return prof.owned and prof.owned[kind] and prof.owned[kind][key] == true
end

local function ownedCount(prof, kind)
	local n = 0
	for _, item in ipairs(Spins.items(kind)) do
		if owns(prof, kind, item.Key) then
			n = n + 1
		end
	end
	return n, #Spins.items(kind)
end

local function bannerName(kind)
	if kind == "Char" then
		return "Basic Recruit"
	end
	return SP.Banners[kind].Name
end

local function onClick(button, fn)
	button.MouseButton1Click:Connect(function()
		click()
		fn()
	end)
end

-- A round glass icon button with a small caption under it.
local function iconButton(parent, iconFn, caption, props)
	local b = make("TextButton", { Size = UDim2.fromOffset(64, 82), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	local disc = make("Frame", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(4, 0), BackgroundColor3 = Color3.fromRGB(10, 12, 22), BackgroundTransparency = 0.3 }, b)
	Gui.round(disc)
	local ring = Gui.stroke(disc, 1.5, Gui.WHITE, 0.75, true)
	local icon = iconFn(disc, 30, Gui.WHITE)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	text(b, { Text = caption, Size = UDim2.new(1, 12, 0, 18), Position = UDim2.fromOffset(-6, 60), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center })
	b.MouseEnter:Connect(function()
		ring.Transparency = 0.2
		ring.Color = Gui.GOLD
	end)
	b.MouseLeave:Connect(function()
		ring.Transparency = 0.75
		ring.Color = Gui.WHITE
	end)
	return b
end

-- Segmented control: returns the frame and a setter(activeKey). onPick(key) on a press.
local function segmented(parent, items, props, onPick)
	local f = make("Frame", { BackgroundColor3 = Color3.fromRGB(8, 10, 18), BackgroundTransparency = 0.35 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	Gui.corner(f, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, f)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	local buttons = {}
	for i, it in ipairs(items) do
		local b = make("TextButton", {
			Size = UDim2.new(1 / #items, -4 * (#items - 1) / #items, 1, 0),
			BackgroundColor3 = Gui.GOLD,
			BackgroundTransparency = 1,
			Text = it.text,
			Font = Gui.FONT_HEAVY,
			TextSize = 16,
			TextColor3 = Gui.MUTED,
			AutoButtonColor = false,
			LayoutOrder = i,
		}, f)
		Gui.corner(b, 6)
		onClick(b, function()
			onPick(it.key)
		end)
		buttons[it.key] = b
	end
	local function set(active)
		for key, b in pairs(buttons) do
			local on = key == active
			b.BackgroundTransparency = on and 0 or 1
			b.TextColor3 = on and Gui.INK or Gui.MUTED
		end
	end
	return f, set
end

-- Toast: a notice that fades out at the top of the screen.
local function toast(msg)
	local t = ui.toast
	if not t or not msg or msg == "" then
		return
	end
	t.label.Text = msg
	t.frame.Visible = true
	t.frame.BackgroundTransparency = 0.15
	t.label.TextTransparency = 0
	t.token = (t.token or 0) + 1
	local token = t.token
	task.delay(3.2, function()
		if t.token == token then
			tween(t.frame, 0.4, { BackgroundTransparency = 1 })
			tween(t.label, 0.4, { TextTransparency = 1 })
			task.delay(0.45, function()
				if t.token == token then
					t.frame.Visible = false
				end
			end)
		end
	end)
end
MenuController.toast = toast

------------------------------------------------------------------------------------------
-- shared chrome: back + title, currencies, settings
------------------------------------------------------------------------------------------

local function currencyRow(parent, props)
	local row = make("Frame", { Size = UDim2.fromOffset(360, 34), BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		row[k] = v
	end
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local vpFrame, vp, vpPlus = Gui.currency(row, Gui.icon.vp, { LayoutOrder = 1 })
	local goldFrame, gold, goldPlus = Gui.currency(row, Gui.icon.gold, { LayoutOrder = 2 })
	goldPlus.Visible = false
	onClick(vpPlus, function()
		MenuController.go("shop")
	end)
	local entry = { vp = vp, gold = gold, vpFrame = vpFrame, goldFrame = goldFrame }
	ui.currencies = ui.currencies or {}
	table.insert(ui.currencies, entry)
	return row
end

-- A sub-screen's header: back arrow and title (top left), currencies (top right).
local function header(page, title)
	local back = make("TextButton", { Size = UDim2.fromOffset(420, 56), Position = UDim2.fromOffset(M, 64), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, page)
	local disc = make("Frame", { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(0, 4), BackgroundColor3 = Color3.fromRGB(10, 12, 22), BackgroundTransparency = 0.3 }, back)
	Gui.round(disc)
	Gui.stroke(disc, 1.5, Gui.WHITE, 0.7, true)
	local arrow = Gui.icon.back(disc, 26, Gui.WHITE)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.5)
	local t = text(back, { Text = title, Font = Gui.FONT_TITLE, TextSize = 40, Size = UDim2.new(1, -64, 1, 0), Position = UDim2.fromOffset(62, 0) })
	Gui.stroke(t, 2.5, Gui.INK, 0)
	onClick(back, function()
		MenuController.go("home")
	end)
	currencyRow(page, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M - 66, 0, 72) })
	local gear = iconButton(page, Gui.icon.settings, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M + 4, 0, 62) })
	onClick(gear, function()
		mods.UIController.toggleSettings(gear.AbsolutePosition.Y + 64 * canvasScale.Scale)
	end)
	return back
end

local function page(name)
	local f = make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, canvas)
	ui.pages = ui.pages or {}
	ui.pages[name] = f
	return f
end

-- A modal: a dim backdrop and a centred glass panel with a title and a close button.
local function modal(name, title, w, h)
	local back = make("TextButton", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 20 }, canvas)
	local panel = Gui.glass(back, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h), ZIndex = 20, Active = true }, 0.08)
	local t = text(panel, { Text = title, Font = Gui.FONT_TITLE, TextSize = 34, Size = UDim2.new(1, -150, 0, 44), Position = UDim2.fromOffset(24, 14), ZIndex = 21 })
	Gui.stroke(t, 2, Gui.INK, 0)
	local close = Gui.flat(panel, "Close", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 18), Size = UDim2.fromOffset(96, 36), ZIndex = 21 })
	local function hide()
		back.Visible = false
	end
	onClick(close, hide)
	back.MouseButton1Click:Connect(hide)
	return { root = back, panel = panel, title = t, hide = hide }
end

------------------------------------------------------------------------------------------
-- Home
------------------------------------------------------------------------------------------

local function buildHome()
	local p = page("home")
	-- profile card (top left)
	local card = Gui.glass(p, { Size = UDim2.fromOffset(372, 92), Position = UDim2.fromOffset(M, 62) }, 0.25)
	local shot = make("ImageLabel", {
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Color3.fromRGB(40, 46, 70),
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150",
	}, card)
	Gui.round(shot)
	Gui.stroke(shot, 2, Gui.GOLD, 0, true)
	local name = text(card, { Text = player.DisplayName, Font = Gui.FONT_HEAVY, TextSize = 24, Size = UDim2.new(1, -104, 0, 28), Position = UDim2.fromOffset(94, 14), TextTruncate = Enum.TextTruncate.AtEnd })
	local sub = text(card, { Text = "", TextSize = 15, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -104, 0, 20), Position = UDim2.fromOffset(94, 44), RichText = true })
	local badge = text(card, { Text = "", TextSize = 13, TextColor3 = Gui.GOLD, Size = UDim2.new(1, -104, 0, 16), Position = UDim2.fromOffset(94, 66) })
	currencyRow(p, { Position = UDim2.fromOffset(M, 166), AnchorPoint = Vector2.new(0, 0) }).UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	-- right: menu icons
	local icons = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M, 0, 62), Size = UDim2.fromOffset(400, 84), BackgroundTransparency = 1 }, p)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, icons)
	local entries = {
		{ Gui.icon.players, "Players", "players" },
		{ Gui.icon.locker, "Locker", "locker" },
		{ Gui.icon.shop, "Shop", "shop" },
		{ Gui.icon.settings, "Settings", "settings" },
		{ Gui.icon.help, "Help", "help" },
	}
	for i, e in ipairs(entries) do
		local b = iconButton(icons, e[1], e[2], { LayoutOrder = i })
		onClick(b, function()
			if e[3] == "settings" then
				mods.UIController.toggleSettings(b.AbsolutePosition.Y + b.AbsoluteSize.Y + 6)
			elseif e[3] == "help" then
				ui.help.root.Visible = true
			else
				MenuController.go(e[3])
			end
		end)
	end

	-- featured recruit (left, middle)
	local ev = Gui.glass(p, { Size = UDim2.fromOffset(372, 236), Position = UDim2.fromOffset(M, 232) }, 0.2)
	local stripe = make("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, ev)
	Gui.corner(stripe, 10)
	Gui.gradient(stripe, Color3.fromRGB(255, 120, 190), Color3.fromRGB(255, 196, 60), 0)
	text(stripe, { Text = "FEATURED RECRUIT", Font = Gui.FONT_HEAVY, TextSize = 16, TextColor3 = Gui.INK, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(14, 0) })
	local evName = Gui.title(ev, { Text = "", TextSize = 46, Size = UDim2.new(1, -28, 0, 50), Position = UDim2.fromOffset(14, 44) })
	local evTier = text(ev, { Text = "", Font = Gui.FONT_TITLE, TextSize = 40, Size = UDim2.fromOffset(80, 50), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 44), TextXAlignment = Enum.TextXAlignment.Right })
	Gui.stroke(evTier, 2.5, Gui.INK, 0)
	local evLine = text(ev, { Text = "", TextSize = 16, Size = UDim2.new(1, -28, 0, 20), Position = UDim2.fromOffset(14, 96) })
	local evBlurb = text(ev, { Text = "", TextSize = 14, TextColor3 = Gui.MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -28, 0, 56), Position = UDim2.fromOffset(14, 120) })
	local evGo = Gui.primary(ev, "Recruit now", { Size = UDim2.fromOffset(150, 38), Position = UDim2.new(0, 14, 1, -50), TextSize = 17 })
	local evOdds = text(ev, { Text = "", TextSize = 13, TextColor3 = Gui.MUTED, Size = UDim2.fromOffset(180, 38), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -50), TextXAlignment = Enum.TextXAlignment.Right })
	onClick(evGo, function()
		banner = "Char"
		recruitTab = "Player"
		MenuController.go("recruit")
	end)

	-- the tutorial, until it's done
	local tut = Gui.glass(p, { Size = UDim2.fromOffset(372, 118), Position = UDim2.fromOffset(M, 480), Visible = false }, 0.2)
	Gui.stroke(tut, 2, Gui.GOLD, 0.2, true)
	text(tut, { Text = "New here? Play the tutorial", Font = Gui.FONT_HEAVY, TextSize = 19, Size = UDim2.new(1, -28, 0, 24), Position = UDim2.fromOffset(14, 10) })
	local tutLine = text(tut, { Text = "", TextSize = 14, TextColor3 = Gui.MUTED, RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -28, 0, 36), Position = UDim2.fromOffset(14, 36) })
	local tutGo = Gui.primary(tut, "Start tutorial", { Size = UDim2.fromOffset(170, 36), Position = UDim2.new(0, 14, 1, -46), TextSize = 16 })
	local tutProgress = text(tut, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 14, TextColor3 = Gui.GOLD_LIGHT, Size = UDim2.fromOffset(160, 36), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -46), TextXAlignment = Enum.TextXAlignment.Right })
	onClick(tutGo, function()
		Net.get("Lobby"):FireServer("tutorial")
	end)

	-- career counters
	local stats = Gui.glass(p, { Size = UDim2.fromOffset(372, 92), Position = UDim2.fromOffset(M, 480) }, 0.25)
	local statRow = make("Frame", { Size = UDim2.new(1, -16, 1, -12), Position = UDim2.fromOffset(8, 6), BackgroundTransparency = 1 }, stats)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, statRow)
	local counters = {}
	for i, def in ipairs({ { "streak", "Win streak" }, { "wins", "Wins" }, { "kills", "Spike kills" }, { "aces", "Aces" }, { "blocks", "Blocks" } }) do
		local cell = make("Frame", { Size = UDim2.new(0.2, -4, 1, 0), BackgroundTransparency = 1, LayoutOrder = i }, statRow)
		local n = text(cell, { Text = "0", Font = Gui.FONT_TITLE, TextSize = 28, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 6), TextXAlignment = Enum.TextXAlignment.Center })
		Gui.stroke(n, 2, Gui.INK, 0)
		local l = text(cell, { Text = def[2], TextSize = 12, TextColor3 = Gui.MUTED, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 44), TextXAlignment = Enum.TextXAlignment.Center })
		local sub = text(cell, { Text = "", TextSize = 11, TextColor3 = Gui.MUTED, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 60), TextXAlignment = Enum.TextXAlignment.Center })
		counters[def[1]] = { value = n, label = l, sub = sub }
	end

	-- tip (bottom left)
	local tip = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, M, 1, -M), Size = UDim2.fromOffset(640, 40), BackgroundTransparency = 1 }, p)
	local tipTag = text(tip, { Text = "TIP", Font = Gui.FONT_HEAVY, TextSize = 14, TextColor3 = Gui.INK, BackgroundTransparency = 0, BackgroundColor3 = Gui.GOLD, Size = UDim2.fromOffset(44, 24), Position = UDim2.fromOffset(0, 8), TextXAlignment = Enum.TextXAlignment.Center })
	Gui.corner(tipTag, 5)
	local tipText = text(tip, { Text = TIPS[1], TextSize = 16, Size = UDim2.new(1, -56, 1, 0), Position = UDim2.fromOffset(56, 0), TextWrapped = true })
	Gui.stroke(tipText, 1, Gui.INK, 0.5)

	-- bottom right: Recruit Player and Match
	local match = Gui.primary(p, "", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M, 1, -M), Size = UDim2.fromOffset(300, 96) })
	local matchIcon = Gui.icon.vp(match, 52)
	matchIcon.Position = UDim2.fromOffset(18, 22)
	text(match, { Text = "MATCH", Font = Gui.FONT_TITLE, TextSize = 40, TextColor3 = Gui.INK, Size = UDim2.new(1, -90, 0, 44), Position = UDim2.fromOffset(84, 12) })
	local matchSub = text(match, { Text = "", TextSize = 15, TextColor3 = Color3.fromRGB(70, 48, 8), Size = UDim2.new(1, -90, 0, 20), Position = UDim2.fromOffset(86, 58) })
	onClick(match, function()
		MenuController.openMatch()
	end)
	local recruit = Gui.secondary(p, "", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M - 316, 1, -M), Size = UDim2.fromOffset(250, 96) })
	local rIcon = Gui.icon.recruit(recruit, 44, Gui.INK)
	rIcon.Position = UDim2.fromOffset(16, 26)
	text(recruit, { Text = "Recruit Player", Font = Gui.FONT_HEAVY, TextSize = 22, TextColor3 = Gui.INK, Size = UDim2.new(1, -76, 0, 28), Position = UDim2.fromOffset(70, 20) })
	local rSub = text(recruit, { Text = "", TextSize = 15, TextColor3 = Color3.fromRGB(80, 86, 100), Size = UDim2.new(1, -76, 0, 20), Position = UDim2.fromOffset(70, 50) })
	onClick(recruit, function()
		banner = "Char"
		recruitTab = "Player"
		MenuController.go("recruit")
	end)

	-- your AI is playing for you
	local rejoin = Gui.glass(p, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M, 1, -M - 110), Size = UDim2.fromOffset(566, 64), Visible = false }, 0.15)
	Gui.stroke(rejoin, 2, Color3.fromRGB(255, 90, 110), 0, true)
	text(rejoin, { Text = "Your AI is playing for you", Font = Gui.FONT_HEAVY, TextSize = 20, Size = UDim2.new(1, -190, 0, 26), Position = UDim2.fromOffset(18, 8) })
	text(rejoin, { Text = "Jump back in at the next serve.", TextSize = 14, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -190, 0, 20), Position = UDim2.fromOffset(18, 34) })
	local rejoinGo = Gui.primary(rejoin, "Rejoin", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 44) })
	onClick(rejoinGo, function()
		Net.get("Lobby"):FireServer("rejoin")
	end)

	ui.home = {
		name = name,
		sub = sub,
		badge = badge,
		evName = evName,
		evTier = evTier,
		evLine = evLine,
		evBlurb = evBlurb,
		evOdds = evOdds,
		tipText = tipText,
		matchSub = matchSub,
		rSub = rSub,
		rejoin = rejoin,
		featured = 1,
		stats = stats,
		counters = counters,
		tut = tut,
		tutGo = tutGo,
		tutLine = tutLine,
		tutProgress = tutProgress,
	}
end

local FEATURED = {}
for _, c in ipairs(Roster) do
	if c.Tier == "S+" then
		table.insert(FEATURED, c)
	end
end

local function myStandIn()
	if not State.match or not State.match.inMatch then
		return false
	end
	for _, team in ipairs(Config.TeamOrder) do
		for _, e in ipairs(State.roster(team)) do
			if e.standInFor == player.UserId then
				return true
			end
		end
	end
	return false
end

local function refreshHome(prof)
	local hm = ui.home
	local c = Roster.get(prof.char or player:GetAttribute("CharId")) or Roster.get(Roster.Starters[1])
	hm.sub.Text = string.format('Playing <font color="#%s"><b>%s</b></font>  %s %s', tierColor(c.Tier):ToHex(), c.Name, c.Tier, roleName(c.Role))
	local have, total = ownedCount(prof, "Char")
	if prof.saving == false then
		hm.badge.Text = "Progress isn't being saved in this session"
	elseif prof.dev then
		hm.badge.Text = "Developer: everything unlocked"
	else
		hm.badge.Text = string.format("%d of %d players recruited", have, total)
	end
	local f = FEATURED[((hm.featured - 1) % math.max(1, #FEATURED)) + 1]
	if f then
		local def = f.Ability and Config.Abilities[f.Ability]
		hm.evName.Text = f.Name
		hm.evTier.Text = f.Tier
		hm.evTier.TextColor3 = tierColor(f.Tier)
		hm.evLine.Text = string.format("%s, %d cm  -  %s", roleName(f.Role), f.Height, def and def.Name or "")
		hm.evLine.TextColor3 = def and def.Color or Gui.WHITE
		hm.evBlurb.Text = def and def.Blurb or ""
		local odds = 0
		for _, row in ipairs(Spins.table("Char")) do
			if row.item.Key == f.Id then
				odds = row.chance
			end
		end
		hm.evOdds.Text = string.format("%.2f%% per recruit%s", odds * 100, owns(prof, "Char", f.Id) and "\nRecruited" or "")
	end
	if (prof.freeSpins or 0) > 0 then
		hm.rSub.Text = string.format("%d free recruit%s", prof.freeSpins, prof.freeSpins == 1 and "" or "s")
	else
		hm.rSub.Text = prof.dev and "Free for developers" or string.format("x1  %d VP", SP.Costs[1])
	end
	-- career counters (below the tutorial card while it's there)
	local rec = prof.record or {}
	local ct = hm.counters
	ct.streak.value.Text = tostring(prof.winStreak or 0)
	ct.streak.value.TextColor3 = (prof.winStreak or 0) >= 2 and Gui.GOLD or Gui.WHITE
	ct.streak.sub.Text = string.format("best %d", prof.bestStreak or 0)
	ct.wins.value.Text = Gui.num(rec.wins or 0)
	ct.wins.sub.Text = string.format("of %s", Gui.num(rec.matches or 0))
	ct.kills.value.Text = Gui.num(rec.kills or 0)
	ct.aces.value.Text = Gui.num(rec.aces or 0)
	ct.blocks.value.Text = Gui.num(rec.blocks or 0)
	-- the tutorial card
	local tut = prof.tutorial
	hm.tut.Visible = tut ~= nil and not tut.done
	hm.stats.Position = UDim2.fromOffset(M, hm.tut.Visible and 610 or 480)
	if tut and not tut.done then
		local vp, gold, spins = Tutorial.reward()
		local _, n, total = Tutorial.progress(tut.steps)
		hm.tutLine.Text = string.format('Learn the basics in a practice match. Reward: <font color="#FFD35A"><b>%d VP, %s Gold and %d free recruits</b></font>', vp, Gui.num(gold), spins)
		hm.tutProgress.Text = n > 0 and string.format("%d of %d done", n, total) or ""
		hm.tutGo.Text = n > 0 and "Continue tutorial" or "Start tutorial"
	end
	-- Match button: your lobby's state
	local mine = lobbies.mine
	if mine then
		local states = { Open = "In lobby", Queued = "Waiting for the court", Teleporting = "Heading to your server", Arriving = "Waiting for players", Playing = "In a match" }
		hm.matchSub.Text = string.format("%s  %d/%d", states[mine.state] or "In lobby", mine.count, mine.capacity)
	else
		hm.matchSub.Text = "Quick Match or lobbies"
	end
	hm.rejoin.Visible = myStandIn()
end

------------------------------------------------------------------------------------------
-- Help
------------------------------------------------------------------------------------------

local function buildHelp()
	local m = modal("Help", "How to play", 760, 560)
	local body = text(m.panel, {
		Text = table.concat({
			"<b>Move</b>  A / D or the arrow keys",
			"<b>Spike</b>  Z, J or left click. On the ground it's your run-up jump, in the air the spike.",
			"<b>Receive</b>  S, K or right click, a little before the ball arrives (early is perfect).",
			"<b>Slide / feint</b>  C or Shift. On the ground a diving receive, in the air a roll shot.",
			"<b>Block</b>  hold W or Up, let go to jump. Longer holds jump higher.",
			"<b>Set</b>  E or V. Toward the net sets a quick, away a back set.",
			"<b>Serve</b>  F for an easy underhand serve that always goes in. Tap X for an overhand serve, hold X to toss for a jump serve (hold toward the net as you let go to toss it forward).",
			"<b>Ability</b>  Q (Iron Wall). <b>Timeout</b>  T.",
			"",
			"Recruit players with V Points, then spend Gold on their stats in Players. Every character's",
			"stats grow to its own ceiling; higher ranks cost more and go higher.",
		}, "\n"),
		RichText = true,
		TextSize = 17,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.25,
		Size = UDim2.new(1, -48, 1, -90),
		Position = UDim2.fromOffset(24, 72),
		ZIndex = 21,
	})
	ui.help = m
	return body
end

------------------------------------------------------------------------------------------
-- Recruit
------------------------------------------------------------------------------------------

local PLAYER_BANNERS = { "Char" }
local COSMETIC_BANNERS = { "Style", "Color", "Trail", "Effect" }
local BANNER_ART = {
	Char = { Color3.fromRGB(255, 196, 60), Color3.fromRGB(255, 110, 70) },
	Style = { Color3.fromRGB(120, 200, 255), Color3.fromRGB(70, 110, 255) },
	Color = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(170, 90, 255) },
	Trail = { Color3.fromRGB(110, 240, 200), Color3.fromRGB(40, 170, 220) },
	Effect = { Color3.fromRGB(255, 150, 70), Color3.fromRGB(230, 60, 60) },
}

local function buildRecruit()
	local p = page("recruit")
	header(p, "Recruit Player")

	-- left: Player / Cosmetic tabs and the banner list
	local left = make("Frame", { Position = UDim2.fromOffset(M, 136), Size = UDim2.fromOffset(300, 560), BackgroundTransparency = 1 }, p)
	local tabs, setTab = segmented(left, { { key = "Player", text = "Player" }, { key = "Cosmetic", text = "Cosmetic" } }, { Size = UDim2.new(1, 0, 0, 44) }, function(key)
		recruitTab = key
		banner = key == "Player" and "Char" or "Style"
		MenuController.refresh()
	end)
	tabs.Name = "Tabs"
	local list = make("Frame", { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 1, -58), BackgroundTransparency = 1 }, left)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rows = {}
	for i, kind in ipairs({ "Char", "Style", "Color", "Trail", "Effect" }) do
		local b = make("TextButton", { Size = UDim2.new(1, 0, 0, 92), BackgroundColor3 = Color3.new(1, 1, 1), Text = "", AutoButtonColor = false, LayoutOrder = i }, list)
		Gui.corner(b, 10)
		local art = BANNER_ART[kind]
		Gui.gradient(b, art[1], art[2], 20)
		local s = Gui.stroke(b, 3, Gui.WHITE, 1, true)
		local shade = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55 }, b)
		Gui.corner(shade, 10)
		local t = Gui.title(b, { Text = bannerName(kind):upper(), TextSize = 26, Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(14, 14) })
		t.ZIndex = 2
		local owned = text(b, { Text = "", TextSize = 14, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(14, 56), ZIndex = 2 })
		onClick(b, function()
			banner = kind
			MenuController.refresh()
		end)
		rows[kind] = { button = b, stroke = s, shade = shade, owned = owned }
	end

	-- centre: the banner's title, description, odds and tools
	local info = make("Frame", { Position = UDim2.fromOffset(M + 330, 150), Size = UDim2.fromOffset(560, 420), BackgroundTransparency = 1 }, p)
	local title = Gui.title(info, { Text = "", TextSize = 64, Size = UDim2.new(1, 0, 0, 70) })
	local desc = text(info, { Text = "", TextSize = 18, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(2, 78) })
	Gui.stroke(desc, 1, Gui.INK, 0.4)
	local odds = text(info, { Text = "", TextSize = 15, RichText = true, TextWrapped = true, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(2, 134) })
	Gui.stroke(odds, 1, Gui.INK, 0.5)
	local tableBtn = Gui.flat(info, "Probability Table", { Size = UDim2.fromOffset(190, 40), Position = UDim2.fromOffset(0, 170) })
	onClick(tableBtn, function()
		MenuController.openTable(banner)
	end)
	local autoBtn = Gui.flat(info, "", { Size = UDim2.fromOffset(250, 40), Position = UDim2.fromOffset(200, 170) })
	onClick(autoBtn, function()
		if profile().autoRolling then
			Net.get("Profile"):FireServer("stop")
		else
			Net.get("Profile"):FireServer("autoroll", banner)
		end
	end)
	text(info, { Text = "Auto-sell new pulls of", TextSize = 14, TextColor3 = Gui.MUTED, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(2, 224) })
	local sells = {}
	for i, r in ipairs(SP.AutoSellable) do
		local b = Gui.flat(info, "", { Size = UDim2.fromOffset(150, 34), Position = UDim2.fromOffset((i - 1) * 158, 246), TextSize = 14 })
		onClick(b, function()
			local on = profile().autoSell and profile().autoSell[r]
			Net.get("Profile"):FireServer("autosell", r, not on)
		end)
		sells[r] = b
	end
	local status = text(info, { Text = "", TextSize = 15, TextColor3 = Gui.GOLD_LIGHT, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(2, 292) })
	Gui.stroke(status, 1, Gui.INK, 0.4)

	-- bottom right: Recruit x1 and x10
	local x10 = Gui.primary(p, "", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M, 1, -M), Size = UDim2.fromOffset(270, 88) })
	text(x10, { Text = "Recruit x10", Font = Gui.FONT_HEAVY, TextSize = 26, TextColor3 = Gui.INK, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 10), TextXAlignment = Enum.TextXAlignment.Center })
	local x10Cost = text(x10, { Text = "", Font = Gui.FONT_NUM, TextSize = 20, TextColor3 = Gui.INK, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(14, 48), TextXAlignment = Enum.TextXAlignment.Center })
	Gui.icon.vp(x10, 24).Position = UDim2.new(0.5, -62, 0, 49)
	local x1 = Gui.secondary(p, "", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M - 286, 1, -M), Size = UDim2.fromOffset(230, 88) })
	text(x1, { Text = "Recruit x1", Font = Gui.FONT_HEAVY, TextSize = 24, TextColor3 = Gui.INK, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 10), TextXAlignment = Enum.TextXAlignment.Center })
	local x1Cost = text(x1, { Text = "", Font = Gui.FONT_NUM, TextSize = 20, TextColor3 = Gui.INK, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(14, 48), TextXAlignment = Enum.TextXAlignment.Center })
	Gui.icon.vp(x1, 24).Position = UDim2.new(0.5, -52, 0, 49)
	local lastSpin = 0
	local function spin(n)
		if os.clock() - lastSpin < 0.6 or seqActive then
			return
		end
		lastSpin = os.clock()
		sendProfile("spin", banner, n)
	end
	x1.MouseButton1Click:Connect(function()
		spin(1)
	end)
	x10.MouseButton1Click:Connect(function()
		spin(10)
	end)

	ui.recruit = { setTab = setTab, rows = rows, title = title, desc = desc, odds = odds, auto = autoBtn, sells = sells, status = status, x1 = x1, x10 = x10, x1Cost = x1Cost, x10Cost = x10Cost }
end

local function refreshRecruit(prof)
	local R = ui.recruit
	R.setTab(recruitTab)
	local visible = recruitTab == "Player" and PLAYER_BANNERS or COSMETIC_BANNERS
	local show = {}
	for _, k in ipairs(visible) do
		show[k] = true
	end
	if not show[banner] then
		banner = visible[1]
	end
	for kind, row in pairs(R.rows) do
		row.button.Visible = show[kind] == true
		local on = kind == banner
		row.stroke.Transparency = on and 0 or 1
		row.stroke.Color = on and Gui.GOLD_LIGHT or Gui.WHITE
		row.shade.BackgroundTransparency = on and 0.75 or 0.5
		local have, total = ownedCount(prof, kind)
		row.owned.Text = string.format("%d of %d unlocked", have, total)
	end
	R.title.Text = bannerName(banner):upper()
	R.desc.Text = banner == "Char" and "Recruit named players: each has a role, a height, stat ceilings and (S and S+) an ability. Upgrade them with Gold in Players." or SP.Banners[banner].Blurb
	local o = Spins.odds(banner)
	local parts = {}
	for _, r in ipairs(Config.Rarity.Order) do
		if o[r] > 0 then
			table.insert(parts, string.format('<font color="#%s">%s %.1f%%</font>', Spins.rarityColor(r):ToHex(), r, o[r] * 100))
		end
	end
	R.odds.Text = table.concat(parts, "    ")
	if prof.autoRolling then
		local n = prof.reveal and prof.reveal.auto or 0
		R.auto.Text = string.format("Stop auto-roll (%d)", n)
		R.auto.TextColor3 = Color3.fromRGB(255, 120, 130)
	else
		R.auto.Text = "Auto-roll until " .. SP.AutoRollTarget
		R.auto.TextColor3 = Config.Rarity.Colors.Legendary
	end
	for r, b in pairs(R.sells) do
		local on = prof.autoSell and prof.autoSell[r]
		b.Text = string.format("%s  %s", r, on and "on" or "off")
		b.TextColor3 = on and Spins.rarityColor(r) or Gui.MUTED
	end
	local free = prof.dev == true
	local freeSpins = prof.freeSpins or 0
	R.x1Cost.Text = (free and "Free") or (freeSpins > 0 and string.format("Free (%d)", freeSpins)) or Gui.num(SP.Costs[1])
	R.x10Cost.Text = free and "Free" or Gui.num(SP.Costs[10])
	R.x1.BackgroundTransparency = (free or freeSpins > 0 or (prof.vp or 0) >= SP.Costs[1]) and 0 or 0.45
	R.x10.BackgroundTransparency = (free or (prof.vp or 0) >= SP.Costs[10]) and 0 or 0.45
end

------------------------------------------------------------------------------------------
-- Probability table
------------------------------------------------------------------------------------------

local function buildTable()
	local m = modal("Odds", "Probability Table", 720, 640)
	local sub = text(m.panel, { Text = "", TextSize = 15, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -48, 0, 20), Position = UDim2.fromOffset(24, 58), ZIndex = 21 })
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 88),
		Size = UDim2.new(1, -40, 1, -104),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 21,
	}, m.panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rows = {}
	local maxRows = 0
	for _, kind in ipairs(Spins.Kinds) do
		maxRows = math.max(maxRows, #Spins.table(kind))
	end
	for i = 1, maxRows do
		local row = make("Frame", { Size = UDim2.new(1, -10, 0, 44), BackgroundColor3 = Color3.fromRGB(26, 30, 48), BackgroundTransparency = 0.2, LayoutOrder = i, Visible = false, ZIndex = 21 }, list)
		Gui.corner(row, 8)
		local bar = make("Frame", { Size = UDim2.fromOffset(6, 44), BackgroundColor3 = Gui.WHITE, ZIndex = 22 }, row)
		Gui.corner(bar, 3)
		local n = text(row, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 17, Size = UDim2.new(0.34, 0, 1, 0), Position = UDim2.fromOffset(18, 0), ZIndex = 22 })
		local d = text(row, { Text = "", TextSize = 14, TextColor3 = Gui.MUTED, Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromScale(0.36, 0), ZIndex = 22 })
		local ch = text(row, { Text = "", Font = Gui.FONT_NUM, TextSize = 16, Size = UDim2.new(0.12, 0, 1, 0), Position = UDim2.fromScale(0.74, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 22 })
		local own = text(row, { Text = "", TextSize = 13, TextColor3 = Color3.fromRGB(110, 240, 180), Size = UDim2.new(0.12, -12, 1, 0), Position = UDim2.fromScale(0.88, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 22 })
		rows[i] = { frame = row, bar = bar, name = n, desc = d, chance = ch, own = own }
	end
	ui.odds = { modal = m, sub = sub, rows = rows }
end

function MenuController.openTable(kind)
	local O = ui.odds
	local prof = profile()
	O.modal.title.Text = bannerName(kind) .. ": Probability Table"
	O.sub.Text = string.format("Every pull is one of these. Duplicates turn into V Points (%s).", table.concat((function()
		local parts = {}
		for _, r in ipairs(Config.Rarity.Order) do
			table.insert(parts, r .. " " .. Spins.sellValue(r))
		end
		return parts
	end)(), ", "))
	local data = Spins.table(kind)
	for i, row in ipairs(O.rows) do
		local d = data[i]
		row.frame.Visible = d ~= nil
		if d then
			local color = Spins.rarityColor(d.item.Rarity)
			row.bar.BackgroundColor3 = color
			row.name.Text = d.item.Name
			row.name.TextColor3 = color
			if kind == "Char" and d.item.Char then
				local c = d.item.Char
				local def = c.Ability and Config.Abilities[c.Ability]
				row.desc.Text = string.format("%s  %s%s", c.Tier, roleName(c.Role), def and ("  -  " .. def.Name) or "")
			else
				row.desc.Text = d.item.Rarity
			end
			row.chance.Text = d.chance >= 0.01 and string.format("%.1f%%", d.chance * 100) or string.format("%.2f%%", d.chance * 100)
			row.own.Text = owns(prof, kind, d.item.Key) and "Owned" or ""
		end
	end
	O.modal.root.Visible = true
end

------------------------------------------------------------------------------------------
-- The recruit sequence
------------------------------------------------------------------------------------------

local ROLE_POSE = { WS = "Cock", MB = "Block", SE = "SetPush", Solo = "Cock" }

local function rigGround(rig)
	local hum = rig.model:FindFirstChildOfClass("Humanoid")
	return (hum and hum.HipHeight or 2) + rig.root.Size.Y / 2
end

-- Concentric discs fading outward: a soft radial glow (UIGradient is linear only).
local function glowDisc(parent, size, color, z)
	local g = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ZIndex = z }, parent)
	local rings = {}
	for i = 1, 6 do
		local d = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(i / 6, i / 6),
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			ZIndex = z,
		}, g)
		Gui.round(d)
		rings[i] = d
	end
	local function set(alpha, c)
		for i, d in ipairs(rings) do
			d.BackgroundTransparency = 1 - alpha * (0.34 - i * 0.045)
			if c then
				d.BackgroundColor3 = c
			end
		end
	end
	set(0)
	return g, set
end

local function trayCard(parent, i)
	local c = make("Frame", { Size = UDim2.fromOffset(104, 138), BackgroundColor3 = Color3.fromRGB(18, 20, 34), BackgroundTransparency = 0.08, LayoutOrder = i, Visible = false, ZIndex = 33 }, parent)
	Gui.corner(c, 8)
	local s = Gui.stroke(c, 2, Gui.WHITE, 0, true)
	local bar = make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Gui.WHITE, ZIndex = 34 }, c)
	Gui.corner(bar, 8)
	local rar = text(bar, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 12, TextColor3 = Gui.INK, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 35 })
	local big = text(c, { Text = "", Font = Gui.FONT_TITLE, TextSize = 34, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 26), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 34 })
	Gui.stroke(big, 2, Gui.INK, 0)
	local name = text(c, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 15, TextWrapped = true, Size = UDim2.new(1, -8, 0, 36), Position = UDim2.fromOffset(4, 68), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 34 })
	local foot = text(c, { Text = "", TextSize = 12, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 1, -24), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 34 })
	local scale = make("UIScale", { Scale = 1 }, c)
	return { frame = c, stroke = s, bar = bar, rar = rar, big = big, name = name, foot = foot, scale = scale }
end

local function buildSequence()
	local root = make("TextButton", { Name = "Recruiting", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 30 }, canvas)
	root.MouseButton1Click:Connect(function()
		if seqActive and seqActive.stage ~= "results" then
			seqActive.clicked = true
		end
	end)
	local black = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 30 }, root)
	local sparks = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 31 }, root)
	local glow, setGlow = glowDisc(root, 900, Gui.WHITE, 31)

	local cont = text(root, { Text = "Click to Continue", Font = Gui.FONT_HEAVY, TextSize = 26, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -60), Size = UDim2.fromOffset(500, 40), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 33 })
	Gui.stroke(cont, 2, Gui.INK, 0.2)
	local skip = Gui.flat(root, "Skip", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M, 0, 64), Size = UDim2.fromOffset(120, 44), TextSize = 18, ZIndex = 36 })
	onClick(skip, function()
		if seqActive then
			seqActive.skipping = true
		end
	end)

	-- the S cinematic: a yellow screen, a light beam, your avatar's silhouette spiking
	local cin = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 32 }, root)
	Gui.gradient(cin, Color3.fromRGB(255, 232, 110), Color3.fromRGB(255, 176, 30), 70)
	local cinGlow, setCinGlow = glowDisc(cin, 760, Color3.new(1, 1, 1), 32)
	cinGlow.Position = UDim2.fromScale(0.58, 0.5)
	local beam = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 140, 3, 0), Position = UDim2.fromScale(-0.3, 0.5), Rotation = 24, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 33 }, cin)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, beam)
	local vp = make("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ImageColor3 = Color3.new(0, 0, 0), Ambient = Color3.new(1, 1, 1), LightColor = Color3.new(1, 1, 1), ZIndex = 34 }, cin)
	local cam = make("Camera", { FieldOfView = 45 }, vp)
	vp.CurrentCamera = cam
	local world = make("WorldModel", {}, vp)
	local ball = make("Part", { Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, Anchored = true, CanCollide = false, Color = Color3.new(0, 0, 0) }, world)
	local flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 37 }, root)

	-- the reveal card
	local card = Gui.glass(root, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(820, 470), Visible = false, ZIndex = 34 }, 0.05)
	local cardScale = make("UIScale", { Scale = 1 }, card)
	local art = make("Frame", { Size = UDim2.new(0, 330, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 34 }, card)
	Gui.corner(art, 10)
	local artGrad = Gui.gradient(art, Color3.fromRGB(255, 220, 110), Color3.fromRGB(40, 30, 20), 90)
	local cvp = make("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-0.4, -1, -0.6), ZIndex = 35 }, art)
	local ccam = make("Camera", { FieldOfView = 38 }, cvp)
	cvp.CurrentCamera = ccam
	local cworld = make("WorldModel", {}, cvp)
	local rarity = text(card, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 18, Size = UDim2.fromOffset(300, 24), Position = UDim2.fromOffset(360, 26), ZIndex = 35 })
	local name = Gui.title(card, { Text = "", TextSize = 60, Size = UDim2.fromOffset(330, 70), Position = UDim2.fromOffset(356, 50), ZIndex = 35 })
	local tier = text(card, { Text = "", Font = Gui.FONT_TITLE, TextSize = 84, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -26, 0, 26), Size = UDim2.fromOffset(150, 96), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35 })
	Gui.stroke(tier, 3, Gui.INK, 0)
	local line = text(card, { Text = "", TextSize = 18, Size = UDim2.fromOffset(440, 22), Position = UDim2.fromOffset(360, 124), ZIndex = 35 })
	local ability = text(card, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 20, Size = UDim2.fromOffset(440, 24), Position = UDim2.fromOffset(360, 156), ZIndex = 35 })
	local blurb = text(card, { Text = "", TextSize = 15, TextColor3 = Gui.MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.fromOffset(440, 58), Position = UDim2.fromOffset(360, 182), ZIndex = 35 })
	local bars = {}
	for i, stat in ipairs(Config.Stats.Order) do
		local y = 250 + (i - 1) * 34
		local l = text(card, { Text = stat, Font = Gui.FONT_HEAVY, TextSize = 15, Size = UDim2.fromOffset(80, 22), Position = UDim2.fromOffset(360, y), ZIndex = 35 })
		local track = make("Frame", { Size = UDim2.fromOffset(270, 10), Position = UDim2.fromOffset(446, y + 6), BackgroundColor3 = Color3.fromRGB(40, 44, 66), ZIndex = 35 }, card)
		Gui.round(track)
		local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Gui.GOLD, ZIndex = 36 }, track)
		Gui.round(fill)
		local v = text(card, { Text = "", Font = Gui.FONT_NUM, TextSize = 15, Size = UDim2.fromOffset(70, 22), Position = UDim2.fromOffset(726, y), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35 })
		bars[stat] = { label = l, track = track, fill = fill, value = v }
	end
	local foot = text(card, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 20, Size = UDim2.fromOffset(440, 26), Position = UDim2.new(0, 360, 1, -46), ZIndex = 35 })

	-- the pulls, as they open
	local tray = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(1140, 140), BackgroundTransparency = 1, ZIndex = 33 }, root)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, tray)
	local cards = {}
	for i = 1, 10 do
		cards[i] = trayCard(tray, i)
	end
	local summary = text(root, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 20, RichText = true, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -272), Size = UDim2.fromOffset(1000, 30), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 33 })
	Gui.stroke(summary, 2, Gui.INK, 0.2)
	local confirm = Gui.primary(root, "Confirm", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(240, 60), TextSize = 24, Visible = false, ZIndex = 36 })
	onClick(confirm, function()
		if seqActive then
			seqActive.clicked = true
		end
	end)

	ui.seq = {
		root = root,
		black = black,
		sparks = sparks,
		setGlow = setGlow,
		cont = cont,
		skip = skip,
		cin = { root = cin, beam = beam, cam = cam, world = world, ball = ball, setGlow = setCinGlow },
		flash = flash,
		card = { root = card, scale = cardScale, artGrad = artGrad, cam = ccam, world = cworld, rarity = rarity, name = name, tier = tier, line = line, ability = ability, blurb = blurb, bars = bars, foot = foot },
		tray = cards,
		summary = summary,
		confirm = confirm,
	}
end

local function alive(seq)
	return seqActive == seq and not seq.cancelled
end

-- Wait `t` seconds (a skip cuts it short). False once the sequence is gone.
local function hold(seq, t)
	local t0 = os.clock()
	while os.clock() - t0 < t do
		if not alive(seq) or seq.skipping then
			return alive(seq)
		end
		RunService.RenderStepped:Wait()
	end
	return alive(seq)
end

-- Wait for a click (or, if allowed, a skip).
local function waitClick(seq, allowSkip)
	seq.clicked = false
	while alive(seq) and not seq.clicked and not (allowSkip and seq.skipping) do
		RunService.RenderStepped:Wait()
	end
	return alive(seq)
end

local function sparkleBurst(gold)
	local S = ui.seq
	S.sparks:ClearAllChildren()
	local color = gold and Color3.fromRGB(255, 214, 90) or Color3.fromRGB(220, 236, 255)
	S.setGlow(0, color)
	local rng = Random.new()
	for i = 1, 34 do
		local size = rng:NextInteger(18, gold and 90 or 64)
		local s = Gui.sparkle(S.sparks, size, color)
		s.ZIndex = 31
		for _, d in ipairs(s:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = 31
			end
		end
		s.Position = UDim2.fromScale(0.5 + (rng:NextNumber() - 0.5) * 0.9, 0.5 + (rng:NextNumber() - 0.5) * 0.8)
		local scale = make("UIScale", { Scale = 0 }, s)
		local delay = rng:NextNumber() * 0.7
		task.delay(delay, function()
			tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			tween(s, 0.9, { Rotation = rng:NextInteger(-90, 90) })
			task.delay(0.35 + rng:NextNumber() * 0.3, function()
				tween(scale, 0.35, { Scale = 0 })
			end)
		end)
		if i == 1 then
			s.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	-- the glow swells (gold when an S is inside)
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < 1.1 and S.root.Visible do
			local a = math.clamp((os.clock() - t0) / 0.8, 0, 1)
			S.setGlow(a * (gold and 1 or 0.55))
			RunService.RenderStepped:Wait()
		end
		S.setGlow(0)
	end)
end

local function pullInfo(kind, it)
	local item = Spins.item(kind, it.key)
	local rarity = item and item.Rarity or "Common"
	return item, rarity, Spins.rarityRank(rarity), Spins.rarityColor(rarity)
end

local function fillTray(i, kind, it)
	local card = ui.seq.tray[i]
	local item, rarity, rank, color = pullInfo(kind, it)
	card.frame.Visible = true
	card.stroke.Color = color
	card.stroke.Thickness = rank >= 4 and 3 or 2
	card.bar.BackgroundColor3 = color
	card.rar.Text = rarity:upper()
	if kind == "Char" and item and item.Char then
		card.big.Text = item.Char.Tier
		card.big.TextColor3 = tierColor(item.Char.Tier)
		card.name.Text = item.Name .. "\n" .. Config.Roles[item.Char.Role].Short
	else
		card.big.Text = ""
		card.name.Text = item and item.Name or "?"
	end
	if it.dup then
		card.foot.Text = "+" .. Spins.sellValue(rarity) .. " VP"
	elseif it.sold then
		card.foot.Text = "Sold +" .. Spins.sellValue(rarity)
	else
		card.foot.Text = "NEW"
	end
	card.foot.TextColor3 = (it.dup or it.sold) and Gui.MUTED or Gui.GOLD_LIGHT
	card.scale.Scale = 0.3
	tween(card.scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Pose a rig at the origin (feet on y = 0) facing -z.
local function poseAt(rig, joints, up, yaw)
	mods.AnimationController.poseModel(rig, joints, CFrame.new(0, rigGround(rig) + (up or 0), 0) * CFrame.Angles(0, math.rad(yaw or 0), 0))
end

-- The S cinematic: the silhouette leaps, draws back and hammers a black ball down as a beam of
-- light sweeps the screen. Returns false if the sequence was cancelled.
local function cinematic(seq)
	local S = ui.seq
	local C = S.cin
	local AC = mods.AnimationController
	C.root.Visible = true
	C.root.BackgroundTransparency = 1
	tween(C.root, 0.12, { BackgroundTransparency = 0 })
	C.setGlow(0)
	C.beam.Position = UDim2.fromScale(-0.3, 0.5)
	local rig = mods.SceneController.cloneAvatar(true)
	if rig then
		rig.model.Parent = C.world
	end
	C.cam.CFrame = CFrame.lookAt(Vector3.new(-13, 2.5, -1), Vector3.new(0, 6.2, -2.5))
	local style = (profile().equip and profile().equip.Style) or "Classic"
	local cock = AC.poseJoints("Cock_" .. style) or AC.poseJoints("Cock")
	local swing = AC.clipDuration("Swing_" .. style) and ("Swing_" .. style) or "Swing"
	local DUR, CONTACT = 2.2, 1.05
	local t0 = os.clock()
	local snapped = false
	if mods.AudioController then
		mods.AudioController.play("Boom", { volume = 0.8 })
	end
	while os.clock() - t0 < DUR do
		if not alive(seq) then
			break
		end
		if seq.skipping then
			break
		end
		local t = os.clock() - t0
		local joints, up = AC.poseJoints("Gather"), 0
		if t > 0.2 then
			local a = math.clamp((t - 0.2) / 1.6, 0, 1)
			up = 4 * 6.5 * a * (1 - a)
			if t < 0.45 then
				joints = AC.poseJoints("Rise")
			elseif t < 0.85 then
				joints = AC.blendJoints(AC.poseJoints("Rise"), cock, (t - 0.45) / 0.4)
			elseif t < CONTACT then
				joints = cock
			else
				local st = t - CONTACT
				joints = st < AC.clipDuration(swing) and AC.clipJoints(swing, st) or AC.poseJoints("SpikeFollow")
			end
		end
		local ground = 3
		if rig then
			poseAt(rig, joints, up)
			ground = rigGround(rig)
		end
		local hand = Vector3.new(0, ground + up + 3.1, -1.4)
		if t < CONTACT then
			local a = math.clamp((t - 0.3) / (CONTACT - 0.3), 0, 1)
			C.ball.Position = hand + Vector3.new(0, 7 * (1 - a), 2.5 * (1 - a))
		else
			local a = math.clamp((t - CONTACT) / 0.22, 0, 1)
			C.ball.Position = hand:Lerp(Vector3.new(0, 0.6, -16), a)
		end
		C.setGlow(math.clamp((t - 0.3) / 0.6, 0, 1) * 0.9)
		if t >= CONTACT and not snapped then
			snapped = true
			if mods.AudioController then
				mods.AudioController.play("SpikeHeavy", { volume = 1.2 })
			end
			S.flash.BackgroundTransparency = 0.2
			tween(S.flash, 0.35, { BackgroundTransparency = 1 })
			tween(C.beam, 0.55, { Position = UDim2.fromScale(1.3, 0.5) }, Enum.EasingStyle.Quint)
		end
		RunService.RenderStepped:Wait()
	end
	-- white out into the reveal
	S.flash.BackgroundTransparency = 0
	tween(S.flash, 0.5, { BackgroundTransparency = 1 })
	C.root.Visible = false
	if rig then
		rig.model:Destroy()
	end
	return alive(seq)
end

local cardRig = nil

local function showCard(kind, it)
	local K = ui.seq.card
	local item, rarity, _, color = pullInfo(kind, it)
	K.root.Visible = true
	K.scale.Scale = 0.6
	tween(K.scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	K.rarity.Text = rarity:upper()
	K.rarity.TextColor3 = color
	K.artGrad.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.75))
	local pose = "ShowCool"
	if kind == "Char" and item and item.Char then
		local c = item.Char
		local def = c.Ability and Config.Abilities[c.Ability]
		K.name.Text = c.Name
		K.tier.Text = c.Tier
		K.tier.TextColor3 = tierColor(c.Tier)
		K.line.Text = string.format("%s, %d cm", roleName(c.Role), c.Height)
		K.ability.Text = def and def.Name or "No ability"
		K.ability.TextColor3 = def and def.Color or Gui.MUTED
		K.blurb.Text = def and def.Blurb or "Abilities come with S and S+ players."
		for stat, b in pairs(K.bars) do
			b.label.Visible, b.track.Visible, b.value.Visible = true, true, true
			b.fill.Size = UDim2.fromScale(math.clamp((c[stat] - Config.Stats.Min) / (Config.Stats.Ref - Config.Stats.Min), 0.03, 1), 1)
			b.fill.BackgroundColor3 = tierColor(c.Tier)
			b.value.Text = "max " .. c[stat]
		end
		pose = ROLE_POSE[c.Role] or "ShowCool"
		if pose == "Cock" then
			local style = profile().equip and profile().equip.Style
			if style and mods.AnimationController.poseJoints("Cock_" .. style) then
				pose = "Cock_" .. style
			end
		end
	else
		K.name.Text = item and item.Name or "?"
		K.tier.Text = ""
		K.line.Text = SP.Banners[kind].Name
		K.ability.Text = "Equip it in the Locker"
		K.ability.TextColor3 = Gui.GOLD_LIGHT
		K.blurb.Text = SP.Banners[kind].Blurb
		for _, b in pairs(K.bars) do
			b.label.Visible, b.track.Visible, b.value.Visible = false, false, false
		end
		if kind == "Style" and item and mods.AnimationController.poseJoints("Cock_" .. item.Key) then
			pose = "Cock_" .. item.Key
		end
	end
	local sell = Spins.sellValue(rarity)
	if it.dup then
		K.foot.Text = string.format("Duplicate: +%d VP", sell)
		K.foot.TextColor3 = Gui.MUTED
	elseif it.sold then
		K.foot.Text = string.format("Auto-sold: +%d VP", sell)
		K.foot.TextColor3 = Gui.MUTED
	else
		K.foot.Text = "NEW"
		K.foot.TextColor3 = Gui.GOLD_LIGHT
	end
	-- your avatar in the pose
	if cardRig then
		cardRig.model:Destroy()
		cardRig = nil
	end
	cardRig = mods.SceneController.cloneAvatar(false)
	if cardRig then
		cardRig.model.Parent = K.world
		poseAt(cardRig, mods.AnimationController.poseJoints(pose), 0, 20)
		K.cam.CFrame = CFrame.lookAt(Vector3.new(4.5, 4.2, -11), Vector3.new(0, 3.2, 0))
	end
	if mods.AudioController then
		mods.AudioController.play(Spins.rarityRank(rarity) >= 4 and "CrowdCheer" or "Point", { volume = 0.9 })
	end
end

local function hideCard()
	ui.seq.card.root.Visible = false
	if cardRig then
		cardRig.model:Destroy()
		cardRig = nil
	end
end

local function endSequence(seq)
	local S = ui.seq
	if seq then
		seq.cancelled = true
	end
	if seqActive == seq then
		seqActive = nil
	end
	S.root.Visible = false
	S.cin.root.Visible = false
	hideCard()
	if ui.pages[screen] then
		ui.pages[screen].Visible = true -- the screen comes back once the recruit is over
	end
	S.sparks:ClearAllChildren()
	mods.SceneController.clearBalls()
	MenuController.applyScene() -- back to the screen's own scene and shot
	MenuController.refresh()
end

local function playSequence(reveal)
	if seqActive then
		endSequence(seqActive)
	end
	local seq = { stage = "open" }
	seqActive = seq
	local S = ui.seq
	local kind, items = reveal.banner, reveal.items or {}
	local colors, strength, best = {}, {}, 1
	for i, it in ipairs(items) do
		local _, _, rank, color = pullInfo(kind, it)
		colors[i] = color
		strength[i] = rank >= 4 and 1 or (rank == 3 and 0.65 or (rank == 2 and 0.4 or 0.2))
		best = math.max(best, rank)
	end
	local gold = best >= 4
	-- the recruit has the screen to itself: no menus, panels or buttons behind it
	for _, f in pairs(ui.pages) do
		f.Visible = false
	end
	ui.match.modal.root.Visible = false
	ui.odds.modal.root.Visible = false
	ui.help.root.Visible = false
	mods.UIController.closeSettings()
	S.root.Visible = true
	S.black.BackgroundTransparency = 0
	S.cont.Visible = false
	S.skip.Visible = true
	S.summary.Visible = false
	S.confirm.Visible = false
	S.cin.root.Visible = false
	hideCard()
	for _, c in ipairs(S.tray) do
		c.frame.Visible = false
	end

	-- 1. sparkles on black (gold when an S is inside)
	sparkleBurst(gold)
	if mods.AudioController then
		mods.AudioController.play(gold and "Thunder" or "Whoosh", { volume = gold and 0.5 or 0.7 })
	end
	if not hold(seq, 1.15) then
		return
	end
	-- 2. the balls fly under the gym ceiling
	mods.SceneController.show("gym")
	mods.SceneController.shot("ceiling")
	mods.SceneController.flyBalls(colors, strength, 1.5)
	tween(S.black, 0.35, { BackgroundTransparency = 1 })
	S.sparks:ClearAllChildren()
	if not hold(seq, 1.75) then
		return
	end
	-- 3. lined up over the stage
	S.black.BackgroundTransparency = 1
	mods.SceneController.shot("lineup")
	mods.SceneController.lineUp(colors, strength)
	S.cont.Visible = true
	if not waitClick(seq, true) then
		return
	end
	S.cont.Visible = false
	-- 4. open them one by one; an S gets its cinematic and card first
	for i, it in ipairs(items) do
		local _, _, rank, color = pullInfo(kind, it)
		mods.SceneController.popBall(i, color)
		if rank >= 4 then
			seq.skipping = false -- a skip lands here
			if not cinematic(seq) then
				return
			end
			seq.skipping = false
		end
		fillTray(i, kind, it)
		if rank >= 4 or #items == 1 then
			showCard(kind, it)
			if not waitClick(seq, true) then
				return
			end
			hideCard()
		elseif not seq.skipping then
			if mods.AudioController then
				mods.AudioController.play("UIClick", { minGap = 0 })
			end
			if not hold(seq, 0.2) then
				return
			end
		end
	end
	-- 5. the results
	seq.skipping = false
	seq.stage = "results"
	S.skip.Visible = false
	local counts = {}
	for _, it in ipairs(items) do
		local _, rarity = pullInfo(kind, it)
		counts[rarity] = (counts[rarity] or 0) + 1
	end
	local parts = {}
	for r = #Config.Rarity.Order, 1, -1 do
		local name = Config.Rarity.Order[r]
		if counts[name] then
			table.insert(parts, string.format('<font color="#%s">%d %s</font>', Spins.rarityColor(name):ToHex(), counts[name], name))
		end
	end
	local refund = (reveal.refund or 0) > 0 and not profile().dev and string.format("   +%d VP from duplicates", reveal.refund) or ""
	S.summary.Text = table.concat(parts, "   ") .. refund
	S.summary.Visible = true
	S.confirm.Visible = true
	waitClick(seq, false)
	endSequence(seq)
end

------------------------------------------------------------------------------------------
-- Players: pick who you play and spend Gold on their stats
------------------------------------------------------------------------------------------

local function sortedRoster(prof)
	local list = {}
	for _, c in ipairs(Roster) do
		table.insert(list, c)
	end
	table.sort(list, function(a, b)
		local oa, ob = owns(prof, "Char", a.Id), owns(prof, "Char", b.Id)
		if oa ~= ob then
			return oa
		end
		local ta, tb = Characters.tierIndex(a.Tier) or 0, Characters.tierIndex(b.Tier) or 0
		if ta ~= tb then
			return ta > tb
		end
		return a.Name < b.Name
	end)
	return list
end

local function buildPlayers()
	local p = page("players")
	header(p, "Players")

	-- the roster grid
	local gridPanel = Gui.glass(p, { Position = UDim2.fromOffset(M, 136), Size = UDim2.new(0.5, -M - 12, 1, -136 - M) }, 0.2)
	local count = text(gridPanel, { Text = "", TextSize = 15, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -32, 0, 22), Position = UDim2.fromOffset(16, 10) })
	local grid = make("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -24, 1, -52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, gridPanel)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(138, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local cards = {}
	for _, c in ipairs(Roster) do
		local b = make("TextButton", { BackgroundColor3 = Color3.fromRGB(22, 26, 42), BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false }, grid)
		Gui.corner(b, 10)
		local s = Gui.stroke(b, 2, tierColor(c.Tier), 0.2, true)
		local band = make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = tierColor(c.Tier) }, b)
		Gui.corner(band, 3)
		local tierL = text(b, { Text = c.Tier, Font = Gui.FONT_TITLE, TextSize = 38, TextColor3 = tierColor(c.Tier), Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(10, 12) })
		Gui.stroke(tierL, 2, Gui.INK, 0)
		text(b, { Text = c.Name, Font = Gui.FONT_HEAVY, TextSize = 18, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(10, 64), TextTruncate = Enum.TextTruncate.AtEnd })
		local def = c.Ability and Config.Abilities[c.Ability]
		text(b, { Text = roleName(c.Role), TextSize = 13, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 88) })
		text(b, { Text = def and def.Name or "", TextSize = 12, TextColor3 = def and def.Color or Gui.MUTED, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 106), TextTruncate = Enum.TextTruncate.AtEnd })
		local tag = text(b, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 12, TextColor3 = Gui.INK, BackgroundTransparency = 0, BackgroundColor3 = Gui.GOLD, Size = UDim2.fromOffset(62, 20), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
		Gui.corner(tag, 4)
		local lock = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Visible = false, ZIndex = 3 }, b)
		Gui.corner(lock, 10)
		text(lock, { Text = "Not recruited", TextSize = 13, TextColor3 = Gui.MUTED, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -24), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		onClick(b, function()
			selectedChar = c.Id
			MenuController.refresh()
		end)
		cards[c.Id] = { button = b, stroke = s, tag = tag, lock = lock }
	end

	-- the selected character
	local d = Gui.glass(p, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M, 0, 136), Size = UDim2.new(0.5, -M - 12, 1, -136 - M) }, 0.12)
	local name = Gui.title(d, { Text = "", TextSize = 50, Size = UDim2.new(1, -200, 0, 58), Position = UDim2.fromOffset(22, 12) })
	local tier = text(d, { Text = "", Font = Gui.FONT_TITLE, TextSize = 64, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 6), Size = UDim2.fromOffset(140, 72), TextXAlignment = Enum.TextXAlignment.Right })
	Gui.stroke(tier, 3, Gui.INK, 0)
	local line = text(d, { Text = "", TextSize = 17, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -44, 0, 22), Position = UDim2.fromOffset(24, 72) })
	local ability = text(d, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 18, Size = UDim2.new(1, -44, 0, 22), Position = UDim2.fromOffset(24, 100) })
	local blurb = text(d, { Text = "", TextSize = 14, TextColor3 = Gui.MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -44, 0, 40), Position = UDim2.fromOffset(24, 124) })
	local select = Gui.primary(d, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 92), Size = UDim2.fromOffset(170, 44), TextSize = 18 })
	onClick(select, function()
		if selectedChar and owns(profile(), "Char", selectedChar) then
			Net.get("Profile"):FireServer("select", selectedChar)
		elseif selectedChar then
			banner = "Char"
			recruitTab = "Player"
			MenuController.go("recruit")
		end
	end)

	local rows = {}
	local steps = Config.Upgrades.Steps
	for i, stat in ipairs(Config.Stats.Order) do
		local y = 176 + (i - 1) * 86
		local row = make("Frame", { Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, 78), BackgroundColor3 = Color3.fromRGB(20, 24, 40), BackgroundTransparency = 0.25 }, d)
		Gui.corner(row, 8)
		text(row, { Text = stat, Font = Gui.FONT_HEAVY, TextSize = 18, Size = UDim2.fromOffset(100, 24), Position = UDim2.fromOffset(14, 8) })
		local value = text(row, { Text = "", Font = Gui.FONT_NUM, TextSize = 18, Size = UDim2.fromOffset(120, 24), Position = UDim2.fromOffset(110, 8) })
		local track = make("Frame", { Size = UDim2.new(1, -250, 0, 10), Position = UDim2.fromOffset(14, 42), BackgroundColor3 = Color3.fromRGB(44, 48, 70) }, row)
		Gui.round(track)
		local cap = make("Frame", { Size = UDim2.fromScale(0.8, 1), BackgroundColor3 = Color3.fromRGB(80, 86, 116) }, track)
		Gui.round(cap)
		local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Gui.GOLD }, track)
		Gui.round(fill)
		local cost = text(row, { Text = "", TextSize = 13, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -250, 0, 18), Position = UDim2.fromOffset(14, 56) })
		local buttons = {}
		local order = {}
		for j = #steps, 1, -1 do
			table.insert(order, -steps[j])
		end
		for _, n in ipairs(steps) do
			table.insert(order, n)
		end
		for k, delta in ipairs(order) do
			local b = Gui.flat(row, (delta > 0 and "+" or "") .. tostring(delta), {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10 - (#order - k) * 38, 0.5, 0),
				Size = UDim2.fromOffset(34, 32),
				TextSize = 14,
				Font = Gui.FONT_HEAVY,
			})
			if delta > 0 then
				b.TextColor3 = Gui.GOLD_LIGHT
			end
			b.MouseButton1Click:Connect(function()
				if selectedChar then
					sendProfile("upgrade", selectedChar, stat, delta)
				end
			end)
			buttons[delta] = b
		end
		rows[stat] = { value = value, cap = cap, fill = fill, cost = cost, buttons = buttons }
	end
	local derived = text(d, { Text = "", TextSize = 15, RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -44, 0, 96), Position = UDim2.new(0, 24, 1, -108) })
	ui.players = { count = count, cards = cards, grid = grid, name = name, tier = tier, line = line, ability = ability, blurb = blurb, select = select, rows = rows, derived = derived }
end

local function refreshPlayers(prof)
	local pl = ui.players
	local have, total = ownedCount(prof, "Char")
	pl.count.Text = string.format("%d of %d recruited. Gold upgrades raise each stat up to the player's ceiling.", have, total)
	local current = prof.char or player:GetAttribute("CharId")
	selectedChar = selectedChar or current
	for i, c in ipairs(sortedRoster(prof)) do
		local card = pl.cards[c.Id]
		card.button.LayoutOrder = i
		local mine = owns(prof, "Char", c.Id)
		card.lock.Visible = not mine
		card.tag.Visible = c.Id == current
		card.tag.Text = "Playing"
		card.stroke.Thickness = c.Id == selectedChar and 3 or 1.5
		card.stroke.Color = c.Id == selectedChar and Gui.WHITE or tierColor(c.Tier)
		card.button.BackgroundColor3 = c.Id == selectedChar and Color3.fromRGB(40, 46, 74) or Color3.fromRGB(22, 26, 42)
	end
	local c = Roster.get(selectedChar) or Roster.get(Roster.Starters[1])
	local mine = owns(prof, "Char", c.Id)
	local def = c.Ability and Config.Abilities[c.Ability]
	pl.name.Text = c.Name
	pl.tier.Text = c.Tier
	pl.tier.TextColor3 = tierColor(c.Tier)
	pl.line.Text = string.format("%s, %d cm", roleName(c.Role), c.Height)
	pl.ability.Text = def and def.Name or "No ability"
	pl.ability.TextColor3 = def and def.Color or Gui.MUTED
	pl.blurb.Text = def and def.Blurb or "Abilities come with S and S+ players."
	if not mine then
		pl.select.Text = "Recruit"
	elseif c.Id == current then
		pl.select.Text = "Playing"
	else
		pl.select.Text = "Play as " .. c.Name
	end
	local levels = mine and prof.levels and prof.levels[c.Id] or nil
	local gold = prof.gold or 0
	local free = prof.dev == true
	local built = {}
	for stat, row in pairs(pl.rows) do
		local base = Characters.baseStat(c, stat)
		local cur = levels and levels[stat] or base
		local ceil = c[stat]
		built[stat] = cur
		local span = Config.Stats.Ref - Config.Stats.Min
		row.value.Text = string.format("%d / %d", cur, ceil)
		row.cap.Size = UDim2.fromScale(math.clamp((ceil - Config.Stats.Min) / span, 0, 1), 1)
		row.fill.Size = UDim2.fromScale(math.clamp((cur - Config.Stats.Min) / span, 0, 1), 1)
		row.fill.BackgroundColor3 = cur >= ceil and tierColor(c.Tier) or Gui.GOLD
		if not mine then
			row.cost.Text = "Recruit this player to upgrade them."
		elseif cur >= ceil then
			row.cost.Text = "Maxed"
		elseif free then
			row.cost.Text = "Free for developers"
		else
			row.cost.Text = string.format("Next point %s Gold    To max %s Gold", Gui.num(Characters.pointCost(c, cur)), Gui.num(Characters.upgradeCost(c, cur, ceil)))
		end
		for delta, b in pairs(row.buttons) do
			local ok
			if delta > 0 then
				ok = mine and cur < ceil and (free or gold >= Characters.pointCost(c, cur))
			else
				ok = mine and cur > base
			end
			b.Active = ok
			b.AutoButtonColor = false
			b.TextTransparency = ok and 0 or 0.6
			b.BackgroundTransparency = ok and 0.15 or 0.6
		end
	end
	local s = Characters.derive(c.Tier, { Height = c.Height, Attack = built.Attack, Defense = built.Defense, Speed = built.Speed, Jump = built.Jump })
	local maxS = Characters.derive(Characters.fromRoster(c, "max"))
	local H = Config.Hits
	local notes = {}
	table.insert(notes, string.format("Hitting point <b>%.2f m</b> (maxed %.2f m)    Spike speed <b>%d to %d km/h</b>", s.ContactMaxM, maxS.ContactMaxM, math.floor(H.SpikeKmhMin * s.Power), math.floor(H.SpikeKmhMax * s.Power)))
	table.insert(notes, string.format("Team stamina <b>%d</b>    Run speed <b>%.1f</b>", math.floor(s.StaminaPool + 0.5), s.WalkSpeed))
	if c.Ability == "Thunder" then
		table.insert(notes, s.ContactMaxM >= H.ThunderHeight and '<font color="#FFE14D">Thunder unlocked: spikes above 4.00 m turn into lightning.</font>' or "Thunder needs a 4.00 m hitting point: upgrade Jump.")
	end
	if built.Jump >= Config.Player.BoomJumpMin then
		table.insert(notes, "Boom jumps unlocked.")
	elseif c.Jump >= Config.Player.BoomJumpMin then
		table.insert(notes, string.format("Boom jumps unlock at %d Jump.", Config.Player.BoomJumpMin))
	end
	pl.derived.Text = table.concat(notes, "\n")
end

------------------------------------------------------------------------------------------
-- Locker: equip unlockables, with a live preview in the gym
------------------------------------------------------------------------------------------

local function lockerOpts(prof)
	local opts = {}
	for _, kind in ipairs(COS.Kinds) do
		local key = lockerPick[kind] or (prof.equip and prof.equip[kind]) or Spins.default(kind)
		opts[kind:lower()] = key
	end
	return opts
end

local function buildLocker()
	local p = page("locker")
	header(p, "Locker")
	local panel = Gui.glass(p, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M, 0, 136), Size = UDim2.fromOffset(560, 620) }, 0.15)
	local kinds = {}
	for _, kind in ipairs(COS.Kinds) do
		table.insert(kinds, { key = kind, text = SP.Banners[kind].Name })
	end
	local _, setKind = segmented(panel, kinds, { Size = UDim2.new(1, -32, 0, 44), Position = UDim2.fromOffset(16, 16) }, function(key)
		lockerKind = key
		MenuController.refresh()
	end)
	local grid = make("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 74),
		Size = UDim2.new(1, -32, 1, -180),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(160, 96), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local chips = {}
	for _, kind in ipairs(COS.Kinds) do
		chips[kind] = {}
		for i, item in ipairs(COS[kind]) do
			local b = make("TextButton", { BackgroundColor3 = Color3.fromRGB(22, 26, 42), BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, LayoutOrder = i, Visible = false }, grid)
			Gui.corner(b, 8)
			local color = Spins.rarityColor(item.Rarity)
			local s = Gui.stroke(b, 2, color, 0.3, true)
			make("Frame", { Size = UDim2.new(0, 5, 1, -16), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = color }, b)
			if item.Color then
				local sw = make("Frame", { Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), BackgroundColor3 = item.Color }, b)
				Gui.round(sw)
				Gui.stroke(sw, 1.5, Gui.WHITE, 0.3, true)
			end
			text(b, { Text = item.Name, Font = Gui.FONT_HEAVY, TextSize = 16, TextWrapped = true, Size = UDim2.new(1, -52, 0, 40), Position = UDim2.fromOffset(20, 8), TextYAlignment = Enum.TextYAlignment.Top })
			local tag = text(b, { Text = "", TextSize = 13, TextColor3 = color, Size = UDim2.new(1, -28, 0, 18), Position = UDim2.new(0, 20, 1, -28) })
			onClick(b, function()
				lockerPick[kind] = item.Key
				MenuController.refresh()
			end)
			chips[kind][item.Key] = { button = b, stroke = s, tag = tag, item = item }
		end
	end
	local pickName = text(panel, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 20, Size = UDim2.new(1, -220, 0, 26), Position = UDim2.new(0, 18, 1, -92) })
	local pickSub = text(panel, { Text = "", TextSize = 14, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -220, 0, 20), Position = UDim2.new(0, 18, 1, -64) })
	local equip = Gui.primary(panel, "", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -20), Size = UDim2.fromOffset(180, 52), TextSize = 19 })
	onClick(equip, function()
		local key = lockerPick[lockerKind]
		local prof = profile()
		if not key then
			return
		end
		if owns(prof, lockerKind, key) then
			Net.get("Profile"):FireServer("equip", lockerKind, key)
		else
			banner = lockerKind
			recruitTab = "Cosmetic"
			MenuController.go("recruit")
		end
	end)
	local caption = text(p, { Text = "", TextSize = 16, RichText = true, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, M, 1, -M), Size = UDim2.fromOffset(700, 24) })
	Gui.stroke(caption, 1, Gui.INK, 0.4)
	ui.locker = { setKind = setKind, chips = chips, pickName = pickName, pickSub = pickSub, equip = equip, caption = caption }
end

local function refreshLocker(prof)
	local L = ui.locker
	L.setKind(lockerKind)
	for kind, list in pairs(L.chips) do
		local equipped = prof.equip and prof.equip[kind] or Spins.default(kind)
		local picked = lockerPick[kind] or equipped
		for key, chip in pairs(list) do
			chip.button.Visible = kind == lockerKind
			local have = owns(prof, kind, key)
			chip.button.BackgroundColor3 = key == picked and Color3.fromRGB(44, 50, 80) or Color3.fromRGB(22, 26, 42)
			chip.stroke.Thickness = key == picked and 3 or 1.5
			chip.stroke.Transparency = key == picked and 0 or 0.3
			if key == equipped then
				chip.tag.Text = "Equipped"
				chip.tag.TextColor3 = Gui.GOLD
			elseif have then
				chip.tag.Text = chip.item.Rarity
				chip.tag.TextColor3 = Spins.rarityColor(chip.item.Rarity)
			else
				chip.tag.Text = "Locked"
				chip.tag.TextColor3 = Gui.MUTED
			end
		end
	end
	local key = lockerPick[lockerKind] or (prof.equip and prof.equip[lockerKind]) or Spins.default(lockerKind)
	lockerPick[lockerKind] = key
	local item = Spins.item(lockerKind, key)
	L.pickName.Text = item and item.Name or key
	L.pickSub.Text = item and (item.Rarity .. "  " .. SP.Banners[lockerKind].Name) or ""
	local equipped = prof.equip and prof.equip[lockerKind] == key
	if owns(prof, lockerKind, key) then
		L.equip.Text = equipped and "Equipped" or "Equip"
	else
		L.equip.Text = "Recruit it"
	end
	local o = lockerOpts(prof)
	local function nm(kind, k)
		local it = Spins.item(kind, k)
		return it and it.Name or k
	end
	L.caption.Text = string.format("<b>Preview</b>   %s  /  %s  /  %s  /  %s", nm("Style", o.style), nm("Color", o.color), nm("Trail", o.trail), nm("Effect", o.effect))
	if shown and screen == "locker" then
		mods.SceneController.setPractice(o)
	end
end

------------------------------------------------------------------------------------------
-- Shop
------------------------------------------------------------------------------------------

local packPrices = {}

local function buildShop()
	local p = page("shop")
	header(p, "Shop")
	local row = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(1100, 330), BackgroundTransparency = 1 }, p)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 20), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local prices = {}
	for i, pack in ipairs(Config.Shop.Packs) do
		local card = Gui.glass(row, { Size = UDim2.fromOffset(250, 320), LayoutOrder = i }, 0.15)
		local icon = Gui.icon.vp(card, 96)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 30)
		local amount = Gui.title(card, { Text = Gui.num(pack.VP), TextSize = 48, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 140), TextXAlignment = Enum.TextXAlignment.Center })
		amount.Name = "Amount"
		text(card, { Text = "V Points  -  " .. pack.Name, TextSize = 16, TextColor3 = Gui.MUTED, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 198), TextXAlignment = Enum.TextXAlignment.Center })
		local buy = Gui.primary(card, "", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(190, 52), TextSize = 20 })
		onClick(buy, function()
			if pack.Id ~= 0 then
				pcall(function()
					MarketplaceService:PromptProductPurchase(player, pack.Id)
				end)
			elseif profile().studio then
				Net.get("Profile"):FireServer("buy", i)
			end
		end)
		prices[i] = buy
		if pack.Id ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(pack.Id, Enum.InfoType.Product)
				end)
				if ok and info and info.PriceInRobux then
					packPrices[i] = info.PriceInRobux
					MenuController.refresh()
				end
			end)
		end
	end
	local P = Config.Progression
	local note = text(p, {
		Text = string.format("Gold comes from matches: %d for a win, %d for a loss and %d for every kill, ace or block. The match MVP earns %d extra V Points.", P.WinGold, P.LossGold, P.PlayGold, P.MvpVP),
		TextSize = 16,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.52, 190),
		Size = UDim2.fromOffset(900, 44),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Gui.stroke(note, 1, Gui.INK, 0.4)
	ui.shop = { prices = prices }
end

local function refreshShop(prof)
	for i, pack in ipairs(Config.Shop.Packs) do
		local b = ui.shop.prices[i]
		if pack.Id ~= 0 then
			b.Text = packPrices[i] and ("R$ " .. packPrices[i]) or "..."
		elseif prof.studio then
			b.Text = "Free in Studio"
		else
			b.Text = "Soon"
		end
	end
end

------------------------------------------------------------------------------------------
-- Match: Quick Match, the lobby list, Create Lobby and your lobby
------------------------------------------------------------------------------------------

local LC = Config.Lobby
local form = { mode = 3, privacy = "Public", password = "", fill = true, botTier = Config.Match.DefaultBotTier }
local matchTab = "Quick"
local editing = false -- the host is changing their lobby's settings
local joinTarget = nil -- a private lobby waiting for its password

local PRIVACY_TEXT = { Public = "Public", Friends = "Friends only", Private = "Private" }
local STATE_TEXT = { Open = "Open", Queued = "Queued", Teleporting = "Starting", Arriving = "Starting", Playing = "Playing" }

local function stepper(parent, props, onStep)
	local f = make("Frame", { BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	local down = Gui.flat(f, "<", { Size = UDim2.fromOffset(44, 40), Font = Gui.FONT_HEAVY, TextSize = 20 })
	local value = text(f, { Text = "", Font = Gui.FONT_TITLE, TextSize = 28, Size = UDim2.new(1, -96, 1, 0), Position = UDim2.fromOffset(48, 0), TextXAlignment = Enum.TextXAlignment.Center })
	Gui.stroke(value, 2, Gui.INK, 0)
	local up = Gui.flat(f, ">", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(44, 40), Font = Gui.FONT_HEAVY, TextSize = 20 })
	onClick(down, function()
		onStep(-1)
	end)
	onClick(up, function()
		onStep(1)
	end)
	return value
end

local function formRow(parent, y, label)
	text(parent, { Text = label, Font = Gui.FONT_HEAVY, TextSize = 17, Size = UDim2.fromOffset(170, 40), Position = UDim2.fromOffset(0, y) })
end

local function buildMatch()
	local m = modal("Match", "Match", 900, 620)
	local P = m.panel
	local tabs, setTab = segmented(P, { { key = "Quick", text = "Quick Match" }, { key = "Browse", text = "Lobbies" }, { key = "Create", text = "Create Lobby" } }, { Size = UDim2.fromOffset(560, 46), Position = UDim2.fromOffset(24, 70) }, function(key)
		matchTab = key
		joinTarget = nil
		MenuController.refresh()
	end)
	local body = make("Frame", { Position = UDim2.fromOffset(24, 132), Size = UDim2.new(1, -48, 1, -152), BackgroundTransparency = 1 }, P)

	-- Quick Match
	local quick = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, body)
	text(quick, { Text = "Jump into a public match with whoever is here. Bots take any empty spots when the countdown runs out.", TextSize = 16, TextColor3 = Gui.MUTED, TextWrapped = true, Size = UDim2.new(1, 0, 0, 44) })
	local modes = {}
	for i, n in ipairs({ 1, 2, 3 }) do
		local b = make("TextButton", { Size = UDim2.fromOffset(262, 250), Position = UDim2.fromOffset((i - 1) * 278, 64), BackgroundColor3 = Color3.fromRGB(22, 26, 42), BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false }, quick)
		Gui.corner(b, 12)
		local s = Gui.stroke(b, 2, Gui.WHITE, 0.75, true)
		Gui.title(b, { Text = n .. "v" .. n, TextSize = 76, Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromOffset(0, 36), TextXAlignment = Enum.TextXAlignment.Center })
		text(b, { Text = (n * 2) .. " players", TextSize = 17, TextColor3 = Gui.MUTED, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 132), TextXAlignment = Enum.TextXAlignment.Center })
		local waiting = text(b, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 16, TextColor3 = Gui.GOLD_LIGHT, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 190), TextXAlignment = Enum.TextXAlignment.Center })
		b.MouseEnter:Connect(function()
			s.Color = Gui.GOLD
			s.Transparency = 0
		end)
		b.MouseLeave:Connect(function()
			s.Color = Gui.WHITE
			s.Transparency = 0.75
		end)
		onClick(b, function()
			Net.get("Lobby"):FireServer("quick", n)
		end)
		modes[n] = { button = b, waiting = waiting }
	end

	-- the lobby list
	local browse = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, body)
	local list = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, browse)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local empty = text(browse, { Text = "No lobbies here yet. Create one, or use Quick Match.", TextSize = 17, TextColor3 = Gui.MUTED, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	local rows = {}
	for i = 1, LC.MaxLobbies do
		local r = make("Frame", { Size = UDim2.new(1, -10, 0, 70), BackgroundColor3 = Color3.fromRGB(22, 26, 42), BackgroundTransparency = 0.1, LayoutOrder = i, Visible = false }, list)
		Gui.corner(r, 10)
		local host = text(r, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 19, Size = UDim2.new(0.5, 0, 0, 26), Position = UDim2.fromOffset(18, 10), TextTruncate = Enum.TextTruncate.AtEnd })
		local detail = text(r, { Text = "", TextSize = 14, TextColor3 = Gui.MUTED, Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(18, 38) })
		local count = text(r, { Text = "", Font = Gui.FONT_NUM, TextSize = 20, Size = UDim2.fromOffset(80, 70), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -280, 0, 0), TextXAlignment = Enum.TextXAlignment.Right })
		local state = text(r, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 13, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(60, 66, 96), Size = UDim2.fromOffset(84, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -168, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Center })
		Gui.corner(state, 5)
		local join = Gui.primary(r, "Join", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(136, 44), TextSize = 18 })
		local entry = { frame = r, host = host, detail = detail, count = count, state = state, join = join }
		onClick(join, function()
			local l = entry.lobby
			if not l then
				return
			end
			if l.locked and not l.mine then
				joinTarget = l.id
				MenuController.refresh()
			else
				Net.get("Lobby"):FireServer("join", l.id)
			end
		end)
		rows[i] = entry
	end
	-- password prompt
	local prompt = Gui.glass(browse, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(460, 190), Visible = false, ZIndex = 5 }, 0.02)
	text(prompt, { Text = "This lobby is private", Font = Gui.FONT_HEAVY, TextSize = 20, Size = UDim2.new(1, -40, 0, 28), Position = UDim2.fromOffset(20, 16) })
	local pwBox = make("TextBox", { Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(20, 54), BackgroundColor3 = Color3.fromRGB(8, 10, 18), TextColor3 = Gui.WHITE, PlaceholderText = "Password", PlaceholderColor3 = Gui.MUTED, Text = "", Font = Gui.FONT, TextSize = 18, ClearTextOnFocus = false }, prompt)
	Gui.corner(pwBox, 6)
	local pwJoin = Gui.primary(prompt, "Join", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -16), Size = UDim2.fromOffset(140, 44) })
	local pwCancel = Gui.flat(prompt, "Cancel", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -172, 1, -16), Size = UDim2.fromOffset(110, 44) })
	onClick(pwJoin, function()
		if joinTarget then
			Net.get("Lobby"):FireServer("join", joinTarget, pwBox.Text)
		end
		joinTarget = nil
		pwBox.Text = ""
		MenuController.refresh()
	end)
	onClick(pwCancel, function()
		joinTarget = nil
		MenuController.refresh()
	end)

	-- Create Lobby (also the host's settings)
	local create = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, body)
	formRow(create, 0, "Mode")
	local _, setMode = segmented(create, { { key = 1, text = "1v1" }, { key = 2, text = "2v2" }, { key = 3, text = "3v3" } }, { Size = UDim2.fromOffset(420, 44), Position = UDim2.fromOffset(180, 0) }, function(k)
		form.mode = k
		MenuController.refresh()
	end)
	formRow(create, 62, "Who can join")
	local _, setPrivacy = segmented(create, { { key = "Public", text = "Public" }, { key = "Friends", text = "Friends" }, { key = "Private", text = "Private" } }, { Size = UDim2.fromOffset(420, 44), Position = UDim2.fromOffset(180, 62) }, function(k)
		form.privacy = k
		MenuController.refresh()
	end)
	local privacyNote = text(create, { Text = "", TextSize = 14, TextColor3 = Gui.MUTED, Size = UDim2.fromOffset(420, 20), Position = UDim2.fromOffset(180, 110) })
	formRow(create, 140, "Password")
	local cpw = make("TextBox", { Size = UDim2.fromOffset(420, 42), Position = UDim2.fromOffset(180, 140), BackgroundColor3 = Color3.fromRGB(8, 10, 18), TextColor3 = Gui.WHITE, PlaceholderText = string.format("%d to %d letters or digits", LC.PasswordMin, LC.PasswordMax), PlaceholderColor3 = Gui.MUTED, Text = "", Font = Gui.FONT, TextSize = 18, ClearTextOnFocus = false }, create)
	Gui.corner(cpw, 6)
	cpw:GetPropertyChangedSignal("Text"):Connect(function()
		form.password = cpw.Text
	end)
	formRow(create, 200, "Fill with bots")
	local _, setFill = segmented(create, { { key = true, text = "On" }, { key = false, text = "Off" } }, { Size = UDim2.fromOffset(280, 44), Position = UDim2.fromOffset(180, 200) }, function(k)
		form.fill = k
		MenuController.refresh()
	end)
	local fillNote = text(create, { Text = "", TextSize = 14, TextColor3 = Gui.MUTED, Size = UDim2.fromOffset(500, 20), Position = UDim2.fromOffset(180, 248) })
	formRow(create, 280, "Bot level")
	local botValue = stepper(create, { Size = UDim2.fromOffset(220, 40), Position = UDim2.fromOffset(180, 280) }, function(d)
		local i = Characters.tierIndex(form.botTier) or 11
		form.botTier = Config.Tiers[math.clamp(i + d, 1, #Config.Tiers)]
		MenuController.refresh()
	end)
	local submit = Gui.primary(create, "", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(220, 56), TextSize = 20 })
	local cancelEdit = Gui.flat(create, "Back to lobby", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -236, 1, 0), Size = UDim2.fromOffset(160, 56), Visible = false })
	onClick(submit, function()
		local s = { mode = form.mode, privacy = form.privacy, password = form.password, fill = form.fill, botTier = form.botTier }
		if editing then
			Net.get("Lobby"):FireServer("settings", s)
			editing = false
		else
			Net.get("Lobby"):FireServer("create", s)
		end
		MenuController.refresh()
	end)
	onClick(cancelEdit, function()
		editing = false
		MenuController.refresh()
	end)

	-- your lobby
	local lobby = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, body)
	local info = text(lobby, { Text = "", TextSize = 16, TextColor3 = Gui.MUTED, RichText = true, Size = UDim2.new(1, 0, 0, 22) })
	local status = text(lobby, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 18, TextColor3 = Gui.GOLD_LIGHT, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 28) })
	local sides = {}
	for i, team in ipairs(Config.TeamOrder) do
		local cfg = Config.Teams[team]
		local col = Gui.glass(lobby, { Size = UDim2.new(0.5, -8, 0, 250), Position = UDim2.new((i - 1) * 0.5, (i - 1) * 8, 0, 66) }, 0.25)
		local band = make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = cfg.Color }, col)
		Gui.corner(band, 3)
		text(col, { Text = cfg.Name, Font = Gui.FONT_TITLE, TextSize = 26, TextColor3 = cfg.Color, Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(14, 12) })
		local slots = {}
		for s = 1, 3 do
			local row = make("Frame", { Size = UDim2.new(1, -24, 0, 54), Position = UDim2.fromOffset(12, 52 + (s - 1) * 62), BackgroundColor3 = Color3.fromRGB(26, 30, 48), BackgroundTransparency = 0.2 }, col)
			Gui.corner(row, 8)
			local nm = text(row, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 17, Size = UDim2.new(1, -140, 1, 0), Position = UDim2.fromOffset(14, 0), TextTruncate = Enum.TextTruncate.AtEnd })
			local tag = text(row, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 12, TextColor3 = Gui.INK, BackgroundTransparency = 0, BackgroundColor3 = Gui.GOLD, Size = UDim2.fromOffset(44, 20), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -86, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
			Gui.corner(tag, 4)
			local kick = Gui.flat(row, "Remove", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(72, 32), TextSize = 13, Visible = false })
			local slot = { row = row, name = nm, tag = tag, kick = kick }
			onClick(kick, function()
				if slot.userId then
					Net.get("Lobby"):FireServer("kick", slot.userId)
				end
			end)
			slots[s] = slot
		end
		sides[team] = { col = col, slots = slots }
	end
	local swap = Gui.flat(lobby, "Switch side", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.fromOffset(150, 54) })
	local settingsB = Gui.flat(lobby, "Settings", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 162, 1, 0), Size = UDim2.fromOffset(130, 54) })
	local leave = Gui.secondary(lobby, "Leave", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -236, 1, 0), Size = UDim2.fromOffset(170, 56), TextSize = 19 })
	local start = Gui.primary(lobby, "Start", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(220, 56), TextSize = 22 })
	onClick(swap, function()
		Net.get("Lobby"):FireServer("team")
	end)
	onClick(settingsB, function()
		local mine = lobbies.mine
		if mine then
			form.mode, form.privacy, form.fill, form.botTier = mine.mode, mine.privacy, mine.fill, mine.botTier
			form.password = mine.password or ""
			cpw.Text = form.password
			editing = true
			MenuController.refresh()
		end
	end)
	onClick(leave, function()
		Net.get("Lobby"):FireServer("leave")
	end)
	onClick(start, function()
		Net.get("Lobby"):FireServer("start")
	end)

	ui.match = {
		modal = m,
		tabs = tabs,
		setTab = setTab,
		quick = quick,
		modes = modes,
		browse = browse,
		rows = rows,
		empty = empty,
		prompt = prompt,
		pwBox = pwBox,
		create = create,
		setMode = setMode,
		setPrivacy = setPrivacy,
		privacyNote = privacyNote,
		cpw = cpw,
		setFill = setFill,
		fillNote = fillNote,
		botValue = botValue,
		submit = submit,
		cancelEdit = cancelEdit,
		lobby = lobby,
		info = info,
		status = status,
		sides = sides,
		swap = swap,
		settings = settingsB,
		leave = leave,
		start = start,
	}
end

function MenuController.openMatch()
	ui.match.modal.root.Visible = true
	Net.get("Lobby"):FireServer("list")
	MenuController.refresh()
end

local function lobbyStatus(mine)
	if mine.state == "Queued" then
		local pos = mine.queuePos or 1
		return pos <= 1 and "Next up on the court..." or string.format("Waiting for the court (%d ahead)", pos - 1)
	elseif mine.state == "Teleporting" then
		return "Taking you to your own server..."
	elseif mine.state == "Arriving" then
		return "Waiting for everyone to arrive..."
	elseif mine.state == "Playing" then
		return "Match in progress"
	elseif mine.quick then
		local left = math.max(0, math.ceil((mine.startsAt or 0) - workspace:GetServerTimeNow()))
		return string.format("Starting in %d. Bots fill the empty spots.", left)
	elseif mine.isHost then
		if not mine.fill and mine.count < mine.capacity then
			return "Both teams need to be full to start (or turn on Fill with bots)."
		end
		return "Start when you're ready."
	end
	return "Waiting for the host to start."
end

local function refreshMatch()
	local Mt = ui.match
	if not Mt.modal.root.Visible then
		return
	end
	local mine = lobbies.mine
	local inLobby = mine ~= nil and not editing
	Mt.tabs.Visible = mine == nil
	Mt.setTab(matchTab)
	Mt.quick.Visible = mine == nil and matchTab == "Quick"
	Mt.browse.Visible = mine == nil and matchTab == "Browse"
	Mt.create.Visible = (mine == nil and matchTab == "Create") or (mine ~= nil and editing)
	Mt.lobby.Visible = inLobby
	if mine then
		Mt.modal.title.Text = mine.quick and string.format("Quick Match %dv%d", mine.mode, mine.mode) or (mine.hostName .. "'s Lobby")
	else
		Mt.modal.title.Text = "Match"
	end

	-- Quick Match: who's waiting in each mode
	local waiting = { 0, 0, 0 }
	for _, l in ipairs(lobbies.list or {}) do
		if l.quick and l.state == "Open" and l.privacy == "Public" then
			waiting[l.mode] = waiting[l.mode] + l.count
		end
	end
	for n, e in pairs(Mt.modes) do
		e.waiting.Text = waiting[n] > 0 and string.format("%d waiting", waiting[n]) or "Start one"
	end

	-- the list
	local shownRows = 0
	for i, row in ipairs(Mt.rows) do
		local l = lobbies.list and lobbies.list[i]
		row.lobby = l
		row.frame.Visible = l ~= nil
		if l then
			shownRows = shownRows + 1
			row.host.Text = l.quick and ("Quick Match " .. l.mode .. "v" .. l.mode) or (l.hostName .. "'s Lobby")
			row.detail.Text = string.format("%dv%d   %s   %s   Bots %s", l.mode, l.mode, PRIVACY_TEXT[l.privacy] or l.privacy, l.fill and "Bots fill" or "No bots", l.botTier)
			row.count.Text = string.format("%d/%d", l.count, l.capacity)
			row.state.Text = STATE_TEXT[l.state] or l.state
			row.state.BackgroundColor3 = l.state == "Open" and Color3.fromRGB(40, 150, 100) or Color3.fromRGB(80, 86, 116)
			local can = l.state == "Open" and l.count < l.capacity and not l.mine
			row.join.Text = l.mine and "Joined" or (l.locked and "Password" or "Join")
			row.join.Active = can
			row.join.BackgroundTransparency = can and 0 or 0.5
		end
	end
	Mt.empty.Visible = shownRows == 0
	Mt.prompt.Visible = joinTarget ~= nil and mine == nil

	-- Create / settings
	Mt.setMode(form.mode)
	Mt.setPrivacy(form.privacy)
	Mt.setFill(form.fill)
	Mt.cpw.Visible = form.privacy == "Private"
	Mt.privacyNote.Text = form.privacy == "Friends" and "Only your Roblox friends in this server see and join it." or (form.privacy == "Private" and "Listed with a lock: players need the password." or "Anyone in this server can join.")
	Mt.fillNote.Text = form.fill and "Start any time: bots take the empty spots." or "Both teams must be full before you can start."
	Mt.botValue.Text = form.botTier
	Mt.botValue.TextColor3 = tierColor(form.botTier)
	Mt.submit.Text = editing and "Save settings" or "Create Lobby"
	Mt.cancelEdit.Visible = editing

	-- your lobby
	if mine then
		local parts = { string.format("%dv%d", mine.mode, mine.mode), PRIVACY_TEXT[mine.privacy] or mine.privacy }
		if mine.password then
			table.insert(parts, "password <b>" .. mine.password .. "</b>")
		end
		table.insert(parts, mine.fill and ("bots fill empty spots (level " .. mine.botTier .. ")") or "no bots")
		if mine.reserved then
			table.insert(parts, "your own server")
		end
		Mt.info.Text = table.concat(parts, "   ")
		Mt.status.Text = lobbyStatus(mine)
		for _, team in ipairs(Config.TeamOrder) do
			local side = Mt.sides[team]
			local members = mine[team] or {}
			for s, slot in ipairs(side.slots) do
				slot.row.Visible = s <= mine.mode
				local who = members[s]
				slot.userId = who and who.id or nil
				if who then
					slot.name.Text = who.name .. (who.id == player.UserId and "  (you)" or "")
					slot.name.TextColor3 = who.id == player.UserId and Gui.GOLD_LIGHT or Gui.WHITE
					slot.tag.Visible = who.host == true
					slot.tag.Text = "Host"
					slot.kick.Visible = mine.isHost and who.id ~= player.UserId and mine.state == "Open"
				else
					slot.name.Text = mine.fill and "Bot" or "Open"
					slot.name.TextColor3 = Gui.MUTED
					slot.tag.Visible = false
					slot.kick.Visible = false
				end
			end
		end
		local open = mine.state == "Open"
		Mt.swap.Visible = open and not mine.quick
		Mt.settings.Visible = open and mine.isHost and not mine.quick
		Mt.start.Visible = open and mine.isHost and not mine.quick
		Mt.leave.Visible = open or mine.state == "Queued"
		Mt.leave.Text = mine.quick and "Cancel queue" or "Leave lobby"
	end
end

------------------------------------------------------------------------------------------
-- Timeout: change your character or your look (the menus open over the match for it)
------------------------------------------------------------------------------------------

local swapMode = false
local swapKind = "Style"

local function buildSwap()
	local m = modal("Swap", "Timeout: character and look", 1000, 560)
	local P = m.panel
	text(P, { Text = "Your characters. You keep your spot and role on court.", TextSize = 15, TextColor3 = Gui.MUTED, Size = UDim2.fromOffset(460, 20), Position = UDim2.fromOffset(24, 62) })
	local chars = make("ScrollingFrame", { Position = UDim2.fromOffset(20, 90), Size = UDim2.fromOffset(470, 450), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, P)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(148, 78), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, chars)
	local cards = {}
	for i, c in ipairs(Roster) do
		local b = make("TextButton", { BackgroundColor3 = Color3.fromRGB(22, 26, 42), BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, LayoutOrder = i, Visible = false }, chars)
		Gui.corner(b, 8)
		local s = Gui.stroke(b, 1.5, tierColor(c.Tier), 0.2, true)
		local t = text(b, { Text = c.Tier, Font = Gui.FONT_TITLE, TextSize = 26, TextColor3 = tierColor(c.Tier), Size = UDim2.fromOffset(48, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), TextXAlignment = Enum.TextXAlignment.Right })
		Gui.stroke(t, 2, Gui.INK, 0)
		text(b, { Text = c.Name, Font = Gui.FONT_HEAVY, TextSize = 16, Size = UDim2.new(1, -60, 0, 22), Position = UDim2.fromOffset(10, 8), TextTruncate = Enum.TextTruncate.AtEnd })
		local def = c.Ability and Config.Abilities[c.Ability]
		text(b, { Text = roleName(c.Role), TextSize = 12, TextColor3 = Gui.MUTED, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 34) })
		text(b, { Text = def and def.Name or "", TextSize = 12, TextColor3 = def and def.Color or Gui.MUTED, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 52) })
		onClick(b, function()
			Net.get("Profile"):FireServer("select", c.Id)
		end)
		cards[c.Id] = { button = b, stroke = s }
	end
	local kinds = {}
	for _, kind in ipairs(COS.Kinds) do
		table.insert(kinds, { key = kind, text = SP.Banners[kind].Name })
	end
	local _, setKind = segmented(P, kinds, { Size = UDim2.fromOffset(470, 40), Position = UDim2.fromOffset(510, 56) }, function(key)
		swapKind = key
		MenuController.refresh()
	end)
	local looks = make("ScrollingFrame", { Position = UDim2.fromOffset(510, 106), Size = UDim2.fromOffset(470, 434), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, P)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(148, 60), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, looks)
	local chips = {}
	for _, kind in ipairs(COS.Kinds) do
		chips[kind] = {}
		for i, item in ipairs(COS[kind]) do
			local b = make("TextButton", { BackgroundColor3 = Color3.fromRGB(22, 26, 42), BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, LayoutOrder = i, Visible = false }, looks)
			Gui.corner(b, 8)
			local s = Gui.stroke(b, 1.5, Spins.rarityColor(item.Rarity), 0.3, true)
			text(b, { Text = item.Name, Font = Gui.FONT_HEAVY, TextSize = 15, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(10, 8) })
			local tag = text(b, { Text = "", TextSize = 12, TextColor3 = Spins.rarityColor(item.Rarity), Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 34) })
			onClick(b, function()
				Net.get("Profile"):FireServer("equip", kind, item.Key)
			end)
			chips[kind][item.Key] = { button = b, stroke = s, tag = tag, item = item }
		end
	end
	ui.swap = { modal = m, cards = cards, setKind = setKind, chips = chips }
end

local function refreshSwap(prof)
	local S = ui.swap
	local current = prof.char or player:GetAttribute("CharId")
	for id, card in pairs(S.cards) do
		card.button.Visible = owns(prof, "Char", id)
		local on = id == current
		card.stroke.Thickness = on and 3 or 1.5
		card.stroke.Color = on and Gui.GOLD or tierColor(Roster.get(id).Tier)
		card.button.BackgroundColor3 = on and Color3.fromRGB(44, 50, 80) or Color3.fromRGB(22, 26, 42)
	end
	S.setKind(swapKind)
	for kind, list in pairs(S.chips) do
		local equipped = prof.equip and prof.equip[kind] or Spins.default(kind)
		for key, chip in pairs(list) do
			chip.button.Visible = kind == swapKind and owns(prof, kind, key)
			local on = key == equipped
			chip.stroke.Thickness = on and 3 or 1.5
			chip.tag.Text = on and "Equipped" or chip.item.Rarity
			chip.tag.TextColor3 = on and Gui.GOLD or Spins.rarityColor(chip.item.Rarity)
		end
	end
end

local function closeSwap()
	if not swapMode then
		return
	end
	swapMode = false
	ui.swap.modal.root.Visible = false
	gui.Enabled = shown
	for _, v in ipairs(ui.vignettes) do
		v.Visible = true
	end
	if ui.pages[screen] then
		ui.pages[screen].Visible = true
	end
end

-- Opened from the timeout panel: just this window over the match.
function MenuController.openSwap()
	if not (State.isPlaying and State.phase() == "Timeout") then
		return
	end
	swapMode = true
	gui.Enabled = true
	for _, f in pairs(ui.pages) do
		f.Visible = false
	end
	for _, v in ipairs(ui.vignettes) do
		v.Visible = false
	end
	ui.swap.modal.root.Visible = true
	refreshSwap(profile())
end

------------------------------------------------------------------------------------------
-- screens, scenes, refresh
------------------------------------------------------------------------------------------

local SCENE = { home = "home", players = "home", shop = "home", recruit = "gym", locker = "gym" }
local autoLine = ""

function MenuController.applyScene()
	if not shown or seqActive then
		return
	end
	local SC = mods.SceneController
	SC.show(SCENE[screen] or "home")
	if screen == "locker" then
		SC.shot("practice", 0.6)
		SC.setPractice(lockerOpts(profile()))
	else
		SC.setPractice(nil)
		if screen == "recruit" then
			SC.shot("recruit", 0.6)
		else
			SC.shot("home", 0.6)
		end
	end
end

function MenuController.go(name)
	if seqActive or not ui.pages[name] then
		return
	end
	if name ~= "locker" then
		lockerPick = {}
	end
	screen = name
	for n, f in pairs(ui.pages) do
		f.Visible = n == name
	end
	MenuController.applyScene()
	MenuController.refresh()
end

local function doRefresh()
	refreshQueued = false
	if not ui.home then
		return
	end
	local prof = profile()
	for _, c in ipairs(ui.currencies) do
		c.vp.Text = Gui.num(prof.vp or 0)
		c.gold.Text = Gui.num(prof.gold or 0)
	end
	refreshHome(prof)
	if screen == "recruit" then
		refreshRecruit(prof)
		ui.recruit.status.Text = prof.autoRolling and autoLine or ""
	elseif screen == "players" then
		refreshPlayers(prof)
	elseif screen == "locker" then
		refreshLocker(prof)
	elseif screen == "shop" then
		refreshShop(prof)
	end
	refreshMatch()
	if swapMode then
		refreshSwap(prof)
	end
end

function MenuController.refresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(function()
		local ok, err = pcall(doRefresh)
		if not ok then
			refreshQueued = false
			warn("[SpikeRush] menu: " .. tostring(err))
		end
	end)
end

local function setShown(on)
	if on == shown then
		return
	end
	if swapMode then
		closeSwap()
	end
	shown = on
	gui.Enabled = on
	if on then
		MenuController.applyScene()
		MenuController.refresh()
	else
		if seqActive then
			endSequence(seqActive)
		end
		mods.SceneController.setPractice(nil)
		mods.SceneController.show(nil)
		ui.match.modal.root.Visible = false
		ui.odds.modal.root.Visible = false
		ui.help.root.Visible = false
	end
end

function MenuController.shown()
	return shown
end

local function onProfile(prof)
	local r = prof.reveal
	if r and r ~= lastReveal and r.items and r.items[1] then
		lastReveal = r
		if prof.autoRolling then
			-- mid auto-roll: a running line instead of the full sequence
			local item = Spins.item(r.banner, r.items[1].key)
			autoLine = string.format("Auto-rolling: %d spins. Last pull: %s (%s)", r.auto or 0, item and item.Name or "?", item and item.Rarity or "?")
		elseif shown then
			task.spawn(playSequence, r)
		end
	end
	if prof.notice then
		toast(prof.notice)
	end
	MenuController.refresh()
end

local function layout()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vs = cam.ViewportSize
	if vs.X < 2 or vs.Y < 2 then
		return
	end
	local s = math.clamp(vs.Y / 900, 0.45, 1.6)
	if vs.X / s < 1180 then
		s = vs.X / 1180 -- narrow screens: keep room for the side panels
	end
	canvasScale.Scale = s
	canvas.Size = UDim2.fromOffset(vs.X / s, vs.Y / s)
end

function MenuController.init(m)
	mods = m
	gui = make("ScreenGui", {
		Name = "SpikeRushMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	canvas = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), BackgroundTransparency = 1 }, gui)
	canvasScale = make("UIScale", {}, canvas)
	-- soft shade at the top and bottom so text reads over any scene
	local top = make("Frame", { Size = UDim2.new(1, 0, 0, 220), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 0 }, canvas)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }) }, top)
	local bottom = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 260), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 0 }, canvas)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.4) }) }, bottom)
	ui.vignettes = { top, bottom }

	buildHome()
	buildRecruit()
	buildPlayers()
	buildLocker()
	buildShop()
	buildHelp()
	buildTable()
	buildMatch()
	buildSequence()
	buildSwap()

	local tf = Gui.glass(canvas, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), Size = UDim2.fromOffset(620, 46), Visible = false, ZIndex = 40 }, 0.15)
	local tl = text(tf, { Text = "", Font = Gui.FONT_HEAVY, TextSize = 17, TextWrapped = true, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	ui.toast = { frame = tf, label = tl }

	layout()
	local function watchCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
		end
		layout()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	State.signals.Profile:Connect(onProfile)
	State.signals.Match:Connect(function()
		setShown(not State.isPlaying)
		MenuController.refresh()
	end)
	State.signals.Announce:Connect(function(a)
		if a.kind == "StandIn" and a.userId == player.UserId and a.reason == "afk" then
			toast("You were away, so your AI took over. Rejoin from Home.")
		end
	end)
	Net.get("Lobbies").OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		if data.notice then
			toast(data.notice)
		end
		if data.list then
			local had = lobbies.mine ~= nil
			lobbies = data
			if not data.mine then
				editing = false
			elseif not had and shown and not data.mine.tutorial then
				ui.match.modal.root.Visible = true -- you just joined or made one
			end
			MenuController.refresh()
		end
	end)
	player:GetAttributeChangedSignal("CharId"):Connect(MenuController.refresh)

	MenuController.go("home")
	setShown(not State.isPlaying)

	-- slow ticks: countdowns, the featured recruit and tips rotating
	local acc, tick = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		-- the timeout window closes with the timeout (or its Close button)
		if swapMode and (not ui.swap.modal.root.Visible or not State.isPlaying or State.phase() ~= "Timeout") then
			closeSwap()
		end
		acc = acc + dt
		if acc < 0.25 or not shown then
			return
		end
		acc = 0
		tick = tick + 1
		if tick % 36 == 0 then
			ui.home.featured = ui.home.featured + 1
		end
		if tick % 40 == 0 then
			ui.home.tipText.Text = TIPS[(math.floor(tick / 40) % #TIPS) + 1]
		end
		if ui.match.modal.root.Visible and lobbies.mine then
			ui.match.status.Text = lobbyStatus(lobbies.mine)
		end
		if tick % 36 == 0 then
			MenuController.refresh()
		end
	end)
end

return MenuController
