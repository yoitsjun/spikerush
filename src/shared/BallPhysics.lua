-- Deterministic ball physics.
--
-- The ball is never a physics-engine part. Every hit produces a "launch" (position, velocity,
-- constant acceleration, optional float-serve wobble, optional hit-stop). BallPhysics.buildPath
-- turns that launch into a piecewise trajectory: net-cord pops, balls dropping out of the net,
-- antenna/under-net faults and the exact touchdown time and point are all resolved up front.
--
-- The server broadcasts the finished path; every client evaluates it against the shared server
-- clock, so all players see exactly the same ball with zero network jitter. The hitter's own
-- client builds the same path locally the instant they hit (prediction), so their hits feel
-- instant even on a high ping.

local Config = require(script.Parent.Config)

local BallPhysics = {}

local C = Config.Court
local R = Config.Ball.Radius
local STEP = 1 / 120
local SPM = Config.Scale.StudsPerMeter

-- Air drag (the owner, 2026-10-28: "make it more like a realistic volleyball game physics"): a
-- flying ball loses speed in proportion to its speed, Config.Ball.Drag per second (linear drag, so
-- a segment stays exact: p(t) = p + (a/k)t + (v - a/k)(1 - e^(-kt))/k). A launch is re-aimed for
-- it (`dragged`): the drag-free launch's landing point and time are kept, so every aim, landing
-- marker and bot plan still holds; only the flight between changes: off the hand faster, slowing
-- toward the end, falling steeper than it rose.
local function dragged(s)
	local k = s.k or 0
	if k <= 0 or s.a.Y >= 0 then
		return s
	end
	local g = -s.a.Y
	local h = s.p.Y - R
	if h < 0 then
		return s
	end
	-- when the drag-free flight would reach the floor
	local T = (s.v.Y + math.sqrt(s.v.Y * s.v.Y + 2 * g * h)) / g
	if T <= 0.02 or T > Config.Ball.MaxFlightTime then
		return s
	end
	local target = s.p + s.v * T + s.a * (0.5 * T * T)
	local f = (1 - math.exp(-k * T)) / k
	local term = s.a / k
	s.v = term + (target - s.p - term * T) / f
	return s
end

-- `drag`: nil for the usual air drag (and the launch re-aimed for it), or { k = per second, raw =
-- true } for a flight already worked out with drag (a retimed path: Updraft). Sets and tosses fly
-- without it (BallPhysics.NO_DRAG): they're aimed at a point mid-flight (a hitter's hand, the
-- server's contact), which a re-aim for the floor would move; soft and short, a real one barely
-- feels it anyway.
BallPhysics.NO_DRAG = { k = 0, raw = true }
function BallPhysics.newLaunch(p, v, a, t0, hold, wob, wobF, drag)
	local s = {
		p = p,
		v = v,
		a = a,
		t0 = t0,
		hold = hold or 0, -- hit-stop: the ball waits on the hand this long before flying
		wob = wob or 0, -- float serve lateral wobble amplitude
		wobF = wobF or 0,
		ph = 0,
		k = (type(drag) == "table" and drag.k) or Config.Ball.Drag or 0,
	}
	if type(drag) == "table" and drag.raw then
		return s
	end
	return dragged(s)
end

local function posAt(s, tau)
	local k = s.k or 0
	local x, y, z
	if k > 0 then
		local e = (1 - math.exp(-k * tau)) / k
		local ax, ay, az = s.a.X / k, s.a.Y / k, s.a.Z / k
		x = s.p.X + ax * tau + (s.v.X - ax) * e
		y = s.p.Y + ay * tau + (s.v.Y - ay) * e
		z = s.p.Z + az * tau + (s.v.Z - az) * e
	else
		x = s.p.X + s.v.X * tau + 0.5 * s.a.X * tau * tau
		y = s.p.Y + s.v.Y * tau + 0.5 * s.a.Y * tau * tau
		z = s.p.Z + s.v.Z * tau + 0.5 * s.a.Z * tau * tau
	end
	if s.wob ~= 0 then
		x = x + s.wob * (math.sin(s.wobF * tau + s.ph) - math.sin(s.ph))
	end
	return Vector3.new(x, y, z)
end

