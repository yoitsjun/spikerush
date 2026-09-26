-- Loading screen (ReplicatedFirst, so it shows before anything else loads).
-- A single frame held like a freeze in a replay: a flat amber screen, a pillar of light with a
-- black ball at its top, and the SPIKE RUSH logo top left. While the game loads, a quiet line on
-- the right says so (and a tip sits bottom left). Once the controllers run (Main.client sets
-- "SpikeRushLoaded") and your avatar has loaded, its silhouette rises into the pillar and holds
-- the bow-draw, the pointing hand just under the ball: the frame freezes on "Click to continue".
-- A click, tap or key plays the swing: the ball blasts away under an impact flash and the screen
-- fades into the game.
-- The silhouette is your avatar posed by AnimationController (cloned by SceneController); without
-- one the ball and the pillar play alone. Everything is GUI objects and parts: nothing to upload.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local MAX_WAIT = 25 -- never hold a player on the loading part longer than this
local MIN_LOAD = 1.5 -- the loading line shows at least this long

local AMBER = Color3.fromRGB(255, 198, 41)
local INK = Color3.fromRGB(16, 18, 34)
local BEAM = Color3.fromRGB(255, 247, 214)
local ORANGE = Color3.fromRGB(255, 122, 24)
local WHITE = Color3.new(1, 1, 1)
local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local LOGO_FACE = Font.new(MONTSERRAT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic) -- Heavy is 900: Montserrat Black
local TEXT_FACE = Font.new(MONTSERRAT, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local TIP_FACE = Font.new(MONTSERRAT, Enum.FontWeight.Medium, Enum.FontStyle.Normal)

-- The frame's layout, as fractions of the screen (sizes are fractions of its height).
local HAND_AT = Vector2.new(0.63, 0.5) -- where the pointing hand sits
local BALL_SIZE = 0.071
local BALL_ABOVE = 0.056 -- the ball's centre above the hand
local BEAM_WIDTH = 0.066
local HAND_TO_FEET = 0.5 -- the hand-to-feet height on the screen (it sets the camera distance)
local FOV = 30
local TAN = math.tan(math.rad(FOV / 2))

local TIPS = {
	"Spike power comes from clean contact at the top of your jump.",
	"Press receive a little early: the stance stays armed.",
	"A 4.00 m hitting point turns Thunder Spiker on.",
	"Azure Dragon: hold spike in the air to charge. You fall slower while charging.",
	"Hold W and release to jump for a block.",
	"Out of guard? Slide receives never cost stamina.",
	"Recruit players and looks with V Points; upgrade stats with Gold.",
	"Timeouts refill stamina and let you rearrange your rotation.",
	"At deuce you have to win by two.",
}

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local gui = make("ScreenGui", {
	Name = "SpikeRushLoading",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = AMBER, BorderSizePixel = 0 }, gui)

-- the stage: the silhouette, the pillar and the ball (shaken together on the hit)
local stage = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, bg)
local vp = make("ViewportFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ImageColor3 = Color3.new(0, 0, 0),
	Ambient = WHITE,
	LightColor = WHITE,
	ZIndex = 2,
}, stage)
local cam = make("Camera", { FieldOfView = FOV }, vp)
vp.CurrentCamera = cam
local world = make("WorldModel", {}, vp)

-- the pillar: a soft halo and a bright core, feathered at the edges, drawn over the silhouette
local function feather(core)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.4 + core * 0.3),
		NumberSequenceKeypoint.new(0.5, core),
		NumberSequenceKeypoint.new(0.75, 0.4 + core * 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
end
local halo = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = BEAM, BorderSizePixel = 0, ZIndex = 3 }, stage)
make("UIGradient", { Transparency = feather(0.72) }, halo)
local beam = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = BEAM, BorderSizePixel = 0, ZIndex = 3 }, stage)
make("UIGradient", { Transparency = feather(0.2) }, beam)
local ball = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(6, 6, 8), BorderSizePixel = 0, ZIndex = 5 }, stage)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ball)
local streak = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false, ZIndex = 4 }, stage)
make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) }, streak)
local flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 30 }, gui)

------------------------------------------------------------------------------------------
-- the logo: SPIKE in white with an ink outline, an orange rim and an ink extrude; RUSH in an
-- orange-to-gold gradient tucked under it with three speed marks; tilted up a few degrees
------------------------------------------------------------------------------------------

