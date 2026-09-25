-- Small shared helpers used by both server and client.

local Players = game:GetService("Players")

local Util = {}

function Util.clamp(x, a, b)
	if x < a then
		return a
	end
	if x > b then
		return b
	end
	return x
end

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

-- Synchronised clock: identical meaning on server and every client.
function Util.now()
	return workspace:GetServerTimeNow()
end

function Util.flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

function Util.flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Frame-rate independent exponential smoothing.
function Util.damp(current, target, speed, dt)
	return current + (target - current) * (1 - math.exp(-speed * dt))
end

function Util.smoothstep(t)
	t = Util.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function Util.isFiniteVector(v)
	if typeof(v) ~= "Vector3" then
		return false
	end
	local m = v.Magnitude
	return m == m and m < 1e5
end

-- Minimal synchronous signal (handlers run immediately, isolated with task.spawn).
local Signal = {}
Signal.__index = Signal

function Util.Signal()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handler = { fn = fn, connected = true }
	local list = self._handlers
	table.insert(list, handler)
	return {
		Disconnect = function()
			handler.connected = false
			for i = #list, 1, -1 do
				if list[i] == handler then
					table.remove(list, i)
				end
			end
		end,
	}
end

function Signal:Fire(...)
	local snapshot = table.clone(self._handlers)
	for _, h in ipairs(snapshot) do
		if h.connected then
			task.spawn(h.fn, ...)
		end
	end
end

-- Entities are "P_<userId>" for players and "B_<n>" for bots.
function Util.modelOf(entityId)
	if type(entityId) ~= "string" then
		return nil
	end
	if string.sub(entityId, 1, 2) == "P_" then
		local uid = tonumber(string.sub(entityId, 3))
		local plr = uid and Players:GetPlayerByUserId(uid)
		return plr and plr.Character or nil
	end
	local bots = workspace:FindFirstChild("Bots")
	return bots and bots:FindFirstChild(entityId) or nil
end

function Util.rootOf(entityId)
	local model = Util.modelOf(entityId)
	return model and model:FindFirstChild("HumanoidRootPart") or nil
end

return Util
