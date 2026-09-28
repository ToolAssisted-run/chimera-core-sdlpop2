#!/bin/bash
# The core gate. The sandboxed core must play Prince of Persia 2 exactly as the
# native reference does (the same driver and SDLPoP2 built for the host) -
# picture, sound, every step's length and lag, the clock and every memory
# domain - survive a savestate before every step and a new host in the middle
# of a run, and then:
#   - show the title and level 1 as they are (pictures compared, and written
#     to build/gate for a person to look at)
#   - step at the game's own rates (a tick of play is 5 to 8 VGA frames; the
#     title reads its keys every frame) and read the controls on every step
#   - export a property table that holds to chimera's docs/game-cores.md, read
#     the same through it natively and sandboxed, obey a poke and hold a freeze
#   - take its settings (a first level, the minutes, the hit points arrive)
#   - refuse a missing game file, the floppy release's PRINCE.EXE and a
#     damaged file
#   - ask for its coroutines' stacks as stacks (MAP_STACK)
#   - package deterministically
#
# The game is the user's Prince of Persia 2 (the Collection CD's files), never
# in the repository: the gate takes it from tests/roms-local (or -d <dir>).
# Without it only the build, the declarations and the refusal of a project with
# no files run. The floppy release's PRINCE.EXE, if tests/roms-local/floppy
# holds one, is used for its refusal.
#
# Usage: ./run-gate.sh [-q] [-m <miniBox dir>] [-d <game dir>]
#   -q skips the build (uses what is built)
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
mb="${MINIBOX_DIR:-$HOME/chimera/extern/chimera-common-minibox}"
data="${POP2_DIR:-$root/tests/roms-local}"
quick=0
while getopts "qm:d:" opt; do
	case "$opt" in
		q) quick=1 ;;
		m) mb="$OPTARG" ;;
		d) data="$OPTARG" ;;
		*) exit 2 ;;
	esac
done
mb="$(cd "$mb" 2>/dev/null && pwd)" || { echo "miniBox not found; pass -m or set MINIBOX_DIR" >&2; exit 1; }

nat="$root/build/native"
wbx="$root/build/guest/core.wbx"
work="$root/build/gate"
rm -rf "$work"
mkdir -p "$work"

ok=0
failed=0
skipped=0
report() {
	printf "%-30s %-6s %s\n" "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok+1)) ;; SKIP) skipped=$((skipped+1)) ;; *) failed=$((failed+1)) ;; esac
}
printf "%-30s %-6s %s\n" "Check" "Result" "Detail"
printf "%-30s %-6s %s\n" "-----" "------" "------"

digests() { grep -E '^(frames|vsync|videoHash|audioHash|stepsHash|lagFrames|clock|domain\[)'; }
# what a turbo run can be held to: all but the whole-run picture hash, which a
# run that skipped half its conversions cannot match - the half it drew is
# compared instead
turboDigests() { grep -E '^(frames|vsync|tailVideoHash|audioHash|stepsHash|lagFrames|clock|domain\[)'; }
# a program that stops stepping would spin forever; no run here takes minutes
native() { timeout 300 "$nat/run-native" "$@"; }
boxed() { timeout 300 "$nat/run-wbx" "$wbx" "$@"; }
# the property at a step of a trace (column 4 on is --trace-props, in order)
at() { awk -v s="$2" -v c="$3" '$1 == s { print $(3 + c) }' "$1"; }
# a step's length in VGA frames (70.086 Hz), from the rate a trace reports
frames_of() { awk -v s="$2" '$1 == s { split($2, r, "/"); print r[2] / 44900 }' "$1"; }

# ------------------------------------------------------------------ 1. build
if [ "$quick" -eq 0 ]; then
	if make -C "$here" -f native.mk MB="$mb" -j"$(nproc)" > "$work/native-make.log" 2>&1 &&
	   make -C "$here" -f guest.mk MB="$mb" -j"$(nproc)" > "$work/guest-make.log" 2>&1; then
		report "build" PASS "native reference, harnesses and core.wbx (check-wbx clean)"
	else
		report "build" FAIL "see build/gate/*-make.log"
	fi
