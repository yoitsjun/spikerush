-- Character setup shared by players and bots: collision groups and humanoid tuning.
-- Jump height and run speed come from each character's build (height + Jump + Speed stats),
-- so no two characters need to jump the same.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)

local CharacterService = {}
local reg

local function register(name)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end

local function setGroup(model, group)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end)
end

local function groundY(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if hum and root then
		return hum.HipHeight + root.Size.Y / 2
	end
	return Config.Player.RootGround
end

-- stats = Characters.derive(...) output
function CharacterService.applyStats(model, stats)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hum or not stats then
		return
	end
	hum.UseJumpPower = false
	hum.JumpHeight = Characters.jumpHeight(stats, groundY(model))
	hum.WalkSpeed = stats.WalkSpeed
	model:SetAttribute("BaseJumpHeight", hum.JumpHeight)
	model:SetAttribute("BaseWalkSpeed", hum.WalkSpeed)
end

function CharacterService.setupHumanoid(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum.UseJumpPower = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- we draw our own name tags
	CharacterService.applyStats(model, Characters.stats(Config.DefaultTier))
	setGroup(model, "Players")
end

function CharacterService.init(r)
	reg = r
	register("Players")
	register("NetBarrier")
	-- Players never shove each other (no body-blocking griefing, no clumping on the ball).
	PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("NetBarrier", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("NetBarrier", "NetBarrier", false)

	local function onPlayer(plr)
		plr.CharacterAdded:Connect(function(char)
			CharacterService.setupHumanoid(char)
			char:SetAttribute("EntityId", "P_" .. tostring(plr.UserId))
			if reg.TeamService and reg.TeamService.onCharacterAdded then
				reg.TeamService.onCharacterAdded(plr, char)
			end
		end)
		if plr.Character then
			CharacterService.setupHumanoid(plr.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, plr in ipairs(Players:GetPlayers()) do
		onPlayer(plr)
	end
end

return CharacterService
