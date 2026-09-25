-- Bot players for the 2.5D game. They fill empty slots so every mode is playable solo and play
-- through the exact same HitService pipeline as humans.
--
-- Each touch the bots re-plan from the analytic ball path: who takes the next touch, where to
-- stand, when to jump. Their spikes use real contact geometry: to aim deep or short a bot picks
-- where to stand relative to the ball (the same rule humans use), and power comes from how
-- cleanly their jump meets it. Tier sets how precise they are.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Util = require(Shared.Util)
local BallPhysics = require(Shared.BallPhysics)
local HitLogic = require(Shared.HitLogic)
local Characters = require(Shared.Characters)
local Spins = require(Shared.Spins)

local BotService = {}
local reg
local bots = {}
local folder
local planSeq, planPhase = -1, nil

local Z, H, P, B = Config.Zones, Config.Hits, Config.Player, Config.Bots
local C = Config.Court
local SPM = Config.Scale.StudsPerMeter
local AZURE = Config.Abilities.Azure
local SKIN = {
	Color3.fromRGB(255, 219, 172),
	Color3.fromRGB(241, 194, 125),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(92, 58, 30),
}

------------------------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------------------------

local function tierPair(b, pair)
	return Characters.byTier(b.entity.charStats, pair)
end

-- The stats this bot plays with right now (Adrenaline boosts them when its team is low).
local function statsOf(e)
	return (HitLogic.effectiveStats(e.charStats, e.ability, reg.TeamService.staminaOf(e.team)))
end

-- A team-level decision (reading the ball out): the skill of that team's bots.
local function teamPair(team, pair)
	for _, e in ipairs(reg.TeamService.members(team)) do
		if e.isBot then
			return Characters.byTier(e.charStats, pair)
		end
	end
	return pair[2]
end

local function stop(b)
	b.hum:Move(Vector3.zero)
end

-- Face along the court only (+z or -z), like everyone in a side view. Writing the root CFrame
-- every frame fights the humanoid's physics, so it's only rewritten when the facing is off.
local function faceDir(b, dirZ)
	if math.abs(dirZ) < 1e-3 then
		return
	end
	local want = dirZ > 0 and 1 or -1
	if b.hrp.CFrame.LookVector.Z * want > 0.999 then
		return
	end
	local pos = b.hrp.Position
	b.hum.AutoRotate = false
	b.hrp.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, want))
end

local function faceNet(b, side)
	faceDir(b, -side)
end

-- Walk along the court toward z. Returns true once arrived.
local function moveTo(b, z)
	local dz = z - b.hrp.Position.Z
	if math.abs(dz) < 0.3 then
		stop(b)
		return true
	end
	local scale = math.clamp(math.abs(dz) / 2.2, 0.3, 1)
	b.hum:Move(Vector3.new(0, 0, (dz > 0 and 1 or -1) * scale))
	faceDir(b, dz)
	return false
end

local function teamBots(team)
	local list = {}
	for _, e in ipairs(reg.TeamService.members(team)) do
		local b = bots[e.id]
		if b then
			table.insert(list, b)
		end
	end
	return list
end

local function rootZ(e)
	local r = reg.TeamService.getRoot(e)
	return r and r.Position.Z
end

-- Formation spots for a team's bots, with humans who moved onto a teammate's spot (say, up to
-- the net to block) swapped in (Court.formationFill).
local function formationFor(team, kind)
	local members = {}
	for _, e in ipairs(reg.TeamService.members(team)) do
		table.insert(members, { id = e.id, role = e.role, isBot = e.isBot, z = not e.isBot and rootZ(e) or nil })
	end
	return Court.formationFill(members, kind, Court.sideOf(team), B.SwapMargin)
end

-- Closest team member to z. Humans get a head start so bots never steal their ball.
local function closestMember(team, z, excludeId)
	local best, bestD = nil, nil
	for _, e in ipairs(reg.TeamService.members(team)) do
		local rz = e.id ~= excludeId and rootZ(e)
		if rz then
			local d = math.abs(rz - z)
			if not e.isBot then
				d = d - 0.6 * SPM
			end
			if not best or d < bestD then
				best, bestD = e, d
			end
		end
	end
	return best
end

-- Simulated jump with the hang force: time to apex from takeoff.
local function jumpTime(jh, cancel)
	local g = workspace.Gravity
	local v = math.sqrt(2 * g * jh)
	local t, dt = 0, 1 / 240
	while v > 0 and t < 3 do
		local a = g
		if math.abs(v) < P.HangVelocityWindow then
			a = g * (1 - cancel)
		end
		v = v - a * dt
		t = t + dt
	end
	return t
end

-- Landing depth (distance from the net on the far side) that an attacker's dz produces.
local function dzForDepth(depth, deepest, shortest)
	local t = math.clamp((deepest - depth) / (deepest - shortest), 0, 1) ^ (1 / 0.9)
	return H.SpikeDzDeep + t * (H.SpikeDzShort - H.SpikeDzDeep)
end

