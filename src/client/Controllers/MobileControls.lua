-- Touch controls, laid out like a console volleyball game's: three big round buttons bottom right
-- that change with the moment, a column of round skill buttons on the left, and a floating
-- thumbstick of our own on the left (a touch there puts the stick under the finger). Roblox's own
-- touch controls are off: this place has no PlayerModule to read their stick from.
--   holding the serve ... Basic Serve (underhand) | Spike Serve (tap: overhand, hold: toss) |
--                         Jump Serve (a standard jump-serve toss)
--   on the ground ....... Slide | Bump (Block at the net) | Jump (straight up, a spike's wind-up;
--                         the owner: "on mobile, make approach just make you jump")
--   in the air .......... Slide (off) | Feint (the bump button) | Spike (Charge with Azure Dragon)
-- At the net the Bump button blocks: hold to charge, let go to jump. Set pops up over it when you
-- can set the ball. The skill column holds your active ability (Q) and your AI teammates' (1, 2).
-- A button keeps the action it was pressed as until the finger lifts, and holds release when the
-- finger lifts anywhere on screen.
-- Every button can be moved and resized in the layout editor (Settings > Touch controls); the
-- layout is saved with your settings (State.settings.touchLayout).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Settings = require(Shared.Settings)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local MobileControls = {}
local mods

local player = Players.LocalPlayer
local UI = Config.UI
local TOUCH = Config.Settings.Touch
local gui, root, uiScale = nil, nil, nil
local buttons = {}
local held = {}
local editor = nil -- while the layout editor is open: { layout, selected, drag }
local ed = nil -- the editor's shade and toolbar

local WHITE = Color3.new(1, 1, 1)
local ORANGE = Color3.fromRGB(255, 150, 40)
local REST, PRESSED, OFF = 0.8, 0.5, 0.92 -- disc fill transparency

-- Each button's usual place (its centre) and size; the skills carry their label under the disc.
local DEFAULTS = {
	A = { UDim2.new(1, -404, 1, -104), 124 },
	B = { UDim2.new(1, -254, 1, -104), 124 },
	C = { UDim2.new(1, -104, 1, -104), 124 },
	Set = { UDim2.new(1, -254, 1, -244), 86 },
	Skill1 = { UDim2.new(0, 70, 0.3, 0), 76, true },
	Skill2 = { UDim2.new(0, 70, 0.3, 118), 76, true },
	Skill3 = { UDim2.new(0, 70, 0.3, 236), 76, true },
}

-- What each button shows in the layout editor.
local EDIT_LOOK = {
	A = { "Slide", "IconSpeed" },
	B = { "Bump", "IconDefense" },
	C = { "Jump", "IconJump" },
	Set = { "Set", "IconStar" },
	Skill1 = { "Skill 1", "IconStar" },
	Skill2 = { "Skill 2", "IconStar" },
	Skill3 = { "Skill 3", "IconStar" },
}

local startDrag -- the editor's drag (defined with the editor)

-- A round button: a see-through white disc with a ring, an icon and its label (inside at the
-- bottom for the big buttons, under the disc for the skills).
local function roundButton(name)
	local d = DEFAULTS[name]
	local labelBelow = d[3] == true
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = d[1]
	b.Size = UDim2.fromOffset(d[2], d[2])
	b.BackgroundColor3 = WHITE
	b.BackgroundTransparency = REST
	b.Visible = false
	b.ZIndex = 2
	b.Parent = root
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	local ring = Instance.new("UIStroke")
	ring.Thickness = 2
	ring.Color = WHITE
	ring.Transparency = 0.3
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = b
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, labelBelow and 0.5 or 0.42)
	icon.Size = UDim2.fromScale(labelBelow and 0.56 or 0.44, labelBelow and 0.56 or 0.44)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ImageColor3 = WHITE
	icon.ImageTransparency = 0.2
	icon.ZIndex = 2
	icon.Parent = b
	-- sized with the disc, so a resized button keeps its proportions
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = labelBelow and UDim2.new(0.5, 0, 1, 4) or UDim2.fromScale(0.5, 0.7)
	label.Size = UDim2.fromScale(1.6, labelBelow and 0.2 or 0.17)
	label.FontFace = Gui.display(Enum.FontWeight.Heavy)
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.45
	label.Text = ""
	label.ZIndex = 2
	label.Parent = b
	local entry = { button = b, ring = ring, icon = icon, label = label, action = nil, enabled = true }
	buttons[name] = entry
	b.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if editor then
			startDrag(name, input)
			return
		end
		if not entry.action or not entry.enabled then
			return
		end
		b.BackgroundTransparency = PRESSED
		held[name] = { input = input, kind = input.UserInputType, at = Vector2.new(input.Position.X, input.Position.Y), action = entry.action, t0 = os.clock() }
		if RunService:IsStudio() then
			print(string.format("[SpikeRush] touch %s -> %s (%s)", name, entry.action, input.UserInputType.Name))
		end
		mods.ActionController.press(entry.action)
	end)
	return entry
