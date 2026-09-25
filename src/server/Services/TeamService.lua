-- Teams, serve order, roles, characters, team stamina and timeouts.
-- Players and bots share one entity shape. Players play their selected roster character in its
-- role when it's free; bots are roster characters of the bot level's tier (the Roster module).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Characters = require(Shared.Characters)
local HitLogic = require(Shared.HitLogic)
local Roster = require(Shared.Roster)

local TeamService = {}
local reg

TeamService.entities = {}
TeamService.teams = { Home = { order = {} }, Away = { order = {} } }
TeamService.teamSize = Config.Match.DefaultTeamSize
TeamService.inMatch = false
TeamService.pendingJoin = {}
TeamService.botTier = Config.Match.DefaultBotTier
TeamService.stamina = { Home = { value = 100, max = 100 }, Away = { value = 100, max = 100 } }
TeamService.timeouts = { Home = Config.Timeout.PerSet, Away = Config.Timeout.PerSet }

local botCounter = 0
local usedNames = {}
local usedChars = {} -- roster ids already on court this match

local function newRecord()
	return { kills = 0, aces = 0, blocks = 0, digs = 0, assists = 0, errors = 0, topKmh = 0 }
end

local function newEntity(id, name, isBot, plr, team, tier, ability, build)
	if not Characters.isTier(tier) then
		tier = Config.DefaultTier
	end
	if not Characters.isAbility(ability) then
		ability = nil
	end
	build = Characters.sanitize(tier, build)
	return {
		id = id,
		name = name,
		isBot = isBot,
		player = plr,
		team = team,
		tier = tier,
		ability = ability,
		build = build,
		role = "WS",
		charStats = Characters.derive(tier, build),
		stats = newRecord(),
	}
end

-- A player's entity is their selected roster character.
local function playerEntity(plr, team)
	local c = reg.ProfileService.character(plr)
	local tier, build = Characters.fromRoster(c)
	local e = newEntity("P_" .. tostring(plr.UserId), plr.DisplayName, false, plr, team, tier, c.Ability, build)
	e.charId, e.charName, e.prefRole = c.Id, c.Name, c.Role
	usedChars[c.Id] = true
	return e
end

-- The first role of `roles` nobody on `team` has yet (preferring `want`).
local function freeRole(team, roles, want)
	local taken = {}
	for _, e in ipairs(TeamService.members(team)) do
		taken[e.role] = true
	end
	for _, r in ipairs(roles) do
		if r == want and not taken[r] then
			return r
		end
	end
	for _, r in ipairs(roles) do
		if not taken[r] then
			return r
		end
	end
	return roles[1]
end

