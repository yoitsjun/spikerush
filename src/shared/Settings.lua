-- Player settings saved in the profile: the switches, the camera shake, the touch layout and
-- your own keys (Config.Controls).
-- The client's State.settings holds the defaults and the live values; clean() keeps only the
-- known keys with sane values, so nothing else a client sends reaches the DataStore. Shared so
-- the server and the headless tests agree.

local Config = require(script.Parent.Config)

local Settings = {}
local S = Config.Settings
local CT = Config.Controls

local allowedKey = {}
for _, name in ipairs(CT.Allowed) do
	allowedKey[name] = true
end
local isAction = {}
for _, action in ipairs(CT.Order) do
	isAction[action] = true
end

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
	-- your own keys: { [action] = key name }, allowed keys only, each key for one action
	if type(t.keys) == "table" then
		local keys, used = {}, {}
		for _, action in ipairs(CT.Order) do
			local k = t.keys[action]
			if type(k) == "string" and allowedKey[k] and not used[k] then
				keys[action] = k
				used[k] = true
			end
		end
		out.keys = keys
	end
	return out
end

-- Whether a key can be picked for an action (Config.Controls.Allowed).
function Settings.allowedKey(name)
	return allowedKey[name or ""] == true
end

-- Every keyboard key's action with your own keys (`keys`: { [action] = key name }): your key
-- replaces that action's defaults, and wins over another action's default on the same key.
function Settings.keyMap(keys)
	keys = type(keys) == "table" and keys or {}
	local map = {}
	for _, action in ipairs(CT.Order) do
		local k = keys[action]
		if type(k) == "string" and allowedKey[k] and map[k] == nil then
			map[k] = action
		end
	end
	for _, action in ipairs(CT.Order) do
		if not (type(keys[action]) == "string" and map[keys[action]] == action) then
			for _, k in ipairs(CT.Defaults[action]) do
				if map[k] == nil then
					map[k] = action
				end
			end
		end
	end
	return map
end

-- The keys an action is on right now, in the order they're shown.
function Settings.keysFor(keys, action)
	if not isAction[action or ""] then
		return {}
	end
	local map = Settings.keyMap(keys)
	local out = {}
	keys = type(keys) == "table" and keys or {}
	if type(keys[action]) == "string" and map[keys[action]] == action then
		return { keys[action] }
	end
	for _, k in ipairs(CT.Defaults[action]) do
		if map[k] == action then
			table.insert(out, k)
		end
	end
	return out
end

-- How a key reads on screen ("L Shift", "Space", "0").
function Settings.keyLabel(name)
	return CT.Labels[name or ""] or tostring(name or "?")
end

-- An action's keys as text: "Space / Z / J" (sep: what goes between them).
function Settings.keysText(keys, action, sep)
	local out = {}
	for _, k in ipairs(Settings.keysFor(keys, action)) do
		table.insert(out, Settings.keyLabel(k))
	end
	return #out > 0 and table.concat(out, sep or " / ") or "none"
end

return Settings
