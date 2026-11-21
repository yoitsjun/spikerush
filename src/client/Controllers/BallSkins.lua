-- Ball skins (Config.Cosmetics.Ball; the owner: "add some ball skins... make your own balls. i
-- want 6-10 balls. another ball can be a spiky ball, or a player's head ball"). In a match the
-- ball wears the skin of whoever served the rally (BallRenderer); the Locker's practice ball and
-- its cards wear the one you point at (SceneController, MenuController).
--
-- BallSkins.build(key, radius, owner) returns a Model centred on the origin (its pivot), every
-- part unanchored, massless and without collisions, for the caller to place and weld, or nil
-- for the classic look (each caller keeps its own). `owner` is the character whose head the
-- Big Head skin copies.
--
-- The meshes were modelled in Blender (assets/balls/BallSkinMeshes.fbx: BallSphere with
-- equirectangular UVs, BallSpiky, BallDisco, BallRing) and imported into
-- ReplicatedStorage.ToolboxAssets.BallSkins; the textures are drawn by
-- tools/generate_ball_skins.py (Assets.BallSkins). Until the meshes are imported, each skin is a
-- plain ball in its main colour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)

local BallSkins = {}

local LOOKS = {
	ProSwirl = { texture = "ProSwirl", color = Color3.fromRGB(255, 206, 40) },
	TriPanel = { texture = "TriPanel", color = Color3.fromRGB(244, 244, 238) },
	Beach = { texture = "Beach", color = Color3.fromRGB(232, 40, 44) },
	Eyeball = { texture = "Eyeball", color = Color3.fromRGB(245, 240, 232) },
	Lava = { texture = "Lava", color = Color3.fromRGB(60, 30, 20), light = Color3.fromRGB(255, 120, 30), embers = Color3.fromRGB(255, 140, 40) },
	Galaxy = { texture = "Galaxy", color = Color3.fromRGB(40, 20, 90), light = Color3.fromRGB(170, 90, 255), embers = Color3.fromRGB(220, 190, 255) },
	Planet = { texture = "Planet", color = Color3.fromRGB(220, 170, 110), ring = Color3.fromRGB(230, 205, 160) },
	Spiky = { mesh = "BallSpiky", color = Color3.fromRGB(150, 156, 170), material = Enum.Material.Metal, reflect = 0.25, span = 1.55 },
	Disco = { mesh = "BallDisco", color = Color3.fromRGB(225, 230, 240), material = Enum.Material.Metal, reflect = 0.7, embers = Color3.fromRGB(255, 255, 255) },
	-- Halloween (the owner's own models, cut down to ~13k triangles and painted in Blender:
	-- assets/balls/BallPumpkin.fbx and BallWitchHat.fbx, imported into ToolboxAssets.BallSkins
	-- under those names; their maps are Assets.BallSkins'). Until then, a glowing ball in the main
	-- colour. `fit`: keeps its own proportions (the hat is wider than it's tall)
	Pumpkin = { mesh = "BallPumpkin", texture = "Pumpkin", fit = true, color = Color3.fromRGB(255, 120, 20), light = Color3.fromRGB(255, 150, 40), embers = Color3.fromRGB(255, 170, 60) },
	-- the Winter collab's (the owner, 2026-11-15: "christmas cosmetics, a snowflake ball..."): maps on
	-- the plain sphere. Snowflake glows cold and sheds white glints; the Ornament and the
	-- Peppermint are glossy; the Snowball sheds powder
	Snowflake = { texture = "Snowflake", color = Color3.fromRGB(170, 222, 255), light = Color3.fromRGB(170, 225, 255), embers = Color3.fromRGB(255, 255, 255) },
	Ornament = { texture = "Ornament", color = Color3.fromRGB(206, 22, 40), reflect = 0.28 },
	Snowball = { texture = "Snowball", color = Color3.fromRGB(250, 252, 255), embers = Color3.fromRGB(235, 244, 255), extra = "snowball" },
	Peppermint = { texture = "Peppermint", color = Color3.fromRGB(240, 60, 70), reflect = 0.14 },
	Gift = { texture = "Gift", color = Color3.fromRGB(24, 132, 74) },
	-- the Winter Pass's: a mirror-gold bauble with its cap, hanging loop and a band of red gems; an
	-- ice crystal (a glowing core in a cluster of glass shards); an icicle ball (the spiky one in
	-- ice); and a snow globe (a clear globe on its wooden stand, a tiny snowy scene inside and snow
	-- swirling in it). (The owner, 2026-11-17: "some of these are also quite shoddy": they were
	-- plain spheres in a colour.) The pieces: EXTRAS below
	GoldBauble = { color = Color3.fromRGB(255, 196, 60), material = Enum.Material.Metal, reflect = 0.45, embers = Color3.fromRGB(255, 230, 140), extra = "bauble" },
	Crystal = { color = Color3.fromRGB(120, 210, 255), material = Enum.Material.Neon, light = Color3.fromRGB(160, 220, 255), embers = Color3.fromRGB(235, 248, 255), extra = "crystal", coreScale = 0.62 },
	IcicleBall = { mesh = "BallSpiky", color = Color3.fromRGB(190, 235, 255), material = Enum.Material.Glass, reflect = 0.3, span = 1.55, embers = Color3.fromRGB(255, 255, 255) },
	SnowGlobe = { color = Color3.fromRGB(225, 242, 255), material = Enum.Material.Glass, reflect = 0.25, light = Color3.fromRGB(200, 230, 255), extra = "globe" },
	-- the advent calendar's (the owner, 2026-11-18: "make up a tone of cosmetics for advent
	-- calender"): gingerbread iced in zigzags with sugar buttons; a gold jingle bell (its slot, rim,
	-- loop and a red bow); a Christmas pudding under custard with a sprig of holly; a snowman's head
	-- (coal eyes and smile, a carrot nose, a little top hat); a pine wreath with berries and a bow;
	-- and the North Star, a faceted gold star (assets/fx/winter/AdventMeshes.fbx: BallStar) that
	-- glows and sheds sparks. Their maps: tools/generate_advent_textures.py
	Gingerbread = { texture = "Gingerbread", color = Color3.fromRGB(190, 112, 52) },
	JingleBell = { color = Color3.fromRGB(255, 196, 50), material = Enum.Material.Metal, reflect = 0.35, embers = Color3.fromRGB(255, 232, 150), extra = "jingle" },
	Pudding = { texture = "Pudding", color = Color3.fromRGB(92, 46, 22), extra = "pudding" },
	SnowmanHead = { texture = "Snowball", color = Color3.fromRGB(250, 252, 255), extra = "snowman" },
	Wreath = { texture = "Wreath", color = Color3.fromRGB(28, 100, 50), extra = "wreath" },
	NorthStar = { mesh = "BallStar", fit = true, span = 1.35, color = Color3.fromRGB(255, 200, 60), material = Enum.Material.Metal, reflect = 0.3, light = Color3.fromRGB(255, 214, 120), embers = Color3.fromRGB(255, 240, 180), extra = "starGlow" },
	WitchHat = { mesh = "BallWitchHat", texture = "WitchHat", fit = true, span = 1.15, color = Color3.fromRGB(60, 30, 90), light = Color3.fromRGB(150, 80, 255), embers = Color3.fromRGB(190, 255, 120) },
}

local function prep(p)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
end

local function mesh(name)
	local box = Assets.toolbox("BallSkins")
	local src = box and box:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		local m = src:Clone()
		m.TextureID = ""
		return m
	end
	return nil
end

local function ball(radius, color)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * radius * 2
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	return p
end

-- sparkles or embers drifting off the ball, and its glow
local function dress(core, look, radius)
	if look.light then
		local l = Instance.new("PointLight")
		l.Color = look.light
		l.Range = radius * 10
		l.Brightness = 1.6
		l.Parent = core
	end
	if look.embers then
		local e = Instance.new("ParticleEmitter")
		e.Texture = Assets.id(Assets.Fx[look.mesh == "BallDisco" and "Glint" or "Dot"]) or ""
		e.Color = ColorSequence.new(look.embers)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.4, 0.9)
		e.Rate = 14
		e.Speed = NumberRange.new(0.5, 2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.Parent = core
	end
end

-- Big Head: the owner's own head (face, hair and hats on it), blown up to the ball's size. A
-- yellow ball with the classic face when there's no head to copy.
local function bigHead(radius, owner)
	local model = Instance.new("Model")
	model.Name = "BallSkin"
	local head = owner and owner:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		local p = ball(radius, Color3.fromRGB(255, 204, 0))
		local face = Instance.new("Decal")
		face.Texture = "rbxasset://textures/face.png"
		face.Face = Enum.NormalId.Front
		face.Parent = p
		p.Name = "Core"
		p.Parent = model
		model.PrimaryPart = p
		return model
	end
	local h = head:Clone()
	for _, c in ipairs(h:GetChildren()) do
		if not (c:IsA("Decal") or c:IsA("DataModelMesh") or c:IsA("SurfaceAppearance")) then
			c:Destroy()
		end
	end
	h.Name = "Core"
	h.CFrame = CFrame.new()
	h.Transparency = 0
	h.Parent = model
	model.PrimaryPart = h
	-- whatever's worn on the head: hair, hats, glasses (accessories welded to it)
	for _, acc in ipairs(owner:GetChildren()) do
		local handle = acc:IsA("Accessory") and acc:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			-- worn on the head: its attachment (HatAttachment, HairAttachment, FaceFrontAttachment...)
			-- is one of the head's, whatever joint holds it
			local onHead = false
			for _, att in ipairs(handle:GetChildren()) do
				if att:IsA("Attachment") and head:FindFirstChild(att.Name) then
					onHead = true
				end
			end
			if onHead then
				local c = Assets.sanitize(handle:Clone())
				for _, w in ipairs(c:GetDescendants()) do
					if w:IsA("JointInstance") or w:IsA("WeldConstraint") or w:IsA("Attachment") or w:IsA("RigidConstraint") then
						w:Destroy()
					end
				end
				c.CFrame = head.CFrame:ToObjectSpace(handle.CFrame)
				c.Parent = model
			end
		end
	end
	local _, size = model:GetBoundingBox()
	model:ScaleTo(model:GetScale() * radius * 2.15 / math.max(size.X, size.Y, size.Z, 0.01))
	local box = model:GetBoundingBox()
	model:PivotTo(box:Inverse() * model:GetPivot())
	-- the pivot at the middle of head and hair together, not the head's own centre (the owner:
	-- "head ball slightly higher than actual")
	h.PivotOffset = h.CFrame:Inverse()
	return model
