-- The Clans window (Config.Clans, ClanService), drawn with the menus' kit (MenuController.kit) and
-- opened from Home's right edge.
--   * not in a clan: Find (search a tag; join, or ask to join a private clan), Create (name, tag,
--     description, public or private, minimum wins; paid with VP or the Clan Founder pass) and the
--     Top clans;
--   * in one: its header (emblem, [TAG] name, points and what's left to spend), Members (each
--     one's stats since joining, and the owner's and officers' controls), Upgrades, Requests
--     (a private clan's), Tag colour (yours, bought with your own share of points), Top clans,
--     Settings (the owner) and Leave.

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
local data = { mine = false, top = {}, colors = {}, color = "White" } -- the last payload
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
	local s = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = Gui.HAIRLINE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, parent)
	for k, v in pairs(props) do
		s[k] = v
	end
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	return s
end

local function row(parent, order, height)
	local r = make("Frame", { Size = UDim2.new(1, -10, 0, height or 46), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 22 }, parent)
	Gui.corner(r, 6)
	return r
end

------------------------------------------------------------------------------------------
-- not in a clan
------------------------------------------------------------------------------------------

-- A clan's card (a search result): its emblem, [TAG] name, description, members, its door.
local function buildFound(parent)
	local f = Gui.card(parent, { Position = UDim2.fromOffset(0, 64), Size = UDim2.fromOffset(700, 220), Visible = false, ZIndex = 22 })
	local emblem = make("ImageLabel", { Position = UDim2.fromOffset(18, 18), Size = UDim2.fromOffset(120, 120), BackgroundColor3 = Gui.NAVY, ScaleType = Enum.ScaleType.Fit, ZIndex = 23 }, f)
	Gui.corner(emblem, 10)
	local title = label(f, { Text = "", RichText = true, display = true, weight = Enum.FontWeight.Heavy, TextSize = 34, Position = UDim2.fromOffset(156, 16), Size = UDim2.new(1, -170, 0, 40) })
	local desc = label(f, { Text = "", TextSize = 16, TextColor3 = Gui.DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(156, 60), Size = UDim2.new(1, -170, 0, 60) })
	local facts = label(f, { Text = "", TextSize = 17, TextColor3 = Gui.CHALK, Position = UDim2.fromOffset(156, 124), Size = UDim2.new(1, -170, 0, 22) })
	local join, joinL = kit.actionPlate(f, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -16), Size = UDim2.fromOffset(240, 50) }, "Join", 22)
	kit.onClick(join, function()
		if ui.foundTag then
			send("join", ui.foundTag)
		end
	end)
	return { frame = f, emblem = emblem, title = title, desc = desc, facts = facts, joinL = joinL }
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
	F.desc.Text = card.desc ~= "" and card.desc or "No description."
	F.facts.Text = string.format("%s points   ·   %d / %d members   ·   %s   ·   %d wins to join", Gui.num(card.points or 0), card.count or 0, card.cap or C.BaseCap, card.public and "Public" or "Private", card.minWins or 0)
	F.joinL.Text = card.public and "Join" or "Ask to join"
end

local function buildFind(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	local box = kit.inputBox(f, { Size = UDim2.fromOffset(420, 46) }, "A clan's tag (2 to 5 letters or numbers)")
	local go = kit.actionPlate(f, { Position = UDim2.fromOffset(432, 0), Size = UDim2.fromOffset(160, 46) }, "Search", 20)
	kit.onClick(go, function()
		send("search", box.Text)
	end)
	ui.found = buildFound(f)
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
	local _, setDoor = kit.segmented(f, { { key = "Public", text = "Public: anyone joins" }, { key = "Private", text = "Private: you let them in" } }, { Position = UDim2.fromOffset(0, 310), Size = UDim2.fromOffset(520, 44), ZIndex = 22 }, function(key)
		ui.createPublic = key == "Public"
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
	label(f, { Text = "Points from every member's wins, spike kills, aces, blocks and MVPs since they joined. The top 3 clans' members get the Top 3 Clan card, the top clan's Top Clan.", TextSize = 15, TextColor3 = Gui.DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40) })
	local list = scroller(f, { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46) })
	return { frame = f, list = list }
