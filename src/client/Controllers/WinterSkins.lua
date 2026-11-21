-- The Winter collab's three skins on court and in their recruit pulls (Config.Halloween.Skins'
-- Limited = "Winter" ones; the owner, 2026-11-16: "viktor sets with christmas lights stringing the
-- path, and the ball glows bluish like snow not purple. kuro's dragon is replaced by santa's sleigh
-- and the sky cracks are snow and icicles... finally laith skin. make something up for that. and
-- make sure their recruit animations are exclusive, like viktor's recruit pull has lights strung
-- up, then it reveals him, kuro has a sleigh dash across the screen"):
--   Twinkle Lights (Viktor)  each Vector Set strings a line of Christmas lights along the ball's
--                            path from his hands (BallRenderer glows the ball snow blue)
--   Sleigh Ride (Kuro)       Santa's sleigh and its reindeer dive in place of the dragon, pulling
--                            back up into the sky; icicles drop out of the cracked sky and shatter
--                            (VFXController.kuro draws the ice sky and the ice-blue fire)
--   Star Topper (Laith)      his Corona's sun is a gold Christmas star, his flare and Sundive throw
--                            ornaments, his path is a garland
-- The pulls (MenuController's skin sequence calls WinterSkins.pull): Lights (the screen strung with
-- lights that come on in turn), Sleigh (the sleigh dashing across a moonlit sky), Tree (a Christmas
-- tree grows, its ornaments pop on, the star lights and bursts into him).
-- Everything here is built from parts and the FxMeshes' winter meshes, nothing new uploaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Util = require(Shared.Util)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)

local WinterSkins = {}
local mods = nil
local folder = nil

local ICE = Color3.fromRGB(150, 225, 255)
local SNOW = Color3.fromRGB(246, 251, 255)
local GOLD = Color3.fromRGB(255, 206, 70)
local RED = Color3.fromRGB(214, 30, 44)
-- the bulbs, in turn (red, gold, green, blue, white)
local BULBS = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 206, 80), Color3.fromRGB(80, 230, 120), Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 250, 240) }

local function sound(key, opts)
	if mods and mods.AudioController then
		pcall(mods.AudioController.play, key, opts)
	end
end

local function hears()
	return mods and mods.AudioController and mods.AudioController.hearsMatch and mods.AudioController.hearsMatch()
end

local function fx()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "WinterSkinFx"
		folder.Parent = workspace
	end
	return folder
end

-- A plain anchored part that touches nothing.
local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function ball(pos, d, color, parent, neon)
	return part({ Shape = Enum.PartType.Ball, Size = Vector3.new(d, d, d), CFrame = CFrame.new(pos), Color = color, Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic }, parent)
end

-- A stick from a to b, `w` thick.
local function stick(a, b, w, color, parent, material)
	local len = (b - a).Magnitude
	return part({ Size = Vector3.new(w, w, math.max(len, 0.05)), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color, Material = material or Enum.Material.SmoothPlastic }, parent)
end

local function camNear(pos)
	local cam = workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - pos).Magnitude < 420
end

function WinterSkins.is(model, key)
	return model ~= nil and model:GetAttribute("Skin") == key
end

------------------------------------------------------------------------------------------
-- Twinkle Lights: a string of lights along a Vector Set's path
------------------------------------------------------------------------------------------

local SPACING = 2.4 -- studs between bulbs
local HANG = 0.7 -- the string hangs this far under the ball's line

