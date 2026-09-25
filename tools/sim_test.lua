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
local C, Z, H = Config.Court, Config.Zones, Config.Hits
local SPM = Config.Scale.StudsPerMeter

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
	local root = apexRoot(SP, 3.5)
	local ok, res = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy))
	local path = BallPhysics.buildPath(res.launch)
	check(ok and res.meta.kmh > 136 and res.meta.kmh <= 141, "perfect contact at the apex", string.format("%.1f km/h, %.2f m", res.meta.kmh, res.meta.height))
	check(not path.flags.netTouch and path.landing.pos.Z * side < 0 and Court.inBounds(path.landing.pos), "perfect spike lands in", describe(path))
	check(oppDepth(path) > 20, "clean contact goes deep", string.format("%.1f studs deep", oppDepth(path)))
	local lowRoot = root - vec(0, 3.2, 0) -- mistimed: hit on the way up
	local ok2, res2 = spike(lowRoot, ballAt(lowRoot, 1.9, 1.3))
	check(ok2 and res2.meta.kmh >= 108 and res2.meta.kmh < 124, "edge contact below the apex is the weak end", string.format("%.1f km/h, contact %.2f", ok2 and res2.meta.kmh or 0, ok2 and res2.meta.contact or 0))
end

print("== spike direction from relative position ==")
do
	local root = apexRoot(SP, 3.0)
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
	local farRoot = apexRoot(SP, 10) -- far off the net, reaching for a ball ahead
	local ok3, res3 = spike(farRoot, ballAt(farRoot, 2.3, 1.2))
	local path3 = BallPhysics.buildPath(res3.launch)
	check(ok3 and res3.meta.quality < H.SpikeAssistQuality and (path3.flags.netTouch or path3.landing.pos.Z * side > 0), "sloppy steep swing from deep finds the net", string.format("q=%.2f %s", res3.meta.quality, describe(path3)))
end

print("== Thunder Spiker (target 160-200 above 4.00 m) ==")
do
	local root = apexRoot(SP, 3.5)
	local ok, res = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), { ability = "Thunder" })
	check(ok and res.meta.thunder and res.meta.kmh >= 185 and res.meta.kmh <= 200.5, "perfect thunder at 4.15 m", string.format("%.1f km/h at %.2f m", res.meta.kmh, res.meta.height))
	local low = root - vec(0, 0.65, 0) -- contact just over 4.00 m, a bit ahead of the hand
	local ok2, res2 = spike(low, ballAt(low, 1.4, 0.25), { ability = "Thunder" })
	check(ok2 and res2.meta.thunder and res2.meta.kmh >= 160 and res2.meta.kmh < 185, "scrappy thunder just over 4.00 m", string.format("%.1f km/h at %.2f m", res2.meta.kmh, res2.meta.height))
	local path = BallPhysics.buildPath(res.launch)
	check(Court.inBounds(path.landing.pos) and not path.flags.netTouch, "thunder spike lands in", describe(path))
	local A = Characters.stats("A")
	local rootA = apexRoot(A, 3.5)
	local ok3, res3 = spike(rootA, ballAt(rootA, Z.SpikeCenterDz, 0), { ability = "Thunder", stats = A })
	check(ok3 and not res3.meta.thunder, "maxed A at 185 cm can't reach 4.00 m", string.format("max %.2f m, %.1f km/h", res3.meta.height, res3.meta.kmh))
	local tallA = Characters.stats("A", "WS", 200)
	local rootT = apexRoot(tallA, 3.5)
	local ok4, res4 = spike(rootT, ballAt(rootT, Z.SpikeCenterDz, 0), { ability = "Thunder", stats = tallA })
	check(ok4 and res4.meta.thunder, "a 200 cm A can", string.format("%.2f m, %.1f km/h", res4.meta.height, res4.meta.kmh))
	local shortS = Characters.stats("S+", "WS", 170)
	local rootS = apexRoot(shortS, 3.5)
	local ok5, res5 = spike(rootS, ballAt(rootS, Z.SpikeCenterDz, 0), { ability = "Thunder", stats = shortS })
	check(ok5 and not res5.meta.thunder, "a 170 cm S+ can't", string.format("%.2f m, %.1f km/h", res5.meta.height, res5.meta.kmh))
end

print("== Azure Dragon ==")
do
	local root = apexRoot(SP, 3.5)
	local b = ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local _, none = spike(root, b, { ability = "Azure" }, { energy = 0 })
	local _, half = spike(root, b, { ability = "Azure" }, { energy = 0.5 })
	local _, full = spike(root, b, { ability = "Azure" }, { energy = 1.0 })
	check(full.meta.kmh >= 190 and full.meta.kmh <= 205 and full.meta.pierce, "full bar = max power and pierce", string.format("0%%: %.0f  50%%: %.0f  100%%: %.0f km/h", none.meta.kmh, half.meta.kmh, full.meta.kmh))
	local okO, over = spike(root, b, { ability = "Azure" }, { energy = 1.3 })
	local path = BallPhysics.buildPath(over.launch)
	check(over.meta.overcharge and not Court.inBounds(path.landing.pos), "overcharge flies out", describe(path))
