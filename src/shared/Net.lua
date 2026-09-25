-- Remote access. Remotes are declared in default.project.json; the server also creates any
-- that are missing so the game still boots if the project file was only partially synced.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Names = {
	"BallState",
	"HitRequest",
	"HitReject",
	"ActionFX",
	"MatchState",
	"Announce",
	"ClientReady",
	"Lobby", -- client -> server: create, quick, join, leave, start, team, kick, settings, rejoin
	"Lobbies", -- server -> client: the lobby list, your lobby, notices
	"Activity", -- client -> server: "I pressed something" (AFK detection)
	"Continue", -- client -> server: after a set, keep playing (true) or end the match (false)
	"SetCharacter",
	"Timeout",
	"Profile",
	"Forfeit",
	"Rotation",
}

local cache = {}

function Net.ensureAll()
	if not RunService:IsServer() then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(Net.Names) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Net.get(name)
	local remote = cache[name]
	if remote then
		return remote
	end
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	remote = folder:WaitForChild(name, 15)
	if not remote then
		error("[SpikeRush] Missing remote '" .. name .. "'. Is the Rojo project synced?")
	end
	cache[name] = remote
	return remote
end

return Net
