#!/usr/bin/env python3
"""Generate src/shared/Roster.lua: the named preset characters you roll for with V Points.

Every character has a role (WS wing spiker, MB middle blocker, SE setter), a tier, a height,
four stats and possibly an ability:
  * WS: the highest Attack and Jump (up to 210 / 190 at the very top).
  * MB: the tallest, with a big Jump (about 180) and less Attack (about 170).
  * SE: Speed and Defense (160 to 180 at the top), light on Attack and Jump.
Abilities come with the character: S+ wing spikers have Thunder Spiker, Azure Dragon, Feral Leap, Zero Point or Corona
(the S+ middle Ironclad, the S+ setter The Tyrant);
S characters have one of their role's abilities (WS Adrenaline, Rising Sun, Counter Edge, Plunge Spin or Skyward;
MB Iron Wall, Rally Cry or Sunshine; SE Chain Reaction, Vector Set or Turnabout); everyone else has none.

The top characters are hand-set (the owner named YeJun: Thunder, 190 Jump and 210 Attack; he
is the only Thunder Spiker. Dante, Feral Leap, has the top Attack, 222); the rest are generated from role templates scaled by
tier with a fixed seed, so the file is stable and reviewable. Re-run after changing a template:  python3 tools/generate_roster.py
"""
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "shared" / "Roster.lua"

