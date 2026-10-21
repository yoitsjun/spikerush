-- Ranked (Config.Ranked): rank points to ranks and divisions, what a match is worth, seasons, and a
-- profile's ranked record:
--   profile.ranked = { season, rp, wins, losses, peak (the season's best RP), best (the best rank
--     index ever), history = { { season, rp, peak, wins, losses } ... } (newest first) }

local Config = require(script.Parent.Config)

local Ranked = {}
local R = Config.Ranked

local function whole(n)
	n = tonumber(n) or 0
	if n ~= n then
		return 0
	end
	return math.max(0, math.floor(n))
end

-- The rank for an RP total: its index in Config.Ranked.Ranks, the rank, the division (3, 2 or 1;
-- nil for a one-tier rank), and the RP where this division starts and the next one does (nil at
-- the top).
function Ranked.rankOf(rp)
	rp = whole(rp)
	if rp >= R.AlmightyAt then
		return #R.Ranks, R.Ranks[#R.Ranks], nil, R.AlmightyAt, nil
	end
	if rp >= R.MightyAt then
		return #R.Ranks - 1, R.Ranks[#R.Ranks - 1], nil, R.MightyAt, R.AlmightyAt
	end
	local step = math.floor(rp / R.PerDivision) -- 0 .. 14
	local idx = math.floor(step / 3) + 1
	local div = 3 - step % 3
	local from = step * R.PerDivision
	return idx, R.Ranks[idx], div, from, from + R.PerDivision
end

local ROMAN = { "I", "II", "III" }

-- "Gold II", "Mighty".
function Ranked.name(rp)
	local _, rank, div = Ranked.rankOf(rp)
	return div and (rank.Name .. " " .. ROMAN[div]) or rank.Name
end

-- How far through its division (0 to 1; 1 at the top).
function Ranked.progress(rp)
	local _, _, _, from, to = Ranked.rankOf(rp)
	if not to then
		return 1
	end
	return math.clamp((whole(rp) - from) / (to - from), 0, 1)
end

-- What a match is worth: +RP for a win, -RP for a loss, moved by how much stronger the other
-- team (`theirs`, its average RP) is than you (`mine`).
function Ranked.change(won, mine, theirs)
	local diff = (whole(theirs) - whole(mine)) / R.Spread
	if won then
		return math.floor(math.clamp(R.Win + diff, R.Min, R.Max) + 0.5)
	end
	return -math.floor(math.clamp(R.Loss - diff, R.Min, R.Max) + 0.5)
end

-- Days from 1970-01-01 to a calendar date (Howard Hinnant's days_from_civil).
local function daysFrom(y, m, d)
	if m <= 2 then
		y = y - 1
	end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- A date from days since 1970-01-01: year, month.
local function civil(z)
	z = z + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then
		y = y + 1
	end
	return y, m
end

local function monthIndex(y, m)
	return y * 12 + (m - 1)
end

-- The season at unix time `now` (1 until Season1Ends, then one a month).
function Ranked.season(now)
	local y, m = civil(math.floor(((tonumber(now) or 0) + R.DayOffset) / 86400))
	local first = monthIndex(R.Season1Ends[1], R.Season1Ends[2])
	return math.max(1, monthIndex(y, m) - first + 2)
end

-- When a season ends (unix time).
function Ranked.seasonEnds(season)
	local first = monthIndex(R.Season1Ends[1], R.Season1Ends[2])
	local idx = first + math.max(1, whole(season)) - 1
	local y, m = math.floor(idx / 12), idx % 12 + 1
	return daysFrom(y, m, 1) * 86400 - R.DayOffset
end

-- A clean ranked record (a profile's), rolled over to `season` if it's an older one: the last
-- season goes to the history and the RP keeps ResetFrac of itself.
function Ranked.clean(data, season)
	data = type(data) == "table" and data or {}
	local out = { season = whole(data.season), rp = whole(data.rp), wins = whole(data.wins), losses = whole(data.losses), peak = whole(data.peak), best = whole(data.best), history = {} }
	if type(data.history) == "table" then
		for _, h in ipairs(data.history) do
			if type(h) == "table" and #out.history < R.HistoryMax then
				table.insert(out.history, { season = whole(h.season), rp = whole(h.rp), peak = whole(h.peak), wins = whole(h.wins), losses = whole(h.losses) })
			end
		end
	end
	season = whole(season)
	if out.season == 0 then
		out.season = season
	elseif season > out.season then
		if out.wins + out.losses > 0 then
			table.insert(out.history, 1, { season = out.season, rp = out.rp, peak = out.peak, wins = out.wins, losses = out.losses })
			while #out.history > R.HistoryMax do
				table.remove(out.history)
			end
		end
		out.season = season
		out.rp = math.floor(out.rp * R.ResetFrac)
		out.wins, out.losses = 0, 0
		out.peak = out.rp
	end
	return out
end

-- A match's result on a record (already rolled over): returns the change in RP.
function Ranked.apply(rec, won, theirs)
	local d = Ranked.change(won, rec.rp, theirs)
	rec.rp = math.max(0, rec.rp + d)
	if won then
		rec.wins = rec.wins + 1
	else
		rec.losses = rec.losses + 1
	end
	rec.peak = math.max(rec.peak, rec.rp)
	rec.best = math.max(rec.best or 0, (Ranked.rankOf(rec.rp)))
	return d
end

return Ranked
