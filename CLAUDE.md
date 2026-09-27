# Spike Rush: notes for Claude

A Roblox volleyball game built with Rojo. Moving to a new account? See CONTINUE.md. Read HANDOFF.md first: what the owner wants, how the code fits together, and the next steps. README.md covers setup and mechanics. TOOLBOX.md covers the asset slots.

## Two Claudes, one branch

- Work on `claude/spike-rush-continuation-uwunbo`. Pull before you start (`git pull --ff-only origin claude/spike-rush-continuation-uwunbo`). Commit and push when a piece of work is done.
- The owner's PC Claude has Roblox Studio over MCP and does the UI, VFX, Toolbox assets and courts. The cloud Claude does gameplay code and the sims.
- Anything placed only in Studio, such as models dropped into `ToolboxAssets`, is lost unless the place is saved. Remind the owner to save.
- Before a long session ends, write what's left into HANDOFF.md's "Next steps". A fresh session only knows what's in the files.

## Rules

- Original art, audio, names and branding only. Nothing from The Spike or SUNCYAN goes into the game, including sounds recorded from their games. Creator Store (Toolbox) assets are fine, except for sounds.
- Sounds are the owner's own uploads only (they come from a free sound library): the owner sends ids with labels and they go in `Assets.Sounds`, with their start and gain in `Assets.SoundFiles`. No Roblox library sounds, Creator Store sounds, generated sounds or stand-ins; an empty slot is silent.
- The checkers parse a Luau subset:
  - no compound assignment (`+=`);
  - no `continue`, not even as a field name;
  - no backtick strings;
  - no type annotations.
- After every change, these must report 0 problems and 0 failures:
  - `python3 tools/check_lua.py`
  - `python3 tools/check_config.py`
  - `python3 tools/check_api.py`
  - `texlua tools/sim_test.lua`
- A changed mechanic gets a scenario in `tools/sim_test.lua`.
- Asset ids go in `src/shared/Assets.lua`; tuning goes in `src/shared/Config.lua`.
- The repo is public. `reference/` is gitignored; never commit reference images or recordings of other games.
