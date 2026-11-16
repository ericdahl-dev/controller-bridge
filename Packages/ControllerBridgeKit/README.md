# ControllerBridgeKit

All the bridge logic for the native macOS app, as a Swift package that builds and tests from the terminal:

```sh
cd Packages/ControllerBridgeKit
swift test
```

## Modules

- **ControllerBridgeCore**: the Coordinator, the Bridge, the mapping and the OSC codec. Pure Swift with Foundation only: no
  CoreMIDI, no Network framework, no UI.

## The default mapping

`Sources/ControllerBridgeCore/Resources/default_mapping.json` is ported value for value from the Python bridge's
`lc6000_bridge/default_mapping.toml`, with the same section and key names. A user mapping file merges over it the same
way the Python config merge does: objects merge key by key, and anything else replaces the default whole.

One value deliberately differs from Python: `osc.feedback_host` is `127.0.0.1`, not `0.0.0.0`. The feedback port takes
untrusted UDP, and the app's network server entitlement would otherwise expose it to the whole LAN. When Syndicate runs
on another Mac, Settings (#19) switches the feedback listen address from "this Mac only" to "all networks", which brings
up macOS's local-network prompt.

Two keys are new, with no Python counterpart: `leds.beat_pulse` (`"off"`, `"beat"` or `"downbeat"`, default `"off"`)
pulses the platter ring on Syndicate's master clock, and `leds.pulse_ms` (default 100) is how long each pulse stays lit.

JSON has no comments, so the PROVISIONAL notes from the TOML file live here. Check these on hardware before relying on
them:

- `midi.channel`: the spec only documents channel 1.
- `jog.ccs`: the spec lists 55 (upper) and 54 (lower); community reports also mention 31 and 17. A turn that shows up
  on several CCs would double the speed.
- `pitch.invert`: flip it if pushing the fader away from you slows down.
- `leds`: each button's LED is assumed to be on its own note (plus 41-43 for the pitch arrows and center), and the
  64-entry pad and ring color table is assumed to be 2 bits per channel, laid out `0b00RRGGBB`.