-- A roster character for a bot: that role, the tier nearest the bot level (within two steps),
-- not already on court.
local function rosterFor(tier, role)
	local want = role == "Solo" and "WS" or role
	local ti = Characters.tierIndex(tier) or 11
	local best, bestD = {}, 3
	for _, c in ipairs(Roster) do
		if c.Role == want and not usedChars[c.Id] then
			local d = math.abs((Characters.tierIndex(c.Tier) or 1) - ti)
			if d < bestD then
				best, bestD = { c }, d
			elseif d == bestD then
				table.insert(best, c)
			end
		end
	end
	if #best == 0 then
		return nil
	end
	return best[math.random(#best)]
end

function TeamService.getModel(e)
	if not e then
		return nil
	end
	if e.isBot then
		return e.model
	end
	return e.player and e.player.Character
end

function TeamService.getRoot(e)
	local m = TeamService.getModel(e)
	return m and m:FindFirstChild("HumanoidRootPart")
end

function TeamService.getHumanoid(e)
	local m = TeamService.getModel(e)
	return m and m:FindFirstChildOfClass("Humanoid")
end

-- HumanoidRootPart height when standing, for jump and hit-height math.
function TeamService.groundY(e)
	local m = TeamService.getModel(e)
	local hum = m and m:FindFirstChildOfClass("Humanoid")
	local root = m and m:FindFirstChild("HumanoidRootPart")
	if hum and root then
		return hum.HipHeight + root.Size.Y / 2
	end
	return Config.Player.RootGround
end

function TeamService.getEntity(id)
	if not id then
		return nil
	end
	return TeamService.entities[id]
end

function TeamService.entityForPlayer(plr)
	return TeamService.entities["P_" .. tostring(plr.UserId)]
end

function TeamService.members(team)
	local out = {}
	for _, id in ipairs(TeamService.teams[team].order) do
		local e = TeamService.entities[id]
		if e then
			table.insert(out, e)
		end
	end
	return out
end

function TeamService.byRole(team, role)
	for _, e in ipairs(TeamService.members(team)) do
		if e.role == role then
			return e
		end
	end
	return nil
end

function TeamService.serverOf(team)
	local id = TeamService.teams[team].order[1]
	return id and TeamService.entities[id]
end

-- Timeout rotation edits (see Court.reorder).
function TeamService.reorder(team, op, id, serving)
	local t = TeamService.teams[team]
	return t ~= nil and Court.reorder(t.order, op, id, serving)
end

-- Side-out: the next player in the order serves.
function TeamService.rotate(team)
	local order = TeamService.teams[team].order
	if #order > 1 then
		table.insert(order, table.remove(order, 1))
	end
end

-- Push tier, ability, role and team onto the character so every client can read them.
function TeamService.applyToModel(e)
	local model = TeamService.getModel(e)
	if not model then
		return
	end
	model:SetAttribute("Team", e.team)
	model:SetAttribute("Role", e.role)
	model:SetAttribute("Ability", e.ability or "")
	model:SetAttribute("CharName", e.charName or e.name)
	model:SetAttribute("EntityId", e.id)
	Characters.writeAttributes(model, e.tier, e.build)
	if e.player then
		-- the local client predicts its own hits from these
		Characters.writeAttributes(e.player, e.tier, e.build)
	end
	reg.CharacterService.applyStats(model, e.charStats)
end

------------------------------------------------------------------------------------------
-- Stamina (a team guard meter for heavy receives)
------------------------------------------------------------------------------------------

-- Adrenaline: when a team's stamina crosses the threshold, its Adrenaline characters get
-- (or lose) their boosted jump; HitLogic boosts their touches from the same stamina.
local function refreshBoosts(team)
	local s = TeamService.stamina[team]
	for _, e in ipairs(TeamService.members(team)) do
		if e.ability == "Adrenaline" then
			local stats, on = HitLogic.effectiveStats(e.charStats, e.ability, s)
			if on ~= (e.boosted == true) then
				e.boosted = on
				local model = TeamService.getModel(e)
				if model then
					reg.CharacterService.applyStats(model, stats)
					model:SetAttribute("Adrenaline", on)
				end
				if e.isBot then
					reg.BotService.refreshJump(e)
				end
			end
		end
	end
end

local function publishStamina(team)
	local s = TeamService.stamina[team]
	ReplicatedStorage:SetAttribute("Stamina_" .. team, s.value)
	ReplicatedStorage:SetAttribute("StaminaMax_" .. team, s.max)
	refreshBoosts(team)
end

function TeamService.staminaOf(team)
	local s = TeamService.stamina[team]
	return { value = s.value, max = s.max }
end

-- A team's pool is the average of its players' pools (Defense raises it).
local function poolFor(team)
	local sum, n = 0, 0
	for _, e in ipairs(TeamService.members(team)) do
		sum = sum + e.charStats.StaminaPool
		n = n + 1
	end
	if n == 0 then
		return 100
	end
	return sum / n
end

function TeamService.fillStamina(team)
	local s = TeamService.stamina[team]
	s.max = poolFor(team)
	s.value = s.max
	publishStamina(team)
end

function TeamService.recoverStamina(team, fraction)
	local s = TeamService.stamina[team]
	s.value = math.min(s.max, s.value + s.max * fraction)
	publishStamina(team)
end

-- Returns true if this drain broke the guard.
function TeamService.drainStamina(team, amount)
	local s = TeamService.stamina[team]
	if not amount or amount <= 0 then
		return false
	end
	local before = s.value
	s.value = math.max(0, s.value - amount)
	publishStamina(team)
	return before > 0 and s.value <= 0
end

------------------------------------------------------------------------------------------
-- Timeouts
------------------------------------------------------------------------------------------

local function publishTimeouts()
	for _, team in ipairs(Config.TeamOrder) do
		ReplicatedStorage:SetAttribute("Timeouts_" .. team, TeamService.timeouts[team])
	end
end

function TeamService.resetTimeouts()
	for _, team in ipairs(Config.TeamOrder) do
		TeamService.timeouts[team] = Config.Timeout.PerSet
	end
	publishTimeouts()
end

function TeamService.useTimeout(team)
	if (TeamService.timeouts[team] or 0) <= 0 then
		return false
	end
	TeamService.timeouts[team] = TeamService.timeouts[team] - 1
	publishTimeouts()
	return true
end

------------------------------------------------------------------------------------------
-- Rosters
------------------------------------------------------------------------------------------

local function pickBotName()
	local names = Config.Bots.Names
	for _ = 1, #names do
		local n = names[math.random(#names)]
		if not usedNames[n] then
			usedNames[n] = true
			return n
		end
	end
	botCounter = botCounter + 1
	return "Rookie " .. botCounter
end

local function addBot(team, index, role)
	botCounter = botCounter + 1
	local id = "B_" .. botCounter
	role = role or "WS"
	local e
	local c = rosterFor(TeamService.botTier, role)
	if c then
		usedChars[c.Id] = true
		local tier, build = Characters.fromRoster(c)
		e = newEntity(id, c.Name, true, nil, team, tier, c.Ability, build)
		e.charId, e.charName = c.Id, c.Name
	else
		local build = Characters.template(TeamService.botTier, role, Characters.rollHeight(Random.new()))
		e = newEntity(id, pickBotName(), true, nil, team, TeamService.botTier, nil, build)
	end
	e.role = role
	TeamService.entities[id] = e
	local order = TeamService.teams[team].order
	if index then
		table.insert(order, index, id)
	else
		table.insert(order, id)
	end
	reg.BotService.spawn(e)
	TeamService.applyToModel(e)
	return e
end

local function removeEntity(e)
	TeamService.entities[e.id] = nil
	local order = TeamService.teams[e.team].order
	for i = #order, 1, -1 do
		if order[i] == e.id then
			table.remove(order, i)
			return i
		end
	end
	return nil
end

-- Roles for a team of `size`, in the order humans claim them (the ace spot first).
local function roleList(size)
	if size <= 1 then
		return { "Solo" }
	elseif size == 2 then
		return { "WS", "SE" }
	end
	return { "WS", "MB", "SE" }
end

function TeamService.clear()
	for _, e in pairs(TeamService.entities) do
		if e.isBot then
			reg.BotService.despawn(e)
		end
	end
	TeamService.entities = {}
	TeamService.teams = { Home = { order = {} }, Away = { order = {} } }
	TeamService.inMatch = false
	TeamService.pendingJoin = {}
	usedNames = {}
	usedChars = {}
end

function TeamService.assign(size)
	TeamService.clear()
	TeamService.teamSize = size
	local humans = Players:GetPlayers()
	for i = #humans, 2, -1 do
		local j = math.random(i)
		humans[i], humans[j] = humans[j], humans[i]
	end
	local roles = roleList(size)
	for _, plr in ipairs(humans) do
		local home, away = #TeamService.teams.Home.order, #TeamService.teams.Away.order
		local team = nil
		if home <= away and home < size then
			team = "Home"
		elseif away < size then
			team = "Away"
		elseif home < size then
			team = "Home"
		end
		if team then
			local e = playerEntity(plr, team)
			e.role = freeRole(team, roles, e.prefRole)
			TeamService.entities[e.id] = e
			table.insert(TeamService.teams[team].order, e.id)
			TeamService.applyToModel(e)
		end
	end
	if Config.Match.FillWithBots then
		for _, team in ipairs(Config.TeamOrder) do
			while #TeamService.teams[team].order < size do
				addBot(team, nil, freeRole(team, roles))
			end
		end
	end
	TeamService.inMatch = true
	for _, team in ipairs(Config.TeamOrder) do
		TeamService.fillStamina(team)
	end
	TeamService.resetTimeouts()
end

function TeamService.endMatch()
	TeamService.clear()
end

function TeamService.resetStats()
	for _, e in pairs(TeamService.entities) do
		e.stats = newRecord()
	end
end

-- Snap everybody to their formation for the next serve, facing the net.
function TeamService.resetPositions(servingTeam)
	for _, team in ipairs(Config.TeamOrder) do
		local side = Court.sideOf(team)
		local server = TeamService.serverOf(team)
		for _, e in ipairs(TeamService.members(team)) do
			local spot
			if team == servingTeam and e == server then
				spot = Court.serveSpot(side, e.role)
			elseif team == servingTeam then
				spot = Court.formationSpot("Serving", e.role, side)
			else
				spot = Court.formationSpot("Receive", e.role, side)
			end
			local model = TeamService.getModel(e)
			if model then
				model:PivotTo(Court.facing(spot + Vector3.new(0, TeamService.groundY(e) + 0.2, 0), side))
				local root = model:FindFirstChild("HumanoidRootPart")
				if root then
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end
			if e.isBot then
				reg.BotService.onReset(e)
			end
		end
	end
end

function TeamService.roster()
	local out = { Home = {}, Away = {} }
	for _, team in ipairs(Config.TeamOrder) do
		for i, id in ipairs(TeamService.teams[team].order) do
			local e = TeamService.entities[id]
			if e then
				table.insert(out[team], {
					id = e.id,
					name = e.name,
					isBot = e.isBot,
					tier = e.tier,
					ability = e.ability,
					char = e.charName,
					role = e.role,
					height = e.build.Height,
					rot = i,
				})
			end
		end
	end
	return out
end

------------------------------------------------------------------------------------------
-- Joining and leaving mid-match
------------------------------------------------------------------------------------------

function TeamService.onCharacterAdded(plr, char)
	local e = TeamService.entityForPlayer(plr)
	if e then
		TeamService.applyToModel(e)
	else
		char:SetAttribute("Role", "Solo")
	end
end

-- A new player takes over a bot (and its role) at the start of the next rally.
function TeamService.hotJoin()
	if not TeamService.inMatch then
		return
	end
	for i = #TeamService.pendingJoin, 1, -1 do
		local plr = TeamService.pendingJoin[i]
		table.remove(TeamService.pendingJoin, i)
		if plr.Parent and not TeamService.entityForPlayer(plr) then
			local bestTeam, bestBot, fewestHumans = nil, nil, math.huge
			for _, team in ipairs(Config.TeamOrder) do
				local humans, bot = 0, nil
				for _, e in ipairs(TeamService.members(team)) do
					if e.isBot then
						if not bot or e.role == "WS" then
							bot = e
						end
					else
						humans = humans + 1
					end
				end
				if bot and humans < fewestHumans then
					bestTeam, bestBot, fewestHumans = team, bot, humans
				end
			end
			if bestBot then
				local role = bestBot.role
				local index = removeEntity(bestBot)
				reg.BotService.despawn(bestBot)
				local e = playerEntity(plr, bestTeam)
				e.role = role
				TeamService.entities[e.id] = e
				table.insert(TeamService.teams[bestTeam].order, index or 1, e.id)
				TeamService.applyToModel(e)
			end
		end
	end
end

function TeamService.onPlayerRemoving(plr)
	for i = #TeamService.pendingJoin, 1, -1 do
		if TeamService.pendingJoin[i] == plr then
			table.remove(TeamService.pendingJoin, i)
		end
	end
	local e = TeamService.entityForPlayer(plr)
	if not e or not TeamService.inMatch then
		TeamService.entities["P_" .. tostring(plr.UserId)] = nil
		return
	end
	local index = removeEntity(e)
	local bot = addBot(e.team, index, e.role)
	local BS = reg.BallService
	if BS.state == "Held" and BS.holderId == e.id then
		BS.hold(bot.id)
		reg.MatchService.serverId = bot.id
	end
	reg.MatchService.broadcast()
end

function TeamService.init(r)
	reg = r
	local function setup(plr)
		if not Characters.isTier(plr:GetAttribute("Tier")) then
			plr:SetAttribute("Tier", Config.DefaultTier)
		end
		if TeamService.inMatch then
			table.insert(TeamService.pendingJoin, plr)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, plr in ipairs(Players:GetPlayers()) do
		setup(plr)
	end
	Players.PlayerRemoving:Connect(TeamService.onPlayerRemoving)
	for _, team in ipairs(Config.TeamOrder) do
		publishStamina(team)
	end
	publishTimeouts()
end

return TeamService
