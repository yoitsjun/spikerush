-- ActionController: turns button presses into volleyball touches (The Spike's control scheme).
--
--   Spike ........ ground: run-up jump / air: spike. Azure Dragon: hold in the air to gather
--                  energy (hover), release to swing. Holding past full overcharges it.
--   Receive ...... arms a receive stance; the touch happens automatically when the ball arrives.
--                  Pressed a little early (not too early) = perfect timing = almost no stamina lost.
--   Slide/feint .. ground: slide receive (never costs stamina) / air: roll shot over the block.
--   Block ........ hold to charge, release to jump; the ball that passes your hands is blocked.
--   Set .......... toward the net = quick, away = back, nothing = open. A receive on the second
--                  touch sets too.
--   Serve ........ tap = overhand serve (hits itself). Hold = jump-serve toss (longer = higher),
--                  then Spike to jump and Spike again to hit.
--
-- Every touch is evaluated locally with the shared HitLogic (same stats, same team stamina as
-- the server), applied instantly and sent to the server for confirmation.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local BallPhysics = require(Shared.BallPhysics)
local HitLogic = require(Shared.HitLogic)
local State = require(script.Parent.State)

local ActionController = {}
local mods

local player = Players.LocalPlayer
local P, Z, H = Config.Player, Config.Zones, Config.Hits
local AZURE = Config.Abilities.Azure
local BUFFER = 0.14 -- how long a set press waits for the ball
-- A spike pressed in the air commits the swing: if the ball will reach your hand within this
-- long (your jump and the ball both predicted), the swing waits for it instead of whiffing.
local SPIKE_WINDOW = 0.6
-- A committed swing lands at the first moment the contact is at least this clean (or as the
-- ball starts to leave your reach), so an early press still spikes, just not as cleanly as a
-- press on time.
local MIN_CONTACT = 0.25
local ATTACK_SCALE = { Spike = 1, Serve = 1.1, Feint = 1.25 }

local lastActionAt = -10
local whiffUntil = 0
local buffered = nil
local stance = nil -- { t0, lastCheck, assist }
local slideCheck = nil
local block = { charging = false, t0 = 0, active = false, activeT0 = 0, lastT = nil }
local serveHold = nil -- { t0 }
local autoOverhand = false
local charge = { holding = false, energy = 0, gauge = 1, overT = 0 }

local REASONS = {
	count = "Three touches used. Send it over!",
	double = "No double touches. Let a teammate play it",
	line = "Step behind the end line to serve",
}

------------------------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------------------------

local AIR_STATES = { [Enum.HumanoidStateType.Jumping] = true, [Enum.HumanoidStateType.Freefall] = true }

local function charInfo()
	local c = player.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return nil
	end
	return {
		char = c,
		hrp = hrp,
		hum = hum,
		root = hrp.Position,
		vy = hrp.AssemblyLinearVelocity.Y,
		-- FloorMaterial lags a few frames behind takeoff; the humanoid state doesn't
		grounded = hum.FloorMaterial ~= Enum.Material.Air and not AIR_STATES[hum:GetState()],
		groundY = hum.HipHeight + hrp.Size.Y / 2,
	}
end

local function buildCtx(info, action, t)
	local BR = mods.BallRenderer
	local touch = BR.getTouch() or { count = 0 }
	local ok, why, third = HitLogic.canTouch(touch, State.myTeam, State.myId, action, State.teamSize())
	local path = BR.getPath()
	local ballVel = Vector3.zero
	if BR.getState() == "Flight" and path then
		ballVel = BallPhysics.velocityAt(path, t)
	end
	return {
		side = State.mySide,
		team = State.myTeam,
		teamSize = State.teamSize(),
		seq = BR.getSeq(),
		ballVel = ballVel,
		lastHit = BR.getMeta(),
		thirdTouch = third,
		touchNumber = HitLogic.touchNumber(touch, State.myTeam),
		stats = State.myStats(),
		ability = State.myAbility(),
		groundY = info.groundY,
		stamina = State.stamina(State.myTeam),
	}, ok, why
end

local function isAzure()
	return State.myAbility() == "Azure"
end

local function towardNetAxis()
	-- +1 if the held direction points at the net, -1 away, 0 none
	local axis = mods.MovementController.axis()
	if math.abs(axis) < 0.3 then
		return 0
	end
	local toward = -State.mySide
	if (axis > 0 and toward > 0) or (axis < 0 and toward < 0) then
		return 1
	end
	return -1
end

-- Who a set is for: another human first, then the ace, then the quick.
local function setTarget()
	local best, bestScore = nil, -math.huge
	for _, e in ipairs(State.roster(State.myTeam)) do
		if e.id ~= State.myId then
			local score = 0
			if not e.isBot then
				score = score + 10
			end
			if e.role == "WS" then
				score = score + 3
			elseif e.role == "MB" then
				score = score + 1
			end
			if score > bestScore then
				best, bestScore = e, score
			end
		end
	end
	return best and best.id or State.myId
end

------------------------------------------------------------------------------------------
-- executing touches
------------------------------------------------------------------------------------------

local function execute(action, info, opts, t, ballPos)
	local ctx, allowed, why = buildCtx(info, action, t)
	if not allowed then
		State.hint(REASONS[why] or "Not your touch")
		return false, why
	end
	if action == "Toss" and math.abs(info.root.Z) < Config.Court.SideDepth - 0.5 then
		State.hint(REASONS.line)
		return false, "line"
	end
	local input = {
		action = action,
		t = t,
		root = info.root,
		vy = info.vy,
		grounded = info.grounded,
		diving = opts.diving == true,
		ball = ballPos,
		assist = opts.assist == true,
		stanceAge = opts.stanceAge or 0.25,
		energy = opts.energy or 0,
		setType = opts.setType,
		targetId = opts.targetId,
		tossHeight = opts.tossHeight,
	}
	local ok, result = HitLogic.compute(input, ctx)
	if not ok then
		return false, result
	end
	local meta = result.meta
	meta.id = State.myId
	meta.name = player.DisplayName
	meta.team = State.myTeam
	meta.t = t
	local touch = HitLogic.nextTouch(mods.BallRenderer.getTouch(), State.myTeam, State.myId, action)
	mods.BallRenderer.predict(result, touch)
	if meta.knock then
		mods.MovementController.knockback(meta.knock)
	end
	Net.get("HitRequest"):FireServer({
		seq = ctx.seq,
		action = action,
		t = t,
		root = info.root,
		vy = info.vy,
		grounded = info.grounded,
		diving = input.diving,
		ball = ballPos,
		assist = input.assist,
		stanceAge = input.stanceAge,
		energy = input.energy,
		setType = input.setType,
		targetId = input.targetId,
		tossHeight = input.tossHeight,
	})
	lastActionAt = os.clock()
	buffered = nil
	return true
end

local function whiff(info, pose, reason)
	if reason then
		State.hint(reason)
	end
	whiffUntil = os.clock() + P.WhiffCooldown
	mods.AnimationController.pose(State.myId, pose or "Swing")
	mods.AudioController.play("Whoosh", { volume = 0.45 })
	Net.get("ActionFX"):FireServer("Whiff", pose or "Swing")
end

local function ballNow()
	local now = Util.now()
	return now, mods.BallRenderer.getPosition(now)
end

local function inPlay()
	return State.isPlaying and State.phase() == "Rally" and mods.BallRenderer.isLive()
end

-- My root height `dt` seconds from now while airborne: gravity with the hang force near the
-- apex and the Azure hover while charging, the same forces MovementController applies.
local function rootPath(info, horizon)
	local g = workspace.Gravity
	local y, v = info.root.Y, info.vy
	local step = 1 / 120
	local out = {}
	local t = 0
	while t < horizon do
		local cancel = 0
		if charge.holding and v <= 0 then
			cancel = AZURE.GravityCancel
		elseif math.abs(v) < P.HangVelocityWindow then
			cancel = P.HangGravityCancel
		end
		v = v - g * (1 - cancel) * step
		y = y + v * step
		t = t + step
		table.insert(out, y)
	end
	return out, step
end

-- Normalised offset of the ball from the centre of my spike zone (|n| <= 1 is in reach).
local function zoneOffset(root, ball, scale)
	local stats = State.myStats()
	local s = scale * (stats.Reach or 1)
	local side = State.mySide
	local handZ = root.Z - side * Z.SpikeForward
	local dz = (ball.Z - handZ) * -side
	local dy = ball.Y - (root.Y + Z.SpikeUp)
	return (dz - Z.SpikeCenterDz) / (Z.SpikeRadiusZ * s), (dy - Z.SpikeCenterDy) / (Z.SpikeRadiusY * s)
end

-- Look ahead: does the ball come into reach within the window? Returns the seconds until it
-- does (nil if never), plus the closest approach for explaining a miss.
local function lookAhead(info, now, scale, horizon)
	local BR = mods.BallRenderer
	local ys, step = rootPath(info, horizon)
	local bestD, bestNz, bestNy = math.huge, 0, 0
	for i = 2, #ys, 2 do
		local t = i * step
		local root = Vector3.new(info.root.X, ys[i], info.root.Z)
		local nz, ny = zoneOffset(root, BR.getPosition(now + t), scale)
		local d = math.sqrt(nz * nz + ny * ny)
		if d <= 1 then
			return t, nz, ny
		end
		if d < bestD then
			bestD, bestNz, bestNy = d, nz, ny
		end
	end
	return nil, bestNz, bestNy
end

local function missReason(nz, ny)
	if math.abs(ny) >= math.abs(nz) then
		if ny > 0 then
			return "Too early: the ball's still above your reach"
		end
		return "Too late: the ball got below your hand"
	end
	if nz > 0 then
		return "Ball's ahead of you: drift toward the net"
	end
	return "Ball's behind you: drift back"
end

local function attackPose(action)
	if action == "Feint" then
		return "Tip"
	end
	return "Swing"
end

-- Swing now if the contact is already decent (or about to get worse), otherwise commit the swing
-- and let processBuffer land it.
local function tryAttack(action, info, opts)
	local now, ball = ballNow()
	-- rules first, so a blocked touch says why instead of silently waiting
	if action ~= "Serve" then
		local allowed, why = HitLogic.canTouch(mods.BallRenderer.getTouch(), State.myTeam, State.myId, action, State.teamSize())
		if not allowed then
			State.hint(REASONS[why] or "Not your touch")
			return false
		end
		if ball.Z * State.mySide < -0.4 then
			State.hint("The ball's already over the net")
			return false
		end
	end
	local scale = ATTACK_SCALE[action] or 1
	local nz, ny = zoneOffset(info.root, ball, scale)
	local d = math.sqrt(nz * nz + ny * ny)
	local q = d <= 1 and (1 - d ^ 1.5) or 0
	local swingNow = d <= 1 and q >= MIN_CONTACT
	if d <= 1 and not swingNow then
		-- barely in reach: swing now if the ball is on its way out, wait if it's coming in
		local ys = rootPath(info, 1 / 60)
		local nz2, ny2 = zoneOffset(Vector3.new(info.root.X, ys[#ys], info.root.Z), mods.BallRenderer.getPosition(now + 1 / 60), scale)
		swingNow = math.sqrt(nz2 * nz2 + ny2 * ny2) >= d
	end
	if swingNow then
		local ok, why = execute(action, info, opts, now, ball)
		if ok then
			mods.AnimationController.pose(State.myId, attackPose(action))
			return true
		end
		if why == "over" then
			State.hint("The ball's already over the net")
			return false
		end
		if why ~= "zone" then
			return false
		end
	end
	local arrives, cz, cy = lookAhead(info, now, scale, SPIKE_WINDOW)
	if arrives then
		buffered = { action = action, opts = opts, expires = os.clock() + arrives + 0.25, scale = scale, lastQ = nil }
		return true
	end
	whiff(info, attackPose(action), missReason(cz, cy))
	return false
end

------------------------------------------------------------------------------------------
-- presses and releases
------------------------------------------------------------------------------------------

local function serving()
	return State.isPlaying and State.phase() == "Serving" and State.isServer()
end

local function myToss()
	local BR = mods.BallRenderer
	local meta = BR.getMeta()
	return BR.isLive() and meta and meta.hitType == "Toss" and meta.id == State.myId
end

local function pressSpike(info)
	local MC = mods.MovementController
	if serving() then
		local BR = mods.BallRenderer
		if BR.getState() == "Held" then
			-- Spike on a held ball: a standard jump-serve toss
			local now = Util.now()
			execute("Toss", info, { tossHeight = (H.TossHighMin + H.TossHighMax) / 2 }, now, info.root)
			autoOverhand = false
			return
		end
		if myToss() then
			if info.grounded then
				MC.approach("Serve")
			elseif isAzure() and charge.gauge > 0.05 then
				charge.holding, charge.energy, charge.overT = true, 0, 0
				MC.setCharging(true)
				Net.get("ActionFX"):FireServer("Charge")
			else
				tryAttack("Serve", info, {})
			end
		end
		return
	end
	if not State.isPlaying or State.phase() ~= "Rally" then
		return
	end
	if info.grounded then
		MC.approach("Spike")
		return
	end
	if isAzure() and charge.gauge > 0.05 then
		charge.holding, charge.energy, charge.overT = true, 0, 0
		MC.setCharging(true)
		mods.AnimationController.pose(State.myId, "Charge", 2)
		mods.AudioController.play("AzureCharge", { volume = 0.7 })
		Net.get("ActionFX"):FireServer("Charge")
		return
	end
	if os.clock() - lastActionAt < P.ActionCooldown or os.clock() < whiffUntil then
		return
	end
	tryAttack("Spike", info, {})
end

local function releaseSpike(info)
	if not charge.holding then
		return
	end
	charge.holding = false
	mods.MovementController.setCharging(false)
	Net.get("ActionFX"):FireServer("ChargeEnd")
	local energy = charge.energy
	if charge.overT >= AZURE.OverchargeGrace then
		energy = 1.3
	end
	charge.energy = 0
	charge.overT = 0
	if info.grounded then
		return
	end
	if serving() and myToss() then
		tryAttack("Serve", info, { energy = energy })
	elseif inPlay() then
		tryAttack("Spike", info, { energy = energy })
	end
end

local function pressReceive(info)
	if serving() then
		return
	end
	if not State.isPlaying then
		return
	end
	stance = { t0 = Util.now(), lastCheck = nil }
	mods.AnimationController.pose(State.myId, "Stance", P.ReceiveStance)
	Net.get("ActionFX"):FireServer("Stance")
end

local function pressSlideFeint(info)
	if not State.isPlaying then
		return
	end
	local phase = State.phase()
	if info.grounded then
		if phase ~= "Rally" and phase ~= "Serving" then
			return
		end
		local dir = mods.MovementController.axis()
		if math.abs(dir) < 0.3 and mods.BallRenderer.isLive() then
			dir = mods.BallRenderer.getPath().landing.pos.Z - info.root.Z
		end
		if mods.MovementController.slide(dir) then
			slideCheck = { until_ = os.clock() + P.SlideTime + 0.05, lastCheck = nil }
			mods.AnimationController.pose(State.myId, "Slide", P.SlideTime + P.SlideRecover)
			mods.AudioController.play("Slide")
			Net.get("ActionFX"):FireServer("Slide")
		end
		return
	end
	if inPlay() and os.clock() - lastActionAt >= P.ActionCooldown then
		tryAttack("Feint", info, {})
	end
end

local function pressBlock(info)
	if not State.isPlaying or not info.grounded then
		return
	end
	block.charging = true
	block.t0 = os.clock()
	mods.AnimationController.pose(State.myId, "Crouch", 2)
end

local function releaseBlock(info)
	if not block.charging then
		return
	end
	block.charging = false
	local fraction = math.clamp((os.clock() - block.t0) / P.BlockChargeTime, 0, 1)
	if not mods.MovementController.blockJump(fraction) then
		return
	end
	if math.abs(info.root.Z) <= P.BlockReach and State.phase() == "Rally" then
		block.active = true
		block.activeT0 = os.clock()
		block.lastT = Util.now()
		mods.AnimationController.pose(State.myId, "Block", 1.1)
		Net.get("ActionFX"):FireServer("Block")
	end
end

local function pressSet(info)
	if not inPlay() or os.clock() - lastActionAt < P.ActionCooldown then
		return
	end
	local dir = towardNetAxis()
	local setType = "Open"
	if dir > 0 then
		setType = "Quick"
	elseif dir < 0 then
		setType = "Back"
	end
	local opts = { setType = setType, targetId = setTarget() }
	local now, ball = ballNow()
	local ok, why = execute("Set", info, opts, now, ball)
	if ok then
		mods.AnimationController.pose(State.myId, "Set")
		return
	end
	if why == "zone" then
		buffered = { action = "Set", opts = opts, expires = os.clock() + 0.3 }
	end
end

local function pressServe(info)
	if not serving() then
		return
	end
	local BR = mods.BallRenderer
	if BR.getState() == "Held" then
		serveHold = { t0 = os.clock() }
		mods.AnimationController.pose(State.myId, "TossReady", 2)
		return
	end
	if myToss() then
		-- X again after the toss hits it (standing, or in the air for a jump serve)
		local now, ball = ballNow()
		execute("Serve", info, {}, now, ball)
		mods.AnimationController.pose(State.myId, "Swing")
	end
end

local function releaseServe(info)
	if not serveHold then
		return
	end
	local held = os.clock() - serveHold.t0
	serveHold = nil
	if not serving() or mods.BallRenderer.getState() ~= "Held" then
		return
	end
	local height = H.TossLow
	autoOverhand = held < P.ServeTapTime
	if not autoOverhand then
		local k = math.clamp((held - P.ServeTapTime) / H.TossChargeTime, 0, 1)
		height = H.TossHighMin + (H.TossHighMax - H.TossHighMin) * k
	end
	local now = Util.now()
	if execute("Toss", info, { tossHeight = height }, now, info.root) then
		mods.AnimationController.pose(State.myId, "Toss")
		mods.AudioController.play("Toss")
	end
end

-- How full the jump-serve toss is right now (for the HUD ring).
function ActionController.tossCharge()
	if not serveHold then
		return nil
	end
	local held = os.clock() - serveHold.t0
	if held < P.ServeTapTime then
		return 0
	end
	return math.clamp((held - P.ServeTapTime) / H.TossChargeTime, 0, 1)
end

function ActionController.blockCharge()
	if not block.charging then
		return nil
	end
	return math.clamp((os.clock() - block.t0) / P.BlockChargeTime, 0, 1)
end

function ActionController.chargeState()
	return charge
end

function ActionController.press(action)
	if action == "Timeout" then
		if State.isPlaying and State.timeouts(State.myTeam) > 0 then
			Net.get("Timeout"):FireServer()
		elseif State.isPlaying then
			State.hint("No timeouts left this set")
		end
		return
	end
	local info = charInfo()
	if not info then
		return
	end
	if action == "Spike" then
		pressSpike(info)
	elseif action == "Receive" then
		pressReceive(info)
	elseif action == "SlideFeint" then
		pressSlideFeint(info)
	elseif action == "Block" then
		pressBlock(info)
	elseif action == "Set" then
		pressSet(info)
	elseif action == "Serve" then
		pressServe(info)
	end
end

function ActionController.release(action)
	local info = charInfo()
	if not info then
		return
	end
	if action == "Spike" then
		releaseSpike(info)
	elseif action == "Block" then
		releaseBlock(info)
	elseif action == "Serve" then
		releaseServe(info)
	end
end

------------------------------------------------------------------------------------------
-- per-frame: buffers, receive stance, slide receive, auto block, overhand auto-serve, charge
------------------------------------------------------------------------------------------

local function processBuffer(info, now)
	if not buffered then
		return
	end
	local action = buffered.action
	local attack = ATTACK_SCALE[action] ~= nil
	if os.clock() > buffered.expires or (attack and info.grounded) then
		buffered = nil
		if action ~= "Set" then
			whiff(info, attackPose(action), "Too late: the ball got past your hand")
		end
		return
	end
	local ball = mods.BallRenderer.getPosition(now)
	if attack then
		-- land the committed swing once the contact is decent, or as the ball starts to leave
		local nz, ny = zoneOffset(info.root, ball, buffered.scale)
		local d = math.sqrt(nz * nz + ny * ny)
		if d > 1 then
			if buffered.lastQ then
				-- it was in reach and has left again
				buffered = nil
				whiff(info, attackPose(action), "Too late: the ball got past your hand")
			end
			return
		else
			local q = 1 - d ^ 1.5
			local leaving = buffered.lastQ ~= nil and q < buffered.lastQ
			buffered.lastQ = q
			if q < MIN_CONTACT and not leaving then
				return
			end
		end
	end
	local ok, why = execute(action, info, buffered.opts, now, ball)
	if ok then
		local pose = attackPose(action)
		if action == "Set" then
			pose = "Set"
		end
		mods.AnimationController.pose(State.myId, pose)
	elseif why ~= "zone" then
		buffered = nil
	end
end

-- The armed receive stance fires at the first good contact point (sub-stepped).
local function processStance(info, now)
	if not stance then
		return
	end
	if now - stance.t0 > P.ReceiveStance or not inPlay() then
		stance = nil
		return
	end
	local BR = mods.BallRenderer
	local path = BR.getPath()
	local stats = State.myStats()
	local side = State.mySide
	local t0 = stance.lastCheck or now
	stance.lastCheck = now
	for i = 1, 5 do
		local t = t0 + (now - t0) * i / 5
		local p = BallPhysics.positionAt(path, t)
		local v = BallPhysics.velocityAt(path, t)
		local inRecv = HitLogic.receiveZone(info.root, p, side, stats, false)
		local inSet = HitLogic.setZone(info.root, p, side, stats)
		local ready = (inRecv and v.Y < 0 and p.Y - info.root.Y <= Z.ReceiveIdealY + 0.6) or (inSet and v.Y < 0 and p.Y - info.root.Y <= Z.SetIdealY + 0.3)
		if ready then
			local opts = { stanceAge = t - stance.t0, assist = stance.assist }
			if HitLogic.touchNumber(BR.getTouch(), State.myTeam) == 2 then
				opts.setType = "Open"
				opts.targetId = setTarget()
			end
			if execute("Bump", info, opts, t, p) then
				stance = nil
				local pose = "Bump"
				if inSet and not inRecv then
					pose = "Set"
				end
				mods.AnimationController.pose(State.myId, pose)
			end
			return
		end
	end
end

local function processSlide(info, now)
	if not slideCheck then
		return
	end
	if os.clock() > slideCheck.until_ or not inPlay() then
		slideCheck = nil
		return
	end
	local BR = mods.BallRenderer
	local path = BR.getPath()
	local t0 = slideCheck.lastCheck or now
	slideCheck.lastCheck = now
	for i = 1, 5 do
		local t = t0 + (now - t0) * i / 5
		local p = BallPhysics.positionAt(path, t)
		if HitLogic.receiveZone(info.root, p, State.mySide, State.myStats(), true) and p.Y - info.root.Y < 0.8 then
			if execute("Bump", info, { diving = true }, t, p) then
				slideCheck = nil
			end
			return
		end
	end
end

local function processBlock(info, now)
	if not block.active then
		return
	end
	if info.grounded and os.clock() - block.activeT0 > 0.25 then
		block.active = false
		return
	end
	local BR = mods.BallRenderer
	local meta = BR.getMeta()
	local t0 = block.lastT or now
	block.lastT = now
	if not inPlay() or not meta or meta.team == State.myTeam then
		return
	end
	if HitLogic.isServe(meta.hitType) or meta.hitType == "Toss" then
		return
	end
	local path = BR.getPath()
	for i = 1, 6 do
		local t = t0 + (now - t0) * i / 6
		local p = BallPhysics.positionAt(path, t)
		local v = BallPhysics.velocityAt(path, t)
		if v.Z * State.mySide > 0 and HitLogic.blockBox(info.root, p, State.mySide, State.myStats()) then
			block.active = false
			execute("Block", info, {}, t, p)
			return
		end
	end
end

-- Tapped X: the standing overhand serve hits itself when the toss comes down.
local function processOverhand(info, now)
	if not autoOverhand or not serving() or not myToss() or not info.grounded then
		return
	end
	local BR = mods.BallRenderer
	local ball = BR.getPosition(now)
	local vel = BR.getVelocity(now)
	if vel.Y < 0 and HitLogic.floatZone(info.root, ball, State.mySide) and ball.Y <= info.root.Y + Z.FloatUp + 0.2 then
		if execute("Serve", info, {}, now, ball) then
			autoOverhand = false
			mods.AnimationController.pose(State.myId, "Swing")
		end
	end
end

local function processCharge(info, dt)
	if charge.holding then
		if info.grounded then
			charge.holding = false
			charge.energy = 0
			mods.MovementController.setCharging(false)
			Net.get("ActionFX"):FireServer("ChargeEnd")
		else
			local rate = dt / AZURE.ChargeTime
			local add = math.min(rate, charge.gauge)
			charge.energy = math.min(1, charge.energy + add)
			charge.gauge = math.max(0, charge.gauge - add)
			if charge.energy >= 1 then
				charge.overT = charge.overT + dt
			end
		end
	elseif info.grounded then
		charge.gauge = math.min(1, charge.gauge + dt / AZURE.GaugeRechargeTime)
	end
	local st = "idle"
	if charge.holding then
		st = "charging"
		if charge.overT >= AZURE.OverchargeGrace then
			st = "over"
		elseif charge.energy >= 1 then
			st = "full"
		end
	end
	State.signals.Charge:Fire(charge.energy, charge.gauge, st)
end

-- Receive assist: arms the stance automatically for a ball heading at you.
local function autoAssist(info, now)
	if not State.settings.assist or stance or not info.grounded or not inPlay() then
		return
	end
	local BR = mods.BallRenderer
	local meta = BR.getMeta()
	if not meta or meta.team == State.myTeam then
		return
	end
	local stats = State.myStats()
	for i = 1, 10 do
		local t = now + i * 0.03
		local p = BR.getPosition(t)
		if HitLogic.receiveZone(info.root, p, State.mySide, stats, false) then
			stance = { t0 = now, lastCheck = nil, assist = true }
			-- tells the server you're playing it, so a covering bot holds off
			Net.get("ActionFX"):FireServer("Stance")
			return
		end
	end
end

------------------------------------------------------------------------------------------
-- context for the HUD / mobile buttons
------------------------------------------------------------------------------------------

local function evaluate(info, now)
	local ctx = {}
	if not info or not State.isPlaying then
		return ctx
	end
	local BR = mods.BallRenderer
	local phase = State.phase()
	local side = State.mySide
	local stats = State.myStats()
	ctx.grounded = info.grounded
	ctx.nearNet = math.abs(info.root.Z) <= P.BlockReach
	ctx.stance = stance ~= nil
	if phase == "Serving" and State.isServer() then
		ctx.serving = true
		if BR.getState() == "Held" then
			ctx.spikeLabel = "Toss"
			if math.abs(info.root.Z) < Config.Court.SideDepth - 0.5 then
				ctx.warn = "Step behind the end line"
			end
		elseif myToss() then
			ctx.spikeLabel = info.grounded and "Jump" or "Serve"
			ctx.inZone = not info.grounded and (HitLogic.spikeZone(info.root, BR.getPosition(now), side, stats, 1.1))
		end
		return ctx
	end
	if phase ~= "Rally" or not BR.isLive() then
		ctx.spikeLabel = "Jump"
		return ctx
	end
	local ok, why, third = HitLogic.canTouch(BR.getTouch(), State.myTeam, State.myId, "Bump", State.teamSize())
	ctx.third = third
	ctx.blockedReason = not ok and why or nil
	local bp = BR.getPosition(now)
	if info.grounded then
		ctx.spikeLabel = "Jump"
		ctx.canSet = ok and (HitLogic.setZone(info.root, bp, side, stats))
	else
		ctx.spikeLabel = isAzure() and "Charge" or "Spike"
		ctx.inZone = (HitLogic.spikeZone(info.root, bp, side, stats, 1))
	end
	local meta = BR.getMeta()
	ctx.incoming = meta ~= nil and meta.team ~= State.myTeam and bp.Z * side > -0.6 * Config.Scale.StudsPerMeter
	return ctx
end

function ActionController.init(m)
	mods = m
	State.signals.Ball:Connect(function()
		-- a new touch invalidates any press buffered against the old trajectory
		buffered = nil
		if stance then
			stance.lastCheck = nil
		end
	end)
	RunService:BindToRenderStep("SpikeRushActions", Enum.RenderPriority.Input.Value + 2, function(dt)
		local info = charInfo()
		local now = Util.now()
		State.context = evaluate(info, now)
		if info and State.isPlaying then
			processCharge(info, dt)
			processBuffer(info, now)
			processStance(info, now)
			processSlide(info, now)
			processBlock(info, now)
			processOverhand(info, now)
			autoAssist(info, now)
		end
	end)
end

return ActionController
