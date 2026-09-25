-- Teams, serve order, roles, characters, team stamina and timeouts.
-- Players and bots share one entity shape. Players play their selected roster character in its
-- role when it's free; bots are roster characters of the bot level's tier (the Roster module).
-- A player who leaves, or goes AFK while the ball is live (Config.Afk), is replaced on the spot
-- by an AI playing their own character in their own avatar; an AFK player can take the slot
-- back at the next dead ball (Rejoin in the menu).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local Characters = require(Shared.Characters)
local HitLogic = require(Shared.HitLogic)
local Roster = require(Shared.Roster)
local Lobbies = require(Shared.Lobbies)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

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
TeamService.benched = {} -- userId -> id of the AI standing in for them
TeamService.idle = {} -- userId -> seconds without input while the ball was live
TeamService.rallyUntil = { Home = -1, Away = -1 } -- Rally Cry: the team's boost lasts until then

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
	local c, tier, build = reg.ProfileService.characterBuild(plr)
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
-- not already on court. Characters that start a set weak (Config.Bots.AvoidAbilities) only
-- when nobody else fits.
local function rosterFor(tier, role)
	local want = role == "Solo" and "WS" or role
	local ti = Characters.tierIndex(tier) or 11
	local avoid = Config.Bots.AvoidAbilities
	local best, bestD = {}, 3
	for pass = 1, 2 do
		for _, c in ipairs(Roster) do
			if c.Role == want and not usedChars[c.Id] and (pass == 2 or not avoid[c.Ability or ""]) then
				local d = math.abs((Characters.tierIndex(c.Tier) or 1) - ti)
				if d < bestD then
					best, bestD = { c }, d
				elseif d == bestD then
					table.insert(best, c)
				end
			end
		end
		if #best > 0 then
			break
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
	reg.CharacterService.applyStats(model, e.liveStats or e.charStats)
	-- ability state for the HUDs and effects (a new entity starts with it ready)
	for _, inst in ipairs({ model, e.player or false }) do
		if inst then
			inst:SetAttribute("Counter", e.ability == "Counter" and (e.counter or 0) or nil)
			inst:SetAttribute("AbilityUntil", e.abilityUntil or -1)
			inst:SetAttribute("AbilityReadyAt", e.abilityReadyAt or 0)
		end
	end
end

------------------------------------------------------------------------------------------
-- Stamina (a team guard meter for heavy receives) and stat boosts
------------------------------------------------------------------------------------------

-- What a character's stats depend on besides the team's stamina (HitLogic.effectiveStats'
-- `extra`): the other team's points this set (Rising Sun), the Counter Edge meter and its own
-- team's Rally Cry.
function TeamService.boostCtx(e, t)
	local scores = reg.MatchService.scores or {}
	return {
		enemyPoints = scores[Court.other(e.team)] or 0,
		counter = e.counter or 0,
		teamBoost = (TeamService.rallyUntil[e.team] or -1) >= (t or Util.now()),
	}
end

-- Boosts change a character's real jump and run speed: Adrenaline (low stamina), Rising Sun
-- (the other team's points), Counter Edge (the meter) and Rally Cry (the team's pop). When a character's boosted stats
-- change, its humanoid is re-tuned (HitLogic boosts the touches from the same inputs) and the
-- character is flagged for everyone's effects (Adrenaline, SunLevel).
function TeamService.refreshBoosts(team)
	local s = TeamService.stamina[team]
	local now = Util.now()
	for _, e in ipairs(TeamService.members(team)) do
		local extra = TeamService.boostCtx(e, now)
		local stats, on = HitLogic.effectiveStats(e.charStats, e.ability, s, extra)
		local model = TeamService.getModel(e)
		if stats ~= (e.liveStats or e.charStats) then
			e.liveStats = stats ~= e.charStats and stats or nil
			if model then
				reg.CharacterService.applyStats(model, stats)
			end
			if e.isBot then
				reg.BotService.refreshJump(e)
			end
		end
		if model then
			model:SetAttribute("Adrenaline", on or nil)
			model:SetAttribute("SunLevel", e.ability == "RisingSun" and HitLogic.sunLevel(extra.enemyPoints) or nil)
		end
	end
