/* The web controller capture (#190): the app's guided capture (ControllerBridgeCapture's CaptureSession, #185) in
   the browser, for owners who don't run the app. It walks the same prompts (prompts.json, the app's own file, checked
   byte for byte by scripts/check_site.py) and writes capture format 1, which the app and the draft tool (#189) read;
   they work out the controls from the raw messages (CaptureFile.inferred()), so this keeps only what the app's
   session keeps at receive time:
   - what arrives during the idle step is noise from then on; clock and active sensing are never credited;
   - a release whose press came before the step is a tail; so is, for half a second after a step starts, anything from
     the controls of the take before it (a jog still spinning).
   Nothing here touches the network. Tested by scripts/test_capture.mjs. */
(function (root) {
  "use strict";

  var FORMAT = 1;
  var TAIL_WINDOW = 0.5;

  function hex(bytes) {
    return bytes.map(function (b) { return (b < 16 ? "0" : "") + b.toString(16).toUpperCase(); }).join(" ");
  }

  function isRealtime(bytes) { return bytes.length === 1 && bytes[0] >= 0xf8; }

  /** A message's noise key, as Inference.noiseKey: note on and off share one; CC by number; pitch bend by channel. */
  function noiseKey(bytes) {
    if (isRealtime(bytes)) return bytes.slice();
    if (bytes.length < 2) return null;
    var kind = bytes[0] & 0xf0, channel = bytes[0] & 0x0f;
    if ((kind === 0x90 || kind === 0x80) && bytes.length >= 3) return [0x90 | channel, bytes[1]];
    if (kind === 0xb0 && bytes.length >= 3) return [0xb0 | channel, bytes[1]];
    if (kind === 0xe0 && bytes.length >= 3) return [0xe0 | channel];
    return null;
  }

  function keyString(key) { return key ? key.join(",") : null; }

  function unique(keys) {
    var seen = {}, out = [];
    keys.forEach(function (k) { var s = keyString(k); if (!seen[s]) { seen[s] = true; out.push(k); } });
    return out;
  }

  /** One capture of one controller: receive raw MIDI with host times in seconds; confirm, redo or skip each step. */
  function session(options) {
    var prompts = options.prompts, index = 0, finished = [], take = [];
    var stepStart = null, tailKeys = {}, pressed = {};

    function current() { return index < prompts.length ? prompts[index] : null; }

    function portKey(port, key) { return port + ":" + key.join(","); }

    function receive(bytes, time, port) {
      port = port || 0;
      if (!current()) return;
      var key = noiseKey(bytes);
      if (key && !isRealtime(bytes)) {
        var pk = portKey(port, key);
        if ((key[0] & 0xf0) === 0x90) {
          var release = (bytes[0] & 0xf0) === 0x80 || bytes[2] === 0;
          if (release && !pressed[pk]) return;
          if (!release) pressed[pk] = true;
        }
        if (stepStart !== null && time - stepStart < TAIL_WINDOW && tailKeys[pk]) return;
      }
      take.push({ time: time, port: port, bytes: bytes.slice() });
    }

    function startStep(time, previous) {
      stepStart = time === undefined ? null : time;
      tailKeys = {};
      previous.forEach(function (m) { var k = noiseKey(m.bytes); if (k) tailKeys[portKey(m.port, k)] = true; });
      pressed = {};
    }

    function finish(status, kept) {
      finished.push({ prompt: current(), status: status, take: kept });
      index += 1;
    }

    function confirm(time) { var kept = take; take = []; finish("confirmed", kept); startStep(time, kept); }
    function redo(time) { var thrown = take; take = []; startStep(time, thrown); }
    function skip(time) { var thrown = take; take = []; finish("skipped", []); startStep(time, thrown); }

    function idleNoise() {
      var keys = [];
      finished.forEach(function (f) {
        if (f.status === "confirmed" && f.prompt.gesture === "idle") {
          f.take.forEach(function (m) { var k = noiseKey(m.bytes); if (k) keys.push(k); });
        }
      });
      return unique(keys);
    }

    /** With no confirmed idle step: keys heard in every one of three or more confirmed, unshifted steps. */
    function repeatedNoise() {
      if (finished.some(function (f) { return f.status === "confirmed" && f.prompt.gesture === "idle"; })) return [];
      var takes = finished.filter(function (f) {
        return f.status === "confirmed" && f.prompt.gesture !== "idle" && !f.prompt.shifted_of;
      }).map(function (f) { return f.take; });
      if (takes.length < 3) return [];
      var sets = takes.map(function (t) {
        var s = {}; t.forEach(function (m) { var k = noiseKey(m.bytes); if (k) s[keyString(k)] = true; }); return s;
      });
      return unique(takes[0].map(function (m) { return noiseKey(m.bytes); }).filter(function (k) {
        return k && sets.every(function (s) { return s[keyString(k)]; });
      }));
    }

    function realtimeNoise() {
      var keys = [];
      finished.forEach(function (f) { f.take.forEach(function (m) { if (isRealtime(m.bytes)) keys.push(m.bytes); }); });
      return unique(keys);
    }

    function file() {
      var noise = unique(idleNoise().concat(repeatedNoise(), realtimeNoise()));
      var noiseSet = {};
      noise.forEach(function (k) { noiseSet[keyString(k)] = true; });
      var steps = finished.map(function (f) {
        var heard = f.take.filter(function (m) { return !isRealtime(m.bytes); });
        var kept = f.prompt.gesture === "idle" ? heard : heard.filter(function (m) {
          var k = noiseKey(m.bytes); return !(k && noiseSet[keyString(k)]);
        });
        var start = kept.length ? kept[0].time : 0;
        return {
          prompt: f.prompt.id, status: f.status,
          messages: kept.map(function (m) { return { t: Math.round((m.time - start) * 1000), port: m.port, midi: hex(m.bytes) }; }),
          controls: [], leds: [],
        };
      });
      return {
        format: FORMAT, app_version: options.appVersion, device: options.device, ports: options.ports,
        prompts: prompts, noise: noise.map(hex), steps: steps,
      };
    }

    return {
      current: current, receive: receive, confirm: confirm, redo: redo, skip: skip, file: file,
      done: function () { return current() === null; },
      position: function () { return { step: index + 1, of: prompts.length }; },
      hasTake: function () {
        var noise = {};
        idleNoise().forEach(function (k) { noise[keyString(k)] = true; });
        return take.some(function (m) { var k = noiseKey(m.bytes); return !isRealtime(m.bytes) && !(k && noise[keyString(k)]); });
      },
    };
  }

  /** The file's JSON: keys sorted at every level, two-space indent, a trailing newline, so two captures diff cleanly. */
  function fileJSON(file) {
    function sorted(value) {
      if (Array.isArray(value)) return value.map(sorted);
      if (value && typeof value === "object") {
        var out = {};
        Object.keys(value).sort().forEach(function (k) { out[k] = sorted(value[k]); });
        return out;
      }
      return value;
    }
    return JSON.stringify(sorted(file), null, 2) + "\n";
  }

  function count(n, noun) { return n + " " + noun + (n === 1 ? "" : "s"); }

  /** What the owner sees before saving: CaptureFile.summary, word for word. */
  function summary(file) {
    var captured = file.steps.filter(function (s) { return s.status === "confirmed"; }).length;
    var messages = file.steps.reduce(function (n, s) { return n + s.messages.length; }, 0);
    var leds = file.steps.reduce(function (n, s) { return n + s.leds.length; }, 0);
    var lines = [
      "Controller: " + file.device,
      "Ports: " + file.ports.input.join(", ") + " (in)" + (file.ports.output.length ? "; " + file.ports.output.join(", ") + " (out)" : ""),
      count(file.steps.length, "step") + ": " + captured + " captured, " + (file.steps.length - captured) + " skipped",
      count(messages, "MIDI message") + ", as the controller sent " + (messages === 1 ? "it" : "them"),
    ];
    if (leds > 0) lines.push(count(leds, "LED answer"));
    lines.push(file.note ? "Your note: " + file.note : "No note");
    lines.push("DeckBridge " + file.app_version);
    lines.push("Nothing else: no name, email, location or time of day.");
    return lines;
  }

  /** CaptureFile.suggestedFileName: the device, with / and : made hyphens, then " capture.deckbridge-capture". */
  function fileName(device) {
    var name = device.trim().replace(/[\/:]/g, "-");
    return (name || "Controller") + " capture.deckbridge-capture";
  }

  root.DeckBridgeCapture = {
    FORMAT: FORMAT, hex: hex, session: session, fileJSON: fileJSON, summary: summary, fileName: fileName,
    emailRecipient: "deckbridge@ericdahl.dev",
    emailSubject: function (device) { return "Controller capture: " + device; },
    emailBody: function (device) { return "Here's a capture of my " + device + " for DeckBridge. The file is attached."; },
  };
})(window);
