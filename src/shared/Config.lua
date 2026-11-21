-- Volleyball Rush configuration (2.5D side-view edition).
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

Config.GameName = "Volleyball Rush"

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
	-- court depth toward the camera (visual only in 2.5D): a real court's 9 m across (the owner,
	-- 2026-10-30: "make the court bigger ... see all the blank spaces"; it was 6 m, a thin strip in
	-- the side-on shot with floor all round it)
	HalfWidth = 4.5 * M,
	SideDepth = 9 * M, -- end lines 9 m from the net
	AttackLine = 3 * M,
	FreeZoneEnd = 3.5 * M, -- serving area behind each end line
	FreeZoneSide = 8,
	NetTop = 2.43 * M,
	NetBottom = 1.43 * M,
	NetHalfWidth = 4.5 * M + 2, -- (the posts stand just outside the court)
	AntennaHeight = 0.8 * M,
	CeilingY = 19 * M,
	WallHalfX = 65, -- far wall (the near side is open for the camera)
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
	-- air drag, per second (BallPhysics: a launch keeps its landing point and time, and leaves the
	-- hand faster and slows toward the end, as a real ball does)
	Drag = 0.22,
	LandGrace = 0.2,
	VisualBlendTime = 0.08,
	-- an attack reaching the hands of a blocker on another client waits there this long (s) for the
	-- server's block, so the block doesn't snap the ball back through the hands (BallRenderer)
	BlockHold = 0.18,
	-- Someone else's hit (the owner: "the issue of teleporting balls in servers"): a hit is timed on
	-- the hitter's own client, so by the time everyone else hears of it the new path is already
	-- LagMin..LagMax seconds along (a 200 km/h spike: about 40 studs at 0.15 s), and the ball jumped
	-- there. Now it starts from the hit and plays the path fast until it has caught up: over
	-- lag * Stretch seconds (Time[1]..Time[2]). A lag past LagMax (joining mid-rally) still jumps.
	CatchUp = { LagMin = 0.03, LagMax = 0.75, Stretch = 2.5, Time = { 0.15, 0.5 } },
	-- Someone else's touch heard late (the owner, 2026-10-28: "work on the ball teleporting"): until
	-- it arrived the ball flew on past their hands, into the floor even, then jumped back. While the
	-- ball is in the reach of a player on another client who may touch it next (Side studs across,
	-- Below..Above studs from their root, not rising faster than RiseMax), it's drawn at Rate of its
	-- speed until it's as far behind its flight as other players' touches really reach us (measured
	-- on each one, eased by LagEase; LagCap the most a measure counts; Max at most), so their touch
	-- starts about where it's drawn; under MinLag (Studio, a good connection) it never slows (the
	-- owner: "the ball is slowing down"). Out of reach with no touch it catches up, Release seconds a
	-- second. Never while it's in your own reach (Mine): you hit the real ball. Visual only.
	ReachHold = { Rate = 0.55, Max = 0.35, MinLag = 0.06, LagEase = 0.35, LagCap = 0.6, Release = 1.6, Side = 7.5, Below = 4.5, Above = 7.5, RiseMax = 18, NetSlack = 0.5, Mine = 8.5 },
	-- a correction this far (studs) or nearer glides over VisualBlendTime + distance / BlendSpeed
	-- seconds (at most BlendTimeMax); further, it jumps (a new rally, a rejoin)
	BlendMax = 40,
	BlendSpeed = 220,
	BlendTimeMax = 0.25,
}

