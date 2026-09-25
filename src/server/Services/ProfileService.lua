-- Player profiles: V Points (VP), one saved character per tier (rolled height, rolled stat
-- caps and four stats), unlocked cosmetics and what's equipped. Saved with DataStoreService;
-- falls back to session-only profiles when the DataStore isn't reachable (e.g. Studio without
-- "Enable Studio Access to API Services").
--
-- Client requests arrive on the "Profile" remote:
--   ("get")                          -> reply with a snapshot
--   ("alloc", tier, stat, delta)     -> move points between the free pool and a stat (+-1/5/10)
--   ("auto", tier)                   -> spread the free points
--   ("spin", banner, count, tier)    -> x1 / x10 spin (Config.Spins)
--   ("keep", index) / ("discard")    -> resolve a pending stat-cap or height spin
--   ("equip", kind, key)             -> equip an unlocked style, colour, trail or score effect
--   ("buy", packIndex)               -> Studio only: grant a pack whose product id isn't set yet
-- and on "SetCharacter" (tier, ability) to pick which character you play.
-- Your active character locks while you're in a match, so prediction always matches the server.
-- VP packs are Developer Products granted in MarketplaceService.ProcessReceipt.

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)
local Spins = require(Shared.Spins)
local Net = require(Shared.Net)

local ProfileService = {}
local reg

local P = Config.Progression
local SP = Config.Spins
local COS = Config.Cosmetics
local VERSION = 2
local profiles = {}
local dirty = {}
local loading = {}
local store = nil
local warned = false
local lastRequest = {}

local function key(plr)
	return "u_" .. tostring(plr.UserId)
end

local function newProfile()
	local p = { v = VERSION, vp = P.StartingVP, builds = {}, owned = {}, equip = {}, receipts = {} }
	for _, kind in ipairs(COS.Kinds) do
		p.owned[kind] = { [Spins.default(kind)] = true }
		p.equip[kind] = Spins.default(kind)
	end
	return p
end

