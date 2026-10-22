-- Match flow: intermission (the court waits for a lobby, see LobbyService) -> match -> sets ->
-- rallies, with rally-point scoring, serve rotation, team stamina recovery, timeouts, stats, MVP
-- and rewards. A match is one set (Match.Sets); after it the players vote to keep playing for
-- the extra set rewards (Continue phase), up to Match.MaxSets. Rewards (the Rewards module):
-- win or loss, plays, extra sets, the MVP bonus and the win streak bonus. A timeout ends early
-- once every player on court has pressed Ready. A match with no humans left on court (everyone
-- left or went AFK) is called off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Roster = require(Shared.Roster)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Rewards = require(Shared.Rewards)
local Lobbies = require(Shared.Lobbies)
local HitLogic = require(Shared.HitLogic)
local Mutators = require(Shared.Mutators)

local MatchService = {}
local reg
local M = Config.Match

MatchService.phase = "Intermission"
MatchService.court = Config.Courts.Default -- the court the arena shows (ArenaBuilder.setCourt)
MatchService.practice = nil -- the drill on the court while a practice lobby plays (PracticeService)
MatchService.phaseEnd = 0
MatchService.mode = M.DefaultTeamSize
MatchService.scores = { Home = 0, Away = 0 }
MatchService.lossStreak = { Home = 0, Away = 0 } -- points each team has lost in a row (stamina comes back faster)
MatchService.sets = { Home = 0, Away = 0 }
MatchService.setNumber = 1
MatchService.target = M.PointsPerSet
MatchService.rules = Lobbies.rules(nil) -- the match's rules: its lobby's (Lobbies.rules)
MatchService.servingTeam = "Home"
MatchService.serverId = nil
MatchService.rallyResult = nil
MatchService.rallyHits = {}
MatchService.pendingTimeout = nil
MatchService.lobby = nil -- the lobby playing on this court
MatchService.aborted = false
MatchService.forfeitVotes = { Home = {}, Away = {} } -- userId -> when they voted (MatchService.forfeitTally)
MatchService.setWinners = {} -- the team that won each set so far
MatchService.totals = { Home = 0, Away = 0 } -- points over the whole match
MatchService.continueVotes = nil -- userId -> true (keep playing) / false (end), while voting
MatchService.timeoutReady = nil -- userId -> true, during a timeout

-- Humans on court who can vote (keep playing, timeout ready).
local function humans()
	local list = {}
	for _, e in pairs(reg.TeamService.entities) do
		if e.player and e.player.Parent then
			table.insert(list, e.player)
		end
	end
	return list
end

local function tallyContinue()
	local yes, no = 0, 0
	local hs = humans()
	for _, plr in ipairs(hs) do
		local v = MatchService.continueVotes and MatchService.continueVotes[plr.UserId]
		if v == true then
			yes = yes + 1
		elseif v == false then
			no = no + 1
		end
	end
	return yes, no, #hs
end

local function tallyReady()
	local n = 0
	local hs = humans()
	for _, plr in ipairs(hs) do
		if MatchService.timeoutReady and MatchService.timeoutReady[plr.UserId] then
			n = n + 1
		end
	end
	return n, #hs
end

local ATTACKS = { Spike = true, Feint = true, JumpServe = true, Overhand = true }

-- A forfeit, or nobody human left to play for.
local function halted()
	return MatchService.forfeitTeam ~= nil or MatchService.aborted
end

-- Waits for a phase to run out (t, or with no t the live phase end, which can move: a timeout
-- everyone is ready for ends early); a forfeit or an abort cuts every wait short.
local function waitUntil(t)
	while Util.now() < (t or MatchService.phaseEnd) and not halted() do
		task.wait(0.05)
	end
end

