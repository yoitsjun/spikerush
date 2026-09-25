-- Builds the competition arena procedurally at server start.
--
-- Laid out for the side-view camera: the camera looks from the open near side (x < 0) across
-- the court, so the stands, LED boards, jumbotron and banners live on the far side (x > 0) and
-- the two ends, and nothing tall sits between the camera and the play.
--
-- Everything is generated from Config.Court so the visuals always match the physics. To bake
-- the arena into your place for hand-editing, run this in the Studio command bar (edit mode)
-- and save the place; a baked arena is kept at runtime:
--   require(game.ServerScriptService.Server.Services.ArenaBuilder).build({ bake = true })

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)

local ArenaBuilder = {}

local C = Config.Court
local WHITE = Color3.fromRGB(248, 248, 244)
local HOME = Config.Teams.Home.Color
local AWAY = Config.Teams.Away.Color
local POLE = Color3.fromRGB(38, 110, 235)

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

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y

local function banner(parent, name, size, cf, face, text, color)
	local p = part(parent, name, size, cf, Config.UI.Ink, Enum.Material.SmoothPlastic)
	deco(p)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 0.2
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.Bangers
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Config.UI.Ink
	stroke.Parent = label
	return p
end

local function buildFloor(arena)
	local W, D = C.WallHalfX, C.WallHalfZ
	part(arena, "Floor", Vector3.new(W * 2 + 40, 2, D * 2 + 4), CFrame.new(-20, -1, 0), Color3.fromRGB(176, 124, 78), Enum.Material.WoodPlanks)
	local fx, fz = C.HalfWidth + C.FreeZoneSide, C.SideDepth + C.FreeZoneEnd
	deco(part(arena, "FreeZone", Vector3.new(fx * 2, 0.05, fz * 2), CFrame.new(0, 0.025, 0), Color3.fromRGB(33, 96, 140)))
	deco(part(arena, "Court", Vector3.new(C.HalfWidth * 2, 0.04, C.SideDepth * 2), CFrame.new(0, 0.06, 0), Color3.fromRGB(236, 128, 52)))
	-- the front zones read a shade darker, like a painted three-metre area
	for _, sz in ipairs({ -1, 1 }) do
		deco(part(arena, "FrontZone", Vector3.new(C.HalfWidth * 2, 0.04, C.AttackLine), CFrame.new(0, 0.07, sz * C.AttackLine / 2), Color3.fromRGB(214, 108, 42)))
	end

	local lines = Instance.new("Folder")
	lines.Name = "Lines"
	lines.Parent = arena
	local LW = C.LineWidth
	local function line(name, sx, sz, x, z)
		deco(part(lines, name, Vector3.new(sx, 0.03, sz), CFrame.new(x, 0.095, z), WHITE))
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

