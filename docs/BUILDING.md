# Building the SDLPoP2 core

This repository builds SDLPoP2, the reconstruction of Prince of Persia 2: The
Shadow and the Flame (DOS), as a Chimera game core: one game rebuilt as a
core, not an emulator. The result is one file, `sdlpop2.chimeraCore`, which
Chimera loads. The steps below are the ones the repository's CI runs from a
fresh clone (`.github/workflows/chimera.yml`).

Placeholders used in this document:

- `<core>`: the checkout of this repository.
- `<chimera>`: a checkout of Chimera
  (https://github.com/ToolAssisted-run/chimera).
- `<minibox>`: `<chimera>/extern/chimera-common-minibox`, the miniBox
  submodule of that checkout. miniBox is the sandbox host and the guest
  toolchain.

## Requirements

- Linux, x86_64. CI builds on GitHub's `ubuntu-latest` runner. Cores are built
  on Linux; the package that comes out runs on Linux and on Windows.
- git, and the packages CI installs:

  ```
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends meson ninja-build build-essential cmake pkg-config python3 libgl1-mesa-dev libegl-dev libx11-dev libxext-dev libasound2-dev
  ```

- The compilers are the distribution's gcc and g++ (`build-essential`). The
  workflow pins no compiler version.
- `curl`. miniBox's build of the C++ guest toolchain calls it (below). The
  workflow's package list does not name it.
- Chimera built with its window, for Chimera's contract tests (and the
  frontend tests). Chimera's `tools/ci-chimera.sh` installs what that needs
  (Qt 6.12, from Qt's own archives with aqt) and builds it; the workflow
  keeps Qt in `~/qt` between runs. The core's own build does not use it.

What gets downloaded or built along the way:

- Nothing in this repository's scripts downloads anything. SDLPoP2 and Munt
  (the Roland MT-32, C++) are compiled from the two submodules.
- miniBox builds the guest C library (musl) from sources in its own checkout.
- miniBox's C++ guest toolchain is a libstdc++ built for the guest. Its build
  fetches the GCC source that matches the host's gcc (about 84 MB) and
  compiles libstdc++ from it. This step needs the network once.

## Get the sources

CI checks out both repositories with `actions/checkout@v6` and
`submodules: recursive`, Chimera at its `main` branch. By hand:

```
git clone --recursive https://github.com/ToolAssisted-run/chimera-core-sdlpop2.git <core>
git clone --recursive https://github.com/ToolAssisted-run/chimera.git <chimera>
```

In a clone made without `--recursive`:

```
git submodule update --init --recursive
```

This repository has two submodules: `extern/SDLPoP2` (the game) and
`extern/munt` (Munt, whose libmt32emu is the Roland MT-32).

The Chimera checkout can be anywhere. CI puts it in `chimera-checkout` inside
the core checkout. The scripts find miniBox in this order:

1. `-m <miniBox dir>` on the script's command line (`MB=<dir>` for the
   makefiles).
2. The `MINIBOX_DIR` environment variable. CI sets it.
3. `<chimera root>/extern/chimera-common-minibox`, for
   `build-package.sh -r <chimera root>` only.
4. `~/chimera/extern/chimera-common-minibox`.

The rest of this document sets the variable once:

```
export MINIBOX_DIR=<chimera>/extern/chimera-common-minibox
```

## Build miniBox

This core needs two build directories of miniBox, because Munt is C++. The
workflow's commands:

```
mb=<chimera>/extern/chimera-common-minibox
[ -f "$mb/build/meson-linux/build.ninja" ] || meson setup "$mb/build/meson-linux" "$mb"
meson compile -C "$mb/build/meson-linux"
[ -f "$mb/build/meson-cpp/build.ninja" ] || meson setup "$mb/build/meson-cpp" "$mb" -Dguest_cpp=true
meson compile -C "$mb/build/meson-cpp"
```

- `build/meson-linux` has `source/host/libminiboxhost.so`, the sandbox host
  library that the `run-wbx` harness links.
- `build/meson-cpp` has the C++ guest toolchain: `guest-sysroot` with musl
  and libstdc++, which `waterbox/guest.mk` compiles and links against.

`guest.mk` compiles with the system's `gcc` and `g++` through the sysroot's
specs file, and looks for libstdc++'s headers under the version that
`gcc -dumpfullversion` prints. The gcc on the PATH must be the one the C++
guest toolchain was built with.