local function sanitizePending(pending)
	if type(pending) ~= "table" or not Spins.isBanner(pending.banner) or not Characters.isTier(pending.tier) then
		return nil
	end
	if type(pending.results) ~= "table" or #pending.results == 0 then
		return nil
	end
	local out = { banner = pending.banner, tier = pending.tier, results = {} }
	for i = 1, math.min(#pending.results, SP.MaxPending) do
		local r = pending.results[i]
		if pending.banner == "Caps" and type(r) == "table" then
			local caps = Characters.statCaps(pending.tier, { Caps = r })
			table.insert(out.results, caps)
		elseif pending.banner == "Height" and tonumber(r) then
			table.insert(out.results, math.floor(math.clamp(tonumber(r), Config.Height.Min, Config.Height.Max)))
		end
	end
	return #out.results > 0 and out or nil
end

-- Old (v1) profiles had upgrade points: they become VP, and their characters keep the tier cap
-- as every stat cap (sanitize fills in missing caps that way).
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
	if type(data.builds) == "table" then
		for tier, b in pairs(data.builds) do
			if Characters.isTier(tier) then
				out.builds[tier] = Characters.sanitize(tier, b)
			end
		end
	end
	for _, kind in ipairs(COS.Kinds) do
		local owned = type(data.owned) == "table" and data.owned[kind]
		if type(owned) == "table" then
			for k, v in pairs(owned) do
				if v and Spins.item(kind, k) then
					out.owned[kind][k] = true
				end
			end
		end
		local eq = type(data.equip) == "table" and data.equip[kind]
		if eq and out.owned[kind][eq] then
			out.equip[kind] = eq
		end
	end
	out.pending = sanitizePending(data.pending)
	if type(data.receipts) == "table" then
		for _, id in ipairs(data.receipts) do
			if type(id) == "string" and #out.receipts < Config.Shop.ReceiptHistory then
				table.insert(out.receipts, id)
			end
		end
	end
	return out
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
		builds = profile.builds,
		owned = profile.owned,
		equip = profile.equip,
		pending = profile.pending,
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
		if plr.Parent then
			profiles[plr] = profile
		end
	end
	return profile
end

-- The saved character for `tier`, created (rolled height and caps) the first time it's used.
function ProfileService.build(plr, tier)
	local profile = ProfileService.get(plr)
	if not Characters.isTier(tier) then
		tier = Config.DefaultTier
	end
	local b = profile.builds[tier]
	if not b then
		b = Characters.newBuild(tier, Random.new())
		profile.builds[tier] = b
		dirty[plr] = true
	end
	return b
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

-- Write the active character onto the Player (and its avatar) so clients can read it.
function ProfileService.applyActive(plr)
	local tier = plr:GetAttribute("Tier")
	if not Characters.isTier(tier) then
		tier = Config.DefaultTier
	end
	local b = ProfileService.build(plr, tier)
	Characters.writeAttributes(plr, tier, b)
	local char = plr.Character
	if char then
		Characters.writeAttributes(char, tier, b)
		char:SetAttribute("Ability", plr:GetAttribute("Ability"))
		reg.CharacterService.applyStats(char, Characters.derive(tier, b))
	end
	applyCosmetics(plr, ProfileService.get(plr))
end

local function copyBuild(b)
	local out = table.clone(b)
	out.Caps = table.clone(b.Caps or {})
	return out
end

function ProfileService.snapshot(plr)
	local profile = ProfileService.get(plr)
	local builds = {}
	for _, tier in ipairs(Config.Tiers) do
		if profile.builds[tier] then
			builds[tier] = copyBuild(profile.builds[tier])
		end
	end
	local owned = {}
	for _, kind in ipairs(COS.Kinds) do
		owned[kind] = table.clone(profile.owned[kind])
	end
	return {
		vp = profile.vp,
		builds = builds,
		owned = owned,
		equip = table.clone(profile.equip),
		pending = profile.pending,
		tier = plr:GetAttribute("Tier"),
		ability = plr:GetAttribute("Ability"),
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

function ProfileService.award(plr, amount)
	local profile = profiles[plr]
	if not profile or amount <= 0 then
		return
	end
	profile.vp = profile.vp + math.floor(amount)
	dirty[plr] = true
	push(plr)
end

local function lockedFor(plr, tier)
	local TS = reg.TeamService
	return TS.inMatch and TS.entityForPlayer(plr) ~= nil and tier == plr:GetAttribute("Tier")
end

-- A character changed: store it and, if it's the one in use, re-apply it.
local function commit(plr, profile, tier, b)
	profile.builds[tier] = Characters.sanitize(tier, b)
	dirty[plr] = true
	if tier == plr:GetAttribute("Tier") then
		ProfileService.applyActive(plr)
	end
end

local ALLOC_STEPS = { [-10] = true, [-5] = true, [-1] = true, [1] = true, [5] = true, [10] = true }

local function spin(plr, profile, banner, count, tier)
	count = tonumber(count)
	local cost = count and Spins.cost(count)
	if not Spins.isBanner(banner) or not cost then
		return
	end
	local def = SP.Banners[banner]
	if def.PerCharacter and not Characters.isTier(tier) then
		return
	end
	if def.PerCharacter and profile.pending then
		push(plr, "Keep or discard your last " .. SP.Banners[profile.pending.banner].Name:lower() .. " spin first.")
		return
	end
	if profile.vp < cost then
		push(plr, "Not enough VP. Get more in the shop or by playing.")
		return
	end
	profile.vp = profile.vp - cost
	dirty[plr] = true
	local rng = Random.new()
	if def.PerCharacter then
		ProfileService.build(plr, tier) -- make sure the character exists
		local results = {}
		for i = 1, count do
			if banner == "Caps" then
				results[i] = Characters.rollCaps(tier, rng)
			else
				results[i] = Characters.rollHeight(rng)
			end
		end
		profile.pending = { banner = banner, tier = tier, results = results }
		push(plr, nil, { banner = banner, tier = tier, count = count })
		return
	end
	local items, refund = {}, 0
	for i = 1, count do
		local k = Spins.rollItem(banner, rng)
		local dup = profile.owned[banner][k] == true
		if dup then
			refund = refund + SP.DuplicateRefund
		end
		profile.owned[banner][k] = true
		items[i] = { key = k, dup = dup }
	end
	profile.vp = profile.vp + refund
	local notice = nil
	if refund > 0 then
		notice = string.format("Duplicates refunded %d VP.", refund)
	end
	push(plr, notice, { banner = banner, count = count, items = items })
end

local function keep(plr, profile, index)
	local pending = profile.pending
	if not pending then
		return
	end
	index = math.floor(tonumber(index) or 0)
	local result = pending.results[index]
	if not result then
		return
	end
	if lockedFor(plr, pending.tier) then
		push(plr, "Your character is locked until this match ends. Keep it after the match.")
		return
	end
	local b = copyBuild(ProfileService.build(plr, pending.tier))
	if pending.banner == "Caps" then
		b.Caps = table.clone(result)
		b = Characters.sanitize(pending.tier, b)
		Characters.fill(pending.tier, b) -- new room gets used right away; move it with the buttons
	else
		b.Height = result
	end
	profile.pending = nil
	commit(plr, profile, pending.tier, b)
	push(plr)
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
	if lastRequest[plr] and now - lastRequest[plr] < 0.05 then
		return
	end
	lastRequest[plr] = now

	if kind == "spin" then
		spin(plr, profile, a, b, c)
		return
	elseif kind == "keep" then
		keep(plr, profile, a)
		return
	elseif kind == "discard" then
		if profile.pending then
			profile.pending = nil
			dirty[plr] = true
		end
		push(plr)
		return
	elseif kind == "equip" then
		if Spins.isCosmetic(a) and profile.owned[a][b] then
			profile.equip[a] = b
			dirty[plr] = true
			applyCosmetics(plr, profile)
		end
		push(plr)
		return
	elseif kind == "buy" then
		local pack = Config.Shop.Packs[tonumber(a) or 0]
		if pack and pack.Id == 0 and RunService:IsStudio() then
			grantPack(plr, pack)
		end
		return
	end

	local tier = a
	if not Characters.isTier(tier) then
		return
	end
	if lockedFor(plr, tier) then
		push(plr, "Your character is locked until this match ends.")
		return
	end
	local build = copyBuild(ProfileService.build(plr, tier))
	if kind == "alloc" then
		local stat, delta = b, math.floor(tonumber(c) or 0)
		if not ALLOC_STEPS[delta] or not Characters.isStat(stat) then
			return
		end
		local n
		if delta > 0 then
			n = Characters.raisable(tier, build, stat, delta)
			if n <= 0 then
				push(plr, Characters.remaining(tier, build) <= 0 and "No free points. Take some from another stat first." or "That stat is at its cap. Spin stat caps to raise it.")
				return
			end
			build[stat] = build[stat] + n
		else
			n = Characters.lowerable(build, stat, -delta)
			if n <= 0 then
				return
			end
			build[stat] = build[stat] - n
		end
	elseif kind == "auto" then
		Characters.fill(tier, build)
	else
		return
	end
	commit(plr, profile, tier, build)
	push(plr)
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
	Net.get("SetCharacter").OnServerEvent:Connect(function(plr, tier, ability)
		if reg.TeamService.inMatch and reg.TeamService.entityForPlayer(plr) then
			push(plr, "Your character is locked until this match ends.")
			return
		end
		if Characters.isTier(tier) then
			plr:SetAttribute("Tier", tier)
		end
		if Characters.isAbility(ability) then
			plr:SetAttribute("Ability", ability)
		end
		ProfileService.applyActive(plr)
		push(plr)
	end)
end

return ProfileService
