-- ActionController: turns button presses into volleyball touches (The Spike's control scheme).
--
--   Spike ........ ground: jump, one tap (with the double approach setting: the first tap squeaks
--                  and starts the approach, the second jumps) / air: spike. Azure Dragon: hold in the air to gather
--                  energy (hover), release to swing. Holding past full overcharges it. Feral
--                  Leap: hold on the ground to charge (he runs faster), let go to leap; the
--                  charge carries him along the court and powers the spike (or the jump serve:
--                  the press that tosses keeps charging while held, as does one after the toss).
--                  Squall: on the ground (Jump too) it dashes under the ball and springs up
--                  (Tailwind); held in the air, once a jump, it hovers and charges, and
--                  letting go swings: at once, a short drop; the longer, the deeper and harder.
--                  With the Halloween Match's ability cards stacked on your own, a hold two of
--                  them want goes by your order (your own first, then the cards): on the ground
--                  the first that starts (a Tailwind with no ball falls through to Feral's
--                  prowl), in the air the first of Azure and Squall; a Sundive there to take
--                  (Corona) goes before either.
--   Ability ...... every one of your active abilities that's ready goes at once.
--   Receive ...... arms a receive stance; the touch happens automatically when the ball arrives.
--                  Pressed a little early (not too early) = perfect timing = almost no stamina lost.
--   Slide/feint .. ground: slide receive (a fraction of the stamina) / air: roll shot over the block.
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
local Breakthrough = require(Shared.Breakthrough)
local Characters = require(Shared.Characters)
local Cups = require(Shared.Cups)
local Halloween = require(Shared.Halloween)
local Lobbies = require(Shared.Lobbies)
local State = require(script.Parent.State)

local ActionController = {}
local mods

local player = Players.LocalPlayer
local P, Z, H = Config.Player, Config.Zones, Config.Hits
local AZURE = Config.Abilities.Azure
local FERAL = Config.Abilities.Feral
local CORONA = Config.Abilities.Corona
local SQUALL = Config.Abilities.Squall
local IRON = Config.Abilities.Ironclad
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
-- swings this jump: as many as you like (the owner took the one-swing limit out again), but
-- Thunder Spiker's second one in a jump hits harder (the server counts them too)
local airSwings = 0
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
-- Squall: Tailwind's rush while Jump or Spike is held on the ground, and Eye of the Storm's hover
-- (once a jump) with the target's depth on their court
local rush = nil -- { t0, kind }
local hover = nil -- { t0, kind }
local hoverUsed = false
-- Ironclad: when this jump left the floor and whether his team had set yet (Forge's charge)
local forge = { t0 = nil, early = false }
local isSquall, startRush, endRush, releaseRush, processRush, startHover, endHover, releaseHover, processHover

local REASONS = {
	count = "Three touches used. Send it over!",
	double = "No double touches. Let a teammate play it",
	line = "Step behind the end line to serve",
}

------------------------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------------------------

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
		-- barrier, or landing on an edge) is on the ground all the same, so it can still jump; and
		-- a one-frame blink of "air" on the floor is still the floor (MovementController.airborne)
		grounded = not mods.MovementController.airborne(),
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
	-- (my own ability is ctx.ability, the one Break grows; ctx.abilities and ctx.abilityList are
	-- every one I play, the Halloween cards' too, built from the same "Abilities" the server's is)
	local has = State.abilitySet()
	local AC = ActionController
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
		abilities = has,
		abilityList = State.myAbilities(),
		groundY = info.groundY,
		stamina = State.stamina(State.myTeam),
		ironWall = action == "Block" and has.IronWall and AC.abilityActive("IronWall") or nil,
		ironclad = AC.bulwark() or nil,
		breakLevel = player:GetAttribute("Break"),
		awakened = has.Ironclad and not AC.bulwark() or nil,
		enemyPoints = State.enemyPoints(State.myTeam),
		teamBoost = State.rallyOn(State.myTeam, t) or nil,
		counter = has.Counter and (player:GetAttribute("Counter") or 0) or nil,
		lift = has.Skyward and player:GetAttribute("Lift") or nil,
		turnabout = has.Turnabout and AC.abilityActive("Turnabout") or nil,
		firstStrike = has.Feral and not player:GetAttribute("FirstStrikeUsed") or nil,
		chain = ReplicatedStorage:GetAttribute("Chain_" .. tostring(State.myTeam)) or 0,
		coronaOn = has.Corona and AC.abilityActive("Corona") or nil,
		coronaStacks = has.Corona and (player:GetAttribute("CoronaStacks") or 0) or nil,
		squallOn = has.Squall and AC.abilityActive("Squall") or nil,
		stormOn = has.Thunder and AC.abilityActive("Thunder") or nil,
		static = has.Thunder and (player:GetAttribute("Static") or 0) or nil,
		mods = Cups.statMods(ReplicatedStorage:GetAttribute("CupMods")), -- a tournament's modifiers
		hex = Halloween.effects(player:GetAttribute("Hex")), -- the Halloween Match's cards that hit me
	}, ok, why
