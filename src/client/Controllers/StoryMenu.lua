-- Story mode's screens (Config.Story, the Story module; the owner, 2026-11-10, after The Spike
-- Cross's):
--   * Home's Story plate, right above the Match plate: "Story 1 - 2" and the next stage's name;
--   * the chapter select: the seasons down the left with their stars, each chapter a tall card
--     with its stars in a pill and "CHAPTER 1" over its name;
--   * a chapter's stages: the list down the left (number, name, three stars; a padlock and
--     "? ? ?" on the ones not open yet, gold on the big matches), the other team's three
--     players on the right, who plays beside you, the three goals, the Reward box (First Clear,
--     First 3 Stars) and Enter;
--   * the result after a stage: its three goals lighting up, the score, what it paid.
-- Enter plays the stage's opening scene (StoryDialogue, StoryScript), then the match starts
-- (LobbyService's "story"); after a win its closing scene plays. A reading-only stage is cleared
-- by reading it ("storyRead").

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Story = require(Shared.Story)
local StoryScript = require(Shared.StoryScript)
local StoryLook = require(Shared.StoryLook)
local Roster = require(Shared.Roster)
local Characters = require(Shared.Characters)
local Assets = require(Shared.Assets)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local StoryMenu = {}
local ST = Config.Story
local mods, kit

local player = Players.LocalPlayer
local make = Gui.make
local gui, canvas, canvasScale, blur
local ui = { rows = {}, cards = {}, seasons = {} }
local view = "chapters"
local chapter = Story.chapters()[1]
local selected = nil -- the stage picked in the list (its key)
local pending = nil -- a result waiting for the menus to come back
local entering = false
local rigs = {} -- "id|kit" -> a built rig's model (cloned into each portrait), or false
local W, H = 1500, 800 -- the screens' own box, centred on the canvas

local STAR_OFF = Color3.fromRGB(70, 74, 92)
local GOLD_ROW = Color3.fromRGB(255, 206, 96)

local function tween(obj, time, props, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function label(parent, props)
	props.ZIndex = props.ZIndex or 3
	return Gui.label(parent, props)
end

-- A line of word at the bottom of the Story screens (the menus' own toast is behind them).
local function note(msg)
	local l = ui.note
	if not l then
		return
	end
	ui.noteGen = (ui.noteGen or 0) + 1
	local gen = ui.noteGen
	l.Text = msg
	l.TextTransparency = 0
	l.Visible = true
	task.delay(2.2, function()
		if ui.noteGen == gen then
			tween(l, 0.3, { TextTransparency = 1 })
		end
	end)
end

local function progress()
	local p = kit and kit.profile() or nil
	return (p and p.story) or { stars = {} }
end

-- Three stars in a row; returns a setter(n).
local function starRow(parent, size, props)
	local f = make("Frame", { Size = UDim2.fromOffset(size * 3 + 12, size), BackgroundTransparency = 1, ZIndex = 3 }, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	local stars = {}
	for i = 1, 3 do
		stars[i] = Gui.iconImage(f, "IconStar", size, STAR_OFF, { Position = UDim2.fromOffset((i - 1) * (size + 6), 0), ZIndex = f.ZIndex })
	end
	return function(n)
		for i = 1, 3 do
			stars[i].ImageColor3 = i <= n and Gui.GOLD or STAR_OFF
		end
	end, f, stars
end

------------------------------------------------------------------------------------------
-- portraits: a cast member's rig in a small viewport
------------------------------------------------------------------------------------------

-- Fill `vp` with a cast member, framed from the chest up (or `full`: head to toe), in `pose`.
local function portrait(vp, id, kitKey, pose, full)
	local key = id .. "|" .. tostring(kitKey)
	task.spawn(function()
		if rigs[key] == nil then
			rigs[key] = false
			local shirt, shorts = nil, nil
			local k = kitKey and ST.Kits[kitKey]
			if k and not ST.Cast[id] then
				shirt, shorts = k[1], k[2] -- (a character with no look of its own wears its team's kit)
			end
			local ok, model = pcall(StoryLook.build, id, shirt, shorts)
			rigs[key] = (ok and model) or false
		end
		local t0 = os.clock()
		while rigs[key] == false and os.clock() - t0 < 10 do
			task.wait(0.1) -- (another portrait is building the same one)
		end
		local src = rigs[key]
		if not src or vp:GetAttribute("Face") ~= key then
			return
		end
		for _, c in ipairs(vp:GetChildren()) do
			if c:IsA("Model") or c:IsA("Camera") then
				c:Destroy()
			end
		end
		local rig = mods.AnimationController.rig(src:Clone())
		if not rig then
			return
		end
		local poses = mods.StoryDialogue.poses()
		mods.AnimationController.poseModel(rig, poses[pose or "Idle"] or poses.Idle, CFrame.Angles(0, math.rad(14), 0))
		rig.model.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		if full then
			cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.2, -13.5), Vector3.new(0, 0.2, 0))
		else
			cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.5, -5.8), Vector3.new(0, 1.5, 0))
		end
		cam.Parent = vp
		vp.CurrentCamera = cam
	end)
end

local function setPortrait(vp, id, kitKey, pose, full)
	local key = id .. "|" .. tostring(kitKey)
	if vp:GetAttribute("Face") == key then
		return
	end
	vp:SetAttribute("Face", key)
	for _, c in ipairs(vp:GetChildren()) do
		if c:IsA("Model") then
			c:Destroy()
		end
	end
	portrait(vp, id, kitKey, pose, full)
end

local function viewport(parent, props)
	local vp = make("ViewportFrame", { BackgroundTransparency = 1, Ambient = Color3.fromRGB(150, 150, 164), LightColor = Color3.fromRGB(255, 244, 226), LightDirection = Vector3.new(-0.45, -0.6, 0.65), ZIndex = 3 }, parent)
	for k, v in pairs(props or {}) do
		vp[k] = v
	end
	return vp
end

------------------------------------------------------------------------------------------
-- the chapter select
------------------------------------------------------------------------------------------

local showStages -- (below)

local function buildChapters(root)
	local v = make("Frame", { Name = "Chapters", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, root)
	ui.chapters = v
	-- the seasons, down the left
	local col = make("Frame", { Position = UDim2.fromOffset(0, 178), Size = UDim2.fromOffset(280, 500), BackgroundTransparency = 1, ZIndex = 2 }, v)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, col)
	local function seasonRow(order, name, locked)
		local b = Gui.cardButton(col, { Size = UDim2.fromOffset(280, 76), LayoutOrder = order, ZIndex = 3 })
		local title = label(b, { Text = name, display = true, TextSize = 26, TextColor3 = locked and Gui.DIM or Gui.CHALK, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 12), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
		local sub = label(b, { Text = locked and "Locked" or "", TextSize = 17, TextColor3 = locked and Gui.DIM or Gui.GOLD, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 44), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
		if locked then
			b.Active = false
			b.BackgroundTransparency = 0.6
			b:SetAttribute("NoNav", true)
		else
			make("UIStroke", { Color = Gui.CHALK, Thickness = 2, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		end
		return { button = b, title = title, sub = sub }
	end
	for i, s in ipairs(ST.Seasons) do
		ui.seasons[s.Key] = seasonRow(i, s.Name, false)
	end
	seasonRow(#ST.Seasons + 1, "Season " .. (#ST.Seasons + 1), true)

	-- the chapters, a row of tall cards
	local row = make("ScrollingFrame", { Position = UDim2.fromOffset(320, 130), Size = UDim2.fromOffset(W - 320, 560), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = Gui.DIM, ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ZIndex = 2 }, v)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, row)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, row)
	local function chapterCard(order, ch, number)
		local color = ch and ch.Color or Color3.fromRGB(60, 64, 84)
		local b = make("TextButton", { Size = UDim2.fromOffset(330, 520), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = order, ClipsDescendants = true, ZIndex = 3 }, row)
		Gui.corner(b, 10)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.25)), ColorSequenceKeypoint.new(0.55, color:Lerp(Color3.new(0, 0, 0), 0.35)), ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 12, 22)) }) }, b)
		local edge = make("UIStroke", { Color = Gui.CHALK, Thickness = 1.5, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local scale = make("UIScale", {}, b)
		local c = { button = b }
		if ch then
			-- the chapter's lead, big, behind the words
			c.vp = viewport(b, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 10), Size = UDim2.fromOffset(420, 560), ZIndex = 3 })
			setPortrait(c.vp, ch.Face or ch.Stages[1].As or "riku", nil, ch.FacePose or "Fist", false) -- (Face: chapter 2's is its rival)
		else
			label(b, { Text = "?", display = true, weight = Enum.FontWeight.Heavy, TextSize = 190, TextColor3 = Color3.fromRGB(28, 30, 44), Size = UDim2.new(1, 0, 0, 260), Position = UDim2.fromOffset(0, 110), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		end
		-- the words sit on a shade at the bottom
		local shade = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 220), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 4 }, b)
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 0.25), NumberSequenceKeypoint.new(1, 0.05) }) }, shade)
		local pill = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(132, 36), BackgroundColor3 = Color3.fromRGB(8, 10, 20), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 5 }, b)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
		Gui.iconImage(pill, "IconStar", 20, Gui.GOLD, { Position = UDim2.fromOffset(16, 8), ZIndex = 6 })
		c.stars = label(pill, { Text = ch and "" or "Soon", display = true, TextSize = 20, TextColor3 = Gui.GOLD, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -52, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
		local numText = ch and (ch.Header or ("CHAPTER " .. ch.Number)) or ("CHAPTER " .. (number or order))
		label(b, { Text = numText, display = true, TextSize = 24, TextColor3 = Gui.GOLD, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -64), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
		-- gold rules either side of "CHAPTER 1"
		for _, x in ipairs({ 0.14, 0.86 }) do
			make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 1, -78), Size = UDim2.fromOffset(54, 2), BackgroundColor3 = Gui.GOLD, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 5 }, b)
		end
		label(b, { Text = ch and ch.Name or "Coming soon", display = true, weight = Enum.FontWeight.Heavy, TextSize = 32, TextColor3 = ch and Gui.CHALK or Gui.DIM, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
		if ch then
			b.MouseEnter:Connect(function()
				edge.Transparency = 0
				tween(scale, 0.12, { Scale = 1.03 })
			end)
			b.MouseLeave:Connect(function()
				edge.Transparency = 0.5
				tween(scale, 0.12, { Scale = 1 })
			end)
			kit.onClick(b, function()
				if Story.chapterOpen(progress(), ch) then
					chapter = ch
					selected = nil
					showStages()
				else
					note("Finish the chapter before it first.")
				end
			end)
			b:SetAttribute("NavFirst", order == 1)
		else
			b.Active = false
			b:SetAttribute("NoNav", true)
		end
		return c
	end
	local main = 0
	for i, ch in ipairs(Story.chapters()) do
		ui.cards[ch.Key] = chapterCard(i, ch)
		main = main + ((not ch.Side) and 1 or 0)
	end
	-- (the next chapter's number counts the main story's only, not a side one's)
	chapterCard(#Story.chapters() + 1, nil, main + 1)
end

local function refreshChapters()
	local p = progress()
	for _, s in ipairs(ST.Seasons) do
		local have, total = Story.seasonStars(p, s.Key)
		ui.seasons[s.Key].sub.Text = string.format("★ %d/%d", have, total)
	end
	for _, ch in ipairs(Story.chapters()) do
		local have, total = Story.chapterStars(p, ch)
		ui.cards[ch.Key].stars.Text = string.format("%d/%d", have, total)
	end
end

------------------------------------------------------------------------------------------
-- a chapter's stages
------------------------------------------------------------------------------------------

local refreshStages

local function buildStages(root)
	local v = make("Frame", { Name = "Stages", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 2 }, root)
	ui.stages = v
	-- the chapter's name across the top
	local bar = make("Frame", { Position = UDim2.fromOffset(200, 84), Size = UDim2.fromOffset(W - 400, 46), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 2 }, v)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1) }) }, bar)
	ui.chapterName = label(bar, { Text = "", RichText = true, display = true, TextSize = 28, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })

	-- the stages, down the left
	local list = Gui.card(v, { Position = UDim2.fromOffset(0, 146), Size = UDim2.fromOffset(520, H - 146), ZIndex = 2 })
	local scroll = make("ScrollingFrame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = Gui.DIM, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 3 }, list)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	ui.list = scroll

	-- the other team, and who you play as
	local info = Gui.card(v, { Position = UDim2.fromOffset(546, 146), Size = UDim2.fromOffset(W - 546, 356), ZIndex = 2 })
	ui.versus = label(info, { Text = "", display = true, TextSize = 26, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center })
	ui.foes = {}
	for i = 1, 3 do
		local c = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, (i - 2) * 196, 0, 62), Size = UDim2.fromOffset(180, 214), BackgroundColor3 = Color3.fromRGB(16, 18, 34), BackgroundTransparency = 0.2, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 3 }, info)
		make("UIStroke", { Color = Gui.CHALK, Thickness = 1, Transparency = 0.75, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, c)
		local vp = viewport(c, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(214, 214), ZIndex = 3 })
		local shade = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 4 }, c)
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0.15) }, shade)
		local name = label(c, { Text = "", display = true, TextSize = 22, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -6), Size = UDim2.new(1, -20, 0, 26), ZIndex = 5 })
		local tier = label(c, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 26, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(60, 28), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 })
		local role = label(c, { Text = "", display = true, TextSize = 17, TextColor3 = Gui.MUTED, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 34), Size = UDim2.fromOffset(60, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 })
		ui.foes[i] = { frame = c, vp = vp, name = name, tier = tier, role = role }
	end
	ui.storyOnly = label(info, { Text = "", TextSize = 22, TextColor3 = Gui.MUTED, TextWrapped = true, Position = UDim2.fromOffset(80, 120), Size = UDim2.new(1, -160, 0, 120), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	ui.playAs = label(info, { Text = "", RichText = true, TextSize = 19, TextColor3 = Gui.MUTED, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	ui.rules = label(info, { Text = "", TextSize = 17, TextColor3 = Gui.DIM, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -10), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })

	-- the three goals
	local goals = Gui.card(v, { Position = UDim2.fromOffset(546, 514), Size = UDim2.fromOffset(W - 546, 132), ZIndex = 2 })
	ui.goals = {}
	for i = 1, 3 do
		local star = Gui.iconImage(goals, "IconStar", 26, STAR_OFF, { Position = UDim2.fromOffset(24, 14 + (i - 1) * 38), ZIndex = 3 })
		local text = label(goals, { Text = "", TextSize = 21, Position = UDim2.fromOffset(64, 12 + (i - 1) * 38), Size = UDim2.new(1, -90, 0, 30) })
		ui.goals[i] = { star = star, text = text }
	end

	-- the rewards, and Enter
	local reward = Gui.card(v, { Position = UDim2.fromOffset(546, 658), Size = UDim2.fromOffset(580, H - 658), ZIndex = 2 })
	label(reward, { Text = "REWARD", display = true, TextSize = 17, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	ui.rewards = {}
	for i, title in ipairs({ "First Clear", "First 3 Stars" }) do
		local slot = make("Frame", { Position = UDim2.fromOffset(16 + (i - 1) * 278, 34), Size = UDim2.fromOffset(270, 94), BackgroundColor3 = Color3.fromRGB(16, 18, 34), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3 }, reward)
		local stroke = make("UIStroke", { Color = Gui.CHALK, Thickness = 1, Transparency = 0.75, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, slot)
		local text = label(slot, { Text = "", RichText = true, display = true, TextSize = 21, TextWrapped = true, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 52), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
		local cap = label(slot, { Text = title, TextSize = 16, TextColor3 = Gui.MUTED, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
		ui.rewards[i] = { slot = slot, stroke = stroke, text = text, cap = cap, title = title }
	end
	local enterB, enterL = kit.actionPlate(v, { Name = "Enter", Position = UDim2.fromOffset(1150, 676), Size = UDim2.fromOffset(W - 1150, 100), ZIndex = 3 }, "Enter", 44)
	enterL.ZIndex = 6 -- (over the plate)
	ui.enter = { button = enterB, label = enterL }
	ui.enter.button:SetAttribute("NavFirst", true)
	kit.onClick(ui.enter.button, function()
		StoryMenu.enter()
	end)
end

-- A stage's row in the list (built once per stage of the chapter shown).
local function stageRow(stage, n)
	local b = make("TextButton", { Size = UDim2.new(1, -8, 0, 48), BackgroundColor3 = GOLD_ROW, BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = n, ZIndex = 3 }, ui.list)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.7) }) }, b)
	local lock = Gui.iconImage(b, "IconLock", 22, Gui.CHALK, { Position = UDim2.fromOffset(14, 13), ZIndex = 4 })
	local num = label(b, { Text = n .. ".", display = true, TextSize = 22, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(40, 48), ZIndex = 4 })
	local name = label(b, { Text = "", display = true, TextSize = 23, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -180, 1, 0), ZIndex = 4 })
	local setStars = starRow(b, 24, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), ZIndex = 4 })
	local row = { button = b, lock = lock, num = num, name = name, setStars = setStars, stage = stage }
	kit.onClick(b, function()
		if Story.unlocked(progress(), stage.Key) then
			selected = stage.Key
			refreshStages()
		else
			note("Clear the stage before it first.")
		end
	end)
	return row
end

local function fillList()
	if ui.listOf == chapter.Key then
		return
	end
	ui.listOf = chapter.Key
	for _, r in pairs(ui.rows) do
		r.button:Destroy()
	end
	ui.rows = {}
	for n, s in ipairs(chapter.Stages) do
		ui.rows[s.Key] = stageRow(s, n)
	end
end

refreshStages = function()
	local p = progress()
	fillList()
	if not selected or not Story.stage(selected) or select(2, Story.stage(selected)) ~= chapter then
		-- the next stage to play in this chapter, else its last
		local nxt = Story.next(p)
		local _, nch = Story.stage(nxt and nxt.Key or "")
		selected = (nch == chapter) and nxt.Key or chapter.Stages[#chapter.Stages].Key
		for _, s in ipairs(chapter.Stages) do
			if not Story.cleared(p, s.Key) then
				selected = s.Key
				break
			end
		end
	end
	ui.chapterName.Text = string.format('<font color="#FFC428">%s</font>   %s', chapter.Tag or tostring(chapter.Number), chapter.Name)
	for key, r in pairs(ui.rows) do
		local open = Story.unlocked(p, key)
		local gold = r.stage.Gold == true
		local on = key == selected
		r.lock.Visible = not open
		r.num.Visible = open
		r.name.Text = open and r.stage.Name or "? ? ?"
		local color = gold and GOLD_ROW or Gui.CHALK
		r.name.TextColor3 = on and Gui.LINE or (open and color or color:Lerp(Color3.new(0, 0, 0), 0.35))
		r.num.TextColor3 = on and Gui.LINE or color
		r.lock.ImageColor3 = gold and GOLD_ROW or Gui.MUTED
		r.button.BackgroundTransparency = on and 0 or 1
		r.setStars(Story.stars(p, key))
	end
	local stage = Story.stage(selected)
	local isMatch = Story.isMatch(stage)
	ui.versus.Text = isMatch and ("vs " .. stage.Versus) or stage.Name
	local foes = Story.foes(stage)
	for i = 1, 3 do
		local f = ui.foes[i]
		local e = foes[i]
		f.frame.Visible = isMatch and e ~= nil
		if isMatch and e then
			f.name.Text = e.name
			f.tier.Text = e.tier
			f.tier.TextColor3 = Characters.color(e.tier)
			f.role.Text = e.role
			setPortrait(f.vp, e.id, stage.Kit, "Idle", false)
		end
	end
	ui.storyOnly.Visible = not isMatch
	ui.storyOnly.Text = "A story stage: no match to play. Read it to the end to clear it."
	if isMatch then
		-- (your own character: the owner, 2026-11-11, "story mode shouldn't lock your character")
		local mates = {}
		for _, id in ipairs(stage.Mates or {}) do
			local ab = stage.MateAbilities and stage.MateAbilities[id]
			local def = ab and Config.Abilities[ab]
			table.insert(mates, Story.castName(id) .. (def and (" (" .. def.Name .. ")") or ""))
		end
		if stage.Lock then
			ui.playAs.Text = string.format('You play as <font color="#FFFFFF"><b>your own character</b></font>, with %s <font color="#FFD63C">(a story stage: they\'re your team)</font>.', table.concat(mates, " and "))
		else
			ui.playAs.Text = 'You play with <font color="#FFFFFF"><b>your own team</b></font>.'
		end
		local court = Config.Courts.List[stage.Court]
		ui.rules.Text = string.format("First to %d points  ·  %s", stage.Points, court and court.Name or "")
	else
		ui.playAs.Text = ""
		ui.rules.Text = ""
	end
	local stars = Story.stars(p, selected)
	local goals = Story.goals(stage)
	for i = 1, 3 do
		ui.goals[i].text.Text = goals[i]
		ui.goals[i].text.TextColor3 = i <= stars and Gui.CHALK or Gui.MUTED
		ui.goals[i].star.ImageColor3 = i <= stars and Gui.GOLD or STAR_OFF
	end
	local grants = { stage.First, stage.Three }
	local got = { stars >= 1, stars >= 3 }
	for i = 1, 2 do
		local r = ui.rewards[i]
		local g = grants[i]
		if not g then
			r.text.Text = '<font color="#96A4CC">None</font>'
			r.cap.Text = r.title
		elseif got[i] then
			r.text.Text = '<font color="#96A4CC">' .. Story.grantText(g) .. "</font>"
			r.cap.Text = r.title .. "  ✓ claimed"
		else
			r.text.Text = '<font color="#FFC428">' .. Story.grantText(g) .. "</font>"
			r.cap.Text = r.title
		end
		r.stroke.Color = (g and not got[i]) and Gui.GOLD or Gui.CHALK
		r.stroke.Transparency = (g and not got[i]) and 0.3 or 0.75
	end
	ui.enter.label.Text = isMatch and (stars >= 1 and "Replay" or "Enter") or (stars >= 1 and "Read again" or "Read")
end

showStages = function()
	view = "stages"
	ui.chapters.Visible = false
	ui.stages.Visible = true
	refreshStages()
end

local function showChapters()
	view = "chapters"
	ui.stages.Visible = false
	ui.chapters.Visible = true
	refreshChapters()
end

------------------------------------------------------------------------------------------
-- the result
------------------------------------------------------------------------------------------

local function buildResult(root)
	local r = make("Frame", { Name = "Result", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 10 }, root)
	ui.result = r
	local head = label(r, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 84, Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 96), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	local sub = label(r, { Text = "", display = true, TextSize = 26, TextColor3 = Gui.MUTED, Position = UDim2.fromOffset(0, 168), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	local rows = {}
	for i = 1, 3 do
		local row = make("Frame", { Position = UDim2.fromOffset(170, 250 + (i - 1) * 86), Size = UDim2.fromOffset(660, 64), BackgroundColor3 = GOLD_ROW, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 11 }, r)
		make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }) }, row)
		make("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = Gui.CHALK, BorderSizePixel = 0, ZIndex = 12 }, row)
		local star = Gui.iconImage(row, "IconStar", 38, STAR_OFF, { Position = UDim2.fromOffset(24, 13), ZIndex = 12 })
		local sscale = make("UIScale", {}, star)
		local text = label(row, { Text = "", display = true, TextSize = 30, Position = UDim2.fromOffset(84, 0), Size = UDim2.new(1, -90, 1, 0), ZIndex = 12 })
		rows[i] = { row = row, star = star, scale = sscale, text = text }
	end
	local total = Gui.card(r, { Position = UDim2.fromOffset(900, 250), Size = UDim2.fromOffset(430, 236), ZIndex = 11 })
	make("Frame", { Position = UDim2.fromOffset(22, 20), Size = UDim2.fromOffset(4, 30), BackgroundColor3 = Gui.SIGNAL, BorderSizePixel = 0, ZIndex = 12 }, total)
	label(total, { Text = "Total", display = true, TextSize = 30, Position = UDim2.fromOffset(38, 18), Size = UDim2.fromOffset(200, 34), ZIndex = 12 })
	local score = label(total, { Text = "", RichText = true, TextSize = 22, Position = UDim2.fromOffset(24, 66), Size = UDim2.new(1, -48, 0, 28), ZIndex = 12 })
	local paid = label(total, { Text = "", RichText = true, TextSize = 21, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(24, 104), Size = UDim2.new(1, -48, 0, 120), ZIndex = 12 })
	local retry = kit.hairButton(r, { Name = "Retry", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(1060, 560), Size = UDim2.fromOffset(190, 74), ZIndex = 12 }, "Retry", 26)
	local nextB, nextL = kit.actionPlate(r, { Name = "Next", Position = UDim2.fromOffset(1080, 552), Size = UDim2.fromOffset(250, 90), ZIndex = 12 }, "Next", 40)
	nextB:SetAttribute("NavFirst", true)
	nextL.ZIndex = 15
	ui.res = { head = head, sub = sub, rows = rows, score = score, paid = paid, retry = retry, next = { button = nextB, label = nextL } }
end

-- Show a stage's result (the Story remote's message), then `after` on Next.
local function showResult(m)
	local stage = Story.stage(m.key)
	if not stage then
		return
	end
	local R = ui.res
	local isMatch = Story.isMatch(stage)
	local won = m.kind == "read" or m.won == true or m.clear == true -- (clear: a stage the story loses, cleared on its points)
	gui.Enabled = true
	StoryMenu.cover(true)
	ui.chapters.Visible = false
	ui.stages.Visible = false
	ui.header.Visible = false
	ui.result.Visible = true
	R.head.Text = isMatch and (won and "STAGE CLEAR" or "DEFEAT") or "THE END"
	R.head.TextColor3 = won and Gui.CHALK or Gui.ALERT
	R.sub.Text = string.format("Story %s   %s", Story.label(m.key), stage.Name)
	local goals = Story.goals(stage)
	for i = 1, 3 do
		local row = R.rows[i]
		row.text.Text = goals[i]
		row.text.TextColor3 = Gui.MUTED
		row.star.ImageColor3 = STAR_OFF
		row.row.BackgroundTransparency = 1
		row.row.Visible = isMatch or i == 1
	end
	R.score.Text = isMatch and string.format('Score   <font color="#FFFFFF"><b>%d : %d</b></font>', m.mine or 0, m.theirs or 0) or "Story read"
	local lines = {}
	if m.first and stage.First then
		table.insert(lines, '<font color="#FFC428">First Clear</font>   ' .. Story.grantText(stage.First))
	end
	if m.three and stage.Three then
		table.insert(lines, '<font color="#FFC428">First 3 Stars</font>   ' .. Story.grantText(stage.Three))
	end
	if #lines == 0 then
		table.insert(lines, won and '<font color="#96A4CC">Already claimed</font>' or (stage.Score and '<font color="#96A4CC">Score to earn the stage\'s rewards</font>' or '<font color="#96A4CC">Win to earn the stage\'s rewards</font>'))
	end
	R.paid.Text = table.concat(lines, "\n")
	R.retry.Visible = isMatch
	R.next.label.Text = won and "Next" or "Back"
	-- the goals light up one by one
	task.spawn(function()
		for i = 1, (m.stars or 0) do
			task.wait(0.45)
			local row = R.rows[i]
			if not ui.result.Visible then
				return
			end
			row.star.ImageColor3 = Gui.GOLD
			row.text.TextColor3 = Gui.CHALK
			row.row.BackgroundTransparency = 0
			row.scale.Scale = 1.7
			tween(row.scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			if mods.AudioController then
				mods.AudioController.play("UIClick", { minGap = 0.05, volume = 0.7 })
			end
		end
	end)
	ui.resultOf = m
end

local function closeResult()
	ui.result.Visible = false
	ui.header.Visible = true
	ui.resultOf = nil
end

------------------------------------------------------------------------------------------
-- opening, entering
------------------------------------------------------------------------------------------

-- The menus hide behind the Story screens (and come back after).
function StoryMenu.cover(on)
	if mods.MenuController.cover then
		mods.MenuController.cover(on)
	end
	if blur then
		tween(blur, 0.25, { Size = on and 16 or 0 })
	end
end

function StoryMenu.close()
	if not gui.Enabled then
		return
	end
	gui.Enabled = false
	closeResult()
	StoryMenu.cover(false)
end

-- Open on the chapters, or (stages = true) straight on the next stage's chapter.
function StoryMenu.open(stages)
	if mods.StoryDialogue.active() or entering then
		return
	end
	local lobbies = kit.lobbies()
	if lobbies and lobbies.mine and not lobbies.mine.story then
		kit.toast("You're already in a lobby: leave it first.")
		return
	end
	gui.Enabled = true
	StoryMenu.cover(true)
	closeResult()
	if stages then
		local nxt = Story.next(progress())
		local _, ch = Story.stage(nxt and nxt.Key or "")
		-- (the whole story done: its last main chapter, not a side one)
		if not ch then
			for _, c in ipairs(Story.chapters()) do
				if not c.Side then
					ch = c
				end
			end
		end
		chapter = ch or Story.chapters()[1]
		selected = nxt and nxt.Key or nil
		showStages()
	else
		showChapters()
	end
end

-- Story mode open on chapter `key`'s stages (the Winter window's Story tab), on `stageKey` when
-- given, else the chapter's first stage not cleared.
function StoryMenu.openChapter(key, stageKey)
	local ch = Story.chapter(key)
	if not ch or mods.StoryDialogue.active() or entering then
		return false
	end
	local lobbies = kit.lobbies()
	if lobbies and lobbies.mine and not lobbies.mine.story then
		kit.toast("You're already in a lobby: leave it first.")
		return false
	end
	gui.Enabled = true
	StoryMenu.cover(true)
	closeResult()
	chapter = ch
	selected = nil
	local _, sch = Story.stage(stageKey or "")
	if sch == ch then
		selected = stageKey
	else
		for _, s in ipairs(ch.Stages) do
			if not Story.cleared(progress(), s.Key) then
				selected = s.Key
				break
			end
		end
	end
	showStages()
	return true
