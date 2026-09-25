-- Client ball: plays back the server's analytic path against the shared clock, applies local
-- prediction for your own hits, reconciles smoothly, and draws the ball, its ribbon trail (thick
-- and coloured by the attack), the dotted arc of a set, the drop shadow and the landing ellipse.
-- It also fires timeline events (net contact, touchdown) for VFX and audio.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local BallPhysics = require(Shared.BallPhysics)
local Spins = require(Shared.Spins)
local State = require(script.Parent.State)

local BallRenderer = {}

local R = Config.Ball.Radius
local G = Config.Ball.Gravity
local HIDDEN = Vector3.new(0, -500, 0)
local FLAT = CFrame.Angles(0, 0, math.rad(90))

local cur = { seq = 0, state = "Idle", path = nil, holder = nil, meta = nil, touch = { count = 0 } }
local predicted = nil -- { seq = n, prev = snapshot before our prediction }
local blendOffset = Vector3.zero
local blendStart = 0
local renderPos = HIDDEN
local renderVel = Vector3.zero
local spinCF = CFrame.identity
local spinFrames = 0
local fired = {}
local bounce = nil

local folder, ballRoot, trailPart, trail, core, aura, glow, shadow, markerRing, markerDot
local sparkles, sparkleOn = nil, false
-- the attacker's equipped trail (V Points unlock): lightning drops jagged segments behind the ball
local lightningOn, lightningColor = false, Color3.new(1, 1, 1)
local chargedHl = nil -- red glow on a Chain Reaction (charged) ball
local chargedOn = false
local pulseRate = 14 -- how fast a glowing ball pulses (a Vector set breathes slower)
local VECTOR = Config.Abilities.Vector.Color
local bolts = {}
local boltIndex, lastBoltAt, lastBoltPos = 0, 0, nil
local BOLT_COUNT = 28
local a0, a1, c0, c1
local dots = {}
local dotIndex = 0
local lastDotAt = 0
local dotsAliveUntil = 0
local DOT_COUNT = 48
local guideDots = {} -- the dotted toss path
local GUIDE_COUNT = 32

------------------------------------------------------------------------------------------
-- visuals
------------------------------------------------------------------------------------------

