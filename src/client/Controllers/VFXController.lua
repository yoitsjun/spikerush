-- Anime-style effects for the side view. Everything in the world is a hand-drawn particle kit
-- from Fx (anime flipbooks out of Creator Store VFX packs), and any kit can be swapped for a
-- Toolbox effect in ReplicatedStorage.ToolboxAssets.VFX.<Name>.
--  * contact: comic hit stars, ring flipbooks and streaking sparks; lightning sprites (Thunder
--    Spiker), blue flames (Azure Dragon), sonic-boom rings chasing the hardest spikes
--  * jumps: a shock disc and cel-shaded dust under the feet
--  * screen: white flash, speed-line streaks, and the impact frame: the screen goes white, the
--    attacker becomes a black silhouette over hand-drawn speed lines for a split second
--  * text: receive grades ("PERFECT 96" with a badge), callouts ("Free ball!", "Stuff!")
--  * unlockables: the attacker's spike colour tints the impact; their score effect (fire
--    explosion, meteor strike, thunderbolt, shockwave) plays where the point lands
-- Kits, sonic rings and the parts left (blades, walls) are pooled; popups and the impact frame
-- are short-lived.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Util = require(Shared.Util)
local BallPhysics = require(Shared.BallPhysics)
local Spins = require(Shared.Spins)
local Court = require(Shared.Court)
local State = require(script.Parent.State)
local Fx = require(script.Parent.Fx)

local VFXController = {}
local mods

local player = Players.LocalPlayer
local UI = Config.UI
local WHITE = Color3.new(1, 1, 1)
local THUNDER = Color3.fromRGB(255, 226, 60)
local AZURE = Color3.fromRGB(70, 210, 255)
local HOT = Color3.fromRGB(255, 50, 90)
local VECTOR = Config.Abilities.Vector.Color
local COUNTER = Config.Abilities.Counter.Color
local FERAL = Config.Abilities.Feral.Color
local FERAL_HOT = Color3.fromRGB(255, 80, 210)
local FERAL_LIGHT = Color3.fromRGB(225, 185, 255)

local fxFolder
local pool = {}
local screen, flashFrame, linesFrame
local lines = {}
local linesUntil, linesDir = 0, 1
local impactGui
local auras = {}
local streaks = {}
-- the charge arcs (Feral Leap's, Azure Dragon's): model -> the arc's parts and state; made and
-- dropped by the functions further down, which the Azure aura uses too
local arcs = {}
local newArc, dropArc

-- the HUD's display face: heavy italic
local DISPLAY = Font.new(Assets.Fonts.Display, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

local GRADE_COLOR = {
	PERFECT = UI.Spark,
	GREAT = Color3.fromRGB(255, 160, 70),
	GOOD = UI.Chalk,
	BAD = Color3.fromRGB(170, 176, 200),
	BROKEN = HOT,
}

local function teamColor(team)
	local t = Config.Teams[team or ""]
	return t and t.Color or UI.Chalk
end

local function near(pos)
	local cam = workspace.CurrentCamera
	return cam ~= nil and math.abs(cam.CFrame.Position.Z - pos.Z) < 85
end

------------------------------------------------------------------------------------------
-- pooled parts
------------------------------------------------------------------------------------------

local PARKED = CFrame.new(0, -500, 0)

local function newPart(shape)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = 1
	p.CFrame = PARKED
	p.Parent = fxFolder
	return p
end

-- Idle parts wait on a free list per shape (no attribute scans, no allocation once warm).
local function take(shape)
	local list = pool[shape]
	if list and #list > 0 then
		return table.remove(list)
	end
	return newPart(shape)
end

local function release(p)
	p.Transparency = 1
	p.CFrame = PARKED
	local list = pool[p.Shape]
	if not list then
		list = {}
		pool[p.Shape] = list
	end
	table.insert(list, p)
end

------------------------------------------------------------------------------------------
-- building blocks: the calls the effects below are written in, drawn with Fx's kits
------------------------------------------------------------------------------------------

-- a soft glow about `radius` studs across
local function burst(pos, color, radius)
	Fx.play("Glow", pos, { color = color, scale = radius / 4 })
end

-- a shock disc on the floor out to `radius` studs
local function floorRing(pos, color, radius)
	Fx.play("Wave", Vector3.new(pos.X, 0.25, pos.Z), { color = color, scale = radius / 5.5 })
end

-- streaking sparks thrown out in the play plane
local function shards(pos, color, count, speed)
	Fx.play("Sparks", pos, { color = color, n = count, scale = math.clamp(speed / 55, 0.6, 1.5) })
end

-- The camera looks along +x, so screen right is +z and up is +y: an upright sprite turns
-- clockwise by this many degrees to point along a world direction.
local function screenAngle(dir)
	return math.deg(math.atan2(dir.Z, dir.Y))
end

-- a lightning bolt sprite from `from` along `dir`
local function bolt(from, dir, length, color)
	Fx.play("Bolt", from + dir * (length / 2), { color = color, scale = length / 10, angle = screenAngle(dir) })
end

-- a ring flipbook growing out to `toSize` studs
local function ringFx(pos, color, _, toSize)
	Fx.play("Ring", pos, { color = color, scale = toSize / 10 })
end

-- a comic hit star about `size` studs across (a many-pointed burst when big)
local function starburst(pos, color, size)
	if size >= 10 then
		Fx.play("Burst", pos, { color = color, scale = size / 11 })
	else
		Fx.play("Star", pos, { color = color, scale = size / 7.5 })
	end
end

-- A pillar of light shooting up out of the floor and thinning away.
local function lightPillar(pos, color, height, width)
	local p = take(Enum.PartType.Cylinder)
	p.Color = color
	p.Size = Vector3.new(0.5, width, width)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	p.Transparency = 0.1
	local up = TweenService:Create(p, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(height, width, width),
		CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	up:Play()
	task.delay(0.16, function()
		local fade = TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(height * 1.1, 0.2, 0.2), Transparency = 1 })
		fade:Play()
		task.delay(0.52, release, p)
	end)
end

-- sparks, dust and flames in the counts the effects were tuned with
local SHARE = { Sparks = 0.4, Dust = 0.5, Fire = 0.35 }
local function emit(kit, pos, count, color)
	Fx.play(kit, pos, { color = color, n = math.max(1, math.ceil(count * SHARE[kit])) })
end

------------------------------------------------------------------------------------------
-- billboards: popups, and the sonic booms around a hard spike
------------------------------------------------------------------------------------------

local sonicPool = {}

-- One-off billboard (popups): the gui is destroyed afterwards, the anchor goes back to the pool.
local function billboard(pos, size)
	local anchor = take(Enum.PartType.Block)
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(size, 0, size, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	return gui, anchor
end

-- A sonic-boom ring, as on The Spike's hardest spikes: a thin hand-drawn ring squeezed into an
-- ellipse standing across the ball's flight. The flight's angle on screen is atan2(vy, vz) and
-- a GUI rotation is clockwise, hence the minus.
local function sonicRing(pos, vel, color, size, duration)
	local e = table.remove(sonicPool)
	if not e then
		local anchor = newPart(Enum.PartType.Block)
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		local gui = Instance.new("BillboardGui")
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Adornee = anchor
		gui.Enabled = false
		gui.Parent = anchor
		local img = Instance.new("ImageLabel")
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(0.36, 1)
		img.BackgroundTransparency = 1
		img.Image = Assets.id(Assets.Fx.Ring) or ""
		img.Parent = gui
		e = { gui = gui, anchor = anchor, img = img }
	end
	e.anchor.CFrame = CFrame.new(pos)
	e.gui.Size = UDim2.new(size * 0.4, 0, size * 0.4, 0)
	e.img.ImageColor3 = color
	e.img.ImageTransparency = 0
	e.img.Rotation = -math.deg(math.atan2(vel.Y, vel.Z))
	e.gui.Enabled = true
	TweenService:Create(e.gui, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(size, 0, size, 0) }):Play()
	TweenService:Create(e.img, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1 }):Play()
	task.delay(duration + 0.05, function()
		e.gui.Enabled = false
		e.anchor.CFrame = PARKED
		table.insert(sonicPool, e)
	end)
end

------------------------------------------------------------------------------------------
-- screen effects
------------------------------------------------------------------------------------------

local function buildScreen()
	screen = Instance.new("ScreenGui")
	screen.Name = "SpikeRushFX"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 5
	screen.Parent = player:WaitForChild("PlayerGui")

	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundColor3 = WHITE
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Parent = screen

	linesFrame = Instance.new("Frame")
	linesFrame.Size = UDim2.fromScale(1, 1)
	linesFrame.BackgroundTransparency = 1
	linesFrame.Visible = false
	linesFrame.Parent = screen
	-- speed lines: tapered hand-drawn strokes (the spark streak), not flat bars
	local stroke = Assets.id(Assets.Fx.Streak) or ""
	local count = State.isMobile and 14 or 24
	for i = 1, count do
		local l = Instance.new("ImageLabel")
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.BackgroundTransparency = 1
		l.Image = stroke
		l.Parent = linesFrame
		lines[i] = { frame = l, x = math.random(), y = math.random(), len = 0.1, speed = 1 }
	end

	-- glowing streaks that flash across the screen on the biggest hits
	for i = 1, 4 do
		local f = Instance.new("ImageLabel")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundTransparency = 1
		f.Image = stroke
		f.ImageTransparency = 1
		f.Size = UDim2.new(1.2, 0, 0, 12)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Parent = screen
		streaks[i] = f
	end

	impactGui = Instance.new("ScreenGui")
	impactGui.Name = "SpikeRushImpact"
	impactGui.IgnoreGuiInset = true
	impactGui.ResetOnSpawn = false
	impactGui.DisplayOrder = 20
	impactGui.Enabled = false
	impactGui.Parent = player:WaitForChild("PlayerGui")
end

function VFXController.flash(strength, duration)
	flashFrame.BackgroundTransparency = 1 - strength
	TweenService:Create(flashFrame, TweenInfo.new(duration or 0.25), { BackgroundTransparency = 1 }):Play()
end

-- Horizontal streaks racing across the screen in the ball's direction (dir: +1 right, -1 left).
function VFXController.speedLines(duration, color, dir)
	if not State.settings.dramatic then
		return
	end
	linesUntil = os.clock() + duration
	linesDir = dir or 1
	for _, l in ipairs(lines) do
		l.frame.ImageColor3 = color or WHITE
		l.x = math.random()
		l.y = 0.08 + math.random() * 0.84
		l.len = 0.12 + math.random() * 0.25
		l.speed = 2.2 + math.random() * 2.5
	end
	linesFrame.Visible = true
end

local function updateLines(dt)
	if not linesFrame.Visible then
		return
	end
	local left = linesUntil - os.clock()
	if left <= 0 then
		linesFrame.Visible = false
		return
	end
	local fade = math.clamp(left / 0.25, 0, 1)
	for _, l in ipairs(lines) do
		l.x = l.x + linesDir * l.speed * dt
		if l.x > 1.3 then
			l.x = -0.3
		elseif l.x < -0.3 then
			l.x = 1.3
		end
		l.frame.Position = UDim2.fromScale(l.x, l.y)
		l.frame.Size = UDim2.new(l.len, 0, 0, l.speed > 3.5 and 12 or 7)
		l.frame.ImageTransparency = 1 - 0.8 * fade
	end
end

-- Where the ball sits in a frozen frame: on the tip of the hitter's right hand in that pose (the
-- owner: "its swinging right below the ball"), so the frame always shows the hit; `fallback`
-- when the clone has no hand.
local function handBall(clone, fallback)
	local hand = clone and (clone:FindFirstChild("RightHand", true) or clone:FindFirstChild("Right Arm", true))
	if not hand or not hand:IsA("BasePart") then
		return fallback
	end
	return (hand.CFrame * CFrame.new(0, -(hand.Size.Y / 2 + Config.Ball.Radius * 0.8), 0)).Position
end

local function silhouette(model, vp)
	local was = model.Archivable
	model.Archivable = true
	local ok, clone = pcall(function()
		return model:Clone()
	end)
	model.Archivable = was
	if not ok or not clone then
		return nil
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Highlight") or d:IsA("Decal") or d:IsA("SurfaceAppearance") or d:IsA("Light") or d:IsA("VectorForce") then
			d:Destroy()
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Color = Color3.new(0, 0, 0)
			d.Material = Enum.Material.SmoothPlastic
			if d:IsA("MeshPart") then
				pcall(function()
					d.TextureID = ""
				end)
			end
			if d.Name == "HumanoidRootPart" then
				d.Transparency = 1
			end
		end
	end
	local world = Instance.new("WorldModel")
	world.Parent = vp
	clone.Parent = world
	return clone
end

