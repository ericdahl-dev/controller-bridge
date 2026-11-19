# Our block for the display chip (#467), included by the Makefile. `make arm` builds block.bin for the wd padding at
# 0x0807DC00 with the GNU Arm toolchain (versions pinned in arm/README.md). ARM_DRAW=0 builds the hook path alone,
# inert, for when the drawing code doesn't fit.
ARM_BUILD ?= $(BUILD)/arm
ARM_DRAW ?= 1
ARM_PREFIX ?= arm-none-eabi-
ARM_CPU := -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
ARM_CFLAGS := -std=c99 -Wall -Wextra -Werror -pedantic -Os $(ARM_CPU) -ffreestanding -fno-builtin -fno-common \
	-fno-pic -fno-stack-protector -fno-tree-loop-distribute-patterns -ffunction-sections -fdata-sections \
	-fstack-usage -DHOOK_DRAWING=$(ARM_DRAW)
ARM_C := arm/adapter.c arm/libc_min.c $(if $(filter 1,$(ARM_DRAW)),arm/hook.c $(SRC))
ARM_OBJ := $(ARM_BUILD)/entry.o $(patsubst %.c,$(ARM_BUILD)/%.o,$(notdir $(ARM_C)))

.PHONY: arm
arm: $(ARM_BUILD)/block.bin

$(ARM_BUILD)/block.elf: $(ARM_C) arm/entry.S arm/block.ld arm/hook.h arm/include/string.h $(wildcard src/*.h) arm/arm.mk
	@mkdir -p $(ARM_BUILD)
	cd $(ARM_BUILD) && $(ARM_PREFIX)gcc $(ARM_CFLAGS) -I$(CURDIR)/arm/include -I$(CURDIR)/src -I$(CURDIR)/arm -c $(addprefix $(CURDIR)/,$(ARM_C))
	$(ARM_PREFIX)gcc $(ARM_CPU) -c arm/entry.S -o $(ARM_BUILD)/entry.o
	$(ARM_PREFIX)gcc $(ARM_CPU) -nostdlib -nostartfiles -Wl,--gc-sections -Wl,--build-id=none \
		-Wl,-T,arm/block.ld -Wl,-Map,$(ARM_BUILD)/block.map -o $@ $(ARM_OBJ) -lgcc

$(ARM_BUILD)/block.bin: $(ARM_BUILD)/block.elf
	$(ARM_PREFIX)objcopy -O binary --gap-fill 0xFF -j .entry_command -j .entry_render -j .text -j .data \
		-j .marker $< $@
	@test "$$(wc -c < $@ | tr -d ' ')" = 9184 || { echo "block.bin isn't the 9,184-byte padding" >&2; exit 1; }
	@$(ARM_PREFIX)size -A $< | awk '/^\.(entry|text|data|marker)/ {used += $$2} END {printf "block: %d of 9184 bytes used\n", used}'
