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
--   Shop ......... V Point and Gold packs (each can be a gift), and a big Recruit button.
--   Codes, Daily . Home's buttons down the right edge: codes and the daily reward, for members of
--                  the group who favorited the game (Roblox's join and favorite prompts).
--   Admin ........ developers only: 2x VP and 2x Gold events in every server, announcements, and
--                  VP, Gold, lucky spins and characters for anyone by username (AdminService).
--   Match ........ Quick Match, the lobby list, Create Lobby (public, friends only or private
--                  with a password, fill with bots, bot level) and your lobby.
-- Layout is drawn on a 900-unit-tall canvas scaled to the screen, so it keeps its proportions
-- on every device.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)
local Spins = require(Shared.Spins)
local Roster = require(Shared.Roster)
local Court = require(Shared.Court)
local Tutorial = require(Shared.Tutorial)
local Assets = require(Shared.Assets)
local Economy = require(Shared.Economy)
local Util = require(Shared.Util)
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
-- Codes, the daily reward, gifts, the admin panel and the running events keep their pieces in
-- this table rather than in locals: this chunk is close to Luau's 200 locals.
local Extra = {}
Extra.profileAt = os.clock() -- when the last profile arrived (its countdowns count from then)
Extra.shopTab = "Currency" -- the Shop's tab: "Currency" (VP and Gold) or "Lucky" (lucky spins and boosts)
Extra.Cards = require(Shared.Cards) -- player cards (the Locker's Cards tab)
local packPrices = { VP = {}, Gold = {}, Lucky = {}, Boost = {} } -- product prices in Robux, looked up once per pack

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

-- The press sound: UIClick, or the button's own ("Sound" attribute: UIConfirm on action plates,
-- UISelect on tabs and toggles). One per press, however many layers of a handler call it, and
-- none when the button already sounded as it went down (Gui.pressSound).
local function click(key)
	Gui.click(key)
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
	Gui.pressSound(button)
	button.MouseButton1Click:Connect(function()
		click(button:GetAttribute("Sound"))
		fn()
	end)
end

-- An icon key (Assets.Images), or `fallback` while its slot is empty.
function Extra.iconKey(key, fallback)
	return Assets.image(key) and key or fallback
end

-- "5h 12m" (the daily reward's wait)
function Extra.waitText(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", math.max(1, m))
end

-- "14:32" (an event's time left)
function Extra.clockText(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
	end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- A running event's time left in seconds (the admin panel's; 0 when it's off).
function Extra.eventLeft(kind)
	return math.max(0, (ReplicatedStorage:GetAttribute("Event_" .. kind) or 0) - Util.now())
end

-- The rarity weights a usual recruit on `kind` uses right now (2x Luck's on Characters, while it
-- runs; nil: the usual ones).
function Extra.recruitWeights(kind)
	if kind == "Char" and Extra.eventLeft("Luck") > 0 then
		return Spins.LuckEventWeights
	end
	return nil
end

-- A text box in the Shop's style.
function Extra.inputBox(parent, props, placeholder)
	local box = make("TextBox", {
		BackgroundColor3 = Color3.fromRGB(6, 8, 16),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		TextColor3 = Gui.CHALK,
		PlaceholderColor3 = Gui.DIM,
		PlaceholderText = placeholder or "",
		Text = "",
		FontFace = Gui.body(Enum.FontWeight.Medium),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ZIndex = 22,
	}, parent)
	for k, v in pairs(props or {}) do
		box[k] = v
	end
	make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, box)
	return box
end

-- Segmented control, as The Spike's toggles: a dark rounded trough, the active segment filled
-- signal yellow. Returns the frame and a setter(activeKey). onPick(key) on a press.
local function segmented(parent, items, props, onPick)
	local f = make("Frame", { BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.2 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	Gui.corner(f, 8)
	make("UIStroke", { Color = Gui.HAIRLINE, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, f)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	local buttons = {}
	for i, it in ipairs(items) do
		local b = make("TextButton", {
			Name = tostring(it.key),
			Size = UDim2.new(1 / #items, -4 * (#items - 1) / #items, 1, 0),
			BackgroundColor3 = Gui.SIGNAL,
			BackgroundTransparency = 1,
			Text = it.text,
			FontFace = Gui.display(),
			TextSize = 20,
			TextColor3 = Gui.DIM,
			AutoButtonColor = false,
			LayoutOrder = i,
		}, f)
		Gui.corner(b, 6)
		b:SetAttribute("Sound", "UISelect")
		onClick(b, function()
			onPick(it.key)
		end)
		buttons[it.key] = b
	end
	local function set(active)
		for key, b in pairs(buttons) do
			local on = key == active
			b.BackgroundTransparency = on and 0 or 1
			b.TextColor3 = on and Gui.LINE or Gui.DIM
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
	t.frame.BackgroundTransparency = 0.1
	t.label.TextTransparency = 0
	t.edge.Transparency = 0.3
	t.tab.BackgroundTransparency = 0
	t.token = (t.token or 0) + 1
	local token = t.token
	task.delay(3.2, function()
		if t.token == token then
			tween(t.frame, 0.4, { BackgroundTransparency = 1 })
			tween(t.label, 0.4, { TextTransparency = 1 })
			tween(t.edge, 0.4, { Transparency = 1 })
			tween(t.tab, 0.4, { BackgroundTransparency = 1 })
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

-- A sub-screen's header, as in The Spike: a back arrow and the title top left (placeHeaders
-- slides them right of Roblox's buttons where they reach into the top bar), the currencies and
-- Settings top right. The pieces it uses (currencyStrip, navItem) come further down, so it looks
-- them up through `chrome` when a screen is built.
local chrome = {}
local function header(page, title)
	local back = make("TextButton", { Name = "Back", Size = UDim2.fromOffset(560, 56), Position = UDim2.fromOffset(M, 64), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, page)
	local arrow = Gui.iconImage(back, "IconBack", 38, Gui.CHALK, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0) })
	Gui.label(back, { Text = title, display = true, weight = Enum.FontWeight.Heavy, TextSize = 46, TextStrokeTransparency = 0.55, Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(58, 0) })
	back.MouseEnter:Connect(function()
		arrow.ImageColor3 = Gui.SIGNAL
		if Gui.onHover then
			Gui.onHover()
		end
	end)
	back.MouseLeave:Connect(function()
		arrow.ImageColor3 = Gui.CHALK
	end)
	onClick(back, function()
		MenuController.go("home")
	end)
	ui.headers = ui.headers or {}
	table.insert(ui.headers, back)
	local strip = chrome.currencyStrip(page, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M - 112, 0, 70) })
	strip.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local gear = chrome.navItem(page, "IconSettings", "Settings", { Name = "Settings", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M + 12, 0, 52) })
	onClick(gear, function()
		mods.UIController.toggleSettings(gear.AbsolutePosition.Y + gear.AbsoluteSize.Y + 6)
	end)
	return back
end

local function page(name)
	local f = make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, canvas)
	ui.pages = ui.pages or {}
	ui.pages[name] = f
	return f
end

-- A signal-yellow plate button and its label (returned so it can be renamed).
local function actionPlate(parent, props, caption, textSize)
	local b = Gui.plateButton(parent, props, Gui.SIGNAL, Gui.SIGNAL_HOT)
	b:SetAttribute("Sound", "UIConfirm")
	local l = Gui.label(b, { Text = caption, display = true, TextSize = textSize or 22, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	return b, l
end

-- A hairline button and its label.
local function hairButton(parent, props, caption, textSize)
	local b = Gui.cardButton(parent, props)
	local l = Gui.label(b, { Text = caption, display = true, TextSize = textSize or 20, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	return b, l
end

-- A modal: a dim backdrop and a centred panel with a title and a Close button. Only Close, or a
-- click on the dim area outside the panel, closes it: the panel is a button of its own laid over
-- the backdrop, so a click anywhere inside it (a label, the gap between two cards) stops there.
-- `broadcast` draws it in Home's kit (a dark hairline card, the display face, a slanted accent
-- under the title); otherwise it's a glass panel.
local function modal(name, title, w, h, broadcast)
	local root = make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, canvas)
	local shade = make("TextButton", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, ZIndex = 20 }, root)
	local panel = make("TextButton", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h), BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 21 }, root)
	local t, close
	if broadcast then
		panel.BackgroundColor3 = Gui.CARD
		panel.BackgroundTransparency = 0.06
		make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
		Gui.halftone(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.55, 0, 0, 190), ImageColor3 = Gui.CHALK, ImageTransparency = 0.94 })
		t = Gui.label(panel, { Text = title, display = true, weight = Enum.FontWeight.Heavy, TextSize = 46, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -170, 0, 52), Position = UDim2.fromOffset(26, 12) })
		Gui.plate(panel, { Size = UDim2.fromOffset(64, 6), Position = UDim2.fromOffset(28, 68) }, Gui.SIGNAL)
		close = hairButton(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(112, 40) }, "Close")
	else
		panel.BackgroundColor3 = Color3.fromRGB(10, 12, 22)
		panel.BackgroundTransparency = 0.08
		Gui.corner(panel, 10)
		Gui.stroke(panel, 1, Gui.WHITE, 0.82, true)
		t = text(panel, { Text = title, Font = Gui.FONT_TITLE, TextSize = 34, Size = UDim2.new(1, -150, 0, 44), Position = UDim2.fromOffset(24, 14), ZIndex = 21 })
		Gui.stroke(t, 2, Gui.INK, 0)
		close = Gui.flat(panel, "Close", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 18), Size = UDim2.fromOffset(96, 36), ZIndex = 21 })
	end
	local function hide()
		root.Visible = false
	end
	onClick(close, hide)
	shade.MouseButton1Click:Connect(hide)
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		if root.Visible and mods and mods.AudioController then
			mods.AudioController.play("UIOpen", { minGap = 0.1 })
		end
	end)
	return { root = root, panel = panel, title = t, hide = hide }
end

------------------------------------------------------------------------------------------
-- Home
------------------------------------------------------------------------------------------

-- A nav item: an icon over a caption. `icon` is a Toolbox image key (Assets.image) or a
-- drawn Gui.icon function. The active one is signal yellow with a slanted bar under it; the
-- rest light up under the pointer.
local function navItem(parent, icon, caption, props, active)
	local b = make("TextButton", { Name = caption, Size = UDim2.fromOffset(96, 74), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	local rest = active and Gui.SIGNAL or Gui.CHALK
	local img
	if type(icon) == "string" then
		img = Gui.iconImage(b, icon, 30, rest, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6) })
	else
		local drawn = icon(b, 30, Gui.HAIRLINE)
		drawn.AnchorPoint = Vector2.new(0.5, 0)
		drawn.Position = UDim2.new(0.5, 0, 0, 6)
	end
	local cap = Gui.label(b, {
		Text = caption,
		display = true,
		TextSize = 17,
		TextColor3 = rest,
		TextStrokeTransparency = 0.6,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local bar = Gui.plate(b, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66), Size = UDim2.fromOffset(46, 5) }, Gui.SIGNAL)
	bar.Visible = active == true
	b.MouseEnter:Connect(function()
		if img then
			img.ImageColor3 = Gui.SIGNAL
		end
		cap.TextColor3 = Gui.SIGNAL
		if Gui.onHover then
			Gui.onHover()
		end
	end)
	b.MouseLeave:Connect(function()
		if img then
			img.ImageColor3 = rest
		end
		cap.TextColor3 = rest
	end)
	return b
end

-- The recruit screen on its player banner (Home's featured card, the Shop's Recruit button).
local function goRecruit()
	banner = "Char"
	recruitTab = "Player"
	MenuController.go("recruit")
end

-- The currencies in a row: icon, amount, and a "+" to the Shop for V Points (Gold is earned).
local function currencyStrip(parent, props)
	local cur = make("Frame", { Size = UDim2.fromOffset(460, 40), BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		cur[k] = v
	end
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, cur)
	local function currency(order, iconFn)
		iconFn(cur, 30).LayoutOrder = order
		local amount = Gui.label(cur, { Text = "0", display = true, TextSize = 26, TextStrokeTransparency = 0.6, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), LayoutOrder = order + 1 })
		local plus = make("TextButton", { Text = "+", FontFace = Gui.display(), TextSize = 32, TextColor3 = Gui.SIGNAL, BackgroundTransparency = 1, Size = UDim2.fromOffset(26, 36), LayoutOrder = order + 2 }, cur)
		return amount, plus
	end
	local vp, vpPlus = currency(1, Gui.icon.vp)
	make("Frame", { Size = UDim2.fromOffset(14, 1), BackgroundTransparency = 1, LayoutOrder = 4 }, cur)
	local gold, goldPlus = currency(5, Gui.icon.gold)
	goldPlus.Visible = false
	onClick(vpPlus, function()
		MenuController.go("shop")
	end)
	ui.currencies = ui.currencies or {}
	table.insert(ui.currencies, { vp = vp, gold = gold })
	return cur
end

-- The nav across the top of every main screen, Home's too: the screens with this one lit, and
-- Help and Settings at the top right, in the nav's row so they stay clear of the panels below.
-- `lit` lights another tab than the screen's own (the Match screen lights Home).
local MAIN_TABS = { { "IconHome", "Home", "home" }, { "IconJump", "Practice", "practice" }, { "IconShop", "Shop", "shop" }, { "IconPlayers", "Players", "players" }, { "IconLocker", "Locker", "locker" }, { "IconRanks", "Ranks", "ranks" } }

local function navBar(p, active, lit)
	local nav = make("Frame", { Name = "Nav", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 30, 0, 18), Size = UDim2.fromOffset(#MAIN_TABS * 96 + (#MAIN_TABS - 1) * 14, 74), BackgroundTransparency = 1 }, p)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, nav)
	for i, e in ipairs(MAIN_TABS) do
		local b = navItem(nav, e[1], e[2], { LayoutOrder = i }, e[3] == (lit or active))
		onClick(b, function()
			if e[3] ~= active then
				MenuController.go(e[3])
			end
		end)
	end
	local side = make("Frame", { Name = "Side", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M + 12, 0, 18), Size = UDim2.fromOffset(2 * 96 + 6, 74), BackgroundTransparency = 1 }, p)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, side)
	for i, e in ipairs({ { "IconHelp", "Help", "help" }, { "IconSettings", "Settings", "settings" } }) do
		local b = navItem(side, e[1], e[2], { LayoutOrder = i })
		onClick(b, function()
			if e[3] == "settings" then
				mods.UIController.toggleSettings(b.AbsolutePosition.Y + b.AbsoluteSize.Y + 6)
			else
				ui.help.root.Visible = true
			end
		end)
	end
	return nav, side
end

-- The top of the main screens (Practice, Shop, Players, Locker, Ranks, Match): the currencies top
-- left under Roblox's own buttons (placeHeaders moves them) and the nav.
local function mainChrome(p, active, lit)
	local strip = currencyStrip(p, { Position = UDim2.fromOffset(M, 24) })
	ui.strips = ui.strips or {}
	table.insert(ui.strips, strip)
	return navBar(p, active, lit)
end
chrome.currencyStrip = currencyStrip
chrome.navItem = navItem

-- Home: the club room behind a match-day overlay. Profile and currencies top left, the nav
-- across the top (every main screen's), the featured recruit and your record on the left, a tip
-- at the bottom, and Recruit Player and the big slanted Match plate (the Match screen) bottom
-- right.
local PROFILE_H = 152 -- the profile block: the headshot row and the currencies under it
local NAV_BOTTOM = 92 -- where the nav across the top ends

local function buildHome()
	local p = page("home")

	-- profile, top left under Roblox's own buttons (placeHome moves it there): a square
	-- headshot, the name, who you play, a slanted accent bar, and the currencies under it
	local prof = make("Frame", { Name = "Profile", Size = UDim2.fromOffset(560, PROFILE_H), Position = UDim2.fromOffset(M, 24), BackgroundTransparency = 1 }, p)
	local shot = make("ImageLabel", {
		Size = UDim2.fromOffset(100, 100),
		BackgroundColor3 = Gui.NAVY_LIGHT,
		BorderSizePixel = 0,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150",
	}, prof)
	make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, shot)
	-- the headshot opens your profile (your record and your leaderboard places)
	local shotBtn = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = shot.ZIndex + 1 }, shot)
	local shotTag = Gui.plate(shot, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 6), Size = UDim2.fromOffset(84, 22), ZIndex = shot.ZIndex + 2 }, Gui.SIGNAL)
	Gui.label(shotTag, { Text = "PROFILE", display = true, weight = Enum.FontWeight.Heavy, TextSize = 13, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = shot.ZIndex + 3 })
	onClick(shotBtn, function()
		MenuController.openPlayerProfile(player.UserId)
	end)
	local name = Gui.label(prof, {
		Text = player.DisplayName,
		display = true,
		TextSize = 42,
		TextStrokeTransparency = 0.6,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(420, 46),
		Position = UDim2.fromOffset(118, -4),
	})
	local sub = Gui.label(prof, {
		Text = "",
		TextSize = 20,
		weight = Enum.FontWeight.Medium,
		RichText = true,
		TextStrokeTransparency = 0.6,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(420, 24),
		Position = UDim2.fromOffset(118, 44),
	})
	Gui.plate(prof, { Size = UDim2.fromOffset(84, 6), Position = UDim2.fromOffset(118, 80) }, Gui.SIGNAL)
	local badge = Gui.label(prof, {
		Text = "",
		TextSize = 15,
		weight = Enum.FontWeight.Medium,
		TextColor3 = Gui.SIGNAL,
		TextStrokeTransparency = 0.6,
		Size = UDim2.fromOffset(330, 18),
		Position = UDim2.fromOffset(214, 74),
	})

	-- currencies under the headshot: icon, amount, a "+" to the shop
	local cur = make("Frame", { Size = UDim2.fromOffset(560, 40), Position = UDim2.fromOffset(0, 112), BackgroundTransparency = 1 }, prof)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, cur)
	local function currency(order, iconFn)
		iconFn(cur, 32).LayoutOrder = order
		local amount = Gui.label(cur, {
			Text = "0",
			display = true,
			TextSize = 28,
			TextStrokeTransparency = 0.6,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 36),
			LayoutOrder = order + 1,
		})
		local plus = make("TextButton", {
			Text = "+",
			FontFace = Gui.display(),
			TextSize = 34,
			TextColor3 = Gui.SIGNAL,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(28, 36),
			LayoutOrder = order + 2,
		}, cur)
		return amount, plus
	end
	local vp, vpPlus = currency(1, Gui.icon.vp)
	make("Frame", { Size = UDim2.fromOffset(16, 1), BackgroundTransparency = 1, LayoutOrder = 4 }, cur)
	local gold, goldPlus = currency(5, Gui.icon.gold)
	goldPlus.Visible = false -- Gold is earned, not bought
	onClick(vpPlus, function()
		MenuController.go("shop")
	end)
	ui.currencies = ui.currencies or {}
	table.insert(ui.currencies, { vp = vp, gold = gold })

	-- the nav across the top, the same as every main screen's
	local nav = navBar(p, "home")

	-- down the right edge (The Spike has its icons there): the daily reward (a dot when one's
	-- waiting), codes, and the admin panel for developers
	local extras = make("Frame", { Name = "Extras", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M + 12, 0, NAV_BOTTOM + 22), Size = UDim2.fromOffset(96, 3 * 84), BackgroundTransparency = 1 }, p)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, extras)
	local dailyBtn = navItem(extras, Extra.iconKey("IconDaily", "IconStar"), "Daily", { LayoutOrder = 1 })
	local dailyDot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 20, 0, 8), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Gui.ALERT, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, dailyBtn)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dailyDot)
	onClick(dailyBtn, function()
		ui.daily.modal.root.Visible = true
		Extra.onRequirementsOpen(profile())
		MenuController.refresh()
	end)
	onClick(navItem(extras, Extra.iconKey("IconCode", "IconShop"), "Codes", { LayoutOrder = 2 }), function()
		ui.codes.modal.root.Visible = true
		Extra.onRequirementsOpen(profile())
		MenuController.refresh()
	end)
	local adminBtn = navItem(extras, Extra.iconKey("IconAdmin", "IconSettings"), "Admin", { LayoutOrder = 3, Visible = false })
	onClick(adminBtn, function()
		MenuController.openAdmin()
	end)

	-- the admin panel's running events (2x VP, 2x Gold) with their time left, under the nav
	local chips = make("Frame", { Name = "Events", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 30, 0, 160), Size = UDim2.fromOffset(620, 40), BackgroundTransparency = 1 }, p)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	local eventChips = {}
	for i, kind in ipairs(Config.Admin.Events) do
		local plate = Gui.plate(chips, { Size = UDim2.fromOffset(230, 38), LayoutOrder = i, Visible = false }, Gui.GOLD)
		local l = Gui.label(plate, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 21, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
		eventChips[kind] = { plate = plate, label = l }
	end
	-- your own 2x VP boost (Config.Boosts), in the Shop's signal yellow
	local boostPlate = Gui.plate(chips, { Size = UDim2.fromOffset(260, 38), LayoutOrder = 9, Visible = false }, Gui.SIGNAL)
	local boostChip = { plate = boostPlate, label = Gui.label(boostPlate, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 21, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 }) }

	-- the left column under the profile (placeHome moves the two together)
	local column = make("Frame", { Name = "Column", Size = UDim2.fromOffset(470, 546), Position = UDim2.fromOffset(M, 24 + PROFILE_H + 20), BackgroundTransparency = 1 }, p)

	-- the featured recruit, as an event card: the tier as a huge faint watermark (no character
	-- art: the card sells the pull), halftone grain, the ability, quick links along the bottom
	local ev = Gui.card(column, { Size = UDim2.fromOffset(470, 292), ClipsDescendants = true })
	Gui.halftone(ev, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.6, 1), ImageColor3 = Gui.CHALK, ImageTransparency = 0.93 })
	local evMark = Gui.label(ev, {
		Text = "",
		display = true,
		weight = Enum.FontWeight.Heavy,
		TextSize = 230,
		TextTransparency = 0.92,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 10, 1, 40),
		Size = UDim2.fromOffset(320, 240),
	})
	Gui.label(ev, { Text = "Featured recruit", TextSize = 15, weight = Enum.FontWeight.Medium, TextColor3 = Gui.HAIRLINE, Size = UDim2.fromOffset(300, 18), Position = UDim2.fromOffset(18, 14) })
	local evName = Gui.label(ev, { Text = "", display = true, TextSize = 50, Size = UDim2.fromOffset(330, 54), Position = UDim2.fromOffset(16, 30) })
	local evTier = Gui.plate(ev, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 18), Size = UDim2.fromOffset(78, 34) }, Gui.SIGNAL)
	local evTierText = Gui.label(evTier, { Text = "", display = true, TextSize = 24, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	local evLine = Gui.label(ev, { Text = "", TextSize = 16, weight = Enum.FontWeight.Medium, Size = UDim2.fromOffset(434, 20), Position = UDim2.fromOffset(18, 88) })
	local evBlurb = Gui.label(ev, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.fromOffset(434, 56), Position = UDim2.fromOffset(18, 112) })
	local evOdds = Gui.label(ev, { Text = "", TextSize = 13, TextColor3 = Gui.DIM, Size = UDim2.fromOffset(434, 16), Position = UDim2.fromOffset(18, 170) })
	local links = make("Frame", { Size = UDim2.fromOffset(434, 80), Position = UDim2.fromOffset(12, 200), BackgroundTransparency = 1 }, ev)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, links)
	onClick(navItem(links, Gui.icon.recruit, "Recruit", { LayoutOrder = 1 }), goRecruit)
	onClick(navItem(links, "IconRanks", "Odds", { LayoutOrder = 2 }), function()
		MenuController.openTable("Char")
	end)
	onClick(navItem(links, "IconPlayers", "Your team", { LayoutOrder = 3 }), function()
		MenuController.go("players")
	end)

	-- your record: a warm card, the win streak big, the rest in a row
	local stats = Gui.card(column, { Size = UDim2.fromOffset(470, 118), Position = UDim2.fromOffset(0, 304) }, Color3.fromRGB(120, 92, 24))
	Gui.label(stats, { Text = "Win streak", TextSize = 15, weight = Enum.FontWeight.Medium, TextColor3 = Gui.SIGNAL_HOT, Size = UDim2.fromOffset(140, 18), Position = UDim2.fromOffset(18, 12) })
	local counters = {}
	counters.streak = {
		value = Gui.label(stats, { Text = "0", display = true, TextSize = 54, Size = UDim2.fromOffset(120, 56), Position = UDim2.fromOffset(16, 30) }),
		sub = Gui.label(stats, { Text = "", TextSize = 13, TextColor3 = Gui.CHALK, TextTransparency = 0.2, Size = UDim2.fromOffset(120, 16), Position = UDim2.fromOffset(18, 88) }),
	}
	make("Frame", { Size = UDim2.fromOffset(1, 86), Position = UDim2.fromOffset(150, 16), BackgroundColor3 = Gui.HAIRLINE, BackgroundTransparency = 0.5, BorderSizePixel = 0 }, stats)
	for i, def in ipairs({ { "wins", "Wins" }, { "kills", "Spike kills" }, { "aces", "Aces" }, { "blocks", "Blocks" } }) do
		local x = 164 + (i - 1) * 74
		counters[def[1]] = {
			value = Gui.label(stats, { Text = "0", display = true, TextSize = 30, Size = UDim2.fromOffset(70, 34), Position = UDim2.fromOffset(x, 22) }),
			label = Gui.label(stats, { Text = def[2], TextSize = 13, TextColor3 = Gui.CHALK, TextTransparency = 0.2, Size = UDim2.fromOffset(72, 16), Position = UDim2.fromOffset(x, 60) }),
			sub = Gui.label(stats, { Text = "", TextSize = 12, TextColor3 = Gui.DIM, Size = UDim2.fromOffset(72, 14), Position = UDim2.fromOffset(x, 78) }),
		}
	end

	-- the tutorial, until it's done
	local tut = Gui.card(column, { Size = UDim2.fromOffset(470, 112), Position = UDim2.fromOffset(0, 434), Visible = false })
	Gui.label(tut, { Text = "New here? Play the tutorial", display = true, TextSize = 22, Size = UDim2.fromOffset(434, 26), Position = UDim2.fromOffset(18, 10) })
	local tutLine = Gui.label(tut, { Text = "", TextSize = 14, TextColor3 = Gui.DIM, RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.fromOffset(434, 34), Position = UDim2.fromOffset(18, 38) })
	local tutGo = Gui.plateButton(tut, { Size = UDim2.fromOffset(180, 32), Position = UDim2.fromOffset(12, 72) }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	local tutGoLabel = Gui.label(tutGo, { Text = "Start tutorial", display = true, TextSize = 18, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	local tutProgress = Gui.label(tut, { Text = "", display = true, TextSize = 16, TextColor3 = Gui.SIGNAL_HOT, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 76), Size = UDim2.fromOffset(160, 24) })
	onClick(tutGo, function()
		Extra.openHowTo(Extra.mustTutorial())
	end)

	-- tip, bottom left: plain text over the room
	local tipText = Gui.label(p, {
		Text = TIPS[1],
		TextSize = 18,
		TextStrokeTransparency = 0.5,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, M, 1, -M - 6),
		Size = UDim2.new(1, -(M * 2 + 360 + 14 + 150 + 40), 0, 48),
	})

	-- Match: the one loud thing on the screen, a slanted signal-yellow plate with print grain
	local matchPos = UDim2.new(1, -M, 1, -M)
	local match, matchPlate = Gui.plateButton(p, { Name = "Match", AnchorPoint = Vector2.new(1, 1), Position = matchPos, Size = UDim2.fromOffset(360, 120) }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	Gui.halftone(matchPlate.Body, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.7, 1) })
	-- two racing stripes at the same 12 degree lean as the plate's ends
	for i = 1, 2 do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -60 + (i - 1) * 18, 0.5, 0),
			Size = UDim2.fromOffset(10, 124),
			Rotation = 12,
			BackgroundColor3 = Gui.LINE,
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
		}, match)
	end
	local inset = Gui.plateInset(matchPlate)
	local ball = Gui.icon.vp(match, 54)
	ball.Position = UDim2.fromOffset(inset, 33)
	Gui.label(match, { Text = "Match", display = true, weight = Enum.FontWeight.Heavy, TextSize = 64, TextColor3 = Gui.LINE, Size = UDim2.fromOffset(220, 70), Position = UDim2.fromOffset(inset + 66, 12) })
	local matchSub = Gui.label(match, { Text = "", TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Gui.LINE, Size = UDim2.fromOffset(240, 20), Position = UDim2.fromOffset(inset + 70, 80) })
	onClick(match, function()
		MenuController.go("match")
	end)

	-- Recruit Player: a square hairline button beside it
	local recruit = Gui.cardButton(p, { Name = "RecruitPlayer", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M - 360 - 14, 1, -M), Size = UDim2.fromOffset(150, 120) })
	local rIcon = Gui.icon.recruit(recruit, 40, Gui.HAIRLINE)
	rIcon.AnchorPoint = Vector2.new(0.5, 0)
	rIcon.Position = UDim2.new(0.5, 0, 0, 16)
	Gui.label(recruit, { Text = "Recruit Player", display = true, TextSize = 19, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 64), TextXAlignment = Enum.TextXAlignment.Center })
	local rSub = Gui.label(recruit, { Text = "", TextSize = 13, TextColor3 = Gui.DIM, Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(6, 90), TextXAlignment = Enum.TextXAlignment.Center })
	onClick(recruit, goRecruit)

	-- your AI is playing for you: a red-edged card over the buttons
	local rejoin = Gui.card(p, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M, 1, -M - 134), Size = UDim2.fromOffset(524, 64), Visible = false })
	rejoin.UIStroke.Color = Gui.ALERT
	rejoin.UIStroke.Thickness = 2
	Gui.label(rejoin, { Text = "Your AI is playing for you", display = true, TextSize = 22, Size = UDim2.fromOffset(340, 26), Position = UDim2.fromOffset(18, 8) })
	Gui.label(rejoin, { Text = "Jump back in at the next serve.", TextSize = 14, TextColor3 = Gui.DIM, Size = UDim2.fromOffset(340, 18), Position = UDim2.fromOffset(18, 36) })
	local rejoinGo = Gui.plateButton(rejoin, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(130, 40) }, Gui.ALERT, Color3.fromRGB(250, 92, 112))
	Gui.label(rejoinGo, { Text = "Rejoin", display = true, TextSize = 20, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	onClick(rejoinGo, function()
		Net.get("Lobby"):FireServer("rejoin")
	end)

	ui.home = {
		profile = prof,
		column = column,
		name = name,
		sub = sub,
		badge = badge,
		evName = evName,
		evTier = evTier,
		evTierText = evTierText,
		evMark = evMark,
		evLine = evLine,
		evBlurb = evBlurb,
		evOdds = evOdds,
		tipText = tipText,
		match = match,
		matchPos = matchPos,
		matchSub = matchSub,
		rSub = rSub,
		rejoin = rejoin,
		featured = 1,
		stats = stats,
		counters = counters,
		tut = tut,
		tutGoLabel = tutGoLabel,
		tutLine = tutLine,
		tutProgress = tutProgress,
		navWidth = nav.Size.X.Offset,
		dailyDot = dailyDot,
		adminBtn = adminBtn,
		eventChips = eventChips,
		boostChip = boostChip,
	}
end

-- Home's running-event chips, the daily reward's dot and the Admin button (every second while
-- Home shows: the chips count down).
function Extra.refreshHome(prof)
	local hm = ui.home
	for kind, chip in pairs(hm.eventChips) do
		local left = Extra.eventLeft(kind)
		chip.plate.Visible = left > 0
		if left > 0 then
			chip.label.Text = string.format("%dx %s  %s", Config.Admin.Multiplier, kind, Extra.clockText(left))
		end
	end
	local boostLeft = (prof.boostVP or 0) - (os.clock() - Extra.profileAt)
	hm.boostChip.plate.Visible = boostLeft > 0
	if boostLeft > 0 then
		hm.boostChip.label.Text = string.format("Your %dx VP  %s", Config.Boosts.Multiplier, Extra.clockText(boostLeft))
	end
	local d = prof.daily
	hm.dailyDot.Visible = d ~= nil and (d.ready == true or (d.opensIn or 0) - (os.clock() - Extra.profileAt) <= 0)
	hm.adminBtn.Visible = prof.admin == true
end

-- Home's profile sits under Roblox's own buttons at the top left, whatever size they are: the
-- menus ignore the GUI inset, so it starts GetGuiInset's height down (pixels, divided by the
-- canvas scale), and the left column follows it. When the name row still reaches the nav across
-- the top, the name stops short of it.
local function placeHome()
	local hm = ui.home
	if not hm then
		return
	end
	local inset = GuiService:GetGuiInset()
	local top = math.max(24, inset.Y / canvasScale.Scale + 12)
	hm.profile.Position = UDim2.fromOffset(M, top)
	hm.column.Position = UDim2.fromOffset(M, top + PROFILE_H + 20)
	local width = 420
	if top - 4 < NAV_BOTTOM then
		local navLeft = canvas.Size.X.Offset / 2 + 30 - hm.navWidth / 2
		width = math.clamp(navLeft - (M + 118) - 16, 160, 420)
	end
	hm.name.Size = UDim2.fromOffset(width, 46)
	hm.sub.Size = UDim2.fromOffset(width, 24)
end

-- A sub-screen's back button and title reach into the top bar on short screens: there they slide
-- right of Roblox's buttons (TopbarInset is the part of the bar those buttons leave free).
local function placeHeaders()
	local s = canvasScale.Scale
	local x = M
	if 64 * s < GuiService:GetGuiInset().Y then
		x = math.max(M, GuiService.TopbarInset.Min.X / s + 12)
	end
	for _, back in ipairs(ui.headers or {}) do
		back.Position = UDim2.fromOffset(x, 64)
	end
	-- the main screens' currencies (and a player page's back arrow) sit under Roblox's buttons
	local top = math.max(24, GuiService:GetGuiInset().Y / s + 12)
	for _, strip in ipairs(ui.strips or {}) do
		strip.Position = UDim2.fromOffset(M, top)
	end
	-- the Match screen's title under the currencies, and its cards under the title
	local ms = ui.matchScreen
	if ms then
		ms.back.Position = UDim2.fromOffset(M, top + 46)
		ms.row.Position = UDim2.fromOffset(0, top + 46 + 70)
	end
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
	hm.sub.Text = string.format('Playing <font color="#%s"><b>%s</b></font>, %s %s', tierColor(c.Tier):ToHex(), c.Name, c.Tier, string.lower(roleName(c.Role)))
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
		hm.evTierText.Text = f.Tier
		hm.evMark.Text = f.Tier
		Gui.tint(hm.evTier, tierColor(f.Tier))
		hm.evLine.Text = string.format("%s, %d cm. %s", roleName(f.Role), f.Height, def and def.Name or "")
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
	if tut and not tut.done then
		local vp, gold, spins = Tutorial.reward()
		local _, n, total = Tutorial.progress(tut.steps)
		hm.tutLine.Text = string.format('Four quick drills: spike, block, serve, dig. Reward: <font color="#FFD35A"><b>%d VP, %s Gold and %d free recruits</b></font>', vp, Gui.num(gold), spins)
		hm.tutProgress.Text = n > 0 and string.format("%d of %d done", n, total) or ""
		hm.tutGoLabel.Text = n > 0 and "Continue tutorial" or "Start tutorial"
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
	Extra.refreshHome(prof)
