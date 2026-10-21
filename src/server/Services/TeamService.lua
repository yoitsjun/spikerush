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
local Cups = require(Shared.Cups)
local Halloween = require(Shared.Halloween)
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
TeamService.dictateUntil = { Home = -1, Away = -1 } -- the Tyrant's Emperor's Dictate (his team's), until then
TeamService.rallyBoost = { Home = 0, Away = 0 } -- Rally Cry's boost (its caller's, grown by breakthroughs)
TeamService.dictateSteal = { Home = 0, Away = 0 } -- and the Dictate's steal
TeamService.chain = { Home = 0, Away = 0 } -- Chain Reaction: the team's explosions this rally
TeamService.event = nil -- the Halloween Match's run while one plays (MatchService): { hands, ai, ... }

local botCounter = 0
local usedNames = {}
local usedChars = {} -- roster ids already on court this match
local reservedChars = {} -- the host's picks while the bots are being made (TeamService.assign)

-- The active abilities (Config.Abilities[x].Active), in the usual order: each has its own window
-- and cooldown attributes (AbilityUntil_<Name>, AbilityReadyAt_<Name>).
local ACTIVES = {}
for _, name in ipairs(Config.AbilityOrder) do
	if Config.Abilities[name] and Config.Abilities[name].Active then
		table.insert(ACTIVES, name)
	end
end

local function newRecord()
	return { kills = 0, aces = 0, blocks = 0, digs = 0, assists = 0, errors = 0, topKmh = 0 }
end

-- Stacked abilities (the owner, 2026-10-15: the Halloween Match's ability cards "stack" with the
-- character's own): e.ability is the character's own (the primary; a card never changes it),
-- e.extraAbilities the cards' (hand order), e.abilities both in order (Characters.abilityList:
-- primary first, none twice) and e.abilitySet the same as a set. `extras` nil: none.
function TeamService.setAbilities(e, extras)
	e.extraAbilities = extras or {}
	e.abilities = Characters.abilityList(e.ability, e.extraAbilities)
	e.abilitySet = Characters.abilitySet(e.abilities)
end

