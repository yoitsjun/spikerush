-- Clans (Config.Clans, the Clans module): making, joining, leaving and running one; the members'
-- stats counted into points; upgrades; tag colours; the clans' leaderboard and its cards.
--
-- Storage: Store holds each clan under its tag (so a tag exists once), IndexStore each player's
-- clan tag under their user id (so a request accepted in another server, or a removal, reaches
-- them on their next join), BoardStore the clans' points. In Studio every store gets "_Studio" on
-- its name: a playtest never touches the live clans.
--
-- The Clan remote: client -> server (op, a, b, c); server -> client a payload { mine = Clans.view
-- of their clan or false, top = the leaderboard, found = a searched clan's card, notice }.
--   ("get")                          their clan and the board
--   ("search", tag)                  one clan's card
--   ("create", { tag, name, desc, public, minWins, pay = "VP" | "Pass" })
--   ("join", tag)                    a public clan: in; a private one: a request
--   ("leave")                        (the owner hands it to the next in line; the last one out closes it)
--   ("accept" | "decline", userId)   a request (owners and officers)
--   ("kick", userId)                 owners and officers (an officer only members)
--   ("promote" | "demote", userId)   the owner: member <-> officer
--   ("transfer", userId)             the owner: the clan is theirs, you're an officer
--   ("settings", { desc, public, minWins, emblem })   the owner (an emblem needs its upgrade)
--   ("rename", { name, tag })        the owner, any time (a new tag moves the clan: the old key keeps
--                                    { movedTo = new tag }, so members away find it, and nobody
--                                    else can take the old tag)
--   ("upgrade", key)                 owners and officers spend the clan's points
--   ("color", key)                   your tag colour: bought with your own share once, then worn

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local MarketplaceService = game:GetService("MarketplaceService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Clans = require(Shared.Clans)

local ClanService = {}
local reg
local C = Config.Clans
local SUFFIX = RunService:IsStudio() and "_Studio" or ""

local store, indexStore, board = nil, nil, nil
local cache = {} -- tag -> { clan, t }: the last read of each clan this server needs
local mineOf = {} -- player -> tag of their clan ("" for none)
local topList = {} -- { { rank, tag, points, name, count, cap } }, best first
local topAt = -1e9
local boardAt = {} -- tag -> when its points were last written to the board
local busy = {} -- player -> true while one of their requests runs

local function stores()
	if store then
		return true
	end
	local ok = pcall(function()
		store = DataStoreService:GetDataStore(C.Store .. SUFFIX)
		indexStore = DataStoreService:GetDataStore(C.Store .. "_Index" .. SUFFIX)
		board = DataStoreService:GetOrderedDataStore(C.BoardStore .. SUFFIX)
	end)
	return ok and store ~= nil
end

local function send(plr, payload)
	Net.get("Clan"):FireClient(plr, payload)
end

local function notify(plr, text)
	send(plr, { notice = text })
end

-- Reads a clan (nil when it doesn't exist or the store fails), following a renamed clan's old tag
-- to its new one: compare the clan's tag with the one asked for.
local function read(tag)
	if not stores() or type(tag) ~= "string" or tag == "" then
		return nil
	end
	for _ = 1, 4 do
		local ok, data = pcall(function()
			return store:GetAsync(tag)
		end)
		if ok and type(data) == "table" and type(data.movedTo) == "string" then
			cache[tag] = nil
			tag = data.movedTo
		elseif ok and type(data) == "table" and data.tag == tag then
			cache[tag] = { clan = data, t = os.clock() }
			return data
		else
			if ok then
				cache[tag] = nil
			end
			return nil
		end
	end
	return nil
end

local function cached(tag, maxAge)
	local c = tag and cache[tag]
	if c and os.clock() - c.t < (maxAge or 60) then
		return c.clan
	end
	return read(tag)
end

-- Changes a clan in the store: `fn(clan)` edits it in place and returns true to keep the change
-- (or false and why). Returns the new clan, or nil and why.
local function update(tag, fn)
	if not stores() then
		return nil, "Clans aren't available right now."
	end
	local why = nil
	local ok, result = pcall(function()
		return store:UpdateAsync(tag, function(old)
			if type(old) ~= "table" or old.tag ~= tag then
				why = "That clan doesn't exist any more."
				return nil
			end
			local keep, w = fn(old)
			if not keep then
				why = w or "That didn't work."
				return nil
			end
			return old
		end)
	end)
	if not ok then
		return nil, "Clans aren't available right now. Try again in a moment."
	end
	if why or type(result) ~= "table" then
		return nil, why or "That didn't work."
	end
	cache[tag] = { clan = result, t = os.clock() }
	return result
end

local function setIndex(userId, tag)
	if not stores() then
		return
	end
	pcall(function()
		if tag and tag ~= "" then
			indexStore:SetAsync(tostring(userId), tag)
		else
			indexStore:RemoveAsync(tostring(userId))
		end
	end)
end

-- Tells every server a clan changed (its members there re-read it).
local function announce(tag)
	pcall(function()
		MessagingService:PublishAsync(C.Topic, tag)
	end)
end

local function writeBoard(clan, force)
	if not stores() or not clan then
		return
	end
	local now = os.clock()
	if not force and boardAt[clan.tag] and now - boardAt[clan.tag] < 30 then
		return
	end
	boardAt[clan.tag] = now
	local total = Clans.points(clan)
	pcall(function()
		board:SetAsync(clan.tag, total)
	end)
end

-- A player's chat tag and its colour, as attributes every client reads (chat, name tags, intro).
-- With its clan's name, emblem and whether it has its own intro (LineupController's clan intro).
local function applyTag(plr)
	local tag = mineOf[plr] or ""
	local profile = reg.ProfileService.get(plr)
	local c = tag ~= "" and cache[tag]
	local clan = c and c.clan or nil
	plr:SetAttribute("ClanTag", tag ~= "" and tag or nil)
	plr:SetAttribute("ClanColor", tag ~= "" and (profile and profile.clanColor or "White") or nil)
	plr:SetAttribute("ClanName", clan and clan.name or nil)
	plr:SetAttribute("ClanEmblem", clan and clan.emblem ~= "" and clan.emblem or nil)
	plr:SetAttribute("ClanIntro", clan and Clans.level(clan, "Intro") > 0 or nil)
end

-- The payload for a player: their clan (and their place in it) and the board.
local function payload(plr, extra)
	local p = extra or {}
	local tag = mineOf[plr]
	local clan = tag and tag ~= "" and cached(tag, 30) or nil
	p.mine = clan and Clans.view(clan) or false
	p.top = topList
	local profile = reg.ProfileService.get(plr)
	p.colors = profile and profile.clanColors or {}
	p.color = profile and profile.clanColor or "White"
	p.passOwned = ClanService.ownsPass(plr)
	return p
end

local function refresh(plr, notice)
	if plr.Parent then
		send(plr, payload(plr, { notice = notice }))
		applyTag(plr) -- (a new name, emblem or intro shows)
	end
end

-- Whether a player owns the Clan Founder pass (asked once).
local passOwned = {}
function ClanService.ownsPass(plr)
	if C.PassId == 0 then
		return false
	end
	if passOwned[plr] == nil then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, C.PassId)
		end)
		passOwned[plr] = ok and owns == true
	end
	return passOwned[plr]