-- Pick an attack depth where the defence isn't.
local function chooseDepth(b, team, shortest)
	local opp = Court.other(team)
	local oside = Court.sideOf(opp)
	local deepest = C.SideDepth - H.SpikeDeepMargin - 0.5
	local foes = {}
	for _, e in ipairs(reg.TeamService.members(opp)) do
		local rz = rootZ(e)
		if rz then
			table.insert(foes, rz * oside)
		end
	end
	local best, bestScore = deepest, -math.huge
	for _, cand in ipairs({ deepest, deepest - 1.25 * SPM, deepest - 2.5 * SPM, (deepest + shortest) / 2, shortest + 0.95 * SPM }) do
		local d = 40
		for _, f in ipairs(foes) do
			d = math.min(d, math.abs(f - cand))
		end
		-- deep attacks are the most powerful: favour them a little
		local score = d + (cand / deepest) * 3 + b.rng:NextNumber() * 4
		if score > bestScore then
			best, bestScore = cand, score
		end
	end
	return best, deepest
end

------------------------------------------------------------------------------------------
-- planning (runs once per touch)
------------------------------------------------------------------------------------------

local function resetTask(b)
	b.task = "Base"
	b.targetZ = nil
	b.jumpAt = nil
	b.acted = false
	b.setType = nil
	b.targetId = nil
	b.feint = false
	b.slideAt = nil
	b.lastCheck = nil
	b.chargeFrom = nil
	b.overcharge = false
	b.coverFor = nil
	b.backup = nil
	b.notBefore = nil
end

-- The nearest bot on `team` to z (skipping `excludeId` and `alsoExclude`), to cover a ball a
-- human should play.
local function coverBot(team, z, excludeId, alsoExclude)
	local best, bestD = nil, math.huge
	for _, b in ipairs(teamBots(team)) do
		if b.entity.id ~= excludeId and b.entity.id ~= alsoExclude then
			local d = math.abs(b.hrp.Position.Z - z)
			if d < bestD then
				best, bestD = b, d
			end
		end
	end
	return best
end

-- A covering bot holds off while its human is trying to play the ball, but not once they've
-- swung and missed: then it goes for the ball (a missed spike gets sent over as a free ball).
local function yieldsToHuman(b)
	if b.coverFor == nil then
		return false
	end
	local covered = reg.TeamService.getEntity(b.coverFor)
	if b.backup and covered and covered.isBot then
		return false -- backing up a bot: it jumps first, so a hit leaves nothing to take
	end
	local HS = reg.HitService
	if HS.missAge(b.coverFor) < B.CoverAfterMiss then
		return false
	end
	return HS.intentAge(b.coverFor) < B.CoverYield
end

-- When the ball comes down to `y` on `side` (or its apex if it never gets that high).
local function descentTo(path, now, y, side)
	local apexT, apexP = BallPhysics.findApex(path, now)
	if apexP and apexP.Y < y and apexP.Z * side > 0 then
		return apexT, apexP
	end
	return BallPhysics.findTime(path, now, function(pos, vel)
		return vel.Y < 0 and pos.Y <= y and pos.Z * side > 0
	end)
end

local function planReceive(team, now, exclude)
	local BS = reg.BallService
	local path = BS.path
	local side = Court.sideOf(team)
	local t, p = BallPhysics.findTime(path, now, function(pos, vel)
		return vel.Y < 0 and pos.Y <= P.RootGround + Z.ReceiveIdealY + 0.3 and pos.Z * side > 0.3
	end)
	if not t then
		t, p = path.landing.t, path.landing.pos
	end
	local standZ = p.Z + side * Z.ReceiveForward
	local who = closestMember(team, standZ, exclude)
	local b = who and bots[who.id]
	if who and not b then
		-- a human's ball: the nearest bot shadows it and digs it if the human doesn't
		b = coverBot(team, standZ, exclude)
		if not b then
			return
		end
		b.coverFor = who.id
		standZ = standZ + side * B.CoverDepth
	end
	if not b then
		return
	end
	b.task = "Receive"
	b.targetZ = standZ
	b.contactT = t
	local walk = b.entity.charStats.WalkSpeed
	local gap = math.abs(b.hrp.Position.Z - standZ) - Z.ReceiveReach
	local timeLeft = t - now - 0.12
	local broken = reg.TeamService.stamina[team].value <= 0
	local heavy = HitLogic.isHeavy(BS.lastHit)
	if (gap > walk * timeLeft and gap < walk * timeLeft + P.SlideSpeed * P.SlideTime) or (broken and heavy) then
		if b.rng:NextNumber() < tierPair(b, B.SlideChance) then
			b.slideAt = t - 0.3
		end
	end
	-- receive timing: stronger bots press at the perfect moment more often
	if b.rng:NextNumber() < tierPair(b, B.PerfectReceiveChance) then
		b.stanceAge = H.PerfectStanceMin + b.rng:NextNumber() * (H.PerfectStanceMax - H.PerfectStanceMin)
	else
		b.stanceAge = H.PerfectStanceMax + 0.05 + b.rng:NextNumber() * tierPair(b, B.SloppyStance)
	end