local function buildLogo(parent)
	local box = make("Frame", { BackgroundTransparency = 1, Rotation = -4, ZIndex = 10 }, parent)
	make("UIAspectRatioConstraint", { AspectRatio = 2.15 }, box)
	local function word(text, pos, size, color, z)
		return make("TextLabel", {
			BackgroundTransparency = 1,
			Text = text,
			FontFace = LOGO_FACE,
			TextScaled = true,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = pos,
			Size = size,
			ZIndex = z,
		}, box)
	end
	local spikeSize = UDim2.fromScale(1, 0.64)
	local extrude = word("SPIKE", UDim2.new(), spikeSize, INK, 10)
	local rim = word("SPIKE", UDim2.new(), spikeSize, ORANGE, 11)
	local face = word("SPIKE", UDim2.new(), spikeSize, WHITE, 12)
	local rush = word("RUSH", UDim2.fromScale(0.36, 0.58), UDim2.fromScale(0.6, 0.38), WHITE, 12)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 214, 70), Color3.fromRGB(255, 108, 20)) }, rush)
	local function stroke(label, color)
		return make("UIStroke", { Color = color, LineJoinMode = Enum.LineJoinMode.Round }, label)
	end
	-- stroke widths as fractions of the logo's height
	local strokes = {
		{ stroke(extrude, INK), 0.05 },
		{ stroke(rim, ORANGE), 0.07 },
		{ stroke(face, INK), 0.032 },
		{ stroke(rush, INK), 0.03 },
	}
	-- speed marks trailing RUSH
	for i, len in ipairs({ 0.2, 0.15, 0.1 }) do
		local m = make("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.335 - (i - 1) * 0.015, 0.68 + (i - 1) * 0.1),
			Size = UDim2.fromScale(len, 0.045),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 12,
		}, box)
		table.insert(strokes, { make("UIStroke", { Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, m), 0.014 })
	end
	local function fit()
		local h = box.AbsoluteSize.Y
		for _, s in ipairs(strokes) do
			s[1].Thickness = math.max(1, h * s[2])
		end
		extrude.Position = UDim2.fromOffset(h * 0.035, h * 0.045)
	end
	box:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	return box
end

local logo = buildLogo(bg)
logo.Position = UDim2.new(0.03, 0, 0, GuiService:GetGuiInset().Y + 10) -- under Roblox's own buttons
logo.Size = UDim2.fromScale(0.22, 0.2)
local logoScale = make("UIScale", { Scale = 1.25 }, logo)
TweenService:Create(logoScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

-- the line on the right: "Loading" with a thin progress bar, later "Click to continue"
local prompt = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.82, 0.545),
	Size = UDim2.fromScale(0.3, 0.05),
	BackgroundTransparency = 1,
	Text = "Loading",
	FontFace = TEXT_FACE,
	TextScaled = true,
	TextColor3 = INK,
	TextTransparency = 0.45,
	ZIndex = 6,
}, bg)
local barBack = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.82, 0, 0.58, 4),
	Size = UDim2.new(0.11, 0, 0, 2),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.82,
	BorderSizePixel = 0,
	ZIndex = 6,
}, bg)
local barFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 6 }, barBack)
local rng = Random.new()
local tip = make("TextLabel", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0.03, 0, 1, -18),
	Size = UDim2.fromScale(0.5, 0.03),
	BackgroundTransparency = 1,
	Text = TIPS[rng:NextInteger(1, #TIPS)],
	FontFace = TIP_FACE,
	TextScaled = true,
	TextColor3 = INK,
	TextTransparency = 0.5,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 6,
}, bg)
make("UITextSizeConstraint", { MaxTextSize = 22 }, tip)

------------------------------------------------------------------------------------------
-- camera and layout: the ball and the pillar sit over the frozen pose's pointing hand
------------------------------------------------------------------------------------------

local handWorld, feetY = nil, nil -- the frozen pose's pointing hand (world) and the soles' height