end

-- The winter balls' pieces round the core (LOOKS' extra), each its own shapes. Positions are
-- around the origin, the ball's centre; `r` the ball's radius.
local function bit(model, props)
	local p = Instance.new("Part")
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = model
	return p
end

local function cone(model, at, w, h, color)
	local p = bit(model, { Size = Vector3.new(w, h, w), CFrame = CFrame.new(at + Vector3.new(0, h / 2, 0)), Color = color })
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.FileMesh
	m.MeshId = "rbxassetid://1033714" -- (the cone: 1.7 across and 0.74 tall at scale 1)
	m.Scale = Vector3.new(w / 1.7, h / 0.74, w / 1.7)
	m.Parent = p
	return p
end

-- points spread evenly over a sphere (a golden-angle spiral)
local function spread(n)
	local out = {}
	for i = 0, n - 1 do
		local y = 1 - (i + 0.5) / n * 2
		local rr = math.sqrt(1 - y * y)
		local a = i * 2.39996
		table.insert(out, Vector3.new(math.cos(a) * rr, y, math.sin(a) * rr))
	end
	return out
end

local EXTRAS = {}

-- a hand-packed snowball: lumps of snow pressed into it
function EXTRAS.snowball(model, core, r)
	local rng = Random.new(3)
	for _, d in ipairs(spread(9)) do
		local s = r * (0.5 + rng:NextNumber() * 0.25)
		bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * s, CFrame = CFrame.new(d * r * 0.78), Color = Color3.fromRGB(246, 250, 255), Material = Enum.Material.Snow })
	end
