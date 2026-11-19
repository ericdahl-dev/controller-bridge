# The drawn display on the chip: our block and its hook (#467)

The same C sources the Mac tests (`src/`) run on the display chip (`wd`, STM32F429). They are built into one raw block that fills the stock 00.50 image's own padding, `0x0807DC00`-`0x0807FFDF` (9,184 bytes, inside the image's CRC; #466). The hook patch (`tools/lc6000-firmware/patches/wd-00.50-drawn-hook.patch`) makes two stock instructions call the block's entries.

Nothing here is flashed. Nothing here holds vendor bytes: the stock addresses come from the static analysis on #466.

## Build

```sh
make -C tools/lc6000-display-fw arm              # build/arm/block.bin, 9,184 bytes, with the marker last
make -C tools/lc6000-display-fw arm-test PYTHON=<python with unicorn>
make -C tools/lc6000-display-fw arm ARM_DRAW=0   # the hook path alone, inert (if drawing ever doesn't fit)
```

- The build prints how much of the padding is used. If the code doesn't fit below the marker, the link fails with "our code doesn't fit in the wd padding". Nothing is ever placed above `0x08080000`.
- **Toolchain, pinned:** `arm-none-eabi-gcc` 16.2.0 with GNU Binutils 2.47 (Homebrew, macOS). CI builds with Ubuntu's `gcc-arm-none-eabi` package.
- **Reproducible per toolchain version:** two builds with the same toolchain are byte-identical (a test checks this). Builds from different toolchain versions, for example Mac and CI, are not expected to match.
- There is no C library. `libc_min.c` provides the four functions the sources may use, and `include/string.h` declares them.

## Layout

| Address | What |
|---|---|
| `0x0807DC00` | Command entry (`entry.S`), called from `0x0800F464` |
| `0x0807DC40` | Render entry (`entry.S`), called from `0x08012456` |
| after that | Our code and constants (`hook.c`, `adapter.c`, `src/`) |
| `0x0807FFDC` | The marker word, `"DFW1"`, last |
| `0x2002AE94` | Our state (`hook_state`), in SRAM stock never uses. Nothing zeroes it, so it carries a magic and a check word |

There is no startup code. The link refuses any `.data` or `.bss`.

## The entries

- **Command entry.** It replaces `mov.w r8, #1` at stock's unknown-command fallthrough. It checks the marker, then calls `hook_command(cmd = sl, msg = r7, len = r5)`, then sets `r8 = 1` itself and returns.
  - `r4`, `r5`, `r7`, `sl` and every callee-saved register are kept.
  - The C acts only on our command `0x20`, and only on a whole message: `len + 10` bytes received, with `F7` at `9 + len`. It copies the message, so nothing keeps a pointer into stock's receive buffer.
- **Render entry.** It replaces `bl 0x0800BEA0`. It always calls stock's render, then our tick if the marker is present, and returns `r0 = 0`. A nonzero result would make stock's main loop skip its 40 ms task.
- Before our first valid message since the last reset, the tick touches nothing.

## Resets

Our SRAM state survives a reboot, so the hook has to notice a reset.

- **The witness.** IRQ 0's NVIC priority byte (`0xE000E400`) is cleared by every reset, and stock never writes it: stock sets priorities only for IRQs 77, 88, 90 and SysTick (#466). The hook writes `0xF0` there when it starts. If it later reads 0, the chip was reset, so our state starts fresh: drawn mode off, no frame, one new malloc allowed.
- **The uptime counter.** Stock's SysTick counter `0x20001BA0` (100 µs, zeroed at boot) going backwards is also a reset. The exception is a step back from within 10 s of `0xFFFFFFFF`: that is the counter wrapping after 4.97 days, and the session carries on.

## Frame buffers

- **Visible layer.** Stock sets up a second LTDC layer at boot and never enables it. Its pixels (320 × 240 × 2 + 64 bytes) are already malloc'd; the pointer is at `0x20001DC0`. In drawn mode the adapter makes that layer an opaque RGB565 overlay above stock's layer and copies our frame into it, rotated 180° and centered at (61, 21). Ending drawn mode turns the layer off, and stock's picture underneath is current again.
- **dfw's back buffer.** 198 × 198 × 4 = 156,816 bytes, from one call to stock's malloc (`0x08017860`). The call happens at the first capability ask or begin of each boot, and the buffer is never freed. If the malloc fails, the ask gets no answer, and the app falls back to images.
