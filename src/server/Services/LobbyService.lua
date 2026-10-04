-- Custom lobbies (the rules live in the shared Lobbies module).
-- Players make a lobby (mode, Public / Friends / Private with a password, fill with bots, bot
-- level), others join it from the list, and the host starts it. Quick Match drops you into the
-- fullest open public lobby of a mode, or opens one that starts itself.
-- Where it plays: on this server's court when that's free. When the court is busy the lobby gets
-- its own reserved server (everyone in it is teleported there with the lobby's settings); in
-- Studio, or if that fails, it waits its turn for this court. A teleported lobby rebuilds itself
-- in the new server, waits for its players, then starts; after the match it stays together
-- there for a rematch.
-- Across servers (Config.Lobby.Global; the owner: "make queues global throughout servers, same
-- with lobbies"): every server lists its open lobbies in a MemoryStore sorted map, so every list
-- shows every server's lobbies and Quick Match joins the fullest queue anywhere. A lobby stays in
-- its host's server; a player from another server takes a remote seat. Their server and the
-- host's talk over MessagingService, a topic per server:
--   to the host:   join, leave, team (swap sides), keep (every few seconds: "these players are
--                  still here")
--   from the host: ok / no (the join), st (the lobby changed), out (a player was removed), close
--                  (the lobby is gone), go (it started: the reserved server's code)
-- When it starts, everyone from every server is teleported to one reserved server. A remote seat
-- whose server goes quiet is let go, and a lobby with nobody left in its host's server closes (a
-- Quick Match finds its players another). The host is always someone in the host's server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lobbies = require(Shared.Lobbies)
local Tutorial = require(Shared.Tutorial)
local Cups = require(Shared.Cups)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local LobbyService = {}
local reg
local L = Config.Lobby
local G = L.Global

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

-- Across servers (see the top). Lobbies of this server keep, besides the usual: gid (their id
-- everywhere), remote (userId -> { job, name, seen, at }: the players from other servers), view /
-- viewKey / v (what the others see, and its version), listed / writing / writtenAt (the shared
-- list) and launch ({ code, x }: started, the reserved server's code and the lobby for it).
local net = {
	on = false,
	job = "", -- this server's id (game.JobId; made up in Studio, where it's empty)
	map = nil,
	dir = {}, -- gid -> entry: the other servers' lobbies, from the last read
	dirAt = -100,
	reading = false,
	-- my players sitting in other servers' lobbies: userId -> { g, job, pending (until the host's
	-- server says yes), since, v (the version that seated them), quick, mode, going (teleporting) }
	remoteOf = {},
	views = {}, -- gid -> { v, view, job }: the lobbies they sit in
	keepAt = 0,
	watchAt = 0,
}
local HANDLERS = {}

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

-- Why a remote seat ended (the host's "out"), and why a remote lobby closed.
local OUT_TEXT = {
	kicked = "The host removed you from the lobby.",
	smaller = "The lobby got smaller and you were moved out.",
	lost = "Lost touch with that lobby's server.",
	solo = "That lobby couldn't take players from other servers, so it went without you.",
	gone = "That lobby is gone.",
}
local CLOSE_TEXT = {
	host = "That lobby closed: nobody is left in its host's server.",
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

-- This server's players in the lobby (the ones from other servers aren't Players here).
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

------------------------------------------------------------------------------------------
-- across servers: the plumbing
------------------------------------------------------------------------------------------

local function gidOf(id)
	return net.job .. "/" .. tostring(id)
end

-- A global id's server and local id.
local function parseGid(g)
	if type(g) ~= "string" or #g > 120 then
		return nil, nil
	end
	local job, id = string.match(g, "^(.+)/(%d+)$")
	return job, tonumber(id)
end

-- A message to another server's inbox (now: wait for it, for the shutdown). Too long for
-- MessagingService, a state or a start goes without its body (the receiver reads it from the
-- shared list).
local function send(job, msg, now)
	if not net.on or type(job) ~= "string" or job == "" or job == net.job then
		return
	end
	msg.from = net.job
	msg.fv = G.Format
	local ok, js = pcall(function()
		return HttpService:JSONEncode(msg)
	end)
	if not ok then
		return
	end
	if #js > G.MessageMax then
		msg.view, msg.x = nil, nil
	end
	local function publish()
		local sent, err = pcall(function()
			MessagingService:PublishAsync(G.Inbox .. job, msg)
		end)
		if not sent then
			warn("[SpikeRush] lobby message (" .. tostring(msg.k) .. "): " .. tostring(err))
		end
	end
	if now then
		publish()
	else
		task.spawn(publish)
	end
end

local function hasRemote(l)
	return l.remote ~= nil and next(l.remote) ~= nil
end

local function remoteJobs(l)
	local jobs = {}
	for _, r in pairs(l.remote or {}) do
		jobs[r.job] = true
	end
	return jobs
end

local function nameOf(l, u)
	local p = Players:GetPlayerByUserId(u)
	if p then
		return p.DisplayName
	end
	local r = l.remote and l.remote[u]
	return r and r.name or "..."
end

-- The host is always someone in this server.
local function fixHost(l)
	if l.host and Players:GetPlayerByUserId(l.host) then
		return
	end
	local list = members(l)
	if list[1] then
		l.host = list[1].UserId
		l.hostName = list[1].DisplayName
	end
end

-- Whether a lobby goes in the shared list: not hidden (practice), open, or holding players from
-- elsewhere (they read it), or started with their reserved server's code.
local function shared(l)
	return net.on and not l.hidden and not l.cup and lobbies[l.id] == l and (l.state == "Open" or hasRemote(l) or l.launch ~= nil)
end

local function writeEntry(l, expire)
	if l.writing then
		l.viewDirty = true -- again once this one is through
		return
	end
	l.writing, l.viewDirty, l.listed = true, false, true
	l.writtenAt = os.clock()
	local entry = { fv = G.Format, job = net.job, view = l.view, code = l.launch and l.launch.code or nil, x = l.launch and l.launch.x or nil }
	task.spawn(function()
		local ok, err = pcall(function()
			net.map:SetAsync(l.gid, entry, expire or G.Expire)
		end)
		l.writing = false
		if not ok then
			l.viewDirty = true
			warn("[SpikeRush] lobby list write: " .. tostring(err))
		end
		if l.unlistAfter then
			l.unlistAfter = nil
			l.listed = false
			pcall(function()
				net.map:RemoveAsync(l.gid)
			end)
		end
	end)
end

local function unlist(l)
	if not l.listed then
		return
	end
	if l.writing then
		l.unlistAfter = true
		return
	end
	l.listed = false
	task.spawn(function()
		pcall(function()
			net.map:RemoveAsync(l.gid)
		end)
	end)
end

-- What the other servers see of a lobby; a change counts its version up and goes straight to the
-- servers of its remote players.
local function refreshView(l)
	if not net.on or l.hidden then
		return
	end
	local view = Lobbies.view(l, function(u)
		return nameOf(l, u)
	end)
	local key = Lobbies.viewKey(view)
	if key == l.viewKey then
		return
	end
	l.viewKey = key
	l.v = (l.v or 0) + 1
	view.v = l.v
	l.view = view
	l.viewDirty = true
	for job in pairs(remoteJobs(l)) do
		send(job, { k = "st", g = l.gid, view = view })
	end
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
	-- the shared list, and the servers of its remote players (a started one's entry stays until
	-- it runs out: it has the code for any server that missed the word)
	if net.on and l.gid and not l.launch then
		unlist(l)
		for job in pairs(remoteJobs(l)) do
			send(job, { k = "close", g = l.gid, why = l.closeWhy or "gone" })
		end
	end
	markDirty()
end

-- A player from another server leaves the lobby (why: tell their server, OUT_TEXT). The lobby
-- closes when nobody is left in this server.
local function removeRemote(l, u, why)
	local r = l.remote and l.remote[u]
	if not r then
		return
	end
	l.remote[u] = nil
	if why then
		send(r.job, { k = "out", g = l.gid, u = u, why = why })
	end
	local empty = Lobbies.remove(l, u)
	if l.state ~= "Playing" and (empty or #members(l) == 0) then
		l.closeWhy = "host"
		dissolve(l)
		return
	end
	fixHost(l)
	refreshView(l)
	markDirty()
end

local function dropRemotes(l, why)
	local list = {}
	for u in pairs(l.remote or {}) do
		table.insert(list, u)
	end
	for _, u in ipairs(list) do
		if lobbies[l.id] == l then
			removeRemote(l, u, why)
		end
	end
end

-- This server's lobby with that global id.
local function lobbyByGid(g)
	local job, id = parseGid(g)
	if job ~= net.job or not id then
		return nil
	end
	return lobbies[id]
end

local function teleportPlayers(list, code, export)
	for _, plr in ipairs(list) do
		reg.ProfileService.save(plr) -- the new server loads what this one saved
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	options:SetTeleportData({ spikeRushLobby = export })
	return pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, list, options)
	end)
end

-- A player of mine leaves the lobby they sit in elsewhere.
local function leaveRemote(plr)
	local r = net.remoteOf[plr.UserId]
	if not r then
		return
	end
	net.remoteOf[plr.UserId] = nil
	if not r.going then
		send(r.job, { k = "leave", g = r.g, u = plr.UserId })
	end
	markDirty()
end

-- A view of a lobby elsewhere, from its host's message or the shared list: the newest is kept,
-- and my players are matched against it (a pending join that shows up is in; a seat that's gone
-- from a view at least as new as the one that gave it is over).
local function takeView(g, job, view)
	if type(view) ~= "table" then
		return
	end
	local w = net.views[g]
	local v = tonumber(view.v) or 0
	if w and v <= (w.v or 0) then
		return
	end
	net.views[g] = { v = v, view = view, job = job }
	for u, r in pairs(net.remoteOf) do
		if r.g == g and not r.going then
			local seated = Lobbies.viewSide(view, u) ~= nil
			if r.pending and seated then
				r.pending, r.v = nil, v
			elseif not r.pending and not seated and v >= (r.v or 0) then
				net.remoteOf[u] = nil
				notify(Players:GetPlayerByUserId(u), "You're no longer in that lobby.")
			end
		end
	end
	markDirty()
end

-- A lobby elsewhere is gone: its players here are told (a Quick Match looks for another queue).
local function closeRemote(g, why)
	net.dir[g] = nil
	for u, r in pairs(net.remoteOf) do
		if r.g == g and not r.going then
			net.remoteOf[u] = nil
			local plr = Players:GetPlayerByUserId(u)
			if plr and r.quick then
				task.defer(LobbyService.quick, plr, r.mode)
			else
				notify(plr, CLOSE_TEXT[why] or CLOSE_TEXT.gone)
			end
		end
	end
	markDirty()
end

local function readEntry(g)
	local ok, entry = pcall(function()
		return net.map:GetAsync(g)
	end)
	if not ok then
		return nil, false
	end
	if type(entry) ~= "table" or entry.fv ~= G.Format then
		return nil, true
	end
	return entry, true
end

-- A lobby elsewhere started: my players in it go to its reserved server (the lobby comes with the
-- message, or from the shared list when the message was too long for it).
local function goAcross(g, code, x)
	if type(code) ~= "string" then
		return
	end
	local list = {}
	for u, r in pairs(net.remoteOf) do
		if r.g == g and not r.pending and not r.going then
			local plr = Players:GetPlayerByUserId(u)
			if plr then
				r.going = true
				table.insert(list, plr)
			end
		end
	end
	if #list == 0 then
		return
	end
	local w = net.views[g]
	if w then
		w.view.state = "Teleporting"
	end
	markDirty()
	task.spawn(function()
		if type(x) ~= "table" then
			local entry = readEntry(g)
			x = entry and entry.x
		end
		local ok = type(x) == "table" and teleportPlayers(list, code, x)
		if not ok then
			for _, plr in ipairs(list) do
				net.remoteOf[plr.UserId] = nil
				notify(plr, "Couldn't take you to that match.")
			end
			markDirty()
		end
	end)
end

local function fetchView(g)
	local entry, answered = readEntry(g)
	if not answered then
		return
	end
	if not entry then
		closeRemote(g, "gone")
		return
	end
	takeView(g, entry.job, entry.view)
	if type(entry.code) == "string" then
		goAcross(g, entry.code, entry.x)
	end
end

-- The other servers' lobbies (every entry not this server's).
local function readDirectory()
	if net.reading or not net.map then
		return
	end
	net.reading = true
	local ok, items = pcall(function()
		return net.map:GetRangeAsync(Enum.SortDirection.Ascending, G.MaxRead)
	end)
	net.reading = false
	net.dirAt = os.clock()
	if not ok or type(items) ~= "table" then
		return
	end
	local dir = {}
	for _, item in ipairs(items) do
		local e = type(item) == "table" and item.value
		if type(item.key) == "string" and type(e) == "table" and e.fv == G.Format and type(e.job) == "string" and e.job ~= net.job and type(e.view) == "table" then
			dir[item.key] = e
		end
	end
	net.dir = dir
	markDirty()
