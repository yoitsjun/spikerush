-- Daily missions and character mastery (Config.Missions, Config.Mastery; the owner, 2026-11-11:
-- "add masteries to incentivize people to play. just like the spike cross. and quests too",
-- "clear challenges and get some rewards and a mastery unlock"). Pure and shared: the server
-- counts and pays, the client draws the same answers; covered by the sims.
--
-- Daily missions: the same Count missions for everyone each day (Check in first, the rest drawn
-- from the pool by the day), Points each; at Goal points the day's reward can be claimed once.
-- profile.missions = { day, stats = { [stat] = n }, claimed }: a new day starts it again.
--
-- Mastery, per character: a rank (Rookie first) and three counters of the points you scored as
-- that character in matches you WON, by where (match, story, cup). Meeting every Need of the
-- next rank lets you claim its reward, which is the promotion. The counters never reset.
-- profile.mastery = { [character id] = { rank, match, story, cup } }

local Config = require(script.Parent.Config)
local Roster = require(script.Parent.Roster)

local Missions = {}
local MC = Config.Missions
local MA = Config.Mastery

local BY_KEY = {}
for _, m in ipairs(MC.Pool) do
	BY_KEY[m.Key] = m
end

local function whole(n)
	n = tonumber(n)
	if not n or n ~= n or n < 0 then
		return 0
	end
	return math.floor(math.min(n, 1e9))
end

------------------------------------------------------------------------------------------
-- daily missions
------------------------------------------------------------------------------------------

-- The mission day `now` (unix) falls on (days turn with Config.PlayRewards.DayOffset).
function Missions.day(now)
	return math.floor(((tonumber(now) or 0) + Config.PlayRewards.DayOffset) / 86400)
end

function Missions.secondsLeft(now)
	now = tonumber(now) or 0
	return (Missions.day(now) + 1) * 86400 - Config.PlayRewards.DayOffset - math.floor(now)
end

function Missions.def(key)
	return type(key) == "string" and BY_KEY[key] or nil
end

-- The day's missions: Check in, then Count - 1 more from the pool, shuffled by the day.
function Missions.daily(day)
	local out = { BY_KEY[MC.Always] }
	local rest = {}
	for _, m in ipairs(MC.Pool) do
		if m.Key ~= MC.Always then
			table.insert(rest, m)
		end
	end
	local seed = (whole(day) * 7919 + 13) % 2147483647
	for i = #rest, 2, -1 do
		seed = (seed * 16807) % 2147483647
		local j = seed % i + 1
		rest[i], rest[j] = rest[j], rest[i]
	end
	for i = 1, math.min(MC.Count - 1, #rest) do
		table.insert(out, rest[i])
	end
	return out
end

-- Saved missions made safe, for `day`: another day's are dropped.
function Missions.clean(data, day)
	local out = { day = whole(day), stats = {}, claimed = false }
	if type(data) == "table" and whole(data.day) == out.day then
		out.claimed = data.claimed == true
		if type(data.stats) == "table" then
			for k, v in pairs(data.stats) do
				if type(k) == "string" and #k <= 24 and whole(v) > 0 then
					out.stats[k] = whole(v)
				end
			end
		end
	end
	return out
end

-- Count things done ({ wins = 1, kills = 7, ... }) toward today's missions.
function Missions.add(state, events)
	for k, v in pairs(events or {}) do
		if type(k) == "string" and whole(v) > 0 then
			state.stats[k] = whole((state.stats[k] or 0) + whole(v))
		end
	end
end

-- A mission's progress: how far, how far it goes, whether it's done.
function Missions.progress(state, def)
	local have = math.min(whole(state.stats[def.Stat]), def.Need)
	return have, def.Need, have >= def.Need
end

-- Today's points and how many missions are done.
function Missions.points(state)
	local done = 0
	for _, def in ipairs(Missions.daily(state.day)) do
		local _, _, ok = Missions.progress(state, def)
		if ok then
			done = done + 1
		end
	end
	return math.min(done * MC.Points, MC.Goal), done
end

function Missions.canClaim(state)
	return not state.claimed and Missions.points(state) >= MC.Goal
end

-- Claim the day's reward: marks it and returns the grant, or nil.
function Missions.claim(state)
	if not Missions.canClaim(state) then
		return nil
	end
	state.claimed = true
	return MC.Reward
end

-- A mission's line: "Win 2 matches."
function Missions.text(def)
	return string.format(def.Text, def.Need)
end

-- What a finished match counts for: one player's part of it (their stats, whether they won, the
-- role and kind of match). scale: a short custom set counts for less (Rewards.pointsScale).
function Missions.matchEvents(info)
	local ev = { matches = 1 }
	ev.kills = whole(info.kills)
	ev.blocks = whole(info.blocks)
	ev.aces = whole(info.aces)
	ev.digs = whole(info.digs)
	if info.won then
		ev.wins = 1
		if info.role == "MB" or info.role == "SE" or info.role == "WS" then
			ev["win" .. info.role] = 1
		end
		if info.kind == "story" then
			ev.story = 1
		elseif info.kind == "cup" then
			ev.cupWins = 1
		end
	end
	return ev
