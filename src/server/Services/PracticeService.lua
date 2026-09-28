-- Practice: automated drills on the court (shared/Tutorial). A practice lobby plays here instead
-- of a match (MatchService.start). Nothing is a rally: every rep puts the ball where the drill
-- needs it, judges one touch or one landing, and resets. The bots stand still (BotService skips
-- them while MatchService.practice is set); a drill moves only the one it needs.
--   spike  a bot setter on your side sets you: your spike has to land in their court
--   block  their attacker at the net spikes: your block has to touch it
--   serve  the ball is in your hands: the serve has to land in their court (in a row)
--   dig    their attacker spikes at you: your receive has to keep it up (in a row)
-- The tutorial runs all four in order and ticks each finished drill (ProfileService's reward
-- once all four are done); a single drill from the Practice tab runs once to its goal.
-- MatchService.practice (in the match state) tells the clients' coach panel what's on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Util = require(Shared.Util)
local HitLogic = require(Shared.HitLogic)
local BallPhysics = require(Shared.BallPhysics)
local Tutorial = require(Shared.Tutorial)

local PracticeService = {}
local reg

local C = Config.Court
local PR = Config.Practice
local P = Config.Player
local SPM = Config.Scale.StudsPerMeter
local HOME, AWAY = "Home", "Away"

local rep = nil -- the rep in play: { drill, playerId, outcome = nil | true | false }
local rng = Random.new()

local function publish(status)
	local MS = reg.MatchService
	MS.practice = status
	MS.broadcast()
end

-- Stand an entity on a spot, facing the net.
local function place(e, spot)
	local TS = reg.TeamService
	local model = TS.getModel(e)
	if not model then
		return
	end
	local side = Court.sideOf(e.team)
	model:PivotTo(Court.facing(spot + Vector3.new(0, TS.groundY(e) + 0.2, 0), side))
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	if e.isBot then
		reg.BotService.onReset(e)
	end
end

-- The first member of `team` that isn't `exceptId` (the setter on your side, their attacker).
local function mate(team, exceptId)
	for _, e in ipairs(reg.TeamService.members(team)) do
		if e.id ~= exceptId then
			return e
		end
	end
	return nil
end

-- The setter's set: out of its hands along the open set's arc to your attack spot.
local function feedSet(setter, target)
	local root = reg.TeamService.getRoot(setter)
	local side = Court.sideOf(setter.team)
	local now = Util.now()
	local hand = Vector3.new(0, (root and root.Position.Y or P.RootGround) + 3.2, root and root.Position.Z or side * 0.9 * SPM)
	local v, g = HitLogic.setArc(hand, side, "Open")
	-- a pass came in first, so the set is the second touch and your spike the third
	local touch = HitLogic.nextTouch(HitLogic.nextTouch({ count = 0 }, setter.team, "Pass", "Bump"), setter.team, setter.id, "Set")
	reg.BallService.launch(BallPhysics.newLaunch(hand, v, Vector3.new(0, -g, 0), now), {
		hitType = "Set",
		setType = "Open",
		id = setter.id,
		name = setter.name,
		team = setter.team,
		targetId = target.id,
		quality = 1,
		t = now,
	}, touch)
end

-- Their attacker's spike: a jump at the net, then the ball off its hand at `kmh` onto `target`
-- (a spot on your floor).
local function attack(attacker, target, kmh)
	local TS = reg.TeamService
	local model = TS.getModel(attacker)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Jump = true
	end
	reg.HitService.fx(attacker.id, "Jump", "Spike")
	task.wait(PR.AttackWindup)
	local root = TS.getRoot(attacker)
	local side = Court.sideOf(attacker.team)
	local y = math.max(root and root.Position.Y + 3.4 or 0, C.NetTop + PR.AttackAboveNet)
	local p = Vector3.new(0, y, side * PR.AttackDepth)
	local g = Config.Ball.Gravity
	local T = (target - p).Magnitude / (kmh / 3.6 * SPM)
	local v = (target - p) / T + Vector3.new(0, 0.5 * g * T, 0)
	local now = Util.now()
	reg.BallService.launch(BallPhysics.newLaunch(p, v, Vector3.new(0, -g, 0), now), {
		hitType = "Spike",
		id = attacker.id,
		name = attacker.name,
		team = attacker.team,
		kmh = math.floor(kmh),
		t = now,
	}, HitLogic.nextTouch({ count = 0 }, attacker.team, attacker.id, "Spike"))
