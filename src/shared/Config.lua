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
	RecoverLoser = 0.2,
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
	Max = 210,
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
	Order = { "Char", "Style", "Color", "Trail", "Effect" },
	Banners = {
		Char = { Name = "Characters", Blurb = "Named characters with their own role, stats, height and ability." },
		Style = { Name = "Spike style", Blurb = "Unlocks spike animations." },
		Color = { Name = "Spike color", Blurb = "Unlocks the colour of your spikes and their impact." },
		Trail = { Name = "Trail", Blurb = "Unlocks the trail your spikes leave." },
		Effect = { Name = "Score effect", Blurb = "Unlocks what happens where your attack lands for a point." },
	},
	-- a character's rarity comes from its tier; sub-tiers share it (minus most common)
	TierRarity = { D = "Common", C = "Common", B = "Rare", A = "Epic", S = "Legendary", ["S+"] = "Mythic" },
	TierWeights = { ["-"] = 3, [""] = 2, ["+"] = 1 },
	SellValue = { Common = 5, Rare = 12, Epic = 30, Legendary = 80, Mythic = 250 },
	AutoSellable = { "Common", "Rare", "Epic" },
	AutoRollMax = 100, -- an auto-roll stops after this many spins
	AutoRollDelay = 0.4, -- seconds between auto-roll spins (so the reveal can be seen)
	AutoRollTarget = "Legendary", -- stops at this rarity or better
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

-- Abilities come with a character (the Roster module). S+ wing spikers: Thunder Spiker or Azure Dragon.
-- S characters have their role's ability. Everyone else has none.
Config.Abilities = {
	Thunder = {
		Name = "Thunder Spiker",
		Tier = "S+",
		Blurb = "Hit the ball above 4.00 m and it becomes a lightning spike.",
		Color = Color3.fromRGB(255, 225, 77),
	},
	Azure = {
		Name = "Azure Dragon",
		Tier = "S+",
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
		Blurb = "Press Q: for a moment every ball that reaches your block is stuffed, whatever its power.",
		Color = Color3.fromRGB(150, 205, 255),
		Duration = 3.0,
		Cooldown = 20,
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
		Blurb = "Every ball the other team sends that you dig fills your Counter meter, and one hard spike fills it. Spikes you receive cost no stamina: blades burst out and sink back in. The meter adds up to +40 Attack and +70 Defense, and your next spike releases all of it for up to +12% more power.",
		Color = Color3.fromRGB(190, 220, 255),
		-- stat points at a full meter (0..100, in proportion below it)
		PerFull = { Attack = 40, Defense = 70 },
		ReleaseBoost = 0.12, -- her spike releases the meter: speed x (1 + this x meter / 100), then it's empty
		GainPerKmh = 0.8, -- meter per km/h of a hard spike she receives (a 125 km/h spike fills it)
		MinGain = 40,
		MaxGain = 100,
		LightGain = 30, -- any other ball of theirs she digs (serves, feints, free balls)
	},
}
Config.AbilityOrder = { "Thunder", "Azure", "Adrenaline", "IronWall", "ChainReaction", "Vector", "Turnabout", "RisingSun", "RallyCry", "Counter" }

Config.Roles = {
	WS = { Name = "Wing spiker", Short = "WS" },
	SE = { Name = "Setter", Short = "SE" },
	MB = { Name = "Middle blocker", Short = "MB" },
	Solo = { Name = "Solo", Short = "SO" },
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
	PreMatchTime = 3.2,
	PreServeTime = 1.2,
	ServeClock = 8,
	PointPauseTime = 2.6,
	SetEndTime = 3.5,
	MatchEndTime = 9,
	DefaultBotTier = "A",
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

-- Leaderboards (the Leaderboards module ranks them): global OrderedDataStores, one per stat,
-- written from each player's career counters; a server-only board when those can't be reached.
Config.Leaderboards = {
	Boards = {
		{ Key = "wins", Name = "Wins", Unit = "wins" },
		{ Key = "bestStreak", Name = "Best win streak", Unit = "in a row" },
		{ Key = "kills", Name = "Spike kills", Unit = "kills" },
		{ Key = "aces", Name = "Aces", Unit = "aces" },
		{ Key = "blocks", Name = "Blocks", Unit = "blocks" },
	},
	StorePrefix = "SpikeRushBoard_v1_",
	Top = 50,
	RefreshInterval = 120, -- seconds between reading the global boards
	FlushInterval = 60, -- seconds between writing changed players' scores
}

-- The tutorial (the Tutorial module has the steps): a 1v1 against a weak bot; finishing every
-- step pays this once.
Config.Tutorial = {
	RewardVP = 50,
	RewardGold = 1000,
	RewardSpins = 5, -- free x1 recruits (used before V Points)
	BotTier = "D-",
	Mode = 1,
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
	QuickChance = { 0.12, 0.35 },
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
