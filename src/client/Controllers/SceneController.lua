-- The menu scenes: two small sets built on this client only, far from the court.
--   * Home: a sunlit club room (lockers, a big window, a bench, a ball cart, a clock) with
--     your own avatar posed in front of the camera. Its room (Config.Rooms, Home's Decorate) can
--     dress it: the Haunted Clubhouse puts it on Halloween night (setRoom).
--   * Gym: a school gym (vaulted ceiling with timber arches, tall windows throwing light shafts,
--     a stage with a red curtain, a ball cart) where recruiting happens: three silhouettes of
--     your avatar stand in for the players you can recruit, and the recruit sequence plays
--     (volleyballs flying under the ceiling, then lined up over the stage).
-- The Locker previews unlockables in the gym: your avatar spikes on a loop with the spike style,
-- colour, trail and score effect you're looking at.
-- The lockers, the bench, the ball carts and every ball are Toolbox models when their slots in
-- ReplicatedStorage.ToolboxAssets.Models are filled (Locker, Bench, BallCart, Volleyball), and
-- simple built stand-ins when they aren't. A cart's own balls are swapped for the volleyball.
-- While a scene is shown this controller owns the camera (CameraController stands down) and a
-- local colour grade and depth of field are switched on.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Spins = require(Shared.Spins)
local Fx = require(script.Parent.Fx)
local BallSkins = require(script.Parent.BallSkins)

local SceneController = {}
local mods

local player = Players.LocalPlayer
local HOME = Vector3.new(1600, 0, -400)
local GYM = Vector3.new(1600, 0, 400)

local folder
local homeBuilt, gymBuilt = false, false
local homeProps, gymProps -- the furniture, rebuilt when a Toolbox model lands
local rng = Random.new()
local current = nil
local camCF, camFov = nil, 40
local shotFrom, shotTo, shotT0, shotDur = nil, nil, 0, 0
local grade, dof
local homeRig, showcase = nil, {}
local homeBits = {} -- the club room's window, sun shafts and lights (a room's decor changes them)
local roomState = { key = nil, decor = nil, flicker = {} } -- the room shown (setRoom) and its decor
local practice = nil -- the Locker's practice spike (see below)
local balls = {}
local flying = {}

------------------------------------------------------------------------------------------
-- building blocks
------------------------------------------------------------------------------------------

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent or folder
	return p
end

local function box(parent, size, cf, color, material, extra)
	local p = part({ Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic }, parent)
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local function light(parent, class, props)
	local l = Instance.new(class)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

-- A copy of the Toolbox model in ReplicatedStorage.ToolboxAssets.Models.<slot> as a Model with
-- its scripts stripped, or nil. Unlike on the court, props cast shadows in the menu sets.
local function toolboxModel(slot)
	local template = Assets.toolbox("Models." .. slot)
	if not template then
		return nil
	end
	local clone = Assets.sanitize(template:Clone())
	local m = clone
	if not clone:IsA("Model") then
		m = Instance.new("Model")
		if clone:IsA("BasePart") then
			clone.Parent = m
		else
			-- a Tool, Accessory or Folder: keep its parts
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") and not d.Parent:IsA("BasePart") then
					d.Parent = m
				end
			end
			clone:Destroy()
		end
	end
	if not m:FindFirstChildWhichIsA("BasePart", true) then
		m:Destroy()
		return nil
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CastShadow = d.Transparency < 1
		end
	end
	m.Name = slot
	return m
end

-- A volleyball: the Toolbox ball when there is one, else white with a yellow and a blue band.
-- Its PrimaryPart is a core at the centre (invisible under a Toolbox ball) that carries lights and
-- trails, so the whole ball moves with PivotTo. `tumble` turns it at random (balls at rest).
local function makeBall(parent, radius, pos, tumble)
	local m = Instance.new("Model")
	m.Name = "Ball"
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 2, CFrame = CFrame.new(pos), Color = Color3.fromRGB(250, 250, 244) }, m)
	m.PrimaryPart = core
	local look = toolboxModel("Volleyball")
	if look then
		look:SetAttribute("BallLook", true)
		core.Transparency = 1
		core.CastShadow = false
		local _, size = look:GetBoundingBox()
		look:ScaleTo(look:GetScale() * radius * 2 / math.max(size.X, size.Y, size.Z, 0.01))
		local box = look:GetBoundingBox()
		local turn = tumble and CFrame.Angles(rng:NextNumber() * math.pi * 2, rng:NextNumber() * math.pi * 2, rng:NextNumber() * math.pi * 2) or CFrame.identity
		look:PivotTo(CFrame.new(pos) * turn * box:ToObjectSpace(look:GetPivot()))
		look.Parent = m
	else
		-- two bands through the centre, crossed, so the ball stays round from every side
		local tilt = CFrame.new(pos) * CFrame.Angles(math.rad(20), math.rad(30), math.rad(90))
		local a = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(radius * 0.62, radius * 2.04, radius * 2.04), CFrame = tilt, Color = Color3.fromRGB(255, 205, 40) }, m)
		local b = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(radius * 0.62, radius * 2.04, radius * 2.04), CFrame = tilt * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(34, 86, 196) }, m)
		a:SetAttribute("BallLook", true)
		b:SetAttribute("BallLook", true)
	end
	m.Parent = parent
	return m
end

-- Scale a prop to fit `fit` (studs along each axis, 0 for any) keeping its proportions, then
-- stand it on `base`: the bottom of its box on base's position and its front (the box's -Z face)
-- along base's LookVector, or its back on base's position with `back` (against a wall). A Toolbox
-- model that faces another way can carry a number attribute "Yaw" (degrees) that turns it.
-- Returns the size it stands at.
local function standProp(m, base, fit, back)
	local yaw = math.rad(m:GetAttribute("Yaw") or 0)
	local _, size = m:GetBoundingBox()
	if math.abs(math.cos(yaw)) < 0.5 then
		size = Vector3.new(size.Z, size.Y, size.X) -- a quarter turn swaps width and depth
	end
	local s = math.huge
	if fit.X > 0 then
		s = math.min(s, fit.X / size.X)
	end
	if fit.Y > 0 then
		s = math.min(s, fit.Y / size.Y)
	end
	if fit.Z > 0 then
		s = math.min(s, fit.Z / size.Z)
	end
	if s < math.huge then
		m:ScaleTo(m:GetScale() * s)
		size = size * s
	end
	local box = m:GetBoundingBox()
	local centre = base * CFrame.new(0, size.Y / 2, back and -size.Z / 2 or 0)
	m:PivotTo(centre * CFrame.Angles(0, yaw, 0) * box:ToObjectSpace(m:GetPivot()))
	return size
end

-- Swap every ball in a prop (a part about as deep and tall as it is wide, and at least `minSize`
-- across) for a volleyball: a Toolbox ball cart may come stocked with basketballs.
local function stockWithBalls(m, minSize)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Parent then
			local s = d.Size
			local lo, hi = math.min(s.X, s.Y, s.Z), math.max(s.X, s.Y, s.Z)
			if lo >= minSize and hi <= lo * 1.1 then
				local pos = d.Position
				d:Destroy()
				makeBall(m, lo / 2, pos, true)
			end
		end
	end
end

local function surfaceText(p, face, text, color, font, bg)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.LightInfluence = 0.4
	sg.PixelsPerStud = 40
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = bg and 0 or 1
	l.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	l.Text = text
	l.TextScaled = true
	l.Font = font or Enum.Font.FredokaOne
	l.TextColor3 = color
	l.Parent = sg
	return l
end

------------------------------------------------------------------------------------------
-- home: the club room
------------------------------------------------------------------------------------------

