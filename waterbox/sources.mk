# sources.mk - what native.mk and guest.mk both build: the same files with the
# same defines, so the native reference and the sandboxed core are the same
# program. Included, not run.

ROOT := ..
POP2 := $(ROOT)/extern/SDLPoP2/source
MB   ?= $(or $(MINIBOX_DIR),$(HOME)/chimera/extern/chimera-common-minibox)

# ---- SDLPoP2, upstream: the library its own meson build makes (source/
# meson.build sdlpop2Sources), less coro.c - the core's coro.c takes its place
# (ucontext is not in musl, and a stack must be asked for as one; see coro.c).
# Nothing of it uses SDL: the SDL frontend is sdl/, which the core is instead.
POP2_NAMES := anim audio audio_opl3 beast blades caverns char cheats collision control \
	core dat fight final frame game glue guard heads hooks image input items kid kidctl kind1 kind5 \
	level lever5 loader menu mobs nis render render_desc render_frame render_hooks render_kind2 \
	render_kind3 render_kind4 render_kind_common render_kind_desc render_ovl37f0 render_palette \
	render_screen render_sprites render_tiles room roomhooks ruins seq shadow13 shell skeleton sound \
	spirit state temple text tick tiles trap walls bridge5 settings replay
POP2_SRCS := $(addprefix $(POP2)/,$(addsuffix .c,$(POP2_NAMES)))
# as SDLPoP2's meson.build: gnu11, a release build, -Wall
POP2_CFLAGS_COMMON := -std=gnu11 -O2 -I$(POP2)

# ---- the core
CORE_NAMES := pop2-driver game-state coro files sha1 wbx-entry
CORE_HDRS := pop2-driver.h sha1.h settings.inc

# the calls the core answers itself (files.c)
WRAP_FLAGS := -Wl,--wrap=fopen

# the patch series goes onto the submodule before anything of SDLPoP2 builds
PATCH_STAMP := $(ROOT)/build/patches.stamp
$(PATCH_STAMP): $(wildcard $(ROOT)/patches/*.patch) apply-patches.sh
	sh apply-patches.sh
	@mkdir -p $(dir $@)
	@touch $@

# Every object depends on the flags it was built with: a change to them
# rebuilds it. (A flag change that rebuilds nothing has bitten these cores: a
# red-zone object two weeks older than the flag that forbade it.)
define flags_stamp
$(shell mkdir -p $(1); printf '%s\n' '$(2)' | cmp -s - $(1)/flags || printf '%s\n' '$(2)' > $(1)/flags)
endef
