-- The Halloween event (Config.Halloween): the Halloween Match's card deck, the roulette's offers,
-- what a hand of cards does to the players it hits, Candy, the limited banner and the per-character
-- skins. Pure and shared: the server deals and checks, both sides read a player's cards from the
-- `Hex` attribute (the keys of every card that hits them, joined with commas) so the prediction
-- matches; covered by the sims.

local Config = require(script.Parent.Config)
local Spins = require(script.Parent.Spins)
local Roster = require(script.Parent.Roster)

local Halloween = {}
local HW = Config.Halloween
local RAR = Config.Rarity
local STATS = Config.Stats.Order

local CARDS, CARD = {}, {}
for _, c in ipairs(HW.Cards) do
	local card = {}
	for k, v in pairs(c) do
		card[k] = v
	end
	card.Target = card.Target or "Self"
	if card.Kind == "Ability" then
		local def = Config.Abilities[card.Ability]
		card.Name = card.Name or (def and def.Name) or card.Ability
	end
	table.insert(CARDS, card)
	CARD[card.Key] = card
end
local DIFF = {}
for i, d in ipairs(HW.Difficulties) do
	DIFF[d.Key] = d
	d.index = i
end

function Halloween.cards()
	return CARDS
end

function Halloween.card(key)
	return type(key) == "string" and CARD[key] or nil
end

function Halloween.difficulty(key)
	return type(key) == "string" and DIFF[key] or nil
end

-- Whether the event is on at `now` (unix).
function Halloween.active(now)
	return (tonumber(now) or 0) < HW.Ends
end

function Halloween.secondsLeft(now)
	return math.max(0, HW.Ends - math.floor(tonumber(now) or 0))
end

-- The event day `now` falls on (days turn at midnight in Chicago: Config.Halloween.DayOffset).
function Halloween.day(now)
	return math.floor(((tonumber(now) or 0) + HW.DayOffset) / 86400)
end

------------------------------------------------------------------------------------------
-- cards
------------------------------------------------------------------------------------------

local function signed(n)
	return (n >= 0 and "+" or "") .. tostring(n)
end

local function pct(mul)
	local p = math.floor((mul - 1) * 100 + 0.5)
	return (p >= 0 and "+" or "") .. p .. "%"
end

-- What a card does, in a line (the card face and the hand list).
function Halloween.blurb(card)
	if type(card) == "string" then
		card = CARD[card]
	end
	if not card then
		return ""
	end
	local parts = {}
	if card.Kind == "Ability" then
		table.insert(parts, card.Name .. " for this run")
	end
	local add = card.Add or {}
	local all = true
	for _, k in ipairs(STATS) do
		if add[k] == nil or add[k] ~= add[STATS[1]] then
			all = false
		end
	end
	if all then
		table.insert(parts, signed(add[STATS[1]]) .. " to every stat")
	else
		for _, k in ipairs(STATS) do
			if add[k] then
				table.insert(parts, signed(add[k]) .. " " .. k)
			end
		end
	end
	if card.Height then
		table.insert(parts, signed(card.Height) .. " cm tall")
	end
	if card.Mul then
		table.insert(parts, pct(card.Mul) .. " every stat")
	end
	if card.PerPoint then
		local per = {}
		for _, k in ipairs(STATS) do
			if card.PerPoint[k] then
				table.insert(per, signed(card.PerPoint[k]) .. " " .. k)
			end
		end
		table.insert(parts, table.concat(per, ", ") .. " for every point the other team scores")
	end
	if card.SpikeMul then
		table.insert(parts, "spikes " .. pct(card.SpikeMul) .. " faster")
	end
	if card.ServeMul then
		table.insert(parts, "jump serves " .. pct(card.ServeMul) .. " faster")
	end
	if card.SpikeReach then
		table.insert(parts, "spike reach " .. pct(card.SpikeReach))
	end
	if card.Block then
		table.insert(parts, "a bigger block")
	end
	if card.Stuff then
		table.insert(parts, "more stuff blocks")
	end
	if card.DrainTake then
		table.insert(parts, "receives cost the guard " .. pct(card.DrainTake))
	end
	if card.DrainDeal then
		table.insert(parts, "your attacks cost their guard " .. pct(card.DrainDeal))
	end
	if card.Pool then
		table.insert(parts, "stamina pool " .. pct(card.Pool))
	end
	local who = card.Target == "Team" and "Your team: " or (card.Target == "Foes" and "The other team: " or "")
	local text = table.concat(parts, ", ")
	return who .. string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2) .. "."
