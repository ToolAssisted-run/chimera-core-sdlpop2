# guest.mk - core.wbx: the same SDLPoP2, Munt and core sources as native.mk,
# built with miniBox's musl/libstdc++ guest toolchain (Munt, the MT-32, is C++)
# and linked at the guest base. Objects land in build/guest; core.wbx is
# checked by miniBox's check-wbx.sh (no thread-local storage, no %fs, no red
# zone) before it counts as built.
#
# Needs miniBox built WITH the C++ guest toolchain:
#   meson setup <miniBox>/build/meson-cpp <miniBox> -Dguest_cpp=true && ninja -C <miniBox>/build/meson-cpp
#
# Usage: make -f guest.mk -j$(nproc) [MB=<miniBox checkout>]

.DEFAULT_GOAL := all
include sources.mk

B      := $(ROOT)/build/guest
MBUILD := $(MB)/build/meson-cpp
SR     := $(MBUILD)/guest-sysroot
GCCVER := $(shell gcc -dumpfullversion)
# the system's compilers over the guest sysroot, through its specs (musl's
# headers and start files, -mno-red-zone), as the DOSBox-X core's cross file
CC     := gcc -specs $(SR)/lib/musl-gcc.specs
CXX    := g++ -specs $(SR)/lib/musl-gcc.specs

# BizHawk waterbox's frozen guest flags, as miniBox's source/guest/meson.build
# gives them to a guest
# The guest is built for the CPU this runs on (a package is built natively,
# never cross-built), with miniBox's own flags for that CPU (its meson.build,
# waterbox_cpu_flags); x86_64 keeps the flags it always had.
ARCH := $(shell uname -m)
ifeq ($(ARCH),aarch64)
CPUFLAGS := -mbranch-protection=none -mno-outline-atomics -ffp-contract=off -fsigned-char -ffixed-x18
else
CPUFLAGS := -mcmodel=large -mno-red-zone -fcf-protection=none
endif
WBFLAGS := -fvisibility=hidden $(CPUFLAGS) -mstack-protector-guard=global \
	-fno-stack-protector -fno-pic -fno-pie -DNDEBUG -DCHIMERA_GUEST
MBINCS := -I$(MB)/extern/emulibc -I$(MB)/source/guest/include -I$(MB)/extern/jsmn
CXXINCS := -I$(SR)/include/c++/$(GCCVER) -I$(SR)/include/c++/$(GCCVER)/$(ARCH)-linux-musl

POP2_CFLAGS := $(WBFLAGS) $(POP2_CFLAGS_COMMON) -w
CORE_CFLAGS := $(WBFLAGS) $(POP2_CFLAGS_COMMON) $(MBINCS) -I. -I$(ROOT)/build/munt-config -I$(MUNT) -Wall -Wno-unused-function
MUNT_CXXFLAGS := $(WBFLAGS) $(MUNT_CXXFLAGS_COMMON) $(CXXINCS) -fexceptions -w

$(call flags_stamp,$(B),$(CC) | $(CXX) | $(POP2_CFLAGS) | $(CORE_CFLAGS) | $(MUNT_CXXFLAGS))

POP2_OBJS := $(patsubst $(POP2)/%.c,$(B)/pop2/%.o,$(POP2_SRCS))
MUNT_OBJS := $(patsubst $(MUNT)/%.cpp,$(B)/munt/%.o,$(MUNT_SRCS))
CORE_OBJS := $(addprefix $(B)/core/,$(addsuffix .o,$(CORE_NAMES)))

all: $(B)/core.wbx

$(SR)/lib/libstdc++.a:
	@echo "miniBox's C++ guest toolchain is missing: $(SR)" >&2
	@echo "build it: meson setup $(MBUILD) $(MB) -Dguest_cpp=true && ninja -C $(MBUILD)" >&2
	@false

$(B)/pop2/%.o: $(POP2)/%.c $(PATCH_STAMP) $(B)/flags | $(SR)/lib/libstdc++.a
	@mkdir -p $(dir $@)
	$(CC) $(POP2_CFLAGS) -c -o $@ $<

$(B)/core/%.o: %.c $(CORE_HDRS) $(PATCH_STAMP) $(B)/flags | $(SR)/lib/libstdc++.a
	@mkdir -p $(dir $@)
	$(CC) $(CORE_CFLAGS) -c -o $@ $<

$(B)/munt/%.o: $(MUNT)/%.cpp $(MUNT_CONFIG) $(B)/flags | $(SR)/lib/libstdc++.a
	@mkdir -p $(dir $@)
	$(CXX) $(MUNT_CXXFLAGS) -c -o $@ $<

# the guest kit's link recipe (the DOSBox-X core's): the large code model's
# --no-relax, the weak pthread pulls libgcc_eh needs, cxxglue for the unwinder
$(B)/core.wbx: $(CORE_OBJS) $(POP2_OBJS) $(MUNT_OBJS)
	$(CXX) -static -no-pie -Wl,--eh-frame-hdr -Wl,-O2 -Wl,--no-relax -Wl,-z,stack-size=8388608 \
		-T $(MB)/source/guest/linkscript.T \
		-Wl,-u,pthread_once -Wl,-u,pthread_cond_wait -Wl,-u,pthread_cond_broadcast -Wl,-u,pthread_key_create \
		-o $@.tmp $^ $(MBUILD)/source/guest/cxxglue.c.o $(MBUILD)/source/guest/emulibc.c.o $(WRAP_FLAGS) \
		-L$(SR)/lib -lstdc++ -lm -lgcc -lgcc_eh -lc
	# an aarch64 guest reads its thread pointer from the machine's slot
	# (miniBox's MACHINE-SPEC, "aarch64"): the host refuses one not rewritten so
	if [ $(ARCH) = aarch64 ]; then python3 $(MB)/source/guest/wbx-tp-rewrite.py $@.tmp; fi
	sh $(MB)/source/guest/check-wbx.sh $@.tmp
	mv $@.tmp $@

clean:
	rm -rf $(B)

.PHONY: all clean
