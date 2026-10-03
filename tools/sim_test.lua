-- Headless test harness: runs the real shared gameplay modules under texlua (Lua 5.3)
-- with tiny shims for the Roblox types they use. Usage: texlua tools/sim_test.lua

local ROOT = arg and arg[0]:match("^(.*)/tools/") or "."

-- Vector3 shim ------------------------------------------------------------------------
local V = {}
V.__index = function(t, k)
	if k == "X" then return rawget(t, 1) end
	if k == "Y" then return rawget(t, 2) end
	if k == "Z" then return rawget(t, 3) end
	if k == "Magnitude" then return math.sqrt(t[1] * t[1] + t[2] * t[2] + t[3] * t[3]) end
	if k == "Unit" then
		local m = math.sqrt(t[1] * t[1] + t[2] * t[2] + t[3] * t[3])
		return setmetatable({ t[1] / m, t[2] / m, t[3] / m }, V)
	end
	return V[k]
end
local function vec(x, y, z) return setmetatable({ x, y, z }, V) end
V.__add = function(a, b) return vec(a[1] + b[1], a[2] + b[2], a[3] + b[3]) end
V.__sub = function(a, b) return vec(a[1] - b[1], a[2] - b[2], a[3] - b[3]) end
V.__unm = function(a) return vec(-a[1], -a[2], -a[3]) end
V.__mul = function(a, b)
	if type(a) == "number" then return vec(a * b[1], a * b[2], a * b[3]) end
	if type(b) == "number" then return vec(a[1] * b, a[2] * b, a[3] * b) end
	return vec(a[1] * b[1], a[2] * b[2], a[3] * b[3])
end
V.__div = function(a, b) return vec(a[1] / b, a[2] / b, a[3] / b) end
V.__tostring = function(a) return string.format("(%.2f, %.2f, %.2f)", a[1], a[2], a[3]) end
function V.Dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
Vector3 = { new = vec, zero = vec(0, 0, 0) }
Color3 = { fromRGB = function(r, g, b) return { r, g, b } end, new = function(r, g, b) return { r, g, b } end }
math.clamp = function(x, a, b) if x < a then return a elseif x > b then return b end return x end

-- Deterministic Random shim (same interface as Roblox Random) -------------------------
Random = {
	new = function(seed)
		local state = (seed or 1) % 2147483647
		if state <= 0 then state = state + 2147483646 end
		return {
			NextNumber = function(self)
				state = (state * 16807) % 2147483647
				return state / 2147483647
			end,
			NextInteger = function(self, a, b)
				state = (state * 16807) % 2147483647
				return a + math.floor(state / 2147483647 * (b - a + 1))
			end,
		}
	end,
}

-- require shim for script.Parent.<Module> -----------------------------------------------
local cache = {}
script = { Parent = setmetatable({}, { __index = function(_, name) return name end }) }
function require(name)
	if cache[name] == nil then
		cache[name] = dofile(ROOT .. "/src/shared/" .. name .. ".lua")
	end
	return cache[name]
end

local Config = require("Config")
local BallPhysics = require("BallPhysics")
local HitLogic = require("HitLogic")
local Court = require("Court")
local Characters = require("Characters")
local Spins = require("Spins")
local Roster = require("Roster")
local Lobbies = require("Lobbies")
local C, Z, H = Config.Court, Config.Zones, Config.Hits
local SPM = Config.Scale.StudsPerMeter
local K = SPM / 3.2 -- the suite's distances were written at 3.2 studs per metre

local failures = 0
local function check(cond, label, detail)
	print(string.format("%s  %s%s", cond and "PASS" or "FAIL", label, detail and ("   " .. detail) or ""))
	if not cond then failures = failures + 1 end
end
local function describe(path)
	local L = path.landing
	return string.format("lands z=%.1f (%s) t=%.2fs net=%s", L.pos.Z, L.kind, L.t - path.segs[1].t0, tostring(path.flags.netTouch or false))
end

local side = 1 -- Away: own court z > 0, attacking toward z < 0
local GROUND = 3.0
local SP = Characters.stats("S+")
local function ctx(extra)
	local c = { side = side, team = "Away", teamSize = 3, seq = 42, ballVel = vec(0, -10, 0), thirdTouch = false,
		touchNumber = 3, stats = SP, ability = nil, groundY = GROUND, stamina = { value = 120, max = 120 } }
	for k, v in pairs(extra or {}) do c[k] = v end
	return c
end
-- a character at the top of its jump, `dist` studs from the net
-- top of a real jump: the Humanoid's JumpHeight plus what the hang force adds near the apex
local function apexRoot(stats, dist)
	return vec(0, GROUND + Characters.jumpHeight(stats, GROUND) + Characters.hangGain(), side * dist)
end
-- ball placed relative to that character's hand (dz toward the net, dy up)
local function ballAt(root, dz, dy)
	local handZ = root.Z - side * Z.SpikeForward
	return vec(0, root.Y + Z.SpikeUp + dy, handZ - side * dz)
end
local function spike(root, ball, extraCtx, extraInput)
	local input = { action = "Spike", t = 0, root = root, ball = ball, vy = 0, grounded = false }
	for k, v in pairs(extraInput or {}) do input[k] = v end
	return HitLogic.compute(input, ctx(extraCtx))
end
local function oppDepth(path) return -path.landing.pos.Z * side end

print("== S+ spike power (targets: 110 weak end, 140 well timed) ==")
do
	local root = apexRoot(SP, 3.5 * K)
	local ok, res = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy))
	local path = BallPhysics.buildPath(res.launch)
	check(ok and res.meta.kmh > 136 and res.meta.kmh <= 141, "perfect contact at the apex", string.format("%.1f km/h, %.2f m", res.meta.kmh, res.meta.height))
	check(not path.flags.netTouch and path.landing.pos.Z * side < 0 and Court.inBounds(path.landing.pos), "perfect spike lands in", describe(path))
	check(oppDepth(path) > 20 * K, "clean contact goes deep", string.format("%.1f studs deep", oppDepth(path)))
	local lowRoot = root - vec(0, 3.2, 0) -- mistimed: hit on the way up
	local ok2, res2 = spike(lowRoot, ballAt(lowRoot, 1.9, 1.3))
	check(ok2 and res2.meta.kmh >= 108 and res2.meta.kmh < 124, "edge contact below the apex is the weak end", string.format("%.1f km/h, contact %.2f", ok2 and res2.meta.kmh or 0, ok2 and res2.meta.contact or 0))
end

print("== spike direction from relative position ==")
do
	local root = apexRoot(SP, 3.0 * K)
	local depths = {}
	for _, dz in ipairs({ -0.1, 1.0, 2.2 }) do
		local ok, res = spike(root, ballAt(root, dz, 0))
		local path = BallPhysics.buildPath(res.launch)
		table.insert(depths, oppDepth(path))
	end
	check(depths[1] > depths[2] and depths[2] > depths[3], "ball ahead of the hand = shorter spike", string.format("depths %.1f > %.1f > %.1f", depths[1], depths[2], depths[3]))
	local ok, res = spike(root, ballAt(root, -1.6, 0.4))
	local path = BallPhysics.buildPath(res.launch)
	check(ok and not Court.inBounds(path.landing.pos), "ball behind the head sails long", describe(path))
	local farRoot = apexRoot(SP, 14 * K) -- far off the net, reaching for a ball ahead
	local ok3, res3 = spike(farRoot, ballAt(farRoot, 2.3, 1.2))
	local path3 = BallPhysics.buildPath(res3.launch)
	check(ok3 and res3.meta.quality < H.SpikeAssistQuality and (path3.flags.netTouch or path3.landing.pos.Z * side > 0), "sloppy steep swing from deep finds the net", string.format("q=%.2f %s", res3.meta.quality, describe(path3)))
end

print("== Thunder Spiker (target 160-200 above 4.00 m) ==")
do
	-- 4.00 m takes a maxed jump: a maxed S+ hits about 4.35 m, a starting one about 3.4 m
	local tallSP = Characters.derive(Characters.fromRoster(Roster.get("yejun"), "max"))
	local root = apexRoot(tallSP, 3.5 * K)
	local ok, res = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), { ability = "Thunder", stats = tallSP })
	check(ok and res.meta.thunder and res.meta.kmh >= 185 and res.meta.kmh <= 200.5, "perfect thunder from a maxed YeJun", string.format("%.1f km/h at %.2f m", res.meta.kmh, res.meta.height))
	local low = root - vec(0, Characters.studsAt(tallSP.ContactMaxM) - Characters.studsAt(4.05), 0) -- just over 4.00 m
	local ok2, res2 = spike(low, ballAt(low, 1.4, 0.25), { ability = "Thunder", stats = tallSP })
	check(ok2 and res2.meta.thunder and res2.meta.kmh >= 160 and res2.meta.kmh < 185, "scrappy thunder just over 4.00 m", string.format("%.1f km/h at %.2f m", res2.meta.kmh, res2.meta.height))
	local path = BallPhysics.buildPath(res.launch)
	check(Court.inBounds(path.landing.pos) and not path.flags.netTouch, "thunder spike lands in", describe(path))
	local A = Characters.stats("A")
	local rootA = apexRoot(A, 3.5 * K)
	local ok3, res3 = spike(rootA, ballAt(rootA, Z.SpikeCenterDz, 0), { ability = "Thunder", stats = A })
	check(ok3 and not res3.meta.thunder, "maxed A at 185 cm can't reach 4.00 m", string.format("max %.2f m, %.1f km/h", res3.meta.height, res3.meta.kmh))
	local tallA = Characters.stats("A", "WS", 190)
	local rootTA = apexRoot(tallA, 3.5 * K)
	local ok6, res6 = spike(rootTA, ballAt(rootTA, Z.SpikeCenterDz, 2.2), { ability = "Thunder", stats = tallA })
	check(ok6 and not res6.meta.thunder, "not a 190 cm maxed A, even off a high ball", string.format("%.2f m, %.1f km/h", res6.meta.height, res6.meta.kmh))
	local tallS = Characters.stats("S", "WS", 200)
	local rootT = apexRoot(tallS, 3.5 * K)
	local ok4, res4 = spike(rootT, ballAt(rootT, Z.SpikeCenterDz, 0), { ability = "Thunder", stats = tallS })
	check(ok4 and res4.meta.thunder, "a 200 cm maxed S can", string.format("%.2f m, %.1f km/h", res4.meta.height, res4.meta.kmh))
	local freshSP = Characters.derive(Characters.fromRoster(Roster.get("yejun")))
	local rootS = apexRoot(freshSP, 3.5 * K)
	local ok5, res5 = spike(rootS, ballAt(rootS, Z.SpikeCenterDz, 0), { ability = "Thunder", stats = freshSP })
	check(ok5 and not res5.meta.thunder, "a fresh (un-upgraded) YeJun can't: Jump upgrades unlock Thunder", string.format("%.2f m, %.1f km/h", res5.meta.height, res5.meta.kmh))
end

