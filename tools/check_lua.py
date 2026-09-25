#!/usr/bin/env python3
"""Static checks for the Spike Rush Luau sources.

The code is written in a Lua 5.1/5.3-compatible subset of Luau so it can be parsed by
`texluac` (LuaTeX's Lua 5.3 compiler). For every file this script:
  1. syntax-checks it,
  2. lists every global read/write from the bytecode and flags anything that is not a
     known Roblox/Luau global (catches typos and missing `local`s),
  3. flags any global *assignment* (almost always a bug).
Also flags Luau-only syntax that would slip past a human review but break the checker.
"""
import re
import subprocess
import sys
from pathlib import Path

ALLOWED = {
    # Roblox globals
    "game", "workspace", "script", "Instance", "Vector3", "Vector2", "CFrame", "Color3",
    "UDim", "UDim2", "Enum", "task", "typeof", "TweenInfo", "NumberSequence",
    "NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint", "NumberRange",
    "Ray", "RaycastParams", "OverlapParams", "BrickColor", "Random", "tick", "time",
    "Rect", "PhysicalProperties", "Region3", "Font", "DateTime", "shared", "Axes", "Faces",
    # Lua/Luau standard library
    "math", "string", "table", "pairs", "ipairs", "next", "print", "warn", "error",
    "require", "pcall", "xpcall", "select", "tostring", "tonumber", "type",
    "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "unpack", "assert",
    "os", "debug", "coroutine", "utf8", "bit32", "_G",
}

root = Path(__file__).resolve().parent.parent
files = sorted(list((root / "src").rglob("*.lua")))
problems = 0

for f in files:
    rel = f.relative_to(root)
    text = f.read_text(encoding="utf-8")
    # Luau-only constructs we deliberately avoid
    code_only = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    code_only = re.sub(r"--[^\n]*", "", code_only)
    code_only = re.sub(r'"(?:\\.|[^"\\])*"', '""', code_only)
    code_only = re.sub(r"'(?:\\.|[^'\\])*'", "''", code_only)
    for pat, why in [
        (r"[+\-*/]=", "compound assignment"),
        (r"\bcontinue\b", "continue"),
        (r"`", "string interpolation"),
    ]:
        for m in re.finditer(pat, code_only):
            line = code_only[: m.start()].count("\n") + 1
            print(f"{rel}:{line}: Luau-only syntax ({why})")
            problems += 1

    res = subprocess.run(["texluac", "-p", "-l", str(f)], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"{rel}: SYNTAX ERROR\n{res.stderr.strip()}")
        problems += 1
        continue
    for line in res.stdout.splitlines():
        m = re.search(r"\[(\d+)\]\s+(GETTABUP|SETTABUP)\s.*_ENV \"([^\"]+)\"", line)
        if not m:
            continue
        lineno, op, name = m.group(1), m.group(2), m.group(3)
        if op == "SETTABUP":
            print(f"{rel}:{lineno}: assigns global '{name}'")
            problems += 1
        elif name not in ALLOWED:
            print(f"{rel}:{lineno}: unknown global '{name}'")
            problems += 1

print(f"\nChecked {len(files)} files, {problems} problem(s).")
sys.exit(1 if problems else 0)
