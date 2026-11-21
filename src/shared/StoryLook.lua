-- The story's faces as Roblox avatars (Config.Story.Cast): a HumanoidDescription for a cast
-- member, and a rig built from it. The dialogue's portraits (StoryDialogue) and a story match's
-- bots (BotService) both dress from here, so a character looks the same talking and playing.
-- A cast row with a UserId wears that account's whole avatar; otherwise a plain rig takes the
-- row's skin, hair and kit colours (and any Accessories the owner lists).

local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local StoryLook = {}
local ST = Config.Story
local SKIN = Color3.fromRGB(234, 184, 146)
local byUser = {} -- UserId -> HumanoidDescription, or false when it wouldn't load

local function fromUser(userId)
	if byUser[userId] == nil then
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		byUser[userId] = (ok and desc) or false
	end
	local d = byUser[userId]
	return d and d:Clone() or nil
end

-- A cast member's look. `shirt` and `shorts` (colours) replace the kit's: a match dresses its
-- bots in their side's colours. Yields the first time a UserId is asked for.
function StoryLook.describe(id, shirt, shorts)
	local c = ST.Cast[id] or {}
	if c.UserId then
		local d = fromUser(c.UserId)
		if d then
			return d
		end
	end
	local d = Instance.new("HumanoidDescription")
	-- (a character without a row of its own: a skin and a hair picked by its id, always the same)
	local hash = 0
	for i = 1, #tostring(id) do
		hash = (hash * 31 + string.byte(tostring(id), i)) % 9973
	end
	local skin = c.Skin or ST.DefaultSkin[hash % #ST.DefaultSkin + 1] or SKIN
	d.HeadColor = skin
	d.LeftArmColor = skin
	d.RightArmColor = skin
	local kit = c.Kit and ST.Kits[c.Kit] or nil
	d.TorsoColor = shirt or (kit and kit[1]) or Color3.fromRGB(120, 124, 140)
	local legs = shorts or (kit and kit[2]) or Color3.fromRGB(40, 44, 60)
	d.LeftLegColor = legs
	d.RightLegColor = legs
	local hair = c.Hair or (not c.Bald and ST.DefaultHair[hash % #ST.DefaultHair + 1]) or nil
	if hair then
		d.HairAccessory = tostring(hair)
	end
	for field, value in pairs(c.Accessories or {}) do
		pcall(function()
			d[field] = value
		end)
	end
	if c.Scale then
		pcall(function()
			d.HeightScale = math.clamp(c.Scale, 0.9, 1.05)
		end)
	end
	return d
end

-- A model that has never been in the world has its accessories wherever they were made (hair
-- hung at the chest): sit each handle on the body by its attachments, as its weld would.
local function seatAccessories(model)
	for _, acc in ipairs(model:GetDescendants()) do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			local att = handle and handle:FindFirstChildWhichIsA("Attachment")
			if att then
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("Attachment") and d.Name == att.Name and d.Parent ~= handle and d.Parent:IsA("BasePart") and not d.Parent:FindFirstAncestorWhichIsA("Accessory") then
						handle.CFrame = d.Parent.CFrame * d.CFrame * att.CFrame:Inverse()
						break
					end
				end
			end
		end
	end
	return model
end

-- A rig of a cast member (R15), or nil when it wouldn't build. `shirt` and `shorts` as
-- StoryLook.describe's. Yields.
function StoryLook.build(id, shirt, shorts)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(StoryLook.describe(id, shirt, shorts), Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return seatAccessories(model)
	end
	-- (hair that won't load shouldn't cost the whole face)
	ok, model = pcall(function()
		local d = StoryLook.describe(id, shirt, shorts)
		d.HairAccessory = ""
		return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	end)
	return ok and model or nil
end

return StoryLook
