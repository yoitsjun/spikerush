# Spike Rush

An anime volleyball game for Roblox in a 2.5D side view, modelled on the feel of *The Spike* (SUNCYAN): huge jumps, high sets, spikes measured in km/h, a team stamina "guard" meter, and named characters you roll for, each with a role, a tier and maybe an ability. Everything in this project is original or from the free Roblox Creator Store: the court, UI, loading screen, game icon and all 27 sound effects are procedural or synthesized from scratch, the effects are drawn with hand-made anime textures from two free Creator Store VFX packs, and nothing is taken from The Spike.

The whole game is a Rojo project. The server is authoritative, and the shared gameplay math is deterministic, so every client predicts its own touches with exactly the numbers the server will use.

## Getting started

Install the toolchain once with `rokit install` or `aftman install` (both pin Rojo 7.7.0). Then start the live sync with `serve.bat` (Windows) or `./serve.sh` (macOS, Linux), or run `rojo serve` in this folder yourself, and press Connect in the Rojo plugin in Roblox Studio. The plugin has to be Rojo 7.7.x: older servers speak sync protocol 4, and the current plugin refuses them. `rojo plugin install` installs the matching plugin.

To start from a place file instead, open `SpikeRush.rbxlx` (built with `rojo build -o SpikeRush.rbxlx`) and connect Rojo from there. Press Play: the server builds the arena at startup and you land on the Home screen. New players get a **tutorial** card there: the four practice drills in order (below). Finishing it pays 50 VP, 1,000 Gold and 5 free recruits, once. The **Practice** tab runs any drill on its own. Drills are never rallies: each rep the court sets you up and judges that one touch. Spike: your setter sets you and you spike 3 into their court. Block: their attacker hits from the net and you get your hands on 3. Serve: land 3 in their court in a row. Dig: their attacker spikes at you and you dig 3 in a row. Press Match, then Quick Match (or make a lobby with Fill with bots on) to play; bots fill every empty slot, so the game is fully playable solo.

Player progress (V Points, Gold, the characters you own, their upgraded stats and the one you play, unlocked cosmetics, auto-sell choices, and your settings, touch layout included) is saved with DataStoreService. In Studio this only works after enabling Game Settings > Security > "Enable Studio Access to API Services" on a published place. Without it the game still runs, profiles just last for the session, and the Home screen says so.

The project file sets Workspace gravity to 45 (the server also enforces it at startup), turns off mouse lock, and uses JumpHeight rather than JumpPower.

## Controls

The keyboard layout follows The Spike's, with WASD and mouse alternatives.

