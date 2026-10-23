-- Clans (Config.Clans): the rules every side shares. A clan is a table kept in a DataStore under
-- its tag (ClanService) and sent to its members' clients (Clans.view):
--   { v, tag, name, desc, emblem (an image id, "" for none), public, minWins, owner (user id),
--     created, members = { [userId string] = { n = name, r = "Owner" | "Officer" | "Member",
--     j = joined, b = their record when they joined, s = their stats since (record minus b),
--     sp = points of their own spent on tag colours } }, legacy (points of members who left),
--     spent (points spent on upgrades), up = { [upgrade key] = level }, req = { [userId string] =
--     { n = name, w = wins, t = when } } (requests to join a private clan) }
-- A member's points are their stats since joining at Config.Clans.Points each; the clan's are every
-- member's plus legacy; what's left to spend is those minus spent.

local Config = require(script.Parent.Config)

local Clans = {}
local C = Config.Clans

local function whole(n)
	n = tonumber(n) or 0
	if n ~= n then
		return 0
	end
	return math.max(0, math.floor(n))
end

-- A typed tag: upper case, letters and digits only, TagMin to TagMax of them. Returns it, or nil
-- and why.
function Clans.cleanTag(text)
	if type(text) ~= "string" then
		return nil, "Pick a tag."
	end
	local t = string.upper((string.gsub(text, "%s", "")))
	if string.find(t, "[^%u%d]") then
		return nil, "A tag is letters and numbers only."
	end
	if #t < C.TagMin or #t > C.TagMax then
		return nil, string.format("A tag is %d to %d characters.", C.TagMin, C.TagMax)
	end
	return t
end

-- A clan name: trimmed, single spaces, 3 to NameMax characters. Returns it, or nil and why.
function Clans.cleanName(text)
	if type(text) ~= "string" then
		return nil, "Pick a name."
	end
	local n = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	n = string.gsub(n, "%s+", " ")
	if #n < 3 or #n > C.NameMax then
		return nil, string.format("A name is 3 to %d characters.", C.NameMax)
	end
	return n
end

function Clans.cleanDesc(text)
	if type(text) ~= "string" then
		return ""
	end
	local d = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	return string.sub(d, 1, C.DescMax)
end

function Clans.cleanMinWins(n)
	return math.min(whole(n), C.MinWinsMax)
end

-- An emblem id from what was typed (digits, or an rbxassetid / a Creator Store link), "" for none.
function Clans.cleanEmblem(text)
	if type(text) ~= "string" then
		return ""
	end
	local id = string.match(text, "(%d+)")
	if not id or #id > 20 then
		return ""
	end
	return id
end

