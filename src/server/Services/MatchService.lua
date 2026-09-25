-- Match flow: intermission (the court waits for a lobby, see LobbyService) -> match -> sets ->
-- rallies, with rally-point scoring, serve rotation, team stamina recovery, timeouts, stats, MVP
-- and rewards. A match is one set (Match.Sets); after it the players vote to keep playing for
-- the extra set rewards (Continue phase), up to Match.MaxSets. Rewards (the Rewards module):
-- win or loss, plays, extra sets, the MVP bonus and the win streak bonus. A timeout ends early
-- once every player on court has pressed Ready. A match with no humans left on court (everyone
-- left or went AFK) is called off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Rewards = require(Shared.Rewards)

local MatchService = {}
local reg
local M = Config.Match

MatchService.phase = "Intermission"
MatchService.phaseEnd = 0
MatchService.mode = M.DefaultTeamSize
MatchService.scores = { Home = 0, Away = 0 }
MatchService.sets = { Home = 0, Away = 0 }
MatchService.setNumber = 1
MatchService.target = M.PointsPerSet
MatchService.servingTeam = "Home"
MatchService.serverId = nil
MatchService.rallyResult = nil
MatchService.rallyHits = {}
MatchService.pendingTimeout = nil
MatchService.lobby = nil -- the lobby playing on this court
MatchService.aborted = false
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
-- playing while they're still in the server).
local function checkAbort()
	local TS = reg.TeamService
	if TS.inMatch and TS.humanCount() == 0 and #TS.pendingJoin == 0 and TS.benchedCount() == 0 then
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
		maxSets = M.MaxSets,
		servingTeam = MatchService.servingTeam,
		serverId = MatchService.serverId,
		rosters = TS.roster(),
		botTier = TS.botTier,
		timeoutPending = MatchService.pendingTimeout,
		lobbyId = l and l.id,
		continueVote = MatchService.continueVotes and { tallyContinue() } or nil,
		timeoutReady = MatchService.timeoutReady and { tallyReady() } or nil,
		tutorial = l and l.tutorial or nil,
	}
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

function MatchService.onServeHit()
	MatchService.setPhase("Rally", 0)
end

function MatchService.onHit(entity, meta, previous)
	table.insert(MatchService.rallyHits, { id = entity.id, team = entity.team, hitType = meta.hitType })
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

	-- a won rally ticks the tutorial's last step for the winners
	for _, e in ipairs(TS.members(winner)) do
		if e.player then
			reg.ProfileService.tutorialStep(e.player, { "point" })
		end
	end

	-- stamina comes back between rallies; the team that lost the point gets more
	TS.recoverStamina(winner, Config.Stamina.RecoverWinner)
	TS.recoverStamina(loser, Config.Stamina.RecoverLoser)

	local sideOut = winner ~= MatchService.servingTeam
	if sideOut then
		TS.rotate(winner)
		MatchService.servingTeam = winner
	end

	local s = MatchService.scores
	local base = MatchService.target
	local playTo, deuce = Court.playTo(s[winner], s[loser], base)
	local setOver = s[winner] >= playTo
	local setPoint = nil
	if not setOver then
		for _, team in ipairs(Config.TeamOrder) do
			local mine, theirs = s[team] + 1, s[Court.other(team)]
			if mine >= Court.playTo(mine, theirs, base) then
				setPoint = team
			end
		end
	end
	local matchPoint = setPoint ~= nil and MatchService.setNumber >= M.Sets -- any set from here may be the last

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
	MatchService.target = M.PointsPerSet
	for _, team in ipairs(Config.TeamOrder) do
		TS.fillStamina(team)
	end
	TS.resetTimeouts()
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

