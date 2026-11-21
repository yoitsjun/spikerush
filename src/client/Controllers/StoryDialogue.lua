-- Story mode's dialogue (the owner's reference clip, 2026-11-10: a Roblox avatar standing left
-- of the screen in front of a gym, its name in thin yellow italics, the line typing out under
-- it, a new pose for each line and emotes over its head; laid out after The Spike Cross's
-- scenes: up to three on screen, the speaker lit and the others dimmed, a title card as a stage
-- opens, narration between scenes).
--
-- A scene is a list of steps (StoryScript says how they read). The faces are rigs built from
-- Config.Story.Cast (StoryLook), each in its own ViewportFrame, posed with AnimationController's
-- static posing and blended from pose to pose. The backdrop is one of the menu's 3D scenes (the
-- school gym, the arena) or a painted one (dusk, beach, black).
--
-- StoryDialogue.play(scene, opts, onDone): opts.title = { label, name } shows the title card
-- first. Click, tap, Space, Enter or a controller's A goes on; Skip leaves. onDone(skipped).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Story = require(Shared.Story)
local StoryLook = require(Shared.StoryLook)
local Gui = require(script.Parent.Gui)

local StoryDialogue = {}
local mods

local player = Players.LocalPlayer
local make = Gui.make
local rad = math.rad

local NAME_COLOR = Color3.fromRGB(255, 214, 92)
local HOT = "#FFB43C" -- {braces} in a line
local DIM = Color3.fromRGB(58, 60, 76) -- everyone who isn't speaking
local TYPE_SPEED = 46 -- letters a second
local BLEND = 0.26 -- seconds from one pose to the next
local ACTOR_W, ACTOR_H = 620, 860
local CAM_Y, CAM_DIST, CAM_FOV = 0.85, 10.6, 30 -- (from the thighs up: the first cut was all face)

-- where the faces stand, as fractions of the screen's width, for one, two and three of them
local SLOTS = { { 0.24 }, { 0.24, 0.76 }, { 0.2, 0.5, 0.8 } }

------------------------------------------------------------------------------------------
-- poses (joint angles in degrees, as AnimationController's: shoulders X forward and up, Y a
-- twist inward, Z out to the side; elbows X bend; Waist -X leans forward; Neck -X looks down)
------------------------------------------------------------------------------------------

local POSE_DEFS = {
	Idle = {
		Neck = { 3, 0, 0 },
		LeftShoulder = { 6, 0, -7 },
		RightShoulder = { 6, 0, 7 },
		LeftElbow = { 14, 0, 0 },
		RightElbow = { 14, 0, 0 },
	},
	-- a hand to the chin, the other arm folded under it
	Think = {
		Waist = { -2, 6, 0 },
		Neck = { -8, -6, 5 },
		RightShoulder = { 50, 52, 6 },
		RightElbow = { 138, 0, 0 },
		LeftShoulder = { 14, -76, -4 },
		LeftElbow = { 96, 0, 0 },
	},
	-- arms folded
	Cross = {
		Waist = { 4, 0, 0 },
		Neck = { 8, 0, 5 },
		LeftShoulder = { 12, -75, -4 },
		LeftElbow = { 95, 0, 0 },
		RightShoulder = { 22, 75, 4 },
		RightElbow = { 92, 0, 0 },
	},
	-- both arms up in front of the chest, shrinking back
	Shy = {
		Waist = { -6, 0, 0 },
		Neck = { -12, 0, 0 },
		LeftShoulder = { 44, -58, 0 },
		LeftElbow = { 124, 0, 0 },
		RightShoulder = { 44, 58, 0 },
		RightElbow = { 124, 0, 0 },
	},
	-- a hand behind the head
	Scratch = {
		Waist = { 0, -6, 0 },
		Neck = { -4, 4, -8 },
		RightShoulder = { 162, 0, 30 },
		RightElbow = { 142, 0, 0 },
		LeftShoulder = { 6, 0, -8 },
		LeftElbow = { 16, 0, 0 },
	},
	Wave = {
		Neck = { 6, 0, -5 },
		RightShoulder = { 152, 0, 34 },
		RightElbow = { 38, 0, 0 },
		LeftShoulder = { 6, 0, -8 },
		LeftElbow = { 14, 0, 0 },
	},
	-- pointing, the free hand on the hip
	Point = {
		Waist = { 2, 14, 0 },
		Neck = { 6, -10, 0 },
		RightShoulder = { 96, -14, 10 },
		RightElbow = { 6, 0, 0 },
		LeftShoulder = { -15, -50, -40 },
		LeftElbow = { 95, 0, 0 },
	},
	-- a fist up at the chest
	Fist = {
		Waist = { 4, -8, 0 },
		Neck = { 10, 6, 0 },
		RightShoulder = { 62, 10, 22 },
		RightElbow = { 126, 0, 0 },
		LeftShoulder = { 10, 0, -14 },
		LeftElbow = { 34, 0, 0 },
	},
	-- both arms in the air
	Cheer = {
		Waist = { 6, 0, 0 },
		Neck = { 14, 0, 0 },
		LeftShoulder = { 164, 0, -26 },
		LeftElbow = { 18, 0, 0 },
		RightShoulder = { 164, 0, 26 },
		RightElbow = { 18, 0, 0 },
	},
	Shrug = {
		Neck = { 2, 0, 8 },
		LeftShoulder = { 12, 62, -26 },
		LeftElbow = { 92, 0, 0 },
		RightShoulder = { 12, -62, 26 },
		RightElbow = { 92, 0, 0 },
	},
	-- hands on the hips
	Hips = {
		Waist = { 4, 0, 0 },
		Neck = { 8, 0, 0 },
		LeftShoulder = { -15, -50, -40 },
		LeftElbow = { 95, 0, 0 },
		RightShoulder = { -15, 50, 40 },
		RightElbow = { 95, 0, 0 },
	},
	-- shoulders down, head down
	Slump = {
		Waist = { -16, 0, 0 },
		Neck = { -20, 0, 0 },
		LeftShoulder = { 10, 0, -3 },
		RightShoulder = { 10, 0, 3 },
		LeftElbow = { 6, 0, 0 },
		RightElbow = { 6, 0, 0 },
	},
}

