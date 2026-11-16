## #171 design proposal: the app in the site's language (agent1)

**Status:** this is a proposal only. No app code is written yet, and the build waits for the user's approval. The boards below compare today's render with an HTML mockup at the same point size, and they include the light theme and a stressed state.

### What's different, and what isn't

The site (#169, PR #170) already uses the app's colors: the Syndicate tokens from #127, with `#171717` ground, `#EDEDEA` ink and `#00FF48` signal. What makes the app look raw beside the site is everything else:

| | App today | Site |
|---|---|---|
| Type | ALL-CAPS bold Inter | Sentence-case Geist at weight 500 with tight tracking, plus small mono labels |
| Shape | 3 pt corners and outlined boxes | 8 and 12 pt corners, pill buttons, grouped cards with hairlines |
| Spacing | 3/6/10/12 scale | 4 pt scale |

The proposal brings those three over. The colors, the flat style and the wording stay as they are. Only the case changes; see **Wording** below.

### Tokens

| Token | Dark | Light | Notes |
|---|---|---|---|
| `surface` **(new, the only new color)** | `#20201F` | `#E6E6E4` | The site's `--p-surface`. Used for grouped cards and the status card. Opaque, so `Contrast.ratio` checks it. |
| `caption` | `#BDBDBD` | `#4F4F4F` | Secondary text and the mono labels. |
| `buttonRaised` | `#2A2A2A` | `#CFCFCD` | Becomes the tonal fill: secondary pills, the segmented track, off deck badges. |
| `hairline` | `#2E2E2E` | `#C7C7C5` | Row dividers. |
| `buttonEdge` | `#7E7E7E` | `#6F6F6F` | Now the edge of a text field. 4.0:1 on `surface`, since it's the field's only cue (#67 item 4). |
| `selectedBar` | ink | ink | Kept: the 2 pt bar under a selected deck in the picker (#67 item 2). |
| `background`, `panel`, `text`, `live`, `attention`, `error`, `accent`, `onAccent` | as today | as today | The Syndicate feel. |
| `button` | | | Unused once the outlined buttons go. Removed in the last slice. |

- **Radius:** `Theme.corner` 3 becomes 8 (badges, fields, popups), 12 (cards) and pill (buttons, chips, segments).
- **Space:** 4 / 8 / 12 / 16 / 24 / 32.
- **Type:**
  - Geist for UI text: 13 body, 15 for status words, 17 for titles, 22 for the guide's headline. Weight 500, with −0.035 em tracking on titles.
  - Geist Mono for labels and data: labels at 11, in natural case, in `caption`; data means ports, MIDI and OSC lines, and deck digits.
  - These replace Inter and IBM Plex Mono so the app and site share a typeface. Both are SIL OFL 1.1, like the fonts they replace.
  - The build needs the static TTFs (Regular, Medium, SemiBold; Mono Regular and Medium), the OFL file in `App/Fonts`, `registerFonts`, and the snapshot font check.

### Components

- **Pill buttons:**
  - **Primary:** signal green with dark ink and a › mark, like the site's call to action. Used only for a window's finishing action: Done in the guide, Apply in Settings.
  - **Secondary:** tonal.
  - **Quiet:** a text link in `caption`.
- **Status light:** a mono label over a 15 pt word with its dot. The word carries the meaning, as today.
- **Status card:** the lights in a two-column grid on `surface`.
  - A third or fourth light wraps to a second row (see the Tempo · Master board).
  - The ports sit under a hairline.
  - Several controllers (#25) get one card each, as the blocks do today.
- **Segmented control:** pills in a tonal track. The selected segment is filled with ink and carries `.isSelected`. Used for the Diagnostics tabs and Ring colors.
- **Switch:** replaces the checkbox in Settings: SwiftUI `Toggle` with the `.switch` style. On is signal in dark and `live` (#007026) in light.
- **Chip:** a small tinted pill, used for UNMAPPED.
- **Deck badge:** 8 pt corners and a Mono digit.
  - Off badges use the tonal fill.
  - In the picker, the selected badge keeps its deck color plus the 2 pt `selectedBar` under it.
  - When the controller follows its layers, the badge shows alone, as today.

### Per surface

The boards cover four surfaces.

**1. Panel (360 pt wide, unchanged)**
- Title in Geist 17/500.
- The status card holds the lights.
- Settings… and Diagnostics… are tonal pills; the footer links are quiet.
- The status line stays, in the same order.
- It's about 90 pt taller in the default state.
- With the bridge stopped and help showing, the help keeps its mono "Why no LEDs?" label and its Copy details link.

**2. Settings (440 pt wide, unchanged)**
- Settings is already a SwiftUI `Settings` scene. Restyled as one form, it would run to about 1,000 pt, so it moves into a `TabView`. That's the macOS Settings convention: a toolbar of tabs, one short pane each, nothing scrolling.
- **The tabs:**
  - **Controller:** Controller, plus Add controller and Mapping.
  - **Decks:** the Decks section.
  - **Syndicate:** Syndicate OSC input and OSC feedback.
  - **General:** Login and Setup Guide….
- macOS draws the tab bar itself; the mock only approximates it.
- Rows follow System Settings: the label on the left, the control on the right, in grouped cards.
- **Apply and Revert** live in a footer shared by every tab, so one Apply covers every tab.
- **When Apply is refused**, the footer lists the problems in plain words, as today. Each one names its tab ("Syndicate: …"), and the window switches to the first tab with a problem. The field errors stay next to their fields.

**3. Diagnostics (720×460, unchanged)**
- The header has the deck badge, the title, and the two lights.
- The tabs become a segmented control, keeping ⌘1–3.
- Copy log and Save… become quiet buttons; Clear log is tonal.
- The log sits in a card, in Mono rows with hairlines between them. UNMAPPED becomes an attention chip.

**4. Setup guide (460 pt, unchanged)**
- It takes the site's support-page layout:
  - A mono eyebrow over a 22 pt headline.
  - Numbered steps, each with a large muted numeral, the Syndicate menu path in mono, and hairlines between steps.
  - A mono checklist.
- The "quit other DJ apps" note becomes an attention callout.
- Done: feedback live is the primary green pill.

### Wording

No word changes. Two things change how words are shown:

1. **Sentence case on screen.** The `.textCase(.uppercase)` calls go, so the captions show their natural case. The status words are capitals in the Kit today ("CONNECTED", "DECK [1]"). Showing them in sentence case means `StatusPresentation` returns them in natural case: "Connected", "Deck [1]". Its tests change red-first. The spoken strings are already natural case, so they don't change.
2. **Settings rows that are a single switch use the switch's own text as the row label.** The short labels "Colors", "Layers" and "Start" go. For example, "Use Syndicate's deck colors" becomes the row title.

Syndicate's own menu names in the guide stay in capitals ("Settings → OSC FEEDBACK → SUBSCRIPTIONS") because that's how Syndicate shows them. "UNMAPPED" also stays: it's the Kit's data value.

### States

**Covered by mocks:**
- The LC6000's default, following layers, with no deck picker.
- Three lights (Tempo · Master) wrapping in the card.
- Bridge stopped, with help.
- Light theme.
- All four Settings tabs.

**Built and checked as snapshots, not mocked:**
- Two controllers: two cards.
- Demo: DEMO is the first light, as today.
- The quit confirmation (#131): the same inline question, with tonal pills and the same Return and Esc keys as today. There's no green, because quitting isn't a finishing action.
- Unplugged, MIDI error, waiting, and not connected with the device list.
- Setup guide waiting (Done is tonal until feedback is live).
- LED Sweep and OSC Log.
- Settings with two controllers and stopped.

**The status line:** its fit budget (#66) assumes Inter 10 caps at 360 pt. Geist 11/500 in sentence case is narrower per word, but the budget is measured again. The four-controller and DEMO+MASTER lines are rendered before the slice lands.

### Accessibility (#67 holds, item by item)

1. **Focus and hover:**
   - Every pill, segment, chip button and switch draws a 2 pt ink focus ring on `isFocused`, with a 2 pt gap in the window color so it shows on the green pill too.
   - Hover lifts the fill to `hairline`.
2. **Selection is never fill alone:**
   - Picker decks keep the `selectedBar` and the `.isSelected` trait.
   - The selected segment is filled with ink (12:1 against the track) and carries `.isSelected`.
   - Settings tabs are system tabs, read as "Decks, tab, 2 of 4".
3. **VoiceOver:**
   - Natural-case strings, so VoiceOver reads them better.
   - Every `accessibilityLabel` and `spoken` string stays.
   - Switches read "Use Syndicate's deck colors, switch, on".
   - Chips read their word, with no "black circle".
4. **Non-text contrast:**
   - The tonal pills are 1.2:1 against the window, but their text names them. #67 sets the 3:1 rule for an edge that is "the only cue", and that isn't the case here. The site's buttons work the same way.
   - Text fields keep a 3:1+ edge (4.0:1).
   - Switch state: 12:1 on in dark, 5:1 in light.
5. **Shortcuts stay:**
   - Panel: ⌘, ⌘D ⌘Q, with Esc and Return in the quit question.
   - Diagnostics: ⌘1–3, ⇧⌘C, ⌘S, ⌘K.
   - Settings: Return for Apply, plus ⌘1–4 for its tabs.
   - Guide: Return for Done.

**Contrast**, computed with `Contrast.ratio`. These pairs get `PaletteTests` cases, red first.

| Pair | Dark | Light |
|---|---|---|
| caption on surface / tonal | 8.7 / 7.6 | 6.6 / 5.3 |
| text on tonal | 12.2 | 11.0 |
| live on surface | 12.0 | 5.0 |
| attention on surface | 7.2 | 5.0 |
| error on surface | 5.1 | |
| field edge on surface | 4.0 | 4.0 |
| onAccent on the green pill | 13.9 | 13.9 |

**Branding:** no Syndicate or Denon logos. "Denon LC6000 PRIME" stays text that comes from the profile.

### Build plan after approval

Test-first, one commit per slice. View bodies stay small for the CI Xcode 26.6 optimizer (#65).

1. Palette: `surface`, the contrast tests, and natural-case status words.
2. Theme: radius, space, the Geist fonts.
3. Shared styles: the pills, segmented control, switch, chip and card, each with a focus snapshot.
4. Panel.
5. Diagnostics.
6. Setup guide.
7. Settings tabs, one slice per pane.
8. Snapshots in both themes, the #29 screenshots, and a hand-off to the site.

### Decisions for the user

1. **Fonts.** Switch to Geist and Geist Mono to match the site (recommended)? Or keep Inter and Plex and take only the shape and spacing?
2. **Settings as four tabs.** This is the one structural change. Without it, the restyled form is about 1,000 pt tall.
3. **Panel height.** It grows about 90 pt for the status card and the bigger targets. Is that fine, or should it be tighter?
4. **Pill buttons without an edge, like the site.** This passes #67, because the text identifies each button. Or keep a thin edge as today, which is safer but looks less like the site.
