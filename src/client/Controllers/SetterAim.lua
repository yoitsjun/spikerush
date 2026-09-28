-- Setter aim. The owner: "setter mode: play as a setter and aim where the ball is going to be
-- set. the opponent cannot see but your team can. mark the location with a circle or
-- crosshair", then "up and down full control. you have to charge up the distance though".
-- While you set for your team (the setter, or alone in 1v1) and your team hasn't set yet, a
-- marker on your side shows where your set will come down: a ring on the floor, a post, and a
-- crosshair at the height the set comes down through. The height is yours to aim at any time
-- (the mouse up and down over the court, the right stick, or a tap); the distance from the net
-- is charged: hold Set and the marker slides out from the net (ActionController.setCharge),
-- let go and the set goes there (HitLogic's input.aimDepth and aimHeight, with the usual
-- accuracy error). The server passes your aim to your teammates only (the SetAim remote), who
-- see it in your team's colour. Settings > Setter aim turns it off.

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

local aimY = nil -- the height your set comes down through (world studs)
local stickY = 0
local sent, sentAt = nil, 0
local marks = {} -- entityId -> { depth, team, seen }: your aim and your teammates'
local drawn = {} -- entityId -> the marker's parts
local folder = nil

local function clampDepth(d)
	return math.clamp(d, H.SetAimMin, H.SetAimMax)
end

local function clampHeight(y)
	return math.clamp(y, H.SetAimLowY, H.SetAimHighY)
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

-- Where a ray from the camera meets the plane the ball flies in (x = 0): its height.
local function heightAt(ray)
	if math.abs(ray.Direction.X) < 1e-3 then
		return nil
	end
	local t = -ray.Origin.X / ray.Direction.X
	if t <= 0 then
		return nil
	end
	return clampHeight(ray.Origin.Y + ray.Direction.Y * t)
end

function SetterAim.on()
	return on()
end

-- Your aim right now: the height you picked and the distance charged so far (the near end
-- until Set is held). ActionController sets there when Set is let go.
function SetterAim.aim()
	if not on() then
		return nil
	end
	local charge = mods.ActionController.setCharge() or 0
	return { depth = H.SetAimMin + (H.SetAimMax - H.SetAimMin) * charge, height = aimY or H.SetArriveY }
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

local function place(d, team, depth, height)
	local z = Court.sideOf(team) * depth
	local top = height or H.SetArriveY
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
		aimY = aimY or H.SetArriveY
		if math.abs(stickY) > 0.2 then
			aimY = clampHeight(aimY + stickY * STICK_SPEED * dt)
		end
	end
	-- tell your team: when it moves (at most 10 times a second), once a second while it holds,
	-- and once when it stops
	local a = active and SetterAim.aim() or nil
	local moved = (a == nil) ~= (sent == nil) or (a and sent and (math.abs(a.depth - sent.depth) > 0.1 or math.abs(a.height - sent.height) > 0.1))
	if (moved and now - sentAt >= 0.1) or (a and now - sentAt >= 1) then
		if a then
			Net.get("SetAim"):FireServer(a.depth, a.height)
		else
			Net.get("SetAim"):FireServer(false)
		end
		sent, sentAt = a, now
	end
	if a then
		marks[State.myId] = { depth = a.depth, height = a.height, team = State.myTeam, seen = now }
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
		place(d, m.team, m.depth, m.height)
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
				aimY = heightAt(workspace.CurrentCamera:ViewportPointToRay(p.X, p.Y)) or aimY
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stickY = input.Position.Y
		end
	end)
	UserInputService.TouchTapInWorld:Connect(function(pos, processedByUI)
		if not processedByUI and on() and workspace.CurrentCamera then
			aimY = heightAt(workspace.CurrentCamera:ScreenPointToRay(pos.X, pos.Y)) or aimY
		end
	end)
	-- a teammate's aim (the server only sends your own team's)
	Net.get("SetAim").OnClientEvent:Connect(function(id, depth, height)
		if type(id) ~= "string" or id == State.myId then
			return
		end
		if type(depth) == "number" and depth == depth then
			local y = type(height) == "number" and height == height and clampHeight(height) or H.SetArriveY
			marks[id] = { depth = clampDepth(depth), height = y, team = State.myTeam, seen = os.clock() }
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