-- The club room's furniture, into homeProps: the Toolbox lockers, bench and ball cart when those
-- slots are filled, else built stand-ins. Runs again whenever a Toolbox model lands.
local function furnishHome()
	if not homeProps then
		return
	end
	homeProps:ClearAllChildren()
	local H = HOME
	-- lockers along the right of the back wall
	local lockers = toolboxModel("Locker")
	if lockers then
		lockers.Parent = homeProps
		standProp(lockers, CFrame.new(H + Vector3.new(15.2, 0, 17.95)), Vector3.new(14.6, 12, 0), true)
	else
		local steel = Color3.fromRGB(150, 158, 166)
		for i = 0, 5 do
			local x = 9 + i * 2.5
			local body = box(homeProps, Vector3.new(2.4, 12, 3), CFrame.new(H + Vector3.new(x, 6, 16.3)), steel, Enum.Material.Metal)
			body.Reflectance = 0.05
			for v = 0, 3 do
				box(homeProps, Vector3.new(1.4, 0.12, 0.05), CFrame.new(H + Vector3.new(x, 10.4 - v * 0.35, 14.78)), Color3.fromRGB(70, 76, 84))
			end
			box(homeProps, Vector3.new(0.14, 0.9, 0.12), CFrame.new(H + Vector3.new(x + 0.8, 6.5, 14.74)), Color3.fromRGB(60, 64, 70), Enum.Material.Metal)
			box(homeProps, Vector3.new(0.06, 12, 0.06), CFrame.new(H + Vector3.new(x + 1.22, 6, 14.78)), Color3.fromRGB(88, 94, 102))
		end
	end
	-- a bench with a towel on it
	local benchTop = 2.45
	local bench = toolboxModel("Bench")
	if bench then
		bench.Parent = homeProps
		benchTop = standProp(bench, CFrame.new(H + Vector3.new(-6, 0, 5)), Vector3.new(11, 0, 0)).Y
	else
		local seat = box(homeProps, Vector3.new(11, 0.5, 2.2), CFrame.new(H + Vector3.new(-6, 2.2, 5)), Color3.fromRGB(176, 124, 80), Enum.Material.WoodPlanks)
		for _, dx in ipairs({ -4.8, 4.8 }) do
			box(homeProps, Vector3.new(0.4, 2, 1.8), seat.CFrame * CFrame.new(dx, -1.2, 0), Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
		end
	end
	box(homeProps, Vector3.new(3, 0.16, 1.3), CFrame.new(H + Vector3.new(-3.5, benchTop + 0.08, 5.2)) * CFrame.Angles(0, math.rad(8), 0), Color3.fromRGB(246, 246, 240), Enum.Material.Fabric) -- a towel
	-- the ball cart under the window, full of volleyballs
	local cartAt = H + Vector3.new(-10, 0, 13.4)
	local cart = toolboxModel("BallCart")
	if cart then
		cart.Parent = homeProps
		local size = standProp(cart, CFrame.new(cartAt), Vector3.new(8.8, 0, 0))
		stockWithBalls(cart, size.Y * 0.15)
	else
		local basket = box(homeProps, Vector3.new(5, 3.4, 4), CFrame.new(cartAt + Vector3.new(0, 1.7, 0)), Color3.fromRGB(40, 70, 170), Enum.Material.Fabric)
		basket.Reflectance = 0
		for i = 0, 4 do
			makeBall(homeProps, 0.9, cartAt + Vector3.new(-1.6 + i * 0.85, 3.9 + (i % 2) * 0.5, -0.8 + (i % 3) * 0.7), true)
		end
	end
end

local function buildHome()
	if homeBuilt then
		return
	end
	homeBuilt = true
	local room = Instance.new("Model")
	room.Name = "HomeRoom"
	room.Parent = folder
	local H = HOME
	local wood = Color3.fromRGB(150, 104, 72)
	local cream = Color3.fromRGB(226, 214, 190)
	box(room, Vector3.new(46, 1, 36), CFrame.new(H + Vector3.new(0, -0.5, 4)), wood, Enum.Material.WoodPlanks)
	box(room, Vector3.new(46, 1, 36), CFrame.new(H + Vector3.new(0, 24.5, 4)), Color3.fromRGB(214, 200, 176))
	box(room, Vector3.new(46, 25, 1), CFrame.new(H + Vector3.new(0, 12, 18.5)), cream)
	box(room, Vector3.new(1, 25, 36), CFrame.new(H + Vector3.new(-23, 12, 4)), cream)
	box(room, Vector3.new(1, 25, 36), CFrame.new(H + Vector3.new(23, 12, 4)), Color3.fromRGB(208, 196, 172))
	-- skirting and a dado rail
	box(room, Vector3.new(46, 1.2, 0.3), CFrame.new(H + Vector3.new(0, 0.6, 17.9)), Color3.fromRGB(120, 84, 58))
	box(room, Vector3.new(46, 0.3, 0.3), CFrame.new(H + Vector3.new(0, 7, 17.9)), Color3.fromRGB(190, 170, 140))

	-- the window: a bright outdoor view on a SurfaceGui (sky and soft trees)
	local win = box(room, Vector3.new(22, 12, 0.2), CFrame.new(H + Vector3.new(-5, 12.5, 17.8)), Color3.fromRGB(236, 246, 226), Enum.Material.Neon)
	homeBits.window = win
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 1.6
	sg.PixelsPerStud = 20
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.Parent = win
	local sky = Instance.new("Frame")
	sky.Size = UDim2.fromScale(1, 1)
	sky.BorderSizePixel = 0
	sky.BackgroundColor3 = Color3.new(1, 1, 1)
	sky.Parent = sg
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(236, 248, 255), Color3.fromRGB(196, 226, 170))
	g.Parent = sky
	local rnd = Random.new(3)
	for _ = 1, 9 do
		local tree = Instance.new("Frame")
		local d = rnd:NextInteger(60, 150)
		tree.Size = UDim2.fromOffset(d, d)
		tree.Position = UDim2.new(rnd:NextNumber(), -d / 2, 0.45 + rnd:NextNumber() * 0.5, -d / 2)
		tree.BackgroundColor3 = Color3.fromRGB(rnd:NextInteger(120, 170), rnd:NextInteger(170, 205), rnd:NextInteger(90, 120))
		tree.BackgroundTransparency = 0.25
		tree.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = tree
		tree.Parent = sky
	end
	local frameColor = Color3.fromRGB(244, 242, 236)
	for _, x in ipairs({ -16, -8.7, -1.3, 6 }) do
		box(room, Vector3.new(0.6, 12.6, 0.6), CFrame.new(H + Vector3.new(x, 12.5, 17.5)), frameColor)
	end
	for _, y in ipairs({ 6.5, 12.5, 18.5 }) do
		box(room, Vector3.new(22.6, 0.6, 0.6), CFrame.new(H + Vector3.new(-5, y, 17.5)), frameColor)
	end
	box(room, Vector3.new(24, 0.5, 1.6), CFrame.new(H + Vector3.new(-5, 6.1, 17.1)), frameColor)
	homeBits.sun = light(win, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 40, Angle = 70, Brightness = 2.2, Color = Color3.fromRGB(255, 240, 214), Shadows = true })
	-- sun shafts through the window
	homeBits.shafts = {}
	for i, x in ipairs({ -11, -4, 3 }) do
		local shaft = box(room, Vector3.new(4.5, 30, 0.1), CFrame.new(H + Vector3.new(x + 3, 8, 11)) * CFrame.Angles(math.rad(-38), math.rad(-12), 0), Color3.fromRGB(255, 240, 210), Enum.Material.Neon)
		shaft.Transparency = 0.9 + i * 0.015
		shaft.CastShadow = false
		table.insert(homeBits.shafts, { part = shaft, alpha = shaft.Transparency })
	end

	-- a jersey pinned on the wall above the lockers: black with a gold number
	local jersey = box(room, Vector3.new(4, 4.6, 0.12), CFrame.new(H + Vector3.new(15.2, 15.2, 17.8)), Color3.fromRGB(24, 24, 28), Enum.Material.Fabric)
	surfaceText(jersey, Enum.NormalId.Front, "7", Color3.fromRGB(230, 184, 70), Enum.Font.FredokaOne)
	box(room, Vector3.new(4.2, 0.2, 0.3), CFrame.new(H + Vector3.new(15.2, 17.6, 17.8)), Color3.fromRGB(90, 90, 96), Enum.Material.Metal)

	-- a clock above the window
	local clock = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3, 3), CFrame = CFrame.new(H + Vector3.new(-5, 21.3, 17.8)) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(245, 245, 240) }, room)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 3.3, 3.3), CFrame = clock.CFrame * CFrame.new(0.06, 0, 0), Color = Color3.fromRGB(40, 40, 44) }, room)
	box(room, Vector3.new(0.12, 1.1, 0.05), CFrame.new(H + Vector3.new(-5, 21.7, 17.6)), Color3.fromRGB(30, 30, 34))
	box(room, Vector3.new(0.8, 0.12, 0.05), CFrame.new(H + Vector3.new(-4.65, 21.3, 17.6)), Color3.fromRGB(30, 30, 34))

	-- shelves with boxes on the left wall
	for i, y in ipairs({ 4, 8.5, 13 }) do
		box(room, Vector3.new(3, 0.3, 14), CFrame.new(H + Vector3.new(-21.2, y, 8)), Color3.fromRGB(120, 86, 60), Enum.Material.WoodPlanks)
		for b = 0, 2 do
			box(room, Vector3.new(2.4, 2 + (b + i) % 2 * 0.8, 2.6), CFrame.new(H + Vector3.new(-21.2, y + 1.2, 3 + b * 4 + i)) * CFrame.Angles(0, math.rad((b * 7) % 11), 0), Color3.fromRGB(196, 158, 112), Enum.Material.Cardboard)
		end
	end

	-- the lockers, the bench and the ball cart (furnishHome)
	homeProps = Instance.new("Model")
	homeProps.Name = "Props"
	homeProps.Parent = room
	furnishHome()

	-- warm room light
	local lamp = box(room, Vector3.new(10, 0.2, 3), CFrame.new(H + Vector3.new(2, 24, 4)), Color3.fromRGB(255, 244, 222), Enum.Material.Neon)
	homeBits.lampPart = lamp
	homeBits.lamp = light(lamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 26, Angle = 100, Brightness = 1.1, Color = Color3.fromRGB(255, 236, 206), Shadows = true })
	local fill = box(room, Vector3.new(1, 1, 1), CFrame.new(H + Vector3.new(0, 8, -6)), Color3.new(1, 1, 1))
	fill.Transparency = 1
	homeBits.fill = light(fill, "PointLight", { Range = 26, Brightness = 0.8, Color = Color3.fromRGB(255, 226, 196), Shadows = false })
	homeBits.room = room
	if room and SceneController.roomKey then
		SceneController.applyRoom()
	end
