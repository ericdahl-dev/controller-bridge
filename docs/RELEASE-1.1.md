# Release 1.1.0: the LC6000 jog display

The checklist for v1.1.0, in order. Each step says who does it and what gates it. Tick the box when it's done. The
step headings are pinned by `scripts/test_release_docs.py`; change both together.

**Nothing in steps 1–2 may be sent to the hardware without the CoS's GO, with the user at the unit.**

## 1. Hardware spike: upload timing

- **Who:** the user at the LC6000, with an agent watching. **Gate:** the CoS's GO.
- Run the slice 0 timing spike from #165: how long an image upload takes over the WD port, and whether the unit
  stays responsive while it runs. Record the numbers on #165.
- [ ] Done; the numbers are on #165.

## 2. Jog display hardware checklist

- **Who:** the user at the LC6000. **Gate:** step 1, and the CoS's GO.
- Work through the 14 steps of the
  [#165 hardware checklist](https://github.com/ericdahl-dev/deckbridge/issues/165#issuecomment-6929614995) (slices 7
  and 6+7): the image, upright and in the deck's color; title wrap; the layer handover; off, on, replug and quit; the
  needle once per bar; the play light; the platter while paused; tempo changes.
- **First (#307):** Quit djay and Engine, and any other app that could act as the unit's host. DeckBridge doesn't guard
  against another host yet (v1.2), so a second host could interfere with the display.
- **Also, after the 14 (#307, #306):**
  - **15. The platter while it plays:** touch the top and turn it on a playing deck. The needle follows the platter, not
    the beat. Let go: within a quarter-second it eases back to the deck's phase.
  - **16. Layers in host mode (#79, #120):** with DeckBridge as host, step through decks 1–4 with Shift + deck select
    (the ch16 note 55 overlay). Each deck's controls drive that deck, and the right deck's LEDs light, both in the
    normal state (controls on ch1) and in the multi-channel state (controls on the layer's channel).
  - **17. LEDs per layer:** on each layer, Play, Cue, Sync and the pads show that deck's state, not another's.
- Answer each step pass or fail on #165. **Any fail blocks the release** until it's fixed and checked again.
- [ ] All 17 pass.

## 3. Turn the jog display on by default

- **Who:** an agent, test-first (/tdd). **Gate:** step 2.
- One PR: `BridgeSettings.jogDisplay` defaults to on, for new settings only, so a saved choice is kept. The Settings
  hint "Off until tested on hardware." goes; "LC6000 only." stays.
- If the Controller tab looks different, re-render the #29 screenshots.
- [ ] Merged.

## 4. CHANGELOG

- **Who:** an agent. **Gate:** step 3.
- Paste this block at the top of `CHANGELOG.md`, adjusted for anything steps 1–3 changed (done: the block below is what
  `CHANGELOG.md` has):

```markdown
## 1.1.0

The LC6000's jog display shows the deck (#165).

- The round screen in the jog wheel shows the deck in front: its number in the deck's color, the track's title and
  artist, and key · BPM. Long titles wrap; an empty deck says "No track". It's on by default for new settings; a saved
  choice is kept. Switch it in Settings › Controller › "Show the deck on the jog display".
- The ring's lit segment, in green, steps with Syndicate's master beat, drawn on the unit itself (#215). The needle turns
  once per bar with that deck's own phase, so you can see at a glance whether the decks are in sync. Turning the platter
  doesn't move it; a seek on a paused deck does, once Syndicate reports it (#388).
- It follows the controller's deck layers, and gives the screen back to the LC6000 when switched off, unplugged or quit.
  While a new card loads, the screen shows "Loading…" instead of going black.
- Diagnostics › Jog display previews every deck's screen live, even without an LC6000 connected (#221).

Controller:

- Shift + Pitch Bend − / + transposes the deck down or up a semitone, turning its key lock on first, as Syndicate needs
  (#377). Without Shift, Pitch Bend still nudges the tempo.
- Main CUE: pressing PLAY while CUE is held keeps the deck playing, and Shift + CUE goes back to the cue point and stops
  (#360).
- Shift + a hot cue pad jumps to that cue at once, whatever the quantize setting, without starting a stopped deck (#361,
  #364).
- The jog and the Needle Drop strip seek a paused deck exactly where you put them, with quantize off while seeking
  (#375).
- Pads past Syndicate's eight hot cues send nothing and stay dark (#311).
- Missing Syndicate subscriptions are a list, each with what it breaks. BarRamp joins it while the jog display is on
  (#261, #258). Demo mode no longer warns about subscriptions (#246).

Groundwork, inactive for the LC6000:

- Mixer support (faders, EQ, filter, cue/mute/solo and VU meters) works once a controller profile has a mixer (#207).
- Profiles may leave out the needle strip, jog, pitch fader or browse knob, and gain Shift done in hardware, Shift pads
  on their own channels and an LED color table (#341, #342, #226, #197).
- Captures gain deck layers, the Shift offset, unplug handling, and an LED test that stays off until it's checked on
  hardware (#217, #229, #187). Draft profiles can come from a controller's MIDI docs alone, as for the Pioneer DDJ-400
  and DDJ-FLX4 (#280).
```

- [ ] In `CHANGELOG.md`, merged.

## 5. TestFlight What to Test

- **Who:** an agent. **Gate:** none; it's ready in `docs/TESTFLIGHT.md`.
- The text after the rule in `docs/TESTFLIGHT.md` is 1.1.0's What to Test. The release workflow sets it on the build.
  It has to stay under 4,000 characters and never offer the LED test (both pinned by `scripts/test_release_docs.py`).
- [ ] Re-read against what steps 1–3 found.

## 6. Internal build

- **Who:** the CoS. **Gate:** steps 3–5 merged on `main`.
- Tag the merge commit on `main`. A plain tag goes to the **Internal** group only (#244):

      git tag -a v1.1.0 -m "Release 1.1.0"
      git push origin v1.1.0

- The user installs it from TestFlight and runs the What to Test list once, on the unit.
- [ ] Internal build checked.

## 7. External build and a short beta

- **Who:** the CoS, with the user's OK. **Gate:** step 6.
- Send the same build to the external **Syndicate** group and Beta App Review, by #244's path. Run the Release workflow
  by hand with version `1.1.0`, the build number from step 6, and **external** ticked. (A new tag whose message contains
  `[external]` does the same, for a new build.)
- Once Beta App Review approves it, run a short external beta: **24–48 hours**, with no blocking crash reports (check
  TestFlight's crashes and feedback). A blocking crash goes back to step 3's fix loop with a new build.
- [ ] Approved, and the beta closed with nothing blocking.

## 8. App Store listing

- **Who:** agent1 (#29). **Gate:** step 3 (the screenshots show the display switch on).
- The Mac App Store listing's text and screenshots for 1.1.0.
- [ ] Ready in App Store Connect.

## 9. Submit 1.1.0 to the App Store

- **Who:** the user submits it in App Store Connect; the CoS prepares it. **Gate:** steps 7 and 8.
- DeckBridge goes to the Mac App Store with 1.1.0:
  - **Price:** Free.
  - **Listing and screenshots:** from #29 (step 8).
  - **Review notes:** `docs/APP_REVIEW.md`, pasted into App Review Information › Notes.
  - **App Privacy:** "Data Not Collected".
  - **Build:** the 1.1.0 build the beta ran.
- Then the user submits it in App Store Connect, and the release waits for App Review.
- [ ] Submitted; approved; released.

## 10. Site

- **Who:** agent3. **Gate:** step 6: v1.1.0 is tagged and on TestFlight (release day).
- The site lives on `main` (#170); Coolify deploys it. agent3's v1.1 site update is held on its own branch, `site-v1.1`, as draft
  [PR #300](https://github.com/ericdahl-dev/deckbridge/pull/300) (no auto-merge; merging it deploys the site),
  until release day: "coming in v1.1" becomes shipped, and the jog display goes on the LC6000 page and in the support FAQ. Merge it
  with `check_site` and the taste-skill gate passing.
- [ ] Merged and deployed.

## 11. After the release

- Close the v1.1 milestone. v1.2 work resumes: the #207 mixer spike first, then #213 and #260 at the unit.
- [ ] Done.