end

print("== tiers, builds and upgrades ==")
do
	local prev = 0
	local okAll = true
	local line = {}
	for _, tier in ipairs({ "D-", "C", "B", "A", "S", "S+" }) do
		local st = Characters.stats(tier)
		local root = apexRoot(st, 3.5)
		local ok, res = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = st })
		okAll = okAll and ok and res.meta.kmh > prev
		prev = ok and res.meta.kmh or prev
		table.insert(line, string.format("%s %.0f/%.2fm", tier, ok and res.meta.kmh or 0, ok and res.meta.height or 0))
	end
	check(okAll, "maxed builds: power and hitting point rise with tier", table.concat(line, "  "))
	local a = Characters.autoBuild("A", "WS", 185)
	check(a.Attack == 155 and a.Jump == 155 and a.Defense == 120 and a.Speed == 120, "A-rank wing spiker build matches The Spike's 155/120/120/155", string.format("%d/%d/%d/%d", a.Attack, a.Defense, a.Speed, a.Jump))
	local fresh = Characters.newBuild("S+", Random.new(3))
	local freshStats = Characters.derive("S+", fresh)
	local maxStats = Characters.stats("S+", "WS", fresh.Height)
	check(freshStats.Power < 0.6 and freshStats.ContactMaxM < maxStats.ContactMaxM - 0.6, "a fresh S+ is far below its cap until upgraded", string.format("fresh %d attack, %.2f m reach; maxed %.2f m", fresh.Attack, freshStats.ContactMaxM, maxStats.ContactMaxM))
	local b = { Height = 185, Attack = 170, Defense = 140, Speed = 140, Jump = 170 }
	check(Characters.raisable("S+", b, "Attack", 10) == 0 and Characters.raisable("S+", { Height = 185, Attack = 100, Defense = 100, Speed = 100, Jump = 100 }, "Jump", 200) == 75, "upgrades stop at the stat cap and the tier total", string.format("total cap left %d", Characters.raisable("S+", b, "Attack", 10)))
	local cheat = Characters.sanitize("B", { Height = 400, Attack = 999, Defense = 999, Speed = 999, Jump = 999 })
	check(cheat.Height == Config.Height.Max and cheat.Attack <= 140 and Characters.total(cheat) <= 500, "sanitize clamps a forged build", string.format("%d cm, %d total", cheat.Height, Characters.total(cheat)))
end

print("== receives, stamina, slides ==")
local incoming = vec(0, -30, side * 110) -- ~140 km/h spike arriving
local lastSpike = { team = "Home", hitType = "Spike", kmh = 140 }
local function receive(root, ball, stam, extraInput, extraCtx)
	local input = { action = "Bump", t = 0, root = root, ball = ball, vy = 0, grounded = true, stanceAge = 0.2 }
	for k, v in pairs(extraInput or {}) do input[k] = v end
	local c = { ballVel = incoming, lastHit = lastSpike, touchNumber = 1, thirdTouch = false, stamina = stam }
	for k, v in pairs(extraCtx or {}) do c[k] = v end
	return HitLogic.compute(input, ctx(c))
end
do
	local root = vec(0, GROUND, side * 18)
	local ball = vec(0, root.Y + Z.ReceiveIdealY, root.Z - side * Z.ReceiveForward)
	local ok, res = receive(root, ball, { value = 120, max = 120 })
	local path = BallPhysics.buildPath(res.launch)
	local _, apexP = BallPhysics.findApex(path, 0)
	local tArr, pArr = BallPhysics.findTime(path, 0.05, function(p, v) return v.Y < 0 and p.Y <= H.PassArriveY end)
	check(ok and res.meta.perfect and res.meta.drain < 4, "perfect receive barely drains stamina", string.format("score %d, drain %.1f", res.meta.score, res.meta.drain or 0))
	check(apexP.Y >= 21 and pArr and math.abs(pArr.Z - side * H.SetterDepth) < 1.5, "receive goes high to the setter", string.format("apex %.1f (%.1f m), arrives z=%.1f after %.2fs", apexP.Y, apexP.Y / SPM, pArr and pArr.Z or 0, tArr or 0))
	local ok2, res2 = receive(root, ball, { value = 120, max = 120 }, { stanceAge = 0.75 })
	check(ok2 and not res2.meta.perfect and (res2.meta.drain or 0) > 12, "late-pressed receive drains full stamina", string.format("%s %d, drain %.1f", res2.meta.grade, res2.meta.score, res2.meta.drain or 0))
	local ok3, res3 = receive(root, ball, { value = 25, max = 120 }, { stanceAge = 0.75 })
	check(ok3 and res3.meta.quality < res2.meta.quality, "red stamina makes receives unreliable", string.format("q %.2f vs %.2f", res3.meta.quality, res2.meta.quality))
	local ok4, res4 = receive(root, ball, { value = 6, max = 120 }, { stanceAge = 0.75 })
	check(ok4 and res4.meta.breaks and res4.meta.shank, "the ball that empties the bar breaks the guard", res4.meta.grade)
	local ok5, res5 = receive(root, ball, { value = 0, max = 120 })
	local path5 = BallPhysics.buildPath(res5.launch)
	check(ok5 and res5.meta.fail and not Court.inBounds(path5.landing.pos), "broken guard can't stop a strong spike", describe(path5))
	local slideRoot = vec(0, GROUND, side * 16)
	local slideBall = vec(0, slideRoot.Y - 2.2, slideRoot.Z - side * 4.2)
	local ok6, res6 = receive(slideRoot, slideBall, { value = 0, max = 120 }, { diving = true })
	local path6 = BallPhysics.buildPath(res6.launch)
	check(ok6 and not res6.meta.fail and not res6.meta.drain and path6.landing.pos.Z * side > 0, "slide receive works on a broken guard, no drain", string.format("q %.2f %s", res6.meta.quality, describe(path6)))
	local softHit = { team = "Home", hitType = "Block", outcome = "Soft", noDrain = true }
	local ok7, res7 = receive(root, ball, { value = 120, max = 120 }, { stanceAge = 0.75 }, { lastHit = softHit })
	check(ok7 and not res7.meta.drain, "soft-block deflection doesn't drain")
