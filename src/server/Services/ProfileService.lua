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
--   ("autosell", rarity, on)         -> pulls of that rarity turn straight into VP
--   ("equip", kind, key)             -> equip an unlocked style, colour, trail or score effect
--   ("favorite", charId, on)         -> star or unstar a character (the Players screen's filter)
--   ("settings", table)              -> your settings (switches, touch layout); no reply
--   ("buy", packIndex, kind)        -> Studio only: grant a pack ("VP", "Gold", "Lucky") whose
--                                       product id isn't set yet
--   ("spin", banner, 1|10, "lucky")  -> spend lucky spins instead of VP (Config.Lucky's odds)
--   ("code", text)                   -> redeem a code, once each
--   ("daily")                        -> claim the daily reward
--   ("favorited", bool)              -> what Roblox told the client: they favorited the game (its prompt
--                                       said so), or no longer have (GetFavoriteAsync, with permission)
--   ("group")                        -> check group membership again (after the join prompt)
--   ("equip", "Card", key)           -> wear a player card you've unlocked (Config.Cards)
-- Player cards are unlocked for good by achievements (Cards.met: the career counters, the MVP
-- count, the best leaderboard place, the players recruited); checkCards runs after every match,
-- recruit and leaderboard read.
--   ("gift", kind, index, username)  -> buy a pack for someone else
--   ("pityPick", charId)             -> the S+ your lucky pity owes you (Config.Spins.Pity)
--   ("favor", charId, "up"|"down"|nil) -> boost, lower or reset a character's odds (Config.Spins.Favor)
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)
local Roster = require(Shared.Roster)
local Court = require(Shared.Court)
local Tutorial = require(Shared.Tutorial)
local Rewards = require(Shared.Rewards)
local Spins = require(Shared.Spins)
local Settings = require(Shared.Settings)
local Economy = require(Shared.Economy)
local Cards = require(Shared.Cards)
local Leaderboards = require(Shared.Leaderboards)
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
local mailStore = nil -- gifts waiting for their player (Config.Admin.MailStore)
local mailBusy = {}
local pendingGift = {} -- plr -> the gift their prompted purchase is: { productId, userId, name, t }
local groupMember = {} -- plr -> whether they're in the group (asked on join and on each claim)
local lastClaim = {} -- plr -> when they last redeemed, claimed or started a gift (each is looked up)
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
	local p = { v = VERSION, vp = P.StartingVP, gold = P.StartingGold, freeSpins = 0, winStreak = 0, bestStreak = 0, record = { matches = 0, wins = 0, kills = 0, aces = 0, blocks = 0, mvps = 0 }, levels = {}, owned = {}, equip = {}, fav = {}, autoSell = {}, receipts = {}, tutorial = { steps = {}, done = false }, teams = {}, settings = {}, perks = {}, perkIds = {}, lucky = 0, codes = {}, daily = { last = 0, streak = 0 }, spent = { robux = 0, gifts = 0 }, mailSeen = {}, liked = false, favorited = false, boosts = {}, cards = {}, pity = Spins.newPity(), favor = {} }
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
	-- what's equipped is kept if it exists; whether it's owned is checked once the player is known
	-- (keepOwned: a developer owns everything without it being in `owned`)
	for _, kind in ipairs(COS.Kinds) do
		local eq = type(data.equip) == "table" and data.equip[kind]
		if type(eq) == "string" and Spins.item(kind, eq) then
			out.equip[kind] = eq
		end
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
	if type(data.fav) == "table" then
		for id, v in pairs(data.fav) do
			if v == true and Roster.get(id) then
				out.fav[id] = true
			end
		end
	end
	out.freeSpins = math.clamp(math.floor(tonumber(data.freeSpins) or 0), 0, 1000)
	out.winStreak = math.max(0, math.floor(tonumber(data.winStreak) or 0))
	out.bestStreak = math.max(out.winStreak, math.floor(tonumber(data.bestStreak) or 0))
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
	if type(data.autoSell) == "table" then
		for _, r in ipairs(SP.AutoSellable) do
			out.autoSell[r] = data.autoSell[r] == true or nil
		end
	end
	out.settings = Settings.clean(data.settings)
	-- perks bought with VP, and the asset id chosen for each of their slots (digits only)
	for _, key in ipairs(Config.Perks.Order) do
		if type(data.perks) == "table" and data.perks[key] == true then
			out.perks[key] = true
		end
		for _, slot in ipairs(perkSlots(key)) do
			local id = type(data.perkIds) == "table" and data.perkIds[slot.Key]
			if type(id) == "string" and string.match(id, "^%d+$") and #id <= 20 then
				out.perkIds[slot.Key] = id
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
	return out
end

-- Everything is owned by a developer; otherwise what the profile holds.
local function owns(profile, kind, k)
	if profile.dev then
		return Spins.item(kind, k) ~= nil
	end
	return profile.owned[kind] ~= nil and profile.owned[kind][k] == true
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
	-- only a profile that loaded (or was confirmed new) may ever be written back
	profile.canSave = ok
	profile.dev = isDeveloper(plr)
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
		freeSpins = profile.freeSpins,
		winStreak = profile.winStreak,
		bestStreak = profile.bestStreak,
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
		receipts = profile.receipts,
		lucky = profile.lucky,
		codes = profile.codes,
		daily = profile.daily,
		spent = profile.spent,
		mailSeen = profile.mailSeen,
		liked = profile.liked,
		favorited = profile.favorited,
		boosts = profile.boosts,
		cards = profile.cards,
		bestRank = profile.bestRank,
		pity = profile.pity,
		favor = profile.favor,
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

-- The roster character this player plays.
function ProfileService.character(plr)
	local profile = ProfileService.get(plr)
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
end

-- Perks: owned when bought with VP, when the player owns the game pass, or for a developer.
local passes = {} -- plr -> { [perk] = true } for the game passes they own
local lastPerkSet = {}

local function hasPerk(plr, profile, key)
	return profile.dev == true or profile.perks[key] == true or (passes[plr] ~= nil and passes[plr][key] == true)
end

-- Each owned perk's ids as attributes on the Player and its avatar ("" for none), one per slot,
-- so every client plays that player's sounds (scoring, spikes, jumps...) and shows their image
-- when they score.
local function applyPerks(plr, profile)
	local char = plr.Character
	for _, key in ipairs(Config.Perks.Order) do
		local owned = hasPerk(plr, profile, key)
		for _, slot in ipairs(perkSlots(key)) do
			local value = owned and profile.perkIds[slot.Key] or ""
			plr:SetAttribute(slot.Key, value)
			if char then
				char:SetAttribute(slot.Key, value)
			end
		end
	end
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
	end
end

-- The tier and build this player plays: their character with its upgrades.
function ProfileService.characterBuild(plr)
	local c = ProfileService.character(plr)
	local tier, build = Characters.fromRoster(c, ProfileService.get(plr).levels[c.Id])
	return c, tier, build
end

-- Write the active character onto the Player (and its avatar) so clients can read it.
function ProfileService.applyActive(plr)
	local c, tier, build = ProfileService.characterBuild(plr)
	local ability = c.Ability or ""
	local char = plr.Character
	for _, inst in ipairs({ plr, char or plr }) do
		Characters.writeAttributes(inst, tier, build)
		inst:SetAttribute("Ability", ability)
		inst:SetAttribute("CharId", c.Id)
		inst:SetAttribute("CharName", c.Name)
		inst:SetAttribute("CharRole", c.Role)
	end
	if char then
		reg.CharacterService.applyStats(char, Characters.derive(tier, build))
	end
	applyCosmetics(plr, ProfileService.get(plr))
	applyPerks(plr, ProfileService.get(plr))
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
	local tier, build = Characters.fromRoster(c, profile.levels[c.Id])
	return c, tier, build
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
		record = table.clone(profile.record),
		tutorial = { steps = table.clone(profile.tutorial.steps), done = profile.tutorial.done },
		levels = levels,
		owned = owned,
		equip = table.clone(profile.equip),
		char = ProfileService.character(plr).Id,
		fav = table.clone(profile.fav or {}),
		teams = teamsCopy(profile),
		autoSell = table.clone(profile.autoSell),
		settings = profile.settings,
		perks = (function()
			local out = {}
			for _, key in ipairs(Config.Perks.Order) do
				local ids = {}
				for _, slot in ipairs(perkSlots(key)) do
					ids[slot.Key] = profile.perkIds[slot.Key]
				end
				out[key] = { owned = hasPerk(plr, profile, key), id = profile.perkIds[key], ids = ids }
			end
			return out
		end)(),
		autoRolling = profile.autoRolling and profile.autoRolling.banner or nil,
		dev = profile.dev or nil,
		admin = profile.dev or nil, -- the admin panel (developers)
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
		-- the Characters banner's pity: recruits counted toward each, whether the next lucky pity is
		-- your pick, and the pick
		pity = { normal = profile.pity.normal, top = profile.pity.top, lucky = profile.pity.lucky, owed = profile.pity.owed, pick = profile.pity.pick },
		favor = profile.favor, -- boosted ("up") and lowered ("down") characters
		favorited = profile.favorited == true or RunService:IsStudio(), -- codes and daily rewards need it
		boostVP = math.max(0, (profile.boosts.VP or 0) - os.time()), -- seconds left on their 2x VP
		group = groupId(),
		member = groupMember[plr], -- nil until it's known
		daily = (function()
			local now = os.time()
			local d = Economy.daily(profile.daily, now)
			return { ready = d.ready, day = d.day, streak = d.streak, lapsed = d.lapsed, opensIn = math.max(0, d.opensAt - now) }
		end)(),
		saving = profile.canSave and store ~= nil,
		studio = RunService:IsStudio(),
	}
