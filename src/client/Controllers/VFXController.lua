-- Anime-style effects for the side view, all procedural (no assets required), with optional
-- Toolbox overrides (ReplicatedStorage.ToolboxAssets.VFX.<Name>).
--  * contact: starbursts and rings drawn in the screen plane, lightning bolts (Thunder Spiker),
--    a dragon-blue burst and hover aura (Azure Dragon), shards, sparks
--  * jumps: a "boom" ring and streaks under the feet
--  * screen: white flash, horizontal speed lines, and the impact frame: the screen goes white,
--    the attacker becomes a black silhouette over a coloured radial burst for a split second
--  * text: receive grades ("PERFECT 96" with a badge), callouts ("Free ball!", "Stuff!")
-- Parts, rings and starbursts are pooled; popups and the impact frame are short-lived.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Util = require(Shared.Util)
local State = require(script.Parent.State)

local VFXController = {}
local mods

local player = Players.LocalPlayer
local UI = Config.UI
local FLAT = CFrame.Angles(0, 0, math.rad(90))
local WHITE = Color3.new(1, 1, 1)
local THUNDER = Color3.fromRGB(255, 226, 60)
local AZURE = Color3.fromRGB(70, 210, 255)
local HOT = Color3.fromRGB(255, 50, 90)

local fxFolder
local pool = {}
local emitterHolder, sparkEmitter, dustEmitter, fireEmitter
local screen, flashFrame, linesFrame
local lines = {}
local linesUntil, linesDir = 0, 1
local impactGui
local auras = {}

local GRADE_COLOR = {
	PERFECT = UI.Spark,
	GREAT = Color3.fromRGB(255, 160, 70),
	GOOD = UI.Chalk,
	BAD = Color3.fromRGB(170, 176, 200),
	BROKEN = HOT,
}

local function teamColor(team)
	local t = Config.Teams[team or ""]
	return t and t.Color or UI.Chalk
end

local function near(pos)
	local cam = workspace.CurrentCamera
	return cam ~= nil and math.abs(cam.CFrame.Position.Z - pos.Z) < 60
end

------------------------------------------------------------------------------------------
-- pooled parts
------------------------------------------------------------------------------------------

local PARKED = CFrame.new(0, -500, 0)

local function newPart(shape)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = 1
	p.CFrame = PARKED
	p.Parent = fxFolder
	return p
end

-- Idle parts wait on a free list per shape (no attribute scans, no allocation once warm).
local function take(shape)
	local list = pool[shape]
	if list and #list > 0 then
		return table.remove(list)
	end
	return newPart(shape)
end

local function release(p)
	p.Transparency = 1
	p.CFrame = PARKED
	local list = pool[p.Shape]
	if not list then
		list = {}
		pool[p.Shape] = list
	end
	table.insert(list, p)
end

local function animate(p, duration, fromSize, toSize, fromT, toT, cf)
	p.Size = fromSize
	p.Transparency = fromT
	p.CFrame = cf
	local tween = TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = toSize,
		Transparency = toT,
	})
	tween:Play()
	tween.Completed:Connect(function()
		release(p)
	end)
end

local function burst(pos, color, radius, duration)
	local p = take(Enum.PartType.Ball)
	p.Color = color
	animate(p, duration, Vector3.new(0.4, 0.4, 0.4), Vector3.new(radius * 2, radius * 2, radius * 2), 0.05, 1, CFrame.new(pos))
end

local function floorRing(pos, color, radius, duration)
	local p = take(Enum.PartType.Cylinder)
	p.Color = color
	animate(p, duration, Vector3.new(0.06, 0.6, 0.6), Vector3.new(0.02, radius * 2, radius * 2), 0.1, 1, CFrame.new(pos.X, 0.2, pos.Z) * FLAT)
end