local POSES = {}
for name, def in pairs(POSE_DEFS) do
	local joints = {}
	for joint, a in pairs(def) do
		joints[joint] = CFrame.Angles(rad(a[1]), rad(a[2]), rad(a[3]))
	end
	POSES[name] = joints
end

function StoryDialogue.poses()
	return POSES
end

-- Every joint of either pose, a to b at t.
local function blend(a, b, t)
	local out = {}
	for joint, cf in pairs(a) do
		out[joint] = cf:Lerp(b[joint] or CFrame.identity, t)
	end
	for joint, cf in pairs(b) do
		if not a[joint] then
			out[joint] = CFrame.identity:Lerp(cf, t)
		end
	end
	return out
end

------------------------------------------------------------------------------------------
-- the screen
------------------------------------------------------------------------------------------

local FACE_NAME = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Light, Enum.FontStyle.Italic)
local FACE_LINE = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Light, Enum.FontStyle.Italic)
local FACE_NOTE = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
local FACE_BOLD = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

local gui, canvas, canvasScale
local ui = {}
local actors = {} -- cast id -> { id, vp, rig, cam, from, to, t0, yaw, phase, x, on, emotes, scale }
local onStage = {} -- the ids standing now, left to right
local session = nil -- the scene playing: { cancelled, advance, skipped }
local backdrop = nil
local conn = nil

local function tween(obj, time, props, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function layout()
	local cam = workspace.CurrentCamera
	if not cam or not canvas then
		return
	end
	local vs = cam.ViewportSize
	if vs.X < 2 or vs.Y < 2 then
		return
	end
	local s = math.clamp(vs.Y / 900, 0.4, 1.8)
	if vs.X / s < 1100 then
		s = vs.X / 1100
	end
	canvasScale.Scale = s
	canvas.Size = UDim2.fromOffset(vs.X / s, vs.Y / s)
end

-- A painted backdrop: bands of colour top to bottom, each { from, to, colour top, colour bottom }.
local function bands(parent, list)
	for _, b in ipairs(list) do
		local f = make("Frame", { Position = UDim2.fromScale(0, b[1]), Size = UDim2.fromScale(1, b[2] - b[1]), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, parent)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(b[3], b[4]) }, f)
	end
end

local function paintDusk(parent)
	bands(parent, {
		{ 0, 0.5, Color3.fromRGB(44, 34, 86), Color3.fromRGB(196, 96, 104) },
		{ 0.5, 0.74, Color3.fromRGB(196, 96, 104), Color3.fromRGB(255, 182, 110) },
		{ 0.74, 1, Color3.fromRGB(46, 36, 56), Color3.fromRGB(22, 18, 30) },
	})
	-- a skyline: dark blocks with a few lit windows
	local W = { 0.07, 0.05, 0.09, 0.06, 0.04, 0.08, 0.06, 0.1, 0.05, 0.07, 0.09, 0.05, 0.08, 0.06, 0.07 }
	local H = { 0.2, 0.31, 0.16, 0.26, 0.36, 0.22, 0.3, 0.18, 0.28, 0.4, 0.2, 0.33, 0.24, 0.3, 0.19 }
	local x = -0.01
	for i, w in ipairs(W) do
		local h = H[i]
		local b = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(x, 0.75), Size = UDim2.fromScale(w, h), BackgroundColor3 = Color3.fromRGB(38, 30, 58):Lerp(Color3.fromRGB(70, 46, 76), (i % 3) / 3), BorderSizePixel = 0 }, parent)
		for k = 1, 5 do
			local wx = ((i * 37 + k * 53) % 70) / 100 + 0.1
			local wy = ((i * 29 + k * 41) % 75) / 100 + 0.08
			make("Frame", { Position = UDim2.fromScale(wx, wy), Size = UDim2.fromScale(0.12, 0.035), BackgroundColor3 = Color3.fromRGB(255, 214, 140), BackgroundTransparency = 0.25, BorderSizePixel = 0 }, b)
		end
		x = x + w + 0.004
	end
	-- the rooftop's rail
	make("Frame", { Position = UDim2.fromScale(0, 0.745), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Color3.fromRGB(16, 14, 24), BorderSizePixel = 0 }, parent)
end

