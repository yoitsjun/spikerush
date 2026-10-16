-- PatchNotes: what changed in each update, newest first, for the What's New panel (Home's News
-- button). The newest patch opens by itself once for each player the first time they see the menus
-- after it ships, and reading to the end of it (the newest patch, not the older ones under it) pays
-- Reward once (the owner: "maybe a small reward for reading if you scroll to the very bottom", then
-- "only to the bottom of the newest update").
--
-- To ship a patch: add an entry at the top of List with a new Id (a date is fine), a Title, a Date
-- and Sections of Items. Item.Icon is an Assets key (an ability icon) shown beside the line. A
-- patch's own Reward replaces the usual one (PatchNotes.reward).

local PatchNotes = {}

-- what reading the newest patch to the bottom pays, once per patch (Economy.cleanGrant)
PatchNotes.Reward = { Gold = 1000 }

PatchNotes.List = {
	{
		Id = "2026-10-15",
		Title = "Halloween Night",
		Date = "October 15, 2026",
		Reward = { Gold = 2500, Lucky = 1 },
		Sections = {
			{
				Heading = "The Halloween event (until November 2)",
				Items = {
					{ Text = "<b>Home > Halloween</b>: the <b>Halloween Match</b> on Easy, Normal or Hard. Two stages to 12 points against the AI: before each, a strip of cards rolls past and lands on three, and you pick one, twice. Win both stages for <b>Candy</b>; the first clear of each difficulty every day pays the most." },
					{ Text = "59 cards: stat buffs and trade-offs, team cards, curses on the other team, rule changes, and an <b>ability card</b> for every ability. Ability cards stack on your own ability, up to <b>two</b> of them." },
					{ Text = "The <b>Halloween banner</b> (VP or Candy): the Pumpkin and Witch Hat balls, the Pumpkin Burst and Ghost Swarm score effects, Halloween jumps, trails and colours, the <b>Haunted Forest</b>, and the Mythic <b>Reaper</b>. Every recruit is a scout point: spend them to pick an item outright." },
					{ Icon = "AbilityZeroPoint", Text = "<b>The Reaper</b> is Taeho's skin: he spikes with a void scythe, souls stream behind the ball and his Zero Point gets its own impact frame. Swap it on and off any time on his page." },
					{ Text = "<b>The Haunted Forest</b>: Home out in a moonlit forest, the clubhouse a haunted cabin among dead trees, with a graveyard, a bubbling cauldron, jack-o'-lanterns and a huge orange moon. Put it on with Home's new <b>Decorate</b> button." },
					{ Text = "The <b>Candy shop</b>: lucky spins, Gold, VP and Halloween cosmetics." },
				},
			},
			{
				Heading = "Breakthroughs",
				Items = {
					{ Text = "Lower tiers grow far more with every breakthrough: a +5 D-tier comes close to a maxed A-tier. Each step also cuts an active ability's cooldown, 40% at +5." },
					{ Text = "Your breakthrough level shows on each player's card (+1 to +5), and every breakthrough gets its own reveal." },
					{ Text = "Favourite a player to lock them: favourites can't be sold." },
				},
			},
			{
				Heading = "Player changes",
				Items = {
					{ Icon = "AbilityIronclad", Text = "<b>Taesan</b> buffed: while he has shields he's an <b>Iron Wall</b> at the net. Every attack that crosses in front of him is shut down, at any height, however hard. Each shield cracks on the first spike it stops and shatters on the next: 3 shields, 6 stops." },
				},
			},
			{
				Heading = "Fixes",
				Items = {
					{ Text = "An AI player whose body was lost mid-match (the 2v3 bug) now gets a new one within a couple of seconds." },
					{ Text = "Phones: the speed readout no longer flickers between two places, and name tags are smaller with only your own details." },
				},
			},
		},
	},
	{
		Id = "2026-10-14",
		Title = "Breakthroughs",
		Date = "October 14, 2026",
		-- (the owner: "make a patchnotes for breakthroughs aswell as a scrolling reward")
		Reward = { Gold = 2500, Lucky = 1 },
		Sections = {
			{
				Heading = "Breakthroughs",
				Items = {
					{ Text = "Duplicate players now become <b>fragments</b> of their tier: S- and S give S fragments, and S+ has its own. Duplicate cosmetics still give V Points." },
					{ Text = "Spend fragments in <b>Players > Breakthrough</b> to take a player up to <b>+5</b>. Every step adds stats past their ceiling, and S and S+ abilities grow stronger too: each player's page shows all five steps." },
					{ Text = "Sell fragments you don't need from <b>Recruit > Breakthrough</b> for the V Points a duplicate gave. An S+ fragment adds a lucky spin." },
					{ Text = "Sell players you don't want from their Breakthrough tab: their V Points, the Gold you spent upgrading them and their fragments all come back. Players now lists only the players you have." },
				},
			},
			{
				Heading = "Player changes",
				Items = {
					{ Icon = "AbilityIronclad", Text = "<b>Taesan</b> reworked. He jumps to block now, with a block a little bigger than anyone's. A 185 km/h or a clean spike breaks a shield, and every spike a shield stops <b>cracks</b> it: the second one shatters it. A broken shield slows the spike so his team can dig it, tips go over him, his spike reaches 20% wider, and awakened he fills Intimidation twice as fast. His shields now show over his head." },
					{ Icon = "AbilitySquall", Text = "<b>Haneul</b>: let go of Jump to stop her dash right where she is, and she stays off the net. Steer her while she hovers. New in <b>Updraft</b>: spring off a teammate's set and it slows down while she goes right at the ball." },
				},
			},
			{
				Heading = "Changes and fixes",
				Items = {
					{ Text = "New code: <b>300squad</b> for 1,500 VP, 16,700 Gold, 5 lucky spins and 30 minutes of 2x Luck. Thanks for 300 in the community server!" },
					{ Text = "Verify in the community server for 750 VP, 7,500 Gold, 3 lucky spins and the Community Squad card: the steps now sit right beside Codes." },
					{ Text = "Every S+ player has a <b>Profile</b> tab with their story." },
					{ Text = "Jump is one tap on every device, and touch players get the double approach. Trade V Points for lucky spins in the Shop's Lucky tab." },
					{ Text = "Phones: the scoreboard shrinks to fit, and your ability, the speed readout and quick chat no longer sit on it. The touch layout editor moves every HUD piece, each team's scoreboard on its own." },
					{ Text = "Setters can aim into the back court, Set wins over the receive assist, and deep sets arc higher." },
					{ Text = "New <b>Bug Catcher</b> card, for players who catch bugs for us." },
				},
			},
		},
	},
	{
		Id = "2026-10-12",
		Title = "The S+ Update",
		Date = "October 12, 2026",
		Sections = {
			{
				Heading = "New players",
				Items = {
					{ Icon = "AbilityCorona", Text = "<b>Laith</b> (S+ wing spiker, Corona). Press Q to flare up: every stat +15%, and your spike jump becomes a towering Sun Leap. Every spike of his burns 14% harder (<b>Sunfire</b>). In the air, Spike with the ball below you to <b>Sundive</b> onto it: the further you drop, the harder it hits (up to +38%), on jump serves too. Some spikes burst into a Zenith for extra power and topspin." },
					{ Icon = "AbilitySquall", Text = "<b>Haneul</b> (S+ wing spiker, Squall), the fastest player in the game. Press Jump to dash under the ball in a flash, leaving shattered glass behind, and spring up while the other team slows down. Hold Spike in the air to hover: the target on their court jumps spot by spot toward their back corner, so let go when it's where you want it. The longer you charge, the deeper and harder it goes, and her spikes whip wildly off blocks." },
					{ Icon = "AbilityFeatherfall", Text = "<b>Arin</b> (S setter, Featherfall). Her open and back sets go up high and float down slowly, and a spike off one hits up to 30% harder the longer the ball was falling." },
					{ Icon = "AbilityIronclad", Text = "<b>Taesan</b> (S+ middle blocker, Ironclad). Three shields: while he has one he's a wall at the net, no jump needed, and every block is a perfect shut-down, but a 150 km/h spike shatters a shield, unless he's <b>Unbreakable</b> (a chance to stop it anyway, best against the softer ones). Lose them all and he <b>awakens</b>: jump before the set and hammer out a charged spike of up to about 215 km/h. Every touch fills his Intimidation meter, and a full one brings the shields back." },
				},
			},
			{
				Heading = "Buffs",
				Items = {
					{ Icon = "AbilityThunder", Text = "<b>YeJun</b>: new <b>Storm Call</b> (Q). For 10 seconds every spike is a full-strength lightning spike at any height, around 220 km/h, and a second swing reaches about 260. New <b>Static Charge</b>: each lightning spike in a rally makes your next ones 6% harder (up to 3 times). New <b>High Strike</b>: his spike jumps go 25% higher." },
					{ Icon = "AbilityAzure", Text = "<b>Seojin</b>'s Dragon Surge fills faster, holds much longer before it overcharges and hits far harder at full (about 232 km/h maxed); digging a full bar costs more stamina." },
					{ Icon = "AbilityFeral", Text = "<b>Dante</b>'s Feral Leap hits harder: a full leap reaches about 220 km/h maxed, and his First Strike about 250." },
					{ Icon = "AbilityChainReaction", Text = "<b>Seoyeon</b>'s Chain Reaction grows with every explosion in a rally (\"Chain Reaction x2!\"), and its spikes now always break the guard." },
				},
			},
			{
				Heading = "Changes and fixes",
				Items = {
					{ Text = "New code: <b>HolyS+</b> for 600 VP, 7,500 Gold and 3 lucky spins (Codes on Home)." },
					{ Text = "New code: <b>1000members</b> for 1,000 VP, 10,000 Gold and 5 lucky spins. Thanks for 1,000 members!" },
					{ Text = "Custom sound effects can be cropped: the Crop button picks the part of the sound that plays." },
					{ Text = "New sound effects for the new players' moves." },
					{ Text = "AI jump serves no longer drift away from the ball." },
					{ Text = "Other players' hits no longer make the ball teleport in laggy servers: it flies from their hand and catches up." },
					{ Text = "Auto-sell is now set on each banner, so turning it on for players no longer sells new cosmetics. Anything you had on stays on for the Players banner, and auto-sold pulls now say \"Auto-sold\"." },
				},
			},
		},
	},
}

-- What reading a patch (the newest) to the bottom pays: its own Reward, else the usual.
function PatchNotes.reward(patch)
	patch = patch or PatchNotes.List[1]
	return (patch and patch.Reward) or PatchNotes.Reward
end

-- The newest patch (nil with none).
function PatchNotes.latest()
	return PatchNotes.List[1]
end

return PatchNotes
