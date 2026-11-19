# LC6000 firmware patch tool

`dfupatch.py` patches the LC6000 PRIME's **jog wheel/display (`wd`)** firmware inside its DfuSe `.dfu` file and fixes both checksums. It is research tooling for #418 (custom firmware). It is not part of the app and isn't for end users.

Python 3, standard library only. Run it with `python3 -I`.

## Rules

- **Never commit or share vendor files or anything built from them.** That covers the stock `.dfu` files, the updater, extracted `.bin` images, dumps and patched `.dfu` files (all inMusic copyright). Only this tool, its tests and **patch descriptions** (addresses plus the few bytes being replaced) go in the repo or in issues. `.gitignore` here blocks `*.dfu`, `*.bin`, `*.hex`, `*.elf` and `*.patched*`, and `apply` refuses to write inside the repository.
- This tool only edits files. It never talks to the hardware. Flashing is a separate step that you do by hand; see the runbook on #431.

## Use

Get the stock `wd` file from your own copy of the updater (`docs/research/*.dmg`, which is gitignored): mount it read-only and copy `jc20_wd_update_00_50_3A7CE2CA.dfu` out of the `.app`'s `Contents/Resources` to a folder **outside the repo**.

Check that the tool understands the file:

```sh
python3 -I tools/lc6000-firmware/dfupatch.py verify ~/lc6000/jc20_wd_update_00_50_3A7CE2CA.dfu
# ok: trailer CRC 0x3A7CE2CA over 0x77fec bytes; a no-op patch reproduces the file bit for bit
```

Write a patch description: one edit per line, `ADDRESS OLD-HEX NEW-HEX`. The address is the absolute flash address (the image starts at `0x08008000`), and `#` starts a comment:

```
# what this changes and why, with the issue number
0x0800XXXX 0f28 1028
```

Apply it, writing the result outside the repo:

```sh
python3 -I tools/lc6000-firmware/dfupatch.py apply ~/lc6000/jc20_wd_update_00_50_3A7CE2CA.dfu my.patch ~/lc6000/wd-patched.dfu
# wrote ~/lc6000/wd-patched.dfu: new trailer CRC 0x........, DfuSe suffix CRC 0x........
```

`apply` refuses, and writes nothing, if:

- the file isn't a one-target, one-element DfuSe file with a good suffix CRC (the stock updater reads the element at a fixed offset, so nothing else would flash correctly);
- the image doesn't end with `EndOfFlashToken`, or it's a `wd` image whose stored trailer CRC doesn't match (see "The `tp` image" below);
- any old bytes don't match what's in the file (wrong image or wrong patch);
- an edit falls outside the image, reaches into the 32-byte trailer, overlaps another edit, or has old and new bytes of different lengths;
- the output already exists, or is inside the repository.

## Placing our block (`place`, #467)

