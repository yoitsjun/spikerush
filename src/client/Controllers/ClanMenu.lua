-- The Clans window (Config.Clans, ClanService), drawn with the menus' kit (MenuController.kit) and
-- opened from the top nav's Clans.
--   * not in a clan: Find (search a tag; join, or ask to join a private clan), Create (name, tag,
--     description, public or private, minimum wins; paid with VP or the Clan Founder pass) and the
--     Top clans;
--   * in one: its header (emblem, [TAG] name, points and what's left to spend), Members (each
--     one's stats since joining, and the owner's and officers' controls), Upgrades, Requests
--     (a private clan's), Tag colour (yours, bought with your own share of points), Top clans,
--     Settings (the owner's controls, and everyone's Leave; the owner's Transfer ownership).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Clans = require(Shared.Clans)
local Gui = require(script.Parent.Gui)

local ClanMenu = {}
local C = Config.Clans
local player = Players.LocalPlayer
local mods, kit
local ui = {}
local data = { mine = false, top = {}, topWeek = {}, colors = {}, color = "White" } -- the last payload
local topView = "All" -- the board shown: "All" (all time) or "Week" (this week's points)
local tab = "Find"
local BLUE = Color3.fromRGB(80, 170, 255)

local function make(...)
	return kit.make(...)
end

local function send(op, a, b)
	Net.get("Clan"):FireServer(op, a, b)
end

local function label(parent, props)
	props.ZIndex = props.ZIndex or 23
	return Gui.label(parent, props)
end

local function clearList(f)
	for _, c in ipairs(f:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function myRole()
	local m = data.mine
	if not m then
		return nil
	end
	for _, mem in ipairs(m.members or {}) do
		if mem.id == player.UserId then
			return mem.role, mem
		end
	end
	return nil
end

local function scroller(parent, props)
	local s = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.DIM, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, parent)
	for k, v in pairs(props) do
		s[k] = v
	end
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	return s
end

-- A button that only fires on the third press, each within 4 s of the last (the owner, 2026-10-25:
-- "add like triple confirms" to Leave and Transfer ownership). Returns a reset for when its target changes.
local CONFIRMS = { "Are you sure?", "Really? Press once more" }
local function tripleConfirm(btn, lbl, idle, fire)
	local presses, at = 0, nil
	local function reset()
		presses, at = 0, nil
		lbl.Text = idle()
	end
	kit.onClick(btn, function()
		presses = (at and os.clock() - at < 4) and presses + 1 or 1
		if presses >= 3 then
			reset()
			fire()
			return
		end
		at = os.clock()
		lbl.Text = CONFIRMS[presses]
		local mark = at
		task.delay(4, function()
			if at == mark then
				reset()
			end
		end)
	end)
	return reset
end

local function row(parent, order, height)
	local r = make("Frame", { Size = UDim2.new(1, -10, 0, height or 46), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 22 }, parent)
	Gui.corner(r, 6)
	return r
end

------------------------------------------------------------------------------------------
-- not in a clan
------------------------------------------------------------------------------------------

-- (a search result opens the clan's page: buildViewer, below)

local function buildFind(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local box = kit.inputBox(f, { Size = UDim2.fromOffset(420, 46) }, "A clan's tag (2 to 5 letters or numbers)")
	local go = kit.actionPlate(f, { Position = UDim2.fromOffset(432, 0), Size = UDim2.fromOffset(160, 46) }, "Search", 20)
	kit.onClick(go, function()
		send("search", box.Text)
	end)
	label(f, { Text = "Or pick one from Top clans.", TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(0, 300), Size = UDim2.fromOffset(700, 22) })
	return { frame = f, box = box }
end

local function buildCreate(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local function field(y, title, placeholder, w)
		label(f, { Text = title, display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(300, 24) })
		return kit.inputBox(f, { Position = UDim2.fromOffset(0, y + 28), Size = UDim2.fromOffset(w or 520, 44) }, placeholder)
	end
	local name = field(0, "Clan name", string.format("3 to %d characters", C.NameMax))
	local tagBox = field(84, "Tag", string.format("%d to %d letters or numbers, shown next to your name", C.TagMin, C.TagMax), 260)
	local desc = field(168, "Description", "What your clan is about (optional)", 760)
	desc.Size = UDim2.fromOffset(760, 70)
	desc.TextWrapped = true
	desc.MultiLine = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	-- public or private, and the wins to join
	label(f, { Text = "Who can join", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(0, 282), Size = UDim2.fromOffset(300, 24) })
	ui.createPublic = true
	local setDoor, _
	_, setDoor = kit.segmented(f, { { key = "Public", text = "Public: anyone joins" }, { key = "Private", text = "Private: you let them in" } }, { Position = UDim2.fromOffset(0, 310), Size = UDim2.fromOffset(520, 44), ZIndex = 22 }, function(key)
		ui.createPublic = key == "Public"
		setDoor(key)
	end)
	setDoor("Public")
	local minWins = field(366, "Minimum wins to join", "0 (no minimum)", 260)
	label(f, { Text = string.format("Starts with room for %d members (more with the Member cap upgrade).", C.BaseCap), TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(280, 400), Size = UDim2.fromOffset(500, 40), TextWrapped = true })
	local function form(pay)
		return { tag = tagBox.Text, name = name.Text, desc = desc.Text, public = ui.createPublic, minWins = tonumber(minWins.Text) or 0, pay = pay }
	end
	-- pay: VP, or the Clan Founder pass
	local byVP = kit.actionPlate(f, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(300, 56) }, string.format("Create  ·  %s VP", Gui.num(C.CostVP)), 21)
	kit.onClick(byVP, function()
		send("create", form("VP"))
	end)
	local byPass, byPassL = kit.hairButton(f, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -316, 1, 0), Size = UDim2.fromOffset(300, 56) }, "Clan Founder pass", 19)
	byPass.Visible = C.PassId ~= 0
	kit.onClick(byPass, function()
		if data.passOwned then
			send("create", form("Pass"))
		else
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, C.PassId)
			end)
		end
	end)
	return { frame = f, byPassL = byPassL }
end

------------------------------------------------------------------------------------------
-- the top clans (both sides)
------------------------------------------------------------------------------------------

local function buildTop(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	-- all time or this week (the owner: "a weekly point counter for clans")
	local _, setView = kit.segmented(f, { { key = "All", text = "All time" }, { key = "Week", text = "This week" } }, { Size = UDim2.fromOffset(320, 40), ZIndex = 22 }, function(key)
		topView = key
		ClanMenu.refresh()
	end)
	setView(topView)
	local note = label(f, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(336, 0), Size = UDim2.new(1, -336, 0, 40) })
	local list = scroller(f, { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50) })
	return { frame = f, list = list, note = note }
end

local RANK_COL = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(205, 214, 228), Color3.fromRGB(215, 140, 70) }