end
local refreshBoosts = TeamService.refreshBoosts

-- Rally Cry: the whole team is boosted until `untilT` (shared clock), for every client's HUD too.
function TeamService.rally(team, untilT)
	TeamService.rallyUntil[team] = untilT
	ReplicatedStorage:SetAttribute("RallyUntil_" .. team, untilT)
	refreshBoosts(team)
	task.delay(math.max(0, untilT - Util.now()) + 0.05, function()
		if TeamService.rallyUntil[team] == untilT then
			refreshBoosts(team)
		end
	end)
end

-- The Counter Edge meter (0..100) on the character and the player (the HUD and prediction);
-- her stats scale with it.
function TeamService.setCounter(e, value)
	e.counter = value
	local model = TeamService.getModel(e)
	if model then
		model:SetAttribute("Counter", value)
	end
	if e.player then
		e.player:SetAttribute("Counter", value)
	end
	refreshBoosts(e.team)
end

-- A new set: meters that build over a set start again (Rising Sun follows the score).
function TeamService.resetSetAbilities()
	for _, e in pairs(TeamService.entities) do
		if e.ability == "Counter" then
			TeamService.setCounter(e, 0)
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
		local tier, build = Characters.fromRoster(c, "max")
		e = newEntity(id, c.Name, true, nil, team, tier, c.Ability, build)
		e.charId, e.charName = c.Id, c.Name
	else
		local build = Characters.template(TeamService.botTier, role, Characters.rollHeight(Random.new()))
		e = newEntity(id, pickBotName(), true, nil, team, TeamService.botTier, nil, build)
		e.charName = e.name
	end
	-- the bot wears a friend's avatar and name (the character name shows under it)
	local friend = reg.FriendService.take()
	if friend then
		e.friendId = friend.id
		e.name = friend.name
	end
	e.role = role
	-- it plays at the lobby's bot level even as a lower-tier character (an S+ lobby with S
	-- middles and setters)
	local lvl = Characters.tierIndex(TeamService.botTier)
	if lvl then
		e.skillP = math.max(e.charStats.p, (lvl - 1) / (#Config.Tiers - 1))
	end
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
	TeamService.benched = {}
	usedNames = {}
	usedChars = {}
	reg.FriendService.releaseAll()
end

-- plan = { Home = { Player }, Away = { Player } } (a lobby's sides). Empty spots get bots: a
-- lobby without "fill with bots" only starts full, so bots there only cover someone who left.
function TeamService.assign(size, plan)
	TeamService.clear()
	TeamService.teamSize = size
	local roles = roleList(size)
	for _, team in ipairs(Config.TeamOrder) do
		for _, plr in ipairs((plan and plan[team]) or {}) do
			if plr.Parent and #TeamService.teams[team].order < size and not TeamService.entityForPlayer(plr) then
				local e = playerEntity(plr, team)
				e.role = freeRole(team, roles, e.prefRole)
				TeamService.entities[e.id] = e
				table.insert(TeamService.teams[team].order, e.id)
				TeamService.applyToModel(e)
				TeamService.idle[plr.UserId] = 0
			end
		end
	end
	for _, team in ipairs(Config.TeamOrder) do
		while #TeamService.teams[team].order < size do
			addBot(team, nil, freeRole(team, roles))
		end
	end
	TeamService.inMatch = true
	for _, team in ipairs(Config.TeamOrder) do
		TeamService.rallyUntil[team] = -1
		ReplicatedStorage:SetAttribute("RallyUntil_" .. team, -1)
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
					standInFor = e.standInFor,
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

-- During a timeout a player can switch to another of their characters: same slot, role and
-- stat line, new build and ability. The team's stamina pool is re-read (the timeout refills it).
function TeamService.swapCharacter(plr)
	local e = TeamService.entityForPlayer(plr)
	if not e or not TeamService.inMatch then
		return
	end
	local c, tier, build = reg.ProfileService.characterBuild(plr)
	if not Characters.isTier(tier) then
		return
	end
	e.tier = tier
	e.ability = Characters.isAbility(c.Ability) and c.Ability or nil
	e.build = Characters.sanitize(tier, build)
	e.charStats = Characters.derive(tier, e.build)
	e.charId, e.charName, e.prefRole = c.Id, c.Name, c.Role
	e.liveStats = nil
	e.counter = 0
	e.abilityUntil = -1
	usedChars[c.Id] = true
	reg.ProfileService.applyActive(plr) -- the player's own attributes (the client predicts from them)
	TeamService.applyToModel(e)
	TeamService.fillStamina(e.team) -- re-applies the boosts (Rising Sun, Rally Cry) to the new build
	reg.MatchService.broadcast()
end

-- Human players on court right now.
function TeamService.humanCount()
	local n = 0
	for _, e in pairs(TeamService.entities) do
		if e.player and e.player.Parent then
			n = n + 1
		end
	end
	return n
end

-- Players whose AI is on court and who are still in the server (they can come back).
function TeamService.benchedCount()
	local n = 0
	for userId, botId in pairs(TeamService.benched) do
		if TeamService.entities[botId] and Players:GetPlayerByUserId(userId) then
			n = n + 1
		end
	end
	return n
end

-- An AI that plays `e`'s character (same build, ability, role, slot and stat line) in the
-- player's own avatar.
local function standIn(e, index)
	botCounter = botCounter + 1
	local id = "B_" .. botCounter
	local plr = e.player
	local bot = newEntity(id, e.name .. " (AI)", true, nil, e.team, e.tier, e.ability, e.build)
	bot.charId, bot.charName = e.charId, e.charName
	bot.role = e.role
	bot.stats = e.stats
	bot.counter = e.counter
	bot.abilityUntil, bot.abilityReadyAt = e.abilityUntil, e.abilityReadyAt
	bot.standInFor = plr and plr.UserId
	local hum = plr and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function()
			bot.description = hum:GetAppliedDescription()
		end)
	end
	if not bot.description and plr then
		bot.avatarId = plr.UserId
	end
	TeamService.entities[id] = bot
	local order = TeamService.teams[e.team].order
	table.insert(order, math.min(index or (#order + 1), #order + 1), id)
	reg.BotService.spawn(bot)
	TeamService.applyToModel(bot)
	refreshBoosts(e.team)
	return bot
end

-- Take a player off the court and put their AI in (reason "afk" or "left").
function TeamService.bench(plr, reason)
	local e = TeamService.entityForPlayer(plr)
	if not e or not TeamService.inMatch then
		TeamService.entities["P_" .. tostring(plr.UserId)] = nil
		return
	end
	local root = TeamService.getRoot(e)
	local cf = root and root.CFrame
	local index = removeEntity(e)
	local bot = standIn(e, index)
	if cf and bot.model then
		bot.model:PivotTo(cf)
	end
	local BS = reg.BallService
	if BS.state == "Held" and BS.holderId == e.id then
		BS.hold(bot.id)
		reg.MatchService.serverId = bot.id
	end
	TeamService.benched[plr.UserId] = bot.id
	local char = plr.Character
	if reason == "afk" and char then
		-- off to the side with the spectators
		char:SetAttribute("Role", "Solo")
		char:SetAttribute("Team", nil)
		char:PivotTo(CFrame.new(Config.Court.LobbySpawn + Vector3.new(0, 4, 0)))
	end
	reg.MatchService.announce({ kind = "StandIn", team = e.team, name = e.name, char = e.charName, reason = reason, userId = plr.UserId })
	reg.MatchService.broadcast()
end

-- Ask to (re)take a spot at the next dead ball: a benched player gets their AI's spot back; a
-- lobby member who arrived late takes a bot's.
function TeamService.requestJoin(plr)
	if not TeamService.inMatch or TeamService.entityForPlayer(plr) then
		return
	end
	local lobby = reg.MatchService.lobby
	if not TeamService.benched[plr.UserId] and not reg.LobbyService.isMember(lobby, plr) then
		return
	end
	for _, p in ipairs(TeamService.pendingJoin) do
		if p == plr then
			return
		end
	end
	table.insert(TeamService.pendingJoin, plr)
	Net.get("Lobbies"):FireClient(plr, { notice = "You'll be back in at the next serve." })
end

-- The bot a joining player replaces: their own AI, else a bot on their lobby side (the wing
-- spiker first), else one on the side with the fewest humans.
local function botFor(plr)
	local own = TeamService.benched[plr.UserId]
	if own and TeamService.entities[own] then
		return TeamService.entities[own]
	end
	local lobby = reg.MatchService.lobby
	local want = lobby and Lobbies.teamOf(lobby, plr.UserId)
	local best, bestKey = nil, math.huge
	for _, team in ipairs(Config.TeamOrder) do
		local humans, bot = 0, nil
		for _, e in ipairs(TeamService.members(team)) do
			if e.isBot then
				if not e.standInFor and (not bot or e.role == "WS") then
					bot = e
				end
			else
				humans = humans + 1
			end
		end
		local key = humans + (team == want and -10 or 0)
		if bot and key < bestKey then
			best, bestKey = bot, key
		end
	end
	return best
end

-- Pending joins happen at the start of a rally (a dead ball).
function TeamService.hotJoin()
	if not TeamService.inMatch then
		return
	end
	for i = #TeamService.pendingJoin, 1, -1 do
		local plr = TeamService.pendingJoin[i]
		table.remove(TeamService.pendingJoin, i)
		local bot = plr.Parent and not TeamService.entityForPlayer(plr) and botFor(plr)
		if bot then
			local team, role = bot.team, bot.role
			local index = removeEntity(bot)
			reg.BotService.despawn(bot)
			reg.FriendService.release(bot.friendId)
			local e = playerEntity(plr, team)
			e.role = role
			if bot.standInFor == plr.UserId then
				e.stats = bot.stats -- carry on the same stat line
				e.counter = bot.counter
				e.abilityUntil, e.abilityReadyAt = bot.abilityUntil, bot.abilityReadyAt
			end
			TeamService.entities[e.id] = e
			table.insert(TeamService.teams[team].order, index or 1, e.id)
			TeamService.applyToModel(e)
			refreshBoosts(team)
			TeamService.benched[plr.UserId] = nil
			TeamService.idle[plr.UserId] = 0
		end
	end
end

function TeamService.onPlayerRemoving(plr)
	for i = #TeamService.pendingJoin, 1, -1 do
		if TeamService.pendingJoin[i] == plr then
			table.remove(TeamService.pendingJoin, i)
		end
	end
	TeamService.bench(plr, "left")
	TeamService.benched[plr.UserId] = nil
	TeamService.idle[plr.UserId] = nil
end

-- AFK watch: idle time builds while the ball is live; any input (the client's Activity ping)
-- resets it. Past Config.Afk.Timeout the player's AI takes over.
local AFK_STEP = 0.5
local function afkTick()
	if not TeamService.inMatch then
		return
	end
	local phase = reg.MatchService.phase
	local gone = {}
	for _, e in pairs(TeamService.entities) do
		local plr = e.player
		if plr and plr.Parent then
			local idle, afk = Lobbies.idle(TeamService.idle[plr.UserId] or 0, AFK_STEP, phase, false)
			TeamService.idle[plr.UserId] = idle
			if afk then
				table.insert(gone, plr)
			end
		end
	end
	for _, plr in ipairs(gone) do
		TeamService.bench(plr, "afk")
	end
end

function TeamService.init(r)
	reg = r
	local function setup(plr)
		if not Characters.isTier(plr:GetAttribute("Tier")) then
			plr:SetAttribute("Tier", Config.DefaultTier)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, plr in ipairs(Players:GetPlayers()) do
		setup(plr)
	end
	Players.PlayerRemoving:Connect(TeamService.onPlayerRemoving)
	Net.get("Activity").OnServerEvent:Connect(function(plr)
		TeamService.idle[plr.UserId] = 0
	end)
	task.spawn(function()
		while true do
			task.wait(AFK_STEP)
			local ok, err = pcall(afkTick)
			if not ok then
				warn("[SpikeRush] afk watch: " .. tostring(err))
			end
		end
	end)
	for _, team in ipairs(Config.TeamOrder) do
		publishStamina(team)
	end
	publishTimeouts()
end

return TeamService
