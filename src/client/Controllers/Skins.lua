-- Per-character skins (Config.Halloween.Skins): the server writes Skin on a character whose player
-- has one on for it (TeamService.applyToModel, ProfileService.applyActive), and every client
-- dresses that character. The Reaper holds a scythe in the hitting hand (it swings with the arm
-- through every spike); its Souls trail is BallRenderer's, its slash and the hole it tears in the
-- air are VFXController's (Skins.slash lights the blade's trail).
-- The scythe is ToolboxAssets.Skins.ReaperScythe: a Model of MeshParts imported by the owner from
-- assets/skins/ReaperScythe.fbx (Blender: Documents/SpikeRushAnimations/fx/Halloween.blend). Its
-- handle along Y, the blade at the top reaching forward (-Z); the parts are coloured here by name
-- (LOOK), and three tiny markers (Tip, Heel, Grip) say where the star sits, where the slash runs
-- and where the hand holds it. The look follows the owner's reference: a thin dark crescent with
-- a pale edge, a cold blue star at the tip, smoke curling up the shaft; and it's void (the owner:
-- "the scythe should have like void vfx"): a violet rim on the spine, black smoke off the blade.
-- Until the model is in the place, a stand-in of parts.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Fx = require(script.Parent.Fx)

local Skins = {}
local mods
local SCYTHE = "ReaperScythe"
local HEIGHT = 6.6 -- studs from the pommel to the top of the blade
local VOID = Color3.fromRGB(140, 80, 255)
local STAR = Color3.fromRGB(170, 205, 255)

-- each part's colour, material and reflectance, by its Blender name
local LOOK = {
	BladeBody = { Color3.fromRGB(14, 16, 28), Enum.Material.Metal, 0.12 },
	BladeEdge = { Color3.fromRGB(150, 165, 195), Enum.Material.Metal, 0.35 },
	VoidRim = { VOID, Enum.Material.Neon, 0 },
	Shaft = { Color3.fromRGB(16, 11, 11), Enum.Material.Wood, 0 },
	Wrap = { Color3.fromRGB(70, 18, 14), Enum.Material.Fabric, 0 },
	Collar = { Color3.fromRGB(22, 22, 28), Enum.Material.Metal, 0.15 },
	Spur = { Color3.fromRGB(22, 22, 28), Enum.Material.Metal, 0.15 },
	Pommel = { Color3.fromRGB(22, 22, 28), Enum.Material.Metal, 0.15 },
}
local MARKERS = { Tip = true, Heel = true, Grip = true }

