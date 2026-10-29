-- Builds the arena procedurally: a fixed core and a court scene swapped at every match start.
--
-- Laid out for the side-view camera: the camera looks from the open near side (x < 0) across
-- the court, so the stands, screens, LED boards and scenery live on the far side (x > 0) and
-- the two ends, and nothing tall sits between the camera and the play.
--
--   Arena.Floor, Net, NetBarrier, Bounds, LobbySpawn   the core: built once, the same on every
--        court (players never lose the floor under them when the court changes)
--   Arena.Scene   the court (Config.Courts): the paint and lines, stands, walls or scenery,
--        LEDBoards, Jumbotron (its "Screen" parts carry a Face attribute; the client draws the
--        score on them), lights. `setCourt(id)` rebuilds it and sets the court's lighting;
--        the Arena and the Scene carry the court id in their "Court" attribute.
--
-- Scenery props use a Toolbox model when one is in ReplicatedStorage.ToolboxAssets.Models
-- (PalmTree, BeachUmbrella, Column; scaled to height and stood on the ground), else parts.
--
-- Everything is generated from Config.Court so the visuals always match the physics. To bake
-- the arena into your place for hand-editing, run this in the Studio command bar (edit mode)
-- and save the place; a baked arena's core is kept at runtime:
--   require(game.ServerScriptService.Server.Services.ArenaBuilder).build({ bake = true })

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Assets = require(Shared.Assets)

local ArenaBuilder = {}

local C = Config.Court
local LEN = C.SideDepth / 30 -- the hall was laid out for 30-stud half courts; stretch along z
local WHITE = Color3.fromRGB(248, 248, 244)
local HOME = Config.Teams.Home.Color
local AWAY = Config.Teams.Away.Color
local INK = Config.UI.Ink
local CHALK = Config.UI.Chalk
local DISPLAY = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

local function part(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- purely visual: no collision, no raycasts, no shadows
local function deco(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y

local function cylinder(parent, name, height, diameter, base, color, material)
	return deco(part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(base + Vector3.new(0, height / 2, 0)) * VERTICAL, color, material, { Shape = Enum.PartType.Cylinder }))
end

-- an ellipsoid (a Ball part can't stretch, a sphere mesh can)
local function ball(parent, name, size, pos, color, material)
	local p = deco(part(parent, name, size, CFrame.new(pos), color, material))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function banner(parent, name, size, cf, face, text, color, back)
	local p = deco(part(parent, name, size, cf, back or INK, Enum.Material.SmoothPlastic))
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 0.2
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.94, 0.86)
	label.Position = UDim2.fromScale(0.03, 0.07)
	label.Text = text
	label.TextScaled = true
	label.FontFace = DISPLAY
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = INK
	stroke.Parent = label
	return p
end

------------------------------------------------------------------------------------------
-- the core
------------------------------------------------------------------------------------------

local function buildNet(arena)
	local net = Instance.new("Model")
	net.Name = "Net"
	net.Parent = arena
	local netH = C.NetTop - C.NetBottom
	local postX = C.NetHalfWidth + 0.9
	local postH = C.NetTop + 1.2

	for _, sx in ipairs({ -1, 1 }) do
		part(net, "Post", Vector3.new(postH, 0.7, 0.7), CFrame.new(sx * postX, postH / 2, 0) * VERTICAL, Color3.fromRGB(214, 218, 230), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		-- the chunky pad covers most of the post, the landmark in the middle of the side view;
		-- each court colours it (setCourt)
		part(net, "PostPad", Vector3.new(C.NetTop * 0.62, 2.2, 2.2), CFrame.new(sx * postX, C.NetTop * 0.31, 0) * VERTICAL, Color3.fromRGB(38, 110, 235), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
		deco(part(net, "PadRing", Vector3.new(0.3, 2.3, 2.3), CFrame.new(sx * postX, C.NetTop * 0.62, 0) * VERTICAL, WHITE, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder }))
		deco(part(net, "Cable", Vector3.new(0.9, 0.08, 0.08), CFrame.new(sx * (C.NetHalfWidth + 0.45), C.NetTop - 0.1, 0), Color3.fromRGB(60, 60, 70)))
	end

	deco(part(net, "TopTape", Vector3.new(C.NetHalfWidth * 2, 0.34, 0.14), CFrame.new(0, C.NetTop - 0.17, 0), WHITE, Enum.Material.Fabric))
	deco(part(net, "BottomTape", Vector3.new(C.NetHalfWidth * 2, 0.16, 0.1), CFrame.new(0, C.NetBottom + 0.08, 0), WHITE, Enum.Material.Fabric))
	for _, sx in ipairs({ -1, 1 }) do
		deco(part(net, "SideTape", Vector3.new(0.22, netH, 0.12), CFrame.new(sx * C.HalfWidth, C.NetBottom + netH / 2, 0), WHITE, Enum.Material.Fabric))
	end

	-- the mesh: thin strands the client ripples when the ball hits the net
	local mesh = folder(net, "Mesh")
	local strand = Color3.fromRGB(26, 28, 38)
	local cols = math.floor(C.NetHalfWidth * 2 / 1.6)
	for i = 0, cols do
		local x = -C.NetHalfWidth + i * (C.NetHalfWidth * 2 / cols)
		deco(part(mesh, "V", Vector3.new(0.05, netH - 0.35, 0.05), CFrame.new(x, C.NetBottom + netH / 2, 0), strand))
	end
	for j = 1, 4 do
		deco(part(mesh, "H", Vector3.new(C.NetHalfWidth * 2, 0.05, 0.05), CFrame.new(0, C.NetBottom + j * netH / 5, 0), strand))
	end

	-- antennae
	local antBottom = C.NetBottom
	local antTop = C.NetTop + C.AntennaHeight
	local segs = 10
	local segH = (antTop - antBottom) / segs
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, segs - 1 do
			local col = WHITE
			if i % 2 == 0 then
				col = Color3.fromRGB(235, 40, 60)
			end
			deco(part(net, "Antenna", Vector3.new(segH, 0.16, 0.16), CFrame.new(sx * C.HalfWidth, antBottom + segH * (i + 0.5), 0.09) * VERTICAL, col, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder }))
		end
	end

	-- players can never cross under or around the net
	pcall(function()
		PhysicsService:RegisterCollisionGroup("NetBarrier")
	end)
	-- frictionless: a player pressed on it (blocking right at the net) slid up it slowly and lost
	-- the jump, which ended the block
	part(arena, "NetBarrier", Vector3.new(C.WallHalfX * 2 + 40, C.CeilingY, 0.6), CFrame.new(-20, C.CeilingY / 2, 0), WHITE, nil, {
		Transparency = 1,
		CastShadow = false,
		CollisionGroup = "NetBarrier",
		CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1),
	})

	-- referee stand on the far side, behind the net
	local rx = C.NetHalfWidth + 3.4
	local refY = C.NetTop * 0.67
	deco(part(net, "RefPlatform", Vector3.new(2.6, 0.3, 2.6), CFrame.new(rx, refY, 0), Color3.fromRGB(50, 54, 70), Enum.Material.Metal))
	for _, ox in ipairs({ -1, 1 }) do
		for _, oz in ipairs({ -1, 1 }) do
			deco(part(net, "RefLeg", Vector3.new(0.2, refY, 0.2), CFrame.new(rx + ox * 1.1, refY / 2, oz * 1.1), Color3.fromRGB(180, 184, 196), Enum.Material.Metal))
		end
	end
end

local function buildCore(arena)
	local W, D = C.WallHalfX, C.WallHalfZ
	part(arena, "Floor", Vector3.new(W * 2 + 40, 2, D * 2 + 4), CFrame.new(-20, -1, 0), Color3.fromRGB(176, 124, 78), Enum.Material.WoodPlanks)
	buildNet(arena)

	-- the hall's walls as invisible bounds, so every court holds the players in the same box
	local bounds = folder(arena, "Bounds")
	local wallH = C.CeilingY + 2
	local clear = { Transparency = 1, CastShadow = false, CanQuery = false }
	part(bounds, "WallFar", Vector3.new(2, wallH, D * 2 + 4), CFrame.new(W + 1, wallH / 2, 0), WHITE, nil, clear)
	part(bounds, "WallHome", Vector3.new(W + 40, wallH, 2), CFrame.new(W / 2 - 20, wallH / 2, -(D + 1)), WHITE, nil, clear)
	part(bounds, "WallAway", Vector3.new(W + 40, wallH, 2), CFrame.new(W / 2 - 20, wallH / 2, D + 1), WHITE, nil, clear)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(C.LobbySpawn)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = arena
end

------------------------------------------------------------------------------------------
-- scene kit
------------------------------------------------------------------------------------------

