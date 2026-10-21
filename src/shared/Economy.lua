-- The economy's rules outside a match: codes, what a grant gives (a code, a daily reward, a
-- gift, the admin panel's Give), daily reward streaks, 2x VP boost timers, the admin panel's
-- events, and the packs sold for Robux (VP, Gold, lucky spins, boosts), which gifting buys for
-- someone else. Pure, shared so the server and the headless tests agree.

local Config = require(script.Parent.Config)
local Roster = require(script.Parent.Roster)
local Spins = require(script.Parent.Spins)
local Breakthrough = require(script.Parent.Breakthrough)
local Halloween = require(script.Parent.Halloween)

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
-- Boosts.MaxHold), and roster characters only (each once), and real cosmetics (Items: { Kind, Key },
-- each once; the owner: "in the admin panel allow gifting cosmetics"). { VP, Gold, Lucky, BoostVP,
-- Chars, Items }.
function Economy.cleanGrant(g)
	g = type(g) == "table" and g or {}
	local cap = Config.Admin.GiveMax
	local function amount(v, max)
		return math.max(0, math.min(whole(v), max))
	end
	local out = { VP = amount(g.VP, cap.VP), Gold = amount(g.Gold, cap.Gold), Lucky = amount(g.Lucky, cap.Lucky), BoostVP = amount(g.BoostVP, Config.Boosts.MaxHold), BoostLuck = amount(g.BoostLuck, Config.Boosts.MaxHold), Chars = {}, Cards = {}, Items = {}, Fragments = {}, Skins = {}, Passes = {}, Perks = {} }
	-- game passes and perks given (a gifted pass: Config.Passes.GiftPacks)
	for _, field in ipairs({ { "Passes", Config.Passes.Order }, { "Perks", Config.Perks.Order } }) do
		if type(g[field[1]]) == "table" then
			for _, key in ipairs(field[2]) do
				for _, k in ipairs(g[field[1]]) do
					if k == key and out[field[1]][#out[field[1]]] ~= key then
						table.insert(out[field[1]], key)
					end
				end
			end
		end
	end
	-- Halloween skins (the owner, 2026-10-17: "add giving skins in the admin panel"): keys of
	-- Config.Halloween.Skins, a copy each, with their characters
	if type(g.Skins) == "table" then
		local seen = {}
		for _, key in ipairs(g.Skins) do
			if type(key) == "string" and Config.Halloween.Skins[key] and not seen[key] then
				seen[key] = true
				table.insert(out.Skins, key)
			end
		end
	end
	-- a luck boost's strength (Config.Boosts.LuckTiers; 2 when it says none)
	out.LuckMul = Economy.luckTier(g.LuckMul)
	-- breakthrough fragments by letter ({ ["S+"] = 5 }; the owner: "add breakthrough fragments to the
	-- admin panel")
	if type(g.Fragments) == "table" then
		for _, grp in ipairs(Config.Breakthrough.Groups) do
			local n = amount(g.Fragments[grp], cap.Fragments)
			if n > 0 then
				out.Fragments[grp] = n
			end
		end
	end
	if type(g.Items) == "table" then
		local seen = {}
		for _, it in ipairs(g.Items) do
			local kind, key = type(it) == "table" and it.Kind, type(it) == "table" and it.Key
			if Spins.isCosmetic(kind) and type(key) == "string" and Spins.item(kind, key) and not seen[kind .. ":" .. key] and #out.Items < 200 then
				seen[kind .. ":" .. key] = true
				table.insert(out.Items, { Kind = kind, Key = key })
			end
		end
	end
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
	return g.VP == 0 and g.Gold == 0 and g.Lucky == 0 and g.BoostVP == 0 and (g.BoostLuck or 0) == 0 and #g.Chars == 0 and #(g.Cards or {}) == 0 and #(g.Items or {}) == 0 and next(g.Fragments or {}) == nil and #(g.Skins or {}) == 0 and #(g.Passes or {}) == 0 and #(g.Perks or {}) == 0
end

-- A luck boost's strength: one of Config.Boosts.LuckTiers, else 2.
function Economy.luckTier(m)
	m = tonumber(m)
	for _, t in ipairs(Config.Boosts.LuckTiers) do
		if t == m then
			return t
		end
	end
	return 2
end

-- The profile's boost timer key for a luck tier ("Luck" for 2x, "Luck4" for 4x...).
function Economy.luckKey(m)
	m = Economy.luckTier(m)
	return m == 2 and "Luck" or ("Luck" .. m)
end

-- Your own luck at `now`: the strongest luck boost running (1 with none) and when it ends.
function Economy.luckBoost(profile, now)
	local b = type(profile) == "table" and type(profile.boosts) == "table" and profile.boosts or {}
	local tiers = Config.Boosts.LuckTiers
	for i = #tiers, 1, -1 do
		local untilT = tonumber(b[Economy.luckKey(tiers[i])])
		if untilT and now < untilT then
			return tiers[i], untilT
		end
	end
	return 1, nil
end

-- A boost timer (unix end) after adding `seconds` at `now`: from now if it had run out, on top
-- if it hadn't, never more than Boosts.MaxHold ahead.
function Economy.extendBoost(untilT, seconds, now)
	local from = math.max(whole(untilT), now)
	return math.min(from + seconds, now + Config.Boosts.MaxHold)
end

-- The Gold that `vp` V Points cost in the Shop's trade (Config.Exchange), or nil for an amount it
-- doesn't sell.
function Economy.exchangeCost(vp)
	vp = tonumber(vp)
	for _, n in ipairs(Config.Exchange.Amounts) do
		if n == vp then
			return vp * Config.Exchange.GoldPerVP
		end
	end
	return nil
end

-- A 2x VP boost bought with Gold or VP (Config.Boosts.CurrencyPacks): its seconds and price, or
-- nil for a pack or currency it doesn't have.
function Economy.boostPrice(index, currency)
	local pack = Config.Boosts.CurrencyPacks[tonumber(index) or 0]
	if not pack or (currency ~= "Gold" and currency ~= "VP") then
		return nil
	end
	return pack.BoostVP, pack[currency]
end

-- What a profile's boost timers multiply `kind` ("VP") by at `now`.
function Economy.boost(profile, kind, now)
	local b = type(profile) == "table" and type(profile.boosts) == "table" and tonumber(profile.boosts[kind]) or nil
	if b and now < b then
		return Config.Boosts.Multiplier
	end
	return 1
end

-- Earned VP (a match, the MVP bonus, a tournament's prize, a daily reward) times `mult`, the
-- server's ProfileService.vpMult: the 2x VP event, the player's own 2x VP boost and their passes
-- (the owner, 2026-10-16: "make 2x vp apply to everything, such as tournaments. only thing it
-- shouldn't apply to are robux purchases and gifts", then "the 2x should not effect codes and all
-- that. only like earnable stuff, like tournaments and matches and daily rewords"). Whole VP.
function Economy.earnedVP(vp, mult)
	return math.floor(math.max(0, tonumber(vp) or 0) * math.max(1, tonumber(mult) or 1) + 0.5)
end

-- A clean grant that was earned (a daily reward): a copy, its VP times `mult` (Economy.earnedVP),
-- the rest as it was.
function Economy.earnedGrant(g, mult)
	local out = {}
	for k, v in pairs(g) do
		out[k] = v
	end
	out.VP = Economy.earnedVP(g.VP, mult)
	return out
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
	if (g.BoostLuck or 0) > 0 then
		-- (each tier on its own clock: Luck, Luck4, Luck6...)
		profile.boosts = type(profile.boosts) == "table" and profile.boosts or {}
		local key = Economy.luckKey(g.LuckMul)
		profile.boosts[key] = Economy.extendBoost(profile.boosts[key], g.BoostLuck, now or 0)
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
	for _, it in ipairs(g.Items or {}) do
		profile.owned[it.Kind] = profile.owned[it.Kind] or {}
		profile.owned[it.Kind][it.Key] = true
	end
	if g.Fragments and next(g.Fragments) then
		profile.fragments = Breakthrough.cleanFragments(profile.fragments)
		for grp, n in pairs(g.Fragments) do
			profile.fragments[grp] = math.min((profile.fragments[grp] or 0) + n, 100000)
		end
	end
	-- a gifted pass, kept on the profile (ProfileService's passesOf reads it), and perks
	if g.Passes and #g.Passes > 0 then
		profile.giftedPasses = type(profile.giftedPasses) == "table" and profile.giftedPasses or {}
		for _, key in ipairs(g.Passes) do
			profile.giftedPasses[key] = true
		end
	end
	if g.Perks and #g.Perks > 0 then
		profile.perks = type(profile.perks) == "table" and profile.perks or {}
		for _, key in ipairs(g.Perks) do
			profile.perks[key] = true
		end
	end
	-- a skin: a copy unless every character it fits already has one, and its characters join
	if g.Skins and #g.Skins > 0 then
		profile.skins = type(profile.skins) == "table" and profile.skins or {}
		for _, key in ipairs(g.Skins) do
			if not Halloween.skinDuplicate(profile.skins, key) then
				Halloween.addCopy(profile.skins, key)
			end
		end
		for _, id in ipairs(Halloween.skinChars(profile.skins, profile.owned.Char)) do
			table.insert(added, id)
		end
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
	if (g.BoostLuck or 0) > 0 then
		table.insert(parts, string.format("%dx Luck for %s", Economy.luckTier(g.LuckMul), Economy.duration(g.BoostLuck)))
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
	for _, it in ipairs(g.Items or {}) do
		local item = Spins.item(it.Kind, it.Key)
		table.insert(parts, (item and item.Name or it.Key) .. " (" .. it.Kind .. ")")
	end
	for _, key in ipairs(g.Passes or {}) do
		table.insert(parts, "the " .. Config.Passes[key].Name .. " pass")
	end
	for _, key in ipairs(g.Perks or {}) do
		table.insert(parts, Config.Perks[key].Name)
	end
	for _, key in ipairs(g.Skins or {}) do
		local s = Config.Halloween.Skins[key]
		table.insert(parts, "the " .. (s and s.Name or key) .. " skin")
	end
	for _, grp in ipairs(Config.Breakthrough.Groups) do
		local n = g.Fragments and g.Fragments[grp] or 0
		if n > 0 then
			table.insert(parts, string.format("%s %s Fragment%s", Economy.commas(n), grp, n == 1 and "" or "s"))
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
-- Discord verification codes (Config.Discord): capitals and digits nobody misreads (no I, O, 0, 1).
local DISCORD_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

function Economy.discordCode(rng)
	local out = {}
	for i = 1, Config.Discord.CodeLength do
		local k = rng:NextInteger(1, #DISCORD_ALPHABET)
		out[i] = string.sub(DISCORD_ALPHABET, k, k)
	end
	return table.concat(out)
end

function Economy.isDiscordCode(s)
	return type(s) == "string" and #s == Config.Discord.CodeLength and string.find(s, "[^A-HJ-NP-Z2-9]") == nil
end

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

-- The admin whitelist as stored (Config.Admin.WhitelistStore): user id (a string) -> { n = the
-- username, t = when added }, made safe: whole positive ids, names of up to 20 characters, at most
-- WhitelistMax (the earliest added kept).
function Economy.cleanAdmins(data)
	local rows = {}
	if type(data) == "table" then
		for k, v in pairs(data) do
			local id = tonumber(k)
			if id and id > 0 and id == math.floor(id) and type(v) == "table" then
				local name = type(v.n) == "string" and string.match(v.n, "^[%w_]+$") and string.sub(v.n, 1, 20) or tostring(id)
				table.insert(rows, { id = id, n = name, t = math.max(0, whole(v.t)) })
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(#rows, Config.Admin.WhitelistMax) do
		out[tostring(rows[i].id)] = { n = rows[i].n, t = rows[i].t }
	end
	return out
end

-- The whitelist for the panel, by name: { { id, name } }.
function Economy.adminList(list)
	local out = {}
	for k, v in pairs(list or {}) do
		table.insert(out, { id = tonumber(k), name = v.n })
	end
	table.sort(out, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
	return out
end

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
	{ kind = "LuckBoost", list = Config.Boosts.LuckPacks },
	{ kind = "LuckBoost4", list = Config.Boosts.LuckPacks4 },
	{ kind = "LuckBoost6", list = Config.Boosts.LuckPacks6 },
	{ kind = "LuckBoost8", list = Config.Boosts.LuckPacks8 },
	{ kind = "LuckBoost16", list = Config.Boosts.LuckPacks16 },
	{ kind = "Bundle", list = Config.Bundles.Packs },
	{ kind = "PassGift", list = Config.Passes.GiftPacks },
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
	return Economy.cleanGrant({ VP = p.VP, Gold = p.Gold, Lucky = p.Lucky, BoostVP = p.BoostVP, BoostLuck = p.BoostLuck, LuckMul = p.LuckMul, Passes = p.Passes, Perks = p.Perks })
end

-- Whether a pack is a bundle sold once per player that `bought` (a profile's bundles: name ->
-- true) already has.
function Economy.boughtOnce(entry, bought)
	return entry ~= nil and entry.pack.Once == true and type(bought) == "table" and bought[entry.pack.Name] == true
end

------------------------------------------------------------------------------------------
-- game passes (Config.Passes)
------------------------------------------------------------------------------------------

-- What the passes in `owned` (key -> true) multiply `kind` ("VP", "Gold", "Luck") by.
function Economy.passMult(owned, kind)
	local m = 1
	if type(owned) == "table" then
		for _, key in ipairs(Config.Passes.Order) do
			local def = Config.Passes[key]
			if owned[key] and tonumber(def[kind]) then
				m = m * def[kind]
			end
		end
	end
	return m
end

-- The pass a game pass id is, or nil.
function Economy.passById(passId)
	for _, key in ipairs(Config.Passes.Order) do
		local id = Config.Passes[key].PassId
		if id ~= 0 and id == passId then
			return key, Config.Passes[key]
		end
	end
	return nil
end

return Economy
