# Spike Rush

An anime volleyball game for Roblox in a 2.5D side view, modelled on the feel of *The Spike* (SUNCYAN): huge jumps, high sets, spikes measured in km/h, a team stamina "guard" meter, and named characters you roll for, each with a role, a tier and maybe an ability. Everything in this project is original. The court, effects, UI, loading screen, game icon and all 27 sound effects are procedural or synthesized from scratch, and nothing is taken from The Spike.

The whole game is a Rojo project. The server is authoritative, and the shared gameplay math is deterministic, so every client predicts its own touches with exactly the numbers the server will use.

## Getting started

Install the toolchain once with `rokit install` or `aftman install` (both pin Rojo 7.7.0). Then start the live sync with `serve.bat` (Windows) or `./serve.sh` (macOS, Linux), or run `rojo serve` in this folder yourself, and press Connect in the Rojo plugin in Roblox Studio. The plugin has to be Rojo 7.7.x: older servers speak sync protocol 4, and the current plugin refuses them. `rojo plugin install` installs the matching plugin.

To start from a place file instead, open `SpikeRush.rbxlx` (built with `rojo build -o SpikeRush.rbxlx`) and connect Rojo from there. Press Play: the server builds the arena at startup and you land on the Home screen. Press Match, then Quick Match (or make a lobby with Fill with bots on) to play; bots fill every empty slot, so the game is fully playable solo.

Player progress (V Points, Gold, the characters you own, their upgraded stats and the one you play, unlocked cosmetics, auto-sell choices) is saved with DataStoreService. In Studio this only works after enabling Game Settings > Security > "Enable Studio Access to API Services" on a published place. Without it the game still runs, profiles just last for the session, and the Home screen says so.

The project file sets Workspace gravity to 45 (the server also enforces it at startup), turns off mouse lock, and uses JumpHeight rather than JumpPower.

## Controls

The keyboard layout follows The Spike's, with WASD and mouse alternatives.

| Action | Keyboard / mouse | Gamepad | What it does |
|---|---|---|---|
| Move | A / D or ← / → | Left stick | You only move along the court; your role sets your depth lane |
| Spike | Z, J or left click | A or R2 | On the ground: run-up jump. In the air: spike. Azure Dragon: hold in the air to charge, release to swing |
| Receive | ↓, S, K or right click | B | Arms a receive stance for 0.8 s; the touch happens by itself when the ball arrives |
| Slide / feint | C, Shift or L | RB | On the ground: slide receive (never costs stamina). In the air: a soft roll shot |
| Block | ↑ or W | Y | Hold to crouch and charge, release to jump; near the net (1.5 m) the ball that passes your hands is blocked |
| Jump | Space | | A plain jump |
| Set | E or V | LB | Hold toward the net for a quick set, away for a back set, nothing for an open set |
| Serve | X | X | Tap for an overhand serve that hits itself; hold to toss for a jump serve (longer = higher toss; hold toward the net as you let go to throw it forward and run into it), then Spike to jump and Spike again to hit. A dotted line shows where the toss will go, and you can't walk past the end line until the serve is hit (jumping over it is fine) |
| Ability | Q | L2 | Active abilities only (Iron Wall) |
| Timeout | T | Select | Two per set; takes effect at the next dead ball, refills stamina and opens the rotation editor |
| Forfeit | Forfeit button (top right) | | Tap twice within 3 s: your team concedes the match and gets no VP |

On a keyboard or gamepad, the compact control rail on the left edge of the screen shows every action as a text pill with its key (the badges switch to gamepad buttons when you use one), lights up whichever action is live right now, and can be clicked. On touch devices the thumbstick moves you and the buttons mirror the keyboard (Spike, Receive, Slide/Feint, Block, Set, Serve and Jump). Receive assist is on by default for touch: it arms the stance for you, with the pass quality capped at 0.62 so manual timing is always better.

## Menus

Outside a match you're in the menus, drawn over two small 3D sets built on your client: a sunlit club room with your own avatar in it, and a school gym with a vaulted timber ceiling and a stage.

