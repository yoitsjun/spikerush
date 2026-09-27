-- Audio: the owner's own sounds only. Every sound resolves in this order:
--   1. ReplicatedStorage.ToolboxAssets.Sounds.<Key> (a Sound holding one of the owner's uploads)
--   2. Assets.Sounds[Key] (the id of one of the owner's uploads)
--   3. BORROW: another slot's sound (a heavy variant's normal sound, deeper and louder; the
--      recruit sequence's old sounds)
-- An empty slot plays nothing. Every sound is fetched at start, so none is late the first time,
-- starts past the silence at the front of its file, and plays at its file's gain
-- (Assets.SoundFiles). Hits at the ball are full volume anywhere on court, panned by position.
-- Hit sounds scale with power: a harder spike is louder and a touch lower.

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Assets = require(Shared.Assets)
local Util = require(Shared.Util)
local State = require(script.Parent.State)

local AudioController = {}

local group
local holder
local loops = {}
local lastPlayed = {}
local freeAttachments = {} -- positional sounds reuse their emitter attachments
local hardSpike = false -- the ball in the air came off a hard spike: it lands with FloorHitHeavy
local serveCheer = nil -- the crowd's swell on a serve toss, cut off when the serve is struck
local bank -- a folder of loaded sounds, one per upload
local masters = {}

-- The loaded copy of an upload that every play clones: a clone starts at once, even from past the
-- silence at the front of its file, where a brand-new Sound given a start offset takes about 0.3 s
-- to begin.
local function master(id)
	local m = masters[id]
	if not m then
		m = Instance.new("Sound")
		m.SoundId = id
		m.Parent = bank or SoundService
		masters[id] = m
	end
	return m
end

-- An empty slot borrows another slot's sound: { key, volume, speed }. A filled Spike covers hard
-- spikes until SpikeHeavy gets its own; the recruit sequence keeps the sounds it used before it
-- had slots.
local BORROW = {
	SpikeHeavy = { "Spike", 1.3, 0.9 },
	FloorHitHeavy = { "FloorHit", 1.3, 0.9 },
	Feint = { "Set", 0.7, 1.15 },
	Whiff = { "Whoosh", 0.8 },
	RecruitOpen = { "Whoosh" },
	RecruitOpenGold = { "Thunder" },
	RecruitOpenMythic = { "Boom" },
	RecruitPop = { "UIClick" },
	RecruitReveal = { "Point" },
	RecruitRevealGold = { "CrowdCheer" },
	RecruitCharge = { "Boom" },
	RecruitSpike = { "SpikeHeavy" },
}

-- A slot's upload: its id, or one of its variants at random.
local function pick(value)
	if type(value) == "table" then
		return #value > 0 and value[math.random(#value)] or nil
	end
	return value
end

local function resolve(key)
	local tb = Assets.toolbox("Sounds." .. key)
	if tb and tb:IsA("Sound") then
		local f = Assets.soundFile(tb.SoundId) or {}
		return { template = tb, volume = f.gain, start = f.start }
	end
	local value = pick(Assets.Sounds[key])
	local id = Assets.id(value)
	if id then
		local f = Assets.soundFile(value) or {}
		return { id = id, volume = f.gain or 1, speed = 1, start = f.start }
	end
	local b = BORROW[key]
	local base = b and resolve(b[1])
	if base then
		return { template = base.template, id = base.id, volume = (base.volume or 1) * (b[2] or 1), speed = (base.speed or 1) * (b[3] or 1), start = base.start }
	end
	return nil
end

local function spawnSound(info, opts)
	local sound
	if info.template then
		sound = Assets.sanitize(info.template:Clone())
		sound.Volume = sound.Volume * (info.volume or 1)
		sound.PlaybackSpeed = sound.PlaybackSpeed * (info.speed or 1)
	else
		sound = master(info.id):Clone()
		sound.Volume = info.volume or 1
		sound.PlaybackSpeed = info.speed or 1
	end
	sound.Volume = sound.Volume * (opts.volume or 1)
	sound.PlaybackSpeed = sound.PlaybackSpeed * (opts.speed or 1)
	sound.SoundGroup = group
	if opts.pos then
		local att = table.remove(freeAttachments)
		if not att then
			att = Instance.new("Attachment")
			att.Parent = holder
		end
		att.WorldPosition = opts.pos
		-- full volume out to the camera (60 to 130 studs back), still panned by where it happened
		sound.RollOffMinDistance = 140
		sound.RollOffMaxDistance = 600
		sound.Parent = att
		local done = false
		local function finish()
			if done then
				return
			end
			done = true
			sound:Destroy()
			table.insert(freeAttachments, att)
		end
		sound.Ended:Connect(finish)
		task.delay(6, finish)
	else
		sound.Parent = SoundService
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
		task.delay(6, function()
			if sound.Parent then
				sound:Destroy()
			end
		end)
	end
	if info.start then
		sound.TimePosition = info.start
	end
	sound:Play()
	return sound
end

-- opts: volume, speed, pos (Vector3 for 3D), minGap
function AudioController.play(key, opts)
	opts = opts or {}
	local info = resolve(key)
	if not info then
		return nil
	end
	local now = os.clock()
	if lastPlayed[key] and now - lastPlayed[key] < (opts.minGap or 0.03) then
		return nil
	end
	lastPlayed[key] = now
	return spawnSound(info, opts)
end

-- The serve is struck (any touch after the toss): the crowd's swell stops.
local function stopServeCheer()
	local s = serveCheer
	serveCheer = nil
	if s and s.Parent then
		TweenService:Create(s, TweenInfo.new(0.1), { Volume = 0 }):Play()
		task.delay(0.1, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
end

local function loop(key, volume)
	if loops[key] then
		return loops[key]
	end
	local info = resolve(key)
	if not info or not (info.template or (Assets.Sounds[key] and Assets.Sounds[key] ~= "")) then
		return nil
	end
	local s
	if info.template then
		s = Assets.sanitize(info.template:Clone())
	else
		s = Instance.new("Sound")
		s.SoundId = info.id
	end
	s.Looped = true
	s.Volume = volume
	s.SoundGroup = group
	s.Parent = SoundService
	s:Play()
	loops[key] = s
	return s
end

local function onHit(snap)
	local meta = snap.meta
	if not meta or not snap.path then
		return
	end
	local pos = snap.path.segs[1].p
	local ht = meta.hitType
	local kmh = meta.kmh or 0
	if ht ~= "Toss" then
		stopServeCheer()
	end
	hardSpike = (ht == "Spike" or ht == "JumpServe") and (meta.thunder == true or kmh >= 130)
	if ht == "Spike" or ht == "JumpServe" then
		if meta.thunder then
			AudioController.play("Thunder", { pos = pos, volume = 1.2 })
			AudioController.play("SpikeHeavy", { pos = pos })
		elseif meta.energy then
			AudioController.play("AzureRelease", { pos = pos, speed = 1.1 - 0.35 * math.min(meta.energy, 1) })
			if kmh >= 130 then
				AudioController.play("SpikeHeavy", { pos = pos, volume = 0.8 })
			end
		elseif kmh >= 130 then
			AudioController.play("SpikeHeavy", { pos = pos })
		else
			local k = math.clamp(kmh / 140, 0, 1)
			AudioController.play("Spike", { pos = pos, speed = 1.1 - k * 0.15, volume = 0.8 + k * 0.6 })
		end
		if kmh >= 110 then
			AudioController.play("Whoosh", { pos = pos, speed = 0.8 })
		end
	elseif ht == "Block" then
		if meta.outcome == "Stuff" then
			AudioController.play("Stuff", { pos = pos })
		else
			AudioController.play("Block", { pos = pos, volume = 0.8 })
		end
	elseif ht == "Set" then
		AudioController.play("Set", { pos = pos })
	elseif ht == "Toss" then
		AudioController.play("Toss", { pos = pos })
		serveCheer = AudioController.play("CrowdServe", { volume = 0.9, minGap = 1 }) or serveCheer
	elseif ht == "Overhand" or ht == "Underhand" then
		AudioController.play("Serve", { pos = pos, speed = ht == "Underhand" and 1.15 or 1 })
	elseif ht == "Feint" then
		AudioController.play("Feint", { pos = pos })
	else
		if meta.fail or meta.breaks then
			AudioController.play("GuardBreak", { pos = pos })
		elseif meta.perfect then
			AudioController.play("ReceivePerfect", { pos = pos })
		else
			AudioController.play("Bump", { pos = pos, speed = 0.95 + (meta.quality or 0.5) * 0.15 })
		end
		-- the crowd reacts when a hard spike gets dug
		if meta.drain and not meta.fail and (meta.quality or 0) >= 0.42 then
			AudioController.play("CrowdGasp", { volume = 0.6, minGap = 0.5 })
		end
	end
end

-- Load every sound now (the bank's copies), so none is late the first time it plays.
local function preload()
	local list = {}
	for _, value in pairs(Assets.Sounds) do
		for _, v in ipairs(type(value) == "table" and value or { value }) do
			local id = Assets.id(v)
			if id then
				table.insert(list, master(id))
			end
		end
	end
	local folder = Assets.toolbox("Sounds")
	for _, s in ipairs(folder and folder:GetChildren() or {}) do
		if s:IsA("Sound") then
			table.insert(list, s)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
end

function AudioController.init()
	bank = Instance.new("Folder")
	bank.Name = "SpikeRushSoundBank"
	bank.Parent = SoundService
	task.spawn(preload)
	group = Instance.new("SoundGroup")
	group.Name = "SpikeRushSFX"
	group.Volume = 1
	group.Parent = SoundService
	-- mix bus: each hit's attack gets through before the compressor clamps (the snap), then the
	-- level comes up; weight in the lows, bite in the highs, and only a touch of hall
	local comp = Instance.new("CompressorSoundEffect")
	comp.Threshold = -22
	comp.Ratio = 3.5
	comp.Attack = 0.015
	comp.Release = 0.12
	comp.GainMakeup = 6
	comp.Priority = 3
	comp.Parent = group
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain = 5
	eq.MidGain = -1
	eq.HighGain = 3
	eq.Priority = 2
	eq.Parent = group
	local hall = Instance.new("ReverbSoundEffect")
	hall.DecayTime = 1.3
	hall.Density = 0.8
	hall.Diffusion = 0.8
	hall.DryLevel = 0
	hall.WetLevel = -24
	hall.Priority = 1
	hall.Parent = group
	holder = Instance.new("Part")
	holder.Name = "SpikeRushAudio"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(0, 0, 0)
	holder.Parent = workspace

	local crowd = loop("CrowdLoop", 0.35)
	loop("Music", 0.18)

	State.signals.Ball:Connect(function(snap, isEcho)
		if isEcho or snap.state ~= "Flight" then
			return
		end
		onHit(snap)
	end)
	State.signals.BallEvent:Connect(function(kind, ev)
		if kind == "Land" and ev.kind == "Floor" then
			local speed = ev.vel.Magnitude
			-- a hard spike lands with its own, heavier thump
			if hardSpike then
				AudioController.play("FloorHitHeavy", { pos = ev.pos, volume = math.clamp(speed / 50, 1.2, 1.8) })
			else
				AudioController.play("FloorHit", { pos = ev.pos, volume = math.clamp(speed / 50, 0.5, 1.6) })
			end
			hardSpike = false
		elseif kind == "Net" then
			AudioController.play("NetHit", { pos = ev.pos })
		end
	end)
	State.signals.Announce:Connect(function(a)
		if a.kind == "Serve" then
			AudioController.play("Whistle", { minGap = 0.5 })
		elseif a.kind == "Point" then
			AudioController.play("Whistle", { speed = 0.9, minGap = 0.3 })
			task.delay(0.12, function()
				AudioController.play("Point", { volume = a.winner == State.myTeam and 1 or 0.6 })
			end)
			if a.reason == "Spike" or a.reason == "Ace" or a.reason == "Stuff" or a.reason == "Break" then
				AudioController.play("CrowdCheer", { volume = 1 })
			elseif a.reason == "Out" or a.reason == "Net" then
				AudioController.play("CrowdGasp", { volume = 0.8 })
			end
			if crowd then
				crowd.Volume = 0.65
				task.delay(1.5, function()
					crowd.Volume = 0.35
				end)
			end
		elseif a.kind == "SetEnd" or a.kind == "MatchEnd" then
			AudioController.play("CrowdCheer", { volume = 1.2 })
			AudioController.play("Whistle", { speed = 0.8 })
		elseif a.kind == "Break" then
			AudioController.play("GuardBreak", { volume = 1.1, minGap = 0.3 })
		elseif a.kind == "Timeout" then
			AudioController.play("Whistle", { speed = 1.1 })
			AudioController.play("Timeout")
		elseif a.kind == "TimeoutCalled" then
			AudioController.play("UIClick")
		end
	end)
	State.signals.Action:Connect(function(entityId, kind, extra)
		if kind == "Slide" then
			AudioController.play("Slide", { volume = 0.7 })
		elseif kind == "Whiff" then
			AudioController.play("Whiff", { volume = 0.6 })
		elseif kind == "Jump" then
			local model = Util.modelOf(entityId)
			if model and (model:GetAttribute("Jump") or 0) >= Config.Player.BoomJumpMin then
				AudioController.play("Boom", { volume = extra == "Spike" and 0.8 or 0.45, minGap = 0.05 })
			end
		elseif kind == "Charge" then
			AudioController.play("AzureCharge", { volume = 0.5 })
		elseif kind == "Approach" then
			-- another player's double approach: the squeak where they start their run-up
			local model = Util.modelOf(entityId)
			local root = model and model:FindFirstChild("HumanoidRootPart")
			AudioController.play("Squeak", { pos = root and root.Position or nil })
		end
	end)
end

return AudioController