-- Shards fly out within the play plane so they read from the side camera.
local function shards(pos, color, count, speed)
	for i = 1, count do
		local p = take(Enum.PartType.Block)
		p.Color = color
		local a = (i / count) * math.pi * 2 + math.random() * 0.5
		local dir = Vector3.new((math.random() - 0.5) * 0.4, math.sin(a), math.cos(a)).Unit
		local len = 0.9 + math.random() * 1.4
		p.Size = Vector3.new(0.16, 0.16, len)
		p.CFrame = CFrame.lookAt(pos, pos + dir)
		p.Transparency = 0
		local goal = CFrame.lookAt(pos + dir * speed * 0.2, pos + dir * (speed * 0.2 + 1))
		local tween = TweenService:Create(p, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = goal,
			Size = Vector3.new(0.05, 0.05, len * 1.5),
			Transparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			release(p)
		end)
	end
end

-- A jagged lightning bolt from `from` along `dir`, in the play plane.
local function bolt(from, dir, length, color)
	local segs = 6
	local prev = from
	local side = Vector3.new(0, -dir.Z, dir.Y)
	for i = 1, segs do
		local along = from + dir * (length * i / segs)
		local jag = side * ((math.random() - 0.5) * length * 0.28)
		local nextP = along + jag
		if i == segs then
			nextP = along
		end
		local p = take(Enum.PartType.Block)
		p.Color = color
		local mid = (prev + nextP) / 2
		local seg = (nextP - prev).Magnitude
		p.Size = Vector3.new(0.22, 0.22, seg)
		p.CFrame = CFrame.lookAt(mid, nextP) + Vector3.new(-0.6, 0, 0)
		p.Transparency = 0
		local tween = TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Linear), { Transparency = 1, Size = Vector3.new(0.08, 0.08, seg) })
		tween:Play()
		tween.Completed:Connect(function()
			release(p)
		end)
		prev = nextP
	end
end

------------------------------------------------------------------------------------------
-- GUI shapes in world space (always face the camera). Rings and starbursts are pooled: each
-- entry owns its anchor part and BillboardGui and is only re-coloured and re-tweened on reuse.
------------------------------------------------------------------------------------------

local ringPool, burstPool = {}, {}
local MAX_RAYS = 16

local function newBillboard()
	local anchor = newPart(Enum.PartType.Block)
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Enabled = false
	gui.Parent = anchor
	return gui, anchor
end

local function park(entry, list)
	entry.gui.Enabled = false
	entry.anchor.CFrame = PARKED
	table.insert(list, entry)
end

-- One-off billboard (popups): the gui is destroyed afterwards, the anchor goes back to the pool.
local function billboard(pos, size)
	local anchor = take(Enum.PartType.Block)
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(size, 0, size, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	return gui, anchor
end

local function ringFx(pos, color, fromSize, toSize, duration, thickness)
	local e = table.remove(ringPool)
	if not e then
		local gui, anchor = newBillboard()
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundTransparency = 1
		f.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Parent = f
		e = { gui = gui, anchor = anchor, stroke = stroke }
	end
	e.anchor.CFrame = CFrame.new(pos)
	e.gui.Size = UDim2.new(fromSize, 0, fromSize, 0)
	e.stroke.Color = color
	e.stroke.Thickness = thickness or 6
	e.stroke.Transparency = 0
	e.gui.Enabled = true
	TweenService:Create(e.gui, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(toSize, 0, toSize, 0) }):Play()
	TweenService:Create(e.stroke, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Thickness = 1 }):Play()
	task.delay(duration + 0.05, function()
		park(e, ringPool)
	end)
end

