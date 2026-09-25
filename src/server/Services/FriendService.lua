-- Bots look like the players' Roblox friends. When a player joins, their friends list is read
-- (up to Config.Bots.FriendsPerPlayer); a bot then borrows an unused friend's name and avatar
-- (HumanoidDescription, cached). When the list can't be read (no friends, Studio without
-- network, a web error) bots fall back to default rigs and their roster names.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local FriendService = {}

local friendsOf = {} -- Player -> { { id, name } }
local descriptions = {} -- userId -> HumanoidDescription (or false when it failed)
local taken = {} -- userId -> true while a bot wears that friend this match

local function load(plr)
	local list = {}
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(plr.UserId)
	end)
	if ok and pages then
		while #list < Config.Bots.FriendsPerPlayer do
			for _, f in ipairs(pages:GetCurrentPage()) do
				if #list >= Config.Bots.FriendsPerPlayer then
					break
				end
				table.insert(list, { id = f.Id, name = f.DisplayName or f.Username })
			end
			if pages.IsFinished then
				break
			end
			local more = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)
			if not more then
				break
			end
		end
	end
	-- shuffle so the same friends don't always show up
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	if plr.Parent then
		friendsOf[plr] = list
	end
end

-- A friend of any player in the server that no bot is wearing yet, or nil.
function FriendService.take()
	for _, plr in ipairs(Players:GetPlayers()) do
		for _, f in ipairs(friendsOf[plr] or {}) do
			if not taken[f.id] and not Players:GetPlayerByUserId(f.id) then
				taken[f.id] = true
				return f
			end
		end
	end
	return nil
end

function FriendService.release(friendId)
	if friendId then
		taken[friendId] = nil
	end
end

function FriendService.releaseAll()
	taken = {}
end

-- That friend's avatar as a HumanoidDescription (a fresh copy), or nil. Yields the first time.
function FriendService.description(friendId)
	if descriptions[friendId] == nil then
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(friendId)
		end)
		descriptions[friendId] = (ok and desc) or false
	end
	local d = descriptions[friendId]
	return d and d:Clone() or nil
end

function FriendService.init()
	local function added(plr)
		task.spawn(load, plr)
	end
	Players.PlayerAdded:Connect(added)
	for _, plr in ipairs(Players:GetPlayers()) do
		added(plr)
	end
	Players.PlayerRemoving:Connect(function(plr)
		friendsOf[plr] = nil
	end)
end

return FriendService