-- The court paint: the free zone, the court, the darker front zones and the lines.
-- p = { free, court, front, line, material, lineWidth, noFree, gloss (a polished floor's shine) }
local function paint(scene, p)
	local fx, fz = C.HalfWidth + C.FreeZoneSide, C.SideDepth + C.FreeZoneEnd
	local mat = p.material or Enum.Material.SmoothPlastic
	local shine = { Reflectance = p.gloss or 0 }
	if not p.noFree then
		deco(part(scene, "FreeZone", Vector3.new(fx * 2, 0.05, fz * 2), CFrame.new(0, 0.025, 0), p.free, mat, shine))
	end
	deco(part(scene, "Court", Vector3.new(C.HalfWidth * 2, 0.04, C.SideDepth * 2), CFrame.new(0, 0.06, 0), p.court, mat, shine))
	if p.front then
		for _, sz in ipairs({ -1, 1 }) do
			deco(part(scene, "FrontZone", Vector3.new(C.HalfWidth * 2, 0.04, C.AttackLine), CFrame.new(0, 0.07, sz * C.AttackLine / 2), p.front, mat, shine))
		end
	end

	local lines = folder(scene, "Lines")
	local LW = p.lineWidth or C.LineWidth
	local col = p.line or WHITE
	local function line(name, sx, sz, x, z)
		deco(part(lines, name, Vector3.new(sx, 0.03, sz), CFrame.new(x, 0.095, z), col, p.lineMaterial))
	end
	line("SidelineNear", LW, C.SideDepth * 2, -(C.HalfWidth - LW / 2), 0)
	line("SidelineFar", LW, C.SideDepth * 2, C.HalfWidth - LW / 2, 0)
	line("EndLineHome", C.HalfWidth * 2, LW, 0, -(C.SideDepth - LW / 2))
	line("EndLineAway", C.HalfWidth * 2, LW, 0, C.SideDepth - LW / 2)
	line("CentreLine", C.HalfWidth * 2, LW, 0, 0)
	line("AttackLineHome", C.HalfWidth * 2, LW, 0, -C.AttackLine)
	line("AttackLineAway", C.HalfWidth * 2, LW, 0, C.AttackLine)
	for _, sz in ipairs({ -1, 1 }) do
		for i = 0, 3 do
			line("AttackDash", 0.9, LW, C.HalfWidth + 0.9 + i * 1.8, sz * C.AttackLine)
		end
		line("ServiceTick", LW, 1.2, C.HalfWidth - LW / 2, sz * (C.SideDepth + 1.1))
	end
end

-- Stepped stands (the client seats the crowd on the same rows). shade(row) -> colour.
local function stands(scene, id, shade, material)
	local f = folder(scene, "Stands")
	for _, row in ipairs(Court.standRows(id)) do
		local size
		if row.axis == "X" then
			size = Vector3.new(row.depth, row.top, row.length)
		else
			size = Vector3.new(row.length, row.top, row.depth)
		end
		local p = part(f, "Row", size, CFrame.new(row.center.X, row.top / 2, row.center.Z), shade(row), material or Enum.Material.SmoothPlastic)
		p.CastShadow = false
	end
	return f
end

-- Where the far stands end (x), for the wall or scenery behind them.
local function standsBack(id)
	local S = Court.stands(id)
	return S.FarStart + S.Rows * S.RowDepth
end

-- The score screens: one each side of the net, standing courtside in front of the far stands.
-- Anything high on the far wall runs into the HUD's scoreboard as the camera climbs with the
-- ball; down here they stay in the lower half of the frame at every camera height.
-- spec = { frame, material, z, w, h }
-- up over the players' heads (the owner: "text covers map": at 3.2 they sat behind the court and
-- covered the players in closer camera shots)
local SCREEN_BASE = 12.5
local function screens(scene, spec)
	local jumbo = Instance.new("Model")
	jumbo.Name = "Jumbotron"
	jumbo.Parent = scene
	local frame = spec.frame or CHALK
	local mat = spec.material or Enum.Material.Metal
	local h, w = spec.h or 6, spec.w or 14
	local x = Court.Stands.FarStart - 1.4
	local y = SCREEN_BASE + h / 2
	for _, sz in ipairs({ -1, 1 }) do
		local z = sz * (spec.z or 33)
		local s = deco(part(jumbo, "Screen", Vector3.new(0.8, h, w), CFrame.new(x, y, z), Color3.fromRGB(16, 18, 28), Enum.Material.Metal))
		s:SetAttribute("Face", "Left")
		deco(part(jumbo, "Frame", Vector3.new(1, h + 0.8, w + 0.8), CFrame.new(x + 0.2, y, z), frame, mat))
		deco(part(jumbo, "Stand", Vector3.new(1, SCREEN_BASE, w * 0.4), CFrame.new(x + 0.2, SCREEN_BASE / 2, z), frame, mat))
	end
	return jumbo
end

-- LED boards along the far side of the free zone and (unless `sidesOnly`) at both ends; the
-- client scrolls a ticker on them.
local function ledBoards(scene, sidesOnly)
	local led = folder(scene, "LEDBoards")
	local bx = C.HalfWidth + C.FreeZoneSide + 1.5
	local bz = C.SideDepth + C.FreeZoneEnd + 1.5
	for _, z in ipairs({ -24 * LEN, 0, 24 * LEN }) do
		local b = part(led, "LED", Vector3.new(0.6, 2.6, 23.5 * LEN), CFrame.new(bx, 1.3, z), INK)
		b:SetAttribute("Face", Enum.NormalId.Left.Name)
	end
	if not sidesOnly then
		for _, sz in ipairs({ -1, 1 }) do
			local b = part(led, "LED", Vector3.new(34, 2.6, 0.6), CFrame.new(8, 1.3, sz * bz), INK)
			b:SetAttribute("Face", sz > 0 and Enum.NormalId.Front.Name or Enum.NormalId.Back.Name)
		end
	end
	return led
end

local function benches(scene)
	for _, sz in ipairs({ -1, 1 }) do
		local col = sz > 0 and AWAY or HOME
		part(scene, "Bench", Vector3.new(1.4, 1.3, 9), CFrame.new(C.HalfWidth + 5, 0.65, sz * 14 * LEN), col, Enum.Material.Fabric)
		deco(part(scene, "Bottle", Vector3.new(0.7, 0.35, 0.35), CFrame.new(C.HalfWidth + 4, 0.35, sz * 9.5 * LEN) * VERTICAL, col, Enum.Material.Glass, { Shape = Enum.PartType.Cylinder }))
	end
end

-- A Toolbox prop from ToolboxAssets.Models.<slot>, scaled to `height` and stood on `base`,
-- turned `yaw` degrees (plus the model's own "Yaw" attribute). Nil when the slot is empty.
local function toolboxProp(scene, slot, base, height, yaw)
	local root = ReplicatedStorage:FindFirstChild("ToolboxAssets")
	local models = root and root:FindFirstChild("Models")
	local src = models and models:FindFirstChild(slot)
	if not src then
		return nil
	end
	local m = src:Clone()
	if m:IsA("BasePart") then
		local holder = Instance.new("Model")
		m.Parent = holder
		m = holder
	end
	if not m:IsA("Model") then
		m:Destroy()
		return nil
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local ok = pcall(function()
		local _, size = m:GetBoundingBox()
		m:ScaleTo(m:GetScale() * height / math.max(0.1, size.Y))
		local cf, size2 = m:GetBoundingBox()
		m.WorldPivot = CFrame.new(cf.Position - Vector3.new(0, size2.Y / 2, 0))
		m:PivotTo(CFrame.new(base) * CFrame.Angles(0, math.rad((yaw or 0) + (src:GetAttribute("Yaw") or 0)), 0))
	end)
	if not ok then
		m:Destroy()
		return nil
	end
	m.Name = slot
	m.Parent = scene
	return m
end

-- A light source hidden in a transparent part.
local function lamp(parent, pos, kind, props)
	local holder = deco(part(parent, "Lamp", Vector3.new(0.5, 0.5, 0.5), CFrame.new(pos), WHITE, nil, { Transparency = 1 }))
	local l = Instance.new(kind)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = holder
	return holder
end

-- Daylight through a hall's high windows: a glass band along the far wall at `wx` from y0 to y1,
-- steel mullions and a transom, and a glowing stripe under it.
local function windowBand(scene, wx, y0, y1, glass, stripe)
	local D = C.WallHalfZ
	local steel = Color3.fromRGB(64, 68, 80)
	local mid = (y0 + y1) / 2
	deco(part(scene, "Windows", Vector3.new(0.4, y1 - y0, D * 2), CFrame.new(wx - 0.3, mid, 0), glass, Enum.Material.Neon, { Transparency = 0.42 }))
	for z = -D, D, 9 do
		deco(part(scene, "Mullion", Vector3.new(0.8, y1 - y0 + 0.6, 0.8), CFrame.new(wx - 0.7, mid, z), steel, Enum.Material.Metal))
	end
	deco(part(scene, "Transom", Vector3.new(0.8, 0.7, D * 2), CFrame.new(wx - 0.7, mid, 0), steel, Enum.Material.Metal))
	if stripe then
		deco(part(scene, "Stripe", Vector3.new(0.5, 0.6, D * 2), CFrame.new(wx - 0.5, y0 - 1.1, 0), stripe, Enum.Material.Neon))
	end
end

-- Late sun through the high windows (the owner, 2026-10-28: "the orange glow and feel of haikyuu
-- volleyball courts"): long shafts of light from the far wall's windows slanting down across the
-- stands to the floor, each two crossed glowing planes, and dust hanging in the light.
local function sunbeams(scene, wx, top, color)
	local f = folder(scene, "Sunbeams")
	for _, z in ipairs({ -54, -24, 6, 36, 62 }) do
		local from = Vector3.new(wx - 1, top, z)
		local to = Vector3.new(-6, 0, z - 14)
		local len = (to - from).Magnitude
		local base = CFrame.lookAt(from, to) * CFrame.new(0, 0, -len / 2)
		for i = 0, 1 do
			deco(part(f, "Beam", Vector3.new(7, 0.1, len), base * CFrame.Angles(0, 0, i * math.pi / 2), color, Enum.Material.Neon, { Transparency = 0.955 }))
		end
	end
	local haze = deco(part(f, "Dust", Vector3.new(60, 26, C.WallHalfZ * 1.6), CFrame.new(18, 18, 0), WHITE, nil, { Transparency = 1 }))
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = Assets.id(Assets.Fx.Dot) or ""
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Rate = 26
	dust.Lifetime = NumberRange.new(9, 14)
	dust.Speed = NumberRange.new(0.2, 0.5)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Size = NumberSequence.new(0.22)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(0.7, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.LightEmission = 1
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 220, 170))
	dust.Parent = haze
	return f
end

-- A cloth banner hung over the far stands, facing the camera: navy cloth, a stripe in `color`,
-- a ball mark and three words.
local function hangBanner(scene, pos, color, words)
	local cloth = deco(part(scene, "Hang", Vector3.new(0.3, 13, 6), CFrame.new(pos), Color3.fromRGB(18, 26, 56), Enum.Material.Fabric))
	deco(part(scene, "HangRod", Vector3.new(0.4, 0.4, 6.6), CFrame.new(pos + Vector3.new(0, 6.7, 0)), Color3.fromRGB(70, 74, 86), Enum.Material.Metal))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Left
	sg.LightInfluence = 0.5
	sg.PixelsPerStud = 20
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.Parent = cloth
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0.16, 0, 1, 0)
	stripe.Position = UDim2.fromScale(0.08, 0)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Parent = sg
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.fromScale(0.6, 0.07)
	mark.Size = UDim2.fromOffset(56, 56)
	mark.BackgroundTransparency = 1
	mark.Parent = sg
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.new(1, 1, 1)
	ring.Thickness = 5
	ring.Parent = mark
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = mark
	local seam = Instance.new("Frame")
	seam.AnchorPoint = Vector2.new(0.5, 0.5)
	seam.Position = UDim2.fromScale(0.5, 0.5)
	seam.Size = UDim2.new(1, 0, 0, 5)
	seam.Rotation = -30
	seam.BackgroundColor3 = color
	seam.BorderSizePixel = 0
	seam.Parent = mark
	local lines = Instance.new("TextLabel")
	lines.BackgroundTransparency = 1
	lines.AnchorPoint = Vector2.new(0.5, 0)
	lines.Position = UDim2.fromScale(0.6, 0.32)
	lines.Size = UDim2.fromScale(0.7, 0.6)
	lines.Text = table.concat(words, "\n")
	lines.TextScaled = true
	lines.FontFace = DISPLAY
	lines.TextColor3 = Color3.fromRGB(240, 242, 250)
	lines.Parent = sg
	return cloth
end

------------------------------------------------------------------------------------------
-- courts
------------------------------------------------------------------------------------------

-- A closed hall: far wall behind the stands, end walls, a ceiling with light panels, banners.
-- h = { wall, accentA, accentB, bannerText, bannerColor, bannerBack, ceiling, light, lightBrightness, wash }
local function hall(scene, id, h)
	local W, D = C.WallHalfX, C.WallHalfZ
	local wallH = C.CeilingY + 2
	local wx = math.max(W, standsBack(id) + 1)
	deco(part(scene, "WallFar", Vector3.new(2, wallH, D * 2 + 4), CFrame.new(wx + 1, wallH / 2, 0), h.wall))
	for _, sz in ipairs({ -1, 1 }) do
		deco(part(scene, "WallEnd", Vector3.new(wx + 60, wallH, 2), CFrame.new(wx / 2 - 30, wallH / 2, sz * (D + 1)), h.wall))
	end
	for _, y in ipairs({ 22, 50 }) do
		deco(part(scene, "Accent", Vector3.new(0.3, 0.35, D), CFrame.new(wx - 0.1, y, -D / 2), h.accentA))
		deco(part(scene, "Accent", Vector3.new(0.3, 0.35, D), CFrame.new(wx - 0.1, y, D / 2), h.accentB))
	end
	banner(scene, "BannerFarHome", Vector3.new(0.4, 8, 34 * LEN), CFrame.new(wx - 0.3, 54, -46 * LEN), Enum.NormalId.Left, string.upper(Config.Teams.Home.Name), HOME, h.bannerBack)
	banner(scene, "BannerFarAway", Vector3.new(0.4, 8, 34 * LEN), CFrame.new(wx - 0.3, 54, 46 * LEN), Enum.NormalId.Left, string.upper(Config.Teams.Away.Name), AWAY, h.bannerBack)
	banner(scene, "BannerHome", Vector3.new(50, 9, 0.4), CFrame.new(10, 40, -D + 0.3), Enum.NormalId.Back, h.bannerText, h.bannerColor, h.bannerBack)
	banner(scene, "BannerAway", Vector3.new(50, 9, 0.4), CFrame.new(10, 40, D - 0.3), Enum.NormalId.Front, h.bannerText, h.bannerColor, h.bannerBack)

	-- ceiling, and a light truss low enough for its lights to reach the floor
	deco(part(scene, "Ceiling", Vector3.new(wx * 2 + 40, 2, D * 2 + 4), CFrame.new(-20, C.CeilingY + 1, 0), h.ceiling))
	local lights = folder(scene, "Lights")
	local n = 0
	for _, x in ipairs({ -8, 8 }) do
		for _, z in ipairs({ -36 * LEN, -18 * LEN, 0, 18 * LEN, 36 * LEN }) do
			n = n + 1
			local panel = deco(part(lights, "Panel", Vector3.new(6, 0.5, 6), CFrame.new(x, 52, z), h.light))
			local sl = Instance.new("SurfaceLight")
			sl.Face = Enum.NormalId.Bottom
			sl.Angle = 85
			sl.Range = 60
			sl.Brightness = h.lightBrightness
			sl.Color = h.light
			sl.Shadows = n == 3 or n == 8
			sl.Parent = panel
		end
	end
	-- wash on the far stands so the crowd reads behind the play
	local S = Court.stands(id)
	for _, z in ipairs({ -40 * LEN, -14 * LEN, 14 * LEN, 40 * LEN }) do
		lamp(lights, Vector3.new(S.FarStart - 6, 30, z), "SpotLight", { Face = Enum.NormalId.Right, Angle = 70, Range = 50, Brightness = 0.6, Color = h.wash })
	end
	return wx
end

local function rails(scene, id, farColor)
	local S = Court.stands(id)
	deco(part(scene, "Rail", Vector3.new(0.25, 0.25, S.FarLength), CFrame.new(S.FarStart, S.BaseTop + 1.1, 0), farColor))
	if S.EndRows > 0 then
		deco(part(scene, "Rail", Vector3.new(S.EndLength, 0.25, 0.25), CFrame.new(S.EndLength * 0.25, S.BaseTop + 1.1, -S.EndStart), HOME))
		deco(part(scene, "Rail", Vector3.new(S.EndLength, 0.25, 0.25), CFrame.new(S.EndLength * 0.25, S.BaseTop + 1.1, S.EndStart), AWAY))
	end
end

-- The top of the stands dressed as a venue, not a block (the owner, 2026-10-29: the courts but
-- the Rush Arena were "small and lackluster", "quite plain"): a back wall rising `up` over the top
-- row with a band of name panels facing the court, flags on poles along it, and the same wall
-- behind each end stand. Returns the wall's top. o = { wall, material, trim, panel, words,
-- wordColors, flags, up }
local function crown(scene, id, o)
	local S = Court.stands(id)
	local f = folder(scene, "StandCrown")
	local top = S.BaseTop + (S.Rows - 1) * S.RowRise
	local back = standsBack(id)
	local up = o.up or 7
	local h = top + up
	deco(part(f, "BackWall", Vector3.new(1.2, h, S.FarLength + 2), CFrame.new(back + 0.6, h / 2, 0), o.wall, o.material))
	deco(part(f, "Trim", Vector3.new(1.8, 0.6, S.FarLength + 2), CFrame.new(back + 0.5, h + 0.3, 0), o.trim, Enum.Material.Metal))
	local n = #o.words
	local span = S.FarLength / n
	for i, word in ipairs(o.words) do
		local z = -S.FarLength / 2 + span * (i - 0.5)
		banner(f, "Panel", Vector3.new(0.4, up - 2.2, span - 3), CFrame.new(back - 0.2, top + 1.6 + (up - 2.2) / 2, z), Enum.NormalId.Left, word, o.wordColors[(i - 1) % #o.wordColors + 1], o.panel)
	end
	if o.flags then
		local k = 0
		for z = -S.FarLength / 2 + 6, S.FarLength / 2 - 5, 13 do
			k = k + 1
			deco(part(f, "FlagPole", Vector3.new(0.35, 9, 0.35), CFrame.new(back + 0.6, h + 4.5, z), o.trim, Enum.Material.Metal))
			deco(part(f, "Flag", Vector3.new(0.15, 3.2, 5), CFrame.new(back + 0.6, h + 7.2, z + 2.6), o.flags[(k - 1) % #o.flags + 1], Enum.Material.Fabric))
		end
	end
	if S.EndRows > 0 then
		local eh = S.BaseTop + (S.EndRows - 1) * S.RowRise + up - 2
		for _, sz in ipairs({ -1, 1 }) do
			local ez = sz * (S.EndStart + S.EndRows * S.RowDepth + 0.6)
			deco(part(f, "EndWall", Vector3.new(S.EndLength + 2, eh, 1.2), CFrame.new(S.EndLength * 0.25, eh / 2, ez), o.wall, o.material))
			deco(part(f, "EndTrim", Vector3.new(S.EndLength + 2, 0.6, 1.8), CFrame.new(S.EndLength * 0.25, eh + 0.3, ez), o.trim, Enum.Material.Metal))
		end
	end
	return h
end

local COURTS = {}

-- Rush Arena: the pro hall, as Home's (the owner, 2026-10-28: "i like how this arena looks"), in
-- the warm glow of an anime gym ("replicate the orange glow and feel of haikyuu volleyball
-- courts"): a polished orange court on a teal free zone, late sun through the high windows
-- slanting across the hall, dust in the light, warm lamps, a soft bloom; blue seats, banners hung
-- in front of the windows.
local ORANGE = Color3.fromRGB(255, 124, 28)
COURTS.Arena = {
	floor = { Color3.fromRGB(44, 40, 46), Enum.Material.SmoothPlastic },
	pad = ORANGE,
	paint = { free = Color3.fromRGB(22, 96, 132), court = Color3.fromRGB(232, 112, 36), front = Color3.fromRGB(214, 98, 30), gloss = 0.06 },
	light = {
		props = { Ambient = Color3.fromRGB(132, 112, 96), OutdoorAmbient = Color3.fromRGB(140, 118, 98), Brightness = 1.8, ClockTime = 17.2, EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.4, ExposureCompensation = -0.05, ShadowSoftness = 0.45 },
		bloom = { Intensity = 0.26, Size = 26, Threshold = 1.75 },
		grade = { Saturation = 0.18, Contrast = 0.14, Brightness = 0, TintColor = Color3.fromRGB(255, 234, 210) },
		atmo = { Density = 0.1, Haze = 0.45, Glare = 0.1, Color = Color3.fromRGB(255, 212, 172), Decay = Color3.fromRGB(214, 140, 90) },
		rays = { Intensity = 0.05, Spread = 0.6 },
	},
	build = function(scene, id)
		local wx = hall(scene, id, {
			wall = Color3.fromRGB(84, 78, 80),
			accentA = HOME,
			accentB = AWAY,
			bannerText = "VOLLEYBALL RUSH",
			bannerColor = CHALK,
			ceiling = Color3.fromRGB(96, 90, 90),
			light = Color3.fromRGB(255, 234, 200),
			lightBrightness = 1.4,
			wash = Color3.fromRGB(255, 224, 190),
		})
		stands(scene, id, function(row)
			if row.index % 2 == 0 then
				return Color3.fromRGB(40, 86, 180)
			end
			return Color3.fromRGB(32, 72, 156)
		end)
		rails(scene, id, ORANGE)
		windowBand(scene, wx, 23, 36, Color3.fromRGB(255, 196, 128), ORANGE)
		sunbeams(scene, wx, 32, Color3.fromRGB(255, 206, 140))
		for i, b in ipairs({ { -50, HOME, { "SERVE", "SPIKE", "RISE" } }, { -17, AWAY, { "ONE", "MORE", "POINT" } }, { 17, HOME, { "RULE", "THE", "NET" } }, { 50, AWAY, { "JUMP", "HIGHER", "HIT" } } }) do
			hangBanner(scene, Vector3.new(wx - 2.2, 31 + (i % 2) * 0.8, b[1]), b[2], b[3])
		end
		screens(scene, { frame = Color3.fromRGB(40, 44, 56) })
		ledBoards(scene)
		benches(scene)
	end,
}

-- Nationals: the championship hall. Blue court, green free zone, crimson stands, gold trim and a
-- bright, white rig.
COURTS.Nationals = {
	floor = { Color3.fromRGB(64, 66, 74), Enum.Material.SmoothPlastic },
	pad = Color3.fromRGB(236, 184, 44),
	paint = { free = Color3.fromRGB(22, 112, 92), court = Color3.fromRGB(46, 112, 196), front = Color3.fromRGB(36, 96, 176) },
	light = {
		props = { Ambient = Color3.fromRGB(104, 104, 112), OutdoorAmbient = Color3.fromRGB(104, 104, 112), Brightness = 1, ClockTime = 20.5, EnvironmentDiffuseScale = 0.35, EnvironmentSpecularScale = 0.3, ExposureCompensation = 0, ShadowSoftness = 0.4 },
		bloom = { Intensity = 0.25, Size = 20, Threshold = 1.9 },
		grade = { Saturation = 0.08, Contrast = 0.08, Brightness = 0, TintColor = Color3.fromRGB(248, 250, 255) },
		atmo = { Density = 0.12, Haze = 0.6, Glare = 0, Color = Color3.fromRGB(170, 176, 200), Decay = Color3.fromRGB(90, 96, 120) },
	},
	build = function(scene, id)
		local gold = Color3.fromRGB(236, 184, 44)
		local wx = hall(scene, id, {
			wall = Color3.fromRGB(24, 30, 64),
			accentA = gold,
			accentB = gold,
			bannerText = "NATIONALS",
			bannerColor = gold,
			ceiling = Color3.fromRGB(12, 12, 16),
			light = Color3.fromRGB(246, 249, 255),
			lightBrightness = 1.25,
			wash = Color3.fromRGB(255, 244, 230),
		})
		stands(scene, id, function(row)
			if row.index % 2 == 0 then
				return Color3.fromRGB(150, 30, 44)
			end
			return Color3.fromRGB(122, 22, 34)
		end)
		rails(scene, id, gold)
		-- the upper deck's fascia, a gold line with a ribbon of team colours
		local S = Court.stands(id)
		local deckY = S.BaseTop + S.Rows * S.RowRise + 1
		deco(part(scene, "Fascia", Vector3.new(0.4, 1.6, S.FarLength), CFrame.new(standsBack(id) + 0.4, deckY, 0), INK))
		deco(part(scene, "FasciaGold", Vector3.new(0.5, 0.3, S.FarLength), CFrame.new(standsBack(id) + 0.2, deckY + 0.9, 0), gold, Enum.Material.Metal))
		-- the ribbon board: a lit band of the championship's name round the deck (the owner,
		-- 2026-10-29: "quite plain")
		for i, word in ipairs({ "NATIONALS", "CHAMPIONSHIP", "VOLLEYBALL RUSH", "CHAMPIONSHIP", "NATIONALS" }) do
			local span = S.FarLength / 5
			banner(scene, "Ribbon", Vector3.new(0.4, 3, span - 1), CFrame.new(standsBack(id) - 0.1, deckY + 2.8, -S.FarLength / 2 + span * (i - 0.5)), Enum.NormalId.Left, word, i % 2 == 0 and CHALK or gold, Color3.fromRGB(12, 14, 34))
		end
		-- the skyboxes over the upper deck: a dark glass band of lit boxes, people in some of them
		local boxY = deckY + 7
		deco(part(scene, "Suites", Vector3.new(0.6, 10, C.WallHalfZ * 2), CFrame.new(wx - 0.4, boxY, 0), Color3.fromRGB(14, 16, 24), Enum.Material.Glass, { Transparency = 0.1, Reflectance = 0.15 }))
		local srng = Random.new(5)
		for z = -C.WallHalfZ + 4, C.WallHalfZ - 4, 6 do
			local warm = srng:NextNumber() < 0.7
			deco(part(scene, "SuiteLight", Vector3.new(0.3, 7.4, 5.2), CFrame.new(wx - 0.9, boxY, z), warm and Color3.fromRGB(255, 196, 132) or Color3.fromRGB(70, 74, 92), Enum.Material.Neon, { Transparency = warm and 0.5 or 0.65 }))
			for k = 1, srng:NextInteger(0, 3) do
				deco(part(scene, "SuiteFan", Vector3.new(0.4, 2.2, 1), CFrame.new(wx - 1.3, boxY - 2.6, z - 2 + k * 1.2), Color3.fromRGB(30, 26, 36)))
			end
		end
		deco(part(scene, "SuiteSill", Vector3.new(1.2, 0.6, C.WallHalfZ * 2), CFrame.new(wx - 1, boxY - 5.2, 0), gold, Enum.Material.Metal))
		-- championship flags hung over the stands, low enough to be seen
		local flags = { HOME, gold, AWAY, CHALK, HOME, gold, AWAY }
		for i, col in ipairs(flags) do
			local z = (i - 4) * 16 * LEN
			deco(part(scene, "Flag", Vector3.new(0.2, 12, 5), CFrame.new(wx - 4, boxY + 14, z), col, Enum.Material.Fabric))
			deco(part(scene, "FlagRod", Vector3.new(0.3, 0.3, 5.6), CFrame.new(wx - 4, boxY + 20.2, z), gold, Enum.Material.Metal))
		end
		-- trusses across the roof
		for _, x in ipairs({ -8, 8, 26 }) do
			deco(part(scene, "Truss", Vector3.new(1.2, 1.2, C.WallHalfZ * 2), CFrame.new(x, 55, 0), Color3.fromRGB(40, 42, 50), Enum.Material.Metal))
		end
		screens(scene, { frame = gold })
		ledBoards(scene)
		benches(scene)
	end,
}

local function palmTree(scene, base, height, lean, rng)
	if toolboxProp(scene, "PalmTree", base, height, rng:NextNumber() * 360) then
		return
	end
	local tree = Instance.new("Model")
	tree.Name = "PalmTree"
	tree.Parent = scene
	local trunk = Color3.fromRGB(128, 94, 62)
	local segs = 7
	local pos = base
	local dir = Vector3.new(lean.X, 1, lean.Z).Unit
	for i = 1, segs do
		local seg = height / segs
		local bend = (Vector3.new(0, 1, 0) + Vector3.new(lean.X, 0, lean.Z) * (1.4 - i / segs)).Unit
		dir = dir:Lerp(bend, 0.5).Unit
		local nextPos = pos + dir * seg
		local d = 1.5 - i * 0.08
		deco(part(tree, "Trunk", Vector3.new(seg + 0.2, d, d), CFrame.lookAt((pos + nextPos) / 2, nextPos) * CFrame.Angles(0, math.rad(90), 0), trunk, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder }))
		pos = nextPos
	end
	local leaf = Color3.fromRGB(58, 140, 70)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + rng:NextNumber() * 0.3
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local frond = 7 + rng:NextNumber() * 2
		local tip = pos + out * frond + Vector3.new(0, -2.4, 0)
		deco(part(tree, "Frond", Vector3.new(2.2, 0.2, frond), CFrame.lookAt((pos + tip) / 2, tip), k % 2 == 0 and leaf or leaf:Lerp(Color3.fromRGB(96, 170, 70), 0.4), Enum.Material.Grass))
	end
	ball(tree, "Coconuts", Vector3.new(1.6, 1.2, 1.6), pos - Vector3.new(0, 0.6, 0), Color3.fromRGB(96, 70, 40), Enum.Material.Wood)
end

local function umbrella(scene, base, colorA, colorB, rng)
	local yaw = rng:NextNumber() * 360
	if toolboxProp(scene, "BeachUmbrella", base, 8, yaw) then
		return
	end
	local m = Instance.new("Model")
	m.Name = "BeachUmbrella"
	m.Parent = scene
	cylinder(m, "Pole", 7.5, 0.25, base, Color3.fromRGB(236, 236, 230), Enum.Material.Metal)
	local top = base + Vector3.new(0, 7.5, 0)
	-- the canopy: eight tilted panels in two colours
	for k = 0, 7 do
		local a = (k + 0.5) / 8 * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local mid = top + out * 2.3 - Vector3.new(0, 0.6, 0)
		deco(part(m, "Canopy", Vector3.new(2.1, 0.12, 4.8), CFrame.lookAt(mid, top + out * 5 - Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, 0), k % 2 == 0 and colorA or colorB, Enum.Material.Fabric))
	end
	ball(m, "Cap", Vector3.new(0.6, 0.6, 0.6), top + Vector3.new(0, 0.2, 0), colorA)
	-- a towel under it
	deco(part(m, "Towel", Vector3.new(3, 0.06, 5.5), CFrame.new(base + Vector3.new(1.5, 0.03, 0)) * CFrame.Angles(0, math.rad(yaw), 0), colorB, Enum.Material.Fabric))
end

-- Sunset Beach: sand, a blue rope court, low bleachers, palms and umbrellas, the sea behind.
COURTS.Beach = {
	floor = { Color3.fromRGB(224, 198, 148), Enum.Material.Sand },
	pad = Color3.fromRGB(238, 98, 66),
	paint = { court = Color3.fromRGB(234, 210, 162), line = Color3.fromRGB(30, 100, 212), material = Enum.Material.Sand, lineWidth = C.LineWidth * 1.6, lineMaterial = Enum.Material.Fabric, noFree = true },
	light = {
		-- a clear blue afternoon (the owner, 2026-10-29: "sky looks too drab. brighten up the
		-- atmosphere. more blue"; it was a hazy pink dusk)
		props = { Ambient = Color3.fromRGB(128, 132, 140), OutdoorAmbient = Color3.fromRGB(160, 170, 184), Brightness = 2.8, ClockTime = 14.2, EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.3, ExposureCompensation = 0.1, ShadowSoftness = 0.25 },
		bloom = { Intensity = 0.35, Size = 24, Threshold = 1.5 },
		grade = { Saturation = 0.2, Contrast = 0.06, Brightness = 0.03, TintColor = Color3.fromRGB(244, 250, 255) },
		atmo = { Density = 0.2, Haze = 0.5, Glare = 0.2, Color = Color3.fromRGB(190, 224, 255), Decay = Color3.fromRGB(110, 176, 240) },
		rays = { Intensity = 0.06, Spread = 0.8 },
	},
	build = function(scene, id)
		local rng = Random.new(21)
		-- the sea from just past the far bounds to the horizon, with a strip of wet sand
		deco(part(scene, "WetSand", Vector3.new(18, 0.2, 700), CFrame.new(C.WallHalfX + 8, -0.05, 0), Color3.fromRGB(196, 168, 120), Enum.Material.Sand))
		deco(part(scene, "Surf", Vector3.new(3, 0.12, 700), CFrame.new(C.WallHalfX + 17.5, 0.12, 0), Color3.fromRGB(236, 244, 248), Enum.Material.SmoothPlastic, { Transparency = 0.2 }))
		-- (it stops well short of the menu rooms, which SceneController builds 1600 studs out)
		deco(part(scene, "Sea", Vector3.new(1100, 0.4, 2400), CFrame.new(C.WallHalfX + 17 + 550, -0.1, 0), Color3.fromRGB(34, 130, 190), Enum.Material.SmoothPlastic, { Reflectance = 0.15 }))
		-- low islands on the horizon (the first also hides the menu rooms behind it)
		-- (the first tall enough to hide the Home room's box behind it: the owner saw it)
		for _, isle in ipairs({ { 1040, -330, 440, 92 }, { 900, 240, 220, 30 }, { 1080, 640, 380, 40 } }) do
			ball(scene, "Island", Vector3.new(160, isle[4] * 2, isle[3]), Vector3.new(isle[1], 0, isle[2]), Color3.fromRGB(96, 124, 112), Enum.Material.Grass)
		end
		-- the sun over the sea, with a soft halo
		deco(part(scene, "Sun", Vector3.new(2, 56, 56), CFrame.new(980, 108, 230), Color3.fromRGB(255, 246, 214), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder }))
		deco(part(scene, "SunHalo", Vector3.new(1, 130, 130), CFrame.new(990, 108, 230), Color3.fromRGB(255, 230, 170), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, Transparency = 0.86 }))
		-- sand beyond the ends and the near side
		deco(part(scene, "Dunes", Vector3.new(300, 1, 400), CFrame.new(-100, -0.55, 0), Color3.fromRGB(224, 198, 148), Enum.Material.Sand))
		stands(scene, id, function(row)
			return row.index % 2 == 0 and Color3.fromRGB(190, 196, 206) or Color3.fromRGB(170, 176, 188)
		end, Enum.Material.Metal)
		local back = standsBack(id)
		-- the grandstands wrapped in the tour's blue, its name panels and flags along the top
		local crownTop = crown(scene, id, {
			wall = Color3.fromRGB(30, 100, 212), material = Enum.Material.Fabric, trim = CHALK, panel = CHALK,
			words = { "SUNSET BEACH", "VOLLEYBALL RUSH", "BEACH TOUR", "VOLLEYBALL RUSH", "SUNSET BEACH" },
			wordColors = { Color3.fromRGB(255, 124, 28), Color3.fromRGB(30, 100, 212) },
			flags = { HOME, Color3.fromRGB(250, 196, 40), AWAY, CHALK },
			up = 4.8,
		})
		-- palms behind the bleachers and along the ends
		for _, z in ipairs({ -84, -62, -38, 34, 60, 86 }) do
			palmTree(scene, Vector3.new(back + 4 + rng:NextNumber() * 6, 0, z + rng:NextNumber() * 4), 26 + rng:NextNumber() * 8, Vector3.new(rng:NextNumber() * 0.4, 0, (rng:NextNumber() - 0.5) * 0.6), rng)
		end
		for _, z in ipairs({ -92, 92 }) do
			palmTree(scene, Vector3.new(4, 0, z), 24, Vector3.new(0.3, 0, -z / math.abs(z) * 0.3), rng)
		end
		-- umbrellas at the ends of the court
		local stripes = {
			{ Color3.fromRGB(236, 64, 64), CHALK },
			{ Color3.fromRGB(250, 196, 40), Color3.fromRGB(40, 150, 220) },
			{ Color3.fromRGB(40, 190, 150), CHALK },
		}
		-- (clear of the end stands, which reach z = +-79)
		local spots = { Vector3.new(18, 0, -86), Vector3.new(6, 0, -96), Vector3.new(20, 0, 88), Vector3.new(4, 0, 98), Vector3.new(32, 0, -94) }
		for i, p in ipairs(spots) do
			local s = stripes[(i - 1) % #stripes + 1]
			umbrella(scene, p, s[1], s[2], rng)
		end
		-- a lifeguard tower down the Away end
		local tower = Instance.new("Model")
		tower.Name = "LifeguardTower"
		tower.Parent = scene
		local tz = 84
		for _, ox in ipairs({ -2, 2 }) do
			for _, oz in ipairs({ -2, 2 }) do
				deco(part(tower, "Leg", Vector3.new(0.5, 9, 0.5), CFrame.new(46 + ox, 4.5, tz + oz), CHALK, Enum.Material.Wood))
			end
		end
		deco(part(tower, "Hut", Vector3.new(5.5, 4, 5.5), CFrame.new(46, 11, tz), Color3.fromRGB(236, 72, 60), Enum.Material.Wood))
		deco(part(tower, "Roof", Vector3.new(6.5, 0.5, 6.5), CFrame.new(46, 13.25, tz), CHALK, Enum.Material.Wood))
		-- a white yacht lying off the point, in view over the stands
		local yacht = Instance.new("Model")
		yacht.Name = "Yacht"
		yacht.Parent = scene
		local yp = Vector3.new(C.WallHalfX + 170, 0, -26)
		deco(part(yacht, "Hull", Vector3.new(34, 4, 9), CFrame.new(yp + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, math.rad(84), 0), CHALK, Enum.Material.SmoothPlastic))
		deco(part(yacht, "Stripe", Vector3.new(34.2, 0.6, 9.2), CFrame.new(yp + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.rad(84), 0), Color3.fromRGB(30, 100, 212), Enum.Material.SmoothPlastic))
		deco(part(yacht, "Cabin", Vector3.new(16, 4, 7), CFrame.new(yp + Vector3.new(0, 5.4, 2)) * CFrame.Angles(0, math.rad(84), 0), CHALK, Enum.Material.SmoothPlastic))
		deco(part(yacht, "Windows", Vector3.new(14, 1.4, 7.2), CFrame.new(yp + Vector3.new(0, 5.8, 2)) * CFrame.Angles(0, math.rad(84), 0), Color3.fromRGB(30, 40, 60), Enum.Material.Glass))
		deco(part(yacht, "Bridge", Vector3.new(8, 2.6, 5.6), CFrame.new(yp + Vector3.new(0, 8.6, 3)) * CFrame.Angles(0, math.rad(84), 0), CHALK, Enum.Material.SmoothPlastic))
		-- out on the water: a sailboat, orange buoys marking the swim line, a pier with lamps
		local boat = Instance.new("Model")
		boat.Name = "Sailboat"
		boat.Parent = scene
		local bp = Vector3.new(C.WallHalfX + 120, 0, 18)
		deco(part(boat, "Hull", Vector3.new(16, 2.2, 5), CFrame.new(bp + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, math.rad(78), 0), CHALK, Enum.Material.SmoothPlastic))
		deco(part(boat, "Keel", Vector3.new(12, 0.6, 4.4), CFrame.new(bp + Vector3.new(0, 2.2, 0)) * CFrame.Angles(0, math.rad(78), 0), Color3.fromRGB(30, 100, 212), Enum.Material.SmoothPlastic))
		deco(part(boat, "Mast", Vector3.new(0.4, 22, 0.4), CFrame.new(bp + Vector3.new(0, 13, 0)), Color3.fromRGB(200, 204, 214), Enum.Material.Metal))
		local sail = Instance.new("WedgePart")
		sail.Name = "Sail"
		sail.Anchored = true
		sail.CanCollide = false
		sail.CanQuery = false
		sail.CanTouch = false
		sail.CastShadow = false
		sail.Size = Vector3.new(0.2, 19, 10)
		sail.CFrame = CFrame.new(bp + Vector3.new(0, 12.5, -5.2)) * CFrame.Angles(0, math.rad(-12), 0)
		sail.Color = Color3.fromRGB(255, 132, 34)
		sail.Material = Enum.Material.Fabric
		sail.Parent = boat
		for i = -3, 3 do
			ball(scene, "Buoy", Vector3.new(1.6, 1.6, 1.6), Vector3.new(C.WallHalfX + 52 + (i % 2) * 4, 0.4, i * 18), Color3.fromRGB(255, 124, 28), Enum.Material.SmoothPlastic)
		end
		local pier = Instance.new("Model")
		pier.Name = "Pier"
		pier.Parent = scene
		local pz = -54
		deco(part(pier, "Deck", Vector3.new(90, 0.8, 7), CFrame.new(C.WallHalfX + 60, 2.6, pz), Color3.fromRGB(150, 112, 74), Enum.Material.WoodPlanks))
		for x = C.WallHalfX + 18, C.WallHalfX + 102, 12 do
			for _, oz in ipairs({ -3.2, 3.2 }) do
				deco(part(pier, "Pile", Vector3.new(0.8, 6, 0.8), CFrame.new(x, 0, pz + oz), Color3.fromRGB(110, 82, 56), Enum.Material.Wood))
			end
			deco(part(pier, "LampPost", Vector3.new(0.3, 5, 0.3), CFrame.new(x, 5.4, pz + 3.2), Color3.fromRGB(46, 48, 58), Enum.Material.Metal))
			ball(pier, "LampGlobe", Vector3.new(0.9, 0.9, 0.9), Vector3.new(x, 8.1, pz + 3.2), Color3.fromRGB(255, 226, 170), Enum.Material.Neon)
		end
		-- pennant bunting over the bleachers between the palms, in both teams' colours
		local back2 = standsBack(id)
		local bunting = folder(scene, "Bunting")
		for _, span in ipairs({ { -70, -24 }, { -24, 24 }, { 24, 70 } }) do
			local n = 14
			for k = 0, n do
				local t = k / n
				local z = span[1] + (span[2] - span[1]) * t
				local y = crownTop + 4.5 - math.sin(t * math.pi) * 2.4
				if k < n then
					local flag = Instance.new("WedgePart")
					flag.Name = "Pennant"
					flag.Anchored = true
					flag.CanCollide = false
					flag.CanQuery = false
					flag.CanTouch = false
					flag.CastShadow = false
					flag.Size = Vector3.new(0.1, 1.4, 1.6)
					flag.CFrame = CFrame.new(back2 + 0.5, y - 0.8, z + (span[2] - span[1]) / n / 2) * CFrame.Angles(math.rad(180), 0, 0)
					flag.Color = (k % 3 == 0 and HOME) or (k % 3 == 1 and CHALK) or AWAY
					flag.Material = Enum.Material.Fabric
					flag.Parent = bunting
				end
			end
			deco(part(bunting, "Rope", Vector3.new(0.1, 0.1, span[2] - span[1]), CFrame.new(back2 + 0.5, crownTop + 2.9, (span[1] + span[2]) / 2), Color3.fromRGB(240, 236, 226)))
		end
		-- surfboards stood in the sand by the bleachers
		local boards = { Color3.fromRGB(255, 124, 28), Color3.fromRGB(40, 190, 220), CHALK, Color3.fromRGB(236, 64, 96) }
		for i, z in ipairs({ -83, -81.2, 82, 83.8 }) do
			deco(part(scene, "Surfboard", Vector3.new(0.4, 7, 1.8), CFrame.new(28 + (i % 2) * 0.8, 3.2, z) * CFrame.Angles(0, 0, math.rad(8 - i * 3)), boards[i], Enum.Material.SmoothPlastic))
		end
		-- the scoreboards in wooden frames in front of the bleachers
		screens(scene, { frame = Color3.fromRGB(150, 110, 70), material = Enum.Material.Wood })
		ledBoards(scene, true)
	end,
}

local function column(scene, base, height, stone)
	if toolboxProp(scene, "Column", base, height, 0) then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Column"
	m.Parent = scene
	deco(part(m, "Plinth", Vector3.new(3.6, 1.2, 3.6), CFrame.new(base + Vector3.new(0, 0.6, 0)), stone, Enum.Material.Limestone))
	cylinder(m, "Shaft", height - 2.4, 2.6, base + Vector3.new(0, 1.2, 0), stone, Enum.Material.Limestone)
	deco(part(m, "Capital", Vector3.new(3.8, 1.2, 3.8), CFrame.new(base + Vector3.new(0, height - 0.6, 0)), stone, Enum.Material.Limestone))
end

local function brazier(scene, base)
	local m = Instance.new("Model")
	m.Name = "Brazier"
	m.Parent = scene
	local iron = Color3.fromRGB(46, 40, 36)
	cylinder(m, "Stand", 4, 0.6, base, iron, Enum.Material.Metal)
	cylinder(m, "Bowl", 1, 2.6, base + Vector3.new(0, 4, 0), iron, Enum.Material.Metal)
	local top = base + Vector3.new(0, 5, 0)
	ball(m, "Flame", Vector3.new(2, 2.6, 2), top + Vector3.new(0, 0.9, 0), Color3.fromRGB(214, 84, 24), Enum.Material.Neon)
	ball(m, "FlameCore", Vector3.new(1.1, 1.7, 1.1), top + Vector3.new(0, 0.7, 0), Color3.fromRGB(230, 160, 60), Enum.Material.Neon)
	lamp(m, top + Vector3.new(0, 2, 0), "PointLight", { Range = 22, Brightness = 1.3, Color = Color3.fromRGB(255, 150, 70), Shadows = false })
end

-- Colosseum: a court chalked on the sand, stone tiers up to an arcade, braziers and red
-- banners, at dusk.
COURTS.Colosseum = {
	floor = { Color3.fromRGB(198, 162, 110), Enum.Material.Sand },
	pad = Color3.fromRGB(150, 36, 34),
	paint = { free = Color3.fromRGB(186, 150, 100), court = Color3.fromRGB(212, 178, 126), line = Color3.fromRGB(244, 240, 228), material = Enum.Material.Sand },
	light = {
		props = { Ambient = Color3.fromRGB(112, 92, 84), OutdoorAmbient = Color3.fromRGB(136, 106, 88), Brightness = 1.8, ClockTime = 17.6, EnvironmentDiffuseScale = 0.4, EnvironmentSpecularScale = 0.2, ExposureCompensation = 0, ShadowSoftness = 0.35 },
		bloom = { Intensity = 0.25, Size = 22, Threshold = 1.9 },
		grade = { Saturation = 0.12, Contrast = 0.08, Brightness = 0, TintColor = Color3.fromRGB(255, 234, 210) },
		atmo = { Density = 0.3, Haze = 1.6, Glare = 0.4, Color = Color3.fromRGB(236, 176, 124), Decay = Color3.fromRGB(170, 96, 64) },
		rays = { Intensity = 0.1, Spread = 0.7 },
	},
	build = function(scene, id)
		local stone = Color3.fromRGB(196, 178, 146)
		local stoneDark = Color3.fromRGB(168, 150, 120)
		local S = Court.stands(id)
		stands(scene, id, function(row)
			return row.index % 2 == 0 and stone or stoneDark
		end, Enum.Material.Limestone)
		-- the podium wall in front of the first tier
		deco(part(scene, "Podium", Vector3.new(1.2, 3.4, S.FarLength), CFrame.new(S.FarStart - 0.6, 1.7, 0), stoneDark, Enum.Material.Limestone))
		-- the outer wall behind the top tier: piers and arches over a dark gallery, then an attic
		local wx = standsBack(id) + 1.5
		local top = S.BaseTop + S.Rows * S.RowRise
		local archBase = top - 2
		local archH = 14
		local span = 9
		local shadow = Color3.fromRGB(52, 40, 32)
		deco(part(scene, "Gallery", Vector3.new(1, archBase + archH + 10, 200), CFrame.new(wx + 1.6, (archBase + archH + 10) / 2, 0), shadow))
		for i = -10, 10 do
			local z = i * span
			deco(part(scene, "Pier", Vector3.new(2.6, archH, 2.4), CFrame.new(wx, archBase + archH / 2, z + span / 2), stone, Enum.Material.Limestone))
			-- the arch head: a dark disc in front of the spandrel
			deco(part(scene, "Arch", Vector3.new(0.3, span - 2.4, span - 2.4), CFrame.new(wx - 0.5, archBase + archH - 4, z), shadow, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder }))
		end
		deco(part(scene, "Spandrel", Vector3.new(0.6, 4, 200), CFrame.new(wx - 0.2, archBase + archH - 2, 0), stone, Enum.Material.Limestone))
		deco(part(scene, "Cornice", Vector3.new(3.4, 1, 200), CFrame.new(wx, archBase + archH + 0.5, 0), stoneDark, Enum.Material.Limestone))
		deco(part(scene, "Attic", Vector3.new(2, 7, 200), CFrame.new(wx + 0.4, archBase + archH + 4.5, 0), stone, Enum.Material.Limestone))
		deco(part(scene, "Base", Vector3.new(1, archBase, 200), CFrame.new(wx + 0.8, archBase / 2, 0), stoneDark, Enum.Material.Limestone))
		-- statues along the attic, gilded eagle standards between them, a brazier at each end (the
		-- owner, 2026-10-29: "quite plain")
		local bronze = Color3.fromRGB(150, 104, 56)
		local attic = archBase + archH + 8
		local marble = Color3.fromRGB(236, 230, 216)
		for i = -8, 8, 2 do
			local z = i * span + span / 2
			-- a marble warrior in front of every other arch, lit warm from below (in the camera's
			-- view), and a gilded eagle standard on the attic over it
			local az = i * span
			local sy = archBase + 0.4
			deco(part(scene, "Plinth", Vector3.new(2.6, 1.4, 3), CFrame.new(wx - 1, sy + 0.7, az), stoneDark, Enum.Material.Limestone))
			deco(part(scene, "StatueBody", Vector3.new(1.6, 5, 2), CFrame.new(wx - 1, sy + 3.9, az), marble, Enum.Material.Marble))
			ball(scene, "StatueHead", Vector3.new(1.2, 1.4, 1.2), Vector3.new(wx - 1, sy + 7.1, az), marble, Enum.Material.Marble)
			deco(part(scene, "StatueSpear", Vector3.new(0.25, 8.6, 0.25), CFrame.new(wx - 1.4, sy + 5.2, az + 1.3), bronze, Enum.Material.Metal))
			deco(part(scene, "StatueShield", Vector3.new(0.4, 2.4, 2.4), CFrame.new(wx - 2, sy + 3.6, az - 0.7), bronze, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder }))
			lamp(scene, Vector3.new(wx - 3, sy + 1, az), "PointLight", { Range = 9, Brightness = 0.8, Color = Color3.fromRGB(255, 170, 90), Shadows = false })
			do
				deco(part(scene, "Standard", Vector3.new(0.3, 10, 0.3), CFrame.new(wx, attic + 5, z), Color3.fromRGB(220, 170, 60), Enum.Material.Metal))
				deco(part(scene, "StandardFlag", Vector3.new(0.15, 4, 2.6), CFrame.new(wx - 0.2, attic + 7.4, z), Color3.fromRGB(150, 26, 26), Enum.Material.Fabric))
				ball(scene, "StandardEagle", Vector3.new(0.9, 1, 1.6), Vector3.new(wx, attic + 10.4, z), Color3.fromRGB(230, 180, 70), Enum.Material.Metal)
			end
		end
		for _, sz in ipairs({ -1, 1 }) do
			brazier(scene, Vector3.new(wx, attic, sz * 92))
		end
		-- red banners on every third pier
		for i = -9, 9, 3 do
			local z = i * span + span / 2
			deco(part(scene, "Banner", Vector3.new(0.2, 9, 3), CFrame.new(wx - 1.45, archBase + archH - 5.5, z), Color3.fromRGB(150, 26, 26), Enum.Material.Fabric))
			deco(part(scene, "BannerTrim", Vector3.new(0.25, 0.5, 3.2), CFrame.new(wx - 1.5, archBase + archH - 1.2, z), Color3.fromRGB(220, 170, 60), Enum.Material.Metal))
		end
		-- end walls
		local ez = S.EndStart + S.EndRows * S.RowDepth + 1
		for _, sz in ipairs({ -1, 1 }) do
			deco(part(scene, "EndWall", Vector3.new(wx + 60, archBase + archH + 8, 2), CFrame.new(wx / 2 - 30, (archBase + archH + 8) / 2, sz * ez), stone, Enum.Material.Limestone))
			deco(part(scene, "EndBand", Vector3.new(wx + 60, 1, 2.4), CFrame.new(wx / 2 - 30, archBase + archH + 0.5, sz * ez), stoneDark, Enum.Material.Limestone))
		end
		-- columns and braziers at the corners of the sand
		for _, sz in ipairs({ -1, 1 }) do
			column(scene, Vector3.new(S.FarStart - 3, 0, sz * (C.SideDepth + C.FreeZoneEnd + 2)), 22, stone)
			brazier(scene, Vector3.new(C.HalfWidth + C.FreeZoneSide + 2, 0, sz * (C.SideDepth + 4)))
			brazier(scene, Vector3.new(C.HalfWidth + C.FreeZoneSide + 2, 0, sz * 14))
		end
		-- the score tablets in bronze in front of the podium
		screens(scene, { frame = Color3.fromRGB(150, 110, 60) })
	end,
}

-- Night Rooftop (an original court): a green court on a roof, bleachers under string lights,
-- floodlights, and the city lit up beyond the parapet.
COURTS.Rooftop = {
	floor = { Color3.fromRGB(102, 104, 112), Enum.Material.Concrete },
	pad = Color3.fromRGB(40, 196, 160),
	paint = { free = Color3.fromRGB(64, 70, 86), court = Color3.fromRGB(40, 128, 88), front = Color3.fromRGB(32, 110, 76) },
	light = {
		props = { Ambient = Color3.fromRGB(116, 114, 140), OutdoorAmbient = Color3.fromRGB(128, 128, 158), Brightness = 1, ClockTime = 21.2, EnvironmentDiffuseScale = 0.35, EnvironmentSpecularScale = 0.4, ExposureCompensation = 0.3, ShadowSoftness = 0.4 },
		bloom = { Intensity = 0.4, Size = 22, Threshold = 1.7 },
		grade = { Saturation = 0.12, Contrast = 0.1, Brightness = 0, TintColor = Color3.fromRGB(236, 238, 255) },
		atmo = { Density = 0.32, Haze = 0.8, Glare = 0, Color = Color3.fromRGB(96, 86, 140), Decay = Color3.fromRGB(46, 36, 90) },
	},
	build = function(scene, id)
		local rng = Random.new(33)
		local W, D = C.WallHalfX, C.WallHalfZ
		local concrete = Color3.fromRGB(128, 130, 138)
		-- the parapet around the roof (the near side stays open)
		deco(part(scene, "Parapet", Vector3.new(1.6, 3.2, D * 2 + 4), CFrame.new(W + 1, 1.6, 0), concrete, Enum.Material.Concrete))
		for _, sz in ipairs({ -1, 1 }) do
			deco(part(scene, "Parapet", Vector3.new(W + 100, 3.2, 1.6), CFrame.new(W / 2 - 50, 1.6, sz * (D + 1)), concrete, Enum.Material.Concrete))
		end
		banner(scene, "Tag", Vector3.new(0.3, 2.6, 30), CFrame.new(W - 0.1, 1.6, -58), Enum.NormalId.Left, "VOLLEYBALL RUSH", Color3.fromRGB(255, 90, 170), Color3.fromRGB(128, 130, 138))
		stands(scene, id, function(row)
			return row.index % 2 == 0 and Color3.fromRGB(120, 128, 142) or Color3.fromRGB(100, 108, 122)
		end, Enum.Material.Metal)
		local back = standsBack(id)
		-- the bleachers' back wall in dark steel, neon name panels along the top
		local crownTop = crown(scene, id, {
			wall = Color3.fromRGB(34, 36, 50), material = Enum.Material.DiamondPlate, trim = Color3.fromRGB(0, 229, 255), panel = Color3.fromRGB(16, 16, 30),
			words = { "NIGHT ROOFTOP", "VOLLEYBALL RUSH", "CITY LEAGUE", "VOLLEYBALL RUSH", "NIGHT ROOFTOP" },
			wordColors = { Color3.fromRGB(255, 80, 170), Color3.fromRGB(255, 132, 34), Color3.fromRGB(0, 229, 255) },
			up = 4.8,
		})
		-- the next roof over, right behind the court (the owner, 2026-10-29: "its a lazy approach to
		-- cover up the scene with a higher stadium"): a water tower on legs, a big neon sign on its
		-- frame, an antenna with a red light, a lit stair hut
		local roof2 = folder(scene, "NextRoof")
		local nx = W + 34
		deco(part(roof2, "Roof", Vector3.new(40, 60, 150), CFrame.new(nx, -32, -10), Color3.fromRGB(44, 46, 58), Enum.Material.Concrete))
		deco(part(roof2, "Ledge", Vector3.new(40.6, 1.2, 150.6), CFrame.new(nx, -1.4, -10), Color3.fromRGB(70, 72, 84), Enum.Material.Concrete))
		local wt = Vector3.new(nx + 4, -2, 52)
		for _, o in ipairs({ Vector3.new(-3, 0, -3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, 3) }) do
			cylinder(roof2, "TowerLeg", 12, 0.6, wt + o, Color3.fromRGB(50, 44, 40), Enum.Material.Metal)
		end
		cylinder(roof2, "WaterTower", 12, 10, wt + Vector3.new(0, 12, 0), Color3.fromRGB(122, 86, 60), Enum.Material.WoodPlanks)
		deco(part(roof2, "TowerCap", Vector3.new(11, 1.6, 11), CFrame.new(wt + Vector3.new(0, 24.8, 0)), Color3.fromRGB(64, 56, 52), Enum.Material.Metal))
		local sign = Vector3.new(nx - 6, 18, -34) -- (clear of the billboard across the street)
		deco(part(roof2, "SignFrame", Vector3.new(1, 12, 36), CFrame.new(sign + Vector3.new(0.6, 0, 0)), Color3.fromRGB(20, 20, 30), Enum.Material.Metal))
		banner(roof2, "NeonSign", Vector3.new(0.4, 10.4, 34.4), CFrame.new(sign), Enum.NormalId.Left, "OPEN ALL NIGHT", Color3.fromRGB(255, 80, 170), Color3.fromRGB(14, 12, 26))
		for _, oz in ipairs({ -12, 12 }) do
			deco(part(roof2, "SignLeg", Vector3.new(0.6, 20, 0.6), CFrame.new(sign + Vector3.new(1, -12, oz)), Color3.fromRGB(40, 42, 50), Enum.Material.Metal))
		end
		deco(part(roof2, "Antenna", Vector3.new(0.5, 34, 0.5), CFrame.new(nx + 8, 15, -8), Color3.fromRGB(150, 152, 160), Enum.Material.Metal))
		ball(roof2, "AntennaLight", Vector3.new(1.2, 1.2, 1.2), Vector3.new(nx + 8, 32.4, -8), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
		deco(part(roof2, "Hut", Vector3.new(10, 8, 12), CFrame.new(nx + 8, 2, -64), Color3.fromRGB(70, 72, 84), Enum.Material.Concrete))
		deco(part(roof2, "HutDoor", Vector3.new(0.2, 5, 3), CFrame.new(nx + 2.9, 1, -64), Color3.fromRGB(255, 196, 120), Enum.Material.Neon))
		-- string lights over the bleachers, sagging between poles
		local bulbs = folder(scene, "StringLights")
		local poles = { -66, -22, 22, 66 }
		local poleH = crownTop + 9
		for _, z in ipairs(poles) do
			deco(part(bulbs, "Pole", Vector3.new(0.4, poleH, 0.4), CFrame.new(back + 1.6, poleH / 2, z), Color3.fromRGB(40, 42, 50), Enum.Material.Metal))
		end
		local warm = Color3.fromRGB(255, 214, 150)
		for i = 1, #poles - 1 do
			local z0, z1 = poles[i], poles[i + 1]
			local n = 16
			for k = 1, n - 1 do
				local t = k / n
				local y = poleH - 0.4 - math.sin(t * math.pi) * 3
				ball(bulbs, "Bulb", Vector3.new(0.55, 0.55, 0.55), Vector3.new(back + 1.6, y, z0 + (z1 - z0) * t), warm, Enum.Material.Neon)
			end
			lamp(bulbs, Vector3.new(back - 1, poleH - 3, (z0 + z1) / 2), "PointLight", { Range = 22, Brightness = 1.2, Color = warm, Shadows = false })
		end
		-- floodlights at the corners
		for _, sz in ipairs({ -1, 1 }) do
			local base = Vector3.new(back + 3, 0, sz * 46)
			cylinder(scene, "FloodPole", 26, 0.8, base, Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
			deco(part(scene, "FloodHead", Vector3.new(1.2, 2.4, 6), CFrame.new(base + Vector3.new(-0.8, 26, 0)), Color3.fromRGB(200, 206, 216), Enum.Material.Neon))
			local aim = CFrame.lookAt(base + Vector3.new(-1.5, 26, 0), Vector3.new(0, 0, sz * 16))
			local holder = deco(part(scene, "Flood", Vector3.new(0.5, 0.5, 0.5), aim, WHITE, nil, { Transparency = 1 }))
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Angle = 60
			spot.Range = 60
			spot.Brightness = 3
			spot.Color = Color3.fromRGB(236, 242, 255)
			spot.Shadows = true
			spot.Parent = holder
		end
		-- a water tank, air units and a stair hut
		local tank = Vector3.new(W - 10, 0, 80)
		for _, o in ipairs({ Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, 2) }) do
			cylinder(scene, "TankLeg", 8, 0.4, tank + o, Color3.fromRGB(60, 50, 44), Enum.Material.Metal)
		end
		cylinder(scene, "Tank", 9, 7.5, tank + Vector3.new(0, 8, 0), Color3.fromRGB(120, 84, 58), Enum.Material.WoodPlanks)
		deco(part(scene, "TankRoof", Vector3.new(8, 1.2, 8), CFrame.new(tank + Vector3.new(0, 17.6, 0)), Color3.fromRGB(70, 60, 54), Enum.Material.Metal))
		for i, z in ipairs({ -66, -72, -60 }) do
			deco(part(scene, "AirUnit", Vector3.new(4, 3 + i * 0.4, 5), CFrame.new(W - 5, 1.6 + i * 0.2, z), Color3.fromRGB(176, 180, 188), Enum.Material.Metal))
		end
		deco(part(scene, "StairHut", Vector3.new(8, 9, 10), CFrame.new(W - 6, 4.5, -84), concrete, Enum.Material.Concrete))
		deco(part(scene, "Door", Vector3.new(0.2, 6, 3), CFrame.new(W - 10.1, 3, -84), Color3.fromRGB(46, 48, 58), Enum.Material.Metal))
		lamp(scene, Vector3.new(W - 10.5, 7, -84), "PointLight", { Range = 12, Brightness = 1.4, Color = Color3.fromRGB(255, 200, 140) })
		-- the city: blocks below and beyond the roof with lit floors facing the court
		local city = folder(scene, "City")
		local window = { Color3.fromRGB(186, 146, 84), Color3.fromRGB(104, 136, 180), Color3.fromRGB(180, 164, 130) }
		local x = W + 40
		for ring = 1, 3 do
			local z = -360
			while z < 360 do
				local w = 16 + rng:NextNumber() * 22
				local h = 10 + rng:NextNumber() * (20 + ring * 28)
				local depth = 20 + rng:NextNumber() * 20
				local bx = x + ring * 55 + rng:NextNumber() * 20
				local col = Color3.fromRGB(26 + ring * 3, 30 + ring * 3, 46 + ring * 4)
				local bottom = -120
				deco(part(city, "Block", Vector3.new(depth, h - bottom, w), CFrame.new(bx, (h + bottom) / 2, z + w / 2), col, Enum.Material.Concrete))
				-- lit floors: a few panes each (a grid of windows, not one long strip)
				local floorY = -40 + rng:NextInteger(0, 3) * 5
				local panes = math.max(2, math.floor(w / 4))
				while floorY < h - 4 do
					if rng:NextNumber() < 0.42 then
						local col = window[rng:NextInteger(1, #window)]
						local first = rng:NextInteger(0, panes - 1)
						local count = rng:NextInteger(1, math.max(1, panes - first))
						for k = first, first + count - 1 do
							if rng:NextNumber() < 0.8 then
								deco(part(city, "Windows", Vector3.new(0.2, 1.4, 2.4), CFrame.new(bx - depth / 2 - 0.1, floorY, z + 2 + k * (w - 4) / math.max(1, panes - 1)), col, Enum.Material.Neon))
							end
						end
					end
					floorY = floorY + 4.5
				end
				if rng:NextNumber() < 0.3 then
					ball(city, "Beacon", Vector3.new(0.9, 0.9, 0.9), Vector3.new(bx, h + 0.8, z + w / 2), Color3.fromRGB(255, 50, 50), Enum.Material.Neon)
				end
				z = z + w + 4 + rng:NextNumber() * 8
			end
		end
		deco(part(city, "Street", Vector3.new(900, 1, 1400), CFrame.new(W + 450, -120, 0), Color3.fromRGB(20, 22, 30), Enum.Material.Asphalt))
		banner(city, "Sign", Vector3.new(0.4, 10, 44), CFrame.new(W + 88, 62, -120), Enum.NormalId.Left, "VOLLEYBALL RUSH", Color3.fromRGB(255, 80, 170), Color3.fromRGB(20, 18, 30))
		-- a billboard on the block across the street, in view over the bleachers: the name in the
		-- brand's orange, a neon frame
		local bb = Vector3.new(W + 70, 30, 8)
		deco(part(city, "BillboardBack", Vector3.new(1, 13, 40), CFrame.new(bb + Vector3.new(0.6, 0, 0)), Color3.fromRGB(16, 18, 30), Enum.Material.Metal))
		banner(city, "Billboard", Vector3.new(0.4, 11.6, 38.4), CFrame.new(bb), Enum.NormalId.Left, "VOLLEYBALL RUSH", Color3.fromRGB(255, 132, 34), Color3.fromRGB(14, 16, 32))
		for _, e in ipairs({ { Vector3.new(0, 6.6, 0), Vector3.new(0.5, 0.5, 40) }, { Vector3.new(0, -6.6, 0), Vector3.new(0.5, 0.5, 40) }, { Vector3.new(0, 0, 20), Vector3.new(0.5, 13.6, 0.5) }, { Vector3.new(0, 0, -20), Vector3.new(0.5, 13.6, 0.5) } }) do
			deco(part(city, "BillboardNeon", e[2], CFrame.new(bb + e[1] - Vector3.new(0.3, 0, 0)), Color3.fromRGB(0, 229, 255), Enum.Material.Neon))
		end
		for _, oz in ipairs({ -12, 12 }) do
			deco(part(city, "BillboardLeg", Vector3.new(0.8, 30, 0.8), CFrame.new(bb + Vector3.new(1, -21, oz)), Color3.fromRGB(40, 42, 50), Enum.Material.Metal))
		end
		-- the score screens in front of the bleachers
		screens(scene, { frame = Color3.fromRGB(46, 48, 58) })
		ledBoards(scene, true)
	end,
}

-- Haunted Forest (Halloween; the owner, 2026-10-15: "and with that a halloween court"): the
-- Haunted Forest room's world for a match. An old plank court painted pumpkin and violet in a
-- clearing at midnight, misty violet air, weathered wooden bleachers under orange and violet string
-- lights, dead trees all round fading into the fog, jack-o'-lanterns (the owner's pumpkin) along
-- the far side, a fenced graveyard down the Away end, the clubhouse cabin with its windows lit down
-- the Home end, lantern floodlights for the play, and a huge orange moon over the trees. The
-- Halloween Match is played here (Config.Halloween.Court).
COURTS.Haunted = {
	floor = { Color3.fromRGB(62, 46, 36), Enum.Material.WoodPlanks },
	pad = Color3.fromRGB(255, 120, 20),
	paint = { free = Color3.fromRGB(44, 28, 54), court = Color3.fromRGB(190, 92, 30), front = Color3.fromRGB(164, 76, 24), material = Enum.Material.WoodPlanks },
	light = {
		props = { Ambient = Color3.fromRGB(92, 84, 122), OutdoorAmbient = Color3.fromRGB(104, 94, 140), Brightness = 0.8, ClockTime = 0.3, EnvironmentDiffuseScale = 0.3, EnvironmentSpecularScale = 0.3, ExposureCompensation = 0.35, ShadowSoftness = 0.45 },
		bloom = { Intensity = 0.55, Size = 24, Threshold = 1.45 },
		grade = { Saturation = 0.1, Contrast = 0.12, Brightness = 0, TintColor = Color3.fromRGB(234, 226, 255) },
		atmo = { Density = 0.4, Haze = 1.7, Glare = 0, Color = Color3.fromRGB(112, 92, 158), Decay = Color3.fromRGB(48, 28, 80) },
	},
	build = function(scene, id)
		local rng = Random.new(31)
		local D = C.WallHalfZ
		local wood = Color3.fromRGB(30, 24, 22)
		-- forest floor all round (short of the menu rooms 1600 out)
		deco(part(scene, "Ground", Vector3.new(900, 1, 1000), CFrame.new(230, -0.56, 0), Color3.fromRGB(34, 32, 28), Enum.Material.Ground))
		stands(scene, id, function(row)
			return row.index % 2 == 0 and Color3.fromRGB(66, 48, 36) or Color3.fromRGB(54, 40, 30)
		end, Enum.Material.WoodPlanks)
		local back = standsBack(id)
		-- a dead tree: a leaning trunk, bare limbs with twigs, now and then a dark clump of leaves
		local trees = folder(scene, "Trees")
		local function deadTree(base, height)
			local d = height * (0.045 + rng:NextNumber() * 0.02)
			local foot = CFrame.new(base) * CFrame.Angles(math.rad((rng:NextNumber() - 0.5) * 8), 0, math.rad((rng:NextNumber() - 0.5) * 8))
			deco(part(trees, "Trunk", Vector3.new(height, d, d), foot * CFrame.new(0, height / 2, 0) * VERTICAL, wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder }))
			for _ = 1, 3 + rng:NextInteger(0, 3) do
				local at = foot * CFrame.new(0, height * (0.45 + rng:NextNumber() * 0.45), 0)
				local dir = CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0) * CFrame.Angles(math.rad(25 + rng:NextNumber() * 40), 0, 0)
				local len = height * (0.18 + rng:NextNumber() * 0.18)
				local cf = at * dir
				deco(part(trees, "Limb", Vector3.new(d * 0.32, len, d * 0.32), cf * CFrame.new(0, len / 2, 0), wood, Enum.Material.Wood))
				local tip = (cf * CFrame.new(0, len, 0)).Position
				local twig = CFrame.new(tip) * dir.Rotation * CFrame.Angles(math.rad((rng:NextNumber() - 0.5) * 70), 0, 0)
				deco(part(trees, "Twig", Vector3.new(d * 0.16, len * 0.45, d * 0.16), twig * CFrame.new(0, len * 0.225, 0), wood, Enum.Material.Wood))
				if rng:NextNumber() < 0.18 then
					local s = height * (0.12 + rng:NextNumber() * 0.1)
					ball(trees, "Leaves", Vector3.new(s, s * 0.7, s), tip, Color3.fromRGB(20, 26, 22), Enum.Material.Grass)
				end
			end
		end
		-- behind the bleachers, layer after layer
		for _ = 1, 34 do
			deadTree(Vector3.new(back + 6 + rng:NextNumber() * 130, 0, -150 + rng:NextNumber() * 300), 34 + rng:NextNumber() * 30)
		end
		-- down both ends (never between the camera and the court)
		for _, sz in ipairs({ -1, 1 }) do
			for _ = 1, 12 do
				local x = -30 + rng:NextNumber() * (back + 40)
				local z = sz * (D + 18 + rng:NextNumber() * 90)
				if not (sz > 0 and x > 6 and x < 52 and math.abs(z) < D + 60) and not (sz < 0 and x > 26 and x < 62 and math.abs(z) < D + 62) then
					deadTree(Vector3.new(x, 0, z), 30 + rng:NextNumber() * 24)
				end
			end
		end
		-- jack-o'-lanterns along the far side of the free zone, each with a candle's light
		local lanterns = folder(scene, "Lanterns")
		local skins = ReplicatedStorage:FindFirstChild("ToolboxAssets")
		skins = skins and skins:FindFirstChild("BallSkins")
		local mesh = skins and skins:FindFirstChild("BallPumpkin")
		local fx = C.HalfWidth + C.FreeZoneSide + 3.4
		for i = -5, 5 do
			local z = i * 13 + (rng:NextNumber() - 0.5) * 3
			local size = 2 + rng:NextNumber() * 1.2
			local p
			local src = mesh and (mesh:IsA("BasePart") and mesh or mesh:FindFirstChildWhichIsA("BasePart", true))
			if src then
				p = src:Clone()
				for _, c in ipairs(p:GetChildren()) do
					if not c:IsA("SurfaceAppearance") then
						c:Destroy()
					end
				end
				p.Size = p.Size * (size / math.max(p.Size.X, p.Size.Y, p.Size.Z))
				p.PivotOffset = CFrame.new()
				p.Anchored = true
				p.CFrame = CFrame.new(fx + rng:NextNumber() * 2, p.Size.Y / 2 + 0.03, z) * CFrame.Angles(0, math.rad(90 + (rng:NextNumber() - 0.5) * 40), 0) -- (on the ground)
				deco(p)
				p.Parent = lanterns
			else
				p = ball(lanterns, "Pumpkin", Vector3.new(size * 1.2, size, size * 1.2), Vector3.new(fx + rng:NextNumber() * 2, size / 2, z), Color3.fromRGB(240, 110, 20), Enum.Material.SmoothPlastic)
			end
			p.Name = "JackOLantern"
			local l = Instance.new("PointLight")
			l.Color = Color3.fromRGB(255, 150, 50)
			l.Range = 10
			l.Brightness = 1.3
			l.Shadows = false
			l.Parent = p
		end
		-- the bleachers' back wall of old planks, painted signs and tattered flags along the top
		local crownTop = crown(scene, id, {
			wall = Color3.fromRGB(52, 38, 32), material = Enum.Material.WoodPlanks, trim = Color3.fromRGB(28, 22, 26), panel = Color3.fromRGB(26, 16, 30),
			words = { "HAUNTED FOREST", "TRICK OR TREAT", "VOLLEYBALL RUSH", "DON'T LOOK BACK", "HAUNTED FOREST" },
			wordColors = { Color3.fromRGB(255, 140, 40), Color3.fromRGB(180, 110, 255) },
			up = 4.8,
		})
		-- a graveyard on the rise behind the bleachers, in the camera's view (the owner, 2026-10-29:
		-- not a taller stand covering the scene): a mound of dark earth, crooked crosses and stones,
		-- a mausoleum with its door glowing green, mist
		local hill = folder(scene, "HillGraves")
		local hx = back + 52
		ball(hill, "Mound", Vector3.new(70, 16, 150), Vector3.new(hx, -2, 0), Color3.fromRGB(28, 22, 30), Enum.Material.Ground)
		local grng = Random.new(77)
		for _ = 1, 26 do
			local z = -66 + grng:NextNumber() * 132
			local x = hx - 22 + grng:NextNumber() * 30
			local y = 6 - ((x - hx) / 35) ^ 2 * 6 - (z / 75) ^ 2 * 6 + 1.2
			local tilt = CFrame.Angles(math.rad((grng:NextNumber() - 0.5) * 18), 0, math.rad((grng:NextNumber() - 0.5) * 18))
			if grng:NextNumber() < 0.5 then
				deco(part(hill, "Cross", Vector3.new(0.5, 4.2, 0.5), CFrame.new(x, y + 2.1, z) * tilt, Color3.fromRGB(96, 92, 104), Enum.Material.Slate))
				deco(part(hill, "CrossArm", Vector3.new(0.5, 0.5, 2.4), CFrame.new(x, y + 3.1, z) * tilt, Color3.fromRGB(96, 92, 104), Enum.Material.Slate))
			else
				deco(part(hill, "Stone", Vector3.new(0.7, 3, 2.2), CFrame.new(x, y + 1.5, z) * tilt, Color3.fromRGB(104, 104, 116), Enum.Material.Slate))
			end
		end
		local mz = 18
		deco(part(hill, "Mausoleum", Vector3.new(12, 12, 14), CFrame.new(hx + 6, 10, mz), Color3.fromRGB(84, 82, 94), Enum.Material.Slate))
		for _, side in ipairs({ -1, 1 }) do
			deco(part(hill, "MausoleumRoof", Vector3.new(8, 0.8, 15), CFrame.new(hx + 6 + side * 3, 17.6, mz) * CFrame.Angles(0, 0, math.rad(side * 30)), Color3.fromRGB(46, 44, 54), Enum.Material.Slate))
		end
		local door = deco(part(hill, "MausoleumDoor", Vector3.new(0.3, 6, 4), CFrame.new(hx - 0.1, 7, mz), Color3.fromRGB(110, 255, 160), Enum.Material.Neon))
		local dl = Instance.new("SurfaceLight")
		dl.Face = Enum.NormalId.Left
		dl.Range = 24
		dl.Brightness = 2
		dl.Color = Color3.fromRGB(110, 255, 160)
		dl.Parent = door
		for _, z in ipairs({ -40, 0, 44 }) do
			ball(hill, "Mist", Vector3.new(40, 5, 46), Vector3.new(hx - 14, 4, z), Color3.fromRGB(150, 140, 200), Enum.Material.SmoothPlastic).Transparency = 0.82
		end
		-- string lights over the bleachers
		local bulbs = folder(scene, "StringLights")
		local poles = { -66, -22, 22, 66 }
		local poleH = crownTop + 11
		for _, z in ipairs(poles) do
			deco(part(bulbs, "Pole", Vector3.new(0.5, poleH, 0.5), CFrame.new(back + 1.6, poleH / 2, z), Color3.fromRGB(40, 30, 26), Enum.Material.Wood))
		end
		local bulbColors = { Color3.fromRGB(255, 140, 40), Color3.fromRGB(170, 90, 255), Color3.fromRGB(255, 200, 90) }
		for i = 1, #poles - 1 do
			local z0, z1 = poles[i], poles[i + 1]
			for k = 1, 15 do
				local t = k / 16
				ball(bulbs, "Bulb", Vector3.new(0.6, 0.6, 0.6), Vector3.new(back + 1.6, poleH - 0.4 - math.sin(t * math.pi) * 3, z0 + (z1 - z0) * t), bulbColors[(k - 1) % 3 + 1], Enum.Material.Neon)
			end
			lamp(bulbs, Vector3.new(back - 1, poleH - 3, (z0 + z1) / 2), "PointLight", { Range = 22, Brightness = 1, Color = Color3.fromRGB(255, 170, 110), Shadows = false })
		end
		-- lantern floodlights at the corners: warm, enough to play by
		for _, sz in ipairs({ -1, 1 }) do
			local base = Vector3.new(back + 3, 0, sz * 46)
			cylinder(scene, "FloodPole", 24, 0.8, base, Color3.fromRGB(36, 28, 24), Enum.Material.Wood)
			deco(part(scene, "FloodHead", Vector3.new(1.6, 2.2, 3), CFrame.new(base + Vector3.new(-0.8, 24, 0)), Color3.fromRGB(255, 196, 120), Enum.Material.Neon))
			local aim = CFrame.lookAt(base + Vector3.new(-1.5, 24, 0), Vector3.new(0, 0, sz * 16))
			local holder = deco(part(scene, "Flood", Vector3.new(0.5, 0.5, 0.5), aim, WHITE, nil, { Transparency = 1 }))
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Angle = 62
			spot.Range = 60
			spot.Brightness = 3
			spot.Color = Color3.fromRGB(255, 222, 186)
			spot.Shadows = true
			spot.Parent = holder
		end
		-- the graveyard down the Away end
		local yard = folder(scene, "Graveyard")
		local stone = Color3.fromRGB(110, 112, 122)
		for _ = 1, 9 do
			local at = Vector3.new(12 + rng:NextNumber() * 36, 0, D + 14 + rng:NextNumber() * 38)
			local s = 0.8 + rng:NextNumber() * 0.5
			local cf = CFrame.new(at) * CFrame.Angles(0, math.rad(90 + (rng:NextNumber() - 0.5) * 30), math.rad((rng:NextNumber() - 0.5) * 10))
			deco(part(yard, "Grave", Vector3.new(2.4 * s, 2.6 * s, 0.5 * s), cf * CFrame.new(0, 1.3 * s, 0), stone, Enum.Material.Slate))
			deco(part(yard, "GraveTop", Vector3.new(0.5 * s, 2.4 * s, 2.4 * s), cf * CFrame.new(0, 2.6 * s, 0) * CFrame.Angles(0, math.rad(90), 0), stone, Enum.Material.Slate, { Shape = Enum.PartType.Cylinder }))
		end
		local iron = Color3.fromRGB(16, 15, 18)
		for x = 8, 52, 1.6 do
			deco(part(yard, "Bar", Vector3.new(0.2, 3.4, 0.2), CFrame.new(x, 1.7, D + 10), iron, Enum.Material.Metal))
		end
		deco(part(yard, "Rail", Vector3.new(44, 0.15, 0.15), CFrame.new(30, 2.8, D + 10), iron, Enum.Material.Metal))
		deco(part(yard, "Rail", Vector3.new(44, 0.15, 0.15), CFrame.new(30, 1.1, D + 10), iron, Enum.Material.Metal))
		lamp(yard, Vector3.new(30, 4, D + 30), "PointLight", { Range = 26, Brightness = 1.2, Color = Color3.fromRGB(110, 255, 160), Shadows = false })
		-- the clubhouse cabin down the Home end, its windows lit
		local cab = folder(scene, "Cabin")
		local cz = -(D + 34)
		local plank = Color3.fromRGB(56, 40, 31)
		deco(part(cab, "Walls", Vector3.new(14, 10, 16), CFrame.new(44, 5, cz), plank, Enum.Material.WoodPlanks))
		for _, side in ipairs({ -1, 1 }) do
			deco(part(cab, "Roof", Vector3.new(8.6, 0.7, 17.6), CFrame.new(44 + side * 3.3, 12.2, cz) * CFrame.Angles(0, 0, math.rad(side * 34)), Color3.fromRGB(30, 24, 28), Enum.Material.Slate))
		end
		for _, z in ipairs({ cz - 4.5, cz + 4.5 }) do
			local pane = deco(part(cab, "Window", Vector3.new(0.2, 2.6, 2.6), CFrame.new(36.95, 5.6, z), Color3.fromRGB(255, 160, 70), Enum.Material.Neon))
			local sl = Instance.new("SurfaceLight")
			sl.Face = Enum.NormalId.Left
			sl.Range = 18
			sl.Brightness = 1.4
			sl.Color = Color3.fromRGB(255, 150, 60)
			sl.Parent = pane
		end
		-- the moon over the trees, with a halo
		deco(part(scene, "Moon", Vector3.new(2, 130, 130), CFrame.new(560, 175, -120), Color3.fromRGB(255, 200, 130), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder }))
		deco(part(scene, "MoonHalo", Vector3.new(1, 210, 210), CFrame.new(565, 175, -120), Color3.fromRGB(255, 150, 90), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, Transparency = 0.86 }))
		banner(scene, "Tag", Vector3.new(0.3, 2.6, 34), CFrame.new(back + 0.6, 1.6, 0), Enum.NormalId.Left, "HALLOWEEN NIGHT", Color3.fromRGB(255, 140, 40), Color3.fromRGB(30, 22, 26))
		screens(scene, { frame = Color3.fromRGB(44, 32, 30), material = Enum.Material.WoodPlanks })
		ledBoards(scene, true)
	end,
}

------------------------------------------------------------------------------------------
-- lighting
------------------------------------------------------------------------------------------

function ArenaBuilder.lighting(spec)
	spec = spec or COURTS[Config.Courts.Default].light
	Lighting.GlobalShadows = true
	for k, v in pairs(spec.props) do
		Lighting[k] = v
	end
	-- the courts own the atmosphere and the post effects: ours from the last court go, and so do
	-- the place template's own (a second Atmosphere would fight the court's); the Sky stays
	local TAKEN = { Atmosphere = true, BloomEffect = true, SunRaysEffect = true, ColorCorrectionEffect = true }
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:GetAttribute("SpikeRush") or TAKEN[child.ClassName] then
			child:Destroy()
		end
	end
	local function effect(class, props)
		local e = Instance.new(class)
		for k, v in pairs(props) do
			e[k] = v
		end
		e:SetAttribute("SpikeRush", true)
		e.Parent = Lighting
		return e
	end
	effect("BloomEffect", spec.bloom)
	effect("ColorCorrectionEffect", spec.grade)
	local atmo = effect("Atmosphere", spec.atmo)
	atmo.Offset = 0
	if spec.rays then
		effect("SunRaysEffect", spec.rays)
	end