local function starburst(pos, color, size, rays, duration)
	local e = table.remove(burstPool)
	if not e then
		local gui, anchor = newBillboard()
		local scale = Instance.new("UIScale")
		scale.Parent = gui
		local list = {}
		for i = 1, MAX_RAYS do
			local r = Instance.new("Frame")
			r.AnchorPoint = Vector2.new(0, 0.5)
			r.Position = UDim2.fromScale(0.5, 0.5)
			r.BorderSizePixel = 0
			r.Parent = gui
			list[i] = r
		end
		local core = Instance.new("Frame")
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5, 0.5)
		core.Size = UDim2.fromScale(0.26, 0.26)
		core.BackgroundColor3 = WHITE
		core.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = core
		e = { gui = gui, anchor = anchor, scale = scale, rays = list, core = core }
	end
	rays = math.min(rays, MAX_RAYS)
	e.anchor.CFrame = CFrame.new(pos)
	e.gui.Size = UDim2.new(size, 0, size, 0)
	e.scale.Scale = 0.35
	for i, r in ipairs(e.rays) do
		if i <= rays then
			r.Visible = true
			r.Size = UDim2.new(0.28 + math.random() * 0.22, 0, 0, math.random(4, 9))
			r.Rotation = (i / rays) * 360 + math.random() * 12
			r.BackgroundColor3 = color
			r.BackgroundTransparency = 0
		else
			r.Visible = false
		end
	end
	e.core.BackgroundTransparency = 0
	e.gui.Enabled = true
	TweenService:Create(e.scale, TweenInfo.new(duration * 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(duration * 0.35, function()
		local fade = TweenInfo.new(duration * 0.65)
		for i = 1, rays do
			TweenService:Create(e.rays[i], fade, { BackgroundTransparency = 1 }):Play()
		end
		TweenService:Create(e.core, fade, { BackgroundTransparency = 1 }):Play()
	end)
	task.delay(duration + 0.05, function()
		park(e, burstPool)
	end)
end

------------------------------------------------------------------------------------------
-- particles
------------------------------------------------------------------------------------------

local function makeEmitter(texture, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Enabled = false
	e.LightInfluence = 0
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = emitterHolder
	return e
end

local function emit(emitter, pos, count, color)
	emitterHolder.CFrame = CFrame.new(pos)
	if color then
		emitter.Color = ColorSequence.new(color)
	end
	emitter:Emit(count)
end

-- A Toolbox effect from ReplicatedStorage.ToolboxAssets.VFX.<name>, fired once at `pos`.
-- Templates can be an Attachment, a Part or a Model holding ParticleEmitters. Each emitter
-- bursts :Emit(EmitCount) after EmitDelay seconds (both optional attributes).
local function toolboxFx(name, pos)
	local template = Assets.toolbox("VFX." .. name)
	if not template then
		return false
	end
	local holder = take(Enum.PartType.Block)
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(pos)
	local clone = Assets.sanitize(template:Clone())
	if clone:IsA("BasePart") then
		if not clone:GetAttribute("Visible") then
			clone.Transparency = 1
		end
		clone.CFrame = holder.CFrame
	elseif clone:IsA("Model") then
		clone:PivotTo(holder.CFrame)
	end
	clone.Parent = holder
	local longest = 0.5
	local list = clone:GetDescendants()
	table.insert(list, clone)
	for _, d in ipairs(list) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			local delay = d:GetAttribute("EmitDelay") or 0
			local count = d:GetAttribute("EmitCount") or 20
			if delay > 0 then
				task.delay(delay, function()
					if d.Parent then
						d:Emit(count)
					end
				end)
			else
				d:Emit(count)
			end
			longest = math.max(longest, delay + d.Lifetime.Max)
		end
	end
	task.delay(longest + 0.3, function()
		clone:Destroy()
		release(holder)
	end)
	return true
end

------------------------------------------------------------------------------------------
-- screen effects
------------------------------------------------------------------------------------------

local function buildScreen()
	screen = Instance.new("ScreenGui")
	screen.Name = "SpikeRushFX"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 5
	screen.Parent = player:WaitForChild("PlayerGui")

	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundColor3 = WHITE
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Parent = screen

	linesFrame = Instance.new("Frame")
	linesFrame.Size = UDim2.fromScale(1, 1)
	linesFrame.BackgroundTransparency = 1
	linesFrame.Visible = false
	linesFrame.Parent = screen
	local count = State.isMobile and 14 or 24
	for i = 1, count do
		local l = Instance.new("Frame")
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.BorderSizePixel = 0
		l.BackgroundColor3 = WHITE
		l.Parent = linesFrame
		lines[i] = { frame = l, x = math.random(), y = math.random(), len = 0.1, speed = 1 }
	end

	impactGui = Instance.new("ScreenGui")
	impactGui.Name = "SpikeRushImpact"
	impactGui.IgnoreGuiInset = true
	impactGui.ResetOnSpawn = false
	impactGui.DisplayOrder = 20
	impactGui.Enabled = false
	impactGui.Parent = player:WaitForChild("PlayerGui")
end

function VFXController.flash(strength, duration)
	flashFrame.BackgroundTransparency = 1 - strength
	TweenService:Create(flashFrame, TweenInfo.new(duration or 0.25), { BackgroundTransparency = 1 }):Play()
end

-- Horizontal streaks racing across the screen in the ball's direction (dir: +1 right, -1 left).
function VFXController.speedLines(duration, color, dir)
	if not State.settings.dramatic then
		return
	end
	linesUntil = os.clock() + duration
	linesDir = dir or 1
	for _, l in ipairs(lines) do
		l.frame.BackgroundColor3 = color or WHITE
		l.x = math.random()
		l.y = 0.08 + math.random() * 0.84
		l.len = 0.12 + math.random() * 0.25
		l.speed = 2.2 + math.random() * 2.5
	end
	linesFrame.Visible = true
end

local function updateLines(dt)
	if not linesFrame.Visible then
		return
	end
	local left = linesUntil - os.clock()
	if left <= 0 then
		linesFrame.Visible = false
		return
	end
	local fade = math.clamp(left / 0.25, 0, 1)
	for _, l in ipairs(lines) do
		l.x = l.x + linesDir * l.speed * dt
		if l.x > 1.3 then
			l.x = -0.3
		elseif l.x < -0.3 then
			l.x = 1.3
		end
		l.frame.Position = UDim2.fromScale(l.x, l.y)
		l.frame.Size = UDim2.new(l.len, 0, 0, 2 + (l.speed > 3.5 and 2 or 0))
		l.frame.BackgroundTransparency = 1 - 0.7 * fade
	end
end

local function silhouette(model, vp)
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
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Highlight") or d:IsA("Decal") or d:IsA("SurfaceAppearance") or d:IsA("Light") or d:IsA("VectorForce") then
			d:Destroy()
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Color = Color3.new(0, 0, 0)
			d.Material = Enum.Material.SmoothPlastic
			if d:IsA("MeshPart") then
				pcall(function()
					d.TextureID = ""
				end)
			end
			if d.Name == "HumanoidRootPart" then
				d.Transparency = 1
			end
		end
	end
	local world = Instance.new("WorldModel")
	world.Parent = vp
	clone.Parent = world
	return clone
end

-- The manga impact frame: white screen, black silhouette, coloured radial burst.
function VFXController.impactFrame(entityId, color)
	if not State.settings.dramatic then
		return
	end
	local cam = workspace.CurrentCamera
	local model = Util.modelOf(entityId)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not cam or not hrp then
		VFXController.flash(0.7, 0.2)
		return
	end
	impactGui:ClearAllChildren()
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = WHITE
	bg.BorderSizePixel = 0
	bg.Parent = impactGui

	local sp = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 1.5, 0))
	local vs = cam.ViewportSize
	local burstFrame = Instance.new("Frame")
	burstFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	burstFrame.Position = UDim2.fromOffset(sp.X, sp.Y)
	burstFrame.Size = UDim2.fromOffset(vs.Y * 1.3, vs.Y * 1.3)
	burstFrame.BackgroundTransparency = 1
	burstFrame.Parent = bg
	for i = 1, 22 do
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0, 0.5)
		r.Position = UDim2.fromScale(0.5, 0.5)
		r.Size = UDim2.new(0.25 + math.random() * 0.3, 0, 0, math.random(8, 26))
		r.Rotation = (i / 22) * 360 + math.random() * 8
		r.BackgroundColor3 = color or HOT
		r.BorderSizePixel = 0
		r.Parent = burstFrame
	end
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(0.3, 0.3)
	disc.BackgroundColor3 = color or HOT
	disc.Parent = burstFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc

	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.new(0, 0, 0)
	vp.LightColor = Color3.new(0, 0, 0)
	vp.Parent = bg
	local vcam = Instance.new("Camera")
	vcam.CFrame = cam.CFrame
	vcam.FieldOfView = cam.FieldOfView
	vcam.Parent = vp
	vp.CurrentCamera = vcam
	silhouette(model, vp)

	impactGui.Enabled = true
	task.delay(0.09, function()
		TweenService:Create(bg, TweenInfo.new(0.14), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(vp, TweenInfo.new(0.14), { ImageTransparency = 1 }):Play()
		for _, r in ipairs(burstFrame:GetChildren()) do
			if r:IsA("Frame") then
				TweenService:Create(r, TweenInfo.new(0.14), { BackgroundTransparency = 1 }):Play()
			end
		end
	end)
	task.delay(0.26, function()
		impactGui.Enabled = false
		impactGui:ClearAllChildren()
	end)
end

------------------------------------------------------------------------------------------
-- popups
------------------------------------------------------------------------------------------

function VFXController.popup(pos, text, color, size, badge)
	local gui, anchor = billboard(pos, 1)
	gui.Size = UDim2.fromOffset(300, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	local fades = {}
	if badge then
		-- a small shield badge: perfect receives drain almost no stamina
		local b = Instance.new("Frame")
		b.Size = UDim2.fromOffset(30, 30)
		b.Rotation = 45
		b.BackgroundColor3 = color
		b.LayoutOrder = 1
		b.Parent = row
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = UI.Ink
		st.Parent = b
		table.insert(fades, { b, "BackgroundTransparency" })
		table.insert(fades, { st, "Transparency" })
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.Font = Enum.Font.Bangers
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 44
	label.Rotation = -5
	label.LayoutOrder = 2
	label.Parent = row
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = UI.Ink
	stroke.Parent = label
	table.insert(fades, { label, "TextTransparency" })
	table.insert(fades, { stroke, "Transparency" })
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = row
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = size or 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0) }):Play()
	task.delay(0.65, function()
		for _, f in ipairs(fades) do
			local goal = {}
			goal[f[2]] = 1
			TweenService:Create(f[1], TweenInfo.new(0.3), goal):Play()
		end
	end)
	task.delay(1.0, function()
		gui:Destroy()
		release(anchor)
	end)
