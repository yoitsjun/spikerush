-- Authoritative ball. The server never simulates a physics part: it stores the current
-- analytic path, broadcasts it once per touch, and waits for the touchdown time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local BallPhysics = require(Shared.BallPhysics)

local BallService = {}

BallService.seq = 0
BallService.state = "Idle" -- Idle | Held | Flight | Dead
BallService.path = nil
BallService.holderId = nil
BallService.lastHit = nil
BallService.touch = { count = 0 }
BallService.onDead = Util.Signal()

local deadFired = true

function BallService.snapshot()
	return {
		seq = BallService.seq,
		state = BallService.state,
		holder = BallService.holderId,
		path = BallService.path,
		meta = BallService.lastHit,
		touch = BallService.touch,
	}
end

local function broadcast()
	Net.get("BallState"):FireAllClients(BallService.snapshot())
end

function BallService.sendTo(plr)
	Net.get("BallState"):FireClient(plr, BallService.snapshot())
end

function BallService.hold(entityId)
	BallService.seq = BallService.seq + 1
	BallService.state = "Held"
	BallService.holderId = entityId
	BallService.path = nil
	BallService.lastHit = nil
	BallService.touch = { count = 0 }
	deadFired = true
	broadcast()
end

function BallService.hide()
	BallService.seq = BallService.seq + 1
	BallService.state = "Idle"
	BallService.holderId = nil
	BallService.path = nil
	BallService.lastHit = nil
	BallService.touch = { count = 0 }
	deadFired = true
	broadcast()
end

function BallService.launch(launch, meta, touch)
	BallService.seq = BallService.seq + 1
	BallService.path = BallPhysics.buildPath(launch)
	BallService.state = "Flight"
	BallService.holderId = nil
	BallService.lastHit = meta
	if touch then
		BallService.touch = touch
	end
	deadFired = false
	broadcast()
	return BallService.path
end

function BallService.positionAt(t)
	if BallService.path then
		return (BallPhysics.positionAt(BallService.path, t))
	end
	return nil
end

function BallService.velocityAt(t)
	if BallService.path then
		return BallPhysics.velocityAt(BallService.path, t)
	end
	return Vector3.zero
end

function BallService.isLive(t)
	return BallService.state == "Flight" and BallService.path ~= nil and (t or Util.now()) < BallService.path.landing.t
end

function BallService.init()
	RunService.Heartbeat:Connect(function()
		if BallService.state ~= "Flight" or deadFired or not BallService.path then
			return
		end
		local landing = BallService.path.landing
		-- The grace window lets a dig sent by a client just before touchdown still arrive.
		if Util.now() >= landing.t + Config.Ball.LandGrace then
			deadFired = true
			BallService.state = "Dead"
			BallService.onDead:Fire(landing, BallService.path.flags, BallService.lastHit, BallService.touch)
		end
	end)
end

return BallService