-- Strings lights behind the ball from `from` while the set `seq` flies (BallRenderer), then lets
-- them twinkle and go out.
local function stringLights(from, seq)
	local BR = mods and mods.BallRenderer
	if not BR then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "TwinkleString"
	holder.Parent = fx()
	local bulbs = {}
	local last = from
	local t0 = os.clock()
	local n = 0
	local function addBulb(at)
		-- a little drooping wire to it, a socket, the bulb (every third one lights the floor)
		local mid = (last + at) / 2 - Vector3.new(0, 0.35, 0)
		stick(last, mid, 0.12, Color3.fromRGB(20, 60, 30), holder)
		stick(mid, at, 0.12, Color3.fromRGB(20, 60, 30), holder)
		part({ Size = Vector3.new(0.26, 0.3, 0.26), CFrame = CFrame.new(at + Vector3.new(0, 0.2, 0)), Color = Color3.fromRGB(30, 40, 30) }, holder)
		n = n + 1
		local color = BULBS[(n - 1) % #BULBS + 1]
		local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.62, 0.78, 0.62), CFrame = CFrame.new(at - Vector3.new(0, 0.15, 0)), Color = color, Material = Enum.Material.Neon }, holder)
		if n % 3 == 1 then
			local l = Instance.new("PointLight")
			l.Color = color
			l.Range = 7
			l.Brightness = 1.6
			l.Parent = b
		end
		table.insert(bulbs, { part = b, color = color, phase = math.random() * 6 })
		last = at
	end
	task.spawn(function()
		-- along the flight (at most 3 s, 60 bulbs)
		while BR.getSeq() == seq and os.clock() - t0 < 3 and #bulbs < 60 do
			local p = BR.renderPosition()
			if p then
				local at = p - Vector3.new(0, HANG, 0)
				if (at - last).Magnitude >= SPACING then
					addBulb(at)
				end
			end
			RunService.Heartbeat:Wait()
		end
		-- then they twinkle a moment and go out, the oldest first
		local t1 = os.clock()
		while os.clock() - t1 < 1.6 do
			local now = os.clock()
			for i, b in ipairs(bulbs) do
				local out = math.clamp((now - t1) * 1.4 - (i / math.max(#bulbs, 1)) * 0.8, 0, 1)
				local tw = (math.sin(now * 9 + b.phase) > 0.2) and 0 or 0.45
				b.part.Transparency = math.max(out, tw * (1 - out))
			end
			RunService.Heartbeat:Wait()
		end
		holder:Destroy()
	end)
end

local lastSeq = nil
local function watchSets()
	local BR = mods and mods.BallRenderer
	if not BR then
		return
	end
	local seq = BR.getSeq()
	if seq == lastSeq then
		return
	end
	lastSeq = seq
	local meta = BR.getMeta()
	if not (meta and meta.hitType == "Set" and meta.vectorSet and meta.id) then
		return
	end
	local model = Util.modelOf(meta.id)
	if not WinterSkins.is(model, "TwinkleLights") then
		return
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local from = (hrp and hrp.Position + Vector3.new(0, 2.6, 0)) or BR.renderPosition()
	if not from or not camNear(from) then
		return
	end
	stringLights(from, seq)
	if hears() then
		sound("WinterBells", { pos = from, volume = 0.55, minGap = 0.2 })
	end
end

------------------------------------------------------------------------------------------
-- Sleigh Ride: the sleigh, its dive, icicles out of the sky
------------------------------------------------------------------------------------------

-- Santa's sleigh and four reindeer, nose (the lead reindeer's) at the origin facing -Z, `k` times
-- full size (about 34 studs nose to tail at 1). A Model of anchored parts; PivotTo moves it whole.
function WinterSkins.buildSleigh(k, parent)
	k = k or 1
	local m = Instance.new("Model")
	m.Name = "Sleigh"
	local function P(x, y, z)
		return Vector3.new(x, y, z) * k
	end
	local BODY = RED
	local TRIM = GOLD
	local WOOD = Color3.fromRGB(110, 60, 30)
	-- the sleigh, its back end at z = 34, its front at z = 22
	part({ Size = P(6, 3, 9), CFrame = CFrame.new(P(0, 2.5, 28.5)), Color = BODY }, m) -- the tub
	part({ Size = P(6, 3.4, 1.2), CFrame = CFrame.new(P(0, 4.6, 33.4)) * CFrame.Angles(math.rad(-12), 0, 0), Color = BODY }, m) -- the high back
	part({ Size = P(6, 1.6, 2), CFrame = CFrame.new(P(0, 3.6, 23.4)) * CFrame.Angles(math.rad(28), 0, 0), Color = BODY }, m) -- the curled front
	part({ Size = P(6.3, 0.35, 9.3), CFrame = CFrame.new(P(0, 4.05, 28.5)), Color = TRIM, Material = Enum.Material.Metal }, m) -- the rim
	part({ Size = P(5, 1.2, 4), CFrame = CFrame.new(P(0, 4.3, 30)), Color = Color3.fromRGB(120, 20, 30) }, m) -- the seat
	-- Santa's sack behind him, green and tied with gold, and a present on top
	ball(P(0, 6.4, 32), 3.4 * k, Color3.fromRGB(30, 120, 60), m)
	part({ Size = P(1.6, 1.6, 1.6), CFrame = CFrame.new(P(0.6, 8.3, 32.4)) * CFrame.Angles(0, 0.5, 0), Color = Color3.fromRGB(70, 150, 255) }, m)
	part({ Size = P(1.7, 0.3, 0.3), CFrame = CFrame.new(P(0.6, 8.3, 32.4)) * CFrame.Angles(0, 0.5, 0), Color = TRIM }, m)
	-- Santa on the seat in front of his sack: red coat and belt, white beard, his hat's pom
	-- flopping back, holding the reins
	local SKIN = Color3.fromRGB(255, 205, 170)
	local FUR = Color3.fromRGB(250, 250, 245)
	ball(P(0, 5.9, 28.2), 3.6 * k, RED, m) -- body
	part({ Shape = Enum.PartType.Cylinder, Size = P(0.7, 3.65, 3.65), CFrame = CFrame.new(P(0, 5.6, 28.2)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(25, 20, 20) }, m) -- belt
	part({ Size = P(0.9, 0.75, 0.3), CFrame = CFrame.new(P(0, 5.6, 26.35)), Color = TRIM, Material = Enum.Material.Metal }, m) -- buckle
	ball(P(0, 8.3, 27.9), 2 * k, SKIN, m) -- face
	ball(P(0, 7.7, 27.1), 1.9 * k, FUR, m) -- beard
	ball(P(0, 8.5, 26.95), 0.45 * k, Color3.fromRGB(240, 150, 140), m) -- nose
	part({ Shape = Enum.PartType.Cylinder, Size = P(0.55, 2.3, 2.3), CFrame = CFrame.new(P(0, 9.15, 27.95)) * CFrame.Angles(0, 0, math.rad(90)), Color = FUR }, m) -- hat brim
	stick(P(0, 9.2, 27.95), P(0, 10.6, 28.6), 1.6 * k, RED, m) -- hat
	stick(P(0, 10.6, 28.6), P(0, 10.9, 29.6), 0.9 * k, RED, m) -- its tip, flopping back
	ball(P(0, 10.85, 29.9), 0.8 * k, FUR, m) -- pom
	for _, x in ipairs({ -1, 1 }) do
		stick(P(x * 1.5, 6.8, 28), P(x * 1.4, 5.4, 25.6), 0.8 * k, RED, m) -- arms out to the reins
		ball(P(x * 1.4, 5.3, 25.4), 0.8 * k, FUR, m) -- mittens
	end
	-- the runners, gold, curling up at the front
	for _, x in ipairs({ -2.6, 2.6 }) do
		part({ Size = P(0.45, 0.45, 12), CFrame = CFrame.new(P(x, 0.2, 28.5)), Color = TRIM, Material = Enum.Material.Metal }, m)
		stick(P(x, 0.2, 22.5), P(x, 1.6, 21), 0.45 * k, TRIM, m, Enum.Material.Metal)
		stick(P(x, 1.6, 21), P(x, 2.8, 21.6), 0.45 * k, TRIM, m, Enum.Material.Metal)
		for _, z in ipairs({ 25, 32 }) do
			stick(P(x, 0.2, z), P(x * 0.9, 1.2, z), 0.35 * k, TRIM, m, Enum.Material.Metal)
		end
	end
	-- the reindeer, two pairs, the lead pair with Rudolph's red nose
	local deer = Color3.fromRGB(120, 72, 38)
	local antler = Color3.fromRGB(220, 200, 160)
	for row = 0, 1 do
		for _, x in ipairs({ -1.8, 1.8 }) do
			local z = 4 + row * 8 -- (the lead pair at 4, the back pair at 12)
			part({ Size = P(1.6, 1.8, 4.4), CFrame = CFrame.new(P(x, 3.4, z + 2)), Color = deer }, m) -- body
			stick(P(x, 4, z), P(x, 5.6, z - 1.2), 0.9 * k, deer, m) -- neck
			part({ Size = P(1.2, 1.2, 1.8), CFrame = CFrame.new(P(x, 5.9, z - 1.8)), Color = deer }, m) -- head
			ball(P(x, 5.7, z - 2.8), 0.6 * k, (row == 0) and Color3.fromRGB(255, 30, 30) or Color3.fromRGB(40, 25, 20), m, row == 0) -- nose
			for _, side in ipairs({ -1, 1 }) do
				stick(P(x + side * 0.3, 6.4, z - 1.6), P(x + side * 1.1, 7.8, z - 1.2), 0.22 * k, antler, m)
				stick(P(x + side * 1.1, 7.8, z - 1.2), P(x + side * 1.6, 8.4, z - 1.8), 0.18 * k, antler, m)
				stick(P(x + side * 0.9, 7.4, z - 1.3), P(x + side * 0.5, 8.2, z - 1.7), 0.16 * k, antler, m)
			end
			-- legs mid-gallop
			stick(P(x, 2.6, z + 0.4), P(x, 1, z - 1), 0.4 * k, deer, m)
			stick(P(x, 2.6, z + 3.6), P(x, 1, z + 5), 0.4 * k, deer, m)
		end
	end
	-- the reins: gold lines from the sleigh to each pair
	for _, x in ipairs({ -1.8, 1.8 }) do
		stick(P(x * 0.78, 5.3, 25.4), P(x, 3.8, 14), 0.15 * k, TRIM, m, Enum.Material.Neon)
		stick(P(x, 3.8, 10), P(x, 3.8, 6), 0.15 * k, TRIM, m, Enum.Material.Neon)
	end
	-- the nose of the whole thing (the lead reindeer's) is the pivot
	local pivot = part({ Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(P(0, 3.4, 0)), Transparency = 1 }, m)
	m.PrimaryPart = pivot
	m.Parent = parent
	return m
end

local function fadeModel(m, a)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= m.PrimaryPart then
			d.Transparency = a
		end
	end
end

-- The sleigh dives out of the sky onto `target` in `secs`, bells ringing and sparkles streaming
-- off it, skims the floor in a burst of snow and presents, and pulls back up into the sky.
-- dirZ: which way the spike flies. h: VFXController's helpers (floorRing, flash, shake).
function WinterSkins.sleighDive(target, dirZ, inferno, secs, h)
	if not camNear(target) then
		return
	end
	-- (the size of Kuro's dragon: the owner, 2026-11-17, "its too small compared to kuro's actual
	-- dragon"; its head alone is 40 studs)
	-- (then 2026-11-18: "its way smaller and basically unnoticeable compared to the actual dragon":
	-- the dragon is about 340 studs nose to tail, the sleigh and its reindeer were 76; now 210 to 260)
	local SCALE = inferno and 7.5 or 6
	local m = WinterSkins.buildSleigh(SCALE, fx())
	local from = target + Vector3.new(0, 62 * SCALE * 0.6, -dirZ * 38 * SCALE * 0.6)
	-- (its pivot is the lead reindeer's nose and the sleigh trails 34 x SCALE behind: the bottom of the
	-- dive sits high enough that the tail stays over the floor as it levels out)
	local low = target + Vector3.new(0, 8 * SCALE, 0)
	local way = (low - from).Unit
	local up = target + Vector3.new(0, 70 * SCALE * 0.7, dirZ * 70 * SCALE * 0.7)
	if hears() then
		sound("WinterSleigh", { volume = 0.9, seconds = 2.2 })
		sound("WinterHoHo", { volume = inferno and 1 or 0.8 })
	end
	task.spawn(function()
		local t0, nextSpark = os.clock(), 0
		while true do
			local now = os.clock() - t0
			local u = math.min(now / secs, 1)
			local nose = from:Lerp(low, u ^ 2.1)
			m:PivotTo(CFrame.lookAt(nose, nose + way))
			if now >= nextSpark then
				nextSpark = now + 0.05
				local tail = nose - way * 14 * SCALE
				Fx.play("Glints", tail, { color = GOLD, scale = 0.64 * SCALE })
				Fx.play("Dust", tail - way * 2 * SCALE, { color = SNOW, scale = 0.73 * SCALE })
			end
			if u >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		-- down: a burst of snow and presents
		local floor = Vector3.new(target.X, 0.3, target.Z)
		if h then
			pcall(h.floorRing, floor, ICE, inferno and 28 or 18)
			pcall(h.flash, inferno and 0.85 or 0.6, inferno and 0.35 or 0.25)
			pcall(h.shake, inferno and 1 or 0.7)
		end
		Fx.play("JumpSnowburst", floor + Vector3.new(0, 1, 0), { scale = inferno and 2.6 or 1.9 })
		Fx.play("JumpPresent", floor + Vector3.new(0, 2, 0), { scale = inferno and 2 or 1.5 })
		Fx.play("ChainExplosion", floor + Vector3.new(0, 2, 0), { color = ICE, scale = inferno and 2 or 1.4 })
		if hears() then
			sound("WinterIce", { pos = floor, volume = 0.8 })
			sound("Boom", { pos = floor, volume = 0.6 })
		end
		-- and away, climbing back into the sky the way the spike went, fading as it goes
		local t1 = os.clock()
		local start = low
		-- (it levels out of the dive and climbs at a gentle, growing angle: pointed straight at the sky
		-- the long sleigh behind the nose swung down through the court, the owner, 2026-11-18: "now
		-- santa is coming out of the ground")
		local climbDir = Vector3.new(0, 0, dirZ)
		while true do
			local u = math.min((os.clock() - t1) / 0.7, 1)
			local p = start:Lerp(up, u ^ 1.6)
			local climb = (climbDir + Vector3.new(0, 0.08 + 0.55 * u, 0)).Unit
			local look = way:Lerp(climb, math.min(1, u / 0.18))
			if look.Magnitude < 0.05 then
				look = climb
			end
			m:PivotTo(CFrame.lookAt(p, p + look))
			fadeModel(m, math.clamp((u - 0.4) / 0.6, 0, 1))
			if u >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		m:Destroy()
	end)
end

-- Icicles drop out of the cracked sky round `pos` and shatter into snow on the floor.
function WinterSkins.icicles(pos, count)
	if not camNear(pos) then
		return
	end
	local holder = fx()
	for i = 1, count or 7 do
		task.delay(i * 0.07 + math.random() * 0.1, function()
			local x = pos.X + (math.random() - 0.5) * 26
			local z = pos.Z + (math.random() - 0.5) * 40
			local len = 3 + math.random() * 3.5
			-- a long point down: two wedges back to back (their tall faces together, the slopes
			-- meeting at the tip below), a frosted cap on top
			local ice = Instance.new("Model")
			local w = 0.7 + math.random() * 0.5
			for _, side in ipairs({ 1, -1 }) do
				local a = Instance.new("WedgePart")
				a.Size = Vector3.new(w, len, w / 2)
				a.CFrame = CFrame.new(0, -len / 2, side * w / 4) * CFrame.Angles(math.pi, side > 0 and 0 or math.pi, 0)
				a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch, a.CastShadow = true, false, false, false, false
				a.Color, a.Material, a.Transparency = side > 0 and ICE or SNOW, Enum.Material.Glass, 0.12
				a.Parent = ice
			end
			local cap = part({ Size = Vector3.new(w * 1.2, 0.35, w * 1.2), CFrame = CFrame.new(0, 0.1, 0), Color = SNOW, Material = Enum.Material.Snow }, ice)
			ice.PrimaryPart = cap
			ice.Parent = holder
			local y0 = 58 + math.random() * 10
			local t0 = os.clock()
			local fall = 0.55 + math.random() * 0.2
			while true do
				local u = math.min((os.clock() - t0) / fall, 1)
				local y = y0 + (len - y0) * u * u
				ice:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, u * 2, 0))
				if u >= 1 then
					break
				end
				RunService.Heartbeat:Wait()
			end
			ice:Destroy()
			Fx.play("JumpSnowburst", Vector3.new(x, 0.6, z), { scale = 0.7 })
			if i == 1 and hears() then
				sound("WinterIce", { pos = Vector3.new(x, 1, z), volume = 0.7, minGap = 0.15 })
			end
		end)
	end
end

------------------------------------------------------------------------------------------
-- Star Topper: ornaments
------------------------------------------------------------------------------------------

-- Ornaments flung out of `pos` that fall and wink out; k: how many and how far (about 0.5..2).
function WinterSkins.ornaments(pos, k)
	if not camNear(pos) then
		return
	end
	k = k or 1
	local holder = fx()
	local list = {}
	for i = 1, math.floor(8 + 6 * k) do
		local a = math.random() * math.pi * 2
		local v = Vector3.new(math.cos(a) * (8 + math.random() * 10) * k, 14 + math.random() * 14, math.sin(a) * (8 + math.random() * 10) * k)
		local color = BULBS[(i - 1) % 4 + 1]
		local b = ball(pos, 0.9 + math.random() * 0.5, color, holder, false)
		b.Material = Enum.Material.Glass
		b.Reflectance = 0.25
		local cap = part({ Size = Vector3.new(0.3, 0.25, 0.3), Color = GOLD, Material = Enum.Material.Metal }, holder)
		table.insert(list, { b = b, cap = cap, v = v })
	end
	Fx.play("JumpPresent", pos, { scale = 1 + 0.6 * k })
	Fx.play("Glints", pos, { color = GOLD, scale = 1.5 + k })
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 1.3 do
			local t = os.clock() - t0
			for _, o in ipairs(list) do
				local p = pos + o.v * t + Vector3.new(0, -40 * t * t, 0)
				if p.Y < 0.6 then
					p = Vector3.new(p.X, 0.6, p.Z)
				end
				o.b.CFrame = CFrame.new(p)
				o.cap.CFrame = CFrame.new(p + Vector3.new(0, o.b.Size.Y / 2, 0))
				local fade = math.clamp((t - 0.9) / 0.4, 0, 1)
				o.b.Transparency = fade
				o.cap.Transparency = fade
			end
			RunService.Heartbeat:Wait()
		end
		for _, o in ipairs(list) do
			o.b:Destroy()
			o.cap:Destroy()
		end
	end)
end

------------------------------------------------------------------------------------------
-- the recruit pulls
------------------------------------------------------------------------------------------

-- ctx (MenuController): root (a full-screen frame to draw in), alive() (false once the recruit is
-- cut), tween(obj, t, props, style), make(class, props, parent), flash (the sequence's flash frame),
-- glow (the glow image), title(after) (the skin's name and line, Extra.mythicTitle).

local function canvas(ctx, root)
	-- a 1600 x 900 canvas centred on the screen (the menu's root is under a UIScale)
	return ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), BackgroundTransparency = 1, ZIndex = 42 }, root)
end

-- Where `pos` shows on the 1600 x 900 canvas through a full-canvas ViewportFrame's camera, or nil
-- behind it. (By hand: that camera's WorldToViewportPoint answers in the screen's pixels, not the
-- frame's, and the sleigh's sparkles all landed in a corner.)
local function project(cam, pos)
	local rel = cam.CFrame:PointToObjectSpace(pos)
	if rel.Z > -0.1 then
		return nil
	end
	local fy = math.tan(math.rad(cam.FieldOfView) / 2)
	return (0.5 + rel.X / -rel.Z / (fy * 1600 / 900) * 0.5) * 1600, (0.5 - rel.Y / -rel.Z / fy * 0.5) * 900
end

local function line(ctx, parent, x1, y1, x2, y2, w, color, z)
	local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	return ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(math.floor((x1 + x2) / 2), math.floor((y1 + y2) / 2)), Size = UDim2.fromOffset(math.floor(len + 1), w), Rotation = math.deg(math.atan2(y2 - y1, x2 - x1)), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z or 43 }, parent)
end

local function wait(ctx, secs, tick)
	local t0 = os.clock()
	while os.clock() - t0 < secs do
		if not ctx.alive() then
			return false
		end
		if tick then
			tick()
		end
		RunService.RenderStepped:Wait()
	end
	return ctx.alive()
end

local function burstTo(ctx, color)
	ctx.flash.BackgroundColor3 = color
	ctx.flash.BackgroundTransparency = 0.15
	ctx.tween(ctx.flash, 0.6, { BackgroundTransparency = 1 })
end

-- Lights: a dark night; three strings of lights sweep across the screen in swags, every bulb dark,
-- then they come on one after another along the strings, blink together, and burst into him.
local function lightsPull(ctx, root)
	local bg = ctx.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 41 }, root)
	ctx.make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(4, 8, 22), Color3.fromRGB(10, 22, 56)) }, bg)
	local c = canvas(ctx, root)
	local snow = ctx.snow and ctx.snow(root) or nil
	local snowT0 = os.clock()
	local function drift()
		if snow and ctx.fallSnow then
			ctx.fallSnow(snow, os.clock() - snowT0)
		end
	end
	local STRINGS = { { y = 190, sag = 70 }, { y = 450, sag = 90 }, { y = 710, sag = 70 } }
	local SWAGS, PER = 4, 12
	local bulbs = {}
	sound("WinterBells", { volume = 0.7 })
	for si, s in ipairs(STRINGS) do
		local pts = {}
		for sw = 0, SWAGS - 1 do
			for i = 0, PER do
				local t = i / PER
				table.insert(pts, { x = -40 + (sw + t) * (1680 / SWAGS), y = s.y + s.sag * 4 * t * (1 - t) + (si % 2 == 0 and -10 or 10) })
			end
		end
		-- the wire, drawn out left to right (alternating ways)
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local seg = line(ctx, c, a.x, a.y, b.x, b.y, 3, Color3.fromRGB(14, 40, 22), 43)
			seg.Visible = false
			task.delay(0.15 + (si - 1) * 0.12 + i * 0.006, function()
				seg.Visible = true
			end)
		end
		for i, pt in ipairs(pts) do
			if i % 4 == 0 then
				local color = BULBS[(#bulbs) % #BULBS + 1]
				local glow = ctx.make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(pt.x, pt.y + 16), Size = UDim2.fromOffset(110, 110), BackgroundTransparency = 1, Image = ctx.glow, ImageColor3 = color, ImageTransparency = 1, ZIndex = 42 }, c)
				ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(pt.x, pt.y - 2), Size = UDim2.fromOffset(9, 7), BackgroundColor3 = Color3.fromRGB(30, 40, 30), BorderSizePixel = 0, ZIndex = 44 }, c)
				local b = ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(pt.x, pt.y + 4), Size = UDim2.fromOffset(16, 24), BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.75), BorderSizePixel = 0, ZIndex = 44 }, c)
				ctx.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
				table.insert(bulbs, { bulb = b, glow = glow, color = color, at = 0.9 + #bulbs * 0.032 })
			end
		end
	end
	-- on, one by one
	local t0 = os.clock()
	local lit = 0
	sound("WinterSparkle", { volume = 0.6, seconds = 3.5 })
	while lit < #bulbs do
		if not ctx.alive() then
			return false
		end
		local t = os.clock() - t0
		while lit < #bulbs and t >= bulbs[lit + 1].at do
			lit = lit + 1
			local b = bulbs[lit]
			b.bulb.BackgroundColor3 = b.color
			b.glow.ImageTransparency = 0.35
			if lit % 6 == 0 then
				sound("WinterJingle", { volume = 0.25, minGap = 0.05 })
			end
		end
		drift()
		RunService.RenderStepped:Wait()
	end
	-- all of them blink together three times
	for k = 1, 3 do
		for _, b in ipairs(bulbs) do
			b.bulb.BackgroundColor3 = b.color:Lerp(Color3.new(0, 0, 0), 0.7)
			b.glow.ImageTransparency = 1
		end
		if not wait(ctx, 0.12, drift) then
			return false
		end
		for _, b in ipairs(bulbs) do
			b.bulb.BackgroundColor3 = b.color:Lerp(Color3.new(1, 1, 1), 0.2 * k)
			b.glow.ImageTransparency = 0.3 - 0.08 * k
		end
		sound("WinterBells", { volume = 0.5 + 0.15 * k, minGap = 0 })
		if not wait(ctx, 0.2, drift) then
			return false
		end
	end
	burstTo(ctx, Color3.fromRGB(220, 240, 255))
	sound("WinterGift", { volume = 1 })
	c:Destroy()
	if snow then
		snow.frame:Destroy()
	end
	bg.BackgroundTransparency = 0
	ctx.title(0.2) -- (it holds the name up a while: Extra.mythicTitle)
	return ctx.alive()
end

-- Sleigh: a moonlit sky with snow falling; bells first, then the sleigh and its reindeer dash
-- across the moon trailing sparkles, a "ho ho ho" as it passes; the sparkles gather into a burst.
local function sleighPull(ctx, root)
	local bg = ctx.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 41 }, root)
	ctx.make("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(4, 8, 30)), ColorSequenceKeypoint.new(0.7, Color3.fromRGB(16, 34, 84)), ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 70, 130)) }) }, bg)
	local c = canvas(ctx, root)
	-- stars, the moon
	for _ = 1, 70 do
		local s = math.random(2, 4)
		local st = ctx.make("Frame", { Position = UDim2.fromOffset(math.random(0, 1600), math.random(0, 620)), Size = UDim2.fromOffset(s, s), BackgroundColor3 = SNOW, BackgroundTransparency = math.random() * 0.5, BorderSizePixel = 0, ZIndex = 42 }, c)
		ctx.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, st)
	end
	ctx.make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(1000, 330), Size = UDim2.fromOffset(760, 760), BackgroundTransparency = 1, Image = ctx.glow, ImageColor3 = Color3.fromRGB(200, 225, 255), ImageTransparency = 0.55, ZIndex = 42 }, c)
	local moon = ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(1000, 330), Size = UDim2.fromOffset(300, 300), BackgroundColor3 = Color3.fromRGB(250, 250, 236), BorderSizePixel = 0, ZIndex = 43 }, c)
	ctx.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, moon)
	-- hills of snow along the bottom
	for i = 0, 3 do
		local hill = ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(i * 520, 740 - (i % 2) * 40), Size = UDim2.fromOffset(1000, 1000), BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(226, 238, 252) or Color3.fromRGB(206, 224, 246), BorderSizePixel = 0, ZIndex = 44 + (i % 2 == 0 and 1 or 0) }, c)
		ctx.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, hill)
	end
	local snow = ctx.snow and ctx.snow(root) or nil
	-- the sleigh in a viewport over it all
	local vp = ctx.make("ViewportFrame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), BackgroundTransparency = 1, Ambient = Color3.fromRGB(120, 130, 170), LightColor = Color3.fromRGB(255, 245, 225), LightDirection = Vector3.new(-0.4, -0.7, -0.6), ZIndex = 46 }, c)
	local cam = ctx.make("Camera", { FieldOfView = 40, CFrame = CFrame.lookAt(Vector3.new(0, 0, 120), Vector3.zero) }, vp)
	vp.CurrentCamera = cam
	local sleigh = WinterSkins.buildSleigh(1, vp)
	sound("WinterSleigh", { volume = 0.9, seconds = 4 })
	if not wait(ctx, 0.6) then
		return false
	end
	-- across, left to right, rising a little over the moon, bobbing
	local dash = 2.2
	local t0, nextSpark, hoho = os.clock(), 0, false
	while true do
		if not ctx.alive() then
			return false
		end
		local t = os.clock() - t0
		local u = math.min(t / dash, 1)
		local x = -120 + 260 * u
		local y = -8 + 26 * u + math.sin(t * 7) * 1.2
		local p = Vector3.new(x, y, 0)
		local dir = Vector3.new(1, 0.1, 0)
		-- (the model's nose is -Z: it faces the way it flies, a quarter turned toward us)
		sleigh:PivotTo(CFrame.lookAt(p, p + dir) * CFrame.Angles(0, math.rad(-18), 0))
		if t >= nextSpark then
			nextSpark = t + 0.03
			-- a sparkle left on the screen where the sleigh's tail is
			local sx, sy = project(cam, p - dir.Unit * 30)
			if sx then
				local dot = ctx.make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(sx + math.random(-12, 12), sy + math.random(-10, 10)), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1, Image = ctx.sparkle or ctx.glow, ImageColor3 = (math.random() < 0.5) and GOLD or SNOW, ZIndex = 45 }, c)
				ctx.tween(dot, 1.2, { Size = UDim2.fromOffset(6, 6), ImageTransparency = 1, Position = UDim2.fromOffset(sx, sy + 70) })
				task.delay(1.25, function()
					dot:Destroy()
				end)
			end
		end
		if u > 0.45 and not hoho then
			hoho = true
			sound("WinterHoHo", { volume = 1 })
		end
		if snow and ctx.fallSnow then
			ctx.fallSnow(snow, t)
		end
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	vp:Destroy()
	burstTo(ctx, Color3.fromRGB(255, 236, 200))
	sound("WinterJingle", { volume = 0.9 })
	ctx.title(0.25)
	if snow then
		snow.frame:Destroy()
	end
	return ctx.alive()