- **Home**: your profile card (headshot, name, the character you play, V Points and Gold), the featured S+ recruit, tips, Players / Locker / Shop / Settings / Help, and the two big buttons, Recruit Player and Match. When your AI is standing in for you in a match, a Rejoin banner appears.
- **Recruit Player**: the Player banner (Basic Recruit) and the Cosmetic banners, the Probability Table (every pull with its exact chance and whether you own it), auto-roll, auto-sell, and Recruit x1 (50 VP) / x10 (500 VP). A recruit plays out like *The Spike*'s: sparkles on black (gold when an S is inside), the volleyballs sweep under the gym ceiling glowing in their rarity colours, then line up over the stage ("Click to Continue") and open one by one. Before an S or S+ opens, a short cinematic plays: a yellow screen, a beam of light, and your own avatar's silhouette leaping and hammering a black ball down in your equipped spike style. Then the reveal card (your avatar in the character's role pose, tier, role, height, ability, stat ceilings) and the results. **Skip** jumps straight to the next S. During auto-roll a running line replaces the sequence, and the one that hits Legendary plays in full.
- **Players**: every character (recruited ones first), who you play, and the Gold upgrades (below).
- **Locker**: equip spike styles, colours, trails and score effects. Whatever you click previews live in the gym: your avatar spikes on a loop with that style, the ball flies with that colour and trail, and lands with that score effect.
- **Shop**: V Point packs.

## Characters, Gold and V Points

You play named characters, like *The Spike*'s. Each one is a preset: a role, a tier (D- to S+), a height, four stat ceilings (Attack, Defense, Speed, Jump) and, at the top tiers, an ability. The roster (33 characters) lives in `src/shared/Roster.lua`, generated by `tools/generate_roster.py` from role templates scaled by tier, with the signature characters set by hand.

| Role | Built for | At the very top |
|---|---|---|
| Wing spiker (WS) | the highest Attack and Jump | up to 210 Attack, 190 Jump (YeJun: Thunder Spiker, 195 / 190) |
| Middle blocker (MB) | the tallest (196 to 206 cm), a big Jump, less Attack | about 170 Attack, 180 Jump |
| Setter (SE) | Speed and Defense | 160 to 180 on both |

Everyone owns three free D-tier starters, one per role (Riku, Daichi and Hana). In a match you take your character's role when it's free. Bots are fully upgraded roster characters, picked for their role at the tier nearest the bot level, and they wear the avatars and names of your Roblox friends (the character's name shows under theirs).

**Gold** raises stats. A recruit starts at 55% of the way from 50 to each of its ceilings; in Players you spend Gold on each stat (buttons for 1, 5 and 10 points, up or down: taking points back refunds them exactly). A point costs more the higher the stat and the higher the character's rank, so an S+ costs the most and goes the highest (maxing YeJun takes about 18,400 Gold). Wing spikers want Attack and Jump, middles Jump and Defense, setters Speed. You earn 300 Gold for a win, 150 for a loss and 20 per kill, ace or block; a new profile starts with 3,000.

Stats map onto gameplay the same way for everyone, from 50 up to 210. Attack sets a power multiplier from 0.45 to 1.00 for spikes and serves. Jump adds vertical on top of your standing reach on a curve that lets the best jumpers pull away (0.3 to 2.24 m), and makes the run-up faster and longer. Defense sets the team stamina pool (50 to 100), cuts stamina drain by up to 35%, and improves receives and blocks. Speed sets run speed (22 to 32) and set accuracy. Standing reach is 1.3 cm per cm of height, and your hitting point is standing reach plus your Jump vertical: the lowest starter (Hana, fresh) hits about 2.6 m and the best maxed jumpers 4.3 to 4.4 m, so a fresh YeJun (3.4 m) has to upgrade Jump to reach the 4.00 m Thunder line. The readout shows your hand's height: a ball met above your hand still counts as your own top.

The world is built at *The Spike*'s scale (4.6 studs to the metre, a real 9 m half court, a 2.43 m net) with characters about 1.15 m tall, and heights above the standing hand are drawn 1.4 times taller (`Config.Scale.JumpScale`), so the best jumpers leap almost three times their own height and hit at twice the net while the readouts stay in real metres. Workspace gravity is 45 and the ball falls at 11.25 m/s².

**V Points (VP)** pay for recruits. You earn 30 for a win, 15 for a loss and 2 per kill, ace or block, the match MVP gets 15 more, and a new profile starts with 500. Recruit x1 costs 50 VP, x10 500:

| Banner | What it gives |
|---|---|
| Basic Recruit | a roster character. D and C tiers are Common, B Rare, A Epic, S Legendary, S+ Mythic (0.5%) |
| Spike style | Full Bow, Scissor Kick, Double Hammer, Whirlwind |
| Spike color | the colour of your spike ribbon and impact: Crimson to Prism |
| Trail | Comet, Sparkle, Flame, Lightning or Stardust behind your spikes |
| Score effect | where your attack lands for a point: Shockwave, Fire Explosion, Meteor Strike, Thunderbolt |

Rarity odds are Common 55%, Rare 28%, Epic 12.5%, Legendary 4% and Mythic 0.5%, spread over the rarities a banner has; within a rarity, lower sub-tiers are more common. A duplicate turns into VP (Common 5, Rare 12, Epic 30, Legendary 80, Mythic 250), and the **auto-sell** toggles do the same for new pulls of Common, Rare or Epic rarity. **Auto-roll** recruits x1 again and again until it hits Legendary or better, runs out of VP, reaches 100 spins, or you press Stop.

VP packs are Developer Products (the Shop screen); set their ids in `Config.Shop.Packs`. Until then they show "Soon", and in Studio they grant their VP for free.

**Developers** own every character and unlockable, recruit and upgrade for free: the place's owner (or the group's owner), anyone in a Studio test session, and any UserId listed in `Config.Developers.UserIds`.

## Abilities

Abilities come with characters, one per role, at the top tiers.

| Ability | Who | What it does |
|---|---|---|
| Thunder Spiker | S+ wing spikers | any spike or jump serve hit above 4.00 m becomes a lightning spike of 160 to 200 km/h at full Attack |
| Azure Dragon | S+ wing spikers | charge in the air (below) |
| Adrenaline | S wing spikers | while the team's stamina is under 40%, +18 Attack and +16 Jump: you jump higher and hit harder, with a red aura |
| Iron Wall | S middle blockers | press Q (L2): for 3 s every ball that reaches your block is stuffed, whatever its power, pierce and Thunder included. 20 s cooldown |
| Chain Reaction | S setters | passive: your sets are charged: the ball glows red and sparks, with a red arc. The spike off one explodes: 15% more speed, 2.4 times the receive drain plus 16 flat that no timing saves you from. A feint off a charged set explodes too |

Azure Dragon charges in the air. Hold Spike after takeoff to gather energy from a gauge that refills on the ground over 3 s; the bar fills in 0.8 s. While charging you float down slowly (85% of gravity cancelled on the way down, so charging never raises your hitting point), drift 25% faster in the air, and a pulsing blue orb gathers on your hitting hand with sparks, a light and a spinning ring. A full bar multiplies spike speed by 1.44 and pierces blocks (except an Iron Wall), and holding 0.28 s past full overcharges the swing so it flies out.

Boom jumps (the shockwave and boom off the floor) need a Jump stat of 170 or more; everyone else just kicks up a little dust.

## How the volleyball works

Spike power comes from contact, not a timing meter. The cleaner your hand meets the ball and the closer that is to the top of your jump, the harder the spike: at full Attack an edge contact is around 110 km/h and a perfect one at the apex about 140. Direction comes from where you are relative to the ball. A ball right at your hand goes deep, a ball further ahead of you (toward the net) comes down short and steep, and a ball behind your head sails long. You steer by where you jump from and how you drift in the air.

The team stamina bars at the top of the screen work as a guard meter. Receiving a hard ball (above 60 km/h) drains your team's bar, and the drain climbs steeply with speed: about 13 for a 110 km/h spike, 27 for 140 and 50 for 180 (less with more Defense; team pools are 50 to 100), so two badly timed receives of a 180 km/h spike break an average guard. The drain also scales with the receiving side's rank: an S+ takes the full amount and every tier below takes less, down to a quarter for D- (so a 140 km/h spike costs an S+ team about 18 and a D- team about 4). A receive pressed a little early (between 0.08 and 0.42 s before contact) is perfect, shows a shield and pays only 15% of the drain, rising to 40% against spikes of 180 km/h and more, and a hard spike makes a clean PERFECT rarer. Heavy balls knock the receiver back and stagger them, and the drain pops up as "Guard -N". Below half the bar turns red and receives get unreliable. The ball that empties it breaks the guard and blasts off the receiver, flying out behind them past the end line, and with a broken guard a spike of 90 km/h or more simply can't be received, except with a slide. Slides, soft-block deflections, free balls and feints never drain. After every rally the winner recovers 10% and the loser 20%, each set starts full, and a timeout refills both teams.

When a ball is yours to play and you don't go for it (no receive, slide, jump or touch in the last second), the nearest bot on your team covers it: it digs the receive, sets it, or sends a free ball over. If you swing and miss (a whiffed spike or dig), the cover goes for the ball straight away and sends it over. When you move onto a teammate's spot, say up to the net to block, that bot drops into the spot you left.

The bot setter feeds the wing spiker first. Off a good pass it sometimes runs a quick to the middle instead (better setters more often), and a bot middle is already in the air when the set is made. On every set to the wing spiker the middle jumps just behind as a backup: if the wing spiker misses, the middle spikes it.

Bots play by tier on top of their stats. A D- team reacts late (0.32 s), mistimes jumps, frames spikes, misses digs and serves, and rarely blocks; an S+ team is clean. Offline, a D- bot gets a dig, spike and serve through cleanly about a third of the time, an S bot about nine times in ten.

Receives and sets go high, and they never go over the net except on the third touch (a free ball). Sets draw a dotted arc and hang about 1.6 s before arriving at hitting height. Serves are hit from behind the end line within 8 s: the overhand serve is a safe lob of about 50 km/h, and a jump serve from an S+ runs around 125 km/h. Blocks can stuff, soft-block, get tooled off the hands or just touch the ball.

In 3v3 the roles are wing spiker, middle blocker and setter, and humans take wing spiker first. Matches are best of three sets to 15, with the deciding set to 11. The yellow diamond between the scores shows the points the set is played to. At 14-14 it's deuce: you have to win by two, so the target rises with every tie (16, then 17, ...) and the diamond turns red, up to a golden point at 25. A timeout (two per set) refills stamina and opens a rotation editor for both teams: Up and Down reorder your rotation, and Serve turns it so that player serves next.

## Matches and lobbies

Press **Match** on Home:

- **Quick Match** (1v1, 2v2 or 3v3) drops you into the fullest open public quick lobby of that mode, or opens one. It starts on its own after 10 s (or when full), with bots in the empty spots. **Cancel queue** leaves it.
- **Lobbies** lists the lobbies in the server you can see: public ones, friends-only ones if you're the host's friend, and private ones with a lock (they ask for the password).
- **Create Lobby**: the mode, who can join (Public, Friends only, or Private with a 3 to 12 character password), Fill with bots (on: start any time; off: both teams must be full) and the bot level. In your lobby you see both teams, can switch sides, and the host can remove players, change the settings and press Start.

A lobby plays on this server's court when it's free. When the court is busy it gets its own server: everyone in it is teleported to a reserved server with the lobby's settings, and after the match the lobby stays together there for a rematch. In Studio (no teleports) lobbies take turns on the court. Only lobby members play; everyone else stays in the menus.

If a player leaves, or gives no input for 12 s while the ball is live, an AI takes their spot on the spot: the same character, build and ability in the player's own avatar, marked "(AI)". An AFK player gets a Rejoin banner on Home and takes the spot back at the next serve. A match with no humans left (and nobody who could rejoin) is called off. The MVP of a finished match earns 15 extra V Points.

## Visuals and audio

A loading screen (in ReplicatedFirst, all GUI shapes) shows soft grey light, rising bubbles, light rays and a spinning yellow, blue and white ball over the title, with tips and a progress bar, and fades out once the client has started. `tools/generate_icon.py` draws the game icon and thumbnail (`assets/icon/GameIcon.png`, 512x512, and `Thumbnail.png`, 1920x1080) in the same style; upload them in the Creator Hub.

Spike, receive and set are keyframed animations: the spiker's arms swing up on takeoff, draw back like a bow at the top (arched back, hitting arm cocked, legs kicked back), whip through on contact and follow through into the fall; receives drive up through a platform, sets catch at the forehead and push up onto the toes (back sets arch), and landings crouch. The camera is a long-lens side view from the open near side, which keeps perspective flat like a 2D game. It rises and pulls back for high sets, closes in on your serve and swings to a low angle after a point. Spikes leave thick ribbon trails that shed stars: yellow for Thunder (with lightning crackling along the whole flight), cyan for Azure and hot pink into red for anything over 120 km/h, chased by sonic-boom rings. Every attack shows a reticle snapping onto the ball, a starburst, a ring and dark debris streaks, the biggest hits flash neon streaks across the screen, perfect receives raise a gold shield over the receiver, and jumps boom off the floor. The biggest hits flash a manga impact frame: the screen goes white and the attacker becomes a black silhouette over a coloured burst. The HUD shows the km/h and hitting height of the last attack under the score, "Team (Player) scored" with the reason after each point, receive grades like "PERFECT 96", and your tier badge, height and a marker over the player you control. Impact frames, speed lines, shake, the landing marker, the closer camera and receive assist can all be toggled in settings.

All 27 sound effects are synthesized by `tools/generate_sfx.py` into `assets/sfx/<Key>.ogg`, and they are already generated. They follow *The Spike*'s sound design without using any of its audio: spikes are a palm smack with a sub boom and an air tear, hard spikes hit like an explosion, a perfect dig rings with a metallic shing, sets are a finger double-tap, and the impact frame gets its own swell-and-slam stinger, all in a light arena room. In game they run through a mix bus (compressor, low-end lift, hall reverb).

Until you upload them the game uses layered Roblox built-in client sounds as stand-ins. The quickest upload: Studio's Asset Manager > Bulk Import on `assets/sfx`, then drag the imported audio into `ReplicatedStorage.ToolboxAssets.Sounds` (each Sound keeps its file name, which is its key). Or paste each id into `Assets.Sounds`. Unverified accounts can only upload a few audio files a month, so start with Spike, SpikeHeavy, Bump, ReceivePerfect, Set, FloorHit, Boom, Thunder, ImpactFrame and Whistle.

Every visual and audio slot also takes a Toolbox (Creator Store) asset, with no code changes: the ball model, eleven particle effects (impacts, the jump boom, the guard break and the Azure aura), sounds, action animations and ability icons. Drag an asset into `ReplicatedStorage.ToolboxAssets.<Category>.<Slot>`, or paste ids into `Assets.Toolbox` and bake them with `ToolboxService.install()` from the command bar, or let `ToolboxService` load them when the server starts. Scripts inside inserted assets are always deleted. [TOOLBOX.md](TOOLBOX.md) lists every slot with what to search for. Bots play Roblox's own default R15 idle, run, jump and fall animations.

## Tuning

Nearly every number lives in `src/shared/Config.lua`. The sections you'll touch most are `Hits` (spike speeds, depths, thunder, sets, tosses), `Stamina`, `Timeout`, `RoleTemplates` and `TierScale` (bots and the roster generator), `Stats`, `StatCurve`, `Height`, `Progression` (VP rewards), `Spins` (costs, character rarity, sell values, auto-roll), `Rarity`, `Cosmetics`, `Shop` (VP packs), `Developers`, `Abilities`, `Player` (jumps, hang time, run-up, slides, blocks), `Bots` (skill by tier) and `Match` (set targets, deuce cap). Keep `Config.Player.Gravity` in step with the Workspace gravity in `default.project.json`.

To bake the generated arena into the place for hand-editing, run this in the Studio command bar in edit mode and save the place; a baked arena is kept at runtime:

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
                       sequence), MobileControls, Crowd
tools/                 checkers, the simulation suite, the SFX, icon, avatar and roster generators
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
texlua tools/sim_test.lua       # 84 gameplay scenarios against the real shared code
```

The simulation suite checks the headline numbers (spike speeds, Thunder and Azure ranges, hitting points by tier, depth control, stamina and guard breaks, touch rules, sets, serves, blocks, the roster, role abilities, spin odds and drop tables, deuce, rotation edits, formation fill, bot skill by tier, the Gold upgrade costs, tier-scaled guard drain, middle quicks and the backup spike, the forward serve toss, lobby rules and the AFK timer) and that client prediction is bit-identical to the server.

## Status

Every check above passes and the project builds and serves with Rojo 7.7.0, but the game has not been run in Roblox Studio yet, so expect a round of runtime fixes and feel tuning (camera framing, jump and hang feel, run-up distance, bot difficulty, stamina numbers) on the first playtest.
