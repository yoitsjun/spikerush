-- Local character movement for the side view, on top of the Humanoid:
--  * lane lock: you only ever move along the court (left/right on screen)
--  * run-up jump: a short dash (longer with a higher Jump stat) then takeoff, with a boom
--  * block jump: hold to charge a higher jump
--  * slide: a receive dive along the court
--  * air control: drift in the air to line up with the ball (that sets your spike angle)
--  * anime hang near the top of every jump; Azure Dragon hovers while charging
-- Jump height and run speed come from your character's build (set by the server).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local State = require(script.Parent.State)

local MovementController = {}
local mods

local P = Config.Player
local AZURE = Config.Abilities.Azure
local player = Players.LocalPlayer
local char, hum, hrp, hangForce
local controls = nil
local slide = nil
local lastSlideAt = -10
local gather = nil
local charging = false
local padAxis = 0
local facing = 1
local jumpKind = nil
local lastForce = nil

local function getControls()
	if controls then
		return controls
	end
	local ok, result = pcall(function()
		local module = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		return module:GetControls()
	end)
	if ok then
		controls = result
	end
	return controls
end

local function baseWalk()
	return (char and char:GetAttribute("BaseWalkSpeed")) or State.myStats().WalkSpeed
end

local function baseJump()
	return (char and char:GetAttribute("BaseJumpHeight")) or (hum and hum.JumpHeight) or 6
end

local function onCharacter(c)
	char = c
	hum = c:WaitForChild("Humanoid")
	hrp = c:WaitForChild("HumanoidRootPart")
	slide, gather, charging = nil, nil, false
	hum.AutoRotate = false
	-- state machine tweaks have to run on the client that owns the humanoid
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)

	local att = Instance.new("Attachment")
	att.Name = "SpikeRushHang"
	att.Parent = hrp
	hangForce = Instance.new("VectorForce")
	hangForce.Name = "SpikeRushHang"
	hangForce.Attachment0 = att
	hangForce.RelativeTo = Enum.ActuatorRelativeTo.World
	hangForce.ApplyAtCenterOfMass = true
	hangForce.Force = Vector3.zero
	hangForce.Parent = hrp
	lastForce = 0

	hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			local kind = jumpKind or "Jump"
			jumpKind = nil
			mods.AnimationController.jumped(State.myId, kind)
			mods.VFXController.boom(State.myId, kind)
			Net.get("ActionFX"):FireServer("Jump", kind)
		elseif new == Enum.HumanoidStateType.Landed then
			hum.JumpHeight = baseJump()
		end
	end)
end

function MovementController.isSliding()
	return slide ~= nil and os.clock() - slide.t0 < P.SlideTime
end

function MovementController.isRecovering()
	return slide ~= nil
end

function MovementController.isGathering()
	return gather ~= nil
end

function MovementController.airborne()
	return hum ~= nil and hum.FloorMaterial == Enum.Material.Air
end

function MovementController.root()
	return hrp
end

function MovementController.facing()
	return facing
end

-- Input along the court: -1..1 (screen right is +z).
function MovementController.axis()
	local axis = mods.InputController.keyboardAxis()
	if axis == 0 and math.abs(padAxis) > 0.2 then
		axis = padAxis
	end
	if axis == 0 and State.isMobile then
		local c = getControls()
		if c then
			local ok, mv = pcall(function()
				return c:GetMoveVector()
			end)
			if ok and mv and math.abs(mv.X) > 0.15 then
				axis = mv.X
			end
		end
	end
	return math.clamp(axis, -1, 1)
end

-- Rewriting the root CFrame every frame fights the humanoid's physics (ground stutter), so the
-- root is only turned when it isn't already squared up along the court.
local function face(dirZ)
	if not hrp or math.abs(dirZ) < 1e-3 then
		return
	end
	facing = dirZ > 0 and 1 or -1
	if hrp.CFrame.LookVector.Z * facing > 0.999 then
		return
	end
	local pos = hrp.Position
	hrp.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, facing))
end

function MovementController.faceNet()
	if State.isPlaying then
		face(-State.mySide)
	end
end

function MovementController.canJump()
	return hum ~= nil and not slide and not gather and hum.FloorMaterial ~= Enum.Material.Air
end

-- Run-up jump: dash in the held direction (or jump in place), then take off.
function MovementController.approach(kind)
	if not MovementController.canJump() then
		return false
	end
	local dir = MovementController.axis()
	if math.abs(dir) < 0.3 then
		dir = 0
	else
		dir = dir > 0 and 1 or -1
	end
	gather = { t0 = os.clock(), dir = dir, kind = kind or "Spike" }
	mods.AnimationController.pose(State.myId, "Gather")
	return true
end

-- Charged block jump: fraction 0..1 of the hold.
function MovementController.blockJump(fraction)
	if not MovementController.canJump() then
		return false
	end
	local k = P.BlockMinHeight + (1 - P.BlockMinHeight) * math.clamp(fraction, 0, 1)
	hum.JumpHeight = baseJump() * k
	jumpKind = "Block"
	hum.Jump = true
	return true
