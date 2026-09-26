-- Hand-drawn effects. Every burst, ring, spark, smoke puff and ball trail in a match is a
-- particle kit made from anime flipbook textures out of two Creator Store VFX packs (the ids are
-- in Assets.Fx), and any kit can be swapped for a whole Toolbox effect: a template in
-- ReplicatedStorage.ToolboxAssets.VFX.<Name> plays instead, sized by its "Scale" attribute and
-- hue-shifted to the play's colour where the kit would have been tinted.
--
--   Fx.play(name, where, opts)  one burst at where (a Vector3 or a CFrame). opts:
--                                color  tints the tintable layers
--                                scale  sizes and speeds (1 = the kit as written)
--                                count  multiplies every layer's particle count
--                                n      replaces every layer's particle count
--                                angle  screen-plane rotation in degrees for aimed sprites
--   Fx.attach(name, parent)     a held kit (a ball trail, an aura) on a part or attachment;
--                                returns a handle: set(on, color, rate), destroy()
--   Fx.override(name)           the Toolbox template filling that slot, or nil
--
-- Bursts are pooled per kit: an instance goes back to its pool once its particles are gone, so
-- a match stops allocating after the first rallies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)

local Fx = {}

local WHITE = Color3.new(1, 1, 1)
local PARKED = CFrame.new(0, -500, 0)
local DUST = Color3.fromRGB(236, 224, 204)
local EMBER = Color3.fromRGB(255, 170, 60)
local THUNDER = Color3.fromRGB(255, 226, 60)
local AZURE = Color3.fromRGB(70, 210, 255)
local HOT = Color3.fromRGB(255, 50, 90)
local ORIENT = {
	flat = Enum.ParticleOrientation.VelocityPerpendicular,
	stretch = Enum.ParticleOrientation.VelocityParallel,
	up = Enum.ParticleOrientation.FacingCameraWorldUp,
}
local FADE = { { 0, 0 }, { 0.7, 0.05 }, { 1, 1 } }

------------------------------------------------------------------------------------------
-- layers: one ParticleEmitter each
--   t      texture key in Assets.Fx      grid   flipbook layout, played once per particle
--   n      particles per burst           rate   particles a second when held (Fx.attach)
--   d      delay before the burst        life   { min, max } seconds
--   size   studs: a number or { {time, value}, ... }       alpha  transparency, same shape
--   speed  { min, max }                  spread degrees either side of straight up, kept in the
--                                               screen plane (the camera looks along +x)
--   drag, accel (a Vector3), rot { min, max } start angle, spin { min, max } degrees a second
--   glow   LightEmission (default 1)     z      ZOffset toward the camera
--   mode   "flat" lies on the floor, "stretch" streaks along its flight, "up" stays upright
--   color  a Color3 or { from, to }      tint   takes the play's colour: from that colour
--                                               lightened by this much (0..1) to the colour
--   aim    true: opts.angle turns it
------------------------------------------------------------------------------------------

local function layer(base, over)
	local s = {}
	for k, v in pairs(base) do
		s[k] = v
	end
	for k, v in pairs(over or {}) do
		s[k] = v
	end
	return s
end

