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
	ThunderHeightSpan = 0.22, -- metres above 4.00 that count toward a max thunder spike
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
	OverhandApexOverNet = 1.4 * M, -- the standing serve floats over on a lob
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
	RecoverLoser = 0.2,
}

Config.Timeout = {
	PerSet = 2,
	Duration = 10, -- long enough to rearrange the rotation
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
	StartFraction = 0.5, -- a new character starts this far from Min toward its tier's cap
}

-- How each stat turns into gameplay. Values interpolate from Stats.Min to Stats.Ref.
Config.StatCurve = {
	Power = { Stat = "Attack", Range = { 0.45, 1.0 } }, -- spike and serve speed multiplier
	VerticalM = { Stat = "Jump", Range = { 0.25, 1.55 } }, -- metres added to standing reach (D- about 3.2 m, maxed S+ about 3.95 m)
	Approach = { Stat = "Jump", Range = { 0.8, 1.25 } }, -- run-up speed and distance
	StaminaPool = { Stat = "Defense", Range = { 50, 100 } },
	DrainReduction = { Stat = "Defense", Range = { 0.0, 0.35 } },
	ReceiveBonus = { Stat = "Defense", Range = { -0.1, 0.08 } },
	BlockPower = { Stat = "Defense", Range = { 0.75, 1.15 } },
	WalkSpeed = { Stat = "Speed", Range = { 22, 32 } },
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

-- V Points (VP): the currency, like The Spike's. Earned by playing and bought in the shop,
-- spent on spins. Stats aren't bought any more: each character's tier total is yours to spread
-- over the four stats, up to that character's rolled stat caps.
Config.Progression = {
	StartingVP = 500, -- enough for one x10 spin (or ten x1) on a fresh profile
	WinVP = 30,
	LossVP = 15,
	PlayVP = 2, -- per kill, ace or block
	DataStoreName = "SpikeRushProfiles_v1",
	AutosaveInterval = 90,
}

-- Rarity tiers shared by every spin.
Config.Rarity = {
	Order = { "Common", "Rare", "Epic", "Legendary" },
	Weights = { Common = 58, Rare = 29, Epic = 10, Legendary = 3 }, -- item banners
	Colors = {
		Common = Color3.fromRGB(170, 178, 200),
		Rare = Color3.fromRGB(80, 170, 255),
		Epic = Color3.fromRGB(190, 110, 255),
		Legendary = Color3.fromRGB(255, 200, 60),
	},
}

-- Spins. Stat caps and height are rolled per character (tier); you see the result and keep it
-- or throw it away (x10 shows ten and you keep the one you like). Styles, colours, trails and
-- score effects unlock for every character; a duplicate refunds a little VP.
Config.Spins = {
	Costs = { [1] = 50, [10] = 500 },
	Order = { "Caps", "Height", "Style", "Color", "Trail", "Effect" },
	Banners = {
		Caps = { Name = "Stat caps", Blurb = "Rolls the four stat caps of this character.", PerCharacter = true },
		Height = { Name = "Height", Blurb = "Rolls this character's height (standing reach).", PerCharacter = true },
		Style = { Name = "Spike style", Blurb = "Unlocks spike animations." },
		Color = { Name = "Spike color", Blurb = "Unlocks the colour of your spikes and their impact." },
		Trail = { Name = "Trail", Blurb = "Unlocks the trail your spikes leave." },
		Effect = { Name = "Score effect", Blurb = "Unlocks what happens where your attack lands for a point." },
	},
	CapFloor = 0.72, -- a rolled stat cap is at least this fraction of the tier's cap
	CapSkew = 1.8, -- higher = top caps rarer
	-- grade of a cap roll by its mean (0..1 of the way to the tier cap) and of a height roll (cm)
	CapGrades = { Legendary = 0.7, Epic = 0.52, Rare = 0.38 },
	HeightGrades = { Legendary = 200, Epic = 194, Rare = 188 },
	DuplicateRefund = 10,
	MaxPending = 10,
}

-- Unlockables. The first item of each list is owned by everyone and equipped by default.
Config.Cosmetics = {
	Kinds = { "Style", "Color", "Trail", "Effect" },
	Attribute = { Style = "SpikeStyle", Color = "SpikeColor", Trail = "SpikeTrail", Effect = "ScoreEffect" },
	Style = {
		{ Key = "Classic", Name = "Classic", Rarity = "Common" },
		{ Key = "Bow", Name = "Full Bow", Rarity = "Rare" },
		{ Key = "Scissor", Name = "Scissor Kick", Rarity = "Rare" },
		{ Key = "Hammer", Name = "Double Hammer", Rarity = "Epic" },
		{ Key = "Whirl", Name = "Whirlwind", Rarity = "Legendary" },
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
}

-- VP packs, sold as Developer Products. Create each product (Creator Hub > your experience >
-- Monetization > Developer Products) and paste its id here. A pack with Id 0 shows as "soon";
-- in Studio it grants its VP for free so the flow can be tested.
Config.Shop = {
	Packs = {
		{ Id = 0, VP = 500, Name = "Pouch" },
		{ Id = 0, VP = 1200, Name = "Bag" },
		{ Id = 0, VP = 2800, Name = "Crate" },
		{ Id = 0, VP = 6500, Name = "Vault" },
	},
	ReceiptHistory = 50, -- purchase ids remembered per profile (duplicate receipts are ignored)
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
		GravityCancel = 0.85, -- a slow, floating fall while gathering energy (on the way down only)
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
	RequirePick = true, -- a match only starts after a player picks a mode in the lobby
	PointsPerSet = 15,
	DecidingSetPoints = 11,
	WinBy = 2,
	PointCap = 25,
	SetsToWin = 2,
	IntermissionTime = 15, -- countdown after the first pick
	IntermissionFastTime = 4, -- once every player has picked
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
	-- Skill by bot tier: every pair is { weakest (D-), strongest (S+) }, so a D- team is slow,
	-- sloppy and mistake-prone while an S+ team is clean (on top of their stats).
	JumpTimingNoise = { 0.15, 0.02 }, -- seconds
	ContactNoise = { 1.3, 0.1 }, -- studs of positioning error under the ball
	ReactionDelay = { 0.32, 0.03 }, -- seconds before starting to move for a new ball
	PerfectReceiveChance = { 0.05, 0.65 },
	SloppyStance = { 0.9, 0.3 }, -- how far outside the perfect window a normal receive is pressed
	WhiffChance = { 0.3, 0.03 }, -- misses a heavy spike outright
	MissChance = { 0.08, 0.0 }, -- misses any ball
	SpikeMishitChance = { 0.35, 0.02 }, -- frames the swing (a weak, wild spike)
	ServeMissChance = { 0.14, 0.01 },
	BlockChance = { 0.35, 0.9 },
	ReadOutChance = { 0.45, 0.9 },
	SlideChance = { 0.35, 0.85 },
	FeintChance = 0.12,
	JumpServeTier = 9, -- tier index from which bots jump serve
	ServeDelay = { 1.0, 2.0 },
	-- Covering: when a ball is a human's to play, the nearest teammate bot shadows it and plays
	-- it unless the human tried something (stance, slide, jump, block, touch) this recently.
	CoverYield = 1.0,
	CoverDepth = 1.5, -- the cover stands this much deeper than the human's spot
	CoverAfterMiss = 1.5, -- after the human whiffs, the cover plays the ball for this long
	SwapMargin = 1.2 * M, -- a human this much closer to a teammate's spot than their own takes it
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
