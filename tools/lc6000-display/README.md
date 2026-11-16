# LC6000 jog display tools

Research tools for the LC6000 PRIME's jog-wheel display, which is driven over its "WD" MIDI port (#121). They're
the groundwork for showing the active deck on the jog (#165). They're not part of the app, and none of them run in
CI.

The protocol, with what each message does and what the unit answers, is written up on #121 (see its recipe comment).
In short:

1. **Host hello** to the Controller port: `F0 00 02 0B 7F 10 60 00 04 04 01 01 00 F7`, then `F0 00 20 7F 01 F7`.
   Without it, the unit refuses uploads (ack `06`).
2. **Upload** to WD:
   - `90 01 00`
   - `0A 01 00 06 0D`
   - `0C`: the PNG's size
   - `0D`: chunks of a 21-bit offset plus the data as an MSB-first 7-bit bitstream
   - `0E`: slot `01`, then the PNG's 32-bit byte-sum as 8 nibbles
3. **Commit:** wait for the `01 10 0F 00 01 00` acks, then send `7E 00 06 01` and `10`.
4. **Show:** `0A 01 00 <slot> 0D`, which displays the image in that slot.

`0C`'s three bytes are only the 21-bit size. The slot is `0E`'s first byte and `0A`'s image index: djay keeps its
logo in slot 01 and loads cover art into slot 02 (#165).

The display shows uploads **rotated 180°**, so images are sent pre-rotated.

**Upload speed depends on the send API, not the unit.**
- `MIDISendSysex` paces SysEx at MIDI 1.0 speed (31,250 baud, about 3.1 KB/s), so a 30 KB image takes about 10 s.
- djay hands about 74 KB of cover art to CoreMIDI in about 40 ms, and the unit acks it all within about 1.1 s:
  roughly 60–70 KB/s, as UMP or packet-list sends at USB speed.

For real-time readouts, djay also sends two channel messages to WD on ch1 (#165):
- **Pitch bend:** the platter marker. It's the virtual record's angle at 33⅓ rpm, wrapping once per turn, sent at
  about 50 Hz.
- **Note 1** at velocity 127 or 0: the play/cue state.

## Files

| File | What it does |
|---|---|
| `jogbuild.py` | PNG in, upload out. `png` re-encodes a 198×198 PNG for the unit (rotated 180°, in the layout the unit has accepted). `plan` writes a `jogseq` plan, into slot 1 or the slot given. `selftest` runs round trips with no device. |
| `jogseq.swift` | Sends a plan to the unit once, listening on both ports. `send` paces SysEx through `MIDISendSysex`; `burst` sends it as UMP packets at USB speed, as djay does, and checks the acks after. `dry` checks a plan and prints it. `selftest` checks the UMP packing. |
| `sysex_decode.py` | Reads a MIDI Monitor capture (`.mmon`, text export or `.syx`), groups the SysEx, and rebuilds image uploads as PNG files (`--dump DIR`). |
| `mmon_list.py` | Lists every message in a `.mmon`, with timing and "To"/"From" endpoints. |
| `images/deck-ring.png` | Our app icon at 198×198, as a source image, not rotated. |
| `images/f-test.png` | An upright F with a red square top-right. The orientation test: the unit shows it upside down with the square lower-left. |

## Use

```sh
cd tools/lc6000-display
python3 -I jogbuild.py selftest
python3 -I jogbuild.py plan images/deck-ring.png /tmp/deck-ring.plan
swiftc -O -swift-version 5 jogseq.swift -o /tmp/jogseq
/tmp/jogseq dry /tmp/deck-ring.plan      # checks and prints; sends nothing
/tmp/jogseq send /tmp/deck-ring.plan     # sends once, SysEx paced at MIDI 1.0 speed: see the rules below
/tmp/jogseq burst /tmp/deck-ring.plan    # the same at USB speed (not yet tried on hardware)
```

A plan is one message per line: `<delay ms> WD|CTL <hex bytes>`, or `<delay ms> ACKS <count> <timeout ms>`, which
waits for that many accepted acks and stops the run on a refusal. Lines starting with `#` are comments.

`jogseq` sends only what the protocol needs:
- **WD:** the `00 02 0B 7F 10` messages, the identity request, pitch bend on ch1, and note 1 on ch1.
- **Controller:** Serato SysEx, the `cmd 60` host message, LED note-ons, and the identity request.

It also refuses to send if the port names are ambiguous.

## Rules

- **Get an OK before sending to the hardware.** The host hello changes the unit's mode, and WD should only ever get
  the messages above. In #143, the app's LED traffic leaked onto WD and left the display blank. Which message
  blanked it isn't known: note 1 alone is djay's play/cue state.
- **No third-party data in this folder:** no other app's images, and no capture files. Test images are our own.
- **What was verified, and what's still a guess:**
  - Verified: these exact images were uploaded and shown on hardware. Uploads were accepted (acks `00`), with the
    hello first.
  - Not yet tested: `plan` writes the protocol's minimal sequence. The verified runs also replayed a DJ app's LED
    paint and identity requests on the Controller port, and four `0A` messages before the last.
  - Trimming those is the bisect planned in #165.
