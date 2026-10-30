-- The admin panel's server side (Home's Admin button; developers only, Config.Developers). Its
-- requests arrive on the "Admin" remote and every one is answered there ({ msg, events }):
--   ("state")                  -> the running events
--   ("event", kind, minutes, mul) -> VP, Gold or Luck at 2x to 16x (Config.Admin.EventMuls) in every
--                                 server for that long
--   ("stop", kind)             -> end it everywhere
--   ("announce", text)         -> through Roblox's text filter, then to every player in every server
--   ("give", username, grant)  -> VP, Gold, lucky spins, characters and cosmetics to anyone by
--                                 username (or user id)
--                                 (ProfileService.giveUser: now, or through their mail)
--   ("server")                 -> the admin alone into a new reserved server, to try lobbies across
--                                 servers (Config.Lobby.Global) with someone who stays behind
--   ("giveAll", grant)         -> VP, Gold, lucky spins (and the rest of a grant) to everyone online
--                                 in every server, once each (nobody offline: no mail)
--   ("wipe", username)         -> reset someone's match stats (off those leaderboards)
--   ("rankReset", username)    -> reset someone's ranked RP, record and best rank (an alt
--                                 farmer's), off the ranked board
--   ("admins")                 -> the whitelist: who the game's owner lets into the panel
--   ("adminAdd", username)     -> let someone in (by username or user id)
--   ("adminRemove", userId)    -> and out again
--                                 (the whitelist's three: the game's owner alone, never Studio's
--                                 stand-ins; Config.Admin.WhitelistStore)
-- Events are kept in a DataStore (a server that starts later reads them, and every server reads
-- them again each PollInterval) and pushed at once over MessagingService, as are announcements
-- and the "open your mail" pings for gifts. The running ones are ReplicatedStorage attributes
-- (Event_VP, Event_Gold, Event_Luck: the unix time each ends, 0 when off; EventMul_<kind>: its
-- strength) for the menus.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
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

local TOPIC_LIVE, TOPIC_NOTICE, TOPIC_MAIL, TOPIC_ADMINS, TOPIC_GIFTALL = "SpikeRushLive", "SpikeRushNotice", "SpikeRushMail", "SpikeRushAdmins", "SpikeRushGiftAll"

local events = {} -- kind -> the unix time it ends
local liveStore = nil
local lastOp = {}
local shownNotice = {} -- ids of the notices this server has shown (its own come back to it)
-- the admin whitelist (Economy.cleanAdmins): who the game's owner lets into the panel
local admins = {} -- tostring(userId) -> { n = username, t = when added }
local adminStore = nil
local ownerOf = {} -- player -> true when they own the game (looked up as they join)

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

-- each event's strength while it runs (Config.Admin.EventMuls: 2x to 16x), by kind
local muls = {}

local function cleanMul(m)
	m = tonumber(m)
	for _, v in ipairs(A.EventMuls) do
		if v == m then
			return v
		end
	end
	return A.Multiplier
end

-- The running events as attributes, for every client, with each one's strength.
local function writeEvents()
	events = Economy.running(events, os.time())
	for _, kind in ipairs(A.Events) do
		ReplicatedStorage:SetAttribute("Event_" .. kind, events[kind] or 0)
		ReplicatedStorage:SetAttribute("EventMul_" .. kind, muls[kind] or A.Multiplier)
	end
end

