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
		Id = "2026-10-21",
		Title = "Ranked & Clans",
		Date = "October 21, 2026",
		Reward = { Gold = 2500, Lucky = 1 },
		Sections = {
			{
				Heading = "Ranked",
				Items = {
					{ Icon = "RankAlmighty", Text = "<b>Ranked</b> is here (Match screen): 1v1, 2v2 and 3v3 against real players only. Climb from <b>Bronze I</b> to <b>Diamond III</b>, then <b>Mighty</b> and <b>Almighty</b>. Every division has its own badge." },
					{ Text = "Beat a stronger team and you gain more; lose to a weaker one and you drop more. The higher you climb, the less a win pays and the more a loss costs." },
					{ Text = "Before every ranked match each team <b>bans one</b> character, then everyone <b>picks</b> who they play. Pick your character from the Ranked window before you queue, too." },
					{ Text = "Seasons are monthly; <b>Season 1</b> ends December 1. A new season keeps half your RP." },
					{ Icon = "RankGold3", Text = "<b>Ranked score effects</b>: Gold Crest, Platinum Spires, Diamond Storm, Mighty Wings and Almighty Ascension. Each is yours while you hold its rank; drop below it and it's gone." },
					{ Icon = "RankAlmighty", Text = "<b>Almighty Ascension</b>: a giant gold statue of you in your intro pose rises out of the court, and a beam of light comes down on you from the heavens." },
					{ Text = "The <b>Ranked leaderboard</b> (Ranks): this season's top players by rank points. It starts fresh every season." },
					{ Text = "The <b>Ranked card</b>: your season, your wins and losses, and your rank's badge, in your rank's colours. It changes as you climb." },
					{ Text = "Leaving a ranked match early costs extra RP and locks the ranked queue for a while. Rejoin the match while it's still on and you get it all back." },
					{ Text = "Everyone who had the Almighty card now has <b>True Almighty</b>. The Almighty card comes from reaching Almighty." },
				},
			},
			{
				Heading = "AFK Lounge",
				Items = {
					{ Text = "<b>AFK</b> (top right): rest in the lounge and get <b>a random reward every 4 minutes</b>, rolled from 17: at least 30 Gold or 10 V Points, up to a <b>Lucky Spin</b>. VIP doubles the Gold and V Points and Roblox Premium adds x1.5, with <b>no daily limit</b>. The side panel adds up what you've made." },
					{ Text = "Stay as long as you want: the lounge refreshes your connection before Roblox's 20 minute AFK kick, and your timer carries on. The timer starts once you're in the lounge." },
				},
			},
			{
				Heading = "Clans and parties",
				Items = {
					{ Text = "<b>Clans</b> (top bar): make one for 1,000 VP or with the Clan Founder pass. Pick a name and a 2 to 5 letter tag, public or private, and a minimum of wins to join." },
					{ Text = "Members earn points for the clan with wins, kills, aces, blocks and MVPs. Spend them on upgrades: more VP and Gold, extra luck, more members, an emblem, and a clan intro when 3 of you play together." },
					{ Text = "<b>Weekly clan points</b>: the clan board shows this week's points too, starting over every Monday." },
					{ Text = "Your clan's <b>Members</b> tab shows the points each member earned <b>today</b> and <b>this week</b>." },
					{ Text = "Buy a tag colour for your [TAG] in chat and over your head. The top 3 clans get their own cards." },
					{ Text = "<b>Parties</b> (top right): invite up to 3 players in your server. The leader's Quick Match or ranked queue takes everyone, on one side." },
				},
			},
			{
				Heading = "New players",
				Items = {
					{ Icon = "AbilityTyrant", Text = "<b>Dohwan, The Tyrant</b> (S+ setter). <b>Emperor's Dictate</b> (Q): for 5 seconds the other team is <b>Locked</b>: 35% less Jump and Speed, 15% less Attack and no slides, and his team gets the stolen stats. Every set of his and his own attacks hit at full power, and their blocks reach half as high. His sets are fast, and the spike off one is 1.3x faster and can't be stuffed. His jump serve dips hard and wrecks the pass." },
					{ Icon = "AbilityTyrant", Text = "Spike past 180 km/h at Dohwan's team and you're <b>Grounded</b>: less Jump and Attack on your next attack." },
					{ Icon = "AbilitySunshine", Text = "<b>Haesol, Sunshine</b> (S middle blocker). A far wider perfect-dig window; a perfect dig lights her up for 10 seconds with +10 to every stat. Her digs reach further, and her <b>Vert Spikes</b> cross the net and drive almost straight down, the steepest slipping under the block." },
				},
			},
			{
				Heading = "Custom matches",
				Items = {
					{ Text = "<b>Match modifiers</b> for custom lobbies: spike power, low or moon gravity, no ability cooldowns, abilities off, endless or fragile stamina, high jumps, turbo speed, walls or no blocking, and stronger serves." },
					{ Text = "Picking the characters your bots play works again in 3v3." },
					{ Text = "Your very first match is against bots at your own level." },
					{ Text = "The tutorial ends with a <b>quick match to 3</b> against bots." },
				},
			},
			{
				Heading = "Shop",
				Items = {
					{ Text = "The <b>Trade</b> tab: turn Gold into V Points, and buy 2x V Points with Gold or VP." },
					{ Text = "Every game pass can be <b>gifted</b>: press Gift on its card." },
					{ Text = "The <b>Locker</b> sorts every tab into Normal, Ranked and Event sections." },
				},
			},
			{
				Heading = "Balance",
				Items = {
					{ Text = "Stacked boosts were sending spikes past 400 km/h. Past 250 km/h a boost now counts for less, and nothing goes over <b>300</b>, except in the <b>Halloween Match</b>, which has no speed limit." },
					{ Icon = "AbilityCorona", Text = "<b>Laith</b>'s jump serve always gets some of his Sundive's power (about 11% harder)." },
					{ Text = "<b>Breakthroughs</b> now grow an ability's power more than its cooldown. Rally Cry's boost reaches 18% at +5, and Storm Call and Iron Wall get stronger too." },
					{ Icon = "AbilityIronclad", Text = "<b>Taesan</b> has to jump to wall, and a set starts with one shield. His Intimidation meter only fills once every shield is broken. The block that shatters a shield pops the ball up for his team, and no spike shatters one at once any more: every shield shuts down one spike, then pops up the next." },
					{ Icon = "AbilityTyrant", Text = "<b>Dohwan</b>: Attack up from 140 to 170, and his <b>Crown Jump Serve</b> now hits as hard as the best S+ wing spiker's (+52 Attack on the serve only)." },
					{ Icon = "AbilityThunder", Text = "<b>YeJun</b>'s second swing gets its own freeze frame, in yellow (violet with the Fallen Angel)." },
					{ Icon = "AbilitySkyward", Text = "<b>Seora</b>: new passive <b>Sharp Angle</b>, her spikes come down a little steeper." },
				},
			},
			{
				Heading = "Fixes",
				Items = {
					{ Text = "The Probability Table and the Lucky Spin Odds no longer show the same numbers (your recruits always used the right odds)." },
					{ Text = "Bots no longer get duplicated, and nobody gets stuck on the wrong side of the net." },
					{ Text = "The Haunted Forest no longer shows in the sky behind the beach court." },
					{ Text = "The Circular Swing spikes with the right hand." },
					{ Text = "Halloween card picks work on a controller, and running out of time picks one at random after 15 seconds." },
					{ Icon = "AbilityCorona", Text = "Laith no longer gets launched across the court or high into the air when his Sundive goes for a low ball." },
					{ Text = "The top bar's buttons no longer overlap on narrower screens, and the timeout panel fits on short phone screens." },
				},
			},
			{
				Heading = "Codes",
				Items = {
					{ Text = "New codes: <b>ranked</b>, <b>clans</b> and <b>1500discord</b>." },
				},
			},
		},
	},
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
					{ Text = "<b>The Haunted Forest</b>: Home out in a moonlit forest, the clubhouse a haunted cabin among dead trees, with a graveyard, a bubbling cauldron, jack-o'-lanterns and a huge orange moon. Home's new <b>Decorate</b> shows a room behind you the moment you pick it; Apply keeps it." },
					{ Icon = "AbilityThunder", Text = "<b>The Fallen Angel</b> is YeJun's skin: one broken black wing, lightning in violet and black, and arms from the underworld that drag him back down on every jump (his own jump while it's on). It shares the banner's Mythic slot with the Reaper." },
					{ Text = "When the Fallen Angel scores, arms burst up under the other team and drag them down through the floor. His Storm Call turns violet too, and the arms on his jumps are bigger, clawing their way out." },
					{ Text = "Each Mythic skin has its own reveal: the Reaper's scythe slashes the screen to pieces, and the Fallen Angel's arms crack their way through it." },
					{ Text = "A skin brings its player with it: pull the Reaper and Taeho is yours, pull the Fallen Angel and YeJun is. Already pulled one? They've joined your roster." },
					{ Text = "Both skins have sounds of their own. The Reaper's scythe swings through every spike and slices on a hard one, and souls wail where his ball lands. The Fallen Angel's wing beats, the underworld growls and the ground gives way on every jump, and his thunder rumbles low." },
					{ Text = "New score effect on the banner, <b>Rest in Peace</b>: a giant gravestone drops on the spot and flings the other team. Carve your own words and a picture on it in the Locker (Customize); otherwise it bears your name." },
					{ Text = "The <b>Candy shop</b>: lucky spins, Gold, VP and Halloween cosmetics." },
				},
			},
			{
				Heading = "Recruits",
				Items = {
					{ Text = "Odds now go by tier: a recruit lands on a tier first (<b>S+ 0.5%</b>, every tier adding up to 100%), then on one of its players. Boost and Lower move your odds inside the tier. The probability table shows every tier with its chance, and each player's share of it." },
					{ Text = "<b>51 new players</b> across the A, B and C tiers (17 for each role). The tier odds haven't changed: there's just more to find in each." },
					{ Text = "S+ players have a line when you recruit them, starting with YeJun's." },
					{ Text = "Luck events go up to <b>16x</b>: N times the luck makes an S+ N times as likely (16x: 8%). Luck events can be 2x, 4x, 6x, 8x or 16x." },
					{ Text = "Pumpkin, Blood Moon and Ectoplasm have colours of their own now, so they no longer look like Tangerine, Crimson and Lime. The Locker's swatches show each colour's bands." },
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
				Heading = "Gameplay",
				Items = {
					{ Text = "<b>Feints</b> float over blocks: a block only reaches one now and then, Iron Wall's too, and then just softens it. Dug, a feint costs a little guard, and breaks a guard at 30% or lower." },
					{ Text = "<b>2x VP</b> (the event, your boosts and the 2x V Points pass) now doubles all the VP you earn: tournament prizes and daily rewards as well as matches. Codes, gifts and purchases stay as they are." },
					{ Text = "Practice drills are endless: go as long as you like, with your streak, best and misses counted, until you head back to the menu. The tutorial can be skipped (no reward), from How to play or from inside it." },
					{ Text = "The serve toss goes higher." },
					{ Icon = "AbilityFeral", Text = "<b>Dante</b>'s First Strike plays a cinematic: the world goes black, he glows purple and cocks his fist, then the white flash as it fires." },
					{ Text = "Timeouts: your favourite players come first in the character switch." },
				},
			},
			{
				Heading = "Player changes",
				Items = {
					{ Text = "<b>Daon</b>, <b>Shoyo</b> and <b>Seora</b> buffed: Daon +12 Attack, +7 Defense, +10 Speed and +10 Jump; Shoyo +7 Attack, +6 Defense, +7 Speed and +3 Jump; Seora +8 Attack, +6 Defense and +8 Speed." },
					{ Icon = "AbilityFeral", Text = "<b>Dante</b>: new <b>Bloodlust</b> (Q). His charge bar burns blood red and races past full, up to <b>165%</b>, for one charged hit (10 seconds at most), and an overcharged leap hits around 265 km/h." },
					{ Icon = "AbilityIronclad", Text = "<b>Taesan</b> buffed: while he has shields he's an <b>Iron Wall</b> at the net. Every attack that crosses in front of him is shut down (all but feints), at any height, however hard. Each shield cracks on the first spike it stops and shatters on the next: 3 shields, 6 stops." },
					{ Icon = "AbilityChainReaction", Text = "<b>Seoyeon</b>'s Chain Reaction is off in 1v1s." },
				},
			},
			{
				Heading = "Fixes",
				Items = {
					{ Text = "An AI player whose body was lost mid-match (the 2v3 bug) now gets a new one within a couple of seconds." },
					{ Text = "Phones: the speed readout no longer flickers between two places, and name tags are smaller with only your own details." },
					{ Text = "Blocking on a slow connection: a spike that reaches you late is checked from the moment it left the hand, so a block that was up in time stops it. On phones, the block tutorial's spikes used to go straight through." },
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
