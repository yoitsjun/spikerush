-- A court's own moment on the match-winning point (the owner, 2026-10-29: "at the end of the match
-- there can be court effects. like halloween, the haunted horseman runs through. on beach, a whale
-- shoots out of ocean"; "pick one of the three": the end of the match). Client-side and visual
-- only, played behind the wide shot (CameraController holds it for a court that has one):
--   Beach      a whale breaches out past the surf and crashes back in
--   Haunted    the Headless Horseman gallops the length of the court, hooves on fire
--   Rooftop    fireworks over the city
-- (only these three for now: the owner, 2026-10-29, "i dont think all of them need the effect")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local State = require(script.Parent.State)
local Fx = require(script.Parent.Fx)

local CourtMoments = {}

local mods = nil
local C = Config.Court
local WHITE = Color3.fromRGB(248, 250, 255)

local function sound(key, opts)
	if mods and mods.AudioController then
		mods.AudioController.play(key, opts)
	end
end

local function courtNow()
	local arena = workspace:FindFirstChild("Arena")
	return arena and arena:GetAttribute("Court") or nil
end

local function holder()
	local f = Instance.new("Model")
	f.Name = "CourtMoment"
	f.Parent = workspace
	return f
end

local function piece(parent, shape, size, color, material, sphere)
	local p = Instance.new("Part")
	p.Shape = shape or Enum.PartType.Block
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
	if sphere then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = parent
	return p
end

-- Run step(t) every frame for `duration` seconds (t from 0 to 1), then done().
local function animate(duration, step, done)
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = math.min(1, (os.clock() - t0) / duration)
		step(t)
		if t >= 1 then
			conn:Disconnect()
			if done then
				done()
			end
		end
	end)
end

-- A column of spray thrown up out of the sea, falling away.
local function spray(pos, height)
	local f = holder()
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local p = piece(f, Enum.PartType.Ball, Vector3.new(4, 4, 4), WHITE, Enum.Material.SmoothPlastic, true)
		p.Transparency = 0.15
		local at = pos + Vector3.new(math.cos(a) * 4, 0, math.sin(a) * 4)
		p.CFrame = CFrame.new(at)
		local h = height * (0.6 + 0.4 * ((i * 37) % 10) / 10)
		TweenService:Create(p, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(5, h, 5), CFrame = CFrame.new(at + Vector3.new(0, h / 2, 0)) }):Play()
		task.delay(0.7, function()
			TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(8, 2, 8), CFrame = CFrame.new(at), Transparency = 1 }):Play()
		end)
	end
	Fx.play("Dust", pos + Vector3.new(0, 4, 0), { color = WHITE, scale = 4 })
	Fx.play("Wave", pos + Vector3.new(0, 0.5, 0), { color = WHITE, scale = 5 })
	task.delay(2, function()
		f:Destroy()
	end)
end

