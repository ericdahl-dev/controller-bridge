# DeckBridge may send a display feed to devices other than Syndicate, and never reads it back

2026-11-20. ADR 0003 says DeckBridge talks to Syndicate over OSC only. The deck panel (#490) needs the deck in front, which only DeckBridge knows, so DeckBridge also sends a **display feed**: plain OSC over UDP to one host and port the DJ sets, off by default (#616). That is the one exception to "OSC only to Syndicate". DeckBridge only sends it: it opens no listener for the feed and acts on nothing a display sends back. The panel is display-only (#490, Out of Scope). Rejected: Syndicate Net, an unknown protocol, and having the panel read Syndicate's feedback itself, which doesn't know the LC6000's deck layer.

## The contract

Every address is under `/DeckBridge/Display/` and carries exactly one value, of the OSC type below. Only changes are sent. A full snapshot of every address goes out when the deck in front changes and each time the feed's destination opens. Turning the feed on or a new host or port sends nothing until the destination opens, then sends the snapshot once (#617). The first snapshot after that waits until Syndicate has answered for the deck in front (its cue palette, unless DeckBridge's own deck colors are on, and whether the deck is loaded, with its track if it is), for at most a second, so a display never starts on a default color or an empty deck.

| Address | Type | Value |
|---|---|---|
| `deck` | `i` | The deck in front, 1-4 |
| `color` | `i` | Its deck color as `0xRRGGBB`, the ring's and the app badge's |
| `title` | `s` | The track's title; `""` while the deck is empty |
| `artist` | `s` | The track's artist; `""` while the deck is empty |

Names reserved for #617, which fixes them: `loaded`, `key`, `bpm`, `tempo` (percent), `elapsed` and `remaining` (seconds), `progress` (0-1), `beat` (1-4, 0 for none), `playing`, `cue`, `sync`, `master`, `loop` (0 or 1), `loopLength` (beats), `phase` (0-1, 0.5 in phase) and `level` (0-1).

**A display must ignore an address it doesn't know**, and a message whose type isn't the one above. That way a newer DeckBridge can add addresses without breaking an older display.

`tools/deck-panel/feed/examples.json` holds worked examples of deck states and the messages sent for them. DeckBridge's tests and the panel core's tests both walk it.
