-- The admin panel's server side (Home's Admin button; developers only, Config.Developers). Its
-- requests arrive on the "Admin" remote and every one is answered there ({ msg, events }):
--   ("state")                  -> the running events
--   ("event", kind, minutes)   -> 2x VP or 2x Gold (Config.Admin) in every server for that long
--   ("stop", kind)             -> end it everywhere
--   ("announce", text)         -> through Roblox's text filter, then to every player in every server
--   ("give", username, grant)  -> VP, Gold, lucky spins and characters to anyone by username (or
--                                 user id)
--                                 (ProfileService.giveUser: now, or through their mail)
-- Events are kept in a DataStore (a server that starts later reads them, and every server reads
-- them again each PollInterval) and pushed at once over MessagingService, as are announcements
-- and the "open your mail" pings for gifts. The running ones are ReplicatedStorage attributes
-- (Event_VP, Event_Gold: the unix time each ends, 0 when off) for the menus.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)

local AdminService = {}
local reg
local A = Config.Admin

local TOPIC_LIVE, TOPIC_NOTICE, TOPIC_MAIL = "SpikeRushLive", "SpikeRushNotice", "SpikeRushMail"

local events = {} -- kind -> the unix time it ends
local liveStore = nil
local lastOp = {}
local shownNotice = {} -- ids of the notices this server has shown (its own come back to it)

local function publish(topic, data)
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(topic, data)
		end)
		if not ok then
			warn("[SpikeRush] MessagingService publish (" .. topic .. "): " .. tostring(err))
		end
	end)
end

-- The running events as attributes, for every client.
local function writeEvents()
	events = Economy.running(events, os.time())
	for _, kind in ipairs(A.Events) do
		ReplicatedStorage:SetAttribute("Event_" .. kind, events[kind] or 0)
	end
end

