-- Client-side state shared by every controller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Characters = require(Shared.Characters)
local Settings = require(Shared.Settings)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

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
	maxSets = Config.Match.MaxSets,
	botTier = Config.Match.DefaultBotTier,
}
State.myTeam = nil
State.mySide = 1
State.myRole = "Solo"
State.isPlaying = false
-- Watching the match on this server's court from the menus' Spectate (the owner: "add a spectate
-- button next to lobbies so you can watch ongoing matches"): the HUD, the camera and the effects
-- treat a spectator like a player, without any of the controls.
State.spectating = false

-- Whether this client is watching the court: playing on it, or spectating.
function State.watching()
	return State.isPlaying or State.spectating
end
-- A touch device. In Studio the workspace attribute ForceTouch pretends to be one, so the touch
-- controls show and take mouse clicks (testing them without the device emulator).
State.isMobile = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	or (RunService:IsStudio() and workspace:GetAttribute("ForceTouch") == true)
State.context = {}
State.profile = nil
State.lastAttack = nil -- { kmh, height, thunder, ... } for the speed readout

-- The defaults; the profile's saved settings replace them once it arrives (setProfile).
State.settings = {
	landingMarker = true,
	shake = 1,
	dramatic = true, -- impact frames, hit-stops, speed lines
	assist = State.isMobile, -- auto-receive assist (capped quality) defaults on for touch
	followCam = false, -- off: the fully zoomed-out wide shot during play
	doubleApproach = false, -- Spike on the ground starts a run-up and a second press jumps
	setterAim = true, -- as the setter, aim where your set goes (SetterAim)
	beginner = false, -- Beginner mode (Config.Beginner): offered in the tutorial
	touchLayout = {}, -- touch buttons you moved or resized: name -> { x, y, size }
	hudLayout = {}, -- HUD pieces you moved or resized on touch (HudLayout): key -> { x, y, size }
	tour = 0, -- the menu tour after the tutorial: the step you're on (4: done)
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

-- Settings live in the profile: the saved ones are applied once, from the first snapshot, and
-- every change is sent back SaveDelay seconds after the last one (the server cleans them).
local SAVED = Config.Settings
local settingsLoaded = false
local saveToken = 0

local function queueSettingsSave()
	saveToken = saveToken + 1
	local token = saveToken
	task.delay(SAVED.SaveDelay, function()
		if token == saveToken then
			Net.get("Profile"):FireServer("settings", Settings.clean(State.settings))
		end
	end)
end

function State.setProfile(p)
	State.profile = p
	if not settingsLoaded then
		settingsLoaded = true
		for key, value in pairs(Settings.clean(p.settings)) do
			State.settings[key] = value
			State.signals.Settings:Fire(key, value)
		end
	end
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

-- A team's name as shown: its clan's while more than half of the team (bots counted) plays for
-- one clan (the owner, 2026-10-22: "instead of sunrise if majority of the team is your clan i want
-- it to display that"), else Config.Teams' (Sunrise, Tidal). Read from the players' ClanTag and
-- ClanName attributes (ClanService).
-- The clan most of a team plays for: its tag and name, or nil.
function State.teamClan(team)
	local members = State.roster(team)
	local counts = {}
	for _, e in ipairs(members) do
		local uid = type(e.id) == "string" and tonumber(string.match(e.id, "^P_(%d+)$"))
		local p = uid and Players:GetPlayerByUserId(uid)
		local tag = p and p:GetAttribute("ClanTag")
		if type(tag) == "string" and tag ~= "" then
			counts[tag] = (counts[tag] or 0) + 1
			if counts[tag] * 2 > #members then
				return tag, p:GetAttribute("ClanName") or tag
			end
		end
	end
	return nil
end

function State.teamName(team)
	local _, name = State.teamClan(team)
	local t = Config.Teams[team or ""]
	return name or (t and t.Name) or "?"
end

-- The short name on the arena's scoreboards: the clan's tag, or SUN / TDL.
function State.teamShort(team)
	local tag = State.teamClan(team)
	local t = Config.Teams[team or ""]
	return tag or (t and t.Short) or "?"
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
local abilitiesCache = nil -- { list, set, actives } (myAbilities: read every frame and physics step too)
player.AttributeChanged:Connect(function()
	statsCache = nil
	abilitiesCache = nil
end)

-- Beginner mode is on for your spikes: switched on, and not a ranked match (Config.Beginner).
function State.beginner()
	return State.settings.beginner == true and not ReplicatedStorage:GetAttribute("RankedMatch")
end

function State.myStats()
	if not statsCache then
		statsCache = Characters.fromAttributes(player) or Characters.stats(Config.DefaultTier)
	end
	return statsCache
end

-- My character's ability, or nil (only S and S+ characters have one). With the Halloween Match's
-- ability cards it's still my own (the primary): the cards stack beside it (myAbilities).
function State.myAbility()
	local a = player:GetAttribute("Ability")
	if Characters.isAbility(a) then
		return a
	end
	return nil
end

-- Every ability I play, in order: my own first, then each ability card's in hand order (the owner,
-- 2026-10-15: "i want them to stack"). Read from the "Abilities" attribute the server writes, so
-- the touch predicted here plays the same list the server's does. Cached; don't change the tables.
local function abilities()
	if not abilitiesCache then
		local list = Characters.abilitiesOf(player)
		local actives = {}
		for _, name in ipairs(list) do
			if Config.Abilities[name].Active then
				table.insert(actives, name)
			end
		end
		abilitiesCache = { list = list, set = Characters.abilitySet(list), actives = actives }
	end
	return abilitiesCache
end

function State.myAbilities()
	return abilities().list
end

-- { [name] = true } for myAbilities (what HitLogic's ctx.abilities takes).
function State.abilitySet()
	return abilities().set
end

function State.hasAbility(name)
	return abilities().set[name] == true
end

-- The ones the Ability key pops (Config.Abilities[x].Active), in the same order.
function State.myActives()
	return abilities().actives
end

-- An ability's breakthrough level: my character's for my own, +0 for a card's.
function State.breakOf(name)
	if name ~= nil and name == State.myAbility() then
		return player:GetAttribute("Break") or 0
	end
	return 0
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

-- Points the other team has this set (Rising Sun's level follows them).
function State.enemyPoints(team)
	local scores = State.match.scores or {}
	return scores[team == "Home" and "Away" or "Home"] or 0
end

-- Whether a team's Rally Cry is on at shared-clock time t.
function State.rallyOn(team, t)
	if not team then
		return false
	end
	return (ReplicatedStorage:GetAttribute("RallyUntil_" .. team) or -1) >= t
end

-- Rally Cry's boost on `team` (its caller's, grown by breakthroughs), and a Dictate's steal.
function State.rallyBoost(team)
	return ReplicatedStorage:GetAttribute("RallyBoost_" .. tostring(team)) or Config.Abilities.RallyCry.Boost
end

function State.dictateSteal(team)
	return ReplicatedStorage:GetAttribute("DictateSteal_" .. tostring(team)) or Config.Abilities.Tyrant.Steal
end

-- Whether `team`'s Tyrant has Emperor's Dictate on at shared-clock time t.
function State.dictateOn(team, t)
	if not team then
		return false
	end
	return (ReplicatedStorage:GetAttribute("DictateUntil_" .. team) or -1) >= t
end

-- Sunshine: lit on this character (a model or the local player) at shared-clock time t.
function State.sunOn(inst, t)
	return inst ~= nil and (inst:GetAttribute("SunshineUntil") or -1) >= t
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
	queueSettingsSave()
end

return State