local function basicPart(name, shape, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function weldTo(root, part)
	part.Anchored = false
	part.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = part
	w.Parent = part
end

-- The ball's look, rebuilt whenever a Toolbox ball arrives. In order of preference:
-- ReplicatedStorage.ToolboxAssets.Models.Volleyball, the uploaded mesh in Assets.Mesh, then the
-- procedural three-colour ball.
local function toolboxBallModel()
	local template = Assets.toolbox("Models.Volleyball")
	if not template then
		return nil
	end
	local clone = Assets.sanitize(template:Clone())
	if clone:IsA("Model") or clone:IsA("BasePart") then
		return clone
	end
	-- a Tool, Accessory or Folder: keep its parts in a Model
	local model = Instance.new("Model")
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") and not d.Parent:IsA("BasePart") then
			d.Parent = model
		end
	end
	clone:Destroy()
	if not model:FindFirstChildWhichIsA("BasePart", true) then
		model:Destroy()
		return nil
	end
	return model
end

-- Scale a Toolbox ball to the gameplay ball, centre its bounding box on the (origin-parked)
-- ball root and weld every part to it.
local function fitToolboxBall(clone)
	local parts = {}
	if clone:IsA("Model") then
		local _, size = clone:GetBoundingBox()
		local scale = (R * 2) / math.max(size.X, size.Y, size.Z, 0.01)
		clone:ScaleTo(clone:GetScale() * scale)
		local box = clone:GetBoundingBox()
		clone:PivotTo(box:Inverse() * clone:GetPivot())
	else
		local size = clone.Size
		local scale = (R * 2) / math.max(size.X, size.Y, size.Z, 0.01)
		clone.Size = size * scale
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("SpecialMesh") then
				d.Scale = d.Scale * scale
			end
		end
		clone.CFrame = CFrame.new()
		table.insert(parts, clone)
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	clone:SetAttribute("BallLook", true)
	clone.Parent = ballRoot
	for _, p in ipairs(parts) do
		weldTo(ballRoot, p)
	end
end

local function applyBallLook()
	for _, c in ipairs(ballRoot:GetChildren()) do
		if c:GetAttribute("BallLook") then
			c:Destroy()
		end
	end
	ballRoot.Transparency = 0
	local home = ballRoot.CFrame
	ballRoot.CFrame = CFrame.new()

	local clone = toolboxBallModel()
	local meshId = Assets.id(Assets.Mesh.BallMesh)
	if clone then
		local ok, err = pcall(fitToolboxBall, clone)
		if not ok then
			warn("[SpikeRush] Toolbox volleyball could not be used: " .. tostring(err))
			clone:Destroy()
			clone = nil
		end
	end
	if clone then
		ballRoot.Transparency = 1
	elseif meshId then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = meshId
		mesh.TextureId = Assets.id(Assets.Mesh.BallTexture) or ""
		local s = R / (Assets.Mesh.BallMeshUnitRadius or 1)
		mesh.Scale = Vector3.new(s, s, s)
		mesh:SetAttribute("BallLook", true)
		mesh.Parent = ballRoot
	else
		-- Procedural three-colour ball: two slightly larger discs read as panel stripes and
		-- make spin clearly visible.
		local yellow = basicPart("BandA", Enum.PartType.Cylinder, Vector3.new(R * 0.62, R * 2.04, R * 2.04), Color3.fromRGB(255, 205, 40))
		yellow.CFrame = ballRoot.CFrame
		yellow:SetAttribute("BallLook", true)
		yellow.Parent = ballRoot
		weldTo(ballRoot, yellow)
		local blue = basicPart("BandB", Enum.PartType.Cylinder, Vector3.new(R * 0.62, R * 2.04, R * 2.04), Color3.fromRGB(34, 86, 196))
		blue.CFrame = ballRoot.CFrame * CFrame.Angles(0, math.rad(90), 0)
		blue:SetAttribute("BallLook", true)
		blue.Parent = ballRoot
		weldTo(ballRoot, blue)
	end
	ballRoot.CFrame = home
end

-- A Toolbox ball can land in ReplicatedStorage after the client started (ToolboxService loads
-- ids at runtime), so watch for it.
local function watchToolboxBall()
	task.spawn(function()
		local root = ReplicatedStorage:WaitForChild("ToolboxAssets", 30)
		local models = root and root:WaitForChild("Models", 10)
		if not models then
			return
		end
		models.ChildAdded:Connect(function(c)
			if c.Name == "Volleyball" then
				task.defer(applyBallLook)
			end
		end)
		if models:FindFirstChild("Volleyball") and ballRoot.Transparency < 1 then
			applyBallLook()
		end
	end)
end

local function buildVisuals()
	folder = Instance.new("Folder")
	folder.Name = "SpikeRushBall"
	folder.Parent = workspace

	ballRoot = basicPart("Ball", Enum.PartType.Ball, Vector3.new(R * 2, R * 2, R * 2), Color3.fromRGB(250, 250, 244))
	ballRoot.Parent = folder

	applyBallLook()

	trailPart = basicPart("TrailAnchor", Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1))
	trailPart.Transparency = 1
	trailPart.Parent = folder
	-- ribbons lie in the play plane (perpendicular to the flight), so they face the side camera
	local function ribbon(width, zOffset)
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(zOffset, width / 2, 0)
		top.Parent = trailPart
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(zOffset, -width / 2, 0)
		bottom.Parent = trailPart
		local t = Instance.new("Trail")
		t.Attachment0 = top
		t.Attachment1 = bottom
		t.Lifetime = 0.2
		t.MinLength = 0.02
		t.FaceCamera = false
		t.LightEmission = 0.6
		t.LightInfluence = 0
		t.Enabled = false
		t.Parent = trailPart
		return t, top, bottom
	end
	trail, a0, a1 = ribbon(R * 1.6, 0)
	core, c0, c1 = ribbon(R * 0.5, -0.05)
	core.Color = ColorSequence.new(Color3.new(1, 1, 1))

	-- pooled dots for the dotted arc of a set
	for i = 1, DOT_COUNT do
		local d = basicPart("Dot", Enum.PartType.Ball, Vector3.new(0.42, 0.42, 0.42), Config.UI.Chalk, Enum.Material.Neon)
		d.Transparency = 1
		d.Parent = folder
		dots[i] = { part = d, born = -10 }
	end

	aura = Instance.new("ParticleEmitter")
	aura.Texture = Assets.Images.Fire
	aura.Rate = 90
	aura.Lifetime = NumberRange.new(0.18, 0.32)
	aura.Speed = NumberRange.new(0.5, 2)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, R * 2.4), NumberSequenceKeypoint.new(1, 0) })
	aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	aura.LightEmission = 1
	aura.LightInfluence = 0
	aura.Enabled = false
	aura.Parent = trailPart

	-- stars shed along an attack's ribbon
	sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = Assets.Images.Spark
	sparkles.Rate = 80
	sparkles.Lifetime = NumberRange.new(0.3, 0.6)
	sparkles.Speed = NumberRange.new(0.5, 2.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.RotSpeed = NumberRange.new(-180, 180)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Enabled = false
	sparkles.Parent = trailPart

	chargedHl = Instance.new("Highlight")
	chargedHl.FillColor = Config.Abilities.ChainReaction.Color
	chargedHl.OutlineColor = Color3.fromRGB(255, 220, 200)
	chargedHl.FillTransparency = 0.45
	chargedHl.OutlineTransparency = 0
	chargedHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	chargedHl.Enabled = false
	chargedHl.Adornee = ballRoot
	chargedHl.Parent = folder

	glow = Instance.new("PointLight")
	glow.Range = 14
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = trailPart

	for i = 1, BOLT_COUNT do
		local b = basicPart("Bolt", Enum.PartType.Block, Vector3.new(0.2, 0.2, 1), Color3.new(1, 1, 1), Enum.Material.Neon)
		b.Transparency = 1
		b.Parent = folder
		bolts[i] = { part = b, born = -10 }
	end

	shadow = basicPart("Shadow", Enum.PartType.Cylinder, Vector3.new(0.04, R * 2.2, R * 2.2), Color3.new(0, 0, 0))
	shadow.Transparency = 0.4
	shadow.Parent = folder

	markerRing = basicPart("LandingRing", Enum.PartType.Cylinder, Vector3.new(0.03, 7, 7), Config.UI.Chalk, Enum.Material.Neon)
	markerRing.Transparency = 1
	markerRing.Parent = folder
	markerDot = basicPart("LandingCore", Enum.PartType.Cylinder, Vector3.new(0.035, 5.6, 5.6), Color3.fromRGB(22, 24, 36), Enum.Material.SmoothPlastic)
	markerDot.Transparency = 1
	markerDot.Parent = folder
end

-- Trail style follows the last touch: lightning yellow, dragon cyan, hot red for big spikes.
local function setWidth(w, cw)
	a0.Position = Vector3.new(0, w / 2, 0)
	a1.Position = Vector3.new(0, -w / 2, 0)
	c0.Position = Vector3.new(-0.05, cw / 2, 0)
	c1.Position = Vector3.new(-0.05, -cw / 2, 0)
end

local function fade(tail)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, tail), NumberSequenceKeypoint.new(1, 1) })
end

