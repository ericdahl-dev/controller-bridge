#!/usr/bin/env python3
"""Distributes an uploaded TestFlight build, for the release workflow (#180).

Waits for the build to finish processing, sets its What to Test from docs/TESTFLIGHT.md, adds it to the beta groups
by name, and submits it for Beta App Review. Every step is safe to run again. Uses the App Store Connect API with the
key the upload uses (Python standard library plus `openssl`, as ci_profile.py does). Never prints the key or a token.
Tested by scripts/test_testflight_distribute.py, through an injected HTTP layer: http(method, path, body, query)
returns (status, json).
"""
import sys

PLATFORM = "MAC_OS"
# App Store Connect usually processes a Mac build in 5 to 30 minutes.
POLL_SECONDS = 30
PROCESSING_TIMEOUT = 60 * 60


class DistributeError(Exception):
    """A step that can't go on, with what to do about it."""


class TestInformationMissing(DistributeError):
    """External testing needs the app's Test Information, a one-time step for the account holder in App Store
    Connect: it holds their contact details, so this script never fills it in."""

    def __init__(self, missing):
        super().__init__(
            f"External testing needs Test Information in App Store Connect ({missing}). Fill it in once under "
            "TestFlight > Test Information (Beta App Description, Feedback Email, and Beta App Review contact "
            "details), then re-run this workflow with workflow_dispatch for this version and build.")


def send(http, method, path, body):
    status, response = http(method, path, body, None)
    if status >= 400:
        raise DistributeError(f"App Store Connect said {status} for {method} {path}: {detail(response)}")
    return response


def get(http, path, query=None):
    status, body = http("GET", path, None, query)
    if status >= 400:
        raise DistributeError(f"App Store Connect said {status} for GET {path}: {detail(body)}")
    return body


def detail(body):
    """The API's error details, never anything from the request."""
    errors = (body or {}).get("errors") or []
    return "; ".join(f"{e.get('code', '')} {e.get('detail', '')}".strip() for e in errors) or "no detail"


def find_app(http, bundle_id):
    apps = get(http, "/apps", {"filter[bundleId]": bundle_id})["data"]
    app = next((a for a in apps if a["attributes"]["bundleId"] == bundle_id), None)
    if app is None:
        raise DistributeError(f"No app with bundle ID {bundle_id} in App Store Connect.")
    return app["id"]


def find_build(http, bundle_id, version, build_number, sleep, timeout=PROCESSING_TIMEOUT):
    """The build's id once it has processed, by marketing version and build number (matched exactly: "42.1" is run
    42, attempt 1). A build not listed yet counts as still processing: it appears a little after the upload."""
    app = find_app(http, bundle_id)
    query = {"filter[app]": app, "filter[preReleaseVersion.version]": version,
             "filter[version]": build_number, "filter[preReleaseVersion.platform]": PLATFORM}
    waited, state = 0, "not listed yet"
    while True:
        builds = get(http, "/builds", query)["data"]
        build = next((b for b in builds if b["attributes"]["version"] == build_number), None)
        state = build["attributes"]["processingState"] if build else "not listed yet"
        if state == "VALID":
            print(f"Build {version} ({build_number}) has processed.")
            return build["id"]
        if state in ("FAILED", "INVALID"):
            raise DistributeError(f"Build {version} ({build_number}) is {state} in App Store Connect; it can't be distributed.")
        if waited >= timeout:
            raise DistributeError(f"Build {version} ({build_number}) is still {state} after {waited // 60} minutes.")
        print(f"Build {version} ({build_number}): {state}, waiting {POLL_SECONDS} s.")
        sleep(POLL_SECONDS)
        waited += POLL_SECONDS


def what_to_test(doc):
    """The What to Test text: everything after the doc's first "---" rule."""
    _, _, text = doc.partition("\n---\n")
    return text.strip()


def set_what_to_test(http, build, text, locale="en-US"):
    """Sets the build's What to Test, creating its localization or updating it, so a rerun writes the same text."""
    existing = get(http, f"/builds/{build}/betaBuildLocalizations")["data"]
    localization = next((l for l in existing if l["attributes"]["locale"] == locale), None)
    if localization:
        send(http, "PATCH", f"/betaBuildLocalizations/{localization['id']}", {"data": {
            "type": "betaBuildLocalizations", "id": localization["id"], "attributes": {"whatsNew": text}}})
    else:
        send(http, "POST", "/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build}}}}})
    print(f"What to Test set ({locale}, {len(text)} characters).")


def add_to_group(http, app, build, name):
    """Adds the build to the beta group with exactly this name. Already in it (409) is fine: reruns are safe."""
    groups = get(http, "/betaGroups", {"filter[app]": app, "filter[name]": name})["data"]
    group = next((g for g in groups if g["attributes"]["name"] == name), None)
    if group is None:
        raise DistributeError(f'No beta group named "{name}" for this app in App Store Connect.')
    status, response = http("POST", f"/betaGroups/{group['id']}/relationships/builds",
                             {"data": [{"type": "builds", "id": build}]}, None)
    if status == 409:
        print(f'Already in "{name}".')
    elif status >= 400:
        raise DistributeError(f'Couldn\'t add the build to "{name}": {status} {detail(response)}')
    else:
        print(f'Added to "{name}".')


REVIEW_CONTACT = {"contactFirstName": "first name", "contactLastName": "last name", "contactPhone": "phone",
                  "contactEmail": "email"}


def check_test_information(http, app, locale="en-US"):
    """External review needs the beta description and feedback email, and the review contact. Checked first, so
    a missing one says what to fill in instead of failing on the submission."""
    contact = get(http, f"/apps/{app}/betaAppReviewDetail")["data"]["attributes"]
    missing = [label for key, label in REVIEW_CONTACT.items() if not contact.get(key)]
    if missing:
        raise TestInformationMissing("Beta App Review contact " + ", ".join(missing))
    localizations = [l["attributes"] for l in get(http, f"/apps/{app}/betaAppLocalizations")["data"]]
    localization = next((l for l in localizations if l.get("locale") == locale), {})
    if not localization.get("description"):
        raise TestInformationMissing(f"Beta App Description, {locale}")
    if not localization.get("feedbackEmail"):
        raise TestInformationMissing(f"Feedback Email, {locale}")


def submit_for_review(http, app, build):
    """Submits the build for Beta App Review, once. Already submitted, by an earlier run or by hand, is done."""
    check_test_information(http, app)
    existing = get(http, f"/builds/{build}/betaAppReviewSubmission")["data"]
    if existing:
        print(f"Already submitted for Beta App Review ({existing['attributes'].get('betaReviewState', 'submitted')}).")
        return
    status, response = http("POST", "/betaAppReviewSubmissions", {"data": {
        "type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": build}}}}}, None)
    if status < 400:
        print("Submitted for Beta App Review.")
        return
    text = detail(response)
    if "review information" in text.lower() or "contact" in text.lower() or "test information" in text.lower():
        raise TestInformationMissing(text)
    if status == 409 and "already" in text.lower():
        print("Already submitted for Beta App Review.")
        return
    raise DistributeError(f"Couldn't submit for Beta App Review: {status} {text}")


if __name__ == "__main__":
    sys.exit("run from the release workflow")
