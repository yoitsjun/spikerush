-- Quick chat (the owner: "like volleyball legends where you can have prewritten phrases like
-- 'nice play' 'set me' 'lag' 'ref' 'gg'... but also emojis"): a panel of phrases and emojis
-- (Config.QuickChat), opened with its button (on screen in a match), its key (G, Settings >
-- Controls) or a controller's right stick click. A pick goes to the server (QuickChatService),
-- which pops it in a bubble over that player's head on every screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local QuickChat = {}
local mods

local player = Players.LocalPlayer
local make = Gui.make
local QC = Config.QuickChat

local gui, panel, button
local tab = "Phrase"
local pages = {}
local tabButtons = {}
local bubbles = {} -- userId -> the bubble showing over their head

local function send(kind, i)
	Net.get("QuickChat"):FireServer(kind, i)
	QuickChat.close()
end

local function setTab(key)
	tab = key
	for k, page in pairs(pages) do
		page.Visible = k == key
	end
	for k, t in pairs(tabButtons) do
		Gui.tint(t.plate, k == key and Gui.SIGNAL or Gui.NAVY_LIGHT)
		t.label.TextColor3 = k == key and Gui.LINE or Gui.CHALK
	end
end

function QuickChat.open()
	if not panel then
		return
	end
	panel.Visible = true
	setTab(tab)
	if mods and mods.PadNav then
		mods.PadNav.set(panel)
	end
end

function QuickChat.close()
	if panel then
		panel.Visible = false
	end
end

function QuickChat.toggle()
	if panel and panel.Visible then
		QuickChat.close()
	else
		QuickChat.open()
	end
end

-- A bubble over a player's head: a phrase on a plate, or a big emoji; it pops in, holds, fades.
local function showBubble(userId, kind, i)
	local plr = Players:GetPlayerByUserId(userId)
	local char = plr and plr.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local old = bubbles[userId]
	if old then
		old:Destroy()
	end
	local emoji = kind == "Emoji"
	local text = emoji and QC.Emojis[i] or QC.Phrases[i]
	if not text then
		return
	end
	local b = make("BillboardGui", {
		Name = "SpikeRushQuickChat",
		Adornee = head,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = emoji and UDim2.fromOffset(72, 72) or UDim2.fromOffset(240, 46),
		StudsOffset = Vector3.new(0, emoji and 3.6 or 3.2, 0),
		ResetOnSpawn = false,
	}, gui)
	local scale = make("UIScale", { Scale = 0.3 }, b)
	if emoji then
		Gui.label(b, { Text = text, TextScaled = true, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	else
		local plate = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Gui.LINE, BackgroundTransparency = 0.1, BorderSizePixel = 0 }, b)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, plate)
		make("UIStroke", { Color = plr == player and Gui.SIGNAL or Gui.CHALK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, plate)
		make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, plate)
		Gui.label(plate, { Text = text, display = true, TextSize = 22, TextColor3 = Gui.CHALK, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), TextXAlignment = Enum.TextXAlignment.Center })
	end
	bubbles[userId] = b
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(QC.Show, function()
		if bubbles[userId] ~= b then
			return
		end
		local fade = TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		fade:Play()
		fade.Completed:Wait()
		if bubbles[userId] == b then
			bubbles[userId] = nil
		end
		b:Destroy()
	end)
end

local function build()
	gui = make("ScreenGui", { Name = "SpikeRushQuickChat", ResetOnSpawn = false, DisplayOrder = 8, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))

	-- the button (in a match or spectating): a speech bubble
	button = make("TextButton", { Name = "QuickChatButton", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.42, 0), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = Gui.LINE, BackgroundTransparency = 0.25, Text = "\u{1F4AC}", TextSize = 30, AutoButtonColor = false, Visible = false }, gui)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, button)
	make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	button:SetAttribute("NoNav", true)
	button.MouseButton1Click:Connect(QuickChat.toggle)

	-- the panel: Phrases and Emojis tabs, a grid of each
	panel = Gui.card(gui, { Name = "QuickChatPanel", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 84, 0.5, 0), Size = UDim2.fromOffset(470, 420), Visible = false, BackgroundTransparency = 0.08 })
	Gui.label(panel, { Text = "Quick chat", display = true, TextSize = 24, Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(200, 32) })
	local close = Gui.plateButton(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(84, 32) }, Gui.NAVY_LIGHT, Gui.BLUE_HOT)
	Gui.label(close, { Text = "Close", display = true, TextSize = 16, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	close.MouseButton1Click:Connect(QuickChat.close)
	for n, def in ipairs({ { "Phrase", "Phrases" }, { "Emoji", "Emojis" } }) do
		local t, plate = Gui.plateButton(panel, { Position = UDim2.fromOffset(16 + (n - 1) * 130, 52), Size = UDim2.fromOffset(122, 34) }, Gui.NAVY_LIGHT, Gui.SIGNAL_HOT)
		local l = Gui.label(t, { Text = def[2], display = true, TextSize = 17, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		t.MouseButton1Click:Connect(function()
			setTab(def[1])
		end)
		tabButtons[def[1]] = { plate = plate, label = l }
	end
	for _, kind in ipairs({ "Phrase", "Emoji" }) do
		local emoji = kind == "Emoji"
		local page = make("ScrollingFrame", { Position = UDim2.fromOffset(12, 96), Size = UDim2.new(1, -24, 1, -108), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Visible = false }, panel)
		make("UIGridLayout", { CellSize = emoji and UDim2.fromOffset(62, 62) or UDim2.fromOffset(140, 40), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		for i, text in ipairs(emoji and QC.Emojis or QC.Phrases) do
			local b = make("TextButton", { LayoutOrder = i, BackgroundColor3 = Gui.NAVY, BackgroundTransparency = 0.15, AutoButtonColor = true, Text = "", BorderSizePixel = 0 }, page)
			make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
			if emoji then
				Gui.label(b, { Text = text, TextScaled = true, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), TextXAlignment = Enum.TextXAlignment.Center })
			else
				Gui.label(b, { Text = text, display = true, TextSize = 17, TextScaled = false, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
			end
			Gui.pressSound(b)
			b.MouseButton1Click:Connect(function()
				send(kind, i)
			end)
		end
		pages[kind] = page
	end
	setTab("Phrase")
end

local function refreshButton()
	if button then
		button.Visible = State.watching() == true
		if not button.Visible then
			QuickChat.close()
		end
	end
end

function QuickChat.init(m)
	mods = m
	build()
	if mods.PadNav then
		mods.PadNav.root(panel, { prio = 30, back = QuickChat.close })
	end
	Net.get("QuickChat").OnClientEvent:Connect(function(userId, kind, i)
		if type(userId) == "number" and (kind == "Phrase" or kind == "Emoji") and type(i) == "number" then
			showBubble(userId, kind, i)
		end
	end)
	State.signals.Match:Connect(refreshButton)
	refreshButton()
end

return QuickChat
