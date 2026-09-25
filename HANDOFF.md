# Handoff: continuing Spike Rush

This file is for whoever picks the project up next (including a new AI session). Read it together with README.md, which covers setup, controls and every player-facing mechanic. This file covers what the owner asked for, how the code fits together, what has and hasn't been verified, and what to do next.

## What the owner asked for

Spike Rush is modelled on *The Spike* (SUNCYAN) and its sequel The Spike Cross. The owner wants high balls, high verticals and high power in a 2.5D side view on a bigger court. They also want tiers from D- to S+ that anyone can pick, with lower tiers genuinely weaker.

Only two abilities exist. Thunder Spiker turns a contact above 4.00 m into a power spike. Azure Dragon lets you jump and charge the spike in the air under reduced gravity, and a full bar hits hardest.

They asked to keep the stadium and to add:

- ball trails and boom jump effects;
- impact frames;
- a km/h and hitting-height readout at the top, under the score.

**Spike power** comes from contact quality, with no timing or hold meter. The position of the character relative to the ball decides whether the spike goes more down or more forward. At the peak of S+, a weak contact should be about 110 km/h and a well-timed one about 140. Thunder at 4 m or higher should reach about 160 to 200, and Azure should be similar.

**Receives and sets** go high. Bumps and sets must never cross the net, except the last (third) touch or when a powerful spike breaks the team's stamina. Sets get a dotted arc.

**Stamina** works like The Spike Cross guard meter:

- Heavy receives drain it. White means clean, red means unreliable (out, shank or pop-up), and broken means strong spikes can't be received.
- There is no drain for slide receives, soft-block deflections, free balls, easy passes or weak feints.
- It partly refills at the end of a rally, and timeouts reset it for everyone on court.
- Defense raises the pool and lowers the drain.

The latest request was: "the jumps should not all be standardized. the tier of your character sets your cap. upgrade stats like the spike mechanics." An earlier version of that message also said "you can roll for heights". That is now implemented as four upgradeable stats capped by tier, rolled heights with a paid re-roll, and upgrade points earned by playing and saved to a DataStore. Whether the paid height re-roll should stay is still an open question for the owner.

**Assets.** The owner originally wanted The Spike's own sounds and visuals copied in. That was declined, and the project builds original equivalents instead: procedural effects and 26 synthesized sounds. Keep it that way.

In the second session the owner asked to use the Roblox Toolbox heavily for VFX, animations, the ball model, sounds and UI. Toolbox (Creator Store) assets are fine; anything ripped from The Spike is not. Gameplay code from the Toolbox (ball physics, hitboxes, movement kits) is deliberately not used, because it would break the deterministic client prediction; TOOLBOX.md explains this to the owner.

**Screenshots.** The owner shared 11 screenshots of The Spike during the first session, and they are not in this zip. The pieces built from them are:

- the top bar with team names, VS and stamina bars;
- the "129.75 km/h 3.85 m" readout;
- thick yellow, red and pink ribbon trails with lightning;
- a white starburst and ring at contact;
- a white landing ellipse on the floor;
- "GOOD 71" receive grades with a shield on perfect receives;
- "Free Ball!";
- the dotted set arc;
- a blue triangle over the controlled player;
- the "Team (Player) scored" banner with a reason tag;
- a white impact frame with a red burst;
- speed lines;
- a blue near-side net post.

Substitution and pause buttons, and skill icons, also appeared in those screenshots but were not built. Ask the owner to re-share the screenshots if visual matching matters.

## World and scale

The court's long axis is Z, with the net at z = 0. Home plays z < 0 (left of screen) and Away plays z > 0 (right). Y is up and X is depth: the camera sits on the open near side around x = -64 and looks toward +X.

The ball always travels in the x = 0 plane. Players are locked to role lanes (`Config.Lanes`: WS -1.2, MB 0.2, SE 1.4, Solo 0), so they only ever move along Z.