local function paintBeach(parent)
	bands(parent, {
		{ 0, 0.52, Color3.fromRGB(255, 150, 104), Color3.fromRGB(255, 216, 150) },
		{ 0.52, 0.66, Color3.fromRGB(60, 150, 170), Color3.fromRGB(28, 96, 128) },
		{ 0.66, 1, Color3.fromRGB(236, 204, 150), Color3.fromRGB(190, 150, 104) },
	})
	local sun = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.68, 0.47), Size = UDim2.fromOffset(190, 190), BackgroundColor3 = Color3.fromRGB(255, 240, 200), BorderSizePixel = 0 }, parent)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, sun)
	-- the sea in front of the sun's lower half, and its light on the water
	local sea = make("Frame", { Position = UDim2.fromScale(0, 0.52), Size = UDim2.fromScale(1, 0.14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, parent)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(60, 150, 170), Color3.fromRGB(28, 96, 128)) }, sea)
	for i = 1, 5 do
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.68, 0.53 + i * 0.02), Size = UDim2.new(0.2 - i * 0.025, 0, 0, 4), BackgroundColor3 = Color3.fromRGB(255, 230, 180), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, parent)
	end
	-- a net post and the net's tape, far off
	make("Frame", { Position = UDim2.fromScale(0.86, 0.5), Size = UDim2.new(0, 8, 0.2, 0), BackgroundColor3 = Color3.fromRGB(70, 50, 44), BorderSizePixel = 0 }, parent)
	make("Frame", { Position = UDim2.fromScale(0.42, 0.52), Size = UDim2.new(0.44, 0, 0, 5), BackgroundColor3 = Color3.fromRGB(250, 246, 236), BorderSizePixel = 0 }, parent)
end

-- A pine silhouette: stepped tiers narrowing to the top, `w` wide and `h` tall, its foot at (x, y)
-- (scale of the backdrop), capped with snow.
local function pineAt(parent, x, y, w, h, color)
	local tiers = 5
	for i = 0, tiers - 1 do
		local tw = w * (1 - i / tiers)
		local th = h / tiers * 1.15
		make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, y - i * h / tiers), Size = UDim2.fromScale(tw, th), BackgroundColor3 = color, BorderSizePixel = 0 }, parent)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(x, y - i * h / tiers - th + th * 0.22), Size = UDim2.fromScale(tw * 0.8, th * 0.22), BackgroundColor3 = Color3.fromRGB(236, 244, 255), BackgroundTransparency = 0.1, BorderSizePixel = 0 }, parent)
	end
end

-- Snow at night (the Winter story: Snowfall Lodge's clearing): a deep blue sky, the moon, pines,
-- a strand of Christmas lights, the snow on the ground and flakes in the air.
local function paintSnow(parent)
	bands(parent, {
		{ 0, 0.62, Color3.fromRGB(8, 14, 40), Color3.fromRGB(40, 70, 130) },
		{ 0.62, 1, Color3.fromRGB(214, 228, 246), Color3.fromRGB(170, 192, 226) },
	})
	local moon = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.78, 0.18), Size = UDim2.fromOffset(150, 150), BackgroundColor3 = Color3.fromRGB(244, 248, 255), BorderSizePixel = 0 }, parent)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, moon)
	local trees = { { 0.04, 0.12, 0.3 }, { 0.14, 0.09, 0.22 }, { 0.26, 0.11, 0.27 }, { 0.62, 0.1, 0.24 }, { 0.73, 0.13, 0.32 }, { 0.86, 0.1, 0.25 }, { 0.96, 0.12, 0.29 } }
	for i, t in ipairs(trees) do
		pineAt(parent, t[1], 0.64, t[2], t[3], (i % 2 == 0) and Color3.fromRGB(16, 52, 40) or Color3.fromRGB(12, 40, 32))
	end
	-- a strand of lights sagging across the top
	local LIGHTS = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(90, 230, 120), Color3.fromRGB(255, 206, 80), Color3.fromRGB(90, 170, 255) }
	for i = 0, 30 do
		local u = i / 30
		local y = 0.05 + 0.05 * math.sin((u * 3 % 1) * math.pi)
		local b = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(u, y), Size = UDim2.fromOffset(12, 18), BackgroundColor3 = LIGHTS[i % #LIGHTS + 1], BorderSizePixel = 0 }, parent)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
	end
	-- flakes, scattered the same way every time
	for i = 1, 70 do
		local x = ((i * 37) % 100) / 100
		local y = ((i * 53) % 97) / 100
		local d = 3 + (i % 4) * 2
		local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(d, d), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.15 + (i % 3) * 0.2, BorderSizePixel = 0 }, parent)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	end
end

