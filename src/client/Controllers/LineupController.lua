-- The matchup intro and the showcase after a match, in the broadcast kit (Gui).
--
-- Intro (MatchStart): each team in turn stands in a row facing the camera in their intro poses
-- (the Pose unlocks) on pedestals in the team colour, each name floating over its head; a slanted
-- plate along the bottom carries the team's emblem and name and a chip per character (tier,
-- character, role, ability). A wipe in the next team's colour swaps them, then both names meet
-- around a VS and the court comes back ("Game on!"). Nothing to press, like a game's entrance.
--
-- Showcase (MatchEnd): your team lines up again: VICTORY in their poses with sparkles, or DEFEAT
-- with hands on knees, the team name on a plate over them; under each a card with the tier, name
-- and @username, and Spikes, Blocks and Aces (digs and top speed under them), the MVP tagged; your
-- rewards along the bottom, and Continue.
--
-- The characters are clones of their models on the court (players and bots alike), posed with
-- AnimationController's static posing inside a ViewportFrame.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Characters = require(Shared.Characters)
local Util = require(Shared.Util)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local LineupController = {}
local mods

local player = Players.LocalPlayer
local make = Gui.make
local INTRO = Config.Match.Intro
local SPACING = 5.4 -- studs between characters in a row
local FOV = 24

local gui, canvas, canvasScale
local run = nil -- what's showing: { token, kind, scenes, sparkles, update }
local runToken = 0

local function tween(obj, time, props, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function label(parent, props)
	local l = Gui.label(parent, props)
	l.ZIndex = props.ZIndex or parent.ZIndex
	return l
end

local function canvasWidth()
	return canvas.Size.X.Offset
end

------------------------------------------------------------------------------------------
-- a row of posed characters in a viewport
------------------------------------------------------------------------------------------

local STRIP = { ForceField = true, BillboardGui = true, SurfaceGui = true, Sound = true, ParticleEmitter = true, Highlight = true, Trail = true, Beam = true, VectorForce = true, Fire = true, Smoke = true, Sparkles = true }

-- A posable copy of an entity's character on the court (nil until it has streamed in).
local function cloneRig(id)
	local model = Util.modelOf(id)
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
		if STRIP[d.ClassName] or d:IsA("Light") then
			d:Destroy()
		end
	end
	return mods.AnimationController.rig(clone)
end

-- Where a world point lands in a viewport, as fractions of its size (nil behind the camera).
local function project(cam, size, p)
	local rel = cam.CFrame:PointToObjectSpace(p)
	if rel.Z >= -0.1 then
		return nil
	end
	local t = math.tan(math.rad(cam.FieldOfView) / 2)
	local x = (rel.X / -rel.Z) / (t * size.X / size.Y)
	local y = (rel.Y / -rel.Z) / t
	return Vector2.new((x + 1) / 2, (1 - y) / 2)
end

local function poseName(key)
	local AC = mods.AnimationController
	if key and AC.poseJoints("Intro_" .. key) then
		return "Intro_" .. key
	end
	return "Intro_Ready"
end

-- A row in `parent`: entries { id, name, pose (a Pose key or "Tired"), mine }. opts: aimY (the
-- height the camera looks at), dist (the least camera distance), tags (names over the heads).
local function newScene(parent, entries, color, opts)
	local vp = make("ViewportFrame", {
		Name = "Lineup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(138, 138, 152),
		LightColor = Color3.fromRGB(255, 244, 226),
		LightDirection = Vector3.new(-0.45, -0.6, 0.65),
		ZIndex = parent.ZIndex + 1,
	}, parent)
	local cam = make("Camera", { FieldOfView = FOV }, vp)
	vp.CurrentCamera = cam
	local names = make("Frame", { Name = "Names", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = parent.ZIndex + 2 }, parent)
	local scene = { vp = vp, cam = cam, names = names, slots = {}, aimY = opts.aimY or 3.2, dist = opts.dist or 26, n = #entries }
	local n = #entries
	for i, e in ipairs(entries) do
		-- the camera looks along +z, so +x is the left of the screen: the first stands leftmost
		local x = ((n + 1) / 2 - i) * SPACING
		-- the pedestal: a disc in the team colour under a white rim
		make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 4.4, 4.4),
			CFrame = CFrame.new(x, -0.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color:Lerp(Color3.new(0, 0, 0), 0.3),
			Material = Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
		}, vp)
		make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.16, 4.62, 4.62),
			CFrame = CFrame.new(x, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
		}, vp)
		-- each turned a little toward the middle (x * 2.35 degrees would face the camera square on);
		-- e.turn turns them further (the slumped losers, whose hunch doesn't read face on; positive
		-- yaw faces screen right, the one in the middle turns that way)
		local turn = (e.turn or 0) * (x < 0 and -1 or 1)
		local slot = { id = e.id, pose = poseName(e.pose), x = x, phase = i * 1.7, yaw = x * 3.2 + turn, lower = e.lower or 0 }
		if opts.tags then
			slot.tag = label(names, {
				Text = e.name or "",
				display = true,
				weight = Enum.FontWeight.Heavy,
				TextSize = 28,
				TextColor3 = e.mine and Gui.SIGNAL or Gui.CHALK,
				TextStrokeTransparency = 0.25,
				AnchorPoint = Vector2.new(0.5, 1),
				Size = UDim2.fromOffset(300, 32),
				TextXAlignment = Enum.TextXAlignment.Center,
				Visible = false,
			})
			-- a small pointer under the name
			local tip = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(12, 12), Rotation = 45, BackgroundColor3 = e.mine and Gui.SIGNAL or Gui.CHALK, BorderSizePixel = 0, ZIndex = names.ZIndex }, slot.tag)
			make("UIStroke", { Color = Gui.LINE, Thickness = 1.5, Transparency = 0.3 }, tip)
		end
		table.insert(scene.slots, slot)
	end
	return scene