local STAR = { t = "HitStar", n = 1, life = { 0.13, 0.16 }, size = { { 0, 2.5 }, { 0.25, 7 }, { 1, 7.5 } }, alpha = { { 0, 0 }, { 0.55, 0 }, { 1, 1 } }, rot = { 0, 360 }, z = 3, tint = 0.15 }
local BURST = { t = "HitBurst", n = 1, life = { 0.16, 0.2 }, size = { { 0, 3 }, { 0.2, 10 }, { 1, 11.5 } }, alpha = { { 0, 0 }, { 0.5, 0 }, { 1, 1 } }, rot = { 0, 360 }, z = 2.5, tint = 0.45 }
local RING = { t = "HitRing", grid = "Grid4x4", n = 1, life = { 0.3, 0.3 }, size = { { 0, 5 }, { 1, 11 } }, alpha = { { 0, 0 }, { 1, 0.2 } }, rot = { 0, 360 }, z = 2, tint = 0.5 }
local SPARKS = { t = "Streak", n = 8, life = { 0.16, 0.26 }, size = { { 0, 4.5 }, { 1, 0.5 } }, speed = { 45, 85 }, drag = 6, spread = 180, mode = "stretch", z = 2, tint = 0.55 }
local GLINTS = { t = "Glint", n = 2, life = { 0.22, 0.32 }, size = { { 0, 0 }, { 0.25, 4.5 }, { 1, 0 } }, speed = { 8, 16 }, drag = 5, spread = 180, rot = { -15, 15 }, z = 3 }
local GLOW = { t = "Glow", n = 1, life = { 0.2, 0.2 }, size = { { 0, 3 }, { 1, 8 } }, alpha = { { 0, 0.4 }, { 1, 1 } }, z = 1, tint = 0 }
local RADIAL = { t = "Radial", n = 1, life = { 0.22, 0.22 }, size = { { 0, 4 }, { 1, 17 } }, alpha = { { 0, 0 }, { 0.5, 0.15 }, { 1, 1 } }, rot = { 0, 360 }, z = 1, tint = 0.4 }
local SPIKY = { t = "SpikyRing", n = 1, life = { 0.3, 0.3 }, size = { { 0, 2 }, { 1, 13 } }, alpha = { { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } }, rot = { 0, 360 }, z = 1.5, tint = 0.3 }
local PUFFS = { t = "Smoke", grid = "Grid4x4", n = 6, life = { 0.55, 0.85 }, size = { { 0, 2.2 }, { 1, 5 } }, alpha = { { 0, 0.05 }, { 0.75, 0.35 }, { 1, 1 } }, speed = { 12, 24 }, spread = 80, drag = 4, accel = Vector3.new(0, 3, 0), rot = { 0, 360 }, glow = 0, color = DUST }
local WAVE = { t = "SpikyRing", n = 1, life = { 0.4, 0.4 }, size = { { 0, 1.5 }, { 1, 14 } }, alpha = { { 0, 0 }, { 0.5, 0.15 }, { 1, 1 } }, rot = { 0, 360 }, mode = "flat", tint = 0.5 }
local DISC = { t = "GroundWave", n = 1, life = { 0.3, 0.3 }, size = { { 0, 1 }, { 1, 9 } }, alpha = { { 0, 0.3 }, { 1, 1 } }, mode = "flat", tint = 0.5 }
local DUSTRING = { t = "DustRing", n = 1, life = { 0.5, 0.5 }, size = { { 0, 2 }, { 1, 13 } }, alpha = { { 0, 0.1 }, { 1, 1 } }, mode = "flat", color = DUST }
local CRACK = { t = "Crack", grid = "Grid4x4", n = 1, life = { 1.5, 1.5 }, size = 12, alpha = { { 0, 0 }, { 0.75, 0 }, { 1, 1 } }, mode = "flat", tint = 0.2, color = Color3.fromRGB(255, 190, 120) }
local FLAMES = { t = "Fire", grid = "Grid4x4", n = 10, life = { 0.45, 0.75 }, size = { { 0, 3 }, { 0.4, 4.5 }, { 1, 2.5 } }, speed = { 5, 12 }, spread = 60, drag = 2, accel = Vector3.new(0, 12, 0), rot = { -25, 25 }, z = 1.5 }
local WHITEFIRE = layer(FLAMES, { t = "FireWhite", tint = 0.35, color = { Color3.fromRGB(255, 236, 150), Color3.fromRGB(255, 110, 40) } })
local FIREBALL = { t = "Fireball", grid = "Grid4x4", n = 3, life = { 0.6, 0.8 }, size = { { 0, 5 }, { 1, 10 } }, speed = { 3, 8 }, spread = 180, rot = { 0, 360 }, glow = 0.4, z = 1 }
local EMBERS = { t = "Dot", n = 16, life = { 0.6, 1.1 }, size = { { 0, 0.7 }, { 1, 0 } }, speed = { 14, 30 }, spread = 60, drag = 1.5, accel = Vector3.new(0, -18, 0), color = EMBER, z = 2 }
local ELECTRIC = { t = "Electric", grid = "Grid4x4", n = 3, life = { 0.22, 0.32 }, size = { { 0, 5 }, { 1, 7 } }, speed = { 0, 4 }, spread = 180, rot = { 0, 360 }, z = 2, tint = 0.3, color = THUNDER }
local ARCS = { t = "Arcs", grid = "Grid2x2", n = 3, life = { 0.14, 0.2 }, size = 6.5, rot = { 0, 360 }, z = 2.5, tint = 0.2, color = THUNDER }
local ROCKS = { t = "Rock", n = 10, life = { 0.7, 1 }, size = { { 0, 1.6 }, { 1, 1.1 } }, speed = { 28, 48 }, spread = 55, accel = Vector3.new(0, -95, 0), rot = { 0, 360 }, spin = { -300, 300 }, glow = 0, z = 1 }
local CRATER = { t = "Crater", n = 1, life = { 1.6, 1.6 }, size = 14, alpha = { { 0, 0 }, { 0.7, 0 }, { 1, 1 } }, mode = "flat", tint = 0.3, color = Color3.fromRGB(255, 150, 70) }
local BOLT = { t = "Bolt", n = 1, life = { 0.14, 0.18 }, size = 10, alpha = { { 0, 0 }, { 0.6, 0 }, { 1, 1 } }, aim = true, z = 2.5, tint = 0.25, color = THUNDER }
local SPARKLE = { t = "Sparkle", n = 1, life = { 0.25, 0.45 }, size = { { 0, 0 }, { 0.3, 1.6 }, { 1, 0 } }, rot = { 0, 90 }, z = 1, tint = 0.6 }