end

local function between(range)
	return range[1] + rng:NextNumber() * (range[2] - range[1])
end

-- A touch the drill counts (MatchService.onHit, only while practising).
function PracticeService.onHit(entity, meta)
	if not rep or rep.outcome ~= nil or entity.id ~= rep.playerId then
		return
	end
	local d = rep.drill.id
	if d == "block" and meta.hitType == "Block" then
		rep.outcome = true
	elseif d == "dig" and (meta.hitType == "Bump" or meta.hitType == "Set" or meta.hitType == "Free") then
		rep.outcome = not meta.fail and not meta.breaks and (meta.quality or 0) >= PR.DigQuality
	end
end

-- A landing: a spike or serve of yours in their court counts; for a block or a dig, the ball
-- getting down without your touch is a miss.
local function onDead(landing, flags, last)
	if not rep or rep.outcome ~= nil then
		return
	end
	local d = rep.drill.id
	if d == "spike" or d == "serve" then
		local ht = last and last.hitType
		local shot = (d == "spike" and ht == "Spike") or (d == "serve" and (ht == "Overhand" or ht == "Underhand" or ht == "JumpServe"))
		local theirs = landing.kind == "Floor" and not (flags and flags.underNet) and Court.inBounds(landing.pos) and Court.teamOnSide(Court.sideOfPoint(landing.pos)) == AWAY
		rep.outcome = last ~= nil and last.id == rep.playerId and shot and theirs
	else
		rep.outcome = false
	end
end

-- Everyone to their spots for a rep of `drill`: the ones it doesn't use stand back.
local function setUp(drill, me, setter, attacker)
	local home, away = Court.sideOf(HOME), Court.sideOf(AWAY)
	for _, e in ipairs(reg.TeamService.members(HOME)) do
		if e ~= me then
			place(e, Court.formationSpot("Defense", e.role, home))
		end
	end
	for _, e in ipairs(reg.TeamService.members(AWAY)) do
		place(e, Court.formationSpot("Defense", e.role, away))
	end
	local d = drill.id
	if d == "spike" then
		place(me, Court.formationSpot("Offense", "WS", home))
		if setter then
			place(setter, Court.formationSpot("Offense", "SE", home))
		end
	elseif d == "block" then
		place(me, Court.spot(home, P.BlockReach * 0.5, me.role))
		if attacker then
			place(attacker, Court.spot(away, PR.AttackDepth, attacker.role))
		end
	elseif d == "serve" then
		place(me, Court.serveSpot(home, me.role))
	elseif d == "dig" then
		place(me, Court.formationSpot("Receive", "WS", home))
		if attacker then
			place(attacker, Court.spot(away, PR.AttackDepth, attacker.role))
		end
	end
end