end

------------------------------------------------------------------------------------------
-- rooms (Config.Rooms): the club room's decor
------------------------------------------------------------------------------------------

-- A jack-o'-lantern: the owner's Pumpkin ball (its carved face lit, a candle's light inside; its
-- face is -z, toward the camera), or an orange ball with a glow while the mesh isn't in the place.
local function jackLantern(parent, at, size, yaw)
	local m = BallSkins.build("Pumpkin", size / 2)
	if m then
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				d.Rate = 4 -- (a few embers, not a ball's trail)
			elseif d:IsA("PointLight") then
				d.Range = size * 3.4
				d.Brightness = 1.4
				d.Shadows = false
				table.insert(roomState.flicker, { light = d, base = 1.4, seed = rng:NextNumber() * 10 })
			end
		end
		m:PivotTo(CFrame.new(at + Vector3.new(0, size * 0.42, 0)) * CFrame.Angles(0, math.rad(yaw or 0), 0))
		m.Parent = parent
		return m
	end
	local p = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = CFrame.new(at + Vector3.new(0, size / 2, 0)), Color = Color3.fromRGB(255, 120, 20) }, parent)
	local l = light(p, "PointLight", { Range = size * 3.4, Brightness = 1.4, Color = Color3.fromRGB(255, 150, 40), Shadows = false })
	table.insert(roomState.flicker, { light = l, base = 1.4, seed = rng:NextNumber() * 10 })
	return p
end

-- A sagging string of pennants from a to b (alternating colours), `n` flags.
local function bunting(parent, a, b, n, sag, colors)
	local prev = a
	for i = 1, n do
		local t = i / n
		local pt = a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		local mid = (prev + pt) / 2
		local cord = box(parent, Vector3.new(0.06, 0.06, (pt - prev).Magnitude), CFrame.lookAt(mid, pt), Color3.fromRGB(40, 30, 36))
		cord.CastShadow = false
		local flagAt = a:Lerp(b, (i - 0.5) / n) - Vector3.new(0, sag * 4 * ((i - 0.5) / n) * (1 - (i - 0.5) / n), 0)
		local dir = (b - a).Unit
		local w = Instance.new("WedgePart")
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch = true, false, false, false
		w.Size = Vector3.new(0.05, 1.5, 1.1)
		-- point down: the wedge's slope from its top edge to a point at the bottom
		w.CFrame = CFrame.lookAt(flagAt - Vector3.new(0, 0.8, 0), flagAt - Vector3.new(0, 0.8, 0) + dir) * CFrame.Angles(0, math.rad(90), math.rad(180))
		w.Color = colors[(i - 1) % #colors + 1]
		w.Material = Enum.Material.Fabric
		w.CastShadow = false
		w.Parent = parent
		prev = pt
	end
end

-- A cobweb in a corner: threads fanning out from `corner` across the two walls' plane (u, v), and
-- rings of thread between them.
local function cobweb(parent, corner, u, v, size)
	local spokes = {}
	for i = 0, 5 do
		local a = math.rad(i * 18)
		local dir = (u * math.cos(a) + v * math.sin(a)).Unit
		table.insert(spokes, dir)
		local tip = corner + dir * size
		local t = box(parent, Vector3.new(0.035, 0.035, size), CFrame.lookAt((corner + tip) / 2, tip), Color3.fromRGB(235, 235, 245))
		t.Transparency = 0.35
		t.CastShadow = false
	end
	for r = 1, 4 do
		local len = size * r / 4.4
		for i = 1, #spokes - 1 do
			local p1, p2 = corner + spokes[i] * len, corner + spokes[i + 1] * len * 0.96
			local t = box(parent, Vector3.new(0.03, 0.03, (p2 - p1).Magnitude), CFrame.lookAt((p1 + p2) / 2, p2), Color3.fromRGB(235, 235, 245))
			t.Transparency = 0.45
			t.CastShadow = false
		end
	end
end

-- A gravestone: a slab with a round top, RIP on its face.
local function gravestone(parent, at, yaw, scale)
	local cf = CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), math.rad((rng:NextNumber() - 0.5) * 8))
	local stone = Color3.fromRGB(116, 118, 128)
	local slab = box(parent, Vector3.new(2.2, 2.4, 0.5) * scale, cf * CFrame.new(0, 1.2 * scale, 0), stone, Enum.Material.Slate)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2.2, 2.2) * scale, CFrame = cf * CFrame.new(0, 2.4 * scale, 0) * CFrame.Angles(0, math.rad(90), 0), Color = stone, Material = Enum.Material.Slate }, parent)
	surfaceText(slab, Enum.NormalId.Front, "RIP", Color3.fromRGB(40, 40, 48), Enum.Font.Fondamento)
	box(parent, Vector3.new(2.6, 0.3, 1.2) * scale, cf * CFrame.new(0, 0.15, 0), Color3.fromRGB(70, 52, 40), Enum.Material.Ground)
end

-- A candle: wax, a flame and its flickering light.
local function candle(parent, at, h)
	box(parent, Vector3.new(0.35, h, 0.35), CFrame.new(at + Vector3.new(0, h / 2, 0)), Color3.fromRGB(240, 232, 214), Enum.Material.SmoothPlastic)
	local flame = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.22, 0.4, 0.22), CFrame = CFrame.new(at + Vector3.new(0, h + 0.22, 0)), Color = Color3.fromRGB(255, 200, 90), Material = Enum.Material.Neon }, parent)
	flame.CastShadow = false
	local l = light(flame, "PointLight", { Range = 7, Brightness = 0.9, Color = Color3.fromRGB(255, 170, 70), Shadows = false })
	table.insert(roomState.flicker, { light = l, base = 0.9, seed = rng:NextNumber() * 10, flame = flame })
end

-- A picture on a billboard (bats hanging from the ceiling, ghosts drifting): bobbing in update().
local function floater(parent, at, key, size, color, alpha, bob)
	local anchor = part({ Size = Vector3.one * 0.1, CFrame = CFrame.new(at), Transparency = 1 }, parent)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(size, size)
	bb.LightInfluence = 0
	bb.Parent = anchor
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = Assets.id(Assets.Fx[key]) or ""
	img.ImageColor3 = color
	img.ImageTransparency = alpha or 0
	img.Parent = bb
	table.insert(roomState.flicker, { anchor = anchor, home = at, bob = bob or 0.4, seed = rng:NextNumber() * 10, img = img })
	return anchor
end