local KITS = {
	-- building blocks
	Star = { STAR },
	Burst = { BURST },
	Ring = { layer(RING, { size = { { 0, 3 }, { 1, 10 } } }), layer(SPIKY, { size = { { 0, 2 }, { 1, 9 } } }) },
	Spiky = { SPIKY },
	Sparks = { layer(SPARKS, { n = 10 }) },
	Glints = { GLINTS },
	Glow = { GLOW },
	Radial = { RADIAL },
	Wave = { WAVE },
	Dust = { layer(PUFFS, { n = 10 }) },
	Fire = { layer(WHITEFIRE, { n = 12 }) },
	Bolt = { BOLT },
	Electric = { ELECTRIC },

	-- contact
	SpikeImpact = { STAR, RING, SPARKS, GLINTS },
	PerfectImpact = {
		BURST,
		layer(STAR, { d = 0.03, size = { { 0, 3 }, { 0.25, 8.5 }, { 1, 9 } } }),
		RING,
		layer(RING, { d = 0.07, size = { { 0, 3 }, { 1, 15 } } }),
		RADIAL,
		layer(SPARKS, { n = 16, speed = { 55, 100 } }),
		GLOW,
	},
	ThunderImpact = {
		layer(BURST, { color = THUNDER }),
		ELECTRIC,
		ARCS,
		layer(RING, { color = THUNDER, size = { { 0, 2 }, { 1, 13 } } }),
		layer(SPARKS, { n = 12, color = THUNDER }),
		layer(GLOW, { color = THUNDER }),
	},
	AzureImpact = {
		layer(BURST, { color = AZURE }),
		layer(RING, { color = AZURE, size = { { 0, 2 }, { 1, 13 } } }),
		layer(WHITEFIRE, { n = 10, color = AZURE, spread = 180, accel = Vector3.new(0, 4, 0) }),
		layer(SPARKS, { n = 10, color = Color3.fromRGB(200, 245, 255) }),
		layer(GLOW, { color = AZURE }),
	},
	BlockImpact = {
		layer(STAR, { size = { { 0, 3 }, { 0.25, 8 }, { 1, 8.5 } } }),
		SPIKY,
		layer(SPARKS, { n = 10 }),
		layer(PUFFS, { n = 3, spread = 180, speed = { 4, 10 } }),
	},
	ReceiveImpact = { layer(RING, { size = { { 0, 1.5 }, { 1, 6.5 } } }), layer(GLINTS, { n = 1 }) },
	NetImpact = { layer(RING, { size = { { 0, 1 }, { 1, 5 } } }), layer(SPARKS, { n = 4, speed = { 20, 35 } }) },
	FloorImpact = { WAVE, PUFFS },
	JumpBoom = { layer(WAVE, { size = { { 0, 1 }, { 1, 9 } } }), DUSTRING, layer(PUFFS, { n = 8 }) },
	GuardBreak = {
		layer(BURST, { color = HOT }),
		layer(SPIKY, { color = HOT }),
		layer(SPARKS, { n = 16, color = Color3.fromRGB(210, 235, 255) }),
		layer(GLINTS, { n = 4 }),
	},
	ChainExplosion = { layer(FIREBALL, { n = 2 }), BURST, RING, layer(SPARKS, { n = 14 }), layer(EMBERS, { n = 12 }) },

	-- score effects: where a point lands (the meteor's fall and the thunderbolt's strike from
	-- the sky are VFXController's, these are the ground)
	ScoreFire = {
		layer(FIREBALL, { n = 4, size = { { 0, 7 }, { 1, 14 } }, speed = { 4, 10 } }),
		layer(FLAMES, { n = 14, size = { { 0, 4 }, { 0.4, 6 }, { 1, 3 } }, speed = { 10, 22 } }),
		layer(WAVE, { color = Color3.fromRGB(255, 150, 60), size = { { 0, 2 }, { 1, 22 } } }),
		layer(CRACK, { color = Color3.fromRGB(255, 120, 40) }),
		layer(EMBERS, { n = 24 }),
		layer(PUFFS, { n = 6, d = 0.1, color = Color3.fromRGB(90, 70, 60), size = { { 0, 4 }, { 1, 9 } } }),
		light = { Color3.fromRGB(255, 140, 60), 6, 32, 0.7 },
	},
	ScoreMeteor = {
		CRATER,
		layer(FIREBALL, { n = 3, size = { { 0, 8 }, { 1, 16 } } }),
		layer(ROCKS, { n = 12 }),
		layer(RING, { size = { { 0, 4 }, { 1, 22 } }, color = Color3.fromRGB(255, 200, 120) }),
		layer(PUFFS, { n = 10, size = { { 0, 4 }, { 1, 10 } }, speed = { 12, 26 }, color = Color3.fromRGB(120, 100, 90) }),
		layer(EMBERS, { n = 20 }),
		light = { Color3.fromRGB(255, 140, 60), 7, 36, 0.7 },
	},
	ScoreThunderbolt = {
		layer(BURST, { color = THUNDER, size = { { 0, 4 }, { 0.2, 13 }, { 1, 14 } } }),
		layer(ELECTRIC, { n = 4, size = { { 0, 7 }, { 1, 10 } } }),
		layer(ARCS, { n = 5, size = 9 }),
		layer(WAVE, { color = THUNDER, size = { { 0, 2 }, { 1, 20 } } }),
		layer(DISC, { color = THUNDER, size = { { 0, 2 }, { 1, 14 } } }),
		layer(CRACK, { color = THUNDER }),
		layer(GLINTS, { n = 5 }),
		light = { THUNDER, 8, 40, 0.5 },
	},
	ScoreShockwave = {
		layer(WAVE, { size = { { 0, 2 }, { 1, 28 } }, life = { 0.5, 0.5 } }),
		layer(DISC, { size = { { 0, 2 }, { 1, 18 } } }),
		layer(DUSTRING, { size = { { 0, 3 }, { 1, 22 } } }),
		layer(SPIKY, { size = { { 0, 3 }, { 1, 18 } } }),
		layer(RADIAL, { size = { { 0, 5 }, { 1, 22 } } }),
		layer(PUFFS, { n = 14, speed = { 14, 30 }, size = { { 0, 3 }, { 1, 7 } } }),
	},

	-- held kits (Fx.attach): the ball's trails, the falling meteor, auras
	TrailFlame = {
		layer(WHITEFIRE, { rate = 150, life = { 0.18, 0.32 }, size = { { 0, 2.8 }, { 1, 0.8 } }, speed = { 0, 1.5 }, spread = 180, drag = 0, accel = Vector3.new(0, 6, 0), tint = 0.4 }),
		layer(EMBERS, { rate = 40, life = { 0.3, 0.6 }, speed = { 1, 4 }, spread = 180, accel = Vector3.new(0, 4, 0), size = { { 0, 0.5 }, { 1, 0 } }, tint = 0.3 }),
	},
	TrailSparkle = {
		layer(GLINTS, { rate = 90, life = { 0.3, 0.55 }, size = { { 0, 0 }, { 0.2, 2.2 }, { 1, 0 } }, speed = { 0.5, 2.5 }, drag = 0, spin = { -120, 120 }, tint = 0.5 }),
		layer(SPARKLE, { rate = 25 }),
	},
	TrailStardust = {
		{ t = "Specks", rate = 140, life = { 0.4, 0.8 }, size = { { 0, 2.4 }, { 1, 0.6 } }, speed = { 0.5, 3 }, spread = 180, rot = { 0, 360 }, tint = 0.5, color = Color3.fromRGB(255, 250, 220) },
		layer(GLINTS, { rate = 70, life = { 0.35, 0.7 }, size = { { 0, 0 }, { 0.2, 2.8 }, { 1, 0 } }, speed = { 0.5, 3 }, drag = 0, spin = { -90, 90 }, tint = 0.4 }),
		layer(SPARKLE, { rate = 30, size = { { 0, 0 }, { 0.3, 2.2 }, { 1, 0 } } }),
	},
	TrailLightning = {
		layer(ARCS, { rate = 45, life = { 0.1, 0.18 }, size = { { 0, 3.5 }, { 1, 4.5 } }, tint = 0.25 }),
		layer(ELECTRIC, { rate = 25, life = { 0.14, 0.22 }, size = 4, speed = { 0, 1 }, tint = 0.3 }),
	},
	TrailComet = {
		layer(GLOW, { rate = 70, life = { 0.12, 0.22 }, size = { { 0, 4.5 }, { 1, 1 } }, alpha = { { 0, 0.3 }, { 1, 1 } }, tint = 0.6, z = -0.5, color = WHITE }),
		layer(GLINTS, { rate = 20, life = { 0.25, 0.4 }, size = { { 0, 0 }, { 0.3, 2 }, { 1, 0 } }, speed = { 0.5, 2 }, drag = 0, tint = 0.5 }),
	},
	MeteorTrail = {
		layer(FLAMES, { rate = 220, life = { 0.2, 0.35 }, size = { { 0, 5 }, { 1, 1.5 } }, speed = { 0, 2 }, spread = 180, accel = Vector3.zero, tint = 0.35 }),
		layer(PUFFS, { rate = 60, life = { 0.4, 0.7 }, speed = { 0, 2 }, spread = 180, drag = 0, accel = Vector3.zero, size = { { 0, 3 }, { 1, 6 } }, color = Color3.fromRGB(80, 64, 58) }),
	},
	AzureAura = {
		layer(WHITEFIRE, { rate = 40, life = { 0.3, 0.55 }, size = { { 0, 2.4 }, { 1, 0.4 } }, speed = { 2, 5 }, spread = 180, drag = 0, accel = Vector3.new(0, 7, 0), tint = 0.45, color = { Color3.fromRGB(150, 245, 255), Color3.fromRGB(30, 100, 255) } }),
	},
	StatusAura = {
		layer(WHITEFIRE, { rate = 40, life = { 0.3, 0.6 }, size = { { 0, 2.2 }, { 1, 0 } }, speed = { 2, 5 }, spread = 40, drag = 0, accel = Vector3.new(0, 3, 0), alpha = { { 0, 0.3 }, { 1, 1 } }, tint = 0.5 }),
	},
}

------------------------------------------------------------------------------------------
-- building
------------------------------------------------------------------------------------------

local function seq(v, k)
	if type(v) == "number" then
		return NumberSequence.new(v * k)
	end
	local points = {}
	for _, p in ipairs(v) do
		table.insert(points, NumberSequenceKeypoint.new(p[1], p[2] * k))
	end
	return NumberSequence.new(points)
end

local function scaled(s, k)
	local points = {}
	for _, p in ipairs(s.Keypoints) do
		table.insert(points, NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k))
	end
	return NumberSequence.new(points)
