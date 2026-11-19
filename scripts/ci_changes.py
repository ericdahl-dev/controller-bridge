#!/usr/bin/env python3
"""Says whether CI's Mac jobs (Kit tests, App build) need to run for a change.
Reads the changed paths, one per line, on stdin; prints mac=true or mac=false for $GITHUB_OUTPUT.
Tested by scripts/test_ci_changes.py."""
import fnmatch, sys

# Changes only the Linux jobs check (Site check, spelling): the website, its scripts, Markdown docs and their check,
# and the LC6000 firmware tool.
# Anything else, including .github/ and the release scripts the Kit job tests, runs the Mac jobs too.
SITE_ONLY = ["website/*", "scripts/check_site.py", "scripts/test_check_site.py", "scripts/site-preview.sh",
             "scripts/test_*.mjs", "*.md",
             # the domain docs' check (GLOSSARY.md, docs/adr), which the Site check job runs
             "scripts/check_domain_docs.py", "scripts/test_check_domain_docs.py",
             # the LC6000 firmware patch tool (#430) and its tests, which the Site check job runs
             "tools/lc6000-firmware/*",
             # the drawn display firmware (#457) and its tests, which the Display firmware job runs
             "tools/lc6000-display-fw/*"]
# Inside those, paths the Mac jobs also test: the shared message vectors (#456), walked by the Kit tests too, and the
# drawn display's reference images (#464), which the Kit tests check against the Swift renderer.
ALSO_MAC = ["tools/lc6000-display-fw/vectors/*", "tools/lc6000-display-fw/test/ref/*"]


def site_only(path):
    if any(fnmatch.fnmatchcase(path, pattern) for pattern in ALSO_MAC):
        return False
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