end

-- Tree: dark, snow falling; a Christmas tree (FxMeshes' FX_Tree) grows up out of the floor, its
-- ornaments pop on one by one, the star on top lights, swells and bursts into him.
local function treePull(ctx, root)
	local bg = ctx.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 41 }, root)
	ctx.make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(3, 10, 8), Color3.fromRGB(10, 34, 22)) }, bg)
	local c = canvas(ctx, root)
	local snow = ctx.snow and ctx.snow(root) or nil
	local vp = ctx.make("ViewportFrame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), BackgroundTransparency = 1, Ambient = Color3.fromRGB(110, 120, 110), LightColor = Color3.fromRGB(255, 240, 210), LightDirection = Vector3.new(-0.5, -0.6, -0.7), ZIndex = 44 }, c)
	local cam = ctx.make("Camera", { FieldOfView = 32, CFrame = CFrame.lookAt(Vector3.new(0, 6.5, 30), Vector3.new(0, 6.5, 0)) }, vp)
	vp.CurrentCamera = cam
	local H = 13 -- the tree's height in the viewport
	local folderMesh = ReplicatedStorage:FindFirstChild("FxMeshes")
	local tpl = folderMesh and folderMesh:FindFirstChild("FX_Tree", true)
	local tree, native = nil, nil
	if tpl and tpl:IsA("MeshPart") then
		tree = tpl:Clone()
		native = tree.Size
		tree.Anchored = true
		tree.Parent = vp
	else
		-- (no mesh in the place: a stack of green tiers)
		tree = Instance.new("Model")
		for i = 0, 4 do
			local w = 9 - i * 1.7
			part({ Size = Vector3.new(w, 2.6, w), CFrame = CFrame.new(0, 1.8 + i * 2.2, 0) * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(30, 120, 60) }, tree)
		end
		part({ Size = Vector3.new(1.4, 1.6, 1.4), CFrame = CFrame.new(0, 0.8, 0), Color = Color3.fromRGB(100, 60, 30) }, tree)
		tree.Parent = vp
	end
	local function growTree(s)
		s = math.max(s, 0.01)
		if native then
			local k = H / native.Y * s
			tree.Size = native * k
			tree.CFrame = CFrame.new(0, tree.Size.Y / 2, 0)
		else
			tree:ScaleTo(s)
			tree:PivotTo(CFrame.new(0, 0, 0))
		end
	end
	growTree(0.01)
	sound("WinterSparkle", { volume = 0.7, seconds = 4 })
	-- up out of the floor, a little overshoot
	local t0 = os.clock()
	while true do
		if not ctx.alive() then
			return false
		end
		local u = math.min((os.clock() - t0) / 0.9, 1)
		local back = 1 + 2.2 * (u - 1) ^ 3 + 1.2 * (u - 1) ^ 2
		growTree(back)
		if snow and ctx.fallSnow then
			ctx.fallSnow(snow, os.clock() - t0)
		end
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	growTree(1)
	-- strings of fairy lights draped along the edge of each tier, coming on bottom to top (the tree
	-- has its own baubles: these glow), just over each tier's lower edge (FX_Tree's, at H = 13).
	local spots = {}
	local RIMS = { { 2.2, 3.75, 8 }, { 4.7, 2.95, 7 }, { 6.8, 2.25, 6 }, { 8.65, 1.55, 5 } }
	for _, rim in ipairs(RIMS) do
		local y, r, n = rim[1], rim[2], rim[3]
		for j = 0, n - 1 do
			local u = j / (n - 1)
			local a = math.rad(-75 + 150 * u)
			-- (a little droop between the ends, as a string hangs)
			table.insert(spots, { pos = Vector3.new(math.sin(a) * r, y - 0.15 * math.sin(u * math.pi), math.cos(a) * r), first = j == 0 })
		end
	end
	for i, spot in ipairs(spots) do
		local p = spot.pos
		local color = BULBS[(i - 1) % #BULBS + 1]
		if not spot.first then
			stick(spots[i - 1].pos, p, 0.08, Color3.fromRGB(16, 44, 24), vp) -- the wire to the last one
		end
		local b = ball(p, 0.01, color, vp, true)
		ctx.tween(b, 0.14, { Size = Vector3.new(0.5, 0.5, 0.5) }, Enum.EasingStyle.Back)
		if i % 4 == 1 then
			sound("WinterJingle", { volume = 0.25, minGap = 0.04 })
		end
		if not wait(ctx, 0.04) then
			return false
		end
		if snow and ctx.fallSnow then
			ctx.fallSnow(snow, os.clock() - t0)
		end
	end
	-- the star: a gold four-point star over the top, lighting and swelling
	local sx, sy = project(cam, Vector3.new(0, H + 0.4, 0))
	sx, sy = sx or 800, sy or 140
	local halo = ctx.make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(sx, sy), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, Image = ctx.glow, ImageColor3 = GOLD, ImageTransparency = 0.2, ZIndex = 46 }, c)
	local star = ctx.make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(sx, sy), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = ctx.sparkle or ctx.glow, ImageColor3 = Color3.fromRGB(255, 230, 120), ZIndex = 47 }, c)
	sound("WinterGift", { volume = 1 })
	ctx.tween(halo, 0.6, { Size = UDim2.fromOffset(360, 360) }, Enum.EasingStyle.Quint)
	ctx.tween(star, 0.6, { Size = UDim2.fromOffset(130, 130), Rotation = 45 }, Enum.EasingStyle.Back)
	if not wait(ctx, 0.9) then
		return false
	end
	-- and it bursts: gold over everything
	ctx.tween(star, 0.25, { Size = UDim2.fromOffset(1400, 1400), ImageTransparency = 1, Rotation = 120 })
	ctx.tween(halo, 0.25, { Size = UDim2.fromOffset(2600, 2600), ImageTransparency = 1 })
	sound("WinterJingle", { volume = 0.9 })
	sound("Boom", { volume = 0.5 })
	if not wait(ctx, 0.12) then
		return false
	end
	burstTo(ctx, Color3.fromRGB(255, 230, 150))
	vp:Destroy()
	ctx.title(0.25)
	if snow then
		snow.frame:Destroy()
	end
	return ctx.alive()