local function baseVelAt(s, tau)
	local k = s.k or 0
	if k > 0 then
		local e = math.exp(-k * tau)
		local term = s.a / k
		return term + (s.v - term) * e
	end
	return Vector3.new(s.v.X + s.a.X * tau, s.v.Y + s.a.Y * tau, s.v.Z + s.a.Z * tau)
end

local function velAt(s, tau)
	local v = baseVelAt(s, tau)
	if s.wob ~= 0 then
		v = v + Vector3.new(s.wob * s.wobF * math.cos(s.wobF * tau + s.ph), 0, 0)
	end
	return v
end

local function refine(s, lo, hi, test)
	for _ = 1, 22 do
		local mid = (lo + hi) * 0.5
		if test(posAt(s, mid)) then
			hi = mid
		else
			lo = mid
		end
	end
	return hi
end

-- Walk one segment until something interesting happens. Clean net crossings are recorded in
-- `flags` and do not end the segment. A segment with a turn (s.dive: Plunge Spin) ends there.
local function scan(s, flags)
	local prev = posAt(s, 0)
	local tau = 0
	local maxT = Config.Ball.MaxFlightTime
	local turnAt = s.dive and s.dive.tau or nil
	while tau < maxT do
		local nt = tau + STEP
		if turnAt and nt > turnAt then
			nt = turnAt
		end
		local pos = posAt(s, nt)
		if pos.Y <= R then
			return "Floor", refine(s, tau, nt, function(p)
				return p.Y <= R
			end)
		end
		if pos.Y >= C.CeilingY - R then
			return "Ceiling", refine(s, tau, nt, function(p)
				return p.Y >= C.CeilingY - R
			end)
		end
		if math.abs(pos.X) >= C.WallHalfX - R or math.abs(pos.Z) >= C.WallHalfZ - R then
			return "Wall", refine(s, tau, nt, function(p)
				return math.abs(p.X) >= C.WallHalfX - R or math.abs(p.Z) >= C.WallHalfZ - R
			end)
		end
		if (prev.Z > 0 and pos.Z <= 0) or (prev.Z < 0 and pos.Z >= 0) then
			local from = 1
			if prev.Z < 0 then
				from = -1
			end
			local tc = refine(s, tau, nt, function(p)
				return p.Z * from <= 0
			end)
			local cp = posAt(s, tc)
			local ax = math.abs(cp.X)
			if ax <= C.NetHalfWidth and cp.Y < C.NetTop + R and cp.Y > C.NetBottom - R then
				return "Net", tc, from
			end
			if ax > C.HalfWidth then
				flags.outsideAntenna = true
			end
			if cp.Y <= C.NetBottom - R and ax <= C.NetHalfWidth then
				flags.underNet = true
				-- when it went under: dead from then on, nobody can touch it on the far side (HitService;
				-- the owner, 2026-10-25: a dig or block there was scoring a down tilt under the net)
				flags.underNetT = flags.underNetT or (s.t0 + (s.hold or 0) + tc)
			end
			flags.crossings = (flags.crossings or 0) + 1
		end
		if turnAt and nt >= turnAt then
			return "Dive", turnAt
		end
		prev = pos
		tau = nt
	end
	return "Timeout", maxT
end