-- The Haunted Clubhouse: the club room on Halloween night. The window goes to a night sky with an
-- orange full moon, bare trees and bats; the sun's shafts go; the lights drop to a dim orange and
-- violet; jack-o'-lanterns (the owner's pumpkin) on the floor, the bench, the shelves and the
-- lockers, candles, orange and violet bunting across the room (The Spike's festival classroom),
-- cobwebs in the corners, two gravestones, bats hanging under the ceiling, ghosts drifting and a
-- violet mist along the floor.
local function buildHaunted(parent)
	local H = HOME
	local d = Instance.new("Model")
	d.Name = "Haunted"
	d.Parent = parent
	-- the night window, just in front of the day one
	local night = box(d, Vector3.new(22, 12, 0.1), CFrame.new(H + Vector3.new(-5, 12.5, 17.62)), Color3.fromRGB(30, 18, 60), Enum.Material.Neon)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 1.2
	sg.PixelsPerStud = 20
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.Parent = night
	local sky = Instance.new("Frame")
	sky.Size = UDim2.fromScale(1, 1)
	sky.BorderSizePixel = 0
	sky.BackgroundColor3 = Color3.new(1, 1, 1)
	sky.Parent = sg
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 10, 40)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(56, 22, 84)), ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 50, 60)) })
	g.Parent = sky
	local moon = Instance.new("Frame")
	moon.AnchorPoint = Vector2.new(0.5, 0.5)
	moon.Position = UDim2.fromScale(0.7, 0.36)
	moon.Size = UDim2.fromOffset(140, 140)
	moon.BackgroundColor3 = Color3.fromRGB(255, 176, 70)
	moon.BorderSizePixel = 0
	moon.Parent = sky
	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(0.5, 0)
	mc.Parent = moon
	local mg = Instance.new("UIGradient")
	mg.Color = ColorSequence.new(Color3.fromRGB(255, 226, 150), Color3.fromRGB(255, 130, 40))
	mg.Rotation = 45
	mg.Parent = moon
	local halo = moon:Clone()
	halo.Size = UDim2.fromOffset(230, 230)
	halo.BackgroundTransparency = 0.82
	halo.ZIndex = 0
	halo.Parent = sky
	local rnd = Random.new(11)
	for i = 1, 6 do
		-- bare trees: a trunk and a dark crown along the bottom
		local x = rnd:NextNumber()
		local trunk = Instance.new("Frame")
		trunk.AnchorPoint = Vector2.new(0.5, 1)
		trunk.Position = UDim2.fromScale(x, 1)
		trunk.Size = UDim2.fromOffset(rnd:NextInteger(8, 14), rnd:NextInteger(70, 130))
		trunk.BackgroundColor3 = Color3.fromRGB(8, 6, 14)
		trunk.BorderSizePixel = 0
		trunk.Rotation = rnd:NextInteger(-8, 8)
		trunk.Parent = sky
		for _ = 1, 3 do
			local br = Instance.new("Frame")
			br.AnchorPoint = Vector2.new(0, 0.5)
			br.Position = UDim2.new(0.5, 0, rnd:NextNumber() * 0.5, 0)
			br.Size = UDim2.fromOffset(rnd:NextInteger(30, 60), 5)
			br.Rotation = rnd:NextInteger(-150, -30)
			br.BackgroundColor3 = Color3.fromRGB(8, 6, 14)
			br.BorderSizePixel = 0
			br.Parent = trunk
		end
		if i <= 4 then
			local bat = Instance.new("ImageLabel")
			bat.BackgroundTransparency = 1
			bat.Image = Assets.id(Assets.Fx.Bat) or ""
			bat.ImageColor3 = Color3.fromRGB(8, 6, 14)
			local sz = rnd:NextInteger(26, 46)
			bat.Size = UDim2.fromOffset(sz, sz)
			bat.Position = UDim2.fromScale(0.45 + rnd:NextNumber() * 0.45, 0.12 + rnd:NextNumber() * 0.35)
			bat.Parent = sky
		end
	end
	local hill = Instance.new("Frame")
	hill.AnchorPoint = Vector2.new(0.5, 1)
	hill.Position = UDim2.fromScale(0.5, 1.25)
	hill.Size = UDim2.fromScale(1.4, 0.45)
	hill.BackgroundColor3 = Color3.fromRGB(10, 8, 18)
	hill.BorderSizePixel = 0
	hill.Parent = sky
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0.5, 0)
	hc.Parent = hill
	light(night, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 30, Angle = 70, Brightness = 0.9, Color = Color3.fromRGB(255, 160, 90), Shadows = true })
	-- jack-o'-lanterns
	for _, spec in ipairs({
		{ Vector3.new(-14.5, 0, 4.5), 2.6, -15 }, -- by the bench
		{ Vector3.new(-9.6, 2.45, 5.1), 1.5, 10 }, -- on the bench
		{ Vector3.new(-21, 4.15, 6), 1.4, 80 }, -- on the shelves
		{ Vector3.new(-21, 8.65, 11), 1.2, 75 },
		{ Vector3.new(11.5, 12.1, 16.3), 1.7, 0 }, -- on the lockers
		{ Vector3.new(19.5, 12.1, 16.3), 1.4, -10 },
		{ Vector3.new(8.8, 0, 3.2), 2, 20 }, -- beside you
		{ Vector3.new(-18, 0, -3.5), 3.4, -25 }, -- the big one, front left
		{ Vector3.new(17.5, 0, 9.5), 2.4, 15 },
	}) do
		jackLantern(d, H + spec[1], spec[2], spec[3])
	end
	-- candles on the shelves and the window sill
	for _, at in ipairs({ Vector3.new(-21, 4.15, 9.4), Vector3.new(-21, 8.65, 4.5), Vector3.new(-21, 13.15, 9), Vector3.new(-13, 6.35, 17), Vector3.new(2.5, 6.35, 17), Vector3.new(-9.5, 6.35, 17.1) }) do
		candle(d, H + at, 0.6 + rng:NextNumber() * 0.6)
	end
	-- bunting across the room, two strings
	local orange, violet, ink = Color3.fromRGB(255, 120, 20), Color3.fromRGB(120, 50, 200), Color3.fromRGB(26, 20, 30)
	bunting(d, H + Vector3.new(-22.4, 21, 17.3), H + Vector3.new(22.4, 21, 17.3), 22, 2.2, { orange, ink, violet })
	bunting(d, H + Vector3.new(-22.4, 22.5, 2), H + Vector3.new(22.4, 22.5, 12), 20, 2.6, { violet, orange, ink })
	-- cobwebs in the back corners and over the window
	cobweb(d, H + Vector3.new(-22.4, 23.9, 17.9), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0), 5)
	cobweb(d, H + Vector3.new(22.4, 23.9, 17.9), Vector3.new(-1, 0, 0), Vector3.new(0, -1, 0), 5.5)
	cobweb(d, H + Vector3.new(-22.4, 23.9, -2), Vector3.new(0, 0, 1), Vector3.new(0, -1, 0), 4)
	-- gravestones by the right wall
	gravestone(d, H + Vector3.new(19.5, 0, 2.5), -100, 1)
	gravestone(d, H + Vector3.new(20.5, 0, 6.2), -80, 0.8)
	-- the witch's hat on the bench, by the towel
	local hat = BallSkins.build("WitchHat", 0.9)
	if hat then
		for _, x in ipairs(hat:GetDescendants()) do
			if x:IsA("ParticleEmitter") then
				x:Destroy()
			elseif x:IsA("PointLight") then
				x.Brightness = 0.6
			end
		end
		hat:PivotTo(CFrame.new(H + Vector3.new(-1.6, 2.45 + 0.75, 5.3)) * CFrame.Angles(0, math.rad(-30), math.rad(-8)))
		hat.Parent = d
	end
	-- bats hanging under the ceiling, ghosts drifting at the back
	for i, at in ipairs({ Vector3.new(-12, 20.5, 14), Vector3.new(-3, 21.5, 15), Vector3.new(6, 20, 13), Vector3.new(14, 21, 10), Vector3.new(-17, 19.5, 8) }) do
		floater(d, H + at, "Bat", 2 + (i % 2) * 0.8, Color3.fromRGB(14, 10, 20), 0, 0.3)
	end
	floater(d, H + Vector3.new(-14, 10, 15.5), "GhostSheet", 3.4, Color3.fromRGB(235, 240, 255), 0.35, 0.8)
	floater(d, H + Vector3.new(16, 14, 12), "GhostSheet", 2.6, Color3.fromRGB(225, 255, 240), 0.45, 0.6)
	-- violet mist along the floor
	local mist = box(d, Vector3.new(40, 0.2, 26), CFrame.new(H + Vector3.new(0, 0.3, 6)), Color3.new(1, 1, 1))
	mist.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = Assets.id(Assets.Fx.Glow) or ""
	e.Color = ColorSequence.new(Color3.fromRGB(150, 90, 230), Color3.fromRGB(80, 40, 140))
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new(5, 9)
	e.Lifetime = NumberRange.new(5, 8)
	e.Rate = 6
	e.Speed = NumberRange.new(0.3, 0.8)
	e.SpreadAngle = Vector2.new(180, 10)
	e.LightEmission = 0.4
	e.LightInfluence = 0
	e.Rotation = NumberRange.new(0, 360)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = mist
	return d
end

-- Puts the room's decor on the club room (once it's built) and sets its mood: the day window and
-- the sun's shafts go for the night one, and the lights dim to orange and violet.
function SceneController.applyRoom()
	local key = SceneController.roomKey or Config.Rooms.Default
	if not homeBits.room or roomState.key == key then
		return
	end
	roomState.key = key
	if roomState.decor then
		roomState.decor:Destroy()
		roomState.decor = nil
	end
	roomState.flicker = {}
	local haunted = key == "Haunted"
	if haunted then
		roomState.decor = buildHaunted(homeBits.room)
	end
	for _, sh in ipairs(homeBits.shafts or {}) do
		sh.part.Transparency = haunted and 1 or sh.alpha
	end
	if homeBits.sun then
		homeBits.sun.Enabled = not haunted
	end
	if homeBits.lamp then
		homeBits.lamp.Color = haunted and Color3.fromRGB(190, 120, 255) or Color3.fromRGB(255, 236, 206)
		homeBits.lamp.Brightness = haunted and 0.45 or 1.1
	end
	if homeBits.lampPart then
		homeBits.lampPart.Color = haunted and Color3.fromRGB(150, 110, 200) or Color3.fromRGB(255, 244, 222)
	end
	if homeBits.fill then
		homeBits.fill.Color = haunted and Color3.fromRGB(255, 140, 60) or Color3.fromRGB(255, 226, 196)
		homeBits.fill.Brightness = haunted and 0.55 or 0.8
	end
	SceneController.refreshGrade()
end