-- The lodge at night (the Winter story): log walls in firelight, the fireplace, a window on the
-- snow, a garland of lights along the mantel.
local function paintLodge(parent)
	bands(parent, {
		{ 0, 0.72, Color3.fromRGB(70, 40, 26), Color3.fromRGB(120, 70, 40) },
		{ 0.72, 1, Color3.fromRGB(90, 54, 32), Color3.fromRGB(50, 30, 20) },
	})
	-- the logs
	for i = 0, 8 do
		make("Frame", { Position = UDim2.fromScale(0, i * 0.08), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = Color3.fromRGB(46, 26, 16), BackgroundTransparency = 0.4, BorderSizePixel = 0 }, parent)
	end
	-- the window: night and snow
	local win = make("Frame", { Position = UDim2.fromScale(0.08, 0.14), Size = UDim2.fromScale(0.22, 0.34), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, parent)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(12, 20, 54), Color3.fromRGB(60, 90, 150)) }, win)
	make("UIStroke", { Color = Color3.fromRGB(40, 22, 14), Thickness = 8 }, win)
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 22, 14), BorderSizePixel = 0 }, win)
	make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Color3.fromRGB(40, 22, 14), BorderSizePixel = 0 }, win)
	for i = 1, 16 do
		local f = make("Frame", { Position = UDim2.fromScale(((i * 29) % 100) / 100, ((i * 47) % 90) / 100), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, win)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	end
	make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.18), BackgroundColor3 = Color3.fromRGB(226, 236, 250), BorderSizePixel = 0 }, win)
	-- the fireplace: stone, the hearth's glow and the flames
	local fire = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.66, 0.74), Size = UDim2.fromScale(0.3, 0.42), BackgroundColor3 = Color3.fromRGB(96, 90, 92), BorderSizePixel = 0 }, parent)
	local hearth = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.62, 0.62), BackgroundColor3 = Color3.fromRGB(20, 12, 10), BorderSizePixel = 0 }, fire)
	make("UICorner", { CornerRadius = UDim.new(0.3, 0) }, hearth)
	for i, c in ipairs({ { 0.5, 0.7, Color3.fromRGB(255, 120, 30) }, { 0.38, 0.5, Color3.fromRGB(255, 170, 50) }, { 0.62, 0.55, Color3.fromRGB(255, 200, 80) } }) do
		local flame = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(c[1], 0.95), Size = UDim2.fromScale(0.2, c[2]), BackgroundColor3 = c[3], BorderSizePixel = 0, Rotation = (i - 2) * 8 }, hearth)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, flame)
	end
	make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.66, 0.33), Size = UDim2.fromScale(0.36, 0.035), BackgroundColor3 = Color3.fromRGB(70, 40, 24), BorderSizePixel = 0 }, parent)
	-- a garland with lights along the mantel
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.66, 0.335), Size = UDim2.fromScale(0.38, 0.025), BackgroundColor3 = Color3.fromRGB(30, 100, 56), BorderSizePixel = 0 }, parent)
	local LIGHTS = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 206, 80), Color3.fromRGB(90, 170, 255) }
	for i = 0, 12 do
		local b = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.48 + i * 0.03, 0.34 + ((i % 2 == 0) and 0.008 or -0.004)), Size = UDim2.fromOffset(10, 14), BackgroundColor3 = LIGHTS[i % #LIGHTS + 1], BorderSizePixel = 0 }, parent)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
	end
	-- the fire's warmth over the room
	local glow = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 150, 60), BackgroundTransparency = 0.88, BorderSizePixel = 0 }, parent)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.66, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, glow)
end

