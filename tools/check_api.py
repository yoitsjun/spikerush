#!/usr/bin/env python3
"""Cross-module API check: every Module.member used through a require'd module, a server
registry (reg.Service.member) or the client controller table (mods.Controller.member) must be
defined by that module (as `function Module.member` or `Module.member = ...`)."""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = root / "src"
files = {f.stem.replace(".server", "").replace(".client", ""): f for f in src.rglob("*.lua")}

def members(name):
    f = files.get(name)
    if not f:
        return None
    txt = f.read_text()
    found = set(re.findall(r"^\s*function\s+" + name + r"\.(\w+)", txt, re.M))
    found |= set(re.findall(r"^\s*" + name + r"\.(\w+)\s*=", txt, re.M))
    return found

cache = {}
def defined(name):
    if name not in cache:
        cache[name] = members(name)
    return cache[name]

problems = 0
for f in sorted(src.rglob("*.lua")):
    txt = f.read_text()
    rel = f.relative_to(root)
    # local X = require(...Name) -> X.member
    aliases = {}
    for alias, mod in re.findall(r"local\s+(\w+)\s*=\s*require\([^)]*?(\w+)\)\s*$", txt, re.M):
        aliases[alias] = mod
    # local BS, MS, TS = reg.BallService, reg.MatchService, reg.TeamService
    for lhs, rhs in re.findall(r"local\s+([\w, ]+?)\s*=\s*((?:reg|mods)\.\w+(?:\s*,\s*(?:reg|mods)\.\w+)*)\s*$", txt, re.M):
        names = [n.strip() for n in lhs.split(",")]
        mods_ = [m.strip().split(".")[1] for m in rhs.split(",")]
        for n, m in zip(names, mods_):
            aliases[n] = m
    uses = set()
    for alias, mod in aliases.items():
        for member in re.findall(r"(?<![\w.:])" + re.escape(alias) + r"\.(\w+)", txt):
            uses.add((mod, member))
    for mod, member in re.findall(r"\b(?:reg|mods)\.(\w+)\.(\w+)", txt):
        uses.add((mod, member))
    for mod, member in sorted(uses):
        if mod in ("Config", "Assets"):
            continue
        d = defined(mod)
        if d is None:
            continue
        if member not in d:
            print(f"{rel}: {mod}.{member} is not defined in {mod}")
            problems += 1
print(f"API references checked, {problems} problem(s).")
sys.exit(1 if problems else 0)
