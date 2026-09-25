-- Match rewards: the win or loss reward with the per-play bonus, the extra sets played past the
-- first, and the win streak bonus. Shared so the server and the headless tests use the same math.

local Config = require(script.Parent.Config)

local Rewards = {}
local P = Config.Progression

-- The match reward: win or loss, plus a bit per kill, ace or block. Returns VP, Gold.
function Rewards.match(won, plays)
	plays = plays or 0
	local vp = (won and P.WinVP or P.LossVP) + P.PlayVP * plays
	local gold = (won and P.WinGold or P.LossGold) + P.PlayGold * plays
	return vp, gold
end

-- Every set past the first pays on its own: more for the sets `team` won. setWinners[i] is the
-- team that won set i. Returns VP, Gold.
function Rewards.extraSets(setWinners, team)
	local vp, gold = 0, 0
	for i = 2, #setWinners do
		if setWinners[i] == team then
			vp = vp + P.ExtraSetWinVP
			gold = gold + P.ExtraSetWinGold
		else
			vp = vp + P.ExtraSetLossVP
			gold = gold + P.ExtraSetLossGold
		end
	end
	return vp, gold
end

-- The win streak after this match (a loss resets it).
function Rewards.nextStreak(streak, won)
	if won then
		return (streak or 0) + 1
	end
	return 0
end

-- The bonus for winning with this streak (counting this win): nothing for the first win, then
-- one step more per straight win, up to StreakMaxSteps. Returns VP, Gold.
function Rewards.streakBonus(streak)
	local steps = math.min(math.max(0, (streak or 0) - 1), P.StreakMaxSteps)
	return steps * P.StreakVP, steps * P.StreakGold
end

-- Who won the match: the most sets, then the most points over all sets, then the last set.
function Rewards.winner(setWinners, points)
	local count = {}
	for _, t in ipairs(setWinners) do
		count[t] = (count[t] or 0) + 1
	end
	local a, b = Config.TeamOrder[1], Config.TeamOrder[2]
	local ca, cb = count[a] or 0, count[b] or 0
	if ca ~= cb then
		return ca > cb and a or b
	end
	local pa, pb = (points and points[a]) or 0, (points and points[b]) or 0
	if pa ~= pb then
		return pa > pb and a or b
	end
	return setWinners[#setWinners]
end

return Rewards