end

local function colors(c)
	if typeof(c) == "Color3" then
		return ColorSequence.new(c)
	end
	return ColorSequence.new(c[1], c[2])
end

-- A kit layer's colour for a play: the colour lightened by `tint` fading into the colour. A
-- Toolbox layer ("hue") keeps each keypoint's own brightness and whiteness and takes the hue.
local function paint(L, color)
	if L.tint == "hue" then
		local h, cs = color:ToHSV()
		local points = {}
		for _, kp in ipairs(L.base.Keypoints) do
			local _, s, v = kp.Value:ToHSV()
			table.insert(points, ColorSequenceKeypoint.new(kp.Time, Color3.fromHSV(h, s * cs, v)))
		end
		return ColorSequence.new(points)
	end
	return ColorSequence.new(color:Lerp(WHITE, L.tint), color)
end

local function emitter(spec, parent)
	local e = Instance.new("ParticleEmitter")
	e.Texture = Assets.id(Assets.Fx[spec.t]) or ""
	e.Enabled = false
	e.LightInfluence = 0
	e.LightEmission = spec.glow or 1
	e.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
	local speed = spec.speed or { 0, 0 }
	if spec.mode == "flat" and speed[2] <= 0 then
		speed = { 0.01, 0.01 } -- a flat sprite faces its velocity: straight up
	end
	e.Speed = NumberRange.new(speed[1], speed[2])
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(spec.spread or 0, 0)
	e.Drag = spec.drag or 0
	e.Acceleration = spec.accel or Vector3.zero
	e.Rotation = NumberRange.new(spec.rot and spec.rot[1] or 0, spec.rot and spec.rot[2] or 0)
	e.RotSpeed = NumberRange.new(spec.spin and spec.spin[1] or 0, spec.spin and spec.spin[2] or 0)
	e.Size = seq(spec.size or 1, 1)
	e.Transparency = seq(spec.alpha or FADE, 1)
	e.ZOffset = spec.z or 0
	e.Color = colors(spec.color or WHITE)
	if spec.mode then
		e.Orientation = ORIENT[spec.mode]
	end
	if spec.grid then
		e.FlipbookLayout = Enum.ParticleFlipbookLayout[spec.grid]
		e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end
	e.Rate = spec.rate or 0
	e.Parent = parent
	return e
