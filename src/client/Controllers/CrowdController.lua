-- Atmosphere, all client-side: a crowd seated on the far-side and end stands (the backdrop of
-- the side view; density scales down on mobile) that sways, then erupts for the team that
-- scored; scrolling LED ribbon boards; and the jumbotron on the far wall with the live score.
-- Crowd motion uses one BulkMoveTo per update.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Court = require(Shared.Court)
local State = require(script.Parent.State)

local CrowdController = {}

local UI = Config.UI
local fans = {}
local parts, cframes = {}, {}
local hype = { Home = 0, Away = 0 }
local ledLabels = {}
local jumboLabels = {}
local ledOffset = 0

local NEUTRAL = {
	Color3.fromRGB(235, 235, 240),
	Color3.fromRGB(60, 62, 80),
	Color3.fromRGB(210, 60, 90),
	Color3.fromRGB(90, 200, 140),
	Color3.fromRGB(250, 210, 90),
}
local SKIN = {
	Color3.fromRGB(255, 219, 172),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
}

local function fanPart(shape, size, color, parent)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildCrowd()
	local folder = Instance.new("Folder")
	folder.Name = "SpikeRushCrowd"
	folder.Parent = workspace
	local density = State.isMobile and Config.Graphics.CrowdDensityMobile or Config.Graphics.CrowdDensityDesktop
	local rng = Random.new(7)
	for _, row in ipairs(Court.standRows()) do
		local count = math.floor(row.length / 2.2)
		for i = 0, count - 1 do
			if rng:NextNumber() < density then
				local along = -row.length / 2 + (i + 0.5) * (row.length / count) + (rng:NextNumber() - 0.5) * 0.5
				local pos, look
				if row.axis == "X" then
					pos = Vector3.new(row.center.X, row.top + 1.0, along)
					look = Vector3.new(-row.sign, 0, 0)
				else
					pos = Vector3.new(row.center.X + along, row.top + 1.0, row.center.Z)
					look = Vector3.new(0, 0, -row.sign)
				end
				-- fans sit behind the team whose half they're on
				local team = pos.Z < 0 and "Home" or "Away"
				local shirt
				if rng:NextNumber() < 0.62 then
					local base = Config.Teams[team].Color
					shirt = base:Lerp(Color3.new(1, 1, 1), rng:NextNumber() * 0.25)
				else
					shirt = NEUTRAL[rng:NextInteger(1, #NEUTRAL)]
				end
				local base = CFrame.lookAt(pos, pos + look)
				local body = fanPart(Enum.PartType.Block, Vector3.new(1.5, 1.9, 0.9), shirt, folder)
				local head = fanPart(Enum.PartType.Ball, Vector3.new(1.05, 1.05, 1.05), SKIN[rng:NextInteger(1, #SKIN)], folder)
				table.insert(fans, {
					body = body,
					head = head,
					base = base,
					team = team,
					phase = rng:NextNumber() * math.pi * 2,
					freq = 7 + rng:NextNumber() * 4,
					arms = rng:NextNumber() < 0.5,
				})
				table.insert(parts, body)
				table.insert(parts, head)
				table.insert(cframes, base)
				table.insert(cframes, base * CFrame.new(0, 1.45, 0))
			end
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function updateCrowd(t)
	local idle = 0.06
	local n = 0
	for _, f in ipairs(fans) do
		local h = hype[f.team]
		local bounce = math.abs(math.sin(t * f.freq * (0.5 + h * 0.6) + f.phase)) * (idle + h * 0.9)
		local sway = math.sin(t * 1.3 + f.phase) * 0.06
		local cf = f.base * CFrame.new(0, bounce, 0) * CFrame.Angles(0, 0, sway)
		n = n + 1
		cframes[n] = cf
		n = n + 1
		cframes[n] = cf * CFrame.new(0, 1.45, 0)
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

------------------------------------------------------------------------------------------
-- LED boards and jumbotron
------------------------------------------------------------------------------------------

local function surface(part, face, ppStud)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = ppStud
	g.LightInfluence = 0
	g.Brightness = 2.2
	g.Adornee = part
	g.ResetOnSpawn = false
	g.Parent = State.player:WaitForChild("PlayerGui")
	return g
end

local function tickerText()
	local home, away = Config.Teams.Home.Name, Config.Teams.Away.Name
	return string.rep("Spike Rush      " .. home .. " vs " .. away .. "      ", 4)
end

local function buildBoards(arena)
	local led = arena:WaitForChild("LEDBoards", 20)
	if led then
		for _, p in ipairs(led:GetChildren()) do
			local faceName = p:GetAttribute("Face")
			local ok, face = pcall(function()
				return Enum.NormalId[faceName]
			end)
			if ok and face then
				local g = surface(p, face, 20)
				local clip = Instance.new("Frame")
				clip.BackgroundColor3 = UI.Ink
				clip.BorderSizePixel = 0
				clip.ClipsDescendants = true
				clip.Size = UDim2.fromScale(1, 1)
				clip.Parent = g
				local l = Instance.new("TextLabel")
				l.BackgroundTransparency = 1
				l.Size = UDim2.new(4, 0, 1, 0)
				l.Font = Enum.Font.GothamBlack
				l.TextScaled = true
				l.TextColor3 = UI.Spark
				l.TextXAlignment = Enum.TextXAlignment.Left
				l.Text = tickerText()
				l.Parent = clip
				table.insert(ledLabels, l)
			end
		end
	end
	local jumbo = arena:WaitForChild("Jumbotron", 20)
	local body = jumbo and jumbo:WaitForChild("Body", 10)
	if body then
		local faces = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
		local faceName = body:GetAttribute("Face")
		if faceName then
			local ok, face = pcall(function()
				return Enum.NormalId[faceName]
			end)
			if ok and face then
				faces = { face }
			end
		end
		for _, face in ipairs(faces) do
			local g = surface(body, face, 16)
			local bg = Instance.new("Frame")
			bg.BackgroundColor3 = Color3.fromRGB(8, 10, 22)
			bg.BorderSizePixel = 0
			bg.Size = UDim2.fromScale(1, 1)
			bg.Parent = g
			local score = Instance.new("TextLabel")
			score.BackgroundTransparency = 1
			score.Size = UDim2.fromScale(1, 0.62)
			score.Position = UDim2.fromScale(0, 0.06)
			score.Font = Enum.Font.GothamBlack
			score.TextScaled = true
			score.RichText = true
			score.TextColor3 = UI.Chalk
			score.Parent = bg
			local sub = Instance.new("TextLabel")
			sub.BackgroundTransparency = 1
			sub.Size = UDim2.fromScale(1, 0.24)
			sub.Position = UDim2.fromScale(0, 0.7)
			sub.Font = Enum.Font.GothamBold
			sub.TextScaled = true
			sub.TextColor3 = UI.Spark
			sub.Parent = bg
			table.insert(jumboLabels, { score = score, sub = sub })
		end
	end
end

local function hex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function refreshJumbo(flash)
	local m = State.match
	local home, away = Config.Teams.Home, Config.Teams.Away
	local s = m.scores or {}
	local text, sub
	if m.inMatch then
		text = string.format('<font color="%s">%s</font> %d : %d <font color="%s">%s</font>', hex(home.Color), home.Short, s.Home or 0, s.Away or 0, hex(away.Color), away.Short)
		local sets = m.sets or {}
		sub = string.format("Set %d, sets %d-%d", m.setNumber or 1, sets.Home or 0, sets.Away or 0)
	else
		text = "Spike Rush"
		sub = "Next match soon"
	end
	if flash then
		sub = flash
	end
	for _, j in ipairs(jumboLabels) do
		j.score.Text = text
		j.sub.Text = sub
	end
end

function CrowdController.init()
	task.spawn(function()
		local arena = workspace:WaitForChild("Arena", 60)
		if not arena then
			return
		end
		buildCrowd()
		buildBoards(arena)
		refreshJumbo()
	end)
	State.signals.Match:Connect(function()
		refreshJumbo()
	end)
	State.signals.Announce:Connect(function(a)
		if a.kind == "Point" and a.winner then
			hype[a.winner] = 1
			hype[a.winner == "Home" and "Away" or "Home"] = 0.1
			local flash = nil
			local shout = { Spike = "Spike!", Ace = "Ace!", Stuff = "Stuff block!", Feint = "Feint!", Break = "Guard break!" }
			if shout[a.reason] then
				flash = shout[a.reason] .. "  " .. Config.Teams[a.winner].Name
			end
			refreshJumbo(flash)
			task.delay(2.2, function()
				refreshJumbo()
			end)
		elseif a.kind == "MatchEnd" or a.kind == "SetEnd" then
			hype.Home, hype.Away = 1, 1
		end
	end)
	local acc = 0
	local interval = 1 / Config.Graphics.CrowdUpdateHz
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		ledOffset = (ledOffset + dt * 0.035) % 0.5
		for _, l in ipairs(ledLabels) do
			l.Position = UDim2.fromScale(-ledOffset * 2, 0)
		end
		hype.Home = math.max(0, hype.Home - dt * 0.35)
		hype.Away = math.max(0, hype.Away - dt * 0.35)
		if acc >= interval and #parts > 0 then
			acc = 0
			updateCrowd(os.clock())
		end
	end)
end

return CrowdController
