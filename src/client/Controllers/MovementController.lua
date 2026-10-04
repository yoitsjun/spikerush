-- Local character movement for the side view, on top of the Humanoid:
--  * lane lock: you only ever move along the court (left/right on screen)
--  * run-up jump: a short dash (longer with a higher Jump stat) then takeoff, with a boom; with
--    the double approach setting the first press squeaks and readies it, the second takes off
--  * block jump: hold to charge a higher jump
--  * slide: a receive dive along the court
--  * air control: drift in the air to line up with the ball (that sets your spike angle)
--  * anime hang near the top of every jump; Azure Dragon hovers while charging
--  * Feral Leap: faster while the charge is held; the leap carries him along the court all flight
-- Jump height and run speed come from your character's build (set by the server).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cups = require(Shared.Cups)
local Net = require(Shared.Net)
local State = require(script.Parent.State)

local MovementController = {}
local mods

local P = Config.Player
local AZURE = Config.Abilities.Azure
local FERAL = Config.Abilities.Feral
local player = Players.LocalPlayer
local char, hum, hrp, hangForce
local controls = nil
local slide = nil
local lastSlideAt = -10
local gather = nil
local run = nil -- the double approach, readied by its first press: { t0, kind }
local charging = false
local padAxis = 0
local facing = 1
local jumpKind = nil
local lastForce = nil
local knock = nil -- { t0, speed } after a heavy receive
local prowlT0 = nil -- Feral Leap: when the charge started (he runs faster as it fills)
local leaping = nil -- { dir, carry, t0 } from a Feral Leap's takeoff until he lands
-- A jump asked for from an input event. The default control script rewrites Humanoid.Jump every
-- render step (from its own keys), so a jump set straight from an input handler is wiped before
-- physics sees it; moveStep applies it after the control script instead.
local queued = nil -- { height, kind }
-- A jump the humanoid was told to take, until it's off the floor: now and then it ignores
-- Humanoid.Jump (the owner: "i dash forward a tad and my arms swing back but i do not jump", and
-- Dante's leap "cancelled"), so if it hasn't left within TAKEOFF_NUDGE it's made to.
local takeoff = nil -- { t0, vz: the run-up's push along the court, if any }
local TAKEOFF_NUDGE, TAKEOFF_GIVEUP = 0.03, 0.25

-- Roblox's control module, if the place has one in PlayerScripts. This place doesn't, and this
-- must never wait for it: a WaitForChild here froze every touch action that asked for the stick
-- (Slide, the run-up, the serve toss) and piled up a stuck thread every frame.
local function getControls()
	if controls then
		return controls
	end
	local ps = player:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if not pm then
		return nil
	end
	local ok, result = pcall(function()
		return require(pm):GetControls()
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
	slide, gather, run, charging, queued, takeoff = nil, nil, nil, false, nil, nil
	prowlT0, leaping = nil, nil
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

-- A double approach readied (the next Spike press takes off).
function MovementController.isRunning()
	return run ~= nil
end

-- In the air from the very first frame of a jump: FloorMaterial still reports the floor for a
-- few frames after takeoff, so the humanoid's own Jumping/Freefall state counts too.
local AIR_STATES = { [Enum.HumanoidStateType.Jumping] = true, [Enum.HumanoidStateType.Freefall] = true }

-- The floor check blinks to "air" for a frame now and then on the flat floor, and one blink used to
-- refuse a jump or call off Feral Leap's whole charge (the owner: "when i serve with dante i
-- sometimes get caught on the ground and i dont jump"; "sometimes on normal jumps too his leap is
-- cancelled"). So the floor holds for FLOOR_GRACE after the last frame on it, unless he's taking off:
-- the Jumping state, or moving up or down.
local FLOOR_GRACE = 0.15
local lastFloorAt = -10

local function inAir()
	if not hum then
		return false
	end
	local vy = hrp and hrp.AssemblyLinearVelocity.Y or 0
	-- a falling state while standing still on the floor (pressed on the net's barrier, or landed
	-- on an edge) isn't the air: without this, jumps were refused until the state cleared
	local air = hum.FloorMaterial == Enum.Material.Air or (AIR_STATES[hum:GetState()] == true and math.abs(vy) >= 0.5)
	if not air then
		lastFloorAt = os.clock()
		return false
	end
	if os.clock() - lastFloorAt < FLOOR_GRACE and hum:GetState() ~= Enum.HumanoidStateType.Jumping and math.abs(vy) < 2 then
		return false -- a blink
	end
	return true
end

function MovementController.airborne()
	return inAir()
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
		-- the touch controls' own thumbstick, else a control module's
		local stick = mods.MobileControls and mods.MobileControls.stickX() or 0
		local c = math.abs(stick) <= 0.15 and getControls() or nil
		if math.abs(stick) > 0.15 then
			axis = stick
		elseif c then
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
	return hum ~= nil and not slide and not gather and not run and not queued and not inAir()
end

local function heldDir()
	local dir = MovementController.axis()
	if math.abs(dir) < 0.3 then
		return 0
	end
	return dir > 0 and 1 or -1
end

-- A readied double approach's second press: the usual gather and takeoff (a dash the way you
-- hold, or straight up).
local function plant()
	gather = { t0 = os.clock(), dir = heldDir(), kind = run.kind }
	run = nil
	mods.AnimationController.pose(State.myId, "Gather")
end

-- Run-up jump: dash in the held direction (or jump in place), then take off. With the double
-- approach setting the first press only readies it, with a floor squeak (you don't move), and the
-- second takes off.
function MovementController.approach(kind)
	if run then
		plant()
		return true
	end
	if not MovementController.canJump() then
		return false
	end
	if State.settings.doubleApproach then
		run = { t0 = os.clock(), kind = kind or "Spike" }
		mods.AudioController.play("Squeak", { pos = hrp.Position })
		Net.get("ActionFX"):FireServer("Approach") -- the others hear the squeak
		return true
	end
	gather = { t0 = os.clock(), dir = heldDir(), kind = kind or "Spike" }
	mods.AnimationController.pose(State.myId, "Gather")
	return true
end

-- Feral Leap: while the charge is held (t0: when it started, nil when it ends) he runs faster.
function MovementController.setProwl(t0)
	prowlT0 = t0
end

-- In the air on a Feral Leap (its carry takes him along the court until he lands).
function MovementController.leaping()
	return leaping ~= nil
end

-- Feral Leap: the gather and takeoff of a run-up jump, the way you hold (at the net when you
-- hold nothing), and a carry for the whole flight from the charge (gauge 0..1). kind: "Spike",
-- or "Serve" into his toss. aim ({ dir, carry }, a jump serve after its own toss): no run-in,
-- just that carry. Returns the direction along z, or nil when you can't jump now.
function MovementController.leap(gauge, kind, aim)
	if not MovementController.canJump() then
		return nil
	end
	if aim then
		gather = { t0 = os.clock(), dir = 0, kind = kind or "Spike", carry = aim.carry, leapDir = aim.dir }
		mods.AnimationController.pose(State.myId, "Gather")
		return aim.dir
	end
	local dir = heldDir()
	if dir == 0 then
		dir = State.isPlaying and -State.mySide or facing
	end
	gather = { t0 = os.clock(), dir = dir, kind = kind or "Spike", carry = FERAL.CarryMax * math.clamp(gauge or 0, 0, 1) }
	mods.AnimationController.pose(State.myId, "Gather")
	return dir
end

-- Charged block jump: fraction 0..1 of the hold.
function MovementController.blockJump(fraction)
	if not MovementController.canJump() then
		return false
	end
	local k = (P.BlockMinHeight + (1 - P.BlockMinHeight) * math.clamp(fraction, 0, 1)) * Cups.factor(ReplicatedStorage:GetAttribute("CupMods"), "BlockJump")
	queued = { height = baseJump() * k, kind = "Block" }
	return true
end

function MovementController.jump(kind)
	if not MovementController.canJump() then
		return false
	end
	queued = { height = baseJump(), kind = kind }
	return true
end

function MovementController.slide(dirZ)
	if not hum or not hrp or slide or gather or os.clock() - lastSlideAt < P.SlideCooldown * Cups.factor(ReplicatedStorage:GetAttribute("CupMods"), "SlideCooldown") then
		return false
	end
	if inAir() then
		return false
	end
	run = nil -- a slide calls off a run-up
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

-- A heavy receive shoves you back from the net (strength 0..1 from HitLogic's meta.knock).
function MovementController.knockback(strength)
	if not hum or not hrp or not strength or strength <= 0 or inAir() then
		return
	end
	run = nil
	knock = { t0 = os.clock(), speed = P.KnockbackSpeed * (0.4 + 0.6 * strength), dur = P.KnockbackTime * (0.6 + 0.4 * strength) }
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

-- Serving: until the ball is served the server can't walk past the end line (so holding
-- toward the net for a forward toss never walks you in). A jump may carry you over it: a jump
-- serve lands in the court legally. Returns the line's depth from the net while it applies.
local LINE_GAP = 0.25
local function serveLine()
	if not State.isPlaying or not State.isServer() then
		return nil
	end
	local phase = State.phase()
	if phase ~= "PreServe" and phase ~= "Serving" then
		return nil
	end
	local BR = mods.BallRenderer
	local meta = BR.getMeta()
	if BR.getState() ~= "Held" and not (meta and meta.hitType == "Toss") then
		return nil
	end
	return Config.Court.SideDepth + LINE_GAP
end

local function holdServeLine(airborne)
	local line = not airborne and serveLine()
	if not line then
		return
	end
	local depth = hrp.Position.Z * State.mySide
	-- only at the line: somebody who jumped well into the court is left where they landed
	if depth < line and depth > line - 2.5 then
		hrp.CFrame = hrp.CFrame + Vector3.new(0, 0, (line - depth) * State.mySide)
		local v = hrp.AssemblyLinearVelocity
		if v.Z * State.mySide < 0 then
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, 0)
		end
	end
end

-- Physics step: lane, hang, hover, the serve line.
local function physicsStep()
	if not hum or not hrp or not hrp.Parent or hum.Health <= 0 then
		return
	end
	lockLane()
	local vy = hrp.AssemblyLinearVelocity.Y
	local airborne = inAir()
	holdServeLine(airborne)
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
	local airborne = inAir()
	local stats = State.myStats()

	if takeoff then
		local e = now - takeoff.t0
		if hum:GetState() == Enum.HumanoidStateType.Jumping or hrp.AssemblyLinearVelocity.Y > 2 or e > TAKEOFF_GIVEUP or slide then
			takeoff = nil -- off the floor (or long past it)
		elseif e > TAKEOFF_NUDGE then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
			if takeoff.vz then
				local v = hrp.AssemblyLinearVelocity
				hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, takeoff.vz) -- and the run-up's push again
			end
		end
	end

	if knock and queued then
		knock = nil -- jumping ends the skid
		hum.WalkSpeed = baseWalk()
	end
	if knock then
		local e = now - knock.t0
		if e < knock.dur and not slide then
			-- skid back away from the net, still facing it
			hum.WalkSpeed = knock.speed * (1 - e / knock.dur)
			hum:Move(Vector3.new(0, 0, State.mySide), false)
			face(-State.mySide)
			return
		end
		knock = nil
		hum.WalkSpeed = baseWalk()
	end

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

	if queued then
		jumpKind = queued.kind
		hum.JumpHeight = queued.height
		hum.Jump = true
		takeoff = { t0 = now }
		queued = nil
	end

	if run and (airborne or now - run.t0 >= P.ApproachArmTime) then
		run = nil -- a readied double approach that wasn't taken (or off the floor some other way)
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
			local carry = gather.carry
			local leapDir = gather.leapDir
			jumpKind = gather.kind
			gather = nil
			hum.WalkSpeed = baseWalk() * P.AirControl
			hum.JumpHeight = baseJump()
			hum.Jump = true
			local v = hrp.AssemblyLinearVelocity
			local vz = nil
			if dir ~= 0 then
				vz = dir * (P.ApproachBoost * stats.Approach + (carry or 0))
			elseif leapDir then
				vz = leapDir * carry -- an aimed leap: just its carry
			end
			if vz then
				hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, vz)
			end
			takeoff = { t0 = now, vz = vz }
			if carry then
				leaping = { dir = leapDir or dir, carry = carry, t0 = now }
			end
		end
		return
	end

	if leaping and not airborne and now - leaping.t0 > 0.25 then
		leaping = nil -- landed
	end

	local axis = MovementController.axis()
	local line = not airborne and serveLine()
	if line and axis * -State.mySide > 0 and hrp.Position.Z * State.mySide <= line + 0.05 then
		axis = 0 -- at the serve line: no walking onto the court
	end
	if airborne then
		local air = P.AirControl
		if State.myAbility() == "Azure" then
			air = air * AZURE.AirSpeedBonus
		end
		if leaping then
			-- a Feral Leap carries him the way he leapt; the stick still drifts on top of it
			local vz = leaping.dir * leaping.carry + axis * baseWalk() * air
			hum.WalkSpeed = math.abs(vz)
			hum:Move(Vector3.new(0, 0, vz >= 0 and 1 or -1), false)
			return
		end
		hum.WalkSpeed = baseWalk() * air
	elseif prowlT0 then
		-- Feral Leap's charge: faster as it fills
		local k = math.clamp((now - prowlT0) / FERAL.ChargeTime, 0, 1)
		hum.WalkSpeed = baseWalk() * (1 + FERAL.RunBoost * k)
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
	RunService.PreSimulation:Connect(function()
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