fi
[ -x "$nat/run-native" ] && [ -x "$nat/run-wbx" ] && [ -f "$wbx" ] || { echo "nothing built to test" >&2; exit 1; }
# a gate over an old core.wbx proves nothing about the sources: every source
# and the patch series must be older than what is tested
stale="$(find "$here" -maxdepth 1 \( -name '*.c' -o -name '*.h' -o -name '*.inc' -o -name '*.mk' \) \
	! -name 'run-*.c' ! -name 'gate-harness.h' -newer "$wbx" | head -3; find "$root/patches" -name '*.patch' -newer "$wbx" | head -1)"
if [ -n "$stale" ]; then
	report "build:fresh" FAIL "core.wbx is older than $(echo $stale | tr '\n' ' ')"
fi

# The program shell and the story scenes run on stacks of their own, which must
# be asked for as stacks (mmap, MAP_STACK): on Windows miniBox cannot deliver a
# fault on a page the stack pointer is in unless it was told the page is a
# stack, and the x68k core died there on its first frame. Linux runs the core
# either way, so this is where it can be seen.
if nm "$root/build/guest/core/coro.o" 2>/dev/null | grep -q ' U mmap$' && ! grep -rq 'makecontext' "$root/build/guest/core"/*.o 2>/dev/null; then
	report "stacks:map-stack" PASS "the coroutines' stacks are mmap'd (MAP_STACK), not malloc'd"
else
	report "stacks:map-stack" FAIL "coro.o does not take its stacks from mmap"
fi

# ------------------------------------------------------------------ 2. the declarations
if python3 "$here/tests/check-wire.py" "$root" > "$work/wire.txt" 2>&1; then
	report "wire:config==driver" PASS "$(cat "$work/wire.txt")"
else
	report "wire:config==driver" FAIL "$(tail -1 "$work/wire.txt")"
fi

# a work dir: the game files the project would mount, and a settings file
workdir() {
	local wd="$work/$1"
	mkdir -p "$wd"
	for f in "$data"/*.DAT "$data"/*.EXE "$data"/*.DEF; do [ -f "$f" ] && cp "$f" "$wd/"; done
	printf '%s' "$2" > "$wd/settings"
	echo "$wd"
}

# ------------------------------------------------------------------ 3. no files
wd="$work/nofiles"; mkdir -p "$wd"; printf '{}' > "$wd/settings"
boxed "$wd" --frames 1 > "$work/nofiles.txt" 2>/dev/null
if grep -qx 'loadError=Prince of Persia 2 needs PRINCE.EXE - add it as the project.s firmware.' "$work/nofiles.txt"; then
	report "refuse:no-files" PASS "$(sed -n 's/^loadError=//p' "$work/nofiles.txt")"
else
	report "refuse:no-files" FAIL "$(head -1 "$work/nofiles.txt")"
fi

if [ ! -f "$data/PRINCE.EXE" ]; then
	report "game" SKIP "no Prince of Persia 2 files in $data"
	echo; echo "$ok ok, $failed failed, $skipped skipped"
	[ "$failed" -eq 0 ]; exit
fi

# ------------------------------------------------------------------ 4. refusals
wd="$(workdir refuse-missing '{}')"; rm "$wd/KID.DAT"
boxed "$wd" --frames 1 > "$work/r1.txt" 2>/dev/null
native "$wd" --frames 1 > "$work/r1n.txt" 2>/dev/null
if grep -qx 'loadError=Prince of Persia 2 needs KID.DAT - add it as the project.s firmware.' "$work/r1.txt" && cmp -s <(grep loadError "$work/r1.txt") <(grep loadError "$work/r1n.txt"); then
	report "refuse:missing-file" PASS "$(sed -n 's/^loadError=//p' "$work/r1.txt")"
else
	report "refuse:missing-file" FAIL "$(grep -m1 . "$work/r1.txt")"
fi

if [ -f "$data/floppy/PRINCE.EXE" ]; then
	wd="$(workdir refuse-floppy '{}')"; cp "$data/floppy/PRINCE.EXE" "$wd/PRINCE.EXE"
	boxed "$wd" --frames 1 > "$work/r2.txt" 2>/dev/null
	if grep -q "^loadError=This PRINCE.EXE is the 1993 floppy release's. SDLPoP2 is rebuilt from the Prince of Persia Collection CD's" "$work/r2.txt"; then
		report "refuse:floppy-exe" PASS "the floppy release's PRINCE.EXE refused by name"
	else
		report "refuse:floppy-exe" FAIL "$(grep -m1 . "$work/r2.txt")"
	fi
else
	report "refuse:floppy-exe" SKIP "no floppy PRINCE.EXE in $data/floppy"
fi

wd="$(workdir refuse-damaged '{}')"; printf '\x55' | dd of="$wd/SEQUENCE.DAT" bs=1 seek=1000 conv=notrunc 2>/dev/null
boxed "$wd" --frames 1 > "$work/r3.txt" 2>/dev/null
if grep -q "^loadError=SEQUENCE.DAT is not Prince of Persia 2 1.0's, as the Prince of Persia Collection CD has it: 11980 bytes, SHA-1 " "$work/r3.txt"; then
	report "refuse:damaged-file" PASS "one byte changed in SEQUENCE.DAT: refused with both hashes"
else
	report "refuse:damaged-file" FAIL "$(grep -m1 . "$work/r3.txt")"
fi

# ------------------------------------------------------------------ 5. the runs
props="Level,Kid.X,Kid.Y,Kid.Room,Kid.HP,Minutes Left,Ticks Left,Kid.Alive"
# name, steps, settings
tests=(
	"title|700|{}"
	"play|400|{\"skip_title\":true}"
)
test_args() {
	case "$1" in
		# the title sequence: the Broderbund card, the credits
		title) args=(--screenshot "300:$work/title.tga" --screenshot "599:$work/credits.tga") ;;
		# level 1 from its first tick: run right off the roof, die, a key
		# restarts it
		play) args=(--movie "$here/tests/play-movie.txt" --screenshot "30:$work/level1.tga") ;;
	esac
}
for t in "${tests[@]}"; do
	IFS='|' read -r name frames settings <<< "$t"
	wd="$(workdir "$name" "$settings")"
	test_args "$name"
	args+=(--frames "$frames")
	trace=(--trace-props "$props" --trace)

	if ! native "$wd" "${args[@]}" --props-json "$work/$name.native.json" "${trace[@]}" "$work/$name.native.trace" > "$work/$name.native.txt" 2> "$work/$name.native.err"; then
		report "$name:equivalence" FAIL "native runner: $(tail -1 "$work/$name.native.err")"; continue
	fi
	if ! boxed "$wd" "${args[@]}" --props-json "$work/$name.box.json" "${trace[@]}" "$work/$name.trace" > "$work/$name.box.txt" 2> "$work/$name.box.err"; then
		report "$name:equivalence" FAIL "sandbox runner: $(tail -1 "$work/$name.box.err")"; continue
	fi
	digests < "$work/$name.native.txt" > "$work/nat.txt"
	digests < "$work/$name.box.txt" > "$work/box.txt"
	boxed "$wd" "${args[@]}" 2>/dev/null | digests > "$work/again.txt"
	if cmp -s "$work/box.txt" "$work/again.txt"; then
		report "$name:determinism" PASS "a second sandboxed run is the same"
	else
		report "$name:determinism" FAIL "$(diff "$work/box.txt" "$work/again.txt" | tr '\n' ' ' | head -c 110)"
	fi
	if cmp -s "$work/nat.txt" "$work/box.txt" && cmp -s "$work/$name.native.trace" "$work/$name.trace"; then
		report "$name:equivalence" PASS "$frames steps, native == sandboxed ($(grep -c . "$work/box.txt") digests and every step's properties)"
	else
		report "$name:equivalence" FAIL "$(diff "$work/nat.txt" "$work/box.txt" | tr '\n' ' ' | head -c 110)$(cmp -s "$work/$name.native.trace" "$work/$name.trace" || echo ' (property traces differ)')"; continue
	fi

	if [ "$name" = play ]; then
		boxed "$wd" --frames "$frames" 2>/dev/null | digests > "$work/idle.txt"
		if cmp -s "$work/box.txt" "$work/idle.txt"; then
			report "$name:input-shaped" FAIL "the input changed nothing"
		else
			report "$name:input-shaped" PASS "the same steps with no input are another game"
		fi
	fi

	boxed "$wd" "${args[@]}" 2>/dev/null | turboDigests > "$work/tnorm.txt"
	boxed "$wd" "${args[@]}" --turbo 2>/dev/null | turboDigests > "$work/turbo.txt"
	if cmp -s "$work/tnorm.txt" "$work/turbo.txt"; then
		report "$name:turbo" PASS "half the pictures unconverted, same game and same second half"
	else
		report "$name:turbo" FAIL "$(diff "$work/tnorm.txt" "$work/turbo.txt" | tr '\n' ' ' | head -c 110)"
	fi

	boxed "$wd" "${args[@]}" --rerecord 2>/dev/null | digests > "$work/rr.txt"
	if cmp -s "$work/box.txt" "$work/rr.txt"; then
		report "$name:savestate" PASS "saved and loaded before every step: lossless"
	else
		report "$name:savestate" FAIL "$(diff "$work/box.txt" "$work/rr.txt" | tr '\n' ' ' | head -c 110)"
	fi

	boxed "$wd" "${args[@]}" --session 2> "$work/ss.err" | digests > "$work/ss.txt"
	if cmp -s "$work/box.txt" "$work/ss.txt"; then
		report "$name:session" PASS "a new host finished the run from a state at step $((frames / 2))"
	else
		report "$name:session" FAIL "$(diff "$work/box.txt" "$work/ss.txt" | tr '\n' ' ' | head -c 110)"
	fi
done

# ------------------------------------------------------------------ 6. what the runs showed
# the pictures, as the gate last saw them (look at build/gate/*.png)
png() { python3 "$here/tests/tga2png.py" "$work/$1.tga" "$work/$1.png" 2 2>/dev/null; }
pixels() { tail -c +19 "$work/$1.tga" | sha1sum | cut -c1-16; }
for shot in "title:300 (Broderbund presents):1ae6ee2c6568dea1" "credits:599 (a game by Jordan Mechner):c66b047ef49547a6" \
	"level1:30 (level 1, the rooftop):305f842af623f741"; do
	IFS=':' read -r file what want <<< "$shot"
	png "$file"
	got="$(pixels "$file")"
	if [ "$got" = "$want" ]; then
		report "picture:$file" PASS "step $what is the picture it was (build/gate/$file.png)"
	else
		report "picture:$file" FAIL "step $what: pixels $got, expected $want (build/gate/$file.png)"
	fi
done

# the rates: a step of play runs the VGA frames up to the next tick (5 or 6 of
# them for the game's frame_delay of 5 in 1/60 s; 7 or 8 when a tick is late,
# as while the prince lies dead); the title reads its keys every frame, so its
# steps are one frame; and every step reads the controls
tr="$work/play.trace"
play_frames="$(awk '$1 ~ /^[0-9]+$/ { split($2, r, "/"); print r[2] / 44900 }' "$tr" | sort -u | tr '\n' ' ')"
title_frames="$(awk '$1 ~ /^[0-9]+$/ { split($2, r, "/"); print r[2] / 44900 }' "$work/title.trace" | sort -u | tr '\n' ' ')"
if [ "$play_frames" = "5 6 7 8 " ] && [ "$title_frames" = "1 " ]; then
	report "steps:rates" PASS "play: 5 to 8 VGA frames a step (a game tick); the title: one frame a step"
else
	report "steps:rates" FAIL "play steps of $play_frames frames; title steps of $title_frames"
fi
lag="$(awk '$1 ~ /^[0-9]+$/ && $3 == 0' "$tr" "$work/title.trace" | wc -l)"
if [ "$lag" = "0" ]; then
	report "steps:lag" PASS "every step of the title and of play reads the controls"
else
	report "steps:lag" FAIL "$lag lag steps"
fi

# the play run: the rooftop guard kills the prince (dead from step 66), and
# the next key the movie presses - Left, first held at step 99 - restarts the
# level: Right was held since before he died, and a key held is not a key typed
died="$(awk '$1 ~ /^[0-9]+$/ && $11 >= 0 { print $1; exit }' "$tr")"
if [ "$died" = "66" ] && [ "$(at "$tr" 98 8)" -ge 0 ] 2>/dev/null && [ "$(at "$tr" 99 8)" -lt 0 ] 2>/dev/null; then
	report "play:die-and-restart" PASS "dead from step 66; the Left pressed at 99 restarts the level (Kid.X $(at "$tr" 98 2) -> $(at "$tr" 99 2))"
else
	report "play:die-and-restart" FAIL "dead from ${died:-never}; Kid.Alive $(at "$tr" 98 8) -> $(at "$tr" 99 8)"
fi

# the property table: the format, and the same table natively and sandboxed
if python3 "$here/tests/check-properties.py" "$work/play.box.json" "$work/play.box.txt" > "$work/props.txt" 2>&1 &&
   cmp -s "$work/play.box.json" "$work/play.native.json"; then
	report "properties:table" PASS "$(cat "$work/props.txt")"
else
	report "properties:table" FAIL "$(tail -1 "$work/props.txt")"
fi

# a poke is what the game finds: the prince's hit points set to 5 before step
# 10 are what the game has from that step (3 before it)
wd="$work/play"
boxed "$wd" --frames 20 --poke "10:Kid.HP=5" --trace "$work/poke.trace" --trace-props "$props" > /dev/null 2>&1
native "$wd" --frames 20 --poke "10:Kid.HP=5" --trace "$work/poke.native.trace" --trace-props "$props" > /dev/null 2>&1
if [ "$(at "$work/poke.trace" 9 5)" = "3" ] && [ "$(at "$work/poke.trace" 10 5)" = "5" ] && cmp -s "$work/poke.trace" "$work/poke.native.trace"; then
	report "properties:poke" PASS "Kid.HP=5 before step 10: 5 hit points from step 10 (3 before), natively and sandboxed"
else
	report "properties:poke" FAIL "Kid.HP $(at "$work/poke.trace" 9 5) -> $(at "$work/poke.trace" 10 5)"
fi

# a freeze is the same write before every step: the prince's hit points held
# at 3 outlast the rooftop guard, who kills him by step 99 without it
boxed "$wd" --frames 100 --freeze "0-99:Kid.HP=3" --trace "$work/freeze.trace" --trace-props "$props" > /dev/null 2>&1
boxed "$wd" --frames 100 --trace "$work/nofreeze.trace" --trace-props "$props" > /dev/null 2>&1
if [ "$(at "$work/freeze.trace" 99 8)" = "-1" ] && [ "$(at "$work/nofreeze.trace" 99 8)" -ge 0 ] 2>/dev/null; then
	report "properties:freeze" PASS "Kid.HP held at 3 for 100 steps: alive at step 99 (Kid.Alive -1; $(at "$work/nofreeze.trace" 99 8), dead, without the freeze)"
else
	report "properties:freeze" FAIL "frozen: Kid.Alive $(at "$work/freeze.trace" 99 8); free: $(at "$work/nofreeze.trace" 99 8)"
fi

# the settings reach the game: start on level 2 (level 3 on would stop at the
# copy protection's question first) with 5 minutes and 5 hit points, and no
# story scene before it
wd="$(workdir settings '{"skip_title":true,"first_level":2,"start_minutes_left":5,"start_hitp":5,"enable_story_scenes":false}')"
boxed "$wd" --frames 20 --trace "$work/settings.trace" --trace-props "$props" > /dev/null 2>&1
if [ "$(at "$work/settings.trace" 19 1)" = "2" ] && [ "$(at "$work/settings.trace" 19 6)" = "5" ] && [ "$(at "$work/settings.trace" 19 5)" = "5" ]; then
	report "settings:reach-the-game" PASS "first_level 2, start_minutes_left 5, start_hitp 5, no story scenes: level 2, 5 minutes, 5 hit points"
else
	report "settings:reach-the-game" FAIL "level $(at "$work/settings.trace" 19 1), minutes $(at "$work/settings.trace" 19 6), HP $(at "$work/settings.trace" 19 5)"
fi

# ------------------------------------------------------------------ 7. the package
if sh "$here/build-package.sh" -m "$mb" -o "$work/pkg1" > "$work/pkg1.log" 2>&1 &&
   sh "$here/build-package.sh" -m "$mb" -o "$work/pkg2" > "$work/pkg2.log" 2>&1 &&
   cmp -s "$work/pkg1/sdlpop2.chimeraCore" "$work/pkg2/sdlpop2.chimeraCore"; then
	report "package" PASS "$(grep 'package sha1' "$work/pkg1.log"), the same twice"
else
	report "package" FAIL "see build/gate/pkg*.log"
fi

echo
echo "$ok ok, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
