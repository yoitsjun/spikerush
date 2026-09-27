-- Touch controls, laid out like a console volleyball game's: three big round buttons bottom right
-- that change with the moment, a column of round skill buttons on the left, and Roblox's floating
-- thumbstick bottom left (StarterPlayer.DevTouchMovementMode = DynamicThumbstick).
--   holding the serve ... Basic Serve (underhand) | Spike Serve (tap: overhand, hold: toss) | Approach
--   on the ground ....... Slide | Bump | Approach (a run-up jump)
--   in the air .......... Slide (off) | Feint (the bump button) | Spike (Charge with Azure Dragon)
-- Set pops up over Bump when you can set the ball, and Block over Approach near the net (hold to
-- charge, release to jump). The skill column holds your active ability (Q) and your AI
-- teammates' (1, 2). A button keeps the action it was pressed as until the finger lifts, and
-- holds release when the finger lifts anywhere on screen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local MobileControls = {}
local mods

local player = Players.LocalPlayer
local UI = Config.UI
local gui, root = nil, nil
local buttons = {}
local held = {}

local WHITE = Color3.new(1, 1, 1)
local ORANGE = Color3.fromRGB(255, 150, 40)
local REST, PRESSED, OFF = 0.8, 0.5, 0.92 -- disc fill transparency

-- A round button: a see-through white disc with a ring, an icon and its label (inside at the
-- bottom for the big buttons, under the disc for the skills).
local function roundButton(name, size, pos, labelBelow)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = pos
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = WHITE
	b.BackgroundTransparency = REST
	b.Visible = false
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
	icon.Parent = b
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = labelBelow and UDim2.new(0.5, 0, 1, 4) or UDim2.fromScale(0.5, 0.7)
	label.Size = UDim2.new(1.6, 0, 0, math.floor(size * (labelBelow and 0.2 or 0.17)))
	label.FontFace = Gui.display(Enum.FontWeight.Heavy)
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.45
	label.Text = ""
	label.Parent = b
	local entry = { button = b, ring = ring, icon = icon, label = label, action = nil, enabled = true }
	buttons[name] = entry
	b.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if not entry.action or not entry.enabled then
			return
		end
		b.BackgroundTransparency = PRESSED
		held[name] = { input = input, action = entry.action, t0 = os.clock() }
		mods.ActionController.press(entry.action)
	end)
	return entry
end

local function releaseInput(input)
	for name, h in pairs(held) do
		if h.input == input then
			held[name] = nil
			local entry = buttons[name]
			entry.button.BackgroundTransparency = entry.enabled and REST or OFF
			mods.ActionController.release(h.action)
		end
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

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "SpikeRushTouch"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")
	root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function rescale()
		local cam = workspace.CurrentCamera
		if cam then
			scale.Scale = math.clamp(cam.ViewportSize.Y / 720, 0.7, 1.1)
		end
	end
	rescale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- the three big buttons, bottom right, and the pop-ups over the middle and right ones
	roundButton("A", 124, UDim2.new(1, -404, 1, -104))
	roundButton("B", 124, UDim2.new(1, -254, 1, -104))
	roundButton("C", 124, UDim2.new(1, -104, 1, -104))
	roundButton("Set", 86, UDim2.new(1, -254, 1, -244))
	roundButton("Block", 86, UDim2.new(1, -104, 1, -244))
	-- the skill column, left
	for i = 1, 3 do
		roundButton("Skill" .. i, 76, UDim2.new(0, 70, 0.3, (i - 1) * 118), true)
	end
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

local function update()
	local show = State.isMobile and State.isPlaying and State.match.inMatch == true
	gui.Enabled = show
	if not show then
		return
	end
	hideDefaultJump()
	local ctx = State.context or {}
	local air = ctx.grounded == false
	if ctx.serving then
		local holding = ctx.spikeLabel == "Toss"
		set("A", holding and "EasyServe" or nil, "Basic Serve", "IconStar")
		set("B", holding and "Serve" or nil, "Spike Serve", "IconAttack")
		set("C", "Spike", air and "Spike" or "Approach", air and "IconAttack" or "IconJump")
		set("Set", nil)
		set("Block", nil)
		-- the spike serve's toss charges while held: the ring warms to orange
		local h = held.B
		if h and h.action == "Serve" then
			local k = math.clamp((os.clock() - h.t0 - Config.Player.ServeTapTime) / Config.Hits.TossChargeTime, 0, 1)
			ring("B", WHITE:Lerp(ORANGE, k), k > 0)
		else
			ring("B", nil, false)
		end
		ring("C", UI.Spark, ctx.inZone == true)
	else
		set("A", "SlideFeint", "Slide", "IconSpeed", not air)
		if air then
			set("B", "SlideFeint", "Feint", "IconDefense")
			set("C", "Spike", ctx.spikeLabel == "Charge" and "Charge" or "Spike", "IconAttack")
		else
			set("B", "Receive", "Bump", "IconDefense")
			set("C", "Spike", "Approach", "IconJump")
		end
		set("Set", ctx.canSet == true and "Set" or nil, "Set", "IconStar")
		set("Block", (ctx.nearNet == true and not air) and "Block" or nil, "Block", "IconDefense")
		ring("A", nil, false)
		ring("B", UI.Spark, ctx.incoming == true and not air)
		ring("C", UI.Spark, ctx.inZone == true)
		ring("Set", UI.Spark, ctx.canSet == true)
		ring("Block", nil, false)
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
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(update)
		if not ok then
			warn("[SpikeRush] touch: " .. tostring(err))
		end
	end)
end

return MobileControls