function BallPhysics.buildPath(launch)
	local segs, flags, netEvents = {}, {}, {}
	local s = launch
	local landing = nil
	for _ = 1, 8 do
		table.insert(segs, s)
		local kind, tau, from = scan(s, flags)
		local pos = posAt(s, tau)
		local vel = velAt(s, tau)
		local absT = s.t0 + s.hold + tau
		if kind == "Dive" then
			-- the turn: on from here with the new velocity and pull
			flags.dive = absT
			s = dragged({ p = pos, v = s.dive.v, a = s.dive.a, t0 = absT, hold = 0, wob = 0, wobF = 0, ph = 0, k = s.k })
		elseif kind == "Net" then
			flags.netTouch = true
			local ns
			if pos.Y >= C.NetTop - R * 0.35 then
				-- Tape contact: the classic net-cord. Over the top it trickles across, below it falls back.
				local nv
				if pos.Y >= C.NetTop then
					nv = Vector3.new(vel.X * 0.55, math.abs(vel.Y) * 0.22 + 2.0 * SPM, vel.Z * 0.45)
					flags.crossings = (flags.crossings or 0) + 1
				else
					nv = Vector3.new(vel.X * 0.5, 1.56 * SPM, -vel.Z * 0.16)
				end
				ns = {
					p = Vector3.new(pos.X, pos.Y, 0),
					v = nv,
					a = Vector3.new(0, s.a.Y, 0),
					t0 = absT,
					hold = 0,
					wob = 0,
					wobF = 0,
					ph = 0,
					k = s.k,
				}
				table.insert(netEvents, { t = absT, pos = pos, kind = "Cord" })
			else
				-- Mesh contact: the net swallows the energy and the ball drops on the hitter's side.
				local tt = refine(s, 0, tau, function(p)
					return p.Z * from <= R
				end)
				local hp = posAt(s, tt)
				local hv = velAt(s, tt)
				absT = s.t0 + s.hold + tt
				ns = {
					p = hp,
					v = Vector3.new(hv.X * 0.35, math.min(hv.Y, 0) * 0.25 - 0.95 * SPM, -hv.Z * 0.18),
					a = Vector3.new(0, s.a.Y, 0),
					t0 = absT,
					hold = 0,
					wob = 0,
					wobF = 0,
					ph = 0,
					k = s.k,
				}
				table.insert(netEvents, { t = absT, pos = hp, kind = "Mesh" })
			end
			s = ns
		else
			landing = { t = absT, pos = pos, vel = vel, kind = kind }
			if kind == "Timeout" then
				landing.kind = "Floor"
			end
			break
		end
	end
	if not landing then
		local last = segs[#segs]
		landing = { t = last.t0 + last.hold + 0.1, pos = last.p, vel = last.v, kind = "Floor" }
	end
	return { segs = segs, landing = landing, flags = flags, netEvents = netEvents }
end

function BallPhysics.segmentAt(path, t)
	local segs = path.segs
	for i = #segs, 2, -1 do
		if t >= segs[i].t0 then
			return segs[i]
		end
	end
	return segs[1]
end

-- Returns position, landed
function BallPhysics.positionAt(path, t)
	local L = path.landing
	if t >= L.t then
		return L.pos, true
	end
	local s = BallPhysics.segmentAt(path, t)
	local tau = t - s.t0 - s.hold
	if tau <= 0 then
		return s.p, false
	end
	return posAt(s, tau), false
end

function BallPhysics.velocityAt(path, t)
	local L = path.landing
	if t >= L.t then
		return L.vel
	end
	local s = BallPhysics.segmentAt(path, t)
	local tau = t - s.t0 - s.hold
	if tau <= 0 then
		return velAt(s, 0)
	end
	return velAt(s, tau)
end

function BallPhysics.startTime(path)
	return path.segs[1].t0
end

-- How far behind real time someone else's hit is shown `age` seconds after we heard of it `lag`
-- seconds late (Config.Ball.CatchUp): the whole lag at first (the ball at the hit), easing to 0
-- (caught up). nil when there's nothing to catch up (too small, or too large: it just jumps).
function BallPhysics.catchUp(lag, age)
	local CU = Config.Ball.CatchUp
	if type(lag) ~= "number" or lag < CU.LagMin or lag > CU.LagMax then
		return nil
	end
	local dur = math.clamp(lag * CU.Stretch, CU.Time[1], CU.Time[2])
	local a = math.max(age, 0) / dur
	if a >= 1 then
		return nil
	end
	return lag * (1 - a * a * (3 - 2 * a))
end

-- First sample (60 Hz) from `fromT` where predicate(pos, vel, t) is true. Used by bots and UI.
function BallPhysics.findTime(path, fromT, predicate)
	local endT = path.landing.t
	local t = math.max(fromT, path.segs[1].t0)
	while t <= endT do
		local p = BallPhysics.positionAt(path, t)
		local v = BallPhysics.velocityAt(path, t)
		if predicate(p, v, t) then
			return t, p
		end
		t = t + 1 / 60
	end
	return nil, nil
end

-- Highest point still ahead of `fromT`.
function BallPhysics.findApex(path, fromT)
	local bestT, bestP = nil, nil
	local t = math.max(fromT, path.segs[1].t0)
	local endT = path.landing.t
	while t <= endT do
		local p = BallPhysics.positionAt(path, t)
		if not bestP or p.Y > bestP.Y then
			bestT, bestP = t, p
		end
		t = t + 1 / 60
	end
	return bestT, bestP
end

return BallPhysics