-- The counted stats out of a career record (ProfileService's profile.record).
function Clans.snapshot(record)
	local out = {}
	for _, k in ipairs(C.StatOrder) do
		out[k] = whole(type(record) == "table" and record[k] or 0)
	end
	return out
end

-- A member's stats since joining: `record` now minus `base` (never below none).
function Clans.since(record, base)
	local now, b = Clans.snapshot(record), Clans.snapshot(base)
	local out = {}
	for _, k in ipairs(C.StatOrder) do
		out[k] = math.max(0, now[k] - b[k])
	end
	return out
end

function Clans.pointsOf(stats)
	local p = 0
	for _, k in ipairs(C.StatOrder) do
		p = p + whole(type(stats) == "table" and stats[k] or 0) * (C.Points[k] or 0)
	end
	return p
end

-- A member's own points, and what's left of them for tag colours.
function Clans.memberPoints(m)
	local p = Clans.pointsOf(m and m.s)
	return p, math.max(0, p - whole(m and m.sp))
end

-- The clan's points: every member's plus those who left; and what's left to spend on upgrades.
function Clans.points(clan)
	local total = whole(clan and clan.legacy)
	for _, m in pairs(clan and clan.members or {}) do
		total = total + (Clans.memberPoints(m))
	end
	return total, math.max(0, total - whole(clan and clan.spent))
end

function Clans.count(clan)
	local n = 0
	for _ in pairs(clan and clan.members or {}) do
		n = n + 1
	end
	return n
end

function Clans.upgrade(key)
	for _, u in ipairs(C.Upgrades) do
		if u.Key == key then
			return u
		end
	end
	return nil
end

function Clans.level(clan, key)
	local u = Clans.upgrade(key)
	return u and math.min(whole(clan and clan.up and clan.up[key]), u.Max) or 0
end

-- The points the next level of an upgrade costs (nil once it's maxed).
function Clans.cost(clan, key)
	local u = Clans.upgrade(key)
	if not u then
		return nil
	end
	local n = Clans.level(clan, key) + 1
	if n > u.Max then
		return nil
	end
	return u.Base * n * n
end

-- How many members fit.
function Clans.cap(clan)
	return C.BaseCap + Clans.level(clan, "Cap") * Clans.upgrade("Cap").Per
end

-- What a clan's upgrades multiply a member's `kind` by: "VP", "Gold" or "Luck" (1 with none).
function Clans.bonus(clan, kind)
	local u = Clans.upgrade(kind)
	if not u or not clan then
		return 1
	end
	return 1 + Clans.level(clan, kind) * u.Per
end

-- Whether someone with `wins` can join: ok, or false and why. (A private clan takes a request.)
function Clans.canJoin(clan, wins)
	if not clan then
		return false, "That clan doesn't exist."
	end
	if whole(wins) < whole(clan.minWins) then
		return false, string.format("%s needs %d wins to join.", clan.name or clan.tag, whole(clan.minWins))
	end
	if Clans.count(clan) >= Clans.cap(clan) then
		return false, "That clan is full."
	end
	return true
end

-- A new clan, `owner` (user id) its only member, `record` their career so far.
function Clans.new(tag, name, desc, public, minWins, owner, ownerName, record, now)
	local clan = {
		v = 1,
		tag = tag,
		name = name,
		desc = Clans.cleanDesc(desc),
		emblem = "",
		public = public ~= false,
		minWins = Clans.cleanMinWins(minWins),
		owner = owner,
		created = now or 0,
		members = {},
		legacy = 0,
		spent = 0,
		up = {},
		req = {},
	}
	Clans.addMember(clan, owner, ownerName, "Owner", record, now)
	return clan
end

function Clans.addMember(clan, userId, name, role, record, now)
	clan.members[tostring(userId)] = { n = name, r = role or "Member", j = now or 0, b = Clans.snapshot(record), s = Clans.snapshot(nil), sp = 0 }
	if clan.req then
		clan.req[tostring(userId)] = nil
	end
end

-- A member leaves (or is removed): their points stay with the clan.
function Clans.removeMember(clan, userId)
	local m = clan.members[tostring(userId)]
	if not m then
		return false
	end
	clan.legacy = whole(clan.legacy) + (Clans.memberPoints(m))
	clan.members[tostring(userId)] = nil
	return true
end

-- A member's latest stats (their record now): returns whether they changed.
-- The week a time falls in (weeks start on Monday, Config.Clans.WeekOffset), and when it ends.
function Clans.week(now)
	local day = math.floor(((tonumber(now) or 0) + C.WeekOffset) / 86400)
	return math.floor((day + 3) / 7) -- (day 0, 1 January 1970, was a Thursday)
end

function Clans.weekEnds(week)
	return ((whole(week) + 1) * 7 - 3) * 86400 - C.WeekOffset
end

-- The clan's points this week (clan.wk = { w = week, p = points }).
function Clans.weekPoints(clan, now)
	local wk = clan and clan.wk
	return (type(wk) == "table" and wk.w == Clans.week(now)) and whole(wk.p) or 0
end

-- Points a member just earned count towards this week too.
function Clans.addWeek(clan, gain, now)
	gain = whole(gain)
	if gain <= 0 then
		return
	end
	local w = Clans.week(now)
	if type(clan.wk) ~= "table" or clan.wk.w ~= w then
		clan.wk = { w = w, p = 0 }
	end
	clan.wk.p = whole(clan.wk.p) + gain
end

function Clans.updateMember(clan, userId, record, now)
	local m = clan and clan.members[tostring(userId)]
	if not m or m.pending then
		return false -- (let in while away: counted from their next join, ClanService)
	end
	local s = Clans.since(record, m.b)
	if now then
		Clans.addWeek(clan, Clans.pointsOf(s) - Clans.pointsOf(m.s), now) -- (what they earned since the last count)
	end
	local changed = false
	for _, k in ipairs(C.StatOrder) do
		if (m.s and m.s[k] or 0) ~= s[k] then
			changed = true
		end
	end
	m.s = s
	return changed
end

function Clans.roleOf(clan, userId)
	local m = clan and clan.members[tostring(userId)]
	return m and m.r or nil
end

-- Owners and officers manage (upgrades, requests, removing members); the owner alone the rest.
function Clans.canManage(clan, userId)
	local r = Clans.roleOf(clan, userId)
	return r == "Owner" or r == "Officer"
end

function Clans.tagColor(key)
	for _, c in ipairs(C.TagColors) do
		if c.Key == key then
			return c
		end
	end
	return C.TagColors[1]
end

local function hex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- "[TAG]" in rich text in a tag colour (a gradient goes letter by letter).
function Clans.tagText(tag, colorKey)
	local cols = Clans.tagColor(colorKey).Colors
	local text = "[" .. tostring(tag) .. "]"
	if #cols == 1 then
		return string.format('<font color="#%s">%s</font>', hex(cols[1]), text)
	end
	local parts = {}
	local n = #text
	for i = 1, n do
		local f = n > 1 and (i - 1) / (n - 1) or 0
		local seg = f * (#cols - 1)
		local a = math.min(math.floor(seg) + 1, #cols)
		local b = math.min(a + 1, #cols)
		local t = seg - (a - 1)
		local c1, c2 = cols[a], cols[b]
		local c = { R = c1.R + (c2.R - c1.R) * t, G = c1.G + (c2.G - c1.G) * t, B = c1.B + (c2.B - c1.B) * t }
		table.insert(parts, string.format('<font color="#%s">%s</font>', hex(c), string.sub(text, i, i)))
	end
	return table.concat(parts)
end

-- What a member's client sees of their clan: everything but the members' join records.
function Clans.view(clan)
	if not clan then
		return nil
	end
	local total, left = Clans.points(clan)
	local members = {}
	for id, m in pairs(clan.members) do
		local p, own = Clans.memberPoints(m)
		table.insert(members, { id = tonumber(id), name = m.n, role = m.r, joined = m.j, stats = m.s, points = p, own = own })
	end
	table.sort(members, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return tostring(a.name) < tostring(b.name)
	end)
	local req = {}
	for id, r in pairs(clan.req or {}) do
		table.insert(req, { id = tonumber(id), name = r.n, wins = r.w, t = r.t })
	end
	table.sort(req, function(a, b)
		return (a.t or 0) < (b.t or 0)
	end)
	local up = {}
	for _, u in ipairs(C.Upgrades) do
		up[u.Key] = Clans.level(clan, u.Key)
	end
	return { tag = clan.tag, name = clan.name, desc = clan.desc, emblem = clan.emblem, shirt = clan.shirt, pants = clan.pants, public = clan.public, minWins = clan.minWins, owner = clan.owner, members = members, requests = req, up = up, points = total, left = left, cap = Clans.cap(clan), count = Clans.count(clan), week = Clans.weekPoints(clan, os.time()) }
end

-- What anyone browsing sees (the owner, 2026-10-22: "allow people to view clans stats and such and
-- members"): the card, every member's role, stats and points, best first, and the clan's totals.
function Clans.card(clan)
	if not clan then
		return nil
	end
	local total = Clans.points(clan)
	local members, totals = {}, {}
	for _, k in ipairs(C.StatOrder) do
		totals[k] = 0
	end
	for id, m in pairs(clan.members or {}) do
		if not m.pending then
			local p = Clans.memberPoints(m)
			table.insert(members, { id = tonumber(id), name = m.n, role = m.r, stats = m.s, points = p })
			for _, k in ipairs(C.StatOrder) do
				totals[k] = totals[k] + whole(m.s and m.s[k] or 0)
			end
		end
	end
	table.sort(members, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return tostring(a.name) < tostring(b.name)
	end)
	-- its upgrades' levels too (the owner, 2026-10-22: "allow the view tab to also see the clan upgrades")
	local up = {}
	for _, u in ipairs(C.Upgrades) do
		up[u.Key] = Clans.level(clan, u.Key)
	end
	return { tag = clan.tag, name = clan.name, desc = clan.desc, emblem = clan.emblem, public = clan.public, minWins = clan.minWins, points = total, week = Clans.weekPoints(clan, os.time()), count = Clans.count(clan), cap = Clans.cap(clan), members = members, totals = totals, up = up }
end

return Clans
