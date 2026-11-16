# ControllerBridgeKit

All the bridge logic for the native macOS app, as a Swift package that builds and tests from the terminal:

```sh
cd Packages/ControllerBridgeKit
swift test
```

## Testing notes

- **Bind before `.contains` in `#expect`.** `#expect((x?.y ?? []).contains(z))` passes when `x` is nil: Swift Testing
  expands the `contains` call, and the optional chain short-circuits it, so the test can't fail (found in #148). Write
  `let sent = rig.midi.outputs[id]?.sent ?? []`, then `#expect(sent.contains(z))`. Comparisons such as `x?.y == v`,
  `x?.y ?? [] == v` and `(x?.y ?? []).last == v` fail correctly.
- When a new test passes on its first run, check it can fail: revert the change it covers, or bind its subject as above.

## Modules

- **ControllerBridgeCore**: the Coordinator, the Bridge, the mapping and the OSC codec. Pure Swift with Foundation only: no
  CoreMIDI, no Network framework, no UI.

## Controller profiles

A profile file is `{ "id", "name", "device_hints", "exclude_hints", "mapping" }`. A MIDI device gets the profile whose
`device_hints` its name contains (ignoring case; the longest hint wins), unless its name contains one of the profile's
`exclude_hints`. The LC6000 PRIME shows up as two ports, "…LC6000 PRIME Controller", which sends every control, and
"…LC6000 PRIME WD", which sends nothing, so its profile excludes `LC6000 PRIME WD` (#99). The LEDs go to the
destination with the same name as the connected source; a controller's layers share it (#143), and the fallback by
name hint never picks an excluded port.

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
The ring shows its deck's badge color (`DeckColors`, #122) while `leds.ring_follows_deck` is true, as in the bundled
profile. Set it to false to use the fixed `leds.ring_color` instead. A file without the key inherits the bundled true.

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
- `pitch.bits` (#195): 14 on the LC6000. A controller with a 7-bit pitch fader sets 7: the fader is then `msb_cc`
  alone and `lsb_cc` may be left out. 64 is the exact center (below it a step is 1/64, above it 1/63), so a centered
  fader reads 0; `invert`, `dead_zone` and pickup work as on 14-bit.
- `midi.encoder_format` (#193): the browse knob (CC 6) and the Auto Loop knob (CC 3) send two's complement:
  0x01–0x3F turn forward, 0x7F is one tick back. Another controller's profile can say `"offset_64"` (0x40 is still,
  0x41 one forward) or `"sign_magnitude"` (bit 6 is back, the low six bits how far). Left out, it's
  `"twos_complement"`.
- `jog.relative_cc` (#204): for a platter that sends relative ticks on one CC (most Pioneer DDJ jogs), not the LC6000's
  14-bit position. The ticks decode by `midi.encoder_format`, `jog.counts_per_rev` counts ticks per turn, and
  `jog.msb_cc`/`jog.lsb_cc` may be left out. `jog.relative_edge_cc` is the platter's edge on its own CC: it nudges
  without a touch, even with `require_touch`. Left out, the jog is the LC6000's absolute pair.
- `leds`: the button LED notes and the `0b00RRGGBB` color table are confirmed.
- `notes.pads` and `pads.roll_sizes` (#196): a controller has 1–16 pads (the LC6000 has 8, notes 32–39). Pad N is
  hot cue N, and in Roll mode plays `roll_sizes[N-1]`, by Syndicate's SlipLoop names (`ThirtySecond`, `Sixteenth`,
  `Eighth`, `Quarter`, `Half`, `One`, `Two`, `Four`); a pad past the list does nothing in Roll mode. Left out,
  `roll_sizes` is the LC6000's eight, shortest first. Syndicate sends 8 cue slots, so pads 9–16 stay dark.
- `leds.levels` (#194): a button LED's velocity at full, dim and off, 127, 1 and 0 on the LC6000. Another controller's
  profile can set any of them (each 0–127; one left out keeps the LC6000's). They drive the button and pitch-center
  LEDs, turning the LEDs off, and the LED sweep's button pass; pad and ring colors don't use them.

Still PROVISIONAL:

- `midi.channel`: the spec only documents channel 1.
- `jog.seek_seconds_per_rev` (2.0) and `jog.beats_per_rev` (4): how far a turn seeks or skips while paused. Tune them by
  feel.
