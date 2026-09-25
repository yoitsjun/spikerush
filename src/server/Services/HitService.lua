-- HitService: validates hit requests from clients (and from bots), runs the shared HitLogic
-- on the validated inputs and launches the authoritative ball.
--
-- Clients report WHEN and WHERE they touched the ball (on their synced clock). The server
-- checks that claim against its own path and character positions, with a latency-sized
-- tolerance, then recomputes the result itself. Because HitLogic is deterministic, the result
-- matches the hitter's prediction exactly. Stamina drain is applied here, on the server only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local BallPhysics = require(Shared.BallPhysics)
local HitLogic = require(Shared.HitLogic)
local Tutorial = require(Shared.Tutorial)

local HitService = {}
local reg

local VALID = { Bump = true, Set = true, Spike = true, Feint = true, Block = true, Toss = true, Serve = true, Underhand = true }
local SET_TYPES = { Open = true, Quick = true, Back = true }
local FX_KINDS = { Slide = true, Block = true, Whiff = true, Jump = true, Charge = true, ChargeEnd = true, Stance = true }
local INTENT = { Slide = true, Block = true, Whiff = true, Jump = true, Charge = true, Stance = true }
local requestLog = {}
local intentAt = {} -- entityId -> os.clock() of the player's last attempt to play the ball
local missedAt = {} -- entityId -> os.clock() of the player's last whiffed swing or dig

-- Seconds since this player last tried to play the ball (a receive stance, slide, jump, block,
-- charge or any touch request). Bots covering a human's ball hold off while this is small.
function HitService.intentAge(entityId)
	local t = intentAt[entityId]
	if not t then
		return math.huge
	end
	return os.clock() - t
end

-- Seconds since this player last swung at the ball and missed. A covering bot plays the ball
-- right away after a miss instead of waiting for the player to try again.
function HitService.missAge(entityId)
	local t = missedAt[entityId]
	if not t then
		return math.huge
	end
	return os.clock() - t
end

local function rateLimited(plr)
	local now = os.clock()
	local log = requestLog[plr]
	if not log then
		log = {}
		requestLog[plr] = log
	end
	while #log > 0 and now - log[1] > 1 do
		table.remove(log, 1)
	end
	if #log >= Config.Net.MaxRequestsPerSecond then
		return true
	end
	table.insert(log, now)
	return false
end

local function finiteNumber(n)
	return type(n) == "number" and n == n and n > -1e6 and n < 1e10
end

local function num(n, lo, hi, default)
	if finiteNumber(n) then
		return math.clamp(n, lo, hi)
	end
	return default
end

