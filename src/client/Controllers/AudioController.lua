-- Audio. Every sound resolves in this order:
--   1. ReplicatedStorage.ToolboxAssets.Sounds.<Key> (a Sound you inserted from the Toolbox)
--   2. Assets.Sounds[Key] (an asset id you pasted)
--   3. Assets.Fallback[Key] (built-in client sounds, pitched and distorted as stand-ins)
-- Hit sounds scale with power: a perfect spike is lower, louder and crunchier.

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function resolve(key)
	local tb = Assets.toolbox("Sounds." .. key)
	if tb and tb:IsA("Sound") then
		return { template = tb }
	end
	local id = Assets.id(Assets.Sounds[key])
	if id then
		return { id = id, volume = 1, speed = 1 }
	end
	local fb = Assets.Fallback[key]
	if fb then
		return fb
	end
	return nil
end

local function spawnSound(info, opts)
	local sound
	if info.template then
		sound = Assets.sanitize(info.template:Clone())
	else
		sound = Instance.new("Sound")
		sound.SoundId = info.id
		sound.Volume = info.volume or 1
		sound.PlaybackSpeed = info.speed or 1
		if info.distort then
			local d = Instance.new("DistortionSoundEffect")
			d.Level = info.distort
			d.Parent = sound
		end
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
		sound.RollOffMinDistance = 20
		sound.RollOffMaxDistance = 260
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
	if info[1] then
		-- a layered stand-in: every layer at once (or after its delay)
		local first = nil
		for _, layer in ipairs(info) do
			if layer.delay then
				task.delay(layer.delay, spawnSound, layer, opts)
			else
				first = first or spawnSound(layer, opts)
			end
		end
		return first
	end
	return spawnSound(info, opts)
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
			AudioController.play("Spike", { pos = pos, speed = 1.25 - k * 0.35, volume = 0.6 + k * 0.7 })
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
		AudioController.play("CrowdServe", { volume = 0.9, minGap = 1 })
	elseif ht == "Overhand" or ht == "Underhand" then
		AudioController.play("Serve", { pos = pos, speed = ht == "Underhand" and 1.15 or 1 })
	elseif ht == "Feint" then
		AudioController.play("Set", { pos = pos, speed = 1.15, volume = 0.7 })
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

function AudioController.init()
	group = Instance.new("SoundGroup")
	group.Name = "SpikeRushSFX"
	group.Volume = 0.8
	group.Parent = SoundService
	-- mix bus: glue the hits together, lift the low end, and put the court in a hall
	local comp = Instance.new("CompressorSoundEffect")
	comp.Threshold = -20
	comp.Ratio = 3
	comp.Attack = 0.004
	comp.Release = 0.15
	comp.GainMakeup = 4
	comp.Priority = 3
	comp.Parent = group
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain = 3
	eq.MidGain = 0
	eq.HighGain = 1
	eq.Priority = 2
	eq.Parent = group
	local hall = Instance.new("ReverbSoundEffect")
	hall.DecayTime = 1.3
	hall.Density = 0.8
	hall.Diffusion = 0.8
	hall.DryLevel = 0
	hall.WetLevel = -17
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
			AudioController.play("FloorHit", { pos = ev.pos, volume = math.clamp(speed / 50, 0.4, 1.6), speed = speed > 45 and 0.8 or 1 })
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
			AudioController.play("Whoosh", { volume = 0.35 })
		elseif kind == "Jump" then
			local model = Util.modelOf(entityId)
			if model and (model:GetAttribute("Jump") or 0) >= Config.Player.BoomJumpMin then
				AudioController.play("Boom", { volume = extra == "Spike" and 0.8 or 0.45, minGap = 0.05 })
			end
		elseif kind == "Charge" then
			AudioController.play("AzureCharge", { volume = 0.5 })
		end
	end)
end

return AudioController
