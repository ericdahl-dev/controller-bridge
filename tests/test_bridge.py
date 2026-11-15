import socket
import threading

import mido
import pytest
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import ThreadingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient

from lc6000_bridge.bridge import Bridge
from lc6000_bridge.codec import join_14bit, pitch_to_tempo_slider, relative_ticks, rgb_to_velocity
from lc6000_bridge.config import load_config


# ---------------------------------------------------------------- codec
def test_relative_ticks():
    assert relative_ticks(0) == 0
    assert relative_ticks(0x01) == 1
    assert relative_ticks(0x3F) == 63
    assert relative_ticks(0x7F) == -1
    assert relative_ticks(0x40) == -64


def test_join_14bit_and_pitch():
    assert join_14bit(0x7F, 0x7F) == 16383
    assert join_14bit(0x40, 0x00) == 8192
    assert pitch_to_tempo_slider(0) == -1.0
    assert pitch_to_tempo_slider(16383) == 1.0
    assert pitch_to_tempo_slider(16383, invert=True) == -1.0
    assert pitch_to_tempo_slider(8192, dead_zone=0.01) == 0.0


def test_rgb_to_velocity():
    assert rgb_to_velocity(0, 0, 0) == 0
    assert rgb_to_velocity(255, 0, 0) == 0b110000
    assert rgb_to_velocity(0, 255, 0) == 0b001100
    assert rgb_to_velocity(255, 255, 255) == 0x3F
    assert rgb_to_velocity(20, 0, 0) != 0  # dim colours still light


# ---------------------------------------------------------------- bridge
class Clock:
    t = 0.0
    def __call__(self):
        return self.t


@pytest.fixture
def rig():
    cfg = load_config()
    sent, leds, clock = [], [], Clock()
    b = Bridge(cfg, lambda a, *x: sent.append((a, x)), leds.append, clock=clock)
    return b, sent, leds, clock


def note(n, on=True):
    return mido.Message("note_on", channel=0, note=n, velocity=127 if on else 0)


def cc(c, v):
    return mido.Message("control_change", channel=0, control=c, value=v)


def test_trigger_only_on_press(rig):
    b, sent, *_ = rig
    b.handle_midi(note(1)); b.handle_midi(note(1, False))
    assert sent == [("/Syndicate/Deck/1/PlayPause", (1,))]


def test_hold_sends_release(rig):
    b, sent, *_ = rig
    b.handle_midi(note(2)); b.handle_midi(note(2, False))
    assert sent == [("/Syndicate/Deck/1/Cue", (1,)), ("/Syndicate/Deck/1/Cue", (0,))]


def test_other_channel_ignored(rig):
    b, sent, *_ = rig
    b.handle_midi(mido.Message("note_on", channel=3, note=1, velocity=127))
    assert sent == []


def test_hotcue_pad_hold(rig):
    b, sent, *_ = rig
    b.handle_midi(note(34)); b.handle_midi(note(34, False))
    assert sent == [("/Syndicate/Deck/1/HotCue", (3, 1)), ("/Syndicate/Deck/1/HotCue", (3, 0))]


def test_roll_mode_and_mode_switch_releases(rig):
    b, sent, *_ = rig
    b.handle_midi(note(28))           # roll mode
    b.handle_midi(note(32))           # pad 1 held
    b.handle_midi(note(27))           # switch to hot cue while held
    assert ("/Syndicate/Deck/1/SlipLoop/ThirtySecond", (1,)) in sent
    assert sent[-1] == ("/Syndicate/Deck/1/SlipLoop/ThirtySecond", (0,))


def test_pitch_fader_14bit(rig):
    b, sent, *_ = rig
    b.handle_midi(cc(8, 0x7F)); b.handle_midi(cc(40, 0x7F))
    addr, (val,) = sent[-1]
    assert addr == "/Syndicate/Deck/1/TempoSlider" and val == 1.0 and isinstance(val, float)
    n = len(sent)
    b.handle_midi(cc(40, 0x7F))       # duplicate value: not resent
    assert len(sent) == n