end

------------------------------------------------------------------------------------------
-- jumps, auras
------------------------------------------------------------------------------------------

-- The "boom" under a jumper's feet.
function VFXController.boom(entityId, kind)
	local model = Util.modelOf(entityId)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local p = hrp.Position
	local big = kind == "Spike" or kind == "Serve"
	if entityId == State.myId and mods then
		mods.AudioController.play("Boom", { volume = big and 0.8 or 0.45, minGap = 0.05 })
	end
	if big and toolboxFx("JumpBoom", Vector3.new(p.X, 0.3, p.Z)) then
		return -- the Toolbox boom replaces the procedural ring and streaks
	end
	floorRing(Vector3.new(p.X, 0.2, p.Z), WHITE, big and 6 or 3.5, big and 0.32 or 0.25)
	emit(dustEmitter, Vector3.new(p.X, 0.4, p.Z), big and 16 or 8)
	if big then
		ringFx(Vector3.new(p.X, 1.2, p.Z), WHITE, 2, 9, 0.28, 5)
		for i = -1, 1 do
			local s = take(Enum.PartType.Block)
			s.Color = WHITE
			local base = Vector3.new(p.X - 0.8, 1.6, p.Z + i * 0.7)
			animate(s, 0.22, Vector3.new(0.1, 3.2, 0.14), Vector3.new(0.04, 0.4, 0.06), 0.2, 1, CFrame.new(base))
		end
	end
