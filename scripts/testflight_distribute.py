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


if __name__ == "__main__":
    sys.exit("run from the release workflow")