-- The whale: a long dark body (head to -Z, so it faces where it's going), a pale belly and
-- throat grooves, flippers and flukes.
local function buildWhale(f)
	local back = Color3.fromRGB(44, 58, 84)
	local belly = Color3.fromRGB(214, 222, 230)
	local parts = {}
	local function add(shape, size, color, offset, sphere, material)
		local p = piece(f, shape, size, color, material, sphere)
		table.insert(parts, { p = p, o = offset })
		return p
	end
	add(Enum.PartType.Block, Vector3.new(12, 11, 40), back, CFrame.new(0, 0, -2), true)
	add(Enum.PartType.Block, Vector3.new(10, 8, 30), belly, CFrame.new(0, -2.6, -6), true)
	add(Enum.PartType.Block, Vector3.new(7, 6, 22), back, CFrame.new(0, 0.4, 20), true)
	for _, side in ipairs({ -1, 1 }) do
		add(Enum.PartType.Block, Vector3.new(12, 0.8, 4), back, CFrame.new(side * 9, -3, -8) * CFrame.Angles(0, math.rad(side * 25), math.rad(side * -25)))
		add(Enum.PartType.Block, Vector3.new(11, 0.8, 5), back, CFrame.new(side * 5.5, 0.6, 31) * CFrame.Angles(0, math.rad(side * 30), 0))
		add(Enum.PartType.Ball, Vector3.new(1.1, 1.1, 1.1), Color3.fromRGB(12, 14, 20), CFrame.new(side * 5.2, -0.6, -16))
	end
	for k = -2, 2 do
		add(Enum.PartType.Block, Vector3.new(0.3, 0.3, 14), Color3.fromRGB(170, 180, 192), CFrame.new(k * 1.4, -5.6, -12))
	end
	return parts
end

function CourtMoments.whale()
	local f = holder()
	local parts = buildWhale(f)
	local x0 = 122 -- (out past the surf, close enough to fill the sky over the stands)
	local function at(t)
		return Vector3.new(x0, -30 + 4 * 68 * t * (1 - t), -60 + 100 * t)
	end
	sound("Boom", { volume = 0.6 })
	task.delay(0.5, sound, "WhaleCall", { volume = 1.2 })
	local splashedUp, splashedDown = false, false
	animate(3.4, function(t)
		local pos = at(t)
		local ahead = at(math.min(1, t + 0.01)) - pos
		if ahead.Magnitude < 1e-3 then
			ahead = Vector3.new(0, -1, 0.3)
		end
		local root = CFrame.lookAt(pos, pos + ahead) * CFrame.Angles(0, 0, math.rad(30 * t)) -- (a slight roll: it stays belly down, flukes flat)
		for _, e in ipairs(parts) do
			e.p.CFrame = root * e.o
		end
		if not splashedUp and pos.Y > -2 then
			splashedUp = true
			spray(Vector3.new(x0, 0, pos.Z), 34)
			sound("BigSplash", { volume = 1.1 })
		end
		if splashedUp and not splashedDown and t > 0.5 and pos.Y < 2 then
			splashedDown = true
			spray(Vector3.new(x0, 0, pos.Z), 44)
			sound("BigSplashDown", { volume = 1.3 })
			sound("Boom", { volume = 0.9 })
		end
	end, function()
		f:Destroy()
	end)
end

-- The Headless Horseman: a black horse at full gallop along the far side of the court, a rider in a
-- violet cloak with a burning jack-o'-lantern for a head and a scythe held high, fire at its hooves.
function CourtMoments.horseman()
	local f = holder()
	local horse = Color3.fromRGB(16, 14, 18)
	local parts, legs = {}, {}
	local function add(size, color, offset, opts)
		opts = opts or {}
		local p = piece(f, opts.shape, size, color, opts.material, opts.sphere)
		local e = { p = p, o = offset, hip = opts.hip, phase = opts.phase }
		table.insert(parts, e)
		return p, e
	end
	-- (the horse faces -Z: CFrame.lookAt below)
	add(Vector3.new(3.2, 3.6, 8.5), horse, CFrame.new(0, 5.4, 0))
	add(Vector3.new(2.2, 4.2, 2.4), horse, CFrame.new(0, 7.6, -4.6) * CFrame.Angles(math.rad(-35), 0, 0))
	add(Vector3.new(1.8, 1.8, 3.4), horse, CFrame.new(0, 9.2, -6.6) * CFrame.Angles(math.rad(20), 0, 0))
	for _, side in ipairs({ -0.5, 0.5 }) do
		add(Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 70, 30), CFrame.new(side * 1.8, 9.6, -7.6), { material = Enum.Material.Neon, shape = Enum.PartType.Ball })
	end
	add(Vector3.new(0.6, 3.6, 1.2), Color3.fromRGB(40, 20, 40), CFrame.new(0, 7.6, 4.6) * CFrame.Angles(math.rad(40), 0, 0))
	for i, leg in ipairs({ { -1, -3.2 }, { 1, -3.2 }, { -1, 3.2 }, { 1, 3.2 } }) do
		local _, e = add(Vector3.new(0.9, 4.4, 0.9), horse, CFrame.new(leg[1], 0, leg[2]), { hip = Vector3.new(leg[1], 4.2, leg[2]), phase = (i % 2 == 0) and math.pi or 0 })
		table.insert(legs, e)
	end
	-- the rider
	add(Vector3.new(2, 3.4, 1.4), Color3.fromRGB(20, 16, 24), CFrame.new(0, 9, 0.6))
	add(Vector3.new(0.2, 5.4, 3.6), Color3.fromRGB(70, 24, 110), CFrame.new(0, 8.6, 2.6) * CFrame.Angles(math.rad(28), 0, 0), { material = Enum.Material.Fabric })
	local head = add(Vector3.new(2.4, 2.1, 2.4), Color3.fromRGB(255, 120, 20), CFrame.new(0, 11.8, 0.4), { sphere = true })
	for _, side in ipairs({ -0.45, 0.45 }) do
		add(Vector3.new(0.5, 0.45, 0.2), Color3.fromRGB(255, 230, 90), CFrame.new(side, 12.1, -0.8), { material = Enum.Material.Neon })
	end
	add(Vector3.new(1.3, 0.35, 0.2), Color3.fromRGB(255, 230, 90), CFrame.new(0, 11.3, -0.8), { material = Enum.Material.Neon })
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 140, 40)
	glow.Range = 16
	glow.Brightness = 2.5
	glow.Parent = head
	add(Vector3.new(0.35, 9, 0.35), Color3.fromRGB(60, 44, 34), CFrame.new(1.4, 12, 0) * CFrame.Angles(math.rad(-20), 0, 0), { material = Enum.Material.Wood })
	add(Vector3.new(0.2, 1.4, 5), Color3.fromRGB(200, 210, 230), CFrame.new(1.4, 16, 1.6) * CFrame.Angles(math.rad(-20), 0, 0), { material = Enum.Material.Metal })

	local x = C.HalfWidth + C.FreeZoneSide - 3
	local z0, z1 = -(C.SideDepth + C.FreeZoneEnd + 30), C.SideDepth + C.FreeZoneEnd + 30
	sound("HorseNeigh", { volume = 1.2 })
	sound("HorseGallop", { volume = 1.1 })
	task.delay(0.9, sound, "SinisterLaugh", { volume = 1 })
	local lastFire = 0
	animate(2.8, function(t)
		local z = z0 + (z1 - z0) * t
		local gallop = os.clock() * 14
		local root = CFrame.lookAt(Vector3.new(x, math.abs(math.sin(gallop)) * 0.8, z), Vector3.new(x, 0, z + 1))
		for _, e in ipairs(parts) do
			if e.hip then
				local swing = math.sin(gallop + e.phase) * 0.7
				e.p.CFrame = root * CFrame.new(e.hip) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -2.2, 0)
			else
				e.p.CFrame = root * e.o
			end
		end
		if os.clock() - lastFire > 0.11 then
			lastFire = os.clock()
			Fx.play("Fire", Vector3.new(x, 0.4, z - 2), { color = Color3.fromRGB(255, 90, 20), scale = 0.55 })
		end
	end, function()
		Fx.play("Dust", Vector3.new(x, 1, z1), { color = Color3.fromRGB(120, 90, 160), scale = 3 })
		f:Destroy()
	end)