end

local function push(plr, notice, reveal)
	local snap = ProfileService.snapshot(plr)
	snap.notice = notice
	snap.reveal = reveal
	Net.get("Profile"):FireClient(plr, snap)
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
				deliver(plr, profile, m.id, Economy.cleanGrant(m.g), type(m.from) == "string" and m.from or nil, type(m.note) == "string" and m.note or nil)
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
	local added = Economy.apply(profile, d.grant, os.time())
	dirty[plr] = true
	save(plr, true)
	push(plr, string.format("Day %d reward: %s!", d.day, Economy.describe(d.grant, added)))
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
	if not entry or type(username) ~= "string" then
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

-- A finished match: a win extends the win streak, a loss (or a forfeit) ends it, and the
-- career counters add this match's wins, spike kills, aces and blocks (`st`, the match stats).
-- Returns the streak after this match.
function ProfileService.recordResult(plr, won, st)
	local profile = profiles[plr]
	if not profile then
		return nil
	end
	profile.winStreak = Rewards.nextStreak(profile.winStreak or 0, won)
	profile.bestStreak = math.max(profile.bestStreak or 0, profile.winStreak)
	local r = profile.record
	r.matches = r.matches + 1
	r.wins = r.wins + (won and 1 or 0)
	if st then
		r.kills = r.kills + (st.kills or 0)
		r.aces = r.aces + (st.aces or 0)
		r.blocks = r.blocks + (st.blocks or 0)
	end
	dirty[plr] = true
	reg.LeaderboardService.track(plr, profile)
	ProfileService.checkCards(plr)
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
	for i = 1, count do
		local k, how = nil, nil
		if banner == "Char" then
			k, how = Spins.pityRoll(profile.pity, rng, lucky, profile.favor) -- counts toward pity, and pays it
		else
			k = Spins.rollItem(banner, rng, lucky and Spins.LuckyWeights or nil)
		end
		local item = Spins.item(banner, k)
		local dup = owns(profile, banner, k)
		local sold = not dup and profile.autoSell[item.Rarity] == true
		if dup or sold then
			refund = refund + Spins.sellValue(item.Rarity)
		else
			profile.owned[banner][k] = true
		end
		items[i] = { key = k, dup = dup or nil, sold = sold or nil, pity = how }
	end
	if not profile.dev then
		profile.vp = profile.vp + refund
	end
	return { banner = banner, count = count, items = items, refund = refund, free = free or nil, lucky = lucky or nil }
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

