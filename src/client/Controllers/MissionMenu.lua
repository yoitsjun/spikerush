-- Daily missions and character mastery (Config.Missions, Config.Mastery, the Missions module; the
-- owner, 2026-11-11, after The Spike Cross's Mission screen and the Mastery tab on its player
-- page):
--   * Missions in the top bar of every main screen, with a dot while something waits (today's
--     check-in, the day's reward, a mastery rank);
--   * the Missions window: a strip with the time to the reset, today's points and the reward
--     with Claim, then the day's six missions as cards (a circle that ticks, the mission and its
--     count, +250P, Go);
--   * the Mastery tab of a character's page (MenuController's Extra.masteryPage): the rank in big
--     letters, the next rank's reward, its three challenges with a tick or the count, and Claim.
-- Opening the window is the day's check-in. Everything is asked through the Profile remote
-- ("missionCheckin", "missionClaim", "masteryClaim").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Missions = require(Shared.Missions)
local Story = require(Shared.Story)
local Roster = require(Shared.Roster)
local State = require(script.Parent.State)
local Gui = require(script.Parent.Gui)

local MissionMenu = {}
local MC = Config.Missions
local MA = Config.Mastery
local mods, kit
local ui = { cards = {} }
local leftAt, leftSecs = 0, 0 -- when the profile last arrived, and its seconds to the reset
local GREEN = Color3.fromRGB(91, 227, 138)
local RING = Color3.fromRGB(120, 126, 150)

local function make(...)
	return kit.make(...)
end

local function label(parent, props)
	props.ZIndex = props.ZIndex or 23
	return Gui.label(parent, props)
end

-- Today's missions as the server last sent them.
local function today()
	local p = kit.profile()
	local m = p and p.missions
	return Missions.clean(m, m and m.day or Missions.day(os.time()))
end

local function mastery()
	local p = kit.profile()
	return (p and type(p.mastery) == "table") and p.mastery or {}
end

local function clock(secs)
	secs = math.max(0, math.floor(secs))
	return string.format("%dH %02dM", math.floor(secs / 3600), math.floor(secs % 3600 / 60))
end

------------------------------------------------------------------------------------------
-- the Missions window
------------------------------------------------------------------------------------------

local function go(where)
	ui.window.hide()
	if where == "story" then
		if mods.StoryMenu then
			mods.StoryMenu.open(true)
		end
	elseif where == "match" or where == "cups" then
		kit.go("match")
	end
end