end

-- Active abilities (Storm Call, Corona, Squall, Iron Wall, Turnabout, Rally Cry), each with its own
-- window and cooldown (a Halloween card's stack beside your own). The server confirms one by
-- writing AbilityUntil_<Name>/AbilityReadyAt_<Name> onto the player; until then the press is
-- predicted locally, per ability, so the touch right after it counts.
local localUntil, localAt = {}, {} -- name -> shared-clock window end / os.clock() of the press

local function activeOn(name, now)
	local serverUntil = player:GetAttribute("AbilityUntil_" .. name) or -1
	return now <= math.max(serverUntil, localUntil[name] or -1)
end

-- Whether that active's window is on (nil: any of mine is).
function ActionController.abilityActive(name)
	local now = Util.now()
	if name ~= nil then
		return State.hasAbility(name) and activeOn(name, now)
	end
	for _, a in ipairs(State.myActives()) do
		if activeOn(a, now) then
			return true
		end
	end
	return false
end

-- Ironclad: he still has shields (Bulwark: he blocks at the net without pressing Block, with a
-- block box a little bigger than anyone's, HitLogic.wallReach; no longer Iron Wall's whole wall).
function ActionController.bulwark()
	return State.hasAbility("Ironclad") and HitLogic.ironLives(player:GetAttribute("IronLives")) > 0
end

-- Ironclad: Forge's charge this jump (0..1), and whether he jumped before the set.
function ActionController.forgeCharge()
	if not State.hasAbility("Ironclad") or not forge.t0 then
		return 0, false
	end
	return math.clamp((os.clock() - forge.t0) / IRON.ChargeTime, 0, 1), forge.early
end

-- Ironclad's reach this jump: Steel Reach widens it by the charge, awakened only (as HitLogic).
local function forgeReach()
	if ActionController.bulwark() then
		return 0
	end
	return (ActionController.forgeCharge())
end

-- The active abilities in an ability list, in its order.
local function activesIn(list)
	local out = {}
	for _, name in ipairs(list or {}) do
		local def = Config.Abilities[name or ""]
		if def and def.Active then
			table.insert(out, name)
		end
	end
	return out
end

-- Over a list of actives with their cooldowns (left(name): seconds): the one to name on a button
-- (the first that's ready, else the soonest), the seconds left (0: at least one is ready), and how
-- many actives there are.
local function nextReady(actives, left)
	local best, bestLeft = nil, math.huge
	for _, name in ipairs(actives) do
		local l = left(name)
		if l <= 0 then
			return name, 0, #actives
		end
		if l < bestLeft then
			best, bestLeft = name, l
		end
	end
	return best, best and bestLeft or 0, #actives
end

-- 0 when that active is ready, else seconds of cooldown left (nil: 0 when any of mine is ready,
-- else the soonest).
function ActionController.abilityCooldown(name)
	local now = Util.now()
	if name ~= nil then
		return math.max(0, (player:GetAttribute("AbilityReadyAt_" .. name) or 0) - now)
	end
	local _, left = nextReady(State.myActives(), ActionController.abilityCooldown)
	return left
end

-- My actives for a skill button (Q pops every ready one): the one to name (the first ready, else
-- the soonest), the seconds left on the soonest (0: one is ready) and how many there are.
function ActionController.mySkill()
	return nextReady(State.myActives(), ActionController.abilityCooldown)
end

-- Your AI teammates with an active ability, in a fixed order (by id: the roster is in rotation
-- order, so a side-out would swap them): keys 1 and 2 (D-pad left and right) pop theirs (every
-- one that's ready: a stand-in carries its player's Halloween cards). Their AI never does it on
-- its own.
local function byId(a, b)
	return a.id < b.id
end

function ActionController.teamAbilities()
	local list = {}
	local rosters = State.match and State.match.rosters
	for _, info in ipairs(rosters and rosters[State.myTeam or ""] or {}) do
		if info.isBot and #activesIn(info.abilities or { info.ability }) > 0 then
			table.insert(list, info)
		end
	end
	table.sort(list, byId)
	return list
end

-- An entity's actives: its roster entry's (as teamAbilities), else its model's "Abilities".
local function activesOf(id)
	local e = State.entry(id)
	if e then
		return activesIn(e.abilities or { e.ability })
	end
	return activesIn(Characters.abilitiesOf(Util.modelOf(id)))
end

-- 0 when an entity's active is ready, else the seconds of cooldown left (nil: 0 when any of its
-- actives is ready, else the soonest).
function ActionController.cooldownOf(id, name)
	local model = Util.modelOf(id)
	local now = Util.now()
	if name ~= nil then
		return math.max(0, (model and model:GetAttribute("AbilityReadyAt_" .. name) or 0) - now)
	end
	local actives = activesOf(id)
	if #actives == 0 then
		return math.max(0, (model and model:GetAttribute("AbilityReadyAt") or 0) - now)
	end
	local _, left = nextReady(actives, function(a)
		return ActionController.cooldownOf(id, a)
	end)
	return left
end

-- An AI teammate's actives for a skill button, as mySkill.
function ActionController.skillOf(id)
	return nextReady(activesOf(id), function(a)
		return ActionController.cooldownOf(id, a)
	end)
end

local function pressTeamAbility(i)
	if not State.isPlaying or not State.match.inMatch then
		return
	end
	local mate = ActionController.teamAbilities()[i]
	if not mate then
		return
	end
	-- (the server pops every one of theirs that's ready, as Q does yours)
	local name, left = ActionController.skillOf(mate.id)
	if left > 0 then
		local def = Config.Abilities[name or ""]
		State.hint(string.format("%s's %s is ready in %d s", mate.char or mate.name, def and def.Name or "ability", math.ceil(left)))
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

-- Q (L2, the touch skill button): every one of my actives that's ready goes at once (my own, then
-- the Halloween cards'), each predicted on its own window; the server pops the same ones off the
-- one remote. A card's lasts its plain Duration (its breakthroughs are my own ability's only).
local function pressAbility()
	local actives = State.myActives()
	if #actives == 0 then
		local def = Config.Abilities[State.myAbilities()[1] or ""]
		if def then
			State.hint(def.Name .. " works on its own, no key needed")
		end
		return
	end
	if not State.isPlaying or not State.match.inMatch then
		return
	end
	local fired = 0
	for _, name in ipairs(actives) do
		if ActionController.abilityCooldown(name) <= 0 and os.clock() - (localAt[name] or -10) >= 0.5 then
			fired = fired + 1
			localAt[name] = os.clock()
			localUntil[name] = Util.now() + Breakthrough.ab(name, "Duration", State.breakOf(name))
			mods.VFXController.ability(State.myId, name, fired)
			if name == "Turnabout" then
				State.hint("Turnabout armed: your next set spins into a spike (jump for it)")
			end
		end
	end
	if fired > 0 then
		Net.get("ActionFX"):FireServer("Ability")
		return
	end
	local name, left = nextReady(actives, ActionController.abilityCooldown)
	if left > 0 then
		State.hint(string.format("%s is ready in %d s", Config.Abilities[name].Name, math.ceil(left)))
	end
end

local function isAzure()
	return State.hasAbility("Azure")
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
local function setTarget(aim)
	-- an aimed set (setter mode) goes to the teammate nearest where it comes down: you pick the
	-- hitter by where you aim (the owner: "allow full setter mode control")
	if aim and aim.depth then
		local spotZ = State.mySide * aim.depth
		local near, nearD = nil, math.huge
		for _, e in ipairs(State.roster(State.myTeam)) do
			if e.id ~= State.myId then
				local m = Util.modelOf(e.id)
				local root = m and m:FindFirstChild("HumanoidRootPart")
				local d = root and math.abs(root.Position.Z - spotZ) or math.huge
				if d < nearD then
					near, nearD = e, d
				end
			end
		end
		if near then
			return near.id
		end
	end
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
		sundive = opts.sundive, -- (Corona: how far the dive dropped him)
		grounded = info.grounded,
		diving = opts.diving == true,
		ball = ballPos,
		assist = opts.assist == true,
		stanceAge = opts.stanceAge or 0.25,
		energy = opts.energy or 0,
		second = opts.second, -- Thunder Spiker's second swing this jump (harder)
		setType = opts.setType,
		targetId = opts.targetId,
		tossHeight = opts.tossHeight,
		tossForward = opts.tossForward,
		aimDepth = opts.aimDepth,
		aimHeight = opts.aimHeight,
		gale = opts.gale, -- (Squall: the hover's charge: its power and how deep it goes)
		metal = nil, -- (Ironclad awakened: Forge's charge, and whether it began before the set)
		early = nil,
	}
	if (action == "Spike" or action == "Serve") and HitLogic.has(ctx, "Feral") and leap.gauge > 0 then
		input.gauge, input.toward = leap.gauge, leap.toward
	end
	if action == "Spike" and HitLogic.has(ctx, "Ironclad") then
		local m, e = ActionController.forgeCharge()
		if m > 0 then
			input.metal, input.early = m, e
		end
	end
	local ok, result = HitLogic.compute(input, ctx)
	if not ok then
		return false, result
	end
	local meta = result.meta
	if meta.turnabout then
		localUntil.Turnabout = -1 -- spent (the server clears its window too, Turnabout's alone)
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
		sundive = input.sundive,
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
		gale = input.gale,
		metal = input.metal,
		early = input.early,
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
		local cancel = mods.MovementController.airCancel(v)
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
-- A touch on your team's fourth ball: if it really meets the ball (the usual hit, with the touch
-- count left out), it's sent to the server, which calls the fault and gives them the point. No
-- ball is predicted. Returns whether it met the ball.
local function fourthTouch(action, info, t, ball)
	local ctx = buildCtx(info, action, t)
	local input = { action = action, t = t, root = info.root, vy = info.vy, grounded = info.grounded, ball = ball, setType = "Open" }
	local ok = HitLogic.compute(input, ctx)
	if not ok then
		return false
	end
	lastActionAt = os.clock()
	mods.AnimationController.pose(State.myId, attackPose(action))
	State.hint("Four touches! That's their point")
	Net.get("HitRequest"):FireServer({
		seq = ctx.seq,
		action = action,
		t = t,
		root = info.root,
		vy = info.vy,
		grounded = info.grounded,
		ball = ball,
		setType = "Open",
	})
	return true
end

-- Count a swing in the air: from the second one in a jump it's marked (Thunder Spiker's hits
-- harder: Config.Abilities.Thunder.SecondBoost).
local function takeSwing(info, opts)
	if info.grounded then
		return true
	end
	airSwings = airSwings + 1
	if airSwings == 2 and opts then -- (only the second: the server agrees)
		opts.second = true
	end
	return true
end

-- Corona's Sundive: with the ball below his reach, the earliest moment within DiveWindow that a
-- straight path no faster than DiveSpeedMax puts his hand's sweet spot on it. Returns the root
-- position to go to and the seconds until then, or nil.
local function divePlan(info, now)
	local BR = mods.BallRenderer
	local side = State.mySide
	local C = Config.Court
	-- the sweet spot's offset from the root (zoneOffset's centre)
	local spot = Vector3.new(0, Z.SpikeUp + Z.SpikeCenterDy, -side * (Z.SpikeForward + Z.SpikeCenterDz))
	local steps = 36
	for i = 1, steps do
		local t = CORONA.DiveWindow * i / steps
		local ball = BR.getPosition(now + t)
		local target = Vector3.new(info.root.X, ball.Y - spot.Y, ball.Z - spot.Z)
		local d = target - info.root
		local clear = ball.Z * side > -0.1 and ball.Y >= C.NetTop + H.SpikeMinContactOverNet
		-- (the arc is about 1.15 times its chord)
		if clear and -d.Y >= CORONA.DiveMinDrop and target.Y > info.groundY + 0.6 and d.Magnitude <= CORONA.DiveMaxDist and d.Magnitude * 1.15 / t <= CORONA.DiveSpeedMax then
			return target, t, ball
		end
	end
	return nil
