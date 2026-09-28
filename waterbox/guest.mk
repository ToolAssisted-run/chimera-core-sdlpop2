# guest.mk - core.wbx: the same SDLPoP2 and core sources as native.mk, built
# with miniBox's musl guest toolchain (C only) and linked at the guest base.
# Objects land in build/guest; core.wbx is checked by miniBox's check-wbx.sh
# (no thread-local storage, no %fs, no red zone) before it counts as built.
#
# Usage: make -f guest.mk -j$(nproc) [MB=<miniBox checkout>]

.DEFAULT_GOAL := all
include sources.mk

B      := $(ROOT)/build/guest
MBUILD := $(MB)/build/meson-linux
CC     := $(MBUILD)/musl-gcc

# BizHawk waterbox's frozen guest flags, as miniBox's source/guest/meson.build
# gives them to a C guest
WBFLAGS := -fvisibility=hidden -mcmodel=large -mno-red-zone -mstack-protector-guard=global \
	-fno-stack-protector -fno-pic -fno-pie -fcf-protection=none -DNDEBUG -DCHIMERA_GUEST
MBINCS := -I$(MB)/extern/emulibc -I$(MB)/source/guest/include -I$(MB)/extern/jsmn

POP2_CFLAGS := $(WBFLAGS) $(POP2_CFLAGS_COMMON) -w
CORE_CFLAGS := $(WBFLAGS) $(POP2_CFLAGS_COMMON) $(MBINCS) -I. -Wall -Wno-unused-function

$(call flags_stamp,$(B),$(CC) | $(POP2_CFLAGS) | $(CORE_CFLAGS))

POP2_OBJS := $(patsubst $(POP2)/%.c,$(B)/pop2/%.o,$(POP2_SRCS))
CORE_OBJS := $(addprefix $(B)/core/,$(addsuffix .o,$(CORE_NAMES)))

all: $(B)/core.wbx

$(CC):
	@echo "miniBox's C guest toolchain is missing: $(CC)" >&2
	@echo "build it: meson setup $(MB)/build/meson-linux $(MB) && ninja -C $(MB)/build/meson-linux" >&2
	@false

$(B)/pop2/%.o: $(POP2)/%.c $(PATCH_STAMP) $(B)/flags | $(CC)
	@mkdir -p $(dir $@)
	$(CC) $(POP2_CFLAGS) -c -o $@ $<

$(B)/core/%.o: %.c $(CORE_HDRS) $(PATCH_STAMP) $(B)/flags | $(CC)
	@mkdir -p $(dir $@)
	$(CC) $(CORE_CFLAGS) -c -o $@ $<

$(B)/core.wbx: $(CORE_OBJS) $(POP2_OBJS)
	$(CC) -static -no-pie -Wl,--eh-frame-hdr,-O2 -Wl,-z,stack-size=8388608 -T $(MB)/source/guest/linkscript.T \
		-o $@.tmp $^ $(MBUILD)/source/guest/emulibc.c.o $(WRAP_FLAGS) -lm -lgcc
	sh $(MB)/source/guest/check-wbx.sh $@.tmp
	mv $@.tmp $@

clean:
	rm -rf $(B)

.PHONY: all clean