-- The manga impact frame: white screen, black silhouette, coloured radial burst.
function VFXController.impactFrame(entityId, color)
	if not State.settings.dramatic then
		return
	end
	local cam = workspace.CurrentCamera
	local model = Util.modelOf(entityId)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not cam or not hrp then
		VFXController.flash(0.7, 0.2)
		return
	end
	impactGui:ClearAllChildren()
	if mods then
		mods.AudioController.play("ImpactFrame", { minGap = 0.2 })
	end
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = WHITE
	bg.BorderSizePixel = 0
	bg.Parent = impactGui

	local sp = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 1.5, 0))
	local vs = cam.ViewportSize
	local tint = color or HOT
	local function sprite(parent, key, size, props)
		local img = Instance.new("ImageLabel")
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(size, size)
		img.BackgroundTransparency = 1
		img.Image = Assets.id(Assets.Fx[key]) or ""
		for k, v in pairs(props or {}) do
			img[k] = v
		end
		img.Parent = parent
		return img
	end
	-- speed lines rushing into the hitter, a glow and a comic hit star, in the attack's colour
	local burstFrame = Instance.new("Frame")
	burstFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	burstFrame.Position = UDim2.fromOffset(sp.X, sp.Y)
	burstFrame.Size = UDim2.fromOffset(vs.Y * 1.3, vs.Y * 1.3)
	burstFrame.BackgroundTransparency = 1
	burstFrame.Parent = bg
	local images = {
		sprite(burstFrame, "Radial", 1.5, { ImageColor3 = tint, Rotation = math.random() * 360 }),
		sprite(burstFrame, "Radial", 1, { ImageColor3 = tint, Rotation = math.random() * 360 }),
		sprite(burstFrame, "Glow", 0.75, { ImageColor3 = tint, ImageTransparency = 0.25 }),
		sprite(burstFrame, "HitStar", 0.42, { ImageColor3 = tint:Lerp(WHITE, 0.35), Rotation = math.random() * 360 }),
	}
	-- a pillar of light through the hitter
	local pillar = Instance.new("Frame")
	pillar.AnchorPoint = Vector2.new(0.5, 0.5)
	pillar.Position = UDim2.fromOffset(sp.X, sp.Y)
	pillar.Size = UDim2.new(0, math.floor(vs.Y * 0.07), 2, 0)
	pillar.BackgroundColor3 = WHITE
	pillar.BorderSizePixel = 0
	pillar.Parent = bg
	local pg = Instance.new("UIGradient")
	pg.Color = ColorSequence.new(tint, WHITE)
	pg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 0.1),
		NumberSequenceKeypoint.new(0.6, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	pg.Parent = pillar
	-- a gold crescent slash across the swing
	local slash = Instance.new("Frame")
	slash.AnchorPoint = Vector2.new(0.5, 0.5)
	slash.Position = UDim2.fromOffset(sp.X, sp.Y)
	slash.Size = UDim2.fromOffset(vs.Y * 0.6, vs.Y * 0.6)
	slash.BackgroundTransparency = 1
	slash.Parent = bg
	table.insert(images, sprite(slash, "Slash", 1, { ImageColor3 = Color3.fromRGB(255, 205, 70), Rotation = -40 + math.random() * 80 }))

	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.new(0, 0, 0)
	vp.LightColor = Color3.new(0, 0, 0)
	vp.Parent = bg
	local vcam = Instance.new("Camera")
	vcam.CFrame = cam.CFrame
	vcam.FieldOfView = cam.FieldOfView
	vcam.Parent = vp
	vp.CurrentCamera = vcam
	silhouette(model, vp)

	impactGui.Enabled = true
	task.delay(0.09, function()
		local fade = TweenInfo.new(0.14)
		TweenService:Create(bg, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(vp, fade, { ImageTransparency = 1 }):Play()
		for _, img in ipairs(images) do
			TweenService:Create(img, fade, { ImageTransparency = 1 }):Play()
		end
		TweenService:Create(pillar, TweenInfo.new(0.16), { BackgroundTransparency = 1 }):Play()
	end)
	task.delay(0.26, function()
		impactGui.Enabled = false
		impactGui:ClearAllChildren()
	end)
end

-- The freeze frame (Zero Point, Dante's First Strike; the owner's reference: a black silhouette on
-- white between letterbox bars): while the ball holds on the hand, a close shot of the hitter
-- and the ball in black on white, pushing in slowly; it snaps away as the ball fires.
local freezeGui = nil
local freezeToken = nil -- the frame on screen now (an older one's cleanup leaves a newer one be)
-- the screen the freeze frames draw on, emptied; returns the new frame's token
local function freezeScreen()
	if not freezeGui then
		freezeGui = Instance.new("ScreenGui")
		freezeGui.Name = "SpikeRushFreeze"
		freezeGui.IgnoreGuiInset = true
		freezeGui.ResetOnSpawn = false
		freezeGui.DisplayOrder = 21
		freezeGui.Parent = player:WaitForChild("PlayerGui")
	end
	freezeGui:ClearAllChildren()
	freezeToken = {}
	return freezeToken
end

function VFXController.freezeFrame(entityId, ballPos, duration, color)
	local cam = workspace.CurrentCamera
	local model = Util.modelOf(entityId)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not cam or not hrp or duration <= 0.05 then
		return false
	end
	local token = freezeScreen()
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = color or WHITE -- (Dante's First Strike: purple, the owner's call)
	bg.BorderSizePixel = 0
	bg.Parent = freezeGui
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.new(0, 0, 0)
	vp.LightColor = Color3.new(0, 0, 0)
	vp.Parent = bg
	-- side on and close, framing the hitter and the ball over their hand
	local mid = hrp.Position:Lerp(ballPos, 0.55)
	local vcam = Instance.new("Camera")
	vcam.FieldOfView = 30
	vcam.CFrame = CFrame.lookAt(mid + Vector3.new(-30, 0.5, 0), mid)
	vcam.Parent = vp
	vp.CurrentCamera = vcam
	local clone = silhouette(model, vp)
	if clone then
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * (Config.Ball.Radius * 2)
		ball.Anchored = true
		ball.Color = Color3.new(0, 0, 0)
		ball.Material = Enum.Material.SmoothPlastic
		ballPos = handBall(clone, ballPos)
		ball.CFrame = CFrame.new(ballPos)
		ball.Parent = clone.Parent
	end
	-- the letterbox
	for _, top in ipairs({ true, false }) do
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0, top and 0 or 1)
		bar.Position = UDim2.fromScale(0, top and 0 or 1)
		bar.Size = UDim2.fromScale(1, 0.1)
		bar.ZIndex = 3
		bar.Parent = bg
	end
	freezeGui.Enabled = true
	TweenService:Create(vcam, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { FieldOfView = 25 }):Play()
	task.delay(duration, function()
		TweenService:Create(bg, TweenInfo.new(0.08), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(vp, TweenInfo.new(0.08), { ImageTransparency = 1 }):Play()
		task.delay(0.09, function()
			if freezeToken == token then
				freezeGui.Enabled = false
				freezeGui:ClearAllChildren()
			end
		end)
	end)
	return true
end

-- The dark freeze frame (the S+ signature hits; the owner's reference: the court goes dark, the
-- hitter lit white and the ball glowing in their hand): the same view as the game's camera, held
-- while the ball holds on the hand.
function VFXController.darkFrame(entityId, ballPos, duration, color)
	local cam = workspace.CurrentCamera
	local model = Util.modelOf(entityId)
	if not cam or not model or duration <= 0.05 then
		return false
	end
	local token = freezeScreen()
	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(4, 4, 10)
	shade.BackgroundTransparency = 0.22
	shade.BorderSizePixel = 0
	shade.Parent = freezeGui
	-- the hitter and the ball, lit white, over the dark
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(235, 235, 245)
	vp.LightColor = WHITE
	vp.LightDirection = Vector3.new(1, -1, 0)
	vp.Parent = freezeGui
	local vcam = Instance.new("Camera")
	vcam.CFrame = cam.CFrame
	vcam.FieldOfView = cam.FieldOfView
	vcam.Parent = vp
	vp.CurrentCamera = vcam
	local clone = silhouette(model, vp)
	if clone then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Color = Color3.fromRGB(245, 245, 250)
			end
		end
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * (Config.Ball.Radius * 2)
		ball.Anchored = true
		ball.Color = color or Color3.fromRGB(255, 200, 60)
		ball.Material = Enum.Material.SmoothPlastic
		ballPos = handBall(clone, ballPos)
		ball.CFrame = CFrame.new(ballPos)
		ball.Parent = clone.Parent
	end
	-- a soft glow where the hand meets the ball
	local sp = cam:WorldToViewportPoint(ballPos)
	local glow = Instance.new("ImageLabel")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromOffset(sp.X, sp.Y)
	glow.Size = UDim2.fromOffset(cam.ViewportSize.Y * 0.28, cam.ViewportSize.Y * 0.28)
	glow.BackgroundTransparency = 1
	glow.Image = Assets.id(Assets.Fx.Glow) or ""
	glow.ImageColor3 = WHITE
	glow.ImageTransparency = 0.05
	glow.ZIndex = 2
	glow.Parent = freezeGui
	freezeGui.Enabled = true
	task.delay(duration, function()
		local out = TweenInfo.new(0.1)
		TweenService:Create(shade, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(vp, out, { ImageTransparency = 1 }):Play()
		TweenService:Create(glow, out, { ImageTransparency = 1 }):Play()
		task.delay(0.11, function()
			if freezeToken == token then
				freezeGui.Enabled = false
				freezeGui:ClearAllChildren()
			end
		end)
	end)
	return true
end

------------------------------------------------------------------------------------------
-- popups
------------------------------------------------------------------------------------------

function VFXController.popup(pos, text, color, size, badge)
	local gui, anchor = billboard(pos, 1)
	gui.Size = UDim2.fromOffset(300, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	local fades = {}
	if badge then
		-- the shield icon: perfect receives drain almost no stamina
		local b = Instance.new("ImageLabel")
		b.Size = UDim2.fromOffset(36, 36)
		b.BackgroundTransparency = 1
		b.Image = Assets.image("IconDefense") or ""
		b.ImageColor3 = color
		b.LayoutOrder = 1
		b.Parent = row
		table.insert(fades, { b, "ImageTransparency" })
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.FontFace = DISPLAY
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 44
	label.Rotation = -5
	label.LayoutOrder = 2
	label.Parent = row
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = UI.Ink
	stroke.Parent = label
	table.insert(fades, { label, "TextTransparency" })
	table.insert(fades, { stroke, "Transparency" })
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = row
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = size or 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0) }):Play()
	task.delay(0.65, function()
		for _, f in ipairs(fades) do
			local goal = {}
			goal[f[2]] = 1
			TweenService:Create(f[1], TweenInfo.new(0.3), goal):Play()
		end
	end)
	task.delay(1.0, function()
		gui:Destroy()
		release(anchor)
	end)
end

------------------------------------------------------------------------------------------
-- jumps, auras
------------------------------------------------------------------------------------------

-- The "boom" under a jumper's feet.
-- Boom jumps (the shockwave off the floor) need a big Jump stat (Player.BoomJumpMin);
-- everyone else just kicks up a little dust.
function VFXController.hasBoom(model)
	return model ~= nil and (model:GetAttribute("Jump") or 0) >= Config.Player.BoomJumpMin
end

function VFXController.boom(entityId, kind)
	local model = Util.modelOf(entityId)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local p = hrp.Position
	local foot = Vector3.new(p.X, 0.25, p.Z)
	-- your own jump sound (the Custom sound effects perk) on every jump; the boom's otherwise
	local own = entityId == State.myId and mods ~= nil and mods.AudioController.custom(entityId, "SoundJump", { volume = 0.7 })
	if not VFXController.hasBoom(model) then
		Fx.play("Dust", foot, { n = 3, scale = 0.7 })
		return
	end
	local big = kind == "Spike" or kind == "Serve"
	if entityId == State.myId and mods and not own then
		mods.AudioController.play("Boom", { volume = big and 0.8 or 0.45, minGap = 0.05 })
	end
	-- the owner: "have the boom jump be more exaggerated, and cool. this should feel powerful when
	-- you jump", then "i dont think it needs a beam of light"): in their spike colour (else the
	-- team's), two shock rings across the floor, a starburst and sparks at the feet, and for your
	-- own jump the screen kicks
	local color = Spins.tint(Spins.equipped(model, "Color")) or teamColor(model:GetAttribute("Team"))
	local k = big and 1 or 0.55
	Fx.play("JumpBoom", foot, { scale = 1.6 * k, count = 1.4 * k })
	floorRing(foot, color, 16 * k)
	task.delay(0.07, floorRing, foot, WHITE, 10 * k)
	starburst(foot + Vector3.new(0, 1, 0), color, 9 * k)
	shards(foot + Vector3.new(0, 0.6, 0), color, math.floor(18 * k), 70)
	if entityId == State.myId and mods then
		mods.CameraController.shake(big and 0.45 or 0.2)
		mods.CameraController.kick(big and -4 or -2)
		if big then
			VFXController.flash(0.12, 0.15)
		end
	end
end


-- The charging hand: an energy orb, swirling sparks and a light on the hitting hand.
local function handFx(model, hrp)
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm") or hrp
	local att = Instance.new("Attachment")
	att.Name = "AzureHand"
	att.Parent = hand
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = Assets.id(Assets.Fx.Glint) or ""
	sparks.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255), AZURE)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Rate = 40
	sparks.Lifetime = NumberRange.new(0.18, 0.4)
	sparks.Speed = NumberRange.new(1.5, 4)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.RotSpeed = NumberRange.new(-180, 180)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.LockedToPart = true
	sparks.Parent = att
	local light = Instance.new("PointLight")
	light.Color = AZURE
	light.Range = 6
	light.Brightness = 1
	light.Shadows = false
	light.Parent = att
	-- the orb, sized in studs: a glow, a white core and a spinning crescent of a ring
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(1, 0, 1, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = att
	gui.Parent = att
	local function sprite(key, size, color)
		local img = Instance.new("ImageLabel")
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(size, size)
		img.BackgroundTransparency = 1
		img.Image = Assets.id(Assets.Fx[key]) or ""
		img.ImageColor3 = color
		img.Parent = gui
		return img
	end
	local glowDisc = sprite("Glow", 1.9, AZURE)
	sprite("Dot", 0.75, WHITE)
	local ring = sprite("Ring", 1.45, Color3.fromRGB(190, 245, 255))
	local rg = Instance.new("UIGradient")
	rg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0),
		NumberSequenceKeypoint.new(0.55, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	rg.Parent = ring
	return { att = att, sparks = sparks, light = light, gui = gui, glow = glowDisc, ring = ring }
end

local function applyEnergy(fx, e)
	e = math.clamp(e, 0, 1.3)
	fx.energy = e
	-- 30 + 110 * e flames a second at the kit's base 40: about 0.75x to 4.3x
	local over = e > 1
	fx.aura.set(true, over and HOT or nil, (30 + 110 * e) / 40)
	local color = over and HOT or AZURE
	fx.hl.FillTransparency = 0.85 - 0.35 * math.min(e, 1)
	fx.hl.FillColor = color
	local h = fx.hand
	local size = 0.8 + 2.6 * math.min(e, 1)
	h.gui.Size = UDim2.new(size, 0, size, 0)
	h.glow.ImageColor3 = color
	h.ring.ImageColor3 = over and Color3.fromRGB(255, 170, 190) or Color3.fromRGB(190, 245, 255)
	h.light.Color = color
	h.light.Range = 6 + 10 * math.min(e, 1)
	h.light.Brightness = 1 + 3 * math.min(e, 1)
	h.sparks.Rate = 30 + 120 * math.min(e, 1)
	h.sparks.Color = ColorSequence.new(Color3.fromRGB(230, 250, 255), color)
	-- the curved gauge behind them fills with it (red once it's held too long)
	local arc = fx.model and arcs[fx.model]
	if arc and arc.kind == "azure" then
		arc.value = math.min(e, 1)
		arc.over = over or nil
	end
end

-- remote: other players' and bots' charges grow on this client's clock
local function setAura(model, on, energy, remote)
	local fx = auras[model]
	if not on then
		if fx then
			fx.att:Destroy()
			fx.hl:Destroy()
			fx.hand.att:Destroy()
			auras[model] = nil
		end
		if arcs[model] and arcs[model].kind == "azure" then
			dropArc(model)
		end
		return
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	if not arcs[model] then
		arcs[model] = newArc(model, hrp, "azure")
	end
	if not fx then
		local att = Instance.new("Attachment")
		att.Name = "AzureAura"
		att.Parent = hrp
		local hl = Instance.new("Highlight")
		hl.FillColor = AZURE
		hl.FillTransparency = 0.8
		hl.OutlineColor = Color3.fromRGB(180, 250, 255)
		hl.OutlineTransparency = 0.2
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
		fx = { model = model, att = att, aura = Fx.attach("AzureAura", att), hl = hl, hand = handFx(model, hrp), t0 = os.clock(), remote = remote }
		auras[model] = fx
	end
	applyEnergy(fx, energy or 0)
end

-- spin the orb rings and grow remote charges
------------------------------------------------------------------------------------------
-- role abilities
------------------------------------------------------------------------------------------

local walls = {} -- entityId -> { part, untilT, side }
local statusFx = {} -- model -> kind -> { att, aura, hl }
local sunSeen = {} -- model -> the Sunrise level last shown

-- Rising Sun levels up: a pillar of light strikes the player out of the sky (the owner's
-- reference: a tall orange-to-red column over them). Two camera-facing beams, a wide hot column
-- and a white core, drop from the top in a blink, hold with a flicker, then flare and fade.
local BEAM_H = 140
local function sunBeam(root)
	local floorY = root.Y - 3
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(root.X, floorY, root.Z)
	part.Parent = fxFolder
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, BEAM_H, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, BEAM_H, 0)
	bottom.Parent = part
	local function beam(width, colors, light)
		local b = Instance.new("Beam")
		b.Attachment0 = bottom
		b.Attachment1 = top
		b.FaceCamera = true
		b.LightEmission = light
		b.LightInfluence = 0
		b.Segments = 1
		b.Width0 = width
		b.Width1 = width
		b.Color = colors
		b.Transparency = NumberSequence.new(0)
		b.Parent = part
		return b
	end
	-- the column keeps its colour against a bright sky (little additive light); the core glows
	local outer = beam(7, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 30)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 95, 25)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 25, 25)),
	}), 0.1)
	local core = beam(1.6, ColorSequence.new(Color3.fromRGB(255, 245, 200), Color3.fromRGB(255, 170, 80)), 1)
	local t0 = os.clock()
	local STRIKE, HOLD, FADE = 0.12, 0.7, 0.45
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t < STRIKE then
			-- the column falls from the sky onto them
			bottom.Position = Vector3.new(0, BEAM_H * (1 - t / STRIKE), 0)
		elseif t < STRIKE + HOLD then
			bottom.Position = Vector3.zero
			local f = 0.08 * math.sin(t * 60)
			outer.Width0, outer.Width1 = 7 + f * 10, 7 + f * 10
			outer.Transparency = NumberSequence.new(0.1 + math.abs(f))
		elseif t < STRIKE + HOLD + FADE then
			local k = (t - STRIKE - HOLD) / FADE
			outer.Width0, outer.Width1 = 7 + 9 * k, 7 + 9 * k
			core.Width0, core.Width1 = 1.6 * (1 - k), 1.6 * (1 - k)
			outer.Transparency = NumberSequence.new(0.1 + 0.9 * k)
			core.Transparency = NumberSequence.new(k)
		else
			conn:Disconnect()
			part:Destroy()
		end
	end)
	Fx.play("JumpBoom", Vector3.new(root.X, floorY + 0.2, root.Z), { color = Color3.fromRGB(255, 150, 40), scale = 1.4 })
	Fx.play("Fire", Vector3.new(root.X, floorY + 1, root.Z), { color = Color3.fromRGB(255, 120, 40), scale = 1.2 })
