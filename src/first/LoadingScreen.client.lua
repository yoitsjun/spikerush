-- Loading screen (ReplicatedFirst, so it shows before anything else loads).
-- A single frame held like a freeze in a replay: an orange-to-magenta screen, a pillar of light
-- with a black ball at its top, and the VOLLEYBALL RUSH logo top left. While the game loads, a quiet line on
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

local ORANGE = Color3.fromRGB(255, 132, 34)
local INK = Color3.fromRGB(16, 18, 34)
local BEAM = Color3.fromRGB(255, 240, 226)
local MAGENTA = Color3.fromRGB(255, 46, 170)
local WHITE = Color3.new(1, 1, 1)
local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local LOGO_FACE = Font.new(MONTSERRAT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic) -- Heavy is 900: Montserrat Black
local TEXT_FACE = Font.new(MONTSERRAT, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local TIP_FACE = Font.new(MONTSERRAT, Enum.FontWeight.Medium, Enum.FontStyle.Normal)

-- The frame's layout, as fractions of the screen (sizes are fractions of its height).
local HAND_AT = Vector2.new(0.63, 0.5) -- where the pointing hand sits
local BALL_SIZE = 0.105
local BALL_ABOVE = 0.073 -- the ball's centre above the hand
local BEAM_WIDTH = 0.098
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

-- Christmas (the owner, 2026-11-17: "we can probably make this christmas themed, with a lil bell
-- jingle pretty similar to our recruit pull"): while the Winter event is on (Winter.active), the
-- same frame at Christmas: red into deep green, snow falling and drifted along the bottom, a
-- string of lights across the top twinkling in turn, the ball a red ornament, bells as the
-- silhouette rises and a jingle and a burst of snowflakes on the hit. (Roblox's own loading
-- screen holds while this reads the event from ReplicatedStorage.)
local XMAS = false
local FLAKE = ""
pcall(function()
	local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared", 4)
	local w = shared and shared:WaitForChild("Winter", 2)
	if w then
		XMAS = require(w).active() == true
	end
	local a = shared and shared:FindFirstChild("Assets")
	if XMAS and a then
		local Assets = require(a)
		FLAKE = Assets.id(Assets.Images.IconSnowflake) or ""
	end
end)
if XMAS then
	table.insert(TIPS, "Snowflakes recruit on the Winter banner: Jaja and the Christmas skins.")
	table.insert(TIPS, "Jaja's story is in the Winter tab, under Story.")
	table.insert(TIPS, "Winter Pass tiers come with XP from your matches.")
end
local XRED = Color3.fromRGB(206, 28, 48)
local XGREEN = Color3.fromRGB(14, 78, 52)
local LIGHTS = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(90, 230, 120), Color3.fromRGB(255, 206, 80), Color3.fromRGB(90, 170, 255) }

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

local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, gui)
if XMAS then
	make("UIGradient", { Rotation = 35, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, XRED), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 14, 38)), ColorSequenceKeypoint.new(1, XGREEN) }) }, bg)
else
	make("UIGradient", { Rotation = 35, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, ORANGE), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 92, 70)), ColorSequenceKeypoint.new(1, MAGENTA) }) }, bg) -- (orange into magenta: not the old flat amber)
end

