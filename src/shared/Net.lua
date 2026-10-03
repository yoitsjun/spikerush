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
	"Leaderboard", -- client asks, server answers with every board
	"SetCharacter",
	"Timeout",
	"Profile",
	"Forfeit",
	"Rotation",
	"SetAim", -- client -> server: a setter's aim (depth, or false); server -> teammates: (id, depth)
	"Admin", -- the admin panel: client -> server ops, server -> client replies (AdminService)
	"Notice", -- server -> client: announcements and events starting, shown to everyone
	"PlayerProfile", -- server -> client: a player's public profile (asked with Profile "profileOf")
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