-- What the running events multiply `kind` ("VP", "Gold" or "Luck") by right now (MatchService's
-- rewards, ProfileService's VP and recruits): each event at the strength it was started at.
function AdminService.multiplier(kind)
	local m = Economy.multiplier(events, kind, os.time())
	if m > 1 then
		return muls[kind] or A.Multiplier
	end
	return m
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
	for _, kind in ipairs(A.Events) do
		if data[kind .. "Mul"] ~= nil then
			muls[kind] = cleanMul(data[kind .. "Mul"]) -- (VPMul, GoldMul, LuckMul)
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
		all[kind .. "Mul"] = muls[kind] or A.Multiplier
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

-- The game's owner: the account that owns it, or the owner (or Owner role) of the group that does
-- (ProfileService.ownsGame), looked up as they join (it asks Roblox). The only one who sees and changes the admin whitelist
-- (the owner, 2026-10-16: "add a whitelist to the admin panel that only i can access"). Studio's
-- every-session developer doesn't count here: a collaborator's playtest writes the live list.
local function lookUpOwner(plr)
	local yes = reg.ProfileService.ownsGame(plr)
	if yes and plr.Parent then
		ownerOf[plr] = true
		reg.ProfileService.pushTo(plr) -- (their admin panel shows the whitelist)
	end
end

function AdminService.isOwner(plr)
	return ownerOf[plr] == true
end

-- Whether the game's owner has let this user into the admin panel.
function AdminService.whitelisted(userId)
	return admins[tostring(userId)] ~= nil
end

-- A new whitelist (read, heard from another server, or just written): anyone in this server it
-- lets in or out is told, and their Admin button shows or goes.
local function takeAdmins(list)
	local before = admins
	admins = list
	for _, plr in ipairs(Players:GetPlayers()) do
		local key = tostring(plr.UserId)
		local was, now = before[key] ~= nil, list[key] ~= nil
		if was ~= now then
			reg.ProfileService.pushTo(plr, now and "You're an admin now: the Admin button is on Home." or "You're not an admin anymore.")
		end
	end
end

local function readAdmins()
	if not adminStore then
		return
	end
	local ok, data = pcall(function()
		return adminStore:GetAsync("list")
	end)
	if ok then
		takeAdmins(Economy.cleanAdmins(data))
	end
end

-- Lets a user into the panel (add) or out of it, in the store, then in every server. Returns true,
-- or false and why.
local function writeAdmins(userId, name, add)
	if not adminStore then
		return false, "The admin list can't be saved here (DataStores are off)."
	end
	local result, full = nil, false
	local ok, err = pcall(function()
		adminStore:UpdateAsync("list", function(old)
			local list = Economy.cleanAdmins(old)
			local key = tostring(userId)
			full = false
			if add and not list[key] then
				local n = 0
				for _ in pairs(list) do
					n = n + 1
				end
				if n >= A.WhitelistMax then
					full = true
					return nil
				end
				list[key] = { n = name, t = os.time() }
			elseif not add then
				list[key] = nil
			end
			result = list
			return list
		end)
	end)
	if full then
		return false, string.format("The list is full (%d admins): remove someone first.", A.WhitelistMax)
	end
	if not ok or not result then
		return false, "Couldn't save the admin list: " .. tostring(err)
	end
	takeAdmins(result)
	publish(TOPIC_ADMINS, os.time())
	return true
end

-- A gift to everyone online (the owner, 2026-10-16: "add global +lucky spins, vpoints, gold, and such
-- only for those online"): every player in this server gets it once (its id), with a notice.
local giftsSeen = {}
local function takeGiftAll(data)
	if type(data) ~= "table" or type(data.id) ~= "string" or giftsSeen[data.id] then
		return 0
	end
	giftsSeen[data.id] = true
	local g = Economy.cleanGrant(data.g)
	if Economy.isEmpty(g) then
		return 0
	end
	local n = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if reg.ProfileService.peek(plr) then
			reg.ProfileService.grant(plr, g, "A gift for everyone online: " .. Economy.describe(g) .. "!")
			n = n + 1
		end
	end
	return n
end

-- Developers (Config.Developers), and whoever the owner's whitelist lets in.
local function isAdmin(plr)
	local profile = reg.ProfileService.peek(plr)
	return profile ~= nil and (profile.dev == true or AdminService.whitelisted(plr.UserId))
end

local function reply(plr, msg, extra)
	local data = { msg = msg, events = Economy.running(events, os.time()) }
	for k, v in pairs(extra or {}) do
		data[k] = v
	end
	Net.get("Admin"):FireClient(plr, data)
end

-- Who has each give-only card (Config.Admin.CardOwnersStore): written when the admin panel gives
-- one and when Take card takes it back; key = the card, value = { [userId] = { n = name, t } }.
local ownersStore, mailStoreA = nil, nil
local function noteOwner(key, userId, name, has)
	if not ownersStore then
		return
	end
	pcall(function()
		ownersStore:UpdateAsync(key, function(old)
			local t = type(old) == "table" and old or {}
			t[tostring(userId)] = has and { n = name, t = os.time() } or nil
			return t
		end)
	end)
end

local function cardName(key)
	for _, c in ipairs(Config.Cards.List) do
		if c.Key == key then
			return c.Name
		end
	end
	return key
end

local function isGrantCard(key)
	for _, c in ipairs(Config.Cards.List) do
		if c.Key == key then
			return c.Grant == true
		end
	end
	return false
end

-- Everyone with `key`: the list, plus gifts of it still unopened in anyone's mail (sent before
-- the list was kept, or not delivered yet), which join the list. { { id, name, pending } }
local function cardOwners(key)
	local found = {}
	local ok, data = pcall(function()
		return ownersStore and ownersStore:GetAsync(key)
	end)
	if ok and type(data) == "table" then
		for id, v in pairs(data) do
			local uid = tonumber(id)
			if uid then
				found[uid] = { id = uid, name = type(v) == "table" and v.n or tostring(uid) }
			end
		end
	end
	if mailStoreA then
		pcall(function()
			local pages = mailStoreA:ListKeysAsync("u_", 100)
			local seen = 0
			while seen < 200 do
				for _, k in ipairs(pages:GetCurrentPage()) do
					seen = seen + 1
					local uid = tonumber(string.match(k.KeyName, "^u_(%d+)$"))
					local okM, mail = pcall(function()
						return mailStoreA:GetAsync(k.KeyName)
					end)
					local has = nil
					for _, m in ipairs(okM and type(mail) == "table" and type(mail.list) == "table" and mail.list or {}) do
						if type(m) == "table" and type(m.g) == "table" and type(m.g.Cards) == "table" and table.find(m.g.Cards, key) then
							has = true
						elseif type(m) == "table" and m.takeCard == key then
							has = false
						end
					end
					if uid and has then
						found[uid] = found[uid] or { id = uid }
						found[uid].pending = true
					end
				end
				if pages.IsFinished then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
	end
	local list = {}
	for uid, e in pairs(found) do
		if not e.name then
			local okN, n = pcall(function()
				return Players:GetNameFromUserIdAsync(uid)
			end)
			e.name = okN and n or tostring(uid)
			if e.pending then
				noteOwner(key, uid, e.name, true) -- on the list from now on
			end
		end
		table.insert(list, e)
	end
	table.sort(list, function(x, y)
		return string.lower(x.name) < string.lower(y.name)
	end)
	return list
end

local function eventName(kind)
	return A.EventNames[kind] or kind
end

local function onAdmin(plr, op, a, b, c)
	if not isAdmin(plr) then
		return
	end
	local now = os.clock()
	if op ~= "state" and lastOp[plr] and now - lastOp[plr] < 0.5 then
		return
	end
	lastOp[plr] = now
	if op == "state" then
		reply(plr, nil, AdminService.isOwner(plr) and { admins = Economy.adminList(admins) } or nil)
	elseif op == "admins" or op == "adminAdd" or op == "adminRemove" then
		-- the whitelist: the game's owner alone
		if not AdminService.isOwner(plr) then
			reply(plr, "Only the game's owner can see and change the admins.")
			return
		end
		if op == "admins" then
			reply(plr, nil, { admins = Economy.adminList(admins) })
			return
		end
		task.spawn(function()
			local userId, why = nil, nil
			if op == "adminRemove" then
				userId = tonumber(a)
			else
				userId, why = reg.ProfileService.findUser(a)
			end
			if not userId then
				reply(plr, why or "That isn't a username or a user id.")
				return
			end
			if op == "adminAdd" and userId == plr.UserId then
				reply(plr, "You own the game: the panel is always yours.")
				return
			end
			local row = admins[tostring(userId)]
			local name = row and row.n or nil
			if not name then
				local okN, n = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				name = okN and type(n) == "string" and n or tostring(userId)
			end
			local done, why2 = writeAdmins(userId, name, op == "adminAdd")
			if done then
				reply(plr, op == "adminAdd" and (name .. " can use the admin panel now.") or (name .. " isn't an admin anymore."), { admins = Economy.adminList(admins) })
			else
				reply(plr, why2)
			end
		end)
	elseif op == "event" then
		local minutes = tonumber(b)
		if not Economy.isEvent(a) or not Economy.isDuration(minutes) then
			return
		end
		-- (at the strength picked: `c`, 2x to 16x)
		local mul = cleanMul(c)
		muls[a] = mul
		events[a] = os.time() + minutes * 60
		writeEvents()
		storeEvents()
		publish(TOPIC_LIVE, { [a] = events[a], [a .. "Mul"] = mul })
		notify({ kind = "event", text = string.format("%dx %s for the next %d minutes! %s", mul, eventName(a), minutes, A.EventLines[a] or "") })
		reply(plr, string.format("%dx %s is on in every server for %d minutes.", mul, a, minutes))
	elseif op == "stop" then
		if not Economy.isEvent(a) then
			return
		end
		local mul = muls[a] or A.Multiplier
		events[a] = nil
		writeEvents()
		storeEvents()
		publish(TOPIC_LIVE, { [a] = 0 })
		reply(plr, string.format("%dx %s stopped.", mul, a))
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
				for _, key in ipairs(g.Cards or {}) do
					if isGrantCard(key) then
						noteOwner(key, userId, name, true)
					end
				end
				local where = Players:GetPlayerByUserId(userId) and "now" or "when they're next in the game (at once if they're online)"
				reply(plr, string.format("Gave %s %s: they get it %s.", name, Economy.describe(g), where))
			else
				reply(plr, why or "That didn't work.")
			end
		end)
	elseif op == "giveAll" then
		local g = Economy.cleanGrant(a)
		if Economy.isEmpty(g) then
			reply(plr, "Enter something to give everyone online.")
			return
		end
		local data = { id = HttpService:GenerateGUID(false), g = g }
		local here = takeGiftAll(data) -- this server at once; the rest hear it
		publish(TOPIC_GIFTALL, data)
		reply(plr, string.format("Gave everyone online %s (%d in this server, and every other server's players now).", Economy.describe(g), here))
	elseif op == "takeCard" then
		-- take a given card back (b: its key) from a username or user id
		local name = type(a) == "string" and string.match(a, "^%s*([%w_]+)%s*$") or nil
		if not name or type(b) ~= "string" then
			reply(plr, "Enter a username (or a user id) and pick the card to take back.")
			return
		end
		task.spawn(function()
			local userId, why = reg.ProfileService.findUser(name)
			if not userId then
				reply(plr, why)
				return
			end
			local done, when = reg.ProfileService.takeCardFrom(userId, b)
			if done then
				noteOwner(b, userId, name, false)
				reply(plr, string.format("Took the %s card back from %s: %s.", cardName(b), name, when), { owners = { card = b, list = cardOwners(b) } })
			else
				reply(plr, when or "That didn't work.")
			end
		end)
	elseif op == "cardOwners" then
		-- who has a give-only card (a: its key)
		if type(a) ~= "string" or not isGrantCard(a) then
			return
		end
		task.spawn(function()
			local list = cardOwners(a)
			reply(plr, string.format("%d %s the %s card.", #list, #list == 1 and "player has" or "players have", cardName(a)), { owners = { card = a, list = list } })
		end)
	elseif op == "wipe" or op == "rankReset" then
		-- reset someone's match stats (wins, matches, kills, aces, blocks, MVPs, streaks) and take
		-- them off those leaderboards; their VP, Gold, characters and purchases stay. rankReset: their
		-- ranked RP, wins, losses, peak and best rank instead, and off the ranked board
		local rank = op == "rankReset"
		local name = type(a) == "string" and string.match(a, "^%s*([%w_]+)%s*$") or nil
		if not name then
			reply(plr, "Enter a username (or a user id) to reset.")
			return
		end
		task.spawn(function()
			local userId, why = reg.ProfileService.findUser(name)
			if not userId then
				reply(plr, why)
				return
			end
			local done, why2 = reg.ProfileService.wipeUser(userId, rank)
			if done then
				local where = Players:GetPlayerByUserId(userId) and "now" or "when they're next in the game (at once if they're online)"
				reply(plr, string.format(rank and "Reset %s's rank to Bronze I (0 RP): it applies %s. The ranked board drops them at its next refresh." or "Reset %s's match stats: it applies %s. The leaderboards drop them at their next refresh.", name, where))
			else
				reply(plr, why2 or "That didn't work.")
			end
		end)
	elseif op == "server" then
		if RunService:IsStudio() then
			reply(plr, "Teleports don't work in Studio: try it in the live game.")
			return
		end
		task.spawn(function()
			local ok, code = pcall(function()
				return TeleportService:ReserveServer(game.PlaceId)
			end)
			if not ok or type(code) ~= "string" then
				reply(plr, "Couldn't open a server: " .. tostring(code))
				return
			end
			reg.ProfileService.save(plr) -- the new server loads what this one saved
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = code
			local sent, err = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, { plr }, options)
			end)
			reply(plr, sent and "Taking you to a new server..." or ("The teleport failed: " .. tostring(err)))
		end)
	end
end

function AdminService.init(r)
	reg = r
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(A.LiveStore)
	end)
	liveStore = ok and store or nil
	local okO, os2 = pcall(function()
		return DataStoreService:GetDataStore(A.CardOwnersStore)
	end)
	ownersStore = okO and os2 or nil
	local okM, ms = pcall(function()
		return DataStoreService:GetDataStore(A.MailStore)
	end)
	mailStoreA = okM and ms or nil
	local okW, ws = pcall(function()
		return DataStoreService:GetDataStore(A.WhitelistStore)
	end)
	adminStore = okW and ws or nil
	writeEvents()
	Net.get("Admin").OnServerEvent:Connect(onAdmin)
	Players.PlayerAdded:Connect(function(plr)
		task.spawn(lookUpOwner, plr)
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		task.spawn(lookUpOwner, plr)
	end
	Players.PlayerRemoving:Connect(function(plr)
		lastOp[plr] = nil
		ownerOf[plr] = nil
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
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC_GIFTALL, function(msg)
				takeGiftAll(msg.Data) -- (this server's own comes back too: seen already)
			end)
		end)
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC_ADMINS, function()
				readAdmins() -- (the owner changed the whitelist somewhere)
			end)
		end)
	end)
	-- the events from before this server started, then again now and then (a missed message, an
	-- event that ended); and every player's mail, in case a ping was missed
	task.spawn(function()
		readEvents()
		readAdmins()
		while true do
			task.wait(A.PollInterval)
			readEvents()
			readAdmins()
			writeEvents()
			for _, plr in ipairs(Players:GetPlayers()) do
				task.spawn(reg.ProfileService.checkMail, plr)
			end
		end
	end)
end

return AdminService
