"""Pure conversion helpers: MIDI values in, OSC values out (and back for LEDs)."""

from __future__ import annotations


def relative_ticks(value: int) -> int:
    """Decode an LC6000 relative CC value into signed ticks.

    Per the LC6000 PRIME MIDI spec: forward 0x01-0x3F, reverse 0x7F-0x40
    (two's-complement style, 0x7F = -1). 0 means no movement.
    """
    value &= 0x7F
    if value == 0:
        return 0
    if value < 0x40:
        return value
    return value - 0x80


def join_14bit(msb: int, lsb: int) -> int:
    """Combine a double-precision CC pair into 0..16383."""
    return ((msb & 0x7F) << 7) | (lsb & 0x7F)


def pitch_to_tempo_slider(value14: int, invert: bool = False, dead_zone: float = 0.0) -> float:
    """Map a 14-bit pitch fader position to Syndicate's TempoSlider (-1..+1)."""
    t = (value14 / 16383.0) * 2.0 - 1.0
    if invert:
        t = -t
    if abs(t) < dead_zone:
        t = 0.0
    return max(-1.0, min(1.0, t))


def rgb_to_velocity(r: int, g: int, b: int) -> int:
    """Quantise an 8-bit RGB colour to an LC6000 pad/ring colour velocity.

    ASSUMPTION (verify with `lc6000-bridge led-sweep`): the 64-entry colour
    table (velocities 0x00-0x3F) is 2 bits per channel, laid out 0b00RRGGBB.
    """
    def q(c: int) -> int:
        return max(0, min(3, round(c / 255 * 3)))

    vel = (q(r) << 4) | (q(g) << 2) | q(b)
    if vel == 0 and (r or g or b):
        # A dim-but-not-black colour should still light up.
        brightest = max((r, 2), (g, 1), (b, 0))[1]
        vel = 1 << (brightest * 2)
    return vel