-- Side on: the camera looks along -X, so the figure (facing -Z) faces right. It stands back far
-- enough that hand to feet spans HAND_TO_FEET of the screen (so blocky and tall avatars frame
-- alike), placed so the hand lands on HAND_AT.
local function fitCamera(size)
	local aspect = size.X / math.max(1, size.Y)
	local depth = math.clamp(math.max(1, handWorld.Y - feetY) / (2 * HAND_TO_FEET * TAN), 6, 80)
	local look, right = Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1)
	local x = (HAND_AT.X * 2 - 1) * depth * TAN * aspect
	local y = (1 - HAND_AT.Y * 2) * depth * TAN
	local pos = handWorld - look * depth - right * x - Vector3.yAxis * y
	cam.CFrame = CFrame.lookAt(pos, pos + look)
end

-- where a point of the scene sits on the screen (Scale units)
local function screenOf(p, size)
	local rel = cam.CFrame:PointToObjectSpace(p)
	local x = rel.X / (-rel.Z * TAN * size.X / math.max(1, size.Y))
	local y = rel.Y / (-rel.Z * TAN)
	return Vector2.new(0.5 + x / 2, 0.5 - y / 2)
end

local ballAt = Vector2.new(HAND_AT.X, HAND_AT.Y - BALL_ABOVE)
local function layout()
	local size = bg.AbsoluteSize
	if size.Y < 2 then
		return
	end
	local hand = HAND_AT
	if handWorld then
		fitCamera(size)
		hand = screenOf(handWorld, size)
	end
	ballAt = Vector2.new(hand.X, hand.Y - BALL_ABOVE)
	local h = size.Y
	ball.Size = UDim2.fromOffset(h * BALL_SIZE, h * BALL_SIZE)
	ball.Position = UDim2.fromScale(ballAt.X, ballAt.Y)
	beam.Position = UDim2.fromScale(ballAt.X, ballAt.Y)
	beam.Size = UDim2.new(0, h * BEAM_WIDTH, 1.05 - ballAt.Y, 0)
	halo.Position = beam.Position
	halo.Size = UDim2.new(0, h * BEAM_WIDTH * 3, 1.05 - ballAt.Y, 0)
end
bg:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

------------------------------------------------------------------------------------------
-- while loading: progress, tips and a slow shimmer in the pillar
------------------------------------------------------------------------------------------

