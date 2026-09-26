-- Loading screen (ReplicatedFirst, so it shows before anything else loads).
-- While the game loads: soft grey stadium light, bubbles drifting up, light rays and a big
-- yellow / blue / white ball spinning over the title, a rotating tip and a progress bar. It stays
-- up for at least MIN_LOAD seconds and until the client controllers have started (Main.client sets
-- "SpikeRushLoaded"), then cuts to a short cinematic like the recruit S: a yellow screen, a beam
-- of light and your avatar's silhouette jumping to spike a ball over a net. The spike slows into a
-- freeze just before the ball lands and "Click to continue" comes up; a click (or any key) plays
-- the landing and fades into the game. The silhouette is your avatar posed by AnimationController
-- (cloned by SceneController once they've started); without an avatar the ball plays alone.
-- All shapes are plain GUI objects and parts: no assets to upload.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local MAX_WAIT = 25 -- never hold a player on the loading part longer than this
local MIN_LOAD = 3 -- the loading part shows at least this long

local INK = Color3.fromRGB(20, 23, 43)
local SPARK = Color3.fromRGB(255, 225, 77)
local BLUE = Color3.fromRGB(34, 86, 196)
local YELLOW = Color3.fromRGB(255, 205, 40)
local CHALK = Color3.fromRGB(244, 247, 255)
local DISPLAY = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)

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

local bg = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(190, 196, 208),
	BorderSizePixel = 0,
}, gui)
make("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(232, 236, 242)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(176, 184, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(96, 104, 128)),
	}),
}, bg)

-- light rays from the top left
local rays = {}
for i = 1, 5 do
	local r = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.18 + i * 0.11, 0, -0.2, 0),
		Size = UDim2.new(0, 70 + i * 18, 1.6, 0),
		Rotation = -28,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
	}, bg)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, r)
	rays[i] = r
end

-- bubbles
local bubbles = {}
local rng = Random.new()
for i = 1, 22 do
	local size = rng:NextInteger(10, 46)
	local b = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
	}, bg)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.45, Thickness = 1.5 }, b)
	local shine = make("Frame", {
		Size = UDim2.fromScale(0.28, 0.28),
		Position = UDim2.fromScale(0.2, 0.18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, b)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
	bubbles[i] = { frame = b, x = rng:NextNumber(), y = rng:NextNumber() * 1.2, speed = 0.02 + rng:NextNumber() * 0.05, sway = rng:NextNumber() * 6 }
end

-- the ball: banded yellow / white / blue, a spinning band gradient under a fixed light
local ballHolder = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.36),
	Size = UDim2.fromScale(0.3, 0.3),
	BackgroundTransparency = 1,
}, bg)
make("UIAspectRatioConstraint", { AspectRatio = 1 }, ballHolder)
local shadow = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.54, 0.56),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.75,
	BorderSizePixel = 0,
}, ballHolder)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shadow)
local ball = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, ballHolder)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ball)
make("UIStroke", { Color = INK, Thickness = 3 }, ball)
local bands = make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, YELLOW),
		ColorSequenceKeypoint.new(0.3, YELLOW),
		ColorSequenceKeypoint.new(0.31, CHALK),
		ColorSequenceKeypoint.new(0.36, CHALK),
		ColorSequenceKeypoint.new(0.37, BLUE),
		ColorSequenceKeypoint.new(0.63, BLUE),
		ColorSequenceKeypoint.new(0.64, CHALK),
		ColorSequenceKeypoint.new(0.69, CHALK),
		ColorSequenceKeypoint.new(0.7, YELLOW),
		ColorSequenceKeypoint.new(1, YELLOW),
	}),
}, ball)
-- shading and a highlight so it reads as a sphere
local shade = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = INK,
	BorderSizePixel = 0,
}, ball)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shade)
make("UIGradient", {
	Rotation = 45,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.55, 0.95),
		NumberSequenceKeypoint.new(1, 0.45),
	}),
}, shade)
local highlight = make("Frame", {
	Position = UDim2.fromScale(0.18, 0.14),
	Size = UDim2.fromScale(0.3, 0.22),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Rotation = -30,
}, ball)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, highlight)

