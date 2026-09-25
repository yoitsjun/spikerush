-- Spins and unlockables: pure helpers shared by the server (which rolls) and the client (which
-- shows odds and names). Stat-cap and height rolls live in Characters.

local Config = require(script.Parent.Config)

local Spins = {}

local SP = Config.Spins
local COS = Config.Cosmetics
local RAR = Config.Rarity

local index = {}
for _, kind in ipairs(COS.Kinds) do
	index[kind] = {}
	for i, item in ipairs(COS[kind]) do
		index[kind][item.Key] = i
	end
end

function Spins.isBanner(banner)
	return type(banner) == "string" and SP.Banners[banner] ~= nil
end

function Spins.isCosmetic(kind)
	return type(kind) == "string" and index[kind] ~= nil
end

function Spins.cost(count)
	return SP.Costs[count]
end

function Spins.item(kind, key)
	local i = index[kind] and index[kind][key]
	return i and COS[kind][i] or nil
end

function Spins.default(kind)
	return COS[kind][1].Key
end

-- The item a character shows for `kind`, from an attribute value (unknown -> the default).
function Spins.resolve(kind, key)
	return Spins.item(kind, key) or COS[kind][1]
end

function Spins.rarityColor(rarity)
	return RAR.Colors[rarity] or RAR.Colors.Common
end

-- Items a banner can drop, grouped by rarity. The default item is owned by everyone and never
-- drops.
local function pool(kind)
	local byRarity = {}
	for i, item in ipairs(COS[kind]) do
		if i > 1 then
			byRarity[item.Rarity] = byRarity[item.Rarity] or {}
			table.insert(byRarity[item.Rarity], item.Key)
		end
	end
	return byRarity
end

local pools = {}
for _, kind in ipairs(COS.Kinds) do
	pools[kind] = pool(kind)
end

-- Chance (0..1) of each rarity on this banner: the rarity weights over the rarities it has.
function Spins.odds(kind)
	local p = pools[kind]
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

-- One item spin: a rarity by weight, then an item of that rarity.
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
	local list = p[pick]
	return list[rng:NextInteger(1, #list)]
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
