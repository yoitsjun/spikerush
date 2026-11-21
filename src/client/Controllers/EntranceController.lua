-- A story rival's entrance (Config.Story.Entrances), after the matchup intro and before the first
-- serve of a stage that names one (its Entrance). Copied from The Spike Cross's Nishikawa (the
-- owner, 2026-11-14: "copy that for yejun", "add lightning sfx and stuff"), as their recording
-- shows it:
--   1. the empty stands, the hall dark and quiet;
--   2. flat yellow bolts flashing all over the screen, a few at a time, faint streaks between;
--   3. the camera drops to the court and one bolt strikes him: a white flash, a ring on the floor,
--      bolts bursting out of the spot;
--   4. dust blowing off him and gold sparks floating up, his Quote over his head;
--   5. his cut-in: letterbox bars, him big on the right sliding in with afterimages, his name huge
--      in italics and his Title under it with his ability's icon.
-- LineupController calls play when its intro ends; MatchService made the pre-match wait longer by
-- the entrance's Time. Heartbeat drives it (a covered window still runs it).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Util = require(Shared.Util)
local Story = require(Shared.Story)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local EntranceController = {}
local mods

local player = Players.LocalPlayer
local make = Gui.make
local YELLOW = Color3.fromRGB(255, 236, 46)
local WHITE = Color3.new(1, 1, 1)

-- the beats, in seconds from the start (the whole runs inside the entrance's Time)
local T = {
	Bolts = 0.45, -- the flashing starts
	Strike = 2.55, -- the camera drops and the bolt hits him
	Dust = 3.2, -- the burst clears: dust, sparks, his line
	CutIn = 4.7, -- his cut-in
	Out = 6.75, -- it fades
	Done = 7.05,
}

local gui
local run = nil -- { token, root, conn, parts, onDone }
local runToken = 0
local pending = nil -- the stage key of the match that just started

local function tween(obj, time, props, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function sound(key, volume)
	if mods.AudioController then
		mods.AudioController.play(key, { volume = volume, minGap = 0 })
	end
end

local function viewport()
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1600, 900)
end

-- the screen's size in a 900-tall frame
local function px(n)
	return n * math.max(0.4, viewport().Y / 900)
end

------------------------------------------------------------------------------------------
-- flat bolts on the screen
------------------------------------------------------------------------------------------

-- One straight piece from a to b, w thick.
local function segment(parent, a, b, w, color, transparency)
	local d = b - a
	local len = d.Magnitude
	if len < 1 then
		return nil
	end
	return make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
		Size = UDim2.fromOffset(len + w * 0.4, w),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = parent.ZIndex,
	}, parent)
end

-- A jagged bolt from `from` to `to`: a few kinks, most pieces thin lines and some thick shards
-- that taper (a wedge in three steps), as The Spike Cross draws them. opts: kinks, jag (how far a
-- kink strays, of the length), thick (the widest shard), color.
local function bolt(parent, rng, from, to, opts)
	opts = opts or {}
	local holder = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = parent.ZIndex }, parent)
	local dir = to - from
	local len = dir.Magnitude
	if len < 2 then
		return holder
	end
	local perp = Vector2.new(-dir.Y, dir.X) / len
	local kinks = opts.kinks or rng:NextInteger(2, 5)
	local pts = { from }
	for i = 1, kinks do
		local t = i / (kinks + 1)
		table.insert(pts, from + dir * t + perp * (rng:NextNumber(-1, 1) * len * (opts.jag or 0.28)))
	end
	table.insert(pts, to)
	local color = opts.color or YELLOW
	local thick = opts.thick or px(32)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		if rng:NextNumber() < 0.5 then
			-- a shard: wide at one end, narrowing to a point
			local w = thick * rng:NextNumber(0.55, 1)
			local flip = rng:NextNumber() < 0.5
			for k = 0, 5 do
				local t0, t1 = k / 6, (k + 1) / 6
				local p0, p1 = a:Lerp(b, t0), a:Lerp(b, t1)
				local f = flip and (k + 1) / 6 or (6 - k) / 6
				segment(holder, p0, p1, math.max(px(2), w * f), color)
			end
		else
			segment(holder, a, b, math.max(px(2), thick * rng:NextNumber(0.12, 0.22)), color)
		end
	end
	return holder