TIERS = ["D-", "D", "D+", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+", "S-", "S", "S+"]
STAT_MIN = 50

# top-of-the-line values per role (S+); lower tiers scale down toward STAT_MIN
TEMPLATES = {
    "WS": {"Attack": 210, "Jump": 190, "Defense": 130, "Speed": 145, "Height": (180, 194)},
    "MB": {"Attack": 172, "Jump": 182, "Defense": 150, "Speed": 118, "Height": (196, 206)},
    "SE": {"Attack": 132, "Jump": 142, "Defense": 178, "Speed": 180, "Height": (170, 184)},
}

NAMES = [
    "Minjae", "Haneul", "Kaito", "Jiho", "Sora", "Dohyun", "Haruki", "Yuna", "Rin", "Taeyang",
    "Aoi", "Jisoo", "Ren", "Eunwoo", "Mio", "Hyunwoo", "Nagi", "Sungmin", "Kaede", "Itsuki",
    "Mirae", "Kenji", "Sena", "Yuto", "Jiwon", "Asahi", "Doyun", "Hikari", "Minseo", "Taeho",
]

# the signature characters, set by hand
FIXED = [
    {"Name": "YeJun", "Role": "WS", "Tier": "S+", "Height": 189, "Attack": 210, "Defense": 124, "Speed": 146, "Jump": 190, "Ability": "Thunder"},
    {"Name": "Seojin", "Role": "WS", "Tier": "S+", "Height": 184, "Attack": 210, "Defense": 128, "Speed": 140, "Jump": 175, "Ability": "Azure"},
    # Feral Leap (the owner: "the highest attack character in the game"): the top Attack of the
    # roster, fast on his feet for the charged run-up, a little less Jump than YeJun
    {"Name": "Dante", "Role": "WS", "Tier": "S+", "Height": 186, "Attack": 222, "Defense": 120, "Speed": 152, "Jump": 184, "Ability": "Feral"},
    # (the owner, 2026-10-16: "buff daon, shoyo, and seora. just some pure stat buffs are enough")
    {"Name": "Shoyo", "Role": "WS", "Tier": "S", "Height": 181, "Attack": 197, "Defense": 124, "Speed": 157, "Jump": 189, "Ability": "Adrenaline"},
    {"Name": "Tetsuo", "Role": "MB", "Tier": "S", "Height": 201, "Attack": 166, "Defense": 158, "Speed": 112, "Jump": 178, "Ability": "IronWall"},
    {"Name": "Seoyeon", "Role": "SE", "Tier": "S", "Height": 176, "Attack": 128, "Defense": 172, "Speed": 178, "Jump": 140, "Ability": "ChainReaction"},
    # the second wave of S abilities (original characters; the owner described the ideas)
    # Ironclad (the owner: an S+ middle blocker with a passive Iron Wall of 3 shields who awakens into
    # a hitter): a tall wall with a hitter's Attack for the awakened spike
    {"Name": "Taesan", "Role": "MB", "Tier": "S+", "Height": 203, "Attack": 186, "Defense": 162, "Speed": 112, "Jump": 182, "Ability": "Ironclad"},
    # Featherfall (the owner: "a setter that works well. a setter that sets high and the ball drops
    # slowly, the longer it drops the harder your spike gets"): quick and steady hands
    {"Name": "Arin", "Role": "SE", "Tier": "S", "Height": 175, "Attack": 128, "Defense": 170, "Speed": 176, "Jump": 140, "Ability": "Featherfall"},
    {"Name": "Ilya", "Role": "SE", "Tier": "S", "Height": 178, "Attack": 130, "Defense": 170, "Speed": 180, "Jump": 142, "Ability": "Vector"},
    {"Name": "Haeri", "Role": "SE", "Tier": "S", "Height": 183, "Attack": 150, "Defense": 160, "Speed": 172, "Jump": 158, "Ability": "Turnabout"},
    # Rising Sun: past an A- at level 0 (a low A before the 2026-10-16 buff); at level 4 (+40 ATK,
    # +36 JMP, +12 DEF, +24 SPD) every stat beats a maxed YeJun (210 / 190 / 124 / 146)
    # (buffed 2026-10-16: +12 Attack, +7 Defense, +10 Speed, +10 Jump)
    {"Name": "Daon", "Role": "WS", "Tier": "S", "Height": 186, "Attack": 188, "Defense": 122, "Speed": 134, "Jump": 170, "Ability": "RisingSun"},
    {"Name": "Joon", "Role": "MB", "Tier": "S", "Height": 202, "Attack": 162, "Defense": 162, "Speed": 110, "Jump": 176, "Ability": "RallyCry"},
    # Counter Edge: lower Attack and Defense at an empty meter; a full one (one hard spike dug)
    # makes her 210 Attack and 200 Defense (+40 / +70) until her next spike releases it
    {"Name": "Ines", "Role": "WS", "Tier": "S", "Height": 184, "Attack": 170, "Defense": 130, "Speed": 138, "Jump": 180, "Ability": "Counter"},
    # the owner's third wave (original characters from the owner's descriptions):
    # a middle blocker "exceptionally tall, but not much else. no ability, just very tall with good
    # stats" (216 cm, the tallest anyone can be: Config.Height.Max). Then "his focus should be good
    # blocks, but not really about the spikes": a trimmed Jump, less Attack, more Defense (block power)
    {"Name": "Mateus", "Role": "MB", "Tier": "S-", "Height": 216, "Attack": 148, "Defense": 156, "Speed": 102, "Jump": 166, "Ability": None},
    # a wing spiker "short but an incredible jump, not higher than yejun's but still very high"
    {"Name": "Junseo", "Role": "WS", "Tier": "S-", "Height": 168, "Attack": 180, "Defense": 110, "Speed": 150, "Jump": 188, "Ability": None},
    # Plunge Spin: "a wingspiker with a blitz spin ability. it sharply angles down"
    {"Name": "Yeonho", "Role": "WS", "Tier": "S", "Height": 185, "Attack": 194, "Defense": 118, "Speed": 140, "Jump": 178, "Ability": "Plunge"},
    # Zero Point (the owner: "S+... an ability focused on perfect contact... a perfect contact
    # spike hits a ??? km/h"): clean hands over raw power, so a little less Attack than YeJun
    {"Name": "Taeho", "Role": "WS", "Tier": "S+", "Height": 187, "Attack": 205, "Defense": 122, "Speed": 146, "Jump": 182, "Ability": "ZeroPoint"},
    # Corona (the owner: a character "based off lucas from the spike"): a high jumper who dives
    # onto the ball, so Jump near the top and a little less Attack (Corona and Sundive add the rest)
    # (the owner, with Haneul: "she is easily the fastest character, and lucas should be second")
    {"Name": "Laith", "Role": "WS", "Tier": "S+", "Height": 183, "Attack": 204, "Defense": 122, "Speed": 192, "Jump": 188, "Ability": "Corona"},
    # Squall (the owner: a spiker "similar to sara seo" who rushes under the ball, hovers to charge
    # and aims her spike; "easily the fastest character"): Speed far above anyone's. Then (the owner:
    # "why does she have 196 atack but only 133 spike kmh and 182 jump but not even 4m"): Attack
    # and Jump up with the other S+ spikers (204, Laith's; 190, the top); then "make her taller":
    # 178 cm (a 4.20 m hitting point), and Updraft lifts her spike jumps for the hover
    {"Name": "Haneul", "Role": "WS", "Tier": "S+", "Height": 178, "Attack": 204, "Defense": 116, "Speed": 230, "Jump": 190, "Ability": "Squall"},
    # Skyward (the owner: "a jump that starts low, but the higher spike point she gets the higher
    # her jump increases... a high max jump, than even yejun. at her peak, maybe 4.7-4.8"): her
    # Jump here is the middle of her climb (Config.Abilities.Skyward moves her hitting point)
    # (buffed 2026-10-16: +8 Attack, +6 Defense, +8 Speed; her Jump stays, Skyward's climb is tuned on it)
    {"Name": "Seora", "Role": "WS", "Tier": "S", "Height": 178, "Attack": 204, "Defense": 124, "Speed": 158, "Jump": 196, "Ability": "Skyward"},
    # The Tyrant (the owner, 2026-10-21: "The Tyrant (S+ Setter)"): the first S+ setter, quicker and
    # steadier than any S setter, with a little more Attack and Jump for his own jump serve
    {"Name": "Dohwan", "Role": "SE", "Tier": "S+", "Height": 180, "Attack": 140, "Defense": 182, "Speed": 188, "Jump": 150, "Ability": "Tyrant"},
    # Sunshine (the owner, 2026-10-21: an S middle blocker, "170 Attack 150 Jump 190 Defense 180
    # Speed"): a digging middle, shorter than the rest of them
    {"Name": "Haesol", "Role": "MB", "Tier": "S", "Height": 191, "Attack": 170, "Defense": 190, "Speed": 180, "Jump": 150, "Ability": "Sunshine"},
]

# free for everyone: a D-tier character in each role
STARTERS = [("Riku", "WS", "D"), ("Daichi", "MB", "D"), ("Hana", "SE", "D")]

# generated characters: (role, tier) slots
SLOTS = []
for role in ("WS", "MB", "SE"):
    SLOTS += [(role, "A+"), (role, "A-"), (role, "B+"), (role, "B-"), (role, "C+"), (role, "C-"), (role, "D+")]


# the filler wave (the owner, 2026-10-16: "add a bunch of more filler characters. maybe like 50 more?
# keep the odds the same but just add a lot more a, a- b, b- and so on"): 17 a role, A+ down to D+,
# filling A, B and C too (Config.Spins.TierOdds gives each tier its chance; more characters only
# share it). Their own names (none ever used before, the retired ones' included) and their own
# seed, drawn after the first wave, so the first wave stays exactly as it was.
EXTRA_NAMES = [
    "Seungwoo", "Hyejin", "Daeho", "Soyeon", "Chanwoo", "Woojin", "Yerin", "Gyuri", "Siwoo", "Juwon",
    "Hayeon", "Minho", "Jaehyun", "Nari", "Bomin", "Chaewon", "Donghae", "Eunbi", "Ganghyun", "Haein",
    "Insoo", "Jinwoo", "Kyungmin", "Seulgi", "Taemin", "Yoonseo", "Hayato", "Ryota", "Akari", "Takumi",
    "Kaori", "Shion", "Ryusei", "Natsuki", "Kotaro", "Hinata", "Ayame", "Daiki", "Emiko", "Fumito",
    "Genji", "Hotaru", "Isamu", "Kazuki", "Makoto", "Noa", "Rei", "Sakura", "Tsubasa", "Yamato",
    "Mateo", "Luca", "Noah", "Elias", "Marco", "Nico", "Leo", "Zara", "Iker", "Theo",
]
EXTRA_PER_ROLE = [("A+", 1), ("A", 3), ("A-", 2), ("B+", 1), ("B", 3), ("B-", 2), ("C+", 1), ("C", 2), ("C-", 1), ("D+", 1)]
EXTRA_SLOTS = []
for role in ("WS", "MB", "SE"):
    for tier, n in EXTRA_PER_ROLE:
        EXTRA_SLOTS += [(role, tier)] * n


def tier_k(tier):
    i = TIERS.index(tier)
    return 0.42 + 0.58 * (i / (len(TIERS) - 1)) ** 1.1


def make(rnd, name, role, tier):
    t = TEMPLATES[role]
    k = tier_k(tier)
    c = {"Name": name, "Role": role, "Tier": tier}
    lo, hi = t["Height"]
    c["Height"] = rnd.randint(lo, hi)
    for stat in ("Attack", "Defense", "Speed", "Jump"):
        v = STAT_MIN + (t[stat] - STAT_MIN) * k + rnd.uniform(-6, 6)
        c[stat] = int(round(min(max(v, STAT_MIN), t[stat])))
    c["Ability"] = None
    return c


# Renamed characters keep their old id: saved profiles (owned, equipped) are keyed by it.
KEEP_ID = {"Taeho": "taeha"}  # renamed from Taeha on 2026-10-10


def slug(name):
    return KEEP_ID.get(name, name.lower())


def lua_entry(c):
    ability = '"%s"' % c["Ability"] if c.get("Ability") else "nil"
    return (
        '\t{ Id = "%s", Name = "%s", Role = "%s", Tier = "%s", Height = %d, Attack = %d, Defense = %d, Speed = %d, Jump = %d, Ability = %s },'
        % (slug(c["Name"]), c["Name"], c["Role"], c["Tier"], c["Height"], c["Attack"], c["Defense"], c["Speed"], c["Jump"], ability)
    )


def main():
    rnd = random.Random(20260925)
    names = NAMES[:]
    rnd.shuffle(names)
    chars = [dict(c) for c in FIXED]
    for name, role, tier in STARTERS:
        chars.append(make(rnd, name, role, tier))
    for role, tier in SLOTS:
        chars.append(make(rnd, names.pop(), role, tier))
    # the filler wave, from its own stream
    taken = {c["Name"] for c in chars} | set(NAMES) | {"Hayun", "Gaeul", "Akira", "Taeha"}
    extra = [n for n in EXTRA_NAMES if n not in taken]
    rnd2 = random.Random(20261016)
    rnd2.shuffle(extra)
    assert len(extra) >= len(EXTRA_SLOTS), "not enough filler names"
    for role, tier in EXTRA_SLOTS:
        chars.append(make(rnd2, extra.pop(), role, tier))
    order = {t: i for i, t in enumerate(TIERS)}
    chars.sort(key=lambda c: (-order[c["Tier"]], ["WS", "MB", "SE"].index(c["Role"]), c["Name"]))

    lines = [
        "-- GENERATED by tools/generate_roster.py: edit the templates there and re-run.",
        "-- The named preset characters you roll for with V Points. Each has a role (WS wing",
        "-- spiker, MB middle blocker, SE setter), a tier, a height (cm), four stats and maybe an",
        "-- ability (Config.Abilities). Starters are owned by everyone.",
        "",
        "local Roster = {",
    ]
    lines += [lua_entry(c) for c in chars]
    lines += [
        "}",
        "",
        "Roster.Starters = { %s }" % ", ".join('"%s"' % slug(n) for n, _, _ in STARTERS),
        "",
        "local byId = {}",
        "for _, c in ipairs(Roster) do",
        "\tbyId[c.Id] = c",
        "end",
        "",
        "function Roster.get(id)",
        "\treturn byId[id or \"\"]",
        "end",
        "",
        "return Roster",
        "",
    ]
    OUT.write_text("\n".join(lines))
    print("wrote %d characters to %s" % (len(chars), OUT))
    for c in chars:
        print("  %-8s %-3s %-2s %3d cm  ATK %3d DEF %3d SPD %3d JMP %3d  %s" % (c["Name"], c["Tier"], c["Role"], c["Height"], c["Attack"], c["Defense"], c["Speed"], c["Jump"], c["Ability"] or "-"))


if __name__ == "__main__":
    main()
