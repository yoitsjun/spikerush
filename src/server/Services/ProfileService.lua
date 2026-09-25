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
--   ("buy", packIndex)               -> Studio only: grant a pack whose product id isn't set yet
-- Your character locks while you're in a match, so prediction always matches the server.
-- VP packs are Developer Products granted in MarketplaceService.ProcessReceipt.
-- Developers (Config.Developers: the place owner, Studio sessions, listed ids) own everything
-- and spin for free.

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)
local Roster = require(Shared.Roster)
local Spins = require(Shared.Spins)
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
-- profile data
------------------------------------------------------------------------------------------

local function newProfile()
	local p = { v = VERSION, vp = P.StartingVP, gold = P.StartingGold, levels = {}, owned = {}, equip = {}, autoSell = {}, receipts = {} }
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
	for _, kind in ipairs(COS.Kinds) do
		local eq = type(data.equip) == "table" and data.equip[kind]
		if eq and out.owned[kind][eq] then
			out.equip[kind] = eq
		end
	end
	if type(data.char) == "string" and out.owned.Char[data.char] then
		out.char = data.char
	end
	if type(data.autoSell) == "table" then
		for _, r in ipairs(SP.AutoSellable) do
			out.autoSell[r] = data.autoSell[r] == true or nil
		end
	end
	if type(data.receipts) == "table" then
		for _, id in ipairs(data.receipts) do
			if type(id) == "string" and #out.receipts < Config.Shop.ReceiptHistory then
				table.insert(out.receipts, id)
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
		levels = profile.levels,
		owned = profile.owned,
		equip = profile.equip,
		char = profile.char,
		autoSell = profile.autoSell,
		receipts = profile.receipts,
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
		levels = levels,
		owned = owned,
		equip = table.clone(profile.equip),
		char = ProfileService.character(plr).Id,
		autoSell = table.clone(profile.autoSell),
		autoRolling = profile.autoRolling and profile.autoRolling.banner or nil,
		dev = profile.dev or nil,
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
-- into VP. Returns the reveal (or nil and a reason).
local function spinOnce(plr, profile, banner, count)
	local cost = Spins.cost(count)
	if not Spins.isBanner(banner) or not cost then
		return nil
	end
	if not profile.dev then
		if profile.vp < cost then
			return nil, "Not enough VP. Get more in the shop or by playing."
		end
		profile.vp = profile.vp - cost
	end
	dirty[plr] = true
	local rng = Random.new()
	local items, refund = {}, 0
	for i = 1, count do
		local k = Spins.rollItem(banner, rng)
		local item = Spins.item(banner, k)
		local dup = owns(profile, banner, k)
		local sold = not dup and profile.autoSell[item.Rarity] == true
		if dup or sold then
			refund = refund + Spins.sellValue(item.Rarity)
		else
			profile.owned[banner][k] = true
		end
		items[i] = { key = k, dup = dup or nil, sold = sold or nil }
	end
	if not profile.dev then
		profile.vp = profile.vp + refund
	end
	return { banner = banner, count = count, items = items, refund = refund }
end

local function spin(plr, profile, banner, count)
	if profile.autoRolling then
		push(plr, "Stop the auto-roll first.")
		return
	end
	local reveal, why = spinOnce(plr, profile, banner, tonumber(count))
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

local function grantPack(plr, pack)
	local profile = ProfileService.get(plr)
	profile.vp = profile.vp + pack.VP
	dirty[plr] = true
	push(plr, string.format("+%d VP", pack.VP))
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
		spin(plr, profile, a, b)
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
		if inMatch(plr) then
			push(plr, "Your character is locked until this match ends.")
			return
		end
		profile.char = c.Id
		dirty[plr] = true
		ProfileService.applyActive(plr)
		push(plr)
	elseif kind == "equip" then
		if Spins.isCosmetic(a) and owns(profile, a, b) then
			profile.equip[a] = b
			dirty[plr] = true
			applyCosmetics(plr, profile)
		end
		push(plr)
	elseif kind == "buy" then
		local pack = Config.Shop.Packs[tonumber(a) or 0]
		if pack and pack.Id == 0 and RunService:IsStudio() then
			grantPack(plr, pack)
		end
	end
end

-- Developer Product purchases. Granted exactly once per PurchaseId, and only reported as
-- granted once the profile holding it is saved (Roblox retries until then).
local function processReceipt(info)
	local plr = Players:GetPlayerByUserId(info.PlayerId)
	if not plr then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local pack = nil
	for _, p in ipairs(Config.Shop.Packs) do
		if p.Id ~= 0 and p.Id == info.ProductId then
			pack = p
		end
	end
	if not pack then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = ProfileService.get(plr)
	local id = tostring(info.PurchaseId)
	for _, seen in ipairs(profile.receipts) do
		if seen == id then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	profile.vp = profile.vp + pack.VP
	table.insert(profile.receipts, 1, id)
	while #profile.receipts > Config.Shop.ReceiptHistory do
		table.remove(profile.receipts)
	end
	dirty[plr] = true
	local stored = save(plr, true)
	if not stored and not RunService:IsStudio() then
		-- not persisted: undo, and let Roblox retry later
		profile.vp = profile.vp - pack.VP
		table.remove(profile.receipts, 1)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	push(plr, string.format("+%d VP. Thanks for the support!", pack.VP))
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

	local function setup(plr)
		task.spawn(function()
			ProfileService.get(plr)
			ProfileService.applyActive(plr)
			push(plr)
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
	Net.get("Profile").OnServerEvent:Connect(onRequest)
end

return ProfileService
