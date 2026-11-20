# The deck panel (#490)

Firmware for the panel that shows DeckBridge's display feed: an Elecrow CrowPanel Advance 7.0-HMI (ESP32-S3-WROOM-1-N16R8, hardware V1.4, 800×480 RGB IPS screen, GT911 touch, 16 MB flash, 8 MB PSRAM).

The default firmware is the deck view (#620): it joins Wi-Fi, listens for the feed on UDP port 9100 and shows the deck in front, its number in the deck color, with the title and artist. With no feed for 3 seconds it shows the waiting screen, with the panel's address and port to type into DeckBridge's Settings. It only listens: it never sends anything (ADR 0011). The test screen (#615) is a separate build, `crowpanel-test`.

## Layout

| Path | What | Built for |
|---|---|---|
| `lib/` | Portable code: no Arduino, no LVGL. `deck_core` (reads the feed, decides the screen), `feed_drain` (datagrams into the core), `font_fallback` (text the font can draw), `test_pattern` (the test screen's bars), `backlight` (the companion chip's bytes per board revision), `gt911` (touch decoding) | The Mac (tests) and the panel |
| `test/` | Host tests for `lib/`, with Unity | The Mac |
| `src/` | The board layer: pins, the companion chip, the RGB panel with LVGL, touch, LVGL's heap in PSRAM, Wi-Fi (`wifi_link`), the feed's UDP socket (`feed_udp`), the deck and waiting screens (`deck_view`), the test screen and `main.cpp` | The panel only |
| `wifi_secrets.py` | Writes `src/wifi_secrets.h` (never committed) from your Wi-Fi file at build time; `test_wifi_secrets.py` tests it | The Mac |
| `feed/` | The display feed's example messages, shared with DeckBridge's tests | — |

The board layer comes from the owner's phrasedeck firmware. Its board settings follow robominds' Crowpanel-Advance-7.0-HMI-Display, whose MIT notice is in `LICENSE.crowpanel-drivers`.

## Build and test

You need PlatformIO 6.2.0 running on Python 3.10-3.14: the pioarduino ESP32 platform refuses newer Pythons. Homebrew's `platformio` runs on Python 3.15 and can't build it, so install PlatformIO from PyPI on Python 3.13 and use that one (`~/.venvs/pio/bin/pio`, or put `~/.venvs/pio/bin` first on your `PATH`):

```sh
python3.13 -m venv ~/.venvs/pio && ~/.venvs/pio/bin/pip install platformio==6.2.0
```

From the repo root:

```sh
pio test -d tools/deck-panel -e native          # host tests for lib/
python3 -I tools/deck-panel/test_wifi_secrets.py  # the Wi-Fi pre-script
pio run  -d tools/deck-panel -e crowpanel       # the deck view: the panel firmware
pio run  -d tools/deck-panel -e crowpanel-test  # the test screen
```

CI runs all of them in the Deck panel job, whenever `tools/deck-panel/` changes. The first build downloads the platform and toolchain (about 1 GB) and takes a few minutes.

## Wi-Fi

A stopgap until the panel is set up from a phone (#622): the network's name and password go into the firmware when it's built. Put them in `~/.config/deckbridge/panel-wifi.ini`, outside the repo (or point `DECK_PANEL_WIFI_INI` at another file):

```ini
[wifi]
ssid = Your network
password = your password
```

No quotes: the spaces around `=` are dropped and quotes would be kept as part of the value. Make the file readable only by you (`chmod 600`).

Each build of `crowpanel` writes `src/wifi_secrets.h` from it (mode 600, gitignored) and prints only `wifi_secrets: set` or `none`, never the values. **Never commit either file.** The password ends up in the firmware image, so anyone with the panel or the `.bin` can read it out. Change the file and build again to move the panel to another network.

Without the file (as in CI), the panel builds with no Wi-Fi and says "Wi-Fi isn't set".

## Flash

The panel's USB serial chip is a CH340K (1A86:7522), and the Mac needs WCH's CH34x driver for it. With the driver installed, the port is `/dev/cu.wchusbserial210`:

```sh
pio run -d tools/deck-panel -e crowpanel -t upload --upload-port /dev/cu.wchusbserial210
```

This writes the bootloader, the partition table (Arduino's stock `default_16MB` layout, `partitions.csv`), `boot_app0` and the app.

**Restore.** The whole 16 MB flash, as it was before our first write, is backed up in a private folder outside the repo (#615). To put it back:

```sh
esptool.py --port /dev/cu.wchusbserial210 write_flash 0 <the backup file>
```

## What the deck view shows

- At boot, before Wi-Fi: "Joining Wi-Fi..." (or "Wi-Fi isn't set" in a build without credentials).
- On Wi-Fi with no feed: "Waiting for DeckBridge" and the panel's address and port, e.g. `192.168.1.40  port 9100`. Type those into DeckBridge's Settings, Display feed.
- With the feed: `Deck 1`-`Deck 4` top left in the deck color, the title below in white and the artist in gray. Long text ends in `...`. Until #621's fonts, accented letters lose their accents and other non-Latin characters show as `?`.
- No feed for 3 seconds, or Wi-Fi lost: the waiting screen again. Wi-Fi rejoins by itself.
- On serial: `deck panel: joining Wi-Fi`, then `on Wi-Fi at <address>, feed port 9100` and `feed port 9100 open`. The network's name is never logged.

## What the test screen shows

Build and flash `crowpanel-test` (`-e crowpanel-test` in the commands above) for it.

- Eight full-height bars across the whole 800 px. From left to right: red, green, blue, white, black, mid gray, dark gray, light gray. If red and blue are swapped, the bus order is wrong.
- A black band across the middle. On it is the line `DeckBridge deck panel  800x480  V1.4  build <short SHA>` (with `-dirty` if built from uncommitted changes), and below it the last touch, as `Touch at x, y`.
- The backlight comes on after the first frame is drawn, so nothing flashes at boot.
- On serial (115200 baud): `deck panel: boot, build <SHA>`, the companion chip and display lines, `touch: GT911 at 0x5D`, then `deck panel: test screen up`. The test screen has no Wi-Fi.

**What only the panel can show:** colors, the full area, the backlight, touch, tearing, Wi-Fi and the feed. None of these has a host test.