end

------------------------------------------------------------------------------------------
-- Help
------------------------------------------------------------------------------------------

-- How to play: one row per action, its keys drawn as keycaps, and what it does.
local HELP_ROWS = {
	{ "Move", { "A", "D" }, "Or the arrow keys. You only ever move along the court." },
	{ "Spike", { "Space", "Z" }, "On the ground your run-up jump (Double approach in Settings: once to run in, again to jump), in the air the spike. J and left click too." },
	{ "Receive", { "S", "K" }, "Press a little before the ball arrives: early is perfect. Right click works too." },
	{ "Slide / feint", { "C", "Shift" }, "On the ground a diving receive that never costs stamina, in the air a roll shot." },
	{ "Block", { "W" }, "Hold near the net, then let go to jump. Longer holds jump higher." },
	{ "Set", { "E", "V" }, "Hold toward the net for a quick, away for a back set, nothing for an open set." },
	{ "Serve", { "F", "X" }, "F serves underhand and always goes in. Tap X to serve overhand, hold X to toss for a jump serve." },
	{ "Ability", { "Q" }, "Iron Wall, Turnabout and Rally Cry. The rest work on their own." },
	{ "Timeout", { "T" }, "At the next dead ball: refills stamina, opens the rotation and lets you change character. Press again before then to call it off." },
}

local function buildHelp()
	local m = modal("Help", "How to play", 960, 660, true)
	local list = make("Frame", { Position = UDim2.fromOffset(24, 96), Size = UDim2.new(1, -48, 0, #HELP_ROWS * 52), BackgroundTransparency = 1, ZIndex = 21 }, m.panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i, row in ipairs(HELP_ROWS) do
		local r = make("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.96, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 21 }, list)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, r)
		Gui.label(r, { Text = row[1], display = true, TextSize = 22, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(150, 46), ZIndex = 22 })
		local keys = make("Frame", { Position = UDim2.fromOffset(166, 8), Size = UDim2.fromOffset(150, 30), BackgroundTransparency = 1, ZIndex = 22 }, r)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, keys)
		for j, k in ipairs(row[2]) do
			local cap = make("Frame", { Size = UDim2.fromOffset(#k > 1 and 58 or 34, 30), BackgroundColor3 = Gui.CHALK, BorderSizePixel = 0, LayoutOrder = j, ZIndex = 22 }, keys)
			make("UICorner", { CornerRadius = UDim.new(0, 5) }, cap)
			make("UIStroke", { Color = Color3.fromRGB(150, 156, 172), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, cap)
			Gui.label(cap, { Text = k, display = true, weight = Enum.FontWeight.Heavy, TextSize = 18, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		end
		Gui.label(r, { Text = row[3], TextSize = 16, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(320, 0), Size = UDim2.new(1, -332, 1, 0), ZIndex = 22 })
	end
	Gui.label(m.panel, {
		Text = "Recruit players with V Points, then spend Gold on their stats in Players. Every character's stats grow to its own ceiling: higher ranks cost more and go higher.",
		TextSize = 16,
		TextColor3 = Gui.CHALK,
		TextWrapped = true,
		Position = UDim2.new(0, 26, 1, -64),
		Size = UDim2.new(1, -52, 0, 44),
		ZIndex = 21,
	})
	ui.help = m
end

------------------------------------------------------------------------------------------
-- Recruit
------------------------------------------------------------------------------------------

local PLAYER_BANNERS = { "Char" }
local COSMETIC_BANNERS = { "Style", "Color", "Trail", "Effect", "Pose" }
-- each banner's card stock (a flat colour under halftone and a gloss streak) and its icon
local BANNER_ART = {
	Char = { color = Color3.fromRGB(214, 138, 40), icon = "IconPlayers" },
	Style = { color = Color3.fromRGB(58, 108, 214), icon = "IconJump" },
	Color = { color = Color3.fromRGB(164, 70, 196), icon = "IconStar" },
	Trail = { color = Color3.fromRGB(28, 150, 164), icon = "IconSpeed" },
	Effect = { color = Color3.fromRGB(206, 62, 62), icon = "IconAttack" },
	Pose = { color = Color3.fromRGB(58, 156, 88), icon = "IconRanks" },
}

-- Recruit, laid out like The Spike's: the Player / Cosmetic toggle and the banners down the left,
-- the banner's big title, description, odds and tools in the middle over the gym, and Recruit x1
-- (a chalk panel) and x10 (signal yellow) bottom right, each with its cost in a dark pill.
local function buildRecruit()
	local p = page("recruit")
	header(p, "Recruit Player")

	local left = make("Frame", { Name = "Banners", Position = UDim2.fromOffset(M, 136), Size = UDim2.fromOffset(330, 620), BackgroundTransparency = 1 }, p)
	local _, setTab = segmented(left, { { key = "Player", text = "Player" }, { key = "Cosmetic", text = "Cosmetic" } }, { Name = "Tabs", Size = UDim2.new(1, 0, 0, 50) }, function(key)
		recruitTab = key
		banner = key == "Player" and "Char" or "Style"
		MenuController.refresh()
	end)
	local list = make("Frame", { Name = "List", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64), BackgroundTransparency = 1 }, left)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rows = {}
	for i, kind in ipairs(SP.Order) do
		local art = BANNER_ART[kind]
		local b = make("TextButton", { Name = kind, Size = UDim2.new(1, 0, 0, 100), BackgroundColor3 = art.color:Lerp(Color3.new(0, 0, 0), 0.3), BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = i, ClipsDescendants = true }, list)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
		Gui.halftone(b, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.75, 1), ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.72 })
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.62, 0.5), Size = UDim2.new(0, 46, 2, 0), Rotation = 28, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, BorderSizePixel = 0 }, b)
		Gui.iconImage(b, art.icon, 66, Color3.new(1, 1, 1), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), ImageTransparency = 0.45 })
		Gui.label(b, { Text = bannerName(kind), display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextStrokeTransparency = 0.45, Position = UDim2.fromOffset(16, 16), Size = UDim2.new(1, -100, 0, 34) })
		local owned = Gui.label(b, { Text = "", TextSize = 15, weight = Enum.FontWeight.Medium, TextStrokeTransparency = 0.55, Position = UDim2.fromOffset(18, 58), Size = UDim2.new(1, -100, 0, 18) })
		local dim = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0 }, b)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, dim)
		local edge = make("UIStroke", { Color = Gui.SIGNAL, Thickness = 3, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		b.MouseEnter:Connect(function()
			if banner ~= kind then
				dim.BackgroundTransparency = 0.25
				if Gui.onHover then
					Gui.onHover()
				end
			end
		end)
		b.MouseLeave:Connect(function()
			dim.BackgroundTransparency = banner == kind and 1 or 0.45
		end)
		onClick(b, function()
			banner = kind
			MenuController.refresh()
		end)
		rows[kind] = { button = b, edge = edge, dim = dim, owned = owned }
	end

	-- centre: the banner's title, description, odds and tools
	local info = make("Frame", { Name = "Info", Position = UDim2.fromOffset(M + 366, 146), Size = UDim2.fromOffset(660, 440), BackgroundTransparency = 1 }, p)
	local title = Gui.label(info, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 80, TextStrokeTransparency = 0.45, Size = UDim2.new(1, 0, 0, 86) })
	Gui.plate(info, { Size = UDim2.fromOffset(100, 7), Position = UDim2.fromOffset(6, 90) }, Gui.SIGNAL)
	local desc = Gui.label(info, { Text = "", TextSize = 20, weight = Enum.FontWeight.Medium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextStrokeTransparency = 0.55, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(4, 110) })
	local odds = Gui.label(info, { Text = "", TextSize = 18, weight = Enum.FontWeight.Medium, RichText = true, TextWrapped = true, TextStrokeTransparency = 0.55, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(4, 172) })
	local tableBtn = hairButton(info, { Name = "Odds", Size = UDim2.fromOffset(220, 48), Position = UDim2.fromOffset(0, 210) }, "Probability Table", 21)
	onClick(tableBtn, function()
		MenuController.openTable(banner)
	end)
	local autoBtn, autoL = hairButton(info, { Name = "Auto", Size = UDim2.fromOffset(310, 48), Position = UDim2.fromOffset(232, 210) }, "", 21)
	onClick(autoBtn, function()
		if profile().autoRolling then
			Net.get("Profile"):FireServer("stop")
		else
			Net.get("Profile"):FireServer("autoroll", banner)
		end
	end)
	Gui.label(info, { Text = "Auto-sell new pulls of", TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, TextStrokeTransparency = 0.6, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(4, 272) })
	local sells = {}
	for i, r in ipairs(SP.AutoSellable) do
		local b, l = hairButton(info, { Name = "Sell" .. r, Size = UDim2.fromOffset(160, 42), Position = UDim2.fromOffset((i - 1) * 170, 298) }, "", 19)
		onClick(b, function()
			local on = profile().autoSell and profile().autoSell[r]
			Net.get("Profile"):FireServer("autosell", r, not on)
		end)
		sells[r] = { button = b, label = l }
	end
	local status = Gui.label(info, { Text = "", TextSize = 17, weight = Enum.FontWeight.Medium, TextColor3 = Gui.SIGNAL_HOT, TextWrapped = true, TextStrokeTransparency = 0.5, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(4, 356) })

	-- bottom right: Recruit x1 and x10
	local function costPill(parent)
		local pill = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(176, 36), BackgroundColor3 = Gui.LINE, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 3 }, parent)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
		local icon = Gui.icon.vp(pill, 26)
		icon.Position = UDim2.fromOffset(6, 5)
		return Gui.label(pill, { Text = "", display = true, TextSize = 22, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -42, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	end
	local x10, x10Plate = Gui.plateButton(p, { Name = "Recruit10", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M, 1, -M), Size = UDim2.fromOffset(310, 118) }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	Gui.label(x10, { Text = "Recruit x10", display = true, weight = Enum.FontWeight.Heavy, TextSize = 36, TextColor3 = Gui.LINE, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 42), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	local x10Cost = costPill(x10)
	local x1 = make("TextButton", { Name = "Recruit1", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M - 326, 1, -M), Size = UDim2.fromOffset(256, 118), BackgroundColor3 = Color3.fromRGB(226, 230, 238), BorderSizePixel = 0, Text = "", AutoButtonColor = false }, p)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, x1)
	local x1Scale = make("UIScale", { Scale = 1 }, x1)
	x1.MouseEnter:Connect(function()
		x1.BackgroundColor3 = Color3.fromRGB(246, 248, 252)
		if Gui.onHover then
			Gui.onHover()
		end
	end)
	x1.MouseLeave:Connect(function()
		x1.BackgroundColor3 = Color3.fromRGB(226, 230, 238)
		x1Scale.Scale = 1
	end)
	x1.MouseButton1Down:Connect(function()
		x1Scale.Scale = 0.97
	end)
	x1.MouseButton1Up:Connect(function()
		x1Scale.Scale = 1
	end)
	Gui.label(x1, { Text = "Recruit x1", display = true, weight = Enum.FontWeight.Heavy, TextSize = 34, TextColor3 = Gui.LINE, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 42), TextXAlignment = Enum.TextXAlignment.Center })
	local x1Cost = costPill(x1)
	local freeTag = Gui.plate(p, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M - 330, 1, -M - 124), Size = UDim2.fromOffset(130, 30), Visible = false }, Gui.ALERT)
	local freeL = Gui.label(freeTag, { Text = "", display = true, TextSize = 18, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	local lastSpin = 0
	local function spin(n, lucky)
		if os.clock() - lastSpin < 0.6 or seqActive then
			return
		end
		lastSpin = os.clock()
		sendProfile("spin", banner, n, lucky and "lucky" or nil)
	end
	Gui.pressSound(x1, "UIConfirm")
	Gui.pressSound(x10, "UIConfirm")
	x1.MouseButton1Click:Connect(function()
		spin(1)
	end)
	x10.MouseButton1Click:Connect(function()
		spin(10)
	end)


	-- lucky spins (the owner: "like volleyball legends with enhanced rates"): a gold strip over the
	-- recruit buttons. Each button spends lucky spins, or buys the pack with that many (Robux);
	-- they also come from codes, daily rewards and gifts. Odds opens their table, Gift sends a pack.
	local lucky = Gui.card(p, { Name = "Lucky", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M, 1, -M - 172), Size = UDim2.fromOffset(582, 110), ClipsDescendants = true }, Color3.fromRGB(120, 88, 14))
	Gui.halftone(lucky, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.7, 1), ImageColor3 = Gui.CHALK, ImageTransparency = 0.93 })
	Gui.label(lucky, { Text = "Lucky spins", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, TextStrokeTransparency = 0.6, Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(250, 32) })
	local luckyHave = Gui.label(lucky, { Text = "", display = true, TextSize = 19, TextColor3 = Gui.GOLD_LIGHT, TextStrokeTransparency = 0.6, Position = UDim2.fromOffset(16, 42), Size = UDim2.fromOffset(250, 22) })
	local luckyOdds = Gui.label(lucky, { Text = "", TextSize = 14, weight = Enum.FontWeight.Medium, RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextStrokeTransparency = 0.6, Position = UDim2.fromOffset(16, 68), Size = UDim2.fromOffset(256, 36) })
	local luckyButtons = {}
	for i, n in ipairs({ 1, 10 }) do
		local x = 282 + (i - 1) * 150
		local b = Gui.plateButton(lucky, { Position = UDim2.fromOffset(x, 10), Size = UDim2.fromOffset(140, 58) }, Gui.GOLD, Gui.GOLD_LIGHT)
		b:SetAttribute("Sound", "UIConfirm")
		Gui.label(b, { Text = "Lucky x" .. n, display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, TextColor3 = Gui.LINE, Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
		local sub = Gui.label(b, { Text = "", display = true, TextSize = 16, TextColor3 = Gui.LINE, Position = UDim2.fromOffset(0, 31), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
		-- the pack with exactly that many (Config.Lucky.Packs)
		local packIndex = nil
		for j, pk in ipairs(Config.Lucky.Packs) do
			if pk.Lucky == n then
				packIndex = j
			end
		end
		onClick(b, function()
			local prof = profile()
			if prof.dev or (prof.lucky or 0) >= n then
				spin(n, true)
				return
			end
			-- not enough: buy the pack with that many
			local pack = packIndex and Config.Lucky.Packs[packIndex]
			if pack and pack.Id ~= 0 then
				pcall(function()
					MarketplaceService:PromptProductPurchase(player, pack.Id)
				end)
			elseif pack and prof.studio then
				Net.get("Profile"):FireServer("buy", packIndex, "Lucky")
			else
				toast("Lucky spins go on sale soon.")
			end
		end)
		luckyButtons[i] = { button = b, sub = sub, n = n, packIndex = packIndex }
	end
	-- pity (Config.Spins.Pity), on the Characters banner: how far along each is, and the S+ your
	-- lucky pity owes you
	local pityCard = Gui.card(p, { Name = "Pity", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M, 1, -M - 290), Size = UDim2.fromOffset(582, 62) }, Color3.fromRGB(70, 20, 70))
	local pityL = Gui.label(pityCard, { Text = "", display = true, TextSize = 17, RichText = true, TextWrapped = true, TextStrokeTransparency = 0.6, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -170, 1, 0) })
	local pityBtn = hairButton(pityCard, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(140, 32) }, "Pick S+", 15)
	onClick(pityBtn, function()
		MenuController.openPityPick()
	end)
	local oddsL = hairButton(lucky, { Position = UDim2.fromOffset(282, 74), Size = UDim2.fromOffset(140, 28) }, "Lucky odds", 15)
	onClick(oddsL, function()
		MenuController.openTable(banner, true)
	end)
	local moreL = hairButton(lucky, { Position = UDim2.fromOffset(432, 74), Size = UDim2.fromOffset(140, 28) }, "More lucky spins", 15)
	onClick(moreL, function()
		Extra.shopTab = "Lucky"
		MenuController.go("shop")
	end)
	for i, pack in ipairs(Config.Lucky.Packs) do
		if pack.Id ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(pack.Id, Enum.InfoType.Product)
				end)
				if ok and info and info.PriceInRobux then
					packPrices.Lucky[i] = info.PriceInRobux
					MenuController.refresh()
				end
			end)
		end
	end

	ui.recruit = { setTab = setTab, rows = rows, title = title, desc = desc, odds = odds, autoL = autoL, sells = sells, status = status, x1 = x1, x10 = x10, x1Cost = x1Cost, x10Cost = x10Cost, x10Plate = x10Plate, freeTag = freeTag, freeL = freeL, luckyHave = luckyHave, luckyOdds = luckyOdds, luckyButtons = luckyButtons, pityCard = pityCard, pityL = pityL }
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
		row.edge.Transparency = on and 0 or 1
		row.dim.BackgroundTransparency = on and 1 or 0.45
		local have, total = ownedCount(prof, kind)
		row.owned.Text = string.format("%d of %d unlocked", have, total)
	end
	R.title.Text = bannerName(banner)
	R.desc.Text = banner == "Char" and "Recruit named players: each has a role, a height, stat ceilings and (S and S+) an ability. Upgrade them with Gold in Players." or SP.Banners[banner].Blurb
	local o = Spins.odds(banner, Extra.recruitWeights(banner))
	local parts = {}
	for _, r in ipairs(Config.Rarity.Order) do
		if o[r] > 0 then
			table.insert(parts, string.format('<font color="#%s">%s %.1f%%</font>', Spins.rarityColor(r):ToHex(), r, o[r] * 100))
		end
	end
	R.odds.Text = table.concat(parts, "     ")
	if prof.autoRolling then
		local n = prof.reveal and prof.reveal.auto or 0
		R.autoL.Text = string.format("Stop auto-roll (%d)", n)
		R.autoL.TextColor3 = Color3.fromRGB(255, 120, 130)
	else
		R.autoL.Text = "Auto-roll until " .. SP.AutoRollTarget
		R.autoL.TextColor3 = Config.Rarity.Colors.Legendary
	end
	for r, s in pairs(R.sells) do
		local on = prof.autoSell and prof.autoSell[r]
		s.label.Text = string.format("%s: %s", r, on and "on" or "off")
		s.label.TextColor3 = on and Spins.rarityColor(r) or Gui.DIM
	end
	local free = prof.dev == true
	local freeSpins = prof.freeSpins or 0
	R.x1Cost.Text = (free and "Free") or (freeSpins > 0 and "Free") or Gui.num(SP.Costs[1])
	R.x10Cost.Text = free and "Free" or Gui.num(SP.Costs[10])
	R.freeTag.Visible = freeSpins > 0
	R.freeL.Text = string.format("%d free", freeSpins)
	R.x1.BackgroundTransparency = (free or freeSpins > 0 or (prof.vp or 0) >= SP.Costs[1]) and 0 or 0.45
	Gui.fade(R.x10Plate, (free or (prof.vp or 0) >= SP.Costs[10]) and 0 or 0.45)
	-- lucky spins: how many, their odds on this banner, and each button's use or price
	local have = prof.lucky or 0
	R.luckyHave.Text = free and "Free for developers" or string.format("You have %d", have)
	local lo = Spins.odds(banner, Spins.LuckyWeights)
	local lparts = {}
	for _, r in ipairs(Config.Rarity.Order) do
		if lo[r] > 0 then
			table.insert(lparts, string.format('<font color="#%s">%s %s%%</font>', Spins.rarityColor(r):ToHex(), r, string.format(lo[r] >= 0.1 and "%.0f" or "%.1f", lo[r] * 100)))
		end
	end
	R.luckyOdds.Text = table.concat(lparts, "  ")
	-- pity: recruits until a random S tier, lucky spins until an S+ (and which)
	R.pityCard.Visible = banner == "Char"
	local pity = prof.pity or {}
	local PT = Config.Spins.Pity
	local pick = pity.pick and Roster.get(pity.pick)
	local nextLucky = pity.owed and (pick and pick.Name or "your pick") or "a random one"
	local gold, red = Spins.rarityColor("Legendary"):ToHex(), Spins.rarityColor("Mythic"):ToHex()
	R.pityL.Text = string.format('Pity: S tier <font color="#%s">%d/%d</font>   S+ <font color="#%s">%d/%d</font>\nLucky pity: S+ <font color="#%s">%d/%d</font> (%s)',
		gold, pity.normal or 0, PT.Normal.Every, red, pity.top or 0, PT.Top.Every, red, pity.lucky or 0, PT.Lucky.Every, nextLucky)
	if ui.pityPick and ui.pityPick.modal.root.Visible then
		Extra.refreshPityPick(prof)
	end
	for _, lb in ipairs(R.luckyButtons) do
		local pack = lb.packIndex and Config.Lucky.Packs[lb.packIndex]
		if free or have >= lb.n then
			lb.sub.Text = "Use " .. lb.n
		elseif pack and pack.Id ~= 0 then
			lb.sub.Text = packPrices.Lucky[lb.packIndex] and ("R$ " .. packPrices.Lucky[lb.packIndex]) or "..."
		else
			lb.sub.Text = prof.studio and "Free in Studio" or "Soon"
		end
	end
end

------------------------------------------------------------------------------------------
-- Probability table
------------------------------------------------------------------------------------------

