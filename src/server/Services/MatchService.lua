-- Match flow: intermission (mode + bot level vote) -> match -> sets -> rallies, with rally-point
-- scoring, serve rotation, team stamina recovery, timeouts, stats, MVP and upgrade points.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Characters = require(Shared.Characters)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

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
MatchService.votes = {}
MatchService.botVotes = {}
MatchService.rallyResult = nil
MatchService.rallyHits = {}
MatchService.pendingTimeout = nil

local ATTACKS = { Spike = true, Feint = true, JumpServe = true, Overhand = true }

local function waitUntil(t)
	while Util.now() < t do
		task.wait(0.05)
	end
end

local function tally()
	local counts = { v1 = 0, v2 = 0, v3 = 0 }
	for _, m in pairs(MatchService.votes) do
		local key = "v" .. tostring(m)
		counts[key] = (counts[key] or 0) + 1
	end
	return counts
end

local function chooseMode()
	local counts = tally()
	local best, bestN = M.DefaultTeamSize, 0
	for _, m in ipairs({ 3, 2, 1 }) do
		local n = counts["v" .. m]
		if n > bestN then
			best, bestN = m, n
		end
	end
	-- never leave humans on the bench: grow the teams until everybody fits
	local humans = #Players:GetPlayers()
	while best < 3 and humans > best * 2 do
		best = best + 1
	end
	return best
end

-- Most-voted bot level; ties go to the stronger tier.
local function chooseBotTier()
	local counts = {}
	for _, tier in pairs(MatchService.botVotes) do
		counts[tier] = (counts[tier] or 0) + 1
	end
	local best, bestN = nil, 0
	for _, tier in ipairs(Config.Tiers) do
		local n = counts[tier] or 0
		if n > 0 and n >= bestN then
			best, bestN = tier, n
		end
	end
	return best or M.DefaultBotTier
end