-- The menus' room (Config.Rooms key; Home's Decorate), drawn when the club room is up.
function SceneController.setRoom(key)
	if SceneController.roomKey == key then
		return
	end
	SceneController.roomKey = key
	SceneController.applyRoom()
end

-- The colour grade for the scene shown: the club room's warm one, or Halloween night's cooler,
-- violet one.
function SceneController.refreshGrade()
	if not grade then
		return
	end
	local night = current == "home" and roomState.key == "Haunted"
	grade.TintColor = night and Color3.fromRGB(236, 222, 255) or Color3.fromRGB(255, 242, 226)
	grade.Brightness = night and -0.04 or 0.02
	grade.Contrast = night and 0.16 or 0.08
	grade.Saturation = night and 0.14 or 0.08
end

local function updateRoom(now)
	for _, f in ipairs(roomState.flicker) do
		if f.light then
			local n = math.noise(now * 3.1, f.seed) * 0.5 + math.noise(now * 9, f.seed + 4) * 0.25
			f.light.Brightness = f.base * (0.85 + n)
			if f.flame then
				f.flame.Size = Vector3.new(0.22, 0.4 + n * 0.25, 0.22)
			end
		elseif f.anchor then
			f.anchor.Position = f.home + Vector3.new(0, math.sin(now * 1.3 + f.seed) * f.bob, math.cos(now * 0.7 + f.seed) * f.bob * 0.5)
		end
	end
end

------------------------------------------------------------------------------------------
-- gym: the recruit hall
------------------------------------------------------------------------------------------

-- The recruit hall's ball cart, into gymProps: the Toolbox cart full of volleyballs, else a
-- built one. Runs again whenever a Toolbox model lands.
local function furnishGym()
	if not gymProps then
		return
	end
	gymProps:ClearAllChildren()
	local at = GYM + Vector3.new(0, 0, 40)
	local cart = toolboxModel("BallCart")
	if cart then
		cart.Parent = gymProps
		local size = standProp(cart, CFrame.new(at), Vector3.new(12, 0, 0))
		stockWithBalls(cart, size.Y * 0.15)
		return
	end
	local body = box(gymProps, Vector3.new(9, 5, 6), CFrame.new(at + Vector3.new(0, 6, 0)), Color3.fromRGB(34, 74, 190), Enum.Material.Fabric)
	surfaceText(body, Enum.NormalId.Back, "SPIKE RUSH", Color3.fromRGB(245, 245, 250), Enum.Font.FredokaOne)
	box(gymProps, Vector3.new(9.2, 0.4, 6.2), CFrame.new(at + Vector3.new(0, 8.6, 0)), Color3.fromRGB(24, 54, 150), Enum.Material.Fabric)
	for _, dx in ipairs({ -4.2, 4.2 }) do
		for _, dz in ipairs({ -2.7, 2.7 }) do
			box(gymProps, Vector3.new(0.3, 3.5, 0.3), CFrame.new(at + Vector3.new(dx, 1.9, dz)), Color3.fromRGB(190, 194, 200), Enum.Material.Metal)
			part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 0.8, 0.8), CFrame = CFrame.new(at + Vector3.new(dx, 0.4, dz)), Color = Color3.fromRGB(40, 40, 44) }, gymProps)
		end
	end
end