-- The lucky pity pick (Config.Spins.Pity): the S+ characters, and the one your lucky pity gives
-- you when it's owed (your first lucky pity is a random S+; when it isn't your pick, the next is).
function Extra.buildPityPick()
	local pool = Spins.pityPool("Lucky")
	local cols = math.min(math.max(#pool, 1), 3)
	local rowsN = math.ceil(math.max(#pool, 1) / cols)
	local m = modal("PityPick", "Lucky pity pick", 120 + cols * 250, 240 + rowsN * 150, true)
	local sub = Gui.label(m.panel, { Text = "", TextSize = 17, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -56, 0, 48), Position = UDim2.fromOffset(28, 84), ZIndex = 21 })
	local cards = {}
	for i, key in ipairs(pool) do
		local c = Roster.get(key)
		local x = 40 + ((i - 1) % cols) * 250
		local y = 150 + math.floor((i - 1) / cols) * 150
		local b = make("TextButton", { Name = key, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(230, 130), BackgroundColor3 = Gui.LINE, BackgroundTransparency = 0.15, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 22 }, m.panel)
		local edge = make("UIStroke", { Color = Gui.SIGNAL, Thickness = 3, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		Gui.label(b, { Text = c.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 32, TextColor3 = tierColor(c.Tier), Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 36), ZIndex = 23 })
		local ab = c.Ability and Config.Abilities[c.Ability]
		Gui.label(b, { Text = c.Tier .. "  " .. roleName(c.Role) .. (ab and ("  /  " .. ab.Name) or ""), TextSize = 15, TextColor3 = Gui.CHALK, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -28, 0, 20), ZIndex = 23 })
		local state = Gui.label(b, { Text = "", display = true, TextSize = 18, Position = UDim2.fromOffset(14, 92), Size = UDim2.new(1, -28, 0, 24), ZIndex = 23 })
		onClick(b, function()
			sendProfile("pityPick", key)
		end)
		cards[key] = { edge = edge, state = state }
	end
	ui.pityPick = { modal = m, sub = sub, cards = cards }
end

function Extra.refreshPityPick(prof)
	local PP = ui.pityPick
	if not PP then
		return
	end
	local pity = prof.pity or {}
	local pickName = pity.pick and Roster.get(pity.pick) and Roster.get(pity.pick).Name
	PP.sub.Text = (pity.owed and "Your next lucky pity is your pick" or "Your next lucky pity is a random S+; when it isn't your pick, the one after is")
		.. (pickName and (". Picked: " .. pickName .. ".") or ". Pick one below.")
	for key, c in pairs(PP.cards) do
		local picked = pity.pick == key
		c.edge.Transparency = picked and 0 or 1
		c.state.Text = picked and "YOUR PICK" or (prof.owned and prof.owned.Char and prof.owned.Char[key] and "Owned: pick" or "Pick")
		c.state.TextColor3 = picked and Gui.SIGNAL or Gui.DIM
	end
end

function MenuController.openPityPick()
	if ui.pityPick then
		Extra.refreshPityPick(profile())
		ui.pityPick.modal.root.Visible = true
	end
end

-- How to play (the owner: "introduce all the controls in the tutorial, and also let them know
-- they can change them at any time in the settings... force new players in to the tutorial"):
-- every control on this device (a keyboard's with your own keys), and Start the tutorial. It
-- opens before every tutorial; a new player (no tutorial finished, no match played, not a
-- developer) gets it by itself and can't close it, and the match modes send them to it.
function Extra.mustTutorial(prof)
	prof = prof or profile()
	return prof.tutorial ~= nil and prof.tutorial.done ~= true and not prof.dev and ((prof.record and prof.record.matches) or 0) == 0
end

function Extra.buildHowTo()
	local m = modal("HowTo", "How to play", 960, 660, true)
	local sub = Gui.label(m.panel, { Text = "", TextSize = 17, TextColor3 = Gui.SIGNAL, TextWrapped = true, Size = UDim2.new(1, -56, 0, 22), Position = UDim2.fromOffset(28, 84), ZIndex = 21 })
	local rows = {}
	for i = 1, 14 do
		local col = (i - 1) % 2
		local line = math.floor((i - 1) / 2)
		local r = make("Frame", { Position = UDim2.fromOffset(28 + col * 458, 120 + line * 58), Size = UDim2.fromOffset(446, 52), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0, Visible = false, ZIndex = 21 }, m.panel)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, r)
		local name = Gui.label(r, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 19, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(0.48, -12, 0, 24), ZIndex = 22 })
		local keys = Gui.label(r, { Text = "", display = true, TextSize = 17, TextColor3 = Gui.SIGNAL, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 4), Size = UDim2.new(0.52, -12, 0, 24), ZIndex = 22 })
		local help = Gui.label(r, { Text = "", TextSize = 13, TextColor3 = Gui.DIM, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 18), ZIndex = 22 })
		rows[i] = { frame = r, name = name, keys = keys, help = help }
	end
	local note = Gui.label(m.panel, { Text = "", TextSize = 16, TextWrapped = true, Position = UDim2.fromOffset(28, 534), Size = UDim2.new(1, -330, 0, 44), ZIndex = 21 })
	local go = actionPlate(m.panel, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -24), Size = UDim2.fromOffset(270, 56) }, "Start the tutorial", 22)
	onClick(go, function()
		Extra.howToLocked = false
		m.hide()
		sendLobby("tutorial")
	end)
	local edit = hairButton(m.panel, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -314, 1, -30), Size = UDim2.fromOffset(170, 44) }, "Change keys", 18)
	onClick(edit, function()
		if mods.UIController.openControls then
			mods.UIController.openControls()
		end
	end)
	-- a new player can't close it (the shade or Close just open it again)
	m.root:GetPropertyChangedSignal("Visible"):Connect(function()
		if not m.root.Visible and Extra.howToLocked then
			task.defer(function()
				if Extra.howToLocked and shown then
					m.root.Visible = true
				end
			end)
		end
	end)
	ui.howTo = { modal = m, sub = sub, rows = rows, note = note, edit = edit }
end

function Extra.refreshHowTo()
	local HT = ui.howTo
	local list = {}
	local CT = Config.Controls
	if State.isMobile then
		for _, e in ipairs(CT.Touch) do
			table.insert(list, { e[1], "", e[2] })
		end
		HT.note.Text = "Move and resize your buttons any time: Settings > Touch controls."
		HT.edit.Visible = false
	elseif mods.InputController.lastDevice() == "Gamepad" then
		for _, e in ipairs(CT.Pad) do
			table.insert(list, { e[1], e[2], "" })
		end
		HT.note.Text = "On a keyboard you can change any key in Settings > Controls, any time."
		HT.edit.Visible = false
	else
		for _, action in ipairs(CT.Order) do
			if action ~= "MoveRight" then
				local name = action == "MoveLeft" and "Move" or CT.Names[action]
				local keys = mods.InputController.keysText(action, " / ")
				if action == "MoveLeft" then
					keys = keys .. "  |  " .. mods.InputController.keysText("MoveRight", " / ")
				elseif action == "Spike" then
					keys = keys .. " / Left click"
				elseif action == "Receive" then
					keys = keys .. " / Right click"
				end
				table.insert(list, { name, keys, CT.Help[action] or "" })
			end
		end
		table.insert(list, { "Teammates' abilities", "1 / 2", "Your AI teammates' active abilities" })
		HT.note.Text = "Change any key in Settings > Controls, any time."
		HT.edit.Visible = true
	end
	for i, r in ipairs(HT.rows) do
		local e = list[i]
		r.frame.Visible = e ~= nil
		if e then
			r.name.Text = e[1]
			r.keys.Text = e[2]
			r.help.Text = e[3]
		end
	end
	HT.sub.Text = Extra.mustTutorial() and "Welcome to Spike Rush! Here are the controls; the tutorial teaches them one at a time (a couple of minutes, with a reward)." or "The controls; the tutorial teaches them one at a time."
end

-- forced: a new player's (no closing it).
function Extra.openHowTo(forced)
	if not ui.howTo then
		return
	end
	Extra.howToLocked = forced == true
	Extra.refreshHowTo()
	ui.howTo.modal.root.Visible = true
end

local function buildTable()
	local m = modal("Odds", "Probability Table", 1000, 680, true)
	local sub = Gui.label(m.panel, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, -48, 0, 20), Position = UDim2.fromOffset(28, 82), ZIndex = 21 })
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 112),
		Size = UDim2.new(1, -40, 1, -128),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Gui.HAIRLINE,
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
		local row = make("Frame", { Size = UDim2.new(1, -10, 0, 46), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.96, BorderSizePixel = 0, LayoutOrder = i, Visible = false, ZIndex = 21 }, list)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
		local bar = make("Frame", { Size = UDim2.fromOffset(5, 46), BackgroundColor3 = Gui.WHITE, BorderSizePixel = 0, ZIndex = 22 }, row)
		local n = Gui.label(row, { Text = "", display = true, TextSize = 21, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(0.28, 0, 1, 0), Position = UDim2.fromOffset(18, 0), ZIndex = 22 })
		local d = Gui.label(row, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(0.27, 0, 1, 0), Position = UDim2.fromScale(0.3, 0), ZIndex = 22 })
		-- Boost and Lower (Config.Spins.Favor), on the Characters banner
		local boost, boostL = hairButton(row, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.58, 0, 0.5, 0), Size = UDim2.fromOffset(76, 32) }, "Boost", 15)
		local lower, lowerL = hairButton(row, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.58, 84, 0.5, 0), Size = UDim2.fromOffset(76, 32) }, "Lower", 15)
		local ch = Gui.label(row, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 21, Size = UDim2.new(0.11, 0, 1, 0), Position = UDim2.fromScale(0.76, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 22 })
		local own = Gui.label(row, { Text = "", display = true, TextSize = 16, TextColor3 = Gui.SIGNAL, Size = UDim2.new(0.12, -12, 1, 0), Position = UDim2.fromScale(0.88, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 22 })
		local r = { frame = row, bar = bar, name = n, desc = d, chance = ch, own = own, boost = boost, boostL = boostL, lower = lower, lowerL = lowerL }
		-- a press toggles it (Boost again, or Lower again, resets it)
		onClick(boost, function()
			if r.key then
				local f = profile().favor or {}
				sendProfile("favor", r.key, f[r.key] ~= "up" and "up" or nil)
			end
		end)
		onClick(lower, function()
			if r.key then
				local f = profile().favor or {}
				sendProfile("favor", r.key, f[r.key] ~= "down" and "down" or nil)
			end
		end)
		rows[i] = r
	end
	ui.odds = { modal = m, sub = sub, rows = rows }
end

function MenuController.openTable(kind, lucky)
	local O = ui.odds
	local prof = profile()
	O.modal.title.Text = bannerName(kind) .. (lucky and ": Lucky Spin Odds" or ": Probability Table")
	O.sub.Text = string.format("Every pull is one of these. Duplicates turn into V Points (%s).", table.concat((function()
		local parts = {}
		for _, r in ipairs(Config.Rarity.Order) do
			table.insert(parts, r .. " " .. Spins.sellValue(r))
		end
		return parts
	end)(), ", "))
	O.kind, O.lucky = kind, lucky
	-- the Characters banner: Boost and Lower move a character's share of its rarity
	local isChar = kind == "Char"
	local favor = isChar and (prof.favor or {}) or nil
	if isChar then
		local F = Config.Spins.Favor
		local ups, downs = Spins.favorCounts(favor)
		O.sub.Text = string.format("Boost a character (x%.1f) or Lower one (x%.1f) to change your odds of it within its rarity: %d/%d boosted, %d/%d lowered. Duplicates turn into V Points.", F.Boost, F.Lower, ups, F.MaxBoost, downs, F.MaxLower)
	end
	local data = Spins.table(kind, lucky and Spins.LuckyWeights or Extra.recruitWeights(kind), favor)
	for i, row in ipairs(O.rows) do
		local d = data[i]
		row.frame.Visible = d ~= nil
		local canFavor = isChar and d ~= nil and not Spins.starters("Char")[d.item.Key]
		row.key = canFavor and d.item.Key or nil
		row.boost.Visible, row.lower.Visible = canFavor, canFavor
		if canFavor then
			local f = favor[d.item.Key]
			row.boostL.Text = f == "up" and "Boosted" or "Boost"
			row.boostL.TextColor3 = f == "up" and Gui.SIGNAL or Gui.CHALK
			row.lowerL.Text = f == "down" and "Lowered" or "Lower"
			row.lowerL.TextColor3 = f == "down" and Gui.SIGNAL_HOT or Gui.CHALK
		end
		if d then
			local color = Spins.rarityColor(d.item.Rarity)
			row.bar.BackgroundColor3 = color
			row.name.Text = d.item.Name
			row.name.TextColor3 = color
			if kind == "Char" and d.item.Char then
				local c = d.item.Char
				local def = c.Ability and Config.Abilities[c.Ability]
				row.desc.Text = string.format("%s %s%s", c.Tier, roleName(c.Role), def and (", " .. def.Name) or "")
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

	-- the S cinematic: a yellow screen (red for a Mythic), a light beam, your avatar's silhouette
	-- spiking
	local cin = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 32 }, root)
	local cinGrad = Gui.gradient(cin, Color3.fromRGB(255, 232, 110), Color3.fromRGB(255, 176, 30), 70)
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
		cin = { root = cin, grad = cinGrad, beam = beam, cam = cam, world = world, ball = ball, setGlow = setCinGlow },
		flash = flash,
		card = { root = card, stroke = card:FindFirstChildOfClass("UIStroke"), scale = cardScale, artGrad = artGrad, cam = ccam, world = cworld, rarity = rarity, name = name, tier = tier, line = line, ability = ability, blurb = blurb, bars = bars, foot = foot },
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

-- The recruit's glow: red when a Mythic is inside, gold for a Legendary, else pale.
local MYTHIC = Config.Rarity.PullGlow.Mythic
local SPARK = { mythic = MYTHIC, gold = Color3.fromRGB(255, 214, 90) }

local function sparkleBurst(tone)
	local S = ui.seq
	S.sparks:ClearAllChildren()
	local color = SPARK[tone] or Color3.fromRGB(220, 236, 255)
	local gold = tone ~= nil
	S.setGlow(0, color)
	local rng = Random.new()
	for i = 1, tone == "mythic" and 46 or 34 do
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
	-- the glow swells (red for a Mythic, gold for a Legendary)
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

-- A pull's item, rarity, rank and the colour it glows in the recruit (Mythic: red; an S-
-- character: its tier's green, so it reads apart from the S tier's gold).
local function pullInfo(kind, it)
	local item = Spins.item(kind, it.key)
	local rarity = item and item.Rarity or "Common"
	local glow = Config.Rarity.PullGlow[rarity] or Spins.rarityColor(rarity)
	local tier = kind == "Char" and item and item.Char and item.Char.Tier
	if tier and tier ~= Characters.group(tier) and Config.TierColors[tier] then
		glow = Config.TierColors[tier]
	end
	return item, rarity, Spins.rarityRank(rarity), glow
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
	if it.pity then
		card.foot.Text = (it.pity == "pick" and "PICK " or "PITY ") .. card.foot.Text -- a pity pull
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
local function cinematic(seq, mythic)
	local S = ui.seq
	local C = S.cin
	local AC = mods.AnimationController
	C.root.Visible = true
	C.root.BackgroundTransparency = 1
	tween(C.root, 0.12, { BackgroundTransparency = 0 })
	-- a Mythic burns red instead of the yellow screen
	if mythic then
		C.grad.Color = ColorSequence.new(Color3.fromRGB(255, 96, 84), Color3.fromRGB(150, 0, 16))
		C.beam.BackgroundColor3 = Color3.fromRGB(255, 214, 206)
		S.flash.BackgroundColor3 = MYTHIC
		C.setGlow(0, Color3.fromRGB(255, 190, 180))
	else
		C.grad.Color = ColorSequence.new(Color3.fromRGB(255, 232, 110), Color3.fromRGB(255, 176, 30))
		C.beam.BackgroundColor3 = Color3.new(1, 1, 1)
		S.flash.BackgroundColor3 = Color3.new(1, 1, 1)
		C.setGlow(0, Color3.new(1, 1, 1))
	end
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
		mods.AudioController.play("RecruitCharge", { volume = 0.8 })
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
				mods.AudioController.play("RecruitSpike", { volume = 1.2 })
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
	-- a Mythic card glows red at the edge
	if K.stroke then
		local mythic = rarity == "Mythic"
		K.stroke.Color = mythic and MYTHIC or Gui.WHITE
		K.stroke.Thickness = mythic and 3 or 1
		K.stroke.Transparency = mythic and 0 or 0.82
	end
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
	if it.pity then
		K.foot.Text = (it.pity == "pick" and "Your lucky pity pick!  " or "Pity!  ") .. K.foot.Text
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
		mods.AudioController.play(Spins.rarityRank(rarity) >= 4 and "RecruitRevealGold" or "RecruitReveal", { volume = 0.9 })
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
		-- a Mythic glows hardest (and pulses red), a Legendary next
		strength[i] = rank >= 5 and 1.3 or (rank >= 4 and 1 or (rank == 3 and 0.65 or (rank == 2 and 0.4 or 0.2)))
		best = math.max(best, rank)
	end
	local gold = best >= 4
	local tone = best >= 5 and "mythic" or (gold and "gold" or nil)
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

	-- 1. sparkles on black (red when a Mythic is inside, gold for a Legendary)
	sparkleBurst(tone)
	if mods.AudioController then
		mods.AudioController.play(gold and "RecruitOpenGold" or "RecruitOpen", { volume = gold and 0.5 or 0.7 })
		if tone == "mythic" then
			mods.AudioController.play("RecruitOpenMythic", { volume = 0.8 })
		end
	end
	if not hold(seq, 1.15) then
		return
	end
	-- 2. the balls fly under the gym ceiling
	mods.SceneController.show("gym")
	mods.SceneController.shot("ceiling")
	mods.SceneController.flyBalls(colors, strength, 1.5)
	local flySound = mods.AudioController and mods.AudioController.play("RecruitFly")
	tween(S.black, 0.35, { BackgroundTransparency = 1 })
	S.sparks:ClearAllChildren()
	local flew = hold(seq, 1.75)
	-- a skip, or the recruit closing, cuts the flight's sound short
	if flySound and (not flew or seq.skipping) then
		flySound:Destroy()
	end
	if not flew then
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
			if not cinematic(seq, rank >= 5) then
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
				mods.AudioController.play("RecruitPop", { minGap = 0 })
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
			table.insert(parts, string.format('<font color="#%s">%d %s</font>', (Config.Rarity.PullGlow[name] or Spins.rarityColor(name)):ToHex(), counts[name], name))
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
-- Players: the roster as cards (filter by role, favourites only, sort by tier or name), and a
-- page per player with its Growth (Gold on the four stats) and Information (its ability, its
-- role and its build's numbers). Laid out like The Spike's player screens.
------------------------------------------------------------------------------------------

local rosterRole = "All" -- All, WS, MB, SE
local rosterFav = false -- favourites only
local rosterSort = "Tier" -- Tier or Name
local teamMode = "3v3" -- the Players screen's team tab: 3v3, 2v2 or 1v1
local teamRole = nil -- the slot shown on the team card (nil: the one you play)
local picking = nil -- { mode, role, you } while a card click fills a team slot
local playerTab = "Growth" -- the player page's tab: Growth or Info
local statStep = Config.Upgrades.Steps[1] -- the player page's + and - move a stat by this much

local function favs(prof)
	return prof.fav or {}
end

-- Points bought above each stat's starting value, and whether all four sit at their ceilings.
local function upgradeState(c, levels)
	local bought, maxed = 0, true
	for _, stat in ipairs(Config.Stats.Order) do
		local base = Characters.baseStat(c, stat)
		local cur = levels and levels[stat] or base
		bought = bought + math.max(0, cur - base)
		if cur < c[stat] then
			maxed = false
		end
	end
	return bought, maxed
end

local function rosterList(prof)
	local fav = favs(prof)
	local list = {}
	for _, c in ipairs(Roster) do
		if (rosterRole == "All" or c.Role == rosterRole) and (not rosterFav or fav[c.Id]) then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		local oa, ob = owns(prof, "Char", a.Id), owns(prof, "Char", b.Id)
		if oa ~= ob then
			return oa
		end
		if rosterSort == "Name" then
			return a.Name < b.Name
		end
		local ta, tb = Characters.tierIndex(a.Tier) or 0, Characters.tierIndex(b.Tier) or 0
		if ta ~= tb then
			return ta > tb
		end
		return a.Name < b.Name
	end)
	return list
end

-- Card art: your own avatar in its role's pose (the bow-draw for wing spikers, a block for
-- middles, a set for setters), lit from the side like a trading card, posed once per role and
-- cloned into each card's ViewportFrame. You play every character as yourself, so the cards show
-- you. They exist before your avatar has loaded, so the art comes in on a later refresh.
local function angles(x, y, z)
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local PORTRAIT = {
	-- the loading screen's bow-draw: the chest open to a side camera, the left arm pointing up
	WS = { pose = "Cock", joints = { Waist = angles(15, -30, 0), LeftShoulder = angles(150, 0, -10), LeftElbow = angles(4, 0, 0), RightShoulder = angles(120, 0, 70), RightElbow = angles(110, 0, 0) }, look = Vector3.new(1, 0.08, 0) },
	MB = { pose = "Block", look = Vector3.new(0.45, 0.1, -1) },
	SE = { pose = "SetCatch", look = Vector3.new(0.9, 0.1, -0.55) },
	Solo = { pose = "ShowReady", look = Vector3.new(0.5, 0.1, -1) },
}
local portraits = nil -- role -> { model, focus }

local function buildPortraits()
	local AC, SC = mods.AnimationController, mods.SceneController
	local char = player.Character
	if not (AC and SC and char and char:FindFirstChild("HumanoidRootPart") and player:HasAppearanceLoaded()) then
		return nil
	end
	local out = {}
	for role, def in pairs(PORTRAIT) do
		local rig = SC.cloneAvatar(false)
		if not rig then
			return nil
		end
		local joints = {}
		for k, v in pairs(AC.poseJoints(def.pose) or {}) do
			joints[k] = v
		end
		for k, v in pairs(def.joints or {}) do
			joints[k] = v
		end
		local hum = rig.model:FindFirstChildOfClass("Humanoid")
		local standY = (hum and hum.HipHeight or 2) + rig.root.Size.Y / 2
		AC.poseModel(rig, joints, CFrame.new(0, standY, 0))
		out[role] = { model = rig.model, focus = Vector3.new(0, standY + 0.7, 0), look = def.look.Unit }
	end
	return out
end