end

-- Emitters for the Azure aura: the Toolbox AzureAura template's emitters if there is one,
-- otherwise a procedural blue flame. Returns a list of { emitter, baseRate }.
local function auraEmitters(att)
	local out = {}
	local template = Assets.toolbox("VFX.AzureAura")
	if template then
		local clone = Assets.sanitize(template:Clone())
		local list = clone:GetDescendants()
		table.insert(list, clone)
		for _, d in ipairs(list) do
			if d:IsA("ParticleEmitter") then
				local pe = d:Clone()
				pe.Enabled = true
				pe.Parent = att
				table.insert(out, { pe, pe.Rate > 0 and pe.Rate or 40 })
			end
		end
		clone:Destroy()
		if #out > 0 then
			return out
		end
	end
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = Assets.Images.Fire
	pe.Color = ColorSequence.new(Color3.fromRGB(150, 245, 255), Color3.fromRGB(30, 100, 255))
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Rate = 40
	pe.Lifetime = NumberRange.new(0.3, 0.55)
	pe.Speed = NumberRange.new(2, 5)
	pe.RotSpeed = NumberRange.new(-200, 200)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	pe.Parent = att
	table.insert(out, { pe, 40 })
	return out
end

local function setAura(model, on, energy)
	local fx = auras[model]
	if not on then
		if fx then
			fx.att:Destroy()
			fx.hl:Destroy()
			auras[model] = nil
		end
		return
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	if not fx then
		local att = Instance.new("Attachment")
		att.Name = "AzureAura"
		att.Parent = hrp
		local hl = Instance.new("Highlight")
		hl.FillColor = AZURE
		hl.FillTransparency = 0.8
		hl.OutlineColor = Color3.fromRGB(180, 250, 255)
		hl.OutlineTransparency = 0.2
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
		fx = { att = att, emitters = auraEmitters(att), hl = hl }
		auras[model] = fx
	end
	local e = math.clamp(energy or 0.6, 0, 1.3)
	-- 30 + 110 * e particles/s for the procedural flame (base 40): about 0.75x to 4.3x
	local k = (30 + 110 * e) / 40
	for _, item in ipairs(fx.emitters) do
		item[1].Rate = item[2] * k
	end
	fx.hl.FillTransparency = 0.85 - 0.35 * math.min(e, 1)
	if e > 1 then
		fx.hl.FillColor = HOT
	else
		fx.hl.FillColor = AZURE
	end
