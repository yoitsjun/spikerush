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
	local want = { WS = "Adrenaline", MB = "IronWall", SE = "ChainReaction" }
	for _, c in ipairs(Roster) do
		okLimits = okLimits and not ids[c.Id] and Characters.isTier(c.Tier) and Config.RoleTemplates[c.Role] ~= nil
		ids[c.Id] = true
		for _, k in ipairs(Config.Stats.Order) do
			okLimits = okLimits and c[k] >= Config.Stats.Min and c[k] <= Config.Stats.Max
		end
		if c.Tier == "S+" then
			okAbility = okAbility and c.Role == "WS" and (c.Ability == "Thunder" or c.Ability == "Azure")
		elseif c.Tier == "S" then
			okAbility = okAbility and c.Ability == want[c.Role]
		else
			okAbility = okAbility and c.Ability == nil
		end
		if c.Role == "WS" then
			okShape = okShape and c.Attack <= 210 and c.Jump <= 190 and c.Attack > c.Defense
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
	check(okAbility, "abilities: S+ wing spikers have Thunder or Azure, S characters their role's ability, the rest none")
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
	-- the teleport round trip
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
end

print("== tutorial ==")
do
	local Tutorial = require("Tutorial")
	local done = {}
	local nextStep, n, total = Tutorial.progress(done)
	check(nextStep.id == "serve" and n == 0 and total == 7 and not Tutorial.complete(done), "the tutorial starts at the serve with 7 steps")
	for _, hit in ipairs({ "Underhand", "Bump", "Set", "Spike", "Block" }) do
		for _, id in ipairs(Tutorial.stepsFor(hit)) do done[id] = true end
	end
	local after = Tutorial.progress(done)
	for _, id in ipairs(Tutorial.stepsFor("JumpServe")) do done[id] = true end
	local beforePoint = Tutorial.complete(done)
	done.point = true
	local vp, gold, spins = Tutorial.reward()
	check(after.id == "jumpserve" and not beforePoint and Tutorial.complete(done) and #Tutorial.stepsFor("Feint") == 0 and vp == 50 and gold == 1000 and spins == 5, "touches tick their steps, a won rally finishes it; the reward is 50 VP, 1,000 Gold and 5 free recruits")
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
	check(Rewards.winner({ "Home", "Away", "Home" }, { Home = 40, Away = 44 }) == "Home" and Rewards.winner({ "Home", "Away" }, { Home = 30, Away = 32 }) == "Away" and Rewards.winner({ "Away", "Home" }, { Home = 30, Away = 30 }) == "Home",
		"the match winner: most sets, then most points, then the last set")
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