end

function StoryMenu.shown()
	return gui ~= nil and gui.Enabled
end

local function back()
	if ui.result.Visible then
		return
	end
	if view == "stages" then
		showChapters()
	else
		StoryMenu.close()
	end
end

-- Enter the stage picked: its opening scene, then the match (or, for a reading-only stage, the
-- stage is cleared as the scene ends).
function StoryMenu.enter(key)
	key = key or selected
	local stage = Story.stage(key)
	if not stage or entering or mods.StoryDialogue.active() then
		return
	end
	if not Story.unlocked(progress(), key) then
		note("Clear the stage before it first.")
		return
	end
	entering = true
	gui.Enabled = false
	closeResult()
	if blur then
		blur.Size = 0
	end
	local scene = StoryScript[key] and StoryScript[key].intro or {}
	local started = mods.StoryDialogue.play(scene, { title = { label = "Story " .. Story.label(key), name = stage.Name } }, function()
		entering = false
		if Story.isMatch(stage) then
			Net.get("Lobby"):FireServer("story", key)
		else
			Net.get("Lobby"):FireServer("storyRead", key)
		end
	end)
	if not started then
		entering = false
	end
end

-- A stage's result arrived: show it once the menus are back (the match's own showcase first).
local function onResult(m)
	if type(m) ~= "table" or not Story.stage(m.key) then
		return
	end
	pending = m
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 60 do
			if pending ~= m then
				return
			end
			if mods.MenuController.shown() and not mods.StoryDialogue.active() and not State.isPlaying then
				break
			end
			task.wait(0.2)
		end
		if pending ~= m then
			return
		end
		pending = nil
		showResult(m)
	end)
