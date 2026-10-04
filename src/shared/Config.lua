-- Spike Rush configuration (2.5D side-view edition).
-- Every gameplay number lives here so feel can be tuned in one place.
--
-- Units: M studs = 1 metre, so the HUD shows real km/h and hitting heights. The scale matches
-- The Spike: a real 9 m half court and a 2.43 m net with true-metre jumps, played by characters
-- who stand about 1.15 m tall (a Roblox avatar is about 5.3 studs), so they fly well above the
-- net. World distances below are written in metres times M; values tied to the avatar's own
-- body (hit zones around the root, lanes) stay in studs.
-- Axes: the court's long axis is Z (the net is the plane z = 0). Home plays on z < 0 (left of
-- the screen), Away on z > 0 (right). Y is height. X is depth toward/away from the camera:
-- the ball always travels in the x = 0 plane; players stand on shallow "lanes" near it.

local Config = {}

local M = 4.6 -- studs per metre

Config.GameName = "Spike Rush"

Config.Scale = {
	StudsPerMeter = M,
	-- Stretch of heights above the standing hand (HeightFloor = Player.RootGround +
	-- Zones.SpikeUp): every stud above it is drawn JumpScale times taller, so characters leap
	-- far over the net like in The Spike while hitting points, the 4.00 m Thunder line and the
	-- HUD stay in real metres (Characters.studsAt / metersAt).
	HeightFloor = 6.9,
	JumpScale = 1.4,
}

-- World height (studs) of a real height in metres, jump stretch included (Characters.studsAt).
local function lift(meters)
	local y = meters * M
	local floor = Config.Scale.HeightFloor
	if y > floor then
		y = floor + (y - floor) * Config.Scale.JumpScale
	end
	return y
end

Config.Court = {
	HalfWidth = 14, -- court depth toward the camera (visual only in 2.5D)
	SideDepth = 9 * M, -- end lines 9 m from the net
	AttackLine = 3 * M,
	FreeZoneEnd = 3.5 * M, -- serving area behind each end line
	FreeZoneSide = 8,
	NetTop = 2.43 * M,
	NetBottom = 1.43 * M,
	NetHalfWidth = 16,
	AntennaHeight = 0.8 * M,
	CeilingY = 19 * M,
	WallHalfX = 58, -- far wall (the near side is open for the camera)
	WallHalfZ = 20 * M,
	LineWidth = 0.1 * M,
	LobbySpawn = Vector3.new(0, 0.5, -10.5 * M),
}

-- Visual depth lanes by role, so teammates never stand inside each other.
-- Negative x is closer to the camera.
Config.Lanes = {
	WS = -1.2,
	MB = 0.2,
	SE = 1.4,
	Solo = 0,
}

Config.Ball = {
	Radius = 0.85,
	Gravity = 11.25 * M, -- ball gravity (a floaty 11.25 m/s2), separate from workspace gravity
	MaxFlightTime = 9,
	LandGrace = 0.2,
	VisualBlendTime = 0.08,
}

