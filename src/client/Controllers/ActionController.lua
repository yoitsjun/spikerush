-- ActionController: turns button presses into volleyball touches (The Spike's control scheme).
--
--   Spike ........ ground: run-up jump (with the double approach setting: the first press runs
--                  in, the second jumps) / air: spike. Azure Dragon: hold in the air to gather
--                  energy (hover), release to swing. Holding past full overcharges it. Feral
--                  Leap: hold on the ground to charge (he runs faster), let go to leap; the
--                  charge carries him along the court and powers the spike (or the jump serve:
--                  the press that tosses keeps charging while held, as does one after the toss).
--   Receive ...... arms a receive stance; the touch happens automatically when the ball arrives.
--                  Pressed a little early (not too early) = perfect timing = almost no stamina lost.
--   Slide/feint .. ground: slide receive (never costs stamina) / air: roll shot over the block.
--   Block ........ hold to charge, release to jump; the ball that passes your hands is blocked.
--   Set .......... toward the net = quick, away = back, nothing = open. A receive on the second
--                  touch sets too.
--   Easy serve ... an underhand serve straight from the hand: a slow, high lob that always lands in.
--   Serve ........ tap = overhand serve (hits itself). Hold = jump-serve toss (longer = higher;
--                  hold toward the net as you let go to toss it forward), then Spike to jump
--                  and Spike again to hit.
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
local Lobbies = require(Shared.Lobbies)
local State = require(script.Parent.State)

local ActionController = {}
local mods

local player = Players.LocalPlayer
local P, Z, H = Config.Player, Config.Zones, Config.Hits
local AZURE = Config.Abilities.Azure
local FERAL = Config.Abilities.Feral
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
-- Feral Leap: the charge held on the ground, and what the current jump took off with (its one
-- spike carries the gauge; spent by that spike or the landing)
local prowl = nil -- { t0, kind } while Spike (Jump on touch) is held on the ground
local leap = { gauge = 0, toward = false, at = -10 }

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
		-- FloorMaterial lags a few frames behind takeoff; the humanoid state doesn't. A humanoid
		-- left in a falling state while it stands still on the floor (pressed on the net's
		-- barrier, or landing on an edge) is on the ground all the same, so it can still jump
		grounded = hum.FloorMaterial ~= Enum.Material.Air and (not AIR_STATES[hum:GetState()] or math.abs(hrp.AssemblyLinearVelocity.Y) < 0.5),
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
	local ability = State.myAbility()
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
		ability = ability,
		groundY = info.groundY,
		stamina = State.stamina(State.myTeam),
		ironWall = action == "Block" and ability == "IronWall" and ActionController.abilityActive() or nil,
		enemyPoints = State.enemyPoints(State.myTeam),
		teamBoost = State.rallyOn(State.myTeam, t) or nil,
		counter = ability == "Counter" and (player:GetAttribute("Counter") or 0) or nil,
		turnabout = ability == "Turnabout" and ActionController.abilityActive() or nil,
		firstStrike = ability == "Feral" and not player:GetAttribute("FirstStrikeUsed") or nil,
	}, ok, why
end

-- Active abilities (Iron Wall, Turnabout, Rally Cry). The server confirms one by writing
-- AbilityUntil/AbilityReadyAt onto the player; until then the press is predicted locally so the
-- touch right after it counts.
local localAbilityUntil, localAbilityAt = -1, -10

function ActionController.abilityActive()
	local serverUntil = player:GetAttribute("AbilityUntil") or -1
	local now = Util.now()
	return now <= math.max(serverUntil, localAbilityUntil)
end

-- 0 when ready, else seconds of cooldown left.
function ActionController.abilityCooldown()
	local readyAt = player:GetAttribute("AbilityReadyAt") or 0
	return math.max(0, readyAt - Util.now())
end

-- Your AI teammates with an active ability, in a fixed order (by id: the roster is in rotation
-- order, so a side-out would swap them): keys 1 and 2 (D-pad left and right) pop theirs. Their
-- AI never does it on its own.
local function byId(a, b)
	return a.id < b.id
