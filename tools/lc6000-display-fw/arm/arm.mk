# Our block for the display chip (#467), included by the Makefile. `make arm` builds block.bin for the wd padding at
# 0x0807DC00 with the GNU Arm toolchain (versions pinned in arm/README.md). ARM_DRAW=0 builds the hook path alone,
# inert, for when the drawing code doesn't fit.
ARM_BUILD ?= $(BUILD)/arm
ARM_DRAW ?= 1
# 1 only once the owner's read-only read shows the upper flash exists and is erased (#501, the firmware README's
# "Read-only checks"). Until then block A never reads 0x08080000, so the capability ask gets no answer.
ARM_UPPER_PROVEN ?= 0
ARM_PREFIX ?= arm-none-eabi-
ARM_CPU := -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
ARM_CFLAGS := -std=c99 -Wall -Wextra -Werror -pedantic -Os $(ARM_CPU) -ffreestanding -fno-builtin -fno-common \
	-fno-pic -fno-stack-protector -fno-tree-loop-distribute-patterns -ffunction-sections -fdata-sections \
	-fstack-usage -DHOOK_DRAWING=$(if $(filter 0,$(ARM_DRAW)),0,1) -DHOOK_UPPER_PROVEN=$(ARM_UPPER_PROVEN) \
	-DHOOK_STUB_DRAWING=$(if $(filter stub,$(ARM_DRAW)),1,0)
# ARM_DRAW=1: hook, protocol and drawing. 0: the hook path alone, inert. stub (test builds only): hook and protocol
# with an empty drawing, so the block tests run while the real drawing doesn't fit the padding (#501).
ARM_SRC_DRAW := arm/hook.c arm/upper.c $(if $(filter stub,$(ARM_DRAW)),src/dfw.c arm/test/draw_stub.c,$(SRC))
ARM_C := arm/adapter.c arm/libc_min.c $(if $(filter 0,$(ARM_DRAW)),,$(ARM_SRC_DRAW))
# For the size tests only: one extra C file (absolute path) and extra link flags, to grow a build past its limit.
ARM_EXTRA_C ?=
ARM_EXTRA_LDFLAGS ?=
ARM_OBJ := $(ARM_BUILD)/entry.o $(patsubst %.c,$(ARM_BUILD)/%.o,$(notdir $(ARM_C) $(ARM_EXTRA_C)))

.PHONY: arm
arm: $(ARM_BUILD)/block.bin $(ARM_BUILD)/upper.bin

# The build's flags, ARM_UPPER_PROVEN above all, kept with its outputs (#501). Make doesn't see a variable change,
# and its timestamps here are whole seconds, so when the flags differ from the last build in this directory, that
# build's outputs go and are built again: `make arm` then `make arm ARM_UPPER_PROVEN=1` never leaves the old block A.
# It runs as the makefile is read, before make decides what is up to date.
ARM_FLAGS := $(ARM_CFLAGS) | $(ARM_C) $(ARM_EXTRA_C) | $(ARM_EXTRA_LDFLAGS)
ifneq ($(filter arm arm-test %/block.bin %/upper.bin,$(or $(MAKECMDGOALS),none)),)
$(shell mkdir -p $(ARM_BUILD) && if [ "$$(cat $(ARM_BUILD)/flags.txt 2>/dev/null)" != "$(ARM_FLAGS)" ]; then \
	rm -f $(ARM_BUILD)/block.elf $(ARM_BUILD)/block.bin $(ARM_BUILD)/upper.elf $(ARM_BUILD)/upper.bin; \
	echo "$(ARM_FLAGS)" > $(ARM_BUILD)/flags.txt; fi)
endif

