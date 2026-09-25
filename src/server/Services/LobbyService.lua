-- Custom lobbies (the rules live in the shared Lobbies module).
-- Players make a lobby (mode, Public / Friends / Private with a password, fill with bots, bot
-- level), others join it from the list, and the host starts it. Quick Match drops you into the
-- fullest open public lobby of a mode, or opens one that starts itself.
-- Where it plays: on this server's court when that's free. When the court is busy the lobby gets
-- its own reserved server (everyone in it is teleported there with the lobby's settings); in
-- Studio, or if that fails, it waits its turn for this court. A teleported lobby rebuilds itself
-- in the new server, waits for its players, then starts; after the match it stays together
-- there for a rematch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lobbies = require(Shared.Lobbies)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local LobbyService = {}
local reg
local L = Config.Lobby

local lobbies = {} -- id -> lobby
local order = {} -- ids, oldest first
local memberOf = {} -- userId -> lobby id
local courtQueue = {} -- lobby ids waiting for this server's court
local friendCache = {} -- viewerId -> { hostId = bool }
local lastRequest = {}
local nextId = 0
local dirty = true

-- A reserved server (made by a lobby's teleport): the lobby rebuilds itself here.
LobbyService.reserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local arrival = nil -- the teleported lobby, while its players arrive

local NOTICES = {
	started = "That lobby has already started.",
	full = "That lobby is full.",
	friends = "That lobby is for the host's friends only.",
	password = "Wrong password.",
	teams = "Both teams need to be full (or turn on Fill with bots).",
	empty = "Nobody is in the lobby.",
	limit = "Too many lobbies in this server. Join one instead.",
	host = "Only the host can do that.",
	gone = "That lobby is gone.",
}

local function markDirty()
	dirty = true
end

local function notify(plr, text)
	if plr and plr.Parent then
		Net.get("Lobbies"):FireClient(plr, { notice = text })
	end
end

local function members(l)
	local out = {}
	for _, side in ipairs({ "Home", "Away" }) do
		for _, u in ipairs(l[side]) do
			local plr = Players:GetPlayerByUserId(u)
			if plr then
				table.insert(out, plr)
			end
		end
	end
	return out
end

-- Friendship, cached. Unknown pairs answer false for now and are looked up in the background.
local function isFriend(viewer, hostId)
	if not hostId or viewer.UserId == hostId then
		return true
	end
	local row = friendCache[viewer.UserId]
	if not row then
		row = {}
		friendCache[viewer.UserId] = row
	end
	if row[hostId] == nil then
		row[hostId] = false
		task.spawn(function()
			local ok, result = pcall(function()
				return viewer:IsFriendsWith(hostId)
			end)
			if ok and result then
				row[hostId] = true
				markDirty()
			end
		end)
	end
	return row[hostId]
end

-- The same check, waiting for the answer (joining needs a real one).
local function isFriendNow(viewer, hostId)
	if not hostId or viewer.UserId == hostId then
		return true
	end
	local ok, result = pcall(function()
		return viewer:IsFriendsWith(hostId)
	end)
	local yes = ok and result == true
	friendCache[viewer.UserId] = friendCache[viewer.UserId] or {}
	friendCache[viewer.UserId][hostId] = yes
	return yes
end

function LobbyService.get(id)
	return lobbies[id]
end

function LobbyService.lobbyOf(plr)
	local id = memberOf[plr.UserId]
	return id and lobbies[id]
end

local function dissolve(l)
	for _, side in ipairs({ "Home", "Away" }) do
		for _, u in ipairs(l[side]) do
			if memberOf[u] == l.id then
				memberOf[u] = nil
			end
		end
	end
	lobbies[l.id] = nil
	for i = #order, 1, -1 do
		if order[i] == l.id then
			table.remove(order, i)
		end
	end
	for i = #courtQueue, 1, -1 do
		if courtQueue[i] == l.id then
			table.remove(courtQueue, i)
		end
	end
	if arrival == l then
		arrival = nil
	end
	markDirty()
end

function LobbyService.leave(plr)
	local l = LobbyService.lobbyOf(plr)
	memberOf[plr.UserId] = nil
	if not l then
		return
	end
	if Lobbies.remove(l, plr.UserId) and l.state ~= "Playing" then
		dissolve(l)
	else
		local host = l.host and Players:GetPlayerByUserId(l.host)
		if host then
			l.hostName = host.DisplayName
		end
		markDirty()
	end
end

local function add(l)
	lobbies[l.id] = l
	table.insert(order, l.id)
	markDirty()
end

local function newId()
	nextId = nextId + 1
	return nextId
end

function LobbyService.create(plr, raw, quick)
	LobbyService.leave(plr)
	if #order >= L.MaxLobbies then
		notify(plr, NOTICES.limit)
		return nil
	end
	local s, why = Lobbies.settings(raw)
	if not s then
		notify(plr, why == "password" and string.format("Pick a password of %d to %d letters or digits.", L.PasswordMin, L.PasswordMax) or "Those settings don't work.")
		return nil
	end
	local l = Lobbies.new(newId(), plr.UserId, plr.DisplayName, s)
	if quick then
		l.quick = true
		l.startsAt = Util.now() + L.QuickStartTime
	end
	Lobbies.seat(l, plr.UserId)
	memberOf[plr.UserId] = l.id
	add(l)
	return l
end

function LobbyService.join(plr, id, password)
	local l = lobbies[id]
	if not l then
		notify(plr, NOTICES.gone)
		return false
	end
	if memberOf[plr.UserId] == id then
		return true
	end
	local friend = l.privacy ~= "Friends" or isFriendNow(plr, l.host)
	local ok, why = Lobbies.canJoin(l, plr.UserId, password, friend)
	if not ok then
		notify(plr, NOTICES[why] or "Can't join that lobby.")
		return false
	end
	LobbyService.leave(plr)
	if not lobbies[id] or not Lobbies.seat(l, plr.UserId) then
		notify(plr, NOTICES.full)
		return false
	end
	memberOf[plr.UserId] = id
	markDirty()
	return true
end

-- The tutorial: a hidden 1v1 against the weakest bots, started at once.
function LobbyService.tutorial(plr)
	local T = Config.Tutorial
	local l = LobbyService.create(plr, { mode = T.Mode, privacy = "Public", fill = true, botTier = T.BotTier }, false)
	if not l then
		return
	end
	l.hidden = true
	l.tutorial = true
	LobbyService.launch(l)
end

-- Quick Match: the fullest open public quick lobby of that mode, or a new one.
function LobbyService.quick(plr, mode)
	local list = {}
	for _, id in ipairs(order) do
		table.insert(list, lobbies[id])
	end
	local l = Lobbies.pickQuick(list, mode)
	if l and LobbyService.join(plr, l.id) then
		return l
	end
	return LobbyService.create(plr, { mode = mode, privacy = "Public", fill = true, botTier = Config.Match.DefaultBotTier }, true)
end

------------------------------------------------------------------------------------------
-- starting
------------------------------------------------------------------------------------------

local function courtFree()
	return not reg.TeamService.inMatch and reg.MatchService.phase == "Intermission" and #courtQueue == 0
end

local function canTeleport()
	return L.ReservedServers and not RunService:IsStudio() and game.PlaceId ~= 0 and not LobbyService.reserved
end

local function queueForCourt(l)
	l.state = "Queued"
	table.insert(courtQueue, l.id)
	markDirty()
end

local function teleport(l)
	local list = members(l)
	local ok, code = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if ok and code then
		for _, plr in ipairs(list) do
			reg.ProfileService.save(plr) -- the new server loads what this one saved
		end
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({ spikeRushLobby = Lobbies.export(l) })
		ok = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, list, options)
		end)
	end
	if not ok and lobbies[l.id] and l.state == "Teleporting" then
		for _, plr in ipairs(list) do
			notify(plr, "Couldn't open a private server. You're next in line for this court.")
		end
		queueForCourt(l)
	end