-- Core: used by both remote requests and bots. Returns ok, reason.
function HitService.process(entity, input, opts)
	opts = opts or {}
	local BS, MS, TS = reg.BallService, reg.MatchService, reg.TeamService
	local now = Util.now()
	local action = input.action
	local phase = MS.phase

	if opts.seq ~= nil and opts.seq ~= BS.seq then
		return false, "stale"
	end
	if opts.fromClient then
		if input.t > now + Config.Net.FutureTolerance or input.t < now - Config.Net.MaxRewind then
			return false, "time"
		end
	end

	if action == "Toss" or action == "Underhand" then
		if phase ~= "Serving" or BS.state ~= "Held" or BS.holderId ~= entity.id then
			return false, "toss"
		end
		if math.abs(input.root.Z) < Config.Court.SideDepth - 0.5 then
			return false, "line"
		end
	elseif action == "Serve" then
		local last = BS.lastHit
		if phase ~= "Serving" or BS.state ~= "Flight" or not last or last.hitType ~= "Toss" or last.id ~= entity.id then
			return false, "serve"
		end
	else
		if phase ~= "Rally" or BS.state ~= "Flight" then
			return false, "phase"
		end
	end

	if BS.state == "Flight" then
		local path = BS.path
		if input.t < BallPhysics.startTime(path) - 0.01 then
			return false, "early"
		end
		if input.t >= path.landing.t then
			return false, "landed"
		end
		local truePos = BallPhysics.positionAt(path, input.t)
		if opts.fromClient then
			if (truePos - input.ball).Magnitude > Config.Net.BallTolerance then
				return false, "ballpos"
			end
		else
			input.ball = truePos
		end
	end

	if opts.fromClient then
		local root = TS.getRoot(entity)
		if not root then
			return false, "noroot"
		end
		if (root.Position - input.root).Magnitude > Config.Net.RootTolerance then
			return false, "rootpos"
		end
	end

	local team = entity.team
	local ok, why, third = HitLogic.canTouch(BS.touch, team, entity.id, action, TS.teamSize)
	if not ok then
		return false, why
	end

	-- an active ability's window (Iron Wall, Turnabout) covers this touch
	local armed = (entity.abilityUntil or -1) >= input.t - 0.05
	local ctx = {
		side = Court.sideOf(team),
		team = team,
		teamSize = TS.teamSize,
		seq = BS.seq,
		ballVel = BS.state == "Flight" and BallPhysics.velocityAt(BS.path, input.t) or Vector3.zero,
		lastHit = BS.lastHit,
		thirdTouch = third,
		touchNumber = HitLogic.touchNumber(BS.touch, team),
		stats = entity.charStats,
		ability = entity.ability,
		groundY = TS.groundY(entity),
		stamina = TS.staminaOf(team),
		forceQuality = opts.forceQuality,
		ironWall = action == "Block" and entity.ability == "IronWall" and armed or nil,
		enemyPoints = (MS.scores or {})[Court.other(team)] or 0,
		teamBoost = (TS.rallyUntil[team] or -1) >= input.t - 0.05 or nil,
		counter = entity.ability == "Counter" and (entity.counter or 0) or nil,
		turnabout = entity.ability == "Turnabout" and armed or nil,
	}
	local computed, result = HitLogic.compute(input, ctx)
	if not computed then
		return false, result
	end

	local previous = BS.lastHit
	local meta = result.meta
	meta.id = entity.id
	meta.name = entity.name
	meta.team = team
	meta.t = input.t
	local touch = HitLogic.nextTouch(BS.touch, team, entity.id, action)
	BS.launch(result.launch, meta, touch)

	-- stamina: the guard meter only ever changes here
	if meta.drain then
		local broke = TS.drainStamina(team, meta.drain)
		if broke or meta.breaks then
			Net.get("Announce"):FireAllClients({ kind = "Break", team = team, id = entity.id, name = entity.name })
		end
	end
	if meta.kmh and (meta.hitType == "Spike" or meta.hitType == "JumpServe") then
		entity.stats.topKmh = math.max(entity.stats.topKmh or 0, meta.kmh)
	end
	-- abilities the touch used up or charged
	if meta.turnabout then
		HitService.setAbilityWindow(entity, -1) -- spent: the next set is a set again
	end
	if meta.counterGain then
		TS.setCounter(entity, math.min(100, (entity.counter or 0) + meta.counterGain))
	elseif meta.counterRelease then
		TS.setCounter(entity, 0)
	end

	if entity.isBot and meta.knock then
		reg.BotService.knockback(entity, meta.knock)
	end
	if action == "Serve" or action == "Underhand" then
		MS.onServeHit(entity)
	end
	if entity.player then
		reg.ProfileService.tutorialStep(entity.player, Tutorial.stepsFor(meta.hitType))
	end
	MS.onHit(entity, meta, previous)
	return true
end

function HitService.onRequest(plr, req)
	if type(req) ~= "table" then
		return
	end
	if rateLimited(plr) then
		return
	end
	local TS = reg.TeamService
	local entity = TS.entityForPlayer(plr)
	local seq = req.seq
	local function reject(reason)
		if type(seq) == "number" then
			Net.get("HitReject"):FireClient(plr, seq, reason)
		end
	end
	if not entity or not TS.inMatch then
		return reject("nomatch")
	end
	intentAt[entity.id] = os.clock()
	if not VALID[req.action] or not finiteNumber(req.t) or not finiteNumber(seq) then
		return reject("bad")
	end
	if not Util.isFiniteVector(req.root) or not Util.isFiniteVector(req.ball) then
		return reject("bad")
	end
	local targetId = nil
	if type(req.targetId) == "string" and #req.targetId < 24 then
		local target = TS.getEntity(req.targetId)
		if target and target.team == entity.team then
			targetId = req.targetId
		end
	end
	local energy = 0
	if entity.ability == "Azure" then
		energy = num(req.energy, 0, 1.4, 0)
	end
	local H = Config.Hits
	local input = {
		action = req.action,
		t = req.t,
		root = req.root,
		ball = req.ball,
		vy = num(req.vy, -200, 200, 0),
		grounded = req.grounded == true,
		diving = req.diving == true,
		assist = req.assist == true,
		stanceAge = num(req.stanceAge, 0, 2, 0.25),
		energy = energy,
		setType = SET_TYPES[req.setType] and req.setType or nil,
		targetId = targetId,
		tossHeight = num(req.tossHeight, H.TossLow, H.TossHighMax, H.TossLow),
		tossForward = num(req.tossForward, 0, 1, 0),
	}
	local ok, why = HitService.process(entity, input, { seq = seq, fromClient = true })
	if not ok then
		reject(why)
	end