local function applyStyle(meta)
	local ht = meta and meta.hitType
	local kmh = (meta and meta.kmh) or 0
	local teamColor = Config.UI.Chalk
	if meta and meta.team and Config.Teams[meta.team] then
		teamColor = Config.Teams[meta.team].Color
	end
	local attack = ht == "Spike" or ht == "JumpServe"
	-- the attacker's unlocks: spike colour and trail
	local model = attack and meta.id and Util.modelOf(meta.id) or nil
	local colorItem = Spins.equipped(model, "Color")
	local tintSeq = attack and Spins.tintSequence(colorItem) or nil
	local tint = attack and Spins.tint(colorItem) or nil
	local trailKey = attack and Spins.equipped(model, "Trail").Key or "Ribbon"
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.6) })
	core.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	aura.Enabled = false
	aura.Rate = 90
	glow.Brightness = 0
	local vectorSet = meta ~= nil and meta.vectorSet == true and ht == "Set"
	chargedOn = meta ~= nil and (meta.charged == true or meta.reaction == true or vectorSet)
	pulseRate = vectorSet and 7 or 14
	if chargedHl then
		chargedHl.Enabled = chargedOn
		chargedHl.FillColor = vectorSet and VECTOR or Config.Abilities.ChainReaction.Color
	end
	core.Enabled = false
	sparkleOn = false
	sparkles.Rate = 80
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	lightningOn = false
	-- thick, nearly solid ribbons like The Spike's: a Thunder spike paints the whole court
	if attack and meta.thunder then
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 232, 40), Color3.fromRGB(255, 246, 150))
		trail.Transparency = fade(0.05)
		trail.Lifetime = 0.9
		trail.LightEmission = 1
		setWidth(R * 4.2, R * 1.2)
		core.Lifetime = 0.5
		aura.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120))
		aura.Enabled = true
		glow.Color = Color3.fromRGB(255, 230, 90)
		glow.Brightness = 5
		sparkleOn = true
		sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 250, 200))
	elseif attack and meta.energy then
		local e = meta.energy
		trail.Color = ColorSequence.new(Color3.fromRGB(80, 230, 255), Color3.fromRGB(30, 90, 255))
		trail.Transparency = fade(0.1)
		trail.Lifetime = 0.5 + 0.3 * e
		trail.LightEmission = 1
		setWidth(R * (2.4 + 1.6 * e), R * 0.9)
		core.Lifetime = 0.35
		aura.Color = ColorSequence.new(Color3.fromRGB(120, 240, 255), Color3.fromRGB(40, 110, 255))
		aura.Enabled = e > 0.5
		glow.Color = Color3.fromRGB(80, 200, 255)
		glow.Brightness = 2 + 3 * e
		sparkleOn = true
		sparkles.Color = ColorSequence.new(Color3.fromRGB(200, 250, 255))
	elseif attack and kmh >= 120 then
		-- hot pink into red, with stars, like The Spike's hardest normal spikes
		trail.Color = tintSeq or ColorSequence.new(Color3.fromRGB(255, 40, 140), Color3.fromRGB(255, 90, 70))
		trail.Transparency = fade(0.12)
		trail.Lifetime = 0.6
		trail.LightEmission = 0.9
		setWidth(R * 3.2, R * 0.8)
		core.Lifetime = 0.3
		glow.Color = tint or Color3.fromRGB(255, 90, 140)
		glow.Brightness = 2
		sparkleOn = true
		sparkles.Color = ColorSequence.new(tint and tint:Lerp(Color3.new(1, 1, 1), 0.6) or Color3.fromRGB(255, 220, 240))
	elseif attack then
		trail.Color = tintSeq or ColorSequence.new(Color3.fromRGB(255, 70, 90), teamColor)
		trail.Transparency = fade(0.2)
		trail.Lifetime = 0.45
		trail.LightEmission = 0.8
		setWidth(R * 2.3, R * 0.6)
		core.Lifetime = 0.24
	elseif ht == "Set" then
		-- sets are drawn as a dotted arc instead
		trail.Lifetime = 0.05
		setWidth(0.05, 0.05)
		if meta.charged then
			-- a Chain Reaction set: the ball glows red and throws sparks, easy to spot
			local red = Config.Abilities.ChainReaction.Color
			aura.Color = ColorSequence.new(Color3.fromRGB(255, 190, 150), red)
			aura.Enabled = true
			glow.Color = red
			glow.Brightness = 5
			sparkleOn = true
			sparkles.Rate = 120
			sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 120, 120))
		elseif meta.vectorSet then
			-- a Vector set: the ball pulses violet (spike it steep for the boost)
			aura.Color = ColorSequence.new(Color3.fromRGB(235, 215, 255), VECTOR)
			aura.Enabled = true
			glow.Color = VECTOR
			glow.Brightness = 4
			sparkleOn = true
			sparkles.Rate = 60
			sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), VECTOR)
		end
	else
		trail.Color = ColorSequence.new(Config.UI.Chalk)
		trail.Transparency = fade(0.55)
		trail.Lifetime = 0.22
		trail.LightEmission = 0.4
		setWidth(R * 1.1, 0.05)
	end
	core.Enabled = attack
	if not attack then
		core.Enabled = false
		return
	end
	if meta.reaction then
		-- off a charged set: the ball burns red
		local c = Config.Abilities.ChainReaction.Color
		trail.Color = ColorSequence.new(c, Color3.fromRGB(255, 170, 60))
		aura.Color = ColorSequence.new(Color3.fromRGB(255, 220, 160), c)
		aura.Enabled = true
		glow.Color = c
		glow.Brightness = math.max(glow.Brightness, 4)
		sparkleOn = true
		sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 210))
	end
	local accent = tint or (meta.thunder and Color3.fromRGB(255, 232, 40)) or (meta.energy and Color3.fromRGB(80, 230, 255)) or Color3.fromRGB(255, 90, 110)
	if trailKey == "Comet" then
		-- a long, wide tail tapering to a point
		trail.Lifetime = trail.Lifetime * 1.7
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.35), NumberSequenceKeypoint.new(1, 0.05) })
		core.Lifetime = core.Lifetime * 1.5
	elseif trailKey == "Sparkle" then
		sparkleOn = true
		sparkles.Rate = 140
		sparkles.Color = ColorSequence.new(accent:Lerp(Color3.new(1, 1, 1), 0.5))
	elseif trailKey == "Flame" then
		aura.Enabled = true
		aura.Rate = 140
		aura.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), tint or Color3.fromRGB(255, 70, 30))
		glow.Color = Color3.fromRGB(255, 140, 60)
		glow.Brightness = math.max(glow.Brightness, 3)
	elseif trailKey == "Lightning" then
		lightningOn = true
		lightningColor = accent:Lerp(Color3.new(1, 1, 1), 0.25)
		lastBoltPos = nil
	elseif trailKey == "Stardust" then
		sparkleOn = true
		sparkles.Rate = 220
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), accent)
		glow.Color = accent
		glow.Brightness = math.max(glow.Brightness, 3)
		trail.Lifetime = trail.Lifetime * 1.3
	end
