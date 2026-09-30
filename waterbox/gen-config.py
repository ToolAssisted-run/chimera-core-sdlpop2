#!/usr/bin/env python3
"""Writes waterbox.config: what the frontend is told about this core.

The settings that are SDLPoP2's own gameplay options come from settings.inc,
the same table the driver writes SDLPoP2.ini's form from; the game's files and
their hashes from the same list the driver checks at Init (pop2-driver.c's
k_files); the buttons from the driver's wire order (pop2-driver.h).

usage: gen-config.py [<out>]   (default: waterbox/waterbox.config)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def ini_settings():
    text = open(os.path.join(HERE, "settings.inc")).read()
    out = []
    for m in re.finditer(r'POP2_SETTING\((\w+), (BOOL|INT), "(\w+)", (-?\d+), (-?\d+), (-?\d+), "([^"]*)",\s*"([^"]*)"\)', text):
        name, kind, _section, dflt, lo, hi, display, desc = m.groups()
        s = {"name": name, "display": display}
        if kind == "BOOL":
            s.update({"type": "bool", "default": dflt == "1"})
        else:
            s.update({"type": "int", "default": int(dflt), "min": int(lo), "max": int(hi)})
        s["description"] = desc
        out.append(s)
    return out


# the releases, as the version setting names them, the driver's R_* mask bits,
# and what the System box calls them - 1.1 first: the default, and the release
# every project played before there was a choice
RELEASES = [("1.1", 1, "Prince of Persia 2 1.1 (Collection CD)"),
            ("1.0", 2, "Prince of Persia 2 1.0"),
            ("ir", 4, "Prince of Persia 2 initial release")]
MASKS = {"R_11": 1, "R_10": 2, "R_IR": 4, "R_1X": 3, "R_ALL": 7}


def game_files():
    """(name, size, sha1, roland, releases): the files pop2-driver.c checks at
    Init - its k_files, always, and its k_roland_files, when the music is the
    MT-32's - each with the releases (version setting values) it belongs to."""
    text = open(os.path.join(HERE, "pop2-driver.c")).read()
    split = text.index("k_roland_files[] = {")
    out = []
    for m in re.finditer(r'\{ "([A-Z0-9_]+\.(?:DAT|EXE|DEF|ROM))", (\d+), "([0-9A-F]{40})", (R_\w+) \}', text):
        mask = MASKS[m.group(4)]
        out.append((m.group(1), int(m.group(2)), m.group(3), m.start() > split, [v for v, bit, _ in RELEASES if mask & bit]))
    return out


def buttons():
    """The input.buttons names, in the driver's enum order (pop2-driver.h)."""
    text = open(os.path.join(HERE, "pop2-driver.h")).read()
    enum = text[text.index("enum Pop2Button"):text.index("POP2_BTN_COUNT")]
    enum = re.sub(r"/\*.*?\*/", "", enum, flags=re.S)
    syms = [s for s in re.findall(r"^\s*POP2_BTN_(\w+)(?:\s*=[^,]*)?,", enum, re.M) if s != "CHEAT_FIRST"]
    special = {"UP": "P1 Up", "DOWN": "P1 Down", "LEFT": "P1 Left", "RIGHT": "P1 Right", "SHIFT": "P1 Shift",
               "CTRL": "P1 Ctrl", "SOUND_ON_OFF": "Sound On/Off", "MUSIC_ON_OFF": "Music On/Off"}
    # the rest: the symbol's words, capitalised (CHEAT_ADD_MAX_HIT_POINT -> Cheat Add Max Hit Point)
    return [special.get(s) or " ".join(w.capitalize() for w in s.split("_")) for s in syms]


