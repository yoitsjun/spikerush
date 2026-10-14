-- HUD pieces you can move and size on touch (the owner: "allow full menu tweaking... not just
-- play buttons"): the scoreboard, the attack readout, Forfeit, Timeout, Settings, the quick chat
-- button, the ability badges and the practice coach (Config.Settings.Hud). The touch layout
-- editor (MobileControls) drags and sizes them with the buttons; they're saved with your settings
-- (State.settings.hudLayout: key -> { x, y, size }, x and y a shift as a fraction of the screen).
--
-- Each piece is wrapped in a see-through full-screen frame that the shift moves, so the code that
-- places the piece (the badges move every frame) keeps working inside it; the size is a UIScale
-- on the piece (around its anchor point). A piece that already has its own UIScale (the badges,
-- the coach) multiplies its scale by size(key) instead. Only on touch: a keyboard or controller
-- player sees the usual layout.

local State = require(script.Parent.State)

local HudLayout = {}

local pieces = {} -- key -> { frame, wrap, scale (ours, or nil when the piece scales itself) }
local preview = nil -- the editor's layout while it's open

local function layoutOf(key)
	if not State.isMobile then
		return nil
	end
	local layout = preview or State.settings.hudLayout or {}
	return layout[key]
end

local function apply(key)
	local p = pieces[key]
	if not p then
		return
	end
	local l = layoutOf(key)
	p.wrap.Position = UDim2.fromScale(l and l.x or 0, l and l.y or 0)
	if p.scale then
		p.scale.Scale = l and l.size or 1
	end
end

-- Puts `frame` (a HUD piece, already parented) under its mover. `ownScale`: the piece sets its own
-- UIScale, so only its shift is ours (it multiplies by HudLayout.size).
function HudLayout.register(key, frame, ownScale)
	if pieces[key] or not frame or not frame.Parent then
		return
	end
	local wrap = Instance.new("Frame")
	wrap.Name = "Move" .. key
	wrap.Size = UDim2.fromScale(1, 1)
	wrap.BackgroundTransparency = 1
	wrap.BorderSizePixel = 0
	wrap.ZIndex = frame.ZIndex
	wrap.Parent = frame.Parent
	frame.Parent = wrap
	local scale = nil
	if not ownScale then
		scale = Instance.new("UIScale")
		scale.Name = "HudSize"
		scale.Parent = frame
	end
	pieces[key] = { frame = frame, wrap = wrap, scale = scale }
	apply(key)
end

-- A piece's size (1: as usual), for a piece that scales itself.
function HudLayout.size(key)
	local l = layoutOf(key)
	return l and l.size or 1
end

-- The piece's frame (for the editor's handle), or nil when it isn't built.
function HudLayout.frame(key)
	local p = pieces[key]
	return p and p.frame
end

-- The screen a piece moves across: the ScreenGui it sits in (its AbsoluteSize is what a shift of
-- 1 means).
function HudLayout.screen(key)
	local p = pieces[key]
	return p and p.wrap:FindFirstAncestorWhichIsA("ScreenGui")
end

function HudLayout.applyAll()
	for key in pairs(pieces) do
		apply(key)
	end
end

-- The editor's layout while it's open (nil: back to the saved one).
function HudLayout.setPreview(layout)
	preview = layout
	HudLayout.applyAll()
end

State.signals.Settings:Connect(function(key)
	if key == "hudLayout" and not preview then
		HudLayout.applyAll()
	end
end)

return HudLayout