end

function LobbyService.launch(l)
	local ok, why = Lobbies.canStart(l)
	if not ok then
		return false, why
	end
	if courtFree() or not canTeleport() then
		queueForCourt(l)
	else
		l.state = "Teleporting"
		markDirty()
		task.spawn(teleport, l)
	end
	return true
end

function LobbyService.start(plr)
	local l = LobbyService.lobbyOf(plr)
	if not l then
		return
	end
	if l.host ~= plr.UserId then
		notify(plr, NOTICES.host)
		return
	end
	local ok, why = LobbyService.launch(l)
	if not ok then
		notify(plr, NOTICES[why] or "Can't start yet.")
	end
end

-- MatchService asks for the next lobby to play on this court (nil while nobody is waiting).
function LobbyService.nextForCourt()
	while #courtQueue > 0 do
		local id = table.remove(courtQueue, 1)
		local l = lobbies[id]
		if l and #members(l) > 0 then
			l.state = "Playing"
			markDirty()
			return l
		elseif l then
			dissolve(l)
		end
	end
	return nil
end

-- Who plays on which side (Players), for TeamService.assign.
function LobbyService.plan(l)
	local plan = { Home = {}, Away = {} }
	for _, side in ipairs({ "Home", "Away" }) do
		for _, u in ipairs(l[side]) do
			local plr = Players:GetPlayerByUserId(u)
			if plr then
				table.insert(plan[side], plr)
			end
		end
	end
	return plan