local function fillTop()
	local list = ui.top.list
	clearList(list) -- (its UIListLayout stays)
	local week = topView == "Week"
	local rows = week and (data.topWeek or {}) or data.top
	if week then
		local left = math.max(0, (data.weekEnds or 0) - os.time())
		ui.top.note.Text = string.format("Points every clan's members earned since Monday. Starts over in %dd %dh.", math.floor(left / 86400), math.floor(left % 86400 / 3600))
	else
		ui.top.note.Text = "Points from every member's wins, spike kills, aces, blocks and MVPs since they joined. The top 3 get the Top 3 Clan card."
	end
	if #rows == 0 then
		label(list, { Text = week and "No clan has earned points this week yet." or "No clans yet: make the first one.", TextSize = 18, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 0 })
		return
	end
	for i, e in ipairs(rows) do
		local r = row(list, i, 48)
		label(r, { Text = "#" .. e.rank, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextColor3 = RANK_COL[e.rank] or Gui.CHALK, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(60, 48) })
		label(r, { Text = string.format("%s %s", Clans.tagText(e.tag, "White"), e.name or ""), RichText = true, display = true, TextSize = 21, Position = UDim2.fromOffset(80, 0), Size = UDim2.fromOffset(520, 48) })
		label(r, { Text = Gui.num(e.points or 0) .. " pts", display = true, TextSize = 19, TextColor3 = BLUE, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -180, 0, 0), Size = UDim2.fromOffset(160, 48) })
		if e.count then
			label(r, { Text = string.format("%d / %d", e.count, e.cap or C.BaseCap), TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.new(1, -170, 0, 0), Size = UDim2.fromOffset(70, 48) })
		end
		-- any clan's page, in a clan or not
		local look = kit.hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(90, 34), ZIndex = 23 }, "View", 16)
		kit.onClick(look, function()
			send("search", e.tag)
		end)
	end
end

------------------------------------------------------------------------------------------
-- in a clan
------------------------------------------------------------------------------------------

local STAT_COLS = { "wins", "kills", "aces", "blocks", "mvps" }

-- what an upgrade does at `level` ("+6%", "35 members", "Unlocked")
local function effectText(u, level)
	if u.Show == "pct" then
		return string.format("+%d%%", math.floor(level * u.Per * 100 + 0.5))
	elseif u.Show == "num" then
		return string.format("%d members", C.BaseCap + level * u.Per)
	end
	return level > 0 and "Unlocked" or "Locked"
end

------------------------------------------------------------------------------------------
-- any clan's page (the owner, 2026-10-22: "allow people to view clans stats and such and members"):
-- a search or Top clans' View opens it over the window, in a clan or not; its Members or its
-- Upgrades (the owner: "allow the view tab to also see the clan upgrades")
------------------------------------------------------------------------------------------