local dressed = {} -- character model -> { scythe, hand, kits = { handles }, slash = { trails } }
local folder -- the held scythes (kept out of the characters: they're placed every frame)

local function prep(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
end

-- The stand-in: a dark shaft, a dark blade with a violet spine, and the three markers where the
-- real model has them.
local function standIn()
	local model = Instance.new("Model")
	model.Name = SCYTHE
	local function part(name, class, size, cf, color, material)
		local p = Instance.new(class)
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Parent = model
		return p
	end
	local shaft = part("Shaft", "Part", Vector3.new(0.2, 6, 0.2), CFrame.new(), Color3.fromRGB(16, 11, 11), Enum.Material.Wood)
	part("BladeBody", "WedgePart", Vector3.new(0.08, 0.6, 3), CFrame.new(0, 2.85, -1.5) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(14, 16, 28), Enum.Material.Metal)
	part("VoidRim", "Part", Vector3.new(0.06, 0.06, 3), CFrame.new(0, 3.18, -1.5) * CFrame.Angles(math.rad(-10), 0, 0), VOID, Enum.Material.Neon)
	part("Tip", "Part", Vector3.new(0.05, 0.05, 0.05), CFrame.new(0, 2.6, -3), Color3.new(), Enum.Material.SmoothPlastic)
	part("Heel", "Part", Vector3.new(0.05, 0.05, 0.05), CFrame.new(0, 2.9, 0), Color3.new(), Enum.Material.SmoothPlastic)
	part("Grip", "Part", Vector3.new(0.05, 0.05, 0.05), CFrame.new(0, -1.4, 0), Color3.new(), Enum.Material.SmoothPlastic)
	model.PrimaryPart = shaft
	return model
end

local function scythe()
	local src = Assets.toolbox("Skins." .. SCYTHE)
	local c
	if src then
		c = Assets.sanitize(src:Clone())
		if c:IsA("BasePart") then
			local m = Instance.new("Model")
			c.Name = "Shaft"
			c.Parent = m
			c = m
		end
	else
		c = standIn()
	end
	c.Name = SCYTHE
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then
			prep(d)
			local look = LOOK[d.Name]
			if look then
				d.Color, d.Material, d.Reflectance = look[1], look[2], look[3]
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
			end
			if MARKERS[d.Name] then
				d.Transparency = 1
			end
		end
	end
	c.PrimaryPart = c:FindFirstChild("Shaft", true) or c:FindFirstChildWhichIsA("BasePart", true)
	local root = c.PrimaryPart
	local grip, heel, tip = c:FindFirstChild("Grip", true), c:FindFirstChild("Heel", true), c:FindFirstChild("Tip", true)
	if root and grip and heel and tip then
		-- its pivot from the markers, whatever axes the importer gave it (Studio's turned the
		-- model's pivot a quarter over): at the grip, up the shaft, facing where the blade reaches
		local up = (heel.Position - grip.Position).Unit
		local reach = tip.Position - heel.Position
		local fwd = (reach - up * reach:Dot(up)).Unit
		root.PivotOffset = root.CFrame:ToObjectSpace(CFrame.lookAt(grip.Position, grip.Position + fwd, up))
	end
	if src and root then
		-- whatever size the importer gave it: HEIGHT tall (the extents are along the pivot's axes)
		local size = c:GetExtentsSize()
		if size.Y > 0.1 then
			c:ScaleTo(c:GetScale() * HEIGHT / size.Y)
		end
	end
	return c
end

local function hand(model)
	return model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
end

-- The hitting arm's line this frame, shoulder to hand (R15's upper arm and hand, or R6's one
-- arm), or nil.
local function armLine(model, h)
	local upper = model:FindFirstChild("RightUpperArm")
	if upper then
		return upper.Position + upper.CFrame.UpVector * (upper.Size.Y * 0.4), h.Position
	end
	if h.Name == "Right Arm" then
		local cf = h.CFrame
		return h.Position + cf.UpVector * (h.Size.Y * 0.4), h.Position - cf.UpVector * (h.Size.Y * 0.45)
	end
	return nil
end

-- Where the scythe is held this frame: its grip in the hand, and the shaft steered by the arm
-- (the owner, 2026-10-15: "i want the scythe to move with the body of course, and the scythe to
-- be swung right now it sits idly"). With the arm down, the shaft stands by the leg and rocks
-- with the arm's swing (running, the approach's arm pump); the higher the arm, the more the shaft
-- lies along it, shoulder to hand and on out past the fist, so the bow-and-arrow draws it back
-- over the shoulder and the arm swing whips it through. The blade reaches where the body faces,
-- turning down as the arm rises (the edge leads the swing). A spike on the blade (`swing`:
-- seconds since Skins.slash) chops it on through, forward and down, on top. (The arm's line, not
-- the hand's own turn: a cocked arm bends the hand back down by the ear.)
local CHOP = math.rad(75)
local function holdFrame(model, h, swing)
	local at = (h.CFrame * CFrame.new(0, -0.15, 0)).Position
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return CFrame.new(at)
	end
	local body = root.CFrame
	local up, look, right = body.UpVector, body.LookVector, body.RightVector
	local shoulder, fist = armLine(model, h)
	local arm = -up
	if shoulder and (fist - shoulder).Magnitude > 0.05 then
		arm = (fist - shoulder).Unit
	end
	-- 0 with the arm hanging, 1 from a little over level
	local raised = math.clamp((arm:Dot(up) + 0.25) / 0.55, 0, 1)
	local idle = (up + look * (arm:Dot(look) * 0.8) + right * 0.12).Unit
	local shaft = idle * (1 - raised) + arm * raised
	if shaft.Magnitude < 1e-3 then
		shaft = up
	end
	shaft = shaft.Unit
	local reach = look * (1 - 0.5 * raised) - up * (0.7 * raised)
	if swing and swing < 0.6 then
		-- on through in a tenth of a second, held, then eased back
		local k = 1
		if swing < 0.1 then
			k = 1 - (1 - swing / 0.1) ^ 3
		elseif swing > 0.32 then
			k = 1 - math.min((swing - 0.32) / 0.28, 1) ^ 2
		end
		local turn = CFrame.fromAxisAngle(right, -CHOP * k) -- (about the body's side: up goes forward)
		shaft = turn:VectorToWorldSpace(shaft)
		reach = turn:VectorToWorldSpace(reach)
	end
	local blade = reach - shaft * reach:Dot(shaft)
	if blade.Magnitude < 1e-3 then
		blade = look - shaft * look:Dot(shaft)
	end
	if blade.Magnitude < 1e-3 then
		blade = -up
	end
	return CFrame.lookAt(at, at + blade.Unit, shaft)
end

local function attachAt(part, worldPos, name)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = part -- (parented first: WorldPosition is relative to the part)
	a.WorldPosition = worldPos
	return a
end

-- The blade's slash: two ribbons from the heel to the tip, lit while the arm swings: an unlit
-- black one inside, a violet one round it (Blade Ball's neon on black).
local function slashTrails(blade, heel, tip)
	local out = {}
	for i, spec in ipairs({
		{ inset = 0, color = ColorSequence.new(Color3.fromRGB(190, 160, 255), VOID), glow = 1, life = 0.22, alpha = 0.1 },
		{ inset = 0.18, color = ColorSequence.new(Color3.fromRGB(6, 3, 14)), glow = 0, life = 0.16, alpha = 0.04 },
	}) do
		local a0 = attachAt(blade, heel:Lerp(tip, spec.inset), "SlashA" .. i)
		local a1 = attachAt(blade, tip:Lerp(heel, spec.inset * 0.5), "SlashB" .. i)
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Color = spec.color
		t.LightEmission = spec.glow
		t.LightInfluence = 0
		t.Lifetime = spec.life
		t.MinLength = 0.02
		t.FaceCamera = false
		t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.alpha), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 1) })
		t.Enabled = false
		t.Parent = blade
		table.insert(out, t)
	end
	return out
end

local function undress(model)
	local st = dressed[model]
	if not st then
		return
	end
	dressed[model] = nil
	for _, h in ipairs(st.kits) do
		pcall(h.destroy)
	end
	if st.scythe then
		st.scythe:Destroy()
	end
end

-- Puts the scythe in the hitting hand with its void effects: held low on the shaft (the Grip
-- marker, its pivot), placed every frame by holdFrame.
local function dress(model)
	local h = hand(model)
	if not h then
		return
	end
	local s = scythe()
	local root = s.PrimaryPart
	if not root then
		s:Destroy()
		return
	end
	s:PivotTo(holdFrame(model, h))
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "SpikeRushSkins"
		folder.Parent = workspace
	end
	s.Parent = folder

	local st = { scythe = s, hand = h, kits = {}, slash = {} }
	dressed[model] = st
	local tipPart = s:FindFirstChild("Tip", true)
	local heelPart = s:FindFirstChild("Heel", true)
	local blade = s:FindFirstChild("BladeBody", true) or root
	local tip = tipPart and tipPart.Position or blade.Position
	local heel = heelPart and heelPart.Position or root.Position
	-- the cold star on the tip, with its light
	local tipAt = attachAt(blade, tip, "VoidStar")
	local light = Instance.new("PointLight")
	light.Color = STAR
	light.Range = 7
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = tipAt
	local function kit(name, at)
		local ok, handle = pcall(Fx.attach, name, at)
		if ok and handle then
			handle.set(true)
			table.insert(st.kits, handle)
		end
	end
	kit("ScytheStar", tipAt)
	kit("ScytheVoid", attachAt(blade, heel:Lerp(tip, 0.45), "VoidSmoke"))
	kit("ScytheWisp", attachAt(root, heel - (tip - heel).Unit * 0.2 - Vector3.new(0, 0.4, 0), "Wisp"))
	-- the violet rim breathes
	local rim = s:FindFirstChild("VoidRim", true)
	if rim then
		rim.Transparency = 0.05
		TweenService:Create(rim, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.45 }):Play()
	end
	st.slash = slashTrails(blade, heel, tip)
end

-- A Reaper's spike (VFXController's onHit): the scythe chops through (holdFrame) with the blade's
-- slash trail lit for `seconds`.
function Skins.slash(model, seconds)
	local st = model and dressed[model]
	if not st then
		return
	end
	st.swingAt = os.clock()
	for _, t in ipairs(st.slash) do
		t.Enabled = true
	end
	task.delay(seconds or 0.3, function()
		if dressed[model] == st then
			for _, t in ipairs(st.slash) do
				t.Enabled = false
			end
		end
	end)
end

-- Whether that character is wearing the Reaper.
function Skins.isReaper(model)
	return model ~= nil and model:GetAttribute("Skin") == "Reaper"
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
	local seen = {}
	for _, model in ipairs(list) do
		seen[model] = true
		local want = Skins.isReaper(model)
		local st = dressed[model]
		local has = st and st.scythe and st.scythe.Parent ~= nil and st.hand.Parent == model
		if want and not has then
			undress(model)
			dress(model)
		elseif has and not want then
			undress(model)
		end
	end
	for model in pairs(dressed) do
		if not seen[model] or not model.Parent then
			undress(model)
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
		-- every held scythe follows its hand and arm (after the frame's animation and physics)
		for model, st in pairs(dressed) do
			if st.hand.Parent == model and st.scythe.Parent then
				st.scythe:PivotTo(holdFrame(model, st.hand, st.swingAt and os.clock() - st.swingAt))
			end
		end
	end)
end

return Skins
