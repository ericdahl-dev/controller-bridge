#!/usr/bin/env python3
"""Tests for wifi_secrets.py, the deck panel's PlatformIO pre-script (#620): runs it with a stand-in for PlatformIO's
env against made-up ini files. Run: python3 -I tools/deck-panel/test_wifi_secrets.py"""
import contextlib, io, os, stat, sys, tempfile, unittest

sys.dont_write_bytecode = True
SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wifi_secrets.py")


class FakeEnv:
    def __init__(self, src):
        self.src = src

    def subst(self, name):
        assert name == "$PROJECT_SRC_DIR", name
        return self.src


def run(ini_text=None, root=None):
    """Runs the script in a temp project (or `root`); returns (header text, header mode, what it printed)."""
    root = root or tempfile.mkdtemp()
    src = os.path.join(root, "src")
    os.makedirs(src, exist_ok=True)
    ini = os.path.join(root, "panel-wifi.ini")
    if ini_text is not None:
        with open(ini, "w") as f:
            f.write(ini_text)
    out = io.StringIO()
    old = os.environ.get("DECK_PANEL_WIFI_INI")
    os.environ["DECK_PANEL_WIFI_INI"] = ini
    try:
        with contextlib.redirect_stdout(out), open(SCRIPT) as f:
            exec(compile(f.read(), SCRIPT, "exec"), {"Import": lambda _: None, "env": FakeEnv(src)})
    finally:
        if old is None:
            del os.environ["DECK_PANEL_WIFI_INI"]
        else:
            os.environ["DECK_PANEL_WIFI_INI"] = old
    header = os.path.join(src, "wifi_secrets.h")
    with open(header) as f:
        return f.read(), stat.S_IMODE(os.stat(header).st_mode), out.getvalue()


class WifiSecretsTests(unittest.TestCase):
    def test_no_file_gives_empty_credentials_and_says_none(self):
        text, _, printed = run(None)
        self.assertIn('#define DECK_PANEL_WIFI_SSID ""', text)
        self.assertIn('#define DECK_PANEL_WIFI_PASSWORD ""', text)
        self.assertIn("none", printed)

    def test_a_file_sets_both_and_prints_only_set(self):
        text, mode, printed = run("[wifi]\nssid = home net\npassword = pa\"ss\\word\n")
        self.assertIn('#define DECK_PANEL_WIFI_SSID "home net"', text)
        self.assertIn('#define DECK_PANEL_WIFI_PASSWORD "pa\\"ss\\\\word"', text)
        self.assertEqual(mode, 0o600)
        self.assertNotIn("home", printed)
        self.assertNotIn("pa", printed.replace("wifi_secrets", ""))
        self.assertIn("set", printed)

    def test_non_ascii_is_octal_escaped(self):
        text, _, _ = run("[wifi]\nssid = café\npassword = x\n")
        self.assertIn('"caf\\303\\251"', text)

    def test_the_same_credentials_leave_the_header_alone(self):
        # A rewrite would recompile wifi_link.cpp on every build.
        root = tempfile.mkdtemp()
        header = os.path.join(root, "src", "wifi_secrets.h")
        run("[wifi]\nssid = a\npassword = b\n", root)
        first = os.stat(header).st_mtime_ns
        os.utime(header, ns=(first - 10**9, first - 10**9))
        run("[wifi]\nssid = a\npassword = b\n", root)
        self.assertEqual(os.stat(header).st_mtime_ns, first - 10**9)
        run("[wifi]\nssid = a\npassword = c\n", root)
        self.assertNotEqual(os.stat(header).st_mtime_ns, first - 10**9)


if __name__ == "__main__":
    unittest.main()