end

-- Jaja's recruit (the owner, 2026-11-16: "make a jaja recruit pull, maybe cards swirl in from the
-- side and circle the middle and split open to reveal him"): a dark stage; playing cards sweep in
-- from both sides and fall into a ring round the middle, orbiting faster and tighter, flipping as
-- they go; they snap together into one big JOKER card, which splits down the middle in a burst of
-- red light, and he's there.
local SUITS = { "♠", "♥", "♦", "♣" }
local JOKER_RED = Color3.fromRGB(214, 30, 44)
local JOKER_INK = Color3.fromRGB(24, 18, 30)

-- A playing card on the canvas: its back (red, a white diamond) and its face (white, a suit or the
-- joker's mark), one shown at a time.
local function playingCard(ctx, parent, w, h, faceText, faceColor, z)
	local card = ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, ZIndex = z }, parent)
	local back = ctx.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = JOKER_RED, BorderSizePixel = 0, ZIndex = z }, card)
	ctx.make("UICorner", { CornerRadius = UDim.new(0, math.floor(w * 0.1)) }, back)
	ctx.make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3 }, back)
	local mark = ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(math.floor(w * 0.42), math.floor(w * 0.42)), Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = z + 1 }, back)
	ctx.make("UIStroke", { Color = Color3.fromRGB(120, 10, 20), Thickness = 2 }, mark)
	local face = ctx.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(250, 248, 242), BorderSizePixel = 0, Visible = false, ZIndex = z }, card)
	ctx.make("UICorner", { CornerRadius = UDim.new(0, math.floor(w * 0.1)) }, face)
	ctx.make("UIStroke", { Color = JOKER_INK, Thickness = 2 }, face)
	ctx.make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 0.6), BackgroundTransparency = 1, Text = faceText, TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = faceColor, ZIndex = z + 1 }, face)
	return { frame = card, back = back, face = face }
