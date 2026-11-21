-- The Winter collab's rules (Config.Winter; the owner, 2026-11-15: a Christmas event with Jaja's
-- Volleyball Evolved: "event snowflakes, quests, and a new event gamemode... an exclusive
-- character that can only be recruited from the event currencies alongside christmas items").
-- Shaped after The Spike Cross's collab event: its collab players come only from the event's own
-- coins, earned from event matches (the day's first clear), daily quests, missions and attendance;
-- one gauge guarantees the character; an exchange shop sells the rest. Pure and shared: the server
-- counts and pays, the client draws the same answers; covered by the sims.
--
-- A player's event save, profile.winter (Winter.clean):
--   snow      Snowflakes held
--   gauge     recruits since Joker last came (at Banner.Pity the next one is him)
--   day       the event day `cleared` is for; cleared = { [difficulty] = true } that day
--   quests    { day, stats = { [stat] = n }, claimed = { [quest key] = true } }: a new day starts it again
--   missions  { stats = { [stat] = n }, claimed = { [mission key] = true } }: the whole event
--   login     { day (the last one paid), count (days paid) }
--   bought    { [shop key] = n }
--   pass      the Winter Pass: { xp, premium (bought), free = { [tier] = true }, prem = { [tier] = true } }
--   advent    the advent calendar's doors opened, one bit each (door 1 is 1, door 2 is 2, door 3 is 4...)
--   points    Winter Match wins by Config.Winter.Board.Points (the event's leaderboard)
--   boardPaid true once the leaderboard's card was settled after the event (given or not placed)
--   preview   true on a save made in a Studio preview before the launch (a live server drops it)

local Config = require(script.Parent.Config)
local Roster = require(script.Parent.Roster)
local Spins = require(script.Parent.Spins)
local Mutators = require(script.Parent.Mutators)

local Winter = {}
local W = Config.Winter

local DIFF, QUEST, MISSION, SHOP = {}, {}, {}, {}
for _, d in ipairs(W.Difficulties) do
	DIFF[d.Key] = d
end
for _, q in ipairs(W.Quests.Pool) do
	QUEST[q.Key] = q
end
for _, m in ipairs(W.Missions) do
	MISSION[m.Key] = m
end
for _, s in ipairs(W.Shop) do
	SHOP[s.Key] = s
end

local function whole(n)
	n = tonumber(n)
	if not n or n ~= n or n < 0 then
		return 0
	end
	return math.floor(math.min(n, 1e9))
end

------------------------------------------------------------------------------------------
-- when
------------------------------------------------------------------------------------------

-- In Studio the event runs whatever Enabled and the dates say (Config.Winter.StudioPreview), to
-- build and test it; a live server never does. The testers' game (Config.Developers.TestGame)
-- runs it too, like Studio (the owner, 2026-11-18: "port all the christmas changes into the test server").
local inStudio = game ~= nil and (game:GetService("RunService"):IsStudio() or game.GameId == Config.Developers.TestGame)
Winter.preview = W.StudioPreview == true and inStudio

-- Open: switched on, and between Starts and Ends (or a Studio preview).
function Winter.active(now)
	now = tonumber(now) or os.time()
	return Winter.preview or (W.Enabled == true and now >= W.Starts and now < W.Ends)
end

-- A Studio preview ahead of the launch: what's earned in one is marked (Winter.clean) and thrown
-- away by a live server, so testing leaves nothing behind.
function Winter.previewing(now)
	now = tonumber(now) or os.time()
	return Winter.preview and now < W.Starts
end

function Winter.secondsLeft(now)
	now = tonumber(now) or os.time()
	return math.max(0, W.Ends - math.floor(now))
end

-- The day `now` falls on (days turn with DayOffset, midnight in Chicago, like the daily missions).
function Winter.day(now)
	return math.floor(((tonumber(now) or 0) + W.DayOffset) / 86400)
end

-- The seconds until the event's day turns (the daily quests and first clears start again).
function Winter.dayLeft(now)
	return 86400 - math.floor(((tonumber(now) or 0) + W.DayOffset) % 86400)
end

function Winter.difficulty(key)
	return type(key) == "string" and DIFF[key] or nil
end

------------------------------------------------------------------------------------------
-- the save
------------------------------------------------------------------------------------------

local function cleanStats(src)
	local out = {}
	if type(src) == "table" then
		for k, v in pairs(src) do
			if type(k) == "string" and #k <= 24 and whole(v) > 0 then
				out[k] = whole(v)
			end
		end
	end
	return out
end

function Winter.clean(data, now)
	local out = { snow = 0, gauge = 0, day = 0, cleared = {}, quests = { day = 0, stats = {}, claimed = {} }, missions = { stats = {}, claimed = {} }, login = { day = 0, count = 0 }, bought = {}, pass = { xp = 0, premium = false, free = {}, prem = {} }, advent = 0, points = 0 }
	-- (a Studio preview's save: marked, and a live server starts it again)
	local previewing = Winter.previewing(now)
	out.preview = previewing or nil
	if type(data) ~= "table" or (data.preview == true and not previewing) then
		return out
	end
	out.snow = math.min(whole(data.snow), W.Snow.Max)
	out.gauge = math.min(whole(data.gauge), W.Banner.Pity - 1)
	out.day = whole(data.day)
	if type(data.cleared) == "table" then
		for k, v in pairs(data.cleared) do
			if v == true and DIFF[k] then
				out.cleared[k] = true
			end
		end
	end
	if type(data.quests) == "table" then
		out.quests.day = whole(data.quests.day)
		out.quests.stats = cleanStats(data.quests.stats)
		if type(data.quests.claimed) == "table" then
			for k, v in pairs(data.quests.claimed) do
				if v == true and QUEST[k] then
					out.quests.claimed[k] = true
				end
			end
		end
	end
	if type(data.missions) == "table" then
		out.missions.stats = cleanStats(data.missions.stats)
		if type(data.missions.claimed) == "table" then
			for k, v in pairs(data.missions.claimed) do
				if v == true and MISSION[k] then
					out.missions.claimed[k] = true
				end
			end
		end
	end
	if type(data.login) == "table" then
		out.login.day = whole(data.login.day)
		out.login.count = math.min(whole(data.login.count), 1000)
	end
	if type(data.bought) == "table" then
		for _, row in ipairs(W.Shop) do
			local n = whole(data.bought[row.Key])
			if n > 0 then
				out.bought[row.Key] = math.min(n, 100000)
			end
		end
	end
	out.advent = math.min(whole(data.advent), 2 ^ W.Advent.Doors - 1)
	out.points = math.min(whole(data.points), 1e7)
	out.boardPaid = data.boardPaid == true or nil
	if type(data.pass) == "table" then
		local P = out.pass
		P.xp = math.min(whole(data.pass.xp), W.Pass.Tiers * W.Pass.TierXP)
		P.premium = data.pass.premium == true
		for _, track in ipairs({ "free", "prem" }) do
			if type(data.pass[track]) == "table" then
				for k, v in pairs(data.pass[track]) do
					local t = tonumber(k)
					if v == true and t and t >= 1 and t <= W.Pass.Tiers and t == math.floor(t) then
						P[track][t] = true
					end
				end
			end
		end
	end
	return out
end

-- Snowflakes in: `mul` is the 2x Event Currency pass or boost (the caller's), never below 1.
function Winter.addSnow(ev, n, mul)
	local add = whole(whole(n) * math.max(1, tonumber(mul) or 1) + 0.5)
	ev.snow = math.min(whole(ev.snow) + add, W.Snow.Max)
	return add
end

------------------------------------------------------------------------------------------
-- the event match's pay
------------------------------------------------------------------------------------------

-- What a finished event match pays in Snowflakes: First for the day's first clear of that
-- difficulty (marked when `mark`), Repeat for later clears, Loss for a loss.
function Winter.matchPay(ev, diffKey, won, day, mark)
	local d = DIFF[diffKey or ""]
	if not d then
		return 0, false
	end
	day = whole(day)
	if ev.day ~= day then
		ev.day = day
		ev.cleared = {}
	end
	if not won then
		return d.Loss, false
	end
	local first = not ev.cleared[d.Key]
	if mark then
		ev.cleared[d.Key] = true
	end
	return first and d.First or d.Repeat, first
end

------------------------------------------------------------------------------------------
-- daily quests
------------------------------------------------------------------------------------------

function Winter.quest(key)
	return type(key) == "string" and QUEST[key] or nil
end

-- The day's quests: the Always one, then Count - 1 more from the pool, shuffled by the day (the
-- same for everyone).
function Winter.dailyQuests(day)
	local Q = W.Quests
	local out, rest = {}, {}
	for _, q in ipairs(Q.Pool) do
		if q.Key == Q.Always then
			table.insert(out, q)
		else
			table.insert(rest, q)
		end
	end
	local seed = (whole(day) * 6151 + 101) % 2147483647
	for i = #rest, 2, -1 do
		seed = (seed * 16807) % 2147483647
		local j = seed % i + 1
		rest[i], rest[j] = rest[j], rest[i]
	end
	for i = 1, math.min(Q.Count - #out, #rest) do
		table.insert(out, rest[i])
	end
	return out
end

local function today(ev, day)
	day = whole(day)
	if ev.quests.day ~= day then
		ev.quests = { day = day, stats = {}, claimed = {} }
	end
	return ev.quests
end

-- Count things done ({ wins = 1, kills = 7, snowWins = 1, ... }: Missions.matchEvents' and the
-- event's own) toward today's quests and the event's missions.
function Winter.add(ev, events, day)
	local q = today(ev, day)
	for k, v in pairs(events or {}) do
		if type(k) == "string" and #k <= 24 and whole(v) > 0 then
			q.stats[k] = whole((q.stats[k] or 0) + whole(v))
			ev.missions.stats[k] = whole((ev.missions.stats[k] or 0) + whole(v))
		end
	end
end

-- A quest's progress today: how far, how far it goes, done, claimed.
function Winter.questProgress(ev, def, day)
	local q = today(ev, day)
	local have = math.min(whole(q.stats[def.Stat]), def.Need)
	return have, def.Need, have >= def.Need, q.claimed[def.Key] == true
end

-- Claim one of today's quests: its Snowflakes, or nil (not today's, not done, already claimed).
function Winter.claimQuest(ev, key, day)
	local def = QUEST[key or ""]
	if not def then
		return nil
	end
	local onToday = false
	for _, q in ipairs(Winter.dailyQuests(day)) do
		onToday = onToday or q.Key == key
	end
	local _, _, done, claimed = Winter.questProgress(ev, def, day)
	if not onToday or not done or claimed then
		return nil
	end
	ev.quests.claimed[key] = true
	return def.Snow
end

function Winter.text(def)
	return string.format(def.Text, def.Need)
end

------------------------------------------------------------------------------------------
-- event missions (once each, over the whole event)
------------------------------------------------------------------------------------------

function Winter.mission(key)
	return type(key) == "string" and MISSION[key] or nil
end

function Winter.missionProgress(ev, def)
	local have = math.min(whole(ev.missions.stats[def.Stat]), def.Need)
	return have, def.Need, have >= def.Need, ev.missions.claimed[def.Key] == true
end

-- Claim a mission: its Grant ({ Snow, VP, Gold, Lucky }), or nil.
function Winter.claimMission(ev, key)
	local def = MISSION[key or ""]
	if not def then
		return nil
	end
	local _, _, done, claimed = Winter.missionProgress(ev, def)
	if not done or claimed then
		return nil
	end
	ev.missions.claimed[key] = true
	return def.Grant
end

------------------------------------------------------------------------------------------
-- attendance
------------------------------------------------------------------------------------------

-- The day's attendance: once a day, the next entry of Login (the last one repeats). Returns the
-- Snowflakes and which day of attendance it was, or nil when today's is already paid.
function Winter.login(ev, day)
	day = whole(day)
	if ev.login.day == day then
		return nil
	end
	ev.login.day = day
	ev.login.count = ev.login.count + 1
	ev.missions.stats.logins = ev.login.count -- (the "check in on N days" mission)
	local n = math.min(ev.login.count, #W.Login)
	return W.Login[n], ev.login.count
end

-- Whether today's attendance is still to take.
function Winter.loginReady(ev, day)
	return ev.login.day ~= whole(day)
end

-- The next `n` days of attendance, for the menu: { day (of attendance), snow, taken }, starting
-- so that today's (or the next one to take) is in view.
function Winter.loginRow(ev, n)
	local out = {}
	local from = math.max(1, ev.login.count + 2 - n) -- (the next one to take is the last in view at the latest)
	for i = from, from + n - 1 do
		table.insert(out, { day = i, snow = W.Login[math.min(i, #W.Login)], taken = i <= ev.login.count })
	end
	return out
end

------------------------------------------------------------------------------------------
-- the Winter Pass (Config.Winter.Pass)
------------------------------------------------------------------------------------------

local PASS = W.Pass

local function passOf(ev)
	if type(ev.pass) ~= "table" then
		ev.pass = { xp = 0, premium = false, free = {}, prem = {} }
	end
	return ev.pass
end

-- Pass XP in (`n`); returns the tiers it reached that it hadn't before (a list, maybe empty).
function Winter.addPassXP(ev, n)
	local P = passOf(ev)
	local before = Winter.passTier(ev)
	P.xp = math.min(whole(P.xp) + whole(n), PASS.Tiers * PASS.TierXP)
	local reached = {}
	for t = before + 1, Winter.passTier(ev) do
		table.insert(reached, t)
	end
	return reached
end

-- The tier reached (0..Tiers), and the XP into the next one and what it takes (0, 0 at the top).
function Winter.passTier(ev)
	local xp = whole(passOf(ev).xp)
	local tier = math.min(PASS.Tiers, math.floor(xp / PASS.TierXP))
	if tier >= PASS.Tiers then
		return PASS.Tiers, 0, 0
	end
	return tier, xp - tier * PASS.TierXP, PASS.TierXP
end

-- A tier's reward on a track ("free" or "prem"), or nil.
function Winter.passReward(tier, track)
	local row = PASS.Rewards[tonumber(tier) or 0]
	return row and (track == "prem" and row.Prem or row.Free) or nil
end

-- Whether a tier's reward on a track can be claimed: ok, or false and why ("tier", "locked",
-- "claimed", "unknown").
function Winter.canClaimPass(ev, tier, track)
	tier = tonumber(tier)
	if not Winter.passReward(tier, track) then
		return false, "unknown"
	end
	local P = passOf(ev)
	if Winter.passTier(ev) < tier then
		return false, "tier"
	end
	if track == "prem" and not P.premium then
		return false, "locked"
	end
	if P[track == "prem" and "prem" or "free"][tier] then
		return false, "claimed"
	end
	return true
end

-- Claim it: the reward (the caller gives it), or nil and why.
function Winter.claimPass(ev, tier, track)
	local ok, why = Winter.canClaimPass(ev, tier, track)
	if not ok then
		return nil, why
	end
	passOf(ev)[track == "prem" and "prem" or "free"][tonumber(tier)] = true
	return Winter.passReward(tier, track)
end

-- Every reward that can be claimed now: { { tier, track }, ... } in tier order.
function Winter.passClaimable(ev)
	local out = {}
	for t = 1, PASS.Tiers do
		for _, track in ipairs({ "free", "prem" }) do
			if Winter.canClaimPass(ev, t, track) then
				table.insert(out, { tier = t, track = track })
			end
		end
	end
	return out
end

-- A reward in a few words ("50 Snowflakes", "Gold Bauble ball", "Snow Day card").
function Winter.rewardText(r)
	if type(r) ~= "table" then
		return ""
	end
	local function n(v)
		local s = tostring(whole(v))
		while true do
			local k
			s, k = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
			if k == 0 then
				break
			end
		end
		return s
	end
	if r.Snow then
		return n(r.Snow) .. " " .. W.Snow.Name
	elseif r.Gold then
		return n(r.Gold) .. " Gold"
	elseif r.VP then
		return n(r.VP) .. " VP"
	elseif r.Lucky then
		return r.Lucky == 1 and "1 lucky spin" or (n(r.Lucky) .. " lucky spins")
	elseif r.Card then
		for _, c in ipairs(Config.Cards.List) do
			if c.Key == r.Card then
				return c.Name .. " card"
			end
		end
		return r.Card .. " card"
	elseif r.Item then
		local it = Spins.item(r.Item.Kind, r.Item.Key)
		local kind = ({ Pose = "pose", Ball = "ball", Trail = "trail", Jump = "jump", Color = "colour", Effect = "score effect", Style = "style" })[r.Item.Kind] or r.Item.Kind
		return (it and it.Name or r.Item.Key) .. " " .. kind
	elseif r.Skin then
		local s = Config.Halloween.Skins[r.Skin]
		return (s and s.Name or r.Skin) .. " skin"
	elseif r.Room then
		local room = Config.Rooms.List[r.Room]
		return (room and room.Name or r.Room) .. " Home room"
	end
	return ""
end

------------------------------------------------------------------------------------------
-- things waiting to be claimed (the menu's dot)
------------------------------------------------------------------------------------------

function Winter.waiting(ev, day)
	local n = Winter.loginReady(ev, day) and 1 or 0
	for _, def in ipairs(Winter.dailyQuests(day)) do
		local _, _, done, claimed = Winter.questProgress(ev, def, day)
		if done and not claimed then
			n = n + 1
		end
	end
	for _, def in ipairs(W.Missions) do
		local _, _, done, claimed = Winter.missionProgress(ev, def)
		if done and not claimed then
			n = n + 1
		end
	end
	return n + #Winter.passClaimable(ev) + (Winter.adventState(ev, Winter.adventToday(os.time()), os.time()) == "today" and 1 or 0)
end

------------------------------------------------------------------------------------------
-- the event match: Christmas Cards (Config.Winter.Match, Rivals, Cards)
------------------------------------------------------------------------------------------

-- The lobby settings a difficulty plays with (Lobbies.settings takes them).
function Winter.settings(diff)
	local M = W.Match
	return { mode = M.Mode, privacy = "Public", fill = true, botTier = diff.Bots, points = M.Points, winBy = 1, sets = 1, timeouts = M.Timeouts, court = M.Court }
end

-- The rival team of an event day: its index in Config.Winter.Rivals (in turn, one a day), and the
-- row. A lobby keeps the index it was made with (a match never changes rival at midnight).
function Winter.rivalIndex(day)
	return whole(day) % #W.Rivals + 1
end

function Winter.rival(index)
	return W.Rivals[tonumber(index) or 0] or W.Rivals[1]
end

-- The characters the bots play (Lobbies.botPicks' shape): Jaja and the rival's two across the net
-- (`rival`: its index; today's when nil); your own team fills your side as in any match, the
-- rest are bots of the difficulty's tier.
function Winter.picks(rival, diffKey)
	local row = Winter.rival(rival or Winter.rivalIndex(Winter.day(os.time())))
	local out, seen = { Home = {}, Away = {} }, {}
	-- (a difficulty without the rivals: Jaja alone is picked, bots of its tier fill the rest)
	local d = DIFF[diffKey or ""]
	local lists = (d and d.Rivals == false) and { W.Match.Foes } or { W.Match.Foes, row.Picks }
	for _, list in ipairs(lists) do
		for _, id in ipairs(list) do
			if Roster.get(id) and not seen[id] then
				seen[id] = true
				table.insert(out.Away, id)
			end
		end
	end
	return out
end

-- Everyone who can stand on the other side of a Winter Match: the Foes and every rival's picks.
local FOE = {}
for _, id in ipairs(W.Match.Foes) do
	FOE[id] = true
end
for _, row in ipairs(W.Rivals) do
	for _, id in ipairs(row.Picks) do
		FOE[id] = true
	end
end

-- How far toward maxed the other side's own character `id` plays on a difficulty (0..1), or nil
-- when `id` isn't Jaja or one of a rival's.
function Winter.foeLevel(diffKey, id)
	local d = DIFF[diffKey or ""]
	if not d or not FOE[id or ""] then
		return nil
	end
	return d.FoeLevel or 1
end

-- the cards
local CARD, DECK = {}, 0
for _, c in ipairs(W.Cards) do
	CARD[c.Key] = c
	DECK = DECK + c.Weight
end

function Winter.cards()
	return W.Cards
end

function Winter.card(key)
	return type(key) == "string" and CARD[key] or nil
end

-- The next rally's card: drawn by Weight, never `last` again (the card in play the rally before).
function Winter.drawCard(rng, last)
	local total = DECK - (CARD[last or ""] and CARD[last].Weight or 0)
	local x = rng:NextNumber() * total
	local pick = nil
	for _, c in ipairs(W.Cards) do
		if c.Key ~= last then
			pick = pick or c
			x = x - c.Weight
			if x < 0 then
				return c
			end
		end
	end
	return pick
end

-- The rally's match modifiers: the lobby's own (a string, Mutators) with the card's on top.
function Winter.cardMutators(base, card)
	local picked = Mutators.parse(base)
	for k, v in pairs(card and card.Mut or {}) do
		picked[k] = v
	end
	return Mutators.clean(picked)
end

-- What a rally is worth with `card` in play.
function Winter.cardPoints(card)
	return math.max(1, whole(card and card.Points or 1))
end

------------------------------------------------------------------------------------------
-- the banner (Snowflakes only)
------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------
-- what only the Winter Pass and the advent calendar give (the owner, 2026-11-18: "dont allow the
-- battlepass skin or the advent calender availabe any other way then the bp and the advent
-- calender"): every cosmetic, card, skin and room on a Pass tier or behind a door, read off
-- those two tables, so whatever goes on them later is theirs too. The banner and the shop below
-- leave these out; the sims check nothing else in Config hands one out.
------------------------------------------------------------------------------------------

local EXCLUSIVE = {} -- "Kind:Key" -> { way = "Pass" | "Advent", at = tier | door }
local function markExclusive(g, way, at)
	if type(g) ~= "table" then
		return
	end
	local function mark(id)
		if not EXCLUSIVE[id] then
			EXCLUSIVE[id] = { way = way, at = at }
		end
	end
	if g.Item then
		mark(g.Item.Kind .. ":" .. g.Item.Key)
	end
	if g.Card then
		mark("Card:" .. g.Card)
	end
	if g.Skin then
		mark("Skin:" .. g.Skin)
	end
	if g.Room then
		mark("Room:" .. g.Room)
	end
end
for tier, row in ipairs(W.Pass.Rewards) do
	markExclusive(row.Free, "Pass", tier)
	markExclusive(row.Prem, "Pass", tier)
end
for door, r in ipairs(W.Advent.Rewards) do
	markExclusive(r, "Advent", door)
end

-- Whether an item ("Ball", "NorthStar"; kinds Card, Skin, Room too) comes only from the Winter
-- Pass or the advent calendar: "Pass" or "Advent" and the tier or door, else nil.
function Winter.exclusive(kind, key)
	local e = EXCLUSIVE[tostring(kind) .. ":" .. tostring(key)]
	if e then
		return e.way, e.at
	end
	return nil
end

-- Whether a grant ({ Item = ..., Card = ..., Skin = ... }) hands out anything exclusive.
function Winter.grantExclusive(g)
	if type(g) ~= "table" then
		return false
	end
	return (g.Item ~= nil and Winter.exclusive(g.Item.Kind, g.Item.Key) ~= nil)
		or (g.Card ~= nil and Winter.exclusive("Card", g.Card) ~= nil)
		or (g.Skin ~= nil and Winter.exclusive("Skin", g.Skin) ~= nil)
		or (g.Room ~= nil and Winter.exclusive("Room", g.Room) ~= nil)
end

-- Where a Christmas skin is got, for its row on the character's page: the text and the Winter
-- window's tab ("Winter Pass tier 30", "Pass").
function Winter.skinWay(key)
	local way, at = Winter.exclusive("Skin", key)
	if way == "Pass" then
		return "Winter Pass tier " .. at, "Pass"
	elseif way == "Advent" then
		return "Advent door " .. at, "Advent"
	end
	for _, row in ipairs(W.Banner.Items) do
		if row.Kind == "Skin" and row.Key == key then
			return "Wild Card banner", "Recruit"
		end
	end
	for _, row in ipairs(W.Shop) do
		if row.Skin == key then
			return "Snowflake shop", "Shop"
		end
	end
	for _, m in ipairs(W.Missions) do
		if m.Grant and m.Grant.Skin == key then
			return "Event mission", "Quests"
		end
	end
	return "Winter event", "Match"
end

local B = W.Banner
local BANNER = {}
for _, row in ipairs(B.Items) do
	local item = nil
	if Winter.exclusive(row.Kind, row.Key) then
		item = nil -- (the Pass's and the calendar's own: never a recruit)
	elseif row.Kind == "Char" then
		local c = Roster.get(row.Key)
		item = c and { name = c.Name, rarity = Spins.tierRarity(c.Tier) } or nil
	elseif row.Kind == "Grant" then
		item = { name = row.Name, rarity = row.Rarity or "Rare" }
	elseif row.Kind == "Skin" then
		-- a skin (Config.Halloween.Skins): a copy, and its character with it (ProfileService)
		local s = Config.Halloween.Skins[row.Key]
		item = s and { name = s.Name, rarity = s.Rarity or "Mythic" } or nil
	else
		-- (a cosmetic that isn't made yet is left off: the banner fills in as the art lands)
		local it = Spins.item(row.Kind, row.Key)
		item = it and { name = it.Name, rarity = it.Rarity } or nil
	end
	if item then
		table.insert(BANNER, { kind = row.Kind, key = row.Key, name = item.name, rarity = item.rarity, weight = row.Weight, grant = row.Grant, featured = row.Featured == true })
	end
end

function Winter.bannerItems()
	return BANNER
end

-- What `count` recruits cost in Snowflakes, or nil.
function Winter.cost(count)
	return B.Cost[tonumber(count) or 0]
end

-- Each item with its chance (its weight over the banner's), best first.
function Winter.bannerTable()
	local total = 0
	for _, it in ipairs(BANNER) do
		total = total + it.weight
	end
	local out = {}
	for _, it in ipairs(BANNER) do
		table.insert(out, { item = it, chance = total > 0 and it.weight / total or 0 })
	end
	table.sort(out, function(a, b)
		if a.item.featured ~= b.item.featured then
			return a.item.featured -- (Jaja heads it, over the Mythic skins)
		end
		local ra, rb = Spins.rarityRank(a.item.rarity), Spins.rarityRank(b.item.rarity)
		if ra ~= rb then
			return ra > rb
		end
		return a.item.key < b.item.key
	end)
	return out
end

local function featured()
	for _, it in ipairs(BANNER) do
		if it.featured then
			return it
		end
	end
	return nil
end

-- Recruits left until the featured character is guaranteed (1 = the very next one).
function Winter.pityLeft(ev)
	return B.Pity - whole(ev.gauge)
end

-- One recruit: an item of the banner. The gauge counts recruits without the featured character;
-- the Pity-th is him, and he empties it whenever he comes.
function Winter.roll(rng, ev)
	local pick = nil
	local star = featured()
	if star and whole(ev.gauge) + 1 >= B.Pity then
		pick = star
	else
		local list = Winter.bannerTable()
		local x = rng:NextNumber()
		pick = list[#list].item
		for _, row in ipairs(list) do
			x = x - row.chance
			if x < 0 then
				pick = row.item
				break
			end
		end
	end
	if pick.featured then
		ev.gauge = 0
	else
		ev.gauge = math.min(whole(ev.gauge) + 1, B.Pity - 1)
	end
	return pick
end

-- Snowflakes back for an item already owned (a duplicate character still gives its fragment:
-- ProfileService; this is for cosmetics).
function Winter.dupSnow(rarity)
	return B.DupSnow[rarity] or 0
end

------------------------------------------------------------------------------------------
-- the shop
------------------------------------------------------------------------------------------

function Winter.shop()
	local out = {}
	for _, row in ipairs(W.Shop) do
		if not Winter.grantExclusive(row) then -- (the Pass's and the calendar's own aren't sold)
			table.insert(out, row)
		end
	end
	return out
end

function Winter.shopRow(key)
	return type(key) == "string" and SHOP[key] or nil
end

-- Whether `key` can be bought now: ok, or false and why ("unknown", "limit", "owned", "snow").
-- owns(kind, key): whether the player already has a cosmetic (the caller's).
function Winter.canBuy(ev, key, owns)
	local row = SHOP[key or ""]
	if not row or Winter.grantExclusive(row) then
		return false, "unknown"
	end
	if row.Limit and whole(ev.bought[row.Key]) >= row.Limit then
		return false, "limit"
	end
	if row.Item and (whole(ev.bought[row.Key]) >= 1 or (owns and owns(row.Item.Kind, row.Item.Key))) then
		return false, "owned"
	end
	-- a skin: once (owns asked with "Skin")
	if row.Skin and (whole(ev.bought[row.Key]) >= 1 or (owns and owns("Skin", row.Skin))) then
		return false, "owned"
	end
	if whole(ev.snow) < row.Price then
		return false, "snow"
	end
	return true
end

-- Buy it: the Snowflakes go, the buy is counted; returns the row (its Grant or Item is the
-- caller's to give), or nil and why.
function Winter.buy(ev, key, owns)
	local ok, why = Winter.canBuy(ev, key, owns)
	if not ok then
		return nil, why
	end
	local row = SHOP[key]
	ev.snow = whole(ev.snow) - row.Price
	ev.bought[row.Key] = whole(ev.bought[row.Key]) + 1
	return row
end

------------------------------------------------------------------------------------------
-- the advent calendar (Config.Winter.Advent)
------------------------------------------------------------------------------------------

local ADV = W.Advent

-- The door `now` falls on: 1 on Starts' day, 0 and below before it, past Doors after the last.
function Winter.adventToday(now)
	return Winter.day(now) - Winter.day(ADV.Starts) + 1
end

function Winter.adventReward(door)
	return ADV.Rewards[tonumber(door) or 0]
end

local function isDoor(door)
	return type(door) == "number" and door == math.floor(door) and door >= 1 and door <= ADV.Doors
end

-- Whether door `door` is open in `ev`.
function Winter.adventOpen(ev, door)
	if not isDoor(door) then
		return false
	end
	return math.floor(whole(ev.advent) / 2 ^ (door - 1)) % 2 == 1
end

local function markDoor(ev, door)
	if not Winter.adventOpen(ev, door) then
		ev.advent = whole(ev.advent) + 2 ^ (door - 1)
	end
end

-- A door's state: "open", "today" (free to open), "missed" (gone by, shut) or "ahead" (still to
-- come): those two are opened with Robux ("early": still to come and never sold ahead, NoEarly).
-- nil: no such door.
function Winter.adventState(ev, door, now)
	if not isDoor(door) then
		return nil
	end
	if Winter.adventOpen(ev, door) then
		return "open"
	end
	local today = Winter.adventToday(now)
	if door == today then
		return "today"
	end
	if door < today then
		return "missed"
	end
	return ADV.NoEarly and ADV.NoEarly[door] and "early" or "ahead"
end

-- Open today's door, free: its reward, or nil and why ("open", "notToday").
function Winter.adventFree(ev, door, now)
	local state = Winter.adventState(ev, door, now)
	if state ~= "today" then
		return nil, state == "open" and "open" or "notToday"
	end
	markDoor(ev, door)
	return Winter.adventReward(door)
end

-- The door a bought opening goes to: `pick` when it's shut and not today's (today's is free), else
-- the earliest such door. nil when every door but today's is open.
function Winter.adventTarget(ev, pick, now)
	local function buyable(d)
		local st = Winter.adventState(ev, d, now)
		return st == "missed" or st == "ahead"
	end
	if buyable(tonumber(pick)) then
		return tonumber(pick)
	end
	for d = 1, ADV.Doors do
		if buyable(d) then
			return d
		end
	end
	return nil
end

-- A bought opening: the door and its reward, or nil.
function Winter.adventBuy(ev, pick, now)
	local door = Winter.adventTarget(ev, pick, now)
	if not door then
		return nil
	end
	markDoor(ev, door)
	return door, Winter.adventReward(door)
end

-- How many doors are open.
function Winter.adventCount(ev)
	local n = 0
	for d = 1, ADV.Doors do
		if Winter.adventOpen(ev, d) then
			n = n + 1
		end
	end
	return n
end

-- A door's reward in words ("Tinsel colour", "North Star ball and 25 Days of Winter card").
function Winter.adventText(r)
	if type(r) ~= "table" then
		return ""
	end
	local parts = {}
	if r.Skin then
		table.insert(parts, Winter.rewardText({ Skin = r.Skin }))
	end
	if r.Item then
		table.insert(parts, Winter.rewardText({ Item = r.Item }))
	end
	if r.Card then
		table.insert(parts, Winter.rewardText({ Card = r.Card }))
	end
	if #parts == 0 then
		return Winter.rewardText(r)
	end
	if #parts > 2 then
		return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
	end
	return table.concat(parts, " and ")
end

------------------------------------------------------------------------------------------
-- the event's leaderboard (Config.Winter.Board)
------------------------------------------------------------------------------------------

-- What a Winter Match win on `diffKey` adds to the board.
function Winter.boardPoints(diffKey)
	return whole(W.Board.Points[diffKey or ""])
end

-- The card a final place earns (1 is first), or nil.
function Winter.boardCard(place)
	place = tonumber(place)
	if not place or place < 1 then
		return nil
	end
	for _, r in ipairs(W.Board.Rewards) do
		if place <= r.Top then
			return r.Card
		end
	end
	return nil
end

-- Whether the board's cards are given out now: the event is over (switched on, past Ends).
function Winter.boardSettles(now)
	now = tonumber(now) or os.time()
	return W.Enabled == true and now >= W.Ends
end

return Winter