local function build()
	gui = make("ScreenGui", { Name = "SpikeRushStoryDialogue", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 58, Enabled = false }, player:WaitForChild("PlayerGui"))
	-- the painted backdrops fill the screen; the rest sits on a 900-high canvas
	ui.paint = make("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Visible = false, ZIndex = 1, ClipsDescendants = true }, gui)
	ui.painted = {
		black = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Visible = false }, ui.paint),
		dusk = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, ui.paint),
		beach = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, ui.paint),
		snow = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, ui.paint),
		lodge = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, ui.paint),
	}
	paintDusk(ui.painted.dusk)
	paintBeach(ui.painted.beach)
	paintSnow(ui.painted.snow)
	paintLodge(ui.painted.lodge)

	canvas = make("Frame", { Name = "Canvas", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), BackgroundTransparency = 1, ZIndex = 2 }, gui)
	canvasScale = make("UIScale", {}, canvas)
	ui.stage = make("Frame", { Name = "Stage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, canvas)

	-- the dark band the lines sit on
	local band = make("Frame", { Name = "Band", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 470), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 5 }, canvas)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 0.42), NumberSequenceKeypoint.new(1, 0.12) }) }, band)
	ui.band = band

	ui.emotes = make("Frame", { Name = "Emotes", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4 }, canvas)

	ui.name = make("TextLabel", { Name = "Name", BackgroundTransparency = 1, FontFace = FACE_NAME, TextSize = 46, TextColor3 = NAME_COLOR, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, Position = UDim2.new(0, 96, 1, -292), Size = UDim2.fromOffset(700, 54), Text = "", ZIndex = 6 }, canvas)
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.2, Transparency = 0.55 }, ui.name)
	ui.line = make("TextLabel", { Name = "Line", BackgroundTransparency = 1, FontFace = FACE_LINE, TextSize = 33, TextColor3 = Color3.fromRGB(246, 247, 250), RichText = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.new(0, 120, 1, -228), Size = UDim2.new(1, -420, 0, 170), Text = "", ZIndex = 6 }, canvas)
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.2, Transparency = 0.5 }, ui.line)
	make("UISizeConstraint", { MaxSize = Vector2.new(1180, 170) }, ui.line)
	-- the "go on" mark after a finished line
	ui.more = make("TextLabel", { Name = "More", BackgroundTransparency = 1, FontFace = FACE_BOLD, TextSize = 24, TextColor3 = NAME_COLOR, Text = "▼", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -96, 1, -56), Size = UDim2.fromOffset(30, 30), Visible = false, ZIndex = 6 }, canvas)

	-- the title card
	local card = make("Frame", { Name = "Card", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.27), Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0, Visible = false, ZIndex = 8 }, canvas)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }) }, card)
	ui.card = card
	ui.cardLabel = make("TextLabel", { BackgroundTransparency = 1, FontFace = FACE_NOTE, TextSize = 26, TextColor3 = NAME_COLOR, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 30), Text = "", ZIndex = 9 }, card)
	ui.cardName = make("TextLabel", { BackgroundTransparency = 1, FontFace = FACE_LINE, TextSize = 58, TextColor3 = Color3.fromRGB(246, 247, 250), Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 66), Text = "", ZIndex = 9 }, card)

	-- taps anywhere go on; Skip sits over it
	ui.tap = make("TextButton", { Name = "Tap", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 7 }, canvas)
	ui.tap.MouseButton1Click:Connect(function()
		if session then
			session.advance = true
		end
	end)
	ui.skip = make("TextButton", { Name = "Skip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 64), Size = UDim2.fromOffset(112, 44), BackgroundColor3 = Color3.fromRGB(10, 12, 28), BackgroundTransparency = 0.35, BorderSizePixel = 0, Text = "Skip  ▶▶", FontFace = FACE_BOLD, TextSize = 18, TextColor3 = Color3.fromRGB(230, 232, 240), AutoButtonColor = false, ZIndex = 10 }, canvas)
	make("UIStroke", { Color = Color3.fromRGB(230, 232, 240), Thickness = 1, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ui.skip)
	ui.skip.MouseButton1Click:Connect(function()
		if session then
			session.skipped = true
			session.cancelled = true
		end
	end)

	-- the fade between backdrops and at both ends
	ui.fade = make("Frame", { Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20 }, gui)

	layout()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
end

------------------------------------------------------------------------------------------
-- the faces
------------------------------------------------------------------------------------------

local function newActor(id)
	local model = StoryLook.build(id) -- (yields)
	if not model then
		return nil
	end
	local rig = mods.AnimationController.rig(model)
	if not rig then
		model:Destroy()
		return nil
	end
	local vp = make("ViewportFrame", {
		Name = "Actor_" .. id,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 40),
		Size = UDim2.fromOffset(ACTOR_W, ACTOR_H),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 150, 164),
		LightColor = Color3.fromRGB(255, 244, 226),
		LightDirection = Vector3.new(-0.45, -0.6, 0.65),
		ImageTransparency = 1,
		Visible = false,
		ZIndex = 3,
	}, ui.stage)
	local cam = make("Camera", { FieldOfView = CAM_FOV, CFrame = CFrame.lookAt(Vector3.new(0, CAM_Y, -CAM_DIST), Vector3.new(0, CAM_Y, 0)) }, vp)
	vp.CurrentCamera = cam
	rig.model.Parent = vp
	local a = { id = id, vp = vp, rig = rig, cam = cam, from = POSES.Idle, to = POSES.Idle, t0 = 0, yaw = 0, phase = (#id * 1.7) % 6, on = false, x = 0.5 }
	a.emotes = make("Frame", { Name = "Emote_" .. id, AnchorPoint = Vector2.new(0.5, 1), Position = vp.Position, Size = vp.Size, BackgroundTransparency = 1, ZIndex = 4 }, ui.emotes)
	mods.AnimationController.poseModel(rig, POSES.Idle, CFrame.identity)
	return a
end

-- Build every face a scene uses before it starts (each build yields), all at once.
local function preload(scene)
	local want = {}
	for _, step in ipairs(scene) do
		if type(step[1]) == "string" then
			want[step[1]] = true
		end
		for _, id in ipairs(step.on or {}) do
			want[id] = true
		end
	end
	local pending = 0
	for id in pairs(want) do
		if actors[id] == nil then
			pending = pending + 1
			actors[id] = false
			task.spawn(function()
				local ok, a = pcall(newActor, id)
				actors[id] = (ok and a) or false
				pending = pending - 1
			end)
		end
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 12 do
		task.wait()
	end
end

local function step(now)
	for _, a in pairs(actors) do
		if a and a.on then
			local t = math.clamp((now - a.t0) / BLEND, 0, 1)
			t = t * t * (3 - 2 * t)
			local joints = blend(a.from, a.to, t)
			-- breathing, so nobody stands frozen
			local breath = math.sin(now * 1.7 + a.phase)
			joints.Waist = (joints.Waist or CFrame.identity) * CFrame.Angles(rad(breath * 0.9), 0, 0)
			joints.Neck = (joints.Neck or CFrame.identity) * CFrame.Angles(rad(-breath * 0.6), 0, rad(math.sin(now * 0.9 + a.phase) * 0.8))
			mods.AnimationController.poseModel(a.rig, joints, CFrame.Angles(0, rad(a.yaw), 0))
		end
	end
end

local function setPose(a, name)
	local to = POSES[name or "Idle"] or POSES.Idle
	if to == a.to then
		return
	end
	local now = os.clock()
	local t = math.clamp((now - a.t0) / BLEND, 0, 1)
	a.from = blend(a.from, a.to, t * t * (3 - 2 * t))
	a.to = to
	a.t0 = now
end

local function clearEmotes(a)
	if a and a.emotes then
		a.emotes:ClearAllChildren()
	end
end

-- Who stands on screen, left to right: the ones already there slide to their new places, the new
-- ones fade in, the rest fade out.
local function setStage(ids)
	local list = {}
	for _, id in ipairs(ids) do
		if actors[id] and #list < 3 then
			table.insert(list, id)
		end
	end
	local keep = {}
	local slots = SLOTS[math.max(1, #list)]
	for i, id in ipairs(list) do
		local a = actors[id]
		keep[id] = true
		local x = slots[i]
		-- each turns a little toward the middle of the screen
		a.yaw = (0.5 - x) * 70 + (x == 0.5 and 0 or 0)
		local pos = UDim2.new(x, 0, 1, 40)
		if not a.on then
			a.on = true
			a.x = x
			a.vp.Visible = true
			a.vp.Position = pos + UDim2.fromOffset(x < 0.5 and -50 or 50, 0)
			a.vp.ImageTransparency = 1
			a.vp.ImageColor3 = DIM
			a.from, a.to, a.t0 = POSES.Idle, POSES.Idle, 0
			tween(a.vp, 0.3, { Position = pos, ImageTransparency = 0 })
		else
			a.x = x
			tween(a.vp, 0.3, { Position = pos })
		end
		a.emotes.Position = pos
	end
	for id, a in pairs(actors) do
		if a and a.on and not keep[id] then
			a.on = false
			clearEmotes(a)
			local vp = a.vp
			local t = tween(vp, 0.22, { ImageTransparency = 1 })
			t.Completed:Connect(function()
				if not a.on then
					vp.Visible = false
				end
			end)
		end
	end
	onStage = list
end

local function light(speaker)
	for _, id in ipairs(onStage) do
		local a = actors[id]
		if a then
			local lit = speaker == nil or id == speaker
			a.vp.ZIndex = (id == speaker) and 4 or 3
			tween(a.vp, 0.2, { ImageColor3 = lit and Color3.new(1, 1, 1) or DIM })
		end
	end
end

------------------------------------------------------------------------------------------
-- emotes, drawn over a face's head
------------------------------------------------------------------------------------------

local EMOTES = {}

local function pop(f)
	local s = make("UIScale", { Scale = 0.2 }, f)
	tween(s, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	return s
end

-- A speech bubble with a few letters in it, up and to the right of the head.
local function bubble(a, text, color)
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.74, 0.12), Size = UDim2.fromOffset(#text > 1 and 132 or 96, 92), BackgroundColor3 = Color3.fromRGB(250, 250, 252), BorderSizePixel = 0, ZIndex = 4 }, a.emotes)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	make("UIStroke", { Color = Color3.fromRGB(26, 26, 34), Thickness = 3 }, f)
	local tail = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.2, 0.93), Size = UDim2.fromOffset(22, 22), Rotation = 45, BackgroundColor3 = Color3.fromRGB(250, 250, 252), BorderSizePixel = 0, ZIndex = 3 }, f)
	make("UIStroke", { Color = Color3.fromRGB(26, 26, 34), Thickness = 3 }, tail)
	-- (the bubble's own fill again over the tail's top edge)
	local cover = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -6, 1, -6), BackgroundColor3 = Color3.fromRGB(250, 250, 252), BorderSizePixel = 0, ZIndex = 4 }, f)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, cover)
	make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), FontFace = FACE_BOLD, TextSize = 50, TextColor3 = color or Color3.fromRGB(26, 26, 34), Text = text, ZIndex = 5 }, f)
	pop(f)
	return f
