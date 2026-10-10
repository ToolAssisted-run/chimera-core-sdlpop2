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
    "PRINCE.EXE": "the program. SDLPoP2 reads its tables (the characters' animations, how the rooms are drawn and the text)",
    "SEQUENCE.DAT": "the animation sequences",
    "PRINCE.DAT": "the pictures and texts that all levels share, the levels themselves and the palettes",
    "KID.DAT": "the prince",
    "GUARD.DAT": "the guards",
    "HEAD.DAT": "the flying heads",
    "SKELETON.DAT": "the skeletons",
    "BIRD.DAT": "the bird-headed guards",
    "FLAME.DAT": "the flames",
    "JINNEE.DAT": "the jinnee",
    "ROOFTOPS.DAT": "the walls and floors of the rooftop levels",
    "DESERT.DAT": "the walls and floors of the desert level",
    "CAVERNS.DAT": "the walls and floors of the caverns",
    "RUINS.DAT": "the walls and floors of the ruins",
    "TEMPLE.DAT": "the walls and floors of the temple",
    "FINAL.DAT": "the walls and floors of the final level",
    "TRANS.DAT": "the transition scenes",
    "NIS.DAT": "the story scenes",
    "NIS3VC.DAT": "the pictures of the story scenes",
    "DIGISND.DAT": "the digitized sounds for the Sound Blaster",
    "MIDISND.DAT": "the FM music",
    "IBMSND.DAT": "the sounds for the PC speaker",
    "NISDIGI.DAT": "the digitized sounds of the story scenes",
    "NISMIDI.DAT": "the FM music of the story scenes",
    "NISIBM.DAT": "the PC speaker sounds of the story scenes",
    "PRESETS.DEF": "the FM instruments. The DOS setup program copies the Sound Blaster Pro's instruments to this file, and on the install disks it is SNDDRVRS\\PRESET33.DEF. It is needed whatever plays the music, because the timing of the story scenes comes from the FM driver",
    "PRESET40.DEF": "the instrument sounds (timbres) for the Roland MT-32. It is a piece of MIDI data that the game sends to the MT-32 when it starts, and the game waits until that is done. The DOS setup program copies it to PRESETS.DEF for that device, and on the CD and the install disks it is SNDDRVRS\\PRESET40.DEF",
    "MT32_CONTROL.ROM": "the control ROM of the Roland MT-32, version 1.07, copied from a first-generation unit",
    "MT32_PCM.ROM": "the PCM ROM of the Roland MT-32, which is the same in every MT-32",
}


# ---- what the controls and the system are called ----
# The frontend keeps no table of these: a core says what its own are called.
# MNEMONICS is the letter each button writes into a movie's text and heads its
# input column with, by the button's name - whole, or without its player ("P2
# Up" is found under "Up"), so one line serves every pad. AXIS_HEADERS is the
# short header of each axis's column. (An entry is read by position: a letter
# may change and no movie made before it is harmed.)
MNEMONICS = {
    "Up": "U", "Down": "D", "Left": "L", "Right": "R", "Shift": "^", "Ctrl": "c", "Pause": "p",
    "Show Time": "t", "Restart Level": "a", "Restart Game": "r", "Next Level": "n",
    "Sound On/Off": "s", "Music On/Off": "m", "Version": "v", "Cheat Lose Hit Point": "Y",
    "Cheat Opponent Hit Point": "O", "Cheat Kill Room": "K", "Cheat Spirit Leaves": "S",
    "Cheat More Time": "+", "Cheat Less Time": "-", "Cheat Flip Screen": "I",
    "Cheat Show Room": "?", "Cheat Add Max Hit Point": "M", "Cheat Feather Fall": "W",
    "Cheat Revive": "V", "Cheat Demo Player": "P", "Cheat God Mode": "G", "Cheat Leave Body": "B",
    "Cheat Leave Body Flame": "F", "Cheat Sword": "Z", "Cheat Look Left": "4",
    "Cheat Look Right": "6", "Cheat Look Up": "8", "Cheat Look Down": "2", "Cheat Teleport": "T",
    "Cheat Fly": "A",
}
SYSTEM_NAMES = {
    "PrinceOfPersia2": "Prince of Persia 2",
}


def _bare(name):
    """A control's name without its player: "P2 Up" -> "Up"."""
    head, _, rest = name.partition(" ")
    return rest if rest and head[:1] == "P" and head[1:].isdigit() else name


