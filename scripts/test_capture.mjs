// Tests for website/capture/capture.js, the web controller capture (#190), run in a plain context (node:vm). No
// browser and no MIDI: the session is fed raw bytes with times, as CaptureSession is in the app's tests.
// Run: node --test scripts/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const SOURCE = readFileSync(new URL("../website/capture/capture.js", import.meta.url), "utf8");
const PROMPTS = JSON.parse(readFileSync(new URL("../website/capture/prompts.json", import.meta.url), "utf8"));

function load() {
  const context = {};
  context.window = context;
  vm.createContext(context);
  vm.runInContext(SOURCE, context);
  return context.DeckBridgeCapture;
}

const C = load();
/** Values built inside the script's own context, as plain JSON data, so deepEqual compares content, not prototypes. */
const plain = (value) => JSON.parse(JSON.stringify(value));
const idle = { id: "idle", text: "Hands off.", gesture: "idle" };
const play = { id: "deck1.play", text: "Press Play.", gesture: "press" };
const cue = { id: "deck1.cue", text: "Press Cue.", gesture: "press" };

function session(prompts = [idle, play, cue]) {
  return C.session({ appVersion: "web 1.0.1", device: "DDJ-400", ports: { input: ["DDJ-400"], output: [] }, prompts });
}

test("MIDI is written as spaced upper-case hex, as in the app's files", () => {
  assert.equal(C.hex([0x90, 0x01, 0x7f]), "90 01 7F");
  assert.equal(C.hex([0xf8]), "F8");
});

test("The prompt list is the app's: 27 steps, idle first, deck 2's Play last", () => {
  assert.equal(PROMPTS.length, 27);
  assert.equal(PROMPTS[0].id, "idle");
  assert.equal(PROMPTS.at(-1).id, "deck2.play");
});

test("A step keeps its messages, timed in milliseconds from its first one, and moves on when confirmed", () => {
  const s = session([play, cue]);
  assert.equal(s.current().id, "deck1.play");
  s.receive([0x90, 0x0b, 0x7f], 10.0);
  s.receive([0x90, 0x0b, 0x00], 10.25);
  s.confirm(11);
  assert.equal(s.current().id, "deck1.cue");
  const step = s.file().steps[0];
  assert.deepEqual(plain(step), {
    prompt: "deck1.play", status: "confirmed",
    messages: [{ t: 0, port: 0, midi: "90 0B 7F" }, { t: 250, port: 0, midi: "90 0B 00" }],
    controls: [], leds: [],
  });
});

test("What arrives while idle is noise from then on: the heartbeat is in noise and left out of later steps", () => {
  const s = session();
  s.receive([0x90, 0x34, 0x7f], 1);
  s.receive([0x90, 0x34, 0x00], 1.1);
  s.confirm(6);
  s.receive([0x90, 0x34, 0x7f], 7);
  s.receive([0x90, 0x0b, 0x7f], 7.5);
  s.receive([0x90, 0x0b, 0x00], 7.6);
  s.confirm(8);
  const file = s.file();
  assert.deepEqual(plain(file.noise), ["90 34"]);
  assert.deepEqual(plain(file.steps[0].messages.map((m) => m.midi)), ["90 34 7F", "90 34 00"]);
  assert.deepEqual(plain(file.steps[1].messages.map((m) => m.midi)), ["90 0B 7F", "90 0B 00"]);
});

test("Clock and active sensing are never credited to a step, and are listed as noise", () => {
  const s = session([play]);
  s.receive([0xf8], 1);
  s.receive([0x90, 0x0b, 0x7f], 1.1);
  s.receive([0xfe], 1.2);
  s.confirm(2);
  const file = s.file();
  assert.deepEqual(plain(file.steps[0].messages.map((m) => m.midi)), ["90 0B 7F"]);
  assert.deepEqual(plain(file.noise), ["F8", "FE"]);
});