local function buildGym()
	if gymBuilt then
		return
	end
	gymBuilt = true
	local hall = Instance.new("Model")
	hall.Name = "RecruitGym"
	hall.Parent = folder
	local G = GYM
	local floorWood = Color3.fromRGB(206, 150, 96)
	local panel = Color3.fromRGB(168, 116, 72)
	local cream = Color3.fromRGB(226, 204, 168)
	local timber = Color3.fromRGB(74, 50, 36)
	local floor = box(hall, Vector3.new(104, 1, 150), CFrame.new(G + Vector3.new(0, -0.5, 20)), floorWood, Enum.Material.WoodPlanks)
	floor.Reflectance = 0.08
	-- court lines
	local lineC = Color3.fromRGB(246, 242, 232)
	for _, z in ipairs({ -30, 30 }) do
		box(hall, Vector3.new(34, 0.05, 0.4), CFrame.new(G + Vector3.new(0, 0.03, z + 20)), lineC)
	end
	for _, x in ipairs({ -17, 17 }) do
		box(hall, Vector3.new(0.4, 0.05, 60), CFrame.new(G + Vector3.new(x, 0.03, 20)), lineC)
	end
	box(hall, Vector3.new(34, 0.05, 0.4), CFrame.new(G + Vector3.new(0, 0.03, 20)), lineC)

	-- walls: wood panelling below, cream above, tall windows
	for _, sx in ipairs({ -1, 1 }) do
		box(hall, Vector3.new(1, 9, 150), CFrame.new(G + Vector3.new(sx * 52, 4.5, 20)), panel, Enum.Material.WoodPlanks)
		box(hall, Vector3.new(1, 28, 150), CFrame.new(G + Vector3.new(sx * 52, 23, 20)), cream)
		for i = 0, 4 do
			local z = -30 + i * 24
			local w = box(hall, Vector3.new(0.2, 12, 14), CFrame.new(G + Vector3.new(sx * 51.4, 21, z)), Color3.fromRGB(255, 246, 220), Enum.Material.Neon)
			if sx < 0 then
				light(w, "SurfaceLight", { Face = Enum.NormalId.Right, Range = 50, Angle = 60, Brightness = 1.6, Color = Color3.fromRGB(255, 226, 170), Shadows = true })
			end
			for _, dz in ipairs({ -7, 0, 7 }) do
				box(hall, Vector3.new(0.5, 12.6, 0.5), CFrame.new(G + Vector3.new(sx * 51.2, 21, z + dz)), Color3.fromRGB(240, 236, 226))
			end
			box(hall, Vector3.new(0.5, 0.5, 14.6), CFrame.new(G + Vector3.new(sx * 51.2, 21, z)), Color3.fromRGB(240, 236, 226))
			if sx < 0 then
				-- a warm shaft of sunlight across the floor
				local shaft = box(hall, Vector3.new(0.1, 40, 11), CFrame.new(G + Vector3.new(-28, 12, z + 6)) * CFrame.Angles(0, 0, math.rad(-52)), Color3.fromRGB(255, 226, 170), Enum.Material.Neon)
				shaft.Transparency = 0.9
				shaft.CastShadow = false
			end
		end
	end
	box(hall, Vector3.new(104, 50, 1), CFrame.new(G + Vector3.new(0, 25, -56)), cream)

	-- the stage and its curtain
	local S = G + Vector3.new(0, 0, 90)
	box(hall, Vector3.new(104, 50, 1), CFrame.new(S + Vector3.new(0, 25, 4)), cream)
	box(hall, Vector3.new(50, 5, 12), CFrame.new(S + Vector3.new(0, 2.5, -3)), Color3.fromRGB(176, 126, 80), Enum.Material.WoodPlanks)
	box(hall, Vector3.new(50, 0.6, 0.4), CFrame.new(S + Vector3.new(0, 5, -9)), Color3.fromRGB(120, 84, 56))
	box(hall, Vector3.new(40, 20, 1), CFrame.new(S + Vector3.new(0, 15, 2.5)), Color3.fromRGB(128, 24, 30), Enum.Material.Fabric)
	box(hall, Vector3.new(46, 3.4, 1.6), CFrame.new(S + Vector3.new(0, 25.5, 2)), Color3.fromRGB(96, 18, 24), Enum.Material.Fabric)
	box(hall, Vector3.new(50, 3, 1.4), CFrame.new(S + Vector3.new(0, 28.5, 3)), panel, Enum.Material.WoodPlanks)
	for _, x in ipairs({ -30, 30 }) do
		box(hall, Vector3.new(5, 3, 0.4), CFrame.new(S + Vector3.new(x, 20, 3.3)), Color3.fromRGB(244, 240, 230))
	end

	-- vaulted ceiling: timber arches across the hall and panels between them
	local seg = 14
	local function archPoint(i)
		local a = math.pi * i / seg
		return Vector3.new(-52 * math.cos(a), 37 + 15 * math.sin(a), 0)
	end
	for k = 0, 7 do
		local z = -48 + k * 19
		for i = 0, seg - 1 do
			local p1, p2 = archPoint(i), archPoint(i + 1)
			local mid = (p1 + p2) / 2
			local len = (p2 - p1).Magnitude
			box(hall, Vector3.new(len + 0.4, 1.6, 1.4), CFrame.lookAt(G + mid + Vector3.new(0, 0, z), G + p2 + Vector3.new(0, 0, z)) * CFrame.Angles(0, math.rad(90), 0), timber, Enum.Material.Wood)
		end
	end
	for i = 0, seg - 1 do
		local p1, p2 = archPoint(i), archPoint(i + 1)
		local mid = (p1 + p2) / 2
		local len = (p2 - p1).Magnitude
		local panelPart = box(hall, Vector3.new(len + 0.3, 0.6, 150), CFrame.lookAt(G + mid + Vector3.new(0, 1, 20), G + p2 + Vector3.new(0, 1, 20)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(116, 90, 72), Enum.Material.WoodPlanks)
		if i == seg / 2 - 1 or i == seg / 2 then
			panelPart.Color = Color3.fromRGB(150, 128, 108)
		end
	end
	-- lights hung under the ridge
	for k = 0, 5 do
		local lamp = box(hall, Vector3.new(3, 0.4, 3), CFrame.new(G + Vector3.new(0, 44, -40 + k * 24)), Color3.fromRGB(255, 244, 220), Enum.Material.Neon)
		light(lamp, "PointLight", { Range = 50, Brightness = 1.2, Color = Color3.fromRGB(255, 228, 190), Shadows = false })
	end

	-- the ball cart (furnishGym)
	gymProps = Instance.new("Model")
	gymProps.Name = "Props"
	gymProps.Parent = hall
	furnishGym()
end

-- Toolbox models can land after the sets are built (ToolboxService loads ids when the server
-- starts): refurnish the built sets when the Models folder changes.
local function watchToolbox()
	task.spawn(function()
		local root = ReplicatedStorage:WaitForChild("ToolboxAssets", 30)
		local models = root and root:WaitForChild("Models", 10)
		if not models then
			return
		end
		local queued = false
		local function refurnish()
			if queued then
				return
			end
			queued = true
			task.defer(function()
				queued = false
				furnishHome()
				furnishGym()
			end)
		end
		models.ChildAdded:Connect(refurnish)
		models.ChildRemoved:Connect(refurnish)
	end)
end

------------------------------------------------------------------------------------------
-- avatars
------------------------------------------------------------------------------------------

-- A static, posable copy of your avatar (nil until your character has loaded).
function SceneController.cloneAvatar(silhouette)
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return nil
	end
	local was = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(function()
		return char:Clone()
	end)
	char.Archivable = was
	if not ok or not clone then
		return nil
	end
	clone.Name = "Avatar"
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("ForceField") or d:IsA("BillboardGui") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Highlight") or d:IsA("Attachment") and d.Name == "SpikeRushHang" then
			d:Destroy()
		end
	end
	if silhouette then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Color = Color3.fromRGB(14, 14, 18)
				d.Material = Enum.Material.SmoothPlastic
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
			elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("SurfaceAppearance") then
				d:Destroy()
			elseif d:IsA("SpecialMesh") then
				d.TextureId = ""
			end
		end
	end
	local rig = mods.AnimationController.rig(clone)
	return rig
end

local function groundOffset(rig)
	local hum = rig.model:FindFirstChildOfClass("Humanoid")
	return (hum and hum.HipHeight or 2) + rig.root.Size.Y / 2
end

local function placeRig(rig, pose, pos, yaw)
	local AC = mods.AnimationController
	AC.poseModel(rig, AC.poseJoints(pose), CFrame.new(pos + Vector3.new(0, groundOffset(rig), 0)) * CFrame.Angles(0, math.rad(yaw or 0), 0))
end

function SceneController.refreshHomeAvatar()
	if homeRig then
		homeRig.model:Destroy()
		homeRig = nil
	end
	if not homeBuilt then
		return
	end
	homeRig = SceneController.cloneAvatar(false)
	if homeRig then
		homeRig.model.Parent = folder
		placeRig(homeRig, "ShowCool", HOME + Vector3.new(2.6, 0, 7), 196)
		if SceneController.homeProp and mods.Skins then
			mods.Skins.prop(homeRig.model, true)
		end
	end
end

-- What your avatar in the menu room holds: "Reaper" (the scythe, on Taeho's page with the skin
-- on) or nil.
function SceneController.setHomeProp(kind)
	if SceneController.homeProp == kind then
		return
	end
	SceneController.homeProp = kind
	if homeRig and mods.Skins then
		mods.Skins.prop(homeRig.model, kind == "Reaper")
	end
end

-- The recruit hall shows three silhouettes of your avatar (the players you could recruit).
function SceneController.refreshShowcase()
	for _, r in ipairs(showcase) do
		r.model:Destroy()
	end
	showcase = {}
	if not gymBuilt then
		return
	end
	local spots = {
		{ pose = "ShowIdle", pos = GYM + Vector3.new(6.5, 0, -12), yaw = 200 },
		{ pose = "ShowCool", pos = GYM + Vector3.new(11, 0, -9.5), yaw = 186 },
		{ pose = "ShowReady", pos = GYM + Vector3.new(15.5, 0, -12.5), yaw = 170 },
	}
	for _, s in ipairs(spots) do
		local rig = SceneController.cloneAvatar(true)
		if rig then
			rig.model.Parent = folder
			local hl = Instance.new("Highlight")
			hl.FillTransparency = 1
			hl.OutlineColor = Color3.fromRGB(255, 236, 190)
			hl.OutlineTransparency = 0.15
			hl.DepthMode = Enum.HighlightDepthMode.Occluded
			hl.Parent = rig.model
			placeRig(rig, s.pose, s.pos, s.yaw)
			if practice then
				rig.model.Parent = nil -- the Locker preview is using the hall
			end
			table.insert(showcase, rig)
		end
	end
end

------------------------------------------------------------------------------------------
-- camera shots
------------------------------------------------------------------------------------------

local SHOTS = {
	home = { from = HOME + Vector3.new(0.4, 4.2, -8.5), to = HOME + Vector3.new(2.2, 3.7, 7), fov = 42 },
	-- the Players screens: the same room, turned so your avatar stands in the left third
	roster = { from = HOME + Vector3.new(-1.6, 4.2, -8.5), to = HOME + Vector3.new(-1.2, 3.7, 7), fov = 42 },
	recruit = { from = GYM + Vector3.new(1, 5.2, -30), to = GYM + Vector3.new(9.5, 4.8, -11), fov = 40 },
	ceiling = { from = GYM + Vector3.new(0, 8, 8), to = GYM + Vector3.new(0, 50, 34), fov = 62 },
	lineup = { from = GYM + Vector3.new(0, 9.5, 12), to = GYM + Vector3.new(0, 18, 88), fov = 58 },
	-- the Locker's practice spike, side on like the match camera, wide enough that the spiker and
	-- the score effect where the ball lands both play left of the Locker's panel (the owner: "have
	-- the angle a bit moved over... i cant see it too well")
	practice = { from = GYM + Vector3.new(-42, 10, 19), to = GYM + Vector3.new(0, 7, 19), fov = 46 },
}

local function shotCF(name)
	local s = SHOTS[name]
	return CFrame.lookAt(s.from, s.to), s.fov
end

-- Cut (duration 0) or glide to a named shot.
function SceneController.shot(name, duration)
	local cf, fov = shotCF(name)
	if not duration or duration <= 0 or not camCF then
		camCF, camFov = cf, fov
		shotFrom = nil
		return
	end
	shotFrom = { cf = camCF, fov = camFov }
	shotTo = { cf = cf, fov = fov }
	shotT0 = os.clock()
	shotDur = duration
end

-- Show a scene ("home" or "gym") or nil to hand the camera back to the game.
function SceneController.show(name)
	if name == current then
		return
	end
	current = name
	if name == "home" then
		buildHome()
		if not homeRig then
			SceneController.refreshHomeAvatar()
		end
		SceneController.shot("home")
		dof.FocusDistance = 16
		dof.InFocusRadius = 6
	elseif name == "gym" then
		buildGym()
		if #showcase == 0 then
			SceneController.refreshShowcase()
		end
		SceneController.shot("recruit")
		dof.FocusDistance = 22
		dof.InFocusRadius = 12
	end
	grade.Enabled = name ~= nil
	dof.Enabled = name ~= nil
	SceneController.refreshGrade()
end

function SceneController.active()
	return current
end

------------------------------------------------------------------------------------------
-- the recruit sequence's 3D part
------------------------------------------------------------------------------------------

local function glowBall(model, color, strength)
	local core = model.PrimaryPart
	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.FillTransparency = 1 - 0.55 * strength
	hl.OutlineColor = color
	hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = model
	local pl = light(core, "PointLight", { Range = 10 + 8 * strength, Brightness = 2 + 3 * strength, Color = color, Shadows = false })
	if strength > 1 then
		-- a Mythic: the glow throbs
		local pulse = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		hl.FillTransparency = 0.15
		TweenService:Create(hl, pulse, { FillTransparency = 0.6 }):Play()
		if pl then
			TweenService:Create(pl, pulse, { Brightness = 1.5 }):Play()
		end
	end
	if strength > 0.7 then
		local att = Instance.new("Attachment")
		att.Parent = core
		local sp = Instance.new("ParticleEmitter")
		sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sp.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		sp.LightEmission = 1
		sp.Rate = strength > 1 and 55 or 30
		sp.Lifetime = NumberRange.new(0.4, 0.8)
		sp.Speed = NumberRange.new(1, 3)
		sp.SpreadAngle = Vector2.new(180, 180)
		sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
		sp.Parent = att
	end
end

function SceneController.clearBalls()
	for _, m in ipairs(balls) do
		m:Destroy()
	end
	balls = {}
	for _, f in ipairs(flying) do
		f.model:Destroy()
	end
	flying = {}
end

-- Volleyballs sweep across under the ceiling in a few clusters. colors[i] = rarity colour,
-- strength[i] = how much they glow (gold S pulls glow hardest).
function SceneController.flyBalls(colors, strength, duration)
	SceneController.clearBalls()
	local n = #colors
	for i = 1, n do
		local cluster = (i - 1) % 3
		local m = makeBall(folder, 1.3, GYM + Vector3.new(-70, 44, 30))
		if strength[i] > 0.3 then
			glowBall(m, colors[i], strength[i])
		end
		table.insert(flying, {
			model = m,
			delay = cluster * 0.12 + math.floor((i - 1) / 3) * 0.05,
			y = 40 + cluster * 3 + (i % 2) * 1.2,
			z = 26 + cluster * 7 + (i % 3) * 1.6,
			dur = duration * (0.8 + 0.1 * cluster),
			t0 = os.clock(),
		})
	end
end

-- The pulls lined up over the stage, each glowing in its rarity colour.
function SceneController.lineUp(colors, strength)
	SceneController.clearBalls()
	local n = #colors
	local spacing = n > 1 and math.min(4.2, 38 / (n - 1)) or 0
	for i = 1, n do
		local x = (i - (n + 1) / 2) * spacing
		local m = makeBall(folder, 1.35, GYM + Vector3.new(x, 30, 84))
		glowBall(m, colors[i], strength[i])
		table.insert(balls, m)
	end
	return balls
end

-- A ball bursts (it's been opened): a hit star, a ring and sparks in its colour.
function SceneController.popBall(i, color)
	local m = balls[i]
	if not m or not m.Parent then
		return
	end
	local pos = m.PrimaryPart.Position
	m:Destroy()
	Fx.play("Burst", pos, { color = color, scale = 0.8 })
	Fx.play("Ring", pos, { color = color, scale = 0.9 })
	Fx.play("Sparks", pos, { color = color, n = 10, scale = 0.8 })
end

------------------------------------------------------------------------------------------
-- the Locker's practice spike
------------------------------------------------------------------------------------------

local PRACTICE = GYM + Vector3.new(0, 0, 16)
local LOOP = 3.1 -- seconds per spike
local TAKEOFF, AIR, CONTACT = 0.35, 1.15, 0.92
local LAND = PRACTICE + Vector3.new(0, 1.2, -20)

local function fadeSeq(from)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, from), NumberSequenceKeypoint.new(1, 1) })
end