-- Put a role's silhouette into a card's viewport (upper body, framed from the role's side).
local function fillPortrait(vp, role)
	local art = portraits and (portraits[role] or portraits.WS)
	if not art or vp:FindFirstChildWhichIsA("Model") then
		return
	end
	local model = art.model:Clone()
	model.Parent = vp
	local cam = vp.CurrentCamera or make("Camera", { FieldOfView = 38 }, vp)
	vp.CurrentCamera = cam
	cam.CFrame = CFrame.lookAt(art.focus + art.look * 11, art.focus)
end

-- A character card: tier-coloured card stock with print grain and a glossy diagonal, the
-- silhouette, the tier badge and role top right, the name at the bottom, a star for favourites,
-- a lock over players you haven't recruited.
local function characterCard(parent, c)
	local color = tierColor(c.Tier)
	local b = make("TextButton", { Name = c.Id, BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.52), BorderSizePixel = 0, Text = "", AutoButtonColor = false, ClipsDescendants = true }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	Gui.halftone(b, { Size = UDim2.fromScale(1, 1), ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.78 })
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.74, 0.12), Size = UDim2.new(0, 56, 1.7, 0), Rotation = 32, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.9, BorderSizePixel = 0 }, b)
	local vp = make("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(150, 146, 160), LightColor = Color3.fromRGB(255, 244, 228), LightDirection = Vector3.new(-0.7, -0.8, 0.4) }, b)
	local shade = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.45), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, b)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) }) }, shade)
	local _, setBadge = Gui.tierBadge(b, 46, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8) })
	setBadge(c.Tier, color, false)
	Gui.label(b, { Text = c.Role, display = true, TextSize = 21, TextStrokeTransparency = 0.35, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 58), Size = UDim2.fromOffset(70, 24), TextXAlignment = Enum.TextXAlignment.Right })
	local plus = Gui.label(b, { Text = "", display = true, TextSize = 17, TextStrokeTransparency = 0.35, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 82), Size = UDim2.fromOffset(70, 20), TextXAlignment = Enum.TextXAlignment.Right })
	local tag = Gui.label(b, { Text = "", display = true, TextSize = 17, TextStrokeTransparency = 0.35, Position = UDim2.new(0, 10, 1, -62), Size = UDim2.new(1, -20, 0, 20) })
	Gui.label(b, { Text = c.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextStrokeTransparency = 0.35, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 10, 1, -42), Size = UDim2.new(1, -20, 0, 34) })
	local star = Gui.iconImage(b, "IconStar", 22, Gui.SIGNAL, { Position = UDim2.fromOffset(8, 8), Visible = false })
	local lock = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.42, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, b)
	Gui.iconImage(lock, "IconLock", 34, Gui.CHALK, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), ImageTransparency = 0.2, ZIndex = 3 })
	local edge = make("UIStroke", { Thickness = 2, Color = color, Transparency = 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	b.MouseEnter:Connect(function()
		edge.Transparency = 0
		if Gui.onHover then
			Gui.onHover()
		end
	end)
	b.MouseLeave:Connect(function()
		edge.Transparency = b:GetAttribute("Playing") and 0 or 0.55
	end)
	return { button = b, vp = vp, edge = edge, tag = tag, plus = plus, star = star, lock = lock, color = color, role = c.Role }
end

local function openPlayer(id)
	selectedChar = id
	playerTab = "Growth"
	MenuController.go("player")
end

local function buildPlayers()
	local p = page("players")
	mainChrome(p, "players")

	-- the roster panel on the right: sort, favourites, roles, then the cards
	local panel = make("Frame", {
		Name = "Roster",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -M, 0, 110),
		Size = UDim2.new(0.5, 0, 1, -110 - M),
		BackgroundColor3 = Gui.CARD,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
	}, p)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
	make("UIStroke", { Color = Gui.HAIRLINE, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	local sortB, sortL = hairButton(panel, { Name = "Sort", Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(176, 46) }, "", 21)
	onClick(sortB, function()
		rosterSort = rosterSort == "Tier" and "Name" or "Tier"
		MenuController.refresh()
	end)
	local favB = Gui.cardButton(panel, { Name = "Favorites", Position = UDim2.fromOffset(202, 14), Size = UDim2.fromOffset(46, 46) })
	local favIcon = Gui.iconImage(favB, "IconStar", 26, Gui.DIM, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	onClick(favB, function()
		rosterFav = not rosterFav
		MenuController.refresh()
	end)
	local roleItems = { { key = "All", text = "All", width = 76 } }
	for _, r in ipairs({ "WS", "MB", "SE" }) do
		table.insert(roleItems, { key = r, text = Config.Roles[r].Short, width = 76 })
	end
	local _, setRole = Gui.chips(panel, roleItems, { Name = "Roles", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(4 * 76 + 24, 46) }, function(key)
		click("UISelect")
		rosterRole = key
		MenuController.refresh()
	end)
	local count = Gui.label(panel, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(18, 68), Size = UDim2.new(1, -36, 0, 20) })
	local grid = make("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(12, 96),
		Size = UDim2.new(1, -24, 1, -108),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Gui.HAIRLINE,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 4) }, grid)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(172, 212), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local cards = {}
	for _, c in ipairs(Roster) do
		local card = characterCard(grid, c)
		onClick(card.button, function()
			local pk = picking
			if not pk then
				openPlayer(c.Id)
				return
			end
			if not owns(profile(), "Char", c.Id) then
				toast("Recruit " .. c.Name .. " first")
				return
			end
			if pk.you then
				picking = nil
				sendProfile("select", c.Id)
			elseif c.Role ~= pk.role then
				toast(string.format("That slot needs a %s", string.lower(Config.Roles[pk.role].Name)))
			else
				picking = nil
				sendProfile("teamPick", pk.mode, pk.role, c.Id)
			end
		end)
		cards[c.Id] = card
	end
	local empty = Gui.label(panel, { Text = "No favourites here yet. Open a player and press Favorite.", TextSize = 18, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(40, 140), Size = UDim2.new(1, -80, 0, 60), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })

	-- while a team slot is being filled: what's being picked, and a way out
	local pickLine = Gui.label(panel, { Text = "", display = true, TextSize = 18, TextColor3 = Gui.SIGNAL, Position = UDim2.fromOffset(18, 64), Size = UDim2.new(1, -150, 0, 26), Visible = false })
	local pickCancel = hairButton(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 62), Size = UDim2.fromOffset(110, 30), Visible = false }, "Cancel", 16)
	onClick(pickCancel, function()
		picking = nil
		MenuController.refresh()
	end)

	-- left: your teams, one per mode. The roles down the side (the one you play marked YOU), and
	-- the chosen slot's card: the character, height, tier, the four stats and the ability. Your
	-- AI teammates play the characters you pick here (a random roster player when you don't).
	local teams = Gui.card(p, { Name = "Teams", Position = UDim2.fromOffset(M, 110), Size = UDim2.new(0, 560, 1, -110 - M - 132 - 16) })
	Gui.label(teams, { Text = "Your teams", display = true, weight = Enum.FontWeight.Heavy, TextSize = 26, Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(220, 34) })
	local _, setMode = Gui.tabs(teams, { { key = "3v3", text = "3v3" }, { key = "2v2", text = "2v2" }, { key = "1v1", text = "1v1" } }, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(300, 44) }, function(key)
		click("UISelect")
		teamMode = key
		teamRole = nil
		picking = nil
		MenuController.refresh()
	end)
	local roleButtons = {}
	for i = 1, 3 do
		local b = make("TextButton", { Position = UDim2.fromOffset(12, 60 + (i - 1) * 104), Size = UDim2.fromOffset(92, 96), BackgroundColor3 = Gui.NAVY, BackgroundTransparency = 0.5, BorderSizePixel = 0, Text = "", AutoButtonColor = false }, teams)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		local bar = make("Frame", { Size = UDim2.new(0, 4, 1, -16), Position = UDim2.fromOffset(0, 8), BackgroundColor3 = Gui.SIGNAL, BorderSizePixel = 0, Visible = false }, b)
		local roleL = Gui.label(b, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 18), TextXAlignment = Enum.TextXAlignment.Center })
		local who = Gui.label(b, { Text = "", display = true, TextSize = 14, Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 60), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
		local rb = { button = b, bar = bar, role = roleL, who = who }
		Gui.pressSound(b, "UISelect", function()
			return rb.key ~= nil
		end)
		b.MouseButton1Click:Connect(function()
			if rb.key then
				click("UISelect")
				teamRole = rb.key
				MenuController.refresh()
			end
		end)
		roleButtons[i] = rb
	end
	local card = make("Frame", { Position = UDim2.fromOffset(116, 60), Size = UDim2.new(1, -130, 1, -72), BackgroundTransparency = 1 }, teams)
	local cName = Gui.label(card, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 40, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -96, 0, 46), TextTruncate = Enum.TextTruncate.AtEnd })
	local cRole = Gui.label(card, { Text = "", display = true, TextSize = 18, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(60, 20) })
	local cLine = Gui.label(card, { Text = "", TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, RichText = true, Position = UDim2.fromOffset(2, 48), Size = UDim2.new(1, -96, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd })
	local cBadge, setCBadge = Gui.tierBadge(card, 76, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0) })
	local statRows = {}
	for i, stat in ipairs(Config.Stats.Order) do
		local row = make("Frame", { Position = UDim2.fromOffset(0, 92 + (i - 1) * 56), Size = UDim2.new(1, -6, 0, 50), BackgroundTransparency = 1 }, card)
		Gui.iconImage(row, "Icon" .. stat, 28, Gui.CHALK, { Position = UDim2.fromOffset(0, 2) })
		Gui.label(row, { Text = stat, display = true, TextSize = 21, Position = UDim2.fromOffset(38, 0), Size = UDim2.fromOffset(140, 30) })
		local value = Gui.label(row, { Text = "", display = true, TextSize = 21, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(140, 30), TextXAlignment = Enum.TextXAlignment.Right })
		local track = make("Frame", { Position = UDim2.fromOffset(38, 34), Size = UDim2.new(1, -38, 0, 8), BackgroundColor3 = Color3.fromRGB(44, 48, 64), BorderSizePixel = 0 }, row)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, track)
		local cap = make("Frame", { Size = UDim2.fromScale(0.8, 1), BackgroundColor3 = Color3.fromRGB(78, 84, 106), BorderSizePixel = 0 }, track)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, cap)
		local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, track)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)
		make("UIGradient", { Color = ColorSequence.new(Gui.SIGNAL, Color3.fromRGB(255, 150, 30)) }, fill)
		statRows[stat] = { row = row, value = value, cap = cap, fill = fill }
	end
	local cAbility = Gui.label(card, { Text = "", display = true, TextSize = 20, RichText = true, Position = UDim2.fromOffset(0, 92 + 4 * 56 + 4), Size = UDim2.new(1, -6, 0, 24), TextTruncate = Enum.TextTruncate.AtEnd })
	local cNote = Gui.label(card, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(0, 92 + 4 * 56 + 30), Size = UDim2.new(1, -6, 0, 40) })
	local pickB, pickL = actionPlate(card, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.fromOffset(170, 46) }, "Pick", 21)
	local clearB = hairButton(card, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 184, 1, -4), Size = UDim2.fromOffset(110, 46) }, "Clear", 19)
	onClick(pickB, function()
		local slot = ui.players.slot
		if not slot then
			return
		end
		picking = { mode = teamMode, role = slot.role, you = slot.you }
		rosterRole = slot.you and "All" or slot.role
		rosterFav = false
		MenuController.refresh()
	end)
	onClick(clearB, function()
		local slot = ui.players.slot
		if slot and not slot.you then
			picking = nil
			sendProfile("teamPick", teamMode, slot.role, "")
		end
	end)

	-- bottom left, under your avatar: who you play now, and a way into their page
	local now = Gui.card(p, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, M, 1, -M), Size = UDim2.fromOffset(470, 132) })
	Gui.label(now, { Text = "Playing now", TextSize = 15, weight = Enum.FontWeight.Medium, TextColor3 = Gui.HAIRLINE, Position = UDim2.fromOffset(122, 12), Size = UDim2.fromOffset(200, 18) })
	local _, setNowBadge = Gui.tierBadge(now, 88, { Position = UDim2.fromOffset(18, 22) })
	local nowName = Gui.label(now, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 40, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(120, 30), Size = UDim2.fromOffset(200, 46) })
	local nowLine = Gui.label(now, { Text = "", TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(122, 80), Size = UDim2.fromOffset(200, 20) })
	local open = actionPlate(now, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(128, 48) }, "Details", 22)
	onClick(open, function()
		openPlayer(profile().char or player:GetAttribute("CharId"))
	end)

	ui.players = {
		pickLine = pickLine,
		pickCancel = pickCancel,
		setMode = setMode,
		roleButtons = roleButtons,
		cName = cName,
		cRole = cRole,
		cLine = cLine,
		cBadge = cBadge,
		setCBadge = setCBadge,
		statRows = statRows,
		cAbility = cAbility,
		cNote = cNote,
		pickB = pickB,
		pickL = pickL,
		clearB = clearB,
		cards = cards,
		count = count,
		sortL = sortL,
		favIcon = favIcon,
		setRole = setRole,
		empty = empty,
		setNowBadge = setNowBadge,
		nowName = nowName,
		nowLine = nowLine,
	}
end

-- The role you play in a team of `mode`: your character's, if the team has it (else the first
-- slot, the way players claim roles in a match).
local function youRole(prof, mode)
	local roles = Court.roles(Court.teamSize(mode) or 3)
	local c = Roster.get(prof.char or "") or Roster.get(Roster.Starters[1])
	if #roles == 1 then
		return roles[1]
	end
	return table.find(roles, c.Role) and c.Role or roles[1]
end

local function refreshTeams(prof)
	local pl = ui.players
	local roles = Court.roles(Court.teamSize(teamMode) or 3)
	local mine = youRole(prof, teamMode)
	if not teamRole or not table.find(roles, teamRole) then
		teamRole = mine
	end
	pl.setMode(teamMode)
	local picks = (prof.teams and prof.teams[teamMode]) or {}
	local you = Roster.get(prof.char or "") or Roster.get(Roster.Starters[1])
	for i, rb in ipairs(pl.roleButtons) do
		local role = roles[i]
		rb.key = role
		rb.button.Visible = role ~= nil
		if role then
			local on = role == teamRole
			rb.role.Text = role == "Solo" and "1v1" or Config.Roles[role].Short
			rb.role.TextColor3 = on and Gui.SIGNAL or Gui.CHALK
			rb.bar.Visible = on
			rb.button.BackgroundTransparency = on and 0.15 or 0.5
			local pick = Roster.get(picks[role] or "")
			if role == mine then
				rb.who.Text = "YOU"
				rb.who.TextColor3 = Gui.SIGNAL
			else
				rb.who.Text = pick and pick.Name or "Random"
				rb.who.TextColor3 = pick and Gui.CHALK or Gui.DIM
			end
		end
	end
	-- the card
	local isYou = teamRole == mine
	local c = isYou and you or Roster.get(picks[teamRole] or "")
	pl.slot = { role = teamRole, you = isYou }
	for _, row in pairs(pl.statRows) do
		row.row.Visible = c ~= nil
	end
	pl.cBadge.Visible = c ~= nil
	pl.clearB.Visible = not isYou and c ~= nil
	pl.pickL.Text = isYou and "Change" or (c and "Swap" or "Pick")
	if not c then
		pl.cName.Text = "Random AI"
		pl.cRole.Visible = false
		pl.cLine.Text = "A roster " .. string.lower(Config.Roles[teamRole].Name) .. " at the lobby's bot level"
		pl.cAbility.Text = ""
		pl.cNote.Text = "Pick one of your players and they take this spot whenever bots fill your " .. teamMode .. " team."
		return
	end
	pl.cName.Text = c.Name
	pl.cRole.Visible = true
	pl.cRole.Text = c.Role
	pl.cRole.Position = UDim2.fromOffset(math.min(pl.cName.TextBounds.X + 8, 330), 4)
	local lv = prof.levels and prof.levels[c.Id]
	local _, maxed = upgradeState(c, lv)
	pl.setCBadge(c.Tier, tierColor(c.Tier), maxed)
	pl.cLine.Text = string.format("%d cm   %s", c.Height, isYou and '<font color="#FFD21F">You</font>' or "AI teammate")
	local span = Config.Stats.Ref - Config.Stats.Min
	for stat, row in pairs(pl.statRows) do
		local cur = lv and lv[stat] or Characters.baseStat(c, stat)
		local ceil = c[stat]
		row.value.Text = cur >= ceil and string.format("MAX / %d", ceil) or string.format("%d / %d", cur, ceil)
		row.value.TextColor3 = cur >= ceil and Gui.SIGNAL or Gui.CHALK
		row.cap.Size = UDim2.fromScale(math.clamp((ceil - Config.Stats.Min) / span, 0, 1), 1)
		row.fill.Size = UDim2.fromScale(math.clamp((cur - Config.Stats.Min) / span, 0, 1), 1)
	end
	local def = c.Ability and Config.Abilities[c.Ability]
	if def then
		pl.cAbility.Text = string.format('<font color="#%s">%s</font>', def.Color:ToHex(), def.Name)
		if isYou then
			pl.cNote.Text = def.Active and "Active: press Q" or def.Kind or "Passive"
		else
			pl.cNote.Text = def.Active and "Active: you pop it with 1 or 2 in a match (your AI never does)" or def.AiNote or "Passive: it works on its own"
		end
	else
		pl.cAbility.Text = ""
		pl.cNote.Text = ""
	end
end

local function refreshPlayers(prof)
	local pl = ui.players
	refreshTeams(prof)
	pl.pickLine.Visible = picking ~= nil
	pl.pickCancel.Visible = picking ~= nil
	pl.count.Visible = picking == nil
	if picking then
		local what = picking.you and "the player you play" or string.format("your %s %s", picking.mode, string.lower(Config.Roles[picking.role].Name))
		pl.pickLine.Text = "Pick " .. what .. ": click a card"
	end
	if not portraits then
		portraits = buildPortraits()
	end
	local current = prof.char or player:GetAttribute("CharId")
	local fav = favs(prof)
	local list = rosterList(prof)
	local shownIds = {}
	for i, c in ipairs(list) do
		shownIds[c.Id] = i
	end
	local have, total = ownedCount(prof, "Char")
	pl.count.Text = string.format("%d of %d recruited. Showing %d.", have, total, #list)
	pl.sortL.Text = "Sort: " .. rosterSort
	pl.favIcon.ImageColor3 = rosterFav and Gui.SIGNAL or Gui.DIM
	pl.setRole(rosterRole)
	pl.empty.Visible = #list == 0
	for id, card in pairs(pl.cards) do
		local c = Roster.get(id)
		local order = shownIds[id]
		card.button.Visible = order ~= nil
		card.button.LayoutOrder = order or 999
		if portraits then
			fillPortrait(card.vp, card.role)
		end
		local mine = owns(prof, "Char", id)
		local bought, maxed = upgradeState(c, mine and prof.levels and prof.levels[id] or nil)
		card.lock.Visible = not mine
		card.plus.Text = (mine and maxed) and "MAX" or (bought > 0 and ("+" .. bought) or "")
		local playing = id == current
		card.button:SetAttribute("Playing", playing)
		if playing then
			card.tag.Text = "Playing"
			card.tag.TextColor3 = Gui.SIGNAL
		elseif table.find(Roster.Starters, id) then
			card.tag.Text = "Starter"
			card.tag.TextColor3 = Gui.CHALK
		else
			card.tag.Text = ""
		end
		card.edge.Color = playing and Gui.SIGNAL or card.color
		card.edge.Thickness = playing and 3 or 2
		card.edge.Transparency = playing and 0 or 0.55
		card.star.Visible = fav[id] == true
	end
	local c = Roster.get(current) or Roster.get(Roster.Starters[1])
	local def = c.Ability and Config.Abilities[c.Ability]
	local _, maxed = upgradeState(c, prof.levels and prof.levels[c.Id] or nil)
	pl.setNowBadge(c.Tier, tierColor(c.Tier), maxed)
	pl.nowName.Text = c.Name
	pl.nowLine.Text = string.format("%s / %d cm%s", c.Role, c.Height, def and string.format(' / <font color="#%s">%s</font>', def.Color:ToHex(), def.Name) or "")
end

-- A player's page: back to the roster top left, your avatar in the room, and the panel on the
-- right with the badge, name, Play and Favorite, and the Growth and Information tabs.
local function buildPlayer()
	local p = page("player")
	local top = make("Frame", { Size = UDim2.fromOffset(560, 56), Position = UDim2.fromOffset(M, 24), BackgroundTransparency = 1 }, p)
	local back = make("TextButton", { Size = UDim2.fromOffset(56, 56), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, top)
	local arrow = Gui.iconImage(back, "IconBack", 38, Gui.CHALK, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	back.MouseEnter:Connect(function()
		arrow.ImageColor3 = Gui.SIGNAL
	end)
	back.MouseLeave:Connect(function()
		arrow.ImageColor3 = Gui.CHALK
	end)
	onClick(back, function()
		MenuController.go("players")
	end)
	currencyStrip(top, { Position = UDim2.fromOffset(72, 8) })
	ui.strips = ui.strips or {}
	table.insert(ui.strips, top)

	local panel = make("Frame", {
		Name = "Detail",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -M, 0, 24),
		Size = UDim2.new(0.5, 0, 1, -24 - M),
		BackgroundColor3 = Gui.CARD,
		BackgroundTransparency = 0.16,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, p)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
	make("UIStroke", { Color = Gui.HAIRLINE, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	Gui.halftone(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.6, 0, 0, 170), ImageColor3 = Gui.CHALK, ImageTransparency = 0.95 })

	-- header: the badge, the name and its line, Play and Favorite
	local _, setBadge = Gui.tierBadge(panel, 96, { Position = UDim2.fromOffset(22, 18) })
	local name = Gui.label(panel, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 54, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(134, 16), Size = UDim2.new(1, -134 - 206, 0, 60) })
	local line = Gui.label(panel, { Text = "", TextSize = 19, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(136, 78), Size = UDim2.new(1, -136 - 206, 0, 24) })
	local function squareAction(x, iconKey, caption)
		local b = Gui.cardButton(panel, { Name = caption, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, x, 0, 18), Size = UDim2.fromOffset(88, 88) })
		local icon = Gui.iconImage(b, iconKey, 34, Gui.CHALK, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12) })
		local l = Gui.label(b, { Text = caption, display = true, TextSize = 18, Position = UDim2.new(0, 0, 1, -32), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
		return b, icon, l
	end
	local play, playIcon, playL = squareAction(-112, "IconPlayers", "Play")
	local fav, favIcon, favL = squareAction(-16, "IconStar", "Favorite")
	onClick(play, function()
		local prof = profile()
		if not selectedChar then
			return
		end
		if owns(prof, "Char", selectedChar) then
			Net.get("Profile"):FireServer("select", selectedChar)
		else
			goRecruit()
		end
	end)
	onClick(fav, function()
		if selectedChar then
			Net.get("Profile"):FireServer("favorite", selectedChar, not favs(profile())[selectedChar])
		end
	end)

	local _, setTab = Gui.tabs(panel, { { key = "Growth", text = "Growth" }, { key = "Info", text = "Information" } }, { Name = "Tabs", Position = UDim2.fromOffset(16, 120), Size = UDim2.new(1, -32, 0, 52) }, function(key)
		click("UISelect")
		playerTab = key
		MenuController.refresh()
	end)

	-- Growth: the four stats with their bars, + and - by the chosen step, and the build's numbers
	local growth = make("Frame", { Position = UDim2.fromOffset(0, 184), Size = UDim2.new(1, 0, 1, -184), BackgroundTransparency = 1 }, panel)
	Gui.label(growth, { Text = "Gold raises each stat up to this player's ceiling.", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(22, 10), Size = UDim2.new(1, -250, 0, 20) })
	local stepItems = {}
	for _, n in ipairs(Config.Upgrades.Steps) do
		table.insert(stepItems, { key = n, text = "x" .. n, width = 58 })
	end
	local _, setStep = Gui.chips(growth, stepItems, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 2), Size = UDim2.fromOffset(#stepItems * 66, 36) }, function(key)
		click("UISelect")
		statStep = key
		MenuController.refresh()
	end)
	local rows = {}
	for i, stat in ipairs(Config.Stats.Order) do
		local row = make("Frame", { Position = UDim2.fromOffset(16, 50 + (i - 1) * 76), Size = UDim2.new(1, -32, 0, 68), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.96, BorderSizePixel = 0 }, growth)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
		Gui.iconImage(row, "Icon" .. stat, 34, Gui.CHALK, { Position = UDim2.fromOffset(12, 17) })
		Gui.label(row, { Text = stat, display = true, TextSize = 24, Position = UDim2.fromOffset(58, 0), Size = UDim2.fromOffset(110, 68) })
		local cost = Gui.label(row, { Text = "", TextSize = 13, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(170, 10), Size = UDim2.new(1, -170 - 250, 0, 16) })
		local track = make("Frame", { Position = UDim2.fromOffset(170, 34), Size = UDim2.new(1, -170 - 250, 0, 10), BackgroundColor3 = Color3.fromRGB(44, 48, 64), BorderSizePixel = 0 }, row)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, track)
		local cap = make("Frame", { Size = UDim2.fromScale(0.8, 1), BackgroundColor3 = Color3.fromRGB(78, 84, 106), BorderSizePixel = 0 }, track)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, cap)
		local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, track)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)
		make("UIGradient", { Color = ColorSequence.new(Gui.SIGNAL, Color3.fromRGB(255, 150, 30)) }, fill)
		local value = Gui.label(row, { Text = "", display = true, TextSize = 22, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -124, 0.5, 0), Size = UDim2.fromOffset(116, 30), TextXAlignment = Enum.TextXAlignment.Right })
		local plusB, plusL = Gui.squareButton(row, "+", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, 0), Size = UDim2.fromOffset(52, 52) })
		local minusB, minusL = Gui.squareButton(row, "-", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(52, 52) })
		Gui.pressSound(plusB, "UITick", function()
			return selectedChar ~= nil and plusB.Active
		end)
		Gui.pressSound(minusB, "UITick", function()
			return selectedChar ~= nil and minusB.Active
		end)
		plusB.MouseButton1Click:Connect(function()
			if selectedChar and plusB.Active then
				click("UITick")
				sendProfile("upgrade", selectedChar, stat, statStep)
			end
		end)
		minusB.MouseButton1Click:Connect(function()
			if selectedChar and minusB.Active then
				click("UITick")
				sendProfile("upgrade", selectedChar, stat, -statStep)
			end
		end)
		rows[stat] = { cost = cost, cap = cap, fill = fill, value = value, plusB = plusB, plusL = plusL, minusB = minusB, minusL = minusL }
	end
	-- the build's numbers, like a stat line under the bars
	local numbers = make("Frame", { Position = UDim2.fromOffset(16, 50 + 4 * 76 + 6), Size = UDim2.new(1, -32, 0, 84), BackgroundTransparency = 1 }, growth)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, numbers)
	local cells = {}
	for i, key in ipairs({ "Hitting point", "Spike speed", "Team stamina", "Run speed" }) do
		local cell = make("Frame", { Size = UDim2.new(0.25, -8, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.96, BorderSizePixel = 0, LayoutOrder = i }, numbers)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, cell)
		local v = Gui.label(cell, { Text = "", display = true, TextSize = 26, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -20, 0, 32) })
		Gui.label(cell, { Text = key, TextSize = 14, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -20, 0, 18) })
		local sub = Gui.label(cell, { Text = "", TextSize = 12, TextColor3 = Gui.DIM, TextTransparency = 0.3, Position = UDim2.fromOffset(14, 62), Size = UDim2.new(1, -20, 0, 16) })
		cells[key] = { value = v, sub = sub }
	end
	local notes = Gui.label(growth, { Text = "", TextSize = 15, TextColor3 = Gui.CHALK, RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(22, 50 + 4 * 76 + 100), Size = UDim2.new(1, -44, 0, 44) })

	-- Information: the ability (for S and S+ players), the role, and the recruit facts
	local info = make("Frame", { Position = UDim2.fromOffset(0, 184), Size = UDim2.new(1, 0, 1, -184), BackgroundTransparency = 1, Visible = false }, panel)
	local ab = make("Frame", { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 196), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.96, BorderSizePixel = 0 }, info)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, ab)
	Gui.label(ab, { Text = "Ability", TextSize = 15, weight = Enum.FontWeight.Medium, TextColor3 = Gui.HAIRLINE, Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(200, 18) })
	local gem = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(46, 72), Size = UDim2.fromOffset(40, 40), Rotation = 45, BorderSizePixel = 0 }, ab)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.4, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, gem)
	local abName = Gui.label(ab, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 34, Position = UDim2.fromOffset(84, 50), Size = UDim2.new(1, -250, 0, 42) })
	local abKind = Gui.plate(ab, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 54), Size = UDim2.fromOffset(170, 34) }, Gui.SIGNAL)
	local abKindL = Gui.label(abKind, { Text = "", display = true, TextSize = 18, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	local abText = Gui.label(ab, { Text = "", TextSize = 18, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(18, 104), Size = UDim2.new(1, -36, 0, 84) })
	local roleBox = make("Frame", { Position = UDim2.fromOffset(16, 220), Size = UDim2.new(1, -32, 0, 110), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.96, BorderSizePixel = 0 }, info)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, roleBox)
	Gui.label(roleBox, { Text = "Role", TextSize = 15, weight = Enum.FontWeight.Medium, TextColor3 = Gui.HAIRLINE, Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(200, 18) })
	local roleName2 = Gui.label(roleBox, { Text = "", display = true, TextSize = 28, Position = UDim2.fromOffset(18, 32), Size = UDim2.new(1, -36, 0, 34) })
	local roleText = Gui.label(roleBox, { Text = "", TextSize = 16, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(18, 68), Size = UDim2.new(1, -36, 0, 40) })
	local facts = make("Frame", { Position = UDim2.fromOffset(16, 342), Size = UDim2.new(1, -32, 0, 84), BackgroundTransparency = 1 }, info)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, facts)
	local factCells = {}
	for i, key in ipairs({ "Height", "Rank", "Per recruit", "Status" }) do
		local cell = make("Frame", { Size = UDim2.new(0.25, -8, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.96, BorderSizePixel = 0, LayoutOrder = i }, facts)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, cell)
		local v = Gui.label(cell, { Text = "", display = true, TextSize = 26, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -20, 0, 32) })
		Gui.label(cell, { Text = key, TextSize = 14, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -20, 0, 18) })
		factCells[key] = v
	end

	ui.player = {
		setBadge = setBadge,
		name = name,
		line = line,
		playIcon = playIcon,
		playL = playL,
		favIcon = favIcon,
		favL = favL,
		setTab = setTab,
		growth = growth,
		info = info,
		setStep = setStep,
		rows = rows,
		cells = cells,
		notes = notes,
		gem = gem,
		abName = abName,
		abKind = abKind,
		abKindL = abKindL,
		abText = abText,
		roleName = roleName2,
		roleText = roleText,
		facts = factCells,
	}
end