-- What the running events multiply `kind` ("VP" or "Gold") by right now (MatchService's rewards).
function AdminService.multiplier(kind)
	return Economy.multiplier(events, kind, os.time())
end

-- Events heard from another server ({ kind = end, 0 to stop }), or read from the store (whole:
-- anything it doesn't list has ended).
local function takeEvents(data, whole)
	if type(data) ~= "table" then
		return
	end
	for _, kind in ipairs(A.Events) do
		local v = tonumber(data[kind])
		if v then
			events[kind] = v > 0 and v or nil
		elseif whole then
			events[kind] = nil
		end
	end
	writeEvents()
end

local function storeEvents()
	if not liveStore then
		return
	end
	local all = {}
	for _, kind in ipairs(A.Events) do
		all[kind] = events[kind] or 0
	end
	task.spawn(function()
		pcall(function()
			liveStore:SetAsync("events", all)
		end)
	end)
end

local function readEvents()
	if not liveStore then
		return
	end
	local ok, data = pcall(function()
		return liveStore:GetAsync("events")
	end)
	if ok and type(data) == "table" then
		takeEvents(data, true)
	end
end

-- A notice for every player here: { id, kind ("announce" or "event"), text, from }.
local function showNotice(n)
	if type(n) ~= "table" or type(n.text) ~= "string" or type(n.id) ~= "string" or shownNotice[n.id] then
		return
	end
	shownNotice[n.id] = true
	Net.get("Notice"):FireAllClients({ kind = n.kind == "event" and "event" or "announce", text = n.text, from = n.from, seconds = A.AnnounceSeconds })
end

local function notify(n)
	n.id = HttpService:GenerateGUID(false)
	showNotice(n)
	publish(TOPIC_NOTICE, n)
end

-- Tells whichever server a player is in to open their mail (ProfileService.giveUser).
function AdminService.pingMail(userId)
	publish(TOPIC_MAIL, userId)
end

local function isAdmin(plr)
	local profile = reg.ProfileService.peek(plr)
	return profile ~= nil and profile.dev == true
end

local function reply(plr, msg)
	Net.get("Admin"):FireClient(plr, { msg = msg, events = Economy.running(events, os.time()) })
end

local function eventName(kind)
	return kind == "VP" and "V Points" or kind
end

local function onAdmin(plr, op, a, b)
	if not isAdmin(plr) then
		return
	end
	local now = os.clock()
	if op ~= "state" and lastOp[plr] and now - lastOp[plr] < 0.5 then
		return
	end
	lastOp[plr] = now
	if op == "state" then
		reply(plr)
	elseif op == "event" then
		local minutes = tonumber(b)
		if not Economy.isEvent(a) or not Economy.isDuration(minutes) then
			return
		end
		events[a] = os.time() + minutes * 60
		writeEvents()
		storeEvents()
		publish(TOPIC_LIVE, { [a] = events[a] })
		notify({ kind = "event", text = string.format("%dx %s for the next %d minutes! Every match pays double.", A.Multiplier, eventName(a), minutes) })
		reply(plr, string.format("%dx %s is on in every server for %d minutes.", A.Multiplier, a, minutes))
	elseif op == "stop" then
		if not Economy.isEvent(a) then
			return
		end
		events[a] = nil
		writeEvents()
		storeEvents()
		publish(TOPIC_LIVE, { [a] = 0 })
		reply(plr, string.format("%dx %s stopped.", A.Multiplier, a))
	elseif op == "announce" then
		if type(a) ~= "string" then
			return
		end
		local text = string.match((string.gsub(a, "%s+", " ")), "^%s*(.-)%s*$")
		text = string.sub(text, 1, A.AnnounceMax)
		if text == "" then
			reply(plr, "Write the announcement first.")
			return
		end
		task.spawn(function()
			local ok, filtered = pcall(function()
				local result = TextService:FilterStringAsync(text, plr.UserId, Enum.TextFilterContext.PublicChat)
				return result:GetNonChatStringForBroadcastAsync()
			end)
			if not ok or type(filtered) ~= "string" then
				reply(plr, "Roblox's text filter couldn't check it. Try again in a moment.")
				return
			end
			notify({ kind = "announce", text = filtered, from = plr.DisplayName })
			reply(plr, "Announced in every server.")
		end)
	elseif op == "give" then
		local name = type(a) == "string" and string.match(a, "^%s*([%w_]+)%s*$") or nil
		local g = Economy.cleanGrant(b)
		if not name or Economy.isEmpty(g) then
			reply(plr, "Enter a username (or a user id) and something to give.")
			return
		end
		task.spawn(function()
			local userId, why = reg.ProfileService.findUser(name)
			if not userId then
				reply(plr, why)
				return
			end
			local sent, why = reg.ProfileService.giveUser(userId, g, nil, "A gift from the developers.")
			if sent then
				local where = Players:GetPlayerByUserId(userId) and "now" or "when they're next in the game (at once if they're online)"
				reply(plr, string.format("Gave %s %s: they get it %s.", name, Economy.describe(g), where))
			else
				reply(plr, why or "That didn't work.")
			end
		end)
	end
end

function AdminService.init(r)
	reg = r
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(A.LiveStore)
	end)
	liveStore = ok and store or nil
	writeEvents()
	Net.get("Admin").OnServerEvent:Connect(onAdmin)
	Players.PlayerRemoving:Connect(function(plr)
		lastOp[plr] = nil
	end)
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC_LIVE, function(msg)
				takeEvents(msg.Data, false)
			end)
		end)
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC_NOTICE, function(msg)
				showNotice(msg.Data)
			end)
		end)
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC_MAIL, function(msg)
				local plr = Players:GetPlayerByUserId(tonumber(msg.Data) or 0)
				if plr then
					reg.ProfileService.checkMail(plr)
				end
			end)
		end)
	end)
	-- the events from before this server started, then again now and then (a missed message, an
	-- event that ended); and every player's mail, in case a ping was missed
	task.spawn(function()
		readEvents()
		while true do
			task.wait(A.PollInterval)
			readEvents()
			writeEvents()
			for _, plr in ipairs(Players:GetPlayers()) do
				task.spawn(reg.ProfileService.checkMail, plr)
			end
		end
	end)
end

return AdminService
