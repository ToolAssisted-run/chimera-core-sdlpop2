# chimera-core-sdlpop2

[SDLPoP2](https://github.com/ToolAssisted-run/SDLPoP2), the reconstruction of
Prince of Persia 2: The Shadow and the Flame (DOS), as a
[Chimera](https://github.com/ToolAssisted-run/chimera) **game core**
(`"kind": "game"`, see Chimera's `docs/game-cores.md`): the whole DOS program
- the title and its demos, the story scenes, the menus, the levels, the hall
of fame - stepped one game step at a time in miniBox's sandbox, packaged as
`sdlpop2.chimeraCore`.

**Built on upstream SDLPoP2, with one patch**: it makes the five routines that
read CONFIG.DAT and the game's own save files weak, so the core can answer
them. Everything else is SDLPoP2's library compiled from source, with the
core's own coroutines (musl has no ucontext) and its SDL frontend left out.

## What it is

- **Prince of Persia 2 1.0 as the Prince of Persia Collection CD has it**,
  from the user's own files - the release SDLPoP2 is rebuilt from, whose
  PRINCE.EXE it reads tables out of. The package carries none of the game's
  data: the 26 files are the project's **firmware**, checked file by file
  against that release's SHA-1 at Init. A missing one is named ("Prince of
  Persia 2 needs KID.DAT - add it as the project's firmware"); a damaged one is
  refused with both hashes. The 1993 floppy release's PRINCE.EXE is another
  build of the program and is refused by name - every other file of that
  release is the CD's, byte for byte.
- **A frame is one step of the game**: while playing, the VGA frames
  (70.086 Hz) up to the next game tick, where the controls are read - 5 or 6
  of them for the game's 1/12 s tick, 7 or 8 when a tick is late; on the title,
  in the story scenes, the menus and the pause, one VGA frame, because the
  program reads its keys every frame there. `GetVsyncNumerator/Denominator`
  report the step just run. Every step reads the controls.
- **The controls are the DOS keyboard's**: P1 Up, Down, Left, Right, Shift and
  Ctrl; and the keys the program reads outside play - Enter, Space, Esc, Tab,
  Backspace, Alt and the letters (the menus, the scenes, the copy protection's
  symbols, the hall of fame's name, the Alt keys). A button held is a key held
  down; a button pressed is that key typed, once - there is no key repeat.
- **Properties**: 339 in `GetGameProperties`. The level number, the time left,
  the random seed and the tick in a packed `Game State` block, copied out after
  each step and back before the next (so pokes and freezes work); the prince's
  record, the room's five character slots, the level (every room's tiles,
  attributes and the characters it starts with), the moving floors and the
  tile animations in place, as further domains, described as arrays.
- **Settings** that change play, recorded in the project: the random seed, the
  cheat word, the intro and the story scenes, skipping the title, and
  SDLPoP2's gameplay settings (the minutes, the hit points, the first level,
  the speeds). Defaults are the original game; with every one at its default
  the game runs on SDLPoP2's verified path, with no overrides installed.
- **The machine is the original setup's**: the Sound Blaster Pro's digitized
  sounds and FM music, and CONFIG.DAT as the DOS setup writes it for them -
  the core's own, since each player's file says what their machine had.
- **Files the game writes** (saved games, the hall of fame, the options) live
  in guest memory, so a savestate carries them. A saved game (PRINCE.SAV) is
  the one file a project may add, for a run that starts from one.

## Building

```
git submodule update --init --recursive
make -C waterbox -f native.mk -j$(nproc)    # the native reference and the harnesses
make -C waterbox -f guest.mk -j$(nproc)     # core.wbx
./waterbox/build-package.sh                 # build/package/sdlpop2.chimeraCore
```

miniBox is taken from `MB=`/`MINIBOX_DIR`, else `~/chimera/extern/chimera-common-minibox`;
it must be built (`build/meson-linux`, which has the C guest toolchain).

## Gate

```
./waterbox/run-gate.sh
```

Native == sandbox (picture, sound, every step's length, every memory domain
and every step's properties), determinism, savestates before every step, a new
host mid-run, turbo, the pictures, the step rates, the table, a poke, a freeze,
the settings, the refusals and the package - each leg seen to fail on a break
of its own.

The game is the user's: put Prince of Persia 2's files (the Collection CD's)
in `tests/roms-local` (gitignored), or pass `-d`; a floppy PRINCE.EXE in
`tests/roms-local/floppy` is used for its refusal. Without the files only the
build, the declarations and the no-files refusal run.