end

EMOTES["!"] = function(a)
	bubble(a, "!", Color3.fromRGB(230, 60, 60))
end
EMOTES["?"] = function(a)
	bubble(a, "?")
end
EMOTES["..."] = function(a)
	bubble(a, "...")
end
EMOTES[":3"] = function(a)
	bubble(a, ":3")
end
EMOTES.note = function(a)
	bubble(a, "♪", Color3.fromRGB(240, 110, 170))
end

-- A sweat drop by the temple.
EMOTES.sweat = function(a)
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.3, 0.2), Size = UDim2.fromOffset(46, 66), BackgroundTransparency = 1, ZIndex = 4 }, a.emotes)
	local tip = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(28, 28), Rotation = 45, BackgroundColor3 = Color3.fromRGB(120, 200, 255), BorderSizePixel = 0, ZIndex = 4 }, f)
	make("UIStroke", { Color = Color3.fromRGB(30, 80, 150), Thickness = 3 }, tip)
	local drop = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.64), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = Color3.fromRGB(120, 200, 255), BorderSizePixel = 0, ZIndex = 5 }, f)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, drop)
	make("UIStroke", { Color = Color3.fromRGB(30, 80, 150), Thickness = 3 }, drop)
	-- (the tip's fill again over the circle's top edge, and a shine)
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(22, 22), Rotation = 45, BackgroundColor3 = Color3.fromRGB(120, 200, 255), BorderSizePixel = 0, ZIndex = 6 }, f)
	local shine = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.36, 0.62), Size = UDim2.fromOffset(9, 15), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 7 }, f)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
	pop(f)
	tween(f, 1.1, { Position = UDim2.fromScale(0.3, 0.25) }, Enum.EasingStyle.Sine)