$(ARM_BUILD)/block.elf: $(ARM_C) arm/entry.S arm/block.ld arm/hook.h arm/upper.h arm/include/string.h $(wildcard src/*.h) arm/arm.mk
	@mkdir -p $(ARM_BUILD)
	cd $(ARM_BUILD) && $(ARM_PREFIX)gcc $(ARM_CFLAGS) -I$(CURDIR)/arm/include -I$(CURDIR)/src -I$(CURDIR)/arm -c $(addprefix $(CURDIR)/,$(ARM_C)) $(ARM_EXTRA_C)
	$(ARM_PREFIX)gcc $(ARM_CPU) -c arm/entry.S -o $(ARM_BUILD)/entry.o
	$(ARM_PREFIX)gcc $(ARM_CPU) -nostdlib -nostartfiles -Wl,--gc-sections -Wl,--build-id=none \
		-Wl,-T,arm/block.ld -Wl,-Map,$(ARM_BUILD)/block.map $(ARM_EXTRA_LDFLAGS) -o $@ $(ARM_OBJ) -lgcc
	@# The hook block never links the drawing (#501): it gets the drawing's table from stock, NULL until the drawing
	@# block checks out. Only the stub test build carries an (empty) drawing.
	@if [ "$(ARM_DRAW)" != stub ] && $(ARM_PREFIX)nm $@ | grep -q ' dfw_draw'; then \
		echo "the hook block links the drawing (dfw_draw*); it must take the table from stock" >&2; rm -f $@; exit 1; fi

$(ARM_BUILD)/block.bin: $(ARM_BUILD)/block.elf
	$(ARM_PREFIX)objcopy -O binary --gap-fill 0xFF -j .entry_command -j .entry_render -j .text -j .data \
		-j .marker $< $@
	@test "$$(wc -c < $@ | tr -d ' ')" = 9184 || { echo "block.bin isn't the 9,184-byte padding" >&2; exit 1; }
	@$(ARM_PREFIX)size -A $< | awk '/^\.(entry|text|data|marker)/ {used += $$2} END {printf "block: %d of 9184 bytes used%s\n", used, "$(if $(filter 1,$(ARM_UPPER_PROVEN)),; reads block B at 0x08080000 (ARM_UPPER_PROVEN=1),; never reads block B (ARM_UPPER_PROVEN=0))"}'

# Block B (#501): the drawing for 0x08080000, sectors 8-11. B never calls into block A, whose addresses move from
# build to build: it links its own copy of what the drawing uses from src/ (dfw_stale, say) and of the few C library
# functions; --gc-sections drops the rest, so the protocol itself stays in A. Its header's length and CRC are filled
# in after the link (upper_seal.py), and block A checks both before it calls B.
UPPER_C := arm/upper_header.c arm/libc_min.c $(SRC)
# For the size tests only: one extra C file (absolute path) and extra link flags, to grow B past its limit.
UPPER_EXTRA_C ?=
UPPER_EXTRA_LDFLAGS ?=
UPPER_OBJ := $(patsubst %.c,$(ARM_BUILD)/upper/%.o,$(notdir $(UPPER_C) $(UPPER_EXTRA_C)))

$(ARM_BUILD)/upper.elf: $(UPPER_C) arm/upper.ld arm/upper.h arm/include/string.h $(wildcard src/*.h) arm/arm.mk
	@mkdir -p $(ARM_BUILD)/upper
	cd $(ARM_BUILD)/upper && $(ARM_PREFIX)gcc $(ARM_CFLAGS) -I$(CURDIR)/arm/include -I$(CURDIR)/src -I$(CURDIR)/arm \
		-c $(addprefix $(CURDIR)/,$(UPPER_C)) $(UPPER_EXTRA_C)
	$(ARM_PREFIX)gcc $(ARM_CPU) -nostdlib -nostartfiles -Wl,--gc-sections -Wl,--build-id=none \
		-Wl,-T,arm/upper.ld -Wl,-Map,$(ARM_BUILD)/upper.map $(UPPER_EXTRA_LDFLAGS) -o $@ $(UPPER_OBJ) -lgcc

$(ARM_BUILD)/upper.bin: $(ARM_BUILD)/upper.elf arm/upper_seal.py
	$(ARM_PREFIX)objcopy -O binary -j .upper_header -j .text -j .data $< $@
	@$(PYTHON) -I arm/upper_seal.py $@

# Each block's limit as a check on whichever toolchain runs it (the Mac's and CI's Ubuntu GCC differ in size, #501):
# block A, hook and protocol, and the hook alone, against the 9,184-byte padding; block B, the drawing, against the
# 512 KB upper flash. Any one over fails.
ARM_SIZE_BUILD ?= $(BUILD)/arm-size
ARM_SIZE_UPPER_EXTRA ?=
ARM_SIZE_UPPER_LDFLAGS ?=
.PHONY: arm-size
arm-size:
	@$(ARM_PREFIX)gcc --version | head -1
	@out=$$($(MAKE) -s ARM_BUILD=$(ARM_SIZE_BUILD)/a ARM_DRAW=1 $(ARM_SIZE_BUILD)/a/block.bin) || exit 1; \
		echo "$$out" | sed 's/^block:/block A (hook and protocol):/'
	@out=$$($(MAKE) -s ARM_BUILD=$(ARM_SIZE_BUILD)/hook ARM_DRAW=0 $(ARM_SIZE_BUILD)/hook/block.bin) || exit 1; \
		echo "$$out" | sed 's/^block:/block A (hook only):/'
	@if out=$$($(MAKE) -s ARM_BUILD=$(ARM_SIZE_BUILD)/b UPPER_EXTRA_C="$(ARM_SIZE_UPPER_EXTRA)" \
		UPPER_EXTRA_LDFLAGS="$(ARM_SIZE_UPPER_LDFLAGS)" $(ARM_SIZE_BUILD)/b/upper.bin 2>&1); then \
		echo "$$out" | sed 's/^block B:/block B (drawing):/'; \
	else echo "$$out" >&2; echo "block B (drawing): over the 524288-byte upper flash"; exit 1; fi
