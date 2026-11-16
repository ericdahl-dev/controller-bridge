# TestFlight: What to test

The release workflow puts everything after the rule below into each build's "What to Test" (en-US), so keep it current
for the version being tagged (#180). App Store Connect allows 4,000 characters.

---

DeckBridge 1.0.1 has a new look that matches getdeckbridge.app. The controller works as in 1.0; this build is about the
app's windows. Please try:

- The new look: open the menu-bar panel, Diagnostics and the setup guide. Is everything readable? Does anything look
  cut off or out of place?
- Settings in four tabs: Controller, Decks, Syndicate and General. Click through them, and try ⌘1 to ⌘4.
- A refused Apply: on the Syndicate tab, clear the Host, switch to another tab, and click Apply. Settings should open
  the Syndicate tab, point at the Host field and say what's wrong.
- A tall tab: add a second controller on the Controller tab. The tab should scroll, with Apply and Revert staying at
  the bottom.
- Light and dark mode: in Settings › General, set Appearance to Light, then Dark, then Match macOS, clicking Apply
  each time. Every window should follow, and the text should stay easy to read.
- Your set as usual: transport, hot cues, jog, the pitch fader, and the LEDs on all four deck layers.

Tell us about anything that looks wrong, reads badly, or behaves differently from 1.0.