end

------------------------------------------------------------------------------------------
-- mastery
------------------------------------------------------------------------------------------

Missions.Kinds = { "match", "story", "cup" }

function Missions.ranks()
	return MA.Ranks
end

-- Saved mastery made safe: real characters, real ranks, whole counters.
function Missions.cleanMastery(data)
	local out = {}
	if type(data) ~= "table" then
		return out
	end
	for id, row in pairs(data) do
		if type(id) == "string" and Roster.get(id) and type(row) == "table" then
			local r = { rank = math.max(1, math.min(#MA.Ranks, whole(row.rank))) }
			for _, k in ipairs(Missions.Kinds) do
				r[k] = whole(row[k])
			end
			out[id] = r
		end
	end
	return out
end

-- A character's mastery row (a fresh Rookie when they have none; not stored until it changes).
function Missions.mastery(state, charId)
	local row = type(state) == "table" and state[charId] or nil
	if row then
		return row
	end
	return { rank = 1, match = 0, story = 0, cup = 0 }
end

function Missions.rank(row)
	return MA.Ranks[row.rank] or MA.Ranks[1]
end

-- The rank after this one, or nil at the top.
function Missions.nextRank(row)
	return MA.Ranks[row.rank + 1]
end

-- The points a match is worth for mastery: only a win counts (The Spike Cross: "only matches you
-- win are recorded"), the points you scored yourself (kills, aces, blocks), a short set for less.
function Missions.masteryScore(info)
	if not info.won then
		return 0
	end
	local s = whole(info.kills) + whole(info.aces) + whole(info.blocks)
	local scale = tonumber(info.scale) or 1
	if scale < 1 and info.kind == "match" then
		s = math.floor(s * math.max(0, scale))
	end
	return s
end

-- Add a won match's score to a character's counter (`kind`: match, story or cup).
function Missions.addMastery(state, charId, kind, score)
	if not Roster.get(charId) or whole(score) <= 0 then
		return false
	end
	local okKind = false
	for _, k in ipairs(Missions.Kinds) do
		okKind = okKind or k == kind
	end
	if not okKind then
		return false
	end
	local row = state[charId]
	if not row then
		row = { rank = 1, match = 0, story = 0, cup = 0 }
		state[charId] = row
	end
	row[kind] = whole(row[kind] + whole(score))
	return true
end

-- Whether every challenge of the next rank is cleared.
function Missions.masteryReady(row)
	local nxt = Missions.nextRank(row)
	if not nxt then
		return false
	end
	for _, k in ipairs(Missions.Kinds) do
		if whole(row[k]) < (nxt.Need[k] or 0) then
			return false
		end
	end
	return true
end

-- Claim the next rank: promotes the character and returns the rank's reward and the rank, or nil.
function Missions.claimMastery(state, charId)
	local row = state[charId]
	if not row or not Missions.masteryReady(row) then
		return nil
	end
	row.rank = row.rank + 1
	local rank = MA.Ranks[row.rank]
	return rank.Reward, rank
end

-- Characters with a rank waiting to be claimed (for Home's dot).
function Missions.masteryWaiting(state)
	local n = 0
	for _, row in pairs(type(state) == "table" and state or {}) do
		if Missions.masteryReady(row) then
			n = n + 1
		end
	end
	return n
end

return Missions