end

local function letGo(name, h)
	held[name] = nil
	local entry = buttons[name]
	entry.button.BackgroundTransparency = entry.enabled and REST or OFF
	if RunService:IsStudio() then
		print(string.format("[SpikeRush] touch %s released after %.2f s", name, os.clock() - h.t0))
	end
	mods.ActionController.release(h.action)
end

-- A lifted finger releases the button it pressed. The input that ends is matched by object, or
-- (should a device hand over a different object) by its kind and where it was, so a hold (the
-- spike serve's toss, a block, the Azure charge) always lets go.
local function releaseInput(input)
	local t = input.UserInputType
	if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local exact = nil
	for name, h in pairs(held) do
		if h.input == input then
			exact = name
		end
	end
	if exact then
		letGo(exact, held[exact])
		return
	end
	local at = Vector2.new(input.Position.X, input.Position.Y)
	local best, bestD = nil, 160
	for name, h in pairs(held) do
		if h.kind == t then
			local d = (h.at - at).Magnitude
			if t == Enum.UserInputType.MouseButton1 or d < bestD then
				best, bestD = name, d
			end
		end
	end
	if best then
		letGo(best, held[best])
	end
end

------------------------------------------------------------------------------------------
-- the thumbstick: a touch that starts on the left of the screen (not on a button) puts the
-- stick under the finger, and dragging it left and right moves you along the court
-- (MovementController.axis reads stickX). In Studio with ForceTouch the mouse drives it.
------------------------------------------------------------------------------------------

local STICK_ZONE = 0.45 -- the left share of the screen a stick can start in (below the top fifth)
local STICK_R = 70 -- how far the knob reaches, in the touch gui's units
local stick = { input = nil, origin = nil, x = 0 }
local stickBase, stickKnob = nil, nil

function MobileControls.stickX()
	return stick.x
end

local function stickRest()
	stickBase.Position = UDim2.fromScale(0.16, 0.74)
	stickKnob.Position = UDim2.fromScale(0.5, 0.5)
	stickBase.BackgroundTransparency = 0.92
	stickKnob.BackgroundTransparency = 0.8
end

local function stickEnd()
	stick.input, stick.origin, stick.x = nil, nil, 0
	stickRest()
end

local function stickMove(pos)
	local s = uiScale.Scale
	local dx = (pos.X - stick.origin.X) / (STICK_R * s)
	local dy = (pos.Y - stick.origin.Y) / (STICK_R * s)
	local len = math.sqrt(dx * dx + dy * dy)
	if len > 1 then
		dx, dy = dx / len, dy / len
	end
	stick.x = math.abs(dx) > 0.15 and dx or 0
	stickKnob.Position = UDim2.new(0.5, dx * STICK_R, 0.5, dy * STICK_R)
end

local function stickBegin(input)
	if stick.input or editor or not gui.Enabled then
		return
	end
	local size = gui.AbsoluteSize
	local p = input.Position
	if p.X > size.X * STICK_ZONE or p.Y < size.Y * 0.2 then
		return
	end
	local s = uiScale.Scale
	stick.input = input
	stick.origin = Vector2.new(p.X, p.Y)
	stickBase.Position = UDim2.fromOffset(p.X / s, p.Y / s)
	stickBase.BackgroundTransparency = 0.82
	stickKnob.BackgroundTransparency = 0.45
	stickMove(stick.origin)
end

local function buildStick()
	stickBase = Instance.new("Frame")
	stickBase.Name = "Stick"
	stickBase.AnchorPoint = Vector2.new(0.5, 0.5)
	stickBase.Size = UDim2.fromOffset(STICK_R * 2, STICK_R * 2)
	stickBase.BackgroundColor3 = WHITE
	stickBase.ZIndex = 1
	stickBase.Parent = root
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = stickBase
	local edge = Instance.new("UIStroke")
	edge.Color = WHITE
	edge.Thickness = 2
	edge.Transparency = 0.5
	edge.Parent = stickBase
	stickKnob = Instance.new("Frame")
	stickKnob.Name = "Knob"
	stickKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	stickKnob.Size = UDim2.fromOffset(64, 64)
	stickKnob.BackgroundColor3 = WHITE
	stickKnob.ZIndex = 1
	stickKnob.Parent = stickBase
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0.5, 0)
	kc.Parent = stickKnob
	stickRest()
	UserInputService.TouchStarted:Connect(function(input, processed)
		if not processed then
			stickBegin(input)
		end
	end)
	UserInputService.TouchMoved:Connect(function(input)
		if input == stick.input then
			stickMove(input.Position)
		end
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if input == stick.input then
			stickEnd()
		end
	end)
	-- Studio's ForceTouch (no real touch screen): the mouse drives the stick
	if not UserInputService.TouchEnabled then
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
				stickBegin(input)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if stick.input and stick.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement then
				stickMove(input.Position)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if stick.input and input.UserInputType == Enum.UserInputType.MouseButton1 then
				stickEnd()
			end
		end)
	end
