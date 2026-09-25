-- Court geometry and formations for the 2.5D game.
-- Gameplay is two-dimensional along the court's long axis (z) and height (y). A team's "side"
-- is -1 (z < 0, left of screen) or +1 (z > 0, right). "Toward the net" is (0, 0, -side).
-- Positions are usually described by depth: distance from the net on your own side.

local Config = require(script.Parent.Config)

local Court = {}

local C = Config.Court
local R = Config.Ball.Radius

-- Points needed to win the set right now. The set is played to `base`, but once both teams
-- reach base - 1 it's deuce: you must win by Match.WinBy, so the target rises with every tie
-- (14-14 plays to 16, 15-15 to 17, ...). Match.PointCap ends it on a golden point.
-- Returns the target and whether it's deuce.
function Court.playTo(a, b, base)
	local M = Config.Match
	local lo = math.min(a, b)
	local target = base
	local deuce = false
	if lo >= base - M.WinBy + 1 then
		target = math.max(base, lo + M.WinBy)
		deuce = true
	end
	if target > M.PointCap then
		target = M.PointCap
	end
	return target, deuce
end

function Court.sideOf(team)
	local t = Config.Teams[team]
	return t and t.Side or 1
end

function Court.other(team)
	if team == "Home" then
		return "Away"
	end
	return "Home"
end

function Court.teamOnSide(side)
	if side < 0 then
		return "Home"
	end
	return "Away"
end

function Court.sideOfPoint(p)
	if p.Z < 0 then
		return -1
	end
	return 1
end

function Court.towardNet(side)
	return Vector3.new(0, 0, -side)
end

-- Distance from the net on a given side (negative if the point is on the other side).
function Court.depthOf(p, side)
	return p.Z * side
end

-- A ball touching the end line is in. Sidelines don't exist in a side-view game.
function Court.inBounds(p)
	return math.abs(p.Z) <= C.SideDepth + R * 0.6
end

function Court.outMargin(p)
	return math.max(math.abs(p.Z) - C.SideDepth, 0)
end

function Court.facing(pos, side)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, -side))
end

function Court.lane(role)
	return Config.Lanes[role or "Solo"] or 0
end

-- A floor point at `depth` from the net on `side`, on a role's lane.
function Court.spot(side, depth, role)
	return Vector3.new(Court.lane(role), 0, side * depth)
end

function Court.attackDepth(setType)
	local H = Config.Hits
	if setType == "Quick" then
		return H.QuickDepth
	elseif setType == "Back" then
		return H.BackDepth
	end
	return H.OpenDepth
end

-- Where each role stands, by situation. Returns depth from the net.
local FORMATION = {
	Receive = { WS = 0.66, MB = 0.42, SE = 0.16, Solo = 0.55 },
	Serving = { WS = 0.6, MB = 0.36, SE = 0.16, Solo = 0.5 },
	Defense = { WS = 0.64, MB = 0.07, SE = 0.34, Solo = 0.5 },
	Offense = { WS = 0.5, MB = 0.3, SE = 0.12, Solo = 0.4 },
}

function Court.formationDepth(kind, role)
	local f = FORMATION[kind] or FORMATION.Receive
	return C.SideDepth * (f[role] or f.Solo)
end

function Court.formationSpot(kind, role, side)
	return Court.spot(side, Court.formationDepth(kind, role), role)
end

function Court.serveSpot(side, role)
	return Court.spot(side, C.SideDepth + 1.1 * Config.Scale.StudsPerMeter, role)
end

-- Stands: the camera sits on the open near side (x < 0), so seating is on the far side (the
-- backdrop behind the play) and at both ends.
Court.Stands = {
	Rows = 11,
	RowDepth = 2.4,
	RowRise = 1.6,
	BaseTop = 1.4,
	FarStart = C.HalfWidth + C.FreeZoneSide + 6,
	FarLength = 2 * (C.SideDepth + C.FreeZoneEnd) + 24,
	EndRows = 8,
	EndStart = C.SideDepth + C.FreeZoneEnd + 6,
	EndLength = 2 * (C.HalfWidth + C.FreeZoneSide) + 10,
}

function Court.standRows()
	local S = Court.Stands
	local rows = {}
	for i = 0, S.Rows - 1 do
		local top = S.BaseTop + i * S.RowRise
		table.insert(rows, {
			axis = "X",
			sign = 1,
			index = i,
			top = top,
			depth = S.RowDepth,
			length = S.FarLength,
			center = Vector3.new(S.FarStart + i * S.RowDepth + S.RowDepth / 2, top, 0),
		})
	end
	for i = 0, S.EndRows - 1 do
		local top = S.BaseTop + i * S.RowRise
		for _, sz in ipairs({ -1, 1 }) do
			table.insert(rows, {
				axis = "Z",
				sign = sz,
				index = i,
				top = top,
				depth = S.RowDepth,
				length = S.EndLength,
				-- end stands are shifted toward the far side so they don't block the camera
				center = Vector3.new(S.EndLength * 0.25, top, sz * (S.EndStart + i * S.RowDepth + S.RowDepth / 2)),
			})
		end
	end
	return rows
end

return Court