def mnemonics_for(buttons):
    """The "mnemonics" of an input declaration: a letter for every one of its
    buttons, and for nothing else. A button nobody gave a letter stops the
    build - the engine would give it its rule's guess, and two columns of one
    pad would share a letter with nobody having decided it."""
    out = {}
    for b in buttons:
        key = b if b in MNEMONICS else _bare(b)
        if key not in MNEMONICS:
            raise SystemExit("no mnemonic for the button %r (MNEMONICS in %s)" % (b, __file__))
        out[key] = MNEMONICS[key]
    return out


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "waterbox.config")
    firmware = []
    everyone = [v for v, _, _ in RELEASES]
    names = {"1.1": "1.1", "1.0": "1.0", "ir": "initial release"}
    for name, size, sha1, roland, releases in game_files():
        which = "/".join(names[v] for v in reversed(releases)) if releases != everyone else ""
        if name.endswith(".ROM"):
            display = "Roland MT-32 %s ROM" % ("control" if "CONTROL" in name else "PCM")
            desc = "%s is not one of the game's files. It is %s. You have to supply it when the music is played by the Roland MT-32. The package contains no ROM. Another MT-32 ROM that Munt (the MT-32 emulator used here) knows can be used instead, and the project records exactly which file it was." % (name, WHAT[name])
        else:
            display = "Prince of Persia 2 %s%s" % (which + " " if which else "", name)
            desc = "%s of Prince of Persia 2 %s(DOS): %s. You have to supply it%s. The package contains none of the game's data. A modified file of your own can be used instead, and the project records exactly which file it was.%s" % (
                name, which + " " if which else "", WHAT[name], " when the music is played by the Roland MT-32" if roland else "",
                " The file expected here is the program without a crack. A cracked copy plays the same, because only the copy protection's code differs and SDLPoP2 does not run that code." if name == "PRINCE.EXE" and releases != ["1.1"] else "")
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
        "systemNames": SYSTEM_NAMES,
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
            "mnemonics": mnemonics_for(buttons()),
        },
        "settings": [
            {
                "name": "version",
                "display": "Version",
                "type": "enum",
                "options": [v for v, _, _ in RELEASES],
                "default": "1.1",
                "description": "Which DOS release of the game is played. The project "
                    "supplies that release's files (see SDLPoP2's "
                    "docs/VERSIONS.md). '1.1' is the release on the Prince "
                    "of Persia Collection CD, which SDLPoP2 is rebuilt from."
                    " The others are '1.0' and the initial release ('ir'). "
                    "The releases differ in movement near walls and gates, "
                    "the guards, the spirit, levels 2, 5, 8 and 14, the "
                    "timers and random numbers, and a few story scenes. 1.0 "
                    "and 1.1 have the same data files and differ only in "
                    "PRINCE.EXE. The initial release has files of its own "
                    "(twelve of them differ), and its cheat word is makinit.",
            },
            {
                "name": "music",
                "display": "Sound Device",
                "type": "enum",
                "options": ["roland", "fm", "speaker"],
                "default": "roland",
                "description": "What plays the sound. 'roland' (the default) plays the "
                    "music on a Roland MT-32 connected to an MPU-401, which "
                    "the game's setup program calls \"Roland "
                    "MT-32/LAPC-1/CM-32L\". 'fm' plays it on the FM chip of "
                    "the Sound Blaster Pro, which is what the original setup"
                    " program chose. Both use the Sound Blaster's digitized "
                    "sounds. 'speaker' uses the PC speaker alone, with the "
                    "game's own speaker player and speaker sounds "
                    "(IBMSND.DAT, NISIBM.DAT). The game knows which device "
                    "it has. With the speaker it answers \"Music "
                    "Unavailable\", plays no background music, and waits "
                    "after a death or at the end of a level for as long as "
                    "the speaker's sounds last, as the original did on such "
                    "a machine. The timing of the story scenes is still the "
                    "sound card's. The MT-32 needs the setup program's "
                    "PRESET40.DEF and the two ROMs of an MT-32 (version "
                    "1.07), which the project supplies as firmware. With it "
                    "the game starts 9.35 seconds later, as the original "
                    "did, while the instrument sounds are sent to the MT-32."
                    " So a movie plays back only with the sound device it "
                    "was made with.",
            },
            {
                "name": "random_seed",
                "display": "Random seed",
                "type": "int",
                "default": 0,
                "min": 0,
                "max": 2147483647,
                "description": "The starting value (seed) of the game's random number "
                    "generator. The DOS program took it from the clock. A "
                    "movie records the number it ran with.",
            },
            {
                "name": "player_name",
                "display": "Player Name (Hall of Fame)",
                "type": "string",
                "default": "Chimera",
                "description": "The name that a won game enters in the hall of fame "
                    "when its time earns a place there. The game types it "
                    "into its own name editor, as the keys would have typed "
                    "it. Only the characters in the game's font are used, "
                    "and only as many as fit in the box (24 at most). The "
                    "controls have no letter keys, so the game enters the "
                    "name by itself.",
            },
            {
                "name": "cheats",
                "display": "Enable Cheats",
                "type": "bool",
                "default": False,
                "description": "Starts the program with the cheat word on its command "
                    "line (yippeeyahoo, or makinit for the initial release),"
                    " as the original allowed. The cheat buttons exist only "
                    "when this is on. They cover the DOS game's cheats and "
                    "SDLPoP2's own. Next Level (Alt+N) can then reach any "
                    "level.",
            },
            {
                "name": "igt_from_level_1",
                "display": "IGT From Level 1",
                "type": "bool",
                "default": True,
                "description": "Makes the in-game time (IGT, the project's GameTime) "
                    "count from the very beginning of level 1. The game's "
                    "own clock stays stopped until the first story scene "
                    "after level 4, so without this setting the levels "
                    "before it add nothing. With it, their ticks of play are"
                    " added, counted the way the clock counts them (while "
                    "the prince is alive). It changes nothing in the game.",
            },
        ] + ini_settings(),
        "firmware": firmware,
    }
    with open(out, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
