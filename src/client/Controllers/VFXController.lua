-- Anime-style effects for the side view, all procedural (no assets required), with optional
-- Toolbox overrides (ReplicatedStorage.ToolboxAssets.VFX.<Name>).
--  * contact: starbursts and rings drawn in the screen plane, lightning bolts (Thunder Spiker),
--    a dragon-blue burst and hover aura (Azure Dragon), shards, sparks
--  * jumps: a "boom" ring and streaks under the feet
--  * screen: white flash, horizontal speed lines, and the impact frame: the screen goes white,
--    the attacker becomes a black silhouette over a coloured radial burst for a split second
--  * text: receive grades ("PERFECT 96" with a badge), callouts ("Free ball!", "Stuff!")
--  * unlockables: the attacker's spike colour tints the impact; their score effect (fire
--    explosion, meteor strike, thunderbolt, shockwave) plays where the point lands
-- Parts, rings and starbursts are pooled; popups and the impact frame are short-lived.

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

local VFXController = {}
local mods

local player = Players.LocalPlayer
local UI = Config.UI
local FLAT = CFrame.Angles(0, 0, math.rad(90))
local WHITE = Color3.new(1, 1, 1)
local THUNDER = Color3.fromRGB(255, 226, 60)
local AZURE = Color3.fromRGB(70, 210, 255)
local HOT = Color3.fromRGB(255, 50, 90)
local VECTOR = Config.Abilities.Vector.Color
local COUNTER = Config.Abilities.Counter.Color

local fxFolder
local pool = {}
local emitterHolder, sparkEmitter, dustEmitter, fireEmitter
local screen, flashFrame, linesFrame
local lines = {}
local linesUntil, linesDir = 0, 1
local impactGui
local auras = {}
local streaks = {}

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

local function animate(p, duration, fromSize, toSize, fromT, toT, cf)
	p.Size = fromSize
	p.Transparency = fromT
	p.CFrame = cf
	local tween = TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = toSize,
		Transparency = toT,
	})
	tween:Play()
	tween.Completed:Connect(function()
		release(p)
	end)
end

local function burst(pos, color, radius, duration)
	local p = take(Enum.PartType.Ball)
	p.Color = color
	animate(p, duration, Vector3.new(0.4, 0.4, 0.4), Vector3.new(radius * 2, radius * 2, radius * 2), 0.05, 1, CFrame.new(pos))
end

local function floorRing(pos, color, radius, duration)
	local p = take(Enum.PartType.Cylinder)
	p.Color = color
	animate(p, duration, Vector3.new(0.06, 0.6, 0.6), Vector3.new(0.02, radius * 2, radius * 2), 0.1, 1, CFrame.new(pos.X, 0.2, pos.Z) * FLAT)
end

-- Shards fly out within the play plane so they read from the side camera.
local function shards(pos, color, count, speed)
	for i = 1, count do
		local p = take(Enum.PartType.Block)
		p.Color = color
		local a = (i / count) * math.pi * 2 + math.random() * 0.5
		local dir = Vector3.new((math.random() - 0.5) * 0.4, math.sin(a), math.cos(a)).Unit
		local len = 0.9 + math.random() * 1.4
		p.Size = Vector3.new(0.16, 0.16, len)
		p.CFrame = CFrame.lookAt(pos, pos + dir)
		p.Transparency = 0
		local goal = CFrame.lookAt(pos + dir * speed * 0.2, pos + dir * (speed * 0.2 + 1))
		local tween = TweenService:Create(p, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = goal,
			Size = Vector3.new(0.05, 0.05, len * 1.5),
			Transparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			release(p)
		end)
	end
end

-- A jagged lightning bolt from `from` along `dir`, in the play plane.
local function bolt(from, dir, length, color)
	local segs = 6
	local prev = from
	local side = Vector3.new(0, -dir.Z, dir.Y)
	for i = 1, segs do
		local along = from + dir * (length * i / segs)
		local jag = side * ((math.random() - 0.5) * length * 0.28)
		local nextP = along + jag
		if i == segs then
			nextP = along
		end
		local p = take(Enum.PartType.Block)
		p.Color = color
		local mid = (prev + nextP) / 2
		local seg = (nextP - prev).Magnitude
		p.Size = Vector3.new(0.22, 0.22, seg)
		p.CFrame = CFrame.lookAt(mid, nextP) + Vector3.new(-0.6, 0, 0)
		p.Transparency = 0
		local tween = TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Linear), { Transparency = 1, Size = Vector3.new(0.08, 0.08, seg) })
		tween:Play()
		tween.Completed:Connect(function()
			release(p)
		end)
		prev = nextP
	end
end

------------------------------------------------------------------------------------------
-- GUI shapes in world space (always face the camera). Rings and starbursts are pooled: each
-- entry owns its anchor part and BillboardGui and is only re-coloured and re-tweened on reuse.
------------------------------------------------------------------------------------------

local ringPool, burstPool = {}, {}
local MAX_RAYS = 16

local function newBillboard()
	local anchor = newPart(Enum.PartType.Block)
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Enabled = false
	gui.Parent = anchor
	return gui, anchor
end

local function park(entry, list)
	entry.gui.Enabled = false
	entry.anchor.CFrame = PARKED
	table.insert(list, entry)
end

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