local function refreshPlayer(prof)
	local d = ui.player
	local current = prof.char or player:GetAttribute("CharId")
	local c = Roster.get(selectedChar) or Roster.get(current) or Roster.get(Roster.Starters[1])
	selectedChar = c.Id
	local mine = owns(prof, "Char", c.Id)
	local levels = mine and prof.levels and prof.levels[c.Id] or nil
	local _, maxed = upgradeState(c, levels)
	local color = tierColor(c.Tier)
	local def = c.Ability and Config.Abilities[c.Ability]
	d.setBadge(c.Tier, color, mine and maxed)
	d.name.Text = c.Name
	d.line.Text = string.format("%s / %d cm%s", c.Role, c.Height, def and string.format(' / <font color="#%s">%s</font>', def.Color:ToHex(), def.Name) or "")
	if not mine then
		d.playL.Text = "Recruit"
		d.playIcon.ImageColor3 = Gui.CHALK
	elseif c.Id == current then
		d.playL.Text = "Playing"
		d.playIcon.ImageColor3 = Gui.SIGNAL
	else
		d.playL.Text = "Play"
		d.playIcon.ImageColor3 = Gui.CHALK
	end
	local isFav = favs(prof)[c.Id] == true
	d.favIcon.ImageColor3 = isFav and Gui.SIGNAL or Gui.CHALK
	d.favL.TextColor3 = isFav and Gui.SIGNAL or Gui.CHALK
	d.setTab(playerTab)
	d.growth.Visible = playerTab == "Growth"
	d.info.Visible = playerTab == "Info"
	d.setStep(statStep)

	-- Growth
	local gold = prof.gold or 0
	local free = prof.dev == true
	local span = Config.Stats.Ref - Config.Stats.Min
	local built = {}
	for stat, row in pairs(d.rows) do
		local base = Characters.baseStat(c, stat)
		local cur = levels and levels[stat] or base
		local ceil = c[stat]
		built[stat] = cur
		row.value.Text = cur >= ceil and string.format("MAX / %d", ceil) or string.format("%d / %d", cur, ceil)
		row.value.TextColor3 = cur >= ceil and Gui.SIGNAL or Gui.CHALK
		row.cap.Size = UDim2.fromScale(math.clamp((ceil - Config.Stats.Min) / span, 0, 1), 1)
		row.fill.Size = UDim2.fromScale(math.clamp((cur - Config.Stats.Min) / span, 0, 1), 1)
		if not mine then
			row.cost.Text = "Recruit this player to upgrade them"
		elseif cur >= ceil then
			row.cost.Text = "At the ceiling"
		elseif free then
			row.cost.Text = "Free for developers"
		else
			row.cost.Text = string.format("Next point %s Gold. To max %s Gold", Gui.num(Characters.pointCost(c, cur)), Gui.num(Characters.upgradeCost(c, cur, ceil)))
		end
		Gui.enable(row.plusB, row.plusL, mine and cur < ceil and (free or gold >= Characters.pointCost(c, cur)))
		Gui.enable(row.minusB, row.minusL, mine and cur > base)
	end
	local s = Characters.derive(c.Tier, { Height = c.Height, Attack = built.Attack, Defense = built.Defense, Speed = built.Speed, Jump = built.Jump })
	local maxS = Characters.derive(Characters.fromRoster(c, "max"))
	local H = Config.Hits
	d.cells["Hitting point"].value.Text = string.format("%.2f m", s.ContactMaxM)
	d.cells["Hitting point"].sub.Text = string.format("maxed %.2f m", maxS.ContactMaxM)
	d.cells["Spike speed"].value.Text = string.format("%d-%d", math.floor(H.SpikeKmhMin * s.Power), math.floor(H.SpikeKmhMax * s.Power))
	d.cells["Spike speed"].sub.Text = "km/h"
	d.cells["Team stamina"].value.Text = tostring(math.floor(s.StaminaPool + 0.5))
	d.cells["Team stamina"].sub.Text = "guard pool"
	d.cells["Run speed"].value.Text = string.format("%.1f", s.WalkSpeed)
	d.cells["Run speed"].sub.Text = "studs a second"
	local notes = {}
	if c.Ability == "Thunder" then
		table.insert(notes, s.ContactMaxM >= H.ThunderHeight and '<font color="#FFE14D">Thunder unlocked: spikes above 4.00 m turn into lightning.</font>' or "Thunder needs a 4.00 m hitting point: upgrade Jump.")
	end
	if built.Jump >= Config.Player.BoomJumpMin then
		table.insert(notes, "Boom jumps unlocked.")
	elseif c.Jump >= Config.Player.BoomJumpMin then
		table.insert(notes, string.format("Boom jumps unlock at %d Jump.", Config.Player.BoomJumpMin))
	end
	d.notes.Text = table.concat(notes, "  ")

	-- Information
	if def then
		d.gem.BackgroundColor3 = def.Color
		d.gem.Visible = true
		d.abName.Text = def.Name
		d.abName.TextColor3 = def.Color
		d.abKind.Visible = true
		d.abKindL.Text = def.Active and string.format("Active: Q, %d s cooldown", def.Cooldown or 0) or def.Kind or "Passive"
		d.abText.Text = def.Blurb or ""
		d.abText.TextColor3 = Gui.CHALK
	else
		d.gem.Visible = false
		d.abName.Text = "No ability"
		d.abName.TextColor3 = Gui.DIM
		d.abKind.Visible = false
		d.abText.Text = "Abilities come with S and S+ players. Recruit one to see theirs here."
		d.abText.TextColor3 = Gui.DIM
	end
	local role = Config.Roles[c.Role]
	d.roleName.Text = role and role.Name or c.Role
	d.roleText.Text = role and role.Blurb or ""
	local odds = 0
	for _, row in ipairs(Spins.table("Char")) do
		if row.item.Key == c.Id then
			odds = row.chance
		end
	end
	d.facts.Height.Text = string.format("%d cm", c.Height)
	d.facts.Rank.Text = c.Tier
	d.facts.Rank.TextColor3 = color
	d.facts["Per recruit"].Text = table.find(Roster.Starters, c.Id) and "Starter" or string.format("%.2f%%", odds * 100)
	d.facts.Status.Text = mine and "Recruited" or "Not yet"
	d.facts.Status.TextColor3 = mine and Gui.CHALK or Gui.DIM
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

-- The Locker: the practice spike plays in the gym on the left with whatever you point at (on the
-- Intro pose tab your avatar holds the pose instead), and a panel on the right holds the kinds
-- (tabs) and their items as square equip cards: a dark
-- glossy tile with a thick rarity border, the name in the middle and Equip, Equipped or Locked
-- under it. The picked item's name and the Equip plate sit along the bottom.
local function lockerCard(parent, kind, item)
	local color = Spins.rarityColor(item.Rarity)
	local b = make("TextButton", { Name = item.Key, BackgroundColor3 = Color3.fromRGB(34, 36, 46), BorderSizePixel = 0, Text = "", AutoButtonColor = false, ClipsDescendants = true, Visible = false }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
	-- the tile's sheen: darker at the foot, a glossy diagonal across the top
	local foot = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, b)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.45) }) }, foot)
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.7, 0.08), Size = UDim2.new(0, 40, 1.8, 0), Rotation = 40, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.9, BorderSizePixel = 0 }, b)
	if item.Color then
		local sw = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = item.Color, BorderSizePixel = 0 }, b)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, sw)
		make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.3, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, sw)
	end
	Gui.label(b, {
		Text = item.Name,
		display = true,
		weight = Enum.FontWeight.Heavy,
		TextSize = 26,
		TextWrapped = true,
		TextStrokeTransparency = 0.35,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, item.Color and 12 or 0),
		Size = UDim2.new(1, -16, 0, 62),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local state = Gui.label(b, { Text = "", display = true, TextSize = 17, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -12, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	local edge = make("UIStroke", { Color = color, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local scale = make("UIScale", { Scale = 1 }, b)
	b.MouseEnter:Connect(function()
		scale.Scale = 1.04
		if Gui.onHover then
			Gui.onHover()
		end
	end)
	b.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	onClick(b, function()
		lockerPick[kind] = item.Key
		MenuController.refresh()
	end)
	return { button = b, edge = edge, state = state, item = item, color = color }
end

local function buildLocker()
	local p = page("locker")
	mainChrome(p, "locker")
	local panel = make("Frame", {
		Name = "Locker",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -M, 0, 110),
		Size = UDim2.new(0.46, 0, 1, -110 - M),
		BackgroundColor3 = Gui.CARD,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
	}, p)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
	make("UIStroke", { Color = Gui.HAIRLINE, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	-- short names, so a sixth tab fits: the player cards (unlocked by achievements, not spins)
	local short = { Style = "Style", Color = "Color", Trail = "Trail", Effect = "Effect", Pose = "Pose" }
	local kinds = {}
	for _, kind in ipairs(COS.Kinds) do
		table.insert(kinds, { key = kind, text = short[kind] or SP.Banners[kind].Name })
	end
	table.insert(kinds, { key = "Card", text = "Cards" })
	local _, setKind = Gui.tabs(panel, kinds, { Name = "Kinds", Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 52) }, function(key)
		click("UISelect")
		lockerKind = key
		MenuController.refresh()
	end)
	local grid = make("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(14, 76),
		Size = UDim2.new(1, -28, 1, -76 - 110),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Gui.HAIRLINE,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8) }, grid)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(150, 150), CellPadding = UDim2.fromOffset(16, 16), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local chips = {}
	for _, kind in ipairs(COS.Kinds) do
		chips[kind] = {}
		for i, item in ipairs(COS[kind]) do
			local card = lockerCard(grid, kind, item)
			card.button.LayoutOrder = i
			chips[kind][item.Key] = card
		end
	end
	-- the Cards tab: a list of player cards (each a small copy of the real card, with your numbers)
	local cardList = make("ScrollingFrame", {
		Name = "Cards",
		Position = UDim2.fromOffset(14, 76),
		Size = UDim2.new(1, -28, 1, -76 - 110),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Gui.HAIRLINE,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
	}, panel)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 18), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 10) }, cardList)
	make("UIListLayout", { Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder }, cardList)
	local cardRows = {}
	for i, def in ipairs(Extra.Cards.list()) do
		local row = make("TextButton", { Name = def.Key, Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = i }, cardList)
		local mini = Gui.playerCard(row, { Position = UDim2.fromOffset(6, 4) })
		make("UIScale", { Scale = 0.55 }, mini.root)
		local lock = make("Frame", { Position = UDim2.fromOffset(2, 0), Size = UDim2.fromOffset(274, 64), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 20 }, row)
		local edge = make("UIStroke", { Color = Gui.SIGNAL, Thickness = 2, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, lock)
		local nm = Gui.label(row, { Text = def.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, Position = UDim2.fromOffset(292, 2), Size = UDim2.new(1, -300, 0, 26) })
		Gui.label(row, { Text = def.Goal, TextSize = 14, TextColor3 = Gui.DIM, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(292, 28), Size = UDim2.new(1, -300, 0, 18) })
		local state = Gui.label(row, { Text = "", display = true, TextSize = 16, Position = UDim2.fromOffset(292, 46), Size = UDim2.new(1, -300, 0, 20) })
		onClick(row, function()
			lockerPick.Card = def.Key
			MenuController.refresh()
		end)
		cardRows[def.Key] = { row = row, mini = mini, lock = lock, edge = edge, name = nm, state = state }
	end
	-- the picked card, big over the gym (with a spike's word, as when you score)
	local cardPreview = Gui.playerCard(p, { Position = UDim2.fromOffset(M + 20, 160), Visible = false })
	make("UIScale", { Scale = 1.15 }, cardPreview.root)
	-- the picked item along the bottom, and Equip
	make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -102), Size = UDim2.new(1, -32, 0, 1), BackgroundColor3 = Gui.HAIRLINE, BackgroundTransparency = 0.6, BorderSizePixel = 0 }, panel)
	local pickName = Gui.label(panel, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 34, TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -46), Size = UDim2.new(1, -260, 0, 40) })
	local pickSub = Gui.label(panel, { Text = "", TextSize = 16, weight = Enum.FontWeight.Medium, RichText = true, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 22, 1, -22), Size = UDim2.new(1, -260, 0, 20) })
	local equip, equipL = actionPlate(panel, { Name = "Equip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -22), Size = UDim2.fromOffset(210, 60) }, "", 26)
	onClick(equip, function()
		local key = lockerPick[lockerKind]
		local prof = profile()
		if not key then
			return
		end
		if lockerKind == "Card" then
			local unlocked = prof.cards and prof.cards.unlocked or {}
			local def = Extra.Cards.get(key)
			if unlocked[key] then
				Net.get("Profile"):FireServer("equip", "Card", key)
			elseif def then
				toast(def.Stat == "grant" and "This card is given to content creators." or (def.Goal .. " to wear this card."))
			end
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
	local caption = Gui.label(p, { Text = "", TextSize = 18, weight = Enum.FontWeight.Medium, RichText = true, TextStrokeTransparency = 0.5, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, M, 1, -M), Size = UDim2.new(0.5, -M, 0, 24) })
	ui.locker = { setKind = setKind, chips = chips, pickName = pickName, pickSub = pickSub, equipL = equipL, caption = caption, grid = grid, cardList = cardList, cardRows = cardRows, cardPreview = cardPreview }
end

-- The Locker's Cards tab: every player card with your own numbers on it (locked ones dimmed, with
-- how far along you are), the picked one big over the gym, and Equip.
-- A card with Avatar (the Content Creator card) shows your own avatar mid-spike: posed again only
-- when your character or spike style changes.
function Extra.cardAvatar(card)
	local c = player.Character
	local key = c and (tostring(c) .. tostring(c:GetAttribute(Config.Cosmetics.Attribute.Style))) or nil
	if card.avatarKey ~= key then
		card.avatarKey = key
		mods.AnimationController.portrait(card.viewport, c, mods.AnimationController.spikePose(c))
	end
end

function Extra.refreshCards(prof)
	local L = ui.locker
	local C = Extra.Cards
	local cs = prof.cards or {}
	local stats = cs.stats or {}
	local unlocked = cs.unlocked or {}
	local equipped = prof.equip and prof.equip.Card or C.default()
	if not C.get(equipped) or not unlocked[equipped] then
		equipped = C.default()
	end
	local picked = C.get(lockerPick.Card) and lockerPick.Card or equipped
	lockerPick.Card = picked
	local char = Roster.get(prof.char or "")
	local tier = char and char.Tier or ""
	local line = char and (char.Name .. "  /  " .. roleName(char.Role)) or ""
	local team = Config.Teams.Home.Color
	local function data(def, withWord)
		local value, label = C.display(def, stats)
		return {
			userId = player.UserId,
			name = player.DisplayName,
			tier = tier,
			tierColor = tierColor(tier),
			line = line,
			value = value,
			label = label,
			word = withWord and (Config.Match.Celebrate.Spike or "KILL!") or nil,
			title = def.Key ~= C.default() and string.upper(def.Name) or nil,
		}
	end
	for key, r in pairs(L.cardRows) do
		local def = C.get(key)
		r.mini.set(C.look(def, team, stats.rank), data(def, false))
		if def.Look.Avatar then
			Extra.cardAvatar(r.mini)
		end
		local have = unlocked[key] == true
		r.lock.Visible = not have
		local got, need = C.progress(def, stats)
		if key == equipped then
			r.state.Text = "EQUIPPED"
			r.state.TextColor3 = Gui.SIGNAL
		elseif have then
			r.state.Text = "EQUIP"
			r.state.TextColor3 = Gui.CHALK
		elseif def.Stat == "rank" or def.Stat == "grant" then
			r.state.Text = def.Stat == "grant" and "GIVEN ONLY" or "LOCKED"
			r.state.TextColor3 = Gui.DIM
		else
			r.state.Text = string.format("LOCKED   %s / %s", Gui.num(got), Gui.num(need))
			r.state.TextColor3 = Gui.DIM
		end
		r.name.TextColor3 = key == picked and Gui.SIGNAL or Gui.CHALK
		r.edge.Transparency = key == picked and 0 or 1
	end
	local def = C.get(picked)
	L.cardPreview.set(C.look(def, team, stats.rank), data(def, true))
	if def.Look.Avatar then
		Extra.cardAvatar(L.cardPreview)
	end
	L.pickName.Text = def.Name
	local got, need = C.progress(def, stats)
	if unlocked[picked] then
		L.pickSub.Text = def.Goal
	elseif def.Stat == "grant" then
		L.pickSub.Text = def.Goal .. " (the developers give it)"
	elseif def.Stat == "rank" then
		L.pickSub.Text = def.Goal .. " to unlock it"
	else
		L.pickSub.Text = string.format("%s to unlock it (%s / %s)", def.Goal, Gui.num(got), Gui.num(need))
	end
	L.equipL.Text = unlocked[picked] and (picked == equipped and "Equipped" or "Equip") or "Locked"
end

local function refreshLocker(prof)
	local L = ui.locker
	L.setKind(lockerKind)
	local isCard = lockerKind == "Card"
	L.grid.Visible = not isCard
	L.cardList.Visible = isCard
	L.cardPreview.root.Visible = isCard
	for kind, list in pairs(L.chips) do
		local equipped = prof.equip and prof.equip[kind] or Spins.default(kind)
		local picked = lockerPick[kind] or equipped
		for key, card in pairs(list) do
			card.button.Visible = kind == lockerKind
			local have = owns(prof, kind, key)
			if key == equipped then
				card.state.Text = "EQUIPPED"
				card.state.TextColor3 = card.color
			elseif have then
				card.state.Text = "EQUIP"
				card.state.TextColor3 = Gui.CHALK
			else
				card.state.Text = "LOCKED"
				card.state.TextColor3 = Gui.DIM
			end
			-- the card being previewed glows white; locked ones sit back
			card.edge.Color = key == picked and Color3.new(1, 1, 1) or card.color
			card.edge.Transparency = have and 0 or 0.45
			card.button.BackgroundColor3 = key == picked and Color3.fromRGB(52, 56, 70) or Color3.fromRGB(34, 36, 46)
		end
	end
	if isCard then
		-- the Cards tab: your avatar holds its pose behind the big card
		Extra.refreshCards(prof)
		local o = lockerOpts(prof)
		o.posing = true
		L.caption.Text = "<b>Player card</b>   what everyone sees when you score"
		if shown and screen == "locker" then
			mods.SceneController.setPractice(o)
		end
		return
	end
	local key = lockerPick[lockerKind] or (prof.equip and prof.equip[lockerKind]) or Spins.default(lockerKind)
	lockerPick[lockerKind] = key
	local item = Spins.item(lockerKind, key)
	L.pickName.Text = item and item.Name or key
	L.pickSub.Text = item and string.format('<font color="#%s">%s</font>  %s', Spins.rarityColor(item.Rarity):ToHex(), item.Rarity, SP.Banners[lockerKind].Name) or ""
	local equipped = prof.equip and prof.equip[lockerKind] == key
	if owns(prof, lockerKind, key) then
		L.equipL.Text = equipped and "Equipped" or "Equip"
	else
		L.equipL.Text = "Recruit it"
	end
	local o = lockerOpts(prof)
	local function nm(kind, k)
		local it = Spins.item(kind, k)
		return it and it.Name or k
	end
	-- the Intro pose tab previews the pose: your avatar holds it instead of spiking
	o.posing = lockerKind == "Pose"
	if o.posing then
		L.caption.Text = string.format("<b>Preview</b>   %s  (the matchup intro, and after a win)", nm("Pose", o.pose))
	else
		L.caption.Text = string.format("<b>Preview</b>   %s  /  %s  /  %s  /  %s", nm("Style", o.style), nm("Color", o.color), nm("Trail", o.trail), nm("Effect", o.effect))
	end
	if shown and screen == "locker" then
		mods.SceneController.setPractice(o)
	end
end

------------------------------------------------------------------------------------------
-- Shop: V Point and Gold packs for Robux, and a big way into Recruit
------------------------------------------------------------------------------------------

-- the Shop's rows, two to a tab, each pack a Developer Product: V Points and Gold (Config.Shop),
-- then lucky spins (Config.Lucky) and 2x VP boosts (Config.Boosts). `amount` is what a card shows.
local SHOP_ROWS = {
	{ key = "VP", tab = "Currency", title = "V Points", note = "Recruit players and looks", icon = Gui.icon.vp },
	{ key = "Gold", tab = "Currency", title = "Gold", note = "Upgrade your players' stats", icon = Gui.icon.gold },
	{ key = "Lucky", tab = "Lucky", title = "Lucky spins", note = "Better odds on any banner, no Commons", icon = function(parent, size)
		return Gui.sparkle(parent, size, Gui.GOLD)
	end, amount = function(pack)
		return "x" .. pack.Lucky
	end },
	{ key = "Boost", tab = "Lucky", title = "2x V Points", note = "Every match pays double VP while it runs", icon = Gui.icon.vp, amount = function(pack)
		local m = math.floor(pack.BoostVP / 60 + 0.5)
		if m < 60 then
			return m .. " min"
		end
		return (m % 60 == 0 and tostring(m / 60) or string.format("%.1f", m / 60)) .. " hr"
	end },
}

local function shopPacks(key)
	local lists = { VP = Config.Shop.Packs, Gold = Config.Shop.GoldPacks, Lucky = Config.Lucky.Packs, Boost = Config.Boosts.Packs }
	return lists[key] or {}
end

local function buildShop()
	local p = page("shop")
	mainChrome(p, "shop")
	-- two tabs (the owner added lucky spins and 2x VP boosts to sell), two rows each
	local _, setTab = segmented(p, { { key = "Currency", text = "V Points & Gold" }, { key = "Lucky", text = "Lucky spins & boosts" } }, { Name = "ShopTabs", Position = UDim2.fromOffset(M, 150), Size = UDim2.fromOffset(520, 46) }, function(key)
		Extra.shopTab = key
		MenuController.refresh()
	end)
	local packs = make("Frame", { Name = "Packs", Position = UDim2.fromOffset(M, 210), Size = UDim2.fromOffset(4 * 200 + 3 * 14, 560), BackgroundTransparency = 1 }, p)
	local tabs = {}
	for _, key in ipairs({ "Currency", "Lucky" }) do
		tabs[key] = make("Frame", { Name = key, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, packs)
	end
	local prices = { VP = {}, Gold = {}, Lucky = {}, Boost = {} }
	local notes = {}
	local rowsIn = { Currency = 0, Lucky = 0 }
	for _, row in ipairs(SHOP_ROWS) do
		rowsIn[row.tab] = rowsIn[row.tab] + 1
		local y = (rowsIn[row.tab] - 1) * 284
		local holder = tabs[row.tab]
		Gui.label(holder, { Text = row.title, display = true, weight = Enum.FontWeight.Heavy, TextSize = 32, TextStrokeTransparency = 0.6, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), Position = UDim2.fromOffset(0, y) })
		notes[row.key] = Gui.label(holder, { Text = row.note, TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Gui.SIGNAL, TextStrokeTransparency = 0.6, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(420, 20), Position = UDim2.new(1, 0, 0, y + 12) })
		Gui.plate(holder, { Size = UDim2.fromOffset(60, 6), Position = UDim2.fromOffset(2, y + 40) }, Gui.SIGNAL)
		for i, pack in ipairs(shopPacks(row.key)) do
			local card = Gui.card(holder, { Size = UDim2.fromOffset(200, 224), Position = UDim2.fromOffset((i - 1) * 214, y + 56), ClipsDescendants = true })
			Gui.halftone(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.7, 1), ImageColor3 = Gui.CHALK, ImageTransparency = 0.94 })
			local icon = row.icon(card, 58)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.new(0.5, 0, 0, 16)
			Gui.label(card, { Text = row.amount and row.amount(pack) or Gui.num(pack[row.key]), display = true, weight = Enum.FontWeight.Heavy, TextSize = 42, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 80), TextXAlignment = Enum.TextXAlignment.Center })
			Gui.label(card, { Text = pack.Name, TextSize = 15, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 128), TextXAlignment = Enum.TextXAlignment.Center })
			local buy, price = actionPlate(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(172, 44) }, "", 20)
			-- buy it for someone else (the owner: "add a gifting system")
			local gift = hairButton(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(56, 28) }, "Gift", 15)
			onClick(gift, function()
				MenuController.openGift(row.key, i)
			end)
			onClick(buy, function()
				if pack.Id ~= 0 then
					pcall(function()
						MarketplaceService:PromptProductPurchase(player, pack.Id)
					end)
				elseif profile().studio then
					Net.get("Profile"):FireServer("buy", i, row.key)
				end
			end)
			prices[row.key][i] = price
			if pack.Id ~= 0 then
				task.spawn(function()
					local ok, info = pcall(function()
						return MarketplaceService:GetProductInfo(pack.Id, Enum.InfoType.Product)
					end)
					if ok and info and info.PriceInRobux then
						packPrices[row.key][i] = info.PriceInRobux
						MenuController.refresh()
					end
				end)
			end
		end
	end

	-- Recruit: the big way in, bottom right like Home's Match plate
	local recruit, recruitPlate = Gui.plateButton(p, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -M, 1, -M), Size = UDim2.fromOffset(440, 128) }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	Gui.halftone(recruitPlate.Body, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.7, 1) })
	local inset = Gui.plateInset(recruitPlate)
	local rIcon = Gui.icon.recruit(recruit, 58, Gui.LINE)
	rIcon.Position = UDim2.fromOffset(inset, 34)
	rIcon.ZIndex = 2
	Gui.label(recruit, { Text = "Recruit", display = true, weight = Enum.FontWeight.Heavy, TextSize = 66, TextColor3 = Gui.LINE, Size = UDim2.fromOffset(280, 72), Position = UDim2.fromOffset(inset + 72, 10), ZIndex = 2 })
	Gui.label(recruit, { Text = "Players, spike styles, colours, trails and effects", TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Gui.LINE, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.fromOffset(300, 40), Position = UDim2.fromOffset(inset + 76, 82), ZIndex = 2 })
	onClick(recruit, goRecruit)

	-- where Gold also comes from, bottom left like Home's tip line
	local P = Config.Progression
	Gui.label(p, {
		Text = string.format("Gold also comes from matches: %d for a win, %d for a loss and %d for every kill, ace or block. The match MVP earns %d extra V Points.", P.WinGold, P.LossGold, P.PlayGold, P.MvpVP),
		TextSize = 17,
		TextWrapped = true,
		TextStrokeTransparency = 0.5,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, M, 1, -M - 6),
		Size = UDim2.new(1, -(M * 2 + 440 + 40), 0, 48),
	})
	-- Perks, on the right: your own sounds and score image (VP, or a game pass)
	local perkCol = make("Frame", { Name = "Perks", Position = UDim2.fromOffset(M + 4 * 214 + 30, 150), Size = UDim2.new(1, -(M + 4 * 214 + 30 + M), 0, 560), BackgroundTransparency = 1 }, p)
	Gui.label(perkCol, { Text = "Perks", display = true, weight = Enum.FontWeight.Heavy, TextSize = 32, TextStrokeTransparency = 0.6, Size = UDim2.new(1, 0, 0, 36) })
	Gui.plate(perkCol, { Size = UDim2.fromOffset(60, 6), Position = UDim2.fromOffset(2, 40) }, Gui.SIGNAL)
	local perks = {}
	for i, key in ipairs(Config.Perks.Order) do
		local def = Config.Perks[key]
		local card = Gui.card(perkCol, { Position = UDim2.fromOffset(0, 56 + (i - 1) * 252), Size = UDim2.new(1, 0, 0, 236), ClipsDescendants = true })
		Gui.label(card, { Text = def.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 26, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 30) })
		Gui.label(card, { Text = def.Blurb, TextSize = 14, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -32, 0, 54) })
		-- not yours yet: buy it
		local buyVP = actionPlate(card, { Position = UDim2.fromOffset(12, 104), Size = UDim2.new(0.5, -18, 0, 46) }, string.format("%s VP", Gui.num(def.VP)), 20)
		local buyPass, buyPassLabel = hairButton(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 104), Size = UDim2.new(0.5, -18, 0, 46) }, "Robux", 18)
		-- yours: which of its sounds you're setting (a perk with Slots), the id, Save and Test
		local slots = def.Slots or { { Key = key, Name = def.Name, Verb = "you score" } }
		local e = { slot = 1 }
		local rowY = 104
		if def.Slots then
			local picker = make("Frame", { Name = "Slot", Position = UDim2.fromOffset(16, 100), Size = UDim2.new(1, -32, 0, 34), BackgroundTransparency = 1 }, card)
			local prev = hairButton(picker, { Size = UDim2.fromOffset(40, 34) }, "<", 20)
			local nxt = hairButton(picker, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(40, 34) }, ">", 20)
			e.slotName = Gui.label(picker, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -96, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
			local function step(d)
				e.slot = (e.slot - 1 + d) % #slots + 1
				e.shownId = nil -- show the new slot's id
				MenuController.refresh()
			end
			onClick(prev, function()
				step(-1)
			end)
			onClick(nxt, function()
				step(1)
			end)
			prev:SetAttribute("Sound", "UITick")
			nxt:SetAttribute("Sound", "UITick")
			e.picker = picker
			rowY = 140
		end
		local box = make("TextBox", {
			Position = UDim2.fromOffset(16, rowY),
			Size = UDim2.new(1, -32 - 188, 0, 46),
			BackgroundColor3 = Color3.fromRGB(6, 8, 16),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			TextColor3 = Gui.CHALK,
			PlaceholderColor3 = Gui.DIM,
			PlaceholderText = key == "ScoreSound" and "Sound id" or "Image or decal id",
			Text = "",
			FontFace = Gui.body(Enum.FontWeight.Medium),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
		}, card)
		make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)
		make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)
		local save = hairButton(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -104, 0, rowY), Size = UDim2.fromOffset(84, 46) }, "Save", 18)
		local test = hairButton(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, rowY), Size = UDim2.fromOffset(84, 46) }, "Test", 18)
		local status = Gui.label(card, { Text = "", TextSize = 14, TextColor3 = Gui.SIGNAL_HOT, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(16, rowY + 56), Size = UDim2.new(1, -32, 0, 226 - rowY - 56) })
		onClick(buyVP, function()
			Net.get("Profile"):FireServer("perkBuy", key)
		end)
		onClick(buyPass, function()
			if def.PassId ~= 0 then
				pcall(function()
					MarketplaceService:PromptGamePassPurchase(player, def.PassId)
				end)
			end
		end)
		onClick(save, function()
			Net.get("Profile"):FireServer("perkSet", slots[e.slot].Key, box.Text)
		end)
		onClick(test, function()
			local id = string.match(box.Text, "%d+")
			if not id then
				return
			end
			if table.find(def.Types, 3) then
				mods.AudioController.playId(id)
			else
				mods.UIController.showScoreImage(id)
			end
		end)
		e.slots, e.buyVP, e.buyPass, e.buyPassLabel, e.box, e.save, e.test, e.status = slots, buyVP, buyPass, buyPassLabel, box, save, test, status
		perks[key] = e
		if def.PassId ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(def.PassId, Enum.InfoType.GamePass)
				end)
				if ok and info and info.PriceInRobux then
					buyPassLabel.Text = "R$ " .. info.PriceInRobux
				end
			end)
		end
	end
	ui.shop = { prices = prices, perks = perks, tabs = tabs, setTab = setTab, notes = notes }