end

-- a Christmas bauble: the crimped cap on top, its wire loop, a band of red gems round the middle
-- and a line of frost dots above and below it
function EXTRAS.bauble(model, core, r)
	local capColor = Color3.fromRGB(226, 214, 190)
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.32, r * 0.5, r * 0.5), CFrame = CFrame.new(0, r * 0.98, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = capColor, Material = Enum.Material.Metal, Reflectance = 0.3 })
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.08, r * 0.58, r * 0.58), CFrame = CFrame.new(0, r * 0.84, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = capColor, Material = Enum.Material.Metal, Reflectance = 0.3 })
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.07, CFrame = CFrame.new(math.cos(a) * r * 0.16, r * 1.3 + math.sin(a) * r * 0.16, 0), Color = capColor, Material = Enum.Material.Metal })
	end
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		local gem = k % 2 == 0
		bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * (gem and 0.2 or 0.11), CFrame = CFrame.new(math.cos(a) * r * 0.97, 0, math.sin(a) * r * 0.97), Color = gem and Color3.fromRGB(220, 24, 44) or Color3.fromRGB(255, 236, 160), Material = gem and Enum.Material.Glass or Enum.Material.Neon, Reflectance = gem and 0.3 or 0 })
	end
	for _, lat in ipairs({ -0.5, 0.5 }) do
		local y, rr = math.sin(lat) * r * 0.99, math.cos(lat) * r * 0.99
		for k = 0, 15 do
			local a = (k + (lat > 0 and 0.5 or 0)) / 16 * math.pi * 2
			bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.08, CFrame = CFrame.new(math.cos(a) * rr, y, math.sin(a) * rr), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon })
		end
	end