Config.Player = {
	Gravity = 45, -- workspace gravity (floaty jumps); the server also sets this at startup
	RootGround = 3.0, -- typical HumanoidRootPart height when standing (R15)
	HangVelocityWindow = 9, -- |vy| below this counts as "near the top of the jump"
	HangGravityCancel = 0.45, -- fraction of gravity cancelled near the apex (anime hang time)
	ApproachGather = 0.1, -- crouch before an approach jump
	ApproachDash = 2.2, -- run-up speed (x walk speed x Approach) during the gather
	ApproachBoost = 18, -- takeoff speed along the court for a run-up jump (x Approach)
	-- Double approach (a setting): the first press squeaks on the floor and readies the jump (you
	-- don't move; the stick walks as usual), the second takes off as one press would without the
	-- setting (the owner: "double approach shouldn't make you move, only you have to hit jump twice
	-- in order to actually jump, and it should play a floor squeak audio"). With no second press
	-- inside ApproachArmTime it's let go.
	ApproachArmTime = 1.0,
	AirControl = 0.55, -- air drift speed as a fraction of walk speed
	SlideSpeed = 50,
	SlideTime = 0.42,
	SlideRecover = 0.38,
	SlideCooldown = 0.75,
	BlockChargeTime = 0.45, -- hold the block key this long for a full-height block
	BlockMinHeight = 0.55, -- a tapped block jumps this fraction of full height
	BlockReach = 1.5 * M, -- max distance from the net that starts a block
	ActionCooldown = 0.18,
	WhiffCooldown = 0.2, -- after a missed swing, before you can swing again
	BoomJumpMin = 170, -- Jump stat needed for a boom jump (the shockwave off the floor)
	ReceiveStance = 0.8, -- how long a receive press stays armed
	ServeTapTime = 0.2, -- X released faster than this = overhand serve
	KnockbackSpeed = 26, -- a heavy receive shoves the receiver back along the court...
	KnockbackTime = 0.28, -- ...for this long (scaled by how heavy the ball was)
}

-- Hit zones, measured from the HumanoidRootPart centre.
Config.Zones = {
	SpikeUp = 3.9, -- hand above the root when the arm is raised
	SpikeForward = 0.4, -- hand sits this far toward the net
	SpikeCenterDz = 0.5, -- sweet spot: ball slightly ahead of the hand
	SpikeCenterDy = -0.1,
	SpikeRadiusZ = 2.9, -- sized so a set falling at 4.6 studs/m stays in reach 0.15 s or more
	SpikeRadiusY = 2.8,
	ReceiveForward = 0.6,
	ReceiveIdealY = -1.0,
	ReceiveHalfY = 2.6,
	ReceiveMinY = -3.3,
	ReceiveMaxY = 2.1,
	ReceiveReach = 3.4,
	SlideReach = 5.2,
	SlideMinY = -3.5,
	SlideMaxY = 1.2,
	SetIdealY = 3.4,
	SetHalfY = 2.4,
	SetMinY = 1.2,
	SetMaxY = 6.4,
	SetReach = 3.0,
	FloatUp = 4.0,
	FloatRadiusZ = 2.8,
	FloatRadiusY = 2.2,
	BlockReachUp = 4.3, -- hands above the root when blocking
	BlockOwnDepth = 1.6, -- block box: how far onto the blocker's side
	BlockOverDepth = 1.4, -- and how far over the net
	BlockNetDistance = 1.0 * M, -- blocker must stand this close to the net
}

Config.Hits = {
	PerfectAt = 0.86,
	GreatAt = 0.66,
	GoodAt = 0.42,

	-- Spikes. Speeds are km/h at a maxed Attack stat (175); lower Attack scales them by Power.
	SpikeKmhMin = 110, -- weakest clean contact
	SpikeKmhMax = 140, -- perfect contact at the top of the jump
	ThunderHeight = 4.0, -- metres
	ThunderKmhMin = 160,
	ThunderKmhMax = 200,
	ThunderHeightSpan = 0.35, -- metres above 4.00 that count toward a max thunder spike (a maxed S+ hits about 4.35)
	SpikeGravityScale = 1.0,
	SpikeDzDeep = -0.2, -- ball right at the hand = deepest spike (behind the head goes long)
	SpikeDzShort = 3.0, -- ball this far ahead of the hand = shortest, steepest spike
	SpikeDeepMargin = 0.4 * M, -- deepest in-court landing, inside the end line
	SpikeShortDepth = 1.4 * M, -- shortest landing, from the net
	SpikeError = 1.9 * M,
	SpikeAssistQuality = 0.5, -- contacts at least this clean get net-clearing help
	SpikeMinContactOverNet = 0.25 * M,
	ContactWeight = 0.62, -- spike quality = contact * this + jump height * (1 - this)
	HitStopPerfect = 0.1, -- the ball freezes on the hand this long: weight on a clean hit
	HitStopGreat = 0.06,
	HitStopThunder = 0.13,

	-- Feints (roll shots)
	FeintKmh = 32,
	FeintApexOverNet = 0.8 * M,
	FeintMaxDepth = 2.8 * M,
	FeintError = 0.8 * M,

	-- Receives: high and slow so the setter has time
	PassApexMin = 5.6 * M,
	PassApexMax = 7.6 * M,
	PassArriveY = 9, -- the setter's hands (studs, from the avatar)
	PassError = 1.6 * M,
	PassGravityScale = 1.0,
	ShankAt = 0.3,
	SlidePassApex = 5 * M,
	SlideQualityFloor = 0.62,
	PerfectStanceMin = 0.08, -- receive pressed this long before contact...
	PerfectStanceMax = 0.42, -- ...up to this long = perfect timing

	-- Sets: high, with a dotted trail
	SetApexOpen = 6.8 * M,
	SetApexQuick = lift(4.4),
	SetApexBack = 6.6 * M,
	SetArriveY = lift(3.75), -- comes down through a typical high-tier hitting point
	SetError = 0.95 * M,
	SetGravityScale = 1.0,
	-- setter aim (SetterAim): a human setter picks the height the set comes down through (any,
	-- from SetAimLowY to SetAimHighY: the hitting points of the shortest and tallest) and charges
	-- its distance from the net by holding Set (SetAimMin, then out to SetAimMax over
	-- SetChargeTime); letting go sets
	SetAimMin = 0.6 * M,
	SetAimMax = 4.2 * M,
	SetAimLowY = lift(2.6),
	SetAimHighY = lift(4.6),
	SetChargeTime = 1.0,
	OpenDepth = 2.3 * M, -- attack spots, distance from the net
	QuickDepth = 1.2 * M,
	BackDepth = 3.9 * M,
	SetterDepth = 1.06 * M,

	-- Serves
	TossLow = 11, -- studs above the release: the overhand toss comes back to the hand
	TossHighMin = 3.4 * M,
	TossHighMax = 5.6 * M,
	TossChargeTime = 0.8,
	TossForward = 1.2,
	TossForwardMax = 2.4 * M, -- a full forward toss comes back down this far in front of the hand
	OverhandApexOverNet = 1.4 * M, -- the standing serve floats over on a lob
	-- the easy underhand serve: straight from the hand (no toss), a slow high rainbow that
	-- always clears the net and lands well inside, between these fractions of the court's depth
	UnderhandApexOverNet = 2.6 * M,
	UnderhandDepthMin = 0.35,
	UnderhandDepthMax = 0.7,
	JumpServeKmhMin = 95,
	JumpServeKmhMax = 125,
	ThunderServeKmhMin = 140,
	ThunderServeKmhMax = 172,
	ServeError = 1.25 * M,
	ServeGravityScale = 2.2, -- jump serves carry topspin and dive
	ServeTopspin = 0.9,

	-- Free balls (third touch only)
	FreeBallApexOverNet = 2.2 * M,
	NetClearance = 0.12 * M,
	NetAssistPush = 0.38 * M,
	NetAssistSteps = 12,
	IncomingSpeedPenaltyStartKmh = 70,
	IncomingSpeedPenaltyRangeKmh = 130,
	IncomingSpeedPenaltyMax = 0.5, -- a hard spike pulls an imperfect receive down this much at most
	AssistQualityCap = 0.62,
}

-- Team stamina: a guard meter for receiving heavy balls.
Config.Stamina = {
	RedAt = 0.5, -- below this fraction the bar turns red and receives get unreliable
	DrainStartKmh = 60, -- balls slower than this never drain
	-- drain = DrainPer100Kmh * ((kmh - start) / 100) ^ DrainExponent, before Defense: a 110 km/h
	-- spike costs about 13, 140 about 27, 180 about 50 and 200 about 63
	DrainPer100Kmh = 38,
	DrainExponent = 1.5,
	-- a perfectly timed receive pays this fraction of the drain: 0.15 up to PerfectMulFromKmh,
	-- rising to PerfectDrainMulMax at PerfectMulToKmh (timing saves less on a monster spike)
	PerfectDrainMul = 0.15,
	PerfectDrainMulMax = 0.4,
	PerfectMulFromKmh = 100,
	PerfectMulToKmh = 180,
	KnockFromKmh = 90, -- heavier receives push the receiver back, up to full at +90 km/h
	BreakFailKmh = 90, -- with a broken guard, balls this fast cannot be received
	LowQualityFloor = 0.55, -- receive quality multiplier at the bottom of the red zone
	RecoverWinner = 0.1, -- fraction of max refilled after a rally
	RecoverLoser = 0.5, -- the team that lost the point gets half its bar back
	-- The drain above is what an S+ attacker's ball costs. Lower tiers hit the guard less and
	-- less: Low for a D-, rising along ((tier - 1) / 14) ^ Exponent to 1 for S+ (B about half,
	-- A about 0.7, S about 0.9).
	TierDrainLow = 0.25,
	TierDrainExponent = 1.6,
}

Config.Timeout = {
	PerSet = 2,
	Duration = 10, -- long enough to rearrange the rotation
	ResetBothTeams = true, -- a timeout refills stamina for everyone on court
}

-- Characters are named presets you roll for with V Points (src/shared/Roster, made by
-- tools/generate_roster.py): a role, a tier, a height, four stats and maybe an ability.
-- Tiers run weakest to strongest; bots of a tier use roster characters of that tier.
Config.Tiers = { "D-", "D", "D+", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+", "S-", "S", "S+" }
Config.DefaultTier = "S+"

-- Role templates: the stats of the very top (S+) character of each role. Lower tiers scale
-- toward Stats.Min (TierScale). Used for bots when the roster has nobody of a tier and role,
-- and by the simulation suite; the roster generator uses the same numbers.
Config.RoleTemplates = {
	WS = { Attack = 210, Jump = 190, Defense = 130, Speed = 145, Height = 187 },
	MB = { Attack = 172, Jump = 182, Defense = 150, Speed = 118, Height = 201 },
	SE = { Attack = 132, Jump = 142, Defense = 178, Speed = 180, Height = 177 },
	Solo = { Attack = 200, Jump = 184, Defense = 150, Speed = 160, Height = 185 },
}
Config.TierScale = { Low = 0.42, Exponent = 1.1 } -- D- stats are Low of the way up from Min

-- Upgrades: a character's roster stats are its ceilings. A newly recruited character starts
-- StartFraction of the way up from Stats.Min and is upgraded with Gold, one point at a time.
-- A point costs more the higher the stat already is, and more on a higher-tier character.
-- Taking points back refunds exactly what they cost.
Config.Upgrades = {
	StartFraction = 0.55,
	BaseCost = 8, -- gold for a point at Stats.Min
	CostPerPoint = 0.35, -- plus this per stat point above Min
	TierMul = { D = 0.6, C = 0.8, B = 1.0, A = 1.3, S = 1.7, ["S+"] = 2.2 },
	Steps = { 1, 5, 10 },
}

Config.Stats = {
	Order = { "Attack", "Defense", "Speed", "Jump" },
	Min = 50,
	Max = 250, -- hard limit on any preset
	Ref = 210, -- a stat at this value gives the top of every range below (the best WS Attack)
}

-- How each stat turns into gameplay. Values interpolate from Stats.Min to Stats.Ref.
Config.StatCurve = {
	Power = { Stat = "Attack", Range = { 0.45, 1.0 }, Extrapolate = true }, -- spike and serve speed multiplier (boosts past 210 keep adding)
	-- metres added to standing reach, on a curve (Exp) so the top jumpers pull away: the lowest
	-- starter hits about 2.6 m, a maxed 190-Jump S+ about 4.35 m, the best maxed middle 4.4 m
	VerticalM = { Stat = "Jump", Range = { 0.3, 2.24 }, Exp = 1.5 },
	Approach = { Stat = "Jump", Range = { 0.8, 1.25 } }, -- run-up speed and distance
	StaminaPool = { Stat = "Defense", Range = { 50, 100 } },
	DrainReduction = { Stat = "Defense", Range = { 0.0, 0.35 } },
	ReceiveBonus = { Stat = "Defense", Range = { -0.1, 0.08 } },
	BlockPower = { Stat = "Defense", Range = { 0.75, 1.15 } },
	WalkSpeed = { Stat = "Speed", Range = { 22, 32 } },
	SetAccuracy = { Stat = "Speed", Range = { 0.7, 1.0 } },
}

-- Every character has a height. Taller = higher standing reach and bigger hit zones, so two
-- characters with the same Jump stat hit from different heights.
Config.Height = {
	Min = 165,
	Max = 216, -- Mateus (was 210; ZoneScale's top moved with it, so every other height keeps its zone)
	Mean = 185,
	Spread = 9, -- roughly one standard deviation, cm
	ReachPerCm = 0.013, -- standing reach in metres per cm of height
	ZoneScale = { 0.94, 0.94 + 0.14 * 51 / 45 }, -- hit-zone size, Min -> Max (1.08 at 210 cm, as before the cap went up)
}

-- V Points (VP): the currency, like The Spike's. Earned by playing and bought in the shop,
-- spent on spins. Stats aren't bought any more: each character's tier total is yours to spread
-- over the four stats, up to that character's rolled stat caps.
Config.Progression = {
	StartingVP = 500, -- enough for one x10 spin (or ten x1) on a fresh profile
	WinVP = 30,
	LossVP = 15,
	PlayVP = 2, -- per kill, ace or block
	MvpVP = 15, -- extra for the match MVP (when a player)
	-- every set played past the first pays on top of the match reward
	ExtraSetWinVP = 20,
	ExtraSetLossVP = 10,
	ExtraSetWinGold = 200,
	ExtraSetLossGold = 100,
	-- win streak: from the second straight win, each win adds this much more (capped)
	StreakVP = 5,
	StreakGold = 50,
	StreakMaxSteps = 5,
	-- a custom lobby's shorter sets pay less: a match's rewards scale by its points over
	-- Match.PointsPerSet (never above 1), down to this; such a match doesn't count for your record
	ShortSetMin = 0.2,
	-- Gold: the second currency, spent on stat upgrades
	StartingGold = 3000,
	WinGold = 300,
	LossGold = 150,
	PlayGold = 20, -- per kill, ace or block
	DataStoreName = "SpikeRushProfiles_v1",
	AutosaveInterval = 90,
}

-- Rarity tiers shared by every spin.
Config.Rarity = {
	Order = { "Common", "Rare", "Epic", "Legendary", "Mythic" },
	Weights = { Common = 55, Rare = 28, Epic = 12.5, Legendary = 4, Mythic = 0.5 },
	Colors = {
		Common = Color3.fromRGB(170, 178, 200),
		Rare = Color3.fromRGB(80, 170, 255),
		Epic = Color3.fromRGB(190, 110, 255),
		Legendary = Color3.fromRGB(255, 200, 60),
		Mythic = Color3.fromRGB(255, 70, 110),
	},
	-- what a pull glows in the recruit sequence when it isn't its label colour: Mythic pulls
	-- glow red (the sparkles, the balls, the cinematic, the tray and the card)
	PullGlow = {
		Mythic = Color3.fromRGB(255, 34, 44),
	},
}

-- Spins: characters (with their ability), spike styles, colours, trails and score effects.
-- Everything you pull is yours for good; a duplicate, or a pull of a rarity you auto-sell,
-- turns into VP (SellValue).
Config.Spins = {
	Costs = { [1] = 50, [10] = 500 },
	Order = { "Char", "Style", "Color", "Trail", "Effect", "Pose" },
	Banners = {
		Char = { Name = "Characters", Blurb = "Named characters with their own role, stats, height and ability." },
		Style = { Name = "Spike style", Blurb = "Unlocks spike animations." },
		Color = { Name = "Spike color", Blurb = "Unlocks the colour of your spikes and their impact." },
		Trail = { Name = "Trail", Blurb = "Unlocks the trail your spikes leave." },
		Effect = { Name = "Score effect", Blurb = "Unlocks what happens where your attack lands for a point." },
		Pose = { Name = "Intro pose", Blurb = "Unlocks how you pose when the teams line up, and after a win." },
	},
	-- a character's rarity comes from its tier; sub-tiers share it (minus most common)
	TierRarity = { D = "Common", C = "Common", B = "Rare", A = "Epic", S = "Legendary", ["S+"] = "Mythic" },
	TierWeights = { ["-"] = 3, [""] = 2, ["+"] = 1 },
	SellValue = { Common = 5, Rare = 12, Epic = 30, Legendary = 80, Mythic = 250 },
	AutoSellable = { "Common", "Rare", "Epic" },
	AutoRollMax = 100, -- an auto-roll stops after this many spins
	AutoRollDelay = 0.4, -- seconds between auto-roll spins (so the reveal can be seen)
	AutoRollTarget = "Legendary", -- stops at this rarity or better
	-- Pity, on the Characters banner (the owner: "normal pity is 200 for a random s tier... lucky
	-- spins... 50... first pity hit is a random s+, next one is a chosen s+"). Recruits count up
	-- until one of ResetTiers comes (by luck or by pity) and start again; the recruit that
	-- reaches Every gives one of Tiers. Lucky spins count on their own: their first pity is a
	-- random S+, and when that wasn't the one you picked, the next is the one you picked. Normal
	-- recruits also count toward an S+ (Top, the owner: "add a normal spin S+ pity but it has to be
	-- 350 pulls"): an S+ is a 0.5% pull, so most players see one long before it (the average wait
	-- is 200), and about one in six reach it. When Top and Normal land on the same recruit, Top wins.
	-- 2x Luck (Config.Admin's event, or your own boost: Config.Boosts.LuckPacks): these rarities'
	-- weights double on the Characters banner (A- and up: Epic, Legendary, Mythic), and the weight
	-- they add is taken from From (D and C: Common), so Rare stays as it is. The event and your
	-- boost stack (the owner: "make it so if there is an admin 2x it stacks and make that clear"):
	-- both on is 4x (Spins.luckWeights). Lucky spins aren't changed.
	LuckEvent = { Double = { "Epic", "Legendary", "Mythic" }, From = "Common" },
	Pity = {
		Normal = { Every = 200, Tiers = { "S-", "S" }, ResetTiers = { "S-", "S", "S+" } },
		Top = { Every = 350, Tiers = { "S+" }, ResetTiers = { "S+" } },
		Lucky = { Every = 50, Tiers = { "S+" }, ResetTiers = { "S+" } },
	},
	-- Boost and Lower (the owner: "slightly boost and slightly lower the chances of getting a
	-- character of your choice during pulling"), on the Characters banner's probability table:
	-- a boosted character's weight within its rarity is x Boost, a lowered one's x Lower. The
	-- rarity's own chance never changes, only which of its characters you get (pity's random
	-- picks too). Up to MaxBoost boosted and MaxLower lowered at a time.
	Favor = { Boost = 1.5, Lower = 0.5, MaxBoost = 3, MaxLower = 3 },
}

-- Developers get everything: every character and unlockable, free spins. The place's owner
-- (or group owner) counts automatically, as does anyone in a Studio test session.
Config.Developers = {
	UserIds = {}, -- extra developer UserIds
	Studio = true,
	Owner = true,
}

-- Unlockables. The first item of each list is owned by everyone and equipped by default.
Config.Cosmetics = {
	Kinds = { "Style", "Color", "Trail", "Effect", "Pose" },
	Attribute = { Style = "SpikeStyle", Color = "SpikeColor", Trail = "SpikeTrail", Effect = "ScoreEffect", Pose = "IntroPose" },
	Style = {
		{ Key = "Classic", Name = "Classic", Rarity = "Common" },
		{ Key = "Bow", Name = "Full Bow", Rarity = "Rare" },
		{ Key = "Scissor", Name = "Scissor Kick", Rarity = "Rare" },
		{ Key = "Hammer", Name = "Double Hammer", Rarity = "Epic" },
		{ Key = "Whirl", Name = "Whirlwind", Rarity = "Legendary" },
		-- the owner: "a 360 jump or a bicycle kick" (AnimationController's Air_ and Swing_ clips)
		{ Key = "Tornado", Name = "Tornado 360", Rarity = "Legendary" },
		{ Key = "Bicycle", Name = "Bicycle Kick", Rarity = "Mythic" },
	},
	Color = {
		{ Key = "Default", Name = "Classic", Rarity = "Common" },
		{ Key = "Crimson", Name = "Crimson", Rarity = "Common", Color = Color3.fromRGB(255, 60, 80) },
		{ Key = "Tangerine", Name = "Tangerine", Rarity = "Common", Color = Color3.fromRGB(255, 150, 50) },
		{ Key = "Lime", Name = "Lime", Rarity = "Rare", Color = Color3.fromRGB(150, 255, 80) },
		{ Key = "Violet", Name = "Violet", Rarity = "Rare", Color = Color3.fromRGB(175, 95, 255) },
		{ Key = "Aqua", Name = "Aqua", Rarity = "Rare", Color = Color3.fromRGB(60, 230, 255) },
		{ Key = "Gold", Name = "Gold", Rarity = "Epic", Color = Color3.fromRGB(255, 210, 60) },
		{ Key = "Void", Name = "Void", Rarity = "Epic", Color = Color3.fromRGB(120, 50, 200) },
		{ Key = "Prism", Name = "Prism", Rarity = "Legendary", Color = Color3.fromRGB(255, 120, 220) },
	},
	Trail = {
		{ Key = "Ribbon", Name = "Ribbon", Rarity = "Common" },
		{ Key = "Comet", Name = "Comet", Rarity = "Common" },
		{ Key = "Sparkle", Name = "Sparkle", Rarity = "Rare" },
		{ Key = "Flame", Name = "Flame", Rarity = "Epic" },
		{ Key = "Lightning", Name = "Lightning", Rarity = "Epic" },
		{ Key = "Stardust", Name = "Stardust", Rarity = "Legendary" },
	},
	Effect = {
		{ Key = "Dust", Name = "Dust", Rarity = "Common" },
		{ Key = "Shockwave", Name = "Shockwave", Rarity = "Common" },
		{ Key = "Fire", Name = "Fire Explosion", Rarity = "Rare" },
		{ Key = "Meteor", Name = "Meteor Strike", Rarity = "Epic" },
		{ Key = "Thunderbolt", Name = "Thunderbolt", Rarity = "Legendary" },
	},
	-- how you pose in the matchup intro and, when your team wins, the showcase after the match
	-- (AnimationController's Intro_<Key> poses)
	Pose = {
		{ Key = "Ready", Name = "Ready", Rarity = "Common" },
		{ Key = "Arms", Name = "Arms Crossed", Rarity = "Common" },
		{ Key = "Point", Name = "Call Your Shot", Rarity = "Rare" },
		{ Key = "Fist", Name = "Victory Fist", Rarity = "Rare" },
		{ Key = "Flex", Name = "Double Flex", Rarity = "Epic" },
		{ Key = "Air", Name = "Sky Attack", Rarity = "Legendary" },
	},
}

-- Perks: one-time unlocks, bought with VP or as a game pass (Creator Hub > your experience >
-- Monetization > Passes; paste the pass id here, 0 while there isn't one). Whoever owns one
-- enters their own asset ids: sounds for their scoring and their touches (a Creator Store sound,
-- or their own upload shared with this experience), or an image that pops up and fades when they
-- score. The server checks each id's asset type (Types: 3 audio, 1 image, 13 decal) before it's
-- kept. A perk's Slots are the ids it takes (one per sound it replaces); each is saved under its
-- Key and written as the attribute of that name on the player and their character (a perk
-- without Slots has one, its own key).
Config.Perks = {
	Order = { "ScoreSound", "ScoreImage" },
	ScoreSound = {
		-- the owner: "buff custom sound effects to be able to change spike sound, jump, and all that"
		Name = "Custom sound effects",
		Blurb = "Your own sounds when you score, spike, jump, serve, receive, set, block or feint. Use sound ids from the Creator Store, or your own uploads shared with Spike Rush.",
		VP = 3000,
		PassId = 1998447396, -- "Custom Sound Effects", 199 Robux
		Attribute = "ScoreSound",
		Types = { 3 },
		Slots = {
			{ Key = "ScoreSound", Name = "Scoring", Verb = "you score" },
			{ Key = "SoundSpike", Name = "Spike", Verb = "you spike" },
			{ Key = "SoundJump", Name = "Jump", Verb = "you jump" },
			{ Key = "SoundServe", Name = "Serve", Verb = "you serve" },
			{ Key = "SoundBump", Name = "Receive", Verb = "you receive" },
			{ Key = "SoundSet", Name = "Set", Verb = "you set" },
			{ Key = "SoundBlock", Name = "Block", Verb = "you block" },
			{ Key = "SoundFeint", Name = "Feint", Verb = "you feint" },
		},
	},
	ScoreImage = {
		Name = "Custom score effect",
		Blurb = "Your own image pops up and fades when you score. Use an image or decal id.",
		VP = 3000,
		PassId = 2001902276, -- "Custom Score Effect", 199 Robux
		Attribute = "ScoreImage",
		Types = { 1, 13 },
	},
	SoundSeconds = 4, -- a custom score sound is cut off after this
	ActionSeconds = 2, -- a custom touch or jump sound after this
	ImageSeconds = 1.6, -- how long the image holds before it fades
	SetCooldown = 3, -- seconds between changes to one id (each one is looked up)
}

-- Player cards (the owner: "more diverse playercards, that are unlocked through achievements rather
-- than spinning. for example, a top 3 leaderboard playercard, or a playercard displaying your
-- winstreak, your wins, your spikes"): the card that slides in when you score, equipped in the
-- Locker. Each is unlocked for good when its Stat reaches Need ("rank": a place in the top Need of
-- any leaderboard), shows one of your numbers in big type (Show, with Label under it; "rank"
-- shows "#2" and the board), and has its own Look: Base (the plate), Sweep (the colour from the
-- left: "team" is the scorer's team, "rank" gold, silver or bronze), Accent (trim, chevrons, the
-- title), Edge (a border, or none), Pattern ("halftone", "stripes", "rays", "stars").
Config.Cards = {
	Default = "Rookie",
	RankColors = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(205, 214, 228), Color3.fromRGB(215, 140, 70) },
	List = {
		{ Key = "Rookie", Name = "Rookie", Goal = "Everyone's first card",
			Look = { Base = Color3.fromRGB(12, 14, 22), Sweep = "team", Accent = Color3.fromRGB(255, 210, 31), Pattern = "halftone" } },
		{ Key = "OnFire", Name = "On Fire", Stat = "bestStreak", Need = 5, Show = "winStreak", Label = "WIN STREAK", Goal = "Win 5 matches in a row",
			Look = { Base = Color3.fromRGB(40, 10, 6), Sweep = Color3.fromRGB(255, 90, 20), Accent = Color3.fromRGB(255, 190, 60), Edge = Color3.fromRGB(255, 120, 30), Pattern = "stripes" } },
		{ Key = "Unstoppable", Name = "Unstoppable", Stat = "bestStreak", Need = 10, Show = "bestStreak", Label = "BEST STREAK", Goal = "Win 10 matches in a row",
			Look = { Base = Color3.fromRGB(30, 0, 8), Sweep = Color3.fromRGB(220, 20, 60), Accent = Color3.fromRGB(255, 215, 90), Edge = Color3.fromRGB(255, 205, 80), Pattern = "rays" } },
		{ Key = "Winner", Name = "Winner", Stat = "wins", Need = 25, Show = "wins", Label = "WINS", Goal = "Win 25 matches",
			Look = { Base = Color3.fromRGB(10, 22, 48), Sweep = Color3.fromRGB(60, 140, 255), Accent = Color3.fromRGB(200, 225, 255), Edge = Color3.fromRGB(170, 190, 220), Pattern = "stripes" } },
		{ Key = "Champion", Name = "Champion", Stat = "wins", Need = 100, Show = "wins", Label = "WINS", Goal = "Win 100 matches",
			Look = { Base = Color3.fromRGB(34, 26, 6), Sweep = Color3.fromRGB(255, 196, 40), Accent = Color3.fromRGB(255, 240, 170), Edge = Color3.fromRGB(255, 214, 90), Pattern = "rays" } },
		{ Key = "SpikeMachine", Name = "Spike Machine", Stat = "kills", Need = 250, Show = "kills", Label = "SPIKE KILLS", Goal = "Score 250 spike kills",
			Look = { Base = Color3.fromRGB(36, 6, 28), Sweep = Color3.fromRGB(255, 60, 160), Accent = Color3.fromRGB(255, 150, 210), Edge = Color3.fromRGB(255, 90, 180), Pattern = "stripes" } },
		{ Key = "AceServer", Name = "Ace Server", Stat = "aces", Need = 50, Show = "aces", Label = "ACES", Goal = "Serve 50 aces",
			Look = { Base = Color3.fromRGB(4, 28, 34), Sweep = Color3.fromRGB(40, 220, 230), Accent = Color3.fromRGB(180, 250, 255), Edge = Color3.fromRGB(60, 230, 240), Pattern = "halftone" } },
		{ Key = "TheWall", Name = "The Wall", Stat = "blocks", Need = 100, Show = "blocks", Label = "BLOCKS", Goal = "Block 100 spikes",
			Look = { Base = Color3.fromRGB(22, 22, 34), Sweep = Color3.fromRGB(130, 110, 255), Accent = Color3.fromRGB(200, 190, 255), Edge = Color3.fromRGB(150, 140, 255), Pattern = "stripes" } },
		{ Key = "MVP", Name = "MVP", Stat = "mvps", Need = 25, Show = "mvps", Label = "MVP AWARDS", Goal = "Be the match MVP 25 times",
			Look = { Base = Color3.fromRGB(30, 24, 4), Sweep = Color3.fromRGB(255, 215, 60), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 225, 110), Pattern = "stars" } },
		{ Key = "Veteran", Name = "Veteran", Stat = "matches", Need = 200, Show = "matches", Label = "MATCHES", Goal = "Play 200 matches",
			Look = { Base = Color3.fromRGB(20, 26, 16), Sweep = Color3.fromRGB(120, 170, 80), Accent = Color3.fromRGB(220, 235, 170), Edge = Color3.fromRGB(160, 190, 110), Pattern = "halftone" } },
		{ Key = "Collector", Name = "Collector", Stat = "owned", Need = 20, Show = "owned", Label = "PLAYERS", Goal = "Recruit 20 players",
			Look = { Base = Color3.fromRGB(14, 20, 40), Sweep = Color3.fromRGB(80, 170, 255), Accent = Color3.fromRGB(255, 120, 220), Edge = Color3.fromRGB(190, 110, 255), Pattern = "stars" } },
		{ Key = "Top3", Name = "Top 3", Stat = "rank", Need = 3, Show = "rank", Goal = "Reach the top 3 of any leaderboard",
			Look = { Base = Color3.fromRGB(24, 24, 30), Sweep = "rank", Accent = Color3.fromRGB(255, 255, 255), Edge = "rank", Pattern = "rays" } },
		{ Key = "Number1", Name = "Number One", Stat = "rank", Need = 1, Show = "rank", Goal = "Reach #1 on any leaderboard",
			Look = { Base = Color3.fromRGB(28, 20, 2), Sweep = Color3.fromRGB(255, 200, 40), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 230, 120), Pattern = "stars" } },
		-- the owner: "another card displaying win/loss ratio... show wins, losses, and percent of
		-- wins": the share of matches won in big type, the wins and losses under it
		{ Key = "WinLoss", Name = "Win/Loss", Stat = "matches", Need = 20, Show = "winRate", Goal = "Play 20 matches",
			Look = { Base = Color3.fromRGB(6, 26, 22), Sweep = Color3.fromRGB(40, 220, 150), Accent = Color3.fromRGB(190, 255, 225), Edge = Color3.fromRGB(60, 230, 160), Pattern = "stripes" } },
		-- the owner: "a new card purple theme for Content creators... keep that text, but make it
		-- their own avatar spiking across the card": given from the admin panel (Grant), never
		-- earned; Big is drawn across the card and Avatar puts your own avatar, mid-spike, over it
		{ Key = "Creator", Name = "Content Creator", Stat = "grant", Grant = true, Goal = "Given to content creators",
			Look = { Base = Color3.fromRGB(26, 8, 48), Sweep = Color3.fromRGB(150, 50, 255), Accent = Color3.fromRGB(255, 110, 230), Edge = Color3.fromRGB(200, 120, 255), Pattern = "stripes", Big = "CONTENT\nCREATOR", Avatar = true } },
	},
}

-- VP and Gold packs, sold as Developer Products. Create each product (Creator Hub > your
-- experience > Monetization > Developer Products) and paste its id here. A pack with Id 0 shows
-- as "soon"; in Studio it grants its VP or Gold for free so the flow can be tested.
Config.Shop = {
	Packs = {
		{ Id = 3715199842, VP = 500, Name = "Pouch" }, -- 99 Robux
		{ Id = 3715199863, VP = 1200, Name = "Bag" }, -- 199
		{ Id = 3715199882, VP = 2800, Name = "Crate" }, -- 399
		{ Id = 3715199894, VP = 6500, Name = "Vault" }, -- 799
	},
	-- Gold for stat upgrades: ten times the VP pack at the same step (a win pays 300 Gold, and
	-- maxing one S+ stat from where a recruit starts costs about 8,000)
	GoldPacks = {
		{ Id = 3715199914, Gold = 5000, Name = "Stack" }, -- 99 Robux
		{ Id = 3715199928, Gold = 12000, Name = "Satchel" }, -- 199
		{ Id = 3715199946, Gold = 28000, Name = "Chest" }, -- 399
		{ Id = 3715199999, Gold = 65000, Name = "Treasury" }, -- 799
	},
	ReceiptHistory = 50, -- purchase ids remembered per profile (duplicate receipts are ignored)
}

-- Lucky spins (the owner: "lucky spins like volleyball legends with enhanced rates, which you can
-- buy with robux"): one lucky spin is one pull on any banner with these rarity weights in place
-- of Rarity.Weights (no Commons; Legendary and Mythic several times likelier). Sold in Packs as
-- Developer Products like the VP packs (a pack with Id 0 shows "Soon", and Studio grants it free),
-- and they also come from codes, daily rewards, gifts and the admin panel.
Config.Lucky = {
	Weights = { Common = 0, Rare = 48, Epic = 34, Legendary = 15, Mythic = 3 },
	-- the owner: "1 lucky spin 3 lucky spin 5 lucky 10 lucky spin" (Recruit's Lucky x1 and x10 buy
	-- the pack with that many when you have fewer)
	Packs = {
		{ Id = 3715530476, Lucky = 1, Name = "Lucky Spin" }, -- 49 Robux
		{ Id = 3715530517, Lucky = 3, Name = "3 Lucky Spins" }, -- 129
		{ Id = 3715530562, Lucky = 5, Name = "5 Lucky Spins" }, -- 199
		{ Id = 3715530621, Lucky = 10, Name = "10 Lucky Spins" }, -- 379
	},
}

-- Boosts (the owner: "developer products for 2x vpoints on timers"): a pack doubles the VP your
-- matches pay (the MVP bonus too) for its time, counted in real time from when you get it. Another
-- adds its time on top, up to MaxHold. It multiplies with the admin panel's 2x VP event. Sold as
-- Developer Products (a pack with Id 0 shows "Soon", and Studio grants it free), and can be gifted.
Config.Boosts = {
	Multiplier = 2,
	MaxHold = 24 * 3600, -- the most time a boost can hold (seconds)
	Packs = {
		{ Id = 3715530751, BoostVP = 15 * 60, Name = "2x VP, 15 minutes" }, -- 49 Robux
		{ Id = 3715530672, BoostVP = 30 * 60, Name = "2x VP, 30 minutes" }, -- 79
		{ Id = 3715530800, BoostVP = 60 * 60, Name = "2x VP, 1 hour" }, -- 129
		{ Id = 3715530842, BoostVP = 3 * 3600, Name = "2x VP, 3 hours" }, -- 299
	},
	-- 2x Luck for yourself (the owner asked for "the 2x luck developer products"): for its time your
	-- usual recruits on the Characters banner are twice as lucky (Config.Spins.LuckEvent: A- and
	-- up twice as likely), and with the admin panel's 2x Luck on too they stack: 4x. Id 0 until the
	-- product exists (free in Studio); suggested names and prices on each line.
	LuckPacks = {
		{ Id = 3716309041, BoostLuck = 15 * 60, Name = "2x Luck, 15 minutes" }, -- 79 Robux
		{ Id = 3716309076, BoostLuck = 30 * 60, Name = "2x Luck, 30 minutes" }, -- 129
		{ Id = 3716309109, BoostLuck = 60 * 60, Name = "2x Luck, 1 hour" }, -- 199
		{ Id = 3716309176, BoostLuck = 3 * 3600, Name = "2x Luck, 3 hours" }, -- 449
	},
}

-- Codes (the owner: "add a codes system... first code should be release, you decide the value
-- they get"): typed in Home's Codes window, any case, spaces ignored; each works once per player.
-- A code pays any of VP, Gold, Lucky (spins) and Chars (roster ids). Until: the unix time it
-- stops working (none: it never does). Keys are the code in lower case, letters and digits only.
Config.Codes = {
	release = { VP = 500, Gold = 5000, Lucky = 1 },
	-- the owner: "new code Update1", then "go with 6000 gold, 3 lucky spins, and 350 vpoints"
	update1 = { VP = 350, Gold = 6000, Lucky = 3 },
}

-- Daily rewards (the owner: "daily rewards for group members only"): members of the group that
-- owns the experience (GroupId 0), or of GroupId, claim one a day on Home. A claim within
-- StreakHours of the last one continues the streak along Rewards (starting over after the last
-- day); a later one starts again from day 1.
Config.Daily = {
	GroupId = 0,
	Cooldown = 20 * 3600, -- seconds from one claim until the next opens
	StreakHours = 48,
	Rewards = {
		{ VP = 50 },
		{ Gold = 1000 },
		{ VP = 75 },
		{ Gold = 2000 },
		{ VP = 100 },
		{ Gold = 3000 },
		{ VP = 150, Lucky = 1 },
	},
}

-- The admin panel (Home's Admin button, for developers: Config.Developers). Events double the VP
-- or Gold a match pays (Multiplier) for one of Durations (minutes), in every server; an
-- announcement shows to every player in every server; and Give sends VP, Gold, lucky spins and
-- characters to anyone by username (online in any server at once, otherwise on their next join).
Config.Admin = {
	Durations = { 5, 10, 15, 20, 30 },
	-- 2x VP and 2x Gold double what matches pay; 2x Luck (the owner: "add 2x luck, similar to the
	-- 2x gold and vp... this should lower the odds of getting the d's and the c's and double the
	-- odds of getting better characters. from A- to above") changes recruits on the Characters
	-- banner: Config.Spins.LuckEvent
	Events = { "VP", "Gold", "Luck" },
	EventNames = { VP = "V Points", Gold = "Gold", Luck = "Luck" },
	EventLines = { VP = "Every match pays double.", Gold = "Every match pays double.", Luck = "Recruits are twice as likely to be A- or better, and it stacks with your own 2x Luck for 4x." },
	Multiplier = 2,
	AnnounceMax = 200, -- characters
	AnnounceSeconds = 10, -- how long an announcement shows
	GiveMax = { VP = 1000000, Gold = 10000000, Lucky = 1000 },
	LiveStore = "SpikeRushLive_v1", -- the running events (DataStore), for servers that start later
	MailStore = "SpikeRushMail_v1", -- gifts waiting for their player (DataStore)
	PollInterval = 60, -- seconds between a server's reads of the events and of its players' mail
}

-- Gifting (the owner: "add a gifting system"): any pack (VP, Gold or lucky spins) can be bought
-- for someone else, by username; it reaches them at once wherever they are, or on their next join.
Config.Gifts = {
	PendingSeconds = 600, -- how long a gift's purchase prompt stays tied to its recipient
	MailSeen = 100, -- delivered gift ids remembered per profile (so a gift never arrives twice)
}

Config.TierColors = {
	D = Color3.fromRGB(150, 156, 176),
	C = Color3.fromRGB(120, 200, 140),
	B = Color3.fromRGB(90, 160, 255),
	A = Color3.fromRGB(190, 120, 255),
	S = Color3.fromRGB(255, 196, 60),
	-- a whole tier can have its own (the owner: "make the s - a lighter color then the s tiers...
	-- or maybe a different color altogether like green"): S- is a bright green, brighter than C's,
	-- on its badges and in the recruit when you pull one
	["S-"] = Color3.fromRGB(70, 240, 130),
}

-- Abilities come with a character (the Roster module). S+ wing spikers: Thunder Spiker, Azure Dragon or Feral Leap.
-- S characters have their role's ability. Everyone else has none.
Config.Abilities = {
	-- Double Swing (the owner: "yejun who has a double swing ability, with enhanced power on the
	-- second swing", then "remove the one swing limitation but keep the double swing buff on
	-- yejun"): anyone may swing again in a jump, and his second swing hits SecondBoost harder.
	-- Passives are shown as rows of their own on the Players screen.
	Thunder = {
		Name = "Thunder Spiker",
		Tier = "S+",
		Blurb = "Hit the ball above 4.00 m and it becomes a lightning spike.",
		Color = Color3.fromRGB(255, 225, 77),
		SecondBoost = 0.18,
		Passives = {
			{ Name = "Double Swing", Blurb = "Swing again in the same jump: the second swing hits 18% harder." },
		},
	},
	Azure = {
		Name = "Azure Dragon",
		Tier = "S+",
		Blurb = "Hold Spike in the air to gather energy under low gravity. A full bar hits hardest and pierces blocks. Hold too long and it flies out.",
		Kind = "Hold Spike in the air", -- how it's used (the menus; Active abilities say Q)
		Color = Color3.fromRGB(57, 213, 255),
		ChargeTime = 0.8, -- seconds of holding to fill the bar
		OverchargeGrace = 0.28, -- holding past full for this long overcharges
		GravityCancel = 0.85, -- a slow, floating fall while gathering energy (on the way down only)
		AirSpeedBonus = 1.25,
		GaugeRechargeTime = 3.0, -- gauge refills on the ground
		MaxBoost = 0.44, -- full energy multiplies spike speed by 1 + this
		PierceAt = 0.97,
	},
	-- The owner: "hold his jump to charge it and the longer he charges it the further it goes",
	-- "the highest attack character in the game". Hold Spike (Jump on touch) on the ground: a
	-- violet arc fills over ChargeTime while he runs faster; let go and he leaps, carried along the
	-- court by the charge. The gauge he took off with powers the spike, or the jump serve (serving,
	-- the press that tosses the ball starts the charge, and so does one after the toss).
	Feral = {
		Name = "Feral Leap",
		Tier = "S+",
		Blurb = "Hold Jump on the ground to charge, let go to leap: the longer the charge, the further you fly and the harder you hit. A full charge at the net breaks blocks with less Attack; your first of the match hits harder still.",
		Kind = "Hold Jump on the ground",
		AiNote = "Your AI charges it in the air on its own, at 85% Attack",
		Color = Color3.fromRGB(165, 80, 255),
		ChargeTime = 0.6, -- seconds of holding to fill the gauge (the owner: "buff charging times"; was 1)
		TapTime = 0.15, -- let go sooner and it's the usual run-up jump
		RunBoost = 0.45, -- run speed while charging: x (1 + this x the gauge)
		CarryMax = 3.4 * M, -- a full leap carries him this fast (studs/s) the way he leapt, all flight
		MaxBoost = 0.4, -- spike and jump serve speed x (1 + this x gauge ^ 1.2)
		FullAt = 0.97, -- the gauge counts as full from here
		FirstBoost = 0.15, -- his first full-gauge spike or jump serve of the match: x (1 + this) on top
		BreakKeep = 0.85, -- a spike that smashes through a block keeps this much of its speed
		ReachMul = 1.15, -- a wider spike reach
		TossReachMul = 1.6, -- his forward serve toss comes down this much further in front
		-- played by the AI (a bot, or a stand-in for an idle player): the gauge fills in the air on
		-- its own over AutoChargeTime, Attack is AutoAttackMul of the player's, and the gauge's and
		-- first strike's speed bonuses are AutoBoostMul of a player's
		AutoChargeTime = 1.0,
		AutoAttackMul = 0.85,
		AutoBoostMul = 0.75,
	},
	Adrenaline = {
		Name = "Adrenaline",
		Tier = "S",
		Role = "WS",
		Blurb = "When your team's stamina drops low, you jump higher and hit harder.",
		Color = Color3.fromRGB(255, 80, 70),
		StaminaBelow = 0.4, -- fraction of the team's bar
		AttackBonus = 18, -- stat points while active
		JumpBonus = 16,
	},
	IronWall = {
		Name = "Iron Wall",
		Tier = "S",
		Role = "MB",
		Active = true, -- press the Ability key (Q)
		-- the owner: "make it so he is literally a perfect block. when he pops the ability and a
		-- spike comes his way, it is perfect shut down onto their side no matter where it hits the
		-- block"
		Blurb = "Press Q: for a moment you're a perfect block. Any attack that comes near your hands, even off the fingertips, is shut straight down onto their side, whatever its power.",
		Color = Color3.fromRGB(150, 205, 255),
		Duration = 3.0,
		Cooldown = 20,
		-- while it's up the block box grows (studs): higher over the hands, further each side of the net
		ReachUp = 1.4,
		OwnDepth = 1.0,
		OverDepth = 1.0,
		-- the shut-down: straight down onto their court, this far from the net (metres), this fast
		StuffDepth = { 1.0, 2.2 },
		StuffKmh = 95,
	},
	ChainReaction = {
		Name = "Chain Reaction",
		Tier = "S",
		Role = "SE",
		Blurb = "Your sets are charged. The spike or feint off one explodes: more power, and it tears through the receivers' stamina.",
		Color = Color3.fromRGB(255, 64, 64),
		PowerMul = 1.15, -- spike speed off a charged set
		DrainMul = 2.4, -- receive drain of the exploding ball
		FlatDrain = 16, -- plus this, even off a feint
	},
	Vector = {
		Name = "Vector Set",
		Tier = "S",
		Role = "SE",
		Blurb = "Your sets pulse, and they go tight to the net and high. The spike off one gains power the steeper it comes down: a sharp, short spike gets up to +22%.",
		Color = Color3.fromRGB(176, 120, 255),
		MaxBoost = 0.22,
		-- the angle (degrees below level) of the line from the contact to where the spike lands:
		-- no boost at AngleMin (deep and flat), the full boost at AngleMax (short and steep)
		AngleMin = 22,
		AngleMax = 42,
		-- her open and back sets: this much of the usual distance from the net, and this much
		-- higher, so the attacker hits close to the net from the top of the jump (steep)
		SetDepthMul = 0.6,
		SetLift = 1.2 * M,
	},
	Turnabout = {
		Name = "Turnabout",
		Tier = "S",
		Role = "SE",
		Active = true,
		Blurb = "Press Q: your next set spins into a spike over the net, before the block can read it.",
		Color = Color3.fromRGB(110, 255, 200),
		Duration = 8, -- seconds the next set stays armed
		Cooldown = 18,
		PowerMul = 1.12,
	},
	RisingSun = {
		Name = "Rising Sun",
		Tier = "S",
		Role = "WS",
		Blurb = "Every 3 points the other team scores raises your Sunrise level. At level 4 (12 points) you outclass anyone.",
		Color = Color3.fromRGB(255, 150, 40),
		Every = 3,
		MaxLevel = 4,
		PerLevel = { Attack = 10, Jump = 9, Defense = 3, Speed = 6 },
	},
	RallyCry = {
		Name = "Rally Cry",
		Tier = "S",
		Role = "MB",
		Active = true,
		Blurb = "Press Q: your whole team gets +12% Attack, Jump, Defense and Speed for 10 s.",
		Color = Color3.fromRGB(255, 214, 90),
		Duration = 10,
		Cooldown = 30,
		Boost = 0.12,
	},
	Counter = {
		Name = "Counter Edge",
		Tier = "S",
		Role = "WS",
		Blurb = "Every ball the other team sends that you dig fills your Counter meter, and one hard spike fills it. Spikes you receive cost far less stamina: blades burst out and sink back in (a Chain Reaction still hits in full). The meter adds up to +40 Attack and +70 Defense, and your next spike releases all of it for up to +46% more power (about 205 km/h maxed).",
		Color = Color3.fromRGB(190, 220, 255),
		-- stat points at a full meter (0..100, in proportion below it)
		PerFull = { Attack = 40, Defense = 70 },
		-- her spike releases the meter: speed x (1 + this x meter / 100), then it's empty (the owner:
		-- "buff ines to be able to have around 200-210 at maxed out": maxed, a full one is about 205
		-- km/h, with Dante's full leap 204 and a full Azure 201; it was 0.12, 157 km/h)
		ReleaseBoost = 0.46,
		GainPerKmh = 0.8, -- meter per km/h of a hard spike she receives (a 125 km/h spike fills it)
		MinGain = 40,
		MaxGain = 100,
		LightGain = 30, -- any other ball of theirs she digs (serves, feints, free balls)
		-- a hard spike she digs costs this share of the guard it would (the owner: "ines should not
		-- be taking 0 damage on spikes", "she should have very high defense but no invincible"; it
		-- was 0); a Chain Reaction's explosion costs her all of it
		SpikeDrainMul = 0.4,
	},
	-- The owner: "a wingspiker with a blitz spin ability. it sharply angles down" (with a picture
	-- of a spike that leaves the hand through a ring of wind and dives), then "i want an
	-- exaggerated downwards spin, make also with the boom jump sound playing. i haven't seen it hit
	-- that sharp downwards angle". His spikes spin hard: they shoot over the net flat and fast,
	-- then just past it turn and plunge at DiveAngle into the front of the court (the ball's path
	-- has a second part from the turn: BallPhysics' launch.dive), with a ring and a boom there.
	Plunge = {
		Name = "Plunge Spin",
		Tier = "S",
		Role = "WS",
		Blurb = "Your spikes spin hard: they shoot over the net flat and fast, then turn and plunge, with a boom. Met out in front of you they fly on and dive near their back line; met further back they turn down at once, short and steep.",
		Color = Color3.fromRGB(255, 60, 90),
		MinContact = 0.15, -- nearly any spike plunges
		MinOverNet = 0.55 * M, -- met at least this far over the tape (lower: a usual spike)
		-- where it lands follows the contact like a usual spike's, the other way round (the owner:
		-- "further back makes it dip quicker while being more in front make it travel further and dip
		-- near the back court"): met at the hand or behind it lands LandShort in at DiveAngleShort;
		-- met SpikeDzShort ahead of the hand it lands BackMargin inside the end line at DiveAngleDeep
		-- (around the 57 the owner tried in Studio)
		DiveAngleShort = 64, -- degrees below level after the turn
		DiveAngleDeep = 52,
		LandShort = 1.6 * M,
		BackMargin = 0.8 * M,
		TurnDrop = 0.35 * M, -- the flat part drops this much from the contact to the turn
		TurnOverNet = 0.5 * M, -- and the turn is never lower than this over the tape
		TurnMin = 0.8 * M, -- the turn is at least this far past the net (the owner's Studio value)
		FlatGravity = 0.25, -- gravity x this on the flat part
		DiveSpeed = 1.0, -- the plunge keeps this much of the speed
		PowerBoost = 0.06, -- and it leaves the hand x (1 + this) faster
	},
}
Config.AbilityOrder = { "Thunder", "Azure", "Feral", "Adrenaline", "IronWall", "ChainReaction", "Vector", "Turnabout", "RisingSun", "RallyCry", "Counter", "Plunge" }

Config.Roles = {
	WS = { Name = "Wing spiker", Short = "WS", Blurb = "Attacks from the wing: the highest jump and the hardest spike on the team." },
	SE = { Name = "Setter", Short = "SE", Blurb = "Runs the offence: quick feet and a solid defence, and every second touch goes up for a hitter." },
	MB = { Name = "Middle blocker", Short = "MB", Blurb = "Guards the net: the tallest player, first to the block and fast on quick sets." },
	Solo = { Name = "Solo", Short = "SO", Blurb = "Covers the whole court alone in 1v1." },
}

Config.Match = {
	DefaultTeamSize = 3,
	PointsPerSet = 15,
	WinBy = 2,
	PointCap = 25,
	-- a match is one set; after each set the players can vote to keep playing (for the extra
	-- set rewards in Progression), up to MaxSets
	Sets = 1,
	MaxSets = 3,
	ContinueTime = 12, -- seconds to vote Keep playing / End match
	-- a custom lobby's rules (Create Lobby, cleaned by Lobbies.rules): the points a set is played
	-- to, win by 2 or 1, the sets (1: one set, then the vote to keep playing; 3 or 5: best of)
	-- and the timeouts per set. Quick Match, practice and the tutorial play the defaults
	-- (PointsPerSet, WinBy, one set, Timeout.PerSet).
	Custom = { PointsMin = 3, PointsMax = 50, Sets = { 1, 3, 5 }, TimeoutsMax = 5 },
	-- the matchup intro (LineupController): a wipe opens each team's turn (Open for the first,
	-- Wipe after), each team lined up in its poses for TeamTime, then both names meet for
	-- VersusTime and it fades to the court; the pre-match wait covers all of it
	Intro = { Open = 0.3, Wipe = 0.25, TeamTime = 2.4, VersusTime = 1.1, Fade = 0.35 },
	PreMatchTime = 7.6,
	PreServeTime = 1.2,
	ServeClock = 8,
	PointPauseTime = 2.6,
	SetEndTime = 3.5,
	MatchEndTime = 11, -- the showcase (your team, their stats); Continue closes it sooner
	DefaultBotTier = "A",
	-- points the scorer earned: after the rally the camera closes on them, their score effect goes
	-- off and their card slides in with this word (faults like outs and nets get none of it)
	Celebrate = { Spike = "SPIKE!", Feint = "FEINT!", Tooled = "TOOLED!", Break = "GUARD BREAK!", Ace = "ACE!", Stuff = "STUFF!", Block = "BLOCK!" },
}

-- Custom lobbies (the Lobbies module has the rules). A lobby plays on this server's court when
-- it's free; otherwise it gets its own reserved server (in Studio it waits for the court).
Config.Lobby = {
	Privacy = { "Public", "Friends", "Private" },
	PasswordMin = 3,
	PasswordMax = 12, -- letters and digits
	MaxLobbies = 16, -- per server
	QuickStartTime = 10, -- a Quick Match lobby starts on its own this long after it opens
	ArriveTimeout = 20, -- a teleported lobby waits this long for its players in the new server
	ReservedServers = true,
}

-- Courts: where a match is played. The play area is the same everywhere (Config.Court); a
-- court changes the floor paint, the surroundings, the stands, the screens and the light
-- (ArenaBuilder draws them, CrowdController seats their crowds). A lobby picks one, or
-- "Rotate" for the next court in Rotation; Quick Match always rotates.
--   Stands   overrides Court.Stands for this court (Rows, EndRows, RowRise); EndRows = 0 has
--            no end stands
--   Crowd    how full the stands are, times Graphics.CrowdDensity*
Config.Courts = {
	Default = "Arena",
	Rotate = "Rotate",
	Rotation = { "Arena", "Beach", "Colosseum", "Nationals", "Rooftop" },
	List = {
		Arena = {
			Name = "Rush Arena",
			Blurb = "The home hall: navy stands and warm lights.",
			Stands = {},
			Crowd = 1,
		},
		Beach = {
			Name = "Sunset Beach",
			Blurb = "Sand, sea and a few bleachers under the palms.",
			Stands = { Rows = 4, EndRows = 0 },
			Crowd = 0.9,
		},
		Colosseum = {
			Name = "Colosseum",
			Blurb = "Stone tiers, arches and braziers at dusk.",
			Stands = { Rows = 14, EndRows = 9, RowRise = 1.9 },
			Crowd = 0.8,
		},
		Nationals = {
			Name = "Nationals",
			Blurb = "The championship hall: packed stands, bright lights.",
			Stands = { Rows = 14, EndRows = 10 },
			Crowd = 0.85,
		},
		Rooftop = {
			Name = "Night Rooftop",
			Blurb = "A court on the roof, the city lit up behind it.",
			Stands = { Rows = 3, EndRows = 0 },
			Crowd = 0.9,
		},
	},
}

-- Leaderboards (the Leaderboards module ranks them): global OrderedDataStores, one per stat,
-- written from each player's career counters; a server-only board when those can't be reached.
Config.Leaderboards = {
	Boards = {
		{ Key = "wins", Name = "Wins", Unit = "wins" },
		{ Key = "bestStreak", Name = "Best win streak", Unit = "in a row" },
		{ Key = "kills", Name = "Spike kills", Unit = "kills" },
		{ Key = "aces", Name = "Aces", Unit = "aces" },
		{ Key = "blocks", Name = "Blocks", Unit = "blocks" },
		-- the owner: "most robux spent, most gifts spent leaderboard"
		{ Key = "robux", Name = "Robux spent", Unit = "Robux", Empty = "Nobody has bought anything yet." },
		{ Key = "gifts", Name = "Gifts given", Unit = "Robux gifted", Empty = "Nobody has sent a gift yet." },
		-- the owner: "a w/l ratio leaderboard with the appropriate title... show wins, losses, and
		-- percent of wins": ranked by the share of matches won (the same order as wins over
		-- losses), from MinMatches on. A board stores one whole number, so the value packs the
		-- percent (to 0.1), the wins and the losses (Leaderboards.winRate); Live: it can go down,
		-- so a player's fresh value replaces the stored one
		{ Key = "winRate", Name = "W/L ratio", Unit = "", WinRate = true, Live = true, MinMatches = 20, Empty = "Play 20 matches to get on this board." },
	},
	StorePrefix = "SpikeRushBoard_v1_",
	Top = 50,
	RefreshInterval = 120, -- seconds between reading the global boards
	FlushInterval = 60, -- seconds between writing changed players' scores
}

-- The tutorial (the Tutorial module has the steps): a 1v1 against a weak bot; finishing every
-- step pays this once.
-- The tutorial: the four practice drills in order (shared/Tutorial), paid once.
Config.Tutorial = {
	RewardVP = 50,
	RewardGold = 1000,
	RewardSpins = 5, -- free x1 recruits (used before V Points)
}

-- Practice drills (PracticeService). The court is a 2v2: you and a setter on your side, their
-- attacker on the other. Bots stand still; a drill moves only the one it needs.
Config.Practice = {
	Mode = 2,
	-- the practice partners (their sets and spikes are scripted, so the tier is mostly the look;
	-- a higher attacker jumps higher): D, like a new player's starters (the owner: "nerf the
	-- tutorial to not put a s tier spiker against a d tier blocker")
	BotTier = "D",
	FeedDelay = 1.1, -- seconds from setting up a rep to the ball coming
	RepTimeout = 7, -- a rep with no result by then is a miss
	ServeTimeout = 45, -- the serve drill waits this long for your serve (then just offers it again)
	PauseAfter = 1.3, -- seconds to watch the ball after a rep before the next one
	AttackWindup = 0.5, -- the attacker's jump before it swings
	AttackDepth = 1.2 * M, -- how far from the net the attacker hits
	AttackAboveNet = 1.2 * M, -- the lowest the attack leaves the hand, above the net top
	BlockKmh = { 90, 110 },
	BlockReachMargin = 0.8, -- the block drill's spike leaves the hand this far (studs) under the top of your full block
	BlockAboveNet = 0.35 * M, -- and never lower than this over the tape
	BlockTargetDepth = { 3 * M, 7 * M }, -- where a spike at your block lands if you miss it
	DigKmh = { 70, 90 },
	DigQuality = 0.35, -- a receive at least this clean counts as a dig
}

-- A player who stops giving input during live play is replaced by an AI playing their own
-- character (and can take the slot back at the next dead ball).
Config.Afk = {
	Timeout = 12, -- seconds without input while the ball is live (10 to 15)
	PingInterval = 1, -- the client reports input at most this often
	Phases = { PreServe = true, Serving = true, Rally = true },
}

Config.Net = {
	MaxRewind = 0.6, -- oldest hit timestamp the server accepts
	FutureTolerance = 0.12,
	BallTolerance = 1.4 * M, -- claimed ball position vs server path
	RootTolerance = 3.3 * M, -- claimed character position vs server character
	MaxRequestsPerSecond = 14,
}

Config.Teams = {
	Home = {
		Name = "Sunrise",
		Short = "SUN",
		Side = -1,
		Color = Color3.fromRGB(240, 138, 36),
		Dark = Color3.fromRGB(120, 56, 14),
		Icon = "TeamSunrise", -- Assets.Images
	},
	Away = {
		Name = "Tidal",
		Short = "TDL",
		Side = 1,
		Color = Color3.fromRGB(47, 140, 255),
		Dark = Color3.fromRGB(16, 52, 128),
		Icon = "TeamTidal",
	},
}
Config.TeamOrder = { "Home", "Away" }

Config.Bots = {
	Names = { "Kaito", "Ren", "Sora", "Yuki", "Aoi", "Haru", "Riku", "Mei", "Taiga", "Nao", "Kira", "Shun", "Emi", "Jin" },
	-- Skill by bot tier: every pair is { weakest (D-), strongest (S+) }, so a D- team is slow,
	-- sloppy and mistake-prone while an S+ team is clean (on top of their stats).
	-- (a bot plays at the lobby's bot level when its character is a lower tier: `skillP`)
	JumpTimingNoise = { 0.12, 0.012 }, -- seconds
	ContactNoise = { 1.1, 0.06 }, -- studs of positioning error under the ball
	ReactionDelay = { 0.28, 0.02 }, -- seconds before starting to move for a new ball
	PerfectReceiveChance = { 0.1, 0.8 },
	SloppyStance = { 0.8, 0.2 }, -- how far outside the perfect window a normal receive is pressed
	WhiffChance = { 0.25, 0.02 }, -- misses a heavy spike outright
	MissChance = { 0.07, 0.0 }, -- misses any ball
	SpikeMishitChance = { 0.3, 0.01 }, -- frames the swing (a weak, wild spike)
	ServeMissChance = { 0.12, 0.01 }, -- jump serves only (the underhand serve never misses)
	BlockChance = { 0.4, 0.95 },
	ReadOutChance = { 0.5, 0.95 },
	SlideChance = { 0.4, 0.9 },
	FeintChance = 0.12,
	-- bot serves: from this tier index (A-) a full-height jump-serve toss (thrown a little
	-- forward to run into); below it the easy underhand serve, which always goes in
	JumpServeTier = 10,
	JumpServeTossForward = 0.4,
	ServeDelay = { 1.0, 2.0 },
	-- Covering: when a ball is a human's to play, the nearest teammate bot shadows it and plays
	-- it unless the human tried something (stance, slide, jump, block, touch) this recently.
	CoverYield = 1.0,
	-- the setter AI's quick to the middle: only off a pass that comes down near the net, with the
	-- middle close enough to get there; better setters call it more ({worst, best} setter)
	QuickChance = { 0.05, 0.14 }, -- a setter's quick to the middle, off a good pass: most sets go to the wing
	QuickHumanMul = 0.5, -- a human middle gets the quick half as often (they have to read it)
	QuickPassDepth = 2.6 * M,
	QuickReachDepth = 4.2 * M,
	-- the middle backs up a set to the wing spiker: a late jump that meets the ball this long
	-- after the wing spiker's contact, so a miss still gets spiked
	BackupDelay = 0.14,
	-- setters jump-set Open and Back sets off a pass that comes down near the net: taken higher,
	-- the set goes higher ({worst, best} setter)
	JumpSetChance = { 0.45, 1.0 },
	JumpSetPassDepth = 3.4 * M,
	JumpSetSlack = 1.2, -- studs: a setter this far off its spot at takeoff sets from the ground
	TurnaboutChance = { 0.3, 0.65 }, -- a Turnabout setter arms it off a pass it can jump for
	RallyCryChance = 0.5, -- a Rally Cry bot pops it at a serve this often once it's ready
	CoverDepth = 1.5, -- the cover stands this much deeper than the human's spot
	CoverAfterMiss = 1.5, -- after the human whiffs, the cover plays the ball for this long
	SwapMargin = 1.2 * M, -- a human this much closer to a teammate's spot than their own takes it
	FriendsPerPlayer = 30, -- bots wear these players' friends' avatars and names
}

-- Settings saved in each player's profile (the Settings module cleans them; the client's
-- State.settings holds the defaults and the live values).
Config.Settings = {
	Switches = { "landingMarker", "dramatic", "assist", "followCam", "doubleApproach", "setterAim" },
	Numbers = { shake = { 0, 1 } },
	-- touch buttons can be moved (x, y: the centre as a fraction of the screen) and resized
	Touch = {
		Buttons = { "A", "B", "C", "Set", "Skill1", "Skill2", "Skill3" },
		MinSize = 0.6,
		MaxSize = 1.6,
		SizeStep = 0.1,
	},
	SaveDelay = 1, -- seconds after the last change before the client sends them
}

-- Keyboard controls (Settings > Controls; the owner: "in the settings, allows keybinds to be
-- changed"). Each action works on its Defaults until you pick your own key, which replaces them
-- (one key per action, and a key you pick is taken from any other action that had it). Allowed:
-- the keys a player may pick: Roblox's own (Escape, chat's Slash, the console's F9, the player
-- list's Tab) and 1 and 2 (your AI teammates' abilities) aren't. The mouse buttons and a
-- controller stay as they are.
Config.Controls = {
	Order = { "MoveLeft", "MoveRight", "Spike", "Receive", "SlideFeint", "Block", "Set", "Serve", "EasyServe", "Ability", "Timeout" },
	Names = {
		MoveLeft = "Move left",
		MoveRight = "Move right",
		Spike = "Jump and spike",
		Receive = "Receive",
		SlideFeint = "Slide and roll shot",
		Block = "Block",
		Set = "Set",
		Serve = "Serve",
		EasyServe = "Easy serve",
		Ability = "Ability",
		Timeout = "Timeout",
	},
	Defaults = {
		MoveLeft = { "A", "Left" },
		MoveRight = { "D", "Right" },
		Spike = { "Space", "Z", "J" },
		Receive = { "S", "Down", "K" },
		SlideFeint = { "C", "LeftShift", "RightShift", "L" },
		Block = { "W", "Up" },
		Set = { "E", "V" },
		Serve = { "X" },
		EasyServe = { "F" },
		Ability = { "Q" },
		Timeout = { "T" },
	},
	Allowed = {
		"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
		"Zero", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
		"KeypadZero", "KeypadOne", "KeypadTwo", "KeypadThree", "KeypadFour", "KeypadFive", "KeypadSix", "KeypadSeven", "KeypadEight", "KeypadNine",
		"Space", "LeftShift", "RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt",
		"Up", "Down", "Left", "Right", "Return", "Backspace", "CapsLock",
		"Comma", "Period", "Semicolon", "Quote", "LeftBracket", "RightBracket", "Minus", "Equals", "BackSlash",
	},
	-- what each does, for the How to play card (the owner: "introduce all the controls in the
	-- tutorial, and also let them know they can change them at any time in the settings")
	Help = {
		MoveLeft = "Walk along the court",
		MoveRight = "Walk along the court",
		Spike = "On the floor a run-up jump; in the air, the spike",
		Receive = "Press a little before the ball reaches you",
		SlideFeint = "A diving receive; in the air, a soft roll shot",
		Block = "Hold at the net, let go to jump",
		Set = "Toward the net: quick; away: back",
		Serve = "Tap: overhand; hold: a jump-serve toss",
		EasyServe = "A slow underhand serve that lands in",
		Ability = "Your character's active ability",
		Timeout = "In a match: refills stamina, change who serves",
	},
	-- a controller's buttons and the touch buttons, for the same card
	Pad = {
		{ "Move", "Left stick" }, { "Jump and spike", "A or R2" }, { "Receive", "B" }, { "Slide and roll shot", "RB" },
		{ "Block", "Y" }, { "Set", "LB" }, { "Serve", "X" }, { "Easy serve", "D-pad up" }, { "Ability", "L2" }, { "Timeout", "Select" },
	},
	Touch = {
		{ "Move", "The stick, bottom left" }, { "Jump and spike", "Jump: jump, then Jump again in the air to spike" },
		{ "Receive and block", "Bump: tap it a little early; at the net hold it to block" }, { "Slide and roll shot", "Slide" },
		{ "Set", "Set" }, { "Serve", "Basic Serve, or hold Spike Serve for a jump serve" }, { "Ability", "Its round button" },
		{ "Timeout", "The hourglass, top right" },
	},
	-- how a key reads on screen (the rest read as their name)
	Labels = {
		Space = "Space", LeftShift = "L Shift", RightShift = "R Shift", LeftControl = "L Ctrl", RightControl = "R Ctrl",
		LeftAlt = "L Alt", RightAlt = "R Alt", Return = "Enter", CapsLock = "Caps",
		Zero = "0", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
		KeypadZero = "Num 0", KeypadOne = "Num 1", KeypadTwo = "Num 2", KeypadThree = "Num 3", KeypadFour = "Num 4",
		KeypadFive = "Num 5", KeypadSix = "Num 6", KeypadSeven = "Num 7", KeypadEight = "Num 8", KeypadNine = "Num 9",
		Comma = ",", Period = ".", Semicolon = ";", Quote = "'", LeftBracket = "[", RightBracket = "]", Minus = "-",
		Equals = "=", BackSlash = "\\",
	},
}

Config.Graphics = {
	CrowdDensityDesktop = 0.7, -- the stands grew with the court
	CrowdDensityMobile = 0.35,
	CrowdUpdateHz = 20,
	CrowdCalmHz = 6, -- update rate while neither crowd is cheering
}

-- HUD palette: stadium "ink" navy; team colours, the stamina bar and the ability colours carry
-- the energy.
Config.UI = {
	Ink = Color3.fromRGB(20, 23, 43),
	InkSoft = Color3.fromRGB(36, 41, 74),
	Chalk = Color3.fromRGB(244, 247, 255),
	Spark = Color3.fromRGB(255, 225, 77),
	Whistle = Color3.fromRGB(255, 59, 92),
	Mint = Color3.fromRGB(80, 240, 190),
	Fog = Color3.fromRGB(160, 166, 200),
}

return Config