end

local function record(e, n, d, tint, aim, rate)
	return { em = e, n = n, d = d, tint = tint, aim = aim, rate = rate, base = e.Color, size = e.Size, speed = e.Speed, accel = e.Acceleration }
end

local folder
local function kitFolder()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "SpikeRushKits"
		folder.Parent = workspace
	end
	return folder
end

local function holder(name)
	local p = Instance.new("Part")
	p.Name = name or "Fx"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = PARKED
	p.Parent = kitFolder()
	return p
end

function Fx.override(name)
	return Assets.toolbox("VFX." .. name)
end

-- A kit's layers built on parent (a part or attachment).
local function buildKit(kit, parent)
	local layers, life = {}, 0.2
	for _, spec in ipairs(kit) do
		local e = emitter(spec, parent)
		table.insert(layers, record(e, spec.n or 1, spec.d or 0, spec.tint, spec.aim, spec.rate or 0))
		life = math.max(life, (spec.d or 0) + spec.life[2])
	end
	return layers, life
end

-- A Toolbox template's emitters, sized by its Scale attribute. Beams, trails and lights are
-- switched off: without the effect's own scripts nothing would ever animate them.
local function adopt(clone, scale)
	local layers, life = {}, 0.2
	local all = clone:GetDescendants()
	table.insert(all, clone)
	for _, d in ipairs(all) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			if scale ~= 1 then
				d.Size = scaled(d.Size, scale)
				d.Speed = NumberRange.new(d.Speed.Min * scale, d.Speed.Max * scale)
				d.Acceleration = d.Acceleration * scale
			end
			local delay = tonumber(d:GetAttribute("EmitDelay")) or 0
			table.insert(layers, record(d, tonumber(d:GetAttribute("EmitCount")) or 20, delay, "hue", false, d.Rate))
			life = math.max(life, delay + d.Lifetime.Max)
		elseif d:IsA("Attachment") and scale ~= 1 then
			d.Position = d.Position * scale
		elseif d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") then
			d.Enabled = false
		elseif d:IsA("Decal") then
			d.Transparency = 1
		end
	end
	return layers, life