end

-- A faint streak: a long thin line fading at both ends.
local function streak(parent, rng, center, angle, len)
	local d = Vector2.new(math.cos(angle), math.sin(angle)) * len / 2
	local s = segment(parent, center - d, center + d, px(rng:NextNumber(3, 6)), YELLOW, 0.35)
	if s then
		make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, s)
	end
	return s
end

local function later(seconds, inst)
	task.delay(seconds, function()
		if inst and inst.Parent then
			inst:Destroy()
		end
	end)
end

------------------------------------------------------------------------------------------
-- the rival on the court
------------------------------------------------------------------------------------------

-- (on the stage's other team, Away: Story.picks. You may be playing the same character yourself.)
local function findRival(charId)
	for _, e in ipairs(State.roster("Away") or {}) do
		if e.charId == charId then
			return e
		end
	end
	return nil
end

local function rootOf(id)
	local model = id and Util.modelOf(id)
	return model and model:FindFirstChild("HumanoidRootPart"), model
end

-- Where a world point is on the screen (nil behind the camera).
local function onScreen(p)
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local v, inFront = cam:WorldToViewportPoint(p)
	if not inFront then
		return nil
	end
	return Vector2.new(v.X, v.Y)
end

-- The shots, by where he stands: the stands high on the far side, then side on at him.
local function standsShot(r)
	return Vector3.new(r.X - 30, 15, r.Z * 0.6), Vector3.new(r.X + 60, 27, r.Z * 0.6), 40
end

local function courtShot(r, push)
	local dist = 30 - push * 6
	return Vector3.new(r.X - dist, r.Y + 4.5, r.Z), Vector3.new(r.X, r.Y + 1.2, r.Z), 34
end

-- A posable copy of his model (LineupController's cloneRig).
local STRIP = { ForceField = true, BillboardGui = true, SurfaceGui = true, Sound = true, ParticleEmitter = true, Highlight = true, Trail = true, Beam = true, Fire = true, Smoke = true, Sparkles = true }
local function cloneRig(model)
	if not model or not model:FindFirstChild("HumanoidRootPart") then
		return nil
	end
	local was = model.Archivable
	model.Archivable = true
	local ok, clone = pcall(function()
		return model:Clone()
	end)
	model.Archivable = was
	if not ok or not clone then
		return nil
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if STRIP[d.ClassName] or d:IsA("Light") or (d:IsA("Constraint") and not d:IsA("AnimationConstraint")) then
			d:Destroy()
		end
	end
	return mods.AnimationController.rig(clone)
end

------------------------------------------------------------------------------------------
-- 3D: dust and sparks where he stands
------------------------------------------------------------------------------------------

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function dustAndSparks(r, parts, run)
	local feet = Vector3.new(r.X, r.Y - 2.6, r.Z)
	local p = make("Part", { Name = "EntranceFx", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 1, Size = Vector3.new(6, 1, 6), CFrame = CFrame.new(feet) }, workspace)
	table.insert(parts, p)
	local smoke = Assets.id(Assets.Fx.Smoke) or ""
	-- two banks of dust rolling out sideways, along the court
	for _, dir in ipairs({ 1, -1 }) do
		local a = make("Attachment", { CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0.12, dir)) }, p)
		local e = emitter(a, {
			Texture = smoke,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
			FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
			EmissionDirection = Enum.NormalId.Front,
			SpreadAngle = Vector2.new(12, 18),
			Speed = NumberRange.new(10, 22),
			Drag = 2.2,
			Lifetime = NumberRange.new(1.2, 1.9),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 6.5) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(236, 232, 226), Color3.fromRGB(190, 184, 176)),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30, 30),
			LightInfluence = 0,
			Acceleration = Vector3.new(0, 1.5, 0),
		})
		e:Emit(dir == 1 and 16 or 10)
		e.Rate = dir == 1 and 10 or 6
		e.Enabled = true
		table.insert(run.dust, e)
	end
	-- gold sparks floating up all around him (their own box, so the dust stays on the floor)
	local box = make("Part", { Name = "EntranceSparks", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 1, Size = Vector3.new(4, 9, 16), CFrame = CFrame.new(feet + Vector3.new(0, 4, 0)) }, workspace)
	table.insert(parts, box)
	local sparks = emitter(box, {
		Texture = Assets.id(Assets.Fx.Dot) or "",
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.6, 2.4),
		Lifetime = NumberRange.new(1.4, 2.6),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(0.5, 0.42), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 214, 90)),
		LightEmission = 1,
		LightInfluence = 0,
		Rate = 18,
		Acceleration = Vector3.new(0, 1, 0),
	})
	sparks:Emit(24)
	sparks.Enabled = true
	return sparks
