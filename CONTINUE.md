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

## Where things stand (end of the thirteenth session)

Built: 37 characters and their abilities, bots, lobbies, four courts (Beach, Colosseum, Nationals, Night Rooftop), recruit, locker, shop, ranks, practice drills, the tutorial, mobile controls, point celebrations and the owner's sounds.

Next, in HANDOFF.md's order:

0. **Hands-on check** of the thirteenth session's work: practice drills, AI teammate abilities (keys 1 and 2), mobile controls, the point celebration.
1. **Sound:** the owner sends ids for the empty slots, and Claude sets each one's start and gain.
2. **Courts:** polish from the owner's screenshots.
3. **Before launch:**
   - create the VP and Gold Developer Products;
   - upload the game icon and thumbnail;
   - lower `StartingVP`.

## Tips to save tokens

- Use one conversation per task, and `/clear` between tasks.
- A fresh conversation reads CLAUDE.md on its own, and HANDOFF.md when you ask it to. Anything not written there is forgotten, so always have Claude update HANDOFF.md and push before you clear.