end

local function onNext()
	local m = ui.resultOf
	if not m then
		return
	end
	local stage = Story.stage(m.key)
	local won = m.kind == "read" or m.won == true or m.clear == true -- (clear: a stage the story loses, cleared on its points)
	closeResult()
	local function toList()
		gui.Enabled = true
		StoryMenu.cover(true)
		local _, ch = Story.stage(m.key)
		chapter = ch
		selected = nil
		showStages()
	end
	local scene = won and Story.isMatch(stage) and StoryScript[m.key] and StoryScript[m.key].outro or nil
	if scene and #scene > 0 then
		gui.Enabled = false
		if blur then
			blur.Size = 0
		end
		if not mods.StoryDialogue.play(scene, {}, toList) then
			toList()
		end
	else
		toList()
	end
end

------------------------------------------------------------------------------------------
-- Home's plate
------------------------------------------------------------------------------------------

local function buildHomePlate()
	local home = kit.canvas:FindFirstChild("home")
	local match = home and home:FindFirstChild("Match")
	if not match then
		return
	end
	-- right above the Match plate, stopping short of the column of buttons down Home's right edge
	-- (it ran under Decorate and Playtime on a short screen)
	local b = Gui.cardButton(home, { Name = "Story", AnchorPoint = Vector2.new(1, 1), Position = match.Position - UDim2.fromOffset(108, match.Size.Y.Offset + 12), Size = UDim2.fromOffset(280, 66), ZIndex = match.ZIndex })
	b.BackgroundTransparency = 0.2
	make("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = Gui.SIGNAL, BorderSizePixel = 0, ZIndex = b.ZIndex }, b)
	local top = label(b, { Text = "Story", display = true, TextSize = 24, Position = UDim2.fromOffset(20, 7), Size = UDim2.new(1, -30, 0, 28), ZIndex = b.ZIndex + 1 })
	local sub = label(b, { Text = "", TextSize = 16, TextColor3 = Gui.MUTED, Position = UDim2.fromOffset(20, 36), Size = UDim2.new(1, -30, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = b.ZIndex + 1 })
	ui.plate = { button = b, top = top, sub = sub }
	kit.onClick(b, function()
		StoryMenu.open(true)
	end)
end

local function refreshPlate()
	local pl = ui.plate
	if not pl then
		return
	end
	local nxt = Story.next(progress())
	if nxt then
		pl.top.Text = "Story " .. Story.label(nxt.Key)
		pl.sub.Text = nxt.Name
	else
		pl.top.Text = "Story"
		pl.sub.Text = "Chapter " .. chapter.Number .. " complete"
	end
end

------------------------------------------------------------------------------------------

local function layout()
	local cam = workspace.CurrentCamera
	if not cam or not canvas then
		return
	end
	local vs = cam.ViewportSize
	if vs.X < 2 or vs.Y < 2 then
		return
	end
	local s = math.clamp(vs.Y / 900, 0.4, 1.8)
	if vs.X / s < W + 60 then
		s = vs.X / (W + 60)
	end
	canvasScale.Scale = s
	canvas.Size = UDim2.fromOffset(vs.X / s, vs.Y / s)
end

local function build()
	gui = make("ScreenGui", { Name = "SpikeRushStory", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 22, Enabled = false }, player:WaitForChild("PlayerGui"))
	make("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 1 }, gui)
	canvas = make("Frame", { Name = "Canvas", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), BackgroundTransparency = 1, ZIndex = 2 }, gui)
	canvasScale = make("UIScale", {}, canvas)
	local root = make("Frame", { Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 16), Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, ZIndex = 2 }, canvas)
	ui.root = root

	-- back, and the title
	local header = make("Frame", { Name = "Header", Size = UDim2.fromOffset(600, 70), BackgroundTransparency = 1, ZIndex = 3 }, root)
	ui.header = header
	local backB = make("TextButton", { Name = "Back", Size = UDim2.fromOffset(64, 64), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 3 }, header)
	Gui.iconImage(backB, "IconBack", 44, Gui.CHALK, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 4 })
	backB:SetAttribute("NavSkipFirst", true)
	kit.onClick(backB, back)
	-- a little book: two pages and a spine
	local book = make("Frame", { Position = UDim2.fromOffset(92, 14), Size = UDim2.fromOffset(34, 38), BackgroundTransparency = 1, ZIndex = 3 }, header)
	local cover = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, book)
	Gui.corner(cover, 5)
	make("UIStroke", { Color = Gui.CHALK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, cover)
	for i = 1, 2 do
		make("Frame", { Position = UDim2.new(0, 9, 0, 6 + i * 8), Size = UDim2.new(1, -18, 0, 3), BackgroundColor3 = Gui.CHALK, BorderSizePixel = 0, ZIndex = 4 }, book)
	end
	label(header, { Text = "Story Mode", display = true, TextSize = 40, Position = UDim2.fromOffset(142, 8), Size = UDim2.fromOffset(400, 50), ZIndex = 3 })

	ui.note = label(root, { Text = "", display = true, TextSize = 24, TextColor3 = Gui.SIGNAL_HOT, TextStrokeTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 44), Size = UDim2.fromOffset(900, 30), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 15 })

	buildChapters(root)
	buildStages(root)
	buildResult(root)
	kit.onClick(ui.res.retry, function()
		local m = ui.resultOf
		closeResult()
		if m then
			StoryMenu.enter(m.key)
		end
	end)
	kit.onClick(ui.res.next.button, onNext)

	if mods.PadNav then
		mods.PadNav.root(root, { prio = 6, back = back })
	end
	blur = Instance.new("BlurEffect")
	blur.Name = "SpikeRushStoryBlur"
	blur.Size = 0
	blur.Parent = Lighting
	layout()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
