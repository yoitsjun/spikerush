-- Procedural R15 animation. Every character (players and bots) gets volleyball poses layered
-- over whatever the default Animator is doing, by blending Motor6D.Transform in Stepped
-- (which runs after the Animator has posed the rig for the frame).
--
-- Layers, highest first: action (one-shot: bump, set, swing, tip, toss, gather, knockback,
-- celebrate) > stance (held: receive stance, slide, block, crouch, charge, toss ready) >
-- automatic (airborne windup, ready stance, serve hold). Everyone faces along the court, so
-- every pose reads in profile from the side camera.
-- Bots have no Animate script, so they also get a procedural run cycle.
--
-- To use uploaded animations instead, fill Assets.Animations; the local player's actions then
-- play those tracks (they replicate) and skip the procedural pose.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local State = require(script.Parent.State)

local AnimationController = {}

local player = Players.LocalPlayer
local rad = math.rad
local chars = {}
local tracks = {}

-- degrees; R15 joint frames: +X on shoulders/hips swings the limb forward and up,
-- -X on knees bends them, -X on the waist leans forward, +Z raises the right arm sideways.
local POSE_DEFS = {
	Ready = {
		drop = 0.35,
		Waist = { -16, 0, 0 },
		Neck = { 10, 0, 0 },
		LeftHip = { 28, 0, -4 },
		RightHip = { 28, 0, 4 },
		LeftKnee = { -46, 0, 0 },
		RightKnee = { -46, 0, 0 },
		LeftAnkle = { 14, 0, 0 },
		RightAnkle = { 14, 0, 0 },
		LeftShoulder = { 38, 0, -8 },
		RightShoulder = { 38, 0, 8 },
		LeftElbow = { 34, 0, 0 },
		RightElbow = { 34, 0, 0 },
	},
	Bump = {
		drop = 0.5,
		Waist = { -22, 0, 0 },
		Neck = { 12, 0, 0 },
		LeftHip = { 38, 0, -6 },
		RightHip = { 38, 0, 6 },
		LeftKnee = { -58, 0, 0 },
		RightKnee = { -58, 0, 0 },
		LeftAnkle = { 18, 0, 0 },
		RightAnkle = { 18, 0, 0 },
		LeftShoulder = { 62, 0, 16 },
		RightShoulder = { 62, 0, -16 },
		LeftElbow = { 0, 0, 0 },
		RightElbow = { 0, 0, 0 },
		LeftWrist = { -10, 0, 0 },
		RightWrist = { -10, 0, 0 },
	},
	Set = {
		drop = 0.2,
		Waist = { 8, 0, 0 },
		Neck = { 24, 0, 0 },
		LeftHip = { 14, 0, 0 },
		RightHip = { 14, 0, 0 },
		LeftKnee = { -20, 0, 0 },
		RightKnee = { -20, 0, 0 },
		LeftShoulder = { 152, 0, -20 },
		RightShoulder = { 152, 0, 20 },
		LeftElbow = { 72, 0, 0 },
		RightElbow = { 72, 0, 0 },
		LeftWrist = { 30, 0, 0 },
		RightWrist = { 30, 0, 0 },
	},
	Windup = {
		Waist = { 14, 26, 0 },
		Neck = { 16, -14, 0 },
		LeftHip = { 24, 0, -6 },
		RightHip = { 10, 0, 6 },
		LeftKnee = { -52, 0, 0 },
		RightKnee = { -70, 0, 0 },
		LeftShoulder = { 148, 0, -10 },
		RightShoulder = { 172, -20, 42 },
		LeftElbow = { 18, 0, 0 },
		RightElbow = { 112, 0, 0 },
	},
	Swing = {
		Waist = { -32, -24, 0 },
		Neck = { -8, 10, 0 },
		LeftHip = { 38, 0, -6 },
		RightHip = { 30, 0, 6 },
		LeftKnee = { -48, 0, 0 },
		RightKnee = { -40, 0, 0 },
		LeftShoulder = { 36, 0, -24 },
		RightShoulder = { 70, 0, 12 },
		LeftElbow = { 44, 0, 0 },
		RightElbow = { 8, 0, 0 },
		RightWrist = { -30, 0, 0 },
	},
	Tip = {
		Waist = { -6, 8, 0 },
		Neck = { 18, 0, 0 },
		LeftHip = { 18, 0, 0 },
		RightHip = { 14, 0, 0 },
		LeftKnee = { -36, 0, 0 },
		RightKnee = { -40, 0, 0 },
		LeftShoulder = { 60, 0, -12 },
		RightShoulder = { 166, 0, 10 },
		LeftElbow = { 30, 0, 0 },
		RightElbow = { 24, 0, 0 },
		RightWrist = { 40, 0, 0 },
	},
	Block = {
		Waist = { -6, 0, 0 },
		Neck = { 6, 0, 0 },
		LeftHip = { 6, 0, -3 },
		RightHip = { 6, 0, 3 },
		LeftKnee = { -12, 0, 0 },
		RightKnee = { -12, 0, 0 },
		LeftShoulder = { 172, 0, -8 },
		RightShoulder = { 172, 0, 8 },
		LeftElbow = { 4, 0, 0 },
		RightElbow = { 4, 0, 0 },
		LeftWrist = { 20, 0, 0 },
		RightWrist = { 20, 0, 0 },
	},
	Dive = {
		drop = 1.6,
		Root = { -72, 0, 0 },
		Neck = { 48, 0, 0 },
		LeftHip = { -8, 0, -6 },
		RightHip = { -8, 0, 6 },
		LeftKnee = { -24, 0, 0 },
		RightKnee = { -18, 0, 0 },
		LeftShoulder = { 164, 0, 12 },
		RightShoulder = { 164, 0, -12 },
		LeftElbow = { 0, 0, 0 },
		RightElbow = { 0, 0, 0 },
	},
	Gather = {
		drop = 0.75,
		Waist = { -30, 0, 0 },
		Neck = { 18, 0, 0 },
		LeftHip = { 52, 0, -4 },
		RightHip = { 52, 0, 4 },
		LeftKnee = { -78, 0, 0 },
		RightKnee = { -78, 0, 0 },
		LeftAnkle = { 22, 0, 0 },
		RightAnkle = { 22, 0, 0 },
		LeftShoulder = { -48, 0, -10 },
		RightShoulder = { -48, 0, 10 },
		LeftElbow = { 10, 0, 0 },
		RightElbow = { 10, 0, 0 },
	},
	Stance = {
		drop = 0.7,
		Waist = { -26, 0, 0 },
		Neck = { 16, 0, 0 },
		LeftHip = { 46, 0, -8 },
		RightHip = { 46, 0, 8 },
		LeftKnee = { -68, 0, 0 },
		RightKnee = { -68, 0, 0 },
		LeftAnkle = { 20, 0, 0 },
		RightAnkle = { 20, 0, 0 },
		LeftShoulder = { 58, 0, 14 },
		RightShoulder = { 58, 0, -14 },
		LeftElbow = { 4, 0, 0 },
		RightElbow = { 4, 0, 0 },
	},
	Crouch = {
		drop = 0.6,
		Waist = { -12, 0, 0 },
		Neck = { 10, 0, 0 },
		LeftHip = { 40, 0, -4 },
		RightHip = { 40, 0, 4 },
		LeftKnee = { -64, 0, 0 },
		RightKnee = { -64, 0, 0 },
		LeftAnkle = { 18, 0, 0 },
		RightAnkle = { 18, 0, 0 },
		LeftShoulder = { 96, 0, -6 },
		RightShoulder = { 96, 0, 6 },
		LeftElbow = { 70, 0, 0 },
		RightElbow = { 70, 0, 0 },
	},
	Charge = {
		Waist = { 22, 34, 0 },
		Neck = { 18, -20, 0 },
		LeftHip = { 30, 0, -8 },
		RightHip = { 6, 0, 8 },
		LeftKnee = { -58, 0, 0 },
		RightKnee = { -84, 0, 0 },
		LeftShoulder = { 140, 0, -24 },
		RightShoulder = { 176, -30, 58 },
		LeftElbow = { 26, 0, 0 },
		RightElbow = { 128, 0, 0 },
	},
	TossReady = {
		Waist = { 4, 6, 0 },
		Neck = { 14, 0, 0 },
		LeftShoulder = { 110, 0, -6 },
		LeftElbow = { 30, 0, 0 },
		RightShoulder = { 60, -10, 20 },
		RightElbow = { 60, 0, 0 },
	},
	Knockback = {
		drop = 0.4,
		Waist = { 26, 0, 0 },
		Neck = { 30, 0, 0 },
		LeftHip = { 8, 0, -8 },
		RightHip = { 8, 0, 8 },
		LeftKnee = { -30, 0, 0 },
		RightKnee = { -30, 0, 0 },
		LeftShoulder = { 30, 0, -40 },
		RightShoulder = { 30, 0, 40 },
		LeftElbow = { 10, 0, 0 },
		RightElbow = { 10, 0, 0 },
	},
	Toss = {
		Waist = { 6, 10, 0 },
		Neck = { 22, 0, 0 },
		LeftShoulder = { 150, 0, -8 },
		RightShoulder = { 110, -10, 34 },
		LeftElbow = { 10, 0, 0 },
		RightElbow = { 70, 0, 0 },
	},
	Hold = {
		LeftShoulder = { 72, 0, 6 },
		LeftElbow = { 38, 0, 0 },
		RightShoulder = { 20, 0, 6 },
		RightElbow = { 20, 0, 0 },
		Neck = { -6, 0, 0 },
	},
	Celebrate = {
		Waist = { 12, 0, 0 },
		Neck = { 18, 0, 0 },
		LeftShoulder = { 160, 0, -38 },
		RightShoulder = { 160, 0, 38 },
		LeftElbow = { 12, 0, 0 },
		RightElbow = { 12, 0, 0 },
		LeftHip = { 8, 0, -8 },
		RightHip = { 8, 0, 8 },
	},
	Burst = {
		Waist = { 16, 0, 0 },
		Neck = { 22, 0, 0 },
		LeftShoulder = { 24, 0, -62 },
		RightShoulder = { 24, 0, 62 },
		LeftElbow = { 26, 0, 0 },
		RightElbow = { 26, 0, 0 },
		LeftHip = { 18, 0, -12 },
		RightHip = { 18, 0, 12 },
		LeftKnee = { -30, 0, 0 },
		RightKnee = { -30, 0, 0 },
	},
}

