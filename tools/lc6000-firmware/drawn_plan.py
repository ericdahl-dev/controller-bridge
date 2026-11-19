#!/usr/bin/env python3
"""The drawn wizard's plan (#567): every decision of `flash-day.sh drawn` in one place. The facts so far in, the next
step out; the shell only does what it's told (dfu-util, the keyboard) and records the result.

  python3 -I drawn_plan.py begin PLAN.json CURRENT.dfu UPPER.dfu OWNER.dfu WORK
  python3 -I drawn_plan.py next PLAN.json         one action, its fields separated by tabs
  python3 -I drawn_plan.py record PLAN.json KEY VALUE
  python3 -I drawn_plan.py devices LISTING        the stock wizard's look: one PATH, ask PATH QUESTION, or stop WHY

Actions:
  ask KEY QUESTION                 a y/N question; record y or n
  type KEY WORD PROMPT             a typed word (FLASH, REWRITE, NO PROBE); record what was typed
  update-mode                      put the display chip in update mode; record ok or failed
  list OUT KEY                     dfu-util -l into OUT; record its path
  read AREA DFU_PATH OUT KEY       dfu-util -U of app, upper or options into OUT; record OUT, or failed
  write AREA DFU_PATH IMAGE KEY    dfu-util -D of IMAGE; record its exit code
  power-cycle                      the owner power-cycles; record ok or failed
  skip KEY TEXT                    say TEXT; record seen
  stop REASON                      say REASON and the way back
  done

Freshness: every write rests on a read made in this run, after update mode was entered; a fact from an earlier run
or from before update mode authorizes nothing, and the read is asked for again.
Standard library only; nothing here talks to the unit."""
import contextlib, io, json, os, sys, types, uuid

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))  # -I leaves this folder off sys.path (#468)
import build_upper_dfu  # noqa: E402
import dfupatch  # noqa: E402
import drawn_flash  # noqa: E402

# Every step `next` can ask for: the shell handles exactly these.
ACTIONS = ("ask", "type", "update-mode", "list", "read", "write", "power-cycle", "skip", "stop", "done")

DISPLAY_LAYOUT = "/0x08000000/04*016Kg,01*064Kg,07*128Kg"  # 1 MB, single bank: the display chip (#432)
TOP_PANEL_LAYOUT = "/0x08000000/04*016Kg,01*064Kg,01*128Kg"  # 256 KB: the top panel chip (#434)


# MARK: the plan file

def begin(path, current, upper, owner, work):
    """A new run: the owner's files, and no facts. A plan file from an earlier run is replaced, never continued."""
    plan = {"run": uuid.uuid4().hex[:12], "files": {"current": current, "upper": upper, "owner": owner},
            "work": work, "seq": 0, "facts": {}}
    save(path, plan)


def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, plan):
    with open(path, "w") as f:
        json.dump(plan, f, indent=1)


def record(path, key, value):
    plan = load(path)
    plan["seq"] += 1
    plan["facts"][key] = {"value": value, "run": plan["run"], "seq": plan["seq"]}
    save(path, plan)


def fact(plan, key):
    """A fact of this run, or None."""
    entry = plan["facts"].get(key)
    return entry["value"] if entry and entry["run"] == plan["run"] else None


def fresh(plan, key):
    """A read made in this run after update mode was entered: the only kind a write may rest on."""
    entry, entered = plan["facts"].get(key), plan["facts"].get("update_mode")
    return (entry is not None and entered is not None and entry["run"] == plan["run"] == entered["run"]
            and entered["value"] == "ok" and entry["seq"] > entered["seq"] and entry["value"] != "failed")


# MARK: the judges, from drawn_flash.py and dfupatch.py, as values

def judged(function, **arguments):
    """(True, what it printed) or (False, why it refused)."""
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            function(types.SimpleNamespace(**arguments))
    except (dfupatch.Refused, OSError) as error:
        return False, str(error)
    return True, out.getvalue().strip()


