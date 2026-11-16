#!/usr/bin/env python3
"""Tests for scripts/testflight_distribute.py against a fake App Store Connect API. No network, no keys.
Run: python3 -I scripts/test_testflight_distribute.py"""
import os, sys, unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testflight_distribute as td

BUNDLE = "dev.ericdahl.ControllerBridge"


class FakeASC:
    """App Store Connect in memory: the app, its builds, groups, localizations and review state."""

    def __init__(self, builds=None):
        # Each build is (version, build number, states the poll sees in turn).
        self.builds = builds if builds is not None else [("1.0.1", "42.1", ["VALID"])]
        self.calls = []

    def http(self, method, path, body=None, query=None):
        self.calls.append((method, path, body, query))
        if method == "GET" and path == "/apps":
            assert query["filter[bundleId]"] == BUNDLE
            return 200, {"data": [{"id": "app1", "attributes": {"bundleId": BUNDLE}}]}
        if method == "GET" and path == "/builds":
            assert query["filter[app]"] == "app1"
            assert query["filter[preReleaseVersion.platform]"] == "MAC_OS"
            found = []
            for index, (version, number, states) in enumerate(self.builds):
                if version == query["filter[preReleaseVersion.version]"] and number == query["filter[version]"]:
                    state = states.pop(0) if len(states) > 1 else states[0]
                    if state is not None:
                        found.append({"id": f"build{index}", "attributes": {"version": number, "processingState": state}})
            return 200, {"data": found}
        raise AssertionError(f"unexpected call {method} {path}")


class Recorder:
    def __init__(self):
        self.slept = []

    def sleep(self, seconds):
        self.slept.append(seconds)


class FindBuildTests(unittest.TestCase):
    def test_finds_the_build_by_version_and_build_number(self):
        api = FakeASC(builds=[("1.0.0", "41.1", ["VALID"]), ("1.0.1", "42.1", ["VALID"])])
        build = td.find_build(api.http, BUNDLE, "1.0.1", "42.1", sleep=Recorder().sleep)
        self.assertEqual(build, "build1")

    def test_matches_the_dotted_build_number_exactly(self):
        # The build number is run.attempt: 42.10 is a different build from 42.1, even if the API returns both.
        def http(method, path, body=None, query=None):
            if path == "/apps":
                return 200, {"data": [{"id": "app1", "attributes": {"bundleId": BUNDLE}}]}
            return 200, {"data": [{"id": "b10", "attributes": {"version": "42.10", "processingState": "VALID"}},
                                  {"id": "b1", "attributes": {"version": "42.1", "processingState": "VALID"}}]}
        self.assertEqual(td.find_build(http, BUNDLE, "1.0.1", "42.1", sleep=Recorder().sleep), "b1")


if __name__ == "__main__":
    unittest.main()
