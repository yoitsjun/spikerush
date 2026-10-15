-- The breakthrough reveal (the owner, 2026-10-15, with Spike Cross's "Breakthrough 5 Achieved!"
-- card: "animations for breakthrough"): after a breakthrough (ProfileService sends the profile with
-- `breakReveal = { id, level }`), two beats. First the reference's splash: on near-black, your
-- avatar in the character's role pose (you play every character as yourself; Taeho holds the
-- scythe while the Reaper's on) dead centre in a glow of its tier colour, "Breakthrough N
-- Achieved!" in gold across its middle, popping in with a split-colour glitch and glitch slices
-- tearing across the picture, sparse confetti specks drifting. Then the character steps left and
-- the gains come in on the right: its "+N", name, tier and role, and what this step gave
-- (Breakthrough.describe). A click (or A) after a moment closes it.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Roster = require(Shared.Roster)
local Characters = require(Shared.Characters)
local Breakthrough = require(Shared.Breakthrough)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local BreakReveal = {}
local mods
local player = Players.LocalPlayer
local make = Gui.make
local GOLD = Color3.fromRGB(255, 214, 90)
local GOLD_LIGHT = Color3.fromRGB(255, 244, 200)
local CONFETTI = { Color3.fromRGB(255, 214, 90), Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 80, 90), Color3.fromRGB(245, 245, 255), Color3.fromRGB(190, 110, 255) }

local POSE = { WS = "Cock", MB = "Block", SE = "SetCatch" }

local current = nil -- the card on screen

local function tween(obj, time, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function tierColor(tier)
	if tier == "S+" then
		return Config.Rarity.Colors.Mythic
	end
	return Characters.color(tier)
end

-- Your avatar posed for the character's role, in a viewport (holding its skin's piece: the scythe).
local function portrait(vp, role, skin)
	local AC, SC = mods.AnimationController, mods.SceneController
	if not (AC and SC) then
		return
	end
	local rig = SC.cloneAvatar(false)
	if not rig then
		return
	end
	local hum = rig.model:FindFirstChildOfClass("Humanoid")
	local standY = (hum and hum.HipHeight or 2) + rig.root.Size.Y / 2
	AC.poseModel(rig, AC.poseJoints(POSE[role] or "ShowReady") or {}, CFrame.new(0, standY, 0))
	if skin == "Reaper" and mods.Skins then
		pcall(mods.Skins.prop, rig.model, true)
	end
	rig.model.Parent = vp
	local cam = make("Camera", { FieldOfView = 34 }, vp)
	vp.CurrentCamera = cam
	local focus = Vector3.new(0, standY + 0.4, 0)
	cam.CFrame = CFrame.lookAt(focus + Vector3.new(0.55, 0.12, -1).Unit * 12, focus)
end

local function close(card)
	if current ~= card or card.closing then
		return
	end
	card.closing = true
	tween(card.fade, 0.3, { GroupTransparency = 1 })
	task.delay(0.32, function()
		card.gui:Destroy()
		if current == card then
			current = nil
		end
	end)
end