end

------------------------------------------------------------------------------------------
-- running it
------------------------------------------------------------------------------------------

local function stop()
	runToken = runToken + 1
	local r = run
	run = nil
	if mods and mods.CameraController and mods.CameraController.override then
		mods.CameraController.override = nil
	end
	if not r then
		return
	end
	if r.conn then
		r.conn:Disconnect()
	end
	for _, p in ipairs(r.parts) do
		if p.Parent then
			p:Destroy()
		end
	end
	if r.root then
		r.root:Destroy()
	end
	gui.Enabled = false
	for _, g in ipairs(r.hidden or {}) do
		if g.Parent then
			g.Enabled = true
		end
	end
	if r.onDone then
		task.spawn(r.onDone)
	end
end

local function alive(r)
	return run == r and r.token == runToken
end

-- Wait until `t` seconds into the entrance; false when it was stopped meanwhile.
local function at(r, t)
	local left = r.t0 + t * r.slow - os.clock()
	if left > 0 then
		task.wait(left)
	end
	return alive(r)
end

-- The flashing: bolts all over the screen, two or three at a time, each a blink.
local function flashes(r, layer, rng)
	task.spawn(function()
		local n = 0
		while alive(r) and os.clock() - r.t0 < (T.Strike - 0.05) * r.slow do
			local vs = viewport()
			for _ = 1, rng:NextInteger(1, 3) do
				local c = Vector2.new(rng:NextNumber(0.05, 0.95) * vs.X, rng:NextNumber(0.05, 0.95) * vs.Y)
				local ang = rng:NextNumber(0, math.pi * 2)
				local len = px(rng:NextNumber(220, 520))
				local d = Vector2.new(math.cos(ang), math.sin(ang)) * len / 2
				later(rng:NextNumber(0.08, 0.17), bolt(layer, rng, c - d, c + d))
				if rng:NextNumber() < 0.6 then
					later(0.2, streak(layer, rng, c + Vector2.new(rng:NextNumber(-200, 200), rng:NextNumber(-120, 120)), ang + rng:NextNumber(-0.6, 0.6), px(rng:NextNumber(140, 300))))
				end
			end
			n = n + 1
			if n % 7 == 1 then
				sound("ScoreTesla", 0.45)
			end
			task.wait(rng:NextNumber(0.05, 0.11))
		end
	end)
end