end

------------------------------------------------------------------------------------------
-- building
------------------------------------------------------------------------------------------

-- Dress the arena as a court (Config.Courts.List); an unknown id falls back to the default.
function ArenaBuilder.setCourt(id)
	local arena = workspace:FindFirstChild("Arena")
	if not arena then
		arena = ArenaBuilder.build()
	end
	if not COURTS[id] or not Config.Courts.List[id] then
		id = Config.Courts.Default
	end
	local court = COURTS[id]
	local old = arena:FindFirstChild("Scene")
	if old then
		old:Destroy()
	end
	local scene = Instance.new("Model")
	scene.Name = "Scene"
	scene:SetAttribute("Court", id)
	-- streaming: the client dresses the boards and screens as soon as the scene arrives, and the
	-- backdrop must be there however far it is from the player
	scene.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local ok, err = pcall(function()
		paint(scene, court.paint)
		court.build(scene, id)
	end)
	if not ok then
		warn("[SpikeRush] court " .. id .. ": " .. tostring(err))
	end
	scene.Parent = arena

	local floor = arena:FindFirstChild("Floor")
	if floor then
		floor.Color = court.floor[1]
		floor.Material = court.floor[2]
	end
	local net = arena:FindFirstChild("Net")
	if net then
		for _, p in ipairs(net:GetChildren()) do
			if p.Name == "PostPad" then
				p.Color = court.pad
			end
		end
	end
	ArenaBuilder.lighting(court.light)
	arena:SetAttribute("Court", id)
	ArenaBuilder.court = id
	return scene
end

function ArenaBuilder.build(opts)
	opts = opts or {}
	local old = workspace:FindFirstChild("Arena")
	if old then
		old:Destroy()
	end
	-- The Baseplate template's plate and spawn sit exactly at y = 0 and would z-fight with the court.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
	local templateSpawn = workspace:FindFirstChild("SpawnLocation")
	if templateSpawn and templateSpawn:IsA("SpawnLocation") then
		templateSpawn:Destroy()
	end

	local arena = Instance.new("Model")
	arena.Name = "Arena"
	if opts.bake then
		arena:SetAttribute("Baked", true)
	end
	buildCore(arena)
	arena.Parent = workspace
	ArenaBuilder.setCourt(opts.court or Config.Courts.Default)
	return arena
end

function ArenaBuilder.init()
	workspace.Gravity = Config.Player.Gravity
	-- a baked arena (built from the command bar and saved) keeps its core; the court still changes
	local existing = workspace:FindFirstChild("Arena")
	if existing and existing:GetAttribute("Baked") then
		ArenaBuilder.setCourt(existing:GetAttribute("Court") or Config.Courts.Default)
		return
	end
	ArenaBuilder.build()
end

return ArenaBuilder
