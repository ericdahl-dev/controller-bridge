"""Guards for the flash-day kit (#435): the wizard and the update-mode tool. No hardware, no vendor data.
Run from the repo root: python3 -I -m unittest discover tools/lc6000-firmware"""
import os, re, shutil, subprocess, unittest

HERE = os.path.dirname(os.path.realpath(__file__))


def text(name):
    with open(os.path.join(HERE, name)) as f:
        return f.read()


class WizardTests(unittest.TestCase):
    def setUp(self):
        self.script = text("flash-day.sh")
        self.stages = self.script[self.script.index("# STAGES:"):]

    def body(self, function):
        """One shell function's text, from its opening line to the closing brace at the start of a line."""
        start = self.stages.index(f"{function}() {{")
        return self.stages[start:self.stages.index("\n}\n", start)]

    def test_the_script_parses(self):
        bash = shutil.which("bash")
        self.assertIsNotNone(bash)
        self.assertEqual(subprocess.run([bash, "-n", os.path.join(HERE, "flash-day.sh")]).returncode, 0)

    def test_the_stage_count_matches_the_stages_written(self):
        for function in ("run_wizard", "run_drawn"):
            with self.subTest(function):
                body = self.body(function)
                declared = int(re.search(r"^TOTAL_STAGES=(\d+)", body, re.M).group(1))
                self.assertEqual(declared, len(re.findall(r'^stage "', body, re.M)))

    def test_the_only_write_to_the_chip_is_in_flash_behind_the_typed_word(self):
        downloads = [m.start() for m in re.finditer(r"dfu-util[^\n]*\s-D\s", self.stages)]
        self.assertEqual(len(downloads), 1)
        start, end = self.stages.index("flash() {"), self.stages.index("# reboot_check")
        self.assertTrue(start < downloads[0] < end)
        gate = self.stages.index('[[ "$typed" == "FLASH" ]] || way_back')
        self.assertTrue(start < gate < downloads[0])

    def test_no_dangerous_dfu_util_options_appear(self):
        for word in (":mass-erase", ":unprotect", ":force", "0x1FFF", "-s 0x08000000"):
            self.assertNotIn(word, self.stages)

    def test_every_read_stays_in_the_settings_app_and_upper_sectors(self):
        self.assertIn('APP_ADDRESS="0x08008000"; APP_SIZE="0x78000"', self.stages)
        self.assertIn('SETTINGS_ADDRESS="0x08004000"; SETTINGS_SIZE="0x4000"', self.stages)
        self.assertIn('UPPER_ADDRESS="0x08080000"; UPPER_SIZE="0x80000"', self.stages)
        for upload in re.findall(r"dfu-util[^\n]*-U[^\n]*", self.stages):
            self.assertRegex(upload, r'-s "\$(APP|SETTINGS|UPPER)_ADDRESS:\$\1_SIZE"')

    def test_the_stock_flash_is_denons_own_updater_before_any_patched_image(self):
        # Seen on hardware (2026-11-19): the updater flashes a chip that's in update mode, and refuses a running,
        # current unit. So Denon's tool does the stock flash, and dfu-util is kept for the patched image.
        stock = self.stages.index('stage "Stock flash: Denon\'s own updater"')
        patched = self.stages.index('stage "Patched image (optional)"')
        self.assertLess(stock, patched)
        between = self.stages[stock:patched]
        self.assertIn("Open Denon's updater", between)
        self.assertNotIn('flash "$STOCK_WD"', self.stages[:stock])

    def test_the_patched_stage_checks_the_chip_holds_stock_before_writing(self):
        patched = self.stages[self.stages.index('stage "Patched image (optional)"'):]
        self.assertLess(patched.index('dfupatch compare "$STOCK_WD"'), patched.index('flash "$PATCHED_WD" "patched"'))

    def test_the_way_back_says_update_mode_first_then_denons_updater(self):
        way_back = self.stages[self.stages.index("way_back() {"):self.stages.index("# dfu_paths")]
        self.assertIn("update mode", way_back)
        self.assertIn("refuses a unit that's running and current", way_back)
        self.assertIn("BACK + FWD + VINYL", way_back)

    def test_the_update_mode_message_needs_a_confirmation_first(self):
        send = self.stages.index("send --yes-enter-update-mode")
        ask = self.stages.index('confirm "Send the update-mode message to the display chip now?" || way_back')
        self.assertLess(ask, send)


