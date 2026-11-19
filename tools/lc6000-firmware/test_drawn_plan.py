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
                 answers=None, words=None, cut_upper_write_at=None, cut_reports_ok=False):
        self.folder = folder
        self.app = bytearray(app)
        self.upper = bytearray(upper if upper is not None else b"\xff" * UPPER_SIZE)
        self.options = options
        self.devices = devices
        self.answers = {"both_true": "y", "all_true": "y", "probe": "y", "stock_look": "y", **(answers or {})}
        self.words = words or {}
        self.cut_upper_write_at = cut_upper_write_at
        self.cut_reports_ok = cut_reports_ok
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
            failed = area == "upper" and self.cut_upper_write_at is not None and not self.cut_reports_ok
            record(action[4], "1" if failed else "0")
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




class RewriteTests(DrawnPlanTests):
    # #501's first B: version 2, the 20-byte header, CRC from Python's zlib (as test_drawn_flash): an older good B.
    OLD_B = bytes.fromhex("44465742" "02000000" "1d000000" "72dfb522" "15000808") + b"123456789"

    def test_a_b_only_rewrite_writes_b_behind_rewrite_and_leaves_the_app_area_alone(self):
        # The chip runs the owner's image already, so it's both "runs now" and "the owner's image" (#560).
        self.current = self.owner
        upper = self.OLD_B + b"\xff" * (UPPER_SIZE - len(self.OLD_B))
        unit = FakeUnit(self.dir.name, self.owner_element, upper=upper)
        self.assertEqual(unit.run(self.plan()), ("done",))
        kinds = self.kinds(unit)
        self.assertEqual(kinds[kinds.index("read upper"):], [
            "read upper", "type word_upper", "write upper", "read upper", "skip app_step",
            "power-cycle", "ask stock_look", "done"])
        self.assertEqual([(a[1], a[2]) for a in unit.log if a[0] == "type"], [("word_upper", "REWRITE")])
        self.assertEqual(unit.writes, ["upper"])
        self.assertEqual(bytes(unit.app), self.owner_element)
        block = good_block()
        self.assertEqual(bytes(unit.upper[:len(block)]), block)
        self.assertEqual(set(unit.upper[len(block):]), {0xFF})

    def test_b_already_there_and_the_image_too_writes_nothing(self):
        self.current = self.owner
        block = good_block()
        unit = FakeUnit(self.dir.name, self.owner_element, upper=block + b"\xff" * (UPPER_SIZE - len(block)))
        self.assertEqual(unit.run(self.plan()), ("done",))
        self.assertEqual(unit.writes, [])
        self.assertIn("skip upper_step", self.kinds(unit))
        self.assertIn("skip app_step", self.kinds(unit))



class CutOffTests(DrawnPlanTests):
    """A write of B cut off part way (#567): the run stops before the owner's image, and a new run rewrites B."""

    def cut_run(self, reports_ok):
        unit = FakeUnit(self.dir.name, self.current_element, cut_upper_write_at=20, cut_reports_ok=reports_ok)   # B is 37 bytes: part of it
        end = unit.run(self.plan())
        self.assertEqual(end[0], "stop")
        self.assertEqual(unit.writes, ["upper"], "the owner's image is never written after a bad B")
        return unit, end

    def test_dfu_util_reporting_the_error_stops_with_the_way_back(self):
        _, end = self.cut_run(reports_ok=False)
        self.assertIn("dfu-util reported an error writing block B", end[1])

    def test_a_cut_write_dfu_util_called_good_is_caught_by_the_read_back(self):
        unit, end = self.cut_run(reports_ok=True)
        self.assertIn("isn't exactly block B after the write", end[1])
        self.assertEqual(self.kinds(unit)[-2:], ["read upper", "stop"])

    def test_a_new_run_sees_part_of_b_and_rewrites_it(self):
        unit, _ = self.cut_run(reports_ok=False)
        again = FakeUnit(self.dir.name, self.current_element, upper=bytes(unit.upper))
        self.assertEqual(again.run(self.plan()), ("done",))
        self.assertEqual([(a[1], a[2]) for a in again.log if a[0] == "type"],
                         [("word_upper", "REWRITE"), ("word_app", "FLASH")])
        block = good_block()
        self.assertEqual(bytes(again.upper[:len(block)]), block)
        self.assertEqual(bytes(again.app), self.owner_element)



class DeviceListTests(DrawnPlanTests):
    """Exactly one device, and it's the display chip, before any read (#567)."""

    def stopped_before_reading(self, devices, answers=None):
        unit = FakeUnit(self.dir.name, self.current_element, devices=devices, answers=answers)
        end = unit.run(self.plan())
        self.assertEqual(end[0], "stop")
        self.assertFalse([a for a in unit.log if a[0] in ("read", "write")], "nothing read or written")
        return end[1]

    def test_no_device_stops(self):
        self.assertIn("0 update-mode devices", self.stopped_before_reading(()))

    def test_two_chips_in_update_mode_stop(self):
        why = self.stopped_before_reading((("2-1.2", DISPLAY_LAYOUT), ("2-1.3", TOP_PANEL_LAYOUT)))
        self.assertIn("2 update-mode devices", why)

    def test_the_top_panel_chip_alone_stops_with_a_plain_message(self):
        # The owner's slip on 2026-11-19: BACK + FWD + VINYL, so the one device was the top panel chip (256 KB).
        why = self.stopped_before_reading((("2-1.2", "@Internal Flash  /0x08000000/04*016Kg,01*064Kg,01*128Kg"),))
        self.assertIn("top panel chip", why)

    def test_another_layout_asks_and_no_stops(self):
        other = (("2-1.2", "@Internal Flash  /0x08000000/12*016Kg"),)
        self.assertIn("isn't the display chip's", self.stopped_before_reading(other, {"list_layout_go_on": "n"}))

    def test_another_layout_answered_yes_goes_on(self):
        unit = FakeUnit(self.dir.name, self.current_element, devices=(("2-1.2", "@Internal Flash  /0x08000000/12*016Kg"),),
                        answers={"list_layout_go_on": "y", "list_again_layout_go_on": "y"})
        self.assertEqual(unit.run(self.plan()), ("done",))