def checked(plan, name, function, files):
    """`judged`, remembered in the plan by the files' contents: a file check depends only on what the files hold, so a
    changed file is checked again and an unchanged one isn't re-read (dfupatch's verify walks all 480 KB)."""
    import hashlib
    digest = hashlib.sha256()
    for path in files.values():
        with open(path, "rb") as f:
            digest.update(f.read())
    key = f"{name}:{digest.hexdigest()}"
    cache = plan.setdefault("checks", {})
    if key not in cache:
        cache[key] = judged(function, **files)
    return tuple(cache[key])


def devices(listing_path):
    """The DFU devices dfu-util -l saw: {path: [alt names]}, 0483:df11 only."""
    import re
    found = {}
    with open(listing_path) as f:
        for line in f:
            if "Found DFU" not in line or "[0483:df11]" not in line.lower():
                continue
            path = re.search(r'path="([^"]*)"', line)
            name = re.search(r'name="([^"]*)"', line)
            if path:
                found.setdefault(path.group(1), []).append(name.group(1) if name else "")
    return found


# MARK: the plan

def out(plan, name):
    return os.path.join(plan["work"], f"{name}-{plan['run']}")


def next_action(path):
    plan = load(path)
    action = decide(plan)
    save(path, plan)   # the remembered file checks
    return action


def decide(plan):
    files = plan["files"]
    # Ready check: nothing sent.
    for label, image in (("the image the chip runs now", files["current"]), ("the owner's image", files["owner"])):
        ok, why = checked(plan, "verify", dfupatch.verify, {"input": image})
        if not ok:
            return ("stop", f"{label} doesn't verify: {why}. Nothing was sent.")
    ok, why = checked(plan, "files", drawn_flash.files, {"upper": files["upper"], "owner": files["owner"]})
    if not ok:
        return ("stop", f"Those aren't block B and the owner's image in their places: {why}. Nothing was sent.")
    for key, question in (
            ("both_true", "Block A, in the owner's image, was built with ARM_UPPER_PROVEN=1, and A and B from the "
                          "same commit (#516). Both true?"),
            ("all_true", "DeckBridge and every other DJ or MIDI app quit, Denon's updater not open, the LC6000 on a "
                         "direct cable and running normally, no gig today. All of that true?")):
        answer = fact(plan, key)
        if answer is None:
            return ("ask", key, question)
        if answer != "y":
            return ("stop", "Not ready. Nothing was sent.")
    probe = fact(plan, "probe")
    if probe is None:
        return ("ask", "probe", "Is an ST-Link probe connected, and can it read the chip (#433)?")
    if probe != "y":
        typed = fact(plan, "no_probe")
        if typed is None:
            return ("type", "no_probe", drawn_flash.NO_PROBE, drawn_flash.NO_PROBE_RISK)
        if typed.strip() != drawn_flash.NO_PROBE:
            return ("stop", f"You typed {typed.strip()!r}, not {drawn_flash.NO_PROBE}. Nothing was sent.")
    # Update mode, and the one device.
    entered = fact(plan, "update_mode")
    if entered is None:
        return ("update-mode",)
    if entered != "ok":
        return ("stop", "The display chip didn't come up in update mode.")
    dfu_path, problem = one_display_chip(plan, "list")
    if problem:
        return problem
    # Before (read-only): the app, the option bytes, the upper flash.
    if unreadable(plan, "app_read"):
        return unreadable(plan, "app_read")
    if not fresh(plan, "app_read"):
        return ("read", "app", dfu_path, out(plan, "wd-app-before"), "app_read")
    ok, why = judged(dfupatch.compare, input=files["current"], readback=fact(plan, "app_read"))
    if not ok:
        return ("stop", f"The chip doesn't hold the image it runs now ({why}). Nothing was written.")
    ok, app_state = judged(drawn_flash.app, owner=files["owner"], read=fact(plan, "app_read"))
    if not ok:
        return ("stop", f"The app area couldn't be judged against the owner's image: {app_state}")
    if unreadable(plan, "options_read"):
        return unreadable(plan, "options_read")
    if not fresh(plan, "options_read"):
        return ("read", "options", dfu_path, out(plan, "wd-option-bytes"), "options_read")
    ok, why = judged(drawn_flash.options, read=fact(plan, "options_read"))
    if not ok:
        return ("stop", f"The chip's protection isn't what block B needs: {why}. Nothing was written.")
    if unreadable(plan, "upper_read"):
        return unreadable(plan, "upper_read")
    if not fresh(plan, "upper_read"):
        return ("read", "upper", dfu_path, out(plan, "wd-upper-before"), "upper_read")
    ok, upper_state = judged(drawn_flash.upper, upper=files["upper"], read=fact(plan, "upper_read"))
    if not ok:
        return ("stop", f"The flash above the image is neither erased, this block B, nor a block B that checks out: "
                        f"{upper_state}. Nothing is written over it.")
    # Step 1: block B.
    step = step_upper(plan, dfu_path, upper_state)
    if step:
        return step
    # Step 2: the owner's image.
    step = step_app(plan, dfu_path, app_state)
    if step:
        return step
    # Power cycle, and the stock look.
    cycled = fact(plan, "power_cycle")
    if cycled is None:
        return ("power-cycle",)
    if cycled != "ok":
        return ("stop", "The display's MIDI port didn't come back after the power cycle.")
    look = fact(plan, "stock_look")
    if look is None:
        return ("ask", "stock_look", "With no host talking to it, does the display look exactly like stock?")
    if look != "y":
        return ("stop", "The display doesn't look like stock with no host.")
    return ("done",)