-- One drill to its goal. Returns true when it's done, false when practice stopped.
local function runDrill(drill, plr, status, stillOn)
	local TS, BS, MS = reg.TeamService, reg.BallService, reg.MatchService
	status.drill = drill.id
	status.count = 0
	status.goal = drill.goal
	status.inARow = drill.inARow
	status.finished = nil
	publish(status)
	MS.announce({ kind = "Drill", drill = drill.id, start = true, count = 0, goal = drill.goal })
	local count = 0
	while stillOn() do
		local me = TS.entityForPlayer(plr)
		local setter = me and mate(HOME, me.id)
		local attacker = mate(AWAY, nil)
		BS.hide()
		TS.fillStamina(HOME)
		MS.serverId = nil
		setUp(drill, me, setter, attacker)
		rep = { drill = drill, playerId = me.id, outcome = nil }
		MS.setPhase("PreServe", PR.FeedDelay)
		task.wait(PR.FeedDelay)
		if not stillOn() then
			break
		end
		local timeout = PR.RepTimeout
		if drill.id == "spike" and setter then
			MS.setPhase("Rally", 0)
			feedSet(setter, me)
		elseif drill.id == "block" and attacker then
			MS.setPhase("Rally", 0)
			attack(attacker, Vector3.new(0, Config.Ball.Radius, Court.sideOf(HOME) * between(PR.BlockTargetDepth)), between(PR.BlockKmh))
		elseif drill.id == "serve" then
			-- you serve: clients only take serve input (the toss, X, F) from the match's server
			MS.servingTeam = HOME
			MS.serverId = me.id
			BS.hold(me.id)
			MS.setPhase("Serving", PR.ServeTimeout)
			timeout = PR.ServeTimeout
		elseif drill.id == "dig" and attacker then
			MS.setPhase("Rally", 0)
			local root = TS.getRoot(me)
			local z = root and root.Position.Z or Court.formationSpot("Receive", "WS", Court.sideOf(HOME)).Z
			attack(attacker, Vector3.new(0, Config.Ball.Radius, z + (rng:NextNumber() * 2 - 1) * 1.5), between(PR.DigKmh))
		end
		local t0 = os.clock()
		while rep.outcome == nil and stillOn() and os.clock() - t0 < timeout do
			task.wait()
		end
		if not stillOn() then
			break
		end
		local outcome = rep.outcome
		rep.outcome = outcome == true -- settled: later touches and landings don't change it
		-- a serve you never made isn't a miss: the ball is offered again
		if outcome ~= nil or drill.id ~= "serve" then
			local done
			count, done = Tutorial.tally(drill, count, outcome == true)
			status.count = count
			publish(status)
			MS.announce({ kind = "Drill", drill = drill.id, success = outcome == true, count = count, goal = drill.goal })
			task.wait(PR.PauseAfter)
			if done then
				rep = nil
				return true
			end
		end
	end
	rep = nil
	return false
end

-- A practice lobby's turn on the court: set up a 2v2 (you and a setter, their attacker), then
-- run the drill (or the tutorial's four) until done or you leave.
function PracticeService.run(lobby)
	local TS, BS, MS, LS = reg.TeamService, reg.BallService, reg.MatchService, reg.LobbyService
	TS.botTier = lobby.botTier or PR.BotTier
	TS.assign(PR.Mode, LS.plan(lobby))
	TS.resetStats()
	MS.forfeitTeam = nil
	MS.rallyHits = {}
	MS.scores = { Home = 0, Away = 0 }
	local plr = nil
	for _, e in ipairs(TS.members(HOME)) do
		plr = plr or e.player
	end
	if not plr then
		for _, e in ipairs(TS.members(AWAY)) do
			plr = plr or e.player
		end
	end
	local drills = {}
	if lobby.tutorial then
		drills = Tutorial.Drills
	elseif Tutorial.drill(lobby.drill) then
		drills = { Tutorial.drill(lobby.drill) }
	end
	local status = { tutorial = lobby.tutorial == true or nil, index = 0, total = #drills }
	local function stillOn()
		return plr ~= nil and plr.Parent ~= nil and TS.entityForPlayer(plr) ~= nil and not MS.forfeitTeam
	end
	for i, drill in ipairs(drills) do
		status.index = i
		if not runDrill(drill, plr, status, stillOn) then
			break
		end
		if lobby.tutorial then
			reg.ProfileService.tutorialStep(plr, { drill.id })
		end
		if i == #drills then
			status.finished = true
			publish(status)
			MS.announce({ kind = "Drill", finished = true, tutorial = lobby.tutorial == true or nil })
			-- the coach offers the way out; stay a moment, then the court frees up
			local t0 = os.clock()
			while stillOn() and os.clock() - t0 < 8 do
				task.wait(0.2)
			end
		end
	end
	BS.hide()
	MS.forfeitTeam = nil
	publish(nil)
end

function PracticeService.init(r)
	reg = r
	reg.BallService.onDead:Connect(onDead)
end

return PracticeService
