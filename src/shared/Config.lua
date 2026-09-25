-- Spike Rush configuration (2.5D side-view edition).
-- Every gameplay number lives here so feel can be tuned in one place.
--
-- Units: 3.2 studs = 1 metre, so the HUD can show real km/h and hitting heights.
-- Axes: the court's long axis is Z (the net is the plane z = 0). Home plays on z < 0 (left of
-- the screen), Away on z > 0 (right). Y is height. X is depth toward/away from the camera:
-- the ball always travels in the x = 0 plane; players stand on shallow "lanes" near it.

local Config = {}

Config.GameName = "Spike Rush"

Config.Scale = {
	StudsPerMeter = 3.2,
}

Config.Court = {
	HalfWidth = 14, -- court depth toward the camera (visual only in 2.5D)
	SideDepth = 30, -- end lines at z = +/-30 (about 9.4 m per side)
	AttackLine = 9.6, -- 3 m
	FreeZoneEnd = 12, -- serving area behind each end line
	FreeZoneSide = 8,
	NetTop = 7.8, -- 2.43 m
	NetBottom = 4.6,
	NetHalfWidth = 16,
	AntennaHeight = 2.9,
	CeilingY = 70,
	WallHalfX = 58, -- far wall (the near side is open for the camera)
	WallHalfZ = 78,
	LineWidth = 0.35,
	LobbySpawn = Vector3.new(0, 0.5, -34),
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
	Gravity = 40, -- ball gravity is separate from workspace gravity: floaty receives and sets
	MaxFlightTime = 9,
	LandGrace = 0.2,
	VisualBlendTime = 0.08,
}

Config.Player = {
	Gravity = 60, -- workspace gravity (floaty jumps); the server also sets this at startup
	RootGround = 3.0, -- typical HumanoidRootPart height when standing (R15)
	HangVelocityWindow = 10, -- |vy| below this counts as "near the top of the jump"
	HangGravityCancel = 0.45, -- fraction of gravity cancelled near the apex (anime hang time)
	ApproachGather = 0.1, -- crouch before an approach jump
	ApproachDash = 2.2, -- run-up speed (x walk speed x Approach) during the gather
	ApproachBoost = 13, -- takeoff speed along the court for a run-up jump (x Approach)
	AirControl = 0.55, -- air drift speed as a fraction of walk speed
	SlideSpeed = 36,
	SlideTime = 0.42,
	SlideRecover = 0.38,
	SlideCooldown = 0.75,
	BlockChargeTime = 0.45, -- hold the block key this long for a full-height block
	BlockMinHeight = 0.55, -- a tapped block jumps this fraction of full height
	BlockReach = 5, -- max distance from the net that starts a block
	ActionCooldown = 0.18,
	WhiffCooldown = 0.32,
	ReceiveStance = 0.8, -- how long a receive press stays armed
	ServeTapTime = 0.2, -- X released faster than this = overhand serve
}

-- Hit zones, measured from the HumanoidRootPart centre.
Config.Zones = {
	SpikeUp = 3.9, -- hand above the root when the arm is raised
	SpikeForward = 0.4, -- hand sits this far toward the net
	SpikeCenterDz = 0.5, -- sweet spot: ball slightly ahead of the hand
	SpikeCenterDy = -0.1,
	SpikeRadiusZ = 2.5,
	SpikeRadiusY = 2.2,
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
	BlockOwnDepth = 1.3, -- block box: how far onto the blocker's side
	BlockOverDepth = 1.1, -- and how far over the net
	BlockNetDistance = 3.2, -- blocker must stand this close to the net
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
	ThunderHeightSpan = 0.22, -- metres above 4.00 that count toward a max thunder spike
	SpikeGravityScale = 1.0,
	SpikeDzDeep = -0.2, -- ball right at the hand = deepest spike (behind the head goes long)
	SpikeDzShort = 3.0, -- ball this far ahead of the hand = shortest, steepest spike
	SpikeDeepMargin = 1.2, -- deepest in-court landing, inside the end line
	SpikeShortDepth = 4.5, -- shortest landing, from the net
	SpikeError = 6,
	SpikeAssistQuality = 0.5, -- contacts at least this clean get net-clearing help
	SpikeMinContactOverNet = 0.8,
	ContactWeight = 0.62, -- spike quality = contact * this + jump height * (1 - this)
	HitStopPerfect = 0.08,
	HitStopGreat = 0.04,
	HitStopThunder = 0.1,

	-- Feints (roll shots)
	FeintKmh = 32,
	FeintApexOverNet = 2.6,
	FeintMaxDepth = 9,
	FeintError = 2.5,

	-- Receives: high and slow so the setter has time
	PassApexMin = 18, -- about 5.6 m
	PassApexMax = 25, -- about 7.8 m
	PassArriveY = 9,
	PassError = 5,
	PassGravityScale = 1.0,
	ShankAt = 0.3,
	SlidePassApex = 16,
	SlideQualityFloor = 0.62,
	PerfectStanceMin = 0.08, -- receive pressed this long before contact...
	PerfectStanceMax = 0.42, -- ...up to this long = perfect timing

	-- Sets: high, with a dotted trail
	SetApexOpen = 22,
	SetApexQuick = 15,
	SetApexBack = 21,
	SetArriveY = 12.6,
	SetError = 3,
	SetGravityScale = 1.0,
	OpenDepth = 7.5, -- attack spots, distance from the net
	QuickDepth = 3.8,
	BackDepth = 12.5,
	SetterDepth = 3.4,

	-- Serves
	TossLow = 11,
	TossHighMin = 14,
	TossHighMax = 22,
	TossChargeTime = 0.8,
	TossForward = 1.2,
	OverhandApexOverNet = 4.5, -- the standing serve floats over on a lob
	JumpServeKmhMin = 95,
	JumpServeKmhMax = 125,
	ThunderServeKmhMin = 140,
	ThunderServeKmhMax = 172,
	ServeError = 4,
	ServeGravityScale = 2.2, -- jump serves carry topspin and dive
	ServeTopspin = 0.9,

	-- Free balls (third touch only)
	FreeBallApexOverNet = 7,
	NetClearance = 0.4,
	NetAssistPush = 1.2,
	NetAssistSteps = 12,
	IncomingSpeedPenaltyStartKmh = 70,
	IncomingSpeedPenaltyRangeKmh = 130,
	IncomingSpeedPenaltyMax = 0.3,
	AssistQualityCap = 0.62,
}

