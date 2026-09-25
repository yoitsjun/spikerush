# Spike Rush

An anime volleyball game for Roblox in a 2.5D side view, modelled on the feel of *The Spike* (SUNCYAN): huge jumps, high sets, spikes measured in km/h, a team stamina "guard" meter, and characters whose tier caps how far you can upgrade them. Everything in this project is original. The court, effects, UI and all 26 sound effects are procedural or synthesized from scratch, and nothing is taken from The Spike.

The whole game is a Rojo project. The server is authoritative, and the shared gameplay math is deterministic, so every client predicts its own touches with exactly the numbers the server will use.

## Getting started

Install the toolchain once with `rokit install` or `aftman install` (both pin Rojo 7.7.0). Then start the live sync with `serve.bat` (Windows) or `./serve.sh` (macOS, Linux), or run `rojo serve` in this folder yourself, and press Connect in the Rojo plugin in Roblox Studio. The plugin has to be Rojo 7.7.x: older servers speak sync protocol 4, and the current plugin refuses them. `rojo plugin install` installs the matching plugin.

To start from a place file instead, open `SpikeRush.rbxlx` (built with `rojo build -o SpikeRush.rbxlx`) and connect Rojo from there. Press Play: the server builds the arena at startup and the lobby waits. A match only starts once a player picks 1v1, 2v2 or 3v3 (the countdown then runs, and drops to 4 seconds once everyone has picked), and bots fill every empty slot, so the game is fully playable solo.