local function ringFx(pos, color, fromSize, toSize, duration, thickness)
	local e = table.remove(ringPool)
	if not e then
		local gui, anchor = newBillboard()
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundTransparency = 1
		f.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Parent = f
		e = { gui = gui, anchor = anchor, stroke = stroke, frame = f }
	end
	e.frame.Size = UDim2.fromScale(1, 1)
	e.frame.Rotation = 0
	e.anchor.CFrame = CFrame.new(pos)
	e.gui.Size = UDim2.new(fromSize, 0, fromSize, 0)
	e.stroke.Color = color
	e.stroke.Thickness = thickness or 6
	e.stroke.Transparency = 0
	e.gui.Enabled = true
	TweenService:Create(e.gui, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(toSize, 0, toSize, 0) }):Play()
	TweenService:Create(e.stroke, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Thickness = 1 }):Play()
	task.delay(duration + 0.05, function()
		park(e, ringPool)
	end)
	return e
end

local function starburst(pos, color, size, rays, duration)
	local e = table.remove(burstPool)
	if not e then
		local gui, anchor = newBillboard()
		local scale = Instance.new("UIScale")
		scale.Parent = gui
		local list = {}
		for i = 1, MAX_RAYS do
			local r = Instance.new("Frame")
			r.AnchorPoint = Vector2.new(0, 0.5)
			r.Position = UDim2.fromScale(0.5, 0.5)
			r.BorderSizePixel = 0
			r.Parent = gui
			list[i] = r
		end
		local core = Instance.new("Frame")
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5, 0.5)
		core.Size = UDim2.fromScale(0.26, 0.26)
		core.BackgroundColor3 = WHITE
		core.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = core
		e = { gui = gui, anchor = anchor, scale = scale, rays = list, core = core }
	end
	rays = math.min(rays, MAX_RAYS)
	e.anchor.CFrame = CFrame.new(pos)
	e.gui.Size = UDim2.new(size, 0, size, 0)
	e.scale.Scale = 0.35
	for i, r in ipairs(e.rays) do
		if i <= rays then
			r.Visible = true
			r.Size = UDim2.new(0.28 + math.random() * 0.22, 0, 0, math.random(4, 9))
			r.Rotation = (i / rays) * 360 + math.random() * 12
			r.BackgroundColor3 = color
			r.BackgroundTransparency = 0
		else
			r.Visible = false
		end
	end
	e.core.BackgroundTransparency = 0
	e.gui.Enabled = true
	TweenService:Create(e.scale, TweenInfo.new(duration * 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(duration * 0.35, function()
		local fade = TweenInfo.new(duration * 0.65)
		for i = 1, rays do
			TweenService:Create(e.rays[i], fade, { BackgroundTransparency = 1 }):Play()
		end
		TweenService:Create(e.core, fade, { BackgroundTransparency = 1 }):Play()
	end)
	task.delay(duration + 0.05, function()
		park(e, burstPool)
	end)
end

-- A sonic-boom ring: an ellipse standing across the ball's flight, as on The Spike's hardest
-- spikes. The camera looks along +x, so screen right is +z and the flight angle on screen is
-- atan2(vy, vz); a GUI rotation is clockwise, hence the minus.
local function sonicRing(pos, vel, color, size, duration)
	local e = ringFx(pos, color, size * 0.4, size, duration, 5)
	e.frame.Size = UDim2.fromScale(0.36, 1)
	e.frame.Rotation = -math.deg(math.atan2(vel.Y, vel.Z))
end

------------------------------------------------------------------------------------------
-- particles
------------------------------------------------------------------------------------------

local function makeEmitter(texture, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Enabled = false
	e.LightInfluence = 0
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = emitterHolder
	return e
end

local function emit(emitter, pos, count, color)
	emitterHolder.CFrame = CFrame.new(pos)
	if color then
		emitter.Color = ColorSequence.new(color)
	end
	emitter:Emit(count)
end

-- A Toolbox effect from ReplicatedStorage.ToolboxAssets.VFX.<name>, fired once at `pos`.
-- Templates can be an Attachment, a Part or a Model holding ParticleEmitters. Each emitter
-- bursts :Emit(EmitCount) after EmitDelay seconds (both optional attributes).
local function toolboxFx(name, pos)
	local template = Assets.toolbox("VFX." .. name)
	if not template then
		return false
	end
	local holder = take(Enum.PartType.Block)
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(pos)
	local clone = Assets.sanitize(template:Clone())
	if clone:IsA("BasePart") then
		if not clone:GetAttribute("Visible") then
			clone.Transparency = 1
		end
		clone.CFrame = holder.CFrame
	elseif clone:IsA("Model") then
		clone:PivotTo(holder.CFrame)
	end
	clone.Parent = holder
	local longest = 0.5
	local list = clone:GetDescendants()
	table.insert(list, clone)
	for _, d in ipairs(list) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			local delay = d:GetAttribute("EmitDelay") or 0
			local count = d:GetAttribute("EmitCount") or 20
			if delay > 0 then
				task.delay(delay, function()
					if d.Parent then
						d:Emit(count)
					end
				end)
			else
				d:Emit(count)
			end
			longest = math.max(longest, delay + d.Lifetime.Max)
		end
	end
	task.delay(longest + 0.3, function()
		clone:Destroy()
		release(holder)
	end)
	return true
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
	local count = State.isMobile and 14 or 24
	for i = 1, count do
		local l = Instance.new("Frame")
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.BorderSizePixel = 0
		l.BackgroundColor3 = WHITE
		l.Parent = linesFrame
		lines[i] = { frame = l, x = math.random(), y = math.random(), len = 0.1, speed = 1 }
	end

	-- glowing horizontal streaks that flash across the screen on the biggest hits
	for i = 1, 4 do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = WHITE
		f.BackgroundTransparency = 1
		f.Size = UDim2.new(1.2, 0, 0, 4)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Parent = screen
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0),
			NumberSequenceKeypoint.new(0.65, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
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
		l.frame.BackgroundColor3 = color or WHITE
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
		l.frame.Size = UDim2.new(l.len, 0, 0, 2 + (l.speed > 3.5 and 2 or 0))
		l.frame.BackgroundTransparency = 1 - 0.7 * fade
	end
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
	local burstFrame = Instance.new("Frame")
	burstFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	burstFrame.Position = UDim2.fromOffset(sp.X, sp.Y)
	burstFrame.Size = UDim2.fromOffset(vs.Y * 1.3, vs.Y * 1.3)
	burstFrame.BackgroundTransparency = 1
	burstFrame.Parent = bg
	for i = 1, 22 do
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0, 0.5)
		r.Position = UDim2.fromScale(0.5, 0.5)
		r.Size = UDim2.new(0.25 + math.random() * 0.3, 0, 0, math.random(8, 26))
		r.Rotation = (i / 22) * 360 + math.random() * 8
		r.BackgroundColor3 = color or HOT
		r.BorderSizePixel = 0
		r.Parent = burstFrame
	end
	-- a soft glow: stacked discs, fainter as they grow
	for i, k in ipairs({ 0.62, 0.46, 0.3 }) do
		local glowDisc = Instance.new("Frame")
		glowDisc.AnchorPoint = Vector2.new(0.5, 0.5)
		glowDisc.Position = UDim2.fromScale(0.5, 0.5)
		glowDisc.Size = UDim2.fromScale(k, k)
		glowDisc.BackgroundColor3 = color or HOT
		glowDisc.BackgroundTransparency = 0.75 - i * 0.2
		glowDisc.BorderSizePixel = 0
		glowDisc.Parent = burstFrame
		local gc = Instance.new("UICorner")
		gc.CornerRadius = UDim.new(0.5, 0)
		gc.Parent = glowDisc
	end
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(0.16, 0.16)
	disc.BackgroundColor3 = WHITE
	disc.Parent = burstFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	-- a pillar of light through the hitter
	local pillar = Instance.new("Frame")
	pillar.AnchorPoint = Vector2.new(0.5, 0.5)
	pillar.Position = UDim2.fromOffset(sp.X, sp.Y)
	pillar.Size = UDim2.new(0, math.floor(vs.Y * 0.07), 2, 0)
	pillar.BackgroundColor3 = WHITE
	pillar.BorderSizePixel = 0
	pillar.Parent = bg
	local pg = Instance.new("UIGradient")
	pg.Color = ColorSequence.new(color or HOT, WHITE)
	pg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 0.1),
		NumberSequenceKeypoint.new(0.6, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	pg.Rotation = 0
	pg.Parent = pillar
	-- a gold crescent slash: half of a thick ring
	local crescent = Instance.new("Frame")
	crescent.AnchorPoint = Vector2.new(0.5, 0.5)
	crescent.Position = UDim2.fromOffset(sp.X, sp.Y)
	crescent.Size = UDim2.fromOffset(vs.Y * 0.5, vs.Y * 0.5)
	crescent.BackgroundTransparency = 1
	crescent.Rotation = -30 + math.random() * 60
	crescent.Parent = bg
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0.5, 0)
	cc.Parent = crescent
	local cs = Instance.new("UIStroke")
	cs.Thickness = math.max(6, vs.Y * 0.018)
	cs.Color = Color3.fromRGB(255, 205, 70)
	cs.Parent = crescent
	local cg = Instance.new("UIGradient")
	cg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.48, 0),
		NumberSequenceKeypoint.new(0.52, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	cg.Rotation = 90
	cg.Parent = cs

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
		TweenService:Create(bg, TweenInfo.new(0.14), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(vp, TweenInfo.new(0.14), { ImageTransparency = 1 }):Play()
		for _, r in ipairs(burstFrame:GetChildren()) do
			if r:IsA("Frame") then
				TweenService:Create(r, TweenInfo.new(0.14), { BackgroundTransparency = 1 }):Play()
			end
		end
		TweenService:Create(pillar, TweenInfo.new(0.16), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(cs, TweenInfo.new(0.16), { Transparency = 1 }):Play()
	end)
	task.delay(0.26, function()
		impactGui.Enabled = false
		impactGui:ClearAllChildren()
	end)
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
		-- a small shield badge: perfect receives drain almost no stamina
		local b = Instance.new("Frame")
		b.Size = UDim2.fromOffset(30, 30)
		b.Rotation = 45
		b.BackgroundColor3 = color
		b.LayoutOrder = 1
		b.Parent = row
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = UI.Ink
		st.Parent = b
		table.insert(fades, { b, "BackgroundTransparency" })
		table.insert(fades, { st, "Transparency" })
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.Font = Enum.Font.Bangers
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
	if not VFXController.hasBoom(model) then
		emit(dustEmitter, Vector3.new(p.X, 0.4, p.Z), 6)
		return
	end
	local big = kind == "Spike" or kind == "Serve"
	if entityId == State.myId and mods then
		mods.AudioController.play("Boom", { volume = big and 0.8 or 0.45, minGap = 0.05 })
	end
	if big and toolboxFx("JumpBoom", Vector3.new(p.X, 0.3, p.Z)) then
		return -- the Toolbox boom replaces the procedural ring and streaks
	end
	floorRing(Vector3.new(p.X, 0.2, p.Z), WHITE, big and 8 or 4, big and 0.36 or 0.26)
	emit(dustEmitter, Vector3.new(p.X, 0.4, p.Z), big and 24 or 10)
	if big then
		ringFx(Vector3.new(p.X, 1.2, p.Z), WHITE, 2, 12, 0.3, 6)
		for i = -1, 1 do
			local s = take(Enum.PartType.Block)
			s.Color = WHITE
			local base = Vector3.new(p.X - 0.8, 1.6, p.Z + i * 0.7)
			animate(s, 0.22, Vector3.new(0.1, 3.2, 0.14), Vector3.new(0.04, 0.4, 0.06), 0.2, 1, CFrame.new(base))
		end
	end
end

-- Emitters for the Azure aura: the Toolbox AzureAura template's emitters if there is one,
-- otherwise a procedural blue flame. Returns a list of { emitter, baseRate }.
local function auraEmitters(att)
	local out = {}
	local template = Assets.toolbox("VFX.AzureAura")
	if template then
		local clone = Assets.sanitize(template:Clone())
		local list = clone:GetDescendants()
		table.insert(list, clone)
		for _, d in ipairs(list) do
			if d:IsA("ParticleEmitter") then
				local pe = d:Clone()
				pe.Enabled = true
				pe.Parent = att
				table.insert(out, { pe, pe.Rate > 0 and pe.Rate or 40 })
			end
		end
		clone:Destroy()
		if #out > 0 then
			return out
		end
	end
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = Assets.Images.Fire
	pe.Color = ColorSequence.new(Color3.fromRGB(150, 245, 255), Color3.fromRGB(30, 100, 255))
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Rate = 40
	pe.Lifetime = NumberRange.new(0.3, 0.55)
	pe.Speed = NumberRange.new(2, 5)
	pe.RotSpeed = NumberRange.new(-200, 200)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	pe.Parent = att
	table.insert(out, { pe, 40 })
	return out
end

-- The charging hand: an energy orb, swirling sparks and a light on the hitting hand.
local function handFx(model, hrp)
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm") or hrp
	local att = Instance.new("Attachment")
	att.Name = "AzureHand"
	att.Parent = hand
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = Assets.Images.Spark
	sparks.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255), AZURE)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Rate = 40
	sparks.Lifetime = NumberRange.new(0.18, 0.4)
	sparks.Speed = NumberRange.new(1.5, 4)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.RotSpeed = NumberRange.new(-360, 360)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.LockedToPart = true
	sparks.Parent = att
	local light = Instance.new("PointLight")
	light.Color = AZURE
	light.Range = 6
	light.Brightness = 1
	light.Shadows = false
	light.Parent = att
	-- the orb: a bright core inside a spinning ring, sized in studs
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(1, 0, 1, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = att
	gui.Parent = att
	local glowDisc = Instance.new("Frame")
	glowDisc.AnchorPoint = Vector2.new(0.5, 0.5)
	glowDisc.Position = UDim2.fromScale(0.5, 0.5)
	glowDisc.Size = UDim2.fromScale(1, 1)
	glowDisc.BackgroundColor3 = AZURE
	glowDisc.BackgroundTransparency = 0.55
	glowDisc.BorderSizePixel = 0
	glowDisc.Parent = gui
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(0.5, 0)
	gc.Parent = glowDisc
	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.5, 0.5)
	core.BackgroundColor3 = WHITE
	core.BorderSizePixel = 0
	core.Parent = gui
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0.5, 0)
	cc.Parent = core
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1.35, 1.35)
	ring.BackgroundTransparency = 1
	ring.Parent = gui
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = ring
	local rs = Instance.new("UIStroke")
	rs.Thickness = 3
	rs.Color = Color3.fromRGB(190, 245, 255)
	rs.Parent = ring
	local rg = Instance.new("UIGradient")
	rg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0),
		NumberSequenceKeypoint.new(0.55, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	rg.Parent = rs
	return { att = att, sparks = sparks, light = light, gui = gui, glow = glowDisc, ring = ring, ringStroke = rs }
end

local function applyEnergy(fx, e)
	e = math.clamp(e, 0, 1.3)
	fx.energy = e
	-- 30 + 110 * e particles/s for the procedural flame (base 40): about 0.75x to 4.3x
	local k = (30 + 110 * e) / 40
	for _, item in ipairs(fx.emitters) do
		item[1].Rate = item[2] * k
	end
	local over = e > 1
	local color = over and HOT or AZURE
	fx.hl.FillTransparency = 0.85 - 0.35 * math.min(e, 1)
	fx.hl.FillColor = color
	local h = fx.hand
	local size = 0.8 + 2.6 * math.min(e, 1)
	h.gui.Size = UDim2.new(size, 0, size, 0)
	h.glow.BackgroundColor3 = color
	h.ringStroke.Color = over and Color3.fromRGB(255, 170, 190) or Color3.fromRGB(190, 245, 255)
	h.light.Color = color
	h.light.Range = 6 + 10 * math.min(e, 1)
	h.light.Brightness = 1 + 3 * math.min(e, 1)
	h.sparks.Rate = 30 + 120 * math.min(e, 1)
	h.sparks.Color = ColorSequence.new(Color3.fromRGB(230, 250, 255), color)
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
		return
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
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
		fx = { att = att, emitters = auraEmitters(att), hl = hl, hand = handFx(model, hrp), t0 = os.clock(), remote = remote }
		auras[model] = fx
	end
	applyEnergy(fx, energy or 0)
end

-- spin the orb rings and grow remote charges
------------------------------------------------------------------------------------------
-- role abilities
------------------------------------------------------------------------------------------

local walls = {} -- entityId -> { part, untilT, side }
local statusFx = {} -- model -> kind -> { att, em, hl }
local sunSeen = {} -- model -> the Sunrise level last shown
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
		if mods and mods.AudioController then
			mods.AudioController.play("Block", { volume = 0.7 })
		end
	elseif ability == "Turnabout" then
		-- armed: a swirl at the setter's feet (the aura scan keeps a glow on while it lasts)
		local pos = hrp.Position
		floorRing(pos, def.Color, 4.5, 0.45)
		ringFx(pos + Vector3.new(0, 1, 0), def.Color, 2, 9, 0.35, 6)
		VFXController.popup(pos + Vector3.new(0, 6, 0), "Turnabout!", def.Color, 1.1)
		if mods and mods.AudioController then
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
		if mods and mods.AudioController then
			mods.AudioController.play("RallyCry", { volume = 0.8 })
		end
	end
end

-- Counter Edge: blades burst out of the receiver in the play plane, hang for a beat and slide
-- back into the body (the spike's force goes into the meter, not the guard).
local function counterBlades(model, color, count)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local from = hrp.Position + Vector3.new(0, 0.6, 0)
	for i = 1, count do
		local p = take(Enum.PartType.Block)
		p.Color = color
		local a = (i / count) * math.pi * 2 + math.random() * 0.35
		local dir = Vector3.new((math.random() - 0.5) * 0.3, math.sin(a), math.cos(a)).Unit
		local dist = 3.2 + math.random() * 1.8
		p.Size = Vector3.new(0.1, 0.4, 2.6)
		p.CFrame = CFrame.lookAt(from + dir * 0.6, from + dir * 2)
		p.Transparency = 0.05
		local out = TweenService:Create(p, TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(from + dir * dist, from + dir * (dist + 1)),
		})
		out.Completed:Connect(function()
			task.delay(0.14, function()
				-- back into wherever the body is now
				local c = (hrp.Parent and hrp.Position or from) + Vector3.new(0, 0.6, 0)
				local back = TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.lookAt(c + dir * 0.3, c + dir * 1.3),
					Size = Vector3.new(0.05, 0.2, 1.1),
					Transparency = 0.7,
				})
				back.Completed:Connect(function()
					release(p)
				end)
				back:Play()
			end)
		end)
		out:Play()
	end