-- A pack's grant added to a profile (VP, Gold, lucky spins, a boost's time). Returns what it was
-- before, for `unapplyPack`.
local function applyPack(profile, g)
	local before = { vp = profile.vp, gold = profile.gold, lucky = profile.lucky, boostVP = profile.boosts.VP }
	Economy.apply(profile, g, os.time())
	return before
end

local function unapplyPack(profile, before)
	profile.vp, profile.gold, profile.lucky, profile.boosts.VP = before.vp, before.gold, before.lucky, before.boostVP
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
				-- after Roblox's join prompt: ask again, so the menus show it
				inGroup(plr, true)
				push(plr)
			else
				giftStart(plr, a, b, c)
			end
		end)
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
		for _, r in ipairs(SP.AutoSellable) do
			if r == a then
				profile.autoSell[r] = b == true or nil
				dirty[plr] = true
			end
		end
		push(plr)
	elseif kind == "select" then
		local c = Roster.get(a)
		if not c or not owns(profile, "Char", c.Id) then
			return
		end
		local playing = inMatch(plr)
		if playing and reg.MatchService.phase ~= "Timeout" then
			push(plr, "You can change character during a timeout, or after the match.")
			return
		end
		profile.char = c.Id
		dirty[plr] = true
		if playing then
			reg.TeamService.swapCharacter(plr) -- same spot and role, new character
		else
			ProfileService.applyActive(plr)
		end
		push(plr)
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
		if Spins.isCosmetic(a) and owns(profile, a, b) then
			profile.equip[a] = b
			dirty[plr] = true
			applyCosmetics(plr, profile)
		end
		push(plr)
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
			profile.perkIds[a] = id
			dirty[plr] = true
			applyPerks(plr, profile)
			push(plr, string.format("Saved for %s: %s", def.Slots and slot.Name or def.Name, tostring(info.Name or id)))
		end)
	elseif kind == "buy" then
		-- Studio: a pack whose product doesn't exist yet is free, so the flow can be tried
		local entry = Economy.pack(b, a)
		if entry and entry.id == 0 and RunService:IsStudio() then
			local g = Economy.packGrant(entry)
			applyPack(profile, g)
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
		end)
		plr.CharacterAdded:Connect(function()
			task.defer(ProfileService.applyActive, plr)
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, plr in ipairs(Players:GetPlayers()) do
		setup(plr)
	end
	Players.PlayerRemoving:Connect(function(plr)
		local profile = profiles[plr]
		if profile then
			profile.autoRolling = nil
		end
		save(plr)
		profiles[plr] = nil
		dirty[plr] = nil
		loading[plr] = nil
		lastRequest[plr] = nil
		passes[plr] = nil
		lastPerkSet[plr] = nil
		pendingGift[plr] = nil
		groupMember[plr] = nil
		lastClaim[plr] = nil
		mailBusy[plr] = nil
	end)
	game:BindToClose(function()
		for _, plr in ipairs(Players:GetPlayers()) do
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
	-- a perk's game pass bought in game (its price counts toward Robux spent)
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
		end
	end)
	Net.get("Profile").OnServerEvent:Connect(onRequest)
end

return ProfileService
