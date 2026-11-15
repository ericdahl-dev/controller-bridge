"""Core translation logic, independent of real MIDI ports and sockets.

`Bridge.handle_midi` turns LC6000 messages into Syndicate OSC calls.
`Bridge.handle_osc` turns Syndicate OSC feedback into LC6000 LED messages.
`Bridge.tick` must be called periodically (every ~10 ms) to release jog bends.
"""

from __future__ import annotations

import time
from typing import Any, Callable

import mido

from .codec import join_14bit, pitch_to_tempo_slider, relative_ticks, rgb_to_velocity

OscSend = Callable[..., None]          # (address, *args)
MidiSend = Callable[[mido.Message], None]

ROLL_SIZES = ["ThirtySecond", "Sixteenth", "Eighth", "Quarter", "Half", "One", "Two", "Four"]
MODES = ("hotcue", "roll", "loop", "slicer")

# Syndicate's default cue colours until ColorPalette feedback arrives.
DEFAULT_PALETTE = {
    1: (255, 0, 0), 2: (255, 128, 0), 3: (255, 255, 0), 4: (0, 255, 0),
    5: (0, 255, 255), 6: (0, 0, 255), 7: (128, 0, 255), 8: (255, 0, 255),
}

FULL = 127
DIM = 1
OFF = 0