end

local function refreshPerks(prof)
	for key, e in pairs(ui.shop.perks) do
		local def = Config.Perks[key]
		local st = prof.perks and prof.perks[key] or {}
		local owned = st.owned == true
		local slot = e.slots[e.slot]
		local id = (st.ids and st.ids[slot.Key]) or (slot.Key == key and st.id) or nil
		e.buyVP.Visible = not owned
		e.buyPass.Visible = not owned and def.PassId ~= 0
		e.box.Visible, e.save.Visible, e.test.Visible = owned, owned, owned
		if e.picker then
			e.picker.Visible = owned
			e.slotName.Text = slot.Name
		end
		if owned and not e.box:IsFocused() and e.shownId ~= (id or "") then
			e.box.Text = id or ""
			e.shownId = id or ""
		end
		if owned then
			local sound = table.find(def.Types, 3) ~= nil
			e.status.Text = id and (sound and string.format("Plays when %s. Test it here.", slot.Verb or "you score") or "Pops up when you score. Test it here.") or "Paste an id and Save."
		else
			e.status.Text = def.PassId ~= 0 and "" or "The game pass comes soon; VP works now."
		end
	end
end

local function refreshShop(prof)
	refreshPerks(prof)
	ui.shop.setTab(Extra.shopTab)
	for key, f in pairs(ui.shop.tabs) do
		f.Visible = key == Extra.shopTab
	end
	-- the boost row says how long yours has left
	local boostLeft = (prof.boostVP or 0) - (os.clock() - Extra.profileAt)
	ui.shop.notes.Boost.Text = boostLeft > 0 and string.format("Yours: %s left (more adds on top)", Extra.clockText(boostLeft)) or SHOP_ROWS[4].note
	for key, labels in pairs(ui.shop.prices) do
		for i, pack in ipairs(shopPacks(key)) do
			local label = labels[i]
			if pack.Id ~= 0 then
				label.Text = packPrices[key][i] and ("R$ " .. packPrices[key][i]) or "..."
			elseif prof.studio then
				label.Text = "Free in Studio"
			else
				label.Text = "Soon"
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- The lobby window: the lobby list, Create Lobby and your lobby (the Match screen's cards open
-- it; Quick Match starts from the cards)
------------------------------------------------------------------------------------------

local LC = Config.Lobby
local MC = Config.Match.Custom
local form = { mode = 3, privacy = "Public", password = "", fill = true, botTier = Config.Match.DefaultBotTier, court = Config.Courts.Rotate, points = Config.Match.PointsPerSet, winBy = Config.Match.WinBy, sets = 1, timeouts = Config.Timeout.PerSet }
local matchTab = "Browse"
local editing = false -- the host is changing their lobby's settings
local joinTarget = nil -- a private lobby waiting for its password

local PRIVACY_TEXT = { Public = "Public", Friends = "Friends only", Private = "Private" }
-- the court picker's choices: the rotation first, then every court in rotation order
local COURT_CHOICES = { Config.Courts.Rotate }
for _, id in ipairs(Config.Courts.Rotation) do
	table.insert(COURT_CHOICES, id)
end

local function courtName(id)
	local c = Config.Courts.List[id or ""]
	return c and c.Name or "Rotation"
end

local STATE_TEXT = { Open = "Open", Queued = "Queued", Teleporting = "Starting", Arriving = "Starting", Playing = "Playing" }

-- Broadcast tabs: slanted plates, the picked one signal yellow with dark type, the rest dark with
-- chalk type that turns yellow under the pointer. Returns the row and a setter(activeKey).
local function plateTabs(parent, items, props, onPick)
	local f = make("Frame", { BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	local h = f.Size.Y.Offset
	local w = math.floor((f.Size.X.Offset - (#items - 1) * 6) / #items)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	local tabs = {}
	for i, it in ipairs(items) do
		local b = make("TextButton", { Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = i }, f)
		local rest = Gui.plate(b, { Size = UDim2.fromOffset(w, h) }, Gui.NAVY)
		Gui.fade(rest, 0.3)
		local picked = Gui.plate(b, { Size = UDim2.fromOffset(w, h), Visible = false }, Gui.SIGNAL)
		local label = Gui.label(b, { Text = it.text, display = true, TextSize = math.floor(h * 0.48), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
		local tab = { key = it.key, rest = rest, picked = picked, label = label, on = false }
		tabs[i] = tab
		b:SetAttribute("Sound", "UISelect")
		onClick(b, function()
			onPick(it.key)
		end)
		b.MouseEnter:Connect(function()
			if not tab.on then
				label.TextColor3 = Gui.SIGNAL
				if Gui.onHover then
					Gui.onHover()
				end
			end
		end)
		b.MouseLeave:Connect(function()
			if not tab.on then
				label.TextColor3 = Gui.CHALK
			end
		end)
	end
	local function set(active)
		for _, tab in ipairs(tabs) do
			tab.on = tab.key == active
			tab.picked.Visible = tab.on
			tab.rest.Visible = not tab.on
			tab.label.TextColor3 = tab.on and Gui.LINE or Gui.CHALK
		end
	end
	return f, set
end

-- A text field in the broadcast kit: dark, a hairline edge, body type.
local function field(parent, props)
	local box = make("TextBox", {
		BackgroundColor3 = Color3.fromRGB(6, 8, 16),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		TextColor3 = Gui.CHALK,
		PlaceholderColor3 = Gui.DIM,
		Text = "",
		FontFace = Gui.body(Enum.FontWeight.Medium),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
	}, parent)
	for k, v in pairs(props or {}) do
		box[k] = v
	end
	make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)
	return box
end

local function stepper(parent, props, onStep)
	local f = make("Frame", { BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	local down = hairButton(f, { Size = UDim2.fromOffset(44, 42) }, "<", 24)
	local value = Gui.label(f, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, Size = UDim2.new(1, -96, 1, 0), Position = UDim2.fromOffset(48, 0), TextXAlignment = Enum.TextXAlignment.Center })
	local up = hairButton(f, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(44, 42) }, ">", 24)
	down:SetAttribute("Sound", "UITick")
	up:SetAttribute("Sound", "UITick")
	-- a click steps once; held down it keeps stepping (3 to 50 points is a long way)
	local function repeater(b, dir)
		local held, last = nil, nil
		b.MouseButton1Down:Connect(function()
			local token = { repeated = false }
			held, last = token, token
			task.delay(0.4, function()
				while held == token and b.Parent do
					token.repeated = true
					onStep(dir)
					if Gui.play then
						Gui.play("UITick", { minGap = 0.05 })
					end
					task.wait(0.07)
				end
			end)
		end)
		local function stop()
			held = nil
		end
		b.MouseButton1Up:Connect(stop)
		b.MouseLeave:Connect(stop)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				stop()
			end
		end)
		onClick(b, function()
			if not (last and last.repeated) then
				onStep(dir)
			end
			last = nil
		end)
	end
	repeater(down, -1)
	repeater(up, 1)
	return value
end

local function formRow(parent, y, label, x)
	return Gui.label(parent, { Text = label, display = true, TextSize = 21, Size = UDim2.fromOffset(170, 44), Position = UDim2.fromOffset(x or 0, y) })
end

-- A custom lobby's rules in a line: "to 21, win by 2, best of 3, 2 timeouts".
local function rulesLine(r)
	local parts = { string.format("to %d", r.points or Config.Match.PointsPerSet) }
	table.insert(parts, (r.winBy or Config.Match.WinBy) > 1 and "win by 2" or "no deuce")
	table.insert(parts, (r.sets or 1) > 1 and string.format("best of %d", r.sets) or "1 set")
	local n = r.timeouts or Config.Timeout.PerSet
	table.insert(parts, n == 1 and "1 timeout" or string.format("%d timeouts", n))
	return table.concat(parts, ", ")
end

-- The lobby window, in Home's broadcast kit: plate tabs, hairline cards, the display face and a
-- signal-yellow plate for the one action on each page. MODE_LINES name the modes (the Match
-- screen's cards).
local MODE_LINES = {
	{ "Solo", "Spike, set and dig on your own" },
	{ "Pairs", "A wing spiker and a setter" },
	{ "Full team", "Wing spiker, middle and setter" },
}

local function buildMatch()
	local m = modal("Match", "Lobbies", 1100, 620, true)
	local P = m.panel
	local tabs, setTab = plateTabs(P, { { key = "Browse", text = "Lobbies" }, { key = "Create", text = "Create Lobby" } }, { Size = UDim2.fromOffset(400, 46), Position = UDim2.fromOffset(24, 88) }, function(key)
		matchTab = key
		joinTarget = nil
		MenuController.refresh()
	end)
	local body = make("Frame", { Position = UDim2.fromOffset(26, 152), Size = UDim2.new(1, -52, 1, -172), BackgroundTransparency = 1 }, P)

	-- the lobby list
	local browse = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, body)
	local list = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, browse)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local empty = Gui.label(browse, { Text = "No lobbies here yet. Create one, or use Quick Match.", TextSize = 18, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	local rows = {}
	for i = 1, LC.MaxLobbies do
		local r = Gui.card(list, { Size = UDim2.new(1, -10, 0, 72), LayoutOrder = i, Visible = false })
		local host = Gui.label(r, { Text = "", display = true, TextSize = 24, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(0.5, 0, 0, 30), Position = UDim2.fromOffset(18, 8) })
		local detail = Gui.label(r, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(18, 42) })
		local count = Gui.label(r, { Text = "", display = true, TextSize = 26, Size = UDim2.fromOffset(80, 72), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -292, 0, 0), TextXAlignment = Enum.TextXAlignment.Right })
		local state = Gui.plate(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -170, 0.5, 0), Size = UDim2.fromOffset(100, 26) }, Gui.NAVY_LIGHT)
		local stateLabel = Gui.label(state, { Text = "", display = true, TextSize = 15, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
		local join, joinPlate = Gui.plateButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(140, 44) }, Gui.SIGNAL, Gui.SIGNAL_HOT)
		local joinLabel = Gui.label(join, { Text = "Join", display = true, TextSize = 20, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
		local entry = { frame = r, host = host, detail = detail, count = count, state = state, stateLabel = stateLabel, join = join, joinPlate = joinPlate, joinLabel = joinLabel }
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
	-- password prompt (a button of its own, so a click on it never reaches the rows under it)
	local prompt = make("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(480, 200), BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.02, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 5 }, browse)
	make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, prompt)
	Gui.label(prompt, { Text = "This lobby is private", display = true, TextSize = 26, Size = UDim2.new(1, -40, 0, 30), Position = UDim2.fromOffset(20, 14) })
	local pwBox = field(prompt, { Size = UDim2.new(1, -40, 0, 46), Position = UDim2.fromOffset(20, 56), PlaceholderText = "Password" })
	local pwJoin = actionPlate(prompt, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -16), Size = UDim2.fromOffset(150, 46) }, "Join")
	local pwCancel = hairButton(prompt, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -184, 1, -16), Size = UDim2.fromOffset(120, 46) }, "Cancel")
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
	local _, setMode = plateTabs(create, { { key = 1, text = "1v1" }, { key = 2, text = "2v2" }, { key = 3, text = "3v3" } }, { Size = UDim2.fromOffset(420, 44), Position = UDim2.fromOffset(180, 0) }, function(k)
		form.mode = k
		MenuController.refresh()
	end)
	formRow(create, 62, "Who can join")
	local _, setPrivacy = plateTabs(create, { { key = "Public", text = "Public" }, { key = "Friends", text = "Friends" }, { key = "Private", text = "Private" } }, { Size = UDim2.fromOffset(420, 44), Position = UDim2.fromOffset(180, 62) }, function(k)
		form.privacy = k
		MenuController.refresh()
	end)
	local privacyNote = Gui.label(create, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.fromOffset(480, 20), Position = UDim2.fromOffset(180, 110) })
	local cpwLabel = formRow(create, 140, "Password")
	local cpw = field(create, { Size = UDim2.fromOffset(420, 44), Position = UDim2.fromOffset(180, 140), PlaceholderText = string.format("%d to %d letters or digits", LC.PasswordMin, LC.PasswordMax) })
	cpw:GetPropertyChangedSignal("Text"):Connect(function()
		form.password = cpw.Text
	end)
	formRow(create, 200, "Fill with bots")
	local _, setFill = plateTabs(create, { { key = true, text = "On" }, { key = false, text = "Off" } }, { Size = UDim2.fromOffset(280, 44), Position = UDim2.fromOffset(180, 200) }, function(k)
		form.fill = k
		MenuController.refresh()
	end)
	local fillNote = Gui.label(create, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.fromOffset(500, 20), Position = UDim2.fromOffset(180, 248) })
	formRow(create, 280, "Bot level")
	local botValue = stepper(create, { Size = UDim2.fromOffset(220, 42), Position = UDim2.fromOffset(180, 280) }, function(d)
		local i = Characters.tierIndex(form.botTier) or 11
		form.botTier = Config.Tiers[math.clamp(i + d, 1, #Config.Tiers)]
		MenuController.refresh()
	end)
	formRow(create, 340, "Court")
	local courtValue = stepper(create, { Size = UDim2.fromOffset(330, 42), Position = UDim2.fromOffset(180, 340) }, function(d)
		local i = 1
		for k, id in ipairs(COURT_CHOICES) do
			if id == form.court then
				i = k
			end
		end
		form.court = COURT_CHOICES[(i - 1 + d) % #COURT_CHOICES + 1]
		MenuController.refresh()
	end)
	courtValue.TextSize = 24
	local courtNote = Gui.label(create, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.fromOffset(400, 20), Position = UDim2.fromOffset(180, 388) })

	-- the match rules, in a column of their own on the right
	local RX = 650
	formRow(create, 0, "Points", RX)
	local pointsValue = stepper(create, { Size = UDim2.fromOffset(200, 42), Position = UDim2.fromOffset(RX + 150, 0) }, function(d)
		form.points = math.clamp(form.points + d, MC.PointsMin, MC.PointsMax)
		MenuController.refresh()
	end)
	local pointsNote = Gui.label(create, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.fromOffset(250, 38), Position = UDim2.fromOffset(RX + 150, 46) })
	formRow(create, 96, "Win by 2", RX)
	local _, setWinBy = plateTabs(create, { { key = 2, text = "On" }, { key = 1, text = "Off" } }, { Size = UDim2.fromOffset(250, 44), Position = UDim2.fromOffset(RX + 150, 96) }, function(k)
		form.winBy = k
		MenuController.refresh()
	end)
	formRow(create, 158, "Sets", RX)
	local _, setSets = plateTabs(create, { { key = 1, text = "1" }, { key = 3, text = "Best of 3" }, { key = 5, text = "Best of 5" } }, { Size = UDim2.fromOffset(250, 44), Position = UDim2.fromOffset(RX + 150, 158) }, function(k)
		form.sets = k
		MenuController.refresh()
	end)
	local setsNote = Gui.label(create, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.fromOffset(250, 20), Position = UDim2.fromOffset(RX + 150, 206) })
	formRow(create, 240, "Timeouts", RX)
	local timeoutsValue = stepper(create, { Size = UDim2.fromOffset(200, 42), Position = UDim2.fromOffset(RX + 150, 240) }, function(d)
		form.timeouts = math.clamp(form.timeouts + d, 0, MC.TimeoutsMax)
		MenuController.refresh()
	end)
	Gui.label(create, { Text = "Per team, every set.", TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.fromOffset(250, 20), Position = UDim2.fromOffset(RX + 150, 286) })
	local submit, submitLabel = actionPlate(create, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(250, 58) }, "Create Lobby", 24)
	local cancelEdit = hairButton(create, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -266, 1, 0), Size = UDim2.fromOffset(180, 58), Visible = false }, "Back to lobby")
	onClick(submit, function()
		local s = { mode = form.mode, privacy = form.privacy, password = form.password, fill = form.fill, botTier = form.botTier, court = form.court, points = form.points, winBy = form.winBy, sets = form.sets, timeouts = form.timeouts }
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

	-- your lobby: both sides as cards with the team's colour along the top
	local lobby = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, body)
	local info = Gui.label(lobby, { Text = "", TextSize = 16, TextColor3 = Gui.DIM, RichText = true, Size = UDim2.new(1, 0, 0, 22) })
	local status = Gui.label(lobby, { Text = "", display = true, TextSize = 22, TextColor3 = Gui.SIGNAL, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 26) })
	local sides = {}
	for i, team in ipairs(Config.TeamOrder) do
		local cfg = Config.Teams[team]
		local col = Gui.card(lobby, { Size = UDim2.new(0.5, -8, 0, 256), Position = UDim2.new((i - 1) * 0.5, (i - 1) * 8, 0, 64) })
		make("Frame", { Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = cfg.Color, BorderSizePixel = 0 }, col)
		Gui.label(col, { Text = cfg.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextColor3 = cfg.Color, Size = UDim2.new(1, -28, 0, 36), Position = UDim2.fromOffset(14, 12) })
		local slots = {}
		for s = 1, 3 do
			local row = make("Frame", { Size = UDim2.new(1, -24, 0, 54), Position = UDim2.fromOffset(12, 56 + (s - 1) * 62), BackgroundColor3 = Gui.NAVY, BackgroundTransparency = 0.4, BorderSizePixel = 0 }, col)
			make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.7, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
			local nm = Gui.label(row, { Text = "", display = true, TextSize = 21, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -164, 1, 0), Position = UDim2.fromOffset(14, 0) })
			local tag = Gui.plate(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -92, 0.5, 0), Size = UDim2.fromOffset(58, 22), Visible = false }, Gui.SIGNAL)
			Gui.label(tag, { Text = "HOST", display = true, TextSize = 13, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
			local kick = hairButton(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(76, 32), Visible = false }, "Remove", 14)
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
	local swap = hairButton(lobby, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.fromOffset(160, 56) }, "Switch side")
	local settingsB = hairButton(lobby, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 172, 1, 0), Size = UDim2.fromOffset(140, 56) }, "Settings")
	local leave, leaveLabel = hairButton(lobby, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -266, 1, 0), Size = UDim2.fromOffset(180, 56) }, "Leave lobby")
	local start = actionPlate(lobby, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(250, 58) }, "Start", 28)
	onClick(swap, function()
		Net.get("Lobby"):FireServer("team")
	end)
	onClick(settingsB, function()
		local mine = lobbies.mine
		if mine then
			form.mode, form.privacy, form.fill, form.botTier, form.court = mine.mode, mine.privacy, mine.fill, mine.botTier, mine.court or Config.Courts.Rotate
			form.points, form.winBy = mine.points or Config.Match.PointsPerSet, mine.winBy or Config.Match.WinBy
			form.sets, form.timeouts = mine.sets or 1, mine.timeouts or Config.Timeout.PerSet
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
		body = body,
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
		cpwLabel = cpwLabel,
		setFill = setFill,
		fillNote = fillNote,
		botValue = botValue,
		courtValue = courtValue,
		courtNote = courtNote,
		pointsValue = pointsValue,
		pointsNote = pointsNote,
		setWinBy = setWinBy,
		setSets = setSets,
		setsNote = setsNote,
		timeoutsValue = timeoutsValue,
		submit = submit,
		submitLabel = submitLabel,
		cancelEdit = cancelEdit,
		lobby = lobby,
		info = info,
		status = status,
		sides = sides,
		swap = swap,
		settings = settingsB,
		leave = leave,
		leaveLabel = leaveLabel,
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
	-- in a lobby there are no tabs: its page moves up into their place
	Mt.body.Position = UDim2.fromOffset(26, mine and 100 or 152)
	Mt.body.Size = UDim2.new(1, -52, 1, mine and -120 or -172)
	Mt.setTab(matchTab)
	Mt.browse.Visible = mine == nil and matchTab == "Browse"
	Mt.create.Visible = (mine == nil and matchTab == "Create") or (mine ~= nil and editing)
	Mt.lobby.Visible = inLobby
	if mine then
		Mt.modal.title.Text = mine.quick and string.format("Quick Match %dv%d", mine.mode, mine.mode) or (mine.hostName .. "'s Lobby")
	else
		Mt.modal.title.Text = "Lobbies"
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
			row.detail.Text = string.format("%dv%d   %s   %s   Bots %s   %s%s", l.mode, l.mode, PRIVACY_TEXT[l.privacy] or l.privacy, l.fill and "Bots fill" or "No bots", l.botTier, l.quick and "Rotation" or courtName(l.court), l.quick and "" or ("   " .. rulesLine(l)))
			row.count.Text = string.format("%d/%d", l.count, l.capacity)
			row.stateLabel.Text = STATE_TEXT[l.state] or l.state
			Gui.tint(row.state, l.state == "Open" and Color3.fromRGB(34, 150, 96) or Gui.NAVY_LIGHT)
			local can = l.state == "Open" and l.count < l.capacity and not l.mine
			row.joinLabel.Text = l.mine and "Joined" or (l.locked and "Password" or "Join")
			row.join.Active = can
			Gui.fade(row.joinPlate, can and 0 or 0.55)
			row.joinLabel.TextTransparency = can and 0 or 0.35
		end
	end
	Mt.empty.Visible = shownRows == 0
	Mt.prompt.Visible = joinTarget ~= nil and mine == nil

	-- Create / settings
	Mt.setMode(form.mode)
	Mt.setPrivacy(form.privacy)
	Mt.setFill(form.fill)
	Mt.cpw.Visible = form.privacy == "Private"
	Mt.cpwLabel.Visible = Mt.cpw.Visible
	Mt.privacyNote.Text = form.privacy == "Friends" and "Only your Roblox friends in this server see and join it." or (form.privacy == "Private" and "Listed with a lock: players need the password." or "Anyone in this server can join.")
	Mt.fillNote.Text = form.fill and "Start any time: bots take the empty spots." or "Both teams must be full before you can start."
	Mt.botValue.Text = form.botTier
	Mt.botValue.TextColor3 = tierColor(form.botTier)
	Mt.courtValue.Text = courtName(form.court)
	local pickedCourt = Config.Courts.List[form.court]
	Mt.courtNote.Text = pickedCourt and pickedCourt.Blurb or "A different court every match."
	Mt.pointsValue.Text = tostring(form.points)
	Mt.pointsNote.Text = form.points < Config.Match.PointsPerSet and string.format("Under %d pays less and doesn't count for your record.", Config.Match.PointsPerSet) or "The points a set is played to."
	Mt.setWinBy(form.winBy)
	Mt.setSets(form.sets)
	Mt.timeoutsValue.Text = tostring(form.timeouts)
	Mt.setsNote.Text = form.sets > 1 and string.format("First to %d sets wins.", math.floor(form.sets / 2) + 1) or "Then a vote to keep playing."
	Mt.submitLabel.Text = editing and "Save settings" or "Create Lobby"
	Mt.cancelEdit.Visible = editing

	-- your lobby
	if mine then
		local parts = { string.format("%dv%d", mine.mode, mine.mode), PRIVACY_TEXT[mine.privacy] or mine.privacy }
		if mine.password then
			table.insert(parts, "password <b>" .. mine.password .. "</b>")
		end
		table.insert(parts, mine.fill and ("bots fill empty spots (level " .. mine.botTier .. ")") or "no bots")
		table.insert(parts, mine.quick and "court rotation" or courtName(mine.court))
		if not mine.quick then
			table.insert(parts, rulesLine(mine))
		end
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
					slot.name.TextColor3 = who.id == player.UserId and Gui.SIGNAL or Gui.CHALK
					slot.tag.Visible = who.host == true
					slot.kick.Visible = mine.isHost and who.id ~= player.UserId and mine.state == "Open"
				else
					slot.name.Text = mine.fill and "Bot" or "Open"
					slot.name.TextColor3 = Gui.DIM
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
		Mt.leaveLabel.Text = mine.quick and "Cancel queue" or "Leave lobby"
	end
end

------------------------------------------------------------------------------------------
-- The Match screen, laid out like The Spike's (our own art): a row of tall cards, one per way
-- to play, each over one of our courts: an icon and the name on top, a strip under them, the
-- court, and a status line along the bottom. The quick modes queue you at once (the lobby
-- window opens with the countdown); Lobbies and Custom open the window on their tab; Practice
-- goes to the drills. The row scrolls sideways when it's wider than the screen.
------------------------------------------------------------------------------------------

local MATCH_CARDS = {
	{ key = "3", mode = 3, title = "3v3", icon = "IconPlayers", art = "MatchArena" },
	{ key = "2", mode = 2, title = "2v2", icon = "IconPlayers", art = "MatchBeach" },
	{ key = "1", mode = 1, title = "1v1", icon = "IconAttack", art = "MatchRooftop" },
	{ key = "Lobbies", title = "Lobbies", icon = "IconHome", art = "MatchNationals", strip = "Public, friends and private" },
	{ key = "Custom", title = "Custom", icon = "IconSettings", art = "MatchColosseum", strip = "Host your own lobby" },
	{ key = "Practice", title = "Practice", icon = "IconJump", art = "MatchPractice", strip = "Drills and the tutorial" },
}
local CARD_W, CARD_H, CARD_GAP = 290, 490, 18

-- A card's status line: short, for the lobby you're in.
local function lobbyLine(mine)
	if mine.state == "Queued" then
		return "Waiting for the court"
	elseif mine.state == "Teleporting" or mine.state == "Arriving" then
		return "Joining..."
	elseif mine.state == "Playing" then
		return "Match in progress"
	elseif mine.quick then
		return string.format("Starting in %d", math.max(0, math.ceil((mine.startsAt or 0) - workspace:GetServerTimeNow())))
	end
	return string.format("%d/%d in the lobby", mine.count, mine.capacity)
end

local function pickMatchCard(c)
	local mine = lobbies.mine
	if mine and (mine.tutorial or mine.practice) then
		mine = nil
	end
	if c.key ~= "Practice" and Extra.mustTutorial() then
		toast("Play the tutorial first: it's quick, and it pays.")
		Extra.openHowTo(true)
		return
	end
	if c.key == "Practice" then
		MenuController.go("practice")
	elseif c.mode then
		if mine then
			-- your lobby's window: its countdown, or Leave / Cancel queue before another mode
			if not (mine.quick and mine.mode == c.mode) then
				toast("You're already in a lobby: leave it first.")
			end
			MenuController.openMatch()
		else
			Net.get("Lobby"):FireServer("quick", c.mode)
		end
	else
		if not mine then
			matchTab = c.key == "Custom" and "Create" or "Browse"
			joinTarget = nil
		end
		MenuController.openMatch()
	end
end

local function buildMatchScreen()
	local p = page("match")
	-- the club room behind stays blurred (applyScene) and dimmed, as in the reference
	make("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, BorderSizePixel = 0 }, p)
	mainChrome(p, "match", "home")
	-- back to Home, and the title, under the currencies
	local back = make("TextButton", { Name = "Back", Size = UDim2.fromOffset(360, 60), Position = UDim2.fromOffset(M, 112), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, p)
	local arrow = Gui.iconImage(back, "IconBack", 40, Gui.SIGNAL, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0) })
	Gui.label(back, { Text = "Match", display = true, weight = Enum.FontWeight.Heavy, TextSize = 54, TextStrokeTransparency = 0.55, Size = UDim2.new(1, -64, 1, 0), Position = UDim2.fromOffset(62, 0) })
	back.MouseEnter:Connect(function()
		arrow.ImageColor3 = Gui.SIGNAL_HOT
		if Gui.onHover then
			Gui.onHover()
		end
	end)
	back.MouseLeave:Connect(function()
		arrow.ImageColor3 = Gui.SIGNAL
	end)
	onClick(back, function()
		MenuController.go("home")
	end)

	local row = make("ScrollingFrame", {
		Name = "Cards",
		Position = UDim2.fromOffset(0, 196),
		Size = UDim2.new(1, 0, 0, CARD_H + 24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	}, p)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, CARD_GAP), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	make("UIPadding", { PaddingLeft = UDim.new(0, M), PaddingRight = UDim.new(0, M) }, row)

	local cards = {}
	for i, c in ipairs(MATCH_CARDS) do
		local b = make("TextButton", { Name = c.key, Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ClipsDescendants = true, LayoutOrder = i }, row)
		-- the court (print grain over the card colour until the art loads)
		Gui.halftone(b, { Size = UDim2.fromScale(1, 1), ImageColor3 = Gui.CHALK, ImageTransparency = 0.9 })
		make("ImageLabel", { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Assets.image(c.art) or "", ScaleType = Enum.ScaleType.Crop }, b)
		-- dark behind the name and the status line, clear over the court
		local shade = make("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, b)
		make("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.25, 0.62),
				NumberSequenceKeypoint.new(0.45, 1),
				NumberSequenceKeypoint.new(0.72, 0.88),
				NumberSequenceKeypoint.new(1, 0.25),
			}),
		}, shade)
		-- the icon and the name, centred
		local head = make("Frame", { Name = "Head", Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1 }, b)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, head)
		Gui.iconImage(head, c.icon, 36, Gui.CHALK, { LayoutOrder = 1 })
		Gui.label(head, { Text = c.title, display = true, weight = Enum.FontWeight.Heavy, TextSize = 44, TextStrokeTransparency = 0.5, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 54), LayoutOrder = 2 })
		-- the strip under it
		local strip = make("Frame", { Name = "Strip", Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0 }, b)
		local stripText = c.strip or string.format("%s   %d players", MODE_LINES[c.mode][1], c.mode * 2)
		Gui.label(strip, { Text = stripText, TextSize = 17, weight = Enum.FontWeight.Medium, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		-- the status line along the bottom
		local foot = make("Frame", { Name = "Foot", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, b)
		local footL = Gui.label(foot, { Text = "", display = true, TextSize = 21, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Center })
		local edge = make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local scale = make("UIScale", { Scale = 1 }, b)
		local e = { button = b, foot = foot, footL = footL, edge = edge, hot = false, over = false }
		local function look()
			edge.Color = (e.hot or e.over) and Gui.SIGNAL or Gui.HAIRLINE
			edge.Thickness = e.hot and 3 or (e.over and 2 or 1)
			edge.Transparency = (e.hot or e.over) and 0 or 0.45
		end
		e.look = look
		b.MouseEnter:Connect(function()
			e.over = true
			look()
			tween(scale, 0.12, { Scale = 1.02 })
			if Gui.onHover then
				Gui.onHover()
			end
		end)
		b.MouseLeave:Connect(function()
			e.over = false
			look()
			tween(scale, 0.12, { Scale = 1 })
		end)
		b.MouseButton1Down:Connect(function()
			scale.Scale = 0.98
		end)
		b.MouseButton1Up:Connect(function()
			scale.Scale = e.over and 1.02 or 1
		end)
		if c.mode then
			b:SetAttribute("Sound", "UIConfirm")
		end
		onClick(b, function()
			pickMatchCard(c)
		end)
		cards[c.key] = e
	end
	ui.matchScreen = { cards = cards, row = row, back = back }
end

local function refreshMatchScreen(prof)
	local ms = ui.matchScreen
	local mine = lobbies.mine
	if mine and (mine.tutorial or mine.practice) then
		mine = nil
	end
	local waiting, open = { 0, 0, 0 }, 0
	for _, l in ipairs(lobbies.list or {}) do
		if l.quick then
			if l.state == "Open" and l.privacy == "Public" and waiting[l.mode] then
				waiting[l.mode] = waiting[l.mode] + l.count
			end
		elseif l.state == "Open" and not l.mine then
			open = open + 1
		end
	end
	local tut = prof.tutorial or {}
	for _, c in ipairs(MATCH_CARDS) do
		local e = ms.cards[c.key]
		local text, hot = "", false
		if c.mode then
			if mine and mine.quick and mine.mode == c.mode then
				text, hot = lobbyLine(mine), true
			elseif waiting[c.mode] > 0 then
				text = string.format("%d waiting", waiting[c.mode])
			else
				text = "Bots fill empty spots"
			end
		elseif c.key == "Lobbies" then
			if mine and not mine.quick and not mine.isHost then
				text, hot = lobbyLine(mine), true
			else
				text = open == 0 and "None open yet" or (open == 1 and "1 open" or string.format("%d open", open))
			end
		elseif c.key == "Custom" then
			if mine and not mine.quick and mine.isHost then
				text, hot = lobbyLine(mine), true
			else
				text = "Your court, your bots"
			end
		else
			if tut.done then
				text = "Tutorial complete"
			else
				local vp, gold = Tutorial.reward()
				text = string.format("Tutorial: %d VP, %s Gold", vp, Gui.num(gold))
			end
		end
		e.footL.Text = text
		e.footL.TextColor3 = hot and Gui.LINE or Gui.CHALK
		e.foot.BackgroundColor3 = hot and Gui.SIGNAL or Color3.new(0, 0, 0)
		e.foot.BackgroundTransparency = hot and 0.05 or 0.35
		e.hot = hot
		e.look()
	end
end

------------------------------------------------------------------------------------------
-- Leaderboards: wins, best win streak, spike kills, aces, blocks
------------------------------------------------------------------------------------------

local Leaderboards = require(Shared.Leaderboards)
local boardData = nil -- the server's last answer
local boardKey = "wins"
local lastBoardAsk = -math.huge
local MEDAL = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(205, 214, 228), Color3.fromRGB(214, 140, 80) }

local function askBoards(force)
	if force or os.clock() - lastBoardAsk > 30 then
		lastBoardAsk = os.clock()
		Net.get("Leaderboard"):FireServer("get")
	end
end

------------------------------------------------------------------------------------------
-- Practice: a card per drill (the ball comes to you, no rallies) and the tutorial
------------------------------------------------------------------------------------------

local DRILL_ICON = { spike = "IconAttack", block = "IconDefense", serve = "IconStar", dig = "IconSpeed" }

-- How to do a drill on the device you're using.
local function drillHow(d)
	if State.isMobile then
		return d.touch
	elseif mods and mods.InputController and mods.InputController.lastDevice() == "Gamepad" then
		return d.pad
	end
	return Tutorial.fill(d.key, function(action)
		return mods and mods.InputController and mods.InputController.keysText(action, " or ") or action
	end)
end

local function buildPractice()
	local p = page("practice")
	mainChrome(p, "practice")
	Gui.label(p, { Text = "Practice", display = true, weight = Enum.FontWeight.Heavy, TextSize = 56, Position = UDim2.fromOffset(M, 112), Size = UDim2.fromOffset(600, 64) })
	Gui.label(p, { Text = "One ball at a time, no rallies: the court sets you up for each rep.", TextSize = 18, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(M + 4, 176), Size = UDim2.fromOffset(900, 24) })
	local cards = {}
	local w, gap = 358, 20
	for i, d in ipairs(Tutorial.Drills) do
		local card = Gui.card(p, { Position = UDim2.fromOffset(M + (i - 1) * (w + gap), 220), Size = UDim2.fromOffset(w, 420) })
		Gui.plate(card, { Size = UDim2.fromOffset(64, 6), Position = UDim2.fromOffset(20, 20) }, Gui.SIGNAL)
		Gui.iconImage(card, DRILL_ICON[d.id] or "IconStar", 54, Gui.CHALK, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18) })
		Gui.label(card, { Text = d.title, display = true, weight = Enum.FontWeight.Heavy, TextSize = 44, Position = UDim2.fromOffset(20, 34), Size = UDim2.new(1, -90, 0, 52) })
		Gui.label(card, { Text = d.inARow and string.format("%d in a row", d.goal) or string.format("%d to finish", d.goal), display = true, TextSize = 20, TextColor3 = Gui.SIGNAL, Position = UDim2.fromOffset(22, 88), Size = UDim2.new(1, -40, 0, 24) })
		Gui.label(card, { Text = d.blurb, TextSize = 18, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(22, 124), Size = UDim2.new(1, -44, 0, 76) })
		local how = Gui.label(card, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(22, 210), Size = UDim2.new(1, -44, 0, 110) })
		local go = actionPlate(card, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -18), Size = UDim2.new(1, -32, 0, 52) }, "Start", 24)
		onClick(go, function()
			sendLobby("practice", d.id)
		end)
		cards[d.id] = { how = how }
	end
	-- the tutorial: the four drills in order, paid once
	local tut = Gui.card(p, { Position = UDim2.fromOffset(M, 660), Size = UDim2.fromOffset(4 * w + 3 * gap, 150) })
	Gui.label(tut, { Text = "Tutorial", display = true, weight = Enum.FontWeight.Heavy, TextSize = 38, Position = UDim2.fromOffset(22, 16), Size = UDim2.fromOffset(400, 46) })
	local tutLine = Gui.label(tut, { Text = "", TextSize = 18, TextColor3 = Gui.DIM, RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(24, 66), Size = UDim2.new(1, -340, 0, 60) })
	local tutGo, tutGoLabel = actionPlate(tut, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 0), Size = UDim2.fromOffset(280, 58) }, "Start tutorial", 24)
	onClick(tutGo, function()
		Extra.openHowTo(Extra.mustTutorial())
	end)
	ui.practice = { cards = cards, tutLine = tutLine, tutGoLabel = tutGoLabel }