end

-- The match is over: a quick lobby splits up, a custom one is ready for a rematch.
function LobbyService.finished(l)
	if not lobbies[l.id] then
		return
	end
	if l.quick or l.tutorial or #members(l) == 0 then
		dissolve(l)
		return
	end
	l.state = "Open"
	markDirty()
end

function LobbyService.isMember(l, plr)
	return l ~= nil and Lobbies.teamOf(l, plr.UserId) ~= nil
end

------------------------------------------------------------------------------------------
-- a teleported lobby arriving in its reserved server
------------------------------------------------------------------------------------------

local function onArrive(plr)
	if not LobbyService.reserved then
		return
	end
	local data = nil
	pcall(function()
		local join = plr:GetJoinData()
		data = join and join.TeleportData
	end)
	if not arrival and type(data) == "table" and data.spikeRushLobby then
		local l = Lobbies.import(data.spikeRushLobby, newId())
		if l then
			l.state = "Arriving"
			l.arriveBy = Util.now() + L.ArriveTimeout
			l.Home, l.Away = {}, {}
			arrival = l
			add(l)
		end
	end
	local l = arrival
	if l and l.expected and l.expected[plr.UserId] then
		Lobbies.seat(l, plr.UserId, l.expected[plr.UserId])
		memberOf[plr.UserId] = l.id
		if l.state == "Playing" then
			reg.TeamService.requestJoin(plr) -- arrived late: takes a bot's place
		end
		markDirty()
	end
end

local function arrivalTick(now)
	local l = arrival
	if not l or l.state ~= "Arriving" then
		return
	end
	local all = true
	for u in pairs(l.expected) do
		if not Players:GetPlayerByUserId(u) then
			all = false
		end
	end
	if (all or now >= l.arriveBy) and Lobbies.count(l) > 0 then
		if not l.host or not Lobbies.teamOf(l, l.host) then
			l.host = l.Home[1] or l.Away[1]
			local host = Players:GetPlayerByUserId(l.host)
			l.hostName = host and host.DisplayName or l.hostName
		end
		l.state = "Open"
		l.fill = true -- whoever didn't make it is covered by a bot
		LobbyService.launch(l)
	elseif now >= l.arriveBy then
		dissolve(l)
	end
end

------------------------------------------------------------------------------------------
-- the list each player sees
------------------------------------------------------------------------------------------