class Bridge:
    def __init__(self, config: dict, send_osc: OscSend, send_midi: MidiSend | None = None,
                 clock: Callable[[], float] = time.monotonic):
        self.cfg = config
        self._send_osc = send_osc
        self._send_midi = send_midi or (lambda msg: None)
        self.clock = clock

        root = config["osc"]["root"]
        self.root = "/" + root.strip("/") + "/"
        self.deck = int(config["deck"]["number"])
        self.channel = int(config["midi"]["channel"]) - 1

        notes = config["notes"]
        self.note_names: dict[int, str] = {}
        for name, num in notes.items():
            if name != "pads":
                self.note_names[int(num)] = name
        self.pad_notes: list[int] = [int(n) for n in notes["pads"]]
        self.needle_touch_note = int(config["needle"]["touch_note"])

        # Controller-side state
        self.shift = False
        self.mode = "hotcue"
        self.key_lock = False
        self.slip = False
        self.platter_touched = False
        self.needle_touched = False
        self.pitch_msb = 0
        self.pitch_lsb = 0
        self.last_tempo: float | None = None
        self.held_pads: dict[int, tuple[str, tuple]] = {}   # pad index -> release call
        self.cue_held = False
        self.censor_held = False

        # Jog state
        self.bend_dir = 0
        self.last_jog_time = 0.0
        self.seek_tick_acc = 0

        # Syndicate-side state (from feedback)
        self.playing = False
        self.play_pending = False
        self.loaded = False
        self.sync = False
        self.slider_enabled = True
        self.loop_on = False
        self.progress: float | None = None
        self.duration: float | None = None
        self.cues: list[int] = [0] * 8          # colour slot 1-8 per cue, 0 = empty
        self.palette = dict(DEFAULT_PALETTE)
        self.led_cache: dict[int, int] = {}

    # ------------------------------------------------------------------ OSC out
    def osc(self, path: str, *args: Any) -> None:
        for a in args:
            if isinstance(a, bool) or not isinstance(a, (int, float)):
                raise TypeError(f"OSC arg for {path} must be int or float, got {a!r}")
        self._send_osc(self.root + path, *args)

    def deck_osc(self, path: str, *args: Any) -> None:
        self.osc(f"Deck/{self.deck}/{path}", *args)

    def start(self) -> None:
        """Ask Syndicate for full state, then paint the LEDs."""
        self.osc("Feedback/Resend", 1)
        self.led_cache.clear()
        self.refresh_leds()

    def release_all(self) -> None:
        """Release every Hold/Bend we may have left pressed (exit or disconnect)."""
        if self.bend_dir:
            self.deck_osc("PhaseBend", 0)
            self.bend_dir = 0
        if self.cue_held:
            self.deck_osc("Cue", 0)
            self.cue_held = False
        if self.censor_held:
            self.deck_osc("Reverse", 0)
            self.censor_held = False
        for path, args in list(self.held_pads.values()):
            self.deck_osc(path, *args)
        self.held_pads.clear()

    # ----------------------------------------------------------------- MIDI in
    def handle_midi(self, msg: mido.Message) -> None:
        if getattr(msg, "channel", None) != self.channel:
            return
        if msg.type in ("note_on", "note_off"):
            pressed = msg.type == "note_on" and msg.velocity > 0
            self._handle_note(msg.note, pressed)
        elif msg.type == "control_change":
            self._handle_cc(msg.control, msg.value)

    def _handle_note(self, note: int, pressed: bool) -> None:
        if note in self.pad_notes:
            self._handle_pad(self.pad_notes.index(note), pressed)
            return
        if note == self.needle_touch_note:
            self.needle_touched = pressed
            return
        name = self.note_names.get(note)
        if name is None:
            return
        handler = getattr(self, f"_btn_{name}", None)
        if handler:
            handler(pressed)

    # Buttons. Triggers fire on press only; Holds send 1 then 0.
    def _btn_play(self, p):
        if p:
            self.deck_osc("PlayPause", 1)

    def _btn_cue(self, p):
        self.cue_held = p
        self.deck_osc("Cue", 1 if p else 0)

    def _btn_beat_jump_back(self, p):
        if p:
            self.deck_osc("SkipBarBack" if self.shift else "SkipBeatBack", 1)

    def _btn_beat_jump_forward(self, p):
        if p:
            self.deck_osc("SkipBarForward" if self.shift else "SkipBeatForward", 1)

    def _btn_track_prev(self, p):
        if p:
            self.osc("Browser/Up", 1)

    def _btn_track_next(self, p):
        if p:
            self.osc("Browser/Down", 1)

    def _btn_censor(self, p):
        self.censor_held = p
        self.deck_osc("Reverse", 1 if p else 0)

    def _btn_loop_in(self, p):
        if p:
            self.deck_osc("LoopIn", 1)

    def _btn_loop_out(self, p):
        if p:
            self.deck_osc("LoopOut", 1)

    def _btn_auto_loop(self, p):
        if p:
            self.deck_osc("Loop", 1)

    def _btn_back(self, p):
        if p:
            self.osc("Browser/Back", 1)

    def _btn_forward(self, p):
        if p:
            self.osc("Browser/Enter", 1)

    def _btn_select_press(self, p):
        if p:
            self.osc("Browser/Enter" if self.shift else f"Browser/L{self.deck}", 1)

    def _btn_sync(self, p):
        if p:
            self.deck_osc("TempoSync", 1)

    def _btn_master(self, p):
        if p:
            self.deck_osc("TempoMaster", 1)

    def _btn_key_lock(self, p):
        if p:
            self.key_lock = not self.key_lock
            self.deck_osc("PitchPreserve", 1 if self.key_lock else 0)
            self.refresh_leds()

    def _btn_slip(self, p):
        if p:
            self.slip = not self.slip
            self.deck_osc("CueSlip", 1 if self.slip else 0)
            self.refresh_leds()

    def _btn_pitch_minus(self, p):
        if p:
            self.deck_osc("PitchReset" if self.shift else "PitchDown", 1)

    def _btn_pitch_plus(self, p):
        if p:
            self.deck_osc("PitchReset" if self.shift else "PitchUp", 1)

    def _btn_shift(self, p):
        self.shift = p
        self.refresh_leds()

    def _set_mode(self, mode):
        self.release_pads()
        self.mode = mode
        self.refresh_leds()

    def _btn_mode_hotcue(self, p):
        if p:
            self._set_mode("hotcue")

    def _btn_mode_roll(self, p):
        if p:
            self._set_mode("roll")

    def _btn_mode_loop(self, p):
        if p:
            self._set_mode("loop")

    def _btn_mode_slicer(self, p):
        if p:
            self._set_mode("slicer")

    def _btn_platter_touch(self, p):
        self.platter_touched = p
        if not p and self.bend_dir:
            self.deck_osc("PhaseBend", 0)
            self.bend_dir = 0

    def _btn_param_back(self, p):
        if p:
            self.deck_osc("BeatSkip", -1)

    def _btn_param_forward(self, p):
        if p:
            self.deck_osc("BeatSkip", 1)

    # Pads
    def release_pads(self) -> None:
        for path, args in list(self.held_pads.values()):
            self.deck_osc(path, *args)
        self.held_pads.clear()

    def _handle_pad(self, i: int, pressed: bool) -> None:
        if not pressed:
            release = self.held_pads.pop(i, None)
            if release:
                self.deck_osc(release[0], *release[1])
            return
        cue = i + 1
        if self.mode == "hotcue":
            self.deck_osc("HotCue", cue, 1)
            self.held_pads[i] = ("HotCue", (cue, 0))
        elif self.mode == "roll":
            path = f"SlipLoop/{ROLL_SIZES[i]}"
            self.deck_osc(path, 1)
            self.held_pads[i] = (path, (0,))
        elif self.mode == "loop":
            self.deck_osc("SetCueLoop", cue)
        # slicer: not mapped (no matching Syndicate OSC route)

    # CCs
    def _handle_cc(self, cc: int, value: int) -> None:
        c = self.cfg
        if cc in c["jog"]["ccs"]:
            self._jog(relative_ticks(value))
        elif cc == c["pitch"]["msb_cc"]:
            self.pitch_msb = value
            self._send_pitch()
        elif cc == c["pitch"]["lsb_cc"]:
            self.pitch_lsb = value
            self._send_pitch()
        elif cc == c["needle"]["cc"]:
            if self.needle_touched or not c["needle"]["require_touch"]:
                self.deck_osc("WaveformSeek", value / 127.0)
        elif cc == c["browse"]["select_turn_cc"]:
            ticks = relative_ticks(value)
            for _ in range(abs(ticks)):
                self.osc("Browser/Down" if ticks > 0 else "Browser/Up", 1)
        elif cc == c["browse"]["auto_loop_size_cc"]:
            ticks = relative_ticks(value)
            if ticks:
                # While looping, LoopIn halves and LoopOut doubles the loop.
                self.deck_osc("LoopOut" if ticks > 0 else "LoopIn", 1)

    def _send_pitch(self) -> None:
        pc = self.cfg["pitch"]
        t = pitch_to_tempo_slider(join_14bit(self.pitch_msb, self.pitch_lsb),
                                  invert=pc["invert"], dead_zone=pc["dead_zone"])
        t = round(t, 5)
        if t != self.last_tempo:
            self.last_tempo = t
            self.deck_osc("TempoSlider", float(t))

    def _jog(self, ticks: int) -> None:
        if ticks == 0:
            return
        jc = self.cfg["jog"]
        if jc["require_touch"] and not self.platter_touched:
            return
        self.last_jog_time = self.clock()
        if self.playing:
            direction = 1 if ticks > 0 else -1
            if direction != self.bend_dir:
                self.bend_dir = direction
                self.deck_osc("PhaseBend", direction)
            return
        # Paused: move the playhead.
        if self.duration and self.progress is not None:
            delta = ticks * jc["seek_seconds_per_tick"] / self.duration
            self.progress = max(0.0, min(1.0, self.progress + delta))
            self.deck_osc("WaveformSeek", float(self.progress))
        else:
            self.seek_tick_acc += ticks
            per_beat = jc["seek_fallback_ticks_per_beat"]
            beats = int(self.seek_tick_acc / per_beat)
            if beats:
                self.seek_tick_acc -= beats * per_beat
                self.deck_osc("BeatSkip", beats)

    def tick(self) -> None:
        if self.bend_dir and self.clock() - self.last_jog_time >= self.cfg["jog"]["bend_release_ms"] / 1000:
            self.deck_osc("PhaseBend", 0)
            self.bend_dir = 0

    # ------------------------------------------------------------- OSC in (feedback)
    def handle_osc(self, address: str, *args: Any) -> None:
        if not address.lower().startswith(self.root.lower()):
            return
        path = address[len(self.root):]
        lower = path.lower()

        if lower == "colorpalette" and len(args) >= 4:
            self.palette[int(args[0])] = (int(args[1]), int(args[2]), int(args[3]))
            self.refresh_leds()
            return

        prefix = f"deck/{self.deck}/"
        if not lower.startswith(prefix):
            return
        key = lower[len(prefix):]
        v = args[0] if args else None

        if key == "playing":
            self.playing = bool(v)
            if not self.playing and self.bend_dir:
                self.deck_osc("PhaseBend", 0)
                self.bend_dir = 0
        elif key == "playpending":
            self.play_pending = bool(v)
        elif key == "loaded":
            self.loaded = bool(v)
            if not self.loaded:
                self.cues = [0] * 8
                self.progress = None
                self.duration = None
        elif key == "trackinfo" and len(args) >= 5:
            self.duration = float(args[4]) or None
            return
        elif key == "progress":
            self.progress = float(v)
            return
        elif key == "sync":
            self.sync = bool(v)
        elif key == "tempoSliderEnabled".lower():
            self.slider_enabled = bool(v)
        elif key == "loop":
            self.loop_on = bool(v)
        elif key == "cues":
            colours = [int(a) for a in args[0::2]][:8]
            self.cues = colours + [0] * (8 - len(colours))
        else:
            return
        self.refresh_leds()

    # --------------------------------------------------------------------- LEDs
    def _led(self, note: int, velocity: int) -> None:
        if self.led_cache.get(note) == velocity:
            return
        self.led_cache[note] = velocity
        self._send_midi(mido.Message("note_on", channel=self.channel, note=int(note), velocity=int(velocity)))

    def _button_led(self, name: str, on: bool) -> None:
        note = self.cfg["notes"].get(name)
        if note is None:
            return
        idle = DIM if self.cfg["leds"]["dim_unlit_buttons"] else OFF
        self._led(note, FULL if on else idle)

    def pad_colours(self) -> list[int]:
        leds = self.cfg["leds"]
        if self.mode == "hotcue":
            return [rgb_to_velocity(*self.palette.get(c, (255, 255, 255))) if c else OFF for c in self.cues]
        if self.mode == "loop":
            loop = rgb_to_velocity(*leds["loop_pad_color"])
            return [loop if c else OFF for c in self.cues]
        if self.mode == "roll":
            return [rgb_to_velocity(*leds["roll_pad_color"])] * 8
        return [OFF] * 8

    def refresh_leds(self) -> None:
        is_master = self.sync and self.slider_enabled
        self._button_led("play", self.playing or self.play_pending)
        self._button_led("cue", self.loaded and not self.playing)
        self._button_led("sync", self.sync)
        self._button_led("master", is_master)
        self._button_led("key_lock", self.key_lock)
        self._button_led("slip", self.slip)
        self._button_led("shift", self.shift)
        self._button_led("loop_in", self.loop_on)
        self._button_led("loop_out", self.loop_on)
        self._button_led("auto_loop", self.loop_on)
        for m in MODES:
            self._button_led(f"mode_{m}", self.mode == m)
        self._led(self.cfg["leds"]["pitch_center"], FULL if self.last_tempo == 0.0 else OFF)
        for note, vel in zip(self.pad_notes, self.pad_colours()):
            self._led(note, vel)
        ring = rgb_to_velocity(*self.cfg["leds"]["ring_color"]) if self.loaded else OFF
        self._led(self.cfg["leds"]["ring"], ring)
