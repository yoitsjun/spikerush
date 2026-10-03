-- Player cards (Config.Cards): the achievement that unlocks each, the numbers a profile has for
-- them, and what a card shows. Shared: the server unlocks and equips them, the menus show the
-- progress, and the headless tests check the rules.

local Config = require(script.Parent.Config)

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
		bestStreak = whole(profile.bestStreak),
		winStreak = whole(profile.winStreak),
		owned = whole(owned),
		rank = (rank and rank >= 1) and math.floor(rank) or nil,
		rankBoard = r and r.board or nil,
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
	if card.Stat == "rank" or card.Stat == "grant" then
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
	if card.Show == "winRate" then
		return string.format("%d%%", math.floor((stats.winPct or 0) + 0.5)), string.format("%s W  %s L", commas(stats.wins), commas(stats.losses))
	end
	if not card.Show then
		return "", ""
	end
	return commas(stats[card.Show] or 0), card.Label or ""
end

-- A card's look with "team" and "rank" resolved: `team` is the scorer's team colour, `rank` the
-- place a rank card shows.
function Cards.look(card, team, rank)
	local L = card.Look
	local rankColor = Config.Cards.RankColors[rank or 1] or Config.Cards.RankColors[1]
	local function resolve(v)
		if v == "team" then
			return team
		elseif v == "rank" then
			return rankColor
		end
		return v
	end
	return { Base = L.Base, Sweep = resolve(L.Sweep), Accent = L.Accent, Edge = resolve(L.Edge), Pattern = L.Pattern, Big = L.Big, Avatar = L.Avatar == true }
end

return Cards
