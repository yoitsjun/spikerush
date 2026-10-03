-- The economy's rules outside a match: codes, what a grant gives (a code, a daily reward, a
-- gift, the admin panel's Give), daily reward streaks, 2x VP boost timers, the admin panel's
-- events, and the packs sold for Robux (VP, Gold, lucky spins, boosts), which gifting buys for
-- someone else. Pure, shared so the server and the headless tests agree.

local Config = require(script.Parent.Config)
local Roster = require(script.Parent.Roster)

local Economy = {}

local function whole(v)
	v = tonumber(v) or 0
	if v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return math.floor(v)
end

-- 12345 -> "12,345"
function Economy.commas(n)
	local s = tostring(whole(n))
	local out = s
	while true do
		local k
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			return out
		end
	end
end

------------------------------------------------------------------------------------------
-- grants
------------------------------------------------------------------------------------------

-- A grant, made safe: whole amounts from 0 to Admin.GiveMax (a boost's seconds to
-- Boosts.MaxHold), and roster characters only (each once). { VP, Gold, Lucky, BoostVP, Chars }.
function Economy.cleanGrant(g)
	g = type(g) == "table" and g or {}
	local cap = Config.Admin.GiveMax
	local function amount(v, max)
		return math.max(0, math.min(whole(v), max))
	end
	local out = { VP = amount(g.VP, cap.VP), Gold = amount(g.Gold, cap.Gold), Lucky = amount(g.Lucky, cap.Lucky), BoostVP = amount(g.BoostVP, Config.Boosts.MaxHold), Chars = {}, Cards = {} }
	-- player cards that are given, never earned (the Content Creator card)
	if type(g.Cards) == "table" then
		local seen = {}
		for _, key in ipairs(g.Cards) do
			if type(key) == "string" and not seen[key] then
				for _, c in ipairs(Config.Cards.List) do
					if c.Key == key and c.Grant then
						seen[key] = true
						table.insert(out.Cards, key)
					end
				end
			end
		end
	end
	if type(g.Chars) == "table" then
		local seen = {}
		for _, id in ipairs(g.Chars) do
			if type(id) == "string" and Roster.get(id) and not seen[id] and #out.Chars < #Roster then
				seen[id] = true
				table.insert(out.Chars, id)
			end
		end
	end
	return out
end

function Economy.isEmpty(g)
	return g.VP == 0 and g.Gold == 0 and g.Lucky == 0 and g.BoostVP == 0 and #g.Chars == 0 and #(g.Cards or {}) == 0
end

-- A boost timer (unix end) after adding `seconds` at `now`: from now if it had run out, on top
-- if it hadn't, never more than Boosts.MaxHold ahead.
function Economy.extendBoost(untilT, seconds, now)
	local from = math.max(whole(untilT), now)
	return math.min(from + seconds, now + Config.Boosts.MaxHold)
end

-- What a profile's boost timers multiply `kind` ("VP") by at `now`.
function Economy.boost(profile, kind, now)
	local b = type(profile) == "table" and type(profile.boosts) == "table" and tonumber(profile.boosts[kind]) or nil
	if b and now < b then
		return Config.Boosts.Multiplier
	end
	return 1
end