end

-- Time from takeoff until this bot's hand rises to handY (its apex time if that's out of reach).
local function handLead(b, handY)
	local hum, hrp = b.hum, b.hrp
	local d = handY - (hum.HipHeight + hrp.Size.Y / 2 + Z.SpikeUp)
	local jh = hum.JumpHeight
	if d >= jh - 0.3 then
		return b.tApex
	end
	if d <= 0 then
		return 0.05
	end
	local g = workspace.Gravity
	local v0 = math.sqrt(2 * g * jh)
	return (v0 - math.sqrt(math.max(0, v0 * v0 - 2 * g * d))) / g
end

-- A quick: the middle is in the air before the set. From where the setter will take the ball
-- (tSet, ballP) the quick's path is known, so the middle runs in and takes off early enough to
-- be at the top when it arrives. Once the set is made the attack plan takes over mid-air.
local function planQuick(mb, team, tSet, ballP)
	local side = Court.sideOf(team)
	local v, g = HitLogic.setArc(ballP, side, "Quick")
	local path = BallPhysics.buildPath(BallPhysics.newLaunch(ballP, v, Vector3.new(0, -g, 0), tSet))
	local stats = statsOf(mb.entity)
	mb.tApex = jumpTime(mb.hum.JumpHeight, P.HangGravityCancel)
	local cT, cP = descentTo(path, tSet, stats.contactMaxStuds - 0.15, side)
	if not cT then
		return
	end
	mb.task = "Quick"
	mb.targetZ = cP.Z + side * Z.SpikeForward
	if mb.targetZ * side < 0.3 * SPM then
		mb.targetZ = side * 0.3 * SPM
	end
	mb.jumpAt = cT - mb.tApex + (mb.rng:NextNumber() * 2 - 1) * tierPair(mb, B.JumpTimingNoise)
end

-- The middle backs up a set to `hitter` (the wing spiker): it jumps late, to meet the ball
-- BackupDelay after the wing spiker's contact. A hit leaves it nothing to do; a miss gets
-- spiked (lower and weaker when the ball has dropped below its best reach).
local function planBackup(team, now, hitter, exclude)
	local TS = reg.TeamService
	if TS.teamSize < 3 or not hitter then
		return nil
	end
	local mbE = TS.byRole(team, "MB")
	local mb = mbE and bots[mbE.id]
	if not mb or mbE.id == hitter.id or mbE.id == exclude then
		return nil
	end
	local side = Court.sideOf(team)
	local path = reg.BallService.path
	local tW = descentTo(path, now, statsOf(hitter).contactMaxStuds - 0.15, side)
	mb.tApex = jumpTime(mb.hum.JumpHeight, P.HangGravityCancel)
	local tM = descentTo(path, now, statsOf(mbE).contactMaxStuds - 0.15, side)
	if not tW or not tM then
		return nil
	end
	local tB = math.max(tM, tW + B.BackupDelay)
	if tB >= path.landing.t then
		return nil
	end
	local pB = BallPhysics.positionAt(path, tB)
	if pB.Y < C.NetTop + 0.6 * SPM or pB.Z * side <= 0 or pB.Z * side > C.AttackLine + 1.9 * SPM then
		return nil
	end
	mb.task = "Spike"
	mb.backup = true
	mb.coverFor = hitter.id
	mb.feint = false
	mb.notBefore = tW + B.BackupDelay * 0.5
	mb.targetZ = pB.Z + side * Z.SpikeForward
	if mb.targetZ * side < 0.3 * SPM then
		mb.targetZ = side * 0.3 * SPM
	end
	mb.jumpAt = tB - handLead(mb, pB.Y)
	return mb
end

