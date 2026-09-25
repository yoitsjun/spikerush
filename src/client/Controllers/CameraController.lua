-- Camera: a side-on broadcast view (the 2.5D look). A long lens from the open near side keeps
-- perspective flat, like a 2D game drawn in 3D. It tracks the ball along the court, rises and
-- pulls back for high sets, closes in on your serve, swings to a low angled view after a point,
-- and punches in on big hits (with trauma-based shake).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local State = require(script.Parent.State)

local CameraController = {}
local mods

local player = Players.LocalPlayer
local C = Config.Court
local BASE_FOV = 34
local DIST = 64
local CLOSE_DIST = 52

local trauma = 0
local fovKick = 0
local roll = 0
local camPos, camLook = nil, nil
local seed = math.random() * 1000
local pointCam = nil -- { focus, untilT, duration, yaw }

function CameraController.shake(amount)
	trauma = math.min(1, trauma + amount * (State.settings.shake or 1))
end

-- Positive widens, negative punches in.
function CameraController.kick(fov)
	if math.abs(fov) > math.abs(fovKick) then
		fovKick = fov
	end
end

function CameraController.tilt(degrees)
	if State.settings.dramatic then
		roll = degrees
	end
end

local function myRoot()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function side(focus, height, dist, yaw, lookY)
	local a = math.rad(yaw or 0)
	local pos = Vector3.new(-dist * math.cos(a), height, focus - dist * math.sin(a))
	return pos, Vector3.new(2, lookY, focus)
end

local function desired(now)
	local phase = State.phase()
	local BR = mods.BallRenderer
	local ballPos = BR.renderPosition()
	local ballVisible = ballPos.Y > -100
	local root = myRoot()
	local dist = State.settings.closeCam and CLOSE_DIST or DIST

	-- dramatic angle on the landing spot right after a point
	if pointCam and now < pointCam.untilT and State.settings.dramatic then
		local e = 1 - (pointCam.untilT - now) / pointCam.duration
		local f = pointCam.focus
		local pos, look = side(f.Z, 6 + e * 3, 38 - e * 4, pointCam.yaw, 3)
		return pos, look, 38
	end

	-- lobby: follow yourself along the court
	if not State.isPlaying then
		local z = root and root.Position.Z * 0.7 or 0
		local pos, look = side(z, 18, dist, 0, 8)
		return pos, look, BASE_FOV
	end

	-- serve close-up
	if State.isServer() and (phase == "PreServe" or phase == "Serving") and root then
		local meta = BR.getMeta()
		local served = meta and meta.hitType ~= "Toss" and BR.getState() == "Flight"
		if not served then
			local r = root.Position
			local lift = 0
			if ballVisible then
				lift = math.max(0, ballPos.Y - 16) * 0.5
			end
			local pos, look = side(r.Z - State.mySide * 12, 14 + lift, dist - 14, 0, 9 + lift)
			return pos, look, BASE_FOV
		end
	end

	-- rally: frame the ball, leaning toward the net so both sides stay readable
	local focus = 0
	if root then
		focus = root.Position.Z * 0.25
	end
	-- jumps reach about 20 studs and sets peak near 30, so the frame sits a little higher and
	-- starts pulling back once the ball climbs past a spiker's hand
	local lookY = 10
	local height = 19
	if ballVisible then
		focus = Util.lerp(focus, ballPos.Z, 0.6)
		local over = math.max(0, ballPos.Y - 18)
		lookY = lookY + over * 0.45
		height = height + over * 0.5
		dist = dist + over * 0.8
	end
	focus = math.clamp(focus, -(C.SideDepth * 0.6), C.SideDepth * 0.6)
	local pos, look = side(focus, height, dist, 0, lookY)
	return pos, look, BASE_FOV
end

local function update(dt)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local now = os.clock()
	local pos, look, fov = desired(now)
	fov = fov or BASE_FOV
	local speed = 4.5
	if pointCam and now < pointCam.untilT then
		speed = 3.5
	end
	if not camPos then
		camPos, camLook = pos, look
	else
		camPos = camPos:Lerp(pos, 1 - math.exp(-speed * dt))
		camLook = camLook:Lerp(look, 1 - math.exp(-speed * 1.3 * dt))
	end

	trauma = math.max(0, trauma - dt * 1.7)
	fovKick = Util.damp(fovKick, 0, 6, dt)
	roll = Util.damp(roll, 0, 5, dt)

	local cf = CFrame.lookAt(camPos, camLook)
	local shake = trauma * trauma
	if shake > 0.001 then
		local t = now * 28
		local ox = math.noise(seed, t) * 1.4 * shake
		local oy = math.noise(seed + 10, t) * 1.4 * shake
		local rz = math.noise(seed + 20, t) * math.rad(3) * shake
		cf = cf * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, rz)
	end
	if math.abs(roll) > 0.01 then
		cf = cf * CFrame.Angles(0, 0, math.rad(roll))
	end
	cam.CFrame = cf
	cam.FieldOfView = math.clamp(fov + fovKick, 20, 70)
end

function CameraController.init(m)
	mods = m
	State.signals.Announce:Connect(function(a)
		if a.kind == "Point" and a.landing and a.reason ~= "ServeClock" then
			local dur = Config.Match.PointPauseTime * 0.6
			local yaw = a.landing.Z > 0 and -14 or 14
			pointCam = { focus = a.landing, untilT = os.clock() + dur, duration = dur, yaw = yaw }
		elseif a.kind ~= "Point" then
			pointCam = nil
		end
	end)
	State.signals.Match:Connect(function(match)
		if match.phase == "PreServe" then
			pointCam = nil
		end
	end)
	RunService:BindToRenderStep("SpikeRushCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