local function payloadFor(plr)
	local list = {}
	for _, id in ipairs(order) do
		local l = lobbies[id]
		if l and Lobbies.visible(l, plr.UserId, l.privacy ~= "Friends" or isFriend(plr, l.host)) then
			table.insert(list, Lobbies.summary(l, plr.UserId))
		end
	end
	local mine = nil
	local l = LobbyService.lobbyOf(plr)
	if l then
		mine = Lobbies.summary(l, plr.UserId)
		mine.isHost = l.host == plr.UserId
		mine.password = mine.isHost and l.password or nil
		mine.side = Lobbies.teamOf(l, plr.UserId)
		mine.startsAt = l.startsAt
		mine.tutorial = l.tutorial
		mine.arriveBy = l.arriveBy
		mine.reserved = LobbyService.reserved
		for i, id in ipairs(courtQueue) do
			if id == l.id then
				mine.queuePos = i
			end
		end
		for _, side in ipairs({ "Home", "Away" }) do
			mine[side] = {}
			for _, u in ipairs(l[side]) do
				local p = Players:GetPlayerByUserId(u)
				table.insert(mine[side], { id = u, name = p and p.DisplayName or "...", host = u == l.host })
			end
		end
	end
	return {
		list = list,
		mine = mine,
		court = { busy = reg.TeamService.inMatch, queue = #courtQueue },
		teleport = canTeleport(),
	}
end

local function broadcast()
	dirty = false
	for _, plr in ipairs(Players:GetPlayers()) do
		Net.get("Lobbies"):FireClient(plr, payloadFor(plr))
	end
end

------------------------------------------------------------------------------------------
-- requests
------------------------------------------------------------------------------------------

local function onRequest(plr, op, a, b)
	local now = os.clock()
	if lastRequest[plr] and now - lastRequest[plr] < 0.15 then
		return
	end
	lastRequest[plr] = now
	if type(op) ~= "string" then
		return
	end
	-- a player in the match can't wander into other lobbies
	if op ~= "rejoin" and op ~= "list" and reg.TeamService.entityForPlayer(plr) and reg.TeamService.inMatch then
		return
	end
	if op == "create" then
		LobbyService.create(plr, a, false)
	elseif op == "tutorial" then
		LobbyService.tutorial(plr)
	elseif op == "quick" then
		local mode = tonumber(a)
		if mode == 1 or mode == 2 or mode == 3 then
			LobbyService.quick(plr, mode)
		end
	elseif op == "join" then
		local id = tonumber(a)
		if id then
			LobbyService.join(plr, id, b)
		end
	elseif op == "leave" then
		local l = LobbyService.lobbyOf(plr)
		if l and (l.state == "Open" or l.state == "Queued") then
			LobbyService.leave(plr)
			if l.state == "Queued" and Lobbies.count(l) == 0 then
				dissolve(l)
			end
		end
	elseif op == "start" then
		LobbyService.start(plr)
	elseif op == "team" then
		local l = LobbyService.lobbyOf(plr)
		if l and l.state == "Open" and Lobbies.swap(l, plr.UserId) then
			markDirty()
		end
	elseif op == "kick" then
		local l = LobbyService.lobbyOf(plr)
		local target = tonumber(a)
		if l and l.host == plr.UserId and target and target ~= plr.UserId and Lobbies.teamOf(l, target) then
			Lobbies.remove(l, target)
			memberOf[target] = nil
			notify(Players:GetPlayerByUserId(target), "The host removed you from the lobby.")
			markDirty()
		end
	elseif op == "settings" then
		local l = LobbyService.lobbyOf(plr)
		if not l or l.host ~= plr.UserId or l.state ~= "Open" then
			return
		end
		local s, why = Lobbies.settings(a)
		if not s then
			notify(plr, why == "password" and string.format("Pick a password of %d to %d letters or digits.", L.PasswordMin, L.PasswordMax) or "Those settings don't work.")
			return
		end
		for _, u in ipairs(Lobbies.configure(l, s)) do
			memberOf[u] = nil
			notify(Players:GetPlayerByUserId(u), "The lobby got smaller and you were moved out.")
		end
		l.quick = nil
		l.startsAt = nil
		markDirty()
	elseif op == "rejoin" then
		reg.TeamService.requestJoin(plr)
	elseif op == "list" then
		Net.get("Lobbies"):FireClient(plr, payloadFor(plr))
	end
end

function LobbyService.init(r)
	reg = r
	Net.get("Lobby").OnServerEvent:Connect(onRequest)
	Players.PlayerAdded:Connect(function(plr)
		onArrive(plr)
		markDirty()
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		onArrive(plr)
	end
	Players.PlayerRemoving:Connect(function(plr)
		LobbyService.leave(plr)
		friendCache[plr.UserId] = nil
		lastRequest[plr] = nil
		markDirty()
	end)
	TeleportService.TeleportInitFailed:Connect(function(plr)
		local l = LobbyService.lobbyOf(plr)
		if l and l.state == "Teleporting" then
			notify(plr, "The teleport failed. You're next in line for this court.")
			queueForCourt(l)
		end
	end)
	task.spawn(function()
		local lastFull = 0
		while true do
			task.wait(0.25)
			local now = Util.now()
			for _, id in ipairs(order) do
				local l = lobbies[id]
				-- a Quick Match lobby starts itself when full or when its countdown runs out
				if l and l.quick and l.state == "Open" and (Lobbies.count(l) >= Lobbies.capacity(l) or now >= (l.startsAt or 0)) then
					LobbyService.launch(l)
				end
			end
			arrivalTick(now)
			-- teleported players leave without firing anything else; a periodic refresh keeps
			-- countdowns and the court status honest
			if dirty or os.clock() - lastFull > 3 then
				lastFull = os.clock()
				broadcast()
			end
		end
	end)
end

return LobbyService
