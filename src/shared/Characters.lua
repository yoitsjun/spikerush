-- Characters: tiers, builds and derived stats.
--
-- A character = tier + height + four stats (Attack, Defense, Speed, Jump).
--   * The tier caps each stat and caps the four-stat total (Config.TierCaps), so builds differ.
--   * Height is rolled when the character is created and sets standing reach.
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

function Characters.caps(tier)
	return Config.TierCaps[tier] or Config.TierCaps[Config.DefaultTier]
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

function Characters.startValue(tier)
	local cap = Characters.caps(tier).Cap
	return round(ST.Min + (cap - ST.Min) * ST.StartFraction)
end

function Characters.newBuild(tier, rng)
	local b = { Height = Characters.rollHeight(rng) }
	local start = Characters.startValue(tier)
	for _, k in ipairs(ST.Order) do
		b[k] = start
	end
	return b
end

function Characters.total(build)
	local sum = 0
	for _, k in ipairs(ST.Order) do
		sum = sum + (build[k] or 0)
	end
	return sum
end

-- Force any (possibly stale or untrusted) build to obey its tier's rules.
function Characters.sanitize(tier, build)
	build = type(build) == "table" and build or {}
	local caps = Characters.caps(tier)
	local start = Characters.startValue(tier)
	local out = { Height = round(clamp(tonumber(build.Height) or HT.Mean, HT.Min, HT.Max)) }
	for _, k in ipairs(ST.Order) do
		out[k] = round(clamp(tonumber(build[k]) or start, ST.Min, caps.Cap))
	end
	-- over the total: shave the biggest stat until it fits
	local guard = 0
	while Characters.total(out) > caps.Total and guard < 2000 do
		guard = guard + 1
		local big = ST.Order[1]
		for _, k in ipairs(ST.Order) do
			if out[k] > out[big] then
				big = k
			end
		end
		out[big] = out[big] - 1
	end
	return out
end

-- How many of `n` points can go into `stat` right now (stat cap and total cap both apply).
function Characters.raisable(tier, build, stat, n)
	if not Characters.isStat(stat) then
		return 0
	end
	local caps = Characters.caps(tier)
	local byStat = caps.Cap - (build[stat] or 0)
	local byTotal = caps.Total - Characters.total(build)
	return math.max(0, math.min(n, byStat, byTotal))
end

-- Points still needed to finish a build.
function Characters.remaining(tier, build)
	return math.max(0, Characters.caps(tier).Total - Characters.total(build))
end

-- Role-shaped builds for bots (and reference builds in tests): the two stats the role lives on
-- go to the cap and the other two split the rest.
local ROLE_PRIORITY = {
	WS = { "Attack", "Jump", "Defense", "Speed" },
	Solo = { "Attack", "Jump", "Speed", "Defense" },
	MB = { "Jump", "Attack", "Speed", "Defense" },
	SE = { "Speed", "Jump", "Attack", "Defense" },
}

function Characters.autoBuild(tier, role, height)
	local caps = Characters.caps(tier)
	local order = ROLE_PRIORITY[role or "WS"] or ROLE_PRIORITY.WS
	local b = { Height = height or HT.Mean }
	b[order[1]] = caps.Cap
	b[order[2]] = caps.Cap
	local rest = caps.Total - 2 * caps.Cap
	b[order[3]] = round(clamp(rest / 2, ST.Min, caps.Cap))
	b[order[4]] = round(clamp(rest - b[order[3]], ST.Min, caps.Cap))
	return Characters.sanitize(tier, b)
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

-- Convenience: a role-shaped, fully upgraded character of this tier.
function Characters.stats(tier, role, height)
	if not Characters.isTier(tier) then
		tier = Config.DefaultTier
	end
	return Characters.derive(tier, Characters.autoBuild(tier, role, height))
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