local function planSet(team, now, exclude)
	local BS = reg.BallService
	local path = BS.path
	local side = Court.sideOf(team)
	local TS = reg.TeamService
	local t, p = descentTo(path, now, P.RootGround + Z.SetIdealY, side)
	if not t then
		t, p = path.landing.t, path.landing.pos
	end
	local setter = TS.byRole(team, "SE")
	local who = nil
	if setter and setter.id ~= exclude then
		who = setter
	else
		who = closestMember(team, p.Z, exclude)
	end
	local b = who and bots[who.id]
	if who and not b then
		b = coverBot(team, p.Z, exclude)
		if b then
			b.coverFor = who.id
		end
	end
	if not b then
		return
	end
	b.task = "Set"
	if b.coverFor then
		b.targetZ = p.Z + side * B.CoverDepth
		b.setType = "Open"
		b.targetId = b.coverFor -- set it back to the human who let it go
		return
	end
	b.targetZ = p.Z
	-- the wing spiker gets the ball; off a good pass (near the net) the setter sometimes calls a
	-- quick to the middle instead, if the middle is close enough to the net to hit it
	local target, setType = nil, "Open"
	local ws = TS.byRole(team, "WS")
	local mb = TS.byRole(team, "MB")
	if mb and mb.id ~= b.entity.id and mb.id ~= exclude and math.abs(p.Z) <= B.QuickPassDepth then
		local mbZ = rootZ(mb)
		local chance = tierPair(b, B.QuickChance)
		if not mb.isBot then
			chance = chance * B.QuickHumanMul
		end
		if mbZ and math.abs(mbZ) <= B.QuickReachDepth and b.rng:NextNumber() < chance then
			target, setType = mb, "Quick"
		end
	end
	if not target and ws and ws.id ~= b.entity.id and ws.id ~= exclude then
		target = ws
		if ws.isBot and b.rng:NextNumber() > 0.9 then
			setType = "Back"
		end
	end
	if not target then
		-- no wing spiker to set: any other hitter, humans first
		for _, e in ipairs(TS.members(team)) do
			if e.id ~= b.entity.id and e.id ~= exclude and (not target or (target.isBot and not e.isBot)) then
				target = e
			end
		end
	end
	if not target then
		target = b.entity -- solo: set yourself
	end
	b.setType = setType
	b.targetId = target.id
	if setType == "Quick" and bots[target.id] then
		planQuick(bots[target.id], team, t, p)
	end
end

local function planAttack(team, now, exclude)
	local BS = reg.BallService
	local path, last = BS.path, BS.lastHit
	local side = Court.sideOf(team)
	local spiker = nil
	if last and last.team == team and last.targetId and last.targetId ~= exclude then
		spiker = bots[last.targetId]
		local human = not spiker and reg.TeamService.getEntity(last.targetId)
		if human then
			-- the set was meant for a human: the middle backs them up with a late jump, and a bot
			-- waits underneath to send a free ball over if nobody gets it
			local backup = planBackup(team, now, human, exclude)
			local cover = coverBot(team, path.landing.pos.Z, exclude, backup and backup.entity.id)
			if cover then
				cover.coverFor = last.targetId
				cover.task = "Free"
				cover.targetZ = path.landing.pos.Z + side * (Z.ReceiveForward + B.CoverDepth)
				cover.stanceAge = 0.25
			end
			return
		end
	end
	if not spiker then
		local apexT, apexP = BallPhysics.findApex(path, now)
		local who = closestMember(team, (apexP or path.landing.pos).Z, exclude)
		spiker = who and bots[who.id]
		if who and not spiker then
			local cover = coverBot(team, path.landing.pos.Z, exclude)
			if cover then
				cover.coverFor = who.id
				cover.task = "Free"
				cover.targetZ = path.landing.pos.Z + side * (Z.ReceiveForward + B.CoverDepth)
				cover.stanceAge = 0.25
			end
			return
		end
		if not apexT then
			spiker = nil
		end
	end
	if not spiker then
		return
	end
	local stats = statsOf(spiker.entity)
	spiker.tApex = jumpTime(spiker.hum.JumpHeight, P.HangGravityCancel)
	local contactY = stats.contactMaxStuds - 0.15
	local lead = spiker.tApex
	local azure = spiker.entity.ability == "Azure"
	if azure then
		-- jump early, reach the top, then hover down (low gravity while charging) and meet the
		-- ball with a full bar
		local delta = math.max(0, AZURE.ChargeTime + 0.08 - spiker.tApex)
		local gEff = workspace.Gravity * (1 - AZURE.GravityCancel)
		contactY = stats.contactMaxStuds - 0.5 * gEff * delta * delta - 0.1
		lead = spiker.tApex + delta
	end
	local cT, cP = descentTo(path, now, contactY, side)
	local canAttack = cP ~= nil and cP.Y > C.NetTop + 0.5 * SPM and cP.Z * side < C.AttackLine + 1.9 * SPM
	if not canAttack then
		-- nothing to hit: send a free ball over on the third touch
		local t, p = BallPhysics.findTime(path, now, function(pos, vel)
			return vel.Y < 0 and pos.Y <= P.RootGround + Z.ReceiveIdealY + 0.3 and pos.Z * side > 0.2
		end)
		if not t then
			p = path.landing.pos
		end
		spiker.task = "Free"
		spiker.targetZ = p.Z + side * Z.ReceiveForward
		spiker.stanceAge = 0.25
		return
	end
	spiker.task = "Spike"
	spiker.feint = spiker.rng:NextNumber() < B.FeintChance
	local depth, deepest = chooseDepth(spiker, team, H.SpikeShortDepth)
	local dz = dzForDepth(depth, deepest, H.SpikeShortDepth)
	local noise = (spiker.rng:NextNumber() * 2 - 1) * tierPair(spiker, B.ContactNoise)
	spiker.targetZ = cP.Z + side * (dz + Z.SpikeForward) + noise
	-- the takeoff spot must stay on our side of the net
	if spiker.targetZ * side < 0.3 * SPM then
		spiker.targetZ = side * 0.3 * SPM
	end
	if azure then
		spiker.chargeFrom = true
		spiker.overcharge = spiker.rng:NextNumber() < 0.03
	end
	spiker.jumpAt = cT - lead + (spiker.rng:NextNumber() * 2 - 1) * tierPair(spiker, B.JumpTimingNoise)
	if spiker.entity.role == "WS" and last and last.hitType == "Set" and last.team == team then
		planBackup(team, now, spiker.entity, exclude)
	end
