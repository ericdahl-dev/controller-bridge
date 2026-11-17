# TestFlight: What to test

The release workflow puts everything after the rule below into each build's "What to Test" (en-US), so keep it current
for the version being tagged (#180). App Store Connect allows 4,000 characters.

**Who gets the build (#244).** A tag goes to the **Internal** group only:

    git tag -a v1.0.3 -m "Jog display check"

To also send it to the external **Syndicate** group and submit it for Beta App Review, put `[external]` in the
annotated tag's message:

    git tag -a v1.0.3 -m "Release 1.0.3 [external]"

To send out a build that's already uploaded, run the Release workflow by hand with its version and build number and
**external** ticked. A lightweight tag, or a message without the marker, is always internal only.

---

DeckBridge 1.1.0 shows the deck on the LC6000's jog display. Please try:

- The jog display: in Settings › Controller, turn on "Show the deck on the jog display". The screen should show the deck
  in front, in its color, with the track's title, artist and key · BPM. Load a track, then a long title. Is it upright
  and easy to read?
- The needle: play a deck. The needle should go round once per bar, in time, and the lit segment should follow the
  master beat. Pause: the play light blinks. Turn the platter: the needle follows.
- Deck layers: switch to deck 2 with Shift + deck select. The screen should redraw as deck 2.
- Off and back: turn the switch off (the unit's own screen comes back), then on. Unplug and replug. Quit DeckBridge: the
  unit goes back to its own screen.
- Without the unit: open Diagnostics › Jog display. It previews every deck's screen live, even with no LC6000.
- Subscriptions: if Syndicate's OSC Feedback subscriptions aren't all on, the panel lists each missing one and what it
  breaks. With the jog display on, BarRamp is on that list.
- Help add a controller: in Settings › Controller, choose "Controller not found?" from the Controller menu (or try it
  with the demo controller). Walk a few steps, then end the capture and save the file.
- Your set as usual: transport, hot cues, jog, the pitch fader and the LEDs on all four deck layers.

Tell us what you see on the display, and anything that looks wrong or behaves differently from 1.0.2.
