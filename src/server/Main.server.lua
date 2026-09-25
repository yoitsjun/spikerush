-- Spike Rush server bootstrap.
-- Services receive a shared registry instead of requiring each other, which keeps the
-- dependency graph flat and avoids circular requires.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
Net.ensureAll()

local Services = script.Parent:WaitForChild("Services")

local registry = {}
local order = {
	"ToolboxService",
	"FriendService",
	"CharacterService",
	"ArenaBuilder",
	"BallService",
	"TeamService",
	"ProfileService",
	"BotService",
	"HitService",
	"LobbyService",
	"MatchService",
}

for _, name in ipairs(order) do
	registry[name] = require(Services:WaitForChild(name))
end

for _, name in ipairs(order) do
	local service = registry[name]
	if service.init then
		local ok, err = pcall(service.init, registry)
		if not ok then
			warn("[SpikeRush] " .. name .. ".init failed: " .. tostring(err))
		end
	end
end

registry.MatchService.start()
print("[SpikeRush] Server ready")
