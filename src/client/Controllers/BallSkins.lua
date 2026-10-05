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
	return model
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
			core.Size = Vector3.one * radius * 2 * (look.span or 1)
			if look.texture then
				core.TextureID = Assets.id(Assets.BallSkins[look.texture]) or ""
			end
			core.Color = look.color
			core.Material = look.material or Enum.Material.SmoothPlastic
		else
			core = ball(radius, look.color)
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