-- Christmas: snow falling behind the stage (and a few big flakes), drifts along the bottom, and
-- a string of lights sagging across the top; animated by the loop below until the screen goes
local flakes, bulbs = {}, {}
if XMAS then
	local srng = Random.new()
	for i = 1, 70 do
		local big = i <= 8 and FLAKE ~= ""
		local f
		if big then
			f = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = FLAKE, ImageTransparency = 0.35, Size = UDim2.fromScale(0.035, 0.035), SizeConstraint = Enum.SizeConstraint.RelativeYY, ZIndex = 1 }, bg)
		else
			local d = srng:NextNumber(0.004, 0.011)
			f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, BackgroundTransparency = srng:NextNumber(0.05, 0.5), BorderSizePixel = 0, Size = UDim2.fromScale(d, d), SizeConstraint = Enum.SizeConstraint.RelativeYY, ZIndex = 1 }, bg)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
		end
		table.insert(flakes, { f = f, x = srng:NextNumber(), y = srng:NextNumber(-0.1, 1), v = srng:NextNumber(0.04, 0.1) * (big and 0.7 or 1), sway = srng:NextNumber(0.005, 0.02), seed = srng:NextNumber(0, 10), spin = big and srng:NextNumber(-40, 40) or 0 })
	end
	-- the drifts: soft white mounds along the bottom
	for i = 0, 7 do
		local w = 0.22 + (i % 3) * 0.05
		local m = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(i / 7, 0.9 - (i % 2) * 0.025), Size = UDim2.fromScale(w, 0.3), BackgroundColor3 = Color3.fromRGB(244, 248, 255), BorderSizePixel = 0, ZIndex = 5 }, bg)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, m)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 214, 240)) }, m)
	end
	-- the lights: a wire sagging across the top, a bulb on it every so often
	local N = 26
	local prev
	for i = 0, N do
		local t = i / N
		local pt = Vector2.new(t, 0.035 + 0.07 * 4 * (t * 3 % 1) * (1 - t * 3 % 1)) -- (three swags)
		if prev then
			local wire = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(20, 40, 26), BorderSizePixel = 0, ZIndex = 9 }, bg)
			table.insert(bulbs, { wire = wire, a = prev, b = pt })
		end
		if i > 0 and i < N then
			local c = LIGHTS[i % #LIGHTS + 1]
			local b = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(pt.X, pt.Y), Size = UDim2.fromScale(0.016, 0.026), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundColor3 = c, BorderSizePixel = 0, ZIndex = 9 }, bg)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
			local glow = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromScale(2.6, 2.4), BackgroundColor3 = c, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 8 }, b)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
			make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.05), Size = UDim2.fromScale(0.5, 0.25), BackgroundColor3 = Color3.fromRGB(40, 60, 46), BorderSizePixel = 0, ZIndex = 9 }, b)
			table.insert(bulbs, { bulb = b, glow = glow, i = i })
		end
		prev = pt
	end
end
local function placeWires()
	local size = bg.AbsoluteSize
	for _, w in ipairs(bulbs) do
		if w.wire then
			local a, b = w.a * size, w.b * size
			local d = b - a
			w.wire.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
			w.wire.Size = UDim2.fromOffset(d.Magnitude + 1, 2)
			w.wire.Rotation = math.deg(math.atan2(d.Y, d.X))
		end
	end
end
if XMAS then
	bg:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeWires)
	placeWires()
end
local xmasStart = os.clock()
local xmasConn = XMAS and RunService.RenderStepped:Connect(function(dt)
	local e = os.clock() - xmasStart
	for _, f in ipairs(flakes) do
		f.y = f.y + f.v * dt
		if f.y > 1.05 then
			f.y = -0.05
		end
		f.f.Position = UDim2.fromScale(f.x + math.sin(e * 0.9 + f.seed) * f.sway, f.y)
		if f.spin ~= 0 then
			f.f.Rotation = e * f.spin
		end
	end
	-- the lights chase along the string, each bright in turn and the rest softly lit
	local lead = (e * 9) % 4
	for _, b in ipairs(bulbs) do
		if b.bulb then
			local on = (b.i % 4) == math.floor(lead)
			b.bulb.BackgroundTransparency = on and 0 or 0.3
			b.glow.BackgroundTransparency = on and 0.55 or 0.85
		end
	end
end) or nil

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
if XMAS then
	-- a red glass ornament: its gold cap and loop on top, a shine, a band of gold
	ball.BackgroundColor3 = Color3.fromRGB(214, 28, 46)
	make("UIGradient", { Rotation = 45, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150)) }, ball)
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 0.12), BackgroundColor3 = Color3.fromRGB(255, 206, 80), BorderSizePixel = 0, ZIndex = 5 }, ball)
	local cap = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.06), Size = UDim2.fromScale(0.32, 0.15), BackgroundColor3 = Color3.fromRGB(255, 206, 80), BorderSizePixel = 0, ZIndex = 6 }, ball)
	make("UICorner", { CornerRadius = UDim.new(0.2, 0) }, cap)
	local loop = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(0.6, 1.2), BackgroundTransparency = 1, ZIndex = 6 }, cap)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, loop)
	make("UIStroke", { Color = Color3.fromRGB(255, 206, 80), Thickness = 2 }, loop)
	local shine = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.32, 0.3), Size = UDim2.fromScale(0.22, 0.16), Rotation = -35, BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 6 }, ball)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
end
local streak = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false, ZIndex = 4 }, stage)
make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) }, streak)
local flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 30 }, gui)

------------------------------------------------------------------------------------------
-- the logo: VOLLEYBALL in white with an ink outline, a magenta rim and an ink extrude; RUSH in
-- a magenta-to-pink gradient tucked under it with three speed marks; tilted up a few degrees
------------------------------------------------------------------------------------------

