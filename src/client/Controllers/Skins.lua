-- Per-character skins (Config.Halloween.Skins): the server writes Skin on a character whose player
-- has one on for it (TeamService.applyToModel, ProfileService.applyActive), and every client
-- dresses that character. The Reaper holds a scythe in the hitting hand (it swings with the arm
-- through every spike); its Souls trail is BallRenderer's.
-- The scythe is ToolboxAssets.Skins.ReaperScythe (a Model or MeshPart, modelled in Blender and
-- imported by the owner: its handle along its Y axis, the blade at the top, about 6 studs tall);
-- until that's in the place, a stand-in of parts.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)

local Skins = {}
local mods
local SCYTHE = "ReaperScythe"

local function prep(p)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
end

-- The stand-in: a dark shaft, a pale curved blade, a cold glow.
local function standIn()
	local color = Config.Halloween.Skins.Reaper.Color
	local model = Instance.new("Model")
	model.Name = SCYTHE
	local shaft = Instance.new("Part")
	shaft.Name = "Handle"
	shaft.Size = Vector3.new(0.22, 6, 0.22)
	shaft.Color = Color3.fromRGB(28, 22, 30)
	shaft.Material = Enum.Material.Wood
	shaft.CFrame = CFrame.new()
	shaft.Parent = model
	local blade = Instance.new("WedgePart")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.08, 0.7, 2.6)
	blade.Color = Color3.fromRGB(205, 215, 230)
	blade.Material = Enum.Material.Metal
	blade.Reflectance = 0.2
	blade.CFrame = CFrame.new(0, 2.85, -1.3) * CFrame.Angles(math.rad(-12), 0, 0)
	blade.Parent = model
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 8
	glow.Brightness = 1.2
	glow.Parent = blade
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = shaft
	weld.Part1 = blade
	weld.Parent = shaft
	model.PrimaryPart = shaft
	return model
end

local function scythe()
	local src = Assets.toolbox("Skins." .. SCYTHE)
	if src then
		local c = Assets.sanitize(src:Clone())
		if c:IsA("BasePart") then
			local m = Instance.new("Model")
			c.Name = "Handle"
			c.Parent = m
			m.PrimaryPart = c
			c = m
		end
		c.Name = SCYTHE
		if not c.PrimaryPart then
			c.PrimaryPart = c:FindFirstChildWhichIsA("BasePart", true)
		end
		return c
	end
	return standIn()
end

local function hand(model)
	return model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
end

-- Puts the scythe in the hitting hand (held a little below its middle, blade up and forward).
local function dress(model)
	local h = hand(model)
	if not h then
		return
	end
	local s = scythe()
	if not s.PrimaryPart then
		s:Destroy()
		return
	end
	for _, d in ipairs(s:GetDescendants()) do
		if d:IsA("BasePart") then
			prep(d)
		end
	end
	s:PivotTo(h.CFrame * CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, 0.8, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = h
	weld.Part1 = s.PrimaryPart
	weld.Parent = s.PrimaryPart
	s.Parent = model
end

-- Every character on court (and your own, in the menus): dressed while its Skin says so.
local function sweep()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, m in ipairs(bots:GetChildren()) do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	for _, model in ipairs(list) do
		local want = model:GetAttribute("Skin") == "Reaper"
		local has = model:FindFirstChild(SCYTHE)
		if want and not has then
			dress(model)
		elseif has and not want then
			has:Destroy()
		end
	end
end

function Skins.init(m)
	mods = m
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc >= 0.5 then
			acc = 0
			sweep()
		end
	end)
end

return Skins