end

-- Rockets up from the city beyond the roof, bursting over the bleachers.
function CourtMoments.fireworks()
	local colors = { Color3.fromRGB(255, 80, 170), Color3.fromRGB(0, 229, 255), Color3.fromRGB(255, 196, 40), Color3.fromRGB(255, 124, 28), WHITE }
	for i = 1, 9 do
		task.delay((i - 1) * 0.32, function()
			local f = holder()
			local from = Vector3.new(110 + (i % 3) * 25, 0, -80 + i * 17)
			local to = from + Vector3.new(-20, 40 + (i % 4) * 4, 0) -- (bursting in the frame, over the stands)
			local col = colors[(i - 1) % #colors + 1]
			local rocket = piece(f, Enum.PartType.Ball, Vector3.new(1.4, 1.4, 1.4), col, Enum.Material.Neon)
			rocket.CFrame = CFrame.new(from)
			sound("FireworkLaunch", { volume = 0.4, minGap = 0.2 })
			TweenService:Create(rocket, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(to) }):Play()
			task.delay(0.9, function()
				f:Destroy()
				Fx.play("Sparks", to, { color = col, scale = 6 })
				Fx.play("Glow", to, { color = col, scale = 6 })
				Fx.play("Star", to, { color = col, scale = 4 })
				sound("FireworkBurst", { volume = 0.6, minGap = 0.15 })
			end)
		end)
	end
end

local MOMENTS = {
	Beach = function()
		CourtMoments.whale()
	end,
	Haunted = function()
		CourtMoments.horseman()
	end,
	Rooftop = function()
		CourtMoments.fireworks()
	end,
}

-- Whether the court in play has a moment (CameraController keeps the wide shot for it).
function CourtMoments.has()
	return MOMENTS[courtNow() or ""] ~= nil
end

function CourtMoments.play(id)
	local m = MOMENTS[id or courtNow() or ""]
	if m then
		local ok, err = pcall(m)
		if not ok then
			warn("[SpikeRush] court moment: " .. tostring(err))
		end
	end
end

function CourtMoments.init(m)
	mods = m
	State.signals.Announce:Connect(function(a)
		if a.kind == "Point" and a.matchWon and State.watching() then
			task.delay(0.4, CourtMoments.play)
		end
	end)
end

return CourtMoments
