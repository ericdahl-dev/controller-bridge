# ControllerBridgeKit

All the bridge logic for the native macOS app, as a Swift package that builds and tests from the terminal:

```sh
cd Packages/ControllerBridgeKit
swift test
```

## Modules

- **ControllerBridgeCore**: the Coordinator, the Bridge, the mapping and the OSC codec. Pure Swift with Foundation only: no
  CoreMIDI, no Network framework, no UI.

## Controller profiles

A profile file is `{ "id", "name", "device_hints", "exclude_hints", "mapping" }`. A MIDI device gets the profile whose
`device_hints` its name contains (ignoring case; the longest hint wins), unless its name contains one of the profile's
`exclude_hints`. The LC6000 PRIME shows up as two ports, "…LC6000 PRIME Controller", which sends every control, and
"…LC6000 PRIME WD", which sends nothing, so its profile excludes `LC6000 PRIME WD` (#99). The LEDs go to the
destination with the same name as the connected source.

## The default mapping

The `mapping` body of `Sources/ControllerBridgeCore/Resources/Profiles/denon-lc6000-prime.json`, the LC6000 controller
profile, is ported value for value from the Python bridge's
`lc6000_bridge/default_mapping.toml` (removed in #30; see the git history), with the same section and key names. A user mapping file merges over it the same
way the Python config merge does: objects merge key by key, and anything else replaces the default whole.

One value deliberately differs from Python: `osc.feedback_host` is `127.0.0.1`, not `0.0.0.0`. The feedback port takes
untrusted UDP, and the app's network server entitlement would otherwise expose it to the whole LAN. When Syndicate runs
on another Mac, Settings (#19) switches the feedback listen address from "this Mac only" to "all networks", which brings
up macOS's local-network prompt.

Two keys are new, with no Python counterpart: `leds.beat_pulse` (`"off"`, `"beat"` or `"downbeat"`, default `"off"`)
pulses the platter ring on Syndicate's master clock, and `leds.pulse_ms` (default 100) is how long each pulse stays lit.

Feedback liveness (#21) adds three more: `osc.feedback_quiet_ms` (default 10000) is how long the bridge waits with no
feedback before asking Syndicate to resend, `osc.feedback_answer_ms` (default 2000) is how long that request may go
unanswered before feedback counts as stopped, and `leds.stale_idle` (`"dim"` or `"off"`, default `"dim"`) is what
Syndicate's LEDs show then.

JSON has no comments, so the notes on the LC6000 profile live here.

Checked on hardware (2026-11-15, see #12 and #103):

- `jog`: the platter sends its 14-bit position on CC 17 (MSB) and CC 49 (LSB), counting up going forward and wrapping
  at 16384. Movement is the change in position, read when the LSB arrives. One slow full turn measured about 3552
  counts, so `counts_per_rev` is 3600.
  - The platter also sends a 14-bit two's-complement speed on CC 55 (MSB) and CC 54 (LSB): forward 0/2…0/8, back
    127/120…127/127 (−8…−1). It isn't used yet: the position change is enough.
- `needle`: the Needle Drop strip is 14-bit on CC 64 (MSB) and CC 65 (LSB), with touch on note 70.
- `midi.ignore_notes`: the unit sends note 52 about every 0.3 s while idle, a heartbeat. It's dropped, and the
  Diagnostics monitor says so.
- `pitch`: 14-bit on CC 8/40, with the fader's top at 0, so `invert` stays false.
- `leds`: the button LED notes and the `0b00RRGGBB` color table are confirmed.

Still PROVISIONAL:

- `midi.channel`: the spec only documents channel 1.
- `jog.seek_seconds_per_rev` (2.0) and `jog.beats_per_rev` (4): how far a turn seeks or skips while paused. Tune them by
  feel.