end

-- Counter Edge released: blades fly along the spike.
local function bladeVolley(pos, dir, color)
	for _ = 1, 7 do
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
	burst(pos, color, 5, 0.3)
	burst(pos, Color3.fromRGB(255, 220, 255), 2.4, 0.18)
	ringFx(pos, color, 2, 16, 0.4, 8)
	starburst(pos, color, 12, 14, 0.3)
	emit(fireEmitter, pos, 50, color)
	emit(sparkEmitter, pos, 30, Color3.fromRGB(255, 200, 255))
	shards(pos, color, 14, 60)
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
				local em = makeEmitter(Assets.Images.Fire, {
					LightEmission = 0.8,
					Lifetime = NumberRange.new(0.3, 0.6),
					Speed = NumberRange.new(2, 5),
					SpreadAngle = Vector2.new(25, 25),
					EmissionDirection = Enum.NormalId.Top,
					Color = ColorSequence.new(st.fire[1], st.fire[2]),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, st.size or 2.2), NumberSequenceKeypoint.new(1, 0) }),
					Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
				})
				em.Enabled = true
				em.Parent = att
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
				fx = { att = att, em = em, hl = hl }
				list[kind] = fx
			end
			if fx then
				fx.em.Rate = st.rate * level
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

local function updateAuras(dt)
	updateAbilityFx(dt)
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
		f.Size = UDim2.new(1.2, 0, 0, (i == 2 or i == 3) and 5 or 2)
		f.BackgroundColor3 = (i == 2 or i == 3) and color or WHITE
		f.BackgroundTransparency = 0.05
		f.Rotation = (math.random() - 0.5) * 2
		TweenService:Create(f, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
			Size = UDim2.new(1.2, 0, 0, 1),
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
	-- a shield: a rounded top plate over a point (a square turned 45 degrees)
	local top = Instance.new("Frame")
	top.BackgroundColor3 = color
	top.BorderSizePixel = 0
	top.Size = UDim2.fromOffset(40, 28)
	top.Position = UDim2.fromOffset(3, 2)
	top.Parent = root
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = top
	local point = Instance.new("Frame")
	point.BackgroundColor3 = color
	point.BorderSizePixel = 0
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Size = UDim2.fromOffset(28, 28)
	point.Position = UDim2.fromOffset(23, 30)
	point.Rotation = 45
	point.Parent = root
	local shine = Instance.new("Frame")
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.3
	shine.BorderSizePixel = 0
	shine.Size = UDim2.fromOffset(6, 30)
	shine.Position = UDim2.fromOffset(20, 6)
	shine.ZIndex = 2
	shine.Parent = root
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0) }):Play()
	task.delay(0.6, function()
		for _, f in ipairs({ top, point, shine }) do
			TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
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
	if meta.adrenaline then
		VFXController.popup(pos + Vector3.new(0, 3, 0), "Adrenaline!", Config.Abilities.Adrenaline.Color, 0.8)
	end
	if ht == "Set" and meta.charged then
		emit(sparkEmitter, pos, 24, chain)
		ringFx(pos, chain, 1, 6, 0.3, 5)
	end
	if ht == "Set" and meta.vectorSet then
		ringFx(pos, VECTOR, 1, 6, 0.35, 5)
		emit(sparkEmitter, pos, 14, VECTOR)
	end
	if meta.turnabout then
		local tcol = Config.Abilities.Turnabout.Color
		ringFx(pos, tcol, 1.5, 10, 0.35, 6)
		starburst(pos, tcol, 8, 12, 0.3)
		VFXController.popup(pos + Vector3.new(0, 2, 0), "Turnabout!", tcol, 1.1)
	end
	if meta.counterGain then
		counterBlades(model, COUNTER, 8)
		VFXController.popup(pos + Vector3.new(0, 2.2, 0), "Counter +" .. math.floor(meta.counterGain + 0.5), COUNTER, 0.85)
		if close and mods.AudioController then
			mods.AudioController.play("Blades", { volume = 0.7 })
		end
	end

	if ht == "Spike" or ht == "JumpServe" then
		local heavy = kmh >= 120
		local vdir = seg.v.Magnitude > 0 and seg.v.Unit or Vector3.new(0, -1, dirZ)
		-- every attack: a reticle snapping onto the ball and dark debris streaks off the contact
		ringFx(pos, WHITE, 7, 2.2, 0.14, 3)
		shards(pos, Color3.fromRGB(24, 22, 30), heavy and 12 or 6, heavy and 75 or 50)
		if meta.vector then
			-- Vector Set: the boost the spike's angle earned
			local boost = meta.vectorBoost or 0
			ringFx(pos, VECTOR, 1.5, 7 + 20 * boost, 0.35, 6)
			VFXController.popup(pos + Vector3.new(0, 2.6, 0), string.format("+%.1f%%", boost * 100), VECTOR, 0.9 + 2 * boost)
		end
		if meta.counterRelease then
			bladeVolley(pos, vdir, COUNTER)
			VFXController.popup(pos + Vector3.new(0, 4.2, 0), string.format("Counter Edge +%d%%", math.floor(Config.Abilities.Counter.MaxBoost * meta.counterRelease + 0.5)), COUNTER, 1)
			if close and mods.AudioController then
				mods.AudioController.play("Blades", { volume = 0.8, speed = 1.2 })
			end
		end
		if heavy or meta.thunder or meta.energy then
			boomRings(snap.path, meta.thunder and THUNDER or (meta.energy and AZURE or WHITE), meta.thunder and 3 or 2)
			if close then
				VFXController.neonStreaks(pos, meta.thunder and THUNDER or (meta.energy and AZURE or HOT))
			end
		end
		if meta.thunder then
			if not toolboxFx("ThunderImpact", pos) then
				starburst(pos, THUNDER, 11, 14, 0.3)
				ringFx(pos, THUNDER, 2, 14, 0.35, 8)
				for _ = 1, 4 do
					local d = (vdir + Vector3.new(0, (math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.2)).Unit
					bolt(pos, d, 7 + math.random() * 5, THUNDER)
				end
				emit(sparkEmitter, pos, 40, THUNDER)
			end
			thunderPath(snap.path)
			if close then
				VFXController.impactFrame(meta.id, THUNDER)
				VFXController.speedLines(0.5, Color3.fromRGB(255, 244, 180), dirZ)
				shaker.shake(0.75)
				shaker.kick(-8)
			end
		elseif meta.energy then
			local e = math.min(meta.energy, 1)
			if not toolboxFx("AzureImpact", pos) then
				starburst(pos, AZURE, 7 + 6 * e, 12, 0.3)
				ringFx(pos, AZURE, 2, 8 + 8 * e, 0.35, 7)
				ringFx(pos, WHITE, 1, 5 + 4 * e, 0.25, 4)
				emit(fireEmitter, pos, math.floor(10 + 25 * e), AZURE)
			end
			if meta.pierce then
				VFXController.popup(pos, "Pierce!", AZURE, 1.1)
			end
			if meta.overcharge then
				VFXController.popup(pos, "Overcharged!", HOT, 0.9)
			end
			if close and e >= 0.9 then
				VFXController.impactFrame(meta.id, Color3.fromRGB(40, 120, 255))
				shaker.shake(0.7)
				shaker.kick(-7)
			elseif close then
				shaker.shake(0.4)
			end
			if close then
				VFXController.speedLines(0.35 + 0.2 * e, Color3.fromRGB(190, 240, 255), dirZ)
			end
		else
			-- the attacker's spike colour (a V Points unlock) replaces the default hot pink
			local tint = Spins.tint(Spins.equipped(model, "Color"))
			local accent = tint or HOT
			if not toolboxFx(heavy and "PerfectImpact" or "SpikeImpact", pos) then
				starburst(pos, tint or WHITE, heavy and 10 or 6, heavy and 14 or 10, 0.26)
				ringFx(pos, WHITE, 1.5, heavy and 11 or 7, 0.3, 6)
				if heavy or tint then
					ringFx(pos, accent, 1, heavy and 8 or 6, 0.3, 5)
					burst(pos, accent, heavy and 2.8 or 1.8, 0.18)
				end
				emit(sparkEmitter, pos, heavy and 26 or 12, (heavy or tint) and accent or WHITE)
			end
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
		return
	end

	if ht == "Block" then
		local outcome = meta.outcome
		if meta.ironWall then
			local wc = Config.Abilities.IronWall.Color
			starburst(pos, wc, 13, 16, 0.3)
			ringFx(pos, wc, 2, 16, 0.4, 9)
			shards(pos, wc, 14, 55)
		end
		if outcome == "Stuff" then
			if not toolboxFx("BlockImpact", pos) then
				starburst(pos, tc, 10, 12, 0.3)
				ringFx(pos, tc, 2, 12, 0.35, 8)
				shards(pos, tc, 10, 45)
				emit(sparkEmitter, pos, 30, tc)
			end
			VFXController.popup(pos, "Stuff!", tc, 1.2)
			VFXController.impactFrame(meta.id, tc)
			shaker.shake(0.5)
			shaker.kick(-5)
		else
			ringFx(pos, tc, 1, 5, 0.25, 5)
			emit(sparkEmitter, pos, 8, tc)
			if outcome == "Soft" then
				VFXController.popup(pos, "Soft block", UI.Chalk, 0.7)
			end
		end
		return
	end

	if ht == "Bump" or ht == "Set" or ht == "Free" or ht == "Feint" or ht == "Overhand" or ht == "Underhand" then
		if not toolboxFx("ReceiveImpact", pos) then
			ringFx(pos, meta.perfect and UI.Spark or WHITE, 1, 4.5, 0.22, 4)
		end
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
			emit(dustEmitter, Vector3.new(pos.X, 0.4, pos.Z), 14)
		end
		if mine then
			shaker.shake(meta.drain and math.clamp(meta.drain / 40, 0.05, 0.3) or 0.05)
		end
	end
end

------------------------------------------------------------------------------------------
-- score effects (V Points unlocks): where an attack lands for a point
------------------------------------------------------------------------------------------

local SCORING = { Spike = true, JumpServe = true, Overhand = true, Feint = true, Block = true }

local function light(pos, color, brightness, range, duration)
	local p = take(Enum.PartType.Block)
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(pos)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = p
	local tween = TweenService:Create(l, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 })
	tween:Play()
	tween.Completed:Connect(function()
		l:Destroy()
		release(p)
	end)
end

local function fireExplosion(pos, scale, tint)
	local s = scale or 1
	burst(pos + Vector3.new(0, 1.5 * s, 0), Color3.fromRGB(255, 200, 80), 4.5 * s, 0.3)
	burst(pos + Vector3.new(0, 1 * s, 0), Color3.fromRGB(255, 90, 30), 7 * s, 0.45)
	floorRing(pos, Color3.fromRGB(40, 20, 16), 7 * s, 1.1)
	floorRing(pos, tint or Color3.fromRGB(255, 120, 40), 11 * s, 0.5)
	ringFx(pos + Vector3.new(0, 2, 0), Color3.fromRGB(255, 170, 60), 2, 14 * s, 0.4, 8)
	emit(fireEmitter, pos + Vector3.new(0, 1, 0), math.floor(60 * s), Color3.fromRGB(255, 150, 50))
	emit(fireEmitter, pos + Vector3.new(0, 2.5, 0), math.floor(30 * s), tint or Color3.fromRGB(255, 70, 30))
	emit(dustEmitter, pos, math.floor(24 * s))
	shards(pos + Vector3.new(0, 0.6, 0), Color3.fromRGB(255, 190, 90), math.floor(12 * s), 45)
	light(pos + Vector3.new(0, 3, 0), Color3.fromRGB(255, 140, 60), 6, 30 * s, 0.6)
end

local function meteorStrike(pos, dirZ, tint)
	local rock = take(Enum.PartType.Ball)
	rock.Color = Color3.fromRGB(255, 120, 40)
	rock.Size = Vector3.new(3.4, 3.4, 3.4)
	rock.Transparency = 0
	local from = pos + Vector3.new(-4, 70, -dirZ * 38)
	rock.CFrame = CFrame.new(from)
	local streaked = 0
	local conn
	local t0 = os.clock()
	local fall = 0.34
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / fall, 0, 1)
		local p = from:Lerp(pos + Vector3.new(0, 1, 0), a * a)
		rock.CFrame = CFrame.new(p)
		streaked = streaked + 1
		if streaked % 2 == 0 then
			emit(fireEmitter, p, 6, tint or Color3.fromRGB(255, 110, 40))
			burst(p, Color3.fromRGB(255, 200, 90), 1.6, 0.2)
		end
		if a >= 1 then
			conn:Disconnect()
			release(rock)
			fireExplosion(pos, 1.35, tint)
			starburst(pos + Vector3.new(0, 2, 0), Color3.fromRGB(255, 220, 120), 14, 14, 0.35)
			shards(pos + Vector3.new(0, 0.5, 0), Color3.fromRGB(70, 50, 40), 16, 60)
			if near(pos) then
				mods.CameraController.shake(0.8)
				mods.CameraController.kick(-6)
				VFXController.flash(0.25, 0.2)
			end
		end
	end)
