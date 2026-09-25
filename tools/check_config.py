#!/usr/bin/env python3
"""Checks that every Config.<Section>.<Key> used in the code (directly or through a local
alias such as `local H = Config.Hits`) is actually defined in src/shared/Config.lua."""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
cfg = (root / "src/shared/Config.lua").read_text()
sections = {}
for m in re.finditer(r"^Config\.(\w+)\s*=\s*\{\s*$(.*?)^\}", cfg, re.M | re.S):
    sections[m.group(1)] = set(re.findall(r"^\t(\w+)\s*=", m.group(2), re.M))
defined = set(re.findall(r"^Config\.(\w+)\s*=", cfg, re.M))
problems = 0
for f in sorted((root / "src").rglob("*.lua")):
    if f.name == "Config.lua":
        continue
    txt = f.read_text()
    rel = f.relative_to(root)
    alias = dict(re.findall(r"local\s+(\w+)\s*=\s*Config\.(\w+)\s*$", txt, re.M))
    for sec in set(re.findall(r"\bConfig\.(\w+)", txt)):
        if sec not in defined:
            print(f"{rel}: Config.{sec} is not defined"); problems += 1
    for sec, key in set(re.findall(r"\bConfig\.(\w+)\.(\w+)", txt)):
        if sec in sections and sec not in ("Teams", "Styles") and key not in sections[sec]:
            print(f"{rel}: Config.{sec}.{key} is not defined"); problems += 1
    for a, sec in alias.items():
        if sec not in sections or sec in ("Teams", "Styles"):
            continue
        for key in set(re.findall(r"(?<![\w.])" + a + r"\.(\w+)", txt)):
            if key not in sections[sec]:
                print(f"{rel}: {a}.{key} (Config.{sec}.{key}) is not defined"); problems += 1
print(f"Config references checked, {problems} problem(s).")
sys.exit(1 if problems else 0)
