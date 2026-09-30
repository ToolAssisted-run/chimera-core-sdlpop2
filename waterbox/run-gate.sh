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
#   - play the music on a Roland MT-32 when asked: the MIDI bytes the same
#     natively and sandboxed, the start-up waiting for the timbres as the
#     original did, the MT-32 heard in stereo; or all the sound on the PC
#     speaker, the game the same
#   - refuse a missing game file and another release's files, and take a
#     file of the project's own in the original's place
#   - play the three DOS releases (the version setting): 1.0 and the initial
#     release the same natively and sandboxed, each its own game (1.0's on
#     level 10: waterbox/tests/v10-separator.txt), a cracked PRINCE.EXE the
#     same as the original
#   - ask for its coroutines' stacks as stacks (MAP_STACK)
#   - package deterministically
#
# The game is the user's Prince of Persia 2 (the Collection CD's files), never
# in the repository: the gate takes it from tests/roms-local (or -d <dir>).
# Without it only the build, the declarations and the refusal of a project with
# no files run. The other releases' legs need tests/roms-local/v10 to hold
# 1.0's PRINCE.EXE (and PRINCE-CRACKED.EXE, a cracked one) and
# tests/roms-local/ir the initial release's files (the same two EXEs); the
# MT-32's legs need
# tests/roms-local/roland to hold the setup's PRESET40.DEF (SNDDRVRS on the CD)
# and an MT-32's ROMs (MT32_CONTROL.ROM v1.07, MT32_PCM.ROM).
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

