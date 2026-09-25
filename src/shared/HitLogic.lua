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
-- Receives drain the receiving team's stamina (a guard meter) depending on ball speed and the
-- receiver's Defense. Low stamina makes receives unreliable; a broken guard can't stop strong
-- spikes at all. Slides never drain stamina.

local Config = require(script.Parent.Config)
local Court = require(script.Parent.Court)
local BallPhysics = require(script.Parent.BallPhysics)
local Characters = require(script.Parent.Characters)

local HitLogic = {}

local C, Z, H, ST = Config.Court, Config.Zones, Config.Hits, Config.Stamina
local R, G = Config.Ball.Radius, Config.Ball.Gravity
local SPM = Config.Scale.StudsPerMeter
local AZURE = Config.Abilities.Azure

local ACTION_CODE = { Bump = 1, Set = 2, Spike = 3, Feint = 4, Block = 5, Toss = 6, Serve = 7 }
local SERVES = { JumpServe = true, Overhand = true }

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

function HitLogic.receiveZone(root, ball, side, stats, sliding)
	local reachMul = (stats and stats.Reach) or 1
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

-- Block: hands above the tape, reaching over the net. Returns ok, quality, fingertips.
function HitLogic.blockBox(root, ball, side, stats)
	if math.abs(root.Z) > Z.BlockNetDistance then
		return false, 0, false
	end
	local zs = ball.Z * side
	if zs > Z.BlockOwnDepth or zs < -Z.BlockOverDepth then
		return false, 0, false
	end
	local top = root.Y + Z.BlockReachUp
	if ball.Y > top + R or ball.Y < C.NetTop - 0.6 then
		return false, 0, false
	end
	local qy = clamp((top + R - ball.Y) / 2.4, 0, 1)
	local qz = falloff(math.abs(zs - 0.1) / (Z.BlockOwnDepth + R), 1.3)
	local q = clamp((qy * 0.5 + qz * 0.5) * ((stats and stats.BlockPower) or 1), 0, 1.15)
	return true, q, (top + R - ball.Y) < 0.9
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

-- The share of the drain a perfectly timed receive still pays.
function HitLogic.perfectDrainMul(kmh)
	local t = clamp((kmh - ST.PerfectMulFromKmh) / (ST.PerfectMulToKmh - ST.PerfectMulFromKmh), 0, 1)
	return lerp(ST.PerfectDrainMul, ST.PerfectDrainMulMax, t)
end

function HitLogic.isHeavy(lastHit)
	if not lastHit or lastHit.noDrain then
		return false
	end
	local ht = lastHit.hitType
	return ht == "Spike" or ht == "JumpServe" or ht == "Overhand"
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

------------------------------------------------------------------------------------------
-- Touch rules
------------------------------------------------------------------------------------------

-- Returns ok, reason, isThirdTouch. Block touches never count.
function HitLogic.canTouch(touch, team, id, action, teamSize)
	if action == "Block" or action == "Toss" or action == "Serve" then
		return true, nil, false
	end
	touch = touch or {}
	if touch.team ~= team then
		return true, nil, false
	end
	local count = touch.count or 0
	if count >= 3 then
		return false, "count", false
	end
	if touch.lastId == id and not touch.lastWasBlock and (teamSize or 3) > 1 then
		return false, "double", false
	end
	return true, nil, count == 2
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
	if action == "Serve" then
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

local function attackPower(kind, q, qContact, heightM, stats, ability, energy)
	local lo, hi = H.SpikeKmhMin, H.SpikeKmhMax
	local tlo, thi = H.ThunderKmhMin, H.ThunderKmhMax
	if kind == "JumpServe" then
		lo, hi = H.JumpServeKmhMin, H.JumpServeKmhMax
		tlo, thi = H.ThunderServeKmhMin, H.ThunderServeKmhMax
	end
	local kmh = lerp(lo, hi, q ^ 1.1) * stats.Power
	local thunder = ability == "Thunder" and heightM >= H.ThunderHeight
	if thunder then
		local over = clamp((heightM - H.ThunderHeight) / H.ThunderHeightSpan, 0, 1)
		kmh = lerp(tlo, thi, qContact * 0.55 + over * 0.45) * stats.Power
	end
	local overcharge, pierce = false, false
	if ability == "Azure" then
		local e = clamp(energy or 0, 0, 1.4)
		if e > 1.02 then
			overcharge = true
			e = 1
		end
		energy = e
		kmh = kmh * (1 + AZURE.MaxBoost * e ^ 1.2)
		pierce = e >= AZURE.PierceAt and not overcharge
	else
		energy = 0
	end
	return kmh, thunder, energy, overcharge, pierce
end

