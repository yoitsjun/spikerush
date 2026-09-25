-- Custom lobbies: the rules, shared so the headless tests run them. The server (LobbyService)
-- holds the lobbies and the menus draw them; neither decides anything this module doesn't.
--   * a lobby has a host, a mode (1v1 to 3v3), a privacy, "fill with bots", a bot level and two
--     sides (Home, Away) of up to `mode` players each
--   * Public lobbies are open to anyone in the server; Friends lobbies are only seen and joined
--     by the host's Roblox friends; Private lobbies are listed with a lock and need the password
--   * with "fill with bots" the host can start any time (bots take the empty spots); without it
--     both sides have to be full
--   * Quick Match joins the fullest open public quick lobby of that mode, or opens one that
--     starts on its own a few seconds later
-- It also holds the AFK rule: idle time only counts while the ball is live.

local Config = require(script.Parent.Config)
local Characters = require(script.Parent.Characters)

local Lobbies = {}
local L = Config.Lobby
local SIDES = { "Home", "Away" }

local PRIVACY = {}
for _, p in ipairs(L.Privacy) do
	PRIVACY[p] = true
end

-- Passwords are letters and digits only, never shown to anyone but the host.
function Lobbies.cleanPassword(raw)
	if type(raw) ~= "string" then
		return ""
	end
	return (raw:gsub("[^%w]", "")):sub(1, L.PasswordMax)
end

-- Settings from a client, made safe. Returns the settings, or nil and a reason ("password").
function Lobbies.settings(raw)
	raw = type(raw) == "table" and raw or {}
	local mode = tonumber(raw.mode)
	if mode ~= 1 and mode ~= 2 and mode ~= 3 then
		mode = Config.Match.DefaultTeamSize
	end
	local s = {
		mode = mode,
		privacy = PRIVACY[raw.privacy] and raw.privacy or "Public",
		fill = raw.fill ~= false,
		botTier = Characters.isTier(raw.botTier) and raw.botTier or Config.Match.DefaultBotTier,
	}
	if s.privacy == "Private" then
		local pw = Lobbies.cleanPassword(raw.password)
		if #pw < L.PasswordMin then
			return nil, "password"
		end
		s.password = pw
	end
	return s
end

function Lobbies.new(id, hostId, hostName, settings)
	local l = { id = id, host = hostId, hostName = hostName, Home = {}, Away = {}, state = "Open" }
	Lobbies.configure(l, settings)
	return l
end

function Lobbies.count(l)
	return #l.Home + #l.Away
end

function Lobbies.capacity(l)
	return l.mode * 2
end

-- The side a player is on (and their slot), or nil.
function Lobbies.teamOf(l, userId)
	for _, side in ipairs(SIDES) do
		for i, u in ipairs(l[side]) do
			if u == userId then
				return side, i
			end
		end
	end
	return nil, nil
end

-- Whether this player sees the lobby in the list (its members always do; nobody else sees a
-- hidden one, like a tutorial).
function Lobbies.visible(l, userId, isFriend)
	if l.host == userId or Lobbies.teamOf(l, userId) then
		return true
	end
	if l.hidden then
		return false
	end
	if l.privacy == "Friends" then
		return isFriend == true
	end
	return true
end

-- Whether this player may join now. Returns ok and, if not, why: "started", "full", "friends"
-- or "password".
function Lobbies.canJoin(l, userId, password, isFriend)
	if Lobbies.teamOf(l, userId) then
		return true
	end
	if l.state ~= "Open" or l.hidden then
		return false, "started"
	end
	if Lobbies.count(l) >= Lobbies.capacity(l) then
		return false, "full"
	end
	if l.privacy == "Friends" and not isFriend then
		return false, "friends"
	end
	if l.privacy == "Private" and Lobbies.cleanPassword(password) ~= l.password then
		return false, "password"
	end
	return true
end

-- Seat a player: on `want` if it has room, else on the emptier side. Returns the side or nil.
function Lobbies.seat(l, userId, want)
	local cur = Lobbies.teamOf(l, userId)
	if cur then
		return cur
	end
	if (want == "Home" or want == "Away") and #l[want] < l.mode then
		table.insert(l[want], userId)
		return want
	end
	local order = SIDES
	if #l.Away < #l.Home then
		order = { "Away", "Home" }
	end
	for _, side in ipairs(order) do
		if #l[side] < l.mode then
			table.insert(l[side], userId)
			return side
		end
	end
	return nil
end

-- Move a player to the other side if it has room.
function Lobbies.swap(l, userId)
	local side, i = Lobbies.teamOf(l, userId)
	if not side then
		return false
	end
	local other = side == "Home" and "Away" or "Home"
	if #l[other] >= l.mode then
		return false
	end
	table.remove(l[side], i)
	table.insert(l[other], userId)
	return true
