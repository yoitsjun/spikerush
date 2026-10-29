-- Player profiles: V Points (VP) and Gold, the characters you own (and how far you've upgraded
-- each), (named presets from the Roster module, each
-- with its role, stat ceilings, height and ability), the one you play, your unlocked cosmetics and
-- what's equipped, and your auto-sell choices. Saved with DataStoreService; falls back to
-- session-only profiles when the DataStore isn't reachable (e.g. Studio without "Enable Studio
-- Access to API Services").
--
-- Client requests arrive on the "Profile" remote:
--   ("get")                          -> reply with a snapshot
--   ("select", charId)               -> play an owned character
--   ("upgrade", charId, stat, delta) -> +1/5/10 costs Gold, -1/5/10 refunds exactly what it cost
--   ("spin", banner, 1|10)           -> x1 / x10 spin (Config.Spins)
--   ("autoroll", banner) / ("stop")  -> spin x1 until a Legendary or better (or out of VP)
--   ("autosell", rarity, on, banner) -> new pulls of that rarity on that banner turn straight into VP
--   ("equip", kind, key)             -> equip an unlocked style, colour, trail or score effect
--   ("favorite", charId, on)         -> star or unstar a character (the Players screen's filter)
--   ("settings", table)              -> your settings (switches, touch layout); no reply
--   ("buy", packIndex, kind)        -> Studio only: grant a pack ("VP", "Gold", "Lucky") whose
--                                       product id isn't set yet
--   ("spin", banner, 1|10, "lucky")  -> spend lucky spins instead of VP (Config.Lucky's odds)
--   ("breakthrough", charId)         -> spend fragments of its letter on its next breakthrough
--   ("sellFragment", group, n)       -> sell n fragments for a duplicate's VP (S+: lucky spins too)
--   ("sellChar", charId)             -> sell a character: its VP, upgrade Gold and fragments back
--   ("code", text)                   -> redeem a code, once each
--   ("daily")                        -> claim the daily reward
--   ("liked")                        -> "I liked the game" (their word: Roblox can't tell a game)
--   ("favorited", bool)              -> what Roblox told the client: they favorited the game (its prompt
--                                       said so), or no longer have (GetFavoriteAsync, with permission)
--   ("group")                        -> check group membership again (after the join prompt)
--   ("equip", "Card", key)           -> wear a player card you've unlocked (Config.Cards)
-- Player cards are unlocked for good by achievements (Cards.met: the career counters, the MVP
-- count, the best leaderboard place, the players recruited); checkCards runs after every match,
-- recruit and leaderboard read.
--   ("gift", kind, index, username)  -> buy a pack for someone else
--   ("pityPick", charId)             -> the S+ your lucky pity owes you (Config.Spins.Pity)
--   ("sTicket", charId)              -> spend a selection ticket on a Config.Retired.TicketTier
--                                       character you don't own (tickets: retired characters)
--   ("favor", charId, "up"|"down"|nil) -> boost, lower or reset a character's odds (Config.Spins.Favor)
--   ("entrance", boardKey | nil)     -> the board whose place shows over your head (nil: your best)
--   ("profileOf", userId)            -> a player's public profile, on the PlayerProfile remote
--   ("skin", "on"|"off", charId, key) -> swap a skin on or off for a character (the Reaper: Jaeil)
--   ("room", key)                    -> Home's room (Config.Rooms: the Haunted Forest)
-- Codes and the daily reward are for members of the group who favorited the game (the owner:
-- "actually check"; Roblox can't tell a game who liked it, but its favorite prompt tells the
-- client when they favorite it). Kept in the profile, so it's done once.
-- Your character locks while you're in a match, so prediction always matches the server.
-- VP, Gold and lucky spin packs are Developer Products granted in MarketplaceService.
-- ProcessReceipt; one bought as a gift goes to its recipient. What's spent in Robux (packs, gifts,
-- the perks' passes) is counted for the leaderboards (not in Studio, whose purchases are tests). Gifts and the admin panel's Give reach a
-- player in another server, or offline, through their mail (a DataStore; giveUser, checkMail).
-- Developers (Config.Developers: the place owner, Studio sessions, listed ids) own everything
-- and spin for free.

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)
local Roster = require(Shared.Roster)
local Breakthrough = require(Shared.Breakthrough)
local Court = require(Shared.Court)
local Tutorial = require(Shared.Tutorial)
local Rewards = require(Shared.Rewards)
local Spins = require(Shared.Spins)
local Settings = require(Shared.Settings)
local SoundCrop = require(Shared.SoundCrop)
local Economy = require(Shared.Economy)
local Ranked = require(Shared.Ranked)
local PatchNotes = require(Shared.PatchNotes)
local Cards = require(Shared.Cards)
local Leaderboards = require(Shared.Leaderboards)
local Halloween = require(Shared.Halloween)
local Rooms = require(Shared.Rooms)
local Lounge = require(Shared.Lounge)
local Net = require(Shared.Net)

local ProfileService = {}
local reg

local P = Config.Progression
local SP = Config.Spins
local COS = Config.Cosmetics
local VERSION = 4
local profiles = {}
local dirty = {}
local loading = {}
local store = nil
local warned = false
local lastRequest = {}
local tzOffset = {} -- player -> their UTC offset in seconds (from their client), so playtime days turn at their own midnight
local mailStore = nil -- gifts waiting for their player (Config.Admin.MailStore)
local mailBusy = {}
local pendingGift = {} -- plr -> the gift their prompted purchase is: { productId, userId, name, t }
local groupMember = {} -- plr -> whether they're in the group (asked on join and on each claim)
local lastClaim = {} -- plr -> when they last redeemed, claimed or started a gift (each is looked up)
local verifyStore = nil -- the Discord's verification codes (Config.Discord.Store)
local discordBusy = {} -- plr -> true while their Discord code is being made or checked
local discordChecked = {} -- plr -> os.clock() of their last Verify
local passPrices = {} -- game pass id -> its price in Robux

local function key(plr)
	return "u_" .. tostring(plr.UserId)
end

------------------------------------------------------------------------------------------
-- developers
------------------------------------------------------------------------------------------

local function isDeveloper(plr)
	local D = Config.Developers
	if D.Studio and RunService:IsStudio() then
		return true
	end
	for _, id in ipairs(D.UserIds) do
		if id == plr.UserId then
			return true
		end
	end
	if D.Owner then
		if game.CreatorType == Enum.CreatorType.User then
			return plr.UserId == game.CreatorId
		end
		local ok, rank = pcall(function()
			return plr:GetRankInGroup(game.CreatorId)
		end)
		return ok and rank == 255
	end
	return false
end

------------------------------------------------------------------------------------------
-- the group (daily rewards and codes are for its members)
------------------------------------------------------------------------------------------

-- Config.Daily.GroupId, or the group that owns the experience (0: none).
local function groupId()
	local id = Config.Daily.GroupId
	if id and id ~= 0 then
		return id
	end
	if game.CreatorType == Enum.CreatorType.Group then
		return game.CreatorId
	end
	return 0
end

-- Whether a player is in the group. Studio test sessions count, so the flow can be tried. fresh:
-- ask again (IsInGroup keeps its first answer all session, and a player may have just joined:
-- the group list sees that at once).
local function inGroup(plr, fresh)
	if RunService:IsStudio() then
		groupMember[plr] = true
		return true
	end
	local gid = groupId()
	if gid == 0 then
		return false
	end
	if groupMember[plr] ~= nil and (groupMember[plr] or not fresh) then
		return groupMember[plr]
	end
	local ok, member = pcall(function()
		return plr:IsInGroup(gid)
	end)
	member = ok and member == true
	if not member and fresh then
		local okList, groups = pcall(function()
			return GroupService:GetGroupsAsync(plr.UserId)
		end)
		if okList and type(groups) == "table" then
			for _, g in ipairs(groups) do
				if g.Id == gid then
					member = true
				end
			end
		end
	end
	groupMember[plr] = member
	return member
end

------------------------------------------------------------------------------------------
-- profile data
------------------------------------------------------------------------------------------

-- The ids a perk takes: its Slots, or one slot named after the perk itself.
local function perkSlots(key)
	local def = Config.Perks[key]
	return (def and def.Slots) or { { Key = key, Name = def and def.Name or key } }
end

-- The perk (key and def) a slot key belongs to, and the slot.
local function perkOfSlot(slotKey)
	for _, key in ipairs(Config.Perks.Order) do
		for _, slot in ipairs(perkSlots(key)) do
			if slot.Key == slotKey then
				return key, Config.Perks[key], slot
			end
		end
	end
	return nil
end

local function newProfile()
	local p = { v = VERSION, vp = P.StartingVP, gold = P.StartingGold, freeSpins = 0, winStreak = 0, bestStreak = 0, playTime = 0, playToday = { day = 0, secs = 0, claimed = {} }, record = { matches = 0, wins = 0, kills = 0, aces = 0, blocks = 0, mvps = 0, devWins = 0 }, levels = {}, owned = {}, equip = {}, fav = {}, autoSell = {}, receipts = {}, tutorial = { steps = {}, done = false }, teams = {}, settings = {}, perks = {}, perkIds = {}, perkCrops = {}, lucky = 0, codes = {}, daily = { last = 0, streak = 0 }, spent = { robux = 0, gifts = 0 }, mailSeen = {}, liked = false, favorited = false, boosts = {}, cards = {}, pity = Spins.newPity(), favor = {}, bundles = {}, sTickets = 0, retiredPaid = {}, patchSeen = "", patchClaimed = {}, discordCode = "", discordDone = false, fragments = {}, breaks = {}, halloween = Halloween.clean(nil), skins = {}, rooms = Rooms.clean(nil), grave = Halloween.cleanGrave(nil), giftedPasses = {}, clanColors = {}, clanColor = "White", ranked = Ranked.clean(nil, Ranked.season(os.time())), almightyMoved = true, lounge = Lounge.clean(nil, Lounge.day(os.time())) }
	for _, kind in ipairs(Spins.Kinds) do
		p.owned[kind] = {}
		for k in pairs(Spins.starters(kind)) do
			p.owned[kind][k] = true
		end
	end
	for _, kind in ipairs(COS.Kinds) do
		p.equip[kind] = Spins.default(kind)
	end
	p.char = Roster.Starters[1]
	return p
end

-- Older profiles (v1 upgrade points, v2 rolled caps) keep their VP and cosmetics; their old
-- characters don't carry over, everyone gets the starters.
local function sanitizeProfile(data)
	if type(data) ~= "table" then
		return newProfile()
	end
	local out = newProfile()
	local vp = data.vp
	if vp == nil then
		vp = data.points
	end
	out.vp = math.max(0, math.floor(tonumber(vp) or P.StartingVP))
	if data.gold ~= nil then
		out.gold = math.max(0, math.floor(tonumber(data.gold) or 0))
	end
	if type(data.levels) == "table" then
		for id, lv in pairs(data.levels) do
			local c = Roster.get(id)
			if c and type(lv) == "table" then
				local clean = {}
				for _, stat in ipairs(Config.Stats.Order) do
					clean[stat] = Characters.statLevel(c, lv, stat)
				end
				out.levels[id] = clean
			end
		end
	end
	for _, kind in ipairs(Spins.Kinds) do
		local owned = type(data.owned) == "table" and data.owned[kind]
		if type(owned) == "table" then
			for k, v in pairs(owned) do
				if v and Spins.item(kind, k) then
					out.owned[kind][k] = true
				end
			end
		end
	end
	-- Candy Corn was a trail for a day, and Rainbow until 2026-10-25; both are colours now (the owner:
	-- "the candy corn is a color", "rainbow should be a color")
	local oldTrail = type(data.owned) == "table" and data.owned.Trail
	for _, key in ipairs({ "CandyCorn", "Rainbow" }) do
		if type(oldTrail) == "table" and oldTrail[key] and Spins.item("Color", key) then
			out.owned.Color[key] = true
		end
	end
	-- what's equipped is kept if it exists; whether it's owned is checked once the player is known
	-- (keepOwned: a developer owns everything without it being in `owned`)
	for _, kind in ipairs(COS.Kinds) do
		local eq = type(data.equip) == "table" and data.equip[kind]
		if type(eq) == "string" and Spins.item(kind, eq) then
			out.equip[kind] = eq
		end
	end
	if type(data.equip) == "table" and (data.equip.Trail == "CandyCorn" or data.equip.Trail == "Rainbow") and not out.equip.Color then
		out.equip.Color = data.equip.Trail
	end
	if type(data.char) == "string" and Spins.item("Char", data.char) then
		out.char = data.char
	end
	-- your AI teammates, per team ("3v3", "2v2"): a character of each slot's role
	if type(data.teams) == "table" then
		for mode, picks in pairs(data.teams) do
			local size = Court.teamSize(mode)
			if size and size >= 2 and type(picks) == "table" then
				for _, role in ipairs(Court.roles(size)) do
					local c = type(picks[role]) == "string" and Roster.get(picks[role])
					if c and c.Role == role then
						out.teams[mode] = out.teams[mode] or {}
						out.teams[mode][role] = c.Id
					end
				end
			end
		end
	end
	-- the Halloween event: Candy, scout points, today's first clears, the Candy shop's buys; and the
	-- skins (the Reaper's copies and the characters they're on)
	out.halloween = Halloween.clean(data.halloween)
	out.skins = Halloween.cleanSkins(data.skins, function(id)
		return Roster.get(id) ~= nil
	end)
	-- (a skin comes with its character: one pulled before it did gets them now)
	Halloween.skinChars(out.skins, out.owned.Char)
	-- Home's rooms (Config.Rooms): the ones won, and the one on
	out.rooms = Rooms.clean(data.rooms)
	-- the Rest in Peace gravestone (Config.Grave): the epitaph (already filtered) and the picture
	out.grave = Halloween.cleanGrave(data.grave)
	-- breakthroughs: the fragments in hand, and each character's level (Config.Breakthrough)
	out.fragments = Breakthrough.cleanFragments(data.fragments)
	if type(data.breaks) == "table" then
		for id, lv in pairs(data.breaks) do
			local level = Breakthrough.level(lv)
			if Roster.get(id) and level > 0 then
				out.breaks[id] = level
			end
		end
	end
	if type(data.fav) == "table" then
		for id, v in pairs(data.fav) do
			if v == true and Roster.get(id) then
				out.fav[id] = true
			end
		end
	end
	out.freeSpins = math.clamp(math.floor(tonumber(data.freeSpins) or 0), 0, 1000)
	-- retired characters (Config.Retired): the ones this profile owned are gone (Spins.item no
	-- longer knows them, above); each pays one selection ticket, once
	out.sTickets = math.clamp(math.floor(tonumber(data.sTickets) or 0), 0, 100)
	if type(data.retiredPaid) == "table" then
		for _, id in ipairs(Config.Retired.Chars) do
			if data.retiredPaid[id] == true then
				out.retiredPaid[id] = true
			end
		end
	end
	local hadChars = type(data.owned) == "table" and type(data.owned.Char) == "table" and data.owned.Char or {}
	for _, id in ipairs(Config.Retired.Chars) do
		if hadChars[id] and not out.retiredPaid[id] then
			out.retiredPaid[id] = true
			out.sTickets = out.sTickets + 1
		end
	end
	out.winStreak = math.max(0, math.floor(tonumber(data.winStreak) or 0))
	out.bestStreak = math.max(out.winStreak, math.floor(tonumber(data.bestStreak) or 0))
	out.playTime = math.max(0, math.floor(tonumber(data.playTime) or 0))
	-- today's playtime and which of Config.PlayRewards it has paid already
	out.playToday = { day = 0, secs = 0, claimed = {} }
	if type(data.playToday) == "table" then
		out.playToday.day = math.max(0, math.floor(tonumber(data.playToday.day) or 0))
		out.playToday.secs = math.max(0, math.floor(tonumber(data.playToday.secs) or 0))
		if type(data.playToday.claimed) == "table" then
			for _, t in ipairs(Config.PlayRewards.Tiers) do
				if data.playToday.claimed[t.Key] == true then
					out.playToday.claimed[t.Key] = true
				end
			end
		end
	end
	if type(data.record) == "table" then
		for k in pairs(out.record) do
			out.record[k] = math.max(0, math.floor(tonumber(data.record[k]) or 0))
		end
	end
	if type(data.tutorial) == "table" then
		out.tutorial.done = data.tutorial.done == true
		if type(data.tutorial.steps) == "table" then
			for id, v in pairs(data.tutorial.steps) do
				if v == true and Tutorial.isStep(id) then
					out.tutorial.steps[id] = true
				end
			end
		end
	end
	out.autoSell = Spins.cleanAutoSell(data.autoSell)
	out.settings = Settings.clean(data.settings)
	-- passes given as gifts (Config.Passes.GiftPacks)
	out.giftedPasses = {}
	for _, key in ipairs(Config.Passes.Order) do
		if type(data.giftedPasses) == "table" and data.giftedPasses[key] == true then
			out.giftedPasses[key] = true
		end
	end
	-- perks bought with VP, and the asset id chosen for each of their slots (digits only)
	for _, key in ipairs(Config.Perks.Order) do
		if type(data.perks) == "table" and data.perks[key] == true then
			out.perks[key] = true
		end
		for _, slot in ipairs(perkSlots(key)) do
			local id = type(data.perkIds) == "table" and data.perkIds[slot.Key]
			if type(id) == "string" and string.match(id, "^%d+$") and #id <= 20 then
				out.perkIds[slot.Key] = id
				-- the part of that sound that plays (the cropper)
				out.perkCrops[slot.Key] = type(data.perkCrops) == "table" and SoundCrop.clean(slot.Key, data.perkCrops[slot.Key]) or nil
			end
		end
	end
	if type(data.receipts) == "table" then
		for _, id in ipairs(data.receipts) do
			if type(id) == "string" and #out.receipts < Config.Shop.ReceiptHistory then
				table.insert(out.receipts, id)
			end
		end
	end
	-- the Discord: their verification code, and whether they verified (Config.Discord)
	out.discordCode = Economy.isDiscordCode(data.discordCode) and data.discordCode or ""
	out.discordDone = data.discordDone == true
	-- What's New: the newest patch they've seen, and the patches whose reading reward they took
	out.patchSeen = (type(data.patchSeen) == "string" and #data.patchSeen <= 40) and data.patchSeen or ""
	if type(data.patchClaimed) == "table" then
		local n = 0
		for id, v in pairs(data.patchClaimed) do
			if type(id) == "string" and #id <= 40 and v == true and n < 50 then
				out.patchClaimed[id] = true
				n = n + 1
			end
		end
	end
	-- lucky spins, the codes used, the daily streak, Robux spent, the gifts already delivered
	out.lucky = math.clamp(math.floor(tonumber(data.lucky) or 0), 0, 1000000)
	out.pity = Spins.cleanPity(data.pity) -- the Characters banner's pity counters and lucky pick
	out.favor = Spins.cleanFavor(data.favor) -- the characters whose odds you boosted or lowered
	if type(data.codes) == "table" then
		for k, v in pairs(data.codes) do
			if v == true and type(k) == "string" and #k <= 40 then
				out.codes[k] = true
			end
		end
	end
	if type(data.daily) == "table" then
		out.daily.last = math.max(0, math.floor(tonumber(data.daily.last) or 0))
		out.daily.streak = math.max(0, math.floor(tonumber(data.daily.streak) or 0))
	end
	if type(data.spent) == "table" then
		out.spent.robux = math.max(0, math.floor(tonumber(data.spent.robux) or 0))
		out.spent.gifts = math.max(0, math.floor(tonumber(data.spent.gifts) or 0))
	end
	if type(data.mailSeen) == "table" then
		for _, id in ipairs(data.mailSeen) do
			if type(id) == "string" and #id <= 80 and #out.mailSeen < Config.Gifts.MailSeen then
				table.insert(out.mailSeen, id)
			end
		end
	end
	out.liked = data.liked == true
	out.favorited = data.favorited == true -- Roblox's favorite prompt said they favorited the game
	-- player cards unlocked, the one worn, and the best leaderboard place reached
	if type(data.cards) == "table" then
		for k, v in pairs(data.cards) do
			if v == true and Cards.get(k) then
				out.cards[k] = true
			end
		end
	end
	if type(data.equip) == "table" and Cards.get(data.equip.Card) then
		out.equip.Card = data.equip.Card
	end
	-- (2026-10-21, the owner: "replace the people who had almighty card with True Almighty"): once,
	-- an Almighty card given before it became the Almighty rank's is a True Almighty card now
	out.almightyMoved = true
	if data.almightyMoved ~= true and out.cards.Almighty2 then
		out.cards.Almighty2 = nil
		out.cards.TrueAlmighty = true
		if out.equip.Card == "Almighty2" then
			out.equip.Card = "TrueAlmighty"
		end
	end
	-- ranked: this season's record and the past ones (Ranked.clean rolls an old season over)
	out.ranked = Ranked.clean(data.ranked, Ranked.season(os.time()))
	-- the AFK Lounge: today's payouts and the time towards the next (Lounge.clean)
	out.lounge = Lounge.clean(data.lounge, Lounge.day(os.time()))
	-- the leaderboard place over your head in the matchup intro: a board, or your best (nil)
	if type(data.equip) == "table" and Leaderboards.isBoard(data.equip.Entrance) then
		out.equip.Entrance = data.equip.Entrance
	end
	-- clans (ClanService): the tag colours bought, the one worn, the best clan board place reached
	out.clanColors = {}
	for _, c in ipairs(Config.Clans.TagColors) do
		if type(data.clanColors) == "table" and data.clanColors[c.Key] == true then
			out.clanColors[c.Key] = true
		end
	end
	out.clanColor = (type(data.clanColor) == "string" and (data.clanColor == "White" or out.clanColors[data.clanColor])) and data.clanColor or "White"
	if type(data.bestClanRank) == "table" and type(data.bestClanRank.tag) == "string" then
		local cr = math.floor(tonumber(data.bestClanRank.rank) or 0)
		if cr >= 1 then
			out.bestClanRank = { rank = cr, tag = string.sub(data.bestClanRank.tag, 1, Config.Clans.TagMax) }
		end
	end
	if type(data.bestRank) == "table" and Leaderboards.isBoard(data.bestRank.board) then
		local r = math.floor(tonumber(data.bestRank.rank) or 0)
		if r >= 1 and r <= Config.Leaderboards.Top then
			out.bestRank = { rank = r, board = data.bestRank.board }
		end
	end
	-- boost timers: the unix time each ends (Config.Boosts)
	if type(data.boosts) == "table" and tonumber(data.boosts.VP) then
		out.boosts.VP = math.max(0, math.floor(tonumber(data.boosts.VP)))
	end
	if type(data.boosts) == "table" and tonumber(data.boosts.Luck) then
		out.boosts.Luck = math.max(0, math.floor(tonumber(data.boosts.Luck)))
	end
	-- the bundles sold once (Config.Bundles) this player has bought, by name
	if type(data.bundles) == "table" then
		for _, b in ipairs(Config.Bundles.Packs) do
			if b.Once and data.bundles[b.Name] == true then
				out.bundles[b.Name] = true
			end
		end
	end
	return out
end

-- Everything is owned by a developer; otherwise what the profile holds.
local function owns(profile, kind, k)
	if profile.dev then
		return Spins.item(kind, k) ~= nil
	end
	return profile.owned[kind] ~= nil and profile.owned[kind][k] == true
end

-- The ranked score effects: reaching a rank this season earns that season's effect for it and the
-- ones under it (Ranked.effectsFor), and it's yours for good, past the season and past dropping
-- below the rank (the owner, 2026-10-25: "keep the rewards permanently its stupid if they get
-- removed"; until then: "if you lose the rank, you lose the explosion"). Returns whether anything
-- changed.
local function syncRankedEffects(profile)
	profile.ranked = Ranked.clean(profile.ranked, Ranked.season(os.time()))
	local held = Ranked.effectsFor(profile.ranked.rp, profile.ranked.season) -- (this season's only)
	profile.owned.Effect = profile.owned.Effect or {}
	local changed = false
	for _, item in ipairs(Config.Cosmetics.Effect or {}) do
		if item.Ranked and held[item.Key] and not profile.owned.Effect[item.Key] then
			profile.owned.Effect[item.Key] = true
			changed = true
		end
	end
	return changed
end

-- Anything equipped that this player doesn't own goes back to the default.
local function keepOwned(profile)
	for _, kind in ipairs(COS.Kinds) do
		if not owns(profile, kind, profile.equip[kind]) then
			profile.equip[kind] = Spins.default(kind)
		end
	end
	if not owns(profile, "Char", profile.char) then
		profile.char = Roster.Starters[1]
	end
	local card = profile.equip.Card
	if card and not (profile.dev or card == Cards.default() or profile.cards[card]) then
		profile.equip.Card = nil
	end
	for _, picks in pairs(profile.teams) do
		for role, id in pairs(picks) do
			if not owns(profile, "Char", id) then
				picks[role] = nil
			end
		end
	end
end

local function load(plr)
	local data, ok = nil, false
	if store then
		for _ = 1, 3 do
			local success, result = pcall(function()
				return store:GetAsync(key(plr))
			end)
			if success then
				data, ok = result, true
				break
			end
			task.wait(1)
		end
		if not ok and not warned then
			warned = true
			warn("[SpikeRush] Profiles couldn't load from the DataStore; progress this session won't be saved.")
		end
	end
	local profile = data and sanitizeProfile(data) or newProfile()
	-- only a profile that loaded (or was confirmed new) may ever be written back; in Studio the
	-- workspace attribute NoSave keeps a playtest from writing it (a test run while the owner plays
	-- the live game: the two sessions would overwrite each other's saves)
	profile.canSave = ok and not (RunService:IsStudio() and workspace:GetAttribute("NoSave") == true)
	profile.dev = isDeveloper(plr)
	syncRankedEffects(profile)
	keepOwned(profile)
	-- a player who left while the DataStore answered must not be cached (nothing would clear it)
	if plr.Parent then
		profiles[plr] = profile
	end
	return profile
end

-- Returns true when the profile is safely stored (or there was nothing to store).
local function save(plr, force)
	local profile = profiles[plr]
	if not profile or not store or not profile.canSave then
		return false
	end
	if not dirty[plr] and not force then
		return true
	end
	local payload = {
		v = VERSION,
		vp = profile.vp,
		gold = profile.gold,
		giftedPasses = profile.giftedPasses,
		freeSpins = profile.freeSpins,
		winStreak = profile.winStreak,
		bestStreak = profile.bestStreak,
		playTime = profile.playTime,
		playToday = profile.playToday,
		record = profile.record,
		tutorial = profile.tutorial,
		levels = profile.levels,
		owned = profile.owned,
		equip = profile.equip,
		char = profile.char,
		fav = profile.fav,
		teams = profile.teams,
		autoSell = profile.autoSell,
		settings = profile.settings,
		perks = profile.perks,
		perkIds = profile.perkIds,
		perkCrops = profile.perkCrops,
		receipts = profile.receipts,
		lucky = profile.lucky,
		codes = profile.codes,
		daily = profile.daily,
		patchSeen = profile.patchSeen,
		patchClaimed = profile.patchClaimed,
		discordCode = profile.discordCode,
		discordDone = profile.discordDone,
		spent = profile.spent,
		mailSeen = profile.mailSeen,
		liked = profile.liked,
		favorited = profile.favorited,
		boosts = profile.boosts,
		cards = profile.cards,
		bestRank = profile.bestRank,
		clanColors = profile.clanColors,
		almightyMoved = profile.almightyMoved,
		ranked = profile.ranked,
		clanColor = profile.clanColor,
		bestClanRank = profile.bestClanRank,
		pity = profile.pity,
		favor = profile.favor,
		fragments = profile.fragments,
		breaks = profile.breaks,
		bundles = profile.bundles,
		sTickets = profile.sTickets,
		retiredPaid = profile.retiredPaid,
		-- the Halloween event (Candy, scout points, today's first clears, the shop's buys) and the
		-- skins (the Reaper's copies and the characters they're on)
		halloween = profile.halloween,
		skins = profile.skins,
		rooms = profile.rooms,
		grave = profile.grave,
		lounge = profile.lounge,
	}
	local success = pcall(function()
		store:UpdateAsync(key(plr), function()
			return payload
		end)
	end)
	if success then
		dirty[plr] = nil
	end
	return success
end

-- The loaded profile, or nil while it's still loading (never waits).
function ProfileService.peek(plr)
	return profiles[plr]
end

-- Store a profile now (before a teleport, so the next server loads the latest).
function ProfileService.save(plr)
	return save(plr, true)
end

-- One DataStore read per player: a second caller (say the match assigning teams while the join
-- load is still waiting on the DataStore) waits for the first instead of loading again and
-- replacing the profile the first caller already handed out.
function ProfileService.get(plr)
	if profiles[plr] then
		return profiles[plr]
	end
	if loading[plr] then
		local waited = 0
		while loading[plr] and waited < 30 do
			waited = waited + task.wait()
		end
		if profiles[plr] then
			return profiles[plr]
		end
	end
	loading[plr] = true
	local ok, profile = pcall(load, plr)
	loading[plr] = nil
	if not ok then
		warn("[SpikeRush] profile load error: " .. tostring(profile))
		profile = newProfile()
		profile.canSave = false
		profile.dev = isDeveloper(plr)
		if plr.Parent then
			profiles[plr] = profile
		end
	end
	return profile
end

-- Practice as any character (the owner, 2026-10-17: "make it so in practice mode, any character
-- can be chosen"): player -> roster id, for that practice only (LobbyService sets it, PracticeService
-- clears it); with no upgrades of yours on it unless you own it.
local practiceAs = setmetatable({}, { __mode = "k" })
function ProfileService.setPracticeAs(plr, id)
	local c = type(id) == "string" and Roster.get(id) or nil
	practiceAs[plr] = c and c.Id or nil
	if profiles[plr] then
		ProfileService.applyActive(plr)
	end
end

-- The best character a player owns that isn't in `banned` (id -> true): the highest tier, then
-- the name. (A ranked ban moves its players onto it: MatchService.runBans.)
function ProfileService.bestOwnedExcept(plr, banned)
	local profile = ProfileService.get(plr)
	local best, bestRank = nil, -1
	for _, c in ipairs(Roster) do
		if not banned[c.Id] and owns(profile, "Char", c.Id) then
			local r = Characters.tierIndex(c.Tier) or 0
			if r > bestRank or (r == bestRank and best and c.Name < best.Name) then
				best, bestRank = c, r
			end
		end
	end
	return best and best.Id or nil
end

-- The roster character this player plays.
function ProfileService.character(plr)
	local profile = ProfileService.get(plr)
	local forced = practiceAs[plr] and Roster.get(practiceAs[plr])
	if forced then
		return forced
	end
	local c = Roster.get(profile.char)
	if not c or not owns(profile, "Char", c.Id) then
		c = Roster.get(Roster.Starters[1])
	end
	return c
end

-- Equipped cosmetics as attributes on the Player and its avatar, so every client draws them.
local function applyCosmetics(plr, profile)
	local char = plr.Character
	for _, kind in ipairs(COS.Kinds) do
		local attr = COS.Attribute[kind]
		local value = profile.equip[kind] or Spins.default(kind)
		plr:SetAttribute(attr, value)
		if char then
			char:SetAttribute(attr, value)
		end
	end
	-- the Rest in Peace gravestone's epitaph ("": their name) and picture (0: none), for every client
	local grave = profile.grave or Halloween.cleanGrave(nil)
	for _, inst in ipairs({ plr, char or plr }) do
		inst:SetAttribute("GraveText", grave.text)
		inst:SetAttribute("GraveImage", grave.image)
	end
end


-- Perks: owned when bought with VP, when the player owns the game pass, or for a developer.
local passes = {} -- plr -> { [perk] = true } for the game passes they own
local lastPerkSet = {}

local function hasPerk(plr, profile, key)
	return profile.dev == true or profile.perks[key] == true or (passes[plr] ~= nil and passes[plr][key] == true)
end

-- Each owned perk's ids as attributes on the Player and its avatar ("" for none), one per slot,
-- so every client plays that player's sounds (scoring, spikes, jumps...) and shows their image
-- when they score; a cropped sound also has <slot>Crop, the part that plays (SoundCrop).
local function applyPerks(plr, profile)
	local char = plr.Character
	for _, key in ipairs(Config.Perks.Order) do
		local owned = hasPerk(plr, profile, key)
		for _, slot in ipairs(perkSlots(key)) do
			local value = owned and profile.perkIds[slot.Key] or ""
			local c = owned and profile.perkCrops[slot.Key]
			local crop = c and NumberRange.new(c.s, c.s + c.l) or nil
			plr:SetAttribute(slot.Key, value)
			plr:SetAttribute(SoundCrop.attribute(slot.Key), crop)
			if char then
				char:SetAttribute(slot.Key, value)
				char:SetAttribute(SoundCrop.attribute(slot.Key), crop)
			end
		end
	end
end

-- Game passes (Config.Passes): owned when Roblox says so, or for a developer.
local ownedPasses = {} -- plr -> { [pass] = true }

local function passesOf(plr, profile)
	local out = {}
	for _, key in ipairs(Config.Passes.Order) do
		if profile.dev == true or (ownedPasses[plr] ~= nil and ownedPasses[plr][key] == true) or (type(profile.giftedPasses) == "table" and profile.giftedPasses[key] == true) then
			out[key] = true
		end
	end
	return out
end

-- What this player's passes multiply `kind` ("VP", "Gold", "Luck") by (MatchService's rewards).
function ProfileService.passMult(plr, kind)
	local profile = profiles[plr]
	return profile and Economy.passMult(passesOf(plr, profile), kind) or 1
end

-- A pass's chat tag as the ChatTag attribute on the Player (every client shows it), and the
-- player card it gives (kept for good, like a granted card).
local function applyPasses(plr, profile)
	local owned = passesOf(plr, profile)
	local tag = ""
	for _, key in ipairs(Config.Passes.Order) do
		local def = Config.Passes[key]
		if owned[key] then
			if def.Tag and tag == "" then
				tag = def.Tag
			end
			if def.Card and not profile.dev and not profile.cards[def.Card] then
				profile.cards[def.Card] = true
				dirty[plr] = true
			end
		end
	end
	plr:SetAttribute("ChatTag", tag)
end

------------------------------------------------------------------------------------------
-- player cards (Config.Cards)
------------------------------------------------------------------------------------------

-- How many characters a profile has recruited (a developer has them all).
local function ownedCount(profile)
	if profile.dev then
		return #Roster
	end
	local n = 0
	for _ in pairs(profile.owned.Char or {}) do
		n = n + 1
	end
	return n
end

local function cardUnlocked(profile, key)
	return profile.dev == true or key == Cards.default() or profile.cards[key] == true
end

local function cardStats(profile)
	return Cards.stats(profile, ownedCount(profile))
end

-- The card a player wears, and what it shows, as attributes on the Player and its avatar
-- (PlayerCard, CardValue, CardLabel, CardRank), so every client draws their card when they score.
local function applyCard(plr, profile)
	local key = profile.equip.Card
	if not (Cards.get(key) and cardUnlocked(profile, key)) then
		key = Cards.default()
	end
	local stats = cardStats(profile)
	local value, label = Cards.display(Cards.get(key), stats)
	for _, inst in ipairs({ plr, plr.Character or plr }) do
		inst:SetAttribute("PlayerCard", key)
		inst:SetAttribute("CardValue", value)
		inst:SetAttribute("CardLabel", label)
		inst:SetAttribute("CardRank", stats.rank or 0)
		inst:SetAttribute("CardRp", stats.rankedRp) -- (the Ranked card's colours and badge)
	end
end

-- Takes a given card back (the owner: "i need to remove almighty card", "from people i accidently
-- gave"); one they wear goes back to the default. Returns whether they had it.
local function takeCard(plr, profile, key)
	local had = profile.cards[key] == true
	profile.cards[key] = nil
	if profile.equip.Card == key then
		profile.equip.Card = nil
	end
	dirty[plr] = true
	applyCard(plr, profile)
	return had
end

-- Player profiles (the owner: "add player profiles that display all that, but also your stats
-- and your leaderboard standings as well. these stats are spikes blocks, etc"): what anyone may
-- see of a player: the card they wear (and what it shows), their character, their record and
-- their place on every board. From this server's profile when they're here, else read from the
-- store (kept a minute; each asker gets one every PROFILE_GAP seconds).
local PROFILE_KEEP, PROFILE_GAP = 60, 1.5
local publicKept = {} -- userId -> { at, data }
local lastLook = {} -- plr -> when they last asked

local function publicOf(profile, userId, name)
	local stats = cardStats(profile)
	local cardKey = profile.equip and profile.equip.Card
	if not (Cards.get(cardKey) and cardUnlocked(profile, cardKey)) then
		cardKey = Cards.default()
	end
	local value, label = Cards.display(Cards.get(cardKey), stats)
	local c = Roster.get(profile.char or "")
	local unlocked = 0
	for _, card in ipairs(Cards.list()) do
		if cardUnlocked(profile, card.Key) then
			unlocked = unlocked + 1
		end
	end
	return {
		userId = userId,
		name = name,
		card = { key = cardKey, value = value, label = label, rank = stats.rank, rp = stats.rankedRp },
		char = c and c.Id or nil,
		record = {
			matches = stats.matches,
			wins = stats.wins,
			losses = stats.losses,
			winPct = stats.winPct,
			kills = stats.kills,
			aces = stats.aces,
			blocks = stats.blocks,
			mvps = stats.mvps,
			bestStreak = stats.bestStreak,
			winStreak = stats.winStreak,
		},
		owned = stats.owned,
		cards = unlocked,
		places = reg.LeaderboardService and reg.LeaderboardService.placesOf(userId) or {},
	}
end

function ProfileService.publicProfile(userId)
	local plr = Players:GetPlayerByUserId(userId)
	if plr and profiles[plr] then
		local s = publicOf(profiles[plr], userId, plr.DisplayName)
		s.username = plr.Name -- (the display name isn't what admin tools look people up by)
		return s
	end
	local kept = publicKept[userId]
	if kept and os.clock() - kept.at < PROFILE_KEEP then
		kept.data.places = reg.LeaderboardService and reg.LeaderboardService.placesOf(userId) or kept.data.places
		return kept.data
	end
	if not store then
		return nil
	end
	local ok, data = pcall(function()
		return store:GetAsync("u_" .. tostring(userId))
	end)
	if not ok or type(data) ~= "table" then
		return nil
	end
	local name, username = "Player", nil
	local okName, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync({ userId })
	end)
	if okName and type(infos) == "table" and infos[1] then
		name = infos[1].DisplayName or infos[1].Username or name
		username = infos[1].Username
	end
	local summary = publicOf(sanitizeProfile(data), userId, name)
	summary.username = username
	publicKept[userId] = { at = os.clock(), data = summary }
	return summary
end

-- The tier and build this player plays: their character with its upgrades and breakthroughs
-- (the level, 0..5, comes back last: its ability grows with it).
function ProfileService.characterBuild(plr)
	local c = ProfileService.character(plr)
	local profile = ProfileService.get(plr)
	local brk = profile.breaks and profile.breaks[c.Id] or 0
	local tier, build = Characters.fromRoster(c, profile.levels[c.Id], brk)
	return c, tier, build, brk
end

-- The skin this player shows on a character (applied and switched on), or nil.
function ProfileService.skinFor(plr, charId)
	local profile = profiles[plr]
	return profile and Halloween.skinOf(profile.skins, charId) or nil
end

-- Write the active character onto the Player (and its avatar) so clients can read it.
function ProfileService.applyActive(plr)
	local c, tier, build, brk = ProfileService.characterBuild(plr)
	-- (always the character's own: a Halloween Match's ability cards stack beside it, in the
	-- "Abilities" TeamService writes during a match)
	local ability = c.Ability or ""
	local char = plr.Character
	for _, inst in ipairs({ plr, char or plr }) do
		Characters.writeAttributes(inst, tier, build)
		inst:SetAttribute("Ability", ability)
		inst:SetAttribute("Skin", ProfileService.skinFor(plr, c.Id))
		inst:SetAttribute("Break", brk > 0 and brk or nil)
		inst:SetAttribute("CharId", c.Id)
		inst:SetAttribute("CharName", c.Name)
		inst:SetAttribute("CharRole", c.Role)
	end
	if char then
		reg.CharacterService.applyStats(char, Characters.derive(tier, build))
	end
	applyCosmetics(plr, ProfileService.get(plr))
	applyPerks(plr, ProfileService.get(plr))
	applyPasses(plr, ProfileService.get(plr))
	applyCard(plr, ProfileService.get(plr))
end

local function teamsCopy(profile)
	local out = {}
	for mode, picks in pairs(profile.teams or {}) do
		out[mode] = table.clone(picks)
	end
	return out
end

-- Your AI teammate for `role` in your `size` team: the character, its tier and your build of it
-- (your upgrades), or nil when you haven't picked one (a random bot plays it).
function ProfileService.teamPick(plr, size, role)
	local profile = profiles[plr]
	local picks = profile and profile.teams[size .. "v" .. size]
	local c = picks and Roster.get(picks[role] or "")
	if not c or not owns(profile, "Char", c.Id) then
		return nil
	end
	local brk = profile.breaks and profile.breaks[c.Id] or 0
	local tier, build = Characters.fromRoster(c, profile.levels[c.Id], brk)
	return c, tier, build, brk
end

function ProfileService.snapshot(plr)
	local profile = ProfileService.get(plr)
	local owned = {}
	for _, kind in ipairs(Spins.Kinds) do
		owned[kind] = {}
		for _, item in ipairs(Spins.items(kind)) do
			if owns(profile, kind, item.Key) then
				owned[kind][item.Key] = true
			end
		end
	end
	local levels = {}
	for id in pairs(owned.Char) do
		local c = Roster.get(id)
		local lv = {}
		for _, stat in ipairs(Config.Stats.Order) do
			lv[stat] = Characters.statLevel(c, profile.levels[id], stat)
		end
		levels[id] = lv
	end
	return {
		vp = profile.vp,
		gold = profile.gold,
		freeSpins = profile.freeSpins or 0,
		winStreak = profile.winStreak or 0,
		bestStreak = profile.bestStreak or 0,
		playTime = profile.playTime or 0,
		playToday = profile.playToday and { day = profile.playToday.day, secs = profile.playToday.secs, claimed = table.clone(profile.playToday.claimed or {}) } or nil,
		record = table.clone(profile.record),
		tutorial = { steps = table.clone(profile.tutorial.steps), done = profile.tutorial.done },
		levels = levels,
		owned = owned,
		equip = table.clone(profile.equip),
		char = ProfileService.character(plr).Id,
		fav = table.clone(profile.fav or {}),
		teams = teamsCopy(profile),
		autoSell = Spins.cleanAutoSell(profile.autoSell),
		settings = profile.settings,
		perks = (function()
			local out = {}
			for _, key in ipairs(Config.Perks.Order) do
				local ids, crops = {}, {}
				for _, slot in ipairs(perkSlots(key)) do
					ids[slot.Key] = profile.perkIds[slot.Key]
					crops[slot.Key] = profile.perkCrops[slot.Key]
				end
				out[key] = { owned = hasPerk(plr, profile, key), id = profile.perkIds[key], ids = ids, crops = crops }
			end
			return out
		end)(),
		autoRolling = profile.autoRolling and profile.autoRolling.banner or nil,
		fragments = table.clone(profile.fragments or {}),
		breaks = table.clone(profile.breaks or {}),
		dev = profile.dev or nil,
		admin = (profile.dev or (reg.AdminService and reg.AdminService.whitelisted(plr.UserId))) or nil, -- the admin panel (developers, and whoever the owner's whitelist lets in)
		adminOwner = (reg.AdminService and reg.AdminService.isOwner(plr)) or nil, -- the admin whitelist (the game's owner alone)
		cards = (function()
			local unlocked = {}
			for _, card in ipairs(Cards.list()) do
				if cardUnlocked(profile, card.Key) then
					unlocked[card.Key] = true
				end
			end
			return { unlocked = unlocked, stats = cardStats(profile) }
		end)(),
		lucky = profile.lucky or 0,
		sTickets = profile.sTickets or 0, -- selection tickets (Config.Retired)
		-- the Characters banner's pity: recruits counted toward each, whether the next lucky pity is
		-- your pick, and the pick
		pity = { normal = profile.pity.normal, top = profile.pity.top, lucky = profile.pity.lucky, owed = profile.pity.owed, pick = profile.pity.pick },
		favor = profile.favor, -- boosted ("up") and lowered ("down") characters
		favorited = profile.favorited == true or RunService:IsStudio(), -- codes and daily rewards need it
		liked = profile.liked == true or RunService:IsStudio(), -- and the like (their word)
		boostVP = math.max(0, (profile.boosts.VP or 0) - os.time()), -- seconds left on their 2x VP
		-- and on their strongest Luck boost, and its strength (2x to 16x)
		boostLuck = (function()
			local m, untilT = Economy.luckBoost(profile, os.time())
			return untilT and math.max(0, untilT - os.time()) or 0
		end)(),
		boostLuckMul = (Economy.luckBoost(profile, os.time())),
		passes = passesOf(plr, profile), -- the game passes they own (Config.Passes)
		bundles = table.clone(profile.bundles), -- the once-only bundles they bought
		grave = profile.grave, -- the Rest in Peace gravestone (Config.Grave)
		lounge = profile.lounge and Lounge.clean(profile.lounge, Lounge.day(os.time())) or nil, -- the AFK Lounge today (LoungeService)
		-- this season's ranked record (the Ranked window, the Ranks screen; it was never sent, so every
		-- client showed Bronze I at 0 RP)
		ranked = Ranked.clean(profile.ranked, Ranked.season(os.time())),
		group = groupId(),
		member = groupMember[plr], -- nil until it's known
		daily = (function()
			local now = os.time()
			local d = Economy.daily(profile.daily, now)
			return { ready = d.ready, day = d.day, streak = d.streak, lapsed = d.lapsed, opensIn = math.max(0, d.opensAt - now) }
		end)(),
		saving = profile.canSave and store ~= nil,
		studio = RunService:IsStudio(),
		-- What's New: the newest patch seen, and whether its reading reward is taken
		patch = (function()
			local latest = PatchNotes.latest()
			return { seen = profile.patchSeen or "", claimed = latest ~= nil and (profile.patchClaimed or {})[latest.Id] == true }
		end)(),
		-- the Discord: their verification code ("" until they ask for one) and whether it's done
		discord = { code = profile.discordCode or "", done = profile.discordDone == true },
		-- the Halloween event (Config.Halloween): Candy, scout points, today's first clears (by
		-- difficulty), the Candy shop's buys, and the skins (copies, and the characters they're on)
		halloween = (function()
			local ev = profile.halloween
			local today = ev.day == Halloween.day(os.time())
			return { candy = ev.candy, scout = ev.scout, cleared = today and table.clone(ev.cleared) or {}, bought = table.clone(ev.bought), endsIn = Halloween.secondsLeft(os.time()) }
		end)(),
		skins = (function()
			local out = {}
			for key, row in pairs(profile.skins) do
				out[key] = { copies = row.copies, free = Halloween.freeCopies(profile.skins, key), on = table.clone(row.on) }
			end
			return out
		end)(),
		-- Home's rooms: the ones won, and the one shown
		rooms = { owned = table.clone(profile.rooms.owned), on = Rooms.current(profile.rooms, profile.dev) },
	}
end

local function push(plr, notice, reveal)
	local snap = ProfileService.snapshot(plr)
	snap.notice = notice
	snap.reveal = reveal
	Net.get("Profile"):FireClient(plr, snap)
end

-- Sends a player their profile again, with a notice (AdminService: they were let into the admin
-- panel or out of it). Nothing before their profile loads.
function ProfileService.pushTo(plr, notice)
	if profiles[plr] then
		push(plr, notice)
	end
end

local function inMatch(plr)
	local TS = reg.TeamService
	return TS.inMatch and TS.entityForPlayer(plr) ~= nil
end

-- Unlocks every card whose achievement is now met (for good), and tells the player unless
-- `quiet` (their first load). Refreshes what their card shows either way.
function ProfileService.checkCards(plr, quiet)
	local profile = profiles[plr]
	if not profile then
		return
	end
	local stats = cardStats(profile)
	local new = {}
	for _, card in ipairs(Cards.list()) do
		if card.Stat and not profile.cards[card.Key] and Cards.met(card, stats) then
			profile.cards[card.Key] = true
			table.insert(new, card.Name)
		end
	end
	if #new > 0 then
		dirty[plr] = true
	end
	applyCard(plr, profile)
	if #new > 0 and not quiet and not profile.dev then
		push(plr, string.format("New player card%s: %s! Wear it from the Locker.", #new > 1 and "s" or "", table.concat(new, ", ")))
	end
end

-- The match MVP (MatchService): the MVP count goes up (the MVP card).
function ProfileService.addMvp(plr)
	local profile = profiles[plr]
	if not profile then
		return
	end
	profile.record.mvps = (profile.record.mvps or 0) + 1
	dirty[plr] = true
	ProfileService.checkCards(plr)
	if reg.ClanService then
		reg.ClanService.onRecord(plr)
	end
end

-- A place in a leaderboard's top 3 (LeaderboardService): kept if it's their best yet (the Top 3
-- and Number One cards show it).
function ProfileService.topRank(plr, rank, board)
	local profile = profiles[plr]
	if not profile or not Leaderboards.isBoard(board) then
		return
	end
	local best = profile.bestRank
	if best and best.rank <= rank then
		return
	end
	profile.bestRank = { rank = rank, board = board }
	dirty[plr] = true
	ProfileService.checkCards(plr)
end

-- Their clan's place on the clans' board (ClanService, the top 3): kept if it's their best yet (the
-- ClanTop3 and ClanNumber1 cards show it).
function ProfileService.clanRank(plr, rank, tag)
	local profile = profiles[plr]
	if not profile or type(rank) ~= "number" or rank < 1 then
		return
	end
	local best = profile.bestClanRank
	if best and best.rank <= rank then
		return
	end
	profile.bestClanRank = { rank = rank, tag = tag }
	dirty[plr] = true
	ProfileService.checkCards(plr)
end

-- A ranked match's result (MatchService): the season rolled over if it's turned, the RP moved by
-- the other team's average (`theirs`). Returns the change and the RP after it.
function ProfileService.rankedResult(plr, won, theirs)
	local profile = profiles[plr]
	if not profile then
		return nil
	end
	profile.ranked = Ranked.clean(profile.ranked, Ranked.season(os.time()))
	local before = Ranked.name(profile.ranked.rp)
	local d = Ranked.apply(profile.ranked, won, theirs)
	dirty[plr] = true
	if syncRankedEffects(profile) then
		keepOwned(profile) -- (dropped under a rank: its effect comes off)
		applyCosmetics(plr, profile)
	end
	local after = Ranked.name(profile.ranked.rp)
	ProfileService.checkCards(plr)
	push(plr, string.format("Ranked: %s%d RP  (%s%s)", d >= 0 and "+" or "", d, after, after ~= before and (d > 0 and ", up from " .. before or ", down from " .. before) or ""))
	return d, profile.ranked.rp
end

-- Leaving a ranked match early (MatchService.onLeaving): its loss, the leave penalty and the queue
-- lock (Ranked.leave), saved with them; rejoining it undoes all of it (rankedUnleave).
function ProfileService.rankedLeave(plr, theirs, key, code, job)
	local profile = profiles[plr]
	if not profile then
		return nil
	end
	profile.ranked = Ranked.clean(profile.ranked, Ranked.season(os.time()))
	local d, secs = Ranked.leave(profile.ranked, theirs, os.time(), key, code, job)
	dirty[plr] = true
	if syncRankedEffects(profile) then
		keepOwned(profile)
	end
	return d, secs
end

function ProfileService.rankedUnleave(plr, key)
	local profile = profiles[plr]
	if not profile then
		return false
	end
	profile.ranked = Ranked.clean(profile.ranked, Ranked.season(os.time()))
	if Ranked.unleave(profile.ranked, key) then
		dirty[plr] = true
		if syncRankedEffects(profile) then
			keepOwned(profile)
			applyCosmetics(plr, profile)
		end
		push(plr, "Welcome back: your leave penalty is lifted.")
		return true
	end
	return false
end

-- The ranked record as it stands (rolled over), or nil.
function ProfileService.rankedRecord(plr)
	local profile = profiles[plr]
	if not profile then
		return nil
	end
	profile.ranked = Ranked.clean(profile.ranked, Ranked.season(os.time()))
	return profile.ranked
end

-- Forget the match you left (you chose not to rejoin it; the penalty stays).
function ProfileService.rankedForgetLeave(plr)
	local rec = ProfileService.rankedRecord(plr)
	if rec and rec.left then
		rec.left = nil
		dirty[plr] = true
		push(plr)
	end
end

-- A player's ranked RP right now (their season rolled over first).
function ProfileService.rankedRp(plr)
	local profile = profiles[plr]
	if not profile then
		return 0
	end
	profile.ranked = Ranked.clean(profile.ranked, Ranked.season(os.time()))
	return profile.ranked.rp
end

-- A change made to a profile from outside (ClanService's tag colours): saved and sent.
-- The AFK Lounge's record (LoungeService), rolled over to today; changed in place, so call
-- markDirty after. Nil while the profile loads.
function ProfileService.lounge(plr)
	local profile = profiles[plr]
	if not profile then
		return nil
	end
	local today = Lounge.day(os.time())
	if type(profile.lounge) ~= "table" or profile.lounge.day ~= today then
		profile.lounge = Lounge.clean(profile.lounge, today)
	end
	return profile.lounge
end

function ProfileService.markDirty(plr)
	if profiles[plr] then
		dirty[plr] = true
	end
end

-- Whether a player has a pass (Config.Passes: bought, gifted, or a developer).
function ProfileService.hasPass(plr, key)
	local profile = profiles[plr]
	return profile ~= nil and passesOf(plr, profile)[key] == true
end

function ProfileService.touch(plr, notice)
	if profiles[plr] then
		dirty[plr] = true
		push(plr, notice)
	end
end



------------------------------------------------------------------------------------------
-- grants and mail (codes, daily rewards, gifts, the admin panel's Give)
------------------------------------------------------------------------------------------

-- Whether a player may use codes and claim daily rewards (the owner: in the group, and they've
-- favorited the game; Studio counts as both). Returns nil, or what's missing. Asks Roblox about
-- the group, so it can yield.
local function claimBlocker(plr, profile)
	if not inGroup(plr, true) then
		return "Join the group first"
	end
	if not profile.favorited and not RunService:IsStudio() then
		return "Favorite the game first"
	end
	if not profile.liked and not RunService:IsStudio() then
		return "Like the game first"
	end
	return nil
end

-- "5h 12m"
local function waitText(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", math.max(1, m))
end

local function mailKey(userId)
	return "u_" .. tostring(userId)
end

local function seenMail(profile, id)
	for _, s in ipairs(profile.mailSeen) do
		if s == id then
			return true
		end
	end
	return false
end

-- Hands an online player a gift once (its id is remembered). Returns whether it was new.
local function deliver(plr, profile, id, g, from, note)
	if seenMail(profile, id) then
		return false
	end
	local added = Economy.apply(profile, g, os.time())
	if #(g.Passes or {}) > 0 or #(g.Perks or {}) > 0 then
		applyPasses(plr, profile) -- (a gifted pass's tag and card, a perk's ids)
		applyPerks(plr, profile)
	end
	table.insert(profile.mailSeen, 1, id)
	while #profile.mailSeen > Config.Gifts.MailSeen do
		table.remove(profile.mailSeen)
	end
	dirty[plr] = true
	local what = Economy.describe(g, added)
	local msg = from and string.format("%s sent you %s!", from, what) or string.format("You got %s!", what)
	if note and note ~= "" then
		msg = msg .. " " .. note
	end
	push(plr, msg)
	return true
end

-- An admin's stats wipe (the owner: "i dont believe this person has 2k wins... how do i wipe the
-- data"): the match record and the win streaks go back to zero; VP, Gold, characters, cosmetics
-- and purchases stay. Once per mail id, like a gift.
local function wipeStats(plr, profile, id)
	if seenMail(profile, id) then
		return false
	end
	profile.record = { matches = 0, wins = 0, kills = 0, aces = 0, blocks = 0, mvps = 0, devWins = 0 }
	profile.winStreak = 0
	profile.bestStreak = 0
	table.insert(profile.mailSeen, 1, id)
	while #profile.mailSeen > Config.Gifts.MailSeen do
		table.remove(profile.mailSeen)
	end
	dirty[plr] = true
	if reg.LeaderboardService then
		task.spawn(reg.LeaderboardService.forget, plr.UserId)
	end
	push(plr, "Your match stats were reset by the developers.")
	return true
end

-- An admin's rank reset (the owner, 2026-10-25: "add a rankreset button to the admin panel to
-- counter alt farmers"): this season's RP, wins, losses and peak go back to zero, and the best
-- rank ever too (what a farmed climb earned); past seasons stay in the history. Once per mail id.
local function resetRank(plr, profile, id)
	if seenMail(profile, id) then
		return false
	end
	local rk = Ranked.clean(profile.ranked, Ranked.season(os.time()))
	rk.rp, rk.wins, rk.losses, rk.peak, rk.best = 0, 0, 0, 0, 0
	profile.ranked = rk
	table.insert(profile.mailSeen, 1, id)
	while #profile.mailSeen > Config.Gifts.MailSeen do
		table.remove(profile.mailSeen)
	end
	dirty[plr] = true
	if reg.LeaderboardService then
		task.spawn(reg.LeaderboardService.forget, plr.UserId, { "ranked" })
	end
	push(plr, "Your ranked rank was reset by the developers.")
	return true
end

-- Wipe a player's match stats (`rank`: reset their rank instead): at once if they're in this
-- server, else through the mail (their server picks it up right away if they're online, or they
-- get it when they next join). The leaderboards drop them either way. Returns ok and, if not, why.
function ProfileService.wipeUser(userId, rank)
	local id = (rank and "rank-" or "wipe-") .. HttpService:GenerateGUID(false)
	if reg.LeaderboardService then
		task.spawn(reg.LeaderboardService.forget, userId, rank and { "ranked" } or nil)
	end
	local plr = Players:GetPlayerByUserId(userId)
	local profile = plr and profiles[plr]
	if profile then
		if rank then
			resetRank(plr, profile, id)
		else
			wipeStats(plr, profile, id)
		end
		save(plr, true)
		push(plr)
		return true
	end
	if not mailStore then
		return false, "They aren't in this server, and reaching other servers needs DataStore access."
	end
	local ok, err = pcall(function()
		mailStore:UpdateAsync(mailKey(userId), function(old)
			local list = (type(old) == "table" and type(old.list) == "table") and old.list or {}
			table.insert(list, { id = id, wipe = not rank or nil, rankReset = rank and true or nil, t = os.time() })
			while #list > 100 do
				table.remove(list, 1)
			end
			return { list = list }
		end)
	end)
	if not ok then
		return false, "It couldn't be sent: " .. tostring(err)
	end
	if reg.AdminService then
		reg.AdminService.pingMail(userId)
	end
	return true
end

-- Takes a given card (Config.Cards, Grant) back from anyone by user id: now if they're in this
-- server, else through their mail when they're next in the game (after any gift still waiting
-- there, so a card sent by mistake and not opened yet goes too).
function ProfileService.takeCardFrom(userId, key)
	local card = Cards.get(key)
	if not card or not card.Grant then
		return false, "Only cards given from the admin panel can be taken back."
	end
	local plr = Players:GetPlayerByUserId(userId)
	local profile = plr and profiles[plr]
	if profile then
		local had = takeCard(plr, profile, key)
		save(plr, true)
		push(plr)
		return true, had and "now" or "now (they didn't have it)"
	end
	if not mailStore then
		return false, "They aren't in this server, and reaching other servers needs DataStore access."
	end
	local ok, err = pcall(function()
		mailStore:UpdateAsync(mailKey(userId), function(old)
			local list = (type(old) == "table" and type(old.list) == "table") and old.list or {}
			table.insert(list, { id = "take-" .. HttpService:GenerateGUID(false), takeCard = key, t = os.time() })
			while #list > 100 do
				table.remove(list, 1)
			end
			return { list = list }
		end)
	end)
	if not ok then
		return false, "It couldn't be sent: " .. tostring(err)
	end
	if reg.AdminService then
		reg.AdminService.pingMail(userId)
	end
	return true, "when they're next in the game (at once if they're online)"
end

-- Gives a player in this server a clean grant (Economy.cleanGrant) with a notice. Returns the
-- characters it added.
function ProfileService.grant(plr, g, notice)
	local profile = profiles[plr]
	if not profile then
		return nil
	end
	local added = Economy.apply(profile, g, os.time())
	dirty[plr] = true
	push(plr, notice)
	return added
end

-- Sends a clean grant to any player by user id: at once if they're in this server, otherwise into
-- their mail, and their server (if they're online in one) is told to open it. `id` makes it arrive
-- once however often it's sent (a gift's purchase id). Returns true, or false and why.
function ProfileService.giveUser(userId, g, from, note, id)
	id = id or HttpService:GenerateGUID(false)
	local plr = Players:GetPlayerByUserId(userId)
	local profile = plr and profiles[plr]
	if profile then
		deliver(plr, profile, id, g, from, note)
		save(plr, true)
		return true
	end
	if not mailStore then
		return false, "They aren't in this server, and sending to other servers needs DataStore access."
	end
	local ok, err = pcall(function()
		mailStore:UpdateAsync(mailKey(userId), function(old)
			local list = (type(old) == "table" and type(old.list) == "table") and old.list or {}
			for _, m in ipairs(list) do
				if type(m) == "table" and m.id == id then
					return nil -- already sent
				end
			end
			table.insert(list, { id = id, g = g, from = from, note = note, t = os.time() })
			while #list > 100 do
				table.remove(list, 1)
			end
			return { list = list }
		end)
	end)
	if not ok then
		return false, "It couldn't be sent: " .. tostring(err)
	end
	if reg.AdminService then
		reg.AdminService.pingMail(userId)
	end
	return true
end

-- Opens a player's mail: every gift not delivered yet is, then the profile is saved, and only then
-- are they cleared from the mail (so neither a crash nor a retry can repeat or lose one).
function ProfileService.checkMail(plr)
	local profile = profiles[plr]
	if not profile or not mailStore or not profile.canSave or mailBusy[plr] then
		return
	end
	mailBusy[plr] = true
	local ok, data = pcall(function()
		return mailStore:GetAsync(mailKey(plr.UserId))
	end)
	local list = ok and type(data) == "table" and type(data.list) == "table" and data.list or nil
	if list and #list > 0 and profiles[plr] then
		local ids = {}
		for _, m in ipairs(list) do
			if type(m) == "table" and type(m.id) == "string" then
				ids[m.id] = true
				if m.rankReset == true then
					resetRank(plr, profile, m.id)
				elseif m.wipe == true then
					wipeStats(plr, profile, m.id)
				elseif type(m.takeCard) == "string" then
					takeCard(plr, profile, m.takeCard)
				else
					deliver(plr, profile, m.id, Economy.cleanGrant(m.g), type(m.from) == "string" and m.from or nil, type(m.note) == "string" and m.note or nil)
				end
			end
		end
		if save(plr, true) then
			pcall(function()
				mailStore:UpdateAsync(mailKey(plr.UserId), function(old)
					if type(old) ~= "table" or type(old.list) ~= "table" then
						return nil
					end
					local keep = {}
					for _, m in ipairs(old.list) do
						if not (type(m) == "table" and ids[m.id]) then
							table.insert(keep, m)
						end
					end
					return { list = keep }
				end)
			end)
		end
	end
	mailBusy[plr] = nil
end

-- A code: known, not used by this player yet, and they're in the group and favorited the game.
local function redeemCode(plr, profile, text)
	local g, why, key = Economy.code(text, os.time())
	if not g then
		push(plr, why == "expired" and "That code has expired." or "That code doesn't exist.")
		return
	end
	if profile.codes[key] then
		push(plr, "You've already used that code.")
		return
	end
	local blocker = claimBlocker(plr, profile)
	if blocker then
		push(plr, blocker .. ", then the code works.")
		return
	end
	if not profiles[plr] or profile.codes[key] then
		return
	end
	profile.codes[key] = true
	local added = Economy.apply(profile, g, os.time())
	dirty[plr] = true
	save(plr, true)
	push(plr, string.format("Code %s: %s!", string.upper(key), Economy.describe(g, added)))
end

-- The daily reward: once per Config.Daily.Cooldown, the streak's day, for group members who favorited
-- the game.
local function claimDaily(plr, profile)
	local blocker = claimBlocker(plr, profile)
	if blocker then
		push(plr, blocker .. ", then claim your daily reward.")
		return
	end
	if not profiles[plr] then
		return
	end
	local now = os.time()
	local d = Economy.daily(profile.daily, now)
	if not d.ready then
		push(plr, "Your next daily reward opens in " .. waitText(d.opensAt - now) .. ".")
		return
	end
	profile.daily = { last = now, streak = d.streak }
	-- (earned, so the 2x VP event, boost and passes multiply its VP: vpMult)
	local mult = ProfileService.vpMult(plr)
	local g = Economy.earnedGrant(d.grant, mult)
	local added = Economy.apply(profile, g, os.time())
	dirty[plr] = true
	save(plr, true)
	push(plr, string.format("Day %d reward: %s%s!", d.day, Economy.describe(g, added), (g.VP > 0 and mult > 1) and string.format(" (%gx VP)", mult) or ""))
end

-- A player's user id from what was typed: a username, or a user id. Returns the id, or nil and
-- why. Asks Roblox, so it yields.
function ProfileService.findUser(text)
	local id = type(text) == "string" and tonumber(string.match(text, "^%s*(%d+)%s*$")) or nil
	if id then
		return id
	end
	local name = type(text) == "string" and string.match(text, "^%s*([%w_]+)%s*$") or nil
	if not name or #name < 3 or #name > 20 then
		return nil, "That isn't a username or a user id."
	end
	local ok, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	if not ok or type(userId) ~= "number" then
		return nil, "Nobody is called " .. name .. "."
	end
	return userId
end

-- A pack bought for someone else: (kind, index, username). The recipient is looked up, then the
-- purchase is prompted; ProcessReceipt sends them the pack.
local function giftStart(plr, kind, index, username)
	local entry = Economy.pack(kind, index)
	if not entry or type(username) ~= "string" or entry.pack.Once then
		return
	end
	local userId, why = ProfileService.findUser(username)
	if not userId then
		push(plr, why)
		return
	end
	local name = username
	if userId == plr.UserId then
		push(plr, "That's you: buy it without Gift.")
		return
	end
	-- a pass they already own from Roblox (a gift of it would be wasted)
	for _, key in ipairs(entry.pack.Passes or {}) do
		local def = Config.Passes[key]
		local okOwn, owns = pcall(function()
			return def.PassId ~= 0 and MarketplaceService:UserOwnsGamePassAsync(userId, def.PassId)
		end)
		if okOwn and owns then
			push(plr, string.format("They already have the %s pass.", def.Name))
			return
		end
	end
	local okName, real = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	name = okName and type(real) == "string" and real or name
	if entry.id == 0 then
		-- no product yet: Studio sends it free, so gifting can be tried
		if RunService:IsStudio() then
			local sent, why = ProfileService.giveUser(userId, Economy.packGrant(entry), plr.DisplayName, nil, "studio:" .. HttpService:GenerateGUID(false))
			push(plr, sent and string.format("Sent %s to %s (free in Studio).", entry.pack.Name, name) or why)
		else
			push(plr, "That pack isn't on sale yet.")
		end
		return
	end
	pendingGift[plr] = { productId = entry.id, userId = userId, name = name, t = os.clock() }
	pcall(function()
		MarketplaceService:PromptProductPurchase(plr, entry.id)
	end)
end

-- What a player's own boost timers multiply `kind` ("VP") by right now (MatchService's rewards).
function ProfileService.boost(plr, kind)
	local profile = profiles[plr]
	return profile and Economy.boost(profile, kind, os.time()) or 1
end

-- What this player's earned VP is multiplied by right now (Economy.earnedVP): the admin panel's
-- 2x VP event, their own 2x VP boost (Config.Boosts) and their passes (Config.Passes), all
-- multiplied. Matches, the MVP bonus, tournament prizes and daily rewards pay it; codes, gifts,
-- Robux packs, refunds, sales and one-off rewards (the tutorial, Discord, patch notes, the Candy
-- shop) don't (the owner, 2026-10-16: "only like earnable stuff, like tournaments and matches and
-- daily rewords. not codes").
function ProfileService.vpMult(plr)
	local event = reg.AdminService and reg.AdminService.multiplier("VP") or 1
	local clan = reg.ClanService and reg.ClanService.bonus(plr, "VP") or 1 -- (their clan's V Point gain upgrade)
	return event * ProfileService.boost(plr, "VP") * ProfileService.passMult(plr, "VP") * clan
end

function ProfileService.award(plr, vp, gold)
	local profile = profiles[plr]
	if not profile then
		return
	end
	profile.vp = profile.vp + math.max(0, math.floor(vp or 0))
	profile.gold = profile.gold + math.max(0, math.floor(gold or 0))
	dirty[plr] = true
	push(plr)
end

-- Pays a tournament's prize (LobbyService): its VP times vpMult. Returns the VP paid and the
-- multiplier.
function ProfileService.awardEarned(plr, vp, gold)
	local mult = ProfileService.vpMult(plr)
	local paid = Economy.earnedVP(vp, mult)
	ProfileService.award(plr, paid, gold)
	return paid, mult
end

-- A Halloween Match run is over after `stage` (won: that stage was won): its Candy (the first
-- clear of the difficulty today pays in full: Halloween.payout). Returns the Candy and whether it
-- was today's first clear.
function ProfileService.eventPayout(plr, diff, stage, won)
	local profile = profiles[plr]
	if not profile then
		return 0, false
	end
	local ev = profile.halloween
	local cleared = won and stage >= Config.Halloween.Stages
	local first = Halloween.firstClear(ev, diff, Halloween.day(os.time()), cleared)
	local candy = Halloween.payout(diff, stage, won, first)
	ev.candy = ev.candy + candy
	dirty[plr] = true
	push(plr)
	return candy, first and cleared
end

-- A developer (recruits and tournament entries are free for them).
function ProfileService.isDev(plr)
	local profile = profiles[plr]
	return profile ~= nil and profile.dev == true
end

-- Take VP (a tournament's entry). Returns true, or false and why. Developers play free, as with
-- recruits.
function ProfileService.spendVP(plr, vp)
	local profile = profiles[plr]
	if not profile then
		return false, "Your profile is still loading."
	end
	vp = math.max(0, math.floor(vp or 0))
	if profile.dev then
		return true
	end
	if profile.vp < vp then
		return false, "Not enough VP. Get more in the shop or by playing."
	end
	profile.vp = profile.vp - vp
	dirty[plr] = true
	push(plr)
	return true
end

-- A finished match: a win extends the win streak, a loss (or a forfeit) ends it, and the
-- career counters add this match's wins, spike kills, aces and blocks (`st`, the match stats);
-- `beatDev`: a win over a team with a developer on it (the Dev Defeater card). Returns the streak
-- after this match.
function ProfileService.recordResult(plr, won, st, beatDev)
	local profile = profiles[plr]
	if not profile then
		return nil
	end
	profile.winStreak = Rewards.nextStreak(profile.winStreak or 0, won)
	profile.bestStreak = math.max(profile.bestStreak or 0, profile.winStreak)
	local r = profile.record
	r.matches = r.matches + 1
	r.wins = r.wins + (won and 1 or 0)
	if won and beatDev then
		r.devWins = (r.devWins or 0) + 1
	end
	if st then
		r.kills = r.kills + (st.kills or 0)
		r.aces = r.aces + (st.aces or 0)
		r.blocks = r.blocks + (st.blocks or 0)
	end
	dirty[plr] = true
	reg.LeaderboardService.track(plr, profile)
	ProfileService.checkCards(plr)
	if reg.ClanService then
		reg.ClanService.onRecord(plr) -- (their stats since joining their clan)
	end
	return profile.winStreak
end

-- The tutorial: tick steps the player really did (HitService, MatchService); the last one pays
-- the reward once.
function ProfileService.tutorialStep(plr, ids)
	local profile = profiles[plr]
	if not profile or profile.tutorial.done then
		return
	end
	local changed = false
	for _, id in ipairs(ids) do
		if Tutorial.isStep(id) and not profile.tutorial.steps[id] then
			profile.tutorial.steps[id] = true
			changed = true
		end
	end
	if not changed then
		return
	end
	dirty[plr] = true
	if Tutorial.complete(profile.tutorial.steps) then
		profile.tutorial.done = true
		local vp, gold, spins = Tutorial.reward()
		profile.vp = profile.vp + vp
		profile.gold = profile.gold + gold
		profile.freeSpins = (profile.freeSpins or 0) + spins
		push(plr, string.format("Tutorial complete! +%d VP, +%s Gold and %d free recruits", vp, tostring(gold), spins))
	else
		push(plr)
	end
end

local STEPS = {}
for _, n in ipairs(Config.Upgrades.Steps) do
	STEPS[n] = true
	STEPS[-n] = true
end

-- Upgrade (or take back) points of one stat of one owned character.
local function upgrade(plr, profile, id, stat, delta)
	local c = Roster.get(id)
	delta = math.floor(tonumber(delta) or 0)
	if not c or not owns(profile, "Char", id) or not Characters.isStat(stat) or not STEPS[delta] then
		return
	end
	if id == ProfileService.character(plr).Id and inMatch(plr) then
		push(plr, "Your character is locked until this match ends.")
		return
	end
	local lv = profile.levels[id] or {}
	local cur = Characters.statLevel(c, lv, stat)
	local target = math.clamp(cur + delta, Characters.baseStat(c, stat), c[stat])
	if target == cur then
		push(plr, delta > 0 and (stat .. " is at its ceiling.") or (stat .. " is at its base."))
		return
	end
	if target > cur then
		local cost = Characters.upgradeCost(c, cur, target)
		if not profile.dev and cost > profile.gold then
			-- buy as many points as the gold allows
			local afford = cur
			local spent = 0
			while afford < target and spent + Characters.pointCost(c, afford) <= profile.gold do
				spent = spent + Characters.pointCost(c, afford)
				afford = afford + 1
			end
			if afford == cur then
				push(plr, string.format("Not enough Gold: the next %s point costs %d.", stat, Characters.pointCost(c, cur)))
				return
			end
			target, cost = afford, spent
		end
		if not profile.dev then
			profile.gold = profile.gold - cost
		end
	elseif not profile.dev then
		profile.gold = profile.gold + Characters.upgradeCost(c, target, cur)
	end
	local clean = {}
	for _, k in ipairs(Config.Stats.Order) do
		clean[k] = Characters.statLevel(c, lv, k)
	end
	clean[stat] = target
	profile.levels[id] = clean
	dirty[plr] = true
	if id == ProfileService.character(plr).Id then
		ProfileService.applyActive(plr)
	end
	push(plr)
end

------------------------------------------------------------------------------------------
-- spins
------------------------------------------------------------------------------------------

-- Spin `count` times on `banner`. Duplicates, and pulls of a rarity set to auto-sell, turn
-- into VP. `lucky`: spend lucky spins (Config.Lucky's odds) instead of VP. Returns the reveal (or
-- nil and a reason).
local function spinOnce(plr, profile, banner, count, lucky)
	local cost = Spins.cost(count)
	if not Spins.isBanner(banner) or not cost then
		return nil
	end
	local free = false
	if lucky then
		if not profile.dev then
			if (profile.lucky or 0) < count then
				return nil, count == 1 and "You have no lucky spins: get some here, or from codes and daily rewards." or string.format("That takes %d lucky spins.", count)
			end
			profile.lucky = profile.lucky - count
		end
	elseif not profile.dev then
		if count == 1 and (profile.freeSpins or 0) > 0 then
			profile.freeSpins = profile.freeSpins - 1 -- free recruits go first
			free = true
		elseif profile.vp < cost then
			return nil, "Not enough VP. Get more in the shop or by playing."
		else
			profile.vp = profile.vp - cost
		end
	end
	dirty[plr] = true
	local rng = Random.new()
	local items, refund = {}, 0
	local frags = nil -- fragments from duplicate characters this spin ({ S = 1, ... })
	-- Luck: the admin panel's event (its own strength, 2x to 16x) and your own strongest boost each
	-- multiply the luck of recruits on the Characters banner, usual and lucky (Spins.luckyAt), and
	-- they stack
	local mult = 1
	if reg.AdminService then
		mult = mult * reg.AdminService.multiplier("Luck")
	end
	mult = mult * Economy.luckBoost(profile, os.time())
	mult = mult * Economy.passMult(passesOf(plr, profile), "Luck") -- the Lucky game pass
	mult = mult * (reg.ClanService and reg.ClanService.bonus(plr, "Luck") or 1) -- their clan's Extra luck
	local luckWeights = nil
	if banner == "Char" then
		luckWeights = lucky and Spins.luckyAt(mult) or Spins.luckWeights(mult)
	end
	for i = 1, count do
		local k, how = nil, nil
		if banner == "Char" then
			k, how = Spins.pityRoll(profile.pity, rng, lucky, profile.favor, luckWeights) -- counts toward pity, and pays it
		else
			k = Spins.rollItem(banner, rng, lucky and Spins.LuckyWeights or nil)
		end
		local item = Spins.item(banner, k)
		local dup = owns(profile, banner, k)
		local sold = not dup and Spins.autoSells(profile.autoSell, banner, item.Rarity)
		local frag = nil
		if dup and banner == "Char" then
			-- Breakthroughs: a duplicate character is a fragment of its letter (S- and S: S)
			local c = Roster.get(k)
			frag = c and Breakthrough.group(c.Tier) or nil
		end
		if frag then
			profile.fragments[frag] = (profile.fragments[frag] or 0) + 1
			frags = frags or {}
			frags[frag] = (frags[frag] or 0) + 1
		elseif dup or sold then
			refund = refund + Spins.sellValue(item.Rarity)
		else
			profile.owned[banner][k] = true
		end
		items[i] = { key = k, dup = dup or nil, sold = sold or nil, pity = how, frag = frag }
	end
	if not profile.dev then
		profile.vp = profile.vp + refund
	end
	return { banner = banner, count = count, items = items, refund = refund, free = free or nil, lucky = lucky or nil, frags = frags }
end

local function spin(plr, profile, banner, count, lucky)
	if profile.autoRolling then
		push(plr, "Stop the auto-roll first.")
		return
	end
	local reveal, why = spinOnce(plr, profile, banner, tonumber(count), lucky)
	if not reveal then
		if why then
			push(plr, why)
		end
		return
	end
	local notice = nil
	if reveal.refund > 0 and not profile.dev then
		notice = string.format("+%d VP from duplicates and auto-sell.", reveal.refund)
	end
	if reveal.frags then
		local parts = {}
		for _, g in ipairs(Config.Breakthrough.Groups) do
			if reveal.frags[g] then
				table.insert(parts, string.format("%d %s", reveal.frags[g], g))
			end
		end
		notice = (notice and notice .. " " or "") .. "+" .. table.concat(parts, ", +") .. " Fragment" .. "s from duplicates."
	end
	push(plr, notice, reveal)
	ProfileService.checkCards(plr)
end

-- Keep spinning x1 until a pull of AutoRollTarget rarity or better, the VP run out, the cap is
-- reached or the player stops it.
local function autoRoll(plr, profile, banner)
	if profile.autoRolling or not Spins.isBanner(banner) then
		return
	end
	local run = { banner = banner }
	profile.autoRolling = run
	push(plr)
	task.spawn(function()
		local target = Spins.rarityRank(SP.AutoRollTarget)
		local rolls, notice = 0, nil
		while profile.autoRolling == run and plr.Parent do
			if rolls >= SP.AutoRollMax then
				notice = string.format("Auto-roll stopped after %d spins.", rolls)
				break
			end
			local reveal, why = spinOnce(plr, profile, banner, 1)
			if not reveal then
				notice = why or "Auto-roll stopped."
				break
			end
			rolls = rolls + 1
			reveal.auto = rolls
			local item = Spins.item(banner, reveal.items[1].key)
			if Spins.rarityRank(item.Rarity) >= target then
				profile.autoRolling = nil
				push(plr, string.format("%s after %d spins!", item.Name, rolls), reveal)
				return
			end
			push(plr, nil, reveal)
			task.wait(SP.AutoRollDelay)
		end
		if profile.autoRolling == run then
			profile.autoRolling = nil
		end
		if plr.Parent then
			push(plr, notice)
		end
	end)
end

------------------------------------------------------------------------------------------
-- the Halloween event's banner, scout points, Candy shop and skins (Config.Halloween)
------------------------------------------------------------------------------------------

local function eventOn()
	return Halloween.active(os.time())
end

-- One banner item to the profile: a skin is one more copy (Candy once every character it fits has
-- one: the Reaper is Jaeil's alone) and its character with it, when missing (Halloween.skinChars);
-- a cosmetic is yours, or Candy when you have it already. Returns dup, candy, and the characters a
-- skin brought (ids).
local function grantEventItem(profile, item)
	if item.kind == "Skin" and not Halloween.skinDuplicate(profile.skins, item.key) then
		Halloween.addCopy(profile.skins, item.key)
		return false, 0, Halloween.skinChars(profile.skins, profile.owned.Char)
	end
	if item.kind == "Card" and not profile.cards[item.key] then
		profile.cards[item.key] = true -- (a player card for the Locker's Cards tab)
		return false, 0
	end
	if item.kind == "Room" and not profile.rooms.owned[item.key] then
		profile.rooms.owned[item.key] = true
		return false, 0
	end
	if item.kind == "Skin" or item.kind == "Room" or item.kind == "Card" or owns(profile, item.kind, item.key) then
		local candy = Halloween.dupCandy(item.rarity)
		profile.halloween.candy = profile.halloween.candy + candy
		return true, candy
	end
	profile.owned[item.kind][item.key] = true
	return false, 0
end

-- Halloween recruits: `count` (1 or 10) for VP or Candy; each one is a scout point too. The
-- reveal goes out as `hwReveal` (its own sequence on the client).
local function eventSpin(plr, profile, count, currency)
	if not eventOn() then
		push(plr, "The Halloween event has ended.")
		return
	end
	count = tonumber(count)
	local cost = Halloween.cost(currency, count)
	if not cost then
		return
	end
	if not profile.dev then
		if currency == "VP" then
			if profile.vp < cost then
				push(plr, "Not enough VP. Get more in the shop or by playing.")
				return
			end
			profile.vp = profile.vp - cost
		else
			if profile.halloween.candy < cost then
				push(plr, "Not enough Candy: clear Halloween Matches for more.")
				return
			end
			profile.halloween.candy = profile.halloween.candy - cost
		end
	end
	local rng = Random.new()
	local items, refund, joined = {}, 0, {}
	for i = 1, count do
		local item = Halloween.roll(rng)
		local dup, candy, chars = grantEventItem(profile, item)
		refund = refund + candy
		for _, id in ipairs(chars or {}) do
			local c = Roster.get(id)
			table.insert(joined, c and c.Name or id)
		end
		items[i] = { kind = item.kind, key = item.key, rarity = item.rarity, dup = dup or nil, candy = candy > 0 and candy or nil }
	end
	profile.halloween.scout = profile.halloween.scout + count * Config.Halloween.Banner.ScoutPerPull
	dirty[plr] = true
	local snap = ProfileService.snapshot(plr)
	local lines = {}
	if #joined > 0 then
		table.insert(lines, table.concat(joined, " and ") .. " joined your roster with the skin!")
	end
	if refund > 0 then
		table.insert(lines, string.format("+%d Candy from duplicates.", refund))
	end
	snap.notice = #lines > 0 and table.concat(lines, " ") or nil
	snap.hwReveal = { count = count, items = items, candy = refund, currency = currency }
	Net.get("Profile"):FireClient(plr, snap)
end

-- Spend scout points on one banner item outright.
local function eventScout(plr, profile, kind, key)
	if not eventOn() then
		push(plr, "The Halloween event has ended.")
		return
	end
	local item = Halloween.bannerItem(kind, key)
	if not item then
		return
	end
	local have = (item.kind == "Skin" and Halloween.skinDuplicate(profile.skins, item.key)) or (item.kind == "Room" and profile.rooms.owned[item.key] == true) or (item.kind == "Card" and profile.cards[item.key] == true) or (item.kind ~= "Skin" and item.kind ~= "Room" and item.kind ~= "Card" and owns(profile, item.kind, item.key))
	if have then
		push(plr, "You have " .. item.name .. " already.")
		return
	end
	if profile.halloween.scout < item.scout then
		push(plr, string.format("%s takes %d scout points.", item.name, item.scout))
		return
	end
	profile.halloween.scout = profile.halloween.scout - item.scout
	local _, _, chars = grantEventItem(profile, item)
	dirty[plr] = true
	local names = {}
	for _, id in ipairs(chars or {}) do
		local c = Roster.get(id)
		table.insert(names, c and c.Name or id)
	end
	push(plr, item.name .. " is yours!" .. (#names > 0 and (" " .. table.concat(names, " and ") .. " joined your roster with it.") or ""))
	if item.kind == "Skin" then
		applyCosmetics(plr, profile)
	end
end

-- One row of the Candy shop.
local function eventShop(plr, profile, key)
	if not eventOn() then
		push(plr, "The Halloween event has ended.")
		return
	end
	local row = nil
	for _, r in ipairs(Config.Halloween.Shop) do
		if r.Key == key then
			row = r
		end
	end
	if not row then
		return
	end
	local ev = profile.halloween
	if row.Limit and (ev.bought[row.Key] or 0) >= row.Limit then
		push(plr, "Sold out: that's all of those for this event.")
		return
	end
	if row.Item and owns(profile, row.Item.Kind, row.Item.Key) then
		push(plr, "You have that already.")
		return
	end
	if ev.candy < row.Price then
		push(plr, string.format("That takes %d Candy.", row.Price))
		return
	end
	ev.candy = ev.candy - row.Price
	ev.bought[row.Key] = (ev.bought[row.Key] or 0) + 1
	if row.Grant then
		Economy.apply(profile, Economy.cleanGrant(row.Grant), os.time())
	end
	if row.Item then
		profile.owned[row.Item.Kind][row.Item.Key] = true
	end
	dirty[plr] = true
	push(plr, row.Name .. " bought.")
end

-- A skin onto one of your characters for good ("apply"), or switched "on" / "off" there (swapped
-- at will from the character's page, The Spike's way: "on" applies a free copy first).
local function skinRequest(plr, profile, op, charId, key)
	key = Halloween.isSkin(key) and key or Config.Halloween.SkinOrder[1]
	local c = type(charId) == "string" and Roster.get(charId)
	if not c or not owns(profile, "Char", c.Id) then
		return
	end
	local row = profile.skins[key]
	if op == "on" and not (row and row.on[c.Id] ~= nil) then
		op = "apply"
	end
	local ok, why
	if op == "apply" then
		if profile.dev and Halloween.freeCopies(profile.skins, key) < 1 then
			Halloween.addCopy(profile.skins, key) -- (developers own everything: a copy when they apply one)
		end
		ok, why = Halloween.applySkin(profile.skins, key, c.Id)
	elseif op == "on" or op == "off" then
		ok, why = Halloween.toggleSkin(profile.skins, key, c.Id, op == "on")
	else
		return
	end
	local name = Config.Halloween.Skins[key].Name
	if not ok then
		local text = { none = "No " .. name .. " copy: get it on the Halloween banner.", applied = name .. " is on " .. c.Name .. " already.", notApplied = "Apply a " .. name .. " copy to " .. c.Name .. " first.", wrongChar = name .. " is " .. Halloween.skinCharNames(key) .. "'s skin." }
		push(plr, text[why] or "Can't do that.")
		return
	end
	dirty[plr] = true
	ProfileService.applyActive(plr)
	if reg.TeamService and reg.TeamService.inMatch then
		reg.TeamService.refreshSkins(plr) -- (their stand-in and their AI teammates too)
	end
	push(plr, string.format("%s %s for %s.", name, (op == "apply" or op == "on") and "on" or "off", c.Name))
end

-- The Rest in Peace gravestone (Config.Grave): the epitaph through Roblox's text filter (empty: your
-- name) and a picture (a Roblox image or decal's id, or a link to it; empty: none).
local graveAt = {}
local function graveRequest(plr, profile, text, image)
	local now = os.clock()
	if graveAt[plr] and now - graveAt[plr] < 2 then
		push(plr, "One moment, then save again.")
		return
	end
	graveAt[plr] = now
	local clean = Halloween.graveText(text)
	local img = Halloween.graveImage(image)
	if type(image) == "string" and string.match(image, "%S") and not img then
		push(plr, "The picture needs a Roblox image or decal: its id, or a link to it.")
		return
	end
	task.spawn(function()
		local filtered = ""
		if clean ~= "" then
			local ok, res = pcall(function()
				return TextService:FilterStringAsync(clean, plr.UserId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
			end)
			if not ok or type(res) ~= "string" then
				push(plr, "Roblox's text filter couldn't check it. Try again in a moment.")
				return
			end
			filtered = res
		end
		if profiles[plr] ~= profile then
			return
		end
		profile.grave = { text = filtered, image = img or 0 }
		dirty[plr] = true
		applyCosmetics(plr, profile)
		push(plr, filtered ~= clean and "Saved, with some words filtered." or "Your gravestone is saved.")
	end)
end

-- Home's room (Config.Rooms): put on one you own (the Decorate window).
local function roomRequest(plr, profile, key)
	local ok, why = Rooms.equip(profile.rooms, key, profile.dev)
	if not ok then
		push(plr, why == "locked" and "That room isn't yours yet: it's on the Halloween banner." or "No such room.")
		return
	end
	dirty[plr] = true
	push(plr, Rooms.get(key).Name .. " is your room now.")
end

-- A pack's grant added to a profile (VP, Gold, lucky spins, a boost's time). Returns what it was
-- before, for `unapplyPack`.
local function applyPack(profile, g)
	local before = { vp = profile.vp, gold = profile.gold, lucky = profile.lucky, boostVP = profile.boosts.VP, boosts = table.clone(profile.boosts) }
	Economy.apply(profile, g, os.time())
	return before
end

-- After a pack bought for yourself: a pass gift product bought without a recipient gives you the
-- pass, its tag and card at once.
local function refreshPassesOf(profile)
	for plr, p in pairs(profiles) do
		if p == profile then
			applyPasses(plr, profile)
			applyPerks(plr, profile)
		end
	end
end

local function unapplyPack(profile, before)
	profile.vp, profile.gold, profile.lucky, profile.boosts.VP = before.vp, before.gold, before.lucky, before.boostVP
	for _, m in ipairs(Config.Boosts.LuckTiers) do
		local key = Economy.luckKey(m)
		profile.boosts[key] = before.boosts[key] -- (every luck tier's clock as it was)
	end
end

-- What a player spent in Robux, for the leaderboards (gift: it was a gift).
local function addSpent(plr, profile, robux, gift, sign)
	-- Studio's purchases are Roblox's free test purchases: they don't go on the Robux boards
	if RunService:IsStudio() then
		return
	end
	robux = math.max(0, math.floor(tonumber(robux) or 0)) * (sign or 1)
	profile.spent.robux = math.max(0, profile.spent.robux + robux)
	if gift then
		profile.spent.gifts = math.max(0, profile.spent.gifts + robux)
	end
	dirty[plr] = true
end

local function onRequest(plr, kind, a, b, c)
	local profile = ProfileService.get(plr)
	if kind == "get" then
		push(plr)
		return
	end
	if kind == "tz" then
		-- the client's UTC offset (seconds), for the playtime day (Config.PlayRewards); the real range
		-- of time zones is UTC-12 to UTC+14
		local off = tonumber(a)
		if off and off == off and off >= -12 * 3600 and off <= 14 * 3600 then
			tzOffset[plr] = math.floor(off / 60) * 60
		end
		return
	end
	-- a little spacing between requests (buttons can be mashed)
	local now = os.clock()
	if kind ~= "stop" and lastRequest[plr] and now - lastRequest[plr] < 0.05 then
		return
	end
	lastRequest[plr] = now

	if kind == "upgrade" then
		upgrade(plr, profile, a, b, c)
	elseif kind == "spin" then
		spin(plr, profile, a, b, c == "lucky")
	elseif kind == "profileOf" then
		-- a player's public profile, by user id (yours, or anyone's on a board)
		local userId = tonumber(a)
		if not userId or userId ~= userId or userId < 1 or userId > 1e15 then
			return
		end
		if lastLook[plr] and now - lastLook[plr] < PROFILE_GAP then
			return
		end
		lastLook[plr] = now
		userId = math.floor(userId)
		task.spawn(function()
			local summary = ProfileService.publicProfile(userId)
			if plr.Parent then
				Net.get("PlayerProfile"):FireClient(plr, summary or { userId = userId, missing = true })
			end
		end)
	elseif kind == "entrance" then
		-- which leaderboard place shows over your head in the matchup intro (nil: your best one)
		profile.equip.Entrance = Leaderboards.isBoard(a) and a or nil
		dirty[plr] = true
		push(plr)
		if reg.LeaderboardService and reg.LeaderboardService.updateEntrance then
			task.spawn(reg.LeaderboardService.updateEntrance, plr)
		end
	elseif kind == "breakthrough" then
		-- spend a fragment of the character's letter on its next breakthrough
		local c = type(a) == "string" and Roster.get(a)
		if not c or not owns(profile, "Char", a) then
			return
		end
		if a == ProfileService.character(plr).Id and inMatch(plr) then
			push(plr, "Your character is locked until this match ends.")
			return
		end
		local level = profile.breaks[a] or 0
		local cost = Breakthrough.cost(level)
		if not cost then
			push(plr, c.Name .. " is at +" .. Config.Breakthrough.Max .. " already.")
			return
		end
		local g = Breakthrough.group(c.Tier)
		if not profile.dev then
			if (profile.fragments[g] or 0) < cost then
				push(plr, string.format("That takes %d %s Fragment%s: duplicate %s-tier recruits give them.", cost, g, cost == 1 and "" or "s", g))
				return
			end
			profile.fragments[g] = profile.fragments[g] - cost
			if profile.fragments[g] <= 0 then
				profile.fragments[g] = nil
			end
		end
		profile.breaks[a] = level + 1
		dirty[plr] = true
		if a == ProfileService.character(plr).Id then
			ProfileService.applyActive(plr)
		end
		-- the client plays the reveal (BreakReveal: "Breakthrough N Achieved!")
		local snap = ProfileService.snapshot(plr)
		snap.notice = string.format("%s broke through: +%d!", c.Name, level + 1)
		snap.breakReveal = { id = a, level = level + 1 }
		Net.get("Profile"):FireClient(plr, snap)
	elseif kind == "adminBreak" then
		-- a character's Breakthrough tab (the owner, 2026-10-29: "a seperate breakthrough max button
		-- and a remove breakthrough button"; then "just make a remove breakthrough button for all
		-- people", "remove one at a time though"): admins go straight to +Max, free; anyone takes
		-- theirs down one level, that level's fragments refunded (a developer paid none)
		local c = type(a) == "string" and Roster.get(a)
		local admin = profile.dev or (reg.AdminService and reg.AdminService.whitelisted(plr.UserId))
		if not c or not owns(profile, "Char", a) or not (b == "remove" or (b == "max" and admin)) then
			return
		end
		if a == ProfileService.character(plr).Id and inMatch(plr) then
			push(plr, "Your character is locked until this match ends.")
			return
		end
		local level = profile.breaks[a] or 0
		if b == "remove" then
			if level <= 0 then
				return
			end
			local back = Config.Breakthrough.Cost[level] or 0
			if back > 0 and not profile.dev then
				local g = Breakthrough.group(c.Tier)
				profile.fragments[g] = (profile.fragments[g] or 0) + back
			end
			profile.breaks[a] = level > 1 and level - 1 or nil
		else
			profile.breaks[a] = Config.Breakthrough.Max
		end
		dirty[plr] = true
		if a == ProfileService.character(plr).Id then
			ProfileService.applyActive(plr)
		end
		push(plr, string.format("%s is at +%d.", c.Name, profile.breaks[a] or 0))
	elseif kind == "sellFragment" then
		-- fragments you don't need, for a duplicate's VP (S+: a lucky spin too)
		local g = type(a) == "string" and Breakthrough.isGroup(a) and a or nil
		local have = g and (profile.fragments[g] or 0) or 0
		local n = math.clamp(math.floor(tonumber(b) or 1), 1, math.max(have, 1))
		if not g or have <= 0 then
			return
		end
		local one = Breakthrough.sellGrant(g)
		local grant = Economy.cleanGrant({ VP = one.VP * n, Lucky = one.Lucky * n })
		profile.fragments[g] = have - n
		if profile.fragments[g] <= 0 then
			profile.fragments[g] = nil
		end
		Economy.apply(profile, grant, os.time())
		dirty[plr] = true
		push(plr, string.format("Sold %d %s Fragment%s: %s.", n, g, n == 1 and "" or "s", Economy.describe(grant)))
	elseif kind == "sellChar" then
		-- a character you don't want (the owner: "sell extra characters you dont want so they dont
		-- leave room in your inventory"): its duplicate's VP, the Gold its upgrades cost and the
		-- fragments its breakthroughs took come back. Not a starter, nor the one you play
		local c = type(a) == "string" and Roster.get(a)
		if not c or profile.dev or not owns(profile, "Char", a) then
			if profile.dev then
				push(plr, "Developers own every character: there's nothing to sell.")
			end
			return
		end
		if Spins.starters("Char")[a] then
			push(plr, "Starters can't be sold.")
			return
		end
		if a == ProfileService.character(plr).Id then
			push(plr, "Pick another character first: you can't sell the one you play.")
			return
		end
		if profile.fav and profile.fav[a] then
			-- a favourite is locked (the owner: "character selling lock probably favorite button")
			push(plr, c.Name .. " is a favorite, so they're locked: unfavorite them to sell.")
			return
		end
		local gold = 0
		for _, stat in ipairs(Config.Stats.Order) do
			local base = Characters.baseStat(c, stat)
			local cur = Characters.statLevel(c, profile.levels[a], stat)
			if cur > base then
				gold = gold + Characters.upgradeCost(c, base, cur)
			end
		end
		local g = Breakthrough.group(c.Tier)
		local back = 0
		for i = 1, profile.breaks[a] or 0 do
			back = back + (Config.Breakthrough.Cost[i] or 0)
		end
		local item = Spins.item("Char", a)
		local grant = Economy.cleanGrant({ VP = Spins.sellValue(item and item.Rarity or "Common"), Gold = gold })
		Economy.apply(profile, grant, os.time())
		if back > 0 then
			profile.fragments[g] = (profile.fragments[g] or 0) + back
		end
		profile.owned.Char[a] = nil
		profile.levels[a] = nil
		profile.breaks[a] = nil
		profile.fav[a] = nil
		for _, picks in pairs(profile.teams) do
			for role, id in pairs(picks) do
				if id == a then
					picks[role] = nil
				end
			end
		end
		dirty[plr] = true
		push(plr, string.format("Sold %s: %s%s.", c.Name, Economy.describe(grant), back > 0 and string.format(" and %d %s Fragment%s back", back, g, back == 1 and "" or "s") or ""))
	elseif kind == "favor" then
		-- Boost or Lower a character's odds on the Characters banner (or reset it)
		local item = type(a) == "string" and Spins.item("Char", a)
		if not item or Spins.starters("Char")[a] then
			return
		end
		local mode = (b == "up" or b == "down") and b or nil
		local ups, downs = Spins.favorCounts(profile.favor)
		if mode == "up" and profile.favor[a] ~= "up" and ups >= Config.Spins.Favor.MaxBoost then
			push(plr, string.format("You can boost %d characters at a time: take one off first.", Config.Spins.Favor.MaxBoost))
			return
		end
		if mode == "down" and profile.favor[a] ~= "down" and downs >= Config.Spins.Favor.MaxLower then
			push(plr, string.format("You can lower %d characters at a time: take one off first.", Config.Spins.Favor.MaxLower))
			return
		end
		profile.favor[a] = mode
		dirty[plr] = true
		push(plr)
	elseif kind == "sTicket" then
		-- a selection ticket: any character of the ticket's tier you don't own yet
		local c = type(a) == "string" and Roster.get(a)
		if (profile.sTickets or 0) < 1 or not c or c.Tier ~= Config.Retired.TicketTier then
			return
		end
		if owns(profile, "Char", c.Id) then
			push(plr, "You already have " .. c.Name .. ". Pick someone new.")
			return
		end
		profile.sTickets = profile.sTickets - 1
		profile.owned.Char[c.Id] = true
		dirty[plr] = true
		save(plr, true)
		push(plr, c.Name .. " joined your roster!")
		ProfileService.checkCards(plr)
	elseif kind == "patchSeen" then
		-- What's New opened: the newest patch is seen (no more dot or pop-up for it)
		local latest = PatchNotes.latest()
		if latest and profile.patchSeen ~= latest.Id then
			profile.patchSeen = latest.Id
			dirty[plr] = true
			push(plr)
		end
	elseif kind == "discordCode" or kind == "discordVerify" then
		-- the Discord (Config.Discord): a code to send the bot, then Verify reads what it wrote
		if profile.discordDone or not verifyStore or discordBusy[plr] then
			push(plr)
			return
		end
		if kind == "discordVerify" and discordChecked[plr] and now - discordChecked[plr] < Config.Discord.CheckGap then
			push(plr, "One moment, then try Verify again.")
			return
		end
		discordBusy[plr] = true
		task.spawn(function()
			if kind == "discordCode" then
				if profile.discordCode == "" then
					local code = Economy.discordCode(Random.new())
					local ok = pcall(function()
						verifyStore:SetAsync("code_" .. code, { userId = plr.UserId, name = plr.Name, at = os.time() })
					end)
					if ok and profiles[plr] then
						profile.discordCode = code
						dirty[plr] = true
						save(plr, true)
					end
				end
				discordBusy[plr] = nil
				push(plr)
				return
			end
			discordChecked[plr] = os.clock()
			local code = profile.discordCode
			local ok, v = pcall(function()
				return verifyStore:GetAsync("done_" .. code)
			end)
			discordBusy[plr] = nil
			if not profiles[plr] or profile.discordDone then
				return
			end
			if not ok then
				push(plr, "Couldn't check right now. Try Verify again in a moment.")
			elseif type(v) == "table" and tonumber(v.userId) == plr.UserId then
				profile.discordDone = true
				local g = Economy.cleanGrant(Config.Discord.Reward)
				local added = Economy.apply(profile, g, os.time())
				dirty[plr] = true
				save(plr, true)
				ProfileService.checkCards(plr)
				push(plr, "Discord verified, thanks for joining! " .. Economy.describe(g, added))
			else
				push(plr, "Not verified yet. In the Discord, type /discordverify " .. code .. ", then click Verify here.")
			end
		end)
	elseif kind == "patchClaim" then
		-- read to the very bottom: the newest patch's reward, once
		local latest = PatchNotes.latest()
		profile.patchClaimed = type(profile.patchClaimed) == "table" and profile.patchClaimed or {}
		if latest and a == latest.Id and not profile.patchClaimed[latest.Id] then
			profile.patchClaimed[latest.Id] = true
			profile.patchSeen = latest.Id
			local g = Economy.cleanGrant(PatchNotes.reward(latest))
			local added = Economy.apply(profile, g, os.time())
			dirty[plr] = true
			save(plr, true)
			push(plr, "Thanks for reading the patch notes! " .. Economy.describe(g, added))
		end
	elseif kind == "skipTutorial" then
		-- (the owner, 2026-10-16: "add a skip tutorial option"): done without its reward; it can
		-- still be played from How to play
		if not profile.tutorial.done then
			profile.tutorial.done = true
			dirty[plr] = true
			push(plr, "Tutorial skipped. Play it any time from How to play.")
		end
	elseif kind == "pityPick" then
		-- the S+ the lucky pity gives you when it's owed
		if Spins.isPityPick(a) then
			profile.pity.pick = a
			dirty[plr] = true
			push(plr, Spins.item("Char", a).Name .. " is your lucky pity pick.")
		end
	elseif kind == "code" or kind == "daily" or kind == "gift" or kind == "group" then
		-- each asks Roblox (the group, a username), so they're spaced out and run on their own
		if lastClaim[plr] and now - lastClaim[plr] < 1.5 then
			push(plr, "One moment...")
			return
		end
		lastClaim[plr] = now
		task.spawn(function()
			if kind == "code" then
				if type(a) == "string" then
					redeemCode(plr, profile, a)
				end
			elseif kind == "daily" then
				claimDaily(plr, profile)
			elseif kind == "group" then
				-- after Roblox's join prompt: ask again, so the menus show it. Roblox keeps a player's
				-- groups from when they joined the server, so a fresh join could read "not a member"
				-- until they rejoined (the owner: "codes work, you just have to rejoin"): the prompt's
				-- own answer (a = it said Joined or AlreadyMember) counts for this session
				if not inGroup(plr, true) and a == true then
					groupMember[plr] = true
				end
				push(plr)
			else
				giftStart(plr, a, b, c)
			end
		end)
	elseif kind == "liked" then
		-- the player says they liked the game (the owner: "add a seperate box for liking the game")
		if not profile.liked then
			profile.liked = true
			dirty[plr] = true
		end
		push(plr)
	elseif kind == "favorited" then
		-- the client asked Roblox whether they've favorited the game (after its favorite prompt,
		-- and whenever Codes or Daily opens)
		if profile.favorited ~= (a == true) then
			profile.favorited = a == true
			dirty[plr] = true
		end
		push(plr)
	elseif kind == "autoroll" then
		autoRoll(plr, profile, a)
	elseif kind == "stop" then
		profile.autoRolling = nil
		push(plr)
	elseif kind == "autosell" then
		if Spins.isBanner(c) then
			for _, r in ipairs(SP.AutoSellable) do
				if r == a then
					profile.autoSell[c] = profile.autoSell[c] or {}
					profile.autoSell[c][r] = b == true or nil
					if next(profile.autoSell[c]) == nil then
						profile.autoSell[c] = nil
					end
					dirty[plr] = true
				end
			end
		end
		push(plr)
	elseif kind == "select" then
		local c = Roster.get(a)
		if not c or not owns(profile, "Char", c.Id) then
			return
		end
		local playing = inMatch(plr)
		local phase = reg.MatchService.phase
		if playing and phase ~= "Timeout" and phase ~= "Pick" then
			push(plr, "You can change character during a timeout, or after the match.")
			return
		end
		if playing and reg.MatchService.isBanned(c.Id) then
			push(plr, c.Name .. " is banned this match.")
			return
		end
		if playing then
			reg.MatchService.releaseBanSwap(plr) -- (off a banned character's stand-in: this pick is who they play)
		end
		profile.char = c.Id
		dirty[plr] = true
		local note = nil
		if playing then
			note = reg.TeamService.swapCharacter(plr) -- same spot, or the new character's role
		else
			ProfileService.applyActive(plr)
		end
		push(plr, note)
	elseif kind == "teamPick" then
		-- an AI teammate for one of your teams: (team "3v3" / "2v2", role, character id or "")
		local size = Court.teamSize(a)
		if not size or size < 2 or not table.find(Court.roles(size), b) then
			return
		end
		local picks = profile.teams[a] or {}
		if c == "" or c == nil then
			picks[b] = nil
		else
			local ch = Roster.get(c)
			if not ch or ch.Role ~= b or not owns(profile, "Char", ch.Id) then
				return
			end
			picks[b] = ch.Id
		end
		profile.teams[a] = picks
		dirty[plr] = true
		push(plr)
	elseif kind == "favorite" then
		local c = Roster.get(a)
		if c then
			profile.fav = profile.fav or {}
			profile.fav[c.Id] = b == true or nil
			dirty[plr] = true
		end
		push(plr)
	elseif kind == "settings" then
		-- replaced whole (the client sends them all a second after its last change)
		profile.settings = Settings.clean(a)
		dirty[plr] = true
	elseif kind == "equip" and a == "Card" then
		-- a player card you've unlocked (Config.Cards)
		if Cards.get(b) and cardUnlocked(profile, b) then
			profile.equip.Card = b
			dirty[plr] = true
			applyCard(plr, profile)
		end
		push(plr)
	elseif kind == "equip" then
		local item = Spins.isCosmetic(a) and Spins.item(a, b)
		if item and not item.Hidden and owns(profile, a, b) then -- (Hidden: a skin's own, like Souls)
			profile.equip[a] = b
			dirty[plr] = true
			applyCosmetics(plr, profile)
		end
		push(plr)
	elseif kind == "hwSpin" then
		eventSpin(plr, profile, a, b == "Candy" and "Candy" or "VP")
	elseif kind == "hwScout" then
		eventScout(plr, profile, a, b)
	elseif kind == "hwShop" then
		eventShop(plr, profile, a)
	elseif kind == "skin" then
		skinRequest(plr, profile, a, b, c)
	elseif kind == "room" then
		roomRequest(plr, profile, a)
	elseif kind == "grave" then
		graveRequest(plr, profile, a, b)
	elseif kind == "exchange" then
		-- V Points for Gold (Config.Exchange), in one of the Shop's amounts
		local cost = Economy.exchangeCost(a)
		if not cost then
			return
		end
		if (profile.gold or 0) < cost then
			push(plr, string.format("You need %s Gold for that.", Economy.commas(cost)))
			return
		end
		profile.gold = profile.gold - cost
		profile.vp = profile.vp + tonumber(a)
		dirty[plr] = true
		push(plr, string.format("+%s VP for %s Gold", Economy.commas(tonumber(a)), Economy.commas(cost)))
	elseif kind == "boostBuy" then
		-- 2x VP for Gold or VP (Config.Boosts.CurrencyPacks)
		local secs, price = Economy.boostPrice(a, b)
		if not secs then
			return
		end
		local have = b == "Gold" and (profile.gold or 0) or profile.vp
		if have < price then
			push(plr, string.format("You need %s %s for that.", Economy.commas(price), b))
			return
		end
		if b == "Gold" then
			profile.gold = profile.gold - price
		else
			profile.vp = profile.vp - price
		end
		profile.boosts = type(profile.boosts) == "table" and profile.boosts or {}
		profile.boosts.VP = Economy.extendBoost(profile.boosts.VP, secs, os.time())
		dirty[plr] = true
		push(plr, string.format("2x VP for %s", Economy.duration(secs)))
	elseif kind == "luckyTrade" then
		-- lucky spins for VP (Config.Lucky.VPCost each), in one of the Shop's amounts
		local n = tonumber(a)
		if not n or not table.find(Config.Lucky.Trade, n) then
			return
		end
		local cost = n * Config.Lucky.VPCost
		if profile.vp < cost then
			push(plr, string.format("You need %d VP for that.", cost))
			return
		end
		profile.vp = profile.vp - cost
		profile.lucky = (profile.lucky or 0) + n
		dirty[plr] = true
		push(plr, n == 1 and "+1 lucky spin" or string.format("+%d lucky spins", n))
	elseif kind == "perkBuy" then
		-- a perk for VP (the game pass is bought through Roblox's prompt)
		local def = Config.Perks[a]
		if not def or not table.find(Config.Perks.Order, a) or hasPerk(plr, profile, a) then
			return
		end
		if profile.vp < def.VP then
			push(plr, string.format("You need %d VP for that.", def.VP))
			return
		end
		profile.vp = profile.vp - def.VP
		profile.perks[a] = true
		dirty[plr] = true
		applyPerks(plr, profile)
		push(plr, def.Name .. " unlocked: enter your id")
	elseif kind == "perkSet" then
		-- your id for one slot of a perk you own (a slot key, e.g. "SoundSpike"; a perk's own key
		-- is its first slot; "" clears it); its asset type is checked first
		local perk, def, slot = perkOfSlot(a)
		if not perk or not hasPerk(plr, profile, perk) or type(b) ~= "string" then
			return
		end
		local id = string.match(b, "^%s*(%d+)%s*$")
		if b ~= "" and (not id or #id > 20) then
			push(plr, "An id is a number: the digits from the asset's page.")
			return
		end
		local last = lastPerkSet[plr] or {}
		lastPerkSet[plr] = last
		if last[a] and now - last[a] < Config.Perks.SetCooldown then
			push(plr, "Give it a moment before changing it again.")
			return
		end
		last[a] = now
		local what = def.Slots and string.format("%s (%s)", def.Name, slot.Name) or def.Name
		if b == "" then
			profile.perkIds[a] = nil
			profile.perkCrops[a] = nil
			dirty[plr] = true
			applyPerks(plr, profile)
			push(plr, what .. " cleared")
			return
		end
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(tonumber(id), Enum.InfoType.Asset)
			end)
			if not ok or type(info) ~= "table" then
				push(plr, "That id couldn't be found.")
				return
			end
			if not table.find(def.Types, info.AssetTypeId) then
				push(plr, table.find(def.Types, 3) and "That id isn't a sound." or "That id isn't an image or a decal.")
				return
			end
			if not profiles[plr] then
				return
			end
			if profile.perkIds[a] ~= id then
				profile.perkCrops[a] = nil -- a new sound starts uncropped
			end
			profile.perkIds[a] = id
			dirty[plr] = true
			applyPerks(plr, profile)
			push(plr, string.format("Saved for %s: %s", def.Slots and slot.Name or def.Name, tostring(info.Name or id)))
		end)
	elseif kind == "perkCrop" then
		-- the part of one slot's saved sound that plays: b = { s = start, l = length } in seconds
		-- (nil, or the whole front, clears it)
		local perk, def, slot = perkOfSlot(a)
		if not perk or not hasPerk(plr, profile, perk) or not table.find(def.Types, 3) or not profile.perkIds[a] then
			return
		end
		local last = lastPerkSet[plr] or {}
		lastPerkSet[plr] = last
		local cd = SoundCrop.attribute(a)
		if last[cd] and now - last[cd] < Config.Perks.CropCooldown then
			push(plr, "Give it a moment before changing it again.")
			return
		end
		last[cd] = now
		local c = SoundCrop.clean(a, b)
		profile.perkCrops[a] = c
		dirty[plr] = true
		applyPerks(plr, profile)
		push(plr, c and string.format("Cropped %s: %.2f s to %.2f s", slot.Name, c.s, c.s + c.l) or string.format("%s plays from the start", slot.Name))
	elseif kind == "buy" then
		-- Studio: a pack whose product doesn't exist yet is free, so the flow can be tried
		local entry = Economy.pack(b, a)
		if entry and entry.id == 0 and RunService:IsStudio() and not Economy.boughtOnce(entry, profile.bundles) then
			local g = Economy.packGrant(entry)
			applyPack(profile, g)
			if entry.pack.Once then
				profile.bundles[entry.pack.Name] = true
			end
			dirty[plr] = true
			push(plr, Economy.describe(g) .. " (free in Studio)")
		end
	end
end

-- Developer Product purchases (VP, Gold and lucky spin packs). Granted exactly once per
-- PurchaseId, and only reported as granted once the profile holding it is saved (Roblox retries
-- until then). One bought as a gift (giftStart) goes to its recipient instead, once whatever the
-- retries (the purchase id is the gift's id).
local function processReceipt(info)
	local plr = Players:GetPlayerByUserId(info.PlayerId)
	if not plr then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local entry = Economy.packByProduct(info.ProductId)
	if not entry then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = ProfileService.get(plr)
	local id = tostring(info.PurchaseId)
	for _, seen in ipairs(profile.receipts) do
		if seen == id then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	local g = Economy.packGrant(entry)
	local gift = pendingGift[plr]
	if gift and (gift.productId ~= info.ProductId or os.clock() - gift.t > Config.Gifts.PendingSeconds) then
		gift = nil
	end
	if gift then
		local sent = ProfileService.giveUser(gift.userId, g, plr.DisplayName, nil, "gift:" .. id)
		if not sent then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	local before = not gift and applyPack(profile, g) or nil
	if not gift and (#(g.Passes or {}) > 0 or #(g.Perks or {}) > 0) then
		refreshPassesOf(profile)
	end
	-- a bundle sold once is marked bought (a second receipt for it still grants: it was paid)
	local once = not gift and entry.pack.Once == true and not profile.bundles[entry.pack.Name]
	if once then
		profile.bundles[entry.pack.Name] = true
	end
	addSpent(plr, profile, info.CurrencySpent, gift ~= nil, 1)
	table.insert(profile.receipts, 1, id)
	while #profile.receipts > Config.Shop.ReceiptHistory do
		table.remove(profile.receipts)
	end
	dirty[plr] = true
	local stored = save(plr, true)
	if not stored and not RunService:IsStudio() then
		-- not persisted: undo, and let Roblox retry later (a gift already sent won't send twice)
		if before then
			unapplyPack(profile, before)
		end
		if once then
			profile.bundles[entry.pack.Name] = nil
		end
		addSpent(plr, profile, info.CurrencySpent, gift ~= nil, -1)
		table.remove(profile.receipts, 1)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if gift then
		pendingGift[plr] = nil
	end
	reg.LeaderboardService.track(plr, profile)
	if gift then
		push(plr, string.format("Gift sent: %s for %s. Thanks for the support!", entry.pack.Name, gift.name))
	else
		push(plr, Economy.describe(g) .. ". Thanks for the support!")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ProfileService.init(r)
	reg = r
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(P.DataStoreName)
	end)
	if ok then
		store = result
	end
	local okMail, mail = pcall(function()
		return DataStoreService:GetDataStore(Config.Admin.MailStore)
	end)
	if okMail then
		mailStore = mail
	end
	local okVerify, vs = pcall(function()
		return DataStoreService:GetDataStore(Config.Discord.Store)
	end)
	if okVerify then
		verifyStore = vs
	end

	local function setup(plr)
		task.spawn(function()
			ProfileService.get(plr)
			ProfileService.checkCards(plr, true)
			ProfileService.applyActive(plr)
			push(plr)
			-- in the group? (for daily rewards and codes); then any gifts waiting in their mail
			task.spawn(function()
				inGroup(plr, false)
				if plr.Parent then
					push(plr)
				end
			end)
			task.spawn(ProfileService.checkMail, plr)
			if reg.ClanService then
				task.spawn(reg.ClanService.onLoaded, plr) -- (their clan, its tag in chat)
			end
			if reg.MatchService and reg.MatchService.onRejoin then
				task.spawn(reg.MatchService.onRejoin, plr) -- (back in the ranked match they left: the penalty lifted)
			end
			-- the perks' game passes they own
			for _, key in ipairs(Config.Perks.Order) do
				local id = Config.Perks[key].PassId
				if id ~= 0 then
					local ok, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, id)
					end)
					if ok and owns and plr.Parent then
						passes[plr] = passes[plr] or {}
						passes[plr][key] = true
						applyPerks(plr, ProfileService.get(plr))
						push(plr)
					end
				end
			end
			-- and the other game passes (Config.Passes)
			for _, key in ipairs(Config.Passes.Order) do
				local id = Config.Passes[key].PassId
				if id ~= 0 then
					local ok, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, id)
					end)
					if ok and owns and plr.Parent then
						ownedPasses[plr] = ownedPasses[plr] or {}
						ownedPasses[plr][key] = true
						applyPasses(plr, ProfileService.get(plr))
						push(plr)
					end
				end
			end
			applyPasses(plr, ProfileService.get(plr))
		end)
		plr.CharacterAdded:Connect(function()
			task.defer(ProfileService.applyActive, plr)
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, plr in ipairs(Players:GetPlayers()) do
		setup(plr)
	end
	-- Playtime (the owner: "a playtime leaderboard"): the seconds a player has spent in the game, kept
	-- on the profile and added up every 15 seconds while they're here. The Playtime board is told every
	-- fifth minute (and when they leave) so it isn't written to the DataStore every minute; players
	-- in this server show their fresh time on the board regardless.
	local playClock = {} -- player -> os.time() of the last count
	local function tickPlayTime(plr, report)
		local profile = profiles[plr]
		if not profile then
			return
		end
		local now = os.time()
		local last = playClock[plr]
		playClock[plr] = now
		if last then
			local gain = math.clamp(now - last, 0, 600)
			profile.playTime = (profile.playTime or 0) + gain
			dirty[plr] = true
			-- today's playtime rewards (Config.PlayRewards): each tier pays once a day
			local pt = profile.playToday
			if type(pt) ~= "table" then
				pt = { day = 0, secs = 0, claimed = {} }
				profile.playToday = pt
			end
			-- the day turns at midnight where the player is (their own offset, sent by the client). It
			-- only ever moves forward, so changing the offset can't win a second reset; until the
			-- offset arrives (a few seconds after joining) nothing counts or turns over
			local off = tzOffset[plr]
			local today = off and math.floor((now + off) / 86400) or pt.day
			if today > pt.day then
				pt.day, pt.secs, pt.claimed = today, 0, {}
				push(plr) -- (the Playtime window starts a new day)
			end
			if off then
				pt.secs = pt.secs + gain
			end
			for _, t in ipairs(Config.PlayRewards.Tiers) do
				if not pt.claimed[t.Key] and pt.secs >= t.Minutes * 60 then
					pt.claimed[t.Key] = true
					local g = Economy.cleanGrant(t.Grant)
					Economy.apply(profile, g, now)
					push(plr, string.format("Playtime reward, %s today: %s!", t.Name, Economy.describe(g)))
				end
			end
		end
		if report and reg.LeaderboardService then
			reg.LeaderboardService.track(plr, profile)
		end
	end
	task.spawn(function()
		local n = 0
		while true do
			task.wait(15)
			n = n + 1
			for _, plr in ipairs(Players:GetPlayers()) do
				tickPlayTime(plr, n % 20 == 0)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(plr)
		local profile = profiles[plr]
		if profile then
			profile.autoRolling = nil
		end
		tickPlayTime(plr, true)
		playClock[plr] = nil
		if reg.MatchService and reg.MatchService.onLeaving then
			pcall(reg.MatchService.onLeaving, plr) -- (leaving a ranked match early: its loss, saved now)
		end
		if reg.ClanService then
			reg.ClanService.onLeft(plr)
		end
		save(plr)
		profiles[plr] = nil
		dirty[plr] = nil
		loading[plr] = nil
		lastRequest[plr] = nil
		tzOffset[plr] = nil
		passes[plr] = nil
		ownedPasses[plr] = nil
		lastPerkSet[plr] = nil
		pendingGift[plr] = nil
		groupMember[plr] = nil
		lastLook[plr] = nil
		lastClaim[plr] = nil
		mailBusy[plr] = nil
	end)
	game:BindToClose(function()
		for _, plr in ipairs(Players:GetPlayers()) do
			tickPlayTime(plr, true)
			save(plr)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(P.AutosaveInterval)
			for _, plr in ipairs(Players:GetPlayers()) do
				save(plr)
			end
		end
	end)

	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local plr = Players:GetPlayerByUserId(userId)
		local gift = plr and pendingGift[plr]
		if gift and gift.productId == productId and not purchased then
			pendingGift[plr] = nil
		end
	end)
	-- a game pass bought in game (its price counts toward Robux spent)
	local function countPass(plr, passId)
		task.spawn(function()
			if not passPrices[passId] then
				local okInfo, info = pcall(function()
					return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
				end)
				passPrices[passId] = okInfo and type(info) == "table" and tonumber(info.PriceInRobux) or 0
			end
			local profile = profiles[plr]
			if profile and passPrices[passId] > 0 then
				addSpent(plr, profile, passPrices[passId], false, 1)
				reg.LeaderboardService.track(plr, profile)
			end
		end)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
		if not purchased then
			return
		end
		for _, key in ipairs(Config.Perks.Order) do
			if Config.Perks[key].PassId ~= 0 and Config.Perks[key].PassId == passId then
				passes[plr] = passes[plr] or {}
				passes[plr][key] = true
				applyPerks(plr, ProfileService.get(plr))
				push(plr, Config.Perks[key].Name .. " unlocked: enter your id")
				countPass(plr, passId)
			end
		end
		local key, def = Economy.passById(passId)
		if key then
			ownedPasses[plr] = ownedPasses[plr] or {}
			ownedPasses[plr][key] = true
			applyPasses(plr, ProfileService.get(plr))
			applyCard(plr, ProfileService.get(plr))
			push(plr, def.Name .. " unlocked. Thanks for the support!")
			countPass(plr, passId)
		end
	end)
	Net.get("Profile").OnServerEvent:Connect(onRequest)
end

return ProfileService