end

function MovementController.jump(kind)
	if not MovementController.canJump() then
		return false
	end
	jumpKind = kind
	hum.JumpHeight = baseJump()
	hum.Jump = true
	return true
end

function MovementController.slide(dirZ)
	if not hum or not hrp or slide or gather or os.clock() - lastSlideAt < P.SlideCooldown then
		return false
	end
	if hum.FloorMaterial == Enum.Material.Air then
		return false
	end
	if math.abs(dirZ or 0) < 0.3 then
		dirZ = facing
	end
	local dir = dirZ > 0 and 1 or -1
	lastSlideAt = os.clock()
	slide = { dir = dir, t0 = os.clock() }
	face(dir)
	hum.JumpHeight = 0
	return true
end

-- Azure Dragon: hover while gathering energy.
function MovementController.setCharging(on)
	charging = on == true
end

local function endSlide()
	slide = nil
	if hum then
		hum.WalkSpeed = baseWalk()
		hum.JumpHeight = baseJump()
	end
end

local function lockLane()
	local lane = State.myLane()
	local pos = hrp.Position
	if math.abs(pos.X - lane) > 0.03 then
		hrp.CFrame = hrp.CFrame + Vector3.new(lane - pos.X, 0, 0)
	end
	local v = hrp.AssemblyLinearVelocity
	if math.abs(v.X) > 0.01 then
		hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, v.Z)
	end
end

-- Physics step: lane, hang, hover.
local function physicsStep()
	if not hum or not hrp or not hrp.Parent or hum.Health <= 0 then
		return
	end
	lockLane()
	local vy = hrp.AssemblyLinearVelocity.Y
	local airborne = hum.FloorMaterial == Enum.Material.Air
	local cancel = 0
	if airborne and not slide then
		if charging and vy <= 0 then
			cancel = AZURE.GravityCancel
		elseif math.abs(vy) < P.HangVelocityWindow then
			cancel = P.HangGravityCancel
		end
	end
	local force = hrp.AssemblyMass * workspace.Gravity * cancel
	if force ~= lastForce then
		lastForce = force
		hangForce.Force = Vector3.new(0, force, 0)
	end
end

-- Render step (after the default control script): movement along the court only.
local function moveStep()
	if not hum or not hrp or not hrp.Parent or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	local airborne = hum.FloorMaterial == Enum.Material.Air
	local stats = State.myStats()

	if slide then
		local e = now - slide.t0
		if e < P.SlideTime then
			hum.WalkSpeed = P.SlideSpeed * (1 - 0.5 * e / P.SlideTime)
			hum:Move(Vector3.new(0, 0, slide.dir), false)
		elseif e < P.SlideTime + P.SlideRecover then
			hum.WalkSpeed = 0
			hum:Move(Vector3.zero, false)
		else
			endSlide()
		end
		return
	end

	if gather then
		local e = now - gather.t0
		if gather.dir ~= 0 then
			hum.WalkSpeed = baseWalk() * P.ApproachDash * stats.Approach
			hum:Move(Vector3.new(0, 0, gather.dir), false)
			face(gather.dir)
		else
			hum:Move(Vector3.zero, false)
		end
		if e >= P.ApproachGather then
			local dir = gather.dir
			jumpKind = gather.kind
			gather = nil
			hum.WalkSpeed = baseWalk() * P.AirControl
			hum.JumpHeight = baseJump()
			hum.Jump = true
			if dir ~= 0 then
				local v = hrp.AssemblyLinearVelocity
				hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, dir * P.ApproachBoost * stats.Approach)
			end
		end
		return
	end

	local axis = MovementController.axis()
	if airborne then
		local air = P.AirControl
		if State.myAbility() == "Azure" then
			air = air * AZURE.AirSpeedBonus
		end
		hum.WalkSpeed = baseWalk() * air
	else
		hum.WalkSpeed = baseWalk()
	end
	hum:Move(Vector3.new(0, 0, axis), false)
	if math.abs(axis) > 0.2 and not airborne then
		face(axis)
	elseif not airborne and State.isPlaying and State.phase() ~= "Intermission" then
		-- standing still: square up to the net so hits read correctly
		face(-State.mySide)
	end
end

function MovementController.init(m)
	mods = m
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			padAxis = input.Position.X
		end
	end)
	RunService.Stepped:Connect(function()
		local ok, err = pcall(physicsStep)
		if not ok then
			warn("[SpikeRush] movement: " .. tostring(err))
		end
	end)
	RunService:BindToRenderStep("SpikeRushMove", Enum.RenderPriority.Input.Value + 1, function()
		local ok, err = pcall(moveStep)
		if not ok then
			warn("[SpikeRush] movement: " .. tostring(err))
		end
	end)
end

return MovementController
