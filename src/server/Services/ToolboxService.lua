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

local function place(category, slot, inst, id, path)
	Assets.sanitize(inst)
	inst.Name = slot
	for key, value in pairs(Assets.ToolboxAttributes and Assets.ToolboxAttributes[slot] or {}) do
		if inst:GetAttribute(key) == nil then
			inst:SetAttribute(key, value)
		end
	end
	inst:SetAttribute("AssetId", tostring(id) .. (path ~= "" and ("/" .. path) or ""))
	inst.Parent = folder(category)
	return inst
end

-- The piece at `path` ("A/B/C") inside a loaded pack. Packs repeat names (two folders called
-- "Folder"), so every child with the right name is tried.
local function findPath(root, path)
	local names = {}
	for name in string.gmatch(path, "[^/]+") do
		table.insert(names, name)
	end
	local function walk(node, i)
		if i > #names then
			return node
		end
		for _, c in ipairs(node:GetChildren()) do
			if c.Name == names[i] then
				local found = walk(c, i + 1)
				if found then
					return found
				end
			end
		end
		return nil
	end
	return walk(root, 1)
end

-- A copy of the slot's piece out of a pack loaded once per id (several slots share packs).
local function piece(packs, id, path, load)
	local pack = packs[id]
	if pack == nil then
		pack = load(id) or false
		packs[id] = pack
	end
	if not pack then
		return nil, "the asset did not load"
	end
	if path == "" then
		packs[id] = nil -- the whole asset goes into the slot
		return pack
	end
	local found = findPath(pack, path)
	if not found then
		return nil, "no " .. path .. " inside it"
	end
	return found:Clone()
end

local function dropPacks(packs)
	for _, pack in pairs(packs) do
		if pack then
			pack:Destroy()
		end
	end
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
			local id, path = Assets.ref(value)
			if id then
				fn(category, slot, id, path)
			end
		end
	end
end

function ToolboxService.loadAll()
	local loaded, failed = 0, 0
	local packs = {}
	each(function(category, slot, id, path)
		if folder(category):FindFirstChild(slot) then
			return
		end
		local inst, err = piece(packs, id, path, loadRuntime)
		if inst then
			place(category, slot, inst, id, path)
			loaded = loaded + 1
		else
			failed = failed + 1
			warn(string.format("[SpikeRush] Toolbox %s.%s (%d) did not load: %s. Get it to the place owner's inventory, or bake it with ToolboxService.install() in Studio.", category, slot, id, tostring(err)))
		end
	end)
	dropPacks(packs)
	if loaded > 0 or failed > 0 then
		print(string.format("[SpikeRush] Toolbox assets: %d loaded, %d failed", loaded, failed))
	end
end

-- Bake every id into the place from the Studio command bar (edit mode). Pass true to replace
-- slots that are already filled. Save the place afterwards to keep them.
function ToolboxService.install(replace)
	local done = 0
	local packs = {}
	each(function(category, slot, id, path)
		local existing = folder(category):FindFirstChild(slot)
		if existing and not replace then
			print(string.format("[SpikeRush] %s.%s already filled, skipped", category, slot))
			return
		end
		local inst, err = piece(packs, id, path, loadStudio)
		if not inst then
			warn(string.format("[SpikeRush] %s.%s: asset %d could not be used: %s", category, slot, id, tostring(err)))
			return
		end
		if existing then
			existing:Destroy()
		end
		place(category, slot, inst, id, path)
		done = done + 1
		print(string.format("[SpikeRush] %s.%s <- %d%s (%s)", category, slot, id, path ~= "" and ("/" .. path) or "", inst.ClassName))
	end)
	dropPacks(packs)
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