local function show(id, level, skin)
	local c = Roster.get(id)
	if not c then
		return
	end
	if current then
		current.gui:Destroy()
		current = nil
	end
	local color = tierColor(c.Tier)
	local gui = make("ScreenGui", { Name = "SpikeRushBreakReveal", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	local fade = make("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 0 }, gui)
	local back = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 5, 10), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, fade)
	tween(back, 0.25, { BackgroundTransparency = 0.02 })
	local card = { gui = gui, fade = fade, at = os.clock() }
	current = card
	local maxed = level >= Config.Breakthrough.Max

	-- a glow of the tier colour behind the character (the reference's dark room, lit from behind)
	local halo = make("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 1.4), BackgroundTransparency = 1, Image = Assets.id(Assets.Fx.Glow) or "", ImageColor3 = color, ImageTransparency = 1 }, fade)
	tween(halo, 0.6, { ImageTransparency = 0.55 })

	-- light rays behind the character, in its tier colour, turning slowly
	local rays = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0, 0), BackgroundTransparency = 1 }, fade)
	for i = 1, 14 do
		local ray = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 10 + (i % 3) * 8, 0, 900), Rotation = i * 360 / 14, BackgroundColor3 = color, BorderSizePixel = 0, BackgroundTransparency = 0.8 }, rays)
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.75, 0.55), NumberSequenceKeypoint.new(1, 0.2) }) }, ray)
	end
	tween(rays, 8, { Rotation = 40 }, Enum.EasingStyle.Linear)

	-- the character: your avatar in its role's pose, rising into the middle
	local vp = make("ViewportFrame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromScale(0.5, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(120, 116, 140), LightColor = Color3.fromRGB(255, 244, 228), LightDirection = Vector3.new(-0.6, -0.7, 0.5), ImageTransparency = 1 }, fade)
	pcall(portrait, vp, c.Role, skin)
	tween(vp, 0.5, { Position = UDim2.fromScale(0.5, 0.52), ImageTransparency = 0 }, Enum.EasingStyle.Back)

	-- glitch slices tearing across the picture as it lands (the reference's displaced bands)
	task.spawn(function()
		local bars = {}
		for i = 1, 5 do
			local bar = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.2 + i * 0.12), Size = UDim2.new(0.42, 0, 0, math.random(4, 16)), BackgroundColor3 = i % 2 == 0 and color or Color3.fromRGB(6, 5, 10), BackgroundTransparency = i % 2 == 0 and 0.55 or 0.1, BorderSizePixel = 0, ZIndex = 3 }, fade)
			table.insert(bars, bar)
		end
		for _ = 1, 9 do
			for _, bar in ipairs(bars) do
				bar.Position = UDim2.new(0.5, math.random(-60, 60), bar.Position.Y.Scale + (math.random() - 0.5) * 0.04, 0)
				bar.Visible = math.random() < 0.7
			end
			task.wait(0.045)
		end
		for _, bar in ipairs(bars) do
			bar:Destroy()
		end
	end)

	-- "Breakthrough N Achieved!": across the character's middle, popping in, with a split-colour glitch
	local titleBox = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(0.62, 0.13), BackgroundTransparency = 1, ZIndex = 4 }, fade)
	local pop = make("UIScale", { Scale = 1.9 }, titleBox)
	local text = string.format("Breakthrough %d Achieved!", level)
	local glitches = {}
	for i, g in ipairs({ { Color3.fromRGB(80, 220, 255), -6 }, { Color3.fromRGB(255, 60, 90), 6 } }) do
		local l = Gui.label(titleBox, { Text = text, display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextColor3 = g[1], TextTransparency = 0.25, Position = UDim2.fromOffset(g[2], i == 1 and -3 or 3), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		table.insert(glitches, l)
	end
	local title = Gui.label(titleBox, { Text = text, display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(GOLD_LIGHT, GOLD) }, title)
	make("UIStroke", { Color = Color3.fromRGB(40, 24, 4), Thickness = 2, Transparency = 0.2 }, title)
	tween(pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	task.spawn(function()
		for _ = 1, 6 do
			for i, l in ipairs(glitches) do
				l.Position = UDim2.fromOffset((i == 1 and -1 or 1) * math.random(3, 12), math.random(-5, 5))
			end
			task.wait(0.05)
		end
		for _, l in ipairs(glitches) do
			tween(l, 0.25, { TextTransparency = 1 })
		end
	end)

	-- right: the name, its +N and what this step gave (the second beat: in after the splash)
	local side = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1.4, 0, 0.5, 0), Size = UDim2.fromScale(0.3, 0.6), BackgroundTransparency = 1 }, fade)
	make("UIListLayout", { Padding = UDim.new(0.015, 0), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	local plus = Gui.label(side, { Text = "+" .. level, display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextColor3 = level >= Config.Breakthrough.Max and GOLD or Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 0.24), TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 1 })
	make("UIStroke", { Color = color, Thickness = 2 }, plus)
	Gui.label(side, { Text = c.Name, display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, Size = UDim2.fromScale(1, 0.13), TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 2 })
	Gui.label(side, { Text = string.format("%s  ·  %s", c.Tier, (Config.Roles[c.Role] and Config.Roles[c.Role].Name) or c.Role), display = true, TextScaled = true, TextColor3 = color, Size = UDim2.fromScale(1, 0.06), TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 3 })
	local d = Breakthrough.describe(c, level)
	local lines = {}
	for _, st in ipairs(d.stats) do
		table.insert(lines, st)
	end
	local def = c.Ability and Config.Abilities[c.Ability]
	if def then
		for _, a in ipairs(d.ability) do
			table.insert(lines, string.format('<font color="#%s">%s</font> %s', def.Color:ToHex(), a[1], a[2]))
		end
	end
	Gui.label(side, { Text = table.concat(lines, "\n"), RichText = true, TextScaled = true, TextColor3 = Gui.CHALK, Size = UDim2.fromScale(1, 0.4), TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 4 })
	if maxed then
		local maxTag = Gui.label(side, { Text = "MAX", display = true, weight = Enum.FontWeight.Heavy, TextScaled = true, TextColor3 = GOLD, Size = UDim2.fromScale(1, 0.07), TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 0 })
		make("UIStroke", { Color = Color3.fromRGB(40, 24, 4), Thickness = 1.5 }, maxTag)
	end
	-- the second beat: the character steps left, the title rises over it, the gains come in
	task.delay(1.35, function()
		if current ~= card or card.closing then
			return
		end
		tween(vp, 0.5, { Position = UDim2.fromScale(0.33, 0.54) }, Enum.EasingStyle.Quint)
		tween(rays, 0.5, { Position = UDim2.fromScale(0.33, 0.5) }, Enum.EasingStyle.Quint)
		tween(halo, 0.5, { Position = UDim2.fromScale(0.33, 0.5) }, Enum.EasingStyle.Quint)
		tween(titleBox, 0.5, { Position = UDim2.fromScale(0.36, 0.17) }, Enum.EasingStyle.Quint)
		tween(pop, 0.5, { Scale = 0.72 }, Enum.EasingStyle.Quint)
		tween(side, 0.55, { Position = UDim2.fromScale(0.96, 0.5) }, Enum.EasingStyle.Back)
	end)

	-- confetti: sparse specks over the whole screen, drifting down and turning (the reference's),
	-- more and gold-heavy at +Max
	for i = 1, maxed and 48 or 30 do
		local sz = math.random(4, 10)
		local x, y = math.random(), math.random() * 0.9
		local col = (maxed and i % 2 == 0) and GOLD or CONFETTI[(i % #CONFETTI) + 1]
		local bit = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y - 0.12), Size = UDim2.fromOffset(sz, math.max(3, math.floor(sz * 0.6))), Rotation = math.random(0, 360), BackgroundColor3 = col, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, fade)
		tween(bit, 0.3, { BackgroundTransparency = 0.05 })
		tween(bit, 3 + math.random() * 2.5, { Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.1, y + 0.25 + math.random() * 0.2), Rotation = bit.Rotation + math.random(-360, 360) }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	end

	local hint = Gui.label(fade, { Text = "Click to continue", display = true, TextSize = 22, TextColor3 = Gui.DIM, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(400, 30), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 })
	task.delay(0.9, function()
		if current == card then
			tween(hint, 0.8, { TextTransparency = 0.2 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end)
	back.MouseButton1Click:Connect(function()
		if os.clock() - card.at > 0.8 then
			close(card)
		end
	end)
	-- a controller: the card takes it (no selection left on the page behind it: A there had pressed
	-- Break through again), A or B closes it
	if mods.PadNav then
		mods.PadNav.root(fade, {
			prio = 45,
			noSelect = true,
			press = function()
				if os.clock() - card.at > 0.8 then
					close(card)
				end
			end,
			back = function()
				close(card)
			end,
		})
	end

	if mods.AudioController then
		mods.AudioController.play(level >= Config.Breakthrough.Max and "RecruitRevealGold" or "RecruitReveal", { volume = 0.9 })
	end
end

function BreakReveal.show(id, level, skin)
	show(id, level, skin)
end

function BreakReveal.init(m)
	mods = m
	local last = nil
	State.signals.Profile:Connect(function(p)
		local r = type(p) == "table" and p.breakReveal
		if r and r ~= last and type(r.id) == "string" then
			last = r
			if not State.isPlaying then
				local skin = nil
				for key, row in pairs(type(p.skins) == "table" and p.skins or {}) do
					if type(row) == "table" and type(row.on) == "table" and row.on[r.id] == true then
						skin = key
					end
				end
				show(r.id, Breakthrough.level(r.level), skin)
			end
		end
	end)
	-- a match starting (a queue filling) takes the screen: the card goes
	State.signals.Match:Connect(function()
		if State.isPlaying and current then
			close(current)
		end
	end)
	-- Enter closes it too (a controller's A and B go through PadNav)
	UserInputService.InputBegan:Connect(function(input)
		local card = current
		if card and os.clock() - card.at > 0.8 and input.KeyCode == Enum.KeyCode.Return then
			close(card)
		end
	end)
end

return BreakReveal