The scale is 4.6 studs per metre (`local M` in Config), matching The Spike: the net top is 11.2 studs (2.43 m), the end lines are at z = ±41.4 (9 m), the attack lines at ±13.8 (3 m), and the court half-depth toward the camera is 14 studs (visual only). Workspace gravity is 45 and the ball uses its own gravity (51.75 studs/s², 11.25 m/s²). A Roblox avatar (about 5.3 studs) stands for a 1.15 m character.

Roles: 3v3 uses WS, MB and SE (humans claim WS first, then MB, then SE); 2v2 uses WS and SE; 1v1 uses Solo. The serve order rotates on side-out.

## How the code fits together

The server boots in this order from `src/server/Main.server.lua`, passing each service a shared registry `reg`:

1. ToolboxService
2. CharacterService
3. ArenaBuilder
4. BallService
5. TeamService
6. ProfileService
7. BotService
8. HitService
9. MatchService

The client boots from `src/client/Main.client.lua`, passing each controller the table `mods`:

1. AudioController
2. BallRenderer
3. CameraController
4. VFXController
5. AnimationController
6. MovementController
7. InputController
8. ActionController
9. UIController
10. MobileControls
11. CrowdController

`State` holds shared client state and signals.

**A touch**, end to end:

1. ActionController turns input into an action.
2. It builds the input and context and runs `HitLogic.compute` from `src/shared`. This is deterministic, with its random numbers seeded by the ball sequence number.
3. BallRenderer applies the result instantly as a prediction.
4. The client sends `HitRequest`.
5. HitService validates it: timestamp window, the reported ball position against the server's own path, the root position tolerance, touch rules, rate limit, and sanitized inputs (receive-stance age, Azure energy, set type, toss height).
6. HitService recomputes with the same HitLogic and launches through BallService, which broadcasts `BallState`.
7. If validation fails, the client gets `HitReject` and rolls back.

Bots call `HitService.botAction` and go through the same pipeline.

**Stamina and timeouts** are server-owned in TeamService. They replicate as ReplicatedStorage attributes `Stamina_<Team>`, `StaminaMax_<Team>` and `Timeouts_<Team>`, and the client passes its reading of them into its prediction. The drain from a touch is applied only in HitService, which announces guard breaks. MatchService handles recovery after rallies, the refill at set start and timeouts (queued to the next dead ball).

**Characters and builds** live in `src/shared/Characters.lua`:

- `derive(tier, build)` turns a build into gameplay stats and is cached.
- `autoBuild` creates role-shaped builds for bots.
- `sanitize` clamps any build to its tier's rules.
- `jumpHeight` works out the Humanoid.JumpHeight that reaches the build's hitting point.

**Saving** is handled by ProfileService. It uses DataStore `SpikeRushProfiles_v1` with key `u_<UserId>`, storing `{ v, points, builds[tier] = { Height, Attack, Defense, Speed, Jump } }`. A profile is only saved if it loaded successfully, so a failed load never overwrites real data.

The active build is written as attributes (Tier, Height, Attack, Defense, Speed, Jump, Ability) onto the Player and the character. The client derives its prediction stats from those; the server uses `entity.charStats`, snapshotted when the match assigns teams. Picks and upgrades for your active character are rejected while your match runs, which keeps both sides identical.

**Toolbox assets** (`ToolboxService`, `Assets.lua`): every visual and audio slot resolves in this order: an instance in `ReplicatedStorage.ToolboxAssets.<Category>.<Slot>`, then an id in `Assets`, then the procedural or built-in fallback. `ToolboxService` fills empty `Models`/`VFX` slots from `Assets.Toolbox` at server start (InsertService: owner's or Roblox's assets only), and `ToolboxService.install()` bakes them from the command bar with `game:GetObjects`. `Assets.sanitize` deletes every script in an inserted asset and makes its parts inert; clients sanitize their clones too. BallRenderer rebuilds the ball's look when `Models.Volleyball` arrives late.

