"""Tests for our block built for the display chip (#467): its layout, its reproducibility, and its two entry shims run
in an emulator (unicorn) against a synthetic flash. The stock functions the shims call are stubs here; no vendor bytes.

Run from tools/lc6000-display-fw after `make arm`:  python3 -I arm/test/test_block.py [BUILD_DIR]
Needs arm-none-eabi binutils and the `unicorn` Python package (pip install unicorn)."""
import os, shutil, struct, subprocess, sys, tempfile, unittest, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
FW = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(FW, "..", "lc6000-firmware"))
import dfupatch  # noqa: E402

import unicorn  # noqa: E402
from unicorn import arm_const as A  # noqa: E402

BUILD = os.environ.get("ARM_BUILD", os.path.join(FW, "build", "arm"))
PAD_START, PAD_END = dfupatch.PAD_START, dfupatch.PAD_END
MARKER = 0x31574644
MARKER_AT = PAD_END - 4
STATE_AT, SRAM_END = 0x2002AE94, 0x20030000

# The stock addresses the block uses (#466), and where the synthetic chip puts its stubs.
STOCK_RENDER, STOCK_MALLOC, STOCK_SEND = 0x0800BEA0, 0x08017860, 0x080144C4
UPTIME, RX_COUNT, RX, WITNESS = 0x20001BA0, 0x2000189A, 0x20001DE0, 0xE000E400
LAYER2_SURFACE_PIXELS = 0x20001DC0
FRAME_AT, LAYER_AT = 0xD0100000, 0xD0180000
RETURN = 0x08000100  # where a shim returns to: the test stops there
UPPER, UPPER_SIZE = 0x08080000, 0x80000  # block B's home (#501): sectors 8-11


def block():
    with open(os.path.join(BUILD, "block.bin"), "rb") as f:
        return f.read()


def symbols():
    out = subprocess.run(["arm-none-eabi-nm", os.path.join(BUILD, "block.elf")], capture_output=True, text=True,
                         check=True).stdout
    return {name: int(value, 16) for value, _, name in (line.split() for line in out.splitlines() if line.count(" ") == 2)}


def sections():
    out = subprocess.run(["arm-none-eabi-objdump", "-h", os.path.join(BUILD, "block.elf")], capture_output=True,
                         text=True, check=True).stdout
    found = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 7 and parts[0].isdigit():
            found[parts[1]] = (int(parts[2], 16), int(parts[3], 16))  # size, VMA
    return found


class LayoutTests(unittest.TestCase):
    def test_the_block_fills_the_padding_exactly_with_the_marker_last(self):
        data = block()
        self.assertEqual(len(data), PAD_END - PAD_START)
        self.assertEqual(struct.unpack_from("<I", data, len(data) - 4)[0], MARKER)

    def test_the_entries_sit_where_the_hook_patch_calls(self):
        names = symbols()
        self.assertEqual(names["hook_entry_command"] & ~1, dfupatch.HOOK_COMMAND_ENTRY)
        self.assertEqual(names["hook_entry_render"] & ~1, dfupatch.HOOK_RENDER_ENTRY)

    def test_nothing_needs_startup_code_and_our_state_sits_in_the_free_top_of_sram(self):
        found = sections()
        for name, (size, _) in found.items():
            if name.startswith((".data", ".bss")):
                self.assertEqual(size, 0, f"{name} would need startup code we don't have")
        size, at = found[".hookstate"]
        self.assertEqual(at, STATE_AT)
        self.assertLessEqual(at + size, SRAM_END)

    def test_no_allocator_is_linked_in(self):
        # The one stock malloc is called through a pointer (hook_stock.malloc); no allocator of our own exists.
        for name in symbols():
            self.assertNotRegex(name.lower(), r"malloc|calloc|realloc|free$|sbrk")

    def test_the_command_entry_ends_as_the_replaced_instruction_did(self):
        out = subprocess.run(["arm-none-eabi-objdump", "-d", "-j", ".entry_command", os.path.join(BUILD, "block.elf")],
                             capture_output=True, text=True, check=True).stdout
        self.assertIn("mov.w\tr8, #1", out)


