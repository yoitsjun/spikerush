-- Tournament cups (Config.Tournament): which cups run now, their modifiers, and what they pay.
-- Pure and shared: every server and client works out the same cups from the clock, so nothing has
-- to be sent; the server checks an entry against them. A match's modifiers travel as one string
-- (the ReplicatedStorage attribute CupMods, keys joined with commas) that both sides read.

local Config = require(script.Parent.Config)

local Cups = {}
local T = Config.Tournament

local MOD = {}
for _, m in ipairs(T.Modifiers) do
	MOD[m.Key] = m
end
local CUP = {}
for i, c in ipairs(T.Cups) do
	CUP[c.Key] = c
	c.index = i
end

function Cups.modifier(key)
	return MOD[key]
end

function Cups.cup(key)
	return CUP[key]
end

-- A small, exact number generator (MINSTD): the same in Luau and plain Lua.
local function nextRand(x)
	return (x * 48271) % 2147483647
end

function Cups.slot(now)
	return math.floor(now / T.Rotate)
end

-- The cups running at `now`: { cup (its Config row), key, mode, mods (keys), endsAt }.
function Cups.current(now)
	local slot = Cups.slot(now)
	local out = {}
	local used = {} -- a modifier another cup already has is only taken when nothing else is left
	for i, c in ipairs(T.Cups) do
		local x = (slot * 7919 + i * 104729) % 2147483646 + 1
		x = nextRand(nextRand(x))
		local mode = T.Modes[x % #T.Modes + 1]
		local pool, spare = {}, {}
		for _, m in ipairs(T.Modifiers) do
			if m.Strength >= c.Min and m.Strength <= c.Max then
				table.insert(used[m.Key] and spare or pool, m.Key)
			end
		end
		if #pool < c.Mods then
			for _, k in ipairs(spare) do
				table.insert(pool, k)
			end
		end
		local mods = {}
		for _ = 1, math.min(c.Mods, #pool) do
			x = nextRand(x)
			local k = table.remove(pool, x % #pool + 1)
			used[k] = true
			table.insert(mods, k)
		end
		table.insert(out, { cup = c, key = c.Key, mode = mode, mods = mods, endsAt = (slot + 1) * T.Rotate })
	end
	return out
end

-- The running cup with that key (or, for an entry sent just as the cups changed, the one before).
function Cups.find(key, now)
	for _, t in ipairs({ now, now - 60 }) do
		for _, run in ipairs(Cups.current(t)) do
			if run.key == key then
				return run
			end
		end
	end
	return nil
end

function Cups.encode(mods)
	return table.concat(mods, ",")
end

-- The modifier keys in a CupMods string (unknown ones left out).
function Cups.parse(s)
	local out = {}
	if type(s) == "string" then
		for k in string.gmatch(s, "[^,]+") do
			if MOD[k] then
				table.insert(out, k)
			end
		end
	end
	return out
end

-- What the modifiers do to everyone's stats (HitLogic.effectiveStats' extra.mods): { add, height },
-- or nil when they don't.
function Cups.statMods(s)
	local add, height, any = {}, 0, false
	for _, k in ipairs(Cups.parse(s)) do
		local m = MOD[k]
		for stat, v in pairs(m.Add or {}) do
			add[stat] = (add[stat] or 0) + v
			any = true
		end
		if m.Height then
			height = height + m.Height
			any = true
		end
	end
	if not any then
		return nil
	end
	return { add = add, height = height }
end

-- The product of one multiplier field (Stamina, OppStamina, SlideCooldown, BlockCharge, BlockJump)
-- over the modifiers; 1 when none has it.
function Cups.factor(s, field)
	local f = 1
	for _, k in ipairs(Cups.parse(s)) do
		local v = MOD[k][field]
		if type(v) == "number" then
			f = f * v
		end
	end
	return f
end

function Cups.has(s, field)
	for _, k in ipairs(Cups.parse(s)) do
		if MOD[k][field] then
			return true
		end
	end
	return false
end

-- What a run pays when it ends after `round` (won: that round was won). Returns vp, gold.
function Cups.payout(cup, round, won)
	if won and round >= T.Rounds then
		return cup.PrizeVP, cup.PrizeGold
	elseif not won and round >= T.Rounds then
		return cup.Consolation, 0
	end
	return 0, 0
end

return Cups
