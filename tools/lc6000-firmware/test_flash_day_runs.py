"""Whole runs of the real `flash-day.sh drawn` (#567) against a fake unit: stand-ins for dfu-util, the update-mode tool
and swiftc on a PATH that holds only them and /usr/bin:/bin, with HOME and the work folder in a temporary folder. So the
real dfu-util, the real update-mode tool in ~/lc6000 and MIDI are out of reach, and each test checks that first: the
owner's unit may be plugged in while these run.
Run from the repo root: python3 -I -m unittest discover tools/lc6000-firmware"""
import os, shutil, subprocess, sys, tempfile, textwrap, unittest

import build_upper_dfu
import dfupatch
from test_build_owner_image import stock_like_element
from test_build_upper_dfu import good_block
from test_dfupatch import dfuse_file, full_wd_element

HERE = os.path.dirname(os.path.realpath(__file__))
WIZARD = os.path.join(HERE, "flash-day.sh")
APP, UPPER = 0x08008000, 0x08080000
DISPLAY_LAYOUT = "@Internal Flash  /0x08000000/04*016Kg,01*064Kg,07*128Kg"
OPTIONS_OK = bytes([0xEC, 0xAA]) + b"\xff" * 6 + bytes([0xFF, 0x0F]) + b"\xff" * 6

# The fake dfu-util: the unit is files in $FAKE_UNIT (app.bin, upper.bin, options.bin, listing.txt); every call is
# logged there. -U refuses an existing file, as dfu-util does.
FAKE_DFU_UTIL = textwrap.dedent('''\
    import os, sys
    sys.path.insert(0, {here!r})
    import dfupatch
    unit = os.environ["FAKE_UNIT"]
    args = sys.argv[1:]
    with open(os.path.join(unit, "calls.log"), "a") as log:
        log.write(" ".join(args) + "\\n")
    def opt(flag):
        return args[args.index(flag) + 1] if flag in args else None
    if "-l" in args:
        sys.stdout.write(open(os.path.join(unit, "listing.txt")).read())
        sys.exit(0)
    if opt("-U"):
        out = opt("-U")
        if os.path.exists(out):
            sys.exit("dfu-util: file exists")
        address, size = (int(x, 0) for x in opt("-s").split(":"))
        if opt("-a") == "1":
            data = open(os.path.join(unit, "options.bin"), "rb").read()[:size]
        else:
            name, base = ("app.bin", {app}) if address == {app} else ("upper.bin", {upper})
            data = open(os.path.join(unit, name), "rb").read()[address - base:address - base + size]
        open(out, "wb").write(data)
        sys.exit(0)
    if opt("-D"):
        image = dfupatch.parse(dfupatch.read(opt("-D")))
        name, base = ("app.bin", {app}) if image.address == {app} else ("upper.bin", {upper})
        path = os.path.join(unit, name)
        memory = bytearray(open(path, "rb").read())
        memory[image.address - base:image.address - base + len(image.element)] = image.element
        open(path, "wb").write(bytes(memory))
        sys.exit(0)
    sys.exit("fake dfu-util: unexpected " + " ".join(args))
    ''')
# The update-mode tool's stand-in, which the fake swiftc "builds": it sends nothing, and logs each call.
FAKE_UPDATE_MODE = '#!/bin/sh\necho "$@" >> "$FAKE_UNIT/update-mode.log"\nexit 0\n'


class FlashDayRunTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        root = self.dir.name
        self.stubs, self.unit, self.work, self.home = (os.path.join(root, n) for n in ("stubs", "unit", "work", "home"))
        for folder in (self.stubs, self.unit, self.work, self.home):
            os.makedirs(folder)
        self.stub("dfu-util", f"#!{sys.executable} -I\n" + FAKE_DFU_UTIL.format(here=HERE, app=APP, upper=UPPER))
        update_mode = os.path.join(root, "update-mode-stub")
        with open(update_mode, "w") as f:
            f.write(FAKE_UPDATE_MODE)
        self.stub("swiftc", f'#!/bin/sh\nwhile [ "$1" != "-o" ]; do shift; done\ncp "{update_mode}" "$2"\nchmod +x "$2"\n')
        self.stub("pgrep", "#!/bin/sh\nexit 1\n")   # DeckBridge isn't running
        self.stub("python3", f'#!/bin/sh\nexec "{sys.executable}" "$@"\n')
        self.current_element, self.owner_element = full_wd_element(), stock_like_element()
        self.current = self.file("current.dfu", dfuse_file(self.current_element))
        self.owner = self.file("owner.dfu", dfuse_file(self.owner_element))
        self.upper = self.file("upper.dfu", build_upper_dfu.dfuse(good_block()))
        self.env = {"PATH": f"{self.stubs}:/usr/bin:/bin", "HOME": self.home, "LC6000_WORK": self.work,
                    "FAKE_UNIT": self.unit, "TERM": "dumb"}

    def stub(self, name, text):
        path = os.path.join(self.stubs, name)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)

    def file(self, name, content):
        path = os.path.join(self.dir.name, name)
        with open(path, "wb") as f:
            f.write(content)
        return path

    def unit_holds(self, app, upper=None, devices=(("2-1.2", DISPLAY_LAYOUT),)):
        with open(os.path.join(self.unit, "app.bin"), "wb") as f:
            f.write(app)
        with open(os.path.join(self.unit, "upper.bin"), "wb") as f:
            f.write(upper if upper is not None else b"\xff" * 0x80000)
        with open(os.path.join(self.unit, "options.bin"), "wb") as f:
            f.write(OPTIONS_OK)
        with open(os.path.join(self.unit, "listing.txt"), "w") as f:
            for path, layout in devices:
                f.write(f'Found DFU: [0483:df11] ver=2200, devnum=5, cfg=1, intf=0, path="{path}", alt=0, '
                        f'name="{layout}", serial="FFFFFFFEFFFF"\n')

    def assert_isolated(self):
        """Nothing these runs start can reach the real unit: only the stand-ins are on PATH."""
        for tool in ("dfu-util", "swiftc", "pgrep", "python3"):
            self.assertEqual(shutil.which(tool, path=self.env["PATH"]), os.path.join(self.stubs, tool), tool)
        real = shutil.which("dfu-util")
        if real:
            self.assertNotIn(os.path.dirname(real), self.env["PATH"].split(":"))
        self.assertNotEqual(self.env["HOME"], os.path.expanduser("~"))
        self.assertFalse(self.env["LC6000_WORK"].startswith(os.path.expanduser("~/lc6000")))

    def run_wizard(self, answers):
        self.assert_isolated()
        result = subprocess.run(["/bin/bash", WIZARD, "drawn"], input="\n".join(answers) + "\n", env=self.env,
                                cwd=self.dir.name, capture_output=True, text=True, timeout=300)
        # The update-mode tool that ran was the stand-in, never the real one.
        with open(os.path.join(self.unit, "update-mode.log")) as f:
            self.assertIn("send --yes-enter-update-mode", f.read())
        return result

    def memory(self, name):
        with open(os.path.join(self.unit, name), "rb") as f:
            return f.read()

    def downloads(self):
        with open(os.path.join(self.unit, "calls.log")) as f:
            return [line for line in f.read().splitlines() if " -D " in f" {line} "]

    def test_a_fresh_flash_writes_b_and_the_owners_image(self):
        self.unit_holds(self.current_element)
        answers = ["", self.current, self.upper, self.owner,   # banner; the three paths
                   "y", "y", "y",                               # both true, all true, the probe
                   "y",                                         # send the update-mode message
                   "FLASH", "FLASH",                            # block B, then the owner's image
                   "",                                          # power cycle: back on
                   "y",                                         # looks like stock
                   "", ""]                                      # the last two pauses
        result = self.run_wizard(answers)
        self.assertEqual(result.returncode, 0, result.stdout[-3000:] + result.stderr[-2000:])
        self.assertEqual(len(self.downloads()), 2)
        block = good_block()
        self.assertEqual(self.memory("upper.bin")[:len(block)], block)
        self.assertEqual(self.memory("app.bin"), self.owner_element)

    def test_a_b_only_rewrite_leaves_the_app_area_alone(self):
        old_b = bytes.fromhex("44465742" "02000000" "1d000000" "72dfb522" "15000808") + b"123456789"
        self.unit_holds(self.owner_element, upper=old_b + b"\xff" * (0x80000 - len(old_b)))
        answers = ["", self.owner, self.upper, self.owner, "y", "y", "y", "y", "REWRITE", "", "y", "", ""]
        result = self.run_wizard(answers)
        self.assertEqual(result.returncode, 0, result.stdout[-3000:] + result.stderr[-2000:])
        self.assertEqual(len(self.downloads()), 1)
        self.assertIn("wd-upper-rewrite", self.downloads()[0])
        self.assertEqual(self.memory("app.bin"), self.owner_element)
        block = good_block()
        self.assertEqual(self.memory("upper.bin")[:len(block)], block)

    def test_a_wrong_word_writes_nothing(self):
        self.unit_holds(self.current_element)
        result = self.run_wizard(["", self.current, self.upper, self.owner, "y", "y", "y", "y", "flash"])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.downloads(), [])
        self.assertEqual(self.memory("app.bin"), self.current_element)


if __name__ == "__main__":
    unittest.main()