end

local function thunderbolt(pos, tint)
	local color = tint or THUNDER
	local top = pos + Vector3.new(-1, 80, 0)
	local prev = top
	local segs = 9
	for i = 1, segs do
		local along = top:Lerp(pos, i / segs)
		local nextP = i == segs and pos or along + Vector3.new(0, 0, (math.random() - 0.5) * 7)
		bolt(prev, (nextP - prev).Unit, (nextP - prev).Magnitude, color)
		prev = nextP
	end
	bolt(pos + Vector3.new(0, 1, 0), Vector3.new(0, 0.3, 1).Unit, 8, color)
	bolt(pos + Vector3.new(0, 1, 0), Vector3.new(0, 0.3, -1).Unit, 8, color)
	starburst(pos + Vector3.new(0, 2, 0), color, 13, 16, 0.3)
	ringFx(pos + Vector3.new(0, 1, 0), color, 2, 16, 0.4, 8)
	floorRing(pos, color, 12, 0.5)
	emit(sparkEmitter, pos + Vector3.new(0, 1, 0), 50, color)
	light(pos + Vector3.new(0, 6, 0), color, 8, 40, 0.5)
	if near(pos) then
		VFXController.flash(0.4, 0.25)
		mods.CameraController.shake(0.6)
	end
end