end

-- A name or description through Roblox's filter (nil when it can't be checked).
local function filtered(plr, text)
	if text == "" then
		return ""
	end
	local ok, out = pcall(function()
		return TextService:FilterStringAsync(text, plr.UserId):GetNonChatStringForBroadcastAsync()
	end)
	return ok and out or nil
end

local function recordOf(plr)
	local profile = reg.ProfileService.get(plr)
	return profile and profile.record or nil
end

local function winsOf(plr)
	local r = recordOf(plr)
	return r and tonumber(r.wins) or 0
end

-- Sets a player's clan in this server (and their tag).
local function setMine(plr, tag)
	mineOf[plr] = tag or ""
	applyTag(plr)
end

------------------------------------------------------------------------------------------
-- the board, and its cards
------------------------------------------------------------------------------------------

local function readTop()
	if not stores() then
		return
	end
	local ok, pages = pcall(function()
		return board:GetSortedAsync(false, C.BoardTop)
	end)
	if not ok or not pages then
		return
	end
	local list = {}
	for i, row in ipairs(pages:GetCurrentPage()) do
		local entry = { rank = i, tag = row.key, points = row.value }
		-- the top ten with their names (one read each, a few times an hour)
		if i <= 10 then
			local clan = cached(row.key, 300)
			if clan then
				entry.name = clan.name
				entry.count = Clans.count(clan)
				entry.cap = Clans.cap(clan)
				entry.emblem = clan.emblem
			end
		end
		table.insert(list, entry)
	end
	topList = list
	topAt = os.clock()
	-- the members of the top clans online here get their rank (the ClanTop3 / ClanNumber1 cards)
	for _, plr in ipairs(Players:GetPlayers()) do
		local tag = mineOf[plr]
		for _, e in ipairs(list) do
			if tag and e.tag == tag and e.rank <= 3 then
				reg.ProfileService.clanRank(plr, e.rank, tag)
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- what the rest of the game asks
------------------------------------------------------------------------------------------