end

local function countOf(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

------------------------------------------------------------------------------------------
-- making, joining and leaving
------------------------------------------------------------------------------------------

-- A cup's entry back to a player who leaves before it starts.
local function cupRefund(l, userId)
	local paid = l.cup and l.cup.paid
	if paid and paid[userId] and l.state == "Open" then
		paid[userId] = nil
		local plr = Players:GetPlayerByUserId(userId)
		local c = Cups.cup(l.cup.key)
		if plr and c then
			reg.ProfileService.award(plr, c.Entry, 0)
			notify(plr, string.format("Your %d VP entry is back.", c.Entry))
		end
	end
end

function LobbyService.leave(plr)
	leaveRemote(plr) -- a seat in another server's lobby
	local l = LobbyService.lobbyOf(plr)
	memberOf[plr.UserId] = nil
	if not l then
		return
	end
	cupRefund(l, plr.UserId)
	local empty = Lobbies.remove(l, plr.UserId)
	if l.state ~= "Playing" and (empty or (hasRemote(l) and #members(l) == 0)) then
		l.closeWhy = "host" -- the players from other servers are told
		dissolve(l)
	else
		fixHost(l)
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
	l.gid = gidOf(l.id)
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
	if l.cup and #l.Home >= l.mode then
		notify(plr, NOTICES.full)
		return false
	end
	LobbyService.leave(plr)
	if l.cup then
		-- a friend's run: they pay the entry too, and sit on the players' side
		local c = Cups.cup(l.cup.key)
		local paid, payWhy = reg.ProfileService.spendVP(plr, c and c.Entry or 0)
		if not paid then
			notify(plr, payWhy)
			return false
		end
		if not lobbies[id] or l.state ~= "Open" or not Lobbies.seat(l, plr.UserId, "Home") then
			reg.ProfileService.award(plr, c and c.Entry or 0, 0)
			notify(plr, NOTICES.full)
			return false
		end
		l.cup.paid = l.cup.paid or {}
		l.cup.paid[plr.UserId] = not reg.ProfileService.isDev(plr) or nil
		memberOf[plr.UserId] = id
		markDirty()
		return true
	end
	if not lobbies[id] or not Lobbies.seat(l, plr.UserId) then
		notify(plr, NOTICES.full)
		return false
	end
	memberOf[plr.UserId] = id
	markDirty()
	return true
end

-- Join a lobby in another server (its entry from the shared list): the seat is theirs once its
-- host's server says yes. quick: a Quick Match (a refusal finds another queue instead).
local function joinRemote(plr, g, password, quick)
	local e = net.dir[g]
	local view = e and e.view
	if type(view) ~= "table" then
		if not quick then
			notify(plr, NOTICES.gone)
		end
		return false
	end
	local friend = view.privacy ~= "Friends" or isFriendNow(plr, tonumber(view.host))
	if not friend then
		notify(plr, NOTICES.friends)
		return false
	end
	LobbyService.leave(plr)
	net.remoteOf[plr.UserId] = { g = g, job = e.job, pending = true, since = os.clock(), quick = quick == true or nil, mode = tonumber(view.mode) }
	takeView(g, e.job, view)
	send(e.job, { k = "join", g = g, u = plr.UserId, n = string.sub(plr.DisplayName, 1, 40), f = friend, pw = password and Lobbies.cleanPassword(password) or nil })
	markDirty()
	return true
end

-- Practice: a hidden lobby of your own that runs a drill on the court instead of a match
-- (PracticeService); the tutorial is all four drills in order. Started at once.
function LobbyService.practice(plr, drillId, tutorial)
	local P = Config.Practice
	if not tutorial and not Tutorial.drill(drillId) then
		return
	end
	local l = LobbyService.create(plr, { mode = P.Mode, privacy = "Public", fill = true, botTier = P.BotTier }, false)
	if not l then
		return
	end
	l.hidden = true
	l.practice = true
	l.tutorial = tutorial == true or nil
	l.drill = not tutorial and drillId or nil
	LobbyService.launch(l)
end

function LobbyService.tutorial(plr)
	LobbyService.practice(plr, nil, true)
end

-- A tournament (Config.Tournament, Cups): a hidden lobby of your own against bot teams, its
-- modifiers on (MatchService), started at once; LobbyService.finished takes it round to round.
function LobbyService.enterCup(plr, key)
	local T = Config.Tournament
	local run = Cups.find(key, os.time())
	if not run then
		notify(plr, "That cup has ended. Pick one of the cups running now.")
		return
	end
	if LobbyService.lobbyOf(plr) or net.remoteOf[plr.UserId] then
		notify(plr, "You're already in a lobby: leave it first.")
		return
	end
	local c = run.cup
	local paid, why = reg.ProfileService.spendVP(plr, c.Entry)
	if not paid then
		notify(plr, why)
		return
	end
	local l = LobbyService.create(plr, { mode = run.mode, privacy = "Friends", fill = true, botTier = c.Bots[1], points = T.Points, sets = 1, timeouts = T.Timeouts }, false)
	if not l then
		reg.ProfileService.award(plr, reg.ProfileService.isDev(plr) and 0 or c.Entry, 0)
		return
	end
	-- the owner: "make it so you can play with friends": the run waits in a friends-only lobby
	-- (your Roblox friends in this server join it from Lobbies, paying the entry too, on your
	-- side) until you press Start
	l.cup = { key = c.Key, name = c.Name, round = 1, mods = Cups.encode(run.mods), paid = { [plr.UserId] = not reg.ProfileService.isDev(plr) or nil } }
	local names = {}
	for _, k in ipairs(run.mods) do
		table.insert(names, Cups.modifier(k).Name)
	end
	notify(plr, string.format("%s: %s. Friends in this server can join from Lobbies; press Start when you're ready.", c.Name, table.concat(names, ", ")))
	markDirty()
end

-- A tournament match is over: on to the next round after a win (straight back on this court),
-- else its payout (Cups.payout) and the run is over.
local function cupFinished(l)
	local T = Config.Tournament
	local res = l.cupResult
	l.cupResult = nil
	local c = Cups.cup(l.cup.key)
	local list = members(l)
	if res and c and res.won and l.cup.round < T.Rounds then
		l.cup.round = l.cup.round + 1
		l.botTier = c.Bots[l.cup.round]
		for _, plr in ipairs(list) do
			notify(plr, string.format("%s: you won round %d! Round %d of %d against %s bots is next.", c.Name, l.cup.round - 1, l.cup.round, T.Rounds, l.botTier))
		end
		l.state = "Queued"
		table.insert(courtQueue, 1, l.id)
		markDirty()
		return
	end
	if res and c then
		local vp, gold = Cups.payout(c, l.cup.round, res.won)
		for _, plr in ipairs(list) do
			if vp > 0 or gold > 0 then
				reg.ProfileService.award(plr, vp, gold)
			end
			if res.won then
				notify(plr, string.format("You won the %s! +%d VP and +%d Gold.", c.Name, vp, gold))
			elseif l.cup.round >= T.Rounds then
				notify(plr, string.format("Out in the final of the %s: +%d VP for getting there.", c.Name, vp))
			else
				notify(plr, string.format("Out of the %s in round %d. Better luck next run!", c.Name, l.cup.round))
			end
		end
	end
	dissolve(l)
end

-- Quick Match: the fullest open public quick lobby of that mode in any server (this server's on
-- a tie), or a new one here. localOnly: this server's only (a refused join elsewhere).
function LobbyService.quick(plr, mode, localOnly)
	if not plr.Parent then
		return nil
	end
	local list = {}
	for _, id in ipairs(order) do
		table.insert(list, lobbies[id])
	end
	local l = Lobbies.pickQuick(list, mode)
	if net.on and not localOnly then
		if os.clock() - net.dirAt > G.QuickFresh then
			readDirectory()
		end
		local others = {}
		for g, e in pairs(net.dir) do
			table.insert(others, { gid = g, view = e.view })
		end
		local g = Lobbies.pickQuickRemote(l, others, mode, Util.now(), G.QuickLead)
		if g and joinRemote(plr, g, nil, true) then
			return nil
		end
	end
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

-- A lobby with players from other servers always goes to a reserved server (a reserved one too).
local function canTeleportAcross()
	return L.ReservedServers and not RunService:IsStudio() and game.PlaceId ~= 0
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
	if ok and type(code) == "string" then
		local export = Lobbies.export(l)
		if hasRemote(l) then
			-- the players from other servers come too: their servers get the code and the lobby
			-- (and the shared list keeps both a while, for one that misses the message)
			l.launch = { code = code, x = export }
			refreshView(l)
			writeEntry(l, G.LaunchKeep)
			for job in pairs(remoteJobs(l)) do
				send(job, { k = "go", g = l.gid, code = code, x = export })
			end
		end
		if #list > 0 then
			ok = teleportPlayers(list, code, export)
		end
	else
		ok = false
	end
	if not ok and lobbies[l.id] and l.state == "Teleporting" then
		if not l.launch then
			dropRemotes(l, "solo") -- this court can't take them: they find another lobby
		end
		if lobbies[l.id] then
			for _, plr in ipairs(list) do
				notify(plr, "Couldn't open a private server. You're next in line for this court.")
			end
			queueForCourt(l)
		end
	end
end

function LobbyService.launch(l)
	local ok, why = Lobbies.canStart(l)
	if not ok then
		return false, why
	end
	if l.cup then
		l.hidden = true -- started: out of the list
		if l.cup.round == 1 then
			local names = {}
			for _, k in ipairs(Cups.parse(l.cup.mods)) do
				table.insert(names, Cups.modifier(k).Name)
			end
			for _, plr in ipairs(members(l)) do
				notify(plr, string.format("%s, round 1 of %d against %s bots. Modifiers: %s.", l.cup.name, Config.Tournament.Rounds, l.botTier, table.concat(names, ", ")))
			end
		end
	end
	if l.quick then
		-- the bots play at the strongest player's level (A up to S+)
		local tiers = {}
		for _, plr in ipairs(members(l)) do
			table.insert(tiers, plr:GetAttribute("Tier"))
		end
		l.botTier = Lobbies.quickBotTier(tiers)
	end
	if hasRemote(l) and not canTeleportAcross() then
		dropRemotes(l, "solo") -- (Studio) nowhere to take them: it plays here
		if lobbies[l.id] ~= l then
			return false, "empty"
		end
	end
	if not hasRemote(l) and (courtFree() or not canTeleport()) then
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
	if l.cup and #members(l) > 0 then
		cupFinished(l)
		return
	end
	if l.quick or l.tutorial or l.practice or l.cup or #members(l) == 0 then
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
-- across servers: what the other servers say
------------------------------------------------------------------------------------------

-- (to the host) a player elsewhere asks for a seat: { g, u, n: their name, f: a friend of the
-- host (their server checked), pw }
function HANDLERS.join(m)
	local u = tonumber(m.u)
	if not u then
		return
	end
	local l = lobbyByGid(m.g)
	if not l then
		send(m.from, { k = "no", g = m.g, u = u, why = "gone" })
		return
	end
	if l.remote and l.remote[u] then
		-- asked again: the seat is still theirs
		l.remote[u].job, l.remote[u].seen = m.from, os.clock()
		send(m.from, { k = "ok", g = m.g, u = u, v = l.v })
		return
	end
	local ok, why = Lobbies.canJoin(l, u, m.pw, m.f == true)
	if ok and (l.hidden or Players:GetPlayerByUserId(u)) then
		ok, why = false, "started"
	end
	if ok and not Lobbies.seat(l, u) then
		ok, why = false, "full"
	end
	if not ok then
		send(m.from, { k = "no", g = m.g, u = u, why = why })
		return
	end
	-- a seat they held in another lobby here is let go
	local held = {}
	for _, id in ipairs(order) do
		local other = lobbies[id]
		if other and other ~= l and other.remote and other.remote[u] then
			table.insert(held, other)
		end
	end
	for _, other in ipairs(held) do
		removeRemote(other, u, nil)
	end
	l.remote = l.remote or {}
	l.remote[u] = { job = m.from, name = type(m.n) == "string" and string.sub(m.n, 1, 40) or "Player", seen = os.clock(), at = os.clock() }
	refreshView(l)
	send(m.from, { k = "ok", g = m.g, u = u, v = l.v })
	markDirty()
end

function HANDLERS.leave(m)
	local l = lobbyByGid(m.g)
	local u = tonumber(m.u)
	if l and u and l.remote and l.remote[u] and l.remote[u].job == m.from then
		removeRemote(l, u, nil)
	end
end

function HANDLERS.team(m)
	local l = lobbyByGid(m.g)
	local u = tonumber(m.u)
	if l and u and l.remote and l.remote[u] and l.state == "Open" and Lobbies.swap(l, u) then
		markDirty()
	end
end

-- "These players of mine are still in your lobby": their seats are kept; a seat of that server's
-- it doesn't list any more (given a moment to hear the yes) is let go.
function HANDLERS.keep(m)
	local l = lobbyByGid(m.g)
	if not l then
		send(m.from, { k = "close", g = m.g, why = "gone" })
		return
	end
	local still = {}
	for _, u in ipairs(type(m.us) == "table" and m.us or {}) do
		still[tonumber(u) or 0] = true
	end
	local now = os.clock()
	local gone = {}
	for u, r in pairs(l.remote or {}) do
		if r.job == m.from then
			if still[u] then
				r.seen = now
			elseif now - r.at > 5 then
				table.insert(gone, u)
			end
		end
	end
	for _, u in ipairs(gone) do
		if lobbies[l.id] == l then
			removeRemote(l, u, nil)
		end
	end
end

-- (from the host) the answer to a join
function HANDLERS.ok(m)
	local u = tonumber(m.u)
	local r = u and net.remoteOf[u]
	if r and r.g == m.g then
		r.pending, r.v, r.job = nil, tonumber(m.v) or 0, m.from
		markDirty()
	elseif u then
		send(m.from, { k = "leave", g = m.g, u = u }) -- they moved on meanwhile: the seat goes back
	end
end

function HANDLERS.no(m)
	local u = tonumber(m.u)
	local r = u and net.remoteOf[u]
	if not (r and r.g == m.g and r.pending) then
		return
	end
	net.remoteOf[u] = nil
	local plr = Players:GetPlayerByUserId(u)
	if plr and r.quick then
		task.defer(LobbyService.quick, plr, r.mode, true)
	else
		notify(plr, NOTICES[m.why] or "Can't join that lobby.")
	end
	markDirty()
end

-- the lobby changed (its view, or just its version when the view didn't fit the message)
function HANDLERS.st(m)
	local watched = false
	for _, r in pairs(net.remoteOf) do
		if r.g == m.g then
			watched = true
		end
	end
	if not watched then
		return
	end
	if type(m.view) == "table" then
		takeView(m.g, m.from, m.view)
	else
		task.spawn(fetchView, m.g)
	end
end

function HANDLERS.out(m)
	local u = tonumber(m.u)
	local r = u and net.remoteOf[u]
	if r and r.g == m.g and not r.going then
		net.remoteOf[u] = nil
		local plr = Players:GetPlayerByUserId(u)
		if plr and r.quick then
			task.defer(LobbyService.quick, plr, r.mode, true)
		else
			notify(plr, OUT_TEXT[m.why] or "You're no longer in that lobby.")
		end
		markDirty()
	end
end

function HANDLERS.close(m)
	closeRemote(m.g, m.why)
end

function HANDLERS.go(m)
	goAcross(m.g, m.code, m.x)
end

local function onMessage(msg)
	local m = type(msg) == "table" and msg.Data or nil
	if type(m) ~= "table" or m.fv ~= G.Format or type(m.k) ~= "string" or type(m.from) ~= "string" or type(m.g) ~= "string" then
		return
	end
	local fn = HANDLERS[m.k]
	if fn then
		local ok, err = pcall(fn, m)
		if not ok then
			warn("[SpikeRush] lobby message " .. m.k .. ": " .. tostring(err))
		end
	end
end

-- Every 0.25 s: my lobbies' views and entries, remote seats gone quiet, my players' seats elsewhere
-- (answers that never came, "still here", a fresh look) and, while anyone here is in the menus,
-- the other servers' lobbies.
local function netTick()
	if not net.on then
		return
	end
	local clock = os.clock()
	local ids = {}
	for _, id in ipairs(order) do
		table.insert(ids, id)
	end
	for _, id in ipairs(ids) do
		local l = lobbies[id]
		if l and hasRemote(l) then
			local lost = {}
			for u, r in pairs(l.remote) do
				if clock - r.seen > G.SeatLease then
					table.insert(lost, u)
				end
			end
			for _, u in ipairs(lost) do
				if lobbies[id] == l then
					removeRemote(l, u, "lost")
				end
			end
		end
		l = lobbies[id]
		if l then
			refreshView(l)
			if shared(l) then
				local since = clock - (l.writtenAt or -100)
				if (l.viewDirty and since >= G.Write) or since >= G.Refresh then
					writeEntry(l, l.launch and G.LaunchKeep or nil)
				end
			elseif l.listed then
				unlist(l)
			end
		end
	end

	local held = {}
	for u, r in pairs(net.remoteOf) do
		local plr = Players:GetPlayerByUserId(u)
		if not plr then
			net.remoteOf[u] = nil
		elseif r.pending and clock - r.since > G.JoinWait then
			net.remoteOf[u] = nil
			send(r.job, { k = "leave", g = r.g, u = u }) -- in case the join gets through late
			if r.quick then
				task.defer(LobbyService.quick, plr, r.mode, true)
			else
				notify(plr, "That lobby's server didn't answer. Try again.")
			end
			markDirty()
		else
			local h = held[r.g]
			if not h then
				h = { job = r.job, us = {}, going = false }
				held[r.g] = h
			end
			if r.going then
				h.going = true
			else
				table.insert(h.us, u)
			end
		end
	end
	for g in pairs(net.views) do
		if not held[g] then
			net.views[g] = nil
		end
	end
	if clock - net.keepAt >= G.Keep then
		net.keepAt = clock
		for g, h in pairs(held) do
			if #h.us > 0 then
				send(h.job, { k = "keep", g = g, us = h.us })
			end
		end
	end
	if clock - net.watchAt >= G.Watch then
		net.watchAt = clock
		for g, h in pairs(held) do
			if not h.going then
				task.spawn(fetchView, g)
			end
		end
	end

	local browsing = false
	for _, plr in ipairs(Players:GetPlayers()) do
		if not (reg.TeamService.inMatch and reg.TeamService.entityForPlayer(plr)) then
			browsing = true
		end
	end
	if browsing and not net.reading and clock - net.dirAt >= G.Read + G.ReadPerEntry * countOf(net.dir) then
		task.spawn(readDirectory)
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
	local r = net.remoteOf[plr.UserId]
	if net.on then
		-- the other servers' open lobbies after this server's, the fullest first
		local others = {}
		for g, e in pairs(net.dir) do
			local v = e.view
			local mine = r ~= nil and r.g == g
			if (v.state == "Open" or mine) and not v.hidden and (v.privacy ~= "Friends" or isFriend(plr, tonumber(v.host))) then
				local s = Lobbies.remoteSummary(v, g, plr.UserId)
				s.mine = mine
				table.insert(others, s)
			end
		end
		table.sort(others, function(a, b)
			if a.count ~= b.count then
				return a.count > b.count
			end
			return a.id < b.id
		end)
		for _, s in ipairs(others) do
			if #list >= G.ListMax then
				break
			end
			table.insert(list, s)
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
		mine.practice = l.practice
		mine.cup = l.cup and { key = l.cup.key, name = l.cup.name, round = l.cup.round, mods = l.cup.mods } or nil
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
				table.insert(mine[side], { id = u, name = nameOf(l, u), host = u == l.host, away = l.remote ~= nil and l.remote[u] ~= nil or nil })
			end
		end
	elseif r and net.views[r.g] then
		-- a seat in another server's lobby
		mine = Lobbies.remoteMine(net.views[r.g].view, r.g, plr.UserId, r.pending)
		if r.going then
			mine.state = "Teleporting"
		end
	end
	return {
		list = list,
		mine = mine,
		court = { busy = reg.TeamService.inMatch, queue = #courtQueue },
		teleport = canTeleport(),
		global = net.on,
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
	local remote = net.remoteOf[plr.UserId]
	if remote and remote.going and op ~= "list" and op ~= "rejoin" then
		return -- on the way to the match
	end
	if op == "create" then
		LobbyService.create(plr, a, false)
	elseif op == "practice" then
		LobbyService.practice(plr, a)
	elseif op == "tutorial" then
		LobbyService.tutorial(plr)
	elseif op == "cup" then
		if type(a) == "string" then
			LobbyService.enterCup(plr, a)
		end
	elseif op == "quick" then
		local mode = tonumber(a)
		if mode == 1 or mode == 2 or mode == 3 then
			LobbyService.quick(plr, mode)
		end
	elseif op == "join" then
		local job, gid = parseGid(a)
		if job == net.job and gid then
			LobbyService.join(plr, gid, b)
		elseif job and net.on then
			joinRemote(plr, a, b, false)
		elseif tonumber(a) then
			LobbyService.join(plr, tonumber(a), b)
		end
	elseif op == "leave" then
		if remote then
			leaveRemote(plr)
			return
		end
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
		if remote then
			if not remote.pending then
				send(remote.job, { k = "team", g = remote.g, u = plr.UserId })
			end
			return
		end
		local l = LobbyService.lobbyOf(plr)
		if l and l.state == "Open" and not l.cup and Lobbies.swap(l, plr.UserId) then
			markDirty()
		end
	elseif op == "kick" then
		local l = LobbyService.lobbyOf(plr)
		local target = tonumber(a)
		if l and l.host == plr.UserId and target and target ~= plr.UserId and Lobbies.teamOf(l, target) then
			if l.remote and l.remote[target] then
				removeRemote(l, target, "kicked")
				return
			end
			cupRefund(l, target)
			Lobbies.remove(l, target)
			memberOf[target] = nil
			notify(Players:GetPlayerByUserId(target), "The host removed you from the lobby.")
			markDirty()
		end
	elseif op == "settings" then
		local l = LobbyService.lobbyOf(plr)
		if not l or l.host ~= plr.UserId or l.state ~= "Open" or l.cup then
			return
		end
		local s, why = Lobbies.settings(a)
		if not s then
			notify(plr, why == "password" and string.format("Pick a password of %d to %d letters or digits.", L.PasswordMin, L.PasswordMax) or "Those settings don't work.")
			return
		end
		for _, u in ipairs(Lobbies.configure(l, s)) do
			if l.remote and l.remote[u] then
				local rr = l.remote[u]
				l.remote[u] = nil
				send(rr.job, { k = "out", g = l.gid, u = u, why = "smaller" })
			else
				memberOf[u] = nil
				notify(Players:GetPlayerByUserId(u), "The lobby got smaller and you were moved out.")
			end
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

-- The other servers' lobbies, the inbox and BindToClose (Config.Lobby.Global).
local function startNet()
	if not G or not G.Enabled or game.PlaceId == 0 then
		return
	end
	net.job = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap(G.Map)
	end)
	if not ok or not map then
		warn("[SpikeRush] lobbies across servers are off: " .. tostring(map))
		return
	end
	net.map = map
	net.on = true
	task.spawn(function()
		local subscribed, err = pcall(function()
			MessagingService:SubscribeAsync(G.Inbox .. net.job, onMessage)
		end)
		if not subscribed then
			-- nobody could reach this server's lobbies: they stay out of the shared list
			warn("[SpikeRush] lobbies across servers are off (inbox): " .. tostring(err))
			net.on = false
			for _, id in ipairs(order) do
				local l = lobbies[id]
				if l and l.listed then
					l.listed = false
					pcall(function()
						net.map:RemoveAsync(l.gid)
					end)
				end
			end
			markDirty()
		end
	end)
	game:BindToClose(function()
		-- the shutdown: this server's lobbies leave the shared list, their remote players are told
		for _, id in ipairs(order) do
			local l = lobbies[id]
			if l and l.listed and not l.launch then
				pcall(function()
					net.map:RemoveAsync(l.gid)
				end)
				for job in pairs(remoteJobs(l)) do
					send(job, { k = "close", g = l.gid, why = "gone" }, true)
				end
			end
		end
	end)
end

function LobbyService.init(r)
	reg = r
	startNet()
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
		net.remoteOf[plr.UserId] = nil
		friendCache[plr.UserId] = nil
		lastRequest[plr] = nil
		markDirty()
	end)
	TeleportService.TeleportInitFailed:Connect(function(plr)
		local remote = net.remoteOf[plr.UserId]
		if remote and remote.going then
			net.remoteOf[plr.UserId] = nil
			notify(plr, "The teleport to that match failed.")
			markDirty()
			return
		end
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
			local ok, err = pcall(netTick)
			if not ok then
				warn("[SpikeRush] lobbies across servers: " .. tostring(err))
			end
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
