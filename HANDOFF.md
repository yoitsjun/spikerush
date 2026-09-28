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

Earlier: "the jumps should not all be standardized. the tier of your character sets your cap. upgrade stats like the spike mechanics", and "you can roll for heights". In the sixth session the owner replaced upgrade points with **V Points** "just like the spike": VP buys spins (x1 = 50, x10 = 500) for stat caps, height and animations, bought in a Shop tab. That answers the old height re-roll question (height is now a spin). The owner also asked for +10 and -1/-5/-10 buttons on stats, rollable spike colours and trails, and score effects (a fire explosion and a meteor strike to start).

On heights (sixth session): a D- was reaching nearly 4 m, while the owner's screenshot shows two S+ players at 3.85 m. Jumps should look higher, while the hitting points drop so the tiers spread out.

Seventh session, the owner's character design (replaces stat allocation and cap or tier rolls): "roll for character builds... 3 options a mb, a ws, or a setter. the ws has the highest jump and attack, reaching heights of 210 attack and 190 jump, if needed we can add more. a mb has the most height and similar jump but less attack maybe around 180 jump and 170 attack. the setter is speed and defense focused, with 160-180 being good for both. and instead of everyone having access to the abilities, you roll for them. make preset character builds with names... YeJun has Thunderspike + 195 attack + 190 jump". Abilities, one per role: MB S "completely shut down block anything" on a key; setter S passive "chemical reaction" that makes the spike or feint off her set explode, with more power, and wipe stamina fast; Thunder and Azure are S+; a normal WS S gets more jump and attack when stamina is low. Also: auto-sell for commons and epics, auto-roll until legendary, a preview of what you're rolling for, full access for developers, and boom jumps only with a Jump stat of 170+.

Eighth session: the menus should look like The Spike's (six reference screenshots: a Home screen with a profile card and currencies top left, icons on the right, an event card, Recruit Player and Match bottom right, a tip line and the character in a locker room; a Recruit Player screen with a banner list, a Player/Skin split, a big title, a Probability Table button and Recruit x1 50 / x10 500) and must look professional, "not like AI". Recruiting must not be instant: it lights up gold for an S, Skip jumps to the S unbox, and an S plays a short animation first (the owner described a yellow screen, a silhouette spiking and a beam of light), with the spike animation "based on the player's current avatar". Also: keep the stat buttons but upgrade the rolled presets with a second currency, **Gold** (like The Spike: four stats, higher ranks cost more and go higher); cancel queue; bots are the player's friends; S+ keeps the original (hard) stamina drain and lower tiers take less; the Chain Reaction ball glows red with a sparkle; an AFK (10 to 15 s) or leaving player is replaced by an AI of the same character; custom lobbies instead of waiting (private with a password, friends only, public, fill with bots); middles spike quicks the setter AI calls, and back up a wing spiker who misses; a forward serve toss, no walking onto the court while serving, and a dotted toss path; +15 VP for the MVP; hitting points from about 2.6 m (the lowest) to 4.3 to 4.4 m (maxed); the jump animation on every jump; previews for spike animations and trails.

**Assets.** The owner originally wanted The Spike's own sounds and visuals copied in. That was declined, and the project builds original equivalents instead: procedural effects and 31 synthesized sounds. Keep it that way.

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

Heights above the standing hand (6.9 studs) are drawn `Config.Scale.JumpScale` (1.4) times taller; `Characters.studsAt`/`metersAt` convert, and Config has a local `lift(m)` for heights written in metres that must meet a hitting point (`SetArriveY`, `SetApexQuick`). The scale is 4.6 studs per metre (`local M` in Config), matching The Spike: the net top is 11.2 studs (2.43 m), the end lines are at z = ±41.4 (9 m), the attack lines at ±13.8 (3 m), and the court half-depth toward the camera is 14 studs (visual only). Workspace gravity is 45 and the ball uses its own gravity (51.75 studs/s², 11.25 m/s²). A Roblox avatar (about 5.3 studs) stands for a 1.15 m character.

Roles: 3v3 uses WS, MB and SE (humans claim WS first, then MB, then SE); 2v2 uses WS and SE; 1v1 uses Solo. The serve order rotates on side-out.

## How the code fits together

The server boots in this order from `src/server/Main.server.lua`, passing each service a shared registry `reg`:

1. ToolboxService
2. FriendService
3. CharacterService
4. ArenaBuilder
5. BallService
6. TeamService
7. ProfileService
8. LeaderboardService
9. BotService
10. HitService
11. LobbyService
12. MatchService

The client boots from `src/client/Main.client.lua`, passing each controller the table `mods`:

1. AudioController
2. BallRenderer
3. CameraController
4. VFXController
5. AnimationController
6. MovementController
7. InputController
8. ActionController
9. UIController (the match HUD, results, the settings panel)
10. SceneController (the menu sets; owns the camera while one is shown)
11. MenuController (every menu screen)
12. LineupController (the matchup intro and the showcase after a match)
13. MobileControls
14. CrowdController

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

**Characters** are named presets in `src/shared/Roster.lua` (generated by `tools/generate_roster.py`; edit the templates and hand-set entries there and re-run). Each entry: `Id, Name, Role, Tier, Height, Attack, Defense, Speed, Jump, Ability`. `Roster.Starters` (a D-tier WS, MB and SE) are owned by everyone. `src/shared/Characters.lua`:

- `fromRoster(entry)` returns its tier and build; `derive(tier, build)` turns a build into gameplay stats (cached).
- `template(tier, role, height)` scales `Config.RoleTemplates` (the S+ values) by `Config.TierScale`; bots use it when the roster has nobody near their tier and role, and the sims use it (`Characters.stats`).
- `boosted(stats, add, mul)` adds stat points (`add`: `{ Attack = n, ... }`) and then multiplies every stat (Adrenaline, Rising Sun, Rally Cry); `derive` extrapolates Power past `Stats.Ref` (`StatCurve.Power.Extrapolate`) so a boosted 220+ Attack keeps adding speed; `sanitize` clamps to `Stats.Min/Max` and the height range.
- `jumpHeight` works out the Humanoid.JumpHeight that reaches the build's hitting point.

`src/shared/Spins.lua`: banners "Char" (the roster, rarity from tier via `Spins.TierRarity`, weight by sub-tier) and the cosmetic kinds. `rollItem` (rarity by weight, then an item by weight; starters never drop), `odds`, `table` (every pull with its chance: the Shop's What's inside), `sellValue`, `rarityRank`, and client helpers `equipped(model, kind)`, `tint`, `tintSequence`.

**Abilities** (Config.Abilities; the deterministic parts in HitLogic, so prediction matches):

- Boosts: `HitLogic.effectiveStats(stats, ability, stamina, extra)` (`extra`: `{ enemyPoints, teamBoost }`, a touch passes its ctx) adds Adrenaline's points while the own team's stamina is under `StaminaBelow`, Rising Sun's `PerLevel` points times `HitLogic.sunLevel(enemyPoints)`, and multiplies everything by `1 + RallyCry.Boost` while `teamBoost`. `compute` uses it for every touch and flags `meta.adrenaline`. TeamService.`refreshBoosts(team)` (on every stamina change, which includes every point and set start, on Rally Cry's start and end, and after stand-ins and joins) re-applies the humanoid's jump and run speed when the boosted table changes (derive is cached, so an unchanged boost is the same table: `e.liveStats`) and sets the `Adrenaline` and `SunLevel` attributes on the character; `TeamService.boostCtx(e)` is the server's `extra`. BotService re-times the bot's jump (`refreshJump`) and plans with the boosted stats (`statsOf`).
- Chain Reaction: sets by a ChainReaction character carry `meta.charged`. An attack whose `ctx.lastHit` is a charged set of its own team explodes: spike speed x `PowerMul`, and `meta.reaction`, `drainMul`, `flatDrain`; a feint gets the same (and loses `noDrain`). `HitLogic.isHeavy` treats reaction balls as heavy; the receive drain is `drainFor x drainMul`, then the perfect-timing share, then `+ flatDrain`.
- Active abilities (Iron Wall, Turnabout, Rally Cry): `HitService.activateAbility(entity)` (from the ActionFX "Ability" request, or a bot: Iron Wall at a block jump, Turnabout off a good pass, Rally Cry at a serve) sets `entity.abilityUntil` and `abilityReadyAt` and the `AbilityUntil`/`AbilityReadyAt` attributes (shared clock) on the character and the player; `HitService.setAbilityWindow` ends a window early. The client predicts its own press (`ActionController.abilityActive`). `TeamService.applyToModel` rewrites these attributes (and `Counter`) from the entity, so a new match starts ready.
- Iron Wall: `ctx.ironWall` (a block inside an IronWall window) makes any block a Stuff (`meta.ironWall`).
- Vector Set: a Vector setter's sets carry `meta.vectorSet` (BallRenderer pulses the ball violet, VFX rings it); her open and back sets go `SetDepthMul` of the usual distance from the net and `SetLift` higher (owner: "prioritize setting close to the net and high"). A spike whose `ctx.lastHit` is such a set of its own team gets `kmh x (1 + MaxBoost x k)`, `k` from the drop angle of the contact-to-landing line between `AngleMin` and `AngleMax`; `meta.vector`, `meta.vectorBoost` (the VFX popup "+x.x%"). Bots: a Vector setter never back-sets and always jump-sets; a hitter off a Vector set aims short enough for `AngleMax`.
- Turnabout: `ctx.turnabout` (a Turnabout character inside its window) turns its second touch (a set or a bump, not a third touch) into `turnabout()`: `meta.hitType = "Spike"`, `meta.turnabout`; from high enough a spike at `PowerMul` searched over speeds and depths until it clears the tape inside the court, else a dump (`meta.downBall`). HitService spends the window (`setAbilityWindow(entity, -1)`); the client spends its local prediction too. Animation plays `Swing_Whirl`.
- Jump sets: a set's `lift` (how far above a standing set it was taken; not for quicks) is added to the apex in `HitLogic.setArc`. BotService.`planJumpSet` times a setter's jump so it meets the pass at the top (`Bots.JumpSetChance`, `JumpSetPassDepth`; only when the pass's apex is above the jump-set contact: an earlier check on the coarse `findTime` sample rejected almost every jump set), and a setter more than `JumpSetSlack` off its spot at takeoff sets from the ground (`setStandZ`); a sim replays the plan against a real pass and the jump physics; the jump sends ActionFX "Jump" "Set" and AnimationController holds `SetCatch` in the air.
- Rising Sun: see Boosts. The HUD's Sunrise meter reads `State.enemyPoints`; VFX burns an orange aura by `SunLevel` and pops "Sunrise Lv n!" on a level up.
- Rally Cry: `TeamService.rally(team, untilT)` sets `rallyUntil[team]` and the ReplicatedStorage attribute `RallyUntil_<Team>`, refreshes the team's boosts and again when it ends; HitService passes `teamBoost` for touches inside it and the client reads the attribute (`State.rallyOn`). HUD tag and gold auras for the team.
- Counter Edge: a first-touch receive of the other team's ball by a Counter character returns `meta.counterGain`: a heavy ball `GainPerKmh` x the incoming km/h (`MinGain`..`MaxGain`, so one hard spike fills it) with no drain and no guard break, anything else `LightGain`. The server adds it to `entity.counter` (0..100, `TeamService.setCounter`, attribute `Counter` on the character and the player, reset each set; it refreshes the boosts). `effectiveStats` adds `PerFull` (+40 Attack, +70 Defense) times the meter / 100 (`extra.counter`). Her spike releases it: `kmh x (1 + ReleaseBoost x meter / 100)` and `meta.counterRelease`, and the server empties it. History: first a one-spike release (+30%), then (owner: "she scales based on her recs") a slow, set-long stat meter that left a maxed Ines at 111 km/h empty; then (owner: "major buff", fill easy and drain on the spike) this. VFX: blades out and back on a dig (`counterBlades`, sound `Blades`), a volley along the released spike.

**Gold upgrades.** A roster entry's stats are its ceilings. `Characters.baseStat` is where a recruit starts (`Config.Upgrades.StartFraction` of the way from 50), `statLevel(c, levels, stat)` reads a saved value (or "max" for bots), `pointCost`/`upgradeCost` price a point (`BaseCost + (value - 50) * CostPerPoint`, times the tier's `TierMul`), and ProfileService's `upgrade` buys as many of the asked points as the Gold covers (down refunds exactly). `VerticalM` is a curve (`Exp` 1.5 on 0.3 to 2.24 m): the lowest fresh starter hits 2.60 m, a maxed YeJun 4.34 m, the best maxed middle 4.37 m.