-- Team stamina: a guard meter for receiving heavy balls.
Config.Stamina = {
	RedAt = 0.5, -- below this fraction the bar turns red and receives get unreliable
	DrainStartKmh = 60, -- balls slower than this never drain
	DrainPer100Kmh = 30, -- drain per 100 km/h above the start, before Defense
	PerfectDrainMul = 0.15,
	BreakFailKmh = 90, -- with a broken guard, balls this fast cannot be received
	LowQualityFloor = 0.55, -- receive quality multiplier at the bottom of the red zone
	RecoverWinner = 0.2, -- fraction of max refilled after a rally
	RecoverLoser = 0.35,
}

Config.Timeout = {
	PerSet = 2,
	Duration = 5,
	ResetBothTeams = true, -- a timeout refills stamina for everyone on court
}

-- Character tiers, weakest to strongest. A tier doesn't fix your stats: it sets the ceiling.
-- Like The Spike, every character has four stats (Attack, Defense, Speed, Jump) that you upgrade
-- with points. The tier caps each stat and caps the total, so a build can't max everything.
Config.Tiers = { "D-", "D", "D+", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+", "S-", "S", "S+" }
Config.DefaultTier = "S+"
Config.TierCaps = {
	["D-"] = { Cap = 105, Total = 375 },
	["D"] = { Cap = 110, Total = 395 },
	["D+"] = { Cap = 115, Total = 410 },
	["C-"] = { Cap = 120, Total = 430 },
	["C"] = { Cap = 125, Total = 445 },
	["C+"] = { Cap = 130, Total = 465 },
	["B-"] = { Cap = 135, Total = 480 },
	["B"] = { Cap = 140, Total = 500 },
	["B+"] = { Cap = 145, Total = 515 },
	["A-"] = { Cap = 150, Total = 535 },
	["A"] = { Cap = 155, Total = 550 },
	["A+"] = { Cap = 160, Total = 570 },
	["S-"] = { Cap = 165, Total = 585 },
	["S"] = { Cap = 170, Total = 600 },
	["S+"] = { Cap = 175, Total = 620 },
}

Config.Stats = {
	Order = { "Attack", "Defense", "Speed", "Jump" },
	Min = 50,
	Ref = 175, -- a stat at this value gives the top of every range below (the S+ cap)
	StartFraction = 0.35, -- a new character starts this far from Min toward its tier's cap
}

-- How each stat turns into gameplay. Values interpolate from Stats.Min to Stats.Ref.
Config.StatCurve = {
	Power = { Stat = "Attack", Range = { 0.3, 1.0 } }, -- spike and serve speed multiplier
	VerticalM = { Stat = "Jump", Range = { 0.4, 1.75 } }, -- metres added to standing reach
	Approach = { Stat = "Jump", Range = { 0.8, 1.25 } }, -- run-up speed and distance
	StaminaPool = { Stat = "Defense", Range = { 60, 130 } },
	DrainReduction = { Stat = "Defense", Range = { 0.0, 0.35 } },
	ReceiveBonus = { Stat = "Defense", Range = { -0.1, 0.08 } },
	BlockPower = { Stat = "Defense", Range = { 0.75, 1.15 } },
	WalkSpeed = { Stat = "Speed", Range = { 16, 24 } },
	SetAccuracy = { Stat = "Speed", Range = { 0.7, 1.0 } },
}

-- Heights are rolled when a character is created. Taller = higher standing reach and bigger
-- hit zones, so two characters with the same Jump stat hit from different heights.
Config.Height = {
	Min = 165,
	Max = 205,
	Mean = 185,
	Spread = 9, -- roughly one standard deviation, cm
	ReachPerCm = 0.013, -- standing reach in metres per cm of height
	ZoneScale = { 0.94, 1.08 }, -- hit-zone size, shortest -> tallest
}

-- Upgrade points: earned by playing, spent on stats (1 point = +1 stat) or a height re-roll.
Config.Progression = {
	StartingPoints = 300, -- generous so a fresh S+ can be tested near its cap right away
	WinPoints = 30,
	LossPoints = 15,
	PlayPoints = 2, -- per kill, ace or block
	HeightRollCost = 40,
	DataStoreName = "SpikeRushProfiles_v1",
	AutosaveInterval = 90,
}

Config.TierColors = {
	D = Color3.fromRGB(150, 156, 176),
	C = Color3.fromRGB(120, 200, 140),
	B = Color3.fromRGB(90, 160, 255),
	A = Color3.fromRGB(190, 120, 255),
	S = Color3.fromRGB(255, 196, 60),
}

Config.Abilities = {
	Thunder = {
		Name = "Thunder Spiker",
		Blurb = "Hit the ball above 4.00 m and it becomes a lightning spike.",
		Color = Color3.fromRGB(255, 225, 77),
	},
	Azure = {
		Name = "Azure Dragon",
		Blurb = "Hold Spike in the air to gather energy under low gravity. A full bar hits hardest and pierces blocks. Hold too long and it flies out.",
		Color = Color3.fromRGB(57, 213, 255),
		ChargeTime = 0.8, -- seconds of holding to fill the bar
		OverchargeGrace = 0.28, -- holding past full for this long overcharges
		GravityCancel = 0.62, -- low gravity while gathering energy
		AirSpeedBonus = 1.25,
		GaugeRechargeTime = 3.0, -- gauge refills on the ground
		MaxBoost = 0.44, -- full energy multiplies spike speed by 1 + this
		PierceAt = 0.97,
	},
}
Config.AbilityOrder = { "Thunder", "Azure" }

Config.Roles = {
	WS = { Name = "Wing spiker" },
	SE = { Name = "Setter" },
	MB = { Name = "Middle blocker" },
	Solo = { Name = "Solo" },
}

Config.Match = {
	DefaultTeamSize = 3,
	FillWithBots = true,
	MinHumansToStart = 1,
	PointsPerSet = 15,
	DecidingSetPoints = 11,
	WinBy = 2,
	PointCap = 25,
	SetsToWin = 2,
	IntermissionTime = 15,
	IntermissionFastTime = 4,
	PreMatchTime = 3.2,
	PreServeTime = 1.2,
	ServeClock = 8,
	PointPauseTime = 2.6,
	SetEndTime = 3.5,
	MatchEndTime = 9,
	DefaultBotTier = "A",
}

Config.Net = {
	MaxRewind = 0.6, -- oldest hit timestamp the server accepts
	FutureTolerance = 0.12,
	BallTolerance = 4.5, -- claimed ball position vs server path
	RootTolerance = 11, -- claimed character position vs server character
	MaxRequestsPerSecond = 14,
}

Config.Teams = {
	Home = {
		Name = "Sunrise",
		Short = "SUN",
		Side = -1,
		Color = Color3.fromRGB(240, 138, 36),
		Dark = Color3.fromRGB(120, 56, 14),
	},
	Away = {
		Name = "Tidal",
		Short = "TDL",
		Side = 1,
		Color = Color3.fromRGB(47, 140, 255),
		Dark = Color3.fromRGB(16, 52, 128),
	},
}
Config.TeamOrder = { "Home", "Away" }

Config.Bots = {
	Names = { "Kaito", "Ren", "Sora", "Yuki", "Aoi", "Haru", "Riku", "Mei", "Taiga", "Nao", "Kira", "Shun", "Emi", "Jin" },
	JumpTimingNoise = { 0.09, 0.02 }, -- seconds, weakest tier -> strongest tier
	ContactNoise = { 0.55, 0.12 }, -- studs of positioning error, weakest -> strongest
	PerfectReceiveChance = { 0.15, 0.6 },
	WhiffChance = { 0.12, 0.03 },
	FeintChance = 0.12,
	JumpServeTier = 9, -- tier index from which bots jump serve
	BlockChance = 0.85,
	ReadOutChance = 0.85,
	SlideChance = 0.8,
	ServeDelay = { 1.0, 2.0 },
}

Config.Graphics = {
	CrowdDensityDesktop = 0.85,
	CrowdDensityMobile = 0.35,
	CrowdUpdateHz = 20,
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
