-- Parties (PartyService): the Party window (the top right's Party, and the Ranked window's Party
-- button): your party (the leader crowned; the leader can remove someone or hand over the lead),
-- Leave, and everyone else in this server with an Invite button. An invite to you pops up at the
-- top of the screen with Accept and Decline until it runs out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Gui = require(script.Parent.Gui)

local PartyMenu = {}
local player = Players.LocalPlayer
local mods, kit
local ui = {}
local data = { party = false, invites = {} }

local function make(...)
	return kit.make(...)
end

local function label(parent, props)
	props.ZIndex = props.ZIndex or 23
	return Gui.label(parent, props)
end

local function send(op, a)
	Net.get("Party"):FireServer(op, a)
end

local function clearList(f)
	for _, c in ipairs(f:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function row(parent, order)
	local r = make("Frame", { Size = UDim2.new(1, -10, 0, 50), BackgroundColor3 = Gui.NAVY, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 22 }, parent)
	Gui.corner(r, 6)
	return r
end

function PartyMenu.current()
	return data.party or nil
end

local function buildWindow()
	local m = kit.modal("Party", "Party", 900, 600, true)
	ui.window = m
	ui.sub = label(m.panel, { Text = "", TextSize = 16, TextColor3 = Gui.DIM, TextWrapped = true, Position = UDim2.fromOffset(28, 80), Size = UDim2.new(1, -56, 0, 40) })
	label(m.panel, { Text = "Your party", display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, Position = UDim2.fromOffset(28, 126), Size = UDim2.fromOffset(300, 26) })
	local members = make("Frame", { Position = UDim2.fromOffset(28, 156), Size = UDim2.fromOffset(400, 220), BackgroundTransparency = 1, ZIndex = 22 }, m.panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, members)
	local leave = kit.hairButton(m.panel, { Position = UDim2.fromOffset(28, 384), Size = UDim2.fromOffset(200, 44) }, "Leave the party", 17)
	kit.onClick(leave, function()
		send("leave")
	end)
	ui.leave = leave
	label(m.panel, { Text = "Invite someone here", display = true, weight = Enum.FontWeight.Heavy, TextSize = 22, Position = UDim2.fromOffset(456, 126), Size = UDim2.fromOffset(400, 26) })
	local others = make("ScrollingFrame", { Position = UDim2.fromOffset(456, 156), Size = UDim2.new(1, -484, 1, -190), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22 }, m.panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, others)
	ui.members, ui.others = members, others
end

local function buildPopup()
	local gui = make("ScreenGui", { Name = "SpikeRushPartyInvite", ResetOnSpawn = false, DisplayOrder = 45 }, player:WaitForChild("PlayerGui"))
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(460, 92), BackgroundColor3 = Color3.fromRGB(14, 16, 28), BorderSizePixel = 0, Visible = false }, gui)
	Gui.corner(f, 10)
	make("UIStroke", { Color = Gui.SIGNAL, Thickness = 2 }, f)
	local text = Gui.label(f, { Text = "", display = true, TextSize = 19, TextWrapped = true, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 40) })
	local yes = kit.actionPlate(f, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -130, 1, -10), Size = UDim2.fromOffset(130, 34) }, "Accept", 17)
	local no = kit.hairButton(f, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -10), Size = UDim2.fromOffset(106, 34) }, "Decline", 16)
	kit.onClick(yes, function()
		if ui.popInvite then
			send("accept", ui.popInvite)
		end
		f.Visible = false
	end)
	kit.onClick(no, function()
		if ui.popInvite then
			send("decline", ui.popInvite)
		end
		f.Visible = false
	end)
	ui.pop = { frame = f, text = text }
end

function PartyMenu.refresh()
	-- the pop-up: the newest invite
	local inv = data.invites[#data.invites]
	if inv and inv.id ~= ui.popShown then
		ui.popShown = inv.id
		ui.popInvite = inv.id
		ui.pop.text.Text = string.format("%s invited you to their party.", inv.from)
		ui.pop.frame.Visible = true
		local id = inv.id
		task.delay(math.max(3, inv.expires or Config.Party.InviteSeconds), function()
			if ui.popInvite == id then
				ui.pop.frame.Visible = false
			end
		end)
	elseif not inv then
		ui.pop.frame.Visible = false
	end
	if not ui.window or not ui.window.root.Visible then
		return
	end
	local party = data.party
	local lead = party and party.leader == player.UserId
	ui.sub.Text = party and (lead and "You lead: when you queue a Quick Match or ranked, your party comes with you, on your side." or "Your leader queues for everyone.")
		or string.format("Team up with up to %d players in this server: the leader's Quick Match or ranked queue takes everyone, on one side.", Config.Party.Max)
	ui.leave.Visible = party ~= false and party ~= nil
	clearList(ui.members)
	local inParty = {}
	if party then
		for i, m in ipairs(party.members) do
			inParty[m.id] = true
			local r = row(ui.members, i)
			label(r, { Text = (m.id == party.leader and "★ " or "") .. m.name, display = true, TextSize = 19, TextColor3 = m.id == player.UserId and Gui.SIGNAL or Gui.CHALK, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -200, 1, 0) })
			if lead and m.id ~= player.UserId then
				local kick = kit.hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(84, 34), ZIndex = 23 }, "Remove", 14)
				kit.onClick(kick, function()
					send("kick", m.id)
				end)
				local give = kit.hairButton(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -98, 0.5, 0), Size = UDim2.fromOffset(84, 34), ZIndex = 23 }, "Lead", 14)
				kit.onClick(give, function()
					send("lead", m.id)
				end)
			end
		end
	else
		label(ui.members, { Text = "Just you for now.", TextSize = 17, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0 })
	end
	clearList(ui.others)
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and not inParty[p.UserId] then
			n = n + 1
			local r = row(ui.others, n)
			label(r, { Text = p.DisplayName, display = true, TextSize = 19, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -140, 1, 0) })
			if not party or lead then
				local inv2 = kit.actionPlate(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 36) }, "Invite", 16)
				kit.onClick(inv2, function()
					send("invite", p.UserId)
				end)
			end
		end
	end
	if n == 0 then
		label(ui.others, { Text = "Nobody else is in this server right now.", TextSize = 17, TextColor3 = Gui.DIM, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0 })
	end
end

function PartyMenu.open()
	ui.window.root.Visible = true
	send("get")
	PartyMenu.refresh()
end

function PartyMenu.init(m)
	mods = m
	kit = mods.MenuController.kit()
	buildWindow()
	buildPopup()
	-- (opened from the top right's Party, MenuController's navBar, and the Ranked window)
	Net.get("Party").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		data.party = p.party or false
		data.invites = p.invites or {}
		if p.notice then
			kit.toast(p.notice)
		end
		PartyMenu.refresh()
		if mods.RankedMenu then
			mods.RankedMenu.refresh()
		end
	end)
	Players.PlayerAdded:Connect(function()
		task.defer(PartyMenu.refresh)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(PartyMenu.refresh)
	end)
end

return PartyMenu
