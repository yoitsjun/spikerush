-- Characters: tiers, builds and derived stats.
--
-- A character = tier + height + four stats (Attack, Defense, Speed, Jump), and maybe an
-- ability. Players roll named presets (the Roster module); bots use roster characters of their tier
-- and role, or the role template scaled by tier (Config.RoleTemplates, Config.TierScale).
--   * Height sets standing reach.
--   * Hitting point at the top of a jump = standing reach (height) + vertical (Jump stat).
-- Stats map onto gameplay the same way for every tier (Config.StatCurve); a higher tier just
-- lets them go higher. derive() is pure, so the client predicts with exactly the numbers the
-- server uses.

local Config = require(script.Parent.Config)

local Characters = {}

local SPM = Config.Scale.StudsPerMeter
local FLOOR = Config.Scale.HeightFloor
local JUMP_SCALE = Config.Scale.JumpScale
local ST = Config.Stats
local HT = Config.Height

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

local function round(x)
	return math.floor(x + 0.5)
end

-- Height in the world (studs) for a real height in metres, and back. Up to the standing hand
-- height the scale is true; above it every metre is drawn JUMP_SCALE times taller, so jumps
-- look huge while hitting points, the Thunder line and the HUD keep real metres.
function Characters.studsAt(meters)
	local y = meters * SPM
	if y > FLOOR then
		y = FLOOR + (y - FLOOR) * JUMP_SCALE
	end
	return y
end

function Characters.metersAt(y)
	if y > FLOOR then
		y = FLOOR + (y - FLOOR) / JUMP_SCALE
	end
	return y / SPM
end

function Characters.tierIndex(tier)
	for i, t in ipairs(Config.Tiers) do
		if t == tier then
			return i
		end
	end
	return nil
end

function Characters.isTier(tier)
	return Characters.tierIndex(tier) ~= nil
end

function Characters.isAbility(ability)
	return type(ability) == "string" and Config.Abilities[ability] ~= nil
end

function Characters.isStat(stat)
	for _, k in ipairs(ST.Order) do
		if k == stat then
			return true
		end
	end
	return false
end

-- Letter group ("S", "A", ...) for colouring badges.
function Characters.group(tier)
	return string.sub(tier or "D", 1, 1)
end

function Characters.color(tier)
	return Config.TierColors[Characters.group(tier)] or Config.UI.Chalk
end

function Characters.ability(name)
	return Config.Abilities[name or ""]
end

------------------------------------------------------------------------------------------
-- Builds
------------------------------------------------------------------------------------------

-- Bell-shaped height roll (average of three uniforms), in whole centimetres.
function Characters.rollHeight(rng)
	rng = rng or Random.new()
	local u = (rng:NextNumber() + rng:NextNumber() + rng:NextNumber()) / 3 - 0.5
	return round(clamp(HT.Mean + u / 0.167 * HT.Spread, HT.Min, HT.Max))
end

function Characters.total(build)
	local sum = 0
	for _, k in ipairs(ST.Order) do
		sum = sum + (build[k] or 0)
	end
	return sum
end