-- Called off when no human is on court and nobody can come back in (an AFK player's AI keeps
-- playing while they're still in the server), or when nobody human is on court and a lobby is
-- waiting for it (Lobbies.shouldAbort).
local function checkAbort()
	local TS = reg.TeamService
	if TS.inMatch and Lobbies.shouldAbort(TS.humanCount(), #TS.pendingJoin, TS.benchedCount(), reg.LobbyService.waitingForCourt()) then
		MatchService.aborted = true
	end
end

function MatchService.state()
	local TS = reg.TeamService
	local mode = MatchService.mode
	if TS.inMatch then
		mode = TS.teamSize
	end
	local l = MatchService.lobby
	return {
		phase = MatchService.phase,
		phaseEnd = MatchService.phaseEnd,
		mode = mode,
		inMatch = TS.inMatch,
		scores = MatchService.scores,
		sets = MatchService.sets,
		setNumber = MatchService.setNumber,
		target = MatchService.target,
		winBy = MatchService.rules.winBy,
		timeouts = MatchService.rules.timeouts,
		bestOf = MatchService.rules.sets > 1 and MatchService.rules.sets or nil,
		maxSets = MatchService.rules.sets > 1 and MatchService.rules.sets or M.MaxSets,
		servingTeam = MatchService.servingTeam,
		serverId = MatchService.serverId,
		rosters = TS.roster(),
		botTier = TS.botTier,
		timeoutPending = MatchService.pendingTimeout,
		lobbyId = l and l.id,
		continueVote = MatchService.continueVotes and { tallyContinue() } or nil,
		forfeitVote = MatchService.forfeitTally(), -- per team: { votes, needed } while a vote is open
		timeoutReady = MatchService.timeoutReady and { tallyReady() } or nil,
		tutorial = l and l.tutorial or nil,
		event = l and l.event and { diff = l.event.diff, stage = l.event.stage, stages = Config.Halloween.Stages } or nil, -- a Halloween Match
		court = MatchService.court,
		practice = MatchService.practice, -- the drill in play (PracticeService), or nil
	}
end

-- A team's forfeit vote (the owner: "forfeits only count if the whole team votes yes"): the
-- votes still standing (Match.ForfeitVoteTime) from players on the team, and how many it needs
-- (every player on it: bots don't vote). Per team { votes, needed }, nil for a team with no vote.
function MatchService.forfeitTally()
	local TS = reg.TeamService
	local out = nil
	local now = os.clock()
	for _, team in ipairs(Config.TeamOrder) do
		local votes = MatchService.forfeitVotes and MatchService.forfeitVotes[team] or {}
		local n, need = 0, 0
		for _, m in ipairs(TS.members(team)) do
			if not m.isBot and m.player then
				need = need + 1
				local t = votes[m.player.UserId]
				if t and now - t < M.ForfeitVoteTime then
					n = n + 1
				end
			end
		end
		if n > 0 then
			out = out or {}
			out[team] = { n, math.max(need, 1) }
		end
	end
	return out
end

function MatchService.broadcast()
	Net.get("MatchState"):FireAllClients(MatchService.state())
end

function MatchService.setPhase(phase, duration)
	MatchService.phase = phase
	MatchService.phaseEnd = Util.now() + (duration or 0)
	MatchService.broadcast()
end

function MatchService.announce(data)
	Net.get("Announce"):FireAllClients(data)
end

------------------------------------------------------------------------------------------
-- rally judgement
------------------------------------------------------------------------------------------

function MatchService.judge(landing, flags, last)
	local r = { landing = landing.pos }
	if not last then
		r.winner = Court.other(MatchService.servingTeam)
		r.reason = "Fault"
		return r
	end
	r.byId = last.id
	if last.hitType == "Toss" then
		r.winner = Court.other(last.team)
		r.reason = "ServiceFault"
		r.error = true
		return r
	end
	if last.fail or last.breaks then
		-- a broken guard couldn't hold the spike: the attacker's point
		r.winner = Court.other(last.team)
		r.reason = "Break"
		return r
	end
	local pos = landing.pos
	if last.breakThrough and landing.kind == "Floor" then
		-- a Feral Leap spike that smashed through the block and wasn't dug: the attacker's kill
		-- (the block was the last touch, but it never stopped the ball)
		r.winner = Court.other(last.team)
		r.reason = Court.inBounds(pos) and "Spike" or "Tooled"
		return r
	end
	if flags.underNet or landing.kind ~= "Floor" then
		r.winner = Court.other(last.team)
		r.error = true
		if flags.underNet then
			r.reason = "Net"
		else
			r.reason = "Out"
		end
		return r
	end
	if Court.inBounds(pos) then
		local floorTeam = Court.teamOnSide(Court.sideOfPoint(pos))
		r.winner = Court.other(floorTeam)
		if floorTeam == last.team then
			r.error = true
			if flags.netTouch then
				r.reason = "Net"
			else
				r.reason = "Drop"
			end
		else
			local ht = last.hitType
			if ht == "JumpServe" or ht == "Overhand" or ht == "Underhand" then
				r.reason = "Ace"
			elseif ht == "Spike" then
				r.reason = "Spike"
			elseif ht == "Feint" then
				r.reason = "Feint"
			elseif ht == "Block" then
				if last.outcome == "Stuff" then
					r.reason = "Stuff"
				else
					r.reason = "Block"
				end
			elseif ht == "Free" then
				r.reason = "Free ball"
			else
				r.reason = "Point"
			end
		end
		return r
	end
	r.winner = Court.other(last.team)
	if last.hitType == "Block" then
		r.reason = "Tooled" -- off the blocker's hands and out: the attacker's point
	else
		r.reason = "Out"
		r.error = true
	end
	return r
end

------------------------------------------------------------------------------------------
-- hit bookkeeping
------------------------------------------------------------------------------------------

-- A fault called on a touch (HitService: the four-touch rule): the rally ends at once and the
-- other team scores; the ball flies on but no longer counts.
function MatchService.touchFault(entity, reason, where)
	if MatchService.phase ~= "Rally" or MatchService.rallyResult or MatchService.practice then
		return
	end
	MatchService.rallyResult = {
		winner = Court.other(entity.team),
		reason = reason,
		byId = entity.id,
		error = true,
		landing = where,
	}
end

function MatchService.onServeHit()
	MatchService.setPhase("Rally", 0)
end

function MatchService.onHit(entity, meta, previous)
	if MatchService.practice then
		reg.PracticeService.onHit(entity, meta)
		return
	end
	table.insert(MatchService.rallyHits, { id = entity.id, team = entity.team, hitType = meta.hitType })
	-- every touch a block gets on the ball counts on the Tab scoreboard (stats.blockTouches); only the
	-- ones that win the point are credited to stats.blocks (awardPoint), which feeds the record and rewards
	if meta.hitType == "Block" then
		entity.stats.blockTouches = (entity.stats.blockTouches or 0) + 1
		task.defer(MatchService.broadcast) -- so the board shows it now, not at the next point
	end
	-- a dig: the first touch that keeps an opponent attack alive
	if previous and previous.team ~= entity.team and ATTACKS[previous.hitType or ""] then
		if (meta.hitType == "Bump" or meta.hitType == "Set" or meta.hitType == "Free") and not meta.fail and (meta.quality or 0) >= 0.35 then
			entity.stats.digs = entity.stats.digs + 1
		end
	end
end

-- The winning team's last touch this rally (who the banner credits).
local function scorerOf(winner)
	local hits = MatchService.rallyHits
	for i = #hits, 1, -1 do
		if hits[i].team == winner then
			return hits[i], i
		end
	end
	return nil, nil
end

function MatchService.awardPoint(res)
	local TS = reg.TeamService
	local winner = res.winner
	local loser = Court.other(winner)
	MatchService.scores[winner] = MatchService.scores[winner] + 1
	MatchService.totals[winner] = (MatchService.totals[winner] or 0) + 1

	local lastHit = TS.getEntity(res.byId)
	if lastHit and res.error then
		lastHit.stats.errors = lastHit.stats.errors + 1
	end
	local credit, index = scorerOf(winner)
	local scorer = credit and TS.getEntity(credit.id)
	if scorer and not res.error then
		local st = scorer.stats
		local reason = res.reason
		if reason == "Spike" or reason == "Feint" or reason == "Break" or reason == "Tooled" then
			st.kills = st.kills + 1
			local IRON = Config.Abilities.Ironclad
			local ironNow = HitLogic.ironLives(scorer.ironLives)
			if TS.has(scorer, "Ironclad") and ironNow < IRON.Lives then
				-- Intimidation: a Taesan below full shields fills it more with a kill (his touch already
				-- added its share)
				local m = (scorer.intimidation or 0) + IRON.MeterBonus
				if m >= 100 then
					TS.setIron(scorer, IRON.Lives, 0)
				else
					TS.setIron(scorer, ironNow, m, scorer.ironCracks)
				end
			end
			local hits = MatchService.rallyHits
			local prev = index and hits[index - 1]
			if prev and prev.team == scorer.team and prev.hitType == "Set" and prev.id ~= scorer.id then
				local setter = TS.getEntity(prev.id)
				if setter then
					setter.stats.assists = setter.stats.assists + 1
				end
			end
		elseif reason == "Ace" then
			st.aces = st.aces + 1
		elseif reason == "Stuff" or reason == "Block" then
			st.blocks = st.blocks + 1
		end
	end

	-- stamina comes back between rallies; the team that lost the point gets more, and more again
	-- for every point in a row it has lost (HitLogic.lossRecovery)
	local streak = MatchService.lossStreak
	streak[loser] = (streak[loser] or 0) + 1
	streak[winner] = 0
	TS.recoverStamina(winner, Config.Stamina.RecoverWinner)
	TS.recoverStamina(loser, HitLogic.lossRecovery(streak[loser]))

	local sideOut = winner ~= MatchService.servingTeam
	if sideOut then
		TS.rotate(winner)
		MatchService.servingTeam = winner
	end

	local s = MatchService.scores
	local base = MatchService.target
	local R = MatchService.rules
	local playTo, deuce = Court.playTo(s[winner], s[loser], base, R.winBy)
	local setOver = s[winner] >= playTo
	local setPoint = nil
	if not setOver then
		for _, team in ipairs(Config.TeamOrder) do
			local mine, theirs = s[team] + 1, s[Court.other(team)]
			if mine >= Court.playTo(mine, theirs, base, R.winBy) then
				setPoint = team
			end
		end
	end
	local matchPoint
	if R.sets > 1 then
		-- best of: the team on set point needs just this set
		matchPoint = setPoint ~= nil and MatchService.sets[setPoint] + 1 >= math.floor(R.sets / 2) + 1
	else
		matchPoint = setPoint ~= nil and MatchService.setNumber >= M.Sets -- any set from here may be the last
	end

	MatchService.setPhase("Point", M.PointPauseTime)
	MatchService.announce({
		kind = "Point",
		winner = winner,
		reason = res.reason,
		error = res.error,
		byId = res.byId,
		scorerId = scorer and scorer.id,
		scorerName = scorer and scorer.name,
		landing = res.landing,
		sideOut = sideOut,
		scores = s,
		setPoint = setPoint,
		matchPoint = matchPoint,
		playTo = playTo,
		deuce = deuce and not setOver and s[winner] == s[loser],
	})
	waitUntil(MatchService.phaseEnd)
	return setOver
end

------------------------------------------------------------------------------------------
-- timeouts
------------------------------------------------------------------------------------------

function MatchService.runTimeout()
	local TS = reg.TeamService
	local req = MatchService.pendingTimeout
	MatchService.pendingTimeout = nil
	if not req or not TS.useTimeout(req.team) then
		return
	end
	if Config.Timeout.ResetBothTeams then
		for _, team in ipairs(Config.TeamOrder) do
			TS.fillStamina(team)
		end
	else
		TS.fillStamina(req.team)
	end
	TS.clearCorona() -- a timeout clears Corona's penalty
	reg.BallService.hide()
	MatchService.timeoutReady = {}
	MatchService.setPhase("Timeout", Config.Timeout.Duration)
	MatchService.announce({ kind = "Timeout", team = req.team, name = req.name })
	waitUntil()
	MatchService.timeoutReady = nil
end

------------------------------------------------------------------------------------------
-- flow
------------------------------------------------------------------------------------------

function MatchService.playRally()
	local TS, BS = reg.TeamService, reg.BallService
	TS.hotJoin()
	TS.ensureBodies()
	checkAbort()
	if halted() then
		return nil
	end
	if MatchService.pendingTimeout then
		MatchService.runTimeout()
	end
	local server = TS.serverOf(MatchService.servingTeam)
	MatchService.serverId = server and server.id
	MatchService.rallyResult = nil
	MatchService.rallyHits = {}
	for _, team in ipairs(Config.TeamOrder) do
		TS.setChain(team, 0) -- Chain Reaction starts again every rally
	end
	TS.resetStatic() -- and Thunder's Static Charge
	TS.resetPositions(MatchService.servingTeam)
	if server then
		BS.hold(server.id)
	end
	MatchService.setPhase("PreServe", M.PreServeTime)
	waitUntil(MatchService.phaseEnd)
	if halted() then
		return nil
	end
	MatchService.setPhase("Serving", M.ServeClock)
	MatchService.announce({ kind = "Serve", team = MatchService.servingTeam, id = MatchService.serverId, name = server and server.name })

	while not MatchService.rallyResult do
		checkAbort()
		if halted() then
			return nil
		end
		if MatchService.phase == "Serving" and BS.state == "Held" then
			if not TS.getEntity(BS.holderId) then
				local s = TS.serverOf(MatchService.servingTeam)
				if s then
					BS.hold(s.id)
					MatchService.serverId = s.id
					MatchService.broadcast()
				end
			elseif Util.now() > MatchService.phaseEnd then
				MatchService.rallyResult = {
					winner = Court.other(MatchService.servingTeam),
					reason = "ServeClock",
					byId = BS.holderId,
					error = true,
				}
			end
		end
		task.wait()
	end
	return MatchService.rallyResult
end

function MatchService.playSet()
	local TS = reg.TeamService
	if halted() then
		return nil -- forfeited or called off between sets
	end
	MatchService.target = MatchService.rules.points
	TS.resetSetAbilities()
	for _, team in ipairs(Config.TeamOrder) do
		TS.fillStamina(team) -- also re-reads the boosts (Rising Sun starts the set at level 0)
	end
	TS.resetTimeouts(MatchService.rules.timeouts)
	MatchService.announce({ kind = "SetStart", setNumber = MatchService.setNumber, target = MatchService.target })
	while true do
		local res = MatchService.playRally()
		if halted() or not res then
			return nil
		end
		local setOver = MatchService.awardPoint(res)
		if setOver then
			return res.winner
		end
		if halted() then
			return nil
		end
	end
end

-- A ranked match (Config.Ranked): each team's average RP before it, and who's had their result
-- (a player who leaves mid-match takes their loss at once: MatchService.onLeaving).
local function teamRp()
	local avg = {}
	for _, team in ipairs(Config.TeamOrder) do
		local sum, n = 0, 0
		for _, e in ipairs(reg.TeamService.members(team)) do
			if e.player then
				sum = sum + reg.ProfileService.rankedRp(e.player)
				n = n + 1
			end
		end
		avg[team] = n > 0 and sum / n or 0
	end
	return avg
end

local function results(winner, forfeitTeam)
	local list = {}
	local ranked = MatchService.lobby and MatchService.lobby.ranked
	local avgRp = ranked and (MatchService.rankedAvg or teamRp()) or nil
	local mvp, mvpScore = nil, -math.huge
	local P = Config.Progression
	local tutorial = MatchService.lobby and MatchService.lobby.tutorial
	-- a tournament's matches pay only its prize (LobbyService, Cups.payout), and a Halloween Match's
	-- only its Candy (ProfileService.eventPayout)
	local cup = MatchService.lobby and (MatchService.lobby.cup or MatchService.lobby.event)
	-- a custom lobby's shorter sets pay less and don't count for your record (a 3-point match
	-- against bots would farm them)
	local points = MatchService.rules.points
	local scale = Rewards.pointsScale(points)
	local counts = not tutorial and not cup and points >= M.PointsPerSet
	-- a forfeit before ForfeitWinMinPoints points were played isn't a win for the other side: no
	-- record, no streak, no VP (a second account forfeiting at once farmed thousands of wins). The
	-- side that forfeits still takes its loss.
	local played = (MatchService.totals.Home or 0) + (MatchService.totals.Away or 0)
	local hollow = forfeitTeam ~= nil and played < M.ForfeitWinMinPoints
	-- the teams with a developer on them (beating one earns the Dev Defeater card)
	local devTeam = {}
	for _, team in ipairs(Config.TeamOrder) do
		for _, e in ipairs(reg.TeamService.members(team)) do
			if e.player and reg.ProfileService.isDev(e.player) then
				devTeam[team] = true
			end
		end
	end
	for _, team in ipairs(Config.TeamOrder) do
		for _, e in ipairs(reg.TeamService.members(team)) do
			local st = e.stats
			local score = st.kills + st.aces * 1.5 + st.blocks * 1.5 + st.digs * 0.5 + st.assists * 0.4 - st.errors * 0.6
			if team == winner then
				score = score + 0.5
			end
			local reward, gold, streak, streakVP, streakGold, extraVP = nil, nil, nil, nil, nil, nil
			local boostVP, boostGold = 1, 1
			local rpDelta = nil
			if e.player then
				local won = team == winner
				local empty = hollow and team ~= forfeitTeam -- the other side of an early forfeit
				if ranked and not empty and not MatchService.rankedDone[e.player] then
					MatchService.rankedDone[e.player] = true
					rpDelta = reg.ProfileService.rankedResult(e.player, won, avgRp[Court.other(team)] or 0)
				end
				if counts and not empty then
					local beatDev = false
					for t in pairs(devTeam) do
						if t ~= team then
							beatDev = true
						end
					end
					streak = reg.ProfileService.recordResult(e.player, won, st, beatDev)
				end
				if team ~= forfeitTeam and not cup and not empty then
					local plays = st.kills + st.aces + st.blocks
					reward, gold = Rewards.match(won, plays)
					local xv, xg = Rewards.extraSets(MatchService.setWinners, team)
					extraVP = xv > 0 and xv or nil
					reward, gold = reward + xv, gold + xg
					if won and streak then
						streakVP, streakGold = Rewards.streakBonus(streak)
						reward, gold = reward + streakVP, gold + streakGold
					end
					if scale < 1 then
						reward, gold = math.floor(reward * scale + 0.5), math.floor(gold * scale + 0.5)
					end
					-- the admin panel's events (2x VP, 2x Gold)
					-- and the player's own 2x VP boost (Config.Boosts) and game passes (Config.Passes):
					-- they multiply (ProfileService.vpMult: tournament prizes and daily rewards pay it too)
					boostVP = reg.ProfileService.vpMult(e.player)
					boostGold = reg.AdminService.multiplier("Gold") * reg.ProfileService.passMult(e.player, "Gold") * (reg.ClanService and reg.ClanService.bonus(e.player, "Gold") or 1)
					reward, gold = math.floor(reward * boostVP + 0.5), math.floor(gold * boostGold + 0.5)
					reg.ProfileService.award(e.player, reward, gold)
				end
			end
			table.insert(list, {
				id = e.id,
				name = e.name,
				char = e.charName,
				team = team,
				isBot = e.isBot,
				tier = e.tier,
				role = e.role,
				pose = reg.TeamService.poseOf(e),
				kills = st.kills,
				aces = st.aces,
				blocks = st.blocks,
				digs = st.digs,
				assists = st.assists,
				errors = st.errors,
				topKmh = st.topKmh,
				reward = reward,
				gold = gold,
				extraVP = extraVP,
				streak = streak,
				streakVP = (streakVP or 0) > 0 and streakVP or nil,
				streakGold = (streakGold or 0) > 0 and streakGold or nil,
				boostVP = boostVP > 1 and boostVP or nil,
				boostGold = boostGold > 1 and boostGold or nil,
				rp = rpDelta,
			})
			if score > mvpScore then
				mvp, mvpScore = e, score
			end
		end
	end
	-- the MVP's bonus V Points
	if mvp and mvp.player and mvp.team ~= forfeitTeam and not cup then
		local bonus = math.floor(P.MvpVP * reg.ProfileService.vpMult(mvp.player) + 0.5)
		reg.ProfileService.award(mvp.player, bonus, 0)
		if counts then
			reg.ProfileService.addMvp(mvp.player) -- the MVP player card counts these
		end
		for _, row in ipairs(list) do
			if row.id == mvp.id then
				row.reward = (row.reward or 0) + bonus
				row.mvpBonus = bonus
			end
		end
	end
	return list, mvp
end

-- After a set: everyone on court votes Keep playing or End match. The match goes on when more
-- players want to keep playing than to stop (at least one); no vote in time ends it.
function MatchService.askContinue(winner)
	local P = Config.Progression
	MatchService.continueVotes = {}
	MatchService.setPhase("Continue", M.ContinueTime)
	MatchService.announce({
		kind = "SetEnd",
		winner = winner,
		sets = MatchService.sets,
		scores = MatchService.scores,
		setNumber = MatchService.setNumber,
		offer = { winVP = P.ExtraSetWinVP, winGold = P.ExtraSetWinGold, lossVP = P.ExtraSetLossVP, lossGold = P.ExtraSetLossGold },
	})
	while Util.now() < MatchService.phaseEnd and not halted() do
		local yes, no, total = tallyContinue()
		if total == 0 or yes + no >= total then
			break
		end
		task.wait(0.1)
	end
	local yes, no = tallyContinue()
	MatchService.continueVotes = nil
	return not halted() and yes > 0 and yes > no
end

-- A custom match's modifiers (Config.Mutators; the lobby's string, nil for none): the Mutators
-- attribute every script and client reads, and gravity (the players' through the workspace, the
-- ball's through HitLogic; clients follow the attribute the same way).
function MatchService.setMutators(s)
	s = (type(s) == "string" and s ~= "") and s or nil
	ReplicatedStorage:SetAttribute("Mutators", s)
	local e = Mutators.effects(s)
	local g = e and e.gravity or 1
	workspace.Gravity = Config.Player.Gravity * g
	HitLogic.setGravity(g)
end

function MatchService.playMatch()
	local TS, BS = reg.TeamService, reg.BallService
	local lobby = MatchService.lobby
	-- dress the arena first: players are placed on the court right after
	MatchService.court = Lobbies.courtFor(lobby, MatchService.court)
	MatchService.rules = Lobbies.rules(lobby)
	MatchService.target = MatchService.rules.points
	-- a tournament's modifiers, for every server script and client (Cups)
	ReplicatedStorage:SetAttribute("CupMods", lobby.cup and lobby.cup.mods or nil)
	MatchService.setMutators(lobby.mutators)
	lobby.cupResult = nil
	lobby.eventResult = nil
	reg.ArenaBuilder.setCourt(MatchService.court)
	TS.botTier = lobby.botTier
	TS.event = lobby.event -- the Halloween Match's cards (TeamService.dealHex)
	TS.assign(lobby.mode, reg.LobbyService.plan(lobby), Lobbies.botPicks(lobby))
	TS.resetStats()
	MatchService.rankedDone = {}
	MatchService.rankedAvg = nil
	MatchService.matchKey = lobby.ranked and HttpService:GenerateGUID(false) or nil -- (a leaver's way back in)
	if lobby.ranked then
		MatchService.runBans()
		MatchService.rankedAvg = teamRp()
	end
	MatchService.pendingTimeout = nil
	MatchService.forfeitTeam = nil
	MatchService.forfeitVotes = { Home = {}, Away = {} }
	MatchService.aborted = false
	MatchService.scores = { Home = 0, Away = 0 }
	MatchService.lossStreak = { Home = 0, Away = 0 } -- points each team has lost in a row (stamina comes back faster)
	MatchService.sets = { Home = 0, Away = 0 }
	MatchService.totals = { Home = 0, Away = 0 }
	MatchService.setWinners = {}
	MatchService.setNumber = 1
	MatchService.servingTeam = Config.TeamOrder[math.random(2)]
	TS.resetPositions(MatchService.servingTeam)
	BS.hide()
	MatchService.setPhase("PreMatch", M.PreMatchTime)
	MatchService.announce({ kind = "MatchStart", mode = TS.teamSize, court = MatchService.court, cup = lobby.cup and { name = lobby.cup.name, round = lobby.cup.round, mods = lobby.cup.mods } or nil, event = lobby.event and { diff = lobby.event.diff, stage = lobby.event.stage, stages = Config.Halloween.Stages } or nil })
	waitUntil(MatchService.phaseEnd)

	while true do
		local winner = MatchService.playSet()
		if MatchService.aborted then
			-- nobody left to play for: no results, no rewards
			BS.hide()
			MatchService.announce({ kind = "MatchAbort" })
			return
		end
		if not MatchService.forfeitTeam then
			MatchService.sets[winner] = MatchService.sets[winner] + 1
			table.insert(MatchService.setWinners, winner)
		end
		BS.hide()
		-- keep playing? Best of 3 or 5 plays on until a team has won most of them; otherwise the
		-- scheduled sets first, then a vote after each
		local more = false
		local R = MatchService.rules
		if not MatchService.forfeitTeam and R.sets > 1 then
			if MatchService.sets[winner] < math.floor(R.sets / 2) + 1 then
				MatchService.setPhase("SetEnd", M.SetEndTime)
				MatchService.announce({ kind = "SetEnd", winner = winner, sets = MatchService.sets, scores = MatchService.scores, setNumber = MatchService.setNumber })
				waitUntil(MatchService.phaseEnd)
				more = true
			end
		elseif not MatchService.forfeitTeam and MatchService.setNumber < M.MaxSets and not lobby.cup and not lobby.event then
			if MatchService.setNumber < M.Sets then
				MatchService.setPhase("SetEnd", M.SetEndTime)
				MatchService.announce({ kind = "SetEnd", winner = winner, sets = MatchService.sets, scores = MatchService.scores, setNumber = MatchService.setNumber })
				waitUntil(MatchService.phaseEnd)
				more = true
			else
				more = MatchService.askContinue(winner)
			end
		end
		if MatchService.aborted then
			MatchService.announce({ kind = "MatchAbort" })
			return
		end
		local forfeit = MatchService.forfeitTeam
		if forfeit or not more then
			local overall = forfeit and Court.other(forfeit) or Rewards.winner(MatchService.setWinners, MatchService.totals)
			if lobby.cup then
				lobby.cupResult = { won = overall == "Home" } -- the players are Home in a cup
			end
			if lobby.event then
				lobby.eventResult = { won = overall == "Home" } -- and in a Halloween Match
			end
			local list, mvp = results(overall, forfeit)
			MatchService.forfeitTeam = nil -- let the results screen run its course
			MatchService.setPhase("MatchEnd", M.MatchEndTime)
			MatchService.announce({
				kind = "MatchEnd",
				winner = overall,
				forfeit = forfeit,
				sets = MatchService.sets,
				results = list,
				mvpId = mvp and mvp.id,
				mvpName = mvp and mvp.name,
			})
			waitUntil(MatchService.phaseEnd)
			return
		end
		MatchService.setNumber = MatchService.setNumber + 1
		MatchService.scores = { Home = 0, Away = 0 }
		MatchService.lossStreak = { Home = 0, Away = 0 } -- points each team has lost in a row (stamina comes back faster)
		MatchService.servingTeam = Court.other(winner)
	end
end

------------------------------------------------------------------------------------------
-- ranked: the bans, and leaving early
------------------------------------------------------------------------------------------

MatchService.bans = nil -- { Home = { character ids }, Away = { ... } } while a ranked match bans
MatchService.matchBans = {} -- character id -> true: banned for the rest of this ranked match
MatchService.picked = nil -- player -> true: ready in the pick after the bans (nil outside it)
MatchService.banLocked = nil -- player -> true: locked in on the bans (nil outside them)
MatchService.rankedDone = {}
local banSwapped = {} -- players moved off a banned character, put back after the match

-- Each team bans BansPerTeam characters (the owner, 2026-10-21: "implement rank bans. one for each
-- team", then "allow 2 bans per side"): BanTime seconds, the team's players' bans count in the order
-- they come until the team has its share; then whoever plays a banned character goes to their best
-- other one for this match.
function MatchService.runBans()
	local TS = reg.TeamService
	local per = Config.Ranked.BansPerTeam
	MatchService.bans = { Home = {}, Away = {} }
	MatchService.setPhase("Bans", Config.Ranked.BanTime)
	MatchService.announce({ kind = "Bans", endsAt = MatchService.phaseEnd, bans = MatchService.bans, per = per })
	-- (a ban can be changed until the end: the owner, 2026-10-22, "allow bans to be changed instead of
	-- it being locked in"), so they end when the time's up or every player on court has locked in
	MatchService.banLocked = {}
	while Util.now() < MatchService.phaseEnd and not halted() do
		local waiting = false
		for _, e in pairs(TS.entities) do
			if e.player and e.player.Parent and not MatchService.banLocked[e.player] then
				waiting = true
			end
		end
		if not waiting then
			break
		end
		task.wait(0.1)
	end
	MatchService.banLocked = nil
	local banned = {}
	for _, list in pairs(MatchService.bans) do
		for _, id in ipairs(list) do
			banned[id] = true
		end
	end
	for _, e in pairs(TS.entities) do
		if e.player and e.charId and banned[e.charId] then
			local id = reg.ProfileService.bestOwnedExcept(e.player, banned)
			if id then
				local was = e.charName or e.charId
				banSwapped[e.player] = true
				reg.ProfileService.setPracticeAs(e.player, id)
				local note = TS.swapCharacter(e.player)
				reg.ProfileService.pushTo(e.player, string.format("%s is banned this match: you're %s.%s", was, e.charName or id, note and (" " .. note) or ""))
			end
		end
	end
	MatchService.announce({ kind = "BansDone", bans = MatchService.bans })
	MatchService.bans = nil
	MatchService.matchBans = banned
	MatchService.runPick(banned)
end

-- After the bans, every player picks who they play (any character of theirs that isn't banned:
-- ProfileService's "select" in this phase): PickTime seconds, or until every player on court is ready.
function MatchService.runPick(banned)
	local TS = reg.TeamService
	local list = {}
	for id in pairs(banned or {}) do
		table.insert(list, id)
	end
	MatchService.picked = {}
	MatchService.setPhase("Pick", Config.Ranked.PickTime)
	MatchService.announce({ kind = "Pick", endsAt = MatchService.phaseEnd, banned = list })
	while Util.now() < MatchService.phaseEnd and not halted() do
		local waiting = false
		for _, e in pairs(TS.entities) do
			if e.player and e.player.Parent and not MatchService.picked[e.player] then
				waiting = true
			end
		end
		if not waiting then
			break
		end
		task.wait(0.1)
	end
	MatchService.picked = nil
	MatchService.announce({ kind = "PickDone" })
end

-- A player's "ready" in the pick (LobbyService's "pickReady" op).
function MatchService.pickReady(plr)
	if MatchService.picked and MatchService.phase == "Pick" and reg.TeamService.entityForPlayer(plr) then
		MatchService.picked[plr] = true
		MatchService.announce({ kind = "PickReady", id = reg.TeamService.entityForPlayer(plr).id })
	end
end

-- Whether a character is banned in the ranked match on now.
function MatchService.isBanned(charId)
	return MatchService.matchBans[charId] == true
end

-- A player moved off a banned character picks another of their own (the pick, a timeout): the
-- stand-in goes, so their pick (profile.char) is who they play. It never took before: the
-- stand-in stayed on top of every switch until the match ended.
function MatchService.releaseBanSwap(plr)
	if banSwapped[plr] then
		banSwapped[plr] = nil
		reg.ProfileService.setPracticeAs(plr, nil)
	end
end

-- A player's ban (LobbyService's "ban" op).
function MatchService.ban(plr, charId)
	local bans = MatchService.bans
	local e = reg.TeamService.entityForPlayer(plr)
	if not bans or MatchService.phase ~= "Bans" or not e or type(charId) ~= "string" or not Roster.get(charId) then
		return
	end
	local list = bans[e.team]
	local at = table.find(list, charId)
	if at then
		-- their team's own ban again: taken back
		table.remove(list, at)
		MatchService.announce({ kind = "BanUpdate", bans = bans, team = e.team, id = charId, removed = true, by = plr.DisplayName })
		return
	end
	for team, other in pairs(bans) do
		if team ~= e.team and table.find(other, charId) then
			return -- (the other team banned it already)
		end
	end
	if #list >= Config.Ranked.BansPerTeam then
		table.remove(list, 1) -- (a change: the team's oldest ban gives way)
	end
	table.insert(list, charId)
	MatchService.announce({ kind = "BanUpdate", bans = bans, team = e.team, id = charId, by = plr.DisplayName })
end

-- A player's "lock in" in the bans (LobbyService's "banLock" op): once every player has, the
-- bans end early.
function MatchService.banLock(plr)
	local e = reg.TeamService.entityForPlayer(plr)
	if MatchService.banLocked and MatchService.phase == "Bans" and e then
		MatchService.banLocked[plr] = true
	end
end

-- A player leaving (ProfileService, before their profile saves): leaving a ranked match early is
-- its loss.
function MatchService.onLeaving(plr)
	local lobby = MatchService.lobby
	if not lobby or not lobby.ranked or MatchService.phase == "Intermission" or MatchService.phase == "MatchEnd" then
		return
	end
	local e = reg.TeamService.entityForPlayer(plr)
	if e and not MatchService.rankedDone[plr] then
		MatchService.rankedDone[plr] = true
		local avg = MatchService.rankedAvg or teamRp()
		-- the loss and the leave penalty (Config.Ranked.Leave); the match's key and where it runs, so
		-- coming back to it undoes them (onRejoin): a reserved server's code, else this server
		local code = lobby.watchCode
		local job = (not code and game.JobId ~= "") and game.JobId or nil
		reg.ProfileService.rankedLeave(plr, avg[Court.other(e.team)] or 0, MatchService.matchKey or "", code, job)
	end
end

-- A player arriving (their profile loaded): back in the ranked match they left while it's still on,
-- their leave penalty is lifted and they take their spot back from their AI at the next serve.
function MatchService.onRejoin(plr)
	local lobby = MatchService.lobby
	if not lobby or not lobby.ranked or not MatchService.matchKey or MatchService.phase == "Intermission" or MatchService.phase == "MatchEnd" then
		return
	end
	local rec = reg.ProfileService.rankedRecord(plr)
	if not rec or not rec.left or rec.left.key ~= MatchService.matchKey then
		return
	end
	if reg.ProfileService.rankedUnleave(plr, MatchService.matchKey) then
		reg.TeamService.requestJoin(plr)
	end
end

local function unswap()
	for plr in pairs(banSwapped) do
		if plr.Parent then
			reg.ProfileService.setPracticeAs(plr, nil)
		end
	end
	table.clear(banSwapped)
end

-- The court waits here until a lobby is ready to play on it (LobbyService.nextForCourt).
function MatchService.intermission()
	local TS, BS = reg.TeamService, reg.BallService
	unswap() -- (a banned character's stand-in goes back)
	MatchService.matchBans = {}
	TS.endMatch()
	TS.event = nil
	BS.hide()
	MatchService.lobby = nil
	MatchService.serverId = nil
	MatchService.rules = Lobbies.rules(nil) -- a custom match's rules end with it
	ReplicatedStorage:SetAttribute("CupMods", nil)
	MatchService.setMutators(nil)
	MatchService.target = MatchService.rules.points
	MatchService.scores = { Home = 0, Away = 0 }
	MatchService.lossStreak = { Home = 0, Away = 0 } -- points each team has lost in a row (stamina comes back faster)
	MatchService.sets = { Home = 0, Away = 0 }
	MatchService.setPhase("Intermission", 0)
	local lobby = nil
	while not lobby do
		lobby = reg.LobbyService.nextForCourt()
		if not lobby then
			task.wait(0.25)
		end
	end
	MatchService.lobby = lobby
	MatchService.mode = lobby.mode
end

function MatchService.start()
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				MatchService.intermission()
				if MatchService.lobby.practice then
					reg.PracticeService.run(MatchService.lobby)
				else
					MatchService.playMatch()
				end
			end)
			if MatchService.lobby then
				reg.LobbyService.finished(MatchService.lobby)
				MatchService.lobby = nil
			end
			if not ok then
				warn("[SpikeRush] match loop error: " .. tostring(err))
				task.wait(2)
			end
		end
	end)
end

function MatchService.init(r)
	reg = r
	Net.get("Timeout").OnServerEvent:Connect(function(plr, op)
		local TS = reg.TeamService
		local e = TS.entityForPlayer(plr)
		if not e or not TS.inMatch then
			return
		end
		-- a press calls one, calls off your own before it starts, or in the timeout is Ready
		if op ~= "ready" then
			op = Lobbies.timeoutPress(MatchService.pendingTimeout, MatchService.phase, e.id, TS.timeouts[e.team] or 0)
		end
		if op == "ready" then
			-- done with the timeout: once everyone on court is ready it ends early
			if MatchService.phase == "Timeout" and MatchService.timeoutReady then
				MatchService.timeoutReady[plr.UserId] = true
				local n, total = tallyReady()
				if n >= total then
					MatchService.phaseEnd = Util.now()
				end
				MatchService.broadcast()
			end
		elseif op == "cancel" then
			-- never started, so never used (runTimeout spends it)
			local req = MatchService.pendingTimeout
			MatchService.pendingTimeout = nil
			MatchService.announce({ kind = "TimeoutCancelled", team = req.team, name = req.name, id = req.id })
			MatchService.broadcast()
		elseif op == "call" then
			MatchService.pendingTimeout = { team = e.team, name = e.name, id = e.id }
			MatchService.announce({ kind = "TimeoutCalled", team = e.team, name = e.name, id = e.id })
			MatchService.broadcast()
		end
	end)
	-- during a timeout, either team can rearrange its rotation and pick its next server
	Net.get("Rotation").OnServerEvent:Connect(function(plr, op, id)
		local TS = reg.TeamService
		local e = TS.entityForPlayer(plr)
		if not e or not TS.inMatch or MatchService.phase ~= "Timeout" or type(id) ~= "string" then
			return
		end
		if op ~= "up" and op ~= "down" and op ~= "serve" then
			return
		end
		if TS.reorder(e.team, op, id, e.team == MatchService.servingTeam) then
			MatchService.broadcast()
		end
	end)
	-- after a set: keep playing (true) or end the match (false)
	Net.get("Continue").OnServerEvent:Connect(function(plr, keep)
		if MatchService.phase ~= "Continue" or not MatchService.continueVotes or not reg.TeamService.entityForPlayer(plr) then
			return
		end
		MatchService.continueVotes[plr.UserId] = keep == true
		MatchService.broadcast()
	end)
	-- a player votes to give up the match for their team (the client asks twice before sending);
	-- pressing again takes the vote back. It goes through once every player on the team voted
	Net.get("Forfeit").OnServerEvent:Connect(function(plr)
		local TS = reg.TeamService
		local e = TS.entityForPlayer(plr)
		local phase = MatchService.phase
		if not e or not TS.inMatch or MatchService.forfeitTeam or phase == "MatchEnd" or phase == "Intermission" then
			return
		end
		local votes = MatchService.forfeitVotes[e.team]
		local now = os.clock()
		if votes[plr.UserId] and now - votes[plr.UserId] < M.ForfeitVoteTime then
			votes[plr.UserId] = nil
			-- (taking back the team's last vote leaves no tally at all: forfeitTally is nil then)
			local left = MatchService.forfeitTally()
			MatchService.announce({ kind = "ForfeitVote", team = e.team, name = e.name, off = true, tally = left and left[e.team] })
			MatchService.broadcast()
			return
		end
		votes[plr.UserId] = now
		local all = MatchService.forfeitTally()
		local tally = all and all[e.team]
		if tally and tally[1] >= tally[2] then
			MatchService.forfeitVotes[e.team] = {}
			MatchService.forfeitTeam = e.team
			MatchService.announce({ kind = "Forfeit", team = e.team, name = e.name })
		else
			MatchService.announce({ kind = "ForfeitVote", team = e.team, name = e.name, tally = tally })
			MatchService.broadcast()
		end
	end)
	Net.get("ClientReady").OnServerEvent:Connect(function(plr)
		Net.get("MatchState"):FireClient(plr, MatchService.state())
		reg.BallService.sendTo(plr)
	end)
	reg.BallService.onDead:Connect(function(landing, flags, last)
		if (MatchService.phase == "Rally" or MatchService.phase == "Serving") and not MatchService.rallyResult then
			MatchService.rallyResult = MatchService.judge(landing, flags or {}, last)
		end
	end)
end

return MatchService
