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

-- Chance (0..1) of each rarity on this banner: the rarity weights over the rarities it has.
function Spins.odds(kind)
	local p = pools[kind] or {}
	local total = 0
	for _, r in ipairs(RAR.Order) do
		if p[r] then
			total = total + RAR.Weights[r]
		end
	end
	local out = {}
	for _, r in ipairs(RAR.Order) do
		out[r] = (p[r] and total > 0) and RAR.Weights[r] / total or 0
	end
	return out
end

-- Everything a banner can give, best first: { item, chance } (what you're rolling for).
function Spins.table(kind)
	local odds = Spins.odds(kind)
	local out = {}
	for i = #RAR.Order, 1, -1 do
		local r = RAR.Order[i]
		local p = (pools[kind] or {})[r]
		if p then
			for _, item in ipairs(p.items) do
				table.insert(out, { item = item, chance = odds[r] * (item.Weight or 1) / p.weight })
			end
		end
	end
	return out
end

-- One spin: a rarity by weight, then an item of that rarity by its weight.
function Spins.rollItem(kind, rng)
	rng = rng or Random.new()
	local p = pools[kind]
	local odds = Spins.odds(kind)
	local x = rng:NextNumber()
	local pick = nil
	for _, r in ipairs(RAR.Order) do
		if p[r] then
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