def test_jog_bend_while_playing_then_release(rig):
    b, sent, _, clock = rig
    b.handle_osc("/Syndicate/Deck/1/Playing", 1)
    b.handle_midi(cc(55, 0x03)); b.handle_midi(cc(55, 0x02))
    assert sent == [("/Syndicate/Deck/1/PhaseBend", (1,))]
    b.handle_midi(cc(55, 0x7E))
    assert sent[-1] == ("/Syndicate/Deck/1/PhaseBend", (-1,))
    clock.t = 0.05; b.tick()
    assert sent[-1][1] == (-1,)
    clock.t = 0.2; b.tick()
    assert sent[-1] == ("/Syndicate/Deck/1/PhaseBend", (0,))


def test_jog_seek_while_paused(rig):
    b, sent, *_ = rig
    b.handle_osc("/Syndicate/Deck/1/TrackInfo", "t", "a", "8A", 120.0, 200.0, 100, 400, "track")
    b.handle_osc("/Syndicate/Deck/1/Progress", 0.5)
    b.handle_midi(cc(55, 10))     # 10 ticks * 0.02 s / 200 s = 0.001
    addr, (val,) = sent[-1]
    assert addr == "/Syndicate/Deck/1/WaveformSeek" and val == pytest.approx(0.501)


def test_jog_fallback_beatskip_without_duration(rig):
    b, sent, *_ = rig
    for _ in range(4):
        b.handle_midi(cc(55, 0x08))   # 32 ticks = 1 beat
    assert sent == [("/Syndicate/Deck/1/BeatSkip", (1,))]


def test_release_all(rig):
    b, sent, *_ = rig
    b.handle_osc("/Syndicate/Deck/1/Playing", 1)
    b.handle_midi(note(2)); b.handle_midi(note(32)); b.handle_midi(cc(55, 1))
    sent.clear()
    b.release_all()
    assert set(sent) == {("/Syndicate/Deck/1/PhaseBend", (0,)), ("/Syndicate/Deck/1/Cue", (0,)),
                         ("/Syndicate/Deck/1/HotCue", (1, 0))}


def test_feedback_drives_leds(rig):
    b, _, leds, _ = rig
    b.handle_osc("/Syndicate/ColorPalette", 3, 0, 0, 255)
    b.handle_osc("/Syndicate/Deck/1/Cues", 3, "Drop", 0, "", *([0, ""] * 6))
    b.handle_osc("/syndicate/deck/1/playing", 1)        # case-insensitive
    last = {m.note: m.velocity for m in leds}
    assert last[32] == rgb_to_velocity(0, 0, 255)       # pad 1 = cue 1 in palette slot 3
    assert last[33] == 0                                # empty cue off
    assert last[1] == 127                               # play LED on
    b.handle_osc("/Syndicate/Deck/2/Playing", 0)        # other deck ignored
    assert {m.note: m.velocity for m in leds}[1] == 127


def test_osc_args_must_be_numbers(rig):
    b, *_ = rig
    with pytest.raises(TypeError):
        b.deck_osc("PlayPause", True)


# ---------------------------------------------------------------- loopback over real UDP
def _free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]; s.close(); return port


def test_udp_loopback():
    got, ev = [], threading.Event()
    d = Dispatcher()
    def h(addr, *a):
        got.append((addr, a)); ev.set()
    d.set_default_handler(h)
    port = _free_port()
    server = ThreadingOSCUDPServer(("127.0.0.1", port), d)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    client = SimpleUDPClient("127.0.0.1", port)
    b = Bridge(load_config(), lambda a, *x: client.send_message(a, list(x) if len(x) != 1 else x[0]))
    b.handle_midi(note(34))
    assert ev.wait(2)
    server.shutdown()
    assert got == [("/Syndicate/Deck/1/HotCue", (3, 1))]
