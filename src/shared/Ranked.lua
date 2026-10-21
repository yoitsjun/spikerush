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

-- What a match is worth: +RP for a win, -RP for a loss. The gap to the other team (`theirs`, its
-- average RP, against yours, `mine`) moves it up to DiffWeight either way (beat a stronger team:
-- more; lose to one: less), then your own rank's Climb (gain, loss) multipliers: the higher you
-- are, the less a win pays and the more a loss costs.
function Ranked.change(won, mine, theirs)
	local k = math.clamp((whole(theirs) - whole(mine)) / R.DiffSpan, -1, 1)
	local _, rank = Ranked.rankOf(mine)
	local climb = (rank and R.Climb[rank.Key]) or { 1, 1 }
	if won then
		return math.floor(math.clamp(R.Win * (1 + R.DiffWeight * k) * climb[1], R.Min, R.Max) + 0.5)
	end
	return -math.floor(math.clamp(R.Loss * (1 - R.DiffWeight * k) * climb[2], R.Min, R.Max) + 0.5)
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
	-- leaving early (Config.Ranked.Leave): when you left (the last few), the queue lock, and the match
	-- you left (to rejoin it: its key, where it is, what it cost)
	out.leaves = {}
	if type(data.leaves) == "table" then
		for _, t in ipairs(data.leaves) do
			if tonumber(t) and #out.leaves < #R.Leave.Bans then
				table.insert(out.leaves, whole(t))
			end
		end
	end
	out.banUntil = whole(data.banUntil)
	local left = data.left
	if type(left) == "table" and type(left.key) == "string" then
		out.left = {
			key = string.sub(left.key, 1, 64),
			code = type(left.code) == "string" and string.sub(left.code, 1, 200) or nil,
			job = type(left.job) == "string" and string.sub(left.job, 1, 64) or nil,
			d = math.min(0, math.floor(tonumber(left.d) or 0)),
			ban = whole(left.ban),
			at = whole(left.at),
			season = whole(left.season),
		}
	end
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

-- Leaving a ranked match early (`key`: the match; `code` / `job`: where it runs, to rejoin it) at
-- unix time `now`: its loss, ExtraRp more, and the queue locked by how many times you've left in
-- the last Window. Returns the RP it cost (negative) and the lock's seconds.
function Ranked.leave(rec, theirs, now, key, code, job)
	local L = R.Leave
	local d = Ranked.apply(rec, false, theirs)
	local extra = math.min(L.ExtraRp, rec.rp)
	rec.rp = rec.rp - extra
	local recent = {}
	for _, t in ipairs(rec.leaves or {}) do
		if now - t < L.Window then
			table.insert(recent, t)
		end
	end
	table.insert(recent, 1, now)
	while #recent > #L.Bans do
		table.remove(recent)
	end
	rec.leaves = recent
	local secs = L.Bans[math.min(#recent, #L.Bans)]
	local prevBan = rec.banUntil or 0
	rec.banUntil = math.max(prevBan, now + secs)
	rec.left = { key = key, code = code, job = job, d = d - extra, ban = prevBan, at = now, season = rec.season }
	return d - extra, secs
end

-- Back in the match you left (`key`), while it's on: the RP, the loss, the leave and the queue
-- lock all come back. Returns whether it did.
function Ranked.unleave(rec, key)
	local left = rec.left
	if not left or left.key ~= key or left.season ~= rec.season then
		return false
	end
	rec.rp = math.max(0, rec.rp - (left.d or 0))
	rec.losses = math.max(0, rec.losses - 1)
	if rec.leaves and rec.leaves[1] == left.at then
		table.remove(rec.leaves, 1)
	end
	rec.banUntil = left.ban or 0
	rec.left = nil
	return true
end

-- Seconds the ranked queue stays locked at unix time `now` (0: open).
function Ranked.banLeft(rec, now)
	return math.max(0, (rec and rec.banUntil or 0) - now)
end

-- The match you left, while you can still rejoin it (else nil).
function Ranked.rejoinable(rec, now)
	local left = rec and rec.left
	if left and now - (left.at or 0) <= R.Leave.RejoinSeconds then
		return left
	end
	return nil
end

-- A match's result on a record (already rolled over): returns the change in RP.
function Ranked.apply(rec, won, theirs)
	local before = rec.rp
	rec.rp = math.max(0, rec.rp + Ranked.change(won, rec.rp, theirs))
	local d = rec.rp - before -- (what really moved: never below 0)
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