local function attack(kind, input, ctx, rng, stats, scale)
	local side = ctx.side
	local ball, root, t = input.ball, input.root, input.t
	local ok, qContact, dz = HitLogic.spikeZone(root, ball, side, stats, scale)
	if not ok then
		return false, "zone"
	end
	if ctx.forceQuality then
		qContact = ctx.forceQuality
	end
	local qHeight = HitLogic.heightQuality(ball.Y, stats, ctx.groundY)
	-- clean contact x good timing: a fingertip touch at a great height is still a poor hit
	local q = clamp(qContact * (H.ContactWeight + (1 - H.ContactWeight) * qHeight), 0, 1)
	local heightM = HitLogic.meters(ball.Y)
	local kmh, thunder, energy, overcharge, pierce = attackPower(kind, q, qContact, heightM, stats, ctx.ability, input.energy)
	local meta = meta0(kind, q)
	meta.height = heightM
	meta.contact = qContact
	meta.thunder = thunder or nil
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
	if overcharge then
		depth = C.SideDepth + SPM * (1.25 + rng:NextNumber() * 2.5)
	end
	local target = Vector3.new(0, R, -side * depth)
	local steps = 0
	if q >= H.SpikeAssistQuality and not overcharge then
		steps = H.NetAssistSteps
	end
	local speed = HitLogic.studs(kmh)
	if kind == "JumpServe" then
		-- topspin: the serve dives. Pick the gravity that makes a flat hit land on target.
		local dist = math.max(math.abs(target.Z - ball.Z), 1)
		local flat = 2 * math.max(ball.Y - R, 1) * (speed / dist) ^ 2
		g = math.max(G * H.ServeGravityScale, flat * H.ServeTopspin)
	end
	local v = speedWithAssist(ball, target, speed, g, side, steps)
	local hold = 0
	if thunder or pierce then
		hold = H.HitStopThunder
	elseif q >= H.PerfectAt then
		hold = H.HitStopPerfect
	elseif q >= H.GreatAt then
		hold = H.HitStopGreat
	end
	return launchResult(meta, ball, v, Vector3.new(0, -g, 0), t, hold)
end

------------------------------------------------------------------------------------------
-- compute(input, ctx) -> ok, result | reason
-- input: action, t, root, ball, vy, grounded, diving (slide), stanceAge, assist, energy,
--        setType, targetId, tossHeight, serveKind
-- ctx:   side, team, teamSize, seq, ballVel, lastHit, thirdTouch, touchNumber, stats,
--        ability, groundY, stamina = { value, max }, forceQuality?
------------------------------------------------------------------------------------------

