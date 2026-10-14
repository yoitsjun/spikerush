-- Quick chat (the owner: "like volleyball legends where you can have prewritten phrases like
-- 'nice play' 'set me' 'lag' 'ref' 'gg'... but also emojis", then "make it a wheel where you pick
-- around 8"): a wheel of your 8 (Settings' quickWheel, Config.QuickChat.Wheel at first), opened
-- with its button (on screen in a match), its key (G, Settings > Controls) or a controller's right
-- stick click. Point at a slice (the mouse or the right stick) and click or press A, or press 1 to
-- 8. Edit swaps any slot for any of the phrases and emojis. A pick goes to the server
-- (QuickChatService), which pops it in a bubble over that player's head on every screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Settings = require(Shared.Settings)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)
local HudLayout = require(script.Parent.HudLayout)

local QuickChat = {}
local mods

local player = Players.LocalPlayer
local make = Gui.make
local QC = Config.QuickChat
local SLOTS = 8
-- rounded slices far enough apart that neighbours never overlap (the owner: the old square ones
-- clumped up and covered each other's text)
local RADIUS = 215
local SLICE = Vector2.new(160, 58)
-- the bubble sits above the name tag (UIController's tagFor: 58 px tall, 2.6 studs over the
-- head), measured in pixels so it clears the tag at any distance
local TAG_HALF = 29
local BUBBLE_H = 210

local gui, button, wheel, editor
local slots = {} -- the wheel's slices: { frame, plate, label, num, scale }
local hot = nil -- the slice pointed at
local bubbles = {} -- userId -> the bubble over their head
local editSlot = 1
local editSlots = {}

-- your wheel: 8 picks like "P3" (phrase 3) or "E1" (emoji 1)
local function picks()
	return Settings.quickWheel(State.settings.quickWheel)
end

local function textOf(pick)
	local kind, i = Settings.quickPick(pick)
	if kind == "Phrase" then
		return QC.Phrases[i], false
	elseif kind == "Emoji" then
		return QC.Emojis[i], true
	end
	return "", false
end

local function send(pick)
	local kind, i = Settings.quickPick(pick)
	if kind then
		Net.get("QuickChat"):FireServer(kind, i)
	end
	QuickChat.close()
end

------------------------------------------------------------------------------------------
-- the wheel
------------------------------------------------------------------------------------------

local function setHot(i)
	hot = i
	for n, s in ipairs(slots) do
		s.plate.BackgroundColor3 = n == i and Gui.SIGNAL or Gui.NAVY
		s.stroke.Color = n == i and Gui.LINE or Gui.HAIRLINE
		s.label.TextColor3 = n == i and Gui.LINE or Gui.CHALK
		s.scale.Scale = n == i and 1.08 or 1
	end
end

local function refreshWheel()
	for n, s in ipairs(slots) do
		local text, emoji = textOf(picks()[n])
		s.label.Text = text
		s.size.MaxTextSize = emoji and 34 or 20
	end
end

-- The slice a direction points at (up is slot 1, then clockwise), or nil near the middle.
local function sliceOf(v, dead)
	if v.Magnitude < dead then
		return nil
	end
	local a = math.deg(math.atan2(v.X, -v.Y)) % 360
	return math.floor((a + 360 / SLOTS / 2) % 360 / (360 / SLOTS)) + 1
end

local stickDir = Vector2.zero
local NUMBER_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight }

local function onWheelInput(_, state, input)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local kc = input.KeyCode
	for n, k in ipairs(NUMBER_KEYS) do
		if kc == k then
			send(picks()[n])
			return Enum.ContextActionResult.Sink
		end
	end
	if kc == Enum.KeyCode.ButtonA or kc == Enum.KeyCode.ButtonR3 then
		if hot then
			send(picks()[hot])
		elseif kc == Enum.KeyCode.ButtonR3 then
			QuickChat.close()
		end
	elseif kc == Enum.KeyCode.ButtonB or kc == Enum.KeyCode.Escape then
		QuickChat.close()
	end
	return Enum.ContextActionResult.Sink
end

function QuickChat.isOpen()
	return wheel ~= nil and wheel.Visible
end

function QuickChat.open()
	if not wheel then
		return
	end
	editor.Visible = false
	refreshWheel()
	setHot(nil)
	stickDir = Vector2.zero
	wheel.Visible = true
	local sc = wheel:FindFirstChildOfClass("UIScale")
	-- shrunk to fit a small screen (a phone held sideways)
	local screen = gui.AbsoluteSize
	local fit = 1
	if screen.X > 10 and screen.Y > 10 then
		fit = math.min(1, (screen.X - 24) / wheel.Size.X.Offset, (screen.Y - 24) / wheel.Size.Y.Offset)
	end
	sc.Scale = 0.6 * fit
	TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
	local keys = { Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonR3, Enum.KeyCode.Escape }
	for _, k in ipairs(NUMBER_KEYS) do
		table.insert(keys, k)
	end
	ContextActionService:BindActionAtPriority("SpikeRushQuickWheel", onWheelInput, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(keys))
end

function QuickChat.close()
	if wheel then
		wheel.Visible = false
	end
	if editor then
		editor.Visible = false
	end
	ContextActionService:UnbindAction("SpikeRushQuickWheel")
end

function QuickChat.toggle()
	if QuickChat.isOpen() or (editor and editor.Visible) then
		QuickChat.close()
	else
		QuickChat.open()
	end
end

local function updateWheel()
	if not QuickChat.isOpen() then
		return
	end
	-- the right stick points; else the mouse, from the wheel's middle
	local ok, state = pcall(function()
		return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	end)
	if ok then
		for _, s in ipairs(state) do
			if s.KeyCode == Enum.KeyCode.Thumbstick2 then
				stickDir = Vector2.new(s.Position.X, -s.Position.Y)
			end
		end
	end
	if stickDir.Magnitude > 0.5 then
		local n = sliceOf(stickDir, 0.5)
		if n ~= hot then
			setHot(n)
		end
		return
	end
	local mid = wheel.AbsolutePosition + wheel.AbsoluteSize / 2
	local n = sliceOf(UserInputService:GetMouseLocation() - mid, 50)
	if n ~= hot then
		setHot(n)
	end
end

------------------------------------------------------------------------------------------
-- the editor: your 8 slots along the top, every phrase and emoji under them
------------------------------------------------------------------------------------------

local function refreshEditor()
	for n, s in ipairs(editSlots) do
		local text, emoji = textOf(picks()[n])
		s.label.Text = text
		s.label.TextScaled = emoji
		Gui.tint(s.plate, n == editSlot and Gui.SIGNAL or Gui.NAVY_LIGHT)
		s.label.TextColor3 = n == editSlot and Gui.LINE or Gui.CHALK
	end
end

local function assign(pick)
	local list = table.clone(picks())
	list[editSlot] = pick
	State.setSetting("quickWheel", list)
	editSlot = editSlot % SLOTS + 1
	refreshEditor()
	refreshWheel()
end

local function openEditor()
	wheel.Visible = false
	ContextActionService:UnbindAction("SpikeRushQuickWheel")
	editSlot = 1
	refreshEditor()
	editor.Visible = true
end

------------------------------------------------------------------------------------------
-- the bubbles
------------------------------------------------------------------------------------------

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
	-- centred where the name tag is (2.6 studs over the head), the bubble in its top part
	-- (a BillboardGui only renders straight under PlayerGui, never inside a ScreenGui)
	local b = make("BillboardGui", {
		Name = "SpikeRushQuickChat",
		Adornee = head,
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(320, BUBBLE_H),
		StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0),
	}, player:WaitForChild("PlayerGui"))
	local bottom = UDim2.new(0.5, 0, 0, BUBBLE_H / 2 - TAG_HALF - 8)
	local scale = make("UIScale", { Scale = 0.3 }, b)
	if emoji then
		Gui.label(b, { Text = text, TextScaled = true, AnchorPoint = Vector2.new(0.5, 1), Position = bottom, Size = UDim2.fromOffset(64, 64), TextXAlignment = Enum.TextXAlignment.Center })
	else
		local plate = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = bottom, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Gui.LINE, BackgroundTransparency = 0.08, BorderSizePixel = 0 }, b)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, plate)
		make("UIStroke", { Color = plr == player and Gui.SIGNAL or Gui.CHALK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, plate)
		make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, plate)
		Gui.label(plate, { Text = text, display = true, TextSize = 22, TextColor3 = Gui.CHALK, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), TextXAlignment = Enum.TextXAlignment.Center })
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

