# controller-bridge

A Mac menu-bar app that lets you use a **Denon LC6000 PRIME** with **[Untitled Audio Syndicate](https://untitledaudiosyndicate.com)** through Syndicate's OSC API, with LED feedback.

Syndicate's own MIDI mapping (0.3.7) can't handle the LC6000's 14-bit jog wheel or its 14-bit pitch fader, and it gives LED feedback only to the DDJ-FLX4 and FLX10. The app reads the LC6000's MIDI, converts it, and sends it to Syndicate's fixed OSC addresses. It also listens to Syndicate's OSC feedback to light the controller.

```
LC6000 ──USB MIDI──▶  Controller Bridge  ──OSC :9090──▶ Syndicate
LC6000 ◀──MIDI LEDs──  Controller Bridge  ◀──OSC feedback :9096── Syndicate
```

## What it does

| LC6000 | Syndicate (`/Syndicate/Deck/{n}/…`) |
|---|---|
| Pitch fader (14-bit CC 8 + 40) | `TempoSlider` −1…+1 at full resolution, with pickup so the tempo never jumps |
| Jog while playing | `PhaseBend` ±1, released 80 ms after the wheel stops |
| Jog while paused | `WaveformSeek`, using the track length from feedback. Falls back to `BeatSkip` |
| Needle Drop strip, while touched | `WaveformSeek` |
| Play / Cue / Sync / Master | `PlayPause` / `Cue` (hold) / `TempoSync` / `TempoMaster` |
| Pads in Hot Cue mode | `HotCue n 1/0` (press and hold) |
| Pads in Roll mode | `SlipLoop/ThirtySecond … Four` (hold) |
| Pads in Loop mode | `SetCueLoop n` |
| Loop In / Loop Out / Auto Loop, and the Auto Loop knob | `LoopIn` / `LoopOut` / `Loop`. Turning the knob halves or doubles the loop |
| Beat Jump ◀ ▶ (Shift for a bar) | `SkipBeatBack` / `SkipBeatForward` (`SkipBar…` with Shift) |
| Censor (hold; Shift + Censor latches) | `Reverse` 1/0 while held; with Shift, each press turns `Reverse` on or off |
| Key Lock / Slip | `PitchPreserve` / `CueSlip` |
| Shift + Key Lock (pitch reset) | `TempoSlider` 0.0, then the fader waits to meet 0.0. Nothing while the tempo slider is disabled (a synced follower) |
| Pitch Bend − / + (hold) | `PhaseMinus` / `PhasePlus` 1/0, nudging the tempo while held |
| Shift + Pitch Bend (pitch range) | Nothing: Syndicate has no OSC route for the slider's range. The log says so once |
| Param ◀ ▶ | `BeatSkip ∓1` |
| Browse knob turn and press (Shift for Enter), Back, Forward, Track ◀ ▶ | `Browser/Up`, `Browser/Down`, `Browser/L{deck}`, `Back`, `Enter` |

**LEDs:**
- Play, Cue, Sync and Master follow Syndicate's state. Play blinks while a quantized start is pending.
- Key Lock, Slip, Shift and the pad-mode buttons show the bridge's own state.
- Pads show your hot cues in Syndicate's cue colors, quantized to the LC6000's 64-color table. A held pad lights brighter.
- The platter ring lights when a track is loaded. It can also pulse on each beat or on the downbeat.

**Recovery:**
- Unplugging the LC6000, sleeping the Mac or quitting releases every held control first.
- Plugging the controller back in repaints its LEDs.
- If Syndicate restarts, the bridge asks it to send its state again.

**Not possible:**
- Scratching: Syndicate has no scratch or scrub OSC route.
- The platter's center display: it needs SysEx that Denon doesn't document.
- Slicer mode: it is unmapped.

## Install

Install **Controller Bridge** from the Mac App Store (macOS 26 or later). It lives in the menu bar and has no Dock icon. On first launch it opens a short setup guide for Syndicate.

## Set up Syndicate

1. **Settings → OSC:** turn **OSC INPUT ENABLED** on. The listen port defaults to 9090.
2. **Settings → OSC FEEDBACK:** set DEST IP to the bridge's computer (`127.0.0.1` if it's the same one) and PORT to `9096`. Turn on these subscriptions: Playing, PlayPending, Loaded and TrackInfo, Position/Progress, TempoSlider/TempoSliderEnabled, Cues, BPM/Sync and Loop.
3. **Settings → MIDI:** turn your controller's MIDI input **off** (for example, Denon LC6000 PRIME). Otherwise Syndicate's own mapping and the bridge would both react to every button.

The menu's **Set up Syndicate** window shows the same steps.

## Settings

Open **Settings…** from the menu.

- **Controller:** the Syndicate **Deck** (1–4), the **MIDI input** and **MIDI output**, and the **Channel**.
  - Automatic picks the first connected device that a controller profile matches.
  - **Add controller** drives a second LC6000 on another deck. Both share Syndicate's one feedback stream.
  - To use two controllers on one device, tell them apart by channel.
