-- Match modifiers for custom lobbies (Config.Mutators; the owner, 2026-10-21: "add custom match
-- modifiers, like more power, low gravity, no ability cd like rocket league"). The host picks an
-- option for each; a lobby carries them as one string ("Power=Super;Gravity=Low", only what isn't
-- the first option), and while its match plays the ReplicatedStorage attribute Mutators holds that
-- string, which both sides turn into the same effects.

local Config = require(script.Parent.Config)

local Mutators = {}
local MU = Config.Mutators

local function optionOf(key, optKey)
	local m = MU.List[key]
	if not m then
		return nil
	end
	for _, o in ipairs(m.Options) do
		if o.Key == optKey then
			return o
		end
	end
	return nil
end

-- A string from anything a client sends ({ Power = "Super", ... } or a string): known modifiers
-- and options only, defaults left out, in Order.
function Mutators.clean(raw)
	local picked = type(raw) == "table" and raw or Mutators.parse(raw)
	local parts = {}
	for _, key in ipairs(MU.Order) do
		local opt = optionOf(key, picked[key])
		if opt and opt ~= MU.List[key].Options[1] then
			table.insert(parts, key .. "=" .. opt.Key)
		end
	end
	return table.concat(parts, ";")
end

-- The picks in a string: { Power = "Super", ... } (unknown ones left out).
function Mutators.parse(s)
	local out = {}
	if type(s) ~= "string" then
		return out
	end
	for key, opt in string.gmatch(s, "(%w+)=(%w+)") do
		if optionOf(key, opt) then
			out[key] = opt
		end
	end
	return out
end

-- What a string does, or nil when it's all defaults:
--   spike, serve   attack and jump-serve speed x
--   gravity        the ball's and the players' gravity x
--   cooldown       active abilities' cooldowns x (0: none)
--   drain          the guard's drain x (0: it never breaks)
--   add            stat points for everyone ({ Jump = 25, ... })
--   noAbilities    nobody plays an ability
--   noBlocks       nobody can block
--   blockUp        the block's reach higher (studs)
local cache = {}
function Mutators.effects(s)
	if type(s) ~= "string" or s == "" then
		return nil
	end
	if cache[s] ~= nil then
		return cache[s] or nil
	end
	local e = { spike = 1, serve = 1, gravity = 1, cooldown = 1, drain = 1, add = {}, blockUp = 0 }
	local any = false
	for key, optKey in pairs(Mutators.parse(s)) do
		local o = optionOf(key, optKey)
		any = true
		e.spike = e.spike * (o.Spike or 1)
		e.serve = e.serve * (o.Serve or 1)
		e.gravity = e.gravity * (o.Gravity or 1)
		e.cooldown = e.cooldown * (o.Cooldown or 1)
		e.drain = e.drain * (o.Drain or 1)
		e.blockUp = e.blockUp + (o.BlockUp or 0)
		e.noAbilities = e.noAbilities or o.NoAbilities or nil
		e.noBlocks = e.noBlocks or o.NoBlocks or nil
		for stat, v in pairs(o.Add or {}) do
			e.add[stat] = (e.add[stat] or 0) + v
		end
	end
	cache[s] = any and e or false
	return any and e or nil
end

-- The live match's effects (the Mutators attribute), or nil.
function Mutators.live()
	local rs = game and game:GetService("ReplicatedStorage")
	return Mutators.effects(rs and rs:GetAttribute("Mutators"))
end

-- Lines for the lobby and the HUD: "Spike power: Super (x1.5)", ... (non-default ones only).
function Mutators.describe(s)
	local picked = Mutators.parse(s)
	local out = {}
	for _, key in ipairs(MU.Order) do
		local o = optionOf(key, picked[key])
		if o then
			table.insert(out, MU.List[key].Name .. ": " .. (o.Name or o.Key))
		end
	end
	return out
end

return Mutators
