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
	SpikeHeavy = "", -- borrows Spike, deeper and louder (the owner preferred it to the shale break, 9119044267)
	Thunder = "117922524763696", -- lightning-strike-cool (the owner's pick): a Thunder spike
	AzureCharge = "",
	AzureRelease = "",
	Boom = "129991093083800", -- "boomp jump": a hit into a low rumble on a boom jump (Jump 170+)
	Whoosh = "", -- borrows TornadoEnd's fast airy whoosh (AudioController BORROW)
	SpikeBody = "", -- the sub boom under every spike: borrows BlackHoleBoom's front
	Whiff = "115661994288749", -- "missed spike or swing": a swing or a dig that misses
	Block = "9119335569", -- Pro Sound Effects: goalie deflection, two-hand smack
	Stuff = "",
	FloorHit = "116030239767785", -- "spike land": the ball landing
	FloorHitHeavy = "94780477478667", -- "heavy land": the ball landing off a hard spike (Thunder, 130+ km/h)
	NetHit = "9113899121", -- Pro Sound Effects: rubbery smack
	Toss = "9113069659", -- Pro Sound Effects: air swoosh
	Serve = "9119334115", -- Pro Sound Effects: soccer chip shot, a hard thud
	Slide = "",
	Squeak = { "93928767284165", "121230189767569" }, -- "squeak 1" / "SQUEAK 2": a double approach's run-up starts
	GuardBreak = "9114593452", -- Pro Sound Effects "Glass Breaks 20": a guard shattering (replaced a sound ripped from another game, 2026-10-28)
	-- the score blast where a point lands (VFXController's celebrate; the owner's uploads)
	ScoreImpact = "91288569991875", -- Ground Slam 3 Explosion, Impact (the owner's pick)
	ScoreShockwave = "9125484367", -- Pro Sound Effects: deep reverberant boom, rumbling tail
	ScoreDebris = "120212342534790", -- Debris Explosion + Small Rocks Rumbling 2 (the owner's pick)
	ScoreSparkle = "138190748214493", -- gold magic (Creator Store)
	AceStinger = "1837834257", -- APM: reverse hard stop noise build
	ScoreThunder = "86789834935708", -- Lightning Bolt (the owner's pick): the Thunderbolt score effect
	-- each score effect's own sounds (Creator Store, picked 2026-10-04 on the owner's "pick them out
	-- through the creator store... pull from all creators")
	TornadoBurst = "133639929570919", -- "Wind Burst Heavy Shockwave": the funnel spins up
	TornadoHowl = "71284123166666", -- "Blizzard Outdoor SFX": a harsh whistling wind while it spins
	TornadoEnd = "9114373663", -- Pro Sound Effects: fast airy whoosh, as it blows apart
	BlackHoleHum = "84321138018138", -- "nother black hole": the hole open
	BlackHoleSuck = "9043343896", -- APM: reverse noise with a hard end, timed to the collapse
	BlackHoleBoom = "1837830182", -- APM: "BOOM-Sub Boom 16", the detonation
	TsunamiRush = "126761084927046", -- "wave_rush_sfx": the wall of water coming on
	TsunamiCrash = "9120610532", -- Pro Sound Effects: "Wave Crash 3", over the spot
	CraterSlam = "133444274732319", -- "downslam rocks slam hit sfx": the floor caving in
	CraterRubble = "9118586430", -- Pro Sound Effects: "Rock Debris 2", the rocks coming down
	CraterLava = "103148587203698", -- "Lava_Bubbles_Clip_2": the pit bubbling
	SpeedWhoosh = "9125920594", -- Pro Sound Effects: searing whoosh, the card skidding in
	SpeedSlam = "102243658312648", -- "combat_melee_REALLYheavyPUNCH": the number slamming down
	ScoreFire = "124035544468314", -- "Long Flame": the Fire Explosion score effect
	MeteorWhoosh = "9125920594", -- the searing whoosh again: the meteor ripping down
	-- the newer score effects' own (Creator Store, picked 2026-10-10; the owner: "fireworks should
	-- use a firework sfx")
	FireworkLaunch = "84790178390954", -- "firework_fly": a rocket whistling up
	FireworkBurst = "83996729056576", -- "Firework Explosion": a crackling burst
	ScoreFreeze = "9125611419", -- Pro Sound Effects: ice crackling as it freezes (Deep Freeze, Ice Age)
	ScoreTesla = "9114277402", -- Pro Sound Effects: electric zaps (Tesla Dome)
	ScorePow = "7468131335", -- "Cartoon Punch" (Ka-Pow)
	ScoreConfetti = "7368630054", -- "Party Popper" (Confetti Cannon)
	ScoreSlash = "5789211405", -- a fast blade whoosh with a ring (World Slash)
	ScoreHoly = "121538758381608", -- "Angelical choir" (Holy Strike)
	MeteorFall = "118217695193917", -- "fireball whoosh": each of Meteor Shower's meteors coming down
	MeteorImpact = "112627943804905", -- "Rock Explosion 1": each one landing
	ScoreRumble = "9113217388", -- Pro Sound Effects: avalanche crash, boulders rumbling (Volcano, Giant Stomp)
	StuffSlam = "9120256647", -- Pro Sound Effects: metal impact
	Whistle = "9118113825", -- Pro Sound Effects: referee whistle, single blast
	Timeout = "",
	UIClick = "101200067239382", -- "UIClick": any button
	UIHover = "", -- the pointer over a button
	UITick = "117000832074549", -- "UITick": a step (+ / -, the steppers)
	Point = "71587723216424", -- UI reward (CoreKit)
	CrowdLoop = "",
	CrowdCheer = "133064028732021", -- "end of rally cheer": a point won by a kill, ace, stuff or break
	CrowdServe = "140530824120891", -- "crowd hype": the crowd swells as the server tosses
	CrowdGasp = "83411385693493", -- crowd ooh (the owner's upload)
	Music = "",
	ImpactFrame = "",
	Blades = "", -- Counter Edge: blades out and back in (the volley along her released spike)
	CounterParry = "137580087669661", -- Parry3 (the owner's pick)
	CounterReturn = "137628815514180", -- sword-slash-and-swing (the owner's pick)
	-- Jaeil and Yeseul (Creator Store, Pro Sound Effects, picked 2026-10-09); both spikes still
	-- play the owner's Spike crack under these
	ZeroPoint = "9120729973", -- "Whoosh Impact 1": thick swish, hard reverberant impact (a Zero Point)
	TalonDrop = "9120730138", -- "Whoosh Impact 4": a shorter swish into a hard hit (Talon Drop)
	SkyPeak = "", -- Yeseul's jump climbs: borrows Lucia's parry, quicker (the owner: "nice and quick sword shink maaybe reuse ines"; the Magic Swirling Tone, 9116408879, was "bad")
	FeralFull = "", -- Feral Leap: the charge is full (let go now)
	FeralLeap = "", -- Feral Leap: the leap off the floor (louder the fuller the charge)
	Bloodlust = "9116292530", -- Valen's Bloodlust (Q): "Lion Roar Beast Snarl 5" (Pro Sound Effects)
	-- the court moments' (CourtMoments; Creator Store, 2026-10-29: the owner, "put some sfx on them.
	-- they feel a bit drab")
	WhaleCall = "3595240019", -- "Haunting Call of a Humpback Whale"
	BigSplash = "9120585252", -- Pro Sound Effects "Water Splash Big Water Splash Dive In 1"
	BigSplashDown = "9120586063", -- Pro Sound Effects "Water Splash Big Water Splash Dive In 6"
	HorseGallop = "118636555040923", -- "Horse Gallop Loopable"
	HorseNeigh = "128890675066690", -- "Undead Horse Neigh"
	SinisterLaugh = "9067394653", -- a Mythic skin's pull, as the scythe cuts the screen open: "deep demonic laugh 1" (zapsplat)
	-- the S+ skins' own (the owner, 2026-10-16: "lets make some custom sfx for the 2 s+ skins")
	ReaperSwing = "9120629501", -- the scythe through every spike: Pro Sound Effects "Web Whoosh Fast Heavy Swooshes 1"
	ReaperSlash = "9119742466", -- its slice on a hard one: Pro Sound Effects "Sword Draw Clang Unsheathing Two Sabers 1"
	ReaperSouls = "9114170094", -- souls wailing where a Souls ball lands: "Dream Weirdness Constant 6" (Pro Sound Effects, Ghosts)
	ReaperFrame = "108165623473748", -- the Reaper's impact frame: "black wipe jwoomph faster attack"
	FallenArms = "9114628818", -- the underworld's arms clawing up: "Goliath Vocal Deep Growling Voice 22" (Pro Sound Effects)
	FallenDirt = "9114658416", -- and the ground giving way under them: "Gravel Slide 1" (Pro Sound Effects)
	FallenThunder = "6993372814", -- his violet-black thunder (played low) in place of YeJun's: "Lightning Strike"
	RallyCry = "",
	-- the new characters' moves (2026-10-12, the owner: "add some cool sfx too"; Pro Sound Effects
	-- unless noted, starts and gains measured in a playtest)
	CoronaFlare = "9114442751", -- Laith's Corona: "Fire Whoosh 2", a punchy torch burst
	SunBlast = "9120704078", -- Laith's big Sundive hit: "Whoosh Combo Of Impacts Bys 5", huge
	TyrantSnap = "9114427575", -- Gunwoo's Emperor's Dictate: "Finger Snaps 1" (Pro Sound Effects)
	SquallOn = "133639929570919", -- Hayul's Squall: TornadoBurst's "Wind Burst Heavy Shockwave"
	SquallDash = "74818885604525", -- Tailwind's dash: "Woosh - Fast - Gust - Wind - Swing - Dash" (lorenzosaudiostash)
	SquallGlass = "9114592102", -- the dash's trail of shattered glass (the owner: "playing that shatter glass effect"): PSE "Glass Breaks 11"
	SquallSpring = "9120704057", -- Tailwind's spring: "Whoosh Combo Of Impacts Bys 4"
	SquallHover = "90848178756425", -- Eye of the Storm's hover: "strong gust of wind" (Sunny_CIover)
	SquallStep = "117000832074549", -- the target jumping a spot: UITick, pitched up each step
	SquallHit = "9113077334", -- a charged hover's hit: "Air Whoosh Heavy Bys And Impacts 1"
	FeatherSet = "135385970610304", -- Narae's floating set: "Twinkle08" (DonReqin)
	FeatherHit = "135385970610304", -- the spike off it: the same twinkle, higher and louder
	IronShieldBreak = "9114592102", -- a Bulwark shield shattering: "Glass Breaks 11", shards
	IronAwaken = "9120729732", -- Dongha awakens: "Whoosh Impact 1", a big stinger up and hit, pitched down
	IronRestore = "9119747260", -- his shields back: "Sword In 1", steel scraping home
	-- Forge's charge hammered out on an anvil (the owner: "a metal clanging sound effect. like hes
	-- forging it on a blacksmith iron", "aggressive heavy sharp"): strikes as it builds, each one
	-- picked from these, then a heavy clang with a sharp steel ring on top once it's full
	ForgeStrike = { "94770719520666", "9113447467", "9125362418" }, -- "AnvilHit" (Glitchy_Robot); PSE "Blacksmith Anvil Hammer Hits 16", "Anvil Hits Ringing Metal Clinks 31"
	ForgeFull = "9125669267", -- PSE "Metal Impact Metal Crowbar Railroad Hammer Hits 1": the heavy clang
	ForgeRing = "9116767882", -- PSE "Metal Pole Impact With Wrench 1": a sharp ringing hit over it
	ForgeHit = "9120730294", -- Forge's hit: "Whoosh Impact 3", a thick swish into a hard impact
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
	["129991093083800"] = { start = 0.38, gain = 2.2 }, -- "boomp jump": 0.39 s silence, peak 183
	["101487104093246"] = { start = 0.25 }, -- "spike sfx": 0.26 s silence, peak 410
	["116030239767785"] = { start = 0.34, gain = 1.3 }, -- "spike land": 0.35 s silence, peak 306
	["140530824120891"] = { start = 0.74, gain = 1.5 }, -- "crowd hype": 0.75 s silence, peak 172
	["111844345256332"] = { start = 0.25, gain = 1.4 }, -- "RecruitBuild": swells from 0.26 s, peak 280
	-- "heavy land" (94780477478667) starts at once and peaks at 492: as it is
	["71996778404557"] = { start = 0.32, gain = 6.5 }, -- "set": 0.33 s silence, peak 48
	["84316579472327"] = { start = 0.32, gain = 3.8 }, -- "feint sound": 0.33 s silence, peak 84
	["115661994288749"] = { start = 0.32, gain = 3.7 }, -- "missed spike or swing": 0.33 s silence, peak 76
	["93928767284165"] = { start = 0.02, gain = 3.4 }, -- "squeak 1": 0.03 s silence, peak 82
	["121230189767569"] = { start = 0.085, gain = 3.3 }, -- "SQUEAK 2": 0.09 s silence, peak 85
	["133064028732021"] = { start = 0.53, gain = 1.3 }, -- "end of rally cheer": 0.54 s silence, peak 273
	["111670558415526"] = { start = 0.15, gain = 0.8 }, -- "real bump": 0.16 s silence, peak 452
	-- the menu set starts at once; gains bring each to about 200
	["101200067239382"] = { gain = 3 }, -- "UIClick": peak 65
	["117000832074549"] = { gain = 1.1 }, -- "UITick": peak 180
	["94544858772525"] = { gain = 1.8 }, -- "UIOpen": peak 108
	["72734883374430"] = { gain = 1.8 }, -- "UIOpenLong": peak 108
	["75496570740002"] = { gain = 0.85 }, -- "UISelect": peak 244
	-- "UIConfirm" (140365614756879) peaks at 219: as it is
	-- Creator Store picks (2026-10-04): starts and gains from a playtest (peak to about 400 at 0.5)
	["91288569991875"] = { gain = 1.15 }, -- ScoreImpact: peak 349
	["120212342534790"] = { gain = 1.1 }, -- ScoreDebris: peak 351
	["137628815514180"] = { start = 0.1, gain = 1.1 }, -- CounterReturn: 0.11 s in, peak 360
	-- the new characters' (2026-10-12): start just before the sound, peak brought to about 400
	["9114442751"] = { start = 0.24 }, -- CoronaFlare: 0.26 s in, peak 409
	["9120704078"] = { start = 0.56, gain = 0.8 }, -- SunBlast: 0.58 s in, peak 490
	["74818885604525"] = { start = 0.03 }, -- SquallDash: peak 392
	["9120704057"] = { start = 0.13, gain = 0.8 }, -- SquallSpring: 0.15 s in, peak 497
	["90848178756425"] = { gain = 0.7 }, -- SquallHover: peak 559
	["9113077334"] = { start = 0.86, gain = 3.4 }, -- SquallHit: 0.88 s in, peak 115
	["135385970610304"] = { start = 0.05, gain = 2.1 }, -- FeatherSet / FeatherHit: peak 189
	["9114592102"] = { start = 0.73, gain = 2.3 }, -- IronShieldBreak: 0.75 s in, peak 174
	["9120729732"] = { start = 0.62 }, -- IronAwaken: 0.64 s in, peak 394
	["9119747260"] = { start = 0.19, gain = 0.7 }, -- IronRestore: 0.21 s in, peak 588
	["94770719520666"] = { gain = 0.65 }, -- ForgeStrike "AnvilHit": peak 618
	["9113447467"] = { gain = 1.75 }, -- ForgeStrike "Blacksmith Anvil Hammer Hits 16": peak 229
	["9125362418"] = { gain = 2.5 }, -- ForgeStrike "Anvil Hits Ringing Metal Clinks 31": peak 159
	["9125669267"] = { gain = 1.7 }, -- ForgeFull: peak 237
	["9116767882"] = { start = 0.1 }, -- ForgeRing: 0.11 s in, peak 410
	-- (2026-10-16) Valen's Bloodlust and the Mythic skin pull: start just before the sound, peak to about 400
	["9116292530"] = { start = 0.38, gain = 2.1 }, -- Bloodlust "Lion Roar Beast Snarl 5": 0.4 s in, peak 187
	["9067394653"] = { start = 0.02, gain = 2.8 }, -- SinisterLaugh "deep demonic laugh 1": peak 132
	-- the S+ skins' own (measured 2026-10-16 at Volume 0.5; a layer under another sound sits lower)
	["9120629501"] = { gain = 0.6 }, -- ReaperSwing: under every spike (by ear)
	["9114170094"] = { start = 0.8, gain = 6.5 }, -- ReaperSouls "Dream Weirdness Constant 6": in by 0.9 s, peak 38, a wail under the landing
	["108165623473748"] = { gain = 0.8 }, -- ReaperFrame "black wipe jwoomph faster attack": peak 479
	["9114628818"] = { start = 0.06, gain = 2.5 }, -- FallenArms "Goliath Vocal Deep Growling Voice 22": peak 160
	["9114658416"] = { start = 0.1, gain = 1.6 }, -- FallenDirt "Gravel Slide 1": peak 247
	["6993372814"] = { gain = 2.6 }, -- FallenThunder "Lightning Strike": peak 155 (played at 0.82), level with Thunder
	["9120730294"] = { start = 0.26, gain = 1.6 }, -- ForgeHit: 0.28 s in, peak 253
	["117922524763696"] = { gain = 0.5 }, -- Thunder: peak 798
	["83411385693493"] = { start = 0.08, gain = 0.8 }, -- CrowdGasp: peak 491
	["9118113825"] = { start = 0.1, gain = 1.8 }, -- Whistle: peak 217
	["9119335569"] = { gain = 6 }, -- Block: peak 47
	["9120256647"] = { start = 0.12, gain = 1.2 }, -- StuffSlam: peak 328
	["9119334115"] = { start = 0.15, gain = 0.6 }, -- Serve: peak 672
	["9113899121"] = { gain = 3 }, -- NetHit: peak 127
	["1837834257"] = { start = 1.6, gain = 1.8 }, -- AceStinger: a 2.4 s build, joined near its peak
	["138190748214493"] = { gain = 1.3 }, -- ScoreSparkle: peak 287
	["71587723216424"] = { gain = 2.4 }, -- Point: peak 157
	["9113069659"] = { start = 1.5, gain = 6 }, -- Toss: quiet, the swoosh at 1.6 s
	-- the score effects' (measured 2026-10-04: where each gets loud and its peak)
	["133639929570919"] = { gain = 1.6 }, -- TornadoBurst: peak 255
	["71284123166666"] = { gain = 2.6 }, -- TornadoHowl: steady, peak 134
	["9114373663"] = { start = 0.38, gain = 4 }, -- TornadoEnd: from 0.41 s, peak 82
	["84321138018138"] = { gain = 0.8 }, -- BlackHoleHum: peak 501
	["9043343896"] = { start = 1.0, gain = 1.5 }, -- BlackHoleSuck: swells from 1.32 s to the hard end at 2.07 s, peak 265
	["1837830182"] = { gain = 0.56 }, -- BlackHoleBoom: peak 711
	-- the newer score effects' (measured 2026-10-10)
	["84790178390954"] = { gain = 1.6 }, -- FireworkLaunch: peak 254
	["83996729056576"] = { gain = 1.9 }, -- FireworkBurst: peak 213
	["9125611419"] = { start = 0.2, gain = 0.7 }, -- ScoreFreeze: from 0.23 s, peak 574
	["9114277402"] = { start = 0.12, gain = 2.4 }, -- ScoreTesla: from 0.15 s, peak 164
	["7468131335"] = { gain = 0.75 }, -- ScorePow: peak 532
	["7368630054"] = { gain = 1.05 }, -- ScoreConfetti: peak 383
	["5789211405"] = { gain = 1.8 }, -- ScoreSlash: peak 219
	["121538758381608"] = { gain = 1.45 }, -- ScoreHoly: peak 273
	["9113217388"] = { start = 0.14, gain = 1.25 }, -- ScoreRumble: from 0.17 s, peak 323
	["118217695193917"] = { start = 0.1, gain = 1.15 }, -- MeteorFall: from 0.13 s, peak 346
	["112627943804905"] = { gain = 0.9 }, -- MeteorImpact: peak 446
	-- Jaeil and Yeseul (2026-10-09): started on the hit, not the swish before it
	["9120729973"] = { start = 0.24, gain = 1.9 }, -- ZeroPoint: swish from 0.11 s, the hit at 0.32 s, peak 212
	["9120730138"] = { start = 0.28, gain = 1.6 }, -- TalonDrop: swish from 0.23 s, the hit at 0.36 s, peak 249
	["126761084927046"] = { start = 5.2, gain = 0.78 }, -- TsunamiRush: builds to a peak of 511 at 7.3 s
	["9120610532"] = { start = 0.42, gain = 2.4 }, -- TsunamiCrash: from 0.45 s, peak 166
	["133444274732319"] = { gain = 0.85 }, -- CraterSlam: peak 470
	["9118586430"] = { start = 1.3, gain = 4 }, -- CraterRubble: from 1.39 s, peak 94
	["103148587203698"] = { gain = 2.5 }, -- CraterLava: peak 106
	["9125920594"] = { start = 0.33, gain = 2.5 }, -- SpeedWhoosh / MeteorWhoosh: from 0.36 s, peak 159
	["102243658312648"] = { gain = 0.5 }, -- SpeedSlam: peak 778
	["124035544468314"] = { gain = 0.83 }, -- ScoreFire: peak 482
	-- Parry3, Lightning Bolt and the shockwave boom start at once and peak near 400: as they are
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
	-- each ability's icon, on the HUD's round badges and the touch skill buttons (the owner's
	-- own art since 2026-10-28, white on clear, tinted in code)
	AbilityThunder = "92092680295887", -- our own: a lightning bolt (assets/ui, tools/generate_ui_icons.py)
	AbilityAzure = "137420198235206", -- decal 114282842219079, a dragon's head (Creator Store): back from our own redraw (the owner, 2026-10-29: "they all seem to have downgraded")
	AbilityFeral = "7486991621", -- decal 7486991661, claw marks (Creator Store): back from our own redraw (the owner, 2026-10-29: "they all seem to have downgraded")
	AbilityAdrenaline = "132570476091718", -- a flame (Creator Store): back from our own redraw (the owner, 2026-10-29: "they all seem to have downgraded")
	AbilityIronWall = "134408087231634", -- our own: a shield (assets/ui, tools/generate_ui_icons.py)
	AbilityChainReaction = "10601266774", -- decal 10601266786, a burst (Creator Store): back from our own redraw (the owner, 2026-10-29: "they all seem to have downgraded")
	AbilityVector = "83887958815685", -- our own: a crosshair (assets/ui, tools/generate_ui_icons.py)
	AbilityTurnabout = "104073632643804", -- our own: circling arrows (assets/ui, tools/generate_ui_icons.py)
	AbilityRisingSun = "70428699370149", -- our own: a sun on the horizon (assets/ui, tools/generate_ui_icons.py)
	AbilityRallyCry = "11874376205", -- decal 11874376247, a megaphone (Creator Store): back from our own redraw (the owner, 2026-10-29: "they all seem to have downgraded")
	AbilityCounter = "12902637748", -- decal 12902637801, crossed swords (Creator Store): back from our own redraw (the owner, 2026-10-29: "they all seem to have downgraded")
	AbilityPlunge = "91077038757273", -- our own: an arrow, flat then a sharp dip (decal 108217333632357; assets/ui, tools/generate_ui_icons.py)
	AbilityZeroPoint = "114247601826218", -- our own: a pinpoint (assets/ui, tools/generate_ui_icons.py)
	AbilitySkyward = "124450783350830", -- our own: climbing chevrons (assets/ui, tools/generate_ui_icons.py)
	AbilityTigerClaw = "10707998279", -- decal 10707998291, a white tiger's head (Creator Store)
	AbilityFever = "13954029980", -- decal 13954030020, a snowflake (Creator Store)
	AbilityCorona = "139313716822338", -- our own: a flaring sun (assets/ui, tools/generate_ui_icons.py)
	AbilitySquall = "113680494267156", -- our own white tornado (assets/icon/AbilitySquall.png)
	AbilityFeatherfall = "129198567408182", -- our own white feather (assets/icon/AbilityFeatherfall.png)
	AbilityIronclad = "77773837528485", -- our own clawed shield (assets/icon/AbilityIronclad.png)
	AbilityTyrant = "116739662945201", -- our own crown (assets/icon/AbilityTyrant.png, tools/generate_ability_icons.py)
	AbilitySunshine = "106265761499045", -- our own sun (assets/icon/AbilitySunshine.png)
	IroncladShield = "122579444814029", -- one of his shields, floating by him (assets/icon/IroncladShield.png)
	-- the Almighty card's ornaments (Look.Divine), our own art (tools/generate_card_ornaments.py)
	CardWingL = "92361767681368", -- gold wing out of the card's left (assets/card/almighty_wing_l.png)
	CardWingR = "81243094935205", -- and its right (assets/card/almighty_wing_r.png)
	CardCrest = "124663177354514", -- a crown with a red gem over the top (assets/card/almighty_crest.png)
	-- the ranked badges (Config.Ranked.Ranks): 3D crests rendered in Blender (tools/render_rank_badges_blender.py, then tools/finish_rank_badges.py into assets/ranks)
	RankBronze = "103886302950823",
	RankSilver = "123041125552754",
	RankGold = "121550200070565",
	RankPlatinum = "105934149359387",
	RankDiamond = "77218192158446",
	RankMighty = "129364484476461",
	RankAlmighty = "91356345193454",
	-- each division's own badge (I, II, III climbing like Roblox RIVALS: Ranked.badgeKey), the one above it the fallback
	RankBronze1 = "77313822748886",
	RankBronze2 = "140408409732283",
	RankBronze3 = "83048628750321",
	RankSilver1 = "103412559071019",
	RankSilver2 = "93318981968724",
	RankSilver3 = "91698768379751",
	RankGold1 = "115270374718856",
	RankGold2 = "135070547821063",
	RankGold3 = "118787813946914",
	RankPlatinum1 = "74854491295486",
	RankPlatinum2 = "92930852991592",
	RankPlatinum3 = "103350995958423",
	RankDiamond1 = "97409362125622",
	RankDiamond2 = "140693202947445",
	RankDiamond3 = "116040870088165",
	CardPumpkin = "78396191300977", -- our own: the Halloween card's jack-o'-lantern (assets/ui, tools/generate_ui_icons.py)
	CardBugNet = "134300946819235", -- the Bug Catcher card's net, mirrored from the owner's pick (assets/card/bug_net.png)
	-- menu icons: one filled white glyph style (Toolbox decals)
	IconHome = "134576977267684", -- our own: a house (assets/ui, tools/generate_ui_icons.py)
	IconSettings = "80759482861840", -- our own: a gear (assets/ui, tools/generate_ui_icons.py)
	IconRanks = "94951858286624", -- our own: a trophy (assets/ui, tools/generate_ui_icons.py)
	IconPlayers = "128622123859265", -- our own: two players (assets/ui, tools/generate_ui_icons.py)
	IconShop = "103147315517425", -- our own: a cart (assets/ui, tools/generate_ui_icons.py)
	IconLocker = "102715520382602", -- our own: a shirt (assets/ui, tools/generate_ui_icons.py)
	IconHelp = "73768815669869", -- our own: a question mark (assets/ui, tools/generate_ui_icons.py)
	IconBack = "133274486599289", -- our own: a back arrow (assets/ui, tools/generate_ui_icons.py)
	-- the four stats, favourites and locked characters (same filled style)
	IconAttack = "71392345507947", -- our own: a flame (assets/ui, tools/generate_ui_icons.py)
	IconDefense = "86230129329549", -- our own: a shield (assets/ui, tools/generate_ui_icons.py)
	IconSpeed = "135065710278270", -- our own: a fast-forward (assets/ui, tools/generate_ui_icons.py)
	IconJump = "82844023450162", -- our own: a leap (assets/ui, tools/generate_ui_icons.py)
	IconStar = "109144555171208", -- our own: a star (assets/ui, tools/generate_ui_icons.py)
	IconLock = "95175508309633", -- our own: a padlock (assets/ui, tools/generate_ui_icons.py)
	-- the team emblems (the matchup intro, the showcase): white line glyphs
	TeamSunrise = "122340681695290", -- our own: a sun (assets/ui, tools/generate_ui_icons.py)
	TeamTidal = "106561860778086", -- our own: three waves (assets/ui, tools/generate_ui_icons.py)
	-- the match's corner buttons
	IconTimeout = "75432321072874", -- our own: an hourglass (assets/ui, tools/generate_ui_icons.py)
	IconForfeit = "78596513021469", -- our own: a flag (assets/ui, tools/generate_ui_icons.py)
	-- Home's buttons down the right edge and the Shop's gifts; empty ones fall back to IconStar,
	-- IconShop and IconSettings (MenuController's `icon`)
	IconDaily = "91496067012593", -- our own: a calendar (assets/ui, tools/generate_ui_icons.py)
	IconCode = "85359819468377", -- our own: a ticket (assets/ui, tools/generate_ui_icons.py)
	IconAdmin = "85587493942600", -- our own: a wrench (assets/ui, tools/generate_ui_icons.py)
	IconGift = "117471119335629", -- our own: a gift box (assets/ui, tools/generate_ui_icons.py)
	-- a right triangle (right angle bottom-left): mirrored, the slanted ends of every plate
	Slant = "70555412223130", -- our own: the plate caps' right triangle (right angle bottom left) (assets/ui, tools/generate_ui_icons.py)
	Halftone = "130875147275516", -- our own: a halftone dot fade (assets/ui, tools/generate_ui_icons.py)
	-- the Match screen's card art: our own courts, rendered in Studio (assets/menu, uploaded to
	-- the owner's account)
	MatchArena = "127761392901061", -- Rush Arena
	MatchBeach = "86703389225100", -- Sunset Beach
	MatchRooftop = "116429204441166", -- Night Rooftop
	MatchNationals = "109844305626417", -- Nationals
	MatchColosseum = "108168199371323", -- Colosseum
	MatchPractice = "127970476168767", -- the club room's ball cart
	-- Decorate's tiles: each Home room rendered in Studio (assets/rooms), Room<Config.Rooms key>
	RoomClubhouse = "118243753679709", -- the Rush Arena (assets/rooms/Clubhouse.png, shot in Studio 2026-10-28)
	RoomNeon = "115001179141888", -- the Neon Court (assets/rooms/Neon.png)
	RoomHaunted = "130995790024847",
}

-- Effect textures (image ids) for the particle kits in Fx.lua: anime sprites and flipbooks, all
-- our own since 2026-10-28 (tools/generate_fx_own.py, the PNGs in assets/fx/own), in place of the
-- Creator Store VFX packs they started from. The flipbook layout is noted where there is one.
Assets.Fx = {
	HitStar = "84578776691802", -- a jagged comic impact star (our own, tools/generate_fx_own.py)
	HitBurst = "126411693371336", -- a many-pointed white burst (our own, tools/generate_fx_own.py)
	Glint = "70421026274490", -- a thin four-point glint (our own, tools/generate_fx_own.py)
	Sparkle = "132804290092923", -- a fat four-point star (our own, tools/generate_fx_own.py)
	Streak = "130178526915601", -- a tapered spark line (our own, tools/generate_fx_own.py)
	HitRing = "132772814642418", -- 4x4: an impact ring breaking into shards (our own, tools/generate_fx_own.py)
	Ring = "125834387367711", -- a thin ring, the sonic boom around a hard spike (our own, tools/generate_fx_own.py)
	SpikyRing = "84769116363514", -- a ragged shockwave ring (our own, tools/generate_fx_own.py)
	Radial = "136382539905094", -- a ring of speed lines (our own, tools/generate_fx_own.py)
	Slash = "77282827501139", -- a crescent swoosh (our own, tools/generate_fx_own.py)
	Glow = "110774508883625", -- a soft white glow (our own, tools/generate_fx_own.py)
	Dot = "125870173557967", -- a soft dot, embers (our own, tools/generate_fx_own.py)
	Specks = "74137990865897", -- scattered star specks (our own, tools/generate_fx_own.py)
	Smoke = "100136475024282", -- 4x4: cel-shaded smoke puffs (our own, tools/generate_fx_own.py)
	GroundWave = "118536844661487", -- a radial shock disc, laid on the floor (our own, tools/generate_fx_own.py)
	DustRing = "132621947143809", -- a ring of dust, laid on the floor (our own, tools/generate_fx_own.py)
	Crack = "100938226132811", -- 4x4: a crack spreading across the floor (our own, tools/generate_fx_own.py)
	Crater = "96837525357185", -- a cracked crater (our own, tools/generate_fx_own.py)
	Fire = "103685843431601", -- 4x4: anime flames (our own, tools/generate_fx_own.py)
	FireWhite = "116567298725900", -- 4x4: white flames, tinted in code (our own, tools/generate_fx_own.py)
	Fireball = "102171971966936", -- 4x4: a rolling fireball (our own, tools/generate_fx_own.py)
	Rock = "93208054984887", -- a rock, meteor debris (our own, tools/generate_fx_own.py)
	Bolt = "124691333332600", -- a lightning bolt (our own, tools/generate_fx_own.py)
	Bolt2 = "79025753395778", -- another bolt (our own, tools/generate_fx_own.py)
	Electric = "78550052410229", -- 4x4: crackling electricity (our own, tools/generate_fx_own.py)
	Arcs = "129463515329686", -- 2x2: lightning arcs (our own, tools/generate_fx_own.py)
	-- our own, for the premium score effects (tools/generate_fx_textures.py; the stat card drawn in
	-- Figma, "Spike Rush Score FX"); the PNGs are in assets/fx
	Swirl = "80708525637021", -- a spiral accretion disc (Black Hole)
	Wind = "78326427385002", -- a streaky band of wind, laid along beams (Tornado)
	Foam = "127115009029101", -- 4x4: spray bursting and thinning (Tsunami)
	Water = "128162093994051", -- tiling water with foam streaks (Tsunami)
	Shock = "88411235546191", -- a glowing ring with a hot rim, laid on the floor
	Flare = "121376733191681", -- a six-point lens flare
	StatCard = "105576360842696", -- the slanted stat plate behind Speed Burst's number
	-- our own toon flipbooks for the jump effects (tools/generate_fx_flipbooks.py, the PNGs in
	-- art/tex): 4x4, white cores with a grey band, tinted in code
	ToonFire = "136212220013921", -- a fire puff blooming, licking up and burning away
	ToonSmoke = "100966658733928", -- a cel-shaded smoke puff billowing and eroding
	ToonSpark = "121718144752045", -- a four-point star flaring and shrinking
	ToonElectric = "111494882405387", -- jagged bolts crackling out, new ones every frame
	ToonBurst = "138250827688419", -- a spiky star blast ringing out
	-- the Halloween event's (tools/generate_halloween_textures.py, the PNGs in assets/fx/halloween).
	-- The copies that came in HalloweenSprites.fbx, uploaded again as Jun Games Production on
	-- 2026-10-28 (tools/meshes_manifest.json): FBX-embedded textures load at once.
	SoulWisp = "99931500530389", -- a screaming soul with a wispy tail (the Reaper's Souls trail)
	Skull = "131429931090679", -- a skull with hollow eyes
	GhostSheet = "125781948678297", -- a sheet ghost, black eyes (Ghost Swarm)
	Bat = "133450613318178", -- a bat, wings spread
	BatFlap = "127489609038048", -- a bat's wingbeat, a 2x2 flipbook played on a loop (Bat Swarm)
	InkSplat = "110148383136194", -- a splash of ink with flung streaks
	CandyCorn = "106176482222720", -- a candy corn in its own colours (not tinted)
}

-- The ball skins' textures (tools/generate_ball_skins.py, the PNGs in assets/balls): equirectangular
-- maps for the BallSphere mesh (BallSkins).
Assets.BallSkins = {
	ProSwirl = "93502986653893",
	TriPanel = "88325341855487",
	Beach = "80024358295953",
	Eyeball = "92160046861735",
	Lava = "85665629262248",
	Galaxy = "78486839153788",
	Planet = "96923597581404",
	-- the owner's Halloween balls, baked in Blender onto their own UVs (assets/balls/Pumpkin.png and
	-- WitchHat.png, embedded in BallPumpkin.fbx and BallWitchHat.fbx): the FBX copies, uploaded again
	-- as Jun Games Production on 2026-10-28
	Pumpkin = "100236614421455",
	WitchHat = "135830846515653",
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
		ScoreFire = "", -- (was a Creator Store pack; Fx.lua's own ScoreFire kit plays)
		ScoreMeteor = "", -- (was a Creator Store pack; Fx.lua's own kit plays)
		ScoreThunderbolt = "", -- (was a Creator Store pack; Fx.lua's own kit plays)
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
	if type(key) ~= "string" then
		return nil
	end
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