end

print("== bumps and sets stay on your side until the third touch ==")
do
	local over = 0
	local worst = 99
	for i = 1, 60 do
		local root = vec(0, GROUND, side * (8 + (i % 20)))
		local ball = vec(0, root.Y - 2.0 + (i % 7) * 0.5, root.Z - side * (((i % 9) - 4) * 0.8))
		local ok, res = receive(root, ball, { value = 120, max = 120 }, { stanceAge = (i % 10) * 0.08 }, { seq = i, touchNumber = 1 + (i % 2) })
		if ok then
			local path = BallPhysics.buildPath(res.launch)
			if path.landing.pos.Z * side < 0 or path.flags.netTouch then over = over + 1 end
			worst = math.min(worst, path.landing.pos.Z * side)
		end
	end
	check(over == 0, "60 random first/second touches: none go over", string.format("closest landing %.1f studs from the net", worst))
	local root = vec(0, GROUND, side * 12)
	local ball = vec(0, root.Y - 1, root.Z - side * 0.6)
	local ok, res = receive(root, ball, { value = 120, max = 120 }, {}, { thirdTouch = true, touchNumber = 3, lastHit = { team = "Away", hitType = "Set" }, ballVel = vec(0, -12, 0) })
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
	check(apexP.Y >= 20 and tA and tA > 1.2 and math.abs(pA.Z - side * H.OpenDepth) < 1.2, "open set: high, hangs, arrives at the attack spot", string.format("apex %.1f (%.1f m), %.2fs to hitting height at z=%.1f", apexP.Y, apexP.Y / SPM, tA or 0, pA and pA.Z or 0))
	local okB, resB = HitLogic.compute({ action = "Bump", t = 0, root = vec(0, GROUND, side * 6), ball = vec(0, GROUND - 1, side * 5.4), grounded = true, stanceAge = 0.2 }, ctx({ touchNumber = 2, lastHit = { team = "Away", hitType = "Bump" } }))
	check(okB and resB.meta.hitType == "Set" and resB.meta.underhand, "second-touch bump becomes an underhand set")
end

print("== serves ==")
do
	local serveZ = side * (C.SideDepth + 3.5)
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
	local ok, res = block({ team = "Away", hitType = "Spike", kmh = 110 }, vec(0, -25, bside * 90))
	local path = BallPhysics.buildPath(res.launch)
	check(ok and res.meta.outcome == "Stuff" and path.landing.pos.Z * side > 0, "S+ blocker stuffs a 110 km/h spike", describe(path))
	local ok2, res2 = block({ team = "Away", hitType = "Spike", kmh = 200, pierce = true }, vec(0, -25, bside * 150))
	check(ok2 and res2.meta.outcome ~= "Stuff" and res2.meta.noDrain, "full Azure pierces the block (soft touch, no drain)", res2.meta.outcome)
end

print("== determinism ==")
do
	local root = apexRoot(SP, 4)
	local b = ballAt(root, 0.9, 0.3)
	local _, a = spike(root, b, { seq = 99, ability = "Thunder" })
	local _, c = spike(root, b, { seq = 99, ability = "Thunder" })
	local pa, pc = BallPhysics.buildPath(a.launch), BallPhysics.buildPath(c.launch)
	check(pa.landing.t == pc.landing.t and (pa.landing.pos - pc.landing.pos).Magnitude == 0, "prediction is bit-identical to authority")
end

print(string.format("\n%d failure(s)", failures))
os.exit(failures == 0 and 0 or 1)
