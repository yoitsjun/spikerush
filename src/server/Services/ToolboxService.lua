-- Toolbox (Creator Store) assets by id.
--
-- Fills ReplicatedStorage.ToolboxAssets.<Category>.<Slot> from the ids in Assets.Toolbox, so
-- Toolbox models and effects plug into the game without touching code. A slot that already
-- holds an instance (dragged in by hand in Studio, or baked with install()) is left alone.
--
-- Runtime loading tries AssetService:LoadAssetAsync first, which reads any free Creator Store
-- model once Game Settings > Security > "Allow Loading Third Party Assets" is on, then
-- InsertService, which only loads assets owned by the place's owner or by Roblox ("Get" a free
-- model first so it sits in your inventory, or in the owning group's). install() runs from the
-- Studio command bar with game:GetObjects, which can read any public asset, and bakes the result
-- into the place:
--   require(game.ServerScriptService.Server.Services.ToolboxService).install()
-- Every inserted asset is sanitized (Assets.sanitize): scripts are deleted before it is parented.

local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)

local ToolboxService = {}

local function folder(category)
	local root = ReplicatedStorage:FindFirstChild("ToolboxAssets")
	if not root then
		root = Instance.new("Folder")
		root.Name = "ToolboxAssets"
		root.Parent = ReplicatedStorage
	end
	local f = root:FindFirstChild(category)
	if not f then
		f = Instance.new("Folder")
		f.Name = category
		f.Parent = root
	end
	return f
end

-- An asset arrives wrapped (LoadAsset returns a Model around it; GetObjects returns a list).
-- Keep the single top-level object when there is one, otherwise keep the wrapper.
local function unwrap(list)
	local useful = {}
	for _, inst in ipairs(list) do
		if not inst:IsA("LuaSourceContainer") then
			table.insert(useful, inst)
		end
	end
	if #useful == 1 then
		return useful[1]
	end
	if #useful == 0 then
		return nil
	end
	local model = Instance.new("Model")
	for _, inst in ipairs(useful) do
		inst.Parent = model
	end
	return model
end

local function place(category, slot, inst)
	Assets.sanitize(inst)
	inst.Name = slot
	local yaw = Assets.ToolboxYaw and Assets.ToolboxYaw[slot]
	if yaw and inst:GetAttribute("Yaw") == nil then
		inst:SetAttribute("Yaw", yaw)
	end
	inst.Parent = folder(category)
	return inst
end

-- Runtime: AssetService (any free Creator Store model when the experience allows third-party
-- assets), else InsertService (owner's or Roblox's assets only).
local function loadRuntime(id)
	local ok, result = pcall(function()
		return AssetService:LoadAssetAsync(id)
	end)
	if not ok or not result then
		local err = result
		ok, result = pcall(function()
			return InsertService:LoadAsset(id)
		end)
		if not ok or not result then
			return nil, tostring(result) .. " (AssetService: " .. tostring(err) .. ")"
		end
	end
	local inst = unwrap(result:GetChildren())
	if inst then
		inst.Parent = nil
	end
	result:Destroy()
	return inst
end

-- Studio command bar: game:GetObjects reads any public asset.
local function loadStudio(id)
	local ok, list = pcall(function()
		return game:GetObjects("rbxassetid://" .. tostring(id))
	end)
	if ok and type(list) == "table" and #list > 0 then
		return unwrap(list)
	end
	return loadRuntime(id)
end

local function each(fn)
	for category, slots in pairs(Assets.Toolbox or {}) do
		for slot, value in pairs(slots) do
			local id = Assets.number(value)
			if id then
				fn(category, slot, id)
			end
		end
	end
end

function ToolboxService.loadAll()
	local loaded, failed = 0, 0
	each(function(category, slot, id)
		if folder(category):FindFirstChild(slot) then
			return
		end
		local inst, err = loadRuntime(id)
		if inst then
			place(category, slot, inst)
			loaded = loaded + 1
		else
			failed = failed + 1
			warn(string.format("[SpikeRush] Toolbox %s.%s (%d) did not load: %s. Get it to the place owner's inventory, or bake it with ToolboxService.install() in Studio.", category, slot, id, tostring(err)))
		end
	end)
	if loaded > 0 or failed > 0 then
		print(string.format("[SpikeRush] Toolbox assets: %d loaded, %d failed", loaded, failed))
	end
end

-- Bake every id into the place from the Studio command bar (edit mode). Pass true to replace
-- slots that are already filled. Save the place afterwards to keep them.
function ToolboxService.install(replace)
	local done = 0
	each(function(category, slot, id)
		local existing = folder(category):FindFirstChild(slot)
		if existing and not replace then
			print(string.format("[SpikeRush] %s.%s already filled, skipped", category, slot))
			return
		end
		local inst = loadStudio(id)
		if not inst then
			warn(string.format("[SpikeRush] %s.%s: asset %d could not be loaded", category, slot, id))
			return
		end
		if existing then
			existing:Destroy()
		end
		place(category, slot, inst)
		done = done + 1
		print(string.format("[SpikeRush] %s.%s <- %d (%s)", category, slot, id, inst.ClassName))
	end)
	print(string.format("[SpikeRush] Installed %d Toolbox asset(s). Save the place to keep them.", done))
	return done
end

function ToolboxService.init()
	if not RunService:IsRunning() then
		return
	end
	-- sanitize anything that was dragged into the folders by hand, then fill the empty slots
	local root = ReplicatedStorage:FindFirstChild("ToolboxAssets")
	if root then
		for _, category in ipairs(root:GetChildren()) do
			for _, item in ipairs(category:GetChildren()) do
				if item:IsA("LuaSourceContainer") then
					item:Destroy()
				else
					Assets.sanitize(item)
				end
			end
		end
	end
	task.spawn(ToolboxService.loadAll)
end

return ToolboxService