CI keeps both directories between runs with `actions/cache@v4`. By hand they
simply stay, and the `[ -f ... ] ||` lines skip `meson setup` when a
directory is already there.

## Build the core

### Patches

`patches/` holds three numbered patches for `extern/SDLPoP2`.
`waterbox/apply-patches.sh` applies them. Both makefiles run it before any
SDLPoP2 file is compiled (`waterbox/sources.mk`, the `build/patches.stamp`
rule), so there is no separate step. It can also be run by hand:

```
./waterbox/apply-patches.sh
```

The script judges the series as a whole:

- It first applies the whole series to a scratch copy of the touched files as
  the submodule's HEAD has them. If that fails it stops and names the patch.
- A pristine tree gets every patch applied (`applied: <patch>`).
- A tree that is exactly what the series leaves behind is left alone
  (`already applied: all 3 patches`).
- Anything in between is an error that names the files.

After a build `git status` shows `extern/SDLPoP2` as modified. That is the
applied series. Do not commit it. `extern/munt` is built as it is.

### The native reference and the guest

```
cd <core>
make -C waterbox -f native.mk -j"$(nproc)"
make -C waterbox -f guest.mk -j"$(nproc)"
```

- `native.mk` builds the native reference with the host's gcc and g++: the
  same SDLPoP2, Munt and core sources as the guest. It makes
  `build/native/run-native`, which drives the core's exports directly, and
  `build/native/run-wbx`, which drives `core.wbx` through the miniBox host as
  the frontend does. The gate compares the two.
- `guest.mk` builds `build/guest/core.wbx` with the C++ guest toolchain. The
  file counts as built only after miniBox's `check-wbx.sh` passes it (no
  thread-local storage, no `%fs`, no red zone).

Both makefiles take `MB=<miniBox dir>`; without it they use `MINIBOX_DIR`.
CI does not call them directly: `waterbox/run-gate.sh` runs both, and
`waterbox/build-package.sh` runs `guest.mk` again.

## Build the package

```
./waterbox/build-package.sh -r <chimera>
```

Usage: `./waterbox/build-package.sh [-m <miniBox dir>] [-r <chimera root>] [-o <out dir>]`

- `-r <chimera root>` writes `<chimera root>/build/Cores/sdlpop2.chimeraCore`
  and removes any `<chimera root>/build/CoreCache/sdlpop2-*` directory. This
  is what CI runs.
- `-o <out dir>` writes `<out dir>/sdlpop2.chimeraCore` instead.
- With neither, the file is `build/package/sdlpop2.chimeraCore`.
- `-m <miniBox dir>` names miniBox and overrides `MINIBOX_DIR`.

The script runs `guest.mk` (log: `build/package-make.log`), checks
`core.wbx`, and packs it with `waterbox/waterbox.config`,
`waterbox/default_keybinds.json`, `waterbox/file_slots.json`, the licences
(from `waterbox/package-licenses.json`) and a `build.json` that records what
built it. It writes the archive twice and stops if the two differ. On success
it prints `package sha1 <hash>` and `packaged -> <path>`.

The package's version is the commit it was built from:

- CI passes `CORE_VERSION` (the commit). That value is stamped as it is.
- Without `CORE_VERSION` the script stamps `<commit>+local`, and
  `<commit>-dirty+local` when tracked files differ from HEAD. The patched
  `extern/SDLPoP2` tree does not count as a change.
- The commit's date, in UTC, is stamped beside it as `versionDate`.

A package built by hand is for testing. Chimera's publish script refuses a
version that carries `+local` or `-dirty`.

The script builds the guest itself, so it also works on a fresh clone with
nothing built yet; its build log is `build/package-make.log`.

## Install it into Chimera

Chimera includes no cores and downloads nothing: it has no network code. A
core gets into Chimera as a file somebody puts in its `cores` folder.

- In a Chimera source checkout the folder is `<chimera>/build/Cores/`.
  `./waterbox/build-package.sh -r <chimera>` writes the package straight
  there.
- In a release bundle the folder is `cores`, beside Chimera's program. Copy
  `sdlpop2.chimeraCore` into it. Another folder can be chosen in
  Tools > Core Manager... > Change folder...