end

-- Fit the row to the viewport's shape: the whole row always shows.
local function frameCamera(scene)
	local size = scene.vp.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return
	end
	local t = math.tan(math.rad(FOV) / 2)
	local halfW = math.max(1, scene.n - 1) * SPACING / 2 + 3.4
	local dist = math.max(scene.dist, halfW / (t * size.X / size.Y))
	scene.cam.CFrame = CFrame.lookAt(Vector3.new(0, scene.aimY + 0.5, -dist), Vector3.new(0, scene.aimY, 0))
end

-- A slot's character drops onto its pedestal and snaps into its pose (false until its model has
-- streamed in; the caller tries again).
local function showSlot(scene, slot, now)
	if slot.rig then
		return true
	end
	local rig = cloneRig(slot.id)
	if not rig then
		return false
	end
	local hum = rig.model:FindFirstChildOfClass("Humanoid")
	slot.rig = rig
	slot.standY = (hum and hum.HipHeight or 2) + rig.root.Size.Y / 2
	slot.float = slot.pose == "Intro_Air"
	slot.t0 = now
	rig.model.Parent = scene.vp
	return true
end

local function stepScene(scene, now)
	local AC = mods.AnimationController
	frameCamera(scene)
	local size = scene.vp.AbsoluteSize
	for _, slot in ipairs(scene.slots) do
		if slot.rig then
			local a = math.clamp((now - slot.t0) / 0.3, 0, 1)
			local e = 1 - (1 - a) ^ 3
			local joints = AC.poseJoints(slot.pose)
			if a < 1 then
				joints = AC.blendJoints(AC.poseJoints("Intro_Ready"), joints, e)
			end
			local y = slot.standY - slot.lower + (1 - e) * 1.8 + math.sin(now * 2.1 + slot.phase) * (slot.float and 0.16 or 0.035)
			AC.poseModel(slot.rig, joints, CFrame.new(slot.x, y, 0) * CFrame.Angles(0, math.rad(slot.yaw), 0))
			if slot.tag and size.X > 2 then
				local head = slot.rig.model:FindFirstChild("Head")
				local p = head and project(scene.cam, size, head.Position + Vector3.new(0, 1.5, 0))
				if p then
					slot.tag.Position = UDim2.fromScale(p.X, math.max(0.08, p.Y))
					slot.tag.Visible = a >= 1
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- pieces: the backdrop, the emblem, the team plate, the wipe
------------------------------------------------------------------------------------------