end

function Halloween.rarityWeight(card)
	return HW.Weights[card.Rarity] or HW.Weights.Common
end

local function has(list, key)
	for _, k in ipairs(list or {}) do
		if k == key then
			return true
		end
	end
	return false
end

-- Whether a card can come up for a player (ai false) or the AI team (ai true). The AI never
-- takes an ability card.
function Halloween.drawable(card, ai)
	if ai then
		return card.Kind ~= "Ability" and not card.NoAi
	end
	return not card.AiOnly
end

-- How many ability cards a hand holds.
function Halloween.abilityCount(hand)
	local n = 0
	for _, k in ipairs(hand or {}) do
		local c = CARD[k]
		if c and c.Kind == "Ability" then
			n = n + 1
		end
	end
	return n
end

-- `n` different cards for one pick, by rarity weight, none already in `held`, no ability card for
-- an ability in `own` (the character's own: it would only repeat it), and none at all once `held`
-- has MaxAbilityCards of them (two beside your own). rng: a Random.
function Halloween.offers(rng, held, n, ai, own)
	local pool, total = {}, 0
	local full = Halloween.abilityCount(held) >= HW.MaxAbilityCards
	for _, card in ipairs(CARDS) do
		if Halloween.drawable(card, ai) and not has(held, card.Key) and not (card.Kind == "Ability" and (full or has(own, card.Ability))) then
			table.insert(pool, card)
			total = total + Halloween.rarityWeight(card)
		end
	end
	local out = {}
	for _ = 1, math.min(n or HW.Offers, #pool) do
		local y = rng:NextNumber() * total
		local pick = #pool
		for i, card in ipairs(pool) do
			y = y - Halloween.rarityWeight(card)
			if y < 0 then
				pick = i
				break
			end
		end
		local card = table.remove(pool, pick)
		total = total - Halloween.rarityWeight(card)
		table.insert(out, card.Key)
	end
	return out
end

-- The AI team's pick from its offers: the rarest (the first on a tie).
function Halloween.aiPick(offers)
	local best, rank = nil, -1
	for _, key in ipairs(offers or {}) do
		local card = CARD[key]
		local r = card and Spins.rarityRank(card.Rarity) or -1
		if r > rank then
			best, rank = key, r
		end
	end
	return best
end

-- A hand with `key` added (no card twice). Ability cards stack: each one is played beside the
-- character's own ability (the owner, 2026-10-15: "it seems the cards take away the abilities. i
-- want them to stack"), up to MaxAbilityCards ("you can stack up to 2 abilities alongside your main
-- one"): one past that isn't added. Returns the new hand (a copy).
function Halloween.addCard(hand, key)
	local out = {}
	for _, k in ipairs(hand or {}) do
		if CARD[k] then
			table.insert(out, k)
		end
	end
	local card = CARD[key]
	if card and not has(out, key) and not (card.Kind == "Ability" and Halloween.abilityCount(out) >= HW.MaxAbilityCards) then
		table.insert(out, key)
	end
	return out
end

-- Every ability a hand's ability cards give, in hand order (Characters.abilityList puts them after
-- the character's own and drops a repeat).
function Halloween.abilitiesOf(hand)
	local out = {}
	for _, k in ipairs(hand or {}) do
		local c = CARD[k]
		if c and c.Kind == "Ability" then
			table.insert(out, c.Ability)
		end
	end
	return out
end

-- A hand made safe: known cards, each once, at most MaxAbilityCards ability cards (addCard), at
-- most Stages x Picks.
function Halloween.cleanHand(list)
	local out = {}
	if type(list) == "table" then
		for _, k in ipairs(list) do
			if CARD[k] then
				out = Halloween.addCard(out, k)
			end
		end
	end
	while #out > HW.Stages * HW.Picks do
		table.remove(out, 1)
	end
	return out
end

function Halloween.encode(list)
	return table.concat(list or {}, ",")
end

function Halloween.parse(s)
	local out = {}
	if type(s) == "string" then
		for k in string.gmatch(s, "[^,]+") do
			if CARD[k] then
				table.insert(out, k)
			end
		end
	end
	return out
end

-- The cards that hit one character, as a Hex string. holders: every hand in the match, { team,
-- userId (nil for the AI team's), cards }. A Self card hits its holder (the AI's: every character
-- on its team without a player), a Team card everyone on the holder's team, a Curse everyone on
-- the other team. userId: the player the character is (or stands in for), nil for a bot.
function Halloween.hexFor(holders, team, userId)
	local out = {}
	for _, h in ipairs(holders or {}) do
		for _, key in ipairs(h.cards or {}) do
			local card = CARD[key]
			if card then
				local hit = false
				if card.Target == "Team" then
					hit = h.team == team
				elseif card.Target == "Foes" then
					hit = h.team ~= team
				elseif h.userId then
					hit = userId ~= nil and h.userId == userId
				else
					hit = h.team == team and userId == nil
				end
				if hit then
					table.insert(out, key)
				end
			end
		end
	end
	return Halloween.encode(out)
end

-- Every hand in a run (Halloween.hexFor's holders): the players' (hands: userId -> cards) on
-- `side` (the players' side, Home), the AI's on the other.
function Halloween.holders(hands, ai, side)
	side = side or "Home"
	local out = {}
	local ids = {}
	for u in pairs(hands or {}) do
		table.insert(ids, u)
	end
	table.sort(ids) -- (the same order everywhere: a Hex string doesn't depend on table order)
	for _, u in ipairs(ids) do
		table.insert(out, { team = side, userId = u, cards = hands[u] })
	end
	if ai and #ai > 0 then
		table.insert(out, { team = side == "Home" and "Away" or "Home", cards = ai })
	end
	return out
end

-- What the cards in a Hex string add up to (cached by the string), or nil for none:
-- { add, height, mul, perPoint, spikeMul, serveMul, spikeReach, block, stuff, drainTake,
-- drainDeal, pool }. HitLogic reads it as ctx.hex.
local effectsCache = {}
function Halloween.effects(s)
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local hit = effectsCache[s]
	if hit ~= nil then
		return hit or nil
	end
	local e = { add = {}, height = 0, mul = 1, perPoint = nil, spikeMul = 1, serveMul = 1, spikeReach = 1, block = nil, stuff = 0, drainTake = 1, drainDeal = 1, pool = 1 }
	local any = false
	for _, key in ipairs(Halloween.parse(s)) do
		local card = CARD[key]
		any = true
		for k, v in pairs(card.Add or {}) do
			e.add[k] = (e.add[k] or 0) + v
		end
		e.height = e.height + (card.Height or 0)
		e.mul = e.mul * (card.Mul or 1)
		if card.PerPoint then
			e.perPoint = e.perPoint or {}
			for k, v in pairs(card.PerPoint) do
				e.perPoint[k] = (e.perPoint[k] or 0) + v
			end
		end
		e.spikeMul = e.spikeMul * (card.SpikeMul or 1)
		e.serveMul = e.serveMul * (card.ServeMul or 1)
		e.spikeReach = e.spikeReach * (card.SpikeReach or 1)
		if card.Block then
			e.block = e.block or { ReachUp = 0, NetExtra = 0, OwnDepth = 0, OverDepth = 0 }
			for k, v in pairs(card.Block) do
				e.block[k] = (e.block[k] or 0) + v
			end
		end
		e.stuff = e.stuff + (card.Stuff or 0)
		e.drainTake = e.drainTake * (card.DrainTake or 1)
		e.drainDeal = e.drainDeal * (card.DrainDeal or 1)
		e.pool = e.pool * (card.Pool or 1)
	end
	effectsCache[s] = any and e or false
	return any and e or nil
end

-- Stat points per point the other team has scored this set (the PerPoint cards).
function Halloween.perPoint(hex, enemyPoints)
	if not hex or not hex.perPoint then
		return nil
	end
	local n = math.max(0, math.floor(tonumber(enemyPoints) or 0))
	local out = {}
	for k, v in pairs(hex.perPoint) do
		out[k] = v * n
	end
	return out
end

-- A block box's extra reach with the cards' added: `iron` is HitLogic.wallReach's (true: Iron
-- Wall's whole wall stays as it is; a table, or nil).
function Halloween.blockReach(iron, hex)
	local extra = hex and hex.block
	if not extra or iron == true then
		return iron
	end
	local out = {}
	for _, k in ipairs({ "ReachUp", "NetExtra", "OwnDepth", "OverDepth" }) do
		out[k] = (type(iron) == "table" and iron[k] or 0) + (extra[k] or 0)
	end
	return out
end

------------------------------------------------------------------------------------------
-- runs and Candy
------------------------------------------------------------------------------------------

-- The Candy a run pays when it ends after `stage` (won: that stage was won); first: the first
-- clear of this difficulty today.
function Halloween.payout(diff, stage, won, first)
	if type(diff) == "string" then
		diff = DIFF[diff]
	end
	if not diff then
		return 0
	end
	if won and stage >= HW.Stages then
		return first and diff.Candy or diff.Repeat
	elseif stage >= HW.Stages then
		return diff.StageOne
	end
	return 0
end

-- A player's saved event data made safe: { candy, scout, day, cleared = { [difficulty] = true }
-- (today's first clears: a new day forgets them), bought = { [shop key] = n } }.
function Halloween.clean(data)
	local out = { candy = 0, scout = 0, day = 0, cleared = {}, bought = {} }
	if type(data) ~= "table" then
		return out
	end
	out.candy = math.clamp(math.floor(tonumber(data.candy) or 0), 0, 10000000)
	out.scout = math.clamp(math.floor(tonumber(data.scout) or 0), 0, 100000)
	out.day = math.max(0, math.floor(tonumber(data.day) or 0))
	if type(data.cleared) == "table" then
		for k, v in pairs(data.cleared) do
			if v == true and DIFF[k] then
				out.cleared[k] = true
			end
		end
	end
	if type(data.bought) == "table" then
		for _, row in ipairs(HW.Shop) do
			local n = math.floor(tonumber(data.bought[row.Key]) or 0)
			if n > 0 then
				out.bought[row.Key] = math.min(n, 100000)
			end
		end
	end
	return out
end

-- Whether a clear of `diff` on day `day` is the first today (and, with mark, records it).
function Halloween.firstClear(ev, diff, day, mark)
	if ev.day ~= day then
		ev.day = day
		ev.cleared = {}
	end
	local first = not ev.cleared[diff]
	if mark then
		ev.cleared[diff] = true
	end
	return first
end

------------------------------------------------------------------------------------------
-- the banner
------------------------------------------------------------------------------------------

local B = HW.Banner
local BANNER = {}
for _, row in ipairs(B.Items) do
	local item = nil
	if row.Kind == "Skin" then
		local s = HW.Skins[row.Key]
		item = s and { Key = row.Key, Name = s.Name, Rarity = s.Rarity } or nil
	elseif row.Kind == "Room" then
		local r = Config.Rooms.List[row.Key]
		item = r and { Key = row.Key, Name = r.Name, Rarity = r.Rarity or "Legendary" } or nil
	else
		item = Spins.item(row.Kind, row.Key)
	end
	if item then
		table.insert(BANNER, { kind = row.Kind, key = row.Key, name = item.Name, rarity = item.Rarity, scout = row.Scout })
	end
end

function Halloween.bannerItems()
	return BANNER
end

function Halloween.bannerItem(kind, key)
	for _, it in ipairs(BANNER) do
		if it.kind == kind and it.key == key then
			return it
		end
	end
	return nil
end

-- What `count` recruits cost in `currency` ("VP" or "Candy"), or nil.
function Halloween.cost(currency, count)
	local list = B.Costs[currency]
	return list and list[tonumber(count) or 0] or nil
end

-- Each item with its chance: its rarity's weight (over the rarities on the banner) shared by the
-- items of that rarity.
function Halloween.bannerTable()
	local total, per = 0, {}
	for _, it in ipairs(BANNER) do
		if not per[it.rarity] then
			per[it.rarity] = 0
			total = total + (B.Weights[it.rarity] or 0)
		end
		per[it.rarity] = per[it.rarity] + 1
	end
	local out = {}
	for _, it in ipairs(BANNER) do
		local w = B.Weights[it.rarity] or 0
		table.insert(out, { item = it, chance = total > 0 and w / total / per[it.rarity] or 0 })
	end
	table.sort(out, function(a, b)
		local ra, rb = Spins.rarityRank(a.item.rarity), Spins.rarityRank(b.item.rarity)
		if ra ~= rb then
			return ra > rb
		end
		return a.item.key < b.item.key
	end)
	return out
end

-- One recruit: an item of the banner, { kind, key, name, rarity, scout }.
function Halloween.roll(rng)
	local list = Halloween.bannerTable()
	local x = rng:NextNumber()
	for _, row in ipairs(list) do
		x = x - row.chance
		if x < 0 then
			return row.item
		end
	end
	return list[#list].item
end

-- What a duplicate cosmetic pays in Candy.
function Halloween.dupCandy(rarity)
	return B.DupCandy[rarity] or 0
end

------------------------------------------------------------------------------------------
-- skins (the Reaper): copies applied to characters for good, each switched on or off
------------------------------------------------------------------------------------------

function Halloween.isSkin(key)
	return type(key) == "string" and HW.Skins[key] ~= nil
end

-- The Rest in Peace gravestone (Config.Grave). A picture from what a player typed: a Roblox asset's
-- id, or a link with one in it (rbxassetid://..., create.roblox.com/store/asset/...,
-- roblox.com/library/...); nil when there's none.
function Halloween.graveImage(s)
	if type(s) == "number" then
		s = tostring(math.floor(s))
	end
	if type(s) ~= "string" then
		return nil
	end
	local id = tonumber(string.match(s, "(%d%d%d%d%d+)") or "")
	if id and id > 0 and id < 1e15 then
		return id
	end
	return nil
end

-- An epitaph made safe before the filter: one line, trimmed, at most Config.Grave.TextMax characters.
function Halloween.graveText(s)
	if type(s) ~= "string" then
		return ""
	end
	s = string.gsub(s, "%c", " ")
	s = string.match((string.gsub(s, "%s+", " ")), "^%s*(.-)%s*$") or ""
	local ok, cut = pcall(utf8.offset, s, Config.Grave.TextMax + 1)
	if ok and cut then
		s = string.sub(s, 1, cut - 1)
	elseif not ok then
		s = string.sub(s, 1, Config.Grave.TextMax)
	end
	return s
end

-- A saved gravestone made safe: { text, image } (image 0: none).
function Halloween.cleanGrave(data)
	local out = { text = "", image = 0 }
	if type(data) == "table" then
		out.text = Halloween.graveText(data.text)
		out.image = Halloween.graveImage(data.image) or 0
	end
	return out
end

-- Whether a skin fits a character: its Chars, or anyone when it has none (the Reaper is Taeho's
-- alone since 2026-10-15).
function Halloween.skinFits(key, charId)
	local s = type(key) == "string" and HW.Skins[key]
	if not s or type(charId) ~= "string" then
		return false
	end
	if not s.Chars then
		return true
	end
	for _, id in ipairs(s.Chars) do
		if id == charId then
			return true
		end
	end
	return false
end

-- The skins that fit a character (keys in SkinOrder; a skin with no Chars fits anyone).
function Halloween.skinsFor(charId)
	local out = {}
	for _, key in ipairs(HW.SkinOrder) do
		if Halloween.skinFits(key, charId) then
			table.insert(out, key)
		end
	end
	return out
end

-- The characters a skin fits, by name ("Taeho"; "anyone" without Chars).
function Halloween.skinCharNames(key)
	local s = HW.Skins[key]
	if not s or not s.Chars then
		return "anyone"
	end
	local names = {}
	for _, id in ipairs(s.Chars) do
		local c = Roster.get(id)
		table.insert(names, c and c.Name or id)
	end
	return table.concat(names, " and ")
end

-- Saved skins made safe: { [skin] = { copies, on = { [charId] = true | false } } } (on: applied to
-- that character, and whether it's showing). isChar: whether an id is a character. A copy applied to
-- a character the skin no longer fits comes back free.
function Halloween.cleanSkins(data, isChar)
	local out = {}
	if type(data) ~= "table" then
		return out
	end
	for _, key in ipairs(HW.SkinOrder) do
		local s = data[key]
		if type(s) == "table" then
			local row = { copies = math.clamp(math.floor(tonumber(s.copies) or 0), 0, HW.MaxCopies), on = {} }
			if type(s.on) == "table" then
				for id, v in pairs(s.on) do
					if type(id) == "string" and type(v) == "boolean" and (not isChar or isChar(id)) and Halloween.skinFits(key, id) then
						row.on[id] = v
					end
				end
			end
			out[key] = row
		end
	end
	return out
end

local function appliedCount(row)
	local n = 0
	for _ in pairs(row.on) do
		n = n + 1
	end
	return n
end

-- Copies of a skin not applied to a character yet.
function Halloween.freeCopies(skins, key)
	local row = skins and skins[key]
	if not row then
		return 0
	end
	return math.max(0, row.copies - appliedCount(row))
end

-- One more copy of a skin (a pull).
function Halloween.addCopy(skins, key)
	skins[key] = skins[key] or { copies = 0, on = {} }
	skins[key].copies = math.min(HW.MaxCopies, skins[key].copies + 1)
end

-- Apply a free copy to a character, for good (it shows at once). Returns ok, why.
function Halloween.applySkin(skins, key, charId)
	if not Halloween.isSkin(key) then
		return false, "unknown"
	end
	if not Halloween.skinFits(key, charId) then
		return false, "wrongChar"
	end
	local row = skins[key]
	if row and row.on[charId] ~= nil then
		return false, "applied"
	end
	if Halloween.freeCopies(skins, key) < 1 then
		return false, "none"
	end
	row.on[charId] = true
	return true
end

-- Switch an applied skin off or on for its character. Returns ok, why.
function Halloween.toggleSkin(skins, key, charId, on)
	local row = skins and skins[key]
	if not row or row.on[charId] == nil then
		return false, "notApplied"
	end
	row.on[charId] = on == true
	return true
end

-- Whether a pull of this skin is a duplicate: every character it fits already has a copy
-- applied, or a free copy is waiting for one (the Reaper fits one character: a second copy is Candy).
function Halloween.skinDuplicate(skins, key)
	local s = HW.Skins[key]
	if not s or not s.Chars then
		return false
	end
	local row = skins and skins[key]
	if not row then
		return false
	end
	local room = 0
	for _, id in ipairs(s.Chars) do
		if row.on[id] == nil then
			room = room + 1
		end
	end
	return Halloween.freeCopies(skins, key) >= room
end

-- The skin a character shows (applied and on), or nil.
function Halloween.skinOf(skins, charId)
	for _, key in ipairs(HW.SkinOrder) do
		local row = skins and skins[key]
		if row and row.on[charId] == true and Halloween.skinFits(key, charId) then
			return key
		end
	end
	return nil
end

return Halloween