end

-- Lightning trail: jagged neon segments dropped behind the ball, fading fast.
local function updateBolts(pos, live, speed)
	local clock = os.clock()
	if lightningOn and live and speed > 8 and clock - lastBoltAt > 0.03 then
		lastBoltAt = clock
		local jag = Vector3.new((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 2.4, (math.random() - 0.5) * 1.2)
		local p = pos + jag
		if lastBoltPos and (p - lastBoltPos).Magnitude < 12 then
			boltIndex = boltIndex % BOLT_COUNT + 1
			local b = bolts[boltIndex]
			local len = (p - lastBoltPos).Magnitude
			b.part.Size = Vector3.new(0.26, 0.26, len)
			b.part.CFrame = CFrame.lookAt((p + lastBoltPos) / 2, p)
			b.part.Color = lightningColor
			b.born = clock
		end
		lastBoltPos = p
	elseif not live then
		lastBoltPos = nil
	end
	for _, b in ipairs(bolts) do
		local age = clock - b.born
		if age < 0.3 then
			b.part.Transparency = age / 0.3
		elseif b.part.Transparency < 1 then
			b.part.Transparency = 1
		end
	end
end

------------------------------------------------------------------------------------------
-- state handling
------------------------------------------------------------------------------------------

local function snapshot()
	return { seq = cur.seq, state = cur.state, holder = cur.holder, path = cur.path, meta = cur.meta, touch = cur.touch }
end

local function adopt(snap, keepEvents)
	local oldPos = renderPos
	cur.seq = snap.seq
	cur.state = snap.state
	cur.holder = snap.holder
	cur.path = snap.path
	cur.meta = snap.meta
	cur.touch = snap.touch or { count = 0 }
	if not keepEvents then
		fired = {}
	end
	bounce = nil
	blendOffset = Vector3.zero
	if cur.state == "Flight" and cur.path and oldPos.Y > -100 then
		local newPos = BallPhysics.positionAt(cur.path, Util.now())
		local err = oldPos - newPos
		if err.Magnitude < 14 then
			blendOffset = err
			blendStart = os.clock()
		end
	end
	applyStyle(cur.meta)
end

local function onState(snap)
	if type(snap) ~= "table" then
		return
	end
	if predicted then
		if snap.seq < predicted.seq then
			return -- older than our prediction: ignore
		end
		local isEcho = snap.seq == predicted.seq and snap.meta and snap.meta.id == State.myId
		predicted = nil
		adopt(snap, isEcho)
		State.signals.Ball:Fire(snap, isEcho)
		return
	end
	if snap.seq < cur.seq then
		return
	end
	adopt(snap, false)
	State.signals.Ball:Fire(snap, false)
end

local function onReject(seq)
	if predicted and predicted.seq == seq + 1 then
		local prev = predicted.prev
		predicted = nil
		adopt(prev, false)
		State.signals.Ball:Fire(prev, true)
		State.hint("Too late!")
	end
end

-- Apply our own hit instantly. The server will echo the identical path.
function BallRenderer.predict(result, touch)
	local prev = snapshot()
	local snap = {
		seq = cur.seq + 1,
		state = "Flight",
		holder = nil,
		path = BallPhysics.buildPath(result.launch),
		meta = result.meta,
		touch = touch,
	}
	predicted = { seq = snap.seq, prev = prev }
	adopt(snap, false)
	State.signals.Ball:Fire(snap, false)
	return snap
end

------------------------------------------------------------------------------------------
-- dead ball bounces (visual only)
------------------------------------------------------------------------------------------

local function buildBounces(landing)
	local segs = {}
	local p, v, t = landing.pos, landing.vel, landing.t
	for _ = 1, 4 do
		local nv = Vector3.new(v.X * 0.62, math.abs(v.Y) * 0.45, v.Z * 0.62)
		if nv.Y < 0.8 * Config.Scale.StudsPerMeter then
			v = nv
			break
		end
		local dur = 2 * nv.Y / G
		table.insert(segs, { p = p, v = nv, t0 = t, dur = dur })
		p = p + Vector3.new(nv.X * dur, 0, nv.Z * dur)
		v = Vector3.new(nv.X, -nv.Y, nv.Z)
		t = t + dur
	end
	return { segs = segs, restPos = p, restT = t, roll = Vector3.new(v.X, 0, v.Z) }
end

local function bounceAt(now)
	if not bounce or bounce.key ~= cur.seq then
		bounce = buildBounces(cur.path.landing)
		bounce.key = cur.seq
	end
	for _, s in ipairs(bounce.segs) do
		if now < s.t0 + s.dur then
			local tau = now - s.t0
			local pos = Vector3.new(s.p.X + s.v.X * tau, R + s.v.Y * tau - 0.5 * G * tau * tau, s.p.Z + s.v.Z * tau)
			return pos, Vector3.new(s.v.X, s.v.Y - G * tau, s.v.Z)
		end
	end
	local tau = now - bounce.restT
	local k = 1.6
	local travel = bounce.roll * ((1 - math.exp(-k * tau)) / k)
	local pos = bounce.restPos + travel
	local W, D = Config.Court.WallHalfX - R, Config.Court.WallHalfZ - R
	pos = Vector3.new(math.clamp(pos.X, -W, W), R, math.clamp(pos.Z, -D, D))
	return pos, bounce.roll * math.exp(-k * tau)
end

------------------------------------------------------------------------------------------
-- timeline events
------------------------------------------------------------------------------------------

local function checkEvents(now)
	local path = cur.path
	for i, ev in ipairs(path.netEvents or {}) do
		local key = "n" .. i
		if not fired[key] and now >= ev.t then
			fired[key] = true
			if now - ev.t < 0.4 then
				State.signals.BallEvent:Fire("Net", ev, cur.meta)
			end
		end
	end
	local L = path.landing
	if not fired.land and now >= L.t then
		fired.land = true
		if now - L.t < 0.4 then
			State.signals.BallEvent:Fire("Land", L, cur.meta)
		end
	end
end

------------------------------------------------------------------------------------------
-- per frame
------------------------------------------------------------------------------------------

local function update(dt)
	local now = Util.now()
	local pos, vel = HIDDEN, Vector3.zero
	local live = false
	if cur.state == "Held" then
		local model = Util.modelOf(cur.holder)
		local hrp = model and model:FindFirstChild("HumanoidRootPart")
		if hrp then
			local side = State.sideOfEntity(cur.holder) or 1
			pos = hrp.Position + Vector3.new(0, 1.5, -side * 1.0) -- just below the toss release point
		end
	elseif (cur.state == "Flight" or cur.state == "Dead") and cur.path then
		local landed
		pos, landed = BallPhysics.positionAt(cur.path, now)
		vel = BallPhysics.velocityAt(cur.path, now)
		if landed then
			pos, vel = bounceAt(now)
		else
			live = true
		end
		checkEvents(now)
	end

	if blendOffset.Magnitude > 0.001 then
		local a = (os.clock() - blendStart) / Config.Ball.VisualBlendTime
		if a >= 1 then
			blendOffset = Vector3.zero
		else
			pos = pos + blendOffset * (1 - Util.smoothstep(a))
		end
	end
	renderPos, renderVel = pos, vel

	-- topspin roll around (up x velocity)
	local speed = vel.Magnitude
	if speed > 0.5 then
		local axis = Vector3.yAxis:Cross(vel)
		if axis.Magnitude > 0.01 then
			local rate = 0.35
			if cur.meta and (cur.meta.hitType == "Overhand" or cur.meta.hitType == "Underhand") then
				rate = 0.06 -- a floater barely spins
			elseif cur.meta and cur.meta.energy then
				rate = 0.35 + 0.9 * cur.meta.energy -- Azure: heavy spin
			end
			spinCF = CFrame.fromAxisAngle(axis.Unit, speed * rate * dt) * spinCF
			spinFrames = spinFrames + 1
			if spinFrames > 120 then
				spinCF = spinCF:Orthonormalize()
				spinFrames = 0
			end
		end
	end
	ballRoot.CFrame = CFrame.new(pos) * spinCF

	if speed > 1 then
		local dir = vel.Unit
		if math.abs(dir.Y) > 0.97 then
			trailPart.CFrame = CFrame.lookAt(pos, pos + vel, Vector3.xAxis)
		else
			trailPart.CFrame = CFrame.lookAt(pos, pos + vel)
		end
	else
		trailPart.CFrame = CFrame.new(pos)
	end
	local ht = cur.meta and cur.meta.hitType
	trail.Enabled = live and speed > 8 and ht ~= "Set" and ht ~= "Toss"
	core.Enabled = trail.Enabled and (ht == "Spike" or ht == "JumpServe")
	sparkles.Enabled = (trail.Enabled or (live and chargedOn)) and sparkleOn
	if chargedOn and live then
		-- the charged (or Vector) ball pulses
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * pulseRate)
		glow.Brightness = 3.5 + 3 * pulse
		if chargedHl then
			chargedHl.FillTransparency = 0.35 + 0.35 * pulse
		end
	end
	if not live then
		aura.Enabled = false
		glow.Brightness = math.max(0, glow.Brightness - dt * 8)
	end
	updateBolts(pos, live, speed)

	-- dotted arc behind a set
	local clock = os.clock()
	if live and cur.meta and cur.meta.dotted and clock - lastDotAt > 0.05 then
		lastDotAt = clock
		dotIndex = dotIndex % DOT_COUNT + 1
		local d = dots[dotIndex]
		d.born = clock
		d.part.CFrame = CFrame.new(pos)
		-- a Chain Reaction set is charged: red dots
		d.part.Color = (cur.meta.charged and Config.Abilities.ChainReaction.Color) or (cur.meta.vectorSet and VECTOR) or Config.UI.Chalk
		dotsAliveUntil = clock + 1.4
	end
	if clock < dotsAliveUntil then
		for _, d in ipairs(dots) do
			local age = clock - d.born
			if age < 1.3 then
				local k = age / 1.3
				local s = 0.42 * (1 - k * 0.6)
				d.part.Size = Vector3.new(s, s, s)
				d.part.Transparency = 0.05 + 0.95 * k * k
			elseif d.part.Transparency < 1 then
				d.part.Transparency = 1
			end
		end
	end

	-- drop shadow: the most important depth cue for timing
	if pos.Y > -100 then
		local h = math.max(pos.Y - R, 0)
		local k = math.clamp(1.25 - h / 40, 0.45, 1.25)
		shadow.Size = Vector3.new(0.04, R * 2.2 * k, R * 2.2 * k)
		shadow.CFrame = CFrame.new(pos.X, 0.13, pos.Z) * FLAT
		shadow.Transparency = math.clamp(0.35 + h / 45, 0.35, 0.85)
	else
		shadow.CFrame = CFrame.new(HIDDEN)
	end

	-- landing marker
	local showMarker = State.settings.landingMarker and live and cur.path and cur.path.landing.kind == "Floor"
	if showMarker and cur.meta and cur.meta.hitType == "Toss" then
		showMarker = false
	end
	if showMarker then
		-- a big white ellipse (seen from the side) that tightens as the ball comes down
		local L = cur.path.landing.pos
		local timeLeft = cur.path.landing.t - now
		local size = 5.2 + math.clamp(timeLeft, 0, 1.6) * 1.6
		markerRing.Size = Vector3.new(0.03, size, size)
		markerDot.Size = Vector3.new(0.035, size * 0.78, size * 0.78)
		markerRing.CFrame = CFrame.new(0, 0.14, L.Z) * FLAT
		markerDot.CFrame = CFrame.new(0, 0.15, L.Z) * FLAT
		markerRing.Transparency = 0.15
		markerDot.Transparency = 0.45
	else
		markerRing.Transparency = 1
		markerDot.Transparency = 1
	end