end

local function planPlay(team, now)
	local BS = reg.BallService
	local path, last, touch = BS.path, BS.lastHit, BS.touch or {}
	local size = reg.TeamService.teamSize
	if last and last.team == team and HitLogic.isServe(last.hitType) then
		return
	end
	local n = HitLogic.touchNumber(touch, team)
	if n > 3 then
		return
	end
	-- read the ball: an opponent ball clearly going out is left alone
	if last and last.team ~= team and Court.outMargin(path.landing.pos) > 1.2 then
		if math.random() < teamPair(team, B.ReadOutChance) then
			return
		end
	end
	local exclude = nil
	if size > 1 and touch.team == team and not touch.lastWasBlock then
		exclude = touch.lastId
	end
	if n == 1 then
		planReceive(team, now, exclude)
	elseif n == 2 then
		planSet(team, now, exclude)
	else
		planAttack(team, now, exclude)
	end
end

local function planBlock(team, now)
	local BS = reg.BallService
	local last = BS.lastHit
	if not last or last.team == team or reg.TeamService.teamSize <= 1 then
		return
	end
	if last.hitType ~= "Set" then
		return
	end
	local attSide = Court.sideOf(last.team)
	local cT, cP = descentTo(BS.path, now, H.SetArriveY, attSide)
	if not cT or math.abs(cP.Z) > 2.2 * SPM then
		return
	end
	local side = Court.sideOf(team)
	local blocker = nil
	for _, role in ipairs({ "MB", "SE", "WS" }) do
		local e = reg.TeamService.byRole(team, role)
		if e and bots[e.id] then
			blocker = bots[e.id]
			break
		end
	end
	if blocker and blocker.rng:NextNumber() < tierPair(blocker, B.BlockChance) then
		blocker.task = "Block"
		blocker.targetZ = side * 0.4 * SPM
		blocker.jumpAt = cT - blocker.tApex + 0.08 + (blocker.rng:NextNumber() * 2 - 1) * tierPair(blocker, B.JumpTimingNoise)
	end
end

local function plan(now)
	local BS, MS = reg.BallService, reg.MatchService
	for _, b in pairs(bots) do
		resetTask(b)
	end
	if MS.phase ~= "Rally" or BS.state ~= "Flight" or not BS.path then
		return
	end
	if now >= BS.path.landing.t then
		return
	end
	local defTeam = Court.teamOnSide(Court.sideOfPoint(BS.path.landing.pos))
	-- everybody else drifts to their situational spot
	for _, team in ipairs(Config.TeamOrder) do
		local side = Court.sideOf(team)
		local kind = team == defTeam and "Offense" or "Defense"
		local last = BS.lastHit
		if team == defTeam and last and last.team ~= team then
			kind = "Receive"
		end
		local spots = formationFor(team, kind)
		for _, b in ipairs(teamBots(team)) do
			b.formKind = kind
			b.targetZ = spots[b.entity.id] or Court.formationSpot(kind, b.entity.role, side).Z
		end
	end
	planPlay(defTeam, now)
	planBlock(Court.other(defTeam), now)
end

------------------------------------------------------------------------------------------
-- execution (every Heartbeat)
------------------------------------------------------------------------------------------

local function act(b, action, ball, extra)
	extra.ball = ball
	local ok = reg.HitService.botAction(b.entity, action, extra)
	if ok then
		b.acted = true
	else
		b.nextActAt = Util.now() + 0.06
	end
	return ok
end

local function whiffs(b)
	if b.rng:NextNumber() < tierPair(b, B.MissChance) then
		return true
	end
	local last = reg.BallService.lastHit
	if not HitLogic.isHeavy(last) then
		return false
	end
	return b.rng:NextNumber() < tierPair(b, B.WhiffChance)
end

-- Sub-stepped search for the first moment since the last check that satisfies test(p, v).
local function sweep(b, path, now, test)
	local t0 = b.lastCheck or (now - 1 / 60)
	for i = 1, 4 do
		local t = t0 + (now - t0) * i / 4
		local p = BallPhysics.positionAt(path, t)
		local v = BallPhysics.velocityAt(path, t)
		if test(p, v) then
			return t, p
		end
	end
	return nil
end