end

local function hideDefaultJump()
	local pg = player:FindFirstChild("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	local frame = tg and tg:FindFirstChild("TouchControlFrame")
	local jb = frame and frame:FindFirstChild("JumpButton")
	if jb then
		jb.Visible = false
	end
end

------------------------------------------------------------------------------------------
-- layout: each button's saved place and size (or its usual one)
------------------------------------------------------------------------------------------

local function layoutOf(name)
	local layout = (editor and editor.layout) or State.settings.touchLayout or {}
	return layout[name]
end

local function place(name)
	local entry = buttons[name]
	local d = DEFAULTS[name]
	local l = layoutOf(name)
	local size = d[2] * (l and l.size or 1)
	entry.button.Size = UDim2.fromOffset(size, size)
	entry.button.Position = l and UDim2.fromScale(l.x, l.y) or d[1]
end

local function applyLayout()
	for name in pairs(buttons) do
		place(name)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "SpikeRushTouch"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	local function rescale()
		local cam = workspace.CurrentCamera
		if cam then
			local s = math.clamp(cam.ViewportSize.Y / 720, 0.7, 1.1)
			uiScale.Scale = s
			-- a UIScale shrinks its frame toward the top-left corner; sized 1/s the frame still
			-- covers the screen, so the buttons stay in their corners
			root.Size = UDim2.fromScale(1 / s, 1 / s)
		end
	end
	rescale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	for _, name in ipairs(TOUCH.Buttons) do
		roundButton(name)
	end
	applyLayout()
	buildStick()
	UserInputService.InputEnded:Connect(releaseInput)
end

-- Point a button at an action (nil hides it) with its label and icon; `enabled` false shows it
-- faded and dead (the Slide button in the air).
local function set(name, action, text, iconKey, enabled)
	local entry = buttons[name]
	entry.action = action
	entry.enabled = enabled ~= false
	entry.button.Visible = action ~= nil
	entry.label.Text = text or ""
	if entry.iconKey ~= iconKey then
		entry.iconKey = iconKey
		entry.icon.Image = Assets.image(iconKey) or ""
	end
	if not held[name] then
		entry.button.BackgroundTransparency = entry.enabled and REST or OFF
	end
	entry.icon.ImageTransparency = entry.enabled and 0.2 or 0.65
	entry.label.TextTransparency = entry.enabled and 0 or 0.5
end

local function ring(name, color, strong)
	local entry = buttons[name]
	entry.ring.Color = color or WHITE
	entry.ring.Thickness = strong and 4 or 2
	entry.ring.Transparency = strong and 0 or 0.3
end

------------------------------------------------------------------------------------------
-- the layout editor: drag a button to move it, pick one (or All) and size it
------------------------------------------------------------------------------------------

local function label(parent, props)
	local l = Gui.label(parent, props)
	l.ZIndex = 7
	return l
end

-- A button's centre as a fraction of the screen, and its size.
local function current(name)
	local l = editor.layout[name]
	if l then
		return { x = l.x, y = l.y, size = l.size }
	end
	local b = buttons[name].button
	local rp, rs = root.AbsolutePosition, root.AbsoluteSize
	local c = b.AbsolutePosition + b.AbsoluteSize / 2
	return { x = (c.X - rp.X) / rs.X, y = (c.Y - rp.Y) / rs.Y, size = 1 }
end

-- Keep a button (its centre at x, y, a fraction of the screen) wholly on screen.
local function onScreen(name, spot)
	spot.size = math.clamp(spot.size, TOUCH.MinSize, TOUCH.MaxSize)
	local rs = root.AbsoluteSize
	local half = DEFAULTS[name][2] * spot.size * uiScale.Scale / 2
	spot.x = math.clamp(spot.x, math.min(0.5, half / rs.X), math.max(0.5, 1 - half / rs.X))
	spot.y = math.clamp(spot.y, math.min(0.5, half / rs.Y), math.max(0.5, 1 - half / rs.Y))
	return Settings.touchButton(spot)
end

local function refreshEditor()
	local sel = editor.selected
	for _, name in ipairs(TOUCH.Buttons) do
		local on = sel == "All" or sel == name
		ring(name, on and Gui.SIGNAL or nil, on)
	end
	local size
	if sel == "All" then
		local sum = 0
		for _, name in ipairs(TOUCH.Buttons) do
			local l = editor.layout[name]
			sum = sum + (l and l.size or 1)
		end
		size = sum / #TOUCH.Buttons
		ed.picked.Text = "ALL BUTTONS"
	else
		local l = editor.layout[sel]
		size = l and l.size or 1
		ed.picked.Text = string.upper(EDIT_LOOK[sel][1])
	end
	ed.pct.Text = string.format("%d%%", math.floor(size * 100 + 0.5))
	ed.setAll(sel == "All" and "All" or nil)
end

local function selectButton(name)
	editor.selected = name
	refreshEditor()
end

startDrag = function(name, input)
	selectButton(name)
	local b = buttons[name].button
	editor.drag = { name = name, input = input, from = Vector2.new(input.Position.X, input.Position.Y), start = b.AbsolutePosition + b.AbsoluteSize / 2 }
end

local function dragTo(input)
	local d = editor and editor.drag
	if not d then
		return
	end
	local mouse = d.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
	if input ~= d.input and not mouse then
		return
	end
	local rp, rs = root.AbsolutePosition, root.AbsoluteSize
	local c = d.start + Vector2.new(input.Position.X, input.Position.Y) - d.from
	local spot = current(d.name)
	spot.x = (c.X - rp.X) / rs.X
	spot.y = (c.Y - rp.Y) / rs.Y
	editor.layout[d.name] = onScreen(d.name, spot)
	place(d.name)
end

local function endDrag(input)
	local d = editor and editor.drag
	if d and (input == d.input or (d.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
		editor.drag = nil
	end
end

local function resize(step)
	local names = editor.selected == "All" and TOUCH.Buttons or { editor.selected }
	for _, name in ipairs(names) do
		local spot = current(name)
		spot.size = math.floor((spot.size + step) * 10 + 0.5) / 10
		editor.layout[name] = onScreen(name, spot)
		place(name)
	end
	refreshEditor()
end

local function closeEditor(save)
	local e = editor
	editor = nil
	if save then
		State.setSetting("touchLayout", e.layout)
	end
	ed.shade.Visible = false
	ed.bar.Visible = false
	gui.DisplayOrder = 8
	for _, name in ipairs(TOUCH.Buttons) do
		ring(name, nil, false)
	end
	applyLayout()
end

local function toolButton(parent, text, x, w, onPress, signal)
	local b
	if signal then
		b = Gui.plateButton(parent, { Position = UDim2.fromOffset(x, 64), Size = UDim2.fromOffset(w, 52), ZIndex = 7 }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	else
		b = Gui.cardButton(parent, { Position = UDim2.fromOffset(x, 64), Size = UDim2.fromOffset(w, 52), ZIndex = 7 })
	end
	label(b, { Text = text, display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, TextColor3 = signal and Gui.LINE or Gui.CHALK, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	b.MouseButton1Click:Connect(function()
		if mods.AudioController then
			mods.AudioController.play(signal and "UIConfirm" or "UISelect")
		end
		onPress()
	end)
	return b
end

local function buildEditor()
	ed = {}
	-- everything behind the buttons dims
	ed.shade = Instance.new("Frame")
	ed.shade.Name = "EditShade"
	ed.shade.Size = UDim2.fromScale(1, 1)
	ed.shade.BackgroundColor3 = Color3.new(0, 0, 0)
	ed.shade.BackgroundTransparency = 0.45
	ed.shade.BorderSizePixel = 0
	ed.shade.ZIndex = 1
	ed.shade.Visible = false
	ed.shade.Parent = root
	local bar = Gui.card(root, { Name = "EditBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(736, 132), BackgroundTransparency = 0.08, ZIndex = 6, Visible = false })
	ed.bar = bar
	label(bar, { Text = "TOUCH CONTROLS", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, Position = UDim2.fromOffset(18, 8), Size = UDim2.fromOffset(260, 34) })
	local tick = Gui.plate(bar, { Size = UDim2.fromOffset(56, 5), Position = UDim2.fromOffset(20, 44) }, Gui.SIGNAL)
	tick.ZIndex = 7
	label(bar, { Text = "Drag a button to move it. Tap one, then size it with - and +.", TextSize = 17, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(280, 8), Size = UDim2.fromOffset(440, 44) })
	ed.picked = label(bar, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = Gui.SIGNAL, Position = UDim2.fromOffset(18, 64), Size = UDim2.fromOffset(142, 52), TextWrapped = true })
	local minus = Gui.squareButton(bar, "-", { Position = UDim2.fromOffset(160, 64), Size = UDim2.fromOffset(52, 52), ZIndex = 7 })
	ed.pct = label(bar, { Text = "100%", display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, Position = UDim2.fromOffset(214, 64), Size = UDim2.fromOffset(74, 52), TextXAlignment = Enum.TextXAlignment.Center })
	local plus = Gui.squareButton(bar, "+", { Position = UDim2.fromOffset(290, 64), Size = UDim2.fromOffset(52, 52), ZIndex = 7 })
	for _, child in ipairs({ minus, plus }) do
		for _, d in ipairs(child:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = 7
			end
		end
	end
	Gui.pressSound(minus, "UITick")
	Gui.pressSound(plus, "UITick")
	minus.MouseButton1Click:Connect(function()
		Gui.click("UITick")
		resize(-TOUCH.SizeStep)
	end)
	plus.MouseButton1Click:Connect(function()
		Gui.click("UITick")
		resize(TOUCH.SizeStep)
	end)
	local chips, setAll = Gui.chips(bar, { { key = "All", text = "All", width = 64 } }, { Position = UDim2.fromOffset(350, 64), Size = UDim2.fromOffset(64, 52), ZIndex = 7 }, function()
		selectButton("All")
	end)
	for _, d in ipairs(chips:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 7
		end
	end
	ed.setAll = setAll
	toolButton(bar, "Reset", 426, 90, function()
		editor.layout = {}
		applyLayout()
		refreshEditor()
	end)
	toolButton(bar, "Cancel", 524, 94, function()
		closeEditor(false)
	end)
	toolButton(bar, "Save", 626, 94, function()
		closeEditor(true)
	end, true)
	UserInputService.InputChanged:Connect(dragTo)
	UserInputService.InputEnded:Connect(endDrag)
end

-- Opens the layout editor over everything: every button shows, whatever the moment.
function MobileControls.editLayout()
	if editor or not gui then
		return
	end
	if not ed then
		buildEditor()
	end
	-- anything held lets go first (a charge or a toss mustn't stay on)
	for name, h in pairs(held) do
		held[name] = nil
		mods.ActionController.release(h.action)
	end
	editor = { layout = table.clone(State.settings.touchLayout or {}), selected = "All", drag = nil }
	gui.Enabled = true
	gui.DisplayOrder = 60
	ed.shade.Visible = true
	ed.bar.Visible = true
	for _, name in ipairs(TOUCH.Buttons) do
		local look = EDIT_LOOK[name]
		set(name, "Edit", look[1], look[2])
		buttons[name].icon.ImageColor3 = WHITE
	end
	applyLayout()
	refreshEditor()
end

function MobileControls.isEditing()
	return editor ~= nil
end

------------------------------------------------------------------------------------------
-- per frame
------------------------------------------------------------------------------------------

local function update()
	if editor then
		return
	end
	-- a finger that has lifted lets go of its button (or the stick), even if its end wasn't heard
	for name, h in pairs(held) do
		local s = h.input.UserInputState
		if s == Enum.UserInputState.End or s == Enum.UserInputState.Cancel then
			letGo(name, h)
		end
	end
	if stick.input then
		local s = stick.input.UserInputState
		if s == Enum.UserInputState.End or s == Enum.UserInputState.Cancel then
			stickEnd()
		end
	end
	local show = State.isMobile and State.isPlaying and State.match.inMatch == true
	gui.Enabled = show
	if not show then
		if stick.input then
			stickEnd()
		end
		return
	end
	hideDefaultJump()
	local ctx = State.context or {}
	local air = ctx.grounded == false
	if ctx.serving then
		local holding = ctx.spikeLabel == "Toss"
		set("A", holding and "EasyServe" or nil, "Basic Serve", "IconStar")
		set("B", holding and "Serve" or nil, "Spike Serve", "IconAttack")
		if holding then
			set("C", "Spike", "Jump Serve", "IconJump") -- a standard jump-serve toss
		else
			set("C", air and "Spike" or "Jump", air and "Spike" or "Jump", air and "IconAttack" or "IconJump")
		end
		set("Set", nil)
		-- the spike serve's toss charges while held: the ring warms to orange
		local h = held.B
		if h and h.action == "Serve" then
			local k = math.clamp((os.clock() - h.t0 - Config.Player.ServeTapTime) / Config.Hits.TossChargeTime, 0, 1)
			ring("B", WHITE:Lerp(ORANGE, k), k > 0)
		else
			ring("B", nil, false)
		end
		ring("C", UI.Spark, ctx.inZone == true or ctx.running == true)
	else
		set("A", "SlideFeint", "Slide", "IconSpeed", not air)
		local atNet = ctx.nearNet == true and not air
		-- Feral Leap: held, Jump charges (let go to leap)
		local jumpLabel = ctx.spikeLabel == "Leap" and "Leap" or "Jump"
		if air then
			set("B", "SlideFeint", "Feint", "IconDefense")
			set("C", "Spike", ctx.spikeLabel == "Charge" and "Charge" or "Spike", "IconAttack")
		elseif atNet then
			-- at the net the bump button blocks: hold to charge, let go to jump
			set("B", "Block", "Block", "IconDefense")
			set("C", "Jump", jumpLabel, "IconJump")
		else
			set("B", "Receive", "Bump", "IconDefense")
			set("C", "Jump", jumpLabel, "IconJump")
		end
		-- with setter aim on the Set button stays up, so the distance can be charged as the pass
		-- comes (hold, then let go when it's in reach)
		local aiming = mods.SetterAim ~= nil and mods.SetterAim.on()
		set("Set", (ctx.canSet == true or aiming) and "Set" or nil, "Set", "IconStar")
		ring("A", nil, false)
		local charge = mods.ActionController.blockCharge()
		if charge then
			ring("B", WHITE:Lerp(ORANGE, charge), true)
		else
			ring("B", UI.Spark, ctx.incoming == true and not air)
		end
		local prowl = mods.ActionController.prowlCharge()
		if prowl then
			local F = Config.Abilities.Feral
			ring("C", prowl >= F.FullAt and Color3.fromRGB(255, 80, 210) or F.Color, true)
		else
			ring("C", UI.Spark, ctx.inZone == true or ctx.running == true)
		end
		ring("Set", UI.Spark, ctx.canSet == true)
	end

	-- skills: your active ability, then your AI teammates'
	local skills = {}
	local mine = State.myAbility()
	local def = Config.Abilities[mine or ""]
	if def and def.Active then
		table.insert(skills, { action = "Ability", ability = mine, left = mods.ActionController.abilityCooldown() })
	end
	for i, mate in ipairs(mods.ActionController.teamAbilities()) do
		table.insert(skills, { action = "Team" .. i, ability = mate.ability, left = mods.ActionController.cooldownOf(mate.id) })
	end
	for i = 1, 3 do
		local s = skills[i]
		local name = "Skill" .. i
		if s then
			local d = Config.Abilities[s.ability]
			local ready = s.left <= 0
			set(name, s.action, ready and d.Name or string.format("%s  %ds", d.Name, math.ceil(s.left)), Assets.image("Ability" .. s.ability) and ("Ability" .. s.ability) or "IconStar")
			buttons[name].icon.ImageColor3 = d.Color
			ring(name, d.Color, ready)
		else
			set(name, nil)
		end
	end
end

function MobileControls.init(m)
	mods = m
	build()
	-- Roblox's own touch controls: their stick can't be read here and their jump button sat on
	-- top of ours, so the touch controls above replace them
	if UserInputService.TouchEnabled then
		pcall(function()
			GuiService.TouchControlsEnabled = false
		end)
	end
	-- the saved layout arrives with the profile (or changes in the editor)
	State.signals.Settings:Connect(function(key)
		if key == "touchLayout" and not editor then
			applyLayout()
		end
	end)
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(update)
		if not ok then
			warn("[SpikeRush] touch: " .. tostring(err))
		end
	end)
end

return MobileControls