-- The strike and the burst at his spot on the screen.
local function strike(r, layer, rng, at2d, feet2d)
	local vs = viewport()
	-- the one bolt, from above the top edge straight down onto him
	later(0.22, bolt(layer, rng, Vector2.new(at2d.X + rng:NextNumber(-60, 60), -40), at2d, { kinks = 5, jag = 0.12, thick = px(30) }))
	local flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = layer.ZIndex + 3 }, layer)
	task.delay(0.12, function()
		if not alive(r) then
			return
		end
		flash.BackgroundTransparency = 0.15
		tween(flash, 0.5, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
		later(0.6, flash)
		-- the ring on the floor
		local ring = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((feet2d or at2d).X, (feet2d or at2d).Y), Size = UDim2.fromOffset(px(60), px(14)), BackgroundTransparency = 1, ZIndex = layer.ZIndex + 1 }, layer)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
		local stroke = make("UIStroke", { Color = WHITE, Thickness = px(7), Transparency = 0 }, ring)
		tween(ring, 0.55, { Size = UDim2.fromOffset(px(520), px(96)) })
		tween(stroke, 0.9, { Transparency = 1, Thickness = px(2) }, Enum.EasingStyle.Quad)
		later(1, ring)
		-- the burst: bolts thrown out of the spot every way, three waves
		for wave = 0, 2 do
			task.delay(wave * 0.09, function()
				if not alive(r) then
					return
				end
				for _ = 1, 9 do
					local ang = rng:NextNumber(0, math.pi * 2)
					local reach = px(rng:NextNumber(260, 900))
					local from = at2d + Vector2.new(math.cos(ang), math.sin(ang)) * px(rng:NextNumber(0, 60))
					later(rng:NextNumber(0.14, 0.26), bolt(layer, rng, from, from + Vector2.new(math.cos(ang), math.sin(ang)) * reach, { thick = px(26) }))
				end
			end)
		end
		mods.CameraController.shake(0.85)
	end)
	sound("Thunder", 1)
	task.delay(0.1, function()
		sound("ScoreThunder", 0.8)
		sound("FloorHitHeavy", 0.9)
		sound("ScoreShockwave", 0.6)
	end)
	return vs
end