print("== The Spike's scale and jumps ==")
do
	local okMap = true
	for _, m in ipairs({ 1.2, 2.0, 2.43, 3.3, 4.0, 4.6 }) do
		okMap = okMap and math.abs(Characters.metersAt(Characters.studsAt(m)) - m) < 1e-9
	end
	check(okMap, "studs and metres convert both ways")
	local jump = Characters.jumpHeight(SP, GROUND)
	local avatarM = 5.3 / SPM
	check(math.abs(C.NetTop / SPM - 2.43) < 1e-6 and math.abs(C.SideDepth / SPM - 9) < 1e-6 and avatarM > 1.0 and avatarM < 1.3, "The Spike's scale: 2.43 m net, 9 m half court, characters about 1.15 m", string.format("net %.1f studs, half court %.1f studs, avatar %.2f m", C.NetTop, C.SideDepth, avatarM))
	check(SP.contactMaxStuds / C.NetTop > 1.9 and SP.contactMaxStuds / C.NetTop < 2.35 and jump > 2.5 * 5.3, "a maxed S+ leaps over twice its height and hits at twice the net", string.format("jump %.1f studs, hand at %.1f studs = %.2fx the net", jump, SP.contactMaxStuds, SP.contactMaxStuds / C.NetTop))
	local Dm = Characters.stats("D-")
	local lowest, highest = math.huge, 0
	for _, c in ipairs(Roster) do
		lowest = math.min(lowest, Characters.derive(Characters.fromRoster(c)).ContactMaxM)
		highest = math.max(highest, Characters.derive(Characters.fromRoster(c, "max")).ContactMaxM)
	end
	check(lowest >= 2.5 and lowest <= 2.65 and highest >= 4.3 and highest <= 4.45 and SP.ContactMaxM > 4.25 and SP.ContactMaxM < 4.4, "the lowest starter hits about 2.6 m, a maxed top jumper 4.3 to 4.4 m", string.format("lowest %.2f m, highest maxed %.2f m, S+ template %.2f m", lowest, highest, SP.ContactMaxM))
	local DmRoot = apexRoot(Dm, 3.5 * K)
	local okD, resD = spike(DmRoot, ballAt(DmRoot, Z.SpikeCenterDz, 2.4), { stats = Dm })
	check(okD and resD.meta.height <= Dm.ContactMaxM + 1e-6, "a ball met above the hand still reads the hand's height", string.format("%.2f m", resD.meta.height))
	local root = apexRoot(SP, 3.5 * K)
	local ok, res = spike(root, ballAt(root, Z.SpikeCenterDz, 0))
	check(ok and math.abs(res.meta.height - SP.ContactMaxM) < 0.03, "the readout still shows the real hitting point", string.format("%.2f m (hitting point %.2f m)", res.meta.height, SP.ContactMaxM))
	-- airtime of a full jump with the hang force, same integration as the bots use
	local P = Config.Player
	local g = P.Gravity
	local v = math.sqrt(2 * g * jump)
	local y, t, dt = 0, 0, 1 / 240
	repeat
		local a = g
		if math.abs(v) < P.HangVelocityWindow then a = g * (1 - P.HangGravityCancel) end
		v = v - a * dt
		y = y + v * dt
		t = t + dt
	until y <= 0 or t > 5
	check(t >= 1.3 and t <= 2.2, "full jump hangs like an anime spike", string.format("%.2f s in the air at gravity %d", t, g))
	local B, A = Characters.stats("B"), Characters.stats("A")
	check(H.SetArriveY >= B.contactMaxStuds and H.SetArriveY <= SP.contactMaxStuds, "sets come down through B to S+ hitting points", string.format("set arrives at %.1f studs; maxed B %.1f, A %.1f, S+ %.1f", H.SetArriveY, B.contactMaxStuds, A.contactMaxStuds, SP.contactMaxStuds))
	-- the spike window: with the best jump timing under an open set, how long the ball stays in
	-- reach. The client commits a swing pressed up to 0.6 s early; this is the window it lands in.
	local sroot = vec(0, GROUND, side * H.SetterDepth)
	local _, setRes = HitLogic.compute({ action = "Set", t = 0, root = sroot, ball = vec(0, sroot.Y + Z.SetIdealY, sroot.Z), grounded = true, setType = "Open" }, ctx({ touchNumber = 2, lastHit = { team = "Away", hitType = "Bump" } }))
	local setPath = BallPhysics.buildPath(setRes.launch)
	local worst, report = math.huge, {}
	local starter = Characters.derive(Characters.fromRoster(Roster.get("riku")))
	for _, b in ipairs({ { "starter Riku (D)", starter }, { "A", A }, { "S+", SP } }) do
		local st = b[2]
		local jy, jv, ys = 0, math.sqrt(2 * g * Characters.jumpHeight(st, GROUND)), {}
		repeat
			ys[#ys + 1] = jy
			local acc = g
			if math.abs(jv) < P.HangVelocityWindow then acc = g * (1 - P.HangGravityCancel) end
			jv = jv - acc * dt
			jy = jy + jv * dt
		until jy < 0
		local best = 0
		for ts = 0, setPath.landing.t, 1 / 30 do
			local inz = 0
			for i = 1, #ys, 4 do
				local tt = ts + (i - 1) * dt
				if tt >= setPath.landing.t then break end
				if HitLogic.spikeZone(vec(0, GROUND + ys[i], side * H.OpenDepth), BallPhysics.positionAt(setPath, tt), side, st, 1) then
					inz = inz + 4 * dt
				end
			end
			best = math.max(best, inz)
		end
		worst = math.min(worst, best)
		table.insert(report, string.format("%s %.2f s", b[1], best))
	end
	check(worst >= 0.15, "a well-timed jump keeps the set in reach long enough to hit", table.concat(report, ", "))
	local tossApex = 2 + H.TossHighMax
	check(tossApex >= SP.contactMaxStuds + 2, "a full toss rises above an S+ jump serve contact", string.format("toss apex about %.1f studs", tossApex + GROUND))
end

print("== Azure Dragon ==")
do
	local root = apexRoot(SP, 3.5 * K)
	local b = ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local _, none = spike(root, b, { ability = "Azure" }, { energy = 0 })
	local _, half = spike(root, b, { ability = "Azure" }, { energy = 0.5 })
	local _, full = spike(root, b, { ability = "Azure" }, { energy = 1.0 })
	check(full.meta.kmh >= 190 and full.meta.kmh <= 205 and full.meta.pierce, "full bar = max power and pierce", string.format("0%%: %.0f  50%%: %.0f  100%%: %.0f km/h", none.meta.kmh, half.meta.kmh, full.meta.kmh))
	local okO, over = spike(root, b, { ability = "Azure" }, { energy = 1.3 })
	local path = BallPhysics.buildPath(over.launch)
	check(over.meta.overcharge and not Court.inBounds(path.landing.pos), "overcharge flies out", describe(path))
end

print("== Feral Leap (Dante) ==")
do
	local FERAL = Config.Abilities.Feral
	local dante = Characters.derive(Characters.fromRoster(Roster.get("dante"), "max"))
	local seojin = Characters.derive(Characters.fromRoster(Roster.get("seojin"), "max"))
	local root = apexRoot(dante, 3.5 * K)
	local b = ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local function leapSpike(gauge, toward, extraCtx, stats)
		local c = { ability = "Feral", stats = stats or dante }
		for k, v in pairs(extraCtx or {}) do c[k] = v end
		local r = apexRoot(c.stats, 3.5 * K)
		return spike(r, ballAt(r, Z.SpikeCenterDz, Z.SpikeCenterDy), c, { gauge = gauge, toward = toward })
	end
	local _, none = leapSpike(0, true)
	local _, half = leapSpike(0.5, true)
	local _, full = leapSpike(1, true)
	local sr = apexRoot(seojin, 3.5 * K)
	local _, azure = spike(sr, ballAt(sr, Z.SpikeCenterDz, Z.SpikeCenterDy), { ability = "Azure", stats = seojin }, { energy = 1 })
	check(none.meta.kmh > 141 and half.meta.kmh > none.meta.kmh + 15 and full.meta.kmh > half.meta.kmh + 25 and full.meta.kmh > azure.meta.kmh and full.meta.kmh <= 212,
		"the longer the charge, the harder the spike; a full one tops a full Azure", string.format("0%%: %.0f  50%%: %.0f  100%%: %.0f km/h (full Azure %.0f)", none.meta.kmh, half.meta.kmh, full.meta.kmh, azure.meta.kmh))
	local path = BallPhysics.buildPath(full.launch)
	check(Court.inBounds(path.landing.pos) and not path.flags.netTouch, "a full leap spike lands in", describe(path))
	local _, away = leapSpike(1, false)
	local _, most = leapSpike(0.9, true)
	check(full.meta.fullLeap and full.meta.breakAtk == dante.Attack and away.meta.fullLeap and not away.meta.breakAtk and not most.meta.fullLeap and not most.meta.breakAtk,
		"only a full charge leaping at the net carries the block break (with his Attack)", string.format("break Attack %s", tostring(full.meta.breakAtk)))
	local _, first = leapSpike(1, true, { firstStrike = true })
	local _, firstHalf = leapSpike(0.5, true, { firstStrike = true })
	check(first.meta.firstStrike and math.abs(first.meta.kmh / full.meta.kmh - (1 + FERAL.FirstBoost)) < 0.005 and not full.meta.firstStrike and not firstHalf.meta.firstStrike,
		"the match's first full charge hits harder still (a partial one doesn't spend it)", string.format("%.0f km/h", first.meta.kmh))

	-- the block break: through a blocker with less Attack, not one with more, never Iron Wall;
	-- blocked where the full leap spike reaches the net
	local bside = -side
	local mb = Characters.stats("S+", "MB")
	local tNet = BallPhysics.findTime(path, 0, function(pos) return pos.Z * side <= 0.2 end)
	local bball = BallPhysics.positionAt(path, tNet)
	local inc = BallPhysics.velocityAt(path, tNet)
	local broot = vec(0, bball.Y - Z.BlockReachUp + 1.0, bside * 1.2)
	local function blockAgainst(meta, stats, wall)
		local last = { team = "Away" }
		for k, v in pairs(meta) do last[k] = v end
		last.team = "Away"
		return HitLogic.compute({ action = "Block", t = 0, root = broot, ball = bball, grounded = false },
			{ side = bside, team = "Home", teamSize = 3, seq = 7, ballVel = inc, lastHit = last, stats = stats, groundY = GROUND, ironWall = wall })
	end
	local okB, smash = blockAgainst(full.meta, mb)
	local spath = BallPhysics.buildPath(smash.launch)
	check(okB and smash.meta.outcome == "Break" and smash.meta.breakThrough and spath.landing.pos.Z * bside > 0 and Court.inBounds(spath.landing.pos) and smash.meta.kmh >= 0.8 * HitLogic.kmh(inc.Magnitude) and HitLogic.isHeavy(smash.meta),
		"a full leap at the net smashes through a middle's block and on into their court, still a spike to dig", string.format("%s at %.0f km/h, %s", smash.meta.outcome, smash.meta.kmh, describe(spath)))
	local strong = Characters.boosted(mb, { Attack = dante.Attack - mb.Attack + 5 })
	local _, held = blockAgainst(full.meta, strong)
	local _, walled = blockAgainst(full.meta, mb, true)
	local _, plain = blockAgainst(away.meta, mb)
	check(held.meta.outcome ~= "Break" and walled.meta.outcome == "Stuff" and plain.meta.outcome ~= "Break",
		"a blocker with more Attack holds, Iron Wall stuffs it, and a leap away from the net can't break", string.format("%s / %s / %s", held.meta.outcome, walled.meta.outcome, plain.meta.outcome))
	local recRoot = vec(0, GROUND, bside * 18 * K)
	local recBall = vec(0, recRoot.Y + Z.ReceiveIdealY, recRoot.Z - bside * Z.ReceiveForward)
	local okD, dig = HitLogic.compute({ action = "Bump", t = 0, root = recRoot, ball = recBall, grounded = true, stanceAge = 0.6 },
		{ side = bside, team = "Home", teamSize = 3, seq = 9, ballVel = vec(0, -30 * K, bside * 110 * K), lastHit = smash.meta, touchNumber = 1, stats = mb, groundY = GROUND, stamina = { value = 90, max = 90 } })
	check(okD and (dig.meta.drain or 0) > 5, "digging the ball that broke through costs stamina like a spike", string.format("drain %.1f", dig.meta.drain or 0))

	-- the AI playing him hits with less; his serve toss goes further forward; his reach is wider
	local auto = HitLogic.effectiveStats(dante, "Feral", nil, { auto = true })
	local _, autoNone = leapSpike(0, true, { auto = true })
	local _, autoFull = leapSpike(1, true, { auto = true })
	local autoBonus = autoFull.meta.kmh / autoNone.meta.kmh - 1
	check(auto.Attack == math.floor(dante.Attack * FERAL.AutoAttackMul + 0.5) and math.abs(autoBonus - FERAL.MaxBoost * FERAL.AutoBoostMul) < 0.005 and autoFull.meta.kmh < full.meta.kmh - 20,
		"played by the AI: 85% of the Attack and three quarters of the gauge's bonus", string.format("%d Attack, a full leap %.0f km/h (+%.0f%%)", auto.Attack, autoFull.meta.kmh, autoBonus * 100))
	local tr = vec(0, GROUND, side * C.SideDepth + side * 2)
	local _, v1 = HitLogic.tossLaunch(tr, side, H.TossHighMax, 1)
	local _, v2 = HitLogic.tossLaunch(tr, side, H.TossHighMax, 1, HitLogic.tossReach("Feral"))
	local T = 2 * v1.Y / Config.Ball.Gravity
	local okT, toss = HitLogic.compute({ action = "Toss", t = 0, root = tr, ball = tr, grounded = true, tossHeight = H.TossHighMax, tossForward = 1 }, ctx({ ability = "Feral" }))
	check(math.abs((math.abs(v2.Z) - math.abs(v1.Z)) * T - H.TossForwardMax * (FERAL.TossReachMul - 1)) < 1e-6 and okT and math.abs(toss.launch.v.Z - v2.Z) < 1e-9,
		"his full forward toss comes down further in front", string.format("%.1f m further", (math.abs(v2.Z) - math.abs(v1.Z)) * T / SPM))
	local wide = ballAt(root, Z.SpikeCenterDz + Z.SpikeRadiusZ * dante.Reach * 1.07, Z.SpikeCenterDy)
	local okW = spike(root, wide, { ability = "Feral", stats = dante })
	local okN = spike(root, wide, { stats = dante })
	check(okW and not okN, "his spike reaches wider", string.format("x%.2f", FERAL.ReachMul))

	-- how far the leap carries: the flight of his full jump (hang force included) at the carry
	local P = Config.Player
	local g = P.Gravity
	local v = math.sqrt(2 * g * Characters.jumpHeight(dante, GROUND))
	local y, t, dt = 0, 0, 1 / 240
	repeat
		local a = g
		if math.abs(v) < P.HangVelocityWindow then a = g * (1 - P.HangGravityCancel) end
		v = v - a * dt
		y = y + v * dt
		t = t + dt
	until y <= 0 or t > 5
	local fullM = FERAL.CarryMax * t / SPM
	local tapM = FERAL.CarryMax * (FERAL.TapTime / FERAL.ChargeTime) * t / SPM
	check(fullM >= 4.5 and fullM <= 8 and tapM < 0.3 * fullM and FERAL.ChargeTime <= 0.7, "a full charge (0.7 s or less) carries the leap 4.5 to 8 m further; the shortest hold a fraction of that", string.format("full %.1f m in %.1f s of charge, shortest leap %.1f m, %.2f s in the air", fullM, FERAL.ChargeTime, tapM, t))

	-- his jump serve takes the charge too (serves are never blocked: no block break)
	local sroot = vec(0, GROUND + Characters.jumpHeight(dante, GROUND) + Characters.hangGain(), side * (C.SideDepth + 1))
	local sball = ballAt(sroot, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local function jumpServe(g, extraCtx)
		local c = ctx({ ability = "Feral", stats = dante })
		for k, v in pairs(extraCtx or {}) do c[k] = v end
		return HitLogic.compute({ action = "Serve", t = 0, root = sroot, ball = sball, vy = 0, grounded = false, gauge = g, toward = true }, c)
	end
	local okS0, s0 = jumpServe(0)
	local okS1, s1 = jumpServe(1)
	local okS2, s2 = jumpServe(1, { firstStrike = true })
	local servePath = okS1 and BallPhysics.buildPath(s1.launch)
	check(okS0 and okS1 and okS2 and s1.meta.hitType == "JumpServe" and math.abs(s1.meta.kmh / s0.meta.kmh - (1 + FERAL.MaxBoost)) < 0.005 and s1.meta.fullLeap and not s1.meta.breakAtk and s2.meta.firstStrike,
		"his jump serve takes the charge too: x1.4 at full, a First Strike, no block break", string.format("%.0f -> %.0f km/h (first strike %.0f), %s", s0.meta.kmh, s1.meta.kmh, s2.meta.kmh, describe(servePath)))

	-- Space on the held ball tosses and starts the charge: his toss goes up high, so a full
	-- charge (then the leap's gather) still meets it at his hitting point, fresh or maxed
	local function serveGap(st)
		local r0 = vec(0, GROUND, side * (C.SideDepth + 1))
		local tp, tv = HitLogic.tossLaunch(r0, side, H.TossHighMax, 0, HitLogic.tossReach("Feral"))
		local tossPath = BallPhysics.buildPath(BallPhysics.newLaunch(tp, tv, vec(0, -Config.Ball.Gravity, 0), 0))
		local takeoff = FERAL.ChargeTime + P.ApproachGather
		local jv, jy, tt, gap, rise, peak = math.sqrt(2 * g * Characters.jumpHeight(st, GROUND)), 0, 0, math.huge, 0, 0
		repeat
			local acc = g
			if math.abs(jv) < P.HangVelocityWindow then acc = g * (1 - P.HangGravityCancel) end
			jv = jv - acc * dt
			jy = jy + jv * dt
			tt = tt + dt
			peak = math.max(peak, jy)
			local ball = BallPhysics.positionAt(tossPath, takeoff + tt)
			local d = math.abs(ball.Y - (GROUND + jy + Z.SpikeUp + Z.SpikeCenterDy))
			if d < gap then
				gap, rise = d, jy
			end
		until jy < 0 or takeoff + tt >= tossPath.landing.t
		return gap, peak - rise -- how close the ball comes to the hand, and how far below the top of the jump
	end
	local freshDante = Characters.derive(Characters.fromRoster(Roster.get("dante")))
	local gapMax, belowMax = serveGap(dante)
	local gapFresh, belowFresh = serveGap(freshDante)
	check(gapMax < 1 and gapFresh < 1 and belowMax < 2 and belowFresh < 2, "a full charge off his toss meets the ball at the top of his jump, fresh or maxed",
		string.format("maxed: the ball %.2f studs from the hand %.1f below the top; fresh: %.2f, %.1f below", gapMax, belowMax, gapFresh, belowFresh))
end

print("== tiers and builds ==")
do
	local prev = 0
	local okAll = true
	local line = {}
	for _, tier in ipairs({ "D-", "C", "B", "A", "S", "S+" }) do
		local st = Characters.stats(tier)
		local root = apexRoot(st, 3.5 * K)
		local ok, res = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = st })
		okAll = okAll and ok and res.meta.kmh > prev
		prev = ok and res.meta.kmh or prev
		table.insert(line, string.format("%s %.0f/%.2fm", tier, ok and res.meta.kmh or 0, ok and res.meta.height or 0))
	end
	check(okAll, "maxed builds: power and hitting point rise with tier", table.concat(line, "  "))
	local cheat = Characters.sanitize("B", { Height = 400, Attack = 999, Defense = -5, Speed = 999, Jump = 999 })
	-- the same 140 km/h spike from an S+ drains the full amount, from lower tiers less and less
	local recRoot = vec(0, GROUND, side * 18 * K)
	local recBall = vec(0, recRoot.Y + Z.ReceiveIdealY, recRoot.Z - side * Z.ReceiveForward)
	local drains = {}
	for _, tier in ipairs({ "S+", "S", "A", "B", "C", "D-" }) do
		local _, r = HitLogic.compute({ action = "Bump", t = 0, root = recRoot, ball = recBall, vy = 0, grounded = true, stanceAge = 0.6 },
			ctx({ ballVel = vec(0, -30 * K, side * 110 * K), lastHit = { team = "Home", hitType = "Spike", kmh = 140, tierDrain = HitLogic.tierDrain(tier) }, touchNumber = 1, stamina = { value = 200, max = 200 } }))
		table.insert(drains, r.meta.drain or 0)
	end
	local falling = true
	for i = 2, #drains do
		falling = falling and drains[i] < drains[i - 1]
	end
	local steeper = (drains[4] - drains[5]) / drains[1] > 0 and HitLogic.tierDrain("S+") == 1 and math.abs(HitLogic.tierDrain("D-") - Config.Stamina.TierDrainLow) < 1e-9
	check(falling and steeper and drains[6] < 0.3 * drains[1], "an S+ spike drains the full guard cost; lower tiers less and less", string.format("S+ %.1f  S %.1f  A %.1f  B %.1f  C %.1f  D- %.1f", drains[1], drains[2], drains[3], drains[4], drains[5], drains[6]))
	check(cheat.Height == Config.Height.Max and cheat.Attack == Config.Stats.Max and cheat.Defense == Config.Stats.Min, "sanitize clamps a forged build", string.format("%d cm, %d attack, %d defense", cheat.Height, cheat.Attack, cheat.Defense))
end

print("== the roster ==")
do
	local ids, okShape, okAbility, okLimits = {}, true, true, true
	local tallestSE, shortestMB, notes = 0, 999, {}
	local want = {
		WS = { Adrenaline = true, RisingSun = true, Counter = true, Plunge = true },
		MB = { IronWall = true, RallyCry = true },
		SE = { ChainReaction = true, Vector = true, Turnabout = true },
	}
	for _, c in ipairs(Roster) do
		okLimits = okLimits and not ids[c.Id] and Characters.isTier(c.Tier) and Config.RoleTemplates[c.Role] ~= nil
		ids[c.Id] = true
		for _, k in ipairs(Config.Stats.Order) do
			okLimits = okLimits and c[k] >= Config.Stats.Min and c[k] <= Config.Stats.Max
		end
		if c.Tier == "S+" then
			okAbility = okAbility and c.Role == "WS" and (c.Ability == "Thunder" or c.Ability == "Azure" or c.Ability == "Feral")
		elseif c.Tier == "S" then
			okAbility = okAbility and want[c.Role][c.Ability or ""] == true and Config.Abilities[c.Ability].Role == c.Role
		else
			okAbility = okAbility and c.Ability == nil
		end
		if c.Role == "WS" then
			-- 210 Attack tops the wing spikers' template; Dante (Feral Leap) is the one above it
			okShape = okShape and (c.Attack <= 210 or c.Ability == "Feral") and c.Jump <= 190 and c.Attack > c.Defense
		elseif c.Role == "SE" then
			okShape = okShape and c.Speed > c.Attack and c.Defense > c.Jump
			tallestSE = math.max(tallestSE, c.Height)
			if c.Tier == "S" then
				okShape = okShape and c.Speed >= 160 and c.Speed <= 180 and c.Defense >= 160 and c.Defense <= 180
			end
		elseif c.Role == "MB" then
			shortestMB = math.min(shortestMB, c.Height)
		end
	end
	check(okLimits and #Roster >= 30, "every roster character is valid and unique", #Roster .. " characters")
	check(okAbility, "abilities: S+ wing spikers have Thunder, Azure or Feral Leap, S characters one of their role's abilities, the rest none")
	local topId, topAtk, nextAtk = nil, 0, 0
	for _, c in ipairs(Roster) do
		if c.Attack > topAtk then
			topId, nextAtk, topAtk = c.Id, topAtk, c.Attack
		elseif c.Attack > nextAtk then
			nextAtk = c.Attack
		end
	end
	check(topId == "dante" and topAtk > nextAtk, "Dante (Feral Leap) has the highest Attack in the game", string.format("%s %d, next best %d", tostring(topId), topAtk, nextAtk))
	check(okShape and shortestMB > tallestSE, "roles: wing spikers hit hardest, middles are the tallest, setters live on speed and defense", string.format("shortest MB %d cm, tallest SE %d cm", shortestMB, tallestSE))
	local yejun = Roster.get("yejun")
	local ys = Characters.derive(Characters.fromRoster(yejun, "max"))
	local thunders = 0
	for _, c in ipairs(Roster) do
		if c.Ability == "Thunder" then
			thunders = thunders + 1
		end
	end
	check(yejun.Ability == "Thunder" and thunders == 1 and yejun.Attack == Config.Stats.Ref and yejun.Jump == 190 and ys.ContactMaxM >= 4.0 and ys.Power == 1, "YeJun is the only Thunder Spiker: top Attack (full power), 190 Jump, and maxed he reaches the 4.00 m line", string.format("Attack %d, power x%.2f, %.2f m", yejun.Attack, ys.Power, ys.ContactMaxM))
	local starters = true
	local roles = {}
	for _, id in ipairs(Roster.Starters) do
		local c = Roster.get(id)
		starters = starters and c ~= nil and string.sub(c.Tier, 1, 1) == "D"
		if c then
			roles[c.Role] = true
		end
	end
	check(starters and roles.WS and roles.MB and roles.SE, "everyone starts with a D-tier wing spiker, middle and setter")
end

print("== deuce ==")
do
	local base = Config.Match.PointsPerSet
	local t1, d1 = Court.playTo(13, 12, base)
	local t2, d2 = Court.playTo(14, 14, base)
	local t3 = Court.playTo(15, 14, base)
	local t4, d4 = Court.playTo(15, 15, base)
	local t5 = Court.playTo(24, 24, base)
	local wins = 16 >= Court.playTo(16, 14, base) and not (15 >= Court.playTo(15, 14, base)) and 15 >= Court.playTo(15, 13, base)
	check(t1 == base and not d1 and t2 == base + 1 and d2 and t3 == base + 1 and t4 == base + 2 and d4 and t5 == Config.Match.PointCap and wins, "deuce: 14-14 plays to 16, 15-15 to 17, capped at a golden point", string.format("13-12 to %d, 14-14 to %d, 15-14 to %d, 15-15 to %d, 24-24 to %d", t1, t2, t3, t4, t5))
	-- a custom lobby's rules: a set to 3 still goes to deuce at 2-2 and ends on a golden point
	-- 10 past its target (as 25 is for 15); win by 1 has no deuce; a set to 50 caps at 60
	local s1, sd1 = Court.playTo(2, 2, 3)
	local s2 = Court.playTo(12, 12, 3)
	local w1, wd1 = Court.playTo(14, 14, 15, 1)
	local w2 = Court.playTo(49, 49, 50, 1)
	local b1 = Court.playTo(59, 59, 50)
	check(s1 == 4 and sd1 and s2 == 13 and w1 == 15 and not wd1 and w2 == 50 and b1 == 60, "custom sets: to 3 has deuce at 2-2 and a golden point at 13; win by 1 has no deuce; to 50 caps at 60",
		string.format("2-2 of 3 to %d, 12-12 to %d, 14-14 of 15 by 1 to %d, 49-49 of 50 by 1 to %d, 59-59 of 50 to %d", s1, s2, w1, w2, b1))
end

print("== rotation and formation ==")
do
	local order = { "a", "b", "c" }
	Court.reorder(order, "serve", "c", true)
	local served = order[1] == "c" and order[2] == "a" and order[3] == "b"
	local order2 = { "a", "b", "c" }
	Court.reorder(order2, "serve", "a", false)
	local recv = order2[2] == "a"
	local order3 = { "a", "b", "c" }
	Court.reorder(order3, "down", "a", true)
	local moved = order3[1] == "b" and order3[2] == "a" and not Court.reorder(order3, "up", "b", true)
	check(served and recv and moved, "timeout: pick the next server (serving or receiving) and move players up and down", table.concat(order, ",") .. " / " .. table.concat(order2, ",") .. " / " .. table.concat(order3, ","))
	local sideH = -1
	local mbZ = Court.formationSpot("Defense", "MB", sideH).Z
	local wsZ = Court.formationSpot("Defense", "WS", sideH).Z
	local members = {
		{ id = "me", role = "WS", isBot = false, z = mbZ + sideH * 0.3 }, -- stepped up to the net
		{ id = "mb", role = "MB", isBot = true },
		{ id = "se", role = "SE", isBot = true },
	}
	local spots = Court.formationFill(members, "Defense", sideH, Config.Bots.SwapMargin)
	members[1].z = wsZ
	local home = Court.formationFill(members, "Defense", sideH, Config.Bots.SwapMargin)
	check(spots.mb == wsZ and spots.se == Court.formationSpot("Defense", "SE", sideH).Z and home.mb == mbZ, "step up to block and the middle drops back into your spot", string.format("middle to %.1f (your spot %.1f), back to %.1f when you return", spots.mb, wsZ, home.mb))
end

print("== bot skill by tier ==")
do
	local B = Config.Bots
	local function clean(tier)
		local st = Characters.stats(tier)
		local dig = (1 - Characters.byTier(st, B.MissChance)) * (1 - Characters.byTier(st, B.WhiffChance))
		local spike = 1 - Characters.byTier(st, B.SpikeMishitChance)
		local serve = 1 - Characters.byTier(st, B.ServeMissChance)
		return dig * spike * serve, st
	end
	local dm, dStats = clean("D-")
	local s, sStats = clean("S")
	check(dm < 0.5 and s > 0.85 and Characters.byTier(dStats, B.ReactionDelay) > 5 * Characters.byTier(sStats, B.ReactionDelay), "a D- bot team dig-spike-serves cleanly under half the time, an S team almost always", string.format("clean D- %.0f%%, S %.0f%%; reaction %.2f s vs %.2f s", dm * 100, s * 100, Characters.byTier(dStats, B.ReactionDelay), Characters.byTier(sStats, B.ReactionDelay)))
	-- TeamService: a bot plays at the lobby's bot level when its character is a lower tier (an
	-- S+ lobby fields S middles and setters, there being no S+ ones)
	local lvl = (Characters.tierIndex("S+") - 1) / (#Config.Tiers - 1)
	local skillP = math.max(sStats.p, lvl)
	local perfect = B.PerfectReceiveChance[1] + (B.PerfectReceiveChance[2] - B.PerfectReceiveChance[1]) * skillP
	check(skillP == 1 and perfect >= 0.8 and sStats.p < 1, "an S+ lobby's bots play at S+ skill even as S characters", string.format("perfect receives %.0f%% (an S character's own tier: %.0f%%)", perfect * 100, Characters.byTier(sStats, B.PerfectReceiveChance) * 100))
end

print("== gold upgrades ==")
do
	local yejun, riku = Roster.get("yejun"), Roster.get("riku")
	local fresh = Characters.derive(Characters.fromRoster(yejun))
	local maxed = Characters.derive(Characters.fromRoster(yejun, "max"))
	local base = Characters.baseStat(yejun, "Attack")
	check(base < yejun.Attack and fresh.Attack == base and maxed.Attack == yejun.Attack and fresh.ContactMaxM < maxed.ContactMaxM - 0.4, "a recruit starts well below its ceiling and upgrades up to it", string.format("YeJun attack %d -> %d, hitting point %.2f -> %.2f m", base, yejun.Attack, fresh.ContactMaxM, maxed.ContactMaxM))
	local rising = Characters.pointCost(yejun, 180) > Characters.pointCost(yejun, 120) and Characters.pointCost(yejun, 120) > Characters.pointCost(riku, 120)
	local full = 0
	for _, stat in ipairs(Config.Stats.Order) do
		full = full + Characters.upgradeCost(yejun, Characters.baseStat(yejun, stat), yejun[stat])
	end
	local split = Characters.upgradeCost(yejun, 130, 140) + Characters.upgradeCost(yejun, 140, 150) == Characters.upgradeCost(yejun, 130, 150)
	check(rising and split, "points cost more the higher the stat and the tier, and refunds add up exactly", string.format("YeJun point at 120: %d gold, at 180: %d; Riku at 120: %d; maxing YeJun: %d gold", Characters.pointCost(yejun, 120), Characters.pointCost(yejun, 180), Characters.pointCost(riku, 120), full))
	local forged = Characters.derive(Characters.fromRoster(riku, { Attack = 999, Jump = 1 }))
	check(forged.Attack == riku.Attack and forged.Jump == Characters.baseStat(riku, "Jump"), "saved levels are clamped between the base and the ceiling")
end

print("== V Points spins ==")
do
	local rng = Random.new(11)
	local n = 20000
	check(Spins.cost(1) == 50 and Spins.cost(10) == 500 and Spins.cost(3) == nil, "x1 costs 50 VP, x10 costs 500 VP")
	local counts, starterDrops = {}, 0
	local startersSet = Spins.starters("Char")
	for _ = 1, n do
		local key = Spins.rollItem("Char", rng)
		local item = Spins.item("Char", key)
		counts[item.Rarity] = (counts[item.Rarity] or 0) + 1
		if startersSet[key] then
			starterDrops = starterDrops + 1
		end
	end
	local odds = Spins.odds("Char")
	local near = math.abs((counts.Mythic or 0) / n - odds.Mythic) < 0.003 and math.abs((counts.Common or 0) / n - odds.Common) < 0.02
	check(near and starterDrops == 0 and odds.Mythic < 0.01, "character spins follow the rarity odds (S+ is Mythic, under 1%) and never drop a starter", string.format("common %d, rare %d, epic %d, legendary %d, mythic %d of %d", counts.Common or 0, counts.Rare or 0, counts.Epic or 0, counts.Legendary or 0, counts.Mythic or 0, n))
	local total, best = 0, nil
	for _, row in ipairs(Spins.table("Char")) do
		total = total + row.chance
		best = best or row
	end
	check(math.abs(total - 1) < 1e-9 and best.item.Rarity == "Mythic", "the drop table lists every character with its chance, best first", string.format("%s first at %.2f%%", best.item.Name, best.chance * 100))
	local defaults = 0
	for _ = 1, 3000 do
		if Spins.rollItem("Color", rng) == Spins.default("Color") then
			defaults = defaults + 1
		end
	end
	local allKinds = true
	for _, kind in ipairs(Config.Cosmetics.Kinds) do
		local k = Spins.rollItem(kind, rng)
		allKinds = allKinds and Spins.item(kind, k) ~= nil and Config.Cosmetics.Attribute[kind] ~= nil
	end
	check(allKinds and defaults == 0, "every unlockable banner rolls a real item and never the default")
	local rising = true
	for i = 2, #Config.Rarity.Order do
		rising = rising and Spins.sellValue(Config.Rarity.Order[i]) > Spins.sellValue(Config.Rarity.Order[i - 1])
	end
	check(rising, "selling pays more for rarer pulls")
end

print("== receives, stamina, slides ==")
local incoming = vec(0, -30 * K, side * 110 * K) -- ~140 km/h spike arriving
local lastSpike = { team = "Home", hitType = "Spike", kmh = 140 }
-- receives are made by a defensive character (the S+ setter template, 178 Defense) unless a
-- test says otherwise
local DEF = Characters.stats("S+", "SE")
local function receive(root, ball, stam, extraInput, extraCtx)
	local input = { action = "Bump", t = 0, root = root, ball = ball, vy = 0, grounded = true, stanceAge = 0.2 }
	for k, v in pairs(extraInput or {}) do input[k] = v end
	local c = { ballVel = incoming, lastHit = lastSpike, touchNumber = 1, thirdTouch = false, stamina = stam, stats = DEF }
	for k, v in pairs(extraCtx or {}) do c[k] = v end
	return HitLogic.compute(input, ctx(c))
end
do
	local root = vec(0, GROUND, side * 18 * K)
	local ball = vec(0, root.Y + Z.ReceiveIdealY, root.Z - side * Z.ReceiveForward)
	local ok, res = receive(root, ball, { value = 120, max = 120 })
	local path = BallPhysics.buildPath(res.launch)
	local _, apexP = BallPhysics.findApex(path, 0)
	local tArr, pArr = BallPhysics.findTime(path, 0.05, function(p, v) return v.Y < 0 and p.Y <= H.PassArriveY end)
	check(ok and res.meta.perfect and res.meta.drain < 4, "perfect receive barely drains stamina", string.format("score %d, drain %.1f", res.meta.score, res.meta.drain or 0))
	check(apexP.Y >= 5.5 * SPM and pArr and math.abs(pArr.Z - side * H.SetterDepth) < 1.5 * K, "receive goes high to the setter", string.format("apex %.1f (%.1f m), arrives z=%.1f after %.2fs", apexP.Y, apexP.Y / SPM, pArr and pArr.Z or 0, tArr or 0))
	local ok2, res2 = receive(root, ball, { value = 120, max = 120 }, { stanceAge = 0.75 })
	check(ok2 and not res2.meta.perfect and (res2.meta.drain or 0) > 12, "late-pressed receive drains full stamina", string.format("%s %d, drain %.1f", res2.meta.grade, res2.meta.score, res2.meta.drain or 0))
	local ok3, res3 = receive(root, ball, { value = 25, max = 120 }, { stanceAge = 0.75 })
	check(ok3 and res3.meta.quality < res2.meta.quality, "red stamina makes receives unreliable", string.format("q %.2f vs %.2f", res3.meta.quality, res2.meta.quality))
	local ok4, res4 = receive(root, ball, { value = 6, max = 120 }, { stanceAge = 0.75 })
	local path4 = BallPhysics.buildPath(res4.launch)
	check(ok4 and res4.meta.breaks and path4.landing.pos.Z * side > C.SideDepth and not path4.flags.crossings, "the ball that empties the bar breaks the guard and flies out behind", string.format("%s, %s", res4.meta.grade, describe(path4)))
	local ok5, res5 = receive(root, ball, { value = 0, max = 120 })
	local path5 = BallPhysics.buildPath(res5.launch)
	check(ok5 and res5.meta.fail and path5.landing.pos.Z * side > C.SideDepth, "broken guard can't stop a strong spike: it flies out behind", describe(path5))
	local slideRoot = vec(0, GROUND, side * 16 * K)
	local slideBall = vec(0, slideRoot.Y - 2.2, slideRoot.Z - side * 4.2)
	local ok6, res6 = receive(slideRoot, slideBall, { value = 0, max = 120 }, { diving = true })
	local path6 = BallPhysics.buildPath(res6.launch)
	check(ok6 and not res6.meta.fail and not res6.meta.drain and path6.landing.pos.Z * side > 0, "slide receive works on a broken guard, no drain", string.format("q %.2f %s", res6.meta.quality, describe(path6)))
	-- the nerf: a 180 km/h spike costs real guard, perfect timing saves less on it, and it knocks
	-- the receiver back
	local A = Characters.stats("A")
	local fast = vec(0, -0.27, side * 0.96).Unit * HitLogic.studs(180)
	local spike180 = { team = "Home", hitType = "Spike", kmh = 180 }
	local okL, late180 = receive(root, ball, { value = A.StaminaPool, max = A.StaminaPool }, { stanceAge = 0.75 }, { stats = A, ballVel = fast, lastHit = spike180 })
	check(okL and late180.meta.drain >= A.StaminaPool * 0.45 and late180.meta.drain * 2 >= A.StaminaPool and late180.meta.knock == 1, "a late receive of a 180 km/h spike costs half an average guard; two break it", string.format("drain %.1f of %.0f, knockback %.2f", late180.meta.drain or 0, A.StaminaPool, late180.meta.knock or 0))
	local okP, perf180 = receive(root, ball, { value = A.StaminaPool, max = A.StaminaPool }, {}, { stats = A, ballVel = fast, lastHit = spike180 })
	local okP2, perf130 = receive(root, ball, { value = A.StaminaPool, max = A.StaminaPool }, {}, { stats = A })
	local r180 = perf180.meta.drain / late180.meta.drain
	check(okP and okP2 and perf180.meta.perfect and r180 > 0.35 and r180 <= 0.4 and perf130.meta.perfect and perf130.meta.drain < 0.08 * A.StaminaPool, "perfect timing still pays, but less against a monster spike", string.format("perfect at 180 pays %.0f%% (%.1f), at 130 only %.1f", r180 * 100, perf180.meta.drain, perf130.meta.drain))
	local slow = vec(0, -0.27, side * 0.96).Unit * HitLogic.studs(110)
	local okG1, good110 = receive(root, ball, { value = 120, max = 120 }, {}, { forceQuality = 0.8, ballVel = slow, lastHit = { team = "Home", hitType = "Spike", kmh = 110 } })
	local okG2, good180 = receive(root, ball, { value = 120, max = 120 }, {}, { forceQuality = 0.8, ballVel = fast, lastHit = spike180 })
	check(okG1 and okG2 and good110.meta.perfect and not good180.meta.perfect, "the same good dig is PERFECT at 110 km/h but not at 180", string.format("%s %d vs %s %d", good110.meta.grade, good110.meta.score, good180.meta.grade, good180.meta.score))
	local softHit = { team = "Home", hitType = "Block", outcome = "Soft", noDrain = true }
	local ok7, res7 = receive(root, ball, { value = 120, max = 120 }, { stanceAge = 0.75 }, { lastHit = softHit })
	check(ok7 and not res7.meta.drain, "soft-block deflection doesn't drain")
end

print("== bumps and sets stay on your side until the third touch ==")
do
	local over = 0
	local worst = 99
	for i = 1, 60 do
		local root = vec(0, GROUND, side * (8 + (i % 20)) * K)
		local ball = vec(0, root.Y - 2.0 + (i % 7) * 0.5, root.Z - side * (((i % 9) - 4) * 0.8))
		local ok, res = receive(root, ball, { value = 120, max = 120 }, { stanceAge = (i % 10) * 0.08 }, { seq = i, touchNumber = 1 + (i % 2) })
		if ok then
			local path = BallPhysics.buildPath(res.launch)
			if path.landing.pos.Z * side < 0 or path.flags.netTouch then over = over + 1 end
			worst = math.min(worst, path.landing.pos.Z * side)
		end
	end
	check(over == 0, "60 random first/second touches: none go over", string.format("closest landing %.1f studs from the net", worst))
	local root = vec(0, GROUND, side * 12 * K)
	local ball = vec(0, root.Y - 1, root.Z - side * 0.6)
	local ok, res = receive(root, ball, { value = 120, max = 120 }, {}, { thirdTouch = true, touchNumber = 3, lastHit = { team = "Away", hitType = "Set" }, ballVel = vec(0, -12 * K, 0) })
	local path = BallPhysics.buildPath(res.launch)
	check(ok and res.meta.free and path.landing.pos.Z * side < 0, "third-touch bump goes over as a free ball", describe(path))
end

print("== sets ==")
do
	local root = vec(0, GROUND, side * H.SetterDepth)
	local ball = vec(0, root.Y + Z.SetIdealY, root.Z)
	local ok, res = HitLogic.compute({ action = "Set", t = 0, root = root, ball = ball, grounded = true, setType = "Open" }, ctx({ touchNumber = 2, lastHit = { team = "Away", hitType = "Bump" } }))
	local path = BallPhysics.buildPath(res.launch)
	local _, apexP = BallPhysics.findApex(path, 0)
	local tA, pA = BallPhysics.findTime(path, 0.05, function(p, v) return v.Y < 0 and p.Y <= H.SetArriveY end)
	check(ok and res.meta.dotted and res.meta.hitType == "Set", "set is flagged for the dotted arc")
	check(apexP.Y >= 6 * SPM and tA and tA > 1.2 and math.abs(pA.Z - side * H.OpenDepth) < 1.2 * K, "open set: high, hangs, arrives at the attack spot", string.format("apex %.1f (%.1f m), %.2fs to hitting height at z=%.1f", apexP.Y, apexP.Y / SPM, tA or 0, pA and pA.Z or 0))
	local okB, resB = HitLogic.compute({ action = "Bump", t = 0, root = vec(0, GROUND, side * 6 * K), ball = vec(0, GROUND - 1, side * (6 * K - 0.6)), grounded = true, stanceAge = 0.2 }, ctx({ touchNumber = 2, lastHit = { team = "Away", hitType = "Bump" } }))
	check(okB and resB.meta.hitType == "Set" and resB.meta.underhand, "second-touch bump becomes an underhand set")
end

print("== middle quicks and the wing spiker backup ==")
do
	local P = Config.Player
	local g = P.Gravity
	local dt = 1 / 240
	-- a bot's jump from takeoff: root heights every dt (hang near the apex, like the bots)
	local function jumpCurve(st)
		local jy, jv, ys = 0, math.sqrt(2 * g * Characters.jumpHeight(st, GROUND)), {}
		repeat
			ys[#ys + 1] = jy
			local acc = g
			if math.abs(jv) < P.HangVelocityWindow then acc = g * (1 - P.HangGravityCancel) end
			jv = jv - acc * dt
			jy = jy + jv * dt
		until jy < 0
		return ys
	end
	local function apexTime(ys)
		local best, bi = -1, 1
		for i, y in ipairs(ys) do if y > best then best, bi = y, i end end
		return (bi - 1) * dt
	end
	-- first moment (and ball height) the ball is in this jumper's spike zone, jumping at `takeoff`
	-- from `depth` off the net, not before `notBefore`
	local function meets(st, depth, path, takeoff, notBefore)
		local ys = jumpCurve(st)
		for i = 1, #ys, 2 do
			local tt = takeoff + (i - 1) * dt
			if tt >= path.landing.t then break end
			if tt >= (notBefore or -math.huge) then
				local b = BallPhysics.positionAt(path, tt)
				local okz, _, _, dy = HitLogic.spikeZone(vec(0, GROUND + ys[i], side * depth), b, side, st, 1)
				if okz and dy <= Z.SpikeCenterDy + 0.25 then return tt, b end
			end
		end
		return nil
	end
	local function descent(path, y)
		local aT, aP = BallPhysics.findApex(path, 0)
		if aP.Y < y then return aT, aP end
		return BallPhysics.findTime(path, 0, function(pos, vel) return vel.Y < 0 and pos.Y <= y end)
	end
	local mb = Characters.derive(Characters.fromRoster(Roster.get("tetsuo"), "max"))
	local ws = Characters.derive(Characters.fromRoster(Roster.get("yejun"), "max"))
	local sroot = vec(0, GROUND, side * H.SetterDepth)
	local sball = vec(0, sroot.Y + Z.SetIdealY, sroot.Z)
	local function setPath(kind)
		local _, r = HitLogic.compute({ action = "Set", t = 0, root = sroot, ball = sball, grounded = true, setType = kind }, ctx({ touchNumber = 2, lastHit = { team = "Away", hitType = "Bump" } }))
		return BallPhysics.buildPath(r.launch), r.meta
	end
	-- setter aim: an aimed set comes down through the hitting height where it was aimed, and an
	-- aim past the range is held to it
	local function arrival(aimDepth, aimHeight)
		local _, r = HitLogic.compute({ action = "Set", t = 0, root = sroot, ball = sball, grounded = true, setType = "Open", aimDepth = aimDepth, aimHeight = aimHeight }, ctx({ touchNumber = 2, lastHit = { team = "Away", hitType = "Bump" } }))
		local path = BallPhysics.buildPath(r.launch)
		local y = math.clamp(aimHeight or H.SetArriveY, H.SetAimLowY, H.SetAimHighY)
		local tA = BallPhysics.findTime(path, 0, function(pos, vel) return vel.Y < 0 and pos.Y <= y end)
		return tA and BallPhysics.positionAt(path, tA).Z * side or -1, r.meta
	end
	local nearAim, farAim = H.SetAimMin + 2, H.SetAimMax - 2
	local dNear, mNear = arrival(nearAim)
	local dFar = arrival(farAim)
	local dPast = arrival(H.SetAimMax * 3)
	local dLow = arrival(farAim, H.SetAimLowY)
	local dHigh = arrival(nearAim, H.SetAimHighY)
	local dSky = arrival(farAim, H.SetAimHighY * 5)
	check(mNear.aimed and math.abs(dNear - nearAim) < 0.8 and math.abs(dFar - farAim) < 0.8 and math.abs(dPast - H.SetAimMax) < 0.8
		and math.abs(dLow - farAim) < 0.8 and math.abs(dHigh - nearAim) < 0.8 and math.abs(dSky - farAim) < 0.8,
		"setter aim: the set comes down through the aimed height at the aimed distance, low or high, near or far, within the range",
		string.format("aimed %.1f -> %.1f, %.1f -> %.1f, past -> %.1f (max %.1f); low %.1f, high %.1f, clamped high %.1f", nearAim, dNear, farAim, dFar, dPast, H.SetAimMax, dLow, dHigh, dSky))
	-- quick: the middle is in the air before the set is even made
	local qPath, qMeta = setPath("Quick")
	local vq, gq = HitLogic.setArc(sball, side, "Quick")
	local nominal = BallPhysics.buildPath(BallPhysics.newLaunch(sball, vq, vec(0, -gq, 0), 0))
	local cT, cP = descent(nominal, mb.contactMaxStuds - 0.15)
	local tApex = apexTime(jumpCurve(mb))
	local takeoff = cT - tApex
	local hitT = meets(mb, cP.Z * side + Z.SpikeForward, qPath, takeoff, 0.2) -- once the set has left the setter's hands
	local oPath = setPath("Open")
	local oT = descent(oPath, mb.contactMaxStuds - 0.15)
	check(qMeta.setType == "Quick" and takeoff <= 0.05 and hitT ~= nil and hitT > cT - 0.25 and cT < oT * 0.75, "a quick: the middle is off the floor as the set is made and meets it at the top, well ahead of an open set", string.format("takeoff at %+.2f s, contact %.2f s after the set (open set %.2f s)", takeoff, hitT or -1, oT))
	-- backup: the middle jumps late behind the wing spiker; a miss is still spiked above the net
	local tW = descent(oPath, ws.contactMaxStuds - 0.15)
	local tM = descent(oPath, mb.contactMaxStuds - 0.15)
	local tB = math.max(tM, tW + Config.Bots.BackupDelay)
	local pB = BallPhysics.positionAt(oPath, tB)
	local jh = Characters.jumpHeight(mb, GROUND)
	local d = pB.Y - (GROUND + Z.SpikeUp)
	local lead = tApex
	if d < jh - 0.3 then
		local v0 = math.sqrt(2 * g * jh)
		lead = (v0 - math.sqrt(math.max(0, v0 * v0 - 2 * g * d))) / g
	end
	local bT, bP = meets(mb, pB.Z * side + Z.SpikeForward, oPath, tB - lead, tW + Config.Bots.BackupDelay * 0.5)
	check(bT ~= nil and bT > tW and bP.Y > C.NetTop + 0.6 * SPM, "backup: after a wing spiker's miss the middle still spikes it, above the net", string.format("wing spiker's contact %.2f s, middle's %.2f s at %.2f m", tW, bT or -1, bP and Characters.metersAt(bP.Y) or 0))
end

print("== serves ==")
do
	local serveZ = Court.serveSpot(side, "WS").Z
	local root = vec(0, GROUND + Characters.jumpHeight(SP, GROUND), serveZ)
	local ball = ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local ok, res = HitLogic.compute({ action = "Serve", t = 0, root = root, ball = ball, grounded = false }, ctx({ touchNumber = 1 }))
	local path = BallPhysics.buildPath(res.launch)
	check(ok and res.meta.hitType == "JumpServe" and path.landing.pos.Z * side < 0 and Court.inBounds(path.landing.pos) and not path.flags.netTouch, "S+ jump serve lands in", string.format("%.0f km/h, %s", res.meta.kmh, describe(path)))
	local groot = vec(0, GROUND, serveZ)
	local gball = vec(0, GROUND + Z.FloatUp, serveZ - side * 0.8)
	local ok2, res2 = HitLogic.compute({ action = "Serve", t = 0, root = groot, ball = gball, grounded = true }, ctx({ touchNumber = 1 }))
	local path2 = BallPhysics.buildPath(res2.launch)
	check(ok2 and res2.meta.hitType == "Overhand" and path2.landing.pos.Z * side < 0 and Court.inBounds(path2.landing.pos) and not path2.flags.netTouch, "overhand serve is safe", string.format("%.0f km/h, %s", res2.meta.kmh, describe(path2)))
	local ok3, res3 = HitLogic.compute({ action = "Toss", t = 0, root = groot, ball = groot, grounded = true, tossHeight = 22 }, ctx())
	local _, apexT = BallPhysics.findApex(BallPhysics.buildPath(res3.launch), 0)
	check(ok3 and res3.meta.serveKind == "Jump" and apexT.Y > 25, "held toss goes high for a jump serve", string.format("apex %.1f", apexT.Y))
	-- the easy underhand serve: from anywhere behind the line, any roll, it clears the net and lands in
	local allIn, slowest, fastest, worstClear = true, math.huge, 0, math.huge
	for d = 0, 10 do
		local z = side * (C.SideDepth + 0.3 + d * (C.FreeZoneEnd - 0.5) / 10)
		for seq = 1, 12 do
			local r = vec(0, GROUND, z)
			local okU, u = HitLogic.compute({ action = "Underhand", t = 0, root = r, ball = r, grounded = true }, ctx({ seq = seq * 13 + d, touchNumber = 1 }))
			if not okU then
				allIn = false
			else
				local up = BallPhysics.buildPath(u.launch)
				local _, atNet = BallPhysics.findTime(up, 0, function(pos) return pos.Z * side <= 0 end)
				if not atNet or up.flags.netTouch or not Court.inBounds(up.landing.pos) or up.landing.pos.Z * side >= 0 then
					allIn = false
				else
					worstClear = math.min(worstClear, atNet.Y - C.NetTop)
				end
				slowest, fastest = math.min(slowest, u.meta.kmh), math.max(fastest, u.meta.kmh)
			end
		end
	end
	check(allIn and fastest < 60 and worstClear > 1 * SPM, "the easy underhand serve always clears the net and lands in, slowly", string.format("%.0f to %.0f km/h, clears the net by %.1f m or more", slowest, fastest, worstClear / SPM))
	-- a forward toss comes back down about TossForwardMax in front, so the server runs into it
	local function tossDrop(fwd)
		local okT, r = HitLogic.compute({ action = "Toss", t = 0, root = groot, ball = groot, grounded = true, tossHeight = 22, tossForward = fwd }, ctx())
		local tp = BallPhysics.buildPath(r.launch)
		local _, back = BallPhysics.findTime(tp, 0, function(pos, vel) return vel.Y < 0 and pos.Y <= groot.Y + 2.0 end)
		return okT and back and (groot.Z - back.Z) * side or 0, r.meta
	end
	local still = tossDrop(0)
	local ahead, fmeta = tossDrop(1)
	check(ahead - still > H.TossForwardMax * 0.9 and ahead - still < H.TossForwardMax * 1.1 and fmeta.tossForward == 1 and serveZ * side - ahead > C.SideDepth - 3 * SPM, "a forward toss drops out in front of the server (toward the net)", string.format("%.1f studs ahead vs %.1f straight up", ahead, still))
end

print("== blocks ==")
do
	local bside = -side
	local broot = vec(0, GROUND + Characters.jumpHeight(SP, GROUND) * 0.9, bside * 1.2)
	local ball = vec(0, C.NetTop + 2.4, bside * 0.3)
	local function block(last, ballVel, stats)
		return HitLogic.compute({ action = "Block", t = 0, root = broot, ball = ball, grounded = false },
			{ side = bside, team = "Home", teamSize = 3, seq = 7, ballVel = ballVel, lastHit = last, stats = stats or SP, groundY = GROUND })
	end
	local ok, res = block({ team = "Away", hitType = "Spike", kmh = 110 }, vec(0, -25 * K, bside * 90 * K))
	local path = BallPhysics.buildPath(res.launch)
	check(ok and res.meta.outcome == "Stuff" and path.landing.pos.Z * side > 0, "S+ blocker stuffs a 110 km/h spike", describe(path))
	local ok2, res2 = block({ team = "Away", hitType = "Spike", kmh = 200, pierce = true }, vec(0, -25 * K, bside * 150 * K))
	check(ok2 and res2.meta.outcome ~= "Stuff" and res2.meta.noDrain, "full Azure pierces the block (soft touch, no drain)", res2.meta.outcome)
end

print("== role abilities ==")
do
	-- Adrenaline (S wing spiker): low team stamina = more Attack and Jump
	local hayun = Characters.derive(Characters.fromRoster(Roster.get("hayun"), "max"))
	local low = { value = 20, max = 100 }
	local boostedStats, on = HitLogic.effectiveStats(hayun, "Adrenaline", low)
	local _, off = HitLogic.effectiveStats(hayun, "Adrenaline", { value = 80, max = 100 })
	local root = apexRoot(boostedStats, 3.5 * K)
	local b = ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local okA, fired = spike(root, b, { ability = "Adrenaline", stats = hayun, stamina = low })
	local okB, calm = spike(apexRoot(hayun, 3.5 * K), ballAt(apexRoot(hayun, 3.5 * K), Z.SpikeCenterDz, Z.SpikeCenterDy), { ability = "Adrenaline", stats = hayun, stamina = { value = 80, max = 100 } })
	check(on and not off and okA and okB and fired.meta.adrenaline and fired.meta.kmh > calm.meta.kmh + 4 and boostedStats.ContactMaxM > hayun.ContactMaxM + 0.1, "Adrenaline: under 40% stamina an S wing spiker hits harder from higher", string.format("%.1f vs %.1f km/h, %.2f vs %.2f m", fired.meta.kmh, calm.meta.kmh, boostedStats.ContactMaxM, hayun.ContactMaxM))

	-- Chain Reaction (S setter): her set is charged, the spike or feint off it explodes
	local seoyeon = Characters.derive(Characters.fromRoster(Roster.get("seoyeon"), "max"))
	local sroot = vec(0, GROUND, side * H.SetterDepth)
	local okS, set = HitLogic.compute({ action = "Set", t = 0, root = sroot, ball = vec(0, sroot.Y + Z.SetIdealY, sroot.Z), grounded = true, setType = "Open" }, ctx({ touchNumber = 2, stats = seoyeon, ability = "ChainReaction", lastHit = { team = "Away", hitType = "Bump" } }))
	local charged = set.meta
	charged.team = "Away"
	local sr = apexRoot(SP, 3.5 * K)
	local sb = ballAt(sr, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local _, plain = spike(sr, sb, { lastHit = { team = "Away", hitType = "Set" } })
	local _, boom = spike(sr, sb, { lastHit = charged })
	local _, feint = spike(sr, sb, { lastHit = charged }, { action = "Feint" })
	check(okS and charged.charged and boom.meta.reaction and math.abs(boom.meta.kmh / plain.meta.kmh - Config.Abilities.ChainReaction.PowerMul) < 0.01 and feint.meta.reaction and not feint.meta.noDrain, "Chain Reaction: a charged set makes the spike (and even a feint) explode", string.format("%.1f vs %.1f km/h", boom.meta.kmh, plain.meta.kmh))
	local recRoot = vec(0, GROUND, side * 18 * K)
	local recBall = vec(0, recRoot.Y + Z.ReceiveIdealY, recRoot.Z - side * Z.ReceiveForward)
	local fast = vec(0, -30 * K, side * 110 * K)
	local _, normalDig = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.6 }, { lastHit = { team = "Home", hitType = "Spike", kmh = 140 }, ballVel = fast })
	local _, boomDig = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.6 }, { lastHit = { team = "Home", hitType = "Spike", kmh = 140, reaction = true, drainMul = boom.meta.drainMul, flatDrain = boom.meta.flatDrain }, ballVel = fast })
	local _, feintDig = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.6 }, { lastHit = { team = "Home", hitType = "Feint", kmh = 32, reaction = true, noDrain = nil, drainMul = feint.meta.drainMul, flatDrain = feint.meta.flatDrain }, ballVel = vec(0, -8 * K, side * 10 * K) })
	check((boomDig.meta.drain or 0) > 2.5 * (normalDig.meta.drain or 0) and (feintDig.meta.drain or 0) >= 10, "the explosion wipes the receivers' stamina fast, even off a feint", string.format("dig drains %.1f vs %.1f; a charged feint %.1f", boomDig.meta.drain or 0, normalDig.meta.drain or 0, feintDig.meta.drain or 0))

	-- Iron Wall (S middle): everything that reaches the block is stuffed, even a full Azure
	local bside = -side
	local gaeul = Characters.derive(Characters.fromRoster(Roster.get("gaeul"), "max"))
	local broot = vec(0, GROUND + Characters.jumpHeight(gaeul, GROUND) * 0.9, bside * 1.2)
	local bball = vec(0, C.NetTop + 2.4, bside * 0.3)
	local function block(wall)
		return HitLogic.compute({ action = "Block", t = 0, root = broot, ball = bball, grounded = false },
			{ side = bside, team = "Home", teamSize = 3, seq = 7, ballVel = vec(0, -25 * K, bside * 150 * K), lastHit = { team = "Away", hitType = "Spike", kmh = 200, pierce = true, thunder = true }, stats = gaeul, groundY = GROUND, ironWall = wall })
	end
	local okW, wall = block(true)
	local okN, noWall = block(false)
	check(okW and okN and wall.meta.outcome == "Stuff" and wall.meta.ironWall and noWall.meta.outcome ~= "Stuff", "Iron Wall: a 200 km/h piercing spike is stuffed", string.format("with the wall: %s, without: %s", wall.meta.outcome, noWall.meta.outcome))
