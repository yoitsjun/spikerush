-- Keyboard, mouse and gamepad input. Touch controls live in MobileControls.
-- Mirrors The Spike's keyboard layout, with WASD and mouse alternatives:
--
--   Move ............ Left/Right or A/D
--   Spike ........... Z, J or left click   (ground: run-up jump / air: spike;
--                                            Azure Dragon: hold in the air to charge, release to swing)
--   Receive ......... Down, S, K or right click (press a little early; the stance stays armed)
--   Slide / feint ... C, Shift or L         (ground: slide receive / air: roll shot)
--   Block ........... Up or W               (hold to jump higher, release to jump)
--   Jump ............ Space
--   Set ............. E or V                (hold toward the net for a quick, away for a back set)
--   Serve ........... X                     (tap = overhand serve; hold = jump-serve toss, longer = higher)
--   Ability ......... Q                     (active abilities: Iron Wall)
--   Timeout ......... T
--
-- Gamepad: A spike, B receive, X serve, Y block, RB slide/feint, LB set, R2 spike, L2 ability,
-- Select timeout.

local UserInputService = game:GetService("UserInputService")

local InputController = {}
local mods

local lastDevice = "Keyboard"

local KEYS = {
	[Enum.KeyCode.Z] = "Spike",
	[Enum.KeyCode.J] = "Spike",
	[Enum.KeyCode.Down] = "Receive",
	[Enum.KeyCode.S] = "Receive",
	[Enum.KeyCode.K] = "Receive",
	[Enum.KeyCode.C] = "SlideFeint",
	[Enum.KeyCode.LeftShift] = "SlideFeint",
	[Enum.KeyCode.RightShift] = "SlideFeint",
	[Enum.KeyCode.L] = "SlideFeint",
	[Enum.KeyCode.Up] = "Block",
	[Enum.KeyCode.W] = "Block",
	[Enum.KeyCode.E] = "Set",
	[Enum.KeyCode.V] = "Set",
	[Enum.KeyCode.X] = "Serve",
	[Enum.KeyCode.T] = "Timeout",
	[Enum.KeyCode.Q] = "Ability",
	[Enum.KeyCode.ButtonL2] = "Ability",
	[Enum.KeyCode.ButtonA] = "Spike",
	[Enum.KeyCode.ButtonR2] = "Spike",
	[Enum.KeyCode.ButtonB] = "Receive",
	[Enum.KeyCode.ButtonX] = "Serve",
	[Enum.KeyCode.ButtonY] = "Block",
	[Enum.KeyCode.ButtonR1] = "SlideFeint",
	[Enum.KeyCode.ButtonL1] = "Set",
	[Enum.KeyCode.ButtonSelect] = "Timeout",
}

local MOUSE = {
	[Enum.UserInputType.MouseButton1] = "Spike",
	[Enum.UserInputType.MouseButton2] = "Receive",
}

local held = {}

function InputController.lastDevice()
	return lastDevice
end

function InputController.isHeld(action)
	return held[action] == true
end

-- -1, 0 or 1 along the court (screen right is +z).
function InputController.keyboardAxis()
	local axis = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		axis = axis + 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
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
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local t = input.UserInputType
		local action = MOUSE[t]
		if action then
			lastDevice = "Keyboard"
			press(action)
			return
		end
		action = KEYS[input.KeyCode]
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
		local action = MOUSE[input.UserInputType] or KEYS[input.KeyCode]
		if action then
			release(action)
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