end

function StoryMenu.init(m)
	mods = m
	kit = mods.MenuController.kit()
	build()
	buildHomePlate()
	refreshPlate()
	State.signals.Profile:Connect(function()
		refreshPlate()
		if gui.Enabled and not ui.result.Visible then
			if view == "stages" then
				refreshStages()
			else
				refreshChapters()
			end
		end
	end)
	Net.get("Story").OnClientEvent:Connect(onResult)
	-- a match starting (yours or anyone's on this court) puts the Story screens away
	State.signals.Announce:Connect(function(a)
		if a.kind ~= "MatchStart" then
			return
		end
		if gui.Enabled and not ui.result.Visible then
			StoryMenu.close()
		end
		-- (and the menus are never left hidden behind a Story screen that's gone)
		if not gui.Enabled and not mods.StoryDialogue.active() and mods.MenuController.cover then
			mods.MenuController.cover(false)
		end
	end)
end

-- (Studio only: setting workspace attribute TestStory to a chapter's key, e.g. "w1", plays every
-- scene of it in order, each stage's opening and, after a match, its ending, with no matches: to
-- read a chapter through. Skip moves on to the next scene.)
if game:GetService("RunService"):IsStudio() then
	workspace:GetAttributeChangedSignal("TestStory"):Connect(function()
		local ch = Story.chapter(workspace:GetAttribute("TestStory"))
		if not ch or not mods then
			return
		end
		local list = {}
		for _, st in ipairs(ch.Stages) do
			local sc = StoryScript[st.Key] or {}
			if sc.intro and #sc.intro > 0 then
				table.insert(list, { scene = sc.intro, title = { label = "Story " .. Story.label(st.Key), name = st.Name } })
			end
			if Story.isMatch(st) and sc.outro and #sc.outro > 0 then
				table.insert(list, { scene = sc.outro })
			end
		end
		local i = 0
		local function nextScene()
			i = i + 1
			local it = list[i]
			if it then
				task.delay(0.4, function()
					mods.StoryDialogue.play(it.scene, { title = it.title }, nextScene)
				end)
			else
				workspace:SetAttribute("TestStory", nil)
			end
		end
		nextScene()
	end)
end

return StoryMenu
