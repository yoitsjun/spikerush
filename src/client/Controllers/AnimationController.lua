-- Procedural R15 animation. Every character (players and bots) gets volleyball poses layered
-- over whatever the Animator is doing, by blending Motor6D.Transform in Stepped (which runs
-- after the Animator has posed the rig for the frame).
--
-- Layers, highest first: action (one-shot: bump, set, swing, tip, toss, gather, knockback,
-- celebrate) > stance (held: receive stance, slide, block, crouch, charge, toss ready) >
-- automatic (airborne windup, ready stance, serve hold). Everyone faces along the court, so
-- every pose reads in profile from the side camera.
--
-- Bots have no Animate script. Each client plays Roblox's default R15 idle, run, jump and fall
-- animations on them (Assets.BotAnimations) and falls back to a procedural run cycle until
-- those load, or if the slots are cleared.
--
-- Uploaded action animations (Assets.Animations) replace the procedural pose for that action:
-- your own character plays them (they replicate to everyone), every client plays them on bots,
-- and other players' tracks arrive by replication, so no client doubles them up.

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
	-- spike jump, modelled on The Spike: arms swing up on takeoff...
	Rise = {
		Waist = { 8, 0, 0 },
		Neck = { 12, 0, 0 },
		LeftShoulder = { 165, 0, -10 },
		RightShoulder = { 165, 0, 10 },
		LeftElbow = { 10, 0, 0 },
		RightElbow = { 10, 0, 0 },
		LeftHip = { -6, 0, -4 },
		RightHip = { -14, 0, 4 },
		LeftKnee = { -50, 0, 0 },
		RightKnee = { -70, 0, 0 },
		LeftAnkle = { -20, 0, 0 },
		RightAnkle = { -20, 0, 0 },
	},
	-- ...then the bow-draw at the top: back arched, hitting arm cocked behind the head, the other
	-- arm aiming at the ball, legs kicked back
	Cock = {
		Waist = { 22, 30, 0 },
		Neck = { 14, -18, 0 },
		LeftShoulder = { 150, 0, -14 },
		LeftElbow = { 12, 0, 0 },
		RightShoulder = { 175, -35, 48 },
		RightElbow = { 125, 0, 0 },
		RightWrist = { -20, 0, 0 },
		LeftHip = { -10, 0, -6 },
		RightHip = { -26, 0, 8 },
		LeftKnee = { -78, 0, 0 },
		RightKnee = { -100, 0, 0 },
		LeftAnkle = { -25, 0, 0 },
		RightAnkle = { -25, 0, 0 },
	},
	-- contact: the arm snaps straight up and forward
	SpikeReach = {
		Waist = { -10, -20, 0 },
		Neck = { 0, 10, 0 },
		LeftShoulder = { 90, 0, -20 },
		LeftElbow = { 40, 0, 0 },
		RightShoulder = { 160, 0, 15 },
		RightElbow = { 5, 0, 0 },
		RightWrist = { 10, 0, 0 },
		LeftHip = { -5, 0, -4 },
		RightHip = { -15, 0, 4 },
		LeftKnee = { -70, 0, 0 },
		RightKnee = { -85, 0, 0 },
	},
	-- the whip: arm through the ball, torso jackknifes, legs come forward
	SpikeSnap = {
		Root = { -12, 0, 0 },
		Waist = { -38, -28, 0 },
		Neck = { -10, 10, 0 },
		LeftShoulder = { 20, 0, -30 },
		LeftElbow = { 50, 0, 0 },
		RightShoulder = { 45, 0, 10 },
		RightElbow = { 10, 0, 0 },
		RightWrist = { -35, 0, 0 },
		LeftHip = { 48, 0, -6 },
		RightHip = { 40, 0, 6 },
		LeftKnee = { -45, 0, 0 },
		RightKnee = { -35, 0, 0 },
	},
	SpikeFollow = {
		Root = { -6, 0, 0 },
		Waist = { -24, -12, 0 },
		Neck = { 4, 0, 0 },
		LeftShoulder = { 30, 0, -20 },
		LeftElbow = { 40, 0, 0 },
		RightShoulder = { 10, 0, -10 },
		RightElbow = { 30, 0, 0 },
		LeftHip = { 40, 0, -6 },
		RightHip = { 34, 0, 6 },
		LeftKnee = { -70, 0, 0 },
		RightKnee = { -60, 0, 0 },
	},
	Air = {
		Neck = { 8, 0, 0 },
		LeftShoulder = { 60, 0, -20 },
		RightShoulder = { 60, 0, 20 },
		LeftElbow = { 30, 0, 0 },
		RightElbow = { 30, 0, 0 },
		LeftHip = { 10, 0, -4 },
		RightHip = { 10, 0, 4 },
		LeftKnee = { -35, 0, 0 },
		RightKnee = { -35, 0, 0 },
	},
	-- receive: the platform drives up through the ball with the legs
	BumpLift = {
		drop = 0.25,
		Waist = { -14, 0, 0 },
		Neck = { 8, 0, 0 },
		LeftHip = { 22, 0, -6 },
		RightHip = { 22, 0, 6 },
		LeftKnee = { -30, 0, 0 },
		RightKnee = { -30, 0, 0 },
		LeftAnkle = { 8, 0, 0 },
		RightAnkle = { 8, 0, 0 },
		LeftShoulder = { 86, 0, 16 },
		RightShoulder = { 86, 0, -16 },
		LeftElbow = { 0, 0, 0 },
		RightElbow = { 0, 0, 0 },
		LeftWrist = { -10, 0, 0 },
		RightWrist = { -10, 0, 0 },
	},
	-- set: catch at the forehead, then push up onto the toes
	SetCatch = {
		drop = 0.35,
		Waist = { 6, 0, 0 },
		Neck = { 26, 0, 0 },
		LeftHip = { 24, 0, -4 },
		RightHip = { 24, 0, 4 },
		LeftKnee = { -40, 0, 0 },
		RightKnee = { -40, 0, 0 },
		LeftAnkle = { 10, 0, 0 },
		RightAnkle = { 10, 0, 0 },
		LeftShoulder = { 140, 0, -24 },
		RightShoulder = { 140, 0, 24 },
		LeftElbow = { 95, 0, 0 },
		RightElbow = { 95, 0, 0 },
		LeftWrist = { 45, 0, 0 },
		RightWrist = { 45, 0, 0 },
	},
	SetPush = {
		drop = -0.12,
		Waist = { 2, 0, 0 },
		Neck = { 22, 0, 0 },
		LeftHip = { 4, 0, -3 },
		RightHip = { 4, 0, 3 },
		LeftKnee = { -6, 0, 0 },
		RightKnee = { -6, 0, 0 },
		LeftAnkle = { -18, 0, 0 },
		RightAnkle = { -18, 0, 0 },
		LeftShoulder = { 172, 0, -10 },
		RightShoulder = { 172, 0, 10 },
		LeftElbow = { 8, 0, 0 },
		RightElbow = { 8, 0, 0 },
		LeftWrist = { 10, 0, 0 },
		RightWrist = { 10, 0, 0 },
	},
	SetPushBack = {
		drop = -0.1,
		Waist = { 22, 0, 0 },
		Neck = { 34, 0, 0 },
		LeftHip = { -4, 0, -3 },
		RightHip = { -4, 0, 3 },
		LeftKnee = { -10, 0, 0 },
		RightKnee = { -10, 0, 0 },
		LeftAnkle = { -18, 0, 0 },
		RightAnkle = { -18, 0, 0 },
		LeftShoulder = { 185, 0, -8 },
		RightShoulder = { 185, 0, 8 },
		LeftElbow = { 6, 0, 0 },
		RightElbow = { 6, 0, 0 },
		LeftWrist = { 20, 0, 0 },
		RightWrist = { 20, 0, 0 },
	},
	LandCrouch = {
		drop = 0.7,
		Waist = { -20, 0, 0 },
		Neck = { 12, 0, 0 },
		LeftHip = { 46, 0, -6 },
		RightHip = { 46, 0, 6 },
		LeftKnee = { -80, 0, 0 },
		RightKnee = { -80, 0, 0 },
		LeftAnkle = { 24, 0, 0 },
		RightAnkle = { 24, 0, 0 },
		LeftShoulder = { 30, 0, -14 },
		RightShoulder = { 30, 0, 14 },
		LeftElbow = { 30, 0, 0 },
		RightElbow = { 30, 0, 0 },
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

-- Keyframed clips: a pose per key, eased between keys. Joints missing from a key hold the
-- nearest key's value, so every key is a full pose for the joints the clip touches.
local EASE = {
	out = function(a)
		return 1 - (1 - a) * (1 - a)
	end,
	inq = function(a)
		return a * a
	end,
	smooth = function(a)
		return a * a * (3 - 2 * a)
	end,
}

local CLIP_DEFS = {
	-- spike contact: reach, whip through, follow through into the fall
	Swing = {
		dur = 0.5,
		keys = { { 0, "SpikeReach" }, { 0.05, "SpikeSnap", "out" }, { 0.24, "SpikeFollow", "smooth" } },
	},
	Bump = {
		dur = 0.45,
		keys = { { 0, "Bump" }, { 0.09, "BumpLift", "out" }, { 0.45, "BumpLift" } },
	},
	Set = {
		dur = 0.42,
		keys = { { 0, "SetCatch" }, { 0.09, "SetPush", "out" }, { 0.42, "SetPush" } },
	},
	SetBack = {
		dur = 0.45,
		keys = { { 0, "SetCatch" }, { 0.1, "SetPushBack", "out" }, { 0.45, "SetPushBack" } },
	},
	Land = {
		dur = 0.34,
		weight = 0.9,
		keys = { { 0, "LandCrouch" }, { 0.12, "LandCrouch" }, { 0.34, "Ready", "smooth" } },
	},
}

local CLIPS = {}
for name, def in pairs(CLIP_DEFS) do
	local union = {}
	for _, k in ipairs(def.keys) do
		for joint in pairs(POSES[k[2]]) do
			union[joint] = true
		end
	end
	local keys = {}
	for i, k in ipairs(def.keys) do
		local joints = {}
		for joint in pairs(union) do
			local cf = POSES[k[2]][joint]
			local j = 1
			while not cf and j < #def.keys do
				-- nearest neighbour key that has this joint (earlier first)
				local before = def.keys[i - j]
				local after = def.keys[i + j]
				cf = (before and POSES[before[2]][joint]) or (after and POSES[after[2]][joint])
				j = j + 1
			end
			joints[joint] = cf or CFrame.identity
		end
		keys[i] = { t = k[1], joints = joints, ease = EASE[k[3] or "smooth"] }
	end
	CLIPS[name] = { dur = def.dur, weight = def.weight or 1, keys = keys, joints = union }
end

-- Sample a clip at time t into `out` (a reused table).
local function sampleClip(clip, t, out)
	local keys = clip.keys
	local i = 1
	while keys[i + 1] and keys[i + 1].t <= t do
		i = i + 1
	end
	local k0, k1 = keys[i], keys[i + 1]
	if not k1 then
		for joint, cf in pairs(k0.joints) do
			out[joint] = cf
		end
		return out
	end
	local a = k1.ease(math.clamp((t - k0.t) / (k1.t - k0.t), 0, 1))
	for joint, cf in pairs(k0.joints) do
		out[joint] = cf:Lerp(k1.joints[joint], a)
	end
	return out
end

-- pose -> Assets.Animations slot
local SLOT = {
	Bump = "Bump",
	Set = "Set",
	Swing = "Swing",
	Tip = "Tip",
	Block = "Block",
	Dive = "Slide",
	Charge = "Charge",
	Toss = "Toss",
	Stance = "Stance",
	Knockback = "Knockback",
	Celebrate = "Celebrate",
	SetBack = "Set",
}

local function slotId(pose)
	local slot = SLOT[pose]
	return slot and Assets.id(Assets.Animations[slot]) or nil
end

------------------------------------------------------------------------------------------
-- character registry
------------------------------------------------------------------------------------------

-- R15 joints by the body part they move. New experiences spawn avatars with AnimationConstraint
-- joints instead of Motor6Ds (Roblox's Avatar Joint Upgrade); both expose Part1 and a Transform
-- that is written in PreSimulation, so joints are found by the part they drive, whatever they
-- are called.
local JOINT_FOR_PART = {
	LowerTorso = "Root",
	UpperTorso = "Waist",
	Head = "Neck",
	LeftUpperArm = "LeftShoulder",
	LeftLowerArm = "LeftElbow",
	LeftHand = "LeftWrist",
	RightUpperArm = "RightShoulder",
	RightLowerArm = "RightElbow",
	RightHand = "RightWrist",
	LeftUpperLeg = "LeftHip",
	LeftLowerLeg = "LeftKnee",
	LeftFoot = "LeftAnkle",
	RightUpperLeg = "RightHip",
	RightLowerLeg = "RightKnee",
	RightFoot = "RightAnkle",
}

local function scanMotors(st)
	local motors, n = {}, 0
	for _, d in ipairs(st.model:GetDescendants()) do
		if d:IsA("AnimationConstraint") or d:IsA("Motor6D") then
			local ok, part1 = pcall(function()
				return d.Part1
			end)
			if (not ok or not part1) and d:IsA("AnimationConstraint") and d.Attachment1 then
				part1 = d.Attachment1.Parent
			end
			local name = (part1 and JOINT_FOR_PART[part1.Name]) or d.Name
			-- an AnimationConstraint wins over a leftover Motor6D for the same limb
			if not motors[name] or d:IsA("AnimationConstraint") then
				if not motors[name] then
					n = n + 1
				end
				motors[name] = d
			end
		end
	end
	st.motors = motors
	st.motorCount = n
	st.lastScan = os.clock()
	local hum = st.model:FindFirstChildOfClass("Humanoid")
	st.animator = hum and hum:FindFirstChildOfClass("Animator")
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
		joints = {},
		clipBuf = {},
		prevBuf = {},
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
-- animation tracks (uploaded actions, bot locomotion)
------------------------------------------------------------------------------------------

local function animatorOf(model, create)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator and create then
		-- bots are server-owned: a client-side Animator plays locally and never replicates
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

-- Cached per Animator and key; a failed load is remembered so it isn't retried every frame.
local function loadTrack(animator, key, id, priority)
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
	local track = set[key]
	if track == nil then
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, t = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		track = ok and t or false
		if track then
			track.Priority = priority
		end
		set[key] = track
	end
	return track or nil
end

-- The uploaded track for a pose on this character, if this client is the one that plays it
-- (your own character, or any bot).
local function uploadedTrack(st, pose, key)
	local id = slotId(pose)
	if not id or not st then
		return nil
	end
	local mine = st.model == player.Character
	if not mine and not st.isBot then
		return nil
	end
	local animator = animatorOf(st.model, st.isBot)
	if not animator then
		return nil
	end
	return loadTrack(animator, key .. pose, id, Enum.AnimationPriority.Action2)
end

-- Another player's uploaded action arrives by replication; don't pose over it.
local function replicatedElsewhere(st, pose)
	return st ~= nil and not st.isBot and st.model ~= player.Character and slotId(pose) ~= nil
end

local function stopStanceTrack(st)
	if st and st.stanceTrack then
		st.stanceTrack:Stop(0.12)
		st.stanceTrack = nil
	end
end

------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------

-- Clips that belong together, so a second trigger in the same instant (the hit prediction and
-- the input handler both call this) doesn't restart or replace the first.
local FAMILY = { Set = "Set", SetBack = "Set", Swing = "Swing", Tip = "Swing", Bump = "Bump" }

function AnimationController.playAction(entityId, pose)
	if not POSES[pose] and not CLIPS[pose] then
		return
	end
	local st = stateFor(entityId)
	if not st then
		return
	end
	local now = os.clock()
	local cur = st.action
	if cur and now - cur.t0 < 0.06 and FAMILY[pose] and FAMILY[pose] == FAMILY[cur.pose] then
		return
	end
	if pose == "Swing" or pose == "Tip" then
		st.swung = true -- the rest of this jump falls in the follow-through, not the bow-draw
	end
	local track = uploadedTrack(st, pose, "A_")
	if track then
		stopStanceTrack(st)
		track.Looped = false
		track:Play(0.05)
		return
	end
	if replicatedElsewhere(st, pose) then
		return
	end
	local clip = CLIPS[pose]
	st.action = { pose = pose, clip = clip, t0 = now, dur = clip and clip.dur or DURATION[pose] or 0.3 }
end

-- A character left the ground. kind: "Spike" / "Serve" (run-up attack), "Block" or "Jump".
function AnimationController.jumped(entityId, kind)
	local st = stateFor(entityId)
	if st then
		st.jumpKind = kind
		st.swung = false
	end
end

function AnimationController.setStance(entityId, pose, duration)
	local st = stateFor(entityId)
	if not st then
		return
	end
	stopStanceTrack(st)
	if pose == nil then
		st.stance = nil
		return
	end
	local untilT = os.clock() + (duration or 1)
	local track = uploadedTrack(st, pose, "S_")
	if track then
		st.stance = nil
		track.Looped = true
		track:Play(0.08)
		st.stanceTrack = track
		st.stanceTrackUntil = untilT
		return
	end
	if replicatedElsewhere(st, pose) then
		st.stance = nil
		return
	end
	st.stance = { pose = pose, untilT = untilT }
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

-- What the character should look like this frame: a key that changes when the pose changes, the
-- target joints (a pose table or a sampled clip) and a weight.
local function pick(st, hum, hrp, now)
	local groundY = hum.HipHeight + hrp.Size.Y / 2
	local airborne = hrp.Position.Y > groundY + 0.9
	if airborne then
		st.wasAirborne = true
	elseif st.wasAirborne then
		-- just landed: a short crouch unless something else is playing
		st.wasAirborne = false
		st.jumpKind = nil
		st.swung = false
		local busy = (st.action and now < st.action.t0 + st.action.dur) or (st.stance and now < st.stance.untilT)
		if not busy then
			st.action = { pose = "Land", clip = CLIPS.Land, t0 = now, dur = CLIPS.Land.dur }
		end
	end
	local action = st.action
	if action and now < action.t0 + action.dur then
		if action.clip then
			return "clip" .. action.pose .. action.t0, sampleClip(action.clip, now - action.t0, st.clipBuf), action.clip.weight
		end
		return action.pose, POSES[action.pose], 1
	end
	if st.stance and now < st.stance.untilT then
		return st.stance.pose, POSES[st.stance.pose], 1
	end
	if airborne then
		if st.swung then
			return "SpikeFollow", POSES.SpikeFollow, 0.95
		end
		if st.jumpKind == "Spike" or st.jumpKind == "Serve" then
			if hrp.AssemblyLinearVelocity.Y > 5 then
				return "Rise", POSES.Rise, 1
			end
			return "Cock", POSES.Cock, 1
		end
		return "Air", POSES.Air, 0.8
	end
	local phase = State.phase()
	if holdsBall(st) then
		return "Hold", POSES.Hold, 0.9
	end
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if (phase == "Rally" or phase == "Serving" or phase == "PreServe") and speed < 3 then
		return "Ready", POSES.Ready, 0.75
	end
	return nil, nil, 0
end

-- Bot locomotion from Roblox's default animations. Returns true while the tracks drive the rig.
local LOCO = { "Idle", "Run", "Jump", "Fall" }

local function botLocomotion(st, hum, hrp)
	if st.loco == nil then
		st.loco = false
		local animator = animatorOf(st.model, true)
		local set, any = {}, false
		if animator then
			for _, key in ipairs(LOCO) do
				local id = Assets.id(Assets.BotAnimations and Assets.BotAnimations[key])
				if id then
					local priority = key == "Idle" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement
					local track = loadTrack(animator, "L_" .. key, id, priority)
					if track then
						track.Looped = key ~= "Jump"
						set[key] = track
						any = true
					end
				end
			end
		end
		if any then
			st.loco = { tracks = set, current = nil, since = os.clock() }
		end
	end
	local loco = st.loco
	if not loco then
		return false
	end
	if not loco.ready then
		for _, track in pairs(loco.tracks) do
			if track.Length > 0 then
				loco.ready = true
			end
		end
		if not loco.ready then
			if os.clock() - loco.since > 8 then
				-- never loaded (moderated or wrong id): keep the procedural cycle for good
				st.loco = false
			end
			return false
		end
	end
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local groundY = hum.HipHeight + hrp.Size.Y / 2
	local want = "Idle"
	if hrp.Position.Y > groundY + 0.6 then
		want = v.Y > 2 and "Jump" or "Fall"
	elseif speed > 1.5 then
		want = "Run"
	end
	if not loco.tracks[want] then
		want = loco.tracks.Idle and "Idle" or nil
	end
	if want ~= loco.current then
		local old = loco.current and loco.tracks[loco.current]
		if old then
			old:Stop(0.15)
		end
		local new = want and loco.tracks[want]
		if new then
			new:Play(0.15)
		end
		loco.current = want
	end
	if want == "Run" then
		loco.tracks.Run:AdjustSpeed(math.clamp(speed / 16, 0.6, 1.6))
	end
	return true
end

-- Procedural run cycle for bots whose locomotion tracks aren't available.
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

local function copyInto(dst, src)
	for k in pairs(dst) do
		dst[k] = nil
	end
	for k, v in pairs(src) do
		dst[k] = v
	end
	return dst
end

local function stepCharacter(st, hum, hrp, now, dt)
	if st.motorCount < 12 and now - st.lastScan > 1 then
		scanMotors(st)
	end
	if st.motorCount > 0 and not st.motors.Waist and now - st.lastScan > 1 then
		scanMotors(st) -- the rig was rebuilt (joints replaced): find them again
	end
	if st.stanceTrack and now > st.stanceTrackUntil then
		stopStanceTrack(st)
	end
	local key, target, weight = pick(st, hum, hrp, now)
	if key ~= st.key and key then
		-- cross-fade from whatever was showing (a sampled clip is copied, its buffer is reused)
		if st.target then
			st.prevTarget = copyInto(st.prevBuf, st.target)
		else
			st.prevTarget = nil
		end
		st.switchT = now
		st.key = key
	end
	if target then
		st.target = target
	end
	st.w = Util.damp(st.w, weight, 16, dt)
	if key == nil and st.w < 0.02 then
		st.key = nil
		st.target = nil
		st.prevTarget = nil
	end

	-- bots: real locomotion tracks when they're loaded, the procedural cycle otherwise
	local procedural = false
	if st.isBot then
		procedural = not botLocomotion(st, hum, hrp)
		if procedural then
			local v = hrp.AssemblyLinearVelocity
			st.phase = st.phase + dt * Vector3.new(v.X, 0, v.Z).Magnitude * 0.55
		end
	end
	local pose = st.target
	if not pose and not procedural then
		return
	end
	-- an Animator that skipped evaluation this frame reuses last frame's pose: layering on top
	-- of it again would compound (Animator.EvaluationThrottled)
	local animator = st.animator
	if animator and animator.Parent and not procedural then
		local ok, throttled = pcall(function()
			return animator.EvaluationThrottled
		end)
		if ok and throttled then
			return
		end
	end

	-- the joints to write this frame (a reused set, so no table per character per frame)
	local joints = st.joints
	for name in pairs(joints) do
		joints[name] = nil
	end
	if pose then
		for name in pairs(pose) do
			joints[name] = true
		end
	end
	local prev = st.prevTarget
	if prev and now - st.switchT < 0.1 then
		for name in pairs(prev) do
			joints[name] = true
		end
	else
		prev = nil
	end
	if procedural then
		for _, name in ipairs(BOT_JOINTS) do
			joints[name] = true
		end
	end

	local a = Util.smoothstep((now - st.switchT) / 0.09)
	for name in pairs(joints) do
		local motor = st.motors[name]
		if motor and motor.Parent then
			local base
			if procedural then
				base = locomotion(st, hrp, dt, name)
			else
				base = motor.Transform
			end
			local goal = base
			if pose then
				goal = pose[name] or base
				if prev and a < 1 then
					goal = (prev[name] or base):Lerp(goal, a)
				end
			end
			motor.Transform = base:Lerp(goal, st.w)
		end
	end
end

local function step(dt)
	local now = os.clock()
	for model, st in pairs(chars) do
		if not model.Parent then
			chars[model] = nil
		else
			local hum = model:FindFirstChildOfClass("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hum and hrp then
				stepCharacter(st, hum, hrp, now, dt)
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
		elseif meta.hitType == "Set" and meta.underhand then
			pose = "Bump"
		elseif meta.hitType == "Set" and meta.setType == "Back" then
			pose = "SetBack"
		end
		if meta.fail or meta.shank or (meta.knock and meta.knock >= 0.35) then
			pose = "Knockback" -- a heavy ball staggers the receiver
		end
		if pose and meta.id then
			local st = stateFor(meta.id)
			if st then
				st.stance = nil
				stopStanceTrack(st)
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
		elseif kind == "Jump" then
			AnimationController.jumped(entityId, extra)
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

	-- PreSimulation runs after the Animator has written this frame's joint transforms, and is the
	-- last Luau event before they are applied to the parts
	RunService.PreSimulation:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[SpikeRush] animation: " .. tostring(err))
		end
	end)
end

return AnimationController
