-- Asset slots.
-- Paste asset ids here (a number, "123456" or "rbxassetid://123456").
-- An empty visual slot falls back to procedural visuals, so the game is fully playable before an
-- asset is uploaded. TOOLBOX.md lists what to look for in the Toolbox (Creator Store).
--
-- Sounds are the owner's own uploads only: no Roblox library sounds, no Creator Store sounds, no
-- stand-ins. An empty sound slot plays nothing until the owner sends its sound.
--
-- Toolbox assets reach the game three ways, and the first one found wins:
--   1. Dragged straight from the Toolbox into ReplicatedStorage.ToolboxAssets.<Category>.<Slot>
--      in Studio (Rojo keeps anything you put in those folders).
--   2. Baked from the ids in Assets.Toolbox below by running this in the Studio command bar
--      (edit mode), then saving the place:
--        require(game.ServerScriptService.Server.Services.ToolboxService).install()
--   3. Loaded at runtime from the same ids by ToolboxService, with AssetService:LoadAssetAsync
--      (any free Creator Store model once Game Settings > Security > "Allow Loading Third Party
--      Assets" is on), else InsertService (only assets the place's owner owns or Roblox made).
-- Every inserted asset is sanitized: scripts are deleted and parts are made non-colliding, so
-- a free model can never run code in the game.
--
--   ToolboxAssets.Models.Volleyball   -> any ball model: the match ball and every menu ball
--   ToolboxAssets.Models.Locker       -> the club room's lockers (a bank of them, front facing -Z)
--   ToolboxAssets.Models.Bench        -> the club room's bench (long side along X)
--   ToolboxAssets.Models.BallCart     -> the ball cart in the club room and the recruit gym; any
--        balls in it are swapped for the volleyball. Menu props are scaled and placed by their
--        bounding box; a number attribute "Yaw" (degrees) turns one that faces another way.
--   ToolboxAssets.Models.PalmTree, BeachUmbrella, Column -> court scenery (Beach, Colosseum);
--        scaled to height and stood on the ground by ArenaBuilder, which draws its own from
--        parts when a slot is empty
--   ToolboxAssets.VFX.<Name>          -> a Part, Model or Attachment holding ParticleEmitters.
--        Impact names: SpikeImpact, PerfectImpact, ThunderImpact, AzureImpact, BlockImpact,
--        FloorImpact, ReceiveImpact, NetImpact, JumpBoom, GuardBreak. Each emitter fires
--        :Emit(n) where n = its "EmitCount" attribute (default 20).
--        AzureAura is held on the charging player instead (its emitters stay enabled).
--   ToolboxAssets.Sounds.<Key>        -> a Sound instance (one of the owner's uploads); overrides
--        the matching key below.
--   ToolboxAssets.UI.<Key>            -> a Decal (or ImageLabel) whose image overrides
--        Assets.Images[Key]: the menu icons, the slant cap and the halftone texture.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = {}

-- A slot holds one upload's id, or a list of them (each play picks one: variants).
Assets.Sounds = {
	Bump = "111670558415526", -- the owner's "real bump": a receive
	ReceivePerfect = "",
	Set = "71996778404557", -- "set"
	Feint = "84316579472327", -- "feint sound": a roll shot over the block
	-- the owner's uploads (from a free sound library): Spike, Boom, FloorHit, FloorHitHeavy, CrowdServe
	Spike = "101487104093246", -- "spike sfx": a spike's crack (SpikeHeavy borrows it, deeper and louder)
	SpikeHeavy = "",
	Thunder = "",
	AzureCharge = "",
	AzureRelease = "",
	Boom = "129991093083800", -- "boomp jump": a hit into a low rumble on a boom jump (Jump 170+)
	Whoosh = "",
	Whiff = "115661994288749", -- "missed spike or swing": a swing or a dig that misses
	Block = "",
	Stuff = "",
	FloorHit = "116030239767785", -- "spike land": the ball landing
	FloorHitHeavy = "94780477478667", -- "heavy land": the ball landing off a hard spike (Thunder, 130+ km/h)
	NetHit = "",
	Toss = "",
	Serve = "",
	Slide = "",
	Squeak = { "93928767284165", "121230189767569" }, -- "squeak 1" / "SQUEAK 2": a double approach's run-up starts
	GuardBreak = "",
	Whistle = "",
	Timeout = "",
	UIClick = "101200067239382", -- "UIClick": any button
	UIHover = "", -- the pointer over a button
	UITick = "117000832074549", -- "UITick": a step (+ / -, the steppers)
	Point = "",
	CrowdLoop = "",
	CrowdCheer = "133064028732021", -- "end of rally cheer": a point won by a kill, ace, stuff or break
	CrowdServe = "140530824120891", -- "crowd hype": the crowd swells as the server tosses
	CrowdGasp = "",
	Music = "",
	ImpactFrame = "",
	Blades = "", -- Counter Edge: blades out and back in
	RallyCry = "",
	UIOpen = "94544858772525", -- "UIOpen": a popup opening
	UIOpenLong = "72734883374430", -- "UIOpenLong": a menu screen changing, the matchup intro's wipes
	UISelect = "75496570740002", -- "UISelect": a tab or toggle
	UIConfirm = "140365614756879", -- "UIConfirm": buy, equip, claim
	-- the recruit sequence (each borrows the sound it used before while its slot is empty)
	RecruitOpen = "", -- the sparkle burst that opens a recruit (borrows Whoosh)
	RecruitOpenGold = "", -- that burst with a Legendary inside (borrows Thunder)
	RecruitOpenMythic = "", -- played over it with a Mythic inside (borrows Boom)
	RecruitFly = "111844345256332", -- "RecruitBuild" (the owner's upload): the balls flying under the gym ceiling
	RecruitPop = "", -- each card dropping into the tray (borrows UIClick)
	RecruitReveal = "", -- a card revealed (borrows Point)
	RecruitRevealGold = "", -- a Legendary or Mythic card revealed (borrows CrowdCheer)
	RecruitCharge = "", -- the S cinematic winding up (borrows Boom)
	RecruitSpike = "", -- the S cinematic's spike (borrows SpikeHeavy)
}

-- Per upload, keyed by asset id (these belong to the file, whichever slot plays it), both
-- measured in Studio from the Sound's TimePosition and PlaybackLoudness:
--   start  seconds of silence at the front of the file, skipped so the sound lands on its moment
--   gain   evens out how loud the files are: peak loudness brought to about 400 at Volume 0.5
Assets.SoundFiles = {
	["129991093083800"] = { start = 0.35, gain = 2.2 }, -- "boomp jump": 0.38 s silence, peak 183
	["101487104093246"] = { start = 0.24 }, -- "spike sfx": 0.26 s silence, peak 410
	["116030239767785"] = { start = 0.33, gain = 1.3 }, -- "spike land": 0.35 s silence, peak 306
	["140530824120891"] = { start = 0.72, gain = 1.5 }, -- "crowd hype": 0.75 s silence, peak 172
	["111844345256332"] = { start = 0.25, gain = 1.4 }, -- "RecruitBuild": swells from 0.26 s, peak 280
	-- "heavy land" (94780477478667) starts at once and peaks at 492: as it is
}

-- The per-upload entry for a sound value (an id in any form, or a Sound's SoundId), or nil.
function Assets.soundFile(value)
	if type(value) ~= "string" and type(value) ~= "number" then
		return nil
	end
	local digits = string.match(tostring(value), "(%d+)%s*$")
	return digits and Assets.SoundFiles[digits] or nil
end

-- Optional action animation ids. Roblox only plays animations owned by the place's owner (or by
-- Roblox), so a Toolbox animation has to be re-published from your account first (open its
-- KeyframeSequence in the Animation Editor and publish). When a slot is set, your own action
-- plays it (it replicates to everyone) and every client plays it on bots; the procedural pose
-- is skipped for that action.
Assets.Animations = {
	Bump = "",
	Set = "",
	Swing = "",
	Tip = "",
	Block = "",
	Slide = "",
	Charge = "",
	Toss = "",
	Stance = "",
	Knockback = "",
	Celebrate = "",
}

-- Locomotion for bots (they have no Animate script). These are Roblox's own default R15
-- animations, which every experience may play. Clear a slot to fall back to the procedural
-- run cycle.
Assets.BotAnimations = {
	Idle = "507766388",
	Run = "507767714",
	Jump = "507765000",
	Fall = "507767968",
}

-- Images: particle textures that ship with the client, and optional UI icons (Decal or Image
-- ids from the Toolbox). Empty icons fall back to text.
-- These are image ids, not the Toolbox decal ids: a decal's image id is its `Texture` after
-- `game:GetObjects("rbxassetid://<decal id>")`. The decal each one came from is noted.
Assets.Images = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	AbilityThunder = "",
	AbilityAzure = "",
	-- menu icons: one filled white glyph style (Toolbox decals)
	IconHome = "13300916613", -- decal 13300916690 (Fluent "home")
	IconSettings = "13300915301", -- decal 13300915335 (Fluent "settings")
	IconRanks = "71015270952901", -- decal 111656292605156
	IconPlayers = "100423427541804", -- decal 112043200329621
	IconShop = "13429538917", -- decal 13429538960
	IconLocker = "11955919597", -- decal 11955919656
	IconHelp = "546164656", -- decal 546164659
	IconBack = "116379345467715", -- decal 106533782606560
	-- the four stats, favourites and locked characters (same filled style)
	IconAttack = "132570476091718", -- decal 119691290898756 (flame)
	IconDefense = "7461510428", -- decal 7461510456 (shield)
	IconSpeed = "90651561026782", -- decal 135031436615807 (runner)
	IconJump = "13751812696", -- decal 13751812742 (leap)
	IconStar = "93992148478224", -- decal 109164246035556
	IconLock = "18854796316", -- decal 18854796355
	-- the team emblems (the matchup intro, the showcase): white line glyphs
	TeamSunrise = "101573322846819", -- decal 108787768126626 (a sun)
	TeamTidal = "18828405697", -- decal 18828405739 (three waves)
	-- the match's corner buttons
	IconTimeout = "132706456899814", -- decal 109363194447921 (sand timer)
	IconForfeit = "9440647549", -- decal 9440647555 (flag)
	-- a right triangle (right angle bottom-left): mirrored, the slanted ends of every plate
	Slant = "2288884279", -- decal 2288884281
	Halftone = "102527515036737", -- decal 124271316176270: a halftone dot fade
}

-- Effect textures (image ids) for the particle kits in Fx.lua: hand-drawn anime sprites and
-- flipbooks out of two free Creator Store VFX packs, "Yona VFX Pack" (18170940328) and
-- "BIG VFX PACK" (17290956157). The flipbook layout is noted where there is one.
Assets.Fx = {
	HitStar = "7919757890", -- a jagged comic impact star (Yona, Hit-03)
	HitBurst = "16937229477", -- a many-pointed white burst (BIG, Anime Crack-01)
	Glint = "13768810492", -- a thin four-point glint (Yona, Arrow-Shot)
	Sparkle = "1084970835", -- a fat four-point star (Yona, Golden-Sparks-01)
	Streak = "7845168136", -- a tapered spark line (Yona, Hit-03)
	HitRing = "13634052022", -- 4x4: an impact ring breaking into shards (Yona, Hit-02)
	Ring = "7919579655", -- a thin ring, the sonic boom around a hard spike (Yona, Hit-03)
	SpikyRing = "8904012224", -- a ragged shockwave ring (Yona, Red-Explosion)
	Radial = "2850138336", -- a ring of speed lines (Yona, Explosion-01)
	Slash = "7216847656", -- a crescent swoosh (BIG, Anime Slashes-01)
	Glow = "4509687978", -- a soft white glow (Yona, Blast-Explosion-02)
	Dot = "10558378459", -- a soft dot, embers (Yona, Block)
	Specks = "1851669703", -- scattered star specks (BIG, Anime Stars-01)
	Smoke = "16669188960", -- 4x4: cel-shaded smoke puffs (BIG, Anime Smoke-01)
	GroundWave = "16954602535", -- a radial shock disc, laid on the floor (BIG, Lighting-01)
	DustRing = "13108021212", -- a ring of dust, laid on the floor (Yona, Electricity Impact)
	Crack = "13784241004", -- 4x4: a crack spreading across the floor (Yona, Ground-Crack-02)
	Crater = "17067057050", -- a cracked crater (BIG, Big-Crack-01)
	Fire = "11395090403", -- 4x4: anime flames (Yona, Explosion-02)
	FireWhite = "11534281007", -- 4x4: white flames, tinted in code (Yona, Blast-Explosion-02)
	Fireball = "12782553831", -- 4x4: a rolling fireball (BIG, Anime Realistic-Explosion-01)
	Rock = "8132607319", -- a rock, meteor debris (Yona, Explosion-01)
	Bolt = "13592365549", -- a lightning bolt (Yona, Lightning)
	Bolt2 = "13612625856", -- another bolt (Yona, Lightning)
	Electric = "14862694841", -- 4x4: crackling electricity (Yona, Lightning)
	Arcs = "16951505034", -- 2x2: lightning arcs (BIG, Anime Lighting-03)
}

-- Font families (a FontFace family: rbxasset://fonts/families/<Name>.json, or a Creator Store
-- font's rbxassetid). Display is set heavy and italic; Body upright.
Assets.Fonts = {
	Display = "rbxasset://fonts/families/Oswald.json",
	Body = "rbxasset://fonts/families/RobotoCondensed.json",
}

-- Custom ball mesh (see tools/generate_volleyball_asset.py). The generated OBJ has radius 1,
-- so a SpecialMesh scale equal to the ball radius makes it match the gameplay ball exactly.
Assets.Mesh = {
	BallMesh = "",
	BallTexture = "",
	BallMeshUnitRadius = 1,
}

-- Creator Store (Toolbox) asset ids that ToolboxService inserts into ToolboxAssets.<Category>.
-- Models and VFX only: sounds, animations and images take their ids in the tables above.
Assets.Toolbox = {
	Models = {
		Volleyball = "123275048347543", -- "Volleyball Ball" (virtuallegendary): one MeshPart
		Locker = "15868311397", -- "Locker School" (ZlatanCooler12): six blue lockers
		Bench = "5110642461", -- "Modern Bench" (smartlegoman1): wood slats on metal legs
		BallCart = "10807459912", -- "Basketball rack" (twoborn): a two-tier ball rack
		-- court scenery (ArenaBuilder): an empty slot draws the prop from parts
		PalmTree = "12392856366", -- "Palm Tree" (Leandre_0311): mesh trunk and fronds on a planter
		BeachUmbrella = "",
		Column = "",
	},
	-- an effect can be one piece of a pack: "<asset id>/<path inside it>"
	VFX = {
		SpikeImpact = "",
		PerfectImpact = "",
		ThunderImpact = "",
		AzureImpact = "",
		BlockImpact = "",
		FloorImpact = "",
		ReceiveImpact = "",
		NetImpact = "",
		JumpBoom = "",
		GuardBreak = "",
		AzureAura = "",
		-- score effects (the Locker's Effect unlocks), played where the point lands
		ScoreFire = "17290956157/Folder/Big/Explosion-01", -- BIG VFX PACK: a cel-shaded fireball
		ScoreMeteor = "18170940328/Explosion-VFX/Explosion-01", -- Yona: rocks, smoke, speed lines
		ScoreThunderbolt = "17290956157/Folder/Big/Lighting-01", -- BIG VFX PACK: a shock disc and a rising bolt
		ScoreShockwave = "",
		-- ball trails (the Locker's Trail unlocks), held on the ball while an attack flies
		TrailComet = "",
		TrailSparkle = "",
		TrailFlame = "",
		TrailLightning = "",
		TrailStardust = "",
	},
}



-- Attributes ToolboxService stamps on an asset it loads by id (a hand-set attribute wins):
--   Yaw    degrees a prop turns, for models that face another way as published (the bench and
--          cart run along Z; the menu sets want their long side along X)
--   Scale  sizes and speeds of an effect's particles, for packs made at a sword-fight scale
--          (the match camera sits 64 studs back)
--   Lift   studs an effect plays above the spot, for effects centred on their middle
Assets.ToolboxAttributes = {
	Bench = { Yaw = 90 },
	BallCart = { Yaw = 90 },
	ScoreFire = { Scale = 0.55, Lift = 2.5 },
	ScoreMeteor = { Scale = 0.5, Lift = 1.5 },
	ScoreThunderbolt = { Scale = 0.7 },
}

function Assets.id(value)
	if value == nil or value == "" or value == 0 then
		return nil
	end
	if type(value) == "number" then
		return "rbxassetid://" .. tostring(value)
	end
	if string.find(value, "://", 1, true) then
		return value
	end
	return "rbxassetid://" .. value
end

-- The numeric id in any accepted form, or nil.
-- A Toolbox slot value: the asset id, and the path of the piece to take out of it ("" for the
-- whole asset). "18170940328/Explosion-VFX/Explosion-01" -> 18170940328, "Explosion-VFX/Explosion-01"
function Assets.ref(value)
	if type(value) == "number" then
		return value > 0 and value or nil, ""
	end
	if type(value) ~= "string" then
		return nil, ""
	end
	local digits, path = string.match(value, "^%s*(%d+)/(.+)$")
	if digits then
		return tonumber(digits), path
	end
	return Assets.number(value), ""
end

function Assets.number(value)
	if type(value) == "number" then
		return value > 0 and value or nil
	end
	if type(value) ~= "string" then
		return nil
	end
	local digits = string.match(value, "(%d+)%s*$")
	return digits and tonumber(digits) or nil
end

-- Look up ReplicatedStorage.ToolboxAssets.<dotted.path>
function Assets.toolbox(path)
	local node = ReplicatedStorage:FindFirstChild("ToolboxAssets")
	for piece in string.gmatch(path, "[^%.]+") do
		if not node then
			return nil
		end
		node = node:FindFirstChild(piece)
	end
	return node
end

-- The image for a UI slot: a Decal or ImageLabel in ToolboxAssets.UI.<key>, else the id in
-- Assets.Images, else nil.
function Assets.image(key)
	local inst = Assets.toolbox("UI." .. key)
	if inst then
		if inst:IsA("Decal") then
			return inst.Texture
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			return inst.Image
		end
	end
	return Assets.id(Assets.Images[key])
end

-- Make an inserted asset inert: no scripts can run, and no part collides, casts shadows or
-- takes touches or raycasts. Returns the same instance.
function Assets.sanitize(inst)
	local doomed = {}
	local all = inst:GetDescendants()
	table.insert(all, inst)
	for _, d in ipairs(all) do
		if d:IsA("LuaSourceContainer") then
			table.insert(doomed, d)
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	for _, d in ipairs(doomed) do
		if d ~= inst then
			d:Destroy()
		end
	end
	return inst
end

return Assets
