# Toolbox assets

Spike Rush runs entirely on procedural visuals and built-in sounds, but every visual and audio slot can be replaced by a Toolbox (Creator Store) asset without touching code. This file lists the slots, what to search for, what a good asset for each slot looks like, and the three ways to install one.

## What comes from the Toolbox, and what doesn't

Use the Toolbox for art, audio, animation and UI: the ball model, particle effects, sound effects, action animations and icons.

Don't swap in Toolbox gameplay code, even though the Toolbox has plenty of it:

- **Ball physics and hitboxes.** The ball is an analytic path computed by `src/shared/BallPhysics.lua`, and every touch goes through `src/shared/HitLogic.lua`. The client predicts each touch with the same deterministic code the server runs, so a physics-part ball or a raycast hitbox module would break prediction and desync every hit.
- **Movement systems.** Lane lock, the run-up jump, the anime hang force and the Azure hover are tuned so that the top of every jump lands exactly on the character's hitting point (`Characters.jumpHeight`). A sprint/dash kit would fight that.
- **Scripts in general.** Free models are a common way to smuggle in backdoors (`require(<id>)` loaders). Every asset the game inserts is sanitized: scripts are deleted and parts are made non-colliding. The one gap is a model you drag in by hand while editing, because a `RunContext` script inside it could run before the server strips it. Check a model's Explorer tree for Scripts before dragging it in, or use route 2 below, which strips scripts before anything is parented.

Also skip anything that looks ripped from *The Spike* (its sounds, sprites or UI). The project stays original.

## Three ways to install

The first one found wins, so a hand-placed asset always beats an id.

1. **Drag it in.** Insert the asset from the Toolbox, then move it to `ReplicatedStorage.ToolboxAssets.<Category>` and rename it to the slot name (for example `ToolboxAssets.VFX.ThunderImpact`). Rojo never deletes anything in those folders, so this survives `rojo serve`.
2. **Bake it from ids.** Paste the asset ids into `Assets.Toolbox` in `src/shared/Assets.lua`, sync, then run this in the Studio command bar (edit mode) and save the place:
   ```lua
   require(game.ServerScriptService.Server.Services.ToolboxService).install()
   ```
   This uses `game:GetObjects`, which can read any public asset. Pass `true` to replace slots that are already filled.
3. **Load at runtime.** With ids in `Assets.Toolbox`, `ToolboxService` loads every empty slot when the server starts. It tries `AssetService:LoadAssetAsync` first, which loads any free Creator Store model once Game Settings > Security > **Allow Loading Third Party Assets** is on (its scripts can't run, and they're deleted anyway). Otherwise it falls back to `InsertService`, which only loads assets owned by the place's owner (or group) or made by Roblox, so click **Get** on the Creator Store first to put the model in your inventory. Failures are printed in Output with a `[SpikeRush]` prefix.

Sounds, animations and images don't go in `Assets.Toolbox`. Paste their ids into `Assets.Sounds`, `Assets.Animations` and `Assets.Images`, or drop a `Sound` into `ToolboxAssets.Sounds.<Key>`.

## Slots

### Ball: `ToolboxAssets.Models.Volleyball`

Search for "volleyball". Pick a single mesh (MeshPart) or a small model with the classic three-panel look. It's scaled to the gameplay ball (0.53 m diameter) and centred automatically, so its size doesn't matter. Avoid balls with physics scripts, BodyVelocity or constraints; they're stripped anyway. The same ball is every ball in the menus too: the ball carts, the volleyballs of the recruit sequence and the Locker's practice spike.

Filled now with "Volleyball Ball" (`123275048347543`, one MeshPart in yellow, blue and white).

### Menu props: `ToolboxAssets.Models.Locker`, `Bench`, `BallCart`

The club room's lockers, its bench, and the ball cart in the club room and the recruit gym. Each is scaled to its spot by its bounding box (the lockers to 12 studs tall against the back wall, the bench to 11 studs long, the cart to 8.8 studs in the club room and 12 in the gym) and stands on the floor. A cart comes stocked: any part in it about as wide as it is tall and deep (the balls of a basketball rack, say) is swapped for the Toolbox volleyball. Until a slot is filled the room uses simple built stand-ins.