local function buildLogo(parent)
	local box = make("Frame", { BackgroundTransparency = 1, Rotation = -4, ZIndex = 10 }, parent)
	make("UIAspectRatioConstraint", { AspectRatio = 2.6 }, box)
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
	-- (at Christmas, the owner, 2026-11-18: "i think we can recolor the top left volleyball rush": the
	-- magenta reads badly on the red, so the rim is pine green and RUSH is gold)
	local RIM = XMAS and Color3.fromRGB(22, 120, 58) or MAGENTA
	local topSize = UDim2.fromScale(1, 0.5)
	local extrude = word("VOLLEYBALL", UDim2.new(), topSize, INK, 10)
	local rim = word("VOLLEYBALL", UDim2.new(), topSize, RIM, 11)
	local face = word("VOLLEYBALL", UDim2.new(), topSize, WHITE, 12)
	local rush = word("RUSH", UDim2.fromScale(0.36, 0.47), UDim2.fromScale(0.6, 0.5), WHITE, 12)
	if XMAS then
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 244, 190), Color3.fromRGB(255, 186, 36)) }, rush)
	else
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 150, 220), MAGENTA) }, rush)
	end
	local function stroke(label, color)
		return make("UIStroke", { Color = color, LineJoinMode = Enum.LineJoinMode.Round }, label)
	end
	-- stroke widths as fractions of the logo's height
	local strokes = {
		{ stroke(extrude, INK), 0.05 },
		{ stroke(rim, RIM), 0.07 },
		{ stroke(face, INK), 0.032 },
		{ stroke(rush, INK), 0.03 },
	}
	-- speed marks trailing RUSH
	for i, len in ipairs({ 0.2, 0.15, 0.1 }) do
		local m = make("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.335 - (i - 1) * 0.015, 0.6 + (i - 1) * 0.12),
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
logo.Position = UDim2.new(0.03, 0, 0, math.max(GuiService:GetGuiInset().Y, 58) + 10) -- under Roblox's own buttons (the inset reads 0 this early)
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
	TextColor3 = XMAS and WHITE or INK,
	TextTransparency = 0.45,
	ZIndex = 6,
}, bg)
local barBack = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.82, 0, 0.58, 4),
	Size = UDim2.new(0.11, 0, 0, 2),
	BackgroundColor3 = XMAS and WHITE or INK,
	BackgroundTransparency = 0.82,
	BorderSizePixel = 0,
	ZIndex = 6,
}, bg)
local barFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = XMAS and WHITE or INK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 6 }, barBack)
local rng = Random.new()
local tip = make("TextLabel", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0.03, 0, 1, -18),
	Size = UDim2.fromScale(0.5, 0.03),
	BackgroundTransparency = 1,
	Text = TIPS[rng:NextInteger(1, #TIPS)],
	FontFace = TIP_FACE,
	TextScaled = true,
	TextColor3 = XMAS and WHITE or INK,
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
	if XMAS then
		play(C, "WinterBells", 0.7)
	end
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
	if XMAS then
		play(C, "WinterJingle", 0.6)
		-- a burst of snowflakes off the ball
		local hh = bg.AbsoluteSize.Y
		for i = 1, 14 do
			local angle = (i / 14) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local dir = Vector2.new(math.cos(angle), math.sin(angle))
			local s = hh * rng:NextNumber(0.03, 0.06)
			local f = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(at.X, 0, at.Y, 0), Size = UDim2.fromOffset(s, s), BackgroundTransparency = 1, Image = FLAKE, ZIndex = 8 }, stage)
			local dist = hh * rng:NextNumber(0.18, 0.34)
			TweenService:Create(f, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(at.X, dir.X * dist, at.Y, dir.Y * dist), Rotation = rng:NextNumber(-180, 180), ImageTransparency = 1 }):Play()
		end
	end
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
	local to = Vector2.new(ballAt.X + 0.75, 1.25) -- down and forward (the figure faces right), off the screen
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
-- (back from the AFK Lounge's refresh, a teleport: straight in, nobody's there to click)
local go = false
pcall(function()
	local data = game:GetService("TeleportService"):GetLocalPlayerTeleportData()
	go = type(data) == "table" and data.lounge == true
end)
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
	if d:IsA("ViewportFrame") or d:IsA("ImageLabel") then
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
if xmasConn then
	xmasConn:Disconnect()
end
gui:Destroy()