end

local RANK_COL = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(205, 214, 228), Color3.fromRGB(215, 140, 70) }

local function fillTop()
	local list = ui.top.list
	clearList(list) -- (its UIListLayout stays)
	if #data.top == 0 then
		label(list, { Text = "No clans yet: make the first one.", TextSize = 18, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 0 })
		return
	end
	for i, e in ipairs(data.top) do
		local r = row(list, i, 48)
		label(r, { Text = "#" .. e.rank, display = true, weight = Enum.FontWeight.Heavy, TextSize = 24, TextColor3 = RANK_COL[e.rank] or Gui.CHALK, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(60, 48) })
		label(r, { Text = string.format("%s %s", Clans.tagText(e.tag, "White"), e.name or ""), RichText = true, display = true, TextSize = 21, Position = UDim2.fromOffset(80, 0), Size = UDim2.fromOffset(520, 48) })
		label(r, { Text = Gui.num(e.points or 0) .. " pts", display = true, TextSize = 19, TextColor3 = BLUE, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -180, 0, 0), Size = UDim2.fromOffset(160, 48) })
		if e.count then
			label(r, { Text = string.format("%d / %d", e.count, e.cap or C.BaseCap), TextSize = 16, TextColor3 = Gui.DIM, Position = UDim2.new(1, -170, 0, 0), Size = UDim2.fromOffset(70, 48) })
		end
		if not data.mine then
			local look = kit.hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(90, 34), ZIndex = 23 }, "View", 16)
			kit.onClick(look, function()
				ClanMenu.setTab("Find")
				send("search", e.tag)
			end)
		end
	end
end

------------------------------------------------------------------------------------------
-- in a clan
------------------------------------------------------------------------------------------

local STAT_COLS = { "wins", "kills", "aces", "blocks", "mvps" }

local function buildMembers(body)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 21 }, body)
	-- the header row
	local head = make("Frame", { Size = UDim2.new(1, -10, 0, 26), BackgroundTransparency = 1, ZIndex = 22 }, f)
	label(head, { Text = "Player", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(200, 26) })
	label(head, { Text = "Role", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(230, 0), Size = UDim2.fromOffset(90, 26) })
	for i, k in ipairs(STAT_COLS) do
		label(head, { Text = C.StatNames[k], TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(320 + (i - 1) * 92, 0), Size = UDim2.fromOffset(90, 26) })
	end
	label(head, { Text = "Points", TextSize = 15, TextColor3 = Gui.DIM, Position = UDim2.fromOffset(780, 0), Size = UDim2.fromOffset(80, 26) })
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
			label(r, { Text = Gui.num(m.stats and m.stats[k] or 0), TextSize = 17, Position = UDim2.fromOffset(320 + (j - 1) * 92, 0), Size = UDim2.fromOffset(90, 46) })
		end
		label(r, { Text = Gui.num(m.points or 0), display = true, TextSize = 18, TextColor3 = BLUE, Position = UDim2.fromOffset(780, 0), Size = UDim2.fromOffset(80, 46) })
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
				btn("Make owner", "transfer")
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

local function effectText(u, level)
	if u.Show == "pct" then
		return string.format("+%d%%", math.floor(level * u.Per * 100 + 0.5))
	elseif u.Show == "num" then
		return string.format("%d members", C.BaseCap + level * u.Per)
	end
	return level > 0 and "Unlocked" or "Locked"
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
	local _, setDoor = kit.segmented(f, { { key = "Public", text = "Public" }, { key = "Private", text = "Private" } }, { Position = UDim2.fromOffset(0, 138), Size = UDim2.fromOffset(360, 44), ZIndex = 22 }, function(key)
		ui.setPublic = key == "Public"
	end)
	label(f, { Text = "Minimum wins to join", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(0, 194), Size = UDim2.fromOffset(300, 24) })
	local minWins = kit.inputBox(f, { Position = UDim2.fromOffset(0, 222), Size = UDim2.fromOffset(200, 44) }, "0")
	label(f, { Text = "Emblem (an image or decal id)", display = true, weight = Enum.FontWeight.Heavy, TextSize = 20, Position = UDim2.fromOffset(0, 278), Size = UDim2.fromOffset(400, 24) })
	local emblem = kit.inputBox(f, { Position = UDim2.fromOffset(0, 306), Size = UDim2.fromOffset(360, 44) }, "Unlock it with the Clan emblem upgrade")
	local save = kit.actionPlate(f, { Position = UDim2.fromOffset(0, 372), Size = UDim2.fromOffset(240, 52) }, "Save", 21)
	kit.onClick(save, function()
		local m = data.mine
		send("settings", { desc = desc.Text, public = ui.setPublic, minWins = tonumber(minWins.Text) or 0, emblem = (m and m.up and (m.up.Emblem or 0) > 0) and emblem.Text or nil })
	end)
	return { frame = f, desc = desc, minWins = minWins, emblem = emblem, setDoor = setDoor }