test("Tails are kept, flagged (#229): a release whose press came before the step, and the last step's controls in its first half-second", () => {
  const s = session([play, cue]);
  s.receive([0x90, 0x0b, 0x7f], 1);
  s.confirm(2);
  s.receive([0x90, 0x0b, 0x00], 2.1);   // Play's release, after the step changed: a tail
  s.receive([0xb0, 0x11, 0x41], 2.2);   // not a control of the last take: kept
  assert.equal(s.hasTake(), true);
  s.receive([0x90, 0x0c, 0x7f], 2.3);
  s.receive([0x80, 0x0c, 0x00], 2.4);
  s.confirm(3);
  assert.deepEqual(plain(s.file().steps[1].messages), [
    { t: 0, port: 0, midi: "90 0B 00", tail: true },
    { t: 100, port: 0, midi: "B0 11 41" },
    { t: 200, port: 0, midi: "90 0C 7F" },
    { t: 300, port: 0, midi: "80 0C 00" },
  ]);
});

test("A tail alone isn't a take: Next stays off until the step's own control is heard", () => {
  const s = session([play, cue]);
  s.receive([0x90, 0x0b, 0x7f], 1);
  s.confirm(2);
  s.receive([0x90, 0x0b, 0x00], 2.1);
  assert.equal(s.hasTake(), false);
});

test("Redo throws the take away; Skip records the step skipped with nothing; the list ends", () => {
  const s = session([play, cue]);
  s.receive([0x90, 0x0b, 0x7f], 1);
  s.redo(2);
  s.receive([0x90, 0x0b, 0x7f], 3);
  s.confirm(4);
  s.skip(5);
  assert.equal(s.current(), null);
  assert.equal(s.done(), true);
  const file = s.file();
  assert.deepEqual(plain(file.steps.map((step) => [step.prompt, step.status, step.messages.length])), [
    ["deck1.play", "confirmed", 1], ["deck1.cue", "skipped", 0],
  ]);
});

test("The file is capture format 1, with the app's keys, and its JSON has sorted keys", () => {
  const s = session([play]);
  s.receive([0x90, 0x0b, 0x7f], 1);
  s.confirm(2);
  const file = s.file();
  assert.deepEqual(plain(Object.keys(file).sort()), ["app_version", "device", "format", "noise", "ports", "prompts", "steps"]);
  assert.equal(file.format, 1);
  assert.equal(file.app_version, "web 1.0.1");
  assert.deepEqual(plain(file.prompts), [play]);
  const json = C.fileJSON(file);
  assert.deepEqual(JSON.parse(json), plain(file));
  assert.ok(json.indexOf('"app_version"') < json.indexOf('"device"') && json.indexOf('"device"') < json.indexOf('"format"'));
  assert.ok(json.endsWith("\n"));
});

test("The summary before download is the app's, word for word, ending with what the file doesn't hold", () => {
  const s = session([idle, play, cue]);
  s.confirm(1);
  s.receive([0x90, 0x0b, 0x7f], 2);
  s.receive([0x90, 0x0b, 0x00], 2.1);
  s.confirm(3);
  s.skip(4);
  assert.deepEqual(plain(C.summary(s.file())), [
    "Controller: DDJ-400",
    "Ports: DDJ-400 (in)",
    "3 steps: 2 captured, 1 skipped",
    "2 MIDI messages, as the controller sent them",
    "No note",
    "DeckBridge web 1.0.1",
    "Nothing else: no name, email, location or time of day.",
  ]);
});

test("The file name, email subject and body are the app's", () => {
  assert.equal(C.fileName("DDJ-400"), "DDJ-400 capture.deckbridge-capture");
  assert.equal(C.fileName("A/B:C"), "A-B-C capture.deckbridge-capture");
  assert.equal(C.fileName("  "), "Controller capture.deckbridge-capture");
  assert.equal(C.emailSubject("DDJ-400"), "Controller capture: DDJ-400");
  assert.equal(C.emailBody("DDJ-400"), "Here's a capture of my DDJ-400 for DeckBridge. The file is attached.");
  assert.equal(C.emailRecipient, "deckbridge@ericdahl.dev");
});

test("The app's prompts are written as given, layer fields included (#217), and no layers block: the app infers it", () => {
  const s = C.session({ appVersion: "web 1.0.1", device: "DDJ-400", ports: { input: ["DDJ-400"], output: [] }, prompts: PROMPTS });
  const file = plain(s.file());
  assert.deepEqual(file.prompts, PROMPTS);
  assert.deepEqual(file.prompts.find((p) => p.id === "deck2.play"), {
    gesture: "press", id: "deck2.play", layer: 2, layer_of: "deck1.play", text: "Press and release Play on deck 2.",
  });
  assert.equal("layers" in file, false);
});
