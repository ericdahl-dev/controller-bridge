import mido
import pytest

from lc6000_bridge.config import load_config
from lc6000_bridge.coordinator import Coordinator, PortNotFound


class FakeInput:
    def __init__(self):
        self.pending = []
        self.closed = False

    def iter_pending(self):
        msgs, self.pending = self.pending, []
        return iter(msgs)

    def close(self):
        self.closed = True


class FakeOutput:
    def __init__(self):
        self.sent = []
        self.closed = False

    def send(self, msg):
        self.sent.append(msg)

    def close(self):
        self.closed = True


class Rig:
    """A fake LC6000 plus a fake Syndicate, plugged into a Coordinator."""

    def __init__(self, inputs=("DENON LC6000 PRIME",), outputs=("DENON LC6000 PRIME",), cfg=None):
        self.t = 0.0
        self.osc = []
        self.inp = FakeInput()
        self.out = FakeOutput()
        self.opened = []
        self.coord = Coordinator(
            cfg or load_config(),
            list_inputs=lambda: list(inputs),
            list_outputs=lambda: list(outputs),
            open_input=lambda name: self.opened.append(("in", name)) or self.inp,
            open_output=lambda name: self.opened.append(("out", name)) or self.out,
            send_osc=lambda addr, *a: self.osc.append((addr, a)),
            clock=lambda: self.t,
        )

    def press(self, note, on=True):
        self.inp.pending.append(mido.Message("note_on", channel=0, note=note, velocity=127 if on else 0))

    def turn(self, cc, value):
        self.inp.pending.append(mido.Message("control_change", channel=0, control=cc, value=value))

    def leds(self):
        return {m.note: m.velocity for m in self.out.sent}


def test_start_opens_matching_ports_and_asks_for_state():
    rig = Rig(inputs=("IAC Bus 1", "DENON LC6000 PRIME"))
    rig.coord.start()
    assert rig.opened == [("in", "DENON LC6000 PRIME"), ("out", "DENON LC6000 PRIME")]
    assert rig.osc == [("/Syndicate/Feedback/Resend", (1,))]


def test_poll_turns_controller_midi_into_osc():
    rig = Rig()
    rig.coord.start()
    rig.osc.clear()
    rig.press(1)                       # Play
    rig.press(1, on=False)
    rig.coord.poll()
    assert rig.osc == [("/Syndicate/Deck/1/PlayPause", (1,))]


def test_poll_releases_jog_nudge_after_wheel_stops():
    rig = Rig()
    rig.coord.start()
    rig.coord.feedback("/Syndicate/Deck/1/Playing", 1)
    rig.osc.clear()
    rig.turn(55, 0x03)                 # jog forward while playing
    rig.coord.poll()
    assert rig.osc == [("/Syndicate/Deck/1/PhaseBend", (1,))]
    rig.t = 0.5                        # wheel idle well past the release time
    rig.coord.poll()
    assert rig.osc[-1] == ("/Syndicate/Deck/1/PhaseBend", (0,))


def test_feedback_lights_the_controller():
    rig = Rig()
    rig.coord.start()
    assert rig.leds()[1] == 1          # Play LED dim while stopped
    rig.coord.feedback("/Syndicate/Deck/1/Playing", 1)
    assert rig.leds()[1] == 127        # full once Syndicate says playing


def test_stop_releases_held_controls_and_closes_ports():
    rig = Rig()
    rig.coord.start()
    rig.press(2)                       # hold Cue
    rig.press(34)                      # hold hot cue 3
    rig.coord.poll()
    rig.osc.clear()
    rig.coord.stop()
    assert set(rig.osc) == {("/Syndicate/Deck/1/Cue", (0,)), ("/Syndicate/Deck/1/HotCue", (3, 0))}
    assert rig.inp.closed and rig.out.closed


def test_missing_controller_names_the_ports_that_exist():
    rig = Rig(inputs=("IAC Bus 1",))
    with pytest.raises(PortNotFound) as err:
        rig.coord.start()
    assert "LC6000" in str(err.value) and "IAC Bus 1" in str(err.value)
    assert rig.opened == []


def test_no_output_port_still_bridges_without_leds():
    rig = Rig(outputs=())
    rig.coord.start()
    rig.osc.clear()
    rig.press(1)
    rig.coord.poll()
    rig.coord.stop()
    assert rig.osc == [("/Syndicate/Deck/1/PlayPause", (1,))]
    assert ("out", None) not in rig.opened and rig.out.sent == []
