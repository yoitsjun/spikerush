-- Setter aim. The owner: "setter mode: play as a setter and aim where the ball is going to be
-- set. the opponent cannot see but your team can. mark the location with a circle or
-- crosshair". While you set for your team (the setter, or alone in 1v1) and your team hasn't
-- set yet, a marker on your side shows where your set will come down: a ring on the floor, a
-- post up from it and a crosshair at the hitting height. Aim with the mouse over the court, the
-- right stick, or a tap on the court; Set sends the ball there (HitLogic's input.aimDepth, with
-- the usual accuracy error). The server passes your aim to your teammates only (the SetAim
-- remote), who see it in your team's colour. Settings > Setter aim turns it off.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Net = require(Shared.Net)
local State = require(script.Parent.State)

local SetterAim = {}
local mods

local H = Config.Hits
local STICK_SPEED = 22 -- studs a second at full right stick
local EXPIRE = 3 -- a teammate's marker that hasn't been heard from for this long goes

local aim = nil -- your aim: the set's distance from the net (studs)
local stickX = 0
local sent, sentAt = nil, 0
local marks = {} -- entityId -> { depth, team, seen }: your aim and your teammates'
local drawn = {} -- entityId -> the marker's parts
local folder = nil

local function clampDepth(d)
	return math.clamp(d, H.SetAimMin, H.SetAimMax)
end

-- Your aim is on while you set for your team, the rally is on and your team hasn't set yet.
local function on()
	if not State.isPlaying or State.settings.setterAim == false or not mods then
		return false
	end
	if State.myRole ~= "SE" and State.teamSize() > 1 then
		return false
	end
	local phase = State.phase()
	if phase ~= "Rally" and phase ~= "Serving" and phase ~= "PreServe" then
		return false
	end
	local touch = mods.BallRenderer.getTouch()
	return not (touch and touch.team == State.myTeam and (touch.count or 0) >= 2)
end

-- Where a ray from the camera meets the plane the ball flies in (x = 0), as a depth on your
-- side of the net.
local function depthAt(ray)
	if math.abs(ray.Direction.X) < 1e-3 then
		return nil
	end
	local t = -ray.Origin.X / ray.Direction.X
	if t <= 0 then
		return nil
	end
	return clampDepth((ray.Origin.Z + ray.Direction.Z * t) * State.mySide)
end

-- Your aim, while it's on (ActionController's Set sends the ball there).
function SetterAim.depth()
	if on() then
		return aim
	end
	return nil
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = folder
	return p
end

-- The marker: a ring on the floor, a post up from it, and at the hitting height a crosshair
-- (a see-through disc and two bars, standing across the court so the camera sees it face on).
local function build(color)
	return {
		ring = part({ Name = "AimRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 4.6, 4.6), Color = color, Transparency = 0.5 }),
		post = part({ Name = "AimPost", Size = Vector3.new(0.16, 1, 0.16), Color = color, Transparency = 0.45 }),
		disc = part({ Name = "AimDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 3.2, 3.2), Color = color, Transparency = 0.72 }),
		barY = part({ Name = "AimBarY", Size = Vector3.new(0.1, 4, 0.2), Color = color }),
		barZ = part({ Name = "AimBarZ", Size = Vector3.new(0.1, 0.2, 4), Color = color }),
	}
end

local function place(d, team, depth)
	local z = Court.sideOf(team) * depth
	local top = H.SetArriveY
	d.ring.CFrame = CFrame.new(0, 0.06, z) * CFrame.Angles(0, 0, math.pi / 2)
	d.post.Size = Vector3.new(0.16, top, 0.16)
	d.post.CFrame = CFrame.new(0, top / 2, z)
	local cross = CFrame.new(-0.2, top, z) -- a hair nearer the camera than the ball's plane
	d.disc.CFrame = cross
	d.barY.CFrame = cross
	d.barZ.CFrame = cross
end

local function update(dt)
	local now = os.clock()
	local active = on()
	if active then
		aim = aim or Court.attackDepth("Open")
		if math.abs(stickX) > 0.2 then
			aim = clampDepth(aim + stickX * State.mySide * STICK_SPEED * dt)
		end
	end
	-- tell your team: when it moves (at most 10 times a second), once a second while it holds,
	-- and once when it stops
	local want = active and aim or nil
	local moved = (want == nil) ~= (sent == nil) or (want and sent and math.abs(want - sent) > 0.1)
	if (moved and now - sentAt >= 0.1) or (want and now - sentAt >= 1) then
		Net.get("SetAim"):FireServer(want or false)
		sent, sentAt = want, now
	end
	if want then
		marks[State.myId] = { depth = want, team = State.myTeam, seen = now }
	else
		marks[State.myId] = nil
	end
	-- draw every aim that's still live; tidy the rest
	for id, m in pairs(marks) do
		if not State.isPlaying or (id ~= State.myId and now - m.seen > EXPIRE) then
			marks[id] = nil
		end
	end
	for id, d in pairs(drawn) do
		if not marks[id] then
			for _, p in pairs(d) do
				p:Destroy()
			end
			drawn[id] = nil
		end
	end
	for id, m in pairs(marks) do
		local d = drawn[id]
		if not d then
			local cfg = Config.Teams[m.team]
			d = build(cfg and cfg.Color or Color3.new(1, 1, 1))
			drawn[id] = d
		end
		place(d, m.team, m.depth)
	end
end

function SetterAim.init(m)
	mods = m
	folder = Instance.new("Folder")
	folder.Name = "SpikeRushSetterAim"
	folder.Parent = workspace
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if on() and workspace.CurrentCamera then
				local p = UserInputService:GetMouseLocation()
				aim = depthAt(workspace.CurrentCamera:ViewportPointToRay(p.X, p.Y)) or aim
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stickX = input.Position.X
		end
	end)
	UserInputService.TouchTapInWorld:Connect(function(pos, processedByUI)
		if not processedByUI and on() and workspace.CurrentCamera then
			aim = depthAt(workspace.CurrentCamera:ScreenPointToRay(pos.X, pos.Y)) or aim
		end
	end)
	-- a teammate's aim (the server only sends your own team's)
	Net.get("SetAim").OnClientEvent:Connect(function(id, depth)
		if type(id) ~= "string" or id == State.myId then
			return
		end
		if type(depth) == "number" and depth == depth then
			marks[id] = { depth = clampDepth(depth), team = State.myTeam, seen = os.clock() }
		else
			marks[id] = nil
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(update, dt)
		if not ok then
			warn("[SpikeRush] setter aim: " .. tostring(err))
		end
	end)
end

return SetterAim
