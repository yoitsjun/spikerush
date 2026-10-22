-- Player cards (Config.Cards): the achievement that unlocks each, the numbers a profile has for
-- them, and what a card shows. Shared: the server unlocks and equips them, the menus show the
-- progress, and the headless tests check the rules.

local Config = require(script.Parent.Config)
local Ranked = require(script.Parent.Ranked)

local Cards = {}

local byKey = {}
for _, c in ipairs(Config.Cards.List) do
	byKey[c.Key] = c
end

local boardNames = {}
for _, b in ipairs(Config.Leaderboards.Boards) do
	boardNames[b.Key] = b.Name
end

-- Whether a card is only ever given (the admin panel's Give), never earned.
function Cards.isGrant(card)
	return card ~= nil and card.Grant == true
end

function Cards.list()
	return Config.Cards.List
end

function Cards.get(key)
	return type(key) == "string" and byKey[key] or nil
end

function Cards.default()
	return Config.Cards.Default
end

local function whole(v)
	v = tonumber(v) or 0
	if v ~= v then
		return 0
	end
	return math.max(0, math.floor(v))
end

-- 12345 -> "12,345"
local function commas(n)
	local s = tostring(whole(n))
	while true do
		local k
		s, k = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			return s
		end
	end
end

-- A profile's numbers for the cards. `owned`: how many characters it has recruited. The best
-- leaderboard place it has reached is profile.bestRank ({ rank, board }).
function Cards.stats(profile, owned)
	local rec = type(profile.record) == "table" and profile.record or {}
	local r = type(profile.bestRank) == "table" and profile.bestRank or nil
	local cr = type(profile.bestClanRank) == "table" and profile.bestClanRank or nil
	local rank = r and tonumber(r.rank) or nil
	local wins, matches = whole(rec.wins), whole(rec.matches)
	return {
		losses = math.max(0, matches - wins),
		winPct = matches > 0 and wins / matches * 100 or 0,
		wins = whole(rec.wins),
		kills = whole(rec.kills),
		aces = whole(rec.aces),
		blocks = whole(rec.blocks),
		matches = whole(rec.matches),
		mvps = whole(rec.mvps),
		devWins = whole(rec.devWins),
		bestStreak = whole(profile.bestStreak),
		winStreak = whole(profile.winStreak),
		owned = whole(owned),
		rank = (rank and rank >= 1) and math.floor(rank) or nil,
		rankBoard = r and r.board or nil,
		clanRank = (cr and tonumber(cr.rank) and cr.rank >= 1) and math.floor(cr.rank) or nil,
		rankedBest = whole(type(profile.ranked) == "table" and profile.ranked.best or 0),
		-- (the Ranked card: this season's)
		rankedRp = whole(type(profile.ranked) == "table" and profile.ranked.rp or 0),
		rankedSeason = whole(type(profile.ranked) == "table" and profile.ranked.season or 0),
		rankedWins = whole(type(profile.ranked) == "table" and profile.ranked.wins or 0),
		rankedLosses = whole(type(profile.ranked) == "table" and profile.ranked.losses or 0),
		rankedPlayed = whole(type(profile.ranked) == "table" and ((profile.ranked.wins or 0) + (profile.ranked.losses or 0) + #(profile.ranked.history or {})) or 0),
		clanTag = cr and cr.tag or nil,
	}
end

-- Whether a card's achievement is met.
function Cards.met(card, stats)
	if not card.Stat then
		return true
	end
	if card.Stat == "rank" then
		return stats.rank ~= nil and stats.rank <= card.Need
	end
	if card.Stat == "clanRank" then
		return stats.clanRank ~= nil and stats.clanRank <= card.Need
	end
	if card.Stat == "grant" then
		return false -- given only
	end
	return (stats[card.Stat] or 0) >= card.Need
end

-- How far along it is: have and need (a rank card: 1 of 1 once reached, else 0 of 1).
function Cards.progress(card, stats)
	if not card.Stat then
		return 1, 1
	end
	if card.Stat == "rank" or card.Stat == "clanRank" or card.Stat == "grant" then
		return Cards.met(card, stats) and 1 or 0, 1
	end
	return math.min(stats[card.Stat] or 0, card.Need), card.Need
end

-- What a card shows in big type, and the label under it: "127" "WINS"; a rank card "#2" and the
-- board ("SPIKE KILLS"). A card with nothing to show gives "", "".
function Cards.display(card, stats)
	if card.Show == "rank" then
		if not stats.rank then
			return "", ""
		end
		return "#" .. stats.rank, string.upper(boardNames[stats.rankBoard or ""] or "LEADERBOARD")
	end
	if card.Show == "clanRank" then
		if not stats.clanRank then
			return "", ""
		end
		return "#" .. stats.clanRank, "[" .. tostring(stats.clanTag or "?") .. "] TOP CLAN"
	end
	if card.Show == "ranked" then
		-- "SEASON 1", and "W:12  L:4  GOLD II"
		return string.format("SEASON %d", math.max(1, stats.rankedSeason or 1)), string.format("W:%d  L:%d  %s", stats.rankedWins or 0, stats.rankedLosses or 0, string.upper(Ranked.name(stats.rankedRp or 0)))
	end
	if card.Show == "winRate" then
		return string.format("%d%%", math.floor((stats.winPct or 0) + 0.5)), string.format("%s W  %s L", commas(stats.wins), commas(stats.losses))
	end
	if not card.Show then
		return "", ""
	end
	return commas(stats[card.Show] or 0), card.Label or ""
end

-- A card's look with "team", "rank" and "ranked" resolved: `team` is the scorer's team colour,
-- `rank` the place a rank card shows, `rp` the wearer's ranked points (the Ranked card: its colour
-- is their rank's, and Badge is their division's badge key, Assets.Images).
function Cards.look(card, team, rank, rp)
	local L = card.Look
	local rankColor = Config.Cards.RankColors[rank or 1] or Config.Cards.RankColors[1]
	local _, ranked = Ranked.rankOf(rp or 0)
	local function resolve(v)
		if v == "team" then
			return team
		elseif v == "rank" then
			return rankColor
		elseif v == "ranked" then
			return ranked.Color
		end
		return v
	end
	local badge = (L.Fx and L.Fx.RankBadge) and Ranked.badgeKey(rp or 0) or nil
	return { Base = L.Base, Sweep = resolve(L.Sweep), Accent = resolve(L.Accent), Edge = resolve(L.Edge), Pattern = L.Pattern, Big = L.Big, Avatar = L.Avatar == true, Fx = L.Fx, Badge = badge }
end

return Cards