end

------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------

function BallRenderer.getState()
	return cur.state
end

function BallRenderer.getSeq()
	return cur.seq
end

function BallRenderer.getPath()
	return cur.path
end

function BallRenderer.getMeta()
	return cur.meta
end

function BallRenderer.getTouch()
	return cur.touch
end

function BallRenderer.getHolder()
	return cur.holder
end

-- Gameplay position (exact path, no visual smoothing).
function BallRenderer.getPosition(t)
	if cur.state == "Flight" and cur.path then
		return (BallPhysics.positionAt(cur.path, t or Util.now()))
	end
	return renderPos
end

function BallRenderer.getVelocity(t)
	if cur.state == "Flight" and cur.path then
		return BallPhysics.velocityAt(cur.path, t or Util.now())
	end
	return Vector3.zero
end

function BallRenderer.isLive(t)
	return cur.state == "Flight" and cur.path ~= nil and (t or Util.now()) < cur.path.landing.t
end

function BallRenderer.renderPosition()
	return renderPos
end

function BallRenderer.renderVelocity()
	return renderVel
end

-- A dotted path (points along the ball's flight, nearest first), or nil to hide it. The serve
-- toss preview uses it.
function BallRenderer.guide(points)
	local n = points and math.min(#points, GUIDE_COUNT) or 0
	for i = 1, math.max(n, #guideDots) do
		local d = guideDots[i]
		if i <= n then
			if not d then
				d = basicPart("TossGuide", Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 246, 214), Enum.Material.Neon)
				d.Parent = folder
				guideDots[i] = d
			end
			d.CFrame = CFrame.new(points[i])
			d.Transparency = 0.1 + 0.6 * (i - 1) / math.max(1, n - 1)
		elseif d then
			d.Transparency = 1
		end
	end
end

function BallRenderer.init()
	buildVisuals()
	watchToolboxBall()
	applyStyle(nil)
	Net.get("BallState").OnClientEvent:Connect(onState)
	Net.get("HitReject").OnClientEvent:Connect(onReject)
	RunService:BindToRenderStep("SpikeRushBall", Enum.RenderPriority.Camera.Value - 2, update)
end

return BallRenderer