local function results(winner, forfeitTeam)
	local list = {}
	local mvp, mvpScore = nil, -math.huge
	local P = Config.Progression
	local tutorial = MatchService.lobby and MatchService.lobby.tutorial
	for _, team in ipairs(Config.TeamOrder) do
		for _, e in ipairs(reg.TeamService.members(team)) do
			local st = e.stats
			local score = st.kills + st.aces * 1.5 + st.blocks * 1.5 + st.digs * 0.5 + st.assists * 0.4 - st.errors * 0.6
			if team == winner then
				score = score + 0.5
			end
			local reward, gold, streak, streakVP, streakGold, extraVP = nil, nil, nil, nil, nil, nil
			if e.player then
				local won = team == winner
				if not tutorial then
					streak = reg.ProfileService.recordResult(e.player, won, st)
				end
				if team ~= forfeitTeam then
					local plays = st.kills + st.aces + st.blocks
					reward, gold = Rewards.match(won, plays)
					local xv, xg = Rewards.extraSets(MatchService.setWinners, team)
					extraVP = xv > 0 and xv or nil
					reward, gold = reward + xv, gold + xg
					if won and streak then
						streakVP, streakGold = Rewards.streakBonus(streak)
						reward, gold = reward + streakVP, gold + streakGold
					end
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
			})
			if score > mvpScore then
				mvp, mvpScore = e, score
			end
		end
	end
	-- the MVP's bonus V Points
	if mvp and mvp.player and mvp.team ~= forfeitTeam then
		reg.ProfileService.award(mvp.player, P.MvpVP, 0)
		for _, row in ipairs(list) do
			if row.id == mvp.id then
				row.reward = (row.reward or 0) + P.MvpVP
				row.mvpBonus = P.MvpVP
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

function MatchService.playMatch()
	local TS, BS = reg.TeamService, reg.BallService
	local lobby = MatchService.lobby
	TS.botTier = lobby.botTier
	TS.assign(lobby.mode, reg.LobbyService.plan(lobby))
	TS.resetStats()
	MatchService.pendingTimeout = nil
	MatchService.forfeitTeam = nil
	MatchService.aborted = false
	MatchService.scores = { Home = 0, Away = 0 }
	MatchService.sets = { Home = 0, Away = 0 }
	MatchService.totals = { Home = 0, Away = 0 }
	MatchService.setWinners = {}
	MatchService.setNumber = 1
	MatchService.servingTeam = Config.TeamOrder[math.random(2)]
	TS.resetPositions(MatchService.servingTeam)
	BS.hide()
	MatchService.setPhase("PreMatch", M.PreMatchTime)
	MatchService.announce({ kind = "MatchStart", mode = TS.teamSize })
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
		-- keep playing? (the scheduled sets first, then a vote after each)
		local more = false
		if not MatchService.forfeitTeam and MatchService.setNumber < M.MaxSets then
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
		MatchService.servingTeam = Court.other(winner)
	end
end

-- The court waits here until a lobby is ready to play on it (LobbyService.nextForCourt).
function MatchService.intermission()
	local TS, BS = reg.TeamService, reg.BallService
	TS.endMatch()
	BS.hide()
	MatchService.lobby = nil
	MatchService.serverId = nil
	MatchService.scores = { Home = 0, Away = 0 }
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
				MatchService.playMatch()
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
		if op == "ready" then
			-- done with the timeout: once everyone on court is ready it ends early
			if e and MatchService.phase == "Timeout" and MatchService.timeoutReady then
				MatchService.timeoutReady[plr.UserId] = true
				local n, total = tallyReady()
				if n >= total then
					MatchService.phaseEnd = Util.now()
				end
				MatchService.broadcast()
			end
			return
		end
		if not e or not TS.inMatch or MatchService.pendingTimeout then
			return
		end
		local phase = MatchService.phase
		if phase == "Intermission" or phase == "PreMatch" or phase == "MatchEnd" then
			return
		end
		if (TS.timeouts[e.team] or 0) <= 0 then
			return
		end
		MatchService.pendingTimeout = { team = e.team, name = e.name }
		MatchService.announce({ kind = "TimeoutCalled", team = e.team, name = e.name })
		MatchService.broadcast()
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
	-- a player gives up the match for their team (the client asks twice before sending)
	Net.get("Forfeit").OnServerEvent:Connect(function(plr)
		local TS = reg.TeamService
		local e = TS.entityForPlayer(plr)
		local phase = MatchService.phase
		if not e or not TS.inMatch or MatchService.forfeitTeam or phase == "MatchEnd" or phase == "Intermission" then
			return
		end
		MatchService.forfeitTeam = e.team
		MatchService.announce({ kind = "Forfeit", team = e.team, name = e.name })
	end)
	Net.get("ClientReady").OnServerEvent:Connect(function(plr)
		Net.get("MatchState"):FireClient(plr, MatchService.state())
		reg.BallService.sendTo(plr)
	end)
	reg.BallService.onDead:Connect(function(landing, flags, last)
		if MatchService.phase == "Rally" or MatchService.phase == "Serving" then
			MatchService.rallyResult = MatchService.judge(landing, flags or {}, last)
		end
	end)
end

return MatchService