- Tools > Core Manager... lists what is in the folder. Refresh List rescans it
  for a package copied in while the window is open.

The same package file works on Linux and on Windows. Chimera's sandbox,
miniBox, runs the guest inside it on either.

Without building: this repository's CI publishes the package on its Releases
page (https://github.com/ToolAssisted-run/chimera-core-sdlpop2/releases). A
rolling `dev` release follows every green push to `main`. A dated
`nightly-YYYY-MM-DD` release comes from the scheduled run (04:00 UTC), only
when `main` moved since the last one. A published package is named
`sdlpop2-<version>.chimeraCore`.

In Chimera a new project picks the core in File > New Project... (Kind: Game)
and the release in the wizard's System box.

## Run the gates

### The core gate

```
./waterbox/run-gate.sh
```

Usage: `./waterbox/run-gate.sh [-q] [-m <miniBox dir>] [-d <game dir>]`

- `-q` skips the build and tests what is built. A `core.wbx` older than a
  source or a patch then fails the `build:fresh` leg.
- `-d` names the folder that holds the game's files (default
  `tests/roms-local`; `POP2_DIR` also sets it).

It needs miniBox built, both directories. It builds the native reference and
the guest, then proves that the sandboxed core plays exactly as the native
reference does (picture, sound, every step's length and lag, the clock, every
memory domain), that a second sandboxed run is the same, that a savestate
before every step loses nothing, and that a new host can finish a run from a
state taken half way. It then checks the pictures, the step rates, the
property table, a poke and a freeze, the settings, the Roland MT-32, the PC
speaker, the three releases, the commands, the cheats, the in-game time, the
refusals, that the coroutines' stacks are asked for as stacks (`MAP_STACK`)
and that the package is the same twice.

The MT-32's sound is held to the sandbox, not to the native reference. Munt
builds its tables in floating point, and glibc's libm and musl's round
differently. The bytes the MT-32 is sent, with their times, are compared.

It prints one line per leg (PASS, FAIL or SKIP) and ends with
`<n> ok, <n> failed, <n> skipped`. The exit status is 0 only when nothing
failed. Its work files and pictures are in `build/gate/`.

The game's files are the user's and are never in the repository. The gate
takes them from `tests/roms-local`, which is gitignored:

- `tests/roms-local/`: Prince of Persia 2's files, the Collection CD's.
- `tests/roms-local/v10/`: 1.0's `PRINCE.EXE`, and `PRINCE-CRACKED.EXE`, a
  cracked one.
- `tests/roms-local/ir/`: the initial release's files, with the same two
  EXEs.
- `tests/roms-local/roland/`: `PRESET40.DEF`, `MT32_CONTROL.ROM` and
  `MT32_PCM.ROM`.

What is skipped without them:

- Without `PRINCE.EXE` in the game folder only the build, the stack check
  (`stacks:map-stack`), the declarations (`wire:config==driver`) and the
  refusal of a project with no files run. Everything else is one `game SKIP`
  line, the package leg included. This is what CI runs: a public runner does
  not have the game.
- Without `v10/PRINCE.EXE` or `ir/PRINCE.EXE` the releases' legs are skipped
  (`version:releases SKIP`).
- Without the three files in `roland/` the MT-32's legs are skipped
  (`roland SKIP`).

This repository has no frontend gate script.

### Chimera's contract tests

CI runs Chimera's own tests against the package it just built. They need
Chimera built first, with the workflow's commands:

```
<chimera>/tools/ci-chimera.sh
```

CI runs these before it builds miniBox. The core's own build reads only
miniBox's build directories, so the order between the two does not matter.

Then, with the package in `<chimera>/build/Cores`:

```
CHIMERA_CORES_DIR=<chimera>/build/Cores <chimera>/build/meson-linux/source/ui/test-packages
```

They prove the package is readable, is built for an ABI this frontend runs,
makes a working factory, binds only buttons its controller declares, and
stamps a version. They need none of the game's files.

## Files the core needs at run time

The package carries none of the game's data and no MT-32 ROM. The user
provides the original DOS release's files, and the project brings them as
firmware. The release is the `version` setting, picked in the new-project
wizard's System box: 1.1 (the default), 1.0 or the initial release (`ir`).
`waterbox/waterbox.config` declares each file with its size and SHA-1.

The game's 26 files, needed for every release and every sound device:

