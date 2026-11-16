#!/usr/bin/env python3
"""Tests for scripts/ci_profile.py against a fake App Store Connect API. No network, no keys.
Run: python3 -I scripts/test_ci_profile.py"""
import base64, contextlib, io, os, sys, tempfile, unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ci_profile

BUNDLE = "dev.ericdahl.ControllerBridge"
NAME = "ControllerBridge CI Mac App Store"
SERIAL = "0A1B2C"


def profile(profile_id, cert="cert", state="ACTIVE", uuid="uuid-old", name=NAME):
    return {
        "id": profile_id,
        "attributes": {"name": name, "profileState": state, "uuid": uuid,
                       "profileContent": base64.b64encode(b"profile " + uuid.encode()).decode()},
        "relationships": {"certificates": {"data": [{"id": cert}]}},
    }


class FakeAPI:
    """App Store Connect in memory: one bundle ID, the distribution certificates and the CI profiles."""

    def __init__(self, profiles=(), serial=SERIAL, bundle=True):
        self.profiles = list(profiles)
        self.serial = serial
        self.bundle = bundle
        self.calls = []

    def call(self, method, path, body=None, query=None):
        self.calls.append((method, path, body))
        if method == "GET" and path == "/bundleIds":
            return {"data": [{"id": "bundle", "attributes": {"identifier": BUNDLE}}] if self.bundle else []}
        if method == "GET" and path == "/certificates":
            return {"data": [{"id": "cert", "attributes": {"serialNumber": self.serial}}]}
        if method == "GET" and path == "/profiles":
            assert query["filter[profileType]"] == "MAC_APP_STORE"
            return {"data": [p for p in self.profiles if p["attributes"]["name"] == query["filter[name]"]]}
        if method == "DELETE" and path.startswith("/profiles/"):
            self.profiles = [p for p in self.profiles if p["id"] != path.split("/")[2]]
            return {}
        if method == "POST" and path == "/profiles":
            made = profile("new", uuid="uuid-new")
            self.profiles.append(made)
            return {"data": made}
        raise AssertionError(f"unexpected call {method} {path}")


class CIProfileTests(unittest.TestCase):
    def run_script(self, api):
        """Runs ci_profile.main() with the fake API, a temporary home, and the release workflow's environment."""
        home = tempfile.mkdtemp()
        env = {"HOME": home, "BUNDLE_ID": BUNDLE, "CERT_SERIAL": "000a1b2c", "PROFILE_NAME": NAME,
               "PROFILE_TYPE": "MAC_APP_STORE", "ASC_KEY_ID": "KEY", "ASC_ISSUER_ID": "ISSUER", "ASC_KEY_PATH": "/none"}
        out = io.StringIO()
        saved_env, saved_call = dict(os.environ), ci_profile.call
        os.environ.update(env)
        ci_profile.call = api.call
        try:
            with contextlib.redirect_stdout(out):
                ci_profile.main()
        finally:
            os.environ.clear(); os.environ.update(saved_env)
            ci_profile.call = saved_call
        return out.getvalue(), home

    def installed(self, home, uuid):
        path = os.path.join(home, "Library/Developer/Xcode/UserData/Provisioning Profiles", uuid + ".provisionprofile")
        with open(path, "rb") as f:
            return f.read()

    def test_reuses_an_active_profile_for_the_certificate(self):
        api = FakeAPI(profiles=[profile("p1")])
        out, home = self.run_script(api)
        self.assertEqual(out, f"name={NAME}\nuuid=uuid-old\n")
        self.assertEqual(self.installed(home, "uuid-old"), b"profile uuid-old")
        self.assertFalse([c for c in api.calls if c[0] in ("POST", "DELETE")])

    def test_makes_a_mac_app_store_profile_when_there_is_none(self):
        api = FakeAPI()
        out, home = self.run_script(api)
        self.assertEqual(out, f"name={NAME}\nuuid=uuid-new\n")
        posts = [c[2] for c in api.calls if c[0] == "POST"]
        self.assertEqual(posts[0]["data"]["attributes"], {"name": NAME, "profileType": "MAC_APP_STORE"})
        self.assertEqual(posts[0]["data"]["relationships"]["bundleId"]["data"]["id"], "bundle")
        self.assertEqual(posts[0]["data"]["relationships"]["certificates"]["data"], [{"type": "certificates", "id": "cert"}])
        self.assertEqual(self.installed(home, "uuid-new"), b"profile uuid-new")

    def test_replaces_its_own_profile_when_it_is_invalid_or_for_another_certificate(self):
        api = FakeAPI(profiles=[profile("p1", state="INVALID"), profile("p2", cert="old-cert")])
        out, _ = self.run_script(api)
        self.assertEqual(out, f"name={NAME}\nuuid=uuid-new\n")
        deleted = sorted(c[1] for c in api.calls if c[0] == "DELETE")
        self.assertEqual(deleted, ["/profiles/p1", "/profiles/p2"])

    def test_refuses_a_certificate_app_store_connect_does_not_know(self):
        with self.assertRaises(SystemExit) as stop:
            self.run_script(FakeAPI(serial="FFFF"))
        self.assertIn("serial mismatch", str(stop.exception.code))

    def test_refuses_a_missing_bundle_id_without_registering_one(self):
        api = FakeAPI(bundle=False)
        with self.assertRaises(SystemExit) as stop:
            self.run_script(api)
        self.assertIn(f"No bundle ID {BUNDLE}", str(stop.exception.code))
        self.assertFalse([c for c in api.calls if c[0] == "POST"])


if __name__ == "__main__":
    unittest.main()