end

local function jokerPull(ctx, root)
	local bg = ctx.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 41 }, root)
	ctx.make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(16, 6, 22), Color3.fromRGB(46, 8, 20)) }, bg)
	local c = canvas(ctx, root)
	local CX, CY = 800, 450
	-- a soft red glow in the middle that swells as the cards close in
	local glow = ctx.make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CX, CY), Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1, Image = ctx.glow, ImageColor3 = JOKER_RED, ImageTransparency = 0.7, ZIndex = 42 }, c)
	sound("WinterCardFlip", { volume = 0.9 })
	-- the cards: half from the left, half from the right, each with its own place on the ring
	local N = 16
	local cards = {}
	for i = 1, N do
		local fromLeft = i % 2 == 1
		local suit = SUITS[(i - 1) % #SUITS + 1]
		local red = suit == "♥" or suit == "♦"
		local pc = playingCard(ctx, c, 92, 132, suit, red and JOKER_RED or JOKER_INK, 44 + (i % 3))
		local sx = fromLeft and (-160 - math.random(0, 220)) or (1760 + math.random(0, 220))
		local sy = 120 + math.random() * 660
		pc.frame.Position = UDim2.fromOffset(sx, sy)
		table.insert(cards, { pc = pc, sx = sx, sy = sy, a0 = (i - 1) / N * math.pi * 2, delay = (i - 1) * 0.035, flipped = false })
	end
	-- 1. in from the sides onto the ring (0..1.05 s), 2. round and round, faster and tighter
	-- (1.05..2.35 s), 3. into the middle (2.35..2.75 s)
	local T_IN, T_ORBIT, T_IN2 = 1.05, 2.35, 2.75
	local t0 = os.clock()
	local lastFlip = 0
	while true do
		if not ctx.alive() then
			return false
		end
		local t = os.clock() - t0
		if t >= T_IN2 then
			break
		end
		-- the spin: slow while they arrive, then winding up
		local spin = t * 1.2 + math.max(0, t - T_IN) ^ 2 * 2.6
		local radius = 300
		if t > T_IN then
			radius = 300 - 90 * math.min((t - T_IN) / (T_ORBIT - T_IN), 1)
		end
		if t > T_ORBIT then
			local u = (t - T_ORBIT) / (T_IN2 - T_ORBIT)
			radius = 210 * (1 - u * u)
		end
		for _, cd in ipairs(cards) do
			local a = cd.a0 + spin
			local rx, ry = CX + math.cos(a) * radius, CY + math.sin(a) * radius * 0.62
			local x, y = rx, ry
			local u = math.clamp((t - cd.delay) / (T_IN - 0.2), 0, 1)
			if u < 1 then
				-- a curving sweep in from the side
				local e = 1 - (1 - u) ^ 3
				local bend = math.sin(e * math.pi) * 140 * (cd.sx < 0 and -1 or 1)
				x = cd.sx + (rx - cd.sx) * e
				y = cd.sy + (ry - cd.sy) * e + bend
			end
			cd.pc.frame.Position = UDim2.fromOffset(x, y)
			cd.pc.frame.Rotation = math.deg(a) + 90
			-- each card flips face up once it's on the ring
			if not cd.flipped and t > T_IN + cd.delay * 2 then
				cd.flipped = true
				cd.pc.back.Visible = false
				cd.pc.face.Visible = true
				if t - lastFlip > 0.06 then
					lastFlip = t
					sound("WinterCardFlip", { volume = 0.35, minGap = 0.05 })
				end
			end
		end
		glow.Size = UDim2.fromOffset(300 + t * 180, 300 + t * 180)
		glow.ImageTransparency = math.max(0.25, 0.7 - t * 0.17)
		RunService.RenderStepped:Wait()
	end
	-- 4. they snap together into one big card: the Joker
	for _, cd in ipairs(cards) do
		cd.pc.frame:Destroy()
	end
	sound("WinterBells", { volume = 0.8 })
	local W, H = 300, 430
	-- (two halves of the same card, so it can split down the middle)
	local halves = {}
	for k, side in ipairs({ -1, 1 }) do
		-- (each clip PAD wider at its outer edge, top and bottom, so the card's outline isn't cut off)
		local PAD = 8
		local clip = ctx.make("Frame", { AnchorPoint = Vector2.new(side < 0 and 1 or 0, 0.5), Position = UDim2.fromOffset(CX, CY), Size = UDim2.fromOffset(W / 2 + PAD, H + PAD * 2), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 46 }, c)
		local whole = ctx.make("Frame", { Position = UDim2.fromOffset(side < 0 and PAD or -W / 2, PAD), Size = UDim2.fromOffset(W, H), BackgroundColor3 = Color3.fromRGB(250, 248, 242), BorderSizePixel = 0, ZIndex = 46 }, clip)
		ctx.make("UICorner", { CornerRadius = UDim.new(0, 26) }, whole)
		ctx.make("UIStroke", { Color = JOKER_RED, Thickness = 6 }, whole)
		ctx.make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(W, 130), BackgroundTransparency = 1, Text = "★", TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = JOKER_RED, ZIndex = 47 }, whole)
		ctx.make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.fromOffset(W - 30, 60), BackgroundTransparency = 1, Text = "JOKER", TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = JOKER_INK, ZIndex = 47 }, whole)
		for _, corner in ipairs({ { 0.1, 0.07 }, { 0.9, 0.93 } }) do
			ctx.make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(corner[1], corner[2]), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, Text = "J", TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = JOKER_RED, ZIndex = 47 }, whole)
		end
		local scale = ctx.make("UIScale", { Scale = 0.3 }, clip)
		ctx.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		halves[k] = { clip = clip, side = side }
	end
	ctx.tween(glow, 0.3, { Size = UDim2.fromOffset(820, 820), ImageTransparency = 0.15 })
	if not wait(ctx, 0.75) then
		return false
	end
	-- 5. it splits down the middle: the halves fly apart, red light pours out, and he's there
	sound("WinterGift", { volume = 1 })
	sound("Boom", { volume = 0.5 })
	-- the light through the split: a white core going red, soft at both edges
	local beam = ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CX, CY), Size = UDim2.fromOffset(8, H), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 45 }, c)
	ctx.make("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, JOKER_RED), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 236, 236)), ColorSequenceKeypoint.new(1, JOKER_RED) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) }),
	}, beam)
	ctx.tween(beam, 0.35, { Size = UDim2.fromOffset(760, 1200) }, Enum.EasingStyle.Quint)
	-- (straight out, no tilt: a turned frame stops clipping and both halves showed whole)
	for _, hv in ipairs(halves) do
		ctx.tween(hv.clip, 0.45, { Position = UDim2.fromOffset(CX + hv.side * 900, CY) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	if not wait(ctx, 0.3) then
		return false
	end
	burstTo(ctx, Color3.fromRGB(255, 200, 200))
	c:Destroy()
	bg.BackgroundTransparency = 0
	ctx.title(0.2)
	return ctx.alive()
end

-- Candy (Candy Claw, Horang's): a snowy night; three claw marks rip down across the screen one after
-- another in candy-cane stripes, the screen jolting with each, a roar, the marks flare and burst
-- into her.
local function candyPull(ctx, root)
	local bg = ctx.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 41 }, root)
	ctx.make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(14, 10, 34), Color3.fromRGB(40, 20, 54)) }, bg)
	local c = canvas(ctx, root)
	local snow = ctx.snow and ctx.snow(root) or nil
	local snowT0 = os.clock()
	local function drift()
		if snow and ctx.fallSnow then
			ctx.fallSnow(snow, os.clock() - snowT0)
		end
	end
	-- a pair of eyes in the dark first, then the swipe
	local eyes = {}
	for _, x in ipairs({ 730, 870 }) do
		local e = ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 420), Size = UDim2.fromOffset(70, 4), BackgroundColor3 = Color3.fromRGB(255, 220, 120), BorderSizePixel = 0, ZIndex = 44 }, c)
		ctx.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, e)
		ctx.make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(180, 120), BackgroundTransparency = 1, Image = ctx.glow, ImageColor3 = Color3.fromRGB(255, 190, 80), ImageTransparency = 0.4, ZIndex = 43 }, e)
		table.insert(eyes, e)
	end
	for _, e in ipairs(eyes) do
		ctx.tween(e, 0.25, { Size = UDim2.fromOffset(70, 30) })
	end
	if not wait(ctx, 0.7, drift) then
		return false
	end
	for _, e in ipairs(eyes) do
		ctx.tween(e, 0.15, { Size = UDim2.fromOffset(70, 2) })
	end
	-- the three marks, each a candy-striped slash drawn down-left in an instant
	local marks = {}
	for i = 1, 3 do
		local x = 560 + (i - 1) * 240
		local m = ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x + 120, 80), Size = UDim2.fromOffset(46, 0), Rotation = 24, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 45 }, c)
		ctx.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, m)
		WinterSkins.candyStripes(m, 5)
		local glow = ctx.make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(4, 0, 1.1, 0), BackgroundTransparency = 1, Image = ctx.glow, ImageColor3 = WinterSkins.CANDY, ImageTransparency = 0.5, ZIndex = 44 }, m)
		table.insert(marks, { frame = m, glow = glow })
	end
	for i, mk in ipairs(marks) do
		if not wait(ctx, 0.14, drift) then
			return false
		end
		ctx.tween(mk.frame, 0.12, { Size = UDim2.fromOffset(46, 760) })
		sound("WinterIce", { volume = 0.5, minGap = 0 })
		c.Position = UDim2.new(0.5, (i % 2 == 0 and -14 or 14), 0.5, 8)
		ctx.tween(c, 0.2, { Position = UDim2.fromScale(0.5, 0.5) })
	end
	sound("Bloodlust", { volume = 0.9 })
	sound("WinterJingle", { volume = 0.5 })
	-- the roar: the marks flare white-hot, the screen shakes, peppermint swirls burst out
	for k = 1, 8 do
		c.Position = UDim2.new(0.5, math.random(-12, 12), 0.5, math.random(-10, 10))
		for _, mk in ipairs(marks) do
			mk.glow.ImageTransparency = 0.5 - k * 0.05
		end
		if not wait(ctx, 0.05, drift) then
			return false
		end
	end
	c.Position = UDim2.fromScale(0.5, 0.5)
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local p = ctx.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(800, 460), Size = UDim2.fromOffset(54, 54), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 46 }, c)
		ctx.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, p)
		WinterSkins.candyStripes(p, 4)
		ctx.tween(p, 0.6, { Position = UDim2.fromOffset(800 + math.cos(a) * 700, 460 + math.sin(a) * 420), Rotation = 360 })
	end
	if not wait(ctx, 0.35, drift) then
		return false
	end
	burstTo(ctx, Color3.fromRGB(255, 236, 236))
	sound("WinterGift", { volume = 1 })
	c:Destroy()
	if snow then
		snow.frame:Destroy()
	end
	bg.BackgroundTransparency = 0
	ctx.title(0.2)
	return ctx.alive()