end
local nextStatusScan = 0

-- Auras for boosts the server flags on characters (and the team's Rally Cry): flame colours,
-- how hard they burn, and a highlight for the loud ones.
local STATUS = {
	Adrenaline = { fire = { Color3.fromRGB(255, 90, 60), Color3.fromRGB(255, 30, 40) }, rate = 28, fill = Color3.fromRGB(255, 60, 50), edge = Color3.fromRGB(255, 90, 70) },
	Sun = { fire = { Color3.fromRGB(255, 230, 140), Config.Abilities.RisingSun.Color }, rate = 9, size = 2.6 },
	Rally = { fire = { Color3.fromRGB(255, 255, 220), Config.Abilities.RallyCry.Color }, rate = 14, fill = Config.Abilities.RallyCry.Color, edge = Color3.fromRGB(255, 240, 170) },
	Armed = { fire = { Color3.fromRGB(230, 255, 245), Config.Abilities.Turnabout.Color }, rate = 22, size = 1.6 },
	Edge = { fire = { Color3.fromRGB(255, 255, 255), Config.Abilities.Counter.Color }, rate = 30, size = 1.4 },
}

-- Iron Wall: a glassy barrier above the middle's hands for the ability's duration.
function VFXController.ability(entityId, ability)
	local def = Config.Abilities[ability or ""]
	local model = Util.modelOf(entityId)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not def or not hrp then
		return
	end
	if ability == "IronWall" then
		local w = walls[entityId]
		if not w then
			local part = Instance.new("Part")
			part.Name = "IronWall"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.ForceField
			part.Color = def.Color
			part.Size = Vector3.new(9, 7.5, 0.5)
			part.Parent = fxFolder
			w = { part = part }
			walls[entityId] = w
		end
		w.untilT = os.clock() + def.Duration
		w.side = State.sideOfEntity(entityId) or 1
		local top = hrp.Position + Vector3.new(0, 5, 0)
		ringFx(top, def.Color, 2, 12, 0.35, 7)
		shards(top, def.Color, 10, 40)
		VFXController.popup(top + Vector3.new(0, 2, 0), "Iron Wall!", def.Color, 1.2)
		if mods and mods.AudioController.hearsMatch() then
			mods.AudioController.play("Block", { volume = 0.7 })
		end
	elseif ability == "Turnabout" then
		-- armed: a swirl at the setter's feet (the aura scan keeps a glow on while it lasts)
		local pos = hrp.Position
		floorRing(pos, def.Color, 4.5, 0.45)
		ringFx(pos + Vector3.new(0, 1, 0), def.Color, 2, 9, 0.35, 6)
		VFXController.popup(pos + Vector3.new(0, 6, 0), "Turnabout!", def.Color, 1.1)
		if mods and mods.AudioController.hearsMatch() then
			mods.AudioController.play("Whoosh", { volume = 0.6, speed = 0.8 })
		end
	elseif ability == "RallyCry" then
		-- a golden shockwave from the middle, and a flare at every teammate's feet
		local pos = hrp.Position
		floorRing(pos, def.Color, 16, 0.7)
		ringFx(pos + Vector3.new(0, 3, 0), def.Color, 2, 18, 0.5, 9)
		starburst(pos + Vector3.new(0, 3, 0), def.Color, 10, 14, 0.35)
		VFXController.popup(pos + Vector3.new(0, 7, 0), "Rally Cry!", def.Color, 1.3)
		local team = State.teamOf(entityId)
		for _, e in ipairs(team and State.roster(team) or {}) do
			local r = Util.rootOf(e.id)
			if r and e.id ~= entityId then
				floorRing(r.Position, def.Color, 5, 0.5)
				burst(r.Position + Vector3.new(0, 1.5, 0), def.Color, 2.2, 0.3)
			end
		end
		if mods and mods.AudioController.hearsMatch() then
			mods.AudioController.play("RallyCry", { volume = 0.8 })
		end
	end
end

-- Counter Edge: when she digs their spike, swords burst out of her across the court and fly
-- back in (the owner: "swords fly out from her depending on the strength of the spike, then fly
-- back in"). strength 0..1 (the meter the dig earned): more swords, flying further. Each sword is
-- a blade and a crossguard from the pool, so a full burst is 20 swords, 40 short-lived parts.
local function counterBlades(model, color, strength)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	strength = math.clamp(strength or 0.5, 0, 1)
	local count = 8 + math.floor(12 * strength + 0.5)
	local from = hrp.Position + Vector3.new(0, 0.6, 0)
	for i = 1, count do
		-- spread around her in the plane the camera sees (along the court and up)
		local a = (i / count) * math.pi * 2 + math.random() * 0.3
		local dir = Vector3.new((math.random() - 0.5) * 0.2, math.sin(a), math.cos(a)).Unit
		local dist = 4 + (8 + math.random() * 8) * (0.3 + 0.7 * strength) + 6 * strength
		local blade = take(Enum.PartType.Block)
		local guard = take(Enum.PartType.Block)
		blade.Color, guard.Color = color, color
		blade.Size = Vector3.new(0.12, 0.3, 3.4)
		guard.Size = Vector3.new(0.12, 1.1, 0.2)
		blade.Transparency, guard.Transparency = 0.05, 0.05
		-- the blade's point leads; the guard sits near its back end
		local function place(c, d)
			local cf = CFrame.lookAt(c + d * 0.6, c + d * 2)
			return cf, cf * CFrame.new(0, 0, 1.2)
		end
		local b0, g0 = place(from, dir)
		blade.CFrame, guard.CFrame = b0, g0
		local b1, g1 = place(from + dir * dist, dir)
		local outInfo = TweenInfo.new(0.18 + 0.06 * strength, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local out = TweenService:Create(blade, outInfo, { CFrame = b1 })
		TweenService:Create(guard, outInfo, { CFrame = g1 }):Play()
		out.Completed:Connect(function()
			task.delay(0.22, function()
				-- back into wherever she is now
				local c = (hrp.Parent and hrp.Position or from) + Vector3.new(0, 0.6, 0)
				local b2, g2 = place(c, dir)
				local backInfo = TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				local back = TweenService:Create(blade, backInfo, { CFrame = b2, Transparency = 0.6 })
				TweenService:Create(guard, backInfo, { CFrame = g2, Transparency = 0.6 }):Play()
				back.Completed:Connect(function()
					release(blade)
					release(guard)
				end)
				back:Play()
			end)
		end)
		out:Play()
	end
end

-- Counter Edge: blades fly along her spike, more the fuller her meter.
local function bladeVolley(pos, dir, color, count)
	for _ = 1, count do
		local p = take(Enum.PartType.Block)
		p.Color = color
		local d = (dir + Vector3.new(0, (math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.5)).Unit
		p.Size = Vector3.new(0.1, 0.35, 2.4)
		p.CFrame = CFrame.lookAt(pos, pos + d)
		p.Transparency = 0.05
		local reach = 14 + math.random() * 10
		local tween = TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(pos + d * reach, pos + d * (reach + 1)),
			Transparency = 1,
		})
		tween.Completed:Connect(function()
			release(p)
		end)
		tween:Play()
	end
end

local function chainExplosion(pos, color)
	Fx.play("ChainExplosion", pos, { color = color })
end

local function updateAbilityFx(dt)
	local now = os.clock()
	for id, w in pairs(walls) do
		local hrp = Util.rootOf(id)
		if not hrp or now > w.untilT then
			w.part:Destroy()
			walls[id] = nil
		else
			local left = w.untilT - now
			w.part.Transparency = left < 0.4 and (1 - left / 0.4) or 0.15
			w.part.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 5.2, -w.side * 1.6))
		end
	end
	-- boost auras: Adrenaline (red), the Sunrise level (orange, hotter each level), the team's
	-- Rally Cry (gold), an armed Turnabout (mint) and a charged Counter meter (steel)
	if now < nextStatusScan then
		return
	end
	nextStatusScan = now + 0.3
	local clock = Util.now()
	local want = {}
	for _, team in ipairs(Config.TeamOrder) do
		local rally = State.rallyOn(team, clock)
		for _, e in ipairs(State.roster(team)) do
			local model = Util.modelOf(e.id)
			if model then
				local w = {}
				if model:GetAttribute("Adrenaline") then
					w.Adrenaline = 1
				end
				local sun = model:GetAttribute("SunLevel") or 0
				if sun > 0 then
					w.Sun = sun
				end
				if sun > (sunSeen[model] or 0) then
					local hrp = model:FindFirstChild("HumanoidRootPart")
					if hrp then
						local c = Config.Abilities.RisingSun.Color
						sunBeam(hrp.Position)
						burst(hrp.Position + Vector3.new(0, 1, 0), c, 3, 0.35)
						ringFx(hrp.Position + Vector3.new(0, 1, 0), c, 2, 10, 0.4, 7)
						VFXController.popup(hrp.Position + Vector3.new(0, 6, 0), "Sunrise Lv " .. sun .. "!", c, 1.1)
					end
				end
				sunSeen[model] = sun
				if rally then
					w.Rally = 1
				end
				if model:GetAttribute("Ability") == "Turnabout" and (model:GetAttribute("AbilityUntil") or -1) >= clock then
					w.Armed = 1
				end
				local edge = model:GetAttribute("Counter") or 0
				if edge > 0 then
					w.Edge = edge / 100
				end
				want[model] = w
			end
		end
	end
	for model, w in pairs(want) do
		local list = statusFx[model] or {}
		statusFx[model] = list
		for kind, level in pairs(w) do
			local st = STATUS[kind]
			local fx = list[kind]
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if not fx and hrp then
				local att = Instance.new("Attachment")
				att.Name = "Status" .. kind
				att.Parent = hrp
				local hl = nil
				if st.fill then
					hl = Instance.new("Highlight")
					hl.FillColor = st.fill
					hl.FillTransparency = 0.85
					hl.OutlineColor = st.edge
					hl.OutlineTransparency = 0.3
					hl.DepthMode = Enum.HighlightDepthMode.Occluded
					hl.Parent = model
				end
				fx = { att = att, aura = Fx.attach("StatusAura", att), hl = hl }
				list[kind] = fx
			end
			if fx then
				fx.aura.set(true, st.fire[2], st.rate * level / 40)
			end
		end
	end
	for model, list in pairs(statusFx) do
		local w = model.Parent and want[model] or {}
		for kind, fx in pairs(list) do
			if not w[kind] or not fx.att.Parent then
				fx.att:Destroy()
				if fx.hl then
					fx.hl:Destroy()
				end
				list[kind] = nil
			end
		end
		if next(list) == nil then
			statusFx[model] = nil
		end
	end
	for model in pairs(sunSeen) do
		if not want[model] then
			sunSeen[model] = nil
		end
	end
end

------------------------------------------------------------------------------------------
-- charge arcs (the owner's references: The Spike's curved gauges). Feral Leap: a violet crescent
-- on the side he faces as he charges and leaps, a thin light one outside it, flames at his feet.
-- Azure Dragon ("make ryuhyeon's charge the curved thing"): a white-blue one behind the charging
-- spiker. A ring's stroke clipped to one side; the charge fills it from the bottom up, and a full
-- one flashes and throbs.
------------------------------------------------------------------------------------------

local ARC_STUDS = 13 -- the billboard, across (studs)
local ARC_MAIN = 0.78 -- the main band's circle across, as a share of the billboard
local ARC_OUTER = 0.92 -- the thin outer band's
local ARC_CUT = 0.11 -- the bands show beyond this far from the centre, on the arc's side
local ARC_STYLE = {
	feral = { main = FERAL, light = FERAL_LIGHT, hot = FERAL_HOT, back = false, flames = true },
	azure = { main = Color3.fromRGB(225, 245, 255), light = AZURE, hot = WHITE, back = true, flames = false },
}
local NO_AURA = { set = function() end, destroy = function() end }

-- One band: a ring's stroke inside a clip that only shows the facing side of the circle.
local function arcBand(gui, size, color)
	local clip = Instance.new("Frame")
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Parent = gui
	local ring = Instance.new("Frame")
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Parent = clip
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	return { clip = clip, ring = ring, stroke = stroke, size = size }
end

-- Put a band on the side the player faces (dir +1: screen right, the camera looks along +x).
local function layoutBand(b, dir)
	local w = 0.5 - ARC_CUT
	local x0 = dir > 0 and 0.5 + ARC_CUT or 0
	b.clip.Position = UDim2.fromScale(x0, 0)
	b.clip.Size = UDim2.fromScale(w, 1)
	b.ring.Size = UDim2.fromScale(b.size / w, b.size)
	b.ring.Position = UDim2.fromScale((0.5 - x0) / w, 0.5)
end