local function buildViewer(parent)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Gui.CARD, BackgroundTransparency = 0.02, BorderSizePixel = 0, Visible = false, ZIndex = 30 }, parent)
	local Z = 31
	local emblem = make("ImageLabel", { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(96, 96), BackgroundColor3 = Gui.NAVY, ScaleType = Enum.ScaleType.Fit, ZIndex = Z }, f)
	Gui.corner(emblem, 10)
	local title = label(f, { Text = "", RichText = true, display = true, weight = Enum.FontWeight.Heavy, TextSize = 32, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(128, 8), Size = UDim2.new(1, -380, 0, 38), ZIndex = Z })
	local desc = label(f, { Text = "", TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(128, 46), Size = UDim2.new(1, -380, 0, 38), ZIndex = Z })
	local facts = label(f, { Text = "", TextSize = 16, Position = UDim2.fromOffset(128, 86), Size = UDim2.new(1, -150, 0, 22), ZIndex = Z })
	local back = kit.hairButton(f, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(110, 40), ZIndex = Z }, "Back", 16)
	kit.onClick(back, function()
		f.Visible = false
		ui.foundTag = nil
	end)
	local join, joinL = kit.actionPlate(f, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -132, 0, 10), Size = UDim2.fromOffset(200, 40), ZIndex = Z }, "Join", 18)
	joinL.ZIndex = Z + 3
	kit.onClick(join, function()
		if ui.foundTag then
			send("join", ui.foundTag)
		end
	end)
	-- the clan's totals, then its members
	local totals = label(f, { Text = "", RichText = true, display = true, TextSize = 18, Position = UDim2.fromOffset(16, 118), Size = UDim2.new(1, -32, 0, 24), ZIndex = Z })
	local V = { frame = f }
	local _, setView = kit.segmented(f, { { key = "Members", text = "Members" }, { key = "Upgrades", text = "Upgrades" } }, { Position = UDim2.fromOffset(16, 150), Size = UDim2.fromOffset(320, 40), ZIndex = Z }, function(key)
		ui.foundView = key
		V.setView(key)
		V.membersF.Visible = key == "Members"
		V.upF.Visible = key == "Upgrades"
	end)
	V.setView = setView
	local membersF = make("Frame", { Position = UDim2.fromOffset(0, 198), Size = UDim2.new(1, 0, 1, -198), BackgroundTransparency = 1, ZIndex = Z }, f)
	local head = make("Frame", { Size = UDim2.new(1, -10, 0, 24), BackgroundTransparency = 1, ZIndex = Z }, membersF)
	label(head, { Text = "Player", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(200, 24), ZIndex = Z })
	label(head, { Text = "Role", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(230, 0), Size = UDim2.fromOffset(90, 24), ZIndex = Z })
	for i, k in ipairs(STAT_COLS) do
		label(head, { Text = C.StatNames[k], TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(320 + (i - 1) * 92, 0), Size = UDim2.fromOffset(90, 24), ZIndex = Z })
	end
	label(head, { Text = "Points", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(780, 0), Size = UDim2.fromOffset(80, 24), ZIndex = Z })
	local list = scroller(membersF, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -28), ZIndex = Z })
	-- its upgrades: each one's level and what it does now
	local upF = make("Frame", { Position = UDim2.fromOffset(0, 198), Size = UDim2.new(1, 0, 1, -198), BackgroundTransparency = 1, Visible = false, ZIndex = Z }, f)
	local upList = scroller(upF, { Size = UDim2.fromScale(1, 1), ZIndex = Z })
	V.upRows = {}
	for i, u in ipairs(C.Upgrades) do
		local r = row(upList, i, 50)
		r.ZIndex = Z
		local name = label(r, { Text = u.Name, display = true, TextSize = 19, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(200, 50), ZIndex = Z + 1 })
		local lvl = label(r, { Text = "", display = true, TextSize = 18, TextColor3 = Gui.GOLD, Position = UDim2.fromOffset(220, 0), Size = UDim2.fromOffset(100, 50), ZIndex = Z + 1 })
		local eff = label(r, { Text = "", display = true, TextSize = 18, TextColor3 = BLUE, Position = UDim2.fromOffset(330, 0), Size = UDim2.fromOffset(150, 50), ZIndex = Z + 1 })
		label(r, { Text = u.Blurb, TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(490, 0), Size = UDim2.new(1, -500, 1, 0), ZIndex = Z + 1 })
		V.upRows[u.Key] = { name = name, lvl = lvl, eff = eff }
	end
	V.membersF, V.upF = membersF, upF
	V.emblem, V.title, V.desc, V.facts, V.join, V.joinL, V.totals, V.list = emblem, title, desc, facts, join, joinL, totals, list
	setView("Members")
	return V
end

local function showFound(card)
	local F = ui.found
	if not card then
		F.frame.Visible = false
		ui.foundTag = nil
		return
	end
	ui.foundTag = card.tag
	F.frame.Visible = true
	F.emblem.Image = (card.emblem and card.emblem ~= "") and ("rbxthumb://type=Asset&id=" .. card.emblem .. "&w=150&h=150") or ""
	F.title.Text = string.format("%s %s", Clans.tagText(card.tag, "White"), card.name or "")
	F.desc.Text = (card.desc and card.desc ~= "") and card.desc or "No description."
	F.facts.Text = string.format("%s points  ·  %s this week  ·  %d / %d members  ·  %s  ·  %d wins to join", Gui.num(card.points or 0), Gui.num(card.week or 0), card.count or 0, card.cap or C.BaseCap, card.public and "Public" or "Private", card.minWins or 0)
	local t = card.totals or {}
	local parts = {}
	for _, k in ipairs(STAT_COLS) do
		table.insert(parts, string.format('<font color="#B0B6C8">%s</font> %s', C.StatNames[k], Gui.num(t[k] or 0)))
	end
	F.totals.Text = "Clan totals:   " .. table.concat(parts, "     ")
	-- Join only for players in no clan, and not their own
	local inClan = data.mine ~= false and data.mine ~= nil
	F.join.Visible = not inClan
	F.joinL.Text = card.public and "Join" or "Ask to join"
	-- the upgrades' levels
	for _, u in ipairs(C.Upgrades) do
		local r = F.upRows[u.Key]
		local lv = card.up and card.up[u.Key] or 0
		r.lvl.Text = u.Max == 1 and (lv > 0 and "Done" or "-") or string.format("Lv. %d/%d", lv, u.Max)
		r.lvl.TextColor3 = lv > 0 and Gui.GOLD or Gui.DIM
		r.eff.Text = effectText(u, lv)
		r.eff.TextColor3 = lv > 0 and BLUE or Gui.DIM
		r.name.TextColor3 = lv > 0 and Gui.CHALK or Gui.DIM
	end
	local list = F.list
	clearList(list)
	for i, m in ipairs(card.members or {}) do
		local r = row(list, i, 44)
		r.ZIndex = 31
		local function cell(text, x, w, props)
			local l = label(r, { Text = text, TextSize = 17, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w, 44), ZIndex = 32 })
			for k, v in pairs(props or {}) do
				l[k] = v
			end
		end
		cell(m.name or "?", 14, 210, { TextColor3 = m.id == player.UserId and Gui.SIGNAL or Gui.CHALK, TextTruncate = Enum.TextTruncate.AtEnd })
		cell(m.role or "", 230, 90, { TextSize = 16, TextColor3 = m.role == "Owner" and Gui.GOLD or (m.role == "Officer" and BLUE or Gui.DIM) })
		for j, k in ipairs(STAT_COLS) do
			cell(Gui.num(m.stats and m.stats[k] or 0), 320 + (j - 1) * 92, 90)
		end
		cell(Gui.num(m.points or 0), 780, 80, { TextColor3 = BLUE })
	end