end

local function fillSettings()
	local S = ui.settings
	local m = data.mine
	if ui.settingsFor ~= m.tag then
		ui.settingsFor = m.tag
		S.desc.Text = m.desc or ""
		S.minWins.Text = tostring(m.minWins or 0)
		S.emblem.Text = m.emblem or ""
		ui.setPublic = m.public
		S.setDoor(m.public and "Public" or "Private")
	end
	S.emblem.TextEditable = (m.up and (m.up.Emblem or 0) > 0) == true
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
	local leave, leaveL = kit.hairButton(m.panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 24), Size = UDim2.fromOffset(120, 40), Visible = false, ZIndex = 23 }, "Leave", 16)
	kit.onClick(leave, function()
		-- press twice within 4 s
		if ui.leaveArmed and os.clock() - ui.leaveArmed < 4 then
			ui.leaveArmed = nil
			leaveL.Text = "Leave"
			send("leave")
		else
			ui.leaveArmed = os.clock()
			leaveL.Text = "Sure?"
			task.delay(4, function()
				if ui.leaveArmed and os.clock() - ui.leaveArmed >= 4 then
					ui.leaveArmed = nil
					leaveL.Text = "Leave"
				end
			end)
		end
	end)
	ui.leave = leave
	local outSeg, outSet = kit.segmented(m.panel, OUT_TABS, { Position = UDim2.fromOffset(28, 86), Size = UDim2.fromOffset(480, 46), ZIndex = 22 }, function(key)
		tab = key
		ClanMenu.refresh()
	end)
	local inSeg, inSet = kit.segmented(m.panel, IN_TABS, { Position = UDim2.fromOffset(28, 86), Size = UDim2.fromOffset(900, 46), ZIndex = 22 }, function(key)
		tab = key
		ClanMenu.refresh()
	end)
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
	ui.leave.Visible = inClan
	ui.window.title.Visible = not inClan
	-- a tab the other side doesn't have goes back to its first
	local valid = {}
	for _, t in ipairs(inClan and IN_TABS or OUT_TABS) do
		valid[t.key] = true
	end
	if not valid[tab] then
		tab = inClan and "Members" or "Find"
		if inClan then
			ui.inSet(tab)
		else
			ui.outSet(tab)
		end
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
	H.sub.Text = string.format("%s points  ·  %s to spend  ·  %d / %d members  ·  %s  ·  you're %s", Gui.num(mine.points or 0), Gui.num(mine.left or 0), mine.count or 0, mine.cap or C.BaseCap, mine.public and "Public" or "Private", string.lower(role or "a member"))
	if tab == "Members" then
		fillMembers()
	elseif tab == "Upgrades" then
		fillUpgrades()
	elseif tab == "Requests" then
		fillRequests()
	elseif tab == "Colors" then
		fillColors()
	elseif tab == "Settings" then
		if role ~= "Owner" then
			ui.settings.frame.Visible = false
		else
			fillSettings()
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
	if kit.extras then
		local b = kit.navItem(kit.extras, kit.iconKey("IconClan", "IconPlayers"), "Clan", { LayoutOrder = 6 })
		kit.extras.Size = UDim2.fromOffset(kit.extras.Size.X.Offset, kit.extras.Size.Y.Offset + 84)
		kit.onClick(b, ClanMenu.open)
	end
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