end

-- Gloom: dark lines hanging over the head.
EMOTES.gloom = function(a)
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.42, 0.06), Size = UDim2.fromOffset(120, 80), BackgroundTransparency = 1, ZIndex = 4 }, a.emotes)
	local H = { 46, 70, 56, 76, 40 }
	for i, h in ipairs(H) do
		local bar = make("Frame", { Position = UDim2.fromOffset((i - 1) * 24, 0), Size = UDim2.fromOffset(9, 0), BackgroundColor3 = Color3.fromRGB(70, 84, 170), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 4 }, f)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bar)
		tween(bar, 0.35 + i * 0.05, { Size = UDim2.fromOffset(9, h) })
	end
end

-- An anger mark: four red hooks round a gap.
EMOTES.anger = function(a)
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.7, 0.14), Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, ZIndex = 4 }, a.emotes)
	local RED = Color3.fromRGB(236, 52, 60)
	for i = 0, 3 do
		local arm = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = i * 90, ZIndex = 4 }, f)
		local v = make("Frame", { Position = UDim2.fromScale(0.58, 0.04), Size = UDim2.fromScale(0.13, 0.36), BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 4 }, arm)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, v)
		local h = make("Frame", { Position = UDim2.fromScale(0.58, 0.29), Size = UDim2.fromScale(0.36, 0.13), BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 4 }, arm)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, h)
	end
	local s = pop(f)
	task.delay(0.3, function()
		if s.Parent then
			tween(s, 0.5, { Scale = 0.86 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end)
end

-- A blush: two pink marks on the cheeks.
EMOTES.blush = function(a)
	for _, x in ipairs({ 0.44, 0.56 }) do
		local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.325), Size = UDim2.fromOffset(40, 20), BackgroundColor3 = Color3.fromRGB(255, 120, 150), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, a.emotes)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
		tween(f, 0.4, { BackgroundTransparency = 0.35 })
	end
end