function MatchService.state()
	local TS = reg.TeamService
	local mode = MatchService.mode
	if TS.inMatch then
		mode = TS.teamSize
	end
	local botTier = TS.inMatch and TS.botTier or chooseBotTier()
	return {
		phase = MatchService.phase,
		phaseEnd = MatchService.phaseEnd,
		mode = mode,
		inMatch = TS.inMatch,
		scores = MatchService.scores,
		sets = MatchService.sets,
		setNumber = MatchService.setNumber,
		target = MatchService.target,
		setsToWin = M.SetsToWin,
		servingTeam = MatchService.servingTeam,
		serverId = MatchService.serverId,
		rosters = TS.roster(),
		votes = tally(),
		botTier = botTier,
		timeoutPending = MatchService.pendingTimeout,
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
	if last.fail then
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
			if ht == "JumpServe" or ht == "Overhand" then
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

	-- stamina comes back between rallies; the team that lost the point gets more
	TS.recoverStamina(winner, Config.Stamina.RecoverWinner)
	TS.recoverStamina(loser, Config.Stamina.RecoverLoser)

	local sideOut = winner ~= MatchService.servingTeam
	if sideOut then
		TS.rotate(winner)
		MatchService.servingTeam = winner
	end

	local s = MatchService.scores
	local target = MatchService.target
	local setOver = (s[winner] >= target and s[winner] - s[loser] >= M.WinBy) or s[winner] >= M.PointCap
	local setPoint = nil
	if not setOver then
		for _, team in ipairs(Config.TeamOrder) do
			local mine, theirs = s[team] + 1, s[Court.other(team)]
			if (mine >= target and mine - theirs >= M.WinBy) or mine >= M.PointCap then
				setPoint = team
			end
		end
	end
	local matchPoint = setPoint ~= nil and MatchService.sets[setPoint] == M.SetsToWin - 1

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
	MatchService.setPhase("Timeout", Config.Timeout.Duration)
	MatchService.announce({ kind = "Timeout", team = req.team, name = req.name })
	waitUntil(MatchService.phaseEnd)
end

------------------------------------------------------------------------------------------
-- flow
------------------------------------------------------------------------------------------

function MatchService.playRally()
	local TS, BS = reg.TeamService, reg.BallService
	TS.hotJoin()
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
	MatchService.setPhase("Serving", M.ServeClock)
	MatchService.announce({ kind = "Serve", team = MatchService.servingTeam, id = MatchService.serverId, name = server and server.name })

	while not MatchService.rallyResult do
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
	if MatchService.setNumber >= M.SetsToWin * 2 - 1 then
		MatchService.target = M.DecidingSetPoints
	else
		MatchService.target = M.PointsPerSet
	end
	for _, team in ipairs(Config.TeamOrder) do
		TS.fillStamina(team)
	end
	TS.resetTimeouts()
	MatchService.announce({ kind = "SetStart", setNumber = MatchService.setNumber, target = MatchService.target })
	while true do
		local res = MatchService.playRally()
		local setOver = MatchService.awardPoint(res)
		if setOver then
			return res.winner
		end
	end
end

local function results(winner)
	local list = {}
	local mvp, mvpScore = nil, -math.huge
	local P = Config.Progression
	for _, team in ipairs(Config.TeamOrder) do
		for _, e in ipairs(reg.TeamService.members(team)) do
			local st = e.stats
			local score = st.kills + st.aces * 1.5 + st.blocks * 1.5 + st.digs * 0.5 + st.assists * 0.4 - st.errors * 0.6
			if team == winner then
				score = score + 0.5
			end
			local reward = nil
			if e.player then
				reward = (team == winner and P.WinPoints or P.LossPoints) + P.PlayPoints * (st.kills + st.aces + st.blocks)
				reg.ProfileService.award(e.player, reward)
			end
			table.insert(list, {
				id = e.id,
				name = e.name,
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
			})
			if score > mvpScore then
				mvp, mvpScore = e, score
			end
		end
	end
	return list, mvp
end

function MatchService.playMatch()
	local TS, BS = reg.TeamService, reg.BallService
	TS.botTier = chooseBotTier()
	TS.assign(MatchService.mode)
	TS.resetStats()
	MatchService.pendingTimeout = nil
	MatchService.scores = { Home = 0, Away = 0 }
	MatchService.sets = { Home = 0, Away = 0 }
	MatchService.setNumber = 1
	MatchService.servingTeam = Config.TeamOrder[math.random(2)]
	TS.resetPositions(MatchService.servingTeam)
	BS.hide()
	MatchService.setPhase("PreMatch", M.PreMatchTime)
	MatchService.announce({ kind = "MatchStart", mode = TS.teamSize })
	waitUntil(MatchService.phaseEnd)

	while true do
		local winner = MatchService.playSet()
		MatchService.sets[winner] = MatchService.sets[winner] + 1
		if MatchService.sets[winner] >= M.SetsToWin then
			local list, mvp = results(winner)
			BS.hide()
			MatchService.setPhase("MatchEnd", M.MatchEndTime)
			MatchService.announce({
				kind = "MatchEnd",
				winner = winner,
				sets = MatchService.sets,
				results = list,
				mvpId = mvp and mvp.id,
				mvpName = mvp and mvp.name,
			})
			waitUntil(MatchService.phaseEnd)
			return
		end
		BS.hide()
		MatchService.setPhase("SetEnd", M.SetEndTime)
		MatchService.announce({ kind = "SetEnd", winner = winner, sets = MatchService.sets, scores = MatchService.scores, setNumber = MatchService.setNumber })
		waitUntil(MatchService.phaseEnd)
		MatchService.setNumber = MatchService.setNumber + 1
		MatchService.scores = { Home = 0, Away = 0 }
		MatchService.servingTeam = Court.other(winner)
	end
end

function MatchService.intermission()
	local TS, BS = reg.TeamService, reg.BallService
	TS.endMatch()
	BS.hide()
	MatchService.votes = {}
	MatchService.serverId = nil
	MatchService.scores = { Home = 0, Away = 0 }
	MatchService.sets = { Home = 0, Away = 0 }
	MatchService.setPhase("Intermission", M.IntermissionTime)
	while #Players:GetPlayers() < M.MinHumansToStart do
		MatchService.phaseEnd = Util.now() + M.IntermissionTime
		MatchService.broadcast()
		task.wait(1)
	end
	while Util.now() < MatchService.phaseEnd do
		local humans = #Players:GetPlayers()
		local voted = 0
		for _ in pairs(MatchService.votes) do
			voted = voted + 1
		end
		if humans > 0 and voted >= humans and MatchService.phaseEnd - Util.now() > M.IntermissionFastTime then
			MatchService.phaseEnd = Util.now() + M.IntermissionFastTime
			MatchService.broadcast()
		end
		task.wait(0.2)
	end
	MatchService.mode = chooseMode()
end

function MatchService.start()
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				MatchService.intermission()
				MatchService.playMatch()
			end)
			if not ok then
				warn("[SpikeRush] match loop error: " .. tostring(err))
				task.wait(2)
			end
		end
	end)
end

function MatchService.init(r)
	reg = r
	-- ("mode", 1|2|3) or ("botTier", "S+")
	Net.get("Vote").OnServerEvent:Connect(function(plr, kind, value)
		if MatchService.phase ~= "Intermission" then
			return
		end
		if kind == "mode" and (value == 1 or value == 2 or value == 3) then
			MatchService.votes[plr.UserId] = value
		elseif kind == "botTier" and Characters.isTier(value) then
			MatchService.botVotes[plr.UserId] = value
		else
			return
		end
		MatchService.broadcast()
	end)
	Net.get("Timeout").OnServerEvent:Connect(function(plr)
		local TS = reg.TeamService
		local e = TS.entityForPlayer(plr)
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
	Net.get("ClientReady").OnServerEvent:Connect(function(plr)
		Net.get("MatchState"):FireClient(plr, MatchService.state())
		reg.BallService.sendTo(plr)
	end)
	Players.PlayerRemoving:Connect(function(plr)
		MatchService.votes[plr.UserId] = nil
		MatchService.botVotes[plr.UserId] = nil
	end)
	reg.BallService.onDead:Connect(function(landing, flags, last)
		if MatchService.phase == "Rally" or MatchService.phase == "Serving" then
			MatchService.rallyResult = MatchService.judge(landing, flags or {}, last)
		end
	end)
end

return MatchService