local function buildNet(arena)
	local net = Instance.new("Model")
	net.Name = "Net"
	net.Parent = arena
	local netH = C.NetTop - C.NetBottom
	local postX = C.NetHalfWidth + 0.9
	local postH = C.NetTop + 1.2

	for _, sx in ipairs({ -1, 1 }) do
		part(net, "Post", Vector3.new(postH, 0.7, 0.7), CFrame.new(sx * postX, postH / 2, 0) * VERTICAL, Color3.fromRGB(214, 218, 230), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		-- the chunky padded pole is the landmark in the middle of the side view
		part(net, "PostPad", Vector3.new(6.2, 1.9, 1.9), CFrame.new(sx * postX, 3.1, 0) * VERTICAL, POLE, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
		deco(part(net, "PadRing", Vector3.new(0.3, 2.0, 2.0), CFrame.new(sx * postX, 6.2, 0) * VERTICAL, WHITE, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder }))
		deco(part(net, "Cable", Vector3.new(0.9, 0.08, 0.08), CFrame.new(sx * (C.NetHalfWidth + 0.45), C.NetTop - 0.1, 0), Color3.fromRGB(60, 60, 70)))
	end

	deco(part(net, "TopTape", Vector3.new(C.NetHalfWidth * 2, 0.34, 0.14), CFrame.new(0, C.NetTop - 0.17, 0), WHITE, Enum.Material.Fabric))
	deco(part(net, "BottomTape", Vector3.new(C.NetHalfWidth * 2, 0.16, 0.1), CFrame.new(0, C.NetBottom + 0.08, 0), WHITE, Enum.Material.Fabric))
	for _, sx in ipairs({ -1, 1 }) do
		deco(part(net, "SideTape", Vector3.new(0.22, netH, 0.12), CFrame.new(sx * C.HalfWidth, C.NetBottom + netH / 2, 0), WHITE, Enum.Material.Fabric))
	end

	-- the mesh: thin strands the client ripples when the ball hits the net
	local mesh = Instance.new("Folder")
	mesh.Name = "Mesh"
	mesh.Parent = net
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
	part(arena, "NetBarrier", Vector3.new(C.WallHalfX * 2 + 40, 80, 0.6), CFrame.new(-20, 40, 0), WHITE, nil, {
		Transparency = 1,
		CastShadow = false,
		CollisionGroup = "NetBarrier",
	})

	-- referee stand on the far side, behind the net
	local rx = C.NetHalfWidth + 3.4
	deco(part(net, "RefPlatform", Vector3.new(2.6, 0.3, 2.6), CFrame.new(rx, 5.2, 0), Color3.fromRGB(50, 54, 70), Enum.Material.Metal))
	for _, ox in ipairs({ -1, 1 }) do
		for _, oz in ipairs({ -1, 1 }) do
			deco(part(net, "RefLeg", Vector3.new(0.2, 5.2, 0.2), CFrame.new(rx + ox * 1.1, 2.6, oz * 1.1), Color3.fromRGB(180, 184, 196), Enum.Material.Metal))
		end
	end
end

local function buildHall(arena)
	local W, D = C.WallHalfX, C.WallHalfZ
	local wallH = 64
	local wallColor = Color3.fromRGB(24, 28, 58)
	-- far wall and the two ends; the near side stays open for the camera
	part(arena, "WallFar", Vector3.new(2, wallH, D * 2 + 4), CFrame.new(W + 1, wallH / 2, 0), wallColor)
	part(arena, "WallHome", Vector3.new(W + 40, wallH, 2), CFrame.new(W / 2 - 20, wallH / 2, -(D + 1)), wallColor)
	part(arena, "WallAway", Vector3.new(W + 40, wallH, 2), CFrame.new(W / 2 - 20, wallH / 2, D + 1), wallColor)

	for _, h in ipairs({ 22, 50 }) do
		deco(part(arena, "Accent", Vector3.new(0.3, 0.35, D), CFrame.new(W - 0.1, h, -D / 2), HOME, Enum.Material.Neon))
		deco(part(arena, "Accent", Vector3.new(0.3, 0.35, D), CFrame.new(W - 0.1, h, D / 2), AWAY, Enum.Material.Neon))
	end

	banner(arena, "BannerFarHome", Vector3.new(0.4, 8, 34), CFrame.new(W - 0.3, 52, -46), Enum.NormalId.Left, string.upper(Config.Teams.Home.Name), HOME)
	banner(arena, "BannerFarAway", Vector3.new(0.4, 8, 34), CFrame.new(W - 0.3, 52, 46), Enum.NormalId.Left, string.upper(Config.Teams.Away.Name), AWAY)
	banner(arena, "BannerHome", Vector3.new(50, 9, 0.4), CFrame.new(10, 40, -D + 0.3), Enum.NormalId.Back, "SPIKE RUSH", Config.UI.Chalk)
	banner(arena, "BannerAway", Vector3.new(50, 9, 0.4), CFrame.new(10, 40, D - 0.3), Enum.NormalId.Front, "SPIKE RUSH", Config.UI.Chalk)

	-- stepped stands (the client seats a crowd on these rows)
	local stands = Instance.new("Folder")
	stands.Name = "Stands"
	stands.Parent = arena
	for _, row in ipairs(Court.standRows()) do
		local size
		if row.axis == "X" then
			size = Vector3.new(row.depth, row.top, row.length)
		else
			size = Vector3.new(row.length, row.top, row.depth)
		end
		local cf = CFrame.new(row.center.X, row.top / 2, row.center.Z)
		local shade = 0.85 + (row.index % 2) * 0.12
		local p = part(stands, "Row", size, cf, Color3.new(0.2 * shade, 0.22 * shade, 0.34 * shade), Enum.Material.SmoothPlastic)
		p.CastShadow = false
	end
	local S = Court.Stands
	deco(part(stands, "Rail", Vector3.new(0.25, 0.25, S.FarLength), CFrame.new(S.FarStart, S.BaseTop + 1.1, 0), Config.UI.Chalk, Enum.Material.Neon))
	deco(part(stands, "Rail", Vector3.new(S.EndLength, 0.25, 0.25), CFrame.new(S.EndLength * 0.25, S.BaseTop + 1.1, -S.EndStart), HOME, Enum.Material.Neon))
	deco(part(stands, "Rail", Vector3.new(S.EndLength, 0.25, 0.25), CFrame.new(S.EndLength * 0.25, S.BaseTop + 1.1, S.EndStart), AWAY, Enum.Material.Neon))

	-- ceiling, and a light truss low enough for its lights to reach the floor
	part(arena, "Ceiling", Vector3.new(W * 2 + 40, 2, D * 2 + 4), CFrame.new(-20, C.CeilingY + 1, 0), Color3.fromRGB(14, 16, 30))
	local lights = Instance.new("Folder")
	lights.Name = "Lights"
	lights.Parent = arena
	local warm = Color3.fromRGB(255, 244, 226)
	local n = 0
	for _, x in ipairs({ -8, 8 }) do
		for _, z in ipairs({ -36, -18, 0, 18, 36 }) do
			n = n + 1
			local panel = deco(part(lights, "Panel", Vector3.new(6, 0.5, 6), CFrame.new(x, 52, z), warm, Enum.Material.Neon))
			local sl = Instance.new("SurfaceLight")
			sl.Face = Enum.NormalId.Bottom
			sl.Angle = 85
			sl.Range = 60
			sl.Brightness = 1.5
			sl.Color = warm
			sl.Shadows = n == 3 or n == 8
			sl.Parent = panel
		end
	end
	-- wash on the far stands so the crowd reads behind the play
	for _, z in ipairs({ -40, -14, 14, 40 }) do
		local wash = deco(part(lights, "CrowdWash", Vector3.new(1, 1, 1), CFrame.new(S.FarStart - 6, 30, z), warm, Enum.Material.Neon, { Transparency = 1 }))
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Right
		spot.Angle = 70
		spot.Range = 45
		spot.Brightness = 1.2
		spot.Color = Color3.fromRGB(200, 210, 255)
		spot.Parent = wash
	end

	-- jumbotron on the far wall, facing the camera (the client draws the live score on it)
	local jumbo = Instance.new("Model")
	jumbo.Name = "Jumbotron"
	jumbo.Parent = arena
	local screen = deco(part(jumbo, "Body", Vector3.new(1.5, 14, 34), CFrame.new(W - 1, 38, 0), Color3.fromRGB(16, 18, 28), Enum.Material.Metal))
	screen:SetAttribute("Face", "Left")
	deco(part(jumbo, "RimTop", Vector3.new(1.6, 0.5, 34.4), CFrame.new(W - 1, 45.2, 0), Config.UI.Chalk, Enum.Material.Neon))
	deco(part(jumbo, "RimBottom", Vector3.new(1.6, 0.5, 34.4), CFrame.new(W - 1, 30.8, 0), Config.UI.Chalk, Enum.Material.Neon))

	-- LED boards along the far side of the free zone and at both ends (the client animates them)
	local led = Instance.new("Folder")
	led.Name = "LEDBoards"
	led.Parent = arena
	local bx = C.HalfWidth + C.FreeZoneSide + 1.5
	local bz = C.SideDepth + C.FreeZoneEnd + 1.5
	for _, z in ipairs({ -24, 0, 24 }) do
		local b = part(led, "LED", Vector3.new(0.6, 2.6, 23.5), CFrame.new(bx, 1.3, z), Config.UI.Ink)
		b:SetAttribute("Face", Enum.NormalId.Left.Name)
	end
	for _, sz in ipairs({ -1, 1 }) do
		local b = part(led, "LED", Vector3.new(34, 2.6, 0.6), CFrame.new(8, 1.3, sz * bz), Config.UI.Ink)
		local face = Enum.NormalId.Back
		if sz > 0 then
			face = Enum.NormalId.Front
		end
		b:SetAttribute("Face", face.Name)
	end

	-- team benches on the far side
	for _, sz in ipairs({ -1, 1 }) do
		local col = HOME
		if sz > 0 then
			col = AWAY
		end
		part(arena, "Bench", Vector3.new(1.4, 1.3, 9), CFrame.new(C.HalfWidth + 5, 0.65, sz * 14), col, Enum.Material.Fabric)
		deco(part(arena, "Bottle", Vector3.new(0.7, 0.35, 0.35), CFrame.new(C.HalfWidth + 4, 0.35, sz * 9.5) * VERTICAL, col, Enum.Material.Glass, { Shape = Enum.PartType.Cylinder }))
	end

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

function ArenaBuilder.lighting()
	Lighting.Ambient = Color3.fromRGB(70, 72, 96)
	Lighting.OutdoorAmbient = Color3.fromRGB(80, 82, 108)
	Lighting.Brightness = 1.2
	Lighting.ClockTime = 20.5
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.2
	Lighting.ShadowSoftness = 0.25

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:GetAttribute("SpikeRush") then
			child:Destroy()
		end
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 26
	bloom.Threshold = 1.3
	bloom:SetAttribute("SpikeRush", true)
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.2
	cc.Contrast = 0.12
	cc.Brightness = 0.02
	cc.TintColor = Color3.fromRGB(255, 247, 238)
	cc:SetAttribute("SpikeRush", true)
	cc.Parent = Lighting

	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.18
	atmo.Offset = 0.1
	atmo.Color = Color3.fromRGB(170, 180, 230)
	atmo.Decay = Color3.fromRGB(70, 80, 130)
	atmo.Glare = 0
	atmo.Haze = 1.1
	atmo:SetAttribute("SpikeRush", true)
	atmo.Parent = Lighting
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
	buildFloor(arena)
	buildNet(arena)
	buildHall(arena)
	arena.Parent = workspace
	ArenaBuilder.lighting()
	return arena
end

function ArenaBuilder.init()
	workspace.Gravity = Config.Player.Gravity
	-- a baked arena (built from the command bar and saved) is kept as-is
	local existing = workspace:FindFirstChild("Arena")
	if existing and existing:GetAttribute("Baked") then
		ArenaBuilder.lighting()
		return
	end
	ArenaBuilder.build()
end

return ArenaBuilder