**Remotes** (`Net.lua`):

| Remote | Payload |
|---|---|
| BallState | ball snapshot to clients |
| HitRequest | client touch |
| HitReject | rejection, triggers rollback |
| ActionFX | Slide, Block, Whiff, Jump, Charge, ChargeEnd, Stance cosmetics |
| MatchState | match snapshot |
| Announce | Point, Serve, SetStart, SetEnd, MatchStart, MatchEnd, Break, Timeout, TimeoutCalled |
| ClientReady | client finished loading |
| Vote | `("mode", 1\|2\|3)` or `("botTier", tier)` |
| SetCharacter | `(tier, ability)` |
| Timeout | call a timeout |
| Profile | client sends `"get"`, `("upgrade", tier, stat, n)` or `("reroll", tier)`; server replies with a snapshot |

**Jump physics.** A hang force cancels 45% of gravity while the vertical speed is under 9 studs/s. The same rule runs in MovementController for players and in BotService for bots. That hang adds about 0.74 studs to the apex (`Characters.hangGain`), and `Characters.jumpHeight` subtracts it, so the true apex equals the build's hitting point; this was verified numerically. The Azure hover cancels 62% of gravity, but only while charging and falling, so charging never raises the hitting point.

## Checks

Code must stay in a Lua 5.1/5.3 compatible subset of Luau: no `+=`, `continue`, type annotations or backtick strings. The offline tools need python3, `texlua` and `texluac` (LuaTeX's Lua 5.3). Run all four after every change and keep them at zero:

```
python3 tools/check_lua.py      # syntax (texluac) and undefined globals
python3 tools/check_config.py   # every Config reference, including local aliases, exists
python3 tools/check_api.py      # every Module.fn / reg.Service.fn / mods.Controller.fn is defined
texlua tools/sim_test.lua       # 51 scenarios run against the real shared modules
```

On Debian or Ubuntu, `apt-get install texlive-binaries` provides `texlua` and `texluac`.

Nested config aliases such as `local AZURE = Config.Abilities.Azure` are not covered by `check_config.py`, so check those by hand. When you change a mechanic, add or update a scenario in `sim_test.lua` that proves the numbers.

## Status

All the code for the 2.5D game is written and every check passes, including all 51 simulations. The project builds and serves with Rojo 7.7.0 (verified with `rojo build` and a live `rojo serve`). The sound effects are generated in `assets/sfx` but not yet uploaded. The owner has connected Rojo in Studio; no runtime errors have been reported back yet.

### Second session (continuation)

- **Rojo pinned to 7.7.0** in `aftman.toml` and a new `rokit.toml`. The previous pin (7.4.4) speaks sync protocol 4; the current Studio plugin speaks 5 and refuses it. Added `serve.bat` and `serve.sh`.
- **Toolbox pipeline**: `ToolboxService`, `Assets.Toolbox`, `Assets.sanitize`, new VFX slots (`NetImpact`, `JumpBoom`, `GuardBreak`, the held `AzureAura`), ability icon slots, and TOOLBOX.md.
- **Fixes found by review**: the `Slide` animation slot never played (the pose is called `Dive`); stance animations (`Charge`, `Block`, `Stance`) now play from their slots; Toolbox VFX Models now fire at the contact point instead of where the model was built; Toolbox emitters that loop are switched to bursts; the profile could load twice when a match started during the DataStore read; a player who left mid-load was cached forever.
- **Bots** now play Roblox's default R15 idle/run/jump/fall on each client (`Assets.BotAnimations`), with the procedural run cycle as the fallback, and uploaded action animations play on bots too.
- **Optimizations**: `State.myStats()` is cached until the build attributes change; the root CFrame (players and bots) is only rewritten when facing is actually off, which also removes a source of ground stutter; hang forces are only written when they change; VFX parts use a free list, and rings and starbursts reuse pooled BillboardGuis; set-arc dots skip their loop when none are alive; the calm crowd updates at 6 Hz instead of 20; the HUD top bar is event-driven and slow panels refresh at 20 Hz; positional sounds reuse their attachments.
- The network policy of that session blocked Roblox, Steam, the App Store and Google, so no Toolbox asset ids were checked and no reference screenshots were downloaded. `reference/README.md` lists the sources; screenshots in `reference/` are gitignored because the repository is public.

### Third session (first playtest feedback)

The owner reported the game "feels weak" and asked for an overhaul. Their answers on the design rules: every number stays (110/140 km/h, Thunder 160 to 200 at 4.00 m, Azure about 200, hitting points in metres), but jumps must look far higher, like The Spike, where players fly above the net and the readout still says about 4 m; gravity lower; spikes "a little stronger".

- **Anime jumps** (shared, deterministic): `Characters.studsAt` / `metersAt` map real metres to world studs. Up to `Config.Scale.HeightFloor` (6.9 studs, the standing hand) the scale is true; above it every metre is drawn `JumpScale` (2.0) times taller. `contactMaxStuds` uses the mapping, and `HitLogic.meters` (every `meta.height`, the Thunder check) maps back, so all readouts and the Thunder line are unchanged. A maxed S+ now jumps 12.1 studs (was 5.7) and hangs 1.8 s. Workspace gravity 60 to 45 (also in `default.project.json`), ball gravity 40 to 36, hang window 10 to 9. Sets, passes and tosses were raised to meet the new contact heights (`SetArriveY` 17.5, open, quick and back set apexes 30, 22 and 29, tosses 18 to 28). Seven new simulations prove it.
- **Power floor**: Attack's multiplier range is now 0.45 to 1.0 (was 0.3) and new characters start halfway to their cap (was 35%), so a fresh S+ spikes about 100 km/h (was 75). Maxed numbers are unchanged. Hit-stop is a little longer.
- **Lobby**: `Config.Match.RequirePick`: the intermission waits for a mode pick; the countdown starts after the first pick. The client shows "Pick 1v1, 2v2 or 3v3".
- **Bot cover**: `HitService.intentAge(id)` records each human's last attempt (stance, slide, jump, block, charge, any hit request; the mobile assist now reports its stance). When a ball is a human's to play, the nearest teammate bot shadows it (`Config.Bots.CoverDepth` deeper) and plays it unless that human tried something within `CoverYield` (1 s): receives, sets (back to that human), and free balls on a third touch the human skips. Not covered by the simulations (it needs Roblox instances).
- **Control rail** on the left (UIController `buildRail`/`updateRail`): one round button per action with its key or gamepad badge, lit from `State.context`, clickable; hidden on touch devices.
- **Lighting** toned down (exposure -0.25, bloom 0.18, saturation 0.02, thin atmosphere, dimmer panels, no neon trims).
- **Animations**: AnimationController now has keyframed clips (`CLIP_DEFS`: Swing, Bump, Set, SetBack, Land) sampled with easing, plus airborne poses by jump kind (Rise on the way up, Cock at the top, SpikeFollow after the swing). `AnimationController.jumped(id, kind)` is fed by MovementController (local) and the `Jump` ActionFX (others; bots now announce block jumps too).
- **Sound**: `tools/generate_sfx.py` recipes redone in The Spike's style (original synthesis: clap-like smacks, sub booms, air tears, metallic shing, finger taps, a room convolution) and a new `ImpactFrame` stinger; regenerated. In game: layered stand-ins (a Fallback entry can be a list of layers with delays), a mix bus (compressor, EQ, reverb) on the SFX group, and a crowd gasp on hard digs.
- **VFX**: thicker, longer ribbons with sparkle emitters; lightning along the whole Thunder flight; sonic-boom ellipses behind hard spikes; a contact reticle and debris streaks on every attack; neon screen streaks on the biggest hits; a gold shield above perfect receivers; a floor ring under receives; the impact frame gained a glow, a light pillar and a gold crescent; bigger jump booms; stronger camera punch.

### Fourth session: "when I jump sometimes it doesn't let me spike"

No mechanic changed; the input got forgiving. With the 1.8 s anime airtime players press while waiting at the top, and a press more than 0.14 s before the ball entered reach used to whiff (and lock swings for 0.32 s), so the swing animation played but no spike happened. Also, for the first frames after takeoff `FloorMaterial` still reported the floor, so a quick second press started another run-up.

- ActionController: a spike, feint or jump-serve press in the air commits the swing. It looks 0.6 s ahead (`SPIKE_WINDOW`), predicting your root with gravity, the hang force and the Azure hover, and the ball's path. If the ball comes into reach, the swing waits and lands at the first moment the contact is at least 0.25 clean (`MIN_CONTACT`), or as the ball starts to leave reach. Early presses therefore spike but weakly (committed swings average about 0.3 contact, 112 to 118 km/h at full Attack); a press on time still hits cleanest. An offline press simulation: across all press moments in a jump that can reach the ball, 16 to 20% used to spike and 41 to 48% do now.
- A real miss says why: too early, too late, ahead of you, behind you, over the net, or the touch rule. `Config.Player.WhiffCooldown` is 0.2 s (was 0.32).
- Airborne means `FloorMaterial == Air` or the humanoid state is Jumping/Freefall, in ActionController and MovementController.
- New simulation: with the best jump timing, an open set stays in reach 0.18 s (fresh S+) to 0.35 s (maxed S+).

### Fifth session: animations, The Spike's scale, stamina nerf

- **Animations never showed**: Roblox's Avatar Joint Upgrade (on by default for new experiences, and not settable from scripts or the project file) spawns R15 rigs with `AnimationConstraint` joints instead of `Motor6D`. AnimationController only looked for Motor6Ds, so it found no joints. It now takes both, keyed by the body part each joint moves (`JOINT_FOR_PART`), writes `Transform` in `RunService.PreSimulation` (the documented point, after the Animator), and skips a frame when `Animator.EvaluationThrottled`. MovementController's physics step moved to PreSimulation too.
- **Scale**: measured from the owner's screenshots, The Spike uses a true-size court (9 m halves, 2.43 m net, hitting points true to the net) with characters drawn about 1.15 m tall. `Config` now has `local M = 4.6` (studs per metre) and every world distance is written in metres times M; values tied to the avatar's body (hit zones around the root, lanes, `PassArriveY`, `TossLow`) stay in studs. `JumpScale` is back to 1: the net and court grew instead, so a maxed S+ hand (19.1 studs) sits 1.7x the net (11.2 studs), as in The Spike. HitLogic, BallPhysics, Court, BotService, ArenaBuilder (`LEN` stretches the hall's z layout), BallRenderer, CameraController and VFXController literals were converted. Walk speeds 22 to 32, slide 50, approach boost 18. The spike zone grew (radius 2.9 x 2.8 studs) so a set, which now falls faster in studs, stays in reach 0.17 to 0.25 s. The simulation suite multiplies its old world literals by `K = SPM / 3.2`.
- **Stamina nerf** (the owner: a 180 km/h spike shouldn't be "eaten up with nothing happening"): drain = 38 x ((kmh - 60) / 100) ^ 1.5 before Defense; the perfect-timing share rises from 0.15 (up to 100 km/h) to 0.4 (180 km/h, `HitLogic.perfectDrainMul`); `IncomingSpeedPenaltyMax` 0.5 makes clean PERFECTs on monster spikes rarer; pools 50 to 100; rally recovery 10% / 20%. HitLogic adds `meta.knock` (0 to 1 above 90 km/h): the receiver is shoved back (MovementController.knockback locally, BotService.knockback for bots via HitService), plays the Knockback pose, shows "Guard -N", and the team's stamina bar shakes. Perfectly timed receives still pay the least, which keeps the design rule; the owner asked for the nerf.

These are the spots most likely to need attention on the first playtest:

| Area | What to check |
|---|---|
| Rojo | The plugin must be 7.7.x (`rojo plugin install`, then restart Studio); "Can't parse JSON" or a protocol error on Connect means an older plugin |
| Scale | The whole hall is bigger (4.6 studs/m): check the camera frames the play, bots cover the longer court, and serves reach from behind the end line |
| Joints | Poses must show on both AnimationConstraint and Motor6D rigs; Output should have no "[SpikeRush] animation" warnings |
| Jumps | Humanoid.JumpHeight is about 11.5 studs for a maxed S+; check the apex reaches the hitting point (the readout should show the lobby's hitting point on a perfect spike) and the air time feels right (tune `JumpScale`, `Player.Gravity`, `HangGravityCancel`) |
| Bot cover | Stand still while a ball comes to you: a teammate bot should dig it. Press receive early instead: the bot must hold off. Watch for bots stealing balls on high ping |
| Animation clips | Spike (rise, bow-draw, whip, follow-through), receive, set and landing read in profile for players and bots |
| Input | W and S double as Block and Receive while the default control script also reads them as forward/back. MovementController overrides `Humanoid:Move` every frame at RenderPriority Input+1; confirm there's no depth drift and no double actions |
| Lane lock | The HumanoidRootPart CFrame and X velocity are corrected every physics step, for players and bots; watch for jitter during slides and jumps |
| Animation | AutoRotate is off and facing is set by CFrame (only when it's more than about 2.5 degrees off). Procedural poses are layered over the Animator through Motor6D.Transform in Stepped; check they blend and read in profile |
| Bot animation | Each client creates a local Animator on the server-owned bots and plays Roblox's default R15 tracks; if they don't load within 8 s the procedural cycle takes over. Check bots run, jump and idle, and that Output has no "Failed to load animation" |
| Impact frame | Clones the attacker's character into a ViewportFrame (Archivable toggled briefly); check it lines up with the real camera and works for other players' characters |
| Bots | Jump timing uses a simulated jump that includes the hang force. Check spikes connect, Azure bots arrive with a full bar, blocks are on time, and the lane lock doesn't fight their movement |
| Saving | Needs "Enable Studio Access to API Services"; verify save and load, the session-only fallback, and that a failed load never gets written back |
| Toolbox | Runtime loading needs the asset in the owner's inventory; otherwise Output shows a `[SpikeRush] Toolbox ... did not load` line. A Toolbox ball is rescaled and centred; check it spins around its centre |
| Mobile | Movement reads the thumbstick X through the control module's `GetMoveVector`; the default jump button is hidden |
| UI | The "▼" player marker and "⚙" settings glyphs rely on Roblox font fallback |
| Camera | Long lens (FOV 34, 64 studs back); high sets must stay in frame at 16:9 and on phones |
| Performance | Rings and starbursts are pooled BillboardGuis; popups are still created per receive grade |

## Next steps

Work in this order:

1. Playtest in Studio. Fix runtime errors; the game's own warnings in Output are prefixed `[SpikeRush]`.
2. Tune the feel:
   - in `Config.Player`: the run-up gather, dash and boost, air control, and hang;
   - in `CameraController`: the camera distances;
   - `Config.Bots` for bot skill and `Config.Stamina` for drain.
3. Fill the Toolbox slots (TOOLBOX.md) and upload the `assets/sfx` files into `Assets.Sounds`.
4. Lower `Config.Progression.StartingPoints` (300, for testing) before launch.
5. Optional additions: uploaded action animations in `Assets.Animations`, substitution and pause buttons.
6. Ask the owner about the height re-roll (still open).