local function emitter(parent, texture)
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Lifetime = NumberRange.new(0.25, 0.55)
	e.Speed = NumberRange.new(0.5, 2.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Enabled = false
	e.Parent = parent
	return e
end

-- A ball dressed like a match ball's attack: a wide ribbon, a white core, sparkles, a flame
-- aura and a light.
local function practiceBall()
	local m = makeBall(folder, 1.15, PRACTICE + Vector3.new(0, -60, 0))
	local core = m.PrimaryPart
	local function ribbon(width, x)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(x, width / 2, 0)
		a0.Parent = core
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(x, -width / 2, 0)
		a1.Parent = core
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.FaceCamera = false
		t.LightInfluence = 0
		t.MinLength = 0.02
		t.Enabled = false
		t.Parent = core
		return t
	end
	local b = { model = m, core = core, bolts = {} }
	b.trail = ribbon(3.4, 0)
	b.coreTrail = ribbon(1, -0.05)
	b.coreTrail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	b.coreTrail.Transparency = fadeSeq(0.1)
	b.coreTrail.LightEmission = 1
	local att = Instance.new("Attachment")
	att.Parent = core
	b.att = att
	b.kits = {}
	b.sparkles = emitter(att, Assets.id(Assets.Fx.Glint) or "")
	b.sparkles.RotSpeed = NumberRange.new(-180, 180)
	b.sparkles.Transparency = fadeSeq(0)
	b.aura = emitter(att, Assets.id(Assets.Fx.FireWhite) or "")
	b.aura.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	b.aura.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	b.aura.Lifetime = NumberRange.new(0.18, 0.32)
	b.aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.8), NumberSequenceKeypoint.new(1, 0) })
	b.aura.Transparency = fadeSeq(0.2)
	b.glow = light(core, "PointLight", { Range = 14, Brightness = 0, Shadows = false })
	return b
end

-- The same looks the match ball gives an attack (BallRenderer), from the previewed unlocks.
-- Dress a ball model in a skin (BallSkins), anchored where its core is; the classic look is the
-- one makeBall gave it, hidden while a skin is on. `owner` is whose head Big Head copies.
local function skinBall(b, key, owner)
	if b.skinKey == key and key ~= "BigHead" then
		return
	end
	b.skinKey = key
	if b.skin then
		b.skin:Destroy()
		b.skin = nil
	end
	local skin = key and key ~= "Classic" and BallSkins.build(key, b.core.Size.X / 2, owner) or nil
	for _, c in ipairs(b.model:GetChildren()) do
		if c:GetAttribute("BallLook") then
			for _, d in ipairs(c:IsA("Model") and c:GetDescendants() or { c }) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = skin and 1 or 0
				end
			end
		end
	end
	if skin then
		for _, d in ipairs(skin:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		skin:PivotTo(b.core.CFrame)
		skin.Parent = b.model
		b.skin = skin
	end
end

local function styleBall(b, colorKey, trailKey)
	local colorItem = Spins.resolve("Color", colorKey)
	local tint = Spins.tint(colorItem)
	b.tint = tint
	b.prism = colorItem and colorItem.Key == "Prism"
	local accent = tint or Color3.fromRGB(255, 90, 110)
	b.trail.Color = Spins.tintSequence(colorItem) or ColorSequence.new(Color3.fromRGB(255, 40, 140), Color3.fromRGB(255, 90, 70))
	b.trail.Transparency = fadeSeq(0.12)
	b.trail.Lifetime = 0.6
	b.trail.LightEmission = (colorItem and colorItem.Emission) or 0.9
	b.trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.6) })
	b.dark = colorItem ~= nil and colorItem.Emission ~= nil -- (no white core inside a black trail)
	b.coreTrail.Enabled = not b.dark
	if colorItem and colorItem.Emission then
		b.trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 1) })
		b.trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0.05) })
	end
	b.coreTrail.Lifetime = 0.3
	b.sparkleOn = true
	b.sparkles.Rate = 80
	b.sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 1.8), NumberSequenceKeypoint.new(1, 0) })
	b.sparkles.Color = ColorSequence.new(accent:Lerp(Color3.new(1, 1, 1), 0.6))
	b.auraOn = false
	b.glow.Color = accent
	if b.kit then
		b.kit.set(false)
	end
	b.kit = nil
	-- a solid trail (Rainbow, Bat Swarm) is the ribbon in its own colours; one with a kit of its own
	-- (Bat Swarm's bats) rides it as in a match (BallRenderer); it was dropped here, so the Locker
	-- showed Bat Swarm as a colour (the owner: "it only is a color right now")
	local trailItem = Spins.resolve("Trail", trailKey)
	local solid, emission = Spins.solidTrail(trailItem)
	b.bats = trailItem ~= nil and trailItem.Key == "Bats"
	if b.bats and not b.batRing then
		b.batRing = Fx.batRing(b.core)
	end
	if solid then
		b.trail.Color = solid
		b.trail.LightEmission = emission
		b.trail.Lifetime = 0.75
		b.prism = false
		trailKey = Fx.has("Trail" .. trailItem.Key) and trailItem.Key or "Ribbon"
	end
	if trailKey and trailKey ~= "Ribbon" then
		-- the unlock's hand-drawn kit rides the ball, as in a match (BallRenderer)
		local kit = b.kits[trailKey]
		if not kit then
			kit = Fx.attach("Trail" .. trailKey, b.att)
			b.kits[trailKey] = kit
		end
		b.kit = kit
		b.kitColor = trailKey == "Flame" and tint or accent
	end
	if trailKey == "Comet" then
		b.trail.Lifetime = 1.0
		b.trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.35), NumberSequenceKeypoint.new(1, 0.05) })
		b.coreTrail.Lifetime = 0.45
	elseif trailKey == "Flame" then
		b.glow.Color = Color3.fromRGB(255, 140, 60)
	elseif trailKey == "Stardust" then
		b.trail.Lifetime = 0.8
	end
end

local function launchFx(b, on)
	b.trail.Enabled = on
	b.coreTrail.Enabled = on and not b.dark
	b.sparkles.Enabled = on and b.sparkleOn
	b.aura.Enabled = on and b.auraOn
	b.glow.Brightness = on and 3 or 0
	if b.kit then
		b.kit.set(on, b.kitColor)
	end
	if b.batRing then
		b.batRing.set(on and b.bats)
	end
end

