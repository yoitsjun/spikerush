-- The Custom sound effects perk's cropper: the part of a player's sound that plays, per slot, as
-- { s = start, l = length } in seconds. The profile keeps it under perkCrops[slotKey]; the player
-- and their character carry it as the attribute <slotKey>Crop (a NumberRange from start to end).
-- Shared so the server, the menu and the headless tests agree.

local Config = require(script.Parent.Config)

local SoundCrop = {}
local P = Config.Perks

local function finite(x)
	return type(x) == "number" and x == x and x > -math.huge and x < math.huge
end

local function round(x)
	return math.floor(x * 100 + 0.5) / 100
end

-- The most of a slot's sound that plays: the score sound's cut-off, or a touch's or a jump's.
function SoundCrop.max(slotKey)
	return slotKey == "ScoreSound" and P.SoundSeconds or P.ActionSeconds
end

-- A crop with sane numbers (rounded to 0.01 s, the length between CropMin and the slot's max), or
-- nil when it isn't one or it's the whole front of the sound (no crop needed).
function SoundCrop.clean(slotKey, c)
	if type(c) ~= "table" or not finite(c.s) or not finite(c.l) then
		return nil
	end
	local max = SoundCrop.max(slotKey)
	local s = round(math.clamp(c.s, 0, P.CropMaxStart))
	local l = round(math.clamp(c.l, P.CropMin, max))
	if s <= 0 and l >= max then
		return nil
	end
	return { s = s, l = l }
end

-- The attribute's name for a slot.
function SoundCrop.attribute(slotKey)
	return slotKey .. "Crop"
end

-- The start and length an attribute value holds (nil, nil for none).
function SoundCrop.read(value)
	if typeof(value) == "NumberRange" then
		return value.Min, value.Max - value.Min
	end
	return nil, nil
end

return SoundCrop
