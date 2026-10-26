-- Beginner mode's jump ring (Config.Beginner; the owner, 2026-10-25: "where you spike and jump there
-- is a white circle indicator"). While your team's ball is up for you to spike (a teammate touched
-- it last and you can still touch it), a white ring on the floor marks where to take off: under
-- the point where the ball comes down through your hitting height, moved back so it meets your hand
-- at the sweet spot (Zones.SpikeCenterDz). The ring closes from RingSize[2] to RingSize[1] over
-- LeadTime and is shut when it's time to jump (the time your jump takes to reach its top before the
-- ball gets there). Never in a ranked match (State.beginner).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BallPhysics = require(Shared.BallPhysics)
local Characters = require(Shared.Characters)
local HitLogic = require(Shared.HitLogic)
local State = require(script.Parent.State)

local BeginnerGuide = {}
local mods

local B, Z = Config.Beginner, Config.Zones
local FLAT = CFrame.Angles(0, 0, math.rad(90))
local HIDDEN = CFrame.new(0, -500, 0)

local ring, core = nil, nil
local plan = nil -- { seq, contactT, jumpT, z }: worked out once per ball path

local function part(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = HIDDEN
	return p
end

-- Where and when to jump for this path, or nil when the ball never comes down through your hitting
-- height on your side.
local function work(path, now)
	local stats = State.myStats()
	local side = State.mySide
	local y = stats.contactMaxStuds + Z.SpikeCenterDy -- the ball at the sweet spot, at the top of your jump
	local t, p = BallPhysics.findTime(path, now, function(pos, vel)
		return vel.Y < 0 and pos.Y <= y and pos.Z * side > 0
	end)
	if not t then
		return nil
	end
	-- (your hand is SpikeForward toward the net from you, and meets the ball SpikeCenterDz behind it)
	local z = p.Z + side * (Z.SpikeCenterDz + Z.SpikeForward)
	local g = Config.Player.Gravity
	local rise = math.sqrt(2 * Characters.jumpHeight(stats) / g)
	return { contactT = t, jumpT = t - rise, z = z }
end

local function show()
	if not State.beginner() or not State.isPlaying or not State.myTeam then
		return false
	end
	local BR = mods.BallRenderer
	if not BR.isLive() then
		return false
	end
	local meta = BR.getMeta()
	if not meta or meta.team ~= State.myTeam or meta.id == State.myId or meta.hitType == "Toss" then
		return false
	end
	return HitLogic.canTouch(BR.getTouch(), State.myTeam, State.myId, "Spike", State.teamSize()) and true or false
end

local function step()
	if not show() then
		plan = nil
		ring.CFrame, core.CFrame = HIDDEN, HIDDEN
		return
	end
	local BR = mods.BallRenderer
	local now = workspace:GetServerTimeNow()
	local seq = BR.getSeq()
	if not plan or plan.seq ~= seq then
		plan = work(BR.getPath(), now) or { none = true }
		plan.seq = seq
	end
	if plan.none or now > plan.contactT then
		ring.CFrame, core.CFrame = HIDDEN, HIDDEN
		return
	end
	local k = math.clamp((plan.jumpT - now) / B.LeadTime, 0, 1)
	local size = B.RingSize[1] + (B.RingSize[2] - B.RingSize[1]) * k
	ring.Size = Vector3.new(0.03, size, size)
	core.Size = Vector3.new(0.035, size * 0.82, size * 0.82)
	ring.CFrame = CFrame.new(0, 0.16, plan.z) * FLAT
	core.CFrame = CFrame.new(0, 0.17, plan.z) * FLAT
	-- (bright once it's time to go)
	ring.Transparency = k <= 0 and 0 or 0.25
end

function BeginnerGuide.init(m)
	mods = m
	local folder = Instance.new("Folder")
	folder.Name = "BeginnerGuide"
	folder.Parent = workspace
	ring = part("JumpRing", Vector3.new(0.03, 6, 6), Color3.new(1, 1, 1), Enum.Material.Neon)
	core = part("JumpCore", Vector3.new(0.035, 5, 5), Color3.fromRGB(22, 24, 36), Enum.Material.SmoothPlastic)
	core.Transparency = 0.5
	ring.Parent = folder
	core.Parent = folder
	RunService.RenderStepped:Connect(step)
end

return BeginnerGuide