end

print("== lobbies ==")
do
	local s1 = Lobbies.settings({ mode = 7, privacy = "Nope", botTier = "Z" })
	local bad = Lobbies.settings({ mode = 2, privacy = "Private", password = "a!" })
	local s2 = Lobbies.settings({ mode = 2, privacy = "Private", password = "spike 99!", fill = false, botTier = "S" })
	check(s1.mode == Config.Match.DefaultTeamSize and s1.privacy == "Public" and s1.fill and s1.botTier == Config.Match.DefaultBotTier and bad == nil and s2.password == "spike99" and not s2.fill,
		"settings are cleaned: bad mode/privacy/tier fall back, a private lobby needs a real password")
	-- custom rules: points 3 to 50, win by 2 or 1, 1 set or best of 3 or 5, 0 to 5 timeouts
	local MC = Config.Match.Custom
	local r0 = Lobbies.rules(nil)
	local rLow = Lobbies.rules({ points = 1, sets = 4, timeouts = -2, winBy = 0 })
	local rHigh = Lobbies.rules({ points = 99.7, sets = 5, timeouts = 9, winBy = 1 })
	local rJunk = Lobbies.rules({ points = 0 / 0, sets = "3", timeouts = "x" })
	check(r0.points == Config.Match.PointsPerSet and r0.winBy == Config.Match.WinBy and r0.sets == 1 and r0.timeouts == Config.Timeout.PerSet
		and rLow.points == MC.PointsMin and rLow.sets == 1 and rLow.timeouts == 0 and rLow.winBy == 2
		and rHigh.points == MC.PointsMax and rHigh.sets == 5 and rHigh.timeouts == MC.TimeoutsMax and rHigh.winBy == 1
		and rJunk.points == Config.Match.PointsPerSet and rJunk.sets == 3 and rJunk.timeouts == Config.Timeout.PerSet,
		"a lobby's rules are cleaned: points 3 to 50, 1 or best of 3 or 5 sets, 0 to 5 timeouts, win by 2 unless 1; junk is the default")
	local custom = Lobbies.new(40, 1, "a", Lobbies.settings({ mode = 2, points = 21, winBy = 1, sets = 3, timeouts = 4 }))
	Lobbies.seat(custom, 1)
	local back = Lobbies.import(Lobbies.export(custom), 41)
	local sum = Lobbies.summary(custom, 1)
	check(custom.points == 21 and custom.winBy == 1 and custom.sets == 3 and custom.timeouts == 4 and back.points == 21 and back.winBy == 1 and back.sets == 3 and back.timeouts == 4 and sum.points == 21 and sum.sets == 3,
		"a custom lobby keeps its rules, shows them in its summary and takes them along to its own server")
	local l = Lobbies.new(1, 100, "Host", s2)
	Lobbies.seat(l, 100)
	local okNo, whyNo = Lobbies.canJoin(l, 200, "wrong")
	local okYes = Lobbies.canJoin(l, 200, "spike99")
	Lobbies.seat(l, 200)
	Lobbies.seat(l, 300)
	check(not okNo and whyNo == "password" and okYes and #l.Home == 2 and #l.Away == 1, "a private lobby lets the password in and balances the sides", string.format("Home %d, Away %d", #l.Home, #l.Away))
	local startOk, startWhy = Lobbies.canStart(l)
	Lobbies.seat(l, 400)
	local fullOk, fullWhy = Lobbies.canJoin(l, 500, "spike99")
	check(not startOk and startWhy == "teams" and Lobbies.canStart(l) and not fullOk and fullWhy == "full", "without bots it starts only with both sides full; a full lobby turns people away")
	local f = Lobbies.new(2, 100, "Host", Lobbies.settings({ mode = 3, privacy = "Friends" }))
	Lobbies.seat(f, 100)
	local fOk, fWhy = Lobbies.canJoin(f, 200, nil, false)
	check(not Lobbies.visible(f, 200, false) and Lobbies.visible(f, 201, true) and not fOk and fWhy == "friends" and Lobbies.canJoin(f, 201, nil, true) and Lobbies.canStart(f), "a friends lobby is hidden from (and closed to) everyone but the host's friends; with bots the host can start alone")
	-- host leaves: the next member hosts; a smaller mode keeps the host
	local h = Lobbies.new(3, 1, "A", Lobbies.settings({ mode = 3 }))
	for _, u in ipairs({ 1, 2, 3, 4, 5 }) do Lobbies.seat(h, u) end
	Lobbies.swap(h, 1)
	local dropped = Lobbies.configure(h, Lobbies.settings({ mode = 1 }))
	check(Lobbies.teamOf(h, 1) ~= nil and Lobbies.count(h) == 2 and #dropped == 3, "shrinking a lobby keeps the host and drops the newest", string.format("%d kept, %d dropped", Lobbies.count(h), #dropped))
	Lobbies.remove(h, 1)
	check(h.host ~= 1 and h.host ~= nil and Lobbies.teamOf(h, h.host) ~= nil, "when the host leaves the next member hosts")
	-- quick match picks the fullest open public quick lobby of the mode
	local q1 = Lobbies.new(10, 1, "a", Lobbies.settings({ mode = 2 })); q1.quick = true; Lobbies.seat(q1, 1)
	local q2 = Lobbies.new(11, 2, "b", Lobbies.settings({ mode = 2 })); q2.quick = true; Lobbies.seat(q2, 2); Lobbies.seat(q2, 3)
	local q3 = Lobbies.new(12, 4, "c", Lobbies.settings({ mode = 3 })); q3.quick = true; Lobbies.seat(q3, 4); Lobbies.seat(q3, 5); Lobbies.seat(q3, 6)
	local q4 = Lobbies.new(13, 7, "d", Lobbies.settings({ mode = 2, privacy = "Private", password = "abc" })); q4.quick = true; Lobbies.seat(q4, 7); Lobbies.seat(q4, 8); Lobbies.seat(q4, 9)
	check(Lobbies.pickQuick({ q1, q2, q3, q4 }, 2) == q2 and Lobbies.pickQuick({ q1, q3 }, 1) == nil, "Quick Match joins the fullest open public lobby of that mode")
	-- a tutorial lobby is hidden: only its player sees it, nobody can join
	local tl = Lobbies.new(20, 1, "a", Lobbies.settings({ mode = 1, botTier = "D-" }))
	tl.hidden = true
	Lobbies.seat(tl, 1)
	local tOk, tWhy = Lobbies.canJoin(tl, 2, nil, true)
	check(Lobbies.visible(tl, 1, false) and not Lobbies.visible(tl, 2, true) and not tOk and tWhy == "started", "a tutorial lobby is hidden and closed to everyone else")
	-- courts: a lobby keeps its pick, Rotate and Quick Match take the next court in the rotation
	local CC = Config.Courts
	local picked = Lobbies.new(30, 1, "a", Lobbies.settings({ mode = 2, court = "Beach" }))
	local rot = Lobbies.new(31, 1, "a", Lobbies.settings({ mode = 2, court = "Moon" }))
	local qc = Lobbies.new(32, 1, "a", Lobbies.settings({ mode = 2, court = "Beach" })); qc.quick = true
	local seen, cur = {}, nil
	for _ = 1, #CC.Rotation do
		cur = Lobbies.courtFor(rot, cur)
		seen[cur] = true
	end
	local allSeen = true
	for _, id in ipairs(CC.Rotation) do
		allSeen = allSeen and seen[id] == true and CC.List[id] ~= nil
	end
	check(picked.court == "Beach" and Lobbies.courtFor(picked, "Beach") == "Beach" and rot.court == CC.Rotate and allSeen
		and Lobbies.courtFor(qc, CC.Rotation[1]) == CC.Rotation[2] and Lobbies.courtFor(rot, "Nowhere") == CC.Rotation[1],
		"courts: a picked court sticks; Rotate and Quick Match go round every court in turn")
	local farRows, endRows = 0, 0
	for _, row in ipairs(Court.standRows("Beach")) do
		if row.axis == "X" then farRows = farRows + 1 else endRows = endRows + 1 end
	end
	check(farRows == CC.List.Beach.Stands.Rows and endRows == 0 and #Court.standRows() == #Court.standRows(CC.Default), "courts: each court seats its own stands", string.format("beach %d far, %d end", farRows, endRows))
	-- the teleport round trip
	picked.Home = { 5 }
	local pb = Lobbies.import(Lobbies.export(picked), 98)
	check(pb.court == "Beach", "a lobby's court survives the trip to its own server")
	local back = Lobbies.import(Lobbies.export(l), 99)
	check(back.mode == 2 and back.password == "spike99" and back.expected[100] == "Home" and back.expected[300] ~= nil and Lobbies.count(back) == 0 and Lobbies.import("junk") == nil, "a lobby survives the trip to its own server")
	-- AFK: idle time only builds while the ball is live; input resets it
	local idle, afk = 0, false
	for _ = 1, 20 do idle, afk = Lobbies.idle(idle, 0.5, "Timeout", false) end
	local quiet = idle
	for _ = 1, math.ceil(Config.Afk.Timeout / 0.5) - 1 do idle, afk = Lobbies.idle(idle, 0.5, "Rally", false) end
	local before = afk
	idle, afk = Lobbies.idle(idle, 0.5, "Rally", false)
	local reset = Lobbies.idle(idle, 0.5, "Rally", true)
	check(quiet == 0 and not before and afk and reset == 0 and Config.Afk.Timeout >= 10 and Config.Afk.Timeout <= 15, "AFK: 10 to 15 s without input while the ball is live (timeouts don't count)", string.format("%d s", Config.Afk.Timeout))
	-- Timeout pressed (the owner: "cancel a timeout by clicking t again")
	local called = { team = "Home", name = "a", id = "P_1" }
	local call = Lobbies.timeoutPress(nil, "Rally", "P_1", 2)
	local none, noneWhy = Lobbies.timeoutPress(nil, "Point", "P_1", 0)
	local cancel = Lobbies.timeoutPress(called, "Rally", "P_1", 2)
	local cancelLate = Lobbies.timeoutPress(called, "Point", "P_1", 2)
	local taken, takenWhy = Lobbies.timeoutPress(called, "Rally", "P_2", 2)
	local inIt = Lobbies.timeoutPress(nil, "Timeout", "P_2", 0)
	local early = Lobbies.timeoutPress(nil, "PreMatch", "P_1", 2)
	check(call == "call" and cancel == "cancel" and cancelLate == "cancel" and taken == nil and takenWhy == "taken" and none == nil and noneWhy == "none" and inIt == "ready" and early == nil,
		"timeout: a press calls one for the next dead ball, the caller's next press (up to the dead ball) calls it off, another's call waits, and in the timeout a press is Ready")
end

print("== tutorial and practice drills ==")
do
	local Tutorial = require("Tutorial")
	local done = {}
	local nextStep, n, total = Tutorial.progress(done)
	check(nextStep.id == "spike" and n == 0 and total == 4 and not Tutorial.complete(done), "the tutorial is the four drills, spike first")
	-- a drill you finish in total keeps its count through a miss; an in-a-row drill starts again
	local spike, serve = Tutorial.drill("spike"), Tutorial.drill("serve")
	local c, fin = 0, false
	for _, ok in ipairs({ true, false, true, false, true }) do
		c, fin = Tutorial.tally(spike, c, ok)
	end
	local s1, sfin = 0, false
	for _, ok in ipairs({ true, true, false, true, true }) do
		s1, sfin = Tutorial.tally(serve, s1, ok)
	end
	local s2, s2fin = Tutorial.tally(serve, s1, true)
	check(c == 3 and fin and s1 == 2 and not sfin and s2 == 3 and s2fin and Tutorial.drill("block").goal == 3 and Tutorial.drill("dig").inARow,
		"drills: spikes and blocks count through a miss; serves and digs have to be 3 in a row", string.format("spike %d, serve streak %d then %d", c, s1, s2))
	for _, d in ipairs(Tutorial.Drills) do
		done[d.id] = true
	end
	local vp, gold, spins = Tutorial.reward()
	check(Tutorial.complete(done) and Tutorial.isStep("dig") and not Tutorial.isStep("point") and vp == 50 and gold == 1000 and spins == 5,
		"finishing the four drills completes the tutorial; the reward is 50 VP, 1,000 Gold and 5 free recruits")
	-- a practice lobby that goes to its own server stays a hidden practice of the same drill
	local pl = Lobbies.new(40, 7, "P", Lobbies.settings({ mode = 2 }))
	Lobbies.seat(pl, 7)
	pl.practice, pl.drill, pl.hidden = true, "dig", true
	local back = Lobbies.import(Lobbies.export(pl), 41)
	check(back.practice and back.hidden and back.drill == "dig" and not back.tutorial, "a practice lobby survives the trip to its own server as the same hidden drill")
end

print("== match rewards: extra sets and win streaks ==")
do
	local Rewards = require("Rewards")
	local PR = Config.Progression
	local winVP, winGold = Rewards.match(true, 3)
	local lossVP = Rewards.match(false, 0)
	local oneVP = Rewards.extraSets({ "Home" }, "Home")
	local xv, xg = Rewards.extraSets({ "Home", "Away", "Home" }, "Home")
	check(Config.Match.Sets == 1 and winVP == PR.WinVP + 3 * PR.PlayVP and winGold == PR.WinGold + 3 * PR.PlayGold and lossVP == PR.LossVP and oneVP == 0
		and xv == PR.ExtraSetLossVP + PR.ExtraSetWinVP and xg == PR.ExtraSetLossGold + PR.ExtraSetWinGold, "a match is one set; every extra set pays on top (more for the sets you win)", string.format("win %d VP / %d Gold; two extra sets (lost, won) +%d VP / +%d Gold", winVP, winGold, xv, xg))
	local streak, bonuses = 0, {}
	for i = 1, 8 do
		streak = Rewards.nextStreak(streak, true)
		bonuses[i] = Rewards.streakBonus(streak)
	end
	local afterLoss = Rewards.nextStreak(streak, false)
	check(bonuses[1] == 0 and bonuses[2] == PR.StreakVP and bonuses[3] == 2 * PR.StreakVP and bonuses[8] == PR.StreakMaxSteps * PR.StreakVP and afterLoss == 0, "a win streak pays more with every straight win (capped), a loss resets it", string.format("bonus VP by streak: %d, %d, %d ... %d", bonuses[1], bonuses[2], bonuses[3], bonuses[8]))
	local k3, k9, k15, k50 = Rewards.pointsScale(3), Rewards.pointsScale(9), Rewards.pointsScale(15), Rewards.pointsScale(50)
	check(math.abs(k3 - Config.Progression.ShortSetMin) < 1e-9 and math.abs(k9 - 0.6) < 1e-9 and k15 == 1 and k50 == 1, "a custom lobby's shorter sets pay less: to 3 a fifth, to 9 three fifths; 15 and longer pay in full", string.format("%.2f %.2f %.2f %.2f", k3, k9, k15, k50))
	check(Rewards.winner({ "Home", "Away", "Home" }, { Home = 40, Away = 44 }) == "Home" and Rewards.winner({ "Home", "Away" }, { Home = 30, Away = 32 }) == "Away" and Rewards.winner({ "Away", "Home" }, { Home = 30, Away = 30 }) == "Home",
		"the match winner: most sets, then most points, then the last set")
end

print("== the second wave of S abilities ==")
do
	local ilya = Characters.derive(Characters.fromRoster(Roster.get("ilya"), "max"))
	local haeri = Characters.derive(Characters.fromRoster(Roster.get("haeri"), "max"))
	local daonC, yejunC = Roster.get("daon"), Roster.get("yejun")
	local daon = Characters.derive(Characters.fromRoster(daonC, "max"))
	local yejunS = Characters.derive(Characters.fromRoster(yejunC, "max"))
	local sroot = vec(0, GROUND, side * H.SetterDepth)
	local sball = vec(0, sroot.Y + Z.SetIdealY, sroot.Z)
	local function set(ability, stats, root, ball, extraCtx)
		local c = { touchNumber = 2, stats = stats, ability = ability, lastHit = { team = "Away", hitType = "Bump" } }
		for k, v in pairs(extraCtx or {}) do c[k] = v end
		return HitLogic.compute({ action = "Set", t = 0, root = root, ball = ball, grounded = root.Y <= GROUND + 0.01, setType = "Open" }, ctx(c))
	end

	-- Vector Set: the pulsing set; the steeper (shorter) the spike off it, the bigger the boost
	local _, vset = set("Vector", ilya, sroot, sball)
	vset.meta.team = "Away"
	local sr = apexRoot(SP, 3.5 * K)
	local _, deep = spike(sr, ballAt(sr, -0.1, 0), { lastHit = vset.meta })
	local _, short = spike(sr, ballAt(sr, 2.2, 0), { lastHit = vset.meta })
	local _, plain = spike(sr, ballAt(sr, 2.2, 0), { lastHit = { team = "Away", hitType = "Set" } })
	check(vset.meta.vectorSet and short.meta.vectorBoost > deep.meta.vectorBoost and short.meta.vectorBoost <= Config.Abilities.Vector.MaxBoost + 1e-9 and plain.meta.vectorBoost == nil and short.meta.kmh > plain.meta.kmh,
		"Vector Set: the spike off her pulsing set gains more the steeper it comes down", string.format("deep +%.1f%%, short +%.1f%% (%.0f vs %.0f km/h off a plain set)", deep.meta.vectorBoost * 100, short.meta.vectorBoost * 100, short.meta.kmh, plain.meta.kmh))
	-- her open set goes tight to the net and high (the attacker hits near the net, steeply)
	local _, nset = set(nil, ilya, sroot, sball)
	local vp, np = BallPhysics.buildPath(vset.launch), BallPhysics.buildPath(nset.launch)
	local _, vA = BallPhysics.findApex(vp, 0)
	local _, nA = BallPhysics.findApex(np, 0)
	local vz, nz = math.abs(vp.landing.pos.Z), math.abs(np.landing.pos.Z)
	check(vz < nz - 0.5 * SPM and vA.Y > nA.Y + 0.8 * SPM and vp.landing.pos.Z * side > 0,
		"Vector Set: her sets go tight to the net and high", string.format("lands %.2f m from the net (a plain set %.2f m), apex %.1f vs %.1f studs", vz / SPM, nz / SPM, vA.Y, nA.Y))

	-- Turnabout: armed, her set (a jump set) spins into a spike over the net; unarmed, it's a set
	local jroot = vec(0, GROUND + Characters.jumpHeight(haeri, GROUND) * 0.9, side * H.SetterDepth) -- near the top of her jump
	local jball = vec(0, jroot.Y + Z.SetIdealY, jroot.Z)
	local _, armed = set("Turnabout", haeri, jroot, jball, { turnabout = true })
	local _, groundArmed = set("Turnabout", haeri, sroot, sball, { turnabout = true })
	local _, unarmed = set("Turnabout", haeri, jroot, jball)
	local ap = BallPhysics.buildPath(armed.launch)
	local gp = BallPhysics.buildPath(groundArmed.launch)
	local up = BallPhysics.buildPath(unarmed.launch)
	check(armed.meta.hitType == "Spike" and armed.meta.turnabout and ap.landing.pos.Z * side < 0 and Court.inBounds(ap.landing.pos) and not ap.flags.netTouch and armed.meta.kmh > 90
		and gp.landing.pos.Z * side < 0 and unarmed.meta.hitType == "Set" and up.landing.pos.Z * side > 0,
		"Turnabout: armed, her jump set spins into a spike over the net (a low one dumps over); unarmed it stays a set", string.format("%.0f km/h, %s", armed.meta.kmh, describe(ap)))
	local _, groundSet = set(nil, SP, sroot, sball)
	local _, jumpSet = set(nil, SP, jroot, jball)
	local _, gA = BallPhysics.findApex(BallPhysics.buildPath(groundSet.launch), 0)
	local _, jA = BallPhysics.findApex(BallPhysics.buildPath(jumpSet.launch), 0)
	check(jA.Y > gA.Y + 3, "a jump set releases higher, so the set goes higher", string.format("apex %.1f vs %.1f studs", jA.Y, gA.Y))

	-- the bot setter's jump set (BotService.planJumpSet and its airborne sweep), off a real pass:
	-- it takes off so the top of its jump meets the ball; early or late by its timing noise it
	-- still has to connect, and the set has to reach the attack spot
	do
		local SE = Characters.stats("S", "SE")
		local g, P = Config.Player.Gravity, Config.Player
		local jh = Characters.jumpHeight(SE, GROUND)
		local function jump()
			local v, y, t, out = math.sqrt(2 * g * jh), 0, 0, {}
			local dt = 1 / 240
			local apexT = nil
			while t < 3 do
				local a = g
				if math.abs(v) < P.HangVelocityWindow then
					a = g * (1 - P.HangGravityCancel)
				end
				v = v - a * dt
				y = y + v * dt
				t = t + dt
				if not apexT and v <= 0 then
					apexT = t
				end
				table.insert(out, y)
				if y < 0 then
					break
				end
			end
			return out, dt, apexT
		end
		local ys, dt, tApex = jump()
		local function descentTo(path, now, y)
			local apexT, apexP = BallPhysics.findApex(path, now)
			if apexP and apexP.Y < y and apexP.Z * side > 0 then
				return apexT, apexP
			end
			return BallPhysics.findTime(path, now, function(pos, vel)
				return vel.Y < 0 and pos.Y <= y and pos.Z * side > 0
			end)
		end
		local recRoot = vec(0, GROUND, side * 18 * K)
		local _, pass = receive(recRoot, vec(0, recRoot.Y + Z.ReceiveIdealY, recRoot.Z - side * Z.ReceiveForward), { value = 120, max = 120 })
		local path = BallPhysics.buildPath(pass.launch)
		local y = GROUND + jh * 0.95 + Z.SetIdealY
		local tc, pc = descentTo(path, 0, y)
		local results = {}
		local _, pa = BallPhysics.findApex(path, 0)
		local allOk = tc ~= nil and pa ~= nil and pa.Y >= y + 0.3
		for _, err in ipairs({ 0, -0.075, 0.075 }) do
			local jumpAt = tc - tApex + err
			local hit = nil
			local tt = jumpAt
			while allOk and tt < path.landing.t do
				local i = math.floor((tt - jumpAt) / dt)
				local ry = GROUND + (i >= 1 and i <= #ys and math.max(0, ys[i]) or 0)
				local root = vec(0, ry, pc.Z)
				local pos, vel = BallPhysics.positionAt(path, tt), BallPhysics.velocityAt(path, tt)
				if vel.Y < 0 and (HitLogic.setZone(root, pos, side, SE)) and pos.Y - root.Y <= Z.SetIdealY + 0.4 then
					hit = { root = root, ball = pos, t = tt }
					break
				end
				tt = tt + 1 / 60
			end
			if hit then
				local okSet, setRes = HitLogic.compute({ action = "Set", t = hit.t, root = hit.root, ball = hit.ball, grounded = false, setType = "Open" },
					ctx({ touchNumber = 2, stats = SE, lastHit = { team = "Away", hitType = "Bump" } }))
				local sp = okSet and BallPhysics.buildPath(setRes.launch)
				local good = sp and sp.landing.pos.Z * side > 0 and not sp.flags.netTouch and setRes.meta.quality >= 0.5
				table.insert(results, string.format("%+.3fs: %s q%.2f lift %.1f", err, good and "ok" or "BAD", setRes.meta.quality or 0, hit.ball.Y - (GROUND + Z.SetIdealY)))
				allOk = allOk and good
			else
				table.insert(results, string.format("%+.3fs: MISS", err))
				allOk = false
			end
		end
		check(allOk, "a bot setter's jump set meets a real pass at the top of its jump, early or late by its timing noise", table.concat(results, ", "))

		-- Haeri (bots play her maxed): armed, the same plan turns her jump set into a real spike
		-- over the net, not the dump a ground set gives
		local haeriS = Characters.derive(Characters.fromRoster(Roster.get("haeri"), "max"))
		local hjh = Characters.jumpHeight(haeriS, GROUND)
		jh = hjh
		local hys, _, hApex = jump()
		local hy = GROUND + hjh * 0.95 + Z.SetIdealY
		local ht = descentTo(path, 0, hy)
		local hit = nil
		local tt = ht - hApex
		while tt < path.landing.t do
			local i = math.floor((tt - (ht - hApex)) / dt)
			local root = vec(0, GROUND + (i >= 1 and i <= #hys and math.max(0, hys[i]) or 0), pc.Z)
			local pos, vel = BallPhysics.positionAt(path, tt), BallPhysics.velocityAt(path, tt)
			if vel.Y < 0 and (HitLogic.setZone(root, pos, side, haeriS)) and pos.Y - root.Y <= Z.SetIdealY + 0.4 then
				hit = { root = root, ball = pos, t = tt }
				break
			end
			tt = tt + 1 / 60
		end
		local okT, tr = false, nil
		if hit then
			okT, tr = HitLogic.compute({ action = "Set", t = hit.t, root = hit.root, ball = hit.ball, grounded = false, setType = "Open" },
				ctx({ touchNumber = 2, stats = haeriS, ability = "Turnabout", turnabout = true, lastHit = { team = "Away", hitType = "Bump" } }))
		end
		local tp = okT and BallPhysics.buildPath(tr.launch)
		check(tp and tr.meta.turnabout and not tr.meta.downBall and tp.landing.pos.Z * side < 0 and Court.inBounds(tp.landing.pos) and not tp.flags.netTouch,
			"Haeri's Turnabout off a bot jump set is a real spike into their court", tp and string.format("contact %.2f m, %.0f km/h, %s", HitLogic.meters(hit.ball.Y), tr.meta.kmh or 0, describe(tp)) or "no contact")
	end

	-- Rising Sun: a low A at 0 points; every 3rd point lost adds a level; at 12 it beats YeJun
	local lv = {}
	for _, pts in ipairs({ 0, 2, 3, 6, 9, 12, 20 }) do
		table.insert(lv, HitLogic.sunLevel(pts))
	end
	local sun0 = HitLogic.effectiveStats(daon, "RisingSun", nil, { enemyPoints = 0 })
	local sun12 = HitLogic.effectiveStats(daon, "RisingSun", nil, { enemyPoints = 12 })
	local beats = true
	for _, k in ipairs(Config.Stats.Order) do
		beats = beats and sun12[k] > yejunC[k]
	end
	local soraA = Characters.derive(Characters.fromRoster(Roster.get("sora"), "max")) -- the A- wing spiker
	check(table.concat(lv, ",") == "0,0,1,2,3,4,4" and beats and sun12.ContactMaxM > yejunS.ContactMaxM and math.abs(sun0.ContactMaxM - soraA.ContactMaxM) < 0.2 and sun0.Attack <= soraA.Attack,
		"Rising Sun: a low A at 0 points, a level every 3 lost, and at 12 every stat beats a maxed YeJun", string.format("%.2f m at 0, %.2f m at 12 (YeJun %.2f m); ATK %d JMP %d DEF %d SPD %d", sun0.ContactMaxM, sun12.ContactMaxM, yejunS.ContactMaxM, sun12.Attack, sun12.Jump, sun12.Defense, sun12.Speed))

	-- Rally Cry: +12% to every stat of the team
	local rally = HitLogic.effectiveStats(SP, nil, nil, { teamBoost = true })
	local rr = apexRoot(rally, 3.5 * K)
	local _, boosted = spike(rr, ballAt(rr, Z.SpikeCenterDz, Z.SpikeCenterDy), { teamBoost = true })
	local _, normal = spike(sr, ballAt(sr, Z.SpikeCenterDz, Z.SpikeCenterDy))
	check(rally.Attack == math.floor(SP.Attack * 1.12 + 0.5) and rally.Jump > SP.Jump and rally.Speed > SP.Speed and boosted.meta.kmh > normal.meta.kmh,
		"Rally Cry: the whole team plays with +12% on every stat", string.format("ATK %d -> %d, spike %.0f -> %.0f km/h", SP.Attack, rally.Attack, normal.meta.kmh, boosted.meta.kmh))

	-- Counter Edge: dug balls fill the meter (a hard spike fills it, without draining); she scales
	-- with it and her next spike releases it
	local ines = Characters.derive(Characters.fromRoster(Roster.get("ines"), "max"))
	local recRoot = vec(0, GROUND, side * 18 * K)
	local recBall = vec(0, recRoot.Y + Z.ReceiveIdealY, recRoot.Z - side * Z.ReceiveForward)
	local fast = vec(0, -30 * K, side * 110 * K)
	local last = { team = "Home", hitType = "Spike", kmh = 140 }
	local _, dig = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.6 }, { lastHit = last, ballVel = fast, ability = "Counter", stats = ines })
	local _, dig2 = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.6 }, { lastHit = last, ballVel = fast, stats = ines })
	local ir = apexRoot(ines, 3.5 * K)
	local ib = ballAt(ir, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local _, empty = spike(ir, ib, { ability = "Counter", stats = ines, counter = 0 })
	local _, full = spike(ir, ib, { ability = "Counter", stats = ines, counter = 100 })
	local s0 = HitLogic.effectiveStats(ines, "Counter", nil, { counter = 0 })
	local s50 = HitLogic.effectiveStats(ines, "Counter", nil, { counter = 50 })
	local s100 = HitLogic.effectiveStats(ines, "Counter", nil, { counter = 100 })
	local hayun = Characters.derive(Characters.fromRoster(Roster.get("hayun"), "max"))
	local CE = Config.Abilities.Counter
	-- a served ball she digs (not heavy) fills it a little and drains like any receive
	local _, light = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.3 }, { lastHit = { team = "Home", hitType = "Underhand", noDrain = true, kmh = 45 }, ballVel = vec(0, -10 * K, side * 40 * K), ability = "Counter", stats = ines })
	check(dig.meta.drain == nil and (dig.meta.counterGain or 0) >= 100 and (dig2.meta.drain or 0) > 0 and light.meta.counterGain == CE.LightGain,
		"Counter Edge: one hard spike dug fills the meter with no guard lost; any other ball of theirs adds some", string.format("+%.0f from a %d km/h spike (vs %.1f guard), +%d from a serve", dig.meta.counterGain or 0, last.kmh, dig2.meta.drain or 0, light.meta.counterGain or 0))
	check(s0 == ines and ines.Attack < hayun.Attack and ines.Defense <= 130 and s50.Attack > s0.Attack and s50.Defense < s100.Defense
		and s100.Defense >= 195 and s100.Attack >= 205 and full.meta.kmh >= 150 and full.meta.kmh > empty.meta.kmh * 1.25 and full.meta.counterRelease == 100 and empty.meta.counterRelease == nil,
		"Counter Edge: a full meter makes her 210 / 200 and her spike releases it for a big hit", string.format("ATK %d / %d / %d, DEF %d / %d / %d (empty / half / full); spike %.0f -> %.0f km/h", s0.Attack, s50.Attack, s100.Attack, s0.Defense, s50.Defense, s100.Defense, empty.meta.kmh, full.meta.kmh))

	-- the server re-tunes a humanoid only when its boosted stats change (TeamService.refreshBoosts
	-- compares tables): no boost is the base table, the same boost the same cached table, and
	-- boosts stack (Rising Sun's points, then Rally Cry's multiplier)
	local b0 = HitLogic.effectiveStats(daon, "RisingSun", nil, { enemyPoints = 2 })
	local b1 = HitLogic.effectiveStats(daon, "RisingSun", nil, { enemyPoints = 4 })
	local b1b = HitLogic.effectiveStats(daon, "RisingSun", nil, { enemyPoints = 5 })
	local both = HitLogic.effectiveStats(daon, "RisingSun", nil, { enemyPoints = 6, teamBoost = true })
	local sun6 = HitLogic.effectiveStats(daon, "RisingSun", nil, { enemyPoints = 6 })
	check(b0 == daon and b1 ~= daon and b1 == b1b and both.Attack == math.floor((daon.Attack + 2 * Config.Abilities.RisingSun.PerLevel.Attack) * 1.12 + 0.5) and both.Attack > sun6.Attack,
		"boosts are shared tables (a humanoid is only re-tuned when a boost changes) and they stack", string.format("ATK %d, Lv1 %d, Lv2 %d, Lv2 + Rally %d", daon.Attack, b1.Attack, sun6.Attack, both.Attack))
end

print("== settings and the double approach ==")
do
	local Settings = require("Settings")
	local P, T = Config.Player, Config.Settings.Touch
	local clean = Settings.clean({
		doubleApproach = true,
		dramatic = "yes",
		shake = 7,
		bogus = 1,
		touchLayout = {
			A = { x = 0.2, y = 1.4, size = 9 },
			B = { x = 0 / 0, y = 0.5, size = 1 },
			C = { x = 0.5, y = 0.5 },
			Set = { x = 0.123456, y = 0.5, size = 1.05 },
			Zed = { x = 0.1, y = 0.1, size = 1 },
		},
	})
	local L = clean.touchLayout
	check(clean.doubleApproach == true and clean.dramatic == nil and clean.shake == 1 and clean.bogus == nil
		and L.A.y == 1 and L.A.size == T.MaxSize and L.B == nil and L.C == nil and L.Zed == nil and L.Set.x == 0.123 and L.Set.size == 1.05,
		"saved settings keep only known keys and sane values (no NaN; places and sizes clamped and rounded)")
	check(next(Settings.clean(nil)) == nil and next(Settings.clean({ touchLayout = {} }).touchLayout) == nil and Settings.clean({ touchLayout = 5 }).touchLayout == nil,
		"no settings, an empty layout (every button in its usual place) and junk all clean safely")
	-- the run-up between the two presses, for every character fresh and maxed
	local minMul, shortest, longest = math.huge, math.huge, 0
	for _, c in ipairs(Roster) do
		for _, lv in ipairs({ "max", false }) do
			local s = Characters.derive(Characters.fromRoster(c, lv or nil))
			minMul = math.min(minMul, P.ApproachRun * s.Approach)
			local run = s.WalkSpeed * P.ApproachRun * s.Approach * P.ApproachRunMax / SPM
			shortest = math.min(shortest, run)
			longest = math.max(longest, run)
		end
	end
	check(minMul > 1 and shortest >= 3 and longest <= 9,
		"double approach: the run-up is faster than walking for everyone, and a full one covers 3 to 9 m", string.format("x%.2f walk at least; %.1f to %.1f m in %.1f s", minMul, shortest, longest, P.ApproachRunMax))
end

print("== matchup intro and showcase ==")
do
	local I, MT = Config.Match.Intro, Config.Match
	local total = I.Open + I.TeamTime + I.Wipe + I.TeamTime + I.Wipe + I.VersusTime + I.Fade
	check(total + 0.3 <= MT.PreMatchTime, "the matchup intro (both teams, then VS) ends before the first serve, with room for lag", string.format("%.2f s of %.1f s", total, MT.PreMatchTime))
	local keys, dupes = {}, false
	for _, item in ipairs(Config.Cosmetics.Pose) do
		dupes = dupes or keys[item.Key] ~= nil
		keys[item.Key] = true
	end
	check(not dupes and Spins.default("Pose") == "Ready" and Spins.isBanner("Pose") and Config.Cosmetics.Attribute.Pose == "IntroPose",
		"intro poses are a cosmetic kind with their own banner; everyone starts with Ready")
	-- the client poses each key as Intro_<Key> (and the losing side as Intro_Tired)
	local f = io.open(ROOT .. "/src/client/Controllers/AnimationController.lua")
	local src = f and f:read("*a") or ""
	if f then
		f:close()
	end
	local missing = {}
	for _, item in ipairs(Config.Cosmetics.Pose) do
		if not string.find(src, "\tIntro_" .. item.Key .. " = {", 1, true) then
			table.insert(missing, item.Key)
		end
	end
	if not string.find(src, "\tIntro_Tired = {", 1, true) then
		table.insert(missing, "Tired")
	end
	check(#missing == 0, "every intro pose has its pose in AnimationController (Intro_<Key>)", table.concat(missing, ", "))
end

print("== leaderboards ==")
do
	local Leaderboards = require("Leaderboards")
	local v = Leaderboards.valuesOf({ bestStreak = 4, record = { wins = 12, kills = 140, aces = 9, blocks = -3 }, spent = { robux = 897, gifts = 399 } })
	check(v.wins == 12 and v.bestStreak == 4 and v.kills == 140 and v.aces == 9 and v.blocks == 0 and v.robux == 897 and v.gifts == 399 and #Leaderboards.Boards == 7,
		"seven boards: wins, best win streak, spike kills, aces and blocks from the career counters, Robux spent and Robux gifted")
	local ranked = Leaderboards.rank({ { userId = 5, value = 10 }, { userId = 2, value = 30 }, { userId = 9, value = 10 }, { userId = 1, value = 7 } }, 3)
	check(#ranked == 3 and ranked[1].userId == 2 and ranked[1].rank == 1 and ranked[2].userId == 5 and ranked[2].rank == 2 and ranked[3].userId == 9 and ranked[3].rank == 2, "best first, ties share a rank, only the top N", string.format("%d:%d %d:%d %d:%d", ranked[1].rank, ranked[1].value, ranked[2].rank, ranked[2].value, ranked[3].rank, ranked[3].value))
	local merged = Leaderboards.merge({ { userId = 1, value = 20, name = "A" }, { userId = 2, value = 15, name = "B" } }, { { userId = 2, value = 25, name = "B" }, { userId = 3, value = 5, name = "C" }, { userId = 4, value = 0, name = "D" } }, 10)
	check(#merged == 3 and merged[1].userId == 2 and merged[1].value == 25 and merged[3].userId == 3, "players in the server show their fresh numbers at once; zeros stay off")
end

print("== perks ==")
do
	-- each slot's id is saved under its key and written as that attribute: keys are unique, the
	-- scoring sound keeps the key saves already use, and every sound the owner named has a slot
	local seen, unique = {}, true
	for _, key in ipairs(Config.Perks.Order) do
		local def = Config.Perks[key]
		for _, slot in ipairs(def.Slots or { { Key = key } }) do
			unique = unique and not seen[slot.Key]
			seen[slot.Key] = true
		end
	end
	local S = Config.Perks.ScoreSound
	check(unique and S.Slots[1].Key == "ScoreSound" and seen.SoundSpike and seen.SoundJump and seen.ScoreImage and S.PassId ~= 0 and Config.Perks.ScoreImage.PassId ~= 0,
		"custom sounds: a unique slot per sound (scoring keeps its saved key; spike, jump and the rest), both game passes set", string.format("%d slots", #S.Slots))
end

print("== codes, lucky spins, daily rewards, gifts and events ==")
do
	local Economy = require("Economy")
	-- codes: any case and spacing, RELEASE pays, unknown ones don't
	local g, why, key = Economy.code("  ReLeAsE ", 100)
	local none, noneWhy = Economy.code("nope", 100)
	check(g ~= nil and key == "release" and g.VP > 0 and g.Gold > 0 and g.Lucky >= 1 and none == nil and noneWhy == "unknown",
		"the RELEASE code works typed any way and pays VP, Gold and a lucky spin; an unknown code pays nothing", g and Economy.describe(g) or tostring(why))
	-- a grant is made safe: no negatives, caps, real characters only, each once
	local clean = Economy.cleanGrant({ VP = -50, Gold = 1e12, Lucky = 2.7, Chars = { "dante", "dante", "nobody", 5 } })
	check(clean.VP == 0 and clean.Gold == Config.Admin.GiveMax.Gold and clean.Lucky == 2 and #clean.Chars == 1 and clean.Chars[1] == "dante",
		"a grant is cleaned: whole amounts from 0 to the caps, real characters once each")
	local prof = { vp = 10, gold = 0, owned = { Char = { dante = true } } }
	local added = Economy.apply(prof, Economy.cleanGrant({ VP = 5, Lucky = 3, Chars = { "dante", "seojin" } }))
	check(prof.vp == 15 and prof.lucky == 3 and prof.owned.Char.seojin and #added == 1 and added[1] == "seojin",
		"a grant adds VP, lucky spins and the characters you didn't have")
	-- lucky spins: no Commons, the top rarities several times likelier, and the rolls follow
	local lucky, normal = Spins.odds("Char", Spins.LuckyWeights), Spins.odds("Char")
	local rng = Random.new(5)
	local counts, n = {}, 20000
	for _ = 1, n do
		local item = Spins.item("Char", Spins.rollItem("Char", rng, Spins.LuckyWeights))
		counts[item.Rarity] = (counts[item.Rarity] or 0) + 1
	end
	check(lucky.Common == 0 and (counts.Common or 0) == 0 and lucky.Mythic >= 4 * normal.Mythic and lucky.Legendary >= 3 * normal.Legendary and math.abs((counts.Mythic or 0) / n - lucky.Mythic) < 0.005,
		"a lucky spin never drops a Common; Mythic and Legendary come several times as often",
		string.format("Mythic %.1f%% (usually %.1f%%), Legendary %.1f%% (usually %.1f%%)", lucky.Mythic * 100, normal.Mythic * 100, lucky.Legendary * 100, normal.Legendary * 100))
	local luckyTotal = 0
	for _, row in ipairs(Spins.table("Char", Spins.LuckyWeights)) do
		luckyTotal = luckyTotal + row.chance
	end
	check(math.abs(luckyTotal - 1) < 1e-9, "the lucky drop table adds up to 100%")
	-- daily rewards: one a day, the streak walks the week and starts over after a missed day
	local D = Config.Daily
	local first = Economy.daily(nil, 1000000)
	local soon = Economy.daily({ last = 1000000, streak = 1 }, 1000000 + 3600)
	local next = Economy.daily({ last = 1000000, streak = 1 }, 1000000 + D.Cooldown + 60)
	local missed = Economy.daily({ last = 1000000, streak = 5 }, 1000000 + D.StreakHours * 3600 + 60)
	local wrap = Economy.daily({ last = 1000000, streak = #D.Rewards }, 1000000 + D.Cooldown + 60)
	check(first.ready and first.day == 1 and not soon.ready and soon.day == 2 and next.ready and next.day == 2 and next.streak == 2
		and missed.ready and missed.day == 1 and missed.lapsed and wrap.day == 1 and wrap.streak == #D.Rewards + 1,
		"daily rewards: one per day, the streak moves along the week, a missed day starts it over, after the last day it goes round")
	-- the admin panel's events: 2x while on, never after
	local ev = { VP = 5000 }
	check(Economy.multiplier(ev, "VP", 4999) == Config.Admin.Multiplier and Economy.multiplier(ev, "VP", 5001) == 1 and Economy.multiplier(ev, "Gold", 4999) == 1
		and Economy.isDuration(15) and not Economy.isDuration(7) and Economy.isEvent("Gold") and not Economy.isEvent("XP"),
		"2x VP pays double while it runs and not after; only the panel's durations and events are accepted")
	-- every pack sold for Robux can be looked up by its product and gifted as what it sells
	local vp1, gold4, lucky2 = Economy.pack("VP", 1), Economy.pack("Gold", 4), Economy.pack("Lucky", 2)
	local byId = Economy.packByProduct(Config.Shop.Packs[1].Id)
	check(vp1 and gold4 and lucky2 and Economy.packGrant(vp1).VP == Config.Shop.Packs[1].VP and Economy.packGrant(gold4).Gold == Config.Shop.GoldPacks[4].Gold
		and Economy.packGrant(lucky2).Lucky == Config.Lucky.Packs[2].Lucky and byId and byId.kind == "VP" and byId.index == 1 and Economy.pack("VP", 9) == nil,
		"VP, Gold and lucky spin packs: found by product id, and each gives what it sells")
	-- the owner's products: lucky spins in 1, 3, 5 and 10, and 2x VP boosts on timers
	local counts = {}
	for _, p in ipairs(Config.Lucky.Packs) do
		table.insert(counts, p.Lucky)
	end
	local boostPack = Economy.pack("Boost", 2)
	check(table.concat(counts, ",") == "1,3,5,10" and boostPack and Economy.packGrant(boostPack).BoostVP == Config.Boosts.Packs[2].BoostVP,
		"lucky spins sell in 1, 3, 5 and 10; boosts sell by time", Economy.describe(Economy.packGrant(boostPack)))
	-- a boost starts when it's received, stacks on top of one that's running, and caps at MaxHold
	local B = Config.Boosts
	local t0 = 1000000
	local fresh = { boosts = {} }
	Economy.apply(fresh, Economy.cleanGrant({ BoostVP = 1800 }), t0)
	local stacked = fresh.boosts.VP
	Economy.apply(fresh, Economy.cleanGrant({ BoostVP = 1800 }), t0 + 600)
	local afterStack = fresh.boosts.VP
	local capped = Economy.extendBoost(t0 + B.MaxHold - 60, 3600, t0)
	local expired = Economy.extendBoost(t0 - 5000, 900, t0)
	check(stacked == t0 + 1800 and afterStack == t0 + 3600 and capped == t0 + B.MaxHold and expired == t0 + 900
		and Economy.boost(fresh, "VP", t0 + 3599) == B.Multiplier and Economy.boost(fresh, "VP", t0 + 3600) == 1,
		"2x VP boosts: start when received, stack on a running one, never hold more than a day, and end on time")
end

print("== player cards ==")
do
	local Cards = require("Cards")
	-- every card: a unique key, a goal, a known pattern, and an achievement it can be unlocked by
	local seen, ok = {}, true
	local patterns = { halftone = true, stripes = true, rays = true, stars = true }
	local stats0 = Cards.stats({ record = {} }, 0)
	for _, c in ipairs(Cards.list()) do
		ok = ok and not seen[c.Key] and type(c.Goal) == "string" and patterns[c.Look.Pattern] ~= nil and c.Look.Base ~= nil
		ok = ok and (c.Stat == nil or c.Stat == "rank" or stats0[c.Stat] ~= nil) and (c.Show == nil or c.Show == "rank" or stats0[c.Show] ~= nil)
		seen[c.Key] = true
	end
	local default = Cards.get(Cards.default())
	check(ok and default and not default.Stat and #Cards.list() >= 10, "player cards: each has its own look, goal and achievement; the default needs nothing", #Cards.list() .. " cards")
	-- they unlock by achievement: a streak, wins, spikes, MVPs, recruits, a leaderboard place
	local prof = { record = { wins = 120, kills = 40, aces = 3, blocks = 0, matches = 150, mvps = 30 }, winStreak = 2, bestStreak = 6, bestRank = { rank = 2, board = "kills" } }
	local st = Cards.stats(prof, 22)
	local function met(key)
		return Cards.met(Cards.get(key), st)
	end
	check(met("OnFire") and not met("Unstoppable") and met("Winner") and met("Champion") and not met("SpikeMachine") and met("MVP") and met("Collector") and not met("Veteran") and met("Top3") and not met("Number1"),
		"cards unlock by achievement: best streak 6 (not 10), 120 wins, 30 MVPs, 22 recruits, #2 on a board (not #1)")
	local have, need = Cards.progress(Cards.get("SpikeMachine"), st)
	local v1, l1 = Cards.display(Cards.get("OnFire"), st)
	local v2, l2 = Cards.display(Cards.get("Champion"), st)
	local v3, l3 = Cards.display(Cards.get("Top3"), st)
	check(have == 40 and need == 250 and v1 == "2" and l1 == "WIN STREAK" and v2 == "120" and l2 == "WINS" and v3 == "#2" and l3 == "SPIKE KILLS",
		"a card shows your number: the current win streak, the wins, or your place and the board", string.format("%s %s / %s %s / %s %s", v1, l1, v2, l2, v3, l3))
	local gold = Cards.look(Cards.get("Top3"), Color3.fromRGB(1, 2, 3), 1)
	local bronze = Cards.look(Cards.get("Top3"), Color3.fromRGB(1, 2, 3), 3)
	local team = Cards.look(Cards.get("Rookie"), Color3.fromRGB(1, 2, 3), nil)
	check(gold.Sweep == Config.Cards.RankColors[1] and bronze.Edge == Config.Cards.RankColors[3] and team.Sweep[1] == 1,
		"the Top 3 card is gold, silver or bronze by the place; the Rookie card takes the team colour")
end

print("== pity ==")
do
	local PT = Config.Spins.Pity
	local rng = Random.new(7)
	local function tierOf(key)
		return Spins.item("Char", key).Char.Tier
	end
	-- normal: one recruit short of pity, the next is an S- or S
	local pity = Spins.newPity()
	pity.normal = PT.Normal.Every - 1
	local k, how = Spins.pityRoll(pity, rng, false)
	check(how == "pity" and (tierOf(k) == "S" or tierOf(k) == "S-") and pity.normal == 0, "normal pity: the 200th recruit without an S tier is a random S tier, and the count starts over", k .. " " .. tierOf(k))
	-- across a long run nobody waits past 200 for an S tier
	local worst, since = 0, 0
	local run = Spins.newPity()
	for _ = 1, 3000 do
		local key = Spins.pityRoll(run, rng, false)
		since = since + 1
		if string.sub(tierOf(key), 1, 1) == "S" then
			worst = math.max(worst, since)
			since = 0
		end
	end
	check(worst <= PT.Normal.Every, "3,000 recruits: never more than 200 between S tiers", "longest wait " .. worst)
	-- lucky: the first pity is a random S+; when it isn't your pick, the next one is your pick
	local lp = Spins.newPity()
	lp.pick = Spins.pityPool("Lucky")[1]
	local picks = {}
	for i = 1, 6 do
		lp.lucky = PT.Lucky.Every - 1
		local key, h = Spins.pityRoll(lp, rng, true)
		picks[i] = { key = key, how = h }
	end
	local ok = true
	for i, pk in ipairs(picks) do
		ok = ok and tierOf(pk.key) == "S+" and (pk.how == "pity" or pk.how == "pick")
		if pk.how == "pity" and pk.key ~= lp.pick then
			ok = ok and (picks[i + 1] == nil or (picks[i + 1].how == "pick" and picks[i + 1].key == lp.pick))
		end
	end
	check(ok and lp.lucky == 0 and picks[1].how == "pity", "lucky pity: the 50th lucky spin is an S+, random first, then your pick after a random one that wasn't it")
	local owedNoPick = Spins.newPity()
	owedNoPick.lucky = PT.Lucky.Every - 1
	Spins.pityRoll(owedNoPick, rng, true)
	local clean = Spins.cleanPity({ normal = 9999, lucky = -3, owed = true, pick = "riku" })
	check(owedNoPick.owed == true and clean.normal == PT.Normal.Every - 1 and clean.lucky == 0 and clean.owed and clean.pick == nil and Spins.isPityPick("yejun") and not Spins.isPityPick("hayun"),
		"with no pick chosen the pick stays owed; saved pity is made safe (only an S+ can be the pick)")
end

print("== the third wave ==")
do
	local yeonho = Characters.derive(Characters.fromRoster(Roster.get("yeonho"), "max"))
	local sr = apexRoot(yeonho, 3.5 * K)
	local b = ballAt(sr, 0.9, 0)
	local _, pl = spike(sr, b, { stats = yeonho, ability = "Plunge" })
	local _, nopl = spike(sr, b, { stats = yeonho })
	local pp, np = BallPhysics.buildPath(pl.launch), BallPhysics.buildPath(nopl.launch)
	local function angle(path)
		local v = path.segs[#path.segs].v
		local t = path.landing.t - path.segs[#path.segs].t0
		local vy = v.Y + path.segs[#path.segs].a.Y * t
		return math.deg(math.atan(-vy / math.max(math.abs(v.Z), 0.01)))
	end
	check(pl.meta.plunge and not nopl.meta.plunge and oppDepth(pp) < oppDepth(np) and angle(pp) > angle(np) + 5 and pl.meta.kmh > nopl.meta.kmh,
		"Plunge Spin: a clean spike lands nearer the net, faster, and dives in steeper", string.format("%.1f vs %.1f m deep, %.0f vs %.0f degrees in, %.0f vs %.0f km/h", oppDepth(pp) / SPM, oppDepth(np) / SPM, angle(pp), angle(np), pl.meta.kmh, nopl.meta.kmh))
	local mateus, junseo, yejun = Roster.get("mateus"), Roster.get("junseo"), Roster.get("yejun")
	local tallest, shortestWS = true, true
	for _, c in ipairs(Roster) do
		tallest = tallest and (c == mateus or c.Height < mateus.Height)
		shortestWS = shortestWS and (c.Role ~= "WS" or c == junseo or c.Height > junseo.Height)
	end
	check(tallest and mateus.Ability == nil and shortestWS and junseo.Jump < yejun.Jump and junseo.Jump >= 185,
		"Mateus is the tallest (no ability); Junseo the shortest wing spiker, with a jump just under YeJun's", string.format("%d cm; %d cm, jump %d vs %d", mateus.Height, junseo.Height, junseo.Jump, yejun.Jump))
	-- the height cap went up for Mateus without changing anyone else's hit zone (1.08 at 210 cm)
	local gaeul = Characters.derive(Characters.fromRoster(Roster.get("gaeul"), "max"))
	local m = Characters.derive(Characters.fromRoster(mateus, "max"))
	local ye = Characters.derive(Characters.fromRoster(yejun, "max"))
	check(math.abs(gaeul.Reach - (0.94 + 0.14 * (204 - 165) / 45)) < 1e-9 and m.Reach > 1.08 and m.contactMaxStuds < ye.contactMaxStuds and m.contactMaxStuds < gaeul.contactMaxStuds and m.BlockPower > gaeul.BlockPower and mateus.Attack < gaeul.Attack,
		"a 216 cm Mateus built to block: everyone else's hit zone is as before, his is the biggest; YeJun and Gaeul still hit higher, he blocks harder and spikes softer", string.format("zone %.3f, contact %.2f m (YeJun %.2f, Gaeul %.2f)", m.Reach, m.ContactMaxM, ye.ContactMaxM, gaeul.ContactMaxM))
	-- Iron Wall: a perfect block wherever the attack meets the hands, even above the usual box,
	-- shut straight down onto their side
	local broot = vec(0, GROUND + Characters.jumpHeight(gaeul, GROUND), side * 0.3 * K)
	local high = vec(0, broot.Y + Z.BlockReachUp + 1.0, side * 0.2)
	local lastSpike = { team = "Home", hitType = "Spike", kmh = 160, pierce = true }
	local okPlain = HitLogic.compute({ action = "Block", t = 0, root = broot, ball = high, grounded = false }, ctx({ stats = gaeul, ability = "IronWall", lastHit = lastSpike, ballVel = vec(0, -8, side * 40) }))
	local okIron, iw = HitLogic.compute({ action = "Block", t = 0, root = broot, ball = high, grounded = false }, ctx({ stats = gaeul, ability = "IronWall", ironWall = true, lastHit = lastSpike, ballVel = vec(0, -8, side * 40) }))
	local ip = okIron and BallPhysics.buildPath(iw.launch)
	local land = ip and ip.landing.pos.Z * -side
	check(not okPlain and okIron and iw.meta.perfectBlock and iw.meta.quality == 1 and land > 0 and land <= Config.Court.SideDepth,
		"Iron Wall: a perfect block even off the top of the hands, shut down into their court", land and string.format("lands %.1f m past the net", land / SPM) or "no block")
end

print("== determinism ==")
do
	local root = apexRoot(SP, 4 * K)
	local b = ballAt(root, 0.9, 0.3)
	local _, a = spike(root, b, { seq = 99, ability = "Thunder" })
	local _, c = spike(root, b, { seq = 99, ability = "Thunder" })
	local pa, pc = BallPhysics.buildPath(a.launch), BallPhysics.buildPath(c.launch)
	check(pa.landing.t == pc.landing.t and (pa.landing.pos - pc.landing.pos).Magnitude == 0, "prediction is bit-identical to authority")
end

print(string.format("\n%d failure(s)", failures))
os.exit(failures == 0 and 0 or 1)