local function fadeEnds(parent)
	local g = Instance.new("UIGradient")
	g.Rotation = -90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, 0),
		NumberSequenceKeypoint.new(0.78, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = parent
	return g
end

-- kind: "feral" (the default) or "azure" (ARC_STYLE)
function newArc(model, hrp, kind)
	kind = ARC_STYLE[kind or ""] and kind or "feral"
	local st = ARC_STYLE[kind]
	local att = Instance.new("Attachment")
	att.Name = "ChargeArc"
	att.Position = Vector3.new(0, 0.9, 0)
	att.Parent = hrp
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(ARC_STUDS, 0, ARC_STUDS, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = att
	gui.Parent = att
	local glow = Instance.new("ImageLabel")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Size = UDim2.fromScale(0.55, 0.9)
	glow.BackgroundTransparency = 1
	glow.Image = Assets.id(Assets.Fx.Glow) or ""
	glow.ImageColor3 = st.light
	glow.Parent = gui
	local track = arcBand(gui, ARC_MAIN, st.main)
	track.stroke.Transparency = 0.78
	local main = arcBand(gui, ARC_MAIN, st.main)
	local fill = Instance.new("UIGradient")
	fill.Rotation = -90 -- from the bottom up
	fill.Parent = main.stroke
	local outer = arcBand(gui, ARC_OUTER, st.light)
	fadeEnds(outer.stroke)
	return {
		kind = kind,
		style = st,
		att = att,
		gui = gui,
		glow = glow,
		track = track,
		main = main,
		fill = fill,
		outer = outer,
		aura = st.flames and Fx.attach("StatusAura", att) or NO_AURA,
		dir = 0,
		value = 0,
		shown = -1,
		full = false,
	}
end

function dropArc(model)
	local a = arcs[model]
	if not a then
		return
	end
	arcs[model] = nil
	a.aura.set(false)
	-- the flames already out finish their life, then everything goes
	TweenService:Create(a.gui, TweenInfo.new(0.18), { Size = UDim2.new(ARC_STUDS * 1.25, 0, ARC_STUDS * 1.25, 0) }):Play()
	for _, b in ipairs({ a.track, a.main, a.outer }) do
		TweenService:Create(b.stroke, TweenInfo.new(0.18), { Transparency = 1 }):Play()
	end
	TweenService:Create(a.glow, TweenInfo.new(0.18), { ImageTransparency = 1 }):Play()
	task.delay(0.7, function()
		a.aura.destroy()
		a.att:Destroy()
	end)
end

-- A remote charge (another player, or a bot's charge in the air) or a leap's fixed gauge.
-- how: "prowl" (grows over `time`), "leap" (holds `value`), "end".
local function remoteArc(model, how, value, time)
	if how == "end" then
		dropArc(model)
		return
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local a = arcs[model]
	if not a then
		a = newArc(model, hrp)
		arcs[model] = a
	end
	a.remote = true
	if how == "prowl" then
		a.t0, a.rate, a.fixed = os.clock(), 1 / math.max(time or 1, 0.05), nil
		a.untilT = os.clock() + 6
	else
		a.fixed = math.clamp(value or a.value, 0, 1)
		a.untilT = os.clock() + 3
	end
end

-- The leap: violet flames and a shock disc under his feet, bigger the fuller the charge.
local function leapBurst(model, gauge)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp or not near(hrp.Position) then
		return
	end
	local p = hrp.Position
	local foot = Vector3.new(p.X, 0.25, p.Z)
	floorRing(foot, FERAL, 4 + 6 * gauge)
	Fx.play("Fire", foot + Vector3.new(0, 1, 0), { color = FERAL, scale = 0.7 + 0.7 * gauge })
	if gauge >= Config.Abilities.Feral.FullAt then
		Fx.play("Ring", p + Vector3.new(0, 1, 0), { color = FERAL_HOT, scale = 1.1 })
	end
	if mods and mods.AudioController then
		mods.AudioController.play("FeralLeap", { pos = p, volume = 0.6 + 0.4 * gauge })
	end
end

local function updateArcs(dt)
	local now = os.clock()
	-- my own charge and leap come straight from ActionController
	local mine = player.Character
	local AC = mods and mods.ActionController
	if mine and AC and not (arcs[mine] and arcs[mine].kind == "azure") then
		local charging = AC.prowlCharge()
		local gauge = AC.leapGauge()
		local v = charging or (gauge > 0 and gauge) or nil
		local a = arcs[mine]
		if v and not a then
			local hrp = mine:FindFirstChild("HumanoidRootPart")
			if hrp then
				a = newArc(mine, hrp)
				arcs[mine] = a
			end
		elseif not v and a and not a.remote then
			dropArc(mine)
			a = nil
		end
		if a and v then
			if a.charging and not charging then
				leapBurst(mine, v) -- let go: the leap
			end
			a.charging = charging ~= nil
			a.value = v
		end
	end
	for model, a in pairs(arcs) do
		local hrp = model.Parent and model:FindFirstChild("HumanoidRootPart")
		if not hrp or (a.remote and now > (a.untilT or 0)) then
			dropArc(model)
		else
			if a.remote then
				a.value = a.fixed or math.min(1, (now - a.t0) * a.rate)
			end
			local v = a.value
			local st = a.style
			-- Feral Leap's on the side he faces, Azure's behind
			local dir = hrp.CFrame.LookVector.Z >= 0 and 1 or -1
			if st.back then
				dir = -dir
			end
			if dir ~= a.dir then
				a.dir = dir
				for _, b in ipairs({ a.track, a.main, a.outer }) do
					layoutBand(b, dir)
				end
				a.glow.Position = UDim2.fromScale(0.5 + dir * 0.36, 0.5)
			end
			-- strokes are in pixels: keep them a share of the arc on any screen
			local px = a.gui.AbsoluteSize.X
			a.track.stroke.Thickness = px * 0.07
			a.main.stroke.Thickness = px * 0.07
			a.outer.stroke.Thickness = math.max(1, px * 0.016)
			local full = v >= (a.kind == "azure" and 0.995 or Config.Abilities.Feral.FullAt)
			if math.abs(v - a.shown) > 0.004 then
				a.shown = v
				if v >= 0.995 then
					a.fill.Transparency = NumberSequence.new(0)
				elseif v <= 0.005 then
					a.fill.Transparency = NumberSequence.new(1)
				else
					a.fill.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(v, 0),
						NumberSequenceKeypoint.new(math.min(v + 0.02, 0.999), 1),
						NumberSequenceKeypoint.new(1, 1),
					})
				end
			end
			if full and not a.full then
				-- full: a flash of light along the arc and a ring off him
				a.full = true
				Fx.play("Ring", hrp.Position + Vector3.new(0, 1, 0), { color = st.hot, scale = 0.8 })
				if model == mine and a.kind == "feral" and mods and mods.AudioController then
					mods.AudioController.play("FeralFull", { volume = 0.8 })
				end
			elseif not full then
				a.full = false
			end
			local throb = full and (0.5 + 0.5 * math.sin(now * 14)) or 0
			local main = full and st.main:Lerp(st.light, 0.35 + 0.4 * throb) or st.main
			if a.over then
				main = HOT -- Azure held too long: it'll fly out
			end
			a.main.stroke.Color = main
			a.outer.stroke.Transparency = full and 0.05 or 0.45
			a.glow.ImageTransparency = 0.85 - 0.45 * v - 0.2 * throb
			-- the flames at his feet burn harder as it fills (repainted only when that changes)
			local step = full and 11 or math.floor(v * 10)
			if step ~= a.auraStep then
				a.auraStep = step
				a.aura.set(true, full and st.hot or st.main, 0.3 + 0.09 * step)
			end
		end
	end
end

-- The charge showing on a model right now (a Feral Leap arc's, or an Azure Dragon's energy), for
-- the HUD's badges; nil when there's none.
function VFXController.chargeOf(model)
	local a = arcs[model]
	if a then
		return a.value
	end
	local fx = auras[model]
	return fx and math.min(fx.energy or 0, 1) or nil
end

-- Skyward: her highest spike this set as a marker left where she met it, a pink line
-- at that height with the metres on it (the owner: "make the top spike indicator stay there").
local peakMarks = {} -- model -> { anchor, gui, text }
local PEAK_BAR = 9 -- studs: the bar's length, from just off the net out over her court
local function updatePeaks()
	local seen = {}
	if State.isPlaying or State.match.inMatch then
		for _, team in ipairs(Config.TeamOrder) do
			for _, e in ipairs(State.roster(team)) do
				local model = Util.modelOf(e.id)
				-- (Lift is only on a Skyward character in this match)
				local peak = model and model:GetAttribute("Lift") ~= nil and model:GetAttribute("PeakM")
				local py, pz = model and model:GetAttribute("PeakY"), model and model:GetAttribute("PeakZ")
				if peak and py and pz then
					seen[model] = true
					local m = peakMarks[model]
					if not m then
						local anchor = take(Enum.PartType.Block)
						anchor.Size = Vector3.new(0.2, 0.2, 0.2)
						anchor.Transparency = 1
						local gui = Instance.new("BillboardGui")
						gui.Size = UDim2.new(PEAK_BAR, 0, 2.2, 0) -- in studs: a long bar beside the net
						gui.AlwaysOnTop = true
						gui.LightInfluence = 0
						gui.Adornee = anchor
						gui.Parent = anchor
						local line = Instance.new("Frame")
						line.AnchorPoint = Vector2.new(0.5, 0.5)
						line.Position = UDim2.fromScale(0.5, 1)
						line.Size = UDim2.new(1, 0, 0, 4)
						line.BorderSizePixel = 0
						line.BackgroundColor3 = Config.Abilities.Skyward.Color
						line.Parent = gui
						local text = Instance.new("TextLabel")
						text.BackgroundTransparency = 1
						text.Size = UDim2.new(1, 0, 1, -4)
						text.Font = Enum.Font.GothamBlack
						text.TextSize = 18
						text.TextColor3 = Config.Abilities.Skyward.Color
						text.TextStrokeTransparency = 0.3
						text.Parent = gui
						m = { anchor = anchor, gui = gui, text = text }
						peakMarks[model] = m
					end
					-- at the height of her highest spike this set (the owner: "literally where her highest
					-- spike was"), the bar running from the net out over her side ("extend the bar and make
					-- it just stay right next to the net")
					m.text.Text = string.format("%.2f m", peak)
					local sideOf = State.sideOfEntity(e.id) or (pz >= 0 and 1 or -1)
					m.anchor.CFrame = CFrame.new(0, py + 1.1, sideOf * (PEAK_BAR / 2 + 0.6))
				end
			end
		end
	end
	for model, m in pairs(peakMarks) do
		if not seen[model] then
			m.gui:Destroy()
			release(m.anchor)
			peakMarks[model] = nil
		end
	end
end

local function updateAuras(dt)
	updateArcs(dt)
	updateAbilityFx(dt)
	updatePeaks()
	for model, fx in pairs(auras) do
		if not model.Parent then
			fx.hand.att:Destroy()
			auras[model] = nil
		else
			fx.hand.ring.Rotation = (fx.hand.ring.Rotation + dt * (240 + 360 * (fx.energy or 0))) % 360
			if fx.remote then
				applyEnergy(fx, math.min(1, (os.clock() - fx.t0) / Config.Abilities.Azure.ChargeTime))
			end
		end
	end
end

-- Neon streaks across the whole screen at the height of the hit.
function VFXController.neonStreaks(pos, color)
	if not State.settings.dramatic then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local sp = cam:WorldToViewportPoint(pos)
	for i, f in ipairs(streaks) do
		local offset = (i - 2.5) * (10 + math.random() * 14)
		f.Position = UDim2.new(0.5, 0, 0, sp.Y + offset)
		f.Size = UDim2.new(1.2, 0, 0, (i == 2 or i == 3) and 16 or 8)
		f.ImageColor3 = (i == 2 or i == 3) and color or WHITE
		f.ImageTransparency = 0
		f.Rotation = (math.random() - 0.5) * 2
		TweenService:Create(f, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			ImageTransparency = 1,
			Size = UDim2.new(1.2, 0, 0, 3),
		}):Play()
	end
end

-- A gold shield over a receiver's head: the guard held on a perfect receive.
function VFXController.shield(entityId, color)
	local model = Util.modelOf(entityId)
	local head = model and (model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart"))
	if not head then
		return
	end
	color = color or Color3.fromRGB(255, 205, 60)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(46, 54)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = head
	gui.Parent = head
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = root
	-- the shield icon with a glint across it
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Image = Assets.image("IconDefense") or ""
	icon.ImageColor3 = color
	icon.Parent = root
	local glint = Instance.new("ImageLabel")
	glint.BackgroundTransparency = 1
	glint.AnchorPoint = Vector2.new(0.5, 0.5)
	glint.Position = UDim2.fromScale(0.68, 0.28)
	glint.Size = UDim2.fromScale(0.8, 0.8)
	glint.Image = Assets.id(Assets.Fx.Glint) or ""
	glint.ZIndex = 2
	glint.Parent = root
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0) }):Play()
	task.delay(0.6, function()
		for _, f in ipairs({ icon, glint }) do
			TweenService:Create(f, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
		end
	end)
	task.delay(0.95, function()
		gui:Destroy()
	end)
end

-- Lightning crackling along the whole flight of a Thunder spike.
local function thunderPath(path)
	for k = 1, 7 do
		task.delay(0.03 + k * 0.045, function()
			local p = BallPhysics.positionAt(path, Util.now())
			local v = BallPhysics.velocityAt(path, Util.now())
			local back = v.Magnitude > 0 and -v.Unit or Vector3.new(0, 0, 1)
			for _ = 1, 2 do
				local d = (back + Vector3.new(0, (math.random() - 0.5) * 1.6, (math.random() - 0.5) * 1.6)).Unit
				bolt(p, d, 4 + math.random() * 5, THUNDER)
			end
		end)
	end
end

-- Sonic-boom rings chasing a hard spike a moment after contact.
local function boomRings(path, color, count)
	for k = 1, count do
		task.delay(0.04 + k * 0.07, function()
			local now = Util.now()
			if now >= path.landing.t then
				return
			end
			sonicRing(BallPhysics.positionAt(path, now), BallPhysics.velocityAt(path, now), color, 5 + k, 0.3)
		end)
	end
end

-- Zero Point: a huge white beam along the whole line of the flight (it barely curves), out
-- behind the hitter too (the owner: "much more exaggerated and goes out behind him too"), in
-- three layers that thin away, with rings standing across it, biggest at the hand.
local ZERO_GLOW = Color3.fromRGB(200, 225, 255)
local ZERO_BEHIND = 90 -- studs of beam behind the hitter
local function zeroBeam(path)
	local from = path.segs[1].p
	local to = path.landing.pos
	local d = to - from
	if d.Magnitude < 1 then
		return
	end
	local dir = d.Unit
	local back = from - dir * ZERO_BEHIND
	local len = (to - back).Magnitude
	local cf = CFrame.lookAt(back:Lerp(to, 0.5), to)
	for i, layer in ipairs({ { 2.6, 0, WHITE, 0.8 }, { 7, 0.45, ZERO_GLOW, 1.0 }, { 16, 0.82, ZERO_GLOW, 1.2 } }) do
		local w, a, col, life = layer[1], layer[2], layer[3], layer[4]
		local p = take(Enum.PartType.Block)
		p.Color = col
		p.Size = Vector3.new(w * 0.3, w * 0.3, len)
		p.CFrame = cf
		p.Transparency = a
		-- it bursts open to full width, then thins away
		TweenService:Create(p, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(w, w, len) }):Play()
		task.delay(0.07, function()
			TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.1, 0.1, len), Transparency = 1 }):Play()
		end)
		task.delay(life + 0.1, release, p)
		if i == 1 then
			p.Transparency = 0
		end
	end
	local v = path.segs[1].v
	-- rings across the line, from behind the hitter out to the landing
	for k = 1, 8 do
		local f = -0.35 + (k - 1) * 0.16
		local at = f < 0 and from + dir * (ZERO_BEHIND * f / 0.35) or from + d * f
		task.delay(math.abs(f) * 0.12, sonicRing, at, v, k % 2 == 0 and WHITE or ZERO_GLOW, k == 3 and 22 or 16 - math.abs(k - 3) * 1.2, 0.6)
	end