-- Adds a clean grant to a profile table (vp, gold, lucky, boosts, owned.Char) at `now` (a boost
-- starts when it's received); a character already owned is skipped. Returns the characters it
-- added.
function Economy.apply(profile, g, now)
	profile.vp = whole(profile.vp) + g.VP
	profile.gold = whole(profile.gold) + g.Gold
	profile.lucky = whole(profile.lucky) + g.Lucky
	if g.BoostVP > 0 then
		profile.boosts = type(profile.boosts) == "table" and profile.boosts or {}
		profile.boosts.VP = Economy.extendBoost(profile.boosts.VP, g.BoostVP, now or 0)
	end
	profile.owned = profile.owned or {}
	profile.owned.Char = profile.owned.Char or {}
	local added = {}
	for _, id in ipairs(g.Chars) do
		if not profile.owned.Char[id] then
			profile.owned.Char[id] = true
			table.insert(added, id)
		end
	end
	profile.cards = type(profile.cards) == "table" and profile.cards or {}
	for _, key in ipairs(g.Cards or {}) do
		profile.cards[key] = true
	end
	return added
end

-- "+500 VP, +5,000 Gold, 1 lucky spin and Dante". `chars` (optional) are the ones to name,
-- say only those a player didn't have yet.
function Economy.describe(g, chars)
	local parts = {}
	if g.VP > 0 then
		table.insert(parts, "+" .. Economy.commas(g.VP) .. " VP")
	end
	if g.Gold > 0 then
		table.insert(parts, "+" .. Economy.commas(g.Gold) .. " Gold")
	end
	if g.Lucky > 0 then
		table.insert(parts, g.Lucky == 1 and "1 lucky spin" or (Economy.commas(g.Lucky) .. " lucky spins"))
	end
	if g.BoostVP > 0 then
		table.insert(parts, string.format("%dx VP for %s", Config.Boosts.Multiplier, Economy.duration(g.BoostVP)))
	end
	for _, id in ipairs(chars or g.Chars) do
		local c = Roster.get(id)
		table.insert(parts, c and c.Name or id)
	end
	for _, key in ipairs(g.Cards or {}) do
		for _, c in ipairs(Config.Cards.List) do
			if c.Key == key then
				table.insert(parts, "the " .. c.Name .. " card")
			end
		end
	end
	if #parts == 0 then
		return "nothing new"
	end
	if #parts == 1 then
		return parts[1]
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

-- 900 -> "15 minutes", 3600 -> "1 hour", 5400 -> "1 hour 30 minutes"
function Economy.duration(seconds)
	local m = math.floor(whole(seconds) / 60 + 0.5)
	local h, rest = math.floor(m / 60), m % 60
	local function unit(n, word)
		return n .. " " .. word .. (n == 1 and "" or "s")
	end
	if h == 0 then
		return unit(rest, "minute")
	end
	if rest == 0 then
		return unit(h, "hour")
	end
	return unit(h, "hour") .. " " .. unit(rest, "minute")
end

------------------------------------------------------------------------------------------
-- codes
------------------------------------------------------------------------------------------

-- A typed code as it's looked up: lower case, letters and digits only.
function Economy.cleanCode(text)
	if type(text) ~= "string" then
		return ""
	end
	return (string.gsub(string.lower(string.sub(text, 1, 40)), "[^%w]", ""))
end

-- The code's grant (clean), or nil and why ("unknown", "expired"); and the code's key.
function Economy.code(text, now)
	local key = Economy.cleanCode(text)
	local def = key ~= "" and Config.Codes[key] or nil
	if type(def) ~= "table" then
		return nil, "unknown", key
	end
	if def.Until and now and now > def.Until then
		return nil, "expired", key
	end
	return Economy.cleanGrant(def), nil, key
end

------------------------------------------------------------------------------------------
-- daily rewards
------------------------------------------------------------------------------------------

-- The daily reward from a profile's saved state ({ last = unix seconds of the last claim,
-- streak = claims in a row }) at `now`: whether one can be claimed, the streak and the day
-- (1..#Rewards) the next claim is, its grant, when it opens, and whether the streak lapsed.
function Economy.daily(state, now)
	local D = Config.Daily
	state = type(state) == "table" and state or {}
	local last = math.max(0, whole(state.last))
	local streak = math.max(0, whole(state.streak))
	local since = now - last
	local ready = last <= 0 or since >= D.Cooldown
	local continues = last > 0 and since < D.StreakHours * 3600
	-- a claim that isn't open yet will still be in time when it opens (Cooldown < StreakHours)
	local nextStreak = (ready and not continues) and 1 or streak + 1
	local day = (nextStreak - 1) % #D.Rewards + 1
	return {
		ready = ready,
		streak = nextStreak,
		day = day,
		grant = Economy.cleanGrant(D.Rewards[day]),
		opensAt = last + D.Cooldown,
		lapsed = ready and last > 0 and not continues,
	}
end

------------------------------------------------------------------------------------------
-- the admin panel's events
------------------------------------------------------------------------------------------

function Economy.isEvent(kind)
	for _, k in ipairs(Config.Admin.Events) do
		if k == kind then
			return true
		end
	end
	return false
end

function Economy.isDuration(minutes)
	for _, m in ipairs(Config.Admin.Durations) do
		if m == minutes then
			return true
		end
	end
	return false
end

-- What the running events multiply `kind` ("VP" or "Gold") by at `now`: events maps a kind to
-- the unix time it ends.
function Economy.multiplier(events, kind, now)
	local untilT = type(events) == "table" and tonumber(events[kind]) or nil
	if untilT and now < untilT then
		return Config.Admin.Multiplier
	end
	return 1
end

-- The events still running at `now` (the ended ones dropped).
function Economy.running(events, now)
	local out = {}
	if type(events) == "table" then
		for _, kind in ipairs(Config.Admin.Events) do
			local untilT = tonumber(events[kind])
			if untilT and now < untilT then
				out[kind] = untilT
			end
		end
	end
	return out
end

------------------------------------------------------------------------------------------
-- packs for Robux
------------------------------------------------------------------------------------------

local PACK_LISTS = {
	{ kind = "VP", list = Config.Shop.Packs },
	{ kind = "Gold", list = Config.Shop.GoldPacks },
	{ kind = "Lucky", list = Config.Lucky.Packs },
	{ kind = "Boost", list = Config.Boosts.Packs },
}

-- A pack by its kind ("VP", "Gold", "Lucky") and index: { kind, index, pack, id }.
function Economy.pack(kind, index)
	for _, l in ipairs(PACK_LISTS) do
		if l.kind == kind then
			local p = l.list[whole(index)]
			return p and { kind = kind, index = whole(index), pack = p, id = p.Id } or nil
		end
	end
	return nil
end

-- The pack a Developer Product sells, or nil.
function Economy.packByProduct(productId)
	for _, l in ipairs(PACK_LISTS) do
		for i, p in ipairs(l.list) do
			if p.Id ~= 0 and p.Id == productId then
				return { kind = l.kind, index = i, pack = p, id = p.Id }
			end
		end
	end
	return nil
end

-- What a pack gives.
function Economy.packGrant(entry)
	local p = entry.pack
	return Economy.cleanGrant({ VP = p.VP, Gold = p.Gold, Lucky = p.Lucky, BoostVP = p.BoostVP })
end

return Economy