-- What a player's clan's upgrades multiply their `kind` ("VP", "Gold", "Luck") by.
function ClanService.bonus(plr, kind)
	local tag = plr and mineOf[plr]
	local c = tag and tag ~= "" and cache[tag]
	return c and Clans.bonus(c.clan, kind) or 1
end

-- A player's clan tag ("" for none) and its clan's cached record (the matchup intro).
function ClanService.tagOf(plr)
	return mineOf[plr] or ""
end

function ClanService.clanOf(plr)
	local tag = mineOf[plr]
	local c = tag and tag ~= "" and cache[tag]
	return c and c.clan or nil
end

-- A finished match (ProfileService.recordResult) or an MVP: their stats since joining go to the clan.
function ClanService.onRecord(plr)
	local tag = mineOf[plr]
	local record = recordOf(plr)
	if not tag or tag == "" or not record then
		return
	end
	task.spawn(function()
		local clan = update(tag, function(c)
			if not c.members[tostring(plr.UserId)] then
				return false, "not a member"
			end
			return Clans.updateMember(c, plr.UserId, record) or true
		end)
		if clan then
			writeBoard(clan, false)
		end
	end)
end

-- Their profile is loaded (ProfileService): which clan they're in (the index), checked against the
-- clan itself.
function ClanService.onLoaded(plr)
	if not stores() then
		return
	end
	local ok, tag = pcall(function()
		return indexStore:GetAsync(tostring(plr.UserId))
	end)
	tag = ok and type(tag) == "string" and tag or ""
	local clan = tag ~= "" and read(tag) or nil
	if clan and clan.tag ~= tag then
		-- the clan was renamed while they were away: their index follows it
		tag = clan.tag
		setIndex(plr.UserId, tag)
	end
	if tag ~= "" and not (clan and clan.members[tostring(plr.UserId)]) then
		-- removed while away (or the clan closed)
		setIndex(plr.UserId, nil)
		tag = ""
	end
	if not plr.Parent then
		return
	end
	setMine(plr, tag)
	if clan then
		-- a name change shows; their stats catch up
		local record = recordOf(plr)
		task.spawn(function()
			update(tag, function(c)
				local m = c.members[tostring(plr.UserId)]
				if not m then
					return false
				end
				m.n = plr.DisplayName
				if m.pending then
					-- (let in while away: their count starts now, not from their whole career)
					m.b = Clans.snapshot(record)
					m.pending = nil
				end
				Clans.updateMember(c, plr.UserId, record)
				return true
			end)
		end)
	end
	if os.clock() - topAt > 300 then
		task.spawn(readTop)
	end
	refresh(plr)
end