end

-- an ice crystal: a glowing core in a cluster of long glass shards, diamond in section, each with
-- a sharp tip
function EXTRAS.crystal(model, core, r)
	local rng = Random.new(8)
	for i, d in ipairs(spread(14)) do
		local len = r * (0.95 + rng:NextNumber() * 0.45)
		local w = r * (0.3 + rng:NextNumber() * 0.12)
		local look = CFrame.lookAt(Vector3.zero, d) * CFrame.Angles(0, 0, math.rad(45)) -- (-Z along the shard, turned so an edge faces out)
		bit(model, { Size = Vector3.new(w, w, len), CFrame = look * CFrame.new(0, 0, -len * 0.42), Color = i % 3 == 0 and Color3.fromRGB(200, 240, 255) or Color3.fromRGB(150, 215, 255), Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.25 })
		bit(model, { Size = Vector3.one * w * 0.62, CFrame = look * CFrame.new(0, 0, -len * 0.92) * CFrame.Angles(math.rad(45), math.rad(45), 0), Color = Color3.fromRGB(225, 248, 255), Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.3 })
	end
end

-- a jingle bell: the slot across its lower half (a dark band with a round hole at each end), a
-- rim round the middle, a loop on top and a red bow tied through it
function EXTRAS.jingle(model, core, r)
	local dark = Color3.fromRGB(70, 40, 10)
	bit(model, { Size = Vector3.new(r * 1.5, r * 0.12, r * 0.4), CFrame = CFrame.new(0, -r * 0.62, 0), Color = dark })
	for _, x in ipairs({ -0.75, 0.75 }) do
		bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.28, CFrame = CFrame.new(x * r, -r * 0.52, 0), Color = dark })
	end
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.06, r * 2.03, r * 2.03), CFrame = CFrame.new(0, -r * 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(200, 140, 30), Material = Enum.Material.Metal })
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.1, CFrame = CFrame.new(0, r * 1.18 + math.sin(a) * r * 0.2, math.cos(a) * r * 0.2), Color = Color3.fromRGB(255, 196, 50), Material = Enum.Material.Metal })
	end
	local red = Color3.fromRGB(214, 26, 44)
	for _, side in ipairs({ -1, 1 }) do
		bit(model, { Size = Vector3.new(r * 0.5, r * 0.34, r * 0.12), CFrame = CFrame.new(side * r * 0.3, r * 1.0, r * 0.05) * CFrame.Angles(0, 0, math.rad(side * -20)), Color = red, Material = Enum.Material.Fabric })
		bit(model, { Size = Vector3.new(r * 0.12, r * 0.4, r * 0.08), CFrame = CFrame.new(side * r * 0.16, r * 0.72, r * 0.1) * CFrame.Angles(0, 0, math.rad(side * 18)), Color = red, Material = Enum.Material.Fabric })
	end
	bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.2, CFrame = CFrame.new(0, r * 1.0, r * 0.08), Color = Color3.fromRGB(170, 14, 30), Material = Enum.Material.Fabric })