end

------------------------------------------------------------------------------------------
-- reactions to gameplay
------------------------------------------------------------------------------------------

local function onHit(snap)
	local meta = snap.meta
	if not meta or not snap.path then
		return
	end
	local seg = snap.path.segs[1]
	local pos = seg.p
	local dirZ = seg.v.Z >= 0 and 1 or -1
	local tc = teamColor(meta.team)
	local ht = meta.hitType
	local kmh = meta.kmh or 0
	local mine = meta.id == State.myId
	local close = mine or near(pos)
	local shaker = mods.CameraController
	local model = meta.id and Util.modelOf(meta.id)
	if model then
		setAura(model, false)
		if meta.gauge and arcs[model] and arcs[model].remote then
			dropArc(model) -- a Feral Leap's arc goes with its spike (mine goes when the gauge is spent)
		end
	end

	local chain = Config.Abilities.ChainReaction.Color
	if meta.reaction then
		chainExplosion(pos, chain)
		VFXController.popup(pos + Vector3.new(0, 1.5, 0), "Chain Reaction!", chain, 1.2)
		if close then
			shaker.shake(0.6)
			VFXController.flash(0.25, 0.2)
		end
	end
	if meta.secondSwing then
		VFXController.popup(pos + Vector3.new(0, 3.4, 0), "Double Swing!", Config.Abilities.Thunder.Color, 1.1)
	end
	if meta.adrenaline then
		VFXController.popup(pos + Vector3.new(0, 3, 0), "Adrenaline!", Config.Abilities.Adrenaline.Color, 0.8)
	end
	if ht == "Set" and meta.charged then
		emit("Sparks", pos, 24, chain)
		ringFx(pos, chain, 1, 6, 0.3, 5)
	end
	if ht == "Set" and meta.vectorSet then
		ringFx(pos, VECTOR, 1, 6, 0.35, 5)
		emit("Sparks", pos, 14, VECTOR)
	end
	if meta.turnabout then
		local tcol = Config.Abilities.Turnabout.Color
		ringFx(pos, tcol, 1.5, 10, 0.35, 6)
		starburst(pos, tcol, 8, 12, 0.3)
		VFXController.popup(pos + Vector3.new(0, 2, 0), "Turnabout!", tcol, 1.1)
	end
	if meta.counterGain then
		counterBlades(model, COUNTER, math.clamp((meta.counterGain or 50) / 100, 0, 1)) -- more and further the harder their spike
		VFXController.popup(pos + Vector3.new(0, 2.2, 0), "Counter +" .. math.floor(meta.counterGain + 0.5), COUNTER, 0.85)
		if close and mods.AudioController then
			-- the parry as the blades burst out, then the sword woosh as they fly back into her (the
			-- owner: "play parry first then the sword woosh into ines"; counterBlades: out, a hold of
			-- 0.22 s, back)
			local s = math.clamp((meta.counterGain or 50) / 100, 0, 1)
			mods.AudioController.play("CounterParry", { volume = 0.8, pos = pos })
			task.delay(0.18 + 0.06 * s + 0.22, mods.AudioController.play, "CounterReturn", { volume = 0.7, pos = pos })
		end
	end

	if ht == "Spike" or ht == "JumpServe" then
		local heavy = kmh >= 120
		local vdir = seg.v.Magnitude > 0 and seg.v.Unit or Vector3.new(0, -1, dirZ)
		if meta.vector then
			-- Vector Set: the boost the spike's angle earned
			local boost = meta.vectorBoost or 0
			ringFx(pos, VECTOR, 1.5, 7 + 20 * boost, 0.35, 6)
			VFXController.popup(pos + Vector3.new(0, 2.6, 0), string.format("+%.1f%%", boost * 100), VECTOR, 0.9 + 2 * boost)
		end
		if meta.plunge then
			-- Plunge Spin: the ball leaves the hand through a big ring of wind (across its line);
			-- where it turns down into the plunge, a second ring, a burst and a boom
			local col = Config.Abilities.Plunge.Color
			sonicRing(pos, seg.v, WHITE, 11, 0.45)
			ringFx(pos, col, 1, 8, 0.3)
			local path = snap.path
			local turn = path.segs[2]
			if turn then
				task.delay(math.max(0, turn.t0 - Util.now()), function()
					if Util.now() < path.landing.t + 0.05 then
						sonicRing(turn.p, turn.v, WHITE, 14, 0.5)
						ringFx(turn.p, col, 1, 12, 0.35)
						Fx.play("Burst", turn.p, { color = col, scale = 1.1 })
						if mods.AudioController then
							mods.AudioController.play("Boom", { pos = turn.p, volume = 1, minGap = 0.05 })
						end
						if close then
							shaker.shake(0.6)
							shaker.kick(-7)
						end
					end
				end)
			end
			if close then
				VFXController.popup(pos + Vector3.new(0, 2.6, 0), "Plunge Spin!", col, 1.1)
				shaker.kick(-5)
			end
		end
		if meta.counterRelease then
			-- Counter Edge released: blades fly with the ball, more the fuller the meter was
			local c = meta.counterRelease
			bladeVolley(pos, vdir, COUNTER, 3 + math.floor(c / 12))
			if c >= 50 then
				VFXController.popup(pos + Vector3.new(0, 4.2, 0), string.format("Counter Edge +%d%%", math.floor(Config.Abilities.Counter.ReleaseBoost * c + 0.5)), COUNTER, 0.8 + 0.4 * c / 100)
			end
			if close and mods.AudioController then
				mods.AudioController.play("Blades", { volume = 0.5 + 0.4 * c / 100, speed = 1.2 })
			end
		end
		-- when the ball leaves the hand (after its hold: a freeze frame's length)
		local fires = math.max(0, seg.t0 + (seg.hold or 0) - Util.now())
		if meta.zero then
			-- Zero Point: the freeze frame while it holds, then the beam, the rings and a white burst;
			-- nothing else on top of it
			-- first the court goes dark around him, lit white with the ball glowing on his hand, then
			-- the silhouette cut-in
			local darkFor = math.min(Config.Abilities.ZeroPoint.FreezeDark, fires)
			if VFXController.darkFrame(meta.id, pos, darkFor, WHITE) then
				task.delay(darkFor, function()
					VFXController.freezeFrame(meta.id, pos, fires - darkFor)
				end)
			else
				VFXController.freezeFrame(meta.id, pos, fires)
			end
			task.delay(fires, function()
				zeroBeam(snap.path)
				Fx.play("PerfectImpact", pos, { color = WHITE, scale = 1.6 })
				Fx.play("Burst", pos, { color = ZERO_GLOW, scale = 1.5 })
				VFXController.flash(0.5, 0.3)
				if close then
					VFXController.speedLines(0.7, WHITE, dirZ)
					shaker.shake(1)
					shaker.kick(-10)
				end
			end)
			return
		end
		if meta.firstStrike then
			-- Dante's First Strike: a shorter freeze frame, in purple, then his usual burst (below) as it
			-- fires
			VFXController.freezeFrame(meta.id, pos, fires, FERAL)
		end
		if meta.talon then
			-- Talon Drop: a pink ring across the drop and a star where she hit it
			local col = Config.Abilities.Skyward.Color
			sonicRing(pos, seg.v, col, 10, 0.4)
			starburst(pos, col, 10)
			if close then
				VFXController.popup(pos + Vector3.new(0, 2.6, 0), "Talon Drop!", col, 1.1)
				shaker.kick(-6)
			end
		end
		-- the S+ signature hits (a Thunder spike, a full Azure, a full Feral Leap): the court goes
		-- dark around the hitter, lit white with the ball glowing on the hand, while it holds; the
		-- rest of the hit plays as it fires (the owner's reference)
		local dark = false -- (the dark frame is Zero Point's alone now: the owner, "just the white spiker guy")
		task.delay(dark and fires or 0, function()
			if heavy or meta.thunder or meta.energy or meta.gauge then
				local ring = meta.thunder and THUNDER or (meta.energy and AZURE) or (meta.gauge and FERAL) or WHITE
				boomRings(snap.path, ring, (meta.thunder or meta.fullLeap) and 3 or 2)
				if close then
					VFXController.neonStreaks(pos, meta.thunder and THUNDER or (meta.energy and AZURE) or (meta.gauge and FERAL_HOT) or HOT)
				end
			end
			if meta.thunder then
				Fx.play("ThunderImpact", pos)
				for _ = 1, 3 do
					local d = (vdir + Vector3.new(0, (math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.2)).Unit
					bolt(pos, d, 7 + math.random() * 5, THUNDER)
				end
				thunderPath(snap.path)
				if close then
					if not dark then
						VFXController.impactFrame(meta.id, THUNDER)
					end
					VFXController.speedLines(0.5, Color3.fromRGB(255, 244, 180), dirZ)
					shaker.shake(0.75)
					shaker.kick(-8)
				end
			elseif meta.energy then
				local e = math.min(meta.energy, 1)
				Fx.play("AzureImpact", pos, { scale = 0.7 + 0.4 * e })
				if meta.pierce then
					VFXController.popup(pos, "Pierce!", AZURE, 1.1)
				end
				if meta.overcharge then
					VFXController.popup(pos, "Overcharged!", HOT, 0.9)
				end
				if close and e >= 0.9 then
					if not dark then
						VFXController.impactFrame(meta.id, Color3.fromRGB(40, 120, 255))
					end
					shaker.shake(0.7)
					shaker.kick(-7)
				elseif close then
					shaker.shake(0.4)
				end
				if close then
					VFXController.speedLines(0.35 + 0.2 * e, Color3.fromRGB(190, 240, 255), dirZ)
				end
			elseif meta.gauge then
				-- Feral Leap: a magenta burst that grows with the charge; a full one freezes the frame,
				-- and his first full one of the match says so
				local g = meta.gauge
				-- (a First Strike's freeze frame holds it all back until the ball fires)
				task.delay(meta.firstStrike and fires or 0, function()
					Fx.play("PerfectImpact", pos, { color = FERAL_HOT, scale = 0.8 + 0.5 * g })
					if meta.firstStrike then
						Fx.play("Burst", pos, { color = FERAL, scale = 1.3 })
						VFXController.popup(pos + Vector3.new(0, 2.6, 0), "First Strike!", FERAL_HOT, 1.4)
					end
					if close and (meta.fullLeap or g >= 0.9) then
						if not meta.firstStrike and not dark then
							VFXController.impactFrame(meta.id, FERAL)
						end
						shaker.shake(meta.firstStrike and 0.9 or 0.7)
						shaker.kick(meta.firstStrike and -9 or -7)
						if meta.firstStrike then
							VFXController.flash(0.35, 0.25)
						end
					elseif close then
						shaker.shake(0.35 + 0.2 * g)
					end
					if close then
						VFXController.speedLines(0.3 + 0.25 * g, FERAL_LIGHT, dirZ)
					end
				end)
			else
				-- the attacker's spike colour (a V Points unlock) replaces the default hot pink
				local tint = Spins.tint(Spins.equipped(model, "Color"))
				local accent = tint or HOT
				Fx.play(heavy and "PerfectImpact" or "SpikeImpact", pos, { color = tint or (heavy and HOT or nil) })
				if close then
					if heavy and meta.grade == "PERFECT" and kmh >= 132 then
						VFXController.impactFrame(meta.id, accent)
					end
					if heavy then
						VFXController.speedLines(0.35, WHITE, dirZ)
						shaker.kick(-6)
					end
					shaker.shake(heavy and 0.55 or 0.25)
				end
			end
		end)
		return
	end

	if ht == "Block" then
		local outcome = meta.outcome
		if outcome == "Break" then
			-- a Feral Leap spike smashed through the hands: shards off the block, on it goes
			Fx.play("BlockImpact", pos, { color = FERAL, scale = 1.3 })
			shards(pos, FERAL_LIGHT, 14, 50)
			VFXController.popup(pos + Vector3.new(0, 1.8, 0), "Break Through!", FERAL_HOT, 1.3)
			if close then
				shaker.shake(0.7)
				shaker.kick(-6)
				VFXController.flash(0.25, 0.2)
			end
			return
		end
		if meta.ironWall then
			Fx.play("BlockImpact", pos, { color = Config.Abilities.IronWall.Color, scale = 1.35 })
		end
		if outcome == "Stuff" then
			Fx.play("BlockImpact", pos, { color = tc })
			VFXController.popup(pos, meta.perfectBlock and "Perfect Block!" or "Stuff!", meta.perfectBlock and Config.Abilities.IronWall.Color or tc, meta.perfectBlock and 1.5 or 1.2)
			if close then
				VFXController.impactFrame(meta.id, tc)
				shaker.shake(0.5)
				shaker.kick(-5)
			end
		else
			Fx.play("ReceiveImpact", pos, { color = tc })
			emit("Sparks", pos, 8, tc)
			if outcome == "Soft" then
				VFXController.popup(pos, "Soft block", UI.Chalk, 0.7)
			end
		end
		return
	end

	if ht == "Bump" or ht == "Set" or ht == "Free" or ht == "Feint" or ht == "Overhand" or ht == "Underhand" then
		Fx.play("ReceiveImpact", pos, { color = meta.perfect and UI.Spark or nil })
		if meta.fail or meta.breaks then
			shards(pos, Color3.fromRGB(200, 230, 255), 12, 40)
			VFXController.popup(pos, "Broken", HOT, 1)
			return
		end
		local hrp = model and model:FindFirstChild("HumanoidRootPart")
		if hrp and (ht == "Bump" or ht == "Free") then
			floorRing(Vector3.new(hrp.Position.X, 0.2, hrp.Position.Z), WHITE, 3.2, 0.35)
		end
		if meta.perfect then
			VFXController.shield(meta.id)
		end
		-- what the ball cost the team's guard
		if meta.drain and meta.drain >= 5 then
			VFXController.popup(pos - Vector3.new(0, 1.6, 0), "Guard -" .. math.floor(meta.drain + 0.5), HOT, 0.6)
			if meta.knock and meta.knock > 0.5 then
				shards(pos, Color3.fromRGB(210, 235, 255), 6 + math.floor(8 * meta.knock), 35)
			end
		end
		if meta.free then
			VFXController.popup(pos, "Free ball!", UI.Chalk, 1)
		elseif meta.score and ht == "Bump" then
			local grade = meta.grade or "GOOD"
			VFXController.popup(pos, grade .. " " .. tostring(meta.score), GRADE_COLOR[grade] or UI.Chalk, 0.9)
		elseif ht == "Set" and meta.grade == "PERFECT" then
			VFXController.popup(pos, "Nice set", UI.Mint, 0.8)
		end
		if meta.slide then
			emit("Dust", Vector3.new(pos.X, 0.4, pos.Z), 14)
		end
		if mine then
			shaker.shake(meta.drain and math.clamp(meta.drain / 40, 0.05, 0.3) or 0.05)
		end
	end
end

------------------------------------------------------------------------------------------
-- score effects (V Points unlocks): where an attack lands for a point
------------------------------------------------------------------------------------------

-- an effect's sound at `pos` (Assets.Sounds[key]), faded out after `fadeAt` seconds if given
local function sfx(key, pos, fadeAt)
	local A = mods and mods.AudioController
	local sound = A and A.play(key, { pos = pos, minGap = 0.01 })
	if sound and fadeAt then
		task.delay(fadeAt, function()
			if sound.Parent then
				TweenService:Create(sound, TweenInfo.new(0.5), { Volume = 0 }):Play()
			end
		end)
	end
	return sound
end

-- The meteor: a burning rock drops out of the sky onto the spot, then the crater (k: bigger).
local function meteorStrike(pos, dirZ, tint, k)
	k = k or 1
	local rock = take(Enum.PartType.Ball)
	rock.Material = Enum.Material.Basalt
	rock.Color = Color3.fromRGB(70, 52, 44)
	rock.Size = Vector3.new(3.2, 3.2, 3.2) * k
	rock.Transparency = 0
	local from = pos + Vector3.new(-4, 70, -dirZ * 38)
	rock.CFrame = CFrame.new(from)
	local att = Instance.new("Attachment")
	att.Parent = rock
	local flames = Fx.attach("MeteorTrail", att)
	flames.set(true, tint)
	sfx("MeteorWhoosh", pos)
	local t0 = os.clock()
	local fall = 0.34
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / fall, 0, 1)
		rock.CFrame = CFrame.new(from:Lerp(pos + Vector3.new(0, 1, 0), a * a))
		if a < 1 then
			return
		end
		conn:Disconnect()
		flames.set(false)
		rock.Transparency = 1
		task.delay(0.5, function()
			flames.destroy()
			att:Destroy()
			rock.Material = Enum.Material.Neon
			release(rock)
		end)
		Fx.play("ScoreMeteor", pos, { color = tint, scale = k })
		if near(pos) then
			mods.CameraController.shake(0.8)
			mods.CameraController.kick(-6)
			VFXController.flash(0.25, 0.2)
		end
	end)
end

-- The thunderbolt: a jagged bolt of hand-drawn segments out of the sky, then the ground
-- crackles.
local function thunderbolt(pos, tint, k)
	k = k or 1
	local color = tint or THUNDER
	local top = pos + Vector3.new(-1, 64, 0)
	local prev = top
	local segs = 7
	for i = 1, segs do
		local nextP = i == segs and pos or top:Lerp(pos, i / segs) + Vector3.new(0, 0, (math.random() - 0.5) * 6 * k)
		bolt(prev, (nextP - prev).Unit, (nextP - prev).Magnitude, color)
		prev = nextP
	end
	Fx.play("ScoreThunderbolt", pos, { color = color, scale = k })
	if mods.AudioController then
		mods.AudioController.play("ScoreThunder", { pos = pos })
	end
	if near(pos) then
		VFXController.flash(0.4, 0.25)
		mods.CameraController.shake(0.6)
	end
end

-- Five more score effects (the owner, with Volleyball Legends' as the idea: "a tornado...", "an
-- explosion displaying stats, a black hole... a tsunami that covers the map, or like rocket league
-- where the explosion alters the map for a bit"; then "use blender and figma to make these player
-- explosions. i want them premium", "some explosions should be bigger than others... like court
-- size" and "make them last a longer so that players can really see it"). Each takes the spot, the
-- tint, the attack's direction along z and a scale (Config.Match.ScoreFx.Scale by rarity: the
-- Legendary and Mythic ones fill the court).
--
-- Their meshes were modelled in Blender (assets/fx/ScoreFxMeshes.fbx: the funnel, the curling wave,
-- the gravity well, the crater, rocks, a shard and a dome) and imported into
-- ReplicatedStorage.ToolboxAssets.ScoreFx; their textures are drawn by
-- tools/generate_fx_textures.py, and the stat card was drawn in Figma. Until the meshes are
-- imported, each effect leaves that layer out (or uses plain parts).

local SCORE_FX = Config.Match.ScoreFx

-- a fresh copy of one of the Blender meshes, or nil. They glow in ForceField (a lit rim) or faint
-- Neon; our white textures go on beams and decals instead, which take the tint (a texture on a
-- MeshPart would paint over its colour).
local function fxMesh(name)
	local box = ReplicatedStorage:FindFirstChild("ToolboxAssets")
	local set = box and box:FindFirstChild("ScoreFx")
	local src = set and set:FindFirstChild(name, true)
	if not (src and src:IsA("MeshPart")) then
		return nil
	end
	local m = src:Clone()
	m.Anchored = true
	m.CanCollide = false
	m.CanQuery = false
	m.CanTouch = false
	m.CastShadow = false
	m.Material = Enum.Material.ForceField
	m.TextureID = ""
	m.Parent = fxFolder
	return m
end

-- an invisible holder for attachments and emitters, destroyed with the effect
local function holderPart(pos)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = fxFolder
	return p
end

-- a scrolling band of wind (Assets.Fx.Wind) between two attachments on `holder`
local function windBeam(holder, color, w0, w1, speed)
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Parent = holder
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Texture = Assets.id(Assets.Fx.Wind) or ""
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureSpeed = speed or 1.5
	b.LightEmission = 1
	b.LightInfluence = 0
	b.FaceCamera = true
	b.Segments = 16
	b.Width0 = w0
	b.Width1 = w1
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new(0.1)
	b.Parent = holder
	return { a0 = a0, a1 = a1, beam = b }
end

-- a glowing ring (Assets.Fx.Shock) laid on the floor, opening out to `radius` and fading over `dur`
-- `texture` (an Assets.Fx key) shown glowing on `face` of part `p`, tinted `color`. A SurfaceGui,
-- not a Decal: in Studio our uploads drew nothing as Decals (as ImageLabels they do), and a
-- SurfaceGui shows on an invisible part and can glow.
local function surfaceImage(p, face, texture, color, glow)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.LightInfluence = 0
	g.Brightness = glow or 2
	g.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	g.CanvasSize = Vector2.new(256, 256)
	g.Parent = p
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = Assets.id(Assets.Fx[texture]) or ""
	img.ImageColor3 = color
	img.Parent = g
	return img
end

local function shockDisc(pos, color, radius, dur)
	local p = holderPart(pos + Vector3.new(0, 0.15, 0))
	p.Size = Vector3.new(1, 0.05, 1)
	local img = surfaceImage(p, Enum.NormalId.Top, "Shock", color)
	local info = TweenInfo.new(dur, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(p, info, { Size = Vector3.new(radius * 2, 0.05, radius * 2) }):Play()
	TweenService:Create(img, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1 }):Play()
	task.delay(dur, p.Destroy, p)
end

-- a flat disc showing `texture` (an Assets.Fx key) tinted `color` on both faces
local function decalDisc(texture, color)
	local p = holderPart(Vector3.new(0, -500, 0))
	p.Size = Vector3.new(1, 0.05, 1)
	surfaceImage(p, Enum.NormalId.Top, texture, color)
	surfaceImage(p, Enum.NormalId.Bottom, texture, color)
	return p
end

local function discAlpha(p, a)
	for _, d in ipairs(p:GetDescendants()) do
		if d:IsA("ImageLabel") then
			d.ImageTransparency = a
		end
	end
end

-- a lens flare (Assets.Fx.Flare) that blooms open and fades
local function flare(pos, color, size, dur)
	local gui, anchor = billboard(pos, size)
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(0.2, 0.2)
	img.Image = Assets.id(Assets.Fx.Flare) or ""
	img.ImageColor3 = color
	img.Parent = gui
	TweenService:Create(img, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
	TweenService:Create(img, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1, Rotation = 25 }):Play()
	task.delay(dur, function()
		gui:Destroy()
		release(anchor)
	end)
end

-- a grid of spray (Assets.Fx.Foam, 4x4) blown out of a box part
local function foamEmitter(parent, color, size)
	local e = Instance.new("ParticleEmitter")
	e.Texture = Assets.id(Assets.Fx.Foam) or ""
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.Color = ColorSequence.new(WHITE, color)
	e.LightEmission = 0.4
	e.LightInfluence = 0
	e.Lifetime = NumberRange.new(0.9, 1.4)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, size * 1.4) })
	e.Speed = NumberRange.new(8, 22)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Drag = 2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Parent = parent
	return e