end


-- your clan's Members tab: each stat column this wide (narrower than a clan page's, to fit Today
-- and Week before the Remove / Officer / Make owner buttons)
local MEMBER_STAT_W = 64

local function buildMembers(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	-- the header row
	local head = make("Frame", { Size = UDim2.new(1, -10, 0, 26), BackgroundTransparency = 1, ZIndex = 22 }, f)
	label(head, { Text = "Player", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(200, 26) })
	label(head, { Text = "Role", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(230, 0), Size = UDim2.fromOffset(90, 26) })
	for i, k in ipairs(STAT_COLS) do
		label(head, { Text = C.StatNames[k], TextSize = 13, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(320 + (i - 1) * MEMBER_STAT_W, 0), Size = UDim2.fromOffset(MEMBER_STAT_W - 2, 26) })
	end
	-- the points they earned today and this week, beside their total (who's making the quota)
	local x = 320 + #STAT_COLS * MEMBER_STAT_W
	label(head, { Text = "Points", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(66, 26) })
	label(head, { Text = "Today", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(x + 68, 0), Size = UDim2.fromOffset(58, 26) })
	label(head, { Text = "Week", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(x + 128, 0), Size = UDim2.fromOffset(58, 26) })
	local list = scroller(f, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30) })
	return { frame = f, list = list }
end

local function fillMembers()
	local list = ui.members.list
	clearList(list) -- (its UIListLayout stays)
	local me = myRole()
	for i, m in ipairs(data.mine.members or {}) do
		local r = row(list, i, 46)
		label(r, { Text = m.name or "?", display = true, TextSize = 19, TextColor3 = m.id == player.UserId and Gui.SIGNAL or Gui.CHALK, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(210, 46), TextTruncate = Enum.TextTruncate.AtEnd })
		label(r, { Text = m.role, TextSize = 16, TextColor3 = m.role == "Owner" and Gui.GOLD or (m.role == "Officer" and BLUE or Gui.DIM), Position = UDim2.fromOffset(230, 0), Size = UDim2.fromOffset(90, 46) })
		for j, k in ipairs(STAT_COLS) do
			label(r, { Text = Gui.num(m.stats and m.stats[k] or 0), TextSize = 17, Position = UDim2.fromOffset(320 + (j - 1) * MEMBER_STAT_W, 0), Size = UDim2.fromOffset(MEMBER_STAT_W - 2, 46) })
		end
		local x = 320 + #STAT_COLS * MEMBER_STAT_W
		label(r, { Text = Gui.num(m.points or 0), display = true, TextSize = 18, TextColor3 = BLUE, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(66, 46) })
		label(r, { Text = Gui.num(m.today or 0), display = true, TextSize = 18, TextColor3 = (m.today or 0) > 0 and Gui.CHALK or Gui.DIM, Position = UDim2.fromOffset(x + 68, 0), Size = UDim2.fromOffset(58, 46) })
		label(r, { Text = Gui.num(m.week or 0), display = true, TextSize = 18, TextColor3 = (m.week or 0) > 0 and Gui.CHALK or Gui.DIM, Position = UDim2.fromOffset(x + 128, 0), Size = UDim2.fromOffset(58, 46) })
		-- the owner's and officers' controls on others
		if m.id ~= player.UserId and (me == "Owner" or (me == "Officer" and m.role == "Member")) then
			local x = -8
			local function btn(text, op)
				local b = kit.hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(84, 32), ZIndex = 23 }, text, 14)
				x = x - 90
				kit.onClick(b, function()
					send(op, m.id)
				end)
			end
			btn("Remove", "kick")
			if me == "Owner" then
				if m.role == "Member" then
					btn("Officer", "promote")
				elseif m.role == "Officer" then
					btn("Member", "demote")
				end
			end
		end
	end
end