local function serveLogic(b, now, grounded, side)
	local BS = reg.BallService
	local e = b.entity
	local root = b.hrp.Position
	if BS.state == "Held" and BS.holderId == e.id then
		stop(b)
		faceNet(b, side)
		if not b.serve then
			local d = B.ServeDelay
			b.serve = {
				at = now + d[1] + b.rng:NextNumber() * (d[2] - d[1]),
				jump = e.charStats.index >= B.JumpServeTier and b.rng:NextNumber() < 0.75,
			}
		end
		if now >= b.serve.at and now >= b.nextActAt then
			local h = H.TossLow
			if b.serve.jump then
				h = H.TossHighMin + b.rng:NextNumber() * (H.TossHighMax - H.TossHighMin)
			end
			if not reg.HitService.botAction(e, "Toss", { tossHeight = h }) then
				b.nextActAt = now + 0.2
			end
		end
		return
	end
	local last = BS.lastHit
	if not (BS.state == "Flight" and last and last.hitType == "Toss" and last.id == e.id) then
		stop(b)
		faceNet(b, side)
		return
	end
	local s = b.serve or { jump = false }
	b.serve = s
	local path = BS.path
	if not s.planned then
		s.planned = true
		if s.jump then
			local contactY = statsOf(e).contactMaxStuds - 0.2
			local t, p = descentTo(path, now, contactY, side)
			if t then
				local depth = C.SideDepth - SPM * (0.95 + b.rng:NextNumber() * 2.5)
				local dz = dzForDepth(depth, C.SideDepth - H.SpikeDeepMargin, 2.8 * SPM)
				s.standZ = p.Z + side * (dz + Z.SpikeForward)
				s.jumpAt = t - b.tApex + (b.rng:NextNumber() * 2 - 1) * tierPair(b, B.JumpTimingNoise)
			end
		else
			s.standZ = root.Z
		end
	end
	if s.standZ and grounded then
		moveTo(b, s.standZ)
	end
	if s.jumpAt and now >= s.jumpAt then
		if grounded then
			b.hum.Jump = true
			reg.HitService.fx(e.id, "Jump", "Serve")
		end
		s.jumpAt = nil
	end
	if now < b.nextActAt then
		return
	end
	local ball = BallPhysics.positionAt(path, now)
	local vel = BallPhysics.velocityAt(path, now)
	if s.miss == nil then
		s.miss = b.rng:NextNumber() < tierPair(b, B.ServeMissChance)
	end
	local extra = {}
	if s.miss then
		extra.quality = 0.02 -- a serve error: long, wide or into the net
	end
	if s.jump and not grounded then
		local ok, _, _, dy = HitLogic.spikeZone(root, ball, side, e.charStats, 1.1)
		if ok and dy <= Z.SpikeCenterDy + 0.3 then
			act(b, "Serve", ball, extra)
		end
	elseif not s.jump and grounded then
		local ok = HitLogic.floatZone(root, ball, side)
		if ok and vel.Y < 0 and ball.Y <= root.Y + Z.FloatUp + 0.2 then
			act(b, "Serve", ball, extra)
		end
	end
end

local function blockCheck(b, now, root, side)
	local BS = reg.BallService
	local last = BS.lastHit
	if not last or last.team == b.entity.team then
		return
	end
	local t, p = sweep(b, BS.path, now, function(pos, vel)
		return vel.Z * side > 0 and (HitLogic.blockBox(root, pos, side, b.entity.charStats))
	end)
	if t then
		act(b, "Block", p, { t = t })
	end
end

local function updateForces(b, grounded, charging)
	local vy = b.hrp.AssemblyLinearVelocity.Y
	local cancel = 0
	if not grounded then
		-- Azure hovers on the way down only, so charging never raises the jump
		if charging and vy <= 0 then
			cancel = AZURE.GravityCancel
		elseif math.abs(vy) < P.HangVelocityWindow then
			cancel = P.HangGravityCancel
		end
	end
	if cancel ~= b.cancel then
		b.cancel = cancel
		b.force.Force = Vector3.new(0, b.hrp.AssemblyMass * workspace.Gravity * cancel, 0)
	end
end

local function lockLane(b)
	local pos = b.hrp.Position
	if math.abs(pos.X - b.lane) > 0.05 then
		b.hrp.CFrame = b.hrp.CFrame + Vector3.new(b.lane - pos.X, 0, 0)
	end
	local v = b.hrp.AssemblyLinearVelocity
	if math.abs(v.X) > 0.01 then
		b.hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, v.Z)
	end
end