| Action | Keyboard / mouse | Gamepad | What it does |
|---|---|---|---|
| Move | A / D or ← / → | Left stick | You only move along the court; your role sets your depth lane |
| Spike | Space, Z, J or left click | A or R2 | On the ground: run-up jump (with **Double approach** on in Settings, the first press starts a run-up toward the net, steered with Move, and the second jumps; a run-up takes off by itself after 0.9 s). In the air: spike. Azure Dragon: hold in the air to charge, release to swing. Feral Leap: hold on the ground to charge, release to leap |
| Receive | ↓, S, K or right click | B | Arms a receive stance for 0.8 s; the touch happens by itself when the ball arrives |
| Slide / feint | C, Shift or L | RB | On the ground: slide receive (never costs stamina). In the air: a soft roll shot |
| Block | ↑ or W | Y | Hold to crouch and charge, release to jump; near the net (1.5 m) the ball that passes your hands is blocked |
| Set | E or V | LB | Hold toward the net for a quick set, away for a back set, nothing for an open set. As the setter (or alone in 1v1) you aim it: a marker on your side shows where the set comes down. Its height follows the mouse up and down over the court (the right stick, or a tap); its distance you charge: hold Set and it slides out from the net, let go to set. Your teammates see it, the other team doesn't (Settings > Setter aim) |
| Easy serve | F | D-pad up | An underhand serve straight from the hand, no toss: a slow, high lob (about 45 km/h) that always clears the net and lands well inside |
| Serve | X | X | Tap for an overhand serve that hits itself; hold to toss for a jump serve (longer = higher toss; hold toward the net as you let go to throw it forward and run into it), then Spike to jump and Spike again to hit. A dotted line shows where the toss will go, and you can't walk past the end line until the serve is hit (jumping over it is fine) |
| Ability | Q | L2 | Active abilities only (Iron Wall, Turnabout, Rally Cry) |
| Teammate ability | 1 / 2 | D-pad left / right | Pops an AI teammate's active ability (their badge beside yours shows the key, and a click does it too); their AI never uses it on its own |
| Timeout | T | Select | Two per set; takes effect at the next dead ball, refills stamina and opens the rotation editor, where you can also switch character or cosmetics; Ready ends it early once everyone is ready. Press it again before the dead ball to call yours off (it isn't used up); during the timeout it's the same as Ready |
| Forfeit | Forfeit button (top right) | | Tap twice within 3 s: your team concedes the match and gets no VP |

On a keyboard or gamepad, the compact control rail on the left edge of the screen shows every action as a text pill with its key (the badges switch to gamepad buttons when you use one), lights up whichever action is live right now, and can be clicked. On touch devices a floating thumbstick moves you (touch anywhere on the left of the screen), and three big round buttons bottom right change with the moment: holding the serve, Basic Serve / Spike Serve (hold to toss) / Jump Serve; on the ground, Slide / Bump / Jump (straight up, winding up a spike); in the air, Feint (the bump button) / Spike. At the net Bump turns into Block: hold to charge, let go to jump. Set pops up when you can set, and your ability and your AI teammates' sit in a column on the left. Receive assist is on by default for touch: it arms the stance for you, with the pass quality capped at 0.62 so manual timing is always better. Settings > Touch controls > Edit shows every button over a dimmed screen: drag one to move it, tap one (or All) and size it from 60% to 160% with - and +, then Save (Reset puts them all back).

The Settings panel (the gear in a match, or Settings in the menus) holds Double approach, the landing marker, impact frames and speed lines, receive assist, the follow camera, camera shake and, on touch devices, the touch layout. Settings save with your profile.

## Menus

Outside a match you're in the menus, drawn over two small 3D sets built on your client: a sunlit club room with your own avatar in it (Toolbox lockers, a bench and a ball cart full of volleyballs), and a school gym with a vaulted timber ceiling, a stage and another ball cart.

- **Home**: your profile card (headshot, name, the character you play, V Points and Gold) top left, just under Roblox's own buttons whatever their size, the featured S+ recruit, tips, Players / Locker / Shop / Settings / Help, and the two big buttons, Recruit Player and Match. When your AI is standing in for you in a match, a Rejoin banner appears.
- **Recruit Player**: the Player banner (Basic Recruit) and the Cosmetic banners, the Probability Table (every pull with its exact chance and whether you own it), auto-roll, auto-sell, and Recruit x1 (50 VP) / x10 (500 VP). A recruit plays out like *The Spike*'s: sparkles on black (gold when an S is inside, red when a Mythic is), the volleyballs sweep under the gym ceiling glowing in their rarity colours (a Mythic throbs red, and its cinematic and card burn red too), then line up over the stage ("Click to Continue") and open one by one. Before an S or S+ opens, a short cinematic plays: a yellow screen, a beam of light, and your own avatar's silhouette leaping and hammering a black ball down in your equipped spike style. Then the reveal card (your avatar in the character's role pose, tier, role, height, ability, stat ceilings) and the results. **Skip** jumps straight to the next S. During auto-roll a running line replaces the sequence, and the one that hits Legendary plays in full.
- **Players**: every character (recruited ones first), who you play, and the Gold upgrades (below).
- **Locker**: equip spike styles, colours, trails, score effects and intro poses. Whatever you click previews live in the gym: your avatar spikes on a loop with that style, the ball flies with that colour and trail, and lands with that score effect; on the Intro pose tab your avatar holds the pose instead. Intro poses (Ready, Arms Crossed, Call Your Shot, Victory Fist, Double Flex, Sky Attack) come from their own Recruit banner.
- **Shop**: two tabs of packs for Robux, each with a Gift button to buy it for someone else: V Points and Gold, then lucky spins and 2x VP boosts. Perks on the right, and a big Recruit button that opens Recruit Player.
- **Daily, Codes and Admin**: buttons down Home's right edge (below). Admin only shows for developers.

Popups (Match, Help, the Probability Table) close only with their Close button or a click on the dark area around them; clicking anywhere inside one never closes it.
- **Ranks**: the leaderboards (below).

## Characters, Gold and V Points

You play named characters, like *The Spike*'s. Each one is a preset: a role, a tier (D- to S+), a height, four stat ceilings (Attack, Defense, Speed, Jump) and, at the top tiers, an ability. The roster (38 characters) lives in `src/shared/Roster.lua`, generated by `tools/generate_roster.py` from role templates scaled by tier, with the signature characters set by hand.

| Role | Built for | At the very top |
|---|---|---|
| Wing spiker (WS) | the highest Attack and Jump | up to 210 Attack, 190 Jump (YeJun, the only Thunder Spiker: 210 / 190); Dante (Feral Leap) has the game's highest Attack, 222 |
| Middle blocker (MB) | the tallest (196 to 206 cm), a big Jump, less Attack | about 170 Attack, 180 Jump |
| Setter (SE) | Speed and Defense | 160 to 180 on both |

Everyone owns three free D-tier starters, one per role (Riku, Daichi and Hana). In a match you take your character's role when it's free. Bots are fully upgraded roster characters, picked for their role at the tier nearest the bot level, and they wear the avatars and names of your Roblox friends (the character's name shows under theirs).

**Gold** raises stats. A recruit starts at 55% of the way from 50 to each of its ceilings; in Players you open a character's page and spend Gold on each stat (+ and - by 1, 5 or 10 points: taking points back refunds them exactly). The Players screen filters by role (WS, MB, SE), shows only your favourites (the star on a character's page), and its Information tab explains the character's ability. A point costs more the higher the stat and the higher the character's rank, so an S+ costs the most and goes the highest (maxing YeJun takes about 19,800 Gold). Wing spikers want Attack and Jump, middles Jump and Defense, setters Speed. You earn 300 Gold for a win, 150 for a loss and 20 per kill, ace or block; a new profile starts with 3,000.

Stats map onto gameplay the same way for everyone, from 50 up to 210. Attack sets a power multiplier from 0.45 to 1.00 for spikes and serves. Jump adds vertical on top of your standing reach on a curve that lets the best jumpers pull away (0.3 to 2.24 m), and makes the run-up faster and longer. Defense sets the team stamina pool (50 to 100), cuts stamina drain by up to 35%, and improves receives and blocks. Speed sets run speed (22 to 32) and set accuracy. Standing reach is 1.3 cm per cm of height, and your hitting point is standing reach plus your Jump vertical: the lowest starter (Hana, fresh) hits about 2.6 m and the best maxed jumpers 4.3 to 4.4 m, so a fresh YeJun (3.4 m) has to upgrade Jump to reach the 4.00 m Thunder line. The readout shows your hand's height: a ball met above your hand still counts as your own top.

The world is built at *The Spike*'s scale (4.6 studs to the metre, a real 9 m half court, a 2.43 m net) with characters about 1.15 m tall, and heights above the standing hand are drawn 1.4 times taller (`Config.Scale.JumpScale`), so the best jumpers leap almost three times their own height and hit at twice the net while the readouts stay in real metres. Workspace gravity is 45 and the ball falls at 11.25 m/s².

**V Points (VP)** pay for recruits. You earn 30 for a win, 15 for a loss and 2 per kill, ace or block, the match MVP gets 15 more, and a new profile starts with 500. Every extra set you choose to play pays +20 VP and +200 Gold if you win it (+10 and +100 if you lose it). A **win streak** pays from your second straight win: +5 VP and +50 Gold more per win in the streak, up to +25 and +250; a loss or a forfeit resets it (the tutorial doesn't count). Home shows your career counters: win streak (and best), wins (of matches played), spike kills, aces and blocks. **Leaderboards** (Ranks on Home) rank everyone on wins, best win streak, spike kills, aces, blocks, Robux spent and Robux gifted: the top 50 of every server (global OrderedDataStores, read every two minutes, with the players in your server always up to date), your rank or your number, and headshots. Without DataStore access (Studio without API access) they rank the players in the server. Recruit x1 costs 50 VP (a free recruit, from the tutorial, is used first), x10 500:

| Banner | What it gives |
|---|---|
| Basic Recruit | a roster character. D and C tiers are Common, B Rare, A Epic, S Legendary, S+ Mythic (0.5%) |
| Spike style | Full Bow, Scissor Kick, Double Hammer, Whirlwind, Tornado 360 (Legendary: a full spin on the way up, then the whip) and Bicycle Kick (Mythic: back to the net, a backflip, and the ball kicked over the head at the contact) |
| Spike color | the colour of your spike ribbon and impact: Crimson to Prism |
| Trail | Comet, Sparkle, Flame, Lightning or Stardust behind your spikes |
| Score effect | where your attack lands for a point: Shockwave, Fire Explosion, Meteor Strike, Thunderbolt |

Rarity odds are Common 55%, Rare 28%, Epic 12.5%, Legendary 4% and Mythic 0.5%, spread over the rarities a banner has; within a rarity, lower sub-tiers are more common. A duplicate turns into VP (Common 5, Rare 12, Epic 30, Legendary 80, Mythic 250), and the **auto-sell** toggles do the same for new pulls of Common, Rare or Epic rarity. **Auto-roll** recruits x1 again and again until it hits Legendary or better, runs out of VP, reaches 100 spins, or you press Stop.

The Shop's packs are Developer Products: 500 / 1,200 / 2,800 / 6,500 VP, 5,000 / 12,000 / 28,000 / 65,000 Gold, 1 / 3 / 5 / 10 lucky spins, and 15 minutes / 30 minutes / 1 hour / 3 hours of 2x VP. Each has a product (Creator Hub > your experience > Monetization > Developer Products) whose id is in `Config.Shop.Packs`, `Config.Shop.GoldPacks`, `Config.Lucky.Packs` or `Config.Boosts.Packs`; the Shop shows the price set there. A pack with id 0 (no product yet) shows "Soon", and in Studio it's granted for free. Each purchase is granted once and only reported as done after the profile holding it has been saved. Purchases in Studio are Roblox's free test purchases: they grant the pack but don't count on the Robux spent boards.

**Perks** (the Shop's Perks column) cost 3,000 VP or a 199 Robux game pass each. **Custom sound effects** takes your own sound ids for scoring, spikes, jumps, serves, receives, sets, blocks and feints (pick one with the arrows, paste the id, Save; everyone in the match hears them). **Custom score effect** pops your own image up when you score. A sound only plays if it's public or shared with the experience.

**Player cards** (the Locker's Cards tab) are what everyone sees when you score a point: your headshot, name and character on a card with its own colours, border and pattern, and a number of yours in big type. They're unlocked by playing, not by recruiting, and stay unlocked: Rookie (everyone), On Fire (a 5-match win streak; shows your current streak), Unstoppable (10 in a row; your best streak), Winner and Champion (25 and 100 wins; your wins), Spike Machine (250 spike kills), Ace Server (50 aces), The Wall (100 blocks), MVP (25 match MVPs), Veteran (200 matches), Collector (20 players recruited), Top 3 (a top-3 place on any leaderboard, in gold, silver or bronze; shows the place and the board) and Number One (#1 on any board). Locked cards show your progress ("40 / 250").

**Codes** (Home's Codes button) pay VP, Gold, lucky spins or characters, once per player. The first is **RELEASE**: 500 VP, 5,000 Gold and a lucky spin. Codes live in `Config.Codes` (the key is the code in lower case; `Until` makes one expire).

**Daily rewards** (Home's Daily button, with a red dot when one is waiting): one a day, 20 hours apart, along a week (50 VP, 1,000 Gold, 75 VP, 2,000 Gold, 100 VP, 3,000 Gold, then 150 VP and a lucky spin); a claim more than 48 hours after the last starts the week over. Codes and daily rewards are for members of the group that owns the game who liked it: the windows show both steps, with Roblox's own join prompt for the group. Roblox can't tell a game who liked it, so that step is an "I liked it" button (the player's word, asked once); the group is checked each time.

**Lucky spins** (the gold strip on Recruit Player) pull from any banner with better odds: no Commons, Rare 48%, Epic 34%, Legendary 15% and Mythic 3% (a normal recruit: 4% and 0.5%). Lucky x1 and x10 use the ones you have, or buy that many for Robux; they also come from codes, daily rewards, gifts and the admin panel. Lucky odds opens their probability table. The Shop's second tab sells packs of 1, 3, 5 and 10.

**2x V Points boosts** (the Shop's second tab): 15 minutes, 30 minutes, 1 hour or 3 hours of double VP from your matches (the MVP bonus too), in real time from when you get it; another adds on top, up to a day. Home shows yours counting down, and it multiplies with the admin panel's 2x VP event.

**Gifts**: every pack (VP, Gold, lucky spins, boosts) can be bought for someone else, by username or user id, or picked from the players in your server. It reaches them at once wherever they are, or when they next join.

**The admin panel** (developers only): start 2x VP or 2x Gold for 5, 10, 15, 20 or 30 minutes in every server (every match pays double, the showcase says so, and Home shows the time left), send an announcement to every player in every server (through Roblox's text filter), and give anyone VP, Gold, lucky spins and characters by username or user id.

**Developers** own every character and unlockable, recruit and upgrade for free: the place's owner (or the group's owner), anyone in a Studio test session, and any UserId listed in `Config.Developers.UserIds`.

## Abilities

Abilities come with characters, one per role, at the top tiers.

| Ability | Who | What it does |
|---|---|---|
| Thunder Spiker | YeJun only (S+ wing spiker) | any spike or jump serve hit above 4.00 m becomes a lightning spike of 160 to 200 km/h at full Attack |
| Azure Dragon | S+ wing spikers | charge in the air (below) |
| Feral Leap | Dante (S+ wing spiker) | charge on the ground, leap from far out (below) |
| Adrenaline | S wing spikers | while the team's stamina is under 40%, +18 Attack and +16 Jump: you jump higher and hit harder, with a red aura |
| Iron Wall | S middle blockers | press Q (L2): for 3 s every ball that reaches your block is stuffed, whatever its power, pierce and Thunder included. 20 s cooldown |
| Chain Reaction | S setters | passive: your sets are charged: the ball glows red and sparks, with a red arc. The spike off one explodes: 15% more speed, 2.4 times the receive drain plus 16 flat that no timing saves you from. A feint off a charged set explodes too |
| Vector Set | Ilya (S setter) | passive: your sets pulse violet and go tight to the net and high (60% of the usual distance, 1.2 m higher), so the attacker hits steeply from close in. The spike off one gains power by its angle: the steeper the line from the contact to where it lands, the more (none at 22 degrees below level, the full +22% at 42 degrees and steeper). The boost pops up at the contact ("+14.3%"). Bot hitters aim short off her sets for the full angle, and a Vector bot always jump-sets |
| Turnabout | Haeri (S setter) | press Q (L2): for 8 s your next second touch (set or bump) turns into a spike over the net by itself, before the block can read it. Jump-set it: taken high it's a real spike deep into their court (12% more power); too low to hit down, it's a quick dump over the tape. 18 s cooldown |
| Rising Sun | Daon (S wing spiker) | passive: every 3 points the other team scores this set raises your Sunrise level (up to 4 at 12 points), each worth +10 Attack, +9 Jump, +3 Defense and +6 Speed. At level 0 Daon is a low A; at level 4 every stat is above a maxed YeJun. Daon's badge shows the level; it burns as an orange aura and resets with the score each set |
| Rally Cry | Joon (S middle blocker) | press Q (L2): your whole team plays with +12% on every stat (Attack, Jump, Defense, Speed) for 10 s: higher jumps, faster runs, harder spikes. A gold tag on everyone's HUD shows it. 30 s cooldown |
| Counter Edge | Ines (S wing spiker) | passive: every ball of theirs you dig fills your Counter meter: a hard spike (0.8 per km/h, 40 to 100 a time, so one of 125 km/h or more fills it) with no guard lost and no guard break (blades burst out of you and sink back in), anything else +30. The meter adds up to +40 Attack and +70 Defense (170 / 130 empty, 210 / 200 full), and your next spike releases all of it for up to +12% more speed on top (about 157 km/h maxed at a full meter), then it starts again. It resets each set |

Azure Dragon charges in the air. Hold Spike after takeoff to gather energy from a gauge that refills on the ground over 3 s; the bar fills in 0.8 s. While charging you float down slowly (85% of gravity cancelled on the way down, so charging never raises your hitting point), drift 25% faster in the air, a pulsing blue orb gathers on your hitting hand with sparks, a light and a spinning ring, and a white-blue arc curves up behind you as the energy fills (it flashes when full and turns red when overcharged). A full bar multiplies spike speed by 1.44 and pierces blocks (except an Iron Wall), and holding 0.28 s past full overcharges the swing so it flies out.

Feral Leap charges on the ground. Hold Jump (Space, Z, J or left click; the Jump button on touch) and a violet arc in front of Dante fills over 0.6 s while he runs up to 45% faster; a tap is the usual run-up jump. It works on the serve too: Space on the ball in his hands tosses it high and keeps charging while held (or hold Jump once any toss is up), and letting go leaps after his own toss (the carry is aimed at the ball, no more than the charge gives); the jump serve takes the charge like a spike (up to 40% faster, about 182 km/h maxed). Let go and he leaps the way you hold (at the net when you hold nothing), carried along the court by the charge for the whole flight: a full one carries him about 7 m further than a plain jump, and Move still drifts on top. The spike off the leap is up to 40% faster with the charge (about 204 km/h from a maxed Dante at full, a full Azure's 201) and spins harder, with a magenta comet trail. A full charge leaping at the net smashes through a block whose Attack is lower than his (the ball keeps 85% of its speed and is still a spike to dig; Iron Wall still stuffs it), and his first full charge of the match hits 15% harder again ("First Strike!", about 235 km/h). He reaches 15% wider for a spike and his forward serve toss goes 1.6 times as far. Played by the AI (a bot, or a stand-in), the gauge fills in the air on its own, at 85% of his Attack and three quarters of the charge's bonus.

In a match every ability on the court is a round badge at the side of the screen, named underneath: yours on the left with your teammates' beside it, the other team's down the right edge (on touch, yours top left and theirs in a row top right). A ring around each icon fills clockwise with what drives it: the charge (Feral Leap, Azure Dragon; seen on other players too), the Counter meter, the Sunrise level, the hitting point toward 4.00 m (Thunder), stamina toward Adrenaline's line, or an active's cooldown, with the seconds left over the icon. It throbs when it's full or ready, and the line under the name says READY, ON, FIRST STRIKE, FULL or RELEASE!.

Boom jumps (the shockwave and boom off the floor) need a Jump stat of 170 or more; everyone else just kicks up a little dust.

## How the volleyball works

Spike power comes from contact, not a timing meter. The cleaner your hand meets the ball and the closer that is to the top of your jump, the harder the spike: at full Attack an edge contact is around 110 km/h and a perfect one at the apex about 140. Direction comes from where you are relative to the ball. A ball right at your hand goes deep, a ball further ahead of you (toward the net) comes down short and steep, and a ball behind your head sails long. You steer by where you jump from and how you drift in the air.

The team stamina bars at the top of the screen work as a guard meter. Receiving a hard ball (above 60 km/h) drains your team's bar, and the drain climbs steeply with speed: about 13 for a 110 km/h spike, 27 for 140 and 50 for 180 (less with more Defense; team pools are 50 to 100), so two badly timed receives of a 180 km/h spike break an average guard. The drain also scales with the receiving side's rank: an S+ takes the full amount and every tier below takes less, down to a quarter for D- (so a 140 km/h spike costs an S+ team about 18 and a D- team about 4). A receive pressed a little early (between 0.08 and 0.42 s before contact) is perfect, shows a shield and pays only 15% of the drain, rising to 40% against spikes of 180 km/h and more, and a hard spike makes a clean PERFECT rarer. Heavy balls knock the receiver back and stagger them, and the drain pops up as "Guard -N". Below half the bar turns red and receives get unreliable. The ball that empties it breaks the guard and blasts off the receiver, flying out behind them past the end line, and with a broken guard a spike of 90 km/h or more simply can't be received, except with a slide. Slides, soft-block deflections, free balls and feints never drain. After every rally the winner recovers 10% and the loser 20%, each set starts full, and a timeout refills both teams.

When a ball is yours to play and you don't go for it (no receive, slide, jump or touch in the last second), the nearest bot on your team covers it: it digs the receive, sets it, or sends a free ball over. If you swing and miss (a whiffed spike or dig), the cover goes for the ball straight away and sends it over. When you move onto a teammate's spot, say up to the net to block, that bot drops into the spot you left.

Setters jump-set: a bot setter takes an open or back set at the top of a jump when the pass comes down near the net (better setters almost always), and a set taken higher goes higher (the height above a standing set is added to the set's peak). Quicks stay quick. A human can jump-set too: jump, then Set in the air. A setter that isn't under the ball in time sets it from the ground instead. A Turnabout bot sometimes arms it, but only for a pass it can jump for; a Rally Cry bot pops it at a serve once it's ready.

Bots play at the lobby's bot level even when their character is a lower tier (an S+ lobby has S middles and setters, and they play at S+ skill).

The bot setter feeds the wing spiker first. Off a good pass it sometimes runs a quick to the middle instead (better setters more often), and a bot middle is already in the air when the set is made. On every set to the wing spiker the middle jumps just behind as a backup: if the wing spiker misses, the middle spikes it.

Bots below A- serve the easy underhand serve (always in); from A- up they toss full height, a little forward, and jump serve (only jump serves can miss, less often the higher the tier).

Bots play by tier on top of their stats. A D- team reacts late (0.32 s), mistimes jumps, frames spikes, misses digs and serves, and rarely blocks; an S+ team is clean. Offline, a D- bot gets a dig, spike and serve through cleanly about a third of the time, an S bot about nine times in ten.

Receives and sets go high, and they never go over the net except on the third touch (a free ball). Sets draw a dotted arc and hang about 1.6 s before arriving at hitting height. Serves are hit from behind the end line within 8 s: the overhand serve is a safe lob of about 50 km/h, and a jump serve from an S+ runs around 125 km/h. Blocks can stuff, soft-block, get tooled off the hands or just touch the ball.

In 3v3 the roles are wing spiker, middle blocker and setter, and humans take wing spiker first. A match is one set to 15. When it ends, everyone on court gets 12 s to vote **Keep playing** (another set, for the extra set rewards) or **End match**; it goes on if more players want to keep playing than to stop, up to three sets. The match winner is the team with the most sets (then the most points, then the last set). The yellow diamond between the scores shows the points the set is played to. At 14-14 it's deuce: you have to win by two, so the target rises with every tie (16, then 17, ...) and the diamond turns red, up to a golden point at 25. A timeout (two per set) refills stamina and opens a rotation editor for both teams: Up and Down reorder your rotation, and Serve turns it so that player serves next. "Character and look" lets you switch to another of your characters (you keep your spot and role) or change your spike style, colour, trail and score effect. The timeout ends early once everyone on court has pressed Ready.

## Matches and lobbies

Press **Match** on Home:

- **Quick Match** (1v1, 2v2 or 3v3) drops you into the fullest open public quick lobby of that mode, or opens one. It starts on its own after 10 s (or when full), with bots in the empty spots. **Cancel queue** leaves it.
- **Lobbies** lists the lobbies in the server you can see: public ones, friends-only ones if you're the host's friend, and private ones with a lock (they ask for the password).
- **Create Lobby**: the mode, who can join (Public, Friends only, or Private with a 3 to 12 character password), Fill with bots (on: start any time; off: both teams must be full) and the bot level. In your lobby you see both teams, can switch sides, and the host can remove players, change the settings and press Start.

A lobby plays on this server's court when it's free. When the court is busy it gets its own server: everyone in it is teleported to a reserved server with the lobby's settings, and after the match the lobby stays together there for a rematch. In Studio (no teleports) lobbies take turns on the court. Only lobby members play; everyone else stays in the menus.

If a player leaves, or gives no input for 12 s while the ball is live, an AI takes their spot on the spot: the same character, build and ability in the player's own avatar, marked "(AI)". An AFK player gets a Rejoin banner on Home and takes the spot back at the next serve. A match with no humans left (and nobody who could rejoin) is called off. The MVP of a finished match earns 15 extra V Points.

Every match opens with a **matchup intro** (about 7 s, before the first serve): each team in turn stands in a row facing you on pedestals in its colour, every player in their equipped **intro pose** with their name over their head, while a plate along the bottom shows the team's emblem and name, the mode and court, and a chip per character (tier, character, role, ability). A wipe in the other team's colour brings on the other side, then both names meet around a VS and the court comes back. At the end, the **showcase** lines up your team again: VICTORY in their poses with sparkles, or DEFEAT with hands on knees, and a card under each player with their tier, name and @username (AI for bots), their Spikes, Blocks and Aces, and their digs and top spike speed, the MVP tagged. Your VP, Gold and win streak run along the bottom; Continue closes it.

## Visuals and audio

The loading screen (in ReplicatedFirst, all GUI shapes) is one held frame: a flat amber screen, a pillar of light with a black ball at its top, and the SPIKE RUSH logo top left (white heavy italic letters over an ink outline, an orange rim and an ink extrude, RUSH in an orange gradient with speed marks). While the game loads, a quiet "Loading" line with a thin bar sits on the right and a tip bottom left. Once the client has started and your avatar has loaded, its silhouette rises into the pillar and freezes in the bow-draw, the pointing hand just under the ball, with "Click to continue". A click, tap or key plays the swing: the ball blasts away under an impact flash and speed lines, and the screen fades into the game. `tools/generate_icon.py` draws the game icon and thumbnail (`assets/icon/GameIcon.png`, 512x512, and `Thumbnail.png`, 1920x1080) in the same style; upload them in the Creator Hub.

Spike, receive and set are keyframed animations: the spiker's arms swing up on takeoff and draw back like a bow straight after (arched back, hitting arm cocked behind the head, the other arm up at the ball, legs kicked back), held for the whole flight until the swing, which whips through on contact and follows through into the fall; receives drive up through a platform, sets catch at the forehead and push up onto the toes (back sets arch), and landings crouch. The camera is a long-lens side view from the open near side, which keeps perspective flat like a 2D game. During play it's fully zoomed out: one fixed wide shot of the whole court, both serve spots and the highest sets, fitted to your screen's shape. The Follow camera setting brings back the tracking view, which rises and pulls back for high sets, closes in on your serve and swings to a low angle after a point. Spikes leave thick ribbon trails that shed stars: yellow for Thunder (with lightning crackling along the whole flight), cyan for Azure and hot pink into red for anything over 120 km/h, chased by sonic-boom rings. Every attack shows a reticle snapping onto the ball, a starburst, a ring and dark debris streaks, the biggest hits flash neon streaks across the screen, perfect receives raise a gold shield over the receiver, and jumps boom off the floor. The biggest hits flash a manga impact frame: the screen goes white and the attacker becomes a black silhouette over a coloured burst. The HUD shows the km/h and hitting height of the last attack under the score, "Team (Player) scored" with the reason after each point, receive grades like "PERFECT 96", and your tier badge, height and a marker over the player you control. Impact frames, speed lines, shake, the landing marker, the closer camera and receive assist can all be toggled in settings.

Every sound is one of the owner's own uploads: the ids go in `Assets.Sounds` (each slot says when it plays), and an empty slot is silent. `Assets.SoundFiles` holds, per upload, the silence to skip at the front of the file and a gain that evens out how loud the files are. Sounds play from loaded copies in `SoundService.SpikeRushSoundBank`, so a sound starts on its moment, and run through a mix bus (a compressor that lets each attack through, low and high lift, a touch of hall). Hits at the ball play at full volume anywhere on court, panned by position. A match's sounds (hits, whistles, the crowd, jumps, abilities, custom sounds) play only for the players in it: someone in the menus, or away while their AI plays, hears nothing of a match in their server. The generated sounds in `assets/sfx` (`tools/generate_sfx.py`) aren't used in the game.

Every visual and audio slot also takes a Toolbox (Creator Store) asset, with no code changes: the ball model (the match ball and every ball in the menus), the menu props (lockers, bench, ball cart), twenty particle effects (impacts, the jump boom, the guard break, the Azure aura, the four score effects and the five ball trails), sounds, action animations and ability icons. Drag an asset into `ReplicatedStorage.ToolboxAssets.<Category>.<Slot>`, or paste ids into `Assets.Toolbox` and bake them with `ToolboxService.install()` from the command bar, or let `ToolboxService` load them when the server starts (any free model once Game Settings > Security > "Allow Loading Third Party Assets" is on). A slot can take one piece of a bigger pack (`"<id>/<path>"`), sized with a `Scale` attribute. Scripts inside inserted assets are always deleted. [TOOLBOX.md](TOOLBOX.md) lists every slot with what fills it now and what to search for. Bots play Roblox's own default R15 idle, run, jump and fall animations.

## Tuning

Nearly every number lives in `src/shared/Config.lua`. The sections you'll touch most are `Hits` (spike speeds, depths, thunder, sets, tosses), `Stamina`, `Timeout`, `RoleTemplates` and `TierScale` (bots and the roster generator), `Stats`, `StatCurve`, `Height`, `Progression` (VP rewards), `Spins` (costs, character rarity, sell values, auto-roll), `Rarity`, `Cosmetics`, `Shop` (VP and Gold packs), `Developers`, `Abilities`, `Player` (jumps, hang time, run-up, slides, blocks), `Bots` (skill by tier) and `Match` (set targets, deuce cap). Keep `Config.Player.Gravity` in step with the Workspace gravity in `default.project.json`.

Courts live in `Config.Courts` (names, the Quick Match rotation, each court's stands and crowd) and `ArenaBuilder` (their paint, scenery and lighting). The play area is the same on every court.

To bake the generated arena into the place for hand-editing, run this in the Studio command bar in edit mode and save the place; a baked arena's core is kept at runtime and its court still changes per match:

```lua
require(game.ServerScriptService.Server.Services.ArenaBuilder).build({ bake = true })
```

## Project layout

```
default.project.json   Rojo tree (remotes, gravity, StarterPlayer settings)
serve.bat, serve.sh    start `rojo serve` for live sync
aftman.toml, rokit.toml  toolchain pins (Rojo 7.7.0)
src/shared/            deterministic code used by both server and clients
  Config.lua           every tuning number
  Characters.lua       tiers, builds, role templates, stat curves, jump heights
  Roster.lua           the named characters (generated by tools/generate_roster.py)
  Spins.lua            banners, odds, drop tables, sell values, colour and trail helpers
  Settings.lua         cleans the settings a player saves (switches, the touch layout)
  Lobbies.lua          lobby rules: settings, privacy and passwords, seating, starting,
                       Quick Match, the teleport round trip, the AFK timer
  HitLogic.lua         every touch: zones, power, direction, stamina, sets, serves, blocks
  BallPhysics.lua      analytic ball paths, net and floor events
  Court.lua            court geometry, role lanes, formations (and filling a moved human's
                       spot), rotation edits, the deuce target, stands
  Assets.lua           asset slots, Toolbox ids and the sanitizer
  Net.lua, Util.lua
src/server/Services/   ToolboxService (Toolbox assets by id), FriendService (bots wear your
                       friends' avatars), CharacterService, ArenaBuilder, BallService,
                       TeamService (teams, AI stand-ins, AFK), ProfileService (saves, Gold
                       upgrades, recruits), BotService, HitService (validation), LobbyService
                       (lobbies, Quick Match, reserved servers), MatchService (flow, scoring,
                       timeouts, rewards)
src/first/             the loading screen (ReplicatedFirst)
src/client/Controllers/ State, Input, Movement, Action (touches and prediction),
                       BallRenderer, Camera, VFX, Animation, Audio, UI (the match HUD),
                       Gui (the menus' UI kit), Scene (the club room and gym sets, recruit
                       balls, the Locker preview), Menu (every menu screen and the recruit
                       sequence), Lineup (the matchup intro and the showcase after a match),
                       MobileControls (and the touch layout editor), Crowd
tools/                 checkers, the simulation suite, the SFX, icon, avatar and roster generators,
                       and pose_preview.py (draws Studio-posed avatars to check a pose)
assets/                volleyball mesh, the generated sound effects, the icon and thumbnail
TOOLBOX.md             every Toolbox slot and how to fill it
reference/             local-only screenshots of The Spike (not synced, not committed)
```

## Development

Game code is written in a Lua 5.1/5.3 compatible subset of Luau (no `+=`, `continue`, type annotations or backtick strings) so the offline checks can run it outside Roblox. After any change, run all four:

```
python3 tools/check_lua.py      # syntax and undefined globals
python3 tools/check_config.py   # every Config reference exists
python3 tools/check_api.py      # every cross-module call is defined
texlua tools/sim_test.lua       # 94 gameplay scenarios against the real shared code
```

The simulation suite checks the headline numbers (spike speeds, Thunder and Azure ranges, hitting points by tier, depth control, stamina and guard breaks, touch rules, sets, serves, blocks, the roster, role abilities, spin odds and drop tables, deuce, rotation edits, formation fill, bot skill by tier, the Gold upgrade costs, tier-scaled guard drain, middle quicks and the backup spike, the forward serve toss, lobby rules, the AFK timer, the underhand serve, the practice drills and the tutorial, extra-set and win-streak rewards, leaderboard ranking, the five newer S abilities and jump sets, Feral Leap's gauge, block break, first strike and carry) and that client prediction is bit-identical to the server.

## Status

Every check above passes and the project builds and serves with Rojo 7.7.0, but the game has not been run in Roblox Studio yet, so expect a round of runtime fixes and feel tuning (camera framing, jump and hang feel, run-up distance, bot difficulty, stamina numbers) on the first playtest.
