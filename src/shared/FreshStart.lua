-- The Fresh Start (Config.FreshStart): once, every profile from before it starts the character
-- and cosmetic grind over, and keeps a Veteran card for having been there. The owner, 2026-11-14,
-- after the stolen game's progress was given back and players quit within a day ("theres nothing
-- to grind for"): "only reset their characters and cosmetics, but at the same time reset all the
-- code usages", "their story and everything stays only characters and cosmetics and
-- breakthroughs and stuff"; Gold and VP capped, the Veteran card in two tiers by matches played.
--
-- Reset: characters (to the starters), their upgrades, breakthroughs and mastery, the AI teams and
-- favourites, the cosmetics won from recruits (to the starters), and every code used.
-- Kept: the Halloween event's cosmetics, skins (a skin brings its character: Halloween.skinChars)
-- and rooms, player cards, ranked and its effects, story, missions, clans, the Lounge, fragments
-- and selection tickets in hand, passes, Lucky spins, everything else.
-- Pure: ProfileService runs it as a profile loads; covered by the sims.

local Config = require(script.Parent.Config)
local Spins = require(script.Parent.Spins)
local Roster = require(script.Parent.Roster)

local FreshStart = {}
local FS = Config.FreshStart
local COS = Config.Cosmetics

-- what the Halloween event gave (its banner and its Candy shop), by "Kind:Key"
local KEEP = {}
for _, it in ipairs(Config.Halloween.Banner.Items) do
	KEEP[it.Kind .. ":" .. it.Key] = true
end
for _, row in ipairs(Config.Halloween.Shop) do
	if row.Item then
		KEEP[row.Item.Kind .. ":" .. row.Item.Key] = true
	end
end

function FreshStart.keeps(kind, key)
	return KEEP[tostring(kind) .. ":" .. tostring(key)] == true
end

-- Whether a profile still has the Fresh Start to go through.
function FreshStart.due(profile)
	return FS.Enabled == true and type(profile) == "table" and (tonumber(profile.fresh) or 0) < FS.Version
end

-- The Veteran card a profile earns: Elite for MatchesForElite or more matches played.
function FreshStart.card(profile)
	local played = type(profile.record) == "table" and tonumber(profile.record.matches) or 0
	if played >= FS.MatchesForElite then
		return FS.EliteCard
	end
	return FS.Card
end

-- Run it on `profile` (sanitized). Returns what it did: { card, goldWas, vpWas, chars, lucky }.
function FreshStart.apply(profile)
	local out = { goldWas = profile.gold, vpWas = profile.vp, chars = 0 }
	for _, kind in ipairs(Spins.Kinds) do
		local had = profile.owned[kind] or {}
		local now = {}
		for k in pairs(Spins.starters(kind)) do
			now[k] = true
		end
		for k, v in pairs(had) do
			if v and FreshStart.keeps(kind, k) then
				now[k] = true
			end
			if v and kind == "Char" and not now[k] then
				out.chars = out.chars + 1
			end
		end
		profile.owned[kind] = now
	end
	-- (the starter characters stay, but come back unupgraded)
	profile.levels = {}
	profile.breaks = {}
	profile.mastery = {}
	profile.teams = {}
	profile.fav = {}
	profile.codes = {}
	profile.char = Roster.Starters[1]
	for _, kind in ipairs(COS.Kinds) do
		if not profile.owned[kind][profile.equip[kind] or ""] then
			profile.equip[kind] = Spins.default(kind)
		end
	end
	profile.gold = math.min(math.max(0, tonumber(profile.gold) or 0), FS.GoldCap)
	profile.vp = math.min(math.max(0, tonumber(profile.vp) or 0), FS.VPCap)
	-- Robux already spent comes back as Lucky spins (what it bought is gone with the characters)
	local robux = type(profile.spent) == "table" and tonumber(profile.spent.robux) or 0
	out.lucky = math.floor(robux / FS.RobuxPerLucky)
	if out.lucky > 0 then
		profile.lucky = (tonumber(profile.lucky) or 0) + out.lucky
	end
	out.card = FreshStart.card(profile)
	profile.cards = profile.cards or {}
	profile.cards[out.card] = true
	profile.equip.Card = out.card
	profile.fresh = FS.Version
	return out
end

return FreshStart