end

-- a moment of tinted, contrasty colour over the whole screen (the big ones only)
local function grade(tint, saturation, dur)
	local Lighting = game:GetService("Lighting")
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = tint
	cc.Saturation = saturation
	cc.Contrast = 0.12
	cc.Brightness = 0.06 -- the arenas are dark already; the tint alone would sink them
	cc.Parent = Lighting
	task.delay(dur * 0.6, function()
		local tw = TweenService:Create(cc, TweenInfo.new(dur * 0.4), { TintColor = WHITE, Saturation = 0, Contrast = 0, Brightness = 0 })
		tw.Completed:Connect(function()
			cc:Destroy()
		end)
		tw:Play()
	end)
end

-- Speed Burst (Rare): the spike's speed slams onto the Figma stat card over a flare and a star, the
-- card skidding in from the side with its speed lines, holding, then punching out.
local function speedBurst(pos, tint, k, reason)
	local meta = mods.BallRenderer and mods.BallRenderer.getMeta()
	local kmh = math.floor(((meta and meta.kmh) or 0) + 0.5)
	local color = tint or Color3.fromRGB(255, 205, 60)
	starburst(pos + Vector3.new(0, 1, 0), WHITE, 22 * k)
	flare(pos + Vector3.new(0, 3 * k, 0), color, 30 * k, 1.2)
	shockDisc(pos, color, 16 * k, 1.1)
	Fx.play("Glints", pos + Vector3.new(0, 3, 0), { color = color, scale = 1.6 * k })
	shards(pos + Vector3.new(0, 1.5, 0), color, math.floor(30 * k), 80)
	local gui, anchor = billboard(pos + Vector3.new(0, 6 * k, 0), 1)
	gui.Size = UDim2.fromOffset(640, 200)
	local card = Instance.new("ImageLabel")
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(-0.6, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.Image = Assets.id(Assets.Fx.StatCard) or ""
	card.ImageColor3 = color
	card.Parent = gui
	local function text(str, x, y, w, h, colorText)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(x, y)
		t.Size = UDim2.fromScale(w, h)
		t.FontFace = DISPLAY
		t.TextScaled = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Text = str
		t.TextColor3 = colorText or WHITE
		t.TextStrokeTransparency = 0.4
		t.Parent = card
		return t
	end
	text(string.upper(reason or "POINT"), 0.14, 0.12, 0.5, 0.16, WHITE)
	local num = text(kmh > 0 and tostring(kmh) or "!", 0.14, 0.3, 0.46, 0.44, WHITE)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), color)
	grad.Rotation = 90
	grad.Parent = num
	text("KM/H", 0.62, 0.42, 0.2, 0.22, color)
	local scale = Instance.new("UIScale")
	scale.Scale = 1.3
	scale.Parent = card
	sfx("SpeedWhoosh", pos)
	task.delay(0.24, sfx, "SpeedSlam", pos)
	TweenService:Create(card, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.3, function()
		if near(pos) then
			mods.CameraController.shake(0.4)
		end
	end)
	task.delay(2.1, function()
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1.7 }):Play()
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
		TweenService:Create(card, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
		task.delay(0.35, function()
			gui:Destroy()
			release(anchor)
		end)
	end)
end

-- Tornado (Legendary): three twisted funnels of wind (the Blender mesh) spin up out of the spot at
-- different speeds, wrapped in scrolling wind beams, with rocks and sparks whirled up its sides
-- and dust thrown off the base; it wanders, then blows apart.
local function tornado(pos, tint, k)
	local color = tint or Color3.fromRGB(70, 255, 190)
	local dur = 3.6
	local height = 26 * k
	local top = 12 * k
	local holder = holderPart(pos)
	local shells = {}
	local FF, NEON = Enum.Material.ForceField, Enum.Material.Neon
	local looks = { { color, FF, 0, 2.6, 1 }, { WHITE, FF, 0.2, -1.8, 0.8 }, { color, NEON, 0.82, 4.2, 0.62 } }
	for i, look in ipairs(looks) do
		local m = fxMesh("Funnel")
		if m then
			m.Color = look[1]
			m.Material = look[2]
			m.Transparency = 1
			shells[i] = { part = m, alpha = look[3], spin = look[4], width = look[5] }
		end
	end
	local beams = {}
	for i = 1, 10 do
		local b = windBeam(holder, i % 3 == 0 and WHITE or color, 0.5 * k, 3.2 * k, 2 + i * 0.15)
		beams[i] = { b = b, a = i / 10 * math.pi * 2, h = 0.2 + (i % 4) * 0.2 }
	end
	local debris = {}
	for i = 1, 16 do
		local r = fxMesh("Rock" .. (i % 4 + 1))
		if not r then
			r = Instance.new("Part")
			r.Anchored = true
			r.CanCollide = false
			r.CanQuery = false
			r.CanTouch = false
			r.Parent = fxFolder
		end
		r.Material = Enum.Material.Slate
		r.Color = Color3.fromRGB(90 + math.random(0, 30), 80, 75)
		local s = (0.6 + math.random() * 1.1) * k
		r.Size = Vector3.new(s, s * 0.8, s)
		debris[i] = { part = r, a = math.random() * 6.3, f = math.random(), speed = 3 + math.random() * 3 }
	end
	sfx("TornadoBurst", pos)
	sfx("TornadoHowl", pos, dur - 0.7)
	task.delay(dur - 0.6, sfx, "TornadoEnd", pos)
	Fx.play("Dust", pos, { n = 14, scale = 2 * k })
	floorRing(pos, color, 22 * k)
	shockDisc(pos, color, 20 * k, 1.4)
	flare(pos + Vector3.new(0, 2, 0), color, 26 * k, 0.8)
	local t0 = os.clock()
	local nextDust = 0
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local e = os.clock() - t0
		local grow = math.clamp(e / 0.5, 0, 1)
		grow = 1 - (1 - grow) * (1 - grow)
		local fade = math.clamp((e - (dur - 0.6)) / 0.6, 0, 1)
		local base = pos + Vector3.new(math.sin(e * 1.3) * 2.5 * k, 0, math.sin(e * 0.9 + 1) * 2 * k)
		local h = height * grow
		for _, s in ipairs(shells) do
			local w = top * 2 * s.width * (1 + fade * 1.2)
			s.part.Size = Vector3.new(w, math.max(0.2, h), w)
			s.part.CFrame = CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, e * s.spin, 0)
			s.part.Transparency = s.alpha + (1 - s.alpha) * math.max(fade, 1 - grow)
		end
		for i, b in ipairs(beams) do
			local a = b.a + e * 5
			local r0 = 1.5 * k
			local r1 = top * (0.7 + b.h * 0.4) * (1 + fade)
			b.b.a0.WorldPosition = base + Vector3.new(math.cos(a) * r0, 0.5, math.sin(a) * r0)
			b.b.a1.WorldPosition = base + Vector3.new(math.cos(a + 2.4) * r1, h * (0.75 + b.h * 0.3), math.sin(a + 2.4) * r1)
			b.b.beam.CurveSize0 = 6 * k
			b.b.beam.CurveSize1 = -4 * k
			b.b.beam.Transparency = NumberSequence.new(0.3 + 0.7 * math.max(fade, 1 - grow))
		end
		for _, d in ipairs(debris) do
			d.f = (d.f + 0.004 * d.speed) % 1
			local a = d.a + e * d.speed * 1.4
			local r = (1.5 + d.f * d.f * top) * (1 + fade * 3)
			d.part.CFrame = CFrame.new(base + Vector3.new(math.cos(a) * r, d.f * h, math.sin(a) * r)) * CFrame.Angles(e * 3, a, e * 2)
			d.part.Transparency = fade
		end
		if e >= nextDust and fade <= 0 then
			nextDust = e + 0.18
			Fx.play("Dust", base, { n = 3, scale = 1.6 * k })
		end
		if e >= dur then
			conn:Disconnect()
			for _, s in ipairs(shells) do
				s.part:Destroy()
			end
			for _, d in ipairs(debris) do
				d.part:Destroy()
			end
			holder:Destroy()
		end
	end)
	task.delay(dur - 0.6, function()
		burst(pos + Vector3.new(0, height * 0.5, 0), WHITE, 18 * k)
		shards(pos + Vector3.new(0, height * 0.4, 0), color, math.floor(40 * k), 90)
		if near(pos) then
			mods.CameraController.shake(0.8)
		end
	end)
	if near(pos) then
		mods.CameraController.shake(0.7)
		task.delay(1, mods.CameraController.shake, 0.5)
		task.delay(2, mods.CameraController.shake, 0.5)
	end