end

local PULLS = { Lights = lightsPull, Sleigh = sleighPull, Tree = treePull, Joker = jokerPull, Candy = candyPull }

function WinterSkins.hasPull(name)
	return PULLS[name or ""] ~= nil
end

-- Plays skin pull `name` in ctx.root. Returns false if the recruit was cut.
function WinterSkins.pull(name, ctx)
	local fn = PULLS[name or ""]
	if not fn then
		return ctx.alive()
	end
	ctx.glow = ctx.glow or Assets.id(Assets.Fx.Glow) or ""
	ctx.sparkle = ctx.sparkle or Assets.id(Assets.Fx.Sparkle)
	local ok, res = pcall(fn, ctx, ctx.root)
	if not ok then
		warn("[WinterSkins] pull " .. tostring(name) .. ": " .. tostring(res))
		return ctx.alive()
	end
	return res
end

------------------------------------------------------------------------------------------
-- the Christmas jump effects (the owner, 2026-11-16: "christmas tree jump and all them seem a
-- little lazy": each was one painted model popping up and standing there). Each is a little
-- scene now, built of parts and tweened: VFXController plays the floor rings and snow puffs round
-- it. `foot` is the jumper's feet, k the size (1 big, 0.7 normal); things stand a little behind
-- the jumper (+X, away from the side camera) so they stay in view.
------------------------------------------------------------------------------------------

local function tw(obj, secs, props, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(secs, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function later(secs, fn)
	task.delay(secs, fn)
end

local function gone(obj, secs)
	task.delay(secs, function()
		if obj then
			obj:Destroy()
		end
	end)
end

-- A cone (Roblox's cone mesh: 1.7 across and 0.74 tall at scale 1), `w` across and `h` tall.
local function cone(cf, w, h, color, parent, material)
	local p = part({ Size = Vector3.new(w, h, w), CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic }, parent)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.FileMesh
	m.MeshId = "rbxassetid://1033714"
	m.Scale = Vector3.new(w / 1.7, h / 0.74, w / 1.7)
	m.Parent = p
	return p, m
end

-- A bit of something thrown out from `from`: up and out along `dir`, then down, fading.
local function fling(p, from, dir, up, secs)
	local peak = from + dir * 0.55 + Vector3.new(0, up, 0)
	local land = from + dir + Vector3.new(0, -from.Y + 0.3, 0)
	p.CFrame = CFrame.new(from)
	tw(p, secs * 0.45, { CFrame = CFrame.new(peak) * CFrame.Angles(math.random() * 3, math.random() * 3, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	later(secs * 0.45, function()
		if p.Parent then
			tw(p, secs * 0.55, { CFrame = CFrame.new(land) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
	gone(p, secs + 0.05)
end

local SNOW_W = Color3.fromRGB(246, 251, 255)
local ICE_C = Color3.fromRGB(170, 225, 255)
local CANDY = Color3.fromRGB(214, 30, 44)
local PINE_C = Color3.fromRGB(22, 92, 50)
local GOLD_C = Color3.fromRGB(255, 206, 70)
local LIGHT_COLORS = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(90, 230, 120), Color3.fromRGB(255, 206, 80), Color3.fromRGB(90, 170, 255) }

-- Snow Burst: a ring of ice crystals erupts round you in a wave, leaning out, then shatters.
local function jumpSnowburst(foot, k, root)
	-- (pointed spikes of ice, big and small in turn: square rods with a ball on top read as sticks)
	local N = 14
	for i = 1, N do
		local a = (i / N) * math.pi * 2
		local big = i % 2 == 0
		local r = (big and 2.5 or 2.1) * k
		local h = (big and (3.0 + (i % 3) * 0.7) or 1.6) * k
		local w = (big and 1.0 or 0.65) * k
		local at = Vector3.new(foot.X + math.cos(a) * r, 0, foot.Z + math.sin(a) * r)
		local out = CFrame.lookAt(at, at + Vector3.new(math.cos(a), 0, math.sin(a)))
		local lean = out * CFrame.Angles(math.rad(big and -22 or -35), 0, 0) -- (tipped out from the middle)
		local c = cone(lean * CFrame.new(0, -h / 2, 0), w, h, ICE_C, root, Enum.Material.Glass)
		c.Transparency = 0.12
		c.Reflectance = 0.25
		later((i - 1) * 0.02, function()
			tw(c, 0.16, { CFrame = lean * CFrame.new(0, h * 0.42, 0) }, Enum.EasingStyle.Back)
		end)
		-- and it shatters into shards flying outward
		later(0.62 + (i % 3) * 0.04, function()
			if not c.Parent then
				return
			end
			local from = c.Position
			for _ = 1, 3 do
				local s = part({ Size = Vector3.new(0.3, 0.6, 0.3) * k, CFrame = CFrame.new(from), Color = ICE_C, Material = Enum.Material.Glass, Transparency = 0.2 }, root)
				fling(s, from, Vector3.new(math.cos(a) * (3 + math.random() * 2), 0, math.sin(a) * (3 + math.random() * 2)) * k, (1.5 + math.random()) * k, 0.6)
			end
			c:Destroy()
		end)
	end
end

-- Snowman: the bottom ball rolls up out of the floor, the middle and the head drop onto it with a
-- bounce, his face, scarf, hat and stick arms pop on, he bobs once, then bursts into snow.
local function jumpSnowman(foot, k, root)
	local S = Vector3.new(foot.X + 1.9 * k, 0, foot.Z)
	local d1, d2, d3 = 2.3 * k, 1.7 * k, 1.25 * k
	local y1, y2, y3 = d1 * 0.45, d1 * 0.9 + d2 * 0.4, d1 * 0.9 + d2 * 0.8 + d3 * 0.42
	local bits = {}
	local function keep(p)
		table.insert(bits, p)
		return p
	end
	local b1 = keep(ball(S + Vector3.new(0, 0.1, 0), 0.1, SNOW_W, root))
	b1.Material = Enum.Material.Snow
	tw(b1, 0.28, { Size = Vector3.new(d1, d1, d1), CFrame = CFrame.new(S + Vector3.new(0, y1, 0)) }, Enum.EasingStyle.Back)
	local function drop(d, y, at)
		local b = keep(ball(S + Vector3.new(0, 14 * k, 0), d, SNOW_W, root))
		b.Material = Enum.Material.Snow
		b.Transparency = 1
		later(at, function()
			b.Transparency = 0
			tw(b, 0.32, { CFrame = CFrame.new(S + Vector3.new(0, y, 0)) }, Enum.EasingStyle.Bounce)
		end)
		return b
	end
	drop(d2, y2, 0.18)
	drop(d3, y3, 0.36)
	-- (he faces the camera: -X)
	later(0.68, function()
		local head = S + Vector3.new(0, y3, 0)
		for _, dz in ipairs({ -0.22, 0.22 }) do
			keep(ball(head + Vector3.new(-d3 * 0.45, 0.12 * k, dz * k), 0.18 * k, Color3.fromRGB(20, 20, 24), root))
		end
		local nose = keep(part({ Size = Vector3.new(0.6 * k, 0.16 * k, 0.16 * k), CFrame = CFrame.new(head + Vector3.new(-d3 * 0.55, -0.05 * k, 0)), Color = Color3.fromRGB(255, 120, 30) }, root))
		nose.Size = Vector3.new(0.05, 0.16 * k, 0.16 * k)
		tw(nose, 0.15, { Size = Vector3.new(0.6 * k, 0.16 * k, 0.16 * k) }, Enum.EasingStyle.Back)
		keep(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35 * k, d3 * 1.02, d3 * 1.02), CFrame = CFrame.new(S + Vector3.new(0, y3 - d3 * 0.45, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = CANDY, Material = Enum.Material.Fabric }, root))
		-- the hat drops on
		local brim = keep(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12 * k, d3 * 1.15, d3 * 1.15), CFrame = CFrame.new(head + Vector3.new(0, 8 * k, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(24, 22, 26) }, root))
		local top = keep(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8 * k, d3 * 0.7, d3 * 0.7), CFrame = CFrame.new(head + Vector3.new(0, 8.4 * k, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(24, 22, 26) }, root))
		tw(brim, 0.25, { CFrame = CFrame.new(head + Vector3.new(0, d3 * 0.48, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, Enum.EasingStyle.Bounce)
		tw(top, 0.25, { CFrame = CFrame.new(head + Vector3.new(0, d3 * 0.48 + 0.42 * k, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, Enum.EasingStyle.Bounce)
		-- stick arms, flung on, waving
		local mid = S + Vector3.new(0, y2, 0)
		for _, side in ipairs({ -1, 1 }) do
			local arm = keep(stick(mid + Vector3.new(0, 0.2 * k, side * d2 * 0.4), mid + Vector3.new(0, 1.1 * k, side * d2 * 1.15), 0.14 * k, Color3.fromRGB(90, 58, 34), root))
			arm.Transparency = 1
			tw(arm, 0.1, { Transparency = 0 })
		end
	end)
	-- he bursts into snow
	later(1.55, function()
		for _, p in ipairs(bits) do
			if p.Parent then
				local from = p.Position
				for _ = 1, 2 do
					local chunk = ball(from, (0.4 + math.random() * 0.3) * k, SNOW_W, root)
					chunk.Material = Enum.Material.Snow
					local a = math.random() * math.pi * 2
					fling(chunk, from, Vector3.new(math.cos(a), 0, math.sin(a)) * (3 + math.random() * 3) * k, (1 + math.random() * 2) * k, 0.7)
				end
				tw(p, 0.15, { Transparency = 1 })
				gone(p, 0.16)
			end
		end
	end)
end

-- Present: a wrapped box drops from the sky and lands with a bounce, its lid blasts off spinning,
-- and confetti and little presents spray out.
local function jumpPresent(foot, k, root)
	local S = Vector3.new(foot.X + 1.9 * k, 0, foot.Z)
	local B = 2.3 * k
	local box = part({ Size = Vector3.new(B, B, B), CFrame = CFrame.new(S + Vector3.new(0, 14 * k, 0)), Color = CANDY }, root)
	local bandA = part({ Size = Vector3.new(B + 0.04, B + 0.04, B * 0.2), CFrame = box.CFrame, Color = GOLD_C, Material = Enum.Material.Metal }, root)
	local bandB = part({ Size = Vector3.new(B * 0.2, B + 0.04, B + 0.04), CFrame = box.CFrame, Color = GOLD_C, Material = Enum.Material.Metal }, root)
	local lid = part({ Size = Vector3.new(B * 1.1, 0.45 * k, B * 1.1), CFrame = box.CFrame * CFrame.new(0, B / 2 + 0.2 * k, 0), Color = Color3.fromRGB(236, 50, 66) }, root)
	local bow = {}
	for _, dz in ipairs({ -1, 1 }) do
		table.insert(bow, ball(lid.Position + Vector3.new(0, 0.4 * k, dz * 0.35 * k), 0.6 * k, GOLD_C, root))
	end
	local landY = B / 2
	local group = { { box, 0 }, { bandA, 0 }, { bandB, 0 }, { lid, B / 2 + 0.2 * k } }
	for _, g in ipairs(group) do
		tw(g[1], 0.38, { CFrame = CFrame.new(S + Vector3.new(0, landY + g[2], 0)) }, Enum.EasingStyle.Bounce)
	end
	for _, b in ipairs(bow) do
		tw(b, 0.38, { CFrame = CFrame.new(S + Vector3.new(0, landY + B / 2 + 0.6 * k, b.Position.Z - S.Z)) }, Enum.EasingStyle.Bounce)
	end
	-- the lid blasts off, and it all sprays out
	later(0.5, function()
		local top = S + Vector3.new(0, B + 0.4 * k, 0)
		-- (a flip over and away, fading only at the end: spun on two axes and faded at once it read
		-- as a see-through bar)
		tw(lid, 0.65, { CFrame = CFrame.new(top + Vector3.new(-1.2 * k, 7 * k, 2 * k)) * CFrame.Angles(math.rad(200), 0, math.rad(20)) }, Enum.EasingStyle.Quad)
		later(0.4, function()
			if lid.Parent then
				tw(lid, 0.25, { Transparency = 1 })
			end
		end)
		for _, b in ipairs(bow) do
			fling(b, b.Position, Vector3.new(0, 0, (math.random() - 0.5) * 6 * k), 5 * k, 0.8)
		end
		for i = 1, 26 do
			local col = (i % 4 == 0) and Color3.new(1, 1, 1) or LIGHT_COLORS[i % #LIGHT_COLORS + 1]
			local bit = part({ Size = Vector3.new(0.35, 0.08, 0.25) * k, CFrame = CFrame.new(top), Color = col, Material = Enum.Material.Neon }, root)
			local a = math.random() * math.pi * 2
			fling(bit, top, Vector3.new(math.cos(a), 0, math.sin(a)) * (2 + math.random() * 4) * k, (4 + math.random() * 4) * k, 0.9 + math.random() * 0.4)
		end
		for i = 1, 3 do
			local m = part({ Size = Vector3.new(0.7, 0.7, 0.7) * k, CFrame = CFrame.new(top), Color = LIGHT_COLORS[i] }, root)
			local a = (i / 3) * math.pi * 2
			fling(m, top, Vector3.new(math.cos(a), 0, math.sin(a)) * 4.5 * k, 5 * k, 1.0)
		end
	end)
	later(1.45, function()
		for _, p in ipairs({ box, bandA, bandB }) do
			if p.Parent then
				tw(p, 0.25, { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
				gone(p, 0.26)
			end
		end
		gone(lid, 0.3)
	end)
end

-- Christmas Tree: the tree grows tier by tier out of the floor, its lights come on and twinkle, the
-- star on top flares, then it sinks back down.
local function jumpTree(foot, k, root)
	local S = Vector3.new(foot.X + 2.2 * k, 0, foot.Z)
	local parts = {}
	local function keep(p)
		table.insert(parts, p)
		return p
	end
	keep(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2 * k, 0.9 * k, 0.9 * k), CFrame = CFrame.new(S + Vector3.new(0, 0.6 * k, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(100, 64, 36), Material = Enum.Material.Wood }, root))
	local tiers = { { 4.2, 2.4, 0.9 }, { 3.3, 2.2, 2.4 }, { 2.4, 2.0, 3.8 }, { 1.5, 1.8, 5.0 } }
	local lights = {}
	for i, t in ipairs(tiers) do
		local w, h, y = t[1] * k, t[2] * k, t[3] * k
		local c, m = cone(CFrame.new(S + Vector3.new(0, y + h / 2, 0)), w, h, PINE_C, root, Enum.Material.Grass)
		keep(c)
		local full = m.Scale
		m.Scale = full * 0.02
		later((i - 1) * 0.11, function()
			tw(m, 0.2, { Scale = full }, Enum.EasingStyle.Back)
		end)
		-- the lights round this tier's skirt (on its surface, not inside it), and a few baubles
		local n = 7 + (4 - i)
		for j = 0, n - 1 do
			local a = j / n * math.pi * 2 + i
			local at = S + Vector3.new(math.cos(a) * w * 0.5, y + h * 0.1, math.sin(a) * w * 0.5)
			local b = keep(ball(at, 0.34 * k, LIGHT_COLORS[(j + i) % #LIGHT_COLORS + 1], root, true))
			b.Transparency = 1
			table.insert(lights, { part = b, color = b.Color, at = 0.5 + (i - 1) * 0.06 + j * 0.015 })
		end
		for j = 0, 2 do
			local a = j / 3 * math.pi * 2 + i * 0.7 + 0.5
			local at = S + Vector3.new(math.cos(a) * w * 0.33, y + h * 0.42, math.sin(a) * w * 0.33)
			local b = keep(ball(at, 0.42 * k, (j % 2 == 0) and CANDY or GOLD_C, root))
			b.Material = Enum.Material.Glass
			b.Reflectance = 0.3
			b.Transparency = 1
			table.insert(lights, { part = b, color = b.Color, at = 0.35 + (i - 1) * 0.08, steady = true })
		end
	end
	local starY = S + Vector3.new(0, 6.9 * k, 0)
	local star = keep(part({ Size = Vector3.new(0.1, 0.1, 0.1), CFrame = CFrame.new(starY) * CFrame.Angles(math.rad(45), 0, 0), Color = GOLD_C, Material = Enum.Material.Neon }, root))
	local star2 = keep(part({ Size = Vector3.new(0.1, 0.1, 0.1), CFrame = CFrame.new(starY), Color = Color3.fromRGB(255, 240, 170), Material = Enum.Material.Neon }, root))
	local glow = Instance.new("PointLight")
	glow.Color = GOLD_C
	glow.Range = 0
	glow.Brightness = 3
	glow.Parent = star
	-- the lights come on, then twinkle
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > 2.2 or not star.Parent then
			conn:Disconnect()
			return
		end
		for i, l in ipairs(lights) do
			if t >= l.at and l.part.Parent then
				l.part.Transparency = 0
				if not l.steady then
					l.part.Color = (math.sin(t * 9 + i * 1.3) > -0.3) and l.color or l.color:Lerp(Color3.new(0, 0, 0), 0.6)
				end
			end
		end
	end)
	-- the star flares
	later(0.7, function()
		if not star.Parent then
			return
		end
		-- (diamonds in the plane the side camera sees: thin along X)
		tw(star, 0.25, { Size = Vector3.new(0.2, 1.0, 1.0) * k }, Enum.EasingStyle.Back)
		tw(star2, 0.25, { Size = Vector3.new(0.18, 0.75, 0.75) * k, CFrame = CFrame.new(starY) * CFrame.Angles(math.rad(45), 0, 0) * CFrame.Angles(math.rad(45), 0, 0) }, Enum.EasingStyle.Back)
		tw(glow, 0.3, { Range = 18 * k })
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(40, 40)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Parent = star
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = Assets.id(Assets.Fx.Sparkle) or ""
		img.ImageColor3 = Color3.fromRGB(255, 236, 150)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(1, 1)
		img.Parent = bb
		tw(bb, 0.3, { Size = UDim2.fromOffset(260 * k, 260 * k) }, Enum.EasingStyle.Back)
		tw(img, 0.9, { Rotation = 90 })
		later(0.5, function()
			if img.Parent then
				tw(img, 0.4, { ImageTransparency = 1 })
			end
		end)
	end)
	-- and it sinks back down into the floor
	later(1.75, function()
		for _, p in ipairs(parts) do
			if p.Parent then
				tw(p, 0.45, { CFrame = p.CFrame - Vector3.new(0, 8 * k, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				gone(p, 0.5)
			end
		end
	end)
end

-- A gold bell, `h` tall, its mouth at `cf`: FxMeshes' FX_Bell (assets/fx/winter/AdventMeshes.fbx,
-- art/AdventFX.blend), else a cone of a skirt under a ball, with a clapper.
local function goldBell(cf, h, root)
	local folderMesh = ReplicatedStorage:FindFirstChild("FxMeshes")
	local tpl = folderMesh and folderMesh:FindFirstChild("FX_Bell", true)
	local m = Instance.new("Model")
	m.Name = "Bell"
	if tpl and tpl:IsA("MeshPart") then
		local b = tpl:Clone()
		b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch, b.CastShadow = true, false, false, false, false
		b.TextureID = ""
		b.Size = b.Size * (h / math.max(b.Size.Y, 0.01))
		b.Color = GOLD_C
		b.Material = Enum.Material.Metal
		b.Reflectance = 0.25
		b.PivotOffset = CFrame.new(0, -b.Size.Y / 2, 0) -- (pivot at the mouth)
		b.Parent = m
		m.PrimaryPart = b
	else
		local skirt = cone(CFrame.new(0, h * 0.25, 0), h * 0.95, h * 0.5, GOLD_C, m, Enum.Material.Metal)
		ball(Vector3.new(0, h * 0.62, 0), h * 0.6, GOLD_C, m).Material = Enum.Material.Metal
		ball(Vector3.new(0, -h * 0.06, 0), h * 0.2, GOLD_C, m).Material = Enum.Material.Metal
		skirt.PivotOffset = CFrame.new(0, -h * 0.25, 0) -- (pivot at the mouth)
		m.PrimaryPart = skirt
	end
	-- a red bow on top
	for _, side in ipairs({ -1, 1 }) do
		part({ Size = Vector3.new(h * 0.08, h * 0.22, h * 0.3), CFrame = CFrame.new(0, h * 1.02, side * h * 0.16) * CFrame.Angles(math.rad(side * 35), 0, 0), Color = CANDY, Material = Enum.Material.Fabric }, m)
	end
	m:PivotTo(cf)
	m.Parent = root
	return m
end

-- Jingle Bells (the advent calendar's; the owner, 2026-11-18): a ring of gold bells springs up out
-- of the floor round you, swings and rings in a wave, gold sparkles flying off each, then they
-- drop back into the floor.
local function jumpJingleBells(foot, k, root)
	local N = 6
	local floorY = 0
	for i = 1, N do
		local a = (i / N) * math.pi * 2
		local r = 2.7 * k
		local h = (i % 2 == 0 and 1.5 or 1.2) * k
		local at = Vector3.new(foot.X + math.cos(a) * r, floorY, foot.Z + math.sin(a) * r)
		local face = CFrame.lookAt(at, Vector3.new(foot.X, floorY, foot.Z))
		local bell = goldBell(face * CFrame.new(0, -h * 1.3, 0), h, root)
		local up = face * CFrame.new(0, h * 0.55, 0)
		local delay = (i - 1) * 0.04
		local cv = Instance.new("CFrameValue")
		cv.Value = bell:GetPivot()
		cv.Parent = bell
		cv.Changed:Connect(function(v)
			if bell.Parent then
				bell:PivotTo(v)
			end
		end)
		later(delay, function()
			tw(cv, 0.22, { Value = up }, Enum.EasingStyle.Back)
		end)
		-- the swing: rocked side to side twice, each bell a beat after the last
		for s = 0, 3 do
			later(delay + 0.24 + s * 0.14, function()
				if cv.Parent then
					local tilt = (s % 2 == 0 and 1 or -1) * math.rad(24 - s * 4)
					tw(cv, 0.13, { Value = up * CFrame.Angles(tilt, 0, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
					Fx.play("Glints", up.Position + Vector3.new(0, h * 0.4, 0), { color = Color3.fromRGB(255, 226, 130), scale = 0.55 * k })
				end
			end)
		end
		-- back into the floor
		later(delay + 0.95, function()
			if cv.Parent then
				tw(cv, 0.22, { Value = face * CFrame.new(0, -h * 1.4, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			end
		end)
	end
	Fx.play("JumpJingleBells", foot + Vector3.new(0, 1.5 * k, 0), { scale = k })
	sound("WinterJingle", { pos = foot, volume = 0.5, minGap = 0.3 })
end

-- Candy Claw (Horang's Christmas skin, Config.Halloween.Skins.CandyClaw): its red, and pieces
-- VFXController's Tiger Claw effects use when she wears it.
WinterSkins.CANDY = Color3.fromRGB(226, 30, 50)

-- Candy-cane stripes on `gui` (white): `n` red bands across it, sharp edged, on the slant.
function WinterSkins.candyStripes(gui, n)
	n = math.clamp(n or 5, 1, 5) -- (a gradient holds 20 keys: four a band)
	local keys = {}
	local red, white = WinterSkins.CANDY, Color3.new(1, 1, 1)
	for i = 0, n - 1 do
		local a, b = i / n, (i + 0.5) / n
		table.insert(keys, ColorSequenceKeypoint.new(a, red))
		table.insert(keys, ColorSequenceKeypoint.new(b - 0.001, red))
		table.insert(keys, ColorSequenceKeypoint.new(b, white))
		table.insert(keys, ColorSequenceKeypoint.new(i == n - 1 and 1 or (i + 1) / n - 0.001, white))
	end
	local g = Instance.new("UIGradient")
	g.Rotation = 45
	g.Color = ColorSequence.new(keys)
	g.Parent = gui
	return g
end

-- Whether a Horang wearing Candy Claw is on court (looked up at most once a second).
local candyAt, candyWas = -1, false
function WinterSkins.candyOn()
	local now = os.clock()
	if now - candyAt < 1 then
		return candyWas
	end
	candyAt, candyWas = now, false
	for _, team in ipairs(Config.TeamOrder) do
		for _, e in ipairs(State.roster(team) or {}) do
			local m = Util.modelOf(e.id)
			if m and m:GetAttribute("Skin") == "CandyClaw" then
				candyWas = true
			end
		end
	end
	return candyWas
end

-- RAWR! in Candy Claw: peppermint swirls flung out of the roar, spinning, and a burst of snow.
function WinterSkins.candyRoar(pos)
	if not camNear(pos) then
		return
	end
	local root = Instance.new("Folder")
	root.Name = "CandyRoar"
	root.Parent = fx()
	gone(root, 2)
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local at = pos + Vector3.new(0, 3, 0)
		local mint = Instance.new("Model")
		local disc = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2.2, 2.2), CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.new(1, 1, 1) }, mint)
		for k = 0, 3 do
			local w = k * math.pi / 2
			part({ Size = Vector3.new(0.55, 0.36, 1.05), CFrame = CFrame.new(at) * CFrame.Angles(0, w + 0.4, 0) * CFrame.new(0, 0, -0.5), Color = WinterSkins.CANDY }, mint)
		end
		mint.PrimaryPart = disc
		mint.Parent = root
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local cv = Instance.new("CFrameValue")
		cv.Value = disc.CFrame
		cv.Parent = mint
		cv.Changed:Connect(function(v)
			if mint.Parent then
				mint:PivotTo(v)
			end
		end)
		tw(cv, 0.9, { Value = CFrame.new(at + dir * 14 + Vector3.new(0, 6 + (i % 3) * 2, 0)) * CFrame.Angles(math.rad(90), i * 2, math.rad(720)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		later(0.7, function()
			for _, p in ipairs(mint:GetChildren()) do
				if p:IsA("BasePart") then
					tw(p, 0.3, { Transparency = 1 })
				end
			end
		end)
	end
	Fx.play("JumpSnowburst", pos + Vector3.new(0, 1, 0), { scale = 1.4 })
end

local JUMPS = { Snowburst = jumpSnowburst, Snowman = jumpSnowman, Present = jumpPresent, Tree = jumpTree, JingleBells = jumpJingleBells }

-- Plays Christmas jump `key` at `foot` (k: 1 big, 0.7 normal). False when it's not one of these
-- or nobody's near enough to see it.
function WinterSkins.jump(key, foot, k)
	local fn = JUMPS[key or ""]
	if not fn or not camNear(foot) then
		return false
	end
	local root = Instance.new("Folder")
	root.Name = "WinterJump"
	root.Parent = fx()
	gone(root, 3)
	local ok, err = pcall(fn, foot, k or 1, root)
	if not ok then
		warn("[WinterSkins] jump " .. tostring(key) .. ": " .. tostring(err))
	end
	return true
end

function WinterSkins.init(m)
	mods = m
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(watchSets)
		if not ok then
			warn("[WinterSkins] " .. tostring(err))
		end
	end)
end

return WinterSkins