-- Start, restyle (opts = { style, color, trail, effect, pose } keys; `posing` holds the intro
-- pose instead of spiking) or stop (nil) the practice spike.
-- The Locker's practice spike plays the picked score effect once, where its next ball lands.
function SceneController.queuePracticeEffect()
	if practice then
		practice.fxQueued = true
	end
end

function SceneController.setPractice(opts)
	if not opts then
		if practice then
			if practice.rig then
				practice.rig.model:Destroy()
			end
			practice.ball.model:Destroy()
			practice = nil
		end
		for _, r in ipairs(showcase) do
			r.model.Parent = folder
		end
		return
	end
	buildGym()
	if not practice then
		practice = { t0 = os.clock(), ball = practiceBall(), cycle = -1 }
	end
	if not practice.rig then
		practice.rig = SceneController.cloneAvatar(false)
		if practice.rig then
			practice.rig.model.Parent = folder
		end
	end
	practice.opts = opts
	styleBall(practice.ball, opts.color, opts.trail)
	skinBall(practice.ball, opts.ball, practice.rig and practice.rig.model)
	if opts.posing then
		launchFx(practice.ball, false)
		practice.ball.model:PivotTo(CFrame.new(PRACTICE + Vector3.new(0, -60, 0)))
	end
	for _, r in ipairs(showcase) do
		r.model.Parent = nil -- the silhouettes stand where the practice ball lands
	end
end

local function practicePose(p, t)
	local AC = mods.AnimationController
	local style = p.opts.style or "Classic"
	local cock = AC.poseJoints("Cock_" .. style) or AC.poseJoints("Cock")
	local swing = AC.clipDuration("Swing_" .. style) and ("Swing_" .. style) or "Swing"
	local air = AC.clipDuration("Air_" .. style) and ("Air_" .. style) or nil
	if t < TAKEOFF then
		return AC.blendJoints(AC.poseJoints("Ready"), AC.poseJoints("Gather"), t / TAKEOFF), 0
	end
	if t < TAKEOFF + AIR then
		local a = (t - TAKEOFF) / AIR
		local up = 4 * 8 * a * (1 - a)
		if air and t >= TAKEOFF + 0.1 and t < CONTACT then
			-- a style with a move on the way up (Tornado's spin, the Bicycle's flip), as in a match
			return AC.clipJoints(air, t - TAKEOFF - 0.1), up
		elseif t < TAKEOFF + 0.2 then
			return AC.poseJoints("Rise"), up
		elseif t < CONTACT then
			return AC.blendJoints(AC.poseJoints("Rise"), cock, math.clamp((t - TAKEOFF - 0.2) / 0.22, 0, 1)), up
		end
		local st = t - CONTACT
		if st < AC.clipDuration(swing) then
			return AC.clipJoints(swing, st), up
		end
		return AC.poseJoints("SpikeFollow"), up
	end
	return AC.blendJoints(AC.poseJoints("LandCrouch"), AC.poseJoints("Ready"), math.clamp((t - TAKEOFF - AIR) / 0.5, 0, 1)), 0
end

local function updatePractice(now)
	local p = practice
	if not p or not p.rig or current ~= "gym" then
		return
	end
	if p.opts.posing then
		-- the Locker's Intro pose tab: your avatar holds the picked pose, turned to the camera
		local AC = mods.AnimationController
		local name = "Intro_" .. tostring(p.opts.pose)
		local joints = AC.poseJoints(name) or AC.poseJoints("Intro_Ready")
		local bob = math.sin(now * 2.1) * (name == "Intro_Air" and 0.16 or 0.035)
		AC.poseModel(p.rig, joints, CFrame.new(PRACTICE + Vector3.new(0, groundOffset(p.rig) + bob, 0)) * CFrame.Angles(0, math.rad(118), 0))
		return
	end
	local t = (now - p.t0) % LOOP
	local cycle = math.floor((now - p.t0) / LOOP)
	local joints, up = practicePose(p, t)
	local base = PRACTICE + Vector3.new(0, groundOffset(p.rig) + up, 0)
	mods.AnimationController.poseModel(p.rig, joints, CFrame.new(base))
	-- the jump effect at takeoff, once a loop
	if t >= TAKEOFF and p.jumpCycle ~= cycle then
		p.jumpCycle = cycle
		mods.VFXController.jumpEffect(PRACTICE + Vector3.new(0, 0.25, 0), p.opts.jump, p.ball.tint, true, p.rig and p.rig.model)
	end
	local b = p.ball
	local hand = base + Vector3.new(0, 3.1, -1.4)
	local drop = TAKEOFF + 0.1
	if t < drop then
		b.model:PivotTo(CFrame.new(PRACTICE + Vector3.new(0, -60, 0)))
	elseif t < CONTACT then
		-- the set comes down into the hand
		local a = (t - drop) / (CONTACT - drop)
		b.model:PivotTo(CFrame.new(hand + Vector3.new(0, 7 * (1 - a), 3 * (1 - a))))
	else
		if p.cycle ~= cycle then
			p.cycle = cycle
			p.from = hand
			p.landed = false
			p.last = hand
			launchFx(b, true)
		end
		local a = math.clamp((t - CONTACT) / 0.36, 0, 1)
		local pos = p.from:Lerp(LAND, a) + Vector3.new(0, math.sin(a * math.pi) * 0.8, 0)
		if not p.landed then
			b.model:PivotTo(CFrame.new(pos))
			if b.batRing then
				b.batRing.step(now, pos - p.last)
			end
			if b.prism then
				b.trail.Color = ColorSequence.new(Spins.tint(Spins.resolve("Color", "Prism"), now))
			end
			p.last = pos
		end
		if a >= 1 and not p.landed then
			p.landed = true
			launchFx(b, false)
			b.model:PivotTo(CFrame.new(LAND + Vector3.new(0, -60, 0)))
			-- the score effect only when asked for (a click on its card): the owner found it
			-- "quite annoying when it keeps repeated"; otherwise the plain floor impact
			local effect = p.fxQueued and p.opts.effect or "Dust"
			p.fxQueued = false
			mods.VFXController.previewEffect(LAND - Vector3.new(0, 1.1, 0), effect, b.tint, -1, nil, p.rig and p.rig.model)
		end
	end
end

------------------------------------------------------------------------------------------
-- per frame
------------------------------------------------------------------------------------------

local function update()
	local now = os.clock()
	for _, f in ipairs(flying) do
		local a = math.clamp((now - f.t0 - f.delay) / f.dur, 0, 1)
		local e = a * a * (3 - 2 * a)
		local x = -70 + 140 * e
		local p = GYM + Vector3.new(x, f.y + math.sin(a * math.pi) * 3, f.z)
		f.model:PivotTo(CFrame.new(p) * CFrame.Angles(0, 0, -a * 12))
	end
	if not current then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if shotFrom then
		local a = math.clamp((now - shotT0) / shotDur, 0, 1)
		local e = 1 - (1 - a) ^ 3
		camCF = shotFrom.cf:Lerp(shotTo.cf, e)
		camFov = shotFrom.fov + (shotTo.fov - shotFrom.fov) * e
		if a >= 1 then
			shotFrom = nil
		end
	end
	-- a gentle handheld drift keeps the shot alive
	local drift = CFrame.Angles(math.sin(now * 0.4) * 0.004, math.sin(now * 0.31) * 0.006, 0)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = camCF * drift
	cam.FieldOfView = camFov
	updatePractice(now)
	if current == "home" and #roomState.flicker > 0 then
		updateRoom(now)
	end
	if homeRig and current == "home" then
		-- breathing
		local bob = math.sin(now * 1.6) * 0.03
		homeRig.model:PivotTo(CFrame.new(0, bob - (homeRig.bob or 0), 0) * homeRig.model:GetPivot())
		homeRig.bob = bob
	end
end

function SceneController.init(m)
	mods = m
	folder = Instance.new("Folder")
	folder.Name = "SpikeRushScenes"
	folder.Parent = workspace
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SpikeRushSceneGrade"
	grade.TintColor = Color3.fromRGB(255, 242, 226)
	grade.Contrast = 0.08
	grade.Saturation = 0.08
	grade.Brightness = 0.02
	grade.Enabled = false
	grade.Parent = Lighting
	dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "SpikeRushSceneFocus"
	dof.FarIntensity = 0.35
	dof.NearIntensity = 0
	dof.FocusDistance = 16
	dof.InFocusRadius = 6
	dof.Enabled = false
	dof.Parent = Lighting
	local function onCharacter(char)
		task.spawn(function()
			if not player:HasAppearanceLoaded() then
				player.CharacterAppearanceLoaded:Wait()
			end
			task.wait(0.3)
			if char.Parent then
				SceneController.refreshHomeAvatar()
				SceneController.refreshShowcase()
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	watchToolbox()
	RunService:BindToRenderStep("SpikeRushScene", Enum.RenderPriority.Camera.Value + 2, function()
		local ok, err = pcall(update)
		if not ok then
			warn("[SpikeRush] scene: " .. tostring(err))
		end
	end)
end

return SceneController
