-- Spins and unlockables: pure helpers shared by the server (which rolls) and the client (which
-- shows odds, names and what a banner can give). Banners: "Char" (the roster's characters)
-- and the cosmetic kinds in Config.Cosmetics.

local Config = require(script.Parent.Config)
local Roster = require(script.Parent.Roster)

local Spins = {}

local SP = Config.Spins
local COS = Config.Cosmetics
local RAR = Config.Rarity

-- A character's rarity comes from its tier (S+ is Mythic, S- and S Legendary, ...).
function Spins.tierRarity(tier)
	return SP.TierRarity[tier] or SP.TierRarity[string.sub(tier or "D", 1, 1)] or "Common"
end

local function subTierWeight(tier)
	local suffix = string.sub(tier, 2)
	return SP.TierWeights[suffix] or 1
end

-- items[kind] = list of { Key, Name, Rarity, Weight }; starters[kind] = { key = true }
local items, index, starters = {}, {}, {}

items.Char = {}
for _, c in ipairs(Roster) do
	table.insert(items.Char, { Key = c.Id, Name = c.Name, Rarity = Spins.tierRarity(c.Tier), Weight = subTierWeight(c.Tier), Char = c })
end
starters.Char = {}
for _, id in ipairs(Roster.Starters) do
	starters.Char[id] = true
end
for _, kind in ipairs(COS.Kinds) do
	items[kind] = COS[kind]
	starters[kind] = { [COS[kind][1].Key] = true }
end
Spins.Kinds = { "Char" }
for _, kind in ipairs(COS.Kinds) do
	table.insert(Spins.Kinds, kind)
end
for kind, list in pairs(items) do
	index[kind] = {}
	for i, item in ipairs(list) do
		index[kind][item.Key] = i
	end
end

function Spins.isBanner(banner)
	return type(banner) == "string" and SP.Banners[banner] ~= nil and items[banner] ~= nil
end

function Spins.isCosmetic(kind)
	return type(kind) == "string" and COS.Attribute[kind] ~= nil
end

function Spins.cost(count)
	return SP.Costs[count]
end

function Spins.items(kind)
	return items[kind] or {}
end

function Spins.item(kind, key)
	local i = index[kind] and index[kind][key]
	return i and items[kind][i] or nil
end

-- Keys everyone owns from the start (they never drop).
function Spins.starters(kind)
	return starters[kind] or {}
end

function Spins.default(kind)
	return items[kind][1].Key
end

-- The item a character shows for `kind`, from an attribute value (unknown -> the default).
function Spins.resolve(kind, key)
	return Spins.item(kind, key) or items[kind][1]
end

function Spins.rarityColor(rarity)
	return RAR.Colors[rarity] or RAR.Colors.Common
end

function Spins.rarityRank(rarity)
	for i, r in ipairs(RAR.Order) do
		if r == rarity then
			return i
		end
	end
	return 1
end

function Spins.sellValue(rarity)
	return SP.SellValue[rarity] or SP.SellValue.Common
end

-- Items a banner can drop, grouped by rarity (starters never drop).
local pools = {}
for kind, list in pairs(items) do
	local byRarity = {}
	for _, item in ipairs(list) do
		if not starters[kind][item.Key] then
			byRarity[item.Rarity] = byRarity[item.Rarity] or { items = {}, weight = 0 }
			local p = byRarity[item.Rarity]
			table.insert(p.items, item)
			p.weight = p.weight + (item.Weight or 1)
		end
	end
	pools[kind] = byRarity
end

-- The rarity weights of a lucky spin (Config.Lucky), for odds, table and rollItem.
Spins.LuckyWeights = Config.Lucky.Weights

-- Chance (0..1) of each rarity on this banner: the rarity weights (Rarity.Weights, or a lucky
-- spin's) over the rarities it has.
function Spins.odds(kind, weights)
	weights = weights or RAR.Weights
	local p = pools[kind] or {}
	local total = 0
	for _, r in ipairs(RAR.Order) do
		if p[r] then
			total = total + (weights[r] or 0)
		end
	end
	local out = {}
	for _, r in ipairs(RAR.Order) do
		out[r] = (p[r] and total > 0) and (weights[r] or 0) / total or 0
	end
	return out
end

-- Everything a banner can give, best first: { item, chance } (what you're rolling for).
function Spins.table(kind, weights)
	local odds = Spins.odds(kind, weights)
	local out = {}
	for i = #RAR.Order, 1, -1 do
		local r = RAR.Order[i]
		local p = (pools[kind] or {})[r]
		if p and odds[r] > 0 then
			for _, item in ipairs(p.items) do
				table.insert(out, { item = item, chance = odds[r] * (item.Weight or 1) / p.weight })
			end
		end
	end
	return out
end

-- One spin: a rarity by weight, then an item of that rarity by its weight. `weights`: a lucky
-- spin's (Spins.LuckyWeights), or nil for the usual ones.
function Spins.rollItem(kind, rng, weights)
	rng = rng or Random.new()
	local p = pools[kind]
	local odds = Spins.odds(kind, weights)
	local x = rng:NextNumber()
	local pick = nil
	for _, r in ipairs(RAR.Order) do
		if p[r] and odds[r] > 0 then
			pick = r
			if x < odds[r] then
				break
			end
			x = x - odds[r]
		end
	end
	local pool = p[pick]
	local y = rng:NextNumber() * pool.weight
	for _, item in ipairs(pool.items) do
		y = y - (item.Weight or 1)
		if y < 0 then
			return item.Key
		end
	end
	return pool.items[#pool.items].Key
end

------------------------------------------------------------------------------------------
-- pity (Config.Spins.Pity, the Characters banner)
------------------------------------------------------------------------------------------

local PITY = SP.Pity

local function tierSet(list)
	local set = {}
	for _, t in ipairs(list) do
		set[t] = true
	end
	return set
end

-- the characters each pity can give (starters never drop)
local pityPools = {}
for _, kind in ipairs({ "Normal", "Lucky" }) do
	local set = tierSet(PITY[kind].Tiers)
	pityPools[kind] = {}
	for _, item in ipairs(items.Char) do
		if set[item.Char.Tier] and not starters.Char[item.Key] then
			table.insert(pityPools[kind], item.Key)
		end
	end
end
local resetSets = { Normal = tierSet(PITY.Normal.ResetTiers), Lucky = tierSet(PITY.Lucky.ResetTiers) }

-- A fresh pity state: { normal, lucky } recruits counted since the last reset, owed (the next
-- lucky pity is your pick) and pick (the S+ you chose).
function Spins.newPity()
	return { normal = 0, lucky = 0, owed = false, pick = nil }
end

-- A saved pity state made safe.
function Spins.cleanPity(data)
	local out = Spins.newPity()
	if type(data) ~= "table" then
		return out
	end
	out.normal = math.clamp(math.floor(tonumber(data.normal) or 0), 0, PITY.Normal.Every - 1)
	out.lucky = math.clamp(math.floor(tonumber(data.lucky) or 0), 0, PITY.Lucky.Every - 1)
	out.owed = data.owed == true
	if Spins.isPityPick(data.pick) then
		out.pick = data.pick
	end
	return out
end

-- The characters a pity gives ("Normal" or "Lucky").
function Spins.pityPool(kind)
	return pityPools[kind] or {}
end

-- Whether a character can be picked for the lucky pity.
function Spins.isPityPick(key)
	for _, k in ipairs(pityPools.Lucky) do
		if k == key then
			return true
		end
	end
	return false
end

-- How many recruits until each pity: normal and lucky (1 = the very next one).
function Spins.pityLeft(pity)
	pity = pity or Spins.newPity()
	return PITY.Normal.Every - (pity.normal or 0), PITY.Lucky.Every - (pity.lucky or 0)
end

-- One recruit on the Characters banner, with pity. Updates `pity` and returns the key and how it
-- came: "pity" (a random one from the pool), "pick" (the S+ you chose) or nil (luck).
function Spins.pityRoll(pity, rng, lucky)
	rng = rng or Random.new()
	local kind = lucky and "Lucky" or "Normal"
	local count = lucky and pity.lucky or pity.normal
	local key, how = nil, nil
	if count + 1 >= PITY[kind].Every then
		local pool = pityPools[kind]
		if lucky and pity.owed and Spins.isPityPick(pity.pick) then
			key, how = pity.pick, "pick"
			pity.owed = false
		elseif #pool > 0 then
			key, how = pool[rng:NextInteger(1, #pool)], "pity"
			if lucky then
				-- the next lucky pity is your pick, unless this one already was (with no pick
				-- chosen yet, it's owed until you choose)
				pity.owed = key ~= pity.pick
			end
		end
	end
	if not key then
		key = Spins.rollItem("Char", rng, lucky and Spins.LuckyWeights or nil)
	end
	local tier = Spins.item("Char", key).Char.Tier
	if resetSets[kind][tier] then
		count = 0
	else
		count = count + 1
	end
	if lucky then
		pity.lucky = count
	else
		pity.normal = count
	end
	return key, how
end

------------------------------------------------------------------------------------------
-- client helpers (Roblox types; never called by the shared simulation)
------------------------------------------------------------------------------------------

-- The item a character has equipped for `kind`, from its model's attributes.
function Spins.equipped(model, kind)
	local key = model and model:GetAttribute(COS.Attribute[kind])
	return Spins.resolve(kind, key)
end

-- A colour item's tint (nil for the classic look). Prism cycles through the hues.
function Spins.tint(item, t)
	if not item or not item.Color then
		return nil
	end
	if item.Key == "Prism" then
		return Color3.fromHSV(((t or os.clock()) * 0.6) % 1, 0.65, 1)
	end
	return item.Color
end

function Spins.tintSequence(item)
	if not item or not item.Color then
		return nil
	end
	if item.Key == "Prism" then
		local keys = {}
		for i = 0, 6 do
			table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.65, 1)))
		end
		return ColorSequence.new(keys)
	end
	return ColorSequence.new(item.Color, item.Color:Lerp(Color3.new(1, 1, 1), 0.35))
end

return Spins
