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
Color3 = { fromRGB = function(r, g, b) return { r, g, b, R = r / 255, G = g / 255, B = b / 255 } end, new = function(r, g, b) return { r, g, b, R = r, G = g, B = b } end }
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

print("== under the net ==")
do
	-- (the owner, 2026-10-25: "down tilts and sets can go under the net and does NOT count a fault"):
	-- the path marks when it went under, and HitService refuses every touch from then on
	local tae = Characters.derive(Characters.fromRoster(Roster.get("taeha"), "max"))
	local n, marked = 0, 0
	for _, ab in ipairs({ "ZeroPoint", false }) do
		for _, dist in ipairs({ 1.5, 2.5, 4 }) do
			local root = apexRoot(tae, dist * SPM)
			local ok, res = spike(root, ballAt(root, 3, 0), { ability = ab or nil, stats = tae })
			local path = ok and BallPhysics.buildPath(res.launch)
			if path and path.flags.underNet then
				n = n + 1
				local t = path.flags.underNetT
				local p = t and BallPhysics.positionAt(path, t)
				if t and t < path.landing.t and math.abs(p.Z) < 1 and p.Y < C.NetBottom then
					marked = marked + 1
				end
			end
		end
	end
	check(n >= 3 and marked == n, "a down tilt under the net is marked dead from the moment it goes under", string.format("%d of %d under-net spikes marked", marked, n))
end