end

function ActionController.teamAbilities()
	local list = {}
	local rosters = State.match and State.match.rosters
	for _, info in ipairs(rosters and rosters[State.myTeam or ""] or {}) do
		local def = info.isBot and Config.Abilities[info.ability or ""]
		if def and def.Active then
			table.insert(list, info)
		end
	end
	table.sort(list, byId)
	return list
end

-- 0 when an entity's ability is ready, else the seconds of cooldown left.
function ActionController.cooldownOf(id)
	local model = Util.modelOf(id)
	local readyAt = model and model:GetAttribute("AbilityReadyAt") or 0
	return math.max(0, readyAt - Util.now())
end

local function pressTeamAbility(i)
	if not State.isPlaying or not State.match.inMatch then
		return
	end
	local mate = ActionController.teamAbilities()[i]
	if not mate then
		return
	end
	local def = Config.Abilities[mate.ability]
	local left = ActionController.cooldownOf(mate.id)
	if left > 0 then
		State.hint(string.format("%s's %s is ready in %d s", mate.char or mate.name, def.Name, math.ceil(left)))
		return
	end
	Net.get("ActionFX"):FireServer("TeamAbility", mate.id)
end

-- Timeout (T, Select, the corner button): calls one for the next dead ball; pressed again before
-- then it calls yours off (not used up); in the timeout it's Ready. The server decides the same
-- way (Lobbies.timeoutPress), so a stale match state here only costs the hint.
local function pressTimeout()
	if not State.isPlaying then
		return
	end
	local op, why = Lobbies.timeoutPress(State.match.timeoutPending, State.phase(), State.myId, State.timeouts(State.myTeam))
	if op == "ready" then
		mods.UIController.timeoutReady()
	elseif op then
		Net.get("Timeout"):FireServer()
	elseif why == "taken" then
		State.hint("A timeout is already called for the next dead ball")
	elseif why == "none" then
		State.hint("No timeouts left this set")
	end
end

