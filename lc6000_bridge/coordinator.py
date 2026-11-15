"""Runs one Bridge against plugged-in MIDI ports, an OSC sender and a clock.

Real ports and sockets are supplied by the command line; tests supply fakes.
"""

from __future__ import annotations

import threading
import time
from typing import Any, Callable

from .bridge import Bridge


class PortNotFound(Exception):
    pass


def _match(names: list[str], wanted: str) -> str | None:
    for n in names:
        if wanted.lower() in n.lower():
            return n
    return None


class Coordinator:
    def __init__(self, cfg: dict, *, list_inputs: Callable[[], list[str]],
                 list_outputs: Callable[[], list[str]], open_input: Callable[[str], Any],
                 open_output: Callable[[str], Any], send_osc: Callable[..., None],
                 clock: Callable[[], float] = time.monotonic):
        self.cfg = cfg
        self._list_inputs = list_inputs
        self._list_outputs = list_outputs
        self._open_input = open_input
        self._open_output = open_output
        self._send_osc = send_osc
        self._clock = clock
        self._lock = threading.Lock()
        self.inp = None
        self.out = None
        self.bridge: Bridge | None = None

    def start(self) -> None:
        inputs = self._list_inputs()
        wanted = self.cfg["midi"]["input"]
        in_name = _match(inputs, wanted)
        if in_name is None:
            listing = "\n  ".join(inputs) or "(none)"
            raise PortNotFound(f"No MIDI input port matching {wanted!r}. Available:\n  {listing}\n"
                               f"Use --midi-input or set [midi].input in your mapping file.")
        self.inp = self._open_input(in_name)
        out_name = _match(self._list_outputs(), self.cfg["midi"]["output"])
        self.out = self._open_output(out_name) if out_name else None   # None: no LEDs
        self.bridge = Bridge(self.cfg, self._send_osc, self.out.send if self.out else None,
                             clock=self._clock)
        with self._lock:
            self.bridge.start()

    def poll(self) -> None:
        """Handle every pending controller message, then run timers."""
        for msg in self.inp.iter_pending():
            with self._lock:
                self.bridge.handle_midi(msg)
        with self._lock:
            self.bridge.tick()

    def stop(self) -> None:
        """Release everything held in Syndicate, then close the ports."""
        with self._lock:
            self.bridge.release_all()
        self.inp.close()
        if self.out:
            self.out.close()

    def feedback(self, address: str, *args: Any) -> None:
        """Syndicate OSC feedback. Safe to call from the listener thread."""
        with self._lock:
            self.bridge.handle_osc(address, *args)