WHAT = {"app_read": "the app area", "options_read": "the option bytes", "upper_read": "the flash above the image",
        "upper_back": "block B's read-back", "app_back": "the owner's image's read-back"}


def unreadable(plan, key):
    """A stop when this run's read of `key` failed (dfu-util refused it), so it's never just asked for again."""
    if fact(plan, key) != "failed":
        return None
    return ("stop", f"{WHAT[key][0].upper()}{WHAT[key][1:]} couldn't be read, so it can't be checked. Nothing more is "
                    f"written.")


def judge_devices(listing):
    """What dfu-util -l saw (#567): ("one", path) for exactly one device that is the display chip; ("ask", path,
    question) for one device whose layout isn't the display chip's (the owner may go on); ("stop", why) for none, two,
    or the top panel chip. Both wizards' look uses it."""
    found = devices(listing)
    if len(found) != 1:
        return ("stop", f"{len(found)} update-mode devices found; exactly one, the display chip, is needed. Two "
                        f"means the top panel chip is in update mode too.")
    (dfu_path, names), = found.items()
    if any(TOP_PANEL_LAYOUT in name for name in names):
        return ("stop", "That's the top panel chip (256 KB), not the display chip. It's in update mode from "
                        "BACK + FWD + VINYL: power the LC6000 off and on to leave it. Nothing was read or written.")
    if not any(DISPLAY_LAYOUT in name for name in names):
        return ("ask", dfu_path, "Its memory layout isn't the display chip's 1 MB one. Go on anyway?")
    return ("one", dfu_path)


def one_display_chip(plan, key):
    """(the DFU path, None), or (None, an action): exactly one device, and it's the display chip."""
    listing = fact(plan, key)
    if listing is None:
        return None, ("list", out(plan, f"dfu-{key}"), key)
    judged_devices = judge_devices(listing)
    if judged_devices[0] == "stop":
        return None, judged_devices
    dfu_path = judged_devices[1]
    if judged_devices[0] == "ask":
        go_on = fact(plan, f"{key}_layout_go_on")
        if go_on is None:
            return None, ("ask", f"{key}_layout_go_on", judged_devices[2])
        if go_on != "y":
            return None, ("stop", "Its memory layout isn't the display chip's. Nothing was read or written.")
    return dfu_path, None