end

-- Black Hole (Mythic): the screen drains of colour as a black core opens over the spot, ringed by
-- a hot photon rim and a spinning gravity well (the Blender mesh, the swirl texture); sparks and
-- streaks spiral into it from all round, wind beams pour inward, then it collapses to a point and
-- detonates in a white dome.
local function blackHole(pos, tint, k)
	local color = tint or Color3.fromRGB(170, 80, 255)
	local dur = 3.6
	local center = pos + Vector3.new(0, 7 * k, 0)
	local holder = holderPart(center)
	local core = take(Enum.PartType.Ball)
	core.Material = Enum.Material.SmoothPlastic
	core.Color = Color3.new(0, 0, 0)
	core.Transparency = 0
	core.Size = Vector3.new(0.5, 0.5, 0.5)
	core.CFrame = CFrame.new(center)
	local rim = take(Enum.PartType.Ball)
	rim.Material = Enum.Material.ForceField -- the photon ring: a lit edge, the black core seen through it
	rim.Color = color
	rim.Transparency = 0
	local well = fxMesh("Well")
	if well then
		well.Color = color
		well.Transparency = 1
	else
		well = take(Enum.PartType.Cylinder)
		well.Color = color
	end
	local swirl = decalDisc("Swirl", color)
	local swirl2 = decalDisc("Swirl", WHITE)
	local beams = {}
	for i = 1, 9 do
		local b = windBeam(holder, i % 2 == 0 and WHITE or color, 1.4 * k, 0.2, -3)
		beams[i] = { b = b, a = i / 9 * math.pi * 2, tilt = (math.random() - 0.5) * 1.2 }
	end
	local bits = {}
	for i = 1, 40 do
		local b = take(Enum.PartType.Ball)
		b.Color = i % 3 == 0 and WHITE or color
		b.Transparency = 0
		local s = (0.3 + math.random() * 0.5) * k
		b.Size = Vector3.new(s, s, s)
		bits[i] = { part = b, a = math.random() * 6.3, y = (math.random() - 0.5) * 0.6, r = (18 + math.random() * 14) * k, delay = math.random() * 1.8, life = 0.9 + math.random() * 0.6 }
	end
	grade(Color3.fromRGB(215, 200, 255), -0.6, dur)
	sfx("BlackHoleHum", center, dur - 0.5)
	task.delay(dur - 1.07, sfx, "BlackHoleSuck", center)
	flare(center, color, 40 * k, 0.6)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local e = os.clock() - t0
		local open = math.clamp(e / 0.5, 0, 1)
		open = 1 - (1 - open) * (1 - open)
		local collapse = math.clamp((e - (dur - 0.35)) / 0.35, 0, 1)
		local s = open * (1 - collapse)
		local tiltCF = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(68))
		if well:IsA("MeshPart") then
			well.Size = Vector3.new(26 * k * s, 8 * k * s, 26 * k * s) + Vector3.new(0.1, 0.1, 0.1)
			well.CFrame = tiltCF * CFrame.Angles(0, e * 3, 0)
			well.Transparency = 1 - s
		else
			well.Size = Vector3.new(0.3, 26 * k * s + 0.1, 26 * k * s + 0.1)
			well.CFrame = tiltCF * CFrame.Angles(0, e * 3, math.rad(90))
			well.Transparency = 0.3 + 0.7 * (1 - s)
		end
		swirl.Size = Vector3.new(30 * k * s + 0.1, 0.05, 30 * k * s + 0.1)
		swirl.CFrame = tiltCF * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, -e * 2.4, 0)
		discAlpha(swirl, 1 - s)
		swirl2.Size = Vector3.new(17 * k * s + 0.1, 0.05, 17 * k * s + 0.1)
		swirl2.CFrame = tiltCF * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, -e * 4, 0)
		discAlpha(swirl2, 0.2 + 0.8 * (1 - s))
		local pulse = 1 + 0.06 * math.sin(e * 22)
		local rs = 9.4 * k * s * pulse + 0.1
		rim.Size = Vector3.new(rs, rs, rs)
		rim.CFrame = CFrame.new(center)
		core.Size = Vector3.new(8, 8, 8) * k * math.max(0.05, s)
		for _, b in ipairs(beams) do
			local a = b.a + e * 1.8
			local r = 30 * k
			b.b.a0.WorldPosition = center + Vector3.new(math.cos(a) * r, b.tilt * r * 0.5, math.sin(a) * r)
			b.b.a1.WorldPosition = center
			b.b.beam.CurveSize0 = 10 * k
			b.b.beam.Transparency = NumberSequence.new(0.45 + 0.55 * (1 - s))
		end
		for _, b in ipairs(bits) do
			local a = math.clamp((e - b.delay) / b.life, 0, 1)
			local r = b.r * (1 - a * a)
			local ang = b.a + a * 7
			b.part.CFrame = CFrame.new(center + Vector3.new(math.cos(ang) * r, b.y * r, math.sin(ang) * r))
			b.part.Transparency = (a <= 0 or a >= 1) and 1 or 0
		end
		if e >= dur then
			conn:Disconnect()
			for _, b in ipairs(bits) do
				release(b.part)
			end
			if well:IsA("MeshPart") then
				well:Destroy()
			else
				release(well)
			end
			swirl:Destroy()
			swirl2:Destroy()
			holder:Destroy()
			rim.Material = Enum.Material.Neon
			release(rim)
			core.Material = Enum.Material.Neon
			release(core)
			-- the detonation
			local dome = fxMesh("Dome")
			if dome then
				dome.Material = Enum.Material.ForceField
				dome.Color = color
				dome.Size = Vector3.new(1, 0.5, 1)
				dome.CFrame = CFrame.new(pos)
				TweenService:Create(dome, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(60, 30, 60) * k, Transparency = 1 }):Play()
				task.delay(0.75, dome.Destroy, dome)
			end
			sfx("BlackHoleBoom", center)
			burst(center, WHITE, 30 * k)
			ringFx(center, color, nil, 34 * k)
			starburst(center, WHITE, 24 * k)
			flare(center, WHITE, 60 * k, 0.9)
			shockDisc(pos, color, 34 * k, 1.2)
			shards(center, color, math.floor(50 * k), 110)
			if near(pos) then
				VFXController.flash(0.7, 0.35)
				mods.CameraController.shake(1.3)
			end
		end
	end)
	if near(pos) then
		mods.CameraController.kick(10) -- the lens pulled toward it
		task.delay(0.8, mods.CameraController.shake, 0.4)
		task.delay(1.8, mods.CameraController.shake, 0.5)
	end
end

-- Tsunami (Legendary): a curling wall of water (the Blender wave, the water texture) rears up
-- behind the scorer's end and sweeps the whole court, spray (the foam flipbook) blowing off its
-- crest, leaving the floor awash behind it; it bursts over the spot and drains away.
local WAVE_FORWARD = 1 -- the imported wave's curl faces +z (checked in Studio)
local function tsunami(pos, tint, dirZ, k)
	local color = tint or Color3.fromRGB(60, 170, 255)
	local C = Config.Court
	local width = (C.HalfWidth + C.FreeZoneSide) * 2 + 16
	local height = 13 * k
	local dur = 3.2
	local reach = C.SideDepth + C.FreeZoneEnd
	local z0 = pos.Z - dirZ * (reach * 1.5)
	local z1 = pos.Z + dirZ * (reach * 0.7)
	local x0, y0 = pos.X, pos.Y - 0.2
	local wave = fxMesh("Wave")
	local back = fxMesh("Wave")
	if wave then
		wave.Material = Enum.Material.Neon
		wave.Color = color
		back.Color = color:Lerp(WHITE, 0.5)
	else
		wave = take(Enum.PartType.Block)
		wave.Material = Enum.Material.Glass
		wave.Color = color
	end
	local crest = holderPart(Vector3.new(x0, y0, z0))
	crest.Size = Vector3.new(width, 1, 2)
	local spray = foamEmitter(crest, color, 4 * k)
	-- the wash left behind: a sheet of water with its texture flowing the wave's way
	local sheet = holderPart(Vector3.new(x0, y0, z0))
	sheet.Transparency = 1
	local water = surfaceImage(sheet, Enum.NormalId.Top, "Water", color, 1)
	water.ScaleType = Enum.ScaleType.Tile
	water.TileSize = UDim2.fromScale(0.25, 0.25)
	water.Size = UDim2.fromScale(1.25, 1.25)
	water.Parent.ClipsDescendants = true
	sfx("TsunamiRush", pos)
	local t0 = os.clock()
	local splashed = false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local e = os.clock() - t0
		local a = math.clamp(e / (dur - 0.5), 0, 1)
		local move = a * a * (3 - 2 * a) * 0.6 + a * 0.4
		local rise = math.clamp(e / 0.45, 0, 1)
		local fall = math.clamp((e - (dur - 0.7)) / 0.7, 0, 1)
		local h = math.max(0.5, height * rise * (1 - fall))
		local z = z0 + (z1 - z0) * move
		local face = CFrame.new(x0, y0, z) * CFrame.Angles(0, dirZ * WAVE_FORWARD > 0 and 0 or math.pi, 0)
		if wave:IsA("MeshPart") then
			local bob = math.sin(e * 6) * 0.04
			wave.Size = Vector3.new(width, h, h * 1.55)
			wave.CFrame = face * CFrame.new(0, h / 2, 0) * CFrame.Angles(bob, 0, 0)
			wave.Transparency = 0.6 + 0.4 * fall
			back.Size = wave.Size * 1.02
			back.CFrame = wave.CFrame
			back.Transparency = fall
		else
			wave.Size = Vector3.new(width, h, 6)
			wave.CFrame = CFrame.new(x0, y0 + h / 2, z) * CFrame.Angles(-dirZ * math.rad(14), 0, 0)
			wave.Transparency = 0.35 + 0.65 * fall
		end
		crest.CFrame = CFrame.new(x0, y0 + h, z + dirZ * h * 0.3)
		if fall < 1 then
			spray:Emit(math.floor(3 * k))
		end
		local len = math.abs(z - z0)
		sheet.Size = Vector3.new(width, 0.05, math.max(0.1, len))
		sheet.CFrame = CFrame.new(x0, y0 + 0.12, (z + z0) / 2)
		local flow = (e * 0.35) % 0.25
		water.Position = UDim2.fromScale(-flow, -flow)
		water.ImageTransparency = 0.3 + 0.7 * fall
		if not splashed and (z - pos.Z) * dirZ >= 0 then
			splashed = true
			local burstAt = holderPart(pos + Vector3.new(0, 2, 0))
			burstAt.Size = Vector3.new(12 * k, 1, 12 * k)
			local s = foamEmitter(burstAt, color, 7 * k)
			s.Speed = NumberRange.new(25, 50)
			s:Emit(60)
			task.delay(2, burstAt.Destroy, burstAt)
			sfx("TsunamiCrash", pos)
			shockDisc(pos, color, 24 * k, 1.2)
			burst(pos + Vector3.new(0, 3, 0), WHITE, 20 * k)
			if near(pos) then
				VFXController.flash(0.3, 0.3)
				mods.CameraController.shake(1)
			end
		end
		if e >= dur then
			conn:Disconnect()
			if wave:IsA("MeshPart") then
				wave:Destroy()
				back:Destroy()
			else
				wave.Material = Enum.Material.Neon
				release(wave)
			end
			spray.Enabled = false
			task.delay(1.5, crest.Destroy, crest)
			sheet:Destroy()
		end
	end)
	grade(Color3.fromRGB(225, 240, 255), -0.1, dur)
	if near(pos) then
		mods.CameraController.shake(0.8)
		task.delay(0.8, mods.CameraController.shake, 0.6)
	end
end

