# Our block for the display chip (#467), included by the Makefile. `make arm` builds block.bin for the wd padding at
# 0x0807DC00 with the GNU Arm toolchain (versions pinned in arm/README.md). ARM_DRAW=0 builds the hook path alone,
# inert, for when the drawing code doesn't fit.
ARM_BUILD ?= $(BUILD)/arm
ARM_DRAW ?= 1
ARM_PREFIX ?= arm-none-eabi-
ARM_CPU := -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
ARM_CFLAGS := -std=c99 -Wall -Wextra -Werror -pedantic -Os $(ARM_CPU) -ffreestanding -fno-builtin -fno-common \
	-fno-pic -fno-stack-protector -fno-tree-loop-distribute-patterns -ffunction-sections -fdata-sections \
	-fstack-usage -DHOOK_DRAWING=$(if $(filter 0,$(ARM_DRAW)),0,1) \
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
arm: $(ARM_BUILD)/block.bin

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
	@$(ARM_PREFIX)size -A $< | awk '/^\.(entry|text|data|marker)/ {used += $$2} END {printf "block: %d of 9184 bytes used\n", used}'

# The 9,184-byte limit as a check on whichever toolchain runs it (the Mac's and CI's Ubuntu GCC differ in size). It
# builds the hook-only block, which must fit, and the block with drawing, whose size is information only: drawing
# moves to its own block at 0x08080000 (#501), so drawing PRs don't fail CI on the padding's size.
ARM_SIZE_BUILD ?= $(BUILD)/arm-size
ARM_SIZE_DRAW_EXTRA ?=
ARM_SIZE_DRAW_LDFLAGS ?=
.PHONY: arm-size
arm-size:
	@$(ARM_PREFIX)gcc --version | head -1
	@if out=$$($(MAKE) -s ARM_BUILD=$(ARM_SIZE_BUILD)/draw ARM_DRAW=1 ARM_EXTRA_C="$(ARM_SIZE_DRAW_EXTRA)" \
		ARM_EXTRA_LDFLAGS="$(ARM_SIZE_DRAW_LDFLAGS)" $(ARM_SIZE_BUILD)/draw/block.bin 2>&1); then \
		echo "$$out" | sed 's/^block:/block (with drawing):/'; \
	else echo "block (with drawing): over the 9184-byte padding; informational until #501"; fi
	@out=$$($(MAKE) -s ARM_BUILD=$(ARM_SIZE_BUILD)/proto ARM_DRAW=stub $(ARM_SIZE_BUILD)/proto/block.bin) || exit 1; \
		echo "$$out" | sed 's/^block:/block (hook and protocol):/'
	@out=$$($(MAKE) -s ARM_BUILD=$(ARM_SIZE_BUILD)/hook ARM_DRAW=0 $(ARM_SIZE_BUILD)/hook/block.bin) || exit 1; \
		echo "$$out" | sed 's/^block:/block (hook only):/'