**Saving** is handled by ProfileService. It uses DataStore `SpikeRushProfiles_v1` with key `u_<UserId>`, storing profile v4: `{ v = 4, vp, gold, levels[charId][stat], owned[kind][key] (kind "Char" plus the cosmetic kinds), equip[kind], char, fav[charId], autoSell[rarity], settings, receipts }` (`fav` is the Players screen's favourites; `settings` the cleaned settings, see the fourteenth session; missing fields default). Older profiles keep their VP and cosmetics; their v1/v2 characters don't carry over (everyone gets the starters). A profile is only saved if it loaded successfully, so a failed load never overwrites real data. Spins apply at once; a duplicate, or a new pull of a rarity set to auto-sell, turns into `SellValue` VP. Auto-roll is a server loop per player (`profile.autoRolling`) that pushes each pull and stops on `AutoRollTarget` rarity, no VP, `AutoRollMax` or a "stop". VP packs (`Config.Shop.Packs`) and Gold packs (`Config.Shop.GoldPacks`) are Developer Products granted in `MarketplaceService.ProcessReceipt` (`packFor`, `applyPack`): each PurchaseId is remembered (last 50) and the receipt is only reported granted after the profile saves; a failed save takes the VP or Gold back and lets Roblox retry (in Studio without API access it grants anyway). Developers (`Config.Developers`) are flagged at load (`profile.dev`): they own everything virtually (not saved) and spin for free.

The active character is written as attributes on the Player and the character: `Tier, Height, Attack, Defense, Speed, Jump, Ability ("" for none), CharId, CharName, CharRole`. Equipped cosmetics are attributes too (`SpikeStyle`, `SpikeColor`, `SpikeTrail`, `ScoreEffect`); bots get random ones (more often at higher tiers). AnimationController swaps the airborne `Cock` pose and `Swing` clip by style (`Cock_<Style>`, `Swing_<Style>`), BallRenderer colours and styles the attack trail, and VFXController tints the spike impact and plays the score effect when an attack or stuff block lands in on the other side.

The active build is written as attributes (Tier, Height, Attack, Defense, Speed, Jump, Ability) onto the Player and the character. The client derives its prediction stats from those; the server uses `entity.charStats`, snapshotted when the match assigns teams. Picks and upgrades for your active character are rejected while your match runs, which keeps both sides identical.

**Menus.** `SceneController` builds two sets far from the court on each client (a club room at (1600, 0, -400), a gym at (1600, 0, 400)), poses static clones of your avatar with `AnimationController.rig`/`poseModel`/`poseJoints`/`blendJoints`/`clipJoints`, drives named camera shots (`home`, `recruit`, `ceiling`, `lineup`, `practice`), the recruit balls (`flyBalls`, `lineUp`, and `popBall`, which bursts a ball with Fx's hit star, ring and sparks) and the Locker's practice spike (`setPractice`: your avatar spikes on a loop with the previewed style, the ball wears the colour and trail, `VFXController.previewEffect` plays the score effect). While a scene is shown CameraController stands down. `MenuController` draws every screen on a 900-unit canvas (UIScale), with `Gui` as its UI kit (the broadcast kit: hairline cards, the Oswald display face, slanted plates, Toolbox icons from `Assets.Images`). It shows whenever you're not on a match roster. The menus ignore the GUI inset, so anything at the top left has to clear Roblox's own buttons: Home's profile block starts `GetGuiInset().Y / scale` down (`placeHome`, with the left column following), and a sub-screen header that reaches into the top bar slides right of `GuiService.TopbarInset.Min.X` (`placeHeaders`); both rerun on viewport and `TopbarInset` changes. `modal()` builds every popup as a dim backdrop button with the panel as a separate button over it, so only Close or a click on the backdrop closes it (`broadcast` draws the panel in Home's kit). The club room's lockers, bench and ball carts and every menu ball come from `ToolboxAssets.Models` (`toolboxModel`, `standProp`, `stockWithBalls`, `furnishHome`/`furnishGym`, rebuilt when the Models folder changes), with built stand-ins for empty slots. A spin's `reveal` starts the recruit sequence (`playSequence`); during auto-roll only the last pull (the one that hit Legendary) plays in full.

**Lobbies and matches.** `src/shared/Lobbies.lua` holds the rules (sims cover them); `LobbyService` keeps the lobbies per server, answers the `Lobby` remote and sends each player their own `Lobbies` view (friends-only lobbies are filtered with a cached `IsFriendsWith`). `MatchService.intermission` waits for `LobbyService.nextForCourt()`, then `TeamService.assign(mode, LobbyService.plan(lobby))` seats the lobby's players (bots fill the rest) and `LobbyService.finished` reopens the lobby (a quick lobby splits up). Starting while the court is busy reserves a server (`TeleportService:ReserveServer`) and teleports the lobby there with `Lobbies.export` as teleport data (profiles are saved first); the reserved server (`PrivateServerId ~= ""` and `PrivateServerOwnerId == 0`) rebuilds it with `Lobbies.import`, waits up to `ArriveTimeout` for its players, and plays locally from then on. In Studio (no teleports) lobbies queue for the court. **AFK and leaving**: clients fire `Activity` on input (at most once a second); TeamService adds idle time only in live phases (`Lobbies.idle`, `Config.Afk`), and `TeamService.bench` swaps a player for `standIn`: a bot with the same character, build, role, slot and stat line in the player's own avatar (`GetAppliedDescription`), announced as `StandIn`. `requestJoin` (the Rejoin button) and `hotJoin` put the player back at the next rally. MatchService calls a match off (`MatchAbort`) when no human is on court and no benched player is still in the server.

**Setter AI.** `planSet` feeds the wing spiker; off a pass that comes down within `Bots.QuickPassDepth` of the net, with the middle within `QuickReachDepth`, it calls a quick with `QuickChance` (by the setter's tier; half for a human middle). `planQuick` pre-plans a bot middle's run and takeoff from the quick's known path (`HitLogic.setArc`), so it's in the air as the set is made. `planBackup` sends the bot middle up `BackupDelay` behind the wing spiker's contact (a rising contact if the ball has dropped below its best reach, `handLead`); `notBefore` stops it taking a ball the wing spiker can still hit, and it only swings at a human's ball after a whiff (or when they don't go).

**Serving.** `HitLogic.tossLaunch(root, side, height, forward)` is the toss (and draws the client's dotted guide, `BallRenderer.guide`): a forward toss comes down `TossForwardMax` in front. While you serve, MovementController holds you behind the end line until the ball is served (`serveLine`); jumping over it is fine.

**Toolbox assets** (`ToolboxService`, `Assets.lua`): every visual and audio slot resolves in this order: an instance in `ReplicatedStorage.ToolboxAssets.<Category>.<Slot>`, then an id in `Assets`, then the procedural or built-in fallback. `ToolboxService` fills empty `Models`/`VFX` slots from `Assets.Toolbox` at server start (`AssetService:LoadAssetAsync`, which reads any free model once "Allow Loading Third Party Assets" is on, else InsertService: owner's or Roblox's assets only), and `ToolboxService.install()` bakes them from the command bar with `game:GetObjects`. A slot's value can name one piece of a pack (`"<id>/<path>"`; each pack loads once, and `findPath` tries every child of a repeated name), and `Assets.ToolboxAttributes` stamps `Yaw` on models that face another way as published and `Scale` / `Lift` on effects made at another scale; an `AssetId` attribute records where each came from. The place has `Models.Volleyball`, `Locker`, `Bench` and `BallCart` and `VFX.ScoreFire`, `ScoreMeteor` and `ScoreThunderbolt` baked in. `Assets.sanitize` deletes every script in an inserted asset and makes its parts inert; clients sanitize their clones too. BallRenderer rebuilds the ball's look when `Models.Volleyball` arrives late.

**Remotes** (`Net.lua`):

| Remote | Payload |
|---|---|
| BallState | ball snapshot to clients |
| HitRequest | client touch |
| HitReject | rejection, triggers rollback |
| ActionFX | Slide, Block, Whiff, Jump, Charge, ChargeEnd, Stance, Approach (a double approach's run-up) cosmetics; "Ability" from a client asks to start its active ability |
| MatchState | match snapshot |
| Announce | Point (with `playTo`, `deuce`), Serve, SetStart, SetEnd, MatchStart (plays the intro), MatchEnd (with `forfeit`; each row has the stats, `role`, `pose`, and `mvpBonus` on the MVP's row; plays the showcase), MatchAbort, Break, Timeout, TimeoutCalled, Forfeit, StandIn (`name`, `char`, `reason` "afk"/"left", `userId`) |
| ClientReady | client finished loading |
| Lobby | client: `("create", settings)`, `"tutorial"`, `("quick", mode)`, `("join", id, password)`, `"leave"`, `"start"`, `"team"`, `("kick", userId)`, `("settings", settings)`, `"rejoin"`, `"list"` |
| Lobbies | server: `{ list, mine, court, teleport }` per player, or `{ notice }` |
| Activity | client: input happened (AFK watch) |
| Continue | client, after a set: keep playing (true) or end the match (false) |
| Leaderboard | client asks (`"get"`); server answers `{ boards = { [key] = { { rank, userId, name, value } } }, global, updated, refresh }` |
| SetCharacter | `(tier, ability)` |
| Timeout | call a timeout; `"ready"` during one: done, end it early once everyone is |
| Profile | client sends `"get"`, `("select", charId)`, `("upgrade", charId, stat, ±1\|5\|10)`, `("spin", banner, 1\|10)`, `("autoroll", banner)`, `"stop"`, `("autosell", rarity, on)`, `("equip", kind, key)`, `("favorite", charId, on)`, `("settings", table)` (no reply), `("buy", pack, "VP"\|"Gold")` (Studio only, packs without an id); server replies with a snapshot (with `reveal` after a spin) |
| Forfeit | concede the match for your team |
| Rotation | during a timeout: `("up"\|"down"\|"serve", entityId)` on your own team |

**Jump physics.** A hang force cancels 45% of gravity while the vertical speed is under 9 studs/s. The same rule runs in MovementController for players and in BotService for bots. That hang adds about 0.74 studs to the apex (`Characters.hangGain`), and `Characters.jumpHeight` subtracts it, so the true apex equals the build's hitting point; this was verified numerically. The Azure hover cancels 85% of gravity, but only while charging and falling, so charging never raises the hitting point.

## Checks

Code must stay in a Lua 5.1/5.3 compatible subset of Luau: no `+=`, `continue`, type annotations or backtick strings. The offline tools need python3, `texlua` and `texluac` (LuaTeX's Lua 5.3). Run all four after every change and keep them at zero:

```
python3 tools/check_lua.py      # syntax (texluac) and undefined globals
python3 tools/check_config.py   # every Config reference, including local aliases, exists
python3 tools/check_api.py      # every Module.fn / reg.Service.fn / mods.Controller.fn is defined
texlua tools/sim_test.lua       # 94 scenarios run against the real shared modules
```

On Debian or Ubuntu, `apt-get install texlive-binaries` provides `texlua` and `texluac`.

Nested config aliases such as `local AZURE = Config.Abilities.Azure` are not covered by `check_config.py`, so check those by hand. When you change a mechanic, add or update a scenario in `sim_test.lua` that proves the numbers.

## Status

All the code for the 2.5D game is written and every check passes, including all 94 simulations. The project builds and serves with Rojo 7.7.0 (verified with `rojo build` and a live `rojo serve`). The sound effects are generated in `assets/sfx` but not yet uploaded. The owner has connected Rojo in Studio; no runtime errors have been reported back yet.

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

### Sixth session: V Points, cosmetics, jump retune, match features

- **Guard break**: the breaking receive (and any touch on a broken guard) now blasts the ball up and out behind the receiver, landing 1.5 to 5 m past their end line (`blastOut` in HitLogic).
- **Azure**: `GravityCancel` 0.85 while charging on the way down (a slow float); a `ChargeLoop` stance clip pulses the charging arm, and VFXController puts an orb, sparks, a light and a spinning ring on the right hand (`handFx`), growing with energy (other clients grow it over `ChargeTime`).
- **Jump retune**: `JumpScale` 1.4 (jumps look higher), `VerticalM` 0.25 to 1.55 m (D- about 3.2 m, maxed S+ 3.95 m at 185 cm), sets and quick-set apexes lifted to match, camera framed higher. The attack readout (and the Thunder check) is capped at the hitting point, so a ball met above the hand can't read 4 m for a short jumper.
- **Block on W**: the default control script rewrites `Humanoid.Jump` every render step, so jumps set from input handlers (the block release, `MovementController.jump`) were wiped before physics saw them. They are now queued and applied in `moveStep`, after the control script. Pressing W works anywhere; it's a block only in a rally near the net.
- **V Points**: see Characters, Spins and Saving above. UI: lobby tabs Play (tier, ability, mode, allocation with -10..+10 and Auto), Shop (six banners, x1/x10, result cards with a pop-in reveal, keep/discard, VP packs) and Locker (equip).
- **Cosmetics**: spike styles (Classic, Bow, Scissor, Hammer, Whirl), spike colours (tint trails, glow, sparks and impacts; Prism is a rainbow), trails (Comet, Sparkle, Flame, Lightning segments, Stardust) and score effects (Shockwave, Fire Explosion, Meteor Strike, Thunderbolt).
- **Deuce**: `Court.playTo(a, b, base)` is the one rule: once both teams reach base - 1 the target is the lower score + 2, capped at `PointCap` (golden point). MatchService uses it for set over and set point; the top bar shows it in a yellow diamond (red with "DEUCE" during deuce) and a callout fires on each deuce tie.
- **Forfeit**: a Forfeit button next to Timeout (tap twice). MatchService's waits end early, the match ends with the other team winning, and the forfeiting team gets no VP.
- **Timeout rotation**: timeouts last 10 s; a panel lets each team reorder its rotation and pick the next server (`Court.reorder`, serving team index 1, receiving team index 2 since a side-out rotates first).
- **Bots**: skill pairs by tier in `Config.Bots` (buffed in the eighth session after the owner found them too weak; a bot's skill is `skillP`, the lobby's bot level or its character's tier if higher; Turnabout bots only arm for a ball they can jump-set) (reaction delay, jump timing, contact noise, perfect-receive chance, sloppy stance, whiff and miss chances, spike mishits, serve errors, block, read-out and slide chances). A covering bot plays the ball at once after its human whiffs (`HitService.missAge`, `Bots.CoverAfterMiss`). Idle bots re-read the formation every 0.2 s and fill the spot a human left (`Court.formationFill`, `Bots.SwapMargin`).
- **UI**: the control rail is compact text pills (no emoji).
- **Loading screen** in `src/first` (ReplicatedFirst), waiting for the player attribute `SpikeRushLoaded` (set at the end of Main.client) with a 25 s cap. **Icon and thumbnail**: `tools/generate_icon.py` into `assets/icon`.

### Seventh session: characters, role abilities, spin tools, avatar thumbnail

- **Thumbnail**: the owner's avatar (a blocky rig: white jacket with ink splatter over a black shirt, dark pants, light shoes, messy black hair, a small purple accessory) is rendered mid-spike by `tools/avatar_render.py` (a numpy z-buffer rasterizer with cel shading and ink lines) and composited by `generate_icon.py`. For a closer likeness, ask the owner for a bigger front and back screenshot and adjust the textures in `avatar_render.textures()`.
- **Characters replace builds**: see Characters, Spins, Abilities and Saving above. Stat allocation (the ±1/5/10 buttons), rolled caps, tier rolls and height rolls are gone; the Play tab lists your characters. `Config.TierCaps` is gone; `Stats.Ref` is 210 (the best WS Attack) and `VerticalM` 0.25 to 1.77 m.
- **Match**: players take their character's role when it's free (`freeRole`); bots are roster characters (`rosterFor`: that role, the nearest tier within two steps, not already on court), else the role template.
- **Shop**: banner list with owned counts, What's inside (every pull and chance), results cards (NEW / +VP / sold), auto-roll with Stop, auto-sell toggles, VP packs.
- **HUD**: the ability panel shows every ability's state (Adrenaline active, Iron Wall cooldown, Chain Reaction, Thunder reach, Azure energy); the control rail and the touch controls gain an Ability button for active abilities; name tags show the character's name.
- **Effects**: Iron Wall barrier, stuff burst; charged sets glow red with sparkles and a red arc; the exploding spike burns red with a burst and "Chain Reaction!"; Adrenaline gives a red aura; boom jumps need Jump 170 (`Config.Player.BoomJumpMin`), in VFX and audio.

### Eighth session: menus, recruiting, Gold, lobbies, AI stand-ins

- Sound pass from the owner's two screen recordings of The Spike (used as a reference only, never cut into the game; the video tracks were black, the audio intact): measured each event family's spectrum, length and envelope and re-synthesized originals in `tools/generate_sfx.py` to match. The crowd was thin and hissy next to the reference (a warm bed, most energy around 1 kHz with a body at 63-125 Hz), so `crowd_bed` became formant voices with syllable-rate chatter over a 70-170 Hz body (CrowdCheer: a 0.6 s swell, a second of roar, a 1.8 s settle); the jump `Boom` is a small crack, a deep sub whump that bounces once and a short rumble; `Bump` is deeper and duller; `Block` a wide slap with air and weight; `UIClick` a broadband tap peaking near 3.9 kHz. New menu slots `UIOpen` (panel swish), `UISelect` (tab blip) and `UIConfirm` (sparkle over a pop) are in `Assets.Sounds` with stand-ins; the menus still need to play them.

- Then: the play camera is fully zoomed out (a fixed wide shot fitted to the screen, `CameraController.wide`; the old tracking view is the "Follow camera" setting, `State.settings.followCam`); an easy **underhand serve** (F / D-pad up; HitLogic action `Underhand`: straight from the held ball, `solveArc` to 35 to 70% of the court's depth over `UnderhandApexOverNet`, a sim proves it always clears the net and lands in); **bots serve** underhand below `Bots.JumpServeTier` (A-) and full-toss jump serves from there (a missed jump serve is still played overhand); a **tutorial** (`src/shared/Tutorial.lua`: 7 steps, `stepsFor(hitType)`; `ProfileService.tutorialStep` ticks steps from HitService touches, block jumps from ActionFX and MatchService's won rallies, and pays `Config.Tutorial` once: 50 VP, 1,000 Gold, 5 `freeSpins` that x1 recruits use before VP; `LobbyService.tutorial` makes a hidden 1v1 lobby against D- bots; UIController's coach panel shows the current step in tutorial matches). Profiles gain `freeSpins` and `tutorial = { steps, done }` (still v4; missing fields default).
- Then: a match is **one set** (`Match.Sets`); after a set MatchService runs a `Continue` phase (`askContinue`: humans vote over the `Continue` remote, `ContinueTime`), up to `MaxSets`; the winner is `Rewards.winner` (sets, then points, then the last set). `src/shared/Rewards.lua` holds the reward math (`match`, `extraSets`, `streakBonus`, `nextStreak`, `winner`), with sims. `ProfileService.recordResult(plr, won, stats)` keeps `winStreak`, `bestStreak` and `record = { matches, wins, kills, aces, blocks }` (Home's counters; tutorial matches don't count). Timeouts: `Timeout` remote `"ready"` marks you ready (`MatchService.timeoutReady`); when every human on court is ready the phase end moves to now (`waitUntil()` with no argument follows the live phase end). `Profile "select"` is allowed during a timeout and calls `TeamService.swapCharacter` (same slot, role and stat line; new build, ability and attributes; the team pool is re-read). The timeout panel's "Character and look" opens `MenuController.openSwap` (the menus' gui over the match, only that window).
- Then: matches cap at three sets (`Match.MaxSets` 3), and **leaderboards**: `src/shared/Leaderboards.lua` (the five boards from `Config.Leaderboards`, `valuesOf(profile)`, `rank`, `merge`, with sims) and `LeaderboardService` (an OrderedDataStore per board, `SpikeRushBoard_v1_<key>`, keys `u_<UserId>`; `track(plr, profile)` queues a player's values after every match and once on join, written every `FlushInterval` and on leave; the top `Top` read every `RefreshInterval`, names via `UserService:GetUserInfosByUserIdsAsync`, merged with this server's live profiles (`ProfileService.peek`); answers the `Leaderboard` remote). The Ranks screen in MenuController shows them.
- Later in the session the owner removed Ryota (the second Thunder Spiker: YeJun is the only one) and raised YeJun's Attack to 210 (the top of the curve, `Stats.Ref`). Saves that owned Ryota simply drop him; a player who had him selected falls back to a starter.

- **Menus and scenes**: see Menus above. The old lobby panel in UIController is gone (UIController keeps the HUD, results and the settings panel, which the menus open with `toggleSettings(belowY)`); the HUD's top bar and announcements stay out of the menus when the match on the court isn't yours.
- **Recruit sequence**: sparkles (gold when a Legendary is inside, red for a Mythic: `Config.Rarity.PullGlow` recolours a pull's glow, balls, tray, card edge and cinematic) -> balls under the gym ceiling -> the line-up and Click to Continue -> each ball pops; a Legendary or Mythic plays the cinematic (a ViewportFrame with `ImageColor3` black over a yellow gradient, your avatar's clone animated Gather -> Rise -> your style's Cock -> the Swing clip, a black ball, a light beam, a white flash), then the reveal card; Skip jumps to the next one; then the results and Confirm.
- **Gold** and **friend bots** (FriendService: bots borrow an unused friend's name and avatar; the character's name shows under it), **tier-scaled drain** (`HitLogic.tierDrain`: S+ full, D- a quarter), a red glow and sparkles on charged sets, cancel queue (Leave / Cancel queue in the Match panel).
- **Lobbies, AFK stand-ins, middle quicks and backups, the forward toss, the serve line and toss guide, the MVP bonus, the height curve, the wind-up on every jump** (AnimationController plays Rise then the style's Cock for any jump but a block).
- Then: **five more S characters** with abilities, from the owner's brief (inspirations named by the owner; the names, looks and numbers here are our own): Ilya (setter, **Vector Set**: a pulsing set, spike power by angle, the boost shown), Haeri (setter, **Turnabout**: "an ability pop and should be automatic": Q arms it and her next second touch spins over as a spike), Daon (wing spiker, **Rising Sun**: a level every 3rd point lost, a low A at 0 and better than YeJun at 12, with a Sunrise meter), Joon (middle, **Rally Cry**: the team +12% on every stat for 10 s) and Ines (wing spiker, **Counter Edge**: received spikes fill a meter instead of draining stamina, blades out and back in; the owner then asked for low base Attack and Defense with Defense around 200, "she scales based on her recs", so the meter now raises her Attack and Defense for the set instead of powering one spike). With them, **setters jump-set** and a set taken higher goes higher. See Abilities above.

### Ninth session: Toolbox props, the profile under Roblox's buttons, Gold packs, the loading cinematic

The owner asked for these after pulling the Ines/Ilya changes; everything was playtested in Studio through the Studio MCP.

- **Profile card**: Roblox's top-left buttons covered it. It now sits `GetGuiInset` down (`placeHome`) and is bigger (100-unit headshot, 42-unit name, larger currencies); sub-screen headers slide right of the buttons where they reach into the top bar (`placeHeaders`).
- **Toolbox props**: the blocky built lockers, bench and ball basket, and the balls that weren't round, are Toolbox models now (see Toolbox assets above and TOOLBOX.md), baked into `ToolboxAssets.Models` with their ids in `Assets.Toolbox`. Every menu ball (carts, the recruit sequence, the Locker's practice spike) is the Toolbox volleyball, which the match ball already used.
- **Shop**: Gold packs next to the VP packs (`Config.Shop.GoldPacks`), granted like VP packs; a big Recruit plate opens Recruit Player (`goRecruit`). The Shop's content is in the broadcast kit.
- **Popups**: a click inside a popup used to reach the backdrop behind it and close it. `modal()` now makes the panel a button of its own over the backdrop.
- **Match window**: restyled in Home's broadcast kit (plate tabs, hairline mode cards, lobby cards edged in team colours, signal-yellow plates for each page's action).
- **Loading screen**: holds at least 3 s, then plays the silhouette spike (see the checklist) and waits for a click. (Redone in the tenth session: see below.)

### Tenth session: the loading freeze, the logo, the menus in The Spike's style, Toolbox VFX, new courts

The owner asked for a full UI overhaul "that doesn't look AI-made", based heavily on The Spike's layout and feel with some creative liberties, Toolbox assets used heavily, and nothing copied from The Spike's art, characters, logo or branding.

- **Loading screen** (`src/first/LoadingScreen.client.lua`), from the owner's reference of The Spike's frozen recruit frame: one amber frame, a feathered pillar of light with a black ball at its top, the logo top left. Your avatar's silhouette (SceneController's `cloneAvatar(true)` in a ViewportFrame tinted black) rises into a dedicated freeze pose (`freezePose`: the chest turned open to the side camera, the left arm up the pillar, the hitting hand cocked behind the head; the game's own `Cock` turns the other way and hides the pointing arm from this side). The camera is fitted so the pointing hand lands on `HAND_AT` and hand-to-feet spans `HAND_TO_FEET` of the screen, so blocky and tall avatars frame alike; the pillar and ball are GUI placed over the hand. A click plays `followPose` (the arms whip, the hips stay put), an impact flash, speed lines and the blast.
- **Logo**: SPIKE RUSH in Montserrat Heavy italic (the 900 weight: `Enum.FontWeight` has no `Black`), white over an ink outline, an orange rim and an ink extrude (stacked TextLabels, stroke widths scaled to the logo's height), RUSH in an orange-to-gold gradient with three speed marks, tilted up 4 degrees. It echoes the energy of The Spike Cross's logo (the owner's reference) without copying its lettering.
- **Players** (MenuController `buildPlayers` / `buildPlayer`), laid out like The Spike's player screens. The roster: a panel on the right with Sort (tier or name), a favourites star, role chips (All, WS, MB, SE) and a grid of cards (tier-coloured card stock with halftone and a gloss streak, a `Gui.tierBadge` ring, role, `+N` points bought or MAX, the name, Starter or Playing, a star for favourites, a lock over players you haven't recruited); "Playing now" bottom left. The card art is your own avatar (`SceneController.cloneAvatar(false)`) posed by role (`PORTRAIT`: the bow-draw for WS, Block for MB, SetCatch for SE), lit from the side in each card's ViewportFrame, built once your avatar has loaded. A card opens the player's page: the badge (MAX when all four stats are at their ceilings), Play and Favorite, and the tabs Growth (stat rows with Toolbox stat icons, bars, `MAX / ceiling`, square + and - by a step of 1, 5 or 10, and the build's numbers) and Information (the ability's name, Passive or "Active: Q" with its cooldown, and its blurb; the role's `Config.Roles[r].Blurb`; height, rank, recruit odds and status). Favourites save in the profile (`fav`, the `favorite` request). The `roster` camera shot puts your avatar in the room's left third.
- **Main screens' top bar** (`mainChrome`): the currencies top left under Roblox's buttons (`currencyStrip`, placed by `placeHeaders`), the nav (Home, Shop, Players, Locker, Ranks) with the current screen lit, Help and Settings top right. New kit pieces in Gui: `tierBadge`, `squareButton` / `enable`, `tabs`, `chips`; `cardButton` stays dim while inactive.
- **Recruit** (The Spike's recruit screen): `header()` is now a back arrow, a heavy title, the currencies and Settings; the Player / Cosmetic toggle (`segmented`, now a dark trough with a signal-yellow segment) over banner cards (`BANNER_ART`: flat card stock, halftone, a gloss streak and a Toolbox icon; the chosen one edged in gold, the rest dimmed); the banner's big title, blurb, odds, Probability Table and auto-roll, and auto-sell toggles; Recruit x1 (a chalk panel) and x10 (a signal-yellow plate), each with its cost in a dark pill, and a red tag for free recruits.
- **Locker**: the main top bar; the kinds as `Gui.tabs`; square equip cards after the owner's reference (a dark glossy tile, a thick rarity border, the name in the middle, EQUIP / EQUIPPED / LOCKED under it; the previewed card edged white); the picked item and the Equip plate along the bottom. The `practice` shot moved 12 studs so the spike plays in the left third, clear of the panel.
- **Shop** and **Ranks** use the main top bar; Ranks' boards are hairline cards with a slanted signal bar on the one shown, the board a dark panel of rows (medal-coloured ranks, square headshots, your row in signal yellow). **Help** is a table of actions with keycaps; the **Probability Table** and the timeout **Swap** window use the broadcast modal (tier badges on the characters, rarity-edged tiles on the looks); the **toast** is a dark hairline card with a signal tab.
- **VFX, hand-drawn** (`src/client/Controllers/Fx.lua`, VFXController, BallRenderer, SceneController), for "rework the vfx to not look ai". Every effect is now a particle kit built from anime flipbook textures out of two free Creator Store packs (ids in `Assets.Fx`; "Yona VFX Pack" 18170940328 and "BIG VFX PACK" 17290956157): comic hit stars, a ragged hit-ring flipbook, spark streaks (`VelocityParallel`), cel-shaded smoke, anime flames, lightning sprites and arcs, a spreading crack, a crater and rocks. `Fx.play(name, where, { color, scale, count, n, angle })` fires a kit, pooled per name (the holder part is named after the kit); `Fx.attach(name, parent)` holds one (trails, auras) and returns `set(on, color, rate)`. A template in `ToolboxAssets.VFX.<Name>` replaces the kit of that name (`Scale` and `Lift` attributes; a tint hue-shifts it). Kit layers spread in the screen plane (`SpreadAngle (s, 0)` around straight up) and floor layers lie flat (`VelocityPerpendicular` on a tiny upward speed). VFXController's old shapes (`burst`, `floorRing`, `shards`, `bolt`, `ringFx`, `starburst`, `emit`) keep their call signatures and draw with kits, so the neon spheres, UIStroke circles, frame rays and the stock sparkle, smoke and fire textures are gone; `bolt` turns an upright bolt sprite along the direction (`screenAngle`).
  - Score effects: `ScoreFire` (BIG's cel fireball), `ScoreMeteor` (Yona's rock blast) and `ScoreThunderbolt` (BIG's shock disc and rising bolt) are Toolbox pieces taken out of their packs by `"<id>/<path>"`; `ScoreShockwave` is a kit. The meteor's fall (a basalt rock in a `MeteorTrail` of flames) and the thunderbolt's bolt out of the sky (seven sprite segments) stay in VFXController (`playScore`, which the Locker's `previewEffect` uses too).
  - Trails: slots `TrailComet`, `TrailSparkle`, `TrailFlame`, `TrailLightning` and `TrailStardust`, filled by kits (the packs' trails are torch effects and looked sparse on a fast ball). BallRenderer rides the attacker's kit on the trail anchor (`kitFor`, on while the ribbon is) instead of the neon lightning segments and the per-key sparkle and aura tweaks, and the Locker's practice ball does the same. The ball's sparkles are glints and its aura is anime flames.
  - Screen: speed lines and streaks are tapered strokes; the impact frame's burst is the packs' speed-line ring, glow, hit star and slash; popups use the display face with the shield icon as the badge; the perfect-receive shield is the shield icon with a glint; the Azure orb is glow, core and ring sprites; status auras burn the anime flame (`StatusAura`).
- **Match HUD** (UIController, in the Gui kit; the old Gotham and Bangers faces map to the kit's through `faceFor`): a slanted scoreboard (each team's wing plate with its name over the stamina bar and a signal tick per timeout; a signal-yellow VS plate with the points played to on a dark tag over it, which turns red in a deuce; a white score box under each side; the serve ball beside the serving side's box); the attack readout with small decimals (`split`); the point banner on a dark bar with a gold edge and the reason on a tag; round Timeout, Forfeit and Settings buttons top right with Toolbox icons (`IconTimeout`, `IconForfeit`) and captions (`ui.timeoutCap`, `ui.forfeitCap`); the settings panel with switches; the control pills bottom left with keycaps; the results on a hairline card with the winner on a slanted plate in their colour and a row per player. The readout hides with the scoreboard whenever the match on the court isn't yours.

These are the spots most likely to need attention on the first playtest:

| Area | What to check |
|---|---|
| Rojo | The plugin must be 7.7.x (`rojo plugin install`, then restart Studio); "Can't parse JSON" or a protocol error on Connect means an older plugin |
| Scale | The whole hall is bigger (4.6 studs/m): check the camera frames the play, bots cover the longer court, and serves reach from behind the end line |
| Joints | Poses must show on both AnimationConstraint and Motor6D rigs; Output should have no "[SpikeRush] animation" warnings |
| Jumps | Humanoid.JumpHeight is about 15 studs for a maxed S+; check the apex reaches the hitting point (the readout should show the lobby's hitting point on a perfect spike) and the air time feels right (tune `JumpScale`, `Player.Gravity`, `HangGravityCancel`) |
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
| Block jump | Hold W near the net in a rally: crouch, release, the jump must happen (it's queued to MovementController's render step) |
| Spins | Spin x1 and x10 on every banner; keep and discard; the Locker equips; other players see your style, colour, trail and score effect |
| Purchases | With a product id set (VP and Gold packs), test in a live server or Studio's test purchases; the receipt must grant once and survive a rejoin |
| Loading screen | One amber frame with the pillar, the ball and the logo; "Loading" for at least 1.5 s, then your avatar's silhouette rises into the bow-draw under the ball and freezes on "Click to continue" (the ball alone if the avatar hasn't loaded); a click plays the swing, the blast and the fade. Never stuck longer than 25 s |
| Timeout | The rotation panel shows for both teams during a timeout, and the chosen server serves next |
| Forfeit | Ends the match at once in any phase, and the results screen says who forfeited |
| Characters | Selecting a character updates the lobby, the HUD and the name tag; bots show roster names; roles follow characters |
| Abilities | Iron Wall on Q stuffs a full Azure; a charged set's spike explodes and drains; Adrenaline turns on below 40% stamina (red aura, higher jump) |
| New S abilities | Vector: the set pulses and the spike pops "+x.x%"; Turnabout: Q then a jump set goes over as a spike (the opponents' bots don't block it); Rising Sun: the meter and the aura climb every 3 points lost and the jump gets visibly higher; Rally Cry: every teammate's HUD shows the gold tag, runs and jumps are faster and higher for 10 s; Counter Edge: blades out and back on a received spike, no guard drop, the HUD's +ATK/+DEF climbs as she receives and resets each set |
| Jump sets | Bot setters jump for open and back sets off a pass near the net; the attacker still meets the higher set (watch spike timing on very high sets) |
| Developers | In Studio every character and unlockable is owned and spins are free |
| Camera | Long lens (FOV 34, 64 studs back); high sets must stay in frame at 16:9 and on phones |
| Performance | Effect kits are pooled per kit (`Fx`), sonic rings reuse their BillboardGuis, and a trail is one held kit per unlock on the ball; popups are still created per receive grade |
| Menus | Home, Recruit, Players, Locker, Shop and the Match panel at 16:9, ultrawide and phone sizes (the canvas scales from 900 units tall, at least 1180 wide); the avatar appears in the club room and the recruit hall once it has loaded; the Settings button opens the settings panel under it; Home's profile and every back button clear Roblox's top-left buttons; clicks inside a popup never close it |
| Recruit | x1 and x10 on every banner: the sequence, gold sparkles for an S (red, a throbbing red ball, a red cinematic and a red-edged card for a Mythic), Skip to the S, the cinematic (silhouette in your style), the card (your avatar posed) and Confirm; auto-roll shows the running line and plays the final Legendary |
| Locker | Clicking a style, colour, trail or effect restyles the practice spike at once; Equip only for owned items |
| Lobbies | Quick Match (countdown, Cancel queue), create each privacy (a friend sees a Friends lobby, a stranger doesn't; a wrong password is refused), switch sides, remove a player, change settings, Start; a second lobby while the court is busy teleports (live servers only) and the reserved server starts it |
| AFK | Stop pressing anything for 12 s during a rally: your AI (your avatar, "(AI)") takes over and Home shows Rejoin; Rejoin puts you back at the next serve with the same stat line. Leaving mid-match leaves your AI in |
| Quicks | Watch bot setters call quicks off good passes (the middle is up as the set goes) and middles back up the wing spiker |
| Serve | Holding toward the net at the line doesn't walk you in; the dotted guide matches the toss; a full forward toss lands about 2.4 m ahead |
| Courts | Each court in Create Lobby plays on that court; Rotation and Quick Match move to the next court every match; the crowd, LED tickers and courtside screens follow the court; the screens never sit under the HUD's scoreboard |

### Eleventh session: courts

Five courts, picked per lobby. The play area (`Config.Court`) is the same on every one; a court changes the paint, the surroundings, the stands, the score screens and the light.

- **Config.Courts**: `List` (name, blurb, `Stands` overrides for `Court.Stands`, `Crowd` density), `Rotation`, `Default` and the `Rotate` pick. `Court.stands(id)` / `Court.standRows(id)` give a court's rows; ArenaBuilder builds them and CrowdController seats the crowd on the same rows.
- **Lobbies**: a `court` setting (a court id or `Rotate`, cleaned like the rest), carried through the summary and the teleport export. `Lobbies.courtFor(l, last)` returns the lobby's pick, or the court after `last` in the rotation (Rotate, and every Quick Match). Sims cover the pick, the rotation, the per-court stands and the teleport round trip.
- **MatchService.playMatch** dresses the arena first (`reg.ArenaBuilder.setCourt`), then places the players. `state().court` and the MatchStart announce carry it, and the "Game on!" callout names it.
- **ArenaBuilder**: the core (Floor, Net, NetBarrier, invisible `Bounds` walls, LobbySpawn) is built once. `setCourt(id)` swaps `Arena.Scene` (a Persistent-streaming Model, since the place streams), recolours the floor and the net pads, sets the lighting, and stamps `Court` on the Arena and the Scene. The lighting takes over the place template's Atmosphere, Bloom, Sun Rays and ColorCorrection at runtime (a second Atmosphere fought the court's); the Sky stays.
  - **Rush Arena**: the old navy hall.
  - **Nationals**: blue court, green free zone, crimson stands, gold trim, flags, trusses, a bright white rig.
  - **Sunset Beach**: sand, blue rope lines, aluminium bleachers, Toolbox palms, part-built umbrellas, a lifeguard tower, the sea with islands, afternoon sun.
  - **Colosseum**: a court chalked on sand, limestone tiers up to an arcade with red banners, columns and braziers, dusk.
  - **Night Rooftop** (original): a green court behind a parapet, bleachers under string lights, floodlights, a water tank, and a lit skyline below.
- **Score screens**: every court puts its two screens courtside, standing on the floor in front of the far stands (`screens()`). On the far wall they sat right under the HUD's scoreboard and rode up into it as the camera climbed. The client draws on every `Jumbotron` part with a `Face` attribute.
- **CrowdController** re-dresses on the Arena's `Court` attribute: it waits for the matching Scene, then rebuilds the crowd (the court's rows and density), the LED tickers (which now name the court) and the screens.
- **Create Lobby** has a Court stepper (Rotation, then each court) with the court's blurb. The lobby list and your lobby's info line show the court.
- **Toolbox**: `Assets.Toolbox.Models.PalmTree` = "Palm Tree" (`12392856366`), installed into `ToolboxAssets.Models` in Studio. **The place must be saved to keep it.** `BeachUmbrella` and `Column` are empty slots (parts are drawn instead). ArenaBuilder's `toolboxProp` scales any upright model to height.
- Verified in a Studio playtest: every court built and screenshotted from the match camera; a Colosseum and a Beach lobby started from the lobby remote; a Quick Match rotated Arena to Beach with the right boards, screens and crowd; no errors in Output. The picker's layout was screenshotted, but its buttons were not clicked in the test (the MCP mouse tool couldn't reach them).
- The beach sea stops short of the menu rooms (SceneController builds them at x = 1600); an island hides the rooms from the court.

### Twelfth session: the owner's sounds

The owner now supplies every sound and asked to remove all the free ones ("from now on use mine").

- **Filled** with the owner's uploads (a free sound library): Spike ("spike sfx"), Boom ("boomp jump"), FloorHit ("spike land"), FloorHitHeavy ("heavy land", a new slot: the landing after a hard spike, meaning Thunder or 130+ km/h), CrowdServe ("crowd hype") and RecruitFly ("RecruitBuild", a new slot: the balls flying under the gym ceiling; a skip cuts it).
- **Removed**: `Assets.Fallback` (the pitched Roblox built-in stand-ins) and the Roblox library UI clicks. An empty slot plays nothing.
- **AudioController**:
  - `BORROW`: SpikeHeavy plays the Spike sound deeper and louder. The new recruit slots (RecruitOpen, RecruitOpenGold, RecruitOpenMythic, RecruitPop, RecruitReveal, RecruitRevealGold, RecruitCharge, RecruitSpike) play the sounds the sequence used before, while empty.
  - The serve cheer stops (a 0.1 s fade) on the first touch after the toss.
- **Timing**: most uploads had 0.25 to 0.75 s of silence at the front ("the boom jump sounds delayed"). `Assets.SoundFiles` skips it per file. A brand-new Sound given a start offset takes about 0.3 s to begin, so every play clones a loaded copy from `SoundService.SpikeRushSoundBank`, which also preloads them all. Measured: each sound starts within about 0.03 s of its moment.
- **Loudness** ("the audio feels weak", "it doesn't match the power of the game"):
  - Hits at the ball had RollOffMinDistance 20 with the camera about 70 studs away, so they played at about -11 dB. Now it's 140.
  - Per-file gains even out the uploads (the boom x2.2).
  - The bus: group volume 1, compressor attack 15 ms and +6 dB makeup, EQ +5 low / +3 high, hall wet -24.
  - Nobody has listened to it yet; tune by ear with the owner.
- **Menus**: `onClick` plays the button's `Sound` attribute: UIConfirm on action plates, UISelect on tabs, toggles and chips (UIClick otherwise), one sound per press. A modal opening plays UIOpen.

### Thirteenth session: the owner's playtest feedback

- **Equips kept** ("retain my equipped character and cosmetics"): a developer owns everything without it being in `owned`, and the profile load dropped any equip not in `owned` before it knew who the player was. Saved equips are kept when the item exists and are checked against ownership once the player is known (`keepOwned`). Verified across a restart.
- **Loading screen**: the ball flew back over the figure's shoulder (`ballAt.X - 0.75`); it now goes down and forward. The ball is 1.5 times bigger, the pillar with it.
- **Stamina**: the team that loses a point gets half its bar back (`RecoverLoser` 0.5, was 0.2).
- **Point celebration**: score effects no longer fire on the client's predicted landing (a late dig could set one off mid-rally). On a point the scorer earned (`Config.Match.Celebrate`), after the server's call:
  - the camera takes a three-quarter close-up of the scorer from the net side (`heroShot`);
  - their equipped effect goes off behind them;
  - their card slides in: a slanted plate in their team colour, their Roblox headshot (`AvatarUserId` on every character model), name, tier, character, role and ability, and the point's word.
- **AI sets**:
  - When the setter takes the first ball, the closest bot now sets. The middle was covering the human wing spiker and watched it drop.
  - A set to a human is theirs: no backup middle.
  - Quicks: 5 to 14% of good passes.
  - A spike jump cuts the pose it took off from, so an early jump raises the arm.
- **Your teams** ("allow yourself to make 3 teams", "you pick your ai team, and you control when they pop the ability"):
  - The Players screen has a left panel with 3v3 / 2v2 / 1v1 tabs, the roles down the side, and a card per slot laid out after the owner's reference: stats, tier, ability, Pick/Swap/Clear, and Change on your own slot.
  - Picks are saved per mode and role (`profile.teams`, `teamPick`). Bots filling the team's first player's side play them at that player's upgrade levels.
  - Your AI teammates' active abilities are yours: keys 1 and 2 (D-pad left and right) or the strip under your ability card. Bots on a team with a player never fire their own.
  - Verified: picks fill the team in a 3v3. **Not verified**: the 1 and 2 keys in a real match (the test player kept getting benched as idle and Studio's viewport was hidden). Try it once.
- **Mobile controls** (the owner's references):
  - Three big see-through round buttons bottom right that change with the moment: serve, Basic / Spike Serve / Approach; ground, Slide / Bump / Approach; air, Feint (the bump button) / Spike.
  - Set and Block pop up when they apply, and a skill column on the left holds your ability and your AI teammates'.
  - Roblox's dynamic thumbstick (`DevTouchMovementMode`, set in the project and in Studio's StarterPlayer; **save the place**).
  - Not seen on a phone yet.
- **Practice mode** ("rework the tutorial and add a proper practice mode... dont make them rallies"):
  - `PracticeService` runs a hidden practice lobby on the court instead of a match: a 2v2, bots standing still.
  - Each rep it launches the set or the attacker's spike itself (synthetic metas and touches), judges your real touch (`MatchService.onHit`) or the landing (`BallService.onDead`), and resets.
  - Drills (shared/Tutorial): spike 3, block 3, serve 3 in a row, dig 3 in a row.
  - The tutorial is the four in order. The top nav has a Practice tab (a card per drill, and the tutorial). The HUD coach shows the drill and its dots.
  - Verified in a playtest: every drill feeds (the setter's sets to you, their attacker's spikes, the serve in your hands), misses count, and "Back to the menu" ends it. **Not verified**: a successful rep (the MCP keyboard input didn't reach the game). Play each drill once and tune `Config.Practice` (attack speeds, the block drill's target depth, the timings).

### Fourteenth session: settings

The owner asked for "some basic settings": movable and resizable touch buttons, and a double approach "similar to the spike:cross... hit jump once, which starts your approach, and press it again to jump", with a floor squeak (their upload, coming).

- **Settings save** in the profile (`profile.settings`, cleaned by `src/shared/Settings.lua` from the lists in `Config.Settings`): the switches, the camera shake and the touch layout. The client applies them once from the first profile snapshot (`State.setProfile`) and sends them all back (`Profile` `"settings"`) `SaveDelay` after the last change. Verified in Studio: junk, unknown keys and NaN are dropped, and a setting survives a restart.
- **Double approach** (`State.settings.doubleApproach`, off by default): Spike on the ground starts a run-up (`MovementController` `run`: `ApproachRun` x walk speed x Approach, steered with Move, the `Approach` pose, the `Squeak` slot, ActionFX `Approach` so others see and hear it); the second press plants into the usual gather and takeoff. A run-up with no second press takes off after `ApproachRunMax` (0.9 s); a slide, a knockback or the rally ending calls it off. The Spike label reads Approach, then Jump. A sim checks every character's run is faster than walking and a full one covers 5.0 to 8.2 m. **Not played by hand**: MCP input can't reach the game, so nobody has pressed it yet.
- **Touch layout editor** (Settings > Touch controls > Edit, touch devices only): every button over a dimmed screen; drag to move, tap one or All and size 60% to 160%, Reset, Cancel, Save (`State.settings.touchLayout`: each button's centre as a fraction of the screen, and its size).
- **Fixed: touch buttons were off in the middle of the screen on phones.** The button frame's UIScale (0.7 on a phone) shrank the whole frame toward the top-left, so the "bottom right" buttons sat around 60% across. The frame is now sized 1/scale. Measured in Studio: the Approach button's centre is 73 px (104 x 0.7) from the right and bottom edges.
- The settings panel shrinks to fit a short screen, and its switches follow changes from anywhere.

Then, the owner: "matchup intro, showcases both teams at the start similar to game entrances showcasing a team. at the bottom, show team name, icon and show off what characters the team is using. make intro poses available and at the end of a game, show off the characters. instead of elims death assists, do spikes blocks aces." Their references (layout only): a Splatoon 3 team intro, and a Roblox results screen (VICTORY plate, the player posed with sparkles, a stat card, Rematch / Play Again / Leave).

- **Intro poses**, a fifth cosmetic kind (`Config.Cosmetics.Pose`, attribute `IntroPose`, the "Intro pose" banner): Ready (everyone's), Arms Crossed, Call Your Shot, Victory Fist, Double Flex, Sky Attack (floats in a spike wind-up). AnimationController's `Intro_<Key>` poses, plus `Intro_Tired` (hands on knees) for the losing side. They were designed with an offline preview, `tools/pose_preview.py`: Studio's server poses a clone of the owner's avatar and posts every part's box to it (`serve`), and it draws front and side views to a PNG (`render`). Its docstring holds the Studio snippet and the joint conventions. The Locker's Intro pose tab previews the pose on your avatar in the gym (`SceneController.setPractice` with `posing`). Bots wear random ones like their other cosmetics. A sim checks every key has its pose.
- **LineupController** (new): clones each entity's model on the court (`Util.modelOf`), rigs and poses it in a ViewportFrame (a row facing the camera, pedestals in the team colour; `newScene`, `showSlot`, `stepScene`), updated on Heartbeat.
  - **Intro** on `MatchStart` (the roster entries now carry `pose`): a wipe in each team's colour, that team's row dropping in one by one with name tags, and a plate along the bottom (the team emblem, the name, the mode and court, YOUR TEAM on yours, a chip per character: tier, character, role, ability); then a signal-yellow wipe to both names meeting around VS, a fade, and the "Game on!" callout (moved here from UIController). `Config.Match.Intro` holds the timeline; `PreMatchTime` went 3.2 to 7.6 s and a sim checks the intro fits.
  - **Showcase** on `MatchEnd` (the results rows now carry `role` and `pose`): your team, VICTORY in their poses with twinkling sparkles (images: particles don't draw in a viewport) or DEFEAT in the tired pose, the team name on a plate, a card under each (tier badge, name, @username or AI and the character, Spikes / Blocks / Aces, digs and top spike, MVP tag), your rewards line, Continue. `MatchEndTime` 9 to 11 s. UIController's old results table is gone.
  - Team emblems: `Assets.Images.TeamSunrise` (a line sun) and `TeamTidal` (three waves), Creator Store decals, named by `Config.Teams[team].Icon`.
- Verified in a Studio playtest through remotes: the intro ran on time (both teams' plates, chips and names right, VS, closed 7.6 s in as the set started), three clones per team posed in their poses (the bots' random ones included), ordered left to right and turned toward the middle; a forfeit showed DEFEAT with three cards and the right stats. **Not seen**: nothing was looked at on screen (Studio's window was covered, and RenderStepped doesn't run then, which is why LineupController uses Heartbeat). The owner needs to look at both.

### Fifteenth session: the owner's playtest of the fourteenth session, and their sounds

The owner sent a screenshot of the matchup intro (the Sunrise team on the Beach) and said "ui looks good though". Their feedback, and what changed:

- "for double approach you have to click spacebar twice": **Space is Spike** (it was a plain jump). It's bound with ContextActionService above Roblox's own jump and sunk, so a press never also hops. On the ground it's the run-up jump, or the run-up and then the jump with Double approach. There's no plain jump key any more.
- "on mobile holding serve toss doesnt work", "approach button doesn't work", "slide button doesn't work": a lifted finger now releases its button even when the end event comes with a different InputObject (matched by kind and position), and every frame a held button whose input has ended lets go. The double approach's run-up heads for the net when no direction is held; a phone player's left thumb is often off the stick. **Not verified**: the Slide path looks right in the code, and no touch device was available. In Studio, MobileControls prints `[SpikeRush] touch <button> -> <action>` and `released after` lines; ask the owner for Output from a mobile test, then remove the prints.
- "for blocking going up to the net and holding bump should do it, not a seperate button": at the net the Bump button becomes **Block** (hold to charge, its ring warms to orange; let go to jump). The separate Block button is gone from the controls, the layout editor and `Config.Settings.Touch.Buttons`.
- **Sounds** (the owner's uploads; all verified as theirs with `GetProductInfo`, access shared): Bump (their "real bump", 111670558415526), Set, Feint, Whiff ("missed spike or swing", for a whiff), Squeak (two variants, "squeak 1" and "SQUEAK 2": a slot can now hold a list and each play picks one), CrowdCheer ("end of rally cheer"), UIClick, UITick (a new slot for the steppers and the stat + and - buttons), UIOpen (popups), UIOpenLong (a new slot for screen changes and the intro's wipes; it replaces UISwipe), UISelect and UIConfirm. The owner removed the combined uploads "spike + rec" and "spike rec + mid rally cheer" ("they sound bad", "the one where they are combined"), so a dug spike plays the Bump like any receive.
- "all the audios feel a little delayed": the new uploads carried 0.3 to 0.55 s of silence at the front (set, feint, whiff, the cheer), so each now has a `start` in `Assets.SoundFiles`, and the old trims were tightened by 10 to 30 ms. Gains bring touches to about 300 and the menu set to about 200 (peak `PlaybackLoudness` at Volume 0.5). Menu sounds now play as a button goes down instead of on the click, which only fires on the release: `Gui.pressSound(button, key, canAct)` sounds it on `MouseButton1Down`, and `Gui.click` (every handler's sound) skips once after a press sounded, so nothing plays twice. `onClick`, tabs, chips and the HUD's buttons use it. Measured in a Quick Match: every sound is audible within 20 to 40 ms of its trigger.
- **The real bump doesn't play yet**: the owner has to click "Click to share access" for asset 111670558415526 in Studio's Output (the place belongs to a group). Then measure its `start` and `gain` like the others.
- **Home's nav** ("on the home screen only these show... change that"): Home now has the same nav as every main screen (`navBar`: Home, Practice, Shop, Players, Locker, Ranks, with Help and Settings at the right of the row). Its old column of Settings, Ranks and Help down the right is gone.
- **The Match screen** ("play menu in this style", the owner's screenshot of The Spike's Match screen; layout only): Home's Match plate opens `page("match")`: the main top bar with Home lit (`mainChrome(p, "match", "home")`), a back arrow and "Match" under the currencies (`placeHeaders` moves both with them), the club room blurred (`SpikeRushMenuBlur`, a BlurEffect on while the screen shows) and dimmed, and a row of six tall cards that scrolls sideways when it's wider than the screen (`MATCH_CARDS`): 3v3, 2v2 and 1v1 queue a Quick Match at once; Lobbies and Custom open the lobby window (now titled Lobbies; its Quick Match tab is gone) on the list or Create Lobby; Practice goes to the drills. Each card has an icon and the name on top, a strip under them, the art, and a status line (players waiting, "Starting in 9" on your queue's card, which lights yellow, lobbies open, the tutorial's reward or "Tutorial complete").
  - The art is our own courts, captured in a Studio playtest (the camera placed by a RenderStep bind, the GUIs and the menu's blur off), cropped to portrait (`assets/menu/*.png`) and uploaded to the owner's account with the Studio MCP's `upload_image` (the owner agreed): `Assets.Images.MatchArena`, `MatchBeach`, `MatchRooftop`, `MatchNationals`, `MatchColosseum` and `MatchPractice` (the club room's ball cart).
  - Verified in a playtest by clicking (the MCP mouse input works while Studio's window is visible; its y is 58 px above screen y, the top bar inset): every card, the queue's countdown on its card, the lobby window's tabs.
- **Fixed: "tossing in serve drill doesnt work"**: the client only takes serve input (the toss, X, F, Spike on the held ball) from the match's server (`State.isServer()`: `serverId`), and the serve drill handed you the ball without making you the server. PracticeService now sets `MatchService.serverId` (and `servingTeam`) for a serve rep and clears it for the others. Verified with MCP keyboard input in a playtest: a tap served overhand and counted, a held toss went up and a jump serve counted. The owner's earlier "on mobile holding serve toss doesnt work" may have been this same bug.

## Next steps

Work in this order. The owner's list from 2026-09-27 comes first, in the order they gave it:

0. **The real bump** (111670558415526): once the owner has shared access (Studio's Output: "Click to share access"), measure its `start` and `gain` and add them to `Assets.SoundFiles`.
0. **Custom match settings** ("allow full customization on custom matches, such as what points you play to low as 3 and up to 50"): Create Lobby gets the points to play to (3 to 50) and the other match rules worth changing.
0. **Daon's level-up beam**: when Rising Sun levels up ("Sunrise Lv n!"), a tall beam of light strikes Daon, like the owner's reference (a vertical orange-to-red pillar over the player on the court).
0. **Setter mode**: playing as a setter, you aim where the set will go. Your team sees the spot, marked with a circle or a crosshair; the opponents don't.
0. **Custom scoring sound**: a game pass, also buyable with VP. The owner of it enters their own sound id, which plays when they score.
0. **Custom scoring image**: a game pass, also buyable with VP. The owner of it enters their own image id, which pops up and fades away when they score.
0. **Look at the showcase after a match** (fourteenth session; built without seeing the screen). The owner has seen the matchup intro and likes it ("ui looks good"). Finish a match (a forfeit is quickest) and look at VICTORY and DEFEAT, the cards and the sparkles. Also the Locker's Intro pose tab and the new Recruit banner. Tune from the owner's screenshots: the camera (`newScene` aimY / dist, `FOV`), the spacing, the poses (`Intro_*`), the timings (`Config.Match.Intro`). Possible additions: Rematch / Play Again buttons like the reference, the other team's cards, animated poses.
0. **Check the fourteenth session's settings by hand**: turn on Double approach and play a rally (does the run-up feel right? tune `ApproachRun` and `ApproachRunMax`); on a phone or Studio's device emulator, open Settings > Touch controls > Edit, move and size a few buttons, Save, and rejoin to see they stay. Then the fifteenth session's touch fixes: hold Spike Serve to toss, Approach (it runs at the net with nothing held), Slide, and Bump turning into Block at the net.
0. **Check the thirteenth session's work by hand.** It's all built and pushed, but Studio's viewport was hidden for most of that session, so almost none of it was seen or played. Only the logic was tested through remotes. Save the place first (Ctrl+S): the Toolbox palm and the dynamic thumbstick exist only in the place.
   - **Practice and the tutorial**: every drill was seen feeding its reps (the setter's sets, their attacker's spikes, the serve in your hands) and counting misses, and "Back to the menu" ends it. A *successful* rep was never made: the MCP keyboard input didn't reach the game. Play each drill and the tutorial; check hits count and the coach's dots fill. Tune `Config.Practice`:
     - `BlockKmh` and `BlockTargetDepth` (can the block be reached?);
     - `DigKmh` (can it be dug?);
     - `AttackWindup`, `FeedDelay` and `PauseAfter`.
   - **Your teams**: the Players screen's team panel (3v3 / 2v2 / 1v1 tabs, the role column, the card, Pick / Swap / Clear, Change on your slot, picking from the grid) was built but never seen on screen. Bots filling your team with your picks *was* verified in a 3v3. Keys 1 and 2 (and the strip under your ability card) for your AI teammates' Iron Wall, Turnabout and Rally Cry were never pressed in a real match.
   - **Mobile controls**: never seen. Use a phone or Studio's device emulator. Check that the three buttons change for serve, ground and air, and that Bump feints in the air. Check the Set and Block pop-ups, the skill column and the floating thumbstick.
   - **Point celebration**: the card was seen sliding in; the camera's close-up on the scorer and the effect behind them were not.
   - **Loading screen**: the ball now flies down and forward, 1.5 times bigger, with the pillar wider to match. Not seen.
   - **AI fixes**, none seen in a real rally:
     - an early jump for a quick raises the arm;
     - a bot sets when the setter took the first ball;
     - the middle leaves your sets alone;
     - quicks are rarer.
   - **Sounds**: nobody has listened since the per-file start offsets, gains and the louder, punchier mix bus (the owner said "weak" and "doesn't match the power of the game" before them). Listen with the owner and tune the file gains in `Assets.SoundFiles`, the per-call volumes in AudioController and the bus in `AudioController.init`. Also check the recruit flight sound (RecruitFly).
1. **Sound pass: the owner supplies every sound** (see the twelfth session). The owner uploads sounds (from a free sound library) and sends ids with labels; nothing else plays. Empty slots are silent until the owner sends theirs. Still empty: ReceivePerfect, SpikeHeavy (borrows Spike), Serve, Toss, Block, Stuff, NetHit, Slide, Whoosh, GuardBreak, Thunder, AzureCharge, AzureRelease, Blades, RallyCry, ImpactFrame, Whistle, Point, Timeout, CrowdLoop, CrowdGasp, Music, UIHover, and the recruit slots except RecruitFly.
   - For each new id: check it's the owner's (`MarketplaceService:GetProductInfo`). The place belongs to a group and the audio to the owner, so a new upload fails with "The experience doesn't have access permission ... Click to share access" in Output until the owner clicks it.
   - In a playtest, play it from a loaded Sound and read `TimePosition` and `PlaybackLoudness` every frame. Add `start` (a little before the sound begins) and `gain` (peak loudness to about 400 at Volume 0.5) to `Assets.SoundFiles`.
   - Tune by ear with the owner: per-call volumes in AudioController, the file gains, and the mix bus in `AudioController.init`.
2. **Courts: what's left** (the eleventh session built them; see its status entry).
   - The owner should save the place in Studio to keep the Toolbox palm in `ToolboxAssets.Models.PalmTree`.
   - Get the owner's screenshots of each court and adjust from their feedback (colours, prop density, the rooftop's skyline, the size of the beach islands).
   - Click through the Create Lobby court stepper by hand once; only its layout was checked.
   - Menu rooms under an outdoor court's lighting: the club room keeps the last court's light after a match (a sunny afternoon after Beach, dusk after Colosseum). Check it looks right, or have SceneController set its own light while the menus are up.
   - Optional: Toolbox models for `BeachUmbrella` and `Column` (TOOLBOX.md says what failed), and a court preview image in the picker.
3. **Score card customization** (the owner: "customization on this comes later"). Every scorer's card now uses one default design: a slanted plate in the team colour with halftone and chevrons, the headshot, the name and the character. The owner's reference is a gallery of card designs, each locked behind a challenge ("Complete 800 Sets (565/800)"), with an equipped one. Build it in our own art:
   - card designs as a cosmetic kind (`Config.Cosmetics`, the Locker);
   - challenge progress from the career counters;
   - `UIController`'s `showScoreCard` reads the equipped design.
4. **Known limits of this session's features** (fix if the owner minds):
   - A practice session takes the server's one court. If a match is on, it waits (Studio) or goes to its own reserved server (live).
   - With more than one player on a team, only the first player's AI picks fill the bots.
   - Players who finished the old tutorial checklist's serve, spike and block steps keep those; the tutorial then only asks for the dig drill.
   - The reference's mobile "Highlight" (camera) button wasn't copied.
5. Playtest in Studio. Fix runtime errors; the game's own warnings in Output are prefixed `[SpikeRush]`. Reserved servers only work in a published game: test lobbies that teleport with two or more players in a live server.
6. Tune the feel:
   - in `Config.Player` and `Config.Scale.JumpScale`: the jump look, run-up, air control and hang;
   - in `CameraController`: the camera distances;
   - `Config.Bots` for bot skill by tier and `Config.Stamina` for drain;
   - `Config.Spins` and `Config.Rarity` for the spin economy.
7. Create the VP and Gold Developer Products and paste their ids into `Config.Shop.Packs` and `Config.Shop.GoldPacks`; upload `assets/icon/GameIcon.png` and `Thumbnail.png`.
8. Fill the Toolbox model and VFX slots (TOOLBOX.md). Sounds are only the owner's uploads (step 1); the `assets/sfx` files aren't used.
9. Lower `Config.Progression.StartingVP` (500, for testing) before launch if the economy needs it.
10. More characters and abilities: add hand-set entries or slots in `tools/generate_roster.py` and re-run; a new ability needs a Config entry, its HitLogic effect (with a sim), and its HUD and VFX.
11. Optional: more spike styles and score effects, uploaded action animations in `Assets.Animations`, substitutions and pause. `assets/sfx` and `tools/generate_sfx.py` are unused now that every sound is the owner's; delete them if the owner agrees.
