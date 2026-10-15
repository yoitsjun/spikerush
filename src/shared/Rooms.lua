-- Home rooms (Config.Rooms): the menu room behind Home, the Players screen and the player pages,
-- swapped from Home's Decorate button (The Spike's "Decorate"; the owner, 2026-10-15: "add a
-- halloween style background you can also spin for kind of like how you can swap this"). The
-- Clubhouse is everyone's; the others are won (the Haunted Clubhouse on the Halloween banner).
-- Saved as profile.rooms = { owned = { [key] = true }, on = key }. Pure and shared (sims).

local Config = require(script.Parent.Config)

local Rooms = {}
local R = Config.Rooms

function Rooms.get(key)
	return type(key) == "string" and R.List[key] or nil
end

-- Every room, in Order: { key, def }.
function Rooms.list()
	local out = {}
	for _, key in ipairs(R.Order) do
		table.insert(out, { key = key, def = R.List[key] })
	end
	return out
end

-- Whether a room is yours: the default always is; a developer owns everything.
function Rooms.owns(rooms, key, dev)
	local def = Rooms.get(key)
	if not def then
		return false
	end
	if def.Default or dev then
		return true
	end
	return type(rooms) == "table" and type(rooms.owned) == "table" and rooms.owned[key] == true
end

-- Saved rooms made safe: known rooms only; the one on is one you own (else the default).
function Rooms.clean(data)
	local out = { owned = {}, on = R.Default }
	if type(data) ~= "table" then
		return out
	end
	if type(data.owned) == "table" then
		for key, v in pairs(data.owned) do
			local def = Rooms.get(key)
			if v == true and def and not def.Default then
				out.owned[key] = true
			end
		end
	end
	if Rooms.owns(out, data.on) then
		out.on = data.on
	end
	return out
end

-- The room shown (the one on; a developer's pick stands even unowned).
function Rooms.current(rooms, dev)
	local on = type(rooms) == "table" and rooms.on or nil
	if Rooms.owns(rooms, on, dev) then
		return on
	end
	return R.Default
end

-- Put a room on. Returns ok, why ("unknown", "locked").
function Rooms.equip(rooms, key, dev)
	if not Rooms.get(key) then
		return false, "unknown"
	end
	if not Rooms.owns(rooms, key, dev) then
		return false, "locked"
	end
	rooms.on = key
	return true
end

return Rooms
