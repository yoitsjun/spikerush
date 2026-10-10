-- Controller (gamepad) navigation for the menus and the in-match panels (the owner: "start with
-- everything"). The game's own controls already take a controller (InputController); this is
-- everything around them.
--   * a root is a panel that takes the controller while it's on screen: a menu page, a modal, the
--     lobby's character picker, the settings panel, the timeout panel, the continue vote, the
--     match's result screen. The highest priority one showing has it (the newest on a tie).
--   * the selection (GuiService.SelectedObject) stays in that root: it starts on the root's
--     first button (its `first`, a NavFirst attribute, else the top-left one), comes back where you
--     left it, and Roblox's own navigation moves it (D-pad, left stick) and presses it (A)
--   * B is the root's back (close a modal, back to Home), LB/RB its main tabs, LT/RT its second
--     row of tabs, Y and X its own extras when it has them
--   * nothing is selected while you play, so A still spikes. In a match D-pad down opens the
--     settings panel (Timeout and Forfeit are there too).
--   * the controller is "in use" from its first input until the mouse, keyboard or a touch
-- Buttons that only make sense with a mouse (the huge click-anywhere ones, the HUD's action rail)
-- carry NoNav; the corner buttons a page shouldn't start on (Back, Close, the nav bar) NavSkipFirst.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Gui = require(script.Parent.Gui)
local State = require(script.Parent.State)

local PadNav = {}
local mods

local player = Players.LocalPlayer
local roots = setmetatable({}, { __mode = "k" }) -- GuiObject or ScreenGui -> opts
local seq = 0
local pad = false
local current = nil -- the root that has the controller
local bound = false
local pauseBound = false

local ACTION = "SpikeRushPadNav"
local PAUSE = "SpikeRushPadPause"
local HUGE = 0.3 -- a button covering more of the screen than this is a click-anywhere catcher

-- Register a root. opts: prio (default 1), back(), first (a button, or a function returning one),
-- when() (only while it's true), press() (A when nothing is selected: noSelect roots), noSelect,
-- y(), x(). Returns opts (change them later through it or PadNav.set).
function PadNav.root(obj, opts)
	opts = opts or {}
	opts.prio = opts.prio or 1
	seq = seq + 1
	opts.seq = seq
	opts.shownAt = 0
	roots[obj] = opts
	if obj:IsA("GuiObject") then
		obj.SelectionGroup = true
		obj.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
		obj.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
		obj.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
		obj.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
		obj:GetPropertyChangedSignal("Visible"):Connect(function()
			if obj.Visible then
				opts.shownAt = os.clock()
				opts.last = nil
			end
		end)
	end
	return opts
end

function PadNav.set(obj, key, value)
	local o = roots[obj]
	if o then
		o[key] = value
	end
end

-- Whether the controller is in use (or Studio's ForcePad workspace attribute, for tests).
function PadNav.usingPad()
	return pad or workspace:GetAttribute("ForcePad") == true
end

-- The root that has the controller right now (nil while you play).
function PadNav.current()
	return current
end

local function onScreen(obj)
	local o = obj
	while o do
		if o:IsA("GuiObject") then
			if not o.Visible then
				return false
			end
		elseif o:IsA("LayerCollector") then
			return o.Enabled
		end
		o = o.Parent
	end
	return false
end

local function screenArea()
	local cam = workspace.CurrentCamera
	local vs = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	return math.max(1, vs.X * vs.Y)
end

local function usable(b, root)
	if not (b:IsA("GuiButton") or b:IsA("TextBox")) or not b.Selectable or b:GetAttribute("NoNav") then
		return false
	end
	if b == root or not b:IsDescendantOf(root) then
		return false
	end
	local s = b.AbsoluteSize
	if s.X < 4 or s.Y < 4 then
		return false
	end
	if s.X * s.Y > HUGE * screenArea() then
		b.Selectable = false -- a click-anywhere catcher: Roblox's navigation skips it from now on
		return false
	end
	return onScreen(b)
end

-- The button a root starts on: its `first`, a NavFirst one, else the top-left one (in rows), with
-- the corner buttons (NavSkipFirst) only when there's nothing else.
local function pick(root, o)
	local first = o.first
	if type(first) == "function" then
		first = first()
	end
	if first and usable(first, root) then
		return first
	end
	local best, bestKey, fallback = nil, nil, nil
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("GuiButton") or d:IsA("TextBox")) and usable(d, root) then
			if d:GetAttribute("NavFirst") then
				return d
			end
			if d:GetAttribute("NavSkipFirst") then
				fallback = fallback or d
			else
				local p = d.AbsolutePosition
				local key = math.floor(p.Y / 40) * 100000 + p.X
				if not bestKey or key < bestKey then
					best, bestKey = d, key
				end
			end
		end
	end
	return best or fallback
end

local function activeRoot()
	local best, bo = nil, nil
	for obj, o in pairs(roots) do
		if obj.Parent and onScreen(obj) and (not o.when or o.when()) then
			if not bo or o.prio > bo.prio or (o.prio == bo.prio and (o.shownAt > bo.shownAt or (o.shownAt == bo.shownAt and o.seq > bo.seq))) then
				best, bo = obj, o
			end
		end
	end
	return best, bo
end

-- The tab rows showing in a root, top to bottom (Gui.tabGroups: tabs, chips, segmented, plates).
local function tabRows(root)
	local list = {}
	for f, g in pairs(Gui.tabGroups) do
		if f.Parent and f:IsDescendantOf(root) and onScreen(f) then
			table.insert(list, { frame = f, group = g })
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = a.frame.AbsolutePosition, b.frame.AbsolutePosition
		if math.abs(pa.Y - pb.Y) > 8 then
			return pa.Y < pb.Y
		end
		return pa.X < pb.X
	end)
	return list
end

local function cycleTabs(root, row, dir)
	local rows = tabRows(root)
	local r = rows[row]
	if not r then
		return false
	end
	local g = r.group
	local n = #g.keys
	if n < 2 then
		return false
	end
	local i = table.find(g.keys, g.current) or 1
	i = (i - 1 + dir) % n + 1
	Gui.click("UISelect")
	g.pick(g.keys[i])
	return true
end

local function handle(_, inputState, input)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local root = current
	local o = root and roots[root]
	if not o then
		return Enum.ContextActionResult.Pass
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.ButtonB then
		if o.back then
			Gui.click()
			o.back()
		end
	elseif k == Enum.KeyCode.ButtonL1 or k == Enum.KeyCode.ButtonR1 then
		cycleTabs(root, 1, k == Enum.KeyCode.ButtonR1 and 1 or -1)
	elseif k == Enum.KeyCode.ButtonL2 or k == Enum.KeyCode.ButtonR2 then
		cycleTabs(root, 2, k == Enum.KeyCode.ButtonR2 and 1 or -1)
	elseif k == Enum.KeyCode.ButtonY then
		if o.y then
			o.y()
		end
	elseif k == Enum.KeyCode.ButtonX then
		if o.x then
			o.x()
		end
	elseif k == Enum.KeyCode.ButtonA then
		if o.press then
			o.press()
		end
	end
	return Enum.ContextActionResult.Sink
end

local function bind(o)
	ContextActionService:UnbindAction(ACTION)
	local keys = { Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2 }
	if o.y then
		table.insert(keys, Enum.KeyCode.ButtonY)
	end
	if o.x then
		table.insert(keys, Enum.KeyCode.ButtonX)
	end
	if o.noSelect and o.press then
		table.insert(keys, Enum.KeyCode.ButtonA)
	end
	ContextActionService:BindActionAtPriority(ACTION, handle, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(keys))
	bound = true
end

local function unbind()
	if bound then
		ContextActionService:UnbindAction(ACTION)
		bound = false
	end
end

-- In a match, D-pad down opens the settings panel (B closes it). Bound only while you play with
-- nothing open, so it never gets in the way of moving through a panel.
local function pause(_, inputState)
	if inputState == Enum.UserInputState.Begin and mods and mods.UIController then
		mods.UIController.toggleSettings()
	end
	return Enum.ContextActionResult.Sink
end

local function setPause(on)
	if on == pauseBound then
		return
	end
	pauseBound = on
	if on then
		ContextActionService:BindActionAtPriority(PAUSE, pause, false, Enum.ContextActionPriority.Medium.Value, Enum.KeyCode.DPadDown)
	else
		ContextActionService:UnbindAction(PAUSE)
	end
end

local function ours(obj)
	return obj ~= nil and obj:IsDescendantOf(player.PlayerGui)
end

local function step()
	local root, o = nil, nil
	if PadNav.usingPad() then
		root, o = activeRoot()
	end
	if root ~= current then
		current = root
		if root then
			bind(o)
		else
			unbind()
		end
	end
	setPause(root == nil and PadNav.usingPad() and State.isPlaying)
	local sel = GuiService.SelectedObject
	if not root or o.noSelect then
		if ours(sel) then
			GuiService.SelectedObject = nil
		end
		return
	end
	if sel and usable(sel, root) then
		o.last = sel
		return
	end
	local nextSel = (o.last and usable(o.last, root)) and o.last or nil
	if not nextSel and os.clock() - (o.emptyAt or 0) > 0.25 then
		nextSel = pick(root, o)
		o.emptyAt = nextSel and 0 or os.clock() -- nothing to select yet: look again in a moment
	end
	if nextSel and nextSel ~= sel then
		GuiService.SelectedObject = nextSel
	end
end

local function setPad(t)
	local name = t and t.Name or ""
	if string.sub(name, 1, 7) == "Gamepad" then
		pad = true
	elseif t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseWheel then
		pad = false
	end
end

function PadNav.init(m)
	mods = m
	-- the Select button is the game's timeout, not Roblox's "select a button" toggle
	pcall(function()
		GuiService.AutoSelectGuiEnabled = false
	end)
	-- the selection's outline: signal yellow, rounded
	local ring = Instance.new("Frame")
	ring.Name = "PadSelection"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Gui.SIGNAL
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = ring
	pcall(function()
		player:WaitForChild("PlayerGui").SelectionImageObject = ring
	end)
	setPad(UserInputService:GetLastInputType())
	UserInputService.LastInputTypeChanged:Connect(setPad)
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			warn("[SpikeRush] pad navigation: " .. tostring(err))
		end
	end)
end

return PadNav
