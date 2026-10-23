-- The AFK Lounge's rules (Config.Lounge), shared by LoungeService and the lounge screen.
-- A profile's lounge record is { day, payouts, gold, carry, made, log }: the day it's for, the
-- payouts made and the Gold they paid that day, the seconds already spent towards the next one,
-- and this stay's totals (made: { Gold, VP, Lucky, BoostVP, BoostLuck, n }) with its latest rolls
-- (log: { i, m }, the reward's index in Config.Lounge.Rewards and the multiplier it had). A stay
-- starts when you step in from a public server and lasts through the lounge's teleports.

local Config = require(script.Parent.Config)

local Lounge = {}
local L = Config.Lounge
local KINDS = { "Gold", "VP", "Lucky", "BoostVP", "BoostLuck" }
Lounge.Kinds = KINDS

-- The day number a time falls in (it turns when Config.PlayRewards' day does).
function Lounge.day(now)
	return math.floor((now + Config.PlayRewards.DayOffset) / 86400)
end

local function whole(v)
	return math.max(0, math.floor(tonumber(v) or 0))
end

-- A fresh stay's totals.
function Lounge.newMade()
	local m = { n = 0 }
	for _, k in ipairs(KINDS) do
		m[k] = 0
	end
	return m
end

-- A clean record for `day`: a stored one checked over, its payouts back to 0 on a new day (the
-- stay's totals carry on through midnight).
function Lounge.clean(data, day)
	local out = { day = day, payouts = 0, gold = 0, carry = 0, made = Lounge.newMade(), log = {} }
	if type(data) == "table" then
		out.carry = math.clamp(math.floor(tonumber(data.carry) or 0), 0, L.Interval - 1)
		if tonumber(data.day) == day then
			out.payouts = math.clamp(math.floor(tonumber(data.payouts) or 0), 0, L.DailyPayouts)
			out.gold = whole(data.gold)
		end
		if type(data.made) == "table" then
			out.made.n = whole(data.made.n)
			for _, k in ipairs(KINDS) do
				out.made[k] = whole(data.made[k])
			end
		end
		if type(data.log) == "table" then
			for _, e in ipairs(data.log) do
				local i = type(e) == "table" and tonumber(e.i)
				if i and L.Rewards[i] and #out.log < L.LogSize then
					table.insert(out.log, { i = i, m = math.max(1, tonumber(e.m) or 1) })
				end
			end
		end
	end
	if out.payouts >= L.DailyPayouts then
		out.carry = 0
	end
	return out
end

-- Starts a new stay: its totals and rolls back to nothing.
function Lounge.startStay(rec)
	rec.made = Lounge.newMade()
	rec.log = {}
end

-- The Gold and V Points multiplier for the VIP pass and Roblox Premium.
function Lounge.mult(vip, premium)
	return (vip and L.VipMult or 1) * (premium and L.PremiumMult or 1)
end

-- Reward i's chance (0 to 1).
function Lounge.chance(i)
	local total = 0
	for _, r in ipairs(L.Rewards) do
		total = total + r.Weight
	end
	return L.Rewards[i].Weight / math.max(total, 1e-9)
end

-- The reward a roll lands on (r in [0, 1)), by weight: its index in Config.Lounge.Rewards.
function Lounge.pick(r)
	local total = 0
	for _, w in ipairs(L.Rewards) do
		total = total + w.Weight
	end
	local x = r * total
	for i, w in ipairs(L.Rewards) do
		x = x - w.Weight
		if x < 0 then
			return i
		end
	end
	return #L.Rewards
end

-- What reward i gives at multiplier `mult`: its Grant, the Gold and V Points multiplied.
function Lounge.grant(i, mult)
	local g = {}
	for k, v in pairs(L.Rewards[i].Grant) do
		g[k] = v
	end
	for _, k in ipairs({ "Gold", "VP" }) do
		if g[k] then
			g[k] = math.floor(g[k] * (mult or 1) + 0.5)
		end
	end
	return g
end

-- A short name for a grant: "+30 GOLD", "+10 VP", "LUCKY SPIN", "2x VP  5 MIN".
function Lounge.label(g)
	local parts = {}
	if (g.Gold or 0) > 0 then
		table.insert(parts, "+" .. g.Gold .. " GOLD")
	end
	if (g.VP or 0) > 0 then
		table.insert(parts, "+" .. g.VP .. " VP")
	end
	if (g.Lucky or 0) > 0 then
		table.insert(parts, g.Lucky == 1 and "LUCKY SPIN" or (g.Lucky .. " LUCKY SPINS"))
	end
	if (g.BoostVP or 0) > 0 then
		table.insert(parts, "2x VP  " .. math.floor(g.BoostVP / 60 + 0.5) .. " MIN")
	end
	if (g.BoostLuck or 0) > 0 then
		table.insert(parts, "2x LUCK  " .. math.floor(g.BoostLuck / 60 + 0.5) .. " MIN")
	end
	return table.concat(parts, "  ")
end

-- Seconds to the next payout (nil once today's are all paid).
function Lounge.nextIn(rec)
	if rec.payouts >= L.DailyPayouts then
		return nil
	end
	return L.Interval - rec.carry
end

-- Spend `dt` seconds inside: every payout that comes due rolls a reward (Lounge.pick on rand())
-- at multiplier `mult`, added to the day's Gold, the stay's totals and its log. Returns the rolls
-- ({ i, g } each) and their grants added together; past today's last payout the time stops counting.
function Lounge.advance(rec, dt, mult, rand)
	local rolls, sum = {}, {}
	if rec.payouts >= L.DailyPayouts then
		rec.carry = 0
		return rolls, sum
	end
	rec.made = rec.made or Lounge.newMade()
	rec.log = rec.log or {}
	rec.carry = rec.carry + math.max(0, dt)
	while rec.carry >= L.Interval and rec.payouts < L.DailyPayouts do
		rec.carry = rec.carry - L.Interval
		rec.payouts = rec.payouts + 1
		local i = Lounge.pick(rand())
		local g = Lounge.grant(i, mult)
		for k, v in pairs(g) do
			sum[k] = (sum[k] or 0) + v
			rec.made[k] = (rec.made[k] or 0) + v
		end
		rec.gold = rec.gold + (g.Gold or 0)
		rec.made.n = rec.made.n + 1
		table.insert(rec.log, 1, { i = i, m = mult })
		while #rec.log > L.LogSize do
			table.remove(rec.log)
		end
		table.insert(rolls, { i = i, g = g })
	end
	if rec.payouts >= L.DailyPayouts then
		rec.carry = 0
	end
	return rolls, sum
end

return Lounge