local function updateBot(b, now)
	local e = b.entity
	local hum, hrp = b.hum, b.hrp
	if not hrp.Parent or hum.Health <= 0 then
		return
	end
	local side = Court.sideOf(e.team)
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local BS, MS = reg.BallService, reg.MatchService
	lockLane(b)

	-- knocked back by a heavy receive: skid away from the net
	if b.knockUntil then
		if now < b.knockUntil then
			local v = hrp.AssemblyLinearVelocity
			local left = (b.knockUntil - now) / b.knockDur
			hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, side * b.knockSpeed * left)
			hum:Move(Vector3.zero)
		else
			b.knockUntil = nil
		end
	end

	-- sliding: a dive along the court that ignores stamina
	if b.slideUntil then
		if now < b.slideUntil then
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, b.slideDir * P.SlideSpeed)
			hum:Move(Vector3.zero)
		elseif now > b.slideUntil + P.SlideRecover then
			b.slideUntil = nil
		else
			stop(b)
		end
	end

	local charging = b.chargeFrom ~= nil and type(b.chargeFrom) == "number" and not grounded
	updateForces(b, grounded, charging)

	if MS.phase == "Serving" then
		serveLogic(b, now, grounded, side)
		return
	end
	b.serve = nil
	if MS.phase ~= "Rally" then
		stop(b)
		if grounded then
			faceNet(b, side)
		end
		return
	end

	-- weaker bots take a moment to read a new ball before they move
	if b.planSeq ~= BS.seq then
		b.planSeq = BS.seq
		b.reactAt = now + tierPair(b, B.ReactionDelay)
	end
	if b.targetZ and not b.slideUntil and not b.knockUntil and grounded and now >= (b.reactAt or 0) then
		local arrived = moveTo(b, b.targetZ)
		if arrived then
			faceNet(b, side)
		end
	end
	if b.jumpAt and now >= b.jumpAt then
		if grounded and not b.slideUntil then
			hum.Jump = true
			if b.task == "Spike" or b.task == "Quick" then
				reg.HitService.fx(e.id, "Jump", "Spike")
			elseif b.task == "Block" then
				reg.HitService.fx(e.id, "Jump", "Block")
				reg.HitService.fx(e.id, "Block")
				if e.ability == "IronWall" then
					reg.HitService.activateAbility(e) -- whenever it's off cooldown
				end
			end
			if b.chargeFrom == true then
				b.chargeFrom = now + 0.08
				reg.HitService.fx(e.id, "Charge")
			end
		end
		b.jumpAt = nil
	end

	if BS.state ~= "Flight" or not BS.path or b.acted or now < b.nextActAt or yieldsToHuman(b) then
		b.lastCheck = now
		return
	end
	local path = BS.path
	if now >= path.landing.t then
		return
	end
	local root = hrp.Position
	local task = b.task

	if b.slideAt and now >= b.slideAt and grounded and not b.slideUntil then
		b.slideAt = nil
		b.slideDir = ((b.targetZ or root.Z) - root.Z) >= 0 and 1 or -1
		b.slideUntil = now + P.SlideTime
		reg.HitService.fx(e.id, "Slide")
	end

	if task == "Receive" or task == "Free" then
		local sliding = b.slideUntil ~= nil
		local t, p = sweep(b, path, now, function(pos, vel)
			local ok = HitLogic.receiveZone(root, pos, side, e.charStats, sliding)
			return ok and vel.Y < 0 and pos.Y - root.Y <= Z.ReceiveIdealY + 0.6
		end)
		if t then
			if task == "Receive" and not sliding and whiffs(b) then
				b.acted = true
				reg.HitService.fx(e.id, "Whiff", "Bump")
			else
				act(b, "Bump", p, { t = t, stanceAge = b.stanceAge, diving = sliding })
			end
		end
	elseif task == "Set" then
		local t, p = sweep(b, path, now, function(pos, vel)
			return vel.Y < 0 and (HitLogic.setZone(root, pos, side, e.charStats)) and pos.Y - root.Y <= Z.SetIdealY + 0.4
		end)
		if t then
			act(b, "Set", p, { t = t, setType = b.setType, targetId = b.targetId })
		else
			local t2, p2 = sweep(b, path, now, function(pos, vel)
				return vel.Y < 0 and (HitLogic.receiveZone(root, pos, side, e.charStats, false)) and pos.Y - root.Y <= Z.ReceiveIdealY + 0.6
			end)
			if t2 then
				act(b, "Set", p2, { t = t2, setType = b.setType, targetId = b.targetId })
			end
		end
	elseif task == "Spike" then
		if not grounded then
			local t, p = sweep(b, path, now, function(pos)
				local ok, _, _, dy = HitLogic.spikeZone(root, pos, side, e.charStats, 1)
				return ok and dy <= Z.SpikeCenterDy + 0.25
			end)
			if t and b.notBefore and t < b.notBefore then
				t = nil -- a backup never takes the ball off its wing spiker's hand
			end
			if t then
				local energy = 0
				if type(b.chargeFrom) == "number" then
					energy = math.clamp((t - b.chargeFrom) / AZURE.ChargeTime, 0, 1)
					if b.overcharge then
						energy = 1.2
					end
					reg.HitService.fx(e.id, "ChargeEnd")
				end
				local extra = { t = t, energy = energy }
				if b.rng:NextNumber() < tierPair(b, B.SpikeMishitChance) then
					extra.quality = 0.2 + 0.3 * b.rng:NextNumber() -- framed it
				end
				act(b, b.feint and "Feint" or "Spike", p, extra)
				b.chargeFrom = nil
			end
		end
	elseif task == "Block" then
		if not grounded then
			blockCheck(b, now, root, side)
		end
	end
	b.lastCheck = now
end

------------------------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------------------------

