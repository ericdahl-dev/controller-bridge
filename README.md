# controller-bridge

Use a **Denon LC6000 PRIME** with **[Untitled Audio Syndicate](https://untitledaudiosyndicate.com)** through Syndicate's OSC API, with LED feedback.

Syndicate's own MIDI mapping (0.3.7) can't handle the LC6000's relative jog wheel, its 14-bit pitch fader, or LED feedback for anything except the DDJ-FLX4/FLX10. This bridge reads the LC6000's MIDI, converts it, and sends it to Syndicate's fixed OSC addresses. It also listens to Syndicate's OSC feedback to light the controller.

```
LC6000 ──USB MIDI──▶  lc6000-bridge  ──OSC :9090──▶ Syndicate
LC6000 ◀──MIDI LEDs──  lc6000-bridge  ◀──OSC feedback :9096── Syndicate
```

## What it does

| LC6000 | Syndicate (`/Syndicate/Deck/{n}/…`) |
|---|---|
| Pitch fader (14-bit CC 8 + 40) | `TempoSlider` −1…+1 at full resolution |
| Jog while playing | `PhaseBend` ±1, released 80 ms after the wheel stops |
| Jog while paused | `WaveformSeek` (uses the track length from feedback); falls back to `BeatSkip` |
| Needle Drop strip (while touched) | `WaveformSeek` |
| Play / Cue / Sync / Master | `PlayPause` / `Cue` (hold) / `TempoSync` / `TempoMaster` |
| Pads – Hot Cue mode | `HotCue n 1/0` (press and hold) |
| Pads – Roll mode | `SlipLoop/ThirtySecond … Four` (hold) |
| Pads – Loop mode | `SetCueLoop n` |
| Loop In / Out / Auto Loop, Auto Loop knob | `LoopIn` / `LoopOut` / `Loop`; turning the knob halves or doubles the loop |
| Beat Jump ◀ ▶ (Shift = bar) | `SkipBeatBack/Forward` (`SkipBar…`) |
| Censor (hold) | `Reverse` 1/0 |
| Key Lock / Slip | `PitchPreserve` / `CueSlip` |
| Pitch − / + (Shift = reset) | `PitchDown` / `PitchUp` / `PitchReset` |
| Param ◀ ▶ | `BeatSkip ∓1` |
| Browse knob turn / press (Shift = Enter), Back, Forward, Track ◀ ▶ | `Browser/Up/Down`, `Browser/L{deck}`, `Back`, `Enter` |

**LEDs:**
- Play, Cue, Sync and Master follow Syndicate's state.
- Key Lock, Slip, Shift and the pad-mode buttons follow the bridge's own state.
- Pads show your hot cues in Syndicate's cue colors, quantized to the LC6000's 64-color table.
- The platter ring lights when a track is loaded.

**Not possible:** scratching, because Syndicate has no scratch/scrub OSC route. The platter's center display needs SysEx that Denon doesn't document. Slicer mode is unmapped.

## Install

```sh
python3 -m venv .venv
.venv/bin/pip install -e .
```

## Set up Syndicate

1. **Settings → OSC:** turn **OSC INPUT ENABLED** on. The listen port defaults to 9090.
2. **Settings → OSC FEEDBACK:** set DEST IP to the bridge's computer (`127.0.0.1` if it's the same one) and PORT to `9096`. Tick these subscriptions: Playing, PlayPending, Loaded and TrackInfo, Position/Progress, TempoSlider/TempoSliderEnabled, Cues, BPM/Sync and Loop.
3. **Settings → MIDI:** leave the LC6000 input **off**. Otherwise Syndicate's own mapping and the bridge would both react to every button.

## Run

```sh
.venv/bin/lc6000-bridge ports                 # find the LC6000's port names
.venv/bin/lc6000-bridge run                   # deck 1, Syndicate on this computer
.venv/bin/lc6000-bridge --deck 2 --host 192.168.1.20 run -v   # -v prints OSC traffic
```

To use two LC6000s, run two copies with different `--deck`, `--midi-input` and `--feedback-port` values. Syndicate only has one feedback destination, so only one copy will get LEDs.

## Verify the mapping on your unit (do this first)

The numbers come from Denon's *LC6000 PRIME MIDI Specification v1.0*. A few of them couldn't be confirmed from the spec text and are marked `PROVISIONAL` in [`default_mapping.toml`](lc6000_bridge/default_mapping.toml):

```sh
.venv/bin/lc6000-bridge monitor     # move every control; anything showing UNMAPPED needs a mapping entry
.venv/bin/lc6000-bridge led-sweep   # steps through all 64 pad colors, then lights each button note
```

- **Jog CCs:** the spec lists CC 55 and 54. If one turn shows up on both, keep only one in `[jog].ccs`.
- **Pitch direction:** set `[pitch].invert = true` if the fader works the wrong way.
- **Colors:** the bridge assumes the color velocity is 2 bits each of red, green and blue (`0b00RRGGBB`). `led-sweep` prints the value it expects for each color.
- **Channel:** the spec only documents channel 1. Change `[midi].channel` if your unit uses another.

Copy `default_mapping.toml`, edit it, and run with `--config my_mapping.toml`. Only the keys you change need to be in the copy.

## Development

```sh
.venv/bin/pip install -e '.[dev]' && .venv/bin/pytest
```

`Bridge` in `lc6000_bridge/bridge.py` is independent of MIDI ports and sockets. The tests feed it synthetic MIDI and OSC feedback, and include a real UDP loopback.

### The Mac app (in progress)

A native, sandboxed menu-bar app is replacing the Python bridge (#12). `Packages/ControllerBridgeKit` holds the logic and its tests. `App/` holds the menu-bar shell and the CoreMIDI and UDP adapters. The Xcode project is generated from `project.yml` and isn't committed.

```sh
(cd Packages/ControllerBridgeKit && swift test)
brew install xcodegen && xcodegen generate
xcodebuild -project ControllerBridge.xcodeproj -scheme ControllerBridge -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build
scripts/smoke.sh   # required before a PR: a virtual LC6000 and a fake Syndicate check Play out and the Play LED back
```

Build Release for the smoke check: an ad-hoc Debug build leaves out the hardened runtime. The app binds its feedback listener to `127.0.0.1:9096`, so it never triggers the local-network prompt. Quit Syndicate or the Python bridge first, since the smoke check needs UDP 9090 and 9096.

#### Look and fonts

The menu-bar panel follows Syndicate's dark, flat style (#34). The colors were sampled from its public screenshots, and `ControllerBridgePresentation` tests every text color against WCAG AA. The app bundles two fonts under the [SIL Open Font License 1.1](https://openfontlicense.org): [Inter](https://github.com/rsms/inter) 4.1 for UI text and [IBM Plex Mono](https://github.com/IBM/plex) 2.5.0 for numbers. Their license files ship in the app, in `Contents/Resources/Fonts/` (`App/Fonts/` in the repo).

For PR screenshots, a Debug build can render the panel without a screen: `ControllerBridge.app/Contents/MacOS/ControllerBridge --render-snapshots snaps`. It prints where the PNGs went (inside the sandbox container). Release builds leave this out.