`place` writes a raw block (our drawn-display code, built by `tools/lc6000-display-fw`'s `make arm`) into the `wd` image's own padding: `0x0807DC00`-`0x0807FFDF`, 9,184 bytes that are `0xFF` in stock 00.50 and lie inside the trailer CRC (#466). It then recomputes the trailer CRC and the DfuSe suffix CRC.

```sh
python3 -I tools/lc6000-firmware/dfupatch.py place ~/lc6000/wd-patched.dfu block.bin ~/lc6000/wd-placed.dfu
# wrote ...: N bytes at 0x0807DC00, new trailer CRC 0x........, DfuSe suffix CRC 0x........
```

It refuses, and writes nothing, if the image isn't `wd` or doesn't hold that range, if the block is empty or bigger than 9,184 bytes, if any byte it would write over isn't `0xFF` (wrong image, or a block is already there), or if the output exists or is inside the repository.

## Patches in this folder

Patch descriptions live in `patches/`. Each one is a few bytes for one firmware version; it holds no vendor image.

### `patches/wd-00.50-show-slot-16.patch` (#425)

- **For:** `wd` firmware 00.50 only, the stock file `jc20_wd_update_00_50_3A7CE2CA.dfu` (trailer CRC `0x3A7CE2CA`). `apply` refuses any other image, because the old bytes won't match.
- **What it changes:** one byte. The show command (`0A`) drops any slot index above 15, although uploads (`0E`) take slots 1-16 and the slot table has room for 16. At `0x0800BDA4`, `cmp r0, #0xf` becomes `cmp r0, #0x10` (`0f 28` to `10 28`), so "show 16" works. The tool then rewrites the trailer CRC (to `0x36DF3956`) and the DfuSe suffix CRC.
- **Why slot 16 is safe to show:** slot N is table entry N + 29, and the table has 46 entries (0-45), so slot 16 is the last entry, set up at boot exactly like slots 1-15. Nothing else in the firmware compares a slot index with 15 or loops over the slots. The details are on #425.
- **Status: unproven on hardware.** Nobody has flashed it. Whether the bootloader accepts a patched image at all is what the flash tests in #435 will show. Follow the runbook on #431, and flash the stock image by the same route first.

```sh
python3 -I tools/lc6000-firmware/dfupatch.py apply ~/lc6000/jc20_wd_update_00_50_3A7CE2CA.dfu \
  tools/lc6000-firmware/patches/wd-00.50-show-slot-16.patch ~/lc6000/jc20_wd_00_50_show16.dfu
# wrote ...: new trailer CRC 0x36DF3956, DfuSe suffix CRC 0x5F321B11
```

### `patches/wd-00.50-vos-scale-1.patch` (#438)

- **For:** `wd` firmware 00.50 only, the stock file `jc20_wd_update_00_50_3A7CE2CA.dfu` (trailer CRC `0x3A7CE2CA`). `apply` refuses any other image, because the old bytes won't match.
- **What it changes:** one byte. The clock setup lowers the STM32F429's core regulator to Scale 2 (`PWR_CR.VOS = 0b10`) and then runs the chip at 180 MHz with over-drive on. ST rates Scale 2 with over-drive to 168 MHz; only Scale 1 with over-drive is rated to 180 MHz. At `0x0800A69E`, `orr r0, r0, #0x8000` becomes `orr r0, r0, #0xc000` (`40 f4 00 40` to `40 f4 40 40`), so VOS stays at `0b11`, Scale 1, the chip's reset value. Nothing else in the image writes VOS.
- **What it costs:** the core runs about 0.06 V higher (typical 1.26 V to 1.32 V), so the chip draws a little more current. Clock speed and all timing stay the same.
- **Status: unproven on hardware.** Nobody has flashed it. Nobody has read `PWR_CR` on a running unit either, so the stock setting is known only from the code. It is not shown to fix the display drop-outs in #428. Whether the bootloader accepts a patched image at all is what the flash tests in #435 will show. Follow the runbook on #431, flash the stock image by the same route first, and have an SWD probe working before you try. The evidence is on #438.

### `patches/tp-00.31-no-deck-select-on-hello.patch` (#439)

- **For:** `tp` (top panel) firmware 00.31 only, the stock file `jc20_tp_update_00_31_120936.dfu`. `apply` refuses any other image, because the old bytes won't match.
- **What it changes:** one byte of start-up data, no code. On a freshly powered unit a host hello (`F0 00 20 7F 01 F7`) puts the top panel into "pick a deck" mode: pads 1-4 blink and the other controls are muted until a pad is pressed. The hello handler (`0x0800C280`) does that only while the deck byte at `0x20000703` is `0xFF`, "no deck picked yet", its power-on value. That value is a literal in the compressed start-up data, at `0x08015CDD`; the patch makes it `0x00`, deck 1. The line covers the whole 4-byte token at `0x08015CDB` (`0a 14 ff 64` to `0a 14 00 64`).
- **What the host then sees after a hello:** ch16 note 55 on (`9F 37 7F`), note 51 at 127 on ch1 (`90 33 7F`), ch16 note 55 off (`8F 37 00`). That is what the stock firmware sends on a hello once deck 1 has been picked. No blinking, no pad press.
- **What stays the same:** with no host the unit already sends on ch1, and still does. Shift + deck select still opens deck select, and a pad still switches deck; pad 1 shows as the current deck from the start. A hello after you picked another deck reports that deck, as before. Goodbye (`F0 00 20 7F 02 F7`) is untouched.
- **Status: proven on the owner's unit (2026-11-19).** Flashed with `dfu-util` from ST's ROM bootloader; the read-back matched the image. After power-on and a host hello, the unit sent the layer 1 signal 24 ms later with no pad press and no blinking; on stock it waits for a pad. Manual deck select still worked. Restoring stock with Denon's updater (bootloader mode) brought the blink back. Evidence on #439.
- **Way back:** hold BACK + FWD + VINYL at power-on (ST's ROM bootloader, which nothing in flash can remove), then run Denon's updater to restore stock 00.31.

```sh
python3 -I tools/lc6000-firmware/dfupatch.py apply ~/lc6000/jc20_tp_update_00_31_120936.dfu \
  tools/lc6000-firmware/patches/tp-00.31-no-deck-select-on-hello.patch ~/lc6000/jc20_tp_00_31_no_deck_select.dfu
# wrote ...: tp image, trailer unchanged (no trailer CRC), DfuSe suffix CRC 0x7AA5BB38
```

## Flash day kit (#435)

Three pieces for the first real flash of the display chip, all run **by the unit's owner**, never by an agent:

- `flash-day.sh`: a step-by-step wizard. It checks the stock file, puts the display chip into update mode, lists what `dfu-util` sees (exactly one device, or it stops) and backs up the settings sector and the app (read-only). Then **Denon's own updater does the stock flash**: on this unit it flashes a chip that's in update mode and refuses a running, current one (seen 2026-11-19 on the top panel chip). If the updater won't, the wizard offers the same stock file through `dfu-util`, after you type `FLASH`, and reads it back. Then you power-cycle and it checks the display's MIDI port returns. A patched image is an optional last step, off by default: it goes through `dfu-util`, only after the chip is confirmed to hold stock, and is read back and compared. Everything it saves goes to `~/lc6000` (or `$LC6000_WORK`), outside the repo.
- `enter-update-mode.swift`: sends the stock updater's one "enter update mode" SysEx to the unit's WD port. `selftest` and `check` send nothing; `send` needs `--yes-enter-update-mode` and exactly one WD port.
- `dfupatch.py compare <file.dfu> <readback.bin>`: checks a raw read-back of the app area against a `.dfu`'s image and says where the first difference is.

```sh
brew install dfu-util
tools/lc6000-firmware/flash-day.sh
```

**Unproven on hardware** until #435 is done: whether Denon's bootloader allows reading flash, whether a power cycle clears its update-mode flag, and whether it accepts a changed image. The wizard stops at each surprise and prints the way back (power cycle; then update mode plus Denon's own updater; then SWD, #433). A patched image still reports version 00.50, so the updater calls a running patched unit current: put the chip in update mode first. Have an ST-Link on the desk first. Never run Denon's updater "to look": it starts erasing as soon as it finds the unit.

The top panel chip needs none of this: hold BACK + FWD + VINYL at power-on and it enters ST's ROM bootloader (seen on hardware, #432); a power cycle leaves it.

The tests (`test_flash_day.py`) guard the kit's shape without hardware: one write, behind the typed word; no mass-erase, unprotect, option-byte or bootloader-sector access; reads only in the settings and app sectors.

## What it recomputes

1. **The `wd` trailer CRC.** The last 32 bytes of the image are a trailer: version, `0xDEADBEEF`, the number of bytes covered (element size − 20), the CRC, then `EndOfFlashToken\0`. The CRC is the **STM32 hardware CRC unit**'s algorithm (CRC-32, polynomial `0x04C11DB7`, init `0xFFFFFFFF`, little-endian 32-bit words, no reflection, no final XOR) over element bytes `0` to `0x77FEB`, so it includes the length field. On the stock image it gives `0x3A7CE2CA`, the hex in the file name.
2. **The DfuSe suffix CRC.** zlib CRC-32 over the whole file except its last 4 bytes, XORed with `0xFFFFFFFF`.

Nothing else changes: every byte outside the patched ranges, the trailer CRC and the suffix CRC stays as it was.

## Verification

- `python3 -I -m unittest discover tools/lc6000-firmware` runs the tests. They build their own synthetic DfuSe files, so they need no vendor data; CI runs them in the Site check job. They pin the CRC to a known answer (one word `0x12345678` gives `0xDF8A8A2B`), check that a no-op patch reproduces the input bit for bit, and that a one-byte patch changes only that byte and the two CRCs.
- `verify` on your own stock `wd` file must print `0x3A7CE2CA` and report a bit-for-bit round trip. If it doesn't, stop: your file isn't the one this tool was written against.

## The `tp` image

The **top panel (`tp`)** image can be patched too. Its trailer has no magic, length or CRC: a version, one word (`0x0001D868`, also in the file name) and `EndOfFlashToken\0`.

The unit's own startup stage was read out through ST's ROM bootloader and analyzed (#432, #434). Before it starts the app it checks **one thing**: the last 16 bytes of the image are `EndOfFlashToken\0`. There is no checksum, length, version or vector check, and the `0x0001D868` word is never read (its meaning is still unknown).

So for a `tp` image the tool:

- tells the chip from the trailer (`wd` has the `0xDEADBEEF` magic; `tp` doesn't);
- applies the edits, refusing any that reach into the last 32 bytes;
- leaves the trailer exactly as it was, and recomputes only the DfuSe suffix CRC.

`verify` on the stock `tp` file prints `ok: tp image, EndOfFlashToken present; it has no checksum …`.

`tp` is also the safe chip to experiment on: BACK + FWD + VINYL at power-on enters ST's ROM bootloader, which nothing in flash can remove; flash isn't read-protected; and Denon's updater restores stock from that mode (all seen on hardware, 2026-11-19). A patched `tp` image boots: a one-byte test image and the no-deck-select patch were both flashed, verified by read-back and run on the owner's unit (2026-11-19, #435, #439).

## What isn't known yet

The CRC recipe reproduces the stock trailer, but nobody has seen the bootloader **enforce** it. The apps never touch the CRC unit and the updater never computes it, so the bootloader is the likely checker. That is inferred, not proven. #434 (bootloader analysis) and #435 (flash test matrix) will settle it.
