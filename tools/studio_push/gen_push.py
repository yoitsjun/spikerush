"""Builds push.json for Studio: exact old/new pairs for scripts that already exist there (taken
from `git diff` of each file against a base snapshot), and whole sources for new scripts.

usage: gen_push.py <repo> <base dir> <out json>
<base dir> holds copies of the files as they were before this session's edits (same relative
paths); a file missing there is new.
"""
import difflib, io, json, os, sys

repo, base, out = sys.argv[1], sys.argv[2], sys.argv[3]
FILES = [
    "src/shared/Config.lua",
    "src/shared/Lobbies.lua",
    "src/shared/Net.lua",
    "src/shared/Story.lua",
    "src/shared/StoryLook.lua",
    "src/shared/StoryScript.lua",
    "src/server/Services/LobbyService.lua",
    "src/server/Services/MatchService.lua",
    "src/server/Services/TeamService.lua",
    "src/server/Services/BotService.lua",
    "src/server/Services/ProfileService.lua",
    "src/client/Main.client.lua",
    "src/client/Controllers/MenuController.lua",
    "src/client/Controllers/SceneController.lua",
    "src/client/Controllers/StoryDialogue.lua",
    "src/client/Controllers/StoryMenu.lua",
]
if len(sys.argv) > 4:
    FILES = sys.argv[4:]


def read(p):
    with io.open(p, encoding="utf-8", newline="") as f:
        return f.read().replace("\r\n", "\n")


def studio_path(rel):
    name = os.path.basename(rel)
    for ext in (".server.lua", ".client.lua", ".lua"):
        if name.endswith(ext):
            name = name[: -len(ext)]
            break
    if rel == "src/first/LoadingScreen.client.lua":
        return ["ReplicatedFirst", "LoadingScreen"]
    if rel.startswith("src/shared/"):
        return ["ReplicatedStorage", "Shared", name]
    if rel.startswith("src/server/Services/"):
        return ["ServerScriptService", "Server", "Services", name]
    if rel.startswith("src/server/"):
        return ["ServerScriptService", "Server", name]
    if rel.startswith("src/client/Controllers/"):
        return ["StarterPlayer", "StarterPlayerScripts", "Client", "Controllers", name]
    if rel.startswith("src/client/"):
        return ["StarterPlayer", "StarterPlayerScripts", "Client", name]
    raise SystemExit("no mapping for " + rel)


def pairs(a, b):
    """Hunks of a -> b as (old, new) strings, each old unique in `a` (grown until it is)."""
    al, bl = a.split("\n"), b.split("\n")
    sm = difflib.SequenceMatcher(None, al, bl, autojunk=False)
    res = []
    spans = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        ctx = 1
        while True:
            lo, hi = max(0, i1 - ctx), min(len(al), i2 + ctx)
            old = "\n".join(al[lo:hi])
            if a.count(old) == 1 or (lo == 0 and hi == len(al)):
                break
            ctx += 1
        jlo, jhi = j1 - (i1 - lo), j2 + (hi - i2)
        # a hunk whose grown context reaches the one before joins it (one pair for both)
        if spans and lo <= spans[-1][1]:
            plo, phi, pjlo, pjhi = spans[-1]
            spans[-1] = (plo, max(phi, hi), pjlo, max(pjhi, jhi))
        else:
            spans.append((lo, hi, jlo, jhi))
    for lo, hi, jlo, jhi in spans:
        res.append(["\n".join(al[lo:hi]), "\n".join(bl[jlo:jhi])])
    # check they apply cleanly in order
    s = a
    for old, new in res:
        if s.count(old) != 1:
            raise SystemExit("hunk not unique after earlier hunks: %r" % old[:80])
        s = s.replace(old, new)
    if s != b:
        raise SystemExit("pairs don't rebuild the file")
    return res


items = []
for rel in FILES:
    now = read(os.path.join(repo, rel))
    bp = os.path.join(base, rel)
    if os.path.exists(bp):
        was = read(bp)
        if was == now:
            continue
        items.append({"rel": rel, "path": studio_path(rel), "pairs": pairs(was, now)})
    else:
        cls = "Script" if rel.endswith(".server.lua") else ("LocalScript" if rel.endswith(".client.lua") else "ModuleScript")
        items.append({"rel": rel, "path": studio_path(rel), "source": now, "className": cls})
with io.open(out, "w", encoding="utf-8", newline="\n") as f:
    json.dump(items, f)
for it in items:
    print(it["rel"], "new" if "source" in it else "%d pairs" % len(it["pairs"]))
