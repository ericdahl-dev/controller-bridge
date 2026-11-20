# The deck panel (#490)

Firmware for the panel that shows DeckBridge's display feed: an Elecrow CrowPanel Advance 7.0-HMI (ESP32-S3-WROOM-1-N16R8, hardware V1.4, 800×480 RGB IPS screen, GT911 touch, 16 MB flash, 8 MB PSRAM).

The default firmware is the deck view (#620): it joins Wi-Fi, listens for the feed on UDP port 9100 and shows the deck in front: its number in the deck color, title, artist, key, BPM, tempo, times, progress, beat, phase, level and lamps (#621). With no feed for 3 seconds it shows the waiting screen, with the panel's address and port to type into DeckBridge's Settings. It only listens: it never sends anything (ADR 0011). The test screen (#615) is a separate build, `crowpanel-test`.

## Layout

| Path | What | Built for |
|---|---|---|
| `lib/` | Portable code: no Arduino, no LVGL. `deck_core` (reads the feed, decides the screen), `feed_drain` (datagrams into the core), `font_fallback` (text the font can draw), `test_pattern` (the test screen's bars), `backlight` (the companion chip's bytes per board revision), `gt911` (touch decoding) | The Mac (tests) and the panel |
| `test/` | Host tests for `lib/`, with Unity | The Mac |
| `src/` | The board layer: pins, the companion chip, the RGB panel with LVGL, touch, LVGL's heap in PSRAM, Wi-Fi (`wifi_link`), the feed's UDP socket (`feed_udp`), the deck and waiting screens (`deck_view`), the test screen and `main.cpp` | The panel only |
| `wifi_secrets.py` | Writes `src/wifi_secrets.h` (never committed) from your Wi-Fi file at build time; `test_wifi_secrets.py` tests it | The Mac |
| `feed/` | The display feed's example messages, shared with DeckBridge's tests | — |
| `fonts/` | `make_fonts.sh`, which converts Geist into `src/fonts/` | The Mac |

The board layer comes from the owner's phrasedeck firmware. Its board settings follow robominds' Crowpanel-Advance-7.0-HMI-Display, whose MIT notice is in `LICENSE.crowpanel-drivers`.

## Build and test

You need PlatformIO 6.2.0 running on Python 3.10-3.14: the pioarduino ESP32 platform refuses newer Pythons. Homebrew's `platformio` runs on Python 3.15 and is refused ("Python version must be 3.10 … 3.14"), so install PlatformIO from PyPI on Python 3.13 and use that one (`~/.venvs/pio/bin/pio`, or put `~/.venvs/pio/bin` first on your `PATH`). It builds and uploads at the ini's 921,600 baud:

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

The panel joins 2.4 GHz networks only. An iPhone hotspot needs **Maximize Compatibility** on (Settings › Personal Hotspot); on 5 GHz the panel stays at "Joining Wi-Fi…" forever, which is also what a wrong password looks like.

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

## What the deck view shows

- At boot, before Wi-Fi: "Joining Wi-Fi..." (or "Wi-Fi isn't set" in a build without credentials).
- On Wi-Fi with no feed: "Waiting for DeckBridge" and the panel's address and port, e.g. `192.168.1.40  port 9100`. Type those into DeckBridge's Settings, Display feed.
- With the feed: the deck screen below. Long titles and artists end in `…`. Characters outside the fonts (see Fonts) show as `?`.
- No feed for 3 seconds, or Wi-Fi lost: the waiting screen again. Wi-Fi rejoins by itself.
- On serial: `deck panel: joining Wi-Fi`, then `on Wi-Fi at <address>, feed port 9100` and `feed port 9100 open`. The network's name is never logged.

## The deck screen

800×480, black, every object at a fixed place and size (`src/deck_view.cpp`):

| Where (x, y, px) | What |
|---|---|
| 24, 12 | The deck number, `1`-`4`, in Geist Mono 64, in the deck color (white if it has none) |
| 100, 16, 676 wide | The title in Geist SemiBold 36, up to two lines, and the artist under it in gray Geist 24, one line |
| y 146 | `Key`, `BPM` and `Tempo` in gray, each value in Geist Mono 32 |
| y 190 | Elapsed (left) and remaining (right, `-m:ss`) in Geist Mono 64 |
| y 280, 704×36 | The progress bar: light gray fill, red for the track's last 30 seconds |
| y 328 | The beat in the bar: four blocks, the current one in the deck color |
| y 366, 704×28 | The phase bar: a center mark and a white marker; no marker while the phase is unknown |
| y 410 | Lamps `PLAY` (green), `CUE` (orange), `SYNC` (blue), `MASTER` (yellow), `LOOP` with its length (cyan): lit is the color with black text, unlit dark gray |
| x 748, 28×310 | The level meter, green from the bottom |

An empty deck shows its number and "No track loaded", with every other field blank, the bars empty and the lamps off. The waiting screen is #620's: a headline and the address, centered.

Each feed update redraws only the widgets whose value changed. Progress, phase and level move a plain box, and only when a whole pixel changes, so their 30 updates a second redraw a strip, never the screen.

## Fonts

[Geist and Geist Mono](https://github.com/vercel/geist-font), the app's fonts (`App/Fonts/`), under the SIL Open Font License 1.1: `src/fonts/Geist-OFL.txt`. Converted to LVGL C files in `src/fonts/` with lv_font_conv 1.5.3, 4 bits per pixel, uncompressed, covering printable ASCII, U+00A0-U+017F and `…`: the ranges `lib/font_fallback` passes through. Change both together.

To regenerate (needs Node):

```sh
tools/deck-panel/fonts/make_fonts.sh
```

| Font | Used for | Flash |
|---|---|---|
| `geist_regular_24` | Artist, names, lamps, waiting detail | 40 KB |
| `geist_semibold_36` | Title, waiting headline | 89 KB |
| `geist_mono_medium_32` | Key, BPM, tempo | 66 KB |
| `geist_mono_semibold_64` | Deck number, elapsed, remaining | 242 KB |

The deck view no longer uses Montserrat 20, 28 or 48; the test screen still has 20 and 28, and LVGL keeps 14 as its default. Together 438 KB of flash, about 287 KB more than the Montserrat sizes they replace. Geist has no glyph for 12 of the range's characters (Geist Mono 14), so the script draws them as their base letter: the soft hyphen as `-`, Ĕĕ Ĭĭ Ŏŏ without the breve, ĸ as `k`, Ŀŀ as `Ll`, ŉ as `n`, ſ as `s`, and in Mono Ĳĳ as `Ii`.

## What the test screen shows

Build and flash `crowpanel-test` (`-e crowpanel-test` in the commands above) for it.

- Eight full-height bars across the whole 800 px. From left to right: red, green, blue, white, black, mid gray, dark gray, light gray. If red and blue are swapped, the bus order is wrong.
- A black band across the middle. On it is the line `DeckBridge deck panel  800x480  V1.4  build <short SHA>` (with `-dirty` if built from uncommitted changes), and below it the last touch, as `Touch at x, y`.
- The backlight comes on after the first frame is drawn, so nothing flashes at boot.
- On serial (115200 baud): `deck panel: boot, build <SHA>`, the companion chip and display lines, `touch: GT911 at 0x5D`, then `deck panel: test screen up`. The test screen has no Wi-Fi.

**What only the panel can show:** colors, the full area, the backlight, touch, tearing, Wi-Fi and the feed. None of these has a host test.