local t0 = os.clock()
local shown = 0
local nextTipAt = t0 + 4.5
local conn = RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local e = now - t0
	beam.BackgroundTransparency = 0.04 + 0.04 * math.sin(e * 1.7)
	if now > nextTipAt then
		nextTipAt = now + 4.5
		tip.Text = TIPS[rng:NextInteger(1, #TIPS)]
	end
	-- progress: loading assets, then the game starting up
	local target
	if player:GetAttribute("SpikeRushLoaded") then
		target = 1
	elseif game:IsLoaded() then
		target = 0.75 + 0.2 * math.min(1, e / 10)
		prompt.Text = "Warming up"
	else
		local queue = ContentProvider.RequestQueueSize
		target = math.min(0.7, 0.1 + 0.6 * (1 - math.min(1, queue / 200)) * math.min(1, e / 3))
		prompt.Text = "Loading"
	end
	shown = shown + (target - shown) * math.min(1, dt * 6)
	barFill.Size = UDim2.fromScale(shown, 1)
end)

------------------------------------------------------------------------------------------
-- the silhouette
------------------------------------------------------------------------------------------

-- The client's controllers once Main.client has started them (the same module instances).
local function controllers()
	if not player:GetAttribute("SpikeRushLoaded") then
		return nil
	end
	local scripts = player:FindFirstChild("PlayerScripts")
	local client = scripts and scripts:FindFirstChild("Client")
	local folder = client and client:FindFirstChild("Controllers")
	if not folder then
		return nil
	end
	local ok, c = pcall(function()
		return {
			anim = require(folder.AnimationController),
			scene = require(folder.SceneController),
			audio = require(folder.AudioController),
			state = require(folder.State),
		}
	end)
	return ok and c or nil
end

-- A static silhouette of your avatar, once it has loaded (a few seconds at most).
local function avatarRig(C)
	if not C then
		return nil
	end
	local deadline = os.clock() + 6
	while os.clock() < deadline do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") and player:HasAppearanceLoaded() then
			break
		end
		task.wait(0.1)
	end
	local ok, rig = pcall(C.scene.cloneAvatar, true)
	return ok and rig or nil
end

local function play(C, name, volume)
	if C and C.audio then
		pcall(C.audio.play, name, { volume = volume })
	end
end

-- The held frame: the bow-draw seen side on. The chest turns open to the camera, the left arm
-- points up the pillar and a little ahead, the hitting hand is cocked behind the head. (The
-- game's own Cock pose turns the other way, which from this side hides the pointing arm behind
-- the body.) The legs keep Cock's tuck.
local function freezePose(AC)
	local base = AC.poseJoints("Cock")
	if not base then
		return nil
	end
	local function angles(x, y, z)
		return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	end
	local j = {}
	for k, v in pairs(base) do
		j[k] = v
	end
	j.Waist = angles(15, -30, 0)
	j.LeftShoulder = angles(150, 0, -10)
	j.LeftElbow = angles(4, 0, 0)
	j.RightShoulder = angles(120, 0, 70)
	j.RightElbow = angles(110, 0, 0)
	return j
end

-- Pose the rig once in the frozen pose to learn where its hand and head are, then set the
-- camera and the pillar around them. Returns the height the root stands at, or nil.
local function stageRig(AC, rig, pose)
	if not (AC and rig and pose) then
		return nil
	end
	local model = rig.model
	local hum = model:FindFirstChildOfClass("Humanoid")
	local standY = (hum and hum.HipHeight or 2) + rig.root.Size.Y / 2
	model.Parent = world
	AC.poseModel(rig, pose, CFrame.new(0, standY, 0))
	local hand = model:FindFirstChild("LeftHand") or model:FindFirstChild("Left Arm")
	local feet = {}
	for _, name in ipairs({ "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }) do
		local p = model:FindFirstChild(name)
		if p then
			table.insert(feet, p.Position.Y - p.Size.Y / 2)
		end
	end
	if not hand or #feet == 0 then
		model.Parent = nil
		return nil
	end
	handWorld = hand.Position + Vector3.new(0, hand.Size.Y * 0.3, 0)
	feetY = math.min(table.unpack(feet))
	layout()
	-- out of sight until it rises
	AC.poseModel(rig, pose, CFrame.new(0, standY - 60, 0))
	return standY
end

-- The silhouette rises into the pillar and settles into the frozen pose.
local function rise(C, AC, rig, pose, standY)
	play(C, "Whoosh", 0.8)
	local from = AC.poseJoints("Rise") or pose
	local start = os.clock()
	local DUR = 0.5
	while true do
		local a = math.min(1, (os.clock() - start) / DUR)
		local e = 1 - (1 - a) ^ 3
		AC.poseModel(rig, AC.blendJoints(from, pose, math.clamp((a - 0.15) / 0.85, 0, 1)), CFrame.new(0, standY - 9 * (1 - e), 0))
		if a >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

------------------------------------------------------------------------------------------
-- the hit: the swing, the ball blasting off, the impact flash and speed lines
------------------------------------------------------------------------------------------

local function impact(C, at)
	play(C, "SpikeHeavy", 1.1)
	play(C, "Boom", 0.9)
	flash.BackgroundTransparency = 0
	TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	local h = bg.AbsoluteSize.Y
	for i = 1, 12 do
		local angle = (i / 12) * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
		local dir = Vector2.new(math.cos(angle), math.sin(angle))
		local len = h * rng:NextNumber(0.16, 0.28)
		local function spot(dist)
			return UDim2.new(at.X, dir.X * dist, at.Y, dir.Y * dist)
		end
		local line = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = spot(h * 0.12 + len / 2),
			Size = UDim2.fromOffset(len, math.max(2, h * 0.004)),
			Rotation = math.deg(angle),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 7,
		}, stage)
		local info = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(line, info, { Position = spot(h * 0.3 + len / 2), BackgroundTransparency = 1 }):Play()
	end
end

-- The follow-through from the held frame: the hitting arm whips down and across, the pointing arm
-- drops and the chest folds, while the hips and legs stay put (the game's own swing clip turns
-- the body the other way, which would jump the silhouette out of the pillar).
local function followPose(pose)
	local function angles(x, y, z)
		return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	end
	local j = {}
	for k, v in pairs(pose) do
		j[k] = v
	end
	j.Waist = angles(-12, -10, 0)
	j.RightShoulder = angles(35, 0, 25)
	j.RightElbow = angles(15, 0, 0)
	j.LeftShoulder = angles(45, 0, -20)
	j.LeftElbow = angles(35, 0, 0)
	return j
end

local function strike(C, AC, rig, pose, standY)
	local follow = pose and followPose(pose)
	local CONTACT = 0.05
	local from = ballAt
	local to = Vector2.new(ballAt.X - 0.75, 1.25) -- down and away, off the screen
	local start = os.clock()
	local hit = false
	while true do
		local t = os.clock() - start
		if rig and AC and standY and follow then
			local a = math.min(1, t / 0.14)
			AC.poseModel(rig, AC.blendJoints(pose, follow, 1 - (1 - a) * (1 - a)), CFrame.new(0, standY, 0))
		end
		if not hit and t >= CONTACT then
			hit = true
			impact(C, from)
		end
		if hit then
			local a = math.min(1, (t - CONTACT) / 0.16)
			local p = from:Lerp(to, a * a)
			ball.Position = UDim2.fromScale(p.X, p.Y)
			-- the streak runs from where it was struck up to the ball
			local size = bg.AbsoluteSize
			local d = Vector2.new((p.X - from.X) * size.X, (p.Y - from.Y) * size.Y)
			local len = d.Magnitude
			if len > 4 then
				streak.Visible = true
				streak.Position = UDim2.new(from.X, d.X / 2, from.Y, d.Y / 2)
				streak.Size = UDim2.fromOffset(len, math.max(4, size.Y * 0.014))
				streak.Rotation = math.deg(math.atan2(d.Y, d.X))
			end
			-- a short shake
			local k = math.max(0, 1 - (t - CONTACT) / 0.3)
			stage.Position = UDim2.fromOffset(rng:NextNumber(-10, 10) * k, rng:NextNumber(-8, 8) * k)
		end
		if t > 0.55 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	stage.Position = UDim2.new()
	streak.Visible = false
end

------------------------------------------------------------------------------------------
-- run
------------------------------------------------------------------------------------------

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local waited = 0
while (not player:GetAttribute("SpikeRushLoaded") or os.clock() - t0 < MIN_LOAD) and waited < MAX_WAIT do
	waited = waited + task.wait(0.1)
end
-- the silhouette needs the controllers and your avatar (the loading line keeps going)
local C = controllers()
local AC = C and C.anim
local rig = avatarRig(C)
local pose = AC and freezePose(AC)
local ok, standY = pcall(stageRig, AC, rig, pose)
if not ok then
	warn("[SpikeRush] loading screen: " .. tostring(standY))
	standY = nil
end
conn:Disconnect()
barFill.Size = UDim2.fromScale(1, 1)

-- the loading line and the tip give way to the frozen frame
local quick = TweenInfo.new(0.25)
local promptOut = TweenService:Create(prompt, quick, { TextTransparency = 1 })
promptOut:Play()
TweenService:Create(barBack, quick, { BackgroundTransparency = 1 }):Play()
TweenService:Create(barFill, quick, { BackgroundTransparency = 1 }):Play()
TweenService:Create(tip, quick, { TextTransparency = 1 }):Play()
if standY then
	local ok2, err = pcall(rise, C, AC, rig, pose, standY)
	if not ok2 then
		warn("[SpikeRush] loading screen: " .. tostring(err))
	end
end
beam.BackgroundTransparency = 0

-- frozen: "Click to continue" until a click, tap or key
promptOut:Cancel()
prompt.Text = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) and "Tap to continue" or "Click to continue"
local catcher = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 25 }, gui)
local go = false
catcher.MouseButton1Click:Connect(function()
	go = true
end)
local keys = UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.Gamepad1 then
		go = true
	end
end)
local waitStart = os.clock()
while not go do
	-- only the prompt breathes; the frame holds
	prompt.TextTransparency = 0.3 + 0.25 * (0.5 + 0.5 * math.cos((os.clock() - waitStart) * 3))
	RunService.RenderStepped:Wait()
end
keys:Disconnect()
catcher:Destroy()
prompt.Visible = false

local ok3, err3 = pcall(strike, C, AC, rig, pose, standY)
if not ok3 then
	warn("[SpikeRush] loading screen: " .. tostring(err3))
end

-- fade out into the game
local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
for _, d in ipairs(gui:GetDescendants()) do
	if d:IsA("ViewportFrame") then
		TweenService:Create(d, info, { ImageTransparency = 1 }):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
	elseif d:IsA("TextLabel") then
		TweenService:Create(d, info, { TextTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, info, { Transparency = 1 }):Play()
	end
end
task.wait(0.55)
gui:Destroy()