WHAT = {
    "PRINCE.EXE": "the program, whose tables (the characters' animations, the rooms' drawing, the text) SDLPoP2 reads",
    "SEQUENCE.DAT": "the animation sequences",
    "PRINCE.DAT": "the pictures and texts every level shares, the levels themselves and the palettes",
    "KID.DAT": "the prince",
    "GUARD.DAT": "the guards",
    "HEAD.DAT": "the flying heads",
    "SKELETON.DAT": "the skeletons",
    "BIRD.DAT": "the bird-headed guards",
    "FLAME.DAT": "the flames",
    "JINNEE.DAT": "the jinnee",
    "ROOFTOPS.DAT": "the rooftop levels' walls and floors",
    "DESERT.DAT": "the desert level's walls and floors",
    "CAVERNS.DAT": "the caverns' walls and floors",
    "RUINS.DAT": "the ruins' walls and floors",
    "TEMPLE.DAT": "the temple's walls and floors",
    "FINAL.DAT": "the final level's walls and floors",
    "TRANS.DAT": "the transition scenes",
    "NIS.DAT": "the story scenes",
    "NIS3VC.DAT": "the story scenes' pictures",
    "DIGISND.DAT": "the Sound Blaster's digitized sounds",
    "MIDISND.DAT": "the FM music",
    "IBMSND.DAT": "the PC speaker's sounds",
    "NISDIGI.DAT": "the story scenes' digitized sounds",
    "NISMIDI.DAT": "the story scenes' FM music",
    "NISIBM.DAT": "the story scenes' PC speaker sounds",
    "PRESETS.DEF": "the FM instruments (the DOS setup copies the Sound Blaster Pro's here; on the install disks it is SNDDRVRS\\PRESET33.DEF). Needed whatever plays the music: the story scenes' timing is the FM driver's",
    "PRESET40.DEF": "the Roland MT-32's timbres, a MIDI piece the start-up sends the MT-32 and waits for (the DOS setup copies it to PRESETS.DEF for that device; it is SNDDRVRS\\PRESET40.DEF on the CD and the install disks)",
    "MT32_CONTROL.ROM": "no file of the game's: the Roland MT-32's control ROM, v1.07, dumped from a unit of the first generation",
    "MT32_PCM.ROM": "no file of the game's: the Roland MT-32's PCM ROM, the one every MT-32 has",
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "waterbox.config")
    firmware = []
    everyone = [v for v, _, _ in RELEASES]
    names = {"1.1": "1.1", "1.0": "1.0", "ir": "initial release"}
    for name, size, sha1, roland, releases in game_files():
        which = "/".join(names[v] for v in reversed(releases)) if releases != everyone else ""
        if name.endswith(".ROM"):
            display = "Roland MT-32 %s ROM" % ("control" if "CONTROL" in name else "PCM")
            desc = "%s: %s. Yours to supply, when the music is the Roland MT-32's - the package carries none of it. Another MT-32 ROM Munt knows may take its place (the project pins its hash)." % (name, WHAT[name])
        else:
            display = "Prince of Persia 2 %s%s" % (which + " " if which else "", name)
            desc = "%s of Prince of Persia 2 %s(DOS): %s. Yours to supply%s - the package carries none of the game's data. A file of your own (a modified one) may take its place: the project pins its hash.%s" % (
                name, which + " " if which else "", WHAT[name], ", when the music is the Roland MT-32's" if roland else "",
                " The uncracked program's hash; a cracked copy plays the same (only the copy protection's code differs, which SDLPoP2 does not run)." if name == "PRINCE.EXE" and releases != ["1.1"] else "")
        decl = {"id": name, "display": display, "description": desc, "size": size, "sha1": sha1, "name": name}
        conds = []
        if releases != everyone:
            conds.append({"setting": "version", "in": releases})
        if roland:
            conds.append({"setting": "music", "in": ["roland"]})
        if conds:
            decl["requiredWhen"] = conds[0] if len(conds) == 1 else {"all": conds}
        firmware.append(decl)

    cfg = {
        "coreName": "SDLPoP2",
        "kind": "game",
        # the releases are the package's machines: the new-project wizard offers
        # them in its System box, as it offers an emulator's systems
        "machineSetting": "version",
        "machines": [{"id": "PrinceOfPersia2", "label": label, "when": [v]} for v, _, label in RELEASES],
        "author": "Sergio Martin and the SDLPoP2 contributors, from Jordan Mechner's Prince of Persia 2; chimera port by Sergio Martin",
        "url": "https://github.com/ToolAssisted-run/chimera-core-sdlpop2",
        "deterministic": True,
        "memoryLayoutMiB": [64, 8, 8, 8, 64],
        "_memoryLayoutMiB_note": "sbrk, sealed, invisible, plain, mmap. The game loads its sound files whole; the program shell's and the story scenes' stacks are mmap'd (MAP_STACK).",
        "video": {
            "_comment": "The DOS game's 320x200 VGA screen (mode 13h), shown on a 4:3 monitor.",
            "width": 320,
            "height": 200,
            "virtualWidth": 320,
            "virtualHeight": 240,
            "vsyncNumerator": 3146875,
            "vsyncDenominator": 269400,
            "_vsync_note": "A frame is one step of the game (docs/game-cores.md): while playing, the VGA frames (70.086 Hz) up to the next game tick, where the controls are read - 5 to 7 of them, 1/12 s walking; on the title, in the story scenes, the menus and the pause, one VGA frame, since the program reads its keys every frame there. GetVsyncNumerator/Denominator report the step just run; 3146875/269400 is six frames.",
            "getBgra": "GetVideoBgra",
        },
        "audio": {
            "_comment": "SDLPoP2's sound (the Sound Blaster Pro's digitized sounds with the music on a Roland MT-32 or the card's FM chip, or the PC speaker alone), rendered at 44100 Hz for exactly the time each step covers: the card's and the speaker's mono on both sides, the MT-32's in stereo.",
            "rate": 44100,
            "samplesPerFrame": 44200,
            "channels": 2,
            "get": "GetAudio",
        },
        "lag": {"inputWasRead": "InputWasRead"},
        "input": {
            "name": "Prince of Persia 2",
            "_comment": "The DOS game's keyboard, a button for each key the game reads in play. P1: the arrows, Shift (grab, careful step, pick up, drink; it also chooses the copy protection's symbol, as Enter does) and Ctrl (the sword; the spirit's spell). The game's commands: Pause (Esc) and Show Time (Space) - either also skips a story scene - Restart Level (Alt+A), Restart Game (Alt+R), Next Level (Alt+N), Sound On/Off (Alt+S), Music On/Off (Alt+M), Version (Alt+V). With the cheats setting on, the cheats: the DOS game's (Lose Hit Point Shift+K, Opponent Hit Point g, Kill Room k, Spirit Leaves Shift+S, More Time and Less Time keypad + and -, Flip Screen Shift+I, Show Room Shift+R, Add Max Hit Point Shift+T, Feather Fall Shift+W, Revive r, Demo Player F3) and SDLPoP2's own (God Mode Shift+G, Leave Body h, Leave Body Flame b, Sword z, Look Left/Right/Up/Down Alt+arrows, Teleport t, Fly A held). Left out: the game's saved games and its menus (Alt+G, Alt+L, Alt+O, Alt+H, Enter, Tab), Joystick Mode and Keyboard Mode (Alt+J, Alt+K), which mean nothing to a movie, and the letter keys; the hall of fame's name is the player_name setting, entered by the game itself. A key pressed is typed once; there is no key repeat.",
            "buttons": buttons(),
        },
        "settings": [
            {
                "name": "version",
                "display": "Version",
                "type": "enum",
                "options": [v for v, _, _ in RELEASES],
                "default": "1.1",
                "description": "The DOS release played, whose files the project brings (SDLPoP2's docs/VERSIONS.md): 1.1, the Prince of Persia Collection CD's, which SDLPoP2 is rebuilt from; 1.0; or the initial release (ir). They differ in movement near walls and gates, the guards, the spirit, levels 2, 5, 8 and 14, the timers and random numbers, and a few story scenes. 1.0 and 1.1 have the same data files and differ in PRINCE.EXE; the initial release's files are its own (twelve of them differ), and its cheat word is makinit.",
            },
            {
                "name": "music",
                "display": "Sound Device",
                "type": "enum",
                "options": ["roland", "fm", "speaker"],
                "default": "roland",
                "description": "What plays the sound: the music on a Roland MT-32 on an MPU-401 (roland, the default), the setup's \"Roland MT-32/LAPC-1/CM-32L\", or on the Sound Blaster Pro's FM chip (fm), as the original setup chose - either way with the Sound Blaster's digitized sounds; or the PC speaker alone (speaker), the game's own speaker player and its sounds (IBMSND.DAT, NISIBM.DAT). The game knows which: with the speaker it answers \"Music Unavailable\", plays no ambient music and waits on a death or a level's end as long as the speaker's sounds last, as the original on that machine did (the story scenes' timing is still the card's). The MT-32 needs the setup's PRESET40.DEF and an MT-32's two ROMs (v1.07), which the project brings as firmware; its game starts 9.35 s later, as the original did, while the start-up sends the MT-32 its timbres - so a movie plays on the music device it was made with.",
            },
            {
                "name": "random_seed",
                "display": "Random seed",
                "type": "int",
                "default": 0,
                "min": 0,
                "max": 2147483647,
                "description": "The seed of the game's random number generator at start (the DOS program took it from the clock). A movie records the number it ran with.",
            },
            {
                "name": "player_name",
                "display": "Player Name (Hall of Fame)",
                "type": "string",
                "default": "Chimera",
                "description": "The name a won game enters in the hall of fame, when its time earns a place there - typed into the game's own editor as the keys would have typed it (the characters the font has, as many as the box holds, up to 24). There are no letter keys: the game enters it by itself.",
            },
            {
                "name": "cheats",
                "display": "Enable Cheats",
                "type": "bool",
                "default": False,
                "description": "Start the program with the cheat word on its command line (yippeeyahoo; the initial release's makinit), as the original allowed: the cheats' buttons exist only with this on (the DOS game's cheats and SDLPoP2's own), and Next Level (Alt+N) reaches any level.",
            },
            {
                "name": "igt_from_level_1",
                "display": "IGT From Level 1",
                "type": "bool",
                "default": True,
                "description": "The in-game time (IGT, the project's GameTime) counts from the very beginning of level 1. The game's own clock stays stopped until the first story scene after level 4, so without this the levels before it count nothing; with it their ticks of play are added, counted as the clock counts them (while the prince lives). Changes nothing in the game.",
            },
        ] + ini_settings(),
        "firmware": firmware,
    }
    with open(out, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
