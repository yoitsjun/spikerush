-- PatchNotes: what changed in each update, newest first, for the What's New panel (Home's News
-- button). The newest patch opens by itself once for each player the first time they see the menus
-- after it ships, and reading it to the very bottom pays Reward once (the owner: "maybe a small
-- reward for reading if you scroll to the very bottom").
--
-- To ship a patch: add an entry at the top of List with a new Id (a date is fine), a Title, a Date
-- and Sections of Items. Item.Icon is an Assets key (an ability icon) shown beside the line.

local PatchNotes = {}

-- what reading the newest patch to the bottom pays, once per patch (Economy.cleanGrant)
PatchNotes.Reward = { Gold = 1000 }

PatchNotes.List = {
	{
		Id = "2026-10-12",
		Title = "The S+ Update",
		Date = "October 12, 2026",
		Sections = {
			{
				Heading = "New players",
				Items = {
					{ Icon = "AbilityCorona", Text = "<b>Laith</b> (S+ wing spiker, Corona). Press Q to flare up: every stat +15%, and your spike jump becomes a towering Sun Leap. Every spike of his burns 14% harder (<b>Sunfire</b>). In the air, Spike with the ball below you to <b>Sundive</b> onto it: the further you drop, the harder it hits (up to +38%), on jump serves too. Some spikes burst into a Zenith for extra power and topspin." },
					{ Icon = "AbilitySquall", Text = "<b>Haneul</b> (S+ wing spiker, Squall), the fastest player in the game. Press Jump to dash under the ball in a flash, leaving shattered glass behind, and spring up while the other team slows down. Hold Spike in the air to hover: the target on their court jumps spot by spot toward their back corner, so let go when it's where you want it. The longer you charge, the deeper and harder it goes." },
					{ Icon = "AbilityFeatherfall", Text = "<b>Arin</b> (S setter, Featherfall). Her open and back sets go up high and float down slowly, and a spike off one hits up to 30% harder the longer the ball was falling." },
					{ Icon = "AbilityIronclad", Text = "<b>Taesan</b> (S+ middle blocker, Ironclad). Three shields: while he has one he's a wall at the net, no jump needed, and every block is a perfect shut-down, but a 150 km/h spike shatters a shield, unless he's <b>Unbreakable</b> (a chance to stop it anyway, best against the softer ones). Lose them all and he <b>awakens</b>: jump before the set and hammer out a charged spike of up to about 215 km/h. Every touch fills his Intimidation meter, and a full one brings the shields back." },
				},
			},
			{
				Heading = "Buffs",
				Items = {
					{ Icon = "AbilityThunder", Text = "<b>YeJun</b>: new <b>Storm Call</b> (Q). For 10 seconds every spike is a full-strength lightning spike at any height, around 220 km/h, and a second swing reaches about 260. New <b>Static Charge</b>: each lightning spike in a rally makes your next ones 6% harder (up to 3 times)." },
					{ Icon = "AbilityAzure", Text = "<b>Seojin</b>'s Dragon Surge fills faster, holds much longer before it overcharges and hits far harder at full (about 232 km/h maxed); digging a full bar costs more stamina." },
					{ Icon = "AbilityFeral", Text = "<b>Dante</b>'s Feral Leap hits harder: a full leap reaches about 220 km/h maxed, and his First Strike about 250." },
					{ Icon = "AbilityChainReaction", Text = "<b>Seoyeon</b>'s Chain Reaction grows with every explosion in a rally (\"Chain Reaction x2!\"), and its spikes now always break the guard." },
				},
			},
			{
				Heading = "Changes and fixes",
				Items = {
					{ Text = "Custom sound effects can be cropped: the Crop button picks the part of the sound that plays." },
					{ Text = "New sound effects for the new players' moves." },
					{ Text = "AI jump serves no longer drift away from the ball." },
				},
			},
		},
	},
}

-- The newest patch (nil with none).
function PatchNotes.latest()
	return PatchNotes.List[1]
end

return PatchNotes
