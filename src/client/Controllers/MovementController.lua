-- Local character movement for the side view, on top of the Humanoid:
--  * lane lock: you only ever move along the court (left/right on screen)
--  * spike jump: one tap jumps, with a boom (no run-in dash, the same on every device); with the
--    double approach setting the first tap squeaks and starts the approach, the second jumps
--  * block jump: hold to charge a higher jump
--  * slide: a receive dive along the court
--  * air control: drift in the air to line up with the ball (that sets your spike angle)
--  * anime hang near the top of every jump; Azure Dragon hovers while charging
--  * Feral Leap: faster while the charge is held; the leap carries him along the court all flight
--  * Squall: Tailwind's rush to the ball and quick spring, a lighter fall, Eye of the Storm's hover;
--    Downdraft slows whoever it catches
-- Jump height and run speed come from your character's build (set by the server).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cups = require(Shared.Cups)
local HitLogic = require(Shared.HitLogic)
local Net = require(Shared.Net)
local Util = require(Shared.Util)
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
-- Corona's Sundive: { p0, c, target, meet, t0, T, wait, dash } (os.clock), an arc onto the ball
-- with gravity off: he hangs where he is for `wait`, zips along it in `dash` (T = wait + dash),
-- hangs at its end for DiveHold, then falls again
local diving = nil
local CORONA = Config.Abilities.Corona
-- A freeze frame's hang (HitLogic.hangs): { cf, untilT } (os.clock): he stays where he hit it,
-- gravity off, until the ball leaves his hand
local frozen = nil
-- Squall: Tailwind's rush ({ target }: the spot along the court she runs to, nil: the way you hold),
-- its spring rising faster until the top, and Eye of the Storm's hover
local SQUALL = Config.Abilities.Squall
local rushing = nil
local rushRise = false
local hovering = false
local homing = nil -- Updraft's spring at the ball: { vz, untilT } (carried along the court until the top)
-- A jump asked for from an input event. The default control script rewrites Humanoid.Jump every
-- render step (from its own keys), so a jump set straight from an input handler is wiped before
-- physics sees it; moveStep applies it after the control script instead.
local queued = nil -- { height, kind }
-- A jump the humanoid was told to take, until it's off the floor: now and then it ignores
-- Humanoid.Jump (the owner: "i dash forward a tad and my arms swing back but i do not jump", and
-- Valen's leap "cancelled"), so if it hasn't left within TAKEOFF_NUDGE it's made to.
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
	local w = (char and char:GetAttribute("BaseWalkSpeed")) or State.myStats().WalkSpeed
	-- Downdraft: a Squall's Tailwind jump slows the other team for a moment
	if (player:GetAttribute("SlowUntil") or -1) > Util.now() then
		w = w * SQUALL.SlowMul
	end
	return w
end

local function baseJump()
	return (char and char:GetAttribute("BaseJumpHeight")) or (hum and hum.JumpHeight) or 6
end

-- A spike or serve jump's height: Corona's Sun Leap goes far higher while it's on; Squall's
-- Updraft and Thunder's High Strike always do. With stacked abilities the highest of them counts
-- (HitLogic.leapMul: the product would leave the court camera's frame).
local function spikeJump()
	local coronaOn = State.hasAbility("Corona") and mods ~= nil and mods.ActionController.abilityActive("Corona")
	return baseJump() * HitLogic.leapMul(State.abilitySet(), coronaOn)
end

local function onCharacter(c)
	-- (with a timeout: a character removed before its parts arrive, a respawn or teleport mid-load,
	-- left an infinite yield in the live logs)
	local h, r = c:WaitForChild("Humanoid", 10), c:WaitForChild("HumanoidRootPart", 10)
	if not h or not r or c ~= player.Character then
		return
	end
	char = c
	hum = h
	hrp = r
	slide, gather, run, charging, queued, takeoff = nil, nil, nil, false, nil, nil
	prowlT0, leaping = nil, nil
	rushing, rushRise, hovering, homing = nil, false, false, nil
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
			rushRise = false
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

-- A spike (or jump serve) jump: one tap and you're up, carrying the way you walk, on every device
-- (the touch Jump button's jump; the owner: "no run in dash"). With the double approach setting the
-- first tap only starts the approach, with a floor squeak (you don't move), and the second jumps
-- (the owner: "tap once to start and tap again to jump"); untaken for ApproachArmTime it's let go.
function MovementController.approach(kind)
	if run then
		local k = run.kind
		run = nil
		return MovementController.jump(k)
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
	return MovementController.jump(kind or "Spike")
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

-- Corona's Sundive: along the path to `target` (a root position) in `seconds`; `meet`: where his
-- hand meets the ball. Returns the path's control point and how far it drops (studs, the spike's
-- claimed drop), or nil when he can't.
function MovementController.dive(target, seconds, meet)
	if not hrp or not inAir() then
		return nil
	end
	local p0 = hrp.Position
	local c = HitLogic.diveControl(p0, target)
	local T = math.max(seconds, 0.03)
	local wait, dash = HitLogic.diveTiming(T)
	diving = { p0 = p0, c = c, target = target, meet = meet, t0 = os.clock(), T = wait + dash, wait = wait, dash = dash }
	return c, p0.Y - target.Y
end

function MovementController.isDiving()
	return diving ~= nil
end

-- Hang where he is for `seconds` (a freeze frame: Zero Point, a first strike, YeJun's impact
-- frames), then fall from a standstill. Only in the air.
function MovementController.freeze(seconds)
	if not hrp or seconds <= 0 or not inAir() then
		return
	end
	local untilT = os.clock() + seconds
	if frozen then
		frozen.untilT = math.max(frozen.untilT, untilT)
	else
		frozen = { cf = hrp.CFrame, untilT = untilT }
	end
end

-- The dive under way: where it's taking him, where he meets the ball, and the arc's start and
-- control point (nil when not diving).
function MovementController.diveTarget()
	if diving then
		return diving.target, diving.meet, diving.p0, diving.c
	end
	return nil
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
	queued = { height = (kind == "Spike" or kind == "Serve") and spikeJump() or baseJump(), kind = kind }
	return true
end

function MovementController.slide(dirZ)
	if not hum or not hrp or slide or gather or os.clock() - lastSlideAt < P.SlideCooldown * Cups.factor(ReplicatedStorage:GetAttribute("CupMods"), "SlideCooldown") then
		return false
	end
	if inAir() then
		return false
	end
	-- Locked by the other team's Emperor's Dictate (the Tyrant): no slides
	if State.myTeam and State.dictateOn(State.myTeam == "Home" and "Away" or "Home", workspace:GetServerTimeNow()) then
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

-- Squall's Tailwind: rushing while `on` (to MovementController.rushTo's spot, or the way you hold).
function MovementController.setRush(on)
	rushing = on and (rushing or {}) or nil
end

-- Where the rush goes along the court (z), or nil to run the way you hold.
function MovementController.rushTo(z)
	if rushing then
		rushing.target = z
	end
end

function MovementController.isRushing()
	return rushing ~= nil
end

-- Let go of Jump mid-dash (the owner: "an instantaneous stop when letting go of jump"): she stops
-- dead where she is and waits there for the spring.
function MovementController.rushStop()
	if rushing and hrp then
		rushing.target = hrp.Position.Z
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
	end
end

-- The dash is at its spot (or has none).
function MovementController.rushArrived()
	return rushing == nil or rushing.target == nil or (hrp ~= nil and math.abs(rushing.target - hrp.Position.Z) <= 0.5)
end

-- The spring off a rush: straight up to the top of a spike jump, rising RushRise times faster
-- (launched that much faster under that much more gravity until the top). `toZ` (Updraft, at a set):
-- the spring carries her along the court to there by the top (HomeMax at most, never closer to
-- the net than NetClear), so she goes right at the ball.
function MovementController.rushJump(toZ)
	if not MovementController.canJump() then
		return false
	end
	rushing = nil
	queued = { height = spikeJump() * SQUALL.RushRise ^ 2, kind = "Spike", still = true }
	if toZ and hrp then
		local _, rise = MovementController.springPeak()
		local side = State.mySide
		local z = math.max(toZ * side, SQUALL.NetClear) * side
		local dz = math.clamp(z - hrp.Position.Z, -SQUALL.HomeMax, SQUALL.HomeMax)
		queued.homeVz, queued.homeT = dz / math.max(rise, 0.05), rise
	end
	rushRise = true
	return true
end

-- Tailwind's spring from where she stands: the height of its top over her root now (studs) and the
-- seconds it takes to get there (RushRise times quicker than a jump that high).
function MovementController.springPeak()
	local h = spikeJump()
	return h, math.sqrt(2 * h / workspace.Gravity) / SQUALL.RushRise
end

-- Eye of the Storm: all but weightless while `on`; the stick glides her along the court (the
-- owner: "adjusting while spiking is kind of impossible since she doesn't move midair during
-- charge").
function MovementController.setHover(on)
	hovering = on == true
	if hovering then
		homing = nil
	end
	if hovering and hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end

function MovementController.isHovering()
	return hovering
end

-- The share of gravity taken off in the air at vertical speed vy: the hang near the top of every
-- jump, Azure's hover while charging, Squall's hover, lighter fall and quick spring. ActionController
-- predicts the jump with it too.
function MovementController.airCancel(vy)
	if hovering then
		return SQUALL.HoverCancel
	end
	if charging and vy <= 0 then
		return AZURE.GravityCancel
	end
	if rushRise and vy > 0 then
		return 1 - SQUALL.RushRise ^ 2
	end
	local cancel = 0
	if math.abs(vy) < P.HangVelocityWindow then
		cancel = P.HangGravityCancel
	end
	if vy <= 0 and State.hasAbility("Squall") then
		cancel = math.max(cancel, SQUALL.FallCancel)
	end
	if vy <= 0 and State.hasAbility("Ironclad") then
		-- Ironclad's Forge: a slow fall, slower still awakened
		local IC = Config.Abilities.Ironclad
		local awake = HitLogic.ironLives(player:GetAttribute("IronLives")) == 0
		cancel = math.max(cancel, awake and IC.AwakenedDescentCancel or IC.DescentCancel)
	end
	return cancel
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
	if frozen then
		if os.clock() >= frozen.untilT or diving then
			frozen = nil
			hrp.AssemblyLinearVelocity = Vector3.zero
		else
			hrp.CFrame = frozen.cf
			hrp.AssemblyLinearVelocity = Vector3.zero
			cancel = 1
		end
	end
	if diving then
		local e = os.clock() - diving.t0
		if (not airborne and e > 0.05) or e > diving.T + CORONA.DiveHold then
			-- landed, or done hanging at the meeting point: gravity again, from a standstill
			diving = nil
			hrp.AssemblyLinearVelocity = Vector3.zero
		else
			-- hang, then along the arc (placed on it every step: it's nearly a teleport), then hang at
			-- its end. No velocity along it: the dash's speed (hundreds of studs/s) carried into the
			-- floor on a low ball and the physics flung him across the court or 50 m up
			local s = math.clamp((e - diving.wait) / diving.dash, 0, 1)
			local pos = HitLogic.divePoint(diving.p0, diving.c, diving.target, s)
			hrp.CFrame = CFrame.new(pos) * (hrp.CFrame - hrp.CFrame.Position)
			hrp.AssemblyLinearVelocity = Vector3.zero
			cancel = 1
		end
	end
	if rushRise and airborne and vy <= 0 then
		rushRise = false -- the spring's top: her usual (lighter) fall from here
	end
	if airborne and not slide and not diving and not frozen then
		cancel = MovementController.airCancel(vy)
		if hovering then
			-- no rising while she hovers; the glide along the court is hers (moveStep)
			local v = hrp.AssemblyLinearVelocity
			if math.abs(v.X) > 0.01 or v.Y > 0 then
				hrp.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), v.Z)
			end
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
		if queued.still then
			-- straight up: the rush's speed isn't carried into the spring (the owner: "i overshoot the
			-- ball a lot"); Updraft's, at a set, goes at the ball instead
			local vz = queued.homeVz or 0
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, vz)
			takeoff.vz = vz
			homing = queued.homeVz and { vz = vz, untilT = now + queued.homeT } or nil
		end
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
			hum.JumpHeight = (jumpKind == "Spike" or jumpKind == "Serve") and spikeJump() or baseJump()
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
		if State.hasAbility("Azure") then
			air = air * AZURE.AirSpeedBonus
		end
		if diving or frozen then
			hum:Move(Vector3.zero, false) -- the dive's path moves him, or he hangs (physicsStep)
			return
		end
		if hovering then
			-- Eye of the Storm: she glides the way you hold while she charges
			hum.WalkSpeed = baseWalk() * air * SQUALL.HoverGlide
			hum:Move(Vector3.new(0, 0, axis), false)
			return
		end
		if homing then
			if now < homing.untilT then
				-- Updraft's spring carries her at the ball until the top; the stick drifts on top
				local vz = homing.vz + axis * baseWalk() * air * 0.5
				hum.WalkSpeed = math.abs(vz)
				hum:Move(Vector3.new(0, 0, vz >= 0 and 1 or -1), false)
				return
			end
			homing = nil
		end
		if leaping then
			-- a Feral Leap carries him the way he leapt; the stick still drifts on top of it
			local vz = leaping.dir * leaping.carry + axis * baseWalk() * air
			hum.WalkSpeed = math.abs(vz)
			hum:Move(Vector3.new(0, 0, vz >= 0 and 1 or -1), false)
			return
		end
		hum.WalkSpeed = baseWalk() * air
	elseif rushing then
		-- Squall's Tailwind: a dash to the spot under the ball, slowing in to stop on it
		local target = rushing.target
		if target then
			local dz = target - hrp.Position.Z
			if math.abs(dz) > 0.5 then
				hum.WalkSpeed = math.min(SQUALL.DashSpeed, math.abs(dz) * 30)
				hum:Move(Vector3.new(0, 0, dz > 0 and 1 or -1), false)
				face(dz)
			else
				hum:Move(Vector3.zero, false)
				face(-State.mySide)
			end
			return
		end
		hum.WalkSpeed = baseWalk()
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
