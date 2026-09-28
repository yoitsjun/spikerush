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

## Where things stand (fifteenth session, last push 28 Sep 07:42)

Built: 37 characters and their abilities, bots, lobbies with custom rules (points 3 to 50, win by 2, best of 3 or 5, timeouts), five courts, recruit, locker, shop (VP and Gold packs live, and the custom score sound and image perks), ranks, practice drills, the tutorial, mobile controls, point celebrations, the owner's sounds, saved settings, the matchup intro and the showcase, the Match screen in The Spike's layout with our own court art, Daon's level-up beam, and setter mode (aim the set's height, charge its distance; your team sees the marker). Touch controls now have their own floating thumbstick, and Slide, Jump (which replaced Approach on touch) and the serve toss work. Studio's `ForceTouch` workspace attribute fakes a touch device for testing with the mouse.

Next, in HANDOFF.md's order:

1. **Hands-on checks** of this session's work: setter mode (a real aimed set, two players for the teammate marker), the Shop's Perks column and a scored point with a custom sound and image, the Match screen at 16:9, a best-of-3 ending, and the older unchecked items (showcase, drills). Touch controls on a real phone: the stick's feel, Slide, Jump and the serve toss.
2. **Game passes:** create "Custom Score Sound" and "Custom Score Effect" (199 Robux each) and put their ids in `Config.Perks` (both `PassId` are still 0). The VP and Gold Developer Products already have their ids.
3. **Sound:** the owner sends ids for the empty slots (ReceivePerfect, Serve, Toss, Block, Stuff, Whistle, Point, the crowd loop and more); Claude sets each one's start and gain.
4. **Courts:** polish from the owner's screenshots.
5. **Score card customization** (asked for "later"): card designs unlocked by challenges.
6. **Before launch:** upload the game icon and thumbnail; lower `StartingVP` (about 150).

## Tips to save tokens

- Use one conversation per task, and `/clear` between tasks.
- A fresh conversation reads CLAUDE.md on its own, and HANDOFF.md when you ask it to. Anything not written there is forgotten, so always have Claude update HANDOFF.md and push before you clear.