The front of a prop is the -Z face of its bounding box, and a bench or cart should run along X. A model that faces another way takes a number attribute `Yaw` (degrees: 90, 180 or -90) that turns it; `Assets.ToolboxYaw` stamps it on models loaded by id.

Filled now with "Locker School" (`15868311397`, six blue lockers), "Modern Bench" (`5110642461`, wood slats on metal legs) and "Basketball rack" (`10807459912`, a two-tier ball rack). Search for "school lockers", "locker room bench" and "ball rack" or "ball cart" to swap them.

### Effects: `ToolboxAssets.VFX.<Name>`

Each effect fires once at the contact point. The template can be an Attachment, a Part or a Model holding ParticleEmitters. The game calls `:Emit(n)` on every emitter, where `n` is the emitter's `EmitCount` attribute (default 20); add an `EmitDelay` attribute (seconds) to stagger layers. Emitters are switched off first, so looping effects become bursts. A Part template is hidden unless you give it a `Visible = true` attribute.

| Slot | When | Search for |
|---|---|---|
| `SpikeImpact` | a normal spike | "hit impact vfx", "punch impact" |
| `PerfectImpact` | a spike of 120 km/h or more | "anime impact", "shockwave vfx" |
| `ThunderImpact` | Thunder Spiker | "lightning impact", "thunder vfx" |
| `AzureImpact` | Azure Dragon | "blue energy burst", "water dragon vfx" |
| `BlockImpact` | stuff block | "shield hit vfx", "block impact" |
| `FloorImpact` | the ball hits the floor | "ground impact", "dust burst" |
| `ReceiveImpact` | bump, set, free ball | "small hit spark" |
| `NetImpact` | the ball hits the net | "small ripple", "soft impact" |
| `JumpBoom` | a run-up or serve jump | "jump boom", "ground slam", "dash smoke" |
| `GuardBreak` | a team's stamina breaks | "shatter vfx", "glass break particles" |
| `AzureAura` | held on the player while charging Azure | "aura vfx", "blue flame aura" |

`AzureAura` is the one held effect: its emitters stay on while the player charges, and their rate scales with the energy gathered.

The side-view camera sits about 64 studs away with a long lens, so effects need to be big and bright to read. Prefer emitters with `LightEmission` near 1 and sizes of 2 to 8 studs.

Particle textures for the built-in effects are in `Assets.Images` (`Spark`, `Smoke`, `Fire`). A Toolbox decal or image id works there too.

### Sounds: `Assets.Sounds.<Key>` or `ToolboxAssets.Sounds.<Key>`

Since the 2022 audio privacy change, a sound only plays in your game if it's public on the Creator Store (Roblox's own sound library is) or you uploaded it yourself. The 26 original sounds in `assets/sfx` are the default plan; the Toolbox is good for the crowd and the music.

| Key | Search for |
|---|---|
| `CrowdLoop` | "stadium crowd ambience", "arena crowd loop" |
| `CrowdCheer`, `CrowdGasp` | "crowd cheer", "crowd gasp" |
| `Music` | a loopable sports or anime track from Roblox's music library |
| `Whistle` | "referee whistle" |
| `Spike`, `SpikeHeavy`, `Bump`, `Set` | "volleyball hit", "ball smack" |
| `Thunder` | "thunder crack", "lightning strike" |
| `Boom`, `Whoosh` | "whoosh", "impact boom" |

### Animations: `Assets.Animations.<Slot>`

Roblox only plays animations owned by the place's owner (or group) or by Roblox. A Toolbox animation (usually a `KeyframeSequence` inside a model) has to be opened in the Animation Editor and published from your account; paste that new id. Slots: `Bump`, `Set`, `Swing`, `Tip`, `Block`, `Slide`, `Charge`, `Toss`, `Stance`, `Knockback`, `Celebrate`. Search for "volleyball animations" or "spike animation" and pick R15 ones.

Bots already use Roblox's own default R15 idle, run, jump and fall animations (`Assets.BotAnimations`), which any game may play.

### UI icons: `Assets.Images.AbilityThunder`, `Assets.Images.AbilityAzure`

Shown in the ability panel and on the lobby cards. Search for "lightning icon" and "dragon icon"; square, transparent PNG decals work best.
