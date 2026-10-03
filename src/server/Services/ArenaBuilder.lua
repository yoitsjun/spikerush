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
-- p = { free, court, front, line, material, lineWidth, noFree }
local function paint(scene, p)
	local fx, fz = C.HalfWidth + C.FreeZoneSide, C.SideDepth + C.FreeZoneEnd
	local mat = p.material or Enum.Material.SmoothPlastic
	if not p.noFree then
		deco(part(scene, "FreeZone", Vector3.new(fx * 2, 0.05, fz * 2), CFrame.new(0, 0.025, 0), p.free, mat))
	end
	deco(part(scene, "Court", Vector3.new(C.HalfWidth * 2, 0.04, C.SideDepth * 2), CFrame.new(0, 0.06, 0), p.court, mat))
	if p.front then
		for _, sz in ipairs({ -1, 1 }) do
			deco(part(scene, "FrontZone", Vector3.new(C.HalfWidth * 2, 0.04, C.AttackLine), CFrame.new(0, 0.07, sz * C.AttackLine / 2), p.front, mat))
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
local SCREEN_BASE = 3.2 -- clear of the LED boards in front
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

local COURTS = {}

-- Rush Arena: the original hall, navy and warm.
COURTS.Arena = {
	floor = { Color3.fromRGB(176, 124, 78), Enum.Material.WoodPlanks },
	pad = Color3.fromRGB(38, 110, 235),
	paint = { free = Color3.fromRGB(33, 96, 140), court = Color3.fromRGB(236, 128, 52), front = Color3.fromRGB(214, 108, 42) },
	light = {
		props = { Ambient = Color3.fromRGB(88, 86, 96), OutdoorAmbient = Color3.fromRGB(96, 94, 104), Brightness = 0.8, ClockTime = 20.5, EnvironmentDiffuseScale = 0.25, EnvironmentSpecularScale = 0.15, ExposureCompensation = -0.25, ShadowSoftness = 0.6 },
		bloom = { Intensity = 0.18, Size = 18, Threshold = 2.2 },
		grade = { Saturation = 0.02, Contrast = 0.04, Brightness = -0.02, TintColor = Color3.fromRGB(252, 246, 238) },
		atmo = { Density = 0.06, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(150, 150, 170), Decay = Color3.fromRGB(80, 80, 100) },
	},
	build = function(scene, id)
		hall(scene, id, {
			wall = Color3.fromRGB(24, 28, 58),
			accentA = HOME,
			accentB = AWAY,
			bannerText = "SPIKE RUSH",
			bannerColor = CHALK,
			ceiling = Color3.fromRGB(14, 16, 30),
			light = Color3.fromRGB(255, 244, 226),
			lightBrightness = 0.9,
			wash = Color3.fromRGB(200, 210, 255),
		})
		stands(scene, id, function(row)
			local s = 0.85 + (row.index % 2) * 0.12
			return Color3.new(0.2 * s, 0.22 * s, 0.34 * s)
		end)
		rails(scene, id, CHALK)
		screens(scene, { frame = Color3.fromRGB(40, 46, 80) })
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
			wall = Color3.fromRGB(26, 26, 32),
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
		-- championship flags hung over the far stands
		local flags = { HOME, gold, AWAY, CHALK, HOME, gold, AWAY }
		for i, col in ipairs(flags) do
			local z = (i - 4) * 16 * LEN
			deco(part(scene, "Flag", Vector3.new(0.2, 12, 5), CFrame.new(wx - 3, 58, z), col, Enum.Material.Fabric))
			deco(part(scene, "FlagRod", Vector3.new(0.3, 0.3, 5.6), CFrame.new(wx - 3, 64.2, z), gold, Enum.Material.Metal))
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
		props = { Ambient = Color3.fromRGB(118, 112, 110), OutdoorAmbient = Color3.fromRGB(150, 140, 136), Brightness = 2.4, ClockTime = 16.2, EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.3, ExposureCompensation = 0, ShadowSoftness = 0.25 },
		bloom = { Intensity = 0.3, Size = 22, Threshold = 1.6 },
		grade = { Saturation = 0.1, Contrast = 0.05, Brightness = 0.01, TintColor = Color3.fromRGB(255, 244, 228) },
		atmo = { Density = 0.28, Haze = 1.4, Glare = 0.35, Color = Color3.fromRGB(214, 222, 236), Decay = Color3.fromRGB(236, 170, 120) },
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
		for _, isle in ipairs({ { 1040, -320, 340, 46 }, { 900, 240, 220, 30 }, { 1080, 640, 380, 40 } }) do
			ball(scene, "Island", Vector3.new(160, isle[4] * 2, isle[3]), Vector3.new(isle[1], 0, isle[2]), Color3.fromRGB(96, 124, 112), Enum.Material.Grass)
		end
		-- sand beyond the ends and the near side
		deco(part(scene, "Dunes", Vector3.new(300, 1, 400), CFrame.new(-100, -0.55, 0), Color3.fromRGB(224, 198, 148), Enum.Material.Sand))
		stands(scene, id, function(row)
			return row.index % 2 == 0 and Color3.fromRGB(190, 196, 206) or Color3.fromRGB(170, 176, 188)
		end, Enum.Material.Metal)
		local back = standsBack(id)
		-- palms behind the bleachers and along the ends
		for _, z in ipairs({ -84, -62, -38, 34, 60, 86 }) do
			palmTree(scene, Vector3.new(back + 4 + rng:NextNumber() * 6, 0, z + rng:NextNumber() * 4), 26 + rng:NextNumber() * 8, Vector3.new(rng:NextNumber() * 0.4, 0, (rng:NextNumber() - 0.5) * 0.6), rng)
		end
		for _, z in ipairs({ -80, 80 }) do
			palmTree(scene, Vector3.new(4, 0, z), 24, Vector3.new(0.3, 0, -z / math.abs(z) * 0.3), rng)
		end
		-- umbrellas at the ends of the court
		local stripes = {
			{ Color3.fromRGB(236, 64, 64), CHALK },
			{ Color3.fromRGB(250, 196, 40), Color3.fromRGB(40, 150, 220) },
			{ Color3.fromRGB(40, 190, 150), CHALK },
		}
		-- (clear of the bleachers, which run to z = +-70 from x = 28)
		local spots = { Vector3.new(18, 0, -66), Vector3.new(6, 0, -76), Vector3.new(20, 0, 68), Vector3.new(4, 0, 78), Vector3.new(30, 0, -80) }
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
		banner(scene, "Tag", Vector3.new(0.3, 2.6, 30), CFrame.new(W - 0.1, 1.6, -58), Enum.NormalId.Left, "SPIKE RUSH", Color3.fromRGB(255, 90, 170), Color3.fromRGB(128, 130, 138))
		stands(scene, id, function(row)
			return row.index % 2 == 0 and Color3.fromRGB(120, 128, 142) or Color3.fromRGB(100, 108, 122)
		end, Enum.Material.Metal)
		local back = standsBack(id)
		-- string lights over the bleachers, sagging between poles
		local bulbs = folder(scene, "StringLights")
		local poles = { -66, -22, 22, 66 }
		for _, z in ipairs(poles) do
			deco(part(bulbs, "Pole", Vector3.new(0.4, 14, 0.4), CFrame.new(back + 1, 7, z), Color3.fromRGB(40, 42, 50), Enum.Material.Metal))
		end
		local warm = Color3.fromRGB(255, 214, 150)
		for i = 1, #poles - 1 do
			local z0, z1 = poles[i], poles[i + 1]
			local n = 16
			for k = 1, n - 1 do
				local t = k / n
				local y = 13.6 - math.sin(t * math.pi) * 3
				ball(bulbs, "Bulb", Vector3.new(0.55, 0.55, 0.55), Vector3.new(back + 1, y, z0 + (z1 - z0) * t), warm, Enum.Material.Neon)
			end
			lamp(bulbs, Vector3.new(back - 1, 11, (z0 + z1) / 2), "PointLight", { Range = 18, Brightness = 1.2, Color = warm, Shadows = false })
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
				-- lit floors
				local floorY = -40 + rng:NextInteger(0, 3) * 5
				while floorY < h - 4 do
					if rng:NextNumber() < 0.28 then
						local lw = w * (0.2 + rng:NextNumber() * 0.5)
						deco(part(city, "Windows", Vector3.new(0.2, 1, lw), CFrame.new(bx - depth / 2 - 0.1, floorY, z + w / 2 + (rng:NextNumber() - 0.5) * (w - lw)), window[rng:NextInteger(1, #window)], Enum.Material.Neon))
					end
					floorY = floorY + 6
				end
				if rng:NextNumber() < 0.3 then
					ball(city, "Beacon", Vector3.new(0.9, 0.9, 0.9), Vector3.new(bx, h + 0.8, z + w / 2), Color3.fromRGB(255, 50, 50), Enum.Material.Neon)
				end
				z = z + w + 4 + rng:NextNumber() * 8
			end
		end
		deco(part(city, "Street", Vector3.new(900, 1, 1400), CFrame.new(W + 450, -120, 0), Color3.fromRGB(20, 22, 30), Enum.Material.Asphalt))
		banner(city, "Sign", Vector3.new(0.4, 10, 44), CFrame.new(W + 88, 62, -120), Enum.NormalId.Left, "SPIKE RUSH", Color3.fromRGB(255, 80, 170), Color3.fromRGB(20, 18, 30))
		-- the score screens in front of the bleachers
		screens(scene, { frame = Color3.fromRGB(46, 48, 58) })
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