-- The backdrop: the team's dark colour, a lighter sweep from the top left, print grain and a few
-- diagonal speed bands.
local function backdrop(parent, color, dark)
	local bg = make("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = dark, BorderSizePixel = 0, ZIndex = parent.ZIndex }, parent)
	make("UIGradient", { Rotation = 35, Color = ColorSequence.new(color:Lerp(dark, 0.35), dark:Lerp(Color3.new(0, 0, 0), 0.35)) }, bg)
	Gui.halftone(bg, { Size = UDim2.fromScale(1, 1), ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.8, ZIndex = bg.ZIndex })
	for i = 1, 4 do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.08 + i * 0.2, 0.45),
			Size = UDim2.new(0, 26 + i * 12, 2, 0),
			Rotation = 24,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.93,
			BorderSizePixel = 0,
			ZIndex = bg.ZIndex,
		}, bg)
	end
	return bg
end

-- A team's emblem: its icon in a disc of its dark colour ringed in white.
local function emblem(parent, team, size, props)
	local T = Config.Teams[team]
	local disc = make("Frame", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = T.Dark, BorderSizePixel = 0, ZIndex = parent.ZIndex + 1 }, parent)
	for k, v in pairs(props or {}) do
		disc[k] = v
	end
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disc)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = math.max(2, size * 0.035), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, disc)
	Gui.iconImage(disc, T.Icon, math.floor(size * 0.64), Color3.new(1, 1, 1), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = disc.ZIndex + 1 })
	return disc
end