class ReproducibleTests(unittest.TestCase):
    def test_two_builds_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as one, tempfile.TemporaryDirectory() as two:
            for out in (one, two):
                subprocess.run(["make", "-s", "-C", FW, "arm", f"ARM_BUILD={out}", "ARM_DRAW=stub"], check=True,
                               capture_output=True)
            for name in ("block.bin", "block.elf"):
                with open(os.path.join(one, name), "rb") as a, open(os.path.join(two, name), "rb") as b:
                    self.assertEqual(a.read(), b.read(), name)


class SizeTests(unittest.TestCase):
    """Each block's limit is a check on every toolchain that builds it, Mac and CI's Ubuntu GCC alike (#501): block A
    the 9,184-byte padding, block B the 512 KB upper flash."""

    def test_arm_size_reports_a_and_b_within_their_limits(self):
        with tempfile.TemporaryDirectory() as out:
            done = subprocess.run(["make", "-s", "-C", FW, "arm-size", f"ARM_SIZE_BUILD={out}"], capture_output=True,
                                  text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        lines = [line for line in done.stdout.splitlines() if line.startswith("block ")]
        self.assertEqual([line.split(":")[0] for line in lines],
                         ["block A (hook and protocol)", "block A (hook only)", "block B (drawing)"])
        for line, limit in zip(lines, (PAD_END - PAD_START, PAD_END - PAD_START, UPPER_SIZE)):
            used, of = (int(word) for word in line.split(":")[1].split()[0:3:2])
            self.assertEqual(of, limit, line)
            self.assertLessEqual(used, limit, line)

    def test_a_block_b_over_the_upper_flash_fails_arm_size(self):
        with tempfile.TemporaryDirectory() as out:
            big = os.path.join(out, "big.c")
            with open(big, "w") as f:
                f.write("const unsigned char upper_too_big[0x80000] = {1};\n"
                        "const unsigned char *upper_keep(void) { return upper_too_big; }\n")
            done = subprocess.run(["make", "-s", "-C", FW, "arm-size", f"ARM_SIZE_BUILD={out}/b",
                                   f"ARM_SIZE_UPPER_EXTRA={big}", "ARM_SIZE_UPPER_LDFLAGS=-Wl,-u,upper_keep"],
                                  capture_output=True, text=True)
        self.assertNotEqual(done.returncode, 0)
        self.assertRegex(done.stdout + done.stderr, r"block B \(drawing\): over|overflow")

    def test_a_block_too_big_for_the_padding_fails_the_link(self):
        with tempfile.TemporaryDirectory() as out:
            subprocess.run(["make", "-s", "-C", FW, "arm", f"ARM_BUILD={out}", "ARM_DRAW=0"], check=True,
                           capture_output=True)
            big_c, big_o = os.path.join(out, "big.c"), os.path.join(out, "big.o")
            with open(big_c, "w") as f:
                f.write("const unsigned char hook_too_big[9184] = {1};\n"
                        "const unsigned char *hook_keep(void) { return hook_too_big; }\n")
            cpu = ["-mcpu=cortex-m4", "-mthumb", "-mfloat-abi=hard", "-mfpu=fpv4-sp-d16"]
            subprocess.run(["arm-none-eabi-gcc", *cpu, "-c", big_c, "-o", big_o], check=True)
            objects = sorted(os.path.join(out, name) for name in os.listdir(out) if name.endswith(".o"))
            done = subprocess.run(["arm-none-eabi-gcc", *cpu, "-nostdlib", "-nostartfiles", "-Wl,-u,hook_keep",
                                   "-Wl,-T," + os.path.join(FW, "arm", "block.ld"), "-o", os.path.join(out, "x.elf"),
                                   *objects, "-lgcc"], capture_output=True, text=True)
        self.assertNotEqual(done.returncode, 0)
        self.assertRegex(done.stderr, r"doesn't fit|overflow")


class Chip:
    """A synthetic display chip: flash with our block in the padding and stubs where stock's functions are."""

    def __init__(self, marker=True, data=None, upper=None):
        self.uc = uc = unicorn.Uc(unicorn.UC_ARCH_ARM, unicorn.UC_MODE_THUMB | unicorn.UC_MODE_MCLASS)
        for base, size in ((0x08000000, 0x100000), (0x10000000, 0x10000), (0x20000000, 0x30000),
                           (0x40016000, 0x1000), (0xD0000000, 0x200000), (0xE000E000, 0x1000)):
            uc.mem_map(base, size)
        data = bytearray(data if data is not None else block())
        if not marker:
            data[-4:] = b"\xff\xff\xff\xff"
        uc.mem_write(PAD_START, bytes(data))
        # The upper flash, 0x08080000-0x080FFFFF: erased, unless a test puts a block B there.
        uc.mem_write(UPPER, b"\xff" * UPPER_SIZE)
        if upper is not None:
            uc.mem_write(UPPER, upper)
        self.upper_reads = 0

        def on_upper_read(uc, access, address, size, value, _):
            self.upper_reads += 1
        uc.hook_add(unicorn.UC_HOOK_MEM_READ, on_upper_read, begin=UPPER, end=UPPER + UPPER_SIZE - 1)
        bx_lr = b"\x70\x47"
        uc.mem_write(STOCK_RENDER, b"\x55\x20" + bx_lr)  # movs r0, #0x55 ; bx lr
        uc.mem_write(STOCK_MALLOC, b"\x00\x48" + bx_lr + struct.pack("<I", FRAME_AT))  # ldr r0, =FRAME_AT ; bx lr
        uc.mem_write(STOCK_SEND, bx_lr)
        uc.mem_write(RETURN, b"\x00\xbf")
        uc.mem_write(LAYER2_SURFACE_PIXELS, struct.pack("<I", LAYER_AT))
        uc.mem_write(0x4001680C, struct.pack("<I", (67 << 16) | 17))  # LTDC_BPCR: AHBP 67, AVBP 17 (#438's timing)
        uc.mem_write(STATE_AT, b"\xa5" * 0x400)  # SRAM garbage, as at power-on
        self.calls = {"render": 0, "malloc": 0}
        self.sent = []

        def on_code(uc, address, size, _):
            if address == STOCK_RENDER:
                self.calls["render"] += 1
            elif address == STOCK_MALLOC:
                self.calls["malloc"] += 1
            elif address == STOCK_SEND:
                length = uc.reg_read(A.UC_ARM_REG_R2)
                self.sent.append(bytes(uc.mem_read(uc.reg_read(A.UC_ARM_REG_R1), length)))
        uc.hook_add(unicorn.UC_HOOK_CODE, on_code)

    def call(self, entry, count=2_000_000, **regs):
        uc = self.uc
        uc.reg_write(A.UC_ARM_REG_SP, 0x10010000 - 0x100)
        uc.reg_write(A.UC_ARM_REG_LR, RETURN | 1)
        for name, value in regs.items():
            uc.reg_write(getattr(A, f"UC_ARM_REG_{name.upper()}"), value)
        self.instructions = 0
        counting = uc.hook_add(unicorn.UC_HOOK_CODE, self.count_instruction)
        uc.emu_start(entry | 1, RETURN, count=count)
        uc.hook_del(counting)
        return {name: uc.reg_read(getattr(A, f"UC_ARM_REG_{name.upper()}"))
                for name in ("r0", "r4", "r5", "r6", "r7", "r8", "r9", "r10", "r11", "sp")}

    def count_instruction(self, uc, address, size, _):
        self.instructions += 1

    def receive(self, hexbytes):
        message = bytes.fromhex(hexbytes)
        self.uc.mem_write(RX, message)
        self.uc.mem_write(RX_COUNT, struct.pack("<H", len(message)))
        return message

    def word(self, address):
        return struct.unpack("<I", self.uc.mem_read(address, 4))[0]


CALLEE_SAVED = dict(r4=0x44444444, r6=0x66666666, r9=0x99999999, r11=0xBBBBBBBB)
CAPABILITY = "F000020B7F1020000200 01F7".replace(" ", "")
BEGIN = "F000020B7F102000020101F7"
DECK_2_RED_TRACK = "F000020B7F10200009030201 7F0000000001F7".replace(" ", "")


class CommandEntryTests(unittest.TestCase):
    def command(self, chip, cmd, message_hex):
        message = chip.receive(message_hex)
        length = (message[7] << 7) | message[8]
        return chip.call(dfupatch.HOOK_COMMAND_ENTRY, r10=cmd, r7=RX, r5=length, r8=0, **CALLEE_SAVED)

    def test_another_command_gets_what_the_replaced_instruction_did_and_nothing_else(self):
        chip = Chip()
        out = self.command(chip, 0x7F, "F000020B7F107F000101F7")
        self.assertEqual(out["r8"], 1)
        self.assertEqual(out["r5"], 1)
        self.assertEqual(out["r7"], RX)
        self.assertEqual(out["sp"], 0x10010000 - 0x100)
        for reg, value in CALLEE_SAVED.items():
            self.assertEqual(out[reg], value, reg)
        self.assertEqual(chip.word(STATE_AT), 0xA5A5A5A5)  # our state untouched

    def test_without_the_marker_our_command_runs_nothing(self):
        chip = Chip(marker=False)
        out = self.command(chip, 0x20, CAPABILITY)
        self.assertEqual(out["r8"], 1)
        self.assertEqual(chip.calls["malloc"], 0)
        self.assertEqual(chip.word(STATE_AT), 0xA5A5A5A5)

    def test_a_capability_ask_is_answered_through_stocks_sender_after_one_malloc(self):
        chip = Chip()
        self.command(chip, 0x20, CAPABILITY)
        chip.call(dfupatch.HOOK_RENDER_ENTRY)
        self.assertEqual(chip.calls["malloc"], 1)
        self.assertEqual(chip.sent, [bytes.fromhex("F000020B01102000020001F7")])


class RenderEntryTests(unittest.TestCase):
    def test_it_calls_stocks_render_and_returns_zero(self):
        for marker in (True, False):
            chip = Chip(marker=marker)
            out = chip.call(dfupatch.HOOK_RENDER_ENTRY, **CALLEE_SAVED)
            self.assertEqual(chip.calls["render"], 1)
            self.assertEqual(out["r0"], 0)
            for reg, value in CALLEE_SAVED.items():
                self.assertEqual(out[reg], value, reg)

    def test_before_our_first_message_the_tick_touches_nothing(self):
        chip = Chip()
        for _ in range(3):
            chip.call(dfupatch.HOOK_RENDER_ENTRY)
        self.assertEqual(chip.word(STATE_AT), 0xA5A5A5A5)
        self.assertEqual(chip.calls["malloc"], 0)
        self.assertEqual(chip.sent, [])


def good_upper():
    """A literal block B (the C header tests' own): CRC 0x22B5DF72 is zlib's, worked out apart. Its entry is never
    called by a capability ask."""
    return struct.pack("<IIIII", 0x42574644, 1, 29, 0x22B5DF72, 0x08080015) + b"123456789"


def proven_block():
    with tempfile.TemporaryDirectory() as out:
        subprocess.run(["make", "-s", "-C", FW, "arm", f"ARM_BUILD={out}", "ARM_UPPER_PROVEN=1"], check=True,
                       capture_output=True)
        with open(os.path.join(out, "block.bin"), "rb") as f:
            return f.read()


def full_upper():
    """A good B filling all 512 KB, so the check is as long as it can ever be."""
    body = struct.pack("<I", 0x08080015) + bytes((i * 7 + 3) & 0xFF for i in range(UPPER_SIZE - 20))
    return struct.pack("<IIII", 0x42574644, 1, UPPER_SIZE, zlib.crc32(body)) + body


class UpperSwitchTests(unittest.TestCase):
    """Block A reads B only when built with the "upper flash proven" switch (#501)."""

    def test_checking_all_512_kb_at_the_ask_stays_well_under_the_apps_half_second(self):
        # Measured at 6.1M instructions for all 512 KB: at 180 MHz and about 1.3 cycles an instruction (flash wait
        # states), about 45 ms, once per boot. Today's B (about 10 KB) is about 1 ms. The app waits 0.5 s.
        chip = Chip(data=proven_block(), upper=full_upper())
        message = chip.receive(CAPABILITY)
        chip.call(dfupatch.HOOK_COMMAND_ENTRY, count=20_000_000, r10=0x20, r7=RX, r5=(message[7] << 7) | message[8],
                  r8=0)
        self.assertLess(chip.instructions, 7_500_000)
        chip.call(dfupatch.HOOK_RENDER_ENTRY)
        self.assertEqual(chip.sent, [bytes.fromhex("F000020B01102000020001F7")])

    def ask(self, chip):
        message = chip.receive(CAPABILITY)
        chip.call(dfupatch.HOOK_COMMAND_ENTRY, r10=0x20, r7=RX, r5=(message[7] << 7) | message[8], r8=0)
        chip.call(dfupatch.HOOK_RENDER_ENTRY)

    def test_flipping_the_switch_rebuilds_block_a_in_the_same_build_dir(self):
        # The README's own order: make arm, then, after the read-only checks, make arm ARM_UPPER_PROVEN=1.
        with tempfile.TemporaryDirectory() as out:
            built = []
            for proven in ("0", "1", "0"):
                subprocess.run(["make", "-s", "-C", FW, "arm", f"ARM_BUILD={out}", f"ARM_UPPER_PROVEN={proven}"],
                               check=True, capture_output=True)
                with open(os.path.join(out, "block.bin"), "rb") as f:
                    built.append(f.read())
        self.assertNotEqual(built[0], built[1], "the switch on must give a new block A")
        self.assertEqual(built[0], built[2], "and off again the old one")

    def test_with_the_switch_the_tick_touches_nothing_before_our_first_message(self):
        # A power cycle clears any crash of ours only if our code runs after our first message (#501).
        chip = Chip(data=proven_block(), upper=upper_block())
        for _ in range(3):
            chip.call(dfupatch.HOOK_RENDER_ENTRY)
        self.assertEqual(chip.upper_reads, 0)
        self.assertEqual(chip.word(STATE_AT), 0xA5A5A5A5)
        self.assertEqual(chip.uc.mem_read(WITNESS, 1), b"\x00")

    def test_without_the_switch_block_a_never_reads_the_upper_flash(self):
        chip = Chip(upper=good_upper())
        for _ in range(3):
            chip.call(dfupatch.HOOK_RENDER_ENTRY)
        self.ask(chip)
        self.assertEqual(chip.upper_reads, 0)

    def test_with_the_switch_only_a_good_block_b_gets_the_ask_answered(self):
        proven = proven_block()
        answer = bytes.fromhex("F000020B01102000020001F7")
        for upper, sent in ((None, []), (good_upper(), [answer])):
            with self.subTest(upper=upper is not None):
                chip = Chip(data=proven, upper=upper)
                self.ask(chip)
                self.assertEqual(chip.sent, sent)



def upper_block():
    with open(os.path.join(BUILD, "upper.bin"), "rb") as f:
        return f.read()


class UpperBlockTests(unittest.TestCase):
    """Block B, the drawing, built for 0x08080000 (#501): the header block A checks, worked out here apart."""

    def test_b_starts_with_a_header_block_a_will_accept(self):
        data = upper_block()
        marker, version, length, crc, draw = struct.unpack_from("<IIIII", data)
        self.assertEqual(marker, 0x42574644)
        self.assertEqual(version, 1)
        self.assertEqual(length, len(data))
        self.assertLessEqual(length, UPPER_SIZE)
        self.assertEqual(crc, zlib.crc32(data[16:]))
        out = subprocess.run(["arm-none-eabi-nm", os.path.join(BUILD, "upper.elf")], capture_output=True, text=True,
                             check=True).stdout
        names = {name: int(value, 16) for value, _, name in (line.split() for line in out.splitlines()
                                                              if line.count(" ") == 2)}
        self.assertEqual(draw & ~1, names["dfw_draw"])  # nm prints a Thumb function's address without bit 0
        self.assertEqual(draw & 1, 1, "Thumb")
        self.assertTrue(UPPER + 20 <= draw < UPPER + length)

    def test_block_a_draws_through_a_good_b_and_stays_silent_for_a_corrupted_one(self):
        proven = proven_block()
        answer = bytes.fromhex("F000020B01102000020001F7")
        corrupted = bytearray(upper_block())
        corrupted[len(corrupted) // 2] ^= 0x01
        for upper, drawn in ((upper_block(), True), (bytes(corrupted), False)):
            with self.subTest(drawn=drawn):
                chip = Chip(data=proven, upper=upper)
                for hexbytes in (CAPABILITY, BEGIN, DECK_2_RED_TRACK):
                    message = chip.receive(hexbytes)
                    chip.call(dfupatch.HOOK_COMMAND_ENTRY, count=20_000_000, r10=0x20, r7=RX,
                              r5=(message[7] << 7) | message[8], r8=0)
                chip.call(dfupatch.HOOK_RENDER_ENTRY, count=50_000_000)
                self.assertEqual(chip.sent, [answer] if drawn else [])
                layer = bytes(chip.uc.mem_read(LAYER_AT, 320 * 240 * 2))
                self.assertEqual(any(layer), drawn, "B's drawing reached the screen" if drawn else "nothing drawn")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        BUILD = sys.argv.pop(1)
    unittest.main()