-- How far up from Stats.Min a tier's stats sit (0..1): Config.TierScale.Low for D-, 1 for S+.
function Characters.tierScale(tier)
	local i = Characters.tierIndex(tier) or #Config.Tiers
	local TS = Config.TierScale
	return TS.Low + (1 - TS.Low) * ((i - 1) / (#Config.Tiers - 1)) ^ TS.Exponent
end

-- The role template scaled to a tier (bots without a roster character, and the simulations).
function Characters.template(tier, role, height)
	local t = Config.RoleTemplates[role or "WS"] or Config.RoleTemplates.WS
	local k = Characters.tierScale(tier)
	local b = { Height = height or t.Height }
	for _, stat in ipairs(ST.Order) do
		b[stat] = round(ST.Min + (t[stat] - ST.Min) * k)
	end
	return b
end

-- Kept for callers that think in "fully built characters of a tier and role".
function Characters.autoBuild(tier, role, height)
	return Characters.sanitize(tier, Characters.template(tier, role, height))
end

------------------------------------------------------------------------------------------
-- Roster characters and upgrades
------------------------------------------------------------------------------------------

local UP = Config.Upgrades

-- Where a freshly recruited character's stat starts (its roster value is the ceiling).
function Characters.baseStat(c, stat)
	return round(ST.Min + (c[stat] - ST.Min) * UP.StartFraction)
end

-- A character's current value of `stat` from its saved levels (missing = base), in range.
function Characters.statLevel(c, levels, stat)
	local base = Characters.baseStat(c, stat)
	if levels == "max" then
		return c[stat]
	end
	local v = type(levels) == "table" and tonumber(levels[stat]) or nil
	return round(clamp(v or base, base, c[stat]))
end

-- Gold for the point that takes `stat` from `value` to `value + 1` on character `c`.
function Characters.pointCost(c, value)
	local mul = UP.TierMul[c.Tier] or UP.TierMul[string.sub(c.Tier, 1, 1)] or 1
	return math.ceil((UP.BaseCost + (value - ST.Min) * UP.CostPerPoint) * mul)
end

-- Gold to go from `from` to `to` (to > from); the same amount comes back going down.
function Characters.upgradeCost(c, from, to)
	local sum = 0
	for v = from, to - 1 do
		sum = sum + Characters.pointCost(c, v)
	end
	return sum
end

-- A roster entry as a tier and a build. levels: the saved stat values ({ Attack = 150, ... }),
-- nil for a fresh recruit, or "max" for the fully upgraded character (bots).
function Characters.fromRoster(c, levels)
	local b = { Height = c.Height }
	for _, stat in ipairs(ST.Order) do
		b[stat] = Characters.statLevel(c, levels, stat)
	end
	return c.Tier, Characters.sanitize(c.Tier, b)
end

-- Clamp any (possibly stale or untrusted) build to the limits every preset lives in.
function Characters.sanitize(tier, build)
	build = type(build) == "table" and build or {}
	local out = { Height = round(clamp(tonumber(build.Height) or HT.Mean, HT.Min, HT.Max)) }
	for _, k in ipairs(ST.Order) do
		out[k] = round(clamp(tonumber(build[k]) or 100, ST.Min, ST.Max))
	end
	return out
end

------------------------------------------------------------------------------------------
-- Derived stats
------------------------------------------------------------------------------------------

function Characters.norm(value)
	return clamp(((value or ST.Min) - ST.Min) / (ST.Ref - ST.Min), 0, 1)
end

local cache = {}

function Characters.derive(tier, build)
	if not Characters.isTier(tier) then
		tier = Config.DefaultTier
	end
	build = Characters.sanitize(tier, build)
	local key = table.concat({ tier, build.Height, build.Attack, build.Defense, build.Speed, build.Jump }, ":")
	if cache[key] then
		return cache[key]
	end
	local i = Characters.tierIndex(tier)
	local s = {
		tier = tier,
		index = i,
		p = (i - 1) / (#Config.Tiers - 1),
		Height = build.Height,
		Attack = build.Attack,
		Defense = build.Defense,
		Speed = build.Speed,
		Jump = build.Jump,
	}
	for name, curve in pairs(Config.StatCurve) do
		local n = Characters.norm(build[curve.Stat])
		if curve.Extrapolate then
			-- boosted past the reference (Rally Cry, Rising Sun): keeps growing
			n = math.max(0, ((build[curve.Stat] or ST.Min) - ST.Min) / (ST.Ref - ST.Min))
		end
		n = n ^ (curve.Exp or 1)
		s[name] = curve.Range[1] + (curve.Range[2] - curve.Range[1]) * n
	end
	local hn = clamp((build.Height - HT.Min) / (HT.Max - HT.Min), 0, 1)
	s.Reach = HT.ZoneScale[1] + (HT.ZoneScale[2] - HT.ZoneScale[1]) * hn
	s.StandingReachM = build.Height * HT.ReachPerCm
	s.ContactMaxM = s.StandingReachM + s.VerticalM
	s.contactMaxStuds = Characters.studsAt(s.ContactMaxM)
	cache[key] = s
	return s
end

-- Convenience: the role template of a tier as derived stats.
function Characters.stats(tier, role, height)
	if not Characters.isTier(tier) then
		tier = Config.DefaultTier
	end
	return Characters.derive(tier, Characters.template(tier, role, height))
end

-- The same character with stat points added (`add`: { Attack = n, ... }) and then every stat
-- multiplied (`mul`, default 1): Adrenaline, Rising Sun, Rally Cry. Cached like derive.
function Characters.boosted(stats, add, mul)
	add = add or {}
	mul = mul or 1
	local b = { Height = stats.Height }
	for _, k in ipairs(ST.Order) do
		b[k] = math.floor((stats[k] + (add[k] or 0)) * mul + 0.5)
	end
	return Characters.derive(stats.tier, b)
end

-- Build carried on a Player's attributes (the server writes them; clients predict with them).
function Characters.fromAttributes(inst)
	local tier = inst:GetAttribute("Tier")
	if not Characters.isTier(tier) then
		return nil
	end
	local b = { Height = inst:GetAttribute("Height") }
	for _, k in ipairs(ST.Order) do
		b[k] = inst:GetAttribute(k)
	end
	return Characters.derive(tier, b)
end

function Characters.writeAttributes(inst, tier, build)
	inst:SetAttribute("Tier", tier)
	inst:SetAttribute("Height", build.Height)
	for _, k in ipairs(ST.Order) do
		inst:SetAttribute(k, build[k])
	end
end

-- Extra rise the hang force adds near the apex (it cancels part of gravity while |vy| is small).
function Characters.hangGain()
	local P = Config.Player
	local w, c = P.HangVelocityWindow, P.HangGravityCancel
	return w * w / (2 * P.Gravity) * (c / (1 - c))
end

-- Humanoid.JumpHeight (studs) that puts this character's hand exactly at its hitting point at
-- the top of the jump, hang included, measured from the avatar's real standing root height.
function Characters.jumpHeight(stats, groundY)
	local standing = (groundY or Config.Player.RootGround) + Config.Zones.SpikeUp
	return math.max(1.5, stats.contactMaxStuds - standing - Characters.hangGain())
end

-- Interpolate a {weakest, strongest} pair by tier (bot skill).
function Characters.byTier(stats, pair)
	return pair[1] + (pair[2] - pair[1]) * stats.p
end

return Characters
