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
	-- (the owner, 2026-10-29: "the ingame patchnotes are mad short", "purge all other patch notes":
	-- Volleyball Rush starts its history here)
	{
		Id = "2026-10-30",
		Title = "Welcome to Volleyball Rush",
		Date = "October 30, 2026",
		Reward = { Gold = 2500, Lucky = 1 },
		Sections = {
			{
				Heading = "A fresh start",
				Items = {
					{ Text = "<b>Spike Rush is now Volleyball Rush</b>: a brand-new game, and a fresh start for everyone. Everybody begins from zero together." },
					{ Text = "A whole new look in <b>orange and magenta</b>: new menus, new icons, a new loading screen and new effects all through the game." },
					{ Text = "Home is now the <b>Rush Arena</b>: a pro court with the crowd in the stands, the big screen, the scoreboard and warm light through the high windows. The old neon night court is a free room in <b>Decorate</b>." },
					{ Icon = "AbilityThunder", Text = "Meet the roster: almost every character has a new name. Their abilities, stats and stories are the same." },
					{ Text = "Your <b>profile chip</b> (top right) shows who you play, your V Points and your Gold on every main screen, with <b>Settings</b> beside it. <b>AFK</b> and <b>Help</b> sit top left, and <b>Party</b> is on Home." },
				},
			},
			{
				Heading = "New: Horang",
				Items = {
					{ Icon = "AbilityTigerClaw", Text = "<b>Horang</b>, an <b>S tier Wing Spiker</b>, joins the roster." },
					{ Icon = "AbilityTigerClaw", Text = "<b>Tiger Claw</b>: receive or dive one of her spikes and a big orange claw marks you (-9 Jump while it's on you). Marked, your <b>next receive of her attack fails</b> and flies out." },
					{ Icon = "AbilityTigerClaw", Text = "A receive the claw breaks can leave you <b>Discouraged</b>: -8 to every stat for 15 seconds." },
					{ Icon = "AbilityTigerClaw", Text = "<b>Fierce Tiger</b>: while the other team's weakest back-row defender is marked, Horang gets +10 Attack and +2 Jump." },
					{ Icon = "AbilityTigerClaw", Text = "<b>RAWR!</b>: on the match's first serve she roars, and each player on the other team may be Discouraged. <b>Hunt</b>: their weakest defender is outlined in red." },
				},
			},
			{
				Heading = "New: Alexis",
				Items = {
					{ Icon = "AbilityFever", Text = "<b>Alexis</b>, an <b>S tier Middle Blocker</b> designed by one of our fans, joins the roster." },
					{ Icon = "AbilityFever", Text = "<b>Fever</b>: every block charges it, 2% a block up to 16%. Press <b>Q</b> and your <b>whole team</b> gets that boost for 8 seconds, and Alexis gets +12 Attack, +22 Defense, +12 Speed and +22 Jump on top." },
					{ Icon = "AbilityFever", Text = "<b>Too cold there</b>: a 1% chance (2% in Fever) to freeze an enemy spike right at their hand and drop it as her block." },
					{ Icon = "AbilityFever", Text = "Breakthroughs make Fever charge faster, go higher and last longer, and raise the Too cold chance." },
				},
			},
			{
				Heading = "Courts",
				Items = {
					{ Text = "Every court has more to look at. <b>Sunset Beach</b>: a sun in a bluer sky, sandy islands with palm trees, a yacht, a sailboat and the lamp-lit pier." },
					{ Text = "<b>Night Rooftop</b>: the next roof over, with an OPEN ALL NIGHT sign, a water tower and a blinking antenna. <b>Haunted Forest</b>: a graveyard hill and a glowing mausoleum." },
					{ Text = "<b>Colosseum</b>: marble warriors in front of the arches and gold standards above. <b>Nationals</b>: a lit ribbon board around the deck. <b>Rush Arena</b>: a glossy orange court in warm late sun." },
					{ Text = "<b>Match point moments</b>: win the match on Sunset Beach and a <b>whale</b> breaches out of the sea; on the Haunted Forest the <b>Headless Horseman</b> rides past; on the Night Rooftop, <b>fireworks</b>." },
					{ Text = "The seats at the ends of the court are gone, so you can see every chase after a ball flying off the court." },
				},
			},
			{
				Heading = "Camera",
				Items = {
					{ Text = "<b>Settings > Camera</b>: sliders for height, zoom and left or right. You see an empty court with your own camera while you set it." },
					{ Text = "The camera <b>zooms out when the ball flies off-screen</b>, so you can always see where it's going." },
				},
			},
			{
				Heading = "Gameplay",
				Items = {
					{ Text = "<b>No more teleporting balls</b>: when someone on another device touches the ball, it now flies on smoothly instead of jumping back." },
					{ Text = "The ball no longer slows down near other players." },
					{ Text = "<b>Air drag</b>: spikes, digs and serves leave the hand fast and slow down at the end, so they fall more steeply than they rose. They still land where the marker says." },
					{ Icon = "AbilityThunder", Text = "YeJun's <b>thunder spike</b> holds the ball on his hand for a split second while his impact frame plays, and he hangs in the air. <b>Double Swing</b> darkens the court around him first." },
					{ Icon = "AbilityPlunge", Text = "A new <b>Plunge Spin</b> icon." },
				},
			},
			{
				Heading = "Players and upgrades",
				Items = {
					{ Text = "A <b>Max</b> button next to x1, x5 and x10 on a player's Growth tab: + upgrades as far as your Gold goes, - takes them back to base with a full refund." },
					{ Text = "<b>Remove breakthrough</b>: take a breakthrough down one level and get that level's fragments back." },
					{ Text = "The roster cards show each player's <b>ability icon</b> and name, and the Info tab's gem shows the ability icon." },
					{ Text = "Menu outlines now wear your <b>spike trail colour</b> (Locker > Color): black on Classic, one colour or a running rainbow on the others." },
				},
			},
			{
				Heading = "Shop",
				Items = {
					{ Text = "New <b>Specials</b> tab: the <b>Relaunch Pack</b> (2,500 VP, 25,000 Gold, 5 Lucky Spins and an S fragment), the <b>Selection Ticket</b> (pick any S player you don't own), the <b>Breakthrough Pack</b> (S+ and S fragments) and the <b>Mega Bundle</b> (12,000 VP, 120,000 Gold, 20 Lucky Spins, 2 hours of 2x VP and S+ fragments)." },
					{ Text = "<b>Private servers</b> are only <b>25 Robux</b>." },
					{ Text = "Bought passes in Spike Rush? Press <b>Restore</b> (top right of the Shop) to bring over VIP, 2x V Points, Lucky, Custom Sound Effects, Custom Score Effect and Clan Founder." },
					{ Text = "Prices now follow your region." },
				},
			},
			{
				Heading = "Halloween Night",
				Items = {
					{ Text = "The <b>Halloween event</b> runs until <b>November 11</b>: Halloween Matches, the Candy shop, the Halloween banner and the Haunted Forest." },
					{ Text = "The <b>Halloween banner is buffed</b>: Legendary 15%, Mythic 0.6%, and every skin 0.3%." },
				},
			},
			{
				Heading = "Codes",
				Items = {
					{ Text = "<b>Release</b>: 1,500 VP, 20,000 Gold, 5 Lucky Spins and 30 minutes of 2x Luck." },
					{ Text = "<b>VolleyballRush</b>: 1,000 VP, 15,000 Gold and 3 Lucky Spins." },
					{ Text = "Codes go in <b>Codes</b> on Home. Join the group, and like and favorite the game, to use them. All the old Spike Rush codes are gone." },
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
