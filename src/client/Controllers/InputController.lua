-- Keyboard, mouse and gamepad input. Touch controls live in MobileControls.
-- Mirrors The Spike's keyboard layout, with WASD and mouse alternatives:
--
--   Move ............ Left/Right or A/D
--   Spike ........... Space, Z, J or left click (ground: run-up jump, or with the double approach
--                                            a squeak then the jump / air: spike; Azure Dragon:
--                                            hold in the air to charge, release to swing)
--   Receive ......... Down, S, K or right click (press a little early; the stance stays armed)
--   Slide / feint ... C, Shift or L         (ground: slide receive / air: roll shot)
--   Block ........... Up or W               (hold to jump higher, release to jump)
--   Set ............. E or V                (hold toward the net for a quick, away for a back set)
--   Serve ........... X                     (tap = overhand serve; hold = jump-serve toss, longer = higher)
--   Easy serve ...... F                     (an underhand serve straight from the hand: slow, always in)
--   Ability ......... Q                     (active abilities: Iron Wall)
--   Timeout ......... T
--
-- Gamepad: A spike, B receive, X serve, D-pad up easy serve, Y block, RB slide/feint, LB set,
-- R2 spike, L2 ability, Select timeout.
--
-- The keyboard keys above are the defaults (Config.Controls): Settings > Controls gives an action
-- a key of your own instead (Settings.keyMap; capture() takes the next key pressed for it).

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Settings = require(Shared.Settings)
local State = require(script.Parent.State)

local InputController = {}
local mods

local lastDevice = "Keyboard"

-- the controller's buttons and the teammates' abilities on 1 and 2 (these stay as they are)
local FIXED = {
	[Enum.KeyCode.ButtonL2] = "Ability",
	[Enum.KeyCode.One] = "Team1", -- your AI teammates' abilities
	[Enum.KeyCode.Two] = "Team2",
	[Enum.KeyCode.DPadLeft] = "Team1",
	[Enum.KeyCode.DPadRight] = "Team2",
	[Enum.KeyCode.ButtonA] = "Spike",
	[Enum.KeyCode.ButtonR2] = "Spike",
	[Enum.KeyCode.ButtonB] = "Receive",
	[Enum.KeyCode.ButtonX] = "Serve",
	[Enum.KeyCode.DPadUp] = "EasyServe",
	[Enum.KeyCode.ButtonY] = "Block",
	[Enum.KeyCode.ButtonR1] = "SlideFeint",
	[Enum.KeyCode.ButtonL1] = "Set",
	[Enum.KeyCode.ButtonSelect] = "Timeout",
}

local MOUSE = {
	[Enum.UserInputType.MouseButton1] = "Spike",
	[Enum.UserInputType.MouseButton2] = "Receive",
}

-- the keyboard, from your keys and the defaults (Settings.keyMap): key -> action, and the keys
-- that move you along the court
local KEYS = {}
local moveLeft, moveRight = {}, {}
local capturing = nil -- Settings > Controls waiting for a key: called with its name

local function rebuild()
	local keys, left, right = {}, {}, {}
	for name, action in pairs(Settings.keyMap(State.settings.keys)) do
		local ok, kc = pcall(function()
			return Enum.KeyCode[name]
		end)
		if ok and kc then
			if action == "MoveLeft" then
				table.insert(left, kc)
			elseif action == "MoveRight" then
				table.insert(right, kc)
			else
				keys[kc] = action
			end
		end
	end
	KEYS, moveLeft, moveRight = keys, left, right
end

local function actionFor(keyCode)
	return KEYS[keyCode] or FIXED[keyCode]
end

-- The next key pressed goes to fn(name) instead of the game (Settings > Controls).
function InputController.capture(fn)
	capturing = fn
end

function InputController.cancelCapture()
	capturing = nil
end

-- An action's keys as text right now ("Space / Z / J").
function InputController.keysText(action, sep)
	return Settings.keysText(State.settings.keys, action, sep)
end

local held = {}

function InputController.lastDevice()
	return lastDevice
end

function InputController.isHeld(action)
	return held[action] == true
end

-- -1, 0 or 1 along the court (screen right is +z).
local function anyDown(list)
	for _, kc in ipairs(list) do
		if UserInputService:IsKeyDown(kc) then
			return true
		end
	end
	return false
end

function InputController.keyboardAxis()
	local axis = 0
	if anyDown(moveRight) then
		axis = axis + 1
	end
	if anyDown(moveLeft) then
		axis = axis - 1
	end
	return axis
end

local function press(action)
	held[action] = true
	mods.ActionController.press(action)
end

local function release(action)
	if held[action] then
		held[action] = nil
		mods.ActionController.release(action)
	end
end

function InputController.init(m)
	mods = m
	-- Space is Spike too. It's taken above Roblox's own jump (sunk at a higher priority), so a
	-- press never also hops: on the ground it's the run-up jump (pressed twice with the double approach)
	rebuild()
	State.signals.Settings:Connect(function(key)
		if key == "keys" then
			rebuild()
		end
	end)
	ContextActionService:BindActionAtPriority("SpikeRushSpace", function(_, inputState)
		-- whatever Space is on (Spike unless you moved it); it never hops on its own
		if inputState == Enum.UserInputState.Begin and capturing then
			local fn = capturing
			capturing = nil
			fn("Space")
			return Enum.ContextActionResult.Sink
		end
		local action = KEYS[Enum.KeyCode.Space]
		if inputState == Enum.UserInputState.Begin then
			lastDevice = "Keyboard"
			if action then
				press(action)
			end
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			if action then
				release(action)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local t = input.UserInputType
		local action = MOUSE[t]
		if action then
			if State.isMobile then
				return -- touch controls (Studio's ForceTouch): the mouse is the finger
			end
			lastDevice = "Keyboard"
			press(action)
			return
		end
		if capturing and t == Enum.UserInputType.Keyboard then
			local fn = capturing
			capturing = nil
			fn(input.KeyCode.Name)
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			return -- Space goes through its own binding above
		end
		action = actionFor(input.KeyCode)
		if action then
			if t == Enum.UserInputType.Gamepad1 then
				lastDevice = "Gamepad"
			else
				lastDevice = "Keyboard"
			end
			press(action)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if State.isMobile and MOUSE[input.UserInputType] then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			return
		end
		local action = MOUSE[input.UserInputType] or actionFor(input.KeyCode)
		if action then
			release(action)
		end
	end)
	-- AFK watch: any input (keys, mouse, touch, sticks) tells the server you're here, at most
	-- once per Afk.PingInterval
	local lastInput, lastSent = 0, 0
	local function touched()
		lastInput = os.clock()
	end
	UserInputService.InputBegan:Connect(touched)
	UserInputService.InputChanged:Connect(touched)
	task.spawn(function()
		local remote = Net.get("Activity")
		while true do
			task.wait(Config.Afk.PingInterval)
			if lastInput > lastSent then
				lastSent = os.clock()
				remote:FireServer()
			end
		end
	end)
	-- losing focus must never leave a hold (charge, toss, block) stuck on
	UserInputService.WindowFocusReleased:Connect(function()
		for action in pairs(held) do
			release(action)
		end
	end)
end

return InputController