end

local function refreshPractice(prof)
	local pr = ui.practice
	for _, d in ipairs(Tutorial.Drills) do
		pr.cards[d.id].how.Text = drillHow(d)
	end
	local tut = prof.tutorial or { steps = {} }
	local vp, gold, spins = Tutorial.reward()
	local _, n, total = Tutorial.progress(tut.steps)
	if tut.done then
		pr.tutLine.Text = "All four drills in order. You've finished it: run it again any time."
		pr.tutGoLabel.Text = "Replay tutorial"
	else
		pr.tutLine.Text = string.format('All four drills in order%s. Reward: <font color="#FFD35A"><b>%d VP, %s Gold and %d free recruits</b></font>', n > 0 and string.format(" (%d of %d done)", n, total) or "", vp, Gui.num(gold), spins)
		pr.tutGoLabel.Text = n > 0 and "Continue tutorial" or "Start tutorial"
	end
end

local function buildRanks()
	local p = page("ranks")
	mainChrome(p, "ranks")
	-- the boards down the left, as hairline cards (the one shown edged in gold with a bar)
	local list = make("Frame", { Name = "Boards", Position = UDim2.fromOffset(M, 150), Size = UDim2.fromOffset(310, 7 * 64 + 6 * 8), BackgroundTransparency = 1 }, p)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local tabs = {}
	for i, b in ipairs(Leaderboards.Boards) do
		local t = Gui.cardButton(list, { Name = b.Key, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = i })
		local bar = Gui.plate(t, { Position = UDim2.fromOffset(-2, 0), Size = UDim2.fromOffset(12, 64) }, Gui.SIGNAL, { flatLeft = true })
		Gui.label(t, { Text = b.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, Size = UDim2.new(1, -40, 0, 28), Position = UDim2.fromOffset(24, 7) })
		local mine = Gui.label(t, { Text = "", TextSize = 15, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(26, 36) })
		onClick(t, function()
			boardKey = b.Key
			MenuController.refresh()
		end)
		tabs[b.Key] = { button = t, bar = bar, stroke = t:FindFirstChildWhichIsA("UIStroke"), mine = mine }
	end
	-- the board itself
	local panel = make("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -M, 0, 150),
		Size = UDim2.new(1, -M * 2 - 340, 1, -150 - M),
		BackgroundColor3 = Gui.CARD,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, p)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
	make("UIStroke", { Color = Gui.HAIRLINE, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	local title = Gui.label(panel, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 46, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -400, 0, 52), Position = UDim2.fromOffset(22, 10) })
	Gui.plate(panel, { Size = UDim2.fromOffset(84, 6), Position = UDim2.fromOffset(24, 64) }, Gui.SIGNAL)
	-- the place that shows over your head in the matchup intro (the owner: "allow players to pick
	-- what stat shows up on the entrance instead of picking the highest")
	local entrance, entranceL = hairButton(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 18), Size = UDim2.fromOffset(350, 44) }, "", 17)
	onClick(entrance, function()
		local cur = profile().equip and profile().equip.Entrance
		sendProfile("entrance", cur ~= boardKey and boardKey or nil)
	end)
	local scope = Gui.label(panel, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.new(1, -40, 0, 18), Position = UDim2.fromOffset(24, 78) })
	local rowsFrame = make("ScrollingFrame", { Position = UDim2.fromOffset(12, 106), Size = UDim2.new(1, -24, 1, -170), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, rowsFrame)
	local rows = {}
	for i = 1, Config.Leaderboards.Top do
		local r = make("Frame", { Size = UDim2.new(1, -10, 0, 58), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.96, BorderSizePixel = 0, LayoutOrder = i, Visible = false }, rowsFrame)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, r)
		local rank = Gui.label(r, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, Size = UDim2.fromOffset(64, 58), Position = UDim2.fromOffset(4, 0), TextXAlignment = Enum.TextXAlignment.Center })
		local shot = make("ImageLabel", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(74, 7), BackgroundColor3 = Gui.NAVY_LIGHT, BorderSizePixel = 0 }, r)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, shot)
		local name = Gui.label(r, { Text = "", display = true, TextSize = 24, Size = UDim2.new(1, -300, 1, 0), Position = UDim2.fromOffset(132, 0), TextTruncate = Enum.TextTruncate.AtEnd })
		local value = Gui.label(r, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 26, Size = UDim2.fromOffset(170, 58), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 0), TextXAlignment = Enum.TextXAlignment.Right })
		local rowEntry = { frame = r, rank = rank, shot = shot, name = name, value = value, userId = nil }
		-- a row opens that player's profile
		local open = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = r.ZIndex + 2 }, r)
		onClick(open, function()
			if rowEntry.userId then
				MenuController.openPlayerProfile(rowEntry.userId)
			end
		end)
		rows[i] = rowEntry
	end
	local empty = Gui.label(panel, { Text = "No scores yet. Win matches to get on the board.", TextSize = 18, TextColor3 = Gui.DIM, Size = UDim2.new(1, -40, 0, 30), Position = UDim2.fromOffset(20, 130), TextXAlignment = Enum.TextXAlignment.Center })
	local you = Gui.label(panel, { Text = "", display = true, TextSize = 22, TextColor3 = Gui.SIGNAL_HOT, RichText = true, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.new(0, 22, 1, -54) })
	ui.ranks = { tabs = tabs, title = title, scope = scope, rows = rows, empty = empty, you = you, entranceL = entranceL }
end

local function refreshRanks(prof)
	local R = ui.ranks
	askBoards(false)
	local mineValues = Leaderboards.valuesOf(prof)
	local unit = "wins"
	local emptyText = "No scores yet. Win matches to get on the board."
	for _, b in ipairs(Leaderboards.Boards) do
		local tab = R.tabs[b.Key]
		local on = b.Key == boardKey
		tab.bar.Visible = on
		if tab.stroke then
			tab.stroke.Color = on and Gui.SIGNAL or Gui.HAIRLINE
		end
		local mineV = mineValues[b.Key] or 0
		tab.mine.Text = (b.WinRate and mineV == 0) and string.format("You: %d matches to go", math.max(0, (b.MinMatches or 0) - ((prof.record and prof.record.matches) or 0))) or ("You: " .. Leaderboards.format(b.Key, mineV))
		if on then
			R.title.Text = b.Name
			unit = b.Unit
			emptyText = b.Empty or emptyText
		end
	end
	local rows = boardData and boardData.boards and boardData.boards[boardKey] or {}
	if boardData then
		local mins = math.floor((boardData.refresh or 120) / 60)
		R.scope.Text = boardData.global and string.format("Every server. The top %d, refreshed every %d minutes.", Config.Leaderboards.Top, mins) or "This server only (the global boards need DataStore access)."
	else
		R.scope.Text = "Loading..."
	end
	local myRank = nil
	local isRate = Leaderboards.board(boardKey) ~= nil and Leaderboards.board(boardKey).WinRate == true
	local cur = prof.equip and prof.equip.Entrance
	R.entranceL.Text = cur == boardKey and "At your entrance (tap: your best place)" or "Show this place at my entrance"
	R.entranceL.TextColor3 = cur == boardKey and Gui.SIGNAL or Gui.CHALK
	for i, row in ipairs(R.rows) do
		local d = rows[i]
		row.frame.Visible = d ~= nil
		if d then
			row.rank.Text = tostring(d.rank)
			row.rank.TextColor3 = MEDAL[d.rank] or Gui.CHALK
			row.name.Text = d.name or "Player"
			-- the W/L ratio board shows the share won, the wins and the losses
			row.value.Size = UDim2.fromOffset(isRate and 330 or 170, 58)
			row.name.Size = UDim2.new(1, isRate and -470 or -300, 1, 0)
			row.value.Text = Leaderboards.format(boardKey, d.value)
			if row.userId ~= d.userId then
				row.userId = d.userId
				row.shot.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(d.userId) .. "&w=48&h=48"
			end
			local me = d.userId == player.UserId
			row.frame.BackgroundColor3 = me and Gui.SIGNAL or Color3.new(1, 1, 1)
			row.frame.BackgroundTransparency = me and 0.8 or (d.rank <= 3 and 0.92 or 0.96)
			if me then
				myRank = d.rank
			end
		end
	end
	R.empty.Visible = boardData ~= nil and #rows == 0
	R.empty.Text = emptyText
	local mine = mineValues[boardKey] or 0
	if myRank then
		R.you.Text = string.format("You: <b>#%d</b> with %s", myRank, Leaderboards.format(boardKey, mine))
	elseif mine > 0 then
		R.you.Text = string.format("You: %s (not in the top %d yet)", Leaderboards.format(boardKey, mine), Config.Leaderboards.Top)
	elseif isRate then
		R.you.Text = string.format("You're on this board after %d matches.", Leaderboards.board(boardKey).MinMatches or 0)
	else
		R.you.Text = "You're not on this board yet."
	end
end

-- A player's profile (the owner: "add player profiles that display all that, but also your stats
-- and your leaderboard standings as well. these stats are spikes blocks, etc"): the card they wear,
-- their record (matches, wins, losses and the share won, spike kills, aces, blocks, MVPs, streaks)
-- and their place on every board. Yours from Home's headshot; anyone's from a leaderboard row. The
-- server answers ("profileOf", userId) on the PlayerProfile remote.
Extra.profileStats = {
	{ "matches", "Matches" }, { "wins", "Wins" }, { "losses", "Losses" }, { "winPct", "Win %" }, { "kills", "Spike kills" },
	{ "aces", "Aces" }, { "blocks", "Blocks" }, { "mvps", "MVPs" }, { "bestStreak", "Best streak" }, { "winStreak", "Win streak" },
}

function Extra.buildPlayerProfile()
	local m = modal("PlayerProfile", "Player profile", 1040, 720, true)
	local card = Gui.playerCard(m.panel, { Position = UDim2.fromOffset(40, 112), ZIndex = 22 })
	make("UIScale", { Scale = 1.2 }, card.root)
	local status = Gui.label(m.panel, { Text = "", TextSize = 18, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(640, 120), Size = UDim2.fromOffset(360, 60), TextWrapped = true, ZIndex = 22 })
	local extra = Gui.label(m.panel, { Text = "", TextSize = 17, TextColor3 = Gui.CHALK, RichText = true, TextWrapped = true, Position = UDim2.fromOffset(640, 120), Size = UDim2.fromOffset(360, 110), ZIndex = 22 })
	-- the record: two rows of five
	local tiles = {}
	for i, def in ipairs(Extra.profileStats) do
		local col = (i - 1) % 5
		local row = math.floor((i - 1) / 5)
		local t = make("Frame", { Position = UDim2.fromOffset(28 + col * 198, 262 + row * 98), Size = UDim2.fromOffset(186, 88), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0, ZIndex = 21 }, m.panel)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, t)
		local v = Gui.label(t, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 36, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 44), ZIndex = 22 })
		Gui.label(t, { Text = def[2], TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(14, 54), Size = UDim2.new(1, -28, 0, 20), ZIndex = 22 })
		tiles[def[1]] = v
	end
	-- the leaderboards: two columns
	Gui.label(m.panel, { Text = "Leaderboards", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, Position = UDim2.fromOffset(28, 468), Size = UDim2.fromOffset(400, 32), ZIndex = 21 })
	Gui.plate(m.panel, { Size = UDim2.fromOffset(46, 5), Position = UDim2.fromOffset(30, 502), ZIndex = 21 }, Gui.SIGNAL)
	local places = {}
	for i, b in ipairs(Leaderboards.Boards) do
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local r = make("Frame", { Position = UDim2.fromOffset(28 + col * 496, 516 + row * 44), Size = UDim2.fromOffset(484, 38), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.96, BorderSizePixel = 0, ZIndex = 21 }, m.panel)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, r)
		Gui.label(r, { Text = b.Name, display = true, TextSize = 18, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 1, 0), ZIndex = 22 })
		places[b.Key] = Gui.label(r, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(170, 38), ZIndex = 22 })
	end
	ui.playerProfile = { modal = m, card = card, status = status, extra = extra, tiles = tiles, places = places }
	Net.get("PlayerProfile").OnClientEvent:Connect(function(data)
		if type(data) == "table" and data.userId == Extra.viewingProfile then
			Extra.fillPlayerProfile(data)
		end
	end)
end

function Extra.fillPlayerProfile(data)
	local PP = ui.playerProfile
	if data.missing then
		PP.status.Text = "No profile to show: they haven't played yet."
		PP.status.Visible = true
		PP.extra.Visible = false
		return
	end
	PP.status.Visible = false
	PP.extra.Visible = true
	local C = Extra.Cards
	local def = C.get(data.card and data.card.key) or C.get(C.default())
	local stats = { rank = data.card and data.card.rank }
	local look = C.look(def, Config.Teams.Home.Color, stats.rank)
	local c = Roster.get(data.char or "")
	local tier = c and c.Tier or ""
	if look.Avatar then
		local other = Players:GetPlayerByUserId(data.userId)
		mods.AnimationController.portrait(PP.card.viewport, other and other.Character, mods.AnimationController.spikePose(other and other.Character))
	end
	PP.card.set(look, {
		userId = data.userId,
		name = data.name or "Player",
		tier = tier,
		tierColor = tierColor(tier),
		line = c and (c.Name .. "  /  " .. roleName(c.Role)) or "",
		value = data.card and data.card.value or "",
		label = data.card and data.card.label or "",
		title = def.Key ~= C.default() and string.upper(def.Name) or nil,
	})
	local rec = data.record or {}
	for key, v in pairs(PP.tiles) do
		if key == "winPct" then
			v.Text = (rec.matches or 0) > 0 and string.format("%.1f%%", rec.winPct or 0) or "-"
		else
			v.Text = Gui.num(rec[key] or 0)
		end
	end
	for key, l in pairs(PP.places) do
		local rank = data.places and data.places[key]
		l.Text = rank and ("#" .. rank) or ("Not in the top " .. Config.Leaderboards.Top)
		l.TextColor3 = rank and (MEDAL[rank] or Gui.CHALK) or Gui.DIM
	end
	PP.extra.Text = string.format("<b>%s</b>\nPlaying %s\n%d of %d characters recruited, %d player cards", data.name or "Player",
		c and (c.Name .. " (" .. c.Tier .. ")") or "nobody yet", data.owned or 0, #Roster, data.cards or 0)
end

-- Open a profile: yours, or anyone's by user id (the server sends it).
function MenuController.openPlayerProfile(userId)
	local PP = ui.playerProfile
	if not PP or not userId then
		return
	end
	Extra.viewingProfile = userId
	PP.status.Text = "Loading..."
	PP.status.Visible = true
	PP.extra.Visible = false
	PP.modal.root.Visible = true
	Net.get("Profile"):FireServer("profileOf", userId)
end

------------------------------------------------------------------------------------------
-- Codes, the daily reward, gifts and the admin panel
------------------------------------------------------------------------------------------

Extra.groupName = nil -- the group's name, looked up once ("" while it's being asked)

function Extra.lookUpGroup()
	local gid = profile().group or 0
	if gid == 0 or Extra.groupName ~= nil then
		return
	end
	Extra.groupName = ""
	task.spawn(function()
		local ok, info = pcall(function()
			return GroupService:GetGroupInfoAsync(gid)
		end)
		if ok and type(info) == "table" and type(info.Name) == "string" then
			Extra.groupName = info.Name
			MenuController.refresh()
		end
	end)
end

function Extra.groupText()
	return (Extra.groupName and Extra.groupName ~= "") and Extra.groupName or "our group"
end

-- Roblox's own join prompt for the group; the server checks again afterwards either way.
function Extra.joinGroup()
	local gid = profile().group or 0
	if gid == 0 then
		toast("There's no group to join yet.")
		return
	end
	task.spawn(function()
		local ok = pcall(function()
			GroupService:PromptJoinAsync(gid)
		end)
		if not ok then
			toast("Find " .. Extra.groupText() .. " on Roblox and join it.")
		end
		Net.get("Profile"):FireServer("group")
	end)
end

-- The favorite (the owner: "it doesn't check if you actually liked the game... have a like the
-- game popup and actually check"). Roblox never tells a game who liked it (and doesn't allow
-- trying), so the check is the favorite: Roblox's own prompt, whose result says whether they
-- favorited it (sent to the server, which keeps it). GetFavoriteAsync can check again, but only
-- once a player has allowed inventory access, which isn't asked for; without it, it quietly fails.
-- The window asks for a like too.
Extra.AES = game:GetService("AvatarEditorService")
function Extra.checkFavorite()
	task.spawn(function()
		local ok, fav = pcall(function()
			return Extra.AES:GetFavoriteAsync(game.PlaceId, Enum.AvatarItemType.Asset)
		end)
		if ok then
			Net.get("Profile"):FireServer("favorited", fav == true)
		end
	end)
end
function Extra.promptFavorite()
	if not Extra.favHooked then
		Extra.favHooked = true
		-- Roblox's prompt says whether it went through
		Extra.AES.PromptSetFavoriteCompleted:Connect(function(result)
			if result == Enum.AvatarPromptResult.Success then
				Net.get("Profile"):FireServer("favorited", true)
				toast("Thanks for the favorite! Give it a like too.")
			else
				Extra.checkFavorite()
			end
		end)
	end
	local ok = pcall(function()
		Extra.AES:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	if not ok then
		toast("Favorite Spike Rush on its Roblox page (the star), and give it a like!")
	end
end
-- Codes or Daily opened: check the favorite, and the first time a player who hasn't favorited
-- opens one this session, Roblox's favorite prompt pops up by itself
function Extra.onRequirementsOpen(prof)
	Extra.checkFavorite()
	if not prof.favorited and not Extra.favPrompted then
		Extra.favPrompted = true
		Extra.promptFavorite()
	end
end

-- The owner's rule for codes and daily rewards: in the group, and they've favorited the game. Two
-- rows that tick off: Join (Roblox's prompt; the server checks) and Favorite (Roblox's prompt;
-- Roblox says whether they have).
function Extra.requirements(parent, y)
	local f = make("Frame", { Position = UDim2.fromOffset(26, y), Size = UDim2.new(1, -52, 0, 104), BackgroundTransparency = 1, ZIndex = 21 }, parent)
	local rows = {}
	for i, def in ipairs({ { "group", "Join" }, { "like", "Favorite" } }) do
		local r = make("Frame", { Position = UDim2.fromOffset(0, (i - 1) * 56), Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0, ZIndex = 21 }, f)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, r)
		Gui.label(r, { Text = tostring(i), display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextColor3 = Gui.SIGNAL, Size = UDim2.fromOffset(36, 48), Position = UDim2.fromOffset(6, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
		local t = Gui.label(r, { Text = "", TextSize = 17, weight = Enum.FontWeight.Medium, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -220, 1, 0), Position = UDim2.fromOffset(46, 0), ZIndex = 22 })
		local b = hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(150, 38), ZIndex = 22 }, def[2], 18)
		local done = Gui.label(r, { Text = "Done", display = true, TextSize = 20, TextColor3 = Color3.fromRGB(110, 230, 150), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.fromOffset(120, 48), TextXAlignment = Enum.TextXAlignment.Right, Visible = false, ZIndex = 22 })
		rows[def[1]] = { text = t, button = b, done = done }
	end
	onClick(rows.group.button, Extra.joinGroup)
	onClick(rows.like.button, Extra.promptFavorite)
	return rows
end

-- Both met, as far as this client knows (the server asks Roblox about the group again).
function Extra.meetsRequirements(prof)
	return prof.member ~= false and prof.favorited == true
end

