-- Player profiles: one saved character per tier (rolled height + four stats) and a balance of
-- upgrade points. Saved with DataStoreService; falls back to session-only profiles when the
-- DataStore isn't reachable (e.g. Studio without "Enable Studio Access to API Services").
--
-- Client requests arrive on the "Profile" remote:
--   ("get")                         -> reply with a snapshot
--   ("upgrade", tier, stat, amount) -> spend points on a stat (tier cap and total cap apply)
--   ("reroll", tier)                -> spend points to re-roll that character's height
-- and on "SetCharacter" (tier, ability) to pick which character you play.
-- Your active character locks while you're in a match, so prediction always matches the server.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)
local Net = require(Shared.Net)

local ProfileService = {}
local reg

local P = Config.Progression
local profiles = {}
local dirty = {}
local store = nil
local warned = false

local function key(plr)
	return "u_" .. tostring(plr.UserId)
end

local function newProfile()
	return { v = 1, points = P.StartingPoints, builds = {} }
end

local function sanitizeProfile(data)
	if type(data) ~= "table" then
		return newProfile()
	end
	local out = { v = 1, points = math.max(0, math.floor(tonumber(data.points) or 0)), builds = {} }
	if type(data.builds) == "table" then
		for tier, b in pairs(data.builds) do
			if Characters.isTier(tier) then
				out.builds[tier] = Characters.sanitize(tier, b)
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
	profiles[plr] = profile
	return profile
end

local function save(plr)
	local profile = profiles[plr]
	if not profile or not store or not profile.canSave or not dirty[plr] then
		return
	end
	local payload = { v = 1, points = profile.points, builds = profile.builds }
	local success = pcall(function()
		store:UpdateAsync(key(plr), function()
			return payload
		end)
	end)
	if success then
		dirty[plr] = nil
	end
end

function ProfileService.get(plr)
	return profiles[plr] or load(plr)
end

-- The saved character for `tier`, created (with a rolled height) the first time it's used.
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
end

function ProfileService.snapshot(plr)
	local profile = ProfileService.get(plr)
	local builds = {}
	for _, tier in ipairs(Config.Tiers) do
		if profile.builds[tier] then
			builds[tier] = table.clone(profile.builds[tier])
		end
	end
	return {
		points = profile.points,
		builds = builds,
		tier = plr:GetAttribute("Tier"),
		ability = plr:GetAttribute("Ability"),
		saving = profile.canSave and store ~= nil,
	}
end

local function push(plr, notice)
	local snap = ProfileService.snapshot(plr)
	snap.notice = notice
	Net.get("Profile"):FireClient(plr, snap)
end

function ProfileService.award(plr, amount)
	local profile = profiles[plr]
	if not profile or amount <= 0 then
		return
	end
	profile.points = profile.points + math.floor(amount)
	dirty[plr] = true
	push(plr)
end

local function lockedFor(plr, tier)
	local TS = reg.TeamService
	return TS.inMatch and TS.entityForPlayer(plr) ~= nil and tier == plr:GetAttribute("Tier")
end

local function onRequest(plr, kind, tier, stat, amount)
	local profile = ProfileService.get(plr)
	if kind == "get" then
		push(plr)
		return
	end
	if not Characters.isTier(tier) then
		return
	end
	if lockedFor(plr, tier) then
		push(plr, "Your character is locked until this match ends.")
		return
	end
	local b = ProfileService.build(plr, tier)
	if kind == "upgrade" then
		amount = math.clamp(math.floor(tonumber(amount) or 1), 1, 25)
		local n = math.min(Characters.raisable(tier, b, stat, amount), profile.points)
		if n <= 0 then
			push(plr, profile.points <= 0 and "No upgrade points left." or "That stat is at this tier's cap.")
			return
		end
		b[stat] = b[stat] + n
		profile.points = profile.points - n
	elseif kind == "reroll" then
		if profile.points < P.HeightRollCost then
			push(plr, "Not enough points to re-roll height.")
			return
		end
		profile.points = profile.points - P.HeightRollCost
		b.Height = Characters.rollHeight(Random.new())
	else
		return
	end
	profile.builds[tier] = Characters.sanitize(tier, b)
	dirty[plr] = true
	if tier == plr:GetAttribute("Tier") then
		ProfileService.applyActive(plr)
	end
	push(plr)
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