-- Whether the character plays `name` (its own ability or a card's).
function TeamService.has(e, name)
	return e ~= nil and name ~= nil and (e.ability == name or (e.abilitySet ~= nil and e.abilitySet[name] == true))
end

-- An active's own window (shared clock; -1 when it's off) and cooldown (0 when it's ready).
function TeamService.windowOf(e, name)
	return (e and e.windows and e.windows[name]) or -1
end

function TeamService.readyAtOf(e, name)
	return (e and e.readyAt and e.readyAt[name]) or 0
end

-- The first active ability in the character's order, or nil: the old single "AbilityUntil" and
-- "AbilityReadyAt" attributes follow it (new code reads the per-name ones).
function TeamService.firstActive(e)
	for _, name in ipairs((e and e.abilities) or {}) do
		local def = Config.Abilities[name]
		if def and def.Active then
			return name
		end
	end
	return nil
end

local function newEntity(id, name, isBot, plr, team, tier, ability, build)
	if not Characters.isTier(tier) then
		tier = Config.DefaultTier
	end
	if not Characters.isAbility(ability) then
		ability = nil
	end
	build = Characters.sanitize(tier, build)
	local e = {
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
		windows = {}, -- active ability -> its window's end (shared clock)
		readyAt = {}, -- active ability -> when it's off cooldown (shared clock)
	}
	TeamService.setAbilities(e, nil)
	return e
end

-- The Halloween Match's cards (TeamService.event, set by MatchService for an event run): the Hex
-- string of every card that hits this character (Halloween.hexFor: its own, its side's team cards,
-- the other side's curses), and a player's ability cards, played beside their character's own
-- ability (a stand-in plays them too). The character's own keeps its breakthroughs; a card's
-- plays at +0 (HitLogic.levelOf).
function TeamService.dealHex(e)
	local ev = TeamService.event
	if not ev then
		e.hex = nil
		TeamService.setAbilities(e, nil)
		return
	end
	local u = (e.player and e.player.UserId) or e.standInFor
	e.hex = Halloween.hexFor(Halloween.holders(ev.hands, ev.ai), e.team, u)
	TeamService.setAbilities(e, u and Halloween.abilitiesOf(ev.hands[u]) or nil)
end

-- A player's entity is their selected roster character.
local function playerEntity(plr, team)
	local c, tier, build, brk = reg.ProfileService.characterBuild(plr)
	local e = newEntity("P_" .. tostring(plr.UserId), plr.DisplayName, false, plr, team, tier, c.Ability, build)
	e.breakLevel = brk or 0 -- breakthroughs: its ability grows (Breakthrough.ab)
	e.charId, e.charName, e.prefRole = c.Id, c.Name, c.Role
	usedChars[c.Id] = true
	TeamService.dealHex(e)
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
		if c.Role == want and not usedChars[c.Id] and not reservedChars[c.Id] then
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

-- The intro pose this entity shows (a Pose unlock key, or nil for the default): a player's
-- equipped one, or what its bot model was dressed in.
function TeamService.poseOf(e)
	local attr = Config.Cosmetics.Attribute.Pose
	local value = e and e.player and e.player:GetAttribute(attr)
	if value == nil then
		local m = TeamService.getModel(e)
		value = m and m:GetAttribute(attr)
	end
	return type(value) == "string" and value or nil
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
-- Whose skins a character wears: its player, the player an AI stands in for, or the player whose
-- team pick an AI teammate is (e.skinOwner: "apply a copy to any character" covers your AI
-- teammates too).
function TeamService.skinOwner(e)
	return e.player or (e.standInFor and Players:GetPlayerByUserId(e.standInFor)) or (e.skinOwner and e.skinOwner.Parent and e.skinOwner) or nil
end

-- A player switched a skin on or off (or applied one) mid-match: every character on court that wears
-- their skins shows it now.
function TeamService.refreshSkins(plr)
	for _, e in pairs(TeamService.entities) do
		if TeamService.skinOwner(e) == plr then
			local model = TeamService.getModel(e)
			if model then
				model:SetAttribute("Skin", e.charId and reg.ProfileService.skinFor(plr, e.charId) or nil)
			end
		end
	end
end

function TeamService.applyToModel(e)
	local model = TeamService.getModel(e)
	if not model then
		return
	end
	model:SetAttribute("Team", e.team)
	model:SetAttribute("Role", e.role)
	model:SetAttribute("Ability", e.ability or "")
	model:SetAttribute("Abilities", Characters.encodeAbilities(e.abilities)) -- (the cards' too, primary first)
	model:SetAttribute("CharName", e.charName or e.name)
	model:SetAttribute("EntityId", e.id)
	-- whose Roblox avatar it wears (a player, the player an AI stands in for, a bot's friend)
	model:SetAttribute("AvatarUserId", e.player and e.player.UserId or e.avatarId or e.friendId or 0)
	Characters.writeAttributes(model, e.tier, e.build)
	if e.player then
		-- the local client predicts its own hits from these
		Characters.writeAttributes(e.player, e.tier, e.build)
	end
	reg.CharacterService.applyStats(model, e.liveStats or e.charStats)
	-- the Halloween Match's cards that hit it (both sides read them: HitLogic's ctx.hex), and every
	-- ability a player plays (the client predicts its own touches from the player's Ability, its own,
	-- and Abilities, the cards' too)
	model:SetAttribute("Hex", e.hex ~= nil and e.hex ~= "" and e.hex or nil)
	if e.player then
		e.player:SetAttribute("Hex", e.hex ~= nil and e.hex ~= "" and e.hex or nil)
		e.player:SetAttribute("Ability", e.ability or "")
		e.player:SetAttribute("Abilities", Characters.encodeAbilities(e.abilities))
	end
	-- a skin its player has on for this character (the Reaper: the server's word, so nobody
	-- draws one they don't have)
	local skinOwner = TeamService.skinOwner(e)
	model:SetAttribute("Skin", skinOwner and e.charId and reg.ProfileService.skinFor(skinOwner, e.charId) or nil)
	-- ability state for the HUDs and effects (a new entity starts with it ready), for every ability
	-- it plays (a card's too)
	local has = TeamService.has
	local first = TeamService.firstActive(e)
	for _, inst in ipairs({ model, e.player or false }) do
		if inst then
			inst:SetAttribute("Counter", has(e, "Counter") and (e.counter or 0) or nil)
			inst:SetAttribute("Lift", has(e, "Skyward") and HitLogic.skyLift(e.lift) or nil)
			if has(e, "Skyward") and e.peakM then
				-- (a stand-in's new body shows the peak its player had)
				inst:SetAttribute("PeakM", e.peakM)
				inst:SetAttribute("PeakY", e.peakY)
				inst:SetAttribute("PeakZ", e.peakZ)
			else
				-- (a peak left on a player who played Seora before must not show)
				inst:SetAttribute("PeakM", nil)
				inst:SetAttribute("PeakY", nil)
				inst:SetAttribute("PeakZ", nil)
			end
			inst:SetAttribute("FirstStrikeUsed", has(e, "Feral") and e.firstStrikeUsed or nil)
			inst:SetAttribute("CoronaStacks", has(e, "Corona") and (e.coronaStacks or 0) or nil)
			inst:SetAttribute("IronLives", has(e, "Ironclad") and HitLogic.ironLives(e.ironLives) or nil)
			inst:SetAttribute("Static", has(e, "Thunder") and (e.static or 0) or nil)
			inst:SetAttribute("Intimidation", has(e, "Ironclad") and (e.intimidation or 0) or nil)
			inst:SetAttribute("IronCracks", has(e, "Ironclad") and (e.ironCracks or 0) or nil)
			inst:SetAttribute("Grounded", e.grounded or nil)
			inst:SetAttribute("SunshineUntil", has(e, "Sunshine") and (e.sunUntil or -1) or nil)
			inst:SetAttribute("Break", (e.breakLevel or 0) > 0 and e.breakLevel or nil) -- (its own ability's)
			-- each active's own window and cooldown (nil for one it doesn't play: none left from an
			-- earlier match's card); the old single pair follows its first active
			for _, name in ipairs(ACTIVES) do
				local held = has(e, name)
				inst:SetAttribute("AbilityUntil_" .. name, held and TeamService.windowOf(e, name) or nil)
				inst:SetAttribute("AbilityReadyAt_" .. name, held and TeamService.readyAtOf(e, name) or nil)
			end
			inst:SetAttribute("AbilityUntil", first and TeamService.windowOf(e, first) or -1)
			inst:SetAttribute("AbilityReadyAt", first and TeamService.readyAtOf(e, first) or 0)
		end
	end
end

------------------------------------------------------------------------------------------
-- Stamina (a team guard meter for heavy receives) and stat boosts
------------------------------------------------------------------------------------------

-- What a character's stats depend on besides the team's stamina (HitLogic.effectiveStats'
-- `extra`): every ability it plays (its own and its cards'), the other team's points this set
-- (Rising Sun), the Counter Edge meter, whether the AI plays it (Feral Leap) and its own team's
-- Rally Cry.
function TeamService.boostCtx(e, t)
	local scores = reg.MatchService.scores or {}
	local now = t or Util.now()
	return {
		ability = e.ability,
		abilities = e.abilitySet,
		abilityList = e.abilities,
		enemyPoints = scores[Court.other(e.team)] or 0,
		counter = e.counter or 0,
		lift = e.lift,
		auto = e.isBot or nil,
		teamBoost = (TeamService.rallyUntil[e.team] or -1) >= now and TeamService.rallyBoost[e.team] or nil,
		dictate = (TeamService.dictateUntil[e.team] or -1) >= now or nil,
		dictated = (TeamService.dictateUntil[Court.other(e.team)] or -1) >= now and TeamService.dictateSteal[Court.other(e.team)] or nil,
		grounded = e.grounded or nil,
		sunOn = TeamService.has(e, "Sunshine") and (e.sunUntil or -1) >= now or nil,
		coronaOn = TeamService.has(e, "Corona") and TeamService.windowOf(e, "Corona") >= now or nil,
		coronaStacks = TeamService.has(e, "Corona") and (e.coronaStacks or 0) or nil,
		squallOn = TeamService.has(e, "Squall") and TeamService.windowOf(e, "Squall") >= now or nil,
		bloodlust = TeamService.has(e, "Feral") and TeamService.windowOf(e, "Feral") >= now or nil,
		breakLevel = e.breakLevel, -- (its own ability's)
		mods = Cups.statMods(ReplicatedStorage:GetAttribute("CupMods")), -- a tournament's modifiers
		hex = Halloween.effects(e.hex), -- the Halloween Match's cards that hit it
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
			model:SetAttribute("SunLevel", TeamService.has(e, "RisingSun") and HitLogic.sunLevel(extra.enemyPoints) or nil)
		end
	end
end
local refreshBoosts = TeamService.refreshBoosts

-- Rally Cry: the whole team is boosted until `untilT` (shared clock), for every client's HUD too.
-- (Two on one team, a card's and a teammate's own: the longer boost stands.)
function TeamService.rally(team, untilT, boost)
	local active = (TeamService.rallyUntil[team] or -1) >= Util.now()
	untilT = math.max(untilT, TeamService.rallyUntil[team] or -1)
	TeamService.rallyUntil[team] = untilT
	-- (two at once: the bigger boost)
	TeamService.rallyBoost[team] = math.max(boost or Config.Abilities.RallyCry.Boost, active and TeamService.rallyBoost[team] or 0)
	ReplicatedStorage:SetAttribute("RallyBoost_" .. team, TeamService.rallyBoost[team])
	ReplicatedStorage:SetAttribute("RallyUntil_" .. team, untilT)
	refreshBoosts(team)
	task.delay(math.max(0, untilT - Util.now()) + 0.05, function()
		if TeamService.rallyUntil[team] == untilT then
			refreshBoosts(team)
		end
	end)
end

-- The Tyrant's Emperor's Dictate: `team` (his) steals from the other until `untilT` (shared clock),
-- for every client's prediction and HUD too. Both teams' stats follow it now and when it ends.
function TeamService.dictate(team, untilT, steal)
	untilT = math.max(untilT, TeamService.dictateUntil[team] or -1)
	TeamService.dictateUntil[team] = untilT
	TeamService.dictateSteal[team] = steal or Config.Abilities.Tyrant.Steal
	ReplicatedStorage:SetAttribute("DictateSteal_" .. team, TeamService.dictateSteal[team])
	ReplicatedStorage:SetAttribute("DictateUntil_" .. team, untilT)
	refreshBoosts(team)
	refreshBoosts(Court.other(team))
	task.delay(math.max(0, untilT - Util.now()) + 0.05, function()
		if TeamService.dictateUntil[team] == untilT then
			refreshBoosts(team)
			refreshBoosts(Court.other(team))
		end
	end)
end

-- Sovereign's Guard: `e` is grounded (less Jump and Attack) until its next attack, or not.
function TeamService.setGrounded(e, on)
	on = on or nil
	if e.grounded == on then
		return
	end
	e.grounded = on
	for _, inst in ipairs({ TeamService.getModel(e) or false, e.player or false }) do
		if inst then
			inst:SetAttribute("Grounded", on)
		end
	end
	refreshBoosts(e.team)
end

-- Sunshine: lit until `untilT` (shared clock; -1 off), for every client's prediction and effects.
function TeamService.setSunshine(e, untilT)
	e.sunUntil = untilT
	for _, inst in ipairs({ TeamService.getModel(e) or false, e.player or false }) do
		if inst then
			inst:SetAttribute("SunshineUntil", untilT)
		end
	end
	refreshBoosts(e.team)
	task.delay(math.max(0, untilT - Util.now()) + 0.05, function()
		if e.sunUntil == untilT then
			refreshBoosts(e.team)
		end
	end)
end

-- Corona: his flare is on until `untilT` and he has used it `stacks` times (the penalty while
-- it's off); his stats follow it now and again when the window ends.
function TeamService.setCorona(e, untilT, stacks)
	e.coronaStacks = stacks
	for _, inst in ipairs({ TeamService.getModel(e) or false, e.player or false }) do
		if inst then
			inst:SetAttribute("CoronaStacks", stacks)
		end
	end
	refreshBoosts(e.team)
	task.delay(math.max(0, untilT - Util.now()) + 0.05, function()
		if TeamService.windowOf(e, "Corona") == untilT then
			refreshBoosts(e.team)
		end
	end)
end

-- An active ability that boosts its own stats (Squall: `name`) is on until `untilT`: the stats
-- follow it now and again when its window ends.
function TeamService.boostWindow(e, untilT, name)
	refreshBoosts(e.team)
	task.delay(math.max(0, untilT - Util.now()) + 0.05, function()
		if name == nil or TeamService.windowOf(e, name) == untilT then
			refreshBoosts(e.team)
		end
	end)
end

-- Thunder's Static Charge: his thunder spikes this rally (0..StaticMax), for every client's HUD.
function TeamService.setStatic(e, n)
	e.static = n
	for _, inst in ipairs({ TeamService.getModel(e) or false, e.player or false }) do
		if inst then
			inst:SetAttribute("Static", n)
		end
	end
end

-- A new rally: every Thunder's Static Charge is spent.
function TeamService.resetStatic()
	for _, e in pairs(TeamService.entities) do
		if TeamService.has(e, "Thunder") and (e.static or 0) > 0 then
			TeamService.setStatic(e, 0)
		end
	end
end

-- Ironclad: his shields (0..Lives; none: awakened), the Intimidation meter (0..100) and the
-- cracks in his current shield (Cracks; none when left out), for every client's HUD and effects.
function TeamService.setIron(e, lives, meter, cracks)
	e.ironLives = HitLogic.ironLives(lives)
	e.intimidation = meter
	e.ironCracks = cracks or 0
	for _, inst in ipairs({ TeamService.getModel(e) or false, e.player or false }) do
		if inst then
			inst:SetAttribute("IronLives", e.ironLives)
			inst:SetAttribute("Intimidation", meter)
			inst:SetAttribute("IronCracks", e.ironCracks)
		end
	end
end

-- A timeout (or a substitution) clears every Corona's penalty.
function TeamService.clearCorona()
	for _, e in pairs(TeamService.entities) do
		if TeamService.has(e, "Corona") and (e.coronaStacks or 0) > 0 then
			e.coronaStacks = 0
			for _, inst in ipairs({ TeamService.getModel(e) or false, e.player or false }) do
				if inst then
					inst:SetAttribute("CoronaStacks", 0)
				end
			end
		end
	end
	for _, team in ipairs(Config.TeamOrder) do
		refreshBoosts(team)
	end
end

-- Chain Reaction: a team's explosions this rally (0 at every serve), for everyone's prediction.
function TeamService.setChain(team, n)
	TeamService.chain[team] = n
	ReplicatedStorage:SetAttribute("Chain_" .. team, n)
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

-- Skyward's lift (metres on her hitting point) on the character and the player (the HUD, her
-- effects and prediction); her real jump follows it.
function TeamService.setLift(e, value)
	e.lift = HitLogic.skyLift(value)
	local model = TeamService.getModel(e)
	if model then
		model:SetAttribute("Lift", e.lift)
	end
	if e.player then
		e.player:SetAttribute("Lift", e.lift)
	end
	refreshBoosts(e.team)
end

-- Skyward: where her highest spike this set was met (metres, and the ball's world height and z),
-- for the marker that stays there; nil clears it.
function TeamService.setPeak(e, m, y, z)
	e.peakM = m
	e.peakY, e.peakZ = m and y or nil, m and z or nil -- (a stand-in's new body shows it too)
	local model = TeamService.getModel(e)
	for _, inst in ipairs({ model or false, e.player or false }) do
		if inst then
			inst:SetAttribute("PeakM", m)
			inst:SetAttribute("PeakY", m and y or nil)
			inst:SetAttribute("PeakZ", m and z or nil)
		end
	end
end

-- A new set: meters that build over a set start again (Rising Sun follows the score), every one
-- the character plays (a card's too).
function TeamService.resetSetAbilities()
	for _, e in pairs(TeamService.entities) do
		if TeamService.has(e, "Counter") then
			TeamService.setCounter(e, 0)
		end
		if TeamService.has(e, "Skyward") then
			TeamService.setLift(e, nil) -- back to the bottom of her climb
			TeamService.setPeak(e, nil)
		end
		if TeamService.has(e, "Ironclad") then
			TeamService.setIron(e, Config.Abilities.Ironclad.StartLives, 0) -- a new set: StartLives shields, the meter empty
		end
		if e.grounded then
			TeamService.setGrounded(e, false)
		end
		if TeamService.has(e, "Sunshine") and (e.sunUntil or -1) >= 0 then
			TeamService.setSunshine(e, -1)
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

-- A team's pool is the average of its players' pools (Defense raises it), times a tournament's
-- stamina modifiers (Cups: every team's, and the bot team's, which is Away in a cup) and the
-- Halloween Match's pool cards (the average over the team of what hits each).
local function poolFor(team)
	local sum, n, cards = 0, 0, 0
	for _, e in ipairs(TeamService.members(team)) do
		sum = sum + e.charStats.StaminaPool
		n = n + 1
		local fx = Halloween.effects(e.hex)
		cards = cards + (fx and fx.pool or 1)
	end
	if n == 0 then
		return 100
	end
	local mods = ReplicatedStorage:GetAttribute("CupMods")
	local f = Cups.factor(mods, "Stamina") * (team == "Away" and Cups.factor(mods, "OppStamina") or 1)
	return sum / n * f * cards / n
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

-- Each team's timeouts for a new set: `n` (the match's rules) or the usual Timeout.PerSet.
function TeamService.resetTimeouts(n)
	for _, team in ipairs(Config.TeamOrder) do
		TeamService.timeouts[team] = n or Config.Timeout.PerSet
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

-- `captain`: the player whose team this bot fills; it plays their pick for the role (their own
-- build of that character) when they made one, else a roster character near the bot level.
-- `pickId`: the custom lobby host's pick for this spot (Lobbies.botPicks), played maxed whether
-- or not anyone owns it; it comes first.
local function addBot(team, index, role, captain, pickId)
	botCounter = botCounter + 1
	local id = "B_" .. botCounter
	role = role or "WS"
	local e
	local c, tier, build, brk = nil, nil, nil, 0
	local picked = pickId and Roster.get(pickId)
	if picked and not usedChars[picked.Id] then
		c = picked
		tier, build = Characters.fromRoster(c, "max")
	end
	local fromPick = false
	if captain and not c then
		c, tier, build, brk = reg.ProfileService.teamPick(captain, TeamService.teamSize, role)
		if c and (usedChars[c.Id] or reservedChars[c.Id]) then
			c = nil -- already on the court (the captain plays it themselves), or the host's pick
		end
		fromPick = c ~= nil
	end
	if not c then
		c = rosterFor(TeamService.botTier, role)
		if c then
			tier, build = Characters.fromRoster(c, "max")
		end
	end
	if c then
		usedChars[c.Id] = true
		e = newEntity(id, c.Name, true, nil, team, tier, c.Ability, build)
		e.charId, e.charName = c.Id, c.Name
		e.breakLevel = brk or 0 -- (the captain's own build of it, breakthroughs too)
		e.skinOwner = fromPick and captain or nil -- (and the captain's skin on it)
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
	TeamService.dealHex(e) -- (the Halloween Match: its side's team cards, the other side's curses)
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

local roleList = Court.roles

function TeamService.clear()
	for _, e in pairs(TeamService.entities) do
		if e.isBot then
			reg.BotService.despawn(e)
		end
	end
	-- the match's abilities end with it (the Halloween Match's cards too): outside a match a player
	-- plays only their character's own (its Ability, which a card never replaced)
	for _, plr in ipairs(Players:GetPlayers()) do
		for _, inst in ipairs({ plr, plr.Character or false }) do
			if inst then
				inst:SetAttribute("Hex", nil)
				inst:SetAttribute("Abilities", nil)
				for _, name in ipairs(ACTIVES) do
					inst:SetAttribute("AbilityUntil_" .. name, nil)
					inst:SetAttribute("AbilityReadyAt_" .. name, nil)
				end
			end
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
function TeamService.assign(size, plan, picks)
	TeamService.clear()
	-- the host's picks for the bot spots: no other bot takes these characters first
	reservedChars = {}
	for _, team in ipairs(Config.TeamOrder) do
		for _, id in ipairs((picks and picks[team]) or {}) do
			reservedChars[id] = true
		end
	end
	TeamService.teamSize = size
	local roles = roleList(size)
	local captains = {} -- the first player on each team: bots fill it with their picks
	for _, team in ipairs(Config.TeamOrder) do
		for _, plr in ipairs((plan and plan[team]) or {}) do
			if plr.Parent and #TeamService.teams[team].order < size and not TeamService.entityForPlayer(plr) then
				captains[team] = captains[team] or plr
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
			local role = freeRole(team, roles)
			addBot(team, nil, role, captains[team], Lobbies.pickFor((picks and picks[team]) or {}, role, usedChars))
		end
	end
	reservedChars = {}
	TeamService.inMatch = true
	for _, team in ipairs(Config.TeamOrder) do
		TeamService.rallyUntil[team] = -1
		ReplicatedStorage:SetAttribute("RallyUntil_" .. team, -1)
		TeamService.dictateUntil[team] = -1
		ReplicatedStorage:SetAttribute("DictateUntil_" .. team, -1)
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

-- Why a bot's body can't be seen, or nil when it's fine: never built, gone from the world, its root
-- part or humanoid lost (a rig that fell out of the world keeps its Model with the parts destroyed:
-- the old check, `model.Parent`, passed it, and the community still saw 2v3s: "the issue with bots
-- not appearing still exists"), dead, or somewhere off the map.
local function bodyProblem(e)
	if e.spawningSince and os.clock() - e.spawningSince < 15 then
		return nil -- still building (BotService.spawn yields): a second build made a clone
	end
	local m = e.model
	if not m or not m.Parent or not m:IsDescendantOf(workspace) then
		return "no model"
	end
	local root = m:FindFirstChild("HumanoidRootPart")
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not root or root.Parent ~= m then
		return "no root part"
	end
	if not hum or hum.Health <= 0 then
		return "no living humanoid"
	end
	local p = root.Position
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then
		return "position NaN"
	end
	if p.Y < -30 or p.Y > 250 or math.abs(p.Z) > 160 or math.abs(p.X) > 160 then
		return string.format("off the map (%.0f, %.0f, %.0f)", p.X, p.Y, p.Z)
	end
	return nil
end

-- Every bot on court has a body: one that never built, or was lost (bodyProblem), gets a new one
-- where its spot is (at each serve, and every couple of seconds in play: bodyWatch). One at a time:
-- building a rig yields.
local fixingBodies = false
function TeamService.ensureBodies()
	if fixingBodies then
		return
	end
	fixingBodies = true
	local ok, err = pcall(function()
		local swept = reg.BotService.sweepOrphans(TeamService.entities)
		if swept > 0 then
			warn(string.format("[SpikeRush] removed %d stray bot bodies", swept))
		end
		for _, e in pairs(TeamService.entities) do
			local why = e.isBot and not e.despawned and bodyProblem(e)
			if why and TeamService.entities[e.id] == e then
				warn(string.format("[SpikeRush] %s's body rebuilt (%s)", tostring(e.name), why))
				if reg.BotService.rebuild(e) and TeamService.entities[e.id] == e then
					TeamService.applyToModel(e)
					refreshBoosts(e.team)
				end
			end
		end
	end)
	fixingBodies = false
	if not ok then
		warn("[SpikeRush] ensureBodies: " .. tostring(err))
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
					ability = e.ability, -- its own
					abilities = e.abilities, -- every one it plays, its own first (the cards' after)
					char = e.charName,
					role = e.role,
					height = e.build.Height,
					rot = i,
					standInFor = e.standInFor,
					pose = TeamService.poseOf(e),
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
		-- a character that respawns mid-match (a reset, a reload) comes in at the lobby spawn, behind
		-- one end line: on the other team's side it was stuck there behind the net until the next
		-- serve (the community: "sometimes the enemy is on the player side"). Back to its own side
		if TeamService.inMatch then
			local side = Court.sideOf(e.team)
			local spot = Court.formationSpot("Receive", e.role, side)
			task.defer(function()
				if char.Parent and TeamService.entityForPlayer(plr) == e then
					char:PivotTo(Court.facing(spot + Vector3.new(0, TeamService.groundY(e) + 0.2, 0), side))
				end
			end)
		end
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
	local c, tier, build, brk = reg.ProfileService.characterBuild(plr)
	if not Characters.isTier(tier) then
		return
	end
	e.breakLevel = brk or 0
	e.tier = tier
	e.ability = Characters.isAbility(c.Ability) and c.Ability or nil
	e.build = Characters.sanitize(tier, build)
	e.charStats = Characters.derive(tier, e.build)
	e.charId, e.charName, e.prefRole = c.Id, c.Name, c.Role
	-- the role goes with the character: trade spots with the AI playing it (Lobbies.roleTrade)
	local holder = TeamService.byRole(e.team, c.Role)
	local trade = Lobbies.roleTrade(e.role, c.Role, holder and (holder.player and "player" or "bot") or nil)
	local note = nil
	if trade == "swap" then
		holder.role, e.role = e.role, c.Role
		TeamService.applyToModel(holder)
		note = "You're playing " .. Config.Roles[c.Role].Name .. " now."
	elseif trade == "taken" then
		note = string.format("%s is playing %s, so you stay %s.", holder.name, Config.Roles[c.Role].Name, Config.Roles[e.role] and Config.Roles[e.role].Name or e.role)
	end
	e.liveStats = nil
	e.counter = 0
	e.windows = {} -- every active's window off (the cooldowns stay)
	e.coronaStacks = 0 -- a substitution clears Corona's penalty
	usedChars[c.Id] = true
	reg.ProfileService.applyActive(plr) -- the player's own attributes (the client predicts from them)
	TeamService.dealHex(e) -- (the Halloween Match: the ability cards stack on the new character's own)
	TeamService.applyToModel(e)
	TeamService.fillStamina(e.team) -- re-applies the boosts (Rising Sun, Rally Cry) to the new build
	reg.MatchService.broadcast()
	return note
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

-- Every ability's meters from one entity to another (a stand-in and back): each ability it plays
-- keeps its own.
local function carryAbilityState(to, from)
	to.counter = from.counter
	to.firstStrikeUsed = from.firstStrikeUsed
	to.lift = from.lift
	to.peakM, to.peakY, to.peakZ = from.peakM, from.peakY, from.peakZ
	to.static = from.static
	to.coronaStacks = from.coronaStacks
	to.ironLives, to.ironCracks, to.intimidation = from.ironLives, from.ironCracks, from.intimidation
	to.grounded = from.grounded
	to.sunUntil = from.sunUntil
end

-- An AI that plays `e`'s character (same build, abilities, role, slot and stat line) in the
-- player's own avatar.
local function standIn(e, index)
	botCounter = botCounter + 1
	local id = "B_" .. botCounter
	local plr = e.player
	local bot = newEntity(id, e.name .. " (AI)", true, nil, e.team, e.tier, e.ability, e.build)
	TeamService.setAbilities(bot, e.extraAbilities) -- (the Halloween Match's ability cards go with the character)
	bot.charId, bot.charName = e.charId, e.charName
	bot.role = e.role
	bot.stats = e.stats
	bot.windows, bot.readyAt = table.clone(e.windows or {}), table.clone(e.readyAt or {})
	carryAbilityState(bot, e)
	bot.standInFor = plr and plr.UserId
	bot.hex = e.hex -- (and the cards that hit it)
	bot.breakLevel = e.breakLevel -- (and its breakthroughs: its own ability's growth and cooldown)
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
	if plr then
		-- benched before the rig is built (spawn yields): with no human left on court, the
		-- match's abort check would otherwise end the match before the player could rejoin
		TeamService.benched[plr.UserId] = id
	end
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
	if TeamService.entities[bot.id] ~= bot then
		-- the match ended, or the player rejoined, while the stand-in's rig was being built
		return
	end
	if cf and bot.model then
		bot.model:PivotTo(cf)
	end
	local BS = reg.BallService
	if BS.state == "Held" and BS.holderId == e.id then
		BS.hold(bot.id)
		reg.MatchService.serverId = bot.id
	end
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
				e.windows, e.readyAt = bot.windows or {}, bot.readyAt or {}
				carryAbilityState(e, bot) -- (the ability cards come again from dealHex)
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
	if not TeamService.inMatch or reg.MatchService.practice then
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
	-- Nobody stays on the wrong side of the net (the community, 2026-10-21: "my character can stuck
	-- in net", "this guy was on the complete wrong team"): the net is a wall (ArenaBuilder's
	-- NetBarrier), so a body that got past its middle (pushed through, or over it) was held on the
	-- other team's side, pinned to the net. Past it for a moment, it's put back just on its own side
	local wrongSince = {}
	task.spawn(function()
		while true do
			task.wait(0.2)
			local ok, err = pcall(function()
				local phase = reg.MatchService and reg.MatchService.phase
				if not TeamService.inMatch or (phase ~= "Rally" and phase ~= "PreServe" and phase ~= "Serving" and phase ~= "Point") then
					table.clear(wrongSince)
					return
				end
				local now = os.clock()
				for id, e in pairs(TeamService.entities) do
					local m = TeamService.getModel(e)
					local root = m and m:FindFirstChild("HumanoidRootPart")
					local side = e.team and Court.sideOf(e.team)
					if root and side and root.Position.Z * side < -0.1 then
						wrongSince[id] = wrongSince[id] or now
						if now - wrongSince[id] > 0.4 then
							wrongSince[id] = nil
							local p = root.Position
							m:PivotTo(Court.facing(Vector3.new(p.X, math.max(p.Y, TeamService.groundY(e) + 0.2), side * 1.6), side))
							local v = root.AssemblyLinearVelocity
							root.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, 0), 0)
							warn(string.format("[SpikeRush] %s was past the net: back on its side", tostring(e.name)))
						end
					else
						wrongSince[id] = nil
					end
				end
			end)
			if not ok then
				warn("[SpikeRush] net watch: " .. tostring(err))
			end
		end
	end)
	-- a body lost mid-rally comes back within a couple of seconds, not at the next serve
	task.spawn(function()
		while true do
			task.wait(2)
			if TeamService.inMatch then
				TeamService.ensureBodies()
			end
		end
	end)
	for _, team in ipairs(Config.TeamOrder) do
		publishStamina(team)
	end
	publishTimeouts()
end

return TeamService