end

-- a Christmas pudding's sprig of holly on top of the custard: two leaves and three berries
function EXTRAS.pudding(model, core, r)
	local leaf = Color3.fromRGB(24, 120, 56)
	for _, side in ipairs({ -1, 1 }) do
		bit(model, { Size = Vector3.new(r * 0.62, r * 0.06, r * 0.26), CFrame = CFrame.new(side * r * 0.28, r * 1.0, 0) * CFrame.Angles(0, math.rad(side * 25), math.rad(side * 14)), Color = leaf })
		bit(model, { Size = Vector3.new(r * 0.5, r * 0.065, r * 0.04), CFrame = CFrame.new(side * r * 0.28, r * 1.02, 0) * CFrame.Angles(0, math.rad(side * 25), math.rad(side * 14)), Color = Color3.fromRGB(12, 70, 30) })
	end
	for k, at in ipairs({ Vector3.new(-0.08, 1.06, 0.06), Vector3.new(0.09, 1.07, 0.04), Vector3.new(0, 1.05, -0.1) }) do
		bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * (k == 1 and 0.2 or 0.18), CFrame = CFrame.new(at * r), Color = Color3.fromRGB(206, 20, 40), Reflectance = 0.15 })
	end
end

-- a snowman's head: coal eyes and a smile of coal, a carrot nose, a little black top hat with a
-- red band (the face to the front, -Z; the hat a little tipped)
function EXTRAS.snowman(model, core, r)
	core.Material = Enum.Material.Snow
	local coal = Color3.fromRGB(24, 22, 26)
	for _, x in ipairs({ -0.32, 0.32 }) do
		bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.2, CFrame = CFrame.new(x * r, r * 0.26, -r * 0.92), Color = coal })
	end
	for k = -2, 2 do
		local a = k * 0.28
		bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.12, CFrame = CFrame.new(math.sin(a) * r * 0.42, -r * 0.22 - math.cos(a) * r * 0.08, -r * 0.92), Color = coal })
	end
	local nose = bit(model, { Size = Vector3.new(r * 0.24, r * 0.6, r * 0.24), CFrame = CFrame.new(0, 0, -r * 1.2) * CFrame.Angles(math.rad(-90), 0, 0), Color = Color3.fromRGB(255, 120, 30) })
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.FileMesh
	m.MeshId = "rbxassetid://1033714"
	m.Scale = Vector3.new(r * 0.24 / 1.7, r * 0.6 / 0.74, r * 0.24 / 1.7)
	m.Parent = nose
	local tip = CFrame.new(0, r * 0.86, 0) * CFrame.Angles(0, 0, math.rad(-12))
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.06, r * 1.1, r * 1.1), CFrame = tip * CFrame.Angles(0, 0, math.rad(90)), Color = coal })
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.62, r * 0.66, r * 0.66), CFrame = tip * CFrame.new(0, r * 0.33, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = coal })
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.12, r * 0.68, r * 0.68), CFrame = tip * CFrame.new(0, r * 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(214, 30, 44) })
end

