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
        self.localizations = {}  # locale -> (id, whatsNew)
        self.groups = {"Internal": "g-int", "Syndicate": "g-ext", "Syndicate Friends": "g-other"}
        self.in_group = set()
        self.group_conflict = False
        self.review_detail = {"contactFirstName": "A", "contactLastName": "B", "contactPhone": "+1 555 0100",
                              "contactEmail": "beta@example.com"}
        self.app_localizations = [{"locale": "en-US", "description": "A bridge.", "feedbackEmail": "beta@example.com"}]
        self.submission = None
        self.submit_reply = None  # (status, body) to answer the POST with, instead of creating one

    def http(self, method, path, body=None, query=None):
        self.calls.append((method, path, body, query))
        if method == "GET" and path == "/apps/app1/betaAppReviewDetail":
            return 200, {"data": {"id": "app1", "attributes": self.review_detail}}
        if method == "GET" and path == "/apps/app1/betaAppLocalizations":
            return 200, {"data": [{"id": f"al{i}", "attributes": a} for i, a in enumerate(self.app_localizations)]}
        if method == "GET" and path == "/builds/build1/betaAppReviewSubmission":
            return 200, {"data": self.submission}
        if method == "POST" and path == "/betaAppReviewSubmissions":
            assert body == {"data": {"type": "betaAppReviewSubmissions",
                                     "relationships": {"build": {"data": {"type": "builds", "id": "build1"}}}}}
            if self.submit_reply:
                return self.submit_reply
            self.submission = {"id": "sub1", "attributes": {"betaReviewState": "WAITING_FOR_REVIEW"}}
            return 201, {"data": self.submission}
        if method == "GET" and path == "/betaGroups":
            assert query["filter[app]"] == "app1"
            # The API's name filter matches partly, as App Store Connect's does.
            return 200, {"data": [{"id": gid, "attributes": {"name": name}}
                                  for name, gid in self.groups.items() if query["filter[name]"] in name]}
        if method == "POST" and path.startswith("/betaGroups/") and path.endswith("/relationships/builds"):
            gid = path.split("/")[2]
            assert body == {"data": [{"type": "builds", "id": "build1"}]}
            if self.group_conflict:
                return 409, {"errors": [{"code": "ENTITY_ERROR", "detail": "The build is already in the group."}]}
            self.in_group.add(gid)
            return 204, {}
        if method == "GET" and path == "/builds/build1/betaBuildLocalizations":
            return 200, {"data": [{"id": lid, "attributes": {"locale": locale, "whatsNew": text}}
                                  for locale, (lid, text) in self.localizations.items()]}
        if method == "POST" and path == "/betaBuildLocalizations":
            attributes = body["data"]["attributes"]
            assert body["data"]["relationships"]["build"]["data"] == {"type": "builds", "id": "build1"}
            self.localizations[attributes["locale"]] = ("loc-new", attributes["whatsNew"])
            return 201, {"data": {"id": "loc-new"}}
        if method == "PATCH" and path.startswith("/betaBuildLocalizations/"):
            lid = path.split("/")[2]
            locale = next(k for k, (i, _) in self.localizations.items() if i == lid)
            assert body["data"] == {"type": "betaBuildLocalizations", "id": lid, "attributes": body["data"]["attributes"]}
            self.localizations[locale] = (lid, body["data"]["attributes"]["whatsNew"])
            return 200, {"data": {"id": lid}}
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


class ProcessingPollTests(unittest.TestCase):
    def test_waits_while_the_build_is_missing_then_processing(self):
        # Right after the upload the build isn't listed yet, then it processes, then it's valid.
        api = FakeASC(builds=[("1.0.1", "42.1", [None, "PROCESSING", "PROCESSING", "VALID"])])
        clock = Recorder()
        self.assertEqual(td.find_build(api.http, BUNDLE, "1.0.1", "42.1", sleep=clock.sleep), "build0")
        self.assertEqual(clock.slept, [td.POLL_SECONDS] * 3)

    def test_a_failed_or_invalid_build_stops_with_its_state(self):
        for state in ("FAILED", "INVALID"):
            api = FakeASC(builds=[("1.0.1", "42.1", ["PROCESSING", state])])
            with self.assertRaisesRegex(td.DistributeError, state):
                td.find_build(api.http, BUNDLE, "1.0.1", "42.1", sleep=Recorder().sleep)

    def test_gives_up_after_the_timeout(self):
        api = FakeASC(builds=[("1.0.1", "42.1", ["PROCESSING"])])
        clock = Recorder()
        with self.assertRaisesRegex(td.DistributeError, "still PROCESSING"):
            td.find_build(api.http, BUNDLE, "1.0.1", "42.1", sleep=clock.sleep, timeout=300)
        self.assertEqual(sum(clock.slept), 300)