Player progress (upgrade points and every character's build) is saved with DataStoreService. In Studio this only works after enabling Game Settings > Security > "Enable Studio Access to API Services" on a published place. Without it the game still runs, profiles just last for the session, and the lobby says so.

The project file sets Workspace gravity to 45 (the server also enforces it at startup), turns off mouse lock, and uses JumpHeight rather than JumpPower.

## Controls

The keyboard layout follows The Spike's, with WASD and mouse alternatives.

| Action | Keyboard / mouse | Gamepad | What it does |
|---|---|---|---|
| Move | A / D or ← / → | Left stick | You only move along the court; your role sets your depth lane |
| Spike | Z, J or left click | A or R2 | On the ground: run-up jump. In the air: spike. Azure Dragon: hold in the air to charge, release to swing |
| Receive | ↓, S, K or right click | B | Arms a receive stance for 0.8 s; the touch happens by itself when the ball arrives |
| Slide / feint | C, Shift or L | RB | On the ground: slide receive (never costs stamina). In the air: a soft roll shot |
| Block | ↑ or W | Y | Hold to charge, release to jump; within 5 studs of the net the ball that passes your hands is blocked |
| Jump | Space | | A plain jump |
| Set | E or V | LB | Hold toward the net for a quick set, away for a back set, nothing for an open set |
| Serve | X | X | Tap for an overhand serve that hits itself; hold to toss for a jump serve (longer = higher toss), then Spike to jump and Spike again to hit |
| Timeout | T | Select | Two per set; takes effect at the next dead ball and refills stamina |

On a keyboard or gamepad, the control rail on the left edge of the screen shows every action with its key (the badges switch to gamepad buttons when you use one), lights up whichever action is live right now, and can be clicked. On touch devices the thumbstick moves you and the buttons mirror the keyboard (Spike, Receive, Slide/Feint, Block, Set, Serve and Jump). Receive assist is on by default for touch: it arms the stance for you, with the pass quality capped at 0.62 so manual timing is always better.

## Characters, tiers and upgrades

A character is a tier, a height and four stats: Attack, Defense, Speed and Jump. The tier does not fix your stats. It sets the ceiling, both for each stat and for the four-stat total, so no build can max everything and the build you choose matters. Every tier is its own saved character with its own height and stats; pick one in the lobby and it becomes the one you play.

| Tier | D- | D | D+ | C- | C | C+ | B- | B | B+ | A- | A | A+ | S- | S | S+ |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Stat cap | 105 | 110 | 115 | 120 | 125 | 130 | 135 | 140 | 145 | 150 | 155 | 160 | 165 | 170 | 175 |
| Total cap | 375 | 395 | 410 | 430 | 445 | 465 | 480 | 500 | 515 | 535 | 550 | 570 | 585 | 600 | 620 |

The A row reproduces The Spike's example A-rank wing spiker, 155 Attack, 120 Defense, 120 Speed and 155 Jump. Stats map onto gameplay the same way at every tier, from 50 up to 175. Attack sets a power multiplier from 0.45 to 1.00 for spikes and serves. Jump adds 0.40 to 1.75 m of vertical on top of your standing reach and makes the run-up faster and longer. Defense sets the team stamina pool (60 to 130), cuts stamina drain by up to 35%, and improves receives and blocks. Speed sets run speed (16 to 24) and set accuracy.

Jumps are drawn the way *The Spike* draws them: heights are true to scale up to your standing hand, and every metre above it is drawn twice as tall (`Config.Scale.JumpScale`), so a maxed S+ leaps about 12 studs and hangs for about 1.8 s, far above the net, while every readout, hitting point and the 4.00 m Thunder line stay in real metres. Workspace gravity is 45 and the ball's is 36.

Height is rolled when a character is created, on a bell curve around 185 cm between 165 and 205. Standing reach is 1.3 cm of reach per cm of height, and your hitting point at the top of a jump is standing reach plus your Jump vertical. That is why jumps are not standardized: a maxed S+ at 185 cm hits at about 4.15 m, a maxed S+ at 170 cm tops out just under the 4.00 m Thunder line, and a tall 200 cm A-rank can clear it. Height changes reach, hitting point and hit-zone size, not the avatar's size, and every avatar shape reaches its build's number because jump height is measured from the avatar's real standing height.

Upgrade points are earned by playing: 30 for a win, 15 for a loss, plus 2 for each kill, ace or block. One point buys +1 on a stat, and 40 points re-roll a character's height. New players start with 300 points (`Config.Progression.StartingPoints`, set high for testing; lower it before launch). A new character starts halfway from 50 to its cap, so a fresh S+ already spikes about 100 km/h and upgrades take it to 140. Your active character is locked while your match is running, which keeps client prediction identical to the server.

## Abilities

Everyone picks one of two abilities.

Thunder Spiker turns any spike or jump serve hit above 4.00 m into a lightning spike of 160 to 200 km/h at full Attack, reaching the top of that range 0.22 m above the line. Whether you can reach 4.00 m at all depends on your height and Jump stat.

Azure Dragon charges in the air. Hold Spike after takeoff to gather energy from a gauge that refills on the ground over 3 s; the bar fills in 0.8 s. While charging you hover (62% of gravity cancelled on the way down, so charging never raises your hitting point) and drift 25% faster in the air. A full bar multiplies spike speed by 1.44 and pierces blocks, and holding 0.28 s past full overcharges the swing so it flies out.

## How the volleyball works

Spike power comes from contact, not a timing meter. The cleaner your hand meets the ball and the closer that is to the top of your jump, the harder the spike: at full Attack an edge contact is around 110 km/h and a perfect one at the apex about 140. Direction comes from where you are relative to the ball. A ball right at your hand goes deep, a ball further ahead of you (toward the net) comes down short and steep, and a ball behind your head sails long. You steer by where you jump from and how you drift in the air.

The team stamina bars at the top of the screen work as a guard meter. Receiving a hard ball (above 60 km/h) drains your team's bar, less with more Defense. A receive pressed a little early (between 0.08 and 0.42 s before contact) is perfect, shows a shield and drains only 15% as much. Below half the bar turns red and receives get unreliable. The ball that empties it breaks the guard, and with a broken guard a spike of 90 km/h or more simply can't be received, except with a slide. Slides, soft-block deflections, free balls and feints never drain. After every rally the winner recovers 20% and the loser 35%, each set starts full, and a timeout refills both teams.

When a ball is yours to play and you don't go for it (no receive, slide, jump or touch in the last second), the nearest bot on your team covers it: it digs the receive, sets it, or sends a free ball over.

Receives and sets go high, and they never go over the net except on the third touch (a free ball) or when a guard break pops the ball over. Sets draw a dotted arc and hang about 1.6 s before arriving at hitting height. Serves are hit from behind the end line within 8 s: the overhand serve is a safe lob of about 50 km/h, and a jump serve from an S+ runs around 125 km/h. Blocks can stuff, soft-block, get tooled off the hands or just touch the ball.

Modes are 1v1, 2v2 and 3v3 by lobby vote, with bots filling the courts and a separate vote for the bot level (default A). In 3v3 the roles are wing spiker, middle blocker and setter, and humans take wing spiker first. Matches are best of three sets to 15, with the deciding set to 11, win by two and a cap of 25.

## Visuals and audio

Spike, receive and set are keyframed animations: the spiker's arms swing up on takeoff, draw back like a bow at the top (arched back, hitting arm cocked, legs kicked back), whip through on contact and follow through into the fall; receives drive up through a platform, sets catch at the forehead and push up onto the toes (back sets arch), and landings crouch. The camera is a long-lens side view from the open near side, which keeps perspective flat like a 2D game. It rises and pulls back for high sets, closes in on your serve and swings to a low angle after a point. Spikes leave thick ribbon trails that shed stars: yellow for Thunder (with lightning crackling along the whole flight), cyan for Azure and hot pink into red for anything over 120 km/h, chased by sonic-boom rings. Every attack shows a reticle snapping onto the ball, a starburst, a ring and dark debris streaks, the biggest hits flash neon streaks across the screen, perfect receives raise a gold shield over the receiver, and jumps boom off the floor. The biggest hits flash a manga impact frame: the screen goes white and the attacker becomes a black silhouette over a coloured burst. The HUD shows the km/h and hitting height of the last attack under the score, "Team (Player) scored" with the reason after each point, receive grades like "PERFECT 96", and your tier badge, height and a marker over the player you control. Impact frames, speed lines, shake, the landing marker, the closer camera and receive assist can all be toggled in settings.

All 27 sound effects are synthesized by `tools/generate_sfx.py` into `assets/sfx/<Key>.ogg`, and they are already generated. They follow *The Spike*'s sound design without using any of its audio: spikes are a palm smack with a sub boom and an air tear, hard spikes hit like an explosion, a perfect dig rings with a metallic shing, sets are a finger double-tap, and the impact frame gets its own swell-and-slam stinger, all in a light arena room. In game they run through a mix bus (compressor, low-end lift, hall reverb).

Until you upload them the game uses layered Roblox built-in client sounds as stand-ins. The quickest upload: Studio's Asset Manager > Bulk Import on `assets/sfx`, then drag the imported audio into `ReplicatedStorage.ToolboxAssets.Sounds` (each Sound keeps its file name, which is its key). Or paste each id into `Assets.Sounds`. Unverified accounts can only upload a few audio files a month, so start with Spike, SpikeHeavy, Bump, ReceivePerfect, Set, FloorHit, Boom, Thunder, ImpactFrame and Whistle.

Every visual and audio slot also takes a Toolbox (Creator Store) asset, with no code changes: the ball model, eleven particle effects (impacts, the jump boom, the guard break and the Azure aura), sounds, action animations and ability icons. Drag an asset into `ReplicatedStorage.ToolboxAssets.<Category>.<Slot>`, or paste ids into `Assets.Toolbox` and bake them with `ToolboxService.install()` from the command bar, or let `ToolboxService` load them when the server starts. Scripts inside inserted assets are always deleted. [TOOLBOX.md](TOOLBOX.md) lists every slot with what to search for. Bots play Roblox's own default R15 idle, run, jump and fall animations.

## Tuning

Nearly every number lives in `src/shared/Config.lua`. The sections you'll touch most are `Hits` (spike speeds, depths, thunder, sets, tosses), `Stamina`, `Timeout`, `TierCaps`, `Stats`, `StatCurve`, `Height`, `Progression`, `Abilities`, `Player` (jumps, hang time, run-up, slides, blocks), `Bots` (skill by tier) and `Match`. Keep `Config.Player.Gravity` in step with the Workspace gravity in `default.project.json`.

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
  Characters.lua       tiers, builds, heights, stat curves, jump heights
  HitLogic.lua         every touch: zones, power, direction, stamina, sets, serves, blocks
  BallPhysics.lua      analytic ball paths, net and floor events
  Court.lua            court geometry, role lanes, formations, stands
  Assets.lua           asset slots, Toolbox ids and the sanitizer
  Net.lua, Util.lua
src/server/Services/   ToolboxService (Toolbox assets by id), CharacterService, ArenaBuilder,
                       BallService, TeamService, ProfileService (saves), BotService,
                       HitService (validation), MatchService (flow, scoring, timeouts, rewards)
src/client/Controllers/ State, Input, Movement, Action (touches and prediction),
                       BallRenderer, Camera, VFX, Animation, Audio, UI, MobileControls, Crowd
tools/                 checkers, the simulation suite and the SFX generator
assets/                volleyball mesh and the generated sound effects
TOOLBOX.md             every Toolbox slot and how to fill it
reference/             local-only screenshots of The Spike (not synced, not committed)
```

## Development

Game code is written in a Lua 5.1/5.3 compatible subset of Luau (no `+=`, `continue`, type annotations or backtick strings) so the offline checks can run it outside Roblox. After any change, run all four:

```
python3 tools/check_lua.py      # syntax and undefined globals
python3 tools/check_config.py   # every Config reference exists
python3 tools/check_api.py      # every cross-module call is defined
texlua tools/sim_test.lua       # 47 gameplay scenarios against the real HitLogic
```

The simulation suite checks the headline numbers (spike speeds, Thunder and Azure ranges, depth control, stamina and guard breaks, touch rules, sets, serves, blocks, the build and upgrade rules) and that client prediction is bit-identical to the server.

## Status

Every check above passes and the project builds and serves with Rojo 7.7.0, but the game has not been run in Roblox Studio yet, so expect a round of runtime fixes and feel tuning (camera framing, jump and hang feel, run-up distance, bot difficulty, stamina numbers) on the first playtest.