local function shockwave(pos, tint)
	local color = tint or WHITE
	floorRing(pos, color, 14, 0.5)
	floorRing(pos, WHITE, 8, 0.35)
	ringFx(pos + Vector3.new(0, 2, 0), color, 2, 16, 0.4, 6)
	emit(dustEmitter, pos, 30)
	if near(pos) then
		mods.CameraController.shake(0.4)
	end
end

-- The attack (or stuff block) that just landed in: the scorer's effect at the spot.
local function scoreEffect(pos, meta)
	if not meta or not SCORING[meta.hitType] or not Court.inBounds(pos) then
		return false
	end
	local side = State.sideOfEntity(meta.id)
	if not side or pos.Z * side > 0 then
		return false -- landed on the hitter's own side: not their point
	end
	local model = Util.modelOf(meta.id)
	local effect = Spins.equipped(model, "Effect").Key
	local tint = Spins.tint(Spins.equipped(model, "Color"))
	if effect == "Fire" then
		fireExplosion(pos, 1, tint)
	elseif effect == "Meteor" then
		meteorStrike(pos, -side, tint)
	elseif effect == "Thunderbolt" then
		thunderbolt(pos, tint)
	elseif effect == "Shockwave" then
		shockwave(pos, tint)
	else
		return false -- Dust: the normal floor impact
	end
	return true