-- Sparkles round the head.
EMOTES.spark = function(a)
	local SPOTS = { { 0.24, 0.14, 46 }, { 0.76, 0.1, 58 }, { 0.82, 0.3, 34 }, { 0.2, 0.34, 30 } }
	for i, sp in ipairs(SPOTS) do
		local s = Gui.sparkle(a.emotes, sp[3], Color3.fromRGB(255, 226, 120))
		s.Position = UDim2.fromScale(sp[1], sp[2])
		s.ZIndex = 4
		local sc = make("UIScale", { Scale = 0 }, s)
		task.delay((i - 1) * 0.08, function()
			if sc.Parent then
				tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
	end
end

function StoryDialogue.emotes()
	return EMOTES
end

local function showEmote(a, key)
	clearEmotes(a)
	local fn = key and EMOTES[key]
	if fn then
		fn(a)
	end
end

------------------------------------------------------------------------------------------
-- backdrops
------------------------------------------------------------------------------------------

local SCENES = { gym = { scene = "gym", shot = "storyGym" }, arena = { scene = "home", shot = "storyArena" } }

local function fadeTo(alpha, time)
	local t = tween(ui.fade, time, { BackgroundTransparency = 1 - alpha }, Enum.EasingStyle.Linear)
	t.Completed:Wait()
end

local function applyBackdrop(key)
	local SC = mods.SceneController
	local world = SCENES[key]
	for name, f in pairs(ui.painted) do
		f.Visible = name == key
	end
	ui.paint.Visible = world == nil
	if world then
		SC.show(world.scene)
		SC.shot(world.shot)
		SC.storyStage(true)
	end
	backdrop = key
end

local function setBackdrop(key, instant)
	if key == backdrop then
		return
	end
	if not (ui.painted[key] or SCENES[key]) then
		key = "black"
	end
	if instant then
		applyBackdrop(key)
		return
	end
	fadeTo(1, 0.22)
	setStage({})
	ui.name.Text = ""
	ui.line.Text = ""
	applyBackdrop(key)
	task.wait(0.05)
	fadeTo(0, 0.28)
end

------------------------------------------------------------------------------------------
-- a scene
------------------------------------------------------------------------------------------

-- {Braces} in a line light the words up.
local function rich(text)
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	text = string.gsub(text, "{", '<font color="' .. HOT .. '"><b>')
	text = string.gsub(text, "}", "</b></font>")
	return text
end

local function plain(text)
	text = string.gsub(text, "[{}]", "")
	return text
end

-- Wait for a press (false when the scene was left).
local function waitAdvance(s)
	s.advance = false
	while not s.advance and not s.cancelled do
		task.wait()
	end
	local went = s.advance
	s.advance = false
	return went and not s.cancelled
end

-- Type a line out; a press finishes it, the next goes on.
local function say(s, who, text, opts)
	local a = who and actors[who] or nil
	if who and a and not a.on then
		-- someone speaking who isn't on screen yet walks on beside whoever is
		local ids = {}
		for _, id in ipairs(onStage) do
			table.insert(ids, id)
		end
		if #ids >= 3 then
			table.remove(ids, #ids)
		end
		table.insert(ids, who)
		setStage(ids)
	end
	for _, id in ipairs(onStage) do
		if id ~= who then
			clearEmotes(actors[id])
		end
	end
	light(who)
	if a then
		setPose(a, opts.pose)
		showEmote(a, opts.emote)
	end
	ui.more.Visible = false
	ui.name.Text = who and Story.castName(who) or ""
	ui.line.FontFace = (who and not opts.think) and FACE_LINE or FACE_NOTE
	ui.line.TextColor3 = (who and not opts.think) and Color3.fromRGB(246, 247, 250) or Color3.fromRGB(206, 210, 224)
	ui.line.Position = who and UDim2.new(0, 120, 1, -228) or UDim2.new(0, 120, 1, -250)
	ui.line.MaxVisibleGraphemes = 0
	ui.line.Text = rich(text)
	table.insert(s.log, { who = who and Story.castName(who) or nil, text = plain(text) })
	local total = utf8.len(plain(text)) or #text
	local shown = 0
	s.advance = false
	while shown < total and not s.cancelled do
		local dt = task.wait()
		shown = math.min(total, shown + dt * TYPE_SPEED)
		ui.line.MaxVisibleGraphemes = math.floor(shown)
		if s.advance then
			s.advance = false
			break
		end
	end
	ui.line.MaxVisibleGraphemes = -1
	if s.cancelled then
		return false
	end
	ui.more.Visible = true
	local went = waitAdvance(s)
	ui.more.Visible = false
	if went then
		Gui.click()
	end
	return went
end

local function titleCard(s, title)
	ui.cardLabel.Text = title.label or ""
	ui.cardName.Text = title.name or ""
	ui.card.Visible = true
	ui.card.BackgroundTransparency = 1
	ui.cardLabel.TextTransparency = 1
	ui.cardName.TextTransparency = 1
	tween(ui.card, 0.35, { BackgroundTransparency = 0.35 })
	tween(ui.cardLabel, 0.35, { TextTransparency = 0 })
	tween(ui.cardName, 0.35, { TextTransparency = 0 })
	local t0 = os.clock()
	s.advance = false
	while os.clock() - t0 < 2.2 and not s.advance and not s.cancelled do
		task.wait()
	end
	s.advance = false
	tween(ui.card, 0.3, { BackgroundTransparency = 1 })
	tween(ui.cardLabel, 0.3, { TextTransparency = 1 })
	tween(ui.cardName, 0.3, { TextTransparency = 1 })
	task.delay(0.32, function()
		ui.card.Visible = false
	end)
end

local function close()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	for _, a in pairs(actors) do
		if a then
			a.on = false
			a.vp.Visible = false
			clearEmotes(a)
		end
	end
	onStage = {}
	backdrop = nil
	ui.name.Text = ""
	ui.line.Text = ""
	ui.more.Visible = false
	ui.card.Visible = false
	gui.Enabled = false
	mods.SceneController.storyStage(false)
	if mods.MenuController.cover then
		mods.MenuController.cover(false)
	end
end

function StoryDialogue.active()
	return session ~= nil
end

-- Play a scene. Returns at once; onDone(skipped) when it's over.
function StoryDialogue.play(scene, opts, onDone)
	if session or type(scene) ~= "table" then
		return false
	end
	opts = opts or {}
	local s = { cancelled = false, advance = false, skipped = false, log = {} }
	session = s
	task.spawn(function()
		layout()
		ui.fade.BackgroundTransparency = 0
		gui.Enabled = true
		if mods.MenuController.cover then
			mods.MenuController.cover(true)
		end
		preload(scene)
		-- the first backdrop goes up behind the fade
		local first = "black"
		for _, st in ipairs(scene) do
			if st.bg then
				first = st.bg
				break
			end
		end
		setBackdrop(first, true)
		conn = RunService.RenderStepped:Connect(function()
			step(os.clock())
		end)
		fadeTo(0, 0.35)
		if opts.title and not s.cancelled then
			titleCard(s, opts.title)
		end
		for _, st in ipairs(scene) do
			if s.cancelled then
				break
			end
			if st.bg then
				setBackdrop(st.bg)
			elseif st.on then
				setStage(st.on)
				task.wait(0.12)
			elseif st.note then
				say(s, nil, st.note, st)
			elseif type(st[1]) == "string" and type(st[2]) == "string" then
				say(s, st[1], st[2], st)
			end
		end
		fadeTo(1, 0.3)
		close()
		session = nil
		tween(ui.fade, 0.3, { BackgroundTransparency = 1 })
		gui.Enabled = true -- (only the fade is left on it; it turns itself off below)
		task.delay(0.32, function()
			if not session then
				gui.Enabled = false
			end
		end)
		if onDone then
			onDone(s.skipped)
		end
	end)
	return true
end

function StoryDialogue.init(m)
	mods = m
	build()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not session then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter or k == Enum.KeyCode.ButtonA then
			session.advance = true
		elseif k == Enum.KeyCode.ButtonY then
			session.skipped = true
			session.cancelled = true
		end
	end)
	-- (the menu's blur stays off behind a scene)
	RunService.Heartbeat:Connect(function()
		if session then
			local blur = Lighting:FindFirstChild("SpikeRushMenuBlur")
			if blur and blur.Size > 0 then
				blur.Size = 0
			end
		end
	end)
end

return StoryDialogue