end

local function tryAttack(action, info, opts)
	takeSwing(info, opts)
	local now, ball = ballNow()
	-- rules first, so a blocked touch says why instead of silently waiting
	if action ~= "Serve" then
		local allowed, why = HitLogic.canTouch(mods.BallRenderer.getTouch(), State.myTeam, State.myId, action, State.teamSize())
		-- not yours to touch: you still swing (the owner: "make it so you can swing whenever"),
		-- and it says why. On your team's fourth touch, a swing that meets the ball is a fault
		if not allowed then
			if HitLogic.isFourthTouchFault(why, action) and fourthTouch(action, info, now, ball) then
				return false
			end
			whiff(info, attackPose(action), REASONS[why] or "Not your touch")
			return false
		end
		if ball.Z * State.mySide < -0.4 then
			whiff(info, attackPose(action), "The ball's already over the net")
			return false
		end
	end
	local scale = ATTACK_SCALE[action] or 1
	if action == "Spike" then
		scale = scale * HitLogic.spikeReachAll(State.abilitySet(), leap.gauge, forgeReach()) -- Feral Leap reaches wider (wider still off a leap); Ironclad's Steel Reach too (the widest of mine)
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
	-- Corona: the ball below his reach is a Sundive, along a path onto it (the swing lands on it);
	-- his jump serve too (the owner: "on serves for laith i cant dash")
	if (action == "Spike" or action == "Serve") and not swingNow and State.hasAbility("Corona") and not info.grounded then
		local target, t, meet = divePlan(info, now)
		local p0 = info.root
		local c, drop = nil, nil
		if target then
			c, drop = mods.MovementController.dive(target, t, meet)
		end
		if c then
			-- the spike claims how far the dive dropped him (he hangs still there for the swing);
			-- a dive at the end of a hover or a charge is the dive's alone (the server drops their
			-- gale and energy too)
			opts.sundive = drop
			opts.gale, opts.energy = nil, nil
			buffered = { action = action, opts = opts, expires = os.clock() + t + Config.Abilities.Corona.DiveHold + 0.05, scale = scale, lastQ = nil }
			mods.AnimationController.pose(State.myId, "Charge", 1)
			-- the streak and its ribbon when the dash goes, after the hang
			local wait = HitLogic.diveTiming(t)
			mods.VFXController.diveStart(State.myId, p0, c, target, wait)
			Net.get("ActionFX"):FireServer("Dive", string.format("%.1f,%.1f,%.2f", target.Y, target.Z, wait))
			return true
		end
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
	return State.hasAbility("Feral")
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