- `PRINCE.EXE`, the program, whose tables SDLPoP2 reads.
- `SEQUENCE.DAT`, `PRINCE.DAT`, `KID.DAT`, `GUARD.DAT`, `HEAD.DAT`,
  `SKELETON.DAT`, `BIRD.DAT`, `FLAME.DAT`, `JINNEE.DAT`, `ROOFTOPS.DAT`,
  `DESERT.DAT`, `CAVERNS.DAT`, `RUINS.DAT`, `TEMPLE.DAT`, `FINAL.DAT`,
  `TRANS.DAT`, `NIS.DAT`, `NIS3VC.DAT`, `DIGISND.DAT`, `MIDISND.DAT`,
  `IBMSND.DAT`, `NISDIGI.DAT`, `NISMIDI.DAT`, `NISIBM.DAT`.
- `PRESETS.DEF`, the FM instruments. On the install disks it is
  `SNDDRVRS\PRESET33.DEF`.

1.0 and 1.1 share their data files and differ in `PRINCE.EXE`. The initial
release has its own `PRINCE.EXE` and its own versions of twelve of the data
files.

Only with the Sound Device setting (`music`) at `roland`, the default:

- `PRESET40.DEF`, the MT-32's timbres. It is `SNDDRVRS\PRESET40.DEF` on the
  CD and on the install disks.
- `MT32_CONTROL.ROM` and `MT32_PCM.ROM`, a Roland MT-32's two ROMs (control
  ROM v1.07). They are no files of the game's. Another MT-32 ROM that Munt
  knows may take their place.

A new project asks for these three unless its Sound Device is set to `fm` or
`speaker`.

Where they come from: the repository says they are the user's own copy of
the original release. 1.1 is the Prince of Persia Collection CD's, the
release SDLPoP2 is rebuilt from. `waterbox/waterbox.config` describes the
MT-32's control ROM as dumped from a unit of the first generation.

A missing file is refused by name, and SDLPoP2 refuses another release's
files. A file of the user's own (a modified `PRINCE.DAT`, a cracked
`PRINCE.EXE`) may take an original's place: the core takes it as it is and
the project pins its hash.

A project needs no file of its own: `waterbox/file_slots.json` declares no
slot.

## Troubleshooting

- `miniBox not found` from the gate or the package script: they fell back to
  `~/chimera/extern/chimera-common-minibox` and it is not there. Pass `-m` or
  export `MINIBOX_DIR`.
- `miniBox's C++ guest toolchain is missing: .../build/meson-cpp/guest-sysroot`:
  miniBox was built without `-Dguest_cpp=true`, or not at all. See
  "Build miniBox".
- `could not download the GCC <version> source from any mirror`, from
  miniBox's C++ toolchain build: the build needs the network to fetch the
  GCC source.
- `extern/SDLPoP2 is not checked out`: run
  `git submodule update --init --recursive`.
- `the series does not apply to the submodule's HEAD at <patch>`: the
  submodule was moved without rebasing the patches.
- `extern/SDLPoP2 is partly patched`: the tree is neither pristine nor
  exactly what the series leaves. To start again from the submodule's HEAD,
  as the script says:

  ```
  git -C extern/SDLPoP2 reset --hard && git -C extern/SDLPoP2 clean -fd && waterbox/apply-patches.sh
  ```

  That discards edits made in the tree. Turn them into a patch first.
- `the guest build failed (build/package-make.log)` from `build-package.sh`:
  the last twenty lines of that log are printed above the message; the
  whole of it is in the file.
- `build:fresh FAIL` in the gate: `-q` was used on a `core.wbx` older than a
  source or a patch. Run the gate without `-q`.
- `nothing built to test`: `-q` was used before anything was built.
- A gate leg fails in the build: the logs are `build/gate/native-make.log`
  and `build/gate/guest-make.log`.
- `stacks:map-stack FAIL`: the coroutines' stacks must come from `mmap` with
  `MAP_STACK`. Linux runs the core either way; on Windows miniBox cannot
  deliver a fault on a stack page it was not told about.
- The MT-32's `audioHash` differs between `run-native` and `run-wbx`: that is
  expected, see "The core gate".
- `packaging is not deterministic`: two archives of the same staging folder
  differed. The package's SHA-1 is the core's identity, so the script stops.
