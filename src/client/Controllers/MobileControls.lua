-- Touch controls, mirroring the keyboard layout:
--   SPIKE ........ ground: run-up jump / air: spike (hold to charge with Azure Dragon)
--   RECEIVE ...... arm the receive stance (press a little early)
--   SLIDE ........ ground: slide receive / air: feint
--   BLOCK ........ hold to charge, release to jump
--   SET .......... set the ball (lean the thumbstick toward the net for a quick, away for a back set)
--   SERVE ........ tap = overhand serve, hold = jump-serve toss (appears when you serve)
--   JUMP ......... a plain jump
-- The default thumbstick moves you along the court; its jump button is replaced by ours.
-- Holds release when the finger lifts anywhere on screen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local State = require(script.Parent.State)

local MobileControls = {}
local mods

local player = Players.LocalPlayer
local UI = Config.UI
local gui, root = nil, nil
local buttons = {}
local held = {}

local function circle(name, text, size, x, y, color)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Font = Enum.Font.GothamBlack
	b.TextSize = math.floor(size * 0.17)
	b.TextColor3 = UI.Chalk
	b.AutoButtonColor = false
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.new(1, -x, 1, -y)
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.22
	b.Parent = root
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = UI.Ink
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	buttons[name] = { button = b, stroke = s, base = color }
	return b
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function bind(name, action)
	local b = buttons[name].button
	b.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		b.BackgroundTransparency = 0.02
		held[name] = { input = input, action = action }
		if action == "Jump" then
			mods.MovementController.jump("Jump")
		else
			mods.ActionController.press(action)
		end
	end)
end

local function releaseInput(input)
	for name, h in pairs(held) do
		if h.input == input then
			held[name] = nil
			buttons[name].button.BackgroundTransparency = 0.22
			if h.action ~= "Jump" then
				mods.ActionController.release(h.action)
			end
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

	circle("Spike", "Spike", 124, 110, 120, Color3.fromRGB(235, 70, 60))
	circle("Receive", "Receive", 92, 240, 80, Color3.fromRGB(50, 130, 235))
	circle("Slide", "Slide", 82, 205, 190, Color3.fromRGB(70, 180, 140))
	circle("Block", "Block", 82, 95, 255, Color3.fromRGB(120, 110, 220))
	circle("Set", "Set", 72, 320, 170, Color3.fromRGB(240, 170, 60))
	circle("Serve", "Serve", 88, 300, 270, Color3.fromRGB(245, 200, 40))
	circle("Jump", "Jump", 64, 350, 70, UI.InkSoft)

	bind("Spike", "Spike")
	bind("Receive", "Receive")
	bind("Slide", "SlideFeint")
	bind("Block", "Block")
	bind("Set", "Set")
	bind("Serve", "Serve")
	bind("Jump", "Jump")
	UserInputService.InputEnded:Connect(releaseInput)
end

local function glow(name, on)
	local b = buttons[name]
	if b then
		b.stroke.Color = on and UI.Spark or UI.Ink
		b.stroke.Thickness = on and 5 or 3
	end
end

local function update()
	local show = State.isMobile and State.isPlaying and State.match.inMatch == true
	gui.Enabled = show
	if not show then
		return
	end
	hideDefaultJump()
	local ctx = State.context or {}
	buttons.Spike.button.Text = ctx.spikeLabel or "Spike"
	glow("Spike", ctx.inZone == true)
	glow("Receive", ctx.incoming == true and ctx.grounded == true)
	glow("Set", ctx.canSet == true)
	buttons.Slide.button.Text = ctx.grounded == false and "Feint" or "Slide"
	buttons.Block.button.BackgroundTransparency = (ctx.nearNet and not held.Block) and 0.22 or 0.55
	buttons.Serve.button.Visible = ctx.serving == true
	buttons.Set.button.Visible = State.teamSize() > 1 or ctx.canSet == true
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
