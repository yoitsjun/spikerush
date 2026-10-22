-- HitLogic: every touch of the ball goes through HitLogic.compute.
--
-- Pure and deterministic (seeded by the ball sequence number): the hitter's client runs it for
-- instant prediction and the server runs the same function on the same inputs for the
-- authoritative result.
--
-- Spikes are decided by contact, not by a meter:
--   * where the ball is relative to your hand sets the angle: ball right at the hand = deep,
--     ball well ahead of you = short and steep toward the net, ball behind your head = long.
--   * how cleanly you meet it and how close you are to the top of your jump set the power.
--   * Thunder Spiker: contact above 4.00 m becomes a lightning spike.
--   * Azure Dragon: energy gathered in the air multiplies power; overcharging sends it out.
--   * Feral Leap: the gauge charged on the ground before the leap multiplies power; a full one
--     leaping at the net smashes through a block with less Attack.
--   * Ironclad (Taesan): a breakable Iron Wall while he has shields (ctx.ironclad); awakened
--     (ctx.awakened), Forge's charge powers and widens his spike (input.metal, input.early).
--   * Squall (Haneul): Eye of the Storm's hover charges the spike, and the charge is how deep it goes
--     (input.gale: let go at once, just over the net; the whole charge, their back line).
--   * Corona (Laith): Sundive, dropping onto the ball from above, multiplies power; Zenith bursts some
--     spikes (the seeded rng picks them, so the hitter's client agrees).
--   * the Halloween Match's ability cards stack with the character's own (ctx.abilities): every one
--     applies and the boosts multiply, the widest reach and the highest jump count once, Zero
--     Point's speed is the base the rest multiply, and breakthroughs grow only its own.
-- Receives drain the receiving team's stamina (a guard meter) depending on ball speed and the
-- receiver's Defense. Low stamina makes receives unreliable; a broken guard can't stop strong
-- spikes at all. Slides pay only Hits.SlideDrainMul of the drain and skip the knockback and the
-- red-zone wobble, but they can still break the guard (and can't save a broken one).

local Config = require(script.Parent.Config)
local Court = require(script.Parent.Court)
local BallPhysics = require(script.Parent.BallPhysics)
local Characters = require(script.Parent.Characters)
local Breakthrough = require(script.Parent.Breakthrough)
local Halloween = require(script.Parent.Halloween)

local HitLogic = {}

local C, Z, H, ST = Config.Court, Config.Zones, Config.Hits, Config.Stamina
local R, G = Config.Ball.Radius, Config.Ball.Gravity
local G0 = G
local SPM = Config.Scale.StudsPerMeter
local AZURE = Config.Abilities.Azure
local FERAL = Config.Abilities.Feral
local ADRENALINE = Config.Abilities.Adrenaline
local CHAIN = Config.Abilities.ChainReaction
local VECTOR = Config.Abilities.Vector
local FEATHER = Config.Abilities.Featherfall
local IRON = Config.Abilities.Ironclad
local THUNDER = Config.Abilities.Thunder
local PLUNGE = Config.Abilities.Plunge
local TURN = Config.Abilities.Turnabout
local SUN = Config.Abilities.RisingSun
local RALLY = Config.Abilities.RallyCry
local COUNTER = Config.Abilities.Counter
local ZERO = Config.Abilities.ZeroPoint
local SKY = Config.Abilities.Skyward
local CORONA = Config.Abilities.Corona
local SQUALL = Config.Abilities.Squall
local TYRANT = Config.Abilities.Tyrant
local SUNSHINE = Config.Abilities.Sunshine

-- An ability's setting grown by breakthroughs (Config.Breakthrough): `level` is the character's
-- (ctx.breakLevel, for its own ability only: levelOf), or for a setter's ability read on the spike,
-- the set's meta.setBreak (setLevel).
local function ab(ability, key, level)
	return Breakthrough.ab(ability, key, level)
end

-- Stacked abilities (Characters.abilityList): ctx.ability is the character's own (the primary),
-- ctx.abilities a set of every ability it plays (primary included) and ctx.abilityList the same in
-- order (primary, then the Halloween Match's ability cards in hand order). Without them it's the one
-- ability, as before.
local function hasIn(ability, set, name)
	return ability == name or (type(set) == "table" and set[name] == true)
end

function HitLogic.has(ctx, name)
	return ctx ~= nil and hasIn(ctx.ability, ctx.abilities, name)
end

-- Breakthroughs grow only the character's own ability: a card's plays at +0.
function HitLogic.levelOf(ctx, name)
	if ctx ~= nil and ctx.ability == name then
		return ctx.breakLevel or 0
	end
	return 0
end

-- Inputs two abilities claim: the first of them in the character's order owns it (the other's use
-- of that input is off; the rest of it still works). GroundJump: hold Jump on the ground (Feral's
-- prowl and leap, Squall's Tailwind). AirSpike: hold Spike in the air (Azure's charge, Squall's
-- Eye of the Storm); a Sundive (Corona) takes the press when the ball is below reach.
HitLogic.INPUTS = { GroundJump = { "Feral", "Squall" }, AirSpike = { "Azure", "Squall" } }

-- The first of `names` in `list` (an ordered ability list), or nil.
function HitLogic.firstOf(list, names)
	for _, a in ipairs(list or {}) do
		for _, n in ipairs(names) do
			if a == n then
				return a
			end
		end
	end
	return nil
end

function HitLogic.inputOwner(list, slot)
	return HitLogic.firstOf(list, HitLogic.INPUTS[slot] or {})
end

-- A set from a name or a set.
local function asSet(abilities)
	if type(abilities) == "table" then
		return abilities
	end
	return { [abilities or ""] = true }
end

-- The widest spike zone of the abilities held (the largest, not the product: four of them
-- multiplied would be three times the zone). leap: Feral's gauge; forge: Ironclad's charge.
function HitLogic.spikeReachAll(abilities, leap, forge)
	local r = 1
	for name in pairs(asSet(abilities)) do
		r = math.max(r, HitLogic.spikeReach(name, name == "Ironclad" and forge or leap))
	end
	return r
end

-- A spike or serve jump's height multiplier: the largest that applies (Thunder's High Strike,
-- Squall's Updraft, Corona's Sun Leap while its window is on), never the product.
function HitLogic.leapMul(abilities, coronaOn)
	local set = asSet(abilities)
	local m = 1
	if set.Thunder then
		m = math.max(m, THUNDER.LeapMul)
	end
	if set.Squall then
		m = math.max(m, SQUALL.LeapMul)
	end
	if set.Corona and coronaOn then
		m = math.max(m, CORONA.LeapMul)
	end
	return m
end

local has, levelOf = HitLogic.has, HitLogic.levelOf

-- A custom match's Gravity modifier (Config.Mutators): the ball's gravity x mul for every arc this
-- module solves. The server and every client set it from the Mutators attribute together, so
-- prediction still matches; 1 is the usual game.
function HitLogic.setGravity(mul)
	G = G0 * (tonumber(mul) or 1)
end

function HitLogic.ballGravity()
	return G
end

-- A setter's breakthroughs read on the spike off her set (meta.setBreak): they grow her own ability
-- only (meta.setBreakFor), so a set ability from a card plays at +0.
local function setLevel(last, name)
	if last ~= nil and last.setBreakFor == name then
		return last.setBreak
	end
	return 0
end

local ACTION_CODE = { Bump = 1, Set = 2, Spike = 3, Feint = 4, Block = 5, Toss = 6, Serve = 7, Underhand = 8 }
local SERVES = { JumpServe = true, Overhand = true, Underhand = true }

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function falloff(x, p)
	if x <= 0 then
		return 1
	end
	if x >= 1 then
		return 0
	end
	return 1 - x ^ p
end

-- The ball always flies in the x = 0 plane.
local function planar(v)
	return Vector3.new(0, v.Y, v.Z)
end

function HitLogic.kmh(studsPerSecond)
	return studsPerSecond / SPM * 3.6
end

function HitLogic.studs(kmh)
	return kmh / 3.6 * SPM
end

-- 0..1: how hard a spike of `kmh` looks (Config.Hits.SpeedFeel), for the effects.
function HitLogic.speedFeel(kmh)
	local f = Config.Hits.SpeedFeel
	return math.clamp(((kmh or 0) - f[1]) / (f[2] - f[1]), 0, 1)
end

-- Real height in metres of a world height (see Characters.studsAt).
function HitLogic.meters(y)
	return Characters.metersAt(y)
end

function HitLogic.grade(q)
	if q >= H.PerfectAt then
		return "PERFECT"
	elseif q >= H.GreatAt then
		return "GREAT"
	elseif q >= H.GoodAt then
		return "GOOD"
	end
	return "BAD"
end

function HitLogic.isServe(hitType)
	return SERVES[hitType or ""] == true
end

------------------------------------------------------------------------------------------
-- Zones (2D: only z and y matter). Each returns (inZone, quality, ...).
------------------------------------------------------------------------------------------

-- How far forward a character's serve toss can go (x TossForwardMax): Feral Leap's goes further.
function HitLogic.tossReach(ability)
	-- (a name or a set: the largest, Feral's and Corona's both 1.6, never 2.56)
	local set = asSet(ability)
	local r = 1
	if set.Feral then
		r = math.max(r, FERAL.TossReachMul)
	end
	if set.Corona then
		r = math.max(r, CORONA.TossReachMul) -- Laith's Long Toss
	end
	return r
end

-- The spike zone's size for an ability (x the usual): Feral Leap reaches wider.
function HitLogic.spikeReach(ability, gauge)
	if ability == "Feral" then
		-- (off a charged leap, gauge > 0: wider still)
		return (gauge or 0) > 0 and FERAL.LeapReachMul or FERAL.ReachMul
	elseif ability == "ZeroPoint" then
		return Config.Abilities.ZeroPoint.ReachMul
	elseif ability == "Squall" then
		return SQUALL.ReachMul -- Shear
	elseif ability == "Ironclad" then
		return IRON.SpikeReach + IRON.ReachMul * clamp(tonumber(gauge) or 0, 0, 1) -- Steel Reach (gauge: Forge's charge)
	end
	return 1
end

-- Feral Leap's gauge after holding the charge `held` seconds (chargeTime fills it: the player's
-- ChargeTime, the AI's AutoChargeTime). With Bloodlust on (`over`) it keeps filling past full,
-- OverTime more to OverMax; without, it stops at 1.
function HitLogic.feralGauge(held, chargeTime, over)
	local g = math.max(tonumber(held) or 0, 0) / math.max(chargeTime or FERAL.ChargeTime, 0.01)
	if g <= 1 or not over then
		return math.min(g, 1)
	end
	local extra = (held - (chargeTime or FERAL.ChargeTime)) / math.max(FERAL.OverTime, 0.01)
	return math.min(1 + extra * (FERAL.OverMax - 1), FERAL.OverMax)
end

-- Updraft (Squall): whether the ball's last touch is a set she slows (a teammate's, not her own).
function HitLogic.updraftCanSlow(meta, team, id)
	return type(meta) == "table" and meta.hitType == "Set" and meta.team ~= nil and meta.team == team and meta.id ~= id
end

-- The set slowed to `f` of its speed from shared time `t`, along the same curve: velocity x f and
-- gravity x f^2 (where it is u seconds on, it now is u / f seconds on). The server relaunches the
-- ball with it, and her client works out the same path to spring at.
function HitLogic.updraftLaunch(path, t, f)
	local s = BallPhysics.segmentAt(path, t)
	local p = BallPhysics.positionAt(path, t)
	return BallPhysics.newLaunch(p, BallPhysics.velocityAt(path, t) * f, s.a * (f * f), t)
end

-- Squall: a hover's charge (0..1) as the spot it sends the spike to, from `lo` (just over the net)
-- to `hi` (the very back) in AimSteps jumps: the target flashes from one to the next as it charges.
function HitLogic.galeDepth(gale, lo, hi)
	local n = SQUALL.AimSteps
	local i = math.floor(clamp(tonumber(gale) or 0, 0, 1) * (n - 1) + 1e-6)
	return lerp(lo, hi, i / (n - 1)), i + 1
end

-- Ironclad: his shields (nil: a fresh entity's whole set); with none left he's awakened.
function HitLogic.ironLives(lives)
	return clamp(math.floor(tonumber(lives) or IRON.Lives), 0, IRON.Lives)
end

-- The serve toss: release point and velocity for a toss `height` studs up. `forward` (0..1)
-- throws it out in front so the server can run into it: at full it comes back to hand height
-- TossForwardMax (x `reach`, HitLogic.tossReach) closer to the net. Also draws the client's
-- dotted toss guide.
function HitLogic.tossLaunch(root, side, height, forward, reach)
	local h = clamp(height or H.TossLow, H.TossLow, H.TossHighMax)
	local fwd = clamp(forward or 0, 0, 1)
	local p = Vector3.new(0, root.Y + 2.0, root.Z - side * 0.8)
	local vy = math.sqrt(2 * G * h)
	local vz = H.TossForward + fwd * H.TossForwardMax * (reach or 1) / (2 * vy / G)
	return p, Vector3.new(0, vy, -side * vz), h, fwd
end

-- Returns ok, contactQuality, dz (ball ahead of the hand, toward the net), dy.
function HitLogic.spikeZone(root, ball, side, stats, scale)
	scale = (scale or 1) * ((stats and stats.Reach) or 1)
	local handZ = root.Z - side * Z.SpikeForward
	local handY = root.Y + Z.SpikeUp
	local dz = (ball.Z - handZ) * -side
	local dy = ball.Y - handY
	local nz = (dz - Z.SpikeCenterDz) / (Z.SpikeRadiusZ * scale)
	local ny = (dy - Z.SpikeCenterDy) / (Z.SpikeRadiusY * scale)
	local d = math.sqrt(nz * nz + ny * ny)
	if d > 1 then
		return false, 0, dz, dy
	end
	return true, clamp(falloff(d, 1.5), 0, 1), dz, dy
end

-- 0 at a standing reach, 1 at this character's max hitting point.
function HitLogic.heightQuality(ballY, stats, groundY)
	local standing = (groundY or Config.Player.RootGround) + Z.SpikeUp
	local top = stats.contactMaxStuds
	if top <= standing + 0.1 then
		return 1
	end
	return clamp((ballY - standing) / (top - standing), 0, 1)
end

function HitLogic.receiveZone(root, ball, side, stats, sliding, mul)
	local reachMul = ((stats and stats.Reach) or 1) * (mul or 1) -- (mul: Sunshine's wider digs)
	local reach = Z.ReceiveReach * reachMul
	local minY, maxY = Z.ReceiveMinY, Z.ReceiveMaxY
	if sliding then
		reach = Z.SlideReach * reachMul
		minY, maxY = Z.SlideMinY, Z.SlideMaxY
	end
	local dz = (ball.Z - root.Z) * -side - Z.ReceiveForward
	local dy = ball.Y - root.Y
	if math.abs(dz) > reach + R or dy < minY or dy > maxY then
		return false, 0
	end
	local qh = falloff(math.abs(dz) / (reach + R * 0.5), 1.6)
	local qv = falloff(math.abs(dy - Z.ReceiveIdealY) / Z.ReceiveHalfY, 1.5)
	return true, clamp(qh * 0.6 + qv * 0.4, 0, 1)
end

function HitLogic.setZone(root, ball, side, stats)
	local reach = Z.SetReach * ((stats and stats.Reach) or 1)
	local dz = (ball.Z - root.Z) * -side
	local dy = ball.Y - root.Y
	if math.abs(dz) > reach + R or dy < Z.SetMinY or dy > Z.SetMaxY then
		return false, 0
	end
	local qh = falloff(math.abs(dz) / (reach + R * 0.5), 1.4)
	local qv = falloff(math.abs(dy - Z.SetIdealY) / Z.SetHalfY, 1.4)
	return true, clamp(qh * 0.5 + qv * 0.5, 0, 1)
end

-- Standing overhand serve: contact above the head, slightly in front.
function HitLogic.floatZone(root, ball, side)
	local dz = (ball.Z - root.Z) * -side - 0.8
	local dy = ball.Y - (root.Y + Z.FloatUp)
	local d = math.sqrt((dz / Z.FloatRadiusZ) ^ 2 + (dy / Z.FloatRadiusY) ^ 2)
	if d > 1 then
		return false, 0
	end
	return true, clamp(falloff(d, 1.4), 0, 1)
end

-- Block: hands above the tape, reaching over the net. Returns ok, quality, fingertips. iron:
-- The block box's extra reach (blockBox's `iron`): Iron Wall's whole wall while it's up, and while
-- Ironclad's Bulwark has shields left (he's Iron Wall for his 3 lives); else nil. `hitType` (the
-- attack's) is kept for callers: every attack meets the wall.
function HitLogic.wallReach(ironWallUp, bulwark, hitType)
	if ironWallUp or bulwark then
		return true
	end
	return nil
end

-- Sunshine lit (Haesol): her block box grows by SunBox, on top of any other extras (Iron Wall's
-- whole wall already covers it).
function HitLogic.sunBox(iron, sunOn)
	if not sunOn then
		return iron
	end
	if iron == true then
		return true
	end
	local out = {}
	for k, v in pairs(SUNSHINE.SunBox) do
		out[k] = v + (type(iron) == "table" and iron[k] or 0)
	end
	if type(iron) == "table" then
		for k, v in pairs(iron) do
			if out[k] == nil then
				out[k] = v
			end
		end
	end
	return out
end

-- A custom match's Walls (Config.Mutators BlockUp): everyone's block reaches higher.
function HitLogic.wallsBox(iron, mut)
	if not mut or (mut.blockUp or 0) <= 0 or iron == true then
		return iron
	end
	local out = { ReachUp = mut.blockUp }
	if type(iron) == "table" then
		for k, v in pairs(iron) do
			out[k] = v + (k == "ReachUp" and mut.blockUp or 0)
		end
	end
	return out
end

-- The Tyrant's Iron Fortress: the block's reach over the tape while his Emperor's Dictate is on
-- against this team (ctx.dictated), else nil.
function HitLogic.blockCut(dictated)
	return dictated and TYRANT.BlockCut or nil
end

-- Haesol's receive reach: DigReach always, SunReach more while Sunshine is lit.
function HitLogic.digReach(ctx)
	if not has(ctx, "Sunshine") then
		return 1
	end
	return SUNSHINE.DigReach * (ctx.sunOn and SUNSHINE.SunReach or 1)
end

-- Her perfect-timing window (everyone else's: PerfectStanceMin..Max).
function HitLogic.perfectStance(ctx)
	if has(ctx, "Sunshine") then
		return SUNSHINE.PerfectStance[1], SUNSHINE.PerfectStance[2]
	end
	return H.PerfectStanceMin, H.PerfectStanceMax
end

-- Iron Wall is up, and the box is bigger (Config.Abilities.IronWall), down to the floor with Floor.
-- `iron`: true for Iron Wall's whole wall, or a table of the same extras (Ironclad's Box).
-- `cut`: the share of its reach over the tape the box keeps (the Tyrant's Iron Fortress); nil: all.
function HitLogic.blockBox(root, ball, side, stats, iron, cut)
	local IW = iron == true and Config.Abilities.IronWall or (type(iron) == "table" and iron or nil)
	if math.abs(root.Z) > Z.BlockNetDistance + (IW and IW.NetExtra or 0) then
		return false, 0, false
	end
	local zs = ball.Z * side
	if zs > Z.BlockOwnDepth + (IW and IW.OwnDepth or 0) or zs < -(Z.BlockOverDepth + (IW and IW.OverDepth or 0)) then
		return false, 0, false
	end
	local top = root.Y + Z.BlockReachUp + (IW and IW.ReachUp or 0)
	if cut then
		top = C.NetTop + math.max(0, top - C.NetTop) * cut
	end
	local bottom = (IW and IW.Floor) and 0 or (C.NetTop - 0.6)
	if ball.Y > top + R or ball.Y < bottom then
		return false, 0, false
	end
	local qy = clamp((top + R - ball.Y) / 2.4, 0, 1)
	local qz = falloff(math.abs(zs - 0.1) / (Z.BlockOwnDepth + R), 1.3)
	local q = clamp((qy * 0.5 + qz * 0.5) * ((stats and stats.BlockPower) or 1), 0, 1.15)
	return true, q, (top + R - ball.Y) < 0.9
end

-- When a ball on `path` first meets a block box (blockBox) between times `from` and `to`, heading
-- onto the blocker's side: t and the ball's position, or nil. Checked every BLOCK_STEP seconds (a
-- 260 km/h spike moves about a stud and a half between checks; the box is 3 studs deep), at least
-- 6 times. The client runs it from where an attack left the hand when it hears of the attack late
-- (the owner, 2026-10-16: "there seems to be a bug with the hitboxes on the blocking tutorial": on
-- a phone's ping the drill's spike, hit 1.2 m off the net, was through the hands before the client
-- knew of it, and only the last frame was ever checked).
local BLOCK_STEP = 0.004
function HitLogic.blockAlong(path, from, to, root, side, stats, iron, cut)
	local n = clamp(math.ceil((to - from) / BLOCK_STEP), 6, 240)
	for i = 1, n do
		local t = from + (to - from) * i / n
		local p = BallPhysics.positionAt(path, t)
		if BallPhysics.velocityAt(path, t).Z * side > 0 and HitLogic.blockBox(root, p, side, stats, iron, cut) then
			return t, p
		end
	end
	return nil
end

-- Ironclad's shields after a block of his (meta): every attack a shield stops cracks it, and the
-- CracksToBreak-th crack shatters it (the owner: "it cracks on one hit and breaks on the next").
-- Returns the shields and cracks left.
function HitLogic.ironAfterBlock(lives, cracks, meta)
	lives = HitLogic.ironLives(lives)
	cracks = math.max(0, math.floor(tonumber(cracks) or 0))
	if lives == 0 or type(meta) ~= "table" or meta.hitType ~= "Block" then
		return lives, cracks
	end
	-- (only Bulwark's own stops crack it, meta.bulwark: one made with Iron Wall up doesn't)
	if meta.ironWall and meta.bulwark and meta.shatter then
		return lives - 1, 0 -- the stop that shatters it (the last crack, or a ShatterKmh spike at once)
	end
	if meta.ironWall and meta.bulwark then
		cracks = cracks + 1
		if cracks >= IRON.CracksToBreak then
			return lives - 1, 0
		end
	end
	return lives, cracks
end

------------------------------------------------------------------------------------------
-- Trajectory solvers (all planar)
------------------------------------------------------------------------------------------

-- Lob through `to` on the way down, peaking at apexY.
function HitLogic.solveArc(from, to, apexY, g)
	apexY = math.max(apexY, from.Y + 0.4, to.Y + 0.4)
	local vy = math.sqrt(2 * g * (apexY - from.Y))
	local tDown = math.sqrt(2 * (apexY - to.Y) / g)
	local T = vy / g + tDown
	return Vector3.new(0, vy, (to.Z - from.Z) / T), T
end

local function directFor(from, to, T, g)
	local dy = to.Y - from.Y
	return Vector3.new(0, (dy + 0.5 * g * T * T) / T, (to.Z - from.Z) / T)
end

-- Straight-ish shot that lands exactly on `to` and leaves the hand at exactly `speed`.
-- Launch speed first falls then rises with flight time (fast direct shot vs slow lob), so find
-- the minimum and take the direct branch. Too slow to reach? Use the minimum-speed shot.
function HitLogic.solveSpeed(from, to, speed, g)
	local best, bestT = math.huge, 0.5
	local T = 0.05
	while T <= 3 do
		local m = directFor(from, to, T, g).Magnitude
		if m < best then
			best, bestT = m, T
		end
		T = T + 0.05
	end
	if speed <= best then
		return directFor(from, to, bestT, g), bestT
	end
	local lo, hi = 0.02, bestT
	for _ = 1, 24 do
		local mid = (lo + hi) * 0.5
		if directFor(from, to, mid, g).Magnitude > speed then
			lo = mid
		else
			hi = mid
		end
	end
	return directFor(from, to, hi, g), hi
end

-- Height margin over the tape when the ball crosses z = 0, or nil if it never heads there.
function HitLogic.netMargin(from, v, g)
	if math.abs(v.Z) < 1e-4 then
		return nil
	end
	local t = -from.Z / v.Z
	if t <= 0 then
		return nil
	end
	local y = from.Y + v.Y * t - 0.5 * g * t * t
	return y - (C.NetTop + R), t
end

-- Push a hard shot deeper until it clears the tape (contacts below the tape still net).
local function speedWithAssist(from, target, speed, g, side, steps)
	local v, T = HitLogic.solveSpeed(from, target, speed, g)
	for _ = 1, steps do
		local m = HitLogic.netMargin(from, v, g)
		if m == nil or m >= H.NetClearance then
			break
		end
		target = target + Vector3.new(0, 0, -side * H.NetAssistPush)
		v, T = HitLogic.solveSpeed(from, target, speed, g)
	end
	return v, T, target
end

local function arcWithAssist(from, target, apex, g)
	local v, T = HitLogic.solveArc(from, target, apex, g)
	for _ = 1, 10 do
		local m = HitLogic.netMargin(from, v, g)
		if m == nil or m >= H.NetClearance then
			break
		end
		apex = apex + 0.38 * SPM
		v, T = HitLogic.solveArc(from, target, apex, g)
	end
	return v, T
end

-- Where a ball launched from `from` with velocity v reaches floor height.
local function landingZ(from, v, g)
	local disc = v.Y * v.Y + 2 * g * (from.Y - R)
	local tl = (v.Y + math.sqrt(math.max(disc, 0))) / g
	return from.Z + v.Z * tl
end

-- Lob that, if nobody touches it, still lands at least minDepth from the net on its own side.
local function ownSideArc(from, target, apex, g, side, minDepth)
	local v, T = HitLogic.solveArc(from, target, apex, g)
	for _ = 1, 8 do
		local lz = landingZ(from, v, g) * side
		if lz >= minDepth then
			break
		end
		target = target + Vector3.new(0, 0, side * (minDepth - lz + 0.1 * SPM))
		v, T = HitLogic.solveArc(from, target, apex, g)
	end
	return v, T
end

-- A set from `ball` to the attack spot `depth` from the net (default: the set type's spot, no
-- error), coming down through `arriveY` (default SetArriveY; a higher one lifts the whole arc):
-- its launch velocity and gravity. The setter AI also uses it to see a quick coming.
-- fast: the Tyrant's Set (the usual arc, flown SetSpeed times faster).
function HitLogic.setArc(ball, side, setType, depth, underhand, lift, arriveY, fast)
	local apex = H.SetApexOpen
	if setType == "Quick" then
		apex = H.SetApexQuick
	elseif setType == "Back" then
		apex = H.SetApexBack
	end
	if underhand then
		apex = apex * 0.92
	end
	apex = apex + (lift or 0) -- a jump set releases higher, so the set goes higher
	arriveY = arriveY or H.SetArriveY
	apex = apex + (arriveY - H.SetArriveY)
	apex = math.max(apex, ball.Y + 0.38 * SPM, arriveY + 0.5 * SPM)
	depth = math.max(depth or Court.attackDepth(setType), 0.47 * SPM)
	apex = apex + H.SetDeepApex * math.max(0, depth - H.BackDepth) -- deep sets go higher
	local g = G * H.SetGravityScale
	if fast then
		g = g * TYRANT.SetSpeed * TYRANT.SetSpeed
		apex = math.max(apex - TYRANT.SetLower, arriveY + 0.8 * SPM, ball.Y + 0.38 * SPM)
	end
	return ownSideArc(ball, Vector3.new(0, arriveY, side * depth), apex, g, side, 0.38 * SPM), g
end

local function jitter(rng, mag)
	return (rng:NextNumber() * 2 - 1) * mag
end

-- Hard-driven balls punish sloppy receives more than clean ones: q = 1 stays 1.
local function applyIncoming(q, kmh)
	local p = clamp((kmh - H.IncomingSpeedPenaltyStartKmh) / H.IncomingSpeedPenaltyRangeKmh, 0, 1) * H.IncomingSpeedPenaltyMax
	return clamp(q * (1 - 2 * p * (1 - q)), 0, 1)
end

-- Stamina a heavy ball costs the receiving team.
-- Grows faster than the speed: a 180 km/h spike costs far more than two 120s.
function HitLogic.drainFor(kmh, stats)
	local over = kmh - ST.DrainStartKmh
	if over <= 0 then
		return 0
	end
	return ST.DrainPer100Kmh * (over / 100) ^ ST.DrainExponent * (1 - ((stats and stats.DrainReduction) or 0))
end

-- How hard an attacker of this tier hits the guard (1 for S+, down to TierDrainLow for D-).
function HitLogic.tierDrain(tier)
	local i = Characters.tierIndex(tier) or #Config.Tiers
	return ST.TierDrainLow + (1 - ST.TierDrainLow) * ((i - 1) / (#Config.Tiers - 1)) ^ ST.TierDrainExponent
end

-- The share of the drain a perfectly timed receive still pays.
function HitLogic.perfectDrainMul(kmh)
	local t = clamp((kmh - ST.PerfectMulFromKmh) / (ST.PerfectMulToKmh - ST.PerfectMulFromKmh), 0, 1)
	return lerp(ST.PerfectDrainMul, ST.PerfectDrainMulMax, t)
end

function HitLogic.isHeavy(lastHit)
	if not lastHit then
		return false
	end
	if lastHit.reaction then
		return true -- an exploding Chain Reaction ball, even a feint
	end
	if lastHit.breakThrough then
		return true -- a Feral Leap spike that smashed through the block is still a spike to dig
	end
	if lastHit.noDrain then
		return false
	end
	local ht = lastHit.hitType
	return ht == "Spike" or ht == "JumpServe" or ht == "Overhand"
end

-- Adrenaline: active while the team's stamina is below the threshold. (set: every ability played,
-- HitLogic.has's ctx.abilities, so a card's Adrenaline counts)
function HitLogic.adrenaline(ability, stamina, set)
	if not hasIn(ability, set, "Adrenaline") or type(stamina) ~= "table" or not stamina.max or stamina.max <= 0 then
		return false
	end
	return stamina.value / stamina.max < ADRENALINE.StaminaBelow
end

-- The share of its bar a team gets back after losing `streak` points in a row (1: just this
-- one): Stamina.RecoverLoser, times LossStreakGrowth for each one before it, up to all of it.
function HitLogic.lossRecovery(streak)
	local n = math.max(1, math.floor(tonumber(streak) or 1))
	return math.min(1, ST.RecoverLoser * ST.LossStreakGrowth ^ (n - 1))
end

-- Zero Point's sweet spot: the ball `dz` in front of the raised hand and `dy` above it (studs,
-- HitLogic.spikeZone's), inside ZeroDz and ZeroDy (x the character's reach).
function HitLogic.zeroSpot(dz, dy, stats)
	local k = ((stats and stats.Reach) or 1) * ZERO.ReachMul
	return dz >= ZERO.ZeroDz[1] * k and dz <= ZERO.ZeroDz[2] * k and dy >= ZERO.ZeroDy[1] * k and dy <= ZERO.ZeroDy[2] * k
end

-- Skyward: the most her hitting point climbs (metres; breakthroughs raise it).
function HitLogic.skyMax(level)
	return ab("Skyward", "MaxLift", level)
end

-- Skyward: her lift (metres on the hitting point) kept in range; nil is the start of a set.
function HitLogic.skyLift(lift, level)
	return clamp(tonumber(lift) or SKY.StartLift, SKY.StartLift, HitLogic.skyMax(level))
end

-- Skyward: what a spike met at `qHeight` (0..1, the top of her jump at 1) adds to her lift.
function HitLogic.skyGain(qHeight)
	return SKY.Gain * clamp(qHeight or 0, 0, 1) ^ SKY.GainExp
end

-- Corona: every stat's multiplier, on (the flare) or off after `stacks` uses (the penalty).
function HitLogic.coronaMul(on, stacks, level)
	if on then
		return 1 + ab("Corona", "Boost", level)
	end
	return 1 - CORONA.PenaltyPer * clamp(math.floor(tonumber(stacks) or 0), 0, CORONA.MaxStacks)
end

-- Sundive's arc from p0 to p2: its middle control point (a quadratic curve bowed up by DiveArc of
-- its length), shared by his movement and the drawn path.
function HitLogic.diveControl(p0, p2)
	local chord = (p2 - p0).Magnitude
	local mid = (p0 + p2) / 2
	return Vector3.new(p0.X, math.max(p0.Y, mid.Y + CORONA.DiveArc * chord), mid.Z)
end

-- Sundive's timing for a dive meeting the ball in T seconds: how long he hangs where he is first,
-- then how long the dash takes (DiveDashTime at most).
function HitLogic.diveTiming(T)
	local dash = math.min(math.max(tonumber(T) or 0, 0), CORONA.DiveDashTime)
	return math.max((tonumber(T) or 0) - dash, 0), math.max(dash, 1 / 240)
end

-- A point on that arc at s (0..1).
function HitLogic.divePoint(p0, c, p2, s)
	local u = 1 - s
	return p0 * (u * u) + c * (2 * u * s) + p2 * (s * s)
end

-- Sundive: how much of the dive bonus a spike gets (0..1) from how far he dropped onto it (studs).
function HitLogic.diveFraction(drop)
	return clamp(((tonumber(drop) or 0) - CORONA.DiveMinDrop) / (CORONA.DiveFullDrop - CORONA.DiveMinDrop), 0, 1)
end

-- Chain Reaction's step for an explosion: 1 for the first of a rally, then 2, 3 (ctx.chain: how
-- many the team has set off this rally).
function HitLogic.chainStep(chain)
	return clamp(math.floor(tonumber(chain) or 0) + 1, 1, #CHAIN.PowerMul)
end

-- Rising Sun: the Sunrise level from the points the other team has this set (0..MaxLevel).
function HitLogic.sunLevel(enemyPoints)
	return math.min(SUN.MaxLevel, math.floor(math.max(0, enemyPoints or 0) / SUN.Every))
end

-- The stats a touch is computed with. Adrenaline adds Attack and Jump while the team's stamina
-- is low; Rising Sun adds its level's points; Counter Edge adds its meter's share of PerFull;
-- Feral Leap played by the AI (extra.auto) loses Attack; Rally Cry (extra.teamBoost) multiplies
-- every stat of the team; Corona multiplies his own, up while it's on and down by his uses while
-- it's off (extra.coronaOn, extra.coronaStacks). extra: { enemyPoints, counter, auto, teamBoost,
-- coronaOn, coronaStacks, breakLevel, abilities, dictate, dictated, grounded, sunOn, digging } (a
-- touch passes its ctx): the Tyrant's Stat Hijack (his team's points, the other team's share lost),
-- Sovereign's Guard's grounded hitter, Sunshine lit and a dig of hers. `ability` is the
-- character's own, the one its breakthroughs (extra.breakLevel) grow; extra.abilities is the set of
-- every ability it plays (a Halloween card's at +0), and each one's boost applies. The server raises
-- the humanoid's jump and run speed to match (TeamService), so the hitting point is real.
function HitLogic.effectiveStats(stats, ability, stamina, extra)
	local add = {}
	local any = false
	local set = extra and extra.abilities
	local function on(name)
		return hasIn(ability, set, name)
	end
	local function lv(name)
		return ability == name and extra and extra.breakLevel or 0
	end
	local adrenaline = HitLogic.adrenaline(ability, stamina, set)
	if adrenaline then
		add.Attack = math.floor(ab("Adrenaline", "AttackBonus", lv("Adrenaline")) + 0.5)
		add.Jump = math.floor(ab("Adrenaline", "JumpBonus", lv("Adrenaline")) + 0.5)
		any = true
	end
	if on("RisingSun") then
		local lvl = HitLogic.sunLevel(extra and extra.enemyPoints)
		if lvl > 0 then
			for k, v in pairs(ab("RisingSun", "PerLevel", lv("RisingSun"))) do
				add[k] = (add[k] or 0) + math.floor(v * lvl + 0.5)
			end
			any = true
		end
	end
	if on("Counter") then
		-- Counter Edge: she scales with the spikes she has received (the meter, 0..100)
		local c = clamp((extra and extra.counter) or 0, 0, 100) / 100
		if c > 0 then
			for k, v in pairs(COUNTER.PerFull) do
				add[k] = (add[k] or 0) + math.floor(v * c + 0.5)
			end
			any = true
		end
	end
	if on("Skyward") then
		-- Skyward: her hitting point climbs with her spikes this set (extra.lift, metres), and her
		-- Attack with it
		local lift = HitLogic.skyLift(extra and extra.lift, lv("Skyward"))
		add.Lift = lift
		-- (her Attack tops out at the usual full lift; a breakthrough's extra lift is height alone)
		add.Attack = (add.Attack or 0) + math.floor(SKY.AttackAtMax * math.min(1, (lift - SKY.StartLift) / (SKY.MaxLift - SKY.StartLift)) + 0.5)
		any = true
	end
	if on("Squall") and extra and extra.squallOn then
		-- Squall: faster, and Attack with her (boosted) Speed
		local speed = math.floor(stats.Speed * SQUALL.SpeedBoost + 0.5)
		add.Speed = (add.Speed or 0) + speed
		add.Attack = (add.Attack or 0) + math.floor(SQUALL.AttackPerSpeed * (stats.Speed + speed) + 0.5)
		any = true
	end
	if extra and extra.mut and next(extra.mut.add) then
		-- a custom match's modifiers (Config.Mutators): stat points for everyone
		for k, v in pairs(extra.mut.add) do
			add[k] = (add[k] or 0) + v
		end
		any = true
	end
	if extra and extra.dictate then
		-- the Tyrant's Stat Hijack, his team's side: the stolen points
		for k, v in pairs(TYRANT.TeamAdd) do
			add[k] = (add[k] or 0) + v
		end
		any = true
	end
	if extra and extra.dictated then
		-- and the other team's, Locked: Steal of their Jump and Speed, a share of it off their Attack
		-- (a number: his grown Steal)
		local steal = type(extra.dictated) == "number" and extra.dictated or TYRANT.Steal
		for _, k in ipairs({ "Jump", "Speed" }) do
			add[k] = (add[k] or 0) - math.floor(stats[k] * steal + 0.5)
		end
		add.Attack = (add.Attack or 0) - math.floor(stats.Attack * steal * TYRANT.StealAttack + 0.5)
		any = true
	end
	if extra and extra.grounded then
		-- Sovereign's Guard: a hitter grounded by a spike past GuardKmh, for their next attack
		for _, k in ipairs({ "Attack", "Jump" }) do
			add[k] = (add[k] or 0) - math.floor(stats[k] * TYRANT.GroundedCut + 0.5)
		end
		any = true
	end
	if on("Sunshine") and extra and extra.sunOn then
		-- Sunshine lit: every stat
		for _, k in ipairs({ "Attack", "Defense", "Speed", "Jump" }) do
			add[k] = (add[k] or 0) + SUNSHINE.SunAdd
		end
		any = true
	end
	if on("Sunshine") and extra and extra.digging then
		-- her digs are played with DigAdd on top
		for k, v in pairs(SUNSHINE.DigAdd) do
			add[k] = (add[k] or 0) + v
		end
		any = true
	end
	if on("Feral") and extra and extra.auto then
		-- the AI playing him (a bot, or a stand-in for an idle player) hits with less
		add.Attack = (add.Attack or 0) - math.floor(stats.Attack * (1 - FERAL.AutoAttackMul) + 0.5)
		any = true
	end
	if extra and extra.mods then
		-- a tournament's modifiers (Cups.statMods): stat points and height for everyone
		for k, v in pairs(extra.mods.add or {}) do
			add[k] = (add[k] or 0) + v
		end
		if (extra.mods.height or 0) ~= 0 then
			add.Height = (add.Height or 0) + extra.mods.height
		end
		any = true
	end
	local hex = extra and extra.hex
	if hex then
		-- the Halloween Match's cards that hit this character (Halloween.effects): stat points,
		-- height, and points for every point the other team has scored this set
		for k, v in pairs(hex.add) do
			add[k] = (add[k] or 0) + v
		end
		for k, v in pairs(Halloween.perPoint(hex, extra.enemyPoints) or {}) do
			add[k] = (add[k] or 0) + v
		end
		if hex.height ~= 0 then
			add.Height = (add.Height or 0) + hex.height
		end
		any = true
	end
	local mul = 1
	if hex and hex.mul ~= 1 then
		mul = mul * hex.mul
	end
	if extra and extra.teamBoost then
		-- (a number: the caller's grown Boost; on top of Monster Mash's, not in its place)
		mul = mul * (1 + (type(extra.teamBoost) == "number" and extra.teamBoost or RALLY.Boost))
		any = true
	end
	if on("Corona") then
		local k = HitLogic.coronaMul(extra and extra.coronaOn, extra and extra.coronaStacks, lv("Corona"))
		if k ~= 1 then
			mul = mul * k
			any = true
		end
	end
	if not any then
		return stats, false
	end
	return Characters.boosted(stats, add, mul), adrenaline
end

-- Vector Set: an attack off a teammate's pulsing set.
function HitLogic.vectorSet(ctx)
	local last = ctx.lastHit
	return last ~= nil and last.vectorSet == true and last.team == ctx.team and last.hitType == "Set"
end

-- Chain Reaction: an attack off a teammate's charged set explodes.
local function reaction(ctx)
	local last = ctx.lastHit
	return last ~= nil and last.charged == true and last.team == ctx.team and last.hitType == "Set"
end

local function meta0(action, q)
	return { hitType = action, quality = q, grade = HitLogic.grade(q), speed = 0, kmh = 0 }
end

local function finish(meta, v)
	meta.speed = v.Magnitude
	meta.kmh = HitLogic.kmh(v.Magnitude)
	return meta
end

local function launchResult(meta, p, v, a, t, hold)
	return true, {
		launch = BallPhysics.newLaunch(planar(p), planar(v), planar(a), t, hold),
		meta = finish(meta, planar(v)),
	}
end

-- A broken guard: the ball blasts off the receiver's arms and flies out behind them, landing
-- past their own end line (it never crosses the net).
local function blastOut(meta, ball, side, rng, t)
	local landing = C.SideDepth + SPM * (1.5 + rng:NextNumber() * 3.5)
	local target = Vector3.new(0, R, side * math.max(landing, ball.Z * side + SPM))
	local apex = ball.Y + SPM * (1.2 + rng:NextNumber() * 2.3)
	local v = HitLogic.solveArc(ball, target, apex, G)
	return launchResult(meta, ball, v, Vector3.new(0, -G, 0), t)
end

------------------------------------------------------------------------------------------
-- Touch rules
------------------------------------------------------------------------------------------

-- Returns ok, reason, isThirdTouch. Block touches never count.
function HitLogic.canTouch(touch, team, id, action, teamSize)
	if action == "Block" or action == "Toss" or action == "Serve" or action == "Underhand" then
		return true, nil, false
	end
	touch = touch or {}
	if touch.team ~= team then
		return true, nil, false
	end
	local count = touch.count or 0
	local double = touch.lastId == id and not touch.lastWasBlock and (teamSize or 3) > 1
	if count >= 3 then
		-- (your own ball again, say your serve still frozen at your hand by Zero Point, is a
		-- double touch, never the four-touch fault: the community saw "4 touches" spiking with
		-- Taeho, "usually on serves")
		return false, double and "double" or "count", false
	end
	if double then
		return false, "double", false
	end
	return true, nil, count == 2
end

-- The four-touch fault (the owner: "swinging for fourth ball should make you lose the point
-- similar to volleyball's four touches rule"): a touch refused because the team has used its
-- three (canTouch's "count") that a player still made on purpose (a swing, a roll shot or a set
-- that really met the ball) loses the rally. Receives are automatic, so they never fault.
local FAULT_ACTIONS = { Spike = true, Feint = true, Set = true }
function HitLogic.isFourthTouchFault(why, action)
	return why == "count" and FAULT_ACTIONS[action] == true
end

-- Which touch (1, 2 or 3) this team is about to make.
function HitLogic.touchNumber(touch, team)
	touch = touch or {}
	if touch.team ~= team then
		return 1
	end
	return (touch.count or 0) + 1
end

function HitLogic.nextTouch(touch, team, id, action)
	touch = touch or {}
	if action == "Block" then
		return { team = team, count = 0, lastId = id, lastWasBlock = true }
	end
	if action == "Serve" or action == "Underhand" then
		return { team = team, count = 3, lastId = id }
	end
	if action == "Toss" then
		return { count = 0 }
	end
	if touch.team ~= team then
		return { team = team, count = 1, lastId = id }
	end
	return { team = team, count = (touch.count or 0) + 1, lastId = id }
end

------------------------------------------------------------------------------------------
-- Attacks shared by spikes and jump serves
------------------------------------------------------------------------------------------

-- Where a hit lands, from the ball's position relative to the hand.
local function attackDepth(dz, qContact, rng, deepest, shortest)
	local t = clamp((dz - H.SpikeDzDeep) / (H.SpikeDzShort - H.SpikeDzDeep), 0, 1)
	local depth = lerp(deepest, shortest, t ^ 0.9)
	if dz < H.SpikeDzDeep then
		-- ball behind the head: it sails long unless you still met it cleanly
		depth = deepest + (H.SpikeDzDeep - dz) * 8 * (1 - qContact)
	end
	return depth + jitter(rng, (1 - qContact) ^ 1.5 * H.SpikeError)
end

-- Every spike and jump serve's speed past the soft cap: SpeedKnee and up counts SpeedOver, never
-- past SpeedMax (the owner, 2026-10-21: stacked buffs had Dante at 400 km/h).
function HitLogic.softCap(kmh)
	if kmh <= H.SpeedKnee then
		return kmh
	end
	return math.min(H.SpeedMax, H.SpeedKnee + (kmh - H.SpeedKnee) * H.SpeedOver)
end

-- ctx: the hitter's (nil: no ability, Talon Drop's plain power). zeroRange: Zero Point's km/h range
-- when the ball is in his sweet spot (it beats the lightning range: the base the rest multiplies)
local function attackPower(kind, q, qContact, heightM, stats, ctx, energy, zeroRange)
	local lo, hi = H.SpikeKmhMin, H.SpikeKmhMax
	local tlo, thi = H.ThunderKmhMin, H.ThunderKmhMax
	if kind == "JumpServe" then
		lo, hi = H.JumpServeKmhMin, H.JumpServeKmhMax
		tlo, thi = H.ThunderServeKmhMin, H.ThunderServeKmhMax
	end
	local kmh = lerp(lo, hi, q ^ 1.1) * stats.Power
	local thunder = has(ctx, "Thunder") and heightM >= H.ThunderHeight
	if thunder then
		local over = clamp((heightM - H.ThunderHeight) / H.ThunderHeightSpan, 0, 1)
		kmh = lerp(tlo, thi, qContact * 0.55 + over * 0.45) * stats.Power
	end
	if zeroRange then
		kmh = math.max(kmh, lerp(zeroRange[1], zeroRange[2], qContact) * stats.Power)
	end
	local overcharge, pierce = false, false
	if has(ctx, "Azure") then
		local e = clamp(energy or 0, 0, 1.4)
		if e > 1.02 then
			overcharge = true
			e = 1
		end
		energy = e
		kmh = kmh * (1 + ab("Azure", "MaxBoost", levelOf(ctx, "Azure")) * e ^ 1.2)
		pierce = e >= AZURE.PierceAt and not overcharge
	else
		energy = 0
	end
	return kmh, thunder, energy, overcharge, pierce
end

local function attack(kind, input, ctx, rng, stats, scale)
	local side = ctx.side
	local ball, root, t = input.ball, input.root, input.t
	if kind == "Spike" then
		-- (the widest of his abilities' reaches, each off its own input: Feral's leap gauge, and
		-- awakened Ironclad's Forge charge; Long Claws on top)
		local forge = has(ctx, "Ironclad") and ctx.awakened and (ctx.auto and IRON.AutoCharge or input.metal) or 0
		scale = scale * HitLogic.spikeReachAll(ctx.abilities or ctx.ability, input.gauge, forge) * (ctx.hex and ctx.hex.spikeReach or 1)
	end
	local ok, qContact, dz, dy = HitLogic.spikeZone(root, ball, side, stats, scale)
	if not ok then
		return false, "zone"
	end
	if ctx.forceQuality then
		qContact = ctx.forceQuality
	end
	local qHeight = HitLogic.heightQuality(ball.Y, stats, ctx.groundY)
	local qTop = qHeight
	-- the Tyrant's set (his team's): Absolute Toss meets it at full power, whatever the timing
	local lastSet = ctx.lastHit
	local tyrantSet = kind == "Spike" and lastSet ~= nil and lastSet.tyrantSet == true and lastSet.team == ctx.team and lastSet.hitType == "Set"
	local absolute = tyrantSet and lastSet.absolute == true
	if absolute then
		qContact, qHeight = 1, 1
	end -- (how near the top it really was: Skyward climbs off this, not a dive's floor)
	-- Sovereign Strike: while his Emperor's Dictate is on, the Tyrant's own attacks are met at full power
	local decree = (kind == "Spike" or kind == "JumpServe") and has(ctx, "Tyrant") and ctx.tyrantOn and true or false
	if decree then
		qContact, qHeight = 1, 1
	end
	-- Sundive (Corona): the further he dropped onto it (input.sundive, studs), the harder (the AI
	-- gets a share without diving); a dive meets the ball under the top of his jump, which doesn't
	-- cost him
	local dive = 0
	if (kind == "Spike" or kind == "JumpServe") and has(ctx, "Corona") then
		dive = ctx.auto and CORONA.AutoDive or HitLogic.diveFraction(input.sundive)
		if dive > 0 and not ctx.auto then
			qHeight = math.max(qHeight, CORONA.DiveHeightFloor)
		end
	end
	-- clean contact x good timing: a fingertip touch at a great height is still a poor hit
	local q = clamp(qContact * (H.ContactWeight + (1 - H.ContactWeight) * qHeight), 0, 1)
	-- the hitting point is the hand: a ball met above it still reads (and counts for Thunder) as
	-- this character's own top, so a short jumper can't reach 4.00 m off a high ball
	local heightM = HitLogic.meters(math.min(ball.Y, stats.contactMaxStuds))
	-- Thunder: Storm Call (ctx.stormOn) makes every spike a thunder spike, as if met at the very top
	-- of the range, and harder still; Static Charge (ctx.static: his thunder spikes this rally) adds
	-- StaticPer a stack
	local storm = (kind == "Spike" or kind == "JumpServe") and has(ctx, "Thunder") and ctx.stormOn == true
	-- Zero Point: the ball slightly in front of his raised hand and above his head makes his spike
	-- far faster, nearly straight and through the block (below)
	-- (his jump serves too, a little slower); its speed is the base every other boost multiplies
	local zero = (kind == "Spike" or kind == "JumpServe") and has(ctx, "ZeroPoint") and HitLogic.zeroSpot(dz, dy, stats) and ball.Y >= C.NetTop + H.SpikeMinContactOverNet
	local zeroRange = zero and (kind == "JumpServe" and ZERO.ZeroServeKmh or ab("ZeroPoint", "ZeroKmh", levelOf(ctx, "ZeroPoint"))) or nil
	local kmh, thunder, energy, overcharge, pierce = attackPower(kind, q, qContact, storm and (H.ThunderHeight + H.ThunderHeightSpan) or heightM, stats, ctx, input.energy, zeroRange)
	if storm then
		kmh = kmh * (1 + ab("Thunder", "StormBoost", levelOf(ctx, "Thunder")))
	end
	local static = 0
	if (kind == "Spike" or kind == "JumpServe") and has(ctx, "Thunder") then
		static = clamp(math.floor(tonumber(ctx.static) or 0), 0, THUNDER.StaticMax)
		kmh = kmh * (1 + ab("Thunder", "StaticPer", levelOf(ctx, "Thunder")) * static)
	end
	-- Thunder Spiker's second swing in one jump hits harder (input.second: the server counts the
	-- swings itself)
	local second = (kind == "Spike" or kind == "JumpServe") and has(ctx, "Thunder") and input.second == true
	if second then
		kmh = kmh * (1 + ab("Thunder", "SecondBoost", levelOf(ctx, "Thunder")))
	end
	if zero then
		-- the ball meets his hand: it holds there through the freeze frame and leaves from there
		-- (the owner saw him "swinging right below the ball" when it was met high in the spot)
		ball = Vector3.new(0, root.Y + Z.SpikeUp + ZERO.HandUp, root.Z - side * (Z.SpikeForward + ZERO.HandAhead))
	end
	local boom = kind == "Spike" and reaction(ctx)
	local link = HitLogic.chainStep(ctx.chain)
	if boom then
		kmh = kmh * ab("ChainReaction", "PowerMul", setLevel(ctx.lastHit, "ChainReaction"))[link] -- (the setter's breakthroughs)
	end
	-- Corona: the dive's power, and Zenith (only his spikes draw from the rng, so nobody else's
	-- hits change)
	if dive > 0 then
		kmh = kmh * (1 + CORONA.DiveBoost * dive)
	end
	if (kind == "Spike" or kind == "JumpServe") and has(ctx, "Corona") then
		kmh = kmh * (1 + ab("Corona", "SpikeBoost", levelOf(ctx, "Corona"))) -- Sunfire
	end
	local zenith = (kind == "Spike" or kind == "JumpServe") and has(ctx, "Corona") and rng:NextNumber() < CORONA.ZenithChance
	if zenith then
		kmh = kmh * (1 + CORONA.ZenithPower)
	end
	-- Featherfall: off her floating set, the longer the ball had been falling when it's met, the
	-- harder (the boost reads the set's own top time, so client and server agree)
	local feather = 0
	local last = ctx.lastHit
	if kind == "Spike" and last and last.featherSet == true and last.team == ctx.team and last.hitType == "Set" and tonumber(last.featherTop) then
		feather = clamp((t - last.featherTop) / FEATHER.FullFall, 0, 1)
		kmh = kmh * (1 + ab("Featherfall", "MaxBoost", setLevel(last, "Featherfall")) * feather)
	end
	-- Ironclad: Forge's charge (input.metal, 0..1, the time he's been up), all of it off a jump before
	-- his team's set (input.early), LateShare after; WallBoost with shields, MaxBoost awakened; the
	-- AI gets AutoCharge
	local metal = 0
	if kind == "Spike" and has(ctx, "Ironclad") then
		if ctx.auto then
			metal = IRON.AutoCharge
		else
			metal = clamp(tonumber(input.metal) or 0, 0, 1) * (input.early == true and 1 or IRON.LateShare)
		end
		kmh = kmh * (1 + ab("Ironclad", ctx.awakened and "MaxBoost" or "WallBoost", levelOf(ctx, "Ironclad")) * metal)
	end
	-- Squall: Eye of the Storm's hover charges the spike (input.gale, 0..1; the AI gets a share)
	local gale = 0
	if (kind == "Spike" or kind == "JumpServe") and has(ctx, "Squall") then
		gale = ctx.auto and SQUALL.AutoGale or clamp(tonumber(input.gale) or 0, 0, 1)
		kmh = kmh * (1 + ab("Squall", "SpikeBoost", levelOf(ctx, "Squall"))) * (1 + ab("Squall", "HoverBoost", levelOf(ctx, "Squall")) * gale) -- (Shear: every spike of hers harder)
	end
	local meta = meta0(kind, q)
	meta.height = heightM
	meta.contact = qContact
	meta.adrenaline = ctx.adrenaline or nil
	meta.tierDrain = HitLogic.tierDrain(stats.tier)
	if zero then
		meta.zero = true
		meta.grade = "PERFECT"
		meta.breakAtk = 999 -- through any block but Iron Wall's
		meta.tierDrain = meta.tierDrain * ZERO.DrainMul
	end
	if (kind == "Spike" or kind == "JumpServe") and has(ctx, "Skyward") then -- (serves climb her too)
		meta.liftGain = HitLogic.skyGain(qTop)
	end
	if boom then
		meta.reaction = true
		meta.drainMul = CHAIN.DrainMul[link]
		meta.flatDrain = CHAIN.FlatDrain[link]
		meta.chainLink = link
	end
	if dive > 0 and not ctx.auto then
		meta.dive = math.floor(dive * 100 + 0.5) / 100
	end
	meta.zenith = zenith or nil
	meta.storm = storm or nil
	meta.static = static > 0 and static or nil
	if feather > 0 then
		meta.feather = math.floor(feather * 100 + 0.5) / 100
	end
	if metal > 0 and not ctx.auto then
		meta.metal = math.floor(metal * 100 + 0.5) / 100
		meta.early = input.early == true or nil
		meta.forgeBoost = math.floor(ab("Ironclad", ctx.awakened and "MaxBoost" or "WallBoost", levelOf(ctx, "Ironclad")) * metal * 1000 + 0.5) / 1000
	end
	if gale > 0 and not ctx.auto then
		meta.gale = math.floor(gale * 100 + 0.5) / 100
	end
	meta.shear = (kind == "Spike" and has(ctx, "Squall")) or nil -- (her spikes fly wild off blocks)
	-- Dragon Surge: a full Azure bar costs the digger more
	if pierce then
		meta.tierDrain = meta.tierDrain * AZURE.FullDrainMul
	end
	meta.thunder = thunder or nil
	meta.secondSwing = second or nil
	meta.energy = energy > 0 and energy or nil
	meta.overcharge = overcharge or nil
	meta.pierce = pierce or nil

	local g = G * H.SpikeGravityScale
	if kind == "Spike" and ball.Y < C.NetTop + H.SpikeMinContactOverNet then
		-- too low to hit down: a weak roll over the tape
		q = math.min(q, 0.3)
		meta.quality, meta.grade = q, HitLogic.grade(q)
		meta.downBall = true
		meta.thunder, meta.pierce = nil, nil
		local target = Vector3.new(0, R, -side * SPM * (1.9 + rng:NextNumber() * 2.5))
		local v = arcWithAssist(ball, target, C.NetTop + 0.95 * SPM, G)
		return launchResult(meta, ball, v, Vector3.new(0, -G, 0), t)
	end

	local deepest = C.SideDepth - H.SpikeDeepMargin
	local shortest = H.SpikeShortDepth
	if kind == "JumpServe" then
		shortest = 2.8 * SPM
	end
	local depth = attackDepth(dz, qContact, rng, deepest, shortest)
	if qContact >= 0.75 then
		depth = math.min(depth, deepest)
	end
	-- Squall: a hover's spike goes as deep as it was charged (input.gale: none, just over the net; the
	-- whole charge, their back line), straying less than usual and more with a poor contact
	-- (an overcharge flies out whatever she charged)
	local hovered = (kind == "Spike" or kind == "JumpServe") and has(ctx, "Squall") and not overcharge and not ctx.auto and tonumber(input.gale) or nil
	if hovered then
		-- (in AimSteps spots, the last at the very back: never past their end line)
		local back = C.SideDepth - SQUALL.BackMargin
		depth = HitLogic.galeDepth(hovered, shortest, back) + jitter(rng, (1 - qContact) ^ 1.5 * H.SpikeError * SQUALL.AimError)
		depth = clamp(depth, shortest, C.SideDepth - 0.04 * SPM)
		meta.aimed = true
	end
	if overcharge then
		depth = C.SideDepth + SPM * (1.25 + rng:NextNumber() * 2.5)
	end
	-- Plunge Spin: high enough over the tape, the spike (or jump serve) shoots flat over the net and turns down
	-- just past it (below). One path a spike: an overcharge (out), then a Zero Point's laser, then a
	-- hover's aimed spot, then the plunge
	local plunge = (kind == "Spike" or kind == "JumpServe") and has(ctx, "Plunge") and not overcharge and not zero and not hovered
		and qContact >= PLUNGE.MinContact and ball.Y >= C.NetTop + PLUNGE.MinOverNet
	if plunge then
		kmh = kmh * (1 + ab("Plunge", "PowerBoost", levelOf(ctx, "Plunge")))
		meta.plunge = true
	end
	-- Sharp Angle (Skyward): Seora's spikes land a little shorter, so a little steeper
	if kind == "Spike" and has(ctx, "Skyward") and not overcharge and not hovered and not plunge and not zero then
		depth = math.max(shortest, depth * SKY.AngleDepthMul)
	end
	-- Vert Spikes (Sunshine): her spikes come down sharp, the steeper the line from the contact to
	-- where it lands the harder; the steepest go under the block (meta.underBlock, after the solve)
	local vert = kind == "Spike" and has(ctx, "Sunshine") and not overcharge and not hovered and not plunge and not zero
	if vert then
		depth = math.max(shortest, depth * SUNSHINE.VertDepthMul)
		local dropAngle = math.deg(math.atan(math.max(ball.Y - R, 0) / math.max(math.abs(depth + side * ball.Z), 1)))
		local k = clamp((dropAngle - SUNSHINE.VertAngle[1]) / (SUNSHINE.VertAngle[2] - SUNSHINE.VertAngle[1]), 0, 1)
		local boost = ab("Sunshine", "VertBoost", levelOf(ctx, "Sunshine")) * k
		kmh = kmh * (1 + boost)
		meta.vert = math.floor(boost * 1000 + 0.5) / 1000
	end
	local target = Vector3.new(0, R, -side * depth)
	-- Vector Set: off her set, the steeper the line from the contact to where it lands, the more
	-- power (a sharp, short spike gets the most)
	if kind == "Spike" and HitLogic.vectorSet(ctx) then
		local dropAngle = math.deg(math.atan(math.max(ball.Y - R, 0) / math.max(math.abs(target.Z - ball.Z), 1)))
		local k = clamp((dropAngle - VECTOR.AngleMin) / (VECTOR.AngleMax - VECTOR.AngleMin), 0, 1)
		local boost = ab("Vector", "MaxBoost", setLevel(ctx.lastHit, "Vector")) * k
		kmh = kmh * (1 + boost)
		meta.vector = true
		meta.vectorBoost = math.floor(boost * 1000 + 0.5) / 1000
	end
	-- Counter Edge: the meter's Attack is already in `stats`; the spike releases the meter on top
	if (kind == "Spike" or kind == "JumpServe") and has(ctx, "Counter") and (ctx.counter or 0) > 0 then
		local c = clamp(ctx.counter, 0, 100)
		kmh = kmh * (1 + ab("Counter", "ReleaseBoost", levelOf(ctx, "Counter")) * c / 100)
		meta.counterRelease = c
	end
	-- Feral Leap: the gauge his leap took off with powers the spike or the jump serve (input.gauge,
	-- 0..1, to OverMax with Bloodlust on: ctx.bloodlust). A full spike leaping at the net
	-- (input.toward) smashes through a block with less Attack than his (meta.breakAtk, read by the
	-- blocker's touch; serves are never blocked), and his first full one of the match
	-- (ctx.firstStrike: not used yet) hits harder still. Every spike and jump serve he hits in
	-- Bloodlust flies red (meta.bloodlust)
	local fullLeap = false
	if (kind == "Spike" or kind == "JumpServe") and has(ctx, "Feral") then
		local g = clamp(input.gauge or 0, 0, ctx.bloodlust and FERAL.OverMax or 1)
		local bonus = ctx.auto and FERAL.AutoBoostMul or 1 -- the AI gets less out of it
		if g > 0 then
			-- (past full the boost grows with the bar itself: 165% gives x (1 + MaxBoost x 1.65))
			kmh = kmh * (1 + ab("Feral", "MaxBoost", levelOf(ctx, "Feral")) * bonus * (g <= 1 and g ^ 1.2 or g))
			meta.gauge = math.floor(g * 100 + 0.5) / 100
		end
		if ctx.bloodlust then
			meta.bloodlust = true
		end
		-- (Bloodlust is one hit: the spike or jump serve his leap's charge powers ends it; one
		-- without a charge doesn't waste it. The owner, 2026-10-16: "after one hit, the ability is over")
		if ctx.bloodlust and g > 0 then
			meta.bloodlustSpent = true
		end
		if g >= FERAL.FullAt then
			fullLeap = true
			meta.fullLeap = true
			if input.toward and kind == "Spike" then
				meta.breakAtk = math.max(meta.breakAtk or 0, stats.Attack) -- (a Zero Point's 999 stays)
			end
			if ctx.firstStrike then
				kmh = kmh * (1 + FERAL.FirstBoost * bonus)
				meta.firstStrike = true
			end
		end
	end
	-- the Tyrant's Set: the spike off it goes SetMul faster, with Armor Break
	if tyrantSet then
		kmh = kmh * ab("Tyrant", "SetMul", setLevel(lastSet, "Tyrant"))
		meta.tyrant = true
		meta.armorBreak = true
		meta.absolute = absolute or nil
		if absolute then
			meta.grade = "PERFECT"
		end
	end
	-- Sovereign Strike: SelfMul faster, with Armor Break
	if decree then
		kmh = kmh * TYRANT.SelfMul
		meta.decree = true
		meta.armorBreak = true
		meta.grade = "PERFECT"
	end
	-- a custom match's modifiers: spike power, jump-serve power
	if ctx.mut then
		kmh = kmh * (kind == "JumpServe" and ctx.mut.serve or ctx.mut.spike)
	end
	-- the Halloween Match's cards: spike and jump serve power, and the drain the attack costs
	local hex = ctx.hex
	if hex then
		kmh = kmh * (kind == "JumpServe" and hex.serveMul or hex.spikeMul)
		meta.tierDrain = meta.tierDrain * hex.drainDeal
	end
	-- the soft cap: stacked boosts can't run away (Config.Hits.SpeedKnee)
	kmh = HitLogic.softCap(kmh)
	local steps = 0
	if q >= H.SpikeAssistQuality and not overcharge then
		steps = H.NetAssistSteps
	end
	local speed = HitLogic.studs(kmh)
	if kind == "JumpServe" then
		if has(ctx, "Tyrant") then
			-- the Crown Jump Serve: a little shorter, and it curls down steeply (heavy topspin)
			target = Vector3.new(0, R, -side * math.max(shortest, depth * TYRANT.CrownDepthMul))
			meta.crown = true
		end
		-- topspin: the serve dives. Pick the gravity that makes a flat hit land on target.
		local dist = math.max(math.abs(target.Z - ball.Z), 1)
		local flat = 2 * math.max(ball.Y - R, 1) * (speed / dist) ^ 2
		g = math.max(G * H.ServeGravityScale, flat * H.ServeTopspin)
		if meta.crown then
			g = g * TYRANT.CrownGravity
		end
	end
	-- the hit stop: a Zero Point's freeze frame first, then a first strike's, then a big hit's
	local hold = 0
	if zero then
		hold = ZERO.Freeze -- the freeze-frame cut-in
	elseif meta.firstStrike then
		hold = FERAL.FirstFreeze
	elseif thunder or pierce or fullLeap or zenith or dive >= 0.7 or gale >= 0.95 or metal >= 0.9 then
		hold = H.HitStopThunder
	elseif q >= H.PerfectAt then
		hold = H.HitStopPerfect
	elseif q >= H.GreatAt then
		hold = H.HitStopGreat
	end
	-- the turn and dive: Plunge Spin's, and Haesol's Vert Spikes (steeper and shorter: Sunshine's VertDive)
	local pd = plunge and PLUNGE or (vert and ball.Y >= C.NetTop + PLUNGE.MinOverNet and SUNSHINE.VertDive) or nil
	if pd then
		-- the turn: past the net, a little under the contact; from there it plunges
		-- to land where the contact sends it (below)
		-- met out in front it flies on and dives near their back line, met further back it turns
		-- down at once (Config.Abilities.Plunge)
		local front = clamp((dz - H.SpikeDzDeep) / (H.SpikeDzShort - H.SpikeDzDeep), 0, 1)
		local tan = math.tan(math.rad(lerp(pd.DiveAngleShort, pd.DiveAngleDeep, front)))
		local turnY = math.max(ball.Y - pd.TurnDrop, C.NetTop + pd.TurnOverNet)
		local land = lerp(pd.LandShort, pd.LandDeep or (deepest - pd.BackMargin), front) + (rng:NextNumber() - 0.5) * 0.5 * SPM
		local turnZ = land - (turnY - R) / tan
		if turnZ < pd.TurnMin then
			turnZ = pd.TurnMin
			land = turnZ + (turnY - R) / tan
		end
		local turn = Vector3.new(0, turnY, -side * turnZ)
		local g1 = G * pd.FlatGravity
		local v1 = HitLogic.solveSpeed(ball, turn, speed, g1)
		local tau = math.abs(turn.Z - ball.Z) / math.max(math.abs(v1.Z), 1)
		local down = Vector3.new(0, R, -side * land) - turn
		local v2 = down.Unit * speed * pd.DiveSpeed
		if vert then
			-- (under the block: the line from her hand to where it lands, as for any spike of hers)
			local angle = math.deg(math.atan(math.max(ball.Y - R, 0) / math.max(math.abs(land + side * ball.Z), 1)))
			meta.underBlock = angle >= SUNSHINE.UnderAngle or nil
			meta.vertDive = true
		end
		hold = math.max(hold, H.HitStopGreat) -- (never less than a great hit's)
		meta.turnAt = math.floor(tau * 1000 + 0.5) / 1000
		local ok, res = launchResult(meta, ball, v1, Vector3.new(0, -g1, 0), t, hold)
		res.launch.dive = { tau = tau, v = planar(v2), a = planar(Vector3.new(0, -G, 0)) }
		return ok, res
	end
	if zero then
		g = g * ZERO.Gravity -- a laser line
	end
	if zenith then
		g = g * CORONA.ZenithSpin -- heavy topspin: it dips harder onto the same spot
	end
	local v, _, landed = speedWithAssist(ball, target, speed, g, side, steps)
	if vert then
		-- the line it really takes (the net assist may have pushed it deeper)
		local angle = math.deg(math.atan(math.max(ball.Y - R, 0) / math.max(math.abs(landed.Z - ball.Z), 1)))
		meta.underBlock = angle >= SUNSHINE.UnderAngle or nil
	end
	return launchResult(meta, ball, v, Vector3.new(0, -g, 0), t, hold)
end

-- Talon Drop (Skyward's feint): a spike driven down over the net, nearly straight down right on
-- top of it and flatter the further back she is (TalonAngle out to TalonReach), never so steep it
-- can't clear the tape.
local function talon(input, ctx, rng, stats)
	local side = ctx.side
	local ball, root, t = input.ball, input.root, input.t
	local ok, qContact = HitLogic.spikeZone(root, ball, side, stats, 1)
	if not ok then
		return false, "zone"
	end
	if ctx.forceQuality then
		qContact = ctx.forceQuality
	end
	local qHeight = HitLogic.heightQuality(ball.Y, stats, ctx.groundY)
	local q = clamp(qContact * (H.ContactWeight + (1 - H.ContactWeight) * qHeight), 0, 1)
	local heightM = HitLogic.meters(math.min(ball.Y, stats.contactMaxStuds))
	local kmh = attackPower("Spike", q, qContact, heightM, stats, nil) * SKY.TalonPower -- (plain power: no lightning or charge)
	local meta = meta0("Spike", q)
	meta.talon = true
	meta.height = heightM
	meta.contact = qContact
	meta.tierDrain = HitLogic.tierDrain(stats.tier)
	meta.liftGain = HitLogic.skyGain(qHeight)
	if reaction(ctx) then
		-- (off a charged set it explodes like a spike, the setter's breakthroughs too)
		local link = HitLogic.chainStep(ctx.chain)
		kmh = kmh * ab("ChainReaction", "PowerMul", setLevel(ctx.lastHit, "ChainReaction"))[link]
		meta.reaction = true
		meta.drainMul = CHAIN.DrainMul[link]
		meta.flatDrain = CHAIN.FlatDrain[link]
		meta.chainLink = link
	end
	-- how far the ball is from the net on her side (studs; 0 or less: over it)
	local back = ball.Z * side
	local angle = lerp(SKY.TalonAngle[1], SKY.TalonAngle[2], clamp(back / SKY.TalonReach, 0, 1))
	if back > 0 then
		-- no steeper than the line that clears the tape (spare for the fall, more the further back)
		local rise = ball.Y - (C.NetTop + R + H.NetClearance + 0.3 + 0.15 * back)
		angle = math.max(math.min(angle, math.deg(math.atan(math.max(rise, 0) / back))), 8)
	end
	local a = math.rad(angle)
	local speed = HitLogic.studs(kmh)
	local v = Vector3.new(0, -math.sin(a) * speed, -side * math.cos(a) * speed)
	meta.talonAngle = math.floor(angle + 0.5)
	local g = G * H.SpikeGravityScale
	return launchResult(meta, ball, v, Vector3.new(0, -g, 0), t, H.HitStopGreat)
end

-- Turnabout: the armed set spins into a spike. High enough (a jump set) it's a real spike deep
-- into the other court; too low to hit down, a quick dump just over the tape.
local function turnabout(meta, ball, side, rng, t, stats, q, level)
	meta.hitType = "Spike"
	meta.turnabout = true
	meta.height = HitLogic.meters(ball.Y)
	meta.tierDrain = HitLogic.tierDrain(stats.tier)
	if ball.Y < C.NetTop + H.SpikeMinContactOverNet then
		meta.downBall = true
		local target = Vector3.new(0, R, -side * SPM * (1.6 + rng:NextNumber() * 1.6))
		local v = arcWithAssist(ball, target, C.NetTop + 0.8 * SPM, G)
		return launchResult(meta, ball, v, Vector3.new(0, -G, 0), t)
	end
	-- from right at the net: the first depth (from a mid-court aim, deeper) that clears the tape
	-- at this speed; if none does inside the court, a little slower
	local g = G * H.SpikeGravityScale
	local speed = HitLogic.studs(lerp(H.SpikeKmhMin, H.SpikeKmhMax, 0.55 + 0.35 * q) * stats.Power * ab("Turnabout", "PowerMul", level))
	local aim = C.SideDepth * (0.45 + 0.3 * rng:NextNumber())
	local deepest = C.SideDepth - H.SpikeDeepMargin
	for _ = 1, 8 do
		local depth = aim
		while depth <= deepest do
			local v = HitLogic.solveSpeed(ball, Vector3.new(0, R, -side * depth), speed, g)
			local m = HitLogic.netMargin(ball, v, g)
			if m and m >= H.NetClearance then
				return launchResult(meta, ball, v, Vector3.new(0, -g, 0), t, H.HitStopGreat)
			end
			depth = depth + 0.5 * SPM
		end
		speed = speed * 0.88
	end
	-- nothing clears at speed: a quick dump over instead
	meta.downBall = true
	local v = arcWithAssist(ball, Vector3.new(0, R, -side * aim), C.NetTop + 0.8 * SPM, G)
	return launchResult(meta, ball, v, Vector3.new(0, -G, 0), t)
end

------------------------------------------------------------------------------------------
-- compute(input, ctx) -> ok, result | reason
-- input: action, t, root, ball, vy, grounded, diving (slide), stanceAge, assist, energy,
--        setType, targetId, tossHeight, serveKind, aimDepth and aimHeight (a human setter's
--        aim, SetterAim), gauge and toward (Feral Leap: the leap's gauge, and whether it went
--        at the net)
-- ctx:   side, team, teamSize, seq, ballVel, lastHit, thirdTouch, touchNumber, stats,
--        ability (the character's own: its breakthroughs, breakLevel, grow it), abilities (the set
--        of every ability it plays, a Halloween card's at +0, its own included; nil: just
--        `ability`), groundY, stamina = { value, max } (own team), forceQuality?, ironWall?,
--        enemyPoints (Rising Sun), teamBoost (Rally Cry), counter (Counter Edge meter 0..100),
--        turnabout (Turnabout armed), firstStrike (Feral Leap's first full charge not used yet),
--        auto (played by the AI), chain (Chain Reaction: the team's explosions this rally),
--        coronaOn and coronaStacks (Corona: on, and how many times it's been used), bloodlust
--        (Feral Leap's Bloodlust on: the gauge may go past full)
------------------------------------------------------------------------------------------

function HitLogic.compute(input, ctx)
	local action = input.action
	local side = ctx.side
	-- (Sunshine: a first-touch receive of hers is played with DigAdd)
	ctx.digging = ((action == "Bump" or action == "Set") and (ctx.touchNumber or 1) == 1 and has(ctx, "Sunshine")) or nil
	local stats, adrenaline = HitLogic.effectiveStats(ctx.stats or Characters.stats(Config.DefaultTier), ctx.ability, ctx.stamina, ctx)
	ctx.adrenaline = adrenaline or nil
	local rng = Random.new(math.floor((ctx.seq or 0) * 7919 + (ACTION_CODE[action] or 0) * 104729 + 17))
	local root, ball, t = input.root, input.ball, input.t

	-- Serve toss ------------------------------------------------------------------------
	if action == "Toss" then
		local p, v, h, fwd = HitLogic.tossLaunch(root, side, input.tossHeight, input.tossForward, HitLogic.tossReach(ctx.abilities or ctx.ability))
		local meta = meta0("Toss", 1)
		meta.grade = "TOSS"
		meta.serveKind = h > H.TossLow + 0.5 and "Jump" or "Overhand"
		if fwd > 0 then
			meta.tossForward = fwd
		end
		return launchResult(meta, p, v, Vector3.new(0, -G, 0), t)
	end

	-- Underhand serve (the easy one) ---------------------------------------------------------
	-- Straight from the hand, no toss: a slow, high rainbow that always clears the net and
	-- lands well inside the other court. Easy to receive, too (no guard drain).
	if action == "Underhand" then
		if not input.grounded then
			return false, "grounded"
		end
		local p = Vector3.new(0, root.Y + 0.4, root.Z - side * 1.0)
		local depth = C.SideDepth * (H.UnderhandDepthMin + (H.UnderhandDepthMax - H.UnderhandDepthMin) * rng:NextNumber())
		local target = Vector3.new(0, R, -side * depth)
		local apex = C.NetTop + H.UnderhandApexOverNet + rng:NextNumber() * 0.4 * SPM
		local v = HitLogic.solveArc(p, target, apex, G)
		local meta = meta0("Underhand", 1)
		meta.grade = "EASY"
		meta.noDrain = true
		meta.height = HitLogic.meters(p.Y)
		return launchResult(meta, p, v, Vector3.new(0, -G, 0), t)
	end

	-- Serve ------------------------------------------------------------------------------
	if action == "Serve" then
		if not input.grounded then
			return attack("JumpServe", input, ctx, rng, stats, 1.1)
		end
		local ok, q = HitLogic.floatZone(root, ball, side)
		if not ok then
			return false, "zone"
		end
		if ctx.forceQuality then
			q = ctx.forceQuality
		end
		local meta = meta0("Overhand", q)
		meta.height = HitLogic.meters(ball.Y)
		local depth = C.SideDepth * (0.55 + 0.3 * rng:NextNumber()) + jitter(rng, (1 - q) * H.ServeError)
		depth = clamp(depth, 2.5 * SPM, C.SideDepth - 0.47 * SPM)
		local target = Vector3.new(0, R, -side * depth)
		local apex = C.NetTop + H.OverhandApexOverNet + rng:NextNumber() * 0.6 * SPM
		local v = arcWithAssist(ball, target, apex, G)
		return launchResult(meta, ball, v, Vector3.new(0, -G, 0), t)
	end

	-- Spike / feint -------------------------------------------------------------------------
	if action == "Spike" or action == "Feint" then
		if input.grounded then
			return false, "grounded"
		end
		if ball.Z * side < -0.12 * SPM then
			return false, "over"
		end
		if action == "Spike" then
			return attack("Spike", input, ctx, rng, stats, 1)
		end
		if has(ctx, "Skyward") then
			return talon(input, ctx, rng, stats) -- her feint is Talon Drop (before Azure's roll shot)
		end
		local ok, qContact, dz = HitLogic.spikeZone(root, ball, side, stats, 1.25)
		if not ok then
			return false, "zone"
		end
		if ctx.forceQuality then
			qContact = ctx.forceQuality
		end
		local meta = meta0("Feint", qContact)
		meta.noDrain = true
		meta.height = HitLogic.meters(ball.Y)
		if reaction(ctx) then
			-- a feint off a charged set still explodes: soft, but it tears through the guard
			local link = HitLogic.chainStep(ctx.chain)
			meta.noDrain = nil
			meta.reaction = true
			meta.drainMul = CHAIN.DrainMul[link]
			meta.flatDrain = CHAIN.FlatDrain[link]
			meta.chainLink = link
		end
		local frac = clamp((dz - H.SpikeDzDeep) / (H.SpikeDzShort - H.SpikeDzDeep), 0, 1)
		local depth = lerp(H.FeintMaxDepth, 0.95 * SPM, frac) + jitter(rng, (1 - qContact) * H.FeintError)
		-- a deep tip: the tip button held (input.tipDepth, 0..1) pushes it towards the back of the court
		local deep = clamp(tonumber(input.tipDepth) or 0, 0, 1)
		depth = lerp(depth, H.FeintDeepDepth, deep)
		meta.deepTip = deep > 0 and deep or nil
		local target = Vector3.new(0, R, -side * clamp(depth, 0.6 * SPM, math.max(H.FeintMaxDepth + 0.95 * SPM, H.FeintDeepDepth)))
		local g = G
		if has(ctx, "Azure") then
			g = G * 1.6 -- topspin roll shot: drops faster
		end
		local v = arcWithAssist(ball, target, math.max(ball.Y + 0.16 * SPM, C.NetTop + H.FeintApexOverNet) + H.FeintDeepLift * deep, g)
		return launchResult(meta, ball, v, Vector3.new(0, -g, 0), t)
	end

	-- Block -----------------------------------------------------------------------------------
	if action == "Block" then
		if ctx.mut and ctx.mut.noBlocks then
			return false, "off" -- (a custom match without blocking)
		end
		local last = ctx.lastHit
		-- Bulwark only in the air (the owner, 2026-10-21: "make taesan have to jump for his iron
		-- wall"): standing, his shields don't block
		local bulwark = ctx.ironclad == true and input.grounded ~= true
		-- (Sunshine lit: a bigger box; the Tyrant's Iron Fortress against this team: a lower one)
		local box = HitLogic.sunBox(Halloween.blockReach(HitLogic.wallReach(ctx.ironWall, bulwark, last and last.hitType), ctx.hex), has(ctx, "Sunshine") and ctx.sunOn)
		box = HitLogic.wallsBox(box, ctx.mut) -- (a custom match's Walls: higher hands)
		local ok, q, fingertips = HitLogic.blockBox(root, ball, side, stats, box, HitLogic.blockCut(ctx.dictated))
		if not ok then
			return false, "zone"
		end
		if not last or last.team == ctx.team then
			return false, "own"
		end
		if HitLogic.isServe(last.hitType) or last.hitType == "Toss" then
			return false, "serve"
		end
		if ctx.forceQuality then
			q = ctx.forceQuality
		end
		-- a feint floats over most blocks, Iron Wall's and Bulwark's too: now and then the hands
		-- reach it (FeintTouchChance x the block's quality), and then they only soften it (the same
		-- seeded roll on the client and the server)
		local feint = last.hitType == "Feint" and not last.reaction
		if feint and rng:NextNumber() >= H.FeintTouchChance * clamp(q, 0, 1) then
			return false, "feint"
		end
		local inc = ctx.ballVel or Vector3.new(0, 0, side * 9.4 * SPM)
		local attackKmh = last.kmh or HitLogic.kmh(inc.Magnitude)
		local power, over = 0, 0
		if last.hitType == "Spike" then
			power = clamp((attackKmh - 60) / 140, 0, 1)
			over = clamp((attackKmh - H.BlockOverKmh[1]) / (H.BlockOverKmh[2] - H.BlockOverKmh[1]), 0, 1)
		end
		-- (a spike past BlockOverKmh[1] keeps getting harder to stop, and isn't a soft touch: below)
		local hard = last.hitType == "Spike" and attackKmh >= H.BlockOverKmh[1]
		local stuffScore = q - 0.42 * power - H.BlockOverStuff * over + (ctx.hex and ctx.hex.stuff or 0)
		if last.pierce or last.armorBreak then
			stuffScore = math.min(stuffScore, 0.3) -- (the Tyrant's Set's Armor Break too)
		end
		-- Shear (Haneul's spike): harder to stuff (only the stuff check moves: a touch that would be
		-- soft stays soft unless the wild roll below takes it), and wild off the hands
		local shear = last.shear == true and last.hitType == "Spike"
		local shearDrop = shear and SQUALL.ShearStuffDrop or 0
		-- Feral Leap: a full-gauge spike leaping at the net smashes through a blocker with less
		-- Attack than the attacker had
		local smash = last.hitType == "Spike" and type(last.breakAtk) == "number" and last.breakAtk > stats.Attack
		-- Ironclad's Bulwark (ctx.ironclad: he has shields) is Iron Wall for his 3 lives (the owner,
		-- 2026-10-15): the same whole wall and perfect shut-down, tips and the hardest spikes
		-- included; each stop cracks a shield instead (HitLogic.ironAfterBlock)
		local perfect = (ctx.ironWall or bulwark) and not feint
		if last.underBlock and not perfect then
			return false, "under" -- Vert Spikes: the steepest slip under the hands (a perfect block still stops it)
		end
		if perfect then
			-- Iron Wall: a perfect block, whatever reaches the hands (pierce, thunder and a Feral
			-- smash included), wherever it meets them
			stuffScore = 1
			q = 1
			smash = false
		end
		local atk = -side
		local meta = meta0("Block", clamp(q, 0, 1))
		meta.attackKmh = attackKmh
		meta.ironWall = perfect or nil
		meta.bulwark = (bulwark and not ctx.ironWall) or nil -- (Bulwark's block: its stops crack a shield)
		local p, v, a, hold = nil, nil, nil, 0
		if feint then
			-- a light touch: the feint slowed, dropping on the blockers' side for them to play (never a
			-- stuff, and no Bulwark shield cracks on it: meta.ironWall stays off)
			meta.outcome = "Soft"
			meta.noDrain = true
			meta.feintTouch = true
			p = Vector3.new(0, ball.Y, side * (R + 0.1))
			v = Vector3.new(0, SPM * (2.2 + 1.2 * rng:NextNumber()), side * SPM * (1.2 + rng:NextNumber()))
			a = Vector3.new(0, -G, 0)
		elseif smash then
			-- through the hands and on down into the blockers' court, barely slowed: still a spike
			-- to dig (isHeavy), and the attacker's point if it lands (MatchService.judge)
			meta.outcome = "Break"
			meta.breakThrough = true
			meta.tierDrain = last.tierDrain
			p = Vector3.new(0, ball.Y, side * (R + 0.1))
			local vin = planar(inc)
			if vin.Z * side < 2.5 * SPM then
				vin = Vector3.new(0, math.min(vin.Y, -2 * SPM), side * 18 * SPM)
			end
			v = vin * FERAL.BreakKeep
			a = Vector3.new(0, -G * H.SpikeGravityScale, 0)
			hold = 0.06
		elseif perfect and meta.bulwark and (attackKmh >= ab("Ironclad", "ShatterKmh", levelOf(ctx, "Ironclad")) or (tonumber(ctx.ironCracks) or 0) + 1 >= IRON.CracksToBreak) then
			-- Bulwark's stop that shatters a shield (its last crack, or a ShatterKmh spike at once): the
			-- ball pops straight up on his side, an easy ball for his team
			meta.outcome = "Soft"
			meta.shatter = true
			meta.noDrain = true
			p = Vector3.new(0, math.max(ball.Y, C.NetTop + R), side * (R + 0.1))
			v = Vector3.new(0, SPM * lerp(IRON.PopUp[1], IRON.PopUp[2], rng:NextNumber()), side * SPM * IRON.PopBack)
			a = Vector3.new(0, -G, 0)
			hold = H.HitStopPerfect
		elseif perfect then
			-- the perfect shut-down: straight down onto their court just past the net, always in
			meta.outcome = "Stuff"
			meta.perfectBlock = true
			local IW = Config.Abilities.IronWall
			p = Vector3.new(0, math.max(ball.Y, C.NetTop + R), atk * (R + 0.1))
			local depth = SPM * lerp(IW.StuffDepth[1], IW.StuffDepth[2], rng:NextNumber())
			v = HitLogic.solveSpeed(p, Vector3.new(0, R, atk * depth), HitLogic.studs(ab("IronWall", "StuffKmh", levelOf(ctx, "IronWall"))), G * 1.3)
			a = Vector3.new(0, -G * 1.3, 0)
			hold = H.HitStopPerfect
		elseif stuffScore - shearDrop >= 0.45 then
			meta.outcome = "Stuff"
			p = Vector3.new(0, ball.Y, atk * (R + 0.1))
			v = Vector3.new(0, -SPM * (4.4 + 5 * q), atk * SPM * (3.1 + 4.4 * q))
			a = Vector3.new(0, -G * 1.3, 0)
			hold = 0.05
		elseif shear and rng:NextNumber() < SQUALL.ShearToolChance then
			-- Shear: off the hands and out, the attacker's point (not a touch they can play)
			local pw = math.max(power, 0.6)
			meta.outcome = "Tool"
			meta.noDrain = true
			meta.wild = true
			p = Vector3.new(0, ball.Y, side * (R + 0.1))
			v = Vector3.new(0, SPM * (4.4 + 1.9 * pw), side * SPM * (8.75 + 4.4 * pw))
			a = Vector3.new(0, -G, 0)
		elseif hard then
			-- a 200+ km/h spike the block didn't stuff: straight through it (more often the harder it
			-- is), or off the hands and out; never a soft touch they can play
			local inc2 = planar(inc)
			if not fingertips and rng:NextNumber() < lerp(H.BlastChance[1], H.BlastChance[2], over) then
				meta.outcome = "Break"
				meta.breakThrough = true
				meta.blast = true
				meta.tierDrain = last.tierDrain
				p = Vector3.new(0, ball.Y, side * (R + 0.1))
				if inc2.Z * side < 2.5 * SPM then
					inc2 = Vector3.new(0, math.min(inc2.Y, -2 * SPM), side * 18 * SPM)
				end
				v = inc2 * H.BlastKeep
				a = Vector3.new(0, -G * H.SpikeGravityScale, 0)
				hold = 0.04
			else
				local pw = math.max(power, 0.8)
				meta.outcome = "Tool"
				meta.noDrain = true
				p = Vector3.new(0, ball.Y, side * (R + 0.1))
				v = Vector3.new(0, SPM * (4.4 + 1.9 * pw), side * SPM * (8.75 + 4.4 * pw))
				a = Vector3.new(0, -G, 0)
			end
		elseif stuffScore >= 0.18 then
			meta.outcome = "Soft"
			meta.noDrain = true
			p = Vector3.new(0, ball.Y, side * (R + 0.1))
			v = Vector3.new(0, SPM * (3.1 + 1.9 * q), side * SPM * (1.9 + 1.25 * rng:NextNumber()))
			a = Vector3.new(0, -G, 0)
		elseif fingertips and power > 0.5 then
			meta.outcome = "Tool"
			meta.noDrain = true
			p = Vector3.new(0, ball.Y, side * (R + 0.1))
			v = Vector3.new(0, SPM * (4.4 + 1.9 * power), side * SPM * (8.75 + 4.4 * power))
			a = Vector3.new(0, -G, 0)
		else
			meta.outcome = "Touch"
			meta.noDrain = true
			p = Vector3.new(0, ball.Y, side * (R + 0.1))
			v = Vector3.new(0, math.abs(inc.Y) * 0.2 + 2.5 * SPM, side * math.max(math.abs(inc.Z) * 0.35, 2.5 * SPM))
			a = Vector3.new(0, -G, 0)
		end
		return launchResult(meta, p, v, a, t, hold)
	end

	-- Receive / set ---------------------------------------------------------------------------
	if action == "Bump" or action == "Set" then
		local sliding = input.diving == true and not ctx.dictated -- (Locked by the Tyrant's Dictate: no slides)
		local isSet = action == "Set"
		local touchN1 = (ctx.touchNumber or 1) == 1
		local overhead = false
		local ok, q = false, 0
		if not sliding then
			ok, q = HitLogic.setZone(root, ball, side, stats)
			overhead = ok
			if ok and not isSet and ball.Y - root.Y < Z.SetMinY + 0.8 then
				-- a receive pressed on a chest-high ball stays a forearm pass
				local ok2, q2 = HitLogic.receiveZone(root, ball, side, stats, false, touchN1 and HitLogic.digReach(ctx) or nil)
				if ok2 then
					ok, q, overhead = ok2, q2, false
				end
			end
		end
		if not ok then
			ok, q = HitLogic.receiveZone(root, ball, side, stats, sliding, touchN1 and HitLogic.digReach(ctx) or nil)
			overhead = false
		end
		if not ok then
			return false, "zone"
		end
		if ctx.forceQuality then
			q = ctx.forceQuality
		end

		local touchN = ctx.touchNumber or 1
		local last = ctx.lastHit
		local heavy = touchN == 1 and HitLogic.isHeavy(last)
		local incomingKmh = HitLogic.kmh(((ctx.ballVel or Vector3.zero)).Magnitude)

		-- timing: a receive pressed a little early is ideal
		local qTime = 1
		if not sliding and not input.assist and not overhead then
			local age = input.stanceAge or 0.25
			local pMin, pMax = HitLogic.perfectStance(ctx) -- (Sunshine: far wider)
			if age < pMin then
				qTime = 0.75 + (age / pMin) * 0.25
			elseif age > pMax then
				qTime = clamp(1 - (age - pMax) / 0.5, 0.45, 1)
			end
		end
		q = clamp(q * 0.62 + qTime * 0.38 + stats.ReceiveBonus, 0, 1)
		if heavy then
			q = applyIncoming(q, incomingKmh)
		end
		if input.assist then
			q = math.min(q, H.AssistQualityCap)
		end
		if sliding then
			q = math.max(q, H.SlideQualityFloor)
		end

		local meta = meta0("Bump", q)
		meta.overhead = overhead or nil
		meta.slide = sliding or nil
		meta.height = HitLogic.meters(ball.Y)

		-- stamina (guard) -------------------------------------------------------------
		local stam = ctx.stamina or { value = 1, max = 1 }
		local pct = 1
		if stam.max > 0 then
			pct = clamp(stam.value / stam.max, 0, 1)
		end
		local perfect = heavy and not sliding and q >= (has(ctx, "Sunshine") and SUNSHINE.PerfectAt or H.PerfectAt)
		local drain = 0
		-- a feint dug (not an exploding one: that's heavy): FeintDrain, and with the guard at
		-- FeintBreakAt or lower it breaks it (the owner: "faints ... break stamina when they are low")
		local feint = last ~= nil and last.team ~= ctx.team and last.hitType == "Feint" and not heavy
		if feint and stam.max > 0 then
			drain = pct <= H.FeintBreakAt and (stam.value + 1) or H.FeintDrain
			if ctx.hex then
				drain = drain * ctx.hex.drainTake
			end
		end
		if heavy then
			drain = HitLogic.drainFor(incomingKmh, stats) * (last.tierDrain or 1)
			if sliding then
				drain = drain * H.SlideDrainMul
			end
			if last.reaction then
				drain = drain * (last.drainMul or 1)
			end
			if last.crown then
				drain = drain * TYRANT.CrownDrainMul -- the Crown Jump Serve
			end
			if perfect then
				drain = drain * HitLogic.perfectDrainMul(incomingKmh)
			end
			if ctx.hex then
				drain = drain * ctx.hex.drainTake -- (the Halloween Match's cards)
			end
			if last.reaction then
				-- the explosion itself: no timing saves you from it, and it always breaks the guard
				-- (the owner: "chain reaction spikes should always break stamina")
				drain = math.max(drain + (last.flatDrain or 0), stam.value + 1)
			end
		end
		if has(ctx, "Counter") and touchN == 1 and last and last.team ~= ctx.team then
			-- Counter Edge: any ball of theirs she digs fills the meter; a hard spike fills it most
			-- (blades burst out and sink back in) and costs only SpikeDrainMul of the guard (the
			-- owner: "she should have very high defense but no invincible"); a Chain Reaction's
			-- explosion costs her the full drain ("chain reaction should still be able to
			-- completely deplete stamina")
			if heavy then
				meta.counterGain = clamp(incomingKmh * COUNTER.GainPerKmh, COUNTER.MinGain, COUNTER.MaxGain)
				if not last.reaction then
					drain = drain * COUNTER.SpikeDrainMul
				end
			else
				meta.counterGain = COUNTER.LightGain
			end
		end
		if ctx.mut then
			drain = drain * ctx.mut.drain -- (a custom match's Stamina, feints and explosions too: 0 never breaks)
		end
		meta.drain = drain > 0 and drain or nil
		meta.perfect = perfect or nil
		meta.sunshine = (perfect and has(ctx, "Sunshine")) or nil -- (a perfect dig of hers lights Sunshine)
		meta.dig = (ctx.digging and not sliding) or nil -- (her sun aura)
		-- a heavy ball knocks the receiver back (0..1), unless they slid
		if heavy and not sliding then
			local knock = clamp((incomingKmh - ST.KnockFromKmh) / 90, 0, 1)
			meta.knock = knock > 0 and knock or nil
		end

		if heavy and stam.value <= 0 and (incomingKmh >= ST.BreakFailKmh or last.reaction) then
			-- guard broken: the spike blasts straight off the arms and out behind
			meta.fail = true
			meta.grade = "BROKEN"
			meta.quality = 0
			meta.score = 0
			meta.knock = 1
			return blastOut(meta, ball, side, rng, t)
		end
		if heavy and not sliding and pct < ST.RedAt then
			local k = ST.LowQualityFloor + (1 - ST.LowQualityFloor) * (pct / ST.RedAt)
			q = q * k
		end
		if (heavy or feint) and stam.value > 0 and stam.value - drain <= 0 then
			-- this ball breaks the guard: it blasts off the arms and flies out behind the receiver
			meta.breaks = true
			meta.quality = 0
			meta.grade = "BROKEN"
			meta.score = 0
			meta.knock = 1
			return blastOut(meta, ball, side, rng, t)
		end
		meta.quality, meta.grade = q, HitLogic.grade(q)
		if meta.perfect then
			meta.grade = "PERFECT"
		end
		meta.score = math.floor(q * 100 + 0.5)

		-- Turnabout: an armed set spins into a spike over the net instead
		-- (before any set ability: the press armed it)
		if ctx.turnabout and has(ctx, "Turnabout") and touchN == 2 and not ctx.thirdTouch then
			return turnabout(meta, ball, side, rng, t, stats, q, levelOf(ctx, "Turnabout"))
		end

		-- third touch: the only touch that goes over
		if ctx.thirdTouch then
			meta.hitType = "Free"
			meta.free = true
			local target = Vector3.new(0, R, -side * SPM * (3.75 + rng:NextNumber() * 3.1))
			local apex = math.max(ball.Y + 0.6 * SPM, C.NetTop + H.FreeBallApexOverNet)
			local v = arcWithAssist(ball, target, apex, G)
			return launchResult(meta, ball, v, Vector3.new(0, -G, 0), t)
		end

		-- shank: off the arms, roughly where the ball was already going
		if q < H.ShankAt then
			meta.shank = true
			local vz = (ctx.ballVel or Vector3.zero).Z
			local dir = side
			if vz * side < 0 then
				dir = -side
			end
			local dist = SPM * (1.25 + (H.ShankAt - q) / H.ShankAt * 3.75 * (0.5 + rng:NextNumber()))
			local tz = ball.Z + dir * dist
			if tz * side < 0.47 * SPM then
				tz = side * 0.47 * SPM
			end
			local apex = math.max(ball.Y + 0.6 * SPM, SPM * (2.2 + rng:NextNumber() * 2.8))
			local v = nil
			if tz * side > 0 then
				v = ownSideArc(ball, Vector3.new(0, R, tz), apex, G, side, 0.38 * SPM)
			else
				v = arcWithAssist(ball, Vector3.new(0, R, tz), apex, G)
			end
			return launchResult(meta, ball, v, Vector3.new(0, -G, 0), t)
		end

		-- second touch, or an explicit set: set the attacker
		if isSet or touchN == 2 then
			local setType = input.setType
			if setType ~= "Quick" and setType ~= "Back" then
				setType = "Open"
			end
			local underhand = not overhead
			meta.hitType = "Set"
			meta.setType = setType
			meta.dotted = true
			-- (every set ability she plays at once: Vector's spot and lift feed Featherfall's float, and
			-- Chain Reaction charges it; never in 1v1, where she'd set herself, the owner, 2026-10-16:
			-- "disable chain reaction in 1v1s")
			meta.charged = (has(ctx, "ChainReaction") and (ctx.teamSize or 3) > 1) or nil
			meta.setBreak = (tonumber(ctx.breakLevel) or 0) > 0 and Breakthrough.level(ctx.breakLevel) or nil -- (Chain Reaction, Vector, Featherfall grow with it)
			meta.setBreakFor = meta.setBreak and ctx.ability or nil -- (her own ability's: setLevel)
			meta.vectorSet = has(ctx, "Vector") or nil -- the pulsing ball
			-- the Tyrant's Set: every set of his (the spike off it: SetMul and Armor Break); Absolute
			-- Toss while his Emperor's Dictate is on (the spike off it at full power)
			meta.tyrantSet = has(ctx, "Tyrant") or nil
			meta.absolute = (has(ctx, "Tyrant") and ctx.tyrantOn) or nil
			meta.underhand = underhand or nil
			if type(input.targetId) == "string" then
				meta.targetId = input.targetId
			end
			local accuracy = stats.SetAccuracy
			if underhand then
				accuracy = accuracy * 0.55
			end
			-- a human setter's aim picks the spot (the same error as any set)
			local aimed = type(input.aimDepth) == "number" and input.aimDepth == input.aimDepth
			local base = Court.attackDepth(setType)
			if aimed then
				base = clamp(input.aimDepth, H.SetAimMin, H.SetAimMax)
				meta.aimed = true
			end
			-- off a pass the Crown Jump Serve wrecked: it strays more and comes down lower
			local crowned = last ~= nil and last.crowned == true and last.team == ctx.team
			local depth = base + jitter(rng, (1 - q) ^ 1.4 * H.SetError / accuracy)
			if crowned then
				depth = depth + jitter(rng, TYRANT.CrownSetError)
			end
			-- a jump set (taken above standing height) goes up higher too; quicks stay quick
			local lift = 0
			if setType ~= "Quick" then
				lift = math.max(0, ball.Y - ((ctx.groundY or Config.Player.RootGround) + Z.SetIdealY))
				if has(ctx, "Vector") and not aimed then
					-- Vector Set: tight to the net and high, for the steepest spike
					depth = depth * VECTOR.SetDepthMul
					lift = lift + VECTOR.SetLift
				end
			end
			local arriveY = nil
			if aimed and type(input.aimHeight) == "number" and input.aimHeight == input.aimHeight then
				arriveY = clamp(input.aimHeight, H.SetAimLowY, H.SetAimHighY)
			end
			if crowned then
				arriveY = (arriveY or H.SetArriveY) - TYRANT.CrownSetLow
				lift = 0
				meta.crowned = true
			end
			if has(ctx, "Featherfall") and setType ~= "Quick" then
				-- Featherfall: up higher, then floating down from the top (lighter gravity) to the same
				-- spot; the spike off it reads how long it has been falling from meta.featherTop
				local g = G * H.SetGravityScale
				local arrive = arriveY or H.SetArriveY
				local apexY = (setType == "Back" and H.SetApexBack or H.SetApexOpen) + lift + (arrive - H.SetArriveY) + FEATHER.ExtraApex
				apexY = math.min(math.max(apexY, ball.Y + 0.38 * SPM, arrive + 0.5 * SPM), C.CeilingY - R - 0.5)
				local vy = math.sqrt(2 * g * math.max(apexY - ball.Y, 0.1))
				local rise = vy / g
				local gf = g * FEATHER.FallGravity
				local fall = math.sqrt(2 * math.max(apexY - arrive, 0.1) / gf)
				local vz = (side * math.max(depth, 0.47 * SPM) - ball.Z) / (rise + fall)
				meta.featherSet = true
				meta.featherTop = math.floor((t + rise) * 1000 + 0.5) / 1000
				local okF, res = launchResult(meta, ball, Vector3.new(0, vy, vz), Vector3.new(0, -g, 0), t)
				res.launch.dive = { tau = rise, v = planar(Vector3.new(0, 0, vz)), a = planar(Vector3.new(0, -gf, 0)) }
				return okF, res
			end
			local v, g = HitLogic.setArc(ball, side, setType, depth, underhand, lift, arriveY, meta.tyrantSet and setType ~= "Quick")
			return launchResult(meta, ball, v, Vector3.new(0, -g, 0), t)
		end

		-- first touch: a high pass to the setter (or up in front of yourself when solo)
		if heavy and last.crown then
			-- the Crown Jump Serve: the pass goes low and wide, and the set off it too (meta.crowned)
			q = q * TYRANT.CrownPassMul
			meta.crowned = true
			meta.quality, meta.score = q, math.floor(q * 100 + 0.5)
			if not meta.perfect then
				meta.grade = HitLogic.grade(q)
			end
		end
		local depth = H.SetterDepth
		if (ctx.teamSize or 3) <= 1 then
			depth = clamp(math.abs(root.Z) - 1.6 * SPM, 1.25 * SPM, 3.75 * SPM)
		end
		local err = (1 - q) ^ 1.3 * H.PassError
		local apex = lerp(H.PassApexMin, H.PassApexMax, q)
		if sliding then
			depth = depth + H.SlidePassDrift * SPM
			err = err + H.SlidePassDrift * SPM
			apex = H.SlidePassApex
		end
		depth = math.max(depth + jitter(rng, err), 0.56 * SPM)
		apex = math.max(apex, ball.Y + 0.3 * SPM)
		local g = G * H.PassGravityScale
		local v = ownSideArc(ball, Vector3.new(0, H.PassArriveY, side * depth), apex, g, side, 0.38 * SPM)
		return launchResult(meta, ball, v, Vector3.new(0, -g, 0), t)
	end

	return false, "action"
end

return HitLogic