- **LEDs:** turn them off to run without lights.
- **OSC:** Syndicate's host and port. The default is this Mac, port 9090.
- **Feedback:** the port Syndicate sends feedback to (default 9096) and where the app listens.
  - **This Mac only** is the default.
  - **All networks** is for Syndicate on another Mac. macOS asks once for permission to use the local network.
- **Start at login:** off by default.

Settings are checked before they're saved. A bad port, an empty host, or two controllers on the same device and channel are listed in plain words, and nothing changes until you fix them.

## Check the mapping on your unit (do this first)

The numbers come from Denon's *LC6000 PRIME MIDI Specification v1.0* and were checked on a real unit. A few are still PROVISIONAL: they're listed in [`Packages/ControllerBridgeKit/README.md`](Packages/ControllerBridgeKit/README.md#the-default-mapping). Open **Diagnostics…** from the menu to check them:

- **MIDI Monitor** shows every incoming message with its mapping name, or `UNMAPPED`. Move every control. Anything UNMAPPED needs a mapping entry.
- **LED Sweep** steps the pads and ring through all 64 color values, then lights each button note in turn.
- **OSC Log** shows what goes to Syndicate and what comes back.

Things to look for:
- **Jog feel:** `jog.seek_seconds_per_rev` and `jog.beats_per_rev` set how far one platter turn seeks or skips while paused.
- **Pitch direction:** the fader's top is slower, as on a real unit. If yours works the wrong way, set `pitch.invert` to `true`.
- **Colors:** the color velocity is 2 bits each of red, green and blue (`0b00RRGGBB`), confirmed on a unit. LED Sweep shows it on yours.
- **Channel:** the spec only documents channel 1. Pick another in Settings if your unit uses one.

## Mapping overrides

To fix a PROVISIONAL value for your unit without a new build, use the **Mapping** section in Settings:

1. Choose **Export…** to save the mapping in use as a profile file.
2. Edit the values you need. The file only needs the keys you change.
3. Choose **Import…** to load it.

The import is merged over the bundled LC6000 profile and checked first. Deck, Channel and the OSC addresses come from Settings, so a file's values for them aren't applied (and Export leaves them out). Unknown keys, wrong types, out-of-range numbers and duplicate assignments are all listed at once, and a rejected file leaves the working mapping as it was. An accepted import releases anything held, then repaints the LEDs. The app keeps the imported file and loads it at every launch. The Mapping section shows which mapping is in use. **Reset to default** goes back to the bundled profile.

## Development

All the bridge logic is in a Swift package, `Packages/ControllerBridgeKit`, which builds and tests in the terminal. `App/` holds the menu-bar app, the CoreMIDI and UDP adapters, and the SwiftUI windows. The Xcode project is generated from `project.yml` and isn't committed.

```sh
(cd Packages/ControllerBridgeKit && swift test)
brew install xcodegen && xcodegen generate
xcodebuild -project ControllerBridge.xcodeproj -scheme ControllerBridge -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build
scripts/smoke.sh   # a virtual LC6000 and a fake Syndicate check Play out and the Play LED back; CI requires it too
```

Build Release for the smoke check: an ad-hoc Debug build leaves out the hardened runtime. Quit Syndicate and the app itself first, because the smoke check needs UDP 9090 and 9096. A real controller can stay plugged in: the check pins the app to its own virtual device and puts your saved settings back afterwards.

**CI uses an older Xcode than you may have locally.** GitHub's standard macOS runner builds with Xcode 26.x (Swift 6.2), while development has been on Xcode 27.2. The two compilers can disagree. Once, Xcode 26.6's Release optimizer crashed on code that 27.2 built fine (#65). If **App build** fails with a `swift-frontend` stack dump, find the function named in `gh run view <id> --log-failed`, then simplify or split it.

Releases are a version tag on `main`. See [`docs/DEVELOPING.md`](docs/DEVELOPING.md#releasing-to-testflight) for the workflow, its secrets and the one-time setup.

### Look and fonts

The app follows Syndicate's dark, flat style (#34). The colors were sampled from its public screenshots, and `ControllerBridgePresentation` tests every text color against WCAG AA. The app bundles two fonts under the [SIL Open Font License 1.1](https://openfontlicense.org): [Inter](https://github.com/rsms/inter) 4.1 for UI text and [IBM Plex Mono](https://github.com/IBM/plex) 2.5.0 for numbers. Their license files ship in the app, in `Contents/Resources/Fonts/` (`App/Fonts/` in the repo).

For PR screenshots, a Debug build can render the panel without a screen: `ControllerBridge.app/Contents/MacOS/ControllerBridge --render-snapshots snaps`. It prints where the PNGs went (inside the sandbox container). Release builds leave this out.

### History

Before the app there was a Python command-line bridge (`lc6000-bridge`). It was removed in #30, once the app matched it. The parity audit on #30 maps each of its tests to the Swift test that replaced it, and its code is in the git history before that PR.
