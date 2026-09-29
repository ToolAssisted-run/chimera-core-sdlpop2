# chimera-core-sdlpop2

[SDLPoP2](https://github.com/ToolAssisted-run/SDLPoP2), the reconstruction of
Prince of Persia 2: The Shadow and the Flame (DOS), as a
[Chimera](https://github.com/ToolAssisted-run/chimera) **game core**
(`"kind": "game"`, see Chimera's `docs/game-cores.md`): the whole DOS program
- the title and its demos, the story scenes, the menus, the levels, the hall
of fame - stepped one game step at a time in miniBox's sandbox, packaged as
`sdlpop2.chimeraCore`.

**Built on upstream SDLPoP2, with three patches**: the first makes the five
routines that read CONFIG.DAT and the game's own save files weak, so the core
can answer them; the second adds two weak hooks, for the hall of fame's name
and for the action button choosing the copy protection's symbol; the third
two more, so the core can count the time of play before the game's clock
starts. Everything else is SDLPoP2's library compiled from source, with the
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
- **The controls are the DOS keyboard's**, a button for each key the game
  reads in play: P1 Up, Down, Left, Right, Shift and Ctrl; then the game's
  commands - Pause (Esc) and Show Time (Space), either of which also skips a
  story scene, Restart Level (Alt+A), Restart Game (Alt+R), Next Level
  (Alt+N), Sound On/Off (Alt+S), Music On/Off (Alt+M), Version (Alt+V),
  Joystick Mode (Alt+J) and Keyboard Mode (Alt+K). A button held is a key held
  down; a button pressed is that key typed, once - there is no key repeat. The
  game's saved games and its menus (Alt+G, Alt+L, Alt+O, Alt+H, Enter, Tab)
  and the letter keys are left out. The copy protection's symbol is chosen
  with the arrows and the action button (P1 Shift).
- **Cheats**, with the Enable Cheats setting (off): the program starts with its
  cheat word, as from the DOS command line, and 22 more buttons exist - the
  DOS game's (Lose Hit Point, Opponent Hit Point, Kill Room, Spirit Leaves,
  More Time, Less Time, Flip Screen, Show Room, Add Max Hit Point, Feather
  Fall, Revive, Demo Player) and SDLPoP2's own (God Mode, Leave Body, Leave
  Body Flame, Sword, Look Left/Right/Up/Down, Teleport, Fly). Without the
  setting they are not buttons at all (`IsButtonActive`).
- **The hall of fame's name** is the Player Name (Hall of Fame) setting
  ("Chimera" by default): a won game's name is typed into the game's own
  editor by itself.
- **Properties**: 346 in `GetGameProperties`. The level number, the next
  level (a poke of 15 on level 14 wins the game), the time left, the random
  seed and the tick in a packed `Game State` block, copied out after each step
  and back before the next (so pokes and freezes work); the prince's record,
  the room's five character slots, the level (every room's tiles, attributes
  and the characters it starts with), the moving floors and the tile
  animations in place, as further domains, described as arrays; and the hall
  of fame as the game last wrote it.
- **The game's timer**: `IGT Ticks` and `IGT Ms` in `Game State`, the ticks of
  1/12 s the clock has lost since the game set it (the minutes it starts with,
  the ticks a minute), times 1000/12. The game's clock starts only with the
  first story scene after level 4, so on its own it counts nothing in levels 1
  to 4. The **IGT From Level 1** setting (on) adds the ticks of play before
  then (`IGT Before Clock`), counted as the clock counts them - while the
  prince lives, not in the story scenes, never in the title's demos, and from
  0 again when a new game starts - so the time runs from the very beginning of
  level 1. It changes nothing in the game. The table names the timer
  (`"gameTimer"`), so Chimera shows it as `IGT mm:ss.mmm` and saves it in the
  project at the end of the movie.
- **Settings** that change play, recorded in the project: the random seed, the
  cheats, the player name, where the in-game time starts, the intro and the story scenes, skipping the title, and
  SDLPoP2's gameplay settings (the minutes, the hit points, the first level,
  the speeds). Defaults are the original game; with every one at its default
  the game runs on SDLPoP2's verified path, with no overrides installed.
- **The machine is the original setup's**: the Sound Blaster Pro's digitized
  sounds and FM music, and CONFIG.DAT as the DOS setup writes it for them -
  the core's own, since each player's file says what their machine had.
- **Files the game writes** (the hall of fame, the options) live in guest
  memory, so a savestate carries them. A project needs no file of its own: its
  file slot list is empty.

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
