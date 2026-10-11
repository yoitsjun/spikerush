-- Quick chat (the owner: "a quick chat feature... prewritten phrases like 'nice play' 'set me'
-- 'lag' 'ref' 'gg'... but also emojis"): a player picks a phrase or an emoji (Config.QuickChat)
-- by its number, the server checks it and the rate (Config.QuickChat Burst / Window / Gap) and
-- tells everyone in the server, whose screens pop it over that player's head. Only the
-- prewritten lists, so nothing to filter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local QuickChatService = {}
local QC = Config.QuickChat

local sent = {} -- player -> the times of their recent quick chats

local function allowed(plr, now)
	local recent = {}
	for _, t in ipairs(sent[plr] or {}) do
		if now - t < QC.Window then
			table.insert(recent, t)
		end
	end
	sent[plr] = recent
	if #recent >= QC.Burst then
		return false
	end
	local last = recent[#recent]
	return not (last and now - last < QC.Gap)
end

function QuickChatService.init()
	local remote = Net.get("QuickChat")
	remote.OnServerEvent:Connect(function(plr, kind, i)
		local list = (kind == "Phrase" and QC.Phrases) or (kind == "Emoji" and QC.Emojis) or nil
		if not list or type(i) ~= "number" or i ~= math.floor(i) or not list[i] then
			return
		end
		local now = os.clock()
		if not allowed(plr, now) then
			return
		end
		table.insert(sent[plr], now)
		remote:FireAllClients(plr.UserId, kind, i)
	end)
	Players.PlayerRemoving:Connect(function(plr)
		sent[plr] = nil
	end)
end

return QuickChatService