end

-- A burst instance: { root = the part or model moved per play, layers, life, k, src }.
local function fromToolbox(template)
	local clone = Assets.sanitize(template:Clone())
	local scale = tonumber(template:GetAttribute("Scale")) or 1
	local inst = { k = 1, src = template, lift = tonumber(template:GetAttribute("Lift")) or 0 }
	if clone:IsA("BasePart") then
		if not clone:GetAttribute("Visible") then
			clone.Transparency = 1
		end
		clone.CFrame = PARKED
		inst.root = clone
		clone.Parent = kitFolder()
	elseif clone:IsA("Model") then
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("BasePart") and not p:GetAttribute("Visible") then
				p.Transparency = 1
			end
		end
		clone:PivotTo(PARKED)
		inst.root = clone
		inst.model = true
		clone.Parent = kitFolder()
	else
		-- an Attachment or a Folder of them: hang it on a holder part
		local part = holder()
		clone.Parent = part
		inst.root = part
	end
	inst.layers, inst.life = adopt(clone, scale)
	return inst
end

local function fromKit(name)
	local kit = KITS[name]
	if not kit then
		return nil
	end
	local part = holder(name)
	local inst = { root = part, k = 1, src = false, lift = 0 }
	inst.layers, inst.life = buildKit(kit, part)
	if kit.light then
		local l = Instance.new("PointLight")
		l.Shadows = false
		l.Brightness = 0
		l.Enabled = false
		l.Parent = part
		inst.light = l
		inst.lightSpec = kit.light
		inst.life = math.max(inst.life, kit.light[4])
	end
	return inst