def options(rdp=0xAA, half=0x0FFF):
    return bytes([0xEC, rdp]) + b"\xff" * 6 + bytes([half & 0xFF, half >> 8]) + b"\xff" * 6


class RefusalTests(DrawnPlanTests):
    """Each refusal stops the run; one before the first write writes nothing (#567)."""

    def refused(self, expect, writes=(), **unit):
        unit.setdefault("app", self.current_element)
        app = unit.pop("app")
        fake = FakeUnit(self.dir.name, app, **unit)
        end = fake.run(self.plan())
        self.assertEqual(end[0], "stop", fake.log)
        self.assertIn(expect, end[1])
        self.assertEqual(fake.writes, list(writes))
        return fake

    def test_read_protection_on_stops_before_any_write(self):
        self.refused("read protection is on", options=options(rdp=0xBB))

    def test_a_write_protected_upper_sector_stops_before_any_write(self):
        self.refused("sector 9", options=options(half=0x0FFF & ~(1 << 9)))

    def test_a_wrong_word_for_b_writes_nothing(self):
        self.refused("not FLASH", words={"word_upper": "flash"})

    def test_a_wrong_word_for_the_image_writes_only_b(self):
        self.refused("not FLASH", writes=["upper"], words={"word_app": "yes"})

    def test_no_probe_without_the_phrase_stops_before_update_mode(self):
        fake = self.refused("not NO PROBE", answers={"probe": "n"}, words={"no_probe": "y"})
        self.assertNotIn("update-mode", self.kinds(fake))

    def test_no_probe_with_the_phrase_goes_on(self):
        fake = FakeUnit(self.dir.name, self.current_element, answers={"probe": "n"})
        self.assertEqual(fake.run(self.plan()), ("done",))

    def test_the_files_swapped_stop_before_anything_is_sent(self):
        self.upper, self.owner = self.owner, self.upper
        # B's file given as the owner's image fails its own check first; either way, nothing is sent.
        fake = self.refused("Nothing was sent")
        self.assertEqual(fake.log[0][0], "stop")

    def test_a_chip_not_holding_the_image_it_runs_now_stops_before_any_write(self):
        other = bytearray(self.current_element)
        other[0x100] ^= 1
        self.refused("doesn't hold the image it runs now", app=bytes(other))

    def test_something_else_in_the_upper_flash_stops_before_any_write(self):
        upper = bytearray(b"\xff" * UPPER_SIZE)
        upper[0x40000] = 0
        self.refused("Nothing is written over it", upper=bytes(upper))

    def test_not_ready_stops_before_anything_is_sent(self):
        for key in ("both_true", "all_true"):
            with self.subTest(key):
                fake = self.refused("Not ready", answers={key: "n"})
                self.assertNotIn("update-mode", self.kinds(fake))

    def test_a_display_not_like_stock_after_the_power_cycle_stops(self):
        self.refused("doesn't look like stock", writes=["upper", "app"], answers={"stock_look": "n"})


class FreshnessTests(DrawnPlanTests):
    """A plan file never lets stale facts authorize a write (#567): each write rests on its own read, made in this run
    after update mode was entered."""

    def test_a_plan_file_left_from_a_completed_run_asks_for_everything_again(self):
        path = self.plan()
        self.assertEqual(FakeUnit(self.dir.name, self.current_element).run(path), ("done",))
        # The same file, begun again for a new run.
        drawn_plan.begin(path, current=self.current, upper=self.upper, owner=self.owner, work=self.dir.name)
        self.assertEqual(drawn_plan.next_action(path)[:2], ("ask", "both_true"))

    def test_facts_from_another_run_kept_in_the_file_authorize_nothing(self):
        # A completed run's facts left in the file under a new run id: the reads come again before any write.
        path = self.plan()
        self.assertEqual(FakeUnit(self.dir.name, self.current_element).run(path), ("done",))
        plan = drawn_plan.load(path)
        plan["run"] = "another-run"
        drawn_plan.save(path, plan)
        unit = FakeUnit(self.dir.name, self.current_element)
        unit.run(path)
        kinds = self.kinds(unit)
        self.assertLess(kinds.index("read upper"), kinds.index("write upper"))
        self.assertLess(kinds.index("read app"), kinds.index("write app"))
        self.assertEqual(kinds[0], "ask both_true")

    def test_a_read_made_before_update_mode_is_read_again(self):
        path = self.plan()
        for key in ("both_true", "all_true", "probe"):
            drawn_plan.record(path, key, "y")
        upper = self.write("old-upper.bin", b"\xff" * UPPER_SIZE)
        drawn_plan.record(path, "upper_read", upper)   # before update mode
        drawn_plan.record(path, "update_mode", "ok")
        unit = FakeUnit(self.dir.name, self.current_element)
        unit.run(path)
        reads = [a[4] for a in unit.log if a[0] == "read"]
        self.assertIn("upper_read", reads)
        self.assertLess(self.kinds(unit).index("read upper"), self.kinds(unit).index("write upper"))


if __name__ == "__main__":
    unittest.main()
