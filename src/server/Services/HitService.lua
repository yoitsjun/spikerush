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
local Breakthrough = require(Shared.Breakthrough)
local Mutators = require(Shared.Mutators)
local Cups = require(Shared.Cups)
local Halloween = require(Shared.Halloween)

local HitService = {}
local reg

local VALID = { Bump = true, Set = true, Spike = true, Feint = true, Block = true, Toss = true, Serve = true, Underhand = true }
local SET_TYPES = { Open = true, Quick = true, Back = true }
local FX_KINDS = { Slide = true, Block = true, Whiff = true, Jump = true, Charge = true, ChargeEnd = true, Stance = true, Approach = true, Prowl = true, Leap = true, ProwlEnd = true, Dive = true, Rush = true, RushEnd = true, RushJump = true, Hover = true, HoverEnd = true }
local INTENT = { Slide = true, Block = true, Whiff = true, Jump = true, Charge = true, Stance = true, Approach = true, Prowl = true, Leap = true, Dive = true, Rush = true, RushJump = true, Hover = true }
local FERAL = Config.Abilities.Feral
-- A player's attacks and empty swings off the floor count until their root is back down (the
-- Heartbeat in init): Thunder Spiker's second one in a jump hits harder. Swings aren't limited.
local airSwings = {} -- entity id -> swings this jump
local SWING_ACTIONS = { Spike = true, Feint = true, Serve = true }
local LEAP_SLACK = 0.15 -- gauge a leap may claim over the charge the server saw (network jitter)
local LEAP_LIFE = 3 -- seconds a leap's gauge stays good for its spike
local requestLog = {}
local intentAt = {} -- entityId -> os.clock() of the player's last attempt to play the ball
local missedAt = {} -- entityId -> os.clock() of the player's last whiffed swing or dig
-- Feral Leap: when the server heard a player start charging ("Prowl"), and the most gauge their
-- leap can have ("Leap": the time held, for the one spike off that leap)
local prowlAt = {} -- entityId -> os.clock()
local leapCap = {} -- entityId -> { gauge, at }
-- Corona: when the server heard a player start a Sundive, and how high he was then; a spike's
-- claimed drop only counts if one started just before it, and no further than he really fell
local diveAt = {} -- entityId -> os.clock()
local diveFrom = {} -- entityId -> root height when the dive started
local DIVE_LIFE = 1.5
-- Squall: when the server heard a player rush (Tailwind: her position lags more), start a hover,
-- and the most charge that hover gave once it ended (Eye of the Storm: a spike claims no more)
local SQUALL = Config.Abilities.Squall
local rushAt = {} -- entityId -> os.clock()
local hoverAt = {} -- entityId -> os.clock()
local hoverCap = {} -- entityId -> { gale, at }
local RUSH_LIFE, HOVER_LIFE = 2, 1.5
local slowedSeq = nil -- the ball path Updraft last slowed (once a set)
-- Ironclad: when the server heard him leave the floor, and whether that was before his team's set
-- (Forge: his spike claims no more charge than the time he's been up)
local IRON = Config.Abilities.Ironclad
local ironJumpAt = {} -- entityId -> os.clock()
local ironEarly = {} -- entityId -> bool
local IRON_LIFE = 4

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

-- Ability state on the character and the player (every client's HUD and effects, and the
-- player's own prediction).
local function writeAbility(entity, name, value)
	local model = reg.TeamService.getModel(entity)
	if model then
		model:SetAttribute(name, value)
	end
	if entity.player then
		entity.player:SetAttribute(name, value)
	end
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
		-- (Corona: a Sundive moves him so fast the server's copy of him lags further behind; one
		-- playing both, a dive and a rush in one rally: the larger slack)
		local slack = 1
		if TS.has(entity, "Corona") and diveAt[entity.id] and os.clock() - diveAt[entity.id] <= DIVE_LIFE then
			slack = math.max(slack, Config.Abilities.Corona.DiveRootSlack)
		end
		if TS.has(entity, "Squall") and rushAt[entity.id] and os.clock() - rushAt[entity.id] <= RUSH_LIFE then
			slack = math.max(slack, SQUALL.RushRootSlack) -- (Tailwind: she rushes too fast for the server's copy of her)
		end
		if (root.Position - input.root).Magnitude > Config.Net.RootTolerance * slack then
			return false, "rootpos"
		end
	end

	local team = entity.team
	local ok, why, third = HitLogic.canTouch(BS.touch, team, entity.id, action, TS.teamSize)
	if not ok then
		-- the four-touch fault: a player's swing or set that really met their team's fourth ball
		-- (the same hit check, with the count left out) gives the other team the point
		if opts.fromClient and HitLogic.isFourthTouchFault(why, action) then
			local fctx = {
				side = Court.sideOf(team),
				team = team,
				teamSize = TS.teamSize,
				seq = BS.seq,
				ballVel = BallPhysics.velocityAt(BS.path, input.t),
				lastHit = BS.lastHit,
				touchNumber = 3,
				stats = entity.charStats,
				ability = entity.ability,
				abilities = entity.abilitySet,
				abilityList = entity.abilities,
				groundY = TS.groundY(entity),
				stamina = TS.staminaOf(team),
				hex = Halloween.effects(entity.hex),
			}
			if HitLogic.compute(input, fctx) then
				MS.touchFault(entity, "FourTouches", input.ball)
				return false, "fourth"
			end
		end
		return false, why
	end

	-- an active ability's own window (Iron Wall, Turnabout, Storm Call...) covers this touch
	local function armed(name)
		return TS.has(entity, name) and TS.windowOf(entity, name) >= input.t - 0.05 or nil
	end
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
		ability = entity.ability, -- its own (the only one its breakthroughs grow)
		abilities = entity.abilitySet, -- every one it plays (the Halloween Match's ability cards too)
		abilityList = entity.abilities, -- the same in order (who owns an input two of them claim)
		groundY = TS.groundY(entity),
		stamina = TS.staminaOf(team),
		forceQuality = opts.forceQuality,
		ironWall = action == "Block" and armed("IronWall") or nil,
		ironclad = TS.has(entity, "Ironclad") and HitLogic.ironLives(entity.ironLives) > 0 or nil,
		ironCracks = TS.has(entity, "Ironclad") and (entity.ironCracks or 0) or nil, -- (the stop that shatters it pops up)
		breakLevel = entity.breakLevel,
		awakened = TS.has(entity, "Ironclad") and HitLogic.ironLives(entity.ironLives) == 0 or nil,
		enemyPoints = (MS.scores or {})[Court.other(team)] or 0,
		teamBoost = (TS.rallyUntil[team] or -1) >= input.t - 0.05 and TS.rallyBoost[team] or nil, -- (its caller's grown boost)
		dictate = (TS.dictateUntil[team] or -1) >= input.t - 0.05 or nil, -- (the Tyrant's Stat Hijack, his team)
		dictated = (TS.dictateUntil[Court.other(team)] or -1) >= input.t - 0.05 and TS.dictateSteal[Court.other(team)] or nil, -- (against this team: his steal)
		tyrantOn = armed("Tyrant"), -- (Absolute Toss: his sets while it's on)
		grounded = entity.grounded or nil, -- (Sovereign's Guard)
		sunOn = TS.has(entity, "Sunshine") and (entity.sunUntil or -1) >= input.t - 0.05 or nil,
		counter = TS.has(entity, "Counter") and (entity.counter or 0) or nil,
		lift = TS.has(entity, "Skyward") and entity.lift or nil,
		turnabout = armed("Turnabout"),
		firstStrike = TS.has(entity, "Feral") and not entity.firstStrikeUsed or nil,
		auto = entity.isBot or nil,
		chain = TS.chain[team] or 0,
		coronaOn = armed("Corona"),
		coronaStacks = TS.has(entity, "Corona") and (entity.coronaStacks or 0) or nil,
		squallOn = armed("Squall"),
		stormOn = armed("Thunder"),
		bloodlust = armed("Feral"), -- (Feral Leap's Bloodlust: the gauge may go past full)
		static = TS.has(entity, "Thunder") and (entity.static or 0) or nil,
		mods = Cups.statMods(ReplicatedStorage:GetAttribute("CupMods")),
		mut = Mutators.live(), -- a custom match's modifiers (Config.Mutators)
		hex = Halloween.effects(entity.hex), -- the Halloween Match's cards that hit this character
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
		HitService.setAbilityWindow(entity, "Turnabout", -1) -- spent: the next set is a set again (its window only)
	end
	if meta.bloodlustSpent then
		HitService.setAbilityWindow(entity, "Feral", -1) -- Bloodlust: its one charged hit is done (the cooldown runs on)
	end
	if meta.reaction then
		TS.setChain(team, (TS.chain[team] or 0) + 1) -- the next explosion this rally is bigger
	end
	if TS.has(entity, "Thunder") and meta.thunder and (meta.hitType == "Spike" or meta.hitType == "JumpServe") then
		-- Static Charge: one more for his next spikes this rally
		TS.setStatic(entity, math.min(Config.Abilities.Thunder.StaticMax, (entity.static or 0) + 1))
	end
	if TS.has(entity, "Ironclad") then
		-- Bulwark: every attack a shield stops cracks it and the second shatters it (none left:
		-- awakened); awakened, every touch fills Intimidation, and full brings the shields back
		local lives = HitLogic.ironLives(entity.ironLives)
		-- (only Bulwark's own blocks: an Iron Wall up takes the spike whole and leaves his shield be)
		if lives > 0 and meta.bulwark then
			local left, cracks = HitLogic.ironAfterBlock(lives, entity.ironCracks, meta)
			if left ~= lives or cracks ~= (entity.ironCracks or 0) then
				TS.setIron(entity, left, entity.intimidation or 0, cracks)
			end
		end
		-- below full shields (a set starts with StartLives), every touch fills Intimidation; full
		-- brings all of them (a stuff block fills it more; his kills are added when the point's
		-- judged: MatchService)
		lives = HitLogic.ironLives(entity.ironLives)
		if lives < IRON.Lives then
			local m = (entity.intimidation or 0) + IRON.MeterPerTouch + (meta.hitType == "Block" and meta.outcome == "Stuff" and IRON.MeterBonus or 0)
			if m >= 100 then
				TS.setIron(entity, IRON.Lives, 0)
			else
				TS.setIron(entity, lives, m, entity.ironCracks)
			end
		end
	end
	if meta.sunshine then
		-- Sunshine: a perfect dig of hers lights it (again from now)
		local lvl = entity.ability == "Sunshine" and entity.breakLevel or 0
		TS.setSunshine(entity, now + Breakthrough.ab("Sunshine", "SunDuration", lvl))
	end
	if meta.hitType == "Spike" or meta.hitType == "JumpServe" then
		-- Sovereign's Guard: an attack faster than GuardKmh at a team with the Tyrant grounds its
		-- hitter for their next attack; this attack spent any grounding it had
		local guarded = false
		if (meta.kmh or 0) > Config.Abilities.Tyrant.GuardKmh then
			for _, other in ipairs(TS.members(Court.other(team))) do
				if TS.has(other, "Tyrant") then
					guarded = true
					break
				end
			end
		end
		TS.setGrounded(entity, guarded)
	end
	if meta.counterGain then
		TS.setCounter(entity, math.min(100, (entity.counter or 0) + meta.counterGain))
	elseif meta.counterRelease then
		TS.setCounter(entity, 0) -- her spike released it
	end
	if meta.zero or meta.firstStrike then
		-- the freeze frame: the hitter hangs where they hit it while the ball holds on the hand
		local root = TS.getRoot(entity)
		if root and not root.Anchored then
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
			task.delay(result.launch.hold or 0, function()
				if root.Parent then
					root.Anchored = false
				end
			end)
		end
	end
	if meta.liftGain and TS.has(entity, "Skyward") then
		-- Skyward: the spike raised her hitting point (the HUD shows her new peak)
		local lvl = entity.ability == "Skyward" and entity.breakLevel or 0
		local before = HitLogic.skyLift(entity.lift, lvl)
		local after = HitLogic.skyLift(before + meta.liftGain, lvl)
		if after > before then
			TS.setLift(entity, after)
		end
		-- her highest spike this set, right where she met it (the marker stays there)
		if meta.height and meta.height > (entity.peakM or 0) then
			TS.setPeak(entity, meta.height, input.ball.Y, input.ball.Z)
		end
	end
	if meta.firstStrike then
		-- Feral Leap's first full charge of the match is spent (the client predicts from this too)
		entity.firstStrikeUsed = true
		writeAbility(entity, "FirstStrikeUsed", true)
	end

	if entity.isBot and meta.knock then
		reg.BotService.knockback(entity, meta.knock)
	end
	if action == "Serve" or action == "Underhand" then
		MS.onServeHit(entity)
	end
	MS.onHit(entity, meta, previous)
	return true
end

-- Off the floor: the root above where it stands.
local function offFloor(entity)
	local root = reg.TeamService.getRoot(entity)
	return root ~= nil and root.Position.Y - reg.TeamService.groundY(entity) > 0.35
end

-- Count a swing in the air. Returns true (swings aren't limited), and whether it's the jump's
-- second or later.
local function countSwing(entity)
	if not offFloor(entity) then
		return true, false
	end
	local n = airSwings[entity.id] or 0
	airSwings[entity.id] = n + 1
	return true, n == 1 -- only the jump's second swing (the owner: the third and later hit as usual)
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
	if TS.has(entity, "Azure") then
		energy = num(req.energy, 0, 1.4, 0)
	end
	-- Feral Leap: no more gauge than the charge the server saw held before the leap, for the one
	-- spike (or jump serve) off that leap
	local gauge, toward = 0, false
	local cap = leapCap[entity.id]
	if TS.has(entity, "Feral") and (req.action == "Spike" or req.action == "Serve") and cap and os.clock() - cap.at <= LEAP_LIFE then
		gauge = math.min(num(req.gauge, 0, FERAL.OverMax, 0), cap.gauge) -- (past 1 only in Bloodlust: the cap)
		toward = req.toward == true
		leapCap[entity.id] = nil
	end
	-- one swing a jump (Thunder Spiker: two, the second harder)
	local second = false
	if SWING_ACTIONS[req.action] then
		local allowed
		allowed, second = countSwing(entity)
		if not allowed then
			return reject("swings")
		end
	end
	-- Corona: Sundive's drop needs a dive the server heard start, and he can't claim more than he
	-- fell since (a little slack: the server's copy of him lags)
	local sundive = 0
	if TS.has(entity, "Corona") and (req.action == "Spike" or req.action == "Serve") and diveAt[entity.id] and os.clock() - diveAt[entity.id] <= DIVE_LIFE then
		local fell = (diveFrom[entity.id] or 0) - (Util.isFiniteVector(req.root) and req.root.Y or 0)
		sundive = math.min(num(req.sundive, 0, Config.Abilities.Corona.DiveMaxDist, 0), math.max(0, fell + 3))
	end
	-- Squall: a hover's charge (its power and how deep it goes) needs a hover the server heard, and
	-- no more charge than it lasted (Eye of the Storm)
	local gale = nil
	if TS.has(entity, "Squall") and (req.action == "Spike" or req.action == "Serve") then
		local now = os.clock()
		local cap = hoverCap[entity.id]
		local most = nil
		if cap and now - cap.at <= HOVER_LIFE then
			most = cap.gale
		elseif hoverAt[entity.id] and now - hoverAt[entity.id] <= SQUALL.HoverMax + HOVER_LIFE then
			most = math.clamp((now - hoverAt[entity.id]) / SQUALL.ChargeTime + SQUALL.HoverSlack, 0, 1)
		end
		if most then
			gale = math.min(num(req.gale, 0, 1, 0), most)
		end
		hoverCap[entity.id], hoverAt[entity.id] = nil, nil
	end
	-- Ironclad (awakened): Forge's charge needs a jump the server heard, no more than he's been up
	local metal, early = nil, nil
	if TS.has(entity, "Ironclad") and req.action == "Spike" and ironJumpAt[entity.id] and os.clock() - ironJumpAt[entity.id] <= IRON_LIFE then
		metal = math.min(num(req.metal, 0, 1, 0), (os.clock() - ironJumpAt[entity.id]) / IRON.ChargeTime + IRON.ChargeSlack)
		early = req.early == true and ironEarly[entity.id] == true
	end
	-- holding Spike in the air is one ability's (HitLogic.INPUTS.AirSpike: the first of Azure's
	-- charge and Squall's hover in the character's order), and a Sundive is neither
	if energy > 0 and gale ~= nil then
		if HitLogic.inputOwner(entity.abilities, "AirSpike") == "Squall" then
			energy = 0
		else
			gale = nil
		end
	end
	if sundive > 0 then
		energy = 0
		gale = nil
	end
	local H = Config.Hits
	local input = {
		second = second or nil,
		metal = metal,
		early = early,
		gale = gale,
		action = req.action,
		t = req.t,
		root = req.root,
		ball = req.ball,
		vy = num(req.vy, -200, 200, 0),
		tipDepth = req.action == "Feint" and num(req.tipDepth, 0, 1, 0) or nil, -- (a deep tip: how long the tip button was held)
		sundive = sundive,
		grounded = req.grounded == true,
		diving = req.diving == true,
		assist = req.assist == true,
		stanceAge = num(req.stanceAge, 0, 2, 0.25),
		energy = energy,
		setType = SET_TYPES[req.setType] and req.setType or nil,
		targetId = targetId,
		tossHeight = num(req.tossHeight, H.TossLow, H.TossHighMax, H.TossLow),
		tossForward = num(req.tossForward, 0, 1, 0),
		aimDepth = req.action == "Set" and num(req.aimDepth, H.SetAimMin, H.SetAimMax, nil) or nil,
		aimHeight = req.action == "Set" and num(req.aimHeight, H.SetAimLowY, H.SetAimHighY, nil) or nil,
		gauge = gauge,
		toward = toward,
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
		gauge = extra.gauge or 0,
		toward = extra.toward == true,
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

-- An active ability's window ends at `untilT` (shared clock; -1 when it's spent). Each active has
-- its own ("AbilityUntil_<Name>"); the old single "AbilityUntil" follows the character's first.
function HitService.setAbilityWindow(entity, name, untilT)
	if not entity or type(name) ~= "string" then
		return
	end
	entity.windows = entity.windows or {}
	entity.windows[name] = untilT
	writeAbility(entity, "AbilityUntil_" .. name, untilT)
	if reg.TeamService.firstActive(entity) == name then
		writeAbility(entity, "AbilityUntil", untilT)
	end
end

-- One active starts: its cooldown, its window, what it does at once. Breakthroughs grow the
-- character's own ability only (a card's plays at +0).
local function startAbility(entity, name, def, now)
	local TS = reg.TeamService
	local lvl = name == entity.ability and entity.breakLevel or 0
	entity.readyAt = entity.readyAt or {}
	local mut = Mutators.live()
	entity.readyAt[name] = now + Breakthrough.cooldown(name, lvl) * (mut and mut.cooldown or 1) -- (shorter with breakthroughs; a custom match's Cooldowns)
	writeAbility(entity, "AbilityReadyAt_" .. name, entity.readyAt[name])
	if TS.firstActive(entity) == name then
		writeAbility(entity, "AbilityReadyAt", entity.readyAt[name])
	end
	local untilT = now + Breakthrough.ab(name, "Duration", lvl) -- (Iron Wall and Rally Cry last longer with breakthroughs)
	HitService.setAbilityWindow(entity, name, untilT)
	if name == "RallyCry" then
		TS.rally(entity.team, untilT, Breakthrough.ab("RallyCry", "Boost", lvl)) -- (a stronger boost with breakthroughs)
	elseif name == "Tyrant" then
		TS.dictate(entity.team, untilT, Breakthrough.ab("Tyrant", "Steal", lvl)) -- Emperor's Dictate: both teams' stats, and the HUDs
	elseif name == "Corona" then
		-- the flare, and one more use for the penalty once it's off
		TS.setCorona(entity, untilT, math.min(def.MaxStacks, (entity.coronaStacks or 0) + 1))
	elseif name == "Squall" then
		TS.boostWindow(entity, untilT, "Squall") -- faster, and Attack with it
	end
	HitService.fx(entity.id, "Ability", name, entity.player) -- the player already shows it
end

-- Active abilities (Storm Call, Corona, Squall, Iron Wall, Turnabout, Rally Cry), each on its own
-- window and cooldown. With `name`, that one starts if the character plays it and it's off
-- cooldown; without, every one it plays that's ready does, in its order (its own, then its
-- Halloween cards': the cards "stack", the owner, 2026-10-15, so one press pops them all). The
-- windows and cooldowns are written onto the character (and the player) as shared-clock times for
-- every client's HUD and effects; Rally Cry also boosts the whole team for the window.
-- Returns whether any started, and the names that did (in order).
function HitService.activateAbility(entity, name)
	local fired = {}
	if not entity then
		return false, fired
	end
	local now = Util.now()
	for _, ab in ipairs(entity.abilities or { entity.ability }) do
		local def = Config.Abilities[ab]
		if def and def.Active and (name == nil or name == ab) and now >= reg.TeamService.readyAtOf(entity, ab) then
			startAbility(entity, ab, def, now)
			table.insert(fired, ab)
		end
	end
	return #fired > 0, fired
end

-- A remote's ability name: an active the character plays, or nil.
local function heldActive(entity, name)
	local def = type(name) == "string" and Config.Abilities[name]
	if def and def.Active and reg.TeamService.has(entity, name) then
		return name
	end
	return nil
end

function HitService.init(r)
	reg = r
	Net.get("HitRequest").OnServerEvent:Connect(HitService.onRequest)
	-- back on the floor: the next jump's swings
	game:GetService("RunService").Heartbeat:Connect(function()
		for id in pairs(airSwings) do
			local e = reg.TeamService.getEntity(id)
			if not e or not offFloor(e) then
				airSwings[id] = nil
			end
		end
	end)
	-- a setter's aim goes to their teammates only (SetterAim); the other team never hears it
	local aimAt = {}
	Net.get("SetAim").OnServerEvent:Connect(function(plr, depth, height)
		local now = os.clock()
		if aimAt[plr] and now - aimAt[plr] < 0.08 then
			return
		end
		aimAt[plr] = now
		local TS = reg.TeamService
		local entity = TS.entityForPlayer(plr)
		if not entity or not TS.inMatch then
			return
		end
		local H = Config.Hits
		local d = num(depth, H.SetAimMin, H.SetAimMax, nil)
		local y = d and num(height, H.SetAimLowY, H.SetAimHighY, H.SetArriveY) or nil
		entity.aimDepth, entity.aimHeight = d, y
		for _, e in ipairs(TS.members(entity.team)) do
			if e.player and e.player ~= plr then
				Net.get("SetAim"):FireClient(e.player, entity.id, d or false, y)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(plr)
		aimAt[plr] = nil
	end)
	Net.get("ActionFX").OnServerEvent:Connect(function(plr, kind, extra, which)
		if kind == "Ability" then
			-- (`extra`: one active by name; none: every one that's ready)
			local e = reg.TeamService.entityForPlayer(plr)
			local phase = reg.MatchService.phase
			if e and (phase == "Rally" or phase == "Serving") and (extra == nil or heldActive(e, extra)) then
				HitService.activateAbility(e, extra)
			end
			return
		end
		if kind == "TeamAbility" then
			-- a player pops an AI teammate's active abilities (bots on a player's team never do;
			-- `which`: one by name, none: every one that's ready)
			local e = reg.TeamService.entityForPlayer(plr)
			local mate = type(extra) == "string" and reg.TeamService.getEntity(extra)
			local phase = reg.MatchService.phase
			if e and mate and mate.isBot and mate.team == e.team and (phase == "Rally" or phase == "Serving") and not rateLimited(plr) then
				if which == nil or heldActive(mate, which) then
					HitService.activateAbility(mate, which)
				end
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
			countSwing(e) -- an empty swing in the air is the jump's swing too
		end
		if reg.TeamService.has(e, "Corona") and kind == "Dive" then
			-- Sundive: his next spike may claim the dive's drop
			diveAt[e.id] = os.clock()
			local root = reg.TeamService.getRoot(e)
			diveFrom[e.id] = root and root.Position.Y or 0
		end
		if reg.TeamService.has(e, "Ironclad") and kind == "Jump" then
			-- Forge: when he left the floor, and whether his team had set yet (a set only just made
			-- still counts as after his jump: EarlyGrace)
			local last = reg.BallService.lastHit
			ironJumpAt[e.id] = os.clock()
			ironEarly[e.id] = not (last and last.hitType == "Set" and last.team == e.team and Util.now() - (tonumber(last.t) or 0) > IRON.EarlyGrace)
		end
		if reg.TeamService.has(e, "Squall") then
			local now = os.clock()
			if kind == "Rush" or kind == "RushJump" then
				rushAt[e.id] = now
			end
			if kind == "RushJump" and reg.MatchService.phase == "Rally" then
				-- Downdraft: the other team runs slower for a moment
				local untilT = Util.now() + SQUALL.SlowTime
				for _, o in ipairs(reg.TeamService.members(Court.other(e.team))) do
					for _, inst in ipairs({ reg.TeamService.getModel(o) or false, o.player or false }) do
						if inst then
							inst:SetAttribute("SlowUntil", untilT)
						end
					end
				end
				-- Updraft: a teammate's set slows from the moment she sprang (her client sends it,
				-- and worked out the same slowed path to spring at)
				local BS = reg.BallService
				if BS.state == "Flight" and BS.path and slowedSeq ~= BS.seq and HitLogic.updraftCanSlow(BS.lastHit, e.team, e.id) then
					local tNow = Util.now()
					local t = type(extra) == "string" and tonumber(extra) or nil
					if not t or math.abs(t - tNow) > 0.6 then
						t = tNow
					end
					if t >= BallPhysics.startTime(BS.path) and t < BS.path.landing.t - 0.05 then
						BS.retime(HitLogic.updraftLaunch(BS.path, t, SQUALL.SetSlow))
						slowedSeq = BS.seq
					end
				end
			elseif kind == "Hover" then
				hoverAt[e.id] = now
				hoverCap[e.id] = nil
			elseif kind == "HoverEnd" and hoverAt[e.id] then
				hoverCap[e.id] = { gale = math.clamp((now - hoverAt[e.id]) / SQUALL.ChargeTime + SQUALL.HoverSlack, 0, 1), at = now }
				hoverAt[e.id] = nil
			end
		end
		if reg.TeamService.has(e, "Feral") then
			-- Feral Leap: the charge starts, then the leap goes with what was held
			if kind == "Prowl" then
				prowlAt[e.id] = os.clock()
				leapCap[e.id] = nil
			elseif kind == "Leap" then
				-- (Bloodlust on: the charge could go past full, to OverMax)
				local held = prowlAt[e.id] and os.clock() - prowlAt[e.id] or 0
				local over = reg.TeamService.windowOf(e, "Feral") >= Util.now() - 0.1
				leapCap[e.id] = { gauge = math.min(HitLogic.feralGauge(held, FERAL.ChargeTime, over) + LEAP_SLACK, over and FERAL.OverMax or 1), at = os.clock() }
				prowlAt[e.id] = nil
			end
		end
		if type(extra) ~= "string" or #extra > 16 then
			extra = nil
		end
		HitService.fx(e.id, kind, extra, plr)
	end)
	Players.PlayerRemoving:Connect(function(plr)
		local id = "P_" .. tostring(plr.UserId)
		requestLog[plr] = nil
		intentAt[id] = nil
		missedAt[id] = nil
		prowlAt[id] = nil
		leapCap[id] = nil
		diveAt[id] = nil
		diveFrom[id] = nil
		rushAt[id] = nil
		hoverAt[id] = nil
		hoverCap[id] = nil
		ironJumpAt[id] = nil
		ironEarly[id] = nil
	end)
end

return HitService
