# Changelog

## 1.0.1

A new look that matches getdeckbridge.app (#171).

- Geist and Geist Mono type, pill buttons, cards, and status words in normal case.
- The panel, Diagnostics and the setup guide are redesigned. The panel is a little taller.
- Settings is in four tabs: Controller, Decks, Syndicate, General, with ⌘1–4. A refused Apply opens the tab and the field
  that needs fixing, and VoiceOver says why.
- A tall Settings tab scrolls, with Apply pinned at the bottom.
- Status chips and segments meet AA contrast in light and dark, and at increased contrast.
- Fix: a MIDI device named "Controller" no longer counts as the controller light.

## 1.0

The first release: a Mac menu-bar app that plays Untitled Audio Syndicate from a Denon LC6000 PRIME over OSC, with
LED feedback. It replaces the Python `lc6000-bridge` command-line tool.

### Controller

- Transport, loops, beat jumps, Key Lock, Slip, Censor (hold, or latched with Shift), Pitch Bend and the browser.
- Pads in Hot Cue, Roll and Loop modes.
- The 14-bit jog wheel bends the phase while playing and seeks while paused; the Needle Drop strip seeks.
- The 14-bit pitch fader at full resolution, with pickup so the tempo never jumps; Shift + Key Lock resets it.
- Four decks from one unit: the bridge follows the LC6000's deck layers.

### LEDs

- Play, Cue, Sync, Master and the loop LEDs follow Syndicate. Play blinks while a quantized start is pending.
- Pads show hot cues in Syndicate's cue colors; a held pad lights brighter.
- The platter ring shows the active deck's color, following Syndicate's cue palette or your own colors.
- Optional beat pulse on the ring, and a choice of dim or off for Syndicate's LEDs while feedback is stale.

### App

- A panel with status lights (CONTROLLER, FEEDBACK, TEMPO) and plain-words help when the LEDs are dark.
- A warning when Syndicate's OSC feedback subscriptions are off (FEEDBACK ● NO DECK DATA), or when one an LED needs is
  missing.
- Settings: deck, MIDI devices, channel, layers, a second controller, LEDs, OSC host and ports, feedback listening,
  deck colors, appearance (Match macOS, Dark or Light), mapping import and export, and start at login.
- Diagnostics: MIDI Monitor, LED Sweep and OSC Log.
- A setup guide for Syndicate, and a demo controller that runs without hardware.
- Recovery: unplug, replug, sleep, a restarted Syndicate and quitting all release held controls and repaint the LEDs.
- Syndicate's look, in its own dark and light theme tokens, with every text color at WCAG AA.

### Not possible yet

- Scratching (Syndicate has no scratch or scrub OSC route), the platter's center display (undocumented SysEx) and
  Slicer mode (unmapped).
