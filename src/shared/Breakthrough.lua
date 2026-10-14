-- Breakthroughs (Config.Breakthrough): fragments from duplicate characters, spent to take a
-- character up to +5 past its stat ceiling, its ability growing too. Shared: the server spends and
-- applies them, the menus show them, HitLogic reads the ability's grown settings, and the headless
-- tests check the rules.

local Config = require(script.Parent.Config)

local BT = Config.Breakthrough

local Breakthrough = {}

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

-- The fragment a character's tier makes and takes: its letter, S+ on its own.
function Breakthrough.group(tier)
	if tier == "S+" then
		return "S+"
	end
	return string.sub(tier or "D", 1, 1)
end

function Breakthrough.isGroup(g)
	for _, k in ipairs(BT.Groups) do
		if k == g then
			return true
		end
	end
	return false
end

-- A saved (possibly untrusted) level, as 0..Max.
function Breakthrough.level(v)
	v = tonumber(v) or 0
	if v ~= v then
		return 0
	end
	return clamp(math.floor(v), 0, BT.Max)
end

-- Fragments the step from `level` to `level + 1` costs (nil at Max).
function Breakthrough.cost(level)
	return BT.Cost[Breakthrough.level(level) + 1]
end

local function hasAbility(c)
	return c ~= nil and c.Ability ~= nil and Config.Abilities[c.Ability] ~= nil
end

-- The stat points step `i` (1..Max) gives roster character `c`.
function Breakthrough.step(c, i)
	local plan = (BT.Stats[c and c.Role or "WS"] or BT.Stats.WS)[i] or {}
	local mul = hasAbility(c) and 1 or BT.NoAbilityMul
	local out = {}
	for k, v in pairs(plan) do
		out[k] = math.floor(v * mul + 0.5)
	end
	return out
end

-- The stat points `level` breakthroughs add to `c`, all steps together.
function Breakthrough.stats(c, level)
	local out = {}
	for i = 1, Breakthrough.level(level) do
		for k, v in pairs(Breakthrough.step(c, i)) do
			out[k] = (out[k] or 0) + v
		end
	end
	return out
end

-- An ability's setting `key` at breakthrough `level` (the plain setting when it doesn't grow).
-- A table setting grows entry by entry.
function Breakthrough.ab(ability, key, level)
	local def = Config.Abilities[ability or ""]
	local v = def and def[key]
	local spec = BT.Ability[ability or ""] and BT.Ability[ability][key]
	level = Breakthrough.level(level)
	if v == nil or not spec or level == 0 then
		return v
	end
	local f = 1 + spec.Grow * level / BT.Max
	local function one(x)
		if type(x) ~= "number" then
			return x
		end
		if spec.Kind == "excess" then
			return 1 + (x - 1) * f
		end
		return x * f
	end
	if type(v) == "table" then
		local t = {}
		for k, x in pairs(v) do
			t[k] = one(x)
		end
		return t
	end
	return one(v)
end

local function show(spec, v)
	if type(v) == "table" then
		v = v[spec.Field or 1]
	end
	v = tonumber(v) or 0
	if spec.Show == "pct" then
		return string.format("+%d%%", math.floor(v * 100 + 0.5))
	elseif spec.Show == "excess" then
		return string.format("+%d%%", math.floor((v - 1) * 100 + 0.5))
	elseif spec.Show == "s" then
		return string.format("%.1f s", v)
	elseif spec.Show == "kmh" then
		return string.format("%d km/h", math.floor(v + 0.5))
	end
	return string.format("+%d", math.floor(v + 0.5))
end

-- What breakthrough `i` of roster character `c` reads as, for the menus: { stats = { "Attack +4",
-- ... }, ability = { { label, value }, ... } } (ability: its grown settings at that level).
function Breakthrough.describe(c, i)
	local out = { stats = {}, ability = {} }
	local step = Breakthrough.step(c, i)
	for _, stat in ipairs(Config.Stats.Order) do
		if step[stat] then
			table.insert(out.stats, string.format("%s +%d", stat, step[stat]))
		end
	end
	local specs = hasAbility(c) and BT.Ability[c.Ability] or nil
	if specs then
		local keys = {}
		for key in pairs(specs) do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			table.insert(out.ability, { specs[key].Label, show(specs[key], Breakthrough.ab(c.Ability, key, i)) })
		end
	end
	return out
end

-- What selling one fragment of `group` pays (Economy.cleanGrant): its rarity's duplicate VP, and
-- SellLucky lucky spins.
function Breakthrough.sellGrant(group)
	if not Breakthrough.isGroup(group) then
		return nil
	end
	local rarity = Config.Spins.TierRarity[group]
	return { VP = Config.Spins.SellValue[rarity] or 0, Lucky = BT.SellLucky[group] or 0 }
end

-- A saved fragment purse ({ S = 3, ... }), cleaned.
function Breakthrough.cleanFragments(t)
	local out = {}
	if type(t) == "table" then
		for _, g in ipairs(BT.Groups) do
			local n = math.floor(tonumber(t[g]) or 0)
			if n == n and n > 0 then
				out[g] = math.min(n, 100000)
			end
		end
	end
	return out
end

return Breakthrough