-- Let go: a tap is the usual jump (or the double approach's first tap); a hold leaps
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
		MC.approach(jumpKind)
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

------------------------------------------------------------------------------------------
-- Squall (Haneul): Tailwind and Eye of the Storm
------------------------------------------------------------------------------------------

isSquall = function()
	return State.hasAbility("Squall")
end

-- The spot along the court (z) under where the ball comes down through her hitting point on her
-- side, for Tailwind's rush (nil: nowhere to go yet).
-- Also the shared-clock time the ball gets there. The height is where her hand really is at the top
-- of her spring (Updraft lifts her well above her card's hitting point): aimed at the card's, a set
-- travelling toward the net came down there further along than she meets it, and she ended past it.
-- `path`: another path to go by (Updraft's slowed set) instead of the ball's.
local function rushTarget(info, now, path)
	if not inPlay() then
		return nil
	end
	path = path or mods.BallRenderer.getPath()
	if not path then
		return nil
	end
	local side = State.mySide
	local rise = mods.MovementController.springPeak()
	local contactY = info.root.Y + rise + Z.SpikeUp + Z.SpikeCenterDy - 0.3
	-- (a ball already below her hitting point and falling has nowhere for her to meet it)
	if BallPhysics.positionAt(path, now).Y < contactY and BallPhysics.velocityAt(path, now).Y < 0 then
		return nil
	end
	local t, p = BallPhysics.findTime(path, now, function(pos, vel)
		return vel.Y < 0 and pos.Y <= contactY
	end)
	if not t or p.Z * side < 0.3 then
		return nil
	end
	local depth = (p.Z + side * (Z.SpikeForward + Z.SpikeCenterDz)) * side
	return math.clamp(depth, SQUALL.NetClear, Config.Court.SideDepth + 2) * side, t
end

-- Updraft: the ball is a teammate's set she'd slow by springing now.
local function updraftSet()
	local BR = mods.BallRenderer
	return BR.getState() == "Flight" and BR.getPath() ~= nil and HitLogic.updraftCanSlow(BR.getMeta(), State.myTeam, State.myId)
end

-- Tailwind: a dash under the ball, then the spring (processRush); false when there's no ball to go
-- under (the usual jump instead).
startRush = function(kind, info)
	if not mods.MovementController.canJump() then
		return false
	end
	local target = rushTarget(info, Util.now())
	if not target then
		return false
	end
	rush = { t0 = os.clock(), kind = kind }
	mods.MovementController.setRush(true)
	mods.MovementController.rushTo(target)
	mods.AnimationController.pose(State.myId, "Prowl", 10)
	mods.VFXController.rush(State.myId, true)
	Net.get("ActionFX"):FireServer("Rush")
	return true
end

endRush = function()
	rush = nil
	mods.MovementController.setRush(false)
	mods.AnimationController.clearStance(State.myId)
	mods.VFXController.rush(State.myId, false)
	Net.get("ActionFX"):FireServer("RushEnd")
end

-- At the spot (or out of time): spring straight up off the dash (and Downdraft). At a teammate's
-- set (Updraft) the set slows from now (the server does the same from the time sent with it) and
-- the spring goes at where she meets the slowed ball.
releaseRush = function(info)
	local r = rush
	if not r then
		return
	end
	endRush()
	local MC = mods.MovementController
	local toZ, at = nil, nil
	if info and updraftSet() then
		local now = Util.now()
		local slowed = BallPhysics.buildPath(HitLogic.updraftLaunch(mods.BallRenderer.getPath(), now, SQUALL.SetSlow))
		toZ = rushTarget(info, now, slowed)
		at = string.format("%.3f", now)
	end
	if MC.rushJump(toZ) then
		mods.VFXController.rushJump(State.myId)
		Net.get("ActionFX"):FireServer("RushJump", at)
	end
end

-- Let go of Jump (or Spike) mid-dash: she stops dead where she is, and still springs on time.
local function stopRush()
	if rush and not rush.stopped then
		rush.stopped = true
		mods.MovementController.rushStop()
	end
end

-- The dash follows the ball each frame; at the spot (or at DashMax) she waits, then springs so her
-- top comes SpringEarly before the ball reaches her (time to hover and charge). It ends if she
-- leaves the floor some other way or the rally stops.
processRush = function(info, now)
	if not rush then
		return
	end
	if not info.grounded or not isSquall() or State.phase() ~= "Rally" then
		endRush()
		return
	end
	local MC = mods.MovementController
	local target, hitT = rushTarget(info, now)
	if target and not rush.stopped then
		MC.rushTo(target)
	end
	if not (rush.stopped or MC.rushArrived() or os.clock() - rush.t0 >= SQUALL.DashMax) then
		return
	end
	-- (a set Updraft slows comes 1 / SetSlow times later once she springs: she springs that much later)
	local _, riseTime = MC.springPeak()
	local lead = (riseTime + SQUALL.SpringEarly) * (updraftSet() and SQUALL.SetSlow or 1)
	if not hitT or hitT - now <= lead or os.clock() - rush.t0 >= SQUALL.SpringWaitMax then
		releaseRush(info)
	end
end

-- Eye of the Storm's target: its depth on their court, from the shortest spike (no charge) to the
-- deepest (the whole charge), as HitLogic sends it.
local function aimRange()
	return H.SpikeShortDepth, Config.Court.SideDepth - SQUALL.BackMargin
end

startHover = function(kind)
	if hover or hoverUsed then
		return false
	end
	hover = { t0 = os.clock(), kind = kind }
	hoverUsed = true
	mods.MovementController.setHover(true)
	mods.AnimationController.pose(State.myId, "Charge", SQUALL.HoverMax + 0.2)
	mods.VFXController.hover(State.myId, true)
	Net.get("ActionFX"):FireServer("Hover")
	return true
end

endHover = function()
	local h = hover
	hover = nil
	mods.MovementController.setHover(false)
	mods.VFXController.hover(State.myId, false)
	mods.VFXController.aimMarker(nil)
	Net.get("ActionFX"):FireServer("HoverEnd")
	return h
end

-- Let go (or the hover runs out): swing, as charged as the hover was, at the target.
releaseHover = function(info)
	local h = endHover()
	if not h or info.grounded then
		return
	end
	local opts = { gale = math.clamp((os.clock() - h.t0) / SQUALL.ChargeTime, 0, 1) }
	if h.kind == "Serve" then
		if serving() and myToss() then
			tryAttack("Serve", info, opts)
		end
	elseif inPlay() then
		tryAttack("Spike", info, opts)
	end
end

-- While she hovers the target on their court moves back with the charge (where the spike goes if
-- she lets go now: just over the net at first, their back line at the whole charge), drawn there
-- for her; it swings by itself at HoverMax.
processHover = function(info, dt)
	if not hover then
		return
	end
	if info.grounded or not isSquall() then
		endHover()
		return
	end
	local lo, hi = aimRange()
	local k = math.clamp((os.clock() - hover.t0) / SQUALL.ChargeTime, 0, 1)
	local depth, step = HitLogic.galeDepth(k, lo, hi)
	mods.VFXController.aimMarker(Vector3.new(info.root.X, 0, -State.mySide * depth), k, step)
	if os.clock() - hover.t0 >= SQUALL.HoverMax then
		releaseHover(info)
	end
end

------------------------------------------------------------------------------------------
-- stacked abilities: who takes a held press (the Halloween Match's cards play beside your own)
------------------------------------------------------------------------------------------

-- Azure Dragon: start gathering energy (the rally's press also poses and plays the charge sound).
local function startCharge(withPose)
	charge.holding, charge.energy, charge.overT = true, 0, 0
	mods.MovementController.setCharging(true)
	if withPose then
		mods.AnimationController.pose(State.myId, "Charge", 2)
		mods.AudioController.play("AzureCharge", { volume = 0.7 })
	end
	Net.get("ActionFX"):FireServer("Charge")
end

-- Hold Jump (or Spike) on the ground in a rally: Feral's prowl and Squall's Tailwind both want it
-- (HitLogic.INPUTS.GroundJump). Mine go in order, my own first, and the first that starts takes
-- the press: a Tailwind with no ball to go under doesn't, so it falls through to the prowl.
local function startGroundHold(kind, info)
	if not State.isPlaying or State.phase() ~= "Rally" then
		return false
	end
	for _, name in ipairs(State.myAbilities()) do
		if name == "Feral" and startProwl(kind) then
			return true
		elseif name == "Squall" and startRush(kind, info) then
			return true
		end
	end
	return false
end

-- Hold Spike in the air: Azure's charge or Squall's hover, whichever comes first of mine
-- (HitLogic.inputOwner; the other's hold is off, and the server keeps only the owner's input).
local function startAirHold(kind)
	local owner = HitLogic.inputOwner(State.myAbilities(), "AirSpike")
	if owner == "Squall" then
		return startHover(kind)
	elseif owner == "Azure" and charge.gauge > 0.05 then
		startCharge(kind == "Spike")
		return true
	end
	return false
end

-- Corona's Sundive is there to take: in the air, the ball out of reach below him and a path onto
-- it. It takes an air press before either hold (the swing it ends in can't wait for one), and the
-- HUD says Dive by this same test. kind: "Serve" (his own toss) or "Spike". Returns { target, meet }.
local function sundive(info, now, kind)
	if info.grounded or not State.hasAbility("Corona") or mods.MovementController.isDiving() then
		return nil
	end
	local BR = mods.BallRenderer
	local scale = ATTACK_SCALE.Serve
	if kind ~= "Serve" then
		if not HitLogic.canTouch(BR.getTouch(), State.myTeam, State.myId, "Bump", State.teamSize()) then
			return nil
		end
		scale = HitLogic.spikeReachAll(State.abilitySet(), leap.gauge, forgeReach())
	end
	if HitLogic.spikeZone(info.root, BR.getPosition(now), State.mySide, State.myStats(), scale) then
		return nil
	end
	local target, _, meet = divePlan(info, now)
	if not target then
		return nil
	end
	return { target = target, meet = meet }
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
			elseif sundive(info, Util.now(), "Serve") or not startAirHold("Serve") then
				-- (Azure's charge or Eye of the Storm on the jump serve too; a Sundive first)
				tryAttack("Serve", info, {})
			end
		end
		return
	end
	if info.grounded then
		-- a jump whenever you like (the owner: "make it so i can jump whenever"): waiting for the
		-- serve, between points and out of a match too; Feral Leap charges only in a rally, and
		-- Squall's Tailwind rushes only in one
		if startGroundHold("Spike", info) then
			return
		end
		MC.approach("Spike")
		return
	end
	if not State.isPlaying or State.phase() ~= "Rally" then
		-- in the air out of a rally: an empty swing whenever you like (still one a jump)
		if os.clock() >= whiffUntil and takeSwing(info, nil) then -- (always true: swings aren't limited)
			whiff(info, attackPose("Spike"), nil)
		end
		return
	end
	-- Eye of the Storm (hover and charge) or Azure's charge: let go to swing; a Sundive goes first
	if not sundive(info, Util.now(), "Spike") and startAirHold("Spike") then
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
	if rush then
		stopRush() -- (Tailwind: let go and she stops; the dash springs by itself)
		return
	end
	if hover then
		releaseHover(info)
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
			-- the whole dive, recovery included, plays the ball as a slide: a receive stance
			-- (pressed or auto-assist) taking it first made it a normal bump, which drained
			-- stamina and could break the guard (the owner: "sliding takes stamina", "and it
			-- breaks guard")
			stance = nil
			slideCheck = { until_ = os.clock() + P.SlideTime + P.SlideRecover + 0.05, lastCheck = nil }
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
	local fraction = math.clamp((os.clock() - block.t0) / (P.BlockChargeTime * Cups.factor(ReplicatedStorage:GetAttribute("CupMods"), "BlockCharge")), 0, 1)
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
	local opts = { setType = setType, targetId = setTarget(aim) }
	if aim then
		opts.aimDepth, opts.aimHeight = aim.depth, aim.height
	end
	local now, ball = ballNow()
	local ok, why = execute("Set", info, opts, now, ball)
	if ok then
		mods.AnimationController.pose(State.myId, "Set")
		return
	end
	if HitLogic.isFourthTouchFault(why, "Set") then
		fourthTouch("Set", info, now, ball) -- a set on your team's fourth ball is a fault
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
				local p, v = HitLogic.tossLaunch(info.root, State.mySide, height, tossForward(), HitLogic.tossReach(State.abilitySet()))
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
	return math.clamp((os.clock() - block.t0) / (P.BlockChargeTime * Cups.factor(ReplicatedStorage:GetAttribute("CupMods"), "BlockCharge")), 0, 1)
end

function ActionController.chargeState()
	return charge
end

-- The touch Jump button: Spike's jump on the ground (one tap, or two with the double approach),
-- winding up a spike, or a jump serve once the toss is up; in the air it's the spike.
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
			mods.MovementController.approach("Serve")
		end
		return
	end
	-- straight up whenever you like; Feral Leap charges only in a rally, Squall's Tailwind too
	-- (the first of them that starts, as on Spike)
	if startGroundHold("Jump", info) then
		return
	end
	mods.MovementController.approach("Spike")
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
		-- Set wins over a receive stance that hasn't played the ball yet (the owner: "on first touch
		-- over on a free ball i cannot set it says double touch": the receive assist bumped it first)
		stance = nil
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
		-- (Tailwind: let go and she stops; touch: Jump is the spike in the air, so a hover or an
		-- Azure charge it started lets go here too)
		releaseSpike(info)
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
	if not stance or slideCheck then
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
		-- (the setter's assist waits for the bump zone: higher up, the ball is theirs to set)
		local setterAssist = stance.assist and State.myRole == "SE"
		local ready = (inRecv and v.Y < 0 and p.Y - info.root.Y <= Z.ReceiveIdealY + 0.6) or (not setterAssist and inSet and v.Y < 0 and p.Y - info.root.Y <= Z.SetIdealY + 0.3)
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
		if HitLogic.receiveZone(info.root, p, State.mySide, State.myStats(), true) and p.Y - info.root.Y < 1.6 then
			if execute("Bump", info, { diving = true }, t, p) then
				slideCheck = nil
			end
			return
		end
	end
end

local function processBlock(info, now)
	-- Iron Wall up: you're a wall at the net, jumping or not (no block press or timing needed)
	local wallUp = ActionController.abilityActive("IronWall") -- (beats Ironclad's Bulwark when both are up)
	local iron = wallUp or ActionController.bulwark()
	if not block.active and not iron then
		return
	end
	if block.active and info.grounded and os.clock() - block.activeT0 > 0.25 then
		block.active = false
		if not iron then
			return
		end
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
	local reach = HitLogic.wallReach(wallUp, ActionController.bulwark(), meta.hitType)
	for i = 1, 6 do
		local t = t0 + (now - t0) * i / 6
		local p = BallPhysics.positionAt(path, t)
		local v = BallPhysics.velocityAt(path, t)
		if v.Z * State.mySide > 0 and HitLogic.blockBox(info.root, p, State.mySide, State.myStats(), reach) then
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
		if info.grounded or not isAzure() then
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
	if not State.settings.assist or stance or slideCheck or not info.grounded or not inPlay() then
		return
	end
	if setCharge or (buffered and buffered.action == "Set") then
		return -- setting it yourself
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

-- What Spike does on the ground: a run-up jump, or with the double approach first the squeak
-- that readies it, then the jump.
local function groundSpikeLabel()
	if prowl then
		return "Leap" -- Feral Leap's charge: let go to leap
	end
	if rush then
		return "Dash" -- Squall's Tailwind: dashing under the ball
	end
	if State.settings.doubleApproach and not mods.MovementController.isRunning() then
		return "Approach"
	end
	return "Jump"
end

-- What Spike does in the air, by pressSpike's own tests: a hold that's on lets go ("Swing" off
-- the hover, "Charge" while charging), a Sundive there to take ("Dive": it goes before a hold),
-- the hold the press would start (the AirSpike owner's), else `base` ("Spike", or "Serve" on the
-- jump serve).
local function airLabel(base, dive)
	if hover then
		return "Swing"
	end
	if charge.holding then
		return "Charge"
	end
	if dive then
		return "Dive"
	end
	local owner = HitLogic.inputOwner(State.myAbilities(), "AirSpike")
	if owner == "Squall" and not hoverUsed then
		return "Hover"
	elseif owner == "Azure" and charge.gauge > 0.05 then
		return "Charge"
	end
	return base
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
			ctx.inZone = not info.grounded and (HitLogic.spikeZone(info.root, BR.getPosition(now), side, stats, 1.1))
			-- Corona: a Sundive onto his own toss (its path is drawn)
			ctx.dive = sundive(info, now, "Serve")
			ctx.spikeLabel = info.grounded and groundSpikeLabel() or airLabel("Serve", ctx.dive)
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
		ctx.inZone = (HitLogic.spikeZone(info.root, bp, side, stats, HitLogic.spikeReachAll(State.abilitySet(), leap.gauge, forgeReach())))
		-- Corona: a Sundive is there to take (the HUD says Dive, and its path is drawn)
		ctx.dive = sundive(info, now, "Spike")
		ctx.spikeLabel = airLabel("Spike", ctx.dive)
	end
	local meta = BR.getMeta()
	ctx.incoming = meta ~= nil and meta.team ~= State.myTeam and bp.Z * side > -0.6 * Config.Scale.StudsPerMeter
	return ctx
end

function ActionController.init(m)
	mods = m
	State.signals.Ball:Connect(function(snap)
		if snap and snap.retime then
			return -- the same touch, slowed (Updraft): a buffered press still stands
		end
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
		-- Corona: the dive's path, while one is there to take and all the way down it
		local dive = State.context.dive
		local MC = mods.MovementController
		if MC.isDiving() then
			local target, meet, p0, c = MC.diveTarget()
			dive = { target = target, meet = meet, p0 = p0, c = c, live = true }
		end
		mods.VFXController.divePath(info and info.hrp, dive)
		if info and info.grounded then
			airSwings = 0 -- back on the floor: the next jump's swing
			if not hover then
				hoverUsed = false
			end
			forge.t0 = nil
		elseif info and not forge.t0 then
			-- Ironclad: off the floor; before his team's set? (Forge)
			local m = mods.BallRenderer.getMeta()
			forge.t0 = os.clock()
			forge.early = not (m and m.hitType == "Set" and m.team == State.myTeam)
		end
		if info and State.isPlaying then
			processRush(info, now)
			processHover(info, dt)
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
			if rush then
				endRush()
			end
			if hover then
				endHover()
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