print("== beginner mode ==")
do
	-- (the owner, 2026-10-25: "beginner mode... slight jump assistance... you cant control your aim,
	-- rather you always hit in square in the middle so it usually goes midcourt")
	local B = Config.Beginner
	local root = apexRoot(SP, 3.0 * K)
	local mid = C.SideDepth * B.Depth
	local worst = 0
	for _, dz in ipairs({ -0.1, 1.0, 2.2 }) do
		local ok, res = spike(root, ballAt(root, dz, 0), nil, { beginner = true })
		local path = ok and BallPhysics.buildPath(res.launch)
		worst = math.max(worst, path and math.abs(oppDepth(path) - mid) or 999)
	end
	check(worst <= B.DepthJitter + 1.5, "beginner spikes all go midcourt, wherever the ball meets the hand", string.format("furthest %.1f studs off the middle (%.1f)", worst, mid))
	-- a ball just past the usual reach: only a beginner hits it
	local far = ballAt(root, Z.SpikeCenterDz, 0)
	local reach, okN, okB = nil, false, false
	for i = 0, 60 do
		local dy = i * 0.1
		local b = vec(far.X, far.Y + dy, far.Z)
		local n = spike(root, b)
		local bb = spike(root, b, nil, { beginner = true })
		if not n and bb then reach, okN, okB = dy, true, true break end
	end
	check(okN and okB, "beginner spikes reach a little further", reach and string.format("a ball %.1f studs over the sweet spot", reach) or "no difference")
	-- a mistimed, scrappy swing (under the top, the ball at the edge of the hand) still hits with some power
	local low = root - vec(0, 3.2, 0)
	local _, rn = spike(low, ballAt(low, 1.9, 1.3))
	local _, rb = spike(low, ballAt(low, 1.9, 1.3), nil, { beginner = true })
	check(rn and rb and rb.meta.kmh > rn.meta.kmh + 2, "a beginner's scrappy, mistimed swing hits harder than usual", string.format("%.0f vs %.0f km/h", rb and rb.meta.kmh or 0, rn and rn.meta.kmh or 0))
	local _, auto = spike(root, ballAt(root, 2.2, 0), { auto = true }, { beginner = true })
	check(auto and not auto.meta.beginner, "bots never play in beginner mode")
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
	-- Dragon Surge (the owner's buff for Seojin): a full bar about 215-230 km/h, and digging it
	-- costs Config.Abilities.Azure.FullDrainMul more
	local AZ = Config.Abilities.Azure
	check(full.meta.kmh >= 225 and full.meta.kmh <= 240 and full.meta.pierce and math.abs(full.meta.tierDrain / half.meta.tierDrain - AZ.FullDrainMul) < 0.001,
		"full bar = max power, pierce and a heavier dig (Dragon Surge)", string.format("0%%: %.0f  50%%: %.0f  100%%: %.0f km/h", none.meta.kmh, half.meta.kmh, full.meta.kmh))
	local okO, over = spike(root, b, { ability = "Azure" }, { energy = 1.3 })
	local path = BallPhysics.buildPath(over.launch)
	check(over.meta.overcharge and not Court.inBounds(path.landing.pos), "overcharge flies out", describe(path))
end

print("== Corona (Laith) ==")
do
	local CO = Config.Abilities.Corona
	local laith = Characters.derive(Characters.fromRoster(Roster.get("laith"), "max"))
	-- the flare: every stat up while it's on, down by his uses while it's off, back after a timeout
	local on = HitLogic.effectiveStats(laith, "Corona", nil, { coronaOn = true, coronaStacks = 3 })
	local off3 = HitLogic.effectiveStats(laith, "Corona", nil, { coronaStacks = 3 })
	local off99 = HitLogic.effectiveStats(laith, "Corona", nil, { coronaStacks = 99 })
	local fresh = HitLogic.effectiveStats(laith, "Corona", nil, { coronaStacks = 0 })
	local function near(a, b)
		return math.abs(a - b) <= 1
	end
	check(near(on.Attack, laith.Attack * (1 + CO.Boost)) and near(on.Jump, laith.Jump * (1 + CO.Boost)) and near(off3.Defense, laith.Defense * (1 - 3 * CO.PenaltyPer))
		and near(off99.Speed, laith.Speed * (1 - CO.MaxStacks * CO.PenaltyPer)) and fresh == laith and on.ContactMaxM > laith.ContactMaxM,
		"Corona: every stat up while it's on; after it, 1% down for each use (12 at most), none before",
		string.format("ATK %d on, %d after 3 uses, %d after 12 (base %d)", on.Attack, off3.Attack, off99.Attack, laith.Attack))

	-- Sundive: a spike he dropped onto hits harder the further he dropped, up to DiveBoost; a dive
	-- met under the top of his jump isn't punished for the height; the AI gets AutoDive of it. The
	-- owner's video: Lucas's plain spikes about 150 km/h, his full dive 252
	local root = apexRoot(laith, 3.5 * K)
	local low = root - vec(0, 2.5, 0) -- a dive meets it lower than his apex
	local function laithSpike(r, drop, extra)
		local c = { ability = "Corona", stats = laith, seq = 7 }
		for k, v in pairs(extra or {}) do c[k] = v end
		return spike(r, ballAt(r, Z.SpikeCenterDz, Z.SpikeCenterDy), c, { sundive = drop })
	end
	local _, plain = laithSpike(root, 0)
	local _, lowPlain = laithSpike(low, 0)
	local _, halfDive = laithSpike(low, (CO.DiveMinDrop + CO.DiveFullDrop) / 2)
	local _, fullDive = laithSpike(low, CO.DiveFullDrop + 5)
	local _, flared = laithSpike(low, CO.DiveFullDrop, { coronaOn = true })
	local _, auto = laithSpike(root, 0, { auto = true })
	-- his jump serve dives too (the owner: "on serves for laith i cant dash")
	local function laithServe(drop)
		local c = ctx({ ability = "Corona", stats = laith, seq = 7, touchNumber = 1 })
		return HitLogic.compute({ action = "Serve", t = 0, root = low, ball = ballAt(low, Z.SpikeCenterDz, Z.SpikeCenterDy), vy = 0, grounded = false, sundive = drop }, c)
	end
	local okP, servePlain = laithServe(0)
	local okD, serveDive = laithServe(CO.DiveFullDrop)
	-- (and a serve without a dive still gets the AI's share: his serves were weak, 2026-10-25)
	check(okP and okD and servePlain.meta.hitType == "JumpServe" and serveDive.meta.dive == 1 and serveDive.meta.kmh > servePlain.meta.kmh * 1.2 and math.abs((servePlain.meta.dive or 0) - CO.AutoDive) < 1e-6,
		"Sundive works on his jump serve too (a plain one gets the AI's share of it)", string.format("%.0f km/h plain, %.0f off a full dive", servePlain.meta.kmh, serveDive.meta.kmh))
	check(not plain.meta.dive and lowPlain.meta.kmh < plain.meta.kmh and halfDive.meta.dive == 0.5 and fullDive.meta.dive == 1
		and fullDive.meta.kmh > plain.meta.kmh * 1.25 and fullDive.meta.kmh > halfDive.meta.kmh + 15 and auto.meta.kmh > plain.meta.kmh and not auto.meta.dive
		and flared.meta.kmh > 200 and flared.meta.kmh < 275,
		"Sunfire and Sundive: every spike +14%, and the further he drops onto it the harder (up to +38%), even met below his apex; with Corona on, past 200",
		string.format("apex %.0f, low %.0f, half dive %.0f, full dive %.0f (with Corona %.0f), AI %.0f km/h", plain.meta.kmh, lowPlain.meta.kmh, halfDive.meta.kmh, fullDive.meta.kmh, flared.meta.kmh, auto.meta.kmh))
	local path = BallPhysics.buildPath(fullDive.launch)
	check(Court.inBounds(path.landing.pos) and not path.flags.netTouch, "a full Sundive spike lands in", describe(path))
	-- the path (the owner's video): from a Sun Leap's top behind the end line to the ball by the net
	-- is within reach, all but straight, in about a tenth of a second, and a drop that long earns
	-- the whole bonus
	local d0, d2 = vec(0, 30, side * (C.SideDepth + 2)), vec(0, 14, side * 3)
	local dc = HitLogic.diveControl(d0, d2)
	local dT = (d2 - d0).Magnitude * 1.15 / CO.DiveSpeedMax
	local bow = HitLogic.divePoint(d0, dc, d2, 0.5).Y - (d0.Y + d2.Y) / 2
	check((d2 - d0).Magnitude <= CO.DiveMaxDist and bow > 0 and bow < 0.1 * (d2 - d0).Magnitude and (HitLogic.divePoint(d0, dc, d2, 1) - d2).Magnitude < 0.001 and HitLogic.diveFraction(d0.Y - d2.Y) == 1 and dT < 0.15,
		"Sundive reaches from a leap behind the end line to the net, all but straight, in a blink, for the whole bonus", string.format("%.1f studs in %.2f s", (d2 - d0).Magnitude, dT))
	-- the dash (the owner: "i still think the dash should be faster"): however early he presses, he
	-- hangs, then the dash itself is over in a few frames and lands as the ball arrives
	local w1, dash1 = HitLogic.diveTiming(0.8)
	local w2, dash2 = HitLogic.diveTiming(0.04)
	check(dash1 <= 0.07 and math.abs(w1 + dash1 - 0.8) < 1e-9 and w2 == 0 and math.abs(dash2 - 0.04) < 1e-9 and (d2 - d0).Magnitude * 1.15 / dash1 > 600,
		"Sundive's dash is over in a few frames, after a hang, arriving with the ball",
		string.format("pressed 0.8 s early: hangs %.2f s, dashes %.2f s (%.0f studs/s)", w1, dash1, (d2 - d0).Magnitude * 1.15 / dash1))
	-- Sun Leap: with Corona on his spike jumps go far higher
	-- (and stays in the court camera's frame: the owner, "why is laith jumping out of the screen")
	local leapUp = Characters.jumpHeight(laith, GROUND) * CO.LeapMul
	check(CO.LeapMul >= 1.3 and leapUp <= 24.5, "Sun Leap: Corona's jump goes far higher, but not off the screen", string.format("x%.1f: %.1f studs up", CO.LeapMul, leapUp))

	-- Zenith: about ZenithChance of his spikes (by the ball's seed, so client and server agree),
	-- +13% and heavier topspin; nobody else's spikes change
	local zenith, total, same = 0, 300, true
	local sample = nil
	for seq = 1, total do
		local _, a = laithSpike(root, 0, { seq = seq })
		local _, b = laithSpike(root, 0, { seq = seq })
		same = same and (a.meta.zenith == b.meta.zenith) and a.meta.kmh == b.meta.kmh
		if a.meta.zenith then
			zenith = zenith + 1
			if not sample then
				sample = seq
			end
		end
	end
	local _, z = laithSpike(root, 0, { seq = sample })
	local _, plainSeq = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = laith, seq = sample })
	local zPath = BallPhysics.buildPath(z.launch)
	local rate = zenith / total
	check(same and rate > CO.ZenithChance - 0.07 and rate < CO.ZenithChance + 0.07 and z.meta.zenith and math.abs(z.meta.kmh / plainSeq.meta.kmh - (1 + CO.ZenithPower) * (1 + CO.SpikeBoost)) < 0.01
		and math.abs(z.launch.a.Y / plainSeq.launch.a.Y - CO.ZenithSpin) < 0.01 and Court.inBounds(zPath.landing.pos),
		"Zenith: about one spike in five bursts (+13%, heavier topspin, still in), the same on both sides",
		string.format("%d of %d, %.0f vs %.0f km/h", zenith, total, z.meta.kmh, plainSeq.meta.kmh))
	local _ = zen

	-- Long Toss: his forward serve toss goes as far as Dante's
	check(HitLogic.tossReach("Corona") == Config.Abilities.Feral.TossReachMul and HitLogic.tossReach("Corona") > 1, "Laith's serve toss goes much further forward, like Dante's")
end

print("== Squall (Haneul) ==")
do
	local SQ = Config.Abilities.Squall
	local haneul = Characters.derive(Characters.fromRoster(Roster.get("haneul"), "max"))
	-- the owner: "she is easily the fastest character, and lucas should be second"
	local speeds = {}
	for _, c in ipairs(Roster) do
		table.insert(speeds, { id = c.Id, speed = c.Speed })
	end
	table.sort(speeds, function(a, b) return a.speed > b.speed end)
	local walkTop = Characters.derive(Characters.fromRoster(Roster.get(speeds[3].id), "max")).WalkSpeed
	check(speeds[1].id == "haneul" and speeds[2].id == "laith" and speeds[1].speed - speeds[2].speed >= 30 and haneul.WalkSpeed > walkTop + 2,
		"Haneul is easily the fastest, Laith second",
		string.format("Speed %d, %d, then %d; runs %.1f against %.1f", speeds[1].speed, speeds[2].speed, speeds[3].speed, haneul.WalkSpeed, walkTop))
	-- Squall: faster still, and Attack with her Speed
	local on = HitLogic.effectiveStats(haneul, "Squall", nil, { squallOn = true })
	local off = HitLogic.effectiveStats(haneul, "Squall", nil, {})
	check(off == haneul and on.Speed == math.min(Config.Stats.Max, haneul.Speed + math.floor(haneul.Speed * SQ.SpeedBoost + 0.5)) and on.Attack > haneul.Attack + 25 and on.WalkSpeed > haneul.WalkSpeed,
		"Squall: faster, and the faster she is the more Attack", string.format("SPD %d -> %d, ATK %d -> %d, run %.1f -> %.1f", haneul.Speed, on.Speed, haneul.Attack, on.Attack, haneul.WalkSpeed, on.WalkSpeed))
	-- Tailwind's aim and timing (the owner: "on these out of system sets, haneul consistenly way
	-- overshoots it"): she aims where her hand really is at the top of her spring (Updraft lifts it
	-- well over her card's hitting point), and springs so her top comes SpringEarly before the ball,
	-- not on arrival
	local springTop = GROUND + Characters.jumpHeight(haneul, GROUND) * SQ.LeapMul + Z.SpikeUp + Z.SpikeCenterDy
	local rise = math.sqrt(2 * Characters.jumpHeight(haneul, GROUND) * SQ.LeapMul / Config.Player.Gravity) / SQ.RushRise
	check(springTop > haneul.contactMaxStuds + 2 and SQ.SpringEarly >= 0.15 and SQ.SpringEarly <= 0.5 and SQ.SpringWaitMax >= 1.5 and rise < 1,
		"Tailwind aims at her real spring top and springs in time for the ball, not on arrival",
		string.format("hand at the top %.1f studs (card %.1f), up in %.2f s, top %.2f s before the ball", springTop, haneul.contactMaxStuds, rise, SQ.SpringEarly))
	-- Shear: a ball just past anyone else's reach is in hers
	local root = apexRoot(haneul, 3.5 * K)
	local wide = ballAt(root, Z.SpikeCenterDz + Z.SpikeRadiusZ * (haneul.Reach or 1) * 1.1, Z.SpikeCenterDy)
	check(HitLogic.spikeReach("Squall") == SQ.ReachMul and HitLogic.spikeZone(root, wide, side, haneul, HitLogic.spikeReach("Squall")) and not HitLogic.spikeZone(root, wide, side, haneul, 1),
		"Shear: her spike reaches wider than anyone's")
	-- Eye of the Storm: the hover's charge powers the spike; the AI gets a share
	local function haneulSpike(input, extra)
		local c = { ability = "Squall", stats = haneul, seq = 9 }
		for k, v in pairs(extra or {}) do c[k] = v end
		return spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), c, input)
	end
	local _, plain = haneulSpike({})
	local _, half = haneulSpike({ gale = 0.5 })
	local _, full = haneulSpike({ gale = 1 })
	local _, auto = haneulSpike({}, { auto = true })
	-- (the owner: "she should at the very least be hitting 150 or 160 and upwards of 200")
	local _, flared = haneulSpike({ gale = 1 }, { squallOn = true })
	check(math.abs(full.meta.kmh / plain.meta.kmh - (1 + SQ.HoverBoost)) < 0.01 and half.meta.kmh > plain.meta.kmh and full.meta.gale == 1 and auto.meta.kmh > plain.meta.kmh and not auto.meta.gale
		and plain.meta.kmh >= 150 and full.meta.kmh >= 200 and flared.meta.kmh > full.meta.kmh,
		"Eye of the Storm: her spikes start at 150+ and a full hover goes past 200 (Squall more)",
		string.format("%.0f plain, %.0f half, %.0f full, %.0f full with Squall, AI %.0f km/h", plain.meta.kmh, half.meta.kmh, full.meta.kmh, flared.meta.kmh, auto.meta.kmh))
	-- how deep (the owner: "the longer you charge up midair the farther back it goes while hitting it
	-- instantly makes it drop very short"): no charge just over the net, the whole charge their back
	-- line, in the court every time
	local shortest, deepest = H.SpikeShortDepth, C.SideDepth - H.SpikeDeepMargin
	local lands = {}
	for i, g in ipairs({ 0, 0.5, 1 }) do
		local ok, res = haneulSpike({ gale = g })
		local path = ok and BallPhysics.buildPath(res.launch)
		lands[i] = path and { depth = oppDepth(path), inn = Court.inBounds(path.landing.pos) and not path.flags.netTouch, aimed = res.meta.aimed } or { depth = 0 }
	end
	local _, noHover = haneulSpike({})
	check(lands[1].inn and lands[2].inn and lands[3].inn and lands[1].aimed and not noHover.meta.aimed and math.abs(lands[1].depth - shortest) < 2 and math.abs(lands[3].depth - deepest) < 2
		and lands[1].depth < lands[2].depth and lands[2].depth < lands[3].depth,
		"Eye of the Storm: let go at once and it drops just over the net; the longer the hover, the deeper",
		string.format("no charge %.1f, half %.1f, full %.1f studs from the net (court %.1f deep)", lands[1].depth, lands[2].depth, lands[3].depth, C.SideDepth))
	-- the target jumps through AimSteps spots (the owner: "in set increments. maybe around 6 or 7,
	-- ending at the very back corner of the court"): the same spot for a little more charge within a
	-- step, the last at the very back, inside the end line
	local d1, s1 = HitLogic.galeDepth(0.01, shortest, C.SideDepth - SQ.BackMargin)
	local d2 = HitLogic.galeDepth(0.05, shortest, C.SideDepth - SQ.BackMargin)
	local dLast, sLast = HitLogic.galeDepth(1, shortest, C.SideDepth - SQ.BackMargin)
	local _, backSpike = haneulSpike({ gale = 1 })
	local backLand = oppDepth(BallPhysics.buildPath(backSpike.launch))
	check(SQ.AimSteps >= 6 and SQ.AimSteps <= 7 and s1 == 1 and d1 == d2 and sLast == SQ.AimSteps and dLast > C.SideDepth - 1 and backLand <= C.SideDepth and backLand > C.SideDepth - 2,
		"Eye of the Storm: the target jumps through 7 spots, the last at the very back of their court",
		string.format("%d spots, the last %.1f studs out (court %.1f), the full-charge spike lands at %.1f", SQ.AimSteps, dLast, C.SideDepth, backLand))
	-- the same seed and charge land the same on the hitter's client and the server
	local _, a = haneulSpike({ gale = 0.6 })
	local _, b = haneulSpike({ gale = 0.6 })
	check(oppDepth(BallPhysics.buildPath(a.launch)) == oppDepth(BallPhysics.buildPath(b.launch)) and a.meta.kmh == b.meta.kmh, "an aimed spike is the same on the client and the server")
	-- Tailwind's spring rises faster to the same top: launched RushRise times faster under RushRise^2
	-- the gravity (MovementController.rushJump / airCancel)
	local g, h = Config.Player.Gravity, 10
	local v0 = math.sqrt(2 * g * h * SQ.RushRise ^ 2)
	local gUp = g * SQ.RushRise ^ 2
	check(math.abs(v0 * v0 / (2 * gUp) - h) < 1e-6 and SQ.RushRise > 1 and SQ.FallCancel > 0 and SQ.HoverCancel < 1 and SQ.SlowMul < 1 and SQ.LeapMul > 1.2
		and C.SideDepth / SQ.DashSpeed < 0.2 and SQ.ChargeTime <= 0.65 and SQ.HoverMax > SQ.ChargeTime,
		"Tailwind dashes the whole court in a blink and springs to the same top, quicker; a full charge in time for the back line; Updraft; a lighter fall; Downdraft",
		string.format("the court in %.2f s, up in %.2f s instead of %.2f, a full charge in %.2f s", C.SideDepth / SQ.DashSpeed, v0 / gUp, math.sqrt(2 * g * h) / g, SQ.ChargeTime))
	-- Updraft at a set: slowed from t along the same curve (where it was u s on, it is u / SetSlow s
	-- on), only a teammate's set, and her dash keeps NetClear off the net
	local set = BallPhysics.buildPath(BallPhysics.newLaunch(Vector3.new(0, 8, 9), Vector3.new(0, 14, -6), Vector3.new(0, -g, 0), 100))
	local t0 = 100.3
	local slowed = BallPhysics.buildPath(HitLogic.updraftLaunch(set, t0, SQ.SetSlow))
	local worst = 0
	for _, u in ipairs({ 0, 0.2, 0.5, 0.8 }) do
		local a1 = BallPhysics.positionAt(set, t0 + u)
		local b1 = BallPhysics.positionAt(slowed, t0 + u / SQ.SetSlow)
		worst = math.max(worst, (a1 - b1).Magnitude)
	end
	local later = slowed.landing.t - t0
	local meta = { hitType = "Set", team = "Home", id = "P_2" }
	check(worst < 1e-3 and math.abs(later * SQ.SetSlow - (set.landing.t - t0)) < 0.02 and SQ.SetSlow > 0.4 and SQ.SetSlow < 0.9
		and HitLogic.updraftCanSlow(meta, "Home", "P_1") and not HitLogic.updraftCanSlow(meta, "Home", "P_2") and not HitLogic.updraftCanSlow(meta, "Away", "P_1")
		and not HitLogic.updraftCanSlow({ hitType = "Spike", team = "Home", id = "P_2" }, "Home", "P_1")
		and SQ.NetClear >= 1.5 and SQ.HomeMax > 0 and SQ.HomeMax <= 2 * Config.Scale.StudsPerMeter and SQ.HoverGlide > 0,
		"Updraft slows a teammate's set along the same curve; Tailwind stays off the net; she glides while she hovers",
		string.format("lands %.2f s later instead of %.2f; %.2f studs off the net", later, set.landing.t - t0, SQ.NetClear))
end

print("== Ironclad (Taesan) ==")
do
	local BTm0 = require("Breakthrough")
	local IR = Config.Abilities.Ironclad
	local taesan = Characters.derive(Characters.fromRoster(Roster.get("taesan"), "max"))
	-- Bulwark (the owner, 2026-10-15: "buff taesan block to be iron wall for 3 lives. it cracks on
	-- one hit and breaks on the next"): while he has shields he's Iron Wall, its whole wall and its
	-- perfect shut-down on every attack, the hardest, clean and piercing spikes and tips included,
	-- even standing; each stop cracks a shield and the next one shatters it: 3 shields, 6 stops
	-- (a block he jumped for: his hands over the tape)
	local IW = Config.Abilities.IronWall
	local broot = vec(0, GROUND + Characters.jumpHeight(taesan, GROUND) * 0.8, side * 1.2)
	local top = broot.Y + Z.BlockReachUp + Config.Ball.Radius
	local function under(below)
		return vec(0, top - below, side * 0.6)
	end
	local palms, tips, chest, legs = under(1.5), under(0.4), under(2.8), under(4.0)
	local function block(kmh, opts)
		opts = opts or {}
		local last = { hitType = opts.hitType or "Spike", team = "Home", kmh = kmh, quality = opts.quality, pierce = opts.pierce, breakAtk = opts.breakAtk }
		local c = ctx({ ability = "Ironclad", stats = taesan, lastHit = last, ironclad = opts.lives ~= 0 or nil, ironLives = opts.lives or 3, ironCracks = opts.cracks, ballVel = vec(0, -8, side * 30), seq = opts.seq or 42 })
		return HitLogic.compute({ action = "Block", t = 0, root = opts.root or broot, ball = opts.ball or palms, vy = 0, grounded = opts.root ~= nil }, c)
	end
	local function walled(ok, r)
		return ok and r.meta.outcome == "Stuff" and r.meta.perfectBlock and r.meta.ironWall and r.meta.bulwark
	end
	local allHeld = true
	for seq = 1, 40 do
		allHeld = allHeld and walled(block(140, { seq = seq })) and walled(block(245, { seq = seq })) and walled(block(150, { seq = seq, quality = 0.95 }))
			and walled(block(130, { seq = seq, pierce = true })) and walled(block(240, { seq = seq, breakAtk = 999 }))
	end
	local okW, held = block(140)
	-- (a feint floats over even Bulwark, the owner, 2026-10-16: no wall stops it, a touch is soft)
	local tipOk, tipTouches = true, 0
	for seq = 1, 60 do
		local okF, rF = block(60, { hitType = "Feint", seq = seq })
		if okF then
			tipTouches = tipTouches + 1
			tipOk = tipOk and rF.meta.outcome == "Soft" and not rF.meta.ironWall and not rF.meta.perfectBlock
		end
	end
	tipOk = tipOk and tipTouches < 25
	local highOk = walled(block(120, { ball = under(-6) }))
	-- standing he isn't a wall (the owner, 2026-10-21: "make taesan have to jump for his iron wall")
	local standOk = not walled(block(200, { root = vec(0, GROUND, side * 1.2), ball = vec(0, C.NetTop + 6, side * 0.6) }))
	local reachOk = walled(block(120, { ball = tips })) and walled(block(120, { ball = chest })) and walled(block(120, { ball = legs }))
	-- with no shields left (awakened) he blocks like anyone: the high ball is out of reach
	local okBare = block(120, { lives = 0, ball = under(-6) })
	-- Cracks: a stop cracks it, the next shatters it; 3 shields take 6 stops; a soft touch nothing
	local after = HitLogic.ironAfterBlock
	local lives, cracks, stops = 3, 0, 0
	while lives > 0 and stops < 20 do
		lives, cracks = after(lives, cracks, held.meta)
		stops = stops + 1
	end
	local l1, c1 = after(3, 0, held.meta)
	local l2, c2 = after(l1, c1, held.meta)
	local l4, c4 = after(3, 1, { hitType = "Block", outcome = "Soft" })
	local l5 = after(0, 0, held.meta)
	check(allHeld and okW and tipOk and highOk and standOk and reachOk and not okBare
		and l1 == 3 and c1 == 1 and l2 == 2 and c2 == 0 and stops == 6 and l4 == 3 and c4 == 1 and l5 == 0 and IR.CracksToBreak == 2
		and HitLogic.wallReach(false, true, "Feint") == true and IW.ReachUp > 10,
		"Bulwark is Iron Wall for 3 lives on a block jump (not standing): every attack shut down (245 km/h, clean, piercing, smashing, any height) but feints (they float over; a touch is soft); a stop cracks a shield, the next shatters it: 6 stops",
		string.format("stops: 3 -> %d (%d crack) -> %d (%d); 3 shields last %d stops", l1, c1, l2, c2, stops))
	-- the stop that shatters a shield pops straight up on his side (the owner, 2026-10-21: "when his
	-- shield is shattered it pops up"): a cracked shield's next stop, never a whole one's however hard
	-- (2026-10-22: "have his shield soft block every other hit. right now any s+ can consistently
	-- break it")
	local function popped(ok, r)
		return ok and r.meta.outcome == "Soft" and r.meta.shatter and r.meta.bulwark and r.launch.v.Y > 0 and r.launch.v.Z * side >= 0
			and r.launch.p.Z * side > 0
	end
	local popOk = true
	for seq = 1, 20 do
		popOk = popOk and popped(block(140, { seq = seq, cracks = 1 })) and popped(block(320, { seq = seq, cracks = 1 })) and walled(block(280, { seq = seq })) and walled(block(320, { seq = seq }))
	end
	local _, big = block(320)
	local l6, c6 = after(3, 0, big.meta)
	check(popOk and l6 == 3 and c6 == 1 and not big.meta.shatter,
		"Bulwark: only the stop that shatters a shield (its second) pops straight up on his side; a whole shield shuts down any spike, 320 km/h too",
		string.format("320 km/h on a whole shield: %d shields, %d cracks", l6, c6))
	check(HitLogic.ironLives(nil) == IR.Lives and HitLogic.ironLives(-1) == 0 and HitLogic.ironLives(9) == IR.Lives and IR.MeterPerTouch == 10 and IR.MeterBonus > 0 and IR.StartLives == 1,
		"Bulwark: a set starts with 1 shield of 3; awakened, every touch fills Intimidation 10% (a kill or a stuff more)")
	check(HitLogic.ironFills(0) and not HitLogic.ironFills(1) and not HitLogic.ironFills(IR.StartLives) and not HitLogic.ironFills(IR.Lives - 1) and not HitLogic.ironFills(nil),
		"Intimidation fills only once every shield is broken (awakened), not while he has one left")
	-- Forge (awakened): a jump before the set charges up to about 215 km/h maxed; after the set,
	-- LateShare of it; not awakened, nothing; the charge widens his reach
	local root = apexRoot(taesan, 3.5 * K)
	local function tspike(input, extra)
		local c = { ability = "Ironclad", stats = taesan, awakened = true }
		for k, v in pairs(extra or {}) do c[k] = v end
		return spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), c, input)
	end
	local _, plain = tspike({})
	local _, early = tspike({ metal = 1, early = true })
	local _, late = tspike({ metal = 1, early = false })
	local _, walled = tspike({ metal = 1, early = true }, { awakened = false })
	local _, auto = tspike({}, { auto = true })
	check(early.meta.kmh >= 205 and early.meta.kmh <= 225 and math.abs(late.meta.kmh / plain.meta.kmh - (1 + IR.MaxBoost * IR.LateShare)) < 0.01
		and walled.meta.kmh >= 170 and walled.meta.kmh <= 185 and auto.meta.kmh > plain.meta.kmh and IR.AwakenedDescentCancel > IR.DescentCancel and HitLogic.spikeReach("Ironclad", 1) > HitLogic.spikeReach("Ironclad", 0) and HitLogic.spikeReach("Ironclad", 0) >= 1.15 and HitLogic.spikeReach("Ironclad", 1) <= 1.55 and IR.ChargeTime <= 0.6,
		"Forge: a quick full charge off a jump before the set: about 178 with shields, about 215 awakened (floating longer); after the set, 30% of it",
		string.format("%.0f plain, %.0f with shields, %.0f awakened, %.0f awakened late (AI %.0f) km/h; full in %.1f s", plain.meta.kmh, walled.meta.kmh, early.meta.kmh, late.meta.kmh, auto.meta.kmh, IR.ChargeTime))
end

print("== Chain Reaction always breaks the guard ==")
do
	-- the owner: "chain reaction spikes should always break stamina": dug with a full guard, even
	-- perfectly, it breaks
	local rroot = vec(0, GROUND, side * 6 * SPM)
	local rball = vec(0, GROUND + Z.ReceiveIdealY, side * 6 * SPM)
	local last = { hitType = "Spike", team = "Home", kmh = 120, reaction = true, drainMul = 2.4, flatDrain = 16, tierDrain = 1 }
	local ok, res = HitLogic.compute({ action = "Bump", t = 0, root = rroot, ball = rball, vy = 0, grounded = true, stanceAge = 0.1 },
		ctx({ touchNumber = 1, lastHit = last, ballVel = vec(0, -20, side * 30), stamina = { value = 120, max = 120 } }))
	check(ok and res.meta.breaks, "Chain Reaction: its spike breaks a full guard, every time", ok and tostring(res.meta.grade) or "no touch")
end

print("== hard spikes into a block ==")
do
	-- (the owner: "im spiking at 300 kmh... every hit is a soft touch block even from an a tier"):
	-- a solid A-tier block soft-touches a 150 km/h spike as before, but a 300 km/h one blasts
	-- through or tools off the hands, never a soft touch; a perfect wall still holds it
	local aTier = Characters.stats("A")
	local broot = vec(0, GROUND + Characters.jumpHeight(aTier, GROUND) * 0.85, side * 1.2)
	local bball = nil
	for dy = 0, 14, 0.1 do
		local b = vec(0, C.NetTop + dy, side * 0.6)
		local ok, q = HitLogic.blockBox(broot, b, side, aTier, false)
		if ok and q > 0.6 and q < 0.8 then
			bball = b
		end
	end
	local function outcomes(kmh, extraCtx)
		local counts = { Stuff = 0, Tool = 0, Soft = 0, Touch = 0, Break = 0 }
		for seq = 1, 300 do
			local c = ctx({ stats = aTier, lastHit = { hitType = "Spike", team = "Home", kmh = kmh, tierDrain = 1 }, ballVel = vec(0, -8, side * 30), seq = seq })
			for k, v in pairs(extraCtx or {}) do c[k] = v end
			local ok, r = HitLogic.compute({ action = "Block", t = 0, root = broot, ball = bball, vy = 0, grounded = false }, c)
			if ok then
				counts[r.meta.outcome] = (counts[r.meta.outcome] or 0) + 1
			end
		end
		return counts
	end
	local slow, hard, walled = outcomes(150), outcomes(300), outcomes(300, { ironWall = true })
	check(bball ~= nil and hard.Soft == 0 and hard.Touch == 0 and hard.Break > 150 and hard.Tool > 0 and slow.Break == 0 and walled.Stuff == 300,
		"a 300 km/h spike blasts through or tools off an A-tier block, never a soft touch; slower ones as before; a perfect wall still holds",
		string.format("150: %d stuff %d soft %d tool %d touch; 300: %d through, %d tool, %d soft; into Iron Wall: %d stuff (of 300)", slow.Stuff, slow.Soft, slow.Tool, slow.Touch, hard.Break, hard.Tool, hard.Soft, walled.Stuff))
end

print("== Shear off blocks (Haneul) ==")
do
	-- (the owner: "her spikes fly more wildly off blocks"): against an ordinary block her spike is
	-- stuffed less and tooled off the hands far more; a perfect block (Iron Wall) still holds
	local blocker = Characters.derive(Characters.fromRoster(Roster.get("taesan"), "max"))
	local broot = vec(0, GROUND + Characters.jumpHeight(blocker, GROUND) * 0.8, side * 1.2)
	-- (a ball near the top of the hands: where a block deflects rather than stuffs)
	local bball = nil
	for dy = 0, 14, 0.1 do
		local b = vec(0, C.NetTop + dy, side * 0.6)
		if HitLogic.blockBox(broot, b, side, blocker, false) then
			bball = b
		end
	end
	local function outcomes(shear, extraCtx)
		local counts = { Stuff = 0, Tool = 0, Soft = 0, Touch = 0, Break = 0 }
		for seq = 1, 400 do
			local last = { hitType = "Spike", team = "Home", kmh = 150, shear = shear or nil }
			local c = ctx({ stats = blocker, lastHit = last, ballVel = vec(0, -8, side * 30), seq = seq })
			for k, v in pairs(extraCtx or {}) do c[k] = v end
			local ok, r = HitLogic.compute({ action = "Block", t = 0, root = broot, ball = bball, vy = 0, grounded = false }, c)
			if ok then
				counts[r.meta.outcome] = (counts[r.meta.outcome] or 0) + 1
			end
		end
		return counts
	end
	local plain, sheared, walled = outcomes(false), outcomes(true), outcomes(true, { ironWall = true })
	check(bball ~= nil and sheared.Stuff <= plain.Stuff and sheared.Tool > plain.Tool + 60 and walled.Stuff == 400,
		"Shear: her spike is stuffed less and tooled off the hands far more; a perfect block still holds",
		string.format("plain: %d stuff, %d tool; hers: %d stuff, %d tool; into Iron Wall: %d stuff (of 400)", plain.Stuff, plain.Tool, sheared.Stuff, sheared.Tool, walled.Stuff))
end

print("== Thunder: Storm Call and Static Charge (YeJun) ==")
do
	local TH = Config.Abilities.Thunder
	local yejun = Characters.derive(Characters.fromRoster(Roster.get("yejun"), "max"))
	local root = apexRoot(yejun, 3.5 * K)
	-- a ball met low, well under 4.00 m (no thunder without the storm)
	local low = root - vec(0, 4, 0)
	local function ys(r, extraCtx, extraInput)
		local c = { ability = "Thunder", stats = yejun }
		for k, v in pairs(extraCtx or {}) do c[k] = v end
		return spike(r, ballAt(r, Z.SpikeCenterDz, Z.SpikeCenterDy), c, extraInput)
	end
	local _, lowPlain = ys(low)
	local _, lowStorm = ys(low, { stormOn = true })
	local _, top = ys(root)
	local _, topStorm = ys(root, { stormOn = true })
	local _, second = ys(root, { stormOn = true }, { second = true })
	check(not lowPlain.meta.thunder and lowStorm.meta.thunder and lowStorm.meta.storm and topStorm.meta.kmh >= 215 and topStorm.meta.kmh <= 225 and second.meta.kmh >= 250 and topStorm.meta.kmh > top.meta.kmh,
		"Storm Call: every spike is full-strength lightning at any height, about 220 maxed (a second swing about 260)",
		string.format("low: %.0f without, %.0f with; top: %.0f without, %.0f with, second swing %.0f km/h", lowPlain.meta.kmh, lowStorm.meta.kmh, top.meta.kmh, topStorm.meta.kmh, second.meta.kmh))
	local _, st3 = ys(root, { static = 3 })
	local _, st9 = ys(root, { static = 9 })
	check(math.abs(st3.meta.kmh / top.meta.kmh - (1 + TH.StaticPer * TH.StaticMax)) < 0.01 and st9.meta.kmh == st3.meta.kmh and st3.meta.static == TH.StaticMax and TH.Active and TH.Duration > 0 and TH.LeapMul > 1.15 and Characters.jumpHeight(yejun, GROUND) * TH.LeapMul <= 24.5,
		"Static Charge: each thunder spike this rally adds 6% to the next, up to 3; High Strike lifts his jump (still on screen)",
		string.format("%.0f with none, %.0f with 3", top.meta.kmh, st3.meta.kmh))
end

print("== gifting cosmetics ==")
do
	-- (the owner: "in the admin panel allow gifting cosmetics"): a grant carries real cosmetics only,
	-- each once, and applying it owns them
	local Economy = require("Economy")
	local Spins = require("Spins")
	local kind = Config.Cosmetics.Kinds[3]
	local item = Spins.items(kind)[2] or Spins.items(kind)[1]
	local g = Economy.cleanGrant({ Items = { { Kind = kind, Key = item.Key }, { Kind = kind, Key = item.Key }, { Kind = "Nope", Key = "x" }, { Kind = kind, Key = "not-a-key" } } })
	local profile = { vp = 0, gold = 0, lucky = 0, owned = {} }
	Economy.apply(profile, g, 0)
	local said = Economy.describe(g)
	check(#g.Items == 1 and not Economy.isEmpty(g) and profile.owned[kind] and profile.owned[kind][item.Key] == true and string.find(said, item.Name, 1, true) ~= nil,
		"admin gifts: a cosmetic in a grant is checked, given once and owned", said)
	-- breakthrough fragments (the owner: "add breakthrough fragments to the admin panel"): real
	-- letters only, capped, added to the purse
	local fg = Economy.cleanGrant({ Fragments = { ["S+"] = 5, A = 2.7, Z = 9, B = -3, S = 99999 } })
	local fp = { vp = 0, gold = 0, lucky = 0, owned = {}, fragments = { ["S+"] = 1 } }
	Economy.apply(fp, fg, 0)
	local fsaid = Economy.describe(fg)
	check(fg.Fragments["S+"] == 5 and fg.Fragments.A == 2 and fg.Fragments.Z == nil and fg.Fragments.B == nil and fg.Fragments.S == Config.Admin.GiveMax.Fragments
		and not Economy.isEmpty(Economy.cleanGrant({ Fragments = { D = 1 } })) and Economy.isEmpty(Economy.cleanGrant({ Fragments = { D = 0 } }))
		and fp.fragments["S+"] == 6 and fp.fragments.A == 2 and string.find(fsaid, "5 S+ Fragments", 1, true) ~= nil,
		"admin gifts: breakthrough fragments by letter, checked and capped, added to the purse", fsaid)
end

print("== the HolyS+ code ==")
do
	local Economy = require("Economy")
	local g1, why1 = Economy.code("HolyS+", os.time())
	local g2 = Economy.code("  holys ", os.time())
	check(g1 ~= nil and why1 == nil and g2 ~= nil and g1.VP == 600 and g1.Gold == 7500 and g1.Lucky == 3,
		"the HolyS+ code reads as typed (the + dropped) and gives 600 VP, 7,500 Gold and 3 lucky spins", g1 and Economy.describe(g1) or tostring(why1))
end

print("== auto-sell per banner ==")
do
	-- (the owner: "glitch where he rolls for cosmetics yet gets nothing"): auto-sell is set per
	-- banner, so Rare on for characters doesn't sell a new Rare ball; an old save's single set
	-- stays on the Characters banner
	local old = Spins.cleanAutoSell({ Rare = true, Common = true })
	local new = Spins.cleanAutoSell({ Ball = { Epic = true, Mythic = true }, Nope = { Rare = true } })
	check(Spins.autoSells(old, "Char", "Rare") and Spins.autoSells(old, "Char", "Common") and not Spins.autoSells(old, "Ball", "Rare")
		and Spins.autoSells(new, "Ball", "Epic") and not Spins.autoSells(new, "Ball", "Mythic") and new.Nope == nil and not Spins.autoSells(new, "Char", "Epic")
		and next(Spins.cleanAutoSell(nil)) == nil,
		"auto-sell: per banner; an old save's setting stays on Characters only; only sellable rarities")
end

print("== the 1000members code ==")
do
	local Economy = require("Economy")
	local g, why = Economy.code("1000Members", os.time())
	check(g ~= nil and g.VP == 1000 and g.Gold == 10000 and g.Lucky == 5,
		"the 1000members code gives 1,000 VP, 10,000 Gold and 5 lucky spins", g and Economy.describe(g) or tostring(why))
end

print("== catching up to someone else's hit ==")
do
	-- (the owner: "the issue of teleporting balls in servers"): a hit heard late is shown from the
	-- hit and eased up to real time, never ahead of it and never backwards; tiny or huge lags don't
	local okAll, last = true, nil
	for i = 0, 60 do
		local b = BallPhysics.catchUp(0.2, i / 100) or 0
		if b > 0.2 + 1e-9 or b < 0 or (last and b > last + 1e-9) then
			okAll = false
		end
		last = b
	end
	local full = BallPhysics.catchUp(0.2, 0)
	check(okAll and math.abs(full - 0.2) < 1e-9 and BallPhysics.catchUp(0.2, 0.6) == nil and BallPhysics.catchUp(0.01, 0) == nil and BallPhysics.catchUp(2, 0) == nil,
		"catch-up: starts at the hit, eases to real time, and skips tiny or huge lags")
end

print("== Discord verification ==")
do
	-- (the owner: "lets start adding an incentive to join the discord", then BedWars-style codes
	-- you send a bot): codes are the set length in unmistakable characters; verifying pays the
	-- Discord Squad card, and no code does
	local Economy = require("Economy")
	local rng = Random.new(7)
	local okAll = true
	for i = 1, 200 do
		local c = Economy.discordCode(rng)
		if not Economy.isDiscordCode(c) or string.find(c, "[IO01]") then
			okAll = false
		end
	end
	local others = 0
	for key, def in pairs(Config.Codes) do
		for _, c in ipairs(def.Cards or {}) do
			if c == "Discord" then
				others = others + 1
			end
		end
	end
	local g = Economy.cleanGrant(Config.Discord.Reward)
	check(okAll and not Economy.isDiscordCode("ABC") and not Economy.isDiscordCode("abcdefg") and not Economy.isDiscordCode("ABCDEF0")
		and g.Cards[1] == "Discord" and others == 0 and Economy.code("SpikeSquad", os.time()) ~= nil,
		"Discord: verification codes are clean, verifying gives the Discord Squad card, and no code does", Economy.describe(g))
end

print("== how hard a spike looks ==")
do
	-- (the owner: "the 300kmh and the 200 visually look identical"): the effects' speed scale
	-- starts past the old 120 km/h look, grows through 200 to 300, and stops at the top
	local a, b, c, d = HitLogic.speedFeel(150), HitLogic.speedFeel(200), HitLogic.speedFeel(300), HitLogic.speedFeel(400)
	check(a == 0 and b > 0 and c > b + 0.5 and d == 1,
		"spike look: 200 and 300 km/h look clearly different, slow ones as before",
		string.format("150: %.2f, 200: %.2f, 300: %.2f, 400: %.2f", a, b, c, d))
end

print("== a match nobody is playing gives up the court ==")
do
	-- (the owner: "it gets stuck in queue"): an all-AI match whose players went AFK is called off
	-- when a lobby is waiting for the court; with nobody waiting the AFK players can still come back
	check(Lobbies.shouldAbort(0, 0, 2, 1) and not Lobbies.shouldAbort(0, 0, 2, 0) and Lobbies.shouldAbort(0, 0, 0, 0)
		and not Lobbies.shouldAbort(1, 0, 0, 3) and not Lobbies.shouldAbort(0, 1, 0, 3),
		"an all-AI match gives the court to a waiting lobby; humans on court or joining keep it")
end

print("== the Almighty card ==")
do
	-- (the owner: "i want to be able to give out a custom banner. Maybe like Almighty"): a card
	-- only given (never earned), and a gift carries it
	local Economy = require("Economy")
	local card = nil
	for _, c in ipairs(Config.Cards.List) do
		if c.Key == "TrueAlmighty" then card = c end
	end
	-- (2026-10-21: the Almighty card is the Almighty rank's now, earned in ranked; the given one is
	-- True Almighty, with an aura and embers on top of everything Almighty has)
	local g = Economy.cleanGrant({ Cards = { "TrueAlmighty" } })
	local profile = { vp = 0, gold = 0, lucky = 0, owned = {}, cards = {} }
	Economy.apply(profile, g, 0)
	local Cards = require("Cards")
	local almighty = Cards.get("Almighty2")
	local reached = Cards.stats({ record = {}, ranked = { best = 7 } }, 0)
	local short = Cards.stats({ record = {}, ranked = { best = 6 } }, 0)
	check(card ~= nil and card.Grant == true and Cards.look(card).Fx.Wings == true and Cards.look(card).Fx.Aura == true and g.Cards[1] == "TrueAlmighty" and profile.cards.TrueAlmighty == true
		and Economy.cleanGrant({ Cards = { "Almighty2" } }).Cards[1] == nil and string.find(Economy.describe(g), "True Almighty", 1, true) ~= nil
		and not Cards.isGrant(almighty) and Cards.met(almighty, reached) and not Cards.met(almighty, short),
		"the True Almighty card can be given and is owned; the Almighty card comes from reaching Almighty in ranked", Economy.describe(g))
end

print("== a character change takes its role ==")
do
	-- (the owner: "when i switch characters to setter ... it doesnt update my roles"): the AI in the
	-- new role trades spots, a player there keeps it, and 1v1 has nothing to trade
	check(Lobbies.roleTrade("WS", "SE", "bot") == "swap" and Lobbies.roleTrade("WS", "SE", "player") == "taken"
		and Lobbies.roleTrade("SE", "SE", "bot") == "same" and Lobbies.roleTrade("Solo", "SE", nil) == "none",
		"switching to a setter in a timeout makes you the setter when an AI had it")
end

print("== deep sets go higher ==")
do
	-- (the owner: "unrestrict the horizontal distance on setter mode", "to reach the very back
	-- court", "maybe higher sets too"): a set aimed at the back line climbs higher than an open
	-- set and still comes down at the aimed spot
	local H = Config.Hits
	local from = vec(0, GROUND + 4, side * 1.2)
	local function apexOf(depth)
		local v, g = HitLogic.setArc(from, side, "Open", depth, false, 0, H.SetArriveY)
		return from.Y + v.Y * v.Y / (2 * g)
	end
	local near, far = apexOf(H.OpenDepth), apexOf(H.SetAimMax)
	check(far > near + 1.5 * C.SideDepth / 9 and H.SetAimMax >= 8.5 * C.SideDepth / 9,
		"setter aim reaches the back line, and a deep set arcs higher",
		string.format("open set apex %.1f, back-line set apex %.1f studs", near, far))
end

print("== patch notes ==")
do
	local PatchNotes = require("PatchNotes")
	local latest = PatchNotes.latest()
	local ids, okShape, okIcons, lines = {}, true, true, 0
	for _, p in ipairs(PatchNotes.List) do
		okShape = okShape and type(p.Id) == "string" and #p.Id <= 40 and not ids[p.Id] and type(p.Title) == "string" and type(p.Sections) == "table" and #p.Sections > 0
		ids[p.Id] = true
		for _, sec in ipairs(p.Sections or {}) do
			okShape = okShape and type(sec.Heading) == "string" and #sec.Items > 0
			for _, item in ipairs(sec.Items) do
				lines = lines + 1
				okShape = okShape and type(item.Text) == "string" and #item.Text > 0
				okIcons = okIcons and (item.Icon == nil or string.match(item.Icon, "^Ability%a+$") ~= nil or string.match(item.Icon, "^Rank%a+%d?$") ~= nil) -- (an ability icon or a rank badge)
			end
		end
	end
	local g = PatchNotes.reward(latest)
	check(latest ~= nil and latest.Title == "Ranked & Clans" and okShape and okIcons and (g.Gold or 0) + (g.VP or 0) > 0 and (g.Gold or 0) <= 5000 and (g.VP or 0) <= 200 and (g.Lucky or 0) <= 1
		and PatchNotes.reward(PatchNotes.List[4]) == PatchNotes.Reward,
		"patch notes: the newest is Ranked & Clans, every entry well formed, a small reading reward (its own, else the usual)",
		string.format("%d patch(es), %d lines, reward %d Gold %d VP", #PatchNotes.List, lines, g.Gold or 0, g.VP or 0))
end

print("== Featherfall (Arin) ==")
do
	local FF = Config.Abilities.Featherfall
	local arin = Characters.derive(Characters.fromRoster(Roster.get("arin"), "max"))
	-- her open set from a clean setting spot, and the same set by a plain setter
	local sroot = vec(0, GROUND, side * 2.0 * SPM)
	local sball = vec(0, GROUND + Z.SetIdealY, side * 2.0 * SPM)
	local function set(ability, setType)
		return HitLogic.compute({ action = "Set", t = 0, root = sroot, ball = sball, vy = 0, grounded = true, setType = setType or "Open" },
			ctx({ ability = ability, stats = arin, touchNumber = 2, seq = 5 }))
	end
	local okP, plain = set(nil)
	local okF, feather = set("Featherfall")
	local okQ, quick = set("Featherfall", "Quick")
	local pPath, fPath = BallPhysics.buildPath(plain.launch), BallPhysics.buildPath(feather.launch)
	-- the top of each, and how long each takes to come down through the hitting height
	local function topAndArrive(path)
		local top, arriveT = -1, nil
		for i = 0, 400 do
			local tt = i * 0.01
			local p = BallPhysics.positionAt(path, tt)
			top = math.max(top, p.Y)
			if not arriveT and tt > 0.3 and BallPhysics.velocityAt(path, tt).Y < 0 and p.Y <= H.SetArriveY then
				arriveT = tt
			end
		end
		return top, arriveT or 99
	end
	local pTop, pT = topAndArrive(pPath)
	local fTop, fT = topAndArrive(fPath)
	local fArrive = BallPhysics.positionAt(fPath, fT)
	local pArrive = BallPhysics.positionAt(pPath, pT)
	check(okP and okF and okQ and feather.meta.featherSet and not quick.meta.featherSet and not plain.meta.featherSet and fTop > pTop + 3 and fT > pT + 0.6
		and math.abs(fArrive.Z - pArrive.Z) < 2.5 and fArrive.Z * side > 0 and not fPath.flags.netTouch,
		"Featherfall: her set goes higher and floats down to the same spot, much slower; quicks stay quick",
		string.format("top %.1f vs %.1f studs, down through the hitting height at %.2f s vs %.2f s, at z %.1f vs %.1f", fTop, pTop, fT, pT, fArrive.Z, pArrive.Z))
	-- the spike off it: the longer it fell, the harder (met at the top, nothing; after FullFall, all)
	local root = apexRoot(SP, 3.5 * K)
	local function spikeAt(dt)
		local c = { lastHit = { featherSet = true, featherTop = feather.meta.featherTop, team = "Away", hitType = "Set" } }
		return spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), c, { t = feather.meta.featherTop + dt })
	end
	local _, s0 = spikeAt(0)
	local _, sHalf = spikeAt(FF.FullFall / 2)
	local _, sFull = spikeAt(FF.FullFall + 1)
	local _, other = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), { lastHit = { featherSet = true, featherTop = 0, team = "Home", hitType = "Set" } }, { t = 3 })
	check(not s0.meta.feather and sHalf.meta.feather == 0.5 and math.abs(sFull.meta.kmh / s0.meta.kmh - (1 + FF.MaxBoost)) < 0.01 and not other.meta.feather,
		"Featherfall: the longer the set had fallen, the harder the spike, up to +30%",
		string.format("%.0f met at the top, %.0f half way, %.0f after the whole fall (her real set falls %.2f s to the hitting height)", s0.meta.kmh, sHalf.meta.kmh, sFull.meta.kmh, fT - (feather.meta.featherTop or 0)))
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
	-- (a full Azure passed it with Dragon Surge, the owner's buff for Seojin: within 20 km/h)
	check(none.meta.kmh > 141 and half.meta.kmh > none.meta.kmh + 15 and full.meta.kmh > half.meta.kmh + 25 and full.meta.kmh >= azure.meta.kmh - 20 and full.meta.kmh <= 225,
		"the longer the charge, the harder the spike; a full one is near a full Azure", string.format("0%%: %.0f  50%%: %.0f  100%%: %.0f km/h (full Azure %.0f)", none.meta.kmh, half.meta.kmh, full.meta.kmh, azure.meta.kmh))
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
	-- Bloodlust (the owner, 2026-10-15: "he now has an active ability he can pop to overcharge to
	-- maybe around 160 170% bar ... and it turns his ball red"): with it on the charge fills past
	-- full to OverMax and the spike grows with the bar; without it the gauge stops at full
	local _, over = leapSpike(FERAL.OverMax, true, { bloodlust = true })
	local _, capped = leapSpike(FERAL.OverMax, true)
	local _, redFull = leapSpike(1, true, { bloodlust = true })
	local CT = FERAL.ChargeTime
	local g0, g1, g2, g3 = HitLogic.feralGauge(CT * 0.5, CT, true), HitLogic.feralGauge(CT + FERAL.OverTime, CT, true), HitLogic.feralGauge(CT + FERAL.OverTime, CT, false), HitLogic.feralGauge(9, CT, true)
	check(FERAL.Active and FERAL.OverMax >= 1.6 and FERAL.OverMax <= 1.7 and math.abs(g0 - 0.5) < 1e-9 and math.abs(g1 - FERAL.OverMax) < 1e-9 and g2 == 1 and g3 == FERAL.OverMax
		and over.meta.gauge == FERAL.OverMax and over.meta.bloodlust and capped.meta.gauge == 1 and not capped.meta.bloodlust and math.abs(capped.meta.kmh - full.meta.kmh) < 0.01
		and redFull.meta.bloodlust and math.abs(redFull.meta.kmh - full.meta.kmh) < 0.01 and over.meta.kmh > full.meta.kmh * 1.15 and over.meta.kmh < 290,
		"Bloodlust (Q): the charge fills past full to 165% and hits far harder; without it the gauge stops at full; every spike in it flies red",
		string.format("165%%: %.0f km/h against %.0f for a full leap", over.meta.kmh, full.meta.kmh))
	-- one hit (the owner, 2026-10-16: "after one hit, the ability is over"): the charged spike spends
	-- it, a spike without a charge doesn't; and the second bar fills fast ("make his 2nd bar fill
	-- significantly quicker")
	local _, plainIn = leapSpike(0, true, { bloodlust = true })
	check(over.meta.bloodlustSpent and redFull.meta.bloodlustSpent and not plainIn.meta.bloodlustSpent and not capped.meta.bloodlustSpent and FERAL.OverTime <= 0.25
		and HitLogic.feralGauge(CT + FERAL.OverTime * 0.5, CT, true) > 1.3,
		"Bloodlust ends with the hit its charge powers (an uncharged spike doesn't spend it), and its second bar fills in a fifth of a second",
		string.format("%.2f s from full to %d%%", FERAL.OverTime, math.floor(FERAL.OverMax * 100)))

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
		"his jump serve takes the charge too: x1.5 at full, a First Strike, no block break", string.format("%.0f -> %.0f km/h (first strike %.0f), %s", s0.meta.kmh, s1.meta.kmh, s2.meta.kmh, describe(servePath)))

	-- Space on the held ball tosses and starts the charge: his toss goes up high, so a full
	-- charge (then the leap's gather) still meets it at his hitting point, fresh or maxed
	local function serveGap(st)
		local r0 = vec(0, GROUND, side * (C.SideDepth + 1))
		local tp, tv = HitLogic.tossLaunch(r0, side, H.FeralTossHigh, 0, HitLogic.tossReach("Feral"))
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
		WS = { Adrenaline = true, RisingSun = true, Counter = true, Plunge = true, Skyward = true },
		MB = { IronWall = true, RallyCry = true, Sunshine = true },
		SE = { ChainReaction = true, Vector = true, Turnabout = true, Featherfall = true },
	}
	for _, c in ipairs(Roster) do
		okLimits = okLimits and not ids[c.Id] and Characters.isTier(c.Tier) and Config.RoleTemplates[c.Role] ~= nil
		ids[c.Id] = true
		for _, k in ipairs(Config.Stats.Order) do
			okLimits = okLimits and c[k] >= Config.Stats.Min and c[k] <= Config.Stats.Max
		end
		if c.Tier == "S+" then
			okAbility = okAbility and ((c.Role == "WS" and (c.Ability == "Thunder" or c.Ability == "Azure" or c.Ability == "Feral" or c.Ability == "ZeroPoint" or c.Ability == "Corona" or c.Ability == "Squall"))
				or (c.Role == "MB" and c.Ability == "Ironclad") or (c.Role == "SE" and c.Ability == "Tyrant"))
		elseif c.Tier == "S" then
			okAbility = okAbility and want[c.Role][c.Ability or ""] == true and Config.Abilities[c.Ability].Role == c.Role
		else
			okAbility = okAbility and c.Ability == nil
		end
		if c.Role == "WS" then
			-- 210 Attack tops the wing spikers' template (Dante, Feral Leap, is above it); 190 Jump (Seora,
			-- Skyward, is above it: her climb moves her hitting point)
			okShape = okShape and (c.Attack <= 210 or c.Ability == "Feral") and (c.Jump <= 190 or c.Ability == "Skyward") and c.Attack > c.Defense
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
	check(okAbility, "abilities: S+ wing spikers have Thunder, Azure, Feral Leap, Zero Point, Corona or Squall (the S+ middle Ironclad, the S+ setter The Tyrant), S characters one of their role's abilities, the rest none")
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
	local ok6, res6 = receive(slideRoot, slideBall, { value = 120, max = 120 }, { diving = true, stanceAge = 0.75 })
	local path6 = BallPhysics.buildPath(res6.launch)
	local slideShare = (res6.meta.drain or 0) / (res2.meta.drain or 1)
	check(ok6 and not res6.meta.breaks and not res6.meta.knock and res6.meta.quality >= H.SlideQualityFloor and math.abs(slideShare - H.SlideDrainMul) < 0.05 and path6.landing.pos.Z * side > 0, "slide receive pays a fraction of a bump's drain, no knockback, at least Great", string.format("q %.2f, drain %.1f vs bump %.1f, %s", res6.meta.quality, res6.meta.drain or 0, res2.meta.drain or 0, describe(path6)))
	local ok7, res7 = receive(slideRoot, slideBall, { value = 2, max = 120 }, { diving = true })
	check(ok7 and res7.meta.breaks, "a slide can still break a nearly empty guard", res7.meta.grade)
	local ok8, res8 = receive(slideRoot, slideBall, { value = 0, max = 120 }, { diving = true })
	check(ok8 and res8.meta.fail, "a slide can't save a broken guard against a strong spike", res8.meta.grade)
	-- Locked by the Tyrant's Dictate: no slides (the same dive plays as a plain bump: the full drain,
	-- not a slide's share)
	local okLk, resLk = receive(slideRoot, slideBall, { value = 120, max = 120 }, { diving = true, stanceAge = 0.75 }, { dictated = Config.Abilities.Tyrant.Steal })
	check(ok6 and (not okLk or (resLk.meta.drain or 0) > (res6.meta.drain or 0) * 1.5), "Locked by the Dictate, a slide is no slide: no slide's cheap drain (or no reach)",
		okLk and string.format("drain %.1f vs a slide's %.1f", resLk.meta.drain or 0, res6.meta.drain or 0) or tostring(resLk))
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
	local hayun = Characters.derive(Characters.fromRoster(Roster.get("shoyo"), "max"))
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
	local CR = Config.Abilities.ChainReaction
	check(okS and charged.charged and boom.meta.reaction and math.abs(boom.meta.kmh / plain.meta.kmh - CR.PowerMul[1]) < 0.01 and feint.meta.reaction and not feint.meta.noDrain, "Chain Reaction: a charged set makes the spike (and even a feint) explode", string.format("%.1f vs %.1f km/h", boom.meta.kmh, plain.meta.kmh))
	-- not in 1v1 (the owner, 2026-10-16: "disable chain reaction in 1v1s"): her own set there isn't
	-- charged, and the spike off it is a plain one
	local okSolo, soloSet = HitLogic.compute({ action = "Set", t = 0, root = sroot, ball = vec(0, sroot.Y + Z.SetIdealY, sroot.Z), grounded = true, setType = "Open" }, ctx({ teamSize = 1, touchNumber = 2, stats = seoyeon, ability = "ChainReaction", lastHit = { team = "Away", hitType = "Bump" } }))
	local soloMeta = (okSolo and soloSet.meta) or {}
	soloMeta.team = "Away"
	local _, soloPlain = spike(sr, sb, { teamSize = 1, lastHit = { team = "Away", hitType = "Set" } })
	local _, soloSpike = spike(sr, sb, { teamSize = 1, lastHit = soloMeta })
	check(okSolo and not soloMeta.charged and not soloSpike.meta.reaction and math.abs(soloSpike.meta.kmh - soloPlain.meta.kmh) < 0.01,
		"Chain Reaction is off in 1v1: her own set isn't charged and the spike off it doesn't explode", string.format("%.1f km/h", soloSpike.meta.kmh))
	-- the chain grows (the owner's buff): the team's second explosion of a rally, then the third,
	-- hit harder and drain more; it stops growing at the last step
	local _, boom2 = spike(sr, sb, { lastHit = charged, chain = 1 })
	local _, boom3 = spike(sr, sb, { lastHit = charged, chain = 2 })
	local _, boom9 = spike(sr, sb, { lastHit = charged, chain = 8 })
	local _, feint3 = spike(sr, sb, { lastHit = charged, chain = 2 }, { action = "Feint" })
	check(boom.meta.chainLink == 1 and boom2.meta.chainLink == 2 and boom3.meta.chainLink == 3 and boom9.meta.chainLink == 3
		and math.abs(boom2.meta.kmh / plain.meta.kmh - CR.PowerMul[2]) < 0.01 and math.abs(boom3.meta.kmh / plain.meta.kmh - CR.PowerMul[3]) < 0.01 and boom9.meta.kmh == boom3.meta.kmh
		and boom3.meta.drainMul == CR.DrainMul[3] and boom3.meta.drainMul > boom.meta.drainMul and feint3.meta.flatDrain == CR.FlatDrain[3],
		"Chain Reaction grows: each explosion in a rally bigger than the last, up to the third", string.format("%.1f, %.1f, %.1f km/h", boom.meta.kmh, boom2.meta.kmh, boom3.meta.kmh))
	local recRoot = vec(0, GROUND, side * 18 * K)
	local recBall = vec(0, recRoot.Y + Z.ReceiveIdealY, recRoot.Z - side * Z.ReceiveForward)
	local fast = vec(0, -30 * K, side * 110 * K)
	local _, normalDig = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.6 }, { lastHit = { team = "Home", hitType = "Spike", kmh = 140 }, ballVel = fast })
	local _, boomDig = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.6 }, { lastHit = { team = "Home", hitType = "Spike", kmh = 140, reaction = true, drainMul = boom.meta.drainMul, flatDrain = boom.meta.flatDrain }, ballVel = fast })
	local _, feintDig = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.6 }, { lastHit = { team = "Home", hitType = "Feint", kmh = 32, reaction = true, noDrain = nil, drainMul = feint.meta.drainMul, flatDrain = feint.meta.flatDrain }, ballVel = vec(0, -8 * K, side * 10 * K) })
	check((boomDig.meta.drain or 0) > 2.5 * (normalDig.meta.drain or 0) and (feintDig.meta.drain or 0) >= 10, "the explosion wipes the receivers' stamina fast, even off a feint", string.format("dig drains %.1f vs %.1f; a charged feint %.1f", boomDig.meta.drain or 0, normalDig.meta.drain or 0, feintDig.meta.drain or 0))

	-- Iron Wall (S middle): everything that reaches the block is stuffed, even a full Azure
	local bside = -side
	local gaeul = Characters.derive(Characters.fromRoster(Roster.get("tetsuo"), "max"))
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
	-- the host moves players between the teams: across while there's room, a swap when it's full
	local mv = Lobbies.new(46, 1, "a", Lobbies.settings({ mode = 2 }))
	for _, u in ipairs({ 1, 2, 3 }) do Lobbies.seat(mv, u) end -- Home 1, 3; Away 2
	local movedAcross = Lobbies.hostMove(mv, 3) and #mv.Home == 1 and #mv.Away == 2 and Lobbies.teamOf(mv, 3) == "Away"
	Lobbies.seat(mv, 4) -- Home 1, 4; Away 2, 3
	local swapped = Lobbies.hostMove(mv, 4) and Lobbies.teamOf(mv, 4) == "Away" and Lobbies.teamOf(mv, 3) == "Home" and #mv.Home == 2 and #mv.Away == 2
	local qmv = Lobbies.new(47, 1, "a", Lobbies.settings({ mode = 2 })); qmv.quick = true; Lobbies.seat(qmv, 1); Lobbies.seat(qmv, 2)
	check(movedAcross and swapped and not Lobbies.hostMove(qmv, 2) and not Lobbies.hostMove(mv, 99),
		"the host moves a player to the other team, or swaps them with that spot when it's full; not in Quick Match")
	-- the host picks the characters of the bot spots, from the whole roster
	local pk = Lobbies.new(42, 1, "a", Lobbies.settings({ mode = 3 }))
	Lobbies.seat(pk, 1, "Home")
	local ws, mb, se
	for _, c in ipairs(Roster) do
		if c.Role == "WS" and not ws then ws = c.Id end
		if c.Role == "MB" and not mb then mb = c.Id end
		if c.Role == "SE" and not se then se = c.Id end
	end
	local set1 = Lobbies.setPick(pk, "Home", 1, ws)
	local set2 = Lobbies.setPick(pk, "Home", 2, se)
	local set3 = Lobbies.setPick(pk, "Away", 3, mb)
	local junk = Lobbies.setPick(pk, "Away", 1, "nobody") or Lobbies.setPick(pk, "Nope", 1, ws) or Lobbies.setPick(pk, "Away", 4, ws)
	local bp = Lobbies.botPicks(pk)
	check(set1 and set2 and set3 and not junk and #bp.Home == 1 and bp.Home[1] == se and #bp.Away == 1 and bp.Away[1] == mb,
		"the host picks bot spots' characters; the host's own spot isn't a bot, junk picks are refused")
	local back2 = Lobbies.import(Lobbies.export(pk), 43)
	check(back2.picks.Away[3] == mb and back2.picks.Home[2] == se and Lobbies.import({ mode = 3, picks = { Home = { "x", 5 } } }, 44).picks.Home[1] == "",
		"picks go along to the lobby's own server, cleaned")
	check(Lobbies.pickFor({ ws, se }, "SE", {}) == se and Lobbies.pickFor({ ws, se }, "MB", {}) == ws and Lobbies.pickFor({ ws }, "WS", { [ws] = true }) == nil and Lobbies.pickFor({ ws }, "Solo", {}) == ws,
		"a bot takes the pick made for its role first, else the next one left")
	-- (the owner, 2026-10-25: "there can only be one of each player. change that": once a team, so
	-- both sides can pick the same character; and the host's skins go on the picked bots)
	local both = Lobbies.setPick(pk, "Away", 2, se)
	local bp2 = Lobbies.botPicks(pk)
	check(both and bp2.Home[1] == se and bp2.Away[1] == se and bp2.host == 1 and Lobbies.pickFor(bp2.Away, "SE", {}) == se,
		"both sides can pick the same character (one of each a team), and the picks name the host for their skins")
	local qk = Lobbies.new(45, 1, "a", Lobbies.settings({ mode = 3 })); qk.quick = true
	check(not Lobbies.setPick(qk, "Away", 1, ws) and #Lobbies.botPicks(qk).Away == 0, "Quick Match takes no picks")
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
	check(Lobbies.pickQuick({ q1, q2, q3, q4 }, 2) == q2 and Lobbies.pickQuick({ q1, q3 }, 1) == nil and Lobbies.pickQuick({ q1, q2, q3, q4 }, 2, true) == nil, "Quick Match joins the fullest open public lobby of that mode (never a ranked one)")
	-- Quick Match bots play at the strongest player's tier, from A up to S+
	check(Lobbies.quickBotTier({ "D", "B" }) == Config.Match.QuickBotFloor and Lobbies.quickBotTier({ "D", "S" }) == "S" and Lobbies.quickBotTier({ "S+" }) == "S+" and Lobbies.quickBotTier({}) == Config.Match.QuickBotFloor,
		"Quick Match bots play at the strongest player's level, A up to S+")
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
	-- across servers (Config.Lobby.Global): the other servers' view of a lobby never has the
	-- password; a seat in another server's lobby reads like one here; Quick Match goes to a fuller
	-- queue elsewhere if there's time to get in, and stays here on a tie
	local names = { [100] = "Ana", [200] = "Bo", [300] = "Cy", [400] = "Di" }
	local view = Lobbies.view(l, function(u) return names[u] or "?" end)
	check(view.password == nil and view.mode == l.mode and view.privacy == "Private" and Lobbies.viewCount(view) == Lobbies.count(l) and Lobbies.viewSide(view, 300) == Lobbies.teamOf(l, 300) and Lobbies.viewSide(view, 999) == nil and view.Home[1].name == "Ana",
		"another server sees a lobby's settings and members, never its password")
	local rs = Lobbies.remoteSummary(view, "job-a/7", 300)
	local pend = Lobbies.remoteMine(view, "job-a/7", 555, true)
	local seated = Lobbies.remoteMine(view, "job-a/7", 300, false)
	check(rs.id == "job-a/7" and rs.remote and rs.mine and rs.locked and rs.capacity == 4 and rs.count == 4 and pend.state == "Joining" and not pend.isHost and seated.state == l.state and seated.side == Lobbies.teamOf(l, 300) and #seated.Home + #seated.Away == 4 and seated.Home[1].host == true,
		"a lobby in another server lists and reads like one here (Joining until its server says yes)")
	local now0 = 1000
	local function qv(mode, n, startsIn, privacy)
		local v = { mode = mode, quick = true, state = "Open", privacy = privacy or "Public", startsAt = now0 + startsIn, Home = {}, Away = {} }
		for i = 1, n do
			table.insert(i % 2 == 1 and v.Home or v.Away, { id = 900 + i, name = "p" })
		end
		return v
	end
	local lead = Config.Lobby.Global.QuickLead
	local here1 = Lobbies.new(50, 1, "a", Lobbies.settings({ mode = 2 })); here1.quick = true; Lobbies.seat(here1, 1)
	local here2 = Lobbies.new(51, 1, "a", Lobbies.settings({ mode = 2 })); here2.quick = true; Lobbies.seat(here2, 1); Lobbies.seat(here2, 2)
	-- e: three but about to start; f: friends only; g: another mode; h: full
	local elsewhere = { { gid = "b/1", view = qv(2, 1, 8) }, { gid = "c/1", view = qv(2, 2, 6) }, { gid = "d/1", view = qv(2, 2, 3) }, { gid = "e/1", view = qv(2, 3, lead / 2) }, { gid = "f/1", view = qv(2, 3, 9, "Friends") }, { gid = "g/1", view = qv(3, 4, 9) }, { gid = "h/1", view = qv(2, 4, 9) } }
	local pickA = Lobbies.pickQuickRemote(here1, elsewhere, 2, now0, lead)
	local pickB = Lobbies.pickQuickRemote(here2, elsewhere, 2, now0, lead)
	local pickC = Lobbies.pickQuickRemote(nil, { elsewhere[1] }, 2, now0, lead)
	-- tournaments (Config.Tournament, Cups): four cups at a time, the same on every machine, each
	-- with Mods modifiers of its strengths; modifiers move stats and stamina; a run pays its prize
	-- for three wins, the consolation for a lost final, nothing else; a run survives a teleport
	do
		local Cups = require("Cups")
		local TT = Config.Tournament
		local t0 = 1791000000
		local a, b2 = Cups.current(t0), Cups.current(t0 + 5)
		local ok = #a == #TT.Cups
		local differs = false
		for slot = 1, 8 do
			local o = Cups.current(t0 + slot * TT.Rotate)
			local taken = {}
			for i, run in ipairs(o) do
				if run.mode ~= a[i].mode or run.mods[1] ~= a[i].mods[1] then
					differs = true
				end
				for _, k in ipairs(run.mods) do
					ok = ok and not taken[k] -- no two cups share a modifier
					taken[k] = true
				end
			end
		end
		for i, run in ipairs(a) do
			local seen = {}
			ok = ok and #run.mods == run.cup.Mods and run.mode == b2[i].mode and run.mods[1] == b2[i].mods[1] and run.endsAt > t0
			for _, k in ipairs(run.mods) do
				local m = Cups.modifier(k)
				ok = ok and m ~= nil and m.Strength >= run.cup.Min and m.Strength <= run.cup.Max and not seen[k]
				seen[k] = true
			end
		end
		check(ok and differs and Cups.find(a[1].key, t0) ~= nil and Cups.find("Nope", t0) == nil, "tournaments: four cups at a time, the same everywhere, each with its own modifiers, a new set every rotation")
		local base = Characters.stats("A")
		local spring = HitLogic.effectiveStats(base, nil, nil, { mods = Cups.statMods("SpringHeels") })
		local giant = HitLogic.effectiveStats(base, nil, nil, { mods = Cups.statMods("Giants") })
		local plain = HitLogic.effectiveStats(base, nil, nil, { mods = Cups.statMods("Marathon") })
		check(spring.Jump == base.Jump + 20 and spring.Attack == base.Attack + 10 and giant.Height > base.Height and giant.ContactMaxM > base.ContactMaxM and plain == base
			and math.abs(Cups.factor("Exhausted,Marathon", "Stamina") - 0.675) < 1e-9 and Cups.factor("", "Stamina") == 1 and Cups.has("DeepSpike", "OppDeep") and not Cups.has("Giants", "OppDeep"),
			"tournament modifiers: stat points and height for everyone, stamina and timing multipliers, the bots' deep spikes",
			string.format("Jump %d -> %d, reach %.2f -> %.2f m", base.Jump, spring.Jump, base.ContactMaxM, giant.ContactMaxM))
		local gold = Cups.cup("Gold")
		local wv, wg = Cups.payout(gold, TT.Rounds, true)
		local fv = Cups.payout(gold, TT.Rounds, false)
		local ev = Cups.payout(gold, 1, false)
		local run = Lobbies.new(77, 1, "a", Lobbies.settings({ mode = 2, points = TT.Points }))
		run.cup = { key = "Gold", name = gold.Name, round = 2, mods = "DeepSpike,Junk" }
		Lobbies.seat(run, 1)
		local back2 = Lobbies.import(Lobbies.export(run), 78)
		-- with friends (the owner: "make it so you can play with friends"): the run's lobby lists as
		-- the cup, and friends take the players' side only (the bots are Away)
		local party = Lobbies.new(79, 1, "Host", Lobbies.settings({ mode = 2, privacy = "Friends" }))
		party.cup = { key = "Gold", name = gold.Name, round = 1, mods = "" }
		Lobbies.seat(party, 1, "Home")
		local friendSide = Lobbies.seat(party, 2, "Home")
		local thirdSide = Lobbies.seat(party, 3, "Home")
		local ps = Lobbies.summary(party, 2)
		check(friendSide == "Home" and thirdSide ~= "Home" and ps.cup and ps.cup.name == gold.Name and not Lobbies.visible(party, 9, false) and Lobbies.visible(party, 9, true),
			"a cup with friends: listed as the cup to the host's friends only, players on one side")
		check(wv == gold.PrizeVP and wg == gold.PrizeGold and fv == gold.Consolation and ev == 0 and gold.PrizeVP > gold.Entry and back2.cup and back2.cup.round == 2 and back2.cup.mods == "DeepSpike" and back2.hidden,
			"a tournament pays its prize for three wins and its consolation for a lost final, and a run goes on in its own server", string.format("Gold Cup: %d VP in, %d VP + %d Gold out", gold.Entry, wv, wg))
	end
	check(pickA == "d/1" and pickB == nil and pickC == "b/1",
		"Quick Match across servers: the fullest queue anywhere with time to get in (the one starting first on a tie); this server's own on a tie", string.format("%s / %s / %s", tostring(pickA), tostring(pickB), tostring(pickC)))
	local waiting = qv(2, 2, 0)
	waiting.startsAt = nil -- a queue now waits until it's full (or someone starts it with bots)
	check(Lobbies.pickQuickRemote(here1, { { gid = "w/1", view = waiting } }, 2, now0, lead) == "w/1", "a Quick Match queue with no countdown can still be joined from another server")
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
	-- (the owner buffed him, 2026-10-16: "buff daon, shoyo, and seora": at 0 points he's past an A-
	-- now, still well under YeJun)
	local soraA = Characters.derive(Characters.fromRoster(Roster.get("sora"), "max")) -- the A- wing spiker
	check(table.concat(lv, ",") == "0,0,1,2,3,4,4" and beats and sun12.ContactMaxM > yejunS.ContactMaxM and sun0.Attack > soraA.Attack and sun0.Attack < yejunC.Attack - 15 and sun0.ContactMaxM < yejunS.ContactMaxM,
		"Rising Sun: past an A- at 0 points but under YeJun, a level every 3 lost, and at 12 every stat beats a maxed YeJun", string.format("%.2f m at 0, %.2f m at 12 (YeJun %.2f m); ATK %d JMP %d DEF %d SPD %d", sun0.ContactMaxM, sun12.ContactMaxM, yejunS.ContactMaxM, sun12.Attack, sun12.Jump, sun12.Defense, sun12.Speed))

	-- Rally Cry: +12% to every stat of the team
	local rally = HitLogic.effectiveStats(SP, nil, nil, { teamBoost = true })
	local rr = apexRoot(rally, 3.5 * K)
	local _, boosted = spike(rr, ballAt(rr, Z.SpikeCenterDz, Z.SpikeCenterDy), { teamBoost = true })
	local _, normal = spike(sr, ballAt(sr, Z.SpikeCenterDz, Z.SpikeCenterDy))
	check(rally.Attack == math.floor(SP.Attack * 1.12 + 0.5) and rally.Jump > SP.Jump and rally.Speed > SP.Speed and boosted.meta.kmh > normal.meta.kmh,
		"Rally Cry: the whole team plays with +12% on every stat", string.format("ATK %d -> %d, spike %.0f -> %.0f km/h", SP.Attack, rally.Attack, normal.meta.kmh, boosted.meta.kmh))

	-- Counter Edge: dug balls fill the meter (a hard spike fills it, for a fraction of the guard);
	-- she scales with it and her next spike releases it
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
	local hayun = Characters.derive(Characters.fromRoster(Roster.get("shoyo"), "max"))
	local CE = Config.Abilities.Counter
	-- a served ball she digs (not heavy) fills it a little and drains like any receive
	local _, light = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 0.3 }, { lastHit = { team = "Home", hitType = "Underhand", noDrain = true, kmh = 45 }, ballVel = vec(0, -10 * K, side * 40 * K), ability = "Counter", stats = ines })
	check((dig.meta.drain or 0) > 0 and math.abs(dig.meta.drain - CE.SpikeDrainMul * (dig2.meta.drain or 0)) < 0.01 and (dig.meta.counterGain or 0) >= 100 and light.meta.counterGain == CE.LightGain,
		"Counter Edge: one hard spike dug fills the meter for a fraction of the guard; any other ball of theirs adds some", string.format("+%.0f from a %d km/h spike for %.1f guard (%.1f without), +%d from a serve", dig.meta.counterGain or 0, last.kmh, dig.meta.drain or 0, dig2.meta.drain or 0, light.meta.counterGain or 0))
	-- not invincible (the owner: "she should have very high defense but no invincible"): a Chain
	-- Reaction's explosion costs her the whole drain and can break her guard from full ("chain
	-- reaction should still be able to completely deplete stamina"), and with no guard left a hard
	-- spike breaks her like anyone
	local CH = Config.Abilities.ChainReaction
	local huge = vec(0, -45 * K, side * 163 * K) -- about 190 km/h
	local boomLast = { team = "Home", hitType = "Spike", kmh = 190, reaction = true, drainMul = CH.DrainMul[1], flatDrain = CH.FlatDrain[1] }
	local _, boomIn = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 1.5 }, { lastHit = boomLast, ballVel = huge, ability = "Counter", stats = ines })
	local _, hardIn = receive(recRoot, recBall, { value = 90, max = 90 }, { stanceAge = 1.5 }, { lastHit = { team = "Home", hitType = "Spike", kmh = 190 }, ballVel = huge, ability = "Counter", stats = ines })
	local _, brokeIn = receive(recRoot, recBall, { value = 0, max = 90 }, { stanceAge = 0.6 }, { lastHit = last, ballVel = fast, ability = "Counter", stats = ines })
	check(boomIn.meta.breaks == true and not hardIn.meta.breaks and (hardIn.meta.drain or 0) > 5 and brokeIn.meta.fail == true,
		"Counter Edge isn't invincible: a Chain Reaction breaks her guard from full, and an empty guard breaks", string.format("a 190 km/h spike costs her %.1f of 90; its explosion breaks her: %s; with no guard: %s", hardIn.meta.drain or 0, tostring(boomIn.meta.breaks), tostring(brokeIn.meta.fail)))
	check(s0 == ines and ines.Attack < hayun.Attack and ines.Defense <= 130 and s50.Attack > s0.Attack and s50.Defense < s100.Defense
		and s100.Defense >= 195 and s100.Attack >= 205 and full.meta.kmh >= 200 and full.meta.kmh <= 210 and full.meta.kmh > empty.meta.kmh * 1.25 and full.meta.counterRelease == 100 and empty.meta.counterRelease == nil,
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
	-- double approach: no run-up any more (the owner: "shouldn't make you move"); the first press
	-- readies the jump and the second has a moment to come
	check(P.ApproachRun == nil and P.ApproachRunMax == nil and P.ApproachArmTime >= 0.5 and P.ApproachArmTime <= 2,
		"double approach: no run-up; the second press has a moment to come", string.format("%.1f s", P.ApproachArmTime))
	-- Spike's jump is one tap with no run-in dash on every device (the owner: "no run in dash"), and
	-- the touch Jump button goes the same way, so the double approach setting works on touch too
	local function src(path)
		local f = io.open(ROOT .. path)
		local s = f and f:read("a") or ""
		if f then
			f:close()
		end
		return s
	end
	local mc = src("/src/client/Controllers/MovementController.lua")
	local approach = mc:match("function MovementController%.approach%(kind%)(.-)\nend")
	check(approach ~= nil and not approach:find("gather") and approach:find("MovementController%.jump") ~= nil and approach:find("doubleApproach") ~= nil,
		"Spike's ground jump: no gather dash; one tap jumps, or two with the double approach")
	local ac = src("/src/client/Controllers/ActionController.lua")
	local pj = ac:match("local function pressJump%(info%)(.-)\nend")
	check(pj ~= nil and not pj:find("MovementController%.jump") and pj:find("MovementController%.approach") ~= nil,
		"the touch Jump button takes the same jump as Spike (the double approach included)")
end

print("== HUD layout ==")
do
	local Settings = require("Settings")
	local H = Config.Settings.Hud
	local clean = Settings.clean({ hudLayout = {
		Score = { x = 0.1, y = -0.05, size = 1.2 },
		Chat = { x = 5, y = -5, size = 9 },
		Forfeit = { x = 0 / 0, y = 0, size = 1 },
		Bogus = { x = 0, y = 0, size = 1 },
	} })
	local L = clean.hudLayout
	check(L.Score.x == 0.1 and L.Score.y == -0.05 and L.Score.size == 1.2
		and L.Chat.x == H.MaxShift and L.Chat.y == -H.MaxShift and L.Chat.size == H.MaxSize
		and L.Forfeit == nil and L.Bogus == nil and #H.Pieces == 10,
		"HUD pieces save their shift and size (clamped, no NaN, known pieces only)")
	local button = {}
	for _, name in ipairs(Config.Settings.Touch.Buttons) do
		button[name] = true
	end
	for _, key in ipairs(H.Pieces) do
		check(H.Names[key] ~= nil and not button[key], "HUD piece " .. key .. " has a name and isn't a touch button's")
	end
end

print("== character profiles ==")
do
	local Bios = require("Bios")
	local ok, missing = true, {}
	for id, text in pairs(Bios) do
		ok = ok and Roster.get(id) ~= nil and type(text) == "string" and #text > 80
	end
	for _, c in ipairs(Roster) do
		if c.Tier == "S+" and not Bios[c.Id] then
			table.insert(missing, c.Name)
		end
	end
	check(ok and #missing == 0, "every profile belongs to a roster character, and every S+ has one", table.concat(missing, ", "))
end

print("== lucky spins for VP ==")
do
	local L = Config.Lucky
	local ok = L.VPCost == 750 and #L.Trade > 0
	for _, n in ipairs(L.Trade) do
		ok = ok and n == math.floor(n) and n >= 1
	end
	check(ok, "lucky spins trade at 750 VP each, in whole amounts", string.format("%d VP; %d amounts", L.VPCost or 0, #L.Trade))
end

print("== ball skins ==")
do
	local keys, dupes = {}, false
	for _, item in ipairs(Config.Cosmetics.Ball) do
		dupes = dupes or keys[item.Key] ~= nil
		keys[item.Key] = true
	end
	-- (the Halloween balls are limited: Config.Halloween's banner, not the Ball banner)
	local n = -1
	for _, item in ipairs(Config.Cosmetics.Ball) do
		if not item.Limited then
			n = n + 1
		end
	end
	check(not dupes and Spins.default("Ball") == "Classic" and Spins.isBanner("Ball") and Spins.isCosmetic("Ball") and Config.Cosmetics.Attribute.Ball == "BallSkin" and n >= 6 and n <= 10,
		"ball skins are a cosmetic kind with their own banner; everyone starts with Classic; 6 to 10 new balls", n .. " new")
	-- every skin but Classic has a look in BallSkins, and each textured one an uploaded texture
	local f = io.open(ROOT .. "/src/client/Controllers/BallSkins.lua")
	local src = f and f:read("*a") or ""
	if f then
		f:close()
	end
	local missing = {}
	for _, item in ipairs(Config.Cosmetics.Ball) do
		if item.Key ~= "Classic" and item.Key ~= "BigHead" and not string.find(src, "\n\t" .. item.Key .. " = {", 1, true) then
			table.insert(missing, item.Key)
		end
	end
	local af = io.open(ROOT .. "/src/shared/Assets.lua")
	local asrc = af and af:read("*a") or ""
	if af then
		af:close()
	end
	local block = string.match(asrc, "Assets%.BallSkins = (%b{})") or ""
	for key, id in string.gmatch(block, '(%w+) = "(%d*)"') do
		if id == "" then
			table.insert(missing, key .. " (texture)")
		end
	end
	if block == "" then
		table.insert(missing, "Assets.BallSkins")
	end
	check(#missing == 0 and string.find(src, "BigHead", 1, true) ~= nil, "every ball skin has its look and texture", table.concat(missing, ", "))
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
	check(v.wins == 12 and v.bestStreak == 4 and v.kills == 140 and v.aces == 9 and v.blocks == 0 and v.robux == 897 and v.gifts == 399 and #Leaderboards.Boards == 10 and v.winRate == 0 and v.playTime == 0,
		"nine boards: wins, best win streak, spike kills, aces and blocks from the career counters, Robux spent and gifted, the W/L ratio (none before 20 matches) and playtime")
	-- the W/L ratio board: one number that sorts by the share won, then the wins, and keeps both
	local wr = Leaderboards.valuesOf({ record = { wins = 120, matches = 194 } }).winRate
	local pct, w, l = Leaderboards.unpackWinRate(wr)
	local better = Leaderboards.winRate(130, 60)
	local tieMoreWins = Leaderboards.winRate(124, 76)
	check(math.abs(pct - 61.9) < 1e-9 and w == 120 and l == 74 and better > wr and tieMoreWins > Leaderboards.winRate(62, 38) and Leaderboards.format("winRate", wr) == "61.9%  120 W  74 L" and Leaderboards.format("wins", 1234) == "1,234 wins",
		"the W/L ratio board shows the share won, the wins and the losses, best share first", Leaderboards.format("winRate", wr))
	local merged = Leaderboards.merge({ { userId = 1, value = Leaderboards.winRate(30, 10) } }, { { userId = 1, value = Leaderboards.winRate(30, 20) } }, 10, true)
	local _, mw, ml = Leaderboards.unpackWinRate(merged[1].value)
	check(mw == 30 and ml == 20, "a board that can go down shows a player's fresh value over the stored one")
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

	-- the cropper: a crop keeps its start, its length stays between CropMin and the slot's cut-off
	-- (4 s scoring, 2 s a touch or a jump), the whole front isn't a crop, junk is dropped, and no
	-- slot's attribute name runs into another slot's key
	local SC = require("SoundCrop")
	local P = Config.Perks
	local a = SC.clean("SoundSpike", { s = 1.234, l = 9 })
	local b = SC.clean("ScoreSound", { s = 2, l = 3.5 })
	local short = SC.clean("SoundJump", { s = 0.5, l = 0.01 })
	local whole = SC.clean("SoundSpike", { s = 0, l = P.ActionSeconds })
	local junk = SC.clean("SoundSpike", { s = 0 / 0, l = 1 }) or SC.clean("SoundSpike", "1,2") or SC.clean("SoundSpike", { s = -5, l = 1 / 0 })
	local far = SC.clean("SoundSet", { s = 1e9, l = 1 })
	local clash = false
	for key in pairs(seen) do
		clash = clash or seen[SC.attribute(key)] ~= nil
	end
	check(a and a.s == 1.23 and a.l == P.ActionSeconds and b and b.l == 3.5 and SC.max("ScoreSound") == P.SoundSeconds
		and short and short.l == P.CropMin and whole == nil and junk == nil and far and far.s == P.CropMaxStart and not clash,
		"custom sounds: a crop keeps its start and a length the slot allows; junk and the whole front aren't kept",
		string.format("spike %.2f+%.2f, score %.2f+%.2f", a and a.s or -1, a and a.l or -1, b and b.s or -1, b and b.l or -1))
end

print("== codes, lucky spins, daily rewards, gifts and events ==")
do
	local Economy = require("Economy")
	-- codes: any case and spacing, UPDATE2 pays, a retired one (RELEASE) and unknown ones don't
	local g, why, key = Economy.code("  UpDaTe 2 ", 100)
	local none, noneWhy = Economy.code("nope", 100)
	local old = Economy.code("release", 100)
	check(g ~= nil and key == "update2" and g.VP > 0 and g.Gold > 0 and g.Lucky >= 1 and none == nil and noneWhy == "unknown" and old == nil,
		"the UPDATE2 code works typed any way and pays VP, Gold and a lucky spin; RELEASE and unknown codes pay nothing", g and Economy.describe(g) or tostring(why))
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
	check(lucky.Common == 0 and (counts.Common or 0) == 0 and lucky.Mythic >= normal.Mythic and lucky.Legendary >= 2 * normal.Legendary and lucky.Epic >= 3 * normal.Epic and math.abs((counts.Mythic or 0) / n - lucky.Mythic) < 0.005,
		"a lucky spin never drops a Common; Epic and Legendary come several times as often, S+ at least as often",
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
	-- the 2x VP event, boosts and passes multiply all earned VP (matches, the MVP bonus, tournament
	-- prizes, daily rewards; the owner, 2026-10-16: "only like earnable stuff, like tournaments and
	-- matches and daily rewords. not codes") and nothing else in a grant
	local CupsE = require("Cups")
	local goldCup = CupsE.cup("Gold")
	local prizeVP = CupsE.payout(goldCup, Config.Tournament.Rounds, true)
	local day1 = Economy.daily(nil, 1000000).grant
	local day7 = Economy.daily({ last = 1000000, streak = #D.Rewards - 1 }, 1000000 + D.Cooldown + 60).grant
	local stackedVP = Economy.multiplier({ VP = 5000 }, "VP", 4999) * Economy.boost(fresh, "VP", t0 + 60) * Economy.passMult({ VIP = true, DoubleVP = true }, "VP")
	local d1, d7 = Economy.earnedGrant(day1, 2), Economy.earnedGrant(day7, stackedVP)
	check(Economy.earnedVP(prizeVP, 2) == 2 * goldCup.PrizeVP and Economy.earnedVP(Config.Progression.MvpVP, 1.5) == math.floor(Config.Progression.MvpVP * 1.5 + 0.5)
		and day1.VP == D.Rewards[1].VP and d1.VP == 2 * day1.VP and d7.VP == math.floor(D.Rewards[7].VP * stackedVP + 0.5) and d7.Lucky == day7.Lucky and d7.Gold == day7.Gold
		and day7.VP == D.Rewards[7].VP and Economy.earnedVP(100, 1) == 100 and Economy.earnedVP(100, 0.5) == 100,
		"2x VP (the event, a boost, passes: they stack) multiplies earned VP: a tournament's prize, the MVP bonus, a daily reward's VP but not its spins",
		string.format("Gold Cup %d -> %d VP; day 7 %d VP x%g -> %d", prizeVP, Economy.earnedVP(prizeVP, 2), day7.VP, stackedVP, d7.VP))
end

print("== breakthroughs ==")
do
	local BTm = require("Breakthrough")
	local BT = Config.Breakthrough
	-- fragments go by letter, S+ on its own
	local groups = BTm.group("S-") == "S" and BTm.group("S") == "S" and BTm.group("S+") == "S+" and BTm.group("A+") == "A" and BTm.group("D") == "D"
	-- +5 adds about 40 stat points to a character with an ability, half again to one without
	local yejun, junseo = Roster.get("yejun"), Roster.get("junseo")
	local function total(t)
		local n = 0
		for _, v in pairs(t) do
			n = n + v
		end
		return n
	end
	local withAb, without = total(BTm.stats(yejun, 5)), total(BTm.stats(junseo, 5))
	local _, plain = Characters.fromRoster(yejun, "max")
	local _, broken = Characters.fromRoster(yejun, "max", 5)
	local lifted = broken.Attack - plain.Attack == BTm.stats(yejun, 5).Attack and broken.Attack > yejun.Attack
	-- abilities grow: a share (Thunder's second swing), a multiplier's part over 1 (Turnabout), a table
	-- (Chain Reaction), a duration (Iron Wall); nothing grows at +0, and a setting with no growth stays
	local TH = Config.Abilities.Thunder
	local second = BTm.ab("Thunder", "SecondBoost", 5)
	local turn = BTm.ab("Turnabout", "PowerMul", 5)
	local chain = BTm.ab("ChainReaction", "PowerMul", 5)
	local wall = BTm.ab("IronWall", "Duration", 5)
	local grows = math.abs(second - TH.SecondBoost * 1.3) < 1e-9 and math.abs(turn - (1 + 0.12 * 1.4)) < 1e-9 and chain[3] > Config.Abilities.ChainReaction.PowerMul[3]
		and wall > Config.Abilities.IronWall.Duration and BTm.ab("Thunder", "SecondBoost", 0) == TH.SecondBoost and BTm.ab("Thunder", "Cooldown", 5) == TH.Cooldown
	-- Adrenaline's boost in a touch grows with the toucher's breakthroughs (ctx.breakLevel)
	local shoyo = Characters.derive(Characters.fromRoster(Roster.get("shoyo"), "max"))
	local low = { value = 10, max = 100 }
	local s0 = HitLogic.effectiveStats(shoyo, "Adrenaline", low, {})
	local s5 = HitLogic.effectiveStats(shoyo, "Adrenaline", low, { breakLevel = 5 })
	-- costs and selling: 5 fragments to +5; an S+ fragment sells with a lucky spin, an S one for VP
	local cost = 0
	for i = 0, BT.Max - 1 do
		cost = cost + BTm.cost(i)
	end
	local sPlus, sOne = BTm.sellGrant("S+"), BTm.sellGrant("S")
	local d = BTm.describe(yejun, 5)
	check(groups and withAb >= 35 and withAb <= 45 and without > withAb and lifted and grows and s5.Attack > s0.Attack
		and cost == 5 and BTm.cost(5) == nil and sPlus.Lucky == 1 and sOne.Lucky == 0 and sOne.VP == Config.Spins.SellValue.Legendary
		and #d.stats > 0 and #d.ability == 4 and d.ability[4][1] == "Cooldown" and BTm.level(9) == 5 and BTm.level(-2) == 0 and BTm.cleanFragments({ S = 3, Q = 9, A = -1 }).S == 3,
		"Breakthroughs: letter fragments (S+ its own), +5 for 5 of them adds ~40 stats past the ceiling (more without an ability) and grows the ability; S+ fragments sell with a lucky spin",
		string.format("+5: %d stat points (%d without an ability); second swing %.0f%% -> %.0f%%; Adrenaline Attack +%d -> +%d", withAb, without, TH.SecondBoost * 100, second * 100, s0.Attack - shoyo.Attack, s5.Attack - shoyo.Attack))
end

print("== breakthroughs: lower tiers gain more, cooldowns shorter ==")
do
	-- the owner (2026-10-15): "make breakthroughs way more powerful on lower tier" and "make ability
	-- cooldowns reduced"
	local BTm = require("Breakthrough")
	local BT = Config.Breakthrough
	local function sum(t)
		local n = 0
		for _, v in pairs(t) do
			n = n + v
		end
		return n
	end
	local function maxed(c, brk)
		local _, b = Characters.fromRoster(c, "max", brk)
		return b.Attack + b.Defense + b.Speed + b.Jump
	end
	-- by tier, wing spikers without an ability (D, C, B, A) and the S+ with one
	local riku, eunwoo, nagi, sora, dante = Roster.get("riku"), Roster.get("eunwoo"), Roster.get("nagi"), Roster.get("sora"), Roster.get("dante")
	local gain = { D = sum(BTm.stats(riku, 5)), C = sum(BTm.stats(eunwoo, 5)), B = sum(BTm.stats(nagi, 5)), A = sum(BTm.stats(sora, 5)), SP = sum(BTm.stats(dante, 5)) }
	-- ("a d shouldn't be hitting low s"): a +5 D-tier comes close to a maxed A-tier but stays under
	-- every maxed S, and under a +5 S+
	local dPlus5, aMax = maxed(riku, 5), maxed(sora)
	local dTop, sLow, sLowName = 0, math.huge, "?"
	for _, c in ipairs(Roster) do
		if c.Tier == "D" then
			dTop = math.max(dTop, maxed(c, 5))
		elseif c.Tier == "S" and maxed(c) < sLow then
			sLow, sLowName = maxed(c), c.Name
		end
	end
	check(gain.D > gain.C and gain.C > gain.B and gain.B > gain.A and gain.A > gain.SP and gain.D >= 3 * gain.SP and dTop < sLow and dPlus5 >= aMax - 40 and maxed(riku, 5) < maxed(dante, 5),
		"breakthroughs give lower tiers far more: a +5 D-tier comes close to a maxed A-tier, under every maxed S and a +5 S+",
		string.format("+5 adds D %d, C %d, B %d, A %d, S+ %d; best +5 D %d vs lowest maxed S (%s) %d; +5 Riku %d vs maxed Sora (A) %d", gain.D, gain.C, gain.B, gain.A, gain.SP, dTop, sLowName, sLow, dPlus5, aMax))
	local cd0, cd5, cd3 = BTm.cooldown("Thunder", 0), BTm.cooldown("Thunder", 5), BTm.cooldown("Thunder", 3)
	check(cd0 == Config.Abilities.Thunder.Cooldown and math.abs(cd5 - cd0 * (1 - BT.CooldownCut)) < 1e-9 and cd3 < cd0 and cd3 > cd5 and BTm.cooldown("Thunder", 99) == cd5
		and BTm.cooldown("Adrenaline", 5) == nil and BTm.cooldown(nil, 5) == nil and BT.CooldownCut <= 0.2,
		string.format("breakthroughs shorten an active ability's cooldown a little, %d%% at +5 (passives have none)", math.floor(BT.CooldownCut * 100 + 0.5)), string.format("Storm Call %.0f s -> %.1f s at +5", cd0, cd5))
	-- (the owner, 2026-10-21: "joon should have increased buff power not cooldown reduction"): Rally
	-- Cry and the Dictate keep their cooldowns and grow their effect instead; Storm Call and Iron
	-- Wall's shut-down grow too
	local A = Config.Abilities
	local rb0, rb5 = BTm.ab("RallyCry", "Boost", 0), BTm.ab("RallyCry", "Boost", 5)
	local base = Characters.stats("S")
	local r0 = HitLogic.effectiveStats(base, nil, nil, { teamBoost = rb0 })
	local r5 = HitLogic.effectiveStats(base, nil, nil, { teamBoost = rb5 })
	local st5 = BTm.ab("Tyrant", "Steal", 5)
	local d5 = HitLogic.effectiveStats(base, nil, nil, { dictated = st5 })
	check(BTm.cooldown("RallyCry", 5) == A.RallyCry.Cooldown and BTm.cooldown("Tyrant", 5) == A.Tyrant.Cooldown and rb5 > rb0 * 1.4 and r5.Attack > r0.Attack
		and st5 > A.Tyrant.Steal and d5.Jump < base.Jump * (1 - A.Tyrant.Steal) and BTm.ab("Thunder", "StormBoost", 5) > A.Thunder.StormBoost and BTm.ab("IronWall", "StuffKmh", 5) > A.IronWall.StuffKmh,
		"breakthroughs grow Rally Cry's boost and the Dictate's steal (their cooldowns stay), Storm Call's power and Iron Wall's shut-down",
		string.format("Rally Cry +%.0f%% -> +%.0f%% (Attack %d -> %d); steal %.0f%% -> %.0f%%", rb0 * 100, rb5 * 100, r0.Attack, r5.Attack, A.Tyrant.Steal * 100, st5 * 100))
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
		ok = ok and (c.Stat == nil or c.Stat == "rank" or c.Stat == "clanRank" or c.Stat == "grant" or stats0[c.Stat] ~= nil) and (c.Show == nil or c.Show == "rank" or c.Show == "clanRank" or c.Show == "winRate" or c.Show == "ranked" or stats0[c.Show] ~= nil)
		ok = ok and (c.Stat ~= "grant" or c.Grant == true)
		seen[c.Key] = true
	end
	-- the Win/Loss card: the share won, then the wins and losses; the Content Creator card is only given
	local wlStats = Cards.stats({ record = { wins = 120, matches = 194 } }, 0)
	local wv, wlab = Cards.display(Cards.get("WinLoss"), wlStats)
	local creator = Cards.get("Creator")
	local Economy = require("Economy")
	local g = Economy.cleanGrant({ Cards = { "Creator", "Rookie", "Creator", "Bogus" } })
	local prof = { cards = {} }
	Economy.apply(prof, g, 0)
	check(wv == "62%" and wlab == "120 W  74 L" and Cards.met(Cards.get("WinLoss"), wlStats) and not Cards.met(creator, wlStats) and Cards.isGrant(creator)
		and #g.Cards == 1 and prof.cards.Creator == true and not Economy.isEmpty(g) and Cards.look(creator, nil, nil).Avatar == true,
		"the Win/Loss card shows the share won and the record; the Content Creator card is given, never earned", wv .. " / " .. wlab)
	-- the Bug Catcher card: given and taken from the admin panel only, with its hanging net
	local bugCard = Cards.get("BugCatcher")
	local bugGrant = Economy.cleanGrant({ Cards = { "BugCatcher" } })
	check(bugCard ~= nil and Cards.isGrant(bugCard) and not Cards.met(bugCard, wlStats) and Cards.look(bugCard).Fx.Net == true and bugGrant.Cards[1] == "BugCatcher",
		"the Bug Catcher card is given, never earned, and hangs its net")
	-- the Ranked card (the owner, 2026-10-21): the season, this season's W and L and the rank, its
	-- colours and badge following the rank now
	local rcard = Cards.get("Ranked")
	local rstats = Cards.stats({ ranked = { season = 2, rp = 1250, wins = 12, losses = 4, history = {} } }, 0)
	local rv, rl = Cards.display(rcard, rstats)
	local rlook = Cards.look(rcard, nil, nil, rstats.rankedRp)
	local blook = Cards.look(rcard, nil, nil, 0)
	check(rv == "SEASON 2" and rl == "W:12  L:4  DIAMOND I" and rlook.Badge == "RankDiamond1" and rlook.Sweep == Config.Ranked.Ranks[5].Color and blook.Badge == "RankBronze1"
		and Cards.met(rcard, rstats) and not Cards.met(rcard, Cards.stats({}, 0)),
		"the Ranked card: the season, W and L and the rank; its colours and badge follow your rank; unlocked by a ranked match", rv .. " / " .. rl)
	local default = Cards.get(Cards.default())
	check(ok and default and not default.Stat and #Cards.list() >= 10, "player cards: each has its own look, goal and achievement; the default needs nothing", #Cards.list() .. " cards")
	-- they unlock by achievement: a streak, wins, spikes, MVPs, recruits, a leaderboard place
	local prof = { record = { wins = 120, kills = 40, aces = 3, blocks = 0, matches = 150, mvps = 30 }, winStreak = 2, bestStreak = 6, bestRank = { rank = 2, board = "kills" } }
	local st = Cards.stats(prof, 22)
	local function met(key)
		return Cards.met(Cards.get(key), st)
	end
	-- quick chat: the owner's phrases are in, more than them, emojis too, and a spam limit
	do
		local QC = require("Config").QuickChat
		local has = {}
		for _, p in ipairs(QC.Phrases) do
			has[p] = true
		end
		local Settings = require("Settings")
		local w = Settings.quickWheel({ "E3", "bogus", "P99", "P10" })
		local cleaned = Settings.clean({ quickWheel = { "E2" } }).quickWheel
		check(#w == 8 and w[1] == "E3" and w[2] == QC.Wheel[2] and w[3] == QC.Wheel[3] and w[4] == "P10" and cleaned[1] == "E2" and #cleaned == 8 and Settings.quickPick("E2") == "Emoji",
			"quick chat wheel: 8 slots, your picks kept, bad ones back to the default")
		check(has["Nice play!"] and has["Set me!"] and has["Lag"] and has["Ref!"] and has["GG"] and #QC.Phrases >= 20 and #QC.Emojis >= 20 and QC.Burst >= 1 and QC.Gap > 0 and QC.Window > QC.Gap,
			"quick chat: the asked-for phrases and more, 20+ emojis, a rate limit", #QC.Phrases .. " phrases, " .. #QC.Emojis .. " emojis")
	end
	-- Dev Defeater: a win over a developer's team
	local devSt = Cards.stats({ record = { devWins = 1 } }, 0)
	check(Cards.met(Cards.get("DevDefeater"), devSt) and not Cards.met(Cards.get("DevDefeater"), Cards.stats({ record = {} }, 0)),
		"the Dev Defeater card unlocks with one win over a developer's team")
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
	-- normal recruits count toward an S+ too, at 350 (the S+ one wins when both are due)
	local both = Spins.newPity()
	both.normal, both.top = PT.Normal.Every - 1, PT.Top.Every - 1
	local tk, th = Spins.pityRoll(both, rng, false)
	check(th == "pity" and tierOf(tk) == "S+" and both.top == 0 and both.normal == 0, "S+ pity: the 350th normal recruit without an S+ is one (it wins over the S tier pity due on the same pull)", tk)
	local longS, longTop, sinceS, sinceTop = 0, 0, 0, 0
	local run2 = Spins.newPity()
	for _ = 1, 20000 do
		local key = Spins.pityRoll(run2, rng, false)
		local t = tierOf(key)
		sinceS, sinceTop = sinceS + 1, sinceTop + 1
		if string.sub(t, 1, 1) == "S" then
			longS = math.max(longS, sinceS)
			sinceS = 0
		end
		if t == "S+" then
			longTop = math.max(longTop, sinceTop)
			sinceTop = 0
		end
	end
	check(longS <= PT.Normal.Every and longTop <= PT.Top.Every, "20,000 recruits: never more than 200 between S tiers, nor 350 between S+", string.format("longest waits %d and %d", longS, longTop))
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

print("== recruits land on a tier first ==")
do
	-- the owner (2026-10-15): "make it 0.5% to hit the s+ tier, then one of the ones in there, that
	-- are boosted. make it like that for s tier as well. make it all up to equal 100"
	local TO = Config.Spins.TierOdds
	local sums, all = {}, 0
	for t, w in pairs(TO) do
		local r = Spins.tierRarity(t)
		sums[r] = (sums[r] or 0) + w
		all = all + w
	end
	local adds = math.abs(all - 100) < 1e-9
	for r, w in pairs(Config.Rarity.Weights) do
		adds = adds and math.abs((sums[r] or 0) - w) < 1e-9
	end
	local function tierTotals(weights, favor)
		local out, shares = {}, {}
		for _, row in ipairs(Spins.table("Char", weights, favor)) do
			local t = row.group.tier
			out[t] = (out[t] or 0) + row.chance
			shares[t] = (shares[t] or 0) + row.share
		end
		return out, shares
	end
	local base = tierTotals()
	local boosted, shares = tierTotals(nil, { daon = "up", ines = "down" })
	local lucky = tierTotals(Spins.LuckyWeights)
	local total = 0
	for _, g in ipairs(Spins.groups("Char")) do
		total = total + g.chance
	end
	local sharesOk = true
	for _, v in pairs(shares) do
		sharesOk = sharesOk and math.abs(v - 1) < 1e-9
	end
	check(adds and math.abs(total - 1) < 1e-9 and math.abs(base["S+"] - 0.0001) < 1e-9 and math.abs(base.S - 0.00185) < 1e-9 and math.abs(base["S-"] - 0.0031) < 1e-9 and base.S < base["S-"]
		and math.abs(boosted.S - base.S) < 1e-12 and math.abs(boosted["S-"] - base["S-"]) < 1e-12 and sharesOk and math.abs(lucky["S+"] - 0.005) < 1e-9,
		"a recruit lands on a tier first (S+ 0.01%, S 0.185%, S- 0.31%: every tier adds up to 100%), then on one of its players; Boost and Lower move odds inside the tier only",
		string.format("S+ %.2f%%, S %.2f%%, S- %.2f%% (lucky spin: S+ %.1f%%, S %.2f%%)", base["S+"] * 100, base.S * 100, base["S-"] * 100, lucky["S+"] * 100, lucky.S * 100))
end

print("== boost and lower ==")
do
	local F = Config.Spins.Favor
	local base = {}
	for _, row in ipairs(Spins.table("Char")) do
		base[row.item.Key] = row.chance
	end
	local favor = { yejun = "up", seojin = "down" }
	local fav, rarity, rarityBase = {}, 0, 0
	for _, row in ipairs(Spins.table("Char", nil, favor)) do
		fav[row.item.Key] = row.chance
		if row.item.Rarity == "Mythic" then
			rarity = rarity + row.chance
			rarityBase = rarityBase + base[row.item.Key]
		end
	end
	check(fav.yejun > base.yejun and fav.seojin < base.seojin and math.abs(rarity - rarityBase) < 1e-9 and math.abs(fav.aoi - base.aoi) < 1e-12,
		"Boost raises a character's odds and Lower cuts them, inside the rarity only (Mythic stays the same)", string.format("YeJun %.3f%% -> %.3f%%, Seojin %.3f%% -> %.3f%%", base.yejun * 100, fav.yejun * 100, base.seojin * 100, fav.seojin * 100))
	-- rolled: a boosted S+ comes more often than a lowered one
	local rng = Random.new(11)
	local up, down = 0, 0
	for _ = 1, 20000 do
		local k = Spins.rollItem("Char", rng, Spins.LuckyWeights, favor)
		if k == "yejun" then
			up = up + 1
		elseif k == "seojin" then
			down = down + 1
		end
	end
	check(up > down * 2, "20,000 lucky pulls: the boosted S+ comes about three times as often as the lowered one", up .. " vs " .. down)
	local clean = Spins.cleanFavor({ riku = "up", yejun = "up", seojin = "up", dante = "up", hayun = "up", shoyo = "down", aoi = "sideways" })
	local ups, downs = Spins.favorCounts(clean)
	check(ups == F.MaxBoost and downs == 1 and clean.riku == nil and clean.aoi == nil, "saved choices are made safe: no starters, no more than the limit", ups .. " boosted, " .. downs .. " lowered")
end

print("== the block drill fits every blocker ==")
do
	local PRc = Config.Practice
	local worst, worstName = math.huge, ""
	for _, c in ipairs(Roster) do
		local st = Characters.derive(Characters.fromRoster(c, nil))
		local top = GROUND + Characters.jumpHeight(st, GROUND) + Characters.hangGain() + Z.BlockReachUp
		local room = top - PRc.BlockReachMargin - (Config.Court.NetTop + PRc.BlockAboveNet)
		if room < worst then
			worst, worstName = room, c.Name
		end
	end
	check(worst > 0 and PRc.BotTier == "D", "practice bots are D tier, and the block drill's spike is reachable by every character, fresh", string.format("least room %.2f studs (%s)", worst, worstName))

	-- their setter's set (PracticeService.setAndAttack) comes down on the attacker's hand, on
	-- their side, late enough for the attacker's jump and a read of it
	local side = Court.sideOf("Away")
	local spot = Court.formationSpot("Offense", "SE", side)
	local hand = Vector3.new(0, GROUND + 3.2, spot.Z)
	local p = Vector3.new(0, Config.Court.NetTop + PRc.AttackAboveNet, side * PRc.AttackDepth)
	local g = Config.Ball.Gravity * Config.Hits.SetGravityScale
	local v, T = HitLogic.solveArc(hand, p, math.max(hand.Y, p.Y) + PRc.DrillSetRise, g)
	local path = BallPhysics.buildPath(BallPhysics.newLaunch(hand, v, Vector3.new(0, -g, 0), 0))
	local at = BallPhysics.positionAt(path, T)
	local own = true
	for i = 0, 10 do
		own = own and BallPhysics.positionAt(path, T * i / 10).Z * side > 0
	end
	check((at - p).Magnitude < 0.3 and own and T > PRc.AttackWindup + 0.6 and T < 2.5, "the drill's set reaches their attacker's hand on their side, with time to read it", string.format("%.2f s, off by %.2f studs", T, (at - p).Magnitude))

	-- the drill's spike (PracticeService.attack, 1.2 m off the net) is through the block within a few
	-- hundredths of a second, before a phone hears of it: the client checks an attack it heard of
	-- late from where it left the hand (HitLogic.blockAlong; the owner, 2026-10-16: "there seems to be
	-- a bug with the hitboxes on the blocking tutorial", Taeho's block missing every spike)
	local me = Court.sideOf("Home")
	local taeho = Characters.derive(Characters.fromRoster(Roster.get("taeha"), nil))
	local broot = vec(0, GROUND + Characters.jumpHeight(taeho, GROUND) + Characters.hangGain(), me * Config.Player.BlockReach * 0.5)
	local fromY = math.max(math.min(Config.Court.NetTop + PRc.AttackAboveNet, broot.Y + Z.BlockReachUp - PRc.BlockReachMargin), Config.Court.NetTop + PRc.BlockAboveNet)
	local from = vec(0, fromY, side * PRc.AttackDepth)
	local function drillSpike(kmh, depth)
		local target = vec(0, Config.Ball.Radius, me * depth)
		local Ts = (target - from).Magnitude / (kmh / 3.6 * SPM)
		local vs = (target - from) / Ts + vec(0, 0.5 * Config.Ball.Gravity * Ts, 0)
		return BallPhysics.buildPath(BallPhysics.newLaunch(from, vs, vec(0, -Config.Ball.Gravity, 0), 0))
	end
	local through, found, fast = 0, true, true
	for _, kmh in ipairs({ PRc.BlockKmh[1], PRc.BlockKmh[2] }) do
		for _, depth in ipairs({ PRc.BlockTargetDepth[1], PRc.BlockTargetDepth[2] }) do
			local sp = drillSpike(kmh, depth)
			local tB = HitLogic.blockAlong(sp, 0, 0.3, broot, me, taeho, nil)
			found = found and tB ~= nil
			through = math.max(through, tB or 1)
			-- (a client hearing of it 0.1 s late, checking only that frame, finds nothing)
			fast = fast and HitLogic.blockAlong(sp, 0.1, 0.1 + 1 / 60, broot, me, taeho, nil) == nil
		end
	end
	-- a 260 km/h spike over the whole rewind still can't slip between two checks
	local rocket = drillSpike(260, PRc.BlockTargetDepth[1])
	check(found and through < 0.08 and fast and HitLogic.blockAlong(rocket, 0, Config.Net.MaxRewind, broot, me, taeho, nil) ~= nil,
		"the block drill's spikes reach Taeho's block within 0.08 s of the hand (a late frame alone misses them); checked from the hand, every one is blocked, a 260 km/h one too",
		string.format("met the hands %.3f s after the hit at the latest", through))
end

print("== the admin whitelist ==")
do
	-- the owner (2026-10-16): "add a whitelist to the admin panel that only i can access": the stored
	-- list is made safe (whole ids, plain usernames, at most WhitelistMax, the earliest kept) and
	-- listed by name
	local Economy = require("Economy")
	local raw = { ["123"] = { n = "Zed", t = 5 }, ["45"] = { n = "amy_b", t = 2 }, ["-3"] = { n = "neg", t = 1 }, ["1.5"] = { n = "half", t = 1 }, abc = { n = "x", t = 1 }, ["77"] = { n = "<b>bad</b>", t = 9 }, ["88"] = "junk" }
	for i = 1, Config.Admin.WhitelistMax + 5 do
		raw[tostring(1000 + i)] = { n = "filler" .. i, t = 100 + i }
	end
	local clean = Economy.cleanAdmins(raw)
	local n = 0
	for _ in pairs(clean) do
		n = n + 1
	end
	local listed = Economy.adminList({ ["123"] = { n = "Zed", t = 5 }, ["45"] = { n = "amy_b", t = 2 } })
	check(n == Config.Admin.WhitelistMax and clean["123"] and clean["45"] and clean["77"] and clean["77"].n == "77" and not clean["-3"] and not clean["1.5"] and not clean.abc and not clean["88"]
		and not clean[tostring(1000 + Config.Admin.WhitelistMax + 5)] and #listed == 2 and listed[1].name == "amy_b" and listed[1].id == 45 and listed[2].name == "Zed"
		and next(Economy.cleanAdmins(nil)) == nil,
		"the admin whitelist is kept clean: whole ids and plain names only, no more than the cap (the earliest stay), listed by name",
		n .. " kept of " .. (Config.Admin.WhitelistMax + 12))
end

print("== codes ==")
do
	local Economy = require("Economy")
	local g1 = Economy.code(" Update1 ")
	local g0 = Economy.code("UPDATE2")
	check(g1 and g1.VP == 350 and g1.Gold == 6000 and g1.Lucky == 3 and g0 and g0.VP == 500 and g0.Gold == 5000 and g0.Lucky == 1 and Economy.code("update 1") ~= nil and Economy.code("RELEASE") == nil,
		"the codes UPDATE1 and UPDATE2 (RELEASE's rewards) work in any case, spaces ignored; RELEASE is retired")
end

print("== feints get past blocks and break a low guard ==")
do
	-- the owner (2026-10-16): "Buff faints. Right now they cannot go over any blocks. Especially
	-- tetsuo. In tsc, faints ... break stamina when they are low and usually never get blocked. Sure
	-- it still can, but a very light soft touch block"
	local tet = Characters.derive(Characters.fromRoster(Roster.get("tetsuo"), "max"))
	local broot = vec(0, GROUND + Characters.jumpHeight(tet, GROUND) * 0.9, side * 1.2)
	local hands = vec(0, broot.Y + Z.BlockReachUp - 1.2, side * 0.6)
	local touched, soft, stuffed = 0, true, false
	for seq = 1, 200 do
		local wall = seq % 2 == 0 -- (half with Iron Wall up)
		local okB, rB = HitLogic.compute({ action = "Block", t = 0, root = broot, ball = hands, vy = 0, grounded = false },
			ctx({ ability = "IronWall", stats = tet, ironWall = wall or nil, lastHit = { hitType = "Feint", team = "Home", kmh = 32 }, ballVel = vec(0, -6, side * 12), seq = seq }))
		if okB then
			touched = touched + 1
			soft = soft and rB.meta.outcome == "Soft" and not rB.meta.perfectBlock
			stuffed = stuffed or rB.meta.outcome == "Stuff"
		end
	end
	-- dug: a little guard at a healthy bar, the guard broken at a low one
	local root = vec(0, GROUND, side * 18 * K)
	local ball = vec(0, root.Y + Z.ReceiveIdealY, root.Z - side * Z.ReceiveForward)
	local feintHit = { team = "Home", hitType = "Feint", kmh = 32, noDrain = true }
	local _, high = receive(root, ball, { value = 100, max = 100 }, { stanceAge = 0.6 }, { lastHit = feintHit, ballVel = vec(0, -8, side * 10) })
	local _, low = receive(root, ball, { value = 25, max = 100 }, { stanceAge = 0.6 }, { lastHit = feintHit, ballVel = vec(0, -8, side * 10) })
	check(touched > 0 and touched < 80 and soft and not stuffed and (high.meta.drain or 0) == Config.Hits.FeintDrain and not high.meta.breaks and low.meta.breaks and (low.meta.drain or 0) > 25,
		"feints float over most blocks (Tetsuo, Iron Wall up or not: touched now and then, never stuffed, only softened); dug, they chip the guard and break a low one",
		string.format("%d of 200 blocks touched; dug at 100%%: -%d, at 25%%: guard broken", touched, high.meta.drain or 0))
end

print("== 2x luck ==")
local Economy = require("Economy")
do
	local base, luck = Spins.odds("Char"), Spins.odds("Char", Spins.LuckEventWeights)
	local sum = 0
	for _, r in ipairs(Config.Rarity.Order) do
		sum = sum + luck[r]
	end
	check(math.abs(luck.Epic - 2 * base.Epic) < 1e-9 and math.abs(luck.Legendary - 2 * base.Legendary) < 1e-9 and math.abs(luck.Mythic - 2 * base.Mythic) < 1e-9
		and math.abs(luck.Rare - base.Rare) < 1e-9 and luck.Common < base.Common and math.abs(sum - 1) < 1e-9 and Economy.isEvent("Luck"),
		"2x Luck: A- and up twice as likely, the Commons (D and C) pay for it, Rare as it is", string.format("Common %.1f%% -> %.1f%%, Epic %.1f%% -> %.1f%%, Legendary %.1f%% -> %.1f%%, Mythic %.2f%% -> %.2f%%",
			base.Common * 100, luck.Common * 100, base.Epic * 100, luck.Epic * 100, base.Legendary * 100, luck.Legendary * 100, base.Mythic * 100, luck.Mythic * 100))
end

print("== 2x luck stacks ==")
do
	local base = Spins.odds("Char")
	local four = Spins.odds("Char", Spins.luckWeights(4))
	local sum = 0
	for _, r in ipairs(Config.Rarity.Order) do
		sum = sum + four[r]
	end
	check(Spins.luckWeights(1) == nil and Spins.luckWeights(2) == Spins.LuckEventWeights and math.abs(four.Mythic - 4 * base.Mythic) < 1e-9 and math.abs(four.Legendary - 4 * base.Legendary) < 1e-9
		and math.abs(four.Rare - base.Rare) < 1e-9 and four.Common >= 0 and four.Common < base.Common and math.abs(sum - 1) < 1e-9,
		"the event's 2x Luck and your own stack: 4x (A- and up four times as likely, the Commons pay)", string.format("Common %.1f%%, Epic %.1f%%, Legendary %.1f%%, Mythic %.1f%%", four.Common * 100, four.Epic * 100, four.Legendary * 100, four.Mythic * 100))
end

print("== 2x luck boosts ==")
do
	local Economy = require("Economy")
	local entry = Economy.pack("LuckBoost", 2)
	local g = Economy.packGrant(entry)
	local prof = { boosts = {} }
	Economy.apply(prof, g, 1000)
	local again = Economy.cleanGrant({ BoostLuck = 15 * 60 })
	Economy.apply(prof, again, 1000)
	check(entry and #Config.Boosts.LuckPacks == 4 and g.BoostLuck == 30 * 60 and prof.boosts.Luck == 1000 + 45 * 60 and Economy.boost(prof, "Luck", 1000 + 60) == 2 and Economy.boost(prof, "Luck", 1000 + 46 * 60) == 1 and not Economy.isEmpty(again) and Economy.describe(again) == "2x Luck for 15 minutes",
		"a 2x Luck pack gives its time (more adds on top) and then runs out", Economy.describe(g))
end

print("== ranked ==")
do
	-- the owner (2026-10-21): Bronze, Silver, Gold, Platinum, Diamond (three divisions each),
	-- Mighty and Almighty; one rank overall; monthly seasons
	local Ranked = require("Ranked")
	local RC = Config.Ranked
	local names = { Ranked.name(0), Ranked.name(99), Ranked.name(100), Ranked.name(299), Ranked.name(300), Ranked.name(1499), Ranked.name(1500), Ranked.name(1999), Ranked.name(2000), Ranked.name(9000) }
	-- (divisions climb I, II, III like Roblox RIVALS: the owner, 2026-10-21)
	local expect = { "Bronze I", "Bronze I", "Bronze II", "Bronze III", "Silver I", "Diamond III", "Mighty", "Mighty", "Almighty", "Almighty" }
	local namesOk = true
	for i, n in ipairs(expect) do
		namesOk = namesOk and names[i] == n
	end
	-- (the owner, 2026-10-21): a stronger team pays more and costs less, a weaker one the other way;
	-- the higher your rank, the less a win pays and the more a loss costs
	local plat = 1000 -- Platinum II: the plain +25 / -20
	local even, evenL = Ranked.change(true, plat, plat), Ranked.change(false, plat, plat)
	local upset, upsetL = Ranked.change(true, plat, plat + 400), Ranked.change(false, plat, plat + 400)
	local stomp, stompL = Ranked.change(true, plat, plat - 400), Ranked.change(false, plat, plat - 400)
	local bronzeW, bronzeL = Ranked.change(true, 50, 50), Ranked.change(false, 50, 50)
	local topW, topL = Ranked.change(true, 2100, 2100), Ranked.change(false, 2100, 2100)
	local mightyW, mightyL = Ranked.change(true, 1600, 1600), Ranked.change(false, 1600, 1600)
	local climbOk = bronzeW > even and even > mightyW and mightyW > topW and -bronzeL < -evenL and -evenL < -mightyL and -mightyL < -topL
	local diffOk = upset > even and even > stomp and -upsetL < -evenL and -evenL < -stompL
	print(string.format("   even +%d/%d; vs 4 divisions up +%d/%d; down +%d/%d; Bronze +%d/%d; Mighty +%d/%d; Almighty +%d/%d", even, evenL, upset, upsetL, stomp, stompL, bronzeW, bronzeL, mightyW, mightyL, topW, topL))
	-- seasons: Season 1 to the end of November 2026 (Chicago), then one a month
	local oct21 = 1792594800 -- 2026-10-21 about 09:00 Chicago
	local s1, s2 = Ranked.season(oct21), Ranked.season(Ranked.seasonEnds(1) + 60)
	local endsNov = Ranked.seasonEnds(1)
	-- a record rolls over: the last season to history, half the RP kept
	local rec = Ranked.clean({ season = 1, rp = 820, wins = 30, losses = 12, peak = 900 }, 2)
	local fresh = Ranked.clean(nil, 1)
	local d = Ranked.apply(fresh, true, 0)
	local keys = Ranked.badgeKeys()
	check(Ranked.badgeKey(0) == "RankBronze1" and Ranked.badgeKey(299) == "RankBronze3" and Ranked.badgeKey(300) == "RankSilver1" and Ranked.badgeKey(1600) == "RankMighty"
		and Ranked.badgeKey(5000) == "RankAlmighty" and #keys == 17 and keys[1] == "RankBronze1" and keys[15] == "RankDiamond3" and keys[17] == "RankAlmighty",
		"ranked badges: one per division, Bronze I to Diamond III, then Mighty and Almighty (17)")
	check(namesOk and even == RC.Win and evenL == -RC.Loss and diffOk and climbOk and s1 == 1 and s2 == 2 and Ranked.season(endsNov - 60) == 1
		and rec.season == 2 and rec.rp == 410 and rec.wins == 0 and rec.history[1].season == 1 and rec.history[1].wins == 30 and rec.history[1].peak == 900
		and fresh.rp == d and fresh.wins == 1 and Ranked.apply({ rp = 5, wins = 0, losses = 0, peak = 5 }, false, 0) == -5 and Ranked.apply({ rp = plat, wins = 0, losses = 0, peak = plat }, false, plat) == -RC.Loss,
		"ranked: Bronze I to Almighty, +25 / -20 moved by the other team's strength and by your rank (easy low, harsh high), monthly seasons (Season 1 to December), half your RP into a new season",
		table.concat(names, ", ") .. string.format("; upset +%d / %d; S1 ends %d", upset, upsetL, endsNov))
end

print("== the speed cap ==")
do
	-- (the owner, 2026-10-21: "dante is hitting 400 kmh and yejun is easily breaking 300" with buffs)
	local H2 = Config.Hits
	local dante = Characters.derive(Characters.fromRoster(Roster.get("dante"), "max", 5))
	local r = apexRoot(dante, 3.5 * K)
	local b = ballAt(r, Z.SpikeCenterDz, Z.SpikeCenterDy)
	-- everything at once: a +5 Dante's first strike in Bloodlust, Rally Cry on, off a Tyrant's Set in the Dictate
	local _, stacked = spike(r, b, { stats = dante, ability = "Feral", breakLevel = 5, bloodlust = true, firstStrike = true, teamBoost = 0.18, dictate = true,
		lastHit = { team = "Away", hitType = "Set", tyrantSet = true, absolute = true } }, { gauge = 1.65, toward = true })
	check(HitLogic.softCap(200) == 200 and HitLogic.softCap(H2.SpeedKnee) == H2.SpeedKnee and math.abs(HitLogic.softCap(300) - 270) < 1e-9 and HitLogic.softCap(1000) == H2.SpeedMax
		and stacked.meta.kmh <= H2.SpeedMax + 1 and stacked.meta.kmh > H2.SpeedKnee,
		"the speed cap: past 250 km/h a boost counts 40%, never past 300; everything stacked on a +5 Dante stays under it",
		string.format("266 -> %.0f, 300 -> %.0f, 400 -> %.0f; the full stack %.0f km/h", HitLogic.softCap(266), HitLogic.softCap(300), HitLogic.softCap(400), stacked.meta.kmh))
end

print("== match modifiers ==")
do
	-- (the owner, 2026-10-21: "add custom match modifiers, like more power, low gravity, no ability cd
	-- like rocket league. add more than just what i added")
	local Mutators = require("Mutators")
	local str = Mutators.clean({ Power = "Super", Gravity = "Bogus", Stamina = "Endless", Jump = "High", Blocks = "Off", Cooldowns = "None", Abilities = "Normal" })
	local e = Mutators.effects(str)
	local again = Mutators.clean(str)
	local root = apexRoot(SP, 3.5 * K)
	local ball = ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local _, plain = spike(root, ball)
	local _, super = spike(root, ball, { mut = e })
	-- Endless: a heavy receive drains nothing; Fragile: double
	local rroot = vec(0, GROUND, side * 18 * K)
	local rball = vec(0, rroot.Y + Z.ReceiveIdealY, rroot.Z - side * Z.ReceiveForward)
	local function recv(mut)
		return HitLogic.compute({ action = "Bump", t = 0, root = rroot, ball = rball, vy = 0, grounded = true, stanceAge = 0.6 },
			ctx({ ballVel = vec(0, -30 * K, side * 110 * K), lastHit = { team = "Home", hitType = "Spike", kmh = 160 }, touchNumber = 1, stamina = { value = 200, max = 200 }, mut = mut }))
	end
	local _, r0 = recv(nil)
	local _, rEnd = recv(e)
	local _, rFrag = recv(Mutators.effects("Stamina=Fragile"))
	-- no blocks
	local broot = vec(0, GROUND + Characters.jumpHeight(SP, GROUND) * 0.8, side * 1.2)
	local palms = vec(0, broot.Y + Z.BlockReachUp + Config.Ball.Radius - 1.5, side * 0.6)
	local okB, why = HitLogic.compute({ action = "Block", t = 0, root = broot, ball = palms, vy = 0, grounded = false },
		ctx({ lastHit = { team = "Home", hitType = "Spike", kmh = 120 }, ballVel = vec(0, -8, side * 30), mut = e }))
	-- gravity: a lighter ball, then back
	HitLogic.setGravity(0.45)
	local moonG = HitLogic.ballGravity()
	HitLogic.setGravity(1)
	local stats = HitLogic.effectiveStats(SP, nil, nil, { mut = e })
	check(str == "Power=Super;Cooldowns=None;Stamina=Endless;Jump=High;Blocks=Off" and again == str and e.spike == 1.5 and e.cooldown == 0 and e.noBlocks
		and math.abs(super.meta.kmh / plain.meta.kmh - 1.5) < 0.03 and (r0.meta.drain or 0) > 0 and rEnd.meta.drain == nil and math.abs(rFrag.meta.drain / r0.meta.drain - 2) < 0.01
		and not okB and why == "off" and math.abs(moonG - Config.Ball.Gravity * 0.45) < 1e-6 and HitLogic.ballGravity() == Config.Ball.Gravity
		and stats.Jump == SP.Jump + 25 and Mutators.effects("") == nil and Mutators.clean(nil) == "" and #Mutators.describe(str) == 5,
		"match modifiers: Super power x1.5, Endless stamina drains nothing (Fragile double), no blocks, Moon gravity, +25 Jump; unknown picks dropped",
		string.format("%s; %.0f -> %.0f km/h; drain %.1f / none / %.1f", str, plain.meta.kmh, super.meta.kmh, r0.meta.drain or 0, rFrag.meta.drain or 0))
end

print("== luck tables ==")
do
	-- (the owner, 2026-10-21: "why do the lucky and basic odds say the same"): the usual weights at
	-- 3x luck stay the usual ones whatever was asked first, and a stray extra argument isn't a base
	local lucky3 = Spins.luckyAt(3)
	local basic3 = Spins.luckWeights(3, false)
	local basic3b = Spins.luckWeights(3)
	check(basic3 == basic3b and basic3 ~= lucky3 and math.abs(basic3.Mythic - Config.Rarity.Weights.Mythic * 3) < 1e-9 and math.abs(lucky3.Mythic - Config.Lucky.Weights.Mythic * 3) < 1e-9,
		"luck: the usual and the lucky weights never share a cache (a stray boolean isn't a base)",
		string.format("3x: usual Mythic %.3f%%, lucky Mythic %.2f%%", basic3.Mythic, lucky3.Mythic))
end

print("== Seora's Sharp Angle ==")
do
	-- (the owner, 2026-10-21: "a passive slightly increase spike angle on seora")
	local seora = Characters.derive(Characters.fromRoster(Roster.get("seora"), "max"))
	local r = apexRoot(seora, 3.5 * K)
	local b = ballAt(r, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local _, plain = spike(r, b, { stats = seora })
	local _, hers = spike(r, b, { stats = seora, ability = "Skyward", lift = -0.45 })
	local pP, pS = BallPhysics.buildPath(plain.launch), BallPhysics.buildPath(hers.launch)
	local function landAngle(path)
		local v = BallPhysics.velocityAt(path, path.landing.t - 0.001)
		return math.deg(math.atan(-v.Y / math.max(math.abs(v.Z), 1e-3)))
	end
	check(oppDepth(pS) < oppDepth(pP) and oppDepth(pS) > oppDepth(pP) * 0.7 and landAngle(pS) > landAngle(pP) and Court.inBounds(pS.landing.pos) and not pS.flags.netTouch,
		"Seora's Sharp Angle: her spike lands a little shorter, so a little steeper, and in",
		string.format("%.1f vs %.1f studs deep, %.0f vs %.0f degrees", oppDepth(pS), oppDepth(pP), landAngle(pS), landAngle(pP)))
end

print("== ranked score effects ==")
do
	-- (the owner, 2026-10-21: one a rank from Gold; "if you lose the rank, you lose the explosion")
	local Ranked = require("Ranked")
	local function count(t)
		local n = 0
		for _ in pairs(t) do n = n + 1 end
		return n
	end
	local silver, gold, dia3, mighty, almighty = Ranked.effectsFor(500, 1), Ranked.effectsFor(650, 1), Ranked.effectsFor(1450, 1), Ranked.effectsFor(1600, 1), Ranked.effectsFor(2500, 1)
	local onBanner = false
	for _, row in ipairs(Spins.table("Effect")) do
		onBanner = onBanner or (Spins.item("Effect", row.item.Key).Ranked ~= nil)
	end
	check(count(silver) == 0 and gold.RankGold and count(gold) == 1 and dia3.RankDiamond and dia3.RankPlatinum and not dia3.RankMighty and count(mighty) == 4 and count(almighty) == 5 and not onBanner,
		"ranked score effects: one a rank from Gold, earned at that rank or higher (kept for good: ProfileService), never on a banner",
		string.format("Silver %d, Gold %d, Diamond III %d, Mighty %d, Almighty %d", count(silver), count(gold), count(dia3), count(mighty), count(almighty)))
	-- (the owner, 2026-10-25: "make the effects for this season s1 bound")
	local s2 = Ranked.effectsFor(2500, 2)
	check(count(s2) == 0 and Spins.item("Effect", "RankGold").Season == 1, "ranked score effects: Season 1's can't be earned in Season 2, even at Almighty", string.format("Season 2 Almighty holds %d", count(s2)))
end

print("== ranked leavers ==")
do
	local Ranked = require("Ranked")
	local L = Config.Ranked.Leave
	local now = 1792594800
	-- (the owner, 2026-10-21: "add a leaver penalty", "it is removed if you rejoin though")
	local rec = Ranked.clean({ season = 1, rp = 1000, wins = 5, losses = 2, peak = 1000 }, 1)
	local plain = Ranked.change(false, 1000, 1000)
	local d1, ban1 = Ranked.leave(rec, 1000, now, "match-a", "code-a", nil)
	local afterOne = rec.rp
	local lockOne = Ranked.banLeft(rec, now)
	-- leaving again soon after: a longer lock; a day later the count starts over
	local _, ban2 = Ranked.leave(rec, 1000, now + 600, "match-b", nil, "job-b")
	local _, ban3 = Ranked.leave(rec, 1000, now + 1200, "match-c", nil, "job-c")
	local fresh = Ranked.clean({ season = 1, rp = 500, leaves = { now - L.Window - 10 } }, 1)
	local _, banLater = Ranked.leave(fresh, 500, now, "match-d", nil, "job-d")
	-- rejoining the match you left gives it all back (only that match, in its season)
	local r2 = Ranked.clean({ season = 1, rp = 1000, wins = 5, losses = 2, peak = 1000 }, 1)
	Ranked.leave(r2, 1000, now, "match-e", "code-e", nil)
	local wrong = Ranked.unleave(r2, "match-x")
	local saved = Ranked.clean(r2, 1) -- (it survives a save and a load)
	local right = Ranked.unleave(saved, "match-e")
	local again = Ranked.unleave(saved, "match-e")
	check(d1 == plain - L.ExtraRp and afterOne == 1000 + plain - L.ExtraRp and ban1 == L.Bans[1] and lockOne == L.Bans[1] and rec.losses == 5
		and ban2 == L.Bans[2] and ban3 == L.Bans[3] and banLater == L.Bans[1]
		and not wrong and right and not again and saved.rp == 1000 and saved.losses == 2 and Ranked.banLeft(saved, now) == 0 and saved.left == nil
		and Ranked.rejoinable(saved, now) == nil and Ranked.rejoinable(rec, now + 1200).key == "match-c" and Ranked.rejoinable(rec, now + 1200 + L.RejoinSeconds + 1) == nil,
		"leaving a ranked match: the loss, -15 RP more and a queue lock that grows with each leave in a day; rejoining that match gives it all back",
		string.format("left at Platinum: %d RP (a plain loss %d), locked %d s, then %d s, %d s", d1, plain, ban1, ban2, ban3))
end

print("== clans ==")
do
	-- the owner (2026-10-21): clans: 1,000 VP (or the pass) to make one, a unique 2-5 tag, a
	-- minimum of wins to join, members' stats counted from when they join into points the owner
	-- spends on upgrades (VP, Gold, luck, member cap...), tag colours bought with your own share
	local Clans = require("Clans")
	do
		-- this week's points: Monday to Monday, only what members earned since the last count
		local mon = Clans.weekEnds(Clans.week(os.time())) -- (a Monday's start)
		local wk = Clans.week(mon)
		local clan = { members = { ["7"] = { r = "Member", b = { wins = 0 }, s = { wins = 2 } } } }
		Clans.updateMember(clan, 7, { wins = 5, matches = 0 }, mon + 3600)
		local first = Clans.weekPoints(clan, mon + 3600)
		Clans.updateMember(clan, 7, { wins = 5, matches = 0 }, mon + 7200)
		local again = Clans.weekPoints(clan, mon + 7200)
		local nextWeek = Clans.weekPoints(clan, mon + 7 * 86400 + 60)
		check(wk == Clans.week(mon - 1) + 1 and Clans.week(mon + 6 * 86400) == wk and first == 3 * Config.Clans.Points.wins and again == first and nextWeek == 0,
			"clans: this week's points count only new points, and start over on Monday", string.format("%d this week", first))
	end
	do
		-- anyone viewing a clan sees its members (best first, a pending one left out) and its totals
		local clan = { tag = "ABC", name = "Alpha", up = { VP = 3, Emblem = 1, Cap = 99 }, members = {
			["1"] = { n = "Ann", r = "Owner", s = { wins = 2, kills = 5 } },
			["2"] = { n = "Bo", r = "Member", s = { wins = 6, kills = 1 } },
			["3"] = { n = "Cy", r = "Member", pending = true, s = { wins = 50 } },
		} }
		local card = Clans.card(clan)
		check(#card.members == 2 and card.members[1].name == "Bo" and card.totals.wins == 8 and card.totals.kills == 6 and card.members[1].stats.wins == 6,
			"clans: a clan's page lists its members, best first, with their stats, and the clan's totals", string.format("%d members, %d wins", #card.members, card.totals.wins))
		local capMax = Config.Clans.Upgrades[4].Max
		check(card.up.VP == 3 and card.up.Emblem == 1 and card.up.Gold == 0 and card.up.Cap == capMax,
			"clans: a clan's page shows its upgrades' levels (none bought is 0, a stored level past the top is the top)")
	end
	local CC = Config.Clans
	local t1, w1 = Clans.cleanTag(" ab1 ")
	local t2 = Clans.cleanTag("A")
	local t3 = Clans.cleanTag("TOOLONG")
	local t4 = Clans.cleanTag("a-b")
	local rec0 = { wins = 10, matches = 20, kills = 100, aces = 5, blocks = 7, mvps = 1 }
	local clan = Clans.new("AB1", "Spike Lords", "  we spike  ", true, 3, 111, "Owner1", rec0, 1000)
	local ok1 = Clans.canJoin(clan, 5)
	local ok2, why2 = Clans.canJoin(clan, 2)
	Clans.addMember(clan, 222, "Two", "Member", { wins = 50, matches = 80 }, 1001)
	-- the owner plays: 3 wins, 4 matches, 20 kills since joining
	Clans.updateMember(clan, 111, { wins = 13, matches = 24, kills = 120, aces = 5, blocks = 7, mvps = 1 })
	Clans.updateMember(clan, 222, { wins = 51, matches = 81 })
	local ownPts = Clans.pointsOf({ wins = 3, matches = 4, kills = 20 })
	local total, left = Clans.points(clan)
	local cost1 = Clans.cost(clan, "VP")
	clan.spent = cost1
	clan.up.VP = 1
	local _, left2 = Clans.points(clan)
	local vpMul = Clans.bonus(clan, "VP")
	local capBefore = Clans.cap(clan)
	clan.up.Cap = 2
	-- a member leaving keeps their points with the clan
	local before = Clans.points(clan)
	Clans.removeMember(clan, 222)
	local after = Clans.points(clan)
	local rich = Clans.tagText("AB1", "Fire")
	local plain = Clans.tagText("AB1", "Nope")
	local view = Clans.view(clan)
	check(t1 == "AB1" and w1 == nil and t2 == nil and t3 == nil and t4 == nil and clan.desc == "we spike" and ok1 and not ok2 and why2 ~= nil
		and ownPts == 3 * CC.Points.wins + 4 * CC.Points.matches + 20 * CC.Points.kills and total == ownPts + CC.Points.wins + CC.Points.matches and left == total
		and cost1 == Clans.upgrade("VP").Base and left2 == math.max(0, total - cost1) and math.abs(vpMul - 1.02) < 1e-9 and capBefore == CC.BaseCap and Clans.cap(clan) == CC.BaseCap + 10
		and before == after and Clans.count(clan) == 1 and select(2, string.gsub(rich, "<font", "")) == 5 and string.find(plain, "EBEBF0", 1, true) ~= nil
		and view.points == after and view.members[1].name == "Owner1" and Clans.cost(clan, "Emblem") == 1000 and Clans.canManage(clan, 111) and not Clans.canManage(clan, 222),
		"clans: a clean 2-5 tag, a wins minimum to join, members' stats since joining become points, upgrades spend them, a leaver's points stay, tag colours",
		string.format("owner %d pts, clan %d, VP upgrade %d, cap %d -> %d", ownPts, total, cost1, capBefore, Clans.cap(clan)))
	-- the clans' board cards: a top 3 clan's members, and the top clan's
	local Cards = require("Cards")
	local cs = Cards.stats({ record = {}, bestClanRank = { rank = 2, tag = "AB1" } }, 0)
	local v, lab = Cards.display(Cards.get("ClanTop3"), cs)
	check(Cards.met(Cards.get("ClanTop3"), cs) and not Cards.met(Cards.get("ClanNumber1"), cs) and v == "#2" and lab == "[AB1] TOP CLAN",
		"a top 3 clan's members get the Top 3 Clan card (the top clan's, Top Clan)", v .. " " .. lab)
	-- the clan's own: a tag can't be made twice (the store's key is the tag)
	clan.up.VP = 99
	check(Clans.level(clan, "VP") == Clans.upgrade("VP").Max and Clans.cost(clan, "VP") == nil, "an upgrade stops at its max")
end

print("== gifted game passes ==")
do
	-- the owner (2026-10-21): "Make all the gamepasses giftable": a gift product gives the pass (or
	-- the perk) inside the game
	local Economy = require("Economy")
	local vip = Economy.pack("PassGift", 1)
	local perk = Economy.pack("PassGift", 4)
	local g1, g2 = Economy.packGrant(vip), Economy.packGrant(perk)
	local prof = { owned = { Char = {} }, perks = {} }
	Economy.apply(prof, g1, 0)
	Economy.apply(prof, g2, 0)
	local junk = Economy.cleanGrant({ Passes = { "Nope", "VIP", "VIP" }, Perks = { "Nope" } })
	local allGiftable = true
	for _, key in ipairs(Config.Passes.Order) do
		local found = false
		for _, p in ipairs(Config.Passes.GiftPacks) do
			found = found or (p.Passes and p.Passes[1] == key) or false
		end
		allGiftable = allGiftable and found
	end
	for _, key in ipairs(Config.Perks.Order) do
		local found = false
		for _, p in ipairs(Config.Passes.GiftPacks) do
			found = found or (p.Perks and p.Perks[1] == key) or false
		end
		allGiftable = allGiftable and found
	end
	check(vip ~= nil and vip.id ~= 0 and prof.giftedPasses.VIP == true and prof.perks.ScoreSound == true and #junk.Passes == 1 and #junk.Perks == 0
		and not Economy.isEmpty(g1) and Economy.describe(g1) == "the VIP pass" and allGiftable and Economy.packByProduct(vip.id).kind == "PassGift",
		"every game pass and perk pass has a gift product; it gives the pass (or perk) in the game", Economy.describe(g1) .. " / " .. Economy.describe(g2))
end

print("== Gold trades ==")
do
	-- the owner (2026-10-21): "50 gold for 1 vp ... and make x2 vp purchasable with coins or vp"
	local Economy = require("Economy")
	local secs, gold = Economy.boostPrice(3, "Gold")
	local _, vp = Economy.boostPrice(1, "VP")
	local per, cp = Config.Exchange.GoldPerVP, Config.Boosts.CurrencyPacks
	check(Economy.exchangeCost(100) == 100 * per and Economy.exchangeCost(2500) == 2500 * per and Economy.exchangeCost(7) == nil and Economy.exchangeCost("x") == nil
		and secs == cp[3].BoostVP and gold == cp[3].Gold and vp == cp[1].VP and Economy.boostPrice(1, "Robux") == nil and Economy.boostPrice(9, "Gold") == nil,
		"V Points for Gold at Exchange.GoldPerVP each, in the Shop's amounts only; 2x VP for Gold or VP at its listed price",
		string.format("100 VP = %d Gold; 1 hr of 2x VP = %d Gold", Economy.exchangeCost(100), gold))
end

print("== the admin panel gives skins ==")
do
	-- the owner (2026-10-17): "add giving skins in the admin panel": a gift's Skins (Halloween skin
	-- keys, junk and repeats dropped) give a copy each and bring the skin's character
	local Economy = require("Economy")
	local g = Economy.cleanGrant({ Skins = { "Reaper", "Nope", "Reaper", 5, "FallenAngel" } })
	local prof = { owned = { Char = {} } }
	local added = Economy.apply(prof, g, 1000)
	local joined = {}
	for _, id in ipairs(added) do
		joined[id] = true
	end
	local text = Economy.describe(g)
	check(#g.Skins == 2 and not Economy.isEmpty(Economy.cleanGrant({ Skins = { "Reaper" } })) and Economy.isEmpty(Economy.cleanGrant({ Skins = { "Nope" } }))
		and prof.skins.Reaper.copies == 1 and prof.skins.FallenAngel.copies == 1 and prof.owned.Char.taeha and prof.owned.Char.yejun and joined.taeha and joined.yejun
		and string.find(text, "the Reaper skin", 1, true) ~= nil,
		"the admin panel gives Halloween skins: a copy each, with their characters", text)
end

print("== luck on lucky spins ==")
do
	-- the owner (2026-10-17): the luck boosts on lucky spins too, "like the luck boosts": a lucky
	-- spin at N times the luck has Epic and up N times as likely, the rarest first, out of the Rares
	local L = Spins.LuckyWeights
	local two = Spins.luckyAt(2)
	local three = Spins.luckyAt(3)
	local function sum(w)
		local t = 0
		for _, r in ipairs(Config.Rarity.Order) do
			t = t + (w[r] or 0)
		end
		return t
	end
	-- a lucky pity-free roll at 3x: S+ about 1.5%
	local rng = Random.new(11)
	local n, top = 20000, 0
	for _ = 1, n do
		local item = Spins.item("Char", Spins.rollItem("Char", rng, three))
		if item.Rarity == "Mythic" then
			top = top + 1
		end
	end
	local pity = { normal = 0, lucky = 0, top = 0 }
	local k = Spins.pityRoll(pity, Random.new(3), true, nil, three)
	check(Spins.luckyAt(1) == L and math.abs(two.Mythic - 2 * L.Mythic) < 1e-9 and math.abs(two.Legendary - 2 * L.Legendary) < 1e-9 and (two.Common or 0) == 0
		and math.abs(sum(two) - 100) < 1e-9 and math.abs(sum(three) - 100) < 1e-9 and two.Rare < L.Rare and Spins.luckWeights(2) ~= two
		and math.abs(top / n - three.Mythic / 100) < 0.004 and k ~= nil and (pity.lucky == 1 or Spins.item("Char", k).Rarity == "Mythic"),
		"luck boosts lucky spins too: Epic and up N times as likely, out of the Rares (the usual recruits' 2x untouched)",
		string.format("2x: Rare %.2f, Epic %.2f, Legendary %.2f, S+ %.2f; 3x S+ %.2f%% (%d in %d)", two.Rare, two.Epic, two.Legendary, two.Mythic, three.Mythic, top, n))
end

print("== 4x, 6x, 8x and 16x luck ==")
do
	-- the owner (2026-10-16): "Add 4x 6x 8x and 16x luck to admin panel and to the shop": N times the
	-- luck makes an S+ 0.5% x N (16x: 8%), the rarest first, the weights still adding up to 100
	local Economy = require("Economy")
	local base = Spins.odds("Char")
	local ok, lines = true, {}
	for _, m in ipairs(Config.Boosts.LuckTiers) do
		local w = Spins.luckWeights(m)
		local o = Spins.odds("Char", w)
		local total = 0
		for _, r in ipairs(Config.Rarity.Order) do
			total = total + (w[r] or 0)
		end
		ok = ok and math.abs(total - 100) < 1e-9 and math.abs(o.Mythic - m * base.Mythic) < 1e-9 and o.Common <= base.Common
		table.insert(lines, string.format("%dx S+ %.1f%%", m, o.Mythic * 100))
	end
	local sixteen = Spins.odds("Char", Spins.luckWeights(16))
	-- packs for every tier, and your luck is your strongest boost running
	local prof = { boosts = {} }
	Economy.apply(prof, Economy.packGrant(Economy.pack("LuckBoost4", 1)), 1000)
	Economy.apply(prof, Economy.packGrant(Economy.pack("LuckBoost", 4)), 1000)
	Economy.apply(prof, Economy.packGrant(Economy.pack("LuckBoost16", 1)), 1000)
	local m1 = Economy.luckBoost(prof, 1000 + 60)
	local m2 = Economy.luckBoost(prof, 1000 + 20 * 60)
	local m3 = Economy.luckBoost(prof, 1000 + 2 * 3600)
	local m4 = Economy.luckBoost(prof, 1000 + 4 * 3600)
	local packsOk = #Config.Boosts.LuckPacks4 == 4 and #Config.Boosts.LuckPacks6 == 4 and #Config.Boosts.LuckPacks8 == 4 and #Config.Boosts.LuckPacks16 == 4
		and Economy.describe(Economy.packGrant(Economy.pack("LuckBoost8", 3))) == "8x Luck for 1 hour" and Economy.cleanGrant({ BoostLuck = 60, LuckMul = 5 }).LuckMul == 2
	check(ok and sixteen.Common < base.Common and packsOk and m1 == 16 and m2 == 2 and m3 == 2 and m4 == 1 and prof.boosts.Luck4 == 1000 + 15 * 60,
		"4x to 16x Luck: an S+ is its base chance x N, the rarest first, out of the Commons; your luck is your strongest boost running",
		table.concat(lines, ", "))
end

print("== Zero Point (Taeho: the ball slightly in front, above his head: ???, nearly straight, through the block) ==")
do
	local th = Characters.derive(Characters.fromRoster(Roster.get("taeha"), "max"))
	local yj = Characters.derive(Characters.fromRoster(Roster.get("yejun"), "max"))
	local root = apexRoot(th, 3.5 * K)
	local ok, res = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = th, ability = "ZeroPoint" })
	local path = ok and BallPhysics.buildPath(res.launch)
	local yr = apexRoot(yj, 3.5 * K)
	local _, double = spike(yr, ballAt(yr, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = yj, ability = "Thunder" }, { second = true })
	check(ok and res.meta.zero and res.meta.grade == "PERFECT" and res.meta.breakAtk == 999 and res.meta.kmh >= 225 and res.meta.kmh <= 250 and res.meta.kmh >= double.meta.kmh - 5
		and not path.flags.netTouch and path.landing.pos.Z * side < 0 and Court.inBounds(path.landing.pos),
		"the ball in his sweet spot makes a Zero Point: about YeJun's double swing or more, and it lands in", string.format("%.1f km/h (YeJun's double swing %.1f), %s", ok and res.meta.kmh or 0, double.meta.kmh, ok and describe(path) or "-"))
	-- his jump serve too: a little slower, from behind the end line, and it lands in
	local sroot = vec(0, GROUND + Characters.jumpHeight(th, GROUND) + Characters.hangGain(), side * (C.SideDepth + 1))
	local okS, serve = HitLogic.compute({ action = "Serve", t = 0, root = sroot, ball = ballAt(sroot, Z.SpikeCenterDz, Z.SpikeCenterDy), vy = 0, grounded = false }, ctx({ stats = th, ability = "ZeroPoint", touchNumber = 1 }))
	local sPath = okS and BallPhysics.buildPath(serve.launch)
	check(okS and serve.meta.hitType == "JumpServe" and serve.meta.zero and serve.meta.kmh >= 200 and serve.meta.kmh < res.meta.kmh and not sPath.flags.netTouch and sPath.landing.pos.Z * side < 0 and Court.inBounds(sPath.landing.pos),
		"his jump serve can be a Zero Point too, a little slower, and it lands in", string.format("%.1f km/h, %s", okS and serve.meta.kmh or 0, okS and describe(sPath) or "-"))
	-- the freeze frame: the ball holds on his hand for the cut-in; and his hitbox is bigger
	local edge = ballAt(root, Z.SpikeCenterDz + Z.SpikeRadiusZ * th.Reach * 1.1, Z.SpikeCenterDy)
	local okWide = spike(root, edge, { stats = th, ability = "ZeroPoint" })
	local okNarrow = spike(root, edge, { stats = th })
	check(res.launch.hold == Config.Abilities.ZeroPoint.Freeze and okWide and not okNarrow,
		"a Zero Point freezes on the hand for the cut-in, and his spike hitbox is bigger", string.format("hold %.2f s", res.launch.hold))
	-- lenient: no PERFECT grade and no exact jump timing needed, just the ball in front and up
	local lowRoot = root - vec(0, 3.2, 0) -- on the way up, the ball well over his hand and ahead
	local okF, fair = spike(lowRoot, ballAt(lowRoot, 1.6, 1.8), { stats = th, ability = "ZeroPoint" })
	check(okF and fair.meta.zero and fair.meta.quality < H.PerfectAt and fair.meta.kmh >= 225,
		"a so-so contact with the ball in front and up is a Zero Point too", string.format("quality %.2f, %.1f km/h", okF and fair.meta.quality or 0, okF and fair.meta.kmh or 0))
	local okB, behind = spike(root, ballAt(root, -0.6, 0.4), { stats = th, ability = "ZeroPoint" })
	local okL, low = spike(root, ballAt(root, 0.8, -2.0), { stats = th, ability = "ZeroPoint" })
	local _, plain = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = th })
	check(okB and okL and not behind.meta.zero and not low.meta.zero and low.meta.kmh < 145 and not plain.meta.zero and plain.meta.kmh < 145,
		"behind his head or low it is his usual spike (and nobody else gets a Zero Point)", string.format("%.1f km/h low, %.1f without the ability", okL and low.meta.kmh or 0, plain.meta.kmh))
	check(res.meta.tierDrain > plain.meta.tierDrain and res.launch.a.Magnitude < plain.launch.a.Magnitude * 0.5,
		"a Zero Point flies nearly straight and costs the digger more stamina", string.format("gravity %.0f vs %.0f", res.launch.a.Magnitude, plain.launch.a.Magnitude))
end

print("== Skyward (Seora: her jump climbs with her spikes; Talon Drop) ==")
do
	local SKYW = Config.Abilities.Skyward
	local se = Characters.derive(Characters.fromRoster(Roster.get("seora"), "max"))
	local yj = Characters.derive(Characters.fromRoster(Roster.get("yejun"), "max"))
	local stam = { value = 120, max = 120 }
	local low = HitLogic.effectiveStats(se, "Skyward", stam, {})
	local top = HitLogic.effectiveStats(se, "Skyward", stam, { lift = 99 })
	check(low.ContactMaxM > 3.75 and low.ContactMaxM < 3.95 and top.ContactMaxM > 4.7 and top.ContactMaxM < 4.8 and top.ContactMaxM > yj.ContactMaxM + 0.3,
		"she starts a set low and climbs past YeJun to about 4.75 m", string.format("%.2f m to %.2f m (YeJun %.2f m)", low.ContactMaxM, top.ContactMaxM, yj.ContactMaxM))
	local root = apexRoot(low, 3.5 * K)
	local ok, res = spike(root, ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = se, ability = "Skyward" })
	local lowRoot = root - vec(0, 3.2, 0)
	local ok2, res2 = spike(lowRoot, ballAt(lowRoot, 1.0, 0.4), { stats = se, ability = "Skyward" })
	check(ok and ok2 and math.abs(res.meta.liftGain - SKYW.Gain) < 0.02 and res2.meta.liftGain < res.meta.liftGain * 0.6 and math.abs(res.meta.height - low.ContactMaxM) < 0.05,
		"a spike at the top of her jump raises it most, a low one little", string.format("+%.3f m at %.2f m, +%.3f m low", ok and res.meta.liftGain or 0, ok and res.meta.height or 0, ok2 and res2.meta.liftGain or 0))
	-- Talon Drop: right at the net nearly straight down; further back flatter, still over the net
	local function talonFrom(ballFromNet)
		local r = apexRoot(top, Z.SpikeForward + Z.SpikeCenterDz + ballFromNet)
		local okT, resT = HitLogic.compute({ action = "Feint", t = 0, root = r, ball = ballAt(r, Z.SpikeCenterDz, Z.SpikeCenterDy), vy = 0, grounded = false }, ctx({ stats = se, ability = "Skyward", lift = 99 }))
		return okT, resT, okT and BallPhysics.buildPath(resT.launch)
	end
	local okN, near, pN = talonFrom(0.25 * SPM)
	local okF, far, pF = talonFrom(2.4 * SPM)
	check(okN and near.meta.talon and near.meta.hitType == "Spike" and near.meta.talonAngle >= 75 and not pN.flags.netTouch and pN.landing.pos.Z * side < 0 and -pN.landing.pos.Z * side < 1.6 * SPM,
		"Talon Drop at the net goes nearly straight down just past the tape", string.format("%d deg, %.1f km/h, %s", okN and near.meta.talonAngle or 0, okN and near.meta.kmh or 0, okN and describe(pN) or "-"))
	check(okF and far.meta.talonAngle < near.meta.talonAngle - 15 and not pF.flags.netTouch and pF.landing.pos.Z * side < 0,
		"further back it's flatter, still over the net onto their side", string.format("%d deg, %s", okF and far.meta.talonAngle or 0, okF and describe(pF) or "-"))
	check(low.Attack == se.Attack and top.Attack == se.Attack + SKYW.AttackAtMax,
		"her Attack climbs with her jump", string.format("%d to %d", low.Attack, top.Attack))
	-- her breakthroughs raise her highest lift (not her Attack)
	check(HitLogic.skyMax(5) > SKYW.MaxLift + 0.2 and HitLogic.skyLift(99, 5) == HitLogic.skyMax(5) and HitLogic.skyLift(99, 0) == SKYW.MaxLift,
		"Skyward: a +5 breakthrough lifts her highest hitting point (her Attack at the top stays)", string.format("%.2f m -> %.2f m", SKYW.MaxLift, HitLogic.skyMax(5)))
end

print("== Dante reaches further off a leap ==")
do
	local dn = Characters.derive(Characters.fromRoster(Roster.get("dante"), "max"))
	local r = apexRoot(dn, 3.5 * K)
	local edge = ballAt(r, Z.SpikeCenterDz + Z.SpikeRadiusZ * dn.Reach * 1.3, Z.SpikeCenterDy)
	local okLeap = spike(r, edge, { stats = dn, ability = "Feral" }, { gauge = 1 })
	local okPlain = spike(r, edge, { stats = dn, ability = "Feral" }, { gauge = 0 })
	check(okLeap and not okPlain and Config.Abilities.Feral.Passives ~= nil,
		"off a charged leap his swing reaches further (a passive)", string.format("x%.2f, x%.2f without a leap", Config.Abilities.Feral.LeapReachMul, Config.Abilities.Feral.ReachMul))
end

print("== a losing streak brings stamina back faster ==")
do
	local a, b, c, d = HitLogic.lossRecovery(1), HitLogic.lossRecovery(2), HitLogic.lossRecovery(3), HitLogic.lossRecovery(6)
	check(a == Config.Stamina.RecoverLoser and b > a * 1.3 and c > b * 1.3 and d == 1,
		"each point lost in a row gives more of the bar back, up to all of it", string.format("%.2f, %.2f, %.2f ... %.2f", a, b, c, d))
end

print("== abilities on jump serves ==")
do
	-- (the owner: "allow everyones abilities to work on serves")
	local S = Characters.derive(Characters.fromRoster(Roster.get("yeonho"), "max"))
	local root = vec(0, GROUND + Characters.jumpHeight(S, GROUND) + Characters.hangGain(), side * (C.SideDepth + 1))
	local function serve(ability, extra)
		local c = ctx({ stats = S, ability = ability, touchNumber = 1 })
		for k, v in pairs(extra or {}) do c[k] = v end
		local ok, res = HitLogic.compute({ action = "Serve", t = 0, root = root, ball = ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy), vy = 0, grounded = false }, c)
		return ok and res, ok and BallPhysics.buildPath(res.launch)
	end
	local plain = serve(nil)
	local pl, plPath = serve("Plunge")
	local co = serve("Counter", { counter = 100 })
	local sk = serve("Skyward")
	check(pl and pl.meta.plunge and plPath.landing.pos.Z * side < 0 and Court.inBounds(plPath.landing.pos) and co and co.meta.counterRelease == 100 and co.meta.kmh > plain.meta.kmh * 1.3 and sk and (sk.meta.liftGain or 0) > 0,
		"Plunge Spin, Counter Edge's release and Skyward's climb work on jump serves", string.format("plunge %s, counter %.0f vs %.0f km/h", pl and describe(plPath) or "-", co and co.meta.kmh or 0, plain.meta.kmh))
	-- Zero Point's ball meets his hand (it isn't left hanging above his swing)
	local th = Characters.derive(Characters.fromRoster(Roster.get("taeha"), "max"))
	local r = apexRoot(th, 3.5 * K)
	local high = ballAt(r, 0.8, 2.6 * th.Reach)
	local okZ, z = spike(r, high, { stats = th, ability = "ZeroPoint" })
	local hand = vec(0, r.Y + Z.SpikeUp, r.Z - side * Z.SpikeForward)
	check(okZ and z.meta.zero and (z.launch.p - hand).Magnitude < 1.2,
		"a Zero Point met high in the spot leaves from his hand", string.format("%.2f studs from the hand (the ball was %.2f)", okZ and (z.launch.p - hand).Magnitude or -1, (high - hand).Magnitude))
end

print("== bundles and game passes ==")
do
	local Economy = require("Economy")
	-- the Starter Pack: one product, several things, sold once
	local starter = Economy.pack("Bundle", 1)
	local g = Economy.packGrant(starter)
	local prof = { vp = 0, gold = 0, lucky = 0, boosts = {} }
	Economy.apply(prof, g, 1000)
	local byId = Config.Bundles.Packs[2].Id ~= 0 and Economy.packByProduct(Config.Bundles.Packs[2].Id) or Economy.pack("Bundle", 2)
	check(starter and starter.pack.Once and prof.vp == starter.pack.VP and prof.gold == starter.pack.Gold and prof.lucky == starter.pack.Lucky and Economy.boost(prof, "Luck", 1000 + 60) == 2
		and not Economy.boughtOnce(starter, {}) and Economy.boughtOnce(starter, { [starter.pack.Name] = true })
		and byId and byId.kind == "Bundle" and not Economy.boughtOnce(byId, { [byId.pack.Name] = true }),
		"a bundle gives everything in it; the Starter Pack counts as bought once it is, the Pro Bundle never does", Economy.describe(g))
	-- the passes multiply each other: VIP 1.5x and 2x V Points make 3x; Lucky 1.5x luck on top of 2x Luck is 3x
	local all = { VIP = true, DoubleVP = true, Lucky = true }
	local three = Spins.odds("Char", Spins.luckWeights(2 * Economy.passMult(all, "Luck")))
	local base = Spins.odds("Char")
	check(Economy.passMult({}, "VP") == 1 and Economy.passMult(nil, "Gold") == 1 and Economy.passMult({ VIP = true }, "Gold") == 1.5
		and Economy.passMult(all, "VP") == 3 and Economy.passMult(all, "Gold") == 1.5 and Economy.passMult(all, "Luck") == 1.5
		and math.abs(three.Mythic - 3 * base.Mythic) < 1e-9 and math.abs(Spins.odds("Char", Spins.luckWeights(1.5)).Mythic - 1.5 * base.Mythic) < 1e-9,
		"game passes multiply what matches pay and the Characters banner's luck, and stack", string.format("Mythic %.2f%% at 3x", three.Mythic * 100))
end

print("== one swing a jump ==")
do
	local yj = Characters.derive(Characters.fromRoster(Roster.get("yejun"), "max"))
	local r = apexRoot(yj, 3.5 * K)
	local b = ballAt(r, 0.9, 0)
	local _, first = spike(r, b, { stats = yj, ability = "Thunder" })
	local _, second = spike(r, b, { stats = yj, ability = "Thunder" }, { second = true })
	local _, other = spike(r, b, { stats = yj, ability = "Azure" }, { second = true })
	local _, plain = spike(r, b, { stats = yj, ability = "Azure" })
	local ratio = second.meta.kmh / first.meta.kmh
	check(second.meta.secondSwing and not first.meta.secondSwing and math.abs(ratio - (1 + Config.Abilities.Thunder.SecondBoost)) < 0.01 and not other.meta.secondSwing and math.abs(other.meta.kmh - plain.meta.kmh) < 1e-6 and Config.Abilities.Thunder.Passives[1].Name == "Double Swing",
		"YeJun's Double Swing: his second swing in a jump hits harder; nobody else's does", string.format("%.0f -> %.0f km/h", first.meta.kmh, second.meta.kmh))
end

print("== stacked abilities ==")
do
	-- the owner (2026-10-15): "it seems the cards take away the abilities. i want them to stack."
	-- ctx.ability stays the character's own (the only one its breakthroughs grow); ctx.abilities is
	-- the set of every ability it plays, the Halloween Match's ability cards included
	local Halloween = require("Halloween")
	local BTm = require("Breakthrough")
	local A = Config.Abilities
	local function set(primary, cards)
		return Characters.abilitySet(Characters.abilityList(primary, cards))
	end
	-- the list: its own first, then the cards in hand order, known ones only, none twice
	local list = Characters.abilityList("Thunder", { "Azure", "Thunder", "nope", "Azure", "Feral" })
	local parsed = Characters.parseAbilities(Characters.encodeAbilities(list))
	check(table.concat(list, ",") == "Thunder,Azure,Feral" and table.concat(parsed, ",") == "Thunder,Azure,Feral" and table.concat(Characters.abilityList(nil, { "Squall" }), ",") == "Squall"
		and #Characters.abilityList(nil, nil) == 0 and Characters.abilitySet(list).Feral and not Characters.abilitySet(list).nope,
		"a character's abilities: its own first, then each card's in hand order, once each; the attribute reads back the same", table.concat(list, ","))
	-- who owns a press two abilities claim: the first of them in that order
	local own = HitLogic.inputOwner
	check(own({ "Azure", "Squall" }, "AirSpike") == "Azure" and own({ "Squall", "Azure" }, "AirSpike") == "Squall" and own({ "Thunder", "Feral", "Squall" }, "GroundJump") == "Feral"
		and own({ "Squall", "Feral" }, "GroundJump") == "Squall" and own({ "Thunder", "Corona" }, "AirSpike") == nil,
		"a press two of them claim (hold Spike in the air, hold Jump on the ground) goes to the first in the character's order")

	-- YeJun (Thunder) with an Azure card: a thunder spike over 4.00 m that his energy multiplies,
	-- Azure at +0 while his own Thunder grows with his breakthroughs
	local yj = Characters.derive(Characters.fromRoster(Roster.get("yejun"), "max"))
	local r = apexRoot(yj, 3.5 * K)
	local b = ballAt(r, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local ta = set("Thunder", { "Azure" })
	local _, th = spike(r, b, { stats = yj, ability = "Thunder" })
	local _, st = spike(r, b, { stats = yj, ability = "Thunder", abilities = ta }, { energy = 1 })
	local _, th0 = spike(r, b, { stats = yj, ability = "Thunder" }, { second = true })
	local _, th5 = spike(r, b, { stats = yj, ability = "Thunder", breakLevel = 5 }, { second = true })
	local _, st5 = spike(r, b, { stats = yj, ability = "Thunder", abilities = ta, breakLevel = 5 }, { energy = 1, second = true })
	local lc = { ability = "Thunder", abilities = ta, breakLevel = 5 }
	check(st.meta.thunder and st.meta.pierce and st.meta.height >= 4.0 and math.abs(st.meta.kmh / HitLogic.softCap(th.meta.kmh * (1 + A.Azure.MaxBoost)) - 1) < 0.01
		and math.abs(st5.meta.kmh / HitLogic.softCap(th5.meta.kmh * (1 + A.Azure.MaxBoost)) - 1) < 0.01 and th5.meta.kmh > th0.meta.kmh * 1.04
		and HitLogic.levelOf(lc, "Thunder") == 5 and HitLogic.levelOf(lc, "Azure") == 0 and HitLogic.has(lc, "Azure") and not HitLogic.has(lc, "Feral"),
		"a Thunder Spiker with an Azure card: a thunder spike his energy multiplies; his breakthroughs grow his own ability, not the card's",
		string.format("%.0f -> %.0f km/h at %.2f m (at +5: %.0f -> %.0f)", th.meta.kmh, st.meta.kmh, st.meta.height, th5.meta.kmh, st5.meta.kmh))
	-- stats: every ability's points add up (an Adrenaline card at +0 on a +5 Counter Edge)
	local ines = Characters.derive(Characters.fromRoster(Roster.get("ines"), "max"))
	local low = { value = 10, max = 100 }
	local alone = HitLogic.effectiveStats(ines, "Counter", low, { counter = 100, breakLevel = 5 })
	local both = HitLogic.effectiveStats(ines, "Counter", low, { counter = 100, breakLevel = 5, abilities = set("Counter", { "Adrenaline" }) })
	check(both.Attack - alone.Attack == A.Adrenaline.AttackBonus and both.Jump - alone.Jump == A.Adrenaline.JumpBonus and alone.Attack > ines.Attack,
		"stat boosts add up: Counter Edge's meter and an Adrenaline card's points (the card at +0)", string.format("Attack %d -> %d -> %d", ines.Attack, alone.Attack, both.Attack))
	-- Rally Cry multiplies on top of Monster Mash (it used to take its place)
	local mash = Halloween.effects("MonsterMash")
	local rallied = HitLogic.effectiveStats(SP, nil, nil, { hex = mash, teamBoost = true })
	check(rallied.Speed == math.floor(SP.Speed * (mash.mul * (1 + A.RallyCry.Boost)) + 0.5) and rallied.Speed > math.floor(SP.Speed * (1 + A.RallyCry.Boost) + 0.5),
		"Rally Cry and Monster Mash multiply", string.format("Speed %d -> %d", SP.Speed, rallied.Speed))

	-- reach, the toss and the jump: the largest of them, never the product
	local reachAll = HitLogic.spikeReachAll
	check(reachAll({ Feral = true, Ironclad = true }, 1, 1) == math.max(A.Feral.LeapReachMul, A.Ironclad.SpikeReach + A.Ironclad.ReachMul) and reachAll({ Feral = true, Ironclad = true }, 1, 0) == A.Feral.LeapReachMul
		and reachAll({ Feral = true, Squall = true }, 0, 0) == math.max(A.Feral.ReachMul, A.Squall.ReachMul) and reachAll("Squall") == A.Squall.ReachMul and reachAll({}) == 1
		and HitLogic.tossReach({ Feral = true, Corona = true }) == math.max(A.Feral.TossReachMul, A.Corona.TossReachMul) and HitLogic.tossReach({ Thunder = true }) == 1
		and HitLogic.leapMul({ Thunder = true, Squall = true }) == A.Squall.LeapMul and HitLogic.leapMul({ Thunder = true, Corona = true }, true) == A.Corona.LeapMul
		and HitLogic.leapMul({ Thunder = true, Corona = true }, false) == A.Thunder.LeapMul and HitLogic.leapMul("Feral") == 1,
		"spike reach, the serve toss and the jump take the largest of the abilities', not the product",
		string.format("reach x%.2f, toss x%.2f, jump x%.2f", reachAll({ Feral = true, Ironclad = true }, 1, 1), HitLogic.tossReach({ Feral = true, Corona = true }), HitLogic.leapMul({ Thunder = true, Squall = true, Corona = true }, true)))
	local dn = Characters.derive(Characters.fromRoster(Roster.get("dante"), "max"))
	local dr = apexRoot(dn, 6 * K)
	local edge = ballAt(dr, Z.SpikeCenterDz + Z.SpikeRadiusZ * dn.Reach * 1.45, Z.SpikeCenterDy)
	local fi = { stats = dn, ability = "Feral", abilities = set("Feral", { "Ironclad" }), awakened = true }
	local okForge = spike(dr, edge, fi, { gauge = 1, metal = 1, early = true })
	local okLeap = spike(dr, edge, fi, { gauge = 1, metal = 0 })
	check(okForge and not okLeap, "Dante with an Ironclad card reaches as far as the wider of the two (his leap, or Forge's charge), not both together")

	-- Zero Point is the base: a Thunder card's Storm Call and an Azure card's energy multiply it, and a
	-- Feral card's leap leaves his 999 through the block
	local tz = Characters.derive(Characters.fromRoster(Roster.get("taeha"), "max"))
	local zr = apexRoot(tz, 3.5 * K)
	local zb = ballAt(zr, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local _, zero = spike(zr, zb, { stats = tz, ability = "ZeroPoint" })
	local _, storm = spike(zr, zb, { stats = tz, ability = "ZeroPoint", abilities = set("ZeroPoint", { "Thunder" }), stormOn = true })
	local _, charged = spike(zr, zb, { stats = tz, ability = "ZeroPoint", abilities = set("ZeroPoint", { "Azure" }) }, { energy = 0.5 })
	local _, leap = spike(zr, zb, { stats = tz, ability = "ZeroPoint", abilities = set("ZeroPoint", { "Feral" }) }, { gauge = 1, toward = true })
	check(zero.meta.zero and storm.meta.zero and storm.meta.storm and math.abs(storm.meta.kmh / HitLogic.softCap(zero.meta.kmh * (1 + A.Thunder.StormBoost)) - 1) < 0.01
		and charged.meta.zero and math.abs(charged.meta.kmh / HitLogic.softCap(zero.meta.kmh * (1 + A.Azure.MaxBoost * 0.5 ^ 1.2)) - 1) < 0.01
		and leap.meta.zero and leap.meta.fullLeap and leap.meta.breakAtk == 999 and storm.launch.hold == A.ZeroPoint.Freeze,
		"Zero Point keeps Storm Call's and the energy's boosts on top, and a full leap keeps his through-any-block",
		string.format("%.0f, with Storm Call %.0f, half a bar %.0f km/h", zero.meta.kmh, storm.meta.kmh, charged.meta.kmh))

	-- one path a spike: an overcharge flies out, then a Zero Point's laser, then a hover's aimed spot,
	-- then Plunge Spin; a plunge keeps a first strike's freeze
	local function plunging(primary, card, input, extra)
		local c = { stats = primary == "ZeroPoint" and tz or yj, ability = primary, abilities = set(primary, { card }) }
		for k, v in pairs(extra or {}) do c[k] = v end
		local root = primary == "ZeroPoint" and zr or r
		local ok, res = spike(root, primary == "ZeroPoint" and zb or b, c, input)
		return ok and res, ok and BallPhysics.buildPath(res.launch)
	end
	local over, overPath = plunging("Plunge", "Azure", { energy = 1.3 })
	local zp = plunging("ZeroPoint", "Plunge")
	local aimed = plunging("Plunge", "Squall", { gale = 0.5 })
	local spun = plunging("Plunge", "Squall")
	local first = plunging("Plunge", "Feral", { gauge = 1 }, { firstStrike = true })
	check(over and over.meta.overcharge and not over.meta.plunge and not over.launch.dive and not Court.inBounds(overPath.landing.pos)
		and zp and zp.meta.zero and not zp.meta.plunge and not zp.launch.dive and aimed and aimed.meta.aimed and not aimed.meta.plunge
		and spun and spun.meta.plunge and spun.launch.dive and first and first.meta.plunge and first.meta.firstStrike and first.launch.hold == A.Feral.FirstFreeze,
		"one path a spike: overcharge (out) over a Zero Point's laser over a hover's aim over Plunge Spin; a plunging first strike still freezes",
		over and describe(overPath) or "-")

	-- Iron Wall up beats his own Bulwark: a 220 km/h clean spike is shut down every time and no
	-- shield cracks; Bulwark alone shuts it down too, and its stop cracks one
	local taesan = Characters.derive(Characters.fromRoster(Roster.get("taesan"), "max"))
	local broot = vec(0, GROUND + Characters.jumpHeight(taesan, GROUND) * 0.8, side * 1.2)
	local palms = vec(0, broot.Y + Z.BlockReachUp + Config.Ball.Radius - 1.5, side * 0.6)
	local function block(seq, wallUp)
		local c = ctx({ ability = "Ironclad", abilities = set("Ironclad", { "IronWall" }), stats = taesan, ironclad = true, ironWall = wallUp or nil, seq = seq,
			lastHit = { hitType = "Spike", team = "Home", kmh = 220, quality = 0.9 }, ballVel = vec(0, -8, side * 30) })
		return HitLogic.compute({ action = "Block", t = 0, root = broot, ball = palms, vy = 0, grounded = false }, c)
	end
	local held, kept, cracked = 0, true, 0
	for seq = 1, 120 do
		local okW, w = block(seq, true)
		if okW and w.meta.outcome == "Stuff" and w.meta.perfectBlock and not w.meta.bulwark then
			held = held + 1
			local lives, cracks = HitLogic.ironAfterBlock(3, 1, w.meta)
			kept = kept and lives == 3 and cracks == 1
		end
		local okB, bw = block(seq, false)
		if okB and bw.meta.outcome == "Stuff" and bw.meta.ironWall and bw.meta.bulwark then
			local lives, cracks = HitLogic.ironAfterBlock(3, 0, bw.meta)
			cracked = cracked + ((lives == 3 and cracks == 1) and 1 or 0)
		end
	end
	check(held == 120 and kept and cracked == 120,
		"Iron Wall up with Ironclad's shields: a 220 km/h spike is shut down every time and cracks nothing; Bulwark alone shuts it down and its stop cracks a shield",
		string.format("held %d of 120; Bulwark alone cracked %d", held, cracked))

	-- the sets: Featherfall's own +5 grows her float's boost, not a Chain Reaction card's explosion
	local arin = Characters.derive(Characters.fromRoster(Roster.get("arin"), "max"))
	local sroot = vec(0, GROUND, side * 2.0 * SPM)
	local sball = vec(0, GROUND + Z.SetIdealY, side * 2.0 * SPM)
	local okS, sres = HitLogic.compute({ action = "Set", t = 0, root = sroot, ball = sball, vy = 0, grounded = true, setType = "Open" },
		ctx({ ability = "Featherfall", abilities = set("Featherfall", { "ChainReaction", "Vector" }), stats = arin, touchNumber = 2, seq = 5, breakLevel = 5 }))
	local sm = okS and sres.meta or {}
	local function copy(t, changes)
		local out = { team = "Away" }
		for k, v in pairs(t) do out[k] = v end
		for k, v in pairs(changes) do out[k] = v end
		return out
	end
	local sr = apexRoot(SP, 3.5 * K)
	local function spikeOff(last)
		local _, res = spike(sr, ballAt(sr, Z.SpikeCenterDz, Z.SpikeCenterDy), { lastHit = last }, { t = (sm.featherTop or 0) + A.Featherfall.FullFall + 1 })
		return res.meta.kmh
	end
	local kChain = spikeOff(copy(sm, {}))
	local kFloat = spikeOff(copy(sm, { charged = false }))
	local kPlain = spikeOff(copy(sm, { charged = false, setBreak = false }))
	check(okS and sm.setBreakFor == "Featherfall" and sm.charged and sm.featherSet and sm.vectorSet
		and math.abs(kChain / HitLogic.softCap(kFloat * A.ChainReaction.PowerMul[1]) - 1) < 0.01 and math.abs(kFloat / kPlain - (1 + BTm.ab("Featherfall", "MaxBoost", 5)) / (1 + A.Featherfall.MaxBoost)) < 0.01,
		"a +5 Featherfall setter with Chain Reaction and Vector cards: one set carries all three; her float's boost grows, the card's explosion doesn't",
		string.format("%.0f plain, %.0f off the float, %.0f exploding", kPlain, kFloat, kChain))

	-- the feint: Skyward's Talon Drop first (at plain power: no lightning) whichever slot holds it
	local se = Characters.derive(Characters.fromRoster(Roster.get("seora"), "max"))
	local top = HitLogic.effectiveStats(se, "Skyward", nil, { lift = 99 })
	local fr = apexRoot(top, Z.SpikeForward + Z.SpikeCenterDz + 0.25 * SPM)
	local function feint(primary, cards)
		local okT, resT = HitLogic.compute({ action = "Feint", t = 0, root = fr, ball = ballAt(fr, Z.SpikeCenterDz, Z.SpikeCenterDy), vy = 0, grounded = false },
			ctx({ stats = se, ability = primary, abilities = cards and set(primary, cards) or nil, lift = 99 }))
		return okT and resT or nil
	end
	local talonOnly, talonCard, talonThunder = feint("Skyward"), feint("Azure", { "Skyward" }), feint("Thunder", { "Skyward" })
	check(talonOnly and talonCard and talonThunder and talonCard.meta.talon and talonThunder.meta.talon and not talonThunder.meta.thunder
		and talonCard.meta.kmh == talonOnly.meta.kmh and talonThunder.meta.kmh == talonOnly.meta.kmh,
		"a Skyward card makes the feint Talon Drop, before Azure's roll shot, at its plain power", string.format("%.1f km/h", talonOnly and talonOnly.meta.kmh or 0))
	-- Skyward climbs off how high the contact really was, not a Corona card's dive floor
	local sw = Characters.derive(Characters.fromRoster(Roster.get("seora"), "max"))
	local swLow = HitLogic.effectiveStats(sw, "Skyward", nil, {})
	local lowRoot = apexRoot(swLow, 3.5 * K) - vec(0, 3.2, 0)
	local lb = ballAt(lowRoot, 1.0, 0.4)
	local _, skyOnly = spike(lowRoot, lb, { stats = sw, ability = "Skyward" })
	local _, dived = spike(lowRoot, lb, { stats = sw, ability = "Skyward", abilities = set("Skyward", { "Corona" }) }, { sundive = 99 })
	check(dived.meta.dive and dived.meta.liftGain == skyOnly.meta.liftGain and dived.meta.kmh > skyOnly.meta.kmh,
		"a Corona card's Sundive powers her spike, but she climbs only by how high she met it", string.format("+%.3f m either way", skyOnly.meta.liftGain or 0))

	-- prediction stays bit-identical: the client's list (read back from the "Abilities" attribute) is
	-- the server's, Corona's Zenith draws included
	local abl = Characters.abilityList("Thunder", { "Corona", "Azure" })
	local mine = Characters.parseAbilities(Characters.encodeAbilities(abl))
	local pr = apexRoot(SP, 4 * K)
	local pb = ballAt(pr, 0.9, 0.3)
	local okA, a = spike(pr, pb, { seq = 99, ability = "Thunder", abilities = Characters.abilitySet(abl), abilityList = abl }, { energy = 0.8 })
	local okC, c = spike(pr, pb, { seq = 99, ability = "Thunder", abilities = Characters.abilitySet(mine), abilityList = mine }, { energy = 0.8 })
	local zeniths = 0
	for seq = 1, 300 do
		local _, z = spike(pr, pb, { seq = seq, ability = "Thunder", abilities = Characters.abilitySet(abl) })
		zeniths = zeniths + (z.meta.zenith and 1 or 0)
	end
	local pa, pc = BallPhysics.buildPath(a.launch), BallPhysics.buildPath(c.launch)
	check(okA and okC and pa.landing.t == pc.landing.t and (pa.landing.pos - pc.landing.pos).Magnitude == 0 and a.meta.kmh == c.meta.kmh and zeniths > 30 and zeniths < 110,
		"prediction is still bit-identical with stacked abilities (a Corona card's Zenith comes up for a Thunder Spiker)", string.format("Zenith %d of 300", zeniths))
end

print("== your own keys ==")
local Settings = require("Settings")
do
	local clean = Settings.clean({ keys = { Spike = "G", Block = "G", Set = "Escape", Receive = 5, Bogus = "H", Timeout = "One" } })
	check(clean.keys.Spike == "G" and clean.keys.Block == nil and clean.keys.Set == nil and clean.keys.Receive == nil and clean.keys.Bogus == nil and clean.keys.Timeout == nil,
		"saved keys: allowed keys only, one action each (no Escape, no 1 and 2, no junk)")
	local map = Settings.keyMap({ Spike = "G", Block = "Space" })
	check(map.G == "Spike" and map.Space == "Block" and map.Z == nil and map.J == nil and map.W == nil and map.Up == nil and map.E == "Set" and map.A == "MoveLeft",
		"your key replaces that action's defaults and wins over another action's default on it")
	local spikeKeys, blockKeys = Settings.keysText({ Spike = "G" }, "Spike"), Settings.keysText({}, "Block")
	local Tut = require("Tutorial")
	local line = Tut.fill(Tut.drill("block").key, function(action)
		return Settings.keysText({ Block = "G" }, action, " or ")
	end)
	local all = true
	for _, d in ipairs(Tut.Drills) do
		all = all and not string.find(Tut.fill(d.key, function(action)
			return Settings.keysText({}, action, " or ")
		end), "[{}]")
	end
	check(line == "Watch the set. Hold G at the net and let go when their attacker jumps." and all, "the tutorial's keyboard lines show your keys", line)
	check(spikeKeys == "G" and blockKeys == "W / Up" and Settings.keysText({}, "SlideFeint") == "C / L Shift / R Shift / L", "the keys an action is on read as text", spikeKeys .. " | " .. blockKeys)
end

print("== tier colours ==")
do
	check(Characters.color("S-") == Config.TierColors["S-"] and Characters.color("S") == Config.TierColors.S and Characters.color("S-") ~= Characters.color("S") and Characters.color("A+") == Config.TierColors.A,
		"S- has its own colour (green), apart from the S tier's gold; other tiers keep their letter's")
end

print("== AI blocks ==")
do
	-- the AI goes up against open and back sets too (it only ever blocked quicks: the open set lands
	-- past the old 2.2 m), every time (the owner, 2026-10-25: "make him jump everytime")
	local B = Config.Bots
	check(B.BlockSetMaxDepth > Court.attackDepth("Open") + 0.5 and B.BlockSetMaxDepth >= Court.attackDepth("Back") and B.BlockChance == nil,
		"the AI blocks open and back sets, not just quicks, every time",
		string.format("up to %.1f m (open %.1f, back %.1f)", B.BlockSetMaxDepth / Config.Scale.StudsPerMeter, Court.attackDepth("Open") / Config.Scale.StudsPerMeter, Court.attackDepth("Back") / Config.Scale.StudsPerMeter))
end

print("== four touches ==")
do
	local touch = { team = "Away", count = 3, lastId = "a" }
	local ok, why = HitLogic.canTouch(touch, "Away", "b", "Spike", 3)
	-- your own serve (count 3) still at your hand: a second swing is a double, not a fault (Taeho)
	local served = HitLogic.nextTouch({ count = 0 }, "Away", "taeho", "Serve")
	local okS, whyS = HitLogic.canTouch(served, "Away", "taeho", "Spike", 3)
	check(not ok and HitLogic.isFourthTouchFault(why, "Spike") and HitLogic.isFourthTouchFault(why, "Set") and not HitLogic.isFourthTouchFault(why, "Bump") and not HitLogic.isFourthTouchFault("double", "Spike")
		and not okS and whyS == "double" and not HitLogic.isFourthTouchFault(whyS, "Spike"),
		"a swing or a set on your team's fourth ball is a fault (an automatic receive isn't); swinging again at your own serve isn't")
end

print("== the third wave ==")
do
	local yeonho = Characters.derive(Characters.fromRoster(Roster.get("yeonho"), "max"))
	local sr = apexRoot(yeonho, 3.5 * K)
	local b = ballAt(sr, 0.9, 0)
	local _, pl = spike(sr, b, { stats = yeonho, ability = "Plunge" })
	local _, nopl = spike(sr, b, { stats = yeonho })
	local pp, np = BallPhysics.buildPath(pl.launch), BallPhysics.buildPath(nopl.launch)
	local function angleIn(path)
		local v = path.landing.vel
		return math.deg(math.atan(-v.Y / math.max(math.abs(v.Z), 0.01)))
	end
	local depthIn = oppDepth(pp) / SPM
	check(pl.meta.plunge and not nopl.meta.plunge and #pp.segs == 2 and pp.flags.dive ~= nil and not pp.flags.netTouch and (pp.flags.crossings or 0) == 1
		and angleIn(pp) >= 50 and angleIn(pp) > angleIn(np) + 12 and pl.meta.kmh > nopl.meta.kmh,
		"Plunge Spin: flat over the net, then a turn and a plunge", string.format("lands %.1f m in at %.0f degrees (a usual spike: %.1f m at %.0f), %.0f vs %.0f km/h", depthIn, angleIn(pp), oppDepth(np) / SPM, angleIn(np), pl.meta.kmh, nopl.meta.kmh))
	-- the contact sets the depth: met out in front it flies on and dives near the back line, met at
	-- the hand it turns down short; both stay in and steep
	local _, frontHit = spike(sr, ballAt(sr, 2.6, 0), { stats = yeonho, ability = "Plunge" })
	local _, backHit = spike(sr, ballAt(sr, -0.1, 0), { stats = yeonho, ability = "Plunge" })
	local fp, bp = BallPhysics.buildPath(frontHit.launch), BallPhysics.buildPath(backHit.launch)
	local fd, bd = oppDepth(fp) / SPM, oppDepth(bp) / SPM
	check(frontHit.meta.plunge and backHit.meta.plunge and fd > bd + 3 and fd <= Config.Court.SideDepth / SPM and bd >= 1 and angleIn(fp) >= 45 and angleIn(bp) >= 58 and not fp.flags.netTouch and not bp.flags.netTouch,
		"Plunge Spin's depth follows the contact: in front, near the back line; at the hand, short and steep", string.format("front %.1f m at %.0f degrees, back %.1f m at %.0f", fd, angleIn(fp), bd, angleIn(bp)))
	local turn = pp.segs[2]
	check(turn.p.Y > Config.Court.NetTop and -turn.p.Z * side > 0, "the turn comes past the net, over the tape", string.format("%.2f m high, %.2f m past", turn.p.Y / SPM, -turn.p.Z * side / SPM))
	local mateus, junseo, yejun = Roster.get("mateus"), Roster.get("junseo"), Roster.get("yejun")
	local tallest, shortestWS = true, true
	for _, c in ipairs(Roster) do
		tallest = tallest and (c == mateus or c.Height < mateus.Height)
		shortestWS = shortestWS and (c.Role ~= "WS" or c == junseo or c.Height > junseo.Height)
	end
	check(tallest and mateus.Ability == nil and shortestWS and junseo.Jump < yejun.Jump and junseo.Jump >= 185,
		"Mateus is the tallest (no ability); Junseo the shortest wing spiker, with a jump just under YeJun's", string.format("%d cm; %d cm, jump %d vs %d", mateus.Height, junseo.Height, junseo.Jump, yejun.Jump))
	-- the height cap went up for Mateus without changing anyone else's hit zone (1.08 at 210 cm)
	local gaeul = Characters.derive(Characters.fromRoster(Roster.get("tetsuo"), "max"))
	local m = Characters.derive(Characters.fromRoster(mateus, "max"))
	local ye = Characters.derive(Characters.fromRoster(yejun, "max"))
	check(math.abs(gaeul.Reach - (0.94 + 0.14 * (201 - 165) / 45)) < 1e-9 and m.Reach > 1.08 and m.contactMaxStuds < ye.contactMaxStuds and mateus.Attack < gaeul.Attack,
		"a 216 cm Mateus built to block: everyone else's hit zone is as before, his is the biggest; YeJun still hits higher, he spikes softer than Tetsuo", string.format("zone %.3f, contact %.2f m (YeJun %.2f, Tetsuo %.2f)", m.Reach, m.ContactMaxM, ye.ContactMaxM, gaeul.ContactMaxM))
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
	-- unbreakable: standing on the floor (no jump), a little off the net, a 4.75 m spike crossing in
	-- front of the wall is still shut down; without the wall it's nowhere near the hands
	local floorRoot = vec(0, GROUND, side * (Z.BlockNetDistance + 1.5))
	local sky = vec(0, 4.75 * SPM, side * 0.2)
	local okNo = HitLogic.compute({ action = "Block", t = 0, root = floorRoot, ball = sky, grounded = true }, ctx({ stats = gaeul, ability = "IronWall", lastHit = lastSpike, ballVel = vec(0, -8, side * 60) }))
	local okWall, ww = HitLogic.compute({ action = "Block", t = 0, root = floorRoot, ball = sky, grounded = true }, ctx({ stats = gaeul, ability = "IronWall", ironWall = true, lastHit = { team = "Home", hitType = "Spike", kmh = 240, pierce = true, breakAtk = 999 }, ballVel = vec(0, -8, side * 60) }))
	check(not okNo and okWall and ww.meta.perfectBlock and ww.meta.outcome == "Stuff",
		"Iron Wall is unbreakable: standing, off the net, a 4.75 m 240 km/h spike that breaks blocks is still shut down", okWall and ww.meta.outcome or "no block")
end

print("== the Halloween event ==")
do
	-- the owner (2026-10-14): a daily Halloween Match against the AI, two stages of 12 points, a
	-- roulette before each stage that stops on 3 cards and you pick 1, twice; at least 50 cards
	-- ("all the cards like the abilities of the characters + some buffs"); Candy; a limited banner
	-- with the two balls, two score effects and the Reaper skin; until November 2
	local Halloween = require("Halloween")
	local HW = Config.Halloween
	local cards = Halloween.cards()
	local keys, ok, bad = {}, true, {}
	local abilities = {}
	for _, c in ipairs(cards) do
		local good = keys[c.Key] == nil and HW.Kinds[c.Kind] ~= nil and HW.Weights[c.Rarity] ~= nil and (c.Target == "Self" or c.Target == "Team" or c.Target == "Foes")
			and type(c.Name) == "string" and #Halloween.blurb(c) > 8
		for k in pairs(c.Add or {}) do
			local known = false
			for _, s in ipairs(Config.Stats.Order) do
				known = known or s == k
			end
			good = good and known
		end
		if c.Kind == "Ability" then
			good = good and Config.Abilities[c.Ability] ~= nil and c.Target == "Self"
			abilities[c.Ability] = true
		end
		if not good then
			table.insert(bad, c.Key)
		end
		keys[c.Key] = true
		ok = ok and good
	end
	local missing = {}
	for _, a in ipairs(Config.AbilityOrder) do
		if not abilities[a] then
			table.insert(missing, a)
		end
	end
	check(ok and #cards >= 50 and #missing == 0, "at least 50 cards, each with a name, a kind, a rarity and a line; one card per ability",
		string.format("%d cards; bad: %s; abilities missing: %s", #cards, table.concat(bad, ", "), table.concat(missing, ", ")))
	check(Halloween.blurb("aThunder") == "Thunder Spiker for this run, +10 Jump." and Halloween.blurb("aRallyCry") == "Rally Cry for this run, +50 to every stat."
		and Halloween.passiveLine("aThunder") == "With Double Swing, Storm Call, Static Charge, High Strike" and Halloween.passiveLine("Coven") == nil
		and Halloween.blurb("Coven") == "Your team: +10 Attack." and Halloween.blurb("Withering") == "The other team: Stamina pool -25%.",
		"the owner's examples: Thunder Spiker with +10 Jump, Rally Cry with +50 to every stat", Halloween.blurb("aThunder") .. " / " .. Halloween.blurb("aRallyCry"))

	-- the roulette: 3 different cards, none you hold; the same seed deals the same; the AI never
	-- gets an ability card; rarer cards come up less
	local rng = Random.new(7)
	local held = { "PumpkinPower", "aThunder" }
	local offers = Halloween.offers(rng, held, HW.Offers)
	local distinct = #offers == 3 and offers[1] ~= offers[2] and offers[2] ~= offers[3] and offers[1] ~= offers[3]
	for _, k in ipairs(offers) do
		distinct = distinct and k ~= "PumpkinPower" and k ~= "aThunder"
	end
	local a1 = Halloween.offers(Random.new(99), {}, 3)
	local a2 = Halloween.offers(Random.new(99), {}, 3)
	local seen, aiAbility = { Common = 0, Legendary = 0 }, 0
	local r2 = Random.new(3)
	for _ = 1, 400 do
		for _, k in ipairs(Halloween.offers(r2, {}, 3)) do
			local c = Halloween.card(k)
			seen[c.Rarity] = (seen[c.Rarity] or 0) + 1
		end
		for _, k in ipairs(Halloween.offers(r2, {}, 3, true)) do
			if Halloween.card(k).Kind == "Ability" then
				aiAbility = aiAbility + 1
			end
		end
	end
	check(distinct and table.concat(a1, ",") == table.concat(a2, ",") and aiAbility == 0 and seen.Common > seen.Legendary * 2,
		"a pick offers 3 different cards you don't hold; the same seed deals the same; the AI never takes an ability; rarer cards come up less",
		string.format("%s; 1200 offers: %d Common, %d Legendary; AI abilities %d", table.concat(offers, ", "), seen.Common, seen.Legendary, aiAbility))
	check(Halloween.aiPick({ "PumpkinPower", "NightmareFuel", "Coven" }) == "NightmareFuel", "the AI picks the rarest card offered")

	-- a hand: ability cards stack (the owner, 2026-10-15: "it seems the cards take away the
	-- abilities. i want them to stack"), every one kept in pick order; no card twice; Stages x Picks
	-- at most; a pick never offers the card of your character's own ability (it would add nothing)
	local hand = Halloween.addCard({}, "aThunder")
	hand = Halloween.addCard(hand, "PumpkinPower")
	hand = Halloween.addCard(hand, "aAzure")
	hand = Halloween.addCard(hand, "PumpkinPower")
	local abs = Halloween.abilitiesOf(hand)
	local clean = Halloween.cleanHand({ "aThunder", "x", "Coven", "aFeral", "BatWings", "GhostStep", "BoneArmor", "Cobwebs" })
	local two = Halloween.cleanHand({ "aThunder", "aAzure", "aThunder" })
	local ownOffered, thunderOffered = 0, 0
	local ro = Random.new(11)
	for _ = 1, 300 do
		for _, k in ipairs(Halloween.offers(ro, {}, 3, false, { "Thunder" })) do
			ownOffered = ownOffered + (k == "aThunder" and 1 or 0)
		end
		for _, k in ipairs(Halloween.offers(ro, {}, 3)) do
			thunderOffered = thunderOffered + (k == "aThunder" and 1 or 0)
		end
	end
	check(#hand == 3 and hand[1] == "aThunder" and hand[2] == "PumpkinPower" and hand[3] == "aAzure" and #abs == 2 and abs[1] == "Thunder" and abs[2] == "Azure"
		and #clean == HW.Stages * HW.Picks and #Halloween.abilitiesOf(clean) == 0 and #two == 2 and table.concat(Halloween.abilitiesOf(two), ",") == "Thunder,Azure"
		and Halloween.abilityOf == nil and ownOffered == 0 and thunderOffered > 0,
		"ability cards stack: a hand keeps every one in pick order, never a card twice, Stages x Picks at most; your own ability's card isn't offered",
		table.concat(hand, ", ") .. " / " .. table.concat(clean, ", ") .. string.format("; Thunder Spiker offered %d times in 300 picks, %d to a Thunder Spiker", thunderOffered, ownOffered))
	-- at most two of them beside your own (the owner, 2026-10-15: "you can stack up to 2 abilities
	-- alongside your main one"): a third isn't added or kept, and none is offered once you hold two
	local three = Halloween.addCard(Halloween.addCard(Halloween.addCard({}, "aThunder"), "aAzure"), "aFeral")
	local kept3 = Halloween.cleanHand({ "aThunder", "aAzure", "aFeral", "Coven" })
	local offeredFull, offeredOne = 0, 0
	local rf = Random.new(5)
	for _ = 1, 300 do
		for _, k in ipairs(Halloween.offers(rf, { "aThunder", "aAzure" }, 3)) do
			offeredFull = offeredFull + (Halloween.card(k).Kind == "Ability" and 1 or 0)
		end
		for _, k in ipairs(Halloween.offers(rf, { "aThunder" }, 3)) do
			offeredOne = offeredOne + (Halloween.card(k).Kind == "Ability" and 1 or 0)
		end
	end
	check(HW.MaxAbilityCards == 2 and #three == 2 and table.concat(Halloween.abilitiesOf(three), ",") == "Thunder,Azure" and table.concat(kept3, ",") == "aThunder,aAzure,Coven"
		and offeredFull == 0 and offeredOne > 0,
		"two ability cards at most beside your own: a third isn't added or kept, and none is offered once you hold two",
		string.format("ability cards offered: %d holding two, %d holding one (300 picks each)", offeredFull, offeredOne))

	-- who each card hits: Self its holder (the AI's, every bot on its side), Team the holder's side,
	-- Curse the other side
	local holders = {
		{ team = "Home", userId = 1, cards = { "PumpkinPower", "Coven", "Cobwebs" } },
		{ team = "Home", userId = 2, cards = { "BatWings" } },
		{ team = "Away", cards = { "BoneArmor", "HexWeakness" } },
	}
	local p1 = Halloween.hexFor(holders, "Home", 1)
	local p2 = Halloween.hexFor(holders, "Home", 2)
	local mate = Halloween.hexFor(holders, "Home", nil)
	local foe = Halloween.hexFor(holders, "Away", nil)
	check(p1 == "PumpkinPower,Coven,HexWeakness" and p2 == "Coven,BatWings,HexWeakness" and mate == "Coven,HexWeakness" and foe == "Cobwebs,BoneArmor",
		"a card hits its holder, a team card the holder's whole side (bots too), a curse the other side, the AI's cards its own bots", p1 .. " | " .. p2 .. " | " .. mate .. " | " .. foe)
	local fx = Halloween.effects("PumpkinPower,Coven,HexWeakness")
	check(fx.add.Attack == 18 and Halloween.effects("PumpkinPower,Coven,HexWeakness") == fx and Halloween.effects("") == nil and Halloween.effects("nope") == nil,
		"a hand's cards add up (+20 +10 -12 Attack), one table per Hex string; none is nothing", string.format("+%d Attack", fx.add.Attack))

	-- the cards in play: stats, height, points per point the other team scores, every stat
	local base = Characters.stats("S+", "WS", 190)
	local pp = HitLogic.effectiveStats(base, nil, nil, { hex = Halloween.effects("PumpkinPower") })
	local giant = HitLogic.effectiveStats(base, nil, nil, { hex = Halloween.effects("GraveGiant") })
	local moon0 = HitLogic.effectiveStats(base, nil, nil, { hex = Halloween.effects("FullMoon"), enemyPoints = 0 })
	local moon8 = HitLogic.effectiveStats(base, nil, nil, { hex = Halloween.effects("FullMoon"), enemyPoints = 8 })
	local mash = HitLogic.effectiveStats(base, nil, nil, { hex = Halloween.effects("MonsterMash") })
	local cursed = HitLogic.effectiveStats(base, nil, nil, { hex = Halloween.effects("FogOfDread") })
	check(pp.Attack == base.Attack + 20 and pp.Power > base.Power and giant.Height == base.Height + 15 and giant.contactMaxStuds > base.contactMaxStuds
		and moon8.Attack == base.Attack + 24 and moon8.Jump == base.Jump + 16 and moon0.Attack == base.Attack
		and mash.Speed == math.floor(base.Speed * 1.08 + 0.5) and cursed.Defense == base.Defense - 6,
		"stat cards add points, Grave Giant raises the hitting point, Full Moon grows with the other team's points, Monster Mash multiplies, a curse takes away",
		string.format("Attack %d -> %d; %d cm -> %d; Full Moon at 8: +%d Attack; Monster Mash Speed %d -> %d", base.Attack, pp.Attack, base.Height, giant.Height, moon8.Attack - base.Attack, base.Speed, mash.Speed))

	-- spikes, serves, reach, drain
	local root = apexRoot(SP, 3.5 * K)
	local b = ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local _, plain = spike(root, b)
	local _, smash = spike(root, b, { hex = Halloween.effects("JackSmash") })
	local _, dig = spike(root, b, { hex = Halloween.effects("Gravedigger") })
	-- a ball just past the edge of the spike zone: out of reach, but not with Long Claws
	local far = nil
	for dz = Z.SpikeCenterDz, Z.SpikeCenterDz + Z.SpikeRadiusZ * 2, 0.05 do
		local probe = ballAt(root, dz, Z.SpikeCenterDy)
		if not HitLogic.spikeZone(root, probe, side, SP, 1) and not far then
			far = probe
		end
	end
	local okFar = spike(root, far)
	local okClaws = spike(root, far, { hex = Halloween.effects("LongClaws") })
	check(math.abs(smash.meta.kmh / plain.meta.kmh - 1.08) < 0.001 and math.abs(dig.meta.tierDrain / plain.meta.tierDrain - 1.25) < 0.001 and not okFar and okClaws,
		"Jack-o'-Smash spikes 8% faster, Gravedigger's cost the digger 25% more, Long Claws reaches a ball just out of reach",
		string.format("%.1f -> %.1f km/h", plain.meta.kmh, smash.meta.kmh))
	local serveZ = Court.serveSpot(side, "WS").Z
	local sroot = vec(0, GROUND + Characters.jumpHeight(SP, GROUND), serveZ)
	local sball = ballAt(sroot, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local _, s0 = HitLogic.compute({ action = "Serve", t = 0, root = sroot, ball = sball, grounded = false }, ctx({ touchNumber = 1 }))
	local _, s1 = HitLogic.compute({ action = "Serve", t = 0, root = sroot, ball = sball, grounded = false }, ctx({ touchNumber = 1, hex = Halloween.effects("PoltergeistServe") }))
	local _, s2 = HitLogic.compute({ action = "Serve", t = 0, root = sroot, ball = sball, grounded = false }, ctx({ touchNumber = 1, hex = Halloween.effects("JackSmash") }))
	check(math.abs(s1.meta.kmh / s0.meta.kmh - 1.12) < 0.001 and s2.meta.kmh == s0.meta.kmh, "Poltergeist Serve: jump serves 12% faster (a spike card leaves serves alone)", string.format("%.1f -> %.1f km/h", s0.meta.kmh, s1.meta.kmh))
	local rroot = vec(0, GROUND, side * 6 * SPM)
	local rball = vec(0, GROUND + Z.ReceiveIdealY, side * 6 * SPM)
	local heavy = { hitType = "Spike", team = "Home", kmh = 150, tierDrain = 1 }
	local function receive(hexStr)
		local _, r = HitLogic.compute({ action = "Bump", t = 0, root = rroot, ball = rball, vy = 0, grounded = true, stanceAge = 0.6 },
			ctx({ touchNumber = 1, lastHit = heavy, ballVel = vec(0, -60 * K, side * 170 * K), stamina = { value = 400, max = 400 }, hex = Halloween.effects(hexStr) }))
		return r.meta.drain or 0
	end
	local d0, dGuard, dBleed = receive(""), receive("GhostlyGuard"), receive("BleedingGuard")
	check(d0 > 0 and math.abs(dGuard / d0 - 0.7) < 0.001 and math.abs(dBleed / d0 - 1.2) < 0.001, "Ghostly Guard: your receives cost 30% less; Bleeding Guard (a curse): 20% more", string.format("drain %.1f / %.1f / %.1f", d0, dGuard, dBleed))
	-- the block: Wall of Bones reaches higher, Phantom Hands stuffs more
	local aTier = Characters.stats("A")
	local broot = vec(0, GROUND + Characters.jumpHeight(aTier, GROUND) * 0.85, side * 1.2)
	local above = vec(0, broot.Y + Z.BlockReachUp + Config.Ball.Radius + 0.6, side * 0.6)
	local okHigh = HitLogic.blockBox(broot, above, side, aTier, nil)
	local okBones = HitLogic.blockBox(broot, above, side, aTier, Halloween.blockReach(nil, Halloween.effects("WallOfBones")))
	local mid = nil
	for dy = 0, 14, 0.1 do
		local bb = vec(0, C.NetTop + dy, side * 0.6)
		local okb, q = HitLogic.blockBox(broot, bb, side, aTier, false)
		if okb and q > 0.56 and q < 0.64 and not mid then
			mid = bb -- (stuffed only with Phantom Hands' push: 130 km/h takes 0.21 off it, a stuff is 0.45)
		end
	end
	local function stuffs(hexStr)
		local n = 0
		for seq = 1, 200 do
			local okb, r = HitLogic.compute({ action = "Block", t = 0, root = broot, ball = mid, vy = 0, grounded = false },
				ctx({ stats = aTier, lastHit = { hitType = "Spike", team = "Home", kmh = 130, tierDrain = 1 }, ballVel = vec(0, -8, side * 30), seq = seq, hex = Halloween.effects(hexStr) }))
			if okb and r.meta.outcome == "Stuff" then
				n = n + 1
			end
		end
		return n
	end
	local st0, st1 = stuffs(""), stuffs("PhantomHands")
	check(not okHigh and okBones and Halloween.blockReach(true, Halloween.effects("WallOfBones")) == true and mid ~= nil and st1 > st0,
		"Wall of Bones blocks a ball over your usual reach (Iron Wall's wall stays as it is); Phantom Hands stuffs more", string.format("stuffs of 200: %d -> %d", st0, st1))

	-- Candy: the first clear of a difficulty each day pays in full, later ones less, a run lost in
	-- stage 2 a little, one lost in stage 1 nothing; a new day clears the first clears
	local hard = Halloween.difficulty("Hard")
	local ev = Halloween.clean({ candy = 5, cleared = { Hard = true, Bogus = true }, day = 10 })
	local first = Halloween.firstClear(ev, "Hard", 10, false)
	local nextDay = Halloween.firstClear(ev, "Hard", 11, true)
	local again = Halloween.firstClear(ev, "Hard", 11, false)
	check(Halloween.payout("Hard", 2, true, true) == hard.Candy and Halloween.payout("Hard", 2, true, false) == hard.Repeat and Halloween.payout("Hard", 2, false, true) == hard.StageOne
		and Halloween.payout("Hard", 1, false, true) == 0 and Halloween.payout("Easy", 2, true, true) < hard.Candy and ev.candy == 5 and ev.cleared.Bogus == nil
		and not first and nextDay and not again,
		"Candy: a day's first clear pays in full, later ones less, a stage-2 loss a little, a stage-1 loss nothing; harder pays more; each day starts over",
		string.format("Hard %d / %d / %d", hard.Candy, hard.Repeat, hard.StageOne))
	check(Halloween.day(HW.Ends) ~= Halloween.day(HW.Ends - 86400) and Halloween.active(HW.Ends - 1) and not Halloween.active(HW.Ends) and HW.Ends == 1793685600,
		"the event runs until the end of November 2 (Chicago)")

	-- the banner: chances add up to 1, the two Mythic skins (the Reaper and the Fallen Angel) share
	-- its rarest weight, every item exists, the limited items stay off the usual banners
	local total, reaper, fallen, known = 0, 0, 0, true
	-- the Halloween 2026 player card pulls too (the owner, 2026-10-17: "add a halloween 2026 card also pullable")
	local hwCard = Halloween.bannerItem("Card", "Halloween2026")
	local hwCardChance = 0
	for _, row in ipairs(Halloween.bannerTable()) do
		if row.item.kind == "Card" then
			hwCardChance = row.chance
		end
	end
	check(hwCard ~= nil and hwCard.rarity == "Epic" and hwCard.scout > 0 and hwCardChance > 0, "the Halloween 2026 player card is on the Halloween banner (and scoutable)", string.format("%.2f%% a recruit", hwCardChance * 100))
	for _, row in ipairs(Halloween.bannerTable()) do
		total = total + row.chance
		if row.item.key == "Reaper" then
			reaper = row.chance
		elseif row.item.key == "FallenAngel" then
			fallen = row.chance
		end
		known = known and row.item.name ~= nil and row.item.scout > 0
	end
	local inBall = false
	for _, row in ipairs(Spins.table("Ball")) do
		inBall = inBall or row.item.Limited ~= nil
	end
	local rr = Random.new(5)
	local pulls, reapers = 8000, 0
	for _ = 1, pulls do
		local k = Halloween.roll(rr).key
		if k == "Reaper" or k == "FallenAngel" then
			reapers = reapers + 1
		end
	end
	check(math.abs(total - 1) < 1e-9 and math.abs(reaper - 0.001) < 1e-9 and math.abs(fallen - 0.001) < 1e-9 and known and #Halloween.bannerItems() == #HW.Banner.Items and not inBall and reapers > 4 and reapers < 35
		and Halloween.cost("Candy", 10) == 250 and Halloween.cost("VP", 1) == 80 and Halloween.cost("VP", 10) == 800 and Halloween.cost("VP", 3) == nil,
		"the Halloween banner: odds add up, the two Mythic skins 0.1% each, limited items stay off the usual banners", string.format("%d Mythic skins in %d pulls", reapers, pulls))
	-- the Fallen Angel: YeJun's alone, his jump the skin's own (hidden: never on a banner or in the
	-- Locker), his thunder in its colour
	local FA = HW.Skins.FallenAngel
	local jump = Spins.item("Jump", FA.Jump)
	check(Halloween.skinFits("FallenAngel", "yejun") and not Halloween.skinFits("FallenAngel", "taeha") and not Halloween.skinFits("Reaper", "yejun")
		and jump ~= nil and jump.Hidden and jump.Limited ~= nil and FA.Thunder ~= nil and FA.Rarity == "Mythic"
		and table.concat(Halloween.skinsFor("yejun"), ",") == "FallenAngel" and Halloween.cleanSkins({ FallenAngel = { copies = 1, on = { yejun = true, taeha = true } } }).FallenAngel.on.taeha == nil,
		"the Fallen Angel is YeJun's skin alone, with its own hidden jump (Underworld) and violet thunder")
	-- Rest in Peace's gravestone (the owner: "Players can customize text and add image URL to the
	-- tombstone. Default is just player name"): a picture from an id or a link, words trimmed and capped
	local GI, GT = Halloween.graveImage, Halloween.graveText
	local long = string.rep("x", Config.Grave.TextMax + 25)
	local g = Halloween.cleanGrave({ text = "  Here   lies\nthe other team  ", image = "https://create.roblox.com/store/asset/12345678/Cool" })
	check(GI("rbxassetid://987654321") == 987654321 and GI("https://www.roblox.com/library/55555555/x") == 55555555 and GI(1234567) == 1234567 and GI("abc") == nil and GI("12") == nil and GI("") == nil
		and #GT(long) == Config.Grave.TextMax and GT(nil) == "" and g.text == "Here lies the other team" and g.image == 12345678 and Halloween.cleanGrave(nil).image == 0
		and Spins.item("Effect", "Grave") ~= nil and Spins.item("Effect", "Grave").Limited == "Halloween",
		"Rest in Peace: the gravestone takes a picture from any Roblox id or link, and words trimmed to one line of up to 40")
	-- the S+ quotes on their recruits (the owner: "a little quote for each s+ recruitment"): S+ ids only
	local quotesOk = Config.Quotes.yejun == "From above the net there is no mercy... only descent."
	for id, q in pairs(Config.Quotes) do
		local c = Roster.get(id)
		quotesOk = quotesOk and c ~= nil and c.Tier == "S+" and type(q) == "string" and #q > 0 and not string.find(q, '"', 1, true)
	end
	check(quotesOk, "S+ recruits can carry a quote (YeJun's first), keyed by roster id")

	-- a run carried through a teleport (Lobbies.export/import): its stage, every hand and the AI's,
	-- made safe on the way in; the players' hands are Home's, the AI's Away's
	local run = { diff = "Hard", stage = 2, hands = { [101] = { "aThunder", "Coven" }, [202] = { "BatWings" } }, ai = { "BoneArmor" } }
	local back = Lobbies.importEvent(Lobbies.exportEvent(run))
	local junk = Lobbies.importEvent({ diff = "Hard", stage = 9, hands = { ["303"] = "aThunder,aAzure,nope,Coven,Coven" }, ai = "aFeral,BoneArmor" })
	local hs = Halloween.holders(back.hands, back.ai)
	check(back.diff == "Hard" and back.stage == 2 and back.ready and table.concat(back.hands[101], ",") == "aThunder,Coven" and table.concat(back.hands[202], ",") == "BatWings"
		and table.concat(back.ai, ",") == "BoneArmor" and Lobbies.importEvent({ diff = "Spooky" }) == nil and junk.stage == Config.Halloween.Stages and table.concat(junk.hands[303], ",") == "aThunder,aAzure,Coven"
		and #hs == 3 and hs[1].userId == 101 and hs[1].team == "Home" and hs[3].team == "Away" and hs[3].userId == nil,
		"a Halloween run survives a teleport (stage, every hand, the AI's), checked on the way in", table.concat(junk.hands[303], ","))

	-- the Reaper is Taeho's alone (the owner, 2026-10-15: "restrict the skin to only taeho now"): a
	-- copy applied to anyone else comes back free; it applies to Taeho only, switched off and on any
	-- time (his page's swap); a second copy is a duplicate (Candy)
	local skins = Halloween.cleanSkins({ Reaper = { copies = 1, on = { yejun = true, ghost = 5 } } }, function(id) return Roster.get(id) ~= nil end)
	local freed = Halloween.freeCopies(skins, "Reaper")
	local dupBefore = Halloween.skinDuplicate(skins, "Reaper")
	local okA, whyA = Halloween.applySkin(skins, "Reaper", "dante")
	local okB = Halloween.applySkin(skins, "Reaper", "taeha")
	local okC, whyC = Halloween.applySkin(skins, "Reaper", "taeha")
	local offOk = Halloween.toggleSkin(skins, "Reaper", "taeha", false)
	local offShow = Halloween.skinOf(skins, "taeha")
	Halloween.toggleSkin(skins, "Reaper", "taeha", true)
	local okD = Halloween.toggleSkin(skins, "Reaper", "laith", false)
	local fresh = Halloween.cleanSkins({}, nil)
	check(freed == 1 and skins.Reaper.on.yejun == nil and skins.Reaper.on.ghost == nil and dupBefore
		and not okA and whyA == "wrongChar" and okB and not okC and whyC == "applied" and offOk and offShow == nil and Halloween.skinOf(skins, "taeha") == "Reaper"
		and Halloween.skinOf(skins, "yejun") == nil and Halloween.skinOf({ Reaper = { copies = 1, on = { yejun = true } } }, "yejun") == nil and not okD
		and Halloween.skinDuplicate(skins, "Reaper") and not Halloween.skinDuplicate(fresh, "Reaper") and Halloween.skinFits("Reaper", "taeha") and not Halloween.skinFits("Reaper", "yejun")
		and Halloween.skinCharNames("Reaper") == "Taeho",
		"the Reaper is Taeho's alone: an old copy on YeJun comes back free, it applies to Taeho only, swaps off and on, and a second copy is a duplicate")

	-- a skin comes with its character (the owner, 2026-10-16: "make sure pulling the skins grant the
	-- characters aswell"): a copy gives Taeho or YeJun when they're missing, once; no copy, nothing
	local pulled = { Reaper = { copies = 1, on = {} }, FallenAngel = { copies = 0, on = {} } }
	local chars = { shoyo = true }
	local gave = Halloween.skinChars(pulled, chars)
	local again = Halloween.skinChars(pulled, chars)
	local noAngelYet = chars.yejun == nil
	Halloween.addCopy(pulled, "FallenAngel")
	local angel = Halloween.skinChars(pulled, chars)
	check(#gave == 1 and gave[1] == "taeha" and chars.taeha and noAngelYet and #again == 0 and #angel == 1 and angel[1] == "yejun" and chars.yejun and chars.shoyo
		and #Halloween.skinChars(nil, chars) == 0,
		"pulling a skin brings its character: the Reaper gives Taeho, the Fallen Angel YeJun, each only when missing")

	-- Candy Corn is a colour, not a trail (the owner, 2026-10-15: "you are mixing up trails and colors
	-- again. the candy corn is a color"): a spike colour in three bands, sold and pulled as one; Bat
	-- Swarm is the trail (its bats: Fx.batRing)
	local ccShop = nil
	for _, row in ipairs(Config.Halloween.Shop) do
		if row.Key == "CandyCorn" then
			ccShop = row
		end
	end
	local cc = Spins.item("Color", "CandyCorn")
	check(cc ~= nil and cc.Color ~= nil and type(cc.Trail) == "table" and #cc.Trail == 3 and Spins.item("Trail", "CandyCorn") == nil
		and Halloween.bannerItem("Color", "CandyCorn") ~= nil and Halloween.bannerItem("Trail", "CandyCorn") == nil and ccShop and ccShop.Item.Kind == "Color"
		and Spins.item("Trail", "Bats") ~= nil and Spins.item("Color", "Bats") == nil,
		"Candy Corn is a spike colour in three bands (banner and shop too); Bat Swarm is the trail")

	-- Home's rooms (the owner, 2026-10-15: "add a halloween style background you can also spin for
	-- kind of like how you can swap this"): the Clubhouse is everyone's; the Haunted Forest is won
	-- on the Halloween banner and swapped in from Decorate; a saved room you don't own falls back
	local Rooms = require("Rooms")
	local fresh = Rooms.clean(nil)
	local junk = Rooms.clean({ owned = { Haunted = true, Nope = true, Clubhouse = true }, on = "Haunted" })
	local junkOn = junk.on
	local stolen = Rooms.clean({ owned = {}, on = "Haunted" })
	local okLocked, whyLocked = Rooms.equip(fresh, "Haunted")
	local okDev = Rooms.equip(Rooms.clean(nil), "Haunted", true)
	local okOwn = Rooms.equip(junk, "Clubhouse")
	local onBanner = Halloween.bannerItem("Room", "Haunted")
	check(fresh.on == "Clubhouse" and junk.owned.Haunted == true and junk.owned.Nope == nil and junk.owned.Clubhouse == nil and junkOn == "Haunted"
		and stolen.on == "Clubhouse" and not okLocked and whyLocked == "locked" and okDev and okOwn and junk.on == "Clubhouse"
		and Rooms.current({ owned = {}, on = "Haunted" }, true) == "Haunted" and Rooms.current({ owned = {}, on = "Haunted" }) == "Clubhouse"
		and onBanner ~= nil and onBanner.rarity == "Legendary" and onBanner.name == "Haunted Forest",
		"Home's rooms: the Clubhouse is everyone's, the Haunted Forest is won on the Halloween banner and swapped in; one you don't own falls back")
end

print("== saving ==")
do
	-- every field the loader reads back (sanitizeProfile's out.<field> = ...) is in the save
	-- payload (the Halloween event's Candy, scout points and Reaper copies once weren't, so a rejoin
	-- lost them)
	local f = io.open(ROOT .. "/src/server/Services/ProfileService.lua")
	local src = f and f:read("*a") or ""
	if f then
		f:close()
	end
	local loader = string.match(src, "local function sanitizeProfile%(data%)(.-)\nend\n") or ""
	local payload = string.match(src, "local payload = (%b{})") or ""
	local missing, n = {}, 0
	local seen = {}
	for field in string.gmatch(loader, "\n%s*out%.([%w_]+)%s*=") do
		if not seen[field] then
			seen[field] = true
			n = n + 1
			if not string.find(payload, "\n%s*" .. field .. "%s*=%s*profile%." .. field) then
				table.insert(missing, field)
			end
		end
	end
	check(n > 20 and #missing == 0, "every profile field the loader reads is saved", n .. " fields; missing: " .. table.concat(missing, ", "))
end

print("== the Tyrant (Dohwan) ==")
do
	local A0Tyrant = Config.Abilities.Tyrant
	local TY = Config.Abilities.Tyrant
	local dohwan = Characters.derive(Characters.fromRoster(Roster.get("dohwan"), "max"))
	local sroot = vec(0, GROUND, side * H.SetterDepth)
	local sball = vec(0, sroot.Y + Z.SetIdealY, sroot.Z)
	local function set(ability, extraCtx, setType)
		local c = { touchNumber = 2, stats = dohwan, ability = ability, lastHit = { team = "Away", hitType = "Bump" } }
		for k, v in pairs(extraCtx or {}) do c[k] = v end
		return HitLogic.compute({ action = "Set", t = 0, root = sroot, ball = sball, grounded = true, setType = setType or "Open" }, ctx(c))
	end
	-- Tyrant's Set: flat and fast (a lower top, down through the hitting height sooner)
	local function topAndArrive(path)
		local top, arriveT = -1, nil
		for i = 0, 400 do
			local tt = i * 0.01
			local p, v = BallPhysics.positionAt(path, tt), BallPhysics.velocityAt(path, tt)
			top = math.max(top, p.Y)
			if not arriveT and v.Y < 0 and p.Y <= H.SetArriveY then
				arriveT = tt
			end
		end
		return top, arriveT or 99
	end
	local okP, plain = set(nil)
	local okT, ty = set("Tyrant")
	local okQ, tq = set("Tyrant", nil, "Quick")
	local pTop, pT = topAndArrive(BallPhysics.buildPath(plain.launch))
	local tTop, tT = topAndArrive(BallPhysics.buildPath(ty.launch))
	check(okP and okT and okQ and ty.meta.tyrantSet and tq.meta.tyrantSet and not ty.meta.absolute and math.abs(pTop - tTop - A0Tyrant.SetLower) < 0.3 and tT < pT * 0.85,
		"Tyrant's Set: half a metre under the usual height, flown faster (down through the hitting height sooner); his quicks are his too",
		string.format("top %.1f vs %.1f studs, down at %.2f vs %.2f s", tTop, pTop, tT, pT))
	-- (the usual height, just faster: the owner, "the setter should have normal height but just faster overall")
	-- the spike off it: SetMul faster, Armor Break; Absolute Toss (Dictate on): full power whatever the timing
	local sr = apexRoot(SP, 3.5 * K)
	local tset = { team = "Away", hitType = "Set", tyrantSet = true }
	local aset = { team = "Away", hitType = "Set", tyrantSet = true, absolute = true }
	local pset = { team = "Away", hitType = "Set" }
	local _, base = spike(sr, ballAt(sr, Z.SpikeCenterDz, Z.SpikeCenterDy), { lastHit = pset })
	local _, boosted = spike(sr, ballAt(sr, Z.SpikeCenterDz, Z.SpikeCenterDy), { lastHit = tset })
	local low = sr - vec(0, 2.6, 0)
	local _, sloppy = spike(low, ballAt(low, 1.6, 1.1), { lastHit = pset })
	local _, absolute = spike(low, ballAt(low, 1.6, 1.1), { lastHit = aset })
	local ratio = boosted.meta.kmh / base.meta.kmh
	check(math.abs(ratio - TY.SetMul) < 0.01 and boosted.meta.armorBreak and boosted.meta.tyrant,
		"the spike off his set: 1.3x as fast, with Armor Break", string.format("%.1f -> %.1f km/h (x%.3f)", base.meta.kmh, boosted.meta.kmh, ratio))
	check(absolute.meta.absolute and absolute.meta.kmh > sloppy.meta.kmh * 1.25 and math.abs(absolute.meta.kmh - base.meta.kmh * TY.SetMul) / (base.meta.kmh * TY.SetMul) < 0.08,
		"Absolute Toss: a mistimed spike off his set during Emperor's Dictate hits at full power",
		string.format("mistimed %.1f km/h, with Absolute Toss %.1f (a clean one %.1f)", sloppy.meta.kmh, absolute.meta.kmh, boosted.meta.kmh))
	-- Sovereign Strike: his own attack during the Dictate, at full power, SelfMul faster, Armor Break
	local dr = apexRoot(dohwan, 3.5 * K)
	local dlow = dr - vec(0, 2.6, 0)
	local _, dClean = spike(dr, ballAt(dr, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = dohwan, ability = "Tyrant", lastHit = pset })
	local _, dSloppy = spike(dlow, ballAt(dlow, 1.6, 1.1), { stats = dohwan, ability = "Tyrant", lastHit = pset })
	local _, dDecree = spike(dlow, ballAt(dlow, 1.6, 1.1), { stats = dohwan, ability = "Tyrant", lastHit = pset, tyrantOn = true })
	check(dDecree.meta.decree and dDecree.meta.armorBreak and not dSloppy.meta.decree and dDecree.meta.kmh > dSloppy.meta.kmh * 1.25
		and math.abs(dDecree.meta.kmh - dClean.meta.kmh * TY.SelfMul) / (dClean.meta.kmh * TY.SelfMul) < 0.08,
		"Sovereign Strike: his own mistimed spike during Emperor's Dictate hits at full power, 1.15x, with Armor Break",
		string.format("mistimed %.1f km/h, in the Dictate %.1f (a clean one %.1f)", dSloppy.meta.kmh, dDecree.meta.kmh, dClean.meta.kmh))
	-- Armor Break: an ordinary block never stuffs it (Iron Wall still does)
	local broot = vec(0, GROUND + Characters.jumpHeight(SP, GROUND) * 0.8, side * 1.2)
	local top = broot.Y + Z.BlockReachUp + Config.Ball.Radius
	local palms = vec(0, top - 1.5, side * 0.6)
	local function block(lastHit, extraCtx, ball)
		local c = { ability = nil, stats = SP, lastHit = lastHit, ballVel = vec(0, -8, side * 30) }
		for k, v in pairs(extraCtx or {}) do c[k] = v end
		return HitLogic.compute({ action = "Block", t = 0, root = broot, ball = ball or palms, vy = 0, grounded = false }, ctx(c))
	end
	local stuffedPlain, stuffedArmor, wallArmor = 0, 0, true
	for seq = 1, 40 do
		local okA, rA = block({ team = "Home", hitType = "Spike", kmh = 120 }, { seq = seq, forceQuality = 1 })
		local okB, rB = block({ team = "Home", hitType = "Spike", kmh = 120, armorBreak = true }, { seq = seq, forceQuality = 1 })
		local okC, rC = block({ team = "Home", hitType = "Spike", kmh = 120, armorBreak = true }, { seq = seq, ironWall = true })
		stuffedPlain = stuffedPlain + ((okA and rA.meta.outcome == "Stuff") and 1 or 0)
		stuffedArmor = stuffedArmor + ((okB and rB.meta.outcome == "Stuff") and 1 or 0)
		wallArmor = wallArmor and okC and rC.meta.outcome == "Stuff"
	end
	check(stuffedPlain > 30 and stuffedArmor == 0 and wallArmor, "Armor Break: a clean block stuffs a plain spike, never one off his set (Iron Wall still does)",
		string.format("stuffed %d / 40 plain, %d / 40 armor break", stuffedPlain, stuffedArmor))
	-- Iron Wall's box (Taesan's Bulwark uses it too) reaches down to the floor: a ball low on his side
	-- under the tape is in it, not in an ordinary block's
	local lowBall = vec(0, GROUND + 1.2, side * 0.8)
	check(HitLogic.blockBox(broot, lowBall, side, SP, true) and not HitLogic.blockBox(broot, lowBall, side, SP, nil),
		"Iron Wall reaches below the feet: a ball under the tape on his side is blocked (an ordinary block misses it)")
	-- Iron Fortress: their block reaches half as high over the tape
	local highBall = vec(0, top - 0.4, side * 0.6)
	local okHigh = block({ team = "Home", hitType = "Spike", kmh = 120 }, { seq = 3 }, highBall)
	local okCut = block({ team = "Home", hitType = "Spike", kmh = 120 }, { seq = 3, dictated = true }, highBall)
	check(okHigh and not okCut and HitLogic.blockCut(true) == TY.BlockCut and HitLogic.blockCut(nil) == nil,
		"Iron Fortress: a ball at the top of the hands is blocked, but not with his Emperor's Dictate on against them")
	-- Stat Hijack: his team +12/+10/+10, theirs -15% Attack, Jump, Speed; Sovereign's Guard -10% Jump and Attack
	local mine = HitLogic.effectiveStats(SP, nil, nil, { dictate = true })
	local theirs = HitLogic.effectiveStats(SP, nil, nil, { dictated = true })
	local grounded = HitLogic.effectiveStats(SP, nil, nil, { grounded = true })
	local function near(a, b) return math.abs(a - b) <= 1 end
	check(mine.Attack == SP.Attack + 12 and mine.Jump == SP.Jump + 10 and mine.Speed == SP.Speed + 10 and mine.Defense == SP.Defense
		and near(theirs.Attack, SP.Attack * (1 - TY.Steal * TY.StealAttack)) and near(theirs.Jump, SP.Jump * (1 - TY.Steal)) and near(theirs.Speed, SP.Speed * (1 - TY.Steal)) and theirs.Defense == SP.Defense
		and near(grounded.Attack, SP.Attack * 0.9) and near(grounded.Jump, SP.Jump * 0.9) and grounded.Speed == SP.Speed,
		"Stat Hijack: his team +12 Attack, +10 Jump, +10 Speed; theirs Locked (35% less Jump and Speed, 15% less Attack); Grounded: 10% less Jump and Attack",
		string.format("ATK %d / %d / %d (from %d)", mine.Attack, theirs.Attack, grounded.Attack, SP.Attack))
	-- the Lock slows their spikes too (the owner, 2026-10-25), on top of the Attack it takes
	do
		local lroot = apexRoot(SP, 3.5 * K)
		local lball = ballAt(lroot, Z.SpikeCenterDz, Z.SpikeCenterDy)
		local okA, freeHit = spike(lroot, lball, { seq = 9, forceQuality = 1 })
		local okB, lockedHit = spike(lroot, lball, { seq = 9, forceQuality = 1, dictated = true })
		local okC, statsOnly = spike(lroot, lball, { seq = 9, forceQuality = 1, stats = HitLogic.effectiveStats(SP, nil, nil, { dictated = true }) })
		check(okA and okB and okC and lockedHit.meta.lockCut and math.abs(lockedHit.meta.kmh - statsOnly.meta.kmh * (1 - TY.LockSpikeCut)) < 0.5 and lockedHit.meta.kmh < freeHit.meta.kmh * 0.8,
			"Emperor's Dictate: the Locked team's spikes are LockSpikeCut slower, on top of the Attack it takes",
			string.format("%.0f km/h free, %.0f with the Attack cut, %.0f Locked", freeHit.meta.kmh, statsOnly.meta.kmh, lockedHit.meta.kmh))
	end
	-- Crown Jump Serve: steeper (more topspin), double drain, a low and wild pass and set
	local sv = vec(0, GROUND + 6.5, side * (C.SideDepth + 1))
	local svBall = ballAt(sv, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local function serve(ability)
		return HitLogic.compute({ action = "Serve", t = 0, root = sv, ball = svBall, vy = 0, grounded = false },
			ctx({ ability = ability, stats = dohwan, touchNumber = 1, lastHit = { team = "Away", hitType = "Toss", id = "x" } }))
	end
	local okS1, plainServe = serve(nil)
	local okS2, crown = serve("Tyrant")
	check(okS1 and okS2 and crown.meta.crown and crown.launch.a.Y < plainServe.launch.a.Y * 1.3,
		"Crown Jump Serve: heavy topspin, it curls down steeply",
		string.format("gravity %.0f vs %.0f", -crown.launch.a.Y, -plainServe.launch.a.Y))
	-- and as hard as the best S+ wing spiker's serve (maxed), only the serve: his spike keeps his own Attack
	local topWS = 0
	for _, c in ipairs(Roster) do
		if c.Tier == "S+" and c.Role == "WS" then
			topWS = math.max(topWS, c.Attack)
		end
	end
	local best = Characters.boosted(dohwan, { Attack = topWS - dohwan.Attack })
	local okS3, bestServe = HitLogic.compute({ action = "Serve", t = 0, root = sv, ball = svBall, vy = 0, grounded = false },
		ctx({ ability = nil, stats = best, touchNumber = 1, lastHit = { team = "Away", hitType = "Toss", id = "x" } }))
	check(okS3 and Roster.get("dohwan").Attack + TY.CrownServeAttack == topWS and math.abs(crown.meta.kmh - bestServe.meta.kmh) < 0.5 and crown.meta.kmh > plainServe.meta.kmh * 1.1 and dohwan.Attack >= 165,
		"Crown Jump Serve: as hard as the best S+ wing spiker's serve (maxed); his own Attack is solid too",
		string.format("%.0f km/h (plain %.0f, top WS stats %.0f); top S+ WS Attack %d, his %d", crown.meta.kmh, plainServe.meta.kmh, bestServe.meta.kmh, topWS, dohwan.Attack))
	local rroot = vec(0, GROUND, side * 18 * K)
	local rball = vec(0, rroot.Y + Z.ReceiveIdealY, rroot.Z - side * Z.ReceiveForward)
	local function recv(last)
		return HitLogic.compute({ action = "Bump", t = 0, root = rroot, ball = rball, vy = 0, grounded = true, stanceAge = 0.5 },
			ctx({ ballVel = vec(0, -20 * K, side * 90 * K), lastHit = last, touchNumber = 1, stamina = { value = 200, max = 200 }, stats = Characters.stats("S+", "SE") }))
	end
	local _, r1 = recv({ team = "Home", hitType = "JumpServe", kmh = 110 })
	local _, r2 = recv({ team = "Home", hitType = "JumpServe", kmh = 110, crown = true })
	check(r2.meta.crowned and math.abs(r2.meta.drain / r1.meta.drain - TY.CrownDrainMul) < 0.01 and r2.meta.quality < r1.meta.quality,
		"Crown Jump Serve: double stamina on the receiver, a worse pass",
		string.format("drain %.1f vs %.1f, pass %.2f vs %.2f", r2.meta.drain, r1.meta.drain, r2.meta.quality, r1.meta.quality))
	local function setOff(pass, seq)
		local c = { touchNumber = 2, stats = dohwan, lastHit = pass, seq = seq }
		return HitLogic.compute({ action = "Set", t = 0, root = sroot, ball = sball, grounded = true, setType = "Open" }, ctx(c))
	end
	local spreadP, spreadC, lower = 0, 0, true
	for seq = 1, 30 do
		local _, a = setOff({ team = "Away", hitType = "Bump" }, seq)
		local _, b = setOff({ team = "Away", hitType = "Bump", crowned = true }, seq)
		local pa, pb = BallPhysics.buildPath(a.launch), BallPhysics.buildPath(b.launch)
		spreadP = spreadP + math.abs(pa.landing.pos.Z - side * Court.attackDepth("Open"))
		spreadC = spreadC + math.abs(pb.landing.pos.Z - side * Court.attackDepth("Open"))
		local ta = topAndArrive(pa)
		local tb = topAndArrive(pb)
		lower = lower and tb < ta and b.meta.crowned
	end
	check(spreadC > spreadP * 1.4 and lower, "the set off a Crown-wrecked pass comes down lower and strays further",
		string.format("average miss %.1f vs %.1f studs", spreadC / 30, spreadP / 30))
	check(require("Bios").dohwan ~= nil and Roster.get("dohwan").Tier == "S+" and Roster.get("dohwan").Role == "SE" and TY.Cooldown == 24 and TY.Duration == 5, "Dohwan: S+ setter, Emperor's Dictate 5 s on a 24 s cooldown")
end

print("== Sunshine (Haesol) ==")
do
	local SU = Config.Abilities.Sunshine
	local haesol = Characters.derive(Characters.fromRoster(Roster.get("haesol"), "max"))
	local rroot = vec(0, GROUND, side * 18 * K)
	local function dig(ability, stanceAge, ball, extraCtx)
		local c = { ballVel = vec(0, -30 * K, side * 110 * K), lastHit = { team = "Home", hitType = "Spike", kmh = 140 }, touchNumber = 1,
			stamina = { value = 200, max = 200 }, stats = haesol, ability = ability }
		for k, v in pairs(extraCtx or {}) do c[k] = v end
		return HitLogic.compute({ action = "Bump", t = 0, root = rroot, ball = ball or vec(0, rroot.Y + Z.ReceiveIdealY, rroot.Z - side * Z.ReceiveForward), vy = 0, grounded = true, stanceAge = stanceAge }, ctx(c))
	end
	-- a far wider perfect window, and a perfect dig lights Sunshine
	local _, early = dig(nil, 0.9)
	local _, hers = dig("Sunshine", 0.9)
	check(not early.meta.perfect and hers.meta.perfect and hers.meta.sunshine and hers.meta.dig, "Sunshine: a dig pressed 0.9 s early is perfect for her (not for anyone else) and lights Sunshine",
		string.format("anyone %.2f, her %.2f", early.meta.quality, hers.meta.quality))
	-- her digs reach 33% wider
	local wide = vec(0, rroot.Y + Z.ReceiveIdealY, rroot.Z - side * (Z.ReceiveForward + Z.ReceiveReach * haesol.Reach * 1.2 + 0.3))
	local okPlain = dig(nil, 0.2, wide)
	local okHers = dig("Sunshine", 0.2, wide)
	check(not okPlain and okHers, "her digs reach 33% wider than anyone's with her height")
	-- her dig is played with +70 Defense and +18 Speed; lit, every stat +10
	local digStats = HitLogic.effectiveStats(haesol, "Sunshine", nil, { digging = true })
	local lit = HitLogic.effectiveStats(haesol, "Sunshine", nil, { sunOn = true })
	check(digStats.Defense == math.min(Config.Stats.Max, haesol.Defense + 70) and digStats.Speed == haesol.Speed + 18
		and lit.Attack == haesol.Attack + 10 and lit.Jump == haesol.Jump + 10 and lit.Defense == math.min(Config.Stats.Max, haesol.Defense + 10) and lit.Speed == haesol.Speed + 10,
		"her dig: +70 Defense, +18 Speed; Sunshine lit: +10 to every stat")
	-- lit, a bigger block box
	local broot = vec(0, GROUND + 2.4, side * 0.9)
	local over = vec(0, broot.Y + Z.BlockReachUp + 0.9, side * 0.2)
	local function block(sunOn)
		return HitLogic.compute({ action = "Block", t = 0, root = broot, ball = over, vy = 0, grounded = false },
			ctx({ ability = "Sunshine", stats = haesol, sunOn = sunOn, lastHit = { team = "Home", hitType = "Spike", kmh = 120 }, ballVel = vec(0, -8, side * 30) }))
	end
	check(not block(nil) and block(true), "Sunshine lit: her block reaches higher")
	-- Vert Spikes: shorter and steeper, harder the steeper, the steepest under the block
	local sr = apexRoot(haesol, 1.6 * K)
	local _, plainS = spike(sr, ballAt(sr, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = haesol })
	local _, vert = spike(sr, ballAt(sr, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = haesol, ability = "Sunshine" })
	local pP, pV = BallPhysics.buildPath(plainS.launch), BallPhysics.buildPath(vert.launch)
	-- how steeply each comes down where it lands (degrees below level)
	local function landAngle(path)
		local L = path.landing
		local v = BallPhysics.velocityAt(path, L.t - 0.001)
		return math.deg(math.atan(-v.Y / math.max(math.abs(v.Z), 1e-3)))
	end
	local aP, aV = landAngle(pP), landAngle(pV)
	check(aV > aP + 15 and aV > 45, "Vert Spikes: her spike dives, coming down far steeper than a usual one", string.format("%.0f vs %.0f degrees at the floor", aV, aP))
	check(vert.meta.vert and vert.meta.vert > 0 and oppDepth(pV) < oppDepth(pP) and vert.meta.kmh > plainS.meta.kmh and Court.inBounds(pV.landing.pos) and not pV.flags.netTouch,
		"Vert Spikes: her spike lands shorter and harder, and in", string.format("%.1f vs %.1f studs deep, %.1f vs %.1f km/h (+%.1f%%)", oppDepth(pV), oppDepth(pP), vert.meta.kmh, plainS.meta.kmh, vert.meta.vert * 100))
	local unders, total = 0, 0
	for i = 0, 8 do
		local r = apexRoot(haesol, (0.5 + i * 0.5) * SPM)
		local okV, rv = spike(r, ballAt(r, Z.SpikeCenterDz, Z.SpikeCenterDy), { stats = haesol, ability = "Sunshine", seq = 10 + i })
		if okV then
			total = total + 1
			unders = unders + (rv.meta.underBlock and 1 or 0)
		end
	end
	local broot2 = vec(0, GROUND + Characters.jumpHeight(SP, GROUND) * 0.8, side * 1.2)
	local bpalms = vec(0, broot2.Y + Z.BlockReachUp + Config.Ball.Radius - 1.5, side * 0.6)
	local function blockIt(last, extraCtx)
		local c = { stats = SP, lastHit = last, ballVel = vec(0, -8, side * 30), seq = 5 }
		for k, v in pairs(extraCtx or {}) do c[k] = v end
		return HitLogic.compute({ action = "Block", t = 0, root = broot2, ball = bpalms, vy = 0, grounded = false }, ctx(c))
	end
	local okU, why = blockIt({ team = "Home", hitType = "Spike", kmh = 130, underBlock = true })
	local okW, rW = blockIt({ team = "Home", hitType = "Spike", kmh = 130, underBlock = true }, { ironWall = true })
	check(unders > 0 and unders < total and not okU and why == "under" and okW and rW.meta.outcome == "Stuff",
		"Vert Spikes: her steepest spikes (close to the net) slip under the block; Iron Wall still stops them",
		string.format("%d of %d spikes from 0.5 to 4.5 m off the net go under", unders, total))
	check(require("Bios").haesol ~= nil and Roster.get("haesol").Tier == "S" and Roster.get("haesol").Role == "MB" and SU.PerfectStance[2] > H.PerfectStanceMax, "Haesol: S middle blocker")
end

print("== ranked leaderboard ==")
do
	local Leaderboards = require("Leaderboards")
	local Ranked = require("Ranked")
	local now = os.time()
	local season = Ranked.season(now)
	local cur = Leaderboards.valuesOf({ ranked = { season = season, rp = 1234 } }).ranked
	local old = Leaderboards.valuesOf({ ranked = { season = season - 1, rp = 1900 } }).ranked
	local board = Leaderboards.board("ranked")
	check(cur == 1234 and old == 0 and Leaderboards.format("ranked", 133) == "Bronze 2  33 RP" and Leaderboards.format("ranked", Config.Ranked.MightyAt + 120) == "Mighty  120 RP" and board.Live and Leaderboards.storeName(board, now) == Config.Leaderboards.StorePrefix .. "ranked_s" .. season and Leaderboards.storeName(Leaderboards.board("wins"), now) == Config.Leaderboards.StorePrefix .. "wins",
		"the ranked board ranks this season's RP (an old season's counts as nothing), shows the division and the RP into it, and keeps a store per season", Leaderboards.format("ranked", 133))
end

print("== AFK Lounge ==")
do
	local Lounge = require("Lounge")
	local LC = Config.Lounge
	local bottom = function() return 0 end -- (the first reward: 30 Gold)
	local topRoll = function() return 0.99999 end -- (the last: the top reward)
	local total = 0
	for _, r in ipairs(LC.Rewards) do
		total = total + r.Weight
	end
	check(#LC.Rewards >= 15 and math.abs(total - 100) < 1e-6 and LC.Rewards[#LC.Rewards].Grant.Lucky == 1 and LC.Rewards[1].Grant.Gold == 30 and LC.Rewards[2].Grant.VP == 10,
		"lounge: at least 15 rewards, weights in percent adding to 100, a lucky spin on top and 30 Gold or 10 VP at the bottom", #LC.Rewards .. " rewards, " .. total)
	local counts, n = {}, 20000
	local seed = 12345
	for _ = 1, n do
		seed = (seed * 1103515245 + 12345) % 2147483648
		local i = Lounge.pick(seed / 2147483648)
		counts[i] = (counts[i] or 0) + 1
	end
	check(math.abs((counts[1] or 0) / n - Lounge.chance(1)) < 0.02 and Lounge.pick(0) == 1 and Lounge.pick(0.99999) == #LC.Rewards, "lounge: a roll lands on each reward about as often as its weight says")
	local g2 = Lounge.grant(1, Lounge.mult(true, true))
	local gl = Lounge.grant(#LC.Rewards, Lounge.mult(true, true))
	check(g2.Gold == math.floor(30 * LC.VipMult * LC.PremiumMult + 0.5) and gl.Lucky == 1 and Lounge.label(gl) == "LUCKY SPIN" and Lounge.label(Lounge.grant(2, 1)) == "+10 VP",
		"lounge: VIP and Premium multiply a reward's Gold and V Points, not a lucky spin", Lounge.label(g2))
	local rec = Lounge.clean(nil, 100)
	local r1 = Lounge.advance(rec, LC.Interval - 1, 1, bottom)
	local r2, s2 = Lounge.advance(rec, 1, 1, bottom)
	check(#r1 == 0 and #r2 == 1 and s2.Gold == 30 and rec.carry == 0 and rec.payouts == 1 and rec.made.Gold == 30 and rec.made.n == 1 and rec.log[1].i == 1, "lounge: one rolled reward per full interval inside, counted in the stay's totals")
	local r3, s3 = Lounge.advance(rec, LC.Interval * 2.5, 1, topRoll)
	check(#r3 == 2 and s3.Lucky == 2 and rec.made.Lucky == 2 and rec.made.n == 3 and rec.log[1].i == #LC.Rewards and rec.gold == 30 and math.abs(rec.carry - LC.Interval * 0.5) < 1e-6,
		"lounge: a long step rolls each interval it covers, adds them up and keeps the remainder")
	local kept = Lounge.clean({ day = 100, payouts = 3, gold = 900, carry = 100, made = { Gold = 90, VP = 10, n = 3 }, log = { { i = 1, m = 1 }, { i = 99, m = 1 } } }, 100)
	local turned = Lounge.clean({ day = 99, payouts = 60, gold = 7200, carry = 100, made = { Gold = 40, n = 1 } }, 100)
	check(kept.payouts == 3 and kept.gold == 900 and kept.carry == 100 and kept.made.Gold == 90 and kept.made.VP == 10 and #kept.log == 1 and turned.payouts == 0 and turned.gold == 0 and turned.carry == 100 and turned.made.Gold == 40,
		"lounge: the time towards the next payout and the stay's totals carry over (a bad log entry is dropped); a new day starts the payouts again")
	Lounge.startStay(kept)
	check(kept.made.Gold == 0 and kept.made.n == 0 and #kept.log == 0 and kept.carry == 0, "lounge: stepping in again starts a new stay, its timer from zero")
	if LC.DailyPayouts then
		local full = Lounge.clean({ day = 100, payouts = LC.DailyPayouts - 1, carry = 0 }, 100)
		local rF = Lounge.advance(full, LC.Interval * 5, 1, bottom)
		local rAfter = Lounge.advance(full, LC.Interval * 5, 1, bottom)
		check(#rF == 1 and #rAfter == 0 and full.carry == 0 and Lounge.nextIn(full) == nil, "lounge: nothing past the daily limit")
	else
		local many = Lounge.clean({ day = 100, payouts = 500, carry = 0 }, 100)
		local rM = Lounge.advance(many, LC.Interval * 5, 1, bottom)
		check(#rM == 5 and many.payouts == 505 and Lounge.nextIn(many) == LC.Interval, "lounge: no daily limit, the rewards keep coming")
	end
	local bad = Lounge.clean({ day = 100, payouts = -5, carry = 1e9 }, 100)
	check(bad.payouts == 0 and bad.carry == LC.Interval - 1, "lounge: a bad stored record is clamped")
end

print("== deep tip ==")
do
	local root = apexRoot(SP, 3.5 * K)
	local b = ballAt(root, Z.SpikeCenterDz, Z.SpikeCenterDy)
	local function tipDepth(deep)
		local ok, r = HitLogic.compute({ action = "Feint", t = 0, root = root, ball = b, vy = 0, grounded = false, tipDepth = deep }, ctx({ seq = 7, forceQuality = 1 }))
		return ok and oppDepth(BallPhysics.buildPath(r.launch)) or -1
	end
	local short, half, full = tipDepth(nil), tipDepth(0.5), tipDepth(1)
	check(short > 0 and short < Config.Hits.FeintMaxDepth + 1.5 * K and half > short + 2 * K and full > half and math.abs(full - Config.Hits.FeintDeepDepth) < 1.5 * K,
		"deep tip: a tap tips short, holding the tip button pushes it to the back of the court",
		string.format("%.1f / %.1f / %.1f m from the net", short / SPM, half / SPM, full / SPM))
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
