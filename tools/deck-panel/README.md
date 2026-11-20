# The deck panel (#490)

Firmware for the panel that shows DeckBridge's display feed: an Elecrow CrowPanel Advance 7.0-HMI (ESP32-S3-WROOM-1-N16R8, hardware V1.4, 800×480 RGB IPS screen, GT911 touch, 16 MB flash, 8 MB PSRAM).

Today it draws a test screen (#615). The deck view comes with the portable core (#619).

## Layout

| Path | What | Built for |
|---|---|---|
| `lib/` | Portable code: no Arduino, no LVGL. `test_pattern` (the test screen's bars), `backlight` (the companion chip's bytes per board revision), `gt911` (touch decoding) | The Mac (tests) and the panel |
| `test/` | Host tests for `lib/`, with Unity | The Mac |
| `src/` | The board layer: pins, the companion chip, the RGB panel with LVGL, touch, LVGL's heap in PSRAM, and `main.cpp` | The panel only |
| `feed/` | The display feed's example messages, shared with DeckBridge's tests | — |

The board layer comes from the owner's phrasedeck firmware. Its board settings follow robominds' Crowpanel-Advance-7.0-HMI-Display, whose MIT notice is in `LICENSE.crowpanel-drivers`.

## Build and test

You need PlatformIO 6.2.0 running on Python 3.10-3.14: the pioarduino ESP32 platform refuses newer Pythons. Homebrew's `platformio` runs on Python 3.15 and is refused ("Python version must be 3.10 … 3.14"), so install PlatformIO from PyPI on a supported Python. A venv on Python 3.13 builds and uploads at the ini's 921,600 baud:

```sh
python3.13 -m venv ~/.venvs/pio && ~/.venvs/pio/bin/pip install platformio==6.2.0
```

From the repo root:

```sh
pio test -d tools/deck-panel -e native     # host tests for lib/
pio run  -d tools/deck-panel -e crowpanel  # the panel firmware
```

CI runs both in the Deck panel job, whenever `tools/deck-panel/` changes. The first build downloads the platform and toolchain (about 1 GB) and takes a few minutes.

## Flash

The panel's USB serial chip is a CH340K (1A86:7522), and the Mac needs WCH's CH34x driver for it. With the driver installed, the port is `/dev/cu.wchusbserial210`:

```sh
pio run -d tools/deck-panel -e crowpanel -t upload --upload-port /dev/cu.wchusbserial210
```

**If the port fails with `tcsetattr: Invalid argument`**, WCH's driver is stuck. This happens after the panel re-enumerates, for example after the Mac sleeps or another USB device is replugged. Unplug the panel and plug it back in, then upload again.

This writes the bootloader, the partition table (Arduino's stock `default_16MB` layout, `partitions.csv`), `boot_app0` and the app.

**Restore.** The whole 16 MB flash, as it was before our first write, is backed up in a private folder outside the repo (#615). To put it back:

```sh
esptool.py --port /dev/cu.wchusbserial210 write_flash 0 <the backup file>
```

## What the test screen shows

- Eight full-height bars across the whole 800 px. From left to right: red, green, blue, white, black, mid gray, dark gray, light gray. If red and blue are swapped, the bus order is wrong.
- A black band across the middle. On it is the line `DeckBridge deck panel  800x480  V1.4  build <short SHA>` (with `-dirty` if built from uncommitted changes), and below it the last touch, as `Touch at x, y`.
- The backlight comes on after the first frame is drawn, so nothing flashes at boot.
- On serial (115200 baud): `deck panel: boot, build <SHA>`, the companion chip and display lines, `touch: GT911 at 0x5D`, then `deck panel: test screen up`.

**What only the panel can show:** colors, the full area, the backlight, touch and tearing. None of these has a host test.