end

-- A score effect anywhere, outside a match (the Locker's preview): the effect's key, the spike
-- colour's tint (or nil) and the direction the attack travelled along z.
function VFXController.previewEffect(pos, effect, tint, dirZ)
	if effect == "Fire" then
		fireExplosion(pos, 1, tint)
	elseif effect == "Meteor" then
		meteorStrike(pos, dirZ or -1, tint)
	elseif effect == "Thunderbolt" then
		thunderbolt(pos, tint)
	elseif effect == "Shockwave" then
		shockwave(pos, tint)
	else
		floorRing(pos, tint or WHITE, 6, 0.35)
		emit(dustEmitter, pos, 24)
	end
end

local function onBallEvent(kind, ev, meta)
	if kind == "Land" then
		if ev.kind ~= "Floor" then
			return
		end
		local pos = Vector3.new(0, 0.2, ev.pos.Z)
		scoreEffect(pos, meta)
		local speed = ev.vel.Magnitude
		local hard = speed > 45
		if not toolboxFx("FloorImpact", pos) then
			floorRing(pos, WHITE, hard and 8 or 3.5, hard and 0.4 or 0.3)
			emit(dustEmitter, pos, hard and 28 or 10)
			if hard then
				local c = WHITE
				if meta and meta.thunder then
					c = THUNDER
				elseif meta and meta.energy then
					c = AZURE
				end
				starburst(pos + Vector3.new(0, 0.8, 0), c, 8, 10, 0.3)
				shards(pos + Vector3.new(0, 0.4, 0), Color3.fromRGB(255, 220, 170), 8, 30)
			end
		end
		if hard then
			mods.CameraController.shake(0.35)
		end
	elseif kind == "Net" then
		local pos = Vector3.new(0, ev.pos.Y, 0)
		if not toolboxFx("NetImpact", pos) then
			ringFx(pos, WHITE, 1, 4, 0.3, 4)
		end
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

local function onBreak(a)
	local model = a.id and Util.modelOf(a.id)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	local pos = hrp and hrp.Position + Vector3.new(0, 2, 0) or Vector3.new(0, 3, 0)
	if not toolboxFx("GuardBreak", pos) then
		shards(pos, Color3.fromRGB(210, 235, 255), 16, 50)
		ringFx(pos, HOT, 2, 12, 0.4, 8)
	end
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

	emitterHolder = Instance.new("Part")
	emitterHolder.Name = "Emitters"
	emitterHolder.Anchored = true
	emitterHolder.CanCollide = false
	emitterHolder.CanQuery = false
	emitterHolder.CanTouch = false
	emitterHolder.Transparency = 1
	emitterHolder.Size = Vector3.new(0.2, 0.2, 0.2)
	emitterHolder.Parent = fxFolder

	sparkEmitter = makeEmitter(Assets.Images.Spark, {
		LightEmission = 1,
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(18, 42),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	})
	dustEmitter = makeEmitter(Assets.Images.Smoke, {
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(180, 10),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 4,
		Acceleration = Vector3.new(0, 2, 0),
		Color = ColorSequence.new(Color3.fromRGB(230, 214, 190)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
	})
	fireEmitter = makeEmitter(Assets.Images.Fire, {
		LightEmission = 1,
		Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(8, 20),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	})

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
		elseif a.kind == "Point" and a.landing and (a.reason == "Spike" or a.reason == "Ace" or a.reason == "Stuff" or a.reason == "Break") then
			emit(sparkEmitter, a.landing + Vector3.new(0, 1, 0), 24, teamColor(a.winner))
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
		elseif kind == "Slide" and model then
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hrp then
				emit(dustEmitter, Vector3.new(hrp.Position.X, 0.4, hrp.Position.Z), 12)
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