end

-- Take a player out; the host passes to the next member. Returns true when nobody is left.
function Lobbies.remove(l, userId)
	local side, i = Lobbies.teamOf(l, userId)
	if side then
		table.remove(l[side], i)
	end
	if l.host == userId then
		l.host = l.Home[1] or l.Away[1]
	end
	return Lobbies.count(l) == 0
end

-- Apply new settings. A smaller mode keeps whoever still fits (anyone who doesn't, newest first,
-- moves to the other side if there's room, else is dropped; never the host). Returns the
-- dropped players.
function Lobbies.configure(l, s)
	l.mode, l.privacy, l.password, l.fill, l.botTier = s.mode, s.privacy, s.password, s.fill, s.botTier
	local out = {}
	for _, side in ipairs(SIDES) do
		local i = #l[side]
		while #l[side] > l.mode and i >= 1 do
			if l[side][i] ~= l.host then
				table.insert(out, table.remove(l[side], i))
			end
			i = i - 1
		end
	end
	local dropped = {}
	for _, u in ipairs(out) do
		if not Lobbies.seat(l, u) then
			table.insert(dropped, u)
		end
	end
	return dropped
end

-- Whether the host can start. Returns ok and, if not, why: "started", "empty" or "teams".
function Lobbies.canStart(l)
	if l.state ~= "Open" then
		return false, "started"
	end
	if Lobbies.count(l) == 0 then
		return false, "empty"
	end
	if not l.fill and (#l.Home < l.mode or #l.Away < l.mode) then
		return false, "teams"
	end
	return true
end

-- The Quick Match lobby to join for a mode: the fullest open public quick lobby with room
-- (oldest first on a tie), or nil.
function Lobbies.pickQuick(list, mode)
	local best = nil
	for _, l in ipairs(list) do
		if l.quick and l.state == "Open" and l.mode == mode and l.privacy == "Public" and Lobbies.count(l) < Lobbies.capacity(l) then
			if not best or Lobbies.count(l) > Lobbies.count(best) or (Lobbies.count(l) == Lobbies.count(best) and l.id < best.id) then
				best = l
			end
		end
	end
	return best
end

-- What a player sees of a lobby in the list.
function Lobbies.summary(l, viewerId)
	return {
		id = l.id,
		host = l.host,
		hostName = l.hostName,
		mode = l.mode,
		privacy = l.privacy,
		locked = l.privacy == "Private",
		fill = l.fill,
		botTier = l.botTier,
		count = Lobbies.count(l),
		capacity = Lobbies.capacity(l),
		state = l.state,
		quick = l.quick == true,
		mine = Lobbies.teamOf(l, viewerId) ~= nil,
	}
end

-- The lobby as plain data for a teleport to its own server.
function Lobbies.export(l)
	local out = { mode = l.mode, privacy = l.privacy, password = l.password, fill = l.fill, botTier = l.botTier, host = l.host, hostName = l.hostName, quick = l.quick == true, Home = {}, Away = {} }
	for _, side in ipairs(SIDES) do
		for _, u in ipairs(l[side]) do
			table.insert(out[side], u)
		end
	end
	return out
end

-- Rebuild an exported lobby (teleport data passes through the client, so check everything).
-- The sides come back empty with `expected` listing who should arrive and on which side.
function Lobbies.import(data, id)
	if type(data) ~= "table" then
		return nil
	end
	local raw = { mode = data.mode, privacy = data.privacy, fill = data.fill, botTier = data.botTier, password = data.password }
	local s = Lobbies.settings(raw)
	if not s then
		raw.privacy = "Public"
		s = Lobbies.settings(raw)
	end
	local l = Lobbies.new(id, tonumber(data.host), type(data.hostName) == "string" and data.hostName:sub(1, 40) or "Host", s)
	l.quick = data.quick == true
	l.expected = {}
	for _, side in ipairs(SIDES) do
		local list = type(data[side]) == "table" and data[side] or {}
		for i = 1, math.min(#list, s.mode) do
			local u = tonumber(list[i])
			if u then
				l.expected[u] = side
			end
		end
	end
	return l
end

-- AFK: add `dt` of idle time. Input resets it; it only builds while the ball is live. Returns
-- the new idle time and whether the player is now AFK.
function Lobbies.idle(idle, dt, phase, active)
	if active then
		return 0, false
	end
	if not Config.Afk.Phases[phase] then
		return idle, false
	end
	idle = idle + dt
	return idle, idle >= Config.Afk.Timeout
end

return Lobbies
