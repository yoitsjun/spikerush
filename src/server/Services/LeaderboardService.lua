-- Leaderboards: wins, best win streak, spike kills, aces and blocks, across every server.
-- Each board is an OrderedDataStore keyed u_<UserId>. A player's scores are queued when a match
-- changes their counters (and once when they join, for counters from before the boards
-- existed) and written every FlushInterval and when they leave. The top of every board is read
-- every RefreshInterval and merged with the players in this server (their fresh numbers show at
-- once). Without DataStore access (Studio without API access) the boards rank this server only.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Leaderboards = require(Shared.Leaderboards)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local LeaderboardService = {}
local reg
local LB = Config.Leaderboards

local stores = {} -- board key -> OrderedDataStore (or nil when unavailable)
local pending = {} -- userId -> values to write
local names = {} -- userId -> display name
local stored = {} -- board key -> rows read from the store
local global = false -- whether the last read reached the stores
local lastRead = -math.huge
local reading = false
local lastRequest = {}

local function openStores()
	for _, b in ipairs(LB.Boards) do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(LB.StorePrefix .. b.Key)
		end)
		stores[b.Key] = ok and store or nil
	end
end

-- Queue a player's current numbers for writing (ProfileService calls this after a match).
function LeaderboardService.track(plr, profile)
	if not plr or not profile then
		return
	end
	local values = Leaderboards.valuesOf(profile)
	local any = false
	for _, v in pairs(values) do
		if v > 0 then
			any = true
		end
	end
	if any then
		pending[plr.UserId] = values
	end
	names[plr.UserId] = plr.DisplayName
end

local function flush()
	for userId, values in pairs(pending) do
		pending[userId] = nil
		for key, value in pairs(values) do
			local store = stores[key]
			if store and value > 0 then
				local ok, err = pcall(function()
					store:SetAsync("u_" .. tostring(userId), value)
				end)
				if not ok then
					warn("[SpikeRush] leaderboard write: " .. tostring(err))
				end
			end
		end
	end
end

-- Display names for user ids we haven't seen, in batches (a failure just leaves "Player").
local function resolveNames(ids)
	local missing = {}
	for _, id in ipairs(ids) do
		if not names[id] then
			table.insert(missing, id)
		end
	end
	local i = 1
	while i <= #missing do
		local batch = {}
		for j = i, math.min(i + 99, #missing) do
			table.insert(batch, missing[j])
		end
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(batch)
		end)
		if ok and type(infos) == "table" then
			for _, info in ipairs(infos) do
				names[info.Id] = info.DisplayName or info.Username
			end
		end
		i = i + 100
	end
end

local function read()
	if reading then
		return
	end
	reading = true
	lastRead = Util.now()
	local anyOk = false
	local ids = {}
	for _, b in ipairs(LB.Boards) do
		local store = stores[b.Key]
		local rows = {}
		if store then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, LB.Top)
			end)
			if ok and pages then
				anyOk = true
				for _, entry in ipairs(pages:GetCurrentPage()) do
					local id = tonumber(string.match(tostring(entry.key), "^u_(%d+)$"))
					if id then
						table.insert(rows, { userId = id, value = math.floor(tonumber(entry.value) or 0) })
						table.insert(ids, id)
					end
				end
			end
		end
		stored[b.Key] = rows
	end
	global = anyOk
	resolveNames(ids)
	for _, rows in pairs(stored) do
		for _, r in ipairs(rows) do
			r.name = names[r.userId]
		end
	end
	reading = false
end

-- Every board as the client shows it: stored rows merged with this server's players.
local function snapshot()
	local live = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local profile = reg.ProfileService.peek(plr)
		if profile then
			table.insert(live, { userId = plr.UserId, name = plr.DisplayName, values = Leaderboards.valuesOf(profile) })
		end
	end
	local boards = {}
	for _, b in ipairs(LB.Boards) do
		local liveRows = {}
		for _, l in ipairs(live) do
			table.insert(liveRows, { userId = l.userId, name = l.name, value = l.values[b.Key] })
		end
		local rows = Leaderboards.merge(stored[b.Key], liveRows, LB.Top)
		for _, r in ipairs(rows) do
			r.name = r.name or names[r.userId] or "Player"
		end
		boards[b.Key] = rows
	end
	return { boards = boards, global = global, updated = lastRead, refresh = LB.RefreshInterval }
end

function LeaderboardService.init(r)
	reg = r
	openStores()
	Net.get("Leaderboard").OnServerEvent:Connect(function(plr)
		local now = os.clock()
		if lastRequest[plr] and now - lastRequest[plr] < 2 then
			return
		end
		lastRequest[plr] = now
		if Util.now() - lastRead > LB.RefreshInterval then
			task.spawn(read)
		end
		Net.get("Leaderboard"):FireClient(plr, snapshot())
	end)
	local function joined(plr)
		names[plr.UserId] = plr.DisplayName
		task.spawn(function()
			-- counters from before the boards existed get onto them once
			LeaderboardService.track(plr, reg.ProfileService.get(plr))
		end)
	end
	Players.PlayerAdded:Connect(joined)
	for _, plr in ipairs(Players:GetPlayers()) do
		joined(plr)
	end
	Players.PlayerRemoving:Connect(function(plr)
		lastRequest[plr] = nil
		if pending[plr.UserId] then
			task.spawn(flush)
		end
	end)
	game:BindToClose(flush)
	task.spawn(function()
		read()
		while true do
			task.wait(LB.FlushInterval)
			flush()
			if Util.now() - lastRead >= LB.RefreshInterval then
				read()
			end
		end
	end)
end

return LeaderboardService