function Extra.refreshRequirements(rows, prof)
	Extra.lookUpGroup()
	local member = prof.member == true
	rows.group.text.Text = member and ("You're in " .. Extra.groupText()) or ("Join " .. Extra.groupText() .. " on Roblox")
	rows.group.button.Visible = not member
	rows.group.done.Visible = member
	rows.like.text.Text = prof.favorited and "You favorited the game. Thanks!" or "Favorite the game (and give it a like!)"
	rows.like.button.Visible = not prof.favorited
	rows.like.done.Visible = prof.favorited == true
end

-- Codes (the owner: "add a codes system"): a box and Redeem, under the requirements.
function Extra.buildCodes()
	local m = modal("Codes", "Codes", 660, 336, true)
	Gui.label(m.panel, { Text = "Codes are for members of the group who favorited the game. Each works once.", TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(28, 84), Size = UDim2.new(1, -56, 0, 20), ZIndex = 21 })
	local req = Extra.requirements(m.panel, 116)
	local box = Extra.inputBox(m.panel, { Position = UDim2.fromOffset(26, 246), Size = UDim2.new(1, -52 - 190, 0, 54), TextSize = 22 }, "Enter a code")
	local go, goPlate = Gui.plateButton(m.panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -26, 0, 246), Size = UDim2.fromOffset(176, 54), ZIndex = 22 }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	go:SetAttribute("Sound", "UIConfirm")
	Gui.label(go, { Text = "Redeem", display = true, TextSize = 24, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	local function redeem()
		if string.match(box.Text, "%w") then
			Net.get("Profile"):FireServer("code", box.Text)
		end
	end
	onClick(go, redeem)
	box.FocusLost:Connect(function(enter)
		if enter then
			redeem()
		end
	end)
	ui.codes = { modal = m, req = req, box = box, goPlate = goPlate }
end

function Extra.refreshCodes(prof)
	local C = ui.codes
	Extra.refreshRequirements(C.req, prof)
	Gui.fade(C.goPlate, Extra.meetsRequirements(prof) and 0 or 0.45)
end

-- A daily reward's lines for its card: "+150 VP" over "1 lucky spin".
function Extra.rewardLines(g)
	local lines = {}
	if g.VP > 0 then
		table.insert(lines, "+" .. Gui.num(g.VP) .. " VP")
	end
	if g.Gold > 0 then
		table.insert(lines, "+" .. Gui.num(g.Gold) .. " Gold")
	end
	if g.Lucky > 0 then
		table.insert(lines, g.Lucky == 1 and "1 lucky spin" or (g.Lucky .. " lucky spins"))
	end
	return table.concat(lines, "\n")
end

-- The daily reward (the owner: "daily rewards for group members only"): the requirements, the
-- week's seven days (claimed, today, next) and Claim.
function Extra.buildDaily()
	local m = modal("Daily", "Daily rewards", 960, 560, true)
	Gui.label(m.panel, { Text = "One a day for members of the group who favorited the game. Miss a day and the week starts over.", TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(28, 84), Size = UDim2.new(1, -56, 0, 20), ZIndex = 21 })
	local req = Extra.requirements(m.panel, 116)
	local week = make("Frame", { Position = UDim2.fromOffset(26, 236), Size = UDim2.new(1, -52, 0, 150), BackgroundTransparency = 1, ZIndex = 21 }, m.panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, week)
	local cards = {}
	local n = #Config.Daily.Rewards
	for i, r in ipairs(Config.Daily.Rewards) do
		local c = make("Frame", { Size = UDim2.new(1 / n, -10 * (n - 1) / n, 1, 0), BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.1, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 21 }, week)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, c)
		local st = make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, c)
		Gui.label(c, { Text = "Day " .. i, display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 10), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
		Gui.label(c, { Text = Extra.rewardLines(Economy.cleanGrant(r)), TextSize = 16, weight = Enum.FontWeight.Medium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -12, 0, 64), Position = UDim2.fromOffset(6, 48), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
		local state = Gui.label(c, { Text = "", display = true, TextSize = 17, TextColor3 = Gui.DIM, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -8), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
		cards[i] = { frame = c, stroke = st, state = state }
	end
	local when = Gui.label(m.panel, { Text = "", TextSize = 17, TextColor3 = Gui.SIGNAL_HOT, Position = UDim2.fromOffset(28, 398), Size = UDim2.new(1, -56, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21 })
	local claim, claimPlate = Gui.plateButton(m.panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(340, 64), ZIndex = 22 }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	claim:SetAttribute("Sound", "UIConfirm")
	local claimL = Gui.label(claim, { Text = "Claim", display = true, TextSize = 26, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	onClick(claim, function()
		Net.get("Profile"):FireServer("daily")
	end)
	ui.daily = { modal = m, req = req, cards = cards, when = when, claimPlate = claimPlate, claimL = claimL }
end

function Extra.refreshDaily(prof)
	local Dy = ui.daily
	Extra.refreshRequirements(Dy.req, prof)
	local d = prof.daily or {}
	local day = d.day or 1
	local left = math.max(0, (d.opensIn or 0) - (os.clock() - Extra.profileAt))
	-- a countdown that ran out since the last profile opens it (the server has the last word)
	local ready = d.ready == true or left <= 0
	for i, c in ipairs(Dy.cards) do
		local claimed = i < day and not d.lapsed
		local today = i == day
		c.state.Text = claimed and "Claimed" or (today and (ready and "Today" or "Next") or "")
		c.state.TextColor3 = today and Gui.SIGNAL or Gui.DIM
		c.stroke.Color = today and Gui.SIGNAL or Gui.HAIRLINE
		c.stroke.Thickness = today and 2 or 1
		c.stroke.Transparency = today and 0 or 0.5
		c.frame.BackgroundTransparency = claimed and 0.5 or 0.1
	end
	Dy.claimL.Text = ready and ("Claim day " .. day) or ("Back in " .. Extra.waitText(left))
	Gui.fade(Dy.claimPlate, (ready and Extra.meetsRequirements(prof)) and 0 or 0.45)
	if d.lapsed then
		Dy.when.Text = "You missed a day, so the week starts over."
	elseif ready then
		Dy.when.Text = ""
	else
		Dy.when.Text = "Your next reward opens in " .. Extra.waitText(left) .. "."
	end
end

-- Gifting (the owner: "add a gifting system"): a pack for someone else, by username or picked from
-- the players here. The server looks them up and opens the purchase.
Extra.giftPick = { kind = "VP", index = 1 }

function Extra.buildGift()
	local m = modal("Gift", "Send a gift", 660, 560, true)
	local what = Gui.label(m.panel, { Text = "", display = true, TextSize = 26, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(28, 86), Size = UDim2.new(1, -56, 0, 30), ZIndex = 21 })
	Gui.label(m.panel, { Text = "Who is it for? Their Roblox username, or someone here.", TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(28, 124), Size = UDim2.new(1, -56, 0, 20), ZIndex = 21 })
	local box = Extra.inputBox(m.panel, { Position = UDim2.fromOffset(26, 152), Size = UDim2.new(1, -52, 0, 52), TextSize = 22 }, "Username")
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(26, 216), Size = UDim2.new(1, -52, 0, 214), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 21 }, m.panel)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(192, 44), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local nobody = Gui.label(m.panel, { Text = "Nobody else is in this server: type their username.", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(28, 222), Size = UDim2.new(1, -56, 0, 20), Visible = false, ZIndex = 21 })
	local send = Gui.plateButton(m.panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -26), Size = UDim2.fromOffset(360, 62), ZIndex = 22 }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	send:SetAttribute("Sound", "UIConfirm")
	local sendL = Gui.label(send, { Text = "Buy as a gift", display = true, TextSize = 25, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
	onClick(send, function()
		local name = string.match(box.Text, "^%s*([%w_]+)%s*$")
		if not name then
			toast("Type their username first.")
			return
		end
		Net.get("Profile"):FireServer("gift", Extra.giftPick.kind, Extra.giftPick.index, name)
		m.hide()
	end)
	ui.gift = { modal = m, what = what, box = box, list = list, nobody = nobody, sendL = sendL }
end

-- Opens the gift window for a pack: kind "VP", "Gold" or "Lucky", and its index.
function MenuController.openGift(kind, index)
	local entry = Economy.pack(kind, index)
	if not entry then
		return
	end
	Extra.giftPick.kind, Extra.giftPick.index = kind, index
	local G = ui.gift
	G.what.Text = string.format("%s: %s", entry.pack.Name, Economy.describe(Economy.packGrant(entry)))
	local price = packPrices[kind] and packPrices[kind][index]
	if entry.id == 0 then
		G.sendL.Text = profile().studio and "Send (free in Studio)" or "Soon"
	else
		G.sendL.Text = price and string.format("Buy as a gift   R$ %d", price) or "Buy as a gift"
	end
	G.box.Text = ""
	for _, c in ipairs(G.list:GetChildren()) do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local others = 0
	for i, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			others = others + 1
			local b = hairButton(G.list, { LayoutOrder = i, ZIndex = 22 }, plr.DisplayName, 18)
			onClick(b, function()
				G.box.Text = plr.Name
			end)
		end
	end
	G.nobody.Visible = others == 0
	G.modal.root.Visible = true
end

-- The admin panel (developers): the events' length, 2x VP and 2x Gold, the announcement, and a
-- player's gift. AdminService answers every request with a line and the running events.
Extra.adminMinutes = Config.Admin.Durations[1]
Extra.adminChars = {} -- the characters picked to give

function Extra.buildAdmin()
	local m = modal("Admin", "Admin panel", 1080, 780, true)
	local function heading(parent, t, y)
		Gui.label(parent, { Text = t, display = true, weight = Enum.FontWeight.Heavy, TextSize = 26, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 30), ZIndex = 22 })
		Gui.plate(parent, { Size = UDim2.fromOffset(46, 5), Position = UDim2.fromOffset(2, y + 32), ZIndex = 22 }, Gui.SIGNAL)
	end
	-- left: the events in every server, then the announcement
	local left = make("Frame", { Position = UDim2.fromOffset(28, 92), Size = UDim2.fromOffset(480, 600), BackgroundTransparency = 1, ZIndex = 21 }, m.panel)
	heading(left, "Events in every server", 0)
	local items = {}
	for _, mins in ipairs(Config.Admin.Durations) do
		table.insert(items, { key = mins, text = mins .. " min" })
	end
	local _, setLen = segmented(left, items, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 46), ZIndex = 22 }, function(key)
		Extra.adminMinutes = key
		MenuController.refresh()
	end)
	local evRows = {}
	for i, kind in ipairs(Config.Admin.Events) do
		local r = make("Frame", { Position = UDim2.fromOffset(0, 106 + (i - 1) * 64), Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0, ZIndex = 22 }, left)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, r)
		Gui.label(r, { Text = Config.Admin.Multiplier .. "x " .. kind, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(100, 56), ZIndex = 23 })
		local status = Gui.label(r, { Text = "", TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(112, 0), Size = UDim2.fromOffset(160, 56), ZIndex = 23 })
		local start, startL = hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0), Size = UDim2.fromOffset(108, 40), ZIndex = 23 }, "Start", 18)
		local stop = hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(80, 40), ZIndex = 23 }, "Stop", 18)
		onClick(start, function()
			Net.get("Admin"):FireServer("event", kind, Extra.adminMinutes)
		end)
		onClick(stop, function()
			Net.get("Admin"):FireServer("stop", kind)
		end)
		evRows[kind] = { status = status, startL = startL, stop = stop }
	end
	heading(left, "Announcement", 314)
	local ann = Extra.inputBox(left, { Position = UDim2.fromOffset(0, 360), Size = UDim2.new(1, 0, 0, 112), TextWrapped = true, MultiLine = true, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 18 }, "Shown to every player in every server")
	local annCount = Gui.label(left, { Text = "0 / " .. Config.Admin.AnnounceMax, TextSize = 14, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(0, 482), Size = UDim2.fromOffset(200, 18), ZIndex = 22 })
	ann:GetPropertyChangedSignal("Text"):Connect(function()
		if #ann.Text > Config.Admin.AnnounceMax then
			ann.Text = string.sub(ann.Text, 1, Config.Admin.AnnounceMax)
		end
		annCount.Text = #ann.Text .. " / " .. Config.Admin.AnnounceMax
	end)
	local send = actionPlate(left, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 480), Size = UDim2.fromOffset(240, 48) }, "Send to everyone", 20)
	onClick(send, function()
		if string.match(ann.Text, "%S") then
			Net.get("Admin"):FireServer("announce", ann.Text)
		end
	end)
	-- right: give a player VP, Gold, lucky spins and characters
	local right = make("Frame", { Position = UDim2.fromOffset(544, 92), Size = UDim2.fromOffset(508, 600), BackgroundTransparency = 1, ZIndex = 21 }, m.panel)
	heading(right, "Give a player", 0)
	local user = Extra.inputBox(right, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 46) }, "Username")
	local amounts = {}
	for i, def in ipairs({ { "VP", "VP" }, { "Gold", "Gold" }, { "Lucky", "Lucky spins" } }) do
		local x = (i - 1) * 172
		Gui.label(right, { Text = def[2], TextSize = 14, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(x, 104), Size = UDim2.fromOffset(160, 16), ZIndex = 22 })
		amounts[def[1]] = Extra.inputBox(right, { Position = UDim2.fromOffset(x, 122), Size = UDim2.fromOffset(164, 44) }, "0")
	end
	Gui.label(right, { Text = "Characters (click to pick)", TextSize = 14, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(0, 178), Size = UDim2.fromOffset(300, 16), ZIndex = 22 })
	-- player cards that are only given: the Content Creator card
	local creatorBtn, creatorL = hairButton(right, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 168), Size = UDim2.fromOffset(250, 28), ZIndex = 23 }, "", 15)
	onClick(creatorBtn, function()
		Extra.adminCreator = not Extra.adminCreator
		MenuController.refresh()
	end)
	local grid = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 198), Size = UDim2.new(1, 0, 0, 300), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, right)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(158, 36), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	-- best first: S+ down to D-
	local order = {}
	for _, c in ipairs(Roster) do
		table.insert(order, c)
	end
	local rank = {}
	for i, t in ipairs(Config.Tiers) do
		rank[t] = i
	end
	table.sort(order, function(x, y)
		if x.Tier ~= y.Tier then
			return (rank[x.Tier] or 0) > (rank[y.Tier] or 0)
		end
		return x.Name < y.Name
	end)
	local charButtons = {}
	for i, c in ipairs(order) do
		local color = tierColor(c.Tier)
		local b = make("TextButton", { Text = c.Name .. "  " .. c.Tier, FontFace = Gui.display(), TextSize = 17, TextColor3 = color, BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.2, AutoButtonColor = false, LayoutOrder = i, ZIndex = 23 }, grid)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		make("UIStroke", { Color = color, Thickness = 1, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		b:SetAttribute("Sound", "UISelect")
		onClick(b, function()
			Extra.adminChars[c.Id] = not Extra.adminChars[c.Id] or nil
			MenuController.refresh()
		end)
		charButtons[c.Id] = { button = b, color = color }
	end
	local picked = Gui.label(right, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(0, 512), Size = UDim2.new(1, -220, 0, 48), ZIndex = 22 })
	local give = actionPlate(right, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 512), Size = UDim2.fromOffset(200, 48) }, "Give", 22)
	onClick(give, function()
		local chars = {}
		for id in pairs(Extra.adminChars) do
			table.insert(chars, id)
		end
		Net.get("Admin"):FireServer("give", user.Text, {
			VP = tonumber(amounts.VP.Text) or 0,
			Gold = tonumber(amounts.Gold.Text) or 0,
			Lucky = tonumber(amounts.Lucky.Text) or 0,
			Chars = chars,
			Cards = Extra.adminCreator and { "Creator" } or nil,
		})
	end)
	local status = Gui.label(m.panel, { Text = "", TextSize = 17, TextColor3 = Gui.SIGNAL_HOT, TextWrapped = true, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 28, 1, -20), Size = UDim2.new(1, -56, 0, 44), ZIndex = 21 })
	ui.admin = { modal = m, setLen = setLen, evRows = evRows, charButtons = charButtons, picked = picked, status = status, creatorL = creatorL }
end

function Extra.refreshAdmin()
	local A = ui.admin
	A.setLen(Extra.adminMinutes)
	A.creatorL.Text = Extra.adminCreator and "Content Creator card: yes" or "Content Creator card: no"
	A.creatorL.TextColor3 = Extra.adminCreator and Gui.SIGNAL or Gui.CHALK
	for kind, r in pairs(A.evRows) do
		local left = Extra.eventLeft(kind)
		r.status.Text = left > 0 and ("On, " .. Extra.clockText(left) .. " left") or "Off"
		r.status.TextColor3 = left > 0 and Gui.SIGNAL or Gui.DIM
		r.startL.Text = left > 0 and "Restart" or "Start"
		r.stop.Visible = left > 0
	end
	local n = 0
	for id, b in pairs(A.charButtons) do
		local on = Extra.adminChars[id] == true
		if on then
			n = n + 1
		end
		b.button.BackgroundColor3 = on and b.color or Gui.CARD
		b.button.BackgroundTransparency = on and 0.05 or 0.2
		b.button.TextColor3 = on and Gui.LINE or b.color
	end
	A.picked.Text = n > 0 and string.format("%d character%s picked", n, n == 1 and "" or "s") or ""
end

function MenuController.openAdmin()
	if not profile().admin then
		return
	end
	ui.admin.modal.root.Visible = true
	Net.get("Admin"):FireServer("state")
	MenuController.refresh()
end

------------------------------------------------------------------------------------------
-- Timeout: change your character or your look (the menus open over the match for it)
------------------------------------------------------------------------------------------

local swapMode = false
local swapKind = "Style"

local function buildSwap()
	local m = modal("Swap", "Timeout: character and look", 1040, 600, true)
	local P = m.panel
	Gui.label(P, { Text = "Your characters. You keep your spot and role on court.", TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.fromOffset(460, 20), Position = UDim2.fromOffset(28, 84), ZIndex = 21 })
	local chars = make("ScrollingFrame", { Position = UDim2.fromOffset(20, 112), Size = UDim2.fromOffset(490, 468), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 21 }, P)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(154, 84), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, chars)
	local cards = {}
	for i, c in ipairs(Roster) do
		local b = make("TextButton", { BackgroundColor3 = tierColor(c.Tier):Lerp(Color3.new(0, 0, 0), 0.6), BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = i, Visible = false, ZIndex = 21 }, chars)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		local s = make("UIStroke", { Color = tierColor(c.Tier), Thickness = 1.5, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local _, setBadge = Gui.tierBadge(b, 40, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), ZIndex = 22 })
		setBadge(c.Tier, tierColor(c.Tier), false)
		Gui.label(b, { Text = c.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, Size = UDim2.new(1, -60, 0, 26), Position = UDim2.fromOffset(10, 8), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 22 })
		local def = c.Ability and Config.Abilities[c.Ability]
		Gui.label(b, { Text = c.Role, display = true, TextSize = 16, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(10, 36), ZIndex = 22 })
		Gui.label(b, { Text = def and def.Name or "", TextSize = 13, TextColor3 = def and def.Color or Gui.DIM, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 58), ZIndex = 22 })
		onClick(b, function()
			Net.get("Profile"):FireServer("select", c.Id)
		end)
		cards[c.Id] = { button = b, stroke = s }
	end
	local kinds = {}
	for _, kind in ipairs(COS.Kinds) do
		table.insert(kinds, { key = kind, text = SP.Banners[kind].Name })
	end
	local _, setKind = segmented(P, kinds, { Size = UDim2.fromOffset(490, 44), Position = UDim2.fromOffset(528, 80), ZIndex = 21 }, function(key)
		swapKind = key
		MenuController.refresh()
	end)
	local looks = make("ScrollingFrame", { Position = UDim2.fromOffset(528, 136), Size = UDim2.fromOffset(490, 444), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 21 }, P)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(154, 62), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, looks)
	local chips = {}
	for _, kind in ipairs(COS.Kinds) do
		chips[kind] = {}
		for i, item in ipairs(COS[kind]) do
			local b = make("TextButton", { BackgroundColor3 = Color3.fromRGB(34, 36, 46), BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = i, Visible = false, ZIndex = 21 }, looks)
			make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
			local s = make("UIStroke", { Color = Spins.rarityColor(item.Rarity), Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
			Gui.label(b, { Text = item.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 19, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(10, 8), ZIndex = 22 })
			local tag = Gui.label(b, { Text = "", display = true, TextSize = 14, TextColor3 = Spins.rarityColor(item.Rarity), Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 36), ZIndex = 22 })
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
		card.stroke.Color = on and Gui.SIGNAL or tierColor(Roster.get(id).Tier)
		card.stroke.Transparency = on and 0 or 0.4
	end
	S.setKind(swapKind)
	for kind, list in pairs(S.chips) do
		local equipped = prof.equip and prof.equip[kind] or Spins.default(kind)
		for key, chip in pairs(list) do
			chip.button.Visible = kind == swapKind and owns(prof, kind, key)
			local on = key == equipped
			chip.stroke.Thickness = on and 3 or 2
			chip.stroke.Color = on and Color3.new(1, 1, 1) or Spins.rarityColor(chip.item.Rarity)
			chip.tag.Text = on and "EQUIPPED" or chip.item.Rarity
			chip.tag.TextColor3 = on and Gui.SIGNAL or Spins.rarityColor(chip.item.Rarity)
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

local SCENE = { home = "home", match = "home", practice = "home", players = "home", player = "home", shop = "home", ranks = "home", recruit = "gym", locker = "gym" }
local autoLine = ""

-- The Match screen blurs the room behind its cards.
local menuBlur = nil
local function setMenuBlur(on)
	if not menuBlur then
		if not on then
			return
		end
		menuBlur = Instance.new("BlurEffect")
		menuBlur.Name = "SpikeRushMenuBlur"
		menuBlur.Size = 0
		menuBlur.Parent = Lighting
	end
	tween(menuBlur, 0.25, { Size = on and 14 or 0 })
end

function MenuController.applyScene()
	if not shown or seqActive then
		return
	end
	setMenuBlur(screen == "match")
	local SC = mods.SceneController
	SC.show(SCENE[screen] or "home")
	if screen == "locker" then
		SC.shot("practice", 0.6)
		local o = lockerOpts(profile())
		o.posing = lockerKind == "Pose"
		SC.setPractice(o)
	else
		SC.setPractice(nil)
		if screen == "recruit" then
			SC.shot("recruit", 0.6)
		elseif screen == "players" or screen == "player" then
			SC.shot("roster", 0.6) -- your avatar in the left third, clear of the panel
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
	local changed = name ~= screen
	screen = name
	if name == "ranks" then
		askBoards(true)
	end
	for n, f in pairs(ui.pages) do
		f.Visible = n == name
	end
	MenuController.applyScene()
	MenuController.refresh()
	if changed and shown then
		if mods.AudioController then
			mods.AudioController.play("UIOpenLong", { minGap = 0.1, volume = 0.6 })
		end
		if name == "home" then
			-- the screen's one entrance: the Match plate slides back in
			local hm = ui.home
			hm.match.Position = hm.matchPos + UDim2.fromOffset(70, 0)
			tween(hm.match, 0.34, { Position = hm.matchPos }, Enum.EasingStyle.Quint)
		end
	end
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
	if screen == "home" then
		refreshHome(prof) -- go("home") refreshes, so other screens needn't keep Home current
	elseif screen == "recruit" then
		refreshRecruit(prof)
		ui.recruit.status.Text = prof.autoRolling and autoLine or ""
	elseif screen == "players" then
		refreshPlayers(prof)
	elseif screen == "player" then
		refreshPlayer(prof)
	elseif screen == "locker" then
		refreshLocker(prof)
	elseif screen == "shop" then
		refreshShop(prof)
	elseif screen == "ranks" then
		refreshRanks(prof)
	elseif screen == "practice" then
		refreshPractice(prof)
	elseif screen == "match" then
		refreshMatchScreen(prof)
	end
	refreshMatch()
	if swapMode then
		refreshSwap(prof)
	end
	if ui.codes.modal.root.Visible then
		Extra.refreshCodes(prof)
	end
	if ui.daily.modal.root.Visible then
		Extra.refreshDaily(prof)
	end
	if ui.admin.modal.root.Visible then
		Extra.refreshAdmin()
	end
	if shown and not Extra.howToShown and Extra.mustTutorial(prof) then
		Extra.howToShown = true
		Extra.openHowTo(true)
	elseif Extra.howToLocked and not Extra.mustTutorial(prof) then
		Extra.howToLocked = false -- the tutorial's done (or a match played): free to close
	end
	if ui.odds and ui.odds.kind and ui.odds.modal.root.Visible then
		MenuController.openTable(ui.odds.kind, ui.odds.lucky) -- Boost and Lower change the odds
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
		setMenuBlur(false)
		ui.match.modal.root.Visible = false
		ui.odds.modal.root.Visible = false
		ui.help.root.Visible = false
		ui.codes.modal.root.Visible = false
		ui.daily.modal.root.Visible = false
		ui.gift.modal.root.Visible = false
		ui.admin.modal.root.Visible = false
	end
end

function MenuController.shown()
	return shown
end

local function onProfile(prof)
	Extra.profileAt = os.clock()
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
	placeHome()
	placeHeaders()
end

function MenuController.init(m)
	mods = m
	Gui.play = function(key, opts)
		if mods.AudioController then
			mods.AudioController.play(key, opts)
		end
	end
	Gui.onHover = function()
		if mods.AudioController then
			mods.AudioController.play("UIHover", { minGap = 0.06, volume = 0.45 })
		end
	end
	gui = make("ScreenGui", {
		Name = "SpikeRushMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	canvas = make("Frame", { Name = "Canvas", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), BackgroundTransparency = 1 }, gui)
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
	buildPlayer()
	buildLocker()
	buildShop()
	buildRanks()
	buildPractice()
	buildHelp()
	buildTable()
	Extra.buildPityPick()
	Extra.buildHowTo()
	Extra.buildPlayerProfile()
	buildMatch()
	buildMatchScreen()
	buildSequence()
	buildSwap()
	Extra.buildCodes()
	Extra.buildDaily()
	Extra.buildGift()
	Extra.buildAdmin()

	-- the toast: a dark hairline card with a signal-yellow tab, under the nav
	local tf = make("Frame", { Name = "Toast", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 30, 0, 100), Size = UDim2.fromOffset(660, 50), BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.1, BorderSizePixel = 0, Visible = false, ZIndex = 40 }, canvas)
	local edge = make("UIStroke", { Color = Gui.HAIRLINE, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tf)
	local tab = make("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = Gui.SIGNAL, BorderSizePixel = 0, ZIndex = 41 }, tf)
	local tl = Gui.label(tf, { Text = "", display = true, TextSize = 21, TextWrapped = true, Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(24, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	ui.toast = { frame = tf, label = tl, edge = edge, tab = tab }

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
	-- Roblox's top bar can change size (and may still be settling on the first frames)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layout)
	end)
	task.delay(1, layout)

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
			elseif not had and shown and not data.mine.tutorial and not data.mine.practice then
				ui.match.modal.root.Visible = true -- you just joined or made one
			end
			MenuController.refresh()
		end
	end)
	player:GetAttributeChangedSignal("CharId"):Connect(MenuController.refresh)
	Net.get("Leaderboard").OnClientEvent:Connect(function(data)
		if type(data) == "table" and type(data.boards) == "table" then
			boardData = data
			MenuController.refresh()
		end
	end)
	-- the admin panel's answers
	Net.get("Admin").OnClientEvent:Connect(function(data)
		if type(data) == "table" and type(data.msg) == "string" then
			ui.admin.status.Text = data.msg
		end
		MenuController.refresh()
	end)
	-- an event starting or ending changes Home's chips
	for _, kind in ipairs(Config.Admin.Events) do
		ReplicatedStorage:GetAttributeChangedSignal("Event_" .. kind):Connect(MenuController.refresh)
	end

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
		if screen == "match" and lobbies.mine then
			refreshMatchScreen(profile()) -- the countdown on your queue's card
		end
		-- countdowns: the events on Home and in the admin panel, the daily reward's wait
		if tick % 4 == 0 then
			if screen == "home" then
				Extra.refreshHome(profile())
			end
			if ui.daily.modal.root.Visible then
				Extra.refreshDaily(profile())
			end
			if ui.admin.modal.root.Visible then
				Extra.refreshAdmin()
			end
		end
		if tick % 36 == 0 then
			MenuController.refresh()
		end
	end)
end

return MenuController