end

------------------------------------------------------------------------------------------
-- playing
------------------------------------------------------------------------------------------

local pools = {} -- name -> idle instances
local sources = {} -- name -> the Toolbox template the pool holds (false: the kit)

local function acquire(name)
	local template = Fx.override(name)
	local src = template or false
	if sources[name] ~= src then
		-- the slot changed (a Toolbox effect arrived or left): start a fresh pool
		for _, inst in ipairs(pools[name] or {}) do
			inst.root:Destroy()
		end
		pools[name] = {}
		sources[name] = src
	end
	local list = pools[name]
	local inst = table.remove(list)
	if inst then
		return inst
	end
	if template then
		return fromToolbox(template)
	end
	return fromKit(name)
end

local function release(name, inst)
	if sources[name] == inst.src then
		if inst.model then
			inst.root:PivotTo(PARKED)
		else
			inst.root.CFrame = PARKED
		end
		table.insert(pools[name], inst)
	else
		inst.root:Destroy()
	end
end

function Fx.play(name, where, opts)
	local inst = acquire(name)
	if not inst then
		return false
	end
	opts = opts or {}
	local k = opts.scale or 1
	local cf = typeof(where) == "CFrame" and where or CFrame.new(where)
	if inst.lift ~= 0 then
		cf = cf + Vector3.new(0, inst.lift * k, 0)
	end
	if inst.model then
		inst.root:PivotTo(cf)
	else
		inst.root.CFrame = cf
	end
	local rescale = k ~= inst.k
	inst.k = k
	for _, L in ipairs(inst.layers) do
		local em = L.em
		if rescale then
			em.Size = scaled(L.size, k)
			em.Speed = NumberRange.new(L.speed.Min * k, L.speed.Max * k)
			em.Acceleration = L.accel * k
		end
		if L.tint and opts.color then
			em.Color = paint(L, opts.color)
			L.painted = true
		elseif L.painted then
			em.Color = L.base
			L.painted = false
		end
		if L.aim then
			local a = opts.angle or 0
			em.Rotation = NumberRange.new(a, a)
		end
		local count = opts.n or math.max(1, math.floor(L.n * (opts.count or 1) + 0.5))
		if L.d > 0 then
			task.delay(L.d, function()
				if em.Parent then
					em:Emit(count)
				end
			end)
		else
			em:Emit(count)
		end
	end
	if inst.light then
		local spec = inst.lightSpec
		local l = inst.light
		l.Color = opts.color or spec[1]
		l.Range = spec[3] * k
		l.Brightness = spec[2]
		l.Enabled = true
		TweenService:Create(l, TweenInfo.new(spec[4], Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	end
	task.delay(inst.life + 0.15, function()
		if inst.light then
			inst.light.Enabled = false
		end
		release(name, inst)
	end)
	return true
end

-- A held kit on parent: a Toolbox template's emitters (at their own rates) or the kit's.
function Fx.attach(name, parent)
	local template = Fx.override(name)
	local layers = {}
	local made = {}
	if template then
		local clone = Assets.sanitize(template:Clone())
		local scale = tonumber(template:GetAttribute("Scale")) or 1
		for _, L in ipairs(adopt(clone, scale)) do
			L.em.Parent = parent
			if L.rate <= 0 then
				L.rate = 30
			end
			table.insert(layers, L)
			table.insert(made, L.em)
		end
		clone:Destroy()
	elseif KITS[name] then
		layers = buildKit(KITS[name], parent)
		for _, L in ipairs(layers) do
			table.insert(made, L.em)
		end
	end
	local handle = { layers = layers, src = template or false }
	function handle.set(on, color, rate)
		for _, L in ipairs(layers) do
			local em = L.em
			if on then
				if L.tint and color then
					em.Color = paint(L, color)
				elseif L.tint then
					em.Color = L.base
				end
				em.Rate = L.rate * (rate or 1)
			end
			em.Enabled = on
		end
	end
	function handle.destroy()
		for _, e in ipairs(made) do
			e:Destroy()
		end
		table.clear(layers)
	end
	return handle
end

-- Fetch every kit texture once, so the first spike of a match doesn't flash blank sprites.
function Fx.preload()
	local list = {}
	for _, id in pairs(Assets.Fx) do
		local e = Instance.new("ParticleEmitter")
		e.Texture = Assets.id(id) or ""
		table.insert(list, e)
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	for _, e in ipairs(list) do
		e:Destroy()
	end
end

return Fx