Config.Player = {
	Gravity = 45, -- workspace gravity (floaty jumps); the server also sets this at startup
	RootGround = 3.0, -- typical HumanoidRootPart height when standing (R15)
	HangVelocityWindow = 9, -- |vy| below this counts as "near the top of the jump"
	HangGravityCancel = 0.45, -- fraction of gravity cancelled near the apex (anime hang time)
	-- Spike's jump on the ground is one tap with no run-in dash on every device, as the touch Jump
	-- button was (the owner, 2026-10-13: "no run in dash"). The gather and dash below are Feral
	-- Leap's now.
	ApproachGather = 0.1, -- crouch before a Feral Leap
	ApproachDash = 2.2, -- run-in speed (x walk speed x Approach) during a leap's gather
	ApproachBoost = 18, -- takeoff speed along the court for a leap (x Approach)
	-- Double approach (a setting, every device): the first tap squeaks on the floor and starts the
	-- approach (you don't move; the stick walks as usual), the second jumps as one tap would without
	-- the setting (the owner: "tap once to start and tap again to jump"). With no second tap inside
	-- ApproachArmTime it's let go.
	ApproachArmTime = 1.0,
	AirControl = 0.55, -- air drift speed as a fraction of walk speed
	-- Slides (buffed 2026-10-10, the owner: "major buff to sliding"): was 50 / 0.42 / 0.38 / 0.75,
	-- about 16 studs of slide; now about 24 with half the recovery and a shorter cooldown.
	SlideSpeed = 64,
	SlideTime = 0.5,
	SlideRecover = 0.2,
	SlideCooldown = 0.45,
	BlockChargeTime = 0.45, -- hold the block key this long for a full-height block
	BlockMinHeight = 0.55, -- a tapped block jumps this fraction of full height
	-- a full block jump is this fraction of a spike jump (it was the whole jump: hands 0.4 studs over
	-- the spiker's best contact, so nothing got over; the owner, 2026-11-16: "nerf blocking to not be
	-- as high as spike height"). Real blockers reach about this share of their approach jump
	BlockFullHeight = 0.8,
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
	SlideReach = 7.0, -- was 5.2 / -3.5 / 1.2 before the slide buff
	SlideMinY = -4.0,
	SlideMaxY = 2.0,
	SetIdealY = 3.4,
	SetHalfY = 2.4,
	SetMinY = 1.2,
	SetMaxY = 6.4,
	SetReach = 3.0,
	FloatUp = 4.0,
	FloatRadiusZ = 2.8,
	FloatRadiusY = 2.2,
	BlockReachUp = 4.3, -- hands above the root when blocking
	BlockStuffCover = 3.5, -- a stuff needs the hands this far (studs) over the ball; nearer, it's soft or tooled (HitLogic)
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
	-- the soft cap on every spike and jump serve (the owner, 2026-10-21: "dante is hitting 400 kmh
	-- and yejun is easily breaking 300" with buffs stacked): past SpeedKnee only SpeedOver of the
	-- rest counts, and nothing goes past SpeedMax (266 -> 256, 300 -> 270, 400 -> 300)
	SpeedKnee = 250,
	SpeedOver = 0.4,
	SpeedMax = 300,
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
	-- a deep tip (the owner, 2026-10-22: "allow deep court tipping based on holding the tip button"):
	-- the tip goes when the button's let go; held past FeintHoldDead it reaches deeper, all the way
	-- to FeintDeepDepth (metres from the net) held FeintHoldFull seconds, its arc a little higher
	FeintDeepDepth = 7.5 * M,
	FeintHoldDead = 0.12,
	FeintHoldFull = 0.7,
	FeintDeepLift = 1.2 * M,
	FeintError = 0.8 * M,
	-- (the owner, 2026-10-16: "Buff faints. Right now they cannot go over any blocks. Especially
	-- tetsuo. In tsc, faints are heavily effective tools that break stamina when they are low and
	-- usually never get blocked. Sure it still can, but a very light soft touch block"): a block
	-- reaches a feint FeintTouchChance of the time (x the block's quality; Iron Wall and Bulwark the
	-- same, no perfect stop) and then only softens it; dug with the team's guard at FeintBreakAt or
	-- less it breaks the guard, above that it costs FeintDrain
	FeintTouchChance = 0.22,
	FeintBreakAt = 0.3,
	FeintDrain = 6,

	-- Receives: high and slow so the setter has time
	PassApexMin = 5.6 * M,
	PassApexMax = 7.6 * M,
	PassArriveY = 9, -- the setter's hands (studs, from the avatar)
	PassError = 1.6 * M,
	PassGravityScale = 1.0,
	ShankAt = 0.3,
	SlidePassApex = 6 * M, -- was 5 m and a 0.62 floor before the slide buff
	SlideQualityFloor = 0.8, -- a slide receive is always at least a Great
	SlidePassDrift = 0.25, -- metres a slide pass lands deeper and its extra error (was 0.6)
	-- a slide receive pays this fraction of a bump's guard drain (the owner: "it shouldnt be
	-- invincible but right now its the same as a bump"); it can still break or fail on a broken guard
	SlideDrainMul = 0.35,
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
	-- SetChargeTime); letting go sets. SetAimMax reaches just inside the end line (the owner:
	-- "unrestrict the horizontal distance on setter mode", "to reach the very back court")
	SetAimMin = 0.6 * M,
	SetAimMax = 8.6 * M,
	SetAimLowY = lift(2.6),
	SetAimHighY = lift(4.6),
	SetChargeTime = 1.4,
	-- a set going deeper than BackDepth goes this much higher per stud further back (the owner:
	-- "maybe higher sets too"): a set to the back line climbs about 2.3 m more, time to get there
	SetDeepApex = 0.5,
	OpenDepth = 2.3 * M, -- attack spots, distance from the net
	QuickDepth = 1.2 * M,
	BackDepth = 3.9 * M,
	SetterDepth = 1.06 * M,

	-- Serves
	-- (higher, the owner, 2026-10-17: "increase the height of the serve toss"; were 11, 3.4 and 5.6)
	TossLow = 13, -- studs above the release: the overhand toss comes back to the hand
	TossHighMin = 4.2 * M,
	TossHighMax = 7.0 * M,
	FeralTossHigh = 5.6 * M, -- Valen's charging toss stays at the old top: his full charge still meets it at the top of his jump
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
	-- Hard spikes into a block (the owner: "right now im spiking at 300 kmh and it easily gets eaten
	-- up... every hit is a soft touch block even from an a tier"): past BlockOverKmh[1] a spike keeps
	-- getting harder to stop (its stuff score BlockOverStuff lower by BlockOverKmh[2]), and one the
	-- block doesn't stuff is never a soft touch: it blasts through (BlastChance, rising with the
	-- speed; BlastKeep of its speed) or goes off the hands and out
	BlockOverKmh = { 200, 300 },
	-- How hard a spike looks (the owner: "the 300kmh and the 200 visually look identical"): every
	-- spike past 120 km/h wore the same trail, slash and impact, and a 200 crosses the court in
	-- about 10 frames, a 300 in 7, too quick to tell apart. From SpeedFeel[1] up to SpeedFeel[2]
	-- the trail gets thicker, longer and white-hot, a shockwave rings off the contact (a second
	-- sonic boom past the middle), and the floor impact, shake and speed lines grow
	SpeedFeel = { 180, 320 },
	BlockOverStuff = 0.25,
	-- A well-hit spike into a block (the owner, 2026-11-16: "at a point its just impossible to spike
	-- past a blocker"): its stuff score is BlockSpikeQuality lower for a perfect one (none for a Good
	-- one or worse); one over shallow hands (Zones.BlockStuffCover) tools off them and out up to
	-- BlockShallowTool of the time, from none for a barely Good one to all of it for a Perfect one
	-- (always off the fingertips from a Great one)
	BlockSpikeQuality = 0.25,
	BlockShallowTool = 0.85,
	BlastChance = { 0.35, 0.75 },
	BlastKeep = 0.8,
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
	-- (the owner: "losing multiple points in a row exponentially increases the stamina that is
	-- gained back"): each point lost in a row multiplies that by this (0.5, 0.7, 0.98: about full
	-- after the third), capped at the whole bar
	LossStreakGrowth = 1.4,
	-- The drain above is what an S+ attacker's ball costs. Lower tiers hit the guard less and
	-- less: Low for a D-, rising along ((tier - 1) / 14) ^ Exponent to 1 for S+ (B about half,
	-- A about 0.7, S about 0.9).
	TierDrainLow = 0.25,
	TierDrainExponent = 1.6,
}

-- Moods (the owner, 2026-11-04, from The Spike Cross's Conditions: "theres 4 states of moods"; "based
-- on the mood state the player gets highlighted": Discouraged purple with worry lines, Encouraged
-- glowing yellow with stars, Anger red, Careless green). One at a time, for Secs, and a timeout resets
-- them all. HitLogic.moodAfter rolls them off a point (Events: a chance each, in order) and
-- HitLogic.moodIdle gives Careless to whoever hasn't touched the ball for CarelessFrom points or more,
-- likelier the longer it goes. Prone: how much likelier a character is (x chance). Discouraged's stats
-- are TigerClaw.DiscouragedCut (and Tiger Claw, RAWR! and Falling Star still bring it on).
Config.Moods = {
	Secs = 20,
	Encouraged = { Label = "Encouraged", Color = Color3.fromRGB(255, 214, 70), Add = { Attack = 5, Defense = 5, Speed = 5, Jump = 5 } },
	Anger = { Label = "Angry", Color = Color3.fromRGB(255, 44, 36), Add = { Attack = 10, Speed = 8, Defense = -8, Jump = -6 } },
	Careless = { Label = "Careless", Color = Color3.fromRGB(70, 230, 110), Add = { Defense = -16, Speed = -16 } },
	Discouraged = { Label = "Discouraged", Color = Color3.fromRGB(150, 70, 255) },
	Events = {
		Ace = { { "Encouraged", 0.5 }, { "Anger", 0.25 } },
		Block = { { "Encouraged", 0.5 } },
		Score = { { "Encouraged", 0.15 } },
		Fail = { { "Discouraged", 0.3 }, { "Anger", 0.2 } }, -- a failed attack: out, in the net or stuffed
	},
	CarelessFrom = 5,
	CarelessChance = 0.12, -- at CarelessFrom points without a touch...
	CarelessStep = 0.08, -- ...and this much more for each one after
	Prone = {
		kuro = { Anger = 1.5 },
		dante = { Anger = 1.5 },
		joon = { Encouraged = 1.5 },
		haesol = { Encouraged = 1.5 },
		tetsuo = { Discouraged = 0.5 },
		taeha = { Careless = 1.5 },
	},
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
-- Breakthroughs (the owner, after Spike Cross: "getting a dupe of a character gets you a fragment
-- named based on the tier of a character... say you pull a dupe shoyo, you get an s tier fragment.
-- you can put that onto ines to upgrade her up to +5", with Spike Cross's tables for scale, "more
-- fit the balance of our game"). A duplicate character pulled gives a fragment of its letter
-- (S- and S give S; S+ has its own) instead of VP. Spending Cost[n] fragments of a character's
-- letter takes it to breakthrough n (Max at most): Stats[role][n] stat points over its roster
-- ceiling (x NoAbilityMul for a character with no ability, which gets nothing else), and each of
-- its ability's Ability entries grows (at Max: x 1 + Grow; Kind "excess": only the part over 1
-- grows, for a multiplier like 1.12). A fragment sells for its rarity's duplicate VP
-- (Spins.SellValue), and SellLucky lucky spins with it (the owner: "the higher tier fragment you
-- sell, maybe you can get a lucky spin").
Config.Breakthrough = {
	Max = 5,
	Groups = { "D", "C", "B", "A", "S", "S+" },
	Cost = { 1, 1, 1, 1, 1 },
	-- about 8 points a step, 40 at +5 (some 5% of an S+'s stats; Spike Cross's are on a smaller scale)
	Stats = {
		WS = { { Attack = 4, Jump = 4 }, { Attack = 3, Speed = 2, Jump = 3 }, { Attack = 3, Defense = 2, Jump = 3 }, { Attack = 4, Speed = 4 }, { Attack = 4, Jump = 4 } },
		MB = { { Defense = 4, Jump = 4 }, { Attack = 3, Defense = 3, Jump = 2 }, { Defense = 4, Jump = 4 }, { Attack = 3, Defense = 3, Speed = 2 }, { Defense = 4, Jump = 4 } },
		SE = { { Speed = 4, Defense = 4 }, { Speed = 3, Defense = 3, Jump = 2 }, { Speed = 4, Defense = 4 }, { Attack = 3, Speed = 3, Defense = 2 }, { Speed = 4, Defense = 4 } },
	},
	NoAbilityMul = 1.5,
	-- the lower the tier, the more each step gives (the owner, 2026-10-15: "make breakthroughs way
	-- more powerful on lower tier in terms of stats", then "a d shouldn't be hitting low s"): maxed,
	-- D totals about 405 stat points, C 447, B 504, A 566, S 619 (Hwan 575 the lowest), S+ 678; at +5
	-- (40 a step's base, x TierMul, x NoAbilityMul without an ability, each point rounded) a D gains
	-- 132 (Rui to 554: near a maxed A like Fuyu's 580, under every S), C 114, B 92, A 80, S 46, S+ 40
	-- (D 3 put a +5 Rui at 604, over Hwan; D 4 at 662)
	TierMul = { D = 2.2, C = 1.9, B = 1.5, A = 1.25, S = 1.15, ["S+"] = 1 },
	-- an active ability's cooldown is this much shorter at +Max, a fifth of it a step (the owner:
	-- "allow breakthroughs to also effect cooldowns"; was 0.3, then 0.4). Then (2026-10-21: "dont
	-- focus so much on cooldowns and instead focus on ability passives. like joon should have
	-- increased buff power not cooldown reduction"): a smaller cut, none at all where the ability's
	-- own effect grows instead (CooldownCuts), and each active's effect grows below
	CooldownCut = 0.15,
	CooldownCuts = { RallyCry = 0, Tyrant = 0, Turnabout = 0, Fever = 0 },
	-- per ability: the settings that grow, and how each shows in the Breakthrough table (Show: "pct"
	-- a share as %, "excess" a multiplier's part over 1 as %, "num" points, "s" seconds, "kmh";
	-- Field: the entry of a table setting to show)
	Ability = {
		Thunder = { SecondBoost = { Grow = 0.3, Label = "Second swing", Show = "pct" }, StaticPer = { Grow = 0.3, Label = "Static Charge a stack", Show = "pct" }, StormBoost = { Grow = 0.6, Label = "Storm Call power", Show = "pct" } },
		Azure = { MaxBoost = { Grow = 0.15, Label = "Full charge", Show = "pct" } },
		Feral = { MaxBoost = { Grow = 0.2, Label = "Full leap", Show = "pct" } },
		Enflamed = { MaxBoost = { Grow = 0.2, Label = "Flame power", Show = "pct" } },
		FallingStar = { StarBoost = { Grow = 0.3, Label = "Star spike", Show = "pct" }, Duration = { Grow = 0.2, Label = "Falling Star lasts", Show = "s" } },
		ZeroPoint = { ZeroKmh = { Grow = 0.04, Label = "Zero Point", Show = "kmh", Field = 2 } },
		Corona = { Boost = { Grow = 0.2, Label = "Flare: every stat", Show = "pct" }, SpikeBoost = { Grow = 0.3, Label = "Sunfire", Show = "pct" } },
		Squall = { SpikeBoost = { Grow = 0.25, Label = "Shear", Show = "pct" }, HoverBoost = { Grow = 0.25, Label = "Full hover", Show = "pct" } },
		Ironclad = { WallBoost = { Grow = 0.2, Label = "Forge with shields", Show = "pct" }, MaxBoost = { Grow = 0.15, Label = "Forge awakened", Show = "pct" } },
		Adrenaline = { AttackBonus = { Grow = 0.4, Label = "Adrenaline Attack", Show = "num" }, JumpBonus = { Grow = 0.4, Label = "Adrenaline Jump", Show = "num" } },
		IronWall = { Duration = { Grow = 0.3, Label = "Iron Wall lasts", Show = "s" }, StuffKmh = { Grow = 0.4, Label = "Shut-down speed", Show = "kmh" } },
		ChainReaction = { PowerMul = { Grow = 0.3, Kind = "excess", Label = "Biggest explosion", Show = "excess", Field = 3 } },
		Vector = { MaxBoost = { Grow = 0.3, Label = "Steepest spike", Show = "pct" } },
		Featherfall = { MaxBoost = { Grow = 0.3, Label = "Longest fall", Show = "pct" } },
		Turnabout = { PowerMul = { Grow = 0.4, Kind = "excess", Label = "Turnabout power", Show = "excess" } },
		RisingSun = { PerLevel = { Grow = 0.3, Label = "Attack a Sunrise level", Show = "num", Field = "Attack" } },
		RallyCry = { Boost = { Grow = 0.5, Label = "Rally Cry boost", Show = "pct" }, Duration = { Grow = 0.2, Label = "Rally Cry lasts", Show = "s" } },
		Counter = { ReleaseBoost = { Grow = 0.2, Label = "Counter Edge release", Show = "pct" } },
		Plunge = { PowerBoost = { Grow = 0.5, Label = "Plunge power", Show = "pct" } },
		-- (the owner, 2026-10-22: "seora breakthrough should obviously increase jump not attack"): her
		-- highest hitting point climbs (MaxLift, metres), her Attack at the top stays
		Skyward = { MaxLift = { Grow = 0.6, Label = "Highest lift", Show = "m" } },
		Tyrant = { Steal = { Grow = 0.4, Label = "Lock takes", Show = "pct" }, Duration = { Grow = 0.25, Label = "Emperor's Dictate lasts", Show = "s" }, SetMul = { Grow = 0.3, Kind = "excess", Label = "Tyrant's Set", Show = "excess" } },
		Sunshine = { SunDuration = { Grow = 0.3, Label = "Sunshine lasts", Show = "s" }, VertBoost = { Grow = 0.3, Label = "Sharpest spike", Show = "pct" } },
		-- (the fan's breakthroughs: "more buffs per fever charge and duration, higher too cold
		-- chance"; at +5 "fever maxed gives +8%", "+10 to everything", "too cold 5%, with fever 7%")
		TigerClaw = { FierceAdd = { Grow = 0.8, Label = "Fierce Tiger: Attack", Show = "num", Field = "Attack" } },
		Joker = { SurpriseBoost = { Grow = 0.5, Label = "Surprise!", Show = "pct" }, JackpotAdd = { Grow = 0.4, Label = "Jackpot!: every stat", Show = "num" } },
		Fever = { PerBlock = { Grow = 0.5, Label = "Fever a block", Show = "pct" }, Max = { Grow = 0.5, Label = "Fever's most", Show = "pct" }, Duration = { Grow = 0.25, Label = "Fever lasts", Show = "s" }, StatAdd = { Grow = 0.6, Label = "Fever: Defense", Show = "num", Field = "Defense" }, ColdChance = { Grow = 1.5, Label = "Too cold", Show = "pct" }, ColdFever = { Grow = 0.75, Label = "Too cold in Fever", Show = "pct" } }, -- (Too cold grows less since the 2026-11-14 buff doubled its base: still 5% / 7% at +5)
	},
	SellLucky = { ["S+"] = 1 },
}

Config.Upgrades = {
	StartFraction = 0.55,
	BaseCost = 8, -- gold for a point at Stats.Min
	CostPerPoint = 0.35, -- plus this per stat point above Min
	TierMul = { D = 0.6, C = 0.8, B = 1.0, A = 1.3, S = 1.7, ["S+"] = 2.2 },
	-- the player page's step chips; MaxStep is the Max chip (the owner, 2026-10-29: "just add a max
	-- feature alongside the 10x"): + goes to the ceiling (as far as the Gold reaches), - back to the
	-- base, refunded
	Steps = { 1, 5, 10, 1000 },
	MaxStep = 1000,
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
	-- (past 210 it keeps adding: Hayul, the fastest, is above it, and boosts push others past it)
	WalkSpeed = { Stat = "Speed", Range = { 22, 32 }, Extrapolate = true },
	SetAccuracy = { Stat = "Speed", Range = { 0.7, 1.0 } },
}

-- Every character has a height. Taller = higher standing reach and bigger hit zones, so two
-- characters with the same Jump stat hit from different heights.
Config.Height = {
	Min = 165,
	Max = 216, -- Rafael (was 210; ZoneScale's top moved with it, so every other height keeps its zone)
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
	-- (the owner, 2026-10-17, after a reference's normal odds: Common 62.495, Rare 35, Legendary 2,
	-- Godly 0.495, Secret 0.01; ours rarity for rarity)
	Weights = { Common = 62.495, Rare = 35, Epic = 2, Legendary = 0.495, Mythic = 0.01 },
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
	Order = { "Char", "Style", "Color", "Trail", "Jump", "Effect", "Pose", "Ball" },
	Banners = {
		Char = { Name = "Characters", Blurb = "Named characters with their own role, stats, height and ability." },
		Style = { Name = "Spike style", Blurb = "Unlocks spike animations." },
		Color = { Name = "Spike color", Blurb = "Unlocks the colour of your spikes and their impact." },
		Trail = { Name = "Trail", Blurb = "Unlocks the trail your spikes leave." },
		Jump = { Name = "Jump effect", Blurb = "Unlocks what bursts from your feet every time you jump." },
		Effect = { Name = "Score effect", Blurb = "Unlocks what happens where your attack lands for a point." },
		Pose = { Name = "Intro pose", Blurb = "Unlocks how you pose when the teams line up, and after a win." },
		Ball = { Name = "Ball skin", Blurb = "Unlocks the ball's look for every rally you serve." },
	},
	-- a character's rarity comes from its tier; sub-tiers share it (minus most common)
	TierRarity = { D = "Common", C = "Common", B = "Rare", A = "Epic", S = "Legendary", ["S+"] = "Mythic" },
	-- the Characters banner by tier (the owner, 2026-10-15: "instead of flat rates like these, make
	-- it 0.5% to hit the s+ tier, then one of the ones in there, that are boosted. make it like that
	-- for s tier as well. make it all up to equal 100"): a recruit lands on a tier first, by these
	-- chances (%), then on one of its characters (Boost and Lower move odds inside the tier only).
	-- A rarity's tiers add up to its Rarity.Weights; 2x Luck and lucky spins scale the rarity and its
	-- tiers keep their shares; a tier with nobody in it gives its share to the rest of its rarity.
	-- (the owner, 2026-10-17: "why is s tier a higher chance than a tier and s-? make s tier 1% or
	-- maybe even less": S 3 -> 0.75 and S- 1 -> 1.25, Legendary 4% -> 2%, the 2% to B)
	TierOdds = { ["S+"] = 0.01, S = 0.185, ["S-"] = 0.31, ["A+"] = 0.4, A = 0.64, ["A-"] = 0.96, ["B+"] = 6, B = 13, ["B-"] = 16, ["C+"] = 8, C = 12.5, ["C-"] = 15.995, ["D+"] = 9, D = 10.2, ["D-"] = 6.8 },
	SellValue = { Common = 5, Rare = 12, Epic = 30, Legendary = 80, Mythic = 250 },
	AutoSellable = { "Common", "Rare", "Epic" },
	AutoRollMax = 100, -- an auto-roll stops after this many spins
	AutoRollDelay = 0.4, -- seconds between auto-roll spins (so the reveal can be seen)
	AutoRollTarget = "Legendary", -- stops at this rarity or better
	-- Pity, on the Characters banner (the owner: "normal pity is 200 for a random s tier... lucky
	-- spins... 50... first pity hit is a random s+, next one is a chosen s+"). Recruits count up
	-- until one of ResetTiers comes (by luck or by pity) and start again; the recruit that
	-- reaches Every gives one of Tiers. Lucky spins count on their own: every lucky pity is the S+
	-- you picked (the owner, 2026-10-30: "make lucky pity 100% give u the one u pick now"; it was a
	-- random S+ first, then your pick), a random S+ until you pick one. Normal
	-- recruits also count toward an S+ (Top, the owner: "add a normal spin S+ pity but it has to be
	-- 350 pulls", then 250): an S+ is a 0.01% pull (since 2026-10-17), so nearly every S+ from normal
	-- recruits comes from this pity. When Top and Normal land on the same recruit, Top wins.
	-- Luck (Config.Admin's event, your own boost: Config.Boosts, the Lucky pass): N times the luck
	-- makes these rarities N times as likely on the Characters banner (A- and up: Epic, Legendary,
	-- Mythic), the rarest first, and the rest of the 100 goes down the order (Rare, then Common):
	-- 2x takes its extra from the Commons alone (an S+ 0.01% x N since 2026-10-17). The
	-- event, your boost and the pass multiply (the owner: "make it so if there is an admin 2x it
	-- stacks and make that clear"; Spins.luckWeights). Lucky spins too since 2026-10-17 (Spins.luckyAt:
	-- the same rule on Config.Lucky's weights, the extra out of the Rares).
	LuckEvent = { Double = { "Epic", "Legendary", "Mythic" } },
	Pity = {
		Normal = { Every = 200, Tiers = { "S-", "S" }, ResetTiers = { "S-", "S", "S+" } },
		Top = { Every = 250, Tiers = { "S+" }, ResetTiers = { "S+" } }, -- (was 350: the owner, 2026-10-17, "buff the pity to only 250 on normal spins")
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
	-- the testers' copy, "Volleyball Generations" (the owner, 2026-11-04: "give them infinite
	-- everything, just like an admin"): everyone in that experience is a developer with TestFunds
	-- VP and Gold. An experience id, so it can never apply to the live game (10773415799).
	TestGame = 10773068035,
	TestFunds = 999999999,
	UserIds = {}, -- extra developer UserIds
	Studio = true,
	Owner = true,
}

-- Unlockables. The first item of each list is owned by everyone and equipped by default.
Config.Cosmetics = {
	Kinds = { "Style", "Color", "Trail", "Jump", "Effect", "Pose", "Ball" },
	Attribute = { Style = "SpikeStyle", Color = "SpikeColor", Trail = "SpikeTrail", Jump = "JumpEffect", Effect = "ScoreEffect", Pose = "IntroPose", Ball = "BallSkin" },
	Style = {
		{ Key = "Classic", Name = "Classic", Rarity = "Common" },
		{ Key = "Bow", Name = "Full Bow", Rarity = "Rare" },
		{ Key = "Scissor", Name = "Scissor Kick", Rarity = "Rare" },
		{ Key = "Hammer", Name = "Double Hammer", Rarity = "Epic" },
		{ Key = "Whirl", Name = "Whirlwind", Rarity = "Legendary" },
		-- the owner: "yuji nishida's circular arm swing": the off-hand straight up, the hitting arm
		-- drawn all the way back from the bottom, then unleashed
		{ Key = "Circular", Name = "Circular Swing", Rarity = "Legendary" },
		-- the owner: "a 360 jump or a bicycle kick" (AnimationController's Air_ and Swing_ clips)
		{ Key = "Tornado", Name = "Tornado 360", Rarity = "Legendary" },
		{ Key = "Bicycle", Name = "Bicycle Kick", Rarity = "Mythic" },
		-- the owner, 2026-11-17 (a flipbook by Lemonkey-144): flat out in the air, both feet into
		-- the ball (AnimationController's Air_Dropkick and Swing_Dropkick)
		{ Key = "Dropkick", Name = "Dropkick", Rarity = "Legendary" },
	},
	Color = {
		{ Key = "Default", Name = "Classic", Rarity = "Common" },
		-- (the owner, 2026-10-15: "pumpkin, tangerine, candy corn, and blood moon and crimson are
		-- nearly identical": the plain ones stay one bright colour; Pumpkin, Candy Corn, Blood Moon and
		-- Ectoplasm wear bands of their own, which the Locker's swatch shows too)
		{ Key = "Crimson", Name = "Crimson", Rarity = "Common", Color = Color3.fromRGB(255, 36, 64) },
		{ Key = "Tangerine", Name = "Tangerine", Rarity = "Common", Color = Color3.fromRGB(255, 150, 50) },
		{ Key = "Lime", Name = "Lime", Rarity = "Rare", Color = Color3.fromRGB(150, 255, 80) },
		{ Key = "Violet", Name = "Violet", Rarity = "Rare", Color = Color3.fromRGB(175, 95, 255) },
		{ Key = "Aqua", Name = "Aqua", Rarity = "Rare", Color = Color3.fromRGB(60, 230, 255) },
		-- white and black are colours, not trails (the owner: "why is white and black in trails it
		-- should be in colors"). Black's trail is drawn without glow (black light is invisible) and
		-- its impacts in a smoky dark grey
		{ Key = "White", Name = "Pure White", Rarity = "Rare", Color = Color3.fromRGB(255, 255, 255) },
		{ Key = "Gold", Name = "Gold", Rarity = "Epic", Color = Color3.fromRGB(255, 210, 60) },
		{ Key = "Void", Name = "Void", Rarity = "Epic", Color = Color3.fromRGB(120, 50, 200) },
		{ Key = "Black", Name = "Jet Black", Rarity = "Epic", Color = Color3.fromRGB(78, 76, 92), Trail = { Color3.fromRGB(6, 6, 10), Color3.fromRGB(44, 42, 56) }, Emission = 0 },
		{ Key = "Prism", Name = "Prism", Rarity = "Legendary", Color = Color3.fromRGB(255, 120, 220) },
		-- a colour, not a trail (the owner, 2026-10-25: "rainbow should be a color"): the ribbon in the
		-- rainbow's six bands; an owned or equipped Rainbow trail carries over (ProfileService)
		{ Key = "Rainbow", Name = "Rainbow", Rarity = "Legendary", Color = Color3.fromRGB(255, 160, 40), Trail = { Color3.fromRGB(255, 60, 70), Color3.fromRGB(255, 160, 40), Color3.fromRGB(255, 235, 60), Color3.fromRGB(80, 230, 110), Color3.fromRGB(60, 170, 255), Color3.fromRGB(170, 90, 255) } },
		-- Halloween (Limited: only from Config.Halloween's banner and shop)
		-- Pumpkin: deep burnt orange with its green stem; Ectoplasm: a pale ghost glow into mint and
		-- deep teal (Lime is the plain green); Blood Moon: blood red into black, dimly lit
		{ Key = "Pumpkin", Name = "Pumpkin", Rarity = "Rare", Color = Color3.fromRGB(226, 88, 8), Trail = { Color3.fromRGB(255, 140, 30), Color3.fromRGB(214, 74, 6), Color3.fromRGB(64, 140, 34) }, Limited = "Halloween" },
		{ Key = "Ectoplasm", Name = "Ectoplasm", Rarity = "Rare", Color = Color3.fromRGB(90, 255, 180), Trail = { Color3.fromRGB(225, 255, 240), Color3.fromRGB(90, 255, 180), Color3.fromRGB(16, 120, 96) }, Limited = "Halloween" },
		{ Key = "Bloodmoon", Name = "Blood Moon", Rarity = "Epic", Color = Color3.fromRGB(150, 0, 22), Trail = { Color3.fromRGB(205, 14, 34), Color3.fromRGB(96, 0, 14), Color3.fromRGB(14, 0, 4) }, Emission = 0.3, Limited = "Halloween" },
		-- a colour, not a trail (the owner, 2026-10-15: "you are mixing up trails and colors again.
		-- the candy corn is a color"): orange impacts, and the ribbon in candy corn's three bands
		{ Key = "CandyCorn", Name = "Candy Corn", Rarity = "Rare", Color = Color3.fromRGB(255, 150, 30), Trail = { Color3.fromRGB(255, 246, 220), Color3.fromRGB(255, 196, 40), Color3.fromRGB(255, 104, 16) }, Limited = "Halloween" },
		-- the Winter collab (Limited: only from Config.Winter's banner and shop; the owner,
		-- 2026-11-15: "christmas cosmetics... idk make a lot"). Frostbite: white into ice blue into deep
		-- blue; Candy Cane: red and white bands; Holly: green, berry red, gold; Aurora: the northern
		-- lights' green into cyan, violet and pink
		{ Key = "Frostbite", Name = "Frostbite", Rarity = "Rare", Color = Color3.fromRGB(150, 220, 255), Trail = { Color3.fromRGB(244, 251, 255), Color3.fromRGB(150, 220, 255), Color3.fromRGB(40, 110, 230) }, Limited = "Winter" },
		{ Key = "CandyCane", Name = "Candy Cane", Rarity = "Rare", Color = Color3.fromRGB(236, 40, 56), Trail = { Color3.fromRGB(236, 40, 56), Color3.fromRGB(255, 255, 255), Color3.fromRGB(236, 40, 56), Color3.fromRGB(255, 255, 255) }, Limited = "Winter" },
		{ Key = "Holly", Name = "Holly", Rarity = "Epic", Color = Color3.fromRGB(30, 170, 80), Trail = { Color3.fromRGB(30, 170, 80), Color3.fromRGB(220, 30, 46), Color3.fromRGB(255, 210, 80) }, Limited = "Winter" },
		{ Key = "Aurora", Name = "Aurora", Rarity = "Legendary", Color = Color3.fromRGB(80, 255, 190), Trail = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(60, 220, 255), Color3.fromRGB(150, 110, 255), Color3.fromRGB(255, 120, 220) }, Emission = 0.8, Limited = "Winter" },
		-- the advent calendar's (Config.Winter.Advent; the owner, 2026-11-18: "make up a tone of
		-- cosmetics for advent calender"): each its own bands, none a recolour of another
		{ Key = "Tinsel", Name = "Tinsel", Rarity = "Rare", Color = Color3.fromRGB(255, 212, 96), Trail = { Color3.fromRGB(236, 240, 250), Color3.fromRGB(255, 212, 96), Color3.fromRGB(236, 240, 250), Color3.fromRGB(255, 212, 96) }, Emission = 0.5, Limited = "Winter", Advent = true },
		{ Key = "Mistletoe", Name = "Mistletoe", Rarity = "Rare", Color = Color3.fromRGB(70, 176, 86), Trail = { Color3.fromRGB(28, 104, 50), Color3.fromRGB(246, 250, 240), Color3.fromRGB(92, 200, 104) }, Limited = "Winter", Advent = true },
		{ Key = "Eggnog", Name = "Eggnog", Rarity = "Rare", Color = Color3.fromRGB(252, 236, 196), Trail = { Color3.fromRGB(255, 246, 220), Color3.fromRGB(196, 136, 72), Color3.fromRGB(252, 230, 184) }, Limited = "Winter", Advent = true },
		{ Key = "Sugarplum", Name = "Sugarplum", Rarity = "Epic", Color = Color3.fromRGB(206, 96, 226), Trail = { Color3.fromRGB(120, 40, 150), Color3.fromRGB(255, 136, 214), Color3.fromRGB(214, 176, 255) }, Emission = 0.5, Limited = "Winter", Advent = true },
		{ Key = "Evergreen", Name = "Evergreen", Rarity = "Epic", Color = Color3.fromRGB(26, 120, 66), Trail = { Color3.fromRGB(10, 60, 34), Color3.fromRGB(34, 136, 72), Color3.fromRGB(255, 206, 80) }, Limited = "Winter", Advent = true },
		{ Key = "SilverBells", Name = "Silver Bells", Rarity = "Epic", Color = Color3.fromRGB(226, 232, 246), Trail = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(176, 186, 208), Color3.fromRGB(204, 228, 255) }, Emission = 0.6, Limited = "Winter", Advent = true },
		{ Key = "PolarNight", Name = "Polar Night", Rarity = "Legendary", Color = Color3.fromRGB(70, 96, 230), Trail = { Color3.fromRGB(18, 28, 92), Color3.fromRGB(96, 72, 210), Color3.fromRGB(224, 236, 255) }, Emission = 0.8, Limited = "Winter", Advent = true },
	},
	Trail = {
		{ Key = "Ribbon", Name = "Ribbon", Rarity = "Common" },
		{ Key = "Comet", Name = "Comet", Rarity = "Common" },
		{ Key = "Sparkle", Name = "Sparkle", Rarity = "Rare" },
		{ Key = "Flame", Name = "Flame", Rarity = "Epic" },
		{ Key = "Lightning", Name = "Lightning", Rarity = "Epic" },
		{ Key = "Stardust", Name = "Stardust", Rarity = "Legendary" },
		-- Halloween (Limited). Bat Swarm: a violet-black ribbon with bats circling the ball the whole
		-- flight (Fx.batRing; the owner: "batswarm should have a bat flying around effect. it only is
		-- a color right now") and more beating off it (TrailBats). Souls is the Reaper skin's
		-- (Config.Halloween.Skins): never on a banner, worn only with the skin (BallRenderer draws it;
		-- Base: its look anywhere else)
		{ Key = "Bats", Name = "Bat Swarm", Rarity = "Epic", Solid = { Color3.fromRGB(40, 20, 60), Color3.fromRGB(130, 60, 200) }, Emission = 0.4, Limited = "Halloween" },
		-- the Winter collab's (Limited). Snowfall: a white ribbon, snowflakes drifting off the ball and
		-- sinking (Fx's TrailSnowfall). Icicle (the owner's "icicle trail"): an ice-blue ribbon, icicles
		-- shed off the ball and dropping away point first (TrailIcicle)
		{ Key = "Snowfall", Name = "Snowfall", Rarity = "Rare", Limited = "Winter" },
		{ Key = "Icicle", Name = "Icicle", Rarity = "Epic", Limited = "Winter" },
		-- the advent calendar's, each shedding its own things (Fx's Trail kits): gold stars, holly
		-- leaves and berries, spinning candy canes, tumbling gingerbread men, swinging sleigh bells.
		-- The winter trails have no colours of their own: the ribbon stays the spike's Color (the owner,
		-- 2026-11-18: "i dont want effects changing the trail color")
		{ Key = "Starlight", Name = "Starlight", Rarity = "Rare", Limited = "Winter", Advent = true },
		{ Key = "Holly", Name = "Holly", Rarity = "Epic", Limited = "Winter", Advent = true },
		{ Key = "CandyCanes", Name = "Candy Canes", Rarity = "Epic", Limited = "Winter", Advent = true },
		{ Key = "Gingerbread", Name = "Gingerbread Men", Rarity = "Legendary", Limited = "Winter", Advent = true },
		{ Key = "SleighBells", Name = "Sleigh Bells", Rarity = "Legendary", Limited = "Winter", Advent = true },
		{ Key = "Souls", Name = "Souls", Rarity = "Mythic", Base = "Stardust", Solid = { Color3.fromRGB(230, 250, 255), Color3.fromRGB(110, 200, 255), Color3.fromRGB(40, 80, 160) }, Emission = 0.9, Limited = "Reaper", Hidden = true },
	},
	-- what bursts from your feet on every jump (the owner: "maybe add jump effects too... lightning
	-- effects when you jump, fire when you jump"): VFXController.jumpEffect, on top of the usual dust
	-- or boom; the Locker's practice jump previews it
	-- (each list runs Common to Mythic: the owner's "organize please")
	Jump = {
		{ Key = "Plain", Name = "Plain", Rarity = "Common" },
		{ Key = "Sparks", Name = "Sparks", Rarity = "Common" },
		{ Key = "Wind", Name = "Gust", Rarity = "Common" },
		{ Key = "Frost", Name = "Frost", Rarity = "Rare" },
		{ Key = "Shadow", Name = "Shadow", Rarity = "Rare" },
		-- (Tremor, Eruption, Radiance, Foxfire, Blue Phoenix: the Blox Fruits pass, the owner's "and
		-- add more", each built on the look of a different fruit's moves, our own art and names)
		{ Key = "Quake", Name = "Tremor", Rarity = "Rare" },
		{ Key = "Fire", Name = "Fire", Rarity = "Epic" },
		{ Key = "Lightning", Name = "Lightning", Rarity = "Epic" },
		{ Key = "Magma", Name = "Eruption", Rarity = "Epic" },
		{ Key = "Rainbow", Name = "Rainbow", Rarity = "Legendary" },
		{ Key = "Storm", Name = "Thunderstorm", Rarity = "Legendary" },
		{ Key = "Radiant", Name = "Radiance", Rarity = "Legendary" },
		{ Key = "Foxfire", Name = "Foxfire", Rarity = "Legendary" },
		{ Key = "Inferno", Name = "Inferno", Rarity = "Mythic" },
		{ Key = "Phoenix", Name = "Blue Phoenix", Rarity = "Mythic" },
		{ Key = "Angel", Name = "Angel", Rarity = "Mythic" }, -- the owner: "add an angel jump effect with angel wings"
		-- Halloween (Limited): graves rising out of a cold mist, bats across the moon, a jack-o'-lantern
		-- bursting under you (VFXController's HW)
		{ Key = "GraveMist", Name = "Grave Mist", Rarity = "Rare", Limited = "Halloween" },
		{ Key = "BatSwarm", Name = "Bat Swarm", Rarity = "Epic", Limited = "Halloween" },
		{ Key = "JackOLantern", Name = "Jack-o'-Lantern", Rarity = "Legendary", Limited = "Halloween" },
		-- the Winter collab's (Limited; the owner's "snow jumps"): a snowflake opening on the floor, a
		-- snowman popping up, a present bursting open, a Christmas tree shooting up (VFXController's
		-- jumpMeshes; the meshes are ours: art/WinterFX.blend)
		{ Key = "Snowburst", Name = "Snow Burst", Rarity = "Rare", Limited = "Winter" },
		{ Key = "Snowman", Name = "Snowman", Rarity = "Epic", Limited = "Winter" },
		{ Key = "Present", Name = "Present", Rarity = "Epic", Limited = "Winter" },
		{ Key = "Tree", Name = "Christmas Tree", Rarity = "Legendary", Limited = "Winter" },
		-- the advent calendar's: a ring of gold bells swings up round you and rings (WinterSkins.jump)
		{ Key = "JingleBells", Name = "Jingle Bells", Rarity = "Legendary", Limited = "Winter", Advent = true },
		-- the Fallen Angel skin's (Config.Halloween.Skins): never on a banner, the jump he wears with it
		-- in place of the equipped one (arms from the underworld, VFXController's HW.underworld)
		{ Key = "Underworld", Name = "Underworld", Rarity = "Mythic", Limited = "FallenAngel", Hidden = true },
	},
	Effect = {
		{ Key = "Dust", Name = "Dust", Rarity = "Common" },
		{ Key = "Shockwave", Name = "Shockwave", Rarity = "Common" },
		{ Key = "Fire", Name = "Fire Explosion", Rarity = "Rare" },
		-- the owner, after Volleyball Legends: "a tornado", "an explosion displaying stats", "a black
		-- hole", "a tsunami that covers the map", "like rocket league where the explosion alters the
		-- map for a bit" (VFXController's playScore)
		{ Key = "Speed", Name = "Speed Burst", Rarity = "Rare" },
		-- (Ka-Pow, Confetti Cannon, Tesla Dome, Fireworks, Deep Freeze: after Rocket League's goal
		-- explosions; Endless Void and World Slash: the owner's "domain expansions" and "world
		-- cutting slash"; our own art and names)
		{ Key = "Pow", Name = "Ka-Pow", Rarity = "Rare" },
		{ Key = "Confetti", Name = "Confetti Cannon", Rarity = "Rare" },
		{ Key = "Meteor", Name = "Meteor Strike", Rarity = "Epic" },
		{ Key = "Crater", Name = "Crater", Rarity = "Epic" },
		{ Key = "IceAge", Name = "Ice Age", Rarity = "Epic" },
		{ Key = "Volcano", Name = "Volcano", Rarity = "Epic" },
		{ Key = "Tesla", Name = "Tesla Dome", Rarity = "Epic" },
		{ Key = "Thunderbolt", Name = "Thunderbolt", Rarity = "Legendary" },
		{ Key = "Tornado", Name = "Tornado", Rarity = "Legendary" },
		{ Key = "Tsunami", Name = "Tsunami", Rarity = "Legendary" },
		{ Key = "MeteorShower", Name = "Meteor Shower", Rarity = "Legendary" },
		{ Key = "Holy", Name = "Holy Strike", Rarity = "Legendary" },
		{ Key = "Fireworks", Name = "Fireworks", Rarity = "Legendary" },
		{ Key = "BlackHole", Name = "Black Hole", Rarity = "Mythic" },
		-- the owner: "make the avatar big and stomp the opponents and ragdoll them"
		{ Key = "Giant", Name = "Giant Stomp", Rarity = "Mythic" },
		{ Key = "Freeze", Name = "Deep Freeze", Rarity = "Mythic" },
		{ Key = "Void", Name = "Endless Void", Rarity = "Mythic" },
		-- the Winter event's (the owner, 2026-11-16: "make some score effects too", after Blade Ball's
		-- kill effects): they do something to the players who lost the point (VFXController HW.giftWrap,
		-- HW.snowGlobe, HW.delivery)
		{ Key = "GiftWrap", Name = "Gift Wrapped", Rarity = "Legendary", Limited = "Winter" },
		{ Key = "SnowGlobe", Name = "Snow Globe", Rarity = "Mythic", Limited = "Winter" },
		{ Key = "Delivery", Name = "Special Delivery", Rarity = "Mythic", Limited = "Winter" },
		{ Key = "WorldSlash", Name = "World Slash", Rarity = "Mythic" },
		-- (the owner, 2026-11-04: "a fire themed or maybe dragon themed explosion to coincide with kuro's
		-- release"): his dragon, erupting out of the floor (VFXController.kuro.eruption)
		{ Key = "FireDragon", Name = "Fire Dragon", Rarity = "Mythic" },
		-- the ranked score effects (the owner, 2026-10-21: "lets start with ranked score effects",
		-- one per rank from Gold, "if you lose the rank, you lose the explosion"): never on a banner;
		-- reaching that rank (or higher) in its Season earns it for good (Ranked.effectsFor; the owner,
		-- 2026-10-25: "keep the rewards permanently"). Season: the ranked season it's earned in ("rank
		-- rewards by season. make the effects for this season s1 bound and next time we will have new
		-- ones"): nobody earns it in another season, and the Locker shows this season's and the ones you
		-- earned; a new season adds its own rows
		{ Key = "RankGold", Name = "Gold Crest", Rarity = "Legendary", Ranked = "Gold", Season = 1 },
		{ Key = "RankPlatinum", Name = "Platinum Spires", Rarity = "Legendary", Ranked = "Platinum", Season = 1 },
		{ Key = "RankDiamond", Name = "Diamond Storm", Rarity = "Mythic", Ranked = "Diamond", Season = 1 },
		{ Key = "RankMighty", Name = "Mighty Wings", Rarity = "Mythic", Ranked = "Mighty", Season = 1 },
		{ Key = "RankAlmighty", Name = "Almighty Ascension", Rarity = "Mythic", Ranked = "Almighty", Season = 1 },
		-- the owner's two Halloween score effects (Limited; Base: drawn as it until their own are made)
		{ Key = "PumpkinBurst", Name = "Pumpkin Burst", Rarity = "Legendary", Limited = "Halloween" }, -- (VFXController pumpkinBurst)
		{ Key = "GhostSwarm", Name = "Ghost Swarm", Rarity = "Legendary", Limited = "Halloween" }, -- (VFXController ghostSwarm)
		-- a giant gravestone dropping on the spot with your epitaph (VFXController HW.graveDrop;
		-- Config.Grave)
		{ Key = "Grave", Name = "Rest in Peace", Rarity = "Legendary", Limited = "Halloween" },
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
		-- the Winter Pass's (the owner, 2026-11-16: "christmas emotes"): poses for the matchup intro
		-- and after a win (AnimationController's Intro_ poses), only from the pass
		{ Key = "ColdHands", Name = "Cold Hands", Rarity = "Rare", Limited = "Winter", Pass = true },
		{ Key = "SnowAngel", Name = "Snow Angel", Rarity = "Epic", Limited = "Winter", Pass = true },
		{ Key = "Reindeer", Name = "Reindeer Antlers", Rarity = "Epic", Limited = "Winter", Pass = true },
		{ Key = "HoHoHo", Name = "Ho Ho Ho", Rarity = "Legendary", Limited = "Winter", Pass = true },
		{ Key = "IceSkater", Name = "Ice Skater", Rarity = "Legendary", Limited = "Winter", Pass = true },
	},
	-- the ball's look (the owner: "add some ball skins... make your own balls. i want 6-10
	-- balls"): the server's skin, the whole rally (BallRenderer; the looks are in BallSkins).
	-- Pro Swirl and Tri Panel are the owner's "mikasa" and "molten" in our own colours and names
	-- (real brands' names and designs stay out of the game).
	Ball = {
		{ Key = "Classic", Name = "Classic", Rarity = "Common" },
		{ Key = "ProSwirl", Name = "Pro Swirl", Rarity = "Rare" },
		{ Key = "TriPanel", Name = "Tri Panel", Rarity = "Rare" },
		{ Key = "Beach", Name = "Beach Ball", Rarity = "Rare" },
		{ Key = "Eyeball", Name = "Eyeball", Rarity = "Epic" },
		{ Key = "Disco", Name = "Disco Ball", Rarity = "Epic" },
		{ Key = "Spiky", Name = "Spiky", Rarity = "Epic" },
		{ Key = "Lava", Name = "Lava Core", Rarity = "Legendary" },
		{ Key = "Galaxy", Name = "Galaxy", Rarity = "Legendary" },
		{ Key = "Planet", Name = "Ringed Planet", Rarity = "Legendary" },
		{ Key = "BigHead", Name = "Big Head", Rarity = "Mythic" },
		-- the owner's Halloween balls (assets/balls: PumpkinBallModel.fbx, WitchHatBall.fbx)
		{ Key = "Pumpkin", Name = "Pumpkin", Rarity = "Legendary", Limited = "Halloween" },
		{ Key = "WitchHat", Name = "Witch Hat", Rarity = "Epic", Limited = "Halloween" },
		-- the Winter collab's balls (Limited; assets/balls, tools/generate_winter_balls.py): the
		-- owner's "snowflake ball", a bauble, a peppermint sweet, a wrapped present, a snowball
		{ Key = "Snowball", Name = "Snowball", Rarity = "Rare", Limited = "Winter" },
		{ Key = "Gift", Name = "Present", Rarity = "Rare", Limited = "Winter" },
		{ Key = "Peppermint", Name = "Peppermint", Rarity = "Epic", Limited = "Winter" },
		{ Key = "Ornament", Name = "Ornament", Rarity = "Epic", Limited = "Winter" },
		{ Key = "Snowflake", Name = "Snowflake", Rarity = "Legendary", Limited = "Winter" },
		-- the Winter Pass's, only from it (BallSkins: no new maps, built from materials and the
		-- existing meshes): a gold bauble, a faceted ice crystal, a spiky icicle ball, a snow globe
		{ Key = "GoldBauble", Name = "Gold Bauble", Rarity = "Epic", Limited = "Winter", Pass = true },
		{ Key = "Crystal", Name = "Ice Crystal", Rarity = "Legendary", Limited = "Winter", Pass = true },
		{ Key = "IcicleBall", Name = "Icicle Ball", Rarity = "Legendary", Limited = "Winter", Pass = true },
		{ Key = "SnowGlobe", Name = "Snow Globe", Rarity = "Mythic", Limited = "Winter", Pass = true },
		-- the advent calendar's (BallSkins: their own maps, and pieces round them)
		{ Key = "Gingerbread", Name = "Gingerbread", Rarity = "Rare", Limited = "Winter", Advent = true },
		{ Key = "JingleBell", Name = "Jingle Bell", Rarity = "Epic", Limited = "Winter", Advent = true },
		{ Key = "Pudding", Name = "Christmas Pudding", Rarity = "Epic", Limited = "Winter", Advent = true },
		{ Key = "SnowmanHead", Name = "Snowman Head", Rarity = "Legendary", Limited = "Winter", Advent = true },
		{ Key = "Wreath", Name = "Wreath", Rarity = "Legendary", Limited = "Winter", Advent = true },
		{ Key = "NorthStar", Name = "North Star", Rarity = "Mythic", Limited = "Winter", Advent = true },
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
		Blurb = "Your own sounds when you score, spike, jump, serve, receive, set, block or feint. Use sound ids from the Creator Store, or your own uploads shared with Volleyball Rush.",
		VP = 3000,
		PassId = 2061424314, -- "Custom Sound Effects", 199 Robux
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
		PassId = 2058305668, -- "Custom Score Effect", 199 Robux
		Attribute = "ScoreImage",
		Types = { 1, 13 },
	},
	SoundSeconds = 4, -- a custom score sound is cut off after this
	ActionSeconds = 2, -- a custom touch or jump sound after this
	ImageSeconds = 1.6, -- how long the image holds before it fades
	SetCooldown = 3, -- seconds between changes to one id (each one is looked up)
	-- the cropper (the owner: "on custom audios, allow an audio cropper"): the part of a sound that
	-- plays, saved per slot as its start and length (SoundCrop); the length is at most the slot's
	-- cut-off above
	CropMin = 0.2, -- the shortest part you can keep
	CropMaxStart = 600, -- a start past this is refused (no audio on Roblox runs that long)
	CropStep = 0.05, -- one press of a nudge button
	CropCooldown = 1, -- seconds between saved crops for one slot
}

-- Player cards (the owner: "more diverse playercards, that are unlocked through achievements rather
-- than spinning. for example, a top 3 leaderboard playercard, or a playercard displaying your
-- winstreak, your wins, your spikes"): the card that slides in when you score, equipped in the
-- Locker. Each is unlocked for good when its Stat reaches Need ("rank": a place in the top Need of
-- any leaderboard), shows one of your numbers in big type (Show, with Label under it; "rank"
-- shows "#2" and the board), and has its own Look: Base (the plate), Sweep (the colour from the
-- left: "team" is the scorer's team, "rank" gold, silver or bronze), Accent (trim, chevrons, the
-- title), Edge (a border, or none), Pattern ("halftone", "stripes", "rays", "stars").
-- The Fresh Start (FreshStart; the owner, 2026-11-14, after players came back for the progress
-- given back and quit in a day, "theres nothing to grind for"): once, as each profile from before
-- it loads, its characters (and their upgrades, breakthroughs and mastery), the cosmetics won from
-- recruits and its used codes reset; Gold and VP are capped; it gets a Veteran card. Story, the
-- Halloween items, cards, ranked, clans and the rest stay. Enabled: on (the owner chose it); it
-- reaches players when the place is published. Developers are left alone (so the owner's Studio
-- playtests, which load the live saves, don't reset theirs; the testers' game makes everyone a
-- developer). Version: bump it to run a new one. RobuxPerLucky: the Robux a
-- player has spent comes back as a Lucky spin per this many (what it bought goes with the reset).
Config.FreshStart = {
	Enabled = true,
	Version = 1,
	GoldCap = 25000,
	VPCap = 5000,
	MatchesForElite = 100,
	Card = "OGVeteran",
	EliteCard = "OGElite",
	RobuxPerLucky = 100,
}

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
		-- the rank cards move too (the owner: "upgrade top 1 and top 3 because now they are lacking way
		-- too behind"), a step under Almighty: Top 3 glows in its medal (gold, silver, bronze) with a
		-- sweeping shine and sparkles; Number One adds the crown and a halo of turning rays
		{ Key = "Top3", Name = "Top 3", Stat = "rank", Need = 3, Show = "rank", Goal = "Reach the top 3 of any leaderboard",
			Look = { Base = Color3.fromRGB(24, 24, 30), Sweep = "rank", Accent = Color3.fromRGB(255, 255, 255), Edge = "rank", Pattern = "rays", Fx = { Glow = true, Shine = true, Sparkles = true } } },
		{ Key = "Number1", Name = "Number One", Stat = "rank", Need = 1, Show = "rank", Goal = "Reach #1 on any leaderboard",
			Look = { Base = Color3.fromRGB(28, 20, 2), Sweep = Color3.fromRGB(255, 200, 40), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 230, 120), Pattern = "stars", Fx = { Glow = true, Crest = true, Halo = true, Shine = true, Sparkles = true } } },
		-- the clans' board (the owner, 2026-10-21: "Leaderboard top clan gets cards similar to rank"):
		-- a member of a top 3 clan, and of the top clan
		{ Key = "ClanTop3", Name = "Top 3 Clan", Stat = "clanRank", Need = 3, Show = "clanRank", Goal = "Be in a top 3 clan",
			Look = { Base = Color3.fromRGB(14, 18, 34), Sweep = "rank", Accent = Color3.fromRGB(200, 230, 255), Edge = "rank", Pattern = "stripes", Fx = { Glow = true, Shine = true, Sparkles = true } } },
		{ Key = "ClanNumber1", Name = "Top Clan", Stat = "clanRank", Need = 1, Show = "clanRank", Goal = "Be in the number one clan",
			Look = { Base = Color3.fromRGB(10, 22, 40), Sweep = Color3.fromRGB(60, 170, 255), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(140, 210, 255), Pattern = "stars", Fx = { Glow = true, Crest = true, Halo = true, Shine = true, Sparkles = true } } },
		-- the owner: "another card displaying win/loss ratio... show wins, losses, and percent of
		-- wins": the share of matches won in big type, the wins and losses under it
		{ Key = "WinLoss", Name = "Win/Loss", Stat = "matches", Need = 20, Show = "winRate", Goal = "Play 20 matches",
			Look = { Base = Color3.fromRGB(6, 26, 22), Sweep = Color3.fromRGB(40, 220, 150), Accent = Color3.fromRGB(190, 255, 225), Edge = Color3.fromRGB(60, 230, 160), Pattern = "stripes" } },
		-- the owner: "a new card purple theme for Content creators... keep that text, but make it
		-- their own avatar spiking across the card": given from the admin panel (Grant), never
		-- earned; Big is drawn across the card and Avatar puts your own avatar, mid-spike, over it
		{ Key = "Creator", Name = "Content Creator", Stat = "grant", Grant = true, Goal = "Given to content creators",
			Look = { Base = Color3.fromRGB(26, 8, 48), Sweep = Color3.fromRGB(150, 50, 255), Accent = Color3.fromRGB(255, 110, 230), Edge = Color3.fromRGB(200, 120, 255), Pattern = "stripes", Big = "CONTENT\nCREATOR", Avatar = true } },
		-- the owner: "add a dev defeater card": win a full match against a team with a developer
		-- on it (Config.Developers)
		{ Key = "DevDefeater", Name = "Dev Defeater", Stat = "devWins", Need = 1, Goal = "Beat a developer's team in a match",
			Look = { Base = Color3.fromRGB(34, 4, 8), Sweep = Color3.fromRGB(235, 30, 50), Accent = Color3.fromRGB(255, 235, 235), Edge = Color3.fromRGB(255, 70, 80), Pattern = "rays", Big = "DEV\nDEFEATER" } },
		-- the owner: "since this guy is so high, i want to be able to give out a custom banner. Maybe
		-- like Almighty", then "a bit bland lets make it really special" (with a game's winged title
		-- banners for reference): the very best players, given from the admin panel (Give a player >
		-- Card). A crimson ribbon in gold with their own avatar mid-spike; its Fx add gold wings, a
		-- crown, turning rays, a sweeping shine, a breathing glow and sparkles (Gui.playerCard)
		-- (Key was "Almighty": renamed to take back every copy given by mistake, the owner: "wipe it
		-- from everyone and only give it back to one guy". A profile drops a card key it doesn't
		-- know when it loads, so the old copies are gone; never reuse "Almighty")
		-- (2026-10-21, the owner: "reuse the current one for the almighty rank"): earned by reaching
		-- Almighty in ranked (Config.Ranked); the players who had it were moved to True Almighty
		{ Key = "Almighty2", Name = "Almighty", Stat = "rankedBest", Need = 7, Goal = "Reach Almighty in ranked",
			Look = { Base = Color3.fromRGB(58, 4, 12), Sweep = Color3.fromRGB(205, 26, 42), Accent = Color3.fromRGB(255, 222, 120), Edge = Color3.fromRGB(255, 210, 80), Pattern = "rays", Big = "ALMIGHTY", Avatar = true, Fx = { Wings = true, Crest = true, Glow = true, Halo = true, Shine = true, Sparkles = true, WordShine = true } } },
		-- the ranked card (the owner, 2026-10-21: "add rank cards like this which update based on your
		-- current rank", after another game's ranked banner: RANKED, SEASON 19, W and L, the rank's
		-- emblem): unlocked by a ranked match; its colours and the badge on its edge follow your rank
		-- now ("ranked": Cards.look), and it shows the season with this season's wins and losses
		{ Key = "Ranked", Name = "Ranked", Stat = "rankedPlayed", Need = 1, Show = "ranked", Goal = "Play a ranked match",
			Look = { Base = Color3.fromRGB(16, 10, 20), Sweep = "ranked", Accent = "ranked", Edge = "ranked", Pattern = "rays", Fx = { RankBadge = true, Glow = true } } },
		-- the very best players, given from the admin panel (the owner, 2026-10-21: "replace the
		-- people who had almighty card with True Almighty and put some more special stuff on it"):
		-- black and gold, everything the Almighty card has, and an aura turning round its edge and
		-- embers rising through it
		{ Key = "TrueAlmighty", Name = "True Almighty", Stat = "grant", Grant = true, Goal = "Given to the very best players",
			Look = { Base = Color3.fromRGB(10, 6, 8), Sweep = Color3.fromRGB(255, 190, 40), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 236, 170), Pattern = "rays", Big = "TRUE\nALMIGHTY", Avatar = true, Fx = { Wings = true, Crest = true, Glow = true, Halo = true, Shine = true, Sparkles = true, WordShine = true, Aura = true, Embers = true } } },
		-- the VIP game pass's card (Config.Passes.VIP): given with the pass, never earned
		-- the Discord's card (Config.Discord): only from verifying your account in the Discord
		-- (named for the community, not Discord: everyone sees cards, and Roblox lets only some players
		-- see Discord named)
		{ Key = "Discord", Name = "Community Squad", Stat = "grant", Grant = true, Goal = "Verify your account in the Volleyball Rush community server",
			Look = { Base = Color3.fromRGB(14, 16, 44), Sweep = Color3.fromRGB(88, 101, 242), Accent = Color3.fromRGB(235, 238, 255), Edge = Color3.fromRGB(130, 142, 255), Pattern = "halftone", Big = "COMMUNITY\nSQUAD" } },
		-- the owner, 2026-10-17: "add a halloween 2026 card also pullable": on the Halloween banner (and
		-- by scout points), never earned
		{ Key = "Halloween2026", Name = "Halloween 2026", Stat = "grant", Grant = true, Goal = "From the Halloween 2026 banner",
			Look = { Base = Color3.fromRGB(22, 8, 30), Sweep = Color3.fromRGB(255, 120, 20), Accent = Color3.fromRGB(255, 190, 70), Edge = Color3.fromRGB(150, 70, 255), Pattern = "stars", Big = "HALLOWEEN\n2026", Fx = { Glow = true, Sparkles = true, Pumpkin = true } } },
		-- the Winter Pass's cards (the owner, 2026-11-16: "titles, cards"): a card worn is your title
		-- over your name in the matchup intro and on your card when you score (LineupController)
		{ Key = "SnowDay", Name = "Snow Day", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the Winter Pass",
			Look = { Base = Color3.fromRGB(10, 26, 60), Sweep = Color3.fromRGB(150, 210, 255), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(200, 230, 255), Pattern = "stars", Big = "SNOW\nDAY", Fx = { Snowfall = true } } },
		{ Key = "Winter2026", Name = "Winter 2026", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the Winter Pass",
			Look = { Base = Color3.fromRGB(8, 20, 48), Sweep = Color3.fromRGB(70, 150, 255), Accent = Color3.fromRGB(235, 247, 255), Edge = Color3.fromRGB(150, 220, 255), Pattern = "stars", Big = "WINTER\n2026", Fx = { Glow = true, Lights = true, Flake = true } } },
		{ Key = "Frostbitten", Name = "Frostbitten", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the Winter Pass",
			Look = { Base = Color3.fromRGB(14, 30, 44), Sweep = Color3.fromRGB(120, 230, 255), Accent = Color3.fromRGB(220, 250, 255), Edge = Color3.fromRGB(120, 230, 255), Pattern = "halftone", Big = "FROST\nBITTEN", Fx = { Icicles = true } } },
		{ Key = "JingleSpiker", Name = "Jingle Spiker", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the Winter Pass (premium)",
			Look = { Base = Color3.fromRGB(40, 6, 10), Sweep = Color3.fromRGB(220, 30, 46), Accent = Color3.fromRGB(255, 214, 90), Edge = Color3.fromRGB(255, 214, 90), Pattern = "stripes", Big = "JINGLE\nSPIKER", Fx = { Bells = true, Sparkles = true } } },
		{ Key = "Naughty", Name = "Naughty", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the Winter Pass (premium)",
			Look = { Base = Color3.fromRGB(16, 4, 6), Sweep = Color3.fromRGB(150, 10, 20), Accent = Color3.fromRGB(255, 90, 90), Edge = Color3.fromRGB(60, 60, 60), Pattern = "rays", Big = "NAUGHTY", Fx = { Coal = true } } },
		{ Key = "Nice", Name = "Nice", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the Winter Pass (premium)",
			Look = { Base = Color3.fromRGB(6, 30, 16), Sweep = Color3.fromRGB(40, 190, 90), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 214, 90), Pattern = "stars", Big = "NICE", Fx = { Gift = true, Sparkles = true } } },
		{ Key = "NorthernLights", Name = "Northern Lights", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the Winter Pass (premium)",
			Look = { Base = Color3.fromRGB(4, 12, 30), Sweep = Color3.fromRGB(80, 255, 190), Accent = Color3.fromRGB(190, 140, 255), Edge = Color3.fromRGB(100, 240, 220), Pattern = "rays", Big = "NORTHERN\nLIGHTS", Fx = { Glow = true, Aurora = true, Sparkles = true } } },
		{ Key = "SantasAce", Name = "Santa's Ace", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the Winter Pass (premium)",
			Look = { Base = Color3.fromRGB(44, 4, 10), Sweep = Color3.fromRGB(235, 40, 56), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 214, 90), Pattern = "rays", Big = "SANTA'S\nACE", Fx = { Glow = true, Shine = true, Sparkles = true, SantaHat = true } } },
		-- the advent calendar's cards (Config.Winter.Advent)
		{ Key = "CozySeason", Name = "Cozy Season", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the advent calendar",
			Look = { Base = Color3.fromRGB(40, 18, 10), Sweep = Color3.fromRGB(196, 92, 44), Accent = Color3.fromRGB(255, 226, 180), Edge = Color3.fromRGB(230, 150, 90), Pattern = "stripes", Big = "COZY\nSEASON", Fx = { Snowfall = true, Glow = true } } },
		{ Key = "SantasHelper", Name = "Santa's Helper", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the advent calendar",
			Look = { Base = Color3.fromRGB(8, 34, 16), Sweep = Color3.fromRGB(36, 160, 74), Accent = Color3.fromRGB(255, 90, 90), Edge = Color3.fromRGB(226, 40, 52), Pattern = "stripes", Big = "SANTA'S\nHELPER", Fx = { Bells = true } } },
		{ Key = "UnderMistletoe", Name = "Under the Mistletoe", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the advent calendar",
			Look = { Base = Color3.fromRGB(14, 30, 18), Sweep = Color3.fromRGB(90, 196, 110), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 110, 130), Pattern = "halftone", Big = "MISTLE\nTOE", Fx = { Glow = true, Sparkles = true } } },
		{ Key = "GingerCrew", Name = "Gingerbread Crew", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the advent calendar",
			Look = { Base = Color3.fromRGB(52, 26, 10), Sweep = Color3.fromRGB(190, 116, 56), Accent = Color3.fromRGB(255, 250, 240), Edge = Color3.fromRGB(255, 250, 240), Pattern = "stars", Big = "GINGER\nCREW", Fx = { Gift = true } } },
		{ Key = "Humbug", Name = "Bah Humbug", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the advent calendar",
			Look = { Base = Color3.fromRGB(10, 22, 8), Sweep = Color3.fromRGB(120, 176, 40), Accent = Color3.fromRGB(230, 255, 140), Edge = Color3.fromRGB(70, 70, 70), Pattern = "rays", Big = "BAH\nHUMBUG", Fx = { Coal = true } } },
		{ Key = "TwelveDays", Name = "Twelve Days", Stat = "grant", Grant = true, Limited = "Winter", Goal = "From the advent calendar",
			Look = { Base = Color3.fromRGB(10, 14, 46), Sweep = Color3.fromRGB(96, 120, 255), Accent = Color3.fromRGB(255, 214, 90), Edge = Color3.fromRGB(255, 214, 90), Pattern = "stars", Big = "TWELVE\nDAYS", Fx = { Lights = true, Flake = true } } },
		{ Key = "Advent2026", Name = "25 Days of Winter", Stat = "grant", Grant = true, Limited = "Winter", Goal = "Door 25 of the advent calendar",
			Look = { Base = Color3.fromRGB(30, 4, 8), Sweep = Color3.fromRGB(255, 196, 60), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 214, 90), Pattern = "rays", Big = "25 DAYS\nOF WINTER", Fx = { Glow = true, Shine = true, Sparkles = true, Lights = true, Aurora = true } } },
		-- the Winter leaderboard's (Config.Winter.Board): given when the event ends, by place
		{ Key = "WinterChampion", Name = "Winter Champion", Stat = "grant", Grant = true, Limited = "Winter", Goal = "First on the Winter leaderboard",
			Look = { Base = Color3.fromRGB(6, 16, 44), Sweep = Color3.fromRGB(255, 214, 90), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 214, 90), Pattern = "rays", Big = "WINTER\nCHAMPION", Fx = { Glow = true, Halo = true, Shine = true, Sparkles = true, Aurora = true } } },
		{ Key = "WinterTop10", Name = "Winter Top 10", Stat = "grant", Grant = true, Limited = "Winter", Goal = "Top 10 on the Winter leaderboard",
			Look = { Base = Color3.fromRGB(8, 20, 50), Sweep = Color3.fromRGB(200, 226, 255), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(200, 226, 255), Pattern = "rays", Big = "WINTER\nTOP 10", Fx = { Glow = true, Shine = true, Flake = true } } },
		{ Key = "WinterTop100", Name = "Winter Top 100", Stat = "grant", Grant = true, Limited = "Winter", Goal = "Top 100 on the Winter leaderboard",
			Look = { Base = Color3.fromRGB(10, 24, 56), Sweep = Color3.fromRGB(110, 170, 255), Accent = Color3.fromRGB(235, 247, 255), Edge = Color3.fromRGB(150, 200, 255), Pattern = "stars", Big = "WINTER\nTOP 100", Fx = { Snowfall = true } } },
		-- the Fresh Start's Veteran cards (Config.FreshStart; the owner, 2026-11-14: "add a veteran
		-- cosmetic", tiered by matches played), after The Spike's VETERAN / ELITE banners: given once
		-- to every profile from before it, never earned after
		{ Key = "OGVeteran", Name = "OG Veteran", Stat = "grant", Grant = true, Goal = "Played before the Fresh Start",
			Look = { Base = Color3.fromRGB(26, 8, 22), Sweep = Color3.fromRGB(235, 40, 150), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 90, 190), Pattern = "stripes", Big = "VETERAN", Fx = { Glow = true, Shine = true } } },
		{ Key = "OGElite", Name = "OG Elite", Stat = "grant", Grant = true, Goal = "Played 100 matches before the Fresh Start",
			Look = { Base = Color3.fromRGB(24, 4, 30), Sweep = Color3.fromRGB(190, 40, 255), Accent = Color3.fromRGB(255, 255, 255), Edge = Color3.fromRGB(255, 120, 230), Pattern = "rays", Big = "ELITE", Fx = { Glow = true, Shine = true, Sparkles = true, Crest = true } } },
		{ Key = "VIP", Name = "VIP", Stat = "grant", Grant = true, Goal = "Comes with the VIP game pass",
			Look = { Base = Color3.fromRGB(20, 14, 2), Sweep = Color3.fromRGB(255, 196, 40), Accent = Color3.fromRGB(255, 245, 200), Edge = Color3.fromRGB(255, 220, 100), Pattern = "stars", Big = "VIP" } },
		-- the owner: "a bug catcher card... put in the admin panel that i can give and take at any
		-- time. maybe have a bug net on the right hand side hanging off": given from the admin panel
		-- to players who report bugs; Fx.Net hangs a swaying bug net off the
		-- card's right edge (Gui.playerCard)
		{ Key = "BugCatcher", Name = "Bug Catcher", Stat = "grant", Grant = true, Goal = "Given for catching bugs in Volleyball Rush",
			Look = { Base = Color3.fromRGB(8, 28, 14), Sweep = Color3.fromRGB(110, 205, 60), Accent = Color3.fromRGB(255, 214, 80), Edge = Color3.fromRGB(140, 225, 80), Pattern = "halftone", Big = "BUG\nCATCHER", Fx = { Net = true } } },
	},
}

-- VP and Gold packs, sold as Developer Products. Create each product (Creator Hub > your
-- experience > Monetization > Developer Products) and paste its id here. A pack with Id 0 shows
-- as "soon"; in Studio it grants its VP or Gold for free so the flow can be tested.
Config.Shop = {
	-- (2026-10-22, the owner: "calculate all the deals because right now its just way too cheap": an S+
	-- through V Points, 250 recruits of pity at 50 VP, cost about 1,540 Robux in Vaults against about
	-- 3,500 in lucky spins; about 40% less VP a pack puts it near 2,630. Base prices on Creator Hub;
	-- regional pricing shows some players about 10% less)
	Packs = {
		{ Id = 3723421173, VP = 300, Name = "Pouch" }, -- 99 Robux (was 500 VP)
		{ Id = 3723421174, VP = 700, Name = "Bag" }, -- 199 (was 1,200)
		{ Id = 3723421176, VP = 1600, Name = "Crate" }, -- 399 (was 2,800)
		{ Id = 3723421179, VP = 3800, Name = "Vault" }, -- 799 (was 6,500)
	},
	-- Gold for stat upgrades: ten times the VP pack at the same step (a win pays 300 Gold, and
	-- maxing one S+ stat from where a recruit starts costs about 8,000)
	GoldPacks = {
		{ Id = 3723421181, Gold = 5000, Name = "Stack" }, -- 99 Robux
		{ Id = 3723421182, Gold = 12000, Name = "Satchel" }, -- 199
		{ Id = 3723421183, Gold = 28000, Name = "Chest" }, -- 399
		{ Id = 3723421184, Gold = 65000, Name = "Treasury" }, -- 799
	},
	ReceiptHistory = 50, -- purchase ids remembered per profile (duplicate receipts are ignored)
}

-- Lucky spins (the owner: "lucky spins like volleyball legends with enhanced rates, which you can
-- buy with robux"): one lucky spin is one pull on any banner with these rarity weights in place
-- of Rarity.Weights (no Commons; Legendary and Mythic several times likelier). Sold in Packs as
-- Developer Products like the VP packs (a pack with Id 0 shows "Soon", and Studio grants it free),
-- and they also come from codes, daily rewards, gifts and the admin panel.
Config.Lucky = {
	-- (the owner, 2026-10-17, after another game's lucky odds: Rare 49.75, Legendary 45, Godly 4.75,
	-- Secret 0.5; were Rare 48, Epic 34, Legendary 15, Mythic 3)
	Weights = { Common = 0, Rare = 49.75, Epic = 45, Legendary = 4.75, Mythic = 0.5 },
	-- the owner: "1 lucky spin 3 lucky spin 5 lucky 10 lucky spin" (Recruit's Lucky x1 and x10 buy
	-- the pack with that many when you have fewer)
	Packs = {
		-- prices raised 2026-10-04 (they outsold the VP packs: per Robux they were the cheaper way to
		-- an S+); the owner sets them on Creator Hub
		-- (2026-10-22: were 99 / 199 / 399 / 799, the 3-pack the cheapest a spin; set through Open Cloud to
		-- a ladder where each bigger pack is the better deal: 99 / 249 / 399 / 699, about 99 / 83 / 80 /
		-- 70 a spin. Base prices; regional pricing shows some players about 10% less)
		{ Id = 3723421185, Lucky = 1, Name = "Lucky Spin" }, -- 99 Robux
		{ Id = 3723421187, Lucky = 3, Name = "3 Lucky Spins" }, -- 249
		{ Id = 3723421188, Lucky = 5, Name = "5 Lucky Spins" }, -- 399
		{ Id = 3723421190, Lucky = 10, Name = "10 Lucky Spins" }, -- 699
	},
	-- traded for V Points in the Shop's Lucky tab (the owner, 2026-10-13: "exchange vp for lucky
	-- spins rate of 250 vpoints for 1"): VPCost each, in these amounts. (2026-10-22, the owner: "2500
	-- is only 300 robux while 10 lucky spins is 720": at 250 VP, Robux spent on V Points bought lucky
	-- spins at well under half their own price. 750 puts it above the Robux packs (about 600 VP a
	-- spin is even), so buying the spins is the better deal and V Points from play still reach them)
	VPCost = 750,
	Trade = { 1, 5, 10 },
}

-- Gold for V Points (the owner, 2026-10-21: "50 gold for 1 vp"), in the Shop's Trade tab: these
-- amounts of VP, GoldPerVP Gold each
Config.Exchange = {
	GoldPerVP = 150, -- (was 50; the owner, 2026-10-22: "buff all the conversion rates its all just too cheap")
	Amounts = { 100, 500, 1000, 2500 },
}

-- Boosts (the owner: "developer products for 2x vpoints on timers"): a pack doubles the VP you
-- earn (matches and their MVP bonus, tournament prizes, daily rewards: ProfileService.vpMult; never
-- codes, gifts or packs) for its time, counted in real time from when you get it. Another
-- adds its time on top, up to MaxHold. It multiplies with the admin panel's 2x VP event. Sold as
-- Developer Products (a pack with Id 0 shows "Soon", and Studio grants it free), and can be gifted.
Config.Boosts = {
	Multiplier = 2,
	MaxHold = 24 * 3600, -- the most time a boost can hold (seconds)
	-- 2x VP for Gold or V Points (the owner, 2026-10-21: "make x2 vp purchasable with coins or vp so
	-- coins have a use for late game"), in the Shop's Trade tab: each length its price in each
	-- (2026-10-22, the owner: "buff all the conversion rates its all just too cheap": about three times
	-- what they were, the VP near the Robux packs' worth, the Gold at Config.Exchange's rate)
	CurrencyPacks = {
		{ BoostVP = 15 * 60, Gold = 36000, VP = 240 },
		{ BoostVP = 30 * 60, Gold = 66000, VP = 440 },
		{ BoostVP = 60 * 60, Gold = 120000, VP = 800 },
		{ BoostVP = 3 * 3600, Gold = 330000, VP = 2200 },
	},
	Packs = {
		{ Id = 3723421192, BoostVP = 15 * 60, Name = "2x VP, 15 minutes" }, -- 49 Robux
		{ Id = 3723421193, BoostVP = 30 * 60, Name = "2x VP, 30 minutes" }, -- 79
		{ Id = 3723421195, BoostVP = 60 * 60, Name = "2x VP, 1 hour" }, -- 129
		{ Id = 3723421198, BoostVP = 3 * 3600, Name = "2x VP, 3 hours" }, -- 299
	},
	-- 2x Luck for yourself (the owner asked for "the 2x luck developer products"): for its time your
	-- usual recruits on the Characters banner are twice as lucky (Config.Spins.LuckEvent: A- and
	-- up twice as likely), and with the admin panel's 2x Luck on too they stack: 4x. Id 0 until the
	-- product exists (free in Studio); suggested names and prices on each line.
	-- the reward for watching a rewarded video ad (the owner, 2026-11-14, after Draw a Farm's: "do
	-- that same rewarded ad system for volleyball rush too"): Roblox grants this product free when
	-- the ad finishes, through ProcessReceipt like a purchase. The Shop's "Watch an ad" button shows
	-- only when Roblox has an ad ready; AdGap: seconds between a player's ads.
	AdPacks = {
		{ Id = 3731103417, BoostLuck = 10 * 60, Name = "Ad reward: 2x Luck, 10 minutes" },
	},
	AdGap = 60,
	LuckPacks = {
		{ Id = 3723421200, BoostLuck = 15 * 60, Name = "2x Luck, 15 minutes" }, -- 79 Robux
		{ Id = 3723421203, BoostLuck = 30 * 60, Name = "2x Luck, 30 minutes" }, -- 129
		{ Id = 3723421205, BoostLuck = 60 * 60, Name = "2x Luck, 1 hour" }, -- 199
		{ Id = 3723421207, BoostLuck = 3 * 3600, Name = "2x Luck, 3 hours" }, -- 449
	},
	-- stronger luck for yourself (the owner, 2026-10-16: "Add 4x 6x 8x and 16x luck to admin panel
	-- and to the shop and accomadte prices accordingly"): each tier its own Developer Products in the
	-- same four lengths, priced up with what they give (an S+ 0.5% x N, Spins.luckWeights). Your luck
	-- is your strongest boost running (they don't multiply each other; each keeps its own clock),
	-- times the admin panel's event and the Lucky pass. Created through Open Cloud on 2026-10-16
	-- (prices on each line; icons in assets/products).
	LuckTiers = { 2, 4, 6, 8, 16 },
	LuckPacks4 = {
		{ Id = 3723421215, BoostLuck = 15 * 60, LuckMul = 4, Name = "4x Luck, 15 minutes" }, -- 149 Robux
		{ Id = 3723421221, BoostLuck = 30 * 60, LuckMul = 4, Name = "4x Luck, 30 minutes" }, -- 249 Robux
		{ Id = 3723421230, BoostLuck = 60 * 60, LuckMul = 4, Name = "4x Luck, 1 hour" }, -- 379 Robux
		{ Id = 3723421241, BoostLuck = 3 * 3600, LuckMul = 4, Name = "4x Luck, 3 hours" }, -- 849 Robux
	},
	LuckPacks6 = {
		{ Id = 3723421255, BoostLuck = 15 * 60, LuckMul = 6, Name = "6x Luck, 15 minutes" }, -- 219 Robux
		{ Id = 3723421258, BoostLuck = 30 * 60, LuckMul = 6, Name = "6x Luck, 30 minutes" }, -- 349 Robux
		{ Id = 3723421268, BoostLuck = 60 * 60, LuckMul = 6, Name = "6x Luck, 1 hour" }, -- 549 Robux
		{ Id = 3723421274, BoostLuck = 3 * 3600, LuckMul = 6, Name = "6x Luck, 3 hours" }, -- 1249 Robux
	},
	LuckPacks8 = {
		{ Id = 3723421285, BoostLuck = 15 * 60, LuckMul = 8, Name = "8x Luck, 15 minutes" }, -- 279 Robux
		{ Id = 3723421291, BoostLuck = 30 * 60, LuckMul = 8, Name = "8x Luck, 30 minutes" }, -- 449 Robux
		{ Id = 3723421296, BoostLuck = 60 * 60, LuckMul = 8, Name = "8x Luck, 1 hour" }, -- 699 Robux
		{ Id = 3723421301, BoostLuck = 3 * 3600, LuckMul = 8, Name = "8x Luck, 3 hours" }, -- 1599 Robux
	},
	LuckPacks16 = {
		{ Id = 3723421302, BoostLuck = 15 * 60, LuckMul = 16, Name = "16x Luck, 15 minutes" }, -- 499 Robux
		{ Id = 3723421310, BoostLuck = 30 * 60, LuckMul = 16, Name = "16x Luck, 30 minutes" }, -- 799 Robux
		{ Id = 3723421320, BoostLuck = 60 * 60, LuckMul = 16, Name = "16x Luck, 1 hour" }, -- 1249 Robux
		{ Id = 3723421326, BoostLuck = 3 * 3600, LuckMul = 16, Name = "16x Luck, 3 hours" }, -- 2799 Robux
	},
}

-- Bundles (the owner: "make gamepasses and developer products that people actually will buy...
-- such as a starter pack bundle"): one Developer Product giving several things at once, worth
-- more than its packs bought one by one (Value: what those packs cost, shown on its card). Once:
-- sold once per player (the Shop hides it after; a receipt that still arrives is granted, it was
-- paid), and not giftable. Id 0 shows "Soon" (free in Studio).
Config.Bundles = {
	Packs = {
		{ Id = 3723421328, Name = "Starter Pack", Once = true, VP = 1500, Gold = 15000, Lucky = 3, BoostLuck = 30 * 60, Value = 800 }, -- 149 Robux
		{ Id = 3723421329, Name = "Pro Bundle", VP = 4000, Gold = 40000, Lucky = 5, BoostVP = 60 * 60, Value = 1400 }, -- 799
	},
}

-- The Shop's Specials (the owner, 2026-10-29: "make some more robux options too. new game, new
-- revenue"): Developer Products like the packs (made through Open Cloud, tools/specials.results.json), with
-- breakthrough Fragments (a group -> count) and STickets (selection tickets: any S player you don't
-- own, Config.Retired.TicketTier). Label: the card's big word.
Config.Specials = {
	Packs = {
		{ Id = 3723772259, Name = "Relaunch Pack", Label = "Relaunch", VP = 2500, Gold = 25000, Lucky = 5, Fragments = { S = 1 } }, -- 399 Robux: the fresh start's welcome deal
		{ Id = 3723772262, Name = "Selection Ticket", Label = "S Pick", STickets = 1 }, -- 599: any S player you don't own
		{ Id = 3723772323, Name = "Breakthrough Pack", Label = "Fragments", VP = 500, Fragments = { ["S+"] = 2, S = 3 } }, -- 499
		{ Id = 3723772327, Name = "Mega Bundle", Label = "Mega", VP = 12000, Gold = 120000, Lucky = 20, BoostVP = 2 * 60 * 60, Fragments = { ["S+"] = 2 } }, -- 1,999
	},
}

-- Game passes, owned for good (Creator Hub > your experience > Monetization > Passes; 0 while
-- there isn't one). VP multiplies the VP you earn (ProfileService.vpMult: matches and their MVP
-- bonus, tournament prizes, daily rewards) and Gold what matches pay, and they multiply with
-- each other, the boosts and the admin panel's events; Luck multiplies the Characters banner's
-- luck like 2x Luck does (Spins.luckWeights), stacking with both. Card: the player card the pass
-- gives (a Grant card); Tag: the chat tag its owners get. Developers own every pass.
Config.Passes = {
	Order = { "VIP", "DoubleVP", "Lucky", "DoubleEvent" },
	-- the original Spike Rush's passes (the stolen game's, 2026-10-26): owning one counts as owning
	-- its pass here once its player presses Restore in the Shop (ProfileService "restorePasses";
	-- the owner, 2026-10-29: "transfer over old spike:rush purchases to here")
	Old = { VIP = 2021828280, DoubleVP = 2021552278, Lucky = 2022146273 },
	OldPerks = { ScoreSound = 1998447396, ScoreImage = 2001902276 },
	VIP = { PassId = 2061244340, Name = "VIP", Blurb = "1.5x the V Points you earn and the Gold matches pay, a gold VIP chat tag and the VIP player card.", VP = 1.5, Gold = 1.5, Card = "VIP", Tag = "VIP" }, -- 349 Robux
	DoubleVP = { PassId = 2061928252, Name = "2x V Points", Blurb = "Matches, tournaments and daily rewards pay double V Points, for good. Stacks with VIP, boosts and events.", VP = 2 }, -- 499
	Lucky = { PassId = 2061598293, Name = "Lucky", Blurb = "Your Characters recruits are 1.5x luckier, for good. Stacks with 2x Luck.", Luck = 1.5 }, -- 399
	-- the event currency's (Config.EventCurrency, the owner, 2026-10-31: "make gamepasses for this
	-- as well"): every event's, not only Halloween's Candy
	DoubleEvent = { PassId = 2062597271, Name = "2x Event Currency", Blurb = "Event matches pay double the event currency, for good: Candy now, and every event after. Stacks with events.", Cur = 2 }, -- 399
	-- every pass giftable (the owner, 2026-10-21: "Make all the gamepasses giftable"): Roblox can't
	-- gift a game pass, so each has a gift Developer Product at the pass's price (made through Open
	-- Cloud) that gives it inside the game (a profile's giftedPasses, or perks for the perk passes)
	GiftPacks = {
		{ Id = 3723421335, Passes = { "VIP" }, Name = "VIP" }, -- 349 Robux
		{ Id = 3723421345, Passes = { "DoubleVP" }, Name = "2x V Points" }, -- 499
		{ Id = 3723421348, Passes = { "Lucky" }, Name = "Lucky" }, -- 399
		{ Id = 3723421354, Perks = { "ScoreSound" }, Name = "Custom sound effects" }, -- 199
		{ Id = 3723421361, Perks = { "ScoreImage" }, Name = "Custom score effect" }, -- 199
		{ Id = 3725008909, Passes = { "DoubleEvent" }, Name = "2x Event Currency" }, -- 399
	},
}

-- The subscriptions (the owner, 2026-10-30: "lets make a subscription for more vp and more luck",
-- then made two: "first one is 2x luck 2nd is 2x vp"): Roblox experience subscriptions, monthly,
-- made in Creator Hub (Monetization > Subscriptions; no Open Cloud API makes one). While a
-- player's is active it multiplies like a game pass (Economy.passMult, as the pass "Sub" .. key),
-- stacking with the other, the passes, boosts and events: VP what earned V Points pay
-- (ProfileService.vpMult), Luck the Characters banner's luck. Id: the subscription's id from
-- Creator Hub ("EXP-..."); "" hides its card in the Shop.
Config.Subscriptions = {
	Order = { "Luck", "VP" },
	Luck = { Id = "EXP-2412803354733445712", Name = "2x Luck", Blurb = "2x luck on every Characters recruit while you're subscribed. Stacks with your passes, boosts and events.", Luck = 2 },
	VP = { Id = "EXP-5104546357994193480", Name = "2x V Points", Blurb = "2x the V Points matches, tournaments and daily rewards pay while you're subscribed. Stacks with the rest.", VP = 2 },
}

-- Codes (the owner: "add a codes system... first code should be release, you decide the value
-- they get"): typed in Home's Codes window, any case, spaces ignored; each works once per player.
-- A code pays any of VP, Gold, Lucky (spins) and Chars (roster ids). Until: the unix time it
-- stops working (none: it never does). Keys are the code in lower case, letters and digits only.
-- The Discord (the owner: "lets start adding an incentive to join the discord", then, from
-- BedWars: "they give you a code and you tell a bot in discord that code to verify your
-- account"). The Codes window, for players Roblox lets see a Discord link (PolicyService's
-- AllowedExternalLinkReferences; never under-13s), shows the invite as copyable text and the
-- player's own verification code. In the Discord they type /discordverify CODE: the bot
-- (tools/discord-verify, a Cloudflare Worker) checks the code in the Store data store
-- ("code_<CODE>" -> { userId, name }, written by the game), and writes "done_<CODE>" (and
-- "discord_<their Discord id>", so one Discord account verifies one Roblox account). Verify in the
-- game reads "done_<CODE>" and pays Reward once, the Discord Squad card with it (nothing else gives
-- that card). Invite: the link without https://; empty hides the strip.
Config.Discord = {
	Invite = "discord.gg/T6N3uw5ghA",
	Store = "DiscordVerify",
	CodeLength = 7,
	CheckGap = 4, -- seconds between a player's Verify checks
	Reward = { VP = 750, Gold = 7500, Lucky = 3, Cards = { "Discord" } },
}

Config.Codes = {
	-- the owner, 2026-11-14, with the Fresh Start (Config.FreshStart): "cut all the other codes.
	-- leave 1 code, freshstart. you decide the reward". Everyone's used codes reset with it, so each
	-- player can take this once. The size is Claude's: Release's, a strong first team without
	-- skipping the grind (about a third of the way to the Fresh Start's caps). Typed any case and
	-- spacing ("Fresh Start" works).
	freshstart = { VP = 1500, Gold = 15000, Lucky = 5, BoostLuck = 30 * 60 },
	-- the Winter collab's (the owner, 2026-11-18: "3 codes is fine but dont go overboard because the
	-- reset happened due to shitty economy"): Snowflakes only, a few recruits' worth, working only
	-- while the event runs (Event: Winter.active)
	jaja = { EventCur = { Snow = 100 }, Event = "Winter" },
	volleyballevolved = { EventCur = { Snow = 100 }, Event = "Winter" },
	merrychristmas = { EventCur = { Snow = 150 }, Event = "Winter" },
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
-- you earn (matches, tournaments, daily rewards: ProfileService.vpMult) or the Gold a match pays
-- (Multiplier) for one of Durations (minutes), in every server; an
-- announcement shows to every player in every server; and Give sends VP, Gold, lucky spins and
-- characters to anyone by username (online in any server at once, otherwise on their next join).
-- The event currency (the owner, 2026-10-31: "add an event currency to the admin panel. this can
-- also be boosted, and can be gifted. dont restrict it to just candy, as christmas update will
-- also have an event currency"): whichever event is on pays its own currency, and Active names
-- it. That one is what the admin panel gives and boosts (the "Cur" event), and what the 2x Event
-- Currency pass doubles. Earned currency (event matches) is multiplied; gifts, refunds and shop
-- buys aren't. Candy is kept where Halloween keeps it (the profile's halloween.candy); any other
-- currency in the profile's eventCur, by key. For Christmas: add its row and set Active to it.
-- (Snowflakes have their row: they're kept in the profile's winter table, Winter.lua. Active stays
-- Candy until the Winter event goes out: set it to "Snow" with Config.Winter.Enabled.)
Config.EventCurrency = {
	Active = "Snow", -- (the Winter Rally's Snowflakes since 2026-11-21; Candy was Halloween's)
	Order = { "Candy", "Snow" },
	Candy = { Name = "Candy", Event = "Halloween", Color = Color3.fromRGB(255, 130, 30) },
	Snow = { Name = "Snowflakes", Event = "Winter", Color = Color3.fromRGB(150, 220, 255) },
	Max = 10000000, -- the most anyone holds of one
}

Config.Admin = {
	Durations = { 5, 10, 15, 20, 30 },
	-- 2x VP doubles earned VP and 2x Gold what matches pay; 2x Luck (the owner: "add 2x luck, similar to the
	-- 2x gold and vp... this should lower the odds of getting the d's and the c's and double the
	-- odds of getting better characters. from A- to above") changes recruits on the Characters
	-- banner: Config.Spins.LuckEvent
	-- Cur: the event currency (Config.EventCurrency.Active), what event matches pay
	Events = { "VP", "Gold", "Luck", "Cur" },
	-- each event's strength, picked as it starts (the owner, 2026-10-16: "Add 4x 6x 8x and 16x
	-- luck to admin panel"; 2026-10-30: "make gold and vp gain also go up to 16x same as the luck")
	EventMuls = { 2, 4, 6, 8, 16 },
	-- the Luck event goes further, for admin abuse (the owner, 2026-11-07: "add up to 128x luck", "admin abuse
	-- only"): the Shop's own luck still tops out at 16x (Config.Boosts.LuckTiers)
	LuckMuls = { 2, 4, 6, 8, 16, 32, 64, 128 },
	EventNames = { VP = "V Points", Gold = "Gold", Luck = "Luck", Cur = Config.EventCurrency[Config.EventCurrency.Active].Name },
	EventLines = { VP = "Matches, tournaments and daily rewards pay that many times the V Points.", Gold = "Every match pays that many times the Gold.", Luck = "Recruits are that many times as likely to be A- or better, and it multiplies with your own Luck.", Cur = "Event matches pay that many times the " .. Config.EventCurrency[Config.EventCurrency.Active].Name .. "." },
	Multiplier = 2, -- an event's strength when none was picked
	AnnounceMax = 200, -- characters
	AnnounceSeconds = 10, -- how long an announcement shows
	GiveMax = { VP = 1000000, Gold = 10000000, Lucky = 1000, Fragments = 1000, STickets = 20, Cur = 1000000 },
	LiveStore = "SpikeRushLive_v1", -- the running events (DataStore), for servers that start later
	MailStore = "SpikeRushMail_v1", -- gifts waiting for their player (DataStore)
	-- who was given each give-only card from the admin panel (DataStore, a key per card): the
	-- owner: "i also want a list of those who own it, so i can easily take it away"
	CardOwnersStore = "SpikeRushCardOwners_v1",
	PollInterval = 60, -- seconds between a server's reads of the events and of its players' mail
	-- the admin whitelist (the owner, 2026-10-16: "add a whitelist to the admin panel that only i
	-- can access"): the players the game's owner lets into the panel (all of it but the list, which
	-- only the owner sees and changes); one DataStore key, read again each PollInterval
	WhitelistStore = "SpikeRushAdmins_v1",
	WhitelistMax = 50,
	-- the gift tracker (the owner, 2026-10-31: "add gift tracker next to admin names"): every Give
	-- and Give everyone online from the panel, by who sent it (one DataStore key, written once a
	-- gift, read when the owner opens the whitelist): a count, totals, and the latest GiftLogKeep
	GiftLogStore = "SpikeRushAdminGifts_v1",
	GiftLogKeep = 25,
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
	-- the owner: "make this S+ red" (S+ is Mythic, whose pulls already glow red)
	["S+"] = Color3.fromRGB(255, 55, 65),
}

-- Abilities come with a character (the Roster module). S+ wing spikers: Thunder Spiker, Azure Dragon or Feral Leap.
-- S characters have their role's ability. Everyone else has none.
Config.Abilities = {
	-- Double Swing (the owner: "yejun who has a double swing ability, with enhanced power on the
	-- second swing", then "remove the one swing limitation but keep the double swing buff on
	-- yejun"): anyone may swing again in a jump, and his second swing hits SecondBoost harder.
	-- Passives are shown as rows of their own on the Players screen.
	-- (the owner, 2026-10-12: "we should buff up yejun hes getting powercrept. maybe another ability
	-- for him too", picking an active and a passive: Storm Call and Static Charge)
	Thunder = {
		Name = "Thunder Spiker",
		Tier = "S+",
		Active = true, -- Storm Call (Q)
		Blurb = "Hit the ball above 4.00 m and it becomes a lightning spike. Press Q for Storm Call: for 10 s every spike is lightning at full strength, at any height.",
		Color = Color3.fromRGB(255, 225, 77),
		SecondBoost = 0.18,
		-- Storm Call: while it's on every spike (and jump serve) is a thunder spike as if met at the
		-- very top of the range, and StormBoost harder on top: maxed and clean about 220 km/h, a
		-- second swing about 260
		Duration = 10,
		Cooldown = 20,
		StormBoost = 0.1,
		-- Static Charge: each of his thunder spikes in a rally charges the next ones StaticPer more,
		-- up to StaticMax; the rally's end clears it
		StaticPer = 0.06,
		StaticMax = 3,
		-- High Strike (the owner: "yejun is just jumping too low. can we buff him"): his spike and
		-- serve jumps go this much higher (17.6 studs maxed -> about 22, with Hayul and Laith); his
		-- hitting point on the card, and so Thunder, stay where they were
		LeapMul = 1.25,
		-- His impact frames hold the play (the owner, 2026-10-29: "on yejuns impact frame kind of
		-- pause the gameplay a bit like taeho just not as exaggerated", "i mean not as long"): a thunder
		-- spike's ball waits on his hand this long while he hangs in the air under the frame (Jaeil's
		-- Zero Point holds 0.6 s, any other big hit 0.13); a second swing's (Jaeil's frame in yellow:
		-- the court dark around him for SwingDark, then his silhouette) a little longer
		Freeze = 0.22,
		SwingFreeze = 0.34,
		SwingDark = 0.1,
		Passives = {
			{ Name = "Double Swing", Blurb = "Swing again in the same jump: the second swing (only the second) hits 18% harder." },
			{ Name = "Storm Call", Blurb = "Press Q: for 10 s every spike is a full-strength lightning spike, at any height, 10% harder still." },
			{ Name = "Static Charge", Blurb = "Each lightning spike in a rally charges your next ones 6% harder (up to 3 times). Resets when the rally ends." },
			{ Name = "High Strike", Blurb = "Your spike jumps go 25% higher." },
		},
	},
	Azure = {
		Name = "Azure Dragon",
		Tier = "S+",
		Blurb = "Hold Spike in the air to gather energy under low gravity. A full bar hits hardest and pierces blocks. Hold too long and it flies out.",
		Kind = "Hold Spike in the air", -- how it's used (the menus; Active abilities say Q)
		Color = Color3.fromRGB(57, 213, 255),
		-- Dragon Surge (the owner: Mujin "feels lacking compared to the other s+"; a full bar was
		-- about 201 km/h maxed, under Valen's 204 / 235 and YeJun's 236): a quicker bar, more room
		-- before it overcharges, about 225 km/h full, and a full bar costs the digger more stamina
		ChargeTime = 0.6, -- seconds of holding to fill the bar (was 0.8)
		-- (2026-10-12, the owner: "buff the others": every S+'s dependable best into 220-240)
		OverchargeGrace = 0.6, -- holding past full for this long overcharges (was 0.28, then 0.45)
		GravityCancel = 0.85, -- a slow, floating fall while gathering energy (on the way down only)
		AirSpeedBonus = 1.25,
		GaugeRechargeTime = 3.0, -- gauge refills on the ground
		MaxBoost = 0.66, -- full energy multiplies spike speed by 1 + this (was 0.44, then 0.55): about 232 maxed
		PierceAt = 0.97,
		FullDrainMul = 1.3, -- digging a full-bar spike costs this much more stamina
	},
	-- The owner: "hold his jump to charge it and the longer he charges it the further it goes",
	-- "the highest attack character in the game". Hold Spike (Jump on touch) on the ground: a
	-- violet arc fills over ChargeTime while he runs faster; let go and he leaps, carried along the
	-- court by the charge. The gauge he took off with powers the spike, or the jump serve (serving,
	-- the press that tosses the ball starts the charge, and so does one after the toss).
	Feral = {
		Name = "Feral Leap",
		Tier = "S+",
		Active = true, -- Bloodlust (Q)
		ActiveName = "Bloodlust",
		Blurb = "Hold Jump on the ground to charge, let go to leap: the longer the charge, the further you fly and the harder you hit. A full charge at the net breaks blocks with less Attack; your first of the match hits harder still. Press Q for Bloodlust: your bar burns red and the charge races past full, to 165%, for one charged hit (10 s at most).",
		Kind = "Hold Jump on the ground",
		AiNote = "Your AI charges it in the air on its own, at 85% Attack",
		Color = Color3.fromRGB(165, 80, 255),
		ChargeTime = 0.6, -- seconds of holding to fill the gauge (the owner: "buff charging times"; was 1)
		TapTime = 0.15, -- let go sooner and it's the usual run-up jump
		RunBoost = 0.45, -- run speed while charging: x (1 + this x the gauge)
		CarryMax = 3.4 * M, -- a full leap carries him this fast (studs/s) the way he leapt, all flight
		MaxBoost = 0.5, -- spike and jump serve speed x (1 + this x gauge ^ 1.2) (was 0.4; "buff the others": a full leap about 220 maxed)
		FullAt = 0.97, -- the gauge counts as full from here
		FirstBoost = 0.15, -- his first full-gauge spike or jump serve of the match: x (1 + this) on top
		FirstFreeze = 1.0, -- and it holds on the impact for the First Impact cinematic (shared/FirstImpact: a second; was a 0.3 s cut-in)
		BreakKeep = 0.85, -- a spike that smashes through a block keeps this much of its speed
		ReachMul = 1.15, -- a wider spike reach
		LeapReachMul = 1.4, -- and wider still on the swing off a charged leap (the owner: "extend dante's swinging hitbox after he leaps")
		-- Bloodlust (the owner, 2026-10-15: "lets add a buff to dante. he now has an active ability he
		-- can pop to overcharge to maybe around 160 170% bar ... and it turns his ball red"): for
		-- Duration the charge keeps filling past full, OverTime more to OverMax (HitLogic.feralGauge),
		-- and past full the boost grows with the bar itself (x (1 + MaxBoost x gauge): a full 165%
		-- about 268 km/h maxed, against 220 for a full leap). His charge bar burns red while it's on
		-- (the owner: "i meant that his bar turns red"; the ball keeps the Feral comet).
		-- One hit (the owner, 2026-10-16: "after one hit, the ability is over"): the spike or jump
		-- serve his leap's charge powers ends it (meta.bloodlustSpent), else Duration does. The second
		-- bar fills fast ("make his 2nd bar fill significantly quicker"; OverTime was 0.45).
		Duration = 10,
		Cooldown = 22,
		OverMax = 1.65,
		OverTime = 0.2,
		BloodColor = Color3.fromRGB(255, 36, 48),
		Passives = {
			{ Name = "Long Reach", Blurb = "Off a charged leap, your swing reaches much further than anyone's." },
			{ Name = "Bloodlust", Blurb = "Press Q: your charge bar burns red and races past full, up to 165%, for one charged hit (10 s at most). An overcharged leap hits far harder." },
		},
		TossReachMul = 1.6, -- his forward serve toss comes down this much further in front
		-- played by the AI (a bot, or a stand-in for an idle player): the gauge fills in the air on
		-- its own over AutoChargeTime, Attack is AutoAttackMul of the player's, and the gauge's and
		-- first strike's speed bonuses are AutoBoostMul of a player's
		AutoChargeTime = 1.0,
		AutoAttackMul = 0.85,
		AutoBoostMul = 0.75,
	},
	-- Laith (the owner: a new character "based off lucas from the spike", pasting his kit: a skill
	-- that raises every stat while it's on and lowers them after by how many times it was used, up
	-- to 12, cleared by a timeout or a substitution; a dive mid-air during the spike, the faster the
	-- descent the more power; a chance for a spike to burst, +13% power and +1 spin; a much further
	-- serve toss like Valen's; and a path he travels along when he jumps). The names are ours
	-- (CLAUDE.md): Corona is the stat flare, Sundive the dive, Zenith the burst, Long Toss the toss.
	-- Sundive: Spike pressed in the air while the ball is below his reach sends him down at it on a
	-- straight path (gravity off, homing on where the ball will be), and the spike gets up to
	-- DiveBoost more power the faster he's falling when he meets it (input.vy).
	Corona = {
		Name = "Corona",
		Tier = "S+",
		Active = true,
		Blurb = "Press Q: every stat flares up 15% for 10 s and your jump becomes a Sun Leap, far higher. After each use your stats sit 1% lower while it's off (up to 12 uses); a timeout clears that. In the air, Spike with the ball below you to dive onto it: the further you drop, the harder the spike. Your jump serve always gets some of that dive power.",
		Color = Color3.fromRGB(255, 178, 46),
		Duration = 10,
		Cooldown = 17, -- (was 20: the community's vote, 2026-11-18, "buff laith")
		Boost = 0.15, -- every stat x (1 + this) while it's on
		-- (the owner: "why is laith's power just so low": his plain spike was anyone's, a full dive
		-- needed a long drop the lower Sun Leap rarely gives, and Corona's penalty grew all match)
		PenaltyPer = 0.01, -- every stat x (1 - this x uses) while it's off (was 0.015)
		SpikeBoost = 0.18, -- (0.14 until the community voted to buff him, 2026-11-18) Sunfire: every spike (and jump serve) of his this much harder (0.12, 0.18, 0.28, then halved: the owner, "lets just half the buff you gave laith")
		MaxStacks = 12,
		-- Sundive
		-- (the owner, watching it: "he should be way way faster", "a long path like this" with a
		-- picture of a long white swoop from high up onto the ball, "he should practically be
		-- teleporting with how fast it is"; then a video of Lucas: from behind the end line he leaps
		-- far higher than anyone, hangs with a see-through orange band to the ball, and in about 0.1 s he's at
		-- the ball by the net, an orange ribbon behind him and a sun bursting at 252 km/h, about 1.7
		-- times his plain spike). The path is all but straight (HitLogic.diveControl), travelled
		-- almost at once; he hangs where he meets it for the swing. Its power is how far he drops.
		DiveWindow = 0.9, -- the ball has to be reachable within this long (seconds)
		DiveMinDrop = 0.6, -- and his hand at least this far above where he'll meet it (studs)
		DiveMaxDist = 12 * M, -- the longest path (studs, start to end): the back row to the net
		DiveArc = 0.06, -- how far the path bows up, as a share of its length
		DiveSpeedMax = 400, -- the fastest he travels along it (studs/s): practically a teleport
		DiveHold = 0.15, -- he hangs at the meeting point this long for the swing
		-- (the owner: "i still think the dash should be faster"): the dash itself takes this long at
		-- most; until it's time to go he hangs where he pressed it, the band out to the ball, then
		-- zips onto it as it arrives (the video's hang, then about a tenth of a second)
		DiveDashTime = 0.06,
		DiveFullDrop = 8, -- a drop this far (studs) or more earns the whole bonus (was 10)
		DiveRootSlack = 4, -- the server's check on where he is allows this much more after a dive
		LeapMul = 1.4, -- Sun Leap: while Corona is on, his spike jumps go this much higher (was 1.9: the owner, "why is laith jumping out of the screen"; the court camera holds its height, so 32 studs up left the frame)
		DiveBoost = 0.38, -- spike speed x (1 + this x how far he dropped) (0.45 before Sunfire, then 0.4, 0.3, 0.36; with the halved buff 0.38)
		DiveHeightFloor = 0.85, -- a dive spike counts as met this close to the top of his jump at least
		AutoDive = 0.3, -- the AI doesn't dive: its spikes get this much of the dive bonus
		-- Zenith: some spikes burst (decided by the ball's seed, so the hitter's client agrees)
		ZenithChance = 0.27, -- (was 0.22: the 2026-11-18 vote)
		ZenithPower = 0.13,
		ZenithSpin = 1.3, -- heavier topspin: gravity on the spike x this (it dips harder)
		TossReachMul = 1.6, -- his forward serve toss comes down this much further in front (Valen's)
		Passives = {
			{ Name = "Sunfire", Blurb = "Every spike of yours burns 18% harder." },
			{ Name = "Sundive", Blurb = "In the air, Spike with the ball below your reach (up to 12 m away): you streak down a path onto it, and the further you drop, the harder it goes (up to +38%)." },
			{ Name = "Sun Leap", Blurb = "While Corona is on, your jump goes far higher, so you can dive from above everything." },
			{ Name = "Zenith", Blurb = "About one spike in four bursts into a Zenith: +13% power and heavy topspin." },
			{ Name = "Long Toss", Blurb = "Your forward serve toss goes much further, like Valen's." },
		},
	},
	-- Hayul (the owner: a new spiker "similar to sara seo": "she dashes across the court and jumps
	-- right where the ball is. she has lower gravity and stay in the air to charge up her spike. she
	-- can aim wherever she wants on the opposing side. she has wider spike range. and has an active
	-- ability where she can increase speed and attack", "she is easily the fastest character",
	-- pasting a kit: a skill raising Attack (more the higher the Speed); the other team slowed just
	-- after her rush's jump; hold Spike to rush to where the ball comes down, let go to spring to the
	-- top of the jump; hold Spike in the air to hover, let go to swing, at a target on their court;
	-- a wider spike range). The names are ours (CLAUDE.md): Squall the skill, Tailwind the rush,
	-- Downdraft the slow, Eye of the Storm the hover and the aim, Shear the reach.
	Squall = {
		Name = "Squall",
		Tier = "S+",
		Active = true,
		Blurb = "Press Q: a squall for 10 s, faster still, and the faster you are the harder you hit. Jump on the ground to dash under the ball and spring up. In the air, hold Spike to hover: let go at once for a short drop, hold longer to hit it deeper and harder.",
		Color = Color3.fromRGB(70, 232, 200),
		Duration = 10,
		Cooldown = 22,
		SpeedBoost = 0.15, -- Speed x (1 + this) while it's on
		AttackPerSpeed = 0.12, -- and Attack + this x her Speed (the boosted one)
		-- Tailwind (the owner: "when she jumps honestly i might want it to just bring you under the ball
		-- automatically with an insanely quick dash"): Jump (or Spike) on the ground in a rally dashes
		-- her to the spot under where the ball comes down through her hitting point and springs her
		-- straight up the moment she's there, quicker than anyone; nowhere to go, it's the usual jump
		DashSpeed = 240, -- studs/s: across the whole court in about a sixth of a second
		DashMax = 0.35, -- a dash that hasn't arrived by now stops where it is
		-- at the spot she waits and springs so her top comes this long before the ball does (time
		-- to hover and charge), not at once: on a long out-of-system set she was up and falling
		-- before it got there (the owner: "on these out of system sets, haneul consistenly way
		-- overshoots it")
		SpringEarly = 0.3,
		SpringWaitMax = 2.5, -- she never waits longer than this
		RushRise = 1.5, -- the jump off a dash rises this much faster (to the same top)
		RushRootSlack = 4, -- the server's check on where she is allows this much more around a dash
		-- (the owner: "she kind of just slams her head into the net... would have an instantaneous
		-- stop when letting go of jump"): let go of Jump mid-dash and she stops dead there, then
		-- springs on time; and the dash (and Updraft's spring) never takes her closer to the net
		-- than NetClear (it went to 0.6 studs, and she sprang into the tape)
		NetClear = 0.5 * M,
		-- Downdraft: just after her Tailwind jump, the other team runs slower
		SlowMul = 0.7,
		SlowTime = 1.2,
		-- Eye of the Storm: lighter in the air (part of gravity off on the way down); Spike held in
		-- the air (once a jump) hovers her, all but weightless, and charges the spike; letting go
		-- swings. The charge is also where it goes (the owner: "the longer you charge up midair the
		-- farther back it goes while hitting it instantly makes it drop very short"): let go at once
		-- and it drops just over the net, held to the full charge it goes to their back line; a
		-- target on their court shows her where, moving back as it charges
		FallCancel = 0.35,
		-- Updraft (the owner: "make her jump higher to accomadate for the charging"): her spike and
		-- serve jumps (Tailwind's spring too) go this much higher, room to hover and charge
		LeapMul = 1.35,
		-- and at a teammate's set (the owner: "when she jumps, the set slows and she jumps right at
		-- the ball, so that its much easier to hit... a passive to updraft"): when she springs off
		-- a dash the set slows to SetSlow of its speed along the same curve (the server relaunches
		-- it from the moment she sprang: HitLogic.updraftLaunch), she springs later to match, and
		-- the spring carries her along the court to where she meets it (HomeMax at most)
		SetSlow = 0.65,
		HomeMax = 1.5 * M,
		HoverCancel = 0.985,
		-- (the owner: "adjusting while spiking is kind of impossible since she doesn't move midair
		-- during charge"): while she hovers the stick glides her along the court at this share of
		-- her air drift
		HoverGlide = 1,
		-- (the owner: "her charging speed is too slow to reach the backcourt in time")
		-- (the owner, then: "the spot her spike lands should flash by, and it is in set increments.
		-- maybe around 6 or 7, ending at the very back corner of the court", with a video of hers:
		-- a white ring on their floor jumping spot by spot toward the back corner)
		HoverMax = 0.8, -- a hover this long swings by itself
		ChargeTime = 0.6, -- seconds of hovering for the whole charge (and the deepest spike)
		AimSteps = 7, -- the spots the target jumps through, just over the net to the very back
		BackMargin = 0.15 * M, -- the last spot: this far inside their end line (the back corner)
		-- (the owner: "buff haneul's lower end of spiking. she should at the very least be hitting 150
		-- or 160 and upwards of 200"): every spike of hers hits SpikeBoost harder, and the hover
		-- adds HoverBoost on top: maxed and clean, about 158 with no charge, 205 full, 228 with Squall
		SpikeBoost = 0.15,
		HoverBoost = 0.3, -- spike speed x (1 + this x the charge) (was 0.38 before SpikeBoost)
		HoverSlack = 0.15, -- charge a spike may claim over the hover the server saw (network jitter)
		AimError = 0.5, -- a hover's spike strays this share of the usual error
		ReachMul = 1.2, -- Shear: her spike reaches this much wider
		-- and flies wild off blocks (the owner: "her spikes fly more wildly off blocks", folded into
		-- Shear): a block stuffs her less (its stuff score this much lower), and one that doesn't
		-- stuff her sends it off the hands and out (a Tool) this often instead of a soft touch they
		-- can play. A perfect block (Iron Wall, Bulwark) still holds
		ShearStuffDrop = 0.15,
		ShearToolChance = 0.5,
		AutoGale = 0.4, -- the AI doesn't hover: its spikes get this much of the charge's power
		Passives = {
			{ Name = "Tailwind", Blurb = "Hold Jump on the ground: a lightning-quick dash under where the ball comes down (let go to stop dead), then a spring straight up, quicker than anyone." },
			{ Name = "Downdraft", Blurb = "Just after a Tailwind jump, the other team runs 30% slower for a moment." },
			{ Name = "Updraft", Blurb = "Your spike jumps go 35% higher. Spring off a teammate's set and it slows to 65% while you go right at the ball." },
			{ Name = "Eye of the Storm", Blurb = "You fall lighter. In the air, hold Spike to hover and charge (the stick glides you): let go at once and it drops just over the net; the longer you hold, the deeper and harder it goes (up to +30%)." },
			{ Name = "Shear", Blurb = "Your spikes cut 15% harder, reach 20% wider than anyone's, and fly wild off blocks: stuffed less, and often whipped off the hands and out." },
		},
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
	-- Dongha (the owner: an S+ middle blocker "with the iron wall ability but as a passive. he has 3
	-- lives, and each time his block gets broken he loses 1. after he loses all 3 lives, he awakens
	-- and he becomes more of an offensive based hitter. jumping before the ball is set, he hovers
	-- midair and charges. this can reach maybe 210 220? you decide. jumping after the ball nets him
	-- less buff. touching the ball after this point grants him [10%] of his intidimadtion meter
	-- back. once full, he regains his block lives", "make him visually lose a shield"). Our names
	-- (CLAUDE.md): Ironclad; Bulwark the wall, Awakening the turn, Forge the hover and charge,
	-- Steel Reach, Intimidation the meter.
	Ironclad = {
		Name = "Ironclad",
		Tier = "S+",
		Role = "MB",
		Blurb = "Bulwark: jump to block while you have shields (up to 3; a set starts with 1) and you're an Iron Wall at the net: every attack that crosses in front of you is shut down, at any height, however hard. Each shield cracks on the first spike it stops and shatters on the next, however hard, and the block that shatters it pops straight up for your team. A jump before the set hangs and charges your spike (about 178 km/h); with no shields left you awaken and it charges to about 215. Awakened, every touch fills Intimidation by 10%; full, all 3 shields are back.",
		Kind = "Passive: shields, then awakened",
		Color = Color3.fromRGB(255, 112, 52), -- awakened: molten
		WallColor = Color3.fromRGB(170, 200, 235), -- the shields: steel
		ChargeColor = Color3.fromRGB(255, 50, 60), -- Forge's charge: red
		Lives = 3,
		-- (the owner, 2026-10-21: "he does not start off fully charged"): a set starts with this many
		-- shields; Intimidation (below) fills only once they're all broken (the owner, 2026-10-22:
		-- "make taesan only start charging his awakened after all of his shields break")
		StartLives = 1,
		-- Bulwark: while he has shields he's Iron Wall (the owner, 2026-10-15: "buff taesan block to
		-- be iron wall for 3 lives. it cracks on one hit and breaks on the next"): Iron Wall's whole
		-- wall (HitLogic.wallReach) and its perfect shut-down on every attack, tips and the hardest
		-- spikes included; nothing breaks through it any more (the 185 km/h / clean-spike break,
		-- Unbreakable and Shrapnel are gone). Instead every spike a shield stops cracks it (a white
		-- flash on him and on the shield over his head) and the CracksToBreak-th stop shatters it.
		-- A new shield (Intimidation) starts whole
		CracksToBreak = 2,
		-- (the owner, 2026-10-21: "he still shuts down everything. however, when his shield is
		-- shattered it pops up"): the stop that shatters a shield pops the ball straight up on his
		-- side, an easy ball for his team. (A 270+ km/h spike used to shatter one at once; the owner,
		-- 2026-10-22: "have his shield soft block every other hit. right now any s+ can consistently
		-- break it": only every CracksToBreak-th stop now, however hard.)
		PopUp = { 5.2, 6.0 }, -- the pop's speed up (m/s, a range), and a little toward his own court
		PopBack = 0.5,
		-- awakened: each touch fills Intimidation this much (of 100; was 10), a spike of his that
		-- scores (a kill) or a block that stuffs this much more
		MeterPerTouch = 10,
		MeterBonus = 15,
		-- Forge: off the floor his fall is slow (part of gravity off on the way down) and the spike
		-- charges with the time he's been up (WallBoost with shields, MaxBoost awakened); a jump before
		-- his team's set gets all of it, one after it LateShare
		DescentCancel = 0.4, -- (was 0.7; the owner: "taesan is a bit too floaty")
		AwakenedDescentCancel = 0.7, -- awakened he floats longer (the owner: "whn he's awakened, make him float longer")
		ChargeTime = 0.5, -- seconds in the air for the whole charge (the owner: "a very quick charge, because quicks are fast")
		MaxBoost = 0.68, -- awakened: spike speed x (1 + this x the charge): about 215 km/h maxed
		-- (the owner: "allow [him] to charge up his spike, albeit at a weaker level when he has his
		-- [shields]. maybe up to 170 180 kmh")
		WallBoost = 0.39, -- with shields: about 178 km/h maxed
		LateShare = 0.3,
		ChargeSlack = 0.15, -- charge a spike may claim over the time the server saw him up
		EarlyGrace = 0.35, -- a jump this soon after the set still counts as before it (latency)
		-- (the owner: "give taesan also extended spike range"): his spike always reaches SpikeReach
		-- times the usual (Hayul's Shear is 1.2 too), and awakened Steel Reach adds up to ReachMul
		-- more with the charge (up to 1.5 in all)
		SpikeReach = 1.2,
		ReachMul = 0.3, -- Steel Reach: + this x the charge
		AutoCharge = 0.5, -- the AI awakened: its spikes get this much of the full charge
		Passives = {
			{ Name = "Bulwark", Blurb = "Up to 3 shields (a set starts with 1): jump to block while you have one and you're an Iron Wall at the net. Every attack that crosses in front of you is shut down, at any height, tips and the hardest spikes too." },
			{ Name = "Cracks", Blurb = "A shield cracks on the first spike it stops and shatters on the next, however hard: every other block is a full shut-down. The block that shatters it pops straight up for your team." },
			{ Name = "Awakening", Blurb = "With no shields left you turn attacker: Forge charges far harder and widens your reach." },
			{ Name = "Forge", Blurb = "Your fall is slow; jump before the set and hang: the longer you're up, the harder the spike (up to +39% with shields, +68% awakened). Jumping after the set gets 30% of it." },
			{ Name = "Steel Reach", Blurb = "Your spike reaches 20% wider than usual, and awakened the charge widens it up to 50%." },
			{ Name = "Intimidation", Blurb = "Only once every shield is broken (awakened): every touch fills the meter 10%, a kill or a stuff block 25%. Full: all 3 shields." },
		},
	},
	IronWall = {
		Name = "Iron Wall",
		Tier = "S",
		Role = "MB",
		Active = true, -- press the Ability key (Q)
		-- the owner: "make it so he is literally a perfect block. when he pops the ability and a
		-- spike comes his way, it is perfect shut down onto their side no matter where it hits the
		-- block"
		-- (then "make iron wall completely unbreakable": while it's up, at the net, every attack that
		-- crosses in front of you is shut down, however high, with no jump or timing needed)
		Blurb = "Press Q: for a moment you're an unbreakable wall. At the net, every attack that crosses in front of you is shut straight down onto their side, however high or hard, even without jumping.",
		Color = Color3.fromRGB(150, 205, 255),
		Duration = 3.0,
		Cooldown = 20,
		-- while it's up the block box grows (studs): far over the hands (any spike's height, even from
		-- the floor), further each side of the net, and you can stand a little further off it
		ReachUp = 20, -- (studs: about 4.4 m more, so the highest spike in the game is still under it)
		OwnDepth = 1.6,
		OverDepth = 1.6,
		NetExtra = 2.5,
		-- and down to the floor (the owner, 2026-10-22: "allow iron wall to extend below the feet, for
		-- taesan aswell"): a steep spike that's crossed the tape can't dip under it on his side
		Floor = true,
		-- the shut-down: straight down onto their court, this far from the net (metres), this fast
		StuffDepth = { 1.0, 2.2 },
		StuffKmh = 95,
	},
	ChainReaction = {
		Name = "Chain Reaction",
		Tier = "S",
		Role = "SE",
		Blurb = "Your sets are charged. The spike or feint off one explodes: more power, and it tears through the receivers' stamina. Every explosion in a rally makes the next one bigger (up to x1.30 power). Off in 1v1s.",
		Color = Color3.fromRGB(255, 64, 64),
		-- the chain grows (the owner picked it for Jiyu's buff): the first explosion of a rally
		-- uses the first step, each one after it the next, until the rally ends
		PowerMul = { 1.15, 1.22, 1.30 }, -- spike speed off a charged set
		DrainMul = { 2.4, 2.8, 3.2 }, -- receive drain of the exploding ball
		FlatDrain = { 16, 20, 26 }, -- plus this, even off a feint
		BlastScale = { 1, 1.35, 1.75 }, -- the explosion's size
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
	-- Narae (the owner: "a setter that works well. a setter that sets high and the ball drops slowly,
	-- the longer it drops the harder your spike gets. dont know how high that buff should be but you
	-- pick"). Featherfall: her open and back sets go up higher and float down from the top (lighter
	-- gravity), so the hitter has time to line up; a spike off one gets more power the longer the
	-- ball had been falling, the whole MaxBoost at FullFall (about the whole float down to the usual
	-- hitting height). Quicks stay quick.
	Featherfall = {
		Name = "Featherfall",
		Tier = "S",
		Role = "SE",
		Blurb = "Your open and back sets go up high and float down slowly. The longer the ball has been falling when your hitter meets it, the harder the spike: up to +30%.",
		Color = Color3.fromRGB(255, 176, 214),
		ExtraApex = 1.2 * M, -- her sets' top this much higher
		FallGravity = 0.4, -- from the top down, gravity x this: it floats
		MaxBoost = 0.3, -- spike speed x (1 + this x how long it fell / FullFall) (was 0.2; the owner: "we can buff the amount of power that featherfall gives")
		FullFall = 1.25, -- seconds of falling for the whole boost (about her set's float down to the usual hitting height)
	},
	-- Byeol (the owner, 2026-11-04: a new setter "inspired by zero from tsc", our own name, look and
	-- twist on a timed set): Q, and for Duration his open and back sets climb and hang, and a star
	-- lights at the top (HitLogic: starFrom). Spiked before that it's a plain spike (the owner: "people
	-- can spike early", it just has no boost); met while it burns (to starTo: the whole slow fall to the
	-- hitting height, and LitGrace) the spike goes StarBoost harder and the hitter is Starlit; a late
	-- spike, any other touch, or the ball dropping leaves them Discouraged for MissSecs
	-- (TeamService.discourage).
	FallingStar = {
		Name = "Falling Star",
		Tier = "S",
		Role = "SE",
		Active = true,
		ActiveName = "Falling Star",
		Blurb = "Press Q: for 6 s your open and back sets climb and hang, and a star lights at the top. Hit it while the star burns for a spike 28% harder. Spike before it lights for a normal spike; spike it late or let it drop and your hitter is Discouraged.",
		AiNote = "Your AI calls it on some of its sets, and its hitters always find the star",
		Color = Color3.fromRGB(120, 200, 255),
		Duration = 6,
		Cooldown = 18,
		HangApex = 1.1 * M, -- the top this far over where the hitter meets it
		FallGravity = 0.22, -- from the top down, gravity x this: it hangs
		LitGrace = 0.15, -- seconds past the hitting height that still count
		EarlySlack = 0.05, -- a swing this close before the star lights still gets the boost (a laggy click)
		StarBoost = 0.28,
		StarlitSecs = 8,
		StarlitAdd = { Attack = 10, Jump = 4 },
		MissSecs = 8,
		Passives = {
			{ Name = "Starlit", Blurb = "A hitter who meets the star gets +10 Attack and +4 Jump for 8 s." },
			{ Name = "Burnt Out", Blurb = "A hitter who spikes it late, or lets it drop, is Discouraged for 8 s." },
		},
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
	-- Gunwoo (the owner, 2026-10-21: "The Tyrant (S+ Setter)": Emperor's Dictate, Sovereign's Guard,
	-- Crown Jump Serve and Tyrant's Set, their numbers kept as the owner wrote them). Emperor's
	-- Dictate (Q): a golden aura across the court; for Duration the other team loses Steal of its
	-- Attack, Jump and Speed and his team gains TeamAdd (Stat Hijack), a spike off his set is met at
	-- full power whatever the timing (Absolute Toss), and the other team's block reaches BlockCut of
	-- its usual height over the tape (Iron Fortress). Sovereign's Guard: an attack of theirs faster
	-- than GuardKmh grounds its hitter: GroundedCut less Jump and Attack on their next attack. His
	-- jump serve is always the Crown Jump Serve (it dips steep, costs the receiver CrownDrainMul of
	-- the guard, and their pass and set off it go low and wide); his sets are always Tyrant's Sets
	-- (the usual arc flown faster, the spike off one SetMul faster and Armor Break: no ordinary block stuffs it).
	Tyrant = {
		Name = "The Tyrant",
		Tier = "S+",
		Role = "SE",
		Active = true, -- Emperor's Dictate (Q)
		ActiveName = "Emperor's Dictate",
		Blurb = "Press Q for Emperor's Dictate: for 5 s their team is Locked (35% less Jump and Speed, 15% less Attack, spikes 20% slower, no slides) and yours gets the stolen stats, your sets are met at full power, your own attacks hit at full power and 1.15x, and their blocks reach half as high. Your sets fly fast (spikes off them 1.3x, no block stuffs them); your jump serve hits as hard as the best S+ wing spiker's, dips hard and wrecks their pass.",
		Color = Color3.fromRGB(255, 196, 60),
		-- (the owner, 2026-10-22: "make dohwans nerf more intense its basically doing nothing right now.
		-- maybe like yamdera from the spike" (Lock: no slides, Speed and Jump down hard), "maybe not as
		-- intense", "its just the ability pop", "and maybe nerf the duration on that too": the Dictate
		-- Locks their team, shorter)
		Duration = 5, -- (was 8)
		Cooldown = 24, -- (was 32; the owner, 2026-10-22: "he's not doing enough to earn that s+ title")
		Steal = 0.35, -- the Lock: the other team's Jump and Speed x (1 - this), and no slides (was 0.15 of all three)
		StealAttack = 0.43, -- and their Attack x (1 - Steal x this): about 15%
		TeamAdd = { Attack = 12, Jump = 10, Speed = 10 }, -- his whole team's, stolen
		BlockCut = 0.5, -- their block's reach over the tape x this
		-- (the owner, 2026-10-25: "buff dohwan so that his ability reduces spike power aswell"): the
		-- Locked team's spikes and jump serves x (1 - this), on top of the Attack it takes (more with a
		-- grown Steal, in proportion)
		LockSpikeCut = 0.2,
		-- Sovereign Strike (2026-10-22, so the Tyrant shows it in his own hands): while Emperor's
		-- Dictate is on, his own spikes and jump serves are met at full power, SelfMul faster, with
		-- Armor Break
		SelfMul = 1.15,
		-- Sovereign's Guard
		GuardKmh = 180,
		GroundedCut = 0.1, -- the grounded hitter's Jump and Attack x (1 - this), one attack
		-- Crown Jump Serve
		-- (the owner, 2026-10-22: "make dohwan's crown serve give him a serve on par with the top of
		-- the s+ ws. only for his serve though", "he should have a decently solid attack though": his
		-- Attack went 140 -> 170, and his jump serve alone hits with this many Attack points more, so
		-- maxed it's Valen's 222, the best S+ wing spiker's)
		CrownServeAttack = 52,
		CrownGravity = 1.55, -- topspin: x the usual jump serve's dip
		CrownDepthMul = 0.85, -- a little shorter, for the steep path down
		CrownDrainMul = 2, -- the receiver's guard drain
		CrownPassMul = 0.72, -- the pass off it: quality x this
		CrownSetError = 1.4 * M, -- and the set off that pass strays up to this much more
		CrownSetLow = 1.2 * M, -- and comes down this much lower
		-- Tyrant's Set (Open and Back; quicks stay quick)
		-- (the owner, 2026-10-21: "i think the tyrant sets so low", then "the setter should have
		-- normal height but just faster overall": a usual set's arc, flown faster; it was flat, its
		-- top 1.1 m over where it came down)
		SetSpeed = 1.25, -- the usual arc, this much faster (gravity x SetSpeed^2: the same path in 1/SetSpeed the time)
		SetLower = 0.5 * M, -- and its top this much lower (then "dohwan sets a little too high now")
		SetMul = 1.3, -- the spike off it
		Passives = {
			{ Name = "Emperor's Dictate", Blurb = "Press Q: for 5 s their team is Locked: 35% less Jump and Speed, 15% less Attack, their spikes and jump serves 20% slower, and no slides. Your team gets +12 Attack, +10 Jump and +10 Speed, spikes off your sets hit at full power, and their blocks reach half as high." },
			{ Name = "Sovereign Strike", Blurb = "While Emperor's Dictate is on, your own spikes and jump serves hit at full power, 1.15x as fast, and no ordinary block stuffs them." },
			{ Name = "Sovereign's Guard", Blurb = "Spike faster than 180 km/h at your team and you're Grounded: 10% less Jump and Attack on your next attack." },
			{ Name = "Crown Jump Serve", Blurb = "Your jump serve hits as hard as the best S+ wing spiker's (+52 Attack on it), curls down steeply, costs the receiver double stamina, and leaves them a low, wild set." },
			{ Name = "Tyrant's Set", Blurb = "Your sets fly fast, the usual arc in less time. The spike off one goes 1.3x as fast with Armor Break: an ordinary block can't stuff it." },
		},
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
	-- Dasol (the owner, 2026-10-21: an S middle blocker, "Ability, Sunshine gives increase perfect
	-- bump window, once this perfect bump is hit, block hitbox, bump hitbox, and all stats increased
	-- by ten. Passive Vert Spikes, all spikes are sharper, the shaper it is, the harder it is, can
	-- be used to go under blocks", "During Bump, Defense Range increases by 33%, Defense by 70, and
	-- Speed by 18", always on, "she has a sun aura when she bumps"). Her receive's perfect window is
	-- wider (PerfectStance, PerfectAt); a perfect one lights Sunshine for SunDuration: every stat
	-- +SunAdd and bigger block and receive boxes. Every receive of hers reaches DigReach wider with
	-- DigAdd on top. Vert Spikes: her spikes land VertDepthMul as deep, the steeper the line down the
	-- harder (VertBoost from VertAngle[1] to [2]), and from UnderAngle on they slip under the block.
	Sunshine = {
		Name = "Sunshine",
		Tier = "S",
		Role = "MB",
		Kind = "Passive: perfect digs",
		Blurb = "Your perfect-dig window is far wider, and a perfect dig lights Sunshine for 10 s: +10 to every stat, bigger block and dig reach. Your digs reach 33% wider (+70 Defense, +18 Speed). Vert Spikes: your spikes come down sharp, harder the steeper, and the steepest slip under blocks.",
		Color = Color3.fromRGB(255, 200, 80),
		PerfectStance = { 0.03, 0.62 }, -- her receive pressed this long before contact is perfect timing (everyone's 0.08..0.42)
		PerfectAt = 0.78, -- and a perfect dig from this quality (everyone's 0.86)
		SunDuration = 10,
		SunAdd = 10, -- every stat while Sunshine is lit
		SunBox = { ReachUp = 1.2, OwnDepth = 0.6, OverDepth = 0.6, NetExtra = 0.8 }, -- the block box's extra (studs)
		SunReach = 1.2, -- her receive reach, x this on top of DigReach
		DigReach = 1.33, -- every receive of hers reaches this much wider
		DigAdd = { Defense = 70, Speed = 18 }, -- and is played with these on top
		-- Vert Spikes
		VertDepthMul = 0.72,
		-- (the owner, 2026-10-21: "add a passive for haesol for a more vertical spike or a steeper
		-- sharper angle"): her spike crosses the net, then turns and drives down nearly vertical
		-- (Plunge Spin's turn, steeper and shorter): met at the hand or behind it at AngleShort onto
		-- LandShort, met out in front at AngleDeep onto LandDeep
		VertDive = { DiveAngleShort = 76, DiveAngleDeep = 66, LandShort = 1.3 * M, LandDeep = 4.2 * M, TurnDrop = 0.3 * M, TurnOverNet = 0.45 * M, TurnMin = 0.5 * M, FlatGravity = 0.3, DiveSpeed = 1.0 },
		VertAngle = { 20, 44 }, -- degrees below level, contact to landing: no boost, the whole VertBoost
		VertBoost = 0.2,
		UnderAngle = 50, -- from here a spike of hers goes under the block (Iron Wall and Bulwark still stop it; 36 before her dive)
		Passives = {
			{ Name = "Sunshine", Blurb = "Your perfect-dig window is far wider. A perfect dig lights Sunshine for 10 s: +10 to every stat, and your block and dig reach grow." },
			{ Name = "Sun Dig", Blurb = "Your digs reach 33% wider and are played with +70 Defense and +18 Speed." },
			{ Name = "Vert Spikes", Blurb = "Your spikes cross the net and drive straight down at a sharp angle: the steeper, the harder (up to +20%), and the steepest slip under the block." },
		},
	},
	-- Kuro (the owner's own character, 2026-11-04; "change all the values that seem too absurd"):
	-- hold Jump on the ground and let go in the gold of the meter for his highest jump, in the silver
	-- for less. The higher he hits, the harder (FlameFromM up to DragonM). From DragonM a dragon dives
	-- from the sky at the spike's landing spot; from InfernoM (once per InfernoCooldown) the sky goes
	-- red and whoever touches the ball burns (TeamService.discourage). The sheet's 5.00 m / 5.05 m
	-- came down to fit the game: a maxed Kuro hits about 4.40 m, gold lifts that to 4.75 m, and the best
	-- block tops out about 4.4 m. No fixed km/h: the speed follows his Attack and height (about 236 for
	-- a Dragon Spike maxed, 250 with Inferno; a full Feral Leap is 220, overcharged 268).
	Enflamed = {
		Name = "Enflamed Dragon",
		Tier = "S+",
		Role = "WS",
		Kind = "Hold Jump on the ground",
		Blurb = "Hold Jump and let go in the gold for your highest jump, the silver for less. The higher you hit, the harder: at the very top a dragon dives from the sky at your spike, and higher still the sky turns red and whoever touches the ball burns.",
		AiNote = "Your AI jumps with it now and then, and hits a gold jump less often than you can",
		Color = Color3.fromRGB(255, 96, 24),
		ChargeTime = 0.72, -- seconds for the meter to fill (the owner: "should be quicker"; was 0.9)
		TapTime = 0.15, -- let go sooner and it's the usual jump
		SilverFrom = 0.55, -- the meter: silver from here on...
		GoldFrom = 0.78, -- ...gold between these two (0.11 s, as long as before the quicker fill)...
		GoldTo = 0.93, -- ...then silver again (held too long)
		GoldLift = 0.35, -- metres on his hitting point
		SilverLift = 0.15,
		FlameFromM = 4.2, -- the flames start at this contact height
		DragonM = 4.7, -- Dragon Spike
		InfernoM = 4.74, -- and the red sky
		MaxBoost = 0.5, -- speed x (1 + this x how far from FlameFromM to DragonM)
		DragonBoost = 0.12,
		InfernoBoost = 0.06,
		InfernoCooldown = 20,
		ReachMul = 1.1, -- Conditioned Player: a bigger spike hitbox
		GuardDefense = 8, -- a stronger guard, harder to break (Defense feeds the guard's size and drain)
		PerfectWiden = 0.1, -- and the perfect-receive window, this share wider at each end
		AutoGold = 0.2, -- played by the AI: its share of gold jumps and of silver ones
		AutoSilver = 0.45,
		AutoBoostMul = 0.7,
		Passives = {
			{ Name = "Dragon Spike", Blurb = "Hit from high enough and a dragon dives at your spike, a fire blast from your hand." },
			{ Name = "Inferno", Blurb = "Hit higher still and the sky turns red and the ball goes up in flames: receive it and your guard breaks at once, touch it at all and you burn (every stat down). Once every 20 s." },
			{ Name = "Conditioned Player", Blurb = "A stronger guard, a wider perfect receive and a bigger spike hitbox." },
		},
	},
	-- Horang (the owner, 2026-10-29: The Spike Cross's Hongshi, with her whole kit, "buff or nerf
	-- accordingly"). Tiger Claw: receiving or diving her attack marks you (only receives: "you only
	-- get it when u rec"; the "Clawed" attribute, HitService, VFXController), -JumpCut Jump while
	-- marked; marked, your next receive of hers fails (off the arms and out: HitLogic meta.clawed) and
	-- the mark is spent; a failed receive of hers Discourages you FailDiscourage of the time.
	-- Fierce Tiger: while the lowest-Defense player in their back court (HitLogic.huntTarget) carries
	-- her mark, FierceAdd (grown by breakthroughs to about +18 Attack, +4 Jump). RAWR!: the match's
	-- first serve Discourages each of them RawrChance of the time. Hunt: that player is outlined.
	-- Discouraged: every stat -DiscouragedCut for DiscouragedSecs.
	TigerClaw = {
		Name = "Tiger Claw",
		Tier = "S",
		Role = "WS",
		Kind = "Passive: marks receivers",
		Blurb = "Receive or dive her attack and a tiger claw marks you (-9 Jump). Marked, your next receive of hers fails, and that can leave you Discouraged. Fierce Tiger: while their weakest back-row defender is marked she hits harder and jumps higher.",
		Color = Color3.fromRGB(255, 132, 30),
		JumpCut = 9,
		FierceAdd = { Attack = 10, Jump = 2 },
		RawrChance = 0.8,
		FailDiscourage = 0.2,
		DiscouragedSecs = 15,
		DiscouragedCut = 8,
		Passives = {
			{ Name = "Fierce Tiger", Blurb = "While the weakest defender in their back row carries your mark: +10 Attack, +2 Jump." },
			{ Name = "RAWR!", Blurb = "The match's first serve very likely Discourages their whole team (-8 to every stat for 15 s)." },
			{ Name = "Hunt", Blurb = "The weakest defender in their back row is outlined in red." },
		},
	},
	-- Joker, the ability of Jaja (the owner, 2026-11-15: "joker's name is jaja"; the Christmas collab character with Jaja's Volleyball: Spike
	-- Evolved, the event's exclusive recruit). Jaja's kit, as sent: "At the start of every rally,
	-- joker throws a card into the air that reveals a random buff, which can be any of these. It
	-- lasts for the rally. Trickery - adds spike power and makes your spikes curve awkwardly.
	-- Bravery - increases your spike power heavily and makes spikes break block. Buffoon - lose 25%
	-- spike power. Jackpot! - massively boosts all stats, grants curve, block break. Passive -
	-- Surprise! - spiking the ball on 2nd touch buffs spike power". The numbers and the odds are
	-- ours (first guesses). Cards: Weight, the odds (of their sum); SpikeMul, his spikes' speed;
	-- Break, Block Break (our Armor Break: it can't be stuffed clean); Curve, the spike leaves the
	-- hand on a strange line (rising or flat, under FlatGravity) and hooks down past the net onto
	-- its spot (Curve below; a 2D court, so the curve is up and down, not sideways); Stats, every
	-- stat +JackpotAdd for the rally. Dealt as each rally starts (TeamService.dealJoker); bots too.
	Joker = {
		Name = "Joker",
		Tier = "S+",
		Role = "WS",
		Kind = "Passive: a card every rally",
		Blurb = "Every rally you throw a card that sets your spikes until the point ends, and borrow a random S or S+ spiker's or blocker's ability with it. Trickery: +8% power, and they curve. Bravery: +20% power with Block Break. Buffoon: -25% power. Jackpot!: +25 to every stat, +12% power, curve and Block Break.",
		Color = Color3.fromRGB(176, 72, 255),
		Order = { "Trickery", "Bravery", "Buffoon", "Jackpot" },
		Cards = {
			Trickery = { Name = "Trickery", Weight = 35, SpikeMul = 1.08, Curve = true, Color = Color3.fromRGB(70, 230, 150), Blurb = "+8% spike power, and your spikes curve." },
			Bravery = { Name = "Bravery", Weight = 30, SpikeMul = 1.2, Break = true, Color = Color3.fromRGB(255, 76, 76), Blurb = "+20% spike power, with Block Break." },
			Buffoon = { Name = "Buffoon", Weight = 25, SpikeMul = 0.75, Color = Color3.fromRGB(150, 156, 176), Blurb = "-25% spike power." },
			Jackpot = { Name = "Jackpot!", Weight = 10, SpikeMul = 1.12, Stats = true, Curve = true, Break = true, Color = Color3.fromRGB(255, 208, 60), Blurb = "+25 to every stat, +12% spike power, curve and Block Break." },
		},
		JackpotAdd = 25, -- every stat, for the rally
		-- Sleight of Hand (the owner, 2026-11-15: "i want him to every round pull a random s tier
		-- ability. this can range from jaeil's zero point to gunwoo's iron wall. no setter abilities"):
		-- with each rally's card he also plays one other ability, drawn evenly from every S and S+
		-- ability of a wing spiker or a middle blocker (HitLogic.jokerPool), stacked beside his own
		-- like a Colosseum ability card (at +0: breakthroughs grow only his own). NoBorrow: left out
		BorrowRoles = { WS = true, MB = true },
		NoBorrow = {},
		SurpriseBoost = 0.1, -- Surprise!: his spike on his team's second touch
		Curve = {
			MinOverNet = 0.3 * M, -- met at least this far over the tape (lower: a usual spike)
			TurnAt = { 0.3, 0.65 }, -- the turn, this share of the way from the net to where it lands
			TurnMin = 0.8 * M, -- never nearer the net than this
			TurnGap = 1.2 * M, -- nor nearer its landing spot than this
			RiseChance = 0.5, -- it leaves the hand climbing this often; otherwise nearly flat
			Rise = { 0.2 * M, 0.9 * M }, -- how far above the contact the turn is, climbing
			Drop = { 0.1 * M, 0.5 * M }, -- or below it, flat
			TurnOverNet = 0.45 * M, -- the turn is never lower than this over the tape
			FlatGravity = 0.3, -- gravity x this before the turn
			DiveSpeed = 0.95, -- the hook keeps this much of the speed
		},
		Passives = {
			{ Name = "Surprise!", Blurb = "Spike on your team's second touch: +10% spike power." },
			{ Name = "Sleight of Hand", Blurb = "Every rally you also play a random S or S+ ability of a wing spiker or middle blocker, from Zero Point to Iron Wall." },
		},
	},
	-- Alexis (a fan's middle blocker, the owner, 2026-10-29, "buff or nerf accordingly"): Fever
	-- charges PerBlock a block up to Max; Q spends it: the whole team gets that much (Rally Cry's
	-- boost, HitService) for Duration and she gets StatAdd on top. "Too cold there": a ColdChance
	-- (ColdFever while Fever is on) that an opposing spike is frozen at the hand and dropped as her
	-- block (HitLogic.coldStuff). The fan's +15/+30/+20/+30 Fever stats were trimmed for an S.
	Fever = {
		Name = "Fever",
		Tier = "S",
		Role = "MB",
		Active = true,
		-- (the owner, 2026-11-14: "lets buff alexis": every number up; was 2% a block to 16%, +12/+22/
		-- +12/+22, 8 s, 24 s cooldown, 1% / 2% freeze)
		Blurb = "Every block charges Fever (3% a block, up to 24%). Press Q: your whole team gets that boost for 10 s and you get +18 Attack, +30 Defense, +18 Speed and +30 Jump. Too cold there: a 2% chance (4% in Fever) to freeze an enemy spike at the hand.",
		Color = Color3.fromRGB(120, 210, 255),
		Duration = 10,
		Cooldown = 20,
		PerBlock = 0.03,
		Max = 0.24,
		StatAdd = { Attack = 18, Defense = 30, Speed = 18, Jump = 30 },
		ColdChance = 0.02,
		ColdFever = 0.04,
		ColdKmh = 40, -- the frozen spike drops this fast at the hitter's feet
		Passives = {
			{ Name = "Too cold there", Blurb = "A 2% chance (4% in Fever) that an enemy spike is frozen at the hand and dropped as your block." },
		},
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
		-- km/h, with Valen's full leap 204 and a full Azure 201; it was 0.12, 157 km/h)
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
	-- Jaeil (the owner: "an ability focused on perfect contact... a perfect contact spike hits a ???
	-- km/h... around [YeJun's] double spike power or maybe higher. a perfect spike plays the image
	-- like i show you, but a normal one doesnt"; then, the PERFECT grade being "impossible": "change
	-- how its achieved", "you need some leniency or else its not possible", "maybe do it if the
	-- ball is slightly infront of you above your head"). A spike met with the ball in his sweet
	-- spot, ZeroDz in front of his raised hand and ZeroDy around and above it (studs, x his reach),
	-- is a Zero Point: ZeroKmh by how clean the contact was (x Power: about 240 maxed, YeJun's
	-- double swing is 236), nearly straight (Gravity), through any block that isn't Iron Wall, the
	-- speed hidden as "???" and a white beam with rings along its line. Anywhere else (behind his
	-- head, low, far out in front) it's his usual spike, no effect.
	ZeroPoint = {
		Name = "Zero Point",
		Tier = "S+",
		Blurb = "Spike the ball while it's slightly in front of you, above your head, and it becomes a Zero Point: too fast to read (??? km/h), nearly straight, through the block, and it costs whoever digs it extra stamina. Anywhere else it's a normal spike.",
		Color = Color3.fromRGB(235, 245, 255),
		ReachMul = 1.12, -- (was 1.2 until the community voted to nerf him, 2026-11-18) his spike hitbox is this much bigger (the owner: "a buff to the hitbox"), the sweet spot too
		-- the owner drew the spot: a big box in front of him and above his head, so it's most of the
		-- front and top of his hitbox (studs from his raised hand, x his reach and ReachMul)
		ZeroDz = { -0.2, 3.0 }, -- (was -0.3 to 3.4 before the 2026-11-18 nerf) -- from level with the hand to well out in front
		ZeroDy = { -1.4, 3.6 }, -- (was -1.6 to 4.0) -- from about his head up past the top of his reach
		ZeroKmh = { 218, 236 }, -- (was 228 to 246) -- from an edge of the sweet spot to a clean contact (x Power)
		-- his jump serves too (the owner: "let zero point work on serves"), a little slower
		ZeroServeKmh = { 198, 218 }, -- (was 205 to 225)
		-- where the ball sits for the freeze and leaves from: on his hand, this far above and ahead
		-- of it (studs)
		HandUp = 0.7,
		HandAhead = 0.5,
		Gravity = 0.35, -- gravity x this: a laser line
		-- the owner: "play a small cutscene when he hits it and freeze on the frame of impact": the ball
		-- holds on his hand this long (everyone sees it) while he hangs in the air and the camera cuts
		-- in on him, then it fires
		-- the first FreezeDark of it stops on the hit with the court gone dark and him lit white (the
		-- owner's second reference, "just the white spiker guy"), the rest is the silhouette cut-in
		Freeze = 0.6,
		FreezeDark = 0.25,
		DrainMul = 1.2, -- (was 1.3) digging one costs this much more stamina
	},
	-- Yeseul (the owner: "a jump that starts low, but the higher spike point she gets the higher her
	-- jump increases... at her peak, maybe 4.7-4.8", and "instead of a typical feint she has a sharp
	-- nearly 90 degree spike"; then, back to S+: "if her attack scales with highest jump too, and
	-- maybe make it so her vertical feint is based on her distance from net"). Her hitting point
	-- moves by Lift metres (from StartLift each set): every spike adds up to Gain, all of it when
	-- met at the top of her jump, less the lower she met it, to MaxLift (maxed: about 3.85 m at the
	-- start of a set, 4.75 m at the top); her Attack climbs with it, up to AttackAtMax more. Her
	-- feint is Talon Drop: a spike driven down at TalonAngle, steepest right at the net and flatter
	-- the further back she is (out to TalonReach, and flatter still past it), never so steep it
	-- can't clear the tape: it always comes down just over the net on their side.
	Skyward = {
		Name = "Skyward",
		Tier = "S", -- (the owner dropped Yeseul to S, keeping her Attack climb)
		Role = "WS",
		Blurb = "Your jump starts low and climbs: every spike raises your hitting point and your Attack, most when you meet it at the very top (up to about 4.75 m and +24 Attack maxed), until the set ends.",
		Color = Color3.fromRGB(255, 120, 200),
		StartLift = -0.45, -- metres on her hitting point at the start of a set
		MaxLift = 0.45,
		AttackAtMax = 24, -- Attack points at MaxLift (none at StartLift, in proportion between)
		Gain = 0.15, -- metres a spike at the top of her jump adds (x the height quality ^ GainExp)
		GainExp = 4, -- steep: only near the top of her jump does a spike lift her much
		TalonAngle = { 86, 55 }, -- degrees below level: right at the net, and at TalonReach
		TalonReach = 2.2 * M, -- the ball this far from the net (her side); further back, flatter still
		TalonPower = 0.9, -- x her spike's speed
		-- Sharp Angle (the owner, 2026-10-21: "a passive slightly increase spike angle on seora"): her
		-- spikes land this much as deep, so they come down a little steeper
		AngleDepthMul = 0.85,
		Passives = {
			{ Name = "Talon Drop", Blurb = "Feint is a spike driven down over the net: nearly straight down right on top of it, flatter the further back you are." },
			{ Name = "Sharp Angle", Blurb = "Your spikes come down a little steeper than anyone's." },
		},
	},
}
-- Retired characters (the owner: "remove repeat characters. provide compensation with one free s
-- tier selection ticket"): each shared an ability with another character. A profile that owned
-- one loses it on its next load and gets a ticket per retired character it owned (once): the
-- ticket recruits any TicketTier character it doesn't own yet (Home opens the pick).
Config.Retired = {
	Chars = { "hayun", "gaeul", "akira" }, -- Adrenaline (Riki stays), Iron Wall (Gaku), Chain Reaction (Jiyu)
	TicketTier = "S",
}

Config.AbilityOrder = { "Thunder", "Azure", "Feral", "Enflamed", "ZeroPoint", "Corona", "Squall", "Ironclad", "Tyrant", "Adrenaline", "IronWall", "Sunshine", "ChainReaction", "Vector", "Featherfall", "FallingStar", "Turnabout", "RisingSun", "RallyCry", "Counter", "Plunge", "Skyward" }

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
	-- a forfeit counts as a win (record, streak, VP) for the other side only after this many points
	-- were played in the match (MatchService.results)
	ForfeitWinMinPoints = 3,
	-- a forfeit is a team vote: every player on the team (bots don't vote) presses Forfeit within
	-- this many seconds of each other, and pressing again takes a vote back
	ForfeitVoteTime = 30, -- (the owner: 3, so leaving early can't rob the other side of a win)
	-- the matchup intro (LineupController): a wipe opens each team's turn (Open for the first,
	-- Wipe after), each team lined up in its poses for TeamTime, then both names meet for
	-- VersusTime and it fades to the court; the pre-match wait covers all of it
	Intro = { Open = 0.3, Wipe = 0.25, TeamTime = 2.4, VersusTime = 1.1, Fade = 0.35 },
	PreMatchTime = 7.6,
	PreServeTime = 1.2,
	ServeClock = 8,
	-- the pause after a point (the owner: "make them last a longer so that players can really see
	-- it, and in turn i guess make the intermission between points a little longer")
	PointPauseTime = 4.4,
	-- the score effects (VFXController's celebrate): each one's scale by its rarity (the owner:
	-- "some explosions should be bigger than others... like court size"); the camera holds on the
	-- spot for Hold seconds before the hero shot, from View[rarity] studs away
	ScoreFx = {
		Scale = { Common = 1.8, Rare = 2.1, Epic = 2.5, Legendary = 3, Mythic = 3.4 },
		Hold = 2.4,
		View = { Common = 40, Rare = 44, Epic = 52, Legendary = 72, Mythic = 80 },
	},
	SetEndTime = 3.5,
	MatchEndTime = 11, -- the showcase (your team, their stats); Continue closes it sooner
	DefaultBotTier = "A",
	FirstMatchTier = "D", -- a player's first Quick Match is against bots of their own tier (this when unknown)
	-- Quick Match bots play at the strongest player's character tier, between these (the owner:
	-- "right now queues only have A+ tiers i want it up to S+")
	QuickBotFloor = "A",
	QuickBotCeiling = "S+",
	-- points the scorer earned: after the rally the camera closes on them, their score effect goes
	-- off and their card slides in with this word (faults like outs and nets get none of it)
	Celebrate = { Spike = "SPIKE!", Feint = "FEINT!", Tooled = "TOOLED!", Break = "GUARD BREAK!", Ace = "ACE!", Stuff = "STUFF!", Block = "BLOCK!" },
}

-- Custom lobbies (the Lobbies module has the rules). A lobby plays on this server's court when
-- it's free; otherwise it gets its own reserved server (in Studio it waits for the court). One
-- with players from other servers (Global) always gets its own.
Config.Lobby = {
	Privacy = { "Public", "Friends", "Private" },
	PasswordMin = 3,
	PasswordMax = 12, -- letters and digits
	MaxLobbies = 16, -- per server
	-- (a Quick Match lobby starts on its own only when it's full; its first player can start it with bots
	-- before that. The owner: "dont make it auto start with bots. leave it and add an option to
	-- start with bots")
	ArriveTimeout = 20, -- a teleported lobby waits this long for its players in the new server
	ReservedServers = true,
	-- Across servers (the owner: "make queues global throughout servers, same with lobbies"):
	-- every server lists its open lobbies in a MemoryStore sorted map (Map), so the lobby list
	-- and Quick Match see every server's. A lobby stays in its host's server; a player elsewhere
	-- takes a remote seat (the two servers talk over MessagingService, a topic per server: Inbox
	-- + its JobId), and when it starts everyone goes to one reserved server. Studio keeps its own
	-- map (MemoryStore keeps Studio and live apart) and can't teleport. Off: lobbies stay per server.
	Global = {
		Enabled = true,
		Map = "SpikeRushLobbies",
		Inbox = "SpikeRushLobby_",
		Format = 1, -- entries and messages of another format are left alone (servers on old code)
		Write = 1, -- s: a changed lobby's entry is rewritten at most this often
		Refresh = 20, -- s: and at least this often
		Expire = 60, -- s: an entry nobody rewrites is gone after this (its server stopped)
		LaunchKeep = 45, -- s: a started lobby's entry (with its server's code) stays this long
		-- (the map's partition ran over its request limit, 2026-10-25: reads less often, and an AFK
		-- Lounge server or a player inside the lounge doesn't count as browsing)
		Read = 8, -- s: how often a server with anyone in the menus reads the list
		ReadPerEntry = 0.15, -- s: plus this per lobby listed (fewer reads when there are many)
		MaxRead = 100, -- lobbies read at most
		ListMax = 30, -- rows in a player's list (this server's lobbies first)
		QuickFresh = 1.5, -- s: Quick Match reads the list again when it's older than this
		QuickLead = 2, -- s: a Quick Match elsewhere is only joined with this long left before it starts
		JoinWait = 6, -- s: a join the host's server hasn't answered by then fails
		Keep = 8, -- s: a server tells each host it still has its players
		Watch = 3, -- s: and reads the lobbies they sit in
		SeatLease = 25, -- s: a remote seat with no word from its server is let go
		MessageMax = 950, -- bytes (MessagingService takes 1 kB a message)
	},
}

-- Match modifiers for custom lobbies (the owner, 2026-10-21: "add custom match modifiers, like more
-- power, low gravity, no ability cd like rocket league. add more than just what i added"): the host
-- picks one option of each (the first is the usual game); src/shared/Mutators.lua reads them.
-- Option fields: Spike / Serve (attack and jump-serve speed x), Gravity (ball and players x),
-- Cooldown (abilities' cooldowns x, 0 none), Drain (guard drain x, 0 never breaks), Add (stat
-- points for everyone), NoAbilities, NoBlocks, BlockUp (block reach higher, studs).
Config.Mutators = {
	Order = { "Power", "Gravity", "Cooldowns", "Abilities", "Stamina", "Jump", "Speed", "Blocks", "Serves" },
	List = {
		Power = { Name = "Spike power", Options = {
			{ Key = "Normal" },
			{ Key = "Strong", Name = "Strong (x1.25)", Spike = 1.25 },
			{ Key = "Super", Name = "Super (x1.5)", Spike = 1.5 },
			{ Key = "Weak", Name = "Weak (x0.8)", Spike = 0.8 },
		} },
		Gravity = { Name = "Gravity", Options = {
			{ Key = "Normal" },
			{ Key = "Low", Name = "Low", Gravity = 0.65 },
			{ Key = "Moon", Name = "Moon", Gravity = 0.45 },
			{ Key = "Heavy", Name = "Heavy", Gravity = 1.35 },
		} },
		Cooldowns = { Name = "Ability cooldowns", Options = {
			{ Key = "Normal" },
			{ Key = "Half", Name = "Half", Cooldown = 0.5 },
			{ Key = "None", Name = "None", Cooldown = 0 },
		} },
		Abilities = { Name = "Abilities", Options = {
			{ Key = "On" },
			{ Key = "Off", Name = "Off (stats only)", NoAbilities = true },
		} },
		Stamina = { Name = "Stamina", Options = {
			{ Key = "Normal" },
			{ Key = "Endless", Name = "Endless (never breaks)", Drain = 0 },
			{ Key = "Fragile", Name = "Fragile (x2 drain)", Drain = 2 },
		} },
		Jump = { Name = "Jump", Options = {
			{ Key = "Normal" },
			{ Key = "High", Name = "High (+25)", Add = { Jump = 25 } },
			{ Key = "Super", Name = "Super (+50)", Add = { Jump = 50 } },
			{ Key = "Low", Name = "Low (-25)", Add = { Jump = -25 } },
		} },
		Speed = { Name = "Run speed", Options = {
			{ Key = "Normal" },
			{ Key = "Fast", Name = "Fast (+30)", Add = { Speed = 30 } },
			{ Key = "Turbo", Name = "Turbo (+60)", Add = { Speed = 60 } },
			{ Key = "Slow", Name = "Slow (-30)", Add = { Speed = -30 } },
		} },
		Blocks = { Name = "Blocking", Options = {
			{ Key = "Normal" },
			{ Key = "Walls", Name = "Walls (higher hands)", BlockUp = 1.5 },
			{ Key = "Off", Name = "Off", NoBlocks = true },
		} },
		Serves = { Name = "Jump serves", Options = {
			{ Key = "Normal" },
			{ Key = "Strong", Name = "Strong (x1.3)", Serve = 1.3 },
			{ Key = "Soft", Name = "Soft (x0.75)", Serve = 0.75 },
		} },
	},
}

-- Tournaments (the owner, after Bloons TD 6's: "3 rounds with bot fill... you pay to enter"; a
-- fixed prize, never a pot of other players' entries, so no wagering): four cups at a time, one
-- per tier, each with its mode and modifiers, picked anew every Rotate seconds (the shared
-- Cups module, the same everywhere). Pay Entry VP, then play Rounds matches against bot teams
-- of Bots[round], one set to Points each; lose and you're out. All three won pays Prize (VP and
-- Gold); losing the last round pays Consolation. Tournament matches pay nothing else; the 2x VP
-- event, boosts and passes multiply the prize's VP (ProfileService.awardEarned).
Config.Tournament = {
	Rotate = 6 * 3600,
	Rounds = 3,
	Points = 15,
	Timeouts = 1,
	Modes = { 1, 2, 3 },
	-- Strength: which modifiers a cup may roll (Mods of them, Min..Max strength)
	Cups = {
		{ Key = "Bronze", Name = "Bronze Cup", Entry = 50, Bots = { "B", "A", "A" }, Mods = 1, Min = 1, Max = 1, PrizeVP = 110, PrizeGold = 600, Consolation = 20, Color = Color3.fromRGB(205, 127, 70) },
		{ Key = "Silver", Name = "Silver Cup", Entry = 150, Bots = { "A", "S", "S" }, Mods = 1, Min = 1, Max = 2, PrizeVP = 360, PrizeGold = 1800, Consolation = 60, Color = Color3.fromRGB(190, 200, 215) },
		{ Key = "Gold", Name = "Gold Cup", Entry = 250, Bots = { "A", "S", "S+" }, Mods = 1, Min = 2, Max = 3, PrizeVP = 600, PrizeGold = 3000, Consolation = 100, Color = Color3.fromRGB(255, 200, 60) },
		{ Key = "Champion", Name = "Champion Cup", Entry = 600, Bots = { "S", "S+", "S+" }, Mods = 2, Min = 2, Max = 3, PrizeVP = 1700, PrizeGold = 8000, Consolation = 250, Color = Color3.fromRGB(255, 80, 120) },
	},
	-- what a modifier does: Add (stat points for everyone), Height (cm for everyone: reach and hit
	-- zones), Stamina / OppStamina (every team's pool, or the bot team's, times this),
	-- SlideCooldown, BlockCharge (block prep time) and BlockJump (block jump height) times this,
	-- OppDeep (the bot team always spikes deep)
	Modifiers = {
		{ Key = "SpringHeels", Name = "Spring Heels", Blurb = "Everyone gets +20 Jump and +10 Attack.", Strength = 1, Add = { Jump = 20, Attack = 10 } },
		{ Key = "PowerSurge", Name = "Power Surge", Blurb = "Everyone gets +15 Attack.", Strength = 1, Add = { Attack = 15 } },
		{ Key = "LightFeet", Name = "Light Feet", Blurb = "Everyone gets +25 Speed.", Strength = 1, Add = { Speed = 25 } },
		{ Key = "Giants", Name = "Giants", Blurb = "All players are taller: higher reach, bigger zones.", Strength = 1, Height = 12 },
		{ Key = "Marathon", Name = "Marathon", Blurb = "All players' stamina increases.", Strength = 1, Stamina = 1.5 },
		{ Key = "QuickSlides", Name = "Quick Slides", Blurb = "Sliding cooldowns are reduced.", Strength = 1, SlideCooldown = 0.4 },
		{ Key = "FastHands", Name = "Fast Hands", Blurb = "Block prep speed is increased.", Strength = 1, BlockCharge = 0.5 },
		{ Key = "IronWill", Name = "Iron Will", Blurb = "The opponent team's stamina increases.", Strength = 2, OppStamina = 1.6 },
		{ Key = "LowNet", Name = "Grounded", Blurb = "All players' block jumps are lowered.", Strength = 2, BlockJump = 0.75 },
		{ Key = "Exhausted", Name = "Exhausted", Blurb = "Extremely reduced stamina for everyone.", Strength = 3, Stamina = 0.45 },
		{ Key = "DeepSpike", Name = "Deep Spike", Blurb = "The opponent always spikes deep.", Strength = 3, OppDeep = true },
	},
}

-- The Halloween event (the owner, 2026-10-14, after Spike Cross's Kingmaker, Western and Tiger
-- Eyes events), until Ends (unix; the end of November 11 in the US Central time zone). The shared
-- Halloween module holds its rules.
--   Match       a daily Halloween Match against the AI: Stages stages of Points points, one set
--               each (the tournament flow: LobbyService takes the run stage to stage). Before each
--               stage the roulette spins through the deck and stops on Offers cards; you pick one,
--               Picks times a stage (2 cards in stage 1, all 4 in stage 2). Win a stage to go on;
--               losing ends the run. Friends in your server can join the run (Mode a side).
--   Difficulties  the bot level and how many cards the AI team takes a stage (AiCards); a clear's
--               Candy: Candy for the first clear of that difficulty each event day (DayOffset: the
--               day turns at midnight US Central), Repeat for later ones, StageOne for a run that
--               won stage 1 and lost stage 2
--   Cards       the deck (50+). Kind: Ability (gives its ability and a buff; one at a time, a new one
--               replaces the old), Stat, Team (every teammate), Curse (the other team) and Rule.
--               Target: who it hits (Self, Team, Foes; Ability, Stat and Rule are Self). Effects:
--               Add (stat points), Height (cm), Mul (every stat x), PerPoint (stat points per point
--               the other team has this set, like Rising Sun), SpikeMul and ServeMul (spike and jump
--               serve km/h x), SpikeReach (the spike zone x), Block (the block box's extra reach,
--               HitLogic.blockBox), Stuff (added to the stuff check), DrainTake (the drain your
--               receives cost your team x), DrainDeal (the drain your attacks cost them x), Pool (the
--               team's stamina pool x). Rarity weights the roulette (Weights) and colours the card.
--               AiOnly / NoAi: who may draw it.
--   Candy       the event currency: from clears, spent on the banner and the Candy shop. It stays
--               after the event.
--   Banner      limited Halloween cosmetics, recruited with VP or Candy (Costs). Its own rarity
--               Weights; every pull is Scout points toward picking one item outright (each item's
--               Scout cost, Spike Cross's Pick-Up Scout). A duplicate cosmetic pays DupCandy; the
--               Reaper skin stacks (Skins).
--   Shop        Candy prices; Limit buys a player over the event (nil: no limit)
--   Skins       per-character skins: each copy is applied to one character for good (any
--               character); it can be switched off and on for that character at any time
--               (profile.skins). The Reaper: a scythe for the hitting hand and the Souls trail,
--               only with the skin.
-- The Rest in Peace score effect's gravestone (the owner, 2026-10-15: "A grave score explosion similar
-- to giant stomp. Players can customize text and add image URL to the tombstone. Default is just
-- player name"): your epitaph, up to TextMax characters through Roblox's text filter (none: your
-- name), and a picture: any Roblox image or decal, by its id or a link to it (Halloween.graveImage).
Config.Grave = { TextMax = 40 }

-- The S+ characters' lines, shown on their recruit (the owner, 2026-10-15: "a little quote for each
-- s+ recruitment. ill tell you ones i want", after The Spike's): by roster id; one without a line
-- just isn't quoted.
Config.Quotes = {
	yejun = "From above the net there is no mercy... only descent.",
}

-- The Colosseum (the owner, 2026-11-14: "repurpose halloween mode into a permanent colloseum mode,
-- just like the spike cross"): the Halloween Match's engine (its cards, the roulette, the AI's
-- hands) as a permanent run of Stages on the Colosseum court, as in The Spike Cross's Volleyball
-- Colosseum: a Life pool the whole run (every point the other team scores costs one; at 0 the run
-- is over), a path to pick before each stage after the first (Nodes: a Match, an Elite team for
-- more, or a Rest), the All-Star at the end, cards after every win, and a Final Reward that grows
-- with every stage and card, paid in Laurels (the old Candy, the same purse) for the first
-- RewardedRuns runs a day, RepeatShare of it after. The Halloween banner and skins below stay
-- closed (Ends); the shop is the Colosseum's for good. Internal names stay Halloween.
Config.Halloween = {
	Name = "Colosseum",
	Ends = 1794463200, -- 2026-11-12 06:00 UTC: the end of November 11 in Chicago (restarted for the Volleyball Rush rerelease; was November 2)
	DayOffset = -6 * 3600, -- event days turn at midnight in Chicago (UTC-6 from November 1)
	Mode = 3,
	Points = 7,
	Stages = 5,
	Picks = 1, -- cards after each win (Elite: Nodes.Elite.Picks)
	StartPicks = 2, -- before stage 1
	MaxHand = 8, -- the most cards a hand holds
	Offers = 3,
	Life = 20, -- the run's Life: every point the other team scores costs one
	RestHeal = 6, -- a Rest gives back this much (up to Life)
	RewardedRuns = 2, -- runs a day that pay the whole Final Reward (The Spike Cross: "Rewards left to claim 2/2")
	RepeatShare = 0.3, -- what later runs that day pay of it
	FailShare = 0.5, -- what a run that ends early pays of what it had built up
	CardReward = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }, -- added to the Final Reward for every card picked
	PathTime = 20, -- seconds for the host to pick a path before the first is taken
	-- what can stand on the path (Kind: Match plays, Rest heals). Bots / AiCards: the difficulty's
	-- (Difficulties) plus these; Reward: x the difficulty's StageReward
	Nodes = {
		Match = { Name = "Match", Kind = "Match", Reward = 1, Blurb = "A team at your difficulty." },
		Elite = { Name = "Elite", Kind = "Match", Reward = 1.6, Elite = true, ExtraAi = 1, Picks = 2, Blurb = "A stronger team with an extra card: more Laurels and 2 cards after the win." },
		Rest = { Name = "Rest", Kind = "Rest", Blurb = "No match: get back Life." },
		AllStar = { Name = "All-Star", Kind = "Match", Reward = 2.5, Boss = true, ExtraAi = 2, Blurb = "The last stage: the best team in the Colosseum." },
	},
	PathNodes = { "Match", "Elite", "Rest" },
	-- ability cards a hand can hold beside the character's own ability (the owner, 2026-10-15: "you
	-- can stack up to 2 abilities alongside your main one"); with two, no more are offered
	MaxAbilityCards = 2,
	PickTime = 15, -- seconds for a pick before one of the offers is taken for you at random (the owner, 2026-10-21: "an automatic random card picker after say 15 seconds"; was 30, the first)
	SpinTime = 3.2, -- the roulette's scroll on the client before it stops on the offers (the owner: "a scrolling cards motion for rolls")
	Timeouts = 1,
	Court = "Colosseum",
	-- Bots, Elite, Boss: the bots' tier at a Match, an Elite and the All-Star; AiCards: the AI's cards
	-- a stage; StageReward: Laurels a stage cleared adds to the Final Reward (x its node's Reward).
	-- (Candy, Repeat, StageOne: the Halloween Match's old payouts, unused.)
	Difficulties = {
		{ Key = "Easy", Name = "Bronze", Bots = "B", Elite = "A", Boss = "S", AiCards = 0, StageReward = 5, Candy = 20, Repeat = 8, StageOne = 4, Color = Color3.fromRGB(205, 127, 50) },
		{ Key = "Normal", Name = "Silver", Bots = "A", Elite = "S", Boss = "S+", AiCards = 1, StageReward = 8, Candy = 30, Repeat = 12, StageOne = 6, Color = Color3.fromRGB(200, 210, 225) },
		{ Key = "Hard", Name = "Gold", Bots = "S+", Elite = "S+", Boss = "S+", AiCards = 2, StageReward = 12, Candy = 45, Repeat = 18, StageOne = 9, Color = Color3.fromRGB(255, 200, 60) },
	},
	Weights = { Common = 50, Rare = 30, Epic = 15, Legendary = 5 },
	Kinds = {
		Ability = { Name = "Ability", Color = Color3.fromRGB(255, 200, 60) },
		Stat = { Name = "Stat", Color = Color3.fromRGB(255, 140, 30) },
		Team = { Name = "Team", Color = Color3.fromRGB(90, 200, 120) },
		Curse = { Name = "Curse", Color = Color3.fromRGB(170, 80, 230) },
		Rule = { Name = "Rule", Color = Color3.fromRGB(80, 170, 255) },
	},
	Cards = {
		-- ability cards: one per ability (Config.AbilityOrder), each with a buff that suits it
		-- (the owner: "thunderspiker card gives you ability to thunderspike at 4m alongside +10 jump
		-- boost. rally cry, +50 to all stats")
		{ Key = "aThunder", Kind = "Ability", Ability = "Thunder", Rarity = "Epic", Add = { Jump = 10 } },
		{ Key = "aAzure", Kind = "Ability", Ability = "Azure", Rarity = "Epic", Add = { Attack = 10, Jump = 5 } },
		{ Key = "aFeral", Kind = "Ability", Ability = "Feral", Rarity = "Epic", Add = { Attack = 12 } },
		{ Key = "aEnflamed", Kind = "Ability", Ability = "Enflamed", Rarity = "Legendary", Add = { Jump = 10 } },
		{ Key = "aZeroPoint", Kind = "Ability", Ability = "ZeroPoint", Rarity = "Legendary", Add = { Attack = 8, Speed = 5 } },
		{ Key = "aCorona", Kind = "Ability", Ability = "Corona", Rarity = "Legendary", Add = { Jump = 10 } },
		{ Key = "aSquall", Kind = "Ability", Ability = "Squall", Rarity = "Legendary", Add = { Speed = 15 } },
		{ Key = "aIronclad", Kind = "Ability", Ability = "Ironclad", Rarity = "Legendary", Add = { Defense = 15 } },
		{ Key = "aAdrenaline", Kind = "Ability", Ability = "Adrenaline", Rarity = "Rare", Add = { Defense = 10 } },
		{ Key = "aIronWall", Kind = "Ability", Ability = "IronWall", Rarity = "Rare", Add = { Jump = 8, Defense = 5 } },
		{ Key = "aChainReaction", Kind = "Ability", Ability = "ChainReaction", Rarity = "Rare", Add = { Speed = 10 } },
		{ Key = "aVector", Kind = "Ability", Ability = "Vector", Rarity = "Rare", Add = { Speed = 8, Attack = 5 } },
		{ Key = "aFeatherfall", Kind = "Ability", Ability = "Featherfall", Rarity = "Rare", Add = { Speed = 8, Defense = 5 } },
		{ Key = "aTurnabout", Kind = "Ability", Ability = "Turnabout", Rarity = "Rare", Add = { Attack = 8 } },
		{ Key = "aFallingStar", Kind = "Ability", Ability = "FallingStar", Rarity = "Rare", Add = { Speed = 8, Jump = 5 } },
		{ Key = "aRisingSun", Kind = "Ability", Ability = "RisingSun", Rarity = "Rare", Add = { Attack = 5, Defense = 5 } },
		{ Key = "aRallyCry", Kind = "Ability", Ability = "RallyCry", Rarity = "Legendary", Add = { Attack = 50, Defense = 50, Speed = 50, Jump = 50 } },
		{ Key = "aCounter", Kind = "Ability", Ability = "Counter", Rarity = "Epic", Add = { Defense = 12 } },
		{ Key = "aPlunge", Kind = "Ability", Ability = "Plunge", Rarity = "Epic", Add = { Attack = 10 } },
		{ Key = "aSkyward", Kind = "Ability", Ability = "Skyward", Rarity = "Epic", Add = { Jump = 12 } },
		{ Key = "aTyrant", Kind = "Ability", Ability = "Tyrant", Rarity = "Legendary", Add = { Speed = 12 } },
		{ Key = "aSunshine", Kind = "Ability", Ability = "Sunshine", Rarity = "Epic", Add = { Defense = 12 } },
		-- stat cards: plain buffs, trade-offs, height
		{ Key = "PumpkinPower", Name = "Gladiator's Might", Kind = "Stat", Rarity = "Common", Add = { Attack = 20 } },
		{ Key = "BatWings", Name = "Eagle's Leap", Kind = "Stat", Rarity = "Common", Add = { Jump = 20 } },
		{ Key = "GhostStep", Name = "Charioteer's Pace", Kind = "Stat", Rarity = "Common", Add = { Speed = 25 } },
		{ Key = "BoneArmor", Name = "Bronze Shield", Kind = "Stat", Rarity = "Common", Add = { Defense = 25 } },
		{ Key = "WitchBrew", Name = "Champion's Blessing", Kind = "Stat", Rarity = "Rare", Add = { Attack = 10, Defense = 10, Speed = 10, Jump = 10 } },
		{ Key = "BlackCat", Name = "Lion's Pounce", Kind = "Stat", Rarity = "Common", Add = { Attack = 12, Speed = 12 } },
		{ Key = "WerewolfMoon", Name = "Titan's Fury", Kind = "Stat", Rarity = "Rare", Add = { Attack = 15, Jump = 15 } },
		{ Key = "CandyRush", Name = "Victory Lap", Kind = "Stat", Rarity = "Common", Add = { Speed = 20, Jump = 10 } },
		{ Key = "VampireBite", Name = "Berserker", Kind = "Stat", Rarity = "Rare", Add = { Attack = 35, Defense = -20 } },
		{ Key = "ZombieHide", Name = "Iron Hide", Kind = "Stat", Rarity = "Rare", Add = { Defense = 40, Speed = -15 } },
		{ Key = "BansheeWail", Name = "Sprinter's Gamble", Kind = "Stat", Rarity = "Rare", Add = { Speed = 40, Jump = -10 } },
		{ Key = "SkeletonSpring", Name = "Reckless Vault", Kind = "Stat", Rarity = "Rare", Add = { Jump = 35, Defense = -15 } },
		{ Key = "GraveGiant", Name = "Colossus", Kind = "Stat", Rarity = "Epic", Height = 15 },
		{ Key = "HauntedStilts", Name = "Stilt Walker", Kind = "Stat", Rarity = "Rare", Height = 25, Add = { Speed = -10 } },
		{ Key = "MonsterMash", Name = "Emperor's Favor", Kind = "Stat", Rarity = "Epic", Mul = 1.08 },
		-- team cards: every teammate
		{ Key = "Coven", Name = "Legion", Kind = "Team", Target = "Team", Rarity = "Rare", Add = { Attack = 10 } },
		{ Key = "HauntedHouse", Name = "Phalanx", Kind = "Team", Target = "Team", Rarity = "Rare", Add = { Defense = 12 } },
		{ Key = "GraveyardShift", Name = "Arena Spirit", Kind = "Team", Target = "Team", Rarity = "Rare", Add = { Jump = 10 } },
		{ Key = "MidnightRun", Name = "Marching Drums", Kind = "Team", Target = "Team", Rarity = "Common", Add = { Speed = 12 } },
		{ Key = "TrickOrTreat", Name = "Crowd's Roar", Kind = "Team", Target = "Team", Rarity = "Epic", Add = { Attack = 6, Defense = 6, Speed = 6, Jump = 6 } },
		{ Key = "PumpkinPatch", Name = "Feast of Rome", Kind = "Team", Target = "Team", Rarity = "Epic", Pool = 1.3 },
		{ Key = "SpiritShield", Name = "Shield Wall", Kind = "Team", Target = "Team", Rarity = "Epic", DrainTake = 0.8 },
		{ Key = "MoonlitCourt", Name = "Senate's Seal", Kind = "Team", Target = "Team", Rarity = "Rare", Height = 8 },
		-- curse cards: the other team
		{ Key = "HexWeakness", Name = "Broken Spear", Kind = "Curse", Target = "Foes", Rarity = "Rare", Add = { Attack = -12 } },
		{ Key = "Cobwebs", Name = "Chains", Kind = "Curse", Target = "Foes", Rarity = "Common", Add = { Speed = -12 } },
		{ Key = "LeadenBones", Name = "Lead Sandals", Kind = "Curse", Target = "Foes", Rarity = "Rare", Add = { Jump = -12 } },
		{ Key = "RottenLuck", Name = "Cracked Shield", Kind = "Curse", Target = "Foes", Rarity = "Common", Add = { Defense = -12 } },
		{ Key = "FogOfDread", Name = "Sandstorm", Kind = "Curse", Target = "Foes", Rarity = "Epic", Add = { Attack = -6, Defense = -6, Speed = -6, Jump = -6 } },
		{ Key = "Withering", Name = "Scorching Sun", Kind = "Curse", Target = "Foes", Rarity = "Epic", Pool = 0.75 },
		{ Key = "ShrinkingCurse", Name = "Humbled", Kind = "Curse", Target = "Foes", Rarity = "Rare", Height = -10 },
		{ Key = "BleedingGuard", Name = "Open Wounds", Kind = "Curse", Target = "Foes", Rarity = "Epic", DrainTake = 1.2 },
		-- rule cards: how the ball plays for you
		{ Key = "JackSmash", Name = "Trident Strike", Kind = "Rule", Rarity = "Rare", SpikeMul = 1.08 },
		{ Key = "PoltergeistServe", Name = "Catapult Serve", Kind = "Rule", Rarity = "Common", ServeMul = 1.12 },
		{ Key = "LongClaws", Name = "Long Spear", Kind = "Rule", Rarity = "Rare", SpikeReach = 1.15 },
		{ Key = "WallOfBones", Name = "Colosseum Wall", Kind = "Rule", Rarity = "Epic", Block = { ReachUp = 1.2, NetExtra = 0.6, OwnDepth = 0.3, OverDepth = 0.4 }, Stuff = 0.06 },
		{ Key = "PhantomHands", Name = "Net of the Retiarius", Kind = "Rule", Rarity = "Rare", Stuff = 0.12 },
		{ Key = "Gravedigger", Name = "Siege Hammer", Kind = "Rule", Rarity = "Rare", DrainDeal = 1.25 },
		{ Key = "GhostlyGuard", Name = "Centurion's Guard", Kind = "Rule", Rarity = "Rare", DrainTake = 0.7 },
		{ Key = "FullMoon", Name = "Thumbs Up", Kind = "Rule", Rarity = "Epic", PerPoint = { Attack = 3, Jump = 2 } },
		{ Key = "NightmareFuel", Name = "Roar of the Crowd", Kind = "Rule", Rarity = "Legendary", PerPoint = { Attack = 2, Defense = 2, Speed = 2, Jump = 2 } },
		{ Key = "SoulHarvest", Name = "Glory or Death", Kind = "Rule", Rarity = "Legendary", SpikeMul = 1.05, DrainDeal = 1.15 },
	},
	Candy = { Name = "Laurels", Color = Color3.fromRGB(255, 196, 70) }, -- (Candy's purse, renamed for the Colosseum)
	-- the banner: limited Halloween cosmetics (Config.Cosmetics' items with Limited = "Halloween")
	-- and the Reaper skin
	Banner = {
		Name = "Halloween Night",
		Blurb = "Limited Halloween cosmetics, and two Mythic skins: the Reaper and the Fallen Angel. Every recruit is 1 scout point: spend them to pick an item outright.",
		Costs = { VP = { [1] = 80, [10] = 800 }, Candy = { [1] = 25, [10] = 250 } }, -- (VP 80 a recruit, 800 for ten: the owner, 2026-10-17; was 60 and 600)
		-- (the owner, 2026-10-29, the rerelease resetting everyone's progress: "buff the halloween
		-- rates": each skin 0.3% again, Legendary 15%; were Rare 60.4, Epic 28, Legendary 11.4 and
		-- Mythic 0.2, each skin 0.1%, the owner's 2026-10-17 cut)
		Weights = { Rare = 52.4, Epic = 32, Legendary = 15, Mythic = 0.6 },
		ScoutPerPull = 1,
		DupCandy = { Rare = 4, Epic = 8, Legendary = 20, Mythic = 40 },
		-- what's on it ({ kind, key, scout cost }); the Reaper's rarity is in Skins
		Items = {
			{ Kind = "Skin", Key = "Reaper", Scout = 150 },
			{ Kind = "Skin", Key = "FallenAngel", Scout = 150 }, -- (the two share the Mythic weight)
			{ Kind = "Room", Key = "Haunted", Scout = 90 }, -- (Home's background: Config.Rooms)
			{ Kind = "Card", Key = "Halloween2026", Scout = 90, Rarity = "Epic" }, -- (a player card: Config.Cards)
			{ Kind = "Effect", Key = "PumpkinBurst", Scout = 90 },
			{ Kind = "Effect", Key = "GhostSwarm", Scout = 90 },
			{ Kind = "Effect", Key = "Grave", Scout = 120 },
			{ Kind = "Ball", Key = "Pumpkin", Scout = 90 },
			{ Kind = "Ball", Key = "WitchHat", Scout = 60 },
			{ Kind = "Jump", Key = "JackOLantern", Scout = 90 },
			{ Kind = "Jump", Key = "BatSwarm", Scout = 60 },
			{ Kind = "Jump", Key = "GraveMist", Scout = 30 },
			{ Kind = "Trail", Key = "Bats", Scout = 60 },
			{ Kind = "Color", Key = "CandyCorn", Scout = 30 },
			{ Kind = "Color", Key = "Bloodmoon", Scout = 60 },
			{ Kind = "Color", Key = "Pumpkin", Scout = 30 },
			{ Kind = "Color", Key = "Ectoplasm", Scout = 30 },
		},
	},
	-- the Candy shop (Limit: buys a player over the event)
	Shop = {
		{ Key = "Lucky1", Name = "1 lucky spin", Price = 120, Limit = 5, Grant = { Lucky = 1 } },
		{ Key = "Gold", Name = "2,500 Gold", Price = 40, Limit = 20, Grant = { Gold = 2500 } },
		{ Key = "VP", Name = "150 VP", Price = 75, Limit = 10, Grant = { VP = 150 } },
		{ Key = "CandyCorn", Name = "Candy Corn spike colour", Price = 160, Item = { Kind = "Color", Key = "CandyCorn" } },
		{ Key = "GraveMist", Name = "Grave Mist jump", Price = 160, Item = { Kind = "Jump", Key = "GraveMist" } },
		{ Key = "PumpkinColor", Name = "Pumpkin spike colour", Price = 120, Item = { Kind = "Color", Key = "Pumpkin" } },
	},
	Skins = {
		Reaper = {
			Name = "Reaper",
			Rarity = "Mythic",
			Blurb = "Jaeil's skin, and Jaeil with it if he isn't yours yet: he spikes with a scythe, souls streaming behind the ball. Swap it on and off any time on his page.",
			Trail = "Souls", -- the trail it wears (Config.Cosmetics.Trail; only with the skin)
			Color = Color3.fromRGB(150, 220, 255),
			-- the only character it fits (the owner, 2026-10-15: "restrict the skin to only taeho
			-- now"); a copy applied to anyone else comes back free, and a second copy pays DupCandy
			Chars = { "taeha" },
			Tint = Color3.fromRGB(150, 100, 255), -- its page and pull glow: void violet
		},
		-- (the owner, 2026-10-15: "fallen angel yejun. he has one broken wing, similar to angel. he
		-- cannot equip other jump cosmetics. he has a purple and black thunder spike and when he jumps,
		-- arms are summoned from the underworld and drag him back down. put him alongside taeho in the
		-- skins gatcha"): the broken wing on his back (Skins), Jump in place of his equipped jump,
		-- and his thunder spikes in Thunder's violet on black
		FallenAngel = {
			Name = "Fallen Angel",
			Rarity = "Mythic",
			Blurb = "YeJun's skin, and YeJun with it if he isn't yours yet: one broken black wing, lightning in violet and black, arms from the underworld that drag him back down on every jump, and a score that drags the other team under. Swap it on and off any time on his page.",
			Jump = "Underworld", -- (Config.Cosmetics.Jump; only with the skin, whatever jump he has on)
			Score = "Underworld", -- his score effect in place of his own (the owner, 2026-10-16: "if he scores, he has a custom effect where he drags the opponents under the map")
			Thunder = Color3.fromRGB(150, 70, 255), -- his thunder spikes' colour (black underneath)
			Color = Color3.fromRGB(190, 150, 255),
			Chars = { "yejun" },
			Tint = Color3.fromRGB(120, 60, 220),
			Pull = "Crack", -- his recruit pull: the screen cracks and the arms crawl out (MenuController's Extra.crackPull; else the Reaper's scythe)
		},
		-- the Winter collab's skins (Limited = "Winter": from the Wild Card banner and the Winter
		-- Pass, never the Halloween banner). The owner, 2026-11-16: "viktor sets with christmas lights
		-- stringing the path, and the ball glows bluish like snow not purple. kuro's dragon is replaced
		-- by santa's sleigh and the sky cracks are snow and icicles... finally laith skin. make
		-- something up for that. and make sure their recruit animations are exclusive". Their looks
		-- are WinterSkins' (client); Pull names their recruit pull there.
		TwinkleLights = {
			Name = "Twinkle Lights",
			Rarity = "Mythic",
			Limited = "Winter",
			Blurb = "Viktor's skin, and Viktor with it if he isn't yours yet: his Vector Sets glow snow blue and string a line of Christmas lights along the ball's path. On the Wild Card banner. Swap it on and off any time on his page.",
			VectorColor = Color3.fromRGB(150, 225, 255), -- his sets' glow in place of Vector's violet
			Color = Color3.fromRGB(150, 225, 255),
			Chars = { "ilya" },
			Tint = Color3.fromRGB(70, 150, 255),
			Pull = "Lights", -- the screen strung with Christmas lights that light up in turn, then him
		},
		SleighRide = {
			Name = "Sleigh Ride",
			Rarity = "Mythic",
			Limited = "Winter",
			Blurb = "Kuro's skin, and Kuro with it if he isn't yours yet: Santa's sleigh dives out of the sky in place of his dragon, the sky cracks into snow and icicles, and his fire burns ice blue. On the Wild Card banner. Swap it on and off any time on his page.",
			Fire = Color3.fromRGB(120, 210, 255), -- his flames in place of Enflamed's orange
			Color = Color3.fromRGB(235, 60, 70),
			Chars = { "kuro" },
			Tint = Color3.fromRGB(220, 40, 56),
			Pull = "Sleigh", -- a sleigh and its reindeer dash across a night sky, bells ringing
		},
		StarTopper = {
			Name = "Star Topper",
			Rarity = "Mythic",
			Limited = "Winter",
			-- (behind door 25 of the advent calendar, Christmas morning, and nowhere else: the owner,
			-- 2026-11-18, "this should be huge, maybe we restructure one of the 3 s+ skins into the 25th
			-- day", then "make laith the 25th day skin")
			Blurb = "Laith's skin, and Laith with it if he isn't yours yet: his Corona's sun becomes the gold star off the top of a Christmas tree, his path a garland of lights, and a Sundive bursts into ornaments. Behind door 25 of the advent calendar. Swap it on and off any time on his page.",
			Color = Color3.fromRGB(255, 214, 90),
			Chars = { "laith" },
			Tint = Color3.fromRGB(40, 160, 80),
			Pull = "Tree", -- a Christmas tree grows up the screen, ornaments on, the star lights and bursts
		},
		-- Horang's (the owner, 2026-11-18: "come up with something for horang, it was voted 4th in line
		-- for christmas skins"): Candy Claw. Her claw rakes in candy-cane stripes, red and white; the
		-- mark on whoever receives her is a candy cane's; RAWR! bursts peppermint swirls and snow
		-- (WinterSkins.candy*). From the Blizzard event mission
		CandyClaw = {
			Name = "Candy Claw",
			Rarity = "Mythic",
			Limited = "Winter",
			Blurb = "Horang's skin, and Horang with it if she isn't yours yet: her claw rakes in candy-cane stripes, the mark she leaves is a candy cane, and RAWR! bursts into peppermint swirls and snow. The Winter Pass's last tier. Swap it on and off any time on her page.",
			Color = Color3.fromRGB(226, 30, 50),
			Chars = { "horang" },
			Tint = Color3.fromRGB(226, 30, 50),
			Pull = "Candy", -- three candy-striped claw marks rip across a snowy night, a roar, then her
		},
	},
	SkinOrder = { "Reaper", "FallenAngel", "TwinkleLights", "SleighRide", "StarTopper", "CandyClaw" },
	MaxCopies = 999,
}

-- Home rooms (src/shared/Rooms.lua): the menu room you stand in on Home, Players and the player
-- pages, swapped from Home's Decorate button (The Spike's; the owner, 2026-10-15: "add a
-- halloween style background you can also spin for kind of like how you can swap this").
-- SceneController draws each one's decorations.
Config.Rooms = {
	Default = "Clubhouse",
	Order = { "Clubhouse", "Neon", "Haunted", "Christmas" },
	List = {
		Clubhouse = { Name = "Rush Arena", Default = true, Blurb = "The pro hall: a maple court under the lights, the crowd, the banners and the big screen." }, -- (key kept for saves; was the club room)
		Neon = { Name = "Neon Court", Default = true, Blurb = "Center court at night: the crowd in the dark, the big screen and the stage lights sweeping." },
		-- the Winter event's (the owner, 2026-11-17: "i want a christmas menu... you can stick this
		-- one in the battlepass"): the Winter Pass's premium tier 26
		Christmas = { Name = "Christmas Eve", Rarity = "Legendary", Limited = "Winter", Blurb = "Home in a snowy clearing on Christmas Eve: a log lodge with its windows warm, a big lit tree with presents, snowy pines, a snowman, an aurora and snow falling." },
		Haunted = { Name = "Haunted Forest", Rarity = "Legendary", Limited = "Halloween", Blurb = "Home out in a moonlit forest: the clubhouse a haunted cabin among dead trees, a graveyard, a bubbling cauldron, jack-o'-lanterns, fog and a huge orange moon." },
	},
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
			Blurb = "The home hall: a maple court under bright lights, banners in the high windows.",
			Stands = {},
			Crowd = 1,
		},
		Beach = {
			Name = "Sunset Beach",
			Blurb = "A beach tour stadium: wrapped grandstands on the sand, palms and the sea behind.",
			-- (the owner, 2026-10-29: "quite plain", then "the beach doesn't need huge audience, i like
			-- how you could see the dock ... dont sacrifice the actual stage for more seats": low
			-- stands, a slim wrapped band and flags on top, the sea and the pier in view)
			Stands = { Rows = 5 },
			Crowd = 0.9,
		},
		Colosseum = {
			Name = "Colosseum",
			Blurb = "Stone tiers, arches and braziers at dusk.",
			Stands = { Rows = 14, RowRise = 1.9 },
			Crowd = 0.8,
		},
		Nationals = {
			Name = "Nationals",
			Blurb = "The championship hall: packed stands, bright lights.",
			Stands = { Rows = 14 },
			Crowd = 0.85,
		},
		Rooftop = {
			Name = "Night Rooftop",
			Blurb = "A court on the roof, the city lit up behind it.",
			Stands = { Rows = 4 }, -- (low: the city is the scene)
			Crowd = 0.9,
		},
		-- Halloween's (the owner, 2026-10-15: "and with that a halloween court"): the Halloween
		-- Match's (Config.Halloween.Court), and a pick for custom lobbies; not in Rotation
		Haunted = {
			Name = "Haunted Forest",
			Blurb = "An old plank court in a clearing at midnight: dead trees, jack-o'-lanterns, a graveyard and a huge orange moon.",
			Stands = { Rows = 4 }, -- (low: the forest is the scene)
			Crowd = 0.75,
		},
		-- the Winter event's (the owner, 2026-11-15: "christmas courts"): the Winter Match's
		-- (Config.Winter.Match.Court), and a pick for custom lobbies; not in Rotation
		Winter = {
			Name = "Snowfall Lodge",
			Blurb = "A court in a snowy clearing on a winter night: Christmas lights, snowmen, a giant lit tree and a log lodge.",
			Stands = { Rows = 4 }, -- (low: the clearing is the scene)
			Crowd = 0.75,
		},
	},
}

-- Leaderboards (the Leaderboards module ranks them): global OrderedDataStores, one per stat,
-- written from each player's career counters; a server-only board when those can't be reached.
Config.Leaderboards = {
	Boards = {
		-- the owner, 2026-10-22: "make a rank elo leaderboard": this season's rank points (Config.Ranked),
		-- shown with the rank; Seasonal: a store of its own each season (the RP start over), Live: RP
		-- go down too, so a player's fresh value replaces the stored one
		{ Key = "ranked", Name = "Ranked", Unit = "RP", Ranked = true, Seasonal = true, Live = true, Empty = "Nobody has played ranked this season yet." },
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
		-- the owner: "a playtime leaderboard": seconds spent in the game (ProfileService adds them up
		-- while a player is here); Time: shown as hours and minutes (Leaderboards.format)
		{ Key = "playTime", Name = "Playtime", Unit = "", Time = true, Empty = "Nobody has played yet." },
		-- the Winter event's (Config.Winter.Board): Winter Match wins, a Blizzard one worth most. Only
		-- while that event is switched on (taken off the list below the Winter config otherwise)
		{ Key = "winter", Name = "Winter event", Unit = "points", Limited = "Winter", Empty = "Win a Winter Match to get on this board." },
	},
	StorePrefix = "SpikeRushBoard_v1_",
	Top = 50,
	RefreshInterval = 120, -- seconds between reading the global boards while someone has them open
	-- and between background reads (for the names' entrance places) when nobody does: the reads ran
	-- into the experience's OrderedDataStore limit (GetSortedAsync throttled, 2026-10-25), and an
	-- AFK Lounge server never reads them
	IdleRefresh = 360,
	FlushInterval = 60, -- seconds between writing changed players' scores
}

-- Playtime rewards (the owner: "10 min is 80vp, 1,000 gold, 30 min is 200 vp, 5,000 gold 3 lucky
-- spins, 1 hr is 10,000 gold, 5 lucky spins, 400 vp"): each tier pays its own grant once a day, the
-- moment a player has been in the game that long today (ProfileService.tickPlayTime). The day turns
-- at midnight where each player is (their client sends its UTC offset: ProfileService "tz"; the day
-- only moves forward, so the offset can't be used for a second reset).
-- Parties (the owner, 2026-10-21: "add a proper party system so you can actually queue ranked, but
-- also regular queues"): up to Max players here; an invite lasts InviteSeconds.
Config.Party = {
	Max = 3,
	InviteSeconds = 60,
}

-- Ranked (the owner, 2026-10-21: "begin work on a ranked mode. the ranks climb from bronze silver gold
-- platinum diamond mighty Almighty"; real players only, one rank across every mode, monthly
-- seasons, three divisions a rank). Rank points (RP): each division is PerDivision of them (Bronze
-- I from 0, Diamond III to 1,499: divisions climb I, II, III); Mighty from MightyAt, Almighty from AlmightyAt, one tier each. A
-- win pays Win and a loss costs Loss, both moved by how much stronger the other team is (Spread RP
-- for each point, between Min and Max); never below 0. Seasons follow the calendar (Chicago time):
-- Season 1 runs to the end of November 2026, then one a month; a new season keeps ResetFrac of your
-- RP and records the last one (its card on the Career panel). Before every ranked match each team
-- bans BansPerTeam characters (BanTime seconds; the owner: "implement rank bans. one for each team",
-- then "allow 2 bans per side", then back to one): nobody plays them that match.
Config.Ranked = {
	Ranks = {
		{ Key = "Bronze", Name = "Bronze", Divisions = 3, Color = Color3.fromRGB(205, 120, 70) },
		{ Key = "Silver", Name = "Silver", Divisions = 3, Color = Color3.fromRGB(200, 212, 228) },
		{ Key = "Gold", Name = "Gold", Divisions = 3, Color = Color3.fromRGB(255, 200, 50) },
		{ Key = "Platinum", Name = "Platinum", Divisions = 3, Color = Color3.fromRGB(80, 225, 200) },
		{ Key = "Diamond", Name = "Diamond", Divisions = 3, Color = Color3.fromRGB(90, 180, 255) },
		{ Key = "Mighty", Name = "Mighty", Divisions = 1, Color = Color3.fromRGB(190, 90, 255) },
		{ Key = "Almighty", Name = "Almighty", Divisions = 1, Color = Color3.fromRGB(255, 70, 70) },
	},
	PerDivision = 100,
	MightyAt = 1500,
	AlmightyAt = 2000,
	-- an even match's RP, then (the owner, 2026-10-21: "you lose less and lose more based on rank
	-- differentials, and the higher you climb the less you gain and more you lose"): the other team's
	-- average RP against yours moves it by up to DiffWeight either way at DiffSpan apart (a win over
	-- a stronger team pays more, a loss to one costs less, and the other way round), then your own
	-- rank's Climb multipliers (gain, loss): generous low, harsh at the top. Kept in Min..Max.
	Win = 25,
	Loss = 20,
	DiffSpan = 400, -- four divisions apart: the whole DiffWeight
	DiffWeight = 0.6,
	Climb = {
		Bronze = { 1.3, 0.6 },
		Silver = { 1.2, 0.75 },
		Gold = { 1.1, 0.9 },
		Platinum = { 1.0, 1.0 },
		Diamond = { 0.9, 1.15 },
		Mighty = { 0.8, 1.3 },
		Almighty = { 0.7, 1.45 },
	},
	Min = 4,
	Max = 55,
	-- leaving a ranked match early (the owner, 2026-10-21: "add a leaver penalty", "it is removed if
	-- you rejoin though"): the loss, ExtraRp more, and the ranked queue locked for Bans[n] seconds,
	-- n your leaves in the last Window (the last step for any more). Rejoin the match while it's
	-- still on (offered for RejoinSeconds) and all of it comes back.
	Leave = {
		ExtraRp = 15,
		Bans = { 120, 300, 900, 1800, 3600 },
		Window = 86400,
		RejoinSeconds = 900,
	},
	ResetFrac = 0.5,
	Season1Ends = { 2026, 12 }, -- (year, month): Season 1 ends as that month begins
	DayOffset = -5 * 3600, -- Chicago, near enough (like the Halloween days)
	BanTime = 20, -- (25 with two bans a team)
	-- then each player picks who they play (the owner, 2026-10-22: "allow a character picker before
	-- you queue ranked match", "after bans"): PickTime seconds, over sooner once every player is ready
	PickTime = 20,
	BansPerTeam = 1, -- (the owner, 2026-10-22: "change the bans per rank team to 1"; was 2 from 2026-10-21)
	Modes = { 1, 2, 3 },
	HistoryMax = 24, -- past seasons kept on a profile
}

-- Clans (the owner, 2026-10-21: "start working on clans", after another game's guilds): anyone
-- makes one for CostVP or with the Clan Founder game pass (PassId), no other requirement; the tag
-- is TagMin to TagMax letters or digits and unique (it's the clan's key in Store); the owner sets a
-- minimum of wins to join (no level). A member's stats count from the day they join (their career
-- record minus where it stood then): wins, spike kills and the rest, worth Points each, all adding
-- up to the clan's points; the owner (and officers) spend them on Upgrades. Each member can spend
-- their own share on tag colours (TagColors) for their [TAG] in chat. The clans' leaderboard is
-- BoardStore (points); the top clans' members get the ClanTop3 / ClanNumber1 cards (Config.Cards).
-- No auctions (the owner: "ditch the auction part").
Config.Clans = {
	Store = "SpikeRushClans", -- tag (upper case) -> the clan
	BoardStore = "SpikeRushClanPoints", -- OrderedDataStore: tag -> points
	-- this week's points (the owner, 2026-10-22: "add a weekly point counter for clans too so i can
	-- determine who the highest one is"): an OrderedDataStore a week (WeekStore .. "_" .. week),
	-- tag -> the points its members earned since Monday (WeekOffset: Chicago, like the ranked days)
	WeekStore = "SpikeRushClanWeek",
	WeekOffset = -5 * 3600,
	Topic = "SpikeRushClans", -- MessagingService: a clan changed (its tag), every server re-reads it
	CostVP = 1000,
	PassId = 2061856257, -- the Clan Founder game pass (249 Robux, tools/monetization_manifest.json): founds a clan without VP
	OldPassId = 2044226785, -- the original Spike Rush's Clan Founder pass counts too (Config.Passes.Old)
	TagMin = 2,
	TagMax = 5,
	NameMax = 24,
	DescMax = 140,
	MinWinsMax = 5000,
	BaseCap = 15, -- members, before the Member cap upgrade
	BoardTop = 50,
	RequestsMax = 30,
	-- what each counted stat is worth in points
	Points = { wins = 10, matches = 2, kills = 1, aces = 3, blocks = 2, mvps = 5 },
	StatOrder = { "wins", "matches", "kills", "aces", "blocks", "mvps" },
	StatNames = { wins = "Wins", matches = "Matches", kills = "Spike kills", aces = "Aces", blocks = "Blocks", mvps = "MVPs" },
	-- the owner's upgrades (the owner: "vp gain, coin gain, extra luck, member cap, and more"): level
	-- n costs Base x n x n points; Per is what each level adds (a share of VP or Gold earned, luck,
	-- members); Max levels. Emblem and Intro unlock the clan's own picture and matchup intro.
	Upgrades = {
		{ Key = "VP", Name = "V Point gain", Blurb = "Every member earns more V Points from matches, tournaments and dailies.", Per = 0.02, Max = 10, Base = 250, Show = "pct" },
		{ Key = "Gold", Name = "Gold gain", Blurb = "Every member earns more Gold from matches.", Per = 0.05, Max = 10, Base = 200, Show = "pct" },
		{ Key = "Luck", Name = "Extra luck", Blurb = "Every member's Characters recruits are luckier.", Per = 0.05, Max = 5, Base = 600, Show = "pct" },
		{ Key = "Cap", Name = "Member cap", Blurb = "Room for more members.", Per = 5, Max = 6, Base = 300, Show = "num" },
		{ Key = "Emblem", Name = "Clan emblem", Blurb = "Your own picture for the clan (any Roblox image or decal id), on its page and its intro.", Per = 1, Max = 1, Base = 1000, Show = "unlock" },
		{ Key = "Intro", Name = "Clan intro", Blurb = "When three or more of you play on one team, the matchup intro shows your clan.", Per = 1, Max = 1, Base = 2500, Show = "unlock" },
		-- (the owner, 2026-10-22: "a team jersey feature, where clan owners can upload their own jersey"):
		-- the owner sets a Roblox Shirt and Pants (catalog ids) in Settings; every member wears them in
		-- their matches (ClanService dresses them)
		{ Key = "Jersey", Name = "Team jersey", Blurb = "Your own shirt and pants (any Roblox Shirt or Pants from the catalog), worn by every member in their matches.", Per = 1, Max = 1, Base = 1500, Show = "unlock" },
	},
	-- tag colours a member buys with their own share (Cost points); Colors: one, or a gradient
	TagColors = {
		{ Key = "White", Name = "White", Cost = 0, Colors = { Color3.fromRGB(235, 235, 240) } },
		{ Key = "Orange", Name = "Orange", Cost = 200, Colors = { Color3.fromRGB(255, 140, 30) } },
		{ Key = "Red", Name = "Red", Cost = 200, Colors = { Color3.fromRGB(240, 60, 60) } },
		{ Key = "Green", Name = "Green", Cost = 200, Colors = { Color3.fromRGB(60, 210, 90) } },
		{ Key = "Blue", Name = "Blue", Cost = 200, Colors = { Color3.fromRGB(70, 150, 255) } },
		{ Key = "Pink", Name = "Pink", Cost = 300, Colors = { Color3.fromRGB(255, 110, 200) } },
		{ Key = "Purple", Name = "Purple", Cost = 300, Colors = { Color3.fromRGB(165, 95, 255) } },
		{ Key = "Gold", Name = "Gold", Cost = 750, Colors = { Color3.fromRGB(255, 205, 50) } },
		{ Key = "Fire", Name = "Fire", Cost = 1500, Colors = { Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 120, 20), Color3.fromRGB(230, 30, 30) } },
		{ Key = "Forest", Name = "Forest", Cost = 1500, Colors = { Color3.fromRGB(170, 240, 90), Color3.fromRGB(40, 170, 70), Color3.fromRGB(20, 110, 60) } },
		{ Key = "Ocean", Name = "Ocean", Cost = 1500, Colors = { Color3.fromRGB(120, 230, 255), Color3.fromRGB(40, 140, 255), Color3.fromRGB(60, 60, 220) } },
		{ Key = "Rainbow", Name = "Rainbow", Cost = 3000, Colors = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 170, 40), Color3.fromRGB(250, 230, 60), Color3.fromRGB(70, 210, 90), Color3.fromRGB(70, 150, 255), Color3.fromRGB(170, 90, 255) } },
	},
}

Config.PlayRewards = {
	-- Chicago (UTC-5): no longer the playtime day (that follows each player's own offset), but still
	-- what the AFK Lounge's day (Lounge.day) turns on
	DayOffset = -5 * 3600,
	Tiers = {
		{ Key = "m10", Name = "10 minutes", Minutes = 10, Grant = { VP = 80, Gold = 1000 } },
		{ Key = "m30", Name = "30 minutes", Minutes = 30, Grant = { VP = 200, Gold = 5000, Lucky = 3 } },
		{ Key = "h1", Name = "1 hour", Minutes = 60, Grant = { VP = 400, Gold = 10000, Lucky = 5 } },
	},
}

-- The AFK Lounge (the owner, 2026-10-22: "add an afk chamber", after another game's AFK Lounge):
-- from Home's AFK button, a screen of its own where rewards keep coming while you rest. Every
-- Interval spent inside rolls one of Rewards (the owner, 2026-10-22: "make it roll through
-- possibilites of rewards ... top reward can be a lucky spin, and the bottom line be 30 gold or 10
-- vp ... no roll animation, you just get it"); its Gold and V Points times VipMult with the VIP
-- pass and PremiumMult with Roblox Premium; up to DailyPayouts a day (the day turns with
-- Config.PlayRewards'). Time towards the next payout is kept on the profile, so
-- leaving and coming back carries on. Roblox drops a player after 20 minutes without input: past
-- RefreshAfter idle seconds inside, the server moves them to a fresh server of this place (a
-- teleport), where the lounge opens again and the loading screen skips its click.
Config.Lounge = {
	-- (was 600; the owner, 2026-10-22: "make the afk rewards 1 minute not 10 minutes", then "is there
	-- a better time limit that you decide? maybe 2:30? maybe 4:30?": 4 minutes pays about two thirds
	-- of the VP an hour of matches does, so playing still pays more)
	Interval = 240,
	VipMult = 2,
	PremiumMult = 1.5,
	-- DailyPayouts: a daily limit on payouts when set; none now (was 60, four hours a day: the
	-- owner, 2026-10-25, "make afk chamber infinite rewards")
	DailyPayouts = nil,
	-- what a payout can roll, from the bottom line up to the top reward: Weight is its chance in
	-- percent (they add up to 100), Tier (1 to 5) its colour on the screen, Grant what it gives
	-- (Economy.cleanGrant; boosts in seconds)
	Rewards = {
		{ Weight = 20.5, Tier = 1, Grant = { Gold = 30 } },
		{ Weight = 18, Tier = 1, Grant = { VP = 10 } },
		{ Weight = 13, Tier = 1, Grant = { Gold = 50 } },
		{ Weight = 11, Tier = 1, Grant = { VP = 15 } },
		{ Weight = 8, Tier = 2, Grant = { Gold = 80 } },
		{ Weight = 7, Tier = 2, Grant = { VP = 25 } },
		{ Weight = 5, Tier = 2, Grant = { Gold = 120 } },
		{ Weight = 4, Tier = 2, Grant = { VP = 40 } },
		{ Weight = 3.5, Tier = 3, Grant = { Gold = 200 } },
		{ Weight = 2.5, Tier = 3, Grant = { VP = 60 } },
		{ Weight = 2.5, Tier = 3, Grant = { BoostVP = 5 * 60 } },
		{ Weight = 1.5, Tier = 4, Grant = { Gold = 350 } },
		{ Weight = 1.2, Tier = 4, Grant = { VP = 100 } },
		{ Weight = 1, Tier = 4, Grant = { BoostLuck = 5 * 60 } },
		{ Weight = 0.7, Tier = 4, Grant = { Gold = 600 } },
		{ Weight = 0.4, Tier = 5, Grant = { VP = 200 } },
		{ Weight = 0.2, Tier = 5, Grant = { Lucky = 1 } }, -- (the top reward)
	},
	LogSize = 8, -- the latest rolls the screen's side panel lists
	RefreshAfter = 17 * 60,
	SyncEvery = 20, -- seconds between the server's countdown corrections to the screen
}

-- The tutorial (the Tutorial module has the steps): a 1v1 against a weak bot; finishing every
-- step pays this once.
-- The tutorial: the four practice drills in order (shared/Tutorial), paid once.
Config.Tutorial = {
	RewardVP = 50,
	RewardGold = 1000,
	RewardSpins = 5, -- free x1 recruits (used before V Points)
	-- after the four drills, a short match against bots (the owner, 2026-10-25: "add a short 3
	-- point bot tutorial match at the end of the tutorial"): you and a bot setter, one set to
	-- MatchPoints (win by 1), D-tier bots; it pays nothing and doesn't count for your record
	MatchMode = 2,
	MatchPoints = 3,
	MatchBots = "D",
	MatchDelay = 5, -- seconds on the TUTORIAL COMPLETE card before it starts (its button skips them)
}

-- Beginner mode (the owner, 2026-10-25: "implement a beginner mode, just like tsc. you have slight
-- jump assistance, and where you spike and jump there is a white circle indicator. also, you cant
-- control your aim, rather you always hit in square in the middle so it usually goes midcourt"):
-- Settings' beginner switch, offered in the tutorial (its coach). Your spikes reach ReachMul wider
-- and a mistimed jump or a scrappy contact counts as at least HeightFloor and ContactFloor of a
-- clean one; every spike
-- lands Depth of the way into their side (give or take DepthJitter), whatever the contact; and a
-- white ring on the floor shows where to take off for your team's set (BeginnerGuide). Never in
-- a ranked match (the RankedMatch attribute). Spikes only: serves, sets and receives are as usual.
Config.Beginner = {
	ReachMul = 1.15,
	HeightFloor = 0.6,
	ContactFloor = 0.55,
	Depth = 0.5,
	DepthJitter = 0.5 * M,
	RingSize = { 3.2, 9 }, -- the ring's width (studs): when it's time to jump, and LeadTime before
	LeadTime = 1.2, -- seconds before take-off the ring starts closing
}

-- Practice drills (PracticeService). The court is a 2v2: you and a setter on your side, their
-- setter and attacker on the other. Bots stand still; a drill moves only the one it needs.
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
	DrillSetRise = 3.5 * M, -- their setter's set (block and dig drills) peaks this far over the attacker's hand
	AttackDepth = 1.2 * M, -- how far from the net the attacker hits
	AttackAboveNet = 1.2 * M, -- the lowest the attack leaves the hand, above the net top
	BlockKmh = { 90, 110 },
	BlockReachMargin = 3.0, -- the block drill's spike leaves the hand this far (studs) under the top of your full block (past Zones.BlockStuffCover: a block in time stuffs it; was 0.8)
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
	-- At the top bot level a team's characters come from this many tiers under it as well, by role
	-- (the owner, 2026-11-16: "make s+ teams not be exclusively locked to gunwoo and the s+ blocker.
	-- just bc they are s+ bots doesn't mean they cant use s tiers. i'd keep the s+ wingspikers locked
	-- on to s+ though"): an S+ team's setter and middle are any S or S+ one, its spiker S+ only.
	-- They still play at the lobby's level (skillP).
	TopTierSpread = { SE = 1, MB = 1 },
	-- now and then a jump goes up properly mistimed (the owner, 2026-11-16: "maybe make ais
	-- sometimes mistime jumps"): the share of block jumps timed right (the rest early or late by
	-- BlockMistime seconds, as a story's other team: Config.Story's FoeBlock and BlockMistime, which
	-- a story stage keeps; there your own side times every block), and the chance a spike jump goes
	-- early or late by SpikeMistime seconds (met off the top of the jump: a weaker, blockable spike)
	BlockTimed = { 0.55, 0.85 },
	-- by tier, in place of BlockTimed: S+ bots time every block jump right, S ones 9 in 10 (the
	-- owner, 2026-11-18: "s and s+ have normal block timing", then S+ perfect and S missing "every
	-- so often"); a story's other team still keeps its own (Config.Story's FoeBlock)
	BlockTimedTier = { ["S+"] = 1, S = 0.9 },
	BlockMistime = { 0.25, 0.45 },
	SpikeMistimeChance = { 0.25, 0.06 },
	SpikeMistime = { 0.06, 0.12 },
	ContactNoise = { 1.1, 0.06 }, -- studs of positioning error under the ball
	-- a spiker's jump steers along the court to its spot by the contact, up to this x its run speed
	-- (a long run to a set from deep used to leave it short)
	AirSteerMul = 1.5,
	ReactionDelay = { 0.28, 0.02 }, -- seconds before starting to move for a new ball
	PerfectReceiveChance = { 0.1, 0.8 },
	SloppyStance = { 0.8, 0.2 }, -- how far outside the perfect window a normal receive is pressed
	WhiffChance = { 0.25, 0.02 }, -- misses a heavy spike outright
	MissChance = { 0.07, 0.0 }, -- misses any ball
	SpikeMishitChance = { 0.3, 0.01 }, -- frames the swing (a weak, wild spike)
	ServeMissChance = { 0.12, 0.01 }, -- jump serves only (the underhand serve never misses)
	HumanAtNet = 1.0 * M, -- a human teammate this close to the net blocks; the AI blocker stays back
	-- (BlockChance is gone: the AI blocker goes up on every set now; at 0.15 to 0.4 it stood still
	-- on most and looked broken)
	-- the AI goes up to block a set that comes down this close to the net (it was 2.2 m, under the
	-- open set's 2.3 m: the AI only ever blocked quicks; the community, "sometimes the middle blocker
	-- doesn't block or jump"); back sets (BackDepth) come in too
	BlockSetMaxDepth = 4.4 * M,
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
	FallingStarChance = 0.45, -- a Falling Star setter calls it on an open or back set this often once it's ready
	RallyCryChance = 0.5, -- a Rally Cry bot pops it at a serve this often once it's ready
	FeverChance = 0.6, -- a Fever bot pops it at a serve this often once it's ready and half charged
	CoronaChance = 0.3, -- and a Corona bot (Laith) his
	SquallChance = 0.4, -- and a Squall bot (Hayul) hers
	ThunderChance = 0.4, -- and a Thunder bot (YeJun) Storm Call
	TyrantChance = 0.5, -- and a Tyrant bot (Gunwoo) Emperor's Dictate
	FeralChance = 0.4, -- and a Feral bot (Valen) Bloodlust
	CoverDepth = 1.5, -- the cover stands this much deeper than the human's spot
	CoverAfterMiss = 1.5, -- after the human whiffs, the cover plays the ball for this long
	SwapMargin = 1.2 * M, -- a human this much closer to a teammate's spot than their own takes it
	FriendsPerPlayer = 30, -- bots wear these players' friends' avatars and names
}

-- Settings saved in each player's profile (the Settings module cleans them; the client's
-- State.settings holds the defaults and the live values).
Config.Settings = {
	Switches = { "landingMarker", "dramatic", "assist", "followCam", "doubleApproach", "setterAim", "beginner", "skipS", "skipSMinus" },
	-- tour: the menu tour's step after the tutorial (MenuController; 4 is done)
	-- camHeight, camZoom, camPan: your own match camera (the owner, 2026-10-29: "a dynamic fov
	-- setter... how high or low it is, and how zoomed in or zoomed out you are. also left or
	-- right"), each -1..1 in CamStep steps (CameraController.wide; Settings > Camera)
	Numbers = { shake = { 0, 1 }, tour = { 0, 4 }, camHeight = { -1, 1 }, camZoom = { -1, 1 }, camPan = { -1, 1 } },
	CamStep = 0.1,
	Cam = { Height = 18, LookHeight = 6, Zoom = 0.3, Pan = 22 }, -- studs (Zoom: a share of the distance) at 1
	-- touch buttons can be moved (x, y: the centre as a fraction of the screen) and resized
	Touch = {
		Buttons = { "A", "B", "C", "Set", "Skill1", "Skill2", "Skill3" },
		MinSize = 0.6,
		MaxSize = 1.6,
		SizeStep = 0.1,
	},
	-- the HUD pieces the same editor moves and sizes (the owner: "allow full menu tweaking...
	-- not just play buttons"; "make the two team scoreboards separate"); each piece's shift is at
	-- most MaxShift of the screen either way
	Hud = {
		Pieces = { "TeamLeft", "Score", "TeamRight", "Readout", "Stats", "Forfeit", "Timeout", "Settings", "Chat", "Ability", "Foes" },
		Names = { TeamLeft = "Left team", Score = "Score", TeamRight = "Right team", Readout = "Speed", Stats = "Stats", Forfeit = "Forfeit", Timeout = "Timeout", Settings = "Settings", Chat = "Chat", Ability = "Your ability", Foes = "Their abilities" },
		MinSize = 0.5,
		MaxSize = 1.6,
		MaxShift = 1,
	},
	SaveDelay = 1, -- seconds after the last change before the client sends them
}

-- Keyboard controls (Settings > Controls; the owner: "in the settings, allows keybinds to be
-- changed"). Each action works on its Defaults until you pick your own key, which replaces them
-- (one key per action, and a key you pick is taken from any other action that had it). Allowed:
-- the keys a player may pick: Roblox's own (Escape, chat's Slash, the console's F9, the player
-- list's Tab) and 1 and 2 (your AI teammates' abilities) aren't. The mouse buttons and a
-- controller stay as they are.
-- Quick chat (QuickChatService, the client's QuickChat; the owner: "prewritten phrases like 'nice
-- play' 'set me' 'lag' 'ref' 'gg'... but also emojis... make some more"): picked by number, shown
-- over the sender's head for Show seconds; at most Burst in Window seconds, Gap apart
Config.QuickChat = {
	Phrases = { "Nice play!", "Set me!", "Lag", "Ref!", "GG", "Nice set!", "Nice spike!", "What a block!", "What a save!", "Mine!", "Yours!", "My bad", "Cover me!", "Watch the tip!", "Let's go!", "Clutch!", "Unlucky", "Thanks!", "Calculated.", "Wow!", "One more!", "Too fast", "Defense!", "Comeback time" },
	-- sob, skull, laughing, fire, steam, cool, clown, clap, scream, pray, thinking, 100, angry,
	-- cold, salute, mind blown, eyes, goat, heart, sleepy, handshake, muscle, target, zap
	Emojis = { "\u{1F62D}", "\u{1F480}", "\u{1F602}", "\u{1F525}", "\u{1F624}", "\u{1F60E}", "\u{1F921}", "\u{1F44F}", "\u{1F631}", "\u{1F64F}", "\u{1F914}", "\u{1F4AF}", "\u{1F621}", "\u{1F976}", "\u{1FAE1}", "\u{1F92F}", "\u{1F440}", "\u{1F410}", "\u{2764}", "\u{1F634}", "\u{1F91D}", "\u{1F4AA}", "\u{1F3AF}", "\u{26A1}" },
	-- the wheel's 8 to start with (P: a phrase, E: an emoji, by number; Settings' quickWheel)
	Wheel = { "P1", "P2", "P5", "P4", "P3", "E1", "E2", "E4" },
	Show = 3,
	Burst = 3,
	Window = 6,
	Gap = 0.8,
}

Config.Controls = {
	Order = { "MoveLeft", "MoveRight", "Spike", "Receive", "SlideFeint", "Block", "Set", "Serve", "EasyServe", "Ability", "Timeout", "QuickChat" },
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
		QuickChat = "Quick chat",
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
		QuickChat = { "G" },
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
		SlideFeint = "A diving receive; in the air, a soft roll shot (let go to tip; hold longer to push it deep)",
		Block = "Hold at the net, let go to jump",
		Set = "Toward the net: quick; away: back",
		Serve = "Tap: overhand; hold: a jump-serve toss",
		EasyServe = "A slow underhand serve that lands in",
		Ability = "Your character's active ability",
		Timeout = "In a match: refills stamina, change who serves",
		QuickChat = "Phrases and emojis over your head",
	},
	-- a controller's buttons (what each does), and the menus on a controller (PadNav), for the same
	-- card (the owner: "make a controller tutorial aswell")
	Pad = {
		{ "Move", "Left stick", "You only move along the court" },
		{ "Jump and spike", "A or R2", "On the floor a run-up jump; in the air, the spike" },
		{ "Receive", "B", "Press a little before the ball reaches you" },
		{ "Slide and roll shot", "RB", "A diving receive; in the air, a soft roll shot" },
		{ "Block", "Y", "Hold at the net, let go to jump" },
		{ "Set", "LB", "Stick toward the net: quick; away: back. Setters aim with the right stick" },
		{ "Serve", "X", "Tap: overhand; hold: a jump-serve toss" },
		{ "Easy serve", "D-pad up", "A slow underhand serve that lands in" },
		{ "Ability", "L2", "Your character's active ability" },
		{ "Teammates' abilities", "D-pad left / right", "Your AI teammates' active abilities" },
		{ "Timeout", "Select", "In a match: refills stamina, change who serves" },
		{ "Quick chat", "Right stick click", "Phrases and emojis over your head" },
		{ "Settings and Forfeit", "D-pad down", "In a match; B closes it" },
		{ "Menus", "D-pad or stick, A", "Move the yellow outline; A presses" },
		{ "Back and tabs", "B, LB / RB", "B goes back or closes; LB and RB switch tabs" },
	},
	Touch = {
		{ "Move", "The stick, bottom left" }, { "Jump and spike", "Jump: jump, then Jump again in the air to spike" },
		{ "Receive and block", "Bump: tap it a little early; at the net hold it to block" }, { "Slide and roll shot", "Slide" },
		{ "Set", "Set" }, { "Serve", "Basic Serve, or hold Spike Serve for a jump serve" }, { "Ability", "Its round button" },
		{ "Timeout", "The hourglass, top right" }, { "Match stats", "Stats, top right" },
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
	Spark = Color3.fromRGB(255, 150, 46), -- (the match's callouts, boards and buttons: a bright orange, 2026-10-28; was the old yellow)
	Whistle = Color3.fromRGB(255, 59, 92),
	Mint = Color3.fromRGB(80, 240, 190),
	Fog = Color3.fromRGB(160, 166, 200),
}

-- Story mode (the owner, 2026-11-10: "a story mode", after The Spike Cross's: a Story plate over
-- Home's Match plate, chapter cards, a chapter's stages unlocking one by one, rewards for each
-- clear). The Story module reads this; the lines themselves are in StoryScript.
--   * a stage is a Match (3v3 against a set team of bots with the `Mates` beside you, one set to
--     Points with no deuce) or a Story (reading only). You play your own character (the owner,
--     2026-11-11: "story mode shouldn't lock your character"); `As` is only the story's lead,
--     the face on the chapter's card;
--   * three stars a stage: a win, then a win by StarDiff[2], then by StarDiff[3] (a Story stage
--     gives all three for reading it);
--   * First pays the first time it's cleared, Three the first time it has three stars; a story
--     match pays nothing else (no match VP, no record), so it can't be farmed;
--   * Bots is the level every bot in it plays at, yours too (TeamService.botTier);
--   * Gold marks the big matches in the stage list.
Config.Story = {
	Mode = 3,
	Timeouts = 1,
	StarDiff = { 0, 3, 5 },
	Goals = { "Win the match", "Win by 3 or more points", "Win by 5 or more points" },
	ReadGoal = "Read the story",
	-- The other team isn't maxed, and grows through each chapter (a tester's notes, passed on by the
	-- owner, 2026-11-15: "nerf the story mode blockers, because they jump too high for a d tier...
	-- right now its basically impossible for a d-b tier to hit over", "maybe make it so they arent
	-- maxed out and they gradually do get stronger throughout the story"). A chapter's FoeLevel =
	-- { first match, last match }: how far every one of the other team's stats is from a fresh
	-- recruit's (0) to maxed (1), the matches between spread evenly (Story.foeLevel; a stage's own
	-- FoeLevel or a FoeHold row wins). FoeBlock, the same shape: the share of the other team's block
	-- jumps that are timed properly; the rest go up early or late by BlockMistime seconds and miss
	-- ("maybe reinstate the intentionally bad timing you had. keep the good block timing for our
	-- side though": your own side's AI blocks as it always does). Defaults for a chapter without them.
	FoeLevel = { 0.4, 0.8 },
	FoeBlock = { 0.4, 0.7 },
	BlockMistime = { 0.32, 0.5 },
	ScoreGoal = "Score %d points", -- a stage the story loses (its Score): won or lost, the points you took
	Seasons = { { Key = "s1", Name = "Season 1" } },
	Chapters = {
		{
			Key = "c1",
			Number = 1,
			Season = "s1",
			Name = "The Third Player",
			Blurb = "Garam Academy's volleyball club has two members, one month and no ace. Then a transfer student walks into the wrong gym.",
			Color = Color3.fromRGB(255, 150, 46),
			School = "Garam Academy",
			FoeLevel = { 0, 0.5 }, -- (fresh recruits in 1-1, half built by the final)
			FoeBlock = { 0.15, 0.45 }, -- (about one block jump in seven timed right in 1-1, under half by the final)
			-- Mates: your teammates in the story; they play only where Lock is set (the owner,
			-- 2026-11-14: "let you use your entire own team and only lock it on certain important
			-- stages where its important to the story"). Elsewhere your own team fills in, as in a
			-- normal match. Locked: 1-1 (they meet), 1-4 (the champions' visit), 1-10 (the final).
			-- They grow as the chapter goes (the owner, 2026-11-14: "it would be cool for kanta and noeul
			-- to get stronger as the story progresses, with abilties albeit weak ones"): MateBreaks,
			-- breakthroughs of stats; MateTier (chapter 2 on), the tier they play at, that tier's stats
			-- for their role and height ("upgrade kanta and noeul overall every few stages. in chapter
			-- 2 they should be about c- to c+"). MateAbilities, an ability each, and MateWeak, the level
			-- it plays at (below 0 weaker than the real thing: Breakthrough.ab), are there for later:
			-- none yet (the owner, 2026-11-14: "its a bit early for them to have abilities").
			Stages = {
				{ Key = "1-1", Name = "Wrong Gym", Kind = "Match", Lock = true, Versus = "Garam Seniors", Kit = "Seniors", As = "riku", Mates = { "daichi", "hana" }, Foes = { "kaede", "kaito", "asahi" }, Bots = "D", Points = 5, Court = "Arena", First = { VP = 60, Gold = 1000 }, Three = { VP = 40, Gold = 1000 } },
				{ Key = "1-2", Name = "Just Until Then", Kind = "Match", Versus = "Garam Seniors", Kit = "Seniors", As = "riku", Mates = { "daichi", "hana" }, Foes = { "kaede", "kaito", "asahi" }, Bots = "D+", Points = 7, Court = "Arena", First = { VP = 60, Gold = 1000 }, Three = { VP = 40, Gold = 1000 } },
				{ Key = "1-3", Name = "Whose Gym Is It", Kind = "Match", Versus = "Badminton Club", Kit = "Badminton", As = "riku", Mates = { "daichi", "hana" }, Foes = { "sakura", "hyejin", "mateo" }, Bots = "D+", Points = 7, Court = "Arena", First = { VP = 70, Gold = 1500 }, Three = { VP = 50, Gold = 1000 } },
				{ Key = "1-4", Name = "The Champions Visit", Kind = "Match", Lock = true, MateBreaks = 2, Gold = true, Versus = "Cheongun Academy B", Kit = "Cheongun", As = "riku", Mates = { "daichi", "hana" }, Foes = { "bomin", "ren", "dohyun" }, Bots = "C-", Points = 5, Court = "Arena", First = { VP = 80, Gold = 1500 }, Three = { VP = 50, Gold = 1500 } },
				{ Key = "1-5", Name = "Bracket Day", Kind = "Match", Versus = "Garam Seniors", Kit = "Seniors", As = "riku", Mates = { "daichi", "hana" }, Foes = { "kaede", "kaito", "asahi" }, Bots = "C-", Points = 7, Court = "Arena", First = { VP = 80, Gold = 1500 }, Three = { VP = 50, Gold = 1500 } },
				{ Key = "1-6", Name = "Rooftop Rules", Kind = "Match", Versus = "Rooftop Regulars", Kit = "Street", As = "riku", Mates = { "daichi", "hana" }, Foes = { "daiki", "iker", "leo" }, Bots = "C", Points = 10, Court = "Rooftop", First = { VP = 90, Gold = 2000 }, Three = { VP = 60, Gold = 1500 } },
				{ Key = "1-7", Name = "First Whistle", Kind = "Match", Versus = "Baekho Tech", Kit = "Baekho", As = "riku", Mates = { "daichi", "hana" }, Foes = { "natsuki", "insoo", "theo" }, Bots = "C", Points = 10, Court = "Nationals", First = { VP = 100, Gold = 2000 }, Three = { VP = 60, Gold = 2000 } },
				{ Key = "1-8", Name = "The Last Page", Kind = "Match", Versus = "Kanta's Old Team", Kit = "Street", As = "riku", Mates = { "daichi", "hana" }, Foes = { "jiho", "hyunwoo", "daeho" }, Bots = "C+", Points = 10, Court = "Beach", First = { VP = 100, Gold = 2000 }, Three = { VP = 60, Gold = 2000 } },
				{ Key = "1-9", Name = "Still Scared?", Kind = "Match", Versus = "Namsan High", Kit = "Namsan", As = "riku", Mates = { "daichi", "hana" }, Foes = { "noa", "nari", "hikari" }, Bots = "C+", Points = 12, Court = "Nationals", First = { VP = 120, Gold = 2500 }, Three = { VP = 80, Gold = 2000 } },
				{ Key = "1-10", Name = "Match Point", Kind = "Match", Lock = true, MateBreaks = 5, Gold = true, Versus = "Cheongun Academy", Kit = "Cheongun", As = "riku", Mates = { "daichi", "hana" }, Foes = { "ganghyun", "elias", "marco" }, Bots = "B-", Points = 15, Court = "Nationals", First = { VP = 200, Gold = 4000, Lucky = 1 }, Three = { VP = 120, Gold = 3000 } },
				{ Key = "1-11", Name = "See You at Regionals", Kind = "Story", First = { VP = 100, Gold = 2000 } },
			},
		},
		-- Chapter 2 (2026-11-14). Regionals need a coach on the bench, Mr. Bae turns out to have
		-- set for Garam's last regionals team, and YeJun (Byeorak High, last year's MVP) is the rival,
		-- playing alone ("his team is like all b tiers or maybe even c tiers, but he alone is an s+").
		-- His first match holds him back (FoeHold: fresh stats, no Storm Call). The final is three
		-- stages, a set each; Garam lose it ("garam loses, and yejun says boring"), Kanta and Noeul
		-- wake up in set three, and Rui is left behind for chapter 3's training. Face: the card's
		-- portrait (its rival).
		{
			Key = "c2",
			Number = 2,
			Season = "s1",
			Name = "Still Standing",
			Blurb = "Regionals need a coach, and Garam doesn't have one. Last year's MVP saw Rui flinch, and he says nobody's still standing when the thunder comes.",
			Color = Color3.fromRGB(255, 206, 46),
			School = "Garam Academy",
			FoeLevel = { 0.35, 0.75 },
			FoeBlock = { 0.4, 0.7 },
			Face = "yejun",
			FacePose = "Cross",
			Stages = {
				{ Key = "2-1", Name = "Two Steps Too Long", Kind = "Match", MateTier = "C-", Versus = "Garam Seniors", Kit = "Seniors", As = "riku", Mates = { "daichi", "hana" }, Foes = { "kaede", "kaito", "asahi" }, Bots = "C-", Points = 7, Court = "Arena", First = { VP = 100, Gold = 2000 }, Three = { VP = 60, Gold = 1500 } },
				{ Key = "2-2", Name = "The Old Photo", Kind = "Match", MateTier = "C-", Versus = "Garam Alumni", Kit = "Alumni", As = "riku", Mates = { "daichi", "hana" }, Foes = { "minho", "takumi", "jaehyun" }, Bots = "C", Points = 7, Court = "Arena", First = { VP = 100, Gold = 2000 }, Three = { VP = 60, Gold = 1500 } },
				{ Key = "2-3", Name = "The Draw", Kind = "Match", MateTier = "C-", Versus = "Namsan High", Kit = "Namsan", As = "riku", Mates = { "daichi", "hana" }, Foes = { "noa", "nari", "hikari" }, Bots = "C+", Points = 10, Court = "Nationals", First = { VP = 110, Gold = 2000 }, Three = { VP = 70, Gold = 2000 } },
				{ Key = "2-4", Name = "Training Camp", Kind = "Match", MateTier = "C", Versus = "Cheongun Academy", Kit = "Cheongun", As = "riku", Mates = { "daichi", "hana" }, Foes = { "ganghyun", "elias", "marco" }, Bots = "B-", Points = 10, Court = "Beach", First = { VP = 120, Gold = 2500 }, Three = { VP = 70, Gold = 2000 } },
				{ Key = "2-5", Name = "Thunder", Kind = "Match", MateTier = "C", Lock = true, Gold = true, FoeHold = { yejun = { Level = 0, NoActive = true } }, Versus = "Byeorak High", Kit = "Thunder", As = "riku", Mates = { "daichi", "hana" }, Foes = { "yejun", "yoonseo", "genji" }, Bots = "C+", Points = 10, Court = "Arena", First = { VP = 150, Gold = 3000 }, Three = { VP = 90, Gold = 2500 } },
				{ Key = "2-6", Name = "Sand", Kind = "Match", MateTier = "C", Versus = "Beach Locals", Kit = "Locals", As = "riku", Mates = { "daichi", "hana" }, Foes = { "nagi", "yuto", "chanwoo" }, Bots = "B-", Points = 10, Court = "Beach", First = { VP = 120, Gold = 2500 }, Three = { VP = 80, Gold = 2000 } },
				{ Key = "2-7", Name = "The Only Blocker", Kind = "Match", MateTier = "C", Lock = true, Versus = "Rooftop Regulars", Kit = "Street", As = "riku", Mates = { "daichi", "hana" }, Foes = { "daiki", "iker", "leo" }, Bots = "B-", Points = 10, Court = "Rooftop", First = { VP = 130, Gold = 2500 }, Three = { VP = 80, Gold = 2500 } },
				{ Key = "2-8", Name = "Round One", Kind = "Match", MateTier = "C+", Versus = "Haeseong High", Kit = "Haeseong", As = "riku", Mates = { "daichi", "hana" }, Foes = { "yerin", "gyuri", "minseo" }, Bots = "B", Points = 12, Court = "Nationals", First = { VP = 140, Gold = 3000 }, Three = { VP = 90, Gold = 2500 } },
				{ Key = "2-9", Name = "Quarterfinal", Kind = "Match", MateTier = "C+", Versus = "Cheongun Academy", Kit = "Cheongun", As = "riku", Mates = { "daichi", "hana" }, Foes = { "ganghyun", "elias", "marco" }, Bots = "B", Points = 12, Court = "Nationals", First = { VP = 150, Gold = 3000 }, Three = { VP = 100, Gold = 2500 } },
				-- the final, a set a stage (the owner, 2026-11-14: "like tsc, theres 3 parts to it. set 1, where its
				-- more an easier, with less points, maybe a lore loss, then set 3, where kanta and noeul awakens, and
				-- the main character feels left behind", then "garam loses, and yejun says boring"): set one and
				-- set three are lost in the story, so they clear on your points (Score); set three is where Kanta
				-- and Noeul wake up (their abilities, still under the real thing) and YeJun plays it all, Storm Call too
				{ Key = "2-10", Name = "Set One", Kind = "Match", MateTier = "C+", Lock = true, Gold = true, FoeHold = { yejun = { Level = 0.15, NoActive = true } }, Score = { 2, 4, 6 }, Versus = "Byeorak High", Kit = "Thunder", As = "riku", Mates = { "daichi", "hana" }, Foes = { "yejun", "yoonseo", "genji" }, Bots = "B+", Points = 7, Court = "Nationals", First = { VP = 150, Gold = 3000 }, Three = { VP = 90, Gold = 2000 } },
				{ Key = "2-11", Name = "Set Two", Kind = "Match", MateTier = "C+", Lock = true, FoeHold = { yejun = { Level = 0.3, NoActive = true } }, Versus = "Byeorak High", Kit = "Thunder", As = "riku", Mates = { "daichi", "hana" }, Foes = { "yejun", "yoonseo", "genji" }, Bots = "B", Points = 10, Court = "Nationals", First = { VP = 180, Gold = 3500 }, Three = { VP = 100, Gold = 2500 } },
				{ Key = "2-12", Name = "Still Standing", Kind = "Match", MateTier = "C+", Lock = true, MateAbilities = { daichi = "RallyCry", hana = "Featherfall" }, MateWeak = -2, Gold = true, Entrance = "yejun", FoeHold = { yejun = { Level = 0.45 } }, Score = { 4, 8, 12 }, Versus = "Byeorak High", Kit = "Thunder", As = "riku", Mates = { "daichi", "hana" }, Foes = { "yejun", "yoonseo", "genji" }, Bots = "B+", Points = 15, Court = "Nationals", First = { VP = 250, Gold = 5000, Lucky = 1 }, Three = { VP = 150, Gold = 4000 } },
				{ Key = "2-13", Name = "Runners-Up", Kind = "Story", First = { VP = 120, Gold = 2500 } },
			},
		},
		-- the Winter event's side story (the owner, 2026-11-16: "a christmas theme mini-story? maybe
		-- about jaja coming in from volleyball evolution"): Side, so it stands apart from the main
		-- story (its first stage is always open, the rest open one by one, Story.next skips it);
		-- Limited, so a live server has it only while the event is on. Tag/Header name it in place of
		-- a chapter number.
		{
			Key = "w1",
			Number = 0,
			Tag = "W",
			Header = "WINTER SPECIAL",
			Side = true,
			Limited = "Winter",
			Season = "winter",
			Name = "Snowed In",
			Blurb = "Kanta won a weekend at Snowfall Lodge. Somebody was already on the court: a joker from another game, missing three cards from his Christmas deck.",
			Color = Color3.fromRGB(110, 180, 240),
			School = "Garam Academy",
			FoeLevel = { 0.3, 0.7 },
			FoeBlock = { 0.35, 0.65 },
			Face = "jaja",
			FacePose = "Hips",
			-- (no stage locked to the story's team: the owner, 2026-11-16, "i dont think we have to lock
			-- the charactesr to kanta and noeul": every match is your own team; the scenes tell it)
			Stages = {
				{ Key = "W-1", Name = "First Snow", Kind = "Match", MateTier = "C+", Versus = "Jaja's Pickup Team", Kit = "Lodge", As = "riku", Mates = { "daichi", "hana" }, Foes = { "jaja", "ilya", "tetsuo" }, Bots = "C", Points = 7, Court = "Winter", First = { VP = 100, Gold = 2000 }, Three = { VP = 60, Gold = 1500 } },
				{ Key = "W-2", Name = "The Lost Cards", Kind = "Story", First = { VP = 100, Gold = 2000 } },
				{ Key = "W-3", Name = "Gift Exchange", Kind = "Match", MateTier = "C+", Versus = "Silver Bells", Kit = "Bells", As = "jaja", Mates = { "daichi", "hana" }, Foes = { "seoyeon", "joon", "akari" }, Bots = "C+", Points = 7, Court = "Winter", First = { VP = 120, Gold = 2500 }, Three = { VP = 70, Gold = 2000 } },
				{ Key = "W-4", Name = "Black Ice", Kind = "Match", MateTier = "B-", Versus = "Black Ice", Kit = "BlackIce", As = "riku", Mates = { "daichi", "hana" }, Foes = { "haeri", "taesan", "isamu" }, Bots = "B-", Points = 10, Court = "Winter", First = { VP = 140, Gold = 3000 }, Three = { VP = 80, Gold = 2000 } },
				{ Key = "W-5", Name = "Jackpot", Kind = "Match", Gold = true, MateTier = "B-", Versus = "Polar Tyrants", Kit = "Tyrants", As = "riku", Mates = { "daichi", "hana" }, Foes = { "dohwan", "alexis", "daon" }, Bots = "B", Points = 12, Court = "Winter", First = { VP = 220, Gold = 5000, Lucky = 1 }, Three = { VP = 100, Gold = 3000 } },
			},
		},
	},
	-- A rival's entrance (EntranceController; the owner, 2026-11-14, after The Spike Cross's
	-- Nishikawa: "copy that for yejun", "add lightning sfx and stuff"): on a stage that names one
	-- (its Entrance: YeJun's only on 2-12, when he starts trying), after the matchup intro and before the first serve. The empty stands, yellow
	-- bolts flashing across the screen, one strike down onto him with a ring and a burst, dust
	-- blowing off him while his Quote shows over his head, then his cut-in: him big on the right,
	-- his name and Title over letterbox bars. Time: seconds it adds to the pre-match wait (the
	-- whole entrance, MatchService).
	Entrances = {
		yejun = { Title = "Thunder Spiker", Quote = "Can you touch someone who lives in the sky?", Color = Color3.fromRGB(255, 236, 46), Icon = "AbilityThunder", Pose = "Arms", Time = 7.2 },
	},
	-- A stage's FoeHold = { [character id] = { Level = 0.6, NoActive = true } } holds one of the
	-- other team back (the owner, 2026-11-14, on YeJun's first story match: "this should be a weaker
	-- yejun... maybe he doesnt use his ability, or he doesn't double swing, or he isn't maxed out"):
	-- Level, how far his stats are from a fresh recruit's (0) to maxed (1) (a fresh recruit's was
	-- "a little too weak"); NoActive never pops his active (Storm Call). Bots never double swing.
	-- YeJun climbs each time he plays (the owner: "maybe each time, his stats jump by like 10-20%",
	-- "he starts at 0 and moves up by 10-20"): 0 in 2-5, 0.15 and 0.3 in the final's first two
	-- sets, 0.45 in the third, never maxed in chapter 2 ("he shouldn't be maxed out in chapter 2
	-- how will the new players beat him?"). The third set is the only one with Storm Call, and
	-- the only one with his entrance: it's where he starts trying ("dont really give yejun an
	-- intro until he starts trying").
	-- The story's faces (StoryDialogue's portraits, and the bots of a story match): a roster id, or
	-- a name of the story's own. Skin, Hair (a catalog hair accessory's id), Kit (the shirt and
	-- shorts colours, Kits below) and Scale (height) dress a plain rig; Accessories (catalog ids
	-- by HumanoidDescription field) add to it, and UserId (a Roblox account's whole avatar) takes
	-- the place of all of it. A roster character without a row gets a skin and a hair of
	-- DefaultHair by its id, and its stage's Kit.
	Cast = {
		riku = { Name = "Rui", Skin = Color3.fromRGB(234, 184, 146), Hair = 13655562, Kit = "Garam" },
		daichi = { Name = "Kanta", Skin = Color3.fromRGB(204, 142, 105), Hair = 3814456274, Kit = "Garam", Scale = 1.08 },
		hana = { Name = "Noeul", Skin = Color3.fromRGB(245, 205, 170), Hair = 164482468, Kit = "Garam", Scale = 0.93 },
		kaede = { Name = "Momiji", Skin = Color3.fromRGB(234, 184, 146), Hair = 3814481268, Kit = "Seniors" },
		sakura = { Name = "Tsubaki", Skin = Color3.fromRGB(245, 205, 170), Hair = 185812297, Kit = "Badminton" },
		ganghyun = { Name = "Kangjun", Skin = Color3.fromRGB(224, 172, 140), Hair = 2830383855, Kit = "Cheongun", Scale = 1.05 },
		marco = { Name = "Luca", Skin = Color3.fromRGB(240, 196, 160), Hair = 185812332, Kit = "Cheongun" },
		daiki = { Name = "Yusei", Skin = Color3.fromRGB(204, 142, 105), Hair = 343584973, Kit = "Street" },
		noa = { Name = "Lina", Skin = Color3.fromRGB(245, 205, 170), Hair = 878922157, Kit = "Namsan" },
		jiho = { Name = "Dojin", Skin = Color3.fromRGB(224, 172, 140), Hair = 376548738, Kit = "Street" },
		-- Baekho Tech (stage 1-7), named by the owner, 2026-11-14: "add 3 names into story onto one team,
		-- shu yano and ray"
		natsuki = { Name = "Shu", Skin = Color3.fromRGB(234, 184, 146), Hair = 62234425, Kit = "Baekho" },
		insoo = { Name = "Yano", Skin = Color3.fromRGB(204, 142, 105), Hair = 376548738, Kit = "Baekho", Scale = 1.06 },
		theo = { Name = "Ray", Skin = Color3.fromRGB(245, 205, 170), Hair = 185812297, Kit = "Baekho", Scale = 0.96 },
		-- the other teams' players, named by the owner, 2026-11-14: "add this name somewhere in the story
		-- Ciciko, yuri, acheron, and wild", "and Wowo", "and Jet, and nish, and fadlan, hiori, and lazer"
		-- (their names in the story: the stage cards, the match and the lines; the roster keeps its own)
		kaito = { Name = "Ciciko", Kit = "Seniors" }, -- Garam Seniors (1-1, 1-2, 1-5)
		asahi = { Name = "Wowo", Kit = "Seniors" },
		hyejin = { Name = "Yuri", Kit = "Badminton" }, -- the Badminton Club (1-3)
		mateo = { Name = "Hiori", Kit = "Badminton" },
		bomin = { Name = "Jet", Kit = "Cheongun" }, -- Cheongun Academy B (1-4)
		ren = { Name = "Nish", Kit = "Cheongun" },
		dohyun = { Name = "Lazer", Kit = "Cheongun" },
		iker = { Name = "Wild", Kit = "Street" }, -- the Rooftop Regulars (1-6)
		leo = { Name = "Fadlan", Kit = "Street" },
		hyunwoo = { Name = "Acheron", Kit = "Street" }, -- Kanta's old team (1-8)
		daeho = { Name = "Kembris", Kit = "Street" }, -- (the owner: "one more name to add for story more kembris")
		-- (the owner's own avatar, 2026-11-14: "for yejun just use my current avatar"; UserId takes the
		-- place of the rest)
		yejun = { Name = "YeJun", UserId = 559391029, Skin = Color3.fromRGB(240, 196, 160), Hair = 553918777, Kit = "Thunder", Scale = 1.06 },
		-- chapter 2: YeJun's teammates at Byeorak High (B tier: "his team is like all b tiers"; the
		-- roster's names until the owner names them), Mr. Bae's old team, the regionals' first round
		yoonseo = { Name = "Yeeun", Kit = "Thunder" },
		genji = { Name = "Isao", Kit = "Thunder" },
		minho = { Name = "Taemin", Kit = "Alumni", Scale = 1.04 },
		takumi = { Name = "Shota", Kit = "Alumni", Scale = 1.06 },
		jaehyun = { Name = "Hojun", Kit = "Alumni" },
		teacher = { Name = "Mr. Bae", Skin = Color3.fromRGB(224, 172, 140), Hair = 402302859, Kit = "Teacher" },
		-- the Winter side story's (Snowed In): Jaja as his own avatar; the other teams by their roster
		-- names, in their stage's kit
		jaja = { Name = "Jaja", UserId = 449474966, Skin = Color3.fromRGB(240, 196, 160), Hair = 62234425, Kit = "Joker" }, -- (the owner: "this is jaja avatar use this": his Roblox avatar; the rest only if it can't load)
	},
	DefaultHair = { 13655562, 3814456274, 376548738, 62234425, 343584973, 2830383855, 3814481268, 164482468, 185812297, 878922157 },
	DefaultSkin = { Color3.fromRGB(234, 184, 146), Color3.fromRGB(245, 205, 170), Color3.fromRGB(204, 142, 105), Color3.fromRGB(224, 172, 140), Color3.fromRGB(160, 110, 80) },
	-- shirt, shorts
	Kits = {
		Garam = { Color3.fromRGB(255, 124, 28), Color3.fromRGB(24, 26, 44) },
		Seniors = { Color3.fromRGB(96, 104, 128), Color3.fromRGB(40, 44, 60) },
		Badminton = { Color3.fromRGB(70, 190, 120), Color3.fromRGB(240, 240, 240) },
		Cheongun = { Color3.fromRGB(36, 70, 190), Color3.fromRGB(235, 235, 245) },
		Street = { Color3.fromRGB(60, 60, 66), Color3.fromRGB(150, 40, 40) },
		Baekho = { Color3.fromRGB(235, 235, 235), Color3.fromRGB(30, 30, 30) },
		Namsan = { Color3.fromRGB(150, 40, 60), Color3.fromRGB(245, 235, 220) },
		Thunder = { Color3.fromRGB(20, 20, 26), Color3.fromRGB(255, 214, 60) }, -- (Byeorak High's, chapter 2)
		Alumni = { Color3.fromRGB(196, 120, 60), Color3.fromRGB(52, 54, 70) }, -- Garam's old team, faded
		Locals = { Color3.fromRGB(70, 170, 200), Color3.fromRGB(240, 220, 170) },
		Haeseong = { Color3.fromRGB(40, 140, 110), Color3.fromRGB(235, 235, 235) },
		Teacher = { Color3.fromRGB(120, 96, 72), Color3.fromRGB(60, 52, 46) },
		-- Snowed In (the Winter side story)
		Joker = { Color3.fromRGB(214, 30, 44), Color3.fromRGB(26, 22, 30) }, -- Jaja's (only if his avatar can't load)
		Lodge = { Color3.fromRGB(120, 74, 46), Color3.fromRGB(236, 228, 210) }, -- his pickup team
		Bells = { Color3.fromRGB(226, 230, 240), Color3.fromRGB(214, 170, 60) }, -- the Silver Bells
		BlackIce = { Color3.fromRGB(26, 36, 64), Color3.fromRGB(150, 210, 240) }, -- Black Ice
		Tyrants = { Color3.fromRGB(70, 36, 110), Color3.fromRGB(230, 190, 70) }, -- the Polar Tyrants
	},
}

-- Daily missions (the owner, 2026-11-11: "quests too", after The Spike Cross's Mission screen:
-- six a day at +250P each, the day's reward at 1,000P, so any four of them). The Missions module
-- reads this. Always is the one that's there every day; the other Count - 1 are drawn from Pool by
-- the day, the same for everyone. Stat is what a mission counts (Missions.matchEvents fills them
-- from a finished match; "checkin" when the Missions window is opened); Go is where its button
-- takes you (match, story, cups, or nothing).
Config.Missions = {
	Count = 6,
	Points = 250,
	Goal = 1000,
	Reward = { VP = 60, Gold = 2000 },
	Always = "checkin",
	Pool = {
		{ Key = "checkin", Text = "Check in.", Stat = "checkin", Need = 1 },
		{ Key = "play", Text = "Play %d matches.", Stat = "matches", Need = 3, Go = "match" },
		{ Key = "win", Text = "Win %d matches.", Stat = "wins", Need = 2, Go = "match" },
		{ Key = "kills", Text = "Score %d points with spikes across matches.", Stat = "kills", Need = 10, Go = "match" },
		{ Key = "blocks", Text = "Block %d spikes across matches.", Stat = "blocks", Need = 3, Go = "match" },
		{ Key = "aces", Text = "Serve %d aces across matches.", Stat = "aces", Need = 2, Go = "match" },
		{ Key = "digs", Text = "Dig %d balls across matches.", Stat = "digs", Need = 10, Go = "match" },
		{ Key = "story", Text = "Win %d Story stage.", Stat = "story", Need = 1, Go = "story" },
		{ Key = "cup", Text = "Win %d Tournament match.", Stat = "cupWins", Need = 1, Go = "cups" },
		{ Key = "winMB", Text = "Win %d match playing a Middle Blocker.", Stat = "winMB", Need = 1, Go = "match" },
		{ Key = "winSE", Text = "Win %d match playing a Setter.", Stat = "winSE", Need = 1, Go = "match" },
		{ Key = "winWS", Text = "Win %d match playing a Wing Spiker.", Stat = "winWS", Need = 1, Go = "match" },
	},
}

-- Character mastery (the owner, 2026-11-11, from The Spike Cross's Mastery tab on a player's
-- page: "clear challenges and get some rewards and a mastery unlock"). Every character starts a
-- Rookie. The next rank's Need is three challenges, each a count of the points you scored as that
-- character (spike kills, aces, blocks) in matches you won: match (Quick Match, custom lobbies,
-- ranked), story (story stages) and cup (tournaments). Clear all three and claim its Reward: that
-- is the promotion. The counts keep running, so play toward a later rank is never lost.
Config.Mastery = {
	Labels = { match = "Score in matches", story = "Score in Story", cup = "Score in Tournaments" },
	Ranks = {
		{ Key = "Rookie", Name = "Rookie", Color = Color3.fromRGB(242, 245, 250) },
		{ Key = "Veteran", Name = "Veteran", Color = Color3.fromRGB(120, 200, 255), Need = { match = 30, story = 20, cup = 20 }, Reward = { VP = 100, Gold = 3000 } },
		{ Key = "Elite", Name = "Elite", Color = Color3.fromRGB(190, 130, 255), Need = { match = 100, story = 60, cup = 60 }, Reward = { VP = 200, Gold = 6000, Lucky = 1 } },
		{ Key = "Master", Name = "Master", Color = Color3.fromRGB(255, 196, 40), Need = { match = 250, story = 150, cup = 150 }, Reward = { VP = 400, Gold = 12000, Lucky = 2 } },
		{ Key = "Legend", Name = "Legend", Color = Color3.fromRGB(255, 90, 90), Need = { match = 600, story = 300, cup = 300 }, Reward = { VP = 800, Gold = 25000, Lucky = 5 } },
	},
}

-- The Winter collab (the owner, 2026-11-15: "we're going to have a christmas event collab with
-- jaja's volleyball game [Volleyball Evolved]. this will have event snowflakes, quests, and
-- a new event gamemode. alongside that, an exclusive character that can only be recruited from the
-- event currencies alongside christmas items like snowflake ball, christmas courts"). Shaped after
-- The Spike Cross's collab event (researched that day: its collab players come only from the
-- event's coins, never V Points; the coins from event matches once a day, an attendance pass and
-- missions; one gauge guarantees a player; an exchange shop). The rules are Winter.lua's.
-- A DRAFT, SWITCHED OFF: Enabled is false, so a published game shows nothing of it. It's wired
-- (the save, the pay, the quests, the banner, the shop: ProfileService; the menu: WinterMenu; a
-- stand-in event match: LobbyService.enterWinter). Every number, the dates and the name are
-- placeholders until the owner's details come.
Config.Winter = {
	-- (launched 2026-11-21, the owner: start "as soon as I publish", end Jan 4, keep the name)
	Enabled = true,
	-- in Studio the event runs whatever Enabled and the dates say, to build and test it (as its
	-- character is on the roster there: Roster). What's earned that way is marked and thrown away
	-- by a live server (Winter.clean), so testing leaves nothing behind for the launch
	StudioPreview = true,
	Name = "Winter Rally",
	Partner = "Volleyball Evolved",
	Starts = 1795240800, -- 2026-11-21 06:00 UTC: midnight in Chicago on release day (no later than the advent calendar's door 1)
	Ends = 1799042400, -- 2027-01-04 06:00 UTC: the end of January 3 in Chicago
	DayOffset = -6 * 3600, -- event days turn at midnight in Chicago
	Snow = { Name = "Snowflakes", Color = Color3.fromRGB(150, 220, 255), Max = 1000000 },
	-- the event match, Christmas Cards (the owner, 2026-11-16: "do what you think is the best idea,
	-- your choice. if you want to fuse then fuse"): The Spike Cross's collab matches (short, your
	-- own lobby against the AI) fused with a card flipped over the court before every rally that
	-- twists that rally's rules (Cards), and a different rival team each event day around Jaja
	-- (Rivals). Foes: who always plays on the other side (the day's rival fills the rest)
	Match = { Mode = 3, Points = 8, Timeouts = 1, Court = "Winter", Foes = { "jaja" } },
	-- the rival teams, one an event day in turn (Winter.rival): Jaja and these two, at the
	-- difficulty's FoeLevel like him
	Rivals = {
		{ Key = "Tyrants", Name = "Snow Tyrants", Picks = { "dohwan", "taesan" } },
		{ Key = "Feather", Name = "Featherfrost", Picks = { "arin", "haesol" } },
		{ Key = "Stars", Name = "Falling Stars", Picks = { "byeol", "alexis" } },
		{ Key = "North", Name = "North Wind", Picks = { "ilya", "tetsuo" } },
		{ Key = "Bells", Name = "Sleigh Bells", Picks = { "seoyeon", "joon" } },
		{ Key = "BlackIce", Name = "Black Ice", Picks = { "haeri", "taesan" } },
		{ Key = "Polar", Name = "Polar Night", Picks = { "dohwan", "alexis" } },
	},
	-- (no card makes stamina unbreakable: a guard that never breaks let AI-only rallies run for
	-- minutes, 2026-11-16)
	-- the Christmas cards: one drawn before every rally of a Winter Match (Weight over the deck's
	-- sum, never the same card twice running) and in play for that rally only. Mut: the rally's
	-- match modifiers (Config.Mutators' keys and options, on both sides through the Mutators
	-- attribute); Points: what the rally is worth; Gift: everyone without one borrows a random
	-- S-tier wing spiker's or middle blocker's ability (Jaja's Sleight of Hand pool). Color: the
	-- card's band
	Cards = {
		{ Key = "Calm", Name = "Silent Night", Text = "All is calm: the usual game.", Weight = 6, Color = Color3.fromRGB(120, 150, 210) },
		{ Key = "Snowball", Name = "Snowball Fight", Text = "Spikes fly 50% faster.", Mut = { Power = "Super" }, Weight = 10, Color = Color3.fromRGB(110, 190, 255) },
		{ Key = "Snowdrift", Name = "Snowdrift", Text = "Moon gravity: the ball and everyone float.", Mut = { Gravity = "Moon" }, Weight = 8, Color = Color3.fromRGB(200, 230, 255) },
		{ Key = "Avalanche", Name = "Avalanche", Text = "Heavy gravity and harder jump serves.", Mut = { Gravity = "Heavy", Serves = "Strong" }, Weight = 7, Color = Color3.fromRGB(70, 110, 190) },
		{ Key = "IceWall", Name = "Ice Wall", Text = "Blocks reach higher.", Mut = { Blocks = "Walls" }, Weight = 8, Color = Color3.fromRGB(140, 225, 255) },
		{ Key = "SugarRush", Name = "Sugar Rush", Text = "Everyone runs faster, and abilities have no cooldown.", Mut = { Speed = "Turbo", Cooldowns = "None" }, Weight = 7, Color = Color3.fromRGB(255, 120, 170) },
		{ Key = "JingleJump", Name = "Jingle Jump", Text = "Everyone jumps higher.", Mut = { Jump = "Super" }, Weight = 8, Color = Color3.fromRGB(255, 214, 90) },
		{ Key = "ThinIce", Name = "Thin Ice", Text = "Stamina drains twice as fast.", Mut = { Stamina = "Fragile" }, Weight = 6, Color = Color3.fromRGB(170, 210, 235) },
		{ Key = "Cocoa", Name = "Hot Cocoa", Text = "All warmed up: everyone runs faster, and cooldowns are halved.", Mut = { Speed = "Fast", Cooldowns = "Half" }, Weight = 6, Color = Color3.fromRGB(170, 110, 70) },
		{ Key = "FrozenToes", Name = "Frozen Toes", Text = "Everyone runs and jumps slower.", Mut = { Speed = "Slow", Jump = "Low" }, Weight = 5, Color = Color3.fromRGB(150, 180, 220) },
		{ Key = "CandyCane", Name = "Candy Cane", Text = "This rally is worth 2 points.", Points = 2, Weight = 8, Color = Color3.fromRGB(236, 40, 56) },
		{ Key = "Gift", Name = "Gift Exchange", Text = "Everyone borrows a random S-tier ability.", Gift = true, Weight = 8, Color = Color3.fromRGB(30, 170, 80) },
		{ Key = "Jackpot", Name = "Jackpot!", Text = "Worth 2 points, everyone borrows an ability, and spikes fly faster.", Points = 2, Gift = true, Mut = { Power = "Super" }, Weight = 2, Color = Color3.fromRGB(255, 196, 40) },
	},
	CardShow = 2.6, -- s: the drawn card big in the middle before it moves under the score
	-- the Winter Pass (the owner, 2026-11-16: "a winter themed pass. paid and free tier, with
	-- rewards like lucky spins, vp, gold, but also good ones like christmas emotes, exclusive balls,
	-- titles, cards"): Tiers of TierXP each, XP from any match, more from Winter Matches, today's
	-- quests and attendance. Every tier has a free reward and a premium one; premium is one
	-- Developer Product for the whole event (Packs: Id 0 shows "Soon" and is free in Studio; Price
	-- is what the button shows until the product exists). A reward: Snow, Gold, VP, Lucky, Card
	-- (Config.Cards key: the titles), Item ({ Kind, Key }: the poses and balls) or Skin.
	Pass = {
		Name = "Winter Pass",
		Tiers = 30,
		TierXP = 150,
		XP = { Match = 20, Win = 10, WinterMatch = 40, WinterWin = 20, Quest = 60, Login = 30 },
		Price = 399,
		Packs = {
			{ Id = 3732620607, Name = "Winter Pass", Label = "Premium", Once = true, WinterPass = true, Price = 399, Gift = true },
			-- tier skips (the owner, 2026-11-16: "add products like skip tiers in the battlepass"):
			-- PassTiers tiers' worth of pass XP (ProfileService.packExtras); Price is shown on the button
			{ Id = 3732640777, Name = "Skip 1 Tier", Label = "+1 tier", PassTiers = 1, Price = 49, Gift = true },
			{ Id = 3732640779, Name = "Skip 5 Tiers", Label = "+5 tiers", PassTiers = 5, Price = 199, Gift = true },
			{ Id = 3732640782, Name = "Skip 10 Tiers", Label = "+10 tiers", PassTiers = 10, Price = 349, Gift = true },
		},
		-- a gifted Winter Pass opened by someone who has premium already: these Snowflakes instead
		GiftDupSnow = 1500,
		Rewards = {
			{ Free = { Snow = 50 }, Prem = { Item = { Kind = "Pose", Key = "Reindeer" } } },
			{ Free = { Gold = 2000 }, Prem = { Lucky = 2 } },
			{ Free = { VP = 80 }, Prem = { Card = "JingleSpiker" } },
			{ Free = { Snow = 50 }, Prem = { VP = 250 } },
			{ Free = { Lucky = 1 }, Prem = { Item = { Kind = "Ball", Key = "Crystal" } } },
			{ Free = { Gold = 2500 }, Prem = { Gold = 8000 } },
			{ Free = { Item = { Kind = "Pose", Key = "ColdHands" } }, Prem = { Lucky = 2 } },
			{ Free = { VP = 100 }, Prem = { Snow = 200 } },
			{ Free = { Snow = 75 }, Prem = { Item = { Kind = "Pose", Key = "HoHoHo" } } },
			{ Free = { Card = "SnowDay" }, Prem = { VP = 300 } },
			{ Free = { Gold = 3000 }, Prem = { Card = "Naughty" } },
			{ Free = { VP = 120 }, Prem = { Card = "Nice" } },
			{ Free = { Snow = 75 }, Prem = { Lucky = 3 } },
			{ Free = { Lucky = 1 }, Prem = { Gold = 10000 } },
			{ Free = { Item = { Kind = "Ball", Key = "GoldBauble" } }, Prem = { Item = { Kind = "Ball", Key = "IcicleBall" } } },
			{ Free = { Gold = 3500 }, Prem = { Snow = 250 } },
			{ Free = { VP = 150 }, Prem = { VP = 400 } },
			{ Free = { Snow = 100 }, Prem = { Item = { Kind = "Pose", Key = "IceSkater" } } },
			{ Free = { Lucky = 1 }, Prem = { Lucky = 3 } },
			{ Free = { Card = "Winter2026" }, Prem = { Card = "NorthernLights" } },
			{ Free = { Gold = 4000 }, Prem = { Gold = 12000 } },
			{ Free = { VP = 150 }, Prem = { Snow = 300 } },
			{ Free = { Snow = 100 }, Prem = { VP = 500 } },
			{ Free = { Lucky = 1 }, Prem = { Lucky = 4 } },
			{ Free = { Item = { Kind = "Pose", Key = "SnowAngel" } }, Prem = { Item = { Kind = "Ball", Key = "SnowGlobe" } } },
			{ Free = { Gold = 5000 }, Prem = { Room = "Christmas" } }, -- (the Christmas Eve Home room)
			{ Free = { VP = 200 }, Prem = { Card = "SantasAce" } },
			{ Free = { Snow = 150 }, Prem = { Lucky = 5 } },
			{ Free = { Lucky = 2 }, Prem = { VP = 750 } },
			-- (Candy Claw, Horang's: the owner, 2026-11-18, "horang tier 30"; Sleigh Ride went to the
			-- Wild Card banner)
			{ Free = { Card = "Frostbitten" }, Prem = { Skin = "CandyClaw" } },
		},
	},
	-- the advent calendar (the owner, 2026-11-18: "add gifting, make up a tone of cosmetics for
	-- advent calender, you can buy forward up till the 25th, you can buy missed days"): a door a day
	-- from Starts (door 1) to door Doors, each a cosmetic. Today's door is free; a missed one, or one
	-- still to come (up to the last), is opened with Product (Robux), the one you picked or else the
	-- earliest still shut. Days turn with DayOffset like the rest of the event. Rewards are the
	-- Pass's kinds (Item, Card, Snow...), and a door may give an Item and a Card both
	Advent = {
		Starts = 1796104800, -- 2026-12-01 06:00 UTC: door 1 opens at midnight in Chicago
		Doors = 25,
		Product = { Id = 3733260425, Name = "Advent Door", Label = "Open a door", Price = 39, Advent = true },
		Refund = 100, -- Snowflakes for a door bought once every door is open (it can't be lost)
		Rewards = {
			{ Item = { Kind = "Color", Key = "Tinsel" } },
			{ Card = "CozySeason" },
			{ Item = { Kind = "Ball", Key = "Gingerbread" } },
			{ Item = { Kind = "Color", Key = "Mistletoe" } },
			{ Item = { Kind = "Trail", Key = "Starlight" } },
			{ Card = "SantasHelper" },
			{ Item = { Kind = "Ball", Key = "JingleBell" } },
			{ Item = { Kind = "Color", Key = "Eggnog" } },
			{ Card = "UnderMistletoe" },
			{ Item = { Kind = "Color", Key = "Sugarplum" } },
			{ Item = { Kind = "Trail", Key = "Holly" } },
			{ Card = "GingerCrew" },
			{ Item = { Kind = "Ball", Key = "Pudding" } },
			{ Item = { Kind = "Color", Key = "Evergreen" } },
			{ Item = { Kind = "Trail", Key = "CandyCanes" } },
			{ Card = "Humbug" },
			{ Item = { Kind = "Ball", Key = "SnowmanHead" } },
			{ Item = { Kind = "Color", Key = "SilverBells" } },
			{ Item = { Kind = "Trail", Key = "Gingerbread" } },
			{ Card = "TwelveDays" },
			{ Item = { Kind = "Ball", Key = "Wreath" } },
			{ Item = { Kind = "Color", Key = "PolarNight" } },
			{ Item = { Kind = "Trail", Key = "SleighBells" } },
			{ Item = { Kind = "Jump", Key = "JingleBells" } },
			-- Christmas morning: the Star Topper skin (Laith with it), the North Star ball and the card
			{ Skin = "StarTopper", Item = { Kind = "Ball", Key = "NorthStar" }, Card = "Advent2026" },
		},
		-- doors that are never sold ahead of their day (Christmas morning's: a Mythic skin for R$ 39
		-- a month early would undercut the banner); once their day has gone by they can be bought
		NoEarly = { [25] = true },
		-- doors whose prize stays hidden until they're open
		Mystery = { [25] = true },
	},
	-- the event's leaderboard (the owner, 2026-11-18: "event leaderboard ofc"): Winter Match wins,
	-- worth Points by difficulty (a Blizzard win counts most), on the Ranks window while the event is
	-- on. When it ends, the top places get a card each (Rewards, best first: Top = the last place
	-- that gets it), handed out as each player next joins (ReadTop places read once a server)
	Board = {
		Points = { Normal = 1, Hard = 2, Blizzard = 4 },
		ReadTop = 100,
		Rewards = {
			{ Top = 1, Card = "WinterChampion" },
			{ Top = 10, Card = "WinterTop10" },
			{ Top = 100, Card = "WinterTop100" },
		},
	},
	-- what a finished event match pays in Snowflakes. First: the day's first clear of that
	-- difficulty; Repeat: later clears; Loss: a loss. FoeLevel: how far Jaja's stats are from a
	-- fresh recruit's (0) to maxed (1) on the other side (Story.heldBuild)
	Difficulties = {
		-- (Rivals = false: Jaja with players of the difficulty's own tier, not the day's S+ rivals; the
		-- owner, 2026-11-18: "the btier event should probably give b tier characters")
		{ Key = "Normal", Name = "Normal", Bots = "B", FoeLevel = 0, Rivals = false, First = 40, Repeat = 5, Loss = 2, Color = Color3.fromRGB(160, 222, 255) },
		{ Key = "Hard", Name = "Hard", Bots = "A", FoeLevel = 0.5, Rivals = false, First = 60, Repeat = 8, Loss = 3, Color = Color3.fromRGB(84, 146, 255) },
		{ Key = "Blizzard", Name = "Blizzard", Bots = "S+", FoeLevel = 1, First = 90, Repeat = 12, Loss = 4, Color = Color3.fromRGB(238, 247, 255) },
	},
	-- daily quests: Count a day, the same for everyone (Always first, the rest drawn by the day),
	-- each paying its Snow once. Stats are Missions.matchEvents' (any match) and the event's own:
	-- snowMatches / snowWins (event matches played / won), recruits (on the event's banner)
	Quests = {
		Count = 3,
		Always = "snow",
		Pool = {
			{ Key = "snow", Text = "Play %d Winter match.", Stat = "snowMatches", Need = 1, Snow = 30 },
			{ Key = "snowWin", Text = "Win %d Winter matches.", Stat = "snowWins", Need = 2, Snow = 35 },
			{ Key = "play", Text = "Play %d matches.", Stat = "matches", Need = 3, Snow = 20 },
			{ Key = "win", Text = "Win %d matches.", Stat = "wins", Need = 2, Snow = 25 },
			{ Key = "kills", Text = "Score %d points with spikes.", Stat = "kills", Need = 12, Snow = 25 },
			{ Key = "blocks", Text = "Block %d spikes.", Stat = "blocks", Need = 3, Snow = 25 },
			{ Key = "aces", Text = "Serve %d aces.", Stat = "aces", Need = 2, Snow = 25 },
			{ Key = "digs", Text = "Dig %d balls.", Stat = "digs", Need = 10, Snow = 20 },
		},
	},
	-- event missions: once each over the whole event (The Spike Cross's pay cosmetics: a profile
	-- background, a frame, a title; ours pay Snowflakes and spins until the winter cosmetics exist)
	Missions = {
		{ Key = "wins10", Text = "Win %d Winter matches.", Stat = "snowWins", Need = 10, Grant = { Snow = 150 } },
		{ Key = "wins30", Text = "Win %d Winter matches.", Stat = "snowWins", Need = 30, Grant = { Snow = 300, Lucky = 1 } },
		{ Key = "kills", Text = "Score %d points with spikes.", Stat = "kills", Need = 150, Grant = { Snow = 150 } },
		{ Key = "blocks", Text = "Block %d spikes.", Stat = "blocks", Need = 40, Grant = { Snow = 100 } },
		{ Key = "recruit", Text = "Recruit %d times on the Wild Card banner.", Stat = "recruits", Need = 30, Grant = { Lucky = 2 } },
		-- for the ones who beat the hardest rivals (was Candy Claw, till it went to the Pass's tier 30)
		{ Key = "blizzard", Text = "Win %d Winter matches on Blizzard.", Stat = "blizzardWins", Need = 15, Grant = { Snow = 300, Lucky = 2 } },
		{ Key = "days", Text = "Check in on %d days of the event.", Stat = "logins", Need = 7, Grant = { Snow = 100 } },
	},
	-- attendance: the Snowflakes for each day you check in (the last entry repeats)
	Login = { 30, 30, 40, 40, 50, 50, 100, 40 },
	-- the banner: Snowflakes only (The Spike Cross: "the only currency that can recruit these
	-- players. V Points cannot be used"). Weight: an item's odds over the banner's sum. Featured:
	-- Joker; Pity recruits without him and the next is him (about 1.5% a recruit before that).
	-- Cosmetic rows that don't exist in Config.Cosmetics yet are skipped (Winter.lua), so the
	-- winter items can be listed here as they're made. A duplicate cosmetic pays DupSnow back
	Banner = {
		Name = "Wild Card",
		Blurb = "Jaja, from Volleyball Evolved, joins for the winter, with Kuro's Sleigh Ride and Viktor's Twinkle Lights skins. Snowflakes only. Every recruit without him fills the gauge: at 140 the next one is Jaja.",
		Cost = { [1] = 50, [10] = 500 },
		-- (was 60 and 1.5%: an active player has about 340 Snowflakes a day, so Jaja was certain in about a
		-- week of a seven-week event; the owner, 2026-11-17: "make it harder to get the s+ tiers. it
		-- would be too short to complete the event". 140 is 7,000 Snowflakes, about three weeks)
		Pity = 140,
		DupSnow = { Rare = 5, Epic = 10, Legendary = 25, Mythic = 50 },
		Items = {
			{ Kind = "Char", Key = "jaja", Weight = 0.75, Featured = true },
			-- two of the Christmas skins (the owner, 2026-11-18: "do kuro and viktor pullable, horang
			-- tier 30 laith door 25"): Mythic, half Jaja's odds each, no pity
			{ Kind = "Skin", Key = "SleighRide", Weight = 0.5 },
			{ Kind = "Skin", Key = "TwinkleLights", Weight = 0.5 },
			-- the winter cosmetics (Config.Cosmetics' Limited = "Winter" rows): 48.5 of the 100
			{ Kind = "Jump", Key = "Tree", Weight = 1 },
			-- the Christmas score effects (2 of the 100, taken off the 1,500 Gold)
			{ Kind = "Effect", Key = "GiftWrap", Weight = 1 },
			{ Kind = "Effect", Key = "SnowGlobe", Weight = 0.5 },
			{ Kind = "Effect", Key = "Delivery", Weight = 0.5 },
			{ Kind = "Trail", Key = "Icicle", Weight = 2.5 },
			{ Kind = "Jump", Key = "Snowman", Weight = 2.5 },
			{ Kind = "Jump", Key = "Present", Weight = 2.5 },
			{ Kind = "Trail", Key = "Snowfall", Weight = 4 },
			{ Kind = "Jump", Key = "Snowburst", Weight = 4 },
			{ Kind = "Ball", Key = "Snowflake", Weight = 1 },
			{ Kind = "Color", Key = "Aurora", Weight = 1 },
			{ Kind = "Ball", Key = "Ornament", Weight = 2.5 },
			{ Kind = "Ball", Key = "Peppermint", Weight = 2.5 },
			{ Kind = "Color", Key = "Holly", Weight = 3 },
			{ Kind = "Ball", Key = "Gift", Weight = 5 },
			{ Kind = "Ball", Key = "Snowball", Weight = 5 },
			{ Kind = "Color", Key = "Frostbite", Weight = 5 },
			{ Kind = "Color", Key = "CandyCane", Weight = 5 },
			{ Kind = "Grant", Key = "Lucky1", Name = "1 lucky spin", Rarity = "Legendary", Weight = 2, Grant = { Lucky = 1 } },
			{ Kind = "Grant", Key = "VP150", Name = "150 VP", Rarity = "Epic", Weight = 8, Grant = { VP = 150 } },
			{ Kind = "Grant", Key = "VP60", Name = "60 VP", Rarity = "Rare", Weight = 15, Grant = { VP = 60 } },
			{ Kind = "Grant", Key = "Gold3000", Name = "3,000 Gold", Rarity = "Rare", Weight = 15, Grant = { Gold = 3000 } },
			{ Kind = "Grant", Key = "Gold1500", Name = "1,500 Gold", Rarity = "Rare", Weight = 11.25, Grant = { Gold = 1500 } }, -- (and what Jaja and the two skins take: 1 of the 100 for Sleigh Ride and Twinkle Lights)
		},
	},
	-- Snowflakes for Robux (the owner, 2026-11-16: "yes you can buy snowfalkes with robux"): Developer
	-- Products, the Snowflakes straight into the event's save (ProfileService.packExtras); Price is
	-- shown on the button. 7,000 is Jaja's certain recruit (Banner.Pity x Cost[1])
	SnowPacks = {
		{ Id = 3732661564, Name = "250 Snowflakes", Label = "250", Snow = 250, Price = 99, Gift = true },
		{ Id = 3732661567, Name = "650 Snowflakes", Label = "650", Snow = 650, Price = 199, Gift = true },
		{ Id = 3732661571, Name = "1,800 Snowflakes", Label = "1,800", Snow = 1800, Price = 449, Gift = true },
		{ Id = 3732661573, Name = "4,000 Snowflakes", Label = "4,000", Snow = 4000, Price = 899, Gift = true },
	},
	-- the Snowflake shop (Limit: buys a player over the event; an Item is bought once). The winter
	-- cosmetics ("snowflake ball, christmas courts") go here as Items once they're made
	Shop = {
		{ Key = "Lucky1", Name = "1 lucky spin", Price = 150, Limit = 5, Grant = { Lucky = 1 } },
		{ Key = "Gold", Name = "2,500 Gold", Price = 40, Limit = 20, Grant = { Gold = 2500 } },
		{ Key = "VP", Name = "150 VP", Price = 80, Limit = 10, Grant = { VP = 150 } },
		-- a sure way to some of the winter items (the rest are the banner's)
		{ Key = "BallSnowball", Name = "Snowball ball", Price = 200, Item = { Kind = "Ball", Key = "Snowball" } },
		{ Key = "BallGift", Name = "Present ball", Price = 200, Item = { Kind = "Ball", Key = "Gift" } },
		{ Key = "ColorFrostbite", Name = "Frostbite spike colour", Price = 150, Item = { Kind = "Color", Key = "Frostbite" } },
		{ Key = "ColorCandyCane", Name = "Candy Cane spike colour", Price = 150, Item = { Kind = "Color", Key = "CandyCane" } },
	},
}

-- An event's own cosmetics (Limited = "Winter") are in the lists only once the event is switched
-- on, like its character (Roster): a published game shows nothing of an event that isn't out
-- (the owner, 2026-11-15: "publish the data reset without any of the event progress yet"). In
-- Studio they're always there, to build and test with.
do
	-- (and the testers' game, Volleyball Generations: the owner, 2026-11-18, "port all the
	-- christmas changes into the test server")
	local inStudio = game ~= nil and (game:GetService("RunService"):IsStudio() or game.GameId == Config.Developers.TestGame)
	if not inStudio and Config.Winter.Enabled ~= true then
		for _, kind in ipairs(Config.Cosmetics.Kinds) do
			local list = Config.Cosmetics[kind]
			for i = #list, 1, -1 do
				if list[i].Limited == "Winter" then
					table.remove(list, i)
				end
			end
		end
		-- and its cards (the Winter Pass's titles) and skins
		for i = #Config.Cards.List, 1, -1 do
			if Config.Cards.List[i].Limited == "Winter" then
				table.remove(Config.Cards.List, i)
			end
		end
		-- and its leaderboard
		for i = #Config.Leaderboards.Boards, 1, -1 do
			if Config.Leaderboards.Boards[i].Limited == "Winter" then
				table.remove(Config.Leaderboards.Boards, i)
			end
		end
		-- and its side story (Snowed In)
		for i = #Config.Story.Chapters, 1, -1 do
			if Config.Story.Chapters[i].Limited == "Winter" then
				table.remove(Config.Story.Chapters, i)
			end
		end
		local order = Config.Halloween.SkinOrder
		for i = #order, 1, -1 do
			local s = Config.Halloween.Skins[order[i]]
			if s and s.Limited == "Winter" then
				Config.Halloween.Skins[order[i]] = nil
				table.remove(order, i)
			end
		end
	end
end

return Config
