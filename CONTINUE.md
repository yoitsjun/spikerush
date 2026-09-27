# Continue Spike Rush on a new account

Everything is saved in GitHub, so a new Claude account can pick up with nothing lost.

- Repo: https://github.com/yoitsjun/spikerush (public)
- Branch: `claude/spike-rush-continuation-uwunbo`

## 1. Cloud Claude (claude.ai/code)

1. Sign in with the new account and connect GitHub. Use the same GitHub account that owns `yoitsjun/spikerush`, so Claude can push.
2. Start a new session on the `yoitsjun/spikerush` repo.
3. Paste this as the first message:

> Check out the branch claude/spike-rush-continuation-uwunbo and work on it. Read CLAUDE.md, CONTINUE.md and HANDOFF.md, then continue from "Next steps" in HANDOFF.md, starting with step 0, the sound pass. Run the four checks after every change, then commit and push to that branch.

## 2. Claude Code on your PC (the one connected to Roblox Studio)

1. **Save the place in Studio first (Ctrl+S).** Things placed only in Studio, like the score effects in `ToolboxAssets.VFX`, are lost otherwise.
2. Log in with the new account. In PowerShell:
   ```
   claude
   ```
   Then type `/login` and pick the new account.
3. Reconnect Roblox Studio, if the new account doesn't see it:
   ```
   claude mcp add --scope user --transport stdio Roblox_Studio -- cmd.exe /c "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat"
   ```
   In Studio, go to Assistant, then Settings, then MCP Servers, and make sure "Claude Code CLI" is connected.
4. Start Claude Code in the project's git folder and paste:

> Find your git clone of this project, or clone https://github.com/yoitsjun/spikerush, and check out the branch claude/spike-rush-continuation-uwunbo. Pull the latest and tell me the folder path. Read CLAUDE.md and HANDOFF.md, then continue with step 0 in Next steps, the sound pass. Before you stop, write anything unfinished into HANDOFF.md and push.

5. Run `rojo serve` from that same folder so Studio shows the latest code.

## Where things stand

- **Game:** complete and playable, with 37 characters and all the abilities, bots, lobbies, recruit, locker, shop, ranks and tutorial. The UI has been overhauled in The Spike's layout with original art, and the VFX were redone with Creator Store textures. See HANDOFF.md for the details.
- **Next up:**
  1. **Sound**, which the owner wants before courts. See HANDOFF.md step 0. Sounds must come from the Creator Store, be original, or be recorded by the owner from real things. Nothing recorded from The Spike or any other game.
  2. **Courts:** Beach, Colosseum, Nationals, plus a court picker.
- **Still to do before launch:**
  - Create the VP and Gold Developer Products and paste their ids into `Config.Shop`.
  - Upload the game icon and thumbnail.
  - Lower `StartingVP`.

## Tips to save tokens

- Use one conversation per task. Type `/clear` between tasks; it's free.
- Before clearing, have Claude write anything unfinished into HANDOFF.md and push. A fresh conversation reads CLAUDE.md on its own and HANDOFF.md when asked.