-- A chip for one character on the team plate: tier badge, character, role, ability.
local function chip(parent, e, x, w)
	local c = Gui.card(parent, { Position = UDim2.fromOffset(x, 24), Size = UDim2.fromOffset(w, 128), BackgroundTransparency = 0.18, ZIndex = parent.ZIndex + 1 })
	local tier = e.tier or ""
	local color = Characters.color(tier)
	local _, setBadge = Gui.tierBadge(c, 50, { Position = UDim2.fromOffset(12, 12), ZIndex = c.ZIndex + 1 })
	setBadge(tier, color, false)
	label(c, { Text = e.char or e.name or "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(72, 10), Size = UDim2.new(1, -80, 0, 32), ZIndex = c.ZIndex + 1 })
	local role = Config.Roles[e.role or ""]
	label(c, { Text = role and role.Name or "", TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(72, 42), Size = UDim2.new(1, -80, 0, 20), ZIndex = c.ZIndex + 1 })
	local ab = Config.Abilities[e.ability or ""]
	label(c, {
		Text = ab and ab.Name or "No ability",
		display = true,
		TextSize = 20,
		TextColor3 = ab and ab.Color or Gui.MUTED,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(14, 84),
		Size = UDim2.new(1, -24, 0, 28),
		ZIndex = c.ZIndex + 1,
	})
	make("Frame", { Position = UDim2.fromOffset(14, 76), Size = UDim2.new(1, -28, 0, 1), BackgroundColor3 = Gui.HAIRLINE, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = c.ZIndex + 1 }, c)
	return c
end

-- The plate along the bottom of a team's intro: the emblem, the name, the mode and court, and a
-- chip per character on the right.
local function teamPlate(parent, team, members, sub, mine)
	local T = Config.Teams[team]
	local W = canvasWidth()
	local plate = Gui.plate(parent, { Name = "TeamPlate", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -60, 1, -30), Size = UDim2.fromOffset(W + 120, 176), ZIndex = parent.ZIndex + 4 }, T.Color, { flatLeft = true, flatRight = true })
	Gui.halftone(plate, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.55, 1), ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.82, ZIndex = plate.ZIndex })
	emblem(plate, team, 136, { Position = UDim2.fromOffset(100, 20) })
	local n = #members
	local chipW = math.clamp(math.floor((W - 720) / math.max(1, n)) - 12, 190, 262)
	local chipsLeft = W - 36 - n * (chipW + 12)
	local nameW = math.max(240, chipsLeft - 290)
	local name = label(plate, { Text = string.upper(T.Name), display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextColor3 = Gui.WHITE, Position = UDim2.fromOffset(262, 14), Size = UDim2.fromOffset(nameW, 96), ZIndex = plate.ZIndex + 1 })
	make("UITextSizeConstraint", { MaxTextSize = 100 }, name)
	make("UIStroke", { Color = T.Dark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, name)
	label(plate, { Text = sub, display = true, TextSize = 26, TextColor3 = T.Dark, Position = UDim2.fromOffset(266, 112), Size = UDim2.fromOffset(nameW, 30), ZIndex = plate.ZIndex + 1 })
	if mine then
		local tag = Gui.plate(plate, { Position = UDim2.fromOffset(262, -26), Size = UDim2.fromOffset(150, 34), ZIndex = plate.ZIndex + 1 }, Gui.SIGNAL)
		label(tag, { Text = "YOUR TEAM", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = tag.ZIndex + 1 })
	end
	local chips = {}
	for i, e in ipairs(members) do
		table.insert(chips, chip(plate, e, 60 + chipsLeft + (i - 1) * (chipW + 12), chipW))
	end
	return plate, chips
end

-- A full-height slanted plate that sweeps across the screen; `mid` runs while it covers it.
local function wipe(parent, color, mid)
	local W = canvasWidth()
	local width = W + 700
	local p = Gui.plate(parent, { Name = "Wipe", Position = UDim2.fromOffset(-width - 20, -40), Size = UDim2.fromOffset(width, 980), ZIndex = 40 }, color)
	local t = tween(p, INTRO.Wipe * 2, { Position = UDim2.fromOffset(W + 20, -40) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	task.delay(INTRO.Wipe, mid)
	t.Completed:Connect(function()
		p:Destroy()
	end)
end

------------------------------------------------------------------------------------------
-- running a sequence
------------------------------------------------------------------------------------------

local function close()
	runToken = runToken + 1
	if run then
		if run.conn then
			run.conn:Disconnect()
		end
		if run.root then
			run.root:Destroy()
		end
		run = nil
	end
	gui.Enabled = false
end

local function begin(kind)
	close()
	local token = runToken
	local root = make("Frame", { Name = kind, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 }, canvas)
	run = { token = token, kind = kind, root = root, scenes = {}, sparkles = {} }
	gui.Enabled = true
	-- Heartbeat, not RenderStepped: a still row needs no pre-render step, and this keeps running
	-- (and testable) while the window isn't drawing
	run.conn = RunService.Heartbeat:Connect(function()
		local ok, err = pcall(function()
			local now = os.clock()
			for _, scene in ipairs(run.scenes) do
				stepScene(scene, now)
			end
			if run.update then
				run.update(now)
			end
		end)
		if not ok then
			warn("[SpikeRush] lineup: " .. tostring(err))
			close()
		end
	end)
	return run
end

local function alive(r)
	return run == r and r.token == runToken
end

-- Wait `t` seconds of a sequence; false when it was closed meanwhile.
local function hold(r, t)
	task.wait(t)
	return alive(r)
end

------------------------------------------------------------------------------------------
-- the intro
------------------------------------------------------------------------------------------

local function modeLine()
	local size = State.teamSize()
	local court = Config.Courts.List[State.match.court or ""]
	local s = string.format("%dV%d", size, size)
	if court then
		s = s .. "   " .. string.upper(court.Name)
	end
	return s
end

-- One team's turn: the backdrop, the row popping in one by one, the plate sliding in.
local function teamStage(r, team)
	local T = Config.Teams[team]
	local stage = make("Frame", { Name = "Stage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, r.root)
	backdrop(stage, T.Color, T.Dark)
	local members = State.roster(team)
	local entries = {}
	for _, e in ipairs(members) do
		table.insert(entries, { id = e.id, name = e.name, pose = e.pose, mine = e.id == State.myId })
	end
	local scene = newScene(stage, entries, T.Color, { aimY = 2.4, dist = 24, tags = true })
	r.scenes = { scene }
	local plate = teamPlate(stage, team, members, modeLine(), team == State.myTeam)
	plate.Position = UDim2.new(0, -canvasWidth() - 200, 1, -30)
	tween(plate, 0.4, { Position = UDim2.new(0, -60, 1, -30) }, Enum.EasingStyle.Quint)
	-- the characters drop in one by one; a model still streaming in gets its turn when it arrives
	local t0 = os.clock()
	r.update = function(now)
		for i, slot in ipairs(scene.slots) do
			if not slot.rig and now - t0 >= 0.1 + (i - 1) * 0.14 then
				showSlot(scene, slot, now)
			end
		end
	end
	return stage
end

-- Both names meet around a VS, then the whole thing fades to the court.
local function versus(r)
	local W = canvasWidth()
	local layer = make("CanvasGroup", { Name = "Versus", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30 }, r.root)
	r.scenes = {}
	r.update = nil
	local sides = {}
	for i, team in ipairs(Config.TeamOrder) do
		local T = Config.Teams[team]
		local left = i == 1
		local half = make("Frame", { Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(left and 0 or 0.5, 0), BorderSizePixel = 0, BackgroundColor3 = T.Dark, ZIndex = 31 }, layer)
		make("UIGradient", { Rotation = left and 0 or 180, Color = ColorSequence.new(T.Dark:Lerp(Color3.new(0, 0, 0), 0.3), T.Color:Lerp(T.Dark, 0.4)) }, half)
		local plate = Gui.plate(layer, { AnchorPoint = Vector2.new(left and 1 or 0, 0.5), Position = UDim2.new(0.5, left and -70 or 70, 0.5, 0), Size = UDim2.fromOffset(math.min(640, W / 2 - 80), 150), ZIndex = 33 }, T.Color)
		emblem(plate, team, 110, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 44, 0.5, 0) })
		local nm = label(plate, { Text = string.upper(T.Name), display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextColor3 = Gui.WHITE, Position = UDim2.fromOffset(170, 20), Size = UDim2.new(1, -210, 0, 110), ZIndex = 34 })
		make("UITextSizeConstraint", { MaxTextSize = 96 }, nm)
		make("UIStroke", { Color = T.Dark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, nm)
		local to = plate.Position
		plate.Position = UDim2.new(left and 0 or 1, left and -40 or 40, 0.5, 0)
		tween(plate, 0.32, { Position = to }, Enum.EasingStyle.Back)
		table.insert(sides, plate)
	end
	local vs = Gui.plate(layer, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(200, 128), ZIndex = 36 }, Gui.SIGNAL)
	label(vs, { Text = "VS", display = true, weight = Enum.FontWeight.Heavy, TextSize = 96, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 37 })
	local punch = make("UIScale", { Scale = 2.4 }, vs)
	task.delay(0.22, function()
		tween(punch, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		if mods.AudioController then
			mods.AudioController.play("UIConfirm")
		end
	end)
	return layer
end

function LineupController.playIntro()
	if not State.isPlaying then
		return
	end
	local r = begin("Intro")
	task.spawn(function()
		local stage = nil
		for i, team in ipairs(Config.TeamOrder) do
			wipe(r.root, Config.Teams[team].Color, function()
				if not alive(r) then
					return
				end
				if stage then
					stage:Destroy()
				end
				stage = teamStage(r, team)
			end)
			if mods.AudioController then
				mods.AudioController.play("UIOpenLong")
			end
			if not hold(r, (i == 1 and INTRO.Open or INTRO.Wipe) + INTRO.TeamTime) then
				return
			end
		end
		local layer = nil
		wipe(r.root, Gui.SIGNAL, function()
			if not alive(r) then
				return
			end
			if stage then
				stage:Destroy()
			end
			layer = versus(r)
		end)
		if not hold(r, INTRO.Wipe + INTRO.VersusTime) then
			return
		end
		if layer then
			tween(layer, INTRO.Fade, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
		end
		if not hold(r, INTRO.Fade) then
			return
		end
		close()
		local court = Config.Courts.List[State.match.court or ""]
		mods.UIController.callout("Game on!", Config.UI.Spark, court and court.Name or modeLine(), 1.4)
	end)
end

------------------------------------------------------------------------------------------
-- the showcase after a match
------------------------------------------------------------------------------------------

local function usernameOf(id)
	local uid = type(id) == "string" and string.sub(id, 1, 2) == "P_" and tonumber(string.sub(id, 3))
	local plr = uid and Players:GetPlayerByUserId(uid)
	return plr and ("@" .. plr.Name) or nil
end

-- A player's card under their character: the team-colour head with the tier, name and
-- @username, the three big numbers, and the digs and top speed under them.
local function statCard(parent, row, color, mvp, x)
	local card = Gui.card(parent, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0.655, 0), Size = UDim2.fromOffset(318, 232), BackgroundTransparency = 0.12, ZIndex = parent.ZIndex + 6 })
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = card.ZIndex + 1 }, card)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(color, color:Lerp(Color3.new(0, 0, 0), 0.3)) }, head)
	local tier = row.tier or ""
	local _, setBadge = Gui.tierBadge(head, 52, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), ZIndex = head.ZIndex + 1 })
	setBadge(tier, Characters.color(tier), false)
	local mine = row.id == State.myId
	label(head, { Text = row.name or "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, TextColor3 = mine and Gui.SIGNAL or Gui.WHITE, TextStrokeTransparency = 0.5, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(72, 8), Size = UDim2.new(1, -82, 0, 32), ZIndex = head.ZIndex + 1 })
	local handle = row.isBot and "AI" or usernameOf(row.id) or ""
	label(head, { Text = handle .. (row.char and ("   " .. row.char) or ""), TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.2, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(73, 40), Size = UDim2.new(1, -82, 0, 20), ZIndex = head.ZIndex + 1 })
	if mvp then
		local tag = Gui.plate(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 8, 0, -18), Size = UDim2.fromOffset(84, 30), ZIndex = card.ZIndex + 3 }, Gui.SIGNAL)
		label(tag, { Text = "MVP", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = tag.ZIndex + 1 })
	end
	local stats = { { row.kills or 0, "Spikes" }, { row.blocks or 0, "Blocks" }, { row.aces or 0, "Aces" } }
	for i, s in ipairs(stats) do
		local box = make("Frame", { Position = UDim2.fromOffset(14 + (i - 1) * 100, 84), Size = UDim2.fromOffset(90, 66), BackgroundColor3 = Color3.fromRGB(38, 42, 58), BorderSizePixel = 0, ZIndex = card.ZIndex + 1 }, card)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
		label(box, { Text = tostring(s[1]), display = true, weight = Enum.FontWeight.Heavy, TextSize = 44, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = box.ZIndex + 1 })
		label(card, { Text = s[2], TextSize = 16, weight = Enum.FontWeight.Medium, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(14 + (i - 1) * 100, 152), Size = UDim2.fromOffset(90, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = card.ZIndex + 1 })
	end
	local top = (row.topKmh and row.topKmh > 0) and string.format("%.1f km/h", row.topKmh) or "-"
	label(card, { Text = string.format("Digs  %d        Top spike  %s", row.digs or 0, top), TextSize = 17, weight = Enum.FontWeight.Medium, TextColor3 = Gui.CHALK, Position = UDim2.fromOffset(16, 190), Size = UDim2.new(1, -32, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = card.ZIndex + 1 })
	return card
end

-- Your line: VP and Gold, extra sets and the win streak.
local function rewardsText(rows)
	for _, e in ipairs(rows) do
		if e.id == State.myId then
			local parts = {}
			if e.reward then
				table.insert(parts, string.format("+%d VP   +%d Gold", e.reward, e.gold or 0))
			end
			if e.mvpBonus then
				table.insert(parts, string.format("MVP bonus +%d VP", e.mvpBonus))
			end
			if e.extraVP then
				table.insert(parts, "extra sets included")
			end
			if e.streak and e.streak >= 2 then
				local bonus = e.streakVP and string.format(" (+%d VP, +%d Gold)", e.streakVP, e.streakGold or 0) or ""
				table.insert(parts, string.format("<b>Win streak %d</b>%s", e.streak, bonus))
			elseif e.streak == 0 then
				table.insert(parts, "win streak reset")
			end
			return table.concat(parts, "      ")
		end
	end
	return ""
end

-- Sparkles over the winners (particles don't draw in a viewport, so these are images).
local SPARKLE_TEXTURES = { "Sparkle", "Glint", "HitStar" }
local function sparkles(r, parent, color)
	local list = {}
	for i = 1, 18 do
		local key = SPARKLE_TEXTURES[(i % #SPARKLE_TEXTURES) + 1]
		local im = make("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.2 + math.random() * 0.6, 0.12 + math.random() * 0.42),
			Size = UDim2.fromOffset(40, 40),
			BackgroundTransparency = 1,
			Image = Assets.id(Assets.Fx[key]) or "",
			ImageColor3 = (i % 3 == 0) and color or ((i % 3 == 1) and Gui.GOLD_LIGHT or Color3.new(1, 1, 1)),
			ZIndex = parent.ZIndex + 3, -- over the row (the viewport and the names)
		}, parent)
		table.insert(list, { im = im, phase = math.random() * 6.28, speed = 1.6 + math.random() * 1.8, size = 26 + math.random() * 34, spin = (math.random() - 0.5) * 90 })
	end
	r.sparkles = list
end

local function twinkle(r, now)
	for _, s in ipairs(r.sparkles) do
		local k = (math.sin(now * s.speed + s.phase) + 1) / 2
		local sz = s.size * (0.35 + 0.65 * k)
		s.im.Size = UDim2.fromOffset(sz, sz)
		s.im.ImageTransparency = 0.15 + 0.8 * (1 - k)
		s.im.Rotation = now * s.spin
	end
end

function LineupController.showcase(a)
	local team = State.myTeam
	if not State.isPlaying or not team then
		return
	end
	local won = a.winner == team
	local T = Config.Teams[team]
	local rows = {}
	for _, e in ipairs(a.results or {}) do
		if e.team == team then
			table.insert(rows, e)
		end
	end
	local r = begin("Showcase")
	local color = won and T.Color or T.Color:Lerp(Color3.fromRGB(70, 74, 92), 0.6)
	local dark = won and T.Dark or T.Dark:Lerp(Color3.fromRGB(20, 22, 30), 0.6)
	local stage = make("Frame", { Name = "Stage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, r.root)
	backdrop(stage, color, dark)
	local entries = {}
	for _, e in ipairs(rows) do
		local pose = won and e.pose or "Tired"
		table.insert(entries, { id = e.id, name = e.name, pose = pose, lower = (won and e.pose == "Air") and 1.6 or 0, turn = not won and 38 or nil })
	end
	local scene = newScene(stage, entries, color, { aimY = 2, dist = 30 })
	r.scenes = { scene }
	if won then
		sparkles(r, stage, T.Color)
	end
	-- VICTORY / DEFEAT over the team name
	local top = Gui.plate(stage, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(560, 112), ZIndex = 12 }, won and T.Color or Color3.fromRGB(58, 62, 80))
	label(top, { Text = won and "VICTORY" or "DEFEAT", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, TextColor3 = won and Gui.WHITE or Gui.MUTED, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 13 })
	local nm = label(top, { Text = T.Name, display = true, weight = Enum.FontWeight.Heavy, TextSize = 60, TextColor3 = Gui.WHITE, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 64), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 13 })
	make("UIStroke", { Color = dark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, nm)
	if a.forfeit then
		label(stage, { Text = a.forfeit == team and "Your team forfeited" or (Config.Teams[a.forfeit].Name .. " forfeited"), display = true, TextSize = 22, TextColor3 = Gui.CHALK, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), Size = UDim2.fromOffset(600, 26), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
	end
	local punch = make("UIScale", { Scale = 1.8 }, top)
	tween(punch, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	-- a card under each character (placed once the camera is framed)
	local cards = {}
	for i, row in ipairs(rows) do
		cards[i] = statCard(stage, row, color, row.id == a.mvpId, 0.5)
		cards[i].Visible = false
	end
	local line = label(stage, { Text = rewardsText(rows), RichText = true, display = true, TextSize = 24, TextColor3 = Gui.CHALK, TextStrokeTransparency = 0.5, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(1000, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
	line.Visible = line.Text ~= ""
	local cont = Gui.plateButton(stage, { Name = "Continue", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -64), Size = UDim2.fromOffset(220, 66), ZIndex = 14 }, Gui.SIGNAL, Gui.SIGNAL_HOT)
	label(cont, { Text = "Continue", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 16 })
	Gui.pressSound(cont, "UIConfirm")
	cont.MouseButton1Click:Connect(function()
		Gui.click("UIConfirm")
		close()
	end)
	if mods.AudioController and won then
		mods.AudioController.play("CrowdCheer", { volume = 0.8 })
	end
	local t0 = os.clock()
	r.update = function(now)
		for i, slot in ipairs(scene.slots) do
			if not slot.rig and now - t0 >= 0.15 + (i - 1) * 0.16 then
				showSlot(scene, slot, now)
			end
			local card = cards[i]
			if card and slot.t0 then
				local size = scene.vp.AbsoluteSize
				local p = size.X > 2 and project(scene.cam, size, Vector3.new(slot.x, 0, 0))
				if p then
					card.Position = UDim2.new(p.X, 0, 0.655, 0)
					card.Visible = true
				end
			end
		end
		if won then
			twinkle(r, now)
		end
	end
end

------------------------------------------------------------------------------------------
-- wiring
------------------------------------------------------------------------------------------

local function rescale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vs = cam.ViewportSize
	if vs.X < 2 or vs.Y < 2 then
		return
	end
	local s = math.clamp(vs.Y / 900, 0.45, 1.6)
	if vs.X / s < 1180 then
		s = vs.X / 1180
	end
	canvasScale.Scale = s
	canvas.Size = UDim2.fromOffset(vs.X / s, vs.Y / s)
end

function LineupController.init(m)
	mods = m
	gui = make("ScreenGui", {
		Name = "SpikeRushLineup",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 30,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	canvas = make("Frame", { Name = "Canvas", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), BackgroundTransparency = 1, ClipsDescendants = true }, gui)
	canvasScale = make("UIScale", {}, canvas)
	rescale()
	local function watchCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		end
		rescale()
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

	State.signals.Announce:Connect(function(a)
		if a.kind == "MatchStart" then
			LineupController.playIntro()
		elseif a.kind == "MatchEnd" then
			LineupController.showcase(a)
		elseif a.kind == "MatchAbort" then
			close()
		end
	end)
	-- leaving the court (the menus come back) or the match moving on ends whatever is showing
	State.signals.Match:Connect(function(m2)
		if not run then
			return
		end
		if not State.isPlaying or (run.kind == "Intro" and m2.phase ~= "PreMatch") then
			close()
		end
	end)
end

return LineupController
