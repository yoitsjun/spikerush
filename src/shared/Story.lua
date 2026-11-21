-- Story mode (Config.Story): chapters of stages that unlock one by one, three stars a stage, a
-- reward the first time a stage is cleared and the first time it has three stars. Pure and
-- shared: the server checks and pays, the client draws the same answers; covered by the sims.
--
-- A player's progress is profile.story = { stars = { [stage key] = 1..3 } }: a stage with a star
-- is cleared. Stages run in order across chapters; the first is always open, the rest open when
-- the one before is cleared.

local Config = require(script.Parent.Config)
local Roster = require(script.Parent.Roster)
local Characters = require(script.Parent.Characters)

local Story = {}
local ST = Config.Story

local ORDER = {} -- every stage, in order
local BY_KEY = {} -- stage key -> { stage, chapter, index (in ORDER), number (in its chapter) }
local CHAPTER = {}
for _, ch in ipairs(ST.Chapters) do
	CHAPTER[ch.Key] = ch
	for n, s in ipairs(ch.Stages) do
		-- (a side chapter's stages stand apart: not in the main story's order, Story.unlocked)
		if not ch.Side then
			table.insert(ORDER, s)
		end
		BY_KEY[s.Key] = { stage = s, chapter = ch, index = (not ch.Side) and #ORDER or nil, number = n }
	end
end

function Story.chapters()
	return ST.Chapters
end

function Story.chapter(key)
	return type(key) == "string" and CHAPTER[key] or nil
end

-- A stage by key: the stage, its chapter, its place among every stage, its number in the chapter.
function Story.stage(key)
	local e = type(key) == "string" and BY_KEY[key] or nil
	if not e then
		return nil
	end
	return e.stage, e.chapter, e.index, e.number
end

-- "1 - 2": chapter and stage numbers, as Home's plate and the title card show them.
function Story.label(key)
	local s, ch, _, n = Story.stage(key)
	if not s then
		return ""
	end
	return string.format("%s - %d", ch.Tag or tostring(ch.Number), n)
end

function Story.isMatch(stage)
	return stage ~= nil and stage.Kind == "Match"
end

------------------------------------------------------------------------------------------
-- progress
------------------------------------------------------------------------------------------

-- Saved progress made safe: only real stages, 1 to 3 stars.
function Story.clean(data)
	local out = { stars = {} }
	local stars = type(data) == "table" and type(data.stars) == "table" and data.stars or {}
	for key, n in pairs(stars) do
		n = tonumber(n)
		if type(key) == "string" and BY_KEY[key] and n and n >= 1 then
			out.stars[key] = math.min(3, math.floor(n))
		end
	end
	return out
end

function Story.stars(progress, key)
	local stars = type(progress) == "table" and progress.stars or nil
	return (stars and stars[key]) or 0
end

function Story.cleared(progress, key)
	return Story.stars(progress, key) >= 1
end

-- Whether a stage can be entered: the first always, the rest once the one before is cleared.
function Story.unlocked(progress, key)
	local e = type(key) == "string" and BY_KEY[key] or nil
	if not e then
		return false
	end
	-- a side chapter (the Winter story): its first stage is open, the rest one after another
	if e.chapter.Side then
		return e.number == 1 or Story.cleared(progress, e.chapter.Stages[e.number - 1].Key)
	end
	if e.index == 1 then
		return true
	end
	return Story.cleared(progress, ORDER[e.index - 1].Key)
end

-- The stage to play next: the first one not cleared (nil when the whole story is done).
function Story.next(progress)
	for _, s in ipairs(ORDER) do
		if not Story.cleared(progress, s.Key) then
			return s
		end
	end
	return nil
end

-- A chapter's stars: earned, and the most there are.
function Story.chapterStars(progress, chapter)
	local have, total = 0, 0
	for _, s in ipairs(chapter.Stages) do
		have = have + Story.stars(progress, s.Key)
		total = total + 3
	end
	return have, total
end

function Story.seasonStars(progress, seasonKey)
	local have, total = 0, 0
	for _, ch in ipairs(ST.Chapters) do
		if ch.Season == seasonKey then
			local h, t = Story.chapterStars(progress, ch)
			have, total = have + h, total + t
		end
	end
	return have, total
end

-- Whether a chapter shows as open: its first stage can be entered.
function Story.chapterOpen(progress, chapter)
	return Story.unlocked(progress, chapter.Stages[1].Key)
end

------------------------------------------------------------------------------------------
-- stars and rewards
------------------------------------------------------------------------------------------

-- The stars a match earns: none for a loss; a win, a win by StarDiff[2], a win by StarDiff[3].
-- A stage the story loses (its Score: the owner, 2026-11-14, "set 1... maybe a lore loss") counts
-- the points you took instead, a star for each of its Score reached, won or lost.
function Story.starsFor(won, mine, theirs, stage)
	if type(stage) == "table" and type(stage.Score) == "table" then
		local n = 0
		for i = 1, 3 do
			if stage.Score[i] and (tonumber(mine) or 0) >= stage.Score[i] then
				n = i
			end
		end
		return n
	end
	if not won then
		return 0
	end
	local diff = (tonumber(mine) or 0) - (tonumber(theirs) or 0)
	local n = 1
	for i = 2, 3 do
		if diff >= ST.StarDiff[i] then
			n = i
		end
	end
	return n
end

-- A stage's three goals, as text.
function Story.goals(stage)
	if not Story.isMatch(stage) then
		return { ST.ReadGoal, ST.ReadGoal, ST.ReadGoal }
	end
	if type(stage.Score) == "table" then
		local out = {}
		for i = 1, 3 do
			out[i] = string.format(ST.ScoreGoal, stage.Score[i] or 0)
		end
		return out
	end
	return ST.Goals
end

local function addGrant(into, g)
	for k, v in pairs(g or {}) do
		if type(v) == "number" then
			into[k] = (into[k] or 0) + v
		end
	end
end

-- Write a result into `progress` (`stars` 0..3: the best is kept). Returns what it earned:
-- { stars (this time), best, first (the stage's first clear), three (its first three stars),
-- grant (the rewards those pay, summed; nil when neither) }.
function Story.record(progress, key, stars)
	local stage = Story.stage(key)
	if not stage or not Story.unlocked(progress, key) then
		return nil
	end
	stars = math.max(0, math.min(3, math.floor(tonumber(stars) or 0)))
	local before = Story.stars(progress, key)
	local out = { stars = stars, best = math.max(before, stars), first = before < 1 and stars >= 1, three = before < 3 and stars >= 3 }
	if out.best > before then
		progress.stars[key] = out.best
	end
	if out.first or out.three then
		out.grant = {}
		if out.first then
			addGrant(out.grant, stage.First)
		end
		if out.three then
			addGrant(out.grant, stage.Three)
		end
	end
	return out
end

-- "+60 VP, +1,000 Gold": a grant in a line.
function Story.grantText(g)
	local parts = {}
	local function comma(n)
		local s = tostring(math.floor(n))
		local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		if out:sub(1, 1) == "," then
			out = out:sub(2)
		end
		return out
	end
	for _, k in ipairs({ "VP", "Gold", "Lucky" }) do
		local v = g and g[k]
		if type(v) == "number" and v > 0 then
			table.insert(parts, "+" .. comma(v) .. " " .. (k == "Lucky" and (v == 1 and "Lucky Spin" or "Lucky Spins") or k))
		end
	end
	return table.concat(parts, ", ")
end

------------------------------------------------------------------------------------------
-- a story match
------------------------------------------------------------------------------------------

-- The lobby settings a stage plays with (Lobbies.settings takes them).
function Story.settings(stage)
	return { mode = ST.Mode, privacy = "Public", fill = true, botTier = stage.Bots, points = stage.Points, winBy = 1, sets = 1, timeouts = ST.Timeouts, court = stage.Court }
end

-- The characters the bots play (Lobbies.botPicks' shape): your teammates and the other team.
-- Your teammates are the story's own only on a locked stage (Lock); elsewhere Home stays empty
-- and your own team fills in, as in a normal match (TeamService: the captain's picks).
function Story.picks(stage)
	local out = { Home = {}, Away = {} }
	if not Story.isMatch(stage) then
		return out
	end
	if stage.Lock then
		for _, id in ipairs(stage.Mates or {}) do
			table.insert(out.Home, id)
		end
	end
	for _, id in ipairs(stage.Foes or {}) do
		table.insert(out.Away, id)
	end
	return out
end

-- A held-back rival's stats (Config.Story's FoeHold Level): each stat that far from a fresh
-- recruit's (0) to maxed (1). The tier and build, as Characters.fromRoster gives them.
function Story.heldBuild(c, level)
	level = math.max(0, math.min(1, tonumber(level) or 0))
	local levels = {}
	for _, stat in ipairs(Config.Stats.Order) do
		local base = Characters.baseStat(c, stat)
		levels[stat] = math.floor(base + (c[stat] - base) * level + 0.5)
	end
	return Characters.fromRoster(c, levels)
end

-- How far a match is through its chapter's matches: 0 (the first) to 1 (the last).
local function along(stage)
	local e = stage and BY_KEY[stage.Key]
	if not e then
		return 0, nil
	end
	local at, n = 0, 0
	for _, s in ipairs(e.chapter.Stages) do
		if Story.isMatch(s) then
			n = n + 1
			if s == stage then
				at = n
			end
		end
	end
	return (n > 1 and at > 0) and (at - 1) / (n - 1) or 0, e.chapter
end

local function ramp(stage, field)
	if type(stage and stage[field]) == "number" then
		return math.max(0, math.min(1, stage[field]))
	end
	local t, ch = along(stage)
	local pair = (ch and ch[field]) or ST[field]
	return math.max(0, math.min(1, pair[1] + (pair[2] - pair[1]) * t))
end

-- How built the other team is in a stage (Config.Story's FoeLevel): 0 a fresh recruit's stats,
-- 1 maxed; it climbs through the chapter. Story.heldBuild turns it into a build.
function Story.foeLevel(stage)
	return ramp(stage, "FoeLevel")
end

-- The share of the other team's block jumps that are timed properly in a stage (FoeBlock); the
-- rest go up early or late (BotService) and miss.
function Story.foeBlock(stage)
	return ramp(stage, "FoeBlock")
end

-- The other team as cards for the stage list: { id, name, role, tier }.
function Story.foes(stage)
	local out = {}
	for _, id in ipairs((stage and stage.Foes) or {}) do
		local c = Roster.get(id)
		if c then
			table.insert(out, { id = c.Id, name = Story.castName(c.Id), role = c.Role, tier = c.Tier }) -- (the story's name for them)
		end
	end
	return out
end

------------------------------------------------------------------------------------------
-- the cast
------------------------------------------------------------------------------------------

-- A face of the story by id: its Config.Story.Cast row (a roster character without one gets its
-- roster name and a plain look).
function Story.cast(id)
	local c = ST.Cast[id]
	if c then
		return c
	end
	local r = Roster.get(id)
	if r then
		return { Name = r.Name }
	end
	return nil
end

function Story.castName(id)
	local c = Story.cast(id)
	return c and c.Name or tostring(id)
end

-- A cast member's shirt and shorts colours (nil without a kit).
function Story.kit(id)
	local c = Story.cast(id)
	local k = c and c.Kit and ST.Kits[c.Kit]
	if not k then
		return nil
	end
	return k[1], k[2]
end

return Story
