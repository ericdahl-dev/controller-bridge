"""The drawn wizard's plan (#567): the facts so far in, the next step out. A fake unit plays the shell's part (dfu-util,
the keyboard), so whole runs are tested with no hardware. Nothing here talks to a unit.
Run from the repo root: python3 -I -m unittest discover tools/lc6000-firmware"""
import os, tempfile, unittest

import build_upper_dfu
import dfupatch
import drawn_plan
from test_build_owner_image import stock_like_element
from test_build_upper_dfu import good_block
from test_dfupatch import dfuse_file, full_wd_element

UPPER, UPPER_SIZE, APP_SIZE = 0x08080000, 0x80000, 0x78000
DISPLAY_LAYOUT = "@Internal Flash  /0x08000000/04*016Kg,01*064Kg,07*128Kg"
TOP_PANEL_LAYOUT = "@Internal Flash  /0x08000000/04*016Kg,01*064Kg,01*128Kg"
# The option bytes as read (RM0090: RDP 0xAA at +1; nWRP, DB1M and SPRMOD in the half-word at +8).
OPTIONS_OK = bytes([0xEC, 0xAA]) + b"\xff" * 6 + bytes([0xFF, 0x0F]) + b"\xff" * 6


def listing(*devices):
    """dfu-util -l's lines for each (path, alt 0 layout)."""
    return "".join(f'Found DFU: [0483:df11] ver=2200, devnum=5, cfg=1, intf=0, path="{path}", alt=0, name="{layout}", '
                   f'serial="FFFFFFFEFFFF"\n' for path, layout in devices)


class FakeUnit:
    """The display chip in update mode, and the owner at the keyboard: runs each action the plan asks for."""

    def __init__(self, folder, app, upper=None, options=OPTIONS_OK, devices=(("2-1.2", DISPLAY_LAYOUT),),
                 answers=None, words=None, cut_upper_write_at=None):
        self.folder = folder
        self.app = bytearray(app)
        self.upper = bytearray(upper if upper is not None else b"\xff" * UPPER_SIZE)
        self.options = options
        self.devices = devices
        self.answers = {"both_true": "y", "all_true": "y", "probe": "y", "stock_look": "y", **(answers or {})}
        self.words = words or {}
        self.cut_upper_write_at = cut_upper_write_at
        self.log = []
        self.writes = []

    def run(self, plan_path, limit=60):
        for _ in range(limit):
            action = drawn_plan.next_action(plan_path)
            self.log.append(action)
            kind = action[0]
            if kind in ("done", "stop"):
                return action
            self.act(plan_path, action)
        raise AssertionError(f"no end after {limit} steps: {self.log}")

    def file(self, name):
        return os.path.join(self.folder, name)

    def act(self, plan_path, action):
        kind = action[0]
        record = lambda key, value: drawn_plan.record(plan_path, key, value)
        if kind == "ask":
            record(action[1], self.answers.get(action[1], "y"))
        elif kind == "type":
            record(action[1], self.words.get(action[1], action[2]))
        elif kind == "update-mode":
            record("update_mode", "ok")
        elif kind == "list":
            with open(action[1], "w") as f:
                f.write(listing(*self.devices))
            record(action[2], action[1])
        elif kind == "read":
            area, path, out = action[1], action[2], action[3]
            data = {"app": self.app, "upper": self.upper, "options": self.options}[area]
            with open(out, "wb") as f:
                f.write(bytes(data))
            record(action[4], out)
        elif kind == "write":
            area, path, image = action[1], action[2], action[3]
            element = dfupatch.parse(dfupatch.read(image)).element
            self.writes.append(area)
            if area == "upper":
                if self.cut_upper_write_at is not None:
                    element = element[:self.cut_upper_write_at]
                self.upper[:len(element)] = element
            else:
                self.app[:len(element)] = element
            record(action[4], "0" if self.cut_upper_write_at is None or area != "upper" else "1")
        elif kind == "power-cycle":
            record("power_cycle", "ok")
        elif kind == "skip":
            record(action[1], "seen")
        else:
            raise AssertionError(f"unknown action {action}")


class DrawnPlanTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.current_element = full_wd_element()
        self.owner_element = stock_like_element()
        self.current = self.write("current.dfu", dfuse_file(self.current_element))
        self.owner = self.write("owner.dfu", dfuse_file(self.owner_element))
        self.upper = self.write("upper.dfu", build_upper_dfu.dfuse(good_block()))

    def write(self, name, content):
        path = os.path.join(self.dir.name, name)
        with open(path, "wb") as f:
            f.write(content)
        return path

    def plan(self):
        path = os.path.join(self.dir.name, "plan.json")
        drawn_plan.begin(path, current=self.current, upper=self.upper, owner=self.owner, work=self.dir.name)
        return path

    def kinds(self, unit):
        return [a[0] if a[0] not in ("read", "write", "ask", "type", "skip") else f"{a[0]} {a[1]}" for a in unit.log]


class FreshFlashTests(DrawnPlanTests):
    def test_a_fresh_flash_writes_b_then_the_image_each_behind_flash_and_reads_each_back(self):
        unit = FakeUnit(self.dir.name, self.current_element)
        end = unit.run(self.plan())
        self.assertEqual(end, ("done",))
        self.assertEqual(self.kinds(unit), [
            "ask both_true", "ask all_true", "ask probe", "update-mode", "list",
            "read app", "read options", "read upper",
            "type word_upper", "write upper", "read upper",
            "list", "type word_app", "write app", "read app",
            "power-cycle", "ask stock_look", "done"])
        words = [a for a in unit.log if a[0] == "type"]
        self.assertEqual([(w[1], w[2]) for w in words], [("word_upper", "FLASH"), ("word_app", "FLASH")])
        self.assertEqual(unit.writes, ["upper", "app"])
        block = good_block()
        self.assertEqual(bytes(unit.upper[:len(block)]), block)
        self.assertEqual(set(unit.upper[len(block):]), {0xFF})
        self.assertEqual(bytes(unit.app), self.owner_element)
        # Every dfu-util action names the one device's path.
        self.assertTrue(all(a[2] == "2-1.2" for a in unit.log if a[0] in ("read", "write")))


if __name__ == "__main__":
    unittest.main()