local function buildUpgrades(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local list = scroller(f, { Size = UDim2.new(0, 330, 1, 0) })
	local detail = Gui.card(f, { Position = UDim2.fromOffset(350, 0), Size = UDim2.new(1, -350, 1, 0), ZIndex = 22 })
	local title = label(detail, { Text = "", display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -40, 0, 36) })
	local blurb = label(detail, { Text = "", TextSize = 17, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(20, 58), Size = UDim2.new(1, -40, 0, 50) })
	local now = label(detail, { Text = "", display = true, TextSize = 22, Position = UDim2.fromOffset(20, 120), Size = UDim2.new(1, -40, 0, 30) })
	local buy, buyL = kit.actionPlate(detail, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.new(1, -40, 0, 56) }, "", 21)
	kit.onClick(buy, function()
		if ui.upgradeSel then
			send("upgrade", ui.upgradeSel)
		end
	end)
	local rows = {}
	for i, u in ipairs(C.Upgrades) do
		local r = make("TextButton", { Size = UDim2.new(1, -10, 0, 52), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 22 }, list)
		Gui.corner(r, 6)
		local stroke = make("UIStroke", { Color = Gui.SIGNAL, Thickness = 2, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, r)
		label(r, { Text = u.Name, display = true, TextSize = 19, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -90, 1, 0) })
		local lvl = label(r, { Text = "", display = true, TextSize = 18, TextColor3 = Gui.GOLD, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(80, 52) })
		kit.onClick(r, function()
			ui.upgradeSel = u.Key
			ClanMenu.refresh()
		end)
		rows[u.Key] = { lvl = lvl, stroke = stroke }
	end
	ui.upgradeSel = C.Upgrades[1].Key
	return { frame = f, rows = rows, title = title, blurb = blurb, now = now, buy = buy, buyL = buyL }
end

local function fillUpgrades()
	local U = ui.upgrades
	local m = data.mine
	for _, u in ipairs(C.Upgrades) do
		local r = U.rows[u.Key]
		local lv = m.up and m.up[u.Key] or 0
		r.lvl.Text = u.Max == 1 and (lv > 0 and "Done" or "") or string.format("Lv. %d/%d", lv, u.Max)
		r.stroke.Transparency = ui.upgradeSel == u.Key and 0 or 1
	end
	local u = Clans.upgrade(ui.upgradeSel)
	local lv = m.up and m.up[u.Key] or 0
	U.title.Text = string.format("%s  Lv. %d", u.Name, lv)
	U.blurb.Text = u.Blurb
	local cost = lv < u.Max and u.Base * (lv + 1) * (lv + 1) or nil
	U.now.Text = cost and string.format("%s  ->  %s", effectText(u, lv), effectText(u, lv + 1)) or (effectText(u, lv) .. "  (maxed)")
	local role = myRole()
	if not cost then
		U.buyL.Text = "Maxed"
	elseif role ~= "Owner" and role ~= "Officer" then
		U.buyL.Text = string.format("(Owner or officers) %s points", Gui.num(cost))
	else
		U.buyL.Text = string.format("Upgrade  ·  %s points", Gui.num(cost))
	end
end

local function buildRequests(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local list = scroller(f, { Size = UDim2.fromScale(1, 1) })
	return { frame = f, list = list }
end

local function fillRequests()
	local list = ui.requests.list
	clearList(list) -- (its UIListLayout stays)
	local reqs = data.mine.requests or {}
	if #reqs == 0 then
		label(list, { Text = data.mine.public and "Your clan is public: anyone with the wins joins at once." or "No requests right now.", TextSize = 18, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 0 })
		return
	end
	for i, q in ipairs(reqs) do
		local r = row(list, i, 46)
		label(r, { Text = q.name or "?", display = true, TextSize = 19, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(300, 46) })
		label(r, { Text = Gui.num(q.wins or 0) .. " wins", TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(320, 0), Size = UDim2.fromOffset(160, 46) })
		local yes = kit.actionPlate(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -110, 0.5, 0), Size = UDim2.fromOffset(110, 34) }, "Accept", 16)
		local no = kit.hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(92, 34), ZIndex = 23 }, "Decline", 15)
		kit.onClick(yes, function()
			send("accept", q.id)
		end)
		kit.onClick(no, function()
			send("decline", q.id)
		end)
	end
end