local function missionCard(parent, i)
	local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
	local c = Gui.card(parent, { Position = UDim2.fromOffset(26 + col * 540, 206 + row * 122), Size = UDim2.fromOffset(528, 108), ZIndex = 22 })
	local ring = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 0), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = GREEN, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 23 }, c)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	local stroke = make("UIStroke", { Color = RING, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
	local tick = label(ring, { Text = "✓", display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 24 })
	local text = label(c, { Text = "", TextSize = 19, TextWrapped = true, Position = UDim2.fromOffset(64, 10), Size = UDim2.fromOffset(250, 88) })
	local pts = label(c, { Text = "+" .. MC.Points .. "P", display = true, TextSize = 22, TextColor3 = Gui.SIGNAL, Position = UDim2.fromOffset(322, 0), Size = UDim2.fromOffset(74, 108), TextXAlignment = Enum.TextXAlignment.Center })
	local b, bl = kit.hairButton(c, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(112, 50), ZIndex = 23 }, "Go", 22)
	bl.ZIndex = 24
	bl.TextColor3 = Gui.SIGNAL
	local card = { frame = c, ring = ring, stroke = stroke, tick = tick, text = text, pts = pts, go = b, goL = bl, where = nil }
	kit.onClick(b, function()
		if card.where then
			go(card.where)
		end
	end)
	return card
end

local function buildWindow()
	local m = kit.modal("Missions", "Daily Missions", 1120, 590, true)
	ui.window = m
	local strip = Gui.card(m.panel, { Position = UDim2.fromOffset(26, 92), Size = UDim2.fromOffset(1068, 98), ZIndex = 22 })
	local pill = make("Frame", { Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(104, 26), BackgroundColor3 = Gui.SIGNAL, BorderSizePixel = 0, ZIndex = 23 }, strip)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
	ui.timer = label(pill, { Text = "", display = true, TextSize = 16, TextColor3 = Gui.LINE, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
	ui.goal = label(strip, { Text = "", TextSize = 21, Position = UDim2.fromOffset(20, 48), Size = UDim2.fromOffset(600, 30) })
	local rewardBox = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -230, 0.5, 0), Size = UDim2.fromOffset(250, 70), BackgroundColor3 = Color3.fromRGB(16, 18, 34), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 23 }, strip)
	label(rewardBox, { Text = "REWARD", display = true, TextSize = 14, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
	label(rewardBox, { Text = Story.grantText(MC.Reward), display = true, TextSize = 21, TextColor3 = Gui.GOLD, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 32), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24 })
	local claim, claimL = kit.actionPlate(strip, { Name = "Claim", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(196, 64), ZIndex = 23 }, "Claim Reward", 24)
	claimL.ZIndex = 26
	claim:SetAttribute("NavFirst", true)
	ui.claim, ui.claimL = claim, claimL
	kit.onClick(claim, function()
		if Missions.canClaim(today()) then
			kit.sendProfile("missionClaim")
		end
	end)
	for i = 1, MC.Count do
		ui.cards[i] = missionCard(m.panel, i)
	end
end

local function waiting()
	local st = today()
	local n = Missions.masteryWaiting(mastery())
	if Missions.canClaim(st) then
		n = n + 1
	end
	if (st.stats.checkin or 0) < 1 then
		n = n + 1
	end
	return n
end

function MissionMenu.refresh()
	local some = waiting() > 0
	for _, dot in ipairs(ui.dots or {}) do
		dot.Visible = some
	end
	if not ui.window or not ui.window.root.Visible then
		return
	end
	local st = today()
	local pts = Missions.points(st)
	ui.goal.Text = string.format("Complete %d daily missions to claim the reward.  (%d/%dP)", math.ceil(MC.Goal / MC.Points), pts, MC.Goal)
	local can = Missions.canClaim(st)
	ui.claimL.Text = st.claimed and "Claimed" or "Claim Reward"
	Gui.enable(ui.claim, ui.claimL, can)
	local list = Missions.daily(st.day)
	for i, card in ipairs(ui.cards) do
		local def = list[i]
		card.frame.Visible = def ~= nil
		if def then
			local have, need, done = Missions.progress(st, def)
			card.text.Text = string.format("%s  (%d/%d)", Missions.text(def), have, need)
			card.text.TextColor3 = done and Gui.MUTED or Gui.CHALK
			card.ring.BackgroundTransparency = done and 0 or 1
			card.stroke.Color = done and GREEN or RING
			card.tick.Visible = done
			card.pts.TextColor3 = done and GREEN or Gui.SIGNAL
			card.where = def.Go
			card.go.Visible = not done and def.Go ~= nil
		end
	end
end

function MissionMenu.open()
	ui.window.root.Visible = true
	if (today().stats.checkin or 0) < 1 then
		kit.sendProfile("missionCheckin") -- opening it is the day's check-in
	end
	MissionMenu.refresh()
end

------------------------------------------------------------------------------------------
-- the Mastery tab of a character's page
------------------------------------------------------------------------------------------

local function buildMastery(frame)
	local M = { frame = frame, rows = {} }
	local band = make("Frame", { Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 104), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, BorderSizePixel = 0 }, frame)
	M.rank = Gui.label(band, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 68, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	-- the next rank's reward, and what it asks
	local box = make("Frame", { Position = UDim2.fromOffset(16, 128), Size = UDim2.fromOffset(178, 84), BackgroundColor3 = Color3.fromRGB(8, 10, 20), BackgroundTransparency = 0.25, BorderSizePixel = 0 }, frame)
	M.reward = Gui.label(box, { Text = "", TextSize = 17, TextColor3 = Gui.GOLD, TextWrapped = true, LineHeight = 1.15, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -20, 1, -12) })
	M.title = Gui.label(frame, { Text = "", display = true, TextSize = 26, TextColor3 = Gui.GOLD, Position = UDim2.fromOffset(208, 134), Size = UDim2.new(1, -224, 0, 32) })
	M.sub = Gui.label(frame, { Text = "", TextSize = 17, TextColor3 = Gui.MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(208, 168), Size = UDim2.new(1, -224, 0, 44) })
	for i, kind in ipairs(Missions.Kinds) do
		local y = 232 + (i - 1) * 52
		local name = Gui.label(frame, { Text = MA.Labels[kind], TextSize = 22, Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -240, 0, 40) })
		local tick = Gui.label(frame, { Text = "✓", display = true, weight = Enum.FontWeight.Heavy, TextSize = 28, TextColor3 = Gui.GOLD, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, y), Size = UDim2.fromOffset(34, 40), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
		local count = Gui.label(frame, { Text = "", display = true, TextSize = 22, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, y), Size = UDim2.fromOffset(130, 40), TextXAlignment = Enum.TextXAlignment.Right })
		M.rows[kind] = { name = name, tick = tick, count = count }
	end
	M.note = Gui.label(frame, { Text = "*Only matches you win are recorded for the challenge.", TextSize = 16, TextColor3 = Gui.MUTED, Position = UDim2.fromOffset(20, 396), Size = UDim2.new(1, -40, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	local claim, claimL = kit.actionPlate(frame, { Name = "ClaimMastery", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 430), Size = UDim2.fromOffset(280, 66) }, "Claim", 26)
	claimL.ZIndex = 4
	M.claim, M.claimL = claim, claimL
	kit.onClick(claim, function()
		if M.char then
			kit.sendProfile("masteryClaim", M.char)
		end
	end)
	return M
end

-- Fill a character page's Mastery tab (MenuController calls it as the page refreshes). `mine`:
-- you own the character.
function MissionMenu.fillMastery(frame, charId, mine)
	if not kit or not frame then
		return
	end
	if not ui.mast or ui.mast.frame ~= frame then
		ui.mast = buildMastery(frame)
	end
	local M = ui.mast
	M.char = charId
	local row = Missions.mastery(mastery(), charId)
	local rank = Missions.rank(row)
	local nxt = Missions.nextRank(row)
	local c = Roster.get(charId)
	M.rank.Text = string.upper(rank.Name)
	M.rank.TextColor3 = rank.Color or Gui.CHALK
	if nxt then
		M.title.Text = "[" .. nxt.Name .. "] Achievement Reward"
		M.sub.Text = "Clear all challenges to claim Mastery rewards."
		M.reward.Text = (string.gsub(Story.grantText(nxt.Reward), ", ", "\n"))
	else
		M.title.Text = "Mastery complete"
		M.sub.Text = (c and c.Name or "This player") .. " has reached the top rank."
		M.reward.Text = "All claimed"
	end
	for _, kind in ipairs(Missions.Kinds) do
		local r = M.rows[kind]
		local have = row[kind] or 0
		local need = nxt and (nxt.Need[kind] or 0) or nil
		local done = need ~= nil and have >= need
		r.count.Text = need and string.format("(%d/%d)", have, need) or tostring(have)
		r.count.TextColor3 = done and Gui.GOLD or Gui.CHALK
		r.tick.Visible = done
	end
	local ready = nxt ~= nil and Missions.masteryReady(row) and mine == true
	M.claim.Visible = nxt ~= nil
	M.claimL.Text = nxt and ("Claim " .. nxt.Name) or "Claim"
	Gui.enable(M.claim, M.claimL, ready)
end

------------------------------------------------------------------------------------------

function MissionMenu.init(m)
	mods = m
	kit = mods.MenuController.kit()
	buildWindow()
	-- a dot on Missions in every screen's top bar (MenuController's nav)
	ui.dots = {}
	for _, d in ipairs(kit.canvas:GetDescendants()) do
		if d.Name == "Missions" and d:IsA("GuiButton") and d.Parent and d.Parent.Name == "Nav" then
			local dot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 22, 0, 2), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Gui.ALERT, BorderSizePixel = 0, Visible = false, ZIndex = d.ZIndex + 2 }, d)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
			table.insert(ui.dots, dot)
		end
	end
	local first = kit.profile()
	if first and type(first.missionsLeft) == "number" then
		leftAt, leftSecs = os.clock(), first.missionsLeft
	end
	State.signals.Profile:Connect(function(p)
		if type(p) == "table" and type(p.missionsLeft) == "number" then
			leftAt, leftSecs = os.clock(), p.missionsLeft
		end
		MissionMenu.refresh()
	end)
	-- the time to the reset, while the window is up
	local last = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < 1 or not ui.window.root.Visible then
			return
		end
		last = now
		ui.timer.Text = clock(leftSecs - (now - leftAt))
	end)
	MissionMenu.refresh()
end

return MissionMenu