------------------------------------------------------------------------------------------
-- building
------------------------------------------------------------------------------------------

local function build()
	gui = make("ScreenGui", { Name = "SpikeRushQuickChat", ResetOnSpawn = false, DisplayOrder = 40, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))

	-- the button (in a match or spectating): a speech bubble
	-- (on the right edge: on the left it covered the ability buttons)
	button = make("TextButton", { Name = "QuickChatButton", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.36, 0), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = Gui.LINE, BackgroundTransparency = 0.25, Text = "\u{1F4AC}", TextSize = 30, AutoButtonColor = false, Visible = false }, gui)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, button)
	make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	button:SetAttribute("NoNav", true)
	button.MouseButton1Click:Connect(QuickChat.toggle)
	-- never higher than just under the corner buttons (Settings ends 82 px under the top bar): on
	-- a phone held sideways 36% down the screen was on top of Settings
	local function place()
		local y = math.max(gui.AbsoluteSize.Y * 0.36, GuiService:GetGuiInset().Y + 82 + 8 + 28)
		button.Position = UDim2.new(1, -16, 0, math.floor(y))
	end
	place()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	HudLayout.register("Chat", button) -- moved and sized in the touch layout editor

	-- the wheel: 8 slices round a hub with Edit in it
	wheel = make("Frame", { Name = "QuickWheel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(RADIUS * 2 + SLICE.X + 10, RADIUS * 2 + SLICE.Y + 20), BackgroundTransparency = 1, Visible = false }, gui)
	make("UIScale", { Scale = 1 }, wheel)
	local ring = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(RADIUS * 2 + 50, RADIUS * 2 + 50), BackgroundColor3 = Gui.LINE, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, wheel)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1.5, Transparency = 0.3 }, ring)
	local hub = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(112, 112), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0 }, wheel)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, hub)
	make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 1.5 }, hub)
	Gui.label(hub, { Text = "QUICK CHAT", display = true, TextSize = 15, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	local edit = Gui.plateButton(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(78, 30) }, Gui.NAVY_LIGHT, Gui.BLUE_HOT)
	Gui.label(edit, { Text = "Edit", display = true, TextSize = 15, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	edit.MouseButton1Click:Connect(openEditor)
	for n = 1, SLOTS do
		local a = math.rad((n - 1) * 360 / SLOTS)
		local f = make("TextButton", { Name = "Slot" .. n, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.sin(a) * RADIUS, 0.5, -math.cos(a) * RADIUS), Size = UDim2.fromOffset(SLICE.X, SLICE.Y), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, wheel)
		local sc = make("UIScale", { Scale = 1 }, f)
		-- a rounded pill; a long phrase wraps and shrinks to fit inside it
		local plate = make("Frame", { Name = "Pill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Gui.NAVY, BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = 3 }, f)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, plate)
		local stroke = make("UIStroke", { Color = Gui.HAIRLINE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, plate)
		local label = Gui.label(f, { Text = "", display = true, TextScaled = true, TextWrapped = true, Size = UDim2.new(1, -48, 1, -12), Position = UDim2.fromOffset(30, 6), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
		local size = make("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 10 }, label)
		local num = Gui.label(f, { Text = tostring(n), TextSize = 13, TextColor3 = Gui.DIM, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(14, 16), Position = UDim2.new(0, 14, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
		f.MouseButton1Click:Connect(function()
			send(picks()[n])
		end)
		slots[n] = { frame = f, plate = plate, stroke = stroke, label = label, size = size, num = num, scale = sc }
	end

	-- the editor: your slots along the top (the yellow one gets the next pick), everything under
	editor = Gui.card(gui, { Name = "QuickChatEditor", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 520), Visible = false, BackgroundTransparency = 0.06 })
	Gui.label(editor, { Text = "Your quick chat wheel", display = true, TextSize = 24, Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(360, 32) })
	Gui.label(editor, { Text = "Pick a slot, then what goes in it.", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(18, 40), Size = UDim2.fromOffset(360, 20) })
	local done = Gui.plateButton(editor, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(96, 34) }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	Gui.label(done, { Text = "Done", display = true, TextSize = 17, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	done.MouseButton1Click:Connect(QuickChat.open)
	local reset = Gui.plateButton(editor, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -116, 0, 12), Size = UDim2.fromOffset(96, 34) }, Gui.NAVY_LIGHT, Gui.BLUE_HOT)
	Gui.label(reset, { Text = "Reset", display = true, TextSize = 17, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	reset.MouseButton1Click:Connect(function()
		State.setSetting("quickWheel", table.clone(QC.Wheel))
		editSlot = 1
		refreshEditor()
		refreshWheel()
	end)
	for n = 1, SLOTS do
		local b, plate = Gui.plateButton(editor, { Position = UDim2.fromOffset(14 + (n - 1) * 74, 70), Size = UDim2.fromOffset(70, 44) }, Gui.NAVY_LIGHT, Gui.SIGNAL_HOT)
		local label = Gui.label(b, { Text = "", display = true, TextSize = 13, Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, ZIndex = 3 })
		b.MouseButton1Click:Connect(function()
			editSlot = n
			refreshEditor()
		end)
		editSlots[n] = { plate = plate, label = label }
	end
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(12, 126), Size = UDim2.new(1, -24, 1, -138), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, editor)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(140, 40), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local order = 0
	for _, kind in ipairs({ "P", "E" }) do
		for i, text in ipairs(kind == "P" and QC.Phrases or QC.Emojis) do
			order = order + 1
			local b = make("TextButton", { LayoutOrder = order, BackgroundColor3 = Gui.NAVY, BackgroundTransparency = 0.15, AutoButtonColor = true, Text = "", BorderSizePixel = 0 }, list)
			make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
			Gui.label(b, { Text = text, display = kind == "P", TextSize = kind == "P" and 16 or 26, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
			Gui.pressSound(b)
			b.MouseButton1Click:Connect(function()
				assign(kind .. i)
			end)
		end
	end
end

local function refreshButton()
	if button then
		-- (the wheel itself works anywhere: G opens it in the menus too)
		button.Visible = State.watching() == true
	end
end

function QuickChat.init(m)
	mods = m
	build()
	refreshWheel()
	if mods.PadNav then
		mods.PadNav.root(editor, { prio = 30, back = QuickChat.close })
	end
	Net.get("QuickChat").OnClientEvent:Connect(function(userId, kind, i)
		if type(userId) == "number" and (kind == "Phrase" or kind == "Emoji") and type(i) == "number" then
			showBubble(userId, kind, i)
		end
	end)
	State.signals.Match:Connect(refreshButton)
	State.signals.Settings:Connect(function(key)
		if key == "quickWheel" then
			refreshWheel()
		end
	end)
	RunService.RenderStepped:Connect(updateWheel)
	refreshButton()
end

return QuickChat