class DrawnPathTests(unittest.TestCase):
    """The drawn flash (#468): `flash-day.sh drawn`, two writes, block B at 0x08080000, then the owner's image. The
    wizard is never run here: it builds and runs the real update-mode tool and dfu-util."""

    body = WizardTests.body

    def setUp(self):
        WizardTests.setUp(self)
        self.drawn = self.body("run_drawn")

    def test_the_drawn_path_runs_only_when_asked_for(self):
        self.assertIn('if [[ "${1:-}" == "drawn" ]]; then run_drawn; else run_wizard "$@"; fi', self.stages)

    def test_it_never_does_a_stock_flash(self):
        self.assertNotIn('flash "$STOCK_WD"', self.drawn)

    def test_both_files_are_checked_before_any_write(self):
        files = self.drawn.index('drawn files "$UPPER_DFU" "$OWNER_DFU"')
        self.assertLess(files, self.drawn.index("enter_update_mode"))
        self.assertLess(files, self.drawn.index('flash "$UPPER_DFU"'))

    def test_it_says_what_it_cant_check_and_asks(self):
        ready = self.drawn[:self.drawn.index('stage "Enter update mode')]
        self.assertIn("ARM_UPPER_PROVEN=1", ready)
        self.assertIn("same commit", ready)

    def test_the_chip_must_hold_the_image_it_runs_now_before_any_write(self):
        before = self.drawn.index('dfupatch compare "$CURRENT_WD"')
        self.assertLess(before, self.drawn.index('flash "$UPPER_DFU"'))

    def test_the_read_only_upper_read_is_the_gate_before_block_b(self):
        read = self.drawn.index('read_upper "$WORK/wd-upper-before-$STAMP.bin"')
        judged = self.drawn.index('drawn upper "$UPPER_DFU" "$WORK/wd-upper-before-$STAMP.bin"')
        self.assertLess(read, judged)
        self.assertLess(judged, self.drawn.index('flash "$UPPER_DFU"'))
        self.assertIn("way_back", self.drawn[judged:self.drawn.index('flash "$UPPER_DFU"')])

    def test_block_b_goes_first_then_the_owners_image_each_through_flash(self):
        # flash() asks for the typed word each time it's called, so each write has its own.
        upper = self.drawn.index('flash "$UPPER_DFU" "upper" upper')
        owner = self.drawn.index('flash "$OWNER_DFU" "owner" app')
        self.assertLess(upper, owner)

    def test_a_block_b_already_there_is_not_written_again(self):
        step_1 = self.drawn[self.drawn.index('stage "Step 1 of 2'):self.drawn.index('stage "Step 2 of 2')]
        self.assertLess(step_1.index('if (( B_DONE ))'), step_1.index('flash "$UPPER_DFU"'))

    def test_block_bs_write_is_read_back_and_judged(self):
        flash = self.body("flash")
        upper = flash[flash.index('if [[ "$area" == upper ]]; then', flash.index("-D")):]
        self.assertLess(upper.index('read_upper "$readback"'), upper.index('drawn upper "$image" "$readback"'))
        self.assertIn("^holds", upper)

    def test_the_way_back_says_block_b_stays_and_is_harmless(self):
        way_back = self.stages[self.stages.index("way_back() {"):self.stages.index("# dfu_paths")]
        self.assertIn("Block B", way_back)
        self.assertIn("only block A calls it", way_back)


class UpdateModeToolTests(unittest.TestCase):
    def setUp(self):
        self.source = text("enter-update-mode.swift")

    def test_it_sends_only_the_updaters_message(self):
        self.assertIn("[0xF0, 0x00, 0x02, 0x0B, 0x01, 0x10, 0x72, 0x00, 0x00, 0xF7]", self.source)
        self.assertEqual(self.source.count("MIDISendEventList("), 1)

    def test_it_only_addresses_the_wd_port_and_needs_exactly_one(self):
        self.assertIn('let portHint = "LC6000 PRIME WD"', self.source)
        self.assertIn("found.count == 1", self.source)

    def test_send_needs_its_long_flag(self):
        self.assertIn('case "send" where arguments.dropFirst().first == "--yes-enter-update-mode":', self.source)


if __name__ == "__main__":
    unittest.main()
