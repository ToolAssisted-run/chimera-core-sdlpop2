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


def game_files():
    text = open(os.path.join(HERE, "pop2-driver.c")).read()
    return [(n, int(size), sha1) for n, size, sha1 in
            re.findall(r'\{ "([A-Z0-9_]+\.(?:DAT|EXE|DEF))", (\d+), "([0-9A-F]{40})" \}', text)]


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
    "PRESETS.DEF": "the FM instruments (the DOS setup copies the Sound Blaster Pro's here; on the install disks it is SNDDRVRS\\PRESET33.DEF)",
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "waterbox.config")
    firmware = []
    for name, size, sha1 in game_files():
        firmware.append({
            "id": name,
            "display": "Prince of Persia 2 1.0 " + name,
            "description": "%s of Prince of Persia 2 1.0 (DOS), as the Prince of Persia Collection CD has it: %s. Yours to supply - the package carries none of the game's data.%s" % (
                name, WHAT[name],
                " The 1993 floppy release's PRINCE.EXE is another build of the program and is refused; its other files are the CD's." if name == "PRINCE.EXE" else ""),
            "size": size,
            "sha1": sha1,
            "name": name,
        })

    cfg = {
        "coreName": "SDLPoP2",
        "kind": "game",
        "systemId": "PrinceOfPersia2",
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
            "_comment": "SDLPoP2's sound (the Sound Blaster Pro's digitized sounds and its FM music, as the original setup plays them), rendered at 44100 Hz for exactly the time each step covers.",
            "rate": 44100,
            "samplesPerFrame": 44200,
            "channels": 1,
            "get": "GetAudio",
        },
        "lag": {"inputWasRead": "InputWasRead"},
        "input": {
            "name": "Prince of Persia 2",
            "_comment": "The DOS game's keyboard, a button for each key the game reads in play. P1: the arrows, Shift (grab, careful step, pick up, drink; it also chooses the copy protection's symbol, as Enter does) and Ctrl (the sword; the spirit's spell). The game's commands: Pause (Esc) and Show Time (Space) - either also skips a story scene - Restart Level (Alt+A), Restart Game (Alt+R), Next Level (Alt+N), Sound On/Off (Alt+S), Music On/Off (Alt+M), Version (Alt+V), Joystick Mode (Alt+J), Keyboard Mode (Alt+K). With the cheats setting on, the cheats: the DOS game's (Lose Hit Point Shift+K, Opponent Hit Point g, Kill Room k, Spirit Leaves Shift+S, More Time and Less Time keypad + and -, Flip Screen Shift+I, Show Room Shift+R, Add Max Hit Point Shift+T, Feather Fall Shift+W, Revive r, Demo Player F3) and SDLPoP2's own (God Mode Shift+G, Leave Body h, Leave Body Flame b, Sword z, Look Left/Right/Up/Down Alt+arrows, Teleport t, Fly A held). Left out: the game's saved games and its menus (Alt+G, Alt+L, Alt+O, Alt+H, Enter, Tab) and the letter keys; the hall of fame's name is the player_name setting, entered by the game itself. A key pressed is typed once; there is no key repeat.",
            "buttons": buttons(),
        },
        "settings": [
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
                "description": "Start the program with the cheat word on its command line (yippeeyahoo), as the original allowed: the cheats' buttons exist only with this on (the DOS game's cheats and SDLPoP2's own), and Next Level (Alt+N) reaches any level.",
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