-- Crater (Epic; Rocket League's idea: the blast changes the court for a while): the floor caves in
-- under the spot (the Blender crater) with magma glowing in the pit, rocks are thrown up and come
-- down around the rim, smoke rolls off it, and it all stays a few seconds before sinking away.
local function crater(pos, tint, k)
	local color = tint or Color3.fromRGB(255, 120, 50)
	local floorY = pos.Y - 0.08
	local bowl = fxMesh("Crater")
	local radius = 7 * k
	if bowl then
		bowl.Material = Enum.Material.Slate
		bowl.Color = Color3.fromRGB(45, 38, 36)
		bowl.Size = Vector3.new(0.1, 0.1, 0.1)
		bowl.CFrame = CFrame.new(pos.X, floorY, pos.Z)
		TweenService:Create(bowl, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(radius * 2, radius * 0.55, radius * 2) }):Play()
	else
		bowl = take(Enum.PartType.Cylinder)
		bowl.Material = Enum.Material.Slate
		bowl.Color = Color3.fromRGB(35, 30, 30)
		bowl.Transparency = 0
		bowl.Size = Vector3.new(0.2, radius * 1.3, radius * 1.3)
		bowl.CFrame = CFrame.new(pos.X, floorY, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	end
	local glow = take(Enum.PartType.Cylinder)
	glow.Color = color
	glow.Transparency = 0.15
	glow.Size = Vector3.new(0.22, radius * 0.7, radius * 0.7)
	glow.CFrame = CFrame.new(pos.X, floorY - 0.1, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = radius * 2.5
	light.Brightness = 4
	light.Parent = glow
	local rocks = {}
	for i = 1, 18 do
		local r = fxMesh("Rock" .. (i % 4 + 1))
		if not r then
			r = Instance.new("Part")
			r.Anchored = true
			r.CanCollide = false
			r.CanQuery = false
			r.CanTouch = false
			r.Parent = fxFolder
		end
		r.Material = Enum.Material.Slate
		r.Color = Color3.fromRGB(70 + math.random(0, 30), 60, 55)
		local s = (1 + math.random() * 1.8) * k
		r.Size = Vector3.new(s, s * 0.7, s)
		local a = (i / 18) * math.pi * 2 + math.random() * 0.3
		local d = radius * (0.95 + math.random() * 0.6)
		local land = Vector3.new(pos.X + math.cos(a) * d, floorY + s * 0.25, pos.Z + math.sin(a) * d)
		local peak = (land + pos) / 2 + Vector3.new(0, (6 + math.random() * 8) * k, 0)
		local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		local rest = CFrame.new(land) * CFrame.Angles(math.rad(math.random(-35, 35)), math.random() * 6, math.rad(math.random(-35, 35)))
		r.CFrame = CFrame.new(pos)
		local up = TweenService:Create(r, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) * spin })
		up.Completed:Connect(function()
			local down = TweenService:Create(r, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = rest })
			down.Completed:Connect(function()
				Fx.play("Dust", land, { n = 2, scale = 1.2 * k })
			end)
			down:Play()
		end)
		up:Play()
		rocks[i] = r
	end
	sfx("CraterSlam", pos)
	task.delay(0.5, sfx, "CraterRubble", pos)
	task.delay(0.9, sfx, "CraterLava", pos)
	task.delay(2.2, sfx, "CraterLava", pos)
	Fx.play("FloorImpact", pos, { color = color, scale = 2.2 * k, count = 2 })
	shockDisc(pos, color, radius * 3, 1.3)
	flare(pos + Vector3.new(0, 2, 0), color, 26 * k, 0.7)
	burst(pos + Vector3.new(0, 1.5, 0), color, 14 * k)
	task.delay(0.65, function()
		if near(pos) then
			mods.CameraController.shake(0.6)
		end
	end)
	-- smoke rolling off the pit while it glows
	for i = 1, 8 do
		task.delay(0.3 + i * 0.35, Fx.play, "Dust", pos + Vector3.new(0, 0.5, 0), { n = 3, scale = 1.6 * k, color = color:Lerp(WHITE, 0.6) })
	end
	TweenService:Create(glow, TweenInfo.new(5), { Transparency = 0.9 }):Play()
	TweenService:Create(light, TweenInfo.new(5), { Brightness = 0 }):Play()
	task.delay(6, function()
		for _, r in ipairs(rocks) do
			TweenService:Create(r, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = r.CFrame - Vector3.new(0, 3 * k, 0) }):Play()
		end
		TweenService:Create(bowl, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		task.delay(0.85, function()
			for _, r in ipairs(rocks) do
				r:Destroy()
			end
			light:Destroy()
			if bowl:IsA("MeshPart") then
				bowl:Destroy()
			else
				bowl.Material = Enum.Material.Neon
				release(bowl)
			end
			release(glow)
		end)
	end)
	if near(pos) then
		mods.CameraController.shake(0.9)
	end
end

-- A score effect at pos: the effect's key, the spike colour's tint (or nil), which way the
-- attack travelled along z, the scale and the point's callout. False for Dust, the plain floor
-- impact.
local function playScore(effect, pos, tint, dirZ, k, reason)
	if effect == "Meteor" then
		meteorStrike(pos, dirZ, tint, k)
	elseif effect == "Thunderbolt" then
		thunderbolt(pos, tint, k)
	elseif effect == "Speed" then
		speedBurst(pos, tint, k or 1, reason)
	elseif effect == "Tornado" then
		tornado(pos, tint, k or 1)
	elseif effect == "BlackHole" then
		blackHole(pos, tint, k or 1)
	elseif effect == "Tsunami" then
		tsunami(pos, tint, dirZ or 1, k or 1)
	elseif effect == "Crater" then
		crater(pos, tint, k or 1)
	elseif effect == "Fire" or effect == "Shockwave" then
		Fx.play("Score" .. effect, pos, { color = tint, scale = k })
		if effect == "Fire" then
			sfx("ScoreFire", pos)
		end
		if near(pos) then
			mods.CameraController.shake(effect == "Fire" and 0.5 or 0.4)
		end
	else
		return false
	end
	return true
end


-- After the rally (on the server's call, so a late dig never sets one off), where the point
-- landed (the owner: "make scoring animations play at the end of the rally wherever you score,
-- and make them large and exaggerated"): every scored point blows up there (a flash, a burst, two
-- shock rings across the floor, a pillar of light, debris and a dust cloud, the screen flashing
-- and shaking) in the scorer's spike colour (else the team's), with their equipped score effect
-- on top, scaled by its rarity (Config.Match.ScoreFx.Scale: the rarer, the bigger, up to the whole
-- court). CameraController holds on the spot first (ScoreFx.Hold), then the scorer.
local function celebrate(a)
	local model = Util.modelOf(a.scorerId)
	local land = a.landing
	if not land then
		local hrp = model and model:FindFirstChild("HumanoidRootPart")
		land = hrp and hrp.Position
	end
	if not land then
		return
	end
	local pos = Vector3.new(land.X, 0.2, land.Z)
	local side = State.sideOfEntity(a.scorerId) or (land.Z > 0 and -1 or 1)
	local tint = model and Spins.tint(Spins.equipped(model, "Color"))
	local color = tint or teamColor(a.winner)
	local big = a.reason == "Ace" or a.reason == "Stuff" or a.reason == "Break"
	burst(pos + Vector3.new(0, 2, 0), WHITE, big and 30 or 24)
	starburst(pos + Vector3.new(0, 1.5, 0), color, big and 30 or 24)
	floorRing(pos, color, big and 40 or 32)
	task.delay(0.09, floorRing, pos, WHITE, big and 26 or 20)
	task.delay(0.05, ringFx, pos + Vector3.new(0, 3, 0), color, nil, big and 34 or 26)
	lightPillar(pos, color, big and 70 or 56, big and 7 or 5.5)
	shards(pos + Vector3.new(0, 1, 0), color, big and 60 or 44, 95)
	Fx.play("FloorImpact", pos, { color = color, scale = 2.6, count = 3 })
	emit("Dust", pos + Vector3.new(0, 0.5, 0), 70, nil)
	if model then
		local fx = Spins.equipped(model, "Effect")
		playScore(fx.Key, pos, tint, -side, SCORE_FX.Scale[fx.Rarity] or SCORE_FX.Scale.Common, Config.Match.Celebrate[a.reason])
	end
	VFXController.flash(big and 0.55 or 0.45, 0.3)
	mods.CameraController.shake(big and 1.2 or 1)
	mods.CameraController.kick(-8)
	local A = mods.AudioController
	A.play("ScoreImpact", { pos = pos })
	A.play("ScoreShockwave", { pos = pos })
	task.delay(0.12, A.play, "ScoreDebris", { pos = pos })
	task.delay(0.45, A.play, "ScoreSparkle", { pos = pos })
	if a.reason == "Ace" then
		A.play("AceStinger")
	elseif a.reason == "Stuff" then
		A.play("StuffSlam", { pos = pos })
	end
end

-- A score effect anywhere, outside a match (the Locker's preview): the effect's key, the spike
-- colour's tint (or nil), the direction the attack travelled along z and the scale (1 if nil).
function VFXController.previewEffect(pos, effect, tint, dirZ, k)
	if not playScore(effect, pos, tint, dirZ or -1, k) then
		Fx.play("FloorImpact", pos, { color = tint })
	end
end

local function onBallEvent(kind, ev, meta)
	if kind == "Land" then
		if ev.kind ~= "Floor" then
			return
		end
		local pos = Vector3.new(0, 0.2, ev.pos.Z)
		local speed = ev.vel.Magnitude
		local hard = speed > 45
		local c = nil
		if meta and meta.thunder then
			c = THUNDER
		elseif meta and meta.energy then
			c = AZURE
		end
		Fx.play("FloorImpact", pos, { color = c, scale = hard and 1 or 0.55, count = hard and 1.4 or 0.6 })
		if hard then
			starburst(pos + Vector3.new(0, 0.8, 0), c or WHITE, 8)
			mods.CameraController.shake(0.35)
		end
	elseif kind == "Net" then
		Fx.play("NetImpact", Vector3.new(0, ev.pos.Y, 0))
		VFXController.rippleNet()
	end
end

-- The net sways where it was hit.
function VFXController.rippleNet()
	local arena = workspace:FindFirstChild("Arena")
	local net = arena and arena:FindFirstChild("Net")
	local mesh = net and net:FindFirstChild("Mesh")
	if not mesh then
		return
	end
	for _, strand in ipairs(mesh:GetChildren()) do
		if strand:IsA("BasePart") then
			local base = strand:GetAttribute("BaseCF")
			if not base then
				base = strand.CFrame
				strand:SetAttribute("BaseCF", base)
			end
			local amp = 0.5 * (1 - math.clamp(math.abs(strand.Position.X) / 16, 0, 0.8))
			strand.CFrame = base * CFrame.new(0, 0, amp)
			TweenService:Create(strand, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { CFrame = base }):Play()
		end
	end
end

-- The guard break (the owner: "on guard breaks, have a shield that gets broken"): a force-field
-- shield pops up around the receiver, then shatters into glass shards that spin away and fade.
local SHIELD = Color3.fromRGB(120, 220, 255)
local function shieldShatter(center)
	local dome = take(Enum.PartType.Ball)
	dome.Material = Enum.Material.ForceField
	dome.Color = SHIELD
	dome.Size = Vector3.new(5.5, 5.5, 5.5)
	dome.CFrame = CFrame.new(center)
	dome.Transparency = 0
	TweenService:Create(dome, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(7.4, 7.4, 7.4) }):Play()
	task.delay(0.12, function()
		dome.Material = Enum.Material.Neon
		release(dome)
		ringFx(center, SHIELD, nil, 16)
		burst(center, WHITE, 12)
		local rng = Random.new()
		for _ = 1, 22 do
			local dir = Vector3.new(rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.6, 1), rng:NextNumber(-1, 1)).Unit
			local shard = take(Enum.PartType.Block)
			shard.Material = Enum.Material.Glass
			shard.Color = SHIELD
			shard.Transparency = 0.15
			shard.Size = Vector3.new(0.12, rng:NextNumber(0.6, 1.6), rng:NextNumber(0.4, 1.1))
			shard.CFrame = CFrame.lookAt(center + dir * 3.6, center + dir * 5) * CFrame.Angles(0, 0, rng:NextNumber(0, math.pi))
			local to = shard.CFrame + dir * rng:NextNumber(6, 12) + Vector3.new(0, -rng:NextNumber(1, 3), 0)
			local spin = CFrame.Angles(rng:NextNumber(-4, 4), rng:NextNumber(-4, 4), rng:NextNumber(-4, 4))
			local tw = TweenService:Create(shard, TweenInfo.new(rng:NextNumber(0.45, 0.7), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = to * spin, Transparency = 1 })
			tw.Completed:Connect(function()
				shard.Material = Enum.Material.Neon
				release(shard)
			end)
			tw:Play()
		end
	end)
end

local function onBreak(a)
	local model = a.id and Util.modelOf(a.id)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	local pos = hrp and hrp.Position + Vector3.new(0, 2, 0) or Vector3.new(0, 3, 0)
	shieldShatter(hrp and hrp.Position + Vector3.new(0, 0.6, 0) or pos)
	Fx.play("GuardBreak", pos)
	VFXController.popup(pos, "Guard break!", HOT, 1.2)
	if a.team == State.myTeam then
		VFXController.flash(0.35, 0.3)
		mods.CameraController.shake(0.45)
	end
end

function VFXController.init(m)
	mods = m
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "SpikeRushFX"
	fxFolder.Parent = workspace

	task.spawn(Fx.preload)

	buildScreen()

	State.signals.Ball:Connect(function(snap, isEcho)
		if isEcho or snap.state ~= "Flight" then
			return
		end
		onHit(snap)
	end)
	State.signals.BallEvent:Connect(onBallEvent)
	State.signals.Announce:Connect(function(a)
		if a.kind == "Break" then
			onBreak(a)
		elseif a.kind == "Point" then
			if a.landing and (a.reason == "Spike" or a.reason == "Ace" or a.reason == "Stuff" or a.reason == "Break") then
				emit("Sparks", a.landing + Vector3.new(0, 1, 0), 24, teamColor(a.winner))
			end
			if a.scorerId and not a.error and Config.Match.Celebrate[a.reason] and State.isPlaying then
				celebrate(a) -- at once: the camera is on the spot for its first moments
			end
		end
	end)
	State.signals.Action:Connect(function(entityId, kind, extra)
		local model = Util.modelOf(entityId)
		if kind == "Ability" then
			VFXController.ability(entityId, extra)
		elseif kind == "Jump" then
			VFXController.boom(entityId, extra)
		elseif kind == "Charge" and model then
			setAura(model, true, 0, true)
		elseif kind == "ChargeEnd" and model then
			setAura(model, false)
		elseif kind == "Prowl" and model then
			-- Feral Leap: a player's charge on the ground, or a bot's in the air ("auto")
			local FL = Config.Abilities.Feral
			remoteArc(model, "prowl", 0, extra == "auto" and FL.AutoChargeTime or FL.ChargeTime)
		elseif kind == "Leap" and model then
			local g = tonumber(extra) or 0
			remoteArc(model, "leap", g)
			leapBurst(model, g)
		elseif kind == "ProwlEnd" and model then
			remoteArc(model, "end")
		elseif kind == "Slide" and model then
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hrp then
				emit("Dust", Vector3.new(hrp.Position.X, 0.4, hrp.Position.Z), 12)
			end
		end
	end)
	-- local Azure charge drives my own aura
	State.signals.Charge:Connect(function(energy, _, st)
		local c = player.Character
		if not c then
			return
		end
		if st == "idle" then
			if auras[c] then
				setAura(c, false)
			end
		else
			local e = energy
			if st == "over" then
				e = 1.2
			end
			setAura(c, true, e)
		end
	end)
	RunService.RenderStepped:Connect(updateLines)
	RunService.RenderStepped:Connect(updateAuras)
end

return VFXController