end

------------------------------------------------------------------------------------------
-- reactions to gameplay
------------------------------------------------------------------------------------------

local function onHit(snap)
	local meta = snap.meta
	if not meta or not snap.path then
		return
	end
	local seg = snap.path.segs[1]
	local pos = seg.p
	local dirZ = seg.v.Z >= 0 and 1 or -1
	local tc = teamColor(meta.team)
	local ht = meta.hitType
	local kmh = meta.kmh or 0
	local mine = meta.id == State.myId
	local close = mine or near(pos)
	local shaker = mods.CameraController
	local model = meta.id and Util.modelOf(meta.id)
	if model then
		setAura(model, false)
	end

	if ht == "Spike" or ht == "JumpServe" then
		local heavy = kmh >= 120
		local vdir = seg.v.Magnitude > 0 and seg.v.Unit or Vector3.new(0, -1, dirZ)
		if meta.thunder then
			if not toolboxFx("ThunderImpact", pos) then
				starburst(pos, THUNDER, 11, 14, 0.3)
				ringFx(pos, THUNDER, 2, 14, 0.35, 8)
				for _ = 1, 4 do
					local d = (vdir + Vector3.new(0, (math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.2)).Unit
					bolt(pos, d, 7 + math.random() * 5, THUNDER)
				end
				emit(sparkEmitter, pos, 40, THUNDER)
			end
			if close then
				VFXController.impactFrame(meta.id, THUNDER)
				VFXController.speedLines(0.5, Color3.fromRGB(255, 244, 180), dirZ)
				shaker.shake(0.6)
				shaker.kick(-6)
			end
		elseif meta.energy then
			local e = math.min(meta.energy, 1)
			if not toolboxFx("AzureImpact", pos) then
				starburst(pos, AZURE, 7 + 6 * e, 12, 0.3)
				ringFx(pos, AZURE, 2, 8 + 8 * e, 0.35, 7)
				ringFx(pos, WHITE, 1, 5 + 4 * e, 0.25, 4)
				emit(fireEmitter, pos, math.floor(10 + 25 * e), AZURE)
			end
			if meta.pierce then
				VFXController.popup(pos, "Pierce!", AZURE, 1.1)
			end
			if meta.overcharge then
				VFXController.popup(pos, "Overcharged!", HOT, 0.9)
			end
			if close and e >= 0.9 then
				VFXController.impactFrame(meta.id, Color3.fromRGB(40, 120, 255))
				shaker.shake(0.55)
				shaker.kick(-5)
			elseif close then
				shaker.shake(0.3)
			end
			if close then
				VFXController.speedLines(0.35 + 0.2 * e, Color3.fromRGB(190, 240, 255), dirZ)
			end
		else
			if not toolboxFx(heavy and "PerfectImpact" or "SpikeImpact", pos) then
				starburst(pos, WHITE, heavy and 10 or 6, heavy and 14 or 10, 0.26)
				ringFx(pos, WHITE, 1.5, heavy and 11 or 7, 0.3, 6)
				if heavy then
					ringFx(pos, HOT, 1, 8, 0.3, 5)
					burst(pos, HOT, 2.8, 0.18)
				end
				emit(sparkEmitter, pos, heavy and 26 or 12, heavy and HOT or WHITE)
			end
			if close then
				if heavy and meta.grade == "PERFECT" and kmh >= 132 then
					VFXController.impactFrame(meta.id, HOT)
				end
				if heavy then
					VFXController.speedLines(0.35, WHITE, dirZ)
					shaker.kick(-4)
				end
				shaker.shake(heavy and 0.4 or 0.18)
			end
		end
		return
	end

	if ht == "Block" then
		local outcome = meta.outcome
		if outcome == "Stuff" then
			if not toolboxFx("BlockImpact", pos) then
				starburst(pos, tc, 10, 12, 0.3)
				ringFx(pos, tc, 2, 12, 0.35, 8)
				shards(pos, tc, 10, 45)
				emit(sparkEmitter, pos, 30, tc)
			end
			VFXController.popup(pos, "Stuff!", tc, 1.2)
			VFXController.impactFrame(meta.id, tc)
			shaker.shake(0.5)
			shaker.kick(-5)
		else
			ringFx(pos, tc, 1, 5, 0.25, 5)
			emit(sparkEmitter, pos, 8, tc)
			if outcome == "Soft" then
				VFXController.popup(pos, "Soft block", UI.Chalk, 0.7)
			end
		end
		return
	end

	if ht == "Bump" or ht == "Set" or ht == "Free" or ht == "Feint" or ht == "Overhand" then
		if not toolboxFx("ReceiveImpact", pos) then
			ringFx(pos, meta.perfect and UI.Spark or WHITE, 1, 4.5, 0.22, 4)
		end
		if meta.fail then
			shards(pos, Color3.fromRGB(200, 230, 255), 12, 40)
			VFXController.popup(pos, "Broken", HOT, 1)
			return
		end
		if meta.free then
			VFXController.popup(pos, "Free ball!", UI.Chalk, 1)
		elseif meta.score and ht == "Bump" then
			local grade = meta.grade or "GOOD"
			VFXController.popup(pos, grade .. " " .. tostring(meta.score), GRADE_COLOR[grade] or UI.Chalk, 0.9, meta.perfect)
		elseif ht == "Set" and meta.grade == "PERFECT" then
			VFXController.popup(pos, "Nice set", UI.Mint, 0.8)
		end
		if meta.slide then
			emit(dustEmitter, Vector3.new(pos.X, 0.4, pos.Z), 14)
		end
		if mine then
			shaker.shake(meta.drain and math.clamp(meta.drain / 40, 0.05, 0.3) or 0.05)
		end
	end
end

local function onBallEvent(kind, ev, meta)
	if kind == "Land" then
		if ev.kind ~= "Floor" then
			return
		end
		local pos = Vector3.new(0, 0.2, ev.pos.Z)
		local speed = ev.vel.Magnitude
		local hard = speed > 45
		if not toolboxFx("FloorImpact", pos) then
			floorRing(pos, WHITE, hard and 8 or 3.5, hard and 0.4 or 0.3)
			emit(dustEmitter, pos, hard and 28 or 10)
			if hard then
				local c = WHITE
				if meta and meta.thunder then
					c = THUNDER
				elseif meta and meta.energy then
					c = AZURE
				end
				starburst(pos + Vector3.new(0, 0.8, 0), c, 8, 10, 0.3)
				shards(pos + Vector3.new(0, 0.4, 0), Color3.fromRGB(255, 220, 170), 8, 30)
			end
		end
		if hard then
			mods.CameraController.shake(0.35)
		end
	elseif kind == "Net" then
		local pos = Vector3.new(0, ev.pos.Y, 0)
		if not toolboxFx("NetImpact", pos) then
			ringFx(pos, WHITE, 1, 4, 0.3, 4)
		end
		VFXController.rippleNet()
	end
end

-- The net sways where it was hit.
function VFXController.rippleNet()
	local arena = workspace:FindFirstChild("Arena")
	local net = arena and arena:FindFirstChild("Net")
	local mesh = net and net:FindFirstChild("Mesh")
	if not mesh then
		return
	end
	for _, strand in ipairs(mesh:GetChildren()) do
		if strand:IsA("BasePart") then
			local base = strand:GetAttribute("BaseCF")
			if not base then
				base = strand.CFrame
				strand:SetAttribute("BaseCF", base)
			end
			local amp = 0.5 * (1 - math.clamp(math.abs(strand.Position.X) / 16, 0, 0.8))
			strand.CFrame = base * CFrame.new(0, 0, amp)
			TweenService:Create(strand, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { CFrame = base }):Play()
		end
	end
end

local function onBreak(a)
	local model = a.id and Util.modelOf(a.id)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	local pos = hrp and hrp.Position + Vector3.new(0, 2, 0) or Vector3.new(0, 3, 0)
	if not toolboxFx("GuardBreak", pos) then
		shards(pos, Color3.fromRGB(210, 235, 255), 16, 50)
		ringFx(pos, HOT, 2, 12, 0.4, 8)
	end
	VFXController.popup(pos, "Guard break!", HOT, 1.2)
	if a.team == State.myTeam then
		VFXController.flash(0.35, 0.3)
		mods.CameraController.shake(0.45)
	end
end

function VFXController.init(m)
	mods = m
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "SpikeRushFX"
	fxFolder.Parent = workspace

	emitterHolder = Instance.new("Part")
	emitterHolder.Name = "Emitters"
	emitterHolder.Anchored = true
	emitterHolder.CanCollide = false
	emitterHolder.CanQuery = false
	emitterHolder.CanTouch = false
	emitterHolder.Transparency = 1
	emitterHolder.Size = Vector3.new(0.2, 0.2, 0.2)
	emitterHolder.Parent = fxFolder

	sparkEmitter = makeEmitter(Assets.Images.Spark, {
		LightEmission = 1,
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(18, 42),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	})
	dustEmitter = makeEmitter(Assets.Images.Smoke, {
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(180, 10),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 4,
		Acceleration = Vector3.new(0, 2, 0),
		Color = ColorSequence.new(Color3.fromRGB(230, 214, 190)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
	})
	fireEmitter = makeEmitter(Assets.Images.Fire, {
		LightEmission = 1,
		Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(8, 20),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	})

	buildScreen()

	State.signals.Ball:Connect(function(snap, isEcho)
		if isEcho or snap.state ~= "Flight" then
			return
		end
		onHit(snap)
	end)
	State.signals.BallEvent:Connect(onBallEvent)
	State.signals.Announce:Connect(function(a)
		if a.kind == "Break" then
			onBreak(a)
		elseif a.kind == "Point" and a.landing and (a.reason == "Spike" or a.reason == "Ace" or a.reason == "Stuff" or a.reason == "Break") then
			emit(sparkEmitter, a.landing + Vector3.new(0, 1, 0), 24, teamColor(a.winner))
		end
	end)
	State.signals.Action:Connect(function(entityId, kind, extra)
		local model = Util.modelOf(entityId)
		if kind == "Jump" then
			VFXController.boom(entityId, extra)
		elseif kind == "Charge" and model then
			setAura(model, true, 0.6)
		elseif kind == "ChargeEnd" and model then
			setAura(model, false)
		elseif kind == "Slide" and model then
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hrp then
				emit(dustEmitter, Vector3.new(hrp.Position.X, 0.4, hrp.Position.Z), 12)
			end
		end
	end)
	-- local Azure charge drives my own aura
	State.signals.Charge:Connect(function(energy, _, st)
		local c = player.Character
		if not c then
			return
		end
		if st == "idle" then
			if auras[c] then
				setAura(c, false)
			end
		else
			local e = energy
			if st == "over" then
				e = 1.2
			end
			setAura(c, true, e)
		end
	end)
	RunService.RenderStepped:Connect(updateLines)
end

return VFXController
