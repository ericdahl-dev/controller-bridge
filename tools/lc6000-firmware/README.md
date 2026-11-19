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
- the image's trailer isn't the `wd` CRC trailer, or its stored CRC doesn't match (see the `tp` limitation below);
- any old bytes don't match what's in the file (wrong image or wrong patch);
- an edit falls outside the image, reaches into the 32-byte trailer, overlaps another edit, or has old and new bytes of different lengths;
- the output already exists, or is inside the repository.

## Flash day kit (#435)

Three pieces for the first real flash of the display chip, all run **by the unit's owner**, never by an agent:

- `flash-day.sh`: a step-by-step wizard. It checks the stock file, puts the display chip into update mode, lists what `dfu-util` sees (exactly one device, or it stops), backs up the settings sector and the app (read-only), flashes the **stock** image over itself after you type `FLASH`, reads it back and compares, then has you power-cycle and checks the display's MIDI port returns. A patched image is an optional last step, off by default. Everything it saves goes to `~/lc6000` (or `$LC6000_WORK`), outside the repo.
- `enter-update-mode.swift`: sends the stock updater's one "enter update mode" SysEx to the unit's WD port. `selftest` and `check` send nothing; `send` needs `--yes-enter-update-mode` and exactly one WD port.
- `dfupatch.py compare <file.dfu> <readback.bin>`: checks a raw read-back of the app area against a `.dfu`'s image and says where the first difference is.

```sh
brew install dfu-util
tools/lc6000-firmware/flash-day.sh
```

**Unproven on hardware** until #435 is done: whether Denon's bootloader allows reading flash, whether a power cycle clears its update-mode flag, and whether it accepts a changed image. The wizard stops at each surprise and prints the way back (power cycle, then Denon's own updater, then SWD, #433). Have an ST-Link on the desk first. Never run Denon's updater "to look": it starts erasing as soon as it finds the unit.

The top panel chip needs none of this: hold BACK + FWD + VINYL at power-on and it enters ST's ROM bootloader (seen on hardware, #432); a power cycle leaves it.

The tests (`test_flash_day.py`) guard the kit's shape without hardware: one write, behind the typed word; no mass-erase, unprotect, option-byte or bootloader-sector access; reads only in the settings and app sectors.

## What it recomputes

1. **The `wd` trailer CRC.** The last 32 bytes of the image are a trailer: version, `0xDEADBEEF`, the number of bytes covered (element size − 20), the CRC, then `EndOfFlashToken\0`. The CRC is the **STM32 hardware CRC unit**'s algorithm (CRC-32, polynomial `0x04C11DB7`, init `0xFFFFFFFF`, little-endian 32-bit words, no reflection, no final XOR) over element bytes `0` to `0x77FEB`, so it includes the length field. On the stock image it gives `0x3A7CE2CA`, the hex in the file name.
2. **The DfuSe suffix CRC.** zlib CRC-32 over the whole file except its last 4 bytes, XORed with `0xFFFFFFFF`.

Nothing else changes: every byte outside the patched ranges, the trailer CRC and the suffix CRC stays as it was.

## Verification

- `python3 -I -m unittest discover tools/lc6000-firmware` runs the tests. They build their own synthetic DfuSe files, so they need no vendor data; CI runs them in the Site check job. They pin the CRC to a known answer (one word `0x12345678` gives `0xDF8A8A2B`), check that a no-op patch reproduces the input bit for bit, and that a one-byte patch changes only that byte and the two CRCs.
- `verify` on your own stock `wd` file must print `0x3A7CE2CA` and report a bit-for-bit round trip. If it doesn't, stop: your file isn't the one this tool was written against.

## The `tp` limitation

The **top panel (`tp`)** image is refused, and there is no option to override that. Its trailer has no magic or length field, and its one value (`0x0001D868`, also in its file name) is **undecoded**. A patched `tp` image would keep a stale value there, and whether the `tp` bootloader checks it is unknown. Until a bootloader dump (#432, #433, #434) shows what that field is, `tp` patches can't be made safe, so this tool won't make them.

## What isn't known yet

The CRC recipe reproduces the stock trailer, but nobody has seen the bootloader **enforce** it. The apps never touch the CRC unit and the updater never computes it, so the bootloader is the likely checker. That is inferred, not proven. #434 (bootloader analysis) and #435 (flash test matrix) will settle it.