-- a wreath: clusters of red berries round it and a red bow on top with its tails
function EXTRAS.wreath(model, core, r)
	local berry = Color3.fromRGB(206, 20, 40)
	for _, d in ipairs(spread(7)) do
		if d.Y < 0.7 then
			local side = d:Cross(Vector3.yAxis)
			side = side.Magnitude > 0.01 and side.Unit or Vector3.xAxis
			local up = side:Cross(d).Unit
			for k = 0, 2 do
				local a = k * 2.1
				local off = (side * math.cos(a) + up * math.sin(a)) * r * 0.09
				bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.16, CFrame = CFrame.new(d * r * 0.98 + off), Color = berry, Reflectance = 0.15 })
			end
		end
	end
	local red = Color3.fromRGB(214, 26, 44)
	for _, side in ipairs({ -1, 1 }) do
		bit(model, { Size = Vector3.new(r * 0.55, r * 0.38, r * 0.14), CFrame = CFrame.new(side * r * 0.32, r * 1.02, 0) * CFrame.Angles(0, 0, math.rad(side * -18)), Color = red, Material = Enum.Material.Fabric })
		bit(model, { Size = Vector3.new(r * 0.16, r * 0.6, r * 0.08), CFrame = CFrame.new(side * r * 0.22, r * 0.62, -r * 0.62) * CFrame.Angles(math.rad(-40), 0, math.rad(side * 14)), Color = red, Material = Enum.Material.Fabric })
	end
	bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.24, CFrame = CFrame.new(0, r * 1.02, 0), Color = Color3.fromRGB(170, 14, 30), Material = Enum.Material.Fabric })
end

-- the North Star: a soft gold glow round its middle (a see-through neon ball inside the points)
function EXTRAS.starGlow(model, core, r)
	bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.9, CFrame = CFrame.new(), Color = Color3.fromRGB(255, 226, 130), Material = Enum.Material.Neon, Transparency = 0.35 })
end

