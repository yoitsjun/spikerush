-- Loading screen (ReplicatedFirst, so it shows before anything else loads).
-- Soft grey stadium light, bubbles drifting up, light rays and a big yellow / blue / white ball
-- spinning over the title, a rotating tip and a progress bar. It stays up until the game has
-- loaded and the client controllers have started (Main.client sets "SpikeRushLoaded"), then
-- fades out. All shapes are plain GUI objects: no assets to upload.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local MAX_WAIT = 25 -- never hold a player on this screen longer than this

local INK = Color3.fromRGB(20, 23, 43)
local SPARK = Color3.fromRGB(255, 225, 77)
local BLUE = Color3.fromRGB(34, 86, 196)
local YELLOW = Color3.fromRGB(255, 205, 40)
local CHALK = Color3.fromRGB(244, 247, 255)

local TIPS = {
	"Spike power comes from clean contact at the top of your jump.",
	"Press receive a little early: the stance stays armed.",
	"A 4.00 m hitting point turns Thunder Spiker on.",
	"Azure Dragon: hold spike in the air to charge. You fall slower while charging.",
	"Hold W and release to jump for a block.",
	"Out of guard? Slide receives never cost stamina.",
	"Spin stat caps and height with V Points in the Shop tab.",
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

-- animation
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

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local waited = 0
while not player:GetAttribute("SpikeRushLoaded") and waited < MAX_WAIT do
	waited = waited + task.wait(0.1)
end
status.Text = "Ready"
task.wait(0.35)

-- fade out
local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
for _, d in ipairs(gui:GetDescendants()) do
	if d:IsA("Frame") then
		TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
	elseif d:IsA("TextLabel") then
		TweenService:Create(d, info, { TextTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, info, { Transparency = 1 }):Play()
	end
end
task.wait(0.55)
conn:Disconnect()
gui:Destroy()
