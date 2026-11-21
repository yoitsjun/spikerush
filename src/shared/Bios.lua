-- Character descriptions: a short line or two on who they are and what their ability does, in the
-- style of The Spike Cross's recruit cards (the owner: "talk about their main abilities, make it
-- short and quick... yejun's insane vertical and his thunder"). Shown on Home's Featured recruit
-- card and a player's Profile tab. Keyed by roster id; a character without one shows its ability's
-- text (the card) or a short line (the tab).

local Bios = {
	-- S+
	yejun = "The Thunder Spiker. The highest vertical in the game: hit the ball above 4 m and it comes down as lightning. Call the storm and every spike he throws cracks like thunder.",
	haneul = "The Wind Spiker. The fastest player alive: she rides the wind under any set, springs up before the block can blink, and hovers in the air until she's ready to strike.",
	byeol = "The star maker. Call the set and the ball climbs and hangs, and a star lights at the top. Meet the star and you hit like a champion; miss it and it stays with you. A setter who makes stars, and doesn't forgive the ones who fall.",
	kuro = "A wing spiker who fights from the top of the sky. Time his jump in the gold of the meter and he climbs higher than anyone: the higher he hits, the more he burns, and at the very top a dragon dives at his spike. Years of conditioning give him a guard that doesn't break.",
	jaja = "The Joker, on loan from Volleyball Evolved. Every rally he flicks a card into the air and plays whatever it shows: Trickery bends his spikes, Bravery breaks the block, the Buffoon laughs at him, and once in a while the Jackpot makes him the best player on the court. Not even he knows which is coming.",
	dante = "The hardest hitter in the game. He crouches, charges and leaps: the longer the charge, the further he flies, and a full one at the net smashes straight through the block.",
	laith = "The Sun Spiker. When Corona flares he leaps higher than anyone and dives onto the ball from above like a falling sun. He burns brightest, even when it burns him out.",
	seojin = "The Azure Dragon. He hangs in the air gathering energy as gravity lets go; a full bar unleashes a spike that pierces any block. Hold too long, though, and it flies out.",
	taeha = "A once-in-a-generation talent. His Zero Point, met just in front of his head, is too fast for any speed gun and too straight to read: it goes through the block and drains whoever digs it.",
	dohwan = "The Tyrant. With a snap of his fingers a golden aura takes the court: he steals the other team's strength for his own, and his flat, lightning-fast sets hit like a decree no block can stuff.",
	taesan = "A wall of steel. Three shields make him an Iron Wall at the net; break them all and he awakens into a monster attacker, hanging in the air to forge his heaviest spikes.",
	-- S
	daon = "The Rising Sun. The further his team falls behind, the stronger he grows: every three points against him he levels up, until nobody on the court can match him.",
	ines = "The Counter Edge. Every dig charges her meter, and hard spikes barely scratch her. When it's full, her next spike releases everything she's absorbed.",
	seora = "Skyward. Her jump starts low and keeps climbing: every spike lifts her hitting point and her power higher, and her Talon Drop feint drives straight down over the net.",
	shoyo = "Pure adrenaline. When his team is running on empty he jumps higher and hits harder than ever: the tighter the rally, the more dangerous he gets.",
	yeonho = "The Plunge Spin. His spikes shoot over the net flat and fast, then spin down hard with a boom, diving in where nobody's standing.",
	haesol = "Sunshine. She lights up when she digs: nail a perfect one and she glows brighter, stronger and bigger at the net, and her steep Vert Spikes slip right under the block.",
	joon = "The team's heartbeat. His Rally Cry fires everyone up: for ten seconds the whole team jumps higher, hits harder and moves faster.",
	tetsuo = "The Iron Wall. Call it and nothing gets past him: every attack in front of him at the net is shut straight down, however high or hard.",
	arin = "Featherfall. Her sets go up high and float down slowly, and the longer the ball has been falling, the harder her hitter's spike lands.",
	haeri = "The Turnabout. The block sees a set coming, and she spins it into a spike over the net instead.",
	ilya = "The Vector Set. His sets pulse tight to the net and high, and the steeper his hitter brings it down, the harder it hits.",
	seoyeon = "The Chain Reaction. Her sets are charged: the spike off one explodes, and every explosion in a rally makes the next one bigger.",
}

return Bios