-- a snow globe: clear glass, a snowy floor inside with a little lit pine, a snowman and a gift,
-- snow swirling round them, on a wooden stand with a gold rim
function EXTRAS.globe(model, core, r)
	core.Transparency = 0.62
	local floorY = -r * 0.36
	local fw = r * 2 * math.sqrt(1 - 0.36 * 0.36) * 0.96
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.3, fw, fw), CFrame = CFrame.new(0, floorY - r * 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(245, 250, 255), Material = Enum.Material.Snow })
	local pine = Color3.fromRGB(30, 120, 64)
	bit(model, { Size = Vector3.new(r * 0.08, r * 0.14, r * 0.08), CFrame = CFrame.new(r * 0.18, floorY + r * 0.07, r * 0.05), Color = Color3.fromRGB(90, 56, 30) })
	cone(model, Vector3.new(r * 0.18, floorY + r * 0.1, r * 0.05), r * 0.6, r * 0.5, pine)
	cone(model, Vector3.new(r * 0.18, floorY + r * 0.38, r * 0.05), r * 0.42, r * 0.42, pine)
	bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.12, CFrame = CFrame.new(r * 0.18, floorY + r * 0.84, r * 0.05), Color = Color3.fromRGB(255, 214, 80), Material = Enum.Material.Neon })
	for k, c in ipairs({ Color3.fromRGB(255, 70, 70), Color3.fromRGB(90, 230, 120), Color3.fromRGB(255, 206, 80), Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 206, 80) }) do
		local a = k * 1.9
		local y = floorY + r * (0.16 + k * 0.08)
		local rr = r * (0.26 - k * 0.025)
		bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.06, CFrame = CFrame.new(r * 0.18 + math.cos(a) * rr, y, r * 0.05 + math.sin(a) * rr), Color = c, Material = Enum.Material.Neon })
	end
	local sx, sz = -r * 0.32, -r * 0.1
	bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.26, CFrame = CFrame.new(sx, floorY + r * 0.12, sz), Color = Color3.fromRGB(250, 252, 255), Material = Enum.Material.Snow })
	bit(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.18, CFrame = CFrame.new(sx, floorY + r * 0.31, sz), Color = Color3.fromRGB(250, 252, 255), Material = Enum.Material.Snow })
	bit(model, { Size = Vector3.new(r * 0.03, r * 0.03, r * 0.1), CFrame = CFrame.new(sx, floorY + r * 0.32, sz - r * 0.1), Color = Color3.fromRGB(255, 120, 30) })
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.1, r * 0.12, r * 0.12), CFrame = CFrame.new(sx, floorY + r * 0.44, sz) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(24, 22, 26) })
	local gcf = CFrame.new(-r * 0.05, floorY + r * 0.06, r * 0.36) * CFrame.Angles(0, math.rad(25), 0)
	bit(model, { Size = Vector3.one * r * 0.13, CFrame = gcf, Color = Color3.fromRGB(214, 36, 52) })
	bit(model, { Size = Vector3.new(r * 0.135, r * 0.135, r * 0.03), CFrame = gcf, Color = Color3.fromRGB(255, 206, 70) })
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.34, r * 1.25, r * 1.25), CFrame = CFrame.new(0, -r * 0.98, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(96, 56, 32), Material = Enum.Material.Wood })
	bit(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(r * 0.07, r * 1.3, r * 1.3), CFrame = CFrame.new(0, -r * 0.82, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 200, 80), Material = Enum.Material.Metal, Reflectance = 0.3 })
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, r * 0.1, 0)
	att.Parent = core
	local e = Instance.new("ParticleEmitter")
	e.Texture = Assets.id(Assets.Fx.Dot) or ""
	e.Color = ColorSequence.new(Color3.new(1, 1, 1))
	e.LightEmission = 0.6
	e.LightInfluence = 0
	e.Size = NumberSequence.new(r * 0.07)
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Rate = 30
	e.Speed = NumberRange.new(r * 0.2, r * 0.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 2
	e.LockedToPart = true
	e.Parent = att
end

local function build(key, radius, owner)
	local model
	if key == "BigHead" then
		model = bigHead(radius, owner)
	else
		local look = LOOKS[key]
		if not look then
			return nil
		end
		model = Instance.new("Model")
		model.Name = "BallSkin"
		local core = mesh(look.mesh or "BallSphere")
		if core then
			local across = radius * 2 * (look.span or 1)
			if look.fit then
				core.Size = core.Size * (across / math.max(core.Size.X, core.Size.Y, core.Size.Z, 0.01))
				-- upright: Studio's 3D importer turns a mesh's pivot a quarter over (the older balls
				-- were tuned with it turned, so only these undo it)
				core.PivotOffset = CFrame.new()
			else
				core.Size = Vector3.one * across * (look.coreScale or 1)
			end
			if look.texture then
				core.TextureID = Assets.id(Assets.BallSkins[look.texture]) or ""
			end
			core.Color = look.color
			core.Material = look.material or Enum.Material.SmoothPlastic
		else
			core = ball(radius * (look.coreScale or 1), look.color)
			core.Material = look.material or Enum.Material.SmoothPlastic
		end
		core.Reflectance = look.reflect or 0
		core.Name = "Core"
		core.CFrame = CFrame.new()
		core.Parent = model
		model.PrimaryPart = core
		if look.ring then
			local ring = mesh("BallRing")
			if ring then
				ring.Size = Vector3.new(radius * 4.2, radius * 0.06, radius * 4.2)
				ring.Color = look.ring
				ring.Material = Enum.Material.SmoothPlastic
				ring.Transparency = 0.1
				ring.CFrame = CFrame.Angles(math.rad(22), 0, math.rad(12))
				ring.Name = "Ring"
				ring.Parent = model
			end
		end
		dress(core, look, radius)
		if look.extra and EXTRAS[look.extra] then
			core.PivotOffset = CFrame.new() -- (upright: the importer's quarter turn would tip the pieces over)
			EXTRAS[look.extra](model, core, radius)
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			prep(d)
		end
	end
	return model
end

-- a skin that fails to build (a strange head, say) falls back to the classic look
function BallSkins.build(key, radius, owner)
	local ok, model = pcall(build, key, radius, owner)
	if not ok then
		warn("[SpikeRush] ball skin " .. tostring(key) .. " failed: " .. tostring(model))
		return nil
	end
	return model
end

return BallSkins
