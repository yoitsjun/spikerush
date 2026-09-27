-- Player settings saved in the profile: the switches, the camera shake and the touch layout.
-- The client's State.settings holds the defaults and the live values; clean() keeps only the
-- known keys with sane values, so nothing else a client sends reaches the DataStore. Shared so
-- the server and the headless tests agree.

local Config = require(script.Parent.Config)

local Settings = {}
local S = Config.Settings

local function finite(x)
	return type(x) == "number" and x == x and x > -math.huge and x < math.huge
end

local function round(x)
	return math.floor(x * 1000 + 0.5) / 1000
end

-- One touch button's place and size ({ x, y, size }), or nil when it isn't a valid one.
function Settings.touchButton(b)
	if type(b) ~= "table" or not finite(b.x) or not finite(b.y) or not finite(b.size) then
		return nil
	end
	return {
		x = round(math.clamp(b.x, 0, 1)),
		y = round(math.clamp(b.y, 0, 1)),
		size = round(math.clamp(b.size, S.Touch.MinSize, S.Touch.MaxSize)),
	}
end

-- The saved settings in `t`, cleaned. A key that's missing or of the wrong type is left out
-- (the client keeps its default); an empty touch layout means every button in its usual place.
function Settings.clean(t)
	local out = {}
	if type(t) ~= "table" then
		return out
	end
	for _, key in ipairs(S.Switches) do
		if type(t[key]) == "boolean" then
			out[key] = t[key]
		end
	end
	for key, range in pairs(S.Numbers) do
		if finite(t[key]) then
			out[key] = math.clamp(t[key], range[1], range[2])
		end
	end
	if type(t.touchLayout) == "table" then
		local layout = {}
		for _, name in ipairs(S.Touch.Buttons) do
			layout[name] = Settings.touchButton(t.touchLayout[name])
		end
		out.touchLayout = layout
	end
	return out
end

return Settings
