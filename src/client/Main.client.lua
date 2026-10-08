-- Spike Rush client bootstrap.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")
local State = require(Controllers:WaitForChild("State"))

-- Match state and announcements feed the shared client state first, so every controller
-- sees consistent data when it reacts.
Net.get("MatchState").OnClientEvent:Connect(function(m)
	if type(m) == "table" then
		State.setMatch(m)
	end
end)
Net.get("Profile").OnClientEvent:Connect(function(p)
	if type(p) == "table" then
		State.setProfile(p)
	end
end)
Net.get("Announce").OnClientEvent:Connect(function(a)
	if type(a) ~= "table" then
		return
	end
	if a.kind == "Point" and a.scores then
		State.match.scores = a.scores
	end
	State.signals.Announce:Fire(a)
end)

local order = {
	"AudioController",
	"BallRenderer",
	"CameraController",
	"VFXController",
	"AnimationController",
	"MovementController",
	"InputController",
	"ActionController",
	"SetterAim",
	"UIController",
	"SceneController",
	"MenuController",
	"LineupController",
	"MobileControls",
	"CrowdController",
}

local mods = { State = State }
for _, name in ipairs(order) do
	mods[name] = require(Controllers:WaitForChild(name))
end
for _, name in ipairs(order) do
	local ok, err = pcall(mods[name].init, mods)
	if not ok then
		warn("[SpikeRush] " .. name .. ".init failed: " .. tostring(err))
	end
end

-- A reset would break rotations mid-rally, and the player list covers the score bug.
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

-- A game pass's chat tag (Config.Passes: the ChatTag attribute the server sets) in gold before
-- its owner's name.
pcall(function()
	local TextChatService = game:GetService("TextChatService")
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local who = source and Players:GetPlayerByUserId(source.UserId)
		local tag = who and who:GetAttribute("ChatTag")
		if type(tag) == "string" and tag ~= "" then
			props.PrefixText = string.format('<font color="#FFC828">[%s]</font> %s', tag, message.PrefixText)
		end
		return props
	end
end)

Net.get("ClientReady"):FireServer()
Net.get("Profile"):FireServer("get")
-- lets the loading screen (ReplicatedFirst) fade out
Players.LocalPlayer:SetAttribute("SpikeRushLoaded", true)
print("[SpikeRush] Client ready for " .. Players.LocalPlayer.Name)
