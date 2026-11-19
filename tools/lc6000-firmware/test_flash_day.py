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

    def test_the_script_parses(self):
        bash = shutil.which("bash")
        self.assertIsNotNone(bash)
        self.assertEqual(subprocess.run([bash, "-n", os.path.join(HERE, "flash-day.sh")]).returncode, 0)

    def test_the_stage_count_matches_the_stages_written(self):
        declared = int(re.search(r"^TOTAL_STAGES=(\d+)", self.stages, re.M).group(1))
        self.assertEqual(declared, len(re.findall(r'^stage "', self.stages, re.M)))

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

    def test_every_read_stays_in_the_settings_and_app_sectors(self):
        self.assertIn('APP_ADDRESS="0x08008000"; APP_SIZE="0x78000"', self.stages)
        self.assertIn('SETTINGS_ADDRESS="0x08004000"; SETTINGS_SIZE="0x4000"', self.stages)
        for upload in re.findall(r"dfu-util[^\n]*-U[^\n]*", self.stages):
            self.assertRegex(upload, r'-s "\$(APP|SETTINGS)_ADDRESS:\$(APP|SETTINGS)_SIZE"')

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