local DURATION = {
	Gather = 0.14,
	Knockback = 0.5,
	Bump = 0.32,
	Set = 0.3,
	Swing = 0.34,
	Tip = 0.28,
	Block = 0.42,
	Toss = 0.36,
	Celebrate = 1.4,
	Burst = 0.8,
}

-- precompute CFrames
local POSES = {}
for name, def in pairs(POSE_DEFS) do
	local joints = {}
	for joint, a in pairs(def) do
		if joint ~= "drop" then
			joints[joint] = CFrame.Angles(rad(a[1]), rad(a[2]), rad(a[3]))
		end
	end
	local drop = def.drop or 0
	if drop ~= 0 then
		joints.Root = CFrame.new(0, -drop, 0) * (joints.Root or CFrame.identity)
	end
	POSES[name] = joints
end

------------------------------------------------------------------------------------------
-- character registry
------------------------------------------------------------------------------------------

local function scanMotors(st)
	local motors, n = {}, 0
	for _, d in ipairs(st.model:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
			n = n + 1
		end
	end
	st.motors = motors
	st.motorCount = n
	st.lastScan = os.clock()
end

local function register(model)
	if chars[model] or not model:IsA("Model") then
		return
	end
	local st = {
		model = model,
		isBot = model:GetAttribute("IsBot") == true,
		w = 0,
		pose = nil,
		prevPose = nil,
		switchT = 0,
		phase = 0,
	}
	scanMotors(st)
	chars[model] = st
end

local function stateFor(entityId)
	local model = Util.modelOf(entityId)
	if not model then
		return nil
	end
	register(model)
	return chars[model]
end

------------------------------------------------------------------------------------------
-- optional uploaded animation tracks (local player only; they replicate)
------------------------------------------------------------------------------------------

local function playTrack(pose)
	local id = Assets.id(Assets.Animations[pose])
	if not id then
		return false
	end
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	local set = tracks[animator]
	if not set then
		set = {}
		tracks[animator] = set
		animator.AncestryChanged:Connect(function(_, parent)
			if not parent then
				tracks[animator] = nil
			end
		end)
	end
	local track = set[pose]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, t = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok then
			return false
		end
		track = t
		track.Priority = Enum.AnimationPriority.Action2
		set[pose] = track
	end
	track:Play(0.05)
	return true
end

------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------

function AnimationController.playAction(entityId, pose)
	if not POSES[pose] then
		return
	end
	if entityId == State.myId and playTrack(pose) then
		return
	end
	local st = stateFor(entityId)
	if st then
		st.action = { pose = pose, t0 = os.clock(), dur = DURATION[pose] or 0.3 }
	end
end

function AnimationController.setStance(entityId, pose, duration)
	local st = stateFor(entityId)
	if not st then
		return
	end
	if pose == nil then
		st.stance = nil
		return
	end
	if entityId == State.myId and pose == "Dive" and playTrack("Dive") then
		return
	end
	st.stance = { pose = pose, untilT = os.clock() + (duration or 1) }
end

local STANCES = { Stance = true, Slide = true, Crouch = true, Block = true, Charge = true, TossReady = true, Dive = true }

-- One entry point: one-shot actions play once, stances hold for `duration`.
function AnimationController.pose(entityId, kind, duration)
	if kind == "Slide" then
		kind = "Dive"
	end
	if STANCES[kind] then
		AnimationController.setStance(entityId, kind, duration or 0.8)
	else
		AnimationController.playAction(entityId, kind)
	end
end

function AnimationController.clearStance(entityId)
	AnimationController.setStance(entityId, nil)
end

------------------------------------------------------------------------------------------
-- per frame
------------------------------------------------------------------------------------------

local function holdsBall(st)
	local BR = AnimationController.mods and AnimationController.mods.BallRenderer
	if not BR or BR.getState() ~= "Held" then
		return false
	end
	return st.model:GetAttribute("EntityId") == BR.getHolder()
end

local function pick(st, hum, hrp)
	local now = os.clock()
	if st.action and now < st.action.t0 + st.action.dur then
		return st.action.pose, 1
	end
	if st.stance and now < st.stance.untilT then
		return st.stance.pose, 1
	end
	local groundY = hum.HipHeight + hrp.Size.Y / 2
	if hum.FloorMaterial == Enum.Material.Air and hrp.Position.Y > groundY + 1.0 then
		return "Windup", 0.9
	end
	local phase = State.phase()
	if holdsBall(st) then
		return "Hold", 0.9
	end
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if (phase == "Rally" or phase == "Serving" or phase == "PreServe") and speed < 3 then
		return "Ready", 0.75
	end
	return nil, 0
end

-- Procedural run cycle for bots (players use the default Animate script).
local function locomotion(st, hrp, dt, joint)
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local k = math.clamp(speed / 16, 0, 1)
	if k < 0.02 then
		return CFrame.identity
	end
	local s = math.sin(st.phase)
	if joint == "LeftHip" then
		return CFrame.Angles(rad(s * 40 * k), 0, 0)
	elseif joint == "RightHip" then
		return CFrame.Angles(rad(-s * 40 * k), 0, 0)
	elseif joint == "LeftKnee" then
		return CFrame.Angles(rad(-(math.max(0, -s) * 60 + 8) * k), 0, 0)
	elseif joint == "RightKnee" then
		return CFrame.Angles(rad(-(math.max(0, s) * 60 + 8) * k), 0, 0)
	elseif joint == "LeftShoulder" then
		return CFrame.Angles(rad(-s * 34 * k), 0, rad(-6 * k))
	elseif joint == "RightShoulder" then
		return CFrame.Angles(rad(s * 34 * k), 0, rad(6 * k))
	elseif joint == "LeftElbow" or joint == "RightElbow" then
		return CFrame.Angles(rad(28 * k), 0, 0)
	elseif joint == "Waist" then
		return CFrame.Angles(rad(-8 * k), rad(s * 8 * k), 0)
	elseif joint == "Root" then
		return CFrame.new(0, math.abs(math.cos(st.phase)) * 0.18 * k, 0)
	end
	return CFrame.identity
end

local BOT_JOINTS = { "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "Waist", "Root" }

local function step(dt)
	local now = os.clock()
	for model, st in pairs(chars) do
		if not model.Parent then
			chars[model] = nil
		else
			local hum = model:FindFirstChildOfClass("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hum and hrp then
				if st.motorCount < 12 and now - st.lastScan > 1 then
					scanMotors(st)
				end
				local pose, weight = pick(st, hum, hrp)
				if pose ~= st.pose then
					if pose then
						st.prevPose = st.pose
						st.switchT = now
						st.pose = pose
					end
				end
				st.w = Util.damp(st.w, weight, 16, dt)
				if pose == nil and st.w < 0.02 then
					st.pose = nil
					st.prevPose = nil
				end

				if st.isBot then
					local v = hrp.AssemblyLinearVelocity
					st.phase = st.phase + dt * Vector3.new(v.X, 0, v.Z).Magnitude * 0.55
				end

				local joints = {}
				if st.pose then
					for name in pairs(POSES[st.pose]) do
						joints[name] = true
					end
				end
				if st.prevPose and now - st.switchT < 0.1 then
					for name in pairs(POSES[st.prevPose]) do
						joints[name] = true
					end
				end
				if st.isBot then
					for _, name in ipairs(BOT_JOINTS) do
						joints[name] = true
					end
				end

				local a = Util.smoothstep((now - st.switchT) / 0.09)
				for name in pairs(joints) do
					local motor = st.motors[name]
					if motor then
						local base
						if st.isBot then
							base = locomotion(st, hrp, dt, name)
						else
							base = motor.Transform
						end
						local target = base
						if st.pose then
							target = POSES[st.pose][name] or base
							if st.prevPose and a < 1 then
								local from = POSES[st.prevPose][name] or base
								target = from:Lerp(target, a)
							end
						end
						motor.Transform = base:Lerp(target, st.w)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- triggers
------------------------------------------------------------------------------------------

local HIT_POSE = {
	Bump = "Bump",
	Set = "Set",
	Spike = "Swing",
	JumpServe = "Swing",
	Overhand = "Swing",
	Feint = "Tip",
	Block = "Block",
	Toss = "Toss",
}

function AnimationController.init(m)
	AnimationController.mods = m
	local function watchPlayer(plr)
		if plr.Character then
			register(plr.Character)
		end
		plr.CharacterAdded:Connect(register)
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		watchPlayer(plr)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	local function watchBots(folder)
		for _, b in ipairs(folder:GetChildren()) do
			register(b)
		end
		folder.ChildAdded:Connect(register)
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		watchBots(bots)
	else
		workspace.ChildAdded:Connect(function(c)
			if c.Name == "Bots" then
				watchBots(c)
			end
		end)
	end

	State.signals.Ball:Connect(function(snap, isEcho)
		if isEcho or snap.state ~= "Flight" or not snap.meta then
			return
		end
		local meta = snap.meta
		local pose = HIT_POSE[meta.hitType]
		if meta.hitType == "Free" then
			pose = meta.overhead and "Set" or "Bump"
		end
		if meta.fail or meta.shank then
			pose = "Knockback"
		end
		if pose and meta.id then
			local st = stateFor(meta.id)
			if st then
				st.stance = nil
			end
			AnimationController.playAction(meta.id, pose)
		end
	end)

	Net.get("ActionFX").OnClientEvent:Connect(function(entityId, kind, extra)
		State.signals.Action:Fire(entityId, kind, extra)
		if kind == "Slide" then
			AnimationController.setStance(entityId, "Dive", 0.9)
		elseif kind == "Block" then
			AnimationController.setStance(entityId, "Block", 1.0)
		elseif kind == "Stance" then
			AnimationController.setStance(entityId, "Stance", 0.8)
		elseif kind == "Charge" then
			AnimationController.setStance(entityId, "Charge", 2.0)
		elseif kind == "ChargeEnd" then
			AnimationController.setStance(entityId, nil)
		elseif kind == "Whiff" and type(extra) == "string" then
			AnimationController.playAction(entityId, extra)
		end
	end)

	State.signals.Announce:Connect(function(a)
		if a.kind == "Point" and a.winner then
			for _, e in ipairs(State.roster(a.winner)) do
				task.delay(0.15 + math.random() * 0.25, function()
					AnimationController.playAction(e.id, "Celebrate")
				end)
			end
		elseif a.kind == "Break" and a.id then
			AnimationController.playAction(a.id, "Burst")
		end
	end)

	RunService.Stepped:Connect(function(_, dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[SpikeRush] animation: " .. tostring(err))
		end
	end)
end

return AnimationController