DOC = """# TestFlight: What to test

Paste this into the build's "What to Test".

---

DeckBridge 1.0.1 has a new look.

- Try Settings.
"""


class WhatToTestTests(unittest.TestCase):
    def test_the_text_is_everything_after_the_rule(self):
        self.assertEqual(td.what_to_test(DOC), "DeckBridge 1.0.1 has a new look.\n\n- Try Settings.")

    def test_creates_the_en_us_text_when_the_build_has_none(self):
        api = FakeASC()
        td.set_what_to_test(api.http, "build1", "New look.")
        self.assertEqual(api.localizations, {"en-US": ("loc-new", "New look.")})

    def test_updates_the_text_on_a_rerun(self):
        api = FakeASC()
        api.localizations = {"en-US": ("loc1", "Old text.")}
        td.set_what_to_test(api.http, "build1", "New look.")
        self.assertEqual(api.localizations, {"en-US": ("loc1", "New look.")})
        self.assertFalse([c for c in api.calls if c[0] == "POST"])


class GroupTests(unittest.TestCase):
    def test_adds_the_build_to_each_group_found_by_its_exact_name(self):
        api = FakeASC()
        td.add_to_group(api.http, "app1", "build1", "Syndicate")
        td.add_to_group(api.http, "app1", "build1", "Internal")
        self.assertEqual(api.in_group, {"g-ext", "g-int"})

    def test_a_missing_group_names_itself(self):
        api = FakeASC()
        with self.assertRaisesRegex(td.DistributeError, "No beta group named \"Testers\""):
            td.add_to_group(api.http, "app1", "build1", "Testers")

    def test_a_build_already_in_the_group_is_fine(self):
        api = FakeASC()
        api.group_conflict = True
        td.add_to_group(api.http, "app1", "build1", "Internal")


class ReviewTests(unittest.TestCase):
    def posts(self, api):
        return [c for c in api.calls if c[0] == "POST" and c[1] == "/betaAppReviewSubmissions"]

    def test_submits_the_build_for_beta_app_review(self):
        api = FakeASC()
        td.submit_for_review(api.http, "app1", "build1")
        self.assertEqual(api.submission["attributes"]["betaReviewState"], "WAITING_FOR_REVIEW")
        self.assertEqual(len(self.posts(api)), 1)

    def test_a_build_already_submitted_is_not_submitted_again(self):
        api = FakeASC()
        api.submission = {"id": "sub0", "attributes": {"betaReviewState": "IN_REVIEW"}}
        td.submit_for_review(api.http, "app1", "build1")
        self.assertEqual(self.posts(api), [])

    def test_a_conflict_saying_already_submitted_counts_as_done(self):
        api = FakeASC()
        api.submit_reply = (409, {"errors": [{"code": "ENTITY_ERROR.STATE_ERROR", "detail": "Build already submitted for review."}]})
        td.submit_for_review(api.http, "app1", "build1")

    def test_missing_contact_details_stop_before_submitting_and_say_what_to_fill_in(self):
        api = FakeASC()
        api.review_detail = dict(api.review_detail, contactPhone=None)
        with self.assertRaisesRegex(td.TestInformationMissing, "Test Information"):
            td.submit_for_review(api.http, "app1", "build1")
        self.assertEqual(self.posts(api), [])

    def test_a_missing_beta_description_or_feedback_email_stops_too(self):
        api = FakeASC()
        api.app_localizations = [{"locale": "en-US", "description": "", "feedbackEmail": "beta@example.com"}]
        with self.assertRaisesRegex(td.TestInformationMissing, "Beta App Description"):
            td.submit_for_review(api.http, "app1", "build1")

    def test_an_api_error_about_the_review_details_gets_the_same_message(self):
        api = FakeASC()
        api.submit_reply = (422, {"errors": [{"code": "ENTITY_ERROR.RELATIONSHIP.INVALID",
                                              "detail": "Beta App Review Information is missing a contact email."}]})
        with self.assertRaisesRegex(td.TestInformationMissing, "Test Information"):
            td.submit_for_review(api.http, "app1", "build1")


if __name__ == "__main__":
    unittest.main()