end

-- Bots act through the same pipeline.
function HitService.botAction(entity, action, extra)
	extra = extra or {}
	local TS = reg.TeamService
	local root = TS.getRoot(entity)
	local hum = TS.getHumanoid(entity)
	if not root or not hum then
		return false
	end
	local input = {
		action = action,
		t = extra.t or Util.now(),
		root = root.Position,
		ball = extra.ball or root.Position,
		vy = root.AssemblyLinearVelocity.Y,
		grounded = hum.FloorMaterial ~= Enum.Material.Air,
		diving = extra.diving == true,
		assist = false,
		stanceAge = extra.stanceAge or 0.25,
		energy = extra.energy or 0,
		setType = extra.setType,
		targetId = extra.targetId,
		tossHeight = extra.tossHeight,
		tossForward = extra.tossForward,
	}
	return (HitService.process(entity, input, { forceQuality = extra.quality }))
end

function HitService.fx(entityId, kind, extra, exceptPlayer)
	local remote = Net.get("ActionFX")
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= exceptPlayer then
			remote:FireClient(p, entityId, kind, extra)
		end
	end
end

local function writeAbility(entity, name, value)
	local model = reg.TeamService.getModel(entity)
	if model then
		model:SetAttribute(name, value)
	end
	if entity.player then
		entity.player:SetAttribute(name, value)
	end
end

-- An active ability's window ends at `untilT` (shared clock; -1 when it's spent).
function HitService.setAbilityWindow(entity, untilT)
	entity.abilityUntil = untilT
	writeAbility(entity, "AbilityUntil", untilT)
end

-- Active abilities (Iron Wall, Turnabout, Rally Cry): start one if it's off cooldown. The window
-- and the cooldown are written onto the character (and the player) as shared-clock times for
-- every client's HUD and effects; Rally Cry also boosts the whole team for the window.
-- Returns true when it started.
function HitService.activateAbility(entity)
	local def = entity and entity.ability and Config.Abilities[entity.ability]
	if not def or not def.Active then
		return false
	end
	local now = Util.now()
	if now < (entity.abilityReadyAt or 0) then
		return false
	end
	entity.abilityReadyAt = now + def.Cooldown
	writeAbility(entity, "AbilityReadyAt", entity.abilityReadyAt)
	HitService.setAbilityWindow(entity, now + def.Duration)
	if entity.ability == "RallyCry" then
		reg.TeamService.rally(entity.team, entity.abilityUntil)
	end
	HitService.fx(entity.id, "Ability", entity.ability, entity.player) -- the player already shows it
	return true
end

function HitService.init(r)
	reg = r
	Net.get("HitRequest").OnServerEvent:Connect(HitService.onRequest)
	Net.get("ActionFX").OnServerEvent:Connect(function(plr, kind, extra)
		if kind == "Ability" then
			local e = reg.TeamService.entityForPlayer(plr)
			local phase = reg.MatchService.phase
			if e and (phase == "Rally" or phase == "Serving") then
				HitService.activateAbility(e)
			end
			return
		end
		if type(kind) ~= "string" or not FX_KINDS[kind] or rateLimited(plr) then
			return
		end
		local e = reg.TeamService.entityForPlayer(plr)
		if not e then
			return
		end
		if INTENT[kind] then
			intentAt[e.id] = os.clock()
		end
		if kind == "Whiff" then
			missedAt[e.id] = os.clock()
		end
		if kind == "Block" then
			reg.ProfileService.tutorialStep(plr, { "block" }) -- a block jump ticks the tutorial's block
		end
		if type(extra) ~= "string" or #extra > 16 then
			extra = nil
		end
		HitService.fx(e.id, kind, extra, plr)
	end)
	Players.PlayerRemoving:Connect(function(plr)
		requestLog[plr] = nil
		intentAt["P_" .. tostring(plr.UserId)] = nil
		missedAt["P_" .. tostring(plr.UserId)] = nil
	end)
end

return HitService
