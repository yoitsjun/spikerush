-- Leaderboards: which numbers of a profile each board ranks, and how rows are ranked and
-- merged. Shared so the server and the headless tests agree.

local Config = require(script.Parent.Config)

local Leaderboards = {}
local LB = Config.Leaderboards

Leaderboards.Boards = LB.Boards

local BY_KEY = {}
for _, b in ipairs(LB.Boards) do
	BY_KEY[b.Key] = b
end

function Leaderboards.isBoard(key)
	return BY_KEY[key] ~= nil
end

-- A profile's value on every board (whole numbers, never negative).
function Leaderboards.valuesOf(profile)
	local rec = (profile and profile.record) or {}
	local function n(v)
		return math.max(0, math.floor(tonumber(v) or 0))
	end
	return {
		wins = n(rec.wins),
		bestStreak = n(profile and profile.bestStreak),
		kills = n(rec.kills),
		aces = n(rec.aces),
		blocks = n(rec.blocks),
	}
end

-- Sort rows ({ userId, value, name }) best first (ties: the lower user id first, so the order
-- is stable) and number them; equal values share a rank (1, 2, 2, 4). Keeps the top `limit`.
function Leaderboards.rank(rows, limit)
	table.sort(rows, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)
	local out = {}
	for i, r in ipairs(rows) do
		if limit and i > limit then
			break
		end
		if i > 1 and r.value == rows[i - 1].value then
			r.rank = out[i - 1].rank
		else
			r.rank = i
		end
		out[i] = r
	end
	return out
end

-- The stored board plus what players in this server have right now (their fresh value wins if
-- it's higher than the stored one, and they appear even if they aren't stored yet). Zeros drop.
function Leaderboards.merge(stored, live, limit)
	local byId = {}
	local rows = {}
	for _, r in ipairs(stored or {}) do
		if r.value > 0 and not byId[r.userId] then
			local row = { userId = r.userId, value = r.value, name = r.name }
			byId[r.userId] = row
			table.insert(rows, row)
		end
	end
	for _, r in ipairs(live or {}) do
		local row = byId[r.userId]
		if row then
			row.value = math.max(row.value, r.value)
			row.name = r.name or row.name
		elseif r.value > 0 then
			row = { userId = r.userId, value = r.value, name = r.name }
			byId[r.userId] = row
			table.insert(rows, row)
		end
	end
	return Leaderboards.rank(rows, limit)
end

return Leaderboards