function ClanService.onLeft(plr)
	mineOf[plr] = nil
	passOwned[plr] = nil
	busy[plr] = nil
end

------------------------------------------------------------------------------------------
-- the ops
------------------------------------------------------------------------------------------

local ops = {}

function ops.get(plr)
	if os.clock() - topAt > 300 then
		readTop()
	end
	refresh(plr)
end

function ops.search(plr, text)
	local tag = Clans.cleanTag(text)
	local clan = tag and read(tag)
	send(plr, payload(plr, { found = clan and Clans.card(clan) or false, notice = not clan and "No clan with that tag." or nil }))
end

function ops.create(plr, form)
	if type(form) ~= "table" then
		return
	end
	if mineOf[plr] and mineOf[plr] ~= "" then
		return notify(plr, "Leave your clan first.")
	end
	local tag, whyTag = Clans.cleanTag(form.tag)
	if not tag then
		return notify(plr, whyTag)
	end
	local name, whyName = Clans.cleanName(form.name)
	if not name then
		return notify(plr, whyName)
	end
	local fName = filtered(plr, name)
	local fTag = filtered(plr, tag)
	local fDesc = filtered(plr, Clans.cleanDesc(form.desc))
	if not fName or not fTag or not fDesc then
		return notify(plr, "Couldn't check that right now. Try again in a moment.")
	end
	if fName ~= name or fTag ~= tag then
		return notify(plr, "That name or tag isn't allowed.")
	end
	-- paid: the pass, else VP (taken first, given back if the tag's taken)
	local byPass = form.pay == "Pass" and ClanService.ownsPass(plr)
	if not byPass then
		local paid, why = reg.ProfileService.spendVP(plr, C.CostVP)
		if not paid then
			return notify(plr, why or string.format("You need %d VP.", C.CostVP))
		end
	end
	local clan = Clans.new(tag, name, fDesc, form.public ~= false, form.minWins, plr.UserId, plr.DisplayName, recordOf(plr), os.time())
	local taken = false
	local ok = stores() and pcall(function()
		store:UpdateAsync(tag, function(old)
			if old ~= nil then
				taken = true
				return nil
			end
			return clan
		end)
	end)
	if not ok or taken then
		if not byPass then
			reg.ProfileService.award(plr, C.CostVP, 0)
		end
		return notify(plr, taken and string.format("The tag [%s] is taken.", tag) or "Clans aren't available right now.")
	end
	cache[tag] = { clan = clan, t = os.clock() }
	setIndex(plr.UserId, tag)
	setMine(plr, tag)
	writeBoard(clan, true)
	refresh(plr, string.format("[%s] %s is yours!", tag, name))
end

function ops.join(plr, text)
	if mineOf[plr] and mineOf[plr] ~= "" then
		return notify(plr, "Leave your clan first.")
	end
	local tag = Clans.cleanTag(text)
	local clan = tag and read(tag)
	if not clan then
		return notify(plr, "That clan doesn't exist.")
	end
	local wins = winsOf(plr)
	local ok, why = Clans.canJoin(clan, wins)
	if not ok then
		return notify(plr, why)
	end
	local record = recordOf(plr)
	if clan.public then
		local result, w = update(tag, function(c)
			local can, cw = Clans.canJoin(c, wins)
			if not can then
				return false, cw
			end
			Clans.addMember(c, plr.UserId, plr.DisplayName, "Member", record, os.time())
			return true
		end)
		if not result then
			return notify(plr, w)
		end
		setIndex(plr.UserId, tag)
		setMine(plr, tag)
		announce(tag)
		refresh(plr, string.format("Welcome to [%s] %s!", tag, result.name))
	else
		local result, w = update(tag, function(c)
			c.req = c.req or {}
			local n = 0
			for _ in pairs(c.req) do
				n = n + 1
			end
			if n >= C.RequestsMax then
				return false, "That clan has too many requests waiting."
			end
			c.req[tostring(plr.UserId)] = { n = plr.DisplayName, w = wins, t = os.time() }
			return true
		end)
		if not result then
			return notify(plr, w)
		end
		announce(tag)
		refresh(plr, string.format("Request sent to [%s]: an officer or the owner can let you in.", tag))
	end
end

-- The next owner when the owner leaves: an officer, else anyone, most points first.
local function heir(clan, leaving)
	local best, bestKey = nil, nil
	for id, m in pairs(clan.members) do
		if id ~= tostring(leaving) then
			local key = (m.r == "Officer" and 1e9 or 0) + (Clans.memberPoints(m))
			if not bestKey or key > bestKey then
				best, bestKey = id, key
			end
		end
	end
	return best
end

function ops.leave(plr)
	local tag = mineOf[plr]
	if not tag or tag == "" then
		return
	end
	local closed = false
	local result, why = update(tag, function(c)
		local nextOwner = c.owner == plr.UserId and heir(c, plr.UserId) or nil
		Clans.removeMember(c, plr.UserId)
		if c.owner == plr.UserId then
			if nextOwner then
				c.owner = tonumber(nextOwner)
				c.members[nextOwner].r = "Owner"
			else
				closed = true
			end
		end
		return true
	end)
	if not result and not closed then
		return notify(plr, why)
	end
	if closed and stores() then
		pcall(function()
			store:RemoveAsync(tag)
		end)
		pcall(function()
			board:RemoveAsync(tag)
		end)
		cache[tag] = nil
	elseif result then
		writeBoard(result, true)
	end
	setIndex(plr.UserId, nil)
	setMine(plr, "")
	announce(tag)
	refresh(plr, closed and string.format("[%s] is closed.", tag) or string.format("You left [%s].", tag))
end

-- A manager's op on a member or a request: `fn(clan, id string, me)` returns ok (or false, why).
local function manage(plr, userId, ownerOnly, fn, after)
	local tag = mineOf[plr]
	local uid = tonumber(userId)
	if not tag or tag == "" or not uid then
		return
	end
	local result, why = update(tag, function(c)
		local me = c.members[tostring(plr.UserId)]
		if not me or (ownerOnly and me.r ~= "Owner") or not Clans.canManage(c, plr.UserId) then
			return false, "Only the owner (or an officer) can do that."
		end
		return fn(c, tostring(uid), me)
	end)
	if not result then
		return notify(plr, why)
	end
	if after then
		after(result, uid)
	end
	writeBoard(result, true)
	announce(tag)
	refresh(plr)
end

function ops.accept(plr, userId)
	manage(plr, userId, false, function(c, id)
		local r = c.req and c.req[id]
		if not r then
			return false, "That request is gone."
		end
		local ok, why = Clans.canJoin(c, r.w)
		if not ok then
			return false, why
		end
		-- (their record from their profile if they're here; else from their next game: base 0
		-- here would count their whole career, so a stranger's base is set when they next load)
		local other = Players:GetPlayerByUserId(tonumber(id))
		local record = other and recordOf(other) or nil
		Clans.addMember(c, tonumber(id), r.n, "Member", record, os.time())
		if not other then
			c.members[id].pending = true
		end
		return true
	end, function(clan, uid)
		local other = Players:GetPlayerByUserId(uid)
		-- (in another server, or not in the game: the index says so when they next load)
		setIndex(uid, clan.tag)
		if other then
			setMine(other, clan.tag)
			refresh(other, string.format("You're in [%s] %s!", clan.tag, clan.name))
		end
	end)
end

function ops.decline(plr, userId)
	manage(plr, userId, false, function(c, id)
		if not (c.req and c.req[id]) then
			return false, "That request is gone."
		end
		c.req[id] = nil
		return true
	end)
end

function ops.kick(plr, userId)
	manage(plr, userId, false, function(c, id, me)
		local m = c.members[id]
		if not m or m.r == "Owner" or (me.r == "Officer" and m.r ~= "Member") then
			return false, "You can't remove them."
		end
		Clans.removeMember(c, tonumber(id))
		return true
	end, function(clan, uid)
		setIndex(uid, nil)
		local other = Players:GetPlayerByUserId(uid)
		if other then
			setMine(other, "")
			refresh(other, string.format("You were removed from [%s].", clan.tag))
		end
	end)
end

function ops.promote(plr, userId)
	manage(plr, userId, true, function(c, id)
		local m = c.members[id]
		if not m or m.r ~= "Member" then
			return false, "Only a member can be made an officer."
		end
		m.r = "Officer"
		return true
	end)
end

function ops.demote(plr, userId)
	manage(plr, userId, true, function(c, id)
		local m = c.members[id]
		if not m or m.r ~= "Officer" then
			return false, "Only an officer can be made a member."
		end
		m.r = "Member"
		return true
	end)
end

function ops.transfer(plr, userId)
	manage(plr, userId, true, function(c, id, me)
		local m = c.members[id]
		if not m or id == tostring(plr.UserId) then
			return false, "Pick another member."
		end
		m.r = "Owner"
		me.r = "Officer"
		c.owner = tonumber(id)
		return true
	end)
end

function ops.settings(plr, form)
	if type(form) ~= "table" then
		return
	end
	local desc = form.desc ~= nil and filtered(plr, Clans.cleanDesc(form.desc)) or nil
	if form.desc ~= nil and not desc then
		return notify(plr, "Couldn't check that right now. Try again in a moment.")
	end
	manage(plr, plr.UserId, true, function(c)
		if desc then
			c.desc = desc
		end
		if form.public ~= nil then
			c.public = form.public == true
		end
		if form.minWins ~= nil then
			c.minWins = Clans.cleanMinWins(form.minWins)
		end
		if form.emblem ~= nil then
			if Clans.level(c, "Emblem") < 1 then
				return false, "Unlock the Clan emblem upgrade first."
			end
			c.emblem = Clans.cleanEmblem(form.emblem)
		end
		return true
	end)
end

-- (the owner, 2026-10-21: "allow the clan name to be modified alongside the tag at any point")
function ops.rename(plr, form)
	local tag = mineOf[plr]
	if type(form) ~= "table" or not tag or tag == "" then
		return
	end
	local clan = read(tag)
	if not clan or clan.owner ~= plr.UserId then
		return notify(plr, "Only the owner can rename the clan.")
	end
	local name, whyName = Clans.cleanName(form.name ~= nil and form.name or clan.name)
	if not name then
		return notify(plr, whyName)
	end
	local newTag, whyTag = Clans.cleanTag(form.tag ~= nil and form.tag or clan.tag)
	if not newTag then
		return notify(plr, whyTag)
	end
	local fName, fTag = filtered(plr, name), filtered(plr, newTag)
	if not fName or not fTag then
		return notify(plr, "Couldn't check that right now. Try again in a moment.")
	end
	if fName ~= name or fTag ~= newTag then
		return notify(plr, "That name or tag isn't allowed.")
	end
	if newTag == tag then
		local result, why = update(tag, function(c)
			c.name = name
			return true
		end)
		if not result then
			return notify(plr, why)
		end
		announce(tag)
		return refresh(plr, "Renamed: " .. name .. ".")
	end
	-- a new tag: the clan moves to its key (only if nobody has it), the old key points there
	local moved = nil
	for k, v in pairs(clan) do
		moved = moved or {}
		moved[k] = v
	end
	moved.tag = newTag
	moved.name = name
	local taken = false
	local ok = pcall(function()
		store:UpdateAsync(newTag, function(old)
			if old ~= nil then
				taken = true
				return nil
			end
			return moved
		end)
	end)
	if not ok or taken then
		return notify(plr, taken and string.format("The tag [%s] is taken.", newTag) or "Clans aren't available right now.")
	end
	pcall(function()
		store:SetAsync(tag, { movedTo = newTag, t = os.time() })
	end)
	pcall(function()
		board:RemoveAsync(tag)
	end)
	cache[tag] = nil
	cache[newTag] = { clan = moved, t = os.clock() }
	writeBoard(moved, true)
	-- members here move with it; the rest when they hear (announce) or next join (onLoaded)
	for _, p in ipairs(Players:GetPlayers()) do
		if mineOf[p] == tag then
			setIndex(p.UserId, newTag)
			setMine(p, newTag)
			refresh(p, p == plr and string.format("Your clan is [%s] %s now.", newTag, name) or nil)
		end
	end
	announce(tag)
end

function ops.upgrade(plr, key)
	local u = Clans.upgrade(key)
	if not u then
		return
	end
	manage(plr, plr.UserId, false, function(c)
		local cost = Clans.cost(c, key)
		if not cost then
			return false, u.Name .. " is maxed."
		end
		local _, left = Clans.points(c)
		if left < cost then
			return false, string.format("%s needs %d points (you have %d to spend).", u.Name, cost, left)
		end
		c.spent = (tonumber(c.spent) or 0) + cost
		c.up = c.up or {}
		c.up[key] = Clans.level(c, key) + 1
		return true
	end)
end

function ops.color(plr, key)
	local col = Clans.tagColor(key)
	if col.Key ~= key then
		return
	end
	local profile = reg.ProfileService.get(plr)
	if not profile then
		return
	end
	profile.clanColors = type(profile.clanColors) == "table" and profile.clanColors or {}
	if col.Cost > 0 and not profile.clanColors[key] then
		local tag = mineOf[plr]
		if not tag or tag == "" then
			return notify(plr, "Join a clan to earn points for tag colours.")
		end
		local result, why = update(tag, function(c)
			local m = c.members[tostring(plr.UserId)]
			if not m then
				return false, "You're not in that clan."
			end
			local _, own = Clans.memberPoints(m)
			if own < col.Cost then
				return false, string.format("%s costs %d of your points (you have %d).", col.Name, col.Cost, own)
			end
			m.sp = (tonumber(m.sp) or 0) + col.Cost
			return true
		end)
		if not result then
			return notify(plr, why)
		end
		profile.clanColors[key] = true
	end
	profile.clanColor = key
	reg.ProfileService.touch(plr)
	applyTag(plr)
	refresh(plr, col.Name .. " tag on.")
end

------------------------------------------------------------------------------------------

function ClanService.init(r)
	reg = r
	Net.get("Clan").OnServerEvent:Connect(function(plr, op, a, b)
		local fn = type(op) == "string" and ops[op]
		if not fn or busy[plr] then
			return
		end
		busy[plr] = true
		local ok, err = pcall(fn, plr, a, b)
		busy[plr] = nil
		if not ok then
			warn("[SpikeRush] clan " .. tostring(op) .. ": " .. tostring(err))
			notify(plr, "That didn't work. Try again in a moment.")
		end
	end)
	-- a clan changed in some server: its members here re-read it (and anyone removed goes)
	pcall(function()
		MessagingService:SubscribeAsync(C.Topic, function(msg)
			local tag = type(msg.Data) == "string" and msg.Data or nil
			if not tag then
				return
			end
			local any = false
			for _, plr in ipairs(Players:GetPlayers()) do
				if mineOf[plr] == tag then
					any = true
				end
			end
			if not any then
				cache[tag] = nil
				return
			end
			local clan = read(tag)
			for _, plr in ipairs(Players:GetPlayers()) do
				if mineOf[plr] == tag then
					if not (clan and clan.members[tostring(plr.UserId)]) then
						setMine(plr, "")
					elseif clan.tag ~= tag then
						setIndex(plr.UserId, clan.tag) -- (renamed: a new tag)
						setMine(plr, clan.tag)
					end
					refresh(plr)
				end
			end
		end)
	end)
	-- the Clan Founder pass bought from the Create tab: theirs at once
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, id, bought)
		if bought and id == C.PassId then
			passOwned[plr] = true
			refresh(plr, "Clan Founder pass: yours. Make your clan!")
		end
	end)
	-- the board every five minutes
	task.spawn(function()
		while true do
			task.wait(300)
			pcall(readTop)
		end
	end)
end

return ClanService
