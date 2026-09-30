#!/usr/bin/env python3
"""Writes a .chimeraProject for run-frontend.sh, by hand, as the wizard would.

A Prince of Persia 2 project is its settings, its firmware pins (every game
file, pinned by SHA-1) and an input log in the panel's own button names, in the
engine's two groups - and, optionally, a saved game in the "savegame" slot.
The movie, if given, is one of the gate's (gate-harness.h's letters, one line a
step, # comments), turned into Chimera's log rows.

usage: make-project.py <package> <out.chimeraProject> <frames> [--movie <route>]
                       [--settings <json>] [--file <slot>=<path>]... [--log-out <path>]
--log-out also writes the rows alone, as chimera-run takes a movie.
"""
import argparse
import hashlib
import json
import os
import zipfile


def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


# the harness's letters (gate-harness.h gate_key_index), by button name
LETTERS = {
    "U": "P1 Up", "D": "P1 Down", "L": "P1 Left", "R": "P1 Right", "S": "P1 Shift", "C": "P1 Ctrl",
    "X": "Pause", "_": "Show Time",
    "a": "Restart Level", "r": "Restart Game", "n": "Next Level", "u": "Sound On/Off", "m": "Music On/Off", "v": "Version",
    "1": "Cheat Lose Hit Point", "2": "Cheat Opponent Hit Point", "3": "Cheat Kill Room", "4": "Cheat Spirit Leaves",
    "+": "Cheat More Time", "-": "Cheat Less Time", "I": "Cheat Flip Screen", "O": "Cheat Show Room",
    "M": "Cheat Add Max Hit Point", "W": "Cheat Feather Fall", "V": "Cheat Revive", "P": "Cheat Demo Player",
    "G": "Cheat God Mode", "B": "Cheat Leave Body", "F": "Cheat Leave Body Flame", "Z": "Cheat Sword",
    "<": "Cheat Look Left", ">": "Cheat Look Right", "^": "Cheat Look Up", "~": "Cheat Look Down",
    "Q": "Cheat Teleport", "A": "Cheat Fly",
}


def row(held, keys, p1):
    # the log's two groups, as the engine orders them: the keys first (player
    # 0: the commands, the cheats that are active), then P1 (the
    # arrows, Shift, Ctrl)
    names = {LETTERS[c] for c in held if c in LETTERS}
    return ("|" + "".join("x" if k in names else "." for k in keys) + "|"
            + "".join(c if n in names else "." for c, n in zip("UDLRSC", p1)) + "|")


def rows_from(movie, frames, keys, p1):
    rows = []
    if movie:
        for line in open(movie):
            if line.startswith("#"):
                continue
            rows.append(row(line.rstrip("\n"), keys, p1))
    while len(rows) < frames:
        rows.append(row("", keys, p1))
    return rows[:frames]


def holds(cond, settings, slots):
    if cond is None:
        return True
    if "not" in cond:
        return not holds(cond["not"], settings, slots)
    if "all" in cond:
        return all(holds(c, settings, slots) for c in cond["all"])
    if "any" in cond:
        return any(holds(c, settings, slots) for c in cond["any"])
    if "slot" in cond:
        return cond["slot"] in slots
    if "setting" in cond:
        v = settings.get(cond["setting"])
        return v in cond["in"] if "in" in cond else v == cond.get("is")
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("package")
    ap.add_argument("out")
    ap.add_argument("frames", type=int)
    ap.add_argument("--movie")
    ap.add_argument("--settings", default="{}")
    ap.add_argument("--file", action="append", default=[])
    ap.add_argument("--log-out")
    a = ap.parse_args()

    cfg = json.loads(zipfile.ZipFile(a.package).read("waterbox.config"))
    settings = {d["name"]: d["default"] for d in cfg["settings"]}
    settings.update(json.loads(a.settings))
    # the cheats' buttons are active only with the cheats setting on
    # (IsButtonActive), and the log has only the active ones
    buttons = [b for b in cfg["input"]["buttons"] if settings.get("cheats") or not b.startswith("Cheat ")]
    keys = [b for b in buttons if not b.startswith("P1 ")]
    p1 = [b for b in buttons if b.startswith("P1 ")]
    assert set(buttons) <= set(LETTERS.values()), set(buttons) - set(LETTERS.values())
    rows = rows_from(a.movie, a.frames, keys, p1)
    if a.log_out:
        open(a.log_out, "w").write("\n".join(rows) + "\n")
    log = "[Input]\nLogKey:#" + "|".join(keys) + "|#" + "|".join(p1) + "|\n" + "\n".join(rows) + "\n[/Input]\n"

    files = []
    for spec in a.file:
        slot, path = spec.split("=", 1)
        files.append({"name": os.path.basename(path), "sha1": sha1(path), "slot": slot})
    slots = {f["slot"] for f in files}
    firmware = [{"id": d["id"], "sha1": d["sha1"]} for d in cfg["firmware"]
                if holds(d.get("requiredWhen"), settings, slots)]

    project = {
        "id": "sdlpop2-frontend-check",
        "title": "Prince of Persia 2 through Chimera",
        "description": "written by waterbox/tests/make-project.py",
        "core": {"name": cfg["coreName"], "version": cfg["version"], "sha1": sha1(a.package)},
        "rerecords": 0,
        "files": files,
        "settings": settings,
        "firmware": firmware,
        "coreCache": [],
        "input": log,
        "markers": [],
        "branches": [],
        "headers": {
            "MovieVersion": "Chimera Project File v1.1",
            "Platform": cfg["systemId"],
            "SHA1": files[0]["sha1"] if files else "",
            "LastInputFrame": str(a.frames - 1),
            "VsyncNumerator": str(cfg["video"]["vsyncNumerator"]),
            "VsyncDenominator": str(cfg["video"]["vsyncDenominator"]),
        },
    }
    with open(a.out, "w") as f:
        json.dump(project, f, indent="\t")


if __name__ == "__main__":
    main()
