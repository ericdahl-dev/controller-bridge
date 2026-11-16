#!/usr/bin/env python3
"""Says whether CI's Mac jobs (Kit tests, App build) need to run for a change.
Reads the changed paths, one per line, on stdin; prints mac=true or mac=false for $GITHUB_OUTPUT.
Tested by scripts/test_ci_changes.py."""
import fnmatch, sys

# Changes only the Linux jobs check (Site check, spelling): the website, its scripts, and Markdown docs.
# Anything else, including .github/ and the release scripts the Kit job tests, runs the Mac jobs too.
SITE_ONLY = ["website/*", "scripts/check_site.py", "scripts/test_check_site.py", "scripts/site-preview.sh",
             "scripts/test_*.mjs", "*.md"]


def site_only(path):
    return not path.startswith(".github/") and any(fnmatch.fnmatchcase(path, pattern) for pattern in SITE_ONLY)


def needs_mac(paths):
    if not paths:
        return True  # an unknown change: run everything
    return not all(site_only(path) for path in paths)


def main():
    paths = [line.strip() for line in sys.stdin if line.strip()]
    print(f"mac={'true' if needs_mac(paths) else 'false'}")


if __name__ == "__main__":
    main()