-- title
local title = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.56),
	Size = UDim2.fromScale(0.8, 0.14),
	BackgroundTransparency = 1,
	Text = "SPIKE RUSH",
	Font = Enum.Font.Bangers,
	TextScaled = true,
	TextColor3 = SPARK,
}, bg)
make("UIStroke", { Color = INK, Thickness = 4 }, title)
make("UITextSizeConstraint", { MaxTextSize = 110 }, title)
local tagline = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.7),
	Size = UDim2.fromScale(0.8, 0.04),
	BackgroundTransparency = 1,
	Text = "anime volleyball",
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = INK,
}, bg)
make("UITextSizeConstraint", { MaxTextSize = 22 }, tagline)

-- progress and tips
local barBack = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.8),
	Size = UDim2.new(0.5, 0, 0, 12),
	BackgroundColor3 = INK,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
}, bg)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, barBack)
local barFill = make("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = SPARK,
	BorderSizePixel = 0,
}, barBack)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, barFill)
local status = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.8, 18),
	Size = UDim2.new(0.6, 0, 0, 18),
	BackgroundTransparency = 1,
	Text = "Loading",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = CHALK,
}, bg)
local tip = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.new(0.8, 0, 0, 22),
	BackgroundTransparency = 1,
	Text = TIPS[rng:NextInteger(1, #TIPS)],
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = CHALK,
	TextWrapped = true,
}, bg)
make("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.3 }, tip)

-- the loading animation
local t0 = os.clock()
local shown = 0
local nextTipAt = t0 + 4
local conn = RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local e = now - t0
	bands.Rotation = (e * 50) % 360
	bands.Offset = Vector2.new(math.sin(e * 1.3) * 0.08, 0)
	ballHolder.Position = UDim2.fromScale(0.5, 0.36 + math.sin(e * 2.2) * 0.012)
	for i, r in ipairs(rays) do
		r.BackgroundTransparency = 0.84 + 0.06 * math.sin(e * 0.8 + i)
	end
	for _, b in ipairs(bubbles) do
		b.y = b.y - b.speed * dt
		if b.y < -0.1 then
			b.y = 1.1
			b.x = rng:NextNumber()
		end
		b.frame.Position = UDim2.new(b.x, math.sin(e + b.sway) * 12, b.y, 0)
	end
	if now > nextTipAt then
		nextTipAt = now + 4
		tip.Text = TIPS[rng:NextInteger(1, #TIPS)]
	end
	-- progress: loading assets, then the game starting up
	local target
	if player:GetAttribute("SpikeRushLoaded") then
		target = 1
	elseif game:IsLoaded() then
		target = 0.75 + 0.2 * math.min(1, e / 10)
		status.Text = "Warming up"
	else
		local queue = ContentProvider.RequestQueueSize
		target = math.min(0.7, 0.1 + 0.6 * (1 - math.min(1, queue / 200)) * math.min(1, e / 3))
		status.Text = "Loading"
	end
	shown = shown + (target - shown) * math.min(1, dt * 6)
	barFill.Size = UDim2.fromScale(shown, 1)
end)

------------------------------------------------------------------------------------------
-- the cinematic
------------------------------------------------------------------------------------------

-- Side on, like the match camera: the spiker on the right, the net in the middle, the ball's
-- landing spot on the left. The silhouette faces -Z (toward the net).
local SPIKER = Vector3.new(0, 0, 1.5)
local NET_Z = -5
local LAND = Vector3.new(0, 0.65, -15)
local CAM_FROM = Vector3.new(-21, 6.2, -6.5)
local CAM_TO = Vector3.new(0, 6.4, -6.5)
local TAKEOFF, AIR, JUMP = 0.25, 1.5, 5.5 -- when the jump starts, its air time, its height (studs)
local CONTACT = TAKEOFF + AIR / 2 -- the spike lands at the top of the jump
local FLIGHT = 0.34 -- the spiked ball's flight to the floor (scene seconds)
local FULL = 0.04 -- full speed after contact, then the slow-motion into the freeze
local SLOW = 0.9 * FLIGHT - FULL -- how much more scene time the slow-motion covers (it never lands)
local FREEZE = 0.7 -- real seconds from contact to "Click to continue"

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

-- Scene time for real time r: real time until just after contact, then a slow-motion that
-- settles into a freeze (the ball hangs just above the floor).
local function sceneTime(r)
	if r <= CONTACT + FULL then
		return r
	end
	return CONTACT + FULL + SLOW * (1 - math.exp(-(r - CONTACT - FULL) / SLOW))
end

local function cinematic(C, rig)
	local AC = C and C.anim
	local style = "Classic"
	if C and C.state and C.state.profile and C.state.profile.equip then
		style = C.state.profile.equip.Style or style
	end
	local cock, swing = nil, "Swing"
	if AC then
		cock = AC.poseJoints("Cock_" .. style) or AC.poseJoints("Cock")
		swing = AC.clipDuration("Swing_" .. style) and ("Swing_" .. style) or "Swing"
	end

	-- the stage: a yellow screen, a glow behind the spiker, a beam of light, the silhouettes
	local cin = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10 }, gui)
	make("UIGradient", { Rotation = 70, Color = ColorSequence.new(Color3.fromRGB(255, 232, 110), Color3.fromRGB(255, 176, 30)) }, cin)
	local glow = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.74, 0.4), Size = UDim2.fromScale(0.9, 0.9), BackgroundTransparency = 1, ZIndex = 10 }, cin)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, glow)
	local rings = {}
	for i = 1, 6 do
		local d = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(i / 6, i / 6), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10 }, glow)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, d)
		rings[i] = d
	end
	local function setGlow(alpha)
		for i, d in ipairs(rings) do
			d.BackgroundTransparency = 1 - alpha * (0.34 - i * 0.045)
		end
	end
	local beam = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 160, 3, 0), Position = UDim2.fromScale(-0.3, 0.5), Rotation = 24, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 11 }, cin)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, beam)
	local vp = make("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ImageColor3 = Color3.new(0, 0, 0), Ambient = Color3.new(1, 1, 1), LightColor = Color3.new(1, 1, 1), ZIndex = 12 }, cin)
	local cam = make("Camera", { FieldOfView = 44, CFrame = CFrame.lookAt(CAM_FROM, CAM_TO) }, vp)
	vp.CurrentCamera = cam
	local world = make("WorldModel", {}, vp)
	local function block(size, cf, shape)
		return make("Part", { Size = size, CFrame = cf, Shape = shape or Enum.PartType.Block, Anchored = true, CanCollide = false, Color = Color3.new(0, 0, 0) }, world)
	end
	-- the floor ends just behind the play, so the frozen ball shows clear of it
	block(Vector3.new(6.8, 0.4, 80), CFrame.new(-2.6, -0.2, -10))
	block(Vector3.new(0.35, 6.4, 0.35), CFrame.new(0.6, 3.2, NET_Z)) -- the net, edge on: its post
	block(Vector3.new(0.3, 2.6, 0.22), CFrame.new(0.4, 5, NET_Z)) -- and the mesh at the top
	local ball3d = block(Vector3.one * 1.3, CFrame.new(0, -50, 0), Enum.PartType.Ball)
	if rig then
		rig.model.Parent = world
	end
	-- a speed streak behind the spiked ball, white rings where it lands, the flash
	local streak = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 10), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Visible = false, ZIndex = 11 }, cin)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) }, streak)
	local flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 16 }, gui)

	-- where a point of the scene sits on the screen (Scale units)
	local function screenOf(p)
		local rel = cam.CFrame:PointToObjectSpace(p)
		local size = vp.AbsoluteSize
		local tanY = math.tan(math.rad(cam.FieldOfView) / 2)
		local x = rel.X / (-rel.Z * tanY * size.X / math.max(1, size.Y))
		local y = rel.Y / (-rel.Z * tanY)
		return Vector2.new(0.5 + x / 2, 0.5 - y / 2)
	end

	local function ground()
		if rig then
			local hum = rig.model:FindFirstChildOfClass("Humanoid")
			return (hum and hum.HipHeight or 2) + rig.root.Size.Y / 2
		end
		return 3
	end
	local base = ground()
	local contactHand = SPIKER + Vector3.new(0, base + JUMP + 3.1, -1.4)
	local behind = screenOf(SPIKER + Vector3.new(0, base + JUMP + 1.5, 0))
	glow.Position = UDim2.fromScale(behind.X, behind.Y)

	-- one frame of the play at scene time s
	local function pose(s)
		local up = 0
		local joints = nil
		if AC then
			joints = AC.poseJoints("Gather")
		end
		if s > TAKEOFF then
			local a = math.clamp((s - TAKEOFF) / AIR, 0, 1)
			up = 4 * JUMP * a * (1 - a)
			if AC then
				if s < TAKEOFF + 0.25 then
					joints = AC.poseJoints("Rise")
				elseif s < CONTACT - 0.12 then
					joints = AC.blendJoints(AC.poseJoints("Rise"), cock, (s - TAKEOFF - 0.25) / (CONTACT - 0.12 - TAKEOFF - 0.25))
				elseif s < CONTACT then
					joints = cock
				else
					local st = s - CONTACT
					joints = st < AC.clipDuration(swing) and AC.clipJoints(swing, st) or AC.poseJoints("SpikeFollow")
				end
				if a >= 1 then
					joints = AC.poseJoints("LandCrouch") or joints
				end
			end
		end
		if rig and AC then
			AC.poseModel(rig, joints, CFrame.new(SPIKER + Vector3.new(0, base + up, 0)))
		end
		local hand = SPIKER + Vector3.new(0, base + up + 3.1, -1.4)
		local pos
		if s < CONTACT then
			-- the set drops into the hand
			local a = math.clamp((s - 0.2) / (CONTACT - 0.2), 0, 1)
			pos = hand + Vector3.new(0, 9 * (1 - a), 3 * (1 - a))
		else
			pos = contactHand:Lerp(LAND, math.clamp((s - CONTACT) / FLIGHT, 0, 1))
		end
		ball3d.CFrame = CFrame.new(pos)
		return pos
	end

	-- the streak runs from behind the ball up to it (a frame turns about its centre, so it's
	-- placed by its midpoint)
	local function drawStreak(pos)
		local size = vp.AbsoluteSize
		local a, b = screenOf(contactHand), screenOf(pos)
		local head = Vector2.new(b.X * size.X, b.Y * size.Y)
		local d = head - Vector2.new(a.X * size.X, a.Y * size.Y)
		local len = math.min(d.Magnitude, size.Y * 0.45)
		if len < 4 then
			streak.Visible = false
			return
		end
		local mid = head - d.Unit * (len / 2)
		streak.Visible = true
		streak.Position = UDim2.fromOffset(mid.X, mid.Y)
		streak.Size = UDim2.fromOffset(len, math.max(6, size.Y * 0.012))
		streak.Rotation = math.deg(math.atan2(d.Y, d.X))
	end

	-- cut in from the loading screen
	pose(0)
	cin.BackgroundTransparency = 0
	flash.BackgroundTransparency = 0
	TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	play(C, "Boom", 0.7)

	-- the jump and the spike, slowing into the freeze just before the ball lands
	local start = os.clock()
	local snapped = false
	local promptAt = nil
	while true do
		local r = os.clock() - start
		local s = sceneTime(r)
		local pos = pose(s)
		setGlow(math.clamp((s - 0.3) / 0.6, 0, 1) * 0.9)
		if s >= CONTACT then
			drawStreak(pos)
			if not snapped then
				snapped = true
				play(C, "SpikeHeavy", 1.1)
				flash.BackgroundTransparency = 0.25
				TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(beam, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(1.3, 0.5) }):Play()
				promptAt = os.clock() + FREEZE
			end
		end
		if promptAt and os.clock() >= promptAt then
			break
		end
		RunService.RenderStepped:Wait()
	end

	-- frozen: the title (under Roblox's own buttons) and "Click to continue"
	local logo = make("TextLabel", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.05, 0, 0, GuiService:GetGuiInset().Y + 16),
		Size = UDim2.fromScale(0.5, 0.16),
		BackgroundTransparency = 1,
		Text = "SPIKE RUSH",
		Font = Enum.Font.Bangers,
		TextScaled = true,
		TextColor3 = CHALK,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 14,
	}, cin)
	make("UIStroke", { Color = INK, Thickness = 4 }, logo)
	make("UITextSizeConstraint", { MaxTextSize = 120 }, logo)
	local logoScale = make("UIScale", { Scale = 1.4 }, logo)
	TweenService:Create(logoScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local cont = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.925), -- in the floor's band (the camera puts it in the bottom 15%)
		Size = UDim2.fromOffset(600, 44),
		BackgroundTransparency = 1,
		Text = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) and "Tap to continue" or "Click to continue",
		FontFace = DISPLAY,
		TextSize = 34,
		TextColor3 = CHALK,
		TextTransparency = 1,
		ZIndex = 14,
	}, cin)
	make("UIStroke", { Color = INK, Thickness = 2.5 }, cont)
	local catcher = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 15 }, gui)
	local go = false
	catcher.MouseButton1Click:Connect(function()
		go = true
	end)
	local keys = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.Gamepad1 then
			go = true
		end
	end)
	-- the freeze holds; only the prompt pulses
	pose(sceneTime(os.clock() - start))
	while not go do
		cont.TextTransparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 4))
		RunService.RenderStepped:Wait()
	end
	keys:Disconnect()
	catcher:Destroy()
	cont.Visible = false

	-- the landing: the ball finishes its flight, hits the floor, rings and a white flash
	local from = ball3d.Position
	local land0 = os.clock()
	while os.clock() - land0 < 0.07 do
		local a = (os.clock() - land0) / 0.07
		ball3d.CFrame = CFrame.new(from:Lerp(LAND, a))
		drawStreak(ball3d.Position)
		RunService.RenderStepped:Wait()
	end
	ball3d.CFrame = CFrame.new(LAND)
	streak.Visible = false
	play(C, "FloorHit", 1.2)
	play(C, "Boom", 1)
	flash.BackgroundTransparency = 0
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	local at = screenOf(LAND)
	for i = 1, 3 do
		local ring = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(at.X, at.Y), Size = UDim2.fromOffset(20, 6), BackgroundTransparency = 1, ZIndex = 13 }, cin)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
		local edge = make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 6 - i, Transparency = 0 }, ring)
		local info = TweenInfo.new(0.5 + i * 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, (i - 1) * 0.06)
		TweenService:Create(ring, info, { Size = UDim2.fromOffset(520 + i * 180, 110 + i * 40) }):Play()
		TweenService:Create(edge, info, { Transparency = 1 }):Play()
	end
	-- a short shake, the ball bounces away and the jump plays out to the landing
	local shake0 = os.clock()
	while os.clock() - shake0 < 0.45 do
		local tb = os.clock() - shake0
		local k = 1 - tb / 0.45
		vp.Position = UDim2.fromOffset(rng:NextNumber(-10, 10) * k, rng:NextNumber(-8, 8) * k)
		pose(CONTACT + FLIGHT + tb)
		ball3d.CFrame = CFrame.new(LAND + Vector3.new(0, 16 * tb - 30 * tb * tb, -12 * tb))
		RunService.RenderStepped:Wait()
	end
	vp.Position = UDim2.new()
	return true
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
-- the silhouette needs the controllers and your avatar (the loading animation keeps going)
local C = controllers()
local rig = avatarRig(C)
status.Text = "Ready"
task.wait(0.3)
conn:Disconnect()

local ok, err = pcall(cinematic, C, rig)
if not ok then
	warn("[SpikeRush] loading cinematic: " .. tostring(err))
end

-- fade out into the game
local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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
task.wait(0.65)
gui:Destroy()
