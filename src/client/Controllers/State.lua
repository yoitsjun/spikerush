-- Client-side state shared by every controller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)
local Util = require(Shared.Util)

local player = Players.LocalPlayer

local State = {}

State.player = player
State.myId = "P_" .. tostring(player.UserId)
State.match = {
	phase = "Intermission",
	phaseEnd = 0,
	mode = Config.Match.DefaultTeamSize,
	rosters = { Home = {}, Away = {} },
	scores = { Home = 0, Away = 0 },
	sets = { Home = 0, Away = 0 },
	votes = { v1 = 0, v2 = 0, v3 = 0 },
	setNumber = 1,
	target = Config.Match.PointsPerSet,
	setsToWin = Config.Match.SetsToWin,
	botTier = Config.Match.DefaultBotTier,
}
State.myTeam = nil
State.mySide = 1
State.myRole = "Solo"
State.isPlaying = false
State.isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
State.context = {}
State.profile = nil
State.lastAttack = nil -- { kmh, height, thunder, ... } for the speed readout

State.settings = {
	landingMarker = true,
	shake = 1,
	dramatic = true, -- impact frames, hit-stops, speed lines
	assist = State.isMobile, -- auto-receive assist (capped quality) defaults on for touch
	closeCam = false,
}

State.signals = {
	Match = Util.Signal(),
	Ball = Util.Signal(), -- (snapshot, isEcho)
	BallEvent = Util.Signal(), -- ("Land" | "Net", event, meta)
	Announce = Util.Signal(),
	Action = Util.Signal(), -- (entityId, kind, extra) cosmetic actions: slide, block, jump, charge
	Settings = Util.Signal(),
	Hint = Util.Signal(),
	Profile = Util.Signal(),
	Charge = Util.Signal(), -- (energy, gauge, state) local Azure charge
}

function State.setMatch(m)
	State.match = m
	State.myTeam = nil
	State.myRole = "Solo"
	for _, team in ipairs(Config.TeamOrder) do
		local roster = (m.rosters and m.rosters[team]) or {}
		for _, e in ipairs(roster) do
			if e.id == State.myId then
				State.myTeam = team
				State.myRole = e.role or "Solo"
			end
		end
	end
	State.isPlaying = State.myTeam ~= nil
	if State.myTeam then
		State.mySide = Config.Teams[State.myTeam].Side
	end
	State.signals.Match:Fire(m)
end

function State.setProfile(p)
	State.profile = p
	State.signals.Profile:Fire(p)
end

function State.phase()
	return State.match.phase
end

function State.teamSize()
	return State.match.mode or 3
end

function State.roster(team)
	return (State.match.rosters and State.match.rosters[team]) or {}
end

function State.entry(id)
	for _, team in ipairs(Config.TeamOrder) do
		for _, e in ipairs(State.roster(team)) do
			if e.id == id then
				return e, team
			end
		end
	end
	return nil, nil
end

function State.teamOf(id)
	local _, team = State.entry(id)
	return team
end

function State.sideOfEntity(id)
	local team = State.teamOf(id)
	return team and Config.Teams[team].Side or nil
end

function State.isServer()
	return State.match.serverId == State.myId
end

-- My character's derived stats, exactly as the server computes them. This sits on the hottest
-- client paths (every zone test, every frame), so the derived table is cached until the server
-- rewrites any of the build attributes. derive() is pure, so the cache can't change a result.
local statsCache = nil
player.AttributeChanged:Connect(function()
	statsCache = nil
end)

function State.myStats()
	if not statsCache then
		statsCache = Characters.fromAttributes(player) or Characters.stats(Config.DefaultTier)
	end
	return statsCache
end

-- My character's ability, or nil (only S and S+ characters have one).
function State.myAbility()
	local a = player:GetAttribute("Ability")
	if Characters.isAbility(a) then
		return a
	end
	return nil
end

-- Depth lane I stand on (players never walk toward or away from the camera).
function State.myLane()
	if not State.isPlaying then
		return 0
	end
	return Config.Lanes[State.myRole] or 0
end

function State.stamina(team)
	local v = ReplicatedStorage:GetAttribute("Stamina_" .. team) or 100
	local m = ReplicatedStorage:GetAttribute("StaminaMax_" .. team) or 100
	return { value = v, max = m }
end

function State.timeouts(team)
	return ReplicatedStorage:GetAttribute("Timeouts_" .. team) or Config.Timeout.PerSet
end

function State.hint(text)
	State.signals.Hint:Fire(text)
end

function State.setSetting(key, value)
	State.settings[key] = value
	State.signals.Settings:Fire(key, value)
end

return State