def step_upper(plan, dfu_path, upper_state):
    files = plan["files"]
    if upper_state.startswith("holds"):
        if fact(plan, "upper_step") is None:
            return ("skip", "upper_step", "Block B is already there, exactly. Step 1 has nothing to write.")
        return None
    rewrite = upper_state.startswith("replace")
    word = "REWRITE" if rewrite else "FLASH"
    written = fact(plan, "upper_written")
    if written is None:
        typed = fact(plan, "word_upper")
        if typed is None:
            return ("type", "word_upper", word, f"This ERASES and WRITES the display chip's upper flash, from "
                                                f"0x08080000 as far as block B reaches. Type {word} to write it.")
        if typed.strip() != word:
            return ("stop", f"You typed {typed.strip()!r}, not {word}. Nothing was written.")
        image = files["upper"]
        if rewrite:
            image = out(plan, "wd-upper-rewrite") + ".dfu"
            if not os.path.exists(image):
                ok, why = judged(drawn_flash.rewrite, upper=files["upper"], read=fact(plan, "upper_read"), output=image)
                if not ok:
                    return ("stop", f"The rewrite file couldn't be made: {why}. Nothing was written.")
        return ("write", "upper", dfu_path, image, "upper_written")
    if written != "0":
        return ("stop", "dfu-util reported an error writing block B. Don't retry blindly. Until the owner's image is "
                        "on, the image there now runs as before: a part of B is never called.")
    if fact(plan, "upper_back") is None:
        return ("read", "upper", dfu_path, out(plan, "wd-upper-after"), "upper_back")
    if unreadable(plan, "upper_back"):
        return unreadable(plan, "upper_back")
    ok, state = judged(drawn_flash.upper, upper=files["upper"], read=fact(plan, "upper_back"))
    if not ok or not state.startswith("holds"):
        return ("stop", "The upper flash isn't exactly block B after the write. Block A checks B's CRC before calling "
                        "it, so it stays unused. Don't flash the owner's image on top: post this on #468.")
    return None


def step_app(plan, dfu_path, app_state):
    files = plan["files"]
    if app_state.startswith("holds"):
        if fact(plan, "app_step") is None:
            return ("skip", "app_step", "The owner's image is already there, exactly. Nothing to write: the app "
                                        "area isn't touched.")
        return None
    written = fact(plan, "app_written")
    if written is None:
        again, problem = one_display_chip(plan, "list_again")
        if problem:
            return problem
        if again != dfu_path:
            return ("stop", "The display chip isn't at the same USB path any more.")
        typed = fact(plan, "word_app")
        if typed is None:
            return ("type", "word_app", "FLASH", "This ERASES and WRITES the display chip's app area "
                                                 "(0x08008000-0x0807FFFF). Type FLASH to write it.")
        if typed.strip() != "FLASH":
            return ("stop", f"You typed {typed.strip()!r}, not FLASH. Nothing was written.")
        return ("write", "app", dfu_path, files["owner"], "app_written")
    if written != "0":
        return ("stop", "dfu-util reported an error writing the owner's image. Don't power-cycle: the chip is still "
                        "in update mode, so Denon's updater or the slot 16 image can go on now.")
    if fact(plan, "app_back") is None:
        return ("read", "app", dfu_path, out(plan, "wd-app-after"), "app_back")
    if unreadable(plan, "app_back"):
        return unreadable(plan, "app_back")
    ok, why = judged(dfupatch.compare, input=files["owner"], readback=fact(plan, "app_back"))
    if not ok:
        return ("stop", f"What's on the chip differs from the owner's image ({why}). Don't power-cycle into it: "
                        f"flash the stock or slot 16 image again.")
    return None


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    command = argv[0] if argv else ""
    if command == "begin" and len(argv) == 6:
        begin(argv[1], current=argv[2], upper=argv[3], owner=argv[4], work=argv[5])
    elif command == "next" and len(argv) == 2:
        # One line, fields separated by tabs; a field's own line breaks as \\n (the shell prints them with %b).
        print("\t".join(field.replace("\\", "\\\\").replace("\n", "\\n") for field in next_action(argv[1])))
    elif command == "devices" and len(argv) == 2:
        print("\t".join(judge_devices(argv[1])))
    elif command == "record" and len(argv) == 4:
        record(argv[1], argv[2], argv[3])
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
