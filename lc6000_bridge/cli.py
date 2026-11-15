"""Command line: run the bridge, monitor raw MIDI, sweep LEDs, list ports."""

from __future__ import annotations

import argparse
import signal
import sys
import threading
import time

import mido
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import ThreadingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient

from .bridge import Bridge
from .config import load_config


def _find_port(names: list[str], wanted: str, kind: str) -> str:
    for n in names:
        if wanted.lower() in n.lower():
            return n
    listing = "\n  ".join(names) or "(none)"
    sys.exit(f"No MIDI {kind} port matching {wanted!r}. Available:\n  {listing}\n"
             f"Use --midi-{kind} or set [midi].{kind} in your mapping file.")


def cmd_ports(_args, _cfg) -> None:
    print("MIDI inputs:");  [print("  " + n) for n in mido.get_input_names()]
    print("MIDI outputs:"); [print("  " + n) for n in mido.get_output_names()]


def cmd_monitor(args, cfg) -> None:
    """Print every MIDI message with the mapping name it matches."""
    port = _find_port(mido.get_input_names(), cfg["midi"]["input"], "input")
    notes = {v: k for k, v in cfg["notes"].items() if k != "pads"}
    for i, n in enumerate(cfg["notes"]["pads"]):
        notes[n] = f"pad{i + 1}"
    ccs = {cfg["pitch"]["msb_cc"]: "pitch_msb", cfg["pitch"]["lsb_cc"]: "pitch_lsb",
           cfg["needle"]["cc"]: "needle", cfg["browse"]["select_turn_cc"]: "select_turn",
           cfg["browse"]["auto_loop_size_cc"]: "auto_loop_size"}
    for c in cfg["jog"]["ccs"]:
        ccs[c] = "jog"
    print(f"Monitoring {port}. Ctrl-C to stop.")
    with mido.open_input(port) as inp:
        for msg in inp:
            label = ""
            if msg.type in ("note_on", "note_off"):
                label = notes.get(msg.note, "UNMAPPED")
            elif msg.type == "control_change":
                label = ccs.get(msg.control, "UNMAPPED")
            ch = getattr(msg, "channel", -1) + 1
            print(f"{time.monotonic():12.3f}  ch{ch:<2} {str(msg):<50} {label}")


def cmd_led_sweep(args, cfg) -> None:
    """Step pads + ring through all 64 colour velocities, then every button note."""
    port = _find_port(mido.get_output_names(), cfg["midi"]["output"], "output")
    ch = int(cfg["midi"]["channel"]) - 1
    pads = cfg["notes"]["pads"] + [cfg["leds"]["ring"]]
    with mido.open_output(port) as out:
        print("Colour sweep: velocity shown on every pad and the ring. Note what each looks like.")
        for vel in range(64):
            for n in pads:
                out.send(mido.Message("note_on", channel=ch, note=n, velocity=vel))
            print(f"  velocity {vel:2d} (0x{vel:02X}) = rgb222 r{vel >> 4 & 3} g{vel >> 2 & 3} b{vel & 3}")
            time.sleep(args.delay)
        for n in pads:
            out.send(mido.Message("note_on", channel=ch, note=n, velocity=0))
        print("Button sweep: each note at full, then dim, then off.")
        for note in range(0, 128):
            if note in pads:
                continue
            for vel in (127, 1, 0):
                out.send(mido.Message("note_on", channel=ch, note=note, velocity=vel))
                time.sleep(args.delay / 3)
            print(f"  note {note}", end="\r")
        print()


def cmd_run(args, cfg) -> None:
    oc = cfg["osc"]
    client = SimpleUDPClient(oc["host"], int(oc["port"]))
    in_name = _find_port(mido.get_input_names(), cfg["midi"]["input"], "input")
    out_names = mido.get_output_names()
    out_port = None
    if not args.no_leds:
        try:
            out_port = mido.open_output(_find_port(out_names, cfg["midi"]["output"], "output"))
        except SystemExit as e:
            print(f"LEDs disabled: {e}", file=sys.stderr)

    def send_osc(address, *a):
        if args.verbose:
            print("OSC ->", address, *a)
        client.send_message(address, list(a) if len(a) != 1 else a[0])

    lock = threading.Lock()
    bridge = Bridge(cfg, send_osc, out_port.send if out_port else None)

    dispatcher = Dispatcher()
    def on_feedback(address, *a):
        if args.verbose:
            print("OSC <-", address, *a)
        with lock:
            bridge.handle_osc(address, *a)
    dispatcher.set_default_handler(on_feedback)
    server = ThreadingOSCUDPServer((oc["feedback_host"], int(oc["feedback_port"])), dispatcher)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    stop = threading.Event()
    def ticker():
        while not stop.is_set():
            with lock:
                bridge.tick()
            time.sleep(0.01)
    threading.Thread(target=ticker, daemon=True).start()

    def shutdown(*_):
        stop.set()
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    print(f"LC6000 '{in_name}' -> Syndicate deck {bridge.deck} at {oc['host']}:{oc['port']}; "
          f"feedback on :{oc['feedback_port']}. Ctrl-C to stop.")
    with mido.open_input(in_name) as inp:
        with lock:
            bridge.start()
        try:
            while not stop.is_set():
                for msg in inp.iter_pending():
                    with lock:
                        bridge.handle_midi(msg)
                time.sleep(0.001)
        finally:
            with lock:
                bridge.release_all()
            server.shutdown()
            if out_port:
                out_port.close()


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="lc6000-bridge", description=__doc__)
    p.add_argument("--config", help="mapping TOML that overrides the defaults")
    p.add_argument("--deck", type=int, help="Syndicate deck 1-4")
    p.add_argument("--midi-input", help="MIDI input port name (substring)")
    p.add_argument("--midi-output", help="MIDI output port name (substring)")
    p.add_argument("--host", help="Syndicate OSC host")
    p.add_argument("--port", type=int, help="Syndicate OSC listen port")
    p.add_argument("--feedback-port", type=int, help="local port for Syndicate OSC feedback")
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="run the bridge")
    r.add_argument("--no-leds", action="store_true")
    r.add_argument("-v", "--verbose", action="store_true", help="print OSC traffic")
    sub.add_parser("monitor", help="print incoming LC6000 MIDI with mapping names")
    s = sub.add_parser("led-sweep", help="cycle LED colours/notes to verify the LED map")
    s.add_argument("--delay", type=float, default=0.6)
    sub.add_parser("ports", help="list MIDI ports")
    args = p.parse_args(argv)

    cfg = load_config(args.config)
    if args.deck:
        cfg["deck"]["number"] = args.deck
    if args.midi_input:
        cfg["midi"]["input"] = args.midi_input
    if args.midi_output:
        cfg["midi"]["output"] = args.midi_output
    if args.host:
        cfg["osc"]["host"] = args.host
    if args.port:
        cfg["osc"]["port"] = args.port
    if args.feedback_port:
        cfg["osc"]["feedback_port"] = args.feedback_port

    {"run": cmd_run, "monitor": cmd_monitor, "led-sweep": cmd_led_sweep, "ports": cmd_ports}[args.cmd](args, cfg)


if __name__ == "__main__":
    main()