local function pressAbility()
	local def = Config.Abilities[State.myAbility() or ""]
	if not def or not def.Active then
		if def then
			State.hint(def.Name .. " works on its own, no key needed")
		end
		return
	end
	if not State.isPlaying or not State.match.inMatch then
		return
	end
	local left = ActionController.abilityCooldown()
	if left > 0 or os.clock() - localAbilityAt < 0.5 then
		State.hint(string.format("%s is ready in %d s", def.Name, math.ceil(left)))
		return
	end
	localAbilityAt = os.clock()
	localAbilityUntil = Util.now() + def.Duration
	Net.get("ActionFX"):FireServer("Ability")
	mods.VFXController.ability(State.myId, State.myAbility())
	if State.myAbility() == "Turnabout" then
		State.hint("Turnabout armed: your next set spins into a spike (jump for it)")
	end
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
	if (action == "Toss" or action == "Underhand") and math.abs(info.root.Z) < Config.Court.SideDepth - 0.5 then
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
		tossForward = opts.tossForward,
		aimDepth = opts.aimDepth,
		aimHeight = opts.aimHeight,
	}
	if (action == "Spike" or action == "Serve") and ctx.ability == "Feral" and leap.gauge > 0 then
		input.gauge, input.toward = leap.gauge, leap.toward
	end
	local ok, result = HitLogic.compute(input, ctx)
	if not ok then
		return false, result
	end
	local meta = result.meta
	if meta.turnabout then
		localAbilityUntil = -1 -- spent (the server clears its window too)
	end
	if input.gauge then
		leap.gauge = 0 -- the leap's one spike (the server spends it too)
		Net.get("ActionFX"):FireServer("ProwlEnd")
	end
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
		tossForward = input.tossForward,
		aimDepth = input.aimDepth,
		aimHeight = input.aimHeight,
		gauge = input.gauge,
		toward = input.toward,
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
	mods.AudioController.play("Whiff", { volume = 0.8 })
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
-- apex and the Azure hover while charging, the same forces MovementController applies. Also the
-- speed along the court to assume: a Feral Leap's carry holds all flight (other jumps: none).
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
	local vz = 0
	if mods.MovementController.leaping() then
		vz = info.hrp.AssemblyLinearVelocity.Z
	end
	return out, step, vz
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
	local ys, step, vz = rootPath(info, horizon)
	local bestD, bestNz, bestNy = math.huge, 0, 0
	for i = 2, #ys, 2 do
		local t = i * step
		local root = Vector3.new(info.root.X, ys[i], info.root.Z + vz * t)
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
	if action == "Spike" then
		scale = scale * HitLogic.spikeReach(State.myAbility()) -- Feral Leap reaches wider
	end
	local nz, ny = zoneOffset(info.root, ball, scale)
	local d = math.sqrt(nz * nz + ny * ny)
	local q = d <= 1 and (1 - d ^ 1.5) or 0
	local swingNow = d <= 1 and q >= MIN_CONTACT
	if d <= 1 and not swingNow then
		-- barely in reach: swing now if the ball is on its way out, wait if it's coming in
		local ys, _, vz = rootPath(info, 1 / 60)
		local nz2, ny2 = zoneOffset(Vector3.new(info.root.X, ys[#ys], info.root.Z + vz / 60), mods.BallRenderer.getPosition(now + 1 / 60), scale)
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

-- The easy serve: underhand, straight from the hand while you still hold the ball.
local function pressEasyServe(info)
	if not serving() or mods.BallRenderer.getState() ~= "Held" or not info.grounded then
		return
	end
	serveHold = nil
	if execute("Underhand", info, {}, Util.now(), info.root) then
		mods.AnimationController.playAction(State.myId, "Bump")
	end
end

-- Holding toward the net when the jump-serve toss goes up throws it forward (0..1).
local function tossForward()
	local toward = mods.MovementController.axis() * -State.mySide
	if toward > 0.3 then
		return math.clamp(toward, 0, 1)
	end
	return 0
end

local function isFeral()
	return State.myAbility() == "Feral"
end

-- Feral Leap: the charge held on the ground, 0..1 (nil when not charging).
function ActionController.prowlCharge()
	if not prowl then
		return nil
	end
	return math.clamp((os.clock() - prowl.t0) / FERAL.ChargeTime, 0, 1)
end

-- The gauge the current jump took off with (0 unless it's a Feral Leap), and whether it went at
-- the net.
function ActionController.leapGauge()
	return leap.gauge, leap.toward
end

-- Hold to charge: he drops low and runs faster as the arc fills; the leap comes on the release.
-- kind: the button held ("Spike", or touch's "Jump"); serve: charging a jump serve (the toss is
-- up, or went up with this press: tossed).
local function startProwl(kind, serve, tossed)
	if not mods.MovementController.canJump() then
		return false
	end
	prowl = { t0 = os.clock(), kind = kind, serve = serve == true, tossed = tossed == true }
	leap.gauge = 0
	mods.MovementController.setProwl(prowl.t0)
	mods.AnimationController.pose(State.myId, "Prowl", 10)
	Net.get("ActionFX"):FireServer("Prowl")
	return true
end

local function cancelProwl()
	if not prowl then
		return
	end
	prowl = nil
	mods.MovementController.setProwl(nil)
	mods.AnimationController.clearStance(State.myId)
	Net.get("ActionFX"):FireServer("ProwlEnd")
end

-- A jump serve's leap goes after his own toss: the carry that has the ball in front of his hand as
-- it comes down through his hitting point (never more than the charge gives), with no run-in.
local function serveLeapAim(info, gauge)
	local path = mods.BallRenderer.getPath()
	if not path or not myToss() then
		return nil
	end
	local contactY = State.myStats().contactMaxStuds - 0.2
	local now = Util.now()
	local t, p = BallPhysics.findTime(path, now, function(pos, vel)
		return vel.Y < 0 and pos.Y <= contactY
	end)
	if not t then
		return nil
	end
	local side = State.mySide
	local dz = p.Z + side * (Z.SpikeForward + Z.SpikeCenterDz) - info.root.Z
	local airTime = math.max(t - now - P.ApproachGather, 0.3)
	return { dir = dz >= 0 and 1 or -1, carry = math.min(math.abs(dz) / airTime, FERAL.CarryMax * gauge) }
end

-- Let go: a tap is the usual jump (Spike's run-up, or touch's Jump straight up); a hold leaps
-- the way you hold (at the net when you hold nothing; a serve's leap goes after the toss),
-- carried by the charge, and the gauge goes with the spike or the serve.
local function releaseProwl(info)
	local p = prowl
	if not p then
		return
	end
	prowl = nil
	local MC = mods.MovementController
	MC.setProwl(nil)
	local held = os.clock() - p.t0
	local jumpKind = p.serve and "Serve" or "Spike"
	if held < FERAL.TapTime then
		mods.AnimationController.clearStance(State.myId)
		Net.get("ActionFX"):FireServer("ProwlEnd")
		if p.tossed then
			return -- the tap that tossed the ball: the next press jumps, as for everyone
		end
		if p.kind == "Jump" then
			MC.jump(jumpKind)
		else
			MC.approach(jumpKind)
		end
		return
	end
	local gauge = math.clamp(held / FERAL.ChargeTime, 0, 1)
	local dir = MC.leap(gauge, jumpKind, p.serve and serveLeapAim(info, gauge) or nil)
	if not dir then
		mods.AnimationController.clearStance(State.myId)
		Net.get("ActionFX"):FireServer("ProwlEnd")
		return
	end
	leap.gauge, leap.toward, leap.at = gauge, dir == -State.mySide, os.clock()
	Net.get("ActionFX"):FireServer("Leap", string.format("%.2f", gauge))
end

local function pressSpike(info)
	local MC = mods.MovementController
	if serving() then
		local BR = mods.BallRenderer
		if BR.getState() == "Held" then
			-- Spike on a held ball: a standard jump-serve toss (Feral Leap: kept held, it charges,
			-- so his goes up high enough to charge in full and still meet it at the top)
			local now = Util.now()
			local height = isFeral() and H.TossHighMax or (H.TossHighMin + H.TossHighMax) / 2
			local tossed = execute("Toss", info, { tossHeight = height, tossForward = tossForward() }, now, info.root)
			autoOverhand = false
			if tossed and isFeral() then
				startProwl("Spike", true, true)
			end
			return
		end
		if myToss() then
			if info.grounded then
				if isFeral() and startProwl("Spike", true) then
					return -- Feral Leap: charge the jump serve, let go to leap into the toss
				end
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
	if info.grounded then
		-- a jump whenever you like (the owner: "make it so i can jump whenever"): waiting for the
		-- serve, between points and out of a match too; Feral Leap charges only in a rally
		if State.isPlaying and State.phase() == "Rally" and isFeral() and startProwl("Spike") then
			return
		end
		if not (State.isPlaying and State.phase() == "Rally") and State.settings.doubleApproach then
			MC.jump("Spike") -- the double approach's run-up only runs in a rally
		else
			MC.approach("Spike")
		end
		return
	end
	if not State.isPlaying or State.phase() ~= "Rally" then
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
	if prowl then
		releaseProwl(info)
		return
	end
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
		cancelProwl() -- a slide calls off Feral Leap's charge
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

-- Hold W (or Up / Y) to crouch and charge, release to jump. Near the net in a rally the jump is
-- a block; anywhere else it's just a charged jump.
local function pressBlock(info)
	if not info.grounded or not mods.MovementController.canJump() then
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

-- Setter aim: holding Set charges the set's distance (SetterAim draws it); letting go sets.
local setCharge = nil -- { t0 } while Set is held with the aim on

function ActionController.setCharge()
	if not setCharge then
		return nil
	end
	return math.clamp((os.clock() - setCharge.t0) / H.SetChargeTime, 0, 1)
end

local function doSet(info, aim)
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
	if aim then
		opts.aimDepth, opts.aimHeight = aim.depth, aim.height
	end
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
	local forward = 0
	autoOverhand = held < P.ServeTapTime
	if not autoOverhand then
		local k = math.clamp((held - P.ServeTapTime) / H.TossChargeTime, 0, 1)
		height = H.TossHighMin + (H.TossHighMax - H.TossHighMin) * k
		forward = tossForward() -- held toward the net: out in front to run into
	end
	local now = Util.now()
	if execute("Toss", info, { tossHeight = height, tossForward = forward }, now, info.root) then
		mods.AnimationController.pose(State.myId, "Toss")
		mods.AudioController.play("Toss")
	end
end

-- The dotted toss path: while you charge the jump-serve toss, where it will go (height from the
-- hold, forward from the direction held); once it's up, the rest of its flight.
local GUIDE_STEP = 0.075
local guideOn = false
local function tossGuide(info)
	local BR = mods.BallRenderer
	local path, from = nil, 0
	if serving() then
		if serveHold and BR.getState() == "Held" then
			local held = os.clock() - serveHold.t0
			if held >= P.ServeTapTime then
				local k = math.clamp((held - P.ServeTapTime) / H.TossChargeTime, 0, 1)
				local height = H.TossHighMin + (H.TossHighMax - H.TossHighMin) * k
				local p, v = HitLogic.tossLaunch(info.root, State.mySide, height, tossForward(), HitLogic.tossReach(State.myAbility()))
				path = BallPhysics.buildPath(BallPhysics.newLaunch(p, v, Vector3.new(0, -Config.Ball.Gravity, 0), 0))
			end
		elseif myToss() then
			path, from = BR.getPath(), Util.now()
		end
	end
	if not path then
		if guideOn then
			BR.guide(nil)
			guideOn = false
		end
		return
	end
	local points = {}
	local floorY = info.root.Y - 1.5
	local t = from + GUIDE_STEP
	while #points < 32 and t < path.landing.t do
		local pos = BallPhysics.positionAt(path, t)
		if pos.Y < floorY and BallPhysics.velocityAt(path, t).Y < 0 then
			break
		end
		table.insert(points, pos)
		t = t + GUIDE_STEP
	end
	BR.guide(points)
	guideOn = true
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

-- The touch Jump button: straight up (the owner: "on mobile, make approach just make you
-- jump"), winding up a spike, or a jump serve once the toss is up; in the air it's the spike.
-- Feral Leap: held on the ground it charges, and letting go leaps.
local function pressJump(info)
	if not info.grounded then
		pressSpike(info)
		return
	end
	if serving() then
		if myToss() then
			if isFeral() and startProwl("Jump", true) then
				return -- Feral Leap: charge the jump serve
			end
			mods.MovementController.jump("Serve")
		end
		return
	end
	-- straight up whenever you like; Feral Leap charges only in a rally
	if State.isPlaying and State.phase() == "Rally" and isFeral() and startProwl("Jump") then
		return
	end
	mods.MovementController.jump("Spike")
end

function ActionController.press(action)
	if action == "Ability" then
		pressAbility()
		return
	end
	if action == "Team1" or action == "Team2" then
		pressTeamAbility(action == "Team1" and 1 or 2)
		return
	end
	if action == "Timeout" then
		pressTimeout()
		return
	end
	local info = charInfo()
	if not info then
		return
	end
	if action == "Spike" then
		pressSpike(info)
	elseif action == "Jump" then
		pressJump(info)
	elseif action == "Receive" then
		pressReceive(info)
	elseif action == "SlideFeint" then
		pressSlideFeint(info)
	elseif action == "Block" then
		pressBlock(info)
	elseif action == "Set" then
		if mods.SetterAim and mods.SetterAim.on() and not mods.SetterAim.charged() then
			doSet(info, mods.SetterAim.aim()) -- the mouse's aim: set there at once
		elseif mods.SetterAim and mods.SetterAim.on() then
			setCharge = { t0 = os.clock() } -- the set goes when Set is let go
		else
			doSet(info, nil)
		end
	elseif action == "Serve" then
		pressServe(info)
	elseif action == "EasyServe" then
		pressEasyServe(info)
	end
end

function ActionController.release(action)
	local info = charInfo()
	if not info then
		return
	end
	if action == "Spike" then
		releaseSpike(info)
	elseif action == "Jump" then
		releaseProwl(info)
	elseif action == "Block" then
		releaseBlock(info)
	elseif action == "Serve" then
		releaseServe(info)
	elseif action == "Set" and setCharge then
		local aim = mods.SetterAim and mods.SetterAim.aim()
		setCharge = nil
		if aim then
			doSet(info, aim)
		end
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

-- Feral Leap: the charge ends if he leaves the ground some other way, or the rally stops (a
-- serve's charge: the toss is gone); a leap's gauge is gone once he lands without hitting.
local function processProwl(info)
	if prowl then
		local live = false
		if prowl.serve then
			live = serving() and myToss()
		else
			live = State.phase() == "Rally"
		end
		if not info.grounded or not isFeral() or not live then
			cancelProwl()
		end
	end
	if leap.gauge > 0 and info.grounded and os.clock() - leap.at > 0.35 and not mods.MovementController.isGathering() then
		leap.gauge = 0
		Net.get("ActionFX"):FireServer("ProwlEnd")
	end
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

-- What Spike does on the ground: a run-up jump, or with the double approach first the run-up,
-- then the jump.
local function groundSpikeLabel()
	if prowl then
		return "Leap" -- Feral Leap's charge: let go to leap
	end
	if State.settings.doubleApproach and not mods.MovementController.isRunning() then
		return "Approach"
	end
	return "Jump"
end

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
	ctx.running = mods.MovementController.isRunning()
	if phase == "Serving" and State.isServer() then
		ctx.serving = true
		if BR.getState() == "Held" then
			ctx.spikeLabel = "Toss"
			if math.abs(info.root.Z) < Config.Court.SideDepth - 0.5 then
				ctx.warn = "Step behind the end line"
			end
		elseif myToss() then
			ctx.spikeLabel = info.grounded and groundSpikeLabel() or "Serve"
			ctx.inZone = not info.grounded and (HitLogic.spikeZone(info.root, BR.getPosition(now), side, stats, 1.1))
		end
		return ctx
	end
	if phase ~= "Rally" or not BR.isLive() then
		ctx.spikeLabel = groundSpikeLabel()
		return ctx
	end
	local ok, why, third = HitLogic.canTouch(BR.getTouch(), State.myTeam, State.myId, "Bump", State.teamSize())
	ctx.third = third
	ctx.blockedReason = not ok and why or nil
	local bp = BR.getPosition(now)
	if info.grounded then
		ctx.spikeLabel = groundSpikeLabel()
		ctx.canSet = ok and (HitLogic.setZone(info.root, bp, side, stats))
	else
		ctx.spikeLabel = isAzure() and "Charge" or "Spike"
		ctx.inZone = (HitLogic.spikeZone(info.root, bp, side, stats, HitLogic.spikeReach(State.myAbility())))
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
			processProwl(info)
			processCharge(info, dt)
			processBuffer(info, now)
			processStance(info, now)
			processSlide(info, now)
			processBlock(info, now)
			processOverhand(info, now)
			autoAssist(info, now)
			tossGuide(info)
		else
			if prowl then
				cancelProwl()
			end
			leap.gauge = 0
			if guideOn then
				mods.BallRenderer.guide(nil)
				guideOn = false
			end
		end
	end)
end

return ActionController