function HitLogic.compute(input, ctx)
	local action = input.action
	local side = ctx.side
	local stats = ctx.stats or Characters.stats(Config.DefaultTier)
	local rng = Random.new(math.floor((ctx.seq or 0) * 7919 + (ACTION_CODE[action] or 0) * 104729 + 17))
	local root, ball, t = input.root, input.ball, input.t

	-- Serve toss ------------------------------------------------------------------------
	if action == "Toss" then
		local h = clamp(input.tossHeight or H.TossLow, H.TossLow, H.TossHighMax)
		local p = Vector3.new(0, root.Y + 2.0, root.Z - side * 0.8)
		local v = Vector3.new(0, math.sqrt(2 * G * h), -side * H.TossForward)
		local meta = meta0("Toss", 1)
		meta.grade = "TOSS"
		meta.serveKind = h > H.TossLow + 0.5 and "Jump" or "Overhand"
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
		local frac = clamp((dz - H.SpikeDzDeep) / (H.SpikeDzShort - H.SpikeDzDeep), 0, 1)
		local depth = lerp(H.FeintMaxDepth, 0.95 * SPM, frac) + jitter(rng, (1 - qContact) * H.FeintError)
		local target = Vector3.new(0, R, -side * clamp(depth, 0.6 * SPM, H.FeintMaxDepth + 0.95 * SPM))
		local g = G
		if ctx.ability == "Azure" then
			g = G * 1.6 -- topspin roll shot: drops faster
		end
		local v = arcWithAssist(ball, target, math.max(ball.Y + 0.16 * SPM, C.NetTop + H.FeintApexOverNet), g)
		return launchResult(meta, ball, v, Vector3.new(0, -g, 0), t)
	end

	-- Block -----------------------------------------------------------------------------------
	if action == "Block" then
		local ok, q, fingertips = HitLogic.blockBox(root, ball, side, stats)
		if not ok then
			return false, "zone"
		end
		local last = ctx.lastHit
		if not last or last.team == ctx.team then
			return false, "own"
		end
		if HitLogic.isServe(last.hitType) or last.hitType == "Toss" then
			return false, "serve"
		end
		if ctx.forceQuality then
			q = ctx.forceQuality
		end
		local inc = ctx.ballVel or Vector3.new(0, 0, side * 9.4 * SPM)
		local attackKmh = last.kmh or HitLogic.kmh(inc.Magnitude)
		local power = 0
		if last.hitType == "Spike" then
			power = clamp((attackKmh - 60) / 140, 0, 1)
		end
		local stuffScore = q - 0.42 * power
		if last.pierce then
			stuffScore = math.min(stuffScore, 0.3)
		end
		local atk = -side
		local meta = meta0("Block", clamp(q, 0, 1))
		meta.attackKmh = attackKmh
		local p, v, a, hold = nil, nil, nil, 0
		if stuffScore >= 0.45 then
			meta.outcome = "Stuff"
			p = Vector3.new(0, ball.Y, atk * (R + 0.1))
			v = Vector3.new(0, -SPM * (4.4 + 5 * q), atk * SPM * (3.1 + 4.4 * q))
			a = Vector3.new(0, -G * 1.3, 0)
			hold = 0.05
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
		local sliding = input.diving == true
		local isSet = action == "Set"
		local overhead = false
		local ok, q = false, 0
		if not sliding then
			ok, q = HitLogic.setZone(root, ball, side, stats)
			overhead = ok
			if ok and not isSet and ball.Y - root.Y < Z.SetMinY + 0.8 then
				-- a receive pressed on a chest-high ball stays a forearm pass
				local ok2, q2 = HitLogic.receiveZone(root, ball, side, stats, false)
				if ok2 then
					ok, q, overhead = ok2, q2, false
				end
			end
		end
		if not ok then
			ok, q = HitLogic.receiveZone(root, ball, side, stats, sliding)
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
			if age < H.PerfectStanceMin then
				qTime = 0.75 + (age / H.PerfectStanceMin) * 0.25
			elseif age > H.PerfectStanceMax then
				qTime = clamp(1 - (age - H.PerfectStanceMax) / 0.5, 0.45, 1)
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
		local perfect = heavy and not sliding and q >= H.PerfectAt
		local drain = 0
		if heavy and not sliding then
			drain = HitLogic.drainFor(incomingKmh, stats)
			if perfect then
				drain = drain * HitLogic.perfectDrainMul(incomingKmh)
			end
		end
		meta.drain = drain > 0 and drain or nil
		meta.perfect = perfect or nil
		-- a heavy ball knocks the receiver back (0..1), unless they slid
		if heavy and not sliding then
			local knock = clamp((incomingKmh - ST.KnockFromKmh) / 90, 0, 1)
			meta.knock = knock > 0 and knock or nil
		end

		if heavy and not sliding and stam.value <= 0 and incomingKmh >= ST.BreakFailKmh then
			-- guard broken: the spike blasts straight off the arms
			meta.fail = true
			meta.grade = "BROKEN"
			meta.quality = 0
			local dir = side
			if (ctx.ballVel or Vector3.zero).Z * side < 0 then
				dir = -side
			end
			local v = Vector3.new(0, SPM * (2.8 + rng:NextNumber() * 3.75), dir * SPM * (6.25 + rng:NextNumber() * 5))
			return launchResult(meta, ball, v, Vector3.new(0, -G, 0), t)
		end
		if heavy and not sliding and pct < ST.RedAt then
			local k = ST.LowQualityFloor + (1 - ST.LowQualityFloor) * (pct / ST.RedAt)
			q = q * k
		end
		if heavy and not sliding and stam.value > 0 and stam.value - drain <= 0 then
			-- this ball breaks the guard: the receive pops up out of control
			meta.breaks = true
			q = math.min(q, H.ShankAt - 0.05)
		end
		meta.quality, meta.grade = q, HitLogic.grade(q)
		if meta.perfect then
			meta.grade = "PERFECT"
		end
		meta.score = math.floor(q * 100 + 0.5)

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
			if not meta.breaks and tz * side < 0.47 * SPM then
				tz = side * 0.47 * SPM
			end
			if meta.breaks and rng:NextNumber() < 0.35 then
				tz = -side * SPM * (0.95 + rng:NextNumber() * 1.9) -- popped over the net
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
			meta.underhand = underhand or nil
			if type(input.targetId) == "string" then
				meta.targetId = input.targetId
			end
			local apex = H.SetApexOpen
			if setType == "Quick" then
				apex = H.SetApexQuick
			elseif setType == "Back" then
				apex = H.SetApexBack
			end
			local accuracy = stats.SetAccuracy
			if underhand then
				accuracy = accuracy * 0.55
				apex = apex * 0.92
			end
			apex = math.max(apex, ball.Y + 0.38 * SPM)
			local depth = Court.attackDepth(setType) + jitter(rng, (1 - q) ^ 1.4 * H.SetError / accuracy)
			depth = math.max(depth, 0.47 * SPM)
			local g = G * H.SetGravityScale
			local v = ownSideArc(ball, Vector3.new(0, H.SetArriveY, side * depth), apex, g, side, 0.38 * SPM)
			return launchResult(meta, ball, v, Vector3.new(0, -g, 0), t)
		end

		-- first touch: a high pass to the setter (or up in front of yourself when solo)
		local depth = H.SetterDepth
		if (ctx.teamSize or 3) <= 1 then
			depth = clamp(math.abs(root.Z) - 1.6 * SPM, 1.25 * SPM, 3.75 * SPM)
		end
		local err = (1 - q) ^ 1.3 * H.PassError
		local apex = lerp(H.PassApexMin, H.PassApexMax, q)
		if sliding then
			depth = depth + 0.6 * SPM
			err = err + 0.6 * SPM
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