-- His line over his head, following him on the screen: big, in white italics outlined in his
-- colour with a soft glow of it behind (the owner, 2026-11-14: "increase the quote's size because
-- right now its a little small and has no aura to it"), punching in with a little shake.
local function quote(r, layer, text, root, color)
	color = color or YELLOW
	local box = make("CanvasGroup", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(px(1300), px(84)), BackgroundTransparency = 1, GroupTransparency = 1, ZIndex = layer.ZIndex + 2 }, layer)
	local glow = Gui.label(box, { Text = text, display = true, weight = Enum.FontWeight.Heavy, TextSize = px(46), TextColor3 = color, TextTransparency = 0.5, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = box.ZIndex })
	make("UIStroke", { Color = color, Thickness = px(9), Transparency = 0.72, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, glow)
	local l = Gui.label(box, { Text = text, display = true, weight = Enum.FontWeight.Heavy, TextSize = px(46), TextColor3 = WHITE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = box.ZIndex + 1 })
	make("UIStroke", { Color = color:Lerp(Color3.new(0, 0, 0), 0.35), Thickness = px(2.5), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	local punch = make("UIScale", { Scale = 1.45 }, box)
	tween(box, 0.18, { GroupTransparency = 0 })
	tween(punch, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	local t0 = os.clock()
	r.follow = function()
		local p = root and root.Parent and onScreen(root.Position + Vector3.new(0, 4.6, 0))
		if p then
			-- a shake as it lands, settling in a third of a second
			local k = math.max(0, 1 - (os.clock() - t0) / 0.35)
			box.Position = UDim2.fromOffset(p.X + math.sin(os.clock() * 70) * px(6) * k, p.Y + math.cos(os.clock() * 55) * px(4) * k)
		end
	end
	return box
end

-- The cut-in: bars, him big on the right with afterimages, his name and title.
local function cutIn(r, layer, def, rival, model, school)
	local vs = viewport()
	local holder = make("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = layer.ZIndex + 5 }, layer)
	r.cutGroup = holder
	-- letterbox bars
	local barH = math.floor(vs.Y * 0.1)
	local top = make("Frame", { Size = UDim2.new(1, 0, 0, barH), Position = UDim2.fromOffset(0, -barH), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = holder.ZIndex + 6 }, holder)
	local bottom = make("Frame", { Size = UDim2.new(1, 0, 0, barH), Position = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = holder.ZIndex + 6 }, holder)
	tween(top, 0.3, { Position = UDim2.fromOffset(0, 0) })
	tween(bottom, 0.3, { Position = UDim2.new(0, 0, 1, -barH) })
	-- him: a posed copy in a viewport, waist up, filling the right side
	local rig = cloneRig(model)
	local w = math.floor(vs.X * 0.58)
	local frames = {}
	if rig then
		local AC = mods.AnimationController
		local vp = make("ViewportFrame", {
			Size = UDim2.fromOffset(w, vs.Y - barH),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(150, 140, 120),
			LightColor = Color3.fromRGB(255, 236, 190),
			LightDirection = Vector3.new(0.5, -0.5, 0.7),
			ZIndex = holder.ZIndex + 3,
		}, holder)
		local cam = make("Camera", { FieldOfView = 30 }, vp)
		vp.CurrentCamera = cam
		local hum = rig.model:FindFirstChildOfClass("Humanoid")
		local standY = (hum and hum.HipHeight or 2) + rig.root.Size.Y / 2
		local poseKey = "Intro_" .. (def.Pose or "Arms")
		AC.poseModel(rig, AC.poseJoints(poseKey) or AC.poseJoints("Intro_Ready"), CFrame.new(0, standY, 0) * CFrame.Angles(0, math.rad(-16), 0))
		rig.model.Parent = vp
		local head = rig.model:FindFirstChild("Head")
		local hy = head and head.Position.Y or standY + 1.6
		-- a little from below, his head in the upper third
		cam.CFrame = CFrame.lookAt(Vector3.new(-0.5, hy - 1.3, -8.6), Vector3.new(0.25, hy - 0.75, 0))
		-- afterimages: copies trailing behind as he slides in
		table.insert(frames, { vp = vp, lag = 0, alpha = 0 })
		for i = 1, 3 do
			local ghost = vp:Clone()
			ghost.CurrentCamera = ghost:FindFirstChildOfClass("Camera")
			ghost.ZIndex = holder.ZIndex + 3 - i
			ghost.ImageTransparency = 0.45 + i * 0.15
			ghost.Parent = holder
			table.insert(frames, { vp = ghost, lag = i * 0.05, alpha = 0.45 + i * 0.15 })
		end
		local restX = vs.X - w + px(30)
		for _, f in ipairs(frames) do
			f.vp.Position = UDim2.fromOffset(vs.X + px(80), barH * 0.5)
			task.delay(f.lag, function()
				if alive(r) then
					tween(f.vp, 0.38, { Position = UDim2.fromOffset(restX, barH * 0.5) })
					if f.lag > 0 then
						tween(f.vp, 0.5, { ImageTransparency = 1 }, Enum.EasingStyle.Quad)
					end
				end
			end)
		end
	end
	-- his name on a banner, as The Spike's score banners (the owner, 2026-11-14: "maybe an outlined
	-- text like this"): a dark band across the screen under a streak in his colour, the name huge in
	-- white italics outlined and glowing in his colour, then a thin divider and, small, his title
	-- with his role raised beside it and his tier and school under it in his colour
	local color = def.Color or YELLOW
	local bandH = px(150)
	local band = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(-1, 0, 0.72, 0), Size = UDim2.new(1, 0, 0, bandH), BackgroundColor3 = Color3.fromRGB(12, 10, 16), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = holder.ZIndex + 7 }, holder)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.75, 0.15), NumberSequenceKeypoint.new(1, 0.6) }) }, band)
	local streak = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.18, 0, 0, px(2)), Size = UDim2.new(0.62, 0, 0, px(6)), Rotation = -2, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = band.ZIndex + 1 }, band)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) }) }, streak)
	tween(band, 0.28, { Position = UDim2.new(0, 0, 0.72, 0) })
	local nameBox = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.56, 0, 0.5, 0), Size = UDim2.fromOffset(px(700), px(150)), BackgroundTransparency = 1, ZIndex = band.ZIndex + 2 }, band)
	local text = string.upper(rival.name or "YeJun")
	-- the glow: the same word behind, in his colour, with a wide soft outline
	local glow = Gui.label(nameBox, { Text = text, display = true, weight = Enum.FontWeight.Heavy, TextSize = px(132), TextColor3 = color, TextTransparency = 0.45, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = nameBox.ZIndex })
	make("UIStroke", { Color = color, Thickness = px(12), Transparency = 0.7, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, glow)
	local nm = Gui.label(nameBox, { Text = text, display = true, weight = Enum.FontWeight.Heavy, TextSize = px(132), TextColor3 = WHITE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = nameBox.ZIndex + 1 })
	make("UIStroke", { Color = color, Thickness = px(3.5), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, nm)
	-- the divider and the small words after it
	make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.575, 0, 0.5, 0), Size = UDim2.fromOffset(math.max(2, px(3)), px(78)), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = band.ZIndex + 2 }, band)
	local info = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.575, px(16), 0.5, 0), Size = UDim2.fromOffset(px(420), px(80)), BackgroundTransparency = 1, ZIndex = band.ZIndex + 2 }, band)
	local title = Gui.label(info, { Text = def.Title or "", display = true, weight = Enum.FontWeight.Bold, TextSize = px(34), TextColor3 = WHITE, Size = UDim2.new(1, 0, 0, px(40)), AutomaticSize = Enum.AutomaticSize.X, ZIndex = info.ZIndex + 1 })
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = px(1.5), Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, title)
	local roleTag = Gui.label(info, { Text = rival.role or "", display = true, weight = Enum.FontWeight.Bold, TextSize = px(16), TextColor3 = color, Size = UDim2.fromOffset(px(40), px(18)), ZIndex = info.ZIndex + 1 })
	task.defer(function()
		if roleTag.Parent then
			roleTag.Position = UDim2.fromOffset(title.TextBounds.X + px(5), px(2))
		end
	end)
	local icon = Assets.image(def.Icon or "")
	local subX = 0
	if icon and icon ~= "" then
		make("ImageLabel", { Image = icon, ImageColor3 = color, BackgroundTransparency = 1, Size = UDim2.fromOffset(px(22), px(22)), Position = UDim2.fromOffset(0, px(44)), ZIndex = info.ZIndex + 1 }, info)
		subX = px(28)
	end
	Gui.label(info, { Text = string.format("%s   %s", rival.tier or "", school or ""), display = true, weight = Enum.FontWeight.Bold, TextSize = px(20), TextColor3 = color, Position = UDim2.fromOffset(subX, px(44)), Size = UDim2.new(1, -subX, 0, px(24)), ZIndex = info.ZIndex + 1 })
	local punch = make("UIScale", { Scale = 1.5 }, nameBox)
	nameBox.Visible = false
	info.Visible = false
	task.delay(0.16, function()
		if alive(r) then
			nameBox.Visible = true
			tween(punch, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
			sound("ScorePow", 0.5)
		end
	end)
	task.delay(0.3, function()
		if alive(r) then
			info.Visible = true
		end
	end)
	-- gold motes drifting up across the cut-in
	local rng = r.rng
	for _ = 1, 26 do
		local s = px(rng:NextNumber(4, 9))
		local x, y = rng:NextNumber(0.05, 0.95) * vs.X, rng:NextNumber(0.2, 1) * vs.Y
		local mote = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(s, s), BackgroundColor3 = Color3.fromRGB(255, 214, 90), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = holder.ZIndex + 7 }, holder)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, mote)
		tween(mote, rng:NextNumber(1.6, 2.4), { Position = UDim2.fromOffset(x + rng:NextNumber(-30, 30), y - px(rng:NextNumber(80, 200))), BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
	end
	sound("SpeedWhoosh", 0.7)
	task.delay(0.12, function()
		sound("ScoreThunder", 0.5)
	end)
end

-- Plays the entrance of the match that just started, if its stage has one; onDone runs when it
-- ends (at once when it can't play). True when it plays.
function EntranceController.play(onDone)
	local key = pending
	pending = nil
	local stage = key and Story.stage(key)
	local def = stage and stage.Entrance and Config.Story.Entrances[stage.Entrance]
	if not def or not State.isPlaying or State.phase() ~= "PreMatch" then
		return false
	end
	stop()
	local token = runToken
	local root = make("Frame", { Name = "Entrance", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 }, gui)
	-- slow: the beats stretched this many times (ReplicatedStorage's EntranceSlow attribute, set in a
	-- playtest to look at each beat; the server's wait doesn't stretch with it)
	local slow = tonumber(ReplicatedStorage:GetAttribute("EntranceSlow")) or 1
	local r = { token = token, root = root, parts = {}, onDone = onDone, t0 = os.clock(), rng = Random.new(), dust = {}, slow = math.clamp(slow, 1, 20), hidden = {} }
	run = r
	gui.Enabled = true
	-- the match's HUD steps aside while it plays (the scoreboard, the buttons): back in stop()
	for _, g in ipairs(player:WaitForChild("PlayerGui"):GetChildren()) do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
			g.Enabled = false
			table.insert(r.hidden, g)
		end
	end
	local rival = findRival(stage.Entrance) or { name = (Config.Story.Cast[stage.Entrance] or {}).Name }
	local rootPart, model = rootOf(rival.id)
	local spot = rootPart and rootPart.Position or Vector3.new(0, 3, 20)

	-- the camera: the stands, then him
	r.shot = "stands"
	mods.CameraController.override = function(now)
		if r.shot == "stands" then
			local pos, look, fov = standsShot(spot)
			-- a slow drift up the stands
			local e = math.clamp((now - r.t0) / (T.Strike * r.slow), 0, 1)
			return pos + Vector3.new(0, e * 3, 0), look + Vector3.new(0, e * 4, 0), fov, true
		end
		local rp = rootPart and rootPart.Parent and rootPart.Position or spot
		local push = math.clamp((now - r.t0 - T.Strike * r.slow) / ((T.Done - T.Strike) * r.slow), 0, 1)
		local pos, look, fov = courtShot(rp, 1 - (1 - push) * (1 - push))
		return pos, look, fov, true
	end

	local flashLayer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10 }, root)
	local black = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 30 }, root)
	tween(black, T.Bolts, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	later(T.Bolts + 0.05, black)
	sound("ScoreRumble", 0.5)

	r.conn = RunService.Heartbeat:Connect(function()
		if r.follow then
			pcall(r.follow)
		end
	end)

	task.spawn(function()
		if not at(r, T.Bolts) then
			return
		end
		flashes(r, flashLayer, r.rng)
		if not at(r, T.Strike) then
			return
		end
		-- the drop to the court and the strike
		r.shot = "court"
		local rp = rootPart and rootPart.Parent and rootPart.Position or spot
		task.wait() -- (the camera cuts this frame)
		local p2 = onScreen(rp) or viewport() / 2
		strike(r, flashLayer, r.rng, p2, onScreen(rp - Vector3.new(0, 2.8, 0)))
		if not at(r, T.Dust) then
			return
		end
		local sparks = dustAndSparks(rp, r.parts, r)
		local line = quote(r, flashLayer, def.Quote or "", rootPart, def.Color)
		sound("ScoreSparkle", 0.4)
		if not at(r, T.CutIn) then
			return
		end
		tween(line, 0.2, { GroupTransparency = 1 })
		cutIn(r, root, def, rival, model, stage.Versus)
		if not at(r, T.Out) then
			return
		end
		for _, e in ipairs(r.dust) do
			e.Enabled = false
		end
		if sparks then
			sparks.Enabled = false
		end
		if r.cutGroup then
			tween(r.cutGroup, T.Done - T.Out, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
		end
		if not at(r, T.Done) then
			return
		end
		stop()
	end)
	return true
end

function EntranceController.init(m)
	mods = m
	gui = make("ScreenGui", {
		Name = "SpikeRushEntrance",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 31, -- (over the lineup's 30)
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	State.signals.Announce:Connect(function(a)
		if a.kind == "MatchStart" then
			pending = a.story
		elseif a.kind == "MatchAbort" or a.kind == "MatchEnd" then
			pending = nil
			if run then
				stop()
			end
		end
	end)
	-- the match moving on (the first serve) or leaving the court ends it
	State.signals.Match:Connect(function(m2)
		if run and (not State.isPlaying or (m2 and m2.phase and m2.phase ~= "PreMatch")) then
			stop()
		end
	end)
end

return EntranceController