local function buildColors(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local own = label(f, { Text = "", TextSize = 17, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40) })
	local grid = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 1, -48), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, f)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(250, 110), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local cells = {}
	for i, col in ipairs(C.TagColors) do
		local cell = make("TextButton", { BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 22 }, grid)
		Gui.corner(cell, 8)
		local stroke = make("UIStroke", { Color = Gui.SIGNAL, Thickness = 2, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, cell)
		local preview = label(cell, { Text = "", RichText = true, display = true, weight = Enum.FontWeight.Heavy, TextSize = 30, Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center })
		label(cell, { Text = col.Name, TextSize = 16, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
		local state = label(cell, { Text = "", TextSize = 15, TextColor3 = Gui.SIGNAL, Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
		kit.onClick(cell, function()
			send("color", col.Key)
		end)
		cells[col.Key] = { preview = preview, state = state, stroke = stroke, col = col }
	end
	return { frame = f, own = own, cells = cells }
end

local function fillColors()
	local K = ui.colors
	local _, me = myRole()
	local left = me and me.own or 0
	K.own.Text = string.format("Your tag in chat, in the colour you pick. Colours cost your own share of the clan's points, once: you have %s to spend.", Gui.num(left))
	for key, c in pairs(K.cells) do
		c.preview.Text = Clans.tagText(data.mine.tag, key)
		local owned = c.col.Cost == 0 or (data.colors and data.colors[key])
		c.state.Text = data.color == key and "Wearing" or (owned and "Wear" or (Gui.num(c.col.Cost) .. " points"))
		c.stroke.Transparency = data.color == key and 0 or 1
	end
end

local function buildSettings(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	label(f, { Text = "Description", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Size = UDim2.fromOffset(300, 24) })
	local desc = kit.inputBox(f, { Position = UDim2.fromOffset(0, 28), Size = UDim2.fromOffset(760, 70), TextWrapped = true, MultiLine = true, TextYAlignment = Enum.TextYAlignment.Top }, "What your clan is about")
	label(f, { Text = "Who can join", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(0, 110), Size = UDim2.fromOffset(300, 24) })
	local setDoor, _
	_, setDoor = kit.segmented(f, { { key = "Public", text = "Public" }, { key = "Private", text = "Private" } }, { Position = UDim2.fromOffset(0, 138), Size = UDim2.fromOffset(360, 44), ZIndex = 22 }, function(key)
		ui.setPublic = key == "Public"
		setDoor(key)
	end)
	label(f, { Text = "Minimum wins to join", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(0, 194), Size = UDim2.fromOffset(300, 24) })
	local minWins = kit.inputBox(f, { Position = UDim2.fromOffset(0, 222), Size = UDim2.fromOffset(200, 44) }, "0")
	label(f, { Text = "Emblem (an image or decal id)", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(0, 278), Size = UDim2.fromOffset(400, 24) })
	local emblem = kit.inputBox(f, { Position = UDim2.fromOffset(0, 306), Size = UDim2.fromOffset(360, 44) }, "Unlock it with the Clan emblem upgrade")
	-- the name and tag, any time (the owner, 2026-10-21)
	label(f, { Text = "Name and tag", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(420, 110), Size = UDim2.fromOffset(300, 24) })
	local nameBox = kit.inputBox(f, { Position = UDim2.fromOffset(420, 138), Size = UDim2.fromOffset(340, 44) }, "Clan name")
	local tagBox = kit.inputBox(f, { Position = UDim2.fromOffset(420, 192), Size = UDim2.fromOffset(160, 44) }, "Tag")
	local rename = kit.hairButton(f, { Position = UDim2.fromOffset(592, 192), Size = UDim2.fromOffset(168, 44) }, "Rename", 17)
	kit.onClick(rename, function()
		send("rename", { name = nameBox.Text, tag = tagBox.Text })
	end)
	label(f, { Text = "Your old tag stays reserved for your clan, so nobody can pose as you.", TextSize = 14, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(420, 242), Size = UDim2.fromOffset(340, 36) })
	-- the team jersey (the Team jersey upgrade): a Roblox Shirt and Pants, by link or id
	label(f, { Text = "Team jersey (Shirt and Pants links or ids)", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(420, 278), Size = UDim2.fromOffset(400, 24) })
	local shirt = kit.inputBox(f, { Position = UDim2.fromOffset(420, 306), Size = UDim2.fromOffset(165, 44) }, "Shirt")
	local pants = kit.inputBox(f, { Position = UDim2.fromOffset(595, 306), Size = UDim2.fromOffset(165, 44) }, "Pants")
	local save = kit.actionPlate(f, { Position = UDim2.fromOffset(0, 372), Size = UDim2.fromOffset(240, 52) }, "Save", 21)
	kit.onClick(save, function()
		local m = data.mine
		local jersey = m and m.up and (m.up.Jersey or 0) > 0
		send("settings", { desc = desc.Text, public = ui.setPublic, minWins = tonumber(minWins.Text) or 0, emblem = (m and m.up and (m.up.Emblem or 0) > 0) and emblem.Text or nil, shirt = jersey and shirt.Text or nil, pants = jersey and pants.Text or nil })
	end)
	-- the owner's controls above sit in `own`; Transfer ownership and Leave sit in their own column
	-- (moved off the member rows and the window's header, 2026-10-25)
	local own = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 21 }, f)
	for _, c in ipairs(f:GetChildren()) do
		if c ~= own then
			c.Parent = own
		end
	end
	local give = make("Frame", { Position = UDim2.fromOffset(800, 0), Size = UDim2.new(1, -800, 0, 310), BackgroundTransparency = 1, ZIndex = 21 }, f)
	label(give, { Text = "Transfer ownership", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Size = UDim2.new(1, 0, 0, 24) })
	label(give, { Text = "Pick who gets the clan. You become an officer.", TextSize = 14, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 20) })
	local picks = scroller(give, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 200) })
	local giveBtn, giveL = kit.hairButton(give, { Position = UDim2.fromOffset(0, 262), Size = UDim2.new(1, 0, 0, 44) }, "Pick a member", 17)
	local function giveIdle()
		return ui.giveTo and ("Make " .. ui.giveTo.name .. " owner") or "Pick a member"
	end
	local resetGive = tripleConfirm(giveBtn, giveL, giveIdle, function()
		if ui.giveTo then
			send("transfer", ui.giveTo.id)
			ui.giveTo = nil
			giveL.Text = giveIdle()
		end
	end)
	local leaveF = make("Frame", { Position = UDim2.fromOffset(800, 330), Size = UDim2.new(1, -800, 0, 120), BackgroundTransparency = 1, ZIndex = 21 }, f)
	label(leaveF, { Text = "Leave clan", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Size = UDim2.new(1, 0, 0, 24) })
	local leaveHint = label(leaveF, { Text = "", TextSize = 14, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 38) })
	local leaveBtn, leaveL = kit.hairButton(leaveF, { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 44) }, "Leave clan", 17)
	tripleConfirm(leaveBtn, leaveL, function()
		return "Leave clan"
	end, function()
		send("leave")
	end)
	return { frame = f, own = own, give = give, picks = picks, giveL = giveL, giveIdle = giveIdle, resetGive = resetGive, leaveF = leaveF, leaveHint = leaveHint, desc = desc, minWins = minWins, emblem = emblem, shirt = shirt, pants = pants, setDoor = setDoor, nameBox = nameBox, tagBox = tagBox }