digests() { grep -E '^(frames|vsync|videoHash|audioHash|stepsHash|lagFrames|clock|midiBytes|midiHash|domain\[)'; }
# what a turbo run can be held to: all but the whole-run picture hash, which a
# run that skipped half its conversions cannot match - the half it drew is
# compared instead
turboDigests() { grep -E '^(frames|vsync|tailVideoHash|audioHash|stepsHash|lagFrames|clock|midiBytes|midiHash|domain\[)'; }
# the MT-32's sound is not held to the native reference: Munt builds its tables
# with floating point, and glibc's libm and musl's round differently (the
# DOSBox-X and OpenSamurai cores' open item). The bytes it is sent, with their
# times, are; the sandbox, which is what Chimera runs, is held to itself
noAudio() { grep -vE '^audioHash='; }
roland=0
[ -f "$data/roland/PRESET40.DEF" ] && [ -f "$data/roland/MT32_CONTROL.ROM" ] && [ -f "$data/roland/MT32_PCM.ROM" ] && roland=1
# a program that stops stepping would spin forever; no run here takes minutes
native() { timeout 300 "$nat/run-native" "$@"; }
boxed() { timeout 300 "$nat/run-wbx" "$wbx" "$@"; }
# the property at a step of a trace (column 4 on is --trace-props, in order)
at() { awk -v s="$2" -v c="$3" '$1 == s { print $(3 + c) }' "$1"; }
# the bottom line of a picture (the game's messages)
strip() { tail -c +19 "$1" 2>/dev/null | head -c $((320 * 200 * 4)) | tail -c $((320 * 16 * 4)) | sha1sum | cut -c1-16; }
tgapixels() { tail -c +19 "$1" 2>/dev/null | sha1sum | cut -c1-16; }
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
# The gate's runs are the FM chip's unless they name the music: the MT-32, the
# default, waits 655 frames at start-up and its sound is not held to the native
# reference - its own legs say roland, and mt32:default what a project that
# names no music gets.
workdir() {
	local wd="$work/$1" s="$2"
	mkdir -p "$wd"
	for f in "$data"/*.DAT "$data"/*.EXE "$data"/*.DEF; do [ -f "$f" ] && cp "$f" "$wd/"; done
	case "$s" in *'"music"'*) ;; '{}') s='{"music":"fm"}' ;; *) s="{\"music\":\"fm\",${s#\{}" ;; esac
	printf '%s' "$s" > "$wd/settings"
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

# the releases (SDLPoP2's docs/VERSIONS.md), each from its own files: 1.0's
# PRINCE.EXE with 1.1's data files (1.0 and 1.1 share them), the initial
# release's own files. relwd <name> <settings> <release dir>
relwd() { wd="$(workdir "$1" "$2")"; cp "$3"/*.DAT "$3"/*.EXE "$3"/*.DEF "$wd/" 2>/dev/null; rm -f "$wd/PRINCE-CRACKED.EXE"; echo "$wd"; }
route() { "$@" --frames 400 --movie "$here/tests/play-movie.txt" --trace "$work/$tag.trace" --trace-props "Level,Kid.X,Kid.Y,Kid.Room" 2>/dev/null | grep -E '^(loadError|frames|videoHash|audioHash|stepsHash|domain\[)'; }
if [ -f "$data/ir/PRINCE.EXE" ] && [ -f "$data/v10/PRINCE.EXE" ]; then
	# the files of one release under another's setting: SDLPoP2's refusal, word for word
	wd="$(relwd refuse-rel-ir '{"version":"ir"}' "$data/v10")"
	boxed "$wd" --frames 1 > "$work/r2.txt" 2>/dev/null
	wd="$(relwd refuse-rel-11 '{"version":"1.1"}' "$data/ir")"
	boxed "$wd" --frames 1 > "$work/r3.txt" 2>/dev/null
	if grep -qx "loadError=The initial release needs its own game files (these are 1.0 / 1.1's)." "$work/r2.txt" &&
	   grep -qx "loadError=These are the initial release's game files: 1.0 and 1.1 need theirs." "$work/r3.txt"; then
		report "refuse:release-files" PASS "1.0's files under the initial release, and the initial release's under 1.1, refused by SDLPoP2"
	else
		report "refuse:release-files" FAIL "$(grep -m1 . "$work/r2.txt") / $(grep -m1 . "$work/r3.txt")"
	fi

	# each release on the play route, natively and sandboxed; and the same
	# release from a cracked PRINCE.EXE (only the copy protection's code differs)
	for rel in 10 ir; do
		v="$rel"; [ "$rel" = 10 ] && v=1.0
		wd="$(relwd "rel-$rel" "{\"version\":\"$v\",\"skip_title\":true}" "$data/$( [ "$rel" = 10 ] && echo v10 || echo ir )")"
		tag="rel-$rel-box"; route boxed "$wd" > "$work/$tag.txt"
		tag="rel-$rel-nat"; (cd "$wd" && route native . ) > "$work/$tag.txt"
		wdc="$(relwd "rel-$rel-crk" "{\"version\":\"$v\",\"skip_title\":true}" "$data/$( [ "$rel" = 10 ] && echo v10 || echo ir )")"
		cp "$data/$( [ "$rel" = 10 ] && echo v10 || echo ir )/PRINCE-CRACKED.EXE" "$wdc/PRINCE.EXE"
		tag="rel-$rel-crk"; route boxed "$wdc" > "$work/$tag.txt"
	done
	wd="$(workdir rel-11 '{"skip_title":true}')"; tag="rel-11-box"; route boxed "$wd" > "$work/$tag.txt"
	ok10=0; okir=0
	grep -qx 'frames=400' "$work/rel-10-box.txt" && cmp -s "$work/rel-10-box.txt" "$work/rel-10-nat.txt" && ok10=1
	grep -qx 'frames=400' "$work/rel-ir-box.txt" && cmp -s "$work/rel-ir-box.txt" "$work/rel-ir-nat.txt" && okir=1
	if [ $ok10 = 1 ] && [ $okir = 1 ]; then
		report "version:native" PASS "1.0 and the initial release play the route (400 steps), the same natively and sandboxed"
	else
		report "version:native" FAIL "1.0 $ok10, initial release $okir (build/gate/rel-*-box.txt vs -nat.txt)"
	fi
	# the initial release is its own game: at step 47 of the route its prince
	# stands at x 394 where 1.1's stands at 401 (IR pushes out of a wall by
	# 15 - d, not d - 32: docs/VERSIONS.md 3.1)
	x_ir="$(at "$work/rel-ir-box.trace" 47 2)"; x_11="$(at "$work/rel-11-box.trace" 47 2)"
	if [ "$x_ir" = 394 ] && [ "$x_11" = 401 ]; then
		report "version:ir-plays-its-own" PASS "step 47 of the route: the initial release's prince at x 394, 1.1's at 401"
	else
		report "version:ir-plays-its-own" FAIL "step 47: initial release x $x_ir (want 394), 1.1 x $x_11 (want 401)"
	fi
	if cmp -s "$work/rel-10-box.txt" "$work/rel-10-crk.txt" && cmp -s "$work/rel-ir-box.txt" "$work/rel-ir-crk.txt"; then
		report "version:cracked-exe" PASS "a cracked PRINCE.EXE plays the route as the original does (1.0 and the initial release)"
	else
		report "version:cracked-exe" FAIL "build/gate/rel-*-crk.txt differs from rel-*-box.txt"
	fi
	# 1.0 is its own game too, which a short route rarely shows: its second
	# guard in approach keeps clear of the first (366C:08F0) where 1.1's
	# advances. Level 10 from the copy protection (seed 0: two Rights and
	# Shift), the seed set to 0x3528860F as its first tick begins, then the
	# separator's 124 ticks: at tick 124 1.1's guard stands at x 431 (frame
	# 164) and 1.0's holds at 445 (frame 186) - SDLPoP2's own oracle numbers
	sep() { boxed "$1" --frames 340 --press 99:R:1 --press 103:R:1 --press 150:S:1 --poke "214:Random Seed=891848207" \
		--movie "$here/tests/v10-separator.txt" --movie-at 214 --trace "$work/$2.trace" --trace-props "Tick,Chars.X[1],Chars.Frame[1]" > /dev/null 2>&1
		awk '$4 == 123 || $4 == 124 { printf "%s:%s/%s ", $4, $5, $6 }' "$work/$2.trace"; }
	s11="$(sep "$(workdir sep-11 '{"skip_title":true,"first_level":10}')" sep-11)"
	s10="$(sep "$(relwd sep-10 '{"version":"1.0","skip_title":true,"first_level":10}' "$data/v10")" sep-10)"
	if [ "$s11" = "123:445/158 124:431/164 " ] && [ "$s10" = "123:445/158 124:445/186 " ]; then
		report "version:1.0-plays-its-own" PASS "level 10, tick 124: 1.1's second guard advances to x 431, 1.0's holds at 445 (the same until then)"
	else
		report "version:1.0-plays-its-own" FAIL "1.1 [$s11] (want 123:445/158 124:431/164), 1.0 [$s10] (want 123:445/158 124:445/186)"
	fi
	# Version (Alt+V) shows the release's own title (SDLPoP2 a575569; before it
	# every release said 1.1's): "PRINCE OF PERSIA 2 v1.1", "PRINCE OF PERSIA 2
	# 1.0", and the initial release's "PRINCE OF PERSIA 2" - the message line
	altv() { boxed "$1" --frames 100 --press 90:v:1 --screenshot "92:$work/$2.tga" > /dev/null 2>&1; strip "$work/$2.tga"; }
	v11="$(altv "$(workdir altv-11 '{"skip_title":true,"first_level":2}')" altv-11)"
	v10="$(altv "$(relwd altv-10 '{"version":"1.0","skip_title":true,"first_level":2}' "$data/v10")" altv-10)"
	vir="$(altv "$(relwd altv-ir '{"version":"ir","skip_title":true,"first_level":2}' "$data/ir")" altv-ir)"
	if [ "$v11" = a49508f6d327d84d ] && [ "$v10" = 6a09cffa842189c5 ] && [ "$vir" = 8420b3306c2a2de7 ]; then
		report "version:alt-v" PASS "Alt+V: PRINCE OF PERSIA 2 V1.1, PRINCE OF PERSIA 2 1.0, PRINCE OF PERSIA 2 (the initial release)"
	else
		report "version:alt-v" FAIL "strips 1.1 $v11 1.0 $v10 ir $vir (build/gate/altv-*.tga)"
	fi
	# the initial release's cheat word is its own (makinit, PRINCE.DAT's TXT4
	# 10): with the cheats on, More Time on step 30 adds a minute
	wd="$(relwd rel-ir-cheat '{"version":"ir","skip_title":true,"cheats":true}' "$data/ir")"
	boxed "$wd" --frames 60 --press 30:+:1 --trace "$work/rel-ir-cheat.trace" --trace-props "Minutes Left" > /dev/null 2>&1
	m29="$(at "$work/rel-ir-cheat.trace" 29 1)"; m59="$(at "$work/rel-ir-cheat.trace" 59 1)"
	if [ -n "$m29" ] && [ "$m59" = "$((m29 + 1))" ]; then
		report "version:ir-cheat-word" PASS "the initial release takes its own cheat word: More Time $m29 -> $m59 minutes"
	else
		report "version:ir-cheat-word" FAIL "minutes $m29 -> $m59 (want one more)"
	fi
else
	report "version:releases" SKIP "no 1.0 PRINCE.EXE in $data/v10 or initial release in $data/ir"
fi

# a file of the project's own is taken in the original's place (Chimera pins
# its hash; user-decided 2026-09-29): a PRINCE.DAT with 64 bytes of level 1's
# data changed plays, and level 1 is not the original's
wd="$(workdir custom-orig '{"skip_title":true}')"
orig="$(boxed "$wd" --frames 30 2>/dev/null | grep -E '^(loadError|frames|domain\[Level\])')"
wd="$(workdir custom-file '{"skip_title":true}')"
python3 -c "import sys; p=sys.argv[1]; d=bytearray(open(p,'rb').read()); d[45056:45120]=bytes(b ^ 0x55 for b in d[45056:45120]); open(p,'wb').write(d)" "$wd/PRINCE.DAT"
custom="$(boxed "$wd" --frames 30 2>/dev/null | grep -E '^(loadError|frames|domain\[Level\])')"
if ! echo "$custom" | grep -q loadError && echo "$custom" | grep -qx 'frames=30' &&
   [ "$(echo "$custom" | grep Level)" != "$(echo "$orig" | grep Level)" ] && ! echo "$orig" | grep -q loadError; then
	report "firmware:custom" PASS "a PRINCE.DAT of the project's own (64 bytes of level 1 changed) is taken, and level 1 is its"
else
	report "firmware:custom" FAIL "custom [$(echo $custom)] original [$(echo $orig)]"
fi

# ------------------------------------------------------------------ 5. the runs
props="Level,Kid.X,Kid.Y,Kid.Room,Kid.HP,Minutes Left,Ticks Left,Kid.Alive"
# what the command and cheat runs read
cprops="Level,Kid.X,Kid.Y,Kid.Room,Drawn Room,Minutes Left,Kid.HP,Kid.Max HP,Kid.Alive"
# name, steps, settings
tests=(
	"title|700|{}"
	"play|400|{\"skip_title\":true}"
	"commands|500|{\"skip_title\":true,\"first_level\":2}"
	"cheats|400|{\"skip_title\":true,\"first_level\":2,\"cheats\":true}"
	"roland|1400|{\"music\":\"roland\"}"
	"speaker|700|{\"music\":\"speaker\"}"
)
# the command keys, each once, on level 2 (where the prince is safe): the
# messages, the pause (Show Time ends it), Restart Level after a run (the
# minutes kept) and Restart Game (the minutes back to 75)
commands_args=(--press 30:_:1 --press 60:u:1 --press 90:m:1 --press 120:v:1
	--press 210:X:1 --press 240:_:1 --poke "300:Minutes Left=50" --press 320:R:10 --press 335:a:1 --press 380:r:1)
# every cheat, on level 2: the DOS game's and SDLPoP2's own
cheats_args=(--press 30:+:1 --press 40:-:1 --press 50:M:1 --press 60:1:1 --press 70:O:1 --press 80:I:1 --press 90:I:1
	--press 100:W:1 --press 110:P:1 --press 115:P:1 --press 120:G:1 --press 130:Z:1 --press "140:<:1" --press "150:>:1"
	--press 160:^:1 --press 170:~:1 --press "180:<:1" --press 190:Q:1 --press 200:AU:15 --press 230:F:1 --press 240:B:1
	--press 250:2:1 --press 260:3:1 --press 270:4:1 --poke "280:Kid.HP=0" --press 330:V:1)
test_args() {
	case "$1" in
		commands) args=("${commands_args[@]}" $(for s in 62 92 122 212; do echo --screenshot "$s:$work/cmd-$s.tga"; done)) ;;
		cheats) args=("${cheats_args[@]}" $(for s in 72 82 112 122 132 142 232 242; do echo --screenshot "$s:$work/cheat-$s.tga"; done)) ;;
		# the title sequence: the Broderbund card, the credits; the first
		# picture of the title's (step 9) and the one before it
		title) args=(--screenshot "300:$work/title.tga" --screenshot "599:$work/credits.tga" --screenshot "8:$work/fm-8.tga"
			--screenshot "9:$work/fm-9.tga") ;;
		# the same title on the MT-32: 655 frames later
		roland) args=(--screenshot "663:$work/mt-663.tga" --screenshot "664:$work/mt-664.tga" --screenshot "955:$work/mt-955.tga") ;;
		# the title on the PC speaker
		speaker) args=(--screenshot "300:$work/sp-300.tga") ;;
		# level 1 from its first tick: run right off the roof, die, a key
		# restarts it
		play) args=(--movie "$here/tests/play-movie.txt" --screenshot "30:$work/level1.tga") ;;
	esac
}
for t in "${tests[@]}"; do
	IFS='|' read -r name frames settings <<< "$t"
	if [ "$name" = roland ] && [ "$roland" = 0 ]; then
		report "roland" SKIP "no PRESET40.DEF and MT-32 ROMs in $data/roland"; continue
	fi
	wd="$(workdir "$name" "$settings")"
	[ "$name" = roland ] && cp "$data"/roland/* "$wd/"
	cmpnat=cat; [ "$name" = roland ] && cmpnat=noAudio
	test_args "$name"
	args+=(--frames "$frames")
	case "$name" in commands|cheats) trace=(--trace-props "$cprops" --trace) ;; *) trace=(--trace-props "$props" --trace) ;; esac

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
	$cmpnat < "$work/nat.txt" > "$work/natcmp.txt"
	$cmpnat < "$work/box.txt" > "$work/boxcmp.txt"
	if cmp -s "$work/natcmp.txt" "$work/boxcmp.txt" && cmp -s "$work/$name.native.trace" "$work/$name.trace"; then
		report "$name:equivalence" PASS "$frames steps, native == sandboxed ($(grep -c . "$work/boxcmp.txt") digests and every step's properties$([ "$name" = roland ] && echo "; $(sed -n 's/^midiBytes=//p' "$work/box.txt") MIDI bytes and their times; the MT-32's sound held to the sandbox"))"
	else
		report "$name:equivalence" FAIL "$(diff "$work/natcmp.txt" "$work/boxcmp.txt" | tr '\n' ' ' | head -c 110)$(cmp -s "$work/$name.native.trace" "$work/$name.trace" || echo ' (property traces differ)')"; continue
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

# ------------------------------------------------------------------ 6a. the MT-32
if [ "$roland" = 1 ]; then
	# the start-up sends the MT-32 its timbres (PRESET40.DEF, a MIDI piece of
	# sysex) and waits for the piece to end, as the original did (2D3E:03EE):
	# its last bytes go in step 655 (19838 sent by 654), the whole of it being
	# 19934, and nothing more in step 656; the title's music follows. The
	# title comes exactly 655 frames later than on the FM chip - the same
	# first picture, at step 664 instead of 9
	up="$(for n in 654 655 656; do boxed "$work/roland" --frames $n 2>/dev/null | sed -n 's/^midiBytes=//p'; done | tr '\n' ' ')"
	if [ "$up" = "19838 19934 19934 " ] && [ "$(pixels mt-664)" = "$(pixels fm-9)" ] && [ "$(pixels mt-663)" = "$(pixels fm-8)" ] &&
	   [ "$(pixels fm-8)" != "$(pixels fm-9)" ] && [ "$(pixels mt-955)" = "1ae6ee2c6568dea1" ]; then
		report "mt32:start-up" PASS "the timbres, 19934 bytes, sent in steps 1-655; the title drawn from step 664 (9 on the FM chip), Broderbund's card at 955"
	else
		report "mt32:start-up" FAIL "bytes at 654/655/656: $up; pictures 663 $(pixels mt-663) 664 $(pixels mt-664) (FM 8 $(pixels fm-8) 9 $(pixels fm-9)), 955 $(pixels mt-955)"
	fi
	# the MT-32 is heard: nothing while it takes its timbres (no sound is asked
	# for), then the title's music in stereo (the card's is the same on both
	# sides)
	if python3 - "$wbx" "$work/roland" "$nat/run-wbx" > "$work/mt32.txt" 2>&1 <<'EOF'
import struct, subprocess, sys
wbx, wd, run = sys.argv[1:]
subprocess.run([run, wbx, wd, "--frames", "1400", "--audio", wd + "/a.raw"], capture_output=True, check=True)
d = open(wd + "/a.raw", "rb").read()
s = struct.unpack("<%dh" % (len(d) // 2), d)
upload = 655 * 44100 * 44900 // 3146875 * 2          # the stereo samples of the first 655 frames
quiet = max(abs(x) for x in s[:upload])
after = s[upload:]
stereo = sum(1 for i in range(0, len(after), 2) if after[i] != after[i + 1])
peak = max(abs(x) for x in after)
assert quiet == 0 and stereo > 100000 and peak > 5000, (quiet, stereo, peak)
print(f"silent through the timbres; then {stereo} of {len(after) // 2} sound frames with left and right apart, peak {peak}")
EOF
	then
		report "mt32:heard" PASS "$(cat "$work/mt32.txt")"
	else
		report "mt32:heard" FAIL "$(tail -1 "$work/mt32.txt")"
	fi
	# the MT-32 is the default: a project that names no music plays it (the same
	# bytes as the roland run's), and without its files is refused for them
	wd="$work/mt-default"; mkdir -p "$wd"
	for f in "$data"/*.DAT "$data"/*.EXE "$data"/*.DEF "$data"/roland/*; do cp "$f" "$wd/"; done
	printf '{}' > "$wd/settings"
	dflt="$(boxed "$wd" --frames 700 2>/dev/null | grep -E '^midi')"
	named="$(boxed "$work/roland" --frames 700 2>/dev/null | grep -E '^midi')"
	rm "$wd/PRESET40.DEF"
	boxed "$wd" --frames 1 > "$work/mt0.txt" 2>/dev/null
	if [ -n "$dflt" ] && [ "$dflt" = "$named" ] && [ "$(echo "$dflt" | sed -n 's/^midiBytes=//p')" -gt 19934 ] &&
	   grep -qx "loadError=Prince of Persia 2 needs PRESET40.DEF for the Roland MT-32's music - add it as the project's firmware." "$work/mt0.txt"; then
		report "mt32:default" PASS "no music setting: the MT-32 ($(echo "$dflt" | sed -n 's/^midiBytes=//p') bytes by step 700, as music roland), and its files asked for"
	else
		report "mt32:default" FAIL "default [$(echo $dflt)] roland [$(echo $named)]; $(grep -m1 . "$work/mt0.txt")"
	fi
	# the MT-32's files are asked for only with it, and each is named or refused
	wd="$(workdir mt-missing '{"music":"roland"}')"; cp "$data"/roland/MT32_*.ROM "$wd/"
	boxed "$wd" --frames 1 > "$work/mt1.txt" 2>/dev/null
	wd="$(workdir mt-damaged '{"music":"roland"}')"; cp "$data"/roland/* "$wd/"
	printf '\x55' | dd of="$wd/MT32_CONTROL.ROM" bs=1 seek=1000 conv=notrunc 2>/dev/null
	boxed "$wd" --frames 1 > "$work/mt2.txt" 2>/dev/null
	wd="$(workdir mt-bad '{"music":"mt32"}')"
	boxed "$wd" --frames 1 > "$work/mt3.txt" 2>/dev/null
	if grep -qx "loadError=Prince of Persia 2 needs PRESET40.DEF for the Roland MT-32's music - add it as the project's firmware." "$work/mt1.txt" &&
	   grep -qx "loadError=the MT-32 did not take MT32_CONTROL.ROM" "$work/mt2.txt" &&
	   grep -qx "loadError=the music setting is mt32; it is roland, fm or speaker" "$work/mt3.txt"; then
		report "mt32:refusals" PASS "no PRESET40.DEF: named; a damaged control ROM: Munt does not take it; an unknown music setting: refused"
	else
		report "mt32:refusals" FAIL "$(grep -h loadError "$work"/mt[123].txt | tr '\n' ' ' | head -c 200)"
	fi
fi

# ------------------------------------------------------------------ 6a'. the PC speaker
# the speaker plays the title: its own sound (not the card's), mono, heard in
# every second of it; the game is the card's - the same pictures, step for
# step, and no MIDI
if python3 - "$wbx" "$work/speaker" "$nat/run-wbx" > "$work/speaker-heard.txt" 2>&1 <<'EOF'
import struct, subprocess, sys
wbx, wd, run = sys.argv[1:]
subprocess.run([run, wbx, wd, "--frames", "700", "--audio", wd + "/a.raw"], capture_output=True, check=True)
d = open(wd + "/a.raw", "rb").read()
s = struct.unpack("<%dh" % (len(d) // 2), d)
left, right = s[0::2], s[1::2]
assert left == right, "left and right apart"
peaks = [max(abs(x) for x in left[i:i + 44100]) for i in range(0, len(left) - 44100 + 1, 44100)]
assert min(peaks) > 3000, peaks
print(f"the title's {len(peaks)} seconds each heard (peaks {min(peaks)}..{max(peaks)}), mono")
EOF
then
	h() { sed -n "s/^$2=//p" "$work/$1.box.txt"; }
	if [ "$(h speaker videoHash)" = "$(h title videoHash)" ] && [ "$(h speaker stepsHash)" = "$(h title stepsHash)" ] &&
	   [ "$(h speaker audioHash)" != "$(h title audioHash)" ] && [ "$(h speaker midiBytes)" = "0" ] && [ "$(pixels sp-300)" = "1ae6ee2c6568dea1" ]; then
		report "speaker:heard" PASS "$(cat "$work/speaker-heard.txt"); not the card's sound; the same 700 pictures and steps as the card's"
	else
		report "speaker:heard" FAIL "video $(h speaker videoHash)/$(h title videoHash) steps $(h speaker stepsHash)/$(h title stepsHash) audio $(h speaker audioHash)/$(h title audioHash) midi $(h speaker midiBytes)"
	fi
else
	report "speaker:heard" FAIL "$(tail -1 "$work/speaker-heard.txt")"
fi

# ------------------------------------------------------------------ 6b. the keys
# the game knows its device (SDLPoP2 issue #1): with the speaker, Music On/Off
# on level 2 answers "Music Unavailable" where the card's says "Ambient Music
# Off" - the message line, speaker against fm
musicmsg() { wd="$(workdir "musicmsg-$1" "{\"music\":\"$1\",\"skip_title\":true,\"first_level\":2}")"
	boxed "$wd" --frames 100 --press 90:m:1 --screenshot "92:$work/musicmsg-$1.tga" >/dev/null 2>&1; strip "$work/musicmsg-$1.tga"; }
mm_fm="$(musicmsg fm)"; mm_sp="$(musicmsg speaker)"
if [ "$mm_fm" = "2b8aae47c79a1313" ] && [ "$mm_sp" = "d899375feb29d15e" ]; then
	report "speaker:game-knows" PASS "Music On/Off with the speaker: MUSIC UNAVAILABLE; with the card: AMBIENT MUSIC OFF"
else
	report "speaker:game-knows" FAIL "strips: fm $mm_fm (want 2b8aae47c79a1313), speaker $mm_sp (want d899375feb29d15e)"
fi
# every command and cheat button reaches the program as the DOS key code its
# key has (SDLPoP2's own trace of the keys the game reads while playing): Alt
# commands scan << 8, Shift+letter a capital, F3 and the Alt arrows their codes
keycodes() { SHELL_TRACE=1 timeout 300 "$nat/run-native" "$@" 2>&1 | awk '/ shell key / { printf "%s ", $4 }'; }
kc="$(keycodes "$work/commands" --frames 500 "${commands_args[@]}")"
kn="$(keycodes "$work/commands" --frames 60 --press 30:n:1 --trace "$work/nextlevel.trace" --trace-props "$cprops")"
kh="$(keycodes "$work/cheats" --frames 400 "${cheats_args[@]}")"
want_c="32 7936 12800 12032 27 32 19712 7680 4864 "
want_h="43 45 84 75 82 73 73 87 15616 15616 71 122 39680 40192 38912 40960 39680 116 18432 97 98 104 103 107 83 114 "
if [ "$kc" = "$want_c" ] && [ "$kn" = "12544 " ] && [ "$kh" = "$want_h" ]; then
	report "keys:codes" PASS "8 commands (Space, Alt+S M V, Esc, Alt+A R N) and 22 cheats arrive as the DOS game's key codes"
else
	report "keys:codes" FAIL "commands [$kc] next [$kn] cheats [$kh]"
fi

# ------------------------------------------------------------------ 6c. the commands
ct="$work/commands.trace"
msgs=""; for s in 62 92 122 212; do png "cmd-$s"; msgs="$msgs$(strip "$work/cmd-$s.tga") "; done
if [ "$msgs" = "c0564ca64c3fc3bf 2b8aae47c79a1313 512534bd5f388ed7 c33fa1725b5d00ea " ]; then
	report "commands:messages" PASS "SOUND OFF, AMBIENT MUSIC OFF, PRINCE OF PERSIA 2 V1.1, GAME PAUSED"
else
	report "commands:messages" FAIL "strips $msgs(build/gate/cmd-*.png)"
fi
# paused until a key; Restart Level puts the prince back and keeps the
# minutes, Restart Game starts again at 75; Next Level cuts them to 15
one="3146875/44900"
if [ "$(awk '$1 == 212' "$ct" | cut -d' ' -f2)" = "$one" ] && [ "$(awk '$1 == 239' "$ct" | cut -d' ' -f2)" = "$one" ] &&
   [ "$(awk '$1 == 245' "$ct" | cut -d' ' -f2)" != "$one" ] &&
   [ "$(at "$ct" 330 2)" != "$(at "$ct" 319 2)" ] && [ "$(at "$ct" 345 6)" = "50" ] && [ "$(at "$ct" 390 6)" = "75" ] &&
   [ "$(at "$work/nextlevel.trace" 40 6)" = "15" ]; then
	report "commands:effects" PASS "paused 212-239; Restart Level keeps 50 minutes, Restart Game 75; Next Level: 15 minutes"
else
	report "commands:effects" FAIL "rates $(awk '$1 == 212 || $1 == 239 || $1 == 245 { printf "%s ", $2 }' "$ct"), X $(at "$ct" 319 2)->$(at "$ct" 330 2), minutes $(at "$ct" 345 6)/$(at "$ct" 390 6)/$(at "$work/nextlevel.trace" 40 6)"
fi

# the copy protection (a level 3 start asks it): the action button chooses
# the symbol - here the third, the answer for this seed: the level begins; the
# first is wrong and the next question comes; with no choice it waits
copyprot_run() { boxed "$work/copyprot" --frames 400 "$@" --trace "$work/cp.trace" --trace-props "Level" > /dev/null 2>&1; awk '$1 == 399 { print $4, $2 }' "$work/cp.trace"; }
workdir copyprot '{"skip_title":true,"first_level":3}' > /dev/null
right="$(copyprot_run --press 99:R:1 --press 103:R:1 --press 150:S:1)"; wrong="$(copyprot_run --press 150:S:1)"; none="$(copyprot_run)"
if [ "$right" = "3 3146875/269400" ] && [ "$wrong" = "0 $one" ] && [ "$none" = "0 $one" ]; then
	report "commands:copy-protection" PASS "Shift on the right symbol: level 3 plays; on a wrong one, or none chosen, the copy protection still asks"
else
	report "commands:copy-protection" FAIL "right [$right] wrong [$wrong] none [$none]"
fi

# the hall of fame's name is the player_name setting ("Chimera" unless set),
# entered by the game itself: level 14 (its copy protection answered), the
# game won by Next Level poked to 15, the closing scene skipped with Space
wd="$(workdir hofname '{"skip_title":true,"first_level":14}')"
boxed "$wd" --frames 700 --press 99:R:1 --press 103:R:1 --press 150:S:1 --poke "400:Next Level=15" --press 420:_:1 \
	--trace "$work/hofname.trace" --trace-props "Hall of Fame.Count,Hall of Fame.Minutes[0]" --dump-domain "Hall of Fame" "$work/hof.bin" \
	--screenshot "699:$work/hofname.tga" > /dev/null 2>&1
png hofname
wd="$(workdir hofblank '{"player_name":"   "}')"
boxed "$wd" --frames 1 > "$work/hofblank.txt" 2>/dev/null
if [ "$(tail -c +3 "$work/hof.bin" 2>/dev/null | head -c 27 | tr -d '\0')" = "Chimera" ] && [ "$(at "$work/hofname.trace" 699 1)" = "1" ] &&
   [ "$(at "$work/hofname.trace" 699 2)" = "75" ] && grep -q "^loadError=the Player Name (Hall of Fame) setting has nothing the game can show" "$work/hofblank.txt"; then
	report "settings:player-name" PASS "a won game (75 minutes left) enters Chimera, the default name, in the hall of fame by itself (build/gate/hofname.png); a blank one is refused"
else
	report "settings:player-name" FAIL "name [$(tail -c +3 "$work/hof.bin" 2>/dev/null | head -c 27 | tr -d '\0')], count $(at "$work/hofname.trace" 699 1), minutes $(at "$work/hofname.trace" 699 2); $(grep -m1 . "$work/hofblank.txt")"
fi

# ------------------------------------------------------------------ 6d. the cheats
cht="$work/cheats.trace"
if [ "$(at "$cht" 35 6)" = "76" ] && [ "$(at "$cht" 45 6)" = "75" ] && [ "$(at "$cht" 55 8)" = "4" ] && [ "$(at "$cht" 65 7)" = "3" ] &&
   [ "$(at "$cht" 145 5)" = "1" ] && [ "$(at "$cht" 155 5)" = "2" ] && [ "$(at "$cht" 195 4)" = "1" ] &&
   [ "$(at "$cht" 210 3)" -lt 60 ] && [ "$(at "$cht" 329 9)" -gt 0 ] && [ "$(at "$cht" 335 9)" = "-1" ]; then
	report "cheats:effects" PASS "+/- minutes, a max hit point, one lost, Look Left/Right, Teleport to room 1, Fly (y $(at "$cht" 210 3)), Revive"
else
	report "cheats:effects" FAIL "min $(at "$cht" 35 6)/$(at "$cht" 45 6), HP $(at "$cht" 55 8) $(at "$cht" 65 7), drawn $(at "$cht" 145 5)/$(at "$cht" 155 5), room $(at "$cht" 195 4), y $(at "$cht" 210 3), alive $(at "$cht" 329 9)->$(at "$cht" 335 9)"
fi
cmsgs=""; for s in 72 112 122 132 142 232 242; do png "cheat-$s"; cmsgs="$cmsgs$(strip "$work/cheat-$s.tga") "; done
png cheat-82
if [ "$cmsgs" = "554f4dbace6d1a7e 01ad1e21a5b45c44 6935eae9edc808c3 056fd1ae30b62f23 31e453820a1b3b16 d534fdba0efb8f19 a3537c3f621e72ac " ] && [ "$(tgapixels "$work/cheat-82.tga")" = "b406b4e9cad0ee21" ]; then
	report "cheats:messages" PASS "ROOM 2, PLAYER ON, GOD MODE ON, NO SWORD, ROOM 1, THE FLAME, ALREADY A SPIRIT; Flip Screen upside down (build/gate/cheat-*.png)"
else
	report "cheats:messages" FAIL "strips $cmsgs flip $(tgapixels "$work/cheat-82.tga")"
fi
# without the setting the cheats are no buttons: none is active, and pressing
# every one changes nothing
wd="$(workdir nocheats '{"skip_title":true,"first_level":2}')"
boxed "$wd" --frames 300 > "$work/nocheats-plain.txt" 2>/dev/null
boxed "$wd" --frames 300 --press "100:1234+-IOMWVPGBF:20" --press "100:Z<>^~QA:20" > "$work/nocheats-pressed.txt" 2>/dev/null
if grep -qx 'activeButtons=14' "$work/nocheats-plain.txt" && grep -qx 'activeButtons=36' "$work/cheats.box.txt" &&
   cmp -s <(digests < "$work/nocheats-plain.txt") <(digests < "$work/nocheats-pressed.txt"); then
	report "cheats:off" PASS "14 buttons active without the setting (36 with it); every cheat held for 20 steps changes nothing"
else
	report "cheats:off" FAIL "$(grep activeButtons "$work/nocheats-plain.txt") / $(grep activeButtons "$work/cheats.box.txt"); $(diff <(digests < "$work/nocheats-plain.txt") <(digests < "$work/nocheats-pressed.txt") | head -2 | tr '\n' ' ')"
fi
# a key two buttons share is one key: Look Left (Alt+Left) held, P1 Left
# pressed while it is, Look Left let go - the left arrow stays down (the
# prince runs on once Alt is up), as one key would; lifting it with Look
# Left would stop him
wd="$(workdir sharedkey '{"skip_title":true,"first_level":2,"cheats":true}')"
boxed "$wd" --frames 90 --press "30:<:15" --press 40:L:50 --trace "$work/leftlook.trace" --trace-props "Kid.X,Kid.Room" > /dev/null 2>&1
pos() { echo "room $(at "$work/leftlook.trace" "$1" 2) x $(at "$work/leftlook.trace" "$1" 1)"; }
if [ -s "$work/leftlook.trace" ] && [ "$(pos 85)" != "$(pos 46)" ]; then
	report "keys:shared" PASS "Look Left let go while P1 Left holds the same key: the prince runs on ($(pos 46) -> $(pos 85))"
else
	report "keys:shared" FAIL "$(pos 46) -> $(pos 85)"
fi

# ------------------------------------------------------------------ 6e. the in-game time
# IGT Ticks counts what the game's clock counts down, and IGT Ms is that at 12
# ticks a second (the table's gameTimer). The clock only runs from the first
# story scene after level 4: level 4 (its copy protection answered), Next
# Level with the cheats, the scene skipped - with IGT From Level 1 off, the
# game's clock alone: nothing counted until level 5, then exactly one tick a
# step, through the minute's rollover (75 -> 74)
wd="$(workdir igt '{"skip_title":true,"first_level":4,"cheats":true,"igt_from_level_1":false}')"
boxed "$wd" --frames 1300 --press 99:R:1 --press 103:R:1 --press 150:S:1 --press 420:n:1 --press 450:_:1 --press 470:_:1 --press 490:_:1 \
	--trace "$work/igt.trace" --trace-props "Level,Minutes Left,Ticks Left,IGT Ticks,IGT Ms" > /dev/null 2>&1
igt="$(awk '$1 ~ /^[0-9]+$/ && $1 >= 519 && $7 - p != 1 { odd++ } $1 ~ /^[0-9]+$/ && $8 != int($7 * 1000 / 12) { bad++ } { p = $7 } END { print odd + 0, bad + 0 }' "$work/igt.trace")"
if [ "$igt" = "0 0" ] && [ "$(at "$work/igt.trace" 517 4)" = "0" ] && [ "$(at "$work/igt.trace" 600 1)" = "5" ] &&
   [ "$(at "$work/igt.trace" 1299 2)" = "74" ] && [ "$(at "$work/igt.trace" 1299 4)" = "782" ] && [ "$(at "$work/igt.trace" 1299 5)" = "65166" ]; then
	report "time:igt" PASS "nothing counted before level 5; then one tick a step through the minute's rollover: 782 = 01:05.166 at step 1299"
else
	report "time:igt" FAIL "off-by-a-tick steps and ms mismatches: $igt; IGT $(at "$work/igt.trace" 517 4) at 517, level $(at "$work/igt.trace" 600 1), minutes $(at "$work/igt.trace" 1299 2), IGT $(at "$work/igt.trace" 1299 4) $(at "$work/igt.trace" 1299 5)"
fi

# IGT From Level 1 (on by default): the ticks of play before the clock starts
# count too. Levels 1 to 4 skipped with Next Level, the copy protection after
# level 2 answered, the story scenes skipped: 984 ticks counted in those four
# levels (none in a scene), then no more once the clock runs, and at every step
# the time is that count plus the clock's. Off, the same run is the clock
# alone, and the game plays exactly the same
lv1_press=(--press 80:n:1 --press 400:n:1 --press 480:R:1 --press 484:R:1 --press 530:S:1 --press 900:n:1 --press 1300:n:1)
for s in $(seq 100 20 380) $(seq 600 20 780) $(seq 920 20 1180) $(seq 1320 20 1600); do lv1_press+=(--press "$s:_:1"); done
lv1_props="Level,Minutes Left,Ticks Left,IGT Ticks,IGT Before Clock,Kid.X,Kid.Room"
wd="$(workdir lv1on '{"skip_title":true,"cheats":true}')"
boxed "$wd" --frames 1900 "${lv1_press[@]}" --trace "$work/lv1on.trace" --trace-props "$lv1_props" > /dev/null 2>&1
wd="$(workdir lv1off '{"skip_title":true,"cheats":true,"igt_from_level_1":false}')"
boxed "$wd" --frames 1900 "${lv1_press[@]}" --trace "$work/lv1off.trace" --trace-props "$lv1_props" > /dev/null 2>&1
# columns: 4 level, 5 minutes, 6 ticks, 7 IGT, 8 before the clock, 9-10 the prince
lv1sum="$(awk '$1 ~ /^[0-9]+$/ && $7 != $8 + 54644 - ($5 * 719 + $6) { bad++ } END { print bad + 0 }' "$work/lv1on.trace")"
lv1play() { awk '$1 ~ /^[0-9]+$/ { print $1, $4, $5, $6, $9, $10 }' "$1"; }
if [ -s "$work/lv1on.trace" ] && [ "$lv1sum" = "0" ] && [ "$(at "$work/lv1on.trace" 100 5)" = "61" ] &&
   [ "$(at "$work/lv1on.trace" 1386 1)" = "4" ] && [ "$(at "$work/lv1on.trace" 1387 1)" = "5" ] &&
   [ "$(at "$work/lv1on.trace" 1386 5)" = "984" ] && [ "$(at "$work/lv1on.trace" 1899 5)" = "984" ] &&
   [ "$(at "$work/lv1on.trace" 1899 4)" = "$((984 + $(at "$work/lv1off.trace" 1899 4)))" ] &&
   [ "$(at "$work/lv1off.trace" 1386 4)" = "0" ] &&
   cmp -s <(lv1play "$work/lv1on.trace") <(lv1play "$work/lv1off.trace"); then
	report "time:from-level-1" PASS "levels 1-4 count 984 ticks, the clock takes over at level 5: $(at "$work/lv1on.trace" 1899 4) at step 1899 ($(at "$work/lv1off.trace" 1899 4) off); play identical either way"
else
	report "time:from-level-1" FAIL "sum mismatches $lv1sum; before $(at "$work/lv1on.trace" 100 5)@100 $(at "$work/lv1on.trace" 1386 5)@1386 $(at "$work/lv1on.trace" 1899 5)@1899; level $(at "$work/lv1on.trace" 1387 1)@1387; IGT $(at "$work/lv1on.trace" 1899 4) on, $(at "$work/lv1off.trace" 1899 4) off"
fi
# ...and only a game's play: the title and its demos (one of level 1 and one
# of level 4 within 15000 frames) count nothing, and a clock no game has set
# is no time. Restart Game starts the count over with the new game
wd="$(workdir lv1title '{}')"
boxed "$wd" --frames 15000 --trace "$work/lv1title.trace" --trace-props "Level,IGT Ticks,IGT Before Clock,Tick" > /dev/null 2>&1
title="$(awk '$1 ~ /^[0-9]+$/ { if (lt != "" && $7 != lt) moved++; lt = $7; if ($5 != 0 || $6 != 0) nz++ } END { print moved + 0, nz + 0 }' "$work/lv1title.trace")"
wd="$(workdir lv1restart '{"skip_title":true}')"
boxed "$wd" --frames 100 --press 60:r:1 --trace "$work/lv1restart.trace" --trace-props "Level,IGT Ticks,IGT Before Clock" > /dev/null 2>&1
if [ "${title%% *}" -gt 100 ] && [ "${title##* }" = "0" ] &&
   [ "$(at "$work/lv1restart.trace" 59 3)" = "60" ] && [ "$(at "$work/lv1restart.trace" 60 3)" = "0" ] && [ "$(at "$work/lv1restart.trace" 75 3)" = "15" ]; then
	report "time:only-play" PASS "the demos ran ${title%% *} ticks and counted none; Restart Game at 60 steps: 60 -> 0, 15 by step 75"
else
	report "time:only-play" FAIL "demo ticks / nonzero steps: $title; restart $(at "$work/lv1restart.trace" 59 3) $(at "$work/lv1restart.trace" 60 3) $(at "$work/lv1restart.trace" 75 3)"
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
