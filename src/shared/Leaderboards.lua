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

function Leaderboards.board(key)
	return BY_KEY[key or ""]
end

-- The win-rate board's one number: the share won to 0.1 (0..1000), then the wins, then the
-- losses (each under a million), so it sorts by the share, then by the wins.
local PCT, WINS = 1e12, 1e6
function Leaderboards.winRate(wins, losses)
	wins, losses = math.max(0, math.floor(wins or 0)), math.max(0, math.floor(losses or 0))
	local played = wins + losses
	if played == 0 then
		return 0
	end
	local permille = math.floor(wins / played * 1000 + 0.5)
	return permille * PCT + math.min(wins, WINS - 1) * WINS + math.min(losses, WINS - 1)
end

-- Back from the number: percent won (0..100), wins, losses.
function Leaderboards.unpackWinRate(v)
	v = math.max(0, math.floor(tonumber(v) or 0))
	local permille = math.floor(v / PCT)
	local rest = v - permille * PCT
	local wins = math.floor(rest / WINS)
	return permille / 10, wins, rest - wins * WINS
end

-- 12345 -> "12,345"
local function commas(n)
	local s = tostring(math.max(0, math.floor(tonumber(n) or 0)))
	while true do
		local k
		s, k = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			return s
		end
	end
end

-- A board's value as text: "1,234 wins", or the win rate's "62.4%  120 W  74 L".
function Leaderboards.format(key, value)
	local b = BY_KEY[key or ""]
	if b and b.WinRate then
		local pct, w, l = Leaderboards.unpackWinRate(value)
		return string.format("%.1f%%  %s W  %s L", pct, commas(w), commas(l))
	end
	local unit = b and b.Unit or ""
	return commas(value) .. (unit ~= "" and (" " .. unit) or "")
end

-- A profile's value on every board (whole numbers, never negative).
function Leaderboards.valuesOf(profile)
	local rec = (profile and profile.record) or {}
	local function n(v)
		return math.max(0, math.floor(tonumber(v) or 0))
	end
	local wins, matches = n(rec.wins), n(rec.matches)
	local losses = math.max(0, matches - wins)
	local rateBoard = BY_KEY.winRate
	return {
		winRate = (rateBoard and matches >= (rateBoard.MinMatches or 0)) and Leaderboards.winRate(wins, losses) or 0,
		wins = n(rec.wins),
		bestStreak = n(profile and profile.bestStreak),
		kills = n(rec.kills),
		aces = n(rec.aces),
		blocks = n(rec.blocks),
		robux = n(profile and profile.spent and profile.spent.robux),
		gifts = n(profile and profile.spent and profile.spent.gifts),
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
-- replace: a board that can go down (the win rate): a player here shows their fresh value.
function Leaderboards.merge(stored, live, limit, replace)
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
			row.value = (replace and r.value > 0) and r.value or math.max(row.value, r.value)
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
