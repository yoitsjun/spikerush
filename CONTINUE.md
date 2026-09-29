# Continue Spike Rush in a fresh conversation

Use this when a conversation gets big (hundreds of thousands of tokens) or when you switch Claude accounts. Everything is saved in GitHub, so nothing is lost.

- Repo: https://github.com/yoitsjun/spikerush (public)
- Branch: `claude/spike-rush-continuation-uwunbo`

## Before you clear (the old conversation)

1. **Save the place in Studio (Ctrl+S).** The palm model, the thumbstick and other Toolbox pieces live only in the place.
2. Paste this into the old conversation:

> Before I clear this conversation: commit and push everything, and make sure HANDOFF.md's "Next steps" has everything that's left, including anything half-done and anything I asked for that isn't done yet. Then tell me it's safe to clear.

3. When it says it's safe, type `/clear`. It's free.

## Claude Code on your PC (connected to Roblox Studio)

After `/clear`, or after `/login` with a new account, paste:

> Pull the latest from the branch claude/spike-rush-continuation-uwunbo. Read CLAUDE.md and HANDOFF.md, then continue from "Next steps" in HANDOFF.md, starting at the top. Before you stop, write anything unfinished into HANDOFF.md and push.

On a new account, if Studio isn't connected:

```
claude mcp add --scope user --transport stdio Roblox_Studio -- cmd.exe /c "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat"
```

Then, in Studio, go to Assistant, then Settings, then MCP Servers, and make sure "Claude Code CLI" is connected.

Keep `rojo serve` running from the same folder Claude works in.

## Cloud Claude (claude.ai/code)

1. Start a new session on `yoitsjun/spikerush`. On a new account, connect GitHub first, using the account that owns the repo.
2. Paste:

> Check out the branch claude/spike-rush-continuation-uwunbo and work on it. Read CLAUDE.md, CONTINUE.md and HANDOFF.md, then continue from "Next steps" in HANDOFF.md. Run the four checks after every change, then commit and push to that branch.

## Where things stand (sixteenth session, 28 Sep)

Newest: **Dante**, an S+ wing spiker with the game's highest Attack (222), and his ability **Feral Leap** (the owner's "based on raul from the spike"): hold Jump on the ground to charge a violet arc, let go to leap, carried further the longer you charged, with the spike powered by the charge; a full charge at the net smashes through a weaker block, and the first full one of a match is a First Strike. Seen working in Studio (the charge, the leap, a leap spike, a bot Dante); the owner hasn't tried him yet. Then the owner's icons request: every ability is now a round badge at the side of the match screen (yours and your teammates' on the left, theirs on the right) with a ring that fills with its charge or cooldown, and Azure Dragon's charge is a curved arc behind the spiker. The icons the owner sent are The Spike's own art, so Creator Store icons of the same ideas stand in (TOOLBOX.md).

Built: 38 characters and their abilities, bots, lobbies with custom rules (points 3 to 50, win by 2, best of 3 or 5, timeouts), five courts, recruit, locker, shop (VP and Gold packs live, and the custom sound effects and score image perks, with their game passes), ranks, practice drills, the tutorial, mobile controls, point celebrations, the owner's sounds, saved settings, the matchup intro and the showcase, the Match screen in The Spike's layout with our own court art, Daon's level-up beam, and setter mode (aim the set's height, charge its distance; your team sees the marker). Touch controls now have their own floating thumbstick, and Slide, Jump (which replaced Approach on touch) and the serve toss work. Studio's `ForceTouch` workspace attribute fakes a touch device for testing with the mouse.

Next, in HANDOFF.md's order:

0. **The economy features** (codes with RELEASE, daily rewards and codes for group members who liked the game, lucky spins for Robux, gifting, the Robux leaderboards, the admin panel with 2x VP / 2x Gold events, announcements and Give by username): run in Studio and working. The owner creates the Developer Products (lucky spins 1, 3, 5, 10 and 2x VP boosts 15 min, 30 min, 1 h, 3 h; ids into `Config.Lucky.Packs` and `Config.Boosts.Packs`).
0. **Dante:** the owner plays him and says how the charge, the leap's distance and the arc feel; tune `Config.Abilities.Feral`. Sounds for `FeralFull` and `FeralLeap` are empty.
0. **The badges:** the owner looks at them and at Azure's arc, and says whether the stand-in icons, sizes and places are right.
1. **Hands-on checks** of the fifteenth session's work: setter mode (a real aimed set, two players for the teammate marker), the Shop's Perks column and a scored point with a custom sound and image, the Match screen at 16:9, a best-of-3 ending, and the older unchecked items (showcase, drills). Touch controls on a real phone: the stick's feel, Slide, Jump and the serve toss.
2. **Game passes:** done ("Custom Sound Effects" and "Custom Score Effect" are set in `Config.Perks`). Custom sounds now cover scoring, spikes, jumps, serves, receives, sets, blocks and feints; the owner should try the Shop's picker.
3. **Sound:** the owner sends ids for the empty slots (ReceivePerfect, Serve, Toss, Block, Stuff, Whistle, Point, the crowd loop and more); Claude sets each one's start and gain.
4. **Courts:** polish from the owner's screenshots.
5. **Score card customization** (asked for "later"): card designs unlocked by challenges.
6. **Before launch:** upload the game icon and thumbnail; lower `StartingVP` (about 150).

## Tips to save tokens

- Use one conversation per task, and `/clear` between tasks.
- A fresh conversation reads CLAUDE.md on its own, and HANDOFF.md when you ask it to. Anything not written there is forgotten, so always have Claude update HANDOFF.md and push before you clear.