end

-- the Transfer ownership picks: everyone but you, officers first
local function fillGive()
	local S = ui.settings
	clearList(S.picks)
	local others = {}
	for _, mem in ipairs(data.mine.members or {}) do
		if mem.id ~= player.UserId then
			table.insert(others, mem)
		end
	end
	table.sort(others, function(a, b)
		if (a.role == "Officer") ~= (b.role == "Officer") then
			return a.role == "Officer"
		end
		return (a.points or 0) > (b.points or 0)
	end)
	local still = false
	for i, mem in ipairs(others) do
		local picked = ui.giveTo and ui.giveTo.id == mem.id
		still = still or picked
		local b = make("TextButton", { Size = UDim2.new(1, -10, 0, 36), BackgroundColor3 = picked and Gui.LINE or Gui.NAVY, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 22 }, S.picks)
		Gui.corner(b, 6)
		if picked then
			make("UIStroke", { Color = Gui.SIGNAL, Thickness = 2 }, b)
		end
		label(b, { Text = mem.name or "?", display = true, TextSize = 17, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -100, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
		label(b, { Text = mem.role, TextSize = 14, TextColor3 = mem.role == "Officer" and BLUE or Gui.DIM, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -90, 0, 0), Size = UDim2.fromOffset(80, 36) })
		kit.onClick(b, function()
			ui.giveTo = { id = mem.id, name = mem.name or "?" }
			S.resetGive() -- a new pick starts the three presses over
			fillGive()
		end)
	end
	if #others == 0 then
		label(S.picks, { Text = "Nobody else is in the clan yet.", TextSize = 15, TextColor3 = Gui.DIM, Size = UDim2.new(1, -10, 0, 36) })
	end
	if ui.giveTo and not still then
		ui.giveTo = nil -- they left
		S.resetGive()
	end
end

local function fillSettings()
	local S = ui.settings
	local m = data.mine
	if ui.settingsFor ~= m.tag then
		ui.settingsFor = m.tag
		S.desc.Text = m.desc or ""
		S.minWins.Text = tostring(m.minWins or 0)
		S.emblem.Text = m.emblem or ""
		S.shirt.Text = m.shirt or ""
		S.pants.Text = m.pants or ""
		S.nameBox.Text = m.name or ""
		S.tagBox.Text = m.tag or ""
		ui.setPublic = m.public
		S.setDoor(m.public and "Public" or "Private")
	end
	S.emblem.TextEditable = (m.up and (m.up.Emblem or 0) > 0) == true
	local jersey = (m.up and (m.up.Jersey or 0) > 0) == true
	S.shirt.TextEditable, S.pants.TextEditable = jersey, jersey
	S.shirt.PlaceholderText = jersey and "Shirt" or "Team jersey upgrade"
	S.pants.PlaceholderText = jersey and "Pants" or "first"
end

------------------------------------------------------------------------------------------
-- the window
------------------------------------------------------------------------------------------

local OUT_TABS = { { key = "Find", text = "Find" }, { key = "Create", text = "Create" }, { key = "Top", text = "Top clans" } }
local IN_TABS = { { key = "Members", text = "Members" }, { key = "Upgrades", text = "Upgrades" }, { key = "Requests", text = "Requests" }, { key = "Colors", text = "Tag colour" }, { key = "Top", text = "Top clans" }, { key = "Settings", text = "Settings" } }

function ClanMenu.setTab(key)
	tab = key
	if ui.outSet and not data.mine then
		ui.outSet(key)
	elseif ui.inSet and data.mine then
		ui.inSet(key)
	end
	ClanMenu.refresh()
end

local function buildWindow()
	local m = kit.modal("Clans", "Clans", 1180, 680, true)
	ui.window = m
	-- in a clan: its header over the tabs
	local head = make("Frame", { Position = UDim2.fromOffset(28, 20), Size = UDim2.new(1, -200, 0, 60), BackgroundTransparency = 1, Visible = false, ZIndex = 22 }, m.panel)
	local emblem = make("ImageLabel", { Size = UDim2.fromOffset(56, 56), BackgroundColor3 = Gui.NAVY, ScaleType = Enum.ScaleType.Fit, ZIndex = 23 }, head)
	Gui.corner(emblem, 8)
	local title = label(head, { Text = "", RichText = true, display = true, weight = Enum.FontWeight.Heavy, TextSize = 34, Position = UDim2.fromOffset(68, 0), Size = UDim2.fromOffset(620, 38) })
	local sub = label(head, { Text = "", TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(68, 38), Size = UDim2.fromOffset(760, 20) })
	ui.head = { frame = head, emblem = emblem, title = title, sub = sub }
	local outSeg, outSet = kit.segmented(m.panel, OUT_TABS, { Position = UDim2.fromOffset(28, 86), Size = UDim2.fromOffset(480, 46), ZIndex = 22 }, ClanMenu.setTab)
	local inSeg, inSet = kit.segmented(m.panel, IN_TABS, { Position = UDim2.fromOffset(28, 86), Size = UDim2.fromOffset(900, 46), ZIndex = 22 }, ClanMenu.setTab)
	ui.outSeg, ui.outSet, ui.inSeg, ui.inSet = outSeg, outSet, inSeg, inSet
	local body = make("Frame", { Position = UDim2.fromOffset(28, 148), Size = UDim2.new(1, -56, 1, -170), BackgroundTransparency = 1, ZIndex = 21 }, m.panel)
	ui.find = buildFind(body)
	ui.create = buildCreate(body)
	ui.top = buildTop(body)
	ui.members = buildMembers(body)
	ui.upgrades = buildUpgrades(body)
	ui.requests = buildRequests(body)
	ui.colors = buildColors(body)
	ui.settings = buildSettings(body)
	ui.found = buildViewer(body)
	outSet("Find")
end

function ClanMenu.refresh()
	if not ui.window then
		return
	end
	local mine = data.mine
	local inClan = mine ~= false and mine ~= nil
	ui.outSeg.Visible = not inClan
	ui.inSeg.Visible = inClan
	ui.head.frame.Visible = inClan
	ui.window.title.Visible = not inClan
	-- a tab the other side doesn't have goes back to its first
	local valid = {}
	for _, t in ipairs(inClan and IN_TABS or OUT_TABS) do
		valid[t.key] = true
	end
	if not valid[tab] then
		tab = inClan and "Members" or "Find"
	end
	-- the yellow mark on the row showing, every time (Top clans is on both rows, so switching rows
	-- on it left the new row unmarked: the owner, 2026-10-25, "make the yellow highlight which slot im on")
	if inClan then
		ui.inSet(tab)
	else
		ui.outSet(tab)
	end
	ui.find.frame.Visible = tab == "Find"
	ui.create.frame.Visible = tab == "Create"
	ui.top.frame.Visible = tab == "Top"
	ui.members.frame.Visible = tab == "Members"
	ui.upgrades.frame.Visible = tab == "Upgrades"
	ui.requests.frame.Visible = tab == "Requests"
	ui.colors.frame.Visible = tab == "Colors"
	ui.settings.frame.Visible = tab == "Settings"
	if tab == "Top" then
		fillTop()
	end
	if not inClan then
		ui.create.byPassL.Text = data.passOwned and "Create  ·  Clan Founder pass" or "Clan Founder pass (Robux)"
		return
	end
	local role = myRole()
	local H = ui.head
	H.emblem.Image = (mine.emblem and mine.emblem ~= "") and ("rbxthumb://type=Asset&id=" .. mine.emblem .. "&w=150&h=150") or ""
	H.title.Text = string.format("%s %s", Clans.tagText(mine.tag, data.color), mine.name or "")
	H.sub.Text = string.format("%s points (%s this week)  ·  %s to spend  ·  %d / %d members  ·  %s  ·  you're %s", Gui.num(mine.points or 0), Gui.num(mine.week or 0), Gui.num(mine.left or 0), mine.count or 0, mine.cap or C.BaseCap, mine.public and "Public" or "Private", string.lower(role or "a member"))
	if tab == "Members" then
		fillMembers()
	elseif tab == "Upgrades" then
		fillUpgrades()
	elseif tab == "Requests" then
		fillRequests()
	elseif tab == "Colors" then
		fillColors()
	elseif tab == "Settings" then
		-- everyone gets Leave here; only the owner gets the rest (and the column moves left without it)
		local S = ui.settings
		local owner = role == "Owner"
		S.own.Visible, S.give.Visible = owner, owner
		S.leaveF.Position = owner and UDim2.fromOffset(800, 330) or UDim2.fromOffset(0, 0)
		S.leaveF.Size = owner and UDim2.new(1, -800, 0, 120) or UDim2.fromOffset(324, 120)
		if owner then
			S.leaveHint.Text = (mine.count or 1) > 1 and "The clan goes to your top officer (or top member). Transfer it first to choose." or "You're the only one in it, so it closes."
			fillSettings()
			fillGive()
		else
			S.leaveHint.Text = "The points you earned stay with the clan."
		end
	end
end

function ClanMenu.open()
	ui.window.root.Visible = true
	send("get")
	ClanMenu.refresh()
end

function ClanMenu.init(m)
	mods = m
	kit = mods.MenuController.kit()
	buildWindow()
	-- (opened from the top nav's Clans: MenuController's MAIN_TABS)
	Net.get("Clan").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		if p.mine ~= nil then
			data.mine = p.mine
		end
		if p.top then
			data.top = p.top
		end
		if p.topWeek then
			data.topWeek = p.topWeek
		end
		if p.weekEnds then
			data.weekEnds = p.weekEnds
		end
		if p.colors then
			data.colors = p.colors
		end
		if p.color then
			data.color = p.color
		end
		if p.passOwned ~= nil then
			data.passOwned = p.passOwned
		end
		if p.found ~= nil then
			showFound(p.found or nil)
		end
		if p.notice then
			kit.toast(p.notice)
		end
		ClanMenu.refresh()
	end)
end

return ClanMenu
