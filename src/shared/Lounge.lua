-- The AFK Lounge's rules (Config.Lounge), shared by LoungeService and the lounge screen.
-- A profile's lounge record is { day, payouts, gold, carry }: the day it's for, the payouts made
-- and the Gold they paid that day, and the seconds already spent towards the next one.

local Config = require(script.Parent.Config)

local Lounge = {}
local L = Config.Lounge

-- The day number a time falls in (it turns when Config.PlayRewards' day does).
function Lounge.day(now)
	return math.floor((now + Config.PlayRewards.DayOffset) / 86400)
end

-- A clean record for `day`: a stored one checked over, its payouts back to 0 on a new day.
function Lounge.clean(data, day)
	local out = { day = day, payouts = 0, gold = 0, carry = 0 }
	if type(data) == "table" then
		out.carry = math.clamp(math.floor(tonumber(data.carry) or 0), 0, L.Interval - 1)
		if tonumber(data.day) == day then
			out.payouts = math.clamp(math.floor(tonumber(data.payouts) or 0), 0, L.DailyPayouts)
			out.gold = math.max(0, math.floor(tonumber(data.gold) or 0))
		end
	end
	if out.payouts >= L.DailyPayouts then
		out.carry = 0
	end
	return out
end

-- The Gold multiplier for the VIP pass and Roblox Premium.
function Lounge.mult(vip, premium)
	return (vip and L.VipMult or 1) * (premium and L.PremiumMult or 1)
end

-- The Gold each payout pays, and the most a day pays.
function Lounge.rate(vip, premium)
	return math.floor(L.BaseGold * Lounge.mult(vip, premium) + 0.5)
end

function Lounge.cap(vip, premium)
	return Lounge.rate(vip, premium) * L.DailyPayouts
end

-- Seconds to the next payout (nil once today's are all paid).
function Lounge.nextIn(rec)
	if rec.payouts >= L.DailyPayouts then
		return nil
	end
	return L.Interval - rec.carry
end

-- Spend `dt` seconds inside: pays every payout that comes due (each `rate` Gold, and GemVP V
-- Points when rand() falls under GemChance). Returns the Gold, the V Points and the number of
-- payouts made; past today's last payout the time stops counting.
function Lounge.advance(rec, dt, rate, rand)
	local gold, vp, n = 0, 0, 0
	if rec.payouts >= L.DailyPayouts then
		rec.carry = 0
		return gold, vp, n
	end
	rec.carry = rec.carry + math.max(0, dt)
	while rec.carry >= L.Interval and rec.payouts < L.DailyPayouts do
		rec.carry = rec.carry - L.Interval
		rec.payouts = rec.payouts + 1
		gold = gold + rate
		rec.gold = rec.gold + rate
		if rand() < L.GemChance then
			vp = vp + L.GemVP
		end
		n = n + 1
	end
	if rec.payouts >= L.DailyPayouts then
		rec.carry = 0
	end
	return gold, vp, n
end

return Lounge