function BotService.spawn(e)
	local teamCfg = Config.Teams[e.team]
	-- a stand-in wears its player's avatar; other bots a friend's when there is one
	-- (FriendService), else a plain rig in team colours
	local desc = e.description and e.description:Clone()
	local avatarId = e.avatarId or e.friendId
	if not desc and avatarId then
		desc = reg.FriendService.description(avatarId)
	end
	if not desc then
		desc = Instance.new("HumanoidDescription")
		local skin = SKIN[math.random(#SKIN)]
		desc.HeadColor = skin
		desc.LeftArmColor = skin
		desc.RightArmColor = skin
		desc.TorsoColor = teamCfg.Color
		desc.LeftLegColor = teamCfg.Dark
		desc.RightLegColor = teamCfg.Dark
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[SpikeRush] Could not create a bot rig: " .. tostring(model))
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	model.Name = e.id
	model:SetAttribute("EntityId", e.id)
	model:SetAttribute("Team", e.team)
	model:SetAttribute("IsBot", true)
	-- bots show off some unlockables too (higher tiers more often)
	local flair = 0.25 + 0.6 * (Characters.tierIndex(e.tier) or 1) / #Config.Tiers
	for _, kind in ipairs(Config.Cosmetics.Kinds) do
		local value = Spins.default(kind)
		if math.random() < flair then
			value = Spins.rollItem(kind)
		end
		model:SetAttribute(Config.Cosmetics.Attribute[kind], value)
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = hrp
	hum.DisplayName = e.name
	reg.CharacterService.setupHumanoid(model)
	reg.CharacterService.applyStats(model, e.charStats)
	local side = Court.sideOf(e.team)
	local lane = Court.lane(e.role)
	model:PivotTo(Court.facing(Vector3.new(lane, 3.2, side * 3.75 * SPM), side))
	model.Parent = folder
	pcall(function()
		hrp:SetNetworkOwner(nil)
	end)

	local att = Instance.new("Attachment")
	att.Name = "HangAttachment"
	att.Parent = hrp
	local force = Instance.new("VectorForce")
	force.Name = "HangForce"
	force.Attachment0 = att
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = hrp

	local b = {
		entity = e,
		model = model,
		hum = hum,
		hrp = hrp,
		force = force,
		lane = lane,
		rng = Random.new(),
		nextActAt = 0,
		tApex = jumpTime(hum.JumpHeight, P.HangGravityCancel),
	}
	resetTask(b)
	bots[e.id] = b
	e.model = model
	planSeq = -1
	return model
end

-- A heavy receive shoves the bot back (strength 0..1 from HitLogic's meta.knock).
function BotService.knockback(e, strength)
	local b = bots[e.id]
	if not b or not strength or strength <= 0 then
		return
	end
	b.knockDur = P.KnockbackTime * (0.6 + 0.4 * strength)
	b.knockSpeed = P.KnockbackSpeed * (0.4 + 0.6 * strength)
	b.knockUntil = Util.now() + b.knockDur
end

function BotService.despawn(e)
	bots[e.id] = nil
	if e.model then
		e.model:Destroy()
		e.model = nil
	end
end

-- The humanoid's jump changed (Adrenaline): re-time jumps from the new height.
function BotService.refreshJump(e)
	local b = bots[e.id]
	if b then
		b.tApex = jumpTime(b.hum.JumpHeight, P.HangGravityCancel)
	end
end

function BotService.onReset(e)
	local b = bots[e.id]
	if not b then
		return
	end
	resetTask(b)
	b.lane = Court.lane(e.role)
	b.serve = nil
	b.slideUntil = nil
	b.nextActAt = 0
	b.tApex = jumpTime(b.hum.JumpHeight, P.HangGravityCancel)
	stop(b)
end

-- Idle bots keep re-reading the formation, so a teammate who moves (a human stepping up to
-- block) is covered while the ball is in the air, not only at the next touch.
local nextFormAt = 0
local function refreshFormation(now)
	if now < nextFormAt or reg.MatchService.phase ~= "Rally" then
		return
	end
	nextFormAt = now + 0.2
	for _, team in ipairs(Config.TeamOrder) do
		local list = teamBots(team)
		local kind = list[1] and list[1].formKind
		if kind then
			local spots = formationFor(team, kind)
			for _, b in ipairs(list) do
				if b.task == "Base" and spots[b.entity.id] then
					b.targetZ = spots[b.entity.id]
				end
			end
		end
	end
end

function BotService.init(r)
	reg = r
	folder = workspace:FindFirstChild("Bots")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Bots"
		folder.Parent = workspace
	end
	RunService.Heartbeat:Connect(function()
		local now = Util.now()
		local BS, MS = reg.BallService, reg.MatchService
		if BS.seq ~= planSeq or MS.phase ~= planPhase then
			planSeq, planPhase = BS.seq, MS.phase
			plan(now)
		end
		refreshFormation(now)
		for _, b in pairs(bots) do
			local ok, err = pcall(updateBot, b, now)
			if not ok then
				warn("[SpikeRush] bot error: " .. tostring(err))
			end
		end
	end)
end

return BotService
